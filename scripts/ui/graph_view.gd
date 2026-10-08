class_name GraphView
extends Control
## 그래프 하나(개체 수·평균 특성·기술 단계). GraphPanel 이 셋을 만들고 데이터(Series)·가로축·마우스 값을 준다.
## 계약: docs/VIEW-API.md "GraphPanel".
##
## 줄이기(M4): 가로 픽셀 열마다 연속한 줄 가운데 첫·최소·최대·끝 줄만 남긴다 — 줄이 수천 개여도 점은 폭의 4배 이하이고
## 열마다 최소·최대가 그대로라 뾰족한 값이 사라지지 않는다. 묶음(Runs)은 원래 줄 번호만 가지므로 세로 범위가 바뀌어도
## 다시 묶지 않는다. 가로 범위·그림 폭·가로축·데이터가 바뀔 때만 처음부터 묶고, 그 사이에는 새 줄만 더한다.
## 비교 모드의 B 는 점선 — 가로 위치 기준 무늬라 선이 자잘하게 오르내려도 무늬가 고르다. 다만 가파른 조각(한 줄짜리
## 뾰족한 값·단계 오름)은 길이 기준 무늬라 무늬 자리 때문에 통째로 사라지지 않는다.
## 마우스 값(세로선·점·값 읽기)은 자식 겹(HoverLayer)에 따로 그린다 — 마우스가 움직이면 그 겹만 다시 그림.
## 화면 문자열·색·크기는 ui.json 의 graph·theme·lab 절.

const KIND_POP := 0
const KIND_TRAIT := 1
const KIND_CIV := 2

const EMPTY_TEXT := "기록 없음"
const EXTINCT_TEXT := "멸종"
const LANE_NAMES: Array[String] = ["저장고", "밭"]
## 저장고·밭 띠의 눈금 범위 글(띠마다 따로인 세로 범위 — 지금 값이 아님을 글 모양으로): "0~4"
const LANE_RANGE_TEXT := "0~%s"
const NO_RECORD_GEN := "— (이 세대 기록 없음%s)"
const NO_RECORD_TICK := "— (이 틱 기록 없음)"
## 띠 위 끝 선의 흐림(바닥선보다 옅게), 오른쪽 띠 범위 글과 그림 영역 사이(픽셀)
const LANE_TOP_ALPHA := 0.6
const RIGHT_LABEL_GAP := 4.0
## 시점 표시 세로선 굵기(발견·마우스 세로선 1px 보다 굵게 — 오래 남는 표시라 눈에 띄게)
const CURSOR_WIDTH := 2.0
## 세로로 긋는 점선(발견·멸종·시점 세로선)의 무늬 = graph.dash_px × 이 값(가로 선보다 촘촘히)
const VERTICAL_DASH_FRAC := 0.5
## 값 읽기 상자 안 선 견본의 점선 무늬 = graph.dash_px × 이 값(짧은 견본에서도 점선으로 보이게)
const KEY_DASH_FRAC := 0.6
## 값 읽기 상자의 세로 여백 = graph.tip_pad × 이 값
const TIP_PAD_V_FRAC := 0.6
## 출생·사망 견본 선의 최소 굵기(얇은 선(1px)의 견본도 색이 보이게)
const KEY_LINE_MIN := 1.5
## 가파른 조각: 세로 변화 > 가로 변화 × 이 값이고 무늬 한 칸(dash + gap)보다 길면 길이 기준 점선
const STEEP_RATIO := 2.0
## 글과 그 세로선 사이(픽셀), 눈금 표시 길이
const LABEL_GAP := 3.0
const TICK_LEN := 3.0
## 숫자 표시의 최대 소수 자릿수
const MAX_DECIMALS := 6
## 가로 눈금 이름 간격 배수(기본 간격 × 이 값들 가운데 가장 작은 것으로 이름이 겹치지 않게)
const LABEL_STEP_MULTS: Array[float] = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0]
## 가로 눈금 이름 사이 최소 여백(픽셀), 그림 폭이 넉넉한 간격(graph.x_label_min_px)의 이 배수보다 좁으면 "좁은 그림"
## (넉넉한 간격 대신 겹치지 않을 만큼만 띄움 — 통합 I04), 단위 글자("틱") 앞 여백
const X_LABEL_PAD := 8.0
const NARROW_LABEL_FACTOR := 2.5
const X_UNIT_GAP := 6.0


## 마우스 값만 그리는 겹(그래프와 같은 크기, 마우스는 통과). 마우스가 움직이면 이것만 다시 그린다 —
## 선·눈금·묶음은 그대로(새 데이터의 다시 그리기는 redraw_hz 로 따로).
class HoverLayer extends Control:
	var view: GraphView
	var draw_count := 0

	func _init(v: GraphView) -> void:
		view = v
		name = "HoverLayer"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		draw_count += 1
		view._draw_hover_on(self)


## 한 실험의 줄마다 가로 픽셀 열(같은 그래프의 선들이 함께 씀). 가로 범위·폭이 바뀌면 버리고 새로.
class ColCache extends RefCounted:
	var cols := PackedInt32Array()

	## 아직 계산하지 않은 줄의 열을 더한다.
	func extend(xs: PackedFloat64Array, x0: float, sx: float, width: int) -> void:
		var n := xs.size()
		var k := cols.size()
		if k >= n:
			return
		cols.resize(n)
		var last_col := width - 1
		for i in range(k, n):
			var c := int(floorf((xs[i] - x0) * sx))
			cols[i] = 0 if c < 0 else (last_col if c > last_col else c)


## 한 선의 픽셀 열 묶음. 묶음 하나 = 같은 열에 연속으로 떨어진 줄들, idx 는 묶음마다 [첫, 최소, 최대, 끝] 줄 번호.
class Runs extends RefCounted:
	var col := PackedInt32Array()
	var idx := PackedInt32Array()
	## 1 = 앞 묶음과 잇지 않음(첫 묶음, 또는 사이에 빈 값(NaN) 줄이 있었음)
	var brk := PackedByteArray()
	## 지금까지 묶은 줄 수(다음에는 여기부터)
	var used := 0
	var _gap := false
	var _lo := 0.0
	var _hi := 0.0

	## used 부터 끝까지의 줄을 묶는다. x0·sx = 가로 값 → 열(픽셀) 변환, width = 열 수.
	func feed(xs: PackedFloat64Array, ys: PackedFloat64Array, x0: float, sx: float, width: int) -> void:
		var cc := ColCache.new()
		cc.extend(xs, x0, sx, width)
		feed_cols(cc.cols, ys, true)

	## 열 번호(cx, 줄마다)가 이미 있을 때. may_nan = false 면 NaN 확인을 건너뜀(개수 열).
	func feed_cols(cx: PackedInt32Array, ys: PackedFloat64Array, may_nan: bool) -> void:
		var n := mini(cx.size(), ys.size())
		if used >= n:
			return
		var m := col.size()
		var last_c := col[m - 1] if m > 0 else -1
		var b := (m - 1) * 4
		var lo := _lo
		var hi := _hi
		for i in range(used, n):
			var y := ys[i]
			if may_nan and is_nan(y):
				_gap = true
				continue
			var c := cx[i]
			if c == last_c and not _gap:
				if y < lo:
					lo = y
					idx[b + 1] = i
				elif y > hi:
					hi = y
					idx[b + 2] = i
				idx[b + 3] = i
			else:
				col.append(c)
				idx.append(i)
				idx.append(i)
				idx.append(i)
				idx.append(i)
				brk.append(1 if m == 0 or _gap else 0)
				_gap = false
				last_c = c
				b = m * 4
				m += 1
				lo = y
				hi = y
		_lo = lo
		_hi = hi
		used = n

	func count() -> int:
		return col.size()


var kind := KIND_POP
var panel: GraphPanel
## 그림 영역(이 Control 의 좌표). 세로 눈금 이름은 왼쪽 여백, 가로 눈금 이름은 아래 띠.
var plot := Rect2()
## 마지막 _draw 시간(µs)·횟수, 그린 선 통계(검사용): {series, col, points, dashed, segments, runs, width}
var last_draw_us := 0
var draw_count := 0
var last_lines: Array[Dictionary] = []
## 마지막으로 그린 발견 표시(검사용): {series, stage, x, labeled}
var last_markers: Array[Dictionary] = []
## 마지막으로 그린 멸종 표시(검사용): {series, x, text, dashed, rect}
var last_extinct: Array[Dictionary] = []
## 마지막으로 그린 시점 표시(검사용, 없으면 빈 배열): {series(틱 축 = -1), x(픽셀), data_x, tick, text, rect}
var last_cursor: Array[Dictionary] = []
## 마지막으로 그린 저장고·밭 띠 눈금 범위 글(검사용): {lane, text, rect}
var last_lane_labels: Array[Dictionary] = []
## 마지막으로 그린 가로축 이름(검사용): {text, value, rect}
var last_x_labels: Array[Dictionary] = []
## 마지막으로 그린 출생·사망 견본 글(검사용, 없으면 "")
var last_flow_key := ""
## 마지막 마우스 세로선 픽셀(검사용, 없으면 NaN)
var last_hover_px := NAN
## 점선 조각이 모두 무늬 틈에 들어 그리지 않은 횟수(검사용 — 빈 배열을 draw_multiline 에 넘기면 엔진 오류)
var dash_skipped := 0
## 묶음을 처음부터 다시 만든 횟수(검사용: 새 줄만 오면 늘지 않음)
var rebuild_count := 0

# 지금 배치(_layout 결과)
var _x0 := 0.0
var _x1 := 1.0
var _xstep := 1.0
var _sx := 1.0
var _y0 := 0.0
var _y1 := 1.0
var _y_ticks := PackedFloat64Array()
var _y_decimals := 0
var _stage_rect := Rect2()
var _lane_rects: Array[Rect2] = []
var _lane_max := PackedFloat64Array([1.0, 1.0])
## 띠마다 실제 자료 최댓값(0 이면 범위 글을 쓰지 않음 — 아무것도 없는데 "1" 이 보이지 않게)
var _lane_data := PackedFloat64Array([0.0, 0.0])
var _gutter := 0.0
var _gutter_key := []
var _layout_key := []
var _runs: Dictionary = {}
var _cols: Dictionary = {}
var _runs_key := []
var _hover_layer: HoverLayer
## 점선 조각을 모으는 버퍼(_xdash_seg 가 더함)
var _dash_buf := PackedVector2Array()

# ── 설정 값 ──
var _font: Font
var _fs := 12
var _lh := 14.0
var _ascent := 11.0
var _c_text := Color.WHITE
var _c_dim := Color.GRAY
var _c_grid := Color.DIM_GRAY
var _c_axis := Color.GRAY
var _c_bg := Color.BLACK
var _c_tip := Color.BLACK
var _c_tip_border := Color.GRAY
var _c_danger := Color.RED
var _c_cursor := Color.YELLOW
var _c_hover := Color.GRAY
var _c_births := Color.BLUE
var _c_deaths := Color.GRAY
var _line_w := 2.0
var _thin_w := 1.0
var _lane_w := 1.5
var _extinct_alpha := 0.8
var _dash := 6.0
var _dash_gap := 4.0
var _point_r := 2.5
var _hover_r := 3.5
var _ring := 2.0
var _pad_top := 6.0
var _pad_right := 8.0
var _gutter_min := 26.0
var _gutter_gap := 6.0
var _x_label_gap := 3.0
var _x_label_min := 64.0
var _y_tick_min := 26.0
var _y_ticks_max := 5
var _y_pad_frac := 0.08
var _y_min_span_frac := 0.04
var _lane_frac := 0.17
var _lane_gap := 6.0
var _stage_offset := 1.5
var _marker_alpha := 0.7
var _marker_faint := 0.25
var _markers_all := true
var _tip_pad := 6.0
var _tip_offset := 10.0
var _key_w := 18.0
var _tip_style: StyleBoxFlat
var _cursor_style: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true
	custom_minimum_size = Vector2(UiConfig.num("graph.min_width"), UiConfig.num("graph.min_height"))
	_read_config()
	_hover_layer = HoverLayer.new(self)
	add_child(_hover_layer)


func _read_config() -> void:
	_font = UiTheme.regular_font()
	_fs = UiConfig.integer("graph.axis_font_size")
	_lh = _font.get_height(_fs)
	_ascent = _font.get_ascent(_fs)
	_c_text = UiTheme.color("text")
	_c_dim = UiTheme.color("text_dim")
	_c_bg = UiTheme.color("background")
	_c_tip = UiTheme.color("toast")
	_c_tip_border = UiTheme.color("panel_border")
	_c_danger = UiTheme.color("danger")
	_c_grid = UiConfig.color("graph.grid")
	_c_axis = UiConfig.color("graph.axis")
	_c_cursor = UiConfig.color("graph.cursor")
	_c_hover = UiConfig.color("graph.hover_line")
	_c_births = UiConfig.color("graph.births")
	_c_deaths = UiConfig.color("graph.deaths")
	_line_w = UiConfig.num("graph.line_width")
	_thin_w = UiConfig.num("graph.thin_width")
	_lane_w = UiConfig.num("graph.lane_line_width")
	_extinct_alpha = UiConfig.num("graph.extinct_alpha")
	_dash = UiConfig.num("graph.dash_px")
	_dash_gap = UiConfig.num("graph.dash_gap_px")
	_point_r = UiConfig.num("graph.point_radius")
	_hover_r = UiConfig.num("graph.hover_dot_radius")
	_ring = UiConfig.num("graph.surface_ring_px")
	_pad_top = UiConfig.num("graph.pad_top")
	_pad_right = UiConfig.num("graph.pad_right")
	_gutter_min = UiConfig.num("graph.gutter_min")
	_gutter_gap = UiConfig.num("graph.gutter_gap")
	_x_label_gap = UiConfig.num("graph.x_label_gap")
	_x_label_min = UiConfig.num("graph.x_label_min_px")
	_y_tick_min = UiConfig.num("graph.y_tick_min_px")
	_y_ticks_max = UiConfig.integer("graph.y_ticks_max")
	_y_pad_frac = UiConfig.num("graph.y_pad_frac")
	_y_min_span_frac = UiConfig.num("graph.y_min_span_frac")
	_lane_frac = UiConfig.num("graph.lane_frac")
	_lane_gap = UiConfig.num("graph.lane_gap_px")
	_stage_offset = UiConfig.num("graph.stage_offset_px")
	_marker_alpha = UiConfig.num("graph.marker_alpha")
	_marker_faint = UiConfig.num("graph.marker_faint_alpha")
	_markers_all = bool(UiConfig.value("graph.markers_on_all", true))
	_tip_pad = UiConfig.num("graph.tip_pad")
	_tip_offset = UiConfig.num("graph.tip_offset_px")
	_key_w = UiConfig.num("graph.legend_key_px")
	_tip_style = UiTheme.box(_c_tip, _c_tip_border, 1, UiConfig.integer("graph.tip_radius"), _tip_pad, _tip_pad * TIP_PAD_V_FRAC)
	_cursor_style = UiTheme.box(Color(_c_bg, UiConfig.num("graph.cursor_label_alpha")), Color(0, 0, 0, 0), 0, UiConfig.integer("graph.tip_radius"),
			UiConfig.num("graph.cursor_label_pad_h"), UiConfig.num("graph.cursor_label_pad_v"))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			if panel != null:
				panel.clear_hover()


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		hover_at(mm.position)


## 마우스가 pos(이 Control 좌표)에 있을 때와 같게(검사도 부름). 그림 영역 가로 밖이면 지움.
## 배치는 크기·데이터가 그대로면 앞 계산을 그대로 쓴다(layout_now).
func hover_at(pos: Vector2) -> void:
	if panel == null:
		return
	layout_now()
	if pos.x < plot.position.x or pos.x > plot.end.x or pos.y < 0.0 or pos.y > size.y:
		panel.clear_hover()
		return
	panel.set_hover(self, px_to_data(pos.x))


## 마우스 겹만 다시 그리기(GraphPanel 이 마우스가 움직였을 때 부름)
func queue_hover_redraw() -> void:
	_hover_layer.queue_redraw()


## 마우스 겹을 그린 횟수(검사용)
func hover_draw_count() -> int:
	return _hover_layer.draw_count


## 픽셀 길이 px 의 가로 값 폭(지금 배치)
func px_span(px: float) -> float:
	return px / maxf(1e-9, _sx)


# ════════════════════════════ 정적 도움 ════════════════════════════

## 눈금 간격: span 을 target 칸쯤으로 나누는 1·2·2.5·5 × 10^k(integer 면 1 이상 정수).
static func nice_step(span: float, target: int, integer: bool = false) -> float:
	if not (span > 0.0) or is_inf(span):
		return 1.0
	var raw := span / float(maxi(1, target))
	var mag := pow(10.0, floorf(log(raw) / log(10.0)))
	var f := raw / mag
	var nf := 10.0
	if f <= 1.0:
		nf = 1.0
	elif f <= 2.0:
		nf = 2.0
	elif f <= 2.5 and not (integer and mag < 10.0):
		nf = 2.5
	elif f <= 5.0:
		nf = 5.0
	var step := nf * mag
	if integer:
		step = maxf(1.0, roundf(step))
	return step


## 간격 step 의 눈금을 정확히 쓰는 데 드는 소수 자릿수
static func decimals_for(step: float) -> int:
	var d := 0
	while d < MAX_DECIMALS:
		var s := step * pow(10.0, d)
		if absf(s - roundf(s)) < 1e-6 * maxf(1.0, absf(s)):
			break
		d += 1
	return d


## 수 → 글자(세 자리 쉼표, 소수 d 자리). -0 은 0.
static func fmt_num(v: float, d: int) -> String:
	if is_nan(v):
		return "—"
	var lim := 0.5 * pow(10.0, -d)
	if absf(v) < lim:
		v = 0.0
	var s := ("%." + str(d) + "f") % absf(v)
	var int_part := s
	var frac := ""
	var dot := s.find(".")
	if dot >= 0:
		int_part = s.substr(0, dot)
		frac = s.substr(dot)
	var out := ""
	var n := int_part.length()
	for i in n:
		out += int_part[i]
		var rest := n - 1 - i
		if rest > 0 and rest % 3 == 0:
			out += ","
	return ("-" if v < 0.0 else "") + out + frac


## 값 크기에 맞춘 읽기용 자릿수(100 이상 0, 10 이상 1, 1 이상 2, 그 밖 3)
static func fmt_auto(v: float) -> String:
	var a := absf(v)
	var d := 3
	if a >= 100.0:
		d = 0
	elif a >= 10.0:
		d = 1
	elif a >= 1.0:
		d = 2
	return fmt_num(v, d)


## 줄이기만 따로(검사용): xs·ys 를 [x0, x1] 를 width 열로 나눠 묶는다.
static func reduce(xs: PackedFloat64Array, ys: PackedFloat64Array, x0: float, x1: float, width: int) -> Runs:
	var r := Runs.new()
	var w := maxi(1, width)
	r.feed(xs, ys, x0, float(w) / maxf(1e-9, x1 - x0), w)
	return r


## 묶음 → 그릴 줄 번호 목록(끊긴 곳마다 따로). 묶음마다 첫 → (최소·최대를 일어난 순서로) → 끝, 같은 줄은 한 번.
## (그리기는 _draw_line 이 같은 순서로 바로 좌표를 만든다. 이것은 검사용.)
static func run_indices(r: Runs) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var cur := PackedInt32Array()
	for k in r.col.size():
		if r.brk[k] == 1 and cur.size() > 0:
			out.append(cur)
			cur = PackedInt32Array()
		var b := k * 4
		var a := r.idx[b]
		var lo := r.idx[b + 1]
		var hi := r.idx[b + 2]
		var z := r.idx[b + 3]
		var m1 := lo if lo < hi else hi
		var m2 := hi if lo < hi else lo
		cur.append(a)
		if m1 != a:
			cur.append(m1)
		if m2 != m1:
			cur.append(m2)
		if z != m2:
			cur.append(z)
	if cur.size() > 0:
		out.append(cur)
	return out


# ════════════════════════════ 좌표 ════════════════════════════

## 가로 값 → 픽셀(이 Control 좌표)
func data_to_px(x: float) -> float:
	return plot.position.x + (x - _x0) * _sx


func px_to_data(px: float) -> float:
	return _x0 + (px - plot.position.x) / maxf(1e-9, _sx)


## index 번째 실험 row 번째 줄의 col 열 점(지금 배치 기준, 검사용). 단계 열은 계단 높이(비교면 엇갈림 포함).
func point_px(index: int, row: int, col: int) -> Vector2:
	layout_now()
	var s := panel.series[index]
	var x := data_to_px(panel.row_x(index, row))
	return Vector2(x, _value_y(index, col, s.cols[col][row]))


## 지금 크기·데이터로 배치를 계산(그리기 없이). 검사·마우스·그리기가 부른다. 크기·데이터·가로축·고르기가
## 앞 계산 때와 같으면 그대로 둔다(마우스가 움직일 때마다 눈금 글 폭을 다시 재지 않게).
func layout_now() -> void:
	if panel == null:
		return
	var key: Array = [size, panel.epoch, panel.data_rev, panel.x_mode, panel.trait_index, panel.show_flows, panel.series.size()]
	if key == _layout_key:
		return
	_layout_key = key
	_layout()


## 지금 세로 범위(검사용): 개체 수·평균 특성 = (아래, 위), 기술 단계 = (0, 3)
func y_range() -> Vector2:
	layout_now()
	if kind == KIND_CIV:
		return Vector2(0.0, float(SimWorld.STAGE_NAMES.size() - 1))
	return Vector2(_y0, _y1)


func y_ticks() -> PackedFloat64Array:
	layout_now()
	return _y_ticks


## 열 col 의 값 v 가 놓일 세로 픽셀
func _value_y(index: int, col: int, v: float) -> float:
	var tf := _ytf(index, col)
	return tf.x - (v - tf.y) * tf.z


## 세로 변환 y = x − (v − y) × z 의 (바닥 픽셀, 바닥 값, 값 1 의 픽셀). 단계 열은 계단 높이(+ 비교 엇갈림), 저장고·밭은 각 띠.
func _ytf(index: int, col: int) -> Vector3:
	if kind == KIND_CIV:
		if col == GraphPanel.C_STAGE:
			var sp := _stage_rect.size.y / float(SimWorld.STAGE_NAMES.size())
			return Vector3(_stage_rect.end.y - sp * 0.5 + _stage_shift(index), 0.0, sp)
		var lane := 0 if col == GraphPanel.C_STORES else 1
		var r := _lane_rects[lane]
		return Vector3(r.end.y, 0.0, r.size.y / maxf(1e-9, _lane_max[lane]))
	return Vector3(plot.end.y, _y0, plot.size.y / maxf(1e-9, _y1 - _y0))


func _stage_y(level: float) -> float:
	var n := float(SimWorld.STAGE_NAMES.size())
	var sp := _stage_rect.size.y / n
	return _stage_rect.end.y - sp * (level + 0.5)


## 비교 모드에서 계단선이 겹쳐 하나로 보이지 않게 A 는 위·B 는 아래로 조금(픽셀만, 값은 그대로)
func _stage_shift(index: int) -> float:
	if panel == null or not panel.is_compare():
		return 0.0
	return -_stage_offset if index == 0 else _stage_offset


# ════════════════════════════ 배치 ════════════════════════════

func _layout() -> void:
	var xr := panel._x_range()
	_x0 = xr.x
	_x1 = xr.y
	_xstep = xr.z
	# 위쪽 글 띠: 기술 단계 = 발견 이름, 개체 수 + 출생·사망 = 견본·단위
	var top := _pad_top + (_lh if kind == KIND_CIV or (kind == KIND_POP and panel.show_flows) else 0.0)
	var x_band := _lh + _x_label_gap
	var h := maxf(1.0, size.y - top - x_band)
	var labels := PackedStringArray()
	match kind:
		KIND_POP:
			var hi := 0.0
			for s in panel.series:
				if s.size() == 0:
					continue
				hi = maxf(hi, s.hi[GraphPanel.C_POP])
				if panel.show_flows:
					hi = maxf(hi, maxf(s.hi[GraphPanel.C_BIRTHS], s.hi[GraphPanel.C_DEATHS]))
			_set_y_range(0.0, maxf(hi, 1.0), true, true, h)
		KIND_TRAIT:
			var c := panel.trait_col()
			var lo := INF
			var hi := -INF
			for s in panel.series:
				if s.size() == 0 or s.lo[c] == INF:
					continue
				lo = minf(lo, s.lo[c])
				hi = maxf(hi, s.hi[c])
			if lo == INF:
				lo = 0.0
				hi = 1.0
			_set_y_range(lo, hi, false, false, h)
		KIND_CIV:
			_y0 = 0.0
			_y1 = float(SimWorld.STAGE_NAMES.size() - 1)
			_y_ticks = PackedFloat64Array()
			for k in SimWorld.STAGE_NAMES.size():
				_y_ticks.append(float(k))
			for k in 2:
				var c := GraphPanel.C_STORES if k == 0 else GraphPanel.C_FARMS
				var m := 0.0
				for s in panel.series:
					if s.size() > 0:
						m = maxf(m, s.hi[c])
				_lane_data[k] = m
				_lane_max[k] = _nice_ceil(maxf(m, 1.0), true)
	if kind == KIND_CIV:
		labels.append_array(SimWorld.STAGE_NAMES)
		labels.append_array(LANE_NAMES)
	else:
		for v in _y_ticks:
			labels.append(fmt_num(v, _y_decimals))
	var gw := _gutter_min
	for l in labels:
		gw = maxf(gw, ceilf(_font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x) + _gutter_gap)
	# 같은 데이터·설정 동안에는 여백을 줄이지 않는다(폭이 자주 바뀌면 묶음을 자꾸 다시 만듦)
	var gk := [panel.epoch, panel.x_mode, panel.trait_index, panel.show_flows, size.x]
	if gk != _gutter_key:
		_gutter_key = gk
		_gutter = 0.0
	_gutter = maxf(_gutter, gw)
	# 기술 단계: 오른쪽에 띠 범위 글 자리(글이 아직 없어도 — 첫 저장고가 생길 때 그림 폭이 바뀌지 않게)
	var pad_r := _pad_right
	if kind == KIND_CIV:
		for k in 2:
			pad_r = maxf(pad_r, ceilf(_font.get_string_size(_lane_text(k), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x) + RIGHT_LABEL_GAP + 2.0)
	var w := maxf(1.0, size.x - _gutter - pad_r)
	plot = Rect2(roundf(_gutter), roundf(top), floorf(w), floorf(h))
	_sx = plot.size.x / maxf(1e-9, _x1 - _x0)
	if kind == KIND_CIV:
		var lane_h := floorf(plot.size.y * _lane_frac)
		var stage_h := plot.size.y - 2.0 * (lane_h + _lane_gap)
		_stage_rect = Rect2(plot.position, Vector2(plot.size.x, stage_h))
		_lane_rects = [
			Rect2(plot.position.x, _stage_rect.end.y + _lane_gap, plot.size.x, lane_h),
			Rect2(plot.position.x, _stage_rect.end.y + 2.0 * _lane_gap + lane_h, plot.size.x, lane_h),
		]


## 세로 범위와 눈금: from_zero 면 0 부터(개수), 아니면 자료 범위에 여유(y_pad_frac)를 두고 눈금 간격의 배수로 넓힘.
## 범위가 값 크기의 y_min_span_frac 보다 좁으면(평평하거나 아주 작은 흔들림) 가운데를 두고 그만큼 넓힌다 —
## 0.0003 같은 잡음이 그래프 높이를 다 차지해 큰 변화처럼 보이지 않게(값이 0 근처면 폭 1).
## 눈금은 많아야 y_ticks_max 개, 간격은 y_tick_min_px 이상(그림이 그보다 낮으면 위·아래 둘): 양 끝을 간격의
## 배수로 넓히면 칸이 늘 수 있어서, 넘치면 다음 간격(1·2·2.5·5 × 10^k)으로 다시.
func _set_y_range(lo: float, hi: float, from_zero: bool, integer: bool, h: float) -> void:
	var max_iv := maxi(1, mini(int(h / maxf(1.0, _y_tick_min)), _y_ticks_max - 1))
	var a := lo
	var b := hi
	if from_zero:
		a = 0.0
	else:
		var span := hi - lo
		var mid := (lo + hi) * 0.5
		var min_span := absf(mid) * _y_min_span_frac
		if min_span <= 1e-9:
			min_span = 1.0
		if span < min_span:
			a = mid - min_span * 0.5
			b = mid + min_span * 0.5
		else:
			a = lo - span * _y_pad_frac
			b = hi + span * _y_pad_frac
		# 자료가 모두 0 이상이면 축도 0 아래로 내려가지 않게
		if lo >= 0.0 and a < 0.0:
			a = 0.0
	var step := nice_step(b - a, max_iv, integer)
	var iv := _y_span_for(a, b, step)
	# 칸이 넘치면 큰 간격을 몇 번 더 보고 칸이 가장 적은 것 가운데 가장 작은 간격(0 을 사이에 둔 자료는 늘 두 칸 이상)
	var s := step
	var tries := 0
	while iv > max_iv and tries < 8:
		s = next_nice(s, integer)
		var niv := _y_span_for(a, b, s)
		if niv < iv:
			iv = niv
			step = s
		tries += 1
	_y0 = floorf(a / step + 1e-9) * step
	_y1 = maxf(ceilf(b / step - 1e-9) * step, _y0 + step)
	_y_decimals = 0 if integer else decimals_for(step)
	_y_ticks = PackedFloat64Array()
	var v := _y0
	var guard := 0
	while v <= _y1 + step * 1e-6 and guard < 64:
		_y_ticks.append(v)
		v += step
		guard += 1


## [a, b] 를 간격 step 의 배수로 넓혔을 때의 칸 수(1 이상)
static func _y_span_for(a: float, b: float, step: float) -> int:
	var y0 := floorf(a / step + 1e-9) * step
	var y1 := maxf(ceilf(b / step - 1e-9) * step, y0 + step)
	return maxi(1, roundi((y1 - y0) / step))


static func _nice_ceil(v: float, integer: bool) -> float:
	var step := nice_step(v, 2, integer)
	return maxf(step, ceilf(v / step - 1e-9) * step)


## 1·2·2.5·5 × 10^k 사다리에서 step 다음(더 큰) 간격(integer 면 10 미만에서 2.5 를 건너뜀)
static func next_nice(step: float, integer: bool = false) -> float:
	if not (step > 0.0) or is_inf(step):
		return 1.0
	var mag := pow(10.0, floorf(log(step) / log(10.0) + 1e-9))
	var f := step / mag
	if f < 1.5:
		return 2.0 * mag
	if f < 2.25:
		return (5.0 if integer and mag < 10.0 else 2.5) * mag
	if f < 3.75:
		return 5.0 * mag
	return 10.0 * mag


## 띠 k 의 눈금 범위 글("0~4")
func _lane_text(k: int) -> String:
	return LANE_RANGE_TEXT % fmt_num(_lane_max[k], 0)


# ════════════════════════════ 그리기 ════════════════════════════

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	draw_count += 1
	last_lines.clear()
	last_markers.clear()
	last_extinct.clear()
	last_cursor.clear()
	last_lane_labels.clear()
	last_x_labels.clear()
	last_flow_key = ""
	# 마우스 겹은 선·범위가 바뀌면 함께 다시(점 높이가 세로 범위를 따름)
	_hover_layer.queue_redraw()
	if panel == null:
		return
	layout_now()
	var key := [_x0, _x1, int(plot.size.x), panel.x_mode, panel.epoch]
	if key != _runs_key:
		_runs_key = key
		_runs.clear()
		_cols.clear()
		rebuild_count += 1
	var total := 0
	for s in panel.series:
		total += s.size()
	_draw_grid(total > 0)
	_draw_x_axis(total > 0)
	if total == 0:
		draw_string(_font, Vector2(plot.position.x, plot.get_center().y + _ascent * 0.5), EMPTY_TEXT,
				HORIZONTAL_ALIGNMENT_CENTER, plot.size.x, _fs, _c_dim)
		last_draw_us = Time.get_ticks_usec() - t0
		return
	if kind == KIND_POP and panel.show_flows:
		_draw_flow_key()
	_draw_markers()
	_draw_cursor()
	# B 를 먼저(아래), A 를 위에
	for si in range(panel.series.size() - 1, -1, -1):
		_draw_series(si)
	last_draw_us = Time.get_ticks_usec() - t0


## 가로 눈금선과 세로축 글. labels = false(기록 없음)면 선만(뜻 없는 눈금 값을 보이지 않게).
func _draw_grid(labels: bool) -> void:
	var x0 := plot.position.x
	var x1 := plot.end.x
	if kind == KIND_CIV:
		for k in SimWorld.STAGE_NAMES.size():
			var y := roundf(_stage_y(float(k))) + 0.5
			draw_line(Vector2(x0, y), Vector2(x1, y), _c_grid, 1.0)
			if labels:
				_draw_y_label(SimWorld.STAGE_NAMES[k], y)
		# 저장고·밭 띠(작은 그래프 둘): 이름은 왼쪽, 띠마다 따로인 세로 범위("0~N")는 오른쪽 — 그 띠 상자 안 세로 가운데
		# (위 끝 선 자리에 두면 아래 띠의 범위 글이 위 띠 선의 끝 옆에 놓여 지금 값처럼 읽혔다). 자료가 모두 0 이면 쓰지 않음.
		for k in 2:
			var r := _lane_rects[k]
			var yb := roundf(r.end.y) + 0.5
			var yt := roundf(r.position.y) + 0.5
			draw_line(Vector2(x0, yt), Vector2(x1, yt), Color(_c_grid, LANE_TOP_ALPHA), 1.0)
			draw_line(Vector2(x0, yb), Vector2(x1, yb), _c_grid, 1.0)
			if not labels:
				continue
			_draw_y_label(LANE_NAMES[k], r.get_center().y)
			if _lane_data[k] > 0.0:
				var t := _lane_text(k)
				var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
				var base := r.get_center().y + (_ascent - _font.get_descent(_fs)) * 0.5
				var lx := x1 + RIGHT_LABEL_GAP
				draw_string(_font, Vector2(lx, base), t, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_dim)
				last_lane_labels.append({lane = k, text = t, rect = Rect2(lx, base - _ascent, tw, _lh)})
		return
	for v in _y_ticks:
		var y := roundf(_value_y(0, -1, v)) + 0.5
		draw_line(Vector2(x0, y), Vector2(x1, y), _c_grid, 1.0)
		if labels:
			_draw_y_label(fmt_num(v, _y_decimals), y)


func _draw_y_label(text: String, y: float) -> void:
	var w := plot.position.x - _gutter_gap
	draw_string(_font, Vector2(0.0, y + (_ascent - _font.get_descent(_fs)) * 0.5), text, HORIZONTAL_ALIGNMENT_RIGHT, w, _fs, _c_dim)


func _draw_x_axis(labels: bool) -> void:
	var yb := roundf(plot.end.y) + 0.5
	draw_line(Vector2(plot.position.x, yb), Vector2(plot.end.x, yb), _c_axis, 1.0)
	if not labels:
		return
	var unit := str(GraphPanel.X_UNITS.get(panel.x_mode, ""))
	var uw := _font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
	var base_y := plot.end.y + _x_label_gap + _ascent
	draw_string(_font, Vector2(size.x - uw - 1.0, base_y), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_dim)
	var right_lim := size.x - uw - X_UNIT_GAP
	var integer := panel.x_mode == GraphPanel.X_TICK
	# 이름이 겹치지 않는 가장 작은 간격 배수
	var widest := _font.get_string_size(fmt_num(_x1, 0) + "0", HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
	var need := maxf(_x_label_min, widest + X_LABEL_PAD)
	# 좁은 그림(1280 창의 아래 자리, 통합 때 더함): 넉넉한 간격이면 이름이 "0" 하나만 남으므로 겹치지 않을 만큼만 띄움
	if plot.size.x < need * NARROW_LABEL_FACTOR:
		need = widest + X_LABEL_PAD
	var pick := LABEL_STEP_MULTS.size() - 1
	for i in LABEL_STEP_MULTS.size():
		if _xstep * LABEL_STEP_MULTS[i] * _sx >= need:
			pick = i
			break
	var placed := _x_label_layout(_xstep * LABEL_STEP_MULTS[pick], integer, base_y, right_lim)
	# 소수 이름("0.5")은 위 어림(정수 글자 폭)보다 넓을 수 있다: 겹치면 더 넓은 간격으로
	while not _x_labels_apart(placed) and pick < LABEL_STEP_MULTS.size() - 1:
		pick += 1
		placed = _x_label_layout(_xstep * LABEL_STEP_MULTS[pick], integer, base_y, right_lim)
	# 그래도 이름이 하나뿐이면(예전: 1280 창 기술 단계 그래프의 1,212틱에서 "0" 만 — 띠 범위 글 자리만큼 그림이 좁아진 뒤),
	# 이름이 둘 이상이고 서로 X_LABEL_PAD 이상 떨어지는 가장 넓은 간격으로 낮춘다(4단계 검토 통합 때 고침)
	if placed.size() < 2:
		for i in range(pick - 1, -1, -1):
			var alt := _x_label_layout(_xstep * LABEL_STEP_MULTS[i], integer, base_y, right_lim)
			if alt.size() < 2:
				continue
			if not _x_labels_apart(alt):
				break
			pick = i
			placed = alt
			break
	var ls := _xstep * LABEL_STEP_MULTS[pick]
	var v := ceilf(_x0 / ls - 1e-9) * ls
	var guard := 0
	while v <= _x1 + ls * 1e-6 and guard < 200:
		guard += 1
		var px := roundf(data_to_px(v)) + 0.5
		draw_line(Vector2(px, yb), Vector2(px, yb + TICK_LEN), _c_axis, 1.0)
		v += ls
	for l in placed:
		var r: Rect2 = l.rect
		draw_string(_font, Vector2(r.position.x, base_y), str(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_dim)
	last_x_labels = placed


## 간격 ls 의 가로축 이름 자리 {text, value, rect}: 눈금 가운데(양 끝에서는 안쪽으로 붙임), 단위 글자 앞(right_lim)까지.
func _x_label_layout(ls: float, integer: bool, base_y: float, right_lim: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := 0 if integer else decimals_for(ls)
	var v := ceilf(_x0 / ls - 1e-9) * ls
	var guard := 0
	while v <= _x1 + ls * 1e-6 and guard < 200:
		guard += 1
		var px := roundf(data_to_px(v)) + 0.5
		var t := fmt_num(v, d)
		var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
		# 눈금 가운데, 양 끝에서는 안쪽으로 붙임(오른쪽은 단위 글자 앞까지) — 이름이 자기 눈금을 덮을 때만 씀
		var lx := clampf(px - tw * 0.5, 0.0, maxf(right_lim - tw, 0.0))
		var r := Rect2(lx, base_y - _ascent, tw, _lh)
		var covers := lx <= px and lx + tw >= px and r.end.x <= right_lim
		# 안쪽으로 붙인 끝 이름이 앞 이름에 붙으면 뺌(간격이 좁아서가 아니라 끝이라서 붙은 것)
		var pulled := lx < px - tw * 0.5 - 0.5
		if covers and pulled and not out.is_empty():
			var prev: Rect2 = out.back().rect
			covers = r.position.x - prev.end.x >= X_LABEL_PAD
		if covers:
			out.append({text = t, value = v, rect = r})
		v += ls
	return out


## 이웃한 이름 사이가 모두 X_LABEL_PAD 이상
func _x_labels_apart(labels: Array[Dictionary]) -> bool:
	for i in range(1, labels.size()):
		var a: Rect2 = labels[i - 1].rect
		var b: Rect2 = labels[i].rect
		if b.position.x - a.end.x < X_LABEL_PAD:
			return false
	return true


## 개체 수 그래프 위쪽 띠의 출생·사망 견본 + 단위("— 출생  — 사망  20틱당"). 단위까지 들어가지 않으면 단위만 뺌
## (값 읽기·단추 말풍선에 단위가 있음). 비교 모드에서도 실선 견본(A·B 는 선 무늬로 — 범례와 같음).
func _draw_flow_key() -> void:
	var base := plot.position.y - LABEL_GAP
	var mid := roundf(base - _ascent * 0.5 + _font.get_descent(_fs) * 0.5) + 0.5
	var names: Array[String] = ["출생", "사망"]
	var cols: Array[Color] = [_c_births, _c_deaths]
	var unit := panel.flow_unit()
	var key_gap := LABEL_GAP + 1.0
	var item_gap := _gutter_gap + 2.0
	var w := 0.0
	for k in 2:
		w += _key_w + key_gap + _font.get_string_size(names[k], HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x + item_gap
	var uw := _font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
	var with_unit := w + uw <= plot.size.x
	var x := plot.position.x
	var shown := PackedStringArray()
	for k in 2:
		draw_line(Vector2(x, mid), Vector2(x + _key_w, mid), cols[k], maxf(_thin_w, KEY_LINE_MIN), true)
		x += _key_w + key_gap
		draw_string(_font, Vector2(x, base), names[k], HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_dim)
		x += _font.get_string_size(names[k], HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x + item_gap
		shown.append(names[k])
	if with_unit:
		draw_string(_font, Vector2(x, base), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_dim)
		shown.append(unit)
	last_flow_key = " ".join(shown)


## 발견 표시: 기술 단계 그래프는 위 띠에 단계 이름까지, 다른 그래프는 흐린 세로선만(ui.graph.markers_on_all).
## 개체 수 그래프에는 멸종 표시(위험 색) — 비교 모드면 "A 멸종"·"B 멸종"(B 는 점선), 이름이 겹치면 한 줄씩 아래로.
func _draw_markers() -> void:
	var y_top := plot.position.y
	var y_bot := plot.end.y
	var label_spans: Array[Vector2] = []
	var ext_rects: Array[Rect2] = []
	for si in panel.series.size():
		var s := panel.series[si]
		var c := panel.series_color(si)
		var dashed := panel.series_dashed(si)
		if kind == KIND_CIV or _markers_all:
			var col := Color(c, _marker_alpha if kind == KIND_CIV else _marker_faint)
			for m in s.markers:
				var x := panel.marker_x(m)
				if x < _x0 or x > _x1:
					continue
				var px := roundf(data_to_px(x)) + 0.5
				if dashed:
					draw_dashed_line(Vector2(px, y_top), Vector2(px, y_bot), col, 1.0, _dash * VERTICAL_DASH_FRAC, false)
				else:
					draw_line(Vector2(px, y_top), Vector2(px, y_bot), col, 1.0)
				var labeled := false
				if kind == KIND_CIV:
					var t: String = SimWorld.STAGE_NAMES[int(m.stage)]
					var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
					var lx := px + LABEL_GAP
					if lx + tw > plot.end.x:
						lx = px - LABEL_GAP - tw
					var span := Vector2(lx - 2.0, lx + tw + 2.0)
					var free := true
					for o in label_spans:
						if span.x < o.y and o.x < span.y:
							free = false
							break
					if free:
						label_spans.append(span)
						draw_string(_font, Vector2(lx, y_top - LABEL_GAP), t, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_dim)
						labeled = true
				last_markers.append({series = si, stage = int(m.stage), x = px, labeled = labeled})
		if kind == KIND_POP and s.extinct_row >= 0:
			var ex := s.extinct_gen if panel.x_mode == GraphPanel.X_GEN else s.extinct_tick
			if ex >= _x0 and ex <= _x1:
				var px := roundf(data_to_px(ex)) + 0.5
				var ecol := Color(_c_danger, _extinct_alpha)
				if dashed:
					draw_dashed_line(Vector2(px, y_top), Vector2(px, y_bot), ecol, 1.0, _dash * VERTICAL_DASH_FRAC, false)
				else:
					draw_line(Vector2(px, y_top), Vector2(px, y_bot), ecol, 1.0)
				var t := EXTINCT_TEXT
				if panel.is_compare():
					t = "%s %s" % [s.tag if s.tag != "" else str(si + 1), EXTINCT_TEXT]
				var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
				var lx := px - LABEL_GAP - tw if px + LABEL_GAP + tw > plot.end.x else px + LABEL_GAP
				var rect := Rect2(lx - 2.0, y_top, tw + 4.0, _lh)
				var guard := 0
				while guard < 4 and ext_rects.any(func(o: Rect2) -> bool: return o.intersects(rect)):
					rect.position.y += _lh
					guard += 1
				ext_rects.append(rect)
				draw_string(_font, Vector2(lx, rect.position.y + _ascent), t, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_danger)
				last_extinct.append({series = si, x = px, text = t, dashed = dashed, rect = rect})


## 연대기 등이 요청한 시점. 틱 축 = 세로선 하나. 세대 축 = 실험마다 그 틱에 그 실험이 있던 평균 세대에(같은 시점도
## 실험마다 세대가 다름 — 첫 실험의 세대에 B 의 사건을 놓지 않게. 발견 표시·연대기 줄과 같은 값), 비교면 B 는 점선,
## 이름 "A · 틱 N". 이름이 겹치면 한 줄씩 위로.
func _draw_cursor() -> void:
	if panel.cursor_tick < 0 or panel.series.is_empty():
		return
	var rects: Array[Rect2] = []
	if panel.x_mode == GraphPanel.X_GEN:
		for si in panel.series.size():
			_draw_cursor_line(si, panel.cursor_x(si), rects)
	else:
		_draw_cursor_line(-1, float(panel.cursor_tick), rects)


func _draw_cursor_line(si: int, x: float, rects: Array[Rect2]) -> void:
	if is_nan(x) or x < _x0 or x > _x1:
		return
	var compare := panel.is_compare() and si >= 0
	var px := roundf(data_to_px(x))
	if compare and panel.series_dashed(si):
		draw_dashed_line(Vector2(px, plot.position.y), Vector2(px, plot.end.y), _c_cursor, CURSOR_WIDTH, _dash * VERTICAL_DASH_FRAC, false)
	else:
		draw_line(Vector2(px, plot.position.y), Vector2(px, plot.end.y), _c_cursor, CURSOR_WIDTH)
	var t := "틱 %s" % fmt_num(float(panel.cursor_tick), 0)
	if compare:
		var s := panel.series[si]
		t = "%s · %s" % [s.tag if s.tag != "" else str(si + 1), t]
	var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
	var pad_h := _cursor_style.content_margin_left
	var pad_v := _cursor_style.content_margin_top
	var lx := px + RIGHT_LABEL_GAP if px + RIGHT_LABEL_GAP + tw + RIGHT_LABEL_GAP <= plot.end.x else px - RIGHT_LABEL_GAP - tw
	var by := plot.end.y - RIGHT_LABEL_GAP
	var rect := Rect2(lx - pad_h, by - _ascent - pad_v, tw + pad_h * 2.0, _lh + pad_v * 2.0)
	var guard := 0
	while guard < 4 and rects.any(func(o: Rect2) -> bool: return o.intersects(rect)):
		rect.position.y -= rect.size.y
		guard += 1
	rects.append(rect)
	draw_style_box(_cursor_style, rect)
	draw_string(_font, Vector2(lx, rect.position.y + pad_v + _ascent), t, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_cursor)
	last_cursor.append({series = si, x = px, data_x = x, tick = panel.cursor_tick, text = t, rect = rect})


func _draw_series(si: int) -> void:
	var s := panel.series[si]
	if s.size() == 0:
		return
	var c := panel.series_color(si)
	var dashed := panel.series_dashed(si)
	match kind:
		KIND_POP:
			if panel.show_flows:
				_draw_line(si, GraphPanel.C_DEATHS, _c_deaths, _thin_w, dashed)
				_draw_line(si, GraphPanel.C_BIRTHS, _c_births, _thin_w, dashed)
			_draw_line(si, GraphPanel.C_POP, c, _line_w, dashed, true)
		KIND_TRAIT:
			_draw_line(si, panel.trait_col(), c, _line_w, dashed, true)
		KIND_CIV:
			_draw_steps(si, c, dashed)
			_draw_line(si, GraphPanel.C_STORES, c, _lane_w, dashed)
			_draw_line(si, GraphPanel.C_FARMS, c, _lane_w, dashed)


## index 번째 실험 col 열 선의 묶음(검사용: 마지막으로 그린 상태)
func line_runs(index: int, col: int) -> Runs:
	return _runs_for(index, col)


func _runs_for(si: int, col: int) -> Runs:
	var k := si * 64 + col
	var r: Runs = _runs.get(k)
	if r == null:
		r = Runs.new()
		_runs[k] = r
	return r


## index 번째 실험의 줄마다 가로 픽셀 열(이 그래프의 선들이 함께 씀, 새 줄만 계산)
func _cols_for(si: int) -> PackedInt32Array:
	var cc: ColCache = _cols.get(si)
	if cc == null:
		cc = ColCache.new()
		_cols[si] = cc
	cc.extend(panel.series[si].xs(panel.x_mode), _x0, _sx, maxi(1, int(plot.size.x)))
	return cc.cols


## 줄인 선 하나 그리기. end_dot 이면 마지막 점에 표면색 고리 + 점(지금 값의 자리).
## 묶음마다 첫 → 최소·최대(일어난 순서) → 끝 줄을 바로 좌표로(run_indices 와 같은 순서, 배열을 따로 만들지 않음).
func _draw_line(si: int, col: int, c: Color, width: float, dashed: bool, end_dot: bool = false) -> void:
	var s := panel.series[si]
	var xs := s.xs(panel.x_mode)
	var ys: PackedFloat64Array = s.cols[col]
	var r := _runs_for(si, col)
	r.feed_cols(_cols_for(si), ys, GraphPanel.MEAN_COLS.has(col))
	var px0 := plot.position.x
	var x0 := _x0
	var sx := _sx
	var tf := _ytf(si, col)
	var by := tf.x
	var y0 := tf.y
	var ky := tf.z
	var idx := r.idx
	var brk := r.brk
	var segs: Array[PackedVector2Array] = []
	var cur := PackedVector2Array()
	for k in r.col.size():
		if brk[k] == 1 and cur.size() > 0:
			segs.append(cur)
			cur = PackedVector2Array()
		var b := k * 4
		var a := idx[b]
		var lo := idx[b + 1]
		var hi := idx[b + 2]
		var z := idx[b + 3]
		var m1 := lo if lo < hi else hi
		var m2 := hi if lo < hi else lo
		cur.append(Vector2(px0 + (xs[a] - x0) * sx, by - (ys[a] - y0) * ky))
		if m1 != a:
			cur.append(Vector2(px0 + (xs[m1] - x0) * sx, by - (ys[m1] - y0) * ky))
		if m2 != m1:
			cur.append(Vector2(px0 + (xs[m2] - x0) * sx, by - (ys[m2] - y0) * ky))
		if z != m2:
			cur.append(Vector2(px0 + (xs[z] - x0) * sx, by - (ys[z] - y0) * ky))
	if cur.size() > 0:
		segs.append(cur)
	var pts_total := 0
	if dashed:
		_dash_buf.clear()
	for pts in segs:
		pts_total += pts.size()
		if pts.size() == 1:
			draw_circle(pts[0], maxf(_point_r, width), c)
		elif dashed:
			for j in pts.size() - 1:
				_xdash_seg(pts[j], pts[j + 1])
		else:
			draw_polyline(pts, c, width, true)
	if dashed:
		_draw_dash_buf(c, width)
	last_lines.append({series = si, col = col, points = pts_total, dashed = dashed, segments = segs.size(), runs = r.count(), width = width})
	if end_dot and r.count() > 0 and idx[(r.count() - 1) * 4 + 3] == s.size() - 1:
		var i := s.size() - 1
		var p := Vector2(px0 + (xs[i] - x0) * sx, by - (ys[i] - y0) * ky)
		draw_circle(p, _point_r + _ring, _c_bg)
		draw_circle(p, _point_r, c)


## 기술 단계 계단선: 단계가 오른 곳의 세로선은 정확한 발견 시점(그 사이 기록 두 줄 안으로 맞춤)에.
func _draw_steps(si: int, c: Color, dashed: bool) -> void:
	var s := panel.series[si]
	var n := s.size()
	var xs := s.xs(panel.x_mode)
	var st: PackedFloat64Array = s.cols[GraphPanel.C_STAGE]
	var dy := _stage_shift(si)
	var pts := PackedVector2Array()
	pts.append(Vector2(data_to_px(xs[0]), _stage_y(st[0]) + dy))
	for k in s.stage_rows:
		var prev := st[k - 1]
		for lvl in range(int(prev) + 1, int(st[k]) + 1):
			var x := xs[k]
			var m := s.marker_for(lvl)
			if not m.is_empty():
				x = clampf(panel.marker_x(m), minf(xs[k - 1], xs[k]), maxf(xs[k - 1], xs[k]))
			var px := data_to_px(x)
			pts.append(Vector2(px, _stage_y(float(lvl - 1)) + dy))
			pts.append(Vector2(px, _stage_y(float(lvl)) + dy))
	pts.append(Vector2(data_to_px(xs[n - 1]), _stage_y(st[n - 1]) + dy))
	if pts.size() == 2 and pts[0].is_equal_approx(pts[1]):
		draw_circle(pts[0], maxf(_point_r, _line_w), c)
	elif dashed:
		# 가로 마디는 가로 위치 기준 무늬, 세로(단계 오름)는 길이 기준(_xdash_seg) — 모두 모아 한 번에(빈 것은 그리지 않음)
		_dash_buf.clear()
		for j in pts.size() - 1:
			_xdash_seg(pts[j], pts[j + 1])
		_draw_dash_buf(c, _line_w)
	else:
		draw_polyline(pts, c, _line_w, true)
	last_lines.append({series = si, col = GraphPanel.C_STAGE, points = pts.size(), dashed = dashed, segments = 1, runs = s.stage_rows.size(), width = _line_w})
	var e := pts[pts.size() - 1]
	draw_circle(e, _point_r + _ring, _c_bg)
	draw_circle(e, _point_r, c)


## 모은 점선 조각을 그린다. 모든 조각이 무늬 틈에 들었으면(빈 배열) 그리지 않는다 — draw_multiline 에 빈 배열을
## 넘기면 엔진 오류(비교 모드 B 의 단계가 막 오른 뒤 짧은 가로 마디 등).
func _draw_dash_buf(c: Color, width: float) -> void:
	if _dash_buf.is_empty():
		dash_skipped += 1
		return
	draw_multiline(_dash_buf, c, width, true)


## 가로 위치 기준 점선: 그림 영역 왼쪽부터 [dash 켬, gap 끔] 무늬를 가로로 깔고, 켬 구간에 든 선 조각만 남긴다
## (draw_multiline 용 시작·끝 쌍). 가파른 조각은 길이 기준(_xdash_seg). 검사용 — 그리기는 _xdash_seg 로 바로 모음.
func _xdash(pts: PackedVector2Array) -> PackedVector2Array:
	_dash_buf.clear()
	for j in pts.size() - 1:
		_xdash_seg(pts[j], pts[j + 1])
	return _dash_buf.duplicate()


## 선 조각 a→b 의 점선 조각을 _dash_buf 에 더한다.
## - 가파른 조각(세로 변화 > 가로 변화 × STEEP_RATIO 이고 무늬 한 칸보다 김, 또는 가로 변화가 거의 0 — 줄인 선의 한 열
##   안 뾰족한 값·단계 오름): 조각 길이를 따라 [dash 켬, gap 끔](시작 = 켬). 가로 위치 무늬로 자르면 끔 열에 든
##   뾰족한 값이 통째로 사라졌다 — 이제 끝(꼭짓점)도 많아야 dash_gap 만큼만 덜 그려짐.
## - 그 밖: 가로 위치 무늬. 무늬 경계를 넘지 않는 조각(같은 열 안의 작은 세로 흔들림 등)은 통째로 켬/끔.
func _xdash_seg(a0: Vector2, b0: Vector2) -> void:
	var period := _dash + _dash_gap
	var adx := absf(b0.x - a0.x)
	var ady := absf(b0.y - a0.y)
	if adx < 0.01 or (ady > adx * STEEP_RATIO and ady >= period):
		_len_dash(a0, b0)
		return
	var a := a0
	var b := b0
	if b.x < a.x:
		var t := a
		a = b
		b = t
	var span := b.x - a.x
	var ox := plot.position.x
	var ph0 := fposmod(a.x - ox, period)
	if ph0 < _dash:
		if ph0 + span <= _dash:
			_dash_buf.append(a)
			_dash_buf.append(b)
			return
	elif ph0 + span <= period:
		return
	var x := a.x
	var guard := 0
	while x < b.x - 1e-4 and guard < 4096:
		guard += 1
		var ph := fposmod(x - ox, period)
		var on := ph < _dash
		var nx := x + ((_dash - ph) if on else (period - ph))
		nx = minf(maxf(nx, x + 1e-3), b.x)
		if on:
			_dash_buf.append(a.lerp(b, (x - a.x) / span))
			_dash_buf.append(a.lerp(b, (nx - a.x) / span))
		x = nx


## 길이 기준 점선(a 에서 켬으로 시작)
func _len_dash(a: Vector2, b: Vector2) -> void:
	var total := a.distance_to(b)
	if total <= _dash:
		_dash_buf.append(a)
		_dash_buf.append(b)
		return
	var period := _dash + _dash_gap
	var s := 0.0
	var guard := 0
	while s < total and guard < 4096:
		guard += 1
		_dash_buf.append(a.lerp(b, s / total))
		_dash_buf.append(a.lerp(b, minf(s + _dash, total) / total))
		s += period


# ════════════════════════════ 마우스 값 ════════════════════════════

## 마우스 겹(HoverLayer)이 부름: 기준 세로선 + 실험마다 그 줄의 점(이 자리에 기록이 없는 실험은 점 없음),
## 마우스가 있는 그래프면 값 읽기 상자. 계산은 GraphPanel.hover_state() 한 번(가로 값이 바뀔 때만).
func _draw_hover_on(ci: CanvasItem) -> void:
	last_hover_px = NAN
	if panel == null or is_nan(panel.hover_x) or panel.series.is_empty():
		return
	layout_now()
	var st := panel.hover_state()
	if st.anchor < 0:
		return
	var cx := roundf(data_to_px(st.anchor_x)) + 0.5
	last_hover_px = cx
	ci.draw_line(Vector2(cx, plot.position.y), Vector2(cx, plot.end.y), _c_hover, 1.0)
	for si in panel.series.size():
		var r := st.rows[si]
		if r < 0 or st.valid[si] == 0:
			continue
		var c := panel.series_color(si)
		for col in _hover_cols():
			var v: float = panel.series[si].cols[col][r]
			if is_nan(v):
				continue
			var p := Vector2(data_to_px(panel.row_x(si, r)), _value_y(si, col, v))
			ci.draw_circle(p, _hover_r + _ring, _c_bg)
			ci.draw_circle(p, _hover_r, c)
	if panel.hover_view == self:
		_draw_readout(ci, cx)


## 마우스 점을 찍을 열(이 그래프가 그리는 선)
func _hover_cols() -> Array[int]:
	match kind:
		KIND_POP:
			return [GraphPanel.C_POP]
		KIND_TRAIT:
			return [panel.trait_col()]
	return [GraphPanel.C_STAGE, GraphPanel.C_STORES, GraphPanel.C_FARMS]


## 값 읽기 줄들: 첫 줄 = 머리(기준 가로 값: 틱, 또는 평균 세대 · 출생·사망을 켰으면 그 단위), 그 뒤 실험마다 {text, series, valid}.
## 비교 모드: 세대 축이면 실험마다 자기 줄의 세대·틱, 틱 축이면 자기 줄의 틱이 머리와 다를 때 그 틱(기록 간격이 다를 때).
## 기준 근처에 기록이 없는 실험은 먼 줄의 값 대신 "— (이 세대 기록 없음 · 최고 G세대)" 또는 "멸종 (틱 N · G세대)".
## 마우스가 이 그래프 위에 없으면 빈 배열(다른 그래프에는 세로선·점만).
func readout_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if panel == null or is_nan(panel.hover_x) or panel.series.is_empty() or panel.hover_view != self:
		return out
	var st := panel.hover_state()
	if st.anchor < 0:
		return out
	var compare := panel.is_compare()
	var gen_mode := panel.x_mode == GraphPanel.X_GEN
	var head := ""
	if gen_mode:
		head = "평균 %s세대" % fmt_num(st.anchor_x, 1)
		if not compare:
			head += " · 틱 %s" % fmt_num(panel.series[st.anchor].tick[st.rows[st.anchor]], 0)
	else:
		head = "틱 %s" % fmt_num(st.anchor_x, 0)
	if kind == KIND_POP and panel.show_flows:
		head += " · 출생·사망 %s" % panel.flow_unit()
	out.append({text = head, series = -1, valid = true})
	for si in panel.series.size():
		var r := st.rows[si]
		if r < 0:
			continue
		var s := panel.series[si]
		var ok := st.valid[si] == 1
		var t := ""
		if ok:
			t = _row_text(s, r)
			if compare and gen_mode:
				t += " (%s세대 · 틱 %s)" % [fmt_num(s.gen_x[r], 1), fmt_num(s.tick[r], 0)]
			elif compare and s.tick[r] != st.anchor_x:
				t += " (틱 %s)" % fmt_num(s.tick[r], 0)
		else:
			t = _no_record_text(s, st.anchor_x)
		if compare:
			t = "%s  %s" % [s.tag if s.tag != "" else str(si + 1), t]
		out.append({text = t, series = si, valid = ok})
	return out


## 기준 가로 값 x 근처에 그 실험의 기록이 없을 때의 글
func _no_record_text(s: GraphPanel.Series, x: float) -> String:
	if panel.x_mode != GraphPanel.X_GEN:
		return NO_RECORD_TICK
	if s.extinct_row >= 0 and x > s.gen_hi:
		return "%s (틱 %s · %s세대)" % [EXTINCT_TEXT, fmt_num(s.extinct_tick, 0), fmt_num(s.extinct_gen, 1)]
	if x > s.gen_hi:
		return NO_RECORD_GEN % (" · 최고 %s세대" % fmt_num(s.gen_hi, 1))
	if x < s.gen_lo:
		return NO_RECORD_GEN % (" · 처음 %s세대" % fmt_num(s.gen_lo, 1))
	return NO_RECORD_GEN % ""


## 값 읽기 글(검사용): 줄들을 " / " 로 이음
func readout_text() -> String:
	var parts := PackedStringArray()
	for l in readout_lines():
		parts.append(str(l.text))
	return " / ".join(parts)


## 출생·사망(flow_ticks 틱당으로 고친 수)의 글: 정수면 정수, 아니면 소수 한 자리
static func fmt_rate(v: float) -> String:
	return fmt_num(v, 0 if absf(v - roundf(v)) < 0.05 else 1)


func _row_text(s: GraphPanel.Series, r: int) -> String:
	match kind:
		KIND_POP:
			var pop := s.cols[GraphPanel.C_POP][r]
			var t := "개체 %s" % fmt_num(pop, 0)
			if pop <= 0.0:
				t += " · " + EXTINCT_TEXT
			if panel.show_flows:
				# 단위(flow_per_ticks 틱당)는 머리 줄에 한 번
				t += " · 출생 %s · 사망 %s" % [fmt_rate(s.cols[GraphPanel.C_BIRTHS][r]), fmt_rate(s.cols[GraphPanel.C_DEATHS][r])]
			return t
		KIND_TRAIT:
			var ti := panel.trait_index
			var v := s.cols[GraphPanel.TRAIT_COLS[ti]][r]
			if is_nan(v):
				return "%s — (개체 없음)" % GraphPanel.TRAIT_NAMES[ti]
			var unit := GraphPanel.TRAIT_UNITS[ti]
			return "%s %s%s" % [GraphPanel.TRAIT_NAMES[ti], fmt_auto(v), (" " + unit) if unit != "" else ""]
	var stage := clampi(int(s.cols[GraphPanel.C_STAGE][r]), 0, SimWorld.STAGE_NAMES.size() - 1)
	return "%s · 저장고 %s · 밭 %s" % [SimWorld.STAGE_NAMES[stage], fmt_num(s.cols[GraphPanel.C_STORES][r], 0),
			fmt_num(s.cols[GraphPanel.C_FARMS][r], 0)]


func _draw_readout(ci: CanvasItem, cx: float) -> void:
	var raw := readout_lines()
	if raw.is_empty():
		return
	var key_space := (_key_w + _gutter_gap) if panel.is_compare() else 0.0
	var pad_h := _tip_style.content_margin_left
	var pad_v := _tip_style.content_margin_top
	# 좁은 그래프(1280 창 등)에서는 줄을 그래프 폭에 맞게 접는다(" · "·" (" 앞에서) — 상자가 그래프 밖으로 잘리지 않게
	var lines := wrap_readout(raw, size.x - pad_h * 2.0 - 2.0, key_space)
	var w := 0.0
	for l in lines:
		var lw := _font.get_string_size(str(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
		if int(l.series) >= 0:
			lw += key_space
		w = maxf(w, lw)
	var box := Vector2(ceilf(w + pad_h * 2.0), ceilf(_lh * lines.size() + pad_v * 2.0))
	var x := cx + _tip_offset
	if x + box.x > size.x:
		x = cx - _tip_offset - box.x
	x = clampf(x, 0.0, maxf(0.0, size.x - box.x))
	var y := plot.position.y + 2.0
	ci.draw_style_box(_tip_style, Rect2(Vector2(x, y), box))
	var ty := y + pad_v
	for l in lines:
		var tx := x + pad_h
		var si := int(l.series)
		if si >= 0 and panel.is_compare():
			if bool(l.first):
				var ky := roundf(ty + _lh * 0.5) + 0.5
				var c := panel.series_color(si)
				if panel.series_dashed(si):
					ci.draw_dashed_line(Vector2(tx, ky), Vector2(tx + _key_w, ky), c, _line_w, _dash * KEY_DASH_FRAC, false, true)
				else:
					ci.draw_line(Vector2(tx, ky), Vector2(tx + _key_w, ky), c, _line_w, true)
			tx += key_space
		var tc := _c_dim
		if si >= 0:
			tc = _c_text if bool(l.valid) else _c_dim
		ci.draw_string(_font, Vector2(tx, ty + _ascent), str(l.text), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, tc)
		ty += _lh


## 값 읽기 줄들을 글 폭 max_w(실험 줄은 견본 자리 key_space 를 뺀 폭)에 맞게 " · "·" (" 앞에서 접는다.
## 이어지는 줄은 {first = false}(견본 없이 들여 씀). 한 조각이 그보다 길면 그 조각은 그대로 둠.
func wrap_readout(lines: Array[Dictionary], max_w: float, key_space: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in lines:
		var text := str(l.text)
		var room := max_w - (key_space if int(l.series) >= 0 else 0.0)
		if _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x <= room:
			out.append({text = text, series = l.series, valid = l.valid, first = true})
			continue
		var cur := ""
		var first := true
		for part in _readout_parts(text):
			var cand := cur + part
			if cur != "" and _font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x > room:
				out.append({text = cur, series = l.series, valid = l.valid, first = first})
				first = false
				cur = part.strip_edges(true, false)
			else:
				cur = cand
		out.append({text = cur, series = l.series, valid = l.valid, first = first})
	return out


## 값 읽기 한 줄을 " · "·" (" 앞에서 나눈 조각들(뒤 조각은 나눈 글자로 시작). 괄호 안("(30.1세대 · 틱 2,040)")은 나누지 않음.
static func _readout_parts(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var start := 0
	var depth := 0
	var i := 1
	while i < text.length():
		if depth == 0 and (text.substr(i, 3) == " · " or text.substr(i, 2) == " ("):
			out.append(text.substr(start, i - start))
			start = i
			i += 1
			continue
		if text[i] == "(":
			depth += 1
		elif text[i] == ")":
			depth = maxi(0, depth - 1)
		i += 1
	out.append(text.substr(start))
	return out
