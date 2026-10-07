class_name LabMain
extends Control
## 실험실 주 화면. 계약: docs/VIEW-API.md "LabMain".
## 위쪽 막대(재생·속도·상태) / 왼쪽 자리 | 지도 관찰 창(SubViewport + MapView) | 개체 정보 창 / 아래 자리.
## 시뮬레이션을 진행(step)하고 사건을 소비(drain_events)하는 것은 화면 가운데 여기뿐이다. 배열에는 쓰지 않는다.

signal ticked(world: SimWorld)
signal events(list: Array)
## 새 실험을 만들었거나 스냅숏을 열어 세계가 바뀌었을 때(4단계 그래프·연대기가 지난 기록을 비움)
signal world_changed(world: SimWorld)

const SEASON_NAMES: Array[String] = ["봄", "여름", "가을", "겨울"]
const NO_SEASON := "계절 없음"
# 지도 위 멈춤 표지 기호(재생·멈춤·빨리 감기 단추는 글꼴 대신 UiTheme.icon 으로 그림 — ⏩ 가 나눔고딕에 없음)
const GLYPH_PAUSE := "‖"
const GLYPH_DISCOVERY := "★"
const USEC_PER_MS := 1000.0
## 실제 배속 창이 이만큼 차기 전에는 "실제 —"(새 실험 직후 0배로 보이지 않게)
const WARMUP_FRACTION := 0.25
# 알림 앞머리(사건 문장이 스스로 설명하므로 발견·오류만 붙임. 사건 kind 는 docs/SIM-API.md)
const TOAST_TAGS := {discovery = "새 발견", error = "오류"}
# 강조 알림(발견·멸종·오류·경고) 테두리의 불투명도
const TOAST_HIGHLIGHT_ALPHA := 0.85
const MAP_HINT := "끌기 이동 · 휠 확대 · 오른쪽 끌기 회전 · 클릭 고르기   │   스페이스 멈춤 · 1~7 속도 · F 따라가기 · Esc 선택 해제"

var world: SimWorld
var map_view: MapView
var info_panel: InfoPanel
var left_dock: VBoxContainer
var bottom_dock: HBoxContainer
## 마지막 advance_frame 의 시뮬레이션 시간(ms)과 예산을 다 써서 밀린 틱을 버렸는지(성능 기록·검사용)
var last_sim_ms := 0.0
var last_budget_hit := false

var _speed := 1
var _paused := false
var _fast := false
var _acc := 0.0
var _selected := -1
var _frame := 0
var _title := ""
# 실제 배속 측정: 최근 프레임의 (시간, 틱 수)
var _hist_dt: Array[float] = []
var _hist_n: Array[int] = []
var _hist_time := 0.0
var _hist_ticks := 0
var _speed_label_wait := 0.0
# 알림: {panel, left(남은 초), kind, text}
var _toasts: Array[Dictionary] = []

# 화면 수치(ui.json, _ready 에서 한 번 읽음)
var _tps := 6.0
var _budget_ms := 10.0
var _ff_budget_ms := 14.0
var _window_s := 1.0
var _max_delta := 0.25
var _steps: Array[int] = []

# 노드
var _top_bar: PanelContainer
var _play_btn: Button
var _speed_btns: Array[Button] = []
var _speed_group := ButtonGroup.new()
var _fast_btn: Button
var _lbl_tick: Label
var _lbl_day: Label
var _lbl_season: Label
var _lbl_daynight: Label
var _lbl_gen: Label
var _lbl_pop: Label
var _lbl_stage: Label
var _lbl_speed: Label
var _left_wrap: PanelContainer
var _bottom_wrap: PanelContainer
var _map_area: Control
var _map_container: SubViewportContainer
var _map_viewport: SubViewport
var _map_title: Label
var _paused_badge: Label
var _toast_box: VBoxContainer


func _ready() -> void:
	_tps = UiConfig.num("speed.ticks_per_second_1x")
	_budget_ms = UiConfig.num("speed.sim_budget_ms")
	_ff_budget_ms = UiConfig.num("speed.fast_forward_budget_ms")
	_window_s = UiConfig.num("speed.actual_speed_window_s")
	_max_delta = UiConfig.num("speed.max_frame_delta_s")
	for v in UiConfig.value("speed.steps", [1]):
		_steps.append(int(v))
	_speed = UiConfig.integer("speed.start_mult")
	theme = UiTheme.build()
	_build_layout()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_min_size(Vector2i(UiConfig.integer("lab.min_width"), UiConfig.integer("lab.min_height")))
	apply_args(OS.get_cmdline_user_args())
	_sync_controls()


func _process(delta: float) -> void:
	advance_frame(delta)


# ════════════════════════════ 실험 ════════════════════════════

## 새 세계를 만들어 붙인다. 성공 "", 실패면 오류 문장(지금 세계는 그대로).
func new_experiment(preset: String, overrides: Dictionary, seed_value: int) -> String:
	var b := SimConfig.build(preset, overrides)
	var err: String = b.error
	if err != "":
		return err
	var w := SimWorld.new()
	err = w.setup(b.config, seed_value)
	if err != "":
		return err
	var label := preset
	var ps := SimConfig.presets()
	if ps.has(preset):
		label = str(ps[preset].get("label", preset))
	_title = "%s · 씨앗 %d" % [label, seed_value]
	if not overrides.is_empty():
		_title += " · 바꾼 값 %d개" % overrides.size()
	_adopt(w)
	return ""


## 스냅숏 파일을 열어 붙인다. 성공 "", 실패면 오류 문장(지금 세계는 그대로). 백업에서 살렸으면 알림.
func open_snapshot(path: String) -> String:
	var r := SimSnapshot.load_file(path)
	var w: SimWorld = r.world
	if w == null:
		var e: String = r.error
		return e if e != "" else "스냅숏을 열 수 없습니다"
	if str(r.status) == "backup":
		show_toast("원본이 깨져 백업에서 열었습니다: %s" % str(r.error), "warn")
	_title = "스냅숏 %s · 씨앗 %d" % [path.get_file(), w.seed_value]
	_adopt(w)
	return ""


## 명령줄 인자(-- 뒤)로 첫 실험을 연다: --seed=N, --preset=이름, --snapshot=경로.
## 잘못된 값은 알림(위험 색)으로 보이고 기본값으로 연다. 오류 문장들을 줄바꿈으로 이어 돌려준다(없으면 "").
## 모르는 인자는 무시한다(검사·캡처 실행기의 --out= 등).
func apply_args(args: PackedStringArray) -> String:
	var def_preset := str(UiConfig.value("lab.default_preset", "default"))
	var def_seed := UiConfig.integer("lab.default_seed")
	var preset := def_preset
	var seed_value := def_seed
	var snapshot := ""
	var errors: Array[String] = []
	for a in args:
		if a.begins_with("--seed="):
			var v := a.substr(7)
			if v.is_valid_int():
				seed_value = v.to_int()
			else:
				errors.append("씨앗은 정수여야 합니다: %s — 기본 씨앗 %d" % [v, def_seed])
		elif a.begins_with("--preset="):
			var p := a.substr(9)
			if SimConfig.preset_names().has(p):
				preset = p
			else:
				errors.append("없는 예설정입니다: %s — 기본 예설정으로 엽니다" % p)
		elif a.begins_with("--snapshot="):
			snapshot = a.substr(11)
	var opened := false
	if snapshot != "":
		var es := open_snapshot(snapshot)
		if es == "":
			opened = true
		else:
			errors.append("스냅숏을 열 수 없습니다(%s): %s — 새 실험으로 엽니다" % [snapshot, es])
	if not opened:
		var e := new_experiment(preset, {}, seed_value)
		if e != "":
			errors.append(e)
			e = new_experiment(def_preset, {}, def_seed)
			if e != "":
				errors.append(e)
	for msg in errors:
		show_toast(msg, "error")
	return "\n".join(errors)


## 세계를 바꿔 끼우고 선택·누적·측정을 처음으로 되돌린다.
func _adopt(w: SimWorld) -> void:
	world = w
	_acc = 0.0
	_frame = 0
	_hist_dt.clear()
	_hist_n.clear()
	_hist_time = 0.0
	_hist_ticks = 0
	_speed_label_wait = 0.0
	map_view.bind(world)
	select_slime(-1)
	_map_title.text = _title
	if is_inside_tree():
		get_window().title = "%s — %s" % [str(ProjectSettings.get_setting("application/config/name", "")), _title]
	_refresh_status(true)
	world_changed.emit(world)


# ════════════════════════════ 속도 ════════════════════════════

## 목표 배속(1배 = speed.ticks_per_second_1x 틱/초). 고르면 빨리 감기는 꺼진다.
func set_speed(mult: int) -> void:
	_speed = maxi(1, mult)
	_fast = false
	_sync_controls()


func set_paused(p: bool) -> void:
	_paused = p
	_sync_controls()


## 빨리 감기: 프레임마다 speed.fast_forward_budget_ms 를 다 써서 진행한다.
func set_fast_forward(on: bool) -> void:
	_fast = on
	_sync_controls()


func is_paused() -> bool:
	return _paused


func is_fast_forward() -> bool:
	return _fast


func target_speed() -> int:
	return _speed


## 최근 speed.actual_speed_window_s 동안 실제로 진행한 배속(프레임 시간 기준).
func actual_speed() -> float:
	if _hist_time <= 0.0 or _tps <= 0.0:
		return 0.0
	return float(_hist_ticks) / _hist_time / _tps


# ════════════════════════════ 선택 ════════════════════════════

## 개체 선택(지도 표시 + 정보 창). -1 또는 없는 id 면 선택 해제.
func select_slime(id: int) -> void:
	if world == null or id < 0 or world.slime_info(id).is_empty():
		id = -1
	_selected = id
	map_view.set_selected(id)
	if id < 0:
		info_panel.clear()
	else:
		info_panel.show_slime(world, id)


func selected_id() -> int:
	return _selected


func _on_slime_requested(id: int) -> void:
	select_slime(id)
	if _selected >= 0:
		map_view.focus_on(id)


func _on_follow_toggled(on: bool) -> void:
	map_view.follow_selected = on


# ════════════════════════════ 진행 ════════════════════════════

## 한 프레임 진행: before_steps → 누적 시간만큼 step(예산 안) → update_view(alpha) → 신호·알림·상태 표시.
## _process 가 부르고, 검사·캡처는 직접 불러 프레임을 결정적으로 몬다. 이 프레임에 돈 틱 수를 돌려준다.
func advance_frame(delta: float) -> int:
	delta = clampf(delta, 0.0, _max_delta)
	_age_toasts(delta)
	if world == null:
		return 0
	map_view.before_steps()
	var n := 0
	last_budget_hit = false
	var t0 := Time.get_ticks_usec()
	if not _paused:
		if _fast:
			# 빨리 감기: 예산을 다 쓸 때까지(적어도 1틱)
			var ff_us := _ff_budget_ms * USEC_PER_MS
			while true:
				world.step()
				n += 1
				if float(Time.get_ticks_usec() - t0) >= ff_us:
					break
			_acc = 0.0
			last_budget_hit = true
		else:
			_acc += delta * _tps * float(_speed)
			var budget_us := _budget_ms * USEC_PER_MS
			while _acc >= 1.0:
				if n > 0 and float(Time.get_ticks_usec() - t0) >= budget_us:
					# 따라가지 못한 몫은 버린다(밀린 틱이 쌓여 점점 더 느려지지 않게). 보간용 소수 부분만 남김
					_acc -= floorf(_acc)
					last_budget_hit = true
					break
				world.step()
				_acc -= 1.0
				n += 1
	last_sim_ms = float(Time.get_ticks_usec() - t0) / USEC_PER_MS
	var alpha := 1.0 if (_fast and not _paused) else clampf(_acc, 0.0, 1.0)
	map_view.update_view(alpha)
	_record_speed(delta, n)
	if n > 0:
		ticked.emit(world)
	var ev := world.drain_events()
	if not ev.is_empty():
		events.emit(ev)
		for e in ev:
			_show_event(e)
	_frame += 1
	var every := maxi(1, UiConfig.integer("info.refresh_frames"))
	if info_panel.current_id() >= 0 and _frame % every == 0:
		info_panel.refresh()
	_speed_label_wait -= delta
	_refresh_status(_speed_label_wait <= 0.0 or _hist_time < _window_s)
	return n


## 실제 배속 창에 이 프레임을 넣고 창보다 오래된 프레임을 뺀다.
func _record_speed(delta: float, n: int) -> void:
	_hist_dt.append(delta)
	_hist_n.append(n)
	_hist_time += delta
	_hist_ticks += n
	while _hist_dt.size() > 1 and _hist_time - _hist_dt[0] >= _window_s:
		_hist_time -= _hist_dt.pop_front()
		_hist_ticks -= _hist_n.pop_front()


# ════════════════════════════ 입력 ════════════════════════════

## 단축키. 글 입력 칸(4단계 씨앗 칸 등)에 초점이 있거나 대화 상자가 떠 있으면 건드리지 않는다.
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	if _text_has_focus() or _dialog_open():
		return
	var code := k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	if _handle_key(code):
		get_viewport().set_input_as_handled()


func _text_has_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## 초점을 가진(또는 배타적인) 창 안 대화 상자·차림표가 떠 있는가(말풍선은 초점이 없어 해당 없음).
func _dialog_open() -> bool:
	for w in get_viewport().get_embedded_subwindows():
		if w.visible and (w.exclusive or w.has_focus()):
			return true
	return false


func _handle_key(code: Key) -> bool:
	match code:
		KEY_SPACE:
			set_paused(not _paused)
			return true
		KEY_ESCAPE:
			select_slime(-1)
			return true
		KEY_F:
			map_view.follow_selected = not map_view.follow_selected
			if map_view.follow_selected and _selected >= 0:
				map_view.focus_on(_selected)
			show_toast("따라가기 켬" if map_view.follow_selected else "따라가기 끔", "info")
			return true
	var idx := -1
	if code >= KEY_1 and code <= KEY_9:
		idx = code - KEY_1
	elif code >= KEY_KP_1 and code <= KEY_KP_9:
		idx = code - KEY_KP_1
	if idx >= 0 and idx < _steps.size():
		set_speed(_steps[idx])
		return true
	return false


# ════════════════════════════ 알림 ════════════════════════════

## 위쪽 가운데 알림(ui.lab.toast_seconds 뒤 사라짐). kind: 사건 종류(discovery·extinction 등) 또는 info·warn·error.
## 왼쪽 띠는 종류 색, 발견은 강조 색·멸종과 오류는 위험 색 테두리. tick >= 0 이면 끝에 흐리게 틱을 붙인다.
func show_toast(text: String, kind: String = "info", tick: int = -1) -> void:
	var col := _kind_color(kind)
	var p := PanelContainer.new()
	p.theme_type_variation = UiTheme.TOAST
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _is_highlight(kind):
		var sb := (theme.get_stylebox("panel", UiTheme.TOAST) as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.border_color = Color(col, TOAST_HIGHLIGHT_ALPHA)
		p.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	p.add_child(row)
	var stripe := ColorRect.new()
	stripe.color = col
	stripe.custom_minimum_size.x = UiConfig.num("lab.toast_stripe_width")
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stripe)
	var tag := str(TOAST_TAGS.get(kind, ""))
	if kind == "discovery" and UiTheme.has_glyphs(GLYPH_DISCOVERY):
		tag = GLYPH_DISCOVERY + " " + tag
	if tag != "":
		var t := Label.new()
		t.text = tag
		t.theme_type_variation = UiTheme.VALUE
		t.add_theme_color_override("font_color", col)
		row.add_child(t)
	var body := Label.new()
	body.text = text
	if _is_highlight(kind):
		body.theme_type_variation = UiTheme.VALUE
	row.add_child(body)
	if tick >= 0:
		var when := Label.new()
		when.text = "틱 " + _commas(tick)
		when.theme_type_variation = UiTheme.DIM
		row.add_child(when)
	_toast_box.add_child(p)
	_toasts.append({panel = p, left = UiConfig.num("lab.toast_seconds"), kind = kind, text = text})
	var cap := maxi(1, UiConfig.integer("lab.toast_max"))
	while _toasts.size() > cap:
		var old: Dictionary = _toasts.pop_front()
		(old.panel as Node).queue_free()


## 지금 보이는 알림 [{kind, text, left}] (검사·캡처용).
func visible_toasts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in _toasts:
		out.append({kind = t.kind, text = t.text, left = t.left})
	return out


func _show_event(e: Dictionary) -> void:
	show_toast(str(e.get("text", "")), str(e.get("kind", "info")), int(e.get("tick", -1)))


func _kind_color(kind: String) -> Color:
	match kind:
		"discovery", "first_farm":
			return UiTheme.color("accent")
		"extinction", "error":
			return UiTheme.color("danger")
		"farm_lost", "warn":
			return UiTheme.color("warn")
	return UiTheme.color("text_dim")


static func _is_highlight(kind: String) -> bool:
	return kind in ["discovery", "extinction", "error", "warn"]


func _age_toasts(delta: float) -> void:
	var fade := maxf(0.001, UiConfig.num("lab.toast_fade_seconds"))
	var k := 0
	while k < _toasts.size():
		var t: Dictionary = _toasts[k]
		t.left = float(t.left) - delta
		var p: PanelContainer = t.panel
		if float(t.left) <= 0.0:
			p.queue_free()
			_toasts.remove_at(k)
			continue
		p.modulate.a = clampf(float(t.left) / fade, 0.0, 1.0)
		k += 1


# ════════════════════════════ 상태 표시 ════════════════════════════

func _refresh_status(with_speed: bool) -> void:
	if world == null or _lbl_tick == null:
		return
	_lbl_tick.text = _commas(world.tick)
	_lbl_day.text = _commas(world.tick / _day_ticks() + 1)
	_lbl_season.text = SEASON_NAMES[world.season] if world.season >= 0 and world.season < SEASON_NAMES.size() else NO_SEASON
	var is_day := world.light >= UiConfig.num("lab.day_light_threshold")
	_lbl_daynight.text = "낮" if is_day else "밤"
	_tint(_lbl_daynight, UiTheme.color("day" if is_day else "night"))
	_lbl_gen.text = "%.1f" % world.mean_generation()
	var pop := world.population()
	_lbl_pop.text = _commas(pop) if pop > 0 else "멸종"
	_tint(_lbl_pop, UiTheme.color("text" if pop > 0 else "danger"))
	var st := clampi(world.stage, 0, SimWorld.STAGE_NAMES.size() - 1)
	_lbl_stage.text = SimWorld.STAGE_NAMES[st]
	_tint(_lbl_stage, UiTheme.color("accent" if st > 0 else "text_dim"))
	if with_speed:
		_speed_label_wait = UiConfig.num("speed.label_refresh_s")
		_lbl_speed.text = speed_text()
		var behind := not _paused and not _fast and _hist_time >= _window_s * 0.5 \
				and actual_speed() < float(_speed) * UiConfig.num("speed.behind_ratio")
		_tint(_lbl_speed, UiTheme.color("warn" if behind else "text"))
	_paused_badge.visible = _paused


## 글자 색을 바뀔 때만 덮어쓴다(같은 색을 매 프레임 다시 넣으면 테마 변경 알림이 돈다).
static func _tint(c: Control, col: Color) -> void:
	if not c.has_theme_color_override("font_color") or c.get_theme_color("font_color") != col:
		c.add_theme_color_override("font_color", col)


## "목표 N배 / 실제 M배"(빨리 감기면 "빨리 감기 / 실제 M배", 멈춤이면 "멈춤 · 목표 N배").
func speed_text() -> String:
	if _paused:
		return "멈춤 · 목표 %d배" % _speed
	var a := actual_speed()
	var actual := (("%.1f" % a) if a < 10.0 else _commas(roundi(a))) + "배"
	if _hist_time < _window_s * WARMUP_FRACTION:
		actual = "—"
	if _fast:
		return "빨리 감기 / 실제 %s" % actual
	return "목표 %d배 / 실제 %s" % [_speed, actual]


## 하루 틱 수(날 표시용). SIM-API 의 질의에 없어 실험 설정(world.cfg)을 읽기만 한다.
func _day_ticks() -> int:
	var t: Variant = world.cfg.get("time")
	if typeof(t) == TYPE_DICTIONARY:
		return maxi(1, int((t as Dictionary).get("day_ticks", 1)))
	return 1


static func _commas(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


## 단추 눌림 상태를 지금 속도·멈춤·빨리 감기에 맞춘다(신호 없이).
func _sync_controls() -> void:
	if _play_btn == null:
		return
	var px := UiConfig.integer("lab.icon_size")
	_play_btn.icon = UiTheme.icon(UiTheme.ICON_PLAY if _paused else UiTheme.ICON_PAUSE, px)
	_play_btn.tooltip_text = ("재생" if _paused else "멈춤") + " (스페이스)"
	_tint_icon(_play_btn, UiTheme.color("warn") if _paused else UiTheme.color("text"))
	for i in _speed_btns.size():
		_speed_btns[i].set_pressed_no_signal(not _fast and _steps[i] == _speed)
	_fast_btn.set_pressed_no_signal(_fast)
	if world != null:
		_refresh_status(true)


# ════════════════════════════ 배치 ════════════════════════════

func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = UiTheme.color("background")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.name = "Column"
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	_top_bar = _build_top_bar()
	col.add_child(_top_bar)

	var mid := HBoxContainer.new()
	mid.name = "Middle"
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	col.add_child(mid)
	_left_wrap = PanelContainer.new()
	_left_wrap.name = "LeftWrap"
	_left_wrap.theme_type_variation = UiTheme.DOCK
	_left_wrap.custom_minimum_size.x = UiConfig.num("lab.left_panel_width")
	_left_wrap.visible = false
	mid.add_child(_left_wrap)
	left_dock = VBoxContainer.new()
	left_dock.name = "LeftDock"
	_left_wrap.add_child(left_dock)

	_map_area = Control.new()
	_map_area.name = "MapArea"
	_map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_area.clip_contents = true
	_map_area.mouse_filter = Control.MOUSE_FILTER_PASS
	mid.add_child(_map_area)
	_map_container = SubViewportContainer.new()
	_map_container.name = "MapContainer"
	_map_container.stretch = true
	_map_container.focus_mode = Control.FOCUS_NONE
	_map_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_area.add_child(_map_container)
	_map_viewport = SubViewport.new()
	_map_viewport.name = "MapViewport"
	_map_viewport.own_world_3d = true
	_map_viewport.msaa_3d = clampi(UiConfig.integer("lab.map_msaa"), 0, 3) as Viewport.MSAA
	_map_container.add_child(_map_viewport)
	map_view = MapView.new()
	map_view.name = "MapView"
	_map_viewport.add_child(map_view)
	_build_map_overlay()

	info_panel = InfoPanel.new()
	info_panel.name = "InfoPanel"
	info_panel.custom_minimum_size.x = UiConfig.num("lab.right_panel_width")
	mid.add_child(info_panel)

	_bottom_wrap = PanelContainer.new()
	_bottom_wrap.name = "BottomWrap"
	_bottom_wrap.theme_type_variation = UiTheme.DOCK
	_bottom_wrap.custom_minimum_size.y = UiConfig.num("lab.bottom_panel_height")
	_bottom_wrap.visible = false
	col.add_child(_bottom_wrap)
	bottom_dock = HBoxContainer.new()
	bottom_dock.name = "BottomDock"
	_bottom_wrap.add_child(bottom_dock)

	# 빈 자리는 숨기고, 4단계가 무언가를 넣으면 보인다
	for dock: Control in [left_dock, bottom_dock]:
		dock.child_entered_tree.connect(func(_n: Node) -> void: _sync_docks.call_deferred())
		dock.child_exiting_tree.connect(func(_n: Node) -> void: _sync_docks.call_deferred())

	map_view.slime_clicked.connect(select_slime)
	info_panel.slime_requested.connect(_on_slime_requested)
	info_panel.follow_toggled.connect(_on_follow_toggled)


func _sync_docks() -> void:
	if not is_instance_valid(left_dock):
		return
	_left_wrap.visible = _live_children(left_dock) > 0
	_bottom_wrap.visible = _live_children(bottom_dock) > 0


static func _live_children(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if not ch.is_queued_for_deletion():
			c += 1
	return c


## 위쪽 막대: [재생] [1배…64배] [빨리 감기] │ 틱·날·계절·낮밤 │ 평균 세대·개체·문명 …… 목표/실제 배속.
## 묶음마다 작은 HBox 로 나눠 간격을 줄인다(최소 창 폭 lab.min_width 안에 가장 긴 표시가 들어가게, 검사).
func _build_top_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.theme_type_variation = UiTheme.TOP_BAR
	bar.custom_minimum_size.y = UiConfig.num("lab.top_bar_min_height")
	var row := _hbox(UiConfig.integer("lab.top_bar_gap"))
	bar.add_child(row)

	_play_btn = _bar_button("", UiConfig.num("lab.play_button_min_width"))
	_play_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_play_btn.pressed.connect(func() -> void: set_paused(not _paused))
	row.add_child(_play_btn)
	var speeds := _hbox(UiConfig.integer("lab.speed_button_gap"))
	row.add_child(speeds)
	for i in _steps.size():
		var m := _steps[i]
		var b := _bar_button("%d배" % m, UiConfig.num("lab.speed_button_min_width"))
		b.toggle_mode = true
		b.button_group = _speed_group
		b.tooltip_text = "%d배 속도 (%d 키)" % [m, i + 1] if i < 9 else "%d배 속도" % m
		b.pressed.connect(set_speed.bind(m))
		_speed_btns.append(b)
		speeds.add_child(b)
	_fast_btn = _bar_button("빨리 감기", 0.0)
	_fast_btn.icon = UiTheme.icon(UiTheme.ICON_FAST, UiConfig.integer("lab.icon_size"))
	_fast_btn.toggle_mode = true
	_fast_btn.tooltip_text = "프레임마다 %.0fms 를 다 써서 최대한 빨리 진행" % _ff_budget_ms
	_fast_btn.toggled.connect(set_fast_forward)
	row.add_child(_fast_btn)

	row.add_child(_vsep())
	var status := _hbox(UiConfig.integer("lab.chip_gap"))
	row.add_child(status)
	_lbl_tick = _chip(status, "틱")
	_lbl_day = _chip(status, "날")
	var sky := _hbox(UiConfig.integer("lab.chip_inner_gap"))
	status.add_child(sky)
	_lbl_season = _value_label(sky)
	_dot(sky)
	_lbl_daynight = _value_label(sky)
	status.add_child(_vsep())
	_lbl_gen = _chip(status, "평균 세대")
	_lbl_pop = _chip(status, "개체")
	_lbl_stage = _chip(status, "문명")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_lbl_speed = _value_label(row)
	_lbl_speed.tooltip_text = "목표 배속과 최근 %.0f초 동안 실제로 낸 배속" % _window_s
	_lbl_speed.mouse_filter = Control.MOUSE_FILTER_PASS
	return bar


## 지도 위 표지: 왼쪽 위 실험 이름·멈춤, 왼쪽 아래 조작 도움말, 위쪽 가운데 알림 묶음.
func _build_map_overlay() -> void:
	var m := UiConfig.num("lab.map_overlay_margin")
	var head := PanelContainer.new()
	head.name = "MapTitle"
	head.theme_type_variation = UiTheme.OVERLAY
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.position = Vector2(m, m)
	_map_area.add_child(head)
	var hrow := HBoxContainer.new()
	hrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hrow)
	_map_title = Label.new()
	_map_title.theme_type_variation = UiTheme.DIM
	hrow.add_child(_map_title)
	_paused_badge = Label.new()
	_paused_badge.theme_type_variation = UiTheme.VALUE
	_paused_badge.text = "%s 멈춤" % UiTheme.glyph_or(GLYPH_PAUSE, "")
	_paused_badge.add_theme_color_override("font_color", UiTheme.color("warn"))
	_paused_badge.visible = false
	hrow.add_child(_paused_badge)

	var hint := PanelContainer.new()
	hint.name = "MapHint"
	hint.theme_type_variation = UiTheme.OVERLAY
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_left = m
	hint.offset_bottom = -m
	hint.offset_top = -m
	_map_area.add_child(hint)
	var hl := Label.new()
	hl.theme_type_variation = UiTheme.DIM
	hl.text = MAP_HINT
	hint.add_child(hl)

	_toast_box = VBoxContainer.new()
	_toast_box.name = "Toasts"
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.anchor_left = 0.5
	_toast_box.anchor_right = 0.5
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.offset_top = UiConfig.num("lab.toast_margin_top")
	_toast_box.offset_bottom = _toast_box.offset_top
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_map_area.add_child(_toast_box)


## 단추 아이콘 색(보통·초점; 올림은 테마대로 흰색).
static func _tint_icon(c: Control, col: Color) -> void:
	for k in ["icon_normal_color", "icon_focus_color"]:
		if not c.has_theme_color_override(k) or c.get_theme_color(k) != col:
			c.add_theme_color_override(k, col)


func _bar_button(text: String, min_w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.x = min_w
	return b


## 흐린 이름 + 굵은 값 한 쌍(작은 HBox). 값 Label 을 돌려준다.
func _chip(parent: HBoxContainer, caption: String) -> Label:
	var box := _hbox(UiConfig.integer("lab.chip_inner_gap"))
	parent.add_child(box)
	var c := Label.new()
	c.text = caption
	c.theme_type_variation = UiTheme.DIM
	box.add_child(c)
	return _value_label(box)


func _value_label(parent: HBoxContainer) -> Label:
	var v := Label.new()
	v.theme_type_variation = UiTheme.VALUE
	parent.add_child(v)
	return v


func _dot(parent: HBoxContainer) -> void:
	var d := Label.new()
	d.text = "·"
	d.theme_type_variation = UiTheme.DIM
	parent.add_child(d)


func _hbox(sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _vsep() -> VSeparator:
	var s := VSeparator.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s
