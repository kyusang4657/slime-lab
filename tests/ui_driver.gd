extends SceneTree
## 실험실 화면 캡처·동작 확인(가상 디스플레이 필요). 계약: docs/VIEW-API.md "캡처".
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/ui_driver.gd -- --out=폴더 [--copy=폴더]
## scenes/lab.tscn 을 뿌리 창(1600×900)에 띄우고 프레임은 LabMain.advance_frame 으로 직접 몬다.
## 시나리오: ① 전경(기본·씨앗 1, 8배로 약 10초) ② demo_fast·씨앗 11 농사 단계 낮, 밭 가까이 자식 있는 개체 선택·카메라 맞춤
## ③ 같은 자리의 밤(멈춤) ④ 64배와 실제 배속 표시 ⑤ 4단계 패널 자리(혼자 실험, 자리 접기 단추 클릭)
## ⑥ 비교 모드(demo_fast | 기본, 1,500틱 뒤 B 지도의 개체를 실제 마우스로 고름).
## 동작: 지도 클릭(실제 마우스 입력) → pick_slime → 정보 창 id, 빈 곳 클릭 → 선택 해제, 속도·멈춤 단추 클릭, 단축키,
## 화면으로 진행해도 역사 해시가 헤드리스와 같음. 그림은 lab-*.jpg(품질 0.85, 600KB 이하 확인). 끝에 RESULT 줄.
## 이전 프로젝트(little-monster-village, 같은 저자·MIT)의 tests/integration_driver.gd 입력 흉내(_click)를 가져와 고침.

const DT := 1.0 / 60.0
const SIZE_LIMIT := 600 * 1024
const JPG_QUALITY := 0.85
## 전경: 8배로 10초(600프레임)
const OVERVIEW_FRAMES := 600
## 농사 장면의 씨앗(demo_fast): 1,041틱에 농사 단계, 1,084틱에 밭 3칸(규칙 고침 g1b 뒤 씨앗 1 은 농사를 1,037틱에 발견하지만
## 밭 3칸이 2,347틱에야 생겨 장면이 늦고 밭이 드묾)
const FARM_SEED := 11
## 농사 단계 뒤 밭이 생길 때까지 더 돌리는 한도(틱)와 바라는 밭 수
const FARM_EXTRA_MAX := 4000
const FARM_WANT := 3
const STAGE_MAX_TICKS := 20000
## 64배 장면: 실제 시간으로 도는 프레임 수
const REALTIME_FRAMES := 150
## 농사 장면: 해가 뜨기를 기다리는 틱 한도(하루 이상), 해가 다 뜬 뒤 더 진행할 틱, 고를 개체가 밭에서 떨어진 칸 한도(차례로 넓힘, -1 = 아무 데나),
## 찍기 전 그리는 프레임(실제 배속 표시가 "—" 를 벗어나게 0.25초 넘게)
const DAY_WAIT_MAX := 200
const DAY_SETTLE_TICKS := 6
const FARM_NEAR: Array[int] = [2, 4, 6, -1]
const FARM_RENDER_FRAMES := 24
## 고를 개체의 남은 수명 하한(틱, 낮 장면에서 밤 장면까지 약 하루 = 60틱)
const MIN_LIFE_LEFT := 90
## 패널 장면: 프레임 없이 미리 진행할 틱(그래프·연대기에 기록이 쌓이게), 비교 장면: 두 실험을 미리 진행할 틱.
## 패널 장면은 기본·씨앗 1 이 채집(1,665틱)·저장(2,208틱)을 열고 저장고 4개(2,387틱까지)를 지은 뒤 — 연대기 6줄·그래프 발견선 둘·
## 지도에 저장고 넷(규칙 고침 g1b 뒤 다시 정함: 예전 1,200틱은 이제 발견 전이라 연대기가 비어 있음)
const PANEL_TICKS := 2400
const COMPARE_TICKS := 1500

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
	await _panels()
	await _compare()
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
	# 세계를 직접 돌리지 않고 lab.step_ticks 로(기록·recorded 가 따라가 그래프·연대기가 세계와 맞음 — 통합 때 고침)
	check(lab.new_experiment("demo_fast", {}, FARM_SEED) == "", "demo_fast·씨앗 %d 실험" % FARM_SEED)
	var w := lab.world
	var t0 := Time.get_ticks_msec()
	var k := 0
	while w.stage < SimWorld.STAGE_FARM and k < STAGE_MAX_TICKS:
		lab.step_ticks(1)
		k += 1
	var extra := 0
	while w.farms.size() < FARM_WANT and extra < FARM_EXTRA_MAX:
		lab.step_ticks(1)
		extra += 1
	print("  농사: %d틱(%.1f초), 인구 %d, 저장고 %d, 밭 %d, 평균 %.1f세대" % [w.tick, float(Time.get_ticks_msec() - t0) / 1000.0,
			w.population(), w.store_tiles.size(), w.farms.size(), w.mean_generation()])
	check(w.stage == SimWorld.STAGE_FARM, "demo_fast 가 농사 단계에 도달(틱 %d)" % w.tick)
	# 낮에 찍는다(밤 장면 lab-03 과 같은 자리를 낮·밤으로 견주도록): 해가 다 뜰 때까지 + 조금 더
	var dawn := 0
	while w.light < 1.0 and dawn < DAY_WAIT_MAX:
		lab.step_ticks(1)
		dawn += 1
	lab.step_ticks(DAY_SETTLE_TICKS)
	# 밭 가까이(FARM_NEAR 의 칸 수 안, 가까운 것부터)에 있는 개체 가운데 자식이 가장 많은 개체. 없으면 전체에서.
	# 밭이 화면 가운데 근처에 와야 위쪽 알림에 가리지 않는다.
	var best := -1
	for near: int in FARM_NEAR:
		best = _most_children(w, near)
		if best >= 0:
			break
	var best_children := int(w.slime_info(best).get("children", 0)) if best >= 0 else 0
	check(best >= 0 and best_children > 0, "밭 가까이 자식 있는 개체 #%d(자식 %d)" % [best, best_children])
	lab.set_paused(false)
	lab.set_speed(2)
	lab.select_slime(best)
	lab.map_view.focus_on(best)
	var got := {n = 0}
	var cb := func(list: Array) -> void: got.n += list.size()
	lab.events.connect(cb)
	# 실제 배속 창(0.25초)이 차도록 조금 넉넉히
	await _render(FARM_RENDER_FRAMES)
	lab.events.disconnect(cb)
	check(not LabMain.is_night(w) and lab._lbl_daynight.text == "낮", "농사 장면은 낮(빛 %.2f)" % w.light)
	check(int(got.n) > 0 and not lab.visible_toasts().is_empty(), "쌓인 사건 %d건 → 알림" % int(got.n))
	check(lab.info_panel.current_id() == best, "정보 창 = 고른 개체 #%d" % best)
	# V07: 정보 창이 스크롤 없이 두뇌 범례까지(여유 info.min_vertical_slack 이상, 1600×900)
	if root.size.y >= 900:
		var over := lab.info_panel.content_overflow()
		check(over <= -UiConfig.num("info.min_vertical_slack"), "V07 정보 창 스크롤 없음(여유 %.0fpx)" % -over)
	check(lab._lbl_stage.text == SimWorld.STAGE_NAMES[SimWorld.STAGE_FARM], "문명 단계 표시: " + lab._lbl_stage.text)
	# 그래프·연대기가 세계와 맞음(세계를 직접 돌리면 기록이 첫 줄에 멈춘 채 찍힘 — 통합 때 고침)
	var x := lab.experiment(0)
	var last_tick := int(x.rows().back().tick)
	check(lab.graph_panel.series_points(0, 0) == x.rows().size() and w.tick - last_tick < int(w.cfg.record.every)
			and lab.chronicle_panel.item_count() == w.chronicle.size(),
			"그래프 %d줄(마지막 틱 %d / 세계 %d)·연대기 %d건이 세계와 맞음" % [x.rows().size(), last_tick, w.tick, lab.chronicle_panel.item_count()])
	await _shot("lab-02-farm-selected")


func _night() -> void:
	# 알림을 지우고(멈춘 채 시간만 흘림) 밤이 될 때까지 진행
	lab.set_paused(true)
	for i in int(ceil(UiConfig.num("lab.toast_seconds") / 0.25)) + 1:
		lab.advance_frame(0.25)
	var w := lab.world
	var k := 0
	while w.light > 0.0 and k < 400:
		lab.step_ticks(1)
		k += 1
	lab.step_ticks(6)
	# 낮 장면에서 고른 개체를 다시 화면 가운데로(밤에도 선택 고리가 보이게). 지도를 먼저 한 번 갱신해
	# (멈춘 채라 진행은 없음) 위에서 직접 돌린 틱 뒤의 위치로 맞춘다.
	await _render(1)
	if lab.selected_id() >= 0:
		lab.map_view.focus_on(lab.selected_id())
	lab.set_paused(false)
	lab.set_speed(1)
	await _render(10)
	check(lab._lbl_daynight.text == "밤", "밤 표시(빛 %.2f)" % w.light)
	check(w.index_of_id(lab.selected_id()) >= 0 and lab.info_panel.current_id() == lab.selected_id(),
			"밤에도 고른 개체 #%d 가 살아 있고 정보 창에 그대로" % lab.selected_id())
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


## ⑤ 4단계 패널 자리: 혼자 실험을 PANEL_TICKS 진행한 뒤(기록이 쌓인 그래프·연대기) 왼쪽·아래 자리와 정보 창이 함께 보이는 모습.
## 지도 오른쪽 아래 "그래프·연대기" 단추를 실제 마우스로 눌러 접었다 편다.
func _panels() -> void:
	check(lab.new_experiment("default", {}, 1) == "", "패널 장면: 기본·씨앗 1 실험")
	check(lab.left_dock.get_node_or_null("ParamPanel") is ParamPanel and lab.bottom_dock.get_node_or_null("GraphPanel") is GraphPanel
			and lab.bottom_dock.get_node_or_null("ChroniclePanel") is ChroniclePanel and lab.get_node_or_null("LabSound") is LabSound,
			"패널 자리: ParamPanel → 왼쪽, GraphPanel·ChroniclePanel → 아래, LabSound → 자식")
	lab.set_paused(true)
	lab.step_ticks(PANEL_TICKS)
	lab.set_paused(false)
	lab.set_speed(4)
	await _render(FARM_RENDER_FRAMES)
	var win := Rect2(Vector2.ZERO, Vector2(root.size))
	check(lab._left_wrap.visible and lab._bottom_wrap.visible and win.encloses(lab._left_wrap.get_global_rect()) and win.encloses(lab._bottom_wrap.get_global_rect()),
			"왼쪽·아래 자리가 창 안에 보임(아래 %s)" % str(lab._bottom_wrap.get_global_rect()))
	var h0 := lab._map_area.size.y
	await _click(_center(lab._bottom_toggle))
	await _render(2)
	check(not lab._bottom_wrap.visible and lab._map_area.size.y > h0, "\"그래프·연대기\" 단추 클릭 → 아래 자리 접힘(지도 높이 %.0f → %.0f)" % [h0, lab._map_area.size.y])
	await _click(_center(lab._bottom_toggle))
	await _render(2)
	check(lab._bottom_wrap.visible and is_equal_approx(lab._map_area.size.y, h0), "다시 클릭 → 아래 자리 펼침")
	await _park_mouse()
	await _render(4)
	var ref := _headless("default", 1, lab.world.tick)
	check(lab.world.history_hash == ref.history_hash and lab.experiments[0].rows().size() == lab.world.tick / int(lab.world.cfg.record.every) + 1,
			"패널 장면 %d틱: 해시가 헤드리스와 같고 기록 %d줄" % [lab.world.tick, lab.experiments[0].rows().size()])
	await _shot("lab-05-panels")


## ⑥ 비교 모드: A = demo_fast, B = 기본(둘 다 씨앗 1)을 COMPARE_TICKS 진행 → 두 해시가 헤드리스와 같음 → 2배로 그리며
## 쌓인 사건 알림(A · / B ·) → B 지도 가운데 개체를 실제 마우스로 눌러 고름(정보 창 이름표 B, 고리는 B 지도에만).
func _compare() -> void:
	var err := lab.start_compare({preset = "demo_fast", overrides = {}, seed = 1}, {preset = "default", overrides = {}, seed = 1})
	check(err == "" and lab.is_comparing() and lab.map_view_of(1) != null, "비교 모드 시작(demo_fast | 기본) %s" % err)
	if not lab.is_comparing():
		return
	var wa := lab.experiment(0).world
	var wb := lab.experiment(1).world
	lab.set_paused(true)
	var t0 := Time.get_ticks_msec()
	lab.step_ticks(COMPARE_TICKS)
	print("  비교: %d틱(%.1f초), A %d마리 %s · B %d마리 %s" % [wa.tick, float(Time.get_ticks_msec() - t0) / 1000.0, wa.population(),
			SimWorld.STAGE_NAMES[wa.stage], wb.population(), SimWorld.STAGE_NAMES[wb.stage]])
	var ra := _headless("demo_fast", 1, wa.tick)
	var rb := _headless("default", 1, wb.tick)
	check(wa.tick == wb.tick and wa.history_hash == ra.history_hash and wb.history_hash == rb.history_hash,
			"비교 모드로 %d틱 진행해도 A·B 역사 해시가 각각 헤드리스와 같음" % wa.tick)
	lab.set_paused(false)
	lab.set_speed(2)
	await _render(FARM_RENDER_FRAMES)
	var tagged := {A = false, B = false}
	for v in lab.visible_toasts():
		var s := str(v.text)
		for tag: String in ["A", "B"]:
			if s.begins_with(tag + " · "):
				tagged[tag] = true
	check(bool(tagged.A) or bool(tagged.B), "비교 모드 알림에 이름표(%s)" % str(tagged))
	var mb := lab._map_area.get_node_or_null("MapContainerB") as Control
	check(mb != null and absf(lab._map_container.size.x - mb.size.x) <= 1.0 and lab._panes[0].full_title == lab.experiment(0).label,
			"지도 둘 나란히(%s | %s)" % [str(lab._map_container.size), str(mb.size) if mb != null else "-"])
	await _click_slime_on(1, false)
	check(lab.selected_index() == 1 and lab.info_panel.current_tag() == "B" and lab.map_view_of(1).ring_info().visible and not lab.map_view.ring_info().visible,
			"B 지도 클릭 → 정보 창 이름표 \"%s\", 고리는 B 지도에만" % lab.info_panel.current_tag())
	# 실험 알림은 자기 지도 칸 안(두 지도 사이를 걸쳐 다른 지도를 가리지 않음) — 쌓인 알림을 그대로 둔 채 찍는다
	await _park_mouse()
	await _render(FARM_RENDER_FRAMES)
	var placed := 0
	var inside := true
	for e: Dictionary in lab._toasts:
		var g := Experiment.TAGS.find(str(e.group))
		if g < 0:
			continue
		placed += 1
		inside = inside and lab._panes[g].container.get_global_rect().encloses((e.panel as Control).get_global_rect())
	check(inside, "비교 모드 실험 알림 %d개가 모두 자기 지도 칸 안" % placed)
	check(lab.view_turns(0) == lab.view_turns(1), "두 지도가 같은 방향(화면이 북쪽 위에서 %d번 돎)" % lab.view_turns(0))
	check(lab._cmp_box.visible and lab._top_bar.get_combined_minimum_size().x <= float(root.size.x), "위쪽 막대 비교 모드 표시가 창 폭 안")
	check(lab.selected_index() == 1 and lab.experiment(1).world.index_of_id(lab.selected_id()) >= 0 and lab.map_view_of(1).ring_info().visible,
			"찍을 때도 B 의 #%d 가 살아 있고 고리가 보임" % lab.selected_id())
	await _shot("lab-06-compare")


# ── 동작 확인 ──

## 화면 가운데에 가까운 살아 있는 개체를 찾아 실제 마우스 입력으로 누른다(그린 위치를 몸 가운데 높이로 투영 —
## pick_slime 이 쓰는 면과 같음). pick_slime 이 그 개체를 찾아야 하고(못 찾으면 실패), 정보 창·선택이 그 id.
## 이어서 지도 모서리(빈 곳)를 누르면 선택 해제.
func _click_slime() -> void:
	await _click_slime_on(0, true)


## k 번째 실험의 지도(비교 모드 1 = B)에서 같은 방법으로 누른다. deselect 면 이어서 그 지도 모서리를 눌러 해제.
func _click_slime_on(k: int, deselect: bool) -> void:
	var w := lab.experiment(k).world
	var mv := lab.map_view_of(k)
	var cam := mv.get_camera()
	var sv := mv.get_viewport() as SubViewport
	var svc := sv.get_parent() as SubViewportContainer
	var mid := Vector2(sv.size) * 0.5
	var center_y := SlimeGeo.slime_mesh().get_aabb().size.y * 0.5 * mv.display_scale()
	var best_i := -1
	var best_d := INF
	var best_pos := Vector2.ZERO
	for i in w.population():
		var q := mv.slime_instance_position(i)
		var wp := Vector3(q.x, center_y, q.z)
		if cam.is_position_behind(wp):
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
	var want := w.s_id[best_i]
	var picked := mv.pick_slime(best_pos)
	check(picked == want, "화면 가운데 개체를 고를 수 있음(pick_slime #%d, 그린 개체 #%d)" % [picked, want])
	if picked < 0:
		return
	var scale := svc.size / Vector2(sv.size)
	await _click(svc.get_global_rect().position + best_pos * scale)
	check(lab.info_panel.current_id() == want and lab.selected_id() == want and lab.selected_index() == k,
			"지도 %d 클릭(실제 입력) → 정보 창 #%d (지금 %d, 실험 %d)" % [k, want, lab.info_panel.current_id(), lab.selected_index()])
	if not deselect:
		return
	await _click(Vector2(svc.get_global_rect().position) + Vector2(4, 4))
	check(lab.selected_id() == -1 and lab.info_panel.current_id() == -1, "빈 곳(지도 모서리) 클릭 → 선택 해제(%d)" % lab.selected_id())


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

## 살아 있는 개체 가운데 자식이 가장 많은 개체 id(없으면 -1). near >= 0 이면 어느 밭과 체비쇼프 거리 near 칸 안인 개체만.
## 남은 수명이 MIN_LIFE_LEFT 틱보다 짧은 개체는 뺀다.
func _most_children(w: SimWorld, near: int) -> int:
	var best := -1
	var best_children := 0
	for i in w.population():
		if near >= 0:
			var close := false
			for c in w.farms:
				if maxi(absi(c % w.w - w.s_x[i]), absi(c / w.w - w.s_y[i])) <= near:
					close = true
					break
			if not close:
				continue
		var info := w.slime_info(w.s_id[i])
		# 밤 장면(lab-03)까지 살아 있도록 남은 수명이 넉넉한 개체만
		if int(info.max_age) - int(info.age) < MIN_LIFE_LEFT:
			continue
		var n := int(info.children)
		if n > best_children:
			best_children = n
			best = w.s_id[i]
	return best


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
	# 3D 지도가 대부분인 화면이라 JPG(PNG 의 절반 크기, 품질 0.85 에서 글자도 또렷함)
	var path := _abs(out).path_join(name + ".jpg")
	img.save_jpg(path, JPG_QUALITY)
	var sz := FileAccess.get_file_as_bytes(path).size()
	check(sz > 0 and sz <= SIZE_LIMIT and img.get_size() == Vector2i(root.size), "그림 %s %dx%d (%d KB)" % [path.get_file(), img.get_width(), img.get_height(), sz / 1024])
	_files.append(path)
	if copy_to != "":
		DirAccess.copy_absolute(path, _abs(copy_to).path_join(path.get_file()))


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p
