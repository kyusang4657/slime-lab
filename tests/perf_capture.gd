extends SceneTree
## 화면 성능 측정(3단계 통합).
##   헤드리스 미세 측정:  godot --headless --path . --script res://tests/perf_capture.gd -- --bench
##   실험실 실측(가상 디스플레이·소프트웨어 GL):
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/perf_capture.gd
## ① 미세 측정: 인구 상한(250)으로 채운 세계에 MapView 를 붙이고, 프레임마다 before_steps → (틱) → update_view 를
##    잰다(틱 없는 프레임·틱 있는 프레임 따로). 농사 단계 세계(건물·밭 있음)도 같은 방식으로 잰다.
## ② 실측: 실험실 장면을 띄우고 기본 예설정 인구가 불어난 뒤(SECONDS 동안) 1배·64배로 실제 시간 진행하며
##    FPS, 프레임 시간, 우리 스크립트 시간(LabMain.advance_frame = 시뮬레이션 + 화면 갱신)을 잰다.
##    llvmpipe 는 CPU 로 그리는 소프트웨어 렌더러라 실제 GPU 와 수치가 다르다(그리기 몫이 훨씬 큼).
##    지도 3D 와 UI 2D 의 그리기 호출을 뷰포트별로 따로 출력한다(전체 모니터 값은 모든 뷰포트의 합).
## ③ 4단계(통합): 패널(파라미터·그래프·연대기·정보 창)을 모두 편 채 ㉮ 위 ②의 장면 ㉯ 기록 5,000줄 혼자
##    ㉰ 기록 5,000줄씩 비교(지도 둘)를 1배·64배로 잰다. 5,000줄은 record.every = 2 로 10,000틱(기본 20 이면 10만 틱이라
##    준비가 너무 김) — 그래서 64배에서 프레임당 새 줄이 기본보다 10배 많은 무거운 쪽 측정이다. 그래프 다시 그리기(_draw 세 개 합,
##    GraphView.last_draw_us)도 함께. ㉮ 는 자리를 접고도 한 번 더 잰다(3단계 측정과 같은 지도 크기 — 패널 몫을 가르려고).
## 선택 인자: --seconds=N(실측 구간 길이, 기본 10), --msaa=N(지도 MSAA 0~3 으로 바꿔 재기, 기본 ui.lab.map_msaa),
##   --only=base|rows|compare(그 장면만, 쉼표로 여럿)

const BENCH_FRAMES := 600
const BENCH_WARM := 30
## 인구가 처음 줄었다가 다시 불어난 뒤를 재려고: 적어도 GROW_MIN_TICKS 진행한 다음 개체가 POP_TARGET 이상이 될 때까지
const POP_TARGET := 200
const GROW_MIN_TICKS := 1500
const GROW_MAX_TICKS := 8000
const SECONDS := 10.0
const WARM_SECONDS := 1.0
const USEC := 1000000.0
## 4단계 기록 많은 장면: record.every 와 진행 틱(→ 기록 ROWS_TICKS / ROWS_EVERY + 1 줄)
const ROWS_EVERY := 2
const ROWS_TICKS := 10000

var _seconds := SECONDS
var _msaa := -1
var _only := PackedStringArray()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			_seconds = maxf(1.0, a.substr(10).to_float())
		elif a.begins_with("--msaa="):
			_msaa = clampi(a.substr(7).to_int(), 0, 3)
		elif a.begins_with("--only="):
			_only = a.substr(7).split(",")
	var bench := OS.get_cmdline_user_args().has("--bench") or DisplayServer.get_name() == "headless"
	if bench:
		_bench.call_deferred()
	else:
		_live.call_deferred()


# ════════════════════════════ ① 헤드리스 미세 측정 ════════════════════════════

func _bench() -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(1260, 856)
	sv.own_world_3d = true
	root.add_child(sv)
	var mv := MapView.new()
	sv.add_child(mv)
	await process_frame
	print("[화면 미세 측정] 헤드리스, MapView.before_steps + update_view, 프레임 %d개" % BENCH_FRAMES)
	# 인구 상한으로 채운 세계(시작 직후라 250마리 근처)
	_bench_world(mv, _world("default", {"population.initial": 250}, 11, 0), "기본·250마리", [1, 4, 64])
	# 농사 단계 세계(건물·밭·운반 열매 있음)
	_bench_world(mv, _world("demo_fast", {}, 1, 1760), "demo_fast 1760틱", [1, 4, 64])
	sv.queue_free()
	await process_frame
	print("RESULT: bench ok")
	quit(0)


func _world(preset: String, sets: Dictionary, seed_value: int, ticks: int) -> SimWorld:
	var w := SimWorld.new()
	w.setup(SimConfig.build(preset, sets).config, seed_value)
	w.step_n(ticks)
	return w


## 배속 mult(1배 = 초당 6틱, 60fps 가정)로 프레임마다 틱을 나눠 넣으며 잰다. 세계는 매번 같은 시작점에서 복제하지 않고
## 이어서 진행하므로 배속별로 개체 수가 조금 다르다(평균 개체 수를 함께 적음).
func _bench_world(mv: MapView, w: SimWorld, label: String, mults: Array) -> void:
	mv.bind(w)
	var tps := UiConfig.num("speed.ticks_per_second_1x")
	for m in mults:
		var per_frame := tps * float(m) / 60.0
		var acc := 0.0
		var view_tick: Array[int] = []
		var view_idle: Array[int] = []
		var sim_us := 0
		var pop_sum := 0
		var slime_part := 0
		for k in BENCH_WARM + BENCH_FRAMES:
			var t0 := Time.get_ticks_usec()
			mv.before_steps()
			var t1 := Time.get_ticks_usec()
			acc += per_frame
			var n := 0
			while acc >= 1.0:
				w.step()
				acc -= 1.0
				n += 1
			var t2 := Time.get_ticks_usec()
			mv.update_view(acc)
			var t3 := Time.get_ticks_usec()
			if k < BENCH_WARM:
				continue
			var v := (t1 - t0) + (t3 - t2)
			if n > 0:
				view_tick.append(v)
			else:
				view_idle.append(v)
			sim_us += t2 - t1
			pop_sum += w.population()
			slime_part += int(mv.view_stats().slime_us)
		var all: Array[int] = []
		all.append_array(view_tick)
		all.append_array(view_idle)
		var st := mv.view_stats()
		print("  %s %d배: 개체 평균 %.0f, 화면 %.0fµs/프레임(중앙 %d, 95%% %d, 최대 %d) — 틱 있는 프레임 %.0fµs(%d개), 틱 없는 프레임 %.0fµs(%d개), 슬라임 부분 %.0fµs, 시뮬레이션 %.0fµs/프레임, 식물 %d·저장고 %d·밭 %d, 삼각형 추정 %d" % [
			label, int(m), float(pop_sum) / BENCH_FRAMES, _mean(all), _pct(all, 0.5), _pct(all, 0.95), _pct(all, 1.0),
			_mean(view_tick), view_tick.size(), _mean(view_idle), view_idle.size(), float(slime_part) / BENCH_FRAMES,
			float(sim_us) / BENCH_FRAMES, int(st.plants), int(st.stores), int(st.farms), int(st.triangles_estimate)])


# ════════════════════════════ ② 실험실 실측 ════════════════════════════

func _live() -> void:
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	root.add_child(lab)
	for i in 3:
		await process_frame
	# LabMain._process 대신 여기서 같은 advance_frame 을 실제 프레임 시간으로 불러 스크립트 시간을 잰다
	lab.set_process(false)
	if _msaa >= 0:
		(lab.map_view.get_viewport() as SubViewport).msaa_3d = _msaa as Viewport.MSAA
	print("[실험실 실측] 창 %s, 렌더러 %s / %s, 지도 MSAA %d, 자리(설정·그래프·연대기) 펼침 %s" % [str(root.size),
			RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(),
			int((lab.map_view.get_viewport() as SubViewport).msaa_3d),
			str(lab.is_dock_open(LabMain.DOCK_LEFT) and lab.is_dock_open(LabMain.DOCK_BOTTOM))])
	# ㉮ 3단계와 같은 장면(기본·씨앗 1, 1,500틱 넘게·개체 200 이상) — 세계를 직접 돌리지 않고 step_ticks(기록·그래프·연대기가 따라감)
	if _want("base"):
		lab.new_experiment("default", {}, 1)
		var w := lab.world
		var g := 0
		while (g < GROW_MIN_TICKS or w.population() < POP_TARGET) and g < GROW_MAX_TICKS:
			lab.step_ticks(1)
			g += 1
		await _scene(lab, "㉮ 기본·씨앗 1(3단계와 같은 장면)")
		# 같은 세계를 자리 둘 다 접고(지도 = 3단계 크기, 패널은 숨어 그리지 않음)
		lab.set_dock_open(LabMain.DOCK_LEFT, false)
		lab.set_dock_open(LabMain.DOCK_BOTTOM, false)
		await process_frame
		await _scene(lab, "㉮′ 같은 세계·자리 둘 다 접음(지도 %s)" % str(lab.map_view.get_viewport().get_visible_rect().size))
		lab.set_dock_open(LabMain.DOCK_LEFT, true)
		lab.set_dock_open(LabMain.DOCK_BOTTOM, true)
		await process_frame
	# ㉯ 기록 5,000줄(혼자)
	if _want("rows"):
		lab.new_experiment("default", {"record.every": ROWS_EVERY}, 1)
		var t0 := Time.get_ticks_msec()
		lab.step_ticks(ROWS_TICKS)
		print("  (준비: %d틱 %.1f초)" % [ROWS_TICKS, float(Time.get_ticks_msec() - t0) / 1000.0])
		await _scene(lab, "㉯ 기본·씨앗 1·record.every %d·%d틱(혼자)" % [ROWS_EVERY, ROWS_TICKS])
	# ㉰ 기록 5,000줄씩 비교(지도 둘)
	if _want("compare"):
		var spec := {preset = "default", overrides = {"record.every": ROWS_EVERY}}
		var a := spec.duplicate(true)
		a.seed = 1
		var b := spec.duplicate(true)
		b.seed = 2
		var err := lab.start_compare(a, b)
		if err != "":
			printerr("비교 시작 실패: " + err)
		var t1 := Time.get_ticks_msec()
		lab.step_ticks(ROWS_TICKS)
		print("  (준비: 두 세계 %d틱 %.1f초)" % [ROWS_TICKS, float(Time.get_ticks_msec() - t1) / 1000.0])
		await _scene(lab, "㉰ 비교 A 씨앗 1 | B 씨앗 2·record.every %d·%d틱" % [ROWS_EVERY, ROWS_TICKS])
	print("RESULT: live ok")
	quit(0)


func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


## 한 장면: 사건을 비우고(연대기·알림) 오래 살 개체를 골라(정보 창 갱신 포함) 1배·64배로 잰다.
func _scene(lab: LabMain, title: String) -> void:
	lab.set_paused(true)
	lab.advance_frame(1.0 / 60.0)
	var rows := PackedStringArray()
	var pops := PackedStringArray()
	var chron := 0
	for x in lab.experiments:
		rows.append(str(x.rows().size()))
		pops.append(str(x.world.population()))
		chron += x.world.chronicle.size()
	var w := lab.world
	print("[%s] 틱 %d, 개체 %s, 기록 %s줄, 연대기 %d건(창 %d줄), 그래프 %dpx 폭" % [title, w.tick, "/".join(pops),
			"/".join(rows), chron, lab.chronicle_panel.item_count(), int(lab.graph_panel.size.x)])
	var pick := -1
	var best_left := 0
	for i in w.population():
		var left := w.s_max_age[i] - w.s_age[i]
		if left > best_left:
			best_left = left
			pick = w.s_id[i]
	lab.select_slime(pick)
	lab.set_paused(false)
	for m in [1, 64]:
		lab.set_speed(m)
		await _measure(lab, m)


func _measure(lab: LabMain, mult: int) -> void:
	var w := lab.world
	var last := Time.get_ticks_usec()
	var t_start := last
	var frames := 0
	var adv_us := 0
	var sim_ms := 0.0
	var frame_us: Array[int] = []
	var ticks0 := w.tick
	var pop_sum := 0
	var fps_sum := 0.0
	var draw_sum := 0.0
	var prim_sum := 0.0
	# 뷰포트별: 지도 SubViewport(3D, 보이는 것) 그리기 호출·기본 도형, 뿌리 창 2D(UI) 그리기 호출
	var map_rid := lab.map_view.get_viewport().get_viewport_rid()
	var root_rid := root.get_viewport_rid()
	var map_draw := 0.0
	var map_prim := 0.0
	var ui_draw := 0.0
	# 4단계 패널: 그래프 다시 그리기(세 그래프 _draw 합)·묶음 새로 만들기 횟수, 엔진 process 단계 시간
	var gp := lab.graph_panel
	var redraws0 := gp.redraw_count
	var rc_seen := gp.redraw_count
	var graph_us := 0
	var graph_n := 0
	var graph_max := 0
	var rebuild0 := 0
	for gi in gp.graph_count():
		rebuild0 += gp.view(gi).rebuild_count
	var warm := true
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / USEC
		last = now
		var a0 := Time.get_ticks_usec()
		lab.advance_frame(dt)
		var a1 := Time.get_ticks_usec()
		# 지난 프레임에 그래프를 다시 그렸으면(redraw_count 가 바뀜) 그 _draw 시간(세 그래프 합)
		var drew := gp.redraw_count != rc_seen
		rc_seen = gp.redraw_count
		if warm:
			if float(now - t_start) / USEC >= WARM_SECONDS:
				warm = false
				t_start = now
				ticks0 = w.tick
				redraws0 = gp.redraw_count
				rebuild0 = 0
				for gi in gp.graph_count():
					rebuild0 += gp.view(gi).rebuild_count
			continue
		if drew:
			var us := 0
			for gi in gp.graph_count():
				us += gp.view(gi).last_draw_us
			graph_us += us
			graph_n += 1
			graph_max = maxi(graph_max, us)
		frames += 1
		adv_us += a1 - a0
		sim_ms += lab.last_sim_ms
		frame_us.append(int(dt * USEC))
		pop_sum += w.population()
		fps_sum += Engine.get_frames_per_second()
		draw_sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim_sum += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		map_draw += RenderingServer.viewport_get_render_info(map_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		map_prim += RenderingServer.viewport_get_render_info(map_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
				RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		ui_draw += RenderingServer.viewport_get_render_info(root_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		if float(now - t_start) / USEC >= _seconds:
			break
	var secs := float(last - t_start) / USEC
	var f := float(maxi(1, frames))
	var adv_ms := float(adv_us) / f / 1000.0
	var sim_avg := sim_ms / f
	print("  %d배: %.1f초 %d프레임 → 평균 %.1f FPS (Engine %.1f), 프레임 시간 중앙 %.1fms·95%% %.1fms, 우리 스크립트(advance_frame) %.2fms/프레임 = 시뮬레이션 %.2fms + 화면·UI %.2fms, %d틱(실제 %.1f배, 표시 \"%s\"), 개체 평균 %.0f, 그리기 호출 %.0f, 기본 도형 %.0f" % [
		mult, secs, frames, f / secs, fps_sum / f, float(_pct(frame_us, 0.5)) / 1000.0, float(_pct(frame_us, 0.95)) / 1000.0,
		adv_ms, sim_avg, adv_ms - sim_avg, w.tick - ticks0, float(w.tick - ticks0) / secs / UiConfig.num("speed.ticks_per_second_1x"),
		lab.speed_text(), float(pop_sum) / f, draw_sum / f, prim_sum / f])
	print("      뷰포트별: 지도(3D) 그리기 호출 %.0f · 기본 도형 %.0f, UI(뿌리 창 2D) 그리기 호출 %.0f — 지도 삼각형 추정 %d(숨긴 풀포기·그림자 포함)" % [
		map_draw / f, map_prim / f, ui_draw / f, int(lab.map_view.view_stats().triangles_estimate)])
	var rebuilds := -rebuild0
	for gi in gp.graph_count():
		rebuilds += gp.view(gi).rebuild_count
	var gn := float(maxi(1, graph_n))
	print("      패널: 그래프 다시 그리기 %d번(%.1f번/초, 한도 %.0f) — 세 그래프 _draw 합 평균 %.2fms·최대 %.2fms, 프레임당 %.2fms, 묶음 새로 만들기 %d번" % [
		gp.redraw_count - redraws0, float(gp.redraw_count - redraws0) / secs, UiConfig.num("graph.redraw_hz"),
		float(graph_us) / gn / 1000.0, float(graph_max) / 1000.0, float(graph_us) / f / 1000.0, rebuilds])


# ── 도움 ──

static func _mean(a: Array[int]) -> float:
	if a.is_empty():
		return 0.0
	var s := 0
	for v in a:
		s += v
	return float(s) / float(a.size())


static func _pct(a: Array[int], q: float) -> int:
	if a.is_empty():
		return 0
	var b := a.duplicate()
	b.sort()
	return int(b[clampi(int(round(q * float(b.size() - 1))), 0, b.size() - 1)])
