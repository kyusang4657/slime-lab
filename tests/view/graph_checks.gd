extends RefCounted
## GraphPanel·GraphView 검사(헤드리스). tests/run_view_tests.gd 가 불러 run(t) 을 부른다.
## LabMain 의 자리 채우기는 통합 때 연결되므로, 여기서는 패널을 직접 lab.bottom_dock 에 넣고 bind_lab 한다.
## 비교 모드는 패널 단위로(LabMain.start_compare 를 거친 종단은 integration4_checks), 실험 둘을 직접 만들어 LabMain 이 내는 것과 같은 호출로 몬다:
##   x.tag = "A"/"B" → panel.load_experiments([a, b])(= experiments_changed) → 진행할 때마다 append_row(k, rows().back())(= recorded).

const MIN_CHECKS := 148
## 합성 줄 수(긴 실행 흉내: 실험 둘 × 이만큼)와 그 줄 간격(틱)
const LONG_ROWS := 6000
const LONG_EVERY := 20
const DEMO_TICKS := 1700


func run(t) -> void:
	_static_checks(t)
	_color_checks(t)
	_series_checks(t)
	await _lab_checks(t)
	await _compare_checks(t)
	await _gen_compare_checks(t)
	await _extinct_compare_checks(t)
	await _narrow_checks(t)
	await _x_label_checks(t)
	await _synthetic_checks(t)
	await _snapshot_note_checks(t)
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
	_dash_checks(t, gv)
	_y_tick_checks(t, gv)
	gv.free()


## 점선(B): 한 열 안의 뾰족한 값이 무늬 자리(끔 구간)에 들어도 꼭짓점까지 그림(G21), 모두 틈에 든 조각은 빈 결과(G24)
func _dash_checks(t, gv: GraphView) -> void:
	var dash := UiConfig.num("graph.dash_px")
	var gap := UiConfig.num("graph.dash_gap_px")
	var period := dash + gap
	gv.plot = Rect2(0, 0, 300, 120)
	# 무늬 자리 10곳(한 칸 = dash + gap)마다: 한 열 안의 오르내림(바닥 → 꼭짓점 → 바닥)과 꼭짓점에서 끝나는 가파른 조각
	var spike_ok := true
	var end_ok := true
	var worst := 0.0
	for p in 10:
		var x0 := 30.0 + period * float(p) / 10.0
		var d1 := gv._xdash(PackedVector2Array([Vector2(x0, 100), Vector2(x0 + 0.3, 40), Vector2(x0 + 0.6, 100)]))
		var top := INF
		for q in d1:
			top = minf(top, q.y)
		spike_ok = spike_ok and top <= 40.0 + 0.01
		var d2 := gv._xdash(PackedVector2Array([Vector2(x0, 100), Vector2(x0 + 3.0, 20)]))
		var top2 := INF
		for q in d2:
			top2 = minf(top2, q.y)
		worst = maxf(worst, top2 - 20.0)
		end_ok = end_ok and top2 <= 20.0 + gap + 0.01
	t.check(spike_ok, "점선: 한 열 안의 뾰족한 값은 무늬 자리 10곳 모두 꼭짓점까지 그림")
	t.check(end_ok, "점선: 꼭짓점에서 끝나는 가파른 조각도 무늬 자리와 무관하게 꼭짓점 dash_gap 안까지(가장 나쁜 %.1fpx)" % worst)
	# 무늬 틈에 통째로 든 짧은 가로 조각 → 빈 결과(그리기 쪽은 draw_multiline 을 부르지 않음 — 아래 비교 검사)
	var g := gv._xdash(PackedVector2Array([Vector2(dash + 0.5, 10), Vector2(dash + 2.0, 10)]))
	t.check(g.is_empty(), "점선: 틈에 든 짧은 가로 조각은 빈 결과")


## 세로 눈금: 많아야 y_ticks_max 개, 간격 ≥ y_tick_min_px — 평평한 값·거의 평평한 값도(G46). 그림이 간격 둘보다 낮으면
## 간격은 보지 않음(0 을 사이에 둔 자료는 늘 두 칸 이상이라 그보다 낮은 그림에서는 지킬 수 없음 — 실제 그래프는 90px 이상).
func _y_tick_checks(t, gv: GraphView) -> void:
	var tmax := UiConfig.integer("graph.y_ticks_max")
	var tmin := UiConfig.num("graph.y_tick_min_px")
	var cases: Array[Vector4] = [Vector4(3.0, 3.0, 0, 0), Vector4(0.978, 1.004, 0, 0), Vector4(0.998, 1.0005, 0, 0), Vector4(1.0, 1.0, 0, 0),
			Vector4(0.0, 263.0, 1, 1), Vector4(0.0, 1.0, 1, 1), Vector4(12.3, 97.1, 0, 0), Vector4(-4.2, 3.3, 0, 0), Vector4(0.0, 87.0, 1, 1),
			Vector4(40.0, 230.0, 0, 0), Vector4(0.0, 12345.0, 1, 1)]
	var bad := PackedStringArray()
	for c in cases:
		for h: float in [30.0, 60.0, 90.0, 120.0, 150.0, 200.0, 260.0]:
			gv._set_y_range(c.x, c.y, c.z > 0.5, c.w > 0.5, h)
			var n := gv._y_ticks.size()
			var spacing := h / float(maxi(1, n - 1))
			if n > tmax or n < 2 or (h >= 2.0 * tmin and spacing < tmin - 1e-6):
				bad.append("%s~%s h%d → %d개" % [str(c.x), str(c.y), int(h), n])
	t.check(bad.is_empty(), "세로 눈금 ≤ %d개·간격 ≥ %dpx (평평한 3.0 · 0.978~1.004 등) %s" % [tmax, int(tmin), ", ".join(bad)])
	gv._set_y_range(3.0, 3.0, false, false, 120.0)
	t.check(gv._y_ticks.size() <= tmax and gv._y_ticks[0] < 3.0 and gv._y_ticks[gv._y_ticks.size() - 1] > 3.0,
			"평평한 3.0(높이 120): 눈금 %s" % str(gv._y_ticks))
	t.check(is_equal_approx(GraphView.next_nice(1.0), 2.0) and is_equal_approx(GraphView.next_nice(2.0), 2.5) and is_equal_approx(GraphView.next_nice(2.0, true), 5.0)
			and is_equal_approx(GraphView.next_nice(0.05), 0.1) and is_equal_approx(GraphView.next_nice(250.0), 500.0), "다음 눈금 간격(1·2·2.5·5 × 10^k)")


# ── 실험 색(G32): A·B 는 뜻 색(경고·강조·위험)과도 구별되고 색각 이상에도 안전, 이름표 글자가 읽힘 ──
## dataviz 검사기와 같은 식: OKLab 거리 × 100, 색각 이상은 Machado-Oliveira-Fernandes(2009) 심도 1.0(제1·제2 색맹 중 작은 값).
## 문턱: 정상 시각 ≥ 15, 색각 이상 ≥ 8, 바탕 대비 ≥ 4.5(이름표 = 실험 색 바탕 + 바탕색 굵은 글자).
const MACHADO := {
	"protan": [Vector3(0.152286, 1.052583, -0.204868), Vector3(0.114503, 0.786281, 0.099216), Vector3(-0.003882, -0.048116, 1.051998)],
	"deutan": [Vector3(0.367322, 0.860646, -0.227968), Vector3(0.280085, 0.672501, 0.047413), Vector3(-0.011820, 0.042940, 0.968881)],
}


func _color_checks(t) -> void:
	var a := UiConfig.color("graph.series_a")
	var b := UiConfig.color("graph.series_b")
	var bg := UiTheme.color("background")
	var bad := PackedStringArray()
	for pair in [["A", a], ["B", b]]:
		var c: Color = pair[1]
		for key in ["warn", "accent", "danger"]:
			var s := UiTheme.color(key)
			var dn := _de(c, s, "")
			var dc := minf(_de(c, s, "protan"), _de(c, s, "deutan"))
			if dn < 15.0 or dc < 8.0:
				bad.append("%s↔%s 정상 %.1f 색각 %.1f" % [pair[0], key, dn, dc])
		var lc := c.srgb_to_linear().get_luminance()
		var lb := bg.srgb_to_linear().get_luminance()
		var con := (maxf(lc, lb) + 0.05) / (minf(lc, lb) + 0.05)
		if con < 4.5:
			bad.append("%s 바탕 대비 %.2f" % [pair[0], con])
	var births := UiConfig.color("graph.births")
	for p in [[a, b], [a, births], [b, births]]:
		if _de(p[0], p[1], "") < 15.0 or minf(_de(p[0], p[1], "protan"), _de(p[0], p[1], "deutan")) < 8.0:
			bad.append("%s↔%s" % [Color(p[0]).to_html(false), Color(p[1]).to_html(false)])
	t.check(bad.is_empty(), "실험 색 A %s · B %s: 경고·강조·위험·출생 색과 정상 ΔE ≥ 15·색각 이상 ΔE ≥ 8, 바탕 대비 ≥ 4.5 %s"
			% [a.to_html(false), b.to_html(false), ", ".join(bad)])


## 두 색의 OKLab 거리 × 100(kind = "" 정상, "protan"·"deutan" 모의)
static func _de(c1: Color, c2: Color, kind: String) -> float:
	return 100.0 * _oklab(_sim(c1, kind)).distance_to(_oklab(_sim(c2, kind)))


static func _sim(c: Color, kind: String) -> Vector3:
	var l := Vector3(_s2lin(c.r), _s2lin(c.g), _s2lin(c.b))
	if kind == "":
		return l
	var m: Array = MACHADO[kind]
	var r0: Vector3 = m[0]
	var r1: Vector3 = m[1]
	var r2: Vector3 = m[2]
	return Vector3(clampf(r0.dot(l), 0.0, 1.0), clampf(r1.dot(l), 0.0, 1.0), clampf(r2.dot(l), 0.0, 1.0))


static func _s2lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _oklab(l: Vector3) -> Vector3:
	var lm := pow(0.4122214708 * l.x + 0.5363325363 * l.y + 0.0514459929 * l.z, 1.0 / 3.0)
	var mm := pow(0.2119034982 * l.x + 0.6806995451 * l.y + 0.1073969566 * l.z, 1.0 / 3.0)
	var sm := pow(0.0883024619 * l.x + 0.2817188376 * l.y + 0.6299787005 * l.z, 1.0 / 3.0)
	return Vector3(0.2104542553 * lm + 0.7936177850 * mm - 0.0040720468 * sm,
			1.9779984951 * lm - 2.4285922050 * mm + 0.4505937099 * sm,
			0.0259040371 * lm + 0.7827717662 * mm - 0.8086757660 * sm)


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

	# 출생·사망 = flow_per_ticks 틱당(G20): 기록 간격 20 과 100 의 같은 빠르기가 같은 값
	var w := UiConfig.num("graph.flow_per_ticks")
	var fa := _flow_series(20, 4, 3, 30)
	var fb := _flow_series(100, 20, 15, 6)
	var rate_ok := true
	for i in range(1, fb.size()):
		var ra := fa.tick.find(fb.tick[i])
		rate_ok = rate_ok and is_equal_approx(fb.cols[GraphPanel.C_BIRTHS][i], fa.cols[GraphPanel.C_BIRTHS][ra])
		rate_ok = rate_ok and is_equal_approx(fb.cols[GraphPanel.C_DEATHS][i], fa.cols[GraphPanel.C_DEATHS][ra])
	t.check(rate_ok and is_equal_approx(fa.cols[GraphPanel.C_BIRTHS][5], 4.0 * w / 20.0) and is_equal_approx(fb.hi[GraphPanel.C_BIRTHS], fa.hi[GraphPanel.C_BIRTHS]),
			"출생·사망은 %d틱당: 기록 간격 20(출생 4) = 간격 100(출생 20) → %s / %s" % [int(w), str(fa.cols[GraphPanel.C_BIRTHS][5]), str(fb.cols[GraphPanel.C_BIRTHS][3])])

	# 세대 축 가장 가까운 줄(G07): 정렬해 둔 값의 이분 탐색 = 모두 훑기(차이가 같으면 뒤 줄), 되돌아가는 값·같은 값·멸종 뒤 이어 씀
	var gs := GraphPanel.Series.new(null)
	var gen := 0.0
	for i in 400:
		gen += 0.05 * sin(float(i) * 0.31) + 0.03
		var g := snappedf(gen, 0.05)
		var pop := 0 if i >= 380 else 10
		gs.append({tick = i * 20, population = pop, mean_gen = g})
	var near_ok := true
	var sorted_ok := true
	for i in gs.gen_sorted.size() - 1:
		sorted_ok = sorted_ok and (gs.gen_sorted[i] < gs.gen_sorted[i + 1] or (gs.gen_sorted[i] == gs.gen_sorted[i + 1] and gs.gen_order[i] < gs.gen_order[i + 1]))
	for q in 300:
		var x := gs.gen_lo - 0.3 + (gs.gen_hi - gs.gen_lo + 0.6) * float(q) / 299.0
		if q % 7 == 0:
			x = gs.gen_x[(q * 13) % gs.size()]
		elif q % 11 == 0:
			x = (gs.gen_x[(q * 17) % gs.size()] + gs.gen_x[(q * 5) % gs.size()]) * 0.5
		near_ok = near_ok and gs.nearest_gen_row(x) == _brute_nearest(gs.gen_x, x)
	t.check(sorted_ok and near_ok and gs.gen_sorted.size() == gs.size(), "세대 축 가장 가까운 줄: 이분 탐색 = 모두 훑기(300곳, 같은 값·되돌아감·멸종 포함)")


## 기록 간격 every 틱마다 출생 births·사망 deaths 인 합성 기록 n 줄
func _flow_series(every: int, births: int, deaths: int, n: int) -> GraphPanel.Series:
	var s := GraphPanel.Series.new(null)
	for i in n:
		s.append({tick = i * every, population = 50, births = births if i > 0 else 0, deaths = deaths if i > 0 else 0, mean_gen = 1.0})
	return s


## 모두 훑어 차이가 가장 작은 줄(같으면 뒤 줄) — 예전 세대 축 방식
func _brute_nearest(gx: PackedFloat64Array, x: float) -> int:
	var best := 0
	var best_d := INF
	for i in gx.size():
		var d := absf(gx[i] - x)
		if d <= best_d:
			best_d = d
			best = i
	return best


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
	# 저장고·밭이 아직 0 이면 띠의 범위 글을 쓰지 않음(예전: 아무것도 없는데 "1" 이 선 끝 옆에, G12)
	panel.redraw_now()
	await t.frames(2)
	t.check(panel.view(GraphPanel.GRAPH_CIV).last_lane_labels.is_empty() and panel.series[0].hi[GraphPanel.C_STORES] == 0.0,
			"저장고·밭 0 → 띠 범위 글 없음(거짓 \"1\" 없음)")
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
	# 시점 표시선이 실제로 그 틱 자리에 그려짐(G40 — 예전 검사는 cursor_tick 값만 봄): 세 그래프 모두, -1·범위 밖이면 없음
	lab.request_cursor(200)
	await t.frames(2)
	var cur_ok := true
	for g in 3:
		var vg := panel.view(g)
		cur_ok = cur_ok and vg.last_cursor.size() == 1 and int(vg.last_cursor[0].tick) == 200 and int(vg.last_cursor[0].series) == -1 \
				and is_equal_approx(float(vg.last_cursor[0].x), roundf(vg.data_to_px(200.0)))
	t.check(cur_ok, "시점 표시선이 세 그래프 모두 틱 200 자리에 그려짐 (%s)" % str(panel.view(0).last_cursor))
	# 이름 상자("틱 200")는 계열 선을 다 그린 뒤(선이 상자를 덮지 않게 — I46)
	var on_top := true
	for g in 3:
		on_top = on_top and _labels_on_top(panel.view(g), panel.view(g).last_cursor)
	t.check(on_top, "시점 이름 상자를 계열 선보다 뒤에 그림(선 위) — 세 그래프 %s" % _seq_text(panel.view(GraphPanel.GRAPH_CIV), panel.view(GraphPanel.GRAPH_CIV).last_cursor))
	lab.request_cursor(99999)
	await t.frames(2)
	var off_ok := panel.view(0).last_cursor.is_empty()
	lab.request_cursor(-1)
	await t.frames(2)
	t.check(off_ok and panel.view(0).last_cursor.is_empty() and panel.view(2).last_cursor.is_empty(), "범위 밖 틱·-1 → 시점 표시선 없음")

	# 발견: demo_fast·씨앗 1 은 1,037틱에 농사까지(DEMO_TICKS 안)
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
	# 저장고·밭 띠의 범위 글(G12): "0~N" 꼴, 그 띠 상자 안 세로 가운데(아래 띠의 글이 위 띠 선 끝 옆에 붙지 않음)
	var lane_ok := v2.last_lane_labels.size() >= 1 and s0.hi[GraphPanel.C_STORES] > 0.0
	for ll in v2.last_lane_labels:
		var lr: Rect2 = v2._lane_rects[int(ll.lane)]
		var rc: Rect2 = ll.rect
		lane_ok = lane_ok and str(ll.text).begins_with("0~") and rc.get_center().y > lr.position.y + 1.0 and rc.get_center().y < lr.end.y - 1.0
		if int(ll.lane) == 1:
			lane_ok = lane_ok and rc.position.y > v2._lane_rects[0].end.y + 0.5
	t.check(lane_ok, "저장고·밭 띠 범위 글 = \"0~N\", 자기 띠 안 (%s)" % str(v2.last_lane_labels.map(func(d: Dictionary) -> String: return str(d.text))))

	# 마우스는 마우스 겹만 다시 그림(G23), 마우스 값은 가로 값이 바뀔 때 한 번만 계산(G07)
	var v0 := panel.view(GraphPanel.GRAPH_POP)
	await _hover_cost_checks(t, panel, "틱 축")
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
	# 세대 축의 시점 표시 = 그 사건의 평균 세대(G06): 발견 틱이면 발견 세로선과 같은 자리, 다른 사건이면 그 연대기 줄의 평균 세대
	# (예전: 가장 가까운 기록 줄의 세대 — 발견 세로선과 어긋남)
	var mk_store := s0.marker_for(SimWorld.STAGE_STORE)
	lab.request_cursor(int(mk_store.tick))
	await t.frames(2)
	var lc := v2.last_cursor
	t.check(lc.size() == 1 and is_equal_approx(float(lc[0].data_x), float(mk_store.gen))
			and is_equal_approx(float(lc[0].x) + 0.5, float(v2.last_markers.filter(func(m: Dictionary) -> bool: return int(m.stage) == SimWorld.STAGE_STORE)[0].x)),
			"세대 축 시점 표시(저장 발견 틱) = 발견 세로선 자리 %s" % str(lc))
	var ev := {}
	for e: Dictionary in w.chronicle:
		if str(e.kind) != "discovery" and str(e.kind) != "extinction" and s0.markers.all(func(m: Dictionary) -> bool: return float(m.tick) != float(e.tick)) \
				and int(e.tick) > int(s0.tick[1]):
			ev = e
			break
	lab.request_cursor(int(ev.get("tick", -1)))
	await t.frames(2)
	t.check(not ev.is_empty() and v2.last_cursor.size() == 1 and is_equal_approx(float(v2.last_cursor[0].data_x), float(ev.mean_gen)),
			"세대 축 시점 표시(%s, 틱 %s) = 그 연대기 사건의 평균 세대 %s" % [str(ev.get("kind")), str(ev.get("tick")), str(ev.get("mean_gen"))])
	lab.request_cursor(-1)
	await _hover_cost_checks(t, panel, "세대 축")
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
	var thin_ok := true
	for l in v0.last_lines:
		if int(l.col) == GraphPanel.C_BIRTHS or int(l.col) == GraphPanel.C_DEATHS:
			thin_ok = thin_ok and is_equal_approx(float(l.width), UiConfig.num("graph.thin_width"))
	t.check(thin_ok, "출생·사망 선 굵기 = graph.thin_width")
	# 출생·사망 단위가 그래프에 보임(G20): 값 읽기 머리 "· 출생·사망 20틱당", 위쪽 띠 견본(단위는 들어갈 폭이면 — 넓은 그래프는 _synthetic_checks)
	v0.hover_at(Vector2(v0.data_to_px(s0.tick[row]), v0.plot.get_center().y))
	var unit := panel.flow_unit()
	var head0: String = str(v0.readout_lines()[0].text) if not v0.readout_lines().is_empty() else ""
	t.check(v0.last_flow_key.contains("출생") and v0.last_flow_key.contains("사망") and head0.ends_with("출생·사망 %s" % unit),
			"출생·사망 단위: 견본 \"%s\" · 값 읽기 \"%s\"" % [v0.last_flow_key, v0.readout_text()])
	panel.clear_hover()
	t.check(v0.y_range().y >= s0.hi[GraphPanel.C_BIRTHS] and v0.y_range().x == 0.0, "개체 수 세로축은 0 부터, 출생 최댓값 포함")
	t.check(v1.last_lines.size() == 1 and int(v1.last_lines[0].col) == GraphPanel.C_SENSE, "평균 특성 = 고른 열(감지)")
	# 같은 특성의 이름 = 정보 창·README 의 "감지"(I51: 그래프만 "감각") — 고르기 항목과 값 읽기 글
	var trait_opt := _find_named(panel, "Trait") as OptionButton
	v1.hover_at(Vector2(v1.data_to_px(s0.tick[row]), v1.plot.get_center().y))
	var sense_txt := v1.readout_text()
	panel.clear_hover()
	t.check(trait_opt != null and trait_opt.get_item_text(trait_opt.selected) == "감지" and sense_txt.contains("감지 ") and not sense_txt.contains("감각"),
			"평균 특성 이름 \"감지\"(고르기 · 값 읽기 \"%s\")" % sense_txt)
	var sense := s0.cols[GraphPanel.C_SENSE][0]
	var yr := v1.y_range()
	t.check(s0.lo[GraphPanel.C_SENSE] == s0.hi[GraphPanel.C_SENSE] and yr.x < sense and yr.y > sense
			and yr.y - yr.x >= sense * UiConfig.num("graph.y_min_span_frac") - 1e-9, "평평한 값(감지 %.1f)도 범위가 생김 %s" % [sense, str(yr)])
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
	await _keyboard_checks(t, lab, panel)
	await _cursor_tail_checks(t, lab, panel)
	lab.queue_free()
	await t.frames(1)


## 마지막 기록 줄 뒤에 난 사건(I15): 사건은 기록 간격(20틱) 사이에도 난다. 멈춘 채 연대기의 최신 줄을 누르면(실제 경로 —
## ChroniclePanel.activate_item → lab.request_cursor) 가로축이 그 틱까지 넓어져 세 그래프 모두 세로선이 그려져야 한다
## (예전: 가로축 끝 = 마지막 기록 줄이라 cursor_tick 만 바뀌고 선이 없었음 — 시연용 씨앗 2 의 틱 126 저장고 등).
func _cursor_tail_checks(t, lab: LabMain, panel: GraphPanel) -> void:
	t.check(lab.new_experiment("demo_fast", {}, 2) == "", "시연용 씨앗 2 새 실험")
	lab.set_paused(true)
	var w := lab.experiments[0].world
	var s := panel.series[0]
	var ev := {}
	var guard := 0
	while ev.is_empty() and guard < 3000:
		lab.step_ticks(1)
		guard += 1
		if w.chronicle.is_empty():
			continue
		var e: Dictionary = w.chronicle.back()
		if float(e.tick) > s.tick[s.size() - 1] and float(e.tick) > panel.x_bounds().y:
			ev = e
	t.check(not ev.is_empty(), "준비: 가로축 끝(%s)을 넘는 최신 사건 %s (세계 틱 %d)" % [str(panel.x_bounds()), str(ev.get("kind")), w.tick])
	if ev.is_empty():
		return
	# 멈춘 채 한 프레임: 쌓인 사건을 연대기로(LabMain 은 프레임마다 drain_events → events_tagged)
	lab.set_paused(true)
	var tick0 := w.tick
	lab.advance_frame(1.0 / 60.0)
	t.check(w.tick == tick0 and s.tick[s.size() - 1] < float(ev.tick), "멈춘 프레임은 틱을 진행하지 않음(틱 %d, 마지막 기록 줄 %d)" % [w.tick, int(s.tick[s.size() - 1])])
	# 그래프가 지금 기록 줄로 한 번 그려진 뒤에 누름(배치가 그대로인 채 시점만 바뀌어도 가로축을 다시 정해야 함)
	panel.redraw_now()
	await t.frames(2)
	var cp := lab.chronicle_panel
	var idx := -1
	if cp != null:
		cp.set_filter(ChroniclePanel.FILTER_ALL)
		for i in cp.item_count():
			if int(cp.item(i).tick) == int(ev.tick):
				idx = i
				break
	t.check(idx >= 0, "연대기에 그 사건 줄(틱 %d)" % int(ev.tick))
	if idx < 0:
		return
	cp.activate_item(idx)
	await t.frames(2)
	var drawn := 0
	for g in 3:
		var vg := panel.view(g)
		if vg.last_cursor.size() == 1 and int(vg.last_cursor[0].tick) == int(ev.tick) and float(vg.last_cursor[0].x) <= vg.plot.end.x + 0.5 \
				and is_equal_approx(float(vg.last_cursor[0].x), roundf(vg.data_to_px(float(ev.tick)))):
			drawn += 1
	t.check(panel.cursor_tick == int(ev.tick) and drawn == 3 and panel.x_bounds().y >= float(ev.tick),
			"마지막 기록 줄(틱 %d) 뒤 사건(틱 %d) 줄을 누르면 세 그래프 모두 시점 세로선(%d개, 가로축 %s)" % [int(s.tick[s.size() - 1]), int(ev.tick), drawn, str(panel.x_bounds())])
	# 세대 축: 그 사건의 평균 세대(연대기 줄 값)가 마지막 기록 줄의 세대보다 커도 세로선이 그려짐
	panel.set_x_axis(GraphPanel.X_GEN)
	await t.frames(2)
	var gdrawn := 0
	for g in 3:
		var vg := panel.view(g)
		if vg.last_cursor.size() == 1 and is_equal_approx(float(vg.last_cursor[0].data_x), float(ev.mean_gen)):
			gdrawn += 1
	t.check(gdrawn == 3, "세대 축에서도 세 그래프 모두 그 사건의 세대(%s)에 세로선(%d개, 가로축 %s · 마지막 줄 %.2f세대)"
			% [str(ev.mean_gen), gdrawn, str(panel.x_bounds()), s.gen_x[s.size() - 1]])
	panel.set_x_axis(GraphPanel.X_TICK)
	# 시점을 지우면 가로축이 다시 기록 줄 범위로
	lab.request_cursor(-1)
	await t.frames(1)
	t.check(panel.x_bounds().y < float(ev.tick), "시점을 지우면 가로축 끝이 다시 기록 줄 범위(%s)" % str(panel.x_bounds()))


## 이름(시점·멸종)이 이 그래프의 모든 계열 선보다 뒤에 그려졌는지(seq — I46)
func _labels_on_top(v: GraphView, labels: Array[Dictionary]) -> bool:
	if labels.is_empty() or v.last_lines.is_empty():
		return false
	var last_line := 0
	for l in v.last_lines:
		last_line = maxi(last_line, int(l.seq))
	for d in labels:
		if int(d.seq) <= last_line:
			return false
	return true


func _seq_text(v: GraphView, labels: Array[Dictionary]) -> String:
	return "선 %s · 이름 %s" % [str(v.last_lines.map(func(l: Dictionary) -> int: return int(l.seq))), str(labels.map(func(d: Dictionary) -> int: return int(d.seq)))]


## 키보드(J16): 가로축 틱/세대·출생·사망·평균 특성 고르기는 키보드 초점을 받는다(Tab 으로 닿음). 초점이 있어도 스페이스는
## 실험실 멈춤(LabMain._input 이 GUI 보다 먼저 받음 — 단추가 눌리지 않음), Enter 는 누름. 마우스로 누르면 초점을 남기지 않음.
func _keyboard_checks(t, lab: LabMain, panel: GraphPanel) -> void:
	var bad: Array[String] = []
	for n in ["XTick", "XGen", "Flows", "Trait"]:
		var c := _find_named(panel, n) as Control
		if c == null or c.focus_mode != Control.FOCUS_ALL:
			bad.append(n)
	t.check(bad.is_empty(), "그래프 조작(가로축·출생·사망·평균 특성)이 키보드 초점을 받음(못 받음: %s)" % ", ".join(bad))
	var flows := _find_named(panel, "Flows") as Button
	if flows == null:
		return
	lab.set_paused(true)
	flows.grab_focus()
	await t.frames(1)
	var on0 := flows.button_pressed
	_key(t, KEY_SPACE)
	t.check(flows.has_focus() and not lab.is_paused() and flows.button_pressed == on0, "출생·사망 단추 초점에서 스페이스 = 재생/멈춤(단추 안 눌림)")
	_key(t, KEY_ENTER)
	t.check(flows.button_pressed != on0 and panel.show_flows == flows.button_pressed and flows.has_focus(), "Enter → 출생·사망 켜고 끔·초점 그대로")
	_key(t, KEY_ENTER)
	# 마우스로 누르려면 단추가 창 안에 있어야 함(헤드리스 기본 창은 작음)
	var root0: Vector2i = t.root.size
	t.root.size = Vector2i(UiConfig.integer("lab.min_width"), UiConfig.integer("lab.min_height"))
	await t.frames(3)
	flows.grab_focus()
	_click(t, flows.get_global_rect().get_center())
	await t.frames(1)
	t.check(flows.button_pressed != on0 and not flows.has_focus(), "마우스로 누르면 출생·사망 켜짐·초점을 남기지 않음")
	t.root.size = root0
	panel.set_show_flows(on0)
	lab.set_paused(true)


func _find_named(n: Node, node_name: String) -> Node:
	return n.find_child(node_name, true, false)


func _key(t, code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = 32 if code == KEY_SPACE and pressed else 0
		e.pressed = pressed
		t.root.push_input(e)


func _click(t, pos: Vector2) -> void:
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = pos
		mb.global_position = pos
		t.root.push_input(mb)


## 마우스가 움직일 때: 선·눈금 그래프(GraphView)는 다시 그리지 않고 마우스 겹만(G23), 마우스 값 계산은 한 번(G07 —
## 예전엔 그리기마다 세 그래프 + 값 읽기가 각자 4번, 세대 축은 매번 모든 줄을 훑음), 세로로만·같은 줄 안이면 아무것도 안 그림.
func _hover_cost_checks(t, panel: GraphPanel, what: String) -> void:
	panel.redraw_now()
	await t.frames(2)
	var v0 := panel.view(GraphPanel.GRAPH_POP)
	var s0 := panel.series[0]
	var draws: Array[int] = []
	var hovers: Array[int] = []
	for g in 3:
		draws.append(panel.view(g).draw_count)
		hovers.append(panel.view(g).hover_draw_count())
	var comp0 := panel.hover_computes
	var px := v0.data_to_px(panel.row_x(0, s0.size() * 2 / 3))
	var r := panel.nearest_row(0, v0.px_to_data(px))
	# 같은 줄로 남는 작은 가로 움직임
	var nudge := 0.0
	for dx: float in [0.2, -0.2, 0.05, -0.05]:
		if panel.nearest_row(0, v0.px_to_data(px + dx)) == r:
			nudge = dx
			break
	v0.hover_at(Vector2(px, v0.plot.get_center().y))
	await t.frames(2)
	var same_draw := true
	var hover_once := true
	for g in 3:
		same_draw = same_draw and panel.view(g).draw_count == draws[g]
		hover_once = hover_once and panel.view(g).hover_draw_count() == hovers[g] + 1
	t.check(same_draw and hover_once and panel.hover_rows()[0] == r and v0.readout_text() != "",
			"%s 마우스: 선 그래프는 그대로, 세 그래프의 마우스 겹만 한 번씩 다시 그림" % what)
	t.check(panel.hover_computes - comp0 == 1, "%s 마우스 값 계산 한 번(세 그래프·값 읽기가 나눠 씀): %d번" % [what, panel.hover_computes - comp0])
	# 세로로만, 그리고 같은 줄 안(0.2px)에서 움직이면 다시 그리지 않음
	v0.hover_at(Vector2(px, v0.plot.position.y + 2.0))
	v0.hover_at(Vector2(px + nudge, v0.plot.end.y - 2.0))
	await t.frames(2)
	var still := true
	for g in 3:
		still = still and panel.view(g).draw_count == draws[g] and panel.view(g).hover_draw_count() == hovers[g] + 1
	t.check(still and panel.hover_rows()[0] == r, "%s 세로로만·같은 줄 안에서 움직이면 다시 그리지 않음" % what)
	panel.clear_hover()
	await t.frames(1)


# ── 비교: 실험 둘을 직접 몬다(패널 단위 — start_compare 를 거친 종단은 integration4_checks) ──
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
	# 점 수는 그 그래프가 그리는 것(그림 폭에 따름 — I38)이라 자리를 잡은 뒤에 센다
	await t.frames(1)
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
	# 시점 표시(G40: 예전 검사는 cursor_tick 값과 draw_count > 0 만 봐서 선을 안 그려도 통과): 틱 축은 세로선 하나가 그 틱 자리에
	panel.set_cursor_tick(300)
	await t.frames(2)
	var cur_ok := true
	for g in 3:
		var vg := panel.view(g)
		cur_ok = cur_ok and vg.last_cursor.size() == 1 and is_equal_approx(float(vg.last_cursor[0].x), roundf(vg.data_to_px(300.0)))
	t.check(panel.cursor_tick == 300 and cur_ok, "비교 틱 축 시점 표시: 세 그래프에 세로선 하나씩, 틱 300 자리 %s" % str(v.last_cursor))
	panel.set_cursor_tick(-1)
	await t.frames(2)
	t.check(v.last_cursor.is_empty(), "시점 표시 -1 → 세로선 없음")
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


## 패널을 따로 띄울 자리(테마 + 크기)
func _host(t, sz: Vector2) -> Control:
	var host := Control.new()
	host.theme = UiTheme.build()
	host.size = sz
	t.root.add_child(host)
	return host


# ── 세대 축 비교: A 는 일찍 멸종(자원 없음), B 는 시연용 — 마우스·시점 표시가 A 의 줄에 묶이지 않음(G05·G06) ──
func _gen_compare_checks(t) -> void:
	var a: Experiment = Experiment.create("no_resources", {}, 1).experiment
	var b: Experiment = Experiment.create("demo_fast", {}, 1).experiment
	a.tag = "A"
	b.tag = "B"
	a.step_n(DEMO_TICKS)
	b.step_n(DEMO_TICKS)
	var host := _host(t, Vector2(1200, 240))
	var panel := GraphPanel.new()
	host.add_child(panel)
	panel.size = host.size
	panel.load_experiments([a, b])
	panel.set_x_axis(GraphPanel.X_GEN)
	await t.frames(2)
	var sa := panel.series[0]
	var sb := panel.series[1]
	t.check(sa.extinct_row >= 0 and sb.gen_hi > sa.gen_hi + 2.0, "준비: A 멸종(최고 %.2f세대), B 는 %.2f세대까지" % [sa.gen_hi, sb.gen_hi])
	# 마우스: A 가 이르지 못한 세대(B 의 범위 70% 자리)
	var v := panel.view(GraphPanel.GRAPH_POP)
	v.layout_now()
	var gx := sb.gen_lo + (sb.gen_hi - sb.gen_lo) * 0.7
	var mouse := v.data_to_px(gx)
	v.hover_at(Vector2(mouse, v.plot.get_center().y))
	await t.frames(2)
	var st := panel.hover_state()
	var lines := v.readout_lines()
	t.check(st.anchor == 1 and absf(v.last_hover_px - mouse) <= UiConfig.num("graph.hover_gap_px") + 1.0,
			"세대 축 비교 마우스: 세로선이 마우스 자리(%.1f ↔ %.1f — A 의 마지막 줄로 튀지 않음)" % [v.last_hover_px, mouse])
	t.check(lines.size() == 3 and str(lines[0].text) == "평균 %s세대" % GraphView.fmt_num(st.anchor_x, 1) and absf(st.anchor_x - gx) < 0.5,
			"머리 = 마우스 자리의 세대: %s" % v.readout_text())
	t.check(lines.size() == 3 and str(lines[1].text).begins_with("A ") and str(lines[1].text).contains(GraphView.EXTINCT_TEXT)
			and not str(lines[1].text).contains("개체") and not bool(lines[1].valid) and st.valid[0] == 0,
			"A 줄 = 이 세대 기록 없음(멸종 틱·세대) — 멸종 전 값을 이 세대 값처럼 보이지 않음: %s" % (str(lines[1].text) if lines.size() > 1 else ""))
	var rb := st.rows[1]
	t.check(lines.size() == 3 and str(lines[2].text).contains("(%s세대 · 틱 %s)" % [GraphView.fmt_num(sb.gen_x[rb], 1), GraphView.fmt_num(sb.tick[rb], 0)]),
			"B 줄 = 자기 줄의 세대·틱: %s" % (str(lines[2].text) if lines.size() > 2 else ""))
	panel.clear_hover()
	# 시점 표시: B 의 농사 발견 틱 → B 의 세로선 = B 의 발견 세로선 자리(예전: A 의 그 틱 세대에), A 는 그 틱의 A 세대(멸종한 세대)
	var civ := panel.view(GraphPanel.GRAPH_CIV)
	var mk := sb.marker_for(SimWorld.STAGE_FARM)
	panel.set_cursor_tick(int(mk.tick))
	await t.frames(2)
	var cb := civ.last_cursor.filter(func(c: Dictionary) -> bool: return int(c.series) == 1)
	var ca := civ.last_cursor.filter(func(c: Dictionary) -> bool: return int(c.series) == 0)
	var mb := civ.last_markers.filter(func(m: Dictionary) -> bool: return int(m.series) == 1 and int(m.stage) == SimWorld.STAGE_FARM)
	t.check(cb.size() == 1 and mb.size() == 1 and is_equal_approx(float(cb[0].x) + 0.5, float(mb[0].x)) and str(cb[0].text).begins_with("B · "),
			"세대 축 비교 시점 표시: B 의 농사 발견 틱 → B 세로선이 B 의 발견 세로선 자리 %s / %s" % [str(cb), str(mb)])
	t.check(ca.size() == 1 and is_equal_approx(float(ca[0].data_x), sa.extinct_gen) and str(ca[0].text).begins_with("A · "),
			"A 세로선은 A 가 그 틱에 있던 세대(멸종한 세대 %.2f)" % sa.extinct_gen)
	t.check(_labels_on_top(civ, civ.last_cursor), "세대 축 비교 시점 이름 상자 둘 모두 계열 선 위(I46) %s" % _seq_text(civ, civ.last_cursor))
	# 세대 축: A 의 줄은 거의 같은 세대(0.0)라 한 픽셀 열에 모여 줄여 그림 — 점 수는 그 그래프가 그리는 것(I38)
	t.check(panel.series_points(GraphPanel.GRAPH_POP, 0) < sa.size(), "세대 축: A %d줄이 한 열에 모여 점 %d개로 줄어 그림"
			% [sa.size(), panel.series_points(GraphPanel.GRAPH_POP, 0)])
	# 틱 축 비교 값 읽기(I45): A 가 멸종한 뒤의 틱이면 "A  멸종 (틱 N)" — 세대 축과 같게(예전: "이 틱 기록 없음")
	panel.set_x_axis(GraphPanel.X_TICK)
	v.layout_now()
	# 그래프마다 점 수(I38): 멸종 줄(개체 0)은 평균 특성이 빈 값이라 평균 특성 그래프의 A 점이 개체 수 그래프보다 하나 적다
	# (예전 series_points 는 그래프와 상관없이 기록 줄 수 — 세 그래프가 늘 같아 "그래프마다" 검사가 공허했음)
	var n_a := sa.size()
	var pts := [panel.series_points(GraphPanel.GRAPH_POP, 0), panel.series_points(GraphPanel.GRAPH_TRAIT, 0), panel.series_points(GraphPanel.GRAPH_CIV, 0)]
	t.check(pts[0] == n_a and pts[1] == n_a - 1 and pts[2] == n_a and panel.series_points(GraphPanel.GRAPH_TRAIT, 1) == sb.size(),
			"그래프마다 그리는 점 수(틱 축): A 개체 수·기술 단계 %d, 평균 특성 %d(멸종 줄 빠짐) — 기록 %d줄 %s" % [pts[0], pts[1], n_a, str(pts)])
	var tx := sb.tick[sb.size() - 1] * 0.7
	v.hover_at(Vector2(v.data_to_px(tx), v.plot.get_center().y))
	var tl := v.readout_lines()
	var want_a := "A  %s (틱 %s)" % [GraphView.EXTINCT_TEXT, GraphView.fmt_num(sa.extinct_tick, 0)]
	t.check(tx > sa.extinct_tick and tl.size() == 3 and str(tl[1].text) == want_a and not bool(tl[1].valid),
			"틱 축 비교: 멸종한 뒤 틱의 A 줄 = \"%s\" (%s)" % [want_a, v.readout_text()])
	v.hover_at(Vector2(v.data_to_px(0.0) + 1.0, v.plot.get_center().y))
	t.check(not v.readout_text().contains(GraphView.EXTINCT_TEXT), "멸종 전 틱에는 멸종 글 없음: %s" % v.readout_text())
	panel.clear_hover()
	host.queue_free()
	await t.frames(1)


# ── 비교 멸종 표시: 어느 실험이 멸종했는지("A 멸종"·"B 멸종", B 는 점선), 같은 자리여도 이름이 겹치지 않음(G47) ──
func _extinct_compare_checks(t) -> void:
	var xs: Array[Experiment] = []
	for k in 2:
		var x: Experiment = Experiment.create("no_resources", {}, 1).experiment
		x.tag = "A" if k == 0 else "B"
		var guard := 0
		while x.world.extinct_tick < 0 and guard < 3000:
			x.step()
			guard += 1
		x.step_n(int(x.world.cfg.record.every))
		xs.append(x)
	var host := _host(t, Vector2(1200, 240))
	var panel := GraphPanel.new()
	host.add_child(panel)
	panel.size = host.size
	panel.load_experiments(xs)
	await t.frames(2)
	var v := panel.view(GraphPanel.GRAPH_POP)
	var le := v.last_extinct
	t.check(le.size() == 2 and str(le[0].text) == "A " + GraphView.EXTINCT_TEXT and str(le[1].text) == "B " + GraphView.EXTINCT_TEXT
			and not bool(le[0].dashed) and bool(le[1].dashed), "비교 멸종 표시: \"A 멸종\"(실선)·\"B 멸종\"(점선) %s" % str(le.map(func(d: Dictionary) -> String: return str(d.text))))
	var apart := false
	if le.size() == 2:
		var r0: Rect2 = le[0].rect
		var r1: Rect2 = le[1].rect
		apart = absf(float(le[0].x) - float(le[1].x)) < 0.01 and not r0.intersects(r1)
	t.check(apart, "같은 자리의 두 멸종 이름이 겹치지 않음(한 줄 아래로)")
	t.check(_labels_on_top(v, le), "멸종 이름을 계열 선보다 뒤에 그림(선 위, I46) %s" % _seq_text(v, le))
	host.queue_free()
	await t.frames(1)


# ── 가장 좁은 폭(1280 창 이하): 그래프 제목이 잘리지 않음(G31), 범례는 예설정 이름만 줄이고 씨앗은 남김(G33) ──
func _narrow_checks(t) -> void:
	var a: Experiment = Experiment.create("demo_fast", {}, 1).experiment
	var b: Experiment = Experiment.create("demo_fast", {}, 2).experiment
	a.tag = "A"
	b.tag = "B"
	var host := _host(t, Vector2(1200, UiConfig.num("lab.bottom_panel_height")))
	var panel := GraphPanel.new()
	host.add_child(panel)
	panel.load_experiments([a, b])
	panel.set_show_flows(true)
	var min_w := panel.get_combined_minimum_size().x
	host.size = Vector2(min_w, host.size.y)
	panel.size = host.size
	await t.frames(3)
	var max_min := 3.0 * (UiConfig.num("graph.min_width") + 2.0 * UiConfig.num("graph.card_pad_h")) + 2.0 * UiConfig.num("graph.card_gap")
	t.check(min_w <= max_min + 0.5, "제목 줄(+ 출생·사망 켬)이 패널 최소 폭을 넓히지 않음: %.0f ≤ %.0f" % [min_w, max_min])
	var titles_ok := true
	var widths := PackedStringArray()
	for g in 3:
		var title := panel.get_node("Body/Charts/Card%d" % g).find_child("Title", true, false) as Label
		var nat := title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x
		titles_ok = titles_ok and title.is_visible_in_tree() and title.size.x + 0.5 >= nat
		widths.append("%s %.0f/%.0f" % [title.text, title.size.x, nat])
	t.check(titles_ok, "가장 좁은 폭 + 출생·사망 켬: 그래프 제목이 잘리지 않음 (%s)" % ", ".join(widths))
	var shown := panel.legend_shown()
	t.check(shown.size() == 2 and shown[0].begins_with("A · ") and shown[0].ends_with("씨앗 1") and shown[1].begins_with("B · ") and shown[1].ends_with("씨앗 2")
			and (shown[0].contains(GraphPanel.ELLIPSIS) or shown[1].contains(GraphPanel.ELLIPSIS)),
			"좁은 범례: 예설정 이름만 줄이고 이름표·씨앗은 남김 %s" % str(shown))
	# 좁은 그래프의 값 읽기: 비교 세대 축 줄("… (0.0세대 · 틱 0)")을 그래프 폭에 맞게 접음(글은 그대로)
	panel.set_x_axis(GraphPanel.X_GEN)
	var civ := panel.view(GraphPanel.GRAPH_CIV)
	civ.layout_now()
	civ.hover_at(Vector2(civ.data_to_px(0.0) + 1.0, civ.plot.get_center().y))
	var raw := civ.readout_lines()
	var key_space := UiConfig.num("graph.legend_key_px") + UiConfig.num("graph.gutter_gap")
	var room := civ.size.x - UiConfig.num("graph.tip_pad") * 2.0 - 2.0
	var wrapped := civ.wrap_readout(raw, room, key_space)
	var fit_ok := wrapped.size() > raw.size()
	var font := UiTheme.regular_font()
	var fs := UiConfig.integer("graph.axis_font_size")
	for l in wrapped:
		var lw := font.get_string_size(str(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + (key_space if int(l.series) >= 0 else 0.0)
		fit_ok = fit_ok and lw <= room + 0.5
	var joined := ""
	for l in wrapped:
		joined += (" " if not bool(l.first) else ("\n" if joined != "" else "")) + str(l.text)
	var orig := "\n".join(PackedStringArray(raw.map(func(d: Dictionary) -> String: return str(d.text))))
	t.check(fit_ok and joined == orig, "좁은 그래프 값 읽기: %d줄 → %d줄로 접어 폭 %.0f 안, 글은 그대로" % [raw.size(), wrapped.size(), room])
	host.queue_free()
	await t.frames(1)


# ── 가로축 이름(통합 I04, 4단계 검토 G29): 좁은 그림(1280 창의 아래 자리)에서도 이름이 둘 이상, 서로 겹치지 않고 그래프 안·단위 글자 앞 ──
## 예전: 그린 이름을 기록하지 않아 캡처로만 봤고, 띠 범위 글이 오른쪽 여백을 쓰게 된 뒤(G12) 1280 창 기술 단계 그래프가 1,212틱에서
## "0" 하나만 남았다(통합 때 캡처로 찾음). 폭 = 패널 최소 폭·1280 창(약 585)·1600 창(약 812)·더 넓게, 틱 범위 여럿, 세 그래프 모두.
func _x_label_checks(t) -> void:
	var host := _host(t, Vector2(1200, UiConfig.num("lab.bottom_panel_height")))
	var panel := GraphPanel.new()
	host.add_child(panel)
	var min_w := panel.get_combined_minimum_size().x
	var ends: Array[int] = [150, 484, 1212, 1696, 3000, 12345]
	for w: float in [min_w, 585.0, 640.0, 812.0, 1100.0]:
		host.size = Vector2(w, host.size.y)
		panel.size = host.size
		var bad := PackedStringArray()
		var shown := PackedStringArray()
		for last in ends:
			var s := GraphPanel.Series.new(null)
			var k := 0
			while k < last:
				s.append({tick = k, population = 50, mean_gen = float(k) / 75.0})
				k += 20
			s.append({tick = last, population = 50, mean_gen = float(last) / 75.0})
			var one: Array[GraphPanel.Series] = [s]
			panel.load_series(one)
			for mode: String in [GraphPanel.X_TICK, GraphPanel.X_GEN]:
				panel.set_x_axis(mode)
				panel.redraw_now()
				await t.frames(2)
				for g in 3:
					var v := panel.view(g)
					var why := _x_labels_bad(v)
					if why != "":
						bad.append("%s %d틱 그래프%d: %s" % [mode, last, g, why])
					if g == GraphPanel.GRAPH_CIV and mode == GraphPanel.X_TICK and last == 1212:
						shown.append(" ".join(PackedStringArray(v.last_x_labels.map(func(l: Dictionary) -> String: return str(l.text)))))
		t.check(bad.is_empty(), "폭 %.0f: 가로축 이름 ≥ 2·겹치지 않음·그래프 안(기술 단계 1,212틱 \"%s\") %s" % [w, ", ".join(shown), "; ".join(bad.slice(0, 4))])
	panel.set_x_axis(GraphPanel.X_TICK)
	host.queue_free()
	await t.frames(1)


## 가로축 이름이 잘못이면 그 까닭(괜찮으면 ""): 둘 미만, 간격이 고르지 않음, 서로 X_LABEL_PAD 미만, 그래프 밖·단위 글자와 겹침
func _x_labels_bad(v: GraphView) -> String:
	var ls := v.last_x_labels
	if ls.size() < 2:
		return "이름 %d개 %s" % [ls.size(), str(ls.map(func(l: Dictionary) -> String: return str(l.text)))]
	var step := float(ls[1].value) - float(ls[0].value)
	var unit_x := v.size.x - UiTheme.regular_font().get_string_size(str(GraphPanel.X_UNITS.get(v.panel.x_mode, "")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiConfig.integer("graph.axis_font_size")).x - 1.0
	for i in ls.size():
		var r: Rect2 = ls[i].rect
		if r.position.x < -0.5 or r.end.x > unit_x - 0.5:
			return "\"%s\" 가 그래프 밖·단위 글자와 겹침(%.0f~%.0f, 단위 %.0f)" % [str(ls[i].text), r.position.x, r.end.x, unit_x]
		if i > 0:
			var prev: Rect2 = ls[i - 1].rect
			if r.position.x - prev.end.x < GraphView.X_LABEL_PAD - 0.5:
				return "\"%s\"·\"%s\" 사이 %.1fpx" % [str(ls[i - 1].text), str(ls[i].text), r.position.x - prev.end.x]
			if not is_equal_approx(float(ls[i].value) - float(ls[i - 1].value), step):
				return "간격이 고르지 않음 %s" % str(ls.map(func(l: Dictionary) -> float: return float(l.value)))
	return ""


# ── 합성 기록 비교: 기록 간격이 다른 A(20)·B(100)의 출생·사망과 B 의 자기 틱(G20), B 의 점선이 모두 무늬 틈이면 그리지 않음(G24) ──
func _synthetic_checks(t) -> void:
	var sa := _flow_series(20, 4, 3, 101)
	var sb := _flow_series(100, 20, 15, 21)
	sa.tag = "A"
	sb.tag = "B"
	sa.name = "A · 합성 · 씨앗 1"
	sb.name = "B · 합성 · 씨앗 2"
	var host := _host(t, Vector2(1200, 240))
	var panel := GraphPanel.new()
	host.add_child(panel)
	panel.size = host.size
	var both: Array[GraphPanel.Series] = [sa, sb]
	panel.load_series(both)
	panel.set_show_flows(true)
	await t.frames(2)
	var v := panel.view(GraphPanel.GRAPH_POP)
	v.layout_now()
	v.hover_at(Vector2(v.data_to_px(1360.0), v.plot.get_center().y))
	var lines := v.readout_lines()
	var txt := v.readout_text()
	t.check(lines.size() == 3 and str(lines[0].text).begins_with("틱 1,360 · ") and not str(lines[1].text).contains("(틱") and str(lines[2].text).ends_with("(틱 1,400)"),
			"기록 간격이 다르면 B 줄에 B 의 틱: %s" % txt)
	t.check(lines.size() == 3 and str(lines[1].text).contains("출생 4 · 사망 3") and str(lines[2].text).contains("출생 4 · 사망 3"),
			"같은 빠르기(20틱에 4)면 기록 간격 20·100 이 같은 값: %s" % txt)
	t.check(v.last_flow_key.contains(panel.flow_unit()), "넓은 그래프: 출생·사망 견본에 단위 \"%s\"" % v.last_flow_key)
	panel.clear_hover()
	panel.set_show_flows(false)
	# B 가 무늬 틈 안의 두 줄(틱 T, T+2)뿐: 점선 조각이 모두 비어 그리지 않음(예전: 빈 배열로 draw_multiline → 엔진 ERROR)
	var civ := panel.view(GraphPanel.GRAPH_CIV)
	civ.layout_now()
	var dash := UiConfig.num("graph.dash_px")
	var period := dash + UiConfig.num("graph.dash_gap_px")
	var tt := -1
	for k in range(200, 1800):
		var p1 := civ.data_to_px(float(k)) - civ.plot.position.x
		var p2 := civ.data_to_px(float(k + 2)) - civ.plot.position.x
		if fposmod(p1, period) >= dash + 0.3 and floorf(p1 / period) == floorf(p2 / period) and fposmod(p2, period) <= period - 0.3:
			tt = k
			break
	var sb2 := GraphPanel.Series.new(null)
	sb2.tag = "B"
	sb2.name = "B · 짧은 기록 · 씨앗 3"
	sb2.append({tick = tt, population = 10, mean_gen = 1.0})
	sb2.append({tick = tt + 2, population = 10, mean_gen = 1.0})
	var skipped := civ.dash_skipped
	var pair: Array[GraphPanel.Series] = [sa, sb2]
	panel.load_series(pair)
	await t.frames(2)
	t.check(tt >= 0 and civ.dash_skipped > skipped and civ.last_lines.any(func(l: Dictionary) -> bool: return int(l.series) == 1 and int(l.col) == GraphPanel.C_STAGE),
			"B 의 점선 조각이 모두 무늬 틈(틱 %d~%d)이면 그리지 않고 건너뜀(%d번)" % [tt, tt + 2, civ.dash_skipped - skipped])
	panel.queue_free()
	# 선 굵기는 ui.json 에서(G28 — 예전엔 저장고·밭을 line_width × 0.75 로 코드에): 띠·얇은 선 굵기를 잠시 다른 값으로 만든 패널
	var gcfg: Dictionary = UiConfig.data()["graph"]
	var keep_lane: Variant = gcfg["lane_line_width"]
	var keep_thin: Variant = gcfg["thin_width"]
	gcfg["lane_line_width"] = 2.75
	gcfg["thin_width"] = 1.25
	var p2 := GraphPanel.new()
	gcfg["lane_line_width"] = keep_lane
	gcfg["thin_width"] = keep_thin
	host.add_child(p2)
	p2.size = host.size
	var only_a: Array[GraphPanel.Series] = [sa]
	p2.load_series(only_a)
	p2.set_show_flows(true)
	await t.frames(2)
	var widths: Array[String] = []
	var w_ok := true
	for g in [GraphPanel.GRAPH_POP, GraphPanel.GRAPH_CIV]:
		for l in p2.view(g).last_lines:
			var c := int(l.col)
			var want := -1.0
			if c == GraphPanel.C_STORES or c == GraphPanel.C_FARMS:
				want = 2.75
			elif c == GraphPanel.C_BIRTHS or c == GraphPanel.C_DEATHS:
				want = 1.25
			if want > 0.0:
				widths.append("%d:%s" % [c, str(l.width)])
				w_ok = w_ok and is_equal_approx(float(l.width), want)
	t.check(w_ok and widths.size() == 4, "선 굵기 = graph.lane_line_width(저장고·밭)·graph.thin_width(출생·사망) %s" % str(widths))
	host.queue_free()
	await t.frames(1)


# ── 스냅숏에서 연 실험(J19): 기록은 연 틱부터라 그 앞의 발견 세로선·시점 표시는 그리지 않음 → 머리에 "기록은 틱 N 부터" ──
func _snapshot_note_checks(t) -> void:
	var dir := "user://graph_checks-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir.path_join("snap.json")
	var x: Experiment = Experiment.create("demo_fast", {}, 1).experiment
	var guard := 0
	while x.world.discovery_tick[SimWorld.STAGE_FORAGE] < 0 and guard < 3000:
		x.step()
		guard += 1
	x.step_n(int(x.world.cfg.record.every) * 2 + 3)
	var host := _host(t, Vector2(1200, 240))
	var panel := GraphPanel.new()
	host.add_child(panel)
	panel.size = host.size
	panel.load_experiments([x])
	await t.frames(2)
	t.check(panel.record_note() == "" and panel.record_note_shown() == "" and not (_find_named(panel, "RecordNote") as Control).visible,
			"틱 0 부터 기록한 실험: 머리 알림 없음")
	t.check(SimSnapshot.save_file(x.world, path) == "", "스냅숏 저장(틱 %d)" % x.world.tick)
	var r := Experiment.from_snapshot(path)
	var y: Experiment = r.experiment
	t.check(y != null and y.rows().size() == 1, "연 실험의 기록은 연 틱 한 줄")
	if y == null:
		host.queue_free()
		return
	panel.load_experiments([y])
	await t.frames(2)
	var want := GraphPanel.RECORD_NOTE % GraphView.fmt_num(float(y.world.tick), 0)
	var note := _find_named(panel, "RecordNote") as Label
	var civ := panel.view(GraphPanel.GRAPH_CIV)
	t.check(panel.record_note_shown() == want and note != null and note.visible and note.text == want and note.tooltip_text != "",
			"스냅숏에서 연 실험: 머리에 \"%s\" (보임 \"%s\")" % [want, panel.record_note_shown()])
	t.check(panel.series[0].markers.size() >= 1 and civ.last_markers.is_empty(), "그 앞의 발견 세로선은 가로축 밖이라 그리지 않음(그래서 알림)")
	# 앞선 사건(채집 발견) 시점을 눌러도 기록 앞이라 세로선 없음 — 알림은 그대로
	panel.set_cursor_tick(int(x.world.discovery_tick[SimWorld.STAGE_FORAGE]))
	await t.frames(2)
	t.check(civ.last_cursor.is_empty() and panel.record_note_shown() == want, "기록 앞 시점: 세로선 없이 알림 유지")
	# 연 뒤 진행해도(새 줄 덧붙임) 알림 그대로, 새 실험이면 사라짐
	for i in int(y.world.cfg.record.every):
		if y.step():
			panel.append_row(0, y.rows().back())
	t.check(panel.series[0].size() == 2 and panel.record_note_shown() == want, "연 뒤 진행해도 알림 그대로")
	panel.load_experiments([x])
	await t.frames(1)
	t.check(panel.record_note_shown() == "", "다시 틱 0 부터인 실험 → 알림 사라짐")
	# 비교(이름표): 스냅숏에서 연 쪽에만
	x.tag = "A"
	y.tag = "B"
	panel.load_experiments([x, y])
	await t.frames(1)
	t.check(panel.record_note_shown() == "B " + want, "비교: 연 실험(B)에만 \"B %s\" (보임 \"%s\")" % [want, panel.record_note_shown()])
	host.queue_free()
	await t.frames(1)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


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
	t.check(panel.series[0].size() == LONG_ROWS and panel.series[1].size() == LONG_ROWS, "합성 %d줄 × 2" % LONG_ROWS)
	panel.redraw_now()
	await t.frames(2)
	var full_us := 0
	var full_fed := 0
	var pts_ok := true
	for g in 3:
		var v := panel.view(g)
		full_us += v.last_draw_us
		full_fed += v.last_fed_rows
		for l in v.last_lines:
			if int(l.points) > 4 * int(v.plot.size.x) + 4:
				pts_ok = false
	var v0 := panel.view(GraphPanel.GRAPH_POP)
	t.check(pts_ok, "줄여 그린 점 ≤ 그림 폭 × 4 (개체 수 A %d점, 폭 %d)" % [int(v0.last_lines[v0.last_lines.size() - 1].points), int(v0.plot.size.x)])
	# series_points(그래프, 실험) = 그 그래프가 실제로 그린 줄인 점 수(I38 — 예전엔 그래프와 상관없이 기록 줄 수 6,000)
	var sp_ok := true
	var sp_txt := PackedStringArray()
	for g in 3:
		var vg := panel.view(g)
		for k in 2:
			var drawn := 0
			for l in vg.last_lines:
				if int(l.series) == k and int(l.col) != GraphPanel.C_STAGE:
					drawn = maxi(drawn, int(l.points))
			var sp := panel.series_points(g, k)
			sp_txt.append("%d/%d:%d" % [g, k, sp])
			sp_ok = sp_ok and sp == drawn and sp > 0 and sp <= 4 * int(vg.plot.size.x) + 4 and sp < LONG_ROWS
	t.check(sp_ok, "series_points = 그 그래프가 그린 점 수(줄인 것, < %d줄) %s" % [LONG_ROWS, ", ".join(sp_txt)])
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
	var inc_fed := 0
	var n_lines := 0
	for g in 3:
		inc_us += panel.view(g).last_draw_us
		inc_fed += panel.view(g).last_fed_rows
		n_lines += panel.view(g).last_lines.filter(func(l: Dictionary) -> bool: return int(l.col) != GraphPanel.C_STAGE).size()
	t.check(extra > 0 and v0.rebuild_count == rebuilt and v0.line_runs(0, GraphPanel.C_POP).used == LONG_ROWS + extra, "범위 안 새 줄 %d개: 다시 묶지 않고 더함" % extra)
	# 그리기 일의 크기는 시계가 아니라 센 수로 본다(I34: 예전 "새 줄 뒤 그리기 < 20 ms" 는 기계 속도·부하에 묶인 단언 —
	# 느린 CI 에서 코드가 맞아도 실패할 수 있었음). 실제 시간은 참고로 출력만.
	t.check(full_fed >= LONG_ROWS * 2 and inc_fed == extra * n_lines,
			"새 줄 뒤 그리기는 새 줄만 묶음에 넣음: 처음 %d줄 · 새 줄만 %d줄 = 새 줄 %d × 선 %d" % [full_fed, inc_fed, extra, n_lines])
	print("    (참고) 그래프 그리기(%d줄 × 2, 세 그래프 합): 처음 %d µs · 새 줄만 %d µs" % [LONG_ROWS, full_us, inc_us])
	# 세대 축 6,000줄 × 2: 가장 가까운 줄 = 모두 훑기와 같은 답(이분 탐색), 마우스는 겹만·계산 한 번(G07·G23)
	panel.set_x_axis(GraphPanel.X_GEN)
	var s1 := panel.series[1]
	var near_ok := true
	for q in 40:
		var gq := s1.gen_lo + (s1.gen_hi - s1.gen_lo) * float(q) / 39.0 + 0.0037
		near_ok = near_ok and panel.nearest_row(1, gq) == _brute_nearest(s1.gen_x, gq)
	t.check(near_ok, "세대 축 %d줄: 가장 가까운 줄 = 모두 훑기(40곳)" % s1.size())
	await _hover_cost_checks(t, panel, "세대 축 %d줄 × 2" % LONG_ROWS)
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
