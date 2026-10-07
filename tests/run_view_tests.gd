extends SceneTree
## 화면 구성 요소 검사(헤드리스):  godot --headless --path . --script res://tests/run_view_tests.gd
## tests/view/*_checks.gd 를 모두 불러 run(self) 를 부른다. 모듈은 check(조건, 설명), root, make_world(), frames(),
## node(부모, 경로), same_state(세계 A, 세계 B) 를 쓴다.
## 모듈은 `const MIN_CHECKS := N` 을 둔다: 검사 수가 그보다 적으면(중간에 스크립트 오류로 함수가 끊김 —
## Godot 4.4 는 오류 난 함수만 멈추고 계속 돌므로) 그 모듈을 실패로 센다. CI 는 로그의 SCRIPT ERROR 도 실패로 본다.
## 선택 인자: --only=모듈이름(쉼표, 예: map_checks), --verbose(통과한 검사도 출력)

const DIR := "res://tests/view"

var _pass := 0
var _fail := 0
var _report: Array[String] = []
var _verbose := false


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		if _verbose:
			print("  ok   " + what)
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


## 자식 노드를 찾는다. 없으면 실패로 세고 null(이름이 바뀐 노드를 건드려 스크립트 오류로 조용히 끊기지 않게 —
## 받은 쪽은 null 이면 돌아간다).
func node(parent: Node, path: String) -> Node:
	var n: Node = parent.get_node_or_null(path) if parent != null else null
	check(n != null, "노드 있음: %s" % path)
	return n


## 두 세계의 상태가 같은지(역사 해시는 hash.every 틱마다만 바뀌므로 그 사이를 보려고 배열을 직접 견줌).
## 같으면 "", 다르면 무엇이 다른지.
func same_state(a: SimWorld, b: SimWorld) -> String:
	if a.tick != b.tick:
		return "틱 %d ≠ %d" % [a.tick, b.tick]
	if a.history_hash != b.history_hash:
		return "역사 해시"
	var diffs: Array[String] = []
	for k in ["s_id", "s_x", "s_y", "s_head", "s_energy", "s_genome", "s_carry", "food", "dropped", "store_food", "farms"]:
		if a.get(k) != b.get(k):
			diffs.append(k)
	if a.chronicle.size() != b.chronicle.size():
		diffs.append("chronicle")
	return ", ".join(diffs)


func _run() -> void:
	var only := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a == "--verbose":
			_verbose = true
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
		var done := _pass + _fail - before
		var want := int((scr as Script).get_script_constant_map().get("MIN_CHECKS", 1))
		if done < maxi(1, want):
			_fail += 1
			printerr("  실패: %s 가 검사를 %d개만 함(최소 %d — 스크립트 오류로 중간에 끊겼나?)" % [name, done, want])
		_report.append("%s %s (검사 %d개, %.1fs)" % ["PASS" if _fail == before_fail else "FAIL", name, done, float(Time.get_ticks_msec() - t0) / 1000.0])
	print("\n".join(_report))
	print("RESULT: %d passed, %d failed (view)" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
