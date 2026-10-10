extends RefCounted
## ParamPanel 검사: 기본값 = 기본 예설정, 예설정 바꾸기 → 세 칸, set_value + apply → 새 실험의 cfg, 잘못된 값 → 칸 아래 오류·
## 지금 실험 그대로, 되돌리기, 씨앗 범위·무작위(전역 난수·세계 그대로), 글 칸 입력 중 단축키 무시, 내보내기·스냅숏(대화 상자),
## 소리 확인 상자, 1280×720 왼쪽 자리 폭 안(가로 넘침 없음)·주요 단추가 화면 안(고정 바닥), 비교 모드(진짜 실험실: 나란히
## 시작 → 실험 둘, 끄면 A 칸의 고친 값 유지), 입력 중인 칸 + 단추(A/B·되돌리기·예설정·새 실험) → 값이 제자리에·초점 풀림,
## 해석 못 한 글자 + 새 실험 → 시작 안 함, 범위 밖 씨앗의 실험, 오래 돈 실험을 버리는 단추 → 확인 대화 상자, 고급 설정
## 한국어 이름표·말풍선, 실수 글자 = JSON 글자, 슬라이더 한 번의 갱신 몫(견준 수·말풍선 수).
## 검토 고침(g4): 씨앗 칸 = 글 칸 + 정수 해석(실제 키 Enter·실제 마우스 클릭·초점 빠짐 모두 같은 규칙, 64비트 씨앗 그대로),
## 고급 설정 0·범위("(검사)") → 줄 아래 오류, 비교 중 저장의 -A/-B 덮어쓰기 물음, 저장 대화 상자 동안 멈춤(이름 틱 = 내용 틱),
## 열기 대화 상자의 "열기" 단추, 단추·고르기 상자 키보드 초점(Tab·Enter, 스페이스 = 멈춤), 웹 내려받기 실패 알림 하나,
## 확인 대화 상자 모양·틱 쉼표, 무작위가 세계 상태(스냅숏 글)를 바꾸지 않음, 화면 글의 글자 범위(나눔고딕 두 굵기 — J17)·
## 두뇌 열지도 범례 끝 글(weight_clamp 를 반올림하지 않음 — I44).
## 비교 시작 인자는 start_compare·stop_compare 를 가로채는 가짜 실험실(FakeLab)로도 확인한다(패널 단위 — 종단은 integration4_checks).

const MIN_CHECKS := 262
## 임시 폴더는 프로세스마다 따로(저장소 사본 여럿에서 함께 돌려도 서로 지우지 않게 — I37, run_tests.tmp_dir 와 같은 규칙)
var TMP_DIR := "user://test_param-%d" % OS.get_process_id()
var SNAP_PATH := TMP_DIR.path_join("snap.json")
const MAIN_KEYS: Array[String] = ["mutation.rate", "resources.scale", "population.initial"]
## 0 으로 나누는 설정 키(I01). SimConfig.validate 가 모두 막으므로(검토 고침 g1a — sim-labels 범위가 "(검사)") 고급 설정에 0 을
## 적으면 그 줄 아래 오류여야 하고, 패널의 오류는 언제나 SimConfig.build 의 오류와 같아야 한다.
const ZERO_DIVISOR_KEYS: Array[String] = ["map.noise_cell", "map.noise_detail_cell", "map.rock_noise_cell", "carry.max",
		"plants.max_food", "sense.crowd_norm", "store.capacity", "body.energy_per_size", "brain.weight_clamp"]
## "(검사)" 범위 수 키의 최소 수(검토 고침 g1a 뒤 모든 수 키의 범위가 검사 — 병합 때 68개, 예전 23개)
const CHECKED_RANGE_MIN := 60
const INT64_MAX := 9223372036854775807
const INT64_MIN := -9223372036854775807 - 1
## 2^53 + 1: 실수(float64)로는 정확히 못 적는 첫 정수(예전 SpinBox 칸은 …992 로 보였음 — J18)
const SEED_2P53_PLUS1 := 9007199254740993
## 글자 범위 검사(J17): 앱 글꼴(보통·굵게)과 화면에 나올 수 있는 글이 있는 곳(스크립트는 주석 아닌 줄)
const FONT_FILES: Array[String] = ["res://assets/fonts/NanumGothic-Regular.ttf", "res://assets/fonts/NanumGothic-Bold.ttf"]
const FONT_SCAN_DIRS: Array[String] = ["res://scripts/ui", "res://scripts/view", "res://scripts/sim", "res://scenes", "res://config"]
const FONT_SCAN_EXT: Array[String] = ["gd", "tscn", "json"]
## 다른 묶음이 고치기로 한 파일을 잠시 건너뛰는 목록(지금은 없음 — config/sim-labels.json 말풍선의 '−'(U+2212)는 병합 때
## '-' 로 고침). 목록의 파일에서 없는 글자가 사라지면 목록에서 지우라고 실패한다(목록이 남아 검사가 줄어든 채 잊히지 않게).
const FONT_PENDING: Array[String] = []


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

	## 웹 내려받기 실패 검사(I40): zip 묶기가 실패한 것처럼(공용 user://downloads 에 쓰지 않음)
	var zip_fail := false

	func results_zip_bytes() -> PackedByteArray:
		return PackedByteArray() if zip_fail else super()


func run(t) -> void:
	var root_size: Vector2i = t.root.size
	t.root.size = Vector2i(UiConfig.integer("lab.min_width"), UiConfig.integer("lab.min_height"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(2)
	lab.set_process(false)
	var p := _attach(lab)
	p.snapshot_dir = TMP_DIR.path_join("snapshots")
	await t.frames(3)
	_defaults(t, lab, p)
	_presets(t, p)
	await _layout(t, lab, p)
	_apply(t, lab, p)
	_invalid(t, lab, p)
	_revert(t, lab, p)
	await _advanced_zero(t, lab, p)
	_checked_ranges(t, lab, p)
	_seed(t, lab, p)
	await _typing(t, lab, p)
	await _pending_edits(t, lab, p)
	await _bad_text(t, lab, p)
	await _seed_enter(t, lab, p)
	await _seed_click(t, lab, p)
	_labels(t, p)
	_font_coverage(t)
	await _brain_legend(t)
	_float_text(t, p)
	_refresh_cost(t, lab, p)
	await _export(t, lab, p)
	await _snapshot(t, lab, p)
	await _save_hold(t, lab, p)
	await _open_button(t, lab, p)
	await _sound(t, lab, p)
	await _seed_range(t, lab, p)
	await _big_seeds(t, lab, p)
	await _keyboard(t, lab, p)
	await _real_compare(t, lab, p)
	await _compare_save(t, lab, p)
	await _engine_overwrite(t, lab, p)
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
		# 최소 창(1280×640)·자리 펼침: 주요 단추(새 실험/나란히 시작)·되돌리기·비교 모드 단추가 스크롤하지 않아도 화면 안
		# (예전에는 비교 모드를 켜면 B 칸이 끼어 나란히 시작·비교 끄기 단추가 스크롤 아래로 밀려 안 보였음)
		var main_btn := p.control("apply" if state == "보통" else "start_compare") as Control
		t.check(_on_screen(t, main_btn) and _on_screen(t, p.control("compare") as Control) and _on_screen(t, p.control("revert") as Control),
				"[%s] 주요 단추·비교 모드 단추가 화면 안(스크롤 없이) %s" % [state, str(main_btn.get_global_rect())])
		var nt := p.control("next_title") as Label
		t.check(nt.is_visible_in_tree() and UiTheme.plain_text(nt.text) == (ParamPanel.TEXT_NEXT if state == "보통" else ParamPanel.TEXT_NEXT_COMPARE),
				"[%s] 다음 실험 제목 보임: %s" % [state, UiTheme.plain_text(nt.text)])
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
	# 자동 줄바꿈 글(상태 줄·줄 아래·바닥 오류·다음 실험 제목·고급 설정 안내)은 낱말 단위로 접음(UiTheme.keep_words — 검토 I49:
	# 예전엔 정보 창만 맞춰, 패널 글은 좁은 폭에서 "범/위" 처럼 한글 낱말 가운데서 끊겼음)
	var split := _split_words(p)
	t.check(split.is_empty() and p.row_error("map.width", 0, true) != "", "자동 줄바꿈 글은 낱말 단위(keep_words) — 잇개 없는 글: %s" % str(split))
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


## 패널 안 보이는 자동 줄바꿈 Label 가운데 낱말 잇개(UiTheme.keep_words) 없이 넣은 글(잇개를 뺀 글)
static func _split_words(root: Node) -> Array[String]:
	var out: Array[String] = []
	for n in root.find_children("*", "Label", true, false):
		var l := n as Label
		if l.is_visible_in_tree() and l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.text.strip_edges().length() > 1 \
				and l.text != UiTheme.keep_words(UiTheme.plain_text(l.text)):
			out.append(UiTheme.plain_text(l.text))
	return out


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


## 고급 설정에 0 을 실제 키로 적고 Enter: SimConfig.build 가 거부하는 값이면 그 줄 아래 오류·새 실험 단추 꺼짐·지금 실험
## 그대로(I01 — 패널 검사 = SimConfig.build 그대로). 0 으로 나누는 키(ZERO_DIVISOR_KEYS)는 이름표 범위가 "(검사)" 면 반드시
## 줄 아래 오류(검토 고침 g1a 의 검사 규칙으로 모두 막힘 — 검사), 패널 오류 = SimConfig.build 오류.
func _advanced_zero(t, lab: LabMain, p: ParamPanel) -> void:
	var x := lab.experiments[0]
	p.set_advanced_open(true)
	await t.frames(1)
	var le := p.control("adv:population.cap") as LineEdit
	(p.control("scroll") as ScrollContainer).ensure_control_visible(le)
	await _type_into(t, le, "0")
	_key(t, KEY_ENTER)
	var s := p.current_settings(0)
	var want := str(SimConfig.build(str(s.preset), s.overrides).error)
	var got := p.row_error("population.cap", 0, true)
	t.check(want != "" and got == want and got.contains("population.cap") and int((s.overrides as Dictionary).get("population.cap", -1)) == 0,
			"고급 설정 population.cap 에 0 + Enter → 그 줄 아래 SimConfig 오류: %s" % got)
	t.check((p.control("apply") as Button).disabled and p.apply() != "" and lab.experiments[0] == x, "0 이 거부되면 새 실험 못 함·지금 실험 그대로")
	var cap_now: Variant = SimConfig.get_value(lab.world.cfg, "population.cap")
	p.set_value("population.cap", cap_now)
	# 0 으로 나누는 키: 패널 오류 = SimConfig.build 오류, "(검사)" 범위면 거부
	var same: Array[String] = []
	var rejected: Array[String] = []
	var passing: Array[String] = []
	for key in ZERO_DIVISOR_KEYS:
		p.set_value(key, "0")
		var sk := p.current_settings(0)
		var wk := str(SimConfig.build(str(sk.preset), sk.overrides).error)
		var gk := p.row_error(key, 0, true)
		# 이름표 범위가 "(검사)" 이고 0 이 그 범위 밖이면 반드시 거부(검토 고침 g1a 뒤 "1 이상 (검사)"·"0 초과 (검사)" 등)
		var rng := str(ParamPanel.key_label(key).get("range", ""))
		var must := rng.contains("(검사)") and _outside_range(rng, 0.0) == 1
		if gk != wk or (must and (gk == "" or not gk.contains(key))):
			same.append("%s(패널 \"%s\" / build \"%s\")" % [key, gk, wk])
		(rejected if wk != "" else passing).append(key)
		p.set_value(key, SimConfig.get_value(lab.world.cfg, key))
	t.check(same.is_empty(), "0 으로 나누는 키 0 → 패널 줄 아래 오류 = SimConfig.build 오류(\"(검사)\" 범위면 거부) %s" % "; ".join(same))
	# 검토 고침 g1a 병합 뒤: 0 으로 나누는 키는 모두 SimConfig 가 거부(범위 "0 초과"·"1~…")
	t.check(passing.is_empty() and rejected.size() == ZERO_DIVISOR_KEYS.size(),
			"0 으로 나누는 키 %d개 모두 SimConfig 가 거부(받아들인 키: %s)" % [ZERO_DIVISOR_KEYS.size(), ", ".join(passing)])
	t.check(p.status_text() == ParamPanel.TEXT_SAME and p.row_error("population.cap", 0, true) == "", "되돌려 적으면 줄 아래 오류 없음·지금 실험과 같음: " + p.status_text())
	p.set_advanced_open(false)


## 이름표 범위에 "(검사)" 가 붙은 수 키: 말풍선이 그 범위를 보이고, 범위 바로 밖 값을 적으면 그 줄 아래 오류(말풍선 범위 =
## 실제 검사 범위, I01). "a~b"·"N 이상"·"N 초과" 꼴을 읽는다("size_min~size_max" 같은 관계 범위는 뺌) — 검토 고침 g1a 가
## 범위를 모두 "(검사)" 로 바꾸면 그 키들도 여기서 함께 본다.
func _checked_ranges(t, lab: LabMain, p: ParamPanel) -> void:
	p.set_advanced_open(true)
	var bad: Array[String] = []
	var keys := 0
	for key in ParamPanel.leaf_keys():
		var kind := ParamPanel.leaf_kind(key)
		if kind != ParamPanel.KIND_INT and kind != ParamPanel.KIND_FLOAT:
			continue
		var rng := str(ParamPanel.key_label(key).get("range", ""))
		if not rng.contains("(검사)"):
			continue
		var outs := _outside_values(rng, kind == ParamPanel.KIND_INT)
		if outs.is_empty():
			continue
		keys += 1
		var tip := (p.control("adv_name:" + key) as Label).tooltip_text
		if not tip.contains("범위 " + rng):
			bad.append("%s 말풍선에 범위 없음" % key)
		for v in outs:
			p.set_value(key, v)
			if not p.row_error(key, 0, true).contains(key):
				bad.append("%s=%s 오류 없음(%s)" % [key, v, p.row_error(key, 0, true)])
		p.set_value(key, SimConfig.get_value(lab.world.cfg, key))
	t.check(keys >= CHECKED_RANGE_MIN and bad.is_empty(), "\"(검사)\" 범위 키 %d개: 말풍선 범위 = 검사 범위(바로 밖 값 → 그 줄 아래 오류) %s" % [keys, "; ".join(bad)])
	t.check(p.status_text() == ParamPanel.TEXT_SAME, "되돌려 적으면 지금 실험과 같음: " + p.status_text())
	p.set_advanced_open(false)


## 범위 글("a~b (검사)"·"N 이상 (검사)"·"N 초과 (검사)") → {lo, hi, lo_open}("" = 끝 없음). 수가 아닌 범위면 {}.
func _range_parts(rng: String) -> Dictionary:
	var body := rng.replace("(검사)", "").strip_edges()
	var r := {lo = "", hi = "", lo_open = false}
	if body.contains("~"):
		r.lo = body.get_slice("~", 0).strip_edges()
		r.hi = body.get_slice("~", 1).strip_edges()
	elif body.ends_with("이상"):
		r.lo = body.trim_suffix("이상").strip_edges()
	elif body.ends_with("초과"):
		r.lo = body.trim_suffix("초과").strip_edges()
		r.lo_open = true
	else:
		return {}
	for b: String in [r.lo, r.hi]:
		if b != "" and not b.is_valid_float():
			return {}
	return r


## 값이 범위 글 밖이면 1, 안이면 0, 읽을 수 없는 범위면 -1.
func _outside_range(rng: String, v: float) -> int:
	var r := _range_parts(rng)
	if r.is_empty():
		return -1
	var lo := str(r.lo)
	var hi := str(r.hi)
	if lo != "" and (v < lo.to_float() or (bool(r.lo_open) and v == lo.to_float())):
		return 1
	if hi != "" and v > hi.to_float():
		return 1
	return 0


## 범위 글의 바로 밖 값들(글자). 수가 아닌 범위면 [].
func _outside_values(rng: String, integer: bool) -> Array[String]:
	var out: Array[String] = []
	var r := _range_parts(rng)
	if r.is_empty():
		return out
	var lo := str(r.lo)
	var hi := str(r.hi)
	var lo_open := bool(r.lo_open)
	if lo != "":
		var a := lo.to_float()
		if lo_open:
			out.append(_num_text(a, integer))
		out.append(_num_text(a - _step_out(a, integer), integer))
	if hi != "":
		var z := hi.to_float()
		out.append(_num_text(z + _step_out(z, integer), integer))
	return out


static func _step_out(v: float, integer: bool) -> float:
	return 1.0 if integer else maxf(absf(v) * 0.001, 0.001)


static func _num_text(v: float, integer: bool) -> String:
	return str(roundi(v)) if integer else String.num(v)


## 씨앗 = 64비트 정수 그대로(실험실·실행기·스냅숏과 같이 자르지 않음). 칸은 글 칸(LineEdit) — 실수 SpinBox 가 아님(J18).
func _seed(t, lab: LabMain, p: ParamPanel) -> void:
	var smax := UiConfig.integer("param.seed_max")
	var sle := p.control("seed:0") as LineEdit
	t.check(sle != null, "씨앗 칸 = 글 칸(LineEdit — 실수 SpinBox 의 식 계산·반올림 없음)")
	if sle == null:
		return
	p.set_value("seed", -5)
	t.check(int(p.current_settings(0).seed) == -5 and sle.text == "-5", "음수 씨앗도 그대로(-5, 칸 \"%s\")" % sle.text)
	p.set_value("seed", smax + 10)
	t.check(int(p.current_settings(0).seed) == smax + 10 and sle.text == str(smax + 10), "ui.param.seed_max 보다 큰 씨앗도 그대로(칸 %s)" % sle.text)
	t.check(p.set_value("seed", "열둘") != "" and int(p.current_settings(0).seed) == smax + 10, "정수가 아닌 씨앗 거부")
	t.check(p.set_value("seed", str(INT64_MAX)) == "" and int(p.current_settings(0).seed) == INT64_MAX
			and p.set_value("seed", str(INT64_MIN)) == "" and int(p.current_settings(0).seed) == INT64_MIN, "64비트 끝 씨앗(글자) 그대로")
	var over := p.set_value("seed", "9223372036854775808")
	var under := p.set_value("seed", "-9223372036854775809")
	t.check(over.contains("사이 정수") and under.contains("사이 정수") and int(p.current_settings(0).seed) == INT64_MIN,
			"64비트 밖 씨앗 → 오류(엔진이 넘치는 수를 자르지 않게): %s" % over)
	# 정수 설정 칸도 64비트를 넘는 글을 to_int 하지 않는다(엔진 ERROR 줄·INT64_MIN 대신 적은 값 그대로 범위 문장 — 검토 최종 확인)
	var bigs: Array[String] = []
	for big: String in ["100000000000000000000", "1e20", "-1e20"]:
		var be := p.set_value("time.day_ticks", big)
		if not (be.contains("time.day_ticks = %s:" % str(big.to_float())) and be.contains("범위") and not be.contains(str(INT64_MIN))):
			bigs.append("%s → %s" % [big, be])
	t.check(bigs.is_empty(), "정수 칸의 64비트 밖 글 → 그 값 그대로 범위 오류(어긋난 것: %s)" % ", ".join(bigs))
	t.check(p.set_value("seed", 42.7) != "" and p.set_value("seed", 3e9) == "" and int(p.current_settings(0).seed) == 3000000000,
			"실수 씨앗: 소수는 오류, 정수 값(3e9)은 그 정수")
	t.check(p.set_value("seed", " +4321 ") == "" and int(p.current_settings(0).seed) == 4321 and sle.text == "4321", "글자 \" +4321 \" → 4321")
	# 무작위: 범위 안(0~ui.param.seed_max), 세계·전역 난수 그대로. 세계는 상태 전체(스냅숏 글)로 견준다 — 역사 해시는
	# hash.every 틱마다만 바뀌므로 틱을 진행하지 않은 채 해시를 견주면 상태를 바꿔도 잡지 못함(I89, VIEW-API 검사 규칙)
	var x := lab.experiments[0]
	var tick := lab.world.tick
	var state := SimSnapshot.to_text(lab.world)
	seed(12345)
	var r1 := randi()
	seed(12345)
	var ok := true
	for i in 5:
		(p.control("random:0") as Button).pressed.emit()
		var v := int(p.current_settings(0).seed)
		ok = ok and v >= 0 and v <= smax and sle.text == str(v)
	t.check(ok, "무작위 씨앗은 0~seed_max")
	t.check(randi() == r1, "무작위가 Godot 전역 난수를 건드리지 않음")
	t.check(lab.experiments[0] == x and lab.world.tick == tick and SimSnapshot.to_text(lab.world) == state,
			"무작위가 세계를 건드리지 않음(상태 전체 = 스냅숏 글이 같음)")
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
	var le := p.control("seed:0") as LineEdit
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


## 글자를 실제 키 입력으로(초점 있는 칸에 들어감). 숫자·점·쉼표·빼기·더하기·곱하기·영문 소문자·빈칸.
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
		elif ch == "+":
			code = KEY_PLUS
		elif ch == "*":
			code = KEY_ASTERISK
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
	await _type_into(t, p.control("seed:0") as LineEdit, "5")
	(p.control("random:0") as Button).pressed.emit()
	t.check(_focus_owner(p) == null and str(p.current_settings(0).seed) == (p.control("seed:0") as LineEdit).text, "무작위 단추 → 초점 풀림·씨앗 칸 = 고른 씨앗")
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
	# 씨앗 칸: 예전 SpinBox 가 말없이 되돌리던 글자
	await _type_into(t, p.control("seed:0") as LineEdit, "42 f")
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


## 씨앗 칸 + 실제 키 Enter: 해석할 수 없는 글자(글자 섞임·식·소수·16진·지수)는 모두 그 줄 아래 오류, 씨앗 그대로(I14 —
## 예전 SpinBox 는 패널이 오류를 낸 뒤 지연된 식 계산이 "42 f"→42·"2+3"→5·"7*6"→42·"0x10"→16·"1e3"→1000·"42.7"→43 으로
## 오류를 지우고 씨앗을 바꿨음). 초점이 빠질 때도 같은 규칙.
func _seed_enter(t, lab: LabMain, p: ParamPanel) -> void:
	var sle := p.control("seed:0") as LineEdit
	var seed0 := int(p.current_settings(0).seed)
	var leaked: Array[String] = []
	for txt in ["42 f", "2+3", "7*6", "42.7", "0x10", "1e3", "12abc"]:
		await _type_into(t, sle, txt)
		_key(t, KEY_ENTER)
		# 지연 호출(예전 SpinBox 의 식 계산)까지 지나게
		await t.frames(2)
		var sv := int(p.current_settings(0).seed)
		var err := p.row_error("seed")
		if sv != seed0 or not err.contains("정수") or sle.text != str(seed0) or sle.has_focus():
			leaked.append("\"%s\" → 씨앗 %d·칸 \"%s\"·오류 \"%s\"" % [txt, sv, sle.text, err])
	t.check(leaked.is_empty(), "씨앗 칸 + Enter: 해석 못 할 글자는 모두 줄 아래 오류·씨앗 %d 그대로 %s" % [seed0, "; ".join(leaked)])
	await _type_into(t, sle, "+77")
	_key(t, KEY_ENTER)
	await t.frames(2)
	t.check(int(p.current_settings(0).seed) == 77 and sle.text == "77" and p.row_error("seed") == "", "\"+77\" + Enter → 씨앗 77·오류 지워짐")
	await _type_into(t, sle, "2+3")
	sle.release_focus()
	await t.frames(2)
	t.check(int(p.current_settings(0).seed) == 77 and sle.text == "77" and p.row_error("seed").contains("정수"), "초점이 빠져도 \"2+3\" → 오류·씨앗 77 그대로")
	p.set_value("seed", seed0)
	t.check(p.status_text() == ParamPanel.TEXT_SAME and p.row_error("seed") == "", "다시 지금 실험 씨앗: " + p.status_text())


func _click(t, pos: Vector2) -> void:
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = pos
		mb.global_position = pos
		t.root.push_input(mb)


## 칸을 스크롤해 보이게 한 뒤 실제 마우스로 누르고, 키로 적는다(Enter 없음).
func _click_type(t, p: ParamPanel, le: LineEdit, text: String) -> void:
	(p.control("scroll") as ScrollContainer).ensure_control_visible(le)
	await t.frames(2)
	_click(t, le.get_global_rect().get_center())
	await t.frames(1)
	# 실제 앱에서는 마우스를 뗄 때 select_all_on_focus 가 글자 전체를 고른다(push_input 은 Input 의 단추 상태를 바꾸지 않아
	# 엔진이 누르는 순간 고른 뒤 누른 자리에 커서를 둠 — 그래서 직접 고름)
	le.select_all()
	_type(t, text)


## 실제 마우스: 칸에 해석할 수 없는 글자를 적은 채(Enter 없음) "새 실험" 단추를 누르면 — LabMain 이 그 누름에서 칸 초점을 풀어
## 확정하므로 단추 신호 전에 이미 확정됨 — 시작하지 않고 그 줄 아래 오류 + "입력 오류"(I14: 예전 씨앗 칸은 LabMain 이
## SpinBox.apply() 로 "42 f" 를 42 로 계산해 씨앗 42 로 새 실험이 시작됐고, 숫자 칸은 옛 값으로 시작하고 오류가 사라졌음).
## 지도를 누르면 확정만(오류 보임·값 그대로) — 그 뒤 새 실험 단추는 지금 값으로 시작.
func _seed_click(t, lab: LabMain, p: ParamPanel) -> void:
	lab.set_paused(true)
	var x := lab.experiments[0]
	var seed0 := lab.world.seed_value
	var sle := p.control("seed:0") as LineEdit
	var apply_c := (p.control("apply") as Control).get_global_rect().get_center()
	await _click_type(t, p, sle, "42 f")
	t.check(sle.has_focus() and sle.text == "42 f", "씨앗 칸을 눌러 \"42 f\" 입력(%s)" % sle.text)
	_click(t, apply_c)
	await t.frames(2)
	t.check(lab.experiments[0] == x and lab.world.seed_value == seed0, "\"42 f\" + 새 실험 단추 클릭 → 시작 안 함(씨앗 %d)" % lab.world.seed_value)
	t.check(p.row_error("seed").contains("정수") and p.error_text().contains("입력 오류") and not sle.has_focus() and sle.text == str(seed0),
			"클릭 → 씨앗 줄 아래 오류·패널 \"입력 오류\": %s / %s" % [p.row_error("seed"), p.error_text()])
	var f := p.control("field:mutation.rate:0") as LineEdit
	var rate0 := float(SimConfig.get_value(lab.world.cfg, "mutation.rate"))
	await _click_type(t, p, f, "0,07")
	_click(t, apply_c)
	await t.frames(2)
	t.check(lab.experiments[0] == x and p.row_error("mutation.rate").contains("수가 아닙니다") and p.error_text().contains("입력 오류")
			and float(SimConfig.get_value(lab.world.cfg, "mutation.rate")) == rate0, "숫자 칸 \"0,07\" + 새 실험 단추 클릭 → 시작 안 함·줄 아래 오류")
	# 지도를 누르면 확정만 — 오류는 보이고 값 그대로, 그 뒤 새 실험 단추는 지금 값으로 시작
	await _click_type(t, p, sle, "9x")
	_click(t, lab._map_container.get_global_rect().get_center())
	await t.frames(2)
	t.check(lab.experiments[0] == x and p.row_error("seed").contains("정수") and int(p.current_settings(0).seed) == seed0, "지도 클릭 → 확정(오류 보임·씨앗 그대로)")
	_click(t, apply_c)
	await t.frames(2)
	t.check(lab.experiments[0] != x and lab.world.seed_value == seed0 and p.status_text() == ParamPanel.TEXT_SAME,
			"그 뒤 새 실험 단추 클릭 → 지금 값(씨앗 %d)으로 새 실험" % lab.world.seed_value)


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


## 글자 범위(검토 J17 — 이전 저장소 test_font_coverage 를 옮김): 화면에 나올 수 있는 글(scripts/ui·view·sim 의 주석 아닌 줄,
## scenes, config/*.json — 설정 말풍선 sim-labels·화면 문자열 ui.json)의 모든 글자가 나눔고딕 보통·굵게 둘 다에 있는지.
## 데스크톱은 시스템 글꼴이 대신 그려 가려지지만 웹 빌드에는 대체 글꼴이 없어 네모로 보인다(두뇌 범례 '−' U+2212 가 그랬음).
func _font_coverage(t) -> void:
	var fonts: Array[FontFile] = []
	for f in FONT_FILES:
		fonts.append(load(f) as FontFile)
	t.check(fonts.size() == 2 and fonts.all(func(f: FontFile) -> bool: return f != null), "앱 글꼴 둘(보통·굵게)")
	var files := PackedStringArray()
	for dir in FONT_SCAN_DIRS:
		for f in DirAccess.get_files_at(dir):
			if FONT_SCAN_EXT.has(f.get_extension()):
				files.append(dir.path_join(f))
	var missing := {}
	var pending_bad := {}
	for path in files:
		var bad := font_missing(FileAccess.get_file_as_string(path), path.get_extension() == "gd", fonts)
		if FONT_PENDING.has(path):
			pending_bad[path] = bad
		elif not bad.is_empty():
			missing[path] = bad
	t.check(files.size() > 20 and missing.is_empty(), "화면 글 %d파일의 모든 글자가 글꼴 둘에 있음(없음: %s)" % [files.size(), str(missing)])
	# 보류 파일은 검사 하나로(목록이 비어도 검사 수가 같게): 모두 아직 없는 글자가 있어야 함 — 고쳐진 파일은 목록에서 지울 것
	var fixed := PackedStringArray()
	for path in FONT_PENDING:
		print("  (참고) 글자 범위 보류(다른 묶음이 고침): %s %s" % [path, str(pending_bad.get(path, "파일 없음"))])
		if (pending_bad.get(path, "") as String).is_empty():
			fixed.append(path)
	t.check(fixed.is_empty(), "보류 파일(%d개)에 아직 없는 글자가 있음(고쳐졌으면 FONT_PENDING 에서 지울 것: %s)" % [FONT_PENDING.size(), ", ".join(fixed)])
	t.check(font_missing("두뇌 −4", false, fonts) == "U+2212" and font_missing("# −4\n-4 ±·…—", true, fonts) == "", "글자 검사 자체: '−' 는 없음, 주석 줄은 건너뜀")


## text 의 글자 가운데 fonts 어느 하나라도 없는 것("U+XXXX" 들, 공백으로 이음). is_script 면 주석 줄(# 로 시작)은 건너뜀.
static func font_missing(text: String, is_script: bool, fonts: Array[FontFile]) -> String:
	var body := text
	if is_script:
		var kept := PackedStringArray()
		for ln in text.split("\n"):
			if not ln.strip_edges().begins_with("#"):
				kept.append(ln)
		body = "\n".join(kept)
	var seen := {}
	for i in body.length():
		var c := body.unicode_at(i)
		if c < 32 or seen.has(c):
			continue
		seen[c] = true
		for f in fonts:
			if not f.has_char(c):
				seen[c] = false
				break
	var out := PackedStringArray()
	for c: int in seen:
		if not seen[c]:
			out.append("U+%04X" % c)
	return " ".join(out)


## 두뇌 열지도 범례(검토 I44·J17): 상한 brain.weight_clamp(고급 설정의 실수 키)를 반올림하지 않고 그대로("%.0f" 는 2.5 →
## "±2", 0.5 → "±0" 이라 색 눈금과 어긋났음), 빼기는 글꼴에 있는 '-'(U+002D). 실제 그린 범례 글(last_legend)로 본다.
func _brain_legend(t) -> void:
	var want := {2.5: ["-2.5", "+2.5"], 0.5: ["-0.5", "+0.5"], 4.0: ["-4", "+4"]}
	for wc: float in want:
		var w: SimWorld = t.make_world({"brain.weight_clamp": wc}, 1)
		if w == null:
			t.check(false, "brain.weight_clamp %s 세계" % str(wc))
			continue
		var bv := BrainView.new()
		bv.weight_clamp = float(w.cfg.brain.weight_clamp)
		bv.set_genome(w.L, w.slime_info(w.s_id[0]).genome)
		t.root.add_child(bv)
		await t.frames(2)
		var got := bv.last_legend
		t.check(got == PackedStringArray(want[wc]) and UiTheme.has_glyphs("".join(got)),
				"두뇌 범례 끝(weight_clamp %s) = %s (그린 것 %s)" % [str(wc), str(want[wc]), str(got)])
		bv.queue_free()
	await t.frames(1)


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
	var base := ProjectSettings.globalize_path(p.snapshot_dir).trim_suffix("/")
	(p.control("save") as Button).pressed.emit()
	await t.frames(1)
	var sd := p.control("save_dialog") as FileDialog
	t.check(sd != null and sd.visible, "스냅숏 저장 → 대화 상자")
	if sd == null:
		return
	t.check(sd.file_mode == FileDialog.FILE_MODE_SAVE_FILE and sd.access == FileDialog.ACCESS_FILESYSTEM and "*.json" in ",".join(sd.filters), "저장 대화 상자: 파일 저장·파일 시스템·*.json")
	t.check(ParamPanel.SNAPSHOT_DIR == "user://experiments" and sd.current_dir.trim_suffix("/") == base and DirAccess.dir_exists_absolute(base)
			and base.contains("test_param-%d" % OS.get_process_id()),
			"시작 폴더 = snapshot_dir(실험실 기본 user://experiments, 검사는 프로세스 임시 폴더 — 공용 폴더를 만들지 않음): %s" % sd.current_dir)
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


## 재생 중 스냅숏 저장: 대화 상자가 떠 있는 동안 실험실을 멈춰 기본 이름의 틱 = 파일 안 틱(J06 — 예전에는 그사이 실험이
## 돌아 4배로 2초면 50틱 어긋남). 닫히면(저장·취소) 다시 재생, 원래 멈춰 있었으면 그대로.
func _save_hold(t, lab: LabMain, p: ParamPanel) -> void:
	lab.step_ticks(12)
	lab.set_paused(false)
	lab.set_speed(4)
	(p.control("save") as Button).pressed.emit()
	await t.frames(1)
	var sd := p.control("save_dialog") as FileDialog
	var tick0 := lab.world.tick
	t.check(sd != null and sd.visible and lab.is_paused(), "재생 중 저장 단추 → 대화 상자 동안 멈춤")
	if sd == null:
		return
	for i in 60:
		lab.advance_frame(1.0 / 60.0)
	var fname := sd.current_file
	var path := ProjectSettings.globalize_path(p.snapshot_dir).path_join(fname)
	sd.get_ok_button().pressed.emit()
	await t.frames(1)
	var r := SimSnapshot.load_file(path)
	var ftick: int = r.world.tick if r.world != null else -1
	t.check(not sd.visible and ftick == tick0 and fname.contains("-tick%d." % ftick),
			"기본 이름의 틱 = 파일 안 틱(%s / 파일 틱 %d)" % [fname, ftick])
	t.check(not lab.is_paused(), "저장하고 닫히면 다시 재생")
	(p.control("save") as Button).pressed.emit()
	await t.frames(1)
	t.check(lab.is_paused(), "다시 저장 단추 → 멈춤")
	sd.get_cancel_button().pressed.emit()
	await t.frames(1)
	t.check(not sd.visible and not lab.is_paused(), "취소 → 다시 재생")
	lab.set_paused(true)
	(p.control("save") as Button).pressed.emit()
	await t.frames(1)
	sd.get_cancel_button().pressed.emit()
	await t.frames(1)
	t.check(lab.is_paused(), "멈춰 있었으면 닫힌 뒤에도 멈춤")
	lab.set_speed(1)


## 스냅숏 열기 대화 상자: 폴더에 내보내기 하위 폴더가 있어도 가장 최근 스냅숏을 골라 둔 채 열려 "열기" 단추가 켜져 있고, 그
## 단추로 열린다. 스냅숏이 없는 폴더(하위 폴더만)에서 이름(경로)을 쳐도 "열기" 가 켜진다(J20 — 예전에는 폴더 줄이 골라진 채
## 열려 이름을 쳐도 꺼진 채였음, 엔진 대화 상자).
func _open_button(t, lab: LabMain, p: ParamPanel) -> void:
	lab.set_paused(true)
	var dir := ProjectSettings.globalize_path(p.snapshot_dir)
	DirAccess.make_dir_recursive_absolute(dir.path_join("20261010-103624-seed1"))
	var snap := dir.path_join("snapA.json")
	lab.step_ticks(5)
	t.check(p.save_snapshot_to(snap) == "", "snapA.json 저장")
	var tick0 := lab.world.tick
	lab.step_ticks(10)
	(p.control("open") as Button).pressed.emit()
	await t.frames(2)
	var od := p.control("open_dialog") as FileDialog
	t.check(od != null and od.visible and od.current_file.ends_with(".json") and not od.get_ok_button().disabled,
			"하위 폴더가 있어도 최근 스냅숏(%s)이 골라진 채 열림 — 열기 단추 켜짐" % (od.current_file if od != null else ""))
	if od == null:
		return
	od.get_line_edit().text = "snapA.json"
	od.get_line_edit().text_changed.emit("snapA.json")
	od.get_ok_button().pressed.emit()
	await t.frames(1)
	t.check(not od.visible and lab.world.tick == tick0 and lab.experiments[0].snapshot_path.ends_with("snapA.json"),
			"이름 snapA.json + 열기 단추 → 열림(틱 %d)" % lab.world.tick)
	# 스냅숏이 없는 폴더: 폴더 줄이 골라져 꺼진 단추가 이름을 치면 켜짐
	var dir0 := p.snapshot_dir
	p.snapshot_dir = TMP_DIR.path_join("only_dirs")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p.snapshot_dir).path_join("20261010-000000-seed1"))
	lab.step_ticks(10)
	(p.control("open") as Button).pressed.emit()
	await t.frames(2)
	var off0 := od.get_ok_button().disabled
	od.get_line_edit().text = snap
	od.get_line_edit().text_changed.emit(snap)
	var off1 := od.get_ok_button().disabled
	od.get_ok_button().pressed.emit()
	await t.frames(1)
	t.check(off0 and not off1 and not od.visible and lab.world.tick == tick0, "스냅숏 없는 폴더: 꺼진 열기 단추(%s)가 경로를 치면 켜짐(%s) → 열림" % [str(off0), str(off1)])
	p.snapshot_dir = dir0


## 키보드만으로(J16): 패널 단추·고르기 상자·확인 상자는 Tab 으로 닿고 Enter 로 누른다. 스페이스는 그대로 멈춤(LabMain 이 GUI
## 보다 먼저 받음 — 초점 단추가 눌리지 않음). 누른 뒤에도 초점은 그 단추에(이어서 Tab). 마우스로 누르면 초점을 남기지 않음.
func _keyboard(t, lab: LabMain, p: ParamPanel) -> void:
	lab.set_paused(false)
	var ids: Array[String] = ["preset:0", "random:0", "export", "save", "open", "sound", "advanced", "apply", "revert", "compare",
			"start_compare", "adv_target:0", "adv_target:1"]
	var none: Array[String] = []
	for id in ids:
		var c := p.control(id) as Control
		if c == null or c.focus_mode != Control.FOCUS_ALL:
			none.append(id)
	t.check(none.is_empty(), "단추·고르기 상자·확인 상자가 키보드 초점을 받음(못 받음: %s)" % ", ".join(none))
	var af := (p.control("apply") as Control).get_theme_stylebox("focus") as StyleBoxFlat
	var sf := (p.control("sound") as Control).get_theme_stylebox("focus") as StyleBoxFlat
	t.check(af != null and af.border_color == UiTheme.color("text") and sf != null and sf.border_color.a > 0.0,
			"초점 테두리가 보임(강조 단추 = 글 색, 확인 상자 = 단추 테두리 — 공용 모양은 비어 있거나 강조 바탕과 같은 색)")
	var sle := p.control("seed:0") as LineEdit
	sle.grab_focus()
	await t.frames(1)
	var target := p.control("apply") as Control
	var seen: Array[String] = []
	for i in 60:
		_key(t, KEY_TAB)
		var f := _focus_owner(p)
		for id in ids:
			if f == p.control(id) and not seen.has(id):
				seen.append(id)
		if f == target:
			break
	t.check(_focus_owner(p) == target and seen.has("random:0") and seen.has("export") and seen.has("save") and seen.has("open") and seen.has("advanced"),
			"씨앗 칸에서 Tab 만으로 무작위·내보내기·스냅숏·고급 설정·새 실험 단추에 닿음(%s)" % ", ".join(seen))
	var x := lab.experiments[0]
	_key(t, KEY_SPACE)
	t.check(lab.is_paused() and lab.experiments[0] == x and _focus_owner(p) == target, "초점 단추에서 스페이스 = 멈춤(단추는 안 눌림)")
	_key(t, KEY_ENTER)
	await t.frames(1)
	t.check(lab.experiments[0] != x and _focus_owner(p) == target, "Enter → 새 실험 단추 누름·초점은 그 단추에 그대로")
	_key(t, KEY_TAB)
	t.check(_focus_owner(p) == p.control("revert"), "이어서 Tab → 되돌리기")
	# 단추에 초점을 둔 채 지도를 누르면 초점이 풀려 Enter 가 그 단추를 누르지 않음
	(p.control("compare") as Control).grab_focus()
	_click(t, lab._map_container.get_global_rect().get_center())
	await t.frames(1)
	_key(t, KEY_ENTER)
	await t.frames(1)
	t.check(_focus_owner(p) == null and not p.is_compare_mode(), "단추 초점 + 지도 클릭 → 초점 풀림·Enter 가 비교 모드 단추를 누르지 않음")
	# 마우스로 누르면 초점을 남기지 않음(누른 뒤 Enter 가 같은 단추를 다시 누르지 않게)
	var adv := p.control("advanced") as Button
	(p.control("scroll") as ScrollContainer).ensure_control_visible(adv)
	await t.frames(2)
	_click(t, adv.get_global_rect().get_center())
	await t.frames(1)
	t.check(adv.button_pressed and _focus_owner(p) == null, "마우스 클릭 → 고급 설정 펼침·초점 남기지 않음")
	p.set_advanced_open(false)
	lab.set_paused(true)


## 비교 중 스냅숏 저장(대화 상자): 같은 이름으로 두 번 저장하면 실제로 쓰는 <이름>-A/-B 가 이미 있으므로 먼저 묻는다 —
## 취소하면 그대로, 덮어쓰기면 새 틱으로(J05 — 예전에는 대화 상자가 고른 <이름>.json 만 보아 묻지 않고 덮어썼음).
func _compare_save(t, lab: LabMain, p: ParamPanel) -> void:
	lab.set_paused(true)
	if not lab.is_comparing():
		p.set_compare_mode(true)
		p.apply_compare()
	t.check(lab.is_comparing(), "비교 중")
	var dir := ProjectSettings.globalize_path(p.snapshot_dir)
	var pa := dir.path_join("cmpsnap-A.json")
	var pb := dir.path_join("cmpsnap-B.json")
	for f in [pa, pb, pa + ".bak", pb + ".bak"]:
		DirAccess.remove_absolute(f)
	await _save_named(t, p, "cmpsnap")
	var tick1 := lab.world.tick
	t.check(_snap_tick(pa) == tick1 and _snap_tick(pb) == tick1, "비교 중 저장 → cmpsnap-A/-B.json(틱 %d)" % tick1)
	lab.step_ticks(30)
	await _save_named(t, p, "cmpsnap")
	var ow := p.control("overwrite_dialog") as ConfirmationDialog
	t.check(ow != null and ow.visible and _snap_tick(pa) == tick1 and ow.dialog_text.contains("cmpsnap-A.json") and ow.dialog_text.contains("cmpsnap-B.json"),
			"같은 이름으로 다시 저장 → -A/-B 를 적은 덮어쓰기 물음(파일 그대로 틱 %d)" % _snap_tick(pa))
	if ow == null:
		return
	t.check(ow.get_cancel_button().has_focus(), "덮어쓰기 물음의 기본 초점 = 취소")
	ow.get_cancel_button().pressed.emit()
	await t.frames(1)
	t.check(not ow.visible and _snap_tick(pa) == tick1 and _snap_tick(pb) == tick1, "취소 → 파일 그대로")
	await _save_named(t, p, "cmpsnap")
	ow.get_ok_button().pressed.emit()
	await t.frames(1)
	t.check(not ow.visible and _snap_tick(pa) == tick1 + 30 and _snap_tick(pb) == tick1 + 30, "덮어쓰기 → 새 틱 %d" % _snap_tick(pa))
	p.set_compare_mode(false)


## 엔진 FileDialog 의 같은 이름 확인(운영 체제 대화 상자를 못 쓸 때 — 헤드리스는 늘 이것, 검토 최종 확인 I50·J05):
## 혼자 저장은 실험실 모양·한국어로 묻고(기본 초점 취소), 비교 중에는 쓰지도 않을 <이름>.json 을 묻지 않고 -A/-B 를 쓴다.
func _engine_overwrite(t, lab: LabMain, p: ParamPanel) -> void:
	lab.set_paused(true)
	if lab.is_comparing():
		p.set_compare_mode(false)
	var dir := ProjectSettings.globalize_path(p.snapshot_dir)
	var solo := dir.path_join("same.json")
	for f in [solo, solo + ".bak", dir.path_join("same-A.json"), dir.path_join("same-B.json")]:
		DirAccess.remove_absolute(f)
	await _save_named(t, p, "same")
	var tick1 := lab.world.tick
	t.check(not lab.is_comparing() and _snap_tick(solo) == tick1, "혼자 저장 → same.json(틱 %d)" % tick1)
	lab.step_ticks(10)
	await _save_named(t, p, "same")
	var sd := p.control("save_dialog") as FileDialog
	var asked: ConfirmationDialog = null
	for c in sd.get_children(true):
		if c is ConfirmationDialog:
			asked = c
			break
	var sb := asked.get_theme_stylebox("panel") as StyleBoxFlat if asked != null else null
	t.check(asked != null and asked.visible and asked.title == "스냅숏을 덮어쓸까요?" and asked.dialog_text.contains("same.json")
			and asked.ok_button_text == "덮어쓰기" and sb != null and sb.bg_color == UiTheme.color("panel"),
			"혼자 같은 이름 → 엔진 확인 창이 실험실 모양·한국어(%s / %s / 바탕 %s)" % [asked.title if asked else "", asked.dialog_text.replace("\n", " ") if asked else "", str(sb.bg_color) if sb else ""])
	if asked == null:
		return
	await t.frames(1)
	t.check(asked.get_cancel_button().has_focus(), "엔진 확인 창의 기본 초점 = 취소")
	asked.get_cancel_button().pressed.emit()
	sd.hide()
	await t.frames(1)
	t.check(_snap_tick(solo) == tick1, "취소 → same.json 그대로")
	# 비교 중: same.json 이 있어도 묻지 않고 -A/-B 를 씀, same.json 은 그대로
	var before := FileAccess.get_file_as_bytes(solo)
	p.set_compare_mode(true)
	p.apply_compare()
	lab.set_paused(true)
	await _save_named(t, p, "same")
	var tick2 := lab.world.tick
	t.check(lab.is_comparing() and not asked.visible and _snap_tick(dir.path_join("same-A.json")) == tick2 and _snap_tick(dir.path_join("same-B.json")) == tick2
			and FileAccess.get_file_as_bytes(solo) == before,
			"비교 중 같은 이름(same.json 있음) → 쓰지 않을 same.json 을 묻지 않고 -A/-B(틱 %d), same.json 그대로" % tick2)
	p.set_compare_mode(false)


## 저장 단추 → 대화 상자 이름 칸에 name → 저장 단추(엔진 대화 상자의 확인 = 실제 고르기 길).
func _save_named(t, p: ParamPanel, fname: String) -> void:
	(p.control("save") as Button).pressed.emit()
	await t.frames(1)
	var sd := p.control("save_dialog") as FileDialog
	sd.get_line_edit().text = fname
	sd.get_ok_button().pressed.emit()
	await t.frames(2)


func _snap_tick(path: String) -> int:
	var r := SimSnapshot.load_file(path)
	return r.world.tick if r.world != null else -1


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


## 지금 실험의 씨앗이 무작위 범위(0~ui.param.seed_max) 밖(명령줄 --seed=-5·스냅숏): 칸은 그 씨앗 그대로, "지금 실험과 같음",
## 새 실험은 같은 씨앗(예전에는 0 으로 잘라 "바꾼 값 1개" 가 뜨고 새 실험이 다른 세계였음). 칸에 적은 씨앗도 자르지 않음.
func _seed_range(t, lab: LabMain, p: ParamPanel) -> void:
	var smax := UiConfig.integer("param.seed_max")
	t.check(lab.new_experiment("default", {}, -5) == "", "씨앗 -5 실험")
	var sle := p.control("seed:0") as LineEdit
	t.check(int(p.current_settings(0).seed) == -5 and p.status_text() == ParamPanel.TEXT_SAME and sle.text == "-5",
			"씨앗 -5 → 칸도 -5·지금 실험과 같음: %s · %s" % [str(p.current_settings(0).seed), p.status_text()])
	var x := lab.experiments[0]
	t.check(p.apply() == "" and lab.experiments[0] != x and lab.world.seed_value == -5, "새 실험 → 같은 씨앗 -5 (%d)" % lab.world.seed_value)
	var big := smax + 852516353
	t.check(lab.new_experiment("default", {}, big) == "" and int(p.current_settings(0).seed) == big and p.status_text() == ParamPanel.TEXT_SAME,
			"씨앗 %d(무작위 범위 밖) → 칸도 그대로·지금 실험과 같음" % big)
	t.check(p.apply() == "" and lab.world.seed_value == big, "새 실험 → 같은 씨앗 %d" % big)
	# 범위 밖 씨앗의 스냅숏을 열어도 같음
	var path := ProjectSettings.globalize_path(TMP_DIR.path_join("big_seed.json"))
	t.check(lab.save_snapshot(path) == "", "범위 밖 씨앗 스냅숏 저장")
	lab.new_experiment("default", {}, 1)
	t.check(lab.open_snapshot(path) == "" and int(p.current_settings(0).seed) == big and p.status_text() == ParamPanel.TEXT_SAME,
			"범위 밖 씨앗 스냅숏을 열면 칸 = 그 씨앗·지금 실험과 같음")
	# 칸에 적은 씨앗도 그대로(64비트 정수 — 예전에는 0~seed_max 로 잘랐음)
	p.set_value("seed", -7)
	t.check(int(p.current_settings(0).seed) == -7 and sle.text == "-7", "칸에 적은 -7 도 그대로")
	lab.new_experiment("default", {}, 1)
	await t.frames(1)


## 2^53 넘는 씨앗·64비트 끝 씨앗(명령줄·스냅숏으로 닿음): 칸 글자 = 씨앗, 칸에 초점을 줬다 빼거나 Enter 만 쳐도 그대로,
## 새 실험은 같은 씨앗(J18 — 예전 실수 SpinBox: …993 이 …992 로 보이고, INT64_MAX 는 초점만 빼도 씨앗 0).
## INT64_MIN 은 "-…" 하나(J31 — "%d" 형식은 부호를 두 번 붙였음): 칸 글자·저장 기본 이름.
func _big_seeds(t, lab: LabMain, p: ParamPanel) -> void:
	lab.set_paused(true)
	var sle := p.control("seed:0") as LineEdit
	for sv: int in [SEED_2P53_PLUS1, INT64_MAX, INT64_MIN]:
		t.check(lab.new_experiment("default", {}, sv) == "", "씨앗 %s 실험" % str(sv))
		t.check(sle.text == str(sv) and int(p.current_settings(0).seed) == sv and p.status_text() == ParamPanel.TEXT_SAME,
				"칸 글자 = 씨앗 %s(칸 \"%s\")·지금 실험과 같음" % [str(sv), sle.text])
		sle.grab_focus()
		await t.frames(1)
		sle.release_focus()
		await t.frames(1)
		var after_blur := int(p.current_settings(0).seed)
		sle.grab_focus()
		await t.frames(1)
		_key(t, KEY_ENTER)
		await t.frames(2)
		t.check(after_blur == sv and int(p.current_settings(0).seed) == sv and sle.text == str(sv) and p.status_text() == ParamPanel.TEXT_SAME,
				"씨앗 %s: 초점 넣고 빼기·Enter → 그대로(%s / %s)" % [str(sv), str(after_blur), str(p.current_settings(0).seed)])
		var x := lab.experiments[0]
		t.check(p.apply() == "" and lab.experiments[0] != x and lab.world.seed_value == sv, "새 실험 → 같은 씨앗 %s" % str(sv))
	(p.control("save") as Button).pressed.emit()
	await t.frames(1)
	var sd := p.control("save_dialog") as FileDialog
	t.check(sd != null and sd.current_file.contains("-seed%s-tick" % str(INT64_MIN)) and not sd.current_file.contains("--"),
			"INT64_MIN 씨앗의 저장 기본 이름에 부호 하나: " + (sd.current_file if sd != null else ""))
	if sd != null:
		sd.hide()
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
	# 모양(I50): 엔진 기본 회색 창이 아니라 실험실 색(바탕 = 패널, 테두리·제목 줄 = 위쪽 막대), 높이는 글·단추에 맞춤
	var def := ThemeDB.get_default_theme()
	var bg := dlg.get_theme_stylebox("panel") as StyleBoxFlat
	var frame := dlg.get_theme_stylebox("embedded_border") as StyleBoxFlat
	t.check(bg != null and bg != def.get_stylebox("panel", "AcceptDialog") and bg.bg_color == UiTheme.color("panel")
			and frame != null and frame.bg_color == UiTheme.color("topbar") and dlg.get_theme_color("title_color") == UiTheme.color("text"),
			"확인 대화 상자 = 실험실 색(바탕 %s, 테두리 %s)" % [str(bg.bg_color) if bg != null else "-", str(frame.bg_color) if frame != null else "-"])
	t.check(dlg.size.y <= ceili(dlg.get_contents_minimum_size().y) + 1, "확인 대화 상자 높이 %d = 글·단추에 맞춤(%d) — 글과 단추 사이가 비지 않음"
			% [dlg.size.y, ceili(dlg.get_contents_minimum_size().y)])
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
	# 물음의 틱은 위쪽 막대·알림과 같이 세 자리 쉼표(I50 — 예전 "틱 1060")
	lab.step_ticks(1000)
	(p.control("apply") as Button).pressed.emit()
	await t.frames(1)
	var want := "틱 %s" % ChroniclePanel.commas(lab.world.tick)
	t.check(dlg.visible and lab.world.tick >= 1000 and UiTheme.plain_text(dlg.dialog_text).contains(want),
			"물음의 틱 = 쉼표(%s): %s" % [want, UiTheme.plain_text(dlg.dialog_text)])
	dlg.get_cancel_button().pressed.emit()
	await t.frames(1)
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
	p.snapshot_dir = TMP_DIR.path_join("snapshots")
	await t.frames(2)
	# 웹: 결과 내려받기 실패 → 알림 하나(LabMain.download_results 가 띄움 — 패널이 하나 더 띄우지 않음, I40)
	fake.zip_fail = true
	p.set_web_mode(true)
	(p.control("export") as Button).pressed.emit()
	var zip_errs := 0
	for to in fake.visible_toasts():
		if str(to.kind) == "error" and str(to.text).contains("묶을 수 없습니다"):
			zip_errs += 1
	t.check(zip_errs == 1 and p.error_text().contains("묶을 수 없습니다"), "웹 결과 내려받기 실패 → 오류 알림 하나(%d개)·패널 안 오류" % zip_errs)
	p.set_web_mode(false)
	fake.zip_fail = false
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
