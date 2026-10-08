extends RefCounted
## ParamPanel 검사: 기본값 = 기본 예설정, 예설정 바꾸기 → 세 칸, set_value + apply → 새 실험의 cfg, 잘못된 값 → 칸 아래 오류·
## 지금 실험 그대로, 되돌리기, 씨앗 범위·무작위(전역 난수·세계 그대로), 글 칸 입력 중 단축키 무시, 내보내기·스냅숏(대화 상자),
## 소리 확인 상자, 1280×720 왼쪽 자리 폭 안(가로 넘침 없음), 비교 모드(B 칸·나란히 시작 인자·끄면 stop_compare).
## 비교 시작 인자는 start_compare·stop_compare 를 가로채는 가짜 실험실(FakeLab)로 확인한다(통합 전 뼈대·통합 뒤 모두 통과).

const MIN_CHECKS := 119
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
	await _export(t, lab, p)
	await _snapshot(t, lab, p)
	await _sound(t, lab, p)
	await _real_compare(t, lab, p)
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
	var card_b := p.control("card:1") as Control
	t.check(card_b.visible and (p.control("start_compare") as Control).visible and not (p.control("apply") as Control).visible, "비교 모드: B 칸·나란히 시작 보임, 새 실험 숨음")
	p.set_compare_mode(false)
	p.set_advanced_open(false)
	await t.frames(1)
	t.check(not card_b.visible and (p.control("apply") as Control).visible, "비교 모드 끄면 B 칸 숨음")


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
	var added := false
	if snd == null:
		t.check(cb.disabled, "LabSound 가 없으면 소리 상자 못 씀")
		cb.button_pressed = true
		t.check(true, "LabSound 없이 눌러도 멈추지 않음")
		snd = LabSound.new()
		lab.add_child(snd)
		added = true
		await t.frames(2)
	else:
		t.check(true, "(통합 뒤) LabSound 있음")
		t.check(true, "(통합 뒤) 건너뜀")
	t.check(not cb.disabled and cb.button_pressed == snd.enabled, "LabSound 를 찾아 상태를 맞춤")
	cb.button_pressed = false
	t.check(snd.enabled == false, "끄면 LabSound.enabled = false")
	cb.button_pressed = true
	t.check(snd.enabled == true, "켜면 LabSound.enabled = true")
	if added:
		snd.queue_free()
		await t.frames(2)
		t.check(cb.disabled, "LabSound 가 사라지면 다시 못 씀")
	else:
		t.check(true, "(통합 뒤) 건너뜀")


## 진짜 실험실: 비교 모드 단추 → B 칸(A 를 베낌), 나란히 시작 → 뼈대면 오류 글, 통합 뒤면 비교 실험 둘.
func _real_compare(t, lab: LabMain, p: ParamPanel) -> void:
	# 패널 A = 지금 실험(스냅숏) 조건에서 시작
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
	if e != "":
		t.check(p.error_text().contains(e) and lab.experiments.size() == 1, "(뼈대) 나란히 시작 오류를 패널 안에: " + e)
		t.check(true, "(뼈대) 비교 실험 없음")
	else:
		t.check(lab.is_comparing() and lab.experiments.size() == 2, "(통합 뒤) 나란히 시작 → 실험 둘")
		t.check(p.now_text().contains("A ·") and p.now_text().contains("B ·") and float(_cfg(lab.experiments[1].world.cfg, "resources.scale")) == 1.6, "(통합 뒤) 지금 실험 A·B")
	btn.button_pressed = false
	await t.frames(1)
	t.check(not p.is_compare_mode() and not (p.control("card:1") as Control).visible and not lab.is_comparing(), "비교 모드 끄기 → B 칸 숨음·비교 끝")


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
