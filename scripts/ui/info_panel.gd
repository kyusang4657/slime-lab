class_name InfoPanel
extends PanelContainer
## 개체 정보 창(실험실 오른쪽). 고른 슬라임의 상태·특성·두뇌 가중치·가계(부모·조부모·자식)를 보여 준다.
## 계약: docs/VIEW-API.md "InfoPanel".
##
## 시뮬레이션은 SIM-API 의 읽기 질의(slime_info·children_of·index_of_id·lin_hue·L)와 읽기 전용 cfg(brain.weight_clamp)만 쓴다.
## 노드는 모두 코드로 만든다(.tscn 없음). 머리(색 견본·#id·세대·생사·따라가기)는 위에 고정, 나머지는 세로 스크롤.
## 테마는 실험실 공용 UiTheme 을 바탕으로(단추·말풍선이 실험실과 같은 모양), 이 창에만 있는 것(작은 단추 글자·가계 단추·
## 에너지 막대·가는 스크롤 막대·촘촘한 구분선)만 더한다. 수치는 ui.json 의 info·theme 절.
## refresh() 는 자주 불리므로(ui.info.refresh_frames) 바뀐 값만 다시 쓰고, 자식 목록은 자식 수가 바뀔 때만 다시 훑는다.

signal slime_requested(id: int)
signal follow_toggled(on: bool)

## 방향 이름(0 북 1 동 2 남 3 서 = SimGrid 순서)
const HEADING_NAMES: Array[String] = ["북 ↑", "동 →", "남 ↓", "서 ←"]
## 가계 단추 메타(검사·도움말용)
const META_ID := "slime_id"
const META_REL := "relation"
const REL_PARENT := "parent"
const REL_GRANDPARENT := "grandparent"
const REL_CHILD := "child"
const EMPTY_TEXT := "슬라임을 눌러 고르세요"
const EMPTY_HINT := "지도에서 슬라임을 클릭하면\n상태·두뇌·가계가 여기에 나옵니다"
const BOLD_FONT := "res://assets/fonts/NanumGothic-Bold.ttf"
## 에너지 막대 상태(채움 색 고르기)
const ENERGY_OK := 0
const ENERGY_WARN := 1
const ENERGY_DANGER := 2
## 머리 견본의 세로/가로 비
const SWATCH_ASPECT := 0.72
## 정보 창 작은 단추(따라가기·가계)의 형 변형: 공용 Button 모양 + 굵은 작은 글자
const SMALL_BUTTON := "InfoSmallButton"
## 창 왼쪽 테두리 두께(픽셀)
const PANEL_BORDER := 1
## 머리·본문 여백 비(info.padding 에 곱함: 위쪽은 조금 좁게)
const PAD_TIGHT := 0.8
const PAD_HALF := 0.5
## 에너지 막대·가는 스크롤 막대 색 변형(어둡게·밝게)
const FILL_DARKEN := 0.12
const GRAB_LIGHTEN := 0.08
const GRAB_HOVER_LIGHTEN := 0.25
const GRAB_PRESS_DARKEN := 0.2
const BAR_RADIUS_K := 0.75
## 마우스 휠 한 칸에 바깥 스크롤을 움직이는 몫(ScrollContainer 기본과 같은 page/8)
const WHEEL_PAGE := 0.125

## 자식 목록을 다시 훑은 횟수(검사용: 자식 수가 그대로면 refresh 가 훑지 않는다)
var children_scans := 0

var _world: SimWorld
var _id := -1
var _alive := false
var _has_brain := false
# 가계 단추로 옮겨 가는 중(slime_requested 를 내는 동안 true): 스크롤 위치를 그대로 둔다
var _nav_from_panel := false
# 자식 목록 캐시: (세계, id) 와 그때의 자식 수. 수가 바뀌고 목록이 한도 미만일 때만 다시 훑는다.
var _kids := PackedInt32Array()
var _kids_world: SimWorld
var _kids_for := -1
var _kids_count := -1
var _fixed_buttons: Array[RelativeButton] = []
var _kid_buttons: Array[RelativeButton] = []
# 빈 상태 안내를 바꿔 쓰는 문구(멸종 등, "" = 기본 EMPTY_TEXT)
var _empty_text := ""

# ── 노드 ──
var _empty: VBoxContainer
var _empty_label: Label
var _main: VBoxContainer
var _swatch: SlimeSwatch
# 비교 모드 이름표(A/B, 실험 색 바탕). 혼자면 숨김(4단계)
var _tag: PanelContainer
var _tag_label: Label
var _title: Label
var _gen: Label
var _status: Label
var _follow: Button
var _scroll: ScrollContainer
var _body: VBoxContainer
var _sec_state: VBoxContainer
var _sec_death: VBoxContainer
var _v_age: Label
var _energy_bar: ProgressBar
var _energy_label: Label
var _v_carry: Label
var _v_action: Label
var _v_pos: Label
var _v_head: Label
var _v_cause: Label
var _v_death: Label
var _v_life: Label
var _v_size: Label
var _v_sense: Label
var _hue_dot: ColorDot
var _v_hue: Label
var _v_birth: Label
var _v_children: Label
var _brain: BrainView
var _brain_note: Label
var _parents_flow: HFlowContainer
var _gp_flow: HFlowContainer
var _kids_key: Label
var _kids_flow: HFlowContainer
var _kids_more: Label

# ── 설정 값 ──
var _fs := 15
var _fs_small := 13
var _fs_title := 18
var _pad := 14.0
var _rel_pad_y := 3.0
var _row_gap := 6
var _key_w := 64.0
var _children_max := 24
var _warn_frac := 0.35
var _danger_frac := 0.15
var _sat := 0.6
var _val := 0.9
var _c_bg := Color.BLACK
var _c_panel := Color.BLACK
var _c_border := Color.DIM_GRAY
var _c_text := Color.WHITE
var _c_dim := Color.GRAY
var _c_accent := Color.AQUAMARINE
var _c_warn := Color.ORANGE
var _c_danger := Color.RED
var _c_eye := Color.BLACK
var _bold: Font
var _fill_styles: Array[StyleBoxFlat] = []
var _energy_state := -1
var _rel_alive_style: Dictionary = {}
var _rel_dead_style: Dictionary = {}
var _brain_scroll: ScrollContainer


func _init() -> void:
	_read_config()
	custom_minimum_size = Vector2(UiConfig.num("lab.right_panel_width"), 0.0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	theme = _make_theme()
	add_theme_stylebox_override("panel", _panel_style())
	_build()
	clear()


func _read_config() -> void:
	_fs = UiConfig.integer("lab.font_size")
	_fs_small = UiConfig.integer("lab.font_size_small")
	_fs_title = UiConfig.integer("info.title_font_size")
	_pad = UiConfig.num("info.padding")
	_rel_pad_y = UiConfig.num("info.relative_pad_v")
	_row_gap = UiConfig.integer("info.row_gap")
	_key_w = UiConfig.num("info.key_width")
	_children_max = UiConfig.integer("info.children_max")
	_warn_frac = UiConfig.num("info.energy_warn_frac")
	_danger_frac = UiConfig.num("info.energy_danger_frac")
	_sat = UiConfig.num("slime.saturation")
	_val = UiConfig.num("slime.value")
	_c_bg = UiConfig.color("theme.background")
	_c_panel = UiConfig.color("theme.panel")
	_c_border = UiConfig.color("theme.panel_border")
	_c_text = UiConfig.color("theme.text")
	_c_dim = UiConfig.color("theme.text_dim")
	_c_accent = UiConfig.color("theme.accent")
	_c_warn = UiConfig.color("theme.warn")
	_c_danger = UiConfig.color("theme.danger")
	_c_eye = UiConfig.color("slime.eye_color")
	_bold = load(BOLD_FONT)


# ════════════════════════════ 계약 함수 ════════════════════════════

## 개체 정보 표시. 없는 id 면 안내 문구만(current_id() = -1).
func show_slime(world: SimWorld, id: int) -> void:
	if world == null:
		clear()
		return
	var d := world.slime_info(id)
	if d.is_empty():
		clear()
		_empty_label.text = "#%d 개체의 기록이 없습니다" % id
		return
	_world = world
	_id = id
	_empty.hide()
	_main.show()
	_fill_static(d)
	_fill_family(d)
	_apply_life(d, true)
	_update_live(d)
	_update_children(d)
	if not _nav_from_panel:
		_scroll.scroll_vertical = 0


## "슬라임을 눌러 고르세요" 안내(set_empty_text 로 바꾼 문구가 있으면 그것). 따라가기 상태는 그대로 둔다(LabMain 이 관리).
func clear() -> void:
	_id = -1
	_world = null
	_main.hide()
	_empty.show()
	_empty_label.text = _empty_text if _empty_text != "" else EMPTY_TEXT
	_clear_flow(_parents_flow)
	_clear_flow(_gp_flow)
	_clear_flow(_kids_flow)
	_fixed_buttons.clear()
	_kid_buttons.clear()
	_kids_for = -1
	_kids_world = null


## 같은 개체의 바뀐 값을 다시 쓴다. 그사이 죽었으면 죽음 표시로 바꾼다. 자식 목록은 자식 수가 바뀔 때만 다시 훑는다.
func refresh() -> void:
	if _world == null or _id < 0:
		return
	var d := _world.slime_info(_id)
	if d.is_empty():
		clear()
		return
	_apply_life(d, false)
	_update_live(d)
	_update_children(d)
	_update_relatives()


func current_id() -> int:
	return _id


## (추가) 빈 상태 안내 문구를 바꾼다("" = 기본 "슬라임을 눌러 고르세요"). LabMain 이 멸종하면 멸종 문구로.
## 지금 빈 상태면 바로 바뀌고, 개체를 보이는 중이면 다음 clear() 부터.
func set_empty_text(text: String) -> void:
	_empty_text = text
	if _id < 0:
		_empty_label.text = _empty_text if _empty_text != "" else EMPTY_TEXT


## (추가, 4단계) 비교 모드에서 어느 실험의 개체인지 머리에 이름표("A"/"B")로 보인다. "" = 숨김(혼자 모드).
## col = 이름표 바탕(실험 색, 글자는 어두운 바탕색). 투명이면 강조 색.
func set_tag(tag: String, col: Color = Color(0, 0, 0, 0)) -> void:
	_tag_label.text = tag
	_tag.visible = tag != ""
	var sb := _tag.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.bg_color = col if col.a > 0.0 else _c_accent


## (추가, 4단계) 지금 이름표("" = 없음). 검사용.
func current_tag() -> String:
	return _tag_label.text if _tag.visible else ""


## (추가) 따라가기 단추 상태만 맞춘다(신호 없음). LabMain 이 F 키로 바꿨을 때 쓴다.
func set_follow(on: bool) -> void:
	_follow.set_pressed_no_signal(on)


## (추가) 두뇌 열지도가 들어갈 너비(픽셀): 창 폭 − 테두리 − 양쪽 여백 − 세로 스크롤 막대. 넘치는 열지도는 가로 스크롤.
static func brain_width() -> float:
	return UiConfig.num("lab.right_panel_width") - float(PANEL_BORDER) - 2.0 * UiConfig.num("info.padding") - UiConfig.num("info.scrollbar_width")


## (추가) 스크롤 본문이 보이는 높이를 넘는 픽셀(음수 = 남는 여유). 1600×900 에서 보통 개체는 스크롤 없이(검사 V07).
func content_overflow() -> float:
	if _scroll == null or _scroll.get_child_count() == 0:
		return 0.0
	return (_scroll.get_child(0) as Control).get_combined_minimum_size().y - _scroll.size.y


## (추가) 머리 한 줄 요약 "#id · N세대 · 살아 있음"(빈 상태면 안내 문구). 검사·캡처 확인용.
func summary_text() -> String:
	if _id < 0:
		return _empty_label.text
	return "%s · %s · %s" % [_title.text, _gen.text, _status.text]


# ════════════════════════════ 채우기 ════════════════════════════

## 개체가 바뀔 때 한 번: 머리·특성·두뇌.
func _fill_static(d: Dictionary) -> void:
	var hue := float(d.hue)
	_swatch.color = _hue_color(hue)
	_swatch.eye_color = _c_eye
	_swatch.shadow_alpha = UiConfig.num("map.blob_shadow_alpha")
	_swatch.tooltip_text = "계통 색 (색상 %.3f)" % hue
	_title.text = "#%d" % _id
	_gen.text = "%d세대" % int(d.gen)
	_v_size.text = "%.2f" % float(d.size)
	var sense := float(d.sense)
	_v_sense.text = "%.2f  (반경 %d칸)" % [sense, int(floorf(sense + 0.5))]
	_hue_dot.color = _hue_color(hue)
	_v_hue.text = "%.3f" % hue
	_v_birth.text = "틱 " + _fmt_int(int(d.birth))
	if d.has("genome"):
		_brain.weight_clamp = float(_world.cfg["brain"]["weight_clamp"])
		_brain.max_width = brain_width()
		_brain.set_genome(_world.L, d.genome)
		_brain_scroll.scroll_horizontal = 0
		_brain_scroll.show()
		_brain_note.hide()
		_has_brain = true
	else:
		_brain_scroll.hide()
		_brain_note.text = "죽은 개체의 유전체는 세계에 남지 않아 두뇌를 그릴 수 없습니다."
		_brain_note.show()
		_has_brain = false


## 부모(2)·조부모(최대 4) 단추. 계통은 바뀌지 않으므로 개체가 바뀔 때만 만든다.
func _fill_family(d: Dictionary) -> void:
	_clear_flow(_parents_flow)
	_clear_flow(_gp_flow)
	_fixed_buttons.clear()
	var pa := int(d.parent_a)
	var pb := int(d.parent_b)
	if pa == SimWorld.NO_PARENT:
		_parents_flow.add_child(_note("초기 개체"))
		_gp_flow.add_child(_note("—"))
		return
	var parents: Array[int] = [pa]
	if pb != SimWorld.NO_PARENT and pb != pa:
		parents.append(pb)
	for p in parents:
		_parents_flow.add_child(_relative_button(p, REL_PARENT))
	if pb == SimWorld.NO_PARENT:
		_parents_flow.add_child(_note("(혼자 번식)"))
	var gps: Array[int] = []
	for p in parents:
		var pd := _world.slime_info(p)
		for g in [int(pd.get("parent_a", SimWorld.NO_PARENT)), int(pd.get("parent_b", SimWorld.NO_PARENT))]:
			if g != SimWorld.NO_PARENT and not gps.has(g):
				gps.append(g)
	if gps.is_empty():
		_gp_flow.add_child(_note("없음 · 부모가 초기 개체"))
	for g in gps:
		_gp_flow.add_child(_relative_button(g, REL_GRANDPARENT))


## 생사 표시 전환(force = 개체가 바뀜). 죽으면 상태 절을 숨기고 죽음 절·원인·사망 틱을 보인다.
func _apply_life(d: Dictionary, force: bool) -> void:
	var alive := bool(d.alive)
	if alive == _alive and not force:
		return
	_alive = alive
	_swatch.dead = not alive
	_follow.disabled = not alive
	_sec_state.visible = alive
	_sec_death.visible = not alive
	if alive:
		_status.text = "살아 있음"
		_status.add_theme_color_override("font_color", _c_accent)
		return
	var cause := int(d.cause)
	var cname: String = SimWorld.CAUSE_NAMES[cause] if cause >= 0 and cause < SimWorld.CAUSE_NAMES.size() else "?"
	var death := int(d.death)
	_status.text = "죽음 · %s · 틱 %s" % [cname, _fmt_int(death)]
	_status.add_theme_color_override("font_color", _c_danger)
	_v_cause.text = cname
	_v_death.text = "틱 " + _fmt_int(death)
	_v_life.text = "%s틱  (출생 %s)" % [_fmt_int(death - int(d.birth)), _fmt_int(int(d.birth))]
	_brain.set_highlight_action(-1)
	if _has_brain:
		_brain_note.text = "죽기 직전의 두뇌"
		_brain_note.show()


## 살아 있는 동안 바뀌는 값(나이·에너지·운반·행동·위치·방향).
func _update_live(d: Dictionary) -> void:
	if not _alive:
		return
	_v_age.text = "%s / %s틱" % [_fmt_int(int(d.age)), _fmt_int(int(d.max_age))]
	var e := float(d.energy)
	var emax := maxf(float(d.energy_max), 0.0001)
	_energy_bar.max_value = emax
	_energy_bar.value = e
	_energy_label.text = "%.1f / %.1f" % [e, emax]
	var frac := e / emax
	var st := ENERGY_OK
	if frac < _danger_frac:
		st = ENERGY_DANGER
	elif frac < _warn_frac:
		st = ENERGY_WARN
	if st != _energy_state:
		_energy_state = st
		_energy_bar.add_theme_stylebox_override("fill", _fill_styles[st])
	var carry := float(d.carry)
	_v_carry.text = "%.1f" % carry if carry > 0.0 else "없음"
	var act := int(d.action)
	_v_action.text = SimBrain.ACTION_NAMES[act] if act >= 0 and act < SimBrain.ACTION_NAMES.size() else "?"
	_brain.set_highlight_action(act)
	_v_pos.text = "(%d, %d)" % [int(d.x), int(d.y)]
	var hd := int(d.heading)
	_v_head.text = HEADING_NAMES[hd] if hd >= 0 and hd < HEADING_NAMES.size() else "?"


## 자식 목록. children_of 는 계통 전체를 훑으므로 (세계, id) 가 바뀌었거나
## 자식 수가 바뀌었고 아직 목록이 한도(children_max) 미만일 때만 다시 부른다.
func _update_children(d: Dictionary) -> void:
	var n := int(d.children)
	_v_children.text = str(n)
	_kids_key.text = "자식 %d" % n
	var stale := _kids_for != _id or _kids_world != _world
	if stale or (n != _kids_count and _kids.size() < mini(n, _children_max)):
		_kids = _world.children_of(_id, _children_max)
		children_scans += 1
		_kids_for = _id
		_kids_world = _world
		_rebuild_kid_buttons()
	_kids_count = n
	var more := n - _kids.size()
	_kids_more.visible = more > 0
	_kids_more.text = "+%d" % more


func _rebuild_kid_buttons() -> void:
	_kids_flow.remove_child(_kids_more)
	_clear_flow(_kids_flow)
	_kid_buttons.clear()
	if _kids.is_empty():
		_kids_flow.add_child(_note("없음"))
	for k in _kids:
		var b := _relative_button(k, REL_CHILD)
		_kid_buttons.append(b)
		_kids_flow.add_child(b)
	_kids_flow.add_child(_kids_more)


## 친척 단추의 생사(흐림)만 갱신. 이진 탐색 몇십 번이라 매번 해도 싸다.
func _update_relatives() -> void:
	for b in _fixed_buttons:
		_sync_relative(b)
	for b in _kid_buttons:
		_sync_relative(b)


func _sync_relative(b: RelativeButton) -> void:
	var alive := _world.index_of_id(b.slime_id) != -1
	if alive != b.alive:
		_style_relative(b, alive)


# ════════════════════════════ 가계 단추 ════════════════════════════

func _relative_button(rid: int, rel: String) -> RelativeButton:
	var b := RelativeButton.new()
	b.slime_id = rid
	b.text = "#%d" % rid
	b.dot = UiConfig.num("info.relative_dot")
	b.dot_left = _pad * PAD_HALF
	b.dead_alpha = UiConfig.num("info.dead_dot_alpha")
	b.theme_type_variation = SMALL_BUTTON
	b.dot_color = _hue_color(float(_world.lin_hue[rid])) if rid >= 0 and rid < _world.lin_hue.size() else _c_dim
	b.focus_mode = Control.FOCUS_NONE
	# 휠은 바깥 스크롤 창으로 넘긴다(누르기는 단추가 받음)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.set_meta(META_ID, rid)
	b.set_meta(META_REL, rel)
	b.pressed.connect(_on_relative_pressed.bind(rid))
	_style_relative(b, _world.index_of_id(rid) != -1)
	if rel != REL_CHILD:
		_fixed_buttons.append(b)
	return b


## 살아 있으면 채운 점·밝은 글자, 죽었으면 속 빈 점·흐린 글자·테두리만.
func _style_relative(b: RelativeButton, alive: bool) -> void:
	b.alive = alive
	var styles: Dictionary = _rel_alive_style if alive else _rel_dead_style
	for k in styles:
		b.add_theme_stylebox_override(k, styles[k])
	var fc := _c_text if alive else Color(_c_dim, UiConfig.num("info.dead_text_alpha"))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, fc)
	b.tooltip_text = _relative_tip(b.slime_id)
	b.queue_redraw()


func _relative_tip(rid: int) -> String:
	var d := _world.slime_info(rid)
	if d.is_empty():
		return "#%d" % rid
	var s := "#%d · %d세대 · " % [rid, int(d.gen)]
	if bool(d.alive):
		s += "살아 있음"
	else:
		var cause := int(d.cause)
		var cname: String = SimWorld.CAUSE_NAMES[cause] if cause >= 0 and cause < SimWorld.CAUSE_NAMES.size() else "?"
		s += "죽음(%s, 틱 %s)" % [cname, _fmt_int(int(d.death))]
	return s + "\n눌러서 이 개체 보기"


func _on_relative_pressed(rid: int) -> void:
	# LabMain 이 이 신호 안에서 바로 show_slime 을 부르면 스크롤을 처음으로 되돌리지 않는다(가계를 이어서 훑기)
	_nav_from_panel = true
	slime_requested.emit(rid)
	_nav_from_panel = false


func _on_follow_toggled(on: bool) -> void:
	follow_toggled.emit(on)


# ════════════════════════════ 만들기 ════════════════════════════

func _build() -> void:
	# 빈 상태 안내
	_empty = VBoxContainer.new()
	_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty.add_theme_constant_override("separation", _row_gap * 2)
	add_child(_empty)
	_empty_label = _label(EMPTY_TEXT, _fs, _c_text, true)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_child(_empty_label)
	var hint := _label(EMPTY_HINT, _fs_small, _c_dim)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_child(hint)
	# 본문: 고정 머리 + 구분선 + 스크롤
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 0)
	add_child(_main)
	_build_header()
	_main.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main.add_child(_scroll)
	var m := _margin(_pad, _pad * PAD_TIGHT, _pad, _pad)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(m)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", UiConfig.integer("info.section_gap"))
	m.add_child(_body)
	_build_state()
	_build_death()
	_build_traits()
	_build_family()
	_build_brain()


func _build_header() -> void:
	var m := _margin(_pad, _pad, _pad, _pad * PAD_TIGHT)
	_main.add_child(m)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(_pad * PAD_TIGHT))
	m.add_child(head)
	var sw := UiConfig.num("info.swatch_size")
	_swatch = SlimeSwatch.new()
	_swatch.mouse_filter = Control.MOUSE_FILTER_PASS
	_swatch.custom_minimum_size = Vector2(sw, sw * SWATCH_ASPECT)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_swatch)
	var tb := VBoxContainer.new()
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tb.add_theme_constant_override("separation", UiConfig.integer("info.title_gap"))
	head.add_child(tb)
	var trow := HBoxContainer.new()
	tb.add_child(trow)
	# 비교 모드 이름표(A/B): 실험 색 바탕 + 어두운 글자(글자 자체는 색을 입히지 않음)
	_tag = PanelContainer.new()
	_tag.add_theme_stylebox_override("panel", UiTheme.box(_c_accent, Color(0, 0, 0, 0), 0, UiConfig.integer("info.corner_radius"),
			UiConfig.num("info.relative_pad_left"), 0.0))
	_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.visible = false
	trow.add_child(_tag)
	_tag_label = _label("", _fs, _c_bg, true)
	_tag.add_child(_tag_label)
	_title = _label("", _fs_title, _c_text, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(_title)
	_follow = Button.new()
	_follow.text = "따라가기"
	_follow.toggle_mode = true
	_follow.theme_type_variation = SMALL_BUTTON
	_follow.focus_mode = Control.FOCUS_NONE
	_follow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_follow.tooltip_text = "카메라가 이 개체를 따라갑니다 (F)"
	_follow.toggled.connect(_on_follow_toggled)
	trow.add_child(_follow)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", UiConfig.integer("info.inline_gap"))
	tb.add_child(srow)
	_gen = _label("", _fs_small, _c_dim, true)
	srow.add_child(_gen)
	_status = _label("", _fs_small, _c_accent)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	srow.add_child(_status)


func _build_state() -> void:
	_sec_state = _section("현재 상태")
	var g := _grid(_sec_state)
	_v_age = _row(g, "나이")
	_key(g, "에너지")
	_energy_bar = ProgressBar.new()
	_energy_bar.show_percentage = false
	_energy_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy_bar.custom_minimum_size = Vector2(0.0, UiConfig.num("info.energy_bar_height"))
	_energy_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_energy_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.add_child(_energy_bar)
	_energy_label = _label("", _fs_small, _c_text, true)
	_energy_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_energy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_energy_label.add_theme_constant_override("outline_size", UiConfig.integer("info.energy_outline"))
	_energy_label.add_theme_color_override("font_outline_color", _c_bg)
	_energy_bar.add_child(_energy_label)
	_v_carry = _row(g, "운반")
	_v_action = _row(g, "행동")
	_v_pos = _row(g, "위치")
	_v_head = _row(g, "방향")


func _build_death() -> void:
	_sec_death = _section("죽음")
	var g := _grid(_sec_death)
	_v_cause = _row(g, "원인")
	_v_cause.add_theme_color_override("font_color", _c_danger)
	_v_death = _row(g, "사망")
	_v_life = _row(g, "산 기간")


func _build_traits() -> void:
	var sec := _section("특성")
	var g := _grid(sec)
	_v_size = _row(g, "크기")
	_v_sense = _row(g, "감지")
	_key(g, "색")
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", UiConfig.integer("info.inline_gap"))
	g.add_child(hb)
	_hue_dot = ColorDot.new()
	_hue_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dd := float(_fs)
	_hue_dot.custom_minimum_size = Vector2(dd, dd)
	_hue_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(_hue_dot)
	_v_hue = _label("", _fs, _c_text)
	hb.add_child(_v_hue)
	_v_birth = _row(g, "출생")
	_v_children = _row(g, "자식 수")


func _build_brain() -> void:
	var sec := _section("두뇌 가중치")
	# 안내(죽기 직전의 두뇌 / 두뇌 없음)는 열지도 위에 둬서 스크롤 없이 보이게
	_brain_note = _label("", _fs_small, _c_dim)
	_brain_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brain_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec.add_child(_brain_note)
	# 열지도는 창 폭에 맞추고(BrainView.max_width), 그래도 넘치는 큰 두뇌(은닉 64 등)는 이 안에서만 가로 스크롤 —
	# 정보 창 폭(= 지도 폭)이 고른 개체에 따라 바뀌지 않게. 세로 휠은 바깥 스크롤로 넘긴다.
	_brain_scroll = ScrollContainer.new()
	_brain_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_brain_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_brain_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brain_scroll.gui_input.connect(_on_brain_wheel)
	sec.add_child(_brain_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_brain_scroll.add_child(center)
	_brain = BrainView.new()
	center.add_child(_brain)


## 두뇌 열지도 위의 세로 휠은 바깥(창 본문) 스크롤로(가로 스크롤 상자가 휠을 가로로 먹지 않게). Shift+휠은 가로.
func _on_brain_wheel(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.shift_pressed:
		return
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	var page := _scroll.get_v_scroll_bar().page
	var sign := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
	_scroll.scroll_vertical += int(sign * page * WHEEL_PAGE * maxf(mb.factor, 1.0))
	_brain_scroll.accept_event()


func _build_family() -> void:
	var sec := _section("가계")
	_parents_flow = _family_row(sec, "부모")
	_gp_flow = _family_row(sec, "조부모")
	_kids_flow = _family_row(sec, "자식")
	# _family_row 가 만든 마지막 열쇠 글자 = 자식 수 표시
	var row := _kids_flow.get_parent()
	_kids_key = row.get_child(0) as Label
	_kids_more = _label("", _fs_small, _c_dim, true)
	_kids_more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_kids_more.tooltip_text = "표시 한도(ui.info.children_max)를 넘는 자식 수"
	_kids_more.mouse_filter = Control.MOUSE_FILTER_PASS
	_kids_flow.add_child(_kids_more)


# ── 작은 만들기 도우미 ──

func _label(text: String, fs: int, col: Color, bold: bool = false) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", fs)
	lb.add_theme_color_override("font_color", col)
	if bold:
		lb.add_theme_font_override("font", _bold)
	return lb


func _note(text: String) -> Label:
	var lb := _label(text, _fs_small, _c_dim)
	lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return lb


func _margin(l: float, t: float, r: float, b: float) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", int(l))
	m.add_theme_constant_override("margin_top", int(t))
	m.add_theme_constant_override("margin_right", int(r))
	m.add_theme_constant_override("margin_bottom", int(b))
	return m


## 절: 작은 굵은 제목 + 오른쪽으로 이어지는 가는 선.
func _section(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _row_gap + UiConfig.integer("info.title_gap"))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiConfig.integer("info.inline_gap"))
	box.add_child(head)
	head.add_child(_label(title, _fs_small, _c_accent, true))
	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(line)
	_body.add_child(box)
	return box


func _grid(parent: Control) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", UiConfig.integer("info.key_gap"))
	g.add_theme_constant_override("v_separation", _row_gap)
	parent.add_child(g)
	return g


func _key(g: GridContainer, text: String) -> Label:
	var k := _label(text, _fs_small, _c_dim)
	k.custom_minimum_size = Vector2(_key_w, 0.0)
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.add_child(k)
	return k


## 열쇠-값 한 줄. 값 글자는 넘치면 말줄임(창 너비를 밀어내지 않게).
func _row(g: GridContainer, key: String) -> Label:
	_key(g, key)
	var v := _label("", _fs, _c_text)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.clip_text = true
	v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	g.add_child(v)
	return v


## 가계 한 줄: 열쇠 글자 + 줄바꿈 단추 흐름.
func _family_row(sec: VBoxContainer, key: String) -> HFlowContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiConfig.integer("info.key_gap"))
	sec.add_child(row)
	var k := _label(key, _fs_small, _c_dim)
	# 첫 줄 단추와 글자 높이를 맞춘다(단추 = 굵은 글꼴 높이 + 위아래 여백)
	k.custom_minimum_size = Vector2(_key_w, _bold.get_height(_fs_small) + _rel_pad_y * 2.0)
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(k)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gap := UiConfig.integer("info.relative_gap")
	flow.add_theme_constant_override("h_separation", gap)
	flow.add_theme_constant_override("v_separation", gap)
	row.add_child(flow)
	return flow


func _clear_flow(f: Container) -> void:
	for c in f.get_children():
		if c == _kids_more:
			continue
		f.remove_child(c)
		c.queue_free()


func _hue_color(hue: float) -> Color:
	return Color.from_hsv(hue, _sat, _val)


## 1234567 → "1,234,567"
static func _fmt_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# ── 테마(공용 UiTheme + 이 창에만 있는 것. 수치는 ui.json theme·lab·info) ──

func _box(bg: Color, radius: float, pad_x: float, pad_y: float) -> StyleBoxFlat:
	return UiTheme.box(bg, Color(0, 0, 0, 0), 0, int(radius), pad_x, pad_y)


func _panel_style() -> StyleBoxFlat:
	var s := _box(_c_panel, 0.0, 0.0, 0.0)
	s.border_width_left = PANEL_BORDER
	s.border_color = _c_border
	s.anti_aliasing = false
	return s


func _make_theme() -> Theme:
	var th := Theme.new()
	# 공용 테마를 바탕으로: 단추(따라가기)·말풍선·차림표는 실험실 전체와 같은 모양(theme.button_padding_* 등)
	th.merge_with(UiTheme.build())
	th.default_font_size = _fs
	var r := UiConfig.num("info.corner_radius")
	# 작은 단추(따라가기·가계): 공용 단추 모양 + 굵은 작은 글자
	th.set_type_variation(SMALL_BUTTON, "Button")
	th.set_font("font", SMALL_BUTTON, _bold)
	th.set_font_size("font_size", SMALL_BUTTON, _fs_small)
	# 에너지 막대
	var br := r * BAR_RADIUS_K
	th.set_stylebox("background", "ProgressBar", _box(_c_bg, br, 0.0, 0.0))
	for c in [_c_accent, _c_warn, _c_danger]:
		_fill_styles.append(_box(Color(c).darkened(FILL_DARKEN), br, 0.0, 0.0))
	th.set_stylebox("fill", "ProgressBar", _fill_styles[ENERGY_OK])
	# 촘촘한 구분선(머리 아래·절 제목 옆, 높이 info.separator_gap)
	var line := StyleBoxLine.new()
	line.color = _c_border
	line.thickness = PANEL_BORDER
	th.set_stylebox("separator", "HSeparator", line)
	th.set_constant("separation", "HSeparator", UiConfig.integer("info.separator_gap"))
	# 가는 스크롤 막대
	var sbw := UiConfig.num("info.scrollbar_width")
	var half := sbw * PAD_HALF
	var track := _box(Color(_c_bg, 0.0), half, half, 0.0)
	th.set_stylebox("scroll", "VScrollBar", track)
	th.set_stylebox("scroll_focus", "VScrollBar", track)
	th.set_stylebox("grabber", "VScrollBar", _box(_c_border.lightened(GRAB_LIGHTEN), half, half, 0.0))
	th.set_stylebox("grabber_highlight", "VScrollBar", _box(_c_border.lightened(GRAB_HOVER_LIGHTEN), half, half, 0.0))
	th.set_stylebox("grabber_pressed", "VScrollBar", _box(_c_accent.darkened(GRAB_PRESS_DARKEN), half, half, 0.0))
	# 가계 단추 모양(살아 있음 / 죽음): 왼쪽은 계통 색 점 자리
	var lp := UiConfig.num("info.relative_dot") + _pad * PAD_HALF + UiConfig.num("info.relative_pad_left")
	var rp := UiConfig.num("info.relative_pad_right")
	for k in ["normal", "hover", "pressed", "hover_pressed"]:
		var lift := UiConfig.num("info.relative_lighten" if k == "normal" else "info.relative_hover_lighten")
		var a := _box(_c_border.lightened(lift), r, rp, _rel_pad_y)
		a.content_margin_left = lp
		_rel_alive_style[k] = a
		var dstyle := _box(Color(_c_panel, 1.0) if k == "normal" else _c_border.darkened(UiConfig.num("info.relative_dead_darken")), r, rp, _rel_pad_y)
		dstyle.content_margin_left = lp
		dstyle.set_border_width_all(PANEL_BORDER)
		dstyle.border_color = _c_border
		_rel_dead_style[k] = dstyle
	return th


# ════════════════════════════ 작은 그리기 노드 ════════════════════════════

## 머리의 색 견본: 아래가 납작한 물방울 슬라임(지도 모델의 실루엣)과 두 눈. 죽으면 눈이 ×.
class SlimeSwatch:
	extends Control
	## 둘레 점 수
	const SEGMENTS := 32
	## 초타원 지수(1 = 반타원, 작을수록 어깨가 꽉 찬 찹쌀떡 모양)
	const ROUNDNESS := 0.7
	## 바닥 쪽 퍼짐(아래로 갈수록 넓어지는 정도)
	const SPREAD := 0.1
	## 눈 위치·크기(몸 반지름·높이에 대한 비)
	const EYE_DX := 0.36
	const EYE_Y := 0.42
	const EYE_R := 0.13
	const GLINT_R := 0.05
	## 바닥 그림자 납작함
	const SHADOW_FLAT := 0.22
	## 몸 둘레 여백(픽셀)·바닥 높이
	const INSET := 1.5
	const TOP_INSET := 3.0
	const BASE_INSET := 2.0
	## 윗부분 반사광 자리·크기·불투명도, 윤곽선 어둡게·두께, 죽은 몸 어둡게, 반사점 위치, × 선 두께
	const SHINE_X := 0.42
	const SHINE_Y := 0.7
	const SHINE_R := 0.13
	const SHINE_ALPHA := 0.4
	const OUTLINE_DARKEN := 0.55
	const OUTLINE_W := 1.5
	const DEAD_DARKEN := 0.3
	const GLINT_OFF := 0.35
	const CROSS_W := 2.0

	## 눈 색(ui.slime.eye_color)·바닥 그림자 불투명도(ui.map.blob_shadow_alpha) — InfoPanel 이 넣음
	var eye_color := Color.BLACK
	var shadow_alpha := 0.4
	var color := Color.WHITE:
		set(v):
			color = v
			queue_redraw()
	var dead := false:
		set(v):
			dead = v
			queue_redraw()

	func _draw() -> void:
		var rx := size.x * 0.5 / (1.0 + SPREAD) - INSET
		var ry := size.y - TOP_INSET
		var base := Vector2(size.x * 0.5, size.y - BASE_INSET)
		# 바닥 그림자(납작한 타원)
		draw_set_transform(base, 0.0, Vector2(1.0, SHADOW_FLAT))
		draw_circle(Vector2.ZERO, rx * (1.0 + SPREAD), Color(0, 0, 0, shadow_alpha), true, -1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var pts := PackedVector2Array()
		for k in SEGMENTS + 1:
			var a := PI + PI * float(k) / float(SEGMENTS)
			var c := cos(a)
			var s := pow(maxf(-sin(a), 0.0), ROUNDNESS)
			var cx := signf(c) * pow(absf(c), ROUNDNESS)
			# 위는 둥글게, 바닥 가까이(s 작음)는 조금 퍼지게
			pts.append(base + Vector2(cx * rx * (1.0 + SPREAD * (1.0 - s)), -s * ry))
		var body := color.darkened(DEAD_DARKEN) if dead else color
		draw_colored_polygon(pts, body)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, body.darkened(OUTLINE_DARKEN), OUTLINE_W, true)
		# 윗부분 반사광
		draw_circle(base + Vector2(-rx * SHINE_X, -ry * SHINE_Y), rx * SHINE_R, Color(1, 1, 1, SHINE_ALPHA), true, -1.0, true)
		var eye := eye_color
		for sx in [-1.0, 1.0]:
			var e := base + Vector2(rx * EYE_DX * sx, -ry * EYE_Y)
			var er := rx * EYE_R
			if dead:
				draw_line(e + Vector2(-er, -er), e + Vector2(er, er), eye, CROSS_W, true)
				draw_line(e + Vector2(-er, er), e + Vector2(er, -er), eye, CROSS_W, true)
			else:
				draw_circle(e, er, eye, true, -1.0, true)
				draw_circle(e + Vector2(-er * GLINT_OFF, -er * GLINT_OFF), rx * GLINT_R, Color.WHITE, true, -1.0, true)


## 색 점(테두리 있는 원).
class ColorDot:
	extends Control
	var color := Color.WHITE:
		set(v):
			color = v
			queue_redraw()

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r - 0.5, color, true, -1.0, true)
		draw_arc(size * 0.5, r - 0.5, 0.0, TAU, 24, color.darkened(0.5), 1.0, true)


## 가계 단추: "#id" 앞에 계통 색 점. 죽은 개체면 속 빈 점(색은 흐리게).
class RelativeButton:
	extends Button
	var slime_id := -1
	var dot_color := Color.WHITE
	var alive := true
	var dot := 8.0
	var dot_left := 7.0
	## 죽은 친척의 속 빈 점 불투명도(ui.info.dead_dot_alpha), 점 테두리 두께
	var dead_alpha := 0.7
	const RING_W := 1.5
	const RING_SEGS := 20

	func _draw() -> void:
		var r := dot * 0.5
		var c := Vector2(dot_left + r, size.y * 0.5)
		if alive:
			draw_circle(c, r, dot_color, true, -1.0, true)
		else:
			draw_arc(c, r - RING_W * 0.5, 0.0, TAU, RING_SEGS, Color(dot_color, dead_alpha), RING_W, true)
