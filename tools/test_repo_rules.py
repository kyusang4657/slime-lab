#!/usr/bin/env python3
"""저장소 규칙 검사(unittest, 파이썬 표준 라이브러리만).

  python3 -m unittest discover -s tools -p "test_*.py" -v

1. `assets/` 아래 모든 파일(가져오기 부속 `.import` 제외)이 CREDITS.md 에 적혀 있다(출처 원칙).
2. 화면 코드(scripts/view, scripts/ui)가 `world.<이름>`·`_world.<이름>` 으로 쓰는 세계 멤버는 모두
   docs/SIM-API.md 에 있다(C#/GDExtension 으로 바꿔 끼울 경계).
3. 문서(DESIGN·VIEW-API·ANALYSIS)에 백틱으로 적은 `ui.절.키` 는 config/ui.json 에 실제로 있다(키 이름이 낡지 않게).
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


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


class TestSimApiBoundary(unittest.TestCase):
    def test_view_uses_only_listed_world_members(self) -> None:
        api = (REPO / "docs" / "SIM-API.md").read_text(encoding="utf-8")
        listed: set[str] = set()
        for span in backticked(api):
            listed.update(re.findall(r"[A-Za-z_][A-Za-z_0-9]*", span))
        used: dict[str, set[str]] = {}
        for d in ("scripts/view", "scripts/ui"):
            for f in sorted((REPO / d).glob("*.gd")):
                for name in re.findall(r"(?<![A-Za-z_0-9.])_?world\.([A-Za-z_][A-Za-z_0-9]*)", f.read_text(encoding="utf-8")):
                    used.setdefault(name, set()).add(f.name)
        self.assertTrue(used, "화면 코드에서 세계 멤버를 하나도 찾지 못함(검사 정규식 확인)")
        unlisted = {k: sorted(v) for k, v in used.items() if k not in listed}
        self.assertEqual(unlisted, {}, "docs/SIM-API.md 에 없는 세계 멤버를 화면이 씀")


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


if __name__ == "__main__":
    unittest.main()
