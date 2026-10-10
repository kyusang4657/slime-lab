#!/usr/bin/env python3
"""빌드·배포 검사(unittest, 파이썬 표준 라이브러리만 + bash·curl·zip·unzip·sha512sum).

  python3 -m unittest discover -s tools -p "test_*.py" -v

GitHub Actions 는 이 기계에서 돌릴 수 없으므로 .github/workflows/build.yml 을 읽어 모양을 확인하고, 그 run 단계와
tools/fetch_godot.sh·build_dist.sh·smoke_run.sh 를 가짜 godot·실행 파일·릴리스(file://)로 실제로 돌려 본다.

1. 워크플로 모양: 모든 run 단계가 bash -eo pipefail(`defaults.run.shell: bash`), 잡마다 timeout-minutes, runs-on 은
   ubuntu-24.04 고정, 액션은 Node 24 판, Godot·템플릿은 fetch_godot.sh(SHA-512)로만·rcedit 는 박아 둔 SHA-512 로 받음,
   zip 판 번호를 박지 않음, 산출물이 없으면 실패, Pages 는 main 의 수동 실행도 배포·enablement 없음·묶음 보존 1일 넘김
   (검토 I17·I56·I58·I59·I60·I80).
2. test 잡의 run 단계를 워크플로가 정한 셸로 실제로 돌림: 가짜 godot 이 실패 종료 코드·쓰기 실패 꼬리·ERROR 를 내면 실패(I17).
3. fetch_godot.sh: 가짜 릴리스를 이 프로세스의 HTTP 서버(127.0.0.1)로 내주고, 맞는 파일만 풀며 목록·파일이 바뀌었거나
   HTTP 404 면 풀기 전에 실패(I60).
4. build_dist.sh: zip·웹 묶음에 고지 파일 넷(LICENSE·CREDITS.md·OFL·GODOT-LICENSE.txt), 이름의 판은 project.godot 에서,
   태그 불일치·내보내기 경고·종료 코드·pck 없음은 실패, 프로젝트 안 build/ 에 .gdignore(I16·I17·I57·I58·I81).
5. smoke_run.sh: 충돌·pck 없음·메인 장면 안 읽음·ERROR·저장소 뿌리의 소스로 대신 뜨는 것은 실패(I17).
6. godot 이 있으면(GODOT 또는 PATH) godot_license.gd 가 엔진 MIT 전문·FreeType 문구·제3자 라이선스 전문을 씀(I16).
7. CREDITS.md 의 엔진 고지·워크플로 출처, Windows 프리셋이 실행 파일 정보를 실제로 바꿈(rcedit), build/.gdignore 가
   저장소에 있음(I16·I57·I79·I81).
"""
from __future__ import annotations

import functools
import hashlib
import http.server
import os
import re
import shutil
import stat
import subprocess
import tempfile
import threading
import unittest
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
WORKFLOW = REPO / ".github" / "workflows" / "build.yml"

# GitHub 이 `shell:` 값마다 쓰는 명령(문서 'jobs.<job_id>.steps[*].shell'). 값이 없으면 Linux 는 `bash -e {0}`.
SHELLS = {
    "bash": ["bash", "--noprofile", "--norc", "-eo", "pipefail"],
    None: ["bash", "-e"],
    "sh": ["sh", "-e"],
}
# 액션마다 Node 24 를 대상으로 하는 가장 낮은 큰 판(각 판의 action.yml `runs.using` 으로 확인함, 2026-10).
# upload-pages-artifact 는 합성 액션이라 안에서 쓰는 upload-artifact 의 판으로 정함(v5 → upload-artifact v7).
NODE24_MIN_MAJOR = {
    "actions/checkout": 5,
    "actions/upload-artifact": 6,
    "actions/download-artifact": 7,
    "actions/upload-pages-artifact": 5,
    "actions/configure-pages": 6,
    "actions/deploy-pages": 5,
}
PINNED_RUNNER = "ubuntu-24.04"
MAX_TIMEOUT_MINUTES = 30
NOTICES = ("LICENSE", "CREDITS.md", "OFL-NanumGothic.txt", "GODOT-LICENSE.txt")
TEST_VERSION = "1.2.3"


# ───────────────────────── 워크플로 읽기(이 파일이 쓰는 YAML 부분만) ─────────────────────────

def _indent(s: str) -> int:
    return len(s) - len(s.lstrip(" "))


def _scalar(v: str):
    v = v.strip()
    if v == "":
        return None
    if len(v) >= 2 and v[0] in "\"'" and v[-1] == v[0]:
        return v[1:-1]
    if v.startswith("[") and v.endswith("]"):
        return [_scalar(x) for x in v[1:-1].split(",") if x.strip()]
    if re.fullmatch(r"-?\d+", v):
        return int(v)
    if v in ("true", "false"):
        return v == "true"
    return v


class _Lines:
    def __init__(self, text: str) -> None:
        self.lines = text.split("\n")
        self.i = 0

    def peek(self) -> str | None:
        """다음 의미 있는 줄(빈 줄·주석 줄은 건너뜀)."""
        while self.i < len(self.lines):
            st = self.lines[self.i].strip()
            if st == "" or st.startswith("#"):
                self.i += 1
                continue
            return self.lines[self.i]
        return None


def _block_scalar(lines: _Lines, parent: int) -> str:
    """`key: |` 아래 글(맨 끝 줄바꿈 하나 — YAML clip)."""
    out: list[str] = []
    ind = None
    while lines.i < len(lines.lines):
        s = lines.lines[lines.i]
        if s.strip() == "":
            out.append("")
            lines.i += 1
            continue
        if _indent(s) <= parent:
            break
        if ind is None:
            ind = _indent(s)
        out.append(s[ind:])
        lines.i += 1
    while out and out[-1] == "":
        out.pop()
    return "\n".join(out) + "\n"


def _parse_map(lines: _Lines, ind: int) -> dict:
    m: dict = {}
    while True:
        s = lines.peek()
        if s is None or _indent(s) != ind or s.strip().startswith("- "):
            return m
        key, _, val = s.strip().partition(":")
        lines.i += 1
        val = val.strip()
        if val in ("|", "|-"):
            m[key] = _block_scalar(lines, ind)
        elif val == "":
            m[key] = _parse(lines, ind + 1)
        else:
            m[key] = _scalar(val)


def _parse(lines: _Lines, min_indent: int):
    s = lines.peek()
    if s is None or _indent(s) < min_indent:
        return None
    ind = _indent(s)
    if not s.strip().startswith("- "):
        return _parse_map(lines, ind)
    seq: list = []
    while True:
        s = lines.peek()
        if s is None or _indent(s) != ind or not s.strip().startswith("- "):
            return seq
        rest = s.strip()[2:].strip()
        if re.match(r"^[A-Za-z0-9_.-]+:(\s|$)", rest):
            lines.lines[lines.i] = " " * (ind + 2) + rest
            seq.append(_parse_map(lines, ind + 2))
        else:
            lines.i += 1
            seq.append(_scalar(rest))


def load_workflow(text: str) -> dict:
    """build.yml 을 사전으로(블록 사상·목록·`|` 글·따옴표·[a, b] 만 — 이 파일이 쓰는 것). PyYAML 이 있으면 같은지 대조한다."""
    return _parse(_Lines(text), 0) or {}


def wf() -> dict:
    return load_workflow(WORKFLOW.read_text(encoding="utf-8"))


def steps(job: str) -> list[dict]:
    return wf()["jobs"][job]["steps"]


def step_named(job: str, prefix: str) -> dict:
    found = [s for s in steps(job) if str(s.get("name", "")).startswith(prefix)]
    assert len(found) == 1, f"{job} 잡에 '{prefix}' 단계가 하나가 아님: {len(found)}"
    return found[0]


def all_steps() -> list[tuple[str, dict]]:
    return [(j, s) for j, job in wf()["jobs"].items() for s in job.get("steps", [])]


def eval_if(expr: str, event: str, ref: str) -> bool:
    """잡 `if:` 식을 주어진 사건·ref 로 계산(==, !=, &&, ||, 괄호, startsWith 만)."""
    py = expr.replace("&&", " and ").replace("||", " or ").replace("startsWith(", "_starts(")
    py = py.replace("github.event_name", "_event").replace("github.ref", "_ref")
    if re.search(r"[A-Za-z_]\w*", re.sub(r"'[^']*'|\b(and|or|not|_starts|_event|_ref)\b", "", py)):
        raise AssertionError(f"계산할 수 없는 if 식: {expr}")
    return bool(eval(py, {"__builtins__": {}}, {"_event": event, "_ref": ref, "_starts": str.startswith}))


def write_exe(path: Path, text: str) -> Path:
    path.write_text(text, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return path


def sha512(path: Path) -> str:
    return hashlib.sha512(path.read_bytes()).hexdigest()


# ───────────────────────── 1. 워크플로 모양 ─────────────────────────

class TestWorkflowShape(unittest.TestCase):
    def test_parser_matches_pyyaml(self) -> None:
        try:
            import yaml  # type: ignore
        except ImportError:
            self.skipTest("PyYAML 없음 — 읽기 함수 대조 건너뜀(나머지 검사는 이 읽기 함수로 함)")
        text = WORKFLOW.read_text(encoding="utf-8")
        ref = yaml.safe_load(text)
        mine = load_workflow(text)
        for k in ("name", "permissions", "defaults", "env", "jobs"):
            self.assertEqual(mine.get(k), ref.get(k), k)
        self.assertEqual(mine["on"], ref[True])  # YAML 1.1 은 on 을 참으로 읽음

    def test_every_run_step_uses_pipefail(self) -> None:
        w = wf()
        self.assertEqual((w.get("defaults") or {}).get("run", {}).get("shell"), "bash",
                         "defaults.run.shell: bash 가 없으면 GitHub 기본 셸은 bash -e {0}(pipefail 없음)")
        for job, s in all_steps():
            if "run" in s:
                self.assertIn(s.get("shell", "bash"), ("bash",), f"{job}/{s.get('name')} 셸")

    def test_jobs_have_timeout_and_pinned_runner(self) -> None:
        for name, job in wf()["jobs"].items():
            t = job.get("timeout-minutes")
            self.assertIsInstance(t, int, f"{name}: timeout-minutes 없음(기본 360분)")
            self.assertTrue(0 < t <= MAX_TIMEOUT_MINUTES, f"{name}: timeout-minutes={t}")
            self.assertEqual(job.get("runs-on"), PINNED_RUNNER, f"{name}: runs-on")

    def test_actions_target_node24(self) -> None:
        seen = set()
        for job, s in all_steps():
            if "uses" not in s:
                continue
            m = re.fullmatch(r"([\w.-]+/[\w.-]+)@v(\d+)", s["uses"])
            self.assertIsNotNone(m, f"{job}: 큰 판 태그가 아닌 액션 {s['uses']}")
            action, major = m.group(1), int(m.group(2))
            self.assertIn(action, NODE24_MIN_MAJOR, f"Node 판을 확인하지 않은 액션 {action}")
            self.assertGreaterEqual(major, NODE24_MIN_MAJOR[action], f"{action}@v{major} 는 Node 20 대상")
            seen.add(action)
        self.assertEqual(seen, set(NODE24_MIN_MAJOR))

    def test_downloads_are_verified(self) -> None:
        env = wf()["env"]
        for k in ("GODOT_SHA512_SUMS", "RCEDIT_SHA512"):
            self.assertRegex(str(env.get(k, "")), r"^[0-9a-f]{128}$", k)
        fetches = 0
        for job, s in all_steps():
            body = s.get("run", "")
            for line in re.findall(r"curl[^\n]*", body):
                self.assertRegex(line, r"curl\s+-\w*f", f"{job}: HTTP 오류에도 성공하는 curl: {line}")
                self.assertIn("sha512sum -c", body, f"{job}: curl 로 받은 파일을 확인하지 않음")
            self.assertNotIn("godotengine/godot/releases", body, f"{job}: Godot 을 fetch_godot.sh 없이 받음")
            fetches += body.count("tools/fetch_godot.sh editor")
        self.assertEqual(fetches, 2, "test·export 잡 둘 다 fetch_godot.sh 로 Godot 을 받음")
        tpl = step_named("export", "Godot 와 내보내기 템플릿")["run"]
        self.assertIn("tools/fetch_godot.sh templates", tpl)

    def test_zip_version_not_hardcoded(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIsNone(re.search(r"slime-lab-\d", text), "zip 이름에 판 번호를 박음")
        paths = [s["with"]["path"] for _, s in all_steps()
                 if s.get("uses", "").startswith("actions/upload-artifact@") and "slime-lab-" in str(s["with"]["path"])]
        self.assertEqual(len(paths), 2)
        for p in paths:
            self.assertIn("${{ env.SLIME_LAB_VERSION }}", p)

    def test_uploads_fail_when_missing(self) -> None:
        n = 0
        for job, s in all_steps():
            if s.get("uses", "").startswith("actions/upload-artifact@"):
                self.assertEqual(s["with"].get("if-no-files-found"), "error", f"{job}: {s['with'].get('name')}")
                n += 1
        self.assertEqual(n, 3)

    def test_pages_condition(self) -> None:
        cond = wf()["jobs"]["pages"]["if"]
        main = "refs/heads/main"
        self.assertTrue(eval_if(cond, "push", main))
        self.assertTrue(eval_if(cond, "workflow_dispatch", main), "Actions 탭 'Run workflow' 도 배포")
        self.assertFalse(eval_if(cond, "pull_request", "refs/pull/1/merge"))
        self.assertFalse(eval_if(cond, "push", "refs/tags/v0.1.0"))
        self.assertFalse(eval_if(cond, "workflow_dispatch", "refs/heads/other"))
        rel = wf()["jobs"]["release"]["if"]
        self.assertTrue(eval_if(rel, "push", "refs/tags/v0.1.0"))
        self.assertFalse(eval_if(rel, "push", main))

    def test_pages_steps(self) -> None:
        for s in steps("pages"):
            if s.get("uses", "").startswith("actions/configure-pages@"):
                self.assertNotIn("enablement", s.get("with") or {}, "GITHUB_TOKEN 으로는 Pages 를 켤 수 없음")
        up = [s for s in steps("export") if s.get("uses", "").startswith("actions/upload-pages-artifact@")]
        self.assertEqual(len(up), 1)
        self.assertEqual(up[0]["with"]["path"], "build/web")
        self.assertGreater(int(up[0]["with"].get("retention-days", 1)), 1,
                           "기본 1일이면 다음 날 'Re-run failed jobs' 의 pages 가 묶음을 못 찾음")

    def test_export_job_order(self) -> None:
        names = [str(s.get("run", s.get("uses", ""))) for s in steps("export")]

        def at(pat: str, unique: bool = True) -> int:
            hits = [i for i, n in enumerate(names) if pat in n]
            self.assertTrue(hits and (len(hits) == 1 or not unique), pat)
            return hits[0]

        rcedit, dist, smoke = at("rcedit-x64.exe"), at("tools/build_dist.sh"), at("tools/smoke_run.sh")
        self.assertLess(at("--import"), rcedit, "가져오기가 편집기 설정을 다시 쓰기 전에")
        self.assertLess(rcedit, dist)
        self.assertLess(dist, smoke)
        self.assertLess(smoke, at("actions/upload-artifact@", unique=False), "확인한 판만 올림")
        st = steps("export")[dist]
        self.assertEqual(st["env"].get("LC_ALL"), "C.UTF-8", "wine 이 한글 제품 이름을 깨뜨림")
        self.assertIn("GODOT", st["env"])
        prep = steps("export")[rcedit]["run"]
        for need in ("sha512sum -c", "export/windows/rcedit", "export/windows/wine", "editor_settings-"):
            self.assertIn(need, prep)


# ───────────────────────── 2. test 잡 단계를 실제로 돌리기 ─────────────────────────

FAKE_GODOT = '#!/usr/bin/env bash\nprintf "%b" "${FAKE_OUT:-}"\nexit "${FAKE_RC:-0}"\n'
GOOD_RESULT = ("RESULT: seed=1 generations=100.0 ticks=6690 pop=105 civ=2(저장) hash=713cea4dea1d time=24.4s "
               "reason=generations\\n")


class TestWorkflowSteps(unittest.TestCase):
    def run_step(self, step: dict, out: str, rc: int) -> int:
        shell = SHELLS[step.get("shell", (wf().get("defaults") or {}).get("run", {}).get("shell"))]
        with tempfile.TemporaryDirectory() as d:
            write_exe(Path(d) / "godot", FAKE_GODOT)
            script = Path(d) / "step.sh"
            script.write_text(step["run"], encoding="utf-8")
            env = dict(os.environ, RUNNER_TEMP=d, FAKE_OUT=out, FAKE_RC=str(rc))
            r = subprocess.run([*shell, str(script)], cwd=d, env=env, capture_output=True, text=True)
            return r.returncode

    def test_experiment_step(self) -> None:
        st = step_named("test", "헤드리스 실험")
        failed_tail = GOOD_RESULT.replace("\\n", " write_failed=summary.json(저장 실패: Can't open file)\\n")
        self.assertEqual(self.run_step(st, GOOD_RESULT, 0), 0, "정상 실행은 통과")
        cases = {
            "쓰기 실패(종료 코드 3, 꼬리)": (failed_tail, 3),
            "쓰기 실패 꼬리만(종료 코드 0)": (failed_tail, 0),
            "종료 코드만 3": (GOOD_RESULT, 3),
            "엔진 ERROR 줄": ("ERROR: 파일을 쓸 수 없습니다: results/ci/summary.json\\n" + GOOD_RESULT, 0),
        }
        for name, (out, rc) in cases.items():
            with self.subTest(name):
                self.assertNotEqual(self.run_step(st, out, rc), 0, name)

    def test_test_steps_keep_godot_exit_code(self) -> None:
        for job, prefix, ok in (("test", "규칙 검사", "PASS a\\nRESULT: 3 passed, 0 failed\\n"),
                                ("test", "화면 검사", "PASS a\\nRESULT: 3 passed, 0 failed (view)\\n"),
                                ("test", "가져오기", "import\\n"), ("export", "가져오기", "import\\n")):
            st = step_named(job, prefix)
            with self.subTest(f"{job}/{prefix}"):
                self.assertEqual(self.run_step(st, ok, 0), 0)
                self.assertNotEqual(self.run_step(st, ok, 1), 0, "godot 종료 코드 1 인데 통과(pipefail 없음)")


# ───────────────────────── 3. fetch_godot.sh ─────────────────────────

class _QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args) -> None:
        pass


class TestFetchGodot(unittest.TestCase):
    VERSION = "9.9.9"

    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(tempfile.mkdtemp())
        handler = functools.partial(_QuietHandler, directory=str(cls.root))
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        shutil.rmtree(cls.root)

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(dir=self.root))
        self.rel = self.tmp / "release"
        self.rel.mkdir()
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}/{self.tmp.name}/release"
        self.editor = f"Godot_v{self.VERSION}-stable_linux.x86_64.zip"
        self.tpz = f"Godot_v{self.VERSION}-stable_export_templates.tpz"
        with zipfile.ZipFile(self.rel / self.editor, "w") as z:
            z.writestr(f"Godot_v{self.VERSION}-stable_linux.x86_64", "#!/bin/sh\necho fake godot\n")
        with zipfile.ZipFile(self.rel / self.tpz, "w") as z:
            z.writestr("templates/linux_release.x86_64", "linux")
            z.writestr("templates/version.txt", f"{self.VERSION}.stable")
            z.writestr("templates/windows_release_x86_64.exe", "win")
        self.write_sums()

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp)

    def write_sums(self, skip: str = "") -> None:
        lines = [f"{sha512(self.rel / n)}  {n}" for n in (self.editor, self.tpz) if n != skip]
        (self.rel / "SHA512-SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    def fetch(self, *args: str, pinned: str | None = None) -> tuple[int, str]:
        env = dict(os.environ, GODOT_VERSION=self.VERSION, GODOT_DOWNLOAD_BASE=self.base,
                   GODOT_SHA512_SUMS=pinned or sha512(self.rel / "SHA512-SUMS.txt"), TMPDIR=str(self.tmp),
                   no_proxy="127.0.0.1", NO_PROXY="127.0.0.1")
        env.pop("RUNNER_TEMP", None)
        r = subprocess.run(["bash", str(REPO / "tools" / "fetch_godot.sh"), *args], env=env,
                           capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr

    def test_good_release(self) -> None:
        dest = self.tmp / "d"
        rc, out = self.fetch("editor", str(dest))
        self.assertEqual(rc, 0, out)
        self.assertTrue(os.access(dest / "godot", os.X_OK))
        rc, out = self.fetch("templates", str(dest / "t"), "linux_release.x86_64", "version.txt")
        self.assertEqual(rc, 0, out)
        self.assertEqual(sorted(p.name for p in (dest / "t").iterdir()), ["linux_release.x86_64", "version.txt"])
        self.assertEqual([p.name for p in self.tmp.iterdir() if p.name.startswith("fetch_godot.")], [],
                         "임시 폴더를 지움")

    def test_bad_downloads_stop_before_extracting(self) -> None:
        def tamper() -> None:
            with zipfile.ZipFile(self.rel / self.editor, "a") as z:
                z.writestr("extra", "x")

        # 이름: (망가뜨리기, 박아 둘 값, 실패 문장에 있어야 할 말 — 엉뚱한 단계의 메시지가 아니게)
        cases = {
            "박아 둔 목록 값과 다름": (lambda: None, "0" * 128, "SHA512-SUMS.txt 의 SHA-512"),
            "파일이 목록과 다름": (tamper, None, "SHA-512 가 SHA512-SUMS.txt 와 다릅니다"),
            "목록에 그 파일 줄이 없음": (lambda: self.write_sums(skip=self.editor), None, "줄이 하나가 아닙니다"),
            "파일이 없음(HTTP 404)": (lambda: (self.rel / self.editor).unlink(), None, "받기 실패"),
        }
        for name, (break_it, pinned, says) in cases.items():
            with self.subTest(name):
                self.tearDown()
                self.setUp()
                break_it()
                dest = self.tmp / "d"
                rc, out = self.fetch("editor", str(dest), pinned=pinned)
                self.assertNotEqual(rc, 0, out)
                self.assertIn(says, out)
                self.assertFalse((dest / "godot").exists(), "확인 전에 풀었음")


# ───────────────────────── 4. build_dist.sh ─────────────────────────

FAKE_EDITOR = r"""#!/usr/bin/env bash
# 가짜 godot 편집기: --export-release 와 --script res://tools/godot_license.gd 만 흉내.
# Windows 는 rcedit 가 한 것처럼 프리셋의 회사·제품·설명·저작권과 판을 UTF-16LE 로 넣는다(FAKE_NORES 면 빼서 'Godot Engine' 그대로).
proj=""; preset=""; outp=""; script=""; lic=""
while [ $# -gt 0 ]; do
  case "$1" in
    --path) proj="$2"; shift 2; continue ;;
    --export-release) preset="$2"; outp="$3"; shift 3; continue ;;
    --script) script="$2" ;;
    --out=*) lic="${1#--out=}" ;;
  esac
  shift
done
u16() { printf '%s' "$1" | iconv -f UTF-8 -t UTF-16LE; }
echo "Godot Engine v4.4.1.stable.official"
if [ -n "$preset" ]; then
  [ "${FAKE_WARN_PRESET:-}" = "$preset" ] && printf 'WARNING: Project export for preset "%s" completed with warnings.\n' "$preset"
  case "$preset" in
    Web) d="$(dirname "$outp")"; for f in index.html index.js index.wasm index.pck index.png; do echo web > "$d/$f"; done ;;
    *)
      printf 'BIN' > "$outp"
      if [ "$preset" = "Windows Desktop" ] && [ -z "${FAKE_NORES:-}" ]; then
        sed -n 's/^application\/\(company_name\|product_name\|file_description\|copyright\)="\(.*\)"$/\2/p' \
          "$proj/export_presets.cfg" | while IFS= read -r v; do u16 "$v"; done >> "$outp"
        u16 "$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "$proj/project.godot").0" >> "$outp"
      fi
      [ "${FAKE_NOPCK:-}" = "$preset" ] || printf 'GDPC' >> "$outp" ;;
  esac
  # 파일을 쓴 뒤 실패 종료 코드(종료 코드만 보고 잡는지)
  [ "${FAKE_FAIL_PRESET:-}" = "$preset" ] && { echo "export failed"; exit 1; }
  echo "savepack: end"; exit 0
fi
if [ "$script" = "res://tools/godot_license.gd" ]; then
  [ -n "${FAKE_LICENSE_FAIL:-}" ] && exit 1
  printf 'Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).\n' > "$lic"; exit 0
fi
exit 2
"""


class TestBuildDist(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.root = self.tmp / "proj"
        (self.root / "tools").mkdir(parents=True)
        (self.root / "assets" / "fonts").mkdir(parents=True)
        shutil.copy(REPO / "tools" / "build_dist.sh", self.root / "tools")
        for f in ("LICENSE", "CREDITS.md", "assets/fonts/OFL-NanumGothic.txt", "export_presets.cfg"):
            shutil.copy(REPO / f, self.root / f)
        proj = (REPO / "project.godot").read_text(encoding="utf-8")
        proj = re.sub(r'(?m)^config/version=".*"$', f'config/version="{TEST_VERSION}"', proj)
        (self.root / "project.godot").write_text(proj, encoding="utf-8")
        self.godot = write_exe(self.tmp / "godot", FAKE_EDITOR)
        self.ghenv = self.tmp / "github_env"

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp)

    def build(self, **extra: str) -> tuple[int, str]:
        env = {k: v for k, v in os.environ.items() if not k.startswith(("GITHUB_", "FAKE_"))}
        env.update(GODOT=str(self.godot), GITHUB_ENV=str(self.ghenv), **extra)
        r = subprocess.run(["bash", str(self.root / "tools" / "build_dist.sh")], cwd=self.root, env=env,
                           capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr

    def test_bundles_carry_notices(self) -> None:
        rc, out = self.build()
        self.assertEqual(rc, 0, out)
        b = self.root / "build"
        for p, exe in (("linux", "slime-lab.x86_64"), ("windows", "slime-lab.exe")):
            z = b / f"slime-lab-{TEST_VERSION}-{p}.zip"
            self.assertTrue(z.is_file(), f"판 번호는 project.godot 에서: {z.name}")
            with zipfile.ZipFile(z) as zz:
                self.assertEqual(sorted(zz.namelist()), sorted([exe, *NOTICES]))
        web = {p.name for p in (b / "web").iterdir()}
        self.assertTrue(set(NOTICES) <= web, f"웹 묶음에 고지 파일: {sorted(web)}")
        self.assertIn("Godot Engine contributors", (b / "web" / "GODOT-LICENSE.txt").read_text(encoding="utf-8"))
        self.assertTrue((b / ".gdignore").is_file(), "프로젝트 안 build/ 에 .gdignore")
        self.assertIn(f"SLIME_LAB_VERSION={TEST_VERSION}", self.ghenv.read_text(encoding="utf-8"))

    def test_tag_must_match_version(self) -> None:
        rc, out = self.build(GITHUB_REF_TYPE="tag", GITHUB_REF_NAME="v9.0.0")
        self.assertNotEqual(rc, 0, out)
        self.assertFalse((self.root / "build" / "linux").exists(), "판 확인은 내보내기 전에")
        rc, out = self.build(GITHUB_REF_TYPE="tag", GITHUB_REF_NAME=f"v{TEST_VERSION}")
        self.assertEqual(rc, 0, out)
        rc, out = self.build(GITHUB_REF_TYPE="branch", GITHUB_REF_NAME="main")
        self.assertEqual(rc, 0, out)

    def test_export_problems_fail(self) -> None:
        cases = {
            "Windows 내보내기 경고(rcedit 없음 등)": {"FAKE_WARN_PRESET": "Windows Desktop"},
            "웹 내보내기 종료 코드 1": {"FAKE_FAIL_PRESET": "Web"},
            "Linux 실행 파일에 pck 없음": {"FAKE_NOPCK": "Linux"},
            # rcedit 가 wine 안에서 죽으면 엔진은 경고 없이 'Godot Engine' 정보 그대로 내보낸다(TMPDIR 이 긴 경로일 때 확인함)
            "Windows 실행 파일 정보가 안 바뀜": {"FAKE_NORES": "1"},
            "엔진 고지 만들기 실패": {"FAKE_LICENSE_FAIL": "1"},
        }
        for name, extra in cases.items():
            with self.subTest(name):
                rc, out = self.build(**extra)
                self.assertNotEqual(rc, 0, out)
                self.assertEqual(list((self.root / "build").glob("*.zip")), [], "실패한 판을 묶지 않음")


# ───────────────────────── 5. smoke_run.sh ─────────────────────────

SCENE_LINE = "Loading resource: res://.godot/exported/133200997/export-c24ae29f-lab.scn"


def fake_app(body: str, pck: bool = True) -> str:
    return "#!/usr/bin/env bash\n" + body + "\nexit 0\n" + ("# GDPC" if pck else "")


class TestSmokeRun(unittest.TestCase):
    def smoke(self, text: str, cwd: Path = REPO) -> tuple[int, str]:
        with tempfile.TemporaryDirectory() as d:
            exe = write_exe(Path(d) / "slime-lab.x86_64", text)
            env = {k: v for k, v in os.environ.items() if k != "RUNNER_TEMP"}
            env["TMPDIR"] = d
            r = subprocess.run(["bash", str(REPO / "tools" / "smoke_run.sh"), str(exe), "5"], cwd=cwd, env=env,
                               capture_output=True, text=True)
            return r.returncode, r.stdout + r.stderr

    def test_good_run_passes(self) -> None:
        rc, out = self.smoke(fake_app(f'echo "Godot Engine v4.4.1"; echo "{SCENE_LINE}"; echo "ALSA lib x"'))
        self.assertEqual(rc, 0, out)

    def test_broken_runs_fail(self) -> None:
        cases = {
            "충돌(SIGSEGV)": fake_app(f'echo "{SCENE_LINE}"; kill -SEGV $$'),
            "pck 없는 실행 파일": fake_app(f'echo "{SCENE_LINE}"', pck=False),
            "프로젝트 자료를 못 읽음": fake_app(
                "echo 'Error: Couldn'\"'\"'t load project data at path \".\". Is the .pck file missing?'; exit 1"),
            "메인 장면을 읽지 않음": fake_app('echo "Godot Engine v4.4.1"'),
            "엔진 ERROR(종료 코드 0)": fake_app(f'echo "{SCENE_LINE}"; echo "ERROR: Failed loading scene: res://x"'),
            "SCRIPT ERROR": fake_app(f'echo "{SCENE_LINE}"; echo "SCRIPT ERROR: Invalid call"'),
            # 저장소 뿌리(project.godot 이 있는 곳)에서 띄우면 pck 없이도 소스로 떠서 통과하던 경우
            "현재 폴더의 소스로만 뜸": fake_app(
                f'if [ -f project.godot ]; then echo "{SCENE_LINE}"; else echo "Error: Couldn'"'"'t load project data"; exit 1; fi'),
        }
        for name, text in cases.items():
            with self.subTest(name):
                rc, out = self.smoke(text)
                self.assertNotEqual(rc, 0, out)


# ───────────────────────── 6. 실제 엔진으로 고지 파일 만들기 ─────────────────────────

def _godot() -> str | None:
    g = os.environ.get("GODOT") or shutil.which("godot")
    return g if g and (shutil.which(g) or os.path.isfile(g)) else None


@unittest.skipUnless(_godot(), "godot 없음(GODOT 환경 변수나 PATH) — 실제 엔진 고지 검사 건너뜀")
class TestGodotLicense(unittest.TestCase):
    def test_license_file_from_engine(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "GODOT-LICENSE.txt"
            r = subprocess.run([_godot(), "--headless", "--path", str(REPO), "--script", "res://tools/godot_license.gd",
                                "--", f"--out={out}"], capture_output=True, text=True, timeout=120)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            text = out.read_text(encoding="utf-8")
        for need in ("Copyright (c) 2014-present Godot Engine contributors",
                     "Permission is hereby granted, free of charge",
                     "Portions of this software are copyright © ",
                     "The FreeType Project (www.freetype.org). All rights reserved.",
                     "Comment: The FreeType Project", "License: FTL", "License: Expat", "Comment: Mbed TLS"):
            self.assertIn(need, text)
        self.assertRegex(text, r"copyright © \d{4}-\d{4} The FreeType Project", "FreeType 연도는 엔진 정보에서")

    def test_missing_out_fails(self) -> None:
        r = subprocess.run([_godot(), "--headless", "--path", str(REPO), "--script", "res://tools/godot_license.gd"],
                           capture_output=True, text=True, timeout=120)
        self.assertNotEqual(r.returncode, 0)


# ───────────────────────── 7. 출처·프리셋·build/.gdignore ─────────────────────────

class TestCreditsAndPresets(unittest.TestCase):
    def test_credits_engine_notice_and_workflow_origin(self) -> None:
        credits = (REPO / "CREDITS.md").read_text(encoding="utf-8")
        engine = next(ln for ln in credits.splitlines() if ln.startswith("| 게임 엔진 |"))
        for need in ("GODOT-LICENSE.txt", "https://godotengine.org/license", "Godot Engine contributors", "FreeType",
                     "tools/godot_license.gd"):
            self.assertIn(need, engine)
        moved = [ln for ln in credits.splitlines() if "little-monster-village" in ln and "가져와 고침" in ln]
        self.assertTrue(any(ln.count(".github/workflows/build.yml") >= 2 for ln in moved),
                        "가져와 고침 표에 워크플로(위치와 원래 파일)")
        last = credits.strip().splitlines()[-1]
        for n in NOTICES:
            self.assertIn(n, last, "배포판 고지 문단")
        self.assertIn("웹", last)

    def test_windows_preset_writes_version_info(self) -> None:
        text = (REPO / "export_presets.cfg").read_text(encoding="utf-8")
        opts = text.split("[preset.1.options]")[1].split("[preset.2]")[0]
        self.assertIn('platform="Windows Desktop"', text.split("[preset.1]")[1].split("[preset.1.options]")[0])
        self.assertRegex(opts, r"(?m)^application/modify_resources=true$",
                         "false 면 회사·제품·저작권 값이 실행 파일에 들어가지 않고 'Godot Engine' 그대로")
        for k in ("company_name", "product_name", "file_description", "copyright"):
            self.assertRegex(opts, rf'(?m)^application/{k}=".+"$', k)

    def test_build_gdignore_tracked(self) -> None:
        self.assertTrue((REPO / "build" / ".gdignore").is_file())
        if shutil.which("git") and (REPO / ".git").exists():
            r = subprocess.run(["git", "-C", str(REPO), "ls-files", "--error-unmatch", "build/.gdignore"],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, "build/.gdignore 가 저장소에 없음")
            r = subprocess.run(["git", "-C", str(REPO), "check-ignore", "-q", "build/linux/x"], capture_output=True)
            self.assertEqual(r.returncode, 0, "내보낸 파일은 계속 무시")


if __name__ == "__main__":
    unittest.main()
