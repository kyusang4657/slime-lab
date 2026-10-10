#!/usr/bin/env python3
"""설계 문서의 데이터 형식 표 검사(unittest, 파이썬 표준 라이브러리만).

  python3 -m unittest discover -s tools -p "test_*.py" -v

DESIGN 8.3(스냅숏 형식) 표가 SimSnapshot 이 쓰는 키를, 8.4(결과 파일) 표가 SimRecorder 의 CSV 열을 모두 적는지 본다
(검토 I18·J25 — 예전 8.3 예시는 실제 to_dict 와 거의 모든 키에서 달랐음). 코드에 키·열을 더하면 문서 표도 함께.
"""
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DESIGN = REPO / "docs" / "DESIGN-v0.1.md"
# 스냅숏 맨 위·절 이름처럼 상수 목록에 없는 키(sim_snapshot.gd 의 to_dict 가 직접 씀)
SNAPSHOT_TOP_KEYS = {"format", "version", "app_version", "seed", "tick", "config", "rng", "history_hash",
    "chronicle", "count", "discovery_tick"}
SNAPSHOT_CONSTS = ["MAP_B64", "CIV_B64", "CIV_INT", "CIV_HEX", "CIV_INT_ADDED", "SLIMES_B64", "LINEAGE_B64",
    "STATS_HEX", "STATS_INT"]
RECORDER_CONSTS = ["TIMESERIES_COLUMNS", "CHRONICLE_COLUMNS", "LINEAGE_COLUMNS"]


def consts(rel, names):
    text = (REPO / rel).read_text(encoding="utf-8")
    out = set()
    for n in names:
        m = re.search(rf"const {n}: Array\[String\] = \[(.*?)\]", text, re.S)
        if not m:
            raise AssertionError(f"{rel} 에 const {n} 목록이 없음")
        out.update(re.findall(r'"(\w+)"', m.group(1)))
    return out


def section(head, nxt):
    d = DESIGN.read_text(encoding="utf-8")
    if head not in d or nxt not in d:
        raise AssertionError(f"DESIGN 에 '{head}' 또는 '{nxt}' 절이 없음")
    return d.split(head, 1)[1].split(nxt, 1)[0]


class DesignFormatTest(unittest.TestCase):
    def test_snapshot_keys_listed(self):
        keys = consts("scripts/sim/sim_snapshot.gd", SNAPSHOT_CONSTS) | SNAPSHOT_TOP_KEYS
        listed = set(re.findall(r"`([A-Za-z_]\w*)", section("### 8.3", "### 8.4")))
        self.assertEqual(sorted(keys - listed), [], "DESIGN 8.3 표에 없는 스냅숏 키")

    def test_result_columns_listed(self):
        cols = consts("scripts/sim/sim_recorder.gd", RECORDER_CONSTS)
        listed = set(re.findall(r"`([A-Za-z_]\w*)`", section("### 8.4", "### 8.5")))
        self.assertEqual(sorted(cols - listed), [], "DESIGN 8.4 표에 없는 결과 파일 열")


if __name__ == "__main__":
    unittest.main()
