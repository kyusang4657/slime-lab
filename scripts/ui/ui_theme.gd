class_name UiTheme
extends RefCounted
## 실험실 공용 테마. config/ui.json 의 "theme"(색·모서리·여백)과 "lab"(글자 크기)에서 코드로 만든다.
## 글꼴은 나눔고딕 보통·굵게(assets/fonts, OFL). 외부 그림 없이 StyleBoxFlat 만 쓴다.
## 다른 구성 요소는 theme_type_variation 에 아래 형 변형 이름을 넣어 같은 모양을 쓴다(docs/VIEW-API.md "UiTheme").

const FONT_REGULAR := "res://assets/fonts/NanumGothic-Regular.ttf"
const FONT_BOLD := "res://assets/fonts/NanumGothic-Bold.ttf"

# 형 변형(type variation) 이름
const TITLE := "TitleLabel"        # 굵은 제목(font_size_title)
const DIM := "DimLabel"            # 흐린 작은 글씨(설명·단위)
const VALUE := "ValueLabel"        # 굵은 값(상태 표시)
const TOP_BAR := "TopBar"          # 위쪽 막대 바탕
const DOCK := "DockPanel"          # 왼쪽·아래 자리 바탕
const CARD := "CardPanel"          # 패널 안의 한 단 어두운 묶음
const OVERLAY := "OverlayPanel"    # 지도 위 반투명 표지
const TOAST := "ToastPanel"        # 위쪽 알림
const ACCENT_BUTTON := "AccentButton"  # 주요 동작(새 실험 등)
const FLAT_BUTTON := "FlatButton"  # 테두리 없는 목록 단추(가계 항목 등)

# 아이콘 모양(icon() 의 이름)
const ICON_PLAY := "play"
const ICON_PAUSE := "pause"
const ICON_FAST := "fast"
# 아이콘 기하(한 변 1 기준): 재생 삼각형 여백, 멈춤 막대 폭·간격, 빨리 감기 삼각형 폭
const ICON_PLAY_INSET := 0.14
const ICON_PAUSE_BAR := 0.22
const ICON_PAUSE_GAP := 0.16
const ICON_FAST_W := 0.42
# 삼각형을 오른쪽으로 미는 양(눈으로 본 무게 중심 맞춤), 멈춤 막대 위 끝(아래 끝 = 1 − 이 값), 빨리 감기 삼각형 위 끝
const ICON_TRI_SHIFT := 0.06
const ICON_BAR_TOP := 0.12
const ICON_FAST_TOP := 0.2
const ICON_FAST_SHIFT := 0.04

# 여백 비(theme.panel_padding·button_padding_* 에 곱함): 카드·지도 위 표지·알림·목록 단추·입력 칸
const CARD_PAD_H := 0.8
const CARD_PAD_V := 0.6
const OVERLAY_PAD_V := 0.4
const TOAST_PAD_H := 1.4
const TOAST_PAD_V := 0.7
const FLAT_PAD := 0.6
const FIELD_PAD_H := 0.8
const LIST_PAD := 0.5
const MENU_PAD := 0.4
# 작은 고정 여백(픽셀): 스크롤 막대·슬라이더 안쪽, 목록 항목 가로·세로
const BAR_INSET := 3.0
const ITEM_PAD_H := 4.0
const ITEM_PAD_V := 2.0
# 색 변형: 올림 테두리 어둡게, 강조색 밝게(눌림 올림), 강조 단추 어둡게(보통·올림·눌림), 막대 채움·스크롤 손잡이 어둡게
const HOVER_BORDER_DARKEN := 0.35
const ACCENT_LIGHTEN := 0.3
const ACCENT_BTN_DARKEN := 0.25
const ACCENT_BTN_HOVER_DARKEN := 0.1
const ACCENT_BTN_PRESS_DARKEN := 0.4
const FILL_DARKEN := 0.15
const GRAB_DARKEN := 0.3
const SLIDER_DARKEN := 0.2

# 같은 테마를 한 번만 만든다(색이 바뀌면 reset())
static var _theme: Theme
static var _regular: Font
static var _bold: Font
static var _icons: Dictionary = {}


## 공용 테마(캐시). 실험실 뿌리에 붙이면 자식 Control 전부가 이어받는다.
static func build() -> Theme:
	if _theme == null:
		_theme = _make()
	return _theme


## 다음 build() 가 ui.json 을 다시 읽어 새로 만들게 한다.
static func reset() -> void:
	_theme = null


static func regular_font() -> Font:
	if _regular == null:
		_regular = load(FONT_REGULAR)
	return _regular


static func bold_font() -> Font:
	if _bold == null:
		_bold = load(FONT_BOLD)
	return _bold


## "theme" 절의 색(예: color("accent")).
static func color(key: String) -> Color:
	return UiConfig.color("theme." + key)


## 낱말 잇개(U+2060, 폭 0 — 그 자리에서 줄을 바꾸지 않음)
const WORD_JOINER := "\u2060"


## 한국어 낱말 단위 줄바꿈(keep-all, 통합 때 더함): Godot 의 ICU 줄바꿈은 한글 음절 사이("발/견")에서도 끊으므로
## 빈칸이 아닌 글자 사이마다 낱말 잇개를 넣어 빈칸에서만 줄이 바뀌게 한다. 폭은 그대로(검사). 한 낱말이 줄보다 길면
## AUTOWRAP_WORD_SMART 가 글자 단위로 끊는다. 읽어 견줄 글자는 plain_text() 로 되돌린다.
static func keep_words(text: String) -> String:
	var out := PackedStringArray()
	var n := text.length()
	for i in n:
		var c := text[i]
		out.append(c)
		if i + 1 < n and not _is_break_space(c) and not _is_break_space(text[i + 1]):
			out.append(WORD_JOINER)
	return "".join(out)


## keep_words 로 넣은 낱말 잇개를 뺀 글자
static func plain_text(text: String) -> String:
	return text.replace(WORD_JOINER, "")


static func _is_break_space(c: String) -> bool:
	return c == " " or c == "\n" or c == "\t"


## 글자가 모두 기본 글꼴에 있으면 true(없는 기호 대신 한국어 글자를 쓰려고 확인).
static func has_glyphs(text: String) -> bool:
	var f := regular_font()
	if f == null:
		return false
	for i in text.length():
		if not f.has_char(text.unicode_at(i)):
			return false
	return true


## 기호가 글꼴에 있으면 기호, 없으면 대신 글자.
static func glyph_or(glyph: String, fallback: String) -> String:
	return glyph if has_glyphs(glyph) else fallback


## 단추용 흰 아이콘(재생·멈춤·빨리 감기). 글꼴에 없는 기호 대신 코드로 그린다(테마의 icon_*_color 가 색을 입힘).
## 볼록 다각형의 변까지 부호 거리로 가장자리를 부드럽게 칠한다(이전 프로젝트 ui_skin.gd 의 _sd 칠하기와 같은 방식).
static func icon(shape: String, px: int) -> Texture2D:
	var key := "%s:%d" % [shape, px]
	if _icons.has(key):
		return _icons[key]
	var polys: Array[PackedVector2Array] = []
	match shape:
		ICON_PLAY:
			var a := ICON_PLAY_INSET
			polys.append(PackedVector2Array([Vector2(a + ICON_TRI_SHIFT, a), Vector2(1.0 - a + ICON_TRI_SHIFT, 0.5), Vector2(a + ICON_TRI_SHIFT, 1.0 - a)]))
		ICON_PAUSE:
			var x0 := 0.5 - ICON_PAUSE_GAP * 0.5 - ICON_PAUSE_BAR
			var x1 := 0.5 + ICON_PAUSE_GAP * 0.5
			for x in [x0, x1]:
				polys.append(PackedVector2Array([Vector2(x, ICON_BAR_TOP), Vector2(x + ICON_PAUSE_BAR, ICON_BAR_TOP),
						Vector2(x + ICON_PAUSE_BAR, 1.0 - ICON_BAR_TOP), Vector2(x, 1.0 - ICON_BAR_TOP)]))
		ICON_FAST:
			for x in [0.5 - ICON_FAST_W, 0.5]:
				polys.append(PackedVector2Array([Vector2(x + ICON_FAST_SHIFT, ICON_FAST_TOP), Vector2(x + ICON_FAST_W + ICON_FAST_SHIFT, 0.5),
						Vector2(x + ICON_FAST_SHIFT, 1.0 - ICON_FAST_TOP)]))
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in px:
		for x in px:
			var p := Vector2((float(x) + 0.5) / float(px), (float(y) + 0.5) / float(px))
			var a := 0.0
			for poly in polys:
				a = maxf(a, clampf(0.5 - _poly_sd(p, poly) * float(px), 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


## 볼록 다각형(시계 방향, 화면 좌표)까지의 부호 거리 근사(안쪽 음수): 각 변 바깥 법선 방향 거리의 최댓값.
static func _poly_sd(p: Vector2, poly: PackedVector2Array) -> float:
	var d := -INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		var n := Vector2(e.y, -e.x)  # 화면 좌표(y 아래)·시계 방향이면 바깥쪽
		d = maxf(d, (p - a).dot(n))
	return d


## 납작한 상자 모양. border_w 는 네 변 공통, radius < 0 이면 theme.corner_radius, pad < 0 이면 theme.panel_padding.
static func box(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = -1, pad_h: float = -1.0, pad_v: float = -1.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(UiConfig.integer("theme.corner_radius") if radius < 0 else radius)
	var ph := UiConfig.num("theme.panel_padding") if pad_h < 0.0 else pad_h
	var pv := UiConfig.num("theme.panel_padding") if pad_v < 0.0 else pad_v
	s.content_margin_left = ph
	s.content_margin_right = ph
	s.content_margin_top = pv
	s.content_margin_bottom = pv
	s.anti_aliasing = true
	return s


static func _make() -> Theme:
	var th := Theme.new()
	var fs := UiConfig.integer("lab.font_size")
	var fs_small := UiConfig.integer("lab.font_size_small")
	var fs_title := UiConfig.integer("lab.font_size_title")
	var bw := UiConfig.integer("theme.border_width")
	var rad := UiConfig.integer("theme.corner_radius")
	var pad := UiConfig.num("theme.panel_padding")
	var bph := UiConfig.num("theme.button_padding_h")
	var bpv := UiConfig.num("theme.button_padding_v")
	var sep := UiConfig.integer("theme.separation")
	var text := color("text")
	var dim := color("text_dim")
	var accent := color("accent")
	var panel := color("panel")
	var border := color("panel_border")
	var field := color("field")
	var a_disabled := UiConfig.num("theme.disabled_alpha")
	var a_focus := UiConfig.num("theme.focus_alpha")
	var a_select := UiConfig.num("theme.selection_alpha")
	var a_placeholder := UiConfig.num("theme.placeholder_alpha")

	th.default_font = regular_font()
	th.default_font_size = fs

	# ── 글씨 ──
	th.set_color("font_color", "Label", text)
	th.set_type_variation(TITLE, "Label")
	th.set_font("font", TITLE, bold_font())
	th.set_font_size("font_size", TITLE, fs_title)
	th.set_type_variation(DIM, "Label")
	th.set_color("font_color", DIM, dim)
	th.set_font_size("font_size", DIM, fs_small)
	th.set_type_variation(VALUE, "Label")
	th.set_font("font", VALUE, bold_font())
	th.set_color("font_color", VALUE, text)
	th.set_color("default_color", "RichTextLabel", text)
	th.set_font("normal_font", "RichTextLabel", regular_font())
	th.set_font("bold_font", "RichTextLabel", bold_font())
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		th.set_font_size(k, "RichTextLabel", fs)

	# ── 바탕 ──
	var side := box(panel, border, 0, 0, pad, pad)
	th.set_stylebox("panel", "PanelContainer", side)
	th.set_stylebox("panel", "Panel", box(panel, border, 0, 0))
	th.set_type_variation(DOCK, "PanelContainer")
	th.set_stylebox("panel", DOCK, box(panel, border, 0, 0, pad, pad))
	th.set_type_variation(TOP_BAR, "PanelContainer")
	var top := box(color("topbar"), border, 0, 0, pad, bpv)
	top.border_width_bottom = bw
	th.set_stylebox("panel", TOP_BAR, top)
	th.set_type_variation(CARD, "PanelContainer")
	th.set_stylebox("panel", CARD, box(color("background"), border, bw, rad, pad * CARD_PAD_H, pad * CARD_PAD_V))
	th.set_type_variation(OVERLAY, "PanelContainer")
	th.set_stylebox("panel", OVERLAY, box(color("overlay"), Color(0, 0, 0, 0), 0, rad, pad * CARD_PAD_H, pad * OVERLAY_PAD_V))
	th.set_type_variation(TOAST, "PanelContainer")
	th.set_stylebox("panel", TOAST, box(color("toast"), border, bw, rad, pad * TOAST_PAD_H, pad * TOAST_PAD_V))
	th.set_constant("separation", "HBoxContainer", sep)
	th.set_constant("separation", "VBoxContainer", sep)
	th.set_constant("h_separation", "GridContainer", sep)
	th.set_constant("v_separation", "GridContainer", sep)
	var line := StyleBoxLine.new()
	line.color = border
	line.thickness = maxi(1, bw)
	th.set_stylebox("separator", "HSeparator", line)
	th.set_constant("separation", "HSeparator", sep * 2)
	var vline := StyleBoxLine.new()
	vline.color = border
	vline.thickness = maxi(1, bw)
	vline.vertical = true
	th.set_stylebox("separator", "VSeparator", vline)
	th.set_constant("separation", "VSeparator", sep * 2)

	# ── 단추: 보통·올림·눌림(켜짐)·못 씀·초점 ──
	var b_normal := box(color("button"), color("button_border"), bw, rad, bph, bpv)
	var b_hover := box(color("button_hover"), dim.darkened(HOVER_BORDER_DARKEN), bw, rad, bph, bpv)
	var b_pressed := box(color("button_pressed"), accent, bw, rad, bph, bpv)
	var b_disabled := box(color("button_disabled"), color("button_disabled"), bw, rad, bph, bpv)
	var b_focus := box(Color(0, 0, 0, 0), Color(accent, a_focus), bw, rad, bph, bpv)
	b_focus.draw_center = false
	for t in ["Button", "OptionButton", "MenuButton"]:
		th.set_stylebox("normal", t, b_normal)
		th.set_stylebox("hover", t, b_hover)
		th.set_stylebox("pressed", t, b_pressed)
		th.set_stylebox("disabled", t, b_disabled)
		th.set_stylebox("focus", t, b_focus)
		th.set_color("font_color", t, text)
		th.set_color("font_hover_color", t, Color.WHITE)
		th.set_color("font_focus_color", t, text)
		th.set_color("font_pressed_color", t, accent)
		th.set_color("font_hover_pressed_color", t, accent.lightened(ACCENT_LIGHTEN))
		th.set_color("font_disabled_color", t, Color(dim, a_disabled))
		th.set_color("icon_normal_color", t, text)
		th.set_color("icon_hover_color", t, Color.WHITE)
		th.set_color("icon_focus_color", t, text)
		th.set_color("icon_pressed_color", t, accent)
		th.set_color("icon_hover_pressed_color", t, accent.lightened(ACCENT_LIGHTEN))
		th.set_color("icon_disabled_color", t, Color(dim, a_disabled))
	for k in ["normal_mirrored", "hover_mirrored", "pressed_mirrored", "disabled_mirrored"]:
		th.set_stylebox(k, "OptionButton", th.get_stylebox(k.trim_suffix("_mirrored"), "OptionButton"))
	th.set_type_variation(ACCENT_BUTTON, "Button")
	th.set_stylebox("normal", ACCENT_BUTTON, box(accent.darkened(ACCENT_BTN_DARKEN), accent, bw, rad, bph, bpv))
	th.set_stylebox("hover", ACCENT_BUTTON, box(accent.darkened(ACCENT_BTN_HOVER_DARKEN), accent.lightened(ACCENT_LIGHTEN), bw, rad, bph, bpv))
	th.set_stylebox("pressed", ACCENT_BUTTON, box(accent.darkened(ACCENT_BTN_PRESS_DARKEN), accent, bw, rad, bph, bpv))
	th.set_font("font", ACCENT_BUTTON, bold_font())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		th.set_color(k, ACCENT_BUTTON, color("background"))
	th.set_type_variation(FLAT_BUTTON, "Button")
	var flat := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, rad, bph * FLAT_PAD, bpv * FLAT_PAD)
	th.set_stylebox("normal", FLAT_BUTTON, flat)
	th.set_stylebox("hover", FLAT_BUTTON, box(color("button_hover"), Color(0, 0, 0, 0), 0, rad, bph * FLAT_PAD, bpv * FLAT_PAD))
	th.set_stylebox("pressed", FLAT_BUTTON, box(color("button_pressed"), Color(0, 0, 0, 0), 0, rad, bph * FLAT_PAD, bpv * FLAT_PAD))
	th.set_stylebox("focus", FLAT_BUTTON, StyleBoxEmpty.new())
	for t in ["CheckBox", "CheckButton"]:
		th.set_color("font_color", t, text)
		th.set_color("font_hover_color", t, Color.WHITE)
		th.set_color("font_pressed_color", t, text)
		th.set_color("font_hover_pressed_color", t, Color.WHITE)
		th.set_color("font_focus_color", t, text)
		th.set_color("font_disabled_color", t, Color(dim, a_disabled))
		th.set_stylebox("focus", t, StyleBoxEmpty.new())

	# ── 막대·입력 ──
	th.set_stylebox("background", "ProgressBar", box(field, border, bw, rad, 0.0, 0.0))
	th.set_stylebox("fill", "ProgressBar", box(accent.darkened(FILL_DARKEN), Color(0, 0, 0, 0), 0, rad, 0.0, 0.0))
	th.set_color("font_color", "ProgressBar", text)
	th.set_font_size("font_size", "ProgressBar", fs_small)
	th.set_stylebox("normal", "LineEdit", box(field, border, bw, rad, bph * FIELD_PAD_H, bpv))
	var le_focus := box(Color(0, 0, 0, 0), accent, bw, rad, bph * FIELD_PAD_H, bpv)
	le_focus.draw_center = false
	th.set_stylebox("focus", "LineEdit", le_focus)
	th.set_stylebox("read_only", "LineEdit", box(color("button_disabled"), border, bw, rad, bph * FIELD_PAD_H, bpv))
	th.set_color("font_color", "LineEdit", text)
	th.set_color("font_uneditable_color", "LineEdit", dim)
	th.set_color("font_placeholder_color", "LineEdit", Color(dim, a_placeholder))
	th.set_color("caret_color", "LineEdit", accent)
	th.set_color("selection_color", "LineEdit", Color(accent, a_select))
	var slider := box(field, border, bw, rad, 0.0, BAR_INSET)
	th.set_stylebox("slider", "HSlider", slider)
	th.set_stylebox("grabber_area", "HSlider", box(accent.darkened(SLIDER_DARKEN), Color(0, 0, 0, 0), 0, rad, 0.0, BAR_INSET))
	th.set_stylebox("grabber_area_highlight", "HSlider", box(accent, Color(0, 0, 0, 0), 0, rad, 0.0, BAR_INSET))
	for t in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", t, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, rad, BAR_INSET, BAR_INSET))
		th.set_stylebox("grabber", t, box(color("button_border"), Color(0, 0, 0, 0), 0, rad, BAR_INSET, BAR_INSET))
		th.set_stylebox("grabber_highlight", t, box(dim.darkened(GRAB_DARKEN), Color(0, 0, 0, 0), 0, rad, BAR_INSET, BAR_INSET))
		th.set_stylebox("grabber_pressed", t, box(accent.darkened(GRAB_DARKEN), Color(0, 0, 0, 0), 0, rad, BAR_INSET, BAR_INSET))

	# ── 목록·말풍선·차림표 ──
	th.set_stylebox("panel", "ItemList", box(field, border, bw, rad, pad * LIST_PAD, pad * LIST_PAD))
	th.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	th.set_stylebox("hovered", "ItemList", box(color("button_hover"), Color(0, 0, 0, 0), 0, rad, ITEM_PAD_H, ITEM_PAD_V))
	th.set_stylebox("selected", "ItemList", box(color("button_pressed"), Color(0, 0, 0, 0), 0, rad, ITEM_PAD_H, ITEM_PAD_V))
	th.set_stylebox("selected_focus", "ItemList", box(color("button_pressed"), accent, bw, rad, ITEM_PAD_H, ITEM_PAD_V))
	th.set_color("font_color", "ItemList", text)
	th.set_color("font_selected_color", "ItemList", accent)
	th.set_color("font_hovered_color", "ItemList", Color.WHITE)
	th.set_stylebox("panel", "TooltipPanel", box(color("topbar"), border, bw, rad, pad * CARD_PAD_H, pad * LIST_PAD))
	th.set_color("font_color", "TooltipLabel", text)
	th.set_font_size("font_size", "TooltipLabel", fs_small)
	th.set_stylebox("panel", "PopupMenu", box(color("topbar"), border, bw, rad, pad * MENU_PAD, pad * MENU_PAD))
	th.set_stylebox("hover", "PopupMenu", box(color("button_hover"), Color(0, 0, 0, 0), 0, rad, ITEM_PAD_H, ITEM_PAD_V))
	th.set_color("font_color", "PopupMenu", text)
	th.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	th.set_color("font_disabled_color", "PopupMenu", Color(dim, a_disabled))
	th.set_stylebox("panel", "TabContainer", box(panel, border, bw, 0, pad, pad))
	var tab_sel := box(panel, accent, 0, rad, bph, bpv)
	tab_sel.border_width_top = maxi(2, bw * 2)
	th.set_stylebox("tab_selected", "TabContainer", tab_sel)
	th.set_stylebox("tab_unselected", "TabContainer", box(color("background"), Color(0, 0, 0, 0), 0, rad, bph, bpv))
	th.set_stylebox("tab_hovered", "TabContainer", box(color("button_hover"), Color(0, 0, 0, 0), 0, rad, bph, bpv))
	th.set_color("font_selected_color", "TabContainer", text)
	th.set_color("font_unselected_color", "TabContainer", dim)
	th.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	return th
