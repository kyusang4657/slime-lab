extends RefCounted
## MapView 검사(헤드리스). tests/run_view_tests.gd 가 불러 run(t) 을 부른다.
## 메시·MultiMesh 개수·인스턴스 위치·선택 고리·고르기(광선)·카메라 제한·입력·결정성·시간을 본다(픽셀은 tests/map_capture.gd).

## 검사용 SubViewport 크기(고르기 광선이 이 크기로 계산됨).
const VP_SIZE := Vector2i(800, 450)
const EPS := 0.0005
## 슬라임 부분 update_view 시간 상한(µs). 목표는 2ms, 느린 CI 를 감안해 넉넉히.
const SLIME_US_LIMIT := 6000.0
const TIMING_FRAMES := 120
## 이 모듈이 적어도 하는 검사 수(중간에 스크립트 오류로 끊기면 실행기가 실패로 셈)
const MIN_CHECKS := 92
## 틱 경계에서 가만히 있는 개체를 지켜볼 틱 수
const STILL_TICKS := 60
## 저장고 움집 처마 반지름(SlimeGeo.storehouse_mesh 의 가장 넓은 지붕 둘레)
const STORE_EAVE := 0.47
## 큰 지도(설정 최대 거리 95 로는 다 안 보이던 크기)
const BIG_MAPS: Array[Vector2i] = [Vector2i(128, 96), Vector2i(200, 150)]
## map_view.gd 에 남아도 되는 숫자 상수(버퍼 짜임·해시·단위 바꿈·수치 오차·메시 치수). 보기 조정값은 ui.json(검토 I55).
const TECH_CONSTS: Array[String] = ["XF", "XFC", "HASH_A", "HASH_B", "HASH_C", "HASH_MASK", "HASH_DIV", "SALT_JITTER", "SALT_PLANT_X",
	"SALT_PLANT_Z", "SALT_PLANT_YAW", "SALT_PLANT_H", "SALT_PLANT_TINT", "SALT_STACK", "SALT_BREATH", "QUARTER", "BYTE", "OPAQUE",
	"DEFAULT_ASPECT", "SIDE_EPS", "VOLUME_EXP", "RING_OUTER", "DOOR_ORDER"]
## 깊이 고르기 검사: 카메라 거리(가까이, 표시 배율 1), 누를 높이(몸 높이에 대한 비), 큰 개체 크기
const PICK_DIST := 6.0
const PICK_TOP_K := 0.85
const PICK_HEAD_K := 0.95
const BIG_SIZE := 1.6
## ui.json 값을 바꿔 MapView 를 만들어 볼 값: 겹침 둘레(예전 코드 상한 0.42 보다 큼), 그림자 원판 안쪽 고리 반지름·진하기
const BIG_STACK := 0.5
const TRY_DISC_INNER := 0.6
const TRY_DISC_ALPHA := 0.7


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
	_check_tick_interp(t, mv, w)
	_check_plants_occupied(t, mv, w)
	_check_selection_and_pick(t, mv, w)
	_check_overview(t, mv, w)
	await _check_input(t, mv, sv, w)
	_check_camera(t, mv, w)
	_check_fit_and_follow(t, mv, w)
	_check_light(t, mv, w)
	_check_timing(t, mv)
	_check_buildings(t, mv)
	_check_determinism(t, mv)
	_check_big_maps(t, mv)
	_check_pick_depth(t, mv)
	_check_extinct(t, mv)
	_check_ui_tuning(t)
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
	var plants_mi := t.node(mv, "Plants") as MultiMeshInstance3D
	var terrain := t.node(mv, "Terrain") as MeshInstance3D
	var slimes_mi := t.node(mv, "Slimes") as MultiMeshInstance3D
	if plants_mi == null or terrain == null or slimes_mi == null:
		return
	var plants: MultiMesh = plants_mi.multimesh
	t.check(plants.instance_count == n_pass, "식물 인스턴스 = 통과 가능 칸 (%d, %d)" % [plants.instance_count, n_pass])
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
	var slimes: MultiMesh = slimes_mi.multimesh
	t.check(slimes.instance_count == w.population(), "묶은 직후 슬라임 인스턴스 = 개체 수")
	t.check(slimes.use_colors, "슬라임 MultiMesh 는 인스턴스 색 사용")
	var st := mv.view_stats()
	var keys_ok := true
	for k in ["slimes", "plants", "stores", "farms", "triangles_estimate"]:
		keys_ok = keys_ok and st.has(k)
	t.check(keys_ok and int(st.slimes) == w.population() and int(st.triangles_estimate) > 0, "view_stats 키와 값")


# ── 움직임(보간) ──

func _check_motion(t, mv: MapView, w: SimWorld) -> void:
	var slimes_mi := t.node(mv, "Slimes") as MultiMeshInstance3D
	if slimes_mi == null:
		return
	var slimes: MultiMesh = slimes_mi.multimesh
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
	# alpha 0.5: 움직인 개체는 두 칸 사이, 위로 뜸(앞 틱·지금 틱 모두 혼자 있던 개체 — 둘레 자리도 보간하므로)
	var pocc := {}
	for k in px.size():
		var pc := py[k] * w.w + px[k]
		pocc[pc] = int(pocc.get(pc, 0)) + 1
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
		if int(occ[w.s_y[i] * w.w + w.s_x[i]]) != 1 or int(pocc[py[j] * w.w + px[j]]) != 1:
			continue
		moved += 1
		var p := mv.slime_instance_position(i)
		var ex := (float(px[j] + w.s_x[i]) * 0.5 + 0.5)
		var ez := (float(py[j] + w.s_y[i]) * 0.5 + 0.5)
		# alpha 0.5: 늘어남 0(sin 2π·½), 높이 = (바닥 맞춤 + 뜀 높이) × 크기 × 표시 배율(멀리서 키움, 가까이 1)
		var base := -SlimeGeo.slime_mesh().get_aabb().position.y * w.s_size[i] * mv.display_scale()
		var hop := UiConfig.num("slime.hop_height") * w.s_size[i] * mv.display_scale()
		if absf(p.x - ex) > 0.01 or absf(p.z - ez) > 0.01 or absf(p.y - (base + hop)) > 0.01:
			mid_ok = false
	t.check(mid_ok and moved > 0, "alpha=0.5 에서 움직인 개체 %d 마리가 두 칸 가운데·공중" % moved)
	await t.frames(1)


# ── 선택 고리·고르기 ──

func _check_selection_and_pick(t, mv: MapView, w: SimWorld) -> void:
	mv.update_view(1.0)
	var ring := t.node(mv, "SelectRing") as MeshInstance3D
	if ring == null:
		return
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
	var sun := t.node(mv, "Sun") as DirectionalLight3D
	var we := t.node(mv, "Environment") as WorldEnvironment
	if sun == null or we == null:
		return
	var e := lerpf(UiConfig.num("map.night_light_energy"), UiConfig.num("map.day_light_energy"), w.light)
	t.check(absf(sun.light_energy - e) < 0.001, "해 세기 = 빛 %.2f 에 따른 보간" % w.light)
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
	var w: SimWorld = t.make_world({}, 1, "demo_fast")
	w.step_n(1750)
	mv.bind(w)
	var stores_mi := t.node(mv, "Stores") as MultiMeshInstance3D
	var farms_mi := t.node(mv, "Farms") as MultiMeshInstance3D
	if stores_mi == null or farms_mi == null:
		return
	var stores: MultiMesh = stores_mi.multimesh
	var farms: MultiMesh = farms_mi.multimesh
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
	_check_store_doorstep(t, mv, w)
	_check_farm_ground(t, mv, w)
	_check_store_blocked(t, mv)
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


# ── 보기 조정값은 ui.json 에서(검토 I55) ──

func _check_ui_tuning(t) -> void:
	# ① map_view.gd 의 숫자 상수는 기술 상수뿐(겹침·옆면 그늘·그림자 원판·끄덕임 같은 조정값은 ui.json)
	var src := FileAccess.get_file_as_string("res://scripts/view/map_view.gd")
	var re := RegEx.new()
	re.compile("(?m)^const\\s+(\\w+)\\s*:?=\\s*(.+)$")
	var extra := PackedStringArray()
	for m in re.search_all(src):
		if not m.get_string(2).begins_with("preload(") and not TECH_CONSTS.has(m.get_string(1)):
			extra.append(m.get_string(1))
	t.check(src != "" and extra.is_empty(), "map_view.gd 에 보기 조정 상수 없음(ui.json 으로) %s" % [extra])
	# ② slime.stack_offset 을 예전 코드 상한(0.42)보다 크게 바꿔도 그대로 쓰임 — 둘레 반지름 = stack_offset,
	#    stack_ring 을 넘으면 stack_grow 씩 넓히되 stack_offset × stack_max_k 까지
	var slime_sec: Dictionary = UiConfig.data()["slime"]
	var map_sec: Dictionary = UiConfig.data()["map"]
	var keep := [slime_sec["stack_offset"], map_sec["blob_shadow_inner"], map_sec["blob_shadow_inner_alpha"]]
	slime_sec["stack_offset"] = BIG_STACK
	map_sec["blob_shadow_inner"] = TRY_DISC_INNER
	map_sec["blob_shadow_inner_alpha"] = TRY_DISC_ALPHA
	var mv := MapView.new()
	slime_sec["stack_offset"] = keep[0]
	map_sec["blob_shadow_inner"] = keep[1]
	map_sec["blob_shadow_inner_alpha"] = keep[2]
	var w: SimWorld = t.make_world({}, 3)
	mv.bind(w)
	var tile := _empty_tile(w)
	var tl := UiConfig.num("map.tile_size")
	var ring := UiConfig.integer("slime.stack_ring")
	var many := ring + 8
	var radii := []
	for m in [2, many]:
		var xs := PackedInt32Array()
		var ys := PackedInt32Array()
		for k in m:
			xs.append(tile % w.w)
			ys.append(tile / w.w)
		var off: PackedFloat32Array = mv.call("_calc_offsets", xs, ys)
		radii.append(Vector2(off[0], off[1]).length() / tl)
	var want_many := minf(BIG_STACK * (1.0 + UiConfig.num("slime.stack_grow") * float(many - ring)), BIG_STACK * UiConfig.num("slime.stack_max_k"))
	t.check(absf(float(radii[0]) - BIG_STACK) < EPS and absf(float(radii[1]) - want_many) < EPS,
			"stack_offset %.2f 가 잘리지 않음: 2마리 %.3f칸, %d마리 %.3f칸(= %.3f, 고치기 전 0.42 에서 잘림)" % [BIG_STACK, float(radii[0]), many, float(radii[1]), want_many])
	t.check(is_equal_approx(MapView.stack_max(), UiConfig.num("slime.stack_offset") * UiConfig.num("slime.stack_max_k")),
			"겹침 둘레 상한 = stack_offset × stack_max_k")
	# ③ 둥근 그림자 원판: 안쪽 고리 반지름·진하기 = map.blob_shadow_inner·blob_shadow_inner_alpha(바꾼 값이 그대로)
	var sh := mv.get_node_or_null("SlimeShadows") as MultiMeshInstance3D
	var got := Vector2(-1.0, -1.0)
	if sh != null:
		var arr := sh.multimesh.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cl: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		if v.size() > 2:
			got = Vector2(Vector2(v[1].x, v[1].z).length(), cl[1].a)
	t.check(absf(got.x - TRY_DISC_INNER) < EPS and absf(got.y - TRY_DISC_ALPHA) < 0.01,
			"그림자 원판 안쪽 고리 = ui map.blob_shadow_inner·blob_shadow_inner_alpha (%.2f, %.2f)" % [got.x, got.y])
	mv.free()


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
	var slimes_mi := t.node(mv, "Slimes") as MultiMeshInstance3D
	var plants_mi := t.node(mv, "Plants") as MultiMeshInstance3D
	if slimes_mi == null or plants_mi == null:
		return
	var slimes: MultiMesh = slimes_mi.multimesh
	var plants: MultiMesh = plants_mi.multimesh
	t.check(w.is_extinct() and slimes.instance_count == 0, "멸종한 세계: 슬라임 인스턴스 0 (t=%d)" % w.tick)
	t.check(int(mv.view_stats().plants) == 0 and plants.instance_count > 0, "자원 없음: 풀포기는 모두 숨김")
	t.check(mv.pick_slime(Vector2(VP_SIZE) * 0.5) == -1, "멸종한 세계에서 고르기 → -1")
	mv.bind(null)
	mv.update_view(0.5)
	mv.before_steps()
	t.check(mv.pick_slime(Vector2(VP_SIZE) * 0.5) == -1 and int(mv.view_stats().slimes) == 0, "세계 없이(bind(null)) 불러도 안전")


# ── 한 프레임 여러 틱·틱 경계(보간은 마지막 한 틱, 둘레 자리도 보간) ──

## 칸 → 개체 수
func _occupancy(xs: PackedInt32Array, ys: PackedInt32Array, width: int) -> Dictionary:
	var occ := {}
	for i in xs.size():
		var c := ys[i] * width + xs[i]
		occ[c] = int(occ.get(c, 0)) + 1
	return occ


func _check_tick_interp(t, mv: MapView, w: SimWorld) -> void:
	var tl := UiConfig.num("map.tile_size")
	# ① 틱마다 before_steps(LabMain 이 하듯) → 2틱 프레임의 alpha 0 = 한 틱 전 칸(두 틱 전이 아님)
	mv.before_steps()
	w.step()
	var px := w.s_x.duplicate()
	var py := w.s_y.duplicate()
	var pid := w.s_id.duplicate()
	mv.before_steps()
	w.step()
	mv.update_view(0.0)
	var occ := _occupancy(w.s_x, w.s_y, w.w)
	var pocc := _occupancy(px, py, w.w)
	var ok := true
	var n := 0
	var moved := 0
	var j := 0
	for i in w.population():
		while j < pid.size() and pid[j] < w.s_id[i]:
			j += 1
		if j >= pid.size() or pid[j] != w.s_id[i]:
			continue
		if int(occ[w.s_y[i] * w.w + w.s_x[i]]) != 1 or int(pocc[py[j] * w.w + px[j]]) != 1:
			continue
		n += 1
		if px[j] != w.s_x[i] or py[j] != w.s_y[i]:
			moved += 1
		var p := mv.slime_instance_position(i)
		if absf(p.x - (float(px[j]) + 0.5) * tl) > EPS or absf(p.z - (float(py[j]) + 0.5) * tl) > EPS:
			ok = false
	t.check(ok and n > 0 and moved > 0, "한 프레임 2틱: alpha 0 에서 혼자 있는 %d마리(움직인 %d)가 한 틱 전 칸 — 보간은 마지막 한 틱만" % [n, moved])
	# ② 기억을 한 번만 하고 2틱 진행 → 낡은(두 틱 전) 출발점에서 미끄러지지 않고 지금 칸
	mv.update_view(1.0)
	mv.before_steps()
	w.step()
	w.step()
	mv.update_view(0.0)
	occ = _occupancy(w.s_x, w.s_y, w.w)
	ok = true
	n = 0
	for i in w.population():
		if int(occ[w.s_y[i] * w.w + w.s_x[i]]) != 1:
			continue
		n += 1
		var p := mv.slime_instance_position(i)
		if absf(p.x - (float(w.s_x[i]) + 0.5) * tl) > EPS or absf(p.z - (float(w.s_y[i]) + 0.5) * tl) > EPS:
			ok = false
	t.check(ok and n > 0, "기억이 두 틱 낡으면 보간하지 않고 지금 칸(%d마리)" % n)
	# ③ 틱 경계: 칸이 그대로인 개체는 alpha 1(틱 T) → alpha 0(틱 T+1)에서 움직이지 않는다(겹침 둘레 자리도 보간)
	var max_jump := 0.0
	var still := 0
	var stacked := 0
	for k in STILL_TICKS:
		mv.update_view(1.0)
		var drawn := {}
		var tile := {}
		for i in w.population():
			drawn[w.s_id[i]] = mv.slime_instance_position(i)
			tile[w.s_id[i]] = w.s_y[i] * w.w + w.s_x[i]
		var occ_t := _occupancy(w.s_x, w.s_y, w.w)
		mv.before_steps()
		w.step()
		mv.update_view(0.0)
		for i in w.population():
			var id := w.s_id[i]
			var c := w.s_y[i] * w.w + w.s_x[i]
			if not tile.has(id) or int(tile[id]) != c:
				continue
			still += 1
			if int(occ_t.get(c, 0)) > 1:
				stacked += 1
			var a: Vector3 = drawn[id]
			var b := mv.slime_instance_position(i)
			max_jump = maxf(max_jump, Vector2(a.x - b.x, a.z - b.z).length())
	t.check(still > 0 and stacked > 0 and max_jump < EPS,
			"틱 경계에서 칸이 그대로인 개체(%d개체·틱, 겹친 칸 %d)가 튀지 않음(최대 %.4f칸, 고치기 전 0.4칸)" % [still, stacked, max_jump])
	mv.update_view(1.0)


# ── 슬라임이 선 칸의 풀포기는 줄여 몸을 뚫지 않게 ──

func _check_plants_occupied(t, mv: MapView, w: SimWorld) -> void:
	var occ_scale := UiConfig.num("map.plant_occupied_scale")
	var plant_h := SlimeGeo.plant_mesh().get_aabb().size.y
	var slime_h := SlimeGeo.slime_mesh().get_aabb().size.y
	for round_i in 2:
		var px := w.s_x.duplicate()
		var py := w.s_y.duplicate()
		mv.before_steps()
		w.step()
		mv.update_view(1.0)
		var occupied := _occupancy(w.s_x, w.s_y, w.w)
		occupied.merge(_occupancy(px, py, w.w))
		var ok := true
		var shrunk := 0
		var full := 0
		for c in w.w * w.h:
			var ps := mv.plant_scale_at(c)
			if ps.x < 0.0:
				continue
			var want := ps.y * (occ_scale if occupied.has(c) else 1.0)
			if absf(ps.x - want) > EPS:
				ok = false
			if occupied.has(c) and ps.y > 0.0:
				shrunk += 1
			elif ps.y > 0.0:
				full += 1
		t.check(ok and shrunk > 0 and full > 0, "점유 칸의 풀포기만 %.2f 배(줄인 %d, 그대로 %d) — 떠난 칸은 되돌림" % [occ_scale, shrunk, full])
		# 줄인 풀포기 높이 ≤ 그 칸 슬라임 몸 높이(가장 작은 개체 기준)
		var tall_ok := true
		for i in w.population():
			var ps2 := mv.plant_scale_at(w.s_y[i] * w.w + w.s_x[i])
			if ps2.x >= 0.0 and ps2.x * plant_h > slime_h * w.s_size[i]:
				tall_ok = false
		t.check(tall_ok, "슬라임이 선 칸의 풀포기는 몸보다 낮음")


# ── 전경(지도 전체)에서 작은 슬라임 키우기·선택 고리 최소 화면 크기 ──

func _check_overview(t, mv: MapView, w: SimWorld) -> void:
	mv.fit_map()
	mv.update_view(1.0)
	var cam := mv.get_camera()
	var k := mv.display_scale()
	t.check(k > 1.0 + EPS and k <= UiConfig.num("map.slime_display_scale_max") + EPS, "전경에서 작은 슬라임을 키워 그림(표시 배율 %.2f)" % k)
	# 몸 배율 = 크기 × 표시 배율(가로² × 세로 = 배율³, 숨쉬기·늘어남은 부피 유지) — 개체 사이 크기 비는 그대로
	var ok := true
	for i in mini(w.population(), 40):
		var sc := mv.slime_instance_scale(i)
		if absf(pow(sc.x * sc.x * sc.y, 1.0 / 3.0) - w.s_size[i] * k) > 0.01:
			ok = false
	t.check(ok, "몸 배율 = 크기 × 표시 배율")
	var iso := _isolated_index(w)
	if iso == -1:
		return
	var id := w.s_id[iso]
	var center_y := SlimeGeo.slime_mesh().get_aabb().size.y * 0.5 * k
	var q := mv.slime_instance_position(iso)
	t.check(mv.pick_slime(cam.unproject_position(Vector3(q.x, center_y, q.z))) == id, "전경에서 키운 몸 가운데를 누르면 그 개체")
	mv.set_selected(id)
	mv.update_view(1.0)
	var ri := mv.ring_info()
	var min_px := UiConfig.num("map.ring_min_px") * (1.0 - UiConfig.num("map.ring_pulse"))
	var c3: Vector3 = ri.position
	var right := cam.global_transform.basis.x
	var dia := cam.unproject_position(c3 - right * float(ri.radius)).distance_to(cam.unproject_position(c3 + right * float(ri.radius)))
	t.check(ri.visible and ri.on_top and dia >= min_px - 0.5, "전경 선택 고리: 화면 지름 %.1fpx ≥ %.0fpx, 맨 위에 그림" % [dia, min_px])
	# 가까이(focus_distance)서는 실제 크기·배율 1·깊이 검사 있는 재질
	mv.focus_on(id)
	mv.update_view(1.0)
	t.check(is_equal_approx(mv.display_scale(), 1.0), "가까이서는 표시 배율 1(%.2f)" % mv.display_scale())
	ri = mv.ring_info()
	var want := UiConfig.num("slime.radius") * w.s_size[iso] * UiConfig.num("map.ring_scale")
	t.check(not ri.on_top and absf(float(ri.radius) - want) <= want * UiConfig.num("map.ring_pulse") + EPS,
			"가까이서 고리 = 실제 크기(%.3f ≈ %.3f)" % [float(ri.radius), want])
	mv.set_selected(-1)
	mv.fit_map()
	mv.update_view(1.0)


# ── 전체 보기(fit_map)·따라가기 부드러움 ──

func _check_fit_and_follow(t, mv: MapView, w: SimWorld) -> void:
	var cam := mv.get_camera()
	mv.fit_map()
	var t0: Vector3 = cam.get("target")
	var d0: float = cam.get("distance")
	var y0: float = cam.get("yaw")
	var p0: float = cam.get("pitch")
	mv.focus_on(w.s_id[0])
	cam.call("rotate_pixels", Vector2(120, 40))
	mv.follow_selected = true
	mv.fit_map()
	t.check(Vector3(cam.get("target")).distance_to(t0) < EPS and absf(float(cam.get("distance")) - d0) < EPS
			and absf(float(cam.get("yaw")) - y0) < EPS and absf(float(cam.get("pitch")) - p0) < EPS and not mv.follow_selected,
			"fit_map: 처음 맞춤(목표·거리·방위·고각)으로 되돌리고 따라가기 끔")
	var inside := true
	for corner in [Vector3(0, 0, 0), Vector3(w.w, 0, 0), Vector3(w.w, 0, w.h), Vector3(0, 0, w.h)]:
		var sp := cam.unproject_position(corner)
		inside = inside and sp.x >= -1.0 and sp.y >= -1.0 and sp.x <= float(VP_SIZE.x) + 1.0 and sp.y <= float(VP_SIZE.y) + 1.0
	t.check(inside, "fit_map 뒤 지도 전체가 화면에 들어옴")
	# 따라가기: 1/30초 한 번 = 1/60초 두 번(프레임 빠르기와 무관)
	var i := w.population() / 2
	mv.set_selected(w.s_id[i])
	mv.follow_selected = true
	mv.update_view(1.0, 1.0 / 30.0)
	var a1: Vector3 = cam.get("target")
	cam.set("target", t0)
	cam.call("apply")
	mv.update_view(1.0, 1.0 / 60.0)
	mv.update_view(1.0, 1.0 / 60.0)
	var a2: Vector3 = cam.get("target")
	t.check(a1.distance_to(a2) < 0.001 and a1.distance_to(t0) > 0.01, "따라가기: 1/30초 한 번 = 1/60초 두 번 (%.4f)" % a1.distance_to(a2))
	mv.follow_selected = false
	mv.set_selected(-1)
	mv.fit_map()
	mv.update_view(1.0)


# ── 큰 지도: 처음에 다 보이고, 축소로 맞춘 거리까지 갈 수 있음(설정 최대 거리 95 를 넘어서) ──

func _check_big_maps(t, mv: MapView) -> void:
	var cam := mv.get_camera()
	for sz in BIG_MAPS:
		var wb: SimWorld = t.make_world({"map.width": sz.x, "map.height": sz.y}, 1)
		mv.bind(wb)
		var fitted: float = cam.get("distance")
		var inside := true
		var within_far := true
		var inv := cam.global_transform.affine_inverse()
		for corner in [Vector3(0, 0, 0), Vector3(wb.w, 0, 0), Vector3(wb.w, 0, wb.h), Vector3(0, 0, wb.h)]:
			var sp := cam.unproject_position(corner)
			inside = inside and not cam.is_position_behind(corner) and sp.x >= -1.0 and sp.y >= -1.0 \
					and sp.x <= float(VP_SIZE.x) + 1.0 and sp.y <= float(VP_SIZE.y) + 1.0
			within_far = within_far and -(inv * corner).z <= cam.far
		t.check(inside and within_far, "%d×%d 지도: 처음에 네 모서리가 화면·먼 면 안(거리 %.0f)" % [sz.x, sz.y, fitted])
		for k in 200:
			cam.call("zoom_at", Vector2(VP_SIZE) * 0.5, -1.0)
		t.check(float(cam.get("distance")) >= fitted - EPS and float(cam.call("distance_max")) >= fitted * UiConfig.num("camera.fit_zoom_out_factor") - EPS,
				"%d×%d 지도: 축소로 맞춘 거리 이상까지(최대 %.0f)" % [sz.x, sz.y, float(cam.call("distance_max"))])


# ── 고르기는 깊이를 본다: 겹친 칸의 앞 개체·낮은 고각의 큰 개체 머리(검토 I53) ──

## 그린 k 번째 개체의 몸 가운데 축 위, 바닥에서 몸 높이 × frac 인 점(월드).
func _body_point(mv: MapView, k: int, frac: float) -> Vector3:
	var p := mv.slime_instance_position(k)
	var h := SlimeGeo.slime_mesh().get_aabb().size.y * mv.slime_instance_scale(k).y
	return Vector3(p.x, p.y + h * frac, p.z)


## 카메라를 target 쪽으로 방위 yaw·가장 낮은 고각·PICK_DIST 에 두고 그린다.
func _low_camera(mv: MapView, target: Vector3, yaw: float) -> void:
	var cam := mv.get_camera()
	cam.set("target", Vector3(target.x, 0.0, target.z))
	cam.set("yaw", yaw)
	cam.set("pitch", deg_to_rad(UiConfig.num("camera.pitch_min_deg")))
	cam.set("distance", PICK_DIST)
	cam.call("apply")
	mv.update_view(1.0)


func _check_pick_depth(t, mv: MapView) -> void:
	var w: SimWorld = t.make_world({}, 3)
	var tile := _empty_tile(w)
	var iso := -1
	if tile != -1:
		# 개체 0·1 을 빈 풀밭 칸 하나에 겹쳐 세우고(크기 1), 떨어진 개체 하나는 가장 큰 크기로
		for k in 2:
			w.s_x[k] = tile % w.w
			w.s_y[k] = tile / w.w
			w.s_size[k] = 1.0
		for i in range(2, w.population()):
			if absi(w.s_x[i] - tile % w.w) + absi(w.s_y[i] - tile / w.w) >= 6:
				var alone := true
				for k in w.population():
					if k != i and absi(w.s_x[k] - w.s_x[i]) + absi(w.s_y[k] - w.s_y[i]) < 3:
						alone = false
						break
				if alone:
					iso = i
					break
	if tile == -1 or iso == -1:
		t.check(false, "깊이 고르기 검사용 칸·개체 (%d, %d)" % [tile, iso])
		return
	w.s_size[iso] = BIG_SIZE
	mv.bind(w)
	var cam := mv.get_camera()
	# ① 겹친 칸: 카메라를 앞 개체(0) 쪽, 가장 낮은 고각에 두고 앞 개체 몸 위쪽을 누름 → 앞 개체(고치기 전: 뒤 개체)
	var f := mv.slime_instance_position(0)
	var b := mv.slime_instance_position(1)
	_low_camera(mv, (f + b) * 0.5, atan2(f.x - b.x, f.z - b.z))
	var got := mv.pick_slime(cam.unproject_position(_body_point(mv, 0, PICK_TOP_K)))
	# 반대쪽에서 보면 앞뒤가 바뀜
	_low_camera(mv, (f + b) * 0.5, atan2(b.x - f.x, b.z - f.z))
	var got2 := mv.pick_slime(cam.unproject_position(_body_point(mv, 1, PICK_TOP_K)))
	t.check(got == w.s_id[0] and got2 == w.s_id[1],
			"겹친 칸: 앞 개체 몸 위쪽을 누르면 앞 개체(#%d → %d, #%d → %d)" % [w.s_id[0], got, w.s_id[1], got2])
	# ② 가장 낮은 고각에서 큰 개체(크기 %.1f)의 머리를 누름 → 그 개체(고치기 전: 반경 밖이라 -1 = 선택 해제)
	_low_camera(mv, mv.slime_instance_position(iso), 0.0)
	var head := mv.pick_slime(cam.unproject_position(_body_point(mv, iso, PICK_HEAD_K)))
	t.check(head == w.s_id[iso], "고각 %.0f° 에서 큰 개체(크기 %.1f) 머리 → 그 개체 (#%d → %d)" % [
			UiConfig.num("camera.pitch_min_deg"), BIG_SIZE, w.s_id[iso], head])
	# ③ 몸 옆 빈 곳(몸에는 안 맞지만 pick_radius 안)을 눌러도 그 개체 — 물러서는 고르기는 그대로
	var p := mv.slime_instance_position(iso)
	var side := Vector3(p.x + UiConfig.num("map.pick_radius") * 0.9 * UiConfig.num("map.tile_size"), p.y, p.z)
	var center_plane := SlimeGeo.slime_mesh().get_aabb().size.y * 0.5 * mv.display_scale()
	var near := mv.pick_slime(cam.unproject_position(Vector3(side.x, center_plane, side.z)))
	t.check(near == w.s_id[iso], "몸 옆(고르기 반경 안)을 눌러도 그 개체 (#%d → %d)" % [w.s_id[iso], near])
	mv.fit_map()


# ── 저장고 칸: 움집 안에 묻히지 않게 문 앞(문 방향, 보통 +Z)에 ──

## Stores MultiMesh 의 k 번째 인스턴스 문 방향(메시 정면 -Z 를 돌린 땅 위 방향 x, z). 버퍼는 행 우선 3×4.
func _store_door(mv: MapView, k: int) -> Vector2:
	var mi := mv.get_node_or_null("Stores") as MultiMeshInstance3D
	if mi == null or k >= mi.multimesh.instance_count:
		return Vector2.ZERO
	var buf := mi.multimesh.buffer
	var stride := buf.size() / mi.multimesh.instance_count
	return Vector2(-buf[k * stride + 2], -buf[k * stride + 10])


func _check_store_doorstep(t, mv: MapView, w: SimWorld) -> void:
	if w.store_tiles.is_empty() or w.population() < 3:
		t.check(false, "저장고 검사용 세계")
		return
	var sc := w.store_tiles[0]
	var sx := sc % w.w
	var sy := sc / w.w
	# 검사용 세계에서만 개체 둘을 저장고 칸에 옮겨 놓고 다시 붙인다(화면은 세계를 바꾸지 않음)
	for k in 2:
		w.s_x[k] = sx
		w.s_y[k] = sy
	mv.bind(w)
	var tl := UiConfig.num("map.tile_size")
	var door := _store_door(mv, 0)
	var ok := door.length() > 0.5
	var n := 0
	for i in w.population():
		if w.s_x[i] != sx or w.s_y[i] != sy:
			continue
		n += 1
		var p := mv.slime_instance_position(i)
		var dx := p.x - (float(sx) + 0.5) * tl
		var dz := p.z - (float(sy) + 0.5) * tl
		if Vector2(dx, dz).length() < STORE_EAVE * tl - EPS or Vector2(dx, dz).dot(door) <= 0.0:
			ok = false
	t.check(ok and n >= 2, "저장고 칸의 %d마리는 움집 처마(%.2f칸) 밖 문 앞(문 방향 %s)에 그려짐" % [n, STORE_EAVE, door])
	var cam := mv.get_camera()
	var center_y := SlimeGeo.slime_mesh().get_aabb().size.y * 0.5 * mv.display_scale()
	var q := mv.slime_instance_position(0)
	t.check(mv.pick_slime(cam.unproject_position(Vector3(q.x, center_y, q.z))) == w.s_id[0], "문 앞에 그린 개체를 누르면 그 개체")


# ── 남쪽이 바위·물이거나 지도 끝인 저장고: 문 앞 자리는 지나갈 수 있는 이웃 쪽(검토 I54) ──

## 검사용 세계에서만 store_tiles 를 바꿔(화면은 store_tiles 만 읽음) 남쪽이 막힌 저장고 둘을 만든다:
## A = 남쪽 이웃이 물·바위이고 동쪽은 지나갈 수 있는 칸, B = 맨 아래 줄(남쪽 = 지도 밖) 칸.
## 각 저장고 칸에 개체를 세우고, 그린 몸 가운데가 지도 안·지나갈 수 있는 칸 위인지, 처마 밖인지, 문이 그쪽을 보는지 본다.
func _check_store_blocked(t, mv: MapView) -> void:
	var w: SimWorld = t.make_world({}, 3)
	var a := -1
	var b := -1
	for y in range(1, w.h - 1):
		for x in range(0, w.w - 1):
			var c := y * w.w + x
			if a == -1 and SimGrid.passable(w.tiles[c]) and not SimGrid.passable(w.tiles[c + w.w]) and SimGrid.passable(w.tiles[c + 1]):
				a = c
	for x in w.w:
		var c := (w.h - 1) * w.w + x
		if b == -1 and SimGrid.passable(w.tiles[c]):
			b = c
	if a == -1 or b == -1 or w.population() < 4:
		t.check(false, "남쪽이 막힌 저장고 검사용 칸 (%d, %d)" % [a, b])
		return
	w.store_tiles = PackedInt32Array([a, b])
	for k in 3:
		var c := a if k < 2 else b
		w.s_x[k] = c % w.w
		w.s_y[k] = c / w.w
	mv.bind(w)
	var tl := UiConfig.num("map.tile_size")
	var bad := PackedStringArray()
	for k in 3:
		var c := a if k < 2 else b
		var p := mv.slime_instance_position(k)
		var off := Vector2(p.x - (float(c % w.w) + 0.5) * tl, p.z - (float(c / w.w) + 0.5) * tl)
		var tx := floori(p.x / tl)
		var tz := floori(p.z / tl)
		var inside := tx >= 0 and tz >= 0 and tx < w.w and tz < w.h
		var door := _store_door(mv, 0 if k < 2 else 1)
		if not inside or not SimGrid.passable(w.tiles[tz * w.w + tx]) or off.length() < STORE_EAVE * tl - EPS or off.dot(door) <= 0.0:
			bad.append("#%d 칸(%d,%d) → 몸 가운데 (%.2f, %.2f)" % [k, c % w.w, c / w.w, p.x, p.z])
	t.check(bad.is_empty(), "남쪽이 막힌 저장고(바위·물 / 지도 끝): 문 앞 개체가 지도 안 지나갈 수 있는 칸 위, 문이 그쪽 %s" % [bad])


# ── 밭 칸: 슬라임·그림자·선택 고리가 흙판 위 ──

func _check_farm_ground(t, mv: MapView, w: SimWorld) -> void:
	if w.farms.is_empty() or w.population() < 3:
		t.check(false, "밭 검사용 세계")
		return
	var fc := w.farms[0]
	w.s_x[2] = fc % w.w
	w.s_y[2] = fc / w.w
	mv.bind(w)
	mv.set_selected(w.s_id[2])
	mv.update_view(1.0)
	var top := UiConfig.num("map.farm_lift") + SlimeGeo.FARM_THICK
	var ridge := top + SlimeGeo.FARM_RIDGE_H
	var p := mv.slime_instance_position(2)
	var sh := mv.shadow_instance_position(2)
	var ri := mv.ring_info()
	t.check(p.y >= top - EPS and sh.y > top, "밭 칸 슬라임 바닥 %.3f·그림자 %.3f 가 흙판 위(%.3f)" % [p.y, sh.y, top])
	t.check(ri.visible and float((ri.position as Vector3).y) >= ridge, "밭 칸 선택 고리 높이 %.3f ≥ 이랑 꼭대기 %.3f" % [float((ri.position as Vector3).y), ridge])
	mv.set_selected(-1)
