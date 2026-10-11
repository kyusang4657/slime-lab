#!/usr/bin/env python3
"""tools/analyze.py 검사(unittest).

  python3 -m unittest discover -s tools -p "test_*.py" -v

가짜 결과 폴더(묶음 2개 × 씨앗 2개, 작은 summary.json·timeseries.csv·chronicle.csv)를 만들어 보고서를 확인하고,
씨앗·격자 인자 해석과 run·sweep 이 만드는 godot 명령줄(subprocess 를 가짜로 바꿔서)을 확인한다.
godot 이 있으면(환경 변수 GODOT 또는 PATH) 실제 실행기로 아주 짧은 묶음을 한 번 돌린다.
"""
from __future__ import annotations

import contextlib
import csv
import io
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analyze  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
## config/sim-defaults.json 의 run.max_ticks 흉내(실행기가 summary.json 의 config 에 남기는 값)
CONFIG_MAX_TICKS = 2000000


# ── 가짜 실행 결과 ──

def write_fake_run(run_dir: Path, seed: int, disc: dict, *, civ: int, end_reason: str = "generations",
                   extinct_tick: int = -1, ticks: int = 400, final_gen: float = 8.0, preset: str = "default",
                   overrides: dict | None = None, odd_text: bool = False,
                   generations_target: float | None = None, max_ticks: int | None = None, bom: bool = False,
                   columns: list[str] | None = None, rows_fn=None, lineage: list[dict] | None = None,
                   summary_extra: dict | None = None, start_tick: int = 0) -> None:
    """실행기 결과 폴더 흉내(summary.json·timeseries.csv·chronicle.csv·final.snapshot.json — 끝까지 쓴 결과).
    disc = {"채집": (틱, 세대), ...} — 없는 단계는 발견 못 함.
    max_ticks 를 주면 실행기처럼 실제로 쓴 틱 상한과 설정의 run.max_ticks(기본 CONFIG_MAX_TICKS)를 남긴다.
    bom 이면 CSV 를 BOM 붙은 UTF-8 로(실행기·실험실 CSV 의 새 형식).
    columns = 시계열 열(기본 analyze.TIMESERIES_COLUMNS — v0.1 결과는 앞 22열), rows_fn(틱) = 그 줄에 덮어쓸 값 사전,
    lineage = lineage.csv 줄(사전 — 빠진 열은 0), summary_extra = summary.json 에 더할 키, start_tick = 첫 줄의 틱(이어 돌린 결과)."""
    csv_enc = "utf-8-sig" if bom else "utf-8"
    run_dir.mkdir(parents=True, exist_ok=True)
    names = analyze.STAGE_NAMES_KO
    summary = {
        "app_version": "0.1.0", "seed": seed, "tick": ticks, "population": 0 if end_reason == "extinction" else 120,
        "peak_population": 250, "mean_generation": 0.0 if end_reason == "extinction" else final_gen,
        "total_births": 300 + seed, "total_deaths": 280 + seed, "civ_stage": civ, "civ_stage_name": names[civ],
        "discovery_ticks": {n: (disc[n][0] if n in disc else -1) for n in ("채집", "저장", "농사")},
        "storehouses": 2 if civ >= 2 else 0, "farms": 5 if civ >= 3 else 0, "extinct_tick": extinct_tick,
        "history_hash": f"{seed:02d}" + "ab" * 31, "config": {"mutation": {"rate": 0.05}},
        "end_reason": end_reason, "run_seconds": 1.25 * seed,
        "generations_target": final_gen if generations_target is None else generations_target,
        "preset": preset, "overrides": overrides or {}, "resumed_from": "",
    }
    if max_ticks is not None:
        summary["max_ticks"] = max_ticks
        summary["config"]["run"] = {"max_ticks": float(CONFIG_MAX_TICKS)}
    summary.update(summary_extra or {})
    (run_dir / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent="\t"), encoding="utf-8")
    # 연대기: 발견 사건 + 쉼표가 든 저장고 사건(따옴표 처리 확인)
    lines = [",".join(analyze.CHRONICLE_COLUMNS)]
    for n in ("채집", "저장", "농사"):
        if n in disc:
            t, g = disc[n]
            text = f"{n} 발견 — 시험 (평균 {g:.1f}세대)" if not odd_text else f"새 발견 {n}"
            lines.append(f"{t},{g},discovery,-1,{text}")
            if n == "저장":
                lines.append(f'{t},{g},store_built,-1,"저장고 1호 — (41, 26)"')
    if end_reason == "extinction":
        lines.append(f"{extinct_tick},0.0,extinction,-1,멸종 — 마지막 개체가 사라짐")
    (run_dir / "chronicle.csv").write_text("\n".join(lines) + "\n", encoding=csv_enc)
    # 시계열: 20틱마다, 평균 세대는 틱에 비례, 크기는 조금씩 줄어듦
    cols = columns or analyze.TIMESERIES_COLUMNS
    rows = [",".join(cols)]
    for tick in range(start_tick, ticks + 1, 20):
        extinct_now = end_reason == "extinction" and tick >= extinct_tick
        pop = 0 if extinct_now else 100 + (tick // 20) % 7
        gen = 0.0 if extinct_now else final_gen * tick / ticks
        stage = max([0] + [i for i, n in enumerate(names) if n in disc and disc[n][0] <= tick])
        vals = {c: 0 for c in cols}
        vals.update({"tick": tick, "population": pop, "mean_gen": round(gen, 6),
                     "mean_size": 0.0 if extinct_now else round(1.0 - 0.001 * tick / 20, 6),
                     "mean_sense": 0.0 if extinct_now else 3.0, "civ_stage": stage})
        if rows_fn is not None:
            vals.update(rows_fn(tick))
        rows.append(",".join(str(vals[c]) for c in cols))
    (run_dir / "timeseries.csv").write_text("\n".join(rows) + "\n", encoding=csv_enc)
    if lineage is not None:
        lines = [",".join(analyze.LINEAGE_COLUMNS)]
        for r in lineage:
            lines.append(",".join(str(r.get(c, 0)) for c in analyze.LINEAGE_COLUMNS))
        (run_dir / "lineage.csv").write_text("\n".join(lines) + "\n", encoding=csv_enc)
    (run_dir / "final.snapshot.json").write_text('{"format": "slime-lab-snapshot"}', encoding="utf-8")


def make_fake_results(root: Path) -> None:
    """묶음 2개(a=1, a=2) × 씨앗 2개."""
    write_fake_run(root / "a=1" / "seed1", 1, {"채집": (100, 1.5), "저장": (200, 3.25), "농사": (400, 7.0)}, civ=3)
    write_fake_run(root / "a=1" / "seed2", 2, {"채집": (120, 2.5), "저장": (300, 5.75)}, civ=2)
    write_fake_run(root / "a=2" / "seed1", 1, {"채집": (150, 4.0)}, civ=1)
    write_fake_run(root / "a=2" / "seed2", 2, {}, civ=0, end_reason="extinction", extinct_tick=90, ticks=100)


def read_csv_rows(path: Path) -> list[dict]:
    """도구가 쓴 CSV(BOM 붙은 UTF-8)를 읽는다."""
    with path.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def quiet():
    """도구의 진행 출력을 숨긴다(작업 스레드의 print 도 sys.stdout 을 쓰므로 같이 숨겨짐)."""
    return contextlib.redirect_stdout(io.StringIO())


class TempDirCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="slime-analyze-"))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)


# ── 인자 해석 ──

class TestArgs(unittest.TestCase):
    def test_parse_seeds(self) -> None:
        self.assertEqual(analyze.parse_seeds("1-4"), [1, 2, 3, 4])
        self.assertEqual(analyze.parse_seeds("1,3,5"), [1, 3, 5])
        self.assertEqual(analyze.parse_seeds("7, 1-3,3"), [1, 2, 3, 7])
        self.assertEqual(analyze.parse_seeds("42"), [42])
        for bad in ("4-1", "a", "", "1-", "-3", "1.5"):
            with self.assertRaises(ValueError, msg=bad):
                analyze.parse_seeds(bad)

    def test_parse_set_and_param(self) -> None:
        self.assertEqual(analyze.parse_set("mutation.rate=0.08"), ("mutation.rate", "0.08"))
        self.assertEqual(analyze.parse_set("seasons.growth=[1,1,0.5,0]"), ("seasons.growth", "[1,1,0.5,0]"))
        for bad in ("mutation.rate", "=1", "a="):
            with self.assertRaises(ValueError, msg=bad):
                analyze.parse_set(bad)
        self.assertEqual(analyze.parse_param("mutation.rate=0.02,0.1,0.02"), ("mutation.rate", ["0.02", "0.1"]))
        with self.assertRaises(ValueError):
            analyze.parse_param("a=1,,2")
        # 배열 값: 괄호 안 쉼표는 나누지 않음
        self.assertEqual(analyze.parse_param("seasons.growth=[1,1,0.5,0],[1,1,1,1]"),
                         ("seasons.growth", ["[1,1,0.5,0]", "[1,1,1,1]"]))
        self.assertEqual(analyze.parse_param("a=[1,2]"), ("a", ["[1,2]"]))
        for bad in ("a=[1,2", "a=1,2]", "a=[1,2},[3]", "a=[1,x]"):
            with self.assertRaises(ValueError, msg=bad):
                analyze.parse_param(bad)
        grid = analyze.build_grid([analyze.parse_param("seasons.growth=[1,1,0.5,0],[1,1,1,1]")])
        self.assertEqual(len({c for c, _ in grid}), 2)  # 칸 폴더 이름이 겹치지 않음

    def test_grid(self) -> None:
        grid = analyze.build_grid([("mutation.rate", ["0.02", "0.1"]), ("resources.scale", ["1", "1.6"])])
        self.assertEqual([c for c, _ in grid], [
            "mutation.rate=0.02__resources.scale=1", "mutation.rate=0.02__resources.scale=1.6",
            "mutation.rate=0.1__resources.scale=1", "mutation.rate=0.1__resources.scale=1.6"])
        self.assertEqual(grid[3][1], [("mutation.rate", "0.1"), ("resources.scale", "1.6")])
        with self.assertRaises(ValueError):
            analyze.build_grid([("a", ["1"]), ("a", ["2"])])
        # 파일 이름에 못 쓰는 글자
        self.assertEqual(analyze.cell_dirname([("brain.policy", "a b/c")]), "brain.policy=a_b_c")

    def test_cli_parsing(self) -> None:
        p = analyze.build_parser()
        a = p.parse_args(["sweep", "--param", "a=1,2", "--param", "b=x", "--seeds", "1-3", "--out", "o",
                          "--set", "c=5", "--set", "d=6"])
        self.assertEqual(a.param, [("a", ["1", "2"]), ("b", ["x"])])
        self.assertEqual(a.seeds, [1, 2, 3])
        self.assertEqual(a.set, [("c", "5"), ("d", "6")])
        self.assertFalse(a.lineage)  # 묶음 실행은 기본으로 lineage 끔
        self.assertTrue(1 <= a.jobs <= 4)
        self.assertTrue(p.parse_args(["run", "--out", "o", "--lineage"]).lineage)
        with mock.patch.dict(os.environ, {"GODOT": "/opt/godot4"}):
            self.assertEqual(analyze.build_parser().parse_args(["run", "--out", "o"]).godot, "/opt/godot4")
        with quiet(), contextlib.redirect_stderr(io.StringIO()):
            for bad in (["run", "--out", "o", "--seeds", "3-1"], ["run", "--out", "o", "--generations", "0"],
                        ["sweep", "--out", "o"], ["run", "--out", "o", "--set", "novalue"]):
                with self.assertRaises(SystemExit, msg=str(bad)):
                    p.parse_args(bad)

    def test_generations_like_runner(self) -> None:
        """--generations 는 실행기(String.is_valid_float)가 받는 꼴만: 파이썬 float 만 읽는 1_0 은 실행 전에 인자 오류(I22)."""
        for good, want in (("100", "100"), ("2.5", "2.5"), ("1e3", "1e3"), (".5", ".5"), ("+5", "+5"), (" 10 ", "10")):
            self.assertEqual(analyze._positive_number(good), want, good)
        p = analyze.build_parser()
        with quiet(), contextlib.redirect_stderr(io.StringIO()):
            for bad in ("1_0", "-5", "0", "1e400", "inf", "nan", "abc", "١٢", "0x10"):
                with self.assertRaises(SystemExit, msg=bad):
                    p.parse_args(["run", "--out", "o", "--generations", bad])

    def test_max_ticks_like_runner(self) -> None:
        """--max-ticks 는 실행기와 같은 1~TICK_MAX 의 정수: 0·음수는 예전에 조용히 "상한 없음" 으로 돌았고, 상한 위는 모든
        실행이 실행기 인자 오류로 실패했음(검토 최종 확인 — I20 의 분석 도구 쪽)."""
        hi = analyze.tick_max()
        self.assertGreater(hi, 1)
        p = analyze.build_parser()
        for good, want in (("1", 1), ("2000", 2000), (str(hi), hi), (" +50 ", 50)):
            self.assertEqual(p.parse_args(["run", "--out", "o", "--max-ticks", good]).max_ticks, want, good)
        with quiet(), contextlib.redirect_stderr(io.StringIO()):
            for bad in ("0", "-5", str(hi + 1), "1e5", "1_0", "abc", "2.5"):
                with self.assertRaises(SystemExit, msg=bad):
                    p.parse_args(["sweep", "--out", "o", "--param", "a=1", "--max-ticks", bad])

    def test_quoted_key_rejected(self) -> None:
        """Windows cmd 는 작은따옴표를 벗기지 않음: 따옴표째 넘어온 키는 모든 실행이 '알 수 없는 키' 로 실패하기 전에
        인자 오류로, 큰따옴표를 쓰라고 안내(J23)."""
        for bad in ("'mutation.rate=0.08'", "'mutation.rate=0.02,0.1'", "'seasons.growth=[1,1,0.5,0],[1,1,1,1]'",
                    '"a.b=1'):
            with self.assertRaises(ValueError, msg=bad) as cm:
                analyze.parse_param(bad)
            self.assertIn("큰따옴표", str(cm.exception))
        with quiet(), contextlib.redirect_stderr(io.StringIO()) as err:
            with self.assertRaises(SystemExit):
                analyze.build_parser().parse_args(["run", "--out", "o", "--set", "'mutation.rate=0.08'"])
        self.assertIn("큰따옴표", err.getvalue())

    def test_natural_order(self) -> None:
        cells = ["rate=0.1", "rate=0.02", "rate=1.5", "rate=0.05"]
        self.assertEqual(sorted(cells, key=analyze.natural_key), ["rate=0.02", "rate=0.05", "rate=0.1", "rate=1.5"])
        self.assertEqual(sorted(["seed10", "seed2", "seed1"], key=analyze.natural_key), ["seed1", "seed2", "seed10"])
        # '-' 는 구분자: 하이픈 번호·날짜 폴더가 거꾸로 서지 않음
        self.assertEqual(sorted(["trial-10", "trial-2", "trial-1"], key=analyze.natural_key), ["trial-1", "trial-2", "trial-10"])
        self.assertEqual(sorted(["2026-10-07", "2026-09-30"], key=analyze.natural_key), ["2026-09-30", "2026-10-07"])
        # '=' 바로 뒤·맨 앞의 '-' 는 음수 부호
        self.assertEqual(sorted(["x=0.1", "x=-0.5", "x=-1", "x=2"], key=analyze.natural_key), ["x=-1", "x=-0.5", "x=0.1", "x=2"])
        self.assertEqual(sorted(["3", "-1", "-5"], key=analyze.natural_key), ["-5", "-1", "3"])


# ── 보고서 ──

class TestReport(TempDirCase):
    def setUp(self) -> None:
        super().setUp()
        self.res = self.tmp / "results"
        make_fake_results(self.res)
        self.out = self.tmp / "report"

    def run_report(self, out: Path, **kw) -> int:
        with quiet():
            return analyze.report(self.res, out, **kw)

    def test_summary_csv(self) -> None:
        self.assertEqual(self.run_report(self.out, plots=False), 0)
        rows = read_csv_rows(self.out / "summary.csv")
        self.assertEqual(list(rows[0].keys()), analyze.SUMMARY_COLUMNS)
        self.assertEqual([(r["cell"], r["seed"]) for r in rows],
                         [("a=1", "1"), ("a=1", "2"), ("a=2", "1"), ("a=2", "2")])
        # 발견 세대 = 연대기 discovery 줄의 mean_gen, 없으면 NaN
        self.assertEqual([r["disc_gen_forage"] for r in rows], ["1.5", "2.5", "4", "NaN"])
        self.assertEqual([r["disc_gen_store"] for r in rows], ["3.25", "5.75", "NaN", "NaN"])
        self.assertEqual([r["disc_gen_farm"] for r in rows], ["7", "NaN", "NaN", "NaN"])
        self.assertEqual([r["disc_tick_store"] for r in rows], ["200", "300", "-1", "-1"])
        self.assertEqual(rows[3]["end_reason"], "extinction")
        self.assertEqual(rows[3]["extinct_tick"], "90")
        self.assertEqual(rows[0]["civ_stage_name"], "농사")
        self.assertEqual(rows[0]["ticks"], "400")
        self.assertEqual(rows[1]["run_seconds"], "2.5")
        self.assertEqual(rows[0]["path"], "a=1/seed1")
        self.assertTrue(rows[0]["history_hash"].startswith("01abab"))
        # 끝 특성 = 살아 있던 마지막 줄(멸종 뒤 0 줄은 빼고)
        self.assertEqual(rows[0]["final_mean_size"], "0.98")
        self.assertEqual(rows[3]["final_mean_sense"], "3")
        # 멸종한 실행의 끝 평균 세대 = 멸종 직전 값(summary.json 의 0 이 아님): 시계열 80틱 줄 = 8.0 × 80/100
        self.assertEqual(rows[3]["mean_generation"], "6.4")

    def test_aggregation(self) -> None:
        self.run_report(self.out, plots=False)
        cells = {r["cell"]: r for r in read_csv_rows(self.out / "cells.csv")}
        self.assertEqual(list(cells), ["a=1", "a=2"])
        a1, a2 = cells["a=1"], cells["a=2"]
        f = float
        self.assertEqual((a1["runs"], a1["extinct"], f(a1["extinction_rate"])), ("2", "0", 0.0))
        self.assertEqual((a2["runs"], a2["extinct"], f(a2["extinction_rate"])), ("2", "1", 0.5))
        rates = ("reach_rate_forage", "reach_rate_store", "reach_rate_farm")
        self.assertEqual(tuple(f(a1[k]) for k in rates), (1.0, 1.0, 0.5))
        self.assertEqual(tuple(f(a2[k]) for k in rates), (0.5, 0.0, 0.0))
        # 사분위(numpy 선형): [1.5, 2.5] → Q1 1.75, 중앙값 2.0, Q3 2.25
        self.assertAlmostEqual(f(a1["disc_gen_forage_median"]), 2.0)
        self.assertAlmostEqual(f(a1["disc_gen_forage_q1"]), 1.75)
        self.assertAlmostEqual(f(a1["disc_gen_forage_q3"]), 2.25)
        self.assertAlmostEqual(f(a1["disc_gen_forage_iqr"]), 0.5)
        self.assertAlmostEqual(f(a1["disc_gen_store_median"]), 4.5)
        self.assertAlmostEqual(f(a1["disc_gen_store_q1"]), 3.875)
        self.assertEqual((a1["disc_gen_farm_n"], f(a1["disc_gen_farm_median"])), ("1", 7.0))
        self.assertEqual((a2["disc_gen_forage_n"], f(a2["disc_gen_forage_median"])), ("1", 4.0))
        self.assertEqual(a2["disc_gen_store_n"], "0")
        self.assertTrue(math.isnan(f(a2["disc_gen_store_median"])))
        self.assertAlmostEqual(f(a1["run_seconds_total"]), 1.25 + 2.5)
        # 멸종한 실행(0)이 끝 평균 세대 중앙값을 끌어내리지 않음: [8.0, 6.4] → 7.2 (고치기 전 [8.0, 0.0] → 4.0)
        self.assertAlmostEqual(f(a2["mean_generation_median"]), 7.2)

    def test_gdignore(self) -> None:
        """보고서 폴더(그리고 run·sweep 결과 폴더)에 .gdignore — 저장소 안이어도 Godot 이 CSV·PNG 를 가져오지 않게."""
        self.assertEqual(self.run_report(self.out, plots=False), 0)
        self.assertTrue((self.out / ".gdignore").is_file())
        for cmd in (["run", "--seeds", "1"], ["sweep", "--param", "a=1,2", "--seeds", "1"]):
            out = self.tmp / cmd[0]
            with mock.patch.object(analyze.subprocess, "run", FakeRunner()), quiet():
                analyze.main(cmd + ["--out", str(out), "--godot", "g", "--no-plots"])
            self.assertTrue((out / ".gdignore").is_file(), cmd[0])

    def test_report_md_and_plots(self) -> None:
        self.assertEqual(self.run_report(self.out), 0)
        md = (self.out / "report.md").read_text(encoding="utf-8")
        for heading in ("# 실험 분석 보고서", "## 묶음별 요약", "## 발견 세대", "## 실행별 결과", "## 그림", "## 읽는 법"):
            self.assertIn(heading, md)
        self.assertIn("| `a=2` | 2 | 50% (1/2) |", md)  # 멸종 비율
        self.assertIn("2.0 [1.8–2.2] (2/2)", md)  # 채집 발견 세대 중앙값 [Q1–Q3]
        if analyze.load_pyplot() is None:
            self.skipTest("matplotlib 없음 — 그림 검사 건너뜀")
        for name in ("population.png", "mean_gen.png", "traits.png", "civ_stage.png", "discovery.png"):
            p = self.out / name
            self.assertTrue(p.is_file() and p.stat().st_size > 5000, name)
            self.assertEqual(p.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
            self.assertIn(f"]({name})", md)

    def test_many_cells_use_facets(self) -> None:
        """묶음이 색 수(8)보다 많으면 색을 돌려쓰지 않고 묶음마다 작은 그림 — 특성은 그림 두 장으로."""
        if analyze.load_pyplot() is None:
            self.skipTest("matplotlib 없음")
        root = self.tmp / "many"
        for i in range(len(analyze.PALETTE) + 1):
            write_fake_run(root / f"rate=0.{i:02d}" / "seed1", 1, {"채집": (100, 1.0 + i)}, civ=1)
        with quiet():
            analyze.report(root, self.out)
        names = sorted(p.name for p in self.out.glob("*.png"))
        self.assertEqual(names, ["civ_stage.png", "discovery.png", "mean_gen.png", "population.png",
                                 "traits_mean_sense.png", "traits_mean_size.png"])
        md = (self.out / "report.md").read_text(encoding="utf-8")
        self.assertIn("](traits_mean_size.png)", md)

    def test_without_matplotlib(self) -> None:
        with mock.patch.object(analyze, "load_pyplot", return_value=None):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                self.assertEqual(analyze.report(self.res, self.out), 0)
        self.assertIn("matplotlib 이 없어", buf.getvalue())
        self.assertEqual(sorted(p.name for p in self.out.glob("*.png")), [])
        self.assertTrue((self.out / "summary.csv").is_file())
        self.assertIn("matplotlib 이 없어", (self.out / "report.md").read_text(encoding="utf-8"))

    def test_deterministic(self) -> None:
        self.run_report(self.tmp / "r1", plots=False)
        self.run_report(self.tmp / "r2", plots=False)
        for name in ("summary.csv", "cells.csv", "report.md"):
            self.assertEqual((self.tmp / "r1" / name).read_bytes(), (self.tmp / "r2" / name).read_bytes(), name)

    def test_root_cell_named_by_preset(self) -> None:
        """run 결과(씨앗 폴더가 바로 아래) → 묶음 이름 = 예설정(+덮어쓰기)."""
        root = self.tmp / "batch"
        write_fake_run(root / "seed1", 1, {"채집": (10, 0.5)}, civ=1, preset="fast_civ",
                       overrides={"mutation.rate": 0.08})
        write_fake_run(root / "seed2", 2, {}, civ=0, preset="fast_civ", overrides={"mutation.rate": 0.08})
        with quiet():
            analyze.report(root, root, plots=False)
        rows = read_csv_rows(root / "summary.csv")
        self.assertEqual([r["cell"] for r in rows], ["fast_civ+mutation.rate=0.08"] * 2)
        self.assertEqual(rows[0]["overrides"], "mutation.rate=0.08")

    def test_csv_has_bom(self) -> None:
        """도구가 쓰는 CSV 는 BOM 붙은 UTF-8 — 한국어 Windows 엑셀이 civ_stage_name('농사') 등을 cp949 로 깨뜨리지 않게(J07).
        pandas·csv 는 BOM 을 건너뛰고 첫 열 이름을 그대로 읽음."""
        import pandas as pd
        self.assertEqual(self.run_report(self.out, plots=False), 0)
        for name in ("summary.csv", "cells.csv"):
            raw = (self.out / name).read_bytes()
            self.assertEqual(raw[:3], b"\xef\xbb\xbf", name)
            self.assertEqual(raw.count(b"\xef\xbb\xbf"), 1, name)
            self.assertEqual(pd.read_csv(self.out / name).columns[0], "cell", name)
        self.assertIn("농사", (self.out / "summary.csv").read_bytes()[3:].decode("utf-8"))
        out = self.tmp / "runs"
        with mock.patch.object(analyze.subprocess, "run", FakeRunner()), quiet():
            analyze.main(["run", "--seeds", "1-2", "--out", str(out), "--godot", "g", "--no-plots"])
        self.assertEqual((out / "runs.csv").read_bytes()[:3], b"\xef\xbb\xbf")
        self.assertEqual([r["seed"] for r in read_csv_rows(out / "runs.csv")], ["1", "2"])

    def test_reads_bom_runner_csv(self) -> None:
        """실행기·실험실 CSV 에 BOM 이 붙어도(새 형식) 같은 표: 연대기 첫 열(tick)을 잃으면 발견 세대가 시계열 보간으로 바뀜."""
        plain, bom = self.tmp / "plain", self.tmp / "bom"
        for root, b in ((plain, False), (bom, True)):
            write_fake_run(root / "x" / "seed1", 1, {"채집": (100, 1.37), "저장": (200, 3.21)}, civ=2, bom=b)
            with quiet():
                analyze.report(root, root, plots=False)
        self.assertEqual((bom / "x" / "seed1" / "chronicle.csv").read_bytes()[:3], b"\xef\xbb\xbf")
        self.assertEqual((plain / "summary.csv").read_bytes(), (bom / "summary.csv").read_bytes())
        self.assertEqual(read_csv_rows(bom / "summary.csv")[0]["disc_gen_forage"], "1.37")

    def test_snapshot_cell_name(self) -> None:
        """예설정 이름을 모르는 실행(이어 돌린 실행기 결과·스냅숏을 연 실험실 내보내기 — preset "")은 묶음 이름 snapshot(I05)."""
        root = self.tmp / "resumed"
        write_fake_run(root / "seed1", 1, {"채집": (10, 0.5)}, civ=1, preset="")
        with quiet():
            analyze.report(root, root, plots=False)
        rows = read_csv_rows(root / "summary.csv")
        self.assertEqual((rows[0]["cell"], rows[0]["preset"], rows[0]["overrides"]), (analyze.SNAPSHOT_CELL, "", ""))
        self.assertIn("예설정 `snapshot`", (root / "report.md").read_text(encoding="utf-8"))

    def test_empty_dir(self) -> None:
        empty = self.tmp / "empty"
        empty.mkdir()
        with quiet(), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(analyze.report(empty, None, plots=False), 1)


class TestDiscovery(unittest.TestCase):
    def test_fallbacks(self) -> None:
        import pandas as pd
        ts = pd.DataFrame({"tick": [0, 100, 200], "population": [10, 10, 10], "mean_gen": [0.0, 1.0, 3.0]})
        ticks = {"채집": 50, "저장": 150, "농사": -1}
        # 연대기 없음 → 시계열 보간
        d = analyze.discovery_generations(None, ticks, ts)
        self.assertEqual(d["forage"], (50, 0.5))
        self.assertEqual(d["store"], (150, 2.0))
        self.assertEqual(d["farm"][0], -1)
        self.assertTrue(math.isnan(d["farm"][1]))
        # 문장 머리가 다르면 같은 틱의 discovery 사건
        chron = pd.DataFrame({"tick": [50, 150], "mean_gen": [0.61, 2.22], "kind": ["discovery", "discovery"],
                              "text": ["새 발견 하나", "새 발견 둘"]})
        d = analyze.discovery_generations(chron, ticks, ts)
        self.assertEqual(d["forage"], (50, 0.61))
        self.assertEqual(d["store"], (150, 2.22))
        # 문장 머리가 우선(틱이 summary 와 달라도 단계 이름으로 맞춤)
        chron = pd.DataFrame({"tick": [51], "mean_gen": [0.7], "kind": ["discovery"], "text": ["채집 발견 — x"]})
        self.assertEqual(analyze.discovery_generations(chron, ticks, None)["forage"], (50, 0.7))


# ── run·sweep 명령줄(가짜 subprocess) ──

class FakeRunner:
    """subprocess.run 대신: 명령줄을 모으고, --out 폴더에 가짜 결과를 쓰고, RESULT 줄을 돌려준다."""

    def __init__(self, fail_seeds: tuple = (), timeout_seeds: tuple = ()):
        self.calls: list[tuple[list, dict]] = []
        self.lock = threading.Lock()
        self.fail_seeds = fail_seeds
        self.timeout_seeds = timeout_seeds

    def __call__(self, cmd, **kw):
        with self.lock:
            self.calls.append((list(cmd), kw))
        args = dict(a[2:].split("=", 1) for a in cmd[cmd.index("--") + 1:] if "=" in a)
        seed = int(args["seed"])
        if seed in self.timeout_seeds:
            raise subprocess.TimeoutExpired(cmd, kw.get("timeout"), output=b"", stderr=b"")
        if seed in self.fail_seeds:
            return subprocess.CompletedProcess(cmd, 2, "", "설정 오류: 알 수 없는 키\n")
        # 실행기처럼 실제로 받은 설정을 summary.json 에 남긴다(이어 돌리기 때 설정 비교용)
        sets = {}
        for a in cmd[cmd.index("--") + 1:]:
            if a.startswith("--set="):
                k, _, v = a[6:].partition("=")
                try:
                    sets[k] = json.loads(v)
                except ValueError:
                    sets[k] = v
        cap = int(args["max-ticks"]) if "max-ticks" in args else CONFIG_MAX_TICKS
        write_fake_run(Path(args["out"]), seed, {"채집": (100, 1.0 + seed)}, civ=1, preset=args["preset"],
                       overrides=sets, generations_target=float(args["generations"]), max_ticks=cap)
        res = f"RESULT: seed={seed} generations=8.0 ticks=400 pop=120 civ=1(채집) hash=0123 time=0.1s reason=generations"
        return subprocess.CompletedProcess(cmd, 0, "Godot Engine v4.4.1\n" + res + "\n", "")


class TestRunCommands(TempDirCase):
    def test_run_commands_and_resume(self) -> None:
        out = self.tmp / "batch"
        # 씨앗 2 는 같은 설정으로 이미 있음 → 건너뜀
        write_fake_run(out / "seed2", 2, {}, civ=0, preset="fast_civ", overrides={"mutation.rate": 0.08},
                       generations_target=5.0)
        fake = FakeRunner()
        with mock.patch.object(analyze.subprocess, "run", fake), quiet():
            code = analyze.main(["run", "--seeds", "1-3", "--generations", "5", "--preset", "fast_civ",
                                 "--set", "mutation.rate=0.08", "--out", str(out), "--godot", "/opt/godot",
                                 "--jobs", "2", "--timeout", "77", "--no-plots"])
        self.assertEqual(code, 0)
        cmds = sorted((c for c, _ in fake.calls), key=lambda c: c[7])
        self.assertEqual(len(cmds), 2)
        for seed, cmd in zip((1, 3), cmds):
            self.assertEqual(cmd, ["/opt/godot", "--headless", "--path", str(REPO), "--script",
                                   "res://tests/run_experiment.gd", "--", f"--seed={seed}", "--generations=5",
                                   f"--out={out.resolve() / f'seed{seed}'}", "--preset=fast_civ",
                                   "--set=mutation.rate=0.08", "--no-lineage", "--quiet"])
        for _, kw in fake.calls:
            self.assertEqual(kw.get("timeout"), 77.0)
            self.assertEqual(kw.get("cwd"), str(REPO))
            # 실행기 출력은 OS 의 코드 페이지가 아니라 UTF-8 로 읽는다(Windows cp949·cp1252 에서 "농사" 가 깨지지 않게)
            self.assertEqual((kw.get("encoding"), kw.get("errors")), ("utf-8", "replace"))
        runs = read_csv_rows(out / "runs.csv")
        self.assertEqual([(r["seed"], r["status"]) for r in runs], [("1", "ok"), ("2", "existing"), ("3", "ok")])
        self.assertTrue(runs[0]["result"].startswith("RESULT: seed=1 "))
        self.assertEqual(runs[0]["exit_code"], "0")
        self.assertTrue((out / "seed1" / "run.log").is_file())
        self.assertEqual(len(read_csv_rows(out / "summary.csv")), 3)
        # 같은 명령을 다시 주면 모두 건너뛰고, 앞서 성공한 줄은 그대로
        fake2 = FakeRunner()
        with mock.patch.object(analyze.subprocess, "run", fake2), quiet():
            code = analyze.main(["run", "--seeds", "1-3", "--generations", "5.0", "--preset", "fast_civ",
                                 "--set", "mutation.rate=0.080", "--out", str(out), "--godot", "/opt/godot",
                                 "--no-plots"])
        self.assertEqual(code, 0)
        self.assertEqual(fake2.calls, [])
        self.assertEqual([r["status"] for r in read_csv_rows(out / "runs.csv")], ["ok", "existing", "ok"])

    def test_resume_with_other_settings_is_flagged(self) -> None:
        """같은 결과 폴더에 다른 설정으로 다시 돌리면 덮어쓰지도 섞어 세지도 않고 mismatch 로 알린다."""
        out = self.tmp / "batch"
        with mock.patch.object(analyze.subprocess, "run", FakeRunner()), quiet():
            analyze.main(["run", "--seeds", "1-2", "--generations", "5", "--out", str(out), "--godot", "g",
                          "--no-plots"])
        fake = FakeRunner()
        buf = io.StringIO()
        with mock.patch.object(analyze.subprocess, "run", fake), contextlib.redirect_stdout(buf):
            code = analyze.main(["run", "--seeds", "1-3", "--generations", "6", "--set", "mutation.rate=0.1",
                                 "--out", str(out), "--godot", "g", "--no-plots"])
        self.assertEqual(code, 1)
        self.assertEqual([c[7] for c, _ in fake.calls], ["--seed=3"])  # 없는 씨앗만 실제로 돌림
        runs = {r["seed"]: r for r in read_csv_rows(out / "runs.csv")}
        self.assertEqual([runs[s]["status"] for s in ("1", "2", "3")], ["mismatch", "mismatch", "ok"])
        self.assertIn("generations 5.0 ≠ 6", runs["1"]["result"])
        self.assertIn("mutation.rate 없음 ≠ 0.1", runs["1"]["result"])
        self.assertIn("설정이 다른 결과", buf.getvalue())
        self.assertIn("mismatch", (out / "report.md").read_text(encoding="utf-8"))

    def test_resume_with_other_max_ticks_is_flagged(self) -> None:
        """--max-ticks 로 잘린 결과를 상한 없는 요청이 그대로 쓰지 않음(그 반대도), 같은 상한이면 건너뜀."""
        out = self.tmp / "cap"
        with mock.patch.object(analyze.subprocess, "run", FakeRunner()), quiet():
            analyze.main(["run", "--seeds", "1", "--generations", "5", "--max-ticks", "100", "--out", str(out),
                          "--godot", "g", "--no-plots"])
        with mock.patch.object(analyze.subprocess, "run", FakeRunner()), quiet():
            code = analyze.main(["run", "--seeds", "1", "--generations", "5", "--out", str(out), "--godot", "g", "--no-plots"])
        runs = read_csv_rows(out / "runs.csv")
        self.assertEqual((code, runs[0]["status"]), (1, "mismatch"))
        self.assertIn(f"max_ticks 100 ≠ {CONFIG_MAX_TICKS}", runs[0]["result"])
        # 반대: 상한 없이 돌린 결과에 --max-ticks 요청
        out2 = self.tmp / "cap2"
        with mock.patch.object(analyze.subprocess, "run", FakeRunner()), quiet():
            analyze.main(["run", "--seeds", "1", "--generations", "5", "--out", str(out2), "--godot", "g", "--no-plots"])
        with mock.patch.object(analyze.subprocess, "run", FakeRunner()), quiet():
            code = analyze.main(["run", "--seeds", "1", "--generations", "5", "--max-ticks", "300", "--out", str(out2),
                                 "--godot", "g", "--no-plots"])
        self.assertEqual((code, read_csv_rows(out2 / "runs.csv")[0]["status"]), (1, "mismatch"))
        # 같은 상한이면 그대로 건너뜀
        fake = FakeRunner()
        with mock.patch.object(analyze.subprocess, "run", fake), quiet():
            code = analyze.main(["run", "--seeds", "1", "--generations", "5", "--max-ticks", "100", "--out", str(out),
                                 "--godot", "g", "--no-plots"])
        self.assertEqual((code, fake.calls, read_csv_rows(out / "runs.csv")[0]["status"]), (0, [], "existing"))

    def test_failed_or_incomplete_is_rerun(self) -> None:
        """summary.json 이 있어도 이전 상태가 failed·timeout·error 이거나 결과 파일이 덜 쓰였으면 'existing' 으로 바꾸지 않고
        다시 돌린다(실행기는 summary.json 을 먼저 쓰고 그 뒤 쓰기에서 실패할 수 있음, I07). 끝까지 쓴 성공 결과는 그대로 건너뜀."""
        out = self.tmp / "retry"
        with mock.patch.object(analyze.subprocess, "run", FakeRunner()), quiet():
            analyze.main(["run", "--seeds", "1-5", "--generations", "5", "--out", str(out), "--godot", "g", "--no-plots"])
        rows = analyze.read_runs_csv(out / "runs.csv")
        for seed, status in ((1, "failed"), (2, "timeout")):
            rows[(analyze.ROOT_CELL, seed)]["status"] = status
        analyze.write_runs_csv(out / "runs.csv", rows)
        (out / "seed3" / "chronicle.csv").write_bytes(b"")  # 쓰다 실패: 0바이트
        (out / "seed4" / "final.snapshot.json").unlink()  # 쓰기 전에 끊김
        s5 = json.loads((out / "seed5" / "summary.json").read_text(encoding="utf-8"))
        fake = FakeRunner()
        buf = io.StringIO()
        with mock.patch.object(analyze.subprocess, "run", fake), contextlib.redirect_stdout(buf):
            code = analyze.main(["run", "--seeds", "1-5", "--generations", "5", "--out", str(out), "--godot", "g",
                                 "--no-plots"])
        self.assertEqual(code, 0)
        self.assertEqual(sorted(c[7] for c, _ in fake.calls), ["--seed=1", "--seed=2", "--seed=3", "--seed=4"])
        self.assertEqual([r["status"] for r in read_csv_rows(out / "runs.csv")], ["ok"] * 5)
        self.assertIn("다시 돌림(이전 실행 failed)", buf.getvalue())
        self.assertIn("다시 돌림(chronicle.csv 없음)", buf.getvalue())
        self.assertEqual(json.loads((out / "seed5" / "summary.json").read_text(encoding="utf-8")), s5)

    def test_incomplete_reason(self) -> None:
        d = self.tmp / "inc"
        write_fake_run(d, 1, {}, civ=0)
        self.assertEqual(analyze.incomplete_reason(d), "")
        s = json.loads((d / "summary.json").read_text(encoding="utf-8"))
        s["write_failed"] = ["snapshot-20.json(저장 실패)"]
        (d / "summary.json").write_text(json.dumps(s, ensure_ascii=False), encoding="utf-8")
        self.assertIn("snapshot-20.json", analyze.incomplete_reason(d))
        s["write_failed"] = []
        s["history_hash"] = ""
        (d / "summary.json").write_text(json.dumps(s), encoding="utf-8")
        self.assertIn("역사 해시", analyze.incomplete_reason(d))
        (d / "summary.json").write_text("{깨짐", encoding="utf-8")
        self.assertIn("읽을 수 없음", analyze.incomplete_reason(d))

    def test_relative_godot_path(self) -> None:
        """--godot ./x 는 지금 셸 위치 기준(--out·--repo 와 같음) — 실행기는 저장소 폴더에서 돌므로 절대 경로로 넘김(I22).
        이름만 주면(godot) PATH 에서 찾게 그대로."""
        for i, (given, want) in enumerate((("./mygodot", os.path.abspath("./mygodot")),
                                           ("bin/godot", os.path.abspath("bin/godot")),
                                           ("/opt/godot", "/opt/godot"), ("godot", "godot"))):
            fake = FakeRunner()
            with mock.patch.object(analyze.subprocess, "run", fake), quiet():
                analyze.main(["run", "--seeds", "1", "--out", str(self.tmp / f"g{i}"), "--godot", given,
                              "--no-report"])
            self.assertEqual(fake.calls[0][0][0], want, given)
            self.assertEqual(fake.calls[0][1].get("cwd"), str(REPO))

    def test_command_text(self) -> None:
        """runs.csv 의 command 열은 그 OS 셸에 붙여 다시 돌릴 수 있게: Windows = cmd 따옴표(list2cmdline), 그 밖 = POSIX(J23)."""
        cmd = ["C:\\Godot dir\\godot_console.exe", "--", "--set=seasons.growth=[1,1,0.5,0]", "--out=C:\\결과 폴더\\seed1"]
        self.assertEqual(analyze.command_text(cmd, windows=True),
                         '"C:\\Godot dir\\godot_console.exe" -- --set=seasons.growth=[1,1,0.5,0] "--out=C:\\결과 폴더\\seed1"')
        self.assertEqual(analyze.command_text(cmd, windows=False),
                         "'C:\\Godot dir\\godot_console.exe' -- '--set=seasons.growth=[1,1,0.5,0]' '--out=C:\\결과 폴더\\seed1'")
        out = self.tmp / "cmdtext"
        fake = FakeRunner()
        with mock.patch.object(analyze.subprocess, "run", fake), quiet():
            analyze.main(["run", "--seeds", "1", "--out", str(out), "--godot", "g", "--no-report"])
        self.assertEqual(read_csv_rows(out / "runs.csv")[0]["command"], analyze.command_text(fake.calls[0][0]))

    def test_output_on_legacy_codepages(self) -> None:
        """Windows 에서 출력을 파일·파이프로 돌리면 ANSI 코드 페이지(cp949·cp1252) strict — 실패 꼬리말의 '—'·한글에서
        UnicodeEncodeError 로 죽어 runs.csv·안내가 빠지던 것(J30). main() 이 표준 출력·오류를 UTF-8 로 다시 설정한다."""
        for enc in ("cp949", "cp1252"):
            out = self.tmp / f"cp-{enc}"
            stdout = io.TextIOWrapper(io.BytesIO(), encoding=enc, errors="strict")
            stderr = io.TextIOWrapper(io.BytesIO(), encoding=enc, errors="strict")
            with mock.patch.object(sys, "stdout", stdout), mock.patch.object(sys, "stderr", stderr):
                code = analyze.main(["run", "--seeds", "1-2", "--out", str(out), "--godot",
                                     str(self.tmp / "없는-godot"), "--jobs", "1"])
                sys.stdout.flush()
            text = stdout.buffer.getvalue().decode("utf-8")
            self.assertEqual(code, 1, enc)
            self.assertIn("(RESULT 없음 — seed1/run.log 참고)", text)
            self.assertIn("godot 실행 파일을 찾지 못했을 수 있습니다", text)
            self.assertEqual([r["status"] for r in read_csv_rows(out / "runs.csv")], ["error", "error"])

    def test_utf8_output_from_real_child(self) -> None:
        """실제 자식 프로세스가 UTF-8 로 쓴 RESULT 줄(한글)을 그대로 읽는다(지역 코드 페이지와 무관)."""
        out = self.tmp / "u"
        job = analyze.Job("x", 1, out, [sys.executable, "-c",
                                        "import sys; sys.stdout.buffer.write('RESULT: civ=3(농사)\\n'.encode('utf-8'))"])
        row = analyze.execute_job(job, self.tmp, 60)
        self.assertEqual(row["result"], "RESULT: civ=3(농사)")

    def test_same_value(self) -> None:
        self.assertTrue(analyze._same_value("0.10", 0.1))
        self.assertTrue(analyze._same_value("40", 40.0))
        self.assertTrue(analyze._same_value("[1,1,0.5,0]", [1.0, 1.0, 0.5, 0.0]))
        self.assertTrue(analyze._same_value("sample", "sample"))
        self.assertFalse(analyze._same_value("0.1", 0.2))
        self.assertFalse(analyze._same_value("argmax", "sample"))

    def test_sweep_commands(self) -> None:
        out = self.tmp / "sweep"
        fake = FakeRunner()
        with mock.patch.object(analyze.subprocess, "run", fake), quiet():
            code = analyze.main(["sweep", "--param", "mutation.rate=0.02,0.1", "--param", "resources.scale=1,1.6",
                                 "--seeds", "1,2", "--generations", "3", "--set", "mutation.rate=0.5",
                                 "--set", "time.season_days=4", "--lineage", "--max-ticks", "900",
                                 "--out", str(out), "--godot", "g", "--no-plots"])
        self.assertEqual(code, 0)
        self.assertEqual(len(fake.calls), 8)
        by_out = {next(a for a in c if a.startswith("--out="))[6:]: c for c, _ in fake.calls}
        cell = "mutation.rate=0.1__resources.scale=1.6"
        cmd = by_out[str(out.resolve() / cell / "seed2")]
        self.assertEqual(cmd[cmd.index("--") + 1:], [
            "--seed=2", "--generations=3", f"--out={out.resolve() / cell / 'seed2'}", "--preset=default",
            "--set=mutation.rate=0.5", "--set=time.season_days=4",  # 고정 덮어쓰기 뒤에
            "--set=mutation.rate=0.1", "--set=resources.scale=1.6",  # 격자 값(실행기에서 뒤가 이김)
            "--max-ticks=900", "--quiet"])  # --lineage → --no-lineage 없음
        rows = read_csv_rows(out / "summary.csv")
        self.assertEqual(sorted(set(r["cell"] for r in rows), key=analyze.natural_key), [
            "mutation.rate=0.02__resources.scale=1", "mutation.rate=0.02__resources.scale=1.6",
            "mutation.rate=0.1__resources.scale=1", "mutation.rate=0.1__resources.scale=1.6"])
        self.assertEqual(len(read_csv_rows(out / "cells.csv")), 4)
        self.assertEqual(len(read_csv_rows(out / "runs.csv")), 8)

    def test_failures_recorded(self) -> None:
        out = self.tmp / "fail"
        fake = FakeRunner(fail_seeds=(2,), timeout_seeds=(3,))
        with mock.patch.object(analyze.subprocess, "run", fake), quiet():
            code = analyze.main(["run", "--seeds", "1-3", "--out", str(out), "--godot", "g", "--no-plots"])
        self.assertEqual(code, 1)
        runs = {r["seed"]: r for r in read_csv_rows(out / "runs.csv")}
        self.assertEqual((runs["1"]["status"], runs["2"]["status"], runs["3"]["status"]), ("ok", "failed", "timeout"))
        self.assertEqual(runs["2"]["exit_code"], "2")
        self.assertIn("설정 오류", (out / "seed2" / "run.log").read_text(encoding="utf-8"))
        md = (out / "report.md").read_text(encoding="utf-8")
        self.assertIn("## 실패·시간 초과", md)
        self.assertIn("timeout", md)
        self.assertEqual(len(read_csv_rows(out / "summary.csv")), 1)

    def test_missing_godot(self) -> None:
        out = self.tmp / "nogodot"
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = analyze.main(["run", "--seeds", "1", "--out", str(out), "--godot", str(self.tmp / "없는-godot"),
                                 "--no-report"])
        self.assertEqual(code, 1)
        self.assertEqual(read_csv_rows(out / "runs.csv")[0]["status"], "error")
        self.assertIn("--godot", buf.getvalue())

    def test_bad_repo(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()) as err:
            code = analyze.main(["run", "--out", str(self.tmp / "x"), "--repo", str(self.tmp)])
        self.assertEqual(code, 2)
        self.assertIn("project.godot", err.getvalue())

    def test_out_is_file(self) -> None:
        """--out 이 파일이거나 파일 아래이면 추적 없이 '오류:' 와 종료 코드 2(1단계 검증 지적 — 예전엔 FileExistsError 와 1). 실행기는 띄우지 않음."""
        f = self.tmp / "a-file"
        f.write_text("x", encoding="utf-8")
        fake = FakeRunner()
        cmds = {"run": ["run", "--seeds", "1", "--no-report", "--godot", "/opt/godot"],
                "ablate": ["ablate", "--runs", str(self.tmp / "runs"), "--at-gen", "1", "--ticks", "10", "--set", "learn.freeze=true",
                           "--godot", "/opt/godot"],
                "gate-a": ["gate-a", "--variant", "A-1", "--seeds", "1", "--godot", "/opt/godot"],
                "baldwin": ["baldwin", str(self.tmp)]}
        for name, argv in cmds.items():
            for out in (f, f / "below"):
                with mock.patch.object(analyze.subprocess, "run", fake), contextlib.redirect_stderr(io.StringIO()) as err, quiet():
                    code = analyze.main(argv + ["--out", str(out)])
                self.assertEqual((code, err.getvalue().startswith("오류: --out ")), (2, True), f"{name} --out {out.name}: {err.getvalue()!r}")
        self.assertEqual(fake.calls, [])


# ── 손 사본(DESIGN-v0.2 14.1 범위 7) ──

SIM_RECORDER = REPO / "scripts" / "sim" / "sim_recorder.gd"
SIM_WORLD = REPO / "scripts" / "sim" / "sim_world.gd"
SIM_BRAIN = REPO / "scripts" / "sim" / "sim_brain.gd"
INFO_PANEL = REPO / "scripts" / "ui" / "info_panel.gd"


def gd_list(path: Path, name: str) -> list[str]:
    """`const 이름: Array[String] = [...]` 의 글자들(적힌 순서)."""
    m = re.search(rf"const {name}: Array\[String\] = \[(.*?)\]", path.read_text(encoding="utf-8"), re.S)
    if not m:
        raise AssertionError(f"{path.name} 에 const {name} 목록이 없음")
    return re.findall(r'"([^"]*)"', m.group(1))


def gd_int(path: Path, name: str) -> int:
    """`const 이름 := 정수`."""
    m = re.search(rf"^const {name} := (-?\d+)$", path.read_text(encoding="utf-8"), re.M)
    if not m:
        raise AssertionError(f"{path.name} 에 const {name} 정수가 없음")
    return int(m.group(1))


class TestHandCopies(unittest.TestCase):
    """analyze.py 가 시뮬레이션 상수를 옮겨 적은 목록 = 원본(sim_recorder.gd·sim_world.gd·sim_brain.gd·info_panel.gd).
    단계마다 열이 늘면 analyze.py 도 함께 고쳐야 한다(고치지 않으면 여기서 실패 — 예전엔 견주는 곳이 없어 v0.2 열이 붙어도 몰랐음)."""

    def test_timeseries_columns(self) -> None:
        self.assertEqual(analyze.TIMESERIES_COLUMNS, gd_list(SIM_RECORDER, "TIMESERIES_COLUMNS"),
                         "analyze.TIMESERIES_COLUMNS ≠ SimRecorder.TIMESERIES_COLUMNS")

    def test_other_recorder_columns(self) -> None:
        for name in ("ACT_COLUMNS", "EFF_COLUMNS", "LINEAGE_COLUMNS", "CHRONICLE_COLUMNS"):
            self.assertEqual(getattr(analyze, name), gd_list(SIM_RECORDER, name), f"analyze.{name} ≠ SimRecorder.{name}")

    def test_stage_names(self) -> None:
        names = gd_list(SIM_WORLD, "STAGE_NAMES")
        self.assertEqual(analyze.STAGE_NAMES_KO, names, "analyze.STAGE_NAMES_KO ≠ SimWorld.STAGE_NAMES")
        self.assertEqual(len(analyze.STAGE_NAMES_EN), len(names))
        want = [(gd_int(SIM_WORLD, f"STAGE_{k.upper()}"), k, names[gd_int(SIM_WORLD, f"STAGE_{k.upper()}")])
                for k in ("forage", "store", "farm")]
        self.assertEqual(analyze.STAGES, want, "analyze.STAGES ≠ SimWorld.STAGE_FORAGE·STORE·FARM 과 STAGE_NAMES")

    def test_actions(self) -> None:
        self.assertEqual(analyze.ACTION_NAMES_KO, gd_list(SIM_BRAIN, "ACTION_NAMES"))
        # 행동 열의 순서 = SimBrain.ACT_* 번호
        for i, col in enumerate(analyze.ACT_COLUMNS):
            self.assertEqual(gd_int(SIM_BRAIN, "ACT_" + col[4:].upper()), i, col)
        # 문명 행동이 열리는 단계: 줍기·심기 = InfoPanel.ACTION_STAGE(SimWorld._act 의 단계 문), 내려놓기 = 채집(운반이 생기는 단계)
        text = INFO_PANEL.read_text(encoding="utf-8")
        stage_of = {m.group(1).lower(): gd_int(SIM_WORLD, "STAGE_" + m.group(2))
                    for m in re.finditer(r"SimBrain\.ACT_(\w+): SimWorld\.STAGE_(\w+)", text)}
        self.assertEqual(sorted(stage_of), ["gather", "plant"])
        got = dict(analyze.CIV_ACTIONS)
        self.assertEqual({k: got[k] for k in stage_of}, stage_of, "analyze.CIV_ACTIONS ≠ InfoPanel.ACTION_STAGE")
        self.assertEqual(got["drop"], gd_int(SIM_WORLD, "STAGE_FORAGE"))
        self.assertTrue(all("act_" + k in analyze.ACT_COLUMNS for k in got))


# ── 행동 셈·먹은 양·관문 A-1 미리 보기(DESIGN-v0.2 14.1 범위 7·10) ──

def acts(gather=(0, 0), drop=(0, 0), plant=(0, 0), total=0) -> dict:
    """시계열 한 줄의 행동 셈: 문명 행동 셋의 (고름, 효과), 나머지는 모든 행동 합이 total 이 되도록 쉬기(쉬기는 늘 효과)."""
    v = {c: 0 for c in analyze.ACT_COLUMNS + analyze.EFF_COLUMNS}
    for key, (a, e) in (("gather", gather), ("drop", drop), ("plant", plant)):
        v["act_" + key], v["eff_" + key] = a, e
    v["act_rest"] = v["eff_rest"] = total - gather[0] - drop[0] - plant[0] if total else 0
    return v


## 손으로 정한 시계열(틱 → 평균 세대·문명 단계·행동 셈). 구간 시작 = 앞 줄이므로
##  - 세대 표: 틱 60 줄(시작 세대 8·채집) → 0~10, 틱 80·100 줄(시작 세대 12·16) → 10~20. 심기는 시작 단계가 농사인 틱 100 줄만.
##  - 틱 표: 행동이 있는 모든 줄(틱 20~100)이 0~200.
HAND_ROWS = {
    0: {"mean_gen": 0, "civ_stage": 0, **acts()},
    20: {"mean_gen": 4, "civ_stage": 0, **acts((10, 0), (5, 0), (5, 0), 100)},
    40: {"mean_gen": 8, "civ_stage": 1, **acts((20, 8), (10, 5), (5, 0), 100)},
    60: {"mean_gen": 12, "civ_stage": 1, **acts((30, 15), (10, 10), (10, 0), 100)},
    80: {"mean_gen": 16, "civ_stage": 3, **acts((10, 5), (10, 5), (20, 10), 100)},
    100: {"mean_gen": 18, "civ_stage": 3, **acts((0, 0), (0, 0), (40, 30), 100)},
}


def hand_ts() -> pd.DataFrame:
    rows = []
    for tick, v in HAND_ROWS.items():
        r = {c: 0 for c in analyze.TIMESERIES_COLUMNS}
        r.update({"tick": tick, "population": 100, **v})
        rows.append(r)
    return pd.DataFrame(rows, columns=analyze.TIMESERIES_COLUMNS)


class TestActions(TempDirCase):
    def test_bins_by_generation_after_opening(self) -> None:
        got = {(b["bin_lo"], b["action"]): (b["rows"], b["act"], b["eff"], b["total"])
               for b in analyze.action_bins(hand_ts(), "gen")}
        self.assertEqual(got, {
            (0, "gather"): (1, 30, 15, 100), (10, "gather"): (2, 10, 5, 200),
            (0, "drop"): (1, 10, 10, 100), (10, "drop"): (2, 10, 5, 200),
            (10, "plant"): (1, 40, 30, 100),
        })

    def test_bins_by_tick(self) -> None:
        got = {(b["bin_lo"], b["bin_hi"], b["action"]): (b["rows"], b["act"], b["eff"], b["total"])
               for b in analyze.action_bins(hand_ts(), "tick")}
        self.assertEqual(got, {(0, 200, "gather"): (5, 70, 28, 500), (0, 200, "drop"): (5, 35, 20, 500),
                               (0, 200, "plant"): (5, 80, 40, 500)})

    def _run(self, name: str, **kw) -> Path:
        root = self.tmp / name
        write_fake_run(root / "x" / "seed1", 1, {"채집": (30, 6.0)}, civ=3, ticks=100,
                       rows_fn=lambda tick: HAND_ROWS[tick], **kw)
        return root

    def test_report_table(self) -> None:
        """보고서의 세대·틱 구간 표 = 손 계산(고름 % · 효과 %, 실행 1개), actions.csv 를 씀."""
        root = self._run("acts")
        with quiet():
            self.assertEqual(analyze.report(root, root, plots=False), 0)
        md = (root / "report.md").read_text(encoding="utf-8")
        self.assertIn("| `x` | 0–10 | 30.00 · 15.00 (1) | 10.00 · 10.00 (1) | — |", md)
        self.assertIn("| `x` | 10–20 | 5.00 · 2.50 (1) | 5.00 · 2.50 (1) | 40.00 · 30.00 (1) |", md)
        self.assertIn("| `x` | 0–200 | 14.00 · 5.60 (1) | 7.00 · 4.00 (1) | 16.00 · 8.00 (1) |", md)
        rows = read_csv_rows(root / "actions.csv")
        self.assertEqual(list(rows[0]), analyze.ACTION_COLUMNS)
        self.assertEqual(len(rows), 5 + 3)
        r = [x for x in rows if x["basis"] == "gen" and x["action"] == "plant"][0]
        self.assertEqual((r["bin_lo"], r["act"], r["eff"], r["success"]), ("10", "40", "30", "0.75"))

    def test_trend_pairs_same_run(self) -> None:
        """같은 실행의 첫 구간 → 끝 구간 방향 수(묶음 중앙값은 구간마다 씨앗 묶음이 달라 방향을 말하지 못함 — 검증 지적).
        씨앗 1 = HAND_ROWS(줍기 고름 30 → 5%·효과 15 → 2.5%·성공률 0.5 → 0.5, 내려놓기 10 → 5·10 → 2.5·1 → 0.5, 심기는 구간 하나),
        씨앗 2 = 줍기만 다른 줄(앞 구간 2%·효과 1 → 뒤 구간 8%·효과 6 — 오름)."""
        root = self.tmp / "trend"
        write_fake_run(root / "x" / "seed1", 1, {"채집": (30, 6.0)}, civ=3, ticks=100, rows_fn=lambda tick: HAND_ROWS[tick])
        up_rows = {tick: dict(v) for tick, v in HAND_ROWS.items()}
        up_rows[60].update(acts((2, 1), (10, 10), (10, 0), 100))
        up_rows[80].update(acts((8, 6), (10, 5), (20, 10), 100))
        up_rows[100].update(acts((8, 6), (0, 0), (40, 30), 100))
        write_fake_run(root / "x" / "seed2", 2, {"채집": (30, 6.0)}, civ=3, ticks=100, rows_fn=lambda tick: up_rows[tick])
        with quiet():
            self.assertEqual(analyze.report(root, root, plots=False), 0)
        acts_df = analyze.action_table(*analyze.build_summary(root), root)
        tr = analyze.action_trend(acts_df, ["x"])
        got = {(r.action, r.measure): (r.runs, r.down, r.up, r.same) for r in tr.itertuples()}
        self.assertEqual(got[("gather", "act_share")], (2, 1, 1, 0))
        self.assertEqual(got[("gather", "eff_share")], (2, 1, 1, 0))
        self.assertEqual(got[("gather", "success")], (2, 0, 1, 1))
        self.assertEqual(got[("drop", "act_share")], (2, 2, 0, 0))
        self.assertEqual(got[("drop", "success")], (2, 2, 0, 0))
        self.assertEqual(got[("plant", "act_share")], (0, 0, 0, 0), "구간이 하나뿐인 실행은 견주지 않음")
        md = (root / "report.md").read_text(encoding="utf-8")
        self.assertIn("### 같은 실행의 첫 구간 → 끝 구간", md)
        self.assertIn("| `x` | 줍기 | 1 · 1 (2) | 1 · 1 (2) | 0 · 1 (2) |", md)
        self.assertIn("| `x` | 내려놓기 | 2 · 0 (2) | 2 · 0 (2) | 2 · 0 (2) |", md)
        self.assertNotIn("| `x` | 심기 |", md)

    def test_summary_columns_come_first(self) -> None:
        """열 목록은 summary.json 의 timeseries_columns 가 먼저(손 사본·CSV 머리보다): v0.1 22열이라 적힌 실행은 행동 셈을 읽지 않음."""
        root = self._run("v01cols", summary_extra={"timeseries_columns": analyze.TIMESERIES_COLUMNS[:22]})
        with quiet():
            analyze.report(root, root, plots=False)
        self.assertFalse((root / "actions.csv").exists(),
                         "summary.json 의 timeseries_columns(v0.1 22열)를 CSV 머리보다 먼저 봐야 함 — 행동 셈을 읽어 actions.csv 를 씀")
        root = self._run("v02cols", summary_extra={"timeseries_columns": analyze.TIMESERIES_COLUMNS})
        with quiet():
            analyze.report(root, root, plots=False)
        self.assertTrue((root / "actions.csv").exists())

    def test_v01_results_still_read(self) -> None:
        """행동 셈 열이 없는 예전 결과(22열)도 보고서가 나오고, 행동 비율 절은 없다고만 적음."""
        root = self.tmp / "old"
        write_fake_run(root / "seed1", 1, {"채집": (100, 1.5)}, civ=1, columns=analyze.TIMESERIES_COLUMNS[:22])
        with quiet():
            self.assertEqual(analyze.report(root, root, plots=False), 0)
        md = (root / "report.md").read_text(encoding="utf-8")
        self.assertIn("행동 셈 열(`act_*`·`eff_*`)이 있는 실행이 없습니다", md)
        self.assertFalse((root / "actions.csv").exists())
        self.assertEqual(read_csv_rows(root / "summary.csv")[0]["window_births"], "NaN")


def lineage_rows(window: int, extra_dead: list[tuple[int, float]]) -> list[dict]:
    """처음 개체 2(부모 없음) + 틱 [200, 600) 출생 window 개 + 그 밖 출생 2(199·600). extra_dead = (세대, 먹은 양) 죽은 개체."""
    rows = [{"id": 0, "parent_a": -1, "parent_b": -1, "gen": 0, "birth_tick": -5, "death_tick": 300, "eaten": 10.0},
            {"id": 1, "parent_a": -1, "parent_b": -1, "gen": 0, "birth_tick": 0, "death_tick": -1, "eaten": 4.0}]
    for k, tick in enumerate([199, 600] + [200 + (399 * i) // max(window - 1, 1) for i in range(window)]):
        rows.append({"id": len(rows), "parent_a": 0, "parent_b": 1, "gen": 1, "birth_tick": tick, "death_tick": -1,
                     "eaten": 2.0})
    for gen, e in extra_dead:
        rows.append({"id": len(rows), "parent_a": 0, "parent_b": 0, "gen": gen, "birth_tick": 700, "death_tick": 800,
                     "eaten": e})
    return rows


class TestLineageReport(TempDirCase):
    def test_eaten_and_gate_preview(self) -> None:
        """lineage.csv 의 eaten → 개체 세대 구간별 먹은 양, 틱 [200, 600) 출생 → window_births·관문 A-1 판정 가능성."""
        root = self.tmp / "lin"
        # 씨앗 1: 1,200틱 살고 대상 출생 30 → 판정 가능. 씨앗 2: 500틱 멸종. 씨앗 3: 살았지만 대상 출생 3.
        write_fake_run(root / "seed1", 1, {}, civ=0, ticks=1200, lineage=lineage_rows(30, [(12, 6.0), (15, 8.0)]))
        write_fake_run(root / "seed2", 2, {}, civ=0, ticks=500, end_reason="extinction", extinct_tick=500,
                       lineage=lineage_rows(31, []))
        write_fake_run(root / "seed3", 3, {}, civ=0, ticks=1200, lineage=lineage_rows(3, []))
        with quiet():
            self.assertEqual(analyze.report(root, root, plots=False), 0)
        rows = read_csv_rows(root / "summary.csv")
        self.assertEqual([r["window_births"] for r in rows], ["30", "31", "3"])
        self.assertEqual([analyze.gate_a_status(r) for _, r in analyze.build_summary(root)[0].iterrows()],
                         ["ok", "extinct", "few"])
        eaten = read_csv_rows(root / "eaten.csv")
        self.assertEqual([(r["seed"], r["gen_lo"], r["dead"], r["eaten_median"]) for r in eaten],
                         [("1", "0", "1", "10"), ("1", "10", "2", "7"), ("2", "0", "1", "10"), ("3", "0", "1", "10")])
        md = (root / "report.md").read_text(encoding="utf-8")
        self.assertIn("## 평생 먹은 양(죽은 개체)", md)
        self.assertIn("| `default` | 10–20 | 7.0 (1 · 2) |", md)
        self.assertIn("| `default` | 3 | 33% (1/3) | 33% (1/3) | 500–500 | 30 [3–31] |", md)

    def test_unknown_eaten_left_out(self) -> None:
        """eaten 칸이 빈 개체(개체별 셈이 없던 옛 스냅숏에서 이어 돌린 실행의, 연 틱 전에 태어난 개체 — 평생 값을 모름)는
        eaten.csv 에서 빠진다(예전에는 0 으로 세어 앞 세대 구간의 중앙값이 0 이 됐을 것 — 검증 지적)."""
        root = self.tmp / "resumed"
        rows = lineage_rows(3, [(0, ""), (0, ""), (0, ""), (0, 9.0), (12, 6.0)])
        write_fake_run(root / "seed1", 1, {}, civ=0, ticks=1200, lineage=rows)
        with quiet():
            self.assertEqual(analyze.report(root, root, plots=False), 0)
        eaten = read_csv_rows(root / "eaten.csv")
        self.assertEqual([(r["gen_lo"], r["dead"], r["eaten_median"]) for r in eaten], [("0", "2", "9.5"), ("10", "1", "6")])

    def test_no_lineage_no_sections(self) -> None:
        root = self.tmp / "nolin"
        write_fake_run(root / "seed1", 1, {}, civ=0)
        with quiet():
            analyze.report(root, root, plots=False)
        md = (root / "report.md").read_text(encoding="utf-8")
        self.assertNotIn("## 평생 먹은 양", md)
        self.assertNotIn("## 관문 A-1", md)
        self.assertFalse((root / "eaten.csv").exists())


# ── 반사실 재생 ablate(가짜 subprocess — DESIGN-v0.2 11.4·14.1 범위 6) ──

class FakeAblateRunner:
    """subprocess.run 대신. 기준 실행(--seed): 400틱에 평균 세대에 닿은 결과(extinct_seeds 는 멸종).
    갈래(--resume): 스냅숏 폴더의 기준 summary.json 틱(F)부터 --max-ticks 까지 20틱마다 줄 — 바꾼 갈래(--fork-set)는
    줄마다 출생 3·줍기 20(효과 10), 그대로 갈래는 출생 2·줍기 10(효과 5), 모든 행동 100. lineage 의 대상 출생은 먹은 양 4(바꿈)·2."""

    def __init__(self, extinct_seeds: tuple = (), fail_fork_seeds: tuple = ()):
        self.calls: list[list[str]] = []
        self.lock = threading.Lock()
        self.extinct_seeds = extinct_seeds
        self.fail_fork_seeds = fail_fork_seeds

    def __call__(self, cmd, **kw):
        with self.lock:
            self.calls.append(list(cmd))
        argv = cmd[cmd.index("--") + 1:]
        args = dict(a[2:].split("=", 1) for a in argv if "=" in a and not a.startswith("--fork-set="))
        forks = {}
        for a in argv:
            if a.startswith("--fork-set="):
                k, _, v = a[len("--fork-set="):].partition("=")
                forks[k] = json.loads(v)
        out = Path(args["out"])
        reset = "--fork-reset-learned" in argv
        if "resume" not in args:
            seed = int(args["seed"])
            ext = seed in self.extinct_seeds
            write_fake_run(out, seed, {}, civ=0, ticks=400, preset=args["preset"],
                           generations_target=float(args["generations"]), max_ticks=CONFIG_MAX_TICKS,
                           end_reason="extinction" if ext else "generations", extinct_tick=380 if ext else -1)
            return subprocess.CompletedProcess(cmd, 0, f"RESULT: seed={seed} reason=generations\n", "")
        base = json.loads((Path(args["resume"]).parent / "summary.json").read_text(encoding="utf-8"))
        f, end, forked = int(base["tick"]), int(args["max-ticks"]), bool(forks) or reset
        if forked and int(base["seed"]) in self.fail_fork_seeds:
            # 실행기가 바꾼 설정으로 스냅숏을 열지 못함(배열 길이를 바꾸는 키) → 결과 폴더를 쓰지 않고 종료 코드 2
            return subprocess.CompletedProcess(cmd, 2, "", "Godot Engine v4.4.1.stable - https://godotengine.org\n\n"
                                               "ERROR: 엔진 줄\n   at: somewhere (x.cpp:1)\n"
                                               "--fork-set 으로 바꾼 설정으로 스냅숏을 열 수 없습니다: 유전체 길이가 맞지 않습니다\n")
        births, gather = (3, (20, 10)) if forked else (2, (10, 5))
        lin = [{"id": i, "parent_a": 0, "parent_b": 0, "gen": 1, "birth_tick": f + 5 * i, "death_tick": -1,
                "eaten": 4.0 if forked else 2.0, "children": 1} for i in range(4)]
        write_fake_run(out, int(base["seed"]), {}, civ=0, ticks=end, start_tick=f, generations_target=1e9,
                       max_ticks=end, end_reason="max_ticks", lineage=lin,
                       rows_fn=lambda tick: {"births": births if tick > f else 0,
                                             **(acts(gather, total=100) if tick > f else acts())},
                       summary_extra={"preset": "", "resumed_from": args["resume"], "forked": forks, "reset_learned": reset,
                                      "history_hash": ("ff" if forked else "ee") + "0" * 62})
        return subprocess.CompletedProcess(cmd, 0, "RESULT: reason=max_ticks\n", "")


class TestAblate(TempDirCase):
    def ablate(self, fake, *extra: str) -> int:
        with mock.patch.object(analyze.subprocess, "run", fake), quiet():
            return analyze.main(["ablate", "--runs", str(self.tmp / "base"), "--at-gen", "30", "--set", "learn_x.k=0",
                                 "--ticks", "100", "--seeds", "1-3", "--godot", "/opt/godot", "--out",
                                 str(self.tmp / "abl"), *extra])

    def test_commands_and_table(self) -> None:
        """① 기준 실행 = --generations G, ② 갈래 = 같은 스냅숏에서 --max-ticks F + N·세대 끝 조건 1e9, 바꾼 갈래에만 --fork-set,
        ③ 표 = 손 계산. 기준 실행이 멸종한 씨앗은 빼고 까닭을 적음."""
        fake = FakeAblateRunner(extinct_seeds=(3,))
        self.assertEqual(self.ablate(fake), 0)
        base = [c for c in fake.calls if any(a.startswith("--seed=") for a in c)]
        branch = [c for c in fake.calls if any(a.startswith("--resume=") for a in c)]
        self.assertEqual(len(base), 3)
        self.assertTrue(all("--generations=30" in c and "--preset=default" in c and "--no-lineage" in c for c in base))
        self.assertEqual(len(branch), 4, "갈래 = 견줄 수 있는 씨앗 2개 × 2(기준 실행이 그 세대 전에 멸종한 씨앗 3 은 뺌)")
        snap1 = self.tmp / "base" / "seed1" / "final.snapshot.json"
        same1 = [c for c in branch if f"--resume={snap1}" in c and not any(a.startswith("--fork-set=") for a in c)]
        fork1 = [c for c in branch if f"--resume={snap1}" in c and "--fork-set=learn_x.k=0" in c]
        self.assertEqual(len(same1), 1, "그대로 갈래(--fork-set 없음)의 명령이 씨앗마다 하나")
        self.assertEqual(len(fork1), 1, "바꾼 갈래(--fork-set)의 명령이 씨앗마다 하나")
        for c in same1 + fork1:
            self.assertIn("--max-ticks=500", c)
            self.assertIn("--generations=1000000000", c)
            self.assertNotIn("--no-lineage", c)
            self.assertFalse(any(a.startswith(("--seed=", "--preset=", "--set=")) for a in c), c)
        rows = read_csv_rows(self.tmp / "abl" / "ablate.csv")
        self.assertEqual(list(rows[0]), analyze.ABLATE_COLUMNS)
        got = {(r["seed"], r["metric"]): (r["same"], r["fork"], r["diff"]) for r in rows}
        self.assertEqual(sorted({s for s, _ in got}), ["1", "2"])
        # 창 (400, 500] 의 5줄: 출생 2·3 씩, 줍기 10·20 % (효과 5·10 %), 대상 출생(4명)의 평균 먹은 양 2·4
        self.assertEqual(got[("1", "births")], ("10", "15", "5"))
        self.assertEqual(got[("1", "act_gather")], ("10", "20", "10"))
        self.assertEqual(got[("2", "eff_gather")], ("5", "10", "5"))
        self.assertEqual(got[("2", "target_eaten")], ("2", "4", "2"))
        self.assertEqual(got[("1", "alive_ticks")], ("100", "100", "0"))
        md = (self.tmp / "abl" / "ablate.md").read_text(encoding="utf-8")
        self.assertIn("| 출생 | 2 | 10.00 | 15.00 | 5.00 [5.00–5.00] | 2 · 0 |", md)
        self.assertIn("| 3 | 기준 실행이 평균 30세대 전에 끝남(멸종, 틱 400) |", md)
        self.assertIn("| 1 | 400 | `ee0000000000` | `ff0000000000` |", md)

    def test_failed_branch_reason_has_runner_error(self) -> None:
        """바꾼 갈래가 실패하면 뺀 씨앗의 까닭에 종료 코드와 실행기의 오류 문장(run.log 의 마지막 오류 줄)이 붙음(검증 지적 —
        예전에는 'fork: 결과 없음' 뿐이라 run.log 를 열어야 했음)."""
        self.assertEqual(self.ablate(FakeAblateRunner(fail_fork_seeds=(2,))), 1)
        md = (self.tmp / "abl" / "ablate.md").read_text(encoding="utf-8")
        self.assertIn("| 2 | 갈래 실행 실패: fork: 결과 없음 (종료 코드 2 — --fork-set 으로 바꾼 설정으로 스냅숏을 열 수 없습니다: "
                      "유전체 길이가 맞지 않습니다) |", md)
        self.assertIn("| 1 | 400 |", md)

    def test_rerun_is_same_table_and_skips(self) -> None:
        """같은 명령을 다시 돌리면 실행 없이 같은 표(결정적). 바꾼 값이 다르면 그 갈래의 이전 결과를 덮어쓰지 않고 실패(mismatch)."""
        self.assertEqual(self.ablate(FakeAblateRunner()), 0)
        first = (self.tmp / "abl" / "ablate.md").read_bytes()
        again = FakeAblateRunner()
        self.assertEqual(self.ablate(again), 0)
        self.assertEqual(again.calls, [])
        self.assertEqual((self.tmp / "abl" / "ablate.md").read_bytes(), first)
        other = FakeAblateRunner()
        with mock.patch.object(analyze.subprocess, "run", other), quiet():
            code = analyze.main(["ablate", "--runs", str(self.tmp / "base"), "--at-gen", "30", "--set", "learn_x.k=1",
                                 "--ticks", "100", "--seeds", "1-3", "--godot", "g", "--out", str(self.tmp / "abl")])
        self.assertEqual(code, 1, "바꾼 값이 다른 이전 갈래 결과는 mismatch 로 실패(덮어쓰지도, 이번 결과로 세지도 않음)")
        self.assertEqual(other.calls, [])
        runs = read_csv_rows(self.tmp / "abl" / "runs.csv")
        self.assertEqual(sorted(r["status"] for r in runs if r["cell"] == analyze.ABLATE_FORK), ["mismatch"] * 3)

    def test_args(self) -> None:
        p = analyze.build_parser()
        a = p.parse_args(["ablate", "--runs", "r", "--at-gen", "30", "--set", "learn.freeze=true", "--ticks", "340",
                          "--set", "care.enabled=false", "--base-set", "brain.memory_units=2"])
        self.assertEqual((a.at_gen, a.ticks, a.set, a.base_set),
                         ("30", 340, [("learn.freeze", "true"), ("care.enabled", "false")], [("brain.memory_units", "2")]))
        self.assertIsNone(a.out)
        with quiet(), contextlib.redirect_stderr(io.StringIO()):
            for bad in (["--set", "a=1", "--ticks", "10"],
                        ["--at-gen", "0", "--set", "a=1", "--ticks", "10"], ["--at-gen", "3", "--set", "a=1", "--ticks", "0"],
                        ["--at-gen", "3", "--set", "a", "--ticks", "5"]):
                with self.assertRaises(SystemExit, msg=str(bad)):
                    p.parse_args(["ablate", "--runs", "r", *bad])

    def test_needs_set_or_reset(self) -> None:
        """--set 도 --reset-learned 도 없으면 바꾼 갈래가 그대로 갈래와 같아 견줄 것이 없음 → 실행하지 않고 종료 코드 2."""
        fake = FakeAblateRunner()
        err = io.StringIO()
        with mock.patch.object(analyze.subprocess, "run", fake), quiet(), contextlib.redirect_stderr(err):
            code = analyze.main(["ablate", "--runs", str(self.tmp / "base"), "--at-gen", "30", "--ticks", "100", "--seeds", "1",
                                 "--godot", "g", "--out", str(self.tmp / "abl")])
        self.assertEqual((code, fake.calls), (2, []))
        self.assertIn("--reset-learned", err.getvalue())

    def test_reset_learned_probe(self) -> None:
        """--reset-learned(이식 시험, DESIGN-v0.2 11.2): 바꾼 갈래에만 실행기 --fork-reset-learned(+ --set 의 --fork-set), 그대로 갈래에는 없음.
        ablate.json 에 조건(baldwin 이 읽음), 기본 폴더 이름에 reset_learned. 같은 폴더에 reset 없이 다시 돌리면 이전 갈래는 mismatch."""
        fake = FakeAblateRunner()
        with mock.patch.object(analyze.subprocess, "run", fake), quiet():
            code = analyze.main(["ablate", "--runs", str(self.tmp / "base"), "--preset", "learn_basic", "--at-gen", "30",
                                 "--reset-learned", "--set", "learn.freeze=true", "--ticks", "100", "--seeds", "1-2", "--godot", "g"])
        self.assertEqual(code, 0)
        out = self.tmp / "base-ablate" / "learn.freeze=true__reset_learned__g30__t100"
        branch = [c for c in fake.calls if any(a.startswith("--resume=") for a in c)]
        fork = [c for c in branch if "--fork-reset-learned" in c]
        same = [c for c in branch if "--fork-reset-learned" not in c]
        self.assertEqual((len(fork), len(same)), (2, 2), "씨앗마다 바꾼 갈래 하나에만 --fork-reset-learned")
        self.assertTrue(all("--fork-set=learn.freeze=true" in c for c in fork) and
                        not any(a.startswith("--fork-set=") for c in same for a in c))
        meta = json.loads((out / "ablate.json").read_text(encoding="utf-8"))
        self.assertEqual((meta["reset_learned"], meta["at_gen"], meta["ticks"], meta["set"], meta["preset"], meta["seeds"]),
                         (True, "30", 100, [["learn.freeze", "true"]], "learn_basic", [1, 2]))
        md = (out / "ablate.md").read_text(encoding="utf-8")
        self.assertIn("`--fork-reset-learned`", md)
        self.assertEqual(json.loads((out / "fork" / "seed1" / "summary.json").read_text(encoding="utf-8"))["reset_learned"], True)
        again = FakeAblateRunner()
        with mock.patch.object(analyze.subprocess, "run", again), quiet():
            code = analyze.main(["ablate", "--runs", str(self.tmp / "base"), "--preset", "learn_basic", "--at-gen", "30",
                                 "--set", "learn.freeze=true", "--ticks", "100", "--seeds", "1-2", "--godot", "g", "--out", str(out)])
        self.assertEqual((code, again.calls), (1, []), "reset 없이 같은 폴더 → 이전 바꾼 갈래(reset_learned true)는 mismatch")
        runs = read_csv_rows(out / "runs.csv")
        self.assertEqual(sorted(r["status"] for r in runs if r["cell"] == analyze.ABLATE_FORK), ["mismatch"] * 2)
        self.assertIn("reset_learned True ≠ False", [r for r in runs if r["cell"] == analyze.ABLATE_FORK][0]["result"])

    def test_default_out_is_beside_runs(self) -> None:
        """--out 을 주지 않으면 <runs>-ablate/<키=값>__g<세대>__t<틱> — 기준 실행 폴더 밖(report 가 갈래를 기준 실행과 섞지 않게)."""
        with mock.patch.object(analyze.subprocess, "run", FakeAblateRunner()), quiet():
            analyze.main(["ablate", "--runs", str(self.tmp / "base"), "--at-gen", "30", "--set", "learn_x.k=0",
                          "--ticks", "100", "--seeds", "1", "--godot", "g"])
        self.assertTrue((self.tmp / "base-ablate" / "learn_x.k=0__g30__t100" / "ablate.md").is_file(),
                        "기본 --out = <runs>-ablate/<키=값>__g<세대>__t<틱>")
        self.assertEqual(sorted(p.name for p in (self.tmp / "base").iterdir()), [".gdignore", "runs.csv", "seed1"])


# ── 관문 A 판정 gate-a(가짜 subprocess — DESIGN-v0.2 14.3) ──

## 가짜 결과의 설정(실행기가 summary.json 의 config 에 남기는 값 가운데 gate-a 가 읽는 것)
GATE_CONFIG = {"repro": {"maturity": 30}, "run": {"max_ticks": float(CONFIG_MAX_TICKS)}}


def gate_lineage(eaten: list[float], life: list[int], children: list[int], alive: int = 0, born: int = 300,
                 outside: tuple[int, int] = (199, 600)) -> list[dict]:
    """대상(틱 born 에 태어남 — 대상 구간 안) 개체마다 (먹은 양, 죽은 나이, 자식 수). 대상이 아닌 줄도 넣어 거르기를 본다: 처음 개체 2
    (부모 없음, 먹은 양 999), 틱 outside(구간 바로 앞·끝)에 태어난 개체(먹은 양 999·자식 9).
    alive = 끝까지 살아 있는(death_tick −1) 대상 수(앞에서부터)."""
    rows = [{"id": 0, "parent_a": -1, "parent_b": -1, "gen": 0, "birth_tick": 0, "death_tick": 400, "eaten": 999.0, "children": 9},
            {"id": 1, "parent_a": -1, "parent_b": -1, "gen": 0, "birth_tick": 0, "death_tick": 500, "eaten": 999.0, "children": 9}]
    for t in outside:
        rows.append({"id": len(rows), "parent_a": 0, "parent_b": 1, "gen": 1, "birth_tick": t, "death_tick": t + 1,
                     "eaten": 999.0, "children": 9})
    for k, (e, lf, c) in enumerate(zip(eaten, life, children)):
        rows.append({"id": len(rows), "parent_a": 0, "parent_b": 1, "gen": 1, "birth_tick": born,
                     "death_tick": -1 if k < alive else born + lf, "eaten": e, "children": c})
    return rows


def gate_spec(seed: int, branch: str) -> dict:
    """손으로 정한 관문 A 결과(씨앗 12개, 갈래마다 대상 30). 손 계산:
    먹은 양 — freeze 10, 학습 끔 11, 학습 12(씨앗 1~10)·8(11~12) → 학습 > freeze 10/12, 묶은 중앙값 12 ÷ 10 = 1.2.
    산 나이 — freeze·학습 끔 40 × 15 + 30 × 15(평균 35, 성숙까지 산 몫 15/30 — 딱 30 은 성숙 30 을 넘지 못함). 학습은 씨앗 1~8
    50 × 12 + 30 × 18(평균 38 > 35, 그러나 성숙 몫 12/30 < 0.5), 씨앗 9~11 31 × 20 + 30 × 10(평균 30.667 < 35, 그러나 성숙 몫 20/30 > 0.5),
    씨앗 12 는 freeze 와 같음 → 평균 산 나이 8/12, 성숙까지 산 몫 3/12(보고만). 묶은 평균 산 나이 12930/360 = 35.917, 성숙 몫 171/360.
    자식 수 — freeze·학습 끔 평균 0.5, 학습 1(씨앗 1~5)·0 → 5/12, 묶은 값 150/360.
    → ① 충족, ② 는 평균 산 나이(8/12)로만 충족(성숙 몫 3/12·자식 5/12) = 통과."""
    if branch == "learn":
        e = 12.0 if seed <= 10 else 8.0
        lf = [50] * 12 + [30] * 18 if seed <= 8 else ([31] * 20 + [30] * 10 if seed <= 11 else [40] * 15 + [30] * 15)
        c = [1] * 30 if seed <= 5 else [0] * 30
    else:
        e = 10.0 if branch == "freeze" else 11.0
        lf = [40] * 15 + [30] * 15
        c = [1] * 15 + [0] * 15
    return {"eaten": [e] * 30, "life": lf, "children": c}


def _fake_sets(argv: list[str], prefix: str) -> dict:
    """가짜 실행기: --set=·--fork-set= 값을 실행기처럼 읽음(JSON 이면 JSON, 아니면 글자)."""
    out = {}
    for a in argv:
        if a.startswith(prefix):
            k, _, v = a[len(prefix):].partition("=")
            out[k] = json.loads(v) if v[:1] not in "abcdefghijklmnopqrstuvwxyz" or v in ("true", "false") else v
    return out


class FakeGateRunner:
    """subprocess.run 대신(gate-a 의 실행기): --set 에서 갈래(learn.enabled·learn.freeze)를 알아내 spec(씨앗, 갈래)의 대상으로 결과 폴더를
    쓴다. spec 이 extinct(멸종 틱)·alive(살아 있는 대상 수)를 주면 그대로. 처음부터 --max-ticks 까지 산 결과가 기본."""

    def __init__(self, spec=gate_spec):
        self.calls: list[list[str]] = []
        self.lock = threading.Lock()
        self.spec = spec

    def __call__(self, cmd, **kw):
        with self.lock:
            self.calls.append(list(cmd))
        argv = cmd[cmd.index("--") + 1:]
        args = dict(a[2:].split("=", 1) for a in argv if "=" in a and not a.startswith("--set="))
        sets = _fake_sets(argv, "--set=")
        branch = "off" if not sets.get("learn.enabled") else ("freeze" if sets.get("learn.freeze") else "learn")
        seed, cap = int(args["seed"]), int(args["max-ticks"])
        sp = self.spec(seed, branch)
        ext = sp.get("extinct", -1)
        write_fake_run(Path(args["out"]), seed, {}, civ=0, ticks=ext if ext >= 0 else cap, preset=args["preset"],
                       overrides=sets, generations_target=float(args["generations"]), max_ticks=cap,
                       end_reason="extinction" if ext >= 0 else "max_ticks", extinct_tick=ext,
                       lineage=gate_lineage(sp["eaten"], sp["life"], sp["children"], sp.get("alive", 0)),
                       summary_extra={"config": GATE_CONFIG,
                                      "history_hash": f"{seed:02d}{'abc'.index(branch[0]) if branch[0] in 'abc' else 9}" + "0" * 61})
        return subprocess.CompletedProcess(cmd, 0, f"RESULT: seed={seed} reason=max_ticks\n", "")


## 갈래 표 손 계산(gate_spec — 학습·freeze·학습 끔)
GATE_HAND_ROWS = [
    "| 평생 먹은 양(중앙값) | ① | 12.00 | 10.00 | 11.00 | 2.00 | 1.00 | 0.200 | 10/12 | 10/12 |",
    "| 평균 산 나이(틱) | ② | 35.92 | 35.00 | 35.00 | 0.92 | 0.92 | 0.026 | 8/12 | 8/12 |",
    "| 평균 자식 수 | ② | 0.417 | 0.500 | 0.500 | -0.083 | -0.083 | -0.167 | 5/12 | 5/12 |",
    "| 성숙까지 산 몫 | 보고 | 0.475 | 0.500 | 0.500 | -0.025 | -0.025 | -0.050 | 3/12 | 3/12 |",
]


class TestGateA(TempDirCase):
    def gate(self, fake, variant: str = "A-1", seeds: str = "1-12", *extra: str) -> int:
        with mock.patch.object(analyze.subprocess, "run", fake), quiet():
            return analyze.main(["gate-a", "--variant", variant, "--seeds", seeds, "--godot", "/opt/godot",
                                 "--out", str(self.tmp / "ga"), *extra])

    def md(self) -> str:
        return (self.tmp / "ga" / "gate_a.md").read_text(encoding="utf-8")

    def test_commands(self) -> None:
        """갈래마다 같은 씨앗을 틱 0 부터: 예설정 chance_baseline + 학습·몸 자람, 학습(freeze 거짓)·freeze(참)·학습 끔(learn.enabled 거짓),
        --max-ticks = 변형의 끝(A-1 1,000 · A-1-life 1,500), 세대 끝 조건은 큰 값, lineage.csv 를 씀. A-1-life 는 A-1′ 세계(400·400·1.0)이고
        --variant 를 주지 않으면 이것(공식 A-1 — 사용자 결정 2026-10-11)."""
        fake = FakeGateRunner()
        self.assertEqual(self.gate(fake, "A-1", "1-2"), 0)
        self.assertEqual(len(fake.calls), 6)
        for c in fake.calls:
            self.assertIn("--preset=chance_baseline", c)
            self.assertIn("--max-ticks=1000", c)
            self.assertIn("--generations=1000000000", c)
            self.assertNotIn("--no-lineage", c)
            self.assertIn("--set=body.grow_enabled=true", c)
        sets = sorted(tuple(a for a in c if a.startswith("--set=learn.")) for c in fake.calls)
        self.assertEqual(sets, sorted([("--set=learn.enabled=true", "--set=learn.freeze=false")] * 2
                                      + [("--set=learn.enabled=true", "--set=learn.freeze=true")] * 2
                                      + [("--set=learn.enabled=false",)] * 2))
        life = FakeGateRunner()
        shutil.rmtree(self.tmp / "ga")
        with mock.patch.object(analyze.subprocess, "run", life), quiet():
            self.assertEqual(analyze.main(["gate-a", "--seeds", "3", "--godot", "g", "--out", str(self.tmp / "ga")]), 0)
        self.assertEqual(len(life.calls), 3)
        for c in life.calls:
            self.assertIn("--max-ticks=1500", c)
            for kv in ("population.initial=400", "population.cap=400", "plants.initial_fill=1.0"):
                self.assertIn("--set=" + kv, c)
        self.assertIn("# 관문 A 보고서 — 변형 `A-1-life`", self.md())
        self.assertIn("- 변형: 공식 A-1(사용자 결정 2026-10-11", self.md())
        aux = FakeGateRunner()
        shutil.rmtree(self.tmp / "ga")
        self.assertEqual(self.gate(aux, "A-1-life", "3", "--aux"), 0)
        with_none = [c for c in aux.calls if "--set=learn.diag_factor=none" in c]
        self.assertEqual(len(with_none), 2, "보조 판: 학습·freeze 갈래만 learn.diag_factor=none")
        self.assertIn("보조 판 — 판정에 쓰지 않음", self.md())

    def test_hand_computed_pass(self) -> None:
        """gate_spec 의 손 계산(세 행·두 차이·효과 크기·씨앗 수, 14.3 보고 꼴 — 지표 넷, 쓰임 ①·②·보고) → 통과. 대상이 아닌 개체
        (처음 개체·틱 199·600 출생)는 빠짐."""
        self.assertEqual(self.gate(FakeGateRunner(), "A-1-life"), 0)
        md = self.md()
        self.assertIn("- **판정: 통과**", md)
        for row in GATE_HAND_ROWS:
            self.assertIn(row, md)
        self.assertIn("학습 > freeze 씨앗 **10/12**(문턱 10), 묶은 중앙값 비 **1.200**(문턱 1.05) → 충족", md)
        self.assertIn("- ② 생존·번식: 평균 산 나이(틱) **8/12** · 평균 자식 수 **5/12**(둘 가운데 하나 ≥ 8) → 충족", md)
        self.assertIn("- 보고만(판정에 쓰지 않음): 성숙까지 산 몫 **3/12**", md)
        self.assertIn("| `GATE_A_WIN` | 10 |", md)
        self.assertIn("| `GATE_A_SECONDARY` | `life`, `children` |", md)
        self.assertIn("| 9 | 학습 | 조건 채움 | [200, 600) | 1,500 | 30 | 12.00 | 30.67 | 0.000 | 0.667 |", md)
        rows = read_csv_rows(self.tmp / "ga" / "gate_a.csv")
        self.assertEqual(list(rows[0]), analyze.GATE_A_COLUMNS)
        r = [x for x in rows if x["seed"] == "9" and x["branch"] == "learn"][0]
        self.assertEqual((r["status"], r["birth_lo"], r["birth_hi"], r["targets"], r["eaten_median"], r["life_mean"],
                          r["matured_share"], r["children_mean"]),
                         ("ok", "200", "600", "30", "12", "30.66666667", "0.6666666667", "0"))

    def test_secondary_uses_life(self) -> None:
        """② 의 생존 지표 = 평균 산 나이(사전 결정 2026-10-11 — 성숙까지 산 몫은 보고만). 두 방향으로 본다:
        손 계산(gate_spec)은 평균 산 나이 8/12 로만 ② 를 채움(성숙 몫 3/12) → 통과. 성숙 몫이 12/12 지만 평균 산 나이 0/12 인 결과 → 실패
        (② 에 성숙 몫을 세면 통과가 되어 이 검사가 실패함)."""
        self.assertEqual(analyze.GATE_A_SECONDARY, ("life", "children"))
        self.assertEqual(self.gate(FakeGateRunner(), "A-1-life"), 0)
        self.assertIn("- **판정: 통과**", self.md())
        shutil.rmtree(self.tmp / "ga")
        matured_only = lambda s, b: {**gate_spec(s, b), **({"life": [31] * 20 + [30] * 10} if b == "learn" else {})}
        self.assertEqual(self.gate(FakeGateRunner(matured_only), "A-1-life"), 0)
        md = self.md()
        self.assertIn("- ② 생존·번식: 평균 산 나이(틱) **0/12** · 평균 자식 수 **5/12**(둘 가운데 하나 ≥ 8) → 못 함", md)
        self.assertIn("- 보고만(판정에 쓰지 않음): 성숙까지 산 몫 **12/12**", md)
        self.assertIn("- **판정: 실패**", md)

    def test_thresholds(self) -> None:
        """문턱 경계: 먹은 양 씨앗 9/12 → 실패. 씨앗 10/12 지만 묶은 중앙값 비 1.04 → 실패. 평균 산 나이·자식 모두 7/12 이하 → 실패."""
        cases = {
            "wins9": lambda s, b: {**gate_spec(s, b), **({"eaten": [9.0] * 30} if b == "learn" and s == 10 else {})},
            "ratio": lambda s, b: {**gate_spec(s, b), **({"eaten": [10.4] * 30} if b == "learn" and s <= 10 else {})},
            "second": lambda s, b: {**gate_spec(s, b), **({"life": [40] * 15 + [30] * 15} if b == "learn" and s == 8 else {})},
        }
        want = {"wins9": "학습 > freeze 씨앗 **9/12**(문턱 10), 묶은 중앙값 비 **1.200**(문턱 1.05) → 못 함",
                "ratio": "학습 > freeze 씨앗 **10/12**(문턱 10), 묶은 중앙값 비 **1.040**(문턱 1.05) → 못 함",
                "second": "평균 산 나이(틱) **7/12** · 평균 자식 수 **5/12**(둘 가운데 하나 ≥ 8) → 못 함"}
        for name, spec in cases.items():
            shutil.rmtree(self.tmp / "ga", ignore_errors=True)
            self.assertEqual(self.gate(FakeGateRunner(spec), "A-1-life"), 0, name)
            md = self.md()
            self.assertIn("- **판정: 실패**", md, name)
            self.assertIn(want[name], md, name)

    def test_tied_metric(self) -> None:
        """판정 가능 씨앗 모두에서 학습 = freeze 인 지표(1단계 검증 — 기본값의 성숙까지 산 몫은 늘 1)는 '갈래를 가르지 못한 지표' 로 적음.
        성숙 몫은 보고만이라 판정에 닿지 않음(모두 성숙해도 평균 산 나이로 통과). 한 씨앗이라도 다르면 적지 않음."""
        self.assertEqual(self.gate(FakeGateRunner()), 0)
        self.assertNotIn("- **갈래를 가르지 못한 지표", self.md())
        shutil.rmtree(self.tmp / "ga")
        all_mature = lambda s, b: {**gate_spec(s, b), "life": [v + 40 for v in gate_spec(s, b)["life"]]}
        self.assertEqual(self.gate(FakeGateRunner(all_mature)), 0)
        md = self.md()
        self.assertIn("- **갈래를 가르지 못한 지표: 성숙까지 산 몫** — 판정 가능 씨앗 12개 모두에서 학습 = freeze(값 1.000). "
                      "같은 값은 이긴 씨앗으로 세지 않으므로 보고만 하는 지표라 판정에 닿지 않음", md)
        self.assertIn("- ② 생존·번식: 평균 산 나이(틱) **8/12** · 평균 자식 수 **5/12**(둘 가운데 하나 ≥ 8) → 충족", md)
        self.assertIn("- **판정: 통과**", md)
        self.assertNotIn("- **갈래를 가르지 못한 지표: 평균", md)
        shutil.rmtree(self.tmp / "ga")
        same_life = lambda s, b: {**gate_spec(s, b), "life": [31] * 30}
        self.assertEqual(self.gate(FakeGateRunner(same_life)), 0)
        md = self.md()
        self.assertIn("- **갈래를 가르지 못한 지표: 평균 산 나이(틱)** — 판정 가능 씨앗 12개 모두에서 학습 = freeze(값 31.00). "
                      "같은 값은 이긴 씨앗으로 세지 않으므로 ② 는 평균 자식 수로만 갈림", md)
        self.assertIn("평균 산 나이(틱) **0/12** · 평균 자식 수 **5/12**(둘 가운데 하나 ≥ 8) → 못 함", md)
        self.assertNotIn("- **갈래를 가르지 못한 지표: 평균 자식 수", md)
        shutil.rmtree(self.tmp / "ga")
        one_differs = lambda s, b: {**gate_spec(s, b), "life": [31] * 30 if (s, b) != (7, "freeze") else [31] * 29 + [30]}
        self.assertEqual(self.gate(FakeGateRunner(one_differs)), 0)
        self.assertNotIn("- **갈래를 가르지 못한 지표", self.md())

    def test_unjudgeable_and_variants(self) -> None:
        """A-1(처음 정의): 한 갈래라도 1,000틱 전에 멸종하거나 대상 < 30 이면 그 씨앗 판정 불가 → 판정 불가(A-1′·공식 조건 안내).
        A-1-life(공식)는 생존 요구가 없어 같은 멸종 씨앗도 판정하지만 끝에 살아 있는 대상이 있으면 판정 불가. 씨앗 수 ≠ 12 이면 판정 안 함.
        학습 끔 갈래는 판정 조건이 아니고, 조건을 못 채우면 셋째 행에서만 빠짐."""
        def spec(s, b):
            sp = gate_spec(s, b)
            if s == 3 and b == "freeze":
                sp["extinct"] = 900
            if s == 4 and b == "learn":
                sp = {k: v[:29] for k, v in sp.items()}
            if s == 5 and b == "off":
                sp["extinct"] = 100
            return sp
        self.assertEqual(self.gate(FakeGateRunner(spec)), 0)
        md = self.md()
        self.assertIn("- **판정: 판정 불가 — 씨앗 2개(3, 4)가 조건을 채우지 못함(처음 정의 — 14.3 은 이때 A-1′ 를 같은 문턱으로 돌림. "
                      "공식 조건은 A-1-life)**", md)
        self.assertIn("| 3 | freeze: 생존 틱 전 멸종(900틱 멸종) |", md)
        self.assertIn("| 4 | 학습: 대상 모자람(대상 29) |", md)
        self.assertIn("| 5 | 학습 끔 | 생존 틱 전 멸종 | [200, 600) | 100 멸종 |", md)
        self.assertIn("## 학습 끔 행이 없는 판정 가능 씨앗", md)
        self.assertIn("| 5 | 생존 틱 전 멸종(100틱 멸종) |", md)
        self.assertIn("(학습 끔 행은 그 갈래도 조건을 채운 9개)", md)
        shutil.rmtree(self.tmp / "ga")

        def spec_life(s, b):
            sp = spec(s, b)
            if s == 6 and b == "learn":
                sp["alive"] = 2
            return sp
        self.assertEqual(self.gate(FakeGateRunner(spec_life), "A-1-life"), 0)
        md = self.md()
        self.assertIn("- **판정: 판정 불가 — 씨앗 2개(4, 6)가 조건을 채우지 못함**", md)
        self.assertIn("| 6 | 학습: 끝에 대상이 살아 있음(대상 2명이 끝에 살아 있음) |", md)
        self.assertNotIn("| 3 | freeze:", md)
        shutil.rmtree(self.tmp / "ga")
        self.assertEqual(self.gate(FakeGateRunner(), "A-1-life", "1-11"), 0)
        self.assertIn("- **판정: 판정 안 함 — 씨앗 11개(문턱은 씨앗 12개 기준, 14.3)**", self.md())

    def test_rerun_reuses_and_same_report(self) -> None:
        """같은 명령을 다시 돌리면 실행 없이 같은 보고서. 실패한 실행(결과 없음)이 있으면 그 씨앗은 판정 불가·종료 코드 1."""
        self.assertEqual(self.gate(FakeGateRunner(), "A-1-life", "1-2"), 0)
        first = self.md()
        again = FakeGateRunner()
        self.assertEqual(self.gate(again, "A-1-life", "1-2"), 0)
        self.assertEqual((again.calls, self.md()), ([], first))
        shutil.rmtree(self.tmp / "ga")

        def failing(cmd, **kw):
            if "--seed=2" in cmd and "--set=learn.freeze=true" in cmd:
                return subprocess.CompletedProcess(cmd, 2, "", "설정 오류: 시험\n")
            return FakeGateRunner()(cmd, **kw)
        self.assertEqual(self.gate(failing, "A-1-life", "1-2"), 1)
        self.assertIn("| 2 | freeze: 실행 실패(결과 없음 (종료 코드 2 — 설정 오류: 시험)) |", self.md())

    def test_variant_names(self) -> None:
        """변형 이름은 정해진 셋(처음 정의 A-1 · 공식 A-1-life · A-2), --variant 기본 = 공식(GATE_A_OFFICIAL), 문턱은 14.3 표의 값."""
        self.assertEqual(list(analyze.GATE_A_VARIANTS), ["A-1", "A-1-life", "A-2"])
        self.assertEqual(analyze.GATE_A_OFFICIAL, "A-1-life")
        self.assertEqual(analyze.build_parser().parse_args(["gate-a", "--out", "x"]).variant, "A-1-life")
        self.assertEqual((analyze.GATE_A_WIN, analyze.GATE_A_RATIO, analyze.GATE_A_SECONDARY_WIN, analyze.GATE_A_MIN_BIRTHS,
                          analyze.GATE_A_SEEDS, analyze.GATE_A_BIRTH_WINDOW, analyze.GATE_A_TICKS, analyze.GATE_A_LIFE_MAX_TICKS,
                          analyze.GATE_A_SECONDARY),
                         (10, 1.05, 8, 30, 12, (200, 600), 1000, 1500, ("life", "children")))
        self.assertEqual((analyze.GATE_A2_PRESET, analyze.GATE_A2_AT_GEN, analyze.GATE_A2_TICKS, analyze.GATE_A2_WINDOW),
                         ("learn_basic", "30", 340, 100))
        self.assertEqual([analyze.GATE_A_VARIANTS[v]["ratio"] for v in analyze.GATE_A_VARIANTS], [True, True, False])
        with quiet(), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                analyze.build_parser().parse_args(["gate-a", "--variant", "A-3", "--out", "x"])

    def test_prereg_stamp(self) -> None:
        """보고서 머리의 사전 고정 줄: --prereg 값을 prereg_text 에 넘겨 그대로 적음, 주지 않으면 '주지 않음'. 판정 문턱은 바꾸지 않음."""
        self.assertEqual(self.gate(FakeGateRunner(), "A-1-life", "1-2"), 0)
        self.assertIn("- 사전 고정: 주지 않음(`--prereg 커밋`", self.md())
        shutil.rmtree(self.tmp / "ga")
        with mock.patch.object(analyze, "prereg_text", side_effect=lambda c: f"받은 값 {c}"):
            self.assertEqual(self.gate(FakeGateRunner(), "A-1-life", "1-2", "--prereg", "1234abc"), 0)
        self.assertIn("- 사전 고정: 받은 값 1234abc\n", self.md())

    @unittest.skipUnless(shutil.which("git"), "git 없음")
    def test_prereg_text_with_git(self) -> None:
        """prereg_text: 사전 고정 커밋의 파일과 지금 파일이 같으면 '같음', 고치면 '다름', 없는 커밋·저장소 밖은 '확인 못 함'."""
        repo = self.tmp / "repo"
        tool = repo / "tools" / "x.py"
        tool.parent.mkdir(parents=True)
        tool.write_text("A = 1\n", encoding="utf-8")
        env = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}
        git = lambda *a: subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", *a],
                                        cwd=str(repo), capture_output=True, text=True, env=env, check=True)
        git("init", "-q")
        git("add", "-A")
        git("commit", "-q", "-m", "v0.2 관문 A(1): 시험 고정")
        h = git("rev-parse", "HEAD").stdout.strip()
        self.assertEqual(analyze.prereg_text(h[:7], tool),
                         f"커밋 `{h[:12]}`(v0.2 관문 A(1): 시험 고정) — 지금 도는 `tools/x.py` 가 그 커밋의 것과 같음")
        tool.write_text("A = 2\n", encoding="utf-8")
        self.assertIn("가 그 커밋의 것과 **다름**(사전 고정 뒤 판정 코드가 바뀜", analyze.prereg_text(h, tool))
        self.assertIn("확인 못 함(저장소에 그런 커밋이 없음)", analyze.prereg_text("0" * 40, tool))
        outside = self.tmp / "plain" / "y.py"
        outside.parent.mkdir()
        outside.write_text("", encoding="utf-8")
        with mock.patch.dict(os.environ, {"GIT_CEILING_DIRECTORIES": str(self.tmp)}):
            self.assertIn("확인 못 함(git 저장소 밖", analyze.prereg_text(h, outside))
        self.assertTrue(analyze.prereg_text("", tool).startswith("주지 않음"))


# ── 관문 A-2(gate-a --variant A-2 — 가짜 subprocess, DESIGN-v0.2 14.3) ──

class FakeGateA2Runner:
    """gate-a --variant A-2 의 실행기 흉내. 기준 실행(--preset=learn_basic --generations=30): 틱 F = 1000 + 10 × 씨앗에 평균 세대 도달
    (base_extinct 씨앗은 900틱에 멸종). 갈래(--resume): 스냅숏 폴더의 기준 summary.json 틱 F 부터 --max-ticks 까지 살고, 대상(틱 F + 50
    출생)은 gate_spec(씨앗, 갈래 — --fork-set=learn.freeze=true 면 freeze, 없으면 learn), 대상 구간 밖 출생(F − 1·F + 100)도 넣음.
    우연 기준(--preset=chance_baseline): chance_ok 씨앗은 --max-ticks 까지 살고 대상(틱 F + 50 출생, F = --max-ticks − 340) 먹은 양 5·
    산 나이 33·자식 0, 나머지는 600틱에 멸종(대상 없음)."""

    def __init__(self, base_extinct: tuple = (), chance_ok: tuple = (1, 2)):
        self.calls: list[list[str]] = []
        self.lock = threading.Lock()
        self.base_extinct = base_extinct
        self.chance_ok = chance_ok

    def __call__(self, cmd, **kw):
        with self.lock:
            self.calls.append(list(cmd))
        argv = cmd[cmd.index("--") + 1:]
        args = dict(a[2:].split("=", 1) for a in argv if "=" in a and not a.startswith(("--set=", "--fork-set=")))
        out = Path(args["out"])
        extra = {"config": GATE_CONFIG}
        if "resume" in args:
            base = json.loads((Path(args["resume"]).parent / "summary.json").read_text(encoding="utf-8"))
            seed, f, end = int(base["seed"]), int(base["tick"]), int(args["max-ticks"])
            forks = _fake_sets(argv, "--fork-set=")
            sp = gate_spec(seed, "freeze" if forks.get("learn.freeze") else "learn")
            write_fake_run(out, seed, {}, civ=0, ticks=end, start_tick=f, generations_target=1e9, max_ticks=end,
                           end_reason="max_ticks", lineage=gate_lineage(sp["eaten"], sp["life"], sp["children"], born=f + 50,
                                                                         outside=(f - 1, f + 100)),
                           summary_extra={**extra, "preset": "", "resumed_from": args["resume"], "forked": forks,
                                          "reset_learned": False,
                                          "history_hash": f"{seed:02d}{'f' if forks else 'e'}" + "0" * 61})
            return subprocess.CompletedProcess(cmd, 0, "RESULT: reason=max_ticks\n", "")
        seed = int(args["seed"])
        if args["preset"] == "learn_basic":
            ext = seed in self.base_extinct
            write_fake_run(out, seed, {}, civ=0, ticks=900 if ext else 1000 + 10 * seed, preset="learn_basic",
                           generations_target=float(args["generations"]), max_ticks=CONFIG_MAX_TICKS,
                           end_reason="extinction" if ext else "generations", extinct_tick=900 if ext else -1,
                           summary_extra={**extra, "history_hash": f"{seed:02d}b" + "0" * 61})
            return subprocess.CompletedProcess(cmd, 0, f"RESULT: seed={seed} reason=generations\n", "")
        end = int(args["max-ticks"])
        f = end - 340
        ok = seed in self.chance_ok
        lin = gate_lineage([5.0] * 30, [33] * 30, [0] * 30, born=f + 50, outside=(f - 1, f + 100)) if ok else gate_lineage([], [], [])
        write_fake_run(out, seed, {}, civ=0, ticks=end if ok else 600, preset=args["preset"], overrides=_fake_sets(argv, "--set="),
                       generations_target=float(args["generations"]), max_ticks=end,
                       end_reason="max_ticks" if ok else "extinction", extinct_tick=-1 if ok else 600, lineage=lin,
                       summary_extra={**extra, "history_hash": f"{seed:02d}c" + "0" * 61})
        return subprocess.CompletedProcess(cmd, 0, f"RESULT: seed={seed} reason=max_ticks\n", "")


class TestGateA2(TempDirCase):
    def gate(self, fake, seeds: str = "1-12", *extra: str) -> int:
        with mock.patch.object(analyze.subprocess, "run", fake), quiet():
            return analyze.main(["gate-a", "--variant", "A-2", "--seeds", seeds, "--godot", "/opt/godot",
                                 "--out", str(self.tmp / "ga2"), *extra])

    def md(self) -> str:
        return (self.tmp / "ga2" / "gate_a.md").read_text(encoding="utf-8")

    def test_commands(self) -> None:
        """① 기준 실행 = learn_basic 평균 30세대(lineage 없음, 틱 상한은 설정값) → ② 같은 스냅숏에서 학습(--fork-set 없음)·freeze
        (--fork-set=learn.freeze=true)를 --max-ticks F + 340·세대 끝 조건 1e9·lineage 로, 우연 기준은 같은 씨앗을 틱 0 부터
        chance_baseline + 학습·몸 자람으로 --max-ticks F + 340 까지."""
        fake = FakeGateA2Runner()
        self.assertEqual(self.gate(fake, "1-2"), 0)
        self.assertEqual(len(fake.calls), 8)
        base = [c for c in fake.calls if "--preset=learn_basic" in c]
        self.assertEqual(len(base), 2)
        for c in base:
            self.assertIn("--generations=30", c)
            self.assertIn("--no-lineage", c)
            self.assertFalse(any(a.startswith(("--max-ticks=", "--set=")) for a in c), c)
        snap1 = self.tmp / "ga2" / "base" / "seed1" / "final.snapshot.json"
        fork1 = [c for c in fake.calls if f"--resume={snap1}" in c]
        self.assertEqual(len(fork1), 2)
        self.assertEqual(sorted(tuple(a for a in c if a.startswith("--fork-set=")) for c in fork1),
                         [(), ("--fork-set=learn.freeze=true",)])
        for c in fork1:
            self.assertIn("--max-ticks=1350", c)
            self.assertIn("--generations=1000000000", c)
            self.assertNotIn("--no-lineage", c)
            self.assertFalse(any(a.startswith(("--seed=", "--preset=", "--set=")) for a in c), c)
        chance1 = [c for c in fake.calls if "--preset=chance_baseline" in c and "--seed=1" in c]
        self.assertEqual(len(chance1), 1)
        for a in ("--max-ticks=1350", "--generations=1000000000", "--set=learn.enabled=true", "--set=body.grow_enabled=true"):
            self.assertIn(a, chance1[0])
        self.assertNotIn("--no-lineage", chance1[0])
        self.assertFalse(any(a.startswith("--resume=") for a in chance1[0]))

    def test_hand_computed(self) -> None:
        """A-2 의 손 계산: 학습·freeze 는 gate_spec(대상 [F, F + 100) — F − 1·F + 100 출생은 빠짐), 우연 기준은 씨앗 1·2 만 F + 340 까지
        삶(나머지 600틱 멸종 → 그 씨앗의 기준 행 없음). ① 은 비 문턱 없이 10/12(비는 보고), ② 평균 산 나이 8/12 → 통과."""
        self.assertEqual(self.gate(FakeGateA2Runner()), 0)
        md = self.md()
        self.assertIn("# 관문 A 보고서 — 변형 `A-2`", md)
        self.assertIn("- **판정: 통과**", md)
        self.assertIn("학습 > freeze 씨앗 **10/12**(문턱 10), 묶은 중앙값 비 **1.200**(A-2 는 보고 — 문턱 없음) → 충족", md)
        self.assertIn("- ② 생존·번식: 평균 산 나이(틱) **8/12** · 평균 자식 수 **5/12**(둘 가운데 하나 ≥ 8) → 충족", md)
        self.assertIn("(우연 기준 행은 그 갈래도 조건을 채운 2개)", md)
        for row in ("| 평생 먹은 양(중앙값) | ① | 12.00 | 10.00 | 5.00 | 2.00 | 7.00 | 0.200 | 10/12 | 2/2 |",
                    "| 평균 산 나이(틱) | ② | 35.92 | 35.00 | 33.00 | 0.92 | 2.92 | 0.026 | 8/12 | 2/2 |",
                    "| 평균 자식 수 | ② | 0.417 | 0.500 | 0.000 | -0.083 | 0.417 | -0.167 | 5/12 | 2/2 |",
                    "| 성숙까지 산 몫 | 보고 | 0.475 | 0.500 | 1.000 | -0.025 | -0.525 | -0.050 | 3/12 | 0/2 |"):
            self.assertIn(row, md)
        self.assertIn("| 학습 − freeze | 학습 − 우연 기준 |", md)
        self.assertIn("## 우연 기준 행이 없는 판정 가능 씨앗", md)
        self.assertIn("| 3 | 생존 틱 전 멸종(600틱 멸종) |", md)
        self.assertIn("| 1 | 학습(그대로) | 조건 채움 | [1010, 1110) | 1,350 | 30 | 12.00 | 38.00 | 1.000 | 0.400 |", md)
        rows = read_csv_rows(self.tmp / "ga2" / "gate_a.csv")
        self.assertEqual(list(rows[0]), analyze.GATE_A_COLUMNS)
        r = [x for x in rows if x["seed"] == "12" and x["branch"] == "chance"][0]
        self.assertEqual((r["status"], r["birth_lo"], r["birth_hi"], r["extinct_tick"], r["targets"]),
                         ("extinct", "1120", "1220", "600", "0"))

    def test_base_ended_and_lenient(self) -> None:
        """기준 실행이 30세대 전에 끝난 씨앗(멸종)은 갈래를 돌리지 않고 판정 불가. A-2 는 남은 씨앗으로 문턱을 셈(판정 불가 씨앗은 높은
        씨앗으로 세지 않음 — 문턱 수는 씨앗 12개 기준 그대로). 같은 명령을 다시 돌리면 실행 없이 같은 보고서."""
        fake = FakeGateA2Runner(base_extinct=(11, 12))
        self.assertEqual(self.gate(fake), 0)
        self.assertEqual(len(fake.calls), 12 + 10 * 3)
        md = self.md()
        self.assertIn("- **판정: 통과(판정 가능 씨앗 10/12 — 판정 불가 씨앗 2개(11, 12)는 높은 씨앗으로 세지 않음)**", md)
        self.assertIn("| 11 | 기준 실행이 평균 30세대 전에 끝남(멸종, 틱 900) |", md)
        self.assertIn("| 11 | 학습(그대로) | 기준 실행 없음(갈래 안 돌림) | — | — | — |", md)
        self.assertIn("학습 > freeze 씨앗 **10/10**(문턱 10)", md)
        first = md
        again = FakeGateA2Runner(base_extinct=(11, 12))
        self.assertEqual(self.gate(again), 0)
        self.assertEqual((again.calls, self.md()), ([], first))
        shutil.rmtree(self.tmp / "ga2")
        self.assertEqual(self.gate(FakeGateA2Runner(base_extinct=tuple(range(1, 13)))), 0)
        self.assertIn("- **판정: 판정 불가 — 씨앗 12개(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)가 조건을 채우지 못함**", self.md())

    def test_aux_rejected(self) -> None:
        """--aux(보조 판)는 A-1 계열만 — A-2 와 함께면 실행하지 않고 종료 코드 2."""
        fake = FakeGateA2Runner()
        err = io.StringIO()
        with mock.patch.object(analyze.subprocess, "run", fake), quiet(), contextlib.redirect_stderr(err):
            code = analyze.main(["gate-a", "--variant", "A-2", "--aux", "--godot", "g", "--out", str(self.tmp / "ga2")])
        self.assertEqual((code, fake.calls), (2, []))
        self.assertIn("--aux", err.getvalue())


# ── 관문 A 재판정의 씨앗 규율(gate_a_seed_guard — 사용자 결정 2026-10-11, DESIGN-v0.2 14.3 '재판정(씨앗 13~24)') ──

class GitOrFake:
    """subprocess.run 대신: git 명령은 진짜로(씨앗 규율의 git 확인), 그 밖(실행기)은 가짜 실행기로."""

    def __init__(self, fake) -> None:
        self.fake = fake
        self.real = subprocess.run

    def __call__(self, cmd, **kw):
        return self.real(cmd, **kw) if cmd[0] == "git" else self.fake(cmd, **kw)


class TestGateASeedRule(TempDirCase):
    def gate(self, fake, seeds: str, *extra: str, variant: str = "A-1-life", repo: Path | None = None) -> tuple[int, str]:
        err = io.StringIO()
        with mock.patch.object(analyze.subprocess, "run", fake), quiet(), contextlib.redirect_stderr(err):
            code = analyze.main(["gate-a", "--variant", variant, "--seeds", seeds, "--godot", "/opt/godot",
                                 "--out", str(self.tmp / "ga"), "--repo", str(repo or REPO), *extra])
        return code, err.getvalue()

    def make_repo(self) -> tuple[Path, callable]:
        """임시 git 저장소: 실행을 정하는 경로(GATE_A_FROZEN_PATHS)마다 파일 하나 + 지금 도는 analyze.py 의 사본 + 문서·무시 파일."""
        repo = self.tmp / "repo"
        files = {"project.godot": "[application]\n", "config/sim-defaults.json": '{"learn": {"eta_init": 0.8}}\n',
                 "scripts/sim/sim_world.gd": "class_name SimWorld\n", "tests/run_experiment.gd": "extends SceneTree\n",
                 "docs/note.md": "문서\n", ".gitignore": ".godot/\n", ".gitattributes": "* text=auto eol=lf\n"}
        for rel, text in files.items():
            (repo / rel).parent.mkdir(parents=True, exist_ok=True)
            (repo / rel).write_text(text, encoding="utf-8")
        (repo / "tools").mkdir()
        shutil.copyfile(Path(analyze.__file__), repo / analyze.GATE_A_TOOL_PATH)
        env = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}
        git = lambda *a: subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", *a],
                                        cwd=str(repo), capture_output=True, text=True, env=env, check=True)
        git("init", "-q")
        git("add", "-A")
        git("commit", "-q", "-m", "v0.2 관문 A 재조정(3): 시험 고정")
        return repo, git

    def test_seed_constants(self) -> None:
        """재판정 씨앗 = 13~24(문턱의 기준 씨앗 수 12개), 예비 = 25~36. 조정용 1~12 와 겹치지 않음. 실행을 정하는 경로에 설정·스크립트·
        실행기·판정 도구가 들어 있음."""
        self.assertEqual(analyze.GATE_A_REJUDGE_SEEDS, tuple(range(13, 25)))
        self.assertEqual(analyze.GATE_A_RESERVE_SEEDS, tuple(range(25, 37)))
        self.assertEqual(len(analyze.GATE_A_REJUDGE_SEEDS), analyze.GATE_A_SEEDS)
        tune = set(range(1, analyze.GATE_A_SEEDS + 1))
        self.assertFalse(tune & set(analyze.GATE_A_REJUDGE_SEEDS) or tune & set(analyze.GATE_A_RESERVE_SEEDS)
                         or set(analyze.GATE_A_REJUDGE_SEEDS) & set(analyze.GATE_A_RESERVE_SEEDS))
        self.assertEqual(analyze.GATE_A_FROZEN_PATHS,
                         ("project.godot", "config", "scripts", "tests/run_experiment.gd", "tools/analyze.py"))
        self.assertEqual(Path(analyze.__file__).resolve(), (REPO / analyze.GATE_A_TOOL_PATH).resolve())
        self.assertEqual(analyze.build_parser().parse_args(["gate-a", "--out", "x"]).seeds, list(range(1, 13)),
                         "--seeds 기본은 조정용 1~12 그대로(재판정 씨앗을 기본으로 두지 않음)")

    def test_refused_before_running(self) -> None:
        """예비 씨앗(하나라도 — 다른 씨앗과 섞여도), 재판정 씨앗의 일부·다른 씨앗과 섞음·--prereg 없음은 아무것도 돌리지 않고 결과 폴더도
        만들지 않고 종료 코드 2(A-1-life·A-2·--aux 모두). 그 밖의 씨앗(1~12·101 이상)은 거르지 않음."""
        cases = [("25-36", "", "예비 씨앗(25~36)"), ("1,30", "", "씨앗 30 은 예비 씨앗(25~36)"),
                 ("13", "", "재판정 씨앗(13~24)은 12개를 함께, 다른 씨앗 없이만 돌립니다(`--seeds 13-24` — 받은 씨앗 13)"),
                 ("12-24", "", "받은 씨앗 12~24"), ("13-23", "", "받은 씨앗 13~23"), ("13-25", "", "예비 씨앗"),
                 ("13-24", "", "재판정 씨앗(13~24)은 `--prereg 사전 고정 커밋` 을 주고만 돌립니다")]
        for variant in ("A-1-life", "A-2"):
            for seeds, prereg, want in cases:
                fake = FakeGateRunner() if variant != "A-2" else FakeGateA2Runner()
                extra = ("--prereg", prereg) if prereg else ()
                code, err = self.gate(fake, seeds, *extra, variant=variant)
                self.assertEqual((code, fake.calls), (2, []), (variant, seeds))
                self.assertIn("오류: 씨앗 규율 — ", err, (variant, seeds))
                self.assertIn(want, err, (variant, seeds))
                self.assertFalse((self.tmp / "ga").exists(), (variant, seeds))
        code, err = self.gate(FakeGateRunner(), "13-24", "--aux")
        self.assertEqual(code, 2)
        self.assertIn("--prereg 사전 고정 커밋", err)
        for seeds in ("1-12", "101", "3"):
            shutil.rmtree(self.tmp / "ga", ignore_errors=True)
            fake = FakeGateRunner()
            self.assertEqual(self.gate(fake, seeds)[0], 0, seeds)
            self.assertTrue(fake.calls, seeds)
            self.assertNotIn("- 씨앗 규율:", (self.tmp / "ga" / "gate_a.md").read_text(encoding="utf-8"), seeds)

    @unittest.skipUnless(shutil.which("git"), "git 없음")
    def test_frozen_files_with_git(self) -> None:
        """재판정 씨앗 13~24 + --prereg: 실행을 정하는 파일이 그 커밋과 같으면 돌리고 보고서 머리에 씨앗 규율 줄. 설정을 고치거나
        추적하지 않는 새 스크립트가 있거나 추적하는 스크립트를 지우면 아무것도 돌리지 않고 결과 폴더도 만들지 않고 종료 코드 2(다른 파일이
        많으면 앞의 GATE_A_FROZEN_LIST_MAX 개와 '외 N개'). 없는 커밋·다른 판정 도구도 거부.
        문서·무시하는 파일(.godot/)이 달라도 돌림."""
        repo, git = self.make_repo()
        h = git("rev-parse", "HEAD").stdout.strip()
        self.assertEqual(analyze.gate_a_frozen_diff(h, repo), "")
        self.assertEqual(analyze.gate_a_seed_guard(list(analyze.GATE_A_REJUDGE_SEEDS), h[:7], repo), "")
        (repo / "docs" / "note.md").write_text("판정 뒤 문서\n", encoding="utf-8")
        (repo / ".godot").mkdir()
        (repo / ".godot" / "cache.cfg").write_text("x\n", encoding="utf-8")
        shift = analyze.GATE_A_REJUDGE_SEEDS[0] - 1
        fake = FakeGateRunner(lambda s, b: gate_spec(s - shift, b))
        code, err = self.gate(GitOrFake(fake), "13-24", "--prereg", h[:7], repo=repo)
        self.assertEqual(code, 0, err)
        self.assertEqual(len(fake.calls), 36)
        md = (self.tmp / "ga" / "gate_a.md").read_text(encoding="utf-8")
        self.assertIn("- 씨앗 규율: 재판정 씨앗(13~24) — 실행 전 확인(`gate_a_seed_guard`): 씨앗 모두를 함께, `--prereg` 커밋과 "
                      "실행을 정하는 파일(`project.godot`, `config`, `scripts`, `tests/run_experiment.gd`, `tools/analyze.py`)이 같음\n", md)
        self.assertIn("- **판정: 통과**", md, "씨앗 규율은 판정 계산을 바꾸지 않음(손 계산 gate_spec 을 씨앗 13~24 로 옮김)")
        for row in GATE_HAND_ROWS:
            self.assertIn(row, md)
        shutil.rmtree(self.tmp / "ga")
        cfg = repo / "config" / "sim-defaults.json"
        changes = [
            (lambda: cfg.write_text('{"learn": {"eta_init": 0.5}}\n', encoding="utf-8"), "다른 파일 1개: config/sim-defaults.json",
             lambda: git("checkout", "--", "config")),
            (lambda: (repo / "scripts" / "sim" / "sim_extra.gd").write_text("x\n", encoding="utf-8"),
             "다른 파일 1개: scripts/sim/sim_extra.gd", lambda: (repo / "scripts" / "sim" / "sim_extra.gd").unlink()),
            (lambda: (repo / "scripts" / "sim" / "sim_world.gd").unlink(), "다른 파일 1개: scripts/sim/sim_world.gd",
             lambda: git("checkout", "--", "scripts")),
        ]
        for change, want, undo in changes:
            change()
            fake = FakeGateRunner()
            code, err = self.gate(GitOrFake(fake), "13-24", "--prereg", h, repo=repo)
            self.assertEqual((code, fake.calls), (2, []), want)
            self.assertIn("사전 고정 커밋과 같을 때만 돌립니다", err)
            self.assertIn(want, err)
            self.assertFalse((self.tmp / "ga").exists())
            undo()
            self.assertEqual(analyze.gate_a_frozen_diff(h, repo), "", want)
        many = [repo / "scripts" / f"s{k}.gd" for k in range(analyze.GATE_A_FROZEN_LIST_MAX + 2)]
        for p in many:
            p.write_text("x\n", encoding="utf-8")
        self.assertEqual(analyze.gate_a_frozen_diff("HEAD", repo),
                         f"커밋 `HEAD` 과 다른 파일 {len(many)}개: "
                         + ", ".join(f"scripts/s{k}.gd" for k in range(analyze.GATE_A_FROZEN_LIST_MAX)) + " 외 2개")
        for p in many:
            p.unlink()
        self.assertIn("확인 못 함(저장소에 커밋", analyze.gate_a_frozen_diff("0" * 40, repo))
        self.assertIn("확인 못 함(저장소에 커밋", analyze.gate_a_seed_guard(list(analyze.GATE_A_REJUDGE_SEEDS), "0" * 40, repo))
        (repo / analyze.GATE_A_TOOL_PATH).write_text("# 다른 도구\n", encoding="utf-8")
        self.assertIn("저장소(--repo)의 `tools/analyze.py` 로만 돌립니다",
                      analyze.gate_a_seed_guard(list(analyze.GATE_A_REJUDGE_SEEDS), h, repo))

    @unittest.skipUnless(shutil.which("git"), "git 없음")
    def test_same_second_edit_is_caught(self) -> None:
        """인덱스를 믿지 않음: 커밋 바로 뒤(같은 초) 같은 크기로 고친 설정도 '다름'(prereg_text 와 같은 방식 — git hash-object)."""
        repo, git = self.make_repo()
        cfg = repo / "config" / "sim-defaults.json"
        before = cfg.read_bytes()
        git("status", "--short")
        cfg.write_bytes(before.replace(b"0.8", b"0.9"))
        self.assertEqual(len(cfg.read_bytes()), len(before))
        self.assertIn("config/sim-defaults.json", analyze.gate_a_frozen_diff("HEAD", repo))


# ── 볼드윈 보고서 baldwin(손으로 만든 결과 폴더 — DESIGN-v0.2 11.2) ──

## 실행마다 개체 세대 구간별 죽은 개체 값: (세대, 죽은 수, η, 배운 양, 어린 동안 배운 양, 동화 지수, 먹은 양, 자식 수)
BALDWIN_HAND = {
    1: [(5, 30, 0.05, 0.01, 0.005, 0.5, 10.0, 1), (15, 30, 0.04, 0.02, 0.01, 0.7, 20.0, 2), (25, 5, 0.09, 0.0, 0.0, 0.1, 1.0, 0)],
    2: [(5, 30, 0.05, 0.01, 0.005, 0.6, 12.0, 1), (15, 30, 0.03, 0.03, 0.01, 0.65, 22.0, 2)],
}


def baldwin_lineage(seed: int) -> list[dict]:
    rows = []
    for gen, n, eta, dw, juv, assim, eaten, ch in BALDWIN_HAND[seed]:
        for _ in range(n):
            rows.append({"id": len(rows), "parent_a": 0, "parent_b": 0, "gen": gen, "birth_tick": 10, "death_tick": 50,
                         "eta": eta, "dw": dw, "dw_juv": juv, "assim": assim, "eaten": eaten, "children": ch})
    # 살아 있는 개체(death_tick −1 — 평생 값이 아직 정해지지 않음)는 빠져야 함
    rows.append({"id": len(rows), "parent_a": 0, "parent_b": 0, "gen": 5, "birth_tick": 10, "death_tick": -1,
                 "eta": 9.0, "dw": 9.0, "dw_juv": 9.0, "assim": 0.0, "eaten": 999.0, "children": 9})
    return rows


def write_probe(d: Path, at_gen: str, values: dict[int, tuple[float, float]], reset: bool = True) -> None:
    """ablate 결과 흉내: ablate.json(조건) + ablate.csv(씨앗마다 대상 평균 먹은 양 (그대로, 바꿈) — 자식 수는 그대로 1 · 바꿈 0.5)."""
    d.mkdir(parents=True, exist_ok=True)
    (d / "ablate.json").write_text(json.dumps({"at_gen": at_gen, "ticks": 340, "reset_learned": reset,
                                               "set": [["learn.freeze", "true"]]}), encoding="utf-8")
    rows = []
    for seed, (same, fork) in values.items():
        rows.append({"seed": seed, "fork_tick": 1000, "metric": "target_eaten", "same": same, "fork": fork, "diff": fork - same})
        rows.append({"seed": seed, "fork_tick": 1000, "metric": "target_children", "same": 1.0, "fork": 0.5, "diff": -0.5})
    analyze.write_csv(pd.DataFrame(rows, columns=analyze.ABLATE_COLUMNS), d / "ablate.csv")


class TestBaldwin(TempDirCase):
    def setUp(self) -> None:
        super().setUp()
        self.root = self.tmp / "learn"
        feats = {"features": ["body.grow_enabled", "learn.enabled"]}
        for seed in (1, 2):
            write_fake_run(self.root / f"seed{seed}", seed, {}, civ=0, preset="learn_basic", lineage=baldwin_lineage(seed),
                           summary_extra=feats)
        # 학습을 끈 실행(features 에 learn.enabled 없음)은 빠지고 까닭이 적힘
        write_fake_run(self.root / "seed3", 3, {}, civ=0, preset="learn_basic", lineage=baldwin_lineage(1),
                       summary_extra={"features": ["body.grow_enabled"]})
        write_probe(self.tmp / "probe_g10", "10", {1: (8.0, 5.0), 2: (9.0, 6.0)})
        write_probe(self.tmp / "probe_g30", "30", {1: (8.0, 7.0), 2: (9.0, 8.0)})
        write_probe(self.tmp / "control_g30", "30", {1: (7.5, 0.0), 2: (7.0, 0.0)}, reset=False)
        write_probe(self.tmp / "not_reset", "20", {1: (1.0, 1.0)}, reset=False)
        (self.tmp / "empty").mkdir()

    def baldwin(self, *extra: str) -> tuple[int, str]:
        with quiet(), contextlib.redirect_stderr(io.StringIO()):
            code = analyze.main(["baldwin", str(self.root), *extra])
        md = (self.root / "baldwin.md").read_text(encoding="utf-8") if (self.root / "baldwin.md").exists() else ""
        return code, md

    def test_generation_trend(self) -> None:
        """세대 구간별(죽은 개체만) 값 = 손 계산, 실행끼리 중앙값. 첫 → 끝 방향은 죽은 개체 ≥ 30 인 구간만(세대 20–30 구간 5명은 뺌)."""
        code, md = self.baldwin()
        self.assertEqual(code, 0)
        self.assertIn("| `learn_basic` | 0–10 | 0.0500 | 0.550 | 0.0100 | 0.0050 | 11.0 | 2 · 60 |", md)
        self.assertIn("| `learn_basic` | 10–20 | 0.0350 | 0.675 | 0.0250 | 0.0100 | 21.0 | 2 · 60 |", md)
        self.assertIn("| `learn_basic` | 20–30 | 0.0900 | 0.100 | 0.0000 | 0.0000 | 1.0 | 1 · 5 |", md)
        self.assertIn("| η 평균 | 2 · 0 (2) |", md)
        self.assertIn("| 동화 지수 | 0 · 2 (2) |", md)
        self.assertIn("`seed3` — 학습을 켜지 않은 실행", md)
        rows = read_csv_rows(self.root / "baldwin.csv")
        self.assertEqual(list(rows[0]), analyze.BALDWIN_COLUMNS)
        r = [x for x in rows if x["seed"] == "1" and x["gen_lo"] == "10"][0]
        self.assertEqual((r["dead"], r["eta_mean"], r["assim_mean"], r["eaten_median"], r["children_mean"]), ("30", "0.04", "0.7", "20", "2"))
        self.assertIn("- **동화**(셋 모두): 판단할 자료 없음", md)
        self.assertIn("- 이식 시험의 타고난 능력이 오름: 자료 없음", md)

    def test_probe_and_control(self) -> None:
        """이식 시험(평균 세대 10·30): 배우는 대 타고난 — 타고난 능력이 오름(2/2 씨앗). η 내림·동화 지수 오름과 함께 동화 = 예.
        학습 끈 대조(30세대): 타고난 < 학습 끔 씨앗 1/2 → 감춤 아니오. 이식 시험이 아닌 폴더·ablate 결과가 아닌 폴더는 뺀 까닭."""
        code, md = self.baldwin("--probe", str(self.tmp / "probe_g30"), "--probe", str(self.tmp / "probe_g10"),
                                "--probe", str(self.tmp / "not_reset"), "--probe", str(self.tmp / "empty"),
                                "--control-probe", str(self.tmp / "control_g30"))
        self.assertEqual(code, 0)
        self.assertIn("| `probe_g10` | 10.0 | 340 | 대상 평균 먹은 양 | 2 | 8.50 | 5.50 | 3.00 | 2 |", md)
        self.assertIn("| `probe_g30` | 30.0 | 340 | 대상 평균 먹은 양 | 2 | 8.50 | 7.50 | 1.00 | 2 |", md)
        self.assertIn("| `probe_g10` | 10.0 | 340 | 대상 평균 자식 수 | 2 | 1.00 | 0.50 | 0.50 | 2 |", md)
        self.assertIn("| `not_reset` | 이식 시험이 아님(ablate.json 의 reset_learned 가 false) |", md)
        self.assertIn("| `empty` | ablate.json 를 읽을 수 없음(analyze.py ablate 의 결과 폴더가 아님) |", md)
        self.assertIn("| `control_g30` | 30.0 | 7.50 | 7.25 | 1/2 |  |", md)
        self.assertIn("- η 가 세대에 따라 줄어듦: 예(2/2 실행)", md)
        self.assertIn("- 동화 지수가 오름: 예(2/2 실행)", md)
        self.assertIn("- 이식 시험의 타고난 능력이 오름(평균 세대 10.0 → 30.0, 대상 평균 먹은 양): 예(2/2 씨앗)", md)
        self.assertIn("- **동화**(셋 모두): 예", md)
        self.assertIn("- **감춤**(가장 늦은 평균 세대에서 타고난 능력 < 학습 끔인 씨앗이 과반): 아니오(평균 세대 30.0, 1/2 씨앗)", md)
        # 타고난 능력이 내리면 동화가 아님, 학습 끔이 더 높으면 감춤
        write_probe(self.tmp / "probe_g30", "30", {1: (8.0, 4.0), 2: (9.0, 5.0)})
        code, md = self.baldwin("--probe", str(self.tmp / "probe_g10"), "--probe", str(self.tmp / "probe_g30"),
                                "--control-probe", str(self.tmp / "control_g30"))
        self.assertIn("- 이식 시험의 타고난 능력이 오름(평균 세대 10.0 → 30.0, 대상 평균 먹은 양): 아니오(0/2 씨앗)", md)
        self.assertIn("- **동화**(셋 모두): 아니오", md)
        self.assertIn("- **감춤**(가장 늦은 평균 세대에서 타고난 능력 < 학습 끔인 씨앗이 과반): 예(평균 세대 30.0, 2/2 씨앗)", md)

    def test_no_learning_runs(self) -> None:
        """학습을 켠 실행이 없으면 종료 코드 1(보고서는 쓰되 그렇다고)."""
        root = self.tmp / "off"
        write_fake_run(root / "seed1", 1, {}, civ=0, lineage=baldwin_lineage(1))
        with quiet(), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(analyze.main(["baldwin", str(root)]), 1)
        self.assertIn("학습을 켠 실행의 lineage.csv 가 없습니다", (root / "baldwin.md").read_text(encoding="utf-8"))


# ── 올린 예시 ──

class TestExamples(unittest.TestCase):
    def test_example_reports_match_doc_commands(self) -> None:
        """올린 예시 보고서(docs/analysis/example)는 ANALYSIS.md 의 명령 그대로 만든 것: 보고서의 결과 폴더 이름 = 명령의
        --out(예전에는 다른 폴더 이름으로 만들어 그대로 재현되지 않았음 — I82), 표는 지금 도구가 쓰는 BOM 붙은 CSV."""
        doc = (REPO / "docs" / "ANALYSIS.md").read_text(encoding="utf-8")
        sec = doc.split("\n## 예시", 1)[1].split("\n## ", 1)[0]
        for kind, n_runs in (("run", 8), ("sweep", 12)):
            m = re.search(rf"analyze\.py {kind}\s[^\n]*(?:\\\n[^\n]*)*?--out results/(\S+)", sec)
            self.assertIsNotNone(m, f"ANALYSIS.md 예시에 {kind} 명령이 없음")
            folder = REPO / "docs" / "analysis" / "example" / kind
            md = (folder / "report.md").read_text(encoding="utf-8")
            self.assertIn(f"- 결과 폴더: `{m.group(1)}` — 실행 **{n_runs}개**", md, kind)
            for name in ("summary.csv", "cells.csv"):
                self.assertEqual((folder / name).read_bytes()[:3], b"\xef\xbb\xbf", f"{kind}/{name}")
            self.assertEqual(len(read_csv_rows(folder / "summary.csv")), n_runs, kind)


# ── 실제 실행기(있을 때만) ──

def _godot() -> str | None:
    g = os.environ.get("GODOT") or shutil.which("godot")
    return g if g and (shutil.which(g) or os.path.isfile(g)) else None


@unittest.skipUnless(_godot(), "godot 없음(GODOT 환경 변수나 PATH) — 실제 실행 검사 건너뜀")
class TestRealRunner(TempDirCase):
    def test_tiny_batch_is_deterministic(self) -> None:
        """씨앗 2개 × 2세대를 실제로 돌리고, 같은 씨앗을 다시 돌려 역사 해시가 같은지 본다."""
        a, b = self.tmp / "a", self.tmp / "b"
        common = ["--generations", "2", "--preset", "fast_civ", "--godot", _godot(), "--timeout", "300", "--no-plots"]
        with quiet():
            self.assertEqual(analyze.main(["run", "--seeds", "1-2", "--out", str(a), "--jobs", "2"] + common), 0)
            self.assertEqual(analyze.main(["run", "--seeds", "1", "--out", str(b)] + common), 0)
        ra = read_csv_rows(a / "summary.csv")
        rb = read_csv_rows(b / "summary.csv")
        self.assertEqual([r["seed"] for r in ra], ["1", "2"])
        self.assertEqual(ra[0]["end_reason"], "generations")
        self.assertEqual(len(ra[0]["history_hash"]), 64)
        self.assertEqual(ra[0]["history_hash"], rb[0]["history_hash"])
        self.assertNotEqual(ra[0]["history_hash"], ra[1]["history_hash"])
        self.assertTrue(read_csv_rows(a / "runs.csv")[0]["result"].startswith("RESULT: seed=1 "))
        self.assertFalse((a / "seed1" / "lineage.csv").exists())  # 묶음 기본 = --no-lineage


if __name__ == "__main__":
    unittest.main()
