extends SceneTree
## Godot 엔진 라이선스와 제3자 고지를 글 파일 하나로 쓴다(배포판 zip·웹 묶음에 넣음, tools/build_dist.sh 가 부름):
##   godot --headless --path . --script res://tools/godot_license.gd -- --out=build/GODOT-LICENSE.txt
## 내용은 이 실행 파일에 든 엔진에서 읽는다: Engine.get_license_text()(엔진 MIT 전문),
## get_copyright_info()(FreeType 등 구성 요소별 저작권 — 엔진 COPYRIGHT.txt 와 같음), get_license_info()(라이선스 전문).
## Godot 문서 'Complying with licenses' 가 말하는 고지문과 FreeType 문구를 함께 적는다.
## 인자: --out=파일(꼭 필요, 상대 경로는 프로젝트 폴더 기준). 실패하면 종료 코드 1.

const TITLE := "슬라임 인공생명 실험실 — Godot Engine 라이선스와 제3자 고지 / Godot Engine license and third-party notices"
const INTRO := "This software uses Godot Engine (%s), available under the following license:"
## FreeType 라이선스(FTL)가 문서에 넣으라고 하는 문구. %s 는 엔진 저작권 정보의 FreeType 연도.
const FREETYPE_NAME := "The FreeType Project"
const FREETYPE_CREDIT := "Portions of this software are copyright © %s The FreeType Project (www.freetype.org). All rights reserved."
const RULE := "=============================================================================="


func _initialize() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr("--out=".length())
	if out == "":
		printerr("사용법: godot --headless --path . --script res://tools/godot_license.gd -- --out=파일")
		quit(1)
		return
	var text := notice_text()
	var path := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("파일을 쓸 수 없습니다: %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("GODOT-LICENSE: %s (%d바이트, 구성 요소 %d개, 라이선스 %d종)" % [path, text.to_utf8_buffer().size(),
			Engine.get_copyright_info().size(), Engine.get_license_info().size()])
	quit(0)


## 파일 전체 글.
static func notice_text() -> String:
	var lines: PackedStringArray = [TITLE, "", INTRO % Engine.get_version_info()["string"], "",
			Engine.get_license_text().strip_edges(), ""]
	var ft := freetype_years()
	if ft != "":
		lines.append_array([FREETYPE_CREDIT % ft, ""])
	lines.append_array([RULE, "Third-party components (Engine.get_copyright_info)", RULE, ""])
	for c in Engine.get_copyright_info():
		lines.append("Comment: " + String(c["name"]))
		for p in c["parts"]:
			lines.append("Files: " + " ".join(PackedStringArray(p["files"])))
			lines.append("Copyright: " + "\n           ".join(PackedStringArray(p["copyright"])))
			lines.append("License: " + String(p["license"]))
		lines.append("")
	lines.append_array([RULE, "Licenses (Engine.get_license_info)", RULE, ""])
	var info := Engine.get_license_info()
	for k in info:
		lines.append("License: " + String(k))
		lines.append(String(info[k]).strip_edges())
		lines.append("")
	return "\n".join(lines)


## 엔진 저작권 정보에 적힌 FreeType 연도(예 "1996-2023"). 없으면 "".
static func freetype_years() -> String:
	for c in Engine.get_copyright_info():
		if String(c["name"]) != FREETYPE_NAME:
			continue
		for p in c["parts"]:
			for line in p["copyright"]:
				var m := RegEx.create_from_string("^[0-9]{4}(-[0-9]{4})?").search(String(line))
				if m != null:
					return m.get_string()
	return ""
