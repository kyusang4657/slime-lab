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
## 선택 인자: --seconds=N(실측 구간 길이, 기본 10)

const BENCH_FRAMES := 600
const BENCH_WARM := 30
## 인구가 처음 줄었다가 다시 불어난 뒤를 재려고: 적어도 GROW_MIN_TICKS 진행한 다음 개체가 POP_TARGET 이상이 될 때까지
const POP_TARGET := 200
const GROW_MIN_TICKS := 1500
const GROW_MAX_TICKS := 8000
const SECONDS := 10.0
const WARM_SECONDS := 1.0
const USEC := 1000000.0

var _seconds := SECONDS


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			_seconds = maxf(1.0, a.substr(10).to_float())
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
	_bench_world(mv, _world("fast_civ", {}, 1, 1760), "fast_civ 1760틱", [1, 4, 64])
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
	lab.new_experiment("default", {}, 1)
	var w := lab.world
	var g := 0
	while (g < GROW_MIN_TICKS or w.population() < POP_TARGET) and g < GROW_MAX_TICKS:
		w.step()
		g += 1
	print("[실험실 실측] 창 %s, 렌더러 %s / %s, 기본·씨앗 1 을 %d틱까지 진행(개체 %d)" % [str(root.size),
			RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), w.tick, w.population()])
	# 개체 하나를 골라 정보 창 갱신도 포함(오래 살 개체)
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
	print("RESULT: live ok")
	quit(0)


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
	var warm := true
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / USEC
		last = now
		var a0 := Time.get_ticks_usec()
		lab.advance_frame(dt)
		var a1 := Time.get_ticks_usec()
		if warm:
			if float(now - t_start) / USEC >= WARM_SECONDS:
				warm = false
				t_start = now
				ticks0 = w.tick
			continue
		frames += 1
		adv_us += a1 - a0
		sim_ms += lab.last_sim_ms
		frame_us.append(int(dt * USEC))
		pop_sum += w.population()
		fps_sum += Engine.get_frames_per_second()
		draw_sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim_sum += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
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
