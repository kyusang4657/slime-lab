#!/usr/bin/env python3
"""설정 키 이름표 검사(unittest, 파이썬 표준 라이브러리만).

  python3 -m unittest discover -s tools -p "test_*.py" -v
  python3 tools/test_sim_labels.py --write      # docs/CONFIG.md 를 config/sim-labels.json 에서 다시 만듦

1. config/sim-defaults.json 의 모든 잎 키(절.키)가 config/sim-labels.json 에 이름·단위·범위·뜻과 함께 있다
   (실험실 고급 설정의 말풍선이 쓰는 한국어 설명 — 키를 더하면 설명도 함께, 없는 키의 설명은 남지 않음).
2. 모든 잎 키의 범위가 SimConfig.validate 의 규칙이고 이름표 범위 글에는 "(검사)" 가 붙어 있다: 수 키는 RULES 의
   [하한, 상한](글에 두 수, "0 초과" = ABOVE), 배열 키는 ARRAY_RULES(원소 수와 원소 범위), 글자 키는 CHOICES(고를 값),
   참·거짓 키는 "true / false". 규칙에만 있는 키(낡은 규칙)도, 기본값·예설정이 규칙 밖인 것도 없다.
3. 절 이름(_sections)이 모든 절에 있고 ParamPanel.SECTION_NAMES(고급 설정 절 머리)와 같다.
4. docs/CONFIG.md 가 이름표에서 만든 글과 글자까지 같다(어긋나면 --write 로 다시 만듦).
5. config/*.json 의 _comment 가 가리키는 docs/*.md 는 실제로 있다(죽은 안내 없음).
6. 멸종 쪽으로 맞춘 스트레스 예설정(harsh_winter)은 화면 이름과 _comment 가 그렇다고 적는다(잰 씨앗 결과 — 검토 J22).
   예설정 표(CONFIG.md)의 "결과·메모" 열은 예설정의 _comment 다.
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


def _sim_config_text() -> str:
    return SIM_CONFIG.read_text(encoding="utf-8")


def _consts(text: str) -> dict[str, str]:
    """sim_config.gd 의 `const 이름 := 수` (규칙 칸이 상수 이름을 쓸 때 풀기)."""
    return dict(re.findall(r"^const ([A-Z_0-9]+) := ([-0-9.e]+)\s*$", text, re.M))


def _block(text: str, name: str) -> str:
    """`const 이름 := [` 또는 `{` 로 시작하는 블록의 몸통."""
    start = text.index(f"const {name} := ")
    close = "\n]" if text[start:].split("\n", 1)[0].rstrip().endswith("[") else "\n}"
    return text[start:text.index(close, start)]


RULE_RE = re.compile(r'\["([a-z_]+\.[a-z_]+)",\s*([-0-9.e]+|[A-Z_]+),\s*([-0-9.e]+|[A-Z_]+)(?:,\s*([A-Z_]+))?\]')


def _rules(name: str) -> dict[str, tuple[float, float, bool, bool]]:
    """규칙 블록: 키 → (하한, 상한, 하한 제외(ABOVE), 두 끝이 정수로 적힘)."""
    text = _sim_config_text()
    consts = _consts(text)
    out = {}
    for m in RULE_RE.finditer(_block(text, name)):
        lo, hi = (consts.get(x, x) for x in (m.group(2), m.group(3)))
        ints = all(re.fullmatch(r"-?\d+", x) for x in (lo, hi))
        out[m.group(1)] = (float(lo), float(hi), m.group(4) == "ABOVE", ints)
    return out


def validate_rules() -> dict[str, tuple[float, float, bool, bool]]:
    """SimConfig.RULES — 수 잎 키의 [키, 하한, 상한(, ABOVE)]."""
    return _rules("RULES")


def array_rules() -> dict[str, tuple[float, float, bool, bool]]:
    """SimConfig.ARRAY_RULES — 배열 잎 키 원소의 [키, 하한, 상한]."""
    return _rules("ARRAY_RULES")


def choices() -> dict[str, list[str]]:
    """SimConfig.CHOICES — 글자 잎 키 → 고를 값."""
    block = _block(_sim_config_text(), "CHOICES")
    return {k: re.findall(r'"([^"]*)"', vals) for k, vals in re.findall(r'"([a-z_]+\.[a-z_]+)":\s*\[([^\]]*)\]', block)}


def in_rule(v: float, rule: tuple[float, float, bool, bool]) -> bool:
    lo, hi, above, _ = rule
    return (v > lo if above else v >= lo) and v <= hi


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
        "- **범위**는 모두 \"(검사)\" = `SimConfig.validate` 가 막는 범위입니다(밖이면 실험을 만들지 않고 패널은 그 줄 아래 오류)."
        " 규칙은 `scripts/sim/sim_config.gd` 의 `RULES`·`ARRAY_RULES`·`CHOICES` 와 관계 검사(크기·감지 초기값, 해 뜨고 지는 시간,"
        " 수명 흔들림)이고 `tools/test_sim_labels.py` 가 이 표의 범위 글과 대조합니다. \"0 초과\" 는 0 을 뺀 범위(나눗수로 쓰이는 값).",
        "- 규칙의 자세한 식은 [`DESIGN-v0.1.md`](DESIGN-v0.1.md) 1~7절, 발견(`discovery.*`) 임계를 고른 기록은"
        " [`TUNING-fast_civ.md`](TUNING-fast_civ.md).",
        "- 정수 키는 파일에 소수점 없이 적힌 키입니다(소수는 거부 — 검사, 패널도 정수만 받음). 틱 단위 키의 상한 1e9 ="
        " `SimConfig.TICK_MAX`(틱 값을 32비트 정수 배열에 담음). 배열·글자 키(`seasons.growth`·`brain.policy`)는 패널에서 보기만 합니다.",
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
    lines.append("| 예설정 | 화면 이름 | 바꾸는 키 | 결과·메모 |")
    lines.append("|---|---|---|---|")
    for name, p in presets.items():
        if name.startswith("_") or not isinstance(p, dict):
            continue
        sets = p.get("set", {})
        changed = ", ".join(f"`{k}` = `{json.dumps(v, ensure_ascii=False)}`" for k, v in sets.items()) or "(없음 — 기본값 그대로)"
        lines.append(f"| `{name}` | {cell(p.get('label', name))} | {changed} | {cell(p.get('_comment', '—'))} |")
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

    def test_every_range_is_checked(self) -> None:
        rules, arrays, chs = validate_rules(), array_rules(), choices()
        self.assertGreater(len(rules), 50, "validate 규칙을 찾지 못함(정규식 확인)")
        self.assertEqual(sorted(k for k in self.keys if "(검사)" not in str(self.labels.get(k, {}).get("range", ""))), [],
                         "범위가 검사되지 않는 키(이름표에 (검사) 없음)")
        bad = []
        for sec, k, v in leaves(self.defaults):
            key = f"{sec}.{k}"
            rng = str(self.labels.get(key, {}).get("range", ""))
            nums = [float(x) for x in NUM_RE.findall(rng)]
            if isinstance(v, bool):
                if rng != "true / false (검사)":
                    bad.append(f"{key}: 참·거짓 키 범위는 \"true / false (검사)\" ≠ \"{rng}\"")
            elif isinstance(v, (int, float)):
                if key not in rules:
                    bad.append(f"{key}: SimConfig.RULES 에 없음")
                    continue
                lo, hi, above, ints = rules[key]
                if lo not in nums or hi not in nums or ("초과" in rng) != above:
                    bad.append(f"{key}: [{lo}, {hi}{' 초과' if above else ''}] ≠ \"{rng}\"")
                if isinstance(v, int) and not ints:
                    bad.append(f"{key}: 정수 키의 규칙 끝값이 정수가 아님")
            elif isinstance(v, list):
                if key not in arrays:
                    bad.append(f"{key}: SimConfig.ARRAY_RULES 에 없음")
                    continue
                lo, hi, _, _ = arrays[key]
                if lo not in nums or hi not in nums or float(len(v)) not in nums:
                    bad.append(f"{key}: 원소 {len(v)}개 [{lo}, {hi}] ≠ \"{rng}\"")
            elif isinstance(v, str):
                if key not in chs:
                    bad.append(f"{key}: SimConfig.CHOICES 에 없음")
                    continue
                missing = [c for c in chs[key] if f'"{c}"' not in rng]
                if missing or rng.count('"') != 2 * len(chs[key]):
                    bad.append(f"{key}: 고를 값 {chs[key]} ≠ \"{rng}\"")
            else:
                bad.append(f"{key}: 알 수 없는 종류 {type(v).__name__}")
        self.assertEqual(bad, [], "validate 규칙과 이름표 범위가 다름")
        stale = sorted(k for k in list(rules) + list(arrays) + list(chs) if k not in self.keys)
        self.assertEqual(stale, [], "sim-defaults.json 에 없는 키의 규칙")

    def test_defaults_and_presets_inside_rules(self) -> None:
        """기본값과 예설정 값이 규칙 안(정수 키는 정수) — 규칙이 기본 실험을 막지 않게."""
        rules, arrays, chs = validate_rules(), array_rules(), choices()
        flat = {f"{s}.{k}": v for s, k, v in leaves(self.defaults)}
        cases = [("기본", flat)]
        for name, p in load(PRESETS).items():
            if not name.startswith("_") and isinstance(p, dict):
                cases.append((name, {**flat, **p.get("set", {})}))
        bad = []
        for name, vals in cases:
            for key, v in vals.items():
                if key in rules and not isinstance(v, bool):
                    if not in_rule(float(v), rules[key]) or (isinstance(flat[key], int) and float(v) != int(v)):
                        bad.append(f"{name}: {key} = {v}")
                elif key in arrays and not all(in_rule(float(x), arrays[key]) for x in v):
                    bad.append(f"{name}: {key} = {v}")
                elif key in chs and v not in chs[key]:
                    bad.append(f"{name}: {key} = {v}")
        self.assertEqual(bad, [], "규칙 밖인 기본값·예설정 값")

    def test_rule_parser_reads_forms(self) -> None:
        """규칙 정규식이 상수 이름·ABOVE·지수 표기를 읽는다(정규식이 낡아 규칙을 놓치면 대조가 비게 됨)."""
        rules = validate_rules()
        self.assertEqual(rules.get("map.width"), (8.0, 1024.0, False, True))
        self.assertEqual(rules.get("plants.max_food"), (0.0, 1e9, True, False))
        self.assertEqual(rules.get("life.max_age", (0, 0))[1], 1e9, "TICK_MAX 상수를 풂")
        self.assertEqual(choices().get("brain.policy"), ["sample", "argmax"])
        self.assertEqual(array_rules().get("seasons.growth", (0, 0))[:2], (0.0, 100.0))

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

    def test_stress_preset_is_marked(self) -> None:
        """harsh_winter 는 잰 씨앗 모두 멸종하는 조건 — 실험실 목록 이름과 _comment 가 그렇게 적는다(예전엔 '혹독한 겨울' 뿐)."""
        hw = load(PRESETS).get("harsh_winter", {})
        self.assertIn("멸종", str(hw.get("label", "")), "harsh_winter 화면 이름에 멸종 조건 표시")
        comment = str(hw.get("_comment", ""))
        self.assertIn("멸종", comment)
        self.assertRegex(comment, r"씨앗 1~\d+", "잰 씨앗 범위와 결과")

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
