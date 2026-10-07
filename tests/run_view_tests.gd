extends SceneTree
## 화면 구성 요소 검사(헤드리스):  godot --headless --path . --script res://tests/run_view_tests.gd
## tests/view/*_checks.gd 를 모두 불러 run(self) 를 부른다. 모듈은 check(조건, 설명), root, make_world(), frames() 를 쓴다.
## 선택 인자: --only=모듈이름(쉼표, 예: map_checks)

const DIR := "res://tests/view"

var _pass := 0
var _fail := 0
var _report: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  실패: " + what)


func make_world(sets: Dictionary = {}, seed_value: int = 1, preset: String = "default") -> SimWorld:
	var b := SimConfig.build(preset, sets)
	if b.error != "":
		printerr("  설정 오류: " + b.error)
		return null
	var w := SimWorld.new()
	var e := w.setup(b.config, seed_value)
	if e != "":
		printerr("  세계 만들기 실패: " + e)
	return w


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var only := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	var files := Array(DirAccess.get_files_at(DIR))
	files.sort()
	for f in files:
		if not f.ends_with("_checks.gd"):
			continue
		var name: String = f.get_basename()
		if not only.is_empty() and not only.has(name):
			continue
		var before_fail := _fail
		var before := _pass + _fail
		var t0 := Time.get_ticks_msec()
		var scr = load(DIR.path_join(f))
		if scr == null or not scr.can_instantiate():
			_fail += 1
			printerr("  실패: %s 를 불러올 수 없음(문법 오류)" % name)
			_report.append("FAIL %s (불러오기 실패)" % name)
			continue
		var mod = scr.new()
		await mod.run(self)
		if _pass + _fail == before:
			_fail += 1
			printerr("  실패: %s 가 검사를 하나도 하지 않음(스크립트 오류?)" % name)
		_report.append("%s %s (%.1fs)" % ["PASS" if _fail == before_fail else "FAIL", name, float(Time.get_ticks_msec() - t0) / 1000.0])
	print("\n".join(_report))
	print("RESULT: %d passed, %d failed (view)" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
