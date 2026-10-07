extends RefCounted
## MapView 검사(헤드리스). tests/run_view_tests.gd 가 불러 run(t) 을 부른다.
## 메시·MultiMesh 개수·인스턴스 위치·선택 고리·고르기(광선)·카메라 제한·입력·결정성·시간을 본다(픽셀은 tests/map_capture.gd).

## 검사용 SubViewport 크기(고르기 광선이 이 크기로 계산됨).
const VP_SIZE := Vector2i(800, 450)
const EPS := 0.0005
## 슬라임 부분 update_view 시간 상한(µs). 목표는 2ms, 느린 CI 를 감안해 넉넉히.
const SLIME_US_LIMIT := 6000.0
const TIMING_FRAMES := 120


func run(t) -> void:
	var sv := SubViewport.new()
	sv.size = VP_SIZE
	sv.own_world_3d = true
	t.root.add_child(sv)
	var mv := MapView.new()
	sv.add_child(mv)
	await t.frames(1)

	var w: SimWorld = t.make_world({}, 3)
	mv.bind(w)
	_check_build(t, mv, w)
	await _check_motion(t, mv, w)
	_check_selection_and_pick(t, mv, w)
	await _check_input(t, mv, sv, w)
	_check_camera(t, mv, w)
	_check_light(t, mv, w)
	_check_timing(t, mv)
	_check_buildings(t, mv)
	_check_determinism(t, mv)
	_check_extinct(t, mv)
	sv.queue_free()
	await t.frames(1)


# ── 만들기 ──

func _check_build(t, mv: MapView, w: SimWorld) -> void:
	var n_pass := 0
	var water := -1
	var rock := -1
	for c in w.w * w.h:
		if SimGrid.passable(w.tiles[c]):
			n_pass += 1
		elif w.tiles[c] == SimGrid.TILE_WATER and water == -1:
			water = c
		elif w.tiles[c] == SimGrid.TILE_ROCK and rock == -1:
			rock = c
	var plants: MultiMesh = (mv.get_node("Plants") as MultiMeshInstance3D).multimesh
	t.check(plants.instance_count == n_pass, "식물 인스턴스 = 통과 가능 칸 (%d, %d)" % [plants.instance_count, n_pass])
	var terrain := mv.get_node("Terrain") as MeshInstance3D
	var tm := terrain.mesh as ArrayMesh
	t.check(tm != null and tm.get_surface_count() == 1, "땅은 ArrayMesh 하나·표면 하나")
	if tm != null and tm.get_surface_count() == 1:
		var arr := tm.surface_get_arrays(0)
		var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		t.check(nv >= w.w * w.h * 4, "땅 정점 수 ≥ 칸 × 4 (%d)" % nv)
		var v0: Vector3 = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0]
		t.check(absf(v0.x) < EPS and absf(v0.z) < EPS, "첫 칸 사각형이 (0,0) 모서리에서 시작")
	if water != -1:
		var cw := mv.terrain_tile_color(water)
		t.check(cw.b > cw.r and cw.b > cw.g, "물 칸 색은 파랑 계열 %s" % cw)
	if rock != -1:
		var cr := mv.terrain_tile_color(rock)
		t.check(absf(cr.r - cr.b) < 0.15, "바위 칸 색은 회색 계열 %s" % cr)
	var grass := -1
	for c in w.w * w.h:
		if w.tiles[c] == SimGrid.TILE_GRASS:
			grass = c
			break
	var cg := mv.terrain_tile_color(grass)
	t.check(cg.g > cg.b, "풀밭 칸 색은 초록 계열 %s" % cg)
	var slimes: MultiMesh = (mv.get_node("Slimes") as MultiMeshInstance3D).multimesh
	t.check(slimes.instance_count == w.population(), "묶은 직후 슬라임 인스턴스 = 개체 수")
	t.check(slimes.use_colors, "슬라임 MultiMesh 는 인스턴스 색 사용")
	var st := mv.view_stats()
	var keys_ok := true
	for k in ["slimes", "plants", "stores", "farms", "triangles_estimate"]:
		keys_ok = keys_ok and st.has(k)
	t.check(keys_ok and int(st.slimes) == w.population() and int(st.triangles_estimate) > 0, "view_stats 키와 값")


# ── 움직임(보간) ──

func _check_motion(t, mv: MapView, w: SimWorld) -> void:
	var slimes: MultiMesh = (mv.get_node("Slimes") as MultiMeshInstance3D).multimesh
	var count_ok := true
	var colors_before := PackedInt32Array()
	for c in w.w * w.h:
		colors_before.append(mv.terrain_tile_color(c).to_rgba32())
	for k in 40:
		mv.before_steps()
		w.step()
		mv.update_view(0.3)
		count_ok = count_ok and slimes.instance_count == w.population()
	t.check(count_ok, "진행 중 매 틱 슬라임 인스턴스 = 개체 수")
	var changed := 0
	for c in w.w * w.h:
		if mv.terrain_tile_color(c).to_rgba32() != colors_before[c]:
			changed += 1
	t.check(changed > 0, "틱이 지나면 땅 색이 다시 칠해짐 (바뀐 칸 %d)" % changed)
	# 한 틱 진행하고 이전 칸을 기억해 두었다가 alpha 별 위치 확인
	var px := w.s_x.duplicate()
	var py := w.s_y.duplicate()
	var pid := w.s_id.duplicate()
	mv.before_steps()
	w.step()
	mv.update_view(1.0)
	var occ := {}
	for i in w.population():
		var c := w.s_y[i] * w.w + w.s_x[i]
		occ[c] = int(occ.get(c, 0)) + 1
	var alone_ok := true
	var alone_n := 0
	for i in w.population():
		if int(occ[w.s_y[i] * w.w + w.s_x[i]]) != 1:
			continue
		var p := mv.slime_instance_position(i)
		var ex := (float(w.s_x[i]) + 0.5) * UiConfig.num("map.tile_size")
		var ez := (float(w.s_y[i]) + 0.5) * UiConfig.num("map.tile_size")
		if absf(p.x - ex) > EPS or absf(p.z - ez) > EPS:
			alone_ok = false
		alone_n += 1
	t.check(alone_ok and alone_n > 0, "alpha=1 에서 혼자 있는 개체 %d 마리가 칸 가운데" % alone_n)
	# 겹친 개체는 가운데에서 조금(최대 STACK_MAX 칸) 비켜 남
	var stack_ok := true
	for i in w.population():
		if int(occ[w.s_y[i] * w.w + w.s_x[i]]) < 2:
			continue
		var p := mv.slime_instance_position(i)
		var d := Vector2(p.x - (float(w.s_x[i]) + 0.5), p.z - (float(w.s_y[i]) + 0.5)).length()
		stack_ok = stack_ok and d > EPS and d <= MapView.STACK_MAX + EPS
	t.check(stack_ok, "같은 칸의 개체는 작은 둘레에 나뉘어 놓임")
	# alpha 0.5: 움직인 개체는 두 칸 사이, 위로 뜸
	mv.update_view(0.5)
	var mid_ok := true
	var moved := 0
	var j := 0
	for i in w.population():
		while j < pid.size() and pid[j] < w.s_id[i]:
			j += 1
		if j >= pid.size() or pid[j] != w.s_id[i]:
			continue
		if px[j] == w.s_x[i] and py[j] == w.s_y[i]:
			continue
		if int(occ[w.s_y[i] * w.w + w.s_x[i]]) != 1:
			continue
		moved += 1
		var p := mv.slime_instance_position(i)
		var ex := (float(px[j] + w.s_x[i]) * 0.5 + 0.5)
		var ez := (float(py[j] + w.s_y[i]) * 0.5 + 0.5)
		# alpha 0.5: 늘어남 0(sin 2π·½), 높이 = 바닥 맞춤 + 뜀 높이 × 크기
		var base := -SlimeGeo.slime_mesh().get_aabb().position.y * w.s_size[i]
		var hop := UiConfig.num("slime.hop_height") * w.s_size[i]
		if absf(p.x - ex) > 0.01 or absf(p.z - ez) > 0.01 or absf(p.y - (base + hop)) > 0.01:
			mid_ok = false
	t.check(mid_ok and moved > 0, "alpha=0.5 에서 움직인 개체 %d 마리가 두 칸 가운데·공중" % moved)
	await t.frames(1)


# ── 선택 고리·고르기 ──

func _check_selection_and_pick(t, mv: MapView, w: SimWorld) -> void:
	mv.update_view(1.0)
	var ring := mv.get_node("SelectRing") as MeshInstance3D
	var iso := _isolated_index(w)
	t.check(iso != -1, "다른 개체와 떨어진 개체가 있음")
	if iso == -1:
		return
	var id := w.s_id[iso]
	mv.set_selected(id)
	mv.update_view(1.0)
	var p := mv.slime_instance_position(iso)
	t.check(ring.visible and absf(ring.position.x - p.x) < EPS and absf(ring.position.z - p.z) < EPS, "선택 고리가 개체 아래에")
	mv.update_view(0.5)
	var p2 := mv.slime_instance_position(w.index_of_id(id))
	t.check(absf(ring.position.x - p2.x) < EPS and absf(ring.position.z - p2.z) < EPS, "선택 고리가 보간 위치를 따라감")
	var dead := -1
	for k in w.s_id[w.population() - 1]:
		if w.index_of_id(k) == -1:
			dead = k
			break
	if dead != -1:
		mv.set_selected(dead)
		t.check(not ring.visible, "죽은 개체를 고르면 고리 없음")
	mv.set_selected(-1)
	t.check(not ring.visible, "선택 해제하면 고리 없음")
	# 고르기: 그 개체 중심을 화면으로 투영한 점 → 그 id
	mv.update_view(1.0)
	var cam := mv.get_camera()
	var center_y := SlimeGeo.slime_mesh().get_aabb().size.y * 0.5
	var q := mv.slime_instance_position(iso)
	var sp := cam.unproject_position(Vector3(q.x, center_y, q.z))
	t.check(mv.pick_slime(sp) == id, "고르기: 투영한 화면 점 → 그 개체 (%d)" % id)
	# 아무도 없는 곳 → -1
	var empty := _empty_tile(w)
	if empty != -1:
		var e := Vector3(float(empty % w.w) + 0.5, center_y, float(empty / w.w) + 0.5)
		t.check(mv.pick_slime(cam.unproject_position(e)) == -1, "빈 곳 고르기 → -1")


## 다른 개체와 1.5칸 넘게 떨어지고 화면 가운데 쪽에 있는 개체의 배열 위치.
func _isolated_index(w: SimWorld) -> int:
	var best := -1
	var best_d := INF
	for i in w.population():
		var ok := true
		for k in w.population():
			if k != i and absi(w.s_x[k] - w.s_x[i]) + absi(w.s_y[k] - w.s_y[i]) < 3:
				ok = false
				break
		if not ok:
			continue
		var d := Vector2(w.s_x[i] - w.w / 2, w.s_y[i] - w.h / 2).length()
		if d < best_d:
			best_d = d
			best = i
	return best


func _empty_tile(w: SimWorld) -> int:
	for y in range(w.h / 4, w.h * 3 / 4):
		for x in range(w.w / 4, w.w * 3 / 4):
			var ok := true
			for k in w.population():
				if absi(w.s_x[k] - x) + absi(w.s_y[k] - y) < 3:
					ok = false
					break
			if ok:
				return y * w.w + x
	return -1


# ── 입력(클릭·끌기·휠) ──

func _check_input(t, mv: MapView, sv: SubViewport, w: SimWorld) -> void:
	mv.update_view(1.0)
	var iso := _isolated_index(w)
	if iso == -1:
		t.check(false, "입력 검사용 개체 없음")
		return
	var cam := mv.get_camera()
	var center_y := SlimeGeo.slime_mesh().get_aabb().size.y * 0.5
	var q := mv.slime_instance_position(iso)
	var sp := cam.unproject_position(Vector3(q.x, center_y, q.z))
	var got: Array[int] = []
	var cb := func(id: int) -> void: got.append(id)
	mv.slime_clicked.connect(cb)
	_mouse(sv, MOUSE_BUTTON_LEFT, true, sp)
	_mouse(sv, MOUSE_BUTTON_LEFT, false, sp)
	t.check(got.size() == 1 and got[0] == w.s_id[iso], "왼쪽 클릭 → slime_clicked(그 id) %s" % [got])
	# 끌기: 클릭으로 치지 않고 목표점이 움직임
	got.clear()
	var before: Vector3 = cam.get("target")
	_mouse(sv, MOUSE_BUTTON_LEFT, true, sp)
	var mm := InputEventMouseMotion.new()
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm.position = sp + Vector2(60, 25)
	mm.relative = Vector2(60, 25)
	sv.push_input(mm, true)
	_mouse(sv, MOUSE_BUTTON_LEFT, false, sp + Vector2(60, 25))
	var after: Vector3 = cam.get("target")
	t.check(got.is_empty() and before.distance_to(after) > 0.1, "왼쪽 끌기 = 이동(클릭 아님)")
	# 휠: 가까이 → 거리 줄어듦
	var d0: float = cam.get("distance")
	_mouse(sv, MOUSE_BUTTON_WHEEL_UP, true, Vector2(VP_SIZE) * 0.5)
	t.check(float(cam.get("distance")) < d0, "휠 위 = 확대")
	# 오른쪽 끌기: 방위가 바뀜
	var yaw0: float = cam.get("yaw")
	_mouse(sv, MOUSE_BUTTON_RIGHT, true, sp)
	var rm := InputEventMouseMotion.new()
	rm.button_mask = MOUSE_BUTTON_MASK_RIGHT
	rm.position = sp + Vector2(80, 0)
	rm.relative = Vector2(80, 0)
	sv.push_input(rm, true)
	_mouse(sv, MOUSE_BUTTON_RIGHT, false, sp + Vector2(80, 0))
	t.check(absf(float(cam.get("yaw")) - yaw0) > 0.01, "오른쪽 끌기 = 회전")
	mv.slime_clicked.disconnect(cb)
	await t.frames(1)


func _mouse(sv: SubViewport, button: MouseButton, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	e.factor = 1.0
	sv.push_input(e, true)


# ── 카메라 ──

func _check_camera(t, mv: MapView, w: SimWorld) -> void:
	var cam := mv.get_camera()
	var center := Vector2(VP_SIZE) * 0.5
	for k in 80:
		cam.call("zoom_at", center, 1.0)
	t.check(is_equal_approx(float(cam.get("distance")), UiConfig.num("camera.distance_min")), "확대는 distance_min 에서 멈춤")
	for k in 120:
		cam.call("zoom_at", center, -1.0)
	t.check(is_equal_approx(float(cam.get("distance")), UiConfig.num("camera.distance_max")), "축소는 distance_max 에서 멈춤")
	for k in 50:
		cam.call("rotate_pixels", Vector2(0, 400))
	t.check(float(cam.get("pitch")) <= deg_to_rad(UiConfig.num("camera.pitch_max_deg")) + EPS, "고각 위 제한")
	for k in 50:
		cam.call("rotate_pixels", Vector2(0, -400))
	t.check(float(cam.get("pitch")) >= deg_to_rad(UiConfig.num("camera.pitch_min_deg")) - EPS, "고각 아래 제한")
	for k in 60:
		cam.call("pan_pixels", Vector2(-3000, -3000), float(VP_SIZE.y))
	var tg: Vector3 = cam.get("target")
	t.check(tg.x >= -EPS and tg.x <= float(w.w) + EPS and tg.z >= -EPS and tg.z <= float(w.h) + EPS, "목표점은 지도 안에 머묾 %s" % tg)
	# 묶으면 지도 전체가 보이게 맞춤: 네 모서리가 화면 안
	mv.bind(w)
	var inside := true
	for corner in [Vector3(0, 0, 0), Vector3(w.w, 0, 0), Vector3(w.w, 0, w.h), Vector3(0, 0, w.h)]:
		var s := cam.unproject_position(corner)
		inside = inside and s.x >= -1.0 and s.y >= -1.0 and s.x <= float(VP_SIZE.x) + 1.0 and s.y <= float(VP_SIZE.y) + 1.0
	t.check(inside, "처음에는 지도 전체가 화면에 들어옴")
	# focus_on: 목표가 그 개체로, 너무 멀면 당김
	var i := w.population() / 2
	var id := w.s_id[i]
	mv.focus_on(id)
	var p := mv.slime_instance_position(i)
	tg = cam.get("target")
	t.check(absf(tg.x - p.x) < EPS and absf(tg.z - p.z) < EPS and float(cam.get("distance")) <= UiConfig.num("camera.focus_distance") + EPS, "focus_on 이 카메라를 개체로 옮김")
	# 따라가기: 다른 개체를 고르고 켜면 목표가 그 개체로 수렴
	var k2 := w.population() / 3
	mv.set_selected(w.s_id[k2])
	mv.follow_selected = true
	for f in 80:
		mv.update_view(1.0)
	var p2 := mv.slime_instance_position(k2)
	tg = cam.get("target")
	t.check(Vector2(tg.x - p2.x, tg.z - p2.z).length() < 0.05, "따라가기: 목표가 선택 개체로 수렴")
	mv.follow_selected = false
	mv.set_selected(-1)
	# 화면 갱신 없이 세계만 진행한 뒤 focus_on: 낡은 그린 위치가 아니라 지금 칸 가운데로(통합 때 고침)
	mv.update_view(1.0)
	var drawn := {}
	for k in w.population():
		drawn[w.s_id[k]] = mv.slime_instance_position(k)
	w.step_n(6)
	var fid := -1
	for k in w.population():
		var id_k := w.s_id[k]
		if drawn.has(id_k):
			var d: Vector3 = drawn[id_k]
			if absf(d.x - (float(w.s_x[k]) + 0.5)) >= 0.5 or absf(d.z - (float(w.s_y[k]) + 0.5)) >= 0.5:
				fid = id_k
				break
	t.check(fid >= 0, "6틱 사이 움직인 개체가 있음")
	if fid >= 0:
		var j := w.index_of_id(fid)
		mv.focus_on(fid)
		tg = cam.get("target")
		t.check(absf(tg.x - (float(w.s_x[j]) + 0.5)) < EPS and absf(tg.z - (float(w.s_y[j]) + 0.5)) < EPS,
				"갱신 전 focus_on → 낡은 그린 위치가 아니라 지금 칸 가운데 (%d, %d)" % [w.s_x[j], w.s_y[j]])
	mv.update_view(1.0)


# ── 낮밤 ──

func _check_light(t, mv: MapView, w: SimWorld) -> void:
	mv.update_view(1.0)
	var sun := mv.get_node("Sun") as DirectionalLight3D
	var e := lerpf(UiConfig.num("map.night_light_energy"), UiConfig.num("map.day_light_energy"), w.light)
	t.check(absf(sun.light_energy - e) < 0.001, "해 세기 = 빛 %.2f 에 따른 보간" % w.light)
	var we := mv.get_node("Environment") as WorldEnvironment
	var a := lerpf(UiConfig.num("map.night_ambient"), UiConfig.num("map.day_ambient"), w.light)
	t.check(absf(we.environment.ambient_light_energy - a) < 0.001, "주변광 = 빛에 따른 보간")


# ── 시간 ──

func _check_timing(t, mv: MapView) -> void:
	# 인구 상한(250)만큼 채운 세계
	var w: SimWorld = t.make_world({"population.initial": 250}, 11)
	mv.bind(w)
	var n := w.population()
	var total := 0
	var slime := 0
	var frames := 0
	for k in TIMING_FRAMES:
		if k % 4 == 0:
			mv.before_steps()
			w.step()
		var t0 := Time.get_ticks_usec()
		mv.update_view(float(k % 4) / 4.0)
		total += Time.get_ticks_usec() - t0
		slime += int(mv.view_stats().slime_us)
		frames += 1
	# 식물·땅 갱신 한 번 시간(강제로)
	var st := mv.view_stats()
	var s_avg := float(slime) / float(frames)
	print("  MapView 시간: 슬라임 %d마리 update_view 평균 %.0fµs (슬라임 부분 %.0fµs), 식물 %d개 갱신 %dµs, 땅 색 %d칸 %dµs, 삼각형 추정 %d" % [
		n, float(total) / float(frames), s_avg, int(st.plants), int(st.plant_us), w.w * w.h, int(st.terrain_us), int(st.triangles_estimate)])
	t.check(s_avg < SLIME_US_LIMIT, "슬라임 갱신 평균 %.0fµs < %.0fµs" % [s_avg, SLIME_US_LIMIT])


# ── 건물 ──

func _check_buildings(t, mv: MapView) -> void:
	var w: SimWorld = t.make_world({}, 1, "fast_civ")
	w.step_n(1750)
	mv.bind(w)
	var stores: MultiMesh = (mv.get_node("Stores") as MultiMeshInstance3D).multimesh
	var farms: MultiMesh = (mv.get_node("Farms") as MultiMeshInstance3D).multimesh
	t.check(w.store_tiles.size() > 0 and stores.instance_count == w.store_tiles.size(), "저장고 인스턴스 = 저장고 수 (%d)" % w.store_tiles.size())
	t.check(w.farms.size() > 0 and farms.instance_count == w.farms.size(), "밭 인스턴스 = 밭 수 (%d)" % w.farms.size())
	var ok := true
	for k in 30:
		mv.before_steps()
		w.step()
		mv.update_view(0.5)
		ok = ok and stores.instance_count == w.store_tiles.size() and farms.instance_count == w.farms.size()
	t.check(ok, "진행 중 저장고·밭 수가 계속 맞음 (밭 %d)" % w.farms.size())
	var st := mv.view_stats()
	t.check(int(st.stores) == w.store_tiles.size() and int(st.farms) == w.farms.size(), "view_stats 저장고·밭")
	# 건물 없는 새 세계로 다시 붙이면 앞 세계의 저장고·밭이 남지 않아야 함(통합 때 찾은 버그)
	var fresh: SimWorld = t.make_world({}, 1)
	mv.bind(fresh)
	t.check(fresh.store_tiles.is_empty() and stores.instance_count == 0 and farms.instance_count == 0,
			"건물 없는 세계로 다시 bind → 저장고·밭 인스턴스 0")


# ── 결정성 ──

func _check_determinism(t, mv: MapView) -> void:
	var a: SimWorld = t.make_world({}, 5)
	var b: SimWorld = t.make_world({}, 5)
	mv.bind(a)
	var cam := mv.get_camera()
	for k in 150:
		mv.before_steps()
		a.step()
		if k % 3 == 0:
			a.step()
		mv.update_view(float(k % 5) / 5.0)
		if k % 10 == 0 and a.population() > 0:
			var id := a.s_id[k % a.population()]
			mv.set_selected(id)
			mv.pick_slime(cam.unproject_position(Vector3(a.w * 0.5, 0.2, a.h * 0.5)))
			mv.focus_on(id)
			mv.view_stats()
	b.step_n(a.tick)
	t.check(a.tick == b.tick and a.history_hash == b.history_hash, "화면을 거쳐 진행해도 역사 해시가 같음 (t=%d)" % a.tick)


# ── 멸종·빈 세계 ──

func _check_extinct(t, mv: MapView) -> void:
	var w: SimWorld = t.make_world({}, 2, "no_resources")
	mv.bind(w)
	var guard := 0
	while not w.is_extinct() and guard < 2000:
		mv.before_steps()
		w.step()
		mv.update_view(0.5)
		guard += 1
	mv.update_view(1.0)
	var slimes: MultiMesh = (mv.get_node("Slimes") as MultiMeshInstance3D).multimesh
	var plants: MultiMesh = (mv.get_node("Plants") as MultiMeshInstance3D).multimesh
	t.check(w.is_extinct() and slimes.instance_count == 0, "멸종한 세계: 슬라임 인스턴스 0 (t=%d)" % w.tick)
	t.check(int(mv.view_stats().plants) == 0 and plants.instance_count > 0, "자원 없음: 풀포기는 모두 숨김")
	t.check(mv.pick_slime(Vector2(VP_SIZE) * 0.5) == -1, "멸종한 세계에서 고르기 → -1")
	mv.bind(null)
	mv.update_view(0.5)
	mv.before_steps()
	t.check(mv.pick_slime(Vector2(VP_SIZE) * 0.5) == -1 and int(mv.view_stats().slimes) == 0, "세계 없이(bind(null)) 불러도 안전")
