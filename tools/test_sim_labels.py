#!/usr/bin/env python3
"""설정 키 이름표 검사(unittest, 파이썬 표준 라이브러리만).

  python3 -m unittest discover -s tools -p "test_*.py" -v
  python3 tools/test_sim_labels.py --write      # docs/CONFIG.md 를 config/sim-labels.json 에서 다시 만듦

1. config/sim-defaults.json 의 모든 잎 키(절.키)가 config/sim-labels.json 에 이름·단위·범위·뜻과 함께 있다
   (실험실 고급 설정의 말풍선이 쓰는 한국어 설명 — 키를 더하면 설명도 함께, 없는 키의 설명은 남지 않음).
2. SimConfig.validate 가 막는 범위(scripts/sim/sim_config.gd 의 규칙)는 이름표의 범위 글과 같은 수이고 "(검사)" 가 붙어 있다.
   "(검사)" 는 validate 가 실제로 보는 키에만 붙는다.
3. 절 이름(_sections)이 모든 절에 있고 ParamPanel.SECTION_NAMES(고급 설정 절 머리)와 같다.
4. docs/CONFIG.md 가 이름표에서 만든 글과 글자까지 같다(어긋나면 --write 로 다시 만듦).
5. config/*.json 의 _comment 가 가리키는 docs/*.md 는 실제로 있다(죽은 안내 없음).
"""
from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULTS = REPO / "config" / "sim-defaults.json"
LABELS = REPO / "config" / "sim-labels.json"
PRESETS = REPO / "config" / "presets.json"
SIM_CONFIG = REPO / "scripts" / "sim" / "sim_config.gd"
PARAM_PANEL = REPO / "scripts" / "ui" / "param_panel.gd"
CONFIG_DOC = REPO / "docs" / "CONFIG.md"
FIELDS = ("name", "unit", "range", "help")
NUM_RE = re.compile(r"-?\d+(?:\.\d+)?(?:e-?\d+)?")


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def leaves(defaults: dict) -> list[tuple[str, str, object]]:
    """(절, 키, 기본값) — 파일 순서."""
    out = []
    for sec, body in defaults.items():
        if not isinstance(body, dict):
            continue
        for k, v in body.items():
            out.append((sec, k, v))
    return out


def validate_rules() -> dict[str, tuple[float, float]]:
    """SimConfig.validate 의 [키, 하한, 상한] 규칙."""
    text = SIM_CONFIG.read_text(encoding="utf-8")
    return {m.group(1): (float(m.group(2)), float(m.group(3)))
            for m in re.finditer(r'\["([a-z_]+\.[a-z_]+)",\s*([-0-9.e]+),\s*([-0-9.e]+)\]', text)}


def validate_cfg_keys() -> set[str]:
    """validate 함수 몸통이 cfg.절.키 로 직접 보는 키(관계 검사)."""
    text = SIM_CONFIG.read_text(encoding="utf-8")
    body = text.split("static func validate(", 1)[1].split("\nstatic func ", 1)[0]
    return {f"{a}.{b}" for a, b in re.findall(r"cfg\.([a-z_]+)\.([a-z_]+)", body)}


def panel_section_names() -> dict[str, str]:
    text = PARAM_PANEL.read_text(encoding="utf-8")
    block = text.split("const SECTION_NAMES := {", 1)[1].split("}", 1)[0]
    return dict(re.findall(r'"(\w+)":\s*"([^"]+)"', block))


def cell(text: object) -> str:
    return str(text).replace("|", "\\|").replace("\n", " ")


def render_doc() -> str:
    """docs/CONFIG.md 전체 글."""
    defaults = load(DEFAULTS)
    labels = load(LABELS)
    presets = load(PRESETS)
    sections = labels.get("_sections", {})
    lines = [
        "# 설정 키 — `config/sim-defaults.json`",
        "",
        "<!-- 이 파일은 `python3 tools/test_sim_labels.py --write` 가 config/sim-labels.json 에서 만듭니다."
        " 설명을 고칠 때는 그 파일을 고치고 다시 만드세요(검사가 글자까지 견줌). -->",
        "",
        "시뮬레이션 수치의 단일 기준은 `config/sim-defaults.json` 입니다. 실험 설정 = 기본값 + 예설정(`config/presets.json`)"
        " + 바꾼 값(실험실 파라미터 패널, 헤드리스 실행기 `--set=절.키=값`). 아래 표는 모든 잎 키의 한국어 이름·기본값·단위·범위·뜻입니다."
        " 실험실 **고급 설정**에서 키 이름에 마우스를 올리면 같은 설명이 말풍선으로 나옵니다.",
        "",
        "- **범위**의 \"(검사)\" = `SimConfig.validate` 가 막는 범위(밖이면 실험을 만들지 않고 패널은 그 줄 아래 오류)."
        " 나머지는 뜻이 통하는 범위이며 검사하지 않습니다.",
        "- 규칙의 자세한 식은 [`DESIGN-v0.1.md`](DESIGN-v0.1.md) 1~7절, 발견(`discovery.*`) 임계를 고른 기록은"
        " [`TUNING-fast_civ.md`](TUNING-fast_civ.md).",
        "- 정수 키는 파일에 소수점 없이 적힌 키입니다(패널은 정수만 받음). 배열·글자 키(`seasons.growth`·`brain.policy`)는 패널에서 보기만 합니다.",
        "",
    ]
    by_sec: dict[str, list[tuple[str, str, object]]] = {}
    for sec, k, v in leaves(defaults):
        by_sec.setdefault(sec, []).append((sec, k, v))
    for sec, rows in by_sec.items():
        lines.append(f"## {sections.get(sec, sec)} · `{sec}`")
        lines.append("")
        lines.append("| 키 | 이름 | 기본값 | 단위 | 범위 | 뜻·효과 |")
        lines.append("|---|---|---|---|---|---|")
        for _, k, v in rows:
            key = f"{sec}.{k}"
            lab = labels.get(key, {})
            val = json.dumps(v, ensure_ascii=False)
            lines.append(f"| `{key}` | {cell(lab.get('name', ''))} | `{val}` | {cell(lab.get('unit', ''))} "
                         f"| {cell(lab.get('range', ''))} | {cell(lab.get('help', ''))} |")
        lines.append("")
    lines.append("## 예설정 · `config/presets.json`")
    lines.append("")
    lines.append("| 예설정 | 화면 이름 | 바꾸는 키 |")
    lines.append("|---|---|---|")
    for name, p in presets.items():
        if name.startswith("_") or not isinstance(p, dict):
            continue
        sets = p.get("set", {})
        changed = ", ".join(f"`{k}` = `{json.dumps(v, ensure_ascii=False)}`" for k, v in sets.items()) or "(없음 — 기본값 그대로)"
        lines.append(f"| `{name}` | {cell(p.get('label', name))} | {changed} |")
    lines.append("")
    return "\n".join(lines)


class TestSimLabels(unittest.TestCase):
    def setUp(self) -> None:
        self.defaults = load(DEFAULTS)
        self.labels = load(LABELS)
        self.keys = [f"{s}.{k}" for s, k, _ in leaves(self.defaults)]

    def test_every_leaf_key_has_label(self) -> None:
        self.assertGreater(len(self.keys), 50)
        missing = [k for k in self.keys if k not in self.labels]
        self.assertEqual(missing, [], "config/sim-labels.json 에 없는 설정 키")
        empty = [f"{k}.{f}" for k in self.keys for f in FIELDS if not str(self.labels.get(k, {}).get(f, "")).strip()]
        self.assertEqual(empty, [], "이름표에 빈 칸(이름·단위·범위·뜻)")

    def test_no_stale_labels(self) -> None:
        extra = sorted(k for k in self.labels if not k.startswith("_") and k not in self.keys)
        self.assertEqual(extra, [], "sim-defaults.json 에 없는 키의 이름표")

    def test_validated_ranges_match(self) -> None:
        rules = validate_rules()
        self.assertGreater(len(rules), 10, "validate 규칙을 찾지 못함(정규식 확인)")
        bad = []
        for key, (lo, hi) in rules.items():
            rng = str(self.labels.get(key, {}).get("range", ""))
            nums = [float(x) for x in NUM_RE.findall(rng)]
            if "(검사)" not in rng or lo not in nums or hi not in nums:
                bad.append(f"{key}: [{lo}, {hi}] ≠ \"{rng}\"")
        self.assertEqual(bad, [], "validate 범위와 이름표 범위가 다름")
        checked = set(rules) | validate_cfg_keys()
        claimed = sorted(k for k in self.keys if "(검사)" in str(self.labels.get(k, {}).get("range", "")) and k not in checked)
        self.assertEqual(claimed, [], "validate 가 보지 않는 키에 (검사)")

    def test_section_names(self) -> None:
        sections = self.labels.get("_sections", {})
        secs = [s for s, v in self.defaults.items() if isinstance(v, dict)]
        self.assertEqual(sorted(s for s in secs if s not in sections), [], "_sections 에 없는 절")
        self.assertEqual(panel_section_names(), {s: sections[s] for s in secs}, "ParamPanel.SECTION_NAMES 와 다름")

    def test_config_doc_is_current(self) -> None:
        self.assertTrue(CONFIG_DOC.exists(), "docs/CONFIG.md 없음 — python3 tools/test_sim_labels.py --write")
        self.assertEqual(CONFIG_DOC.read_text(encoding="utf-8"), render_doc(),
                         "docs/CONFIG.md 가 config/sim-labels.json 과 다름 — python3 tools/test_sim_labels.py --write")
        doc = CONFIG_DOC.read_text(encoding="utf-8")
        self.assertEqual([k for k in self.keys if f"`{k}`" not in doc], [], "CONFIG.md 에 없는 키")

    def test_comment_doc_pointers_exist(self) -> None:
        dead = []
        found = 0
        for p in sorted((REPO / "config").glob("*.json")):
            comment = str(load(p).get("_comment", ""))
            for ref in re.findall(r"docs/[\w.\-]+\.md", comment):
                found += 1
                if not (REPO / ref).exists():
                    dead.append(f"{p.name}: {ref}")
        self.assertGreater(found, 0)
        self.assertEqual(dead, [], "_comment 가 없는 문서를 가리킴")


if __name__ == "__main__":
    if "--write" in sys.argv:
        CONFIG_DOC.write_text(render_doc(), encoding="utf-8")
        print(f"썼습니다: {CONFIG_DOC.relative_to(REPO)}")
    else:
        unittest.main()
