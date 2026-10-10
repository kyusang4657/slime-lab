#!/usr/bin/env python3
"""헤드리스 실행기(tests/run_experiment.gd) 명령줄 검사(unittest) — 실제 godot 을 subprocess 로 부른다.

  python3 -m unittest discover -s tools -p "test_*.py" -v

godot 은 환경 변수 GODOT 또는 PATH 의 godot(tools/test_analyze.py 와 같은 규칙). 찾지 못하면 건너뛰지 않고 실패한다
(이 검사는 실행기의 명령줄 계약을 지키는 유일한 곳이고, GitHub Actions 에는 godot 이 있다). 처음 한 번
`godot --headless --path . --import` 가 되어 있어야 한다(CI 는 앞 단계에서 함).

지키는 계약(tests/run_experiment.gd 머리 주석·docs/ANALYSIS.md "헤드리스 실행기"):
- 인자: --max-ticks·--snapshot-every 는 정수와 범위(틱 상한 2^31−1), --generations 는 0 보다 큰 유한한 수, --seed 는 64비트.
  어기면 종료 코드 2(검토 I20·J01). INT64_MIN 씨앗도 RESULT 줄에 바르게(J31).
- --resume: --seed·--preset·--set 과 함께면 2. 이어 돌린 해시 = 끊김 없는 해시, summary.json 은 preset ""·overrides {}·
  resumed_from·resume_status(I05). 본 파일이 깨지면 경고하고 백업을 썼다고 적음(I06). 곧바로 끝나도 같은 틱 한 줄(I23).
- 결과 폴더: 앞 실행의 파일이 섞이지 않음, 모르는 파일이 있으면 2 로 거부하고 아무것도 지우지 않음(I21).
- 설정 오류(절 통째 덮어쓰기·범위 밖 값)는 2, 결과 폴더를 건드리지 않음(I02·I03). analyze.py --set 경로도 실행기 2 를 기록.
- 쓰기 실패는 3 이고 RESULT 줄 끝에 write_failed(중간 스냅숏 포함, J10·I17). 정상이면 RESULT 줄이 reason=… 으로 끝남.
"""
from __future__ import annotations

import contextlib
import csv
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analyze  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
RUNNER = "res://tests/run_experiment.gd"
## 실행기 하나의 시간 제한(초) — 여기 실행은 모두 수십~수백 틱이라 몇 초면 끝남
TIMEOUT = 300
## 동시에 띄우는 godot 수(인자 오류 검사)
PARALLEL = 4
## 틱을 담는 세계 배열(PackedInt32Array)의 상한 = 실행기 TICK_LIMIT
TICK_LIMIT = 2**31 - 1
## 개체 없이 시작 → 틱 0 에 멸종으로 끝남(인자가 잘못 받아들여졌을 때도 검사가 오래 걸리지 않게)
EMPTY = "--set=population.initial=0"


def godot_path() -> str | None:
    g = os.environ.get("GODOT") or shutil.which("godot")
    return g if g and (shutil.which(g) or os.path.isfile(g)) else None


def run_runner(*args: str, timeout: float = TIMEOUT) -> subprocess.CompletedProcess:
    """실행기를 명령줄 그대로 돌린다(출력은 UTF-8)."""
    g = godot_path()
    if g is None:
        raise AssertionError("godot 을 찾지 못했습니다 — 환경 변수 GODOT 이나 PATH 에 godot 4.4.1 을 두세요"
                             "(이 검사는 건너뛰지 않습니다)")
    cmd = [g, "--headless", "--path", str(REPO), "--script", RUNNER, "--", *args]
    return subprocess.run(cmd, capture_output=True, encoding="utf-8", errors="replace", timeout=timeout)


def result_line(cp: subprocess.CompletedProcess) -> str:
    lines = [ln for ln in cp.stdout.splitlines() if ln.startswith("RESULT:")]
    return lines[-1] if lines else ""


def summary(d: Path) -> dict:
    return json.loads((d / "summary.json").read_text(encoding="utf-8-sig"))


def data_rows(csv_path: Path) -> list[list[str]]:
    with csv_path.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.reader(f))[1:]


def listing(d: Path) -> dict[str, bytes]:
    return {p.name: p.read_bytes() for p in sorted(d.iterdir()) if p.is_file()}


class RunnerCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if godot_path() is None:
            raise AssertionError("godot 을 찾지 못했습니다 — 환경 변수 GODOT 이나 PATH 에 godot 4.4.1 을 두세요"
                                 "(실행기 명령줄 검사는 건너뛰지 않습니다)")
        cls.tmp = Path(tempfile.mkdtemp(prefix="slime-runner-"))

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def ok(self, cp: subprocess.CompletedProcess, code: int = 0) -> None:
        self.assertEqual(cp.returncode, code, f"종료 코드 {cp.returncode} ≠ {code}\n{cp.stdout[-2000:]}\n{cp.stderr[-2000:]}")


# ── 인자 ──

class TestArgs(RunnerCase):
    def test_bad_numbers_rejected(self) -> None:
        """to_int 로만 읽던 인자: 1e5 → 15틱, abc → 상한 없음, 2^31 → 틱 배열이 뒤집힘 — 모두 종료 코드 2 로 거부(I20·J01)."""
        cases = [
            "--max-ticks=1e5", "--max-ticks=10k", "--max-ticks=abc", "--max-ticks=-5", "--max-ticks=0",
            f"--max-ticks={TICK_LIMIT + 1}", "--max-ticks=99999999999999999999",
            "--snapshot-every=1e4", "--snapshot-every=abc", "--snapshot-every=-1", f"--snapshot-every={TICK_LIMIT + 1}",
            "--generations=-5", "--generations=0", "--generations=1_0", "--generations=1e400",
            "--seed=99999999999999999999", "--seed=-9223372036854775809",
        ]
        outs = {c: self.tmp / f"bad{i}" for i, c in enumerate(cases)}
        with ThreadPoolExecutor(PARALLEL) as pool:
            res = dict(zip(cases, pool.map(lambda c: run_runner(f"--out={outs[c]}", EMPTY, c, "--quiet"), cases)))
        wrong = [f"{c} → 종료 코드 {cp.returncode}" for c, cp in res.items() if cp.returncode != 2]
        self.assertEqual(wrong, [], "잘못된 수 인자를 받아들임")
        for c, cp in res.items():
            self.assertIn("인자 오류", cp.stderr, c)
            self.assertNotIn("Cannot represent", cp.stderr, c)  # 64비트를 넘는 글을 to_int 가 자르며 찍는 엔진 오류 없이
            self.assertFalse(outs[c].exists(), f"{c}: 인자 오류인데 결과 폴더를 만듦")

    def test_limits_accepted(self) -> None:
        """경계값은 받는다: --max-ticks 2^31−1, --snapshot-every 0(끔), 64비트 끝 씨앗."""
        out = self.tmp / "limits"
        cp = run_runner(f"--out={out}", EMPTY, f"--max-ticks={TICK_LIMIT}", "--snapshot-every=0",
                        "--seed=9223372036854775807", "--generations=1e3", "--quiet")
        self.ok(cp)
        s = summary(out)
        self.assertEqual((s["max_ticks"], s["seed"], s["generations_target"]), (TICK_LIMIT, 9223372036854775807, 1000))

    def test_int64_min_seed(self) -> None:
        """씨앗 INT64_MIN: '%d' 는 부호를 두 번 붙임(--9223…) — RESULT 줄은 str() 로(J31)."""
        out = self.tmp / "minseed"
        cp = run_runner(f"--out={out}", EMPTY, "--seed=-9223372036854775808", "--quiet")
        self.ok(cp)
        self.assertIn("RESULT: seed=-9223372036854775808 ", result_line(cp))
        self.assertNotIn("--9223", cp.stdout)
        self.assertEqual(summary(out)["seed"], -9223372036854775808)


# ── 이어 돌리기 ──

class TestResume(RunnerCase):
    """원본: fast_civ + mutation.rate 0.07, 씨앗 3, 70틱, 35틱마다 스냅숏(35·70 은 기록 간격 20 의 배수가 아님)."""

    @classmethod
    def setUpClass(cls) -> None:
        super().setUpClass()
        cls.orig = cls.tmp / "orig"
        cls.orig_cp = run_runner("--seed=3", "--preset=fast_civ", "--set=mutation.rate=0.07", "--max-ticks=70",
                                 "--snapshot-every=35", f"--out={cls.orig}", "--quiet")

    def setUp(self) -> None:
        self.ok(self.orig_cp)

    def test_resume_same_hash_and_summary(self) -> None:
        """--snapshot-every 의 중간 스냅숏에서 이어 돌리면 끊김 없이 돌린 것과 같은 해시. summary.json 은 스냅숏 쪽 값(I05)."""
        out = self.tmp / "resumed"
        snap = self.orig / "snapshot-35.json"
        self.assertTrue(snap.is_file() and (self.orig / "snapshot-70.json").is_file(), "중간 스냅숏")
        cp = run_runner(f"--resume={snap}", "--max-ticks=70", f"--out={out}", "--quiet")
        self.ok(cp)
        a, b = summary(self.orig), summary(out)
        self.assertEqual((b["tick"], b["history_hash"]), (a["tick"], a["history_hash"]), "이어 돌린 해시 = 끊김 없는 해시")
        # 예설정 이름은 스냅숏에 없으므로 ""(실험실에서 스냅숏을 연 실험과 같음), 쓰이지 않은 덮어쓰기를 적지 않음
        self.assertEqual((b["preset"], b["overrides"]), ("", {}))
        self.assertEqual((b["resumed_from"], b["resume_status"]), (str(snap), "loaded"))
        self.assertEqual((b["seed"], b["config"]["mutation"]["rate"]), (3, 0.07))
        self.assertEqual(b["config"], a["config"])
        self.assertEqual((a["resumed_from"], a["resume_status"], a["preset"]), ("", "", "fast_civ"))

    def test_resume_rejects_condition_args(self) -> None:
        """--resume 은 스냅숏의 설정·씨앗을 쓴다 → --seed·--preset·--set 을 함께 주면 무시하지 않고 인자 오류 2(I05)."""
        snap = self.orig / "snapshot-35.json"
        for extra in ("--seed=9", "--preset=default", "--set=mutation.rate=0.5"):
            out = self.tmp / ("rej" + extra.split("=")[0].strip("-"))
            cp = run_runner(f"--resume={snap}", extra, "--max-ticks=70", f"--out={out}", "--quiet")
            self.assertEqual(cp.returncode, 2, extra)
            self.assertIn("--resume", cp.stderr, extra)
            self.assertFalse(out.exists(), extra)

    def test_resume_from_backup_is_reported(self) -> None:
        """본 파일이 깨져 .bak 에서 읽으면 경고 줄을 찍고 summary.json 에 실제로 읽은 파일·resume_status=backup(I06)."""
        d = self.tmp / "bk"
        d.mkdir()
        shutil.copy(self.orig / "snapshot-35.json", d / "s.json.bak")
        (d / "s.json").write_text('{"format": "slime-lab-snapshot", 깨진', encoding="utf-8")
        out = self.tmp / "from_bak"
        cp = run_runner(f"--resume={d / 's.json'}", "--max-ticks=70", f"--out={out}", "--quiet")
        self.ok(cp)
        self.assertIn("경고", cp.stderr)
        self.assertIn("백업", cp.stderr)
        s = summary(out)
        self.assertEqual((s["resume_status"], s["resumed_from"]), ("backup", str(d / "s.json.bak")))
        self.assertEqual(s["history_hash"], summary(self.orig)["history_hash"])

    def test_resume_that_ends_at_once_writes_one_row(self) -> None:
        """이어 돌리자마자 끝나면(틱 상한 ≤ 지금 틱) 같은 틱 줄을 두 번(둘째는 출생·사망 0) 쓰지 않음 — 실험실과 같은 한 줄(I23)."""
        for cap in ("70", "50"):
            out = self.tmp / f"at_once{cap}"
            cp = run_runner(f"--resume={self.orig / 'final.snapshot.json'}", f"--max-ticks={cap}", f"--out={out}", "--quiet")
            self.ok(cp)
            rows = data_rows(out / "timeseries.csv")
            self.assertEqual([r[0] for r in rows], ["70"], f"--max-ticks={cap}: 시계열 줄 {[r[0] for r in rows]}")

    def test_resume_inside_out_dir_refused(self) -> None:
        """이어 돌릴 스냅숏이 결과 폴더 바로 안이면 거부(그 폴더를 비우며 지우게 됨) — 스냅숏은 그대로(I21)."""
        before = listing(self.orig)
        cp = run_runner(f"--resume={self.orig / 'snapshot-35.json'}", "--max-ticks=70", f"--out={self.orig}", "--quiet")
        self.assertEqual(cp.returncode, 2)
        self.assertIn("결과 폴더 안", cp.stderr)
        self.assertEqual(listing(self.orig), before)

    def test_missing_snapshot(self) -> None:
        cp = run_runner(f"--resume={self.tmp / '없는.json'}", f"--out={self.tmp / 'nosnap'}", "--quiet")
        self.assertEqual(cp.returncode, 2)


# ── 결과 폴더 ──

class TestOutDir(RunnerCase):
    def test_rerun_leaves_no_stale_files(self) -> None:
        """같은 --out 을 다시 쓰면 앞 실행의 lineage.csv·snapshot-N.json·final.snapshot.json.bak 이 남지 않음.
        .gdignore·analyze.py 의 run.log 는 그대로(I21)."""
        d = self.tmp / "again"
        self.ok(run_runner("--seed=7", "--max-ticks=40", "--snapshot-every=20", f"--out={d}", "--quiet"))
        self.assertTrue((d / "lineage.csv").is_file() and (d / "snapshot-40.json").is_file())
        (d / "run.log").write_text("analyze 기록", encoding="utf-8")
        self.ok(run_runner("--seed=9", "--max-ticks=20", "--no-lineage", f"--out={d}", "--quiet"))
        names = sorted(p.name for p in d.iterdir())
        self.assertEqual(names, [".gdignore", "chronicle.csv", "final.snapshot.json", "run.log", "summary.json",
                                 "timeseries.csv"])
        self.assertEqual(summary(d)["seed"], 9)
        self.assertEqual((d / "run.log").read_text(encoding="utf-8"), "analyze 기록")

    def test_unknown_files_refused(self) -> None:
        """모르는 파일·하위 폴더가 있으면 아무것도 지우지 않고 종료 코드 2(사용자 파일을 함부로 지우지 않음, I21)."""
        d = self.tmp / "mixed"
        self.ok(run_runner("--seed=7", "--max-ticks=20", f"--out={d}", "--quiet"))
        (d / "notes.txt").write_text("내 메모", encoding="utf-8")
        before = listing(d)
        cp = run_runner("--seed=9", "--max-ticks=20", f"--out={d}", "--quiet")
        self.assertEqual(cp.returncode, 2)
        self.assertIn("notes.txt", cp.stderr)
        self.assertEqual(listing(d), before)
        (d / "notes.txt").unlink()
        (d / "sub").mkdir()
        self.assertEqual(run_runner("--seed=9", "--max-ticks=20", f"--out={d}", "--quiet").returncode, 2)
        self.assertEqual(summary(d)["seed"], 7)

    def test_config_error_keeps_previous_results(self) -> None:
        """설정 오류는 결과 폴더를 보기 전에 거른다 — 앞 결과가 그대로(I03)."""
        d = self.tmp / "keep"
        self.ok(run_runner("--seed=7", "--max-ticks=20", f"--out={d}", "--quiet"))
        before = listing(d)
        cp = run_runner("--set=population.initial=-1", "--max-ticks=20", f"--out={d}", "--quiet")
        self.assertEqual(cp.returncode, 2)
        self.assertIn("설정 오류", cp.stderr)
        self.assertEqual(listing(d), before)


# ── 설정 오류 ──

class TestConfigErrors(RunnerCase):
    def test_section_override_is_config_error(self) -> None:
        """절 키에 사전(--set=body={...}): 세계를 만들다 스크립트 오류로 멈춰도 0틱 멸종 결과·종료 코드 0 이 아니라 2(I02)."""
        out = self.tmp / "section"
        cp = run_runner('--set=body={"energy_per_size":40}', f"--out={out}", "--quiet")
        self.assertEqual(cp.returncode, 2, cp.stdout + cp.stderr)
        self.assertIn("설정 오류", cp.stderr)
        self.assertFalse((out / "summary.json").exists())

    def test_bad_values_are_config_errors(self) -> None:
        """범위 밖·종류가 다른 값은 종료 코드 2, 결과 없음(I03 — 명령줄 --set 경로)."""
        for i, bad in enumerate(("population.initial=-1", "map.width=4", "mutation.rate=[1]", "없는.키=1")):
            out = self.tmp / f"badval{i}"
            cp = run_runner(f"--set={bad}", f"--out={out}", "--quiet")
            self.assertEqual(cp.returncode, 2, bad)
            self.assertFalse((out / "summary.json").exists(), bad)

    def test_analyze_set_path_records_exit_2(self) -> None:
        """analyze.py --set 경로: 실행기가 2 로 거부한 실행은 failed·exit_code 2 로 기록되고 결과로 세지 않음(I03)."""
        out = self.tmp / "an_bad"
        with contextlib.redirect_stdout(io.StringIO()):
            code = analyze.main(["run", "--seeds", "1", "--set", "population.initial=-1", "--out", str(out),
                                 "--godot", godot_path(), "--timeout", str(TIMEOUT), "--no-report"])
        self.assertEqual(code, 1)
        with (out / "runs.csv").open(encoding="utf-8-sig", newline="") as f:
            runs = list(csv.DictReader(f))
        self.assertEqual([(r["status"], r["exit_code"]) for r in runs], [("failed", "2")])
        self.assertFalse((out / "seed1" / "summary.json").exists())
        self.assertIn("설정 오류", (out / "seed1" / "run.log").read_text(encoding="utf-8"))

    def test_analyze_reruns_incomplete_with_real_runner(self) -> None:
        """analyze.py 이어 돌리기: 덜 쓴 결과(final.snapshot.json 없음)는 다시 돌리고, 실행기는 run.log 가 있는 그 폴더를
        정리해 다시 씀(I07·I21)."""
        out = self.tmp / "an_rerun"
        common = ["run", "--seeds", "1", "--generations", "100", "--max-ticks", "20", "--out", str(out),
                  "--godot", godot_path(), "--timeout", str(TIMEOUT), "--no-report"]
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(analyze.main(common), 0)
        h = summary(out / "seed1")["history_hash"]
        (out / "seed1" / "final.snapshot.json").unlink()
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            self.assertEqual(analyze.main(common), 0)
        self.assertIn("다시 돌림", buf.getvalue())
        self.assertTrue((out / "seed1" / "final.snapshot.json").is_file())
        self.assertEqual(summary(out / "seed1")["history_hash"], h)


# ── 쓰기 실패 ──

class TestWriteFailures(RunnerCase):
    def test_snapshot_write_failure_exits_3(self) -> None:
        """--snapshot-every 중간 스냅숏을 못 쓰면 버리지 않고 오류 줄·종료 코드 3·RESULT 의 write_failed(J10·I17)."""
        blocker = self.tmp / "blocker"
        blocker.write_text("파일이라 폴더를 만들 수 없음", encoding="utf-8")
        cp = run_runner("--max-ticks=40", "--snapshot-every=20", f"--out={blocker / 'out'}", "--quiet")
        self.assertEqual(cp.returncode, 3)
        line = result_line(cp)
        self.assertIn(" write_failed=", line)
        for name in ("snapshot-20.json(", "snapshot-40.json(", "final.snapshot.json(", "summary.json"):
            self.assertIn(name, line)
        self.assertIn("중간 스냅숏을 쓰지 못했습니다", cp.stderr)
        self.assertIsNone(re.search(r"reason=\w+$", line), "쓰기 실패면 RESULT 줄이 reason=… 으로 끝나지 않음")

    def test_result_line_ends_with_reason(self) -> None:
        """정상이면 RESULT 줄이 reason=… 으로 끝남(CI 는 줄 끝까지 맞춰 write_failed 꼬리를 실패로 봄, I17)."""
        out = self.tmp / "okline"
        cp = run_runner("--max-ticks=20", f"--out={out}", "--quiet")
        self.ok(cp)
        self.assertRegex(result_line(cp), r"^RESULT: seed=1 .* reason=max_ticks$")
        self.assertEqual(summary(out)["write_failed"], [])


if __name__ == "__main__":
    unittest.main()
