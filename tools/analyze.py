#!/usr/bin/env python3
"""슬라임 실험실 오프라인 분석 도구 (앱 실행에는 쓰지 않는다).

헤드리스 실행기(tests/run_experiment.gd)를 씨앗·파라미터별로 여러 번 돌리고, 결과 폴더들을 모아
표(summary.csv·cells.csv)·보고서(report.md)·그림(PNG)을 만든다.

  python3 tools/analyze.py run    --seeds 1-8 --generations 100 --preset fast_civ --out results/batch
  python3 tools/analyze.py sweep  --param mutation.rate=0.02,0.1 --seeds 1-4 --generations 50 --out results/sweep
  python3 tools/analyze.py report results/batch [--out 보고서폴더]
  python3 tools/analyze.py ablate --runs results/base --at-gen 30 --set mutation.rate=0.2 --ticks 340 --seeds 1-12
  python3 tools/analyze.py gate-a --seeds 1-12 --prereg COMMIT --out results/gate-a1-life      # 공식 A-1(= --variant A-1-life)
  python3 tools/analyze.py gate-a --variant A-2 --seeds 1-12 --prereg COMMIT --out results/gate-a2
  python3 tools/analyze.py baldwin results/learn [--probe 이식시험폴더 …] [--control-probe 대조폴더 …]

Windows(cmd·PowerShell): python3 대신 py, 인자는 큰따옴표(cmd 는 작은따옴표를 벗기지 않음), 줄잇기는 cmd ^·PowerShell `,
godot 은 콘솔 판으로: py tools\\analyze.py run --seeds 1-4 --godot "C:\\Godot\\Godot_v4.4.1-stable_win64_console.exe" --out results\\batch
(docs/ANALYSIS.md "Windows").

필요: Python 3.9 이상, numpy, pandas. matplotlib 은 선택(없으면 그림만 건너뛴다).
CSV(summary.csv·cells.csv·runs.csv)는 BOM 붙은 UTF-8 로 쓴다(엑셀이 한글을 바로 읽게). 읽을 때는 BOM 이 있어도 없어도 된다.
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
## 손 사본: 아래 목록은 시뮬레이션 상수를 옮겨 적은 것이라 tools/test_analyze.py TestHandCopies 가 원본과 견준다(단계마다 열이
## 늘면 함께 고침). 결과를 읽을 때 열 목록은 실행마다 summary.json 의 timeseries_columns·lineage_columns 를 먼저 쓴다(run_columns).
## scripts/sim/sim_recorder.gd 의 TIMESERIES_COLUMNS 와 같은 순서(v0.1 22열 + v0.2 0단계 행동 셈 16열 + 1단계 생애·학습 10열 —
## DESIGN-v0.2 9.3)
TIMESERIES_COLUMNS = [
    "tick", "day", "season", "light", "population", "births", "deaths", "mean_gen", "mean_energy",
    "mean_size", "mean_sense", "mean_age", "food_total", "dropped_total", "stored_total", "carry_total",
    "civ_stage", "storehouses", "farms", "forage_attempts", "store_drops", "farm_sprouts",
    "act_forward", "act_left", "act_right", "act_eat", "act_rest", "act_gather", "act_drop", "act_plant",
    "eff_forward", "eff_left", "eff_right", "eff_eat", "eff_rest", "eff_gather", "eff_drop", "eff_plant",
    "stage_juvenile", "stage_young", "stage_adult", "stage_old", "mean_size_eff",
    "learn_events", "eta_mean", "dw_mean", "rbar_mean", "pmax_mean",
]
## sim_recorder.gd 의 ACT_COLUMNS·EFF_COLUMNS(구간 행동별 고른 횟수·효과가 난 횟수, 행동 번호 SimBrain.ACT_* 순서)
ACT_COLUMNS = ["act_forward", "act_left", "act_right", "act_eat", "act_rest", "act_gather", "act_drop", "act_plant"]
EFF_COLUMNS = ["eff_forward", "eff_left", "eff_right", "eff_eat", "eff_rest", "eff_gather", "eff_drop", "eff_plant"]
## sim_recorder.gd 의 LINEAGE_COLUMNS(v0.1 11열 + eaten + 1단계 eta·dw·dw_juv·assim — DESIGN-v0.2 9.4)
LINEAGE_COLUMNS = ["id", "parent_a", "parent_b", "gen", "birth_tick", "death_tick", "death_cause", "children", "size",
                   "sense", "hue", "eaten", "eta", "dw", "dw_juv", "assim"]
## scripts/sim/sim_recorder.gd 의 CHRONICLE_COLUMNS
CHRONICLE_COLUMNS = ["tick", "mean_gen", "kind", "actor_id", "text"]
## SimWorld.STAGE_NAMES (0 없음 1 채집 2 저장 3 농사)
STAGE_NAMES_KO = ["없음", "채집", "저장", "농사"]
STAGE_NAMES_EN = ["none", "forage", "store", "farm"]
## 발견 단계: (단계 번호, 열 이름 꼬리, 연대기·summary.json 의 한국어 이름) — SimWorld.STAGE_FORAGE·STAGE_STORE·STAGE_FARM
STAGES = [(1, "forage", "채집"), (2, "store", "저장"), (3, "farm", "농사")]
## SimBrain.ACTION_NAMES(행동 번호 순서 — ACT_COLUMNS 의 꼬리와 같은 순서)
ACTION_NAMES_KO = ["앞으로", "왼쪽 돌기", "오른쪽 돌기", "먹기", "쉬기", "줍기", "내려놓기", "심기"]
## 문명 행동: (열 꼬리, 그 행동이 효과를 낼 수 있게 되는 문명 단계). 줍기·심기는 SimWorld._act 의 단계 문(InfoPanel.ACTION_STAGE 와
## 같음), 내려놓기는 운반이 있어야 효과가 나는데 운반은 채집이 열린 뒤에만 생김.
CIV_ACTIONS = [("gather", 1), ("drop", 1), ("plant", 3)]
## summary.json 의 끝난 이유 → 보고서 표기
END_REASON_KO = {"generations": "세대 도달", "extinction": "멸종", "max_ticks": "틱 상한"}

## summary.csv 열(이 순서로 쓴다)
SUMMARY_COLUMNS = [
    "cell", "seed", "preset", "overrides", "generations_target", "end_reason", "ticks", "mean_generation",
    "population", "peak_population", "births", "deaths", "civ_stage", "civ_stage_name", "extinct_tick",
    "storehouses", "farms",
    "disc_tick_forage", "disc_gen_forage", "disc_tick_store", "disc_gen_store", "disc_tick_farm", "disc_gen_farm",
    "final_mean_size", "final_mean_sense", "window_births", "run_seconds", "history_hash", "path",
]
## 정수로 써야 하는 summary.csv 열
SUMMARY_INT_COLUMNS = [
    "seed", "ticks", "population", "peak_population", "births", "deaths", "civ_stage", "extinct_tick",
    "storehouses", "farms", "disc_tick_forage", "disc_tick_store", "disc_tick_farm", "window_births",
]
## runs.csv 열
RUNS_COLUMNS = ["cell", "seed", "status", "exit_code", "wall_seconds", "result", "out_dir", "command"]
## CSV 실수 형식(입력이 소수 6자리 이하라 10자리 유효숫자면 그대로 왕복)
FLOAT_FORMAT = "%.10g"
## 묶음 하나를 대표하는 루트 폴더 이름(run 결과처럼 씨앗 폴더가 바로 아래에 있을 때)
ROOT_CELL = "."
## 예설정 이름을 모르는 실행(스냅숏에서 이어 돌렸거나 실험실에서 스냅숏을 연 실험 — summary.json 의 preset 이 "")의 묶음 이름
SNAPSHOT_CELL = "snapshot"
## 쓰는 CSV 의 인코딩: BOM 붙은 UTF-8(한국어 Windows 엑셀이 두 번 클릭으로 열어도 한글이 깨지지 않게 — 검토 J07).
## 읽을 때도 이것으로(BOM 이 없는 예전 파일도 그대로 읽힘)
CSV_ENCODING = "utf-8-sig"
## 끝까지 쓴 실행 결과 폴더에 summary.json 과 함께 있어야 하는 파일(이어 돌리기 때 완결성 확인 — 검토 I07)
RESULT_FILES = ["timeseries.csv", "chronicle.csv", "final.snapshot.json"]
## runs.csv 의 이전 상태가 이것이면 summary.json 이 있어도 다시 돌린다(쓰다 실패했거나 중간에 끊긴 실행)
RERUN_STATUSES = ("failed", "timeout", "error")
## --generations 로 받는 수: 실행기(String.is_valid_float)와 파이썬 float 이 둘 다 읽는 꼴(부호 없는 10진수, 지수 표기)
GENERATIONS_RE = re.compile(r"\+?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?")

# ── 행동 셈(act/eff)·먹은 양·관문 A-1 미리 보기(DESIGN-v0.2 11.1·11.3·14.1 범위 10) ──

## 행동 비율 표의 세대 구간 폭(구간 시작의 평균 세대로 0~10, 10~20, …)
ACT_GEN_BIN = 10
## 같은 틱 비교 표의 틱 구간 경계(우연 기준 세계는 수백 틱 만에 멸종할 수 있어 처음 1,000틱을 틱으로 견줌 — DESIGN-v0.2 11.3)
ACT_TICK_EDGES = [0, 200, 400, 600, 800, 1000]
## 먹은 양 표의 개체 세대 구간 폭(lineage.csv 의 gen)
EATEN_GEN_BIN = 10
## 관문 A-1(DESIGN-v0.2 14.3)의 대상 출생 틱 구간 [시작, 끝), 처음 정의(A-1)의 판정에 필요한 틱(그 전에 멸종하면 판정 불가 — 공식
## A-1-life 에는 이 요구가 없음, 사용자 결정 2026-10-11), 씨앗마다 필요한 대상 출생 수(GATE_A_MIN_BIRTHS). 0단계 기준선 보고가 우연 기준
## 세계에서 처음 정의의 판정이 가능한지 미리 본다(판정 자체는 gate-a).
GATE_A_BIRTH_WINDOW = (200, 600)
GATE_A_TICKS = 1000
GATE_A_MIN_BIRTHS = 30
## 반사실 재생(ablate)의 두 갈래 폴더 이름(그대로 · 바꿈)과, 갈래 실행에 주는 평균 세대 끝 조건(세대가 먼저 끝내지 않게 큰 값 — 11.4)
ABLATE_SAME = "same"
ABLATE_FORK = "fork"
ABLATE_GENERATIONS = "1000000000"
## 뺀 씨앗의 까닭에 붙이는 run.log 오류 줄의 최대 글자 수
FAILURE_LINE_MAX = 300

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
    if "'" in key or '"' in key:
        # Windows cmd 는 작은따옴표를 벗기지 않아 '키=값' 이 따옴표째 넘어온다 → 모든 실행이 '알 수 없는 키' 로 실패하기 전에 막음
        raise ValueError(f"키에 따옴표가 들어 있습니다: {key} — Windows cmd 에서는 큰따옴표로 감싸세요(docs/ANALYSIS.md \"Windows\")")
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
    """--generations: 실행기가 받는 꼴(GENERATIONS_RE — 파이썬 float 만 읽는 1_0 같은 글은 실행기가 거부해 모든 실행이
    실패하므로 여기서 막음)의 0 보다 큰 유한한 수인지 확인하고, 글자는 그대로 실행기에 넘긴다."""
    t = str(text).strip()
    if not GENERATIONS_RE.fullmatch(t):
        raise argparse.ArgumentTypeError(f"수여야 합니다(예: 100, 2.5, 1e3): {text}")
    v = float(t)
    if not math.isfinite(v) or v <= 0:
        raise argparse.ArgumentTypeError(f"0 보다 커야 합니다: {text}")
    return t


## 실행기의 틱 상한 SimConfig.TICK_MAX 를 읽을 곳(단일 기준 — 실행기 --max-ticks 는 1~이 값, 밖이면 인자 오류 2)
SIM_CONFIG_GD = "scripts/sim/sim_config.gd"
TICK_MAX_RE = re.compile(r"^const TICK_MAX := (\d+)$", re.M)
## --max-ticks 글: 실행기 int_arg(String.is_valid_int)가 받는 꼴(부호 하나 + 숫자) — 1e5·1_0 은 거부
INT_RE = re.compile(r"[+-]?[0-9]+")


def tick_max(repo: Path | None = None) -> int:
    """실행기의 틱 상한(scripts/sim/sim_config.gd 의 `const TICK_MAX`)."""
    m = TICK_MAX_RE.search((repo or default_repo()).joinpath(SIM_CONFIG_GD).read_text(encoding="utf-8"))
    if not m:
        raise ValueError(f"{SIM_CONFIG_GD} 에서 TICK_MAX 를 찾지 못했습니다")
    return int(m.group(1))


def _max_ticks(text: str) -> int:
    """--max-ticks: 실행기와 같은 1~TICK_MAX 의 정수. 예전엔 0·음수를 조용히 "상한 없음"(설정의 run.max_ticks)으로 돌렸음."""
    t = str(text).strip()
    hi = tick_max()
    if not INT_RE.fullmatch(t) or not 1 <= int(t) <= hi:
        raise argparse.ArgumentTypeError(f"1~{hi} 의 정수여야 합니다: {text}")
    return int(t)


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
    """실행기 한 번: 묶음·씨앗·결과 폴더·명령줄, 그리고 이어 돌리기 때 맞춰 볼 요청 설정.
    resume·forks·reset 은 반사실 재생(ablate)의 갈래: 이어 돌릴 스냅숏, --fork-set 키=값, --fork-reset-learned(배운 두뇌 되돌림)."""
    cell: str
    seed: int
    out_dir: Path
    cmd: list[str] = field(default_factory=list)
    preset: str = ""
    generations: str = ""
    sets: list[tuple[str, str]] = field(default_factory=list)
    max_ticks: int | None = None
    resume: str = ""
    forks: list[tuple[str, str]] = field(default_factory=list)
    reset: bool = False


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
        s = json.loads((job.out_dir / "summary.json").read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return "summary.json 을 읽을 수 없음"
    diffs = []
    if job.preset and str(s.get("preset", "")) != job.preset:
        diffs.append(f"preset {s.get('preset')} ≠ {job.preset}")
    if job.generations and not _same_value(job.generations, s.get("generations_target")):
        diffs.append(f"generations {s.get('generations_target')} ≠ {job.generations}")
    # 덮어쓰기(--set)와 반사실 재생의 바꾼 키(--fork-set → summary.json 의 forked, 예전 결과는 없음 = {})
    for want, have in ((dict(job.sets), s.get("overrides", {}) or {}), (dict(job.forks), s.get("forked", {}) or {})):
        # 같은 키는 뒤의 값(실행기와 같은 규칙)
        for k in sorted(set(want) | set(have)):
            if k not in want or k not in have or not _same_value(want[k], have[k]):
                diffs.append(f"{k} {_json_scalar(have[k]) if k in have else '없음'} ≠ {want.get(k, '없음')}")
    if job.resume and _norm_path(s.get("resumed_from", "")) != _norm_path(job.resume):
        diffs.append(f"resumed_from {s.get('resumed_from') or '없음'} ≠ {job.resume}")
    # 이식 시험(--fork-reset-learned): summary.json 의 reset_learned(1단계부터 — 예전 결과는 없음 = false)
    if bool(s.get("reset_learned", False)) != job.reset:
        diffs.append(f"reset_learned {bool(s.get('reset_learned', False))} ≠ {job.reset}")
    # 틱 상한: 실행기가 summary.json 에 실제로 쓴 상한(max_ticks)과 이번 요청(--max-ticks, 없으면 설정의 run.max_ticks).
    # 예전 결과(max_ticks 기록 없음)는 설정값으로 본다. 다르면 잘린 실행이 섞이므로 mismatch.
    cfg_cap = ((s.get("config", {}) or {}).get("run", {}) or {}).get("max_ticks")
    have_cap = s.get("max_ticks", cfg_cap)
    want_cap = job.max_ticks if job.max_ticks is not None and job.max_ticks > 0 else cfg_cap
    if have_cap is not None and want_cap is not None and float(have_cap) != float(want_cap):
        diffs.append(f"max_ticks {_json_scalar(have_cap)} ≠ {_json_scalar(want_cap)}")
    return ", ".join(diffs)


def _norm_path(p) -> str:
    """경로 비교용(절대·정리). 빈 값은 ""."""
    return os.path.normcase(os.path.abspath(str(p))) if p else ""


def default_repo() -> Path:
    """기본 저장소 위치 = tools/ 의 부모."""
    return Path(__file__).resolve().parent.parent


def resolve_godot(godot: str) -> str:
    """--godot: 경로 구분자가 있으면 지금 셸 위치 기준 절대 경로로 바꾼다(실행기는 저장소 폴더에서 돌므로 ./godot 같은 상대
    경로가 저장소 기준으로 풀려 못 찾음 — --out·--repo 와 같은 기준, 검토 I22). 이름만 있으면(godot) PATH 에서 찾게 그대로."""
    seps = [os.sep, "/"] + ([os.altsep] if os.altsep else [])
    if any(sep in godot for sep in seps):
        return os.path.abspath(godot)
    return godot


def command_text(cmd: list[str], windows: bool | None = None) -> str:
    """runs.csv 의 command 열: 그 OS 의 셸에 그대로 붙여 다시 돌릴 수 있는 글(Windows = cmd 따옴표 규칙 list2cmdline,
    그 밖 = POSIX shlex.join). windows 를 주지 않으면 지금 OS."""
    if windows is None:
        windows = os.name == "nt"
    return subprocess.list2cmdline(cmd) if windows else shlex.join(cmd)


def incomplete_reason(run_dir: Path) -> str:
    """summary.json 이 있는 결과 폴더가 끝까지 쓴 실행 결과인가. 맞으면 "", 아니면 까닭.
    조건: summary.json 이 읽히고 역사 해시가 있으며 write_failed(실행기가 summary.json 보다 먼저 못 쓴 파일)가 비었고,
    RESULT_FILES 가 비어 있지 않게 있음(쓰기 실패·중간에 끊긴 실행은 summary.json 만 남을 수 있음)."""
    try:
        s = json.loads((run_dir / "summary.json").read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return "summary.json 을 읽을 수 없음"
    if not isinstance(s, dict) or not s.get("history_hash"):
        return "summary.json 에 역사 해시가 없음"
    if s.get("write_failed"):
        return "쓰지 못한 파일: " + ", ".join(str(x) for x in s["write_failed"])
    for name in RESULT_FILES:
        p = run_dir / name
        if not p.is_file() or p.stat().st_size == 0:
            return f"{name} 없음"
    return ""


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


def build_resume_command(godot: str, repo: Path, snapshot: Path, max_ticks: int, out_dir: Path,
                         forks: list[tuple[str, str]], lineage: bool, reset: bool = False) -> list[str]:
    """반사실 재생 갈래의 실행기 명령줄(DESIGN-v0.2 11.4 의 2): 스냅숏에서 --max-ticks(절대 틱)까지, 세대 끝 조건은 큰 값.
    --resume 은 --seed·--preset·--set 과 함께 줄 수 없으므로 그것들은 넣지 않는다. forks 가 있으면 --fork-set 으로,
    reset 이면 --fork-reset-learned(이식 시험 — 살아 있는 개체의 배운 두뇌를 타고난 것으로 되돌림, 11.2)."""
    cmd = [godot, "--headless", "--path", str(repo), "--script", RUNNER_SCRIPT, "--",
           f"--resume={snapshot}", f"--max-ticks={max_ticks}", f"--generations={ABLATE_GENERATIONS}", f"--out={out_dir}"]
    for k, v in forks:
        cmd.append(f"--fork-set={k}={v}")
    if reset:
        cmd.append("--fork-reset-learned")
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
           "result": "", "out_dir": "", "command": command_text(job.cmd)}
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


def failure_detail(run_dir: Path, row: dict | None) -> str:
    """실패한 실행의 종료 코드(runs.csv 줄)와 run.log 의 마지막 오류 줄 — 엔진 머리 줄과 들여 쓴 줄(엔진 오류의 'at:')은 빼고.
    실행기의 오류 문장(예: --fork-set 으로 바꾼 설정으로 스냅숏을 열 수 없음)이 그 폴더를 열지 않아도 보이게."""
    parts = []
    code = str((row or {}).get("exit_code", "")).strip()
    if code:
        parts.append(f"종료 코드 {code}")
    try:
        lines = (run_dir / "run.log").read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        lines = []
    msg = [ln.strip() for ln in lines if ln.strip() and not ln[:1].isspace() and not ln.startswith("Godot Engine")]
    if msg:
        parts.append(msg[-1][:FAILURE_LINE_MAX].replace("|", "/"))
    return " — ".join(parts)


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
    with path.open(encoding=CSV_ENCODING, newline="") as f:
        for r in csv.DictReader(f):
            try:
                rows[(r.get("cell", ROOT_CELL), int(r["seed"]))] = r
            except (KeyError, ValueError):
                continue
    return rows


def write_runs_csv(path: Path, rows: dict[tuple[str, int], dict]) -> None:
    keys = sorted(rows, key=lambda k: (natural_key(k[0]), k[1]))
    with path.open("w", encoding=CSV_ENCODING, newline="") as f:
        w = csv.DictWriter(f, fieldnames=RUNS_COLUMNS, lineterminator="\n", extrasaction="ignore")
        w.writeheader()
        for k in keys:
            w.writerow({c: rows[k].get(c, "") for c in RUNS_COLUMNS})


def run_jobs(jobs: list[Job], out_root: Path, repo: Path, n_jobs: int, timeout: float | None) -> int:
    """일들을 병렬로 돌린다(이미 끝까지 쓴 결과가 있으면 건너뜀). runs.csv 를 쓰고 실패 수를 돌려준다.
    summary.json 이 있어도 runs.csv 의 이전 상태가 RERUN_STATUSES 이거나 결과 파일이 덜 쓰였으면(incomplete_reason) 다시 돌린다."""
    runs_path = out_root / "runs.csv"
    rows = read_runs_csv(runs_path)
    todo: list[Job] = []
    mismatched = 0
    for job in jobs:
        key = (job.cell, job.seed)
        rel = _rel(job.out_dir, out_root)
        if (job.out_dir / "summary.json").is_file():
            prev = rows.get(key)
            why = incomplete_reason(job.out_dir)
            if not why and prev is not None and prev.get("status") in RERUN_STATUSES:
                why = f"이전 실행 {prev.get('status')}"
            if why:
                # 쓰다 실패했거나 끊긴 실행은 결과가 아니다 → 다시 돌림(실행기가 앞 결과 파일을 지우고 새로 씀)
                print(f"  다시 돌림({why}): {rel}")
                todo.append(job)
                continue
            diff = existing_mismatch(job)
            if diff:
                # 다른 설정의 결과를 덮어쓰지도, 이번 요청의 결과로 세지도 않는다 → 보고서의 실패 표에 나옴
                mismatched += 1
                rows[key] = {"cell": job.cell, "seed": job.seed, "status": "mismatch", "out_dir": rel,
                             "result": f"이미 있는 결과의 설정이 다름: {diff}", "command": command_text(job.cmd)}
                print(f"  경고: {rel} 에 설정이 다른 결과가 이미 있습니다({diff}). 다른 --out 을 쓰거나 폴더를 지우세요.")
                continue
            if prev is None or prev.get("status") not in ("ok", "existing"):
                rows[key] = {"cell": job.cell, "seed": job.seed, "status": "existing", "out_dir": rel,
                             "command": command_text(job.cmd)}
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


def make_out_dir(d: Path, what: str = "--out") -> str:
    """결과 폴더를 만들고 .gdignore 를 둔다. 만들 수 없으면(그 자리나 부모가 파일·권한 없음) 오류 문장을 돌려준다 — 부르는 쪽이
    '오류:' 와 종료 코드 2 로 끝냄(예전엔 FileExistsError 추적과 종료 코드 1 — 1단계 검증 지적)."""
    if d.exists() and not d.is_dir():
        return f"{what} 이 폴더가 아니라 파일입니다: {d}"
    try:
        d.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        return f"{what} 폴더를 만들 수 없습니다: {d} ({e.strerror or e})"
    ensure_gdignore(d)
    return ""


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
    godot = resolve_godot(args.godot)
    out_root = Path(args.out).resolve()
    err = make_out_dir(out_root)
    if err:
        print("오류: " + err, file=sys.stderr)
        return 2
    jobs = []
    for seed in args.seeds:
        out_dir = out_root / f"seed{seed}"
        cmd = build_command(godot, repo, seed, args.generations, out_dir, args.preset, args.set,
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
    godot = resolve_godot(args.godot)
    out_root = Path(args.out).resolve()
    err = make_out_dir(out_root)
    if err:
        print("오류: " + err, file=sys.stderr)
        return 2
    print(f"격자 {len(grid)}칸 × 씨앗 {len(args.seeds)}개")
    jobs = []
    for cell, pairs in grid:
        for seed in args.seeds:
            out_dir = out_root / cell / f"seed{seed}"
            # 고정 덮어쓰기(--set) 뒤에 격자 값 → 같은 키면 격자 값이 이긴다
            sets = list(args.set) + pairs
            cmd = build_command(godot, repo, seed, args.generations, out_dir, args.preset, sets,
                                args.lineage, args.max_ticks)
            jobs.append(Job(cell, seed, out_dir, cmd, args.preset, args.generations, sets, args.max_ticks))
    failed = run_jobs(jobs, out_root, repo, args.jobs, args.timeout)
    if not args.no_report:
        report(out_root, out_root, plots=not args.no_plots, lang=args.lang)
    return 1 if failed else 0


# ── 반사실 재생(ablate — DESIGN-v0.2 11.4) ──

## ablate 가 견주는 지표: (키, 보고서 이름). 창 = 갈라진 틱 F 부터 F + N 앞까지(시계열은 틱 (F, F + N] 의 줄 — 구간 출생·사망·행동
## 셈이 그 틱들 동안의 것, 계통은 틱 [F, F + N) 에 태어난 '대상' 개체).
ABLATE_METRICS = [
    ("births", "출생"), ("deaths", "사망"), ("pop_mean", "평균 개체 수"), ("pop_end", "끝 개체 수"),
    ("alive_ticks", "산 틱"),
    ("act_gather", "줍기 고름 %"), ("eff_gather", "줍기 효과 %"), ("act_drop", "내려놓기 고름 %"),
    ("eff_drop", "내려놓기 효과 %"), ("act_plant", "심기 고름 %"), ("eff_plant", "심기 효과 %"),
    ("target_eaten", "대상 평균 먹은 양"), ("target_children", "대상 평균 자식 수"),
]
## ablate.csv 열(씨앗·지표마다 한 줄)
ABLATE_COLUMNS = ["seed", "fork_tick", "metric", "same", "fork", "diff"]
## ablate 의 조건 파일(baldwin 이 이식 시험 폴더를 읽을 때 씀)과, --reset-learned 일 때 기본 폴더 이름에 붙이는 말
ABLATE_META = "ablate.json"
ABLATE_RESET_TAG = "reset_learned"


def ablate_metrics(run_dir: Path, fork_tick: int, ticks: int) -> dict[str, float]:
    """갈래 하나(결과 폴더)의 창 [F, F + N) 지표(ABLATE_METRICS). 없는 값은 NaN(멸종 뒤 행동 셈, lineage.csv 없음 등)."""
    out = {k: float("nan") for k, _ in ABLATE_METRICS}
    s = json.loads((run_dir / "summary.json").read_text(encoding="utf-8-sig"))
    ts = read_timeseries(run_dir / "timeseries.csv")
    end = fork_tick + ticks
    ext = _int_or(s.get("extinct_tick"))
    out["alive_ticks"] = float((ext if 0 <= ext < end else end) - fork_tick)
    if ts is not None:
        w = ts[(ts["tick"] > fork_tick) & (ts["tick"] <= end)]
        if len(w):
            out["births"] = float(w["births"].sum())
            out["deaths"] = float(w["deaths"].sum())
            out["pop_mean"] = float(w["population"].mean())
            out["pop_end"] = float(w["population"].iloc[-1])
            if all(c in w.columns for c in ACT_COLUMNS + EFF_COLUMNS):
                total = float(w[ACT_COLUMNS].to_numpy(dtype=float).sum())
                for key, _ in CIV_ACTIONS:
                    if total > 0:
                        out["act_" + key] = 100.0 * float(w["act_" + key].sum()) / total
                        out["eff_" + key] = 100.0 * float(w["eff_" + key].sum()) / total
    lin = read_lineage(run_dir / "lineage.csv")
    if lin is not None:
        tg = lin[(lin["parent_a"] >= 0) & (lin["birth_tick"] >= fork_tick) & (lin["birth_tick"] < end)]
        if len(tg):
            out["target_children"] = float(tg["children"].mean())
            if "eaten" in tg.columns:
                out["target_eaten"] = float(tg["eaten"].mean())
    return out


def ablate_table(pairs: list[tuple[int, int, dict, dict]]) -> tuple[pd.DataFrame, list[list[str]]]:
    """씨앗마다 (씨앗, F, 그대로 지표, 바꿈 지표) → (ablate.csv 표, 보고서 줄). 보고서 줄은 지표마다: 씨앗 수(두 갈래 모두 값이
    있는), 그대로·바꿈 중앙값, 차이(바꿈 − 그대로)의 중앙값 [Q1–Q3], 바꿈이 큰·작은 씨앗 수."""
    rows = []
    for seed, f, same, fork in pairs:
        for key, _ in ABLATE_METRICS:
            a, b = same[key], fork[key]
            rows.append({"seed": seed, "fork_tick": f, "metric": key, "same": a, "fork": b,
                         "diff": b - a if not (math.isnan(a) or math.isnan(b)) else float("nan")})
    table = pd.DataFrame(rows, columns=ABLATE_COLUMNS)
    md = []
    for key, name in ABLATE_METRICS:
        g = table[(table["metric"] == key) & table["diff"].notna()]
        if not len(g):
            md.append([name, "0", "—", "—", "—", "—"])
            continue
        q1, med, q3 = quartiles(g["diff"])
        up = int((g["diff"] > 0).sum())
        down = int((g["diff"] < 0).sum())
        md.append([name, str(len(g)), _fmt(quartiles(g["same"])[1], 2), _fmt(quartiles(g["fork"])[1], 2),
                   f"{_fmt(med, 2)} [{_fmt(q1, 2)}–{_fmt(q3, 2)}]", f"{up} · {down}"])
    return table, md


def cmd_ablate(args) -> int:
    """ablate: 반사실 재생(DESIGN-v0.2 11.4 의 실행 순서). 씨앗마다
      ① 기준 실행 --runs/seed<N>/ 을 평균 --at-gen 세대까지(같은 설정의 끝까지 쓴 결과가 있으면 그대로 씀) → final.snapshot.json, 그 틱 = F
      ② 그 스냅숏에서 두 갈래를 F + --ticks 틱까지: OUT/same/seed<N>(그대로)·OUT/fork/seed<N>(--set 들을 --fork-set 으로,
         --reset-learned 면 --fork-reset-learned 도 — 이식 시험, DESIGN-v0.2 11.2)
      ③ 창 [F, F + N) 의 지표(ABLATE_METRICS)를 견준 표 → OUT/ablate.csv·ablate.md, 조건 → OUT/ablate.json(baldwin 이 읽음).
         같은 명령을 다시 돌리면 같은 표.
    기준 실행이 그 세대 전에 멸종했거나 틱 상한에 닿은 씨앗은 빼고 표에 적는다. 종료 코드: 0 성공, 1 실패한 실행이 있음, 2 인자·저장소 오류."""
    repo = Path(args.repo).resolve()
    err = _check_repo(repo)
    if err:
        print("오류: " + err, file=sys.stderr)
        return 2
    if not args.set and not args.reset_learned:
        print("오류: 바꾼 갈래에 줄 것이 없습니다(--set 또는 --reset-learned)", file=sys.stderr)
        return 2
    godot = resolve_godot(args.godot)
    runs_root = Path(args.runs).resolve()
    tag = "__".join(([cell_dirname(list(args.set))] if args.set else []) + ([ABLATE_RESET_TAG] if args.reset_learned else [])) \
        + f"__g{args.at_gen}__t{args.ticks}"
    out_root = Path(args.out).resolve() if args.out else runs_root.parent / f"{runs_root.name}-ablate" / tag
    for d, what in ((runs_root, "--runs"), (out_root, "--out")):
        err = make_out_dir(d, what)
        if err:
            print("오류: " + err, file=sys.stderr)
            return 2
    # ① 기준 실행(analyze.py run 과 같은 폴더 꼴 — 이미 있으면 설정을 맞춰 보고 그대로 씀)
    base = []
    for seed in args.seeds:
        d = runs_root / f"seed{seed}"
        cmd = build_command(godot, repo, seed, args.at_gen, d, args.preset, args.base_set, False, None)
        base.append(Job(ROOT_CELL, seed, d, cmd, args.preset, args.at_gen, list(args.base_set), None))
    print(f"① 기준 실행: 평균 {args.at_gen}세대까지 → {runs_root}")
    failed = run_jobs(base, runs_root, repo, args.jobs, args.timeout)
    # ② 갈래
    skipped: dict[int, str] = {}
    fork_tick: dict[int, int] = {}
    branches = []
    for seed in args.seeds:
        d = runs_root / f"seed{seed}"
        why = incomplete_reason(d) if (d / "summary.json").is_file() else "기준 실행 결과 없음"
        if not why and existing_mismatch(base[args.seeds.index(seed)]):
            why = "기준 실행의 설정이 다름(runs.csv 의 mismatch)"
        s = json.loads((d / "summary.json").read_text(encoding="utf-8-sig")) if not why else {}
        if not why and s.get("end_reason") != "generations":
            why = (f"기준 실행이 평균 {args.at_gen}세대 전에 끝남"
                   f"({END_REASON_KO.get(str(s.get('end_reason')), s.get('end_reason'))}, 틱 {s.get('tick')})")
        if why:
            skipped[seed] = why
            continue
        f = int(s["tick"])
        fork_tick[seed] = f
        snap = d / "final.snapshot.json"
        for branch, forks, reset in ((ABLATE_SAME, [], False), (ABLATE_FORK, list(args.set), args.reset_learned)):
            od = out_root / branch / f"seed{seed}"
            cmd = build_resume_command(godot, repo, snap, f + args.ticks, od, forks, True, reset)
            branches.append(Job(branch, seed, od, cmd, "", ABLATE_GENERATIONS, [], f + args.ticks, str(snap), forks, reset))
    print(f"② 갈래: 그대로·바꿈({ablate_change_text(args)}) × 씨앗 {len(fork_tick)}개, "
          f"갈라진 틱부터 {args.ticks}틱 → {out_root}")
    if branches:
        failed += run_jobs(branches, out_root, repo, args.jobs, args.timeout)
    # ③ 견주기(두 갈래가 모두 끝까지 쓴 씨앗만). 실패한 갈래는 종료 코드와 run.log 의 오류 줄을 까닭에 붙임
    pairs = []
    branch_rows = read_runs_csv(out_root / "runs.csv")
    for seed in sorted(fork_tick):
        dirs = [out_root / b / f"seed{seed}" for b in (ABLATE_SAME, ABLATE_FORK)]
        bad = [incomplete_reason(x) if (x / "summary.json").is_file() else "결과 없음" for x in dirs]
        if any(bad):
            why = []
            for b, w, x in zip((ABLATE_SAME, ABLATE_FORK), bad, dirs):
                if w:
                    det = failure_detail(x, branch_rows.get((b, seed)))
                    why.append(f"{b}: {w}" + (f" ({det})" if det else ""))
            skipped[seed] = "갈래 실행 실패: " + "; ".join(why)
            continue
        pairs.append((seed, fork_tick[seed], ablate_metrics(dirs[0], fork_tick[seed], args.ticks),
                      ablate_metrics(dirs[1], fork_tick[seed], args.ticks)))
    table, md_rows = ablate_table(pairs)
    write_csv(table, out_root / "ablate.csv")
    write_ablate_md(out_root / "ablate.md", args, runs_root, pairs, md_rows, skipped, out_root)
    meta = {"runs": str(runs_root), "preset": args.preset, "base_set": [list(kv) for kv in args.base_set],
            "at_gen": args.at_gen, "ticks": args.ticks, "set": [list(kv) for kv in args.set],
            "reset_learned": bool(args.reset_learned), "seeds": list(args.seeds)}
    (out_root / ABLATE_META).write_text(json.dumps(meta, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
    print(f"표: {out_root / 'ablate.md'}  (씨앗 {len(pairs)}개, 뺀 씨앗 {len(skipped)}개)")
    print(_md_table(["지표", "씨앗", "그대로", "바꿈", "차이 중앙값 [Q1–Q3]", "바꿈 > · < 그대로"], md_rows,
                    ["l", "r", "r", "r", "r", "r"]))
    if not pairs:
        print("오류: 견줄 수 있는 씨앗이 없습니다", file=sys.stderr)
        return 1
    return 1 if failed else 0


def ablate_change_text(args) -> str:
    """바꾼 갈래에 준 것(보고서·진행 출력): --set 키=값들과 --reset-learned."""
    parts = [f"{k}={v}" for k, v in args.set]
    if args.reset_learned:
        parts.append("--fork-reset-learned(배운 두뇌를 타고난 것으로)")
    return ", ".join(parts)


def write_ablate_md(path: Path, args, runs_root: Path, pairs: list, md_rows: list[list[str]], skipped: dict[int, str],
                    out_root: Path) -> None:
    """ablate.md: 조건, 지표 차이 표, 씨앗별 갈라진 틱과 두 갈래의 끝 해시, 뺀 씨앗, 읽는 법."""
    sets = ", ".join([f"`{k}={v}`" for k, v in args.set]
                     + (["`--fork-reset-learned`(살아 있는 개체의 배운 두뇌 = 유전체, 기준선 0, 고리 비움 — 이식 시험)"]
                        if args.reset_learned else []))
    base_sets = ", ".join(f"`{k}={v}`" for k, v in args.base_set) or "없음"
    out = ["# 반사실 재생(ablate) 보고서", "",
           f"- 기준 실행: `{runs_root.name}` — 예설정 `{args.preset}`, 덮어쓰기 {base_sets}, 평균 {args.at_gen}세대까지(끝 스냅숏의 틱 = F)",
           f"- 바꾼 갈래(`{ABLATE_FORK}`): {sets} · 그대로 갈래(`{ABLATE_SAME}`): 바꾸지 않음 · 둘 다 F 부터 {args.ticks}틱",
           f"- 씨앗 {', '.join(str(s) for s, *_ in pairs) or '없음'} (견준 {len(pairs)}개)",
           "- 표: [`ablate.csv`](ablate.csv)(씨앗·지표마다 그대로·바꿈·차이). 갈래 결과는 이 폴더의 "
           f"`{ABLATE_SAME}/`·`{ABLATE_FORK}/`(`analyze.py report` 로 보고서를 만들 수 있음).", "",
           "## 지표 차이(바꿈 − 그대로)", ""]
    out.append(_md_table(["지표", "씨앗", "그대로 중앙값", "바꿈 중앙값", "차이 중앙값 [Q1–Q3]", "바꿈 > · < 그대로(씨앗)"],
                         md_rows, ["l", "r", "r", "r", "r", "r"]))
    out += ["", "## 씨앗별 갈라진 틱", ""]
    rows = []
    for seed, f, _, _ in pairs:
        h = []
        for b in (ABLATE_SAME, ABLATE_FORK):
            s = json.loads((out_root / b / f"seed{seed}" / "summary.json").read_text(encoding="utf-8-sig"))
            h.append(f"`{str(s.get('history_hash', ''))[:12]}`")
        rows.append([str(seed), f"{f:,}", *h])
    out.append(_md_table(["씨앗", "F(틱)", "그대로 끝 해시", "바꿈 끝 해시"], rows, ["r", "r", "l", "l"]))
    if skipped:
        out += ["", "## 뺀 씨앗", ""]
        out.append(_md_table(["씨앗", "까닭"], [[str(k), v] for k, v in sorted(skipped.items())], ["r", "l"]))
    out += ["", "## 읽는 법", "",
            "- 두 갈래는 같은 스냅숏(같은 세계·난수 상태)에서 설정 하나만 다르게 이어 돌린 쌍입니다(결정적 재생 — 같은 명령이면 같은 표). "
            "차이에는 그 설정의 직접 효과와, 행동이 달라져 갈라진 출생·먹이 고갈 같은 생태 되먹임이 함께 들어 있습니다.",
            "- 시계열 지표는 틱 (F, F + N] 의 줄(구간 출생·사망·행동 셈이 그 틱들 동안의 것), 대상 = 틱 [F, F + N) 에 태어난 개체"
            "(살아 있는 개체의 먹은 양·자식 수는 끝 틱까지의 값 — 수명이 창보다 길면 잘림).",
            "- 차이의 사분위는 numpy 기본(선형 보간)입니다. 씨앗이 적으면 거칠게 읽어야 합니다.", ""]
    path.write_text("\n".join(out), encoding="utf-8")


# ── 관문 A 판정(gate-a — DESIGN-v0.2 14.3) ──

## 판정 문턱(실행 전 고정 — 14.3·11.5, 명령 인자로 바꿀 수 없음. 보고서 머리에 그대로 인쇄). 씨앗 GATE_A_SEEDS 개 기준이라 씨앗 수가
## 다르면 판정하지 않는다(값만 적음). A-1 의 대상 출생 틱 구간·대상 수 하한은 위의 GATE_A_BIRTH_WINDOW·GATE_A_MIN_BIRTHS(A-2 의 대상 수
## 하한도 같음), GATE_A_TICKS 는 처음 정의(A-1)의 생존 틱.
GATE_A_WIN = 10
## ① 의 묶은 먹은 양 중앙값 비(학습 ÷ freeze) 하한 — A-1(공식 A-1-life 와 처음 정의 A-1)만. A-2 의 통과 기준(14.3)에는 비 문턱이 없음(보고)
GATE_A_RATIO = 1.05
GATE_A_SECONDARY_WIN = 8
GATE_A_SEEDS = 12
## ② 생존·번식의 지표(지표마다 부호 셈 — 하나라도 학습 쪽이 높은 씨앗 ≥ GATE_A_SECONDARY_WIN 이면 충족). 생존 = 평균 산 나이(대상의 죽은
## 나이 death_tick − birth_tick 의 평균, 묶은 값도 평균). 사전 결정(설계 운영자 2026-10-11, 판정 실행 전 — 14.3): 처음 정의의 '성숙까지
## 산 몫'은 기본값에서 늘 1.000 이라 갈래를 가르지 못해(1단계 검증) 표에 보고만 한다.
GATE_A_SECONDARY = ("life", "children")
## A-1-life 의 틱 상한: 대상(틱 GATE_A_BIRTH_WINDOW 출생)이 모두 죽을 때까지 — 최대 수명(life.max_age 200 + 흔들림 30)이면 830틱 전에
## 모두 죽으므로 넉넉한 끝. 그 전에 멸종하면 실행기가 멈춤. 끝에 살아 있는 대상이 있으면 그 씨앗은 판정 불가(평생 값이 잘림)
GATE_A_LIFE_MAX_TICKS = 1500
## 관문 A 세계(14.3 A-1): 우연 기준 예설정 + 학습 + 몸 자람(A-2 의 learn_basic 과 같은 몸). A-2 의 기준 행(우연 기준)도 이 세계
GATE_A_PRESET = "chance_baseline"
GATE_A_BASE_SETS = [("learn.enabled", "true"), ("body.grow_enabled", "true")]
## 공식 A-1 판정 조건(사용자 결정 2026-10-11 — 14.3) = gate-a 의 기본 --variant
GATE_A_OFFICIAL = "A-1-life"
## A-2(14.3 — 보고): 예설정 GATE_A2_PRESET 을 평균 GATE_A2_AT_GEN 세대까지(끝 스냅숏의 틱 = F), 그 스냅숏에서 두 갈래를 F + GATE_A2_TICKS
## 까지, 대상 = 틱 [F, F + GATE_A2_WINDOW) 출생(F + 330 전에 모두 죽음). 기준 실행은 OUT/GATE_A2_BASE/seed<N>
GATE_A2_PRESET = "learn_basic"
GATE_A2_AT_GEN = "30"
GATE_A2_TICKS = 340
GATE_A2_WINDOW = 100
GATE_A2_BASE = "base"
## 판정 조건의 이름 붙은 변형. kind = "start"(틱 0 부터 세 갈래) · "fork"(A-2 — 기준 실행의 끝 스냅숏에서 갈라짐). need_ticks = 대상과
## 상관없이 그 틱까지 살아야 판정(0 = 요구 없음), max_ticks = 실행기 --max-ticks(틱 0 부터, 그 전에 멸종하면 멈춤). ratio = ① 에
## GATE_A_RATIO 문턱을 쓰나. strict = 판정 불가 씨앗이 하나라도 있으면 변형 전체가 판정 불가(A-1) — 거짓이면 남은 씨앗으로 문턱을 세고
## 판정 불가 씨앗은 높은 씨앗으로 세지 않음(A-2 — 14.3 '씨앗 단위 판정 불가는 표에 그대로').
GATE_A_VARIANTS = {
    "A-1": {"kind": "start", "sets": GATE_A_BASE_SETS, "max_ticks": GATE_A_TICKS, "need_ticks": GATE_A_TICKS,
            "ratio": True, "strict": True,
            "text": f"처음 정의(공식 아님 — 0단계 미리 보기에서 판정 불가로 보여 바꿈, 14.3) — 틱 0 부터 {GATE_A_TICKS:,}틱, "
                    f"두 갈래 모두 {GATE_A_TICKS:,}틱까지 살고 대상 ≥ {GATE_A_MIN_BIRTHS}"},
    "A-1-life": {"kind": "start", "sets": GATE_A_BASE_SETS + [("population.initial", "400"), ("population.cap", "400"),
                                                              ("plants.initial_fill", "1.0")],
                 "max_ticks": GATE_A_LIFE_MAX_TICKS, "need_ticks": 0, "ratio": True, "strict": True,
                 "text": f"공식 A-1(사용자 결정 2026-10-11 — A-1′ 세계에서 생존 틱 요구를 뺌) — 두 갈래 모두 대상 ≥ {GATE_A_MIN_BIRTHS}, "
                         f"대상이 모두 죽을 때까지(또는 멸종까지, 최대 {GATE_A_LIFE_MAX_TICKS:,}틱)"},
    "A-2": {"kind": "fork", "ratio": False, "strict": False,
            "text": f"A-2(보고 — 진화한 두뇌에서도 득인가) — `{GATE_A2_PRESET}` 을 평균 {GATE_A2_AT_GEN}세대까지(끝 스냅숏의 틱 = F), "
                    f"그 스냅숏에서 그대로·freeze 를 F + {GATE_A2_TICKS} 까지, 두 갈래 모두 대상 ≥ {GATE_A_MIN_BIRTHS}"},
}
## 갈래: (폴더·csv 이름, 보고서 이름, 더하는 설정). 학습 = 배우는 쪽, freeze = 학습을 멈춘 대조(비용은 냄), 학습 끔 = 비용까지 뺀 셋째 행
GATE_A_BRANCHES = [("learn", "학습", [("learn.freeze", "false")]), ("freeze", "freeze", [("learn.freeze", "true")]),
                   ("off", "학습 끔", [("learn.enabled", "false")])]
## A-2 의 갈래: 학습 = 스냅숏을 그대로 이어 돌림, freeze = 스냅숏에서 --fork-set(이 설정), 우연 기준(셋째 행 — 기준 행) = 같은 씨앗의
## 우연 기준 세계(GATE_A_PRESET + 이 설정 — learn_basic 과 유전만 다름)를 틱 0 부터 F + GATE_A2_TICKS 까지 따로 돌림
GATE_A2_BRANCHES = [("learn", "학습(그대로)", []), ("freeze", "freeze", [("learn.freeze", "true")]),
                    ("chance", "우연 기준", GATE_A_BASE_SETS)]
## 판정에 쓰는 두 갈래(셋째 행은 보고만)
GATE_A_JUDGED = ("learn", "freeze")
## 보조 판(--aux, 14.3): 학습·freeze 갈래를 learn.diag_factor = none 으로 — 보고만, 판정에 쓰지 않음(A-1 계열만)
GATE_A_AUX_SETS = [("learn.diag_factor", "none")]
## gate_a.csv 열(씨앗·갈래마다 한 줄). birth_lo·birth_hi = 대상 출생 틱 [lo, hi)
GATE_A_COLUMNS = ["seed", "branch", "status", "birth_lo", "birth_hi", "end_reason", "ticks", "extinct_tick", "targets",
                  "targets_alive", "eaten_median", "eaten_mean", "life_mean", "children_mean", "matured_share", "history_hash"]
GATE_A_INT_COLUMNS = ["seed", "birth_lo", "birth_hi", "ticks", "extinct_tick", "targets", "targets_alive"]
## 지표: (키, 보고서 이름, 소수 자리). 판정에서의 쓰임은 gate_a_role(① 먹은 양 · ② GATE_A_SECONDARY · 나머지는 보고만)
GATE_A_METRICS = [("eaten", "평생 먹은 양(중앙값)", 2), ("life", "평균 산 나이(틱)", 2), ("children", "평균 자식 수", 3),
                  ("matured", "성숙까지 산 몫", 3)]
## 지표 → gate_a.csv 의 씨앗·갈래 값 열
GATE_A_METRIC_COLUMNS = {"eaten": "eaten_median", "life": "life_mean", "children": "children_mean", "matured": "matured_share"}
## 사전 고정 줄(prereg_text)의 git 명령 하나의 시간 제한(초)
PREREG_GIT_TIMEOUT = 60
## 씨앗·갈래 상태 → 보고서 표기
GATE_A_RUN_STATUS_KO = {"ok": "조건 채움", "extinct": "생존 틱 전 멸종", "short": "생존 틱 전에 끝남", "few": "대상 모자람",
                        "alive": "끝에 대상이 살아 있음", "nolineage": "lineage.csv 없음", "failed": "실행 실패",
                        "nobase": "기준 실행 없음(갈래 안 돌림)"}


def gate_a_role(key: str) -> str:
    """지표의 판정 쓰임: "①"(먹은 양) · "②"(GATE_A_SECONDARY) · "보고"(판정에 쓰지 않음)."""
    return "①" if key == "eaten" else ("②" if key in GATE_A_SECONDARY else "보고")


def gate_a_branches(variant: str) -> list:
    """변형의 갈래 목록(A-2 는 GATE_A2_BRANCHES, 나머지는 GATE_A_BRANCHES). 셋째 갈래 = 보고만 하는 셋째 행."""
    return GATE_A2_BRANCHES if GATE_A_VARIANTS[variant]["kind"] == "fork" else GATE_A_BRANCHES


def gate_a_branch_sets(variant: str, branch: str, aux: bool) -> list[tuple[str, str]]:
    """A-1 계열 갈래 하나의 덮어쓰기(변형의 설정 → 갈래 설정 → 보조 판 설정 순, 같은 키는 뒤의 값 — 실행기와 같은 규칙)."""
    sets = dict(GATE_A_VARIANTS[variant]["sets"])
    sets.update(dict(next(b[2] for b in GATE_A_BRANCHES if b[0] == branch)))
    if aux and branch in GATE_A_JUDGED:
        sets.update(dict(GATE_A_AUX_SETS))
    return list(sets.items())


def gate_a_run(run_dir: Path, window: tuple[int, int], need: int) -> tuple[dict, dict[str, np.ndarray]]:
    """결과 폴더 하나(끝까지 쓴 실행) → (gate_a.csv 한 줄의 값, 대상 개체 값 배열 {eaten, life, children, matured}).
    대상 = 틱 [window) 에 태어난 개체(처음 개체 제외). 산 나이 = 죽은 나이(death_tick − birth_tick — 끝에 살아 있으면 끝 틱까지, 그런 대상이
    있으면 상태 alive 라 판정에 쓰지 않음). 성숙까지 산 = 산 나이 > repro.maturity — 나이를 더한 뒤 번식 자격(나이 ≥ 성숙)을 갖고 그 틱의
    번식 단계에 살아서 닿음(DESIGN-v0.1 8.4 틱 기준, sim_world.gd _act·_eligible).
    상태: ok · extinct(need 틱 전 멸종) · short(멸종 없이 need 틱 전에 끝남) · few(대상 < GATE_A_MIN_BIRTHS) ·
    alive(끝에 살아 있는 대상 — 평생 값이 잘림) · nolineage. need = 0 이면 생존 틱 요구 없음."""
    s = json.loads((run_dir / "summary.json").read_text(encoding="utf-8-sig"))
    ext, ticks = _int_or(s.get("extinct_tick")), _int_or(s.get("tick"), 0)
    lo, hi = window
    row = {"status": "ok", "birth_lo": lo, "birth_hi": hi, "end_reason": s.get("end_reason", ""), "ticks": ticks,
           "extinct_tick": ext, "targets": 0, "targets_alive": 0, "eaten_median": float("nan"), "eaten_mean": float("nan"),
           "life_mean": float("nan"), "children_mean": float("nan"), "matured_share": float("nan"),
           "history_hash": str(s.get("history_hash", ""))[:12]}
    vals = {k: np.zeros(0) for k, _, _ in GATE_A_METRICS}
    lin = read_lineage(run_dir / "lineage.csv")
    if lin is None or "eaten" not in lin.columns:
        row["status"] = "nolineage"
        return row, vals
    tg = lin[(lin["parent_a"] >= 0) & (lin["birth_tick"] >= lo) & (lin["birth_tick"] < hi)]
    maturity = int(((s.get("config", {}) or {}).get("repro", {}) or {}).get("maturity", 0))
    dead = tg["death_tick"].to_numpy(dtype=int) >= 0
    life = np.where(dead, tg["death_tick"].to_numpy(dtype=int), ticks) - tg["birth_tick"].to_numpy(dtype=int)
    vals = {"eaten": pd.to_numeric(tg["eaten"], errors="coerce").to_numpy(dtype=float), "life": life.astype(float),
            "children": tg["children"].to_numpy(dtype=float), "matured": (life > maturity).astype(float)}
    n = len(tg)
    row.update({"targets": n, "targets_alive": int((~dead).sum())})
    if n:
        row.update({"eaten_median": float(np.nanmedian(vals["eaten"])), "eaten_mean": float(np.nanmean(vals["eaten"])),
                    "life_mean": float(vals["life"].mean()), "children_mean": float(vals["children"].mean()),
                    "matured_share": float(vals["matured"].mean())})
    if need and 0 <= ext < need:
        row["status"] = "extinct"
    elif need and ext < 0 and ticks < need:
        row["status"] = "short"
    elif n < GATE_A_MIN_BIRTHS:
        row["status"] = "few"
    elif row["targets_alive"] > 0:
        row["status"] = "alive"
    return row, vals


def _pooled(vals: list[dict], key: str) -> float:
    """씨앗들의 대상 값을 묶은 값: 먹은 양은 중앙값, 나머지(평균 산 나이·자식 수·성숙까지 산 몫)는 평균. 대상이 없으면 NaN."""
    arr = np.concatenate([v[key] for v in vals]) if vals else np.zeros(0)
    arr = arr[~np.isnan(arr)]
    if not arr.size:
        return float("nan")
    return float(np.median(arr)) if key == "eaten" else float(arr.mean())


def _status_detail(row: dict) -> str:
    """판정 불가·셋째 행 없음의 까닭에 붙이는 자세한 값."""
    return {"extinct": f"{row.get('extinct_tick')}틱 멸종", "short": f"{row.get('ticks')}틱에 끝남",
            "few": f"대상 {row.get('targets')}", "alive": f"대상 {row.get('targets_alive')}명이 끝에 살아 있음",
            "nolineage": "lineage.csv 없음", "failed": row.get("why", ""), "nobase": row.get("why", "")}.get(row["status"], "")


def gate_a_evaluate(seeds: list[int], runs: dict[tuple[str, int], tuple[dict, dict]], variant: str, aux: bool) -> dict:
    """씨앗·갈래 결과 → 판정. runs[(갈래, 씨앗)] = gate_a_run 의 결과(실행 실패면 ({status: failed, why}, {}), A-2 의 기준 실행이 없으면
    ({status: nobase, why}, {})). 판정 가능한 씨앗 = 판정 갈래(GATE_A_JUDGED) 둘 다 ok. 셋째 행(A-1 학습 끔 · A-2 우연 기준)은 그 갈래도
    ok 인 판정 가능 씨앗만 묶고 셈(못 채운 씨앗은 third_missing). 결과: {verdict, judged, unjudged{씨앗: 까닭}, third, third_missing,
    wins{지표: (학습 > freeze, 학습 > 셋째)}, pooled{(갈래, 지표): 값}, ratio, crit1, crit2, ties}."""
    spec = GATE_A_VARIANTS[variant]
    branches = gate_a_branches(variant)
    names = {b: n for b, n, _ in branches}
    third = branches[2][0]
    missing = ({"status": "failed", "why": "결과 없음"}, {})
    unjudged: dict[int, str] = {}
    for seed in seeds:
        rows = [runs.get((b, seed), missing)[0] for b in GATE_A_JUDGED]
        nobase = [r for r in rows if r["status"] == "nobase"]
        if nobase:
            unjudged[seed] = nobase[0].get("why", "") or GATE_A_RUN_STATUS_KO["nobase"]
            continue
        why = []
        for b, row in zip(GATE_A_JUDGED, rows):
            if row["status"] != "ok":
                detail = _status_detail(row)
                why.append(f"{names[b]}: {GATE_A_RUN_STATUS_KO[row['status']]}" + (f"({detail})" if detail else ""))
        if why:
            unjudged[seed] = "; ".join(why)
    judged = [s for s in seeds if s not in unjudged]
    third_ok = [s for s in judged if runs.get((third, s), missing)[0]["status"] == "ok"]
    third_missing = {}
    for s in judged:
        if s not in third_ok:
            row = runs.get((third, s), missing)[0]
            detail = _status_detail(row)
            third_missing[s] = GATE_A_RUN_STATUS_KO.get(row["status"], str(row["status"])) + (f"({detail})" if detail else "")
    pooled = {}
    for b, _, _ in branches:
        vs = [runs[(b, s)][1] for s in (third_ok if b == third else judged) if (b, s) in runs and runs[(b, s)][1]]
        for key, _, _ in GATE_A_METRICS:
            pooled[(b, key)] = _pooled(vs, key)
    col = GATE_A_METRIC_COLUMNS
    wins = {}
    for key, _, _ in GATE_A_METRICS:
        w = []
        for other, among in (("freeze", judged), (third, third_ok)):
            k = 0
            for s in among:
                a = runs[("learn", s)][0][col[key]]
                o = runs[(other, s)][0][col[key]]
                k += int(not (math.isnan(a) or math.isnan(o)) and a > o)
            w.append(k)
        wins[key] = tuple(w)
    # 갈래를 가르지 못한 지표: 판정 가능 씨앗 모두에서 학습 값 = freeze 값(같으면 이긴 씨앗으로 세지 않으므로 그 지표로는 문턱에 닿을 수
    # 없음 — 1단계 검증: 기본값에서는 자식이 부모에게 받은 에너지만으로 성숙 나이보다 오래 살아 성숙까지 산 몫이 늘 1). 값 = 그 같은 값들
    ties = {}
    for key, _, _ in GATE_A_METRICS:
        pairs = [(runs[("learn", s)][0][col[key]], runs[("freeze", s)][0][col[key]]) for s in judged]
        same = bool(pairs) and all(not (math.isnan(a) or math.isnan(o)) and a == o for a, o in pairs)
        ties[key] = sorted({float(a) for a, _ in pairs}) if same else None
    fr = pooled[("freeze", "eaten")]
    ratio = pooled[("learn", "eaten")] / fr if fr and not math.isnan(fr) else float("nan")
    crit1 = wins["eaten"][0] >= GATE_A_WIN and (not spec["ratio"] or (not math.isnan(ratio) and ratio >= GATE_A_RATIO))
    crit2 = any(wins[key][0] >= GATE_A_SECONDARY_WIN for key in GATE_A_SECONDARY)
    if aux:
        verdict = "보조 판 — 판정에 쓰지 않음(learn.diag_factor = none, 14.3)"
    elif len(seeds) != GATE_A_SEEDS:
        verdict = f"판정 안 함 — 씨앗 {len(seeds)}개(문턱은 씨앗 {GATE_A_SEEDS}개 기준, 14.3)"
    elif unjudged and (spec["strict"] or not judged):
        verdict = f"판정 불가 — 씨앗 {len(unjudged)}개({', '.join(str(s) for s in sorted(unjudged))})가 조건을 채우지 못함"
        if variant == "A-1":
            verdict += f"(처음 정의 — 14.3 은 이때 A-1′ 를 같은 문턱으로 돌림. 공식 조건은 {GATE_A_OFFICIAL})"
    else:
        verdict = "통과" if crit1 and crit2 else "실패"
        if unjudged:
            verdict += (f"(판정 가능 씨앗 {len(judged)}/{len(seeds)} — 판정 불가 씨앗 {len(unjudged)}개"
                        f"({', '.join(str(s) for s in sorted(unjudged))})는 높은 씨앗으로 세지 않음)")
    return {"verdict": verdict, "judged": judged, "unjudged": unjudged, "third": third, "third_ok": third_ok,
            "third_missing": third_missing, "wins": wins, "pooled": pooled, "ratio": ratio, "crit1": crit1, "crit2": crit2,
            "ties": ties}


def prereg_text(commit: str | None, tool: Path | None = None) -> str:
    """보고서 머리의 '사전 고정' 줄. commit = --prereg(판정 문턱·지표를 판정 실행 전에 고정한 커밋 — DESIGN-v0.2 14 절 판정 규칙).
    git 으로 그 커밋을 찾고, 지금 도는 tool(기본 이 파일)이 그 커밋의 것과 같은지 본다: 그 커밋의 파일 blob 해시 = 지금 파일의
    git hash-object --path(줄 끝 변환 설정을 따름, 인덱스를 쓰지도 믿지도 않음 — 같은 초에 고친 파일도 가려냄).
    git 이 없거나 저장소 밖·없는 커밋이면 '확인 못 함'."""
    if not commit:
        return "주지 않음(`--prereg 커밋` — 공식 판정은 사전 고정 커밋을 주고 돌림, DESIGN-v0.2 14 절 판정 규칙)"
    tool = (tool or Path(__file__)).resolve()

    def git(*a: str) -> subprocess.CompletedProcess:
        return subprocess.run(["git", *a], cwd=str(tool.parent), capture_output=True, encoding="utf-8", errors="replace",
                              timeout=PREREG_GIT_TIMEOUT)
    try:
        top = git("rev-parse", "--show-toplevel")
        if top.returncode != 0:
            return f"커밋 `{commit}` — 확인 못 함(git 저장소 밖: {tool.parent})"
        full = git("rev-parse", "--verify", "--quiet", f"{commit}^{{commit}}")
        if full.returncode != 0:
            return f"커밋 `{commit}` — 확인 못 함(저장소에 그런 커밋이 없음)"
        h = full.stdout.strip()
        subject = git("log", "-1", "--format=%s", h).stdout.strip()
        rel = Path(os.path.relpath(tool, top.stdout.strip())).as_posix()
        then = git("rev-parse", "--verify", "--quiet", f"{h}:{rel}")
        now = git("hash-object", f"--path={rel}", str(tool))
    except (OSError, subprocess.SubprocessError) as e:
        return f"커밋 `{commit}` — 확인 못 함(git 을 실행하지 못함: {e})"
    if now.returncode != 0:
        return f"커밋 `{h[:12]}`({subject}) — 확인 못 함(git hash-object 종료 코드 {now.returncode})"
    same = then.returncode == 0 and then.stdout.strip() == now.stdout.strip()
    return (f"커밋 `{h[:12]}`({subject}) — 지금 도는 `{rel}` 가 그 커밋의 것과 "
            + ("같음" if same else "**다름**(사전 고정 뒤 판정 코드가 바뀜 — 이 보고서는 사전 고정대로의 판정이 아님)"))


def _gate_a_collect(job: Job, rows_csv: dict, window: tuple[int, int], need: int) -> tuple[dict, dict]:
    """갈래 실행 하나의 결과 → (gate_a.csv 한 줄의 값, 대상 값). 끝까지 쓰지 못했거나 설정이 다른 결과는 failed(까닭에 종료 코드·오류 줄)."""
    why = incomplete_reason(job.out_dir) if (job.out_dir / "summary.json").is_file() else "결과 없음"
    if not why and existing_mismatch(job):
        why = "설정이 다른 결과(runs.csv 의 mismatch)"
    if why:
        det = failure_detail(job.out_dir, rows_csv.get((job.cell, job.seed)))
        row = {c: float("nan") for c in GATE_A_COLUMNS}
        row.update({"status": "failed", "why": why + (f" ({det})" if det else ""), "birth_lo": window[0], "birth_hi": window[1],
                    "end_reason": "", "history_hash": ""})
        return row, {}
    return gate_a_run(job.out_dir, window, need)


def cmd_gate_a(args) -> int:
    """gate-a: 관문 A(DESIGN-v0.2 14.3)의 변형 하나(기본 = 공식 A-1 GATE_A_OFFICIAL)를 씨앗마다 돌리고(같은 설정의 끝까지 쓴 결과가
    있으면 그대로 씀) 대상 개체의 평생 먹은 양·평균 산 나이·자식 수(와 보고만 하는 성숙까지 산 몫)를 견줘 OUT/gate_a.csv·gate_a.md 를 쓴다.
      A-1 계열: 세 갈래(학습·freeze·학습 끔)를 틱 0 부터.
      A-2: ① OUT/base/seed<N> 에 learn_basic 을 평균 30세대까지(끝 스냅숏 틱 F) ② 그 스냅숏에서 학습(그대로)·freeze 를 F + 340 까지,
           우연 기준 세계를 틱 0 부터 F + 340 까지 ③ 대상 [F, F + 100) 출생.
    판정 문턱은 GATE_A_* 상수(명령 인자로 바꿀 수 없음), --prereg 는 보고서 머리의 사전 고정 줄(prereg_text).
    종료 코드: 0 보고서를 씀(판정 결과와 상관없이), 1 실패한 실행이 있음, 2 인자·저장소 오류."""
    repo = Path(args.repo).resolve()
    err = _check_repo(repo)
    if err:
        print("오류: " + err, file=sys.stderr)
        return 2
    spec = GATE_A_VARIANTS[args.variant]
    if args.aux and spec["kind"] != "start":
        print(f"오류: --aux(보조 판)는 A-1 계열 변형만입니다(14.3 — {args.variant} 는 아님)", file=sys.stderr)
        return 2
    godot = resolve_godot(args.godot)
    out_root = Path(args.out).resolve()
    err = make_out_dir(out_root)
    if err:
        print("오류: " + err, file=sys.stderr)
        return 2
    prereg = prereg_text(args.prereg)
    branches = gate_a_branches(args.variant)
    runs: dict[tuple[str, int], tuple[dict, dict]] = {}
    if spec["kind"] == "fork":
        failed = _gate_a2_run_all(args, repo, godot, out_root, runs)
    else:
        jobs = []
        for b, _, _ in branches:
            for seed in args.seeds:
                d = out_root / b / f"seed{seed}"
                sets = gate_a_branch_sets(args.variant, b, args.aux)
                cmd = build_command(godot, repo, seed, ABLATE_GENERATIONS, d, GATE_A_PRESET, sets, True, spec["max_ticks"])
                jobs.append(Job(b, seed, d, cmd, GATE_A_PRESET, ABLATE_GENERATIONS, sets, spec["max_ticks"]))
        print(f"관문 A 변형 {args.variant}{' (보조 판)' if args.aux else ''}: 갈래 {len(branches)}개 × 씨앗 {len(args.seeds)}개 → {out_root}")
        failed = run_jobs(jobs, out_root, repo, args.jobs, args.timeout)
        rows_csv = read_runs_csv(out_root / "runs.csv")
        for job in jobs:
            runs[(job.cell, job.seed)] = _gate_a_collect(job, rows_csv, GATE_A_BIRTH_WINDOW, int(spec["need_ticks"]))
    table = []
    for b, _, _ in branches:
        for seed in args.seeds:
            r = runs.get((b, seed), ({"status": "failed", "why": "결과 없음"}, {}))[0]
            table.append({"seed": seed, "branch": b, **{c: r.get(c, float("nan")) for c in GATE_A_COLUMNS[2:]}})
    ev = gate_a_evaluate(list(args.seeds), runs, args.variant, args.aux)
    df = pd.DataFrame(table, columns=GATE_A_COLUMNS)
    for c in GATE_A_INT_COLUMNS:
        df[c] = pd.to_numeric(df[c], errors="coerce").round().astype("Int64")
    write_csv(df, out_root / "gate_a.csv")
    write_gate_a_md(out_root / "gate_a.md", args, runs, ev, prereg)
    print(f"사전 고정: {prereg}")
    print(f"판정: {ev['verdict']}")
    print(f"보고서: {out_root / 'gate_a.md'}")
    return 1 if failed else 0


def _gate_a2_run_all(args, repo: Path, godot: str, out_root: Path, runs: dict) -> int:
    """A-2 의 실행(14.3·11.4 의 실행 순서)과 결과 모으기 → runs 를 채우고 실패 수를 돌려준다.
    ① 기준 실행 OUT/base/seed<N>: GATE_A2_PRESET 을 평균 GATE_A2_AT_GEN 세대까지(lineage 없음 — 대상은 갈래가 씀). 그 전에 끝난 씨앗
       (멸종·틱 상한)·실패한 씨앗은 갈래를 돌리지 않고 nobase(판정 불가).
    ② 끝 스냅숏(틱 F)에서 학습(그대로)·freeze(--fork-set) 를 F + GATE_A2_TICKS 까지, 우연 기준 세계를 같은 씨앗으로 틱 0 부터
       F + GATE_A2_TICKS 까지(--max-ticks — 그 전에 멸종하면 그 씨앗의 기준 행은 없음: 생존 틱 요구 F + GATE_A2_TICKS).
    ③ 대상 = 틱 [F, F + GATE_A2_WINDOW) 출생. 판정 갈래에는 생존 틱 요구가 없음(A-1-life 와 같음)."""
    base_jobs = []
    for seed in args.seeds:
        d = out_root / GATE_A2_BASE / f"seed{seed}"
        cmd = build_command(godot, repo, seed, GATE_A2_AT_GEN, d, GATE_A2_PRESET, [], False, None)
        base_jobs.append(Job(GATE_A2_BASE, seed, d, cmd, GATE_A2_PRESET, GATE_A2_AT_GEN, [], None))
    print(f"관문 A 변형 A-2: ① 기준 실행 {GATE_A2_PRESET} 평균 {GATE_A2_AT_GEN}세대 × 씨앗 {len(args.seeds)}개 → "
          f"{out_root / GATE_A2_BASE}")
    failed = run_jobs(base_jobs, out_root, repo, args.jobs, args.timeout)
    fork_tick: dict[int, int] = {}
    jobs: list[tuple[Job, int]] = []
    for job in base_jobs:
        seed, d = job.seed, job.out_dir
        why = incomplete_reason(d) if (d / "summary.json").is_file() else "기준 실행 결과 없음"
        if not why and existing_mismatch(job):
            why = "기준 실행의 설정이 다름(runs.csv 의 mismatch)"
        s = json.loads((d / "summary.json").read_text(encoding="utf-8-sig")) if not why else {}
        if not why and s.get("end_reason") != "generations":
            why = (f"기준 실행이 평균 {GATE_A2_AT_GEN}세대 전에 끝남"
                   f"({END_REASON_KO.get(str(s.get('end_reason')), s.get('end_reason'))}, 틱 {s.get('tick')})")
        if why:
            for b, _, _ in GATE_A2_BRANCHES:
                row = {c: float("nan") for c in GATE_A_COLUMNS}
                row.update({"status": "nobase", "why": why, "end_reason": "", "history_hash": ""})
                runs[(b, seed)] = (row, {})
            continue
        f = int(s["tick"])
        fork_tick[seed] = f
        end = f + GATE_A2_TICKS
        snap = d / "final.snapshot.json"
        for b, _, sets in GATE_A2_BRANCHES:
            od = out_root / b / f"seed{seed}"
            if b == "chance":
                cmd = build_command(godot, repo, seed, ABLATE_GENERATIONS, od, GATE_A_PRESET, sets, True, end)
                jobs.append((Job(b, seed, od, cmd, GATE_A_PRESET, ABLATE_GENERATIONS, list(sets), end), end))
            else:
                cmd = build_resume_command(godot, repo, snap, end, od, list(sets), True)
                jobs.append((Job(b, seed, od, cmd, "", ABLATE_GENERATIONS, [], end, str(snap), list(sets)), 0))
    print(f"② 갈래: {' · '.join(n for _, n, _ in GATE_A2_BRANCHES)} × 씨앗 {len(fork_tick)}개, F + {GATE_A2_TICKS} 까지 → {out_root}")
    if jobs:
        failed += run_jobs([j for j, _ in jobs], out_root, repo, args.jobs, args.timeout)
    rows_csv = read_runs_csv(out_root / "runs.csv")
    for job, need in jobs:
        f = fork_tick[job.seed]
        runs[(job.cell, job.seed)] = _gate_a_collect(job, rows_csv, (f, f + GATE_A2_WINDOW), need)
    return failed


def write_gate_a_md(path: Path, args, runs: dict, ev: dict, prereg: str) -> None:
    """gate_a.md: 변형·조건·사전 고정, 고정 문턱(GATE_A_* 그대로), 판정, 지표마다 세 행·두 차이·효과 크기(14.3 보고 꼴), 씨앗별 표,
    판정 불가 씨앗·셋째 행이 없는 씨앗, 읽는 법."""
    spec = GATE_A_VARIANTS[args.variant]
    branches = gate_a_branches(args.variant)
    names = {b: n for b, n, _ in branches}
    third = ev["third"]
    lo, hi = GATE_A_BIRTH_WINDOW
    head = [f"# 관문 A 보고서 — 변형 `{args.variant}`{' · 보조 판' if args.aux else ''}", "",
            f"- 변형: {spec['text']}"]
    if spec["kind"] == "fork":
        head += [f"- 기준 실행: 예설정 `{GATE_A2_PRESET}` 을 평균 {GATE_A2_AT_GEN}세대까지(`{GATE_A2_BASE}/seed<N>` — 끝 스냅숏의 틱 = F, "
                 "씨앗마다 다름)",
                 f"- 갈래: {names['learn']} = 스냅숏을 그대로 이어 돌림 · {names['freeze']} = "
                 f"`--fork-set={', '.join(f'{k}={v}' for k, v in branches[1][2])}` — 둘 다 같은 스냅숏에서 F + {GATE_A2_TICKS} 까지",
                 f"- 기준 행: {names[third]} — 같은 씨앗의 예설정 `{GATE_A_PRESET}` + "
                 f"{', '.join(f'`{k}={v}`' for k, v in branches[2][2])}(`{GATE_A2_PRESET}` 과 유전만 다름)를 틱 0 부터 F + {GATE_A2_TICKS} 까지 "
                 f"따로 — 그 전에 멸종했거나 대상 < {GATE_A_MIN_BIRTHS}·끝에 산 대상이 있으면 그 씨앗의 기준 행은 없음",
                 f"- 대상: 틱 [F, F + {GATE_A2_WINDOW}) 에 태어난 개체. 씨앗 {', '.join(str(s) for s in args.seeds)}",
                 "- A-2 는 보고입니다(관문 A 통과 = A-1 통과, 2단계로 갈지는 사용자가 판단 — 14.3)"]
    else:
        sets = ", ".join(f"`{k}={v}`" for k, v in spec["sets"])
        head += [f"- 세계: 예설정 `{GATE_A_PRESET}` + {sets}" + (f" + 학습·freeze 갈래에 {', '.join(f'`{k}={v}`' for k, v in GATE_A_AUX_SETS)}"
                                                               if args.aux else ""),
                 "- 갈래: " + " · ".join(f"{n}(`{', '.join(f'{k}={v}' for k, v in st)}`)" for _, n, st in branches)
                 + " — 같은 씨앗, 틱 0 부터",
                 f"- 대상: 틱 [{lo}, {hi}) 에 태어난 개체(처음 개체 제외). 씨앗 {', '.join(str(s) for s in args.seeds)}"]
    out = head + [f"- 사전 고정: {prereg}", f"- **판정: {ev['verdict']}**", "",
                  "## 고정 문턱(`analyze.py` 상수 — 명령 인자로 바꿀 수 없음)", ""]
    sec = " · ".join(n for k, n, _ in GATE_A_METRICS if k in GATE_A_SECONDARY)
    out.append(_md_table(["상수", "값", "뜻"], [
        ["`GATE_A_WIN`", str(GATE_A_WIN), "① 대상 먹은 양 중앙값이 학습 쪽에서 높은 씨앗 수 하한"],
        ["`GATE_A_RATIO`", f"{GATE_A_RATIO}", "① 씨앗들의 대상을 묶은 먹은 양 중앙값 비(학습 ÷ freeze) 하한 — A-1 만(A-2 는 보고)"],
        ["`GATE_A_SECONDARY_WIN`", str(GATE_A_SECONDARY_WIN), f"② {sec} 가운데 하나가 학습 쪽에서 높은 씨앗 수 하한(지표마다 셈)"],
        ["`GATE_A_SECONDARY`", ", ".join(f"`{k}`" for k in GATE_A_SECONDARY),
         "② 의 지표(사전 결정 2026-10-11 — 생존 = 평균 산 나이, 성숙까지 산 몫은 보고만)"],
        ["`GATE_A_MIN_BIRTHS`", str(GATE_A_MIN_BIRTHS), "씨앗·갈래마다 필요한 대상 수"],
        ["`GATE_A_SEEDS`", str(GATE_A_SEEDS), "문턱의 기준 씨앗 수(다르면 판정하지 않음)"],
        ["`GATE_A_BIRTH_WINDOW`", f"[{lo}, {hi})", "A-1: 대상 출생 틱"],
        ["`GATE_A_LIFE_MAX_TICKS`", f"{GATE_A_LIFE_MAX_TICKS:,}", f"{GATE_A_OFFICIAL}(공식 A-1): 틱 상한(그 전에 대상이 모두 죽음)"],
        ["`GATE_A_TICKS`", f"{GATE_A_TICKS:,}", "A-1(처음 정의): 두 갈래 모두 이 틱까지 살아야 판정"],
        ["`GATE_A2_AT_GEN`", GATE_A2_AT_GEN, f"A-2: 기준 실행(`{GATE_A2_PRESET}`)의 평균 세대 — 끝 스냅숏 틱 F"],
        ["`GATE_A2_TICKS`", str(GATE_A2_TICKS), "A-2: 갈래·기준 행을 F + 이 틱까지"],
        ["`GATE_A2_WINDOW`", str(GATE_A2_WINDOW), "A-2: 대상 출생 틱 [F, F + 이 값)"],
    ], ["l", "r", "l"]))
    n, m = len(ev["judged"]), len(ev["third_ok"])
    w = ev["wins"]
    ratio_need = f"(문턱 {GATE_A_RATIO})" if spec["ratio"] else "(A-2 는 보고 — 문턱 없음)"
    out += ["", "## 판정", "",
            f"판정 가능한 씨앗 {n}개 / {len(args.seeds)}개.", "",
            f"- ① 먹은 양: 학습 > freeze 씨앗 **{w['eaten'][0]}/{n}**(문턱 {GATE_A_WIN}), 묶은 중앙값 비 "
            f"**{_fmt(ev['ratio'], 3)}**{ratio_need} → {'충족' if ev['crit1'] else '못 함'}",
            "- ② 생존·번식: " + " · ".join(f"{nm} **{w[k][0]}/{n}**" for k, nm, _ in GATE_A_METRICS if k in GATE_A_SECONDARY)
            + f"(둘 가운데 하나 ≥ {GATE_A_SECONDARY_WIN}) → {'충족' if ev['crit2'] else '못 함'}",
            "- 보고만(판정에 쓰지 않음): " + " · ".join(f"{nm} **{w[k][0]}/{n}**" for k, nm, _ in GATE_A_METRICS
                                                  if gate_a_role(k) == "보고")]
    sec_names = {k: nm for k, nm, _ in GATE_A_METRICS if k in GATE_A_SECONDARY}
    for key, name, dg in GATE_A_METRICS:
        if ev["ties"][key] is None:
            continue
        role = gate_a_role(key)
        if role == "①":
            other = "① 을 채울 수 없음"
        elif role == "②":
            other = "② 는 " + " · ".join(v for k, v in sec_names.items() if k != key) + "로만 갈림"
        else:
            other = "보고만 하는 지표라 판정에 닿지 않음"
        out.append(f"- **갈래를 가르지 못한 지표: {name}** — 판정 가능 씨앗 {n}개 모두에서 학습 = freeze"
                   f"(값 {' · '.join(_fmt(v, dg) for v in ev['ties'][key])}). 같은 값은 이긴 씨앗으로 세지 않으므로 {other}")
    out += ["", f"## 지표 — 판정 가능 씨앗 {n}개의 대상을 묶은 값({names[third]} 행은 그 갈래도 조건을 채운 {m}개)", ""]
    rows = []
    p = ev["pooled"]
    for key, name, dg in GATE_A_METRICS:
        a, f, o = p[("learn", key)], p[("freeze", key)], p[(third, key)]
        eff = (a - f) / f if f and not (math.isnan(a) or math.isnan(f)) else float("nan")
        rows.append([name, gate_a_role(key), _fmt(a, dg), _fmt(f, dg), _fmt(o, dg), _fmt(a - f, dg), _fmt(a - o, dg), _fmt(eff, 3),
                     f"{w[key][0]}/{n}", f"{w[key][1]}/{m}"])
    out.append(_md_table(["지표", "쓰임", names["learn"], names["freeze"], names[third], "학습 − freeze", f"학습 − {names[third]}",
                          "효과 크기 (학습 − freeze) ÷ freeze", "학습 > freeze 씨앗", f"학습 > {names[third]} 씨앗"], rows,
                         ["l", "l", "r", "r", "r", "r", "r", "r", "r", "r"]))
    out += ["", "## 씨앗별", ""]
    rows = []
    for seed in args.seeds:
        for b, bn, _ in branches:
            r = runs.get((b, seed), ({"status": "failed"}, {}))[0]
            end = r.get("extinct_tick")
            end_text = (f"{int(end):,} 멸종" if isinstance(end, (int, np.integer)) and end >= 0
                        else (f"{int(r['ticks']):,}" if isinstance(r.get("ticks"), (int, np.integer)) else "—"))
            blo, bhi = r.get("birth_lo"), r.get("birth_hi")
            window = f"[{int(blo)}, {int(bhi)})" if isinstance(blo, (int, np.integer)) and isinstance(bhi, (int, np.integer)) else "—"
            rows.append([str(seed), bn, GATE_A_RUN_STATUS_KO.get(r.get("status"), str(r.get("status"))), window, end_text,
                         _fmt(r.get("targets"), 0) if isinstance(r.get("targets"), (int, np.integer)) else "—",
                         _fmt(r.get("eaten_median"), 2), _fmt(r.get("life_mean"), 2), _fmt(r.get("children_mean"), 3),
                         _fmt(r.get("matured_share"), 3), f"`{r.get('history_hash') or ''}`"])
    out.append(_md_table(["씨앗", "갈래", "상태", "대상 출생(틱)", "끝(틱)", "대상", "먹은 양 중앙값", "평균 산 나이", "평균 자식 수",
                          "성숙까지 산 몫", "해시"], rows, ["r", "l", "l", "r", "r", "r", "r", "r", "r", "r", "l"]))
    if ev["unjudged"]:
        out += ["", "## 판정 불가 씨앗", ""]
        out.append(_md_table(["씨앗", "까닭"], [[str(k), v] for k, v in sorted(ev["unjudged"].items())], ["r", "l"]))
    if ev["third_missing"]:
        out += ["", f"## {names[third]} 행이 없는 판정 가능 씨앗", ""]
        out.append(_md_table(["씨앗", "까닭"], [[str(k), v] for k, v in sorted(ev["third_missing"].items())], ["r", "l"]))
    out += ["", "## 읽는 법", "",
            ("- 두 판정 갈래는 같은 씨앗의 같은 스냅숏(A-2)" if spec["kind"] == "fork" else "- 세 갈래는 같은 씨앗·같은 처음 세계")
            + "에서 설정 하나만 다르게 돌린 것입니다. 행동이 달라지면 출생·먹이 고갈·난수 뽑기도 갈라지므로, "
            "차이에는 학습 자체와 학습이 바꾼 생태 되먹임이 함께 들어 있습니다(14.3).",
            f"- 학습 − freeze = 학습이 한 몫(freeze 도 학습 비용은 냄), 학습 − {names[third]} = "
            + ("진화 없는 우연 기준 세계와의 차이(A-2 의 기준 행)." if spec["kind"] == "fork" else "비용까지 뺀 순 득.")
            + " 효과 크기 = (학습 − freeze) ÷ freeze.",
            "- 묶은 값 = 판정 가능 씨앗들의 대상 개체를 한데 모은 값(먹은 양은 중앙값, 평균 산 나이·자식 수·성숙까지 산 몫은 평균). 씨앗 수는 "
            "씨앗마다 값(먹은 양 중앙값·평균 산 나이·평균 자식 수·성숙까지 산 몫)이 학습 쪽에서 **더 큰**(같으면 세지 않음) 씨앗. "
            f"{names[third]} 행은 그 갈래도 조건(대상 ≥ {GATE_A_MIN_BIRTHS}·끝에 산 대상 없음"
            + (f"·F + {GATE_A2_TICKS} 까지 생존" if spec["kind"] == "fork" else "") + ")을 채운 씨앗만.",
            "- 산 나이 = 죽은 나이(`death_tick` − `birth_tick`). 판정 가능 씨앗은 대상이 모두 죽었으므로 평생 값입니다. "
            "② 의 생존 지표는 평균 산 나이입니다(사전 결정 2026-10-11 — 판정 실행 전, DESIGN-v0.2 14.3).",
            "- 성숙까지 산 = 산 나이 > `repro.maturity` — 번식 자격 나이로 번식 단계에 살아서 닿음. 보고만 합니다: 기본값에서는 이 몫이 "
            "세 갈래 모두 1 이 되기 쉬워(자식이 부모에게 받은 에너지만으로 성숙 나이보다 오래 삶 — 1단계 검증에서 가장 일찍 굶어 죽은 개체도 "
            "50틱 넘게 삶) 갈래를 가르지 못했습니다. 판정 가능 씨앗 모두에서 학습 = freeze 인 지표는 위 '판정' 에 '갈래를 가르지 못한 지표' 로 "
            "적습니다.",
            f"- 표: [`gate_a.csv`](gate_a.csv)(씨앗·갈래마다 한 줄). 갈래 결과는 이 폴더의 "
            + "·".join(f"`{b}/`" for b in ([GATE_A2_BASE] if spec["kind"] == "fork" else []) + [b for b, _, _ in branches]) + ".", ""]
    path.write_text("\n".join(out), encoding="utf-8")


# ── 볼드윈 보고서(baldwin — DESIGN-v0.2 11.2) ──

## 세대 추이의 개체 세대 구간 폭, 같은 실행의 첫 → 끝 구간을 견줄 때 쓰는 구간의 죽은 개체 수 하한(끝 세대 구간은 앞서 간 몇 계통만
## 있어 개체가 적음 — 그런 구간은 방향 셈에서 뺌)
BALDWIN_GEN_BIN = EATEN_GEN_BIN
BALDWIN_MIN_DEAD = 30
## baldwin.csv 열(실행·개체 세대 구간마다 한 줄 — 죽은 개체)
BALDWIN_COLUMNS = ["cell", "seed", "path", "gen_lo", "gen_hi", "dead", "eta_mean", "dw_mean", "dw_juv_mean", "assim_mean",
                   "eaten_median", "children_mean"]
## 세대 추이 지표: (baldwin.csv 열, 보고서 이름, 소수 자리, 동화 쪽 방향 — +1 오름 · −1 내림 · 0 방향 없음)
BALDWIN_TREND = [("eta_mean", "η 평균", 4, -1), ("assim_mean", "동화 지수", 3, +1), ("dw_mean", "배운 양", 4, 0),
                 ("dw_juv_mean", "어린 동안 배운 양", 4, 0), ("eaten_median", "평생 먹은 양 중앙값", 1, 0)]
## 이식 시험 지표(ablate.csv 의 metric — 그대로 갈래 = 배우는 두뇌, 바꾼 갈래 = 타고난 두뇌)
BALDWIN_PROBE_METRICS = [("target_eaten", "대상 평균 먹은 양"), ("target_children", "대상 평균 자식 수")]


def baldwin_bins(lin: pd.DataFrame) -> list[dict]:
    """실행 하나의 개체 세대 구간(BALDWIN_GEN_BIN 폭)별 죽은 개체의 η·배운 양·어린 동안 배운 양·동화 지수 평균, 먹은 양 중앙값, 자식 수 평균.
    죽은 개체만(평생 값이 정해짐). 먹은 양 칸이 빈 개체(옛 스냅숏에서 이어 돌림)는 먹은 양에서만 뺌."""
    dead = lin[lin["death_tick"] >= 0]
    out = []
    bins = dead["gen"].to_numpy(dtype=int) // BALDWIN_GEN_BIN
    for b in sorted(set(bins.tolist())):
        g = dead[bins == b]
        e = pd.to_numeric(g["eaten"], errors="coerce").dropna().to_numpy(dtype=float) if "eaten" in g.columns else np.zeros(0)
        out.append({"gen_lo": b * BALDWIN_GEN_BIN, "gen_hi": (b + 1) * BALDWIN_GEN_BIN, "dead": len(g),
                    "eta_mean": float(g["eta"].mean()), "dw_mean": float(g["dw"].mean()),
                    "dw_juv_mean": float(g["dw_juv"].mean()), "assim_mean": float(g["assim"].mean()),
                    "eaten_median": float(np.median(e)) if e.size else float("nan"),
                    "children_mean": float(g["children"].mean())})
    return out


def baldwin_table(root: Path) -> tuple[pd.DataFrame, list[str]]:
    """root 아래 학습을 켠 실행(summary.json 의 features 에 learn.enabled)의 lineage.csv → baldwin.csv 표. 둘째 값 = 뺀 실행과 까닭."""
    df, _ = build_summary(root)
    rows, skipped = [], []
    for _, r in df.iterrows():
        d = root / r["path"]
        s = json.loads((d / "summary.json").read_text(encoding="utf-8-sig"))
        lin = read_lineage(d / "lineage.csv")
        if "learn.enabled" not in (s.get("features") or []):
            skipped.append(f"`{r['path']}` — 학습을 켜지 않은 실행(features 에 learn.enabled 없음)")
        elif lin is None or not all(c in lin.columns for c in ("eta", "dw", "dw_juv", "assim")):
            skipped.append(f"`{r['path']}` — lineage.csv 나 1단계 열(eta·dw·dw_juv·assim)이 없음")
        else:
            for b in baldwin_bins(lin):
                rows.append({"cell": r["cell"], "seed": r["seed"], "path": r["path"], **b})
    out = pd.DataFrame(rows, columns=BALDWIN_COLUMNS)
    for c in ("seed", "gen_lo", "gen_hi", "dead"):
        out[c] = pd.to_numeric(out[c], errors="coerce").round().astype("Int64")
    return out, skipped


def baldwin_direction(table: pd.DataFrame, col: str) -> tuple[int, int, int]:
    """같은 실행의 첫 → 끝 세대 구간(죽은 개체 ≥ BALDWIN_MIN_DEAD 인 구간만)에서 col 이 (내린, 오른, 같은) 실행 수. 구간이 하나뿐이면 뺌."""
    down = up = same = 0
    for _, g in table[table["dead"] >= BALDWIN_MIN_DEAD].groupby("path", sort=True):
        if len(g) < 2:
            continue
        g = g.sort_values("gen_lo")
        a, b = float(g[col].iloc[0]), float(g[col].iloc[-1])
        if math.isnan(a) or math.isnan(b):
            continue
        down += int(b < a)
        up += int(b > a)
        same += int(b == a)
    return down, up, same


def read_probe(d: Path) -> dict:
    """이식 시험 폴더(analyze.py ablate --reset-learned 의 결과) → {dir, at_gen, ticks, reset, seeds{씨앗: {지표: (배우는, 타고난)}}, error}."""
    try:
        meta = json.loads((d / ABLATE_META).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"dir": d, "error": f"{ABLATE_META} 를 읽을 수 없음(analyze.py ablate 의 결과 폴더가 아님)"}
    try:
        t = pd.read_csv(d / "ablate.csv", encoding=CSV_ENCODING)
    except (OSError, ValueError, pd.errors.EmptyDataError):
        return {"dir": d, "error": "ablate.csv 를 읽을 수 없음"}
    seeds: dict[int, dict] = {}
    for r in t.itertuples():
        if r.metric in dict(BALDWIN_PROBE_METRICS):
            seeds.setdefault(int(r.seed), {})[r.metric] = (float(r.same), float(r.fork))
    return {"dir": d, "at_gen": float(meta.get("at_gen", "nan")), "ticks": int(meta.get("ticks", 0)),
            "reset": bool(meta.get("reset_learned")), "sets": meta.get("set", []), "seeds": seeds, "error": ""}


def cmd_baldwin(args) -> int:
    """baldwin: 학습을 켠 실행 폴더의 세대 추이(η·배운 양·어린 동안 배운 양·동화 지수 — lineage.csv), 이식 시험(--probe: ablate
    --reset-learned 결과 — 같은 스냅숏의 배우는 두뇌 대 타고난 두뇌), 학습 끈 대조(--control-probe: 학습을 끈 실행의 ablate 결과의
    그대로 갈래)를 모아 OUT/baldwin.csv·baldwin.md(DESIGN-v0.2 11.2 의 보고 항목 — 관문 아님). 종료 코드: 0 씀, 1 읽을 실행이 없음, 2 폴더 오류."""
    root = Path(args.dir).resolve()
    if not root.is_dir():
        print(f"오류: 폴더가 없습니다: {root}", file=sys.stderr)
        return 2
    out_dir = Path(args.out).resolve() if args.out else root
    err = make_out_dir(out_dir)
    if err:
        print("오류: " + err, file=sys.stderr)
        return 2
    table, skipped = baldwin_table(root)
    probes = sorted((read_probe(Path(p).resolve()) for p in args.probe), key=lambda p: (p.get("at_gen", math.inf), str(p["dir"])))
    controls = [read_probe(Path(p).resolve()) for p in args.control_probe]
    write_csv(table, out_dir / "baldwin.csv")
    write_baldwin_md(out_dir / "baldwin.md", root, table, skipped, probes, controls)
    print(f"보고서: {out_dir / 'baldwin.md'}  (실행 {table['path'].nunique() if len(table) else 0}개, 이식 시험 {len(probes)}개)")
    if not len(table):
        print(f"오류: {root} 아래에 학습을 켠 실행의 lineage.csv 가 없습니다(analyze.py run --lineage)", file=sys.stderr)
        return 1
    return 0


def _probe_innate(p: dict, metric: str) -> dict[int, float]:
    return {s: v[metric][1] for s, v in p.get("seeds", {}).items() if metric in v and not math.isnan(v[metric][1])}


def write_baldwin_md(path: Path, root: Path, table: pd.DataFrame, skipped: list[str], probes: list[dict],
                     controls: list[dict]) -> None:
    """baldwin.md: 세대 추이, 같은 실행의 첫 → 끝 구간 방향, 이식 시험(배우는 대 타고난), 학습 끈 대조와 타고난 능력, 동화·감춤 항목, 읽는 법."""
    out = ["# 볼드윈 보고서(baldwin)", "",
           f"- 실행 폴더: `{root.name}` — 학습을 켠 실행 **{table['path'].nunique() if len(table) else 0}개**",
           f"- 이식 시험(`--probe`) {len(probes)}개 · 학습 끈 대조(`--control-probe`) {len(controls)}개",
           "- 표: [`baldwin.csv`](baldwin.csv)(실행·개체 세대 구간마다 — 죽은 개체). DESIGN-v0.2 11.2 의 보고 항목이고 관문이 아닙니다.", ""]
    cells = sorted(set(table["cell"]), key=natural_key) if len(table) else []
    out += ["## 세대 추이(죽은 개체)", "",
            f"개체 세대({BALDWIN_GEN_BIN}세대 폭)마다 실행의 값을 내고 묶음마다 그 **중앙값**(괄호 = 실행 수 · 죽은 개체 수 합). "
            "η = 태어날 때 학습률 유전자 8개의 평균(행동 행별 η 는 기록 열에 없음), 배운 양 = 64 행동 가중치의 abs(배운 − 타고난) 평균, "
            "어린 동안 배운 양 = 어린 동안 모든 갱신에서 가중치마다 움직인 양의 **합**(배운 양과 단위가 달라 수십 배 큼 — 같은 눈금으로 견주지 않음), "
            "동화 지수 = 고리의 판단마다 타고난·배운 두뇌의 가장 큰 행동이 같은 몫(죽을 때).", ""]
    rows = []
    for cell in cells:
        g = table[table["cell"] == cell]
        for lo, hi in sorted(set((int(a), int(b)) for a, b in zip(g["gen_lo"], g["gen_hi"]))):
            h = g[g["gen_lo"] == lo]
            rows.append([f"`{cell}`", f"{lo:,}–{hi:,}"] + [_fmt(quartiles(h[c])[1], dg) for c, _, dg, _ in BALDWIN_TREND]
                        + [f"{len(h)} · {int(h['dead'].sum()):,}"])
    out.append(_md_table(["묶음", "개체 세대"] + [n for _, n, _, _ in BALDWIN_TREND] + ["실행 · 개체"], rows,
                         ["l", "r"] + ["r"] * (len(BALDWIN_TREND) + 1)) if rows else "학습을 켠 실행의 lineage.csv 가 없습니다.")
    out += ["", "## 같은 실행의 첫 구간 → 끝 구간", "",
            f"실행마다 죽은 개체가 {BALDWIN_MIN_DEAD} 이상인 첫 세대 구간과 끝 구간을 견줘 **내린 실행 · 오른 실행 (견준 실행)** 을 셉니다"
            "(구간마다 실행 묶음이 달라 중앙값끼리 견주면 실행 구성이 섞이므로).", ""]
    dirs = {c: baldwin_direction(table, c) for c, _, _, _ in BALDWIN_TREND} if len(table) else {}
    out.append(_md_table(["지표", "내림 · 오름 (견준 실행)"],
                         [[n, f"{dirs[c][0]} · {dirs[c][1]} ({sum(dirs[c])})"] for c, n, _, _ in BALDWIN_TREND], ["l", "r"])
               if dirs else "견줄 실행이 없습니다.")
    out += ["", "## 이식 시험 — 같은 스냅숏의 배우는 두뇌 대 타고난 두뇌", "",
            "`analyze.py ablate --reset-learned --set learn.freeze=true` 의 결과 폴더마다: 그대로 갈래(배우는 두뇌) · 바꾼 갈래(살아 있는 "
            "개체의 배운 두뇌를 유전체로 되돌리고 학습을 멈춤 = 타고난 두뇌)의 씨앗 중앙값, 차이(배우는 − 타고난)의 중앙값, 배우는 쪽이 큰 씨앗 수.", ""]
    rows = []
    bad = []
    for p in probes:
        if p["error"] or not p.get("reset"):
            bad.append([f"`{p['dir'].name}`", p["error"] or "이식 시험이 아님(ablate.json 의 reset_learned 가 false)"])
            continue
        for m, name in BALDWIN_PROBE_METRICS:
            vals = [(v[m][0], v[m][1]) for v in p["seeds"].values() if m in v and not any(math.isnan(x) for x in v[m])]
            if not vals:
                continue
            a = [x for x, _ in vals]
            b = [y for _, y in vals]
            rows.append([f"`{p['dir'].name}`", _fmt(p["at_gen"], 1), f"{p['ticks']:,}", name, str(len(vals)),
                         _fmt(quartiles(a)[1], 2), _fmt(quartiles(b)[1], 2), _fmt(quartiles([x - y for x, y in vals])[1], 2),
                         str(sum(1 for x, y in vals if x > y))])
    out.append(_md_table(["폴더", "평균 세대", "틱", "지표", "씨앗", "배우는", "타고난", "차이 중앙값", "배우는 > 타고난"], rows,
                         ["l", "r", "r", "l", "r", "r", "r", "r", "r"]) if rows else "이식 시험 결과가 없습니다(`--probe`).")
    if bad:
        out += ["", _md_table(["폴더", "뺀 까닭"], bad)]
    good = [p for p in probes if not p["error"] and p.get("reset")]
    m0 = BALDWIN_PROBE_METRICS[0][0]
    out += ["", "## 학습 끈 대조와 타고난 능력", "",
            f"`--control-probe`(학습을 끈 실행에서 같은 평균 세대·틱으로 돌린 ablate 결과)의 그대로 갈래 = 학습 없이 진화한 두뇌의 능력. "
            f"같은 평균 세대의 이식 시험의 타고난 능력과 {BALDWIN_PROBE_METRICS[0][1]}로 견줍니다(같은 씨앗끼리).", ""]
    rows = []
    hiding = None
    for c in controls:
        if c["error"]:
            rows.append([f"`{c['dir'].name}`", "—", "—", "—", "—", c["error"]])
            continue
        match = [p for p in good if p["at_gen"] == c["at_gen"]]
        if not match:
            rows.append([f"`{c['dir'].name}`", _fmt(c["at_gen"], 1), "—", "—", "—", "같은 평균 세대의 이식 시험이 없음"])
            continue
        innate = _probe_innate(match[0], m0)
        ctrl = {s: v[m0][0] for s, v in c["seeds"].items() if m0 in v and not math.isnan(v[m0][0])}
        common = sorted(set(innate) & set(ctrl))
        lower = sum(1 for s in common if innate[s] < ctrl[s])
        rows.append([f"`{c['dir'].name}`", _fmt(c["at_gen"], 1), _fmt(quartiles([innate[s] for s in common])[1], 2),
                     _fmt(quartiles([ctrl[s] for s in common])[1], 2), f"{lower}/{len(common)}", ""])
        if common and (hiding is None or c["at_gen"] >= hiding[0]):
            hiding = (c["at_gen"], lower, len(common))
    out.append(_md_table(["대조 폴더", "평균 세대", "타고난(학습 켬) 중앙값", "학습 끔 중앙값", "타고난 < 학습 끔 씨앗", "비고"], rows,
                         ["l", "r", "r", "r", "r", "l"]) if rows else "학습 끈 대조가 없습니다(`--control-probe`).")
    # 동화·감춤(11.2 의 보고 항목): 방향 수의 과반으로 적고, 자료가 없으면 그렇다고만
    eta_d, assim_d = dirs.get("eta_mean"), dirs.get("assim_mean")
    items = []
    items.append(f"- η 가 세대에 따라 줄어듦: {_majority(eta_d, 0)}")
    items.append(f"- 동화 지수가 오름: {_majority(assim_d, 1)}")
    if len(good) >= 2:
        first, last = _probe_innate(good[0], m0), _probe_innate(good[-1], m0)
        common = sorted(set(first) & set(last))
        upn = sum(1 for s in common if last[s] > first[s])
        innate_up = common and upn * 2 > len(common)
        items.append(f"- 이식 시험의 타고난 능력이 오름(평균 세대 {_fmt(good[0]['at_gen'], 1)} → {_fmt(good[-1]['at_gen'], 1)}, "
                     f"{BALDWIN_PROBE_METRICS[0][1]}): {'예' if innate_up else '아니오'}({upn}/{len(common)} 씨앗)")
    else:
        innate_up = None
        items.append("- 이식 시험의 타고난 능력이 오름: 자료 없음(평균 세대가 다른 `--probe` 둘 이상이 필요)")
    assim = (eta_d and assim_d and innate_up is not None and _is_majority(eta_d, 0) and _is_majority(assim_d, 1) and innate_up)
    items.append(f"- **동화**(셋 모두): {'예' if assim else ('아니오' if innate_up is not None and eta_d and assim_d else '판단할 자료 없음')}")
    items.append("- **감춤**(가장 늦은 평균 세대에서 타고난 능력 < 학습 끔인 씨앗이 과반): "
                 + (f"{'예' if hiding[1] * 2 > hiding[2] else '아니오'}(평균 세대 {_fmt(hiding[0], 1)}, {hiding[1]}/{hiding[2]} 씨앗)"
                    if hiding else "판단할 자료 없음"))
    out += ["", "## 동화·감춤(보고 항목 — 결과 그대로)", ""] + items
    if skipped:
        out += ["", "## 뺀 실행", ""] + [f"- {x}" for x in skipped]
    out += ["", "## 읽는 법", "",
            "- 동화(11.2): 세대가 가며 η 가 줄고, 동화 지수가 오르고, 이식 시험의 타고난 능력이 오름 — 처음에는 배워야 했던 행동이 타고난 것이 됨. "
            "감춤: 학습을 켠 실행의 타고난 능력이 학습 끈 대조보다 낮음(Mayley 1997). 어느 쪽이든 결과 그대로 적습니다.",
            "- 방향 수는 같은 실행끼리 짝지은 첫 → 끝 구간이고, 과반이면 '예'로 적습니다(통계 검정 아님).",
            "- 이식 시험의 두 갈래는 같은 스냅숏에서 갈라 돌린 쌍입니다. 타고난 갈래는 갈라진 뒤 태어난 개체도 배우지 않습니다(학습 멈춤).",
            "- 이식 시험 폴더 만들기: `analyze.py ablate --runs <학습 실행> --preset learn_basic --at-gen G --reset-learned "
            "--set learn.freeze=true --ticks N`, 학습 끈 대조는 같은 G·N 으로 학습을 끈 실행에서(`--set` 은 아무 키 — 그대로 갈래만 읽음).", ""]
    path.write_text("\n".join(out), encoding="utf-8")


def _is_majority(d: tuple[int, int, int] | None, idx: int) -> bool:
    """방향 수 (내림, 오름, 같음) 가운데 idx 쪽이 견준 실행의 과반인가."""
    return bool(d) and sum(d) > 0 and d[idx] * 2 > sum(d)


def _majority(d: tuple[int, int, int] | None, idx: int) -> str:
    if not d or sum(d) == 0:
        return "자료 없음"
    return f"{'예' if _is_majority(d, idx) else '아니오'}({d[idx]}/{sum(d)} 실행)"


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
        df = pd.read_csv(path, encoding=CSV_ENCODING)
    except (pd.errors.EmptyDataError, pd.errors.ParserError, UnicodeDecodeError):
        return None
    for c in ("tick", "population", "mean_gen", "mean_size", "mean_sense", "civ_stage"):
        if c not in df.columns:
            return None
    return df


def read_lineage(path: Path) -> pd.DataFrame | None:
    """lineage.csv(묶음 실행은 기본으로 쓰지 않음 — --lineage). 없거나 읽을 수 없으면 None. eaten 은 0단계부터의 열(예전 결과는 없음)."""
    if not path.is_file():
        return None
    try:
        df = pd.read_csv(path, encoding=CSV_ENCODING)
    except (pd.errors.EmptyDataError, pd.errors.ParserError, UnicodeDecodeError):
        return None
    for c in ("id", "parent_a", "gen", "birth_tick", "death_tick", "children"):
        if c not in df.columns:
            return None
    return df


def window_births(lin: pd.DataFrame | None, window: tuple[int, int] = GATE_A_BIRTH_WINDOW) -> float:
    """틱 [시작, 끝) 에 태어난 개체 수(처음 개체 — 부모 없음 — 는 빼고). lineage.csv 가 없으면 NaN."""
    if lin is None:
        return float("nan")
    born = lin[(lin["parent_a"] >= 0) & (lin["birth_tick"] >= window[0]) & (lin["birth_tick"] < window[1])]
    return float(len(born))


def read_chronicle(path: Path) -> pd.DataFrame | None:
    if not path.is_file():
        return None
    try:
        df = pd.read_csv(path, dtype={"kind": str, "text": str}, keep_default_na=False, encoding=CSV_ENCODING)
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
    with (run_dir / "summary.json").open(encoding="utf-8-sig") as f:
        s = json.load(f)
    ts = read_timeseries(run_dir / "timeseries.csv")
    chron = read_chronicle(run_dir / "chronicle.csv")
    disc = discovery_generations(chron, s.get("discovery_ticks", {}) or {}, ts)
    overrides = s.get("overrides", {}) or {}
    ov_text = ";".join(f"{k}={_json_scalar(overrides[k])}" for k in sorted(overrides))
    rel = _rel(run_dir, root)
    parent = Path(rel).parent.as_posix() if rel != "." else ROOT_CELL
    if parent in ("", "."):
        # 루트 바로 아래 씨앗 폴더들(run 결과) → 예설정(+덮어쓰기)으로 이름 짓기. 예설정을 모르면(스냅숏에서) SNAPSHOT_CELL
        parent = (str(s.get("preset", "default")) or SNAPSHOT_CELL) + (f"+{ov_text}" if ov_text else "")
    row = {
        "cell": parent, "seed": s.get("seed"), "preset": s.get("preset", ""), "overrides": ov_text,
        "generations_target": s.get("generations_target"),
        "end_reason": s.get("end_reason", ""), "ticks": s.get("tick"), "mean_generation": s.get("mean_generation"),
        "population": s.get("population"), "peak_population": s.get("peak_population"),
        "births": s.get("total_births"), "deaths": s.get("total_deaths"), "civ_stage": s.get("civ_stage"),
        "civ_stage_name": s.get("civ_stage_name", ""), "extinct_tick": s.get("extinct_tick", -1),
        "storehouses": s.get("storehouses"), "farms": s.get("farms"),
        "final_mean_size": float("nan"), "final_mean_sense": float("nan"),
        "window_births": window_births(read_lineage(run_dir / "lineage.csv")),
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


# ── 행동 셈(act/eff)·평생 먹은 양·관문 A-1 미리 보기 ──

## actions.csv 열(실행·구간·행동마다 한 줄)
ACTION_COLUMNS = ["cell", "seed", "path", "basis", "bin_lo", "bin_hi", "action", "rows", "total", "act", "eff",
                  "act_share", "eff_share", "success"]
## eaten.csv 열(실행·개체 세대 구간마다 한 줄)
EATEN_COLUMNS = ["cell", "seed", "path", "gen_lo", "gen_hi", "dead", "eaten_median", "eaten_mean"]


def run_columns(run_dir: Path, ts: pd.DataFrame | None) -> list[str]:
    """실행 하나의 시계열 열 목록: summary.json 의 timeseries_columns(0단계부터 실행기·실험실이 씀 — DESIGN-v0.2 9.5), 없으면(예전
    결과) timeseries.csv 머리. 열이 단계마다 늘므로 어떤 열이 있는지는 손 사본(TIMESERIES_COLUMNS)이 아니라 이것으로 본다."""
    try:
        s = json.loads((run_dir / "summary.json").read_text(encoding="utf-8-sig"))
        cols = s.get("timeseries_columns")
        if isinstance(cols, list) and cols:
            return [str(c) for c in cols]
    except (OSError, ValueError):
        pass
    return list(ts.columns) if ts is not None else []


def action_bins(ts: pd.DataFrame, basis: str) -> list[dict]:
    """실행 하나의 구간별 행동 셈. 시계열 한 줄 = 앞 줄 뒤 그 줄까지의 구간(births 와 같은 뜻 — DESIGN-v0.2 9.3)이고, 줄을
    구간 **시작** 값(앞 줄의 평균 세대·틱·문명 단계, 첫 줄은 그 줄)으로 나눈다.
      basis = "gen": 시작 평균 세대로 ACT_GEN_BIN 폭. 문명 행동마다 그 행동이 열린 단계(CIV_ACTIONS) 뒤에 시작한 줄만(열린 뒤).
      basis = "tick": ACT_TICK_EDGES 의 틱 구간. 열림과 상관없이 모든 줄(우연 기준과 같은 틱에서 견줌).
    행동이 하나도 없는 줄(멸종 뒤)은 뺀다. 결과: [{bin_lo, bin_hi, action, rows, total, act, eff}] — total = 그 줄들의 모든 행동 합."""
    t = ts.sort_values("tick").reset_index(drop=True)
    act = t[ACT_COLUMNS].to_numpy(dtype=float)
    eff = t[EFF_COLUMNS].to_numpy(dtype=float)
    total = act.sum(axis=1)
    start = t[["tick", "mean_gen", "civ_stage"]].shift(1)
    start.iloc[0] = t[["tick", "mean_gen", "civ_stage"]].iloc[0]
    if basis == "gen":
        idx = np.floor(start["mean_gen"].to_numpy(dtype=float) / ACT_GEN_BIN).astype(int)
        edges = None
    else:
        edges = ACT_TICK_EDGES
        idx = np.searchsorted(np.asarray(edges), start["tick"].to_numpy(dtype=float), side="right") - 1
    stage = start["civ_stage"].to_numpy(dtype=float)
    out = []
    for a, (key, open_stage) in enumerate(CIV_ACTIONS):
        col = ACT_COLUMNS.index("act_" + key)
        use = total > 0
        if basis == "gen":
            use = use & (stage >= open_stage)
        else:
            use = use & (idx >= 0) & (idx < len(edges) - 1)
        for b in sorted(set(idx[use].tolist())):
            m = use & (idx == b)
            lo, hi = (b * ACT_GEN_BIN, (b + 1) * ACT_GEN_BIN) if basis == "gen" else (edges[b], edges[b + 1])
            out.append({"bin_lo": lo, "bin_hi": hi, "action": key, "rows": int(m.sum()), "total": float(total[m].sum()),
                        "act": float(act[m, col].sum()), "eff": float(eff[m, col].sum())})
    return out


def action_table(df: pd.DataFrame, series: dict[str, pd.DataFrame], root: Path) -> pd.DataFrame:
    """모든 실행의 구간별 문명 행동 셈(actions.csv). 행동 셈 열(act_*·eff_*)이 없는 실행(v0.1 실행기 결과)은 빠진다.
    act_share = act ÷ total(그 구간에 고른 모든 행동 가운데 이 행동), eff_share = eff ÷ total, success = eff ÷ act."""
    rows = []
    for _, r in df.iterrows():
        ts = series.get(r["path"])
        if ts is None:
            continue
        cols = run_columns(root / r["path"], ts)
        if not all(c in cols and c in ts.columns for c in ACT_COLUMNS + EFF_COLUMNS):
            continue
        for basis in ("gen", "tick"):
            for b in action_bins(ts, basis):
                tot, a, e = b["total"], b["act"], b["eff"]
                rows.append({"cell": r["cell"], "seed": r["seed"], "path": r["path"], "basis": basis, **b,
                             "act_share": a / tot if tot > 0 else float("nan"),
                             "eff_share": e / tot if tot > 0 else float("nan"),
                             "success": e / a if a > 0 else float("nan")})
    out = pd.DataFrame(rows, columns=ACTION_COLUMNS)
    for c in ("seed", "bin_lo", "bin_hi", "rows"):
        out[c] = pd.to_numeric(out[c], errors="coerce").round().astype("Int64")
    return out


## 같은 실행의 첫 구간 → 끝 구간에서 방향을 셀 지표(actions.csv 의 열, 보고서 이름)
TREND_MEASURES = [("act_share", "고름"), ("eff_share", "효과"), ("success", "성공률")]
TREND_COLUMNS = ["cell", "action", "measure", "runs", "down", "up", "same"]


def action_trend(acts: pd.DataFrame, cells: list[str]) -> pd.DataFrame:
    """세대 구간 표(basis = gen)에서 실행마다 그 행동이 값을 가진 **첫 구간과 끝 구간**을 견줘, 묶음·행동·지표마다 내린·오른·같은
    실행 수. 묶음 중앙값은 구간마다 값이 있는 씨앗 묶음이 달라(일찍 열린 씨앗만 앞 구간에 있음) 그 차이로 방향을 말하면 씨앗 구성이
    섞이므로, 같은 실행끼리 짝지어 본다. 구간이 하나뿐인 실행과 두 값 중 하나가 NaN 인 지표는 뺀다(runs = 견준 실행 수)."""
    rows = []
    g = acts[acts["basis"] == "gen"] if acts is not None and len(acts) else None
    for cell in cells:
        for key, _ in CIV_ACTIONS:
            h = g[(g["cell"] == cell) & (g["action"] == key)] if g is not None else None
            for m, _ in TREND_MEASURES:
                down = up = same = 0
                if h is not None:
                    for _, r in h.groupby("path", sort=True):
                        if len(r) < 2:
                            continue
                        r = r.sort_values("bin_lo")
                        first, last = float(r[m].iloc[0]), float(r[m].iloc[-1])
                        if math.isnan(first) or math.isnan(last):
                            continue
                        if last < first:
                            down += 1
                        elif last > first:
                            up += 1
                        else:
                            same += 1
                rows.append({"cell": cell, "action": key, "measure": m, "runs": down + up + same,
                             "down": down, "up": up, "same": same})
    return pd.DataFrame(rows, columns=TREND_COLUMNS)


def eaten_table(df: pd.DataFrame, root: Path) -> pd.DataFrame:
    """lineage.csv 의 평생 먹은 양(eaten — 0단계부터의 열)을 개체 세대 구간(EATEN_GEN_BIN 폭)마다: 죽은 개체(death_tick ≥ 0)의
    수·중앙값·평균(eaten.csv). lineage.csv 나 eaten 열이 없는 실행은 빠진다. eaten 칸이 빈 개체(개체별 셈이 없던 옛 스냅숏에서
    이어 돌린 실행의, 연 틱 전에 태어난 개체 — 평생 값을 모름)도 뺀다."""
    rows = []
    for _, r in df.iterrows():
        lin = read_lineage(root / r["path"] / "lineage.csv")
        if lin is None or "eaten" not in lin.columns:
            continue
        dead = lin[(lin["death_tick"] >= 0) & pd.to_numeric(lin["eaten"], errors="coerce").notna()]
        bins = (dead["gen"].to_numpy(dtype=int) // EATEN_GEN_BIN)
        for b in sorted(set(bins.tolist())):
            e = dead["eaten"].to_numpy(dtype=float)[bins == b]
            rows.append({"cell": r["cell"], "seed": r["seed"], "path": r["path"], "gen_lo": b * EATEN_GEN_BIN,
                         "gen_hi": (b + 1) * EATEN_GEN_BIN, "dead": len(e), "eaten_median": float(np.median(e)),
                         "eaten_mean": float(np.mean(e))})
    out = pd.DataFrame(rows, columns=EATEN_COLUMNS)
    for c in ("seed", "gen_lo", "gen_hi", "dead"):
        out[c] = pd.to_numeric(out[c], errors="coerce").round().astype("Int64")
    return out


def gate_a_status(row) -> str:
    """관문 A-1 판정 가능성(실행 하나): "ok" = GATE_A_TICKS 틱까지 살았고 대상 출생 ≥ GATE_A_MIN_BIRTHS, "extinct" = 그 전에 멸종,
    "few" = 살았지만 대상 출생이 모자람, "short" = 멸종하지 않았지만 그 틱 전에 끝남(모름), "nolineage" = lineage.csv 없음."""
    ext = _int_or(row["extinct_tick"])
    if 0 <= ext < GATE_A_TICKS:
        return "extinct"
    if ext < 0 and _int_or(row["ticks"]) < GATE_A_TICKS:
        return "short"
    if pd.isna(row["window_births"]):
        return "nolineage"
    return "ok" if int(row["window_births"]) >= GATE_A_MIN_BIRTHS else "few"


def write_csv(df: pd.DataFrame, path: Path) -> None:
    """결정적 CSV: BOM 붙은 UTF-8(CSV_ENCODING), 쉼표, \\n, 실수 10자리 유효숫자, 빈 값은 NaN."""
    df.to_csv(path, index=False, float_format=FLOAT_FORMAT, na_rep="NaN", lineterminator="\n", encoding=CSV_ENCODING)


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


## 관문 A-1 판정 가능성(gate_a_status) → 보고서 표기
GATE_A_STATUS_KO = {"ok": "판정 가능", "extinct": f"{GATE_A_TICKS:,}틱 전 멸종", "few": "대상 출생 모자람",
                    "short": f"{GATE_A_TICKS:,}틱 전에 끝남", "nolineage": "lineage.csv 없음"}


def _action_md_rows(acts: pd.DataFrame, basis: str, cells: list[str]) -> list[list[str]]:
    """행동 비율 표의 줄: 묶음 × 구간, 문명 행동마다 '고름 % · 효과 % (실행 수)' — 실행마다 낸 비율의 중앙값."""
    rows = []
    sub = acts[acts["basis"] == basis]
    for cell in cells:
        g = sub[sub["cell"] == cell]
        for lo, hi in sorted(set((int(a), int(b)) for a, b in zip(g["bin_lo"], g["bin_hi"]))):
            row = [f"`{cell}`", f"{lo:,}–{hi:,}"]
            for key, _ in CIV_ACTIONS:
                h = g[(g["bin_lo"] == lo) & (g["action"] == key)]
                if not len(h):
                    row.append("—")
                    continue
                a = quartiles(h["act_share"])[1] * 100.0
                e = quartiles(h["eff_share"])[1] * 100.0
                row.append(f"{a:.2f} · {e:.2f} ({len(h)})")
            rows.append(row)
    return rows


def _action_md(acts: pd.DataFrame, cells: list[str]) -> list[str]:
    """보고서의 '행동 비율' 절(행동 셈 열이 있는 실행이 없으면 그렇다고만)."""
    out = ["## 행동 비율(act/eff)", ""]
    if acts is None or not len(acts):
        return out + ["행동 셈 열(`act_*`·`eff_*`)이 있는 실행이 없습니다(v0.2 0단계 전 실행기의 결과).", ""]
    names = dict(zip([c[4:] for c in ACT_COLUMNS], ACTION_NAMES_KO))
    head = [f"{names[k]} 고름 · 효과 %(실행)" for k, _ in CIV_ACTIONS]
    out += ["실행마다 구간의 **고름 비율**(이 행동을 고른 횟수 ÷ 모든 행동 횟수)과 **효과 비율**(효과가 난 횟수 ÷ 모든 행동 횟수)을 "
            "내고, 묶음마다 그 **중앙값**을 적습니다(괄호 = 그 구간에 값이 있는 실행 수). 실행마다 구간·행동별 값은 "
            "[`actions.csv`](actions.csv).", "",
            "### 세대 구간별 — 문명 행동이 열린 뒤", "",
            f"구간 = 구간 시작의 평균 세대({ACT_GEN_BIN}세대 폭). 줍기·내려놓기는 채집, 심기는 농사가 열린 뒤에 시작한 구간만 셉니다.", ""]
    out.append(_md_table(["묶음", "평균 세대"] + head, _action_md_rows(acts, "gen", cells), ["l", "r", "r", "r", "r"]))
    trend = action_trend(acts, cells)
    rows = []
    for cell in cells:
        for key, _ in CIV_ACTIONS:
            h = trend[(trend["cell"] == cell) & (trend["action"] == key)]
            if not len(h) or int(h["runs"].max()) == 0:
                continue
            row = [f"`{cell}`", names[key]]
            for m, _ in TREND_MEASURES:
                x = h[h["measure"] == m].iloc[0]
                row.append(f"{int(x['down'])} · {int(x['up'])} ({int(x['runs'])})")
            rows.append(row)
    out += ["", "### 같은 실행의 첫 구간 → 끝 구간", "",
            "위 표의 묶음 중앙값은 구간마다 값이 있는 실행이 달라(일찍 열린 씨앗만 앞 구간에 있음) 구간끼리의 차이에 씨앗 구성의 차이가 "
            "섞입니다. 그래서 실행마다 그 행동의 **첫 구간과 끝 구간**을 견줘 방향을 셉니다: **내린 실행 · 오른 실행 (견준 실행)**. "
            "구간이 하나뿐인 실행은 빠지고, 성공률 = 효과 ÷ 고름입니다.", ""]
    out.append(_md_table(["묶음", "행동"] + [f"{n} 내림 · 오름" for _, n in TREND_MEASURES], rows, ["l", "l", "r", "r", "r"])
               if rows else "견줄 실행이 없습니다(구간이 둘 이상인 실행 없음).")
    out += ["", f"### 틱 구간별 — 처음 {ACT_TICK_EDGES[-1]:,}틱(열림과 상관없이)", "",
            "같은 틱에서 묶음을 견주는 표(우연 기준 세계는 수백 틱 만에 멸종할 수 있음). 단계가 열리기 전의 줍기·심기는 "
            "효과가 없는 시도라 효과 비율이 0 입니다.", ""]
    out.append(_md_table(["묶음", "틱"] + head, _action_md_rows(acts, "tick", cells), ["l", "r", "r", "r", "r"]))
    return out + [""]


def _eaten_md(eaten: pd.DataFrame, cells: list[str]) -> list[str]:
    """보고서의 '평생 먹은 양' 절(lineage.csv 에 eaten 이 있는 실행이 있을 때만)."""
    if eaten is None or not len(eaten):
        return []
    out = ["## 평생 먹은 양(죽은 개체)", "",
           f"`lineage.csv` 의 `eaten`. 개체 세대({EATEN_GEN_BIN}세대 폭)마다 실행의 중앙값을 내고 묶음마다 그 중앙값을 적습니다"
           "(괄호 = 실행 수 · 죽은 개체 수 합). 실행마다 값은 [`eaten.csv`](eaten.csv).", ""]
    rows = []
    for cell in cells:
        g = eaten[eaten["cell"] == cell]
        for lo, hi in sorted(set((int(a), int(b)) for a, b in zip(g["gen_lo"], g["gen_hi"]))):
            h = g[g["gen_lo"] == lo]
            rows.append([f"`{cell}`", f"{lo:,}–{hi:,}", f"{_fmt(quartiles(h['eaten_median'])[1])} "
                         f"({len(h)} · {int(h['dead'].sum()):,})"])
    out.append(_md_table(["묶음", "개체 세대", "먹은 양 중앙값(실행 · 개체)"], rows, ["l", "r", "r"]))
    return out + [""]


def _gate_a_md(df: pd.DataFrame, cells: list[str]) -> list[str]:
    """보고서의 '관문 A-1 판정 가능성' 절(lineage.csv 가 있는 실행이 있을 때만)."""
    if not df["window_births"].notna().any():
        return []
    lo, hi = GATE_A_BIRTH_WINDOW
    out = ["## 관문 A-1 판정 가능성(미리 보기)", "",
           f"DESIGN-v0.2 14.3 의 A-1 은 씨앗마다 {GATE_A_TICKS:,}틱까지 살고 틱 [{lo}, {hi}) 출생이 {GATE_A_MIN_BIRTHS} 이상이어야 "
           "판정합니다. 실행마다 값은 `summary.csv` 의 `extinct_tick`·`window_births`.", ""]
    rows = []
    for cell in cells:
        g = df[df["cell"] == cell]
        st = [gate_a_status(r) for _, r in g.iterrows()]
        wb = g["window_births"].dropna().astype(float).tolist()
        ext = [int(v) for v in g["extinct_tick"].dropna() if int(v) >= 0]
        rows.append([f"`{cell}`", str(len(g)), _pct(st.count("ok"), len(g)), _pct(st.count("extinct"), len(g)),
                     f"{min(ext):,}–{max(ext):,}" if ext else "—",
                     f"{_fmt(quartiles(wb)[1], 0)} [{_fmt(min(wb), 0)}–{_fmt(max(wb), 0)}]" if wb else "—"])
    out.append(_md_table(["묶음", "실행", "판정 가능", f"{GATE_A_TICKS:,}틱 전 멸종", "멸종 틱 범위",
                          f"출생 [{lo}, {hi}) 중앙값 [최소–최대]"], rows, ["l", "r", "r", "r", "r", "r"]))
    return out + [""]


def write_report_md(path: Path, root: Path, df: pd.DataFrame, cells: pd.DataFrame, plots: list[str],
                    plot_note: str, runs: dict[tuple[str, int], dict], acts: pd.DataFrame | None = None,
                    eaten: pd.DataFrame | None = None) -> None:
    """report.md: 묶음별 요약, 발견 세대, 행동 비율·먹은 양·관문 A-1 미리 보기(v0.2 0단계 열), 실행별 결과, 그림, 실패, 읽는 법."""
    out = ["# 실험 분석 보고서", ""]
    presets = sorted(set(str(p) or SNAPSHOT_CELL for p in df["preset"]))
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
    out.append("")
    order = cell_order(df)
    out += _action_md(acts, order)
    out += _eaten_md(eaten, order)
    out += _gate_a_md(df, order)
    out += ["## 실행별 결과", ""]
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
        "- **행동 비율**: 고름 = 그 행동을 고른 횟수 ÷ 그 구간 모든 개체·틱의 행동 수(판단하지 않은 틱의 되풀이 포함), "
        "효과 = 실제로 무언가 바뀐 횟수(DESIGN-v0.2 11.1 — 줍기는 운반이 늘 때, 내려놓기는 운반에서 나갈 때, 심기는 밭이 생길 때) "
        "÷ 같은 분모. 구간은 시계열 줄(기록 간격, 기본 20틱) 단위입니다.",
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
    err = make_out_dir(out_dir)
    if err:
        print("오류: " + err, file=sys.stderr)
        return 2
    cells = aggregate(df)
    write_csv(df, out_dir / "summary.csv")
    write_csv(cells, out_dir / "cells.csv")
    acts = action_table(df, series, root)
    eaten = eaten_table(df, root)
    # 행동 셈·먹은 양 열이 있는 실행이 있을 때만 쓴다(예전 결과 폴더에 빈 표를 남기지 않게)
    if len(acts):
        write_csv(acts, out_dir / "actions.csv")
    if len(eaten):
        write_csv(eaten, out_dir / "eaten.csv")
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
    write_report_md(out_dir / "report.md", root, df, cells, files, note, runs, acts, eaten)
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
    p.add_argument("--godot", default=os.environ.get("GODOT", "godot"),
                   help="godot 실행 파일(기본 환경 변수 GODOT 또는 godot). 상대 경로는 지금 폴더 기준. "
                        "Windows 는 Godot_v4.4.1-stable_win64_console.exe 경로를 큰따옴표로")
    p.add_argument("--repo", default=str(default_repo()), help="저장소(기본 tools/ 의 부모)")
    p.add_argument("--out", required=True, help="결과 폴더")
    p.add_argument("--lineage", dest="lineage", action="store_true", help="lineage.csv 도 쓰기(크다)")
    p.add_argument("--no-lineage", dest="lineage", action="store_false", help="lineage.csv 쓰지 않기(기본)")
    p.set_defaults(lineage=False)
    p.add_argument("--max-ticks", type=_max_ticks, default=None, help="틱 상한(1~SimConfig.TICK_MAX 의 정수, 기본 설정값)")
    p.add_argument("--timeout", type=float, default=3600.0, help="실행 하나의 시간 제한(초, 기본 3600)")
    p.add_argument("--no-report", action="store_true", help="실행만 하고 보고서는 만들지 않기")
    _add_report_opts(p)


def _add_report_opts(p: argparse.ArgumentParser) -> None:
    p.add_argument("--no-plots", action="store_true", help="그림 만들지 않기")
    p.add_argument("--lang", choices=["auto", "ko", "en"], default="auto",
                   help="그림 문구 언어(auto = 한글 글꼴이 되면 한국어)")


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="analyze.py", description="슬라임 실험실 오프라인 분석(헤드리스 실행 묶음·보고서)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Windows(cmd·PowerShell): py tools\\analyze.py …, 배열·쉼표 값은 큰따옴표로 "
               "(--param \"seasons.growth=[1,1,0.5,0],[1,1,1,1]\"), 줄잇기는 cmd ^ · PowerShell `, "
               "--godot \"C:\\…\\Godot_v4.4.1-stable_win64_console.exe\". 자세히: docs/ANALYSIS.md \"Windows\".")
    sub = ap.add_subparsers(dest="command", required=True)
    p = sub.add_parser("run", help="씨앗 여러 개를 같은 설정으로 돌리고 보고서")
    _add_batch_args(p)
    p.set_defaults(func=cmd_run)
    p = sub.add_parser("sweep", help="--param 격자 × 씨앗을 돌리고 묶음별 보고서")
    p.add_argument("--param", type=_arg_type(parse_param), action="append", required=True, metavar="KEY=V1,V2",
                   help="바꿔 볼 설정(여러 번 → 전체 격자), 예: --param mutation.rate=0.02,0.1")
    _add_batch_args(p)
    p.set_defaults(func=cmd_sweep)
    p = sub.add_parser("ablate", help="반사실 재생: 같은 스냅숏에서 그대로·설정을 바꾼 갈래를 돌려 견줌(DESIGN-v0.2 11.4)")
    p.add_argument("--runs", required=True, help="기준 실행 폴더(씨앗마다 seed<N>/ — 없으면 만들고, 같은 설정의 결과가 있으면 그대로 씀)")
    p.add_argument("--at-gen", type=_positive_number, required=True, help="기준 실행의 목표 평균 세대(그 끝 스냅숏에서 갈라짐)")
    p.add_argument("--set", type=_arg_type(parse_set), action="append", default=[], metavar="KEY=VALUE",
                   help="바꾼 갈래에 줄 설정(실행기 --fork-set, 여러 번). 저장된 배열 길이를 바꾸는 키(brain.hidden 등)는 실행기가 거부")
    p.add_argument("--reset-learned", action="store_true",
                   help="바꾼 갈래에 실행기 --fork-reset-learned(이식 시험: 배운 두뇌 = 유전체 — 학습을 켠 기준 실행만, "
                        "보통 --set learn.freeze=true 와 함께, DESIGN-v0.2 11.2). --set 이나 이것 가운데 하나는 있어야 함")
    p.add_argument("--ticks", type=_max_ticks, required=True, help="갈라진 뒤 돌릴 틱 수(1~SimConfig.TICK_MAX 의 정수)")
    p.add_argument("--seeds", type=_arg_type(parse_seeds), default=parse_seeds("1-4"),
                   help='씨앗: "1-12", "1,3,5" (기본 1-4)')
    p.add_argument("--preset", default="default", help="기준 실행의 예설정(기본 default)")
    p.add_argument("--base-set", type=_arg_type(parse_set), action="append", default=[], metavar="KEY=VALUE",
                   help="기준 실행의 설정 덮어쓰기(여러 번 — 두 갈래 모두 이 설정에서 시작)")
    p.add_argument("--out", default=None, help="갈래 결과·표 폴더(기본 <runs>-ablate/<키=값>__g<세대>__t<틱>)")
    p.add_argument("--jobs", type=int, default=max(1, min(4, os.cpu_count() or 1)),
                   help="동시에 돌릴 실행기 수(기본 min(4, CPU 수))")
    p.add_argument("--godot", default=os.environ.get("GODOT", "godot"), help="godot 실행 파일(run 과 같음)")
    p.add_argument("--repo", default=str(default_repo()), help="저장소(기본 tools/ 의 부모)")
    p.add_argument("--timeout", type=float, default=3600.0, help="실행 하나의 시간 제한(초, 기본 3600)")
    p.set_defaults(func=cmd_ablate)
    p = sub.add_parser("gate-a", help="관문 A(DESIGN-v0.2 14.3): 학습·freeze·셋째 행 갈래를 씨앗마다 돌려 판정 보고서")
    p.add_argument("--variant", choices=list(GATE_A_VARIANTS), default=GATE_A_OFFICIAL,
                   help=f"판정 조건(기본 {GATE_A_OFFICIAL} = 공식 A-1, 사용자 결정 2026-10-11 — A-1′ 세계, 생존 틱 요구 없음, 대상이 모두 "
                        "죽을 때까지). A-1 = 처음 정의(1,000틱 생존 필요 — 공식 아님). A-2 = 진화한 두뇌(보고 — learn_basic 30세대 "
                        "스냅숏에서 그대로·freeze, 기준 행 우연 기준)")
    p.add_argument("--seeds", type=_arg_type(parse_seeds), default=parse_seeds("1-12"),
                   help=f'씨앗(기본 1-12 — 판정 문턱은 씨앗 {GATE_A_SEEDS}개 기준, 다르면 값만 적고 판정하지 않음)')
    p.add_argument("--aux", action="store_true",
                   help="보조 판: 학습·freeze 갈래를 learn.diag_factor=none 으로(판정에 쓰지 않음, A-1 계열 변형만)")
    p.add_argument("--prereg", default="", metavar="COMMIT",
                   help="사전 고정 커밋(판정 문턱·지표를 판정 실행 전에 고정한 커밋): 보고서 머리에 그 커밋과, 지금 도는 analyze.py 가 "
                        "그 커밋의 것과 같은지(git)를 적음. 판정 문턱은 바꾸지 않음")
    p.add_argument("--out", required=True,
                   help="결과 폴더(갈래마다 <갈래>/seed<N>/ — A-2 는 기준 실행 base/seed<N>/ 도, 표 gate_a.csv·gate_a.md)")
    p.add_argument("--jobs", type=int, default=max(1, min(4, os.cpu_count() or 1)),
                   help="동시에 돌릴 실행기 수(기본 min(4, CPU 수))")
    p.add_argument("--godot", default=os.environ.get("GODOT", "godot"), help="godot 실행 파일(run 과 같음)")
    p.add_argument("--repo", default=str(default_repo()), help="저장소(기본 tools/ 의 부모)")
    p.add_argument("--timeout", type=float, default=3600.0, help="실행 하나의 시간 제한(초, 기본 3600)")
    p.set_defaults(func=cmd_gate_a)
    p = sub.add_parser("baldwin", help="볼드윈 보고서(DESIGN-v0.2 11.2): η·배운 양·동화 지수의 세대 추이, 이식 시험, 학습 끈 대조")
    p.add_argument("dir", help="학습을 켠 실행 결과 폴더(analyze.py run --lineage — 아래의 summary.json 을 모두 찾음)")
    p.add_argument("--probe", action="append", default=[], metavar="DIR",
                   help="이식 시험 폴더(analyze.py ablate --reset-learned --set learn.freeze=true 의 --out, 여러 번 — 평균 세대마다)")
    p.add_argument("--control-probe", action="append", default=[], metavar="DIR",
                   help="학습 끈 대조 폴더(학습을 끈 실행의 ablate --out — 그대로 갈래만 읽음, 같은 평균 세대의 --probe 와 견줌)")
    p.add_argument("--out", default=None, help="보고서 폴더(기본 결과 폴더)")
    p.set_defaults(func=cmd_baldwin)
    p = sub.add_parser("report", help="결과 폴더를 모아 summary.csv·report.md·그림")
    p.add_argument("dir", help="결과 폴더(아래의 summary.json 을 모두 찾음)")
    p.add_argument("--out", default=None, help="보고서 폴더(기본 결과 폴더)")
    _add_report_opts(p)
    p.set_defaults(func=cmd_report)
    return ap


def utf8_output() -> None:
    """표준 출력·오류를 UTF-8 로 다시 설정한다. Windows 는 출력을 파일·파이프로 돌리면 ANSI 코드 페이지(cp949·cp1252)를
    strict 로 써서 '—'·한글을 print 하다 UnicodeEncodeError 로 죽는다(검토 J30). reconfigure 가 없는 스트림(StringIO 등)은 그대로."""
    for stream in (sys.stdout, sys.stderr):
        reconf = getattr(stream, "reconfigure", None)
        if reconf is None:
            continue
        try:
            reconf(encoding="utf-8", errors="backslashreplace")
        except (ValueError, OSError):
            pass


def main(argv: list[str] | None = None) -> int:
    utf8_output()
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
