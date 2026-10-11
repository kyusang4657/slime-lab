#!/usr/bin/env python3
"""설계 문서의 데이터 형식 표 검사(unittest, 파이썬 표준 라이브러리만).

  python3 -m unittest discover -s tools -p "test_*.py" -v

DESIGN-v0.1 8.3(스냅숏 형식) 표가 SimSnapshot 이 쓰는 키를, 8.4(결과 파일) 표가 SimRecorder 의 CSV 열을 모두 적는지 본다
(검토 I18·J25 — 예전 8.3 예시는 실제 to_dict 와 거의 모든 키에서 달랐음). 코드에 키·열을 더하면 문서 표도 함께.
v0.2 에서 더한 것(DESIGN-v0.2 14.1 범위 9)은 DESIGN-v0.2 9.1(스냅숏 키 — sim_snapshot.gd 의 *_ADDED 상수)·9.3(timeseries.csv 새 열)·
9.4(lineage.csv 새 열)에 있어야 하고, CSV 의 새 열은 v0.1 열 뒤에 그 표의 순서 그대로 붙어야 한다(표가 단계마다 길어지므로 코드의
새 열 = 표 순서의 앞부분). 구현을 마친 단계(IMPLEMENTED_STAGE)까지의 열·스냅숏 키는 표 그대로 코드에 모두 있어야 하고 그 뒤 단계의
것은 없어야 한다(단계마다 열·키를 확정 — DESIGN-v0.2 14.2 범위 7). summary.json 의 키(SimRecorder.summary·실행기의 extra)는
DESIGN-v0.1 8.4 의 summary.json 줄이나 DESIGN-v0.2 9.5 에 적혀 있어야 한다.
"""
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DESIGN = REPO / "docs" / "DESIGN-v0.1.md"
DESIGN_V02 = REPO / "docs" / "DESIGN-v0.2.md"
SNAPSHOT = "scripts/sim/sim_snapshot.gd"
RECORDER = "scripts/sim/sim_recorder.gd"
# 스냅숏 맨 위·절 이름처럼 상수 목록에 없는 키(sim_snapshot.gd 의 to_dict 가 직접 씀)
SNAPSHOT_TOP_KEYS = {"format", "version", "app_version", "seed", "tick", "config", "rng", "history_hash",
    "chronicle", "count", "discovery_tick"}
SNAPSHOT_CONSTS = ["MAP_B64", "CIV_B64", "CIV_INT", "CIV_HEX", "CIV_INT_ADDED", "SLIMES_B64", "LINEAGE_B64",
    "STATS_HEX", "STATS_INT"]
# v0.2 에서 더한 스냅숏 키 상수(DESIGN-v0.2 9.1 의 '키 목록 상수' — 단계마다 이 목록에 더함)
SNAPSHOT_CONSTS_V02 = ["SLIMES_B64_ADDED", "LINEAGE_B64_ADDED", "STATS_B64_ADDED", "STATS_HEX_ADDED", "STATS_INT_ADDED"]
# *_ADDED 가운데 스냅숏 키가 아닌 것(설정 키·절 이름 — 옛 설정 채우기)과 v0.1 판의 것
NOT_SNAPSHOT_ADDED = {"CONFIG_KEYS_ADDED", "SECTIONS_ADDED", "CIV_INT_ADDED"}
RECORDER_CONSTS = ["TIMESERIES_COLUMNS", "CHRONICLE_COLUMNS", "LINEAGE_COLUMNS", "ACT_COLUMNS", "EFF_COLUMNS"]
# v0.1 의 열 수(DESIGN-v0.1 8.4 — v0.2 의 열은 이 뒤에 붙음, DESIGN-v0.2 9.3·9.4)
V01_TIMESERIES_COUNT = 22
V01_LINEAGE_COUNT = 11
# 구현을 마친 v0.2 단계: 이 단계까지 DESIGN-v0.2 9.1·9.3·9.4 표에 적은 키·열은 코드에 모두 있고, 그 뒤 단계의 것은 없다(단계를 마치면 올림)
IMPLEMENTED_STAGE = 1
# 9.1 표의 절 → 그 절의 v0.2 키 상수(sim_snapshot.gd). 표의 절이 여기 없으면 그 절의 키는 아직 구현 전이어야 함
SECTION_CONSTS = {"slimes": ["SLIMES_B64_ADDED"], "lineage": ["LINEAGE_B64_ADDED"],
                  "stats": ["STATS_B64_ADDED", "STATS_HEX_ADDED", "STATS_INT_ADDED"]}
# summary.json 의 키를 쓰는 곳: (파일, 사전 글의 시작 줄) — SimRecorder.summary 의 d 와 실행기의 extra
SUMMARY_SOURCES = [(RECORDER, "\tvar d := {"), ("tests/run_experiment.gd", "\tvar extra := {")]


def const_list(rel, name):
    """`const 이름: Array[String] = [...]` 의 글자들(적힌 순서)."""
    text = (REPO / rel).read_text(encoding="utf-8")
    m = re.search(rf"const {name}: Array\[String\] = \[(.*?)\]", text, re.S)
    if not m:
        raise AssertionError(f"{rel} 에 const {name} 목록이 없음")
    return re.findall(r'"(\w+)"', m.group(1))


def consts(rel, names):
    out = set()
    for n in names:
        out.update(const_list(rel, n))
    return out


def section(head, nxt, doc=DESIGN):
    d = doc.read_text(encoding="utf-8")
    if head not in d or nxt not in d:
        raise AssertionError(f"{doc.name} 에 '{head}' 또는 '{nxt}' 절이 없음")
    return d.split(head, 1)[1].split(nxt, 1)[0]


def ticked(text):
    """백틱으로 시작하는 이름들(적힌 순서, 겹침 포함)."""
    return re.findall(r"`([A-Za-z_]\w*)", text)


def v02_timeseries_staged():
    """DESIGN-v0.2 9.3 표의 (단계, 열 이름)(표 순서 — '| 단계 | 열 | 뜻 |' 줄의 첫째·둘째 칸)."""
    out = []
    for line in section("### 9.3", "### 9.4", DESIGN_V02).splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 3 and re.fullmatch(r"\d+", cells[0]):
            out.extend((int(cells[0]), n) for n in re.findall(r"`([A-Za-z_]\w*)`", cells[1]))
    return out


def v02_timeseries_order():
    """DESIGN-v0.2 9.3 표의 열 이름(표 순서)."""
    return [n for _, n in v02_timeseries_staged()]


def v02_lineage_staged():
    """DESIGN-v0.2 9.4 첫 문단의 (단계, 열 이름): `eta`(1 — …)·`cparent`·`tribe`(3) 처럼 이름 묶음 뒤 괄호의 첫 수가 단계."""
    para = section("### 9.4", "### 9.5", DESIGN_V02).strip().split("\n\n", 1)[0]
    out = []
    for m in re.finditer(r"((?:`[A-Za-z_]\w*`·?)+)\((\d+)", para):
        out.extend((int(m.group(2)), n) for n in re.findall(r"`([A-Za-z_]\w*)`", m.group(1)))
    return out


def v02_lineage_order():
    """DESIGN-v0.2 9.4 의 새 열 이름(첫 문단의 백틱 순서)."""
    para = section("### 9.4", "### 9.5", DESIGN_V02).strip().split("\n\n", 1)[0]
    return re.findall(r"`([A-Za-z_]\w*)`", para)


def v02_snapshot_staged():
    """DESIGN-v0.2 9.1 표의 (절, 단계, 키) — '| 절 | 키 | 꼴 | 길이 | 단계 | 옛 파일 |' 줄(절 칸이 비면 위 줄의 절)."""
    out = []
    sec = ""
    for line in section("### 9.1", "### 9.2", DESIGN_V02).splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 6 or not re.fullmatch(r"\d+", cells[4]):
            continue
        m = re.fullmatch(r"`(\w+)`", cells[0])
        if m:
            sec = m.group(1)
        out.extend((sec, int(cells[4]), k) for k in re.findall(r"`([A-Za-z_]\w*)`", cells[1]))
    return out


def dict_keys(rel, start):
    """GDScript 사전 글(start 끝의 '{' 부터 짝이 맞는 '}' 까지 — 안의 괄호·사전은 건너뜀)의 맨 바깥 `이름 =` 키들."""
    text = (REPO / rel).read_text(encoding="utf-8")
    if start not in text:
        raise AssertionError(f"{rel} 에 '{start.strip()}' 가 없음")
    rest = text.split(start, 1)[1]
    depth, top = 0, []
    for ch in rest:
        if ch in "{[(":
            depth += 1
        elif ch in "}])":
            if depth == 0:
                break
            depth -= 1
        top.append(ch if depth == 0 else " ")
    return re.findall(r"(?:^|[,\s])([A-Za-z_]\w*) = ", "".join(top))


class DesignFormatTest(unittest.TestCase):
    def test_snapshot_keys_listed(self):
        keys = consts(SNAPSHOT, SNAPSHOT_CONSTS) | SNAPSHOT_TOP_KEYS
        listed = set(ticked(section("### 8.3", "### 8.4")))
        self.assertEqual(sorted(keys - listed), [], "DESIGN 8.3 표에 없는 스냅숏 키")

    def test_v02_snapshot_keys_listed(self):
        text = (REPO / SNAPSHOT).read_text(encoding="utf-8")
        added = set(re.findall(r"const (\w+_ADDED): Array\[String\]", text)) - NOT_SNAPSHOT_ADDED
        self.assertEqual(sorted(added - set(SNAPSHOT_CONSTS_V02)), [], "SNAPSHOT_CONSTS_V02 에 없는 v0.2 키 상수(이 파일에 더할 것)")
        table = section("### 9.1", "### 9.2", DESIGN_V02)
        keys = consts(SNAPSHOT, SNAPSHOT_CONSTS_V02)
        self.assertGreater(len(keys), 0)
        self.assertEqual(sorted(keys - set(ticked(table))), [], "DESIGN-v0.2 9.1 표에 없는 v0.2 스냅숏 키")
        for name in SNAPSHOT_CONSTS_V02:
            self.assertIn(f"`{name}`", table, "DESIGN-v0.2 9.1 의 키 목록 상수에 없음")

    def test_result_columns_listed(self):
        ts = const_list(RECORDER, "TIMESERIES_COLUMNS")
        ln = const_list(RECORDER, "LINEAGE_COLUMNS")
        v01 = set(ts[:V01_TIMESERIES_COUNT]) | set(ln[:V01_LINEAGE_COUNT]) | set(const_list(RECORDER, "CHRONICLE_COLUMNS"))
        listed = set(re.findall(r"`([A-Za-z_]\w*)`", section("### 8.4", "### 8.5")))
        self.assertEqual(sorted(v01 - listed), [], "DESIGN 8.4 표에 없는 결과 파일 열")
        v02 = set(v02_timeseries_order()) | set(v02_lineage_order())
        extra = consts(RECORDER, RECORDER_CONSTS) - v01
        self.assertEqual(sorted(extra - v02), [], "DESIGN-v0.2 9.3·9.4 에 없는 v0.2 결과 파일 열")

    def test_v02_columns_appended_in_table_order(self):
        ts = const_list(RECORDER, "TIMESERIES_COLUMNS")
        ln = const_list(RECORDER, "LINEAGE_COLUMNS")
        want_ts = v02_timeseries_order()
        want_ln = v02_lineage_order()
        self.assertGreater(len(want_ts), 16, "DESIGN-v0.2 9.3 표를 읽지 못함")
        self.assertEqual(want_ln[:1], ["eaten"], "DESIGN-v0.2 9.4 의 첫 열")
        extra_ts = ts[V01_TIMESERIES_COUNT:]
        extra_ln = ln[V01_LINEAGE_COUNT:]
        self.assertEqual(extra_ts, want_ts[:len(extra_ts)], "timeseries.csv 의 v0.2 열 = DESIGN-v0.2 9.3 표 순서의 앞부분")
        self.assertEqual(extra_ln, want_ln[:len(extra_ln)], "lineage.csv 의 v0.2 열 = DESIGN-v0.2 9.4 순서의 앞부분")
        self.assertEqual(const_list(RECORDER, "ACT_COLUMNS") + const_list(RECORDER, "EFF_COLUMNS"), extra_ts[:16],
                         "0단계 열 = ACT_COLUMNS + EFF_COLUMNS")


    def test_implemented_stage_complete(self):
        """구현을 마친 단계(IMPLEMENTED_STAGE)까지의 표 열·키 = 코드(순서까지), 그 뒤 단계의 것은 코드에 없음."""
        ts = const_list(RECORDER, "TIMESERIES_COLUMNS")[V01_TIMESERIES_COUNT:]
        ln = const_list(RECORDER, "LINEAGE_COLUMNS")[V01_LINEAGE_COUNT:]
        want_ts = [n for st, n in v02_timeseries_staged() if st <= IMPLEMENTED_STAGE]
        want_ln = [n for st, n in v02_lineage_staged() if st <= IMPLEMENTED_STAGE]
        self.assertEqual([n for _, n in v02_lineage_staged()], v02_lineage_order(), "DESIGN-v0.2 9.4 의 열마다 (단계)가 있음")
        self.assertEqual(ts, want_ts, f"timeseries.csv 의 v0.2 열 = DESIGN-v0.2 9.3 의 {IMPLEMENTED_STAGE}단계까지 열")
        self.assertEqual(ln, want_ln, f"lineage.csv 의 v0.2 열 = DESIGN-v0.2 9.4 의 {IMPLEMENTED_STAGE}단계까지 열")
        rows = v02_snapshot_staged()
        self.assertGreater(len(rows), 30, "DESIGN-v0.2 9.1 표를 읽지 못함")
        for sec in sorted({s for s, _, _ in rows}):
            want = sorted(k for s, st, k in rows if s == sec and st <= IMPLEMENTED_STAGE)
            have = sorted(consts(SNAPSHOT, SECTION_CONSTS.get(sec, [])))
            self.assertEqual(have, want, f"스냅숏 {sec} 의 v0.2 키 = DESIGN-v0.2 9.1 의 {IMPLEMENTED_STAGE}단계까지 키")

    def test_summary_keys_listed(self):
        """summary.json 의 키(SimRecorder.summary 의 사전·실행기의 extra)는 DESIGN-v0.1 8.4 의 summary.json 줄이나 DESIGN-v0.2 9.5 에."""
        keys = []
        for rel, start in SUMMARY_SOURCES:
            keys += dict_keys(rel, start)
        self.assertIn("timeseries_columns", keys)
        self.assertIn("end_reason", keys)
        v01 = section("### 8.4", "### 8.5").split("**`summary.json`**", 1)[1].split("\n\n", 1)[0]
        listed = set(ticked(v01)) | set(ticked(section("### 9.5", "## 10.", DESIGN_V02)))
        self.assertEqual(sorted(set(keys) - listed), [], "DESIGN-v0.1 8.4·DESIGN-v0.2 9.5 에 없는 summary.json 키")


if __name__ == "__main__":
    unittest.main()
