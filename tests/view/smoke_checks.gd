extends RefCounted
## 뼈대 검사: 계약(docs/VIEW-API.md)의 클래스·함수가 있고, 화면이 시뮬레이션 역사를 바꾸지 않는다.
## 검사 실행기 --only: 없는 모듈 이름(오타)·빈 이름은 아무것도 돌리지 않고 실패(검토 J15).

## 이 모듈이 적어도 하는 검사 수(중간에 스크립트 오류로 끊기면 실행기가 실패로 셈)
const MIN_CHECKS := 23
const DT := 1.0 / 60.0
const RUNNER := "res://tests/run_view_tests.gd"
## 실행기를 따로 띄워 보는 오타 이름(있는 모듈 map_checks 의 오타)
const TYPO := "map_check"

func run(t) -> void:
	for cls in ["SlimeGeo", "MapView", "InfoPanel", "BrainView", "LabMain", "UiConfig"]:
		var found := false
		for g in ProjectSettings.get_global_class_list():
			if g["class"] == cls:
				found = true
		t.check(found, "클래스 %s 가 있음" % cls)
	t.check(UiConfig.num("speed.ticks_per_second_1x") > 0.0, "ui.json 읽기")
	for name in ["slime_mesh", "plant_mesh", "berry_mesh", "storehouse_mesh", "farm_mesh", "ring_mesh"]:
		var m: Mesh = Callable(SlimeGeo, name).call()
		t.check(m != null and m.get_surface_count() > 0, "SlimeGeo.%s 메시" % name)
	# 실험실 장면을 띄워 진행해도 역사 해시가 헤드리스와 같아야 한다
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(2)
	t.check(lab.world != null and lab.map_view != null and lab.info_panel != null, "실험실 구성 요소가 만들어짐")
	var err := lab.new_experiment("default", {}, 7)
	t.check(err == "", "새 실험: " + err)
	# 실제 프레임 진행(advance_frame)으로 해시 검사점(hash.every)을 둘 넘게 — 검사점 사이에서는 해시가 그대로라 증명이 안 됨
	lab.set_process(false)
	lab.set_paused(false)
	lab.set_speed(8)
	var every := int(lab.world.cfg.hash.every)
	var guard := 0
	while lab.world.tick < 2 * every + 1 and guard < 2000:
		lab.advance_frame(DT)
		guard += 1
	var ref: SimWorld = t.make_world({}, 7)
	ref.step_n(lab.world.tick)
	t.check(lab.world.tick > 2 * every and lab.world.history_hash == ref.history_hash,
			"화면 프레임으로 %d틱(검사점 %d 둘 지남) 진행해도 역사 해시가 같음" % [lab.world.tick, every])
	var diff: String = t.same_state(lab.world, ref)
	t.check(diff == "", "끝 틱의 상태(개체·에너지·유전체·먹이·연대기)도 같음 %s" % diff)
	lab.queue_free()
	await t.frames(1)
	_only_arg(t)


## 검사 실행기 --only(검토 J15: 예전엔 오타 난 이름을 조용히 걸러 "RESULT: 0 passed, 0 failed"·종료 코드 0).
func _only_arg(t) -> void:
	var runner = load(RUNNER)
	var names: PackedStringArray = runner.module_names()
	t.check(names.has("map_checks") and names.has("smoke_checks") and not names.has("world_compare"),
			"모듈 목록 = tests/view/*_checks.gd(%d개, 도우미 파일은 빠짐)" % names.size())
	var all: Dictionary = runner.select_modules(names, null)
	t.check(all.error == "" and all.run == names, "--only 없음 → 모두")
	var one: Dictionary = runner.select_modules(names, "map_checks,info_checks")
	t.check(one.error == "" and one.run == PackedStringArray(["info_checks", "map_checks"]), "--only=map_checks,info_checks → 그 둘(목록 순서) %s" % str(one.run))
	var typo: Dictionary = runner.select_modules(names, "info_checks," + TYPO)
	t.check(str(typo.error).contains(TYPO) and (typo.run as PackedStringArray).is_empty(),
			"--only 에 없는 이름이 하나라도 있으면 아무것도 돌리지 않고 오류: %s" % str(typo.error).left(60))
	var empty: Dictionary = runner.select_modules(names, " , ")
	t.check(str(empty.error) != "" and (empty.run as PackedStringArray).is_empty(), "--only= 에 이름이 없으면 오류")
	# 실제로 실행기를 띄워: 오타 이름 → 종료 코드 1, RESULT 에 실패 하나(아무 모듈도 돌지 않으므로 금방 끝남)
	var out: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", RUNNER, "--", "--only=" + TYPO])
	var rc := OS.execute(OS.get_executable_path(), args, out, true)
	var text := "\n".join(PackedStringArray(out))
	t.check(rc == 1 and text.contains("RESULT: 0 passed, 1 failed (view)") and text.contains(TYPO),
			"실행기 --only=%s(오타) → 종료 코드 %d, %s" % [TYPO, rc, "RESULT 줄에 실패 하나" if text.contains("1 failed") else text.right(200)])
