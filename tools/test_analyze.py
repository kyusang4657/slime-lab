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


# ── 가짜 실행 결과 ──

def write_fake_run(run_dir: Path, seed: int, disc: dict, *, civ: int, end_reason: str = "generations",
                   extinct_tick: int = -1, ticks: int = 400, final_gen: float = 8.0, preset: str = "default",
                   overrides: dict | None = None, odd_text: bool = False,
                   generations_target: float | None = None) -> None:
    """실행기 결과 폴더 흉내. disc = {"채집": (틱, 세대), ...} — 없는 단계는 발견 못 함."""
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
    (run_dir / "chronicle.csv").write_text("\n".join(lines) + "\n", encoding="utf-8")
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
    (run_dir / "timeseries.csv").write_text("\n".join(rows) + "\n", encoding="utf-8")


def make_fake_results(root: Path) -> None:
    """묶음 2개(a=1, a=2) × 씨앗 2개."""
    write_fake_run(root / "a=1" / "seed1", 1, {"채집": (100, 1.5), "저장": (200, 3.25), "농사": (400, 7.0)}, civ=3)
    write_fake_run(root / "a=1" / "seed2", 2, {"채집": (120, 2.5), "저장": (300, 5.75)}, civ=2)
    write_fake_run(root / "a=2" / "seed1", 1, {"채집": (150, 4.0)}, civ=1)
    write_fake_run(root / "a=2" / "seed2", 2, {}, civ=0, end_reason="extinction", extinct_tick=90, ticks=100)


def read_csv_rows(path: Path) -> list[dict]:
    with path.open(encoding="utf-8", newline="") as f:
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

    def test_natural_order(self) -> None:
        cells = ["rate=0.1", "rate=0.02", "rate=1.5", "rate=0.05"]
        self.assertEqual(sorted(cells, key=analyze.natural_key), ["rate=0.02", "rate=0.05", "rate=0.1", "rate=1.5"])
        self.assertEqual(sorted(["seed10", "seed2", "seed1"], key=analyze.natural_key), ["seed1", "seed2", "seed10"])


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
        write_fake_run(Path(args["out"]), seed, {"채집": (100, 1.0 + seed)}, civ=1, preset=args["preset"],
                       overrides=sets, generations_target=float(args["generations"]))
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
