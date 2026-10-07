extends RefCounted
## 뼈대 검사: 계약(docs/VIEW-API.md)의 클래스·함수가 있고, 화면이 시뮬레이션 역사를 바꾸지 않는다.

## 이 모듈이 적어도 하는 검사 수(중간에 스크립트 오류로 끊기면 실행기가 실패로 셈)
const MIN_CHECKS := 17
const DT := 1.0 / 60.0

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
