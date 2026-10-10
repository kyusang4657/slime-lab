class_name BrainView
extends Control
## 두뇌 가중치 열지도. 계약: docs/VIEW-API.md "BrainView".
##
## 위 덩어리 = 은닉(행 n_hid) × 입력(열 n_in) = 유전체 w1, 아래 덩어리 = 출력(행 n_out) × 은닉(열 n_hid) = w2.
## 칸의 배치는 SimBrain 유전체 순서 그대로(w1[j * n_in + i], w2[q * n_hid + j]). 기억 뉴런 열·행은 가는 선으로 나눈다.
## 색은 음수(ui.info.heatmap_negative) → 0(창 색 theme.panel) → 양수(heatmap_positive).
## 세기 = (|w| / weight_clamp) ^ heatmap_gamma — 초기 가중치(±1)가 상한(±4)보다 훨씬 작아 감마로 밝게 편다.
## 입력 이름은 열 위에 한글 세로쓰기(글자는 바로 선 채 위→아래)로 쓰고, 칸 위에 마우스를 올리면
## "입력 → 은닉: 가중치" 풍선 도움말. 아래 덩어리에서는 현재 행동 줄을 강조한다(set_highlight_action).
## 칸 높이는 언제나 ui.info.heatmap_cell(줄 이름이 겹치지 않게), 칸 너비는 max_width(정보 창 폭) 안에 들도록
## heatmap_cell_min 까지 좁힌다(설정이 허용하는 큰 두뇌 — 은닉 64·기억 16 — 에서도 창을 밀어내지 않게).
## 칸이 글자보다 좁으면 열 이름은 몇 칸마다 하나씩만 쓴다(풍선 도움말에는 모두 있음).

## cell_at() 이 돌려주는 덩어리 종류
const BLOCK_W1 := "w1"
const BLOCK_W2 := "w2"
const BLOCK_INPUT := "input"
## 범례 그라데이션 조각 수
const LEGEND_STEPS := 48
## 세운 글자와 칸 사이 틈, 줄 이름과 칸 사이 틈(픽셀)
const LABEL_PAD := 5.0
## 현재 행동 줄 표시 막대 두께
const MARK_WIDTH := 3.0
## 범례 막대 높이
const LEGEND_BAR := 8.0
## 세로쓰기 글자 간격 = 글자 크기 + 이 값
const CHAR_STEP_PAD := 1.0
## 기억 출력 줄 이름을 강조색보다 이만큼 어둡게
const MEM_LABEL_DARKEN := 0.15

## 색 세기 정규화 상한(세계 설정 brain.weight_clamp). set_genome 전에 넣는다.
var weight_clamp := 4.0
## 열지도 전체가 들어가야 하는 너비(픽셀, INF = 제한 없음). set_genome 전에 넣는다(InfoPanel 이 창 폭에서 계산).
var max_width := INF
## 마지막으로 그린 범례 양 끝 글(검사용, legend_texts)
var last_legend := PackedStringArray()

var _L: Dictionary = {}
var _genome := PackedFloat32Array()
var _highlight := -1
var _font: Font
# 설정에서 읽은 값
## 칸 너비(열, max_width 에 맞춤)·높이(행, heatmap_cell)
var _cw := 14.0
var _cell := 14.0
var _gap := 1.0
var _gamma := 1.0
var _fs := 11
var _label_w := 64.0
var _header_h := 80.0
var _block_gap := 10.0
var _legend_h := 28.0
var _c_pos := Color.ORANGE
var _c_neg := Color.SKY_BLUE
var _c_mid := Color.BLACK
var _c_grid := Color.DIM_GRAY
var _c_text := Color.WHITE
var _c_dim := Color.GRAY
var _c_accent := Color.AQUAMARINE
var _hl_alpha := 0.16


func _init() -> void:
	_cell = UiConfig.num("info.heatmap_cell")
	_gap = UiConfig.num("info.heatmap_gap")
	_gamma = UiConfig.num("info.heatmap_gamma")
	_fs = UiConfig.integer("info.heatmap_font_size")
	_label_w = UiConfig.num("info.heatmap_label_width")
	_header_h = UiConfig.num("info.heatmap_header_height")
	_block_gap = UiConfig.num("info.heatmap_block_gap")
	_legend_h = UiConfig.num("info.heatmap_legend_height")
	_c_pos = UiConfig.color("info.heatmap_positive")
	_c_neg = UiConfig.color("info.heatmap_negative")
	_c_mid = UiConfig.color("theme.panel")
	_c_grid = UiConfig.color("theme.panel_border")
	_c_text = UiConfig.color("theme.text")
	_c_dim = UiConfig.color("theme.text_dim")
	_c_accent = UiConfig.color("theme.accent")
	_hl_alpha = UiConfig.num("info.heatmap_highlight_alpha")
	_cw = _cell
	# 스크롤 휠은 바깥 스크롤 창으로 넘기되 풍선 도움말은 받는다
	mouse_filter = Control.MOUSE_FILTER_PASS


## 유전체(개체 하나 분량, 길이 L.genes)를 그린다. 최소 크기는 L 에서 계산한다(size_for).
func set_genome(L: Dictionary, genome: PackedFloat32Array) -> void:
	_L = L
	_genome = genome
	_cw = cell_width_for(L, max_width)
	custom_minimum_size = size_for(L, max_width)
	queue_redraw()


## 아래 덩어리에서 강조할 행동 번호(SimBrain.ACT_*, -1 = 없음). 같은 값이면 다시 그리지 않는다.
func set_highlight_action(a: int) -> void:
	if a == _highlight:
		return
	_highlight = a
	queue_redraw()


func highlight_action() -> int:
	return _highlight


func has_genome() -> bool:
	return not _L.is_empty() and _genome.size() >= int(_L.get("trait_offset", 0)) and not _genome.is_empty()


## 구조 L 일 때 열지도 전체 크기. 너비 = 줄 이름 칸 + max(n_in, n_hid) × 칸 너비(cell_width_for),
## 높이 = 세운 입력 이름 + w1 행 + 덩어리 틈 + 은닉 번호 줄 + w2 행 + 범례(행 높이 = heatmap_cell).
static func size_for(L: Dictionary, max_w: float = INF) -> Vector2:
	if L.is_empty():
		return Vector2.ZERO
	var cell := UiConfig.num("info.heatmap_cell")
	var cw := cell_width_for(L, max_w)
	var n_in := int(L.n_in)
	var n_hid := int(L.n_hid)
	var n_out := int(L.n_out)
	var wd := UiConfig.num("info.heatmap_label_width") + float(maxi(n_in, n_hid)) * cw
	var ht := UiConfig.num("info.heatmap_header_height") + float(n_hid) * cell + UiConfig.num("info.heatmap_block_gap") \
			+ cell + float(n_out) * cell + UiConfig.num("info.heatmap_legend_height")
	return Vector2(wd, ht)


## 칸 너비: heatmap_cell, 단 max_w 안에 들도록 heatmap_cell_min 까지 좁힌다(정수 픽셀). 그래도 넘치면 바깥이 가로 스크롤.
static func cell_width_for(L: Dictionary, max_w: float = INF) -> float:
	var cell := UiConfig.num("info.heatmap_cell")
	if L.is_empty() or is_inf(max_w):
		return cell
	var cols := maxi(1, maxi(int(L.n_in), int(L.n_hid)))
	var fit := floorf((max_w - UiConfig.num("info.heatmap_label_width")) / float(cols))
	return clampf(fit, UiConfig.num("info.heatmap_cell_min"), cell)


## 입력 i 의 화면 이름(기본 12개 다음은 기억 입력).
static func input_name(i: int) -> String:
	if i < SimBrain.INPUT_NAMES.size():
		return SimBrain.INPUT_NAMES[i]
	return "기억 %d" % (i - SimBrain.BASE_INPUTS + 1)


## 출력 q 의 화면 이름(기본 8개 행동 다음은 기억 출력).
static func output_name(q: int) -> String:
	if q < SimBrain.ACTION_NAMES.size():
		return SimBrain.ACTION_NAMES[q]
	return "기억 %d" % (q - SimBrain.BASE_OUTPUTS + 1)


## 가중치 색: 음수 색 ← 창 색(0) → 양수 색. 세기는 |w| / clamp 에 감마.
static func weight_color(wv: float, clamp_w: float) -> Color:
	var mid := UiConfig.color("theme.panel")
	var t := clampf(absf(wv) / maxf(clamp_w, 0.0001), 0.0, 1.0)
	t = pow(t, UiConfig.num("info.heatmap_gamma"))
	var end := UiConfig.color("info.heatmap_positive") if wv > 0.0 else UiConfig.color("info.heatmap_negative")
	return mid.lerp(end, t)


## 빠른 판(설정 값을 이미 읽어 둔 상태에서 그리기용).
func _wcolor(wv: float) -> Color:
	var t := clampf(absf(wv) / maxf(weight_clamp, 0.0001), 0.0, 1.0)
	t = pow(t, _gamma)
	return _c_mid.lerp(_c_pos if wv > 0.0 else _c_neg, t)


# ── 배치 ──

func _y_w1() -> float:
	return _header_h


func _y_w2_head() -> float:
	return _header_h + float(int(_L.n_hid)) * _cell + _block_gap


func _y_w2() -> float:
	return _y_w2_head() + _cell


func _y_legend() -> float:
	return _y_w2() + float(int(_L.n_out)) * _cell


## 위치 pos 의 칸. {block, row, col, weight, text} 또는 {}(칸 밖). 풍선 도움말과 검사가 쓴다.
func cell_at(pos: Vector2) -> Dictionary:
	if not has_genome():
		return {}
	var n_in := int(_L.n_in)
	var n_hid := int(_L.n_hid)
	var n_out := int(_L.n_out)
	var col := int(floorf((pos.x - _label_w) / _cw))
	if pos.x < _label_w:
		return {}
	# 세운 입력 이름 위
	if pos.y < _y_w1() and col < n_in:
		return {block = BLOCK_INPUT, row = -1, col = col, weight = 0.0, text = "입력 %d: %s" % [col + 1, input_name(col)]}
	var r1 := int(floorf((pos.y - _y_w1()) / _cell))
	if pos.y >= _y_w1() and r1 < n_hid and col < n_in:
		var wv := float(_genome[r1 * n_in + col])
		return {block = BLOCK_W1, row = r1, col = col, weight = wv,
				text = "입력 「%s」 → 은닉 %d\n가중치 %+.2f" % [input_name(col), r1 + 1, wv]}
	var r2 := int(floorf((pos.y - _y_w2()) / _cell))
	if pos.y >= _y_w2() and r2 < n_out and col < n_hid:
		var wv2 := float(_genome[int(_L.w2_offset) + r2 * n_hid + col])
		return {block = BLOCK_W2, row = r2, col = col, weight = wv2,
				text = "은닉 %d → 「%s」\n가중치 %+.2f" % [col + 1, output_name(r2), wv2]}
	return {}


func _get_tooltip(at_position: Vector2) -> String:
	var c := cell_at(at_position)
	return str(c.get("text", ""))


func _draw() -> void:
	_font = get_theme_default_font()
	last_legend = PackedStringArray()
	if not has_genome():
		var msg := "두뇌 기록 없음"
		var sz := _font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs)
		draw_string(_font, (size - sz) * 0.5 + Vector2(0, _font.get_ascent(_fs)), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_dim)
		return
	var n_in := int(_L.n_in)
	var n_hid := int(_L.n_hid)
	var n_out := int(_L.n_out)
	var w2o := int(_L.w2_offset)
	var x0 := _label_w
	var cw := _cw
	var asc := _font.get_ascent(_fs)
	var desc := _font.get_descent(_fs)
	# 칸이 글자보다 좁으면 열 이름은 몇 칸마다 하나씩(겹치지 않게)
	var glyph_w := _font.get_string_size("가", HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
	var in_stride := maxi(1, ceili(glyph_w / cw))
	var num_w := _font.get_string_size(str(n_hid), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x + _gap
	var num_stride := maxi(1, ceili(num_w / cw))
	# ① 입력 이름: 글자를 바로 세워 위에서 아래로 쌓고(한글 세로쓰기), 마지막 글자가 칸 바로 위에 오게 한다
	var step := float(_fs) + CHAR_STEP_PAD
	for i in n_in:
		if i % in_stride != 0:
			continue
		var cx := x0 + float(i) * cw + (cw - _gap) * 0.5
		var chars := input_name(i).replace(" ", "")
		var col := _c_text if i < SimBrain.BASE_INPUTS else _c_accent
		for k in chars.length():
			var ch := chars.substr(k, 1)
			var chw := _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
			var by := _y_w1() - LABEL_PAD - desc - float(chars.length() - 1 - k) * step
			draw_string(_font, Vector2(cx - chw * 0.5, by), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, col)
	_label_right("입력 →", _y_w1() - LABEL_PAD - desc, _c_dim)
	# ② w1: 은닉 j(행) × 입력 i(열)
	var y1 := _y_w1()
	draw_rect(Rect2(x0 - _gap, y1 - _gap, float(n_in) * cw + _gap, float(n_hid) * _cell + _gap), _c_grid)
	for j in n_hid:
		for i in n_in:
			var r := Rect2(x0 + float(i) * cw, y1 + float(j) * _cell, cw - _gap, _cell - _gap)
			draw_rect(r, _wcolor(float(_genome[j * n_in + i])))
		_label_right("은닉 %d" % (j + 1), y1 + float(j) * _cell + (_cell + asc - desc) * 0.5 - _gap * 0.5, _c_dim)
	if n_in > SimBrain.BASE_INPUTS:
		var mx := x0 + float(SimBrain.BASE_INPUTS) * cw - _gap * 0.5
		draw_line(Vector2(mx, y1 - _gap), Vector2(mx, y1 + float(n_hid) * _cell), _c_accent, 1.0)
	# ③ 은닉 번호 줄
	var yh := _y_w2_head()
	for j in n_hid:
		if j % num_stride != 0:
			continue
		var num := str(j + 1)
		var nw := _font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
		draw_string(_font, Vector2(x0 + float(j) * cw + (cw - _gap - nw) * 0.5, yh + (_cell + asc - desc) * 0.5),
				num, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_dim)
	_label_right("은닉 →", yh + (_cell + asc - desc) * 0.5, _c_dim)
	# ④ w2: 출력 q(행) × 은닉 j(열)
	var y2 := _y_w2()
	draw_rect(Rect2(x0 - _gap, y2 - _gap, float(n_hid) * cw + _gap, float(n_out) * _cell + _gap), _c_grid)
	for q in n_out:
		var ry := y2 + float(q) * _cell
		var hl := q == _highlight
		if hl:
			draw_rect(Rect2(0.0, ry - _gap, x0 - _gap, _cell), Color(_c_accent, _hl_alpha))
			draw_rect(Rect2(0.0, ry - _gap, MARK_WIDTH, _cell), _c_accent)
		for j in n_hid:
			var r2 := Rect2(x0 + float(j) * cw, ry, cw - _gap, _cell - _gap)
			draw_rect(r2, _wcolor(float(_genome[w2o + q * n_hid + j])))
		var col := _c_accent if hl else (_c_text if q < SimBrain.BASE_OUTPUTS else _c_accent.darkened(MEM_LABEL_DARKEN))
		_label_right(output_name(q), ry + (_cell + asc - desc) * 0.5 - _gap * 0.5, col)
	if n_out > SimBrain.BASE_OUTPUTS:
		var my := y2 + float(SimBrain.BASE_OUTPUTS) * _cell - _gap * 0.5
		draw_line(Vector2(x0 - _gap, my), Vector2(x0 + float(n_hid) * cw, my), _c_accent, 1.0)
	# ⑤ 범례: -상한 [음수 … 0 … 양수] +상한
	var yl := _y_legend() + (_legend_h - LEGEND_BAR) * 0.5
	var bw := float(n_hid) * cw - _gap
	for k in LEGEND_STEPS:
		var f0 := float(k) / float(LEGEND_STEPS)
		var wv := (f0 * 2.0 - 1.0 + 1.0 / float(LEGEND_STEPS)) * weight_clamp
		draw_rect(Rect2(x0 + f0 * bw, yl, bw / float(LEGEND_STEPS) + 0.5, LEGEND_BAR), _wcolor(wv))
	draw_line(Vector2(x0 + bw * 0.5, yl - 2.0), Vector2(x0 + bw * 0.5, yl + LEGEND_BAR + 2.0), _c_dim, 1.0)
	var tb := yl + (LEGEND_BAR + asc - desc) * 0.5
	var ends := legend_texts(weight_clamp)
	last_legend = ends
	_label_right(ends[0], tb, _c_dim)
	draw_string(_font, Vector2(x0 + bw + LABEL_PAD, tb), ends[1], HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_dim)


## 범례 양 끝 글 [음수 끝, 양수 끝]: 상한 그대로(정수면 정수, 아니면 필요한 소수 자릿수 — 2.5 → "-2.5"·"+2.5").
## 검토 I44: "%.0f" 라 2.5 가 "±2", 0.5 가 "±0" 으로 색 눈금과 어긋났음. 빼기는 '-'(U+002D) — 수학 빼기 '−'(U+2212)는
## 나눔고딕에 없어 시스템 글꼴이 없는 웹에서 네모로 보였음(검토 J17).
static func legend_texts(clamp_w: float) -> PackedStringArray:
	var v := GraphView.fmt_num(clamp_w, GraphView.decimals_for(clamp_w))
	return PackedStringArray(["-" + v, "+" + v])


## 줄 이름 칸에 오른쪽 맞춤으로 쓴다(baseline = 글자 기준선 y).
func _label_right(text: String, baseline: float, col: Color) -> void:
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
	draw_string(_font, Vector2(_label_w - LABEL_PAD - tw, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, col)
