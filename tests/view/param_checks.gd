extends RefCounted
## ParamPanel 검사: 기본값 = 기본 예설정, 예설정 바꾸기 → 세 칸, set_value + apply → 새 실험의 cfg, 잘못된 값 → 칸 아래 오류·
## 지금 실험 그대로, 되돌리기, 씨앗 범위·무작위(전역 난수·세계 그대로), 글 칸 입력 중 단축키 무시, 내보내기·스냅숏(대화 상자),
## 소리 확인 상자, 1280×720 왼쪽 자리 폭 안(가로 넘침 없음)·주요 단추가 화면 안(고정 바닥), 비교 모드(진짜 실험실: 나란히
## 시작 → 실험 둘, 끄면 A 칸의 고친 값 유지), 입력 중인 칸 + 단추(A/B·되돌리기·예설정·새 실험) → 값이 제자리에·초점 풀림,
## 해석 못 한 글자 + 새 실험 → 시작 안 함, 범위 밖 씨앗의 실험, 오래 돈 실험을 버리는 단추 → 확인 대화 상자, 고급 설정
## 한국어 이름표·말풍선, 실수 글자 = JSON 글자, 슬라이더 한 번의 갱신 몫(견준 수·말풍선 수).
## 비교 시작 인자는 start_compare·stop_compare 를 가로채는 가짜 실험실(FakeLab)로도 확인한다(패널 단위 — 종단은 integration4_checks).

const MIN_CHECKS := 180
const TMP_DIR := "user://test_param"
const SNAP_PATH := "user://test_param/snap.json"
const MAIN_KEYS: Array[String] = ["mutation.rate", "resources.scale", "population.initial"]


## start_compare·stop_compare 호출을 기록만 하는 실험실(나머지는 진짜 LabMain).
class FakeLab extends LabMain:
	const FAKE_ERR := "가짜 실험실: 비교 인자만 기록함"
	var compare_calls: Array = []
	var stop_calls := 0

	func start_compare(a: Dictionary, b: Dictionary) -> String:
		compare_calls.append([a.duplicate(true), b.duplicate(true)])
		return FAKE_ERR

	func stop_compare() -> void:
		stop_calls += 1

	## 내보내기 단추 검사: 공용 user://experiments 대신 임시 폴더
	var export_dir := ""

	func default_export_dir() -> String:
		return export_dir if export_dir != "" else super()


func run(t) -> void:
	var root_size: Vector2i = t.root.size
	t.root.size = Vector2i(UiConfig.integer("lab.min_width"), UiConfig.integer("lab.min_height"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(2)
	lab.set_process(false)
	var p := _attach(lab)
	await t.frames(3)
	_defaults(t, lab, p)
	_presets(t, p)
	await _layout(t, lab, p)
	_apply(t, lab, p)
	_invalid(t, lab, p)
	_revert(t, lab, p)
	_seed(t, lab, p)
	await _typing(t, lab, p)
	await _pending_edits(t, lab, p)
	await _bad_text(t, lab, p)
	_labels(t, p)
	_float_text(t, p)
	_refresh_cost(t, lab, p)
	await _export(t, lab, p)
	await _snapshot(t, lab, p)
	await _sound(t, lab, p)
	await _seed_range(t, lab, p)
	await _real_compare(t, lab, p)
	await _confirm(t, lab, p)
	lab.queue_free()
	await t.frames(2)
	await _fake_lab(t)
	_clean_dir(ProjectSettings.globalize_path(TMP_DIR))
	t.root.size = root_size


## 실험실에 이미 붙은 패널(통합 뒤 LabMain 이 붙임)이 있으면 그것, 없으면 새로 붙인다.
func _attach(lab: LabMain) -> ParamPanel:
	for ch in lab.left_dock.get_children():
		if ch is ParamPanel:
			return ch as ParamPanel
	var p := ParamPanel.new()
	lab.left_dock.add_child(p)
	p.bind_lab(lab)
	return p


func _cfg(cfg: Dictionary, key: String) -> Variant:
	return SimConfig.get_value(cfg, key)


func _defaults(t, lab: LabMain, p: ParamPanel) -> void:
	var def := str(UiConfig.value("lab.default_preset"))
	var dseed := UiConfig.integer("lab.default_seed")
	var s := p.current_settings(0)
	t.check(str(s.preset) == def and (s.overrides as Dictionary).is_empty() and int(s.seed) == dseed, "처음 값 = 기본 예설정·씨앗: %s" % str(s))
	var dc: Dictionary = SimConfig.build(def, {}).config
	for key in MAIN_KEYS:
		t.check(p.field_text(key) == ParamPanel.format_value(key, _cfg(dc, key)), "%s 칸 = 기본 예설정 값(%s)" % [key, p.field_text(key)])
		t.check(not p.is_highlighted(key), "%s 강조 없음(지금 실험과 같음)" % key)
	t.check(p.status_text() == ParamPanel.TEXT_SAME, "상태 줄: " + p.status_text())
	t.check(p.now_text().contains(lab.experiments[0].label) and p.now_text().contains("돌연변이 0.05"), "지금 실험 요약: " + p.now_text().replace("\n", " / "))
	var opt := p.control("preset:0") as OptionButton
	t.check(opt != null and opt.item_count == SimConfig.preset_names().size(), "예설정 목록 = SimConfig.presets()")
	var labels_ok := true
	var ps := SimConfig.presets()
	for i in opt.item_count:
		var pn := str(opt.get_item_metadata(i))
		labels_ok = labels_ok and opt.get_item_text(i) == str((ps[pn] as Dictionary).get("label", pn))
	t.check(labels_ok, "예설정 이름 = presets 의 label")
	t.check(str(opt.get_item_metadata(opt.selected)) == def, "고른 예설정 = 기본")
	t.check(ParamPanel.leaf_kind("population.initial") == ParamPanel.KIND_INT and ParamPanel.leaf_kind("mutation.rate") == ParamPanel.KIND_FLOAT
			and ParamPanel.leaf_kind("repro.asexual_when_alone") == ParamPanel.KIND_BOOL and ParamPanel.leaf_kind("seasons.growth") == ParamPanel.KIND_OTHER,
			"잎 키 종류(정수·실수·참거짓·배열)")
	t.check(ParamPanel.format_value("population.initial", 200.0) == "200" and ParamPanel.format_value("resources.scale", 1.0) == "1.0", "값 글자(정수 키는 정수)")


func _select_preset(p: ParamPanel, name: String, which: int = 0) -> void:
	var opt := p.control("preset:%d" % which) as OptionButton
	for i in opt.item_count:
		if str(opt.get_item_metadata(i)) == name:
			opt.select(i)
			opt.item_selected.emit(i)
			return


func _presets(t, p: ParamPanel) -> void:
	# 예설정을 고르면(단추 경로) 세 칸이 그 예설정 값으로
	for pn in ["abundant", "no_resources", "default"]:
		_select_preset(p, pn)
		var pc: Dictionary = SimConfig.build(pn, {}).config
		var ok: bool = str(p.current_settings(0).preset) == pn
		for key in MAIN_KEYS:
			ok = ok and p.field_text(key) == ParamPanel.format_value(key, _cfg(pc, key))
		t.check(ok, "예설정 %s → 세 칸 = 그 예설정 값(%s / %s / %s)" % [pn, p.field_text(MAIN_KEYS[0]), p.field_text(MAIN_KEYS[1]), p.field_text(MAIN_KEYS[2])])
	_select_preset(p, "abundant")
	t.check(p.is_highlighted("resources.scale") and not p.is_highlighted("mutation.rate"), "지금 실험과 다른 값만 강조(자원량)")
	t.check(p.status_text() == ParamPanel.TEXT_PENDING % 1, "상태 줄: " + p.status_text())
	# 바꾼 값이 있어도 예설정을 고르면 그 예설정 값으로
	p.set_value("mutation.rate", 0.2)
	t.check((p.current_settings(0).overrides as Dictionary).get("mutation.rate") == 0.2, "set_value → 바꾼 값")
	_select_preset(p, "default")
	t.check((p.current_settings(0).overrides as Dictionary).is_empty() and p.field_text("mutation.rate") == "0.05", "예설정을 고르면 바꾼 값을 지움")
	t.check(p.status_text() == ParamPanel.TEXT_SAME, "기본으로 돌아오면 지금 실험과 같음")
	# 예설정 값과 같은 값을 적으면 바꾼 값이 아님
	p.set_value("mutation.rate", 0.05)
	t.check((p.current_settings(0).overrides as Dictionary).is_empty(), "예설정과 같은 값은 바꾼 값에 넣지 않음")
	# 슬라이더(눈금 자릿수로 정리: 0.30000000000000004 같은 값이 생기지 않음)
	var sl := p.control("slider:mutation.rate:0") as HSlider
	sl.value = 0.015
	var mv: Variant = (p.current_settings(0).overrides as Dictionary).get("mutation.rate")
	t.check(typeof(mv) == TYPE_FLOAT and float(mv) == 0.015 and SimConfig.build("default", {"mutation.rate": mv}).error == "", "슬라이더 값 = 눈금 값(%s)" % str(mv))
	var si := p.control("slider:population.initial:0") as HSlider
	si.value = 123.0
	var iv: Variant = (p.current_settings(0).overrides as Dictionary).get("population.initial")
	t.check(typeof(iv) == TYPE_INT and int(iv) == 123, "초기 개체 수 슬라이더 → 정수")
	var cap := float(_cfg(SimConfig.build("default", {}).config, "population.cap"))
	t.check(is_equal_approx(si.max_value, minf(UiConfig.num("param.initial_max"), cap)), "초기 개체 수 끝 = min(initial_max, population.cap) = %.0f" % si.max_value)
	p.set_value("population.cap", 120)
	t.check(is_equal_approx(si.max_value, 120.0), "개체 상한을 바꾸면 슬라이더 끝도(%.0f)" % si.max_value)
	t.check((p.control("slider:mutation.rate:0") as HSlider).max_value == UiConfig.num("param.mutation_rate_max")
			and (p.control("slider:resources.scale:0") as HSlider).max_value == UiConfig.num("param.resource_scale_max"), "슬라이더 범위 = ui.param")
	p.revert()


func _layout(t, lab: LabMain, p: ParamPanel) -> void:
	await t.frames(3)
	var lw := UiConfig.num("lab.left_panel_width")
	var room := lw - 2.0 * UiConfig.num("theme.panel_padding")
	t.check(lab._left_wrap.visible, "패널을 넣으면 왼쪽 자리가 보임")
	for state in ["보통", "비교 + 고급 설정"]:
		if state != "보통":
			p.set_compare_mode(true)
			p.set_advanced_open(true)
			await t.frames(3)
		# 세로 스크롤 막대가 보여도 들어가야 한다(막대 폭을 더해 견줌)
		var vbar_w: float = (p.control("scroll") as ScrollContainer).get_v_scroll_bar().get_combined_minimum_size().x
		var minw: float = p.get_combined_minimum_size().x + vbar_w
		t.check(minw <= room, "[%s] 패널 최소 폭 + 스크롤 막대 %.0f ≤ %.0f" % [state, minw, room])
		t.check(lab._left_wrap.size.x <= lw + 0.5, "[%s] 왼쪽 자리 폭 %.0f = lab.left_panel_width(늘어나지 않음)" % [state, lab._left_wrap.size.x])
		var right := p.get_global_rect().end.x + 0.5
		var worst := ""
		for c in _controls(p):
			if c.is_visible_in_tree() and c.get_global_rect().end.x > right:
				worst = "%s %.0f > %.0f" % [c.get_class(), c.get_global_rect().end.x, right]
				break
		t.check(worst == "", "[%s] 가로로 넘치는 칸 없음 %s" % [state, worst])
		var sc := p.control("scroll") as ScrollContainer
		t.check(sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "[%s] 가로 스크롤 없음" % state)
		if state != "보통":
			t.check(sc.get_v_scroll_bar().max_value > sc.size.y + 1.0, "[%s] 세로로 넘치면 스크롤(내용 %.0f > %.0f)" % [state, sc.get_v_scroll_bar().max_value, sc.size.y])
		# 1280×720·자리 펼침: 주요 단추(새 실험/나란히 시작)·되돌리기·비교 모드 단추가 스크롤하지 않아도 화면 안
		# (예전에는 비교 모드를 켜면 B 칸이 끼어 나란히 시작·비교 끄기 단추가 스크롤 아래로 밀려 안 보였음)
		var main_btn := p.control("apply" if state == "보통" else "start_compare") as Control
		t.check(_on_screen(t, main_btn) and _on_screen(t, p.control("compare") as Control) and _on_screen(t, p.control("revert") as Control),
				"[%s] 주요 단추·비교 모드 단추가 화면 안(스크롤 없이) %s" % [state, str(main_btn.get_global_rect())])
		var nt := p.control("next_title") as Label
		t.check(nt.is_visible_in_tree() and nt.text == (ParamPanel.TEXT_NEXT if state == "보통" else ParamPanel.TEXT_NEXT_COMPARE),
				"[%s] 다음 실험 제목 보임: %s" % [state, nt.text])
	var card_b := p.control("card:1") as Control
	t.check(card_b.visible and (p.control("start_compare") as Control).visible and not (p.control("apply") as Control).visible, "비교 모드: B 칸·나란히 시작 보임, 새 실험 숨음")
	t.check((p.control("card_side:1") as Label).text == ParamPanel.TEXT_COL_NEXT, "비교 전 칸 머리 = \"다음 조건\"(지도는 아직 하나)")
	p.set_compare_mode(false)
	p.set_advanced_open(false)
	await t.frames(1)
	t.check(not card_b.visible and (p.control("apply") as Control).visible, "비교 모드 끄면 B 칸 숨음")


## 컨트롤이 화면에 다 보이는가: 보이고, 창 안이고, 스크롤 조상이 있으면 그 보이는 칸 안.
func _on_screen(t, c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var vis := Rect2(Vector2.ZERO, Vector2(t.root.size))
	var n := c.get_parent()
	while n != null:
		if n is ScrollContainer:
			vis = vis.intersection((n as ScrollContainer).get_global_rect())
		n = n.get_parent()
	return vis.grow(0.5).encloses(c.get_global_rect())


func _controls(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	for ch in n.get_children():
		if ch is Control:
			out.append(ch as Control)
			if not (ch is ScrollBar):
				out.append_array(_controls(ch))
	return out


func _apply(t, lab: LabMain, p: ParamPanel) -> void:
	var old := lab.experiments[0]
	p.set_value("mutation.rate", 0.12)
	p.set_value("resources.scale", 1.35)
	p.set_value("population.initial", 150)
	p.set_value("plants.regrow", 0.2)
	p.set_value("seed", 77)
	t.check(lab.experiments[0] == old and lab.world.seed_value != 77, "값을 바꿔도 지금 실험은 그대로")
	t.check(p.status_text() == ParamPanel.TEXT_PENDING % 5, "상태 줄 바꾼 값 5개: " + p.status_text())
	t.check(p.is_highlighted("seed") and p.is_highlighted("mutation.rate"), "바꾼 씨앗·값 강조")
	var e := p.apply()
	t.check(e == "" and lab.experiments[0] != old, "apply → 새 실험: " + e)
	var cfg: Dictionary = lab.world.cfg
	t.check(float(_cfg(cfg, "mutation.rate")) == 0.12 and float(_cfg(cfg, "resources.scale")) == 1.35
			and int(_cfg(cfg, "population.initial")) == 150 and float(_cfg(cfg, "plants.regrow")) == 0.2, "새 실험의 cfg 에 패널 값")
	t.check(lab.world.seed_value == 77 and lab.world.population() == 150, "새 실험 씨앗 77·초기 개체 150")
	t.check(p.status_text() == ParamPanel.TEXT_SAME and not p.is_highlighted("mutation.rate"), "적용 뒤 지금 실험과 같음")
	t.check(p.now_text().contains("씨앗 77") and p.now_text().contains("돌연변이 0.12") and p.now_text().contains("개체 150"), "지금 실험 요약 갱신: " + p.now_text().replace("\n", " / "))
	# 단추 경로
	p.set_value("seed", 78)
	(p.control("apply") as Button).pressed.emit()
	t.check(lab.world.seed_value == 78 and float(_cfg(lab.world.cfg, "mutation.rate")) == 0.12, "새 실험 단추 → 씨앗 78, 바꾼 값 유지")


func _invalid(t, lab: LabMain, p: ParamPanel) -> void:
	var x := lab.experiments[0]
	var w0 := int(_cfg(lab.world.cfg, "map.width"))
	p.set_advanced_open(true)
	var err := p.set_value("map.width", 4)
	t.check(err.contains("map.width"), "범위 밖 값 → 오류: " + err)
	t.check(p.row_error("map.width", 0, true).contains("map.width"), "오류가 그 칸 아래에: " + p.row_error("map.width", 0, true))
	t.check(p.error_text() != "" and p.status_text().contains("오류"), "패널 오류 글·상태 줄")
	t.check((p.control("apply") as Button).disabled, "오류가 있으면 새 실험 단추를 못 씀")
	var toasts0 := lab.visible_toasts().size()
	var r := p.apply()
	t.check(r != "" and lab.experiments[0] == x and int(_cfg(lab.world.cfg, "map.width")) == w0, "apply 거부 · 지금 실험 그대로")
	var toasted := false
	for to in lab.visible_toasts():
		toasted = toasted or (str(to.kind) == "error" and str(to.text).contains("새 실험을 시작할 수 없습니다"))
	t.check(toasted and lab.visible_toasts().size() >= mini(toasts0 + 1, UiConfig.integer("lab.toast_max")), "오류 알림")
	# 칸에 해석할 수 없는 글자 → 그 줄 오류, 값은 그대로
	var le := p.control("adv:plants.regrow") as LineEdit
	le.text = "abc"
	le.text_submitted.emit("abc")
	t.check(p.row_error("plants.regrow", 0, true).contains("수가 아닙니다"), "글자 오류: " + p.row_error("plants.regrow", 0, true))
	t.check(float((p.current_settings(0).overrides as Dictionary).get("plants.regrow", -1.0)) == 0.2 and le.text == "0.2", "해석 못 한 글자는 버리고 값 유지")
	t.check(p.set_value("map.height", "2.5").contains("정수") and not (p.current_settings(0).overrides as Dictionary).has("map.height"), "정수 키에 소수 → 오류")
	t.check(p.set_value("seasons.growth", [1, 1, 1, 1]) != "", "배열 키는 패널에서 바꾸지 않음")
	# 체크 상자(참거짓 키)
	var cb := p.control("adv:repro.asexual_when_alone") as CheckBox
	cb.button_pressed = true
	t.check((p.current_settings(0).overrides as Dictionary).get("repro.asexual_when_alone") == true and p.is_highlighted("repro.asexual_when_alone", 0, true), "참거짓 칸 → 바꾼 값·강조")
	# 초기 개체 수 > 개체 상한
	p.set_value("map.width", 64)
	var e2 := p.set_value("population.cap", 100)
	t.check(e2.contains("population.cap") and p.row_error("population.initial").contains("population.initial"), "초기 개체 수 > 상한 → 초기 개체 수 칸 아래 오류: " + p.row_error("population.initial"))


func _revert(t, lab: LabMain, p: ParamPanel) -> void:
	var rb := p.control("revert") as Button
	t.check(not rb.disabled, "바꾼 값이 있으면 되돌리기 가능")
	rb.pressed.emit()
	var s := p.current_settings(0)
	t.check((s.overrides as Dictionary).is_empty() and int(s.seed) == 78, "되돌리기 → 바꾼 값 없음, 씨앗 그대로")
	t.check(p.error_text() == "" and p.row_error("population.initial") == "" and p.row_error("map.width", 0, true) == "", "되돌리면 오류도 사라짐")
	t.check(p.field_text("mutation.rate") == "0.05" and p.field_text("population.initial") == "200", "되돌리기 → 예설정 값")
	# 지금 실험(0.12·1.35·150·0.2)과 다른 값 넷이 강조
	t.check(p.is_highlighted("mutation.rate") and p.status_text() == ParamPanel.TEXT_PENDING % 4, "지금 실험과 다른 값 4개: " + p.status_text())
	t.check(rb.disabled, "되돌린 뒤 되돌리기 단추 꺼짐")
	p.set_advanced_open(false)
	# 다시 지금 실험 조건으로
	var x := lab.experiments[0]
	for k: String in x.overrides:
		p.set_value(k, x.overrides[k])
	t.check(p.status_text() == ParamPanel.TEXT_SAME, "같은 값을 다시 적으면 지금 실험과 같음")


func _seed(t, lab: LabMain, p: ParamPanel) -> void:
	var smax := UiConfig.integer("param.seed_max")
	var spin := p.control("seed:0") as SpinBox
	t.check(spin.min_value == 0.0 and spin.max_value == float(smax) and spin.rounded, "씨앗 칸 0~ui.param.seed_max")
	p.set_value("seed", -5)
	t.check(int(p.current_settings(0).seed) == 0, "음수 씨앗 → 0")
	p.set_value("seed", smax + 10)
	t.check(int(p.current_settings(0).seed) == smax and int(spin.value) == smax, "seed_max 보다 큰 씨앗 → seed_max")
	t.check(p.set_value("seed", "열둘") != "" and int(p.current_settings(0).seed) == smax, "정수가 아닌 씨앗 거부")
	spin.value = 4321.0
	t.check(int(p.current_settings(0).seed) == 4321, "씨앗 칸 → 조건")
	# 무작위: 범위 안, 세계·전역 난수 그대로
	var x := lab.experiments[0]
	var tick := lab.world.tick
	var h := lab.world.history_hash
	seed(12345)
	var r1 := randi()
	seed(12345)
	var ok := true
	for i in 5:
		(p.control("random:0") as Button).pressed.emit()
		var v := int(p.current_settings(0).seed)
		ok = ok and v >= 0 and v <= smax and int(spin.value) == v
	t.check(ok, "무작위 씨앗은 0~seed_max")
	t.check(randi() == r1, "무작위가 Godot 전역 난수를 건드리지 않음")
	t.check(lab.experiments[0] == x and lab.world.tick == tick and lab.world.history_hash == h, "무작위가 세계를 건드리지 않음")
	p.set_value("seed", 78)


func _key(t, code: Key, ch: String = "") -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = ch.unicode_at(0) if ch != "" and pressed else 0
		e.pressed = pressed
		t.root.push_input(e)


func _typing(t, lab: LabMain, p: ParamPanel) -> void:
	lab.set_paused(false)
	lab.set_speed(1)
	var id := lab.world.s_id[0]
	lab.select_slime(id)
	var le := (p.control("seed:0") as SpinBox).get_line_edit()
	le.grab_focus()
	await t.frames(1)
	var follow0 := lab.map_view.follow_selected
	_key(t, KEY_4, "4")
	_key(t, KEY_2, "2")
	_key(t, KEY_SPACE, " ")
	_key(t, KEY_F, "f")
	t.check(le.has_focus() and le.text.contains("42"), "씨앗 칸에 글자가 들어감(%s)" % le.text)
	t.check(not lab.is_paused() and lab.target_speed() == 1 and lab.map_view.follow_selected == follow0, "씨앗 칸 입력 중 스페이스·숫자·F 단축키 무시")
	_key(t, KEY_ESCAPE)
	t.check(not le.has_focus() and lab.selected_id() == id and int(p.current_settings(0).seed) == 78, "Esc → 입력 버리고 초점 풀기(선택 해제 아님)")
	# 숫자 칸: "0.07" + Enter → 값, 단축키(0 = 전체 보기, 7 = 64배) 무시
	var f := p.control("field:mutation.rate:0") as LineEdit
	f.grab_focus()
	await t.frames(1)
	for c in ["0", ".", "0", "7"]:
		var code: Key = KEY_PERIOD if c == "." else (KEY_0 + int(c)) as Key
		_key(t, code, c)
	t.check(lab.target_speed() == 1, "숫자 칸 입력 중 7 키가 배속을 바꾸지 않음")
	_key(t, KEY_ENTER)
	t.check(not f.has_focus() and float((p.current_settings(0).overrides as Dictionary).get("mutation.rate", 0.0)) == 0.07, "Enter → 값 확정(0.07)·초점 풀림")
	_key(t, KEY_2)
	t.check(lab.target_speed() == int((UiConfig.value("speed.steps") as Array)[1]), "초점이 풀리면 단축키 다시 동작")
	lab.set_speed(1)
	lab.set_paused(true)
	p.set_value("mutation.rate", 0.12)


## 글자를 실제 키 입력으로(초점 있는 칸에 들어감). 숫자·점·쉼표·빼기·영문 소문자·빈칸.
func _type(t, text: String) -> void:
	for i in text.length():
		var ch := text[i]
		var code: Key = KEY_SPACE
		if ch >= "0" and ch <= "9":
			code = (KEY_0 + int(ch)) as Key
		elif ch == ".":
			code = KEY_PERIOD
		elif ch == ",":
			code = KEY_COMMA
		elif ch == "-":
			code = KEY_MINUS
		elif ch >= "a" and ch <= "z":
			code = (KEY_A + (ch.unicode_at(0) - "a".unicode_at(0))) as Key
		_key(t, code, ch)


## 칸에 초점을 주고(글자 전체 고름) 실제 키로 적는다 — Enter 없이.
func _type_into(t, le: LineEdit, text: String) -> void:
	le.grab_focus()
	await t.frames(1)
	_type(t, text)


func _focus_owner(p: ParamPanel) -> Control:
	return p.get_viewport().gui_get_focus_owner()


## 입력 중인 칸(Enter 없음) + 단추: 적던 값은 적던 칸·상태로 확정되고 초점이 풀린다(초점이 남아 나중에 다른 칸·되돌린 상태에
## 확정되던 것). 단추를 누른 뒤에는 단축키가 바로 듣는다.
func _pending_edits(t, lab: LabMain, p: ParamPanel) -> void:
	var x := lab.experiments[0]
	p.set_compare_mode(true)
	p.set_advanced_open(true)
	(p.control("adv_target:0") as Button).pressed.emit()
	await t.frames(1)
	# (a) A 칸 고급 설정에 적다가 B 단추 → A 에 들어감
	await _type_into(t, p.control("adv:metab.base") as LineEdit, "0.09")
	t.check((p.control("adv:metab.base") as LineEdit).text == "0.09", "고급 칸에 0.09 를 적음(Enter 없음)")
	(p.control("adv_target:1") as Button).pressed.emit()
	t.check(_focus_owner(p) == null, "A/B 단추 → 입력 칸 초점 풀림")
	p.get_viewport().gui_release_focus()
	var a := p.current_settings(0).overrides as Dictionary
	var b := p.current_settings(1).overrides as Dictionary
	t.check(float(a.get("metab.base", -1.0)) == 0.09 and not b.has("metab.base"), "A 에 적고 B 단추 → A 에만 metab.base 0.09 (A %s / B %s)" % [str(a), str(b)])
	t.check((p.control("adv:metab.base") as LineEdit).text == ParamPanel.format_value("metab.base", 0.06), "B 칸 보기 → 칸 글자 = B 값 0.06")
	# (b) B 에 적다가 A 단추 → B 에 들어감
	await _type_into(t, p.control("adv:mutation.sigma") as LineEdit, "0.9")
	(p.control("adv_target:0") as Button).pressed.emit()
	p.get_viewport().gui_release_focus()
	a = p.current_settings(0).overrides as Dictionary
	b = p.current_settings(1).overrides as Dictionary
	t.check(float(b.get("mutation.sigma", -1.0)) == 0.9 and not a.has("mutation.sigma"), "B 에 적고 A 단추 → B 에만 mutation.sigma 0.9")
	# (c) 적다가 되돌리기 → 바꾼 값 없음(적던 글자가 나중에 다시 확정되지 않음), 칸 = 예설정 값
	await _type_into(t, p.control("field:resources.scale:0") as LineEdit, "2.0")
	(p.control("revert") as Button).pressed.emit()
	t.check(_focus_owner(p) == null, "되돌리기 → 초점 풀림")
	p.get_viewport().gui_release_focus()
	t.check((p.current_settings(0).overrides as Dictionary).is_empty() and (p.current_settings(1).overrides as Dictionary).is_empty()
			and p.field_text("resources.scale") == "1.0", "적다가 되돌리기 → 바꾼 값 없음·칸 = 예설정 1.0 (%s)" % str(p.current_settings(0).overrides))
	# (d) 적다가 예설정 고르기 → 예설정 값, 바꾼 값 없음
	await _type_into(t, p.control("field:resources.scale:0") as LineEdit, "2.5")
	_select_preset(p, "abundant")
	t.check(_focus_owner(p) == null, "예설정 고르기 → 초점 풀림")
	p.get_viewport().gui_release_focus()
	t.check(str(p.current_settings(0).preset) == "abundant" and (p.current_settings(0).overrides as Dictionary).is_empty()
			and p.field_text("resources.scale") == "1.6", "적다가 예설정(풍요) → 칸 1.6·바꾼 값 없음 (%s)" % str(p.current_settings(0).overrides))
	_select_preset(p, "default")
	p.set_compare_mode(false)
	p.set_advanced_open(false)
	# 지금 실험 조건으로(씨앗·바꾼 값)
	for k: String in x.overrides:
		p.set_value(k, x.overrides[k])
	t.check(p.status_text() == ParamPanel.TEXT_SAME, "다시 지금 실험 조건: " + p.status_text())
	# (e) 칸에 적고 새 실험 단추 → 적은 값으로 시작, 초점 풀림, 단축키 바로 동작
	lab.set_speed(1)
	await _type_into(t, p.control("field:mutation.rate:0") as LineEdit, "0.12")
	(p.control("apply") as Button).pressed.emit()
	t.check(lab.experiments[0] != x and float(_cfg(lab.world.cfg, "mutation.rate")) == 0.12 and _focus_owner(p) == null,
			"적고 새 실험 단추 → 적은 값으로 새 실험·초점 풀림")
	_key(t, KEY_2)
	t.check(lab.target_speed() == int((UiConfig.value("speed.steps") as Array)[1]), "새 실험 단추 뒤 단축키(2) 바로 동작")
	lab.set_speed(1)
	# (f) 씨앗 칸에 적고 무작위·비교 모드 단추 → 초점 풀림
	await _type_into(t, (p.control("seed:0") as SpinBox).get_line_edit(), "5")
	(p.control("random:0") as Button).pressed.emit()
	t.check(_focus_owner(p) == null and int(p.current_settings(0).seed) == int((p.control("seed:0") as SpinBox).value), "무작위 단추 → 초점 풀림·씨앗 칸 = 고른 씨앗")
	await _type_into(t, p.control("field:population.initial:0") as LineEdit, "150")
	(p.control("compare") as Button).button_pressed = true
	t.check(_focus_owner(p) == null, "비교 모드 단추 → 초점 풀림")
	(p.control("compare") as Button).button_pressed = false
	p.set_value("seed", lab.world.seed_value)
	t.check(p.status_text() == ParamPanel.TEXT_SAME, "다시 지금 실험 조건: " + p.status_text())
	# 읽기 전용 고급 칸은 초점을 받지 않는다(눌러도 단축키가 그대로)
	t.check((p.control("adv:seasons.growth") as LineEdit).focus_mode == Control.FOCUS_NONE
			and (p.control("adv:brain.policy") as LineEdit).focus_mode == Control.FOCUS_NONE, "읽기 전용 고급 칸 초점 없음")


## 해석할 수 없는 글자를 적은 채(Enter 없음) 새 실험·나란히 시작 → 시작하지 않고 그 줄 아래 오류 + 패널 오류 + 알림.
func _bad_text(t, lab: LabMain, p: ParamPanel) -> void:
	var x := lab.experiments[0]
	await _type_into(t, p.control("field:mutation.rate:0") as LineEdit, "0,07")
	(p.control("apply") as Button).pressed.emit()
	t.check(lab.experiments[0] == x and float(_cfg(lab.world.cfg, "mutation.rate")) == 0.12, "\"0,07\" + 새 실험 단추 → 시작 안 함(지금 실험 그대로)")
	t.check(p.row_error("mutation.rate").contains("수가 아닙니다") and p.error_text().contains("입력 오류"),
			"그 줄 아래 오류·패널 오류: %s / %s" % [p.row_error("mutation.rate"), p.error_text()])
	var toasted := false
	for to in lab.visible_toasts():
		toasted = toasted or (str(to.kind) == "error" and str(to.text).contains("입력 오류"))
	t.check(toasted and p.field_text("mutation.rate") == "0.12" and _focus_owner(p) == null, "오류 알림·칸은 지금 값·초점 풀림")
	# 함수 경로(apply)도 같음
	var le := p.control("field:mutation.rate:0") as LineEdit
	le.grab_focus()
	le.text = "abc"
	var e := p.apply()
	t.check(e.contains("입력 오류") and lab.experiments[0] == x, "apply() 도 시작 안 함: " + e)
	# 씨앗 칸: SpinBox 가 말없이 되돌리던 글자
	await _type_into(t, (p.control("seed:0") as SpinBox).get_line_edit(), "42 f")
	e = p.apply()
	t.check(e.contains("씨앗은 정수") and lab.experiments[0] == x and lab.world.seed_value == x.seed_value, "씨앗 칸 \"42 f\" + 새 실험 → 시작 안 함: " + e)
	# 나란히 시작(B 칸)
	p.set_compare_mode(true)
	await _type_into(t, p.control("field:mutation.rate:1") as LineEdit, "0,2")
	(p.control("start_compare") as Button).pressed.emit()
	t.check(not lab.is_comparing() and lab.experiments[0] == x and p.row_error("mutation.rate", 1).contains("수가 아닙니다")
			and p.error_text().contains("B: "), "B 칸 \"0,2\" + 나란히 시작 → 시작 안 함·B 줄 오류: " + p.error_text())
	p.set_compare_mode(false)
	p.set_value("mutation.rate", 0.12)
	t.check(p.status_text() == ParamPanel.TEXT_SAME and p.row_error("mutation.rate") == "", "고쳐 적으면 오류 사라짐: " + p.status_text())


## 고급 설정: 줄 이름은 키 그대로, 말풍선 = 한국어 이름·뜻·단위·범위(config/sim-labels.json) + 키 + 값, 읽기 전용 배열 칸의 전체 값.
func _labels(t, p: ParamPanel) -> void:
	var missing: Array[String] = []
	for k in ParamPanel.leaf_keys():
		var l := ParamPanel.key_label(k)
		if str(l.get("name", "")) == "" or str(l.get("help", "")) == "":
			missing.append(k)
	t.check(missing.is_empty(), "모든 설정 키에 한국어 이름·뜻(없음: %s)" % ", ".join(missing))
	p.set_advanced_open(true)
	var nl := p.control("adv_name:map.fertility_floor") as Label
	t.check(nl.text == "fertility_floor" and nl.tooltip_text.contains("최저 비옥도") and nl.tooltip_text.contains("map.fertility_floor")
			and nl.tooltip_text.contains("범위"), "줄 이름 = 키, 말풍선 = 한국어 이름·뜻·범위: " + nl.tooltip_text.replace("\n", " / "))
	var g := p.control("adv:seasons.growth") as LineEdit
	t.check(g.tooltip_text.contains("[1.0,1.2,0.8,0.3]"), "읽기 전용 배열 칸 말풍선 = 전체 값: " + g.tooltip_text)
	t.check((p.control("adv:metab.base") as LineEdit).tooltip_text.contains("기본 대사"), "고급 칸 말풍선에 한국어 이름")
	p.set_advanced_open(false)


## 실수 글자 = JSON 글자(적용되는 cfg 값 그대로 — 14자리에서 잘리거나 아주 작은 값이 0.0 으로 보이지 않음).
func _float_text(t, p: ParamPanel) -> void:
	p.set_value("mutation.rate", "0.123456789012345")
	var ft := p.field_text("mutation.rate")
	var ov: Variant = (p.current_settings(0).overrides as Dictionary).get("mutation.rate")
	t.check(ft == "0.123456789012345" and ft.to_float() == float(ov), "15자리 값의 칸 글자 = 적용 값: %s" % ft)
	var tiny := ParamPanel.format_value("plants.night_growth", 5e-15)
	t.check(tiny != "0.0" and absf(tiny.to_float() - 5e-15) < 1e-20, "아주 작은 값도 0.0 이 아님: " + tiny)
	t.check(ParamPanel.format_value("resources.scale", 1.0) == "1.0" and ParamPanel.format_value("mutation.rate", 0.05) == "0.05", "보통 값 표기는 그대로")
	p.set_value("mutation.rate", 0.12)


## 슬라이더를 끄는 동안(set_value 한 번) 고급 설정을 펼쳐도: "지금 실험과 다른가" 는 칸마다 한 번만 세고(키 수 + 씨앗),
## 85줄 말풍선은 다시 만들지 않는다(칸·예설정·지금 실험이 바뀔 때만). 시간은 참고로 출력만(기계마다 다름).
func _refresh_cost(t, lab: LabMain, p: ParamPanel) -> void:
	p.set_advanced_open(true)
	var n := ParamPanel.leaf_keys().size()
	var tips0 := p.stats_tip_builds
	var evals0 := p.stats_diff_evals
	var t0 := Time.get_ticks_usec()
	p.set_value("mutation.rate", 0.07)
	var us := Time.get_ticks_usec() - t0
	t.check(p.stats_tip_builds == tips0, "set_value 한 번에 말풍선 다시 만들지 않음(%d줄)" % (p.stats_tip_builds - tips0))
	t.check(p.stats_diff_evals - evals0 <= n + 1, "set_value 한 번에 견준 수 %d ≤ 키 %d + 씨앗(칸 하나)" % [p.stats_diff_evals - evals0, n])
	var sl := p.control("slider:mutation.rate:0") as HSlider
	tips0 = p.stats_tip_builds
	evals0 = p.stats_diff_evals
	sl.value = 0.09
	t.check(p.stats_tip_builds == tips0 and p.stats_diff_evals - evals0 <= n + 1, "슬라이더 한 칸도 같음(견준 수 %d)" % (p.stats_diff_evals - evals0))
	_select_preset(p, "abundant")
	t.check(p.stats_tip_builds - tips0 == n, "예설정을 바꾸면 말풍선을 한 번 다시 만듦(%d줄)" % (p.stats_tip_builds - tips0))
	print("  (참고) 고급 설정을 펼친 채 set_value 한 번 %d µs" % us)
	_select_preset(p, "default")
	p.set_advanced_open(false)
	# 다시 지금 실험 조건으로
	for k: String in lab.experiments[0].overrides:
		p.set_value(k, lab.experiments[0].overrides[k])
	t.check(p.status_text() == ParamPanel.TEXT_SAME, "다시 지금 실험 조건: " + p.status_text())


func _export(t, lab: LabMain, p: ParamPanel) -> void:
	var dir := TMP_DIR.path_join("export")
	_clean_dir(ProjectSettings.globalize_path(dir))
	var e := p.export_to(dir)
	var abs_dir := ProjectSettings.globalize_path(dir)
	var ok := e == ""
	for fn in ["summary.json", "timeseries.csv", "chronicle.csv", "final.snapshot.json"]:
		ok = ok and FileAccess.file_exists(abs_dir.path_join(fn))
	t.check(ok, "export_to(폴더) → 결과 파일: " + e)
	var toasted := false
	for to in lab.visible_toasts():
		toasted = toasted or str(to.text).contains("결과를 내보냈습니다")
	t.check(toasted and p.error_text() == "", "내보내기 알림(LabMain)·패널 오류 글 없음")
	_clean_dir(abs_dir)
	await t.frames(1)


func _snapshot(t, lab: LabMain, p: ParamPanel) -> void:
	var path := ProjectSettings.globalize_path(SNAP_PATH)
	for f in [path, path + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var base := ProjectSettings.globalize_path(ParamPanel.SNAPSHOT_DIR).trim_suffix("/")
	(p.control("save") as Button).pressed.emit()
	await t.frames(1)
	var sd := p.control("save_dialog") as FileDialog
	t.check(sd != null and sd.visible, "스냅숏 저장 → 대화 상자")
	if sd == null:
		return
	t.check(sd.file_mode == FileDialog.FILE_MODE_SAVE_FILE and sd.access == FileDialog.ACCESS_FILESYSTEM and "*.json" in ",".join(sd.filters), "저장 대화 상자: 파일 저장·파일 시스템·*.json")
	t.check(sd.current_dir.trim_suffix("/") == base and DirAccess.dir_exists_absolute(base), "시작 폴더 = user://experiments(%s)" % sd.current_dir)
	t.check(sd.current_file.begins_with("snapshot-") and sd.current_file.ends_with(".json"), "기본 파일 이름: " + sd.current_file)
	sd.file_selected.emit(path)
	sd.hide()
	t.check(FileAccess.file_exists(path), "파일을 고르면 저장")
	var tick := lab.world.tick
	lab.step_ticks(30)
	(p.control("open") as Button).pressed.emit()
	await t.frames(1)
	var od := p.control("open_dialog") as FileDialog
	t.check(od != null and od.visible and od.file_mode == FileDialog.FILE_MODE_OPEN_FILE and od.access == FileDialog.ACCESS_FILESYSTEM, "스냅숏 열기 → 열기 대화 상자")
	if od == null:
		return
	od.file_selected.emit(path)
	od.hide()
	t.check(lab.experiments[0].snapshot_path == path and lab.world.tick == tick, "파일을 고르면 열림(틱 %d)" % lab.world.tick)
	t.check(p.now_text().contains("스냅숏"), "지금 실험 = 스냅숏: " + p.now_text().replace("\n", " / "))
	var s := p.current_settings(0)
	t.check(float((s.overrides as Dictionary).get("mutation.rate", 0.0)) == 0.12 and int(s.seed) == lab.world.seed_value and p.status_text() == ParamPanel.TEXT_SAME,
			"스냅숏의 설정을 패널로(가장 가까운 예설정 %s + 다른 값 %d개)" % [str(s.preset), (s.overrides as Dictionary).size()])
	var e := p.open_snapshot_from(ProjectSettings.globalize_path(TMP_DIR.path_join("없는파일.json")))
	t.check(e != "" and p.error_text().contains(e) and lab.experiments[0].snapshot_path == path, "없는 스냅숏 → 패널 안 오류, 지금 실험 그대로")
	await t.frames(1)


func _find_sound(lab: LabMain) -> LabSound:
	for ch in lab.get_children():
		if ch is LabSound and not ch.is_queued_for_deletion():
			return ch as LabSound
	return null


func _sound(t, lab: LabMain, p: ParamPanel) -> void:
	var cb := p.control("sound") as CheckBox
	var snd := _find_sound(lab)
	t.check(snd != null and snd == lab.lab_sound, "실험실에 LabSound 있음")
	if snd == null:
		return
	t.check(not cb.disabled and cb.button_pressed == snd.enabled, "LabSound 를 찾아 상태를 맞춤")
	cb.button_pressed = false
	t.check(snd.enabled == false, "끄면 LabSound.enabled = false")
	cb.button_pressed = true
	t.check(snd.enabled == true, "켜면 LabSound.enabled = true")
	# LabSound 가 실험실에서 빠지면 못 씀(자식이 바뀔 때마다 다시 찾음), 돌아오면 다시
	lab.remove_child(snd)
	await t.frames(2)
	t.check(cb.disabled and cb.tooltip_text.contains("LabSound"), "LabSound 가 빠지면 소리 상자 못 씀")
	cb.button_pressed = true
	t.check(cb.disabled, "LabSound 없이 눌러도 멈추지 않음")
	lab.add_child(snd)
	await t.frames(2)
	t.check(not cb.disabled and cb.button_pressed == snd.enabled, "LabSound 가 돌아오면 다시 씀")


## 지금 실험의 씨앗이 패널 범위(0~seed_max) 밖(명령줄 --seed=-5·스냅숏): 칸은 그 씨앗 그대로(안내), "지금 실험과 같음",
## 새 실험은 같은 씨앗으로(예전에는 0 으로 잘라 "바꾼 값 1개" 가 뜨고 새 실험이 다른 세계였음).
func _seed_range(t, lab: LabMain, p: ParamPanel) -> void:
	var smax := UiConfig.integer("param.seed_max")
	t.check(lab.new_experiment("default", {}, -5) == "", "씨앗 -5 실험")
	var spin := p.control("seed:0") as SpinBox
	var note := p.control("seed_note:0") as Label
	t.check(int(p.current_settings(0).seed) == -5 and p.status_text() == ParamPanel.TEXT_SAME and int(spin.value) == -5,
			"씨앗 -5 → 칸도 -5·지금 실험과 같음: %s · %s" % [str(p.current_settings(0).seed), p.status_text()])
	t.check(note.visible and note.text.contains("-5"), "범위 밖 씨앗 안내: " + note.text)
	var x := lab.experiments[0]
	t.check(p.apply() == "" and lab.experiments[0] != x and lab.world.seed_value == -5, "새 실험 → 같은 씨앗 -5 (%d)" % lab.world.seed_value)
	var big := smax + 852516353
	t.check(lab.new_experiment("default", {}, big) == "" and int(p.current_settings(0).seed) == big and p.status_text() == ParamPanel.TEXT_SAME,
			"씨앗 %d(상한 밖) → 칸도 그대로·지금 실험과 같음" % big)
	t.check(p.apply() == "" and lab.world.seed_value == big, "새 실험 → 같은 씨앗 %d" % big)
	# 범위 밖 씨앗의 스냅숏을 열어도 같음
	var path := ProjectSettings.globalize_path(TMP_DIR.path_join("big_seed.json"))
	t.check(lab.save_snapshot(path) == "", "범위 밖 씨앗 스냅숏 저장")
	lab.new_experiment("default", {}, 1)
	t.check(lab.open_snapshot(path) == "" and int(p.current_settings(0).seed) == big and p.status_text() == ParamPanel.TEXT_SAME,
			"범위 밖 씨앗 스냅숏을 열면 칸 = 그 씨앗·지금 실험과 같음")
	# 칸에서 고치면 범위 안으로(계약 그대로)
	p.set_value("seed", -7)
	t.check(int(p.current_settings(0).seed) == 0 and not note.visible, "칸에서 고친 씨앗은 범위 안으로·안내 사라짐")
	lab.new_experiment("default", {}, 1)
	await t.frames(1)


## 진짜 실험실: 비교 모드 단추 → B 칸(A 를 베낌), 나란히 시작 → 비교 실험 둘(지도 둘·칸 머리 = 지도 자리), 비교 중에도 주요
## 단추가 화면 안, 비교 중에 A 칸을 고치고 비교를 끄면 고친 값이 남음(같은 A 실험이라 다시 맞추지 않음).
func _real_compare(t, lab: LabMain, p: ParamPanel) -> void:
	# 패널 A = 지금 실험 조건에서 시작
	t.check(p.status_text() == ParamPanel.TEXT_SAME, "비교 전 A 칸 = 지금 실험")
	var btn := p.control("compare") as Button
	btn.button_pressed = true
	await t.frames(1)
	t.check(p.is_compare_mode() and (p.control("card:1") as Control).visible, "비교 모드 단추 → B 칸")
	t.check(SimConfig.deep_equal(p.current_settings(1), p.current_settings(0)), "B 칸은 A 조건을 베껴 시작")
	p.set_value("resources.scale", 1.6, 1)
	t.check(p.is_highlighted("resources.scale", 1) and not p.is_highlighted("resources.scale", 0), "B 의 바꾼 값만 B 칸에서 강조")
	t.check(p.status_text() == ParamPanel.TEXT_COMPARE_IDLE, "비교 전 상태 줄: " + p.status_text())
	var e := p.apply_compare()
	t.check(e == "" and lab.is_comparing() and lab.experiments.size() == 2, "나란히 시작 → 실험 둘: " + e)
	t.check(p.now_text().contains("A ·") and p.now_text().contains("B ·") and lab.experiments.size() == 2
			and float(_cfg(lab.experiments[1].world.cfg, "resources.scale")) == 1.6, "지금 실험 A·B, B 의 자원량 1.6")
	t.check((p.control("card_side:0") as Label).text == ParamPanel.COL_SIDES[0] and (p.control("card_side:1") as Label).text == ParamPanel.COL_SIDES[1],
			"비교 중 칸 머리 = 왼쪽/오른쪽 지도")
	await t.frames(3)
	t.check(_on_screen(t, p.control("start_compare") as Control) and _on_screen(t, p.control("compare") as Control),
			"비교 중에도 나란히 시작·비교 끄기 단추가 화면 안")
	# 비교 중 A 칸을 고치고 비교를 끔 → 고친 값 그대로(A 실험은 같은 것)
	p.set_value("mutation.rate", 0.2, 0)
	p.set_value("seed", 4242, 0)
	btn.button_pressed = false
	await t.frames(1)
	t.check(not p.is_compare_mode() and not (p.control("card:1") as Control).visible and not lab.is_comparing(), "비교 모드 끄기 → B 칸 숨음·비교 끝")
	var s := p.current_settings(0)
	t.check(float((s.overrides as Dictionary).get("mutation.rate", -1.0)) == 0.2 and int(s.seed) == 4242
			and p.status_text() == ParamPanel.TEXT_PENDING % 2, "비교를 꺼도 A 칸의 고친 값 그대로: %s · %s" % [str(s), p.status_text()])
	t.check(p.apply() == "" and float(_cfg(lab.world.cfg, "mutation.rate")) == 0.2 and lab.world.seed_value == 4242
			and p.status_text() == ParamPanel.TEXT_SAME, "새 실험 → 고친 값으로·지금 실험과 같음")


## 오래 돈 실험을 버리는 단추(새 실험·나란히 시작·비교 끄기)는 먼저 묻는다(confirm_discard_ticks 이상). 취소 = 그대로,
## 끝내기 = 함. 문턱 아래·함수(apply 등)는 묻지 않음. 대화 상자가 떠 있는 동안 실험실 단축키 무시.
func _confirm(t, lab: LabMain, p: ParamPanel) -> void:
	var limit0 := p.confirm_discard_ticks
	t.check(limit0 == UiConfig.integer("param.confirm_discard_ticks") and limit0 > 0, "문턱 = ui.param.confirm_discard_ticks(%d)" % limit0)
	p.confirm_discard_ticks = 50
	var x := lab.experiments[0]
	(p.control("apply") as Button).pressed.emit()
	t.check(lab.experiments[0] != x and p.control("confirm_dialog") == null, "문턱 아래(틱 %d)면 묻지 않고 새 실험" % x.world.tick)
	x = lab.experiments[0]
	lab.step_ticks(60)
	(p.control("apply") as Button).pressed.emit()
	await t.frames(1)
	var dlg := p.control("confirm_dialog") as ConfirmationDialog
	t.check(dlg != null and dlg.visible and lab.experiments[0] == x and UiTheme.plain_text(dlg.dialog_text).contains("틱 60"),
			"틱 60 → 새 실험 단추가 먼저 물음: " + (UiTheme.plain_text(dlg.dialog_text) if dlg != null else ""))
	if dlg == null:
		p.confirm_discard_ticks = limit0
		return
	t.check(dlg.get_cancel_button().has_focus(), "기본 초점 = 취소(Enter 한 번에 버리지 않음)")
	var speed := lab.target_speed()
	_key(t, KEY_7, "7")
	t.check(lab._dialog_open() and dlg.visible and lab.target_speed() == speed, "묻는 동안 실험실 단축키(7 = 배속) 무시")
	dlg.get_cancel_button().pressed.emit()
	await t.frames(1)
	t.check(not dlg.visible and lab.experiments[0] == x and lab.world.tick == 60, "취소 → 지금 실험 그대로")
	(p.control("apply") as Button).pressed.emit()
	dlg.get_ok_button().pressed.emit()
	await t.frames(1)
	t.check(not dlg.visible and lab.experiments[0] != x and lab.world.tick == 0, "끝내기 → 새 실험(0틱)")
	# 함수 경로(apply)는 묻지 않음
	lab.step_ticks(60)
	x = lab.experiments[0]
	t.check(p.apply() == "" and lab.experiments[0] != x and not dlg.visible, "apply() 는 묻지 않음")
	# 비교 끄기: B 를 버리므로 B 가 오래 돌았으면 물음, 취소하면 단추는 켜진 채·비교 그대로
	p.set_compare_mode(true)
	t.check(p.apply_compare() == "" and lab.is_comparing(), "나란히 시작(함수)")
	lab.step_ticks(60)
	var btn := p.control("compare") as Button
	btn.button_pressed = false
	await t.frames(1)
	t.check(dlg.visible and lab.is_comparing() and btn.button_pressed and UiTheme.plain_text(dlg.dialog_text).contains("B 실험"),
			"비교 끄기 → 먼저 물음(단추 켜진 채): " + UiTheme.plain_text(dlg.dialog_text))
	dlg.get_cancel_button().pressed.emit()
	await t.frames(1)
	t.check(not dlg.visible and lab.is_comparing() and btn.button_pressed and p.is_compare_mode(), "취소 → 비교 그대로·단추 켜짐")
	# 나란히 시작 단추도 물음
	var a := lab.experiments[0]
	(p.control("start_compare") as Button).pressed.emit()
	t.check(dlg.visible and lab.experiments[0] == a, "나란히 시작 단추 → 먼저 물음")
	dlg.get_cancel_button().pressed.emit()
	await t.frames(1)
	btn.button_pressed = false
	dlg.get_ok_button().pressed.emit()
	await t.frames(1)
	t.check(not lab.is_comparing() and not p.is_compare_mode() and not btn.button_pressed and lab.experiments[0] == a, "끝내기 → B 를 버리고 A 계속")
	p.confirm_discard_ticks = limit0


## 가짜 실험실: 나란히 시작 단추가 start_compare(a, b) 를 패널 두 칸의 조건으로 부르는지, 끄면 stop_compare,
## 내보내기 단추가 default_export_dir() 에 쓰는지.
func _fake_lab(t) -> void:
	var fake := FakeLab.new()
	fake.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.root.add_child(fake)
	await t.frames(2)
	fake.set_process(false)
	var p := _attach(fake)
	await t.frames(2)
	(p.control("compare") as Button).button_pressed = true
	t.check((p.control("card:1") as Control).visible and (p.control("start_compare") as Control).visible, "가짜 실험실: B 칸·나란히 시작")
	_select_preset(p, "abundant", 1)
	p.set_value("seed", 9, 1)
	p.set_value("mutation.rate", 0.2, 1)
	p.set_value("population.initial", 120, 0)
	(p.control("start_compare") as Button).pressed.emit()
	t.check(fake.compare_calls.size() == 1, "나란히 시작 → start_compare 한 번")
	if fake.compare_calls.size() == 1:
		var a: Dictionary = fake.compare_calls[0][0]
		var b: Dictionary = fake.compare_calls[0][1]
		t.check(SimConfig.deep_equal(a, p.current_settings(0)) and SimConfig.deep_equal(b, p.current_settings(1)), "인자 = current_settings(0), current_settings(1)")
		t.check(str(b.preset) == "abundant" and int(b.seed) == 9 and (b.overrides as Dictionary).get("mutation.rate") == 0.2, "B 인자: 풍요·씨앗 9·돌연변이 0.2")
		t.check(str(a.preset) == "default" and (a.overrides as Dictionary).get("population.initial") == 120 and not (a.overrides as Dictionary).has("mutation.rate"), "A 인자: 기본·초기 개체 120")
	t.check(p.error_text().contains(FakeLab.FAKE_ERR), "start_compare 오류를 패널 안에")
	# 고급 설정 B 칸
	p.set_advanced_open(true)
	(p.control("adv_target:1") as Button).pressed.emit()
	t.check((p.control("adv:mutation.rate") as LineEdit).text == "0.2", "고급 설정 B 칸 보기")
	(p.control("adv_target:0") as Button).pressed.emit()
	t.check((p.control("adv:mutation.rate") as LineEdit).text == "0.05", "고급 설정 A 칸 보기")
	p.set_value("map.width", 4, 1)
	t.check((p.control("start_compare") as Button).disabled and p.apply_compare().begins_with("B") and fake.compare_calls.size() == 1, "B 오류면 나란히 시작 안 함")
	# 통합된 LabMain 이 새 실험 때 스스로 stop_compare 를 부를 수도 있으므로 끄기 직전 수와 견줌
	var stops0 := fake.stop_calls
	(p.control("compare") as Button).button_pressed = false
	t.check(fake.stop_calls == stops0 + 1 and not (p.control("card:1") as Control).visible, "비교 모드 끄기 → stop_compare 한 번")
	# CSV 내보내기 단추 → lab.export_csv(lab.default_export_dir())
	fake.export_dir = TMP_DIR.path_join("button_export")
	var abs_dir := ProjectSettings.globalize_path(fake.export_dir)
	_clean_dir(abs_dir)
	(p.control("export") as Button).pressed.emit()
	t.check(FileAccess.file_exists(abs_dir.path_join("timeseries.csv")) and FileAccess.file_exists(abs_dir.path_join("final.snapshot.json")), "CSV 내보내기 단추 → lab.default_export_dir() 에 결과 폴더")
	_clean_dir(abs_dir)
	# 오래 돈 실험 + 새 실험 단추 → "내보내고 끝내기" = 결과 폴더(lab.default_export_dir())를 내보낸 뒤 새 실험
	p.confirm_discard_ticks = 10
	fake.step_ticks(20)
	var fx := fake.experiments[0]
	(p.control("apply") as Button).pressed.emit()
	var dlg := p.control("confirm_dialog") as ConfirmationDialog
	t.check(dlg != null and dlg.visible and fake.experiments[0] == fx, "가짜 실험실: 틱 20 → 새 실험 단추가 먼저 물음")
	if dlg != null:
		(dlg.find_child("ExportButton", true, false) as Button).pressed.emit()
		await t.frames(1)
		t.check(FileAccess.file_exists(abs_dir.path_join("timeseries.csv")) and fake.experiments[0] != fx and not dlg.visible,
				"내보내고 끝내기 → 결과 폴더를 쓴 뒤 새 실험")
	_clean_dir(abs_dir)
	fake.queue_free()
	await t.frames(2)


## 폴더를 비운다(파일·하위 폴더, 검사 뒤 정리).
func _clean_dir(abs_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	var da := DirAccess.open(abs_dir)
	if da == null:
		return
	# 기록기가 만드는 .gdignore 같은 숨은 파일까지
	da.include_hidden = true
	for d in da.get_directories():
		_clean_dir(abs_dir.path_join(d))
	for f in da.get_files():
		DirAccess.remove_absolute(abs_dir.path_join(f))
	DirAccess.remove_absolute(abs_dir)
