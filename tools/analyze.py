#!/usr/bin/env python3
"""슬라임 실험실 오프라인 분석 도구 (앱 실행에는 쓰지 않는다).

헤드리스 실행기(tests/run_experiment.gd)를 씨앗·파라미터별로 여러 번 돌리고, 결과 폴더들을 모아
표(summary.csv·cells.csv)·보고서(report.md)·그림(PNG)을 만든다.

  python3 tools/analyze.py run    --seeds 1-8 --generations 100 --preset fast_civ --out results/batch
  python3 tools/analyze.py sweep  --param mutation.rate=0.02,0.1 --seeds 1-4 --generations 50 --out results/sweep
  python3 tools/analyze.py report results/batch [--out 보고서폴더]

필요: Python 3.9 이상, numpy, pandas. matplotlib 은 선택(없으면 그림만 건너뛴다).
PyTorch 는 쓰지 않는다(이유는 docs/ANALYSIS.md). 자세한 사용법도 docs/ANALYSIS.md.
"""
from __future__ import annotations

import argparse
import csv
import itertools
import json
import math
import os
import re
import shlex
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd

# ── 고정 이름(시뮬레이션 쪽과 같아야 하는 것) ──

## 헤드리스 실행기 스크립트
RUNNER_SCRIPT = "res://tests/run_experiment.gd"
## scripts/sim/sim_recorder.gd 의 TIMESERIES_COLUMNS 와 같은 순서
TIMESERIES_COLUMNS = [
    "tick", "day", "season", "light", "population", "births", "deaths", "mean_gen", "mean_energy",
    "mean_size", "mean_sense", "mean_age", "food_total", "dropped_total", "stored_total", "carry_total",
    "civ_stage", "storehouses", "farms", "forage_attempts", "store_drops", "farm_sprouts",
]
## scripts/sim/sim_recorder.gd 의 CHRONICLE_COLUMNS
CHRONICLE_COLUMNS = ["tick", "mean_gen", "kind", "actor_id", "text"]
## SimWorld.STAGE_NAMES (0 없음 1 채집 2 저장 3 농사)
STAGE_NAMES_KO = ["없음", "채집", "저장", "농사"]
STAGE_NAMES_EN = ["none", "forage", "store", "farm"]
## 발견 단계: (단계 번호, 열 이름 꼬리, 연대기·summary.json 의 한국어 이름)
STAGES = [(1, "forage", "채집"), (2, "store", "저장"), (3, "farm", "농사")]
## summary.json 의 끝난 이유 → 보고서 표기
END_REASON_KO = {"generations": "세대 도달", "extinction": "멸종", "max_ticks": "틱 상한"}

## summary.csv 열(이 순서로 쓴다)
SUMMARY_COLUMNS = [
    "cell", "seed", "preset", "overrides", "generations_target", "end_reason", "ticks", "mean_generation",
    "population", "peak_population", "births", "deaths", "civ_stage", "civ_stage_name", "extinct_tick",
    "storehouses", "farms",
    "disc_tick_forage", "disc_gen_forage", "disc_tick_store", "disc_gen_store", "disc_tick_farm", "disc_gen_farm",
    "final_mean_size", "final_mean_sense", "run_seconds", "history_hash", "path",
]
## 정수로 써야 하는 summary.csv 열
SUMMARY_INT_COLUMNS = [
    "seed", "ticks", "population", "peak_population", "births", "deaths", "civ_stage", "extinct_tick",
    "storehouses", "farms", "disc_tick_forage", "disc_tick_store", "disc_tick_farm",
]
## runs.csv 열
RUNS_COLUMNS = ["cell", "seed", "status", "exit_code", "wall_seconds", "result", "out_dir", "command"]
## CSV 실수 형식(입력이 소수 6자리 이하라 10자리 유효숫자면 그대로 왕복)
FLOAT_FORMAT = "%.10g"
## 묶음 하나를 대표하는 루트 폴더 이름(run 결과처럼 씨앗 폴더가 바로 아래에 있을 때)
ROOT_CELL = "."

# ── 그림 모양(색은 범주 팔레트를 고정 순서로, 바탕·글자·격자는 차분한 회색) ──

## 범주 색 8개(고정 순서). 묶음이 이보다 많으면 색을 돌려쓰지 않고 작은 그림 여러 장(패싯)으로 나눈다.
PALETTE = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948"]
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_2 = "#52514e"
MUTED = "#898781"
GRID = "#e1e0d9"
AXIS = "#c3c2b7"
## 그림 해상도(문서에 넣을 크기를 생각해 낮게)
DPI = 110
## 패싯 한 줄의 칸 수
FACET_COLS = 4
## 그림 위 제목·부제 자리(인치)
TITLE_IN = 0.62
## 발견 세대 그림: 오른쪽 끝 "도달/전체" 글자 자리(가로 범위에 대한 비율)
DISC_RIGHT_PAD = 0.22
## 문명 단계 그림: 실행마다 띄우는 폭의 합(단계 간격 1 에 대한 비율)
CIV_SPREAD = 0.36
## 특성 그림의 최소 세로 범위(거의 변하지 않을 때 잡음을 확대하지 않게)
TRAIT_MIN_SPAN = {"mean_size": 0.2, "mean_sense": 1.0}
## 한글 글꼴(프로젝트 기본 글꼴, OFL)
FONT_FILES = ["assets/fonts/NanumGothic-Regular.ttf", "assets/fonts/NanumGothic-Bold.ttf"]

## 그림·보고서 문구(한글 글꼴이 없으면 영어)
TEXT = {
    "ko": {
        "tick": "틱", "mean_gen": "평균 세대", "population": "개체 수", "mean_size": "평균 크기",
        "mean_sense": "평균 감지 반경", "civ_stage": "문명 단계", "disc_gen": "발견 세대(평균 세대)",
        "stages": STAGE_NAMES_KO,
        "t_population": "개체 수 — 실행마다 한 선",
        "t_mean_gen": "평균 세대 — 실행마다 한 선",
        "t_traits": "특성 변화 — 평균 세대에 따른 평균 크기·감지 반경",
        "t_traits_one": "특성 변화",
        "t_civ": "문명 단계 — 평균 세대에 따른 계단(실행마다 조금씩 띄움)",
        "t_disc": "발견 세대 — 단계·묶음별 (점 = 실행, 상자 = 사분위 범위, 굵은 선 = 중앙값)",
        "runs_cells": "묶음 {c}개 · 실행 {r}개",
        "none_reached": "도달한 실행 없음",
        "extinct": "멸종",
    },
    "en": {
        "tick": "tick", "mean_gen": "mean generation", "population": "population", "mean_size": "mean size",
        "mean_sense": "mean sense radius", "civ_stage": "civilization stage", "disc_gen": "discovery generation",
        "stages": STAGE_NAMES_EN,
        "t_population": "Population — one line per run",
        "t_mean_gen": "Mean generation — one line per run",
        "t_traits": "Traits — mean size and sense radius vs. mean generation",
        "t_traits_one": "Traits",
        "t_civ": "Civilization stage vs. mean generation (runs slightly offset)",
        "t_disc": "Discovery generation by stage and cell (dot = run, box = IQR, bar = median)",
        "runs_cells": "{c} cells · {r} runs",
        "none_reached": "no run reached",
        "extinct": "extinct",
    },
}


# ── 인자 해석 ──

def parse_seeds(text: str) -> list[int]:
    """씨앗 목록 해석: "1-8", "1,3,5", "1-3,7". 겹치는 것은 한 번만, 오름차순."""
    out: set[int] = set()
    for part in str(text).split(","):
        part = part.strip()
        if part == "":
            continue
        m = re.fullmatch(r"(\d+)\s*-\s*(\d+)", part)
        if m:
            a, b = int(m.group(1)), int(m.group(2))
            if b < a:
                raise ValueError(f"씨앗 범위가 거꾸로입니다: {part}")
            out.update(range(a, b + 1))
        elif re.fullmatch(r"\d+", part):
            out.add(int(part))
        else:
            raise ValueError(f"씨앗은 0 이상의 정수·범위(1-8)·쉼표 목록이어야 합니다: {part}")
    if not out:
        raise ValueError("씨앗이 하나도 없습니다")
    return sorted(out)


def parse_set(text: str) -> tuple[str, str]:
    """--set 키=값 → (키, 값). 값은 실행기(SimConfig.parse_value)가 해석하므로 글자 그대로 둔다."""
    key, eq, value = str(text).partition("=")
    key = key.strip()
    if eq == "" or key == "" or value == "":
        raise ValueError(f"키=값 형식이어야 합니다: {text}")
    return key, value


def split_top_level(value: str) -> list[str]:
    """쉼표로 나누되 괄호([]·{}) 안의 쉼표는 나누지 않는다: "[1,1,0.5,0],[1,1,1,1]" → ["[1,1,0.5,0]", "[1,1,1,1]"].
    괄호가 맞지 않으면 ValueError."""
    parts: list[str] = []
    cur: list[str] = []
    pairs = {"]": "[", "}": "{"}
    stack: list[str] = []
    for ch in value:
        if ch in "[{":
            stack.append(ch)
        elif ch in "]}":
            if not stack or stack[-1] != pairs[ch]:
                raise ValueError(f"괄호가 맞지 않습니다: {value}")
            stack.pop()
        if ch == "," and not stack:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if stack:
        raise ValueError(f"괄호가 닫히지 않았습니다: {value}")
    parts.append("".join(cur))
    return parts


def parse_param(text: str) -> tuple[str, list[str]]:
    """--param 키=값1,값2 → (키, [값...]). 같은 값 반복은 한 번만(순서 유지).
    배열 값도 된다: seasons.growth=[1,1,0.5,0],[1,1,1,1] (괄호 안 쉼표는 나누지 않음, 배열·사전은 JSON 이어야 함)."""
    key, value = parse_set(text)
    values: list[str] = []
    for v in split_top_level(value):
        v = v.strip()
        if v == "":
            raise ValueError(f"빈 값이 있습니다: {text}")
        if v[:1] in "[{":
            try:
                json.loads(v)
            except ValueError:
                raise ValueError(f"배열·사전 값은 JSON 이어야 합니다: {v}")
        if v not in values:
            values.append(v)
    return key, values


def build_grid(params: list[tuple[str, list[str]]]) -> list[tuple[str, list[tuple[str, str]]]]:
    """--param 들의 전체 격자. [(묶음 폴더 이름, [(키, 값)...])] — 주어진 키 순서, 값 순서대로."""
    keys = [k for k, _ in params]
    if len(set(keys)) != len(keys):
        raise ValueError("같은 키를 --param 으로 두 번 줄 수 없습니다")
    cells = []
    for combo in itertools.product(*[vals for _, vals in params]):
        pairs = list(zip(keys, combo))
        cells.append((cell_dirname(pairs), pairs))
    return cells


def cell_dirname(pairs: list[tuple[str, str]]) -> str:
    """묶음 폴더 이름: "키=값__키=값". 파일 이름에 못 쓰는 글자는 _ 로."""
    def safe(s: str) -> str:
        return re.sub(r"[^0-9A-Za-z._+\-=]", "_", s)
    return "__".join(f"{safe(k)}={safe(v)}" for k, v in pairs)


def _positive_number(text: str) -> str:
    """--generations: 양수인지만 확인하고 글자는 그대로 실행기에 넘긴다."""
    try:
        v = float(text)
    except ValueError:
        raise argparse.ArgumentTypeError(f"수여야 합니다: {text}")
    if not math.isfinite(v) or v <= 0:
        raise argparse.ArgumentTypeError(f"0 보다 커야 합니다: {text}")
    return str(text).strip()


def _arg_type(fn):
    """ValueError 를 argparse 오류로 바꾸는 감싸개."""
    def wrapped(text: str):
        try:
            return fn(text)
        except ValueError as e:
            raise argparse.ArgumentTypeError(str(e))
    wrapped.__name__ = fn.__name__
    return wrapped


def natural_key(s: str) -> tuple:
    """사람이 기대하는 순서: "rate=0.02" < "rate=0.1" < "rate=1.5" (숫자 덩어리는 수로 비교).
    '-' 는 글자 맨 앞이나 '=' 바로 뒤에서만 음수 부호로 본다("rate=-0.5" < "rate=0.1", 그러나 "trial-2" < "trial-10")."""
    parts = re.split(r"((?:(?<![^=])-)?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)", str(s))
    key = []
    for p in parts:
        if p == "":
            continue
        try:
            key.append((0, float(p), ""))
        except ValueError:
            key.append((1, 0.0, p))
    return tuple(key)


# ── 실행(run·sweep) ──

@dataclass
class Job:
    """실행기 한 번: 묶음·씨앗·결과 폴더·명령줄, 그리고 이어 돌리기 때 맞춰 볼 요청 설정."""
    cell: str
    seed: int
    out_dir: Path
    cmd: list[str] = field(default_factory=list)
    preset: str = ""
    generations: str = ""
    sets: list[tuple[str, str]] = field(default_factory=list)
    max_ticks: int | None = None


def _same_value(text: str, v) -> bool:
    """명령줄 글자 값과 summary.json 에 기록된 값이 같은가("0.10" = 0.1, "[1,1,0.5,0]" = [1.0, 1.0, 0.5, 0.0])."""
    try:
        parsed = json.loads(text)
    except (TypeError, ValueError):
        parsed = text  # 따옴표 없는 문자열 값(예: sample)
    if isinstance(parsed, (int, float)) and isinstance(v, (int, float)) and not isinstance(v, bool):
        return float(parsed) == float(v)
    return parsed == v


def existing_mismatch(job: Job) -> str:
    """이미 있는 결과(summary.json)가 이번 요청과 설정이 다르면 차이를 설명하는 문장, 같으면 ""."""
    try:
        s = json.loads((job.out_dir / "summary.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "summary.json 을 읽을 수 없음"
    diffs = []
    if job.preset and str(s.get("preset", "")) != job.preset:
        diffs.append(f"preset {s.get('preset')} ≠ {job.preset}")
    if job.generations and not _same_value(job.generations, s.get("generations_target")):
        diffs.append(f"generations {s.get('generations_target')} ≠ {job.generations}")
    want = dict(job.sets)  # 같은 키는 뒤의 값(실행기와 같은 규칙)
    have = s.get("overrides", {}) or {}
    for k in sorted(set(want) | set(have)):
        if k not in want or k not in have or not _same_value(want[k], have[k]):
            diffs.append(f"{k} {_json_scalar(have[k]) if k in have else '없음'} ≠ {want.get(k, '없음')}")
    # 틱 상한: 실행기가 summary.json 에 실제로 쓴 상한(max_ticks)과 이번 요청(--max-ticks, 없으면 설정의 run.max_ticks).
    # 예전 결과(max_ticks 기록 없음)는 설정값으로 본다. 다르면 잘린 실행이 섞이므로 mismatch.
    cfg_cap = ((s.get("config", {}) or {}).get("run", {}) or {}).get("max_ticks")
    have_cap = s.get("max_ticks", cfg_cap)
    want_cap = job.max_ticks if job.max_ticks is not None and job.max_ticks > 0 else cfg_cap
    if have_cap is not None and want_cap is not None and float(have_cap) != float(want_cap):
        diffs.append(f"max_ticks {_json_scalar(have_cap)} ≠ {_json_scalar(want_cap)}")
    return ", ".join(diffs)


def default_repo() -> Path:
    """기본 저장소 위치 = tools/ 의 부모."""
    return Path(__file__).resolve().parent.parent


def build_command(godot: str, repo: Path, seed: int, generations: str, out_dir: Path, preset: str,
                  sets: list[tuple[str, str]], lineage: bool, max_ticks: int | None = None) -> list[str]:
    """헤드리스 실행기 명령줄. 같은 키를 여러 번 주면 실행기에서 뒤의 값이 이긴다."""
    cmd = [godot, "--headless", "--path", str(repo), "--script", RUNNER_SCRIPT, "--",
           f"--seed={seed}", f"--generations={generations}", f"--out={out_dir}", f"--preset={preset}"]
    for k, v in sets:
        cmd.append(f"--set={k}={v}")
    if max_ticks is not None and max_ticks > 0:
        cmd.append(f"--max-ticks={max_ticks}")
    if not lineage:
        cmd.append("--no-lineage")
    cmd.append("--quiet")
    return cmd


def result_line(stdout: str) -> str:
    """실행기 출력에서 마지막 "RESULT:" 줄."""
    found = ""
    for line in (stdout or "").splitlines():
        if line.startswith("RESULT:"):
            found = line.strip()
    return found


def execute_job(job: Job, repo: Path, timeout: float | None) -> dict:
    """실행기 하나를 돌리고 runs.csv 한 줄을 돌려준다. 출력은 결과 폴더의 run.log 에 남긴다."""
    t0 = time.monotonic()
    row = {"cell": job.cell, "seed": job.seed, "status": "", "exit_code": "", "wall_seconds": "",
           "result": "", "out_dir": "", "command": shlex.join(job.cmd)}
    log = ""
    try:
        # Godot 은 어느 OS 에서나 UTF-8 로 쓴다(RESULT 줄의 "농사" 등). 지역 코드 페이지(cp949·cp1252)로 읽지 않게.
        cp = subprocess.run(job.cmd, cwd=str(repo), capture_output=True, encoding="utf-8", errors="replace",
                            timeout=timeout)
        row["exit_code"] = cp.returncode
        row["result"] = result_line(cp.stdout)
        ok = cp.returncode == 0 and (job.out_dir / "summary.json").is_file()
        row["status"] = "ok" if ok else "failed"
        log = (cp.stdout or "") + (cp.stderr or "")
    except subprocess.TimeoutExpired as e:
        # subprocess.run 이 자기 자식 프로세스만 끝낸다(다른 godot 는 건드리지 않음)
        row["status"] = "timeout"
        log = _as_text(e.stdout) + _as_text(e.stderr) + f"\n시간 초과({timeout}초)\n"
    except OSError as e:
        row["status"] = "error"
        log = f"실행 실패: {e}\n"
    row["wall_seconds"] = f"{time.monotonic() - t0:.2f}"
    try:
        job.out_dir.mkdir(parents=True, exist_ok=True)
        (job.out_dir / "run.log").write_text(log, encoding="utf-8")
    except OSError:
        pass
    return row


def _as_text(b) -> str:
    if b is None:
        return ""
    if isinstance(b, bytes):
        return b.decode("utf-8", "replace")
    return str(b)


def read_runs_csv(path: Path) -> dict[tuple[str, int], dict]:
    """이전 runs.csv(이어 돌리기 때 기존 줄을 지키려고)."""
    rows: dict[tuple[str, int], dict] = {}
    if not path.is_file():
        return rows
    with path.open(encoding="utf-8", newline="") as f:
        for r in csv.DictReader(f):
            try:
                rows[(r.get("cell", ROOT_CELL), int(r["seed"]))] = r
            except (KeyError, ValueError):
                continue
    return rows


def write_runs_csv(path: Path, rows: dict[tuple[str, int], dict]) -> None:
    keys = sorted(rows, key=lambda k: (natural_key(k[0]), k[1]))
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=RUNS_COLUMNS, lineterminator="\n", extrasaction="ignore")
        w.writeheader()
        for k in keys:
            w.writerow({c: rows[k].get(c, "") for c in RUNS_COLUMNS})


def run_jobs(jobs: list[Job], out_root: Path, repo: Path, n_jobs: int, timeout: float | None) -> int:
    """일들을 병렬로 돌린다(이미 summary.json 이 있으면 건너뜀). runs.csv 를 쓰고 실패 수를 돌려준다."""
    runs_path = out_root / "runs.csv"
    rows = read_runs_csv(runs_path)
    todo: list[Job] = []
    mismatched = 0
    for job in jobs:
        key = (job.cell, job.seed)
        rel = _rel(job.out_dir, out_root)
        if (job.out_dir / "summary.json").is_file():
            diff = existing_mismatch(job)
            prev = rows.get(key)
            if diff:
                # 다른 설정의 결과를 덮어쓰지도, 이번 요청의 결과로 세지도 않는다 → 보고서의 실패 표에 나옴
                mismatched += 1
                rows[key] = {"cell": job.cell, "seed": job.seed, "status": "mismatch", "out_dir": rel,
                             "result": f"이미 있는 결과의 설정이 다름: {diff}", "command": shlex.join(job.cmd)}
                print(f"  경고: {rel} 에 설정이 다른 결과가 이미 있습니다({diff}). 다른 --out 을 쓰거나 폴더를 지우세요.")
                continue
            if prev is None or prev.get("status") not in ("ok", "existing"):
                rows[key] = {"cell": job.cell, "seed": job.seed, "status": "existing", "out_dir": rel,
                             "command": shlex.join(job.cmd)}
            print(f"  건너뜀(이미 있음): {rel}")
        else:
            todo.append(job)
    total = len(todo)
    print(f"실행 {total}개 (건너뜀 {len(jobs) - total}개), 동시에 {n_jobs}개")
    failed = mismatched
    lock = threading.Lock()
    if total > 0:
        with ThreadPoolExecutor(max_workers=max(1, n_jobs)) as pool:
            futures = {pool.submit(execute_job, job, repo, timeout): job for job in todo}
            done = 0
            for fut in as_completed(futures):
                job = futures[fut]
                row = fut.result()
                row["out_dir"] = _rel(job.out_dir, out_root)
                with lock:
                    done += 1
                    rows[(job.cell, job.seed)] = row
                    if row["status"] != "ok":
                        failed += 1
                    # 하나 끝날 때마다 runs.csv 를 갱신(중간에 멈춰도 기록이 남게)
                    write_runs_csv(runs_path, rows)
                tail = row["result"] or f"(RESULT 없음 — {row['out_dir']}/run.log 참고)"
                print(f"  [{done}/{total}] {row['out_dir']} {row['status']} {row['wall_seconds']}초  {tail}",
                      flush=True)
    out_root.mkdir(parents=True, exist_ok=True)
    write_runs_csv(runs_path, rows)
    if todo and all(rows[(j.cell, j.seed)].get("status") == "error" for j in todo):
        print("godot 실행 파일을 찾지 못했을 수 있습니다. --godot 경로나 환경 변수 GODOT 를 확인하세요.")
    return failed


def ensure_gdignore(d: Path) -> None:
    """결과 폴더에 빈 .gdignore 를 둔다(저장소 안이면 Godot 이 CSV 를 번역 표로, PNG 를 텍스처로 가져오지 않게).
    Godot 은 .gdignore 가 있는 폴더의 하위 폴더도 모두 건너뛴다. 저장소 밖에 두어도 해가 없다."""
    try:
        d.mkdir(parents=True, exist_ok=True)
        (d / ".gdignore").touch(exist_ok=True)
    except OSError:
        pass


def _rel(p: Path, root: Path) -> str:
    try:
        return Path(os.path.relpath(p, root)).as_posix()
    except ValueError:
        return p.as_posix()


def _check_repo(repo: Path) -> str:
    if not (repo / "project.godot").is_file():
        return f"Godot 프로젝트가 아닙니다(project.godot 없음): {repo}"
    if not (repo / "tests" / "run_experiment.gd").is_file():
        return f"헤드리스 실행기가 없습니다: {repo / 'tests' / 'run_experiment.gd'}"
    return ""


def cmd_run(args) -> int:
    """run: 씨앗마다 실행기 하나 → OUT/seed<N>/ → runs.csv → 보고서."""
    repo = Path(args.repo).resolve()
    err = _check_repo(repo)
    if err:
        print("오류: " + err, file=sys.stderr)
        return 2
    out_root = Path(args.out).resolve()
    out_root.mkdir(parents=True, exist_ok=True)
    ensure_gdignore(out_root)
    jobs = []
    for seed in args.seeds:
        out_dir = out_root / f"seed{seed}"
        cmd = build_command(args.godot, repo, seed, args.generations, out_dir, args.preset, args.set,
                            args.lineage, args.max_ticks)
        jobs.append(Job(ROOT_CELL, seed, out_dir, cmd, args.preset, args.generations, list(args.set), args.max_ticks))
    failed = run_jobs(jobs, out_root, repo, args.jobs, args.timeout)
    if not args.no_report:
        report(out_root, out_root, plots=not args.no_plots, lang=args.lang)
    return 1 if failed else 0


def cmd_sweep(args) -> int:
    """sweep: --param 격자의 칸마다 씨앗들을 돌려 OUT/<키=값__키=값>/seed<N>/ → runs.csv → 묶음별 보고서."""
    repo = Path(args.repo).resolve()
    err = _check_repo(repo)
    if err:
        print("오류: " + err, file=sys.stderr)
        return 2
    try:
        grid = build_grid(args.param)
    except ValueError as e:
        print("오류: " + str(e), file=sys.stderr)
        return 2
    out_root = Path(args.out).resolve()
    out_root.mkdir(parents=True, exist_ok=True)
    ensure_gdignore(out_root)
    print(f"격자 {len(grid)}칸 × 씨앗 {len(args.seeds)}개")
    jobs = []
    for cell, pairs in grid:
        for seed in args.seeds:
            out_dir = out_root / cell / f"seed{seed}"
            # 고정 덮어쓰기(--set) 뒤에 격자 값 → 같은 키면 격자 값이 이긴다
            sets = list(args.set) + pairs
            cmd = build_command(args.godot, repo, seed, args.generations, out_dir, args.preset, sets,
                                args.lineage, args.max_ticks)
            jobs.append(Job(cell, seed, out_dir, cmd, args.preset, args.generations, sets, args.max_ticks))
    failed = run_jobs(jobs, out_root, repo, args.jobs, args.timeout)
    if not args.no_report:
        report(out_root, out_root, plots=not args.no_plots, lang=args.lang)
    return 1 if failed else 0


# ── 결과 읽기 ──

def discover_runs(root: Path) -> list[Path]:
    """root 아래 summary.json 이 있는 폴더(실행 결과) 목록. 정렬해서 결정적으로."""
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        if "summary.json" in filenames:
            found.append(Path(dirpath))
    return sorted(found, key=lambda p: natural_key(_rel(p, root)))


def read_timeseries(path: Path) -> pd.DataFrame | None:
    if not path.is_file():
        return None
    try:
        df = pd.read_csv(path)
    except (pd.errors.EmptyDataError, pd.errors.ParserError, UnicodeDecodeError):
        return None
    for c in ("tick", "population", "mean_gen", "mean_size", "mean_sense", "civ_stage"):
        if c not in df.columns:
            return None
    return df


def read_chronicle(path: Path) -> pd.DataFrame | None:
    if not path.is_file():
        return None
    try:
        df = pd.read_csv(path, dtype={"kind": str, "text": str}, keep_default_na=False)
    except (pd.errors.EmptyDataError, pd.errors.ParserError, UnicodeDecodeError):
        return None
    for c in ("tick", "mean_gen", "kind", "text"):
        if c not in df.columns:
            return None
    df["tick"] = pd.to_numeric(df["tick"], errors="coerce")
    df["mean_gen"] = pd.to_numeric(df["mean_gen"], errors="coerce")
    return df


def discovery_generations(chron: pd.DataFrame | None, summary_ticks: dict,
                          ts: pd.DataFrame | None = None) -> dict[str, tuple[int, float]]:
    """단계별 (발견 틱, 발견 세대). 발견 세대 = chronicle.csv 의 discovery 사건 줄의 mean_gen.

    사건 단계는 문장 머리("채집 발견 — …")로 알아내고, 머리가 다르면 summary.json 의 발견 틱과 같은 틱으로 맞춘다.
    연대기가 없거나 사건이 빠졌는데 summary.json 에 발견 틱이 있으면 timeseries.csv 의 평균 세대를 틱으로 보간한다.
    발견하지 못한 단계는 (-1, NaN).
    """
    out: dict[str, tuple[int, float]] = {}
    events = []
    if chron is not None:
        d = chron[chron["kind"] == "discovery"]
        events = [(int(t), float(g), str(x)) for t, g, x in zip(d["tick"], d["mean_gen"], d["text"])
                  if not (pd.isna(t) or pd.isna(g))]
    used = set()
    for _, key, ko in STAGES:
        s_tick = summary_ticks.get(ko, -1) if isinstance(summary_ticks, dict) else -1
        try:
            s_tick = int(s_tick)
        except (TypeError, ValueError):
            s_tick = -1
        hit = None
        # 1) 문장 머리
        for i, (t, g, text) in enumerate(events):
            if i not in used and text.startswith(ko + " 발견"):
                hit = i
                break
        # 2) summary.json 발견 틱과 같은 틱의 사건(머리가 다를 때)
        if hit is None and s_tick >= 0:
            for i, (t, g, text) in enumerate(events):
                if i not in used and t == s_tick and not any(text.startswith(n + " 발견") for _, _, n in STAGES):
                    hit = i
                    break
        if hit is not None:
            used.add(hit)
            t, g, _ = events[hit]
            out[key] = (s_tick if s_tick >= 0 else t, g)
        elif s_tick >= 0 and ts is not None and len(ts) > 0:
            # 3) 연대기에 없으면 시계열 보간(근사)
            alive = ts[ts["population"] > 0]
            g = float(np.interp(s_tick, alive["tick"], alive["mean_gen"])) if len(alive) else float("nan")
            out[key] = (s_tick, round(g, 2))
        else:
            out[key] = (s_tick, float("nan"))
    return out


def summary_row(run_dir: Path, root: Path) -> tuple[dict, pd.DataFrame | None]:
    """실행 결과 폴더 하나 → summary.csv 한 줄과 시계열."""
    with (run_dir / "summary.json").open(encoding="utf-8") as f:
        s = json.load(f)
    ts = read_timeseries(run_dir / "timeseries.csv")
    chron = read_chronicle(run_dir / "chronicle.csv")
    disc = discovery_generations(chron, s.get("discovery_ticks", {}) or {}, ts)
    overrides = s.get("overrides", {}) or {}
    ov_text = ";".join(f"{k}={_json_scalar(overrides[k])}" for k in sorted(overrides))
    rel = _rel(run_dir, root)
    parent = Path(rel).parent.as_posix() if rel != "." else ROOT_CELL
    if parent in ("", "."):
        # 루트 바로 아래 씨앗 폴더들(run 결과) → 예설정(+덮어쓰기)으로 이름 짓기
        parent = str(s.get("preset", "default")) + (f"+{ov_text}" if ov_text else "")
    row = {
        "cell": parent, "seed": s.get("seed"), "preset": s.get("preset", ""), "overrides": ov_text,
        "generations_target": s.get("generations_target"),
        "end_reason": s.get("end_reason", ""), "ticks": s.get("tick"), "mean_generation": s.get("mean_generation"),
        "population": s.get("population"), "peak_population": s.get("peak_population"),
        "births": s.get("total_births"), "deaths": s.get("total_deaths"), "civ_stage": s.get("civ_stage"),
        "civ_stage_name": s.get("civ_stage_name", ""), "extinct_tick": s.get("extinct_tick", -1),
        "storehouses": s.get("storehouses"), "farms": s.get("farms"),
        "final_mean_size": float("nan"), "final_mean_sense": float("nan"),
        "run_seconds": s.get("run_seconds"), "history_hash": s.get("history_hash", ""), "path": rel,
    }
    for _, key, _ in STAGES:
        row[f"disc_tick_{key}"], row[f"disc_gen_{key}"] = disc[key]
    extinct = s.get("end_reason") == "extinction" or s.get("population") == 0 or _int_or(s.get("extinct_tick")) >= 0
    if extinct:
        # 멸종한 실행의 끝 평균 세대는 0(빈 개체의 평균)이 아니라 멸종 직전 값 — 아래 시계열에서. 없으면 NaN(중앙값에서 빠짐).
        row["mean_generation"] = float("nan")
    if ts is not None:
        alive = ts[ts["population"] > 0]
        if len(alive):
            row["final_mean_size"] = float(alive["mean_size"].iloc[-1])
            row["final_mean_sense"] = float(alive["mean_sense"].iloc[-1])
            if extinct:
                row["mean_generation"] = float(alive["mean_gen"].iloc[-1])
    return row, ts


def _json_scalar(v) -> str:
    if isinstance(v, (dict, list)):
        return json.dumps(v, ensure_ascii=False, separators=(",", ":"))
    if isinstance(v, float) and v.is_integer():
        return str(int(v)) if abs(v) < 1e15 else repr(v)
    return str(v)


def build_summary(root: Path) -> tuple[pd.DataFrame, dict[str, pd.DataFrame]]:
    """root 아래 모든 실행 → summary 표(묶음·씨앗 순)와 path → 시계열."""
    rows, series = [], {}
    for run_dir in discover_runs(root):
        try:
            row, ts = summary_row(run_dir, root)
        except (OSError, ValueError) as e:
            print(f"  읽지 못함: {run_dir} ({e})", file=sys.stderr)
            continue
        if not row["history_hash"]:
            continue  # 실행기 결과가 아닌 summary.json
        rows.append(row)
        if ts is not None:
            series[row["path"]] = ts
    df = pd.DataFrame(rows, columns=SUMMARY_COLUMNS)
    if len(df):
        order = sorted(range(len(df)), key=lambda i: (natural_key(df["cell"].iloc[i]), _int_or(df["seed"].iloc[i]),
                                                     df["path"].iloc[i]))
        df = df.iloc[order].reset_index(drop=True)
    for c in SUMMARY_INT_COLUMNS:
        df[c] = pd.to_numeric(df[c], errors="coerce").round().astype("Int64")
    for c in ("generations_target", "mean_generation", "final_mean_size", "final_mean_sense", "run_seconds",
              "disc_gen_forage", "disc_gen_store", "disc_gen_farm"):
        df[c] = pd.to_numeric(df[c], errors="coerce").astype(float)
    return df, series


def _int_or(v, default: int = -1) -> int:
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def cell_order(df: pd.DataFrame) -> list[str]:
    return sorted(set(df["cell"]), key=natural_key)


def quartiles(values) -> tuple[float, float, float]:
    """(Q1, 중앙값, Q3). 값이 없으면 NaN. numpy 기본(선형 보간) 사분위."""
    arr = np.asarray([v for v in values if not pd.isna(v)], dtype=float)
    if arr.size == 0:
        return float("nan"), float("nan"), float("nan")
    q1, med, q3 = np.percentile(arr, [25, 50, 75])
    return float(q1), float(med), float(q3)


def aggregate(df: pd.DataFrame) -> pd.DataFrame:
    """묶음별 집계: 실행 수, 멸종 비율, 단계별 도달 비율, 발견 세대 중앙값·사분위(도달한 실행만), 기타 중앙값."""
    rows = []
    for cell in cell_order(df):
        g = df[df["cell"] == cell]
        n = len(g)
        extinct = int(sum(1 for r, t in zip(g["end_reason"], g["extinct_tick"])
                          if r == "extinction" or (not pd.isna(t) and int(t) >= 0)))
        row = {"cell": cell, "runs": n, "extinct": extinct, "extinction_rate": extinct / n if n else float("nan")}
        stage = g["civ_stage"].fillna(0).astype(int)
        for st, key, _ in STAGES:
            reached = int((stage >= st).sum())
            row[f"reached_{key}"] = reached
            row[f"reach_rate_{key}"] = reached / n if n else float("nan")
        for _, key, _ in STAGES:
            vals = g[f"disc_gen_{key}"].dropna().tolist()
            q1, med, q3 = quartiles(vals)
            row[f"disc_gen_{key}_n"] = len(vals)
            row[f"disc_gen_{key}_median"] = med
            row[f"disc_gen_{key}_q1"] = q1
            row[f"disc_gen_{key}_q3"] = q3
            row[f"disc_gen_{key}_iqr"] = q3 - q1
        for c in ("mean_generation", "ticks", "population", "peak_population", "final_mean_size",
                  "final_mean_sense", "run_seconds"):
            row[f"{c}_median"] = quartiles(pd.to_numeric(g[c], errors="coerce").tolist())[1]
        row["run_seconds_total"] = float(pd.to_numeric(g["run_seconds"], errors="coerce").sum())
        rows.append(row)
    return pd.DataFrame(rows)


def write_csv(df: pd.DataFrame, path: Path) -> None:
    """결정적 CSV: UTF-8, 쉼표, \\n, 실수 10자리 유효숫자, 빈 값은 NaN."""
    df.to_csv(path, index=False, float_format=FLOAT_FORMAT, na_rep="NaN", lineterminator="\n", encoding="utf-8")


# ── 그림 ──

def load_pyplot():
    """matplotlib(Agg) 을 불러온다. 없으면 None."""
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        return plt
    except ImportError:
        return None


def setup_fonts(lang: str) -> str:
    """그림 언어 정하기. 한국어면 나눔고딕을 matplotlib 에 등록하고, 실패하면 영어로."""
    if lang == "en":
        return "en"
    try:
        from matplotlib import font_manager
        import matplotlib
        names = []
        for rel in FONT_FILES:
            p = default_repo() / rel
            if p.is_file():
                font_manager.fontManager.addfont(str(p))
                names.append(font_manager.FontProperties(fname=str(p)).get_name())
        if not names:
            raise FileNotFoundError("NanumGothic")
        matplotlib.rcParams["font.family"] = names[0]
        matplotlib.rcParams["axes.unicode_minus"] = False  # 나눔고딕에 − 글리프가 없음
        return "ko"
    except Exception as e:  # 글꼴 문제는 그림을 막지 않는다
        if lang == "ko":
            print(f"  한글 글꼴을 쓰지 못해 영어 문구로 그립니다({e})")
        return "en"


def _style(plt) -> None:
    plt.rcParams.update({
        "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
        "axes.edgecolor": AXIS, "axes.linewidth": 0.8, "axes.labelcolor": INK_2, "axes.titlecolor": INK,
        "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8, "grid.linestyle": "-",
        "axes.spines.top": False, "axes.spines.right": False, "axes.axisbelow": True,
        "xtick.color": MUTED, "ytick.color": MUTED, "xtick.labelcolor": INK_2, "ytick.labelcolor": INK_2,
        "font.size": 9.5, "axes.titlesize": 10.5, "axes.labelsize": 9.5, "legend.fontsize": 9,
        "legend.frameon": False, "lines.solid_capstyle": "round", "lines.solid_joinstyle": "round",
        "savefig.dpi": DPI, "figure.dpi": DPI,
    })


def _min_span(ax, span: float) -> None:
    """세로 범위가 span 보다 좁으면 가운데를 두고 넓힌다(변화가 거의 없을 때 잡음을 크게 보이지 않게)."""
    lo, hi = ax.get_ylim()
    if hi - lo < span:
        mid = (lo + hi) / 2.0
        ax.set_ylim(mid - span / 2.0, mid + span / 2.0)


class Plotter:
    """runs(요약 표)와 시계열로 그림 파일을 만든다. 묶음 ≤ 8 이면 한 그림에 겹쳐 색으로, 넘으면 묶음마다 작은 그림."""

    def __init__(self, plt, lang: str, df: pd.DataFrame, series: dict[str, pd.DataFrame], out_dir: Path):
        self.plt = plt
        self.t = TEXT[lang]
        self.df = df
        self.series = series
        self.out_dir = out_dir
        self.cells = cell_order(df)
        # 색은 묶음 순서로 고정(순위가 아니라 묶음을 따라감). 8개를 넘으면 돌려쓰지 않고 패싯 + 한 색
        self.facet = len(self.cells) > len(PALETTE)
        self.color = {c: (PALETTE[0] if self.facet else PALETTE[i]) for i, c in enumerate(self.cells)}
        self.files: list[str] = []

    def runs_of(self, cell: str) -> list[tuple[pd.Series, pd.DataFrame]]:
        """묶음의 (요약 줄, 시계열) — 씨앗 순. 시계열이 없는 실행은 빠진다."""
        out = []
        for _, r in self.df[self.df["cell"] == cell].iterrows():
            ts = self.series.get(r["path"])
            if ts is not None and len(ts):
                out.append((r, ts))
        return out

    def _new_fig(self, panels: int, height: float):
        """겹침 모드: 1 × panels 칸. 패싯 모드: 묶음마다 한 칸(가로 FACET_COLS 개씩). (그림, 칸 목록, 묶음 → 칸)."""
        plt = self.plt
        if self.facet:
            n = len(self.cells)
            cols = min(FACET_COLS, n)
            rows = math.ceil(n / cols)
            fig, axes = plt.subplots(rows, cols, figsize=(3.0 * cols, 2.2 * rows + TITLE_IN + 0.3), sharex=True,
                                     sharey=True, layout="constrained", squeeze=False)
            flat = list(axes.flat)
            for ax in flat[n:]:
                ax.set_visible(False)
            for cell, ax in zip(self.cells, flat):
                ax.set_title(cell, loc="left", fontsize=8.5, color=INK_2)
            return fig, flat[:n], dict(zip(self.cells, flat))
        width = 9.5 if panels == 1 else 5.2 * panels
        fig, axes = plt.subplots(1, panels, figsize=(width, height), layout="constrained", squeeze=False)
        flat = list(axes.flat)
        return fig, flat, {c: flat[0] for c in self.cells}

    def _legend(self, fig, extra: list | None = None) -> None:
        """묶음이 둘 이상이면 아래에 범례(색 선 + 이름 + 실행 수). 하나뿐이면 부제가 이름을 말한다."""
        from matplotlib.lines import Line2D
        handles = []
        if not self.facet and len(self.cells) >= 2:
            for c in self.cells:
                n = int((self.df["cell"] == c).sum())
                handles.append(Line2D([0], [0], color=self.color[c], lw=2, label=f"{c}  (n={n})"))
        if extra:
            handles.extend(extra)
        if handles:
            fig.legend(handles=handles, loc="outside lower center", ncol=min(len(handles), 4), frameon=False,
                       handlelength=1.6, columnspacing=1.8)

    def _finish(self, fig, name: str, title: str) -> None:
        """위에 제목(굵게)·부제(회색)를 두고 저장한다. 제목 자리는 인치로 고정해 그림 높이와 관계없이 같은 간격."""
        sub = self.t["runs_cells"].format(c=len(self.cells), r=len(self.df))
        if len(self.cells) == 1:
            sub = f"{self.cells[0]} · {sub}"
        w, h = fig.get_size_inches()
        fig.get_layout_engine().set(rect=(0.0, 0.0, 1.0, 1.0 - TITLE_IN / h))
        fig.text(0.14 / w, 1.0 - 0.12 / h, title, ha="left", va="top", fontsize=12, fontweight="bold", color=INK)
        fig.text(0.14 / w, 1.0 - 0.38 / h, sub, ha="left", va="top", fontsize=9, color=INK_2)
        fig.savefig(self.out_dir / name, dpi=DPI, metadata={"Software": None})
        self.plt.close(fig)
        self.files.append(name)

    def _extinct_handle(self):
        from matplotlib.lines import Line2D
        return Line2D([0], [0], color=INK_2, lw=0, marker="x", markersize=6, markeredgewidth=1.4,
                      label=self.t["extinct"])

    def _labels(self, axes: list, xlabel: str, ylabel: str) -> None:
        """축 이름. 패싯이면 왼쪽 열에만 세로 이름, 맨 아래 칸에만 가로 이름."""
        if not self.facet:
            for ax in axes:
                ax.set_xlabel(xlabel)
                ax.set_ylabel(ylabel)
            return
        n = len(axes)
        cols = min(FACET_COLS, n)
        for i, ax in enumerate(axes):
            if i % cols == 0:
                ax.set_ylabel(ylabel)
            if i >= n - cols:
                ax.set_xlabel(xlabel)
                ax.tick_params(labelbottom=True)

    def line_metric(self, name: str, title: str, xcol: str, ycol: str, xlabel: str, ylabel: str,
                    alive_only: bool, min_span: float | None = None) -> None:
        """실행마다 얇은 선 하나(묶음 색). 멸종한 실행은 끝에 ×.
        min_span 이 없으면 세로축은 0 부터(양: 개체 수·세대), 있으면 자동 범위 + 최소 폭(특성)."""
        fig, axes, ax_of = self._new_fig(1, 4.4)
        any_extinct = False
        for cell in self.cells:
            ax = ax_of[cell]
            for r, ts in self.runs_of(cell):
                d = ts[ts["population"] > 0] if alive_only else ts
                if len(d) == 0:
                    continue
                ax.plot(d[xcol], d[ycol], color=self.color[cell], lw=1.0, alpha=0.85)
                if r["end_reason"] == "extinction":
                    any_extinct = True
                    ax.plot([d[xcol].iloc[-1]], [d[ycol].iloc[-1]], marker="x", ms=6, mew=1.4,
                            color=self.color[cell], lw=0)
        for ax in axes:
            if min_span is None:
                ax.set_ylim(bottom=0)
            ax.set_xlim(left=0)
        if min_span is not None and axes:
            _min_span(axes[0], min_span)  # 패싯은 세로축을 함께 쓰므로 한 칸만 맞추면 됨
        self._labels(axes, xlabel, ylabel)
        self._legend(fig, [self._extinct_handle()] if any_extinct else None)
        self._finish(fig, name, title)

    def traits(self) -> None:
        """평균 크기·감지 반경 대 평균 세대. 겹침 모드: 한 그림에 두 칸. 패싯 모드: 특성마다 그림 한 장."""
        t = self.t
        specs = [("mean_size", t["mean_size"]), ("mean_sense", t["mean_sense"])]
        if self.facet:
            for col, label in specs:
                self.line_metric(f"traits_{col}.png", f"{t['t_traits_one']} — {label}", "mean_gen", col,
                                 t["mean_gen"], label, alive_only=True, min_span=TRAIT_MIN_SPAN[col])
            return
        fig, axes, _ = self._new_fig(2, 4.2)
        for ax, (col, label) in zip(axes, specs):
            for cell in self.cells:
                for _, ts in self.runs_of(cell):
                    d = ts[ts["population"] > 0]
                    if len(d):
                        ax.plot(d["mean_gen"], d[col], color=self.color[cell], lw=1.0, alpha=0.85)
            ax.set_xlabel(t["mean_gen"])
            ax.set_ylabel(label)
            ax.set_xlim(left=0)
            _min_span(ax, TRAIT_MIN_SPAN[col])
        self._legend(fig)
        self._finish(fig, "traits.png", t["t_traits"])

    def civ_stage(self) -> None:
        """문명 단계 계단선(가로 평균 세대). 겹치지 않게 실행마다 세로로 조금씩 띄운다."""
        t = self.t
        fig, axes, ax_of = self._new_fig(1, 4.0)
        # 한 칸에 그리는 실행들에 0, 1, 2 … 번호를 매겨 위아래로 펼친다
        slot: dict[str, int] = {}
        per_ax: dict[int, int] = {}
        for cell in self.cells:
            for r, _ in self.runs_of(cell):
                a = id(ax_of[cell])
                slot[r["path"]] = per_ax.get(a, 0)
                per_ax[a] = per_ax.get(a, 0) + 1
        any_extinct = False
        for cell in self.cells:
            ax = ax_of[cell]
            total = per_ax.get(id(ax), 1)
            # 펼친 폭 전체가 단계 간격의 CIV_SPREAD 를 넘지 않게(선이 다른 단계 쪽으로 넘어가 보이지 않도록)
            spread = min(0.06, CIV_SPREAD / max(1, total))
            for r, ts in self.runs_of(cell):
                off = (slot[r["path"]] - (total - 1) / 2.0) * spread
                d = ts[ts["population"] > 0]
                if len(d) == 0:
                    continue
                ax.plot(d["mean_gen"], d["civ_stage"] + off, color=self.color[cell], lw=1.3, alpha=0.9,
                        drawstyle="steps-post")
                if r["end_reason"] == "extinction":
                    any_extinct = True
                    ax.plot([d["mean_gen"].iloc[-1]], [d["civ_stage"].iloc[-1] + off], marker="x", ms=6, mew=1.4,
                            color=self.color[cell], lw=0)
        for ax in axes:
            ax.set_yticks(range(len(t["stages"])))
            ax.set_yticklabels(t["stages"])
            ax.set_ylim(-0.45, 3.45)
            ax.set_xlim(left=0)
            ax.grid(axis="x", visible=False)
        self._labels(axes, t["mean_gen"], t["civ_stage"])
        self._legend(fig, [self._extinct_handle()] if any_extinct else None)
        self._finish(fig, "civ_stage.png", t["t_civ"])

    def discovery(self) -> None:
        """단계마다 한 칸: 세로 = 묶음, 가로 = 발견 세대. 점 = 실행, 상자 = 사분위, 굵은 선 = 중앙값, 오른쪽 = 도달 수."""
        plt, t = self.plt, self.t
        n_cells = len(self.cells)
        height = TITLE_IN + 1.3 + 0.48 * n_cells
        fig, axes = plt.subplots(1, len(STAGES), figsize=(11.0, max(3.2, height)), layout="constrained",
                                 squeeze=False)
        for i, (ax, (st, key, _)) in enumerate(zip(axes.flat, STAGES)):
            col = f"disc_gen_{key}"
            any_point = False
            for yi, cell in enumerate(self.cells):
                y = n_cells - 1 - yi  # 첫 묶음이 맨 위
                g = self.df[self.df["cell"] == cell]
                vals = np.sort(g[col].dropna().to_numpy(dtype=float))
                m = len(vals)
                if m >= 3:
                    q1, q3 = np.percentile(vals, [25, 75])
                    ax.add_patch(plt.Rectangle((q1, y - 0.24), max(q3 - q1, 1e-9), 0.48, facecolor="none",
                                               edgecolor=MUTED, lw=1.0, zorder=2))
                if m >= 1:
                    med = float(np.median(vals))
                    ax.plot([med, med], [y - 0.32, y + 0.32], color=INK, lw=2.0, zorder=3, solid_capstyle="butt")
                    spread = min(0.13, 0.56 / m)
                    offs = [(j - (m - 1) / 2.0) * spread for j in range(m)]
                    ax.scatter(vals, [y + o for o in offs], s=36, color=self.color[cell], edgecolors=SURFACE,
                               linewidths=1.2, zorder=4)
                    any_point = True
                # 도달 수는 칸 안 오른쪽 끝(점들과 겹치지 않게 아래에서 가로 범위를 넓혀 둔다)
                ax.annotate(f"{m}/{len(g)}", xy=(1.0, y), xycoords=("axes fraction", "data"), xytext=(-4, 0),
                            textcoords="offset points", va="center", ha="right", fontsize=8.5, color=INK_2)
            ax.set_ylim(-0.6, n_cells - 0.4)
            ax.set_yticks(range(n_cells))
            ax.set_yticklabels(list(reversed(self.cells)) if i == 0 else [""] * n_cells)
            ax.tick_params(axis="y", length=0)
            ax.grid(axis="y", visible=False)
            ax.set_title(t["stages"][st], loc="left", fontsize=10.5, color=INK)
            ax.set_xlabel(t["disc_gen"])
            if not any_point:
                ax.text(0.5, 0.5, t["none_reached"], transform=ax.transAxes, ha="center", va="center",
                        color=MUTED, fontsize=9.5)
                ax.set_xticks([])
            else:
                # 세대는 0 부터(묶음 사이 이르고 늦음을 그대로 비교하도록), 오른쪽은 도달 수 글자 자리
                hi = float(np.nanmax(self.df[col].to_numpy(dtype=float)))
                hi = max(hi, 1.0)
                ax.set_xlim(0.0, hi * (1.0 + DISC_RIGHT_PAD))
        self._finish(fig, "discovery.png", t["t_disc"])


def make_plots(df: pd.DataFrame, series: dict[str, pd.DataFrame], out_dir: Path, lang: str) -> tuple[list[str], str]:
    """그림 파일을 만든다. (파일 이름 목록, 언어) — matplotlib 이 없으면 ([], "")."""
    plt = load_pyplot()
    if plt is None:
        print("matplotlib 이 없어 그림을 건너뜁니다(pip install matplotlib). 표와 보고서는 만들었습니다.")
        return [], ""
    used = setup_fonts(lang)
    _style(plt)
    p = Plotter(plt, used, df, series, out_dir)
    t = TEXT[used]
    p.line_metric("population.png", t["t_population"], "tick", "population", t["tick"], t["population"],
                  alive_only=False)
    p.line_metric("mean_gen.png", t["t_mean_gen"], "tick", "mean_gen", t["tick"], t["mean_gen"], alive_only=True)
    p.traits()
    p.civ_stage()
    p.discovery()
    return p.files, used


# ── 보고서 ──

PLOT_NOTES = {
    "population.png": ("개체 수", "실행마다 얇은 선 하나(가로 틱, 세로 살아 있는 개체 수, 묶음 색). 멸종한 실행은 끝에 ×. "
                       "개체 수 상한(population.cap)에 붙어 있으면 먹이보다 상한이 개체 수를 정하고 있다는 뜻."),
    "mean_gen.png": ("평균 세대", "틱에 따른 살아 있는 개체의 평균 세대. 기울기 = 세대 교체 속도(세대당 틱의 역수). "
                     "크기가 작아지는 진화가 일어나면 후반에 기울기가 바뀐다."),
    "traits.png": ("특성 변화", "가로 평균 세대, 세로 평균 크기(왼쪽)·평균 감지 반경(오른쪽). 대사 비용 압력으로 둘 다 "
                   "줄어드는지, 묶음(파라미터)마다 다른지 본다."),
    "traits_mean_size.png": ("특성 변화 — 크기", "묶음마다 작은 그림. 가로 평균 세대, 세로 평균 크기."),
    "traits_mean_sense.png": ("특성 변화 — 감지 반경", "묶음마다 작은 그림. 가로 평균 세대, 세로 평균 감지 반경."),
    "civ_stage.png": ("문명 단계", "가로 평균 세대, 세로 문명 단계(없음·채집·저장·농사) 계단선. 선이 겹치지 않게 실행마다 "
                      "세로로 조금씩 띄웠다. 계단이 오른쪽에 있을수록 늦게 발견. 멸종한 실행은 끝에 ×."),
    "discovery.png": ("발견 세대", "단계(채집·저장·농사)마다 한 칸. 세로 = 묶음, 점 = 실행 하나의 발견 세대, 회색 상자 = "
                      "사분위 범위(실행 3개 이상일 때), 굵은 검은 선 = 중앙값, 오른쪽 숫자 = 도달한 실행/전체 실행."),
}


def _fmt(v, digits: int = 1) -> str:
    if v is None or (isinstance(v, float) and math.isnan(v)) or (not isinstance(v, str) and pd.isna(v)):
        return "—"
    if isinstance(v, (int, np.integer)):
        return f"{int(v):,}"
    return f"{float(v):,.{digits}f}"


def _pct(k: int, n: int) -> str:
    if n == 0:
        return "—"
    return f"{round(100.0 * k / n):d}% ({k}/{n})"


def _md_table(header: list[str], rows: list[list[str]], align: list[str] | None = None) -> str:
    align = align or ["l"] * len(header)
    sep = ["---:" if a == "r" else "---" for a in align]
    lines = ["| " + " | ".join(header) + " |", "| " + " | ".join(sep) + " |"]
    for r in rows:
        lines.append("| " + " | ".join(str(c).replace("|", "\\|") for c in r) + " |")
    return "\n".join(lines)


def write_report_md(path: Path, root: Path, df: pd.DataFrame, cells: pd.DataFrame, plots: list[str],
                    plot_note: str, runs: dict[tuple[str, int], dict]) -> None:
    """report.md: 묶음별 요약, 발견 세대, 실행별 결과, 그림, 실패, 읽는 법(한국어)."""
    out = ["# 실험 분석 보고서", ""]
    presets = sorted(set(str(p) for p in df["preset"]))
    targets = sorted(set(float(v) for v in df["generations_target"] if not pd.isna(v)))
    overrides = sorted(set(str(o) for o in df["overrides"]))
    if overrides == [""]:
        ov_text = "없음"
    elif len(overrides) == 1:
        ov_text = f"`{overrides[0]}`"
    else:
        ov_text = "묶음마다 다름(`summary.csv` 의 `overrides` 열)"
    out += [
        f"- 결과 폴더: `{root.name}` — 실행 **{len(df)}개**, 묶음 **{len(cells)}개**",
        f"- 예설정 {', '.join(f'`{p}`' for p in presets)} · 목표 평균 세대 "
        f"{', '.join(_fmt(v, 1) for v in targets) or '—'} · 덮어쓰기 {ov_text}",
        "- 표: [`summary.csv`](summary.csv)(실행마다 한 줄), [`cells.csv`](cells.csv)(묶음별 집계). "
        "만든 명령: `python3 tools/analyze.py report <결과 폴더>`",
        "",
        "## 묶음별 요약",
        "",
    ]
    rows = []
    for _, c in cells.iterrows():
        n = int(c["runs"])
        rows.append([f"`{c['cell']}`", str(n), _pct(int(c["extinct"]), n),
                     _pct(int(c["reached_forage"]), n), _pct(int(c["reached_store"]), n),
                     _pct(int(c["reached_farm"]), n), _fmt(c["mean_generation_median"]),
                     _fmt(c["ticks_median"], 0), _fmt(c["population_median"], 0), _fmt(c["run_seconds_total"])])
    out.append(_md_table(["묶음", "실행", "멸종", "채집 도달", "저장 도달", "농사 도달", "끝 평균 세대(중앙값)",
                          "틱(중앙값)", "끝 개체 수(중앙값)", "실행 시간 합(초)"], rows,
                         ["l", "r", "r", "r", "r", "r", "r", "r", "r", "r"]))
    out += ["", "## 발견 세대", "",
            "도달한 실행만으로 계산한 **중앙값 [Q1–Q3]** (괄호 안 = 도달한 실행/전체). 발견하지 못한 실행은 빠지므로 "
            "도달 비율과 함께 읽습니다.", ""]
    rows = []
    for _, c in cells.iterrows():
        n = int(c["runs"])
        cellrow = [f"`{c['cell']}`"]
        for _, key, _ in STAGES:
            k = int(c[f"disc_gen_{key}_n"])
            if k == 0:
                cellrow.append(f"— (0/{n})")
            else:
                cellrow.append(f"{_fmt(c[f'disc_gen_{key}_median'])} [{_fmt(c[f'disc_gen_{key}_q1'])}–"
                               f"{_fmt(c[f'disc_gen_{key}_q3'])}] ({k}/{n})")
        rows.append(cellrow)
    out.append(_md_table(["묶음", "채집", "저장", "농사"], rows, ["l", "r", "r", "r"]))
    out += ["", "## 실행별 결과", ""]
    rows = []
    for _, r in df.iterrows():
        rows.append([f"`{r['cell']}`", _fmt(r["seed"]), END_REASON_KO.get(str(r["end_reason"]), str(r["end_reason"])),
                     _fmt(r["ticks"]), _fmt(r["mean_generation"]), _fmt(r["population"]),
                     _fmt(r["peak_population"]), str(r["civ_stage_name"] or "—"),
                     _fmt(r["disc_gen_forage"], 2), _fmt(r["disc_gen_store"], 2), _fmt(r["disc_gen_farm"], 2),
                     _fmt(r["final_mean_size"], 2), _fmt(r["final_mean_sense"], 2),
                     _fmt(r["run_seconds"]), f"`{str(r['history_hash'])[:12]}`"])
    out.append(_md_table(["묶음", "씨앗", "끝난 이유", "틱", "평균 세대", "개체", "최고", "단계", "채집 세대",
                          "저장 세대", "농사 세대", "끝 크기", "끝 감지", "시간(초)", "해시"], rows,
                         ["l", "r", "l", "r", "r", "r", "r", "l", "r", "r", "r", "r", "r", "r", "l"]))
    out += ["", "## 그림", ""]
    if not plots:
        out += [plot_note or "그림 없음.", ""]
    else:
        if plot_note:
            out += [plot_note, ""]
        for name in plots:
            title, note = PLOT_NOTES.get(name, (name, ""))
            out += [f"### {title}", "", f"![{title}]({name})", "", note, ""]
    bad = [r for r in runs.values() if r.get("status") not in ("ok", "existing", "")]
    if bad:
        out += ["## 실패·시간 초과", "",
                "`runs.csv` 에 성공하지 못한 것으로 기록된 실행입니다(failed·timeout·error 는 그 폴더의 `run.log`, "
                "mismatch = 그 폴더에 **설정이 다른 이전 결과**가 있어 건너뜀 — 위 표에 그 이전 결과가 섞여 있음).", ""]
        rows = [[f"`{b.get('cell', '')}`", str(b.get("seed", "")), str(b.get("status", "")),
                 str(b.get("exit_code", "")), f"`{b.get('out_dir', '')}`", str(b.get("result", ""))]
                for b in sorted(bad, key=lambda b: (natural_key(b.get("cell", "")), _int_or(b.get("seed"))))]
        out.append(_md_table(["묶음", "씨앗", "상태", "종료 코드", "폴더", "내용"], rows))
        out.append("")
    out += [
        "## 읽는 법",
        "",
        "- **발견 세대** = 그 실행의 `chronicle.csv` 에서 `kind = discovery` 인 사건 줄의 `mean_gen`"
        "(발견이 일어난 틱에 살아 있던 개체들의 평균 세대, 0.01 단위). 단계는 문장 머리(`채집 발견 — …`)로 가립니다.",
        "- **도달 비율** = 끝날 때 문명 단계(`civ_stage`)가 그 단계 이상인 실행의 비율. **멸종 비율** = 끝난 이유가 멸종인 실행의 비율.",
        "- **끝 평균 세대**: 멸종한 실행은 멸종 직전(살아 있던 마지막 시계열 줄, 최대 기록 간격 20틱 전)의 평균 세대입니다"
        "(빈 개체의 평균 0 을 쓰면 중앙값이 내려가 진화가 느린 것처럼 보이므로).",
        "- 사분위는 numpy 기본(선형 보간) 백분위수입니다. 실행이 적으면(씨앗 4개 등) 사분위 범위는 거칠게 읽어야 합니다.",
        "- 실행이 목표 세대에서 멈추므로, 목표보다 늦게 올 발견은 \"도달 못 함\"으로 보입니다(오른쪽 중도 절단).",
        "- 같은 씨앗·같은 설정이면 역사 해시가 같습니다(결정성). 해시가 다르면 설정이나 코드가 다릅니다.",
        "",
    ]
    path.write_text("\n".join(out), encoding="utf-8")


def report(root: Path, out_dir: Path | None = None, plots: bool = True, lang: str = "auto") -> int:
    """report: root 아래 결과를 모아 summary.csv·cells.csv·report.md·PNG 를 out_dir(기본 root)에 쓴다."""
    root = Path(root).resolve()
    out_dir = Path(out_dir).resolve() if out_dir else root
    if not root.is_dir():
        print(f"오류: 폴더가 없습니다: {root}", file=sys.stderr)
        return 2
    df, series = build_summary(root)
    if len(df) == 0:
        print(f"오류: {root} 아래에 실행 결과(summary.json)가 없습니다", file=sys.stderr)
        return 1
    out_dir.mkdir(parents=True, exist_ok=True)
    ensure_gdignore(out_dir)
    cells = aggregate(df)
    write_csv(df, out_dir / "summary.csv")
    write_csv(cells, out_dir / "cells.csv")
    files: list[str] = []
    note = ""
    if plots:
        files, used = make_plots(df, series, out_dir, lang)
        if not used:
            note = "matplotlib 이 없어 그림을 만들지 않았습니다(`pip install -r tools/requirements.txt`)."
        elif used == "en":
            note = "한글 글꼴을 쓰지 못해 그림 문구는 영어입니다."
    else:
        note = "그림을 끄고(--no-plots) 만들었습니다."
    runs = read_runs_csv(root / "runs.csv")
    write_report_md(out_dir / "report.md", root, df, cells, files, note, runs)
    print(f"보고서: {out_dir / 'report.md'}  (실행 {len(df)}개, 묶음 {len(cells)}개, 그림 {len(files)}장)")
    return 0


def cmd_report(args) -> int:
    return report(Path(args.dir), Path(args.out) if args.out else None, plots=not args.no_plots, lang=args.lang)


# ── 명령줄 ──

def _add_batch_args(p: argparse.ArgumentParser) -> None:
    """run·sweep 공통 인자."""
    p.add_argument("--seeds", type=_arg_type(parse_seeds), default=parse_seeds("1-4"),
                   help='씨앗: "1-8", "1,3,5", "1-3,7" (기본 1-4)')
    p.add_argument("--generations", type=_positive_number, default="100", help="목표 평균 세대(기본 100)")
    p.add_argument("--preset", default="default", help="예설정 이름(config/presets.json, 기본 default)")
    p.add_argument("--set", type=_arg_type(parse_set), action="append", default=[], metavar="KEY=VALUE",
                   help="설정 덮어쓰기(여러 번), 예: --set mutation.rate=0.08")
    p.add_argument("--jobs", type=int, default=max(1, min(4, os.cpu_count() or 1)),
                   help="동시에 돌릴 실행기 수(기본 min(4, CPU 수))")
    p.add_argument("--godot", default=os.environ.get("GODOT", "godot"), help="godot 실행 파일(기본 환경 변수 GODOT 또는 godot)")
    p.add_argument("--repo", default=str(default_repo()), help="저장소(기본 tools/ 의 부모)")
    p.add_argument("--out", required=True, help="결과 폴더")
    p.add_argument("--lineage", dest="lineage", action="store_true", help="lineage.csv 도 쓰기(크다)")
    p.add_argument("--no-lineage", dest="lineage", action="store_false", help="lineage.csv 쓰지 않기(기본)")
    p.set_defaults(lineage=False)
    p.add_argument("--max-ticks", type=int, default=None, help="틱 상한(기본 설정값)")
    p.add_argument("--timeout", type=float, default=3600.0, help="실행 하나의 시간 제한(초, 기본 3600)")
    p.add_argument("--no-report", action="store_true", help="실행만 하고 보고서는 만들지 않기")
    _add_report_opts(p)


def _add_report_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--no-plots", action="store_true", help="그림 만들지 않기")
    p.add_argument("--lang", choices=["auto", "ko", "en"], default="auto",
                   help="그림 문구 언어(auto = 한글 글꼴이 되면 한국어)")


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="analyze.py", description="슬라임 실험실 오프라인 분석(헤드리스 실행 묶음·보고서)")
    sub = ap.add_subparsers(dest="command", required=True)
    p = sub.add_parser("run", help="씨앗 여러 개를 같은 설정으로 돌리고 보고서")
    _add_batch_args(p)
    p.set_defaults(func=cmd_run)
    p = sub.add_parser("sweep", help="--param 격자 × 씨앗을 돌리고 묶음별 보고서")
    p.add_argument("--param", type=_arg_type(parse_param), action="append", required=True, metavar="KEY=V1,V2",
                   help="바꿔 볼 설정(여러 번 → 전체 격자), 예: --param mutation.rate=0.02,0.1")
    _add_batch_args(p)
    p.set_defaults(func=cmd_sweep)
    p = sub.add_parser("report", help="결과 폴더를 모아 summary.csv·report.md·그림")
    p.add_argument("dir", help="결과 폴더(아래의 summary.json 을 모두 찾음)")
    p.add_argument("--out", default=None, help="보고서 폴더(기본 결과 폴더)")
    _add_report_opts(p)
    p.set_defaults(func=cmd_report)
    return ap


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
