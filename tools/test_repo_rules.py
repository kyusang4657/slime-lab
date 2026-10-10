#!/usr/bin/env python3
"""저장소 규칙 검사(unittest, 파이썬 표준 라이브러리만).

  python3 -m unittest discover -s tools -p "test_*.py" -v

1. `assets/` 아래 모든 파일(가져오기 부속 `.import` 제외)이 CREDITS.md 에 적혀 있다(출처 원칙).
2. 화면 코드(scripts/view, scripts/ui)가 시뮬레이션에 닿는 이름은 모두 docs/SIM-API.md 에 있다(C#/GDExtension 으로
   바꿔 끼울 경계). 세계에 닿는 꼴: `world.X`·`_world.X`, 사슬 `lab.world.X`·`experiments[k].world.X`, 그리고 세계를 가리키는
   이름 `w.X` — `SimWorld` 로 적은 변수·인자, `var w := x.world`(…`if … else null` 포함)·`var w2 = w` 처럼 세계를 받은 변수.
   함수 안에서 생긴 이름은 그 함수 안에서만, 멤버 선언이면 파일 전체(다른 함수의 `w` 는 폭일 수 있음). 기록기(`SimRecorder` 로
   적은 이름·`recorder.X`)와 정적 이름(`SimConfig.X`·`SimSnapshot.X` 등)도 같은 방식. 주석·문자열 안은 보지 않는다.
   또 화면은 세계를 바꾸지 않는다(VIEW-API 규칙 1): 세계에 닿은 멤버에 대입(`=`·`+=`·`[i] =`)·읽기 허용 목록(`READ_ONLY_CALLS` —
   `size`·`get`·`duplicate` 등) 밖의 메서드 호출·진행 호출(`step`·`step_n`·`setup`·`sample`·`drain_events`)은 실패 — 진행·기록은
   Experiment(`setup`·`step`·`step_n`·`sample`)와 LabMain(`drain_events`)만. 세계 멤버를 받은 변수(`var c := w.cfg`,
   `for e in w.chronicle`)를 고치는 것도 실패. (예전엔 고치는 메서드의 금지 목록이라 `get_or_add`·`encode_u8`·`call` 을 놓쳤음.)
   한계: 이름으로만 따라가므로 사전·배열에 넣었다 꺼낸 세계나 다른 함수가 돌려준 세계는 보지 못한다.
3. 문서(DESIGN·VIEW-API·ANALYSIS)에 백틱으로 적은 `ui.절.키` 는 config/ui.json 에 실제로 있다(키 이름이 낡지 않게).
4. 사용자 데이터 폴더 이름이 영문(project.godot `custom_user_dir_name`) — 경로에 한글이 들어가면 엔진 FileDialog 가 거짓
   "권한 없음" 을 띄운다(TEST-REPORT I06).
5. 문서가 말하는 그래프·연대기 색의 색각 이상 수치(VIEW-API 그래프·연대기 절 — 문턱 수는 그 문장에서 읽음)가
   config/ui.json 의 실제 색에서 성립한다(그래프 A·B·출생 모든 쌍, 연대기는 `other` 를 뺀 다섯 묶음 모든 쌍). 계산은 dataviz
   검사기와 같음: Machado·Oliveira·Fernandes(2009) 심도 1.0 적색맹·녹색맹 모의, OKLab 거리 ×100(ΔE), WCAG 명도 대비,
   OKLCH 명도·채도 범위(어두운 바탕 0.48~0.67, 채도 ≥ 0.10). 예전에는 저장소 밖 검사기로 한 번 잰 수치였다(검토 G52).
"""
from __future__ import annotations

import json
import math
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
VIEW_DIRS = ("scripts/view", "scripts/ui")


def backticked(text: str) -> list[str]:
    """`...` 안의 글자들."""
    return re.findall(r"`([^`\n]+)`", text)


class TestCredits(unittest.TestCase):
    def test_every_asset_is_credited(self) -> None:
        credits = (REPO / "CREDITS.md").read_text(encoding="utf-8")
        missing = []
        for p in sorted((REPO / "assets").rglob("*")):
            if p.is_dir() or p.suffix == ".import" or p.name.startswith("."):
                continue
            if p.name not in credits:
                missing.append(p.relative_to(REPO).as_posix())
        self.assertEqual(missing, [], "CREDITS.md 에 없는 자산")

    def test_readme_mentions_font_license(self) -> None:
        readme = (REPO / "README.md").read_text(encoding="utf-8")
        self.assertIn("OFL", readme)
        self.assertIn("OFL-NanumGothic.txt", readme)


# ───────────────────────── GDScript 훑기(경계 검사용) ─────────────────────────

def gd_code_lines(text: str) -> list[str]:
    """줄마다 주석(`#` 부터)을 지우고 문자열 안을 비운 코드. 줄 수·줄 번호는 그대로(세 따옴표 문자열은 여러 줄)."""
    out: list[str] = []
    triple = ""
    for line in text.split("\n"):
        res: list[str] = []
        i, n = 0, len(line)
        if triple:
            end = line.find(triple)
            if end < 0:
                out.append("")
                continue
            res.append(triple)
            i = end + 3
            triple = ""
        while i < n:
            ch = line[i]
            if ch == "#":
                break
            if ch in "\"'":
                if line.startswith(ch * 3, i):
                    end = line.find(ch * 3, i + 3)
                    if end < 0:
                        triple = ch * 3
                        res.append(triple)
                        break
                    res.append(ch * 6)
                    i = end + 3
                    continue
                j = i + 1
                while j < n and line[j] != ch:
                    j += 2 if line[j] == "\\" else 1
                res.append(ch * 2)
                i = j + 1
                continue
            res.append(ch)
            i += 1
        out.append("".join(res))
    return out


_FUNC_RE = re.compile(r"^\s*(?:static\s+)?func\s+[A-Za-z_]\w*")


def gd_scopes(lines: list[str]) -> tuple[list[int], list[list[int]]]:
    """(함수 밖 줄 번호들, 이름 있는 함수마다 그 줄 번호들). 이름 없는 `func(...)`(람다)는 감싼 함수에 속한다."""
    top: list[int] = []
    funcs: list[list[int]] = []
    cur: list[int] | None = None
    for i, ln in enumerate(lines):
        if not ln.strip():
            continue
        if _FUNC_RE.match(ln):
            cur = [i]
            funcs.append(cur)
            continue
        if not ln[0].isspace():
            cur = None
        (top if cur is None else cur).append(i)
    return top, funcs


# 세계·기록기에 닿는 기본 꼴: 이름 `world`·`_world`(`recorder`), 또는 무엇이든 `.world`(`.recorder`) 사슬
SIM_KINDS = {
    "SimWorld": r"(?:(?<![\w.])_?world|\.world)",
    "SimRecorder": r"(?:(?<![\w.])_?recorder|\.recorder)",
}
_IDENT = r"[A-Za-z_]\w*"
_CHAIN = r"(?:\s*\[[^\]\n]*\]|\.[A-Za-z_]\w*)*"
_ASSIGN_RE = re.compile(r"^\s*(?:@\w+\s+)*(?:static\s+)?(?:var\s+)?(" + _IDENT + r")\s*(?::\s*[\w\[\]]*\s*)?:?=(?!=)\s*(.+?)\s*$")
_FOR_RE = re.compile(r"^\s*for\s+(" + _IDENT + r")\s*(?::\s*[\w\[\]]+\s*)?\s+in\s+(.+?)\s*:\s*$")
_WRITE_AFTER = re.compile(_CHAIN + r"\s*(?:\*\*|<<|>>|[-+*/%&|^])?=(?!=)")
# 세계 멤버(사슬)와 그것을 받은 변수에 붙여 불러도 되는 메서드 — 읽기만 하는 것의 허용 목록. 이 밖의 호출은 세계를 바꿀 수 있는
# 것으로 셈(검토 I36: 예전엔 고치는 메서드의 금지 목록 append·clear … 이라 get_or_add·encode_u8·call 같은 꼴을 놓쳤다).
# 화면 코드가 새 읽기 메서드를 쓰면 세계를 바꾸지 않는지 확인하고 여기에 더할 것.
READ_ONLY_CALLS = (
    "size", "is_empty", "has", "has_all", "get", "keys", "values", "duplicate", "slice", "find", "rfind", "count",
    "back", "front", "min", "max", "hash", "is_read_only", "begins_with", "ends_with", "contains", "merged",
    "recursive_equal", "to_byte_array", "hex_encode", "get_string_from_utf8", "bsearch", "get_state_string",
)
_CALL_AFTER = re.compile(_CHAIN + r"\.([A-Za-z_]\w*)\s*\(")


def _mutating_call(rest: str) -> str:
    """세계 멤버 바로 뒤(사슬을 지나) 허용 목록 밖 메서드를 부르면 그 이름, 아니면 ""."""
    m = _CALL_AFTER.match(rest)
    return m.group(1) if m and m.group(1) not in READ_ONLY_CALLS else ""
# 세계를 진행하거나 상태를 바꾸는 호출과, 그것을 불러도 되는 파일(VIEW-API 규칙 1: 진행·기록(`sample`)은 Experiment = 세계 + 기록기,
# 사건 비우기는 LabMain)
WORLD_DRIVE_CALLS = ("step", "step_n", "setup", "sample", "drain_events")
WORLD_DRIVE_ALLOWED = {"experiment.gd": {"setup", "step", "step_n", "sample"}, "lab_main.gd": {"drain_events"}}
STATIC_CLASSES = ("SimWorld", "SimGrid", "SimBrain", "SimConfig", "SimSnapshot", "SimRecorder", "SimRng", "SimTerrain")


def _alt(names: set[str]) -> str:
    return "|".join(sorted((re.escape(n) for n in names), key=len, reverse=True))


def _pieces(rhs: str) -> list[str]:
    """`a if c else b` 의 두 갈래(아니면 식 그대로), 바깥 괄호 하나는 벗김."""
    out = []
    for piece in re.split(r"\s+if\s+.+?\s+else\s+", rhs):
        p = piece.strip()
        if p.startswith("(") and p.endswith(")"):
            p = p[1:-1].strip()
        out.append(p)
    return out


def _yields(rhs: str, kind: str, names: set[str]) -> bool:
    """오른쪽 식이 그 대상 자체를 내놓는가(`x.world`, `w`, `exp.world if exp != null else null`, `SimWorld.new()`)."""
    return any(re.search(SIM_KINDS[kind] + r"$", p) or p in names or re.fullmatch(kind + r"\.new\(\s*\)", p)
               for p in _pieces(rhs))


def _member_chain_rhs(rhs: str, refs: str) -> bool:
    """오른쪽 식이 대상의 멤버(사슬, 호출 없음)인가(`w.cfg`, `x.world.chronicle[i]`)."""
    return any(re.fullmatch(r"[\w.\[\] ]*?" + refs + r"\." + _IDENT + _CHAIN, p) for p in _pieces(rhs))


def scan_sim_access(text: str, fname: str = "x.gd") -> dict[str, list]:
    """GDScript 한 파일에서 시뮬레이션에 닿는 곳.
    반환: {"SimWorld": [(줄, 멤버)], "SimRecorder": [(줄, 멤버)], "static": [(줄, "SimX.멤버")], "writes": [(줄, 설명)]}."""
    lines = gd_code_lines(text)
    top, funcs = gd_scopes(lines)
    found: dict[str, list] = {k: [] for k in SIM_KINDS}
    found["static"] = []
    found["writes"] = []
    typed = {k: re.compile(r"(?<![\w.])(" + _IDENT + r")\s*:\s*" + k + r"\b(?!\s*\.)") for k in SIM_KINDS}

    def collect(rows: list[int], seed: dict[str, set[str]]) -> dict[str, set[str]]:
        """그 범위에서 세계(기록기)를 가리키는 이름들(이름이 이름을 받으면 끝까지 따라감)."""
        names = {k: set(v) for k, v in seed.items()}
        changed = True
        while changed:
            changed = False
            for i in rows:
                ln = lines[i]
                m = _ASSIGN_RE.match(ln)
                for k in SIM_KINDS:
                    new = set(typed[k].findall(ln))
                    if m and _yields(m.group(2), k, names[k]):
                        new.add(m.group(1))
                    if not new <= names[k]:
                        names[k] |= new
                        changed = True
        return names

    file_names = collect(top, {k: set() for k in SIM_KINDS})
    for rows in [top] + funcs:
        names = file_names if rows is top else collect(rows, file_names)
        refs = {k: "(?:" + base + (r"|(?<![\w.])(?:" + _alt(names[k]) + r")" if names[k] else "") + ")"
                for k, base in SIM_KINDS.items()}
        # 세계 멤버를 받은 변수(사전·배열은 참조라 고치면 세계가 바뀜)
        held: set[str] = set()
        for i in rows:
            m = _ASSIGN_RE.match(lines[i]) or _FOR_RE.match(lines[i])
            if m and _member_chain_rhs(m.group(2), refs["SimWorld"]):
                held.add(m.group(1))
        for i in rows:
            ln = lines[i]
            lineno = i + 1
            for k in SIM_KINDS:
                for m in re.finditer(refs[k] + r"\.(" + _IDENT + r")", ln):
                    member = m.group(1)
                    found[k].append((lineno, member))
                    if k != "SimWorld":
                        continue
                    rest = ln[m.end():]
                    if _WRITE_AFTER.match(rest):
                        found["writes"].append((lineno, f"세계 멤버에 대입: {member}"))
                    elif _mutating_call(rest):
                        found["writes"].append((lineno, f"세계 멤버에 읽기 허용 목록 밖 호출: {member}{rest.split('(')[0]}"))
                    elif member in WORLD_DRIVE_CALLS and re.match(r"\s*\(", rest) \
                            and member not in WORLD_DRIVE_ALLOWED.get(fname, set()):
                        found["writes"].append((lineno, f"세계를 진행·변경하는 호출: {member}()"))
            if held:
                for m in re.finditer(r"(?<![\w.])(" + _alt(held) + r")(?=\s*[.\[])", ln):
                    rest = ln[m.end():]
                    if _WRITE_AFTER.match(rest) or _mutating_call(rest):
                        found["writes"].append((lineno, f"세계 멤버를 받은 {m.group(1)} 을(를) 고침"))
            for m in re.finditer(r"(?<![\w.])(" + "|".join(STATIC_CLASSES) + r")\.(" + _IDENT + r")", ln):
                found["static"].append((lineno, f"{m.group(1)}.{m.group(2)}"))
    return found


def sim_api_names() -> tuple[set[str], set[str]]:
    """SIM-API.md 의 백틱 안 이름들: (멤버 이름 집합, `SimX.이름` 집합 — `SimX.PREFIX_*` 는 머리로)."""
    api = (REPO / "docs" / "SIM-API.md").read_text(encoding="utf-8")
    listed: set[str] = set()
    qualified: set[str] = set()
    for span in backticked(api):
        listed.update(re.findall(r"[A-Za-z_][A-Za-z_0-9]*", span))
        for m in re.finditer(r"(Sim[A-Z]\w*)\.([A-Za-z_]\w*\*?)", span):
            qualified.add(f"{m.group(1)}.{m.group(2)}")
    # `SimGrid.TILE_GRASS`·`TILE_WATER` 처럼 같은 줄에서 클래스 이름을 생략한 상수
    for line in api.split("\n"):
        cls = re.search(r"`(Sim[A-Z]\w*)\.", line)
        if cls:
            for span in backticked(line):
                if re.fullmatch(r"[A-Z][A-Z0-9_]*\*?", span):
                    qualified.add(f"{cls.group(1)}.{span}")
    return listed, qualified


def static_listed(name: str, qualified: set[str]) -> bool:
    return name in qualified or any(q.endswith("*") and name.startswith(q[:-1]) for q in qualified)


class TestSimApiBoundary(unittest.TestCase):
    def _scan_view(self) -> dict[str, dict[str, list]]:
        out = {}
        for d in VIEW_DIRS:
            for f in sorted((REPO / d).glob("*.gd")):
                out[f"{d}/{f.name}"] = scan_sim_access(f.read_text(encoding="utf-8"), f.name)
        return out

    def test_view_uses_only_listed_world_members(self) -> None:
        listed, qualified = sim_api_names()
        used: dict[str, set[str]] = {}
        unlisted_static: dict[str, set[str]] = {}
        counts = {"SimWorld": 0, "SimRecorder": 0, "static": 0}
        for path, found in self._scan_view().items():
            for k in ("SimWorld", "SimRecorder"):
                for _ln, name in found[k]:
                    counts[k] += 1
                    used.setdefault(f"{k}.{name}", set()).add(Path(path).name)
            for _ln, name in found["static"]:
                counts["static"] += 1
                if not static_listed(name, qualified):
                    unlisted_static.setdefault(name, set()).add(Path(path).name)
        # 검사 정규식이 다시 눈멀지 않았는지(4단계 코드는 세계를 수백 곳에서 읽음 — 예전 정규식은 그 일부만 봄)
        self.assertGreater(counts["SimWorld"], 100, "화면 코드에서 세계 멤버를 거의 찾지 못함(검사 정규식 확인)")
        self.assertGreater(counts["SimRecorder"], 2, "화면 코드에서 기록기 멤버를 찾지 못함")
        self.assertGreater(counts["static"], 40, "화면 코드에서 Sim* 정적 이름을 거의 찾지 못함")
        unlisted = {k: sorted(v) for k, v in used.items() if k.split(".", 1)[1] not in listed}
        self.assertEqual(unlisted, {}, "docs/SIM-API.md 에 없는 세계·기록기 멤버를 화면이 씀")
        self.assertEqual({k: sorted(v) for k, v in unlisted_static.items()}, {},
                         "docs/SIM-API.md 에 없는 Sim* 정적 이름을 화면이 씀")

    def test_view_never_writes_world(self) -> None:
        writes = {path: found["writes"] for path, found in self._scan_view().items() if found["writes"]}
        self.assertEqual(writes, {}, "화면 코드가 세계를 바꿈(VIEW-API 규칙 1)")

    def test_scanner_catches_known_forms(self) -> None:
        """검사기 자체가 4단계의 접근 꼴을 잡는지(정규식이 다시 눈멀지 않게). 예전 정규식(맨 `world.`·`_world.` 만)은
        아래 세계 멤버 11개 중 3개(`kid`·`baz` 도 못 봄)만, 고치기는 하나도 잡지 못했다. 33·34·36줄은 고치는 메서드 금지 목록이
        놓치던 꼴(허용 목록으로 바꿔 잡음)."""
        src = "\n".join([
            "extends Control",                                                        # 1
            "var lab: Node",                                                          # 2
            "var _kids_world: SimWorld",                                              # 3
            "var label := \"world.in_string\"  # world.in_comment",                   # 4
            "func a(x) -> int:",                                                      # 5
            "\treturn x.world.period_births + lab.experiments[0].world.tick_a",       # 6
            "func b(x) -> void:",                                                     # 7
            "\tvar w := x.world",                                                     # 8
            "\tvar n := w.bar",                                                       # 9
            "\tvar w2 = w",                                                           # 10
            "\tprint(w2.qux, _kids_world.kid, n)",                                    # 11
            "func c(w: SimWorld) -> float:",                                          # 12
            "\treturn w.baz",                                                         # 13
            "func d(x) -> void:",                                                     # 14
            "\tvar w: SimWorld = x.world if x != null else null",                     # 15
            "\tw.food[0] = 1.0",                                                      # 16 대입
            "\tx.world.tick += 1",                                                    # 17 대입
            "\tw.chronicle.append({})",                                               # 18 고치는 호출
            "\tw.step()",                                                             # 19 진행
            "\tvar c := w.cfg",                                                       # 20
            "\tc.time.day_ticks = 3",                                                 # 21 받은 사전을 고침
            "\tfor e in w.chronicle:",                                                # 22
            "\t\te.text = \"\"",                                                      # 23 받은 사건을 고침
            "\tif w.tick == 0 and w.food[0] >= 1.0:",                                 # 24 비교는 읽기
            "\t\tprint(w.mean_of(w.s_energy), c.time.day_ticks, e.kind)",             # 25 읽기
            "func e(rec: SimRecorder) -> int:",                                       # 26
            "\treturn rec.secret + SimConfig.hidden_helper(1) + SimGrid.TILE_GRASS",  # 27
            "func f() -> void:",                                                      # 28
            "\tvar w := size.x",                                                      # 29
            "\tvar text := SimSnapshot.to_text(lab.world)",                           # 30
            "\tprint(w.abs(), text.length())",                                        # 31
            "func g(w: SimWorld) -> void:",                                           # 32
            "\tw.cfg.get_or_add(\"x\", 1)",                                           # 33 허용 목록 밖(없는 키를 더함)
            "\tw.tiles.encode_u8(0, 3)",                                              # 34 허용 목록 밖(바이트를 씀)
            "\tvar d := w.cfg.time",                                                  # 35
            "\td.call(\"clear\")",                                                    # 36 받은 사전에 허용 목록 밖 호출
            "\tprint(w.chronicle.size(), w.s_genome.duplicate().size(), d.get(\"k\"), w.cfg.has(\"time\"))",  # 37 읽기
        ])
        found = scan_sim_access(src, "panel.gd")
        members = {m for _l, m in found["SimWorld"]}
        for want in ("period_births", "tick_a", "bar", "qux", "kid", "baz", "food", "tick", "chronicle", "step", "cfg"):
            self.assertIn(want, members)
        self.assertNotIn("in_string", members, "문자열 안")
        self.assertNotIn("in_comment", members, "주석 안")
        self.assertNotIn("abs", members, "다른 함수의 w(폭)는 세계가 아님")
        self.assertNotIn("length", members, "세계를 인자로 넘긴 호출의 결과는 세계가 아님")
        self.assertEqual({m for _l, m in found["SimRecorder"]}, {"secret"})
        self.assertIn("SimConfig.hidden_helper", {s for _l, s in found["static"]})
        write_lines = sorted({ln for ln, _w in found["writes"]})
        self.assertEqual(write_lines, [16, 17, 18, 19, 21, 23, 33, 34, 36], found["writes"])
        # 진행 호출은 Experiment·LabMain 만
        drive = "func s(w: SimWorld) -> void:\n\tw.step()\n\tw.drain_events()\n"
        self.assertEqual(scan_sim_access(drive, "experiment.gd")["writes"], [(3, "세계를 진행·변경하는 호출: drain_events()")])
        self.assertEqual(scan_sim_access(drive, "lab_main.gd")["writes"], [(2, "세계를 진행·변경하는 호출: step()")])
        # SIM-API 에서 클래스 이름을 생략한 상수·`*` 머리
        _listed, qualified = sim_api_names()
        self.assertTrue(static_listed("SimGrid.TILE_WATER", qualified))
        self.assertTrue(static_listed("SimBrain.ACT_PLANT", qualified))
        self.assertFalse(static_listed("SimConfig.hidden_helper", qualified))


class TestDocConfigKeys(unittest.TestCase):
    def test_ui_keys_in_docs_exist(self) -> None:
        ui = json.loads((REPO / "config" / "ui.json").read_text(encoding="utf-8"))
        bad = []
        checked = 0
        for doc in ("docs/DESIGN-v0.1.md", "docs/VIEW-API.md", "docs/ANALYSIS.md", "README.md"):
            for span in backticked((REPO / doc).read_text(encoding="utf-8")):
                for m in re.finditer(r"(?<![A-Za-z_0-9.])ui\.([a-z_0-9]+(?:\.[a-z_0-9]+)*)(?![A-Za-z_0-9*])", span):
                    if m.group(1) == "json":
                        continue  # 파일 이름 ui.json
                    node = ui
                    ok = True
                    for part in m.group(1).split("."):
                        if not isinstance(node, dict) or part not in node:
                            ok = False
                            break
                        node = node[part]
                    checked += 1
                    if not ok:
                        bad.append(f"{doc}: ui.{m.group(1)}")
        self.assertGreater(checked, 10)
        self.assertEqual(bad, [], "config/ui.json 에 없는 키를 문서가 가리킴")


class TestProjectSettings(unittest.TestCase):
    def test_user_dir_is_ascii(self) -> None:
        """I06: 프로젝트 이름(한글) 대신 영문 사용자 폴더(`~/.local/share/slime-lab`, `%APPDATA%\\slime-lab`)."""
        text = (REPO / "project.godot").read_text(encoding="utf-8")
        app = re.search(r"^\[application\]\s*$(.*?)(?=^\[|\Z)", text, re.S | re.M)
        self.assertIsNotNone(app, "project.godot 에 [application] 절이 없음")
        body = app.group(1) if app else ""
        self.assertRegex(body, r"(?m)^config/use_custom_user_dir\s*=\s*true\s*$", "사용자 폴더 이름을 따로 정하지 않음")
        m = re.search(r'(?m)^config/custom_user_dir_name\s*=\s*"([^"]*)"\s*$', body)
        self.assertIsNotNone(m, "config/custom_user_dir_name 이 없음")
        name = m.group(1) if m else ""
        self.assertRegex(name, r"^[A-Za-z0-9._-]+$", f"사용자 폴더 이름이 영문·숫자가 아님: {name!r}")


# ───────────────────────── 색 검사(dataviz 검사기와 같은 계산) ─────────────────────────

# Machado·Oliveira·Fernandes(2009) 심도 1.0 색각 이상 모의 행렬(선형 RGB)
MACHADO = {
    "protan": ((0.152286, 1.052583, -0.204868), (0.114503, 0.786281, 0.099216), (-0.003882, -0.048116, 1.051998)),
    "deutan": ((0.367322, 0.860646, -0.227968), (0.280085, 0.672501, 0.047413), (-0.011820, 0.042940, 0.968881)),
}
DARK_L_BAND = (0.48, 0.67)  # 어두운 바탕에서 계열 색의 OKLCH 명도 범위
CHROMA_FLOOR = 0.10         # 이보다 낮으면 회색으로 읽힘
CONTRAST_MIN = 3.0          # 바탕 대비(WCAG, 그림 요소)
CHRONICLE_GROUPS = ("discovery", "building", "farm_lost", "milestone", "extinction")  # `other`(쓰지 않는 묶음)는 뺌
# 문턱은 상수가 아니라 VIEW-API 의 문장에서 읽는다(문서 수치 = 검사 수치). 색을 일부러 바꿨다면 다시 재서 그 문장의 수만 고치면 됨.
# 문서는 소수 한 자리로 반올림해 적으므로 잰 값도 한 자리로 반올림해 견준다.
GRAPH_CLAIM_LINE = "- 색: A = `ui.graph.series_a`"
GRAPH_CLAIM_RE = r"색각 이상 (?:시뮬레이션|모의)[^,\n]*?ΔE ≥ ([0-9.]+), 정상 ΔE ≥ ([0-9.]+)"
CHRONICLE_CLAIM_LINE = "- 띠 색 `ui.chronicle.colors`"
CHRONICLE_CLAIM_RE = r"색각 이상 모의 모든 쌍 ΔE ≥ ([0-9.]+), 빨강·주황\(위험·경고 뜻 색\)은 정상 시각 ΔE ([0-9.]+)"


def _srgb(h: str) -> tuple[float, float, float]:
    h = h.strip().lstrip("#")[:6]
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))  # type: ignore[return-value]


def _lin(h: str) -> tuple[float, float, float]:
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in _srgb(h))  # type: ignore[return-value]


def _oklab(rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    r, g, b = rgb
    l_ = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m_ = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s_ = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)


def _simulate(h: str, kind: str) -> tuple[float, float, float]:
    r, g, b = _lin(h)
    return tuple(min(1.0, max(0.0, row[0] * r + row[1] * g + row[2] * b)) for row in MACHADO[kind])  # type: ignore[return-value]


def delta_e(h1: str, h2: str, kind: str = "") -> float:
    """OKLab 거리 ×100. kind = "protan"·"deutan" 이면 그 색각 이상 모의 뒤, "" 이면 정상 시각."""
    a = _oklab(_simulate(h1, kind) if kind else _lin(h1))
    b = _oklab(_simulate(h2, kind) if kind else _lin(h2))
    return 100.0 * math.dist(a, b)


def cvd_delta_e(h1: str, h2: str) -> float:
    return min(delta_e(h1, h2, "protan"), delta_e(h1, h2, "deutan"))


def contrast(h1: str, h2: str) -> float:
    def lum(h: str) -> float:
        r, g, b = _lin(h)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    hi, lo = sorted((lum(h1), lum(h2)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def oklch_lc(h: str) -> tuple[float, float]:
    l_, a, b = _oklab(_lin(h))
    return l_, math.hypot(a, b)


class TestPaletteClaims(unittest.TestCase):
    def setUp(self) -> None:
        self.ui = json.loads((REPO / "config" / "ui.json").read_text(encoding="utf-8"))
        self.bg = str(self.ui["theme"]["background"])
        self.view_api = (REPO / "docs" / "VIEW-API.md").read_text(encoding="utf-8")

    def _claims(self, line_start: str, pattern: str) -> tuple[float, ...]:
        """VIEW-API 에서 line_start 로 시작하는 줄의 수치들."""
        lines = [ln for ln in self.view_api.split("\n") if ln.startswith(line_start)]
        self.assertEqual(len(lines), 1, f"VIEW-API 에 '{line_start}' 줄이 하나가 아님")
        m = re.search(pattern, lines[0] if lines else "")
        self.assertIsNotNone(m, f"VIEW-API '{line_start}' 줄에서 ΔE 수치 문장을 찾지 못함 — 문장을 바꿨다면 이 검사의 정규식도")
        return tuple(float(x) for x in m.groups()) if m else ()

    def _pairs(self, colors: dict[str, str]) -> list[tuple[str, str]]:
        names = list(colors)
        return [(names[i], names[j]) for i in range(len(names)) for j in range(i + 1, len(names))]

    def test_calculation_matches_reference(self) -> None:
        """계산이 dataviz 검사기와 같은지(그 검사기가 낸 값: 흰↔검 대비 21, 같은 색 ΔE 0, 순수 빨강 OKLCH 0.628·0.258,
        4단계 처음 그래프 색 #2aa98a·#d97630·#5b8fe8 의 가장 나쁜 쌍 색각 이상 11.8(녹색맹)·정상 18.4)."""
        self.assertAlmostEqual(contrast("#ffffff", "#000000"), 21.0, places=6)
        self.assertAlmostEqual(delta_e("#2aa98a", "#2aa98a", "deutan"), 0.0, places=9)
        self.assertAlmostEqual(oklch_lc("#ff0000")[0], 0.628, places=3)
        self.assertAlmostEqual(oklch_lc("#ff0000")[1], 0.258, places=3)
        self.assertAlmostEqual(delta_e("#2aa98a", "#d97630", "deutan"), 11.8, places=1)
        self.assertAlmostEqual(delta_e("#2aa98a", "#5b8fe8"), 18.4, places=1)

    def test_graph_series_colors(self) -> None:
        """VIEW-API 그래프 절: A·B·출생 세 색은 바탕 위에서 모든 쌍 색각 이상 ΔE ≥ X·정상 ΔE ≥ Y, 대비 ≥ 3:1, 명도·채도 범위 안."""
        cvd_min, normal_min = self._claims(GRAPH_CLAIM_LINE, GRAPH_CLAIM_RE)
        g = self.ui["graph"]
        colors = {"series_a": str(g["series_a"]), "series_b": str(g["series_b"]), "births": str(g["births"])}
        for name, c in colors.items():
            l_, ch = oklch_lc(c)
            self.assertTrue(DARK_L_BAND[0] <= l_ <= DARK_L_BAND[1], f"graph.{name} {c} 명도 {l_:.3f} 가 범위 밖")
            self.assertGreaterEqual(ch, CHROMA_FLOOR, f"graph.{name} {c} 채도 {ch:.3f}")
            self.assertGreaterEqual(contrast(c, self.bg), CONTRAST_MIN, f"graph.{name} {c} 바탕 대비")
        for a, b in self._pairs(colors):
            cvd = cvd_delta_e(colors[a], colors[b])
            normal = delta_e(colors[a], colors[b])
            self.assertGreaterEqual(round(cvd, 1), cvd_min, f"{a}↔{b} 색각 이상 ΔE {cvd:.2f} < 문서 {cvd_min}")
            self.assertGreaterEqual(round(normal, 1), normal_min, f"{a}↔{b} 정상 시각 ΔE {normal:.2f} < 문서 {normal_min}")

    def test_chronicle_group_colors(self) -> None:
        """VIEW-API 연대기 절: 다섯 묶음(`other` 제외) 모든 쌍 색각 이상 ΔE ≥ X, 밭 잃음(경고)↔멸종(위험) 정상 ΔE ≥ Y, 대비 ≥ 3:1."""
        cvd_min, warn_danger_min = self._claims(CHRONICLE_CLAIM_LINE, CHRONICLE_CLAIM_RE)
        cc = self.ui["chronicle"]["colors"]
        colors = {k: str(cc[k]) for k in CHRONICLE_GROUPS}
        for name, c in colors.items():
            self.assertGreaterEqual(contrast(c, self.bg), CONTRAST_MIN, f"chronicle.colors.{name} {c} 바탕 대비")
        for a, b in self._pairs(colors):
            cvd = cvd_delta_e(colors[a], colors[b])
            self.assertGreaterEqual(round(cvd, 1), cvd_min, f"{a}↔{b} 색각 이상 ΔE {cvd:.2f} < 문서 {cvd_min}")
        wd = delta_e(colors["farm_lost"], colors["extinction"])
        self.assertGreaterEqual(round(wd, 1), warn_danger_min, f"밭 잃음↔멸종 정상 시각 ΔE {wd:.2f} < 문서 {warn_danger_min}")

if __name__ == "__main__":
    unittest.main()
