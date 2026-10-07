extends SceneTree
## 실험실 화면 캡처·동작 확인(가상 디스플레이 필요). 계약: docs/VIEW-API.md "캡처".
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/ui_driver.gd -- --out=폴더 [--copy=폴더]
## scenes/lab.tscn 을 뿌리 창(1600×900)에 띄우고 프레임은 LabMain.advance_frame 으로 직접 몬다.
## 시나리오: ① 전경(기본·씨앗 1, 8배로 약 10초) ② fast_civ 농사 단계, 자식 있는 개체 선택·카메라 맞춤 ③ 밤(멈춤) ④ 64배와 실제 배속 표시.
## 동작: 지도 클릭 → 정보 창 id(실제 MapView 면 실제 입력, 뼈대면 신호), 속도·멈춤 단추 클릭, 단축키,
## 화면으로 진행해도 역사 해시가 헤드리스와 같음. 그림은 lab-*.png(600KB 넘으면 JPG). 끝에 RESULT 줄.
## 이전 프로젝트(little-monster-village, 같은 저자·MIT)의 tests/integration_driver.gd 입력 흉내(_click)를 가져와 고침.

const DT := 1.0 / 60.0
const SIZE_LIMIT := 600 * 1024
const JPG_QUALITY := 0.88
## 전경: 8배로 10초(600프레임)
const OVERVIEW_FRAMES := 600
## 농사 단계 뒤 밭이 생길 때까지 더 돌리는 한도(틱)와 바라는 밭 수
const FARM_EXTRA_MAX := 4000
const FARM_WANT := 3
const STAGE_MAX_TICKS := 20000
## 64배 장면: 실제 시간으로 도는 프레임 수
const REALTIME_FRAMES := 150

var out := "res://docs/screenshots/v0.1"
var copy_to := ""
var lab: LabMain
var _pass := 0
var _fail := 0
var _files: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--copy="):
			copy_to = a.substr(7)
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("  ok   " + what)
	else:
		_fail += 1
		print("  FAIL " + what)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_abs(out))
	if copy_to != "":
		DirAccess.make_dir_recursive_absolute(_abs(copy_to))
	lab = load("res://scenes/lab.tscn").instantiate()
	root.add_child(lab)
	await _frames(3)
	lab.set_process(false)
	print("[실험실 캡처] 창 %s, 렌더러 %s, 지도 %s" % [str(root.size), RenderingServer.get_current_rendering_method(), lab.map_view.get_script().resource_path])
	check(lab.world != null and lab.size.is_equal_approx(Vector2(root.size)), "실험실이 창 전체(%s)" % str(lab.size))
	await _overview()
	await _farm()
	await _night()
	await _speed64()
	for f in _files:
		print("  그림 %s (%d KB)" % [f, FileAccess.get_file_as_bytes(f).size() / 1024])
	print("RESULT: %d passed, %d failed (ui)" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ── 시나리오 ──

func _overview() -> void:
	check(lab.new_experiment("default", {}, 1) == "", "기본·씨앗 1 실험")
	lab.set_paused(false)
	lab.set_speed(8)
	var t0 := Time.get_ticks_msec()
	for i in OVERVIEW_FRAMES:
		lab.advance_frame(DT)
	print("  전경: %d틱 진행(%.1f초)" % [lab.world.tick, float(Time.get_ticks_msec() - t0) / 1000.0])
	var ref := _headless("default", 1, lab.world.tick)
	check(lab.world.history_hash == ref.history_hash, "화면으로 %d틱 진행해도 역사 해시가 헤드리스와 같음" % lab.world.tick)
	await _render(6)
	await _shot("lab-01-overview")
	# 동작: 지도 클릭 → 정보 창, 단추 클릭
	lab.set_paused(true)
	await _render(3)
	await _click_slime()
	await _click_buttons()
	lab.select_slime(-1)


func _farm() -> void:
	check(lab.new_experiment("fast_civ", {}, 1) == "", "fast_civ·씨앗 1 실험")
	var w := lab.world
	var t0 := Time.get_ticks_msec()
	var k := 0
	while w.stage < SimWorld.STAGE_FARM and k < STAGE_MAX_TICKS:
		w.step()
		k += 1
	var extra := 0
	while w.farms.size() < FARM_WANT and extra < FARM_EXTRA_MAX:
		w.step()
		extra += 1
	print("  농사: %d틱(%.1f초), 인구 %d, 저장고 %d, 밭 %d, 평균 %.1f세대" % [w.tick, float(Time.get_ticks_msec() - t0) / 1000.0,
			w.population(), w.store_tiles.size(), w.farms.size(), w.mean_generation()])
	check(w.stage == SimWorld.STAGE_FARM, "fast_civ 가 농사 단계에 도달(틱 %d)" % w.tick)
	# 살아 있는 개체 가운데 자식이 가장 많은 개체
	var best := -1
	var best_children := 0
	for i in w.population():
		var info := w.slime_info(w.s_id[i])
		if int(info.children) > best_children:
			best_children = int(info.children)
			best = w.s_id[i]
	check(best >= 0, "자식 있는 개체 #%d(자식 %d)" % [best, best_children])
	lab.set_paused(false)
	lab.set_speed(2)
	lab.select_slime(best)
	lab.map_view.focus_on(best)
	var got := {n = 0}
	var cb := func(list: Array) -> void: got.n += list.size()
	lab.events.connect(cb)
	await _render(12)
	lab.events.disconnect(cb)
	check(int(got.n) > 0 and not lab.visible_toasts().is_empty(), "쌓인 사건 %d건 → 알림" % int(got.n))
	check(lab.info_panel.current_id() == best, "정보 창 = 고른 개체 #%d" % best)
	check(lab._lbl_stage.text == SimWorld.STAGE_NAMES[SimWorld.STAGE_FARM], "문명 단계 표시: " + lab._lbl_stage.text)
	await _shot("lab-02-farm-selected")


func _night() -> void:
	# 알림을 지우고(멈춘 채 시간만 흘림) 밤이 될 때까지 진행
	lab.set_paused(true)
	for i in int(ceil(UiConfig.num("lab.toast_seconds") / 0.25)) + 1:
		lab.advance_frame(0.25)
	var w := lab.world
	var k := 0
	while w.light > 0.0 and k < 400:
		w.step()
		k += 1
	w.step_n(6)
	lab.set_paused(false)
	lab.set_speed(1)
	await _render(10)
	check(lab._lbl_daynight.text == "밤", "밤 표시(빛 %.2f)" % w.light)
	# 멈춘 모습(▶ 아이콘·지도 위 멈춤 표지)도 함께 찍는다
	lab.set_paused(true)
	await _render(2)
	check(lab._paused_badge.visible and lab.speed_text().begins_with("멈춤"), "멈춤 표지: " + lab.speed_text())
	await _shot("lab-03-night")


func _speed64() -> void:
	check(lab.new_experiment("default", {}, 1) == "", "64배용 기본·씨앗 1 실험")
	lab.set_paused(false)
	await _click(_center(lab._speed_btns[lab._speed_btns.size() - 1]))
	check(lab.target_speed() == 64, "64배 단추 클릭 → 목표 64배")
	await _park_mouse()
	# 실제 시간으로(_process) 돌린다
	lab.set_process(true)
	var t0 := Time.get_ticks_msec()
	await _frames(REALTIME_FRAMES)
	lab.set_process(false)
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	print("  64배: %d프레임 %.1f초에 %d틱, 실제 %.1f배, 표시 \"%s\"" % [REALTIME_FRAMES, secs, lab.world.tick, lab.actual_speed(), lab._lbl_speed.text])
	check(lab.world.tick > 0 and lab.actual_speed() > 0.0, "실시간 진행(%d틱)" % lab.world.tick)
	check(lab._lbl_speed.text.begins_with("목표 64배 / 실제 "), "실제 배속 표시: " + lab._lbl_speed.text)
	var ref := _headless("default", 1, lab.world.tick)
	check(lab.world.history_hash == ref.history_hash, "실시간 진행 뒤에도 역사 해시가 헤드리스와 같음(%d틱)" % lab.world.tick)
	await _shot("lab-04-speed64")


# ── 동작 확인 ──

## 화면 가운데에 가까운 살아 있는 개체를 찾아 누른다. 실제 MapView(pick_slime 이 개체를 찾음)면 실제 마우스 입력,
## 뼈대 MapView 면 slime_clicked 신호로 연결만 확인한다.
func _click_slime() -> void:
	var w := lab.world
	var cam := lab.map_view.get_camera()
	var sv := lab.map_view.get_viewport() as SubViewport
	var svc := sv.get_parent() as SubViewportContainer
	var tile := UiConfig.num("map.tile_size")
	var mid := Vector2(sv.size) * 0.5
	var best_i := -1
	var best_d := INF
	var best_pos := Vector2.ZERO
	for i in w.population():
		var wp := Vector3((float(w.s_x[i]) + 0.5) * tile, 0.0, (float(w.s_y[i]) + 0.5) * tile)
		if cam == null or cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		var d := sp.distance_to(mid)
		if d < best_d:
			best_d = d
			best_i = i
			best_pos = sp
	check(best_i >= 0, "화면 안의 개체를 찾음")
	if best_i < 0:
		return
	var picked := lab.map_view.pick_slime(best_pos)
	if picked >= 0:
		var scale := svc.size / Vector2(sv.size)
		await _click(svc.get_global_rect().position + best_pos * scale)
		check(lab.info_panel.current_id() == picked and lab.selected_id() == picked, "지도 클릭(실제 입력) → 정보 창 #%d (지금 %d)" % [picked, lab.info_panel.current_id()])
		await _click(Vector2(svc.get_global_rect().position) + Vector2(4, 4))
		print("  빈 곳(모서리) 클릭 뒤 선택 %d" % lab.selected_id())
	else:
		var id := w.s_id[best_i]
		lab.map_view.slime_clicked.emit(id)
		check(lab.info_panel.current_id() == id, "지도 클릭(신호, 뼈대 MapView) → 정보 창 #%d" % id)


func _click_buttons() -> void:
	var was := lab.is_paused()
	await _click(_center(lab._play_btn))
	check(lab.is_paused() != was, "재생/멈춤 단추 클릭")
	await _click(_center(lab._play_btn))
	await _click(_center(lab._speed_btns[2]))
	check(lab.target_speed() == int((UiConfig.value("speed.steps") as Array)[2]), "속도 단추 클릭 → %d배" % lab.target_speed())
	await _click(_center(lab._fast_btn))
	check(lab.is_fast_forward(), "빨리 감기 단추 클릭")
	await _click(_center(lab._speed_btns[3]))
	check(not lab.is_fast_forward() and lab.target_speed() == int((UiConfig.value("speed.steps") as Array)[3]), "속도 단추로 빨리 감기 끔")
	var k := InputEventKey.new()
	k.keycode = KEY_SPACE
	k.pressed = true
	var before := lab.is_paused()
	root.push_input(k)
	check(lab.is_paused() != before, "스페이스 단축키")
	lab.set_paused(true)
	await _park_mouse()


## 마우스를 정보 창 아래 모서리로 옮겨 단추의 올림(hover) 모양이 캡처에 남지 않게.
func _park_mouse() -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(root.size) - Vector2(4, 4)
	mv.global_position = mv.position
	root.push_input(mv)
	await _frames(1)


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _click(pos: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	root.push_input(mv)
	await _frames(1)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		root.push_input(e)
		await _frames(1)


# ── 도움 ──

func _headless(preset: String, seed_value: int, ticks: int) -> SimWorld:
	var w := SimWorld.new()
	w.setup(SimConfig.build(preset, {}).config, seed_value)
	w.step_n(ticks)
	return w


## n 프레임 그리기(실험실 진행 포함, 그사이 지도는 자기 _process 로 카메라 등을 움직임).
func _render(n: int) -> void:
	for i in n:
		lab.advance_frame(DT)
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := _abs(out).path_join(name + ".png")
	img.save_png(path)
	if FileAccess.get_file_as_bytes(path).size() > SIZE_LIMIT:
		DirAccess.remove_absolute(path)
		path = _abs(out).path_join(name + ".jpg")
		img.save_jpg(path, JPG_QUALITY)
	var sz := FileAccess.get_file_as_bytes(path).size()
	check(sz > 0 and sz <= SIZE_LIMIT and img.get_size() == Vector2i(root.size), "그림 %s %dx%d (%d KB)" % [path.get_file(), img.get_width(), img.get_height(), sz / 1024])
	_files.append(path)
	if copy_to != "":
		DirAccess.copy_absolute(path, _abs(copy_to).path_join(path.get_file()))


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p
