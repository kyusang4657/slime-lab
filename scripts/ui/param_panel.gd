class_name ParamPanel
extends VBoxContainer
## 파라미터 패널(실험실 왼쪽 자리). 계약: docs/VIEW-API.md "ParamPanel".
## 패널에 적힌 값 = **다음** 실험이 쓸 조건(예설정 + 바꾼 값 + 씨앗). 값을 바꿔도 지금 실험에는 적용되지 않고
## "새 실험"(비교 모드면 "나란히 시작")을 눌러야 LabMain 이 새 세계를 만든다. 맨 위 "지금 실험" 묶음은
## experiments_changed 를 받아 지금 돌고 있는 실험(이름·씨앗·세 값)을 보여 준다.
##
## 시뮬레이션은 읽기만 한다: 설정은 SimConfig(defaults·presets·build·get_value), 지금 실험의 값은 Experiment 의
## 만든 조건과 읽기 전용 world.cfg(사본으로 견줌). 세계를 진행하거나 고치지 않는다(진행은 LabMain 만).
## 값 검사는 SimConfig.build 그대로(+ 초기 개체 수 ≤ population.cap). 오류는 그 칸 바로 아래 빨간 글.
## 강조(왼쪽 띠 + 강조 색 값) = 지금 실험과 다른 값. 상태 줄 "바꾼 값 N개" 의 N 도 같은 기준(설정 잎 키 + 씨앗).
## 노드는 모두 코드로 만든다. 패널 전체가 세로 스크롤, 가로는 lab.left_panel_width 안(가로 넘침 없음, 검사).

## 세 주요 값(슬라이더 + 숫자 칸)
const MAIN_KEYS: Array[String] = ["mutation.rate", "resources.scale", "population.initial"]
const MAIN_NAMES := {"mutation.rate": "돌연변이율", "resources.scale": "자원량", "population.initial": "초기 개체 수"}
## "지금 실험" 요약에 쓰는 짧은 이름
const MAIN_SHORT := {"mutation.rate": "돌연변이", "resources.scale": "자원", "population.initial": "개체"}
## 고급 설정 절 이름(sim-defaults.json 의 절 → 화면 이름)
const SECTION_NAMES := {
	"map": "지도", "time": "시간", "seasons": "계절", "plants": "식물", "resources": "자원", "dropped": "떨어진 먹이",
	"body": "몸", "metab": "대사", "eat": "먹기", "life": "수명", "repro": "번식", "population": "개체군",
	"sense": "감각", "traits": "특성", "brain": "두뇌", "mutation": "돌연변이", "carry": "운반", "store": "저장고",
	"farm": "밭", "discovery": "발견", "hash": "역사 해시", "record": "기록", "run": "실행기",
}
## set_value 의 특별 키(설정 키가 아닌 것)
const KEY_PRESET := "preset"
const KEY_SEED := "seed"
## 잎 키 종류(고급 설정 칸 모양)
const KIND_INT := "int"
const KIND_FLOAT := "float"
const KIND_BOOL := "bool"
## 수·참거짓이 아닌 잎(배열·글자): 보이기만 하고 패널에서 바꾸지 않음
const KIND_OTHER := "other"
## 스냅숏 대화 상자의 시작 폴더(LabMain.default_export_dir 와 같은 곳)
const SNAPSHOT_DIR := "user://experiments"
const TEXT_SAME := "지금 실험과 같음"
const TEXT_PENDING := "바꾼 값 %d개 · 새 실험을 눌러 적용"
const TEXT_PENDING_COMPARE := "바꾼 값 %d개 · 나란히 시작을 눌러 적용"
const TEXT_COMPARE_IDLE := "나란히 시작을 누르면 A·B 를 함께 시작"
const TEXT_NO_LAB := "실험실에 연결되지 않았습니다"
const TEXT_NO_EXPERIMENT := "아직 실험이 없습니다"
## 비교 칸 이름표와 지도 위치
const COL_TAGS: Array[String] = ["A", "B"]
const COL_SIDES: Array[String] = ["왼쪽 지도", "오른쪽 지도"]
## 고급 설정 펼침 표시(글꼴에 없으면 대신 글자)
const GLYPH_OPEN := "▼"
const GLYPH_CLOSED := "▶"

var _lab: LabMain
# 칸별 다음 실험 조건: {preset, seed, overrides(예설정과 다른 값만), error, config, last_key, field_key, field_msg}
var _cols: Array[Dictionary] = []
# 지금 돌고 있는 실험: {tag, label, seed, cfg(world.cfg 의 깊은 사본 — 견주기만 함)}
var _running: Array[Dictionary] = []
var _compare_on := false
var _adv_open := false
# 고급 설정이 보여 주는 칸(0 = A, 1 = B — 비교 모드에서만 고름)
var _adv_col := 0
# 마지막 동작(새 실험·내보내기·스냅숏)의 오류 문장
var _action_error := ""
var _was_comparing := false
# 화면을 상태에 맞추는 중(슬라이더 끝을 줄이면 Range 가 값을 잘라 value_changed 를 내므로 그 신호를 무시)
var _syncing := false

# 화면 수치(ui.param 등, _init 에서 한 번 읽음)
var _fs_small := 13
var _seed_max := 2147483647
var _gap := 6
var _row_gap := 2
var _stripe_w := 3.0
var _c_text := Color.WHITE
var _c_dim := Color.GRAY
var _c_accent := Color.AQUAMARINE
var _c_danger := Color.RED
var _c_series: Array[Color] = [Color.AQUAMARINE, Color.ORANGE]

# ── 노드 ──
var _scroll: ScrollContainer
var _body: VBoxContainer
var _now_box: VBoxContainer
var _next_title: Label
var _cards: Array[Dictionary] = []
var _status: Label
var _error: Label
var _apply_btn: Button
var _start_compare_btn: Button
var _revert_btn: Button
var _compare_btn: Button
var _export_btn: Button
var _save_btn: Button
var _open_btn: Button
var _sound_check: CheckBox
var _adv_toggle: Button
var _adv_note: Label
var _adv_box: VBoxContainer
var _adv_target: HBoxContainer
var _adv_target_btns: Array[Button] = []
var _adv_target_group := ButtonGroup.new()
# 고급 설정 줄: 키 → {row, stripe, name, field(LineEdit 또는 CheckBox), err, kind}
var _adv_rows: Dictionary = {}
var _save_dialog: FileDialog
var _open_dialog: FileDialog

# 설정 잎 키(sim-defaults.json 순서)와 종류, 예설정별 설정(캐시)
static var _leaf_order: Array[String] = []
static var _leaf_kind: Dictionary = {}
static var _preset_cache: Dictionary = {}


func _init() -> void:
	name = "ParamPanel"
	_read_config()
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	_scan_leaves()
	var def_preset := str(UiConfig.value("lab.default_preset", "default"))
	var def_seed := UiConfig.integer("lab.default_seed")
	for c in COL_TAGS.size():
		_cols.append(_new_col(def_preset, def_seed, {}))
		_validate(c)
	_build()
	_refresh()


func _read_config() -> void:
	_fs_small = UiConfig.integer("lab.font_size_small")
	_seed_max = maxi(0, UiConfig.integer("param.seed_max"))
	_gap = UiConfig.integer("param.group_gap")
	_row_gap = UiConfig.integer("param.row_gap")
	_stripe_w = UiConfig.num("param.changed_stripe_width")
	_c_text = UiTheme.color("text")
	_c_dim = UiTheme.color("text_dim")
	_c_accent = UiTheme.color("accent")
	_c_danger = UiTheme.color("danger")
	# A·B 이름표 색은 그래프의 계열 색과 같게(같은 실험 = 같은 색)
	_c_series = [UiConfig.color("graph.series_a"), UiConfig.color("graph.series_b")]


# ════════════════════════════ 계약 함수 ════════════════════════════

## 실험실에 붙는다: 실험 목록이 바뀌면 "지금 실험" 을 다시 읽고, 패널 값도 그 실험의 조건으로 맞춘다.
func bind_lab(lab: LabMain) -> void:
	if _lab != null and is_instance_valid(_lab):
		if _lab.experiments_changed.is_connected(_on_experiments_changed):
			_lab.experiments_changed.disconnect(_on_experiments_changed)
		if _lab.child_entered_tree.is_connected(_on_lab_children):
			_lab.child_entered_tree.disconnect(_on_lab_children)
			_lab.child_exiting_tree.disconnect(_on_lab_children)
	_lab = lab
	if _lab == null:
		_running.clear()
		_refresh()
		return
	_lab.experiments_changed.connect(_on_experiments_changed)
	# 소리(LabSound)는 LabMain 이 나중에 붙일 수 있다 — 자식이 바뀔 때마다 다시 찾는다
	_lab.child_entered_tree.connect(_on_lab_children)
	_lab.child_exiting_tree.connect(_on_lab_children)
	_on_experiments_changed(_lab.experiments)
	_sync_sound.call_deferred()


## 지금 패널에 적힌 조건 {preset, overrides, seed}. which = 0(A) / 1(B, 비교 모드 칸).
## overrides 는 고른 예설정과 다른 값만(점으로 이은 키). 사본이라 고쳐 써도 패널은 그대로.
func current_settings(which: int = 0) -> Dictionary:
	var col := _cols[clampi(which, 0, _cols.size() - 1)]
	return {preset = str(col.preset), overrides = (col.overrides as Dictionary).duplicate(true), seed = int(col.seed)}


## 값 하나를 바꾼다(검사·자동화용, 칸에 적은 것과 같음). key = 설정 키("mutation.rate" 등), "preset"(예설정 이름),
## "seed"(씨앗, 0~ui.param.seed_max 로 자름). 글자 값은 칸에 적은 것처럼 해석한다.
## 돌려주는 값: 이 값 또는 이 칸 조건의 오류 문장("" = 문제 없음). 지금 실험에는 적용하지 않는다(apply() 가 함).
func set_value(key: String, value: Variant, which: int = 0) -> String:
	var c := clampi(which, 0, _cols.size() - 1)
	var col := _cols[c]
	var err := ""
	col.field_key = ""
	col.field_msg = ""
	match key:
		KEY_PRESET:
			err = _set_preset(c, str(value))
		KEY_SEED:
			var r := _parse_seed(value)
			err = str(r.error)
			if err == "":
				col.seed = int(r.value)
			else:
				col.field_key = KEY_SEED
				col.field_msg = err
		_:
			var r2 := _coerce(key, value)
			err = str(r2.error)
			if err != "":
				col.field_key = key
				col.field_msg = err
			else:
				var ov: Dictionary = col.overrides
				var pv: Variant = SimConfig.get_value(_preset_config(str(col.preset)), key)
				if SimConfig.deep_equal(r2.value, pv):
					ov.erase(key)
				else:
					ov[key] = r2.value
				col.last_key = key
	_validate(c)
	_refresh()
	return err if err != "" else str(col.error)


## 새 실험 단추와 같다: 패널의 A 조건으로 lab.new_experiment. 성공 "", 실패면 오류 문장(패널 안 빨간 글 + 알림).
## 조건에 오류가 있으면 실험실에 넘기지 않는다(지금 실험 그대로).
func apply() -> String:
	_commit_edits()
	var err := ""
	if _lab == null or not is_instance_valid(_lab):
		err = TEXT_NO_LAB
	elif str(_cols[0].error) != "":
		err = "설정 오류: %s" % str(_cols[0].error)
	else:
		var s := current_settings(0)
		err = _lab.new_experiment(str(s.preset), s.overrides, int(s.seed))
	_report(err, "새 실험을 시작할 수 없습니다")
	return err


## "나란히 시작" 단추와 같다: A·B 조건으로 lab.start_compare(a, b). 성공 "", 실패면 오류 문장(패널 안 + 알림).
func apply_compare() -> String:
	_commit_edits()
	var err := ""
	if _lab == null or not is_instance_valid(_lab):
		err = TEXT_NO_LAB
	else:
		for c in _cols.size():
			if str(_cols[c].error) != "":
				err = "%s 설정 오류: %s" % [COL_TAGS[c], str(_cols[c].error)]
				break
		if err == "":
			err = _lab.start_compare(current_settings(0), current_settings(1))
	_report(err, "비교를 시작할 수 없습니다")
	return err


## 되돌리기 단추와 같다: 보이는 칸(A, 비교 모드면 B 도)의 바꾼 값을 지워 고른 예설정 값으로. 씨앗은 그대로.
func revert() -> void:
	for c in _visible_cols():
		var col := _cols[c]
		col.overrides = {}
		col.last_key = ""
		col.field_key = ""
		col.field_msg = ""
		_validate(c)
	_action_error = ""
	_refresh()


## 비교 모드 단추와 같다. 켜면 B 칸이 나타나고(비교 중이 아니면 A 조건을 그대로 베낌), 끄면 lab.stop_compare().
func set_compare_mode(on: bool) -> void:
	_commit_edits()
	if on == _compare_on:
		return
	_compare_on = on
	_compare_btn.set_pressed_no_signal(on)
	if on:
		var comparing := _lab != null and is_instance_valid(_lab) and _lab.is_comparing()
		if not comparing:
			_cols[1] = _copy_col(_cols[0])
			_validate(1)
	else:
		_adv_col = 0
		if _lab != null and is_instance_valid(_lab):
			_lab.stop_compare()
	_action_error = ""
	_refresh()


func is_compare_mode() -> bool:
	return _compare_on


## 결과 폴더 내보내기(CSV 내보내기 단추가 lab.default_export_dir() 로 부르는 것과 같은 함수). 성공 "".
func export_to(dir: String) -> String:
	var err := TEXT_NO_LAB if _lab == null or not is_instance_valid(_lab) else _lab.export_csv(dir)
	_report(err, "")
	return err


## 고급 설정 펼치기/접기.
func set_advanced_open(on: bool) -> void:
	_adv_open = on
	_adv_toggle.set_pressed_no_signal(on)
	_refresh()


## 고급 설정이 보여 주는 칸(비교 모드에서 0 = A, 1 = B).
func set_advanced_target(which: int) -> void:
	_adv_col = clampi(which, 0, 1) if _compare_on else 0
	_refresh()


# ════════════════════════════ 검사·캡처용 ════════════════════════════

## 상태 줄 글(지금 실험과 같음 / 바꾼 값 N개 …).
func status_text() -> String:
	return _status.text


## 패널 아래쪽 오류 글(없으면 "").
func error_text() -> String:
	return _error.text if _error.visible else ""


## 지금 실험 요약 줄들(실험마다 "이름 / 세 값").
func now_text() -> String:
	var out: Array[String] = []
	for ch in _now_box.get_children():
		for l in _labels_in(ch):
			out.append(UiTheme.plain_text(l.text))
	return "\n".join(out)


## 칸(which)의 주요 값 숫자 칸 글자.
func field_text(key: String, which: int = 0) -> String:
	var row := _main_row(which, key)
	return (row.field as LineEdit).text if not row.is_empty() else ""


## 그 키가 강조(지금 실험과 다름)되어 있는가. 고급 설정 줄이면 고급 칸 기준.
func is_highlighted(key: String, which: int = 0, advanced: bool = false) -> bool:
	var row: Dictionary = _adv_rows.get(key, {}) if advanced else _main_row(which, key)
	if key == KEY_SEED and not advanced and which >= 0 and which < _cards.size():
		return _stripe_on(_cards[which].seed_stripe as ColorRect)
	return not row.is_empty() and _stripe_on(row.stripe as ColorRect)


## 그 키 줄 아래 오류 글(보이지 않으면 "").
func row_error(key: String, which: int = 0, advanced: bool = false) -> String:
	var row: Dictionary = _adv_rows.get(key, {}) if advanced else _main_row(which, key)
	if row.is_empty():
		return ""
	var l := row.err as Label
	return l.text if l.visible else ""


## 노드 찾기(검사·캡처용): "apply"·"start_compare"·"revert"·"compare"·"export"·"save"·"open"·"sound"·"advanced"·
## "scroll"·"random:0"·"seed:0"·"preset:0"·"slider:<키>:0"·"field:<키>:0"·"card:1"·"adv:<키>"·"adv_target:1"·"save_dialog"·"open_dialog".
func control(id: String) -> Node:
	var p := id.split(":")
	var w := int(p[p.size() - 1]) if p.size() > 1 and p[p.size() - 1].is_valid_int() else 0
	match p[0]:
		"apply": return _apply_btn
		"start_compare": return _start_compare_btn
		"revert": return _revert_btn
		"compare": return _compare_btn
		"export": return _export_btn
		"save": return _save_btn
		"open": return _open_btn
		"sound": return _sound_check
		"advanced": return _adv_toggle
		"scroll": return _scroll
		"random": return _cards[w].random
		"seed": return _cards[w].seed
		"preset": return _cards[w].preset
		"card": return _cards[w].root
		"slider", "field":
			var row := _main_row(w, p[1])
			return null if row.is_empty() else row[p[0]]
		"adv":
			var r: Dictionary = _adv_rows.get(p[1], {})
			return null if r.is_empty() else r.field
		"adv_target": return _adv_target_btns[w]
		"save_dialog": return _save_dialog
		"open_dialog": return _open_dialog
	return null


# ════════════════════════════ 조건(칸) ════════════════════════════

func _new_col(preset: String, seed_in: int, overrides: Dictionary) -> Dictionary:
	return {preset = preset, seed = seed_in, overrides = overrides.duplicate(true), error = "", config = {},
			last_key = "", field_key = "", field_msg = ""}


func _copy_col(src: Dictionary) -> Dictionary:
	return _new_col(str(src.preset), int(src.seed), src.overrides)


## 조건 검사: SimConfig.build 그대로 + 초기 개체 수 ≤ 개체 상한(넘으면 처음부터 번식이 막힘).
func _validate(c: int) -> void:
	var col := _cols[c]
	var b := SimConfig.build(str(col.preset), col.overrides)
	col.error = str(b.error)
	col.config = b.config
	if col.error == "":
		var ini := int(SimConfig.get_value(col.config, "population.initial"))
		var cap := int(SimConfig.get_value(col.config, "population.cap"))
		if ini > cap:
			col.error = "초기 개체 수(population.initial = %d)가 개체 상한(population.cap = %d)보다 큽니다" % [ini, cap]


## 예설정을 고르면 바꾼 값을 지우고 그 예설정 값으로(씨앗은 그대로).
func _set_preset(c: int, preset_name: String) -> String:
	if not SimConfig.presets().has(preset_name):
		return "없는 예설정입니다: %s" % preset_name
	var col := _cols[c]
	col.preset = preset_name
	col.overrides = {}
	col.last_key = ""
	return ""


## 씨앗 값 해석: 정수(글자도 됨)를 0~seed_max 로 자른다. {value, error}
func _parse_seed(value: Variant) -> Dictionary:
	var v := 0
	match typeof(value):
		TYPE_INT:
			v = int(value)
		TYPE_FLOAT:
			if not is_finite(float(value)) or float(value) != floorf(float(value)):
				return {value = 0, error = "씨앗은 정수여야 합니다: %s" % str(value)}
			v = int(value)
		TYPE_STRING, TYPE_STRING_NAME:
			var s := str(value).strip_edges()
			if not s.is_valid_int():
				return {value = 0, error = "씨앗은 정수여야 합니다: %s" % s}
			v = s.to_int()
		_:
			return {value = 0, error = "씨앗은 정수여야 합니다"}
	return {value = clampi(v, 0, _seed_max), error = ""}


## 설정 값 해석(칸에 적은 글자 또는 값) → 그 키의 종류. {value, error}
func _coerce(key: String, value: Variant) -> Dictionary:
	if not _leaf_kind.has(key):
		return {value = null, error = "알 수 없는 설정 키: %s" % key}
	var kind := str(_leaf_kind[key])
	if kind == KIND_OTHER:
		return {value = null, error = "%s 는 패널에서 바꿀 수 없습니다(예설정·명령줄 --set 으로)" % key}
	var v: Variant = value
	if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME:
		var s := str(v).strip_edges()
		if kind == KIND_BOOL:
			if s in ["true", "켬", "1"]:
				return {value = true, error = ""}
			if s in ["false", "끔", "0"]:
				return {value = false, error = ""}
			return {value = null, error = "%s 는 참·거짓(true/false)이어야 합니다: %s" % [key, s]}
		if s.is_valid_int():
			v = s.to_int()
		elif s.is_valid_float():
			v = s.to_float()
		else:
			return {value = null, error = "%s: 수가 아닙니다 — \"%s\"" % [key, s]}
	match kind:
		KIND_BOOL:
			if typeof(v) != TYPE_BOOL:
				return {value = null, error = "%s 는 참·거짓이어야 합니다" % key}
			return {value = v, error = ""}
		KIND_INT:
			if typeof(v) == TYPE_FLOAT:
				var f := float(v)
				if not is_finite(f) or f != floorf(f):
					return {value = null, error = "%s 는 정수여야 합니다: %s" % [key, str(v)]}
				return {value = int(f), error = ""}
			if typeof(v) == TYPE_INT:
				return {value = v, error = ""}
		KIND_FLOAT:
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				var f2 := float(v)
				if not is_finite(f2):
					return {value = null, error = "%s: 유한한 수여야 합니다" % key}
				return {value = f2, error = ""}
	return {value = null, error = "%s: 수가 아닙니다" % key}


## 칸(c)의 다음 실험 값(바꾼 값이 있으면 그것, 없으면 예설정 값).
func _value(c: int, key: String) -> Variant:
	var ov: Dictionary = _cols[c].overrides
	if ov.has(key):
		return ov[key]
	return SimConfig.get_value(_preset_config(str(_cols[c].preset)), key)


## 칸(c)을 견줄 지금 실험(비교 중이면 같은 자리, 아니면 첫째 실험). 없으면 {}.
func _reference(c: int) -> Dictionary:
	if _running.is_empty():
		return {}
	return _running[c] if c < _running.size() else _running[0]


## 칸(c)의 값이 지금 실험과 다른가(강조 기준).
func _differs(c: int, key: String) -> bool:
	var ref := _reference(c)
	if ref.is_empty():
		return false
	if key == KEY_SEED:
		return int(_cols[c].seed) != int(ref.seed)
	return not SimConfig.deep_equal(_value(c, key), SimConfig.get_value(ref.cfg, key))


## 칸(c)이 지금 실험과 다른 값 수(설정 잎 키 + 씨앗).
func _diff_count(c: int) -> int:
	if _reference(c).is_empty():
		return 0
	var n := 0
	for key in _leaf_order:
		if _differs(c, key):
			n += 1
	if _differs(c, KEY_SEED):
		n += 1
	return n


func _visible_cols() -> Array[int]:
	var out: Array[int] = [0]
	if _compare_on:
		out.append(1)
	return out


# ════════════════════════════ 설정 키 목록 ════════════════════════════

## sim-defaults.json 의 잎 키와 종류. JSON 을 읽으면 수가 모두 실수가 되므로 정수 키는 파일 글자(소수점 없는 수)로 가린다.
static func _scan_leaves() -> void:
	if not _leaf_order.is_empty():
		return
	var ints := {}
	var text := FileAccess.get_file_as_string(SimConfig.DEFAULTS_PATH)
	var sec_re := RegEx.create_from_string("\"(\\w+)\"\\s*:\\s*\\{([^{}]*)\\}")
	var int_re := RegEx.create_from_string("\"(\\w+)\"\\s*:\\s*(-?\\d+)\\s*(?=[,}\\s])")
	for m in sec_re.search_all(text):
		for l in int_re.search_all(m.get_string(2)):
			ints[m.get_string(1) + "." + l.get_string(1)] = true
	var d := SimConfig.defaults()
	for sec: String in d:
		if typeof(d[sec]) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = d[sec]
		for k: String in s:
			var key := sec + "." + k
			var kind := KIND_OTHER
			match typeof(s[k]):
				TYPE_BOOL:
					kind = KIND_BOOL
				TYPE_INT, TYPE_FLOAT:
					kind = KIND_INT if ints.has(key) else KIND_FLOAT
			_leaf_order.append(key)
			_leaf_kind[key] = kind


## 설정 잎 키 종류("int"·"float"·"bool"·"other", 없는 키 "").
static func leaf_kind(key: String) -> String:
	_scan_leaves()
	return str(_leaf_kind.get(key, ""))


## 설정 잎 키 전부(sim-defaults.json 순서).
static func leaf_keys() -> Array[String]:
	_scan_leaves()
	return _leaf_order.duplicate()


## 예설정이 적용된 설정(바꾼 값 없음, 캐시 사본을 고치지 말 것).
static func _preset_config(preset_name: String) -> Dictionary:
	if not _preset_cache.has(preset_name):
		var b := SimConfig.build(preset_name, {})
		_preset_cache[preset_name] = b.config
	return _preset_cache[preset_name]


## 값 글자: 정수 키는 정수, 실수는 Godot 기본 표기(JSON 과 같은 자릿수 — 왕복하는 값 그대로), 참거짓·배열은 JSON.
static func format_value(key: String, v: Variant) -> String:
	if v == null:
		return "—"
	match typeof(v):
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT, TYPE_FLOAT:
			if leaf_kind(key) == KIND_INT:
				return str(int(v))
			return str(float(v))
	return JSON.stringify(v)


# ════════════════════════════ 지금 실험 ════════════════════════════

func _on_experiments_changed(list: Array) -> void:
	_running.clear()
	for item in list:
		var x := item as Experiment
		if x == null or x.world == null:
			continue
		# 읽기 전용 cfg 를 깊은 사본으로 떠서 견주기에만 쓴다(세계 쪽 사전은 건드리지 않음)
		var cfg: Dictionary = (x.world.cfg as Dictionary).duplicate(true)
		_running.append({tag = x.tag, label = x.label, seed = x.seed_value, cfg = cfg, preset = x.preset,
				overrides = x.overrides.duplicate(true), snapshot = x.snapshot_path})
	# 패널은 지금 돌고 있는 실험의 조건에서 시작한다(스냅숏이면 가장 가까운 예설정 + 다른 값)
	for k in mini(_running.size(), _cols.size()):
		var col := _settings_from_running(_running[k])
		if not col.is_empty():
			_cols[k] = col
			_validate(k)
	var comparing := _running.size() > 1
	if comparing and not _compare_on:
		_compare_on = true
		_compare_btn.set_pressed_no_signal(true)
	elif not comparing and _was_comparing and _compare_on:
		_compare_on = false
		_adv_col = 0
		_compare_btn.set_pressed_no_signal(false)
	_was_comparing = comparing
	_action_error = ""
	_fill_now()
	_refresh()


## 지금 실험의 조건을 패널 칸으로. 만든 실험이면 그 조건 그대로, 스냅숏이면 다른 값이 가장 적은 예설정 + 다른 값.
## 그렇게 만든 조건이 SimConfig.build 를 통과하지 못하면 {}(패널 값 그대로 둠).
func _settings_from_running(r: Dictionary) -> Dictionary:
	var preset := str(r.preset)
	var ov: Dictionary = r.overrides
	if preset == "" or not SimConfig.presets().has(preset):
		var best := ""
		var best_n := -1
		for p in SimConfig.preset_names():
			var d := _config_diff(_preset_config(p), r.cfg)
			if best_n < 0 or d.size() < best_n:
				best = p
				best_n = d.size()
				ov = d
		preset = best
	else:
		# 예설정과 같은 값은 빼 둔다(바꾼 값 = 예설정과 다른 값만)
		var pc := _preset_config(preset)
		var kept := {}
		for k: String in ov:
			if not SimConfig.deep_equal(ov[k], SimConfig.get_value(pc, k)):
				kept[k] = ov[k]
		ov = kept
	if preset == "" or SimConfig.build(preset, ov).error != "":
		return {}
	return _new_col(preset, clampi(int(r.seed), 0, _seed_max), ov)


## 두 설정에서 값이 다른 잎 키 → cfg 쪽 값(종류가 같고 cfg 에 있는 것만).
static func _config_diff(base: Dictionary, cfg: Dictionary) -> Dictionary:
	var out := {}
	for key in _leaf_order:
		var a: Variant = SimConfig.get_value(base, key)
		var b: Variant = SimConfig.get_value(cfg, key)
		if b == null or typeof(a) != typeof(b):
			continue
		if not SimConfig.deep_equal(a, b):
			out[key] = b.duplicate(true) if typeof(b) == TYPE_ARRAY else b
	return out


## "지금 실험" 묶음을 다시 채운다(실험마다 이름 한 줄 + 세 값 한 줄).
func _fill_now() -> void:
	for ch in _now_box.get_children():
		_now_box.remove_child(ch)
		ch.queue_free()
	if _running.is_empty():
		var l := _dim_label(TEXT_NO_EXPERIMENT if _lab != null else TEXT_NO_LAB)
		_now_box.add_child(l)
		return
	for k in _running.size():
		var r := _running[k]
		var item := VBoxContainer.new()
		item.add_theme_constant_override("separation", 0)
		_now_box.add_child(item)
		var head := HBoxContainer.new()
		item.add_child(head)
		if _running.size() > 1:
			head.add_child(_chip(k))
		var name_l := Label.new()
		# 낱말 단위로 줄바꿈(한글 음절 사이 "발/견" 에서 끊지 않게 — 통합 때 고침)
		name_l.text = UiTheme.keep_words(("%s · %s" % [str(r.tag), str(r.label)]) if str(r.tag) != "" else str(r.label))
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.theme_type_variation = UiTheme.VALUE
		head.add_child(name_l)
		var parts: Array[String] = []
		for key in MAIN_KEYS:
			parts.append("%s %s" % [str(MAIN_SHORT[key]), format_value(key, SimConfig.get_value(r.cfg, key))])
		var vals := _dim_label(UiTheme.keep_words(" · ".join(parts)))
		vals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.add_child(vals)


# ════════════════════════════ 화면 갱신 ════════════════════════════

## 상태(칸 값·지금 실험)를 화면에 옮긴다. 초점이 있는(입력 중인) 칸의 글자는 덮어쓰지 않는다.
func _refresh() -> void:
	if _status == null:
		return
	_syncing = true
	_refresh_controls()
	_syncing = false


func _refresh_controls() -> void:
	for c in _cards.size():
		var card: Dictionary = _cards[c]
		var shown := c == 0 or _compare_on
		(card.root as Control).visible = shown
		(card.head as Control).visible = _compare_on
		if shown:
			_refresh_card(c)
	_next_title.visible = not _compare_on
	_apply_btn.visible = not _compare_on
	_start_compare_btn.visible = _compare_on
	_apply_btn.disabled = str(_cols[0].error) != ""
	_start_compare_btn.disabled = str(_cols[0].error) != "" or str(_cols[1].error) != ""
	var any_override := false
	for c in _visible_cols():
		any_override = any_override or not (_cols[c].overrides as Dictionary).is_empty()
	_revert_btn.disabled = not any_override
	_refresh_status()
	_adv_target.visible = _compare_on
	for k in _adv_target_btns.size():
		_adv_target_btns[k].set_pressed_no_signal(k == _adv_col)
	var ov_n := (_cols[_adv_col].overrides as Dictionary).size()
	var mark := UiTheme.glyph_or(GLYPH_OPEN if _adv_open else GLYPH_CLOSED, "-" if _adv_open else "+")
	_adv_toggle.text = "%s 고급 설정" % mark
	_adv_note.text = "예설정과 다른 값 %d개" % ov_n if ov_n > 0 else "모든 설정 키(sim-defaults.json)"
	_adv_box.visible = _adv_open
	if _adv_open:
		_refresh_advanced()


func _refresh_card(c: int) -> void:
	var card: Dictionary = _cards[c]
	var col := _cols[c]
	var opt := card.preset as OptionButton
	for i in opt.item_count:
		if str(opt.get_item_metadata(i)) == str(col.preset):
			if opt.selected != i:
				opt.select(i)
			opt.tooltip_text = "%s (%s)" % [opt.get_item_text(i), str(col.preset)]
	var spin := card.seed as SpinBox
	if not spin.get_line_edit().has_focus() and int(spin.value) != int(col.seed):
		spin.set_value_no_signal(float(col.seed))
	_mark(card.seed_stripe as ColorRect, card.seed_label as Label, _differs(c, KEY_SEED), false)
	var seed_err := card.seed_err as Label
	_set_err(seed_err, str(col.field_msg) if str(col.field_key) == KEY_SEED else "")
	var mentioned := _mentioned(str(col.error))
	var rows: Dictionary = card.rows
	for key: String in rows:
		var row: Dictionary = rows[key]
		var v: Variant = _value(c, key)
		var field := row.field as LineEdit
		if not field.has_focus():
			var t := format_value(key, v)
			if field.text != t:
				field.text = t
		var slider := row.slider as HSlider
		if key == "population.initial":
			# 초기 개체 수 슬라이더 끝 = min(ui.param.initial_max, 이 칸 조건의 population.cap)
			var cap: Variant = _value(c, "population.cap")
			var hi := UiConfig.num("param.initial_max")
			if cap != null:
				hi = minf(hi, float(cap))
			slider.max_value = maxf(slider.min_value, hi)
			slider.tooltip_text = "%s ~ %s (ui.param.initial_max 와 population.cap 중 작은 값)" % [str(int(slider.min_value)), str(int(slider.max_value))]
		if v != null:
			slider.set_value_no_signal(float(v))
		var diff := _differs(c, key)
		var bad := mentioned.has(key)
		_mark(row.stripe as ColorRect, row.name as Label, diff, bad)
		_tint(field, _c_accent if diff else _c_text)
		_set_err(row.err as Label, _row_message(col, key, mentioned))


func _refresh_advanced() -> void:
	var c := _adv_col
	var col := _cols[c]
	var mentioned := _mentioned(str(col.error))
	for key: String in _adv_rows:
		var row: Dictionary = _adv_rows[key]
		var v: Variant = _value(c, key)
		var diff := _differs(c, key)
		var bad := mentioned.has(key)
		_mark(row.stripe as ColorRect, row.name as Label, diff, bad)
		var f: Control = row.field
		if f is CheckBox:
			(f as CheckBox).set_pressed_no_signal(bool(v))
		elif f is LineEdit:
			var le := f as LineEdit
			if not le.has_focus():
				var t := format_value(key, v)
				if le.text != t:
					le.text = t
			_tint(le, _c_accent if diff else _c_text)
		var ref := _reference(c)
		var tip := "%s\n예설정(%s) 값: %s" % [key, str(col.preset), format_value(key, SimConfig.get_value(_preset_config(str(col.preset)), key))]
		if not ref.is_empty():
			tip += "\n지금 실험 값: %s" % format_value(key, SimConfig.get_value(ref.cfg, key))
		if str(row.kind) == KIND_OTHER:
			tip += "\n패널에서 바꿀 수 없는 값(예설정·명령줄 --set 으로)"
		(row.name as Label).tooltip_text = tip
		_set_err(row.err as Label, _row_message(col, key, mentioned))


## 줄 아래 오류: 칸에 적은 글자 오류(그 줄) 또는 조건 오류(오류 문장이 가리키는 줄, 가리키는 줄이 없으면 마지막으로 바꾼 줄).
func _row_message(col: Dictionary, key: String, mentioned: Array[String]) -> String:
	if str(col.field_key) == key:
		return str(col.field_msg)
	var err := str(col.error)
	if err == "":
		return ""
	if mentioned.has(key) or (mentioned.is_empty() and str(col.last_key) == key):
		return err
	return ""


## 오류 문장이 가리키는 설정 키들.
func _mentioned(err: String) -> Array[String]:
	var out: Array[String] = []
	if err == "":
		return out
	for key in _leaf_order:
		if err.contains(key):
			out.append(key)
	return out


func _refresh_status() -> void:
	var text := ""
	var col := _c_dim
	var errs: Array[String] = []
	for c in _visible_cols():
		if str(_cols[c].error) != "":
			errs.append(("%s: " % COL_TAGS[c] if _compare_on else "") + str(_cols[c].error))
	if _lab == null or not is_instance_valid(_lab):
		text = TEXT_NO_LAB
	elif _running.is_empty():
		text = TEXT_NO_EXPERIMENT
	elif not errs.is_empty():
		text = "설정 오류 — 고쳐야 시작할 수 있습니다"
		col = _c_danger
	elif _compare_on and _running.size() < 2:
		text = TEXT_COMPARE_IDLE
		col = _c_accent
	else:
		var n := 0
		for c in _visible_cols():
			n += _diff_count(c)
		if n == 0:
			text = TEXT_SAME
		else:
			text = (TEXT_PENDING_COMPARE if _compare_on else TEXT_PENDING) % n
			col = _c_accent
	_status.text = text
	_tint(_status, col)
	if _action_error != "":
		errs.append(_action_error)
	_set_err(_error, "\n".join(errs))


## 강조 띠·이름 색: 지금 실험과 다르면 강조 색 띠, 오류가 가리키면 위험 색 이름.
func _mark(stripe: ColorRect, name_l: Label, diff: bool, bad: bool) -> void:
	var sc := Color(_c_accent, 1.0 if diff else 0.0)
	if stripe.color != sc:
		stripe.color = sc
	_tint(name_l, _c_danger if bad else (_c_text if diff else _c_dim))


## 글자 색을 바뀔 때만 덮어쓴다(같은 색을 다시 넣으면 테마 변경 알림·배치가 돈다 — 슬라이더를 끄는 동안 줄 수십 개).
static func _tint(c: Control, col: Color) -> void:
	if not c.has_theme_color_override("font_color") or c.get_theme_color("font_color") != col:
		c.add_theme_color_override("font_color", col)


func _set_err(l: Label, text: String) -> void:
	if l.text != text:
		l.text = text
	l.visible = text != ""


## 동작 결과를 패널 안 빨간 글로(+ 알림). what 이 비어 있으면 알림 없이(LabMain 이 이미 알림을 띄우는 동작).
func _report(err: String, what: String) -> void:
	_action_error = err
	if err != "" and what != "" and _lab != null and is_instance_valid(_lab):
		_lab.show_toast("%s: %s" % [what, err], "error")
	_refresh()


# ════════════════════════════ 입력 ════════════════════════════

## 입력 중인 칸(초점이 있는 글 칸·씨앗)을 확정한다(단추는 초점을 받지 않아 칸이 그대로 초점을 쥐고 있을 수 있음).
func _commit_edits() -> void:
	for c in _cards.size():
		var card: Dictionary = _cards[c]
		var spin := card.seed as SpinBox
		if spin.get_line_edit().has_focus():
			spin.apply()
		var rows: Dictionary = card.rows
		for key: String in rows:
			var le := rows[key].field as LineEdit
			if le.has_focus():
				_commit_field(le, key, c)
	for key: String in _adv_rows:
		var f: Control = _adv_rows[key].field
		if f is LineEdit and f.has_focus():
			_commit_field(f as LineEdit, key, _adv_col)


## 글 칸 확정: 지금 값과 글자가 같으면 아무것도 안 함(초점이 빠질 때·Enter 가 겹쳐도 한 번만).
func _commit_field(le: LineEdit, key: String, c: int) -> void:
	if le.text.strip_edges() == format_value(key, _value(c, key)):
		return
	var err := set_value(key, le.text, c)
	if str(_cols[c].field_key) == key and err != "":
		# 해석할 수 없는 글자: 오류를 그 줄 아래에 보이고 칸은 지금 값으로 되돌림
		le.text = format_value(key, _value(c, key))


func _on_field_submitted(_t: String, le: LineEdit, key: String, which: int) -> void:
	var c := _adv_col if which < 0 else which
	_commit_field(le, key, c)
	le.release_focus()


func _on_field_focus_exited(le: LineEdit, key: String, which: int) -> void:
	_commit_field(le, key, _adv_col if which < 0 else which)


## 글 칸에서 Esc = 적던 글자를 버리고 초점 풀기(단축키는 LabMain 이 글 칸 초점 중에는 무시함).
func _on_field_gui_input(ev: InputEvent, le: LineEdit, key: String, which: int) -> void:
	var k := ev as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		le.text = format_value(key, _value(_adv_col if which < 0 else which, key))
		le.release_focus()
		le.accept_event()


func _on_seed_gui_input(ev: InputEvent, spin: SpinBox) -> void:
	var k := ev as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		var le := spin.get_line_edit()
		le.text = str(int(spin.value))
		le.release_focus()
		le.accept_event()


func _on_slider(v: float, key: String, which: int) -> void:
	if _syncing:
		return
	set_value(key, _snap(key, v), which)


## 슬라이더 값을 눈금 자릿수의 글자로 바꿨다 다시 읽는다(0.30000000000000004 같은 값이 JSON 왕복 검사에 걸리지 않게).
func _snap(key: String, v: float) -> Variant:
	if leaf_kind(key) == KIND_INT:
		return roundi(v)
	var step := _step_of(key)
	var digits := maxi(0, int(ceilf(-log(step) / log(10.0) - 1e-9))) if step > 0.0 else 6
	return String.num(snappedf(v, step) if step > 0.0 else v, digits).to_float()


func _step_of(key: String) -> float:
	match key:
		"mutation.rate":
			return UiConfig.num("param.mutation_rate_step")
		"resources.scale":
			return UiConfig.num("param.resource_scale_step")
	return UiConfig.num("param.initial_step")


func _on_preset_selected(idx: int, which: int) -> void:
	if _syncing:
		return
	var opt := _cards[which].preset as OptionButton
	set_value(KEY_PRESET, str(opt.get_item_metadata(idx)), which)


func _on_seed_changed(v: float, which: int) -> void:
	if _syncing:
		return
	set_value(KEY_SEED, int(v), which)


## 무작위 씨앗: 화면 쪽 시각으로 씨앗을 준 따로 쓰는 난수기에서 고른다(시뮬레이션 난수·Godot 전역 난수와 무관).
func random_seed(which: int = 0) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Time.get_ticks_usec()) ^ hash(Time.get_unix_time_from_system()) ^ hash(which)
	var v := rng.randi_range(0, _seed_max)
	set_value(KEY_SEED, v, which)
	return int(_cols[which].seed)


func _on_adv_toggled(on: bool, key: String) -> void:
	if _syncing:
		return
	set_value(key, on, _adv_col)


func _on_export() -> void:
	if _lab == null or not is_instance_valid(_lab):
		_report(TEXT_NO_LAB, "")
		return
	export_to(_lab.default_export_dir())


# ════════════════════════════ 스냅숏 ════════════════════════════

## 스냅숏 대화 상자(저장·열기, 파일 시스템, *.json, 시작 폴더 user://experiments — 없으면 만듦)를 띄운다.
func open_snapshot_dialog(save: bool) -> FileDialog:
	_commit_edits()
	var dir := ProjectSettings.globalize_path(SNAPSHOT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var d := _save_dialog if save else _open_dialog
	if d == null:
		d = FileDialog.new()
		d.name = "SaveSnapshotDialog" if save else "OpenSnapshotDialog"
		d.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
		d.access = FileDialog.ACCESS_FILESYSTEM
		d.filters = PackedStringArray(["*.json ; 스냅숏 JSON"])
		d.title = "스냅숏 저장" if save else "스냅숏 열기"
		d.cancel_button_text = "취소"
		# 운영 체제 대화 상자를 쓸 수 있으면 그것(OS 말로 나오고, 엔진 대화 상자는 한글 경로에서 "권한 없음" 문구를
		# 잘못 띄움 — 엔진 4.4 의 is_readable 이 경로를 UTF-8 로 넘기지 않음). 못 쓰면(헤드리스·포털 없는 Linux) 엔진 대화 상자.
		d.use_native_dialog = true
		d.file_selected.connect(_on_snapshot_save if save else _on_snapshot_open)
		add_child(d)
		if save:
			_save_dialog = d
		else:
			_open_dialog = d
	d.current_dir = dir
	if save:
		d.current_file = _default_snapshot_name()
	d.popup_centered(Vector2i(UiConfig.integer("param.dialog_width"), UiConfig.integer("param.dialog_height")))
	return d


## 저장 파일 기본 이름 snapshot-<날짜-시각>-seed<N>-tick<T>.json(시각은 이름에만 씀).
func _default_snapshot_name() -> String:
	var t := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d-%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
	var x: Experiment = _lab.experiment(0) if _lab != null and is_instance_valid(_lab) else null
	if x == null:
		return "snapshot-%s.json" % stamp
	return "snapshot-%s-seed%d-tick%d.json" % [stamp, x.seed_value, x.world.tick]


## 저장: 혼자면 그 파일, 비교 중이면 <이름>-A.json·<이름>-B.json 두 파일. 성공 알림은 LabMain 이 띄운다.
func save_snapshot_to(path: String) -> String:
	if _lab == null or not is_instance_valid(_lab):
		_report(TEXT_NO_LAB, "")
		return TEXT_NO_LAB
	var errs: Array[String] = []
	var n := _lab.experiments.size()
	for k in n:
		var p := path
		if n > 1:
			p = "%s-%s.%s" % [path.get_basename(), _lab.experiments[k].tag, path.get_extension() if path.get_extension() != "" else "json"]
		var e := _lab.save_snapshot(p, k)
		if e != "":
			errs.append(e)
	var err := "\n".join(errs)
	_report(err, "스냅숏을 저장할 수 없습니다")
	return err


## 열기: lab.open_snapshot(혼자 모드로). 실패하면 패널 안 빨간 글 + 알림.
func open_snapshot_from(path: String) -> String:
	if _lab == null or not is_instance_valid(_lab):
		_report(TEXT_NO_LAB, "")
		return TEXT_NO_LAB
	var err := _lab.open_snapshot(path)
	_report(err, "스냅숏을 열 수 없습니다")
	return err


func _on_snapshot_save(path: String) -> void:
	save_snapshot_to(path)


func _on_snapshot_open(path: String) -> void:
	open_snapshot_from(path)


# ════════════════════════════ 소리 ════════════════════════════

## 실험실의 LabSound 자식(없으면 null).
func _sound() -> LabSound:
	if _lab == null or not is_instance_valid(_lab):
		return null
	for ch in _lab.get_children():
		if ch is LabSound and not ch.is_queued_for_deletion():
			return ch as LabSound
	return null


func _on_lab_children(_n: Node) -> void:
	_sync_sound.call_deferred()


func _sync_sound() -> void:
	if not is_instance_valid(_sound_check):
		return
	var s := _sound()
	_sound_check.disabled = s == null
	_sound_check.set_pressed_no_signal(s != null and s.enabled)
	_sound_check.tooltip_text = "발견·멸종 등 사건 효과음" if s != null else "소리 장치(LabSound)가 없습니다"


func _on_sound_toggled(on: bool) -> void:
	var s := _sound()
	if s != null:
		s.enabled = on
	_sync_sound()


# ════════════════════════════ 배치 ════════════════════════════

func _build() -> void:
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	add_child(_scroll)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", _gap)
	_scroll.add_child(_body)

	var title := Label.new()
	title.text = "실험 조건"
	title.theme_type_variation = UiTheme.TITLE
	_body.add_child(title)

	# 지금 실험(돌고 있는 것)
	var now := PanelContainer.new()
	now.name = "Now"
	now.theme_type_variation = UiTheme.CARD
	_body.add_child(now)
	var now_v := VBoxContainer.new()
	now_v.add_theme_constant_override("separation", _row_gap)
	now.add_child(now_v)
	now_v.add_child(_dim_label("지금 실험"))
	_now_box = VBoxContainer.new()
	_now_box.add_theme_constant_override("separation", _gap / 2)
	now_v.add_child(_now_box)
	_fill_now()

	# 다음 실험 조건(A, 비교 모드면 B 도)
	_next_title = _dim_label("다음 실험 — 새 실험을 누르면 적용")
	_next_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_next_title)
	for c in COL_TAGS.size():
		_cards.append(_build_card(c))
		_body.add_child(_cards[c].root)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", _fs_small)
	_body.add_child(_status)
	_error = _err_label()
	_error.name = "Error"
	_body.add_child(_error)

	_apply_btn = _button("새 실험", "패널 조건으로 새 세계를 만듦(지금 실험은 끝남)")
	_apply_btn.theme_type_variation = UiTheme.ACCENT_BUTTON
	_apply_btn.pressed.connect(func() -> void: apply())
	_body.add_child(_apply_btn)
	_start_compare_btn = _button("나란히 시작", "A·B 조건으로 두 세계를 나란히 시작(같은 배속)")
	_start_compare_btn.theme_type_variation = UiTheme.ACCENT_BUTTON
	_start_compare_btn.pressed.connect(func() -> void: apply_compare())
	_body.add_child(_start_compare_btn)
	var row := _hbox()
	_body.add_child(row)
	_revert_btn = _button("되돌리기", "바꾼 값을 지워 고른 예설정 값으로(씨앗은 그대로)")
	_revert_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_revert_btn.pressed.connect(revert)
	row.add_child(_revert_btn)
	_compare_btn = _button("비교 모드", "두 조건(A·B)을 나란히 돌려 견줌")
	_compare_btn.toggle_mode = true
	_compare_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compare_btn.toggled.connect(set_compare_mode)
	row.add_child(_compare_btn)

	_body.add_child(HSeparator.new())
	_export_btn = _button("CSV 내보내기", "결과 폴더(시계열·연대기·계통 CSV, 요약, 스냅숏)를 %s/<날짜-시각>-seed<N> 에" % SNAPSHOT_DIR)
	_export_btn.pressed.connect(_on_export)
	_body.add_child(_export_btn)
	var srow := _hbox()
	_body.add_child(srow)
	_save_btn = _button("스냅숏 저장", "지금 세계를 JSON 파일로(비교 중이면 A·B 두 파일)")
	_save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_btn.pressed.connect(func() -> void: open_snapshot_dialog(true))
	srow.add_child(_save_btn)
	_open_btn = _button("스냅숏 열기", "저장한 세계를 열어 이어서 진행(혼자 모드)")
	_open_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open_btn.pressed.connect(func() -> void: open_snapshot_dialog(false))
	srow.add_child(_open_btn)
	_sound_check = _check_box()
	_sound_check.text = "소리"
	_sound_check.focus_mode = Control.FOCUS_NONE
	_sound_check.toggled.connect(_on_sound_toggled)
	_body.add_child(_sound_check)
	_sync_sound()

	_body.add_child(HSeparator.new())
	_build_advanced()


## 조건 칸 하나(예설정·씨앗·세 값). 비교 모드에서는 머리에 A/B 이름표.
func _build_card(c: int) -> Dictionary:
	var root := PanelContainer.new()
	root.name = "Card" + COL_TAGS[c]
	root.theme_type_variation = UiTheme.CARD
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _row_gap * 2)
	root.add_child(v)
	var head := _hbox()
	head.add_child(_chip(c))
	var tl := Label.new()
	tl.text = COL_TAGS[c]
	tl.theme_type_variation = UiTheme.VALUE
	head.add_child(tl)
	head.add_child(_dim_label(COL_SIDES[c]))
	v.add_child(head)

	var lw := UiConfig.num("param.label_width")
	# 예설정
	var prow := _hbox()
	v.add_child(prow)
	# 예설정 줄에는 강조 띠가 없지만 같은 자리를 비워 둔다(이름·칸이 아래 줄들과 같은 세로선에 서게)
	prow.add_child(_stripe())
	var pl := Label.new()
	pl.text = "예설정"
	pl.add_theme_color_override("font_color", _c_dim)
	pl.custom_minimum_size.x = lw
	prow.add_child(pl)
	var opt := OptionButton.new()
	opt.fit_to_longest_item = false
	opt.clip_text = true
	opt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	opt.focus_mode = Control.FOCUS_NONE
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ps := SimConfig.presets()
	for pname in SimConfig.preset_names():
		opt.add_item(str((ps[pname] as Dictionary).get("label", pname)))
		var i := opt.item_count - 1
		opt.set_item_metadata(i, pname)
		opt.set_item_tooltip(i, pname)
	opt.item_selected.connect(_on_preset_selected.bind(c))
	prow.add_child(opt)

	# 씨앗
	var srow := _hbox()
	v.add_child(srow)
	var sstripe := _stripe()
	srow.add_child(sstripe)
	var sl := Label.new()
	sl.text = "씨앗"
	sl.custom_minimum_size.x = lw
	srow.add_child(sl)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = _seed_max
	spin.step = 1
	spin.rounded = true
	spin.select_all_on_focus = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.custom_minimum_size.x = UiConfig.num("param.seed_field_min_width")
	spin.get_line_edit().add_theme_constant_override("minimum_character_width", 0)
	spin.tooltip_text = "씨앗 0 ~ %d (같은 씨앗·조건 = 같은 역사)" % _seed_max
	spin.value_changed.connect(_on_seed_changed.bind(c))
	# Enter = 확정하고 초점 풀기(지도로 돌아가면 단축키가 바로 동작), Esc = 적던 글자 버리기
	spin.get_line_edit().text_submitted.connect(func(_t: String) -> void: spin.get_line_edit().release_focus())
	spin.get_line_edit().gui_input.connect(_on_seed_gui_input.bind(spin))
	srow.add_child(spin)
	var rnd := _button("무작위", "화면 쪽 시각으로 고른 씨앗(시뮬레이션 난수와 무관)")
	# 글자가 잘리지 않게(씨앗 칸이 대신 줄어듦)
	rnd.clip_text = false
	rnd.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	rnd.pressed.connect(func() -> void: random_seed(c))
	srow.add_child(rnd)
	var serr := _err_label()
	v.add_child(serr)

	var rows := {}
	for key in MAIN_KEYS:
		rows[key] = _build_main_row(v, c, key)
	return {root = root, head = head, preset = opt, seed = spin, seed_stripe = sstripe, seed_label = sl,
			seed_err = serr, random = rnd, rows = rows}


## 주요 값 한 줄: [띠][이름 ……][숫자 칸] / [슬라이더] / [오류].
func _build_main_row(parent: VBoxContainer, c: int, key: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _row_gap)
	parent.add_child(box)
	var top := _hbox()
	box.add_child(top)
	var stripe := _stripe()
	top.add_child(stripe)
	var nl := Label.new()
	nl.text = str(MAIN_NAMES[key])
	nl.tooltip_text = key
	nl.mouse_filter = Control.MOUSE_FILTER_PASS
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(nl)
	var field := _field(UiConfig.num("param.value_field_width"))
	field.tooltip_text = "%s — 직접 적으면 슬라이더 범위 밖 값도 됨(설정 검사 범위 안)" % key
	_wire_field(field, key, c)
	top.add_child(field)
	var slider := HSlider.new()
	slider.scrollable = false
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match key:
		"mutation.rate":
			slider.min_value = 0.0
			slider.max_value = UiConfig.num("param.mutation_rate_max")
		"resources.scale":
			slider.min_value = 0.0
			slider.max_value = UiConfig.num("param.resource_scale_max")
		_:
			slider.min_value = UiConfig.num("param.initial_min")
			slider.max_value = UiConfig.num("param.initial_max")
	slider.step = _step_of(key)
	if key != "population.initial":
		slider.tooltip_text = "%s ~ %s" % [str(slider.min_value), str(slider.max_value)]
	slider.value_changed.connect(_on_slider.bind(key, c))
	box.add_child(slider)
	var err := _err_label()
	box.add_child(err)
	return {stripe = stripe, name = nl, field = field, slider = slider, err = err}


## 고급 설정: 펼침 단추 + (비교 모드) A/B 고르기 + 절별 잎 키 줄.
func _build_advanced() -> void:
	var head := _hbox()
	_body.add_child(head)
	_adv_toggle = Button.new()
	_adv_toggle.name = "AdvancedToggle"
	_adv_toggle.theme_type_variation = UiTheme.FLAT_BUTTON
	_adv_toggle.toggle_mode = true
	_adv_toggle.focus_mode = Control.FOCUS_NONE
	_adv_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_adv_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_adv_toggle.tooltip_text = "sim-defaults.json 의 모든 설정 키(수·참거짓은 바꿀 수 있음)"
	_adv_toggle.toggled.connect(set_advanced_open)
	head.add_child(_adv_toggle)
	_adv_target = _hbox()
	head.add_child(_adv_target)
	for c in COL_TAGS.size():
		var b := Button.new()
		b.text = COL_TAGS[c]
		b.toggle_mode = true
		b.button_group = _adv_target_group
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "%s 칸의 고급 설정" % COL_TAGS[c]
		b.pressed.connect(set_advanced_target.bind(c))
		_adv_target.add_child(b)
		_adv_target_btns.append(b)
	_adv_note = _dim_label("")
	_adv_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_adv_note)
	_adv_box = VBoxContainer.new()
	_adv_box.name = "Advanced"
	_adv_box.add_theme_constant_override("separation", _row_gap)
	_body.add_child(_adv_box)
	var fw := UiConfig.num("param.advanced_field_width")
	var last_sec := ""
	for key in _leaf_order:
		var sec := key.get_slice(".", 0)
		var leaf := key.substr(sec.length() + 1)
		if sec != last_sec:
			last_sec = sec
			var sh := Label.new()
			sh.text = "%s · %s" % [str(SECTION_NAMES.get(sec, sec)), sec]
			sh.theme_type_variation = UiTheme.VALUE
			sh.add_theme_font_size_override("font_size", _fs_small)
			sh.add_theme_color_override("font_color", _c_dim)
			if _adv_box.get_child_count() > 0:
				var sp := Control.new()
				sp.custom_minimum_size.y = float(_row_gap * 2)
				_adv_box.add_child(sp)
			_adv_box.add_child(sh)
		var kind := str(_leaf_kind[key])
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		_adv_box.add_child(box)
		var r := _hbox()
		box.add_child(r)
		var stripe := _stripe()
		r.add_child(stripe)
		var nl := Label.new()
		nl.text = leaf
		nl.mouse_filter = Control.MOUSE_FILTER_PASS
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nl.add_theme_font_size_override("font_size", _fs_small)
		r.add_child(nl)
		var field: Control
		if kind == KIND_BOOL:
			var cb := _check_box()
			cb.focus_mode = Control.FOCUS_NONE
			cb.toggled.connect(_on_adv_toggled.bind(key))
			field = cb
		else:
			var le := _field(fw)
			le.add_theme_font_size_override("font_size", _fs_small)
			if kind == KIND_OTHER:
				le.editable = false
				le.alignment = HORIZONTAL_ALIGNMENT_LEFT
			else:
				_wire_field(le, key, -1)
			field = le
		field.tooltip_text = key
		r.add_child(field)
		var err := _err_label()
		box.add_child(err)
		_adv_rows[key] = {row = box, stripe = stripe, name = nl, field = field, err = err, kind = kind}


func _wire_field(le: LineEdit, key: String, which: int) -> void:
	le.text_submitted.connect(_on_field_submitted.bind(le, key, which))
	le.focus_exited.connect(_on_field_focus_exited.bind(le, key, which))
	le.gui_input.connect(_on_field_gui_input.bind(le, key, which))


func _field(w: float) -> LineEdit:
	var le := LineEdit.new()
	le.custom_minimum_size.x = w
	# 최소 폭은 위 값으로만(기본 "글자 4개" 최소 폭이 좁은 자리에서 패널을 밀어 넓히지 않게)
	le.add_theme_constant_override("minimum_character_width", 0)
	le.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	le.select_all_on_focus = true
	le.context_menu_enabled = false
	return le


func _button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return b


## 바탕 없는 확인 상자(기본 모양의 못 씀·올림 바탕이 패널 위에서 큰 어두운 상자로 보이지 않게).
func _check_box() -> CheckBox:
	var cb := CheckBox.new()
	cb.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		cb.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	return cb


func _hbox() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UiConfig.integer("theme.separation"))
	return h


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = UiTheme.DIM
	return l


func _err_label() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", _c_danger)
	l.add_theme_font_size_override("font_size", _fs_small)
	l.visible = false
	return l


## 바꾼 값 표시 띠(강조 색, 지금 실험과 다를 때만 칠함). 꺼져도 자리는 지킨다(이름이 옆으로 흔들리지 않게).
func _stripe() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(_stripe_w, 0.0)
	r.color = Color(_c_accent, 0.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _stripe_on(stripe: ColorRect) -> bool:
	return stripe.color.a > 0.5


## A·B 이름표 색 점(그래프 계열 색).
func _chip(c: int) -> Control:
	var s := UiConfig.num("param.chip_size")
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := ColorRect.new()
	r.color = _c_series[clampi(c, 0, _c_series.size() - 1)]
	r.custom_minimum_size = Vector2(s, s)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(r)
	return cc


func _main_row(which: int, key: String) -> Dictionary:
	if which < 0 or which >= _cards.size():
		return {}
	var rows: Dictionary = _cards[which].rows
	return rows.get(key, {})


func _labels_in(n: Node) -> Array[Label]:
	var out: Array[Label] = []
	if n is Label:
		out.append(n as Label)
	for ch in n.get_children():
		out.append_array(_labels_in(ch))
	return out
