extends RefCounted
## GraphPanel·GraphView 검사(헤드리스). tests/run_view_tests.gd 가 불러 run(t) 을 부른다.
## LabMain 의 자리 채우기는 통합 때 연결되므로, 여기서는 패널을 직접 lab.bottom_dock 에 넣고 bind_lab 한다.
## 비교 모드(start_compare)도 아직 뼈대라, 실험 둘을 직접 만들어 LabMain 이 내는 것과 같은 호출로 몬다:
##   x.tag = "A"/"B" → panel.load_experiments([a, b])(= experiments_changed) → 진행할 때마다 append_row(k, rows().back())(= recorded).

const MIN_CHECKS := 60
## 합성 줄 수(긴 실행 흉내: 실험 둘 × 이만큼)와 그 줄 간격(틱)
const LONG_ROWS := 6000
const LONG_EVERY := 20
## 그리기 시간의 넉넉한 상한(µs) — 느린 CI 에서도 넘지 않을 값. 실제 시간은 출력한다.
const DRAW_BOUND_US := 20000
const DEMO_TICKS := 1700


func run(t) -> void:
	_static_checks(t)
	_series_checks(t)
	await _lab_checks(t)
	await _compare_checks(t)
	await _long_checks(t)


# ── 정적 도움 함수·줄이기 ──
func _static_checks(t) -> void:
	t.check(is_equal_approx(GraphView.nice_step(100.0, 5, true), 20.0), "눈금 간격 100/5 → 20")
	t.check(is_equal_approx(GraphView.nice_step(0.07, 4), 0.02), "눈금 간격 0.07/4 → 0.02")
	t.check(GraphView.nice_step(3.0, 5, true) >= 1.0, "정수 눈금은 1 이상")
	t.check(GraphView.decimals_for(0.25) == 2 and GraphView.decimals_for(50.0) == 0, "눈금 자릿수")
	t.check(GraphView.fmt_num(12345.6, 1) == "12,345.6" and GraphView.fmt_num(-0.0001, 2) == "0.00", "숫자 표시(쉼표·-0)")

	# 줄이기(M4): 열마다 첫·최소·최대·끝 줄 번호가 그 열의 참값
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	for i in 1000:
		xs.append(float(i))
		ys.append(sin(float(i) * 0.37) * 10.0 + float((i * 7919) % 13))
	ys[333] = 99.0
	ys[777] = -99.0
	var r := GraphView.reduce(xs, ys, 0.0, 1000.0, 10)
	t.check(r.count() == 10, "1000줄 → 10열: 묶음 %d개" % r.count())
	var ok := true
	for c in 10:
		var lo := INF
		var hi := -INF
		for i in range(c * 100, c * 100 + 100):
			lo = minf(lo, ys[i])
			hi = maxf(hi, ys[i])
		var b := c * 4
		if r.idx[b] != c * 100 or r.idx[b + 3] != c * 100 + 99 or ys[r.idx[b + 1]] != lo or ys[r.idx[b + 2]] != hi:
			ok = false
	t.check(ok, "열마다 첫·끝 줄과 최소·최대 값이 그대로")
	var flat: Array[int] = []
	for seg in GraphView.run_indices(r):
		for i in seg:
			flat.append(i)
	t.check(flat.has(333) and flat.has(777), "뾰족한 값(줄 333·777)이 그릴 점에 남음")
	t.check(flat.size() <= 4 * 10, "그릴 점 ≤ 열 수 × 4: %d" % flat.size())
	# 나눠 넣어도(새 줄만 더함) 한 번에 넣은 것과 같은 묶음
	var r2 := GraphView.Runs.new()
	var sx := 10.0 / 1000.0
	r2.feed(xs.slice(0, 450), ys.slice(0, 450), 0.0, sx, 10)
	r2.feed(xs, ys, 0.0, sx, 10)
	t.check(r2.col == r.col and r2.idx == r.idx and r2.used == 1000, "새 줄만 더해도 같은 묶음")
	# 빈 값(NaN) 줄은 선을 끊는다
	var ys2 := ys.duplicate()
	for i in range(500, 520):
		ys2[i] = NAN
	var segs := GraphView.run_indices(GraphView.reduce(xs, ys2, 0.0, 1000.0, 50))
	t.check(segs.size() == 2, "NaN 줄에서 선이 둘로 끊김: %d" % segs.size())
	# 가로 위치 기준 점선: 켬 구간이 무늬 비율만큼
	var gv := GraphView.new()
	var pts := PackedVector2Array([Vector2(0, 10), Vector2(100, 10)])
	var dashes := gv._xdash(pts)
	var on := 0.0
	for k in range(0, dashes.size(), 2):
		on += dashes[k].distance_to(dashes[k + 1])
	var want := 100.0 * UiConfig.num("graph.dash_px") / (UiConfig.num("graph.dash_px") + UiConfig.num("graph.dash_gap_px"))
	t.check(dashes.size() >= 4 and absf(on - want) <= UiConfig.num("graph.dash_px"), "점선 켬 길이 %.1f ≈ %.1f" % [on, want])
	gv.free()


# ── 줄 쌓기: 멸종·평균 세대 이어 쓰기 ──
func _series_checks(t) -> void:
	var s := GraphPanel.Series.new(null)
	var base := {tick = 0, population = 5, births = 1, deaths = 0, mean_gen = 2.5, mean_size = 1.1, mean_sense = 3.0,
			mean_energy = 9.0, mean_age = 40.0, civ_stage = 0, storehouses = 0, farms = 0}
	s.append(base)
	var r2 := base.duplicate()
	r2.tick = 20
	r2.population = 0
	r2.mean_gen = 0.0
	r2.mean_size = 0.0
	s.append(r2)
	t.check(s.extinct_row == 1 and s.extinct_tick == 20.0, "멸종 줄·틱")
	t.check(is_nan(s.cols[GraphPanel.C_SIZE][1]) and s.cols[GraphPanel.C_POP][1] == 0.0, "개체가 없으면 평균은 빈 값(NaN), 개체 수는 0")
	t.check(s.gen_x[1] == 2.5 and s.hi[GraphPanel.C_SIZE] == 1.1 and s.lo[GraphPanel.C_SIZE] == 1.1, "세대 축은 마지막 평균 세대를 이어 씀, 범위는 NaN 제외")


# ── 실험실에 묶기: 기록·지우기·시점·가로축·발견·마우스 ──
func _lab_checks(t) -> void:
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(2)
	lab.set_process(false)
	t.check(lab.new_experiment("demo_fast", {}, 1) == "", "실험실: demo_fast 새 실험")
	var panel := GraphPanel.new()
	lab.bottom_dock.add_child(panel)
	panel.bind_lab(lab)
	await t.frames(3)
	t.check(panel.graph_count() == 3, "그래프 3개")
	var x := lab.experiments[0]
	t.check(panel.series_points(0, 0) == x.rows().size() and x.rows().size() == 1, "묶자마자 지금 실험의 기록을 읽음")
	# 바로 다시 그려 두면(_since = 0) 아래 간격 검사가 실제 프레임 시간과 무관하다
	panel.redraw_now()
	var redraws := panel.redraw_count
	lab.step_ticks(400)
	var n := x.rows().size()
	var all_ok := true
	for g in 3:
		all_ok = all_ok and panel.series_points(g, 0) == n
	t.check(all_ok and n == 21, "step_ticks(400) → 세 그래프 모두 기록 줄 수만큼(%d)" % n)
	var last_row: Dictionary = x.rows().back()
	t.check(panel.series[0].cols[GraphPanel.C_POP][n - 1] == float(last_row.population) and panel.series[0].tick[n - 1] == float(last_row.tick),
			"덧붙인 값 = 기록 줄")
	# 다시 그리기는 모아서: 간격 전에는 안 그림, 지나면 한 번
	t.check(is_equal_approx(panel.redraw_interval(), 1.0 / UiConfig.num("graph.redraw_hz")), "다시 그리기 간격 = 1 / redraw_hz")
	t.check(panel.is_dirty() and panel.redraw_count == redraws, "새 줄 20개가 와도 바로 다시 그리지 않음")
	t.check(not panel.advance(panel.redraw_interval() * 0.5), "간격 전에는 다시 그리지 않음")
	t.check(panel.advance(panel.redraw_interval() * 0.6) and not panel.is_dirty() and panel.redraw_count == redraws + 1, "간격이 지나면 한 번 다시 그림")
	t.check(not panel.advance(panel.redraw_interval() * 2.0), "새 줄이 없으면 다시 그리지 않음")
	# 시점 표시
	lab.request_cursor(200)
	t.check(panel.cursor_tick == 200, "cursor_tick_requested → 시점 표시")
	lab.request_cursor(-1)
	t.check(panel.cursor_tick == -1, "-1 → 시점 표시 지움")

	# 발견: demo_fast 는 1,636틱에 농사까지
	lab.step_ticks(DEMO_TICKS - 400)
	var w := x.world
	var s0 := panel.series[0]
	var marks_ok := s0.markers.size() == 3
	for m in s0.markers:
		marks_ok = marks_ok and float(m.tick) == float(w.discovery_tick[int(m.stage)])
	t.check(marks_ok and w.stage == SimWorld.STAGE_FARM, "발견 표시 3개, 틱 = world.discovery_tick %s" % str(w.discovery_tick))
	panel.redraw_now()
	await t.frames(2)
	var v2 := panel.view(GraphPanel.GRAPH_CIV)
	var mk_ok := v2.last_markers.size() == 3
	for m in v2.last_markers:
		var want := roundf(v2.data_to_px(float(w.discovery_tick[int(m.stage)]))) + 0.5
		mk_ok = mk_ok and absf(float(m.x) - want) < 0.01
	t.check(mk_ok, "기술 단계 그래프의 발견 세로선이 발견 틱 자리(%d개)" % v2.last_markers.size())
	t.check(v2.last_markers.any(func(m: Dictionary) -> bool: return m.labeled), "발견 이름이 적어도 하나 보임")

	# 가로축 바꾸기: 알려진 점(마지막 줄)의 가로 픽셀
	var v0 := panel.view(GraphPanel.GRAPH_POP)
	var k := s0.size() - 1
	var p_tick := v0.point_px(0, k, GraphPanel.C_POP)
	var b := panel.x_bounds()
	var want_tick := v0.plot.position.x + (s0.tick[k] - b.x) / (b.y - b.x) * v0.plot.size.x
	t.check(absf(p_tick.x - want_tick) < 0.01 and b.x <= s0.tick[0] and b.y >= s0.tick[k], "틱 축: 마지막 줄 가로 %.1f = %.1f" % [p_tick.x, want_tick])
	var rel0 := (v0.data_to_px(s0.tick[k] * 0.5) - v0.plot.position.x) / v0.plot.size.x
	var v1 := panel.view(GraphPanel.GRAPH_TRAIT)
	v1.layout_now()
	var rel1 := (v1.data_to_px(s0.tick[k] * 0.5) - v1.plot.position.x) / v1.plot.size.x
	t.check(absf(rel0 - rel1) < 1e-6, "세 그래프가 같은 가로 범위")
	panel.set_x_axis("gen")
	var p_gen := v0.point_px(0, k, GraphPanel.C_POP)
	var bg := panel.x_bounds()
	var want_gen := v0.plot.position.x + (s0.gen_x[k] - bg.x) / (bg.y - bg.x) * v0.plot.size.x
	t.check(panel.x_mode == GraphPanel.X_GEN and absf(p_gen.x - want_gen) < 0.01 and bg.y < b.y, "세대 축: 마지막 줄 가로 = 평균 세대 %.2f 자리" % s0.gen_x[k])
	t.check(absf(p_gen.y - p_tick.y) < 0.01, "가로축을 바꿔도 세로 위치는 그대로")
	panel.redraw_now()
	await t.frames(2)
	var gm_ok := v2.last_markers.size() == 3
	for m in v2.last_markers:
		var mm := s0.marker_for(int(m.stage))
		gm_ok = gm_ok and absf(float(m.x) - (roundf(v2.data_to_px(float(mm.gen))) + 0.5)) < 0.01 and float(mm.gen) > 0.0
	t.check(gm_ok, "세대 축의 발견 세로선 = 연대기의 발견 평균 세대 자리")
	# 세대 축의 가장 가까운 줄 = 차이가 가장 작은 줄
	var gx := s0.gen_x[k / 2] + 0.03
	var best := 0
	for i in s0.size():
		if absf(s0.gen_x[i] - gx) <= absf(s0.gen_x[best] - gx):
			best = i
	t.check(panel.nearest_row(0, gx) == best, "세대 축 가장 가까운 줄")
	panel.set_x_axis("없는축")
	t.check(panel.x_mode == GraphPanel.X_GEN, "모르는 가로축 값은 무시")
	panel.set_x_axis("tick")

	# 마우스: 가장 가까운 기록 줄과 값 읽기
	v0.layout_now()
	var row := 30
	var every := float(int(w.cfg.record.every))
	v0.hover_at(Vector2(v0.data_to_px(s0.tick[row] + every * 0.3), v0.plot.get_center().y))
	t.check(panel.hover_rows()[0] == row and panel.hover_view == v0, "마우스 → 가장 가까운 줄 %d" % panel.hover_rows()[0])
	v0.hover_at(Vector2(v0.data_to_px(s0.tick[row] + every * 0.7), v0.plot.get_center().y))
	t.check(panel.hover_rows()[0] == row + 1, "반 칸 넘으면 다음 줄")
	var txt := v0.readout_text()
	t.check(txt.contains("틱 %s" % GraphView.fmt_num(s0.tick[row + 1], 0)) and txt.contains("개체 %s" % GraphView.fmt_num(s0.cols[GraphPanel.C_POP][row + 1], 0)),
			"값 읽기: %s" % txt)
	t.check(v1.readout_text() == "" and v1.readout_lines().is_empty(), "값 읽기 상자는 마우스가 있는 그래프에만")
	v2.layout_now()
	v2.hover_at(Vector2(v2.data_to_px(s0.tick[n + 10]), v2.plot.get_center().y))
	t.check(v2.readout_text().contains(SimWorld.STAGE_NAMES[int(s0.cols[GraphPanel.C_STAGE][n + 10])]) and v2.readout_text().contains("밭"), "기술 단계 값 읽기: %s" % v2.readout_text())
	v0.hover_at(Vector2(v0.plot.position.x - 5.0, v0.plot.get_center().y))
	t.check(is_nan(panel.hover_x) and panel.hover_view == null, "그림 영역 밖 → 마우스 값 지움")

	# 출생·사망, 평균 특성 고르기, 평평한 값
	panel.set_show_flows(true)
	panel.set_trait(GraphPanel.TRAIT_COLS.find(GraphPanel.C_SENSE))
	await t.frames(2)
	var cols0: Array[int] = []
	for l in v0.last_lines:
		cols0.append(int(l.col))
	t.check(cols0.has(GraphPanel.C_BIRTHS) and cols0.has(GraphPanel.C_DEATHS) and cols0.has(GraphPanel.C_POP), "출생·사망 선을 켬")
	t.check(v0.y_range().y >= s0.hi[GraphPanel.C_BIRTHS] and v0.y_range().x == 0.0, "개체 수 세로축은 0 부터, 출생 최댓값 포함")
	t.check(v1.last_lines.size() == 1 and int(v1.last_lines[0].col) == GraphPanel.C_SENSE, "평균 특성 = 고른 열(감각)")
	var sense := s0.cols[GraphPanel.C_SENSE][0]
	var yr := v1.y_range()
	t.check(s0.lo[GraphPanel.C_SENSE] == s0.hi[GraphPanel.C_SENSE] and yr.x < sense and yr.y > sense
			and yr.y - yr.x >= sense * UiConfig.num("graph.y_min_span_frac") - 1e-9, "평평한 값(감각 %.1f)도 범위가 생김 %s" % [sense, str(yr)])
	panel.set_show_flows(false)
	panel.set_trait(0)

	# 화면을 거쳐도 역사는 그대로(패널은 읽기만)
	var ref: SimWorld = t.make_world({}, 1, "demo_fast")
	ref.step_n(w.tick)
	t.check(t.same_state(w, ref) == "", "그래프를 붙여 진행해도 상태·해시가 헤드리스와 같음 %s" % t.same_state(w, ref))

	# experiments_changed → 지우고 처음부터
	t.check(lab.new_experiment("default", {}, 2) == "", "새 실험")
	t.check(panel.series.size() == 1 and panel.series_points(0, 0) == 1 and panel.series[0].markers.is_empty(), "새 실험 → 지우고 새 기록 1줄")
	t.check(panel.legend_texts() == PackedStringArray([lab.experiments[0].display_name()]), "범례 = 실험 이름")
	lab.queue_free()
	await t.frames(1)


# ── 비교: 실험 둘을 직접 몬다(LabMain.start_compare 가 뼈대라서) ──
func _compare_checks(t) -> void:
	var a: Experiment = Experiment.create("default", {}, 1).experiment
	var b: Experiment = Experiment.create("demo_fast", {}, 1).experiment
	a.tag = "A"
	b.tag = "B"
	a.step_n(400)
	b.step_n(400)
	var host := Control.new()
	host.theme = UiTheme.build()
	host.size = Vector2(1200, 240)
	t.root.add_child(host)
	var panel := GraphPanel.new()
	host.add_child(panel)
	panel.size = host.size
	panel.load_experiments([a, b])
	t.check(panel.series_points(0, 0) == a.rows().size() and panel.series_points(2, 1) == b.rows().size(), "비교: 두 실험의 점 수")
	t.check(panel.legend_texts() == PackedStringArray([a.display_name(), b.display_name()]) and a.display_name().begins_with("A · "), "범례 = display_name() 둘")
	var items := panel.legend_items()
	t.check(items.size() == 2 and not bool(items[0].dashed) and bool(items[1].dashed)
			and items[0].color == UiConfig.color("graph.series_a") and items[1].color == UiConfig.color("graph.series_b"), "범례 견본: A 실선 series_a · B 점선 series_b")
	# recorded 와 같은 호출로 한 줄씩
	var every := int(a.world.cfg.record.every)
	for i in every:
		if a.step():
			panel.append_row(0, a.rows().back())
		if b.step():
			panel.append_row(1, b.rows().back())
	t.check(panel.series_points(0, 0) == a.rows().size() and panel.series_points(0, 1) == b.rows().size(), "append_row 로 두 실험 모두 한 줄씩 늘어남")
	panel.append_row(5, a.rows().back())
	t.check(panel.series.size() == 2, "없는 실험 번호는 무시")
	panel.redraw_now()
	await t.frames(2)
	var v := panel.view(GraphPanel.GRAPH_POP)
	var solid_a := false
	var dashed_b := false
	for l in v.last_lines:
		if int(l.col) == GraphPanel.C_POP:
			if int(l.series) == 0 and not bool(l.dashed) and int(l.points) > 1:
				solid_a = true
			if int(l.series) == 1 and bool(l.dashed) and int(l.points) > 1:
				dashed_b = true
	t.check(solid_a and dashed_b, "개체 수: A 실선 + B 점선을 그림")
	var civ := panel.view(GraphPanel.GRAPH_CIV)
	t.check(civ.point_px(0, 0, GraphPanel.C_STAGE).y < civ.point_px(1, 0, GraphPanel.C_STAGE).y, "같은 단계여도 A·B 계단선이 겹치지 않게 엇갈림")
	v.layout_now()
	v.hover_at(Vector2(v.data_to_px(200.0), v.plot.get_center().y))
	var lines := v.readout_lines()
	t.check(lines.size() == 3 and str(lines[1].text).begins_with("A ") and str(lines[2].text).begins_with("B "), "값 읽기에 A·B 함께: %s" % v.readout_text())
	panel.set_cursor_tick(300)
	await t.frames(2)
	t.check(panel.cursor_tick == 300 and v.draw_count > 0, "시점 표시 그림")
	panel.load_experiments([])
	await t.frames(2)
	t.check(panel.series.is_empty() and panel.series_points(0, 0) == 0 and v.last_lines.is_empty() and v.draw_count > 0, "실험 없음: 빈 그래프(오류 없음)")
	var one: Experiment = Experiment.create("default", {}, 3).experiment
	panel.load_experiments([one])
	await t.frames(2)
	t.check(v.last_lines.size() == 1 and int(v.last_lines[0].points) == 1, "줄 하나: 점 하나로 그림")
	t.check(panel.x_bounds().y - panel.x_bounds().x >= UiConfig.num("graph.x_min_span_ticks"), "줄 하나여도 가로축 최소 폭")
	host.queue_free()
	await t.frames(1)


# ── 긴 실행: 6,000줄 × 2 — 줄이기와 그리기 시간 ──
func _long_checks(t) -> void:
	var a: Experiment = Experiment.create("default", {}, 1).experiment
	var b: Experiment = Experiment.create("default", {}, 2).experiment
	a.tag = "A"
	b.tag = "B"
	var host := Control.new()
	host.theme = UiTheme.build()
	host.size = Vector2(1600, 260)
	t.root.add_child(host)
	var panel := GraphPanel.new()
	host.add_child(panel)
	panel.size = host.size
	panel.load_experiments([a, b])
	var spike_row := 4321
	for k in 2:
		for i in range(1, LONG_ROWS):
			panel.append_row(k, _row(i, k, spike_row))
	t.check(panel.series_points(0, 0) == LONG_ROWS and panel.series_points(1, 1) == LONG_ROWS, "합성 %d줄 × 2" % LONG_ROWS)
	panel.redraw_now()
	await t.frames(2)
	var full_us := 0
	var pts_ok := true
	for g in 3:
		var v := panel.view(g)
		full_us += v.last_draw_us
		for l in v.last_lines:
			if int(l.points) > 4 * int(v.plot.size.x) + 4:
				pts_ok = false
	var v0 := panel.view(GraphPanel.GRAPH_POP)
	t.check(pts_ok, "줄여 그린 점 ≤ 그림 폭 × 4 (개체 수 A %d점, 폭 %d)" % [int(v0.last_lines[v0.last_lines.size() - 1].points), int(v0.plot.size.x)])
	var flat: Array[int] = []
	for seg in GraphView.run_indices(v0.line_runs(0, GraphPanel.C_POP)):
		for i in seg:
			flat.append(i)
	t.check(flat.has(spike_row), "6,000줄 가운데 한 줄짜리 뾰족한 값도 남음")
	# 가로 범위 안에서 줄을 더하면 묶음을 다시 만들지 않고 새 줄만
	var rebuilt := v0.rebuild_count
	var xb := panel.x_bounds()
	var extra := 0
	var i2 := LONG_ROWS
	while float(i2 * LONG_EVERY) < xb.y and extra < 50:
		panel.append_row(0, _row(i2, 0, spike_row))
		panel.append_row(1, _row(i2, 1, spike_row))
		i2 += 1
		extra += 1
	panel.redraw_now()
	await t.frames(2)
	var inc_us := 0
	for g in 3:
		inc_us += panel.view(g).last_draw_us
	t.check(extra > 0 and v0.rebuild_count == rebuilt and v0.line_runs(0, GraphPanel.C_POP).used == LONG_ROWS + extra, "범위 안 새 줄 %d개: 다시 묶지 않고 더함" % extra)
	print("    그래프 그리기(%d줄 × 2, 세 그래프 합): 처음 %d µs · 새 줄만 %d µs" % [LONG_ROWS, full_us, inc_us])
	t.check(inc_us < DRAW_BOUND_US, "새 줄 뒤 그리기 %d µs < %d µs" % [inc_us, DRAW_BOUND_US])
	host.queue_free()
	await t.frames(1)


## 합성 기록 줄(k 번째 실험의 i 번째)
func _row(i: int, k: int, spike_row: int) -> Dictionary:
	var f := float(i)
	var pop := 120.0 + 60.0 * sin(f * 0.011 + float(k)) + float((i * 31) % 17)
	if i == spike_row and k == 0:
		pop = 900.0
	return {tick = i * LONG_EVERY, population = int(pop), births = (i * 7) % 11, deaths = (i * 5) % 9, mean_gen = f * 0.02,
			mean_size = 1.0 + 0.05 * sin(f * 0.003), mean_sense = 3.0, mean_energy = 12.0 + sin(f * 0.02), mean_age = 90.0,
			civ_stage = mini(3, i / 1500), storehouses = mini(8, i / 600), farms = maxi(0, i / 40 - 60)}
