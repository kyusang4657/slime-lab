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
## v0.2 1단계(DESIGN-v0.2 10절): 학습을 켠 세계는 탭(set_mode)으로 타고난(유전체) / 배운(행동 행을 배운 두뇌로) / 차이(배운 − 타고난)를
## 그린다. 배운 두뇌는 출력층 행동 행만이라 W1·기억 출력 행은 타고난·배운 탭에서 같고 차이 탭에서 0 이다. 차이 탭의 색 상한은
## 가장 큰 차이 이상인 1·2·5 × 10^k(diff_scale_for — 배운 양은 ±상한보다 훨씬 작아 같은 눈금이면 보이지 않음). 행동 행 오른쪽에는
## 학습률 유전자 열(L.eta_len > 0 일 때만 — 끄면 예전과 같은 크기·그림).

## cell_at() 이 돌려주는 덩어리 종류
const BLOCK_W1 := "w1"
const BLOCK_W2 := "w2"
const BLOCK_INPUT := "input"
## 학습률 유전자 열(행동 행마다 하나)
const BLOCK_ETA := "eta"
## 탭(set_mode): 타고난 = 유전체 그대로, 배운 = 행동 행을 배운 두뇌로, 차이 = 배운 − 타고난(행동 행만, 나머지 0)
const MODE_INNATE := 0
const MODE_LEARNED := 1
const MODE_DIFF := 2
const MODE_NAMES: Array[String] = ["타고난", "배운", "차이"]
## 학습률 열 머리 글자(η 는 나눔고딕에 없어 웹에서 네모 — 검토 J17 과 같은 까닭으로 낱말)
const ETA_HEADER := "학습률"
## 차이 탭의 입력층 덩어리 가운데 글(배우지 않으니 차이 0)
const DIFF_W1_NOTE := "입력층은 배우지 않음"
## 차이 탭 색 상한: 가장 큰 차이 이상인 첫 '단 × 10^k'(1·2·5 눈금), 한 자리 올림 배수
const NICE_STEPS: Array[float] = [1.0, 2.0, 5.0, 10.0]
const DECADE := 10.0
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
## 마지막으로 그린 색 상한(검사용 — 타고난·배운 탭 = weight_clamp, 차이 탭 = diff_scale())
var last_scale := 0.0

var _L: Dictionary = {}
var _genome := PackedFloat32Array()
## 배운 두뇌(행동 행 n_act × 은닉, s_w2 의 한 개체분 — 비면 학습 끔)와 지금 탭, 차이 탭 색 상한
var _learned := PackedFloat64Array()
var _mode := MODE_INNATE
var _diff_scale := 0.0
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
var _eta_w := 44.0
# 그리는 동안의 색 상한(color_scale)
var _scale := 4.0


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
	_eta_w = UiConfig.num("info.heatmap_eta_width")
	_cw = _cell
	# 스크롤 휠은 바깥 스크롤 창으로 넘기되 풍선 도움말은 받는다
	mouse_filter = Control.MOUSE_FILTER_PASS


## 유전체(개체 하나 분량, 길이 L.genes)를 그린다. 최소 크기는 L 에서 계산한다(size_for). 배운 두뇌는 set_learned 로 따로
## (구조가 바뀐 유전체면 들고 있던 배운 두뇌는 길이가 맞지 않아 쓰지 않음 — has_learned).
func set_genome(L: Dictionary, genome: PackedFloat32Array) -> void:
	_L = L
	_genome = genome
	_cw = cell_width_for(L, max_width)
	custom_minimum_size = size_for(L, max_width)
	_diff_scale = _compute_diff_scale()
	if not has_learned():
		_mode = MODE_INNATE
	queue_redraw()


## (v0.2 1단계) 배운 두뇌 = 행동 행 n_act × 은닉(SIM-API s_w2 의 한 개체분, 같은 배치). 빈 배열 = 학습 끈 세계(타고난 탭만).
## 배운 두뇌가 없으면 탭은 타고난으로 돌아감.
func set_learned(w2: PackedFloat64Array) -> void:
	_learned = w2
	_diff_scale = _compute_diff_scale()
	if not has_learned():
		_mode = MODE_INNATE
	queue_redraw()


## 배운 두뇌를 그릴 수 있나(유전체가 있고 배운 두뇌 길이 = 행동 × 은닉).
func has_learned() -> bool:
	return has_genome() and not _learned.is_empty() and _learned.size() == _n_act() * int(_L.n_hid)


## 탭(MODE_*). 배운 두뇌가 없으면 타고난만. 같은 값이면 다시 그리지 않는다.
func set_mode(m: int) -> void:
	var nm := clampi(m, MODE_INNATE, MODE_DIFF) if has_learned() else MODE_INNATE
	if nm == _mode:
		return
	_mode = nm
	queue_redraw()


func mode() -> int:
	return _mode


## 학습률 유전자 열을 그리나(학습을 켠 유전체 — L.eta_len > 0).
func has_eta() -> bool:
	return has_genome() and _eta_len(_L) > 0 and _genome.size() >= int(_L.eta_offset) + _eta_len(_L)


## 행동 행 q 의 학습률 유전자(없으면 NAN).
func eta_of(q: int) -> float:
	if not has_eta() or q < 0 or q >= _eta_len(_L):
		return NAN
	return float(_genome[int(_L.eta_offset) + q])


## 지금 탭의 칸 값: W1(BLOCK_W1, 은닉 row × 입력 col)·W2(BLOCK_W2, 출력 row × 은닉 col). 차이 탭은 배운 − 타고난(배우지 않는
## W1·기억 출력 행은 0), 배운 탭은 행동 행만 배운 두뇌.
func weight_of(block: String, row: int, col: int) -> float:
	if block == BLOCK_W1:
		return 0.0 if _mode == MODE_DIFF else float(_genome[row * int(_L.n_in) + col])
	var n_hid := int(_L.n_hid)
	var innate := float(_genome[int(_L.w2_offset) + row * n_hid + col])
	if row >= _n_act() or _mode == MODE_INNATE or not has_learned():
		return 0.0 if _mode == MODE_DIFF else innate
	var learned := _learned[row * n_hid + col]
	return learned - innate if _mode == MODE_DIFF else learned


## 지금 탭의 색 상한(타고난·배운 = weight_clamp, 차이 = diff_scale()).
func color_scale() -> float:
	return _diff_scale if _mode == MODE_DIFF else weight_clamp


## 차이 탭의 색 상한(행동 행의 가장 큰 abs(배운 − 타고난) 에서 diff_scale_for).
func diff_scale() -> float:
	return _diff_scale


## 가장 큰 차이 → 그 이상인 첫 1·2·5 × 10^k(아래는 ui.info.heatmap_diff_min). 범례가 둥근 수가 되게.
static func diff_scale_for(max_abs: float) -> float:
	var lo := UiConfig.num("info.heatmap_diff_min")
	var v := maxf(max_abs, lo)
	var p := lo
	while p * DECADE <= v:
		p *= DECADE
	while p > v:
		p /= DECADE
	for k in NICE_STEPS:
		if p * k >= v:
			return p * k
	return p * DECADE


func _compute_diff_scale() -> float:
	var m := 0.0
	if has_learned():
		var n_hid := int(_L.n_hid)
		var w2o := int(_L.w2_offset)
		for q in _n_act():
			for j in n_hid:
				m = maxf(m, absf(_learned[q * n_hid + j] - float(_genome[w2o + q * n_hid + j])))
	return diff_scale_for(m)


func _n_act() -> int:
	return int(_L.get("n_act", SimBrain.BASE_OUTPUTS))


static func _eta_len(L: Dictionary) -> int:
	return int(L.get("eta_len", 0))


## 학습률 열이 차지하는 가로(틈 + ui.info.heatmap_eta_width, 학습 끔이면 0).
static func eta_extra(L: Dictionary) -> float:
	return LABEL_PAD + UiConfig.num("info.heatmap_eta_width") if _eta_len(L) > 0 else 0.0


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


## 구조 L 일 때 열지도 전체 크기. 너비 = 줄 이름 칸 + max(n_in × 칸 너비, n_hid × 칸 너비 + 학습률 열)(cell_width_for, 학습률 열은
## 학습을 켠 구조만 — eta_extra), 높이 = 세운 입력 이름 + w1 행 + 덩어리 틈 + 은닉 번호 줄 + w2 행 + 범례(행 높이 = heatmap_cell).
static func size_for(L: Dictionary, max_w: float = INF) -> Vector2:
	if L.is_empty():
		return Vector2.ZERO
	var cell := UiConfig.num("info.heatmap_cell")
	var cw := cell_width_for(L, max_w)
	var n_in := int(L.n_in)
	var n_hid := int(L.n_hid)
	var n_out := int(L.n_out)
	var wd := UiConfig.num("info.heatmap_label_width") + maxf(float(n_in) * cw, float(n_hid) * cw + eta_extra(L))
	var ht := UiConfig.num("info.heatmap_header_height") + float(n_hid) * cell + UiConfig.num("info.heatmap_block_gap") \
			+ cell + float(n_out) * cell + UiConfig.num("info.heatmap_legend_height")
	return Vector2(wd, ht)


## 칸 너비: heatmap_cell, 단 max_w 안에 들도록 heatmap_cell_min 까지 좁힌다(정수 픽셀). 그래도 넘치면 바깥이 가로 스크롤.
static func cell_width_for(L: Dictionary, max_w: float = INF) -> float:
	var cell := UiConfig.num("info.heatmap_cell")
	if L.is_empty() or is_inf(max_w):
		return cell
	var cols := maxi(1, maxi(int(L.n_in), int(L.n_hid)))
	var room := max_w - UiConfig.num("info.heatmap_label_width")
	var fit := floorf(room / float(cols))
	if _eta_len(L) > 0:
		fit = minf(fit, floorf((room - eta_extra(L)) / float(maxi(1, int(L.n_hid)))))
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


## 빠른 판(설정 값을 이미 읽어 둔 상태에서 그리기용). 상한 = 지금 탭의 color_scale(_draw 가 _scale 에 넣음).
func _wcolor(wv: float) -> Color:
	var t := clampf(absf(wv) / maxf(_scale, 0.0001), 0.0, 1.0)
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
		var wv := weight_of(BLOCK_W1, r1, col)
		var t1 := "입력 「%s」 → 은닉 %d\n가중치 %+.2f" % [input_name(col), r1 + 1, float(_genome[r1 * n_in + col])]
		if _mode == MODE_DIFF:
			t1 += "\n(입력층은 배우지 않음 — 차이 0)"
		return {block = BLOCK_W1, row = r1, col = col, weight = wv, text = t1}
	var r2 := int(floorf((pos.y - _y_w2()) / _cell))
	if pos.y >= _y_w2() and r2 < n_out and col < n_hid:
		return {block = BLOCK_W2, row = r2, col = col, weight = weight_of(BLOCK_W2, r2, col), text = _w2_text(r2, col)}
	# 학습률 열(행동 행 오른쪽)
	var ex := _label_w + float(n_hid) * _cw + LABEL_PAD
	if has_eta() and pos.y >= _y_w2() and r2 < _eta_len(_L) and pos.x >= ex and pos.x < ex + _eta_w:
		var e := eta_of(r2)
		return {block = BLOCK_ETA, row = r2, col = -1, weight = e,
				text = "「%s」 학습률 유전자 %.3f\n유효 학습률 = 이 값 × 생애 단계 배수(learn.stage_mult)" % [output_name(r2), e]}
	return {}


## 아래 덩어리 칸의 풍선 글: 학습을 켠 세계의 행동 행은 타고난·배운·차이를 함께.
func _w2_text(q: int, j: int) -> String:
	var n_hid := int(_L.n_hid)
	var innate := float(_genome[int(_L.w2_offset) + q * n_hid + j])
	var head := "은닉 %d → 「%s」" % [j + 1, output_name(q)]
	if not has_learned():
		return head + "\n가중치 %+.2f" % innate
	if q >= _n_act():
		return head + "\n가중치 %+.2f(기억 출력은 배우지 않음)" % innate
	var learned := _learned[q * n_hid + j]
	return head + "\n타고난 %+.3f · 배운 %+.3f\n차이 %+.4f" % [innate, learned, learned - innate]


func _get_tooltip(at_position: Vector2) -> String:
	var c := cell_at(at_position)
	return str(c.get("text", ""))


func _draw() -> void:
	_font = get_theme_default_font()
	last_legend = PackedStringArray()
	_scale = color_scale()
	last_scale = _scale
	if not has_genome():
		var msg := "두뇌 기록 없음"
		var sz := _font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs)
		draw_string(_font, (size - sz) * 0.5 + Vector2(0, _font.get_ascent(_fs)), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_dim)
		return
	var n_in := int(_L.n_in)
	var n_hid := int(_L.n_hid)
	var n_out := int(_L.n_out)
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
			draw_rect(r, _wcolor(weight_of(BLOCK_W1, j, i)))
		_label_right("은닉 %d" % (j + 1), y1 + float(j) * _cell + (_cell + asc - desc) * 0.5 - _gap * 0.5, _c_dim)
	if n_in > SimBrain.BASE_INPUTS:
		var mx := x0 + float(SimBrain.BASE_INPUTS) * cw - _gap * 0.5
		draw_line(Vector2(mx, y1 - _gap), Vector2(mx, y1 + float(n_hid) * _cell), _c_accent, 1.0)
	if _mode == MODE_DIFF:
		# 차이 탭: 입력층은 배우지 않아 모두 0 — 빈 칸이 '기록 없음'으로 읽히지 않게 가운데에 적는다
		var nw := _font.get_string_size(DIFF_W1_NOTE, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
		draw_string(_font, Vector2(x0 + (float(n_in) * cw - nw) * 0.5, y1 + (float(n_hid) * _cell + asc - desc) * 0.5),
				DIFF_W1_NOTE, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, _c_dim)
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
	var eta_x := x0 + float(n_hid) * cw + LABEL_PAD
	if has_eta():
		draw_string(_font, Vector2(eta_x, yh + (_cell + asc - desc) * 0.5), ETA_HEADER, HORIZONTAL_ALIGNMENT_LEFT, _eta_w, _fs, _c_dim)
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
			draw_rect(r2, _wcolor(weight_of(BLOCK_W2, q, j)))
		var col := _c_accent if hl else (_c_text if q < SimBrain.BASE_OUTPUTS else _c_accent.darkened(MEM_LABEL_DARKEN))
		_label_right(output_name(q), ry + (_cell + asc - desc) * 0.5 - _gap * 0.5, col)
		if has_eta() and q < _eta_len(_L):
			draw_string(_font, Vector2(eta_x, ry + (_cell + asc - desc) * 0.5 - _gap * 0.5), "%.3f" % eta_of(q),
					HORIZONTAL_ALIGNMENT_LEFT, _eta_w, _fs, _c_accent if hl else _c_dim)
	if n_out > SimBrain.BASE_OUTPUTS:
		var my := y2 + float(SimBrain.BASE_OUTPUTS) * _cell - _gap * 0.5
		draw_line(Vector2(x0 - _gap, my), Vector2(x0 + float(n_hid) * cw, my), _c_accent, 1.0)
	# ⑤ 범례: -상한 [음수 … 0 … 양수] +상한
	var yl := _y_legend() + (_legend_h - LEGEND_BAR) * 0.5
	var bw := float(n_hid) * cw - _gap
	for k in LEGEND_STEPS:
		var f0 := float(k) / float(LEGEND_STEPS)
		var wv := (f0 * 2.0 - 1.0 + 1.0 / float(LEGEND_STEPS)) * _scale
		draw_rect(Rect2(x0 + f0 * bw, yl, bw / float(LEGEND_STEPS) + 0.5, LEGEND_BAR), _wcolor(wv))
	draw_line(Vector2(x0 + bw * 0.5, yl - 2.0), Vector2(x0 + bw * 0.5, yl + LEGEND_BAR + 2.0), _c_dim, 1.0)
	var tb := yl + (LEGEND_BAR + asc - desc) * 0.5
	var ends := legend_texts(_scale)
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
