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
## 감지 = 개체의 감지 반경 s_sense(정보 창·README 와 같은 이름 — 검토 I51: 그래프만 "감각". 설정 절 sense "감각" 은 다른 것)
const TRAIT_NAMES: Array[String] = ["크기", "감지", "에너지", "나이", "세대"]
const TRAIT_UNITS: Array[String] = ["", "칸", "", "틱", "세대"]

const FLOWS_TEXT := "출생·사망"
const FLOWS_TIP := "출생·사망 수를 얇은 선으로 — %d틱당 수로 고쳐 그림(실험마다 기록 간격 record.every 가 달라도 같은 눈금)"
## 출생·사망 단위(그래프 안 견본·값 읽기): "20틱당"
const FLOW_UNIT := "%d틱당"
const X_LABEL := "가로축"
const X_TICK_TEXT := "틱"
const X_GEN_TEXT := "평균 세대"
const EMPTY_LEGEND := "실험 없음"
## 기록이 틱 0 보다 뒤에서 시작하는 실험(스냅숏에서 연 실험)의 머리 알림 — 그 앞의 발견 세로선·시점 표시는 가로축 범위
## 밖이라 그리지 않으므로 그 사실을 그래프에 적는다(검토 J19). 비교면 앞에 이름표("A 기록은 …").
const RECORD_NOTE := "기록은 틱 %s 부터"
const RECORD_NOTE_TIP := "스냅숏에는 세계와 연대기만 담겨, 연 실험은 연 틱부터 다시 기록합니다.\n그 앞의 발견 세로선과 연대기 줄의 시점 표시는 그래프에 나오지 않습니다."
## 사건 종류(SIM-API): 발견
const KIND_DISCOVERY := "discovery"
## 실험 이름에서 견줄 때 달라지는 끝 부분의 시작("기본 · 씨앗 1 · 바꾼 값 2개" 의 " · 씨앗 ") — 범례를 줄일 때 이 뒤는 남김
const SEED_MARK := " · 씨앗 "
const ELLIPSIS := "…"
## 범례 선 견본 길이 = graph.legend_key_px × 이 값(그래프 안 견본보다 길게 — 머리 줄에서 눈에 띄게)
const LEGEND_KEY_SCALE := 1.5


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
	## 세대 축 가장 가까운 줄 찾기: 평균 세대 값을 (값, 줄 번호) 순으로 늘 정렬해 둔 것 — 이분 탐색(O(log n)).
	## 새 줄은 제자리에 끼움(대개 끝 근처라 싸다).
	var gen_sorted := PackedFloat64Array()
	var gen_order := PackedInt32Array()
	## 출생·사망 열은 "flow_ticks 틱당 수"로 고쳐 쌓는다(기록 간격 = 앞 줄과의 틱 차이). 기록 간격(record.every)이
	## 실험마다 달라도 같은 눈금 — 기본 간격(20)과 같으면 기록 줄의 수 그대로.
	var flow_ticks := 20.0
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
	## 첫 줄의 기록 간격(앞 줄이 없음): 그 실험의 record.every, 모르면 flow_ticks
	var _first_dt := 20.0

	func _init(e: Experiment) -> void:
		exp = e
		flow_ticks = maxf(1.0, UiConfig.num("graph.flow_per_ticks"))
		_first_dt = flow_ticks
		if e != null:
			name = e.display_name()
			tag = e.tag
			if e.world != null:
				_first_dt = maxf(1.0, float(e.world.cfg.record.every))
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

	## 가로축 모드에서 이 실험의 (처음, 끝) 가로 값(줄이 없으면 (INF, -INF))
	func x_extent(mode: String) -> Vector2:
		if size() == 0:
			return Vector2(INF, -INF)
		if mode == X_GEN:
			return Vector2(gen_lo, gen_hi)
		return Vector2(tick[0], tick[size() - 1])

	## 시계열 한 줄 덧붙이기(사전은 읽기만 하고 붙잡지 않음).
	func append(row: Dictionary) -> void:
		var k := tick.size()
		var t := float(row.get("tick", 0))
		var pop := float(row.get("population", 0))
		var alive := pop > 0.0
		# 출생·사망 = 앞 줄 이후의 수 → flow_ticks 틱당
		var dt := (t - tick[k - 1]) if k > 0 else _first_dt
		var flow_k := flow_ticks / maxf(1.0, dt)
		tick.append(t)
		for c in COL_KEYS.size():
			var v := float(row.get(COL_KEYS[c], 0.0))
			if not alive and _mean_flag[c] == 1:
				v = NAN
			elif c == C_BIRTHS or c == C_DEATHS:
				v *= flow_k
			cols[c].append(v)
			if not is_nan(v):
				if v < lo[c]:
					lo[c] = v
				if v > hi[c]:
					hi[c] = v
		var g := float(row.get("mean_gen", 0.0)) if alive else (gen_x[k - 1] if k > 0 else 0.0)
		if is_nan(g):
			g = gen_x[k - 1] if k > 0 else 0.0
		gen_x.append(g)
		gen_lo = minf(gen_lo, g)
		gen_hi = maxf(gen_hi, g)
		# (값, 줄 번호) 순 유지: 같은 값 뒤에 끼움(새 줄 번호가 가장 크므로)
		var pos := gen_sorted.bsearch(g, false)
		gen_sorted.insert(pos, g)
		gen_order.insert(pos, k)
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

	## 평균 세대 x 에 가장 가까운 줄(없으면 -1). 모든 줄을 훑어 차이가 가장 작은 줄(같으면 뒤 줄)을 고르는 것과
	## 같은 답을 정렬해 둔 값의 이분 탐색으로(O(log n)) — 마우스가 움직일 때마다 수천 줄을 훑지 않게.
	func nearest_gen_row(x: float) -> int:
		var n := gen_sorted.size()
		if n == 0 or is_nan(x):
			return -1
		var i := gen_sorted.bsearch(x, false)
		if i <= 0:
			# 모두 x 보다 큼: 가장 작은 값의 줄 가운데 번호가 가장 큰 것
			return gen_order[gen_sorted.bsearch(gen_sorted[0], false) - 1]
		var left := gen_order[i - 1]
		if i >= n:
			return left
		var dl := x - gen_sorted[i - 1]
		var gr := gen_sorted[i]
		var right := gen_order[gen_sorted.bsearch(gr, false) - 1]
		var dr := gr - x
		if dl < dr:
			return left
		if dr < dl:
			return right
		return maxi(left, right)

	## 틱 t 에 이 실험의 평균 세대(시점 표시를 세대 축에 놓을 자리). 그 틱의 발견 표시 → 멸종 뒤면 멸종한 세대 →
	## 그 틱의 연대기 사건의 평균 세대(연대기 줄과 같은 값) → 앞뒤 기록 줄 사이를 틱으로 잇기. 첫 줄보다 앞이면 NaN.
	func gen_at_tick(t: float) -> float:
		var n := size()
		if n == 0 or is_nan(t) or t < tick[0]:
			return NAN
		for m in markers:
			if float(m.tick) == t:
				return float(m.gen)
		if extinct_row >= 0 and t >= extinct_tick:
			return extinct_gen
		var w := exp.world if exp != null else null
		if w != null:
			var e := chronicle_at(w.chronicle, t)
			if not e.is_empty():
				var g := float(e.get("mean_gen", NAN))
				if not is_nan(g):
					return g
		if t >= tick[n - 1]:
			return gen_x[n - 1]
		var i := tick.bsearch(t)
		if tick[i] == t:
			return gen_x[i]
		var f := (t - tick[i - 1]) / maxf(1e-9, tick[i] - tick[i - 1])
		return lerpf(gen_x[i - 1], gen_x[i], f)

	## 연대기(틱 순)에서 틱 t 의 첫 사건(없으면 빈 사전) — 이분 탐색
	static func chronicle_at(ch: Array, t: float) -> Dictionary:
		var a := 0
		var b := ch.size()
		while a < b:
			var mid := (a + b) >> 1
			var em: Dictionary = ch[mid]
			if float(em.get("tick", 0)) < t:
				a = mid + 1
			else:
				b = mid
		if a < ch.size():
			var e: Dictionary = ch[a]
			if float(e.get("tick", -1)) == t:
				return e
		return {}


## 마우스 값 상태(가로 값 하나에 대해 한 번만 계산해 세 그래프·값 읽기가 함께 씀)
class HoverState extends RefCounted:
	## 실험마다 마우스 가로 값에 가장 가까운 기록 줄(없으면 -1)
	var rows := PackedInt32Array()
	## 1 = 그 줄이 기준 가로 값 근처(값·점을 보임), 0 = 이 자리에는 그 실험의 기록이 없음
	## (세대 축에서 그 세대에 이르지 못했거나 멸종한 실험 — 먼 줄의 값을 이 자리 값처럼 보이지 않게)
	var valid := PackedByteArray()
	## 세로선·머리 글의 가로 값 = 모든 실험의 줄 가운데 마우스에 가장 가까운 줄의 가로 값, 그 실험 번호
	var anchor_x := NAN
	var anchor := -1


## 머리 범례(코드로 그림): 항목 {text, color, dashed, key, head, mid, tail}를 왼쪽부터 붙여 놓고, 자리가 모자라면
## 이름을 줄인다(최소 폭이 이름에 묶이지 않아 창을 좁혀도 넘치지 않음). 전체 이름은 말풍선.
## 줄일 때는 가운데(예설정 이름)만 "…"로 줄이고 앞(이름표 "A · ")·끝(" · 씨앗 N · 바꾼 값 K개")은 남긴다 — 같은
## 예설정을 씨앗만 바꿔 견줄 때 다른 곳이 끝에 있어서(1280 창에서 둘 다 "A · 시연·검사용(아주 빠른 발…" 로 같아 보이던 것).
## 끝까지 남길 자리도 없으면 그때만 뒤를 자른다.
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
			out.append(_fit_item(k, widths[k]))
		return out

	func _tw(text: String) -> float:
		return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x

	## 항목 k 를 줄여도 남길 폭(앞 + "…" + 끝, 자연 폭보다 크지 않게). 끝이 없으면 0.
	func _keep_w(k: int) -> float:
		var tail := str(items[k].get("tail", ""))
		if tail == "":
			return 0.0
		return minf(_tw(str(items[k].text)), _tw(str(items[k].get("head", "")) + ELLIPSIS + tail))

	## 항목마다 글 폭: 모자라면 먼저 남길 폭(앞·끝)을 주고, 남는 자리를 나머지(자연 폭 − 남길 폭)에 비례해 나눔.
	func _widths() -> PackedFloat64Array:
		var nat := PackedFloat64Array()
		var keep := PackedFloat64Array()
		var fixed := 0.0
		var total := 0.0
		var keep_total := 0.0
		for k in items.size():
			var w := _tw(str(items[k].text))
			nat.append(w)
			total += w
			keep.append(_keep_w(k))
			keep_total += keep[k]
			if bool(items[k].key):
				fixed += _key_w + _key_gap
			if k > 0:
				fixed += _gap
		var room := maxf(0.0, size.x - fixed)
		if total <= room or total <= 0.0:
			return nat
		var out := PackedFloat64Array()
		if keep_total >= room:
			for k in nat.size():
				out.append(floorf(nat[k] * room / total))
			return out
		var rest := room - keep_total
		var flex := total - keep_total
		for k in nat.size():
			out.append(floorf(keep[k] + (nat[k] - keep[k]) * rest / maxf(1e-9, flex)))
		return out

	## 항목 k 를 폭 w 에 맞춤: 가운데만 줄이고 앞·끝은 남김, 그래도 안 되면 뒤를 자름
	func _fit_item(k: int, w: float) -> String:
		var text := str(items[k].text)
		if _tw(text) <= w + 0.5:
			return text
		var head := str(items[k].get("head", ""))
		var mid := str(items[k].get("mid", ""))
		var tail := str(items[k].get("tail", ""))
		if tail != "" and _tw(head + ELLIPSIS + tail) <= w + 0.5:
			var m := mid
			while m.length() > 0:
				m = m.substr(0, m.length() - 1)
				var c := head + m.strip_edges() + ELLIPSIS + tail
				if _tw(c) <= w + 0.5:
					return c
			return head + ELLIPSIS + tail
		return _fit(text, w)

	func _fit(text: String, w: float) -> String:
		if _tw(text) <= w + 0.5:
			return text
		var t := text
		while t.length() > 0:
			t = t.substr(0, t.length() - 1)
			var c := t.strip_edges() + ELLIPSIS
			if _tw(c) <= w:
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
			var t := _fit_item(k, widths[k])
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
## 데이터가 바뀐 횟수(줄 덧붙임·다시 읽기 — 배치·마우스 값 캐시의 기준)
var data_rev := 0
## 마우스 값 상태를 새로 계산한 횟수(검사용: 마우스가 움직여 가로 값이 바뀔 때 한 번 — 그리기마다 다시 하지 않음)
var hover_computes := 0

var _lab: LabMain
var _views: Array[GraphView] = []
var _dirty := false
var _since := 0.0
var _interval := 0.2
var _hover_state: HoverState = null
var _hover_key: Array = []

# ── 노드 ──
var _legend: LegendBar
var _record_note: Label
var _btn_tick: Button
var _btn_gen: Button
var _flows_btn: Button
var _trait_opt: OptionButton

# ── 설정 값 ──
var _fs_small := 13
var _fs_title := 14
var _key_w := 18.0
var _dash := 6.0
var _line_w := 2.0
var _x_target := 5
var _x_snap_div := 4.0
var _x_min_ticks := 100.0
var _x_min_gen := 1.0
var _hover_gap_px := 8.0
var _flow_ticks := 20.0


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
	_x_target = maxi(2, UiConfig.integer("graph.x_ticks"))
	_x_snap_div = maxf(1.0, UiConfig.num("graph.x_snap_div"))
	_x_min_ticks = maxf(1.0, UiConfig.num("graph.x_min_span_ticks"))
	_x_min_gen = maxf(0.01, UiConfig.num("graph.x_min_span_gen"))
	_hover_gap_px = maxf(0.0, UiConfig.num("graph.hover_gap_px"))
	_flow_ticks = maxf(1.0, UiConfig.num("graph.flow_per_ticks"))


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
	var out: Array[Series] = []
	for item in list:
		var x := item as Experiment
		if x == null:
			continue
		var s := Series.new(x)
		for r in x.rows():
			s.append(r)
		out.append(s)
	load_series(out)


## 이미 쌓은 기록(Series)으로 처음부터(load_experiments 가 부름. 검사는 합성 기록을 직접 넣음 — 실험 없이 Series.new(null)).
func load_series(list: Array[Series]) -> void:
	series = list
	epoch += 1
	data_rev += 1
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
	data_rev += 1
	_dirty = true
	if series[index].size() == 1:
		_sync_record_note()


## 시점 표시(연대기 → 그래프). -1 = 지움.
func set_cursor_tick(tick: int) -> void:
	cursor_tick = tick
	redraw_now()


# ════════════════════════════ 검사·조작 API ════════════════════════════

## 그래프 수(3)
func graph_count() -> int:
	return _views.size()


## graph 번째 그래프가 index 번째 실험을 잇는 점 수(검사용, GraphView.series_point_count): 그 그래프의 줄인 선의 점 —
## 줄이 그림 폭보다 적으면 기록 줄 수와 같음. 기록 줄 수 자체는 series[index].size().
func series_points(graph: int, index: int) -> int:
	if graph < 0 or graph >= _views.size() or index < 0 or index >= series.size():
		return 0
	return _views[graph].series_point_count(index)


## 가로축: "tick"(틱) / "gen"(평균 세대). 셋 모두 함께 바뀐다. 다른 값은 무시(지금 축 그대로).
func set_x_axis(mode: String) -> void:
	if mode != X_TICK and mode != X_GEN:
		return
	x_mode = mode
	if _btn_tick != null:
		_btn_tick.set_pressed_no_signal(mode == X_TICK)
		_btn_gen.set_pressed_no_signal(mode == X_GEN)
	redraw_now()


## 출생·사망 얇은 선 켜고 끄기(견본·단위는 개체 수 그래프 안 위쪽 띠 — 제목 줄을 좁히지 않게)
func set_show_flows(on: bool) -> void:
	show_flows = on
	if _flows_btn != null:
		_flows_btn.set_pressed_no_signal(on)
	redraw_now()


## 출생·사망 단위 글("20틱당")
func flow_unit() -> String:
	return FLOW_UNIT % int(_flow_ticks)


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
	else:
		hi = maxf(hi, _cursor_hi())
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


## 시점 표시가 마지막 기록 줄 뒤에 있으면 그 가로 값(없으면 -INF). 사건은 기록 간격 사이에도 나서, 멈춘 채 연대기의
## 최신 줄을 누르면 그 틱이 가로축 끝(마지막 기록 줄을 올린 값)을 넘을 수 있다 — 가로축을 그 자리까지 넓혀 세로선이 보이게
## (검토 I15: 세 그래프 모두 선이 없었음). 그 실험의 세계가 이미 지난 틱일 때만(세계에 없는 틱 99999 는 넓히지 않음).
## 첫 기록 줄 앞(스냅숏에서 연 실험의 앞선 사건)은 넓히지 않는다 — 그 앞은 기록이 없다(머리의 record_note, J19).
func _cursor_hi() -> float:
	var hi := -INF
	if cursor_tick < 0:
		return hi
	for k in series.size():
		var s := series[k]
		if s.size() == 0:
			continue
		var w := s.exp.world if s.exp != null else null
		var now := float(w.tick) if w != null else s.tick[s.size() - 1]
		if float(cursor_tick) > now:
			continue
		var cx := cursor_x(k)
		if not is_nan(cx):
			hi = maxf(hi, cx)
	return hi


## index 번째 실험에서 가로 값 x 에 가장 가까운 기록 줄(없으면 -1). 틱 축은 틱의 이분 탐색, 세대 축은 정렬해 둔
## 평균 세대의 이분 탐색(차이가 가장 작은 줄, 같으면 뒤 줄 — 모두 훑는 것과 같은 답, O(log n)).
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
	return s.nearest_gen_row(x)


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
	return hover_state().rows


## 마우스 값 상태(가로 값·가로축·데이터·마우스 그래프가 그대로면 앞 계산을 그대로 — 세 그래프·값 읽기가 한 번 계산을 나눠 씀)
func hover_state() -> HoverState:
	var tol := hover_view.px_span(_hover_gap_px) if hover_view != null and is_instance_valid(hover_view) else 0.0
	var key: Array = [hover_x, x_mode, epoch, data_rev, tol]
	if _hover_state != null and key == _hover_key:
		return _hover_state
	_hover_key = key
	_hover_state = _compute_hover(tol)
	return _hover_state


## 실험마다 가장 가까운 줄 → 그 가운데 마우스에 가장 가까운 줄이 기준(세로선·머리 글). 다른 실험의 줄은 기준에서
## (gap = 마우스 그래프의 hover_gap_px 픽셀, 또는 그 실험의 기록 간격의 반) 안에 있을 때만 값으로 보인다 —
## 세대 축에서 그 세대에 이르지 못한(멸종·느린) 실험의 먼 줄이 이 세대의 값처럼 보이지 않게.
func _compute_hover(gap: float) -> HoverState:
	hover_computes += 1
	var st := HoverState.new()
	var best_d := INF
	for k in series.size():
		var r := nearest_row(k, hover_x)
		st.rows.append(r)
		st.valid.append(0)
		if r < 0:
			continue
		var d := absf(row_x(k, r) - hover_x)
		if d < best_d:
			best_d = d
			st.anchor = k
			st.anchor_x = row_x(k, r)
	if st.anchor < 0:
		return st
	for k in series.size():
		var r := st.rows[k]
		if r >= 0 and absf(row_x(k, r) - st.anchor_x) <= _row_tolerance(k, gap):
			st.valid[k] = 1
	return st


## index 번째 실험의 줄이 기준 가로 값의 "같은 자리"로 보이는 거리: max(gap, 그 실험의 평균 줄 간격의 반)
func _row_tolerance(index: int, gap: float) -> float:
	var s := series[index]
	var n := s.size()
	var e := s.x_extent(x_mode)
	var half := (e.y - e.x) / float(n - 1) * 0.5 if n > 1 else 0.0
	return maxf(gap, half) + 1e-9


## 마우스 상태의 겉모습(마우스 그래프·줄·보임·기준) — 이것이 그대로면 다시 그릴 것이 없다
func _hover_look() -> Array:
	if is_nan(hover_x):
		return []
	var st := hover_state()
	return [hover_view, st.rows, st.valid, st.anchor_x]


## GraphView 가 부름: 마우스가 그래프 위(가로 값 x). 보이는 것(줄·기준·그래프)이 바뀔 때만 마우스 겹만 다시 그린다
## (선·눈금은 그대로 — 새 데이터의 다시 그리기는 redraw_hz 로 따로). 세로로만 움직이거나 같은 줄 안이면 그리지 않음.
func set_hover(v: GraphView, x: float) -> void:
	var before := _hover_look()
	hover_view = v
	hover_x = x
	if _hover_look() == before:
		return
	for g in _views:
		g.queue_hover_redraw()


func clear_hover() -> void:
	if is_nan(hover_x) and hover_view == null:
		return
	hover_x = NAN
	hover_view = null
	for g in _views:
		g.queue_hover_redraw()


## index 번째 실험에서 시점 표시(cursor_tick)의 지금 가로 값(NaN = 없음 또는 그 실험의 기록 앞).
## 틱 축 = 그 틱, 세대 축 = 그 실험이 그 틱에 있던 평균 세대(Series.gen_at_tick — 발견 표시·연대기 줄과 같은 값).
func cursor_x(index: int) -> float:
	if cursor_tick < 0 or index < 0 or index >= series.size() or series[index].size() == 0:
		return NAN
	if x_mode == X_TICK:
		return float(cursor_tick)
	return series[index].gen_at_tick(float(cursor_tick))


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
	_legend = LegendBar.new(_fs_small, _key_w * LEGEND_KEY_SCALE, UiConfig.num("graph.key_gap"), UiConfig.num("graph.legend_gap"), _line_w, _dash)
	_legend.name = "Legend"
	head.add_child(_legend)
	_record_note = Label.new()
	_record_note.name = "RecordNote"
	_record_note.theme_type_variation = UiTheme.DIM
	_record_note.add_theme_font_size_override("font_size", _fs_small)
	_record_note.tooltip_text = RECORD_NOTE_TIP
	_record_note.mouse_filter = Control.MOUSE_FILTER_PASS
	_record_note.visible = false
	head.add_child(_record_note)
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
		# 제목은 줄이지 않는다(최소 폭 = 글 폭). 제목 줄에는 제목 + 조작 하나만 — 출생·사망 견본은 그래프 안 위쪽 띠
		# (1280 창에서 견본이 제목 "개체 수" 를 0 폭으로 밀어내던 것).
		var title := Label.new()
		title.name = "Title"
		title.text = GRAPH_TITLES[g]
		title.theme_type_variation = UiTheme.VALUE
		title.add_theme_font_size_override("font_size", _fs_title)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_child(title)
		match g:
			GRAPH_POP:
				_flows_btn = _toggle(FLOWS_TEXT, null)
				_flows_btn.name = "Flows"
				_flows_btn.tooltip_text = FLOWS_TIP % int(_flow_ticks)
				_flows_btn.toggled.connect(set_show_flows)
				title_row.add_child(_flows_btn)
			GRAPH_TRAIT:
				_trait_opt = OptionButton.new()
				_trait_opt.name = "Trait"
				for n in TRAIT_NAMES:
					_trait_opt.add_item(n)
				_trait_opt.select(trait_index)
				# 키보드로 닿음(Tab·Enter — 스페이스는 LabMain 이 먼저 멈춤으로 씀, J16)
				ParamPanel.keyboard_focus(_trait_opt)
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


## 마우스로 누르면 이 패널 단추·고르기 상자의 키보드 초점을 푼다(Tab 으로 고른 뒤 지도를 누르고 Enter 를 쳐도 눌리지 않게 —
## ParamPanel.release_button_focus, J16).
func _input(event: InputEvent) -> void:
	ParamPanel.release_button_focus(self, event)


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
	ParamPanel.keyboard_focus(b)
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


## 머리 범례: 비교면 실험마다 선 견본(A 실선·B 점선) + display_name(), 혼자면 실험 이름만(선이 하나라 견본 없음)
func _rebuild_legend() -> void:
	_sync_record_note()
	if _legend == null:
		return
	var list: Array[Dictionary] = []
	if series.is_empty():
		list.append({text = EMPTY_LEGEND, key = false, color = Color.WHITE, dashed = false})
	elif series.size() == 1:
		list.append(_legend_item(series[0], false, Color.WHITE, false))
	else:
		for k in series.size():
			list.append(_legend_item(series[k], true, series_color(k), series_dashed(k)))
	_legend.set_items(list)


func _legend_item(s: Series, key: bool, c: Color, dashed: bool) -> Dictionary:
	var parts := split_name(s.name, s.tag)
	return {text = s.name, key = key, color = c, dashed = dashed, head = parts[0], mid = parts[1], tail = parts[2]}


## 실험 이름 → [앞(이름표 "A · "), 가운데(예설정 이름 — 줄일 곳), 끝(" · 씨앗 N …" — 견줄 때 다른 곳)].
## " · 씨앗 " 이 없으면 끝은 "" (줄일 때 뒤를 자름).
static func split_name(text: String, tag: String) -> PackedStringArray:
	var head := ""
	var rest := text
	var tp := tag + " · "
	if tag != "" and text.begins_with(tp):
		head = tp
		rest = text.substr(tp.length())
	var i := rest.find(SEED_MARK)
	if i < 0:
		return PackedStringArray([head, rest, ""])
	return PackedStringArray([head, rest.substr(0, i), rest.substr(i)])


## 머리 알림 글: 첫 기록 줄이 틱 0 보다 뒤인 실험마다 "기록은 틱 N 부터"(비교면 "A 기록은 …", " · " 로 이음). 없으면 "".
func record_note() -> String:
	var parts := PackedStringArray()
	for k in series.size():
		var s := series[k]
		if s.size() == 0 or s.tick[0] <= 0.0:
			continue
		var t := RECORD_NOTE % GraphView.fmt_num(s.tick[0], 0)
		if is_compare():
			t = "%s %s" % [s.tag if s.tag != "" else str(k + 1), t]
		parts.append(t)
	return " · ".join(parts)


func _sync_record_note() -> void:
	if _record_note == null:
		return
	var t := record_note()
	_record_note.text = t
	_record_note.visible = t != ""


## 머리 알림이 보이면 그 글, 아니면 ""(검사용)
func record_note_shown() -> String:
	return _record_note.text if _record_note != null and _record_note.visible else ""


## 범례에 보이는 이름들(검사용)
func legend_texts() -> PackedStringArray:
	var out := PackedStringArray()
	if _legend != null:
		for it in _legend.items:
			out.append(str(it.text))
	return out


## 범례 항목(검사용): {text, color, dashed, key, head, mid, tail}
func legend_items() -> Array[Dictionary]:
	return _legend.items if _legend != null else []


## 범례에 지금 실제로 보이는 글(줄였으면 "…" 포함, 검사용)
func legend_shown() -> PackedStringArray:
	return _legend.shown_texts() if _legend != null else PackedStringArray()
