class_name GraphPanel
extends HBoxContainer
## 그래프 3개(개체 수·평균 특성·기술 단계) — 실험실 아래 자리. 계약: docs/VIEW-API.md "GraphPanel".
##
## 데이터: experiments_changed → 지우고 각 실험의 rows() 를 처음부터, recorded(index, row) → 한 줄 덧붙임(다시 훑지 않음).
## 실험마다 열(column)별 PackedFloat64Array 를 따로 쌓는다(사전을 프레임마다 복사하지 않음). 그리기는 GraphView 셋.
## 다시 그리기는 ui.graph.redraw_hz 이하(새 줄이 와도 모아서), 마우스·크기·설정 바뀜은 바로.
## 시뮬레이션은 읽기만 한다: Experiment.rows()·display_name()·tag, world.discovery_tick·chronicle·extinct_tick(발견·멸종 시점).
## LabMain 없이도 쓸 수 있다(검사·캡처): load_experiments(목록) → append_row(번호, 줄) → set_cursor_tick(틱).

const GRAPH_POP := 0
const GRAPH_TRAIT := 1
const GRAPH_CIV := 2
const GRAPH_TITLES: Array[String] = ["개체 수", "평균 특성", "기술 단계"]
## 가로축(set_x_axis 의 값)
const X_TICK := "tick"
const X_GEN := "gen"
const X_UNITS := {"tick": "틱", "gen": "세대"}

# ── 열 번호(Series.cols 의 자리) ──
const C_POP := 0
const C_BIRTHS := 1
const C_DEATHS := 2
const C_SIZE := 3
const C_SENSE := 4
const C_ENERGY := 5
const C_AGE := 6
const C_GEN := 7
const C_STAGE := 8
const C_STORES := 9
const C_FARMS := 10
## 열 번호 → 시계열 줄 키(SimRecorder.TIMESERIES_COLUMNS)
const COL_KEYS: Array[String] = ["population", "births", "deaths", "mean_size", "mean_sense", "mean_energy",
		"mean_age", "mean_gen", "civ_stage", "storehouses", "farms"]
## 개체가 없으면 뜻이 없는 열(평균): 그 줄은 NaN 으로 두어 선을 끊는다(평균 함수가 0 을 돌려 거짓 바닥이 생기지 않게)
const MEAN_COLS: Array[int] = [C_SIZE, C_SENSE, C_ENERGY, C_AGE, C_GEN]
## 평균 특성 고르기(OptionButton 항목 순서)
const TRAIT_COLS: Array[int] = [C_SIZE, C_SENSE, C_ENERGY, C_AGE, C_GEN]
const TRAIT_NAMES: Array[String] = ["크기", "감각", "에너지", "나이", "세대"]
const TRAIT_UNITS: Array[String] = ["", "칸", "", "틱", "세대"]

const FLOWS_TEXT := "출생·사망"
const FLOWS_TIP := "기록 간격(record.every 틱)마다의 출생·사망 수를 얇은 선으로"
const X_LABEL := "가로축"
const X_TICK_TEXT := "틱"
const X_GEN_TEXT := "평균 세대"
const EMPTY_LEGEND := "실험 없음"
## 사건 종류(SIM-API): 발견
const KIND_DISCOVERY := "discovery"


## 실험 하나의 기록. 열마다 따로 쌓은 수 배열 + 가로축 값 + 발견·멸종 표시.
class Series extends RefCounted:
	var exp: Experiment
	var name := ""
	var tag := ""
	var tick := PackedFloat64Array()
	## 평균 세대 가로축: 개체가 없으면(멸종 뒤) 마지막 평균 세대를 이어 쓴다(멸종한 세대에 선이 떨어짐)
	var gen_x := PackedFloat64Array()
	var cols: Array[PackedFloat64Array] = []
	## 열마다 지금까지의 최솟값·최댓값(NaN 제외) — 세로축 범위를 다시 훑지 않고 정함
	var lo := PackedFloat64Array()
	var hi := PackedFloat64Array()
	var gen_lo := INF
	var gen_hi := -INF
	## 발견 표시 {stage, tick, gen}(world.discovery_tick·연대기의 정확한 시점)
	var markers: Array[Dictionary] = []
	## civ_stage 가 앞 줄보다 커진 줄 번호
	var stage_rows := PackedInt32Array()
	## 멸종(개체 수가 0 이 된 첫 줄, 없으면 -1)과 그 틱·평균 세대
	var extinct_row := -1
	var extinct_tick := -1.0
	var extinct_gen := 0.0
	var _last_stage := -1
	var _mean_flag := PackedByteArray()

	func _init(e: Experiment) -> void:
		exp = e
		if e != null:
			name = e.display_name()
			tag = e.tag
		for c in COL_KEYS.size():
			cols.append(PackedFloat64Array())
			lo.append(INF)
			hi.append(-INF)
			_mean_flag.append(1 if MEAN_COLS.has(c) else 0)

	func size() -> int:
		return tick.size()

	## 가로축 값 배열(모드별)
	func xs(mode: String) -> PackedFloat64Array:
		return gen_x if mode == X_GEN else tick

	## 시계열 한 줄 덧붙이기(사전은 읽기만 하고 붙잡지 않음).
	func append(row: Dictionary) -> void:
		var k := tick.size()
		var t := float(row.get("tick", 0))
		var pop := float(row.get("population", 0))
		var alive := pop > 0.0
		tick.append(t)
		for c in COL_KEYS.size():
			var v := float(row.get(COL_KEYS[c], 0.0))
			if not alive and _mean_flag[c] == 1:
				v = NAN
			cols[c].append(v)
			if not is_nan(v):
				if v < lo[c]:
					lo[c] = v
				if v > hi[c]:
					hi[c] = v
		var g := float(row.get("mean_gen", 0.0)) if alive else (gen_x[k - 1] if k > 0 else 0.0)
		gen_x.append(g)
		gen_lo = minf(gen_lo, g)
		gen_hi = maxf(gen_hi, g)
		if not alive and extinct_row < 0:
			extinct_row = k
			var w := exp.world if exp != null else null
			extinct_tick = float(w.extinct_tick) if w != null and w.extinct_tick >= 0 else t
			extinct_gen = g
		var s := int(row.get("civ_stage", 0))
		if _last_stage < 0:
			# 첫 줄: 이미 지난 발견(스냅숏에서 열었으면)도 넣어 둔다 — 그릴 때 가로축 범위 밖이면 생략
			for st in range(1, s + 1):
				_add_marker(st, t, g)
		elif s > _last_stage:
			stage_rows.append(k)
			for st in range(_last_stage + 1, s + 1):
				_add_marker(st, t, g)
		_last_stage = maxi(_last_stage, s)

	## 발견 표시: 정확한 틱은 world.discovery_tick, 그때의 평균 세대는 연대기의 발견 사건(없으면 이 줄 값).
	func _add_marker(st: int, row_tick: float, row_gen: float) -> void:
		var mt := row_tick
		var mg := row_gen
		var w := exp.world if exp != null else null
		if w != null:
			if st < w.discovery_tick.size() and w.discovery_tick[st] >= 0:
				mt = float(w.discovery_tick[st])
			for i in range(w.chronicle.size() - 1, -1, -1):
				var e: Dictionary = w.chronicle[i]
				if str(e.get("kind", "")) == KIND_DISCOVERY and int(e.get("stage", -1)) == st:
					mg = float(e.get("mean_gen", row_gen))
					break
		markers.append({stage = st, tick = mt, gen = mg})

	## 단계 st 의 발견 표시(없으면 빈 사전)
	func marker_for(st: int) -> Dictionary:
		for m in markers:
			if int(m.stage) == st:
				return m
		return {}


## 선 견본(범례): 실선·점선, 굵기
class LineKey extends Control:
	var color := Color.WHITE
	var dashed := false
	var width := 2.0
	var dash := 4.0

	func _init(c: Color, is_dashed: bool, w: float, key_w: float, dash_px: float) -> void:
		color = c
		dashed = is_dashed
		width = w
		dash = dash_px
		custom_minimum_size = Vector2(key_w, 12.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var y := roundf(size.y * 0.5)
		if dashed:
			draw_dashed_line(Vector2(0, y), Vector2(size.x, y), color, width, dash, false, true)
		else:
			draw_line(Vector2(0, y), Vector2(size.x, y), color, width, true)


## 머리 범례(코드로 그림): 항목 {text, color, dashed, key}를 왼쪽부터 붙여 놓고, 자리가 모자라면 이름을
## 자연 폭에 비례해 줄여 "…"로 자른다(최소 폭이 이름에 묶이지 않아 창을 좁혀도 넘치지 않음). 전체 이름은 말풍선.
class LegendBar extends Control:
	var items: Array[Dictionary] = []
	var _font: Font
	var _fs := 13
	var _c_text := Color.WHITE
	var _c_dim := Color.GRAY
	var _key_w := 24.0
	var _key_gap := 5.0
	var _gap := 18.0
	var _line_w := 2.0
	var _dash := 6.0

	func _init(fs: int, key_w: float, key_gap: float, gap: float, line_w: float, dash: float) -> void:
		_font = UiTheme.regular_font()
		_fs = fs
		_c_text = UiTheme.color("text")
		_c_dim = UiTheme.color("text_dim")
		_key_w = key_w
		_key_gap = key_gap
		_gap = gap
		_line_w = line_w
		_dash = dash
		mouse_filter = Control.MOUSE_FILTER_PASS
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		custom_minimum_size = Vector2(0.0, ceilf(_font.get_height(_fs)) + 2.0)

	func set_items(list: Array[Dictionary]) -> void:
		items = list
		var names := PackedStringArray()
		for it in items:
			names.append(str(it.text))
		tooltip_text = "\n".join(names)
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	## 그릴 때 실제로 보이는 글(잘렸으면 "…" 포함, 검사용)
	func shown_texts() -> PackedStringArray:
		var out := PackedStringArray()
		var widths := _widths()
		for k in items.size():
			out.append(_fit(str(items[k].text), widths[k]))
		return out

	func _widths() -> PackedFloat64Array:
		var nat := PackedFloat64Array()
		var fixed := 0.0
		var total := 0.0
		for k in items.size():
			var w := _font.get_string_size(str(items[k].text), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
			nat.append(w)
			total += w
			if bool(items[k].key):
				fixed += _key_w + _key_gap
			if k > 0:
				fixed += _gap
		var room := maxf(0.0, size.x - fixed)
		if total > room and total > 0.0:
			for k in nat.size():
				nat[k] = floorf(nat[k] * room / total)
		return nat

	func _fit(text: String, w: float) -> String:
		if _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x <= w + 0.5:
			return text
		var t := text
		while t.length() > 0:
			t = t.substr(0, t.length() - 1)
			var c := t.strip_edges() + "…"
			if _font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x <= w:
				return c
		return ""

	func _draw() -> void:
		var widths := _widths()
		var lh := _font.get_height(_fs)
		var base := (size.y - lh) * 0.5 + _font.get_ascent(_fs)
		var mid := roundf(size.y * 0.5) + 0.5
		var x := 0.0
		for k in items.size():
			var it := items[k]
			if k > 0:
				x += _gap
			if bool(it.key):
				var c: Color = it.color
				if bool(it.dashed):
					draw_dashed_line(Vector2(x, mid), Vector2(x + _key_w, mid), c, _line_w, _dash, false, true)
				else:
					draw_line(Vector2(x, mid), Vector2(x + _key_w, mid), c, _line_w, true)
				x += _key_w + _key_gap
			var t := _fit(str(it.text), widths[k])
			draw_string(_font, Vector2(x, base), t, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_text if bool(it.key) else _c_dim)
			x += widths[k]


## 다시 그린 횟수(검사용: 새 줄은 모아서 redraw_hz 이하로)
var redraw_count := 0
## 실험별 기록(혼자 1개, 비교 2개)
var series: Array[Series] = []
var x_mode := X_TICK
var show_flows := false
var trait_index := 0
## 연대기 등이 요청한 시점(틱, -1 = 없음)
var cursor_tick := -1
## 마우스가 가리키는 가로축 값(NaN = 없음)과 그 그래프(값 읽기 상자는 그 그래프에만)
var hover_x := NAN
var hover_view: GraphView = null
## 데이터를 처음부터 다시 읽은 횟수(GraphView 가 묶음 캐시를 버리는 기준)
var epoch := 0

var _lab: LabMain
var _views: Array[GraphView] = []
var _dirty := false
var _since := 0.0
var _interval := 0.2

# ── 노드 ──
var _legend: LegendBar
var _btn_tick: Button
var _btn_gen: Button
var _flows_btn: Button
var _flow_keys: HBoxContainer
var _trait_opt: OptionButton

# ── 설정 값 ──
var _fs_small := 13
var _fs_title := 14
var _key_w := 18.0
var _dash := 6.0
var _line_w := 2.0
var _thin_w := 1.0
var _x_target := 5
var _x_snap_div := 4.0
var _x_min_ticks := 100.0
var _x_min_gen := 1.0


func _init() -> void:
	name = "GraphPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_read_config()
	_build()
	set_x_axis(X_TICK)


func _read_config() -> void:
	var hz := maxf(0.1, UiConfig.num("graph.redraw_hz"))
	_interval = 1.0 / hz
	_fs_small = UiConfig.integer("lab.font_size_small")
	_fs_title = UiConfig.integer("graph.title_font_size")
	_key_w = UiConfig.num("graph.legend_key_px")
	_dash = UiConfig.num("graph.dash_px")
	_line_w = UiConfig.num("graph.line_width")
	_thin_w = UiConfig.num("graph.thin_width")
	_x_target = maxi(2, UiConfig.integer("graph.x_ticks"))
	_x_snap_div = maxf(1.0, UiConfig.num("graph.x_snap_div"))
	_x_min_ticks = maxf(1.0, UiConfig.num("graph.x_min_span_ticks"))
	_x_min_gen = maxf(0.01, UiConfig.num("graph.x_min_span_gen"))


# ════════════════════════════ 연결 ════════════════════════════

## 실험실에 묶는다: 실험 목록·기록·시점 요청을 받는다. 지금 실험을 바로 읽는다.
func bind_lab(lab: LabMain) -> void:
	if _lab != null and is_instance_valid(_lab):
		if _lab.experiments_changed.is_connected(load_experiments):
			_lab.experiments_changed.disconnect(load_experiments)
			_lab.recorded.disconnect(append_row)
			_lab.cursor_tick_requested.disconnect(set_cursor_tick)
	_lab = lab
	if lab == null:
		load_experiments([])
		return
	lab.experiments_changed.connect(load_experiments)
	lab.recorded.connect(append_row)
	lab.cursor_tick_requested.connect(set_cursor_tick)
	load_experiments(lab.experiments)


## 실험 목록을 처음부터 다시 읽는다(experiments_changed). 시점 표시·마우스 값은 지운다.
func load_experiments(list: Array) -> void:
	series.clear()
	for item in list:
		var x := item as Experiment
		if x == null:
			continue
		var s := Series.new(x)
		for r in x.rows():
			s.append(r)
		series.append(s)
	epoch += 1
	cursor_tick = -1
	hover_x = NAN
	hover_view = null
	_rebuild_legend()
	redraw_now()


## index 번째 실험에 한 줄 덧붙인다(recorded). 다시 그리기는 모아서(redraw_hz).
func append_row(index: int, row: Dictionary) -> void:
	if index < 0 or index >= series.size():
		return
	series[index].append(row)
	_dirty = true


## 시점 표시(연대기 → 그래프). -1 = 지움.
func set_cursor_tick(tick: int) -> void:
	cursor_tick = tick
	redraw_now()


# ════════════════════════════ 검사·조작 API ════════════════════════════

## 그래프 수(3)
func graph_count() -> int:
	return _views.size()


## graph 번째 그래프에서 index 번째 실험의 점 수(검사용). 세 그래프 모두 기록 줄 하나가 점 하나.
func series_points(graph: int, index: int) -> int:
	if graph < 0 or graph >= _views.size() or index < 0 or index >= series.size():
		return 0
	return series[index].size()


## 가로축: "tick"(틱) / "gen"(평균 세대). 셋 모두 함께 바뀐다. 다른 값은 무시(지금 축 그대로).
func set_x_axis(mode: String) -> void:
	if mode != X_TICK and mode != X_GEN:
		return
	x_mode = mode
	if _btn_tick != null:
		_btn_tick.set_pressed_no_signal(mode == X_TICK)
		_btn_gen.set_pressed_no_signal(mode == X_GEN)
	redraw_now()


## 출생·사망 얇은 선 켜고 끄기
func set_show_flows(on: bool) -> void:
	show_flows = on
	if _flows_btn != null:
		_flows_btn.set_pressed_no_signal(on)
		_flow_keys.visible = on
	redraw_now()


## 평균 특성 고르기(TRAIT_COLS 의 번호)
func set_trait(i: int) -> void:
	trait_index = clampi(i, 0, TRAIT_COLS.size() - 1)
	if _trait_opt != null and _trait_opt.selected != trait_index:
		_trait_opt.select(trait_index)
	redraw_now()


func trait_col() -> int:
	return TRAIT_COLS[trait_index]


## graph 번째 GraphView(검사용)
func view(graph: int) -> GraphView:
	return _views[graph] if graph >= 0 and graph < _views.size() else null


## 지금 가로축으로 본 index 번째 실험의 row 번째 줄의 가로 값
func row_x(index: int, row: int) -> float:
	var s := series[index]
	return s.gen_x[row] if x_mode == X_GEN else s.tick[row]


## 표시 하나의 지금 가로 값({tick, gen} 사전)
func marker_x(m: Dictionary) -> float:
	return float(m.gen) if x_mode == X_GEN else float(m.tick)


## 모든 실험이 함께 쓰는 가로축 범위(x0, x1). 눈금 간격(x_step)의 1/x_snap_div 단위로 끝을 올려
## 줄이 늘어도 범위가 가끔만 바뀐다(그동안 GraphView 는 새 줄만 묶음에 더함).
func x_bounds() -> Vector2:
	var r := _x_range()
	return Vector2(r.x, r.y)


## 가로축 눈금 기본 간격(1·2·5 × 10^k)
func x_step() -> float:
	return _x_range().z


func _x_range() -> Vector3:
	var lo := INF
	var hi := -INF
	for s in series:
		if s.size() == 0:
			continue
		if x_mode == X_GEN:
			lo = minf(lo, s.gen_lo)
			hi = maxf(hi, s.gen_hi)
		else:
			lo = minf(lo, s.tick[0])
			hi = maxf(hi, s.tick[s.size() - 1])
	var integer := x_mode == X_TICK
	if lo == INF:
		lo = 0.0
		hi = 0.0
	# 줄이 몇 개 없을 때도 축이 너무 짧지 않게(새 실험의 첫 점이 왼쪽에서 자라 나가게)
	var min_span := _x_min_gen if x_mode == X_GEN else _x_min_ticks
	if hi - lo < min_span:
		hi = lo + min_span
	var step := GraphView.nice_step(hi - lo, _x_target, integer)
	var x0 := floorf(lo / step) * step
	var snap := step / _x_snap_div
	if integer:
		snap = maxf(1.0, snap)
	var x1 := ceilf(hi / snap - 1e-9) * snap
	if x1 <= x0:
		x1 = x0 + step
	return Vector3(x0, x1, step)


## index 번째 실험에서 가로 값 x 에 가장 가까운 기록 줄(없으면 -1). 틱 축은 이분 탐색, 세대 축은 훑음.
func nearest_row(index: int, x: float) -> int:
	if index < 0 or index >= series.size() or is_nan(x):
		return -1
	var s := series[index]
	var n := s.size()
	if n == 0:
		return -1
	if x_mode == X_TICK:
		var i := s.tick.bsearch(x)
		if i <= 0:
			return 0
		if i >= n:
			return n - 1
		return i - 1 if x - s.tick[i - 1] <= s.tick[i] - x else i
	var best := 0
	var best_d := INF
	for i in n:
		var d := absf(s.gen_x[i] - x)
		if d <= best_d:
			best_d = d
			best = i
	return best


## 틱 tick 에 가장 가까운 기록 줄(가로축과 무관, 시점 표시용)
func nearest_row_by_tick(index: int, tick: float) -> int:
	if index < 0 or index >= series.size():
		return -1
	var s := series[index]
	var n := s.size()
	if n == 0:
		return -1
	var i := s.tick.bsearch(tick)
	if i <= 0:
		return 0
	if i >= n:
		return n - 1
	return i - 1 if tick - s.tick[i - 1] <= s.tick[i] - tick else i


## 마우스가 가리키는 기록 줄(실험마다, 없으면 -1)
func hover_rows() -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in series.size():
		out.append(nearest_row(k, hover_x))
	return out


## GraphView 가 부름: 마우스가 그래프 위(가로 값 x)
func set_hover(v: GraphView, x: float) -> void:
	hover_view = v
	hover_x = x
	for g in _views:
		g.queue_redraw()


func clear_hover() -> void:
	if is_nan(hover_x) and hover_view == null:
		return
	hover_x = NAN
	hover_view = null
	for g in _views:
		g.queue_redraw()


## 실험별 선 색(A = series_a, B = series_b)과 점선 여부
func series_color(index: int) -> Color:
	return UiConfig.color("graph.series_b") if index == 1 else UiConfig.color("graph.series_a")


func series_dashed(index: int) -> bool:
	return index == 1


func is_compare() -> bool:
	return series.size() > 1


# ════════════════════════════ 다시 그리기 ════════════════════════════

func _process(delta: float) -> void:
	advance(delta)


## 새 줄로 더러워졌으면 redraw_interval() 이 지났을 때만 다시 그린다. 그렸으면 true(검사가 delta 를 직접 줌).
func advance(delta: float) -> bool:
	_since += delta
	if not _dirty or _since < _interval:
		return false
	if not is_visible_in_tree():
		return false
	_since = 0.0
	_dirty = false
	redraw_count += 1
	for g in _views:
		g.queue_redraw()
	return true


## 바로 다시 그린다(설정·데이터 교체·시점 표시).
func redraw_now() -> void:
	_dirty = false
	_since = 0.0
	redraw_count += 1
	for g in _views:
		g.queue_redraw()


## 다시 그리기 최소 간격(초) = 1 / ui.graph.redraw_hz
func redraw_interval() -> float:
	return _interval


## 그리지 않은 새 줄이 있는지
func is_dirty() -> bool:
	return _dirty


# ════════════════════════════ 만들기 ════════════════════════════

func _build() -> void:
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", UiConfig.integer("graph.row_gap"))
	add_child(body)

	# ── 머리: 범례 | 가로축 ──
	var head := HBoxContainer.new()
	head.name = "Header"
	head.add_theme_constant_override("separation", UiConfig.integer("graph.control_gap"))
	body.add_child(head)
	_legend = LegendBar.new(_fs_small, _key_w * 1.5, UiConfig.num("graph.key_gap"), UiConfig.num("graph.legend_gap"), _line_w, _dash)
	_legend.name = "Legend"
	head.add_child(_legend)
	var xl := Label.new()
	xl.text = X_LABEL
	xl.theme_type_variation = UiTheme.DIM
	head.add_child(xl)
	var group := ButtonGroup.new()
	_btn_tick = _toggle(X_TICK_TEXT, group)
	_btn_tick.name = "XTick"
	_btn_tick.toggled.connect(func(on: bool) -> void:
		if on:
			set_x_axis(X_TICK))
	head.add_child(_btn_tick)
	_btn_gen = _toggle(X_GEN_TEXT, group)
	_btn_gen.name = "XGen"
	_btn_gen.toggled.connect(func(on: bool) -> void:
		if on:
			set_x_axis(X_GEN))
	head.add_child(_btn_gen)

	# ── 그래프 카드 셋 ──
	var row := HBoxContainer.new()
	row.name = "Charts"
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", UiConfig.integer("graph.card_gap"))
	body.add_child(row)
	for g in GRAPH_TITLES.size():
		var card := PanelContainer.new()
		card.name = "Card%d" % g
		card.theme_type_variation = UiTheme.CARD
		card.add_theme_stylebox_override("panel", _card_style())
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", UiConfig.integer("graph.title_gap"))
		card.add_child(col)
		var title_row := HBoxContainer.new()
		title_row.name = "TitleRow"
		title_row.add_theme_constant_override("separation", UiConfig.integer("graph.control_gap"))
		col.add_child(title_row)
		var title := Label.new()
		title.name = "Title"
		title.text = GRAPH_TITLES[g]
		title.theme_type_variation = UiTheme.VALUE
		title.add_theme_font_size_override("font_size", _fs_title)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
		title_row.add_child(title)
		match g:
			GRAPH_POP:
				_flow_keys = HBoxContainer.new()
				_flow_keys.name = "FlowKeys"
				_flow_keys.add_theme_constant_override("separation", UiConfig.integer("graph.key_gap"))
				_flow_keys.visible = false
				_add_key(_flow_keys, UiConfig.color("graph.births"), false, _thin_w, "출생")
				_add_key(_flow_keys, UiConfig.color("graph.deaths"), false, _thin_w, "사망")
				title_row.add_child(_flow_keys)
				_flows_btn = _toggle(FLOWS_TEXT, null)
				_flows_btn.name = "Flows"
				_flows_btn.tooltip_text = FLOWS_TIP
				_flows_btn.toggled.connect(set_show_flows)
				title_row.add_child(_flows_btn)
			GRAPH_TRAIT:
				_trait_opt = OptionButton.new()
				_trait_opt.name = "Trait"
				for n in TRAIT_NAMES:
					_trait_opt.add_item(n)
				_trait_opt.select(trait_index)
				_trait_opt.focus_mode = Control.FOCUS_NONE
				_compact(_trait_opt, "OptionButton")
				_trait_opt.item_selected.connect(set_trait)
				title_row.add_child(_trait_opt)
			GRAPH_CIV:
				var hint := Label.new()
				hint.text = "세로선 = 발견"
				hint.theme_type_variation = UiTheme.DIM
				hint.name = "Hint"
				title_row.add_child(hint)
		var v := GraphView.new()
		v.name = "Graph%d" % g
		v.kind = g
		v.panel = self
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(v)
		_views.append(v)


## 카드 바탕: 공용 CardPanel 모양에서 여백만 그래프에 맞게
func _card_style() -> StyleBox:
	var base := UiTheme.build().get_stylebox("panel", UiTheme.CARD) as StyleBoxFlat
	var sb := base.duplicate() as StyleBoxFlat
	sb.content_margin_left = UiConfig.num("graph.card_pad_h")
	sb.content_margin_right = UiConfig.num("graph.card_pad_h")
	sb.content_margin_top = UiConfig.num("graph.card_pad_v")
	sb.content_margin_bottom = UiConfig.num("graph.card_pad_v")
	return sb


## 작은 켜고 끄는 단추(공용 Button 모양 + 작은 글자·좁은 세로 여백)
func _toggle(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	if group != null:
		b.button_group = group
	_compact(b, "Button")
	return b


func _compact(c: Control, type: String) -> void:
	var th := UiTheme.build()
	var pv := UiConfig.num("graph.button_pad_v")
	var ph := UiConfig.num("graph.button_pad_h")
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed", "normal_mirrored", "hover_mirrored", "pressed_mirrored", "disabled_mirrored"]:
		if not th.has_stylebox(st, type):
			continue
		var sb := th.get_stylebox(st, type).duplicate() as StyleBox
		sb.content_margin_top = pv
		sb.content_margin_bottom = pv
		sb.content_margin_left = ph
		sb.content_margin_right = ph
		c.add_theme_stylebox_override(st, sb)
	c.add_theme_font_size_override("font_size", _fs_small)


func _add_key(box: HBoxContainer, c: Color, dashed: bool, w: float, text: String) -> Label:
	box.add_child(LineKey.new(c, dashed, w, _key_w, _dash * 0.6))
	var l := Label.new()
	l.text = text
	l.theme_type_variation = UiTheme.DIM
	box.add_child(l)
	return l


## 머리 범례: 비교면 실험마다 선 견본(A 실선·B 점선) + display_name(), 혼자면 실험 이름만(선이 하나라 견본 없음)
func _rebuild_legend() -> void:
	if _legend == null:
		return
	var list: Array[Dictionary] = []
	if series.is_empty():
		list.append({text = EMPTY_LEGEND, key = false, color = Color.WHITE, dashed = false})
	elif series.size() == 1:
		list.append({text = series[0].name, key = false, color = Color.WHITE, dashed = false})
	else:
		for k in series.size():
			list.append({text = series[k].name, key = true, color = series_color(k), dashed = series_dashed(k)})
	_legend.set_items(list)


## 범례에 보이는 이름들(검사용)
func legend_texts() -> PackedStringArray:
	var out := PackedStringArray()
	if _legend != null:
		for it in _legend.items:
			out.append(str(it.text))
	return out


## 범례 항목(검사용): {text, color, dashed, key}
func legend_items() -> Array[Dictionary]:
	return _legend.items if _legend != null else []
