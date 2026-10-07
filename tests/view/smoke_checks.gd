extends RefCounted
## 뼈대 검사: 계약(docs/VIEW-API.md)의 클래스·함수가 있고, 화면이 시뮬레이션 역사를 바꾸지 않는다.

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
	lab.set_paused(true)
	for k in 50:
		lab.map_view.before_steps()
		lab.world.step()
		lab.map_view.update_view(0.5)
	var ref: SimWorld = t.make_world({}, 7)
	ref.step_n(50)
	t.check(lab.world.history_hash == ref.history_hash and lab.world.tick == ref.tick, "화면을 거쳐 진행해도 역사 해시가 같음")
	lab.queue_free()
	await t.frames(1)
