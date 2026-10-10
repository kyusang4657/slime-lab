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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analyze  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
## config/sim-defaults.json 의 run.max_ticks 흉내(실행기가 summary.json 의 config 에 남기는 값)
CONFIG_MAX_TICKS = 2000000


# ── 가짜 실행 결과 ──

def write_fake_run(run_dir: Path, seed: int, disc: dict, *, civ: int, end_reason: str = "generations",
                   extinct_tick: int = -1, ticks: int = 400, final_gen: float = 8.0, preset: str = "default",
                   overrides: dict | None = None, odd_text: bool = False,
                   generations_target: float | None = None, max_ticks: int | None = None, bom: bool = False) -> None:
    """실행기 결과 폴더 흉내(summary.json·timeseries.csv·chronicle.csv·final.snapshot.json — 끝까지 쓴 결과).
    disc = {"채집": (틱, 세대), ...} — 없는 단계는 발견 못 함.
    max_ticks 를 주면 실행기처럼 실제로 쓴 틱 상한과 설정의 run.max_ticks(기본 CONFIG_MAX_TICKS)를 남긴다.
    bom 이면 CSV 를 BOM 붙은 UTF-8 로(실행기·실험실 CSV 의 새 형식)."""
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
    rows = [",".join(analyze.TIMESERIES_COLUMNS)]
    for tick in range(0, ticks + 1, 20):
        extinct_now = end_reason == "extinction" and tick >= extinct_tick
        pop = 0 if extinct_now else 100 + (tick // 20) % 7
        gen = 0.0 if extinct_now else final_gen * tick / ticks
        stage = max([0] + [i for i, n in enumerate(names) if n in disc and disc[n][0] <= tick])
        vals = {c: 0 for c in analyze.TIMESERIES_COLUMNS}
        vals.update({"tick": tick, "population": pop, "mean_gen": round(gen, 6),
                     "mean_size": 0.0 if extinct_now else round(1.0 - 0.001 * tick / 20, 6),
                     "mean_sense": 0.0 if extinct_now else 3.0, "civ_stage": stage})
        rows.append(",".join(str(vals[c]) for c in analyze.TIMESERIES_COLUMNS))
    (run_dir / "timeseries.csv").write_text("\n".join(rows) + "\n", encoding=csv_enc)
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
