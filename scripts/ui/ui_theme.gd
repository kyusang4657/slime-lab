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
			polys.append(PackedVector2Array([Vector2(a + 0.06, a), Vector2(1.0 - a + 0.06, 0.5), Vector2(a + 0.06, 1.0 - a)]))
		ICON_PAUSE:
			var x0 := 0.5 - ICON_PAUSE_GAP * 0.5 - ICON_PAUSE_BAR
			var x1 := 0.5 + ICON_PAUSE_GAP * 0.5
			for x in [x0, x1]:
				polys.append(PackedVector2Array([Vector2(x, 0.12), Vector2(x + ICON_PAUSE_BAR, 0.12), Vector2(x + ICON_PAUSE_BAR, 0.88), Vector2(x, 0.88)]))
		ICON_FAST:
			for x in [0.5 - ICON_FAST_W, 0.5]:
				polys.append(PackedVector2Array([Vector2(x + 0.04, 0.2), Vector2(x + ICON_FAST_W + 0.04, 0.5), Vector2(x + 0.04, 0.8)]))
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
	th.set_stylebox("panel", CARD, box(color("background"), border, bw, rad, pad * 0.8, pad * 0.6))
	th.set_type_variation(OVERLAY, "PanelContainer")
	th.set_stylebox("panel", OVERLAY, box(color("overlay"), Color(0, 0, 0, 0), 0, rad, pad * 0.8, pad * 0.4))
	th.set_type_variation(TOAST, "PanelContainer")
	th.set_stylebox("panel", TOAST, box(color("toast"), border, bw, rad, pad * 1.4, pad * 0.7))
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
	var b_hover := box(color("button_hover"), dim.darkened(0.35), bw, rad, bph, bpv)
	var b_pressed := box(color("button_pressed"), accent, bw, rad, bph, bpv)
	var b_disabled := box(color("button_disabled"), color("button_disabled"), bw, rad, bph, bpv)
	var b_focus := box(Color(0, 0, 0, 0), Color(accent, 0.55), bw, rad, bph, bpv)
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
		th.set_color("font_hover_pressed_color", t, accent.lightened(0.3))
		th.set_color("font_disabled_color", t, Color(dim, 0.45))
		th.set_color("icon_normal_color", t, text)
		th.set_color("icon_hover_color", t, Color.WHITE)
		th.set_color("icon_focus_color", t, text)
		th.set_color("icon_pressed_color", t, accent)
		th.set_color("icon_hover_pressed_color", t, accent.lightened(0.3))
		th.set_color("icon_disabled_color", t, Color(dim, 0.45))
	for k in ["normal_mirrored", "hover_mirrored", "pressed_mirrored", "disabled_mirrored"]:
		th.set_stylebox(k, "OptionButton", th.get_stylebox(k.trim_suffix("_mirrored"), "OptionButton"))
	th.set_type_variation(ACCENT_BUTTON, "Button")
	th.set_stylebox("normal", ACCENT_BUTTON, box(accent.darkened(0.25), accent, bw, rad, bph, bpv))
	th.set_stylebox("hover", ACCENT_BUTTON, box(accent.darkened(0.1), accent.lightened(0.3), bw, rad, bph, bpv))
	th.set_stylebox("pressed", ACCENT_BUTTON, box(accent.darkened(0.4), accent, bw, rad, bph, bpv))
	th.set_font("font", ACCENT_BUTTON, bold_font())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		th.set_color(k, ACCENT_BUTTON, color("background"))
	th.set_type_variation(FLAT_BUTTON, "Button")
	var flat := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, rad, bph * 0.6, bpv * 0.6)
	th.set_stylebox("normal", FLAT_BUTTON, flat)
	th.set_stylebox("hover", FLAT_BUTTON, box(color("button_hover"), Color(0, 0, 0, 0), 0, rad, bph * 0.6, bpv * 0.6))
	th.set_stylebox("pressed", FLAT_BUTTON, box(color("button_pressed"), Color(0, 0, 0, 0), 0, rad, bph * 0.6, bpv * 0.6))
	th.set_stylebox("focus", FLAT_BUTTON, StyleBoxEmpty.new())
	for t in ["CheckBox", "CheckButton"]:
		th.set_color("font_color", t, text)
		th.set_color("font_hover_color", t, Color.WHITE)
		th.set_color("font_pressed_color", t, text)
		th.set_color("font_hover_pressed_color", t, Color.WHITE)
		th.set_color("font_focus_color", t, text)
		th.set_color("font_disabled_color", t, Color(dim, 0.45))
		th.set_stylebox("focus", t, StyleBoxEmpty.new())

	# ── 막대·입력 ──
	th.set_stylebox("background", "ProgressBar", box(field, border, bw, rad, 0.0, 0.0))
	th.set_stylebox("fill", "ProgressBar", box(accent.darkened(0.15), Color(0, 0, 0, 0), 0, rad, 0.0, 0.0))
	th.set_color("font_color", "ProgressBar", text)
	th.set_font_size("font_size", "ProgressBar", fs_small)
	th.set_stylebox("normal", "LineEdit", box(field, border, bw, rad, bph * 0.8, bpv))
	var le_focus := box(Color(0, 0, 0, 0), accent, bw, rad, bph * 0.8, bpv)
	le_focus.draw_center = false
	th.set_stylebox("focus", "LineEdit", le_focus)
	th.set_stylebox("read_only", "LineEdit", box(color("button_disabled"), border, bw, rad, bph * 0.8, bpv))
	th.set_color("font_color", "LineEdit", text)
	th.set_color("font_uneditable_color", "LineEdit", dim)
	th.set_color("font_placeholder_color", "LineEdit", Color(dim, 0.6))
	th.set_color("caret_color", "LineEdit", accent)
	th.set_color("selection_color", "LineEdit", Color(accent, 0.35))
	var slider := box(field, border, bw, rad, 0.0, 3.0)
	th.set_stylebox("slider", "HSlider", slider)
	th.set_stylebox("grabber_area", "HSlider", box(accent.darkened(0.2), Color(0, 0, 0, 0), 0, rad, 0.0, 3.0))
	th.set_stylebox("grabber_area_highlight", "HSlider", box(accent, Color(0, 0, 0, 0), 0, rad, 0.0, 3.0))
	for t in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", t, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, rad, 3.0, 3.0))
		th.set_stylebox("grabber", t, box(color("button_border"), Color(0, 0, 0, 0), 0, rad, 3.0, 3.0))
		th.set_stylebox("grabber_highlight", t, box(dim.darkened(0.3), Color(0, 0, 0, 0), 0, rad, 3.0, 3.0))
		th.set_stylebox("grabber_pressed", t, box(accent.darkened(0.3), Color(0, 0, 0, 0), 0, rad, 3.0, 3.0))

	# ── 목록·말풍선·차림표 ──
	th.set_stylebox("panel", "ItemList", box(field, border, bw, rad, pad * 0.5, pad * 0.5))
	th.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	th.set_stylebox("hovered", "ItemList", box(color("button_hover"), Color(0, 0, 0, 0), 0, rad, 4.0, 2.0))
	th.set_stylebox("selected", "ItemList", box(color("button_pressed"), Color(0, 0, 0, 0), 0, rad, 4.0, 2.0))
	th.set_stylebox("selected_focus", "ItemList", box(color("button_pressed"), accent, bw, rad, 4.0, 2.0))
	th.set_color("font_color", "ItemList", text)
	th.set_color("font_selected_color", "ItemList", accent)
	th.set_color("font_hovered_color", "ItemList", Color.WHITE)
	th.set_stylebox("panel", "TooltipPanel", box(color("topbar"), border, bw, rad, pad * 0.8, pad * 0.5))
	th.set_color("font_color", "TooltipLabel", text)
	th.set_font_size("font_size", "TooltipLabel", fs_small)
	th.set_stylebox("panel", "PopupMenu", box(color("topbar"), border, bw, rad, pad * 0.4, pad * 0.4))
	th.set_stylebox("hover", "PopupMenu", box(color("button_hover"), Color(0, 0, 0, 0), 0, rad, 4.0, 2.0))
	th.set_color("font_color", "PopupMenu", text)
	th.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	th.set_color("font_disabled_color", "PopupMenu", Color(dim, 0.45))
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
