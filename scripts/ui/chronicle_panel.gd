class_name ChroniclePanel
extends VBoxContainer
## 연대기 — 실험실 아래 자리 오른쪽. 계약: docs/VIEW-API.md "ChroniclePanel".
##
## 각 실험의 연대기(world.chronicle: 발견·저장고·첫 밭·밭 잃음·세대·멸종)를 최신이 위로 보여 준다.
## experiments_changed 를 받으면 각 세계의 chronicle 을 처음부터 다시 읽고(줄은 우리 사본 — 연대기 사전은 고치지 않음),
## 그 뒤로는 events_tagged 로 온 새 사건만 덧붙인다(매 프레임 연대기를 훑지 않음). 비교 모드면 줄 앞에 A/B.
## 줄 = 종류 색 띠 · 틱 · 평균 세대 · 문장(최대 ui.chronicle.text_max_lines 줄, 넘치면 말줄임 — 풍선 도움말에 전체).
## 거르기: 전체·발견·건물(저장고·첫 밭)·밭 잃음·세대·멸종. 최대 ui.chronicle.max_items 줄, 넘치면 맨 아래 "더 오래된 K개".
## 줄을 누르면 lab.request_cursor(틱)(그래프 시점 표시), 행위자(actor ≥ 0)가 있으면 lab.select_slime(actor, index).
## 목록은 Control 하나가 보이는 줄만 그린다(300줄이어도 노드 수가 그대로, 새 줄만 문장을 접음).

## 줄을 눌렀을 때(틱, 행위자 id 또는 -1, 실험 번호). LabMain 이 없어도 검사·다른 요소가 받을 수 있게
signal row_activated(tick: int, actor: int, index: int)

## 거르기 묶음(= 거르기 OptionButton 의 id·순서)
const FILTER_ALL := 0
const FILTER_DISCOVERY := 1
const FILTER_BUILD := 2
const FILTER_FARM_LOST := 3
const FILTER_MILESTONE := 4
const FILTER_EXTINCTION := 5
const FILTER_NAMES: Array[String] = ["전체", "발견", "건물", "밭 잃음", "세대", "멸종"]
const FILTER_TIPS: Array[String] = ["모든 사건", "문명 단계 발견(채집·저장·농사)", "저장고 건설·첫 밭",
		"버려진 밭이 풀밭으로 돌아감", "평균 세대 이정표(record.generation_milestone 마다)", "멸종"]
## 사건 종류(docs/SIM-API.md 의 kind) → 거르기 묶음. 모르는 종류는 "전체" 에만
const GROUP_OF := {"discovery": FILTER_DISCOVERY, "store_built": FILTER_BUILD, "first_farm": FILTER_BUILD,
		"farm_lost": FILTER_FARM_LOST, "milestone": FILTER_MILESTONE, "extinction": FILTER_EXTINCTION}
## 묶음 → ui.chronicle.colors 의 키(띠 색. 0 = 모르는 종류)
const COLOR_KEYS: Array[String] = ["other", "discovery", "building", "farm_lost", "milestone", "extinction"]
const TITLE := "연대기"
## 머리 줄 설명(열 이름 — 줄 안의 세대는 "평균" 을 줄여 씀). 누르면 하는 일은 줄의 풍선 도움말에
const HINT := "틱 · 평균 세대 · 사건 — 최신이 위"
const EMPTY_TEXT := "아직 기록된 사건이 없습니다"
const EMPTY_FILTERED := "이 종류의 사건이 아직 없습니다"
## 줄 머리 글자("틱 N · 평균 G세대 · 문장"). 평균 세대는 저장된 그대로(사건의 mean_gen 은 0.01 단위 = chronicle.csv) —
## 0.1 단위로 한 번 더 반올림하면 문장 속 "(평균 X세대)"(반올림 전 값을 0.1 단위로)와 어긋났음(4.35 → "4.4세대" 옆에 "평균 4.3세대")
const TICK_WORD := "틱"
const GEN_FORMAT := "평균 %.2f세대"
## 목록 안의 평균 세대(폭을 아끼려고 "평균" 을 뺌 — 머리 줄·풍선 도움말·item_text 에는 있음)
const GEN_SHORT := "%.2f세대"
const SEP := " · "
## 줄바꿈 자리를 고를 때 빈칸을 얼마나 붙여 둘지(낮은 것부터 끊음, wrap_text): 보통 빈칸 · 괄호 안 · 숫자로 시작하는 낱말 앞
const GLUE_NONE := 0
const GLUE_PAREN := 1
const GLUE_NUMBER := 2

## 화면에 두는 최대 줄 수(ui.chronicle.max_items, 검사에서 줄여 볼 수 있음 — 바꾸면 refresh())
var max_items := 300

var _lab: LabMain
# 실험 목록(비교 모드면 [A, B])과 실험마다의 줄(오래된 것 → 새것), 묶음별 줄(같은 사전을 가리킴)
var _exps: Array = []
var _rows: Array = []
var _by_group: Array = []
# 실험마다 줄로 읽은 연대기 항목 수(다시 읽기·덧붙이기). 다시 읽을 때 아직 비우지 않은 사건은 연대기 끝에 이미 있으므로,
# 다음 events_tagged 목록 가운데 연대기 위치가 이보다 앞인 것은 건너뜀(_already_read — 틱이 아니라 위치로 셈)
var _read_n: Array[int] = []
var _filter := FILTER_ALL
var _visible: Array = []
var _older := 0
var _list: RowList
var _bar: VScrollBar
var _filter_btn: OptionButton
var _hint: Label


func _init() -> void:
	max_items = maxi(1, UiConfig.integer("chronicle.max_items"))
	# 실험실 뿌리의 공용 테마와 같은 것(혼자 띄워 찍거나 검사할 때도 같은 모양)
	theme = UiTheme.build()
	custom_minimum_size.x = UiConfig.num("chronicle.width")
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", UiConfig.integer("theme.separation"))
	_build()


func _build() -> void:
	var head := HBoxContainer.new()
	head.name = "Head"
	add_child(head)
	var title := Label.new()
	title.text = TITLE
	title.theme_type_variation = UiTheme.VALUE
	head.add_child(title)
	_hint = Label.new()
	_hint.text = HINT
	_hint.theme_type_variation = UiTheme.DIM
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.clip_text = true
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_hint)
	_filter_btn = OptionButton.new()
	_filter_btn.name = "Filter"
	# 스페이스(멈춤)·숫자 키(속도)를 가로채지 않게
	_filter_btn.focus_mode = Control.FOCUS_NONE
	_filter_btn.tooltip_text = "사건 종류 거르기(괄호 = 사건 수)"
	var px := UiConfig.integer("chronicle.swatch_px")
	for g in FILTER_NAMES.size():
		if g == FILTER_ALL:
			_filter_btn.add_item(FILTER_NAMES[g], g)
		else:
			_filter_btn.add_icon_item(_swatch(group_color(g), px), FILTER_NAMES[g], g)
		_filter_btn.set_item_tooltip(g, FILTER_TIPS[g])
	_filter_btn.item_selected.connect(func(i: int) -> void: set_filter(_filter_btn.get_item_id(i)))
	head.add_child(_filter_btn)

	var card := PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = UiTheme.CARD
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	card.add_child(row)
	_list = RowList.new()
	_list.name = "Rows"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.row_clicked.connect(activate_item)
	_list.tip_of = item_tooltip
	row.add_child(_list)
	# 스크롤 막대는 늘 자리를 차지한다(나타났다 사라지며 글 폭이 바뀌어 줄이 다시 접히지 않게) — 필요 없으면 투명
	_bar = VScrollBar.new()
	_bar.name = "Scroll"
	_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bar.focus_mode = Control.FOCUS_NONE
	row.add_child(_bar)
	_list.bar = _bar
	_bar.value_changed.connect(func(_v: float) -> void: _list.queue_redraw())
	_sync_filter_labels()
	_list.set_rows([], 0, false, [], EMPTY_TEXT, false)


# ════════════════════════════ 연결 ════════════════════════════

## 실험실에 붙인다: experiments_changed → 처음부터 다시 읽음, events_tagged → 새 사건 덧붙임. 지금 실험도 바로 읽는다.
func bind_lab(lab: LabMain) -> void:
	if _lab != null:
		if _lab.experiments_changed.is_connected(set_experiments):
			_lab.experiments_changed.disconnect(set_experiments)
		if _lab.events_tagged.is_connected(append_events):
			_lab.events_tagged.disconnect(append_events)
	_lab = lab
	if lab == null:
		return
	lab.experiments_changed.connect(set_experiments)
	lab.events_tagged.connect(append_events)
	set_experiments(lab.experiments)


## 실험 목록으로 처음부터 다시 채운다(각 world.chronicle 을 읽어 우리 사본으로). 비교 모드(2개 이상)면 줄 앞에 A/B.
func set_experiments(list: Array) -> void:
	_exps = list.duplicate()
	_rows.clear()
	_by_group.clear()
	_read_n.clear()
	for k in _exps.size():
		var all: Array = []
		var groups: Array = [all]
		for g in range(1, FILTER_NAMES.size()):
			groups.append([])
		_rows.append(all)
		_by_group.append(groups)
		var w := _world_of(k)
		_read_n.append(w.chronicle.size() if w != null else 0)
		if w != null:
			for e: Dictionary in w.chronicle:
				_add_row(k, e)
	_list.selected = {}
	_refresh(false)


## index 번째 실험의 새 사건(LabMain.events_tagged 의 사본 목록)을 덧붙인다.
## 다시 읽을 때 이미 연대기에서 읽은 사건(그때 아직 비우지 않았던 것)은 건너뛴다 — _already_read.
func append_events(index: int, list: Array) -> void:
	if index < 0 or index >= _rows.size() or list.is_empty():
		return
	var skip := _already_read(index, list)
	if skip >= list.size():
		return
	for i in range(skip, list.size()):
		_add_row(index, list[i] as Dictionary)
	_refresh(true)


## list 의 앞에서 몇 개가 이미 줄로 읽은 연대기 항목인지(그만큼 건너뜀). LabMain 은 drain_events 바로 뒤에 보내므로
## list = 연대기의 끝 list.size() 개이고, 그 가운데 연대기 위치가 _read_n 보다 앞인 것이 다시 읽을 때 이미 넣은 것.
## 틱으로 거르지 않는다: 발견·저장고·첫 밭·밭 잃음은 한 틱을 진행하는 도중에 진행 전 틱 번호를 달고 나와서,
## "다시 읽은 틱 이하 = 이미 읽음" 으로 거르면 다시 읽은 바로 뒤 틱의 새 사건을 잃었다(스냅숏 열기·비교 끝내기 뒤).
## 연대기의 끝과 다른 목록(세계 없음, 검사가 꾸며 넣은 사건)은 모두 새 사건.
func _already_read(index: int, list: Array) -> int:
	var w := _world_of(index)
	if w == null:
		return 0
	var n := w.chronicle.size()
	var first := n - list.size()
	var skip := 0
	if first >= 0 and _read_n[index] > first and _is_tail(w.chronicle, first, list):
		skip = mini(_read_n[index] - first, list.size())
	_read_n[index] = maxi(_read_n[index], n)
	return skip


## list 가 연대기 ch 의 first 번째부터 끝까지와 같은 사건인지(틱·종류·문장 — 받는 쪽 사본이라 사전 자체는 다름)
static func _is_tail(ch: Array, first: int, list: Array) -> bool:
	for i in list.size():
		var a: Dictionary = ch[first + i]
		var b: Dictionary = list[i]
		if int(a.get("tick", -1)) != int(b.get("tick", -1)) or str(a.get("kind", "")) != str(b.get("kind", "")) \
				or str(a.get("text", "")) != str(b.get("text", "")):
			return false
	return true


## k 번째 실험의 세계(없으면 null)
func _world_of(k: int) -> SimWorld:
	var x: Experiment = _exps[k] as Experiment if k >= 0 and k < _exps.size() else null
	return x.world if x != null else null


## 사건 사전 → 줄(우리 사본: 틱·종류·행위자·문장·평균 세대·실험 번호·묶음)
func _add_row(k: int, e: Dictionary) -> void:
	var kind := str(e.get("kind", ""))
	var g := int(GROUP_OF.get(kind, FILTER_ALL))
	var r := {
		tick = int(e.get("tick", 0)), kind = kind, actor = int(e.get("actor", -1)), text = str(e.get("text", "")),
		gen = float(e.get("mean_gen", 0.0)), index = k, group = g,
	}
	(_rows[k] as Array).append(r)
	if g != FILTER_ALL:
		(_by_group[k][g] as Array).append(r)


# ════════════════════════════ 거르기·목록 ════════════════════════════

## 거르기 묶음(FILTER_*)을 고른다(거르기 단추와 같음).
func set_filter(id: int) -> void:
	id = clampi(id, 0, FILTER_NAMES.size() - 1)
	if _filter_btn.get_selected_id() != id:
		_filter_btn.select(_filter_btn.get_item_index(id))
	if id == _filter:
		return
	_filter = id
	# 고른 줄은 그대로(그래프 시점 표시와 맞게) — 거른 목록에 없으면 강조만 안 보임
	_refresh(false)


func filter() -> int:
	return _filter


## 보이는 줄을 다시 고른다: 실험마다 (묶음의) 줄 끝에서부터 틱이 큰 것을 골라 max_items 개까지(최신이 위).
## 같은 틱이면 뒤 실험(B)이 위 — 한 틱 안에서 A 다음 B 를 진행하므로 B 의 사건이 더 나중. O(max_items × 실험 수).
## keep_scroll: 새 줄이 위에 붙어도 읽던 줄이 제자리에 있게(맨 위를 보고 있었으면 새 줄이 보임).
func refresh(keep_scroll: bool = false) -> void:
	_refresh(keep_scroll)


func _refresh(keep_scroll: bool) -> void:
	var lists: Array = []
	var ptr: Array[int] = []
	var total := 0
	for k in _by_group.size():
		var a: Array = _by_group[k][_filter]
		lists.append(a)
		ptr.append(a.size() - 1)
		total += a.size()
	_visible = []
	while _visible.size() < max_items:
		var best := -1
		for k in lists.size():
			if ptr[k] < 0:
				continue
			if best < 0 or int(lists[k][ptr[k]].tick) >= int(lists[best][ptr[best]].tick):
				best = k
		if best < 0:
			break
		_visible.append(lists[best][ptr[best]])
		ptr[best] -= 1
	_older = total - _visible.size()
	var tags: Array[String] = []
	if _exps.size() > 1:
		for k in _exps.size():
			tags.append(_tag_of(k))
	_list.set_rows(_visible, _older, _exps.size() > 1, tags, EMPTY_TEXT if _filter == FILTER_ALL else EMPTY_FILTERED, keep_scroll)
	_sync_filter_labels()


## 거르기 항목에 사건 수: "발견 (3)"(모든 실험 합)
func _sync_filter_labels() -> void:
	for g in FILTER_NAMES.size():
		var n := 0
		for k in _by_group.size():
			n += (_by_group[k][g] as Array).size()
		var label := "%s (%s)" % [FILTER_NAMES[g], commas(n)]
		var i := _filter_btn.get_item_index(g)
		if _filter_btn.get_item_text(i) != label:
			_filter_btn.set_item_text(i, label)


## 줄을 누른 것과 같다: 그 줄을 고르고 그래프에 시점 표시를 요청, 행위자가 있으면 그 개체를 고른다.
func activate_item(i: int) -> void:
	if i < 0 or i >= _visible.size():
		return
	var r: Dictionary = _visible[i]
	_list.selected = r
	_list.queue_redraw()
	var tick := int(r.tick)
	var actor := int(r.actor)
	var index := int(r.index)
	row_activated.emit(tick, actor, index)
	if _lab == null:
		return
	_lab.request_cursor(tick)
	if actor >= 0:
		_select_actor(actor, index)


## lab.select_slime(actor, index). 3단계 LabMain 의 select_slime(id) 처럼 실험 번호를 받지 않으면
## A(0) 의 개체만 고른다(B 의 id 를 A 세계에서 고르면 다른 개체가 됨).
func _select_actor(actor: int, index: int) -> void:
	if _lab.get_method_argument_count("select_slime") >= 2:
		_lab.call("select_slime", actor, index)
	elif index == 0:
		_lab.call("select_slime", actor)


# ════════════════════════════ 검사·캡처용 ════════════════════════════

## 지금 보이는 줄 수("더 오래된 K개" 표시 줄은 빼고)
func item_count() -> int:
	return _visible.size()


## i 번째(0 = 맨 위 = 최신) 줄의 글: "틱 N · 평균 G세대 · 문장"(비교 모드면 앞에 "A · ")
func item_text(i: int) -> String:
	if i < 0 or i >= _visible.size():
		return ""
	return _line_text(_visible[i])


## i 번째 줄의 사본 {tick, kind, actor, text, gen, index, group}
func item(i: int) -> Dictionary:
	if i < 0 or i >= _visible.size():
		return {}
	var r: Dictionary = _visible[i]
	return {tick = r.tick, kind = r.kind, actor = r.actor, text = r.text, gen = r.gen, index = r.index, group = r.group}


## 보이지 않는(max_items 를 넘어 잘린) 더 오래된 줄 수(지금 거르기 기준)
func older_count() -> int:
	return _older


## 거르기 묶음의 사건 수(모든 실험 합)
func group_count(id: int) -> int:
	var n := 0
	for k in _by_group.size():
		n += (_by_group[k][id] as Array).size()
	return n


## i 번째 줄의 풍선 도움말(실험 이름·틱·평균 세대·문장 전체·누르면 하는 일)
func item_tooltip(i: int) -> String:
	if i < 0 or i >= _visible.size():
		return ""
	var r: Dictionary = _visible[i]
	var lines: Array[String] = []
	var k := int(r.index)
	if _exps.size() > 1 and k < _exps.size() and _exps[k] != null:
		lines.append((_exps[k] as Experiment).display_name())
	lines.append("%s %s%s%s" % [TICK_WORD, commas(int(r.tick)), SEP, GEN_FORMAT % float(r.gen)])
	lines.append(str(r.text))
	var act := "누르면 그래프에 틱 %s 표시" % commas(int(r.tick))
	if int(r.actor) >= 0:
		act += " · #%d 고르기" % int(r.actor)
	lines.append(act)
	return "\n".join(lines)


## i 번째 줄의 화면 사각형(전역 좌표, 지금 스크롤 기준). 목록 밖이면 빈 사각형
func item_rect(i: int) -> Rect2:
	return _list.row_rect_global(i)


## i 번째 줄이 다 보이게 스크롤한다(이미 보이면 그대로).
func scroll_to_item(i: int) -> void:
	_list.scroll_to(i)


## 목록 그리기 통계(검사용): {drawn: 마지막으로 그린 줄 수, shaped: 지금까지 문장을 접은 횟수, height: 전체 높이}
func list_stats() -> Dictionary:
	return {drawn = _list.drawn_rows, shaped = _list.shaped_rows, height = _list.total_height()}


## 목록 Control(검사가 크기·스크롤을 보려고)
func list_control() -> Control:
	return _list


func _line_text(r: Dictionary) -> String:
	var s := "%s %s%s%s%s%s" % [TICK_WORD, commas(int(r.tick)), SEP, GEN_FORMAT % float(r.gen), SEP, str(r.text)]
	if _exps.size() > 1:
		s = _tag_of(int(r.index)) + SEP + s
	return s


## k 번째 실험의 이름표("A"/"B" — 실험에 없으면 순서대로)
func _tag_of(k: int) -> String:
	var x: Experiment = _exps[k] as Experiment if k >= 0 and k < _exps.size() else null
	if x != null and x.tag != "":
		return x.tag
	return Experiment.TAGS[clampi(k, 0, Experiment.TAGS.size() - 1)]


# ════════════════════════════ 도움 ════════════════════════════

## 묶음의 띠 색(ui.chronicle.colors)
static func group_color(g: int) -> Color:
	return UiConfig.color("chronicle.colors." + COLOR_KEYS[clampi(g, 0, COLOR_KEYS.size() - 1)])


## 문장을 폭 안에서 낱말(빈칸) 단위로 접는다 — 한글 음절 사이에서 끊지 않고(우리말 줄바꿈), 한 낱말이 폭보다 길 때만
## 글자 단위로 자른다. 다음 낱말이 넘치면 이 줄의 빈칸 가운데 덜 붙여 둔(_glue_levels 가 낮은) 마지막 자리에서 끊는다:
## 괄호 안("(30, 0)"·"(남은 밭 55)")과 숫자로 시작하는 낱말 앞("밭 1곳이")은 다른 자리가 없을 때만(묶음이 폭보다 넓을 때 —
## 그때도 숫자는 앞 낱말과 함께: "(남은" / "밭 55)"). max_lines 를 넘으면 마지막 줄 끝을 말줄임표로.
static func wrap_text(font: Font, text: String, fs: int, width: float, max_lines: int, ellipsis: String = "…") -> PackedStringArray:
	var lines := PackedStringArray()
	var words := text.split(" ", false)
	var glue := _glue_levels(words)
	var s := 0
	while s < words.size():
		# 낱말 하나가 폭보다 길면 글자 단위로 자르고 남은 조각이 이 줄의 첫 낱말
		while words[s].length() > 1 and _text_w(font, words[s], fs) > width:
			var k := _fit_chars(font, words[s], fs, width, "")
			lines.append(words[s].substr(0, k))
			words[s] = words[s].substr(k)
		# s 부터 폭 안에 드는 마지막 낱말 e
		var line := words[s]
		var e := s
		while e + 1 < words.size():
			var cand := line + " " + words[e + 1]
			if _text_w(font, cand, fs) > width:
				break
			line = cand
			e += 1
		if e + 1 < words.size():
			# 끊을 자리(낱말 j 뒤): 가장 덜 붙여 둔 단계 가운데 가장 뒤
			var cut := e
			for j in range(e - 1, s - 1, -1):
				if glue[cut] == GLUE_NONE:
					break
				if glue[j] < glue[cut]:
					cut = j
			if cut < e:
				line = " ".join(words.slice(s, cut + 1))
				e = cut
		lines.append(line)
		s = e + 1
	if lines.size() > maxi(1, max_lines):
		var keep := maxi(1, max_lines)
		var rest := " ".join(lines.slice(keep - 1))
		lines = lines.slice(0, keep - 1)
		lines.append(ellipsize(font, rest, fs, width, ellipsis))
	return lines


## 낱말 i 뒤 빈칸을 얼마나 붙여 둘지(마지막 낱말은 GLUE_NONE): 다음 낱말이 숫자로 시작하면 GLUE_NUMBER(수를 앞 낱말에서
## 떼지 않음 — "밭 55"·"시도 121회"), 괄호 안이면 GLUE_PAREN, 아니면 GLUE_NONE. 시뮬레이션 문장은 그대로 두고 접는 자리만 고름.
static func _glue_levels(words: PackedStringArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(words.size())
	var depth := 0
	for i in words.size():
		depth = maxi(0, depth + words[i].count("(") - words[i].count(")"))
		if i + 1 < words.size() and words[i + 1].left(1).is_valid_int():
			out[i] = GLUE_NUMBER
		elif depth > 0 and i + 1 < words.size():
			out[i] = GLUE_PAREN
		else:
			out[i] = GLUE_NONE
	return out


## 폭을 넘으면 끝을 잘라 말줄임표를 붙인다.
static func ellipsize(font: Font, text: String, fs: int, width: float, ellipsis: String = "…") -> String:
	if _text_w(font, text, fs) <= width:
		return text
	var k := _fit_chars(font, text, fs, width, ellipsis)
	return text.substr(0, k).strip_edges(false, true) + ellipsis


## 앞 k 글자(+ 꼬리)가 폭 안에 드는 가장 큰 k(적어도 1)
static func _fit_chars(font: Font, text: String, fs: int, width: float, tail: String) -> int:
	var lo := 1
	var hi := text.length()
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if _text_w(font, text.substr(0, mid) + tail, fs) <= width:
			lo = mid
		else:
			hi = mid - 1
	return lo


static func _text_w(font: Font, text: String, fs: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## 세 자리마다 쉼표
static func commas(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


## 거르기 항목의 색 견본(모서리를 한 픽셀 깎은 네모)
static func _swatch(col: Color, px: int) -> Texture2D:
	var n := maxi(4, px)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(col)
	for c in [Vector2i(0, 0), Vector2i(n - 1, 0), Vector2i(0, n - 1), Vector2i(n - 1, n - 1)]:
		img.set_pixelv(c, Color(col, 0.0))
	return ImageTexture.create_from_image(img)


# ════════════════════════════ 목록 ════════════════════════════

## 줄 목록: 보이는 줄만 그리는 Control 하나. 문장은 줄마다 한 번 접어(wrap_text) 두고 글 폭이 바뀔 때만
## 다시 접는다(새 사건이 오면 새 줄만). 스크롤은 옆의 VScrollBar(bar) 값.
class RowList extends Control:
	signal row_clicked(i: int)

	## 고른(누른) 줄 사전(같은 사전이면 새 줄이 위에 붙어도 강조가 따라감)
	var selected: Dictionary = {}
	var bar: VScrollBar
	## i → 풍선 도움말 글(패널이 넣음)
	var tip_of: Callable
	## 검사용: 마지막 _draw 에서 그린 줄 수, 지금까지 문장을 접은 줄 수
	var drawn_rows := 0
	var shaped_rows := 0

	var _rows: Array = []
	var _older := 0
	var _tagged := false
	var _tags: Array[String] = []
	var _empty := ""
	var _hover := -1
	# 줄 위 끝 y(마지막 다음 칸 = 줄 끝, 그 뒤 "더 오래된" 표시)
	var _ys := PackedFloat32Array()
	var _total := 0.0
	var _laid_w := -1.0
	var _x_tick := 0.0
	var _tick_w := 0.0
	var _x_gen := 0.0
	var _gen_w := 0.0
	var _x_text := 0.0
	var _text_w := 0.0
	var _badge_w := 0.0
	var _footer_h := 0.0
	# 설정
	var _fs_meta := 13
	var _fs_text := 13
	var _max_lines := 2
	var _ellipsis := "…"
	var _stripe := 3.0
	var _pad_v := 4.0
	var _gap := 8.0
	var _badge_pad := 4.0
	var _badge_gap := 6.0
	var _wheel := 48.0
	var _colors: Array[Color] = []
	var _tag_boxes: Array[StyleBoxFlat] = []
	var _c_text := Color.WHITE
	var _c_dim := Color.GRAY
	var _c_line := Color.DIM_GRAY

	func _init() -> void:
		_fs_meta = UiConfig.integer("lab.font_size_small")
		_fs_text = UiConfig.integer("chronicle.text_font_size")
		_max_lines = maxi(1, UiConfig.integer("chronicle.text_max_lines"))
		_ellipsis = UiTheme.glyph_or("…", "...")
		_stripe = UiConfig.num("chronicle.stripe_width")
		_pad_v = UiConfig.num("chronicle.row_pad_v")
		_gap = UiConfig.num("chronicle.col_gap")
		_badge_pad = UiConfig.num("chronicle.badge_pad_h")
		_badge_gap = UiConfig.num("chronicle.badge_gap")
		_wheel = UiConfig.num("chronicle.wheel_step_px")
		for g in ChroniclePanel.COLOR_KEYS.size():
			_colors.append(ChroniclePanel.group_color(g))
		# A/B 이름표: 테두리만(색 = 그래프의 A·B 선 색), 글자는 본문 색
		for key in ["graph.series_a", "graph.series_b"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = UiConfig.color(key)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(UiConfig.integer("chronicle.badge_radius"))
			_tag_boxes.append(sb)
		_c_text = UiConfig.color("theme.text")
		_c_dim = UiConfig.color("theme.text_dim")
		_c_line = UiConfig.color("theme.panel_border")
		clip_contents = true
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP

	## 보일 줄(최신이 위)을 바꾼다. keep_scroll 이면 지금 맨 위에 걸친 줄을 같은 자리에 둔다(맨 위면 그대로 0).
	func set_rows(rows: Array, older: int, tagged: bool, tags: Array[String], empty_text: String, keep_scroll: bool) -> void:
		var anchor: Dictionary = {}
		var off := 0.0
		if keep_scroll and bar != null and bar.value > 0.0:
			var a := _row_at_y(bar.value)
			if a >= 0:
				anchor = _rows[a]
				off = bar.value - _ys[a]
		var retag := tagged != _tagged
		_rows = rows
		_older = older
		_tagged = tagged
		_tags = tags
		_empty = empty_text
		_hover = -1
		if retag:
			_laid_w = -1.0
		_layout()
		if bar != null:
			var v := 0.0
			if not anchor.is_empty():
				for i in _rows.size():
					if is_same(_rows[i], anchor):
						v = _ys[i] + off
						break
			bar.value = v
		queue_redraw()

	func total_height() -> float:
		return _total

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_RESIZED:
				if not is_equal_approx(size.x, _laid_w):
					_laid_w = -1.0
				_layout()
			NOTIFICATION_THEME_CHANGED:
				_laid_w = -1.0
				_layout()
			NOTIFICATION_MOUSE_EXIT:
				if _hover != -1:
					_hover = -1
					queue_redraw()

	func _font() -> Font:
		return get_theme_font("font", "Label")

	## 줄 높이·열 자리 계산. 열 폭(틱·평균 세대)은 보이는 줄 가운데 가장 넓은 것 — 바뀌면 문장 폭이 바뀌어 다시 접는다.
	func _layout() -> void:
		var font := _font()
		if font == null or size.x <= 0.0:
			_ys = PackedFloat32Array()
			_total = 0.0
			_sync_bar()
			return
		var tick_w := 0.0
		var gen_w := 0.0
		for r: Dictionary in _rows:
			tick_w = maxf(tick_w, _meta_w(font, r, "_tw", ChroniclePanel.TICK_WORD + " " + ChroniclePanel.commas(int(r.tick))))
			gen_w = maxf(gen_w, _meta_w(font, r, "_gw", ChroniclePanel.GEN_SHORT % float(r.gen)))
		_badge_w = 0.0
		if _tagged:
			_badge_w = font.get_string_size("W", HORIZONTAL_ALIGNMENT_LEFT, -1, _fs_meta).x + 2.0 * _badge_pad
		# A/B 이름표와 틱 사이는 열 사이(col_gap)보다 좁게(ui.chronicle.badge_gap) — 이름표가 그 줄의 틱에 붙어 보이게
		_x_tick = _stripe + _gap + (_badge_w + _badge_gap if _tagged else 0.0)
		_x_gen = _x_tick + ceilf(tick_w) + _gap
		_x_text = _x_gen + ceilf(gen_w) + _gap
		_text_w = maxf(1.0, size.x - _x_text - _gap * 0.5)
		_laid_w = size.x
		_tick_w = ceilf(tick_w)
		_gen_w = ceilf(gen_w)
		var line_h := maxf(font.get_height(_fs_text), font.get_height(_fs_meta))
		_ys.resize(_rows.size() + 1)
		var y := 0.0
		for i in _rows.size():
			_ys[i] = y
			y += float(maxi(1, _lines(font, _rows[i]).size())) * line_h + 2.0 * _pad_v + 1.0
		_ys[_rows.size()] = y
		_footer_h = (font.get_height(_fs_meta) + 2.0 * _pad_v + _gap) if _older > 0 else 0.0
		_total = y + _footer_h
		_sync_bar()

	## 줄 머리 글자 폭(줄 사전에 담아 둠 — 우리 사본이라 연대기는 그대로)
	func _meta_w(font: Font, r: Dictionary, key: String, text: String) -> float:
		if not r.has(key):
			r[key] = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs_meta).x
		return float(r[key])

	## 문장 줄(폭이 같으면 잡아 둔 것을 그대로 — 새 줄이나 폭이 바뀐 줄만 다시 접음)
	func _lines(font: Font, r: Dictionary) -> PackedStringArray:
		if r.has("_lines") and is_equal_approx(float(r.get("_lw", -1.0)), _text_w):
			return r["_lines"]
		var out := ChroniclePanel.wrap_text(font, str(r.text), _fs_text, _text_w, _max_lines, _ellipsis)
		r["_lines"] = out
		r["_lw"] = _text_w
		shaped_rows += 1
		return out

	func _sync_bar() -> void:
		if bar == null:
			return
		bar.max_value = maxf(_total, 1.0)
		bar.page = maxf(size.y, 1.0)
		bar.step = 1.0
		var need := _total > size.y + 0.5
		bar.modulate.a = 1.0 if need else 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_STOP if need else Control.MOUSE_FILTER_IGNORE
		if not need and bar.value != 0.0:
			bar.value = 0.0

	func _scroll() -> float:
		return bar.value if bar != null else 0.0

	## 목록 안 y(스크롤 포함)에 있는 줄(없으면 -1)
	func _row_at_y(y: float) -> int:
		if _rows.is_empty() or _ys.size() != _rows.size() + 1 or y < 0.0 or y >= _ys[_rows.size()]:
			return -1
		var lo := 0
		var hi := _rows.size() - 1
		while lo < hi:
			var mid := (lo + hi + 1) / 2
			if _ys[mid] <= y:
				lo = mid
			else:
				hi = mid - 1
		return lo

	func row_at(pos: Vector2) -> int:
		return _row_at_y(pos.y + _scroll())

	func scroll_to(i: int) -> void:
		if bar == null or i < 0 or i >= _rows.size() or _ys.size() <= i + 1:
			return
		var top := _ys[i]
		var bottom := _ys[i + 1]
		if top < bar.value:
			bar.value = top
		elif bottom > bar.value + size.y:
			bar.value = bottom - size.y

	func row_rect_global(i: int) -> Rect2:
		if i < 0 or i >= _rows.size() or _ys.size() <= i + 1:
			return Rect2()
		var r := Rect2(0.0, _ys[i] - _scroll(), size.x, _ys[i + 1] - _ys[i] - 1.0)
		r = r.intersection(Rect2(Vector2.ZERO, size))
		if r.size.y <= 0.0:
			return Rect2()
		return Rect2(get_global_transform() * r.position, r.size)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
					if bar != null:
						var k := maxf(mb.factor, 1.0) if mb.factor > 0.0 else 1.0
						bar.value += (_wheel if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -_wheel) * k
					_update_hover(mb.position)
					accept_event()
				MOUSE_BUTTON_LEFT:
					var i := row_at(mb.position)
					if i >= 0:
						row_clicked.emit(i)
					accept_event()
			return
		var pan := event as InputEventPanGesture
		if pan != null and bar != null:
			bar.value += pan.delta.y * _wheel
			accept_event()
			return
		var mm := event as InputEventMouseMotion
		if mm != null:
			_update_hover(mm.position)

	func _update_hover(pos: Vector2) -> void:
		var h := row_at(pos)
		if h != _hover:
			_hover = h
			queue_redraw()

	func _get_tooltip(at_position: Vector2) -> String:
		var i := row_at(at_position)
		if i < 0 or not tip_of.is_valid():
			return ""
		return str(tip_of.call(i))

	func _draw() -> void:
		drawn_rows = 0
		var font := _font()
		if font == null:
			return
		var meta_h := font.get_height(_fs_meta)
		var asc_meta := font.get_ascent(_fs_meta)
		var line_h := maxf(font.get_height(_fs_text), meta_h)
		var asc := maxf(font.get_ascent(_fs_text), asc_meta)
		if _rows.is_empty():
			var sz := font.get_string_size(_empty, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs_meta)
			draw_string(font, Vector2(maxf(0.0, (size.x - sz.x) * 0.5), (size.y - meta_h) * 0.5 + asc_meta), _empty,
					HORIZONTAL_ALIGNMENT_LEFT, size.x, _fs_meta, _c_dim)
			return
		if _laid_w < 0.0 or _ys.size() != _rows.size() + 1:
			_layout()
		if _ys.size() != _rows.size() + 1:
			return
		var sc := _scroll()
		var hover_box := get_theme_stylebox("hovered", "ItemList")
		var sel_box := get_theme_stylebox("selected", "ItemList")
		var bold := get_theme_font("font", "ValueLabel")
		var first := maxi(0, _row_at_y(sc))
		for i in range(first, _rows.size()):
			var top := _ys[i] - sc
			if top > size.y:
				break
			var h := _ys[i + 1] - _ys[i] - 1.0
			var r: Dictionary = _rows[i]
			var rect := Rect2(0.0, top, size.x, h)
			if is_same(r, selected):
				draw_style_box(sel_box, rect)
			elif i == _hover:
				draw_style_box(hover_box, rect)
			# 종류 색 띠
			draw_rect(Rect2(0.0, top + 1.0, _stripe, h - 2.0), _colors[clampi(int(r.group), 0, _colors.size() - 1)])
			var base := top + _pad_v + asc
			# 비교 모드: A/B 이름표(테두리 = 그래프의 A·B 선 색)
			if _tagged:
				var k := int(r.index)
				var bx := Rect2(_stripe + _gap, base - asc_meta, _badge_w, meta_h)
				draw_style_box(_tag_boxes[mini(k, _tag_boxes.size() - 1)], bx)
				var tag := _tags[k] if k < _tags.size() else "?"
				var tw := bold.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs_meta).x
				draw_string(bold, Vector2(bx.position.x + (bx.size.x - tw) * 0.5, base), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs_meta, _c_text)
			# 틱(오른쪽 맞춤: 숫자 자리가 줄마다 맞음) · 평균 세대(흐림)
			var num := ChroniclePanel.commas(int(r.tick))
			var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs_meta).x
			var right := _x_tick + _tick_w
			draw_string(font, Vector2(right - nw, base), num, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs_meta, _c_text)
			var word := ChroniclePanel.TICK_WORD + " "
			var ww := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs_meta).x
			draw_string(font, Vector2(right - nw - ww, base), word, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs_meta, _c_dim)
			var gen := ChroniclePanel.GEN_SHORT % float(r.gen)
			var gw := float(r.get("_gw", 0.0))
			draw_string(font, Vector2(_x_gen + _gen_w - gw, base), gen, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs_meta, _c_dim)
			var lines := _lines(font, r)
			for li in lines.size():
				draw_string(font, Vector2(_x_text, base + float(li) * line_h), lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, _fs_text, _c_text)
			# 줄 사이 가는 선
			draw_line(Vector2(_stripe + _gap, top + h + 0.5), Vector2(size.x, top + h + 0.5), _c_line, 1.0)
			drawn_rows += 1
		# 맨 아래: 잘린 오래된 줄 수
		if _older > 0:
			var fy := _ys[_rows.size()] - sc
			if fy < size.y:
				var msg := "더 오래된 %s개는 생략 — 내보낸 chronicle.csv 에 모두 있음" % ChroniclePanel.commas(_older)
				var mw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs_meta).x
				draw_string(font, Vector2(maxf(_gap, (size.x - mw) * 0.5), fy + _gap * 0.5 + _pad_v + asc_meta), msg,
						HORIZONTAL_ALIGNMENT_LEFT, size.x - _gap, _fs_meta, _c_dim)
