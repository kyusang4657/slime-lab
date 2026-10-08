class_name LabMain
extends Control
## 실험실 주 화면. 계약: docs/VIEW-API.md "LabMain"·"4단계 계약".
## 위쪽 막대(재생·속도·상태) / [왼쪽 자리 | 지도 관찰 창(SubViewport + MapView, 비교 모드면 A | B 둘)] 아래 자리 | 개체 정보 창.
## 시뮬레이션을 진행(step)하고 사건을 소비(drain_events)하는 것은 화면 가운데 여기뿐이다(Experiment 를 거쳐). 배열에는 쓰지 않는다.

signal ticked(world: SimWorld)
signal events(list: Array)
## 새 실험을 만들었거나 스냅숏을 열어 세계가 바뀌었을 때(4단계 그래프·연대기가 지난 기록을 비움)
signal world_changed(world: SimWorld)
## 실험 목록이 바뀌었을 때(새 실험·스냅숏·비교 시작/끝). 4단계 그래프·연대기·파라미터 패널이 처음부터 다시 읽음
signal experiments_changed(list: Array)
## index 번째 실험이 시계열 한 줄을 기록했을 때(Experiment.step 이 record.every 마다)
signal recorded(index: int, row: Dictionary)
## index 번째 실험의 drain_events() 결과(비어 있지 않을 때, 깊은 사본). events(list) 는 첫째 실험만(3단계 호환).
## 사본은 signal 마다 하나다 — 같은 signal 의 청취자끼리는 같은 배열을 받으므로 고쳐 쓰지 말 것(꾸미려면 먼저 복사)
signal events_tagged(index: int, list: Array)
## 그래프에 시점 표시를 요청(연대기 줄을 눌렀을 때 등). tick < 0 = 표시 지움
signal cursor_tick_requested(tick: int)

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
# 오래 보이는 알림(오류·경고: 경로 등을 읽을 시간)
const TOAST_LONG_KINDS: Array[String] = ["error", "warn"]
# _trim_toasts: 모든 칸의 알림을 셈
const ALL_PANES := -2
# 조작 도움말: 지도가 넓으면 한 줄, 좁으면(1280 창·비교 모드) 두 줄
const HINT_MOUSE := "끌기 이동 · 휠 확대 · 오른쪽 끌기 회전 · 클릭 고르기"
const HINT_KEYS := "스페이스 멈춤 · 1~7 속도 · F 따라가기 · Home 전체 보기 · Esc 선택 해제"
const HINT_SEP := "   │   "
const MAP_HINT := HINT_MOUSE + HINT_SEP + HINT_KEYS
## 더 좁을 때(1280 창 비교 모드의 A 칸) 키 줄을 둘로 나눈 세 줄 도움말(통합 때 더함)
const HINT_KEYS_A := "스페이스 멈춤 · 1~7 속도 · F 따라가기"
const HINT_KEYS_B := "Home 전체 보기 · Esc 선택 해제"
const FIT_TEXT := "전체 보기"
## 자리 접기 단추(지도 오른쪽 아래). 눌림 = 자리가 보임
const DOCK_LEFT := "left"
const DOCK_BOTTOM := "bottom"
const LEFT_TOGGLE_TEXT := "실험 조건"
const BOTTOM_TOGGLE_TEXT := "그래프·연대기"
## 비교 모드 실험 색(이름표 바탕): 그래프 계열 색과 같게(A 실선·B 점선과 한눈에 맞도록)
const TAG_COLOR_KEYS: Array[String] = ["graph.series_a", "graph.series_b"]
## 화면 방향 화살표(카메라가 북쪽 위에서 90° 씩 돈 수만큼 밀어 씀 — 0 북 1 동 2 남 3 서 순서). 지도 나침반·정보 창 방향
const ARROWS: Array[String] = ["↑", "→", "↓", "←"]
## 글 칸 밖을 누르면 초점을 푸는 마우스 단추(휠은 아님 — 칸에 적는 중에 패널을 굴려도 초점 그대로)
const RELEASE_BUTTONS: Array[MouseButton] = [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]


## 지도 한 칸(혼자면 하나, 비교 모드면 A·B 둘): SubViewportContainer ⊃ SubViewport ⊃ MapView + 왼쪽 위 표지.
class MapPane:
	var container: SubViewportContainer
	var viewport: SubViewport
	var map: MapView
	## 왼쪽 위 표지(OverlayPanel): 이름표(비교 모드) · 실험 이름 · 멈춤 · 멸종 · 전체 보기
	var head: PanelContainer
	var tag: PanelContainer
	var title: Label
	var paused: Label
	var extinct: Label
	## 나침반 "북 →"(카메라가 북쪽 위가 아닐 때만 — 비교 모드의 세로 칸에서 지도를 돌렸을 때 등)
	var north: Label
	var fit: Button
	## 이 지도의 실험 알림(비교 모드, 칸 가운데 위 — 혼자 모드·이름표 없는 알림은 공용 Toasts)
	var toasts: VBoxContainer
	## 표지 폭을 마지막으로 맞춘 조건(바뀔 때만 다시 잼)
	var fit_key := ""
	var width := 0.0


var world: SimWorld
## 진행 중인 실험들(혼자면 1개, 비교 모드면 2개: [A, B]). world = experiments[0].world, map_view = A 의 지도
var experiments: Array[Experiment] = []
var map_view: MapView
var info_panel: InfoPanel
var left_dock: VBoxContainer
var bottom_dock: HBoxContainer
## 4단계 패널(_ready 에서 자리에 넣고 bind_lab(self))
var param_panel: ParamPanel
var graph_panel: GraphPanel
var chronicle_panel: ChroniclePanel
var lab_sound: LabSound
## 마지막 advance_frame 의 시뮬레이션 시간(ms)과 예산을 다 써서 밀린 틱을 버렸는지(성능 기록·검사용)
var last_sim_ms := 0.0
var last_budget_hit := false

var _speed := 1
var _paused := false
var _fast := false
var _acc := 0.0
var _selected := -1
# 선택한 개체가 속한 실험(비교 모드 0 = A, 1 = B). 선택을 지워도 마지막 값을 둔다(F 따라가기가 쓸 지도)
var _selected_index := 0
var _frame := 0
var _title := ""
# 실제 배속 측정: 최근 프레임의 (시간, 진행한 틱 몫). 틱 몫은 정수 틱이 아니라 누적의 소수 부분까지 센 진행량
# (따라가면 정확히 목표 배속, 예산에 걸려 버린 몫은 빠짐). 속도·멈춤·빨리 감기를 바꾸면 창을 비운다.
var _hist_dt: Array[float] = []
var _hist_n: Array[float] = []
var _hist_time := 0.0
var _hist_ticks := 0.0
var _speed_label_wait := 0.0
# 세계를 바꾼 직후 첫 프레임(불러오기 시간이 든 긴 프레임)은 실제 배속 창에 넣지 않는다
var _skip_record := false
# 한 틱 비용 추정(µs, 지수 이동 평균): 예산을 넘기 **전에** 멈추려고 다음 틱 비용을 미리 더해 본다.
# 한 틱 = 모든 실험을 한 틱씩(비교 모드면 A·B 둘 몫을 합친 시간)
var _step_us_est := 0.0
var _est_alpha := 0.2
var _behind_fill := 0.5
# 실험마다 멸종을 이미 보았는지(멸종하는 순간 한 번만 알리려고), 모두 멸종해 저절로 멈췄는지(새 세계에서는 다시 재생)
var _extinct_seen: Array[bool] = []
var _extinct_paused := false
# 알림: {panel, left(남은 초), kind, group(비교 모드 이름표), text, body, count_label, when, count,
# pane(알림을 띄운 지도 칸 번호, -1 = 공용 Toasts), box(알림이 든 VBox)}
var _toasts: Array[Dictionary] = []
# 알림 묶음이 시작하는 높이(지도 표지 줄 아래, _layout_maps 가 정함)
var _toast_top := 0.0
var _coalesce: Array[String] = []
# 자리 접기(lab.left_dock_open·bottom_dock_open 이 처음 값)
var _left_open := true
var _bottom_open := true

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
var _day_chip: Control
var _lbl_season: Label
var _lbl_daynight: Label
var _lbl_gen: Label
var _lbl_pop: Label
var _lbl_stage: Label
var _lbl_speed: Label
# 혼자 모드 상태(평균 세대·개체·문명) / 비교 모드 상태(A 개체 · 문명 │ B 개체 · 문명)
var _single_box: HBoxContainer
var _cmp_box: HBoxContainer
var _cmp_pop: Array[Label] = []
var _cmp_stage: Array[Label] = []
var _left_wrap: PanelContainer
var _bottom_wrap: PanelContainer
var _map_area: Control
var _panes: Array[MapPane] = []
# A 지도(_panes[0])의 노드 별명(3단계 검사·캡처가 씀)
var _map_container: SubViewportContainer
var _map_viewport: SubViewport
var _map_title: Label
var _paused_badge: Label
var _extinct_badge: Label
var _fit_btn: Button
var _hint: PanelContainer
var _hint_label: Label
var _dock_toggles: HBoxContainer
var _left_toggle: Button
var _bottom_toggle: Button
var _toast_box: VBoxContainer


func _ready() -> void:
	_tps = UiConfig.num("speed.ticks_per_second_1x")
	_budget_ms = UiConfig.num("speed.sim_budget_ms")
	_ff_budget_ms = UiConfig.num("speed.fast_forward_budget_ms")
	_window_s = UiConfig.num("speed.actual_speed_window_s")
	_max_delta = UiConfig.num("speed.max_frame_delta_s")
	_est_alpha = clampf(UiConfig.num("speed.step_estimate_alpha"), 0.0, 1.0)
	_behind_fill = clampf(UiConfig.num("speed.behind_min_fill"), 0.0, 1.0)
	for v in UiConfig.value("speed.steps", [1]):
		_steps.append(int(v))
	for v in UiConfig.value("lab.toast_coalesce_kinds", []):
		_coalesce.append(str(v))
	_speed = UiConfig.integer("speed.start_mult")
	_left_open = bool(UiConfig.value("lab.left_dock_open", true))
	_bottom_open = bool(UiConfig.value("lab.bottom_dock_open", true))
	theme = UiTheme.build()
	_build_layout()
	# 패널은 첫 실험을 열기 전에 붙인다(첫 experiments_changed 를 받게)
	_place_panels()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_min_size(Vector2i(UiConfig.integer("lab.min_width"), UiConfig.integer("lab.min_height")))
	var errs := apply_args(OS.get_cmdline_user_args())
	if errs != "":
		# 알림을 놓쳐도 터미널에서 전체 문장(경로 포함)을 읽을 수 있게
		printerr(errs)
	_sync_controls()


func _process(delta: float) -> void:
	advance_frame(delta)


# ════════════════════════════ 실험 ════════════════════════════

## 새 세계를 만들어 붙인다(비교 모드면 끝내고 하나만). 성공 "", 실패면 오류 문장(지금 세계는 그대로).
func new_experiment(preset: String, overrides: Dictionary, seed_value: int) -> String:
	var r := Experiment.create(preset, overrides, seed_value)
	if r.experiment == null:
		var err: String = r.error
		return err
	_adopt_list([r.experiment])
	return ""


## 스냅숏 파일을 열어 붙인다(비교 모드면 끝내고 하나만). 성공 "", 실패면 오류 문장(지금 세계는 그대로). 백업에서 살렸으면 알림.
func open_snapshot(path: String) -> String:
	var r := Experiment.from_snapshot(path)
	if r.experiment == null:
		var err: String = r.error
		return err
	_adopt_list([r.experiment])
	# 세계를 바꾸면 앞 세계의 알림을 지우므로 백업 경고는 바꾼 뒤에 띄운다
	if str(r.status) == "backup":
		show_toast("원본이 깨져 백업에서 열었습니다: %s" % str(r.error), "warn")
	return ""


## 두 실험을 나란히(A | B) 시작한다. a·b = {preset, overrides, seed}(빠진 키는 기본 예설정·{}·기본 씨앗).
## 지도 둘을 나란히 보이고, 같은 배속으로 틱마다 A 다음 B 를 진행한다. 성공 "", 실패면 "A: 오류"/"B: 오류"(지금 실험 그대로).
func start_compare(a: Dictionary, b: Dictionary) -> String:
	var list: Array[Experiment] = []
	var specs: Array[Dictionary] = [a, b]
	for k in specs.size():
		var r := _create_from(specs[k])
		if r.experiment == null:
			return "%s: %s" % [Experiment.TAGS[k], str(r.error)]
		list.append(r.experiment)
	_adopt_list(list)
	return ""


## 비교를 끝내고 A 만 남긴다(A 의 세계·기록·카메라·선택은 그대로, B 지도는 지움). 비교 중이 아니면 아무것도 안 함.
func stop_compare() -> void:
	if not is_comparing():
		return
	var a := experiments[0]
	var keep := _selected if _selected_index == 0 else -1
	experiments.clear()
	a.tag = ""
	# 이름은 혼자 모드 순서로(비교 때는 B 와 다른 값을 먼저 적었음)
	if a.snapshot_path == "":
		a.label = Experiment.default_label(a.preset, a.overrides, a.seed_value)
	experiments.append(a)
	_extinct_seen.resize(1)
	# 이름표가 붙은 알림(A · / B ·, 비교 모드 F 키 알림)만 지운다 — 이름표 없는 알림(내보내기 실패 경로 등)은 남김.
	# B 지도 칸(과 그 알림 묶음)을 지우기 전에.
	_clear_toasts(true)
	_set_pane_count(1)
	_title = a.label
	# 한 틱 비용이 B 몫만큼 줄었으니 다시 잰다
	_step_us_est = 0.0
	_reset_speed_window()
	_skip_record = true
	_update_titles()
	select_slime(keep, 0)
	info_panel.set_empty_text(_empty_text())
	_set_window_title()
	_refresh_status(true)
	experiments_changed.emit(experiments)
	show_toast("비교를 끝냈습니다 — %s 만 계속합니다" % a.label, "info")


func is_comparing() -> bool:
	return experiments.size() > 1


func experiment(index: int = 0) -> Experiment:
	return experiments[index] if index >= 0 and index < experiments.size() else null


## index 번째 실험의 지도(비교 모드 0 = A, 1 = B). 없으면 null.
func map_view_of(index: int) -> MapView:
	return _panes[index].map if index >= 0 and index < _panes.size() else null


## 비교 모드 실험 색(이름표 바탕) = 그래프 계열 색(ui.graph.series_a / series_b).
static func tag_color(index: int) -> Color:
	return UiConfig.color(TAG_COLOR_KEYS[clampi(index, 0, TAG_COLOR_KEYS.size() - 1)])


## 스냅숏 저장(index 번째 실험). 성공 "", 실패면 오류 문장. 성공하면 알림.
func save_snapshot(path: String, index: int = 0) -> String:
	var x := experiment(index)
	if x == null:
		return "저장할 실험이 없습니다"
	var e := x.save_snapshot(path)
	if e == "":
		show_toast("스냅숏을 저장했습니다: %s" % ProjectSettings.globalize_path(path), "info")
	return e


## 결과 폴더 내보내기(CSV·요약·연대기·계통·스냅숏). 비교 모드면 dir/A, dir/B. 성공 "", 실패면 오류 문장. 결과는 알림으로.
## 비교 모드의 실패는 "B/timeseries.csv" 처럼 어느 실험의 파일인지 적고, 다 쓴 쪽은 "A 는 저장됨: 경로" 로 알린다.
func export_csv(dir: String) -> String:
	if experiments.is_empty():
		return "내보낼 실험이 없습니다"
	var failed := PackedStringArray()
	var saved: Array[String] = []
	for x in experiments:
		var d := dir if experiments.size() == 1 else dir.path_join(x.tag)
		var bad := x.export_dir(d)
		if experiments.size() == 1:
			failed.append_array(bad)
			continue
		for f in bad:
			failed.append("%s/%s" % [x.tag, f])
		if bad.is_empty():
			saved.append("%s 는 저장됨: %s" % [x.tag, ProjectSettings.globalize_path(d)])
	if not failed.is_empty():
		var msg := "내보내기 실패: %s" % ", ".join(failed)
		if not saved.is_empty():
			msg += " (%s)" % ", ".join(saved)
		show_toast(msg, "error")
		return msg
	show_toast("결과를 내보냈습니다: %s" % ProjectSettings.globalize_path(dir), "info")
	return ""


# ════════════════════════════ 웹(브라우저) 내려받기 ════════════════════════════
# 웹 체험판에는 사용자가 고를 파일 시스템이 없다(user:// = 브라우저 IndexedDB). 그래서 결과 폴더를 zip 으로 묶어
# 브라우저 내려받기로 넘긴다. zip 을 만드는 부분은 데스크톱에서도 같아 검사한다(내려받기 호출만 웹에서).

## 웹 체험판인지(파라미터 패널이 내보내기·스냅숏 단추를 내려받기로 바꿈)
static func is_web() -> bool:
	return OS.has_feature("web")


## 결과 폴더(export_csv 와 같은 파일, 비교면 A/·B/ 아래)를 zip 바이트로. 실패하면 빈 배열.
## 임시 폴더 user://web_export/<프로세스>-<µs> 와 zip 은 끝나면(실패해도) 지운다(숨은 .gdignore 까지 — 남던 것을 고침, 검사).
func results_zip_bytes() -> PackedByteArray:
	if experiments.is_empty():
		return PackedByteArray()
	var dir := "%s/%d-%d" % [WEB_EXPORT_DIR, OS.get_process_id(), Time.get_ticks_usec()]
	last_zip_tmp_dir = dir
	var abs_dir := ProjectSettings.globalize_path(dir)
	var abs_zip := abs_dir + ".zip"
	var bytes := PackedByteArray()
	var ok := true
	for x in experiments:
		var d := dir if experiments.size() == 1 else dir.path_join(x.tag)
		ok = ok and x.export_dir(d).is_empty()
	if ok:
		bytes = _zip_dir(abs_dir, abs_zip)
	_remove_tree(abs_dir)
	DirAccess.remove_absolute(abs_zip)
	# 다른 것이 없으면 web_export 폴더도(다른 실험실이 쓰는 중이면 비어 있지 않아 그대로)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WEB_EXPORT_DIR))
	return bytes


## 결과를 zip 으로 내려받기(웹). 데스크톱에서는 zip 을 user://downloads/ 에 저장(검사·확인용). 성공 "".
func download_results() -> String:
	var bytes := results_zip_bytes()
	if bytes.is_empty():
		var msg := "결과를 묶을 수 없습니다"
		show_toast(msg, "error")
		return msg
	var fname := default_export_dir().get_file() + ".zip"
	return _deliver(bytes, fname, "application/zip", "결과(zip)")


## index 번째 실험의 스냅숏 JSON 내려받기(웹). 데스크톱에서는 user://downloads/ 에 저장. 성공 "".
## 파일 이름 snapshot-<날짜-시각>-seed<그 실험의 씨앗>-tick<T>[-A/-B].json.
func download_snapshot(index: int = 0) -> String:
	var x := experiment(index)
	if x == null:
		return "저장할 실험이 없습니다"
	var text := SimSnapshot.to_text(x.world)
	var fname := "snapshot-%s-seed%d-tick%d%s.json" % [_stamp(), x.seed_value, x.world.tick, "" if x.tag == "" else "-" + x.tag]
	return _deliver(text.to_utf8_buffer(), fname, "application/json", "스냅숏")


## 마지막으로 넘긴 내려받기 파일 이름(검사용)
var last_download_name := ""
## 마지막 results_zip_bytes 의 임시 폴더(검사용 — 끝나면 지워져 있어야 함)
var last_zip_tmp_dir := ""
const WEB_EXPORT_DIR := "user://web_export"


func _deliver(bytes: PackedByteArray, fname: String, mime: String, what: String) -> String:
	last_download_name = fname
	if is_web():
		JavaScriptBridge.download_buffer(bytes, fname, mime)
		show_toast("%s 내려받기: %s" % [what, fname], "info")
		return ""
	var path := "user://downloads/" + fname
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "파일을 쓸 수 없습니다: %s" % path
	f.store_buffer(bytes)
	f.close()
	show_toast("%s 저장: %s" % [what, ProjectSettings.globalize_path(path)], "info")
	return ""


## 폴더(하위 폴더 포함)를 zip 으로 묶어 그 바이트를 돌려준다(경로는 폴더 기준 상대).
static func _zip_dir(abs_dir: String, abs_zip: String) -> PackedByteArray:
	var z := ZIPPacker.new()
	if z.open(abs_zip) != OK:
		return PackedByteArray()
	_zip_add(z, abs_dir, "")
	z.close()
	return FileAccess.get_file_as_bytes(abs_zip)


static func _zip_add(z: ZIPPacker, abs_dir: String, rel: String) -> void:
	var here := abs_dir.path_join(rel) if rel != "" else abs_dir
	for f in DirAccess.get_files_at(here):
		if f.begins_with("."):
			continue
		z.start_file(rel.path_join(f) if rel != "" else f)
		z.write_file(FileAccess.get_file_as_bytes(here.path_join(f)))
		z.close_file()
	for d in DirAccess.get_directories_at(here):
		_zip_add(z, abs_dir, rel.path_join(d) if rel != "" else d)


## 폴더를 통째로 지운다(숨은 파일 — 결과 폴더의 .gdignore — 까지. get_files_at 은 숨은 파일을 빼서 폴더가 남았었음).
static func _remove_tree(abs_dir: String) -> void:
	var da := DirAccess.open(abs_dir)
	if da == null:
		return
	da.include_hidden = true
	for f in da.get_files():
		DirAccess.remove_absolute(abs_dir.path_join(f))
	for d in da.get_directories():
		_remove_tree(abs_dir.path_join(d))
	DirAccess.remove_absolute(abs_dir)


## 기본 내보내기 폴더 user://experiments/<날짜-시각>-seed<N>(비교 모드면 -seed<A>-vs-seed<B>).
## 시각은 화면 쪽 이름에만 씀 — 시뮬레이션과 무관.
func default_export_dir() -> String:
	var seeds: Array[String] = []
	for x in experiments:
		seeds.append("seed%d" % x.seed_value)
	if seeds.is_empty():
		seeds.append("seed0")
	return "user://experiments/%s-%s" % [_stamp(), "-vs-".join(seeds)]


## 화면 쪽 시각 "날짜-시각"(내보내기·내려받기 이름용)
static func _stamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d-%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]


## 프레임 없이 모든 실험을 n틱 진행(기록·recorded 신호 포함, 검사·캡처용). 사건은 다음 프레임에 알림.
func step_ticks(n: int) -> void:
	for i in n:
		_step_once()


## 그래프에 시점 표시를 요청한다(연대기 → 그래프).
func request_cursor(tick: int) -> void:
	cursor_tick_requested.emit(tick)


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


## {preset, overrides, seed} 로 실험 하나를 만든다(빠진 키는 기본값). 결과: Experiment.create 와 같은 {experiment, error}.
static func _create_from(spec: Dictionary) -> Dictionary:
	var preset := str(spec.get("preset", UiConfig.value("lab.default_preset", "default")))
	var ov: Variant = spec.get("overrides", {})
	if typeof(ov) != TYPE_DICTIONARY:
		return {experiment = null, error = "바꾼 값(overrides)은 사전이어야 합니다"}
	var sd: Variant = spec.get("seed", UiConfig.integer("lab.default_seed"))
	if typeof(sd) != TYPE_INT and typeof(sd) != TYPE_FLOAT:
		return {experiment = null, error = "씨앗은 정수여야 합니다: %s" % str(sd)}
	return Experiment.create(preset, ov as Dictionary, int(sd))


## 실험 목록을 바꿔 끼우고(이름표 A/B, 지도 수) 선택·누적·측정·알림을 처음으로 되돌린다.
func _adopt_list(list: Array) -> void:
	experiments.clear()
	for k in list.size():
		var x: Experiment = list[k]
		x.tag = Experiment.TAGS[k] if list.size() > 1 else ""
		experiments.append(x)
	# 비교 모드 이름: A·B 의 바꾼 값 가운데 서로 다른 키를 먼저 적는다(같은 예설정·씨앗에서 값만 다른 비교도 이름이 갈리게)
	if experiments.size() > 1:
		var diff := Experiment.differing_keys(experiments[0].overrides, experiments[1].overrides)
		for x in experiments:
			if x.snapshot_path == "":
				x.label = Experiment.default_label(x.preset, x.overrides, x.seed_value, diff)
	if experiments.size() == 1:
		_title = experiments[0].label
	else:
		_title = "비교 · A %s │ B %s" % [experiments[0].label, experiments[1].label]
	_set_pane_count(experiments.size())
	_adopt(experiments[0].world)
	experiments_changed.emit(experiments)


## 세계를 바꿔 끼우고 선택·누적·측정·알림을 처음으로 되돌린다(_adopt_list 가 부름). 지도마다 자기 실험의 세계를 붙인다.
func _adopt(w: SimWorld) -> void:
	# 앞 세계의 알림(멸종·발견 등)이 새 세계 위에 남지 않게
	_clear_toasts()
	world = w
	_acc = 0.0
	_frame = 0
	_reset_speed_window()
	_skip_record = true
	_step_us_est = 0.0
	# 이미 멸종한 스냅숏을 열면 멈추지 않고 표시만(멸종하는 순간에만 멈춤). 앞 세계의 멸종으로 저절로 멈췄으면 다시 재생.
	_extinct_seen.clear()
	for x in experiments:
		_extinct_seen.append(x.world.extinct_tick >= 0)
	if _extinct_paused:
		_extinct_paused = false
		set_paused(false)
	info_panel.set_empty_text(_empty_text())
	for k in _panes.size():
		_panes[k].map.follow_selected = false
		_panes[k].map.bind(experiments[k].world if k < experiments.size() else null)
	_selected_index = 0
	select_slime(-1)
	info_panel.set_follow(false)
	_update_titles()
	_set_window_title()
	_refresh_status(true)
	world_changed.emit(world)


func _set_window_title() -> void:
	if is_inside_tree():
		get_window().title = "%s — %s" % [str(ProjectSettings.get_setting("application/config/name", "")), _title]


# ════════════════════════════ 속도 ════════════════════════════

## 목표 배속(1배 = speed.ticks_per_second_1x 틱/초). 고르면 빨리 감기는 꺼진다.
## 배속이 바뀌면 실제 배속 창을 비운다(앞 배속의 프레임으로 "뒤처짐" 경고가 잘못 뜨지 않게).
func set_speed(mult: int) -> void:
	var m := maxi(1, mult)
	if m != _speed or _fast:
		_reset_speed_window()
	_speed = m
	_fast = false
	_sync_controls()


func set_paused(p: bool) -> void:
	if p != _paused:
		_reset_speed_window()
	_paused = p
	_extinct_paused = false
	_sync_controls()


## 빨리 감기: 프레임마다 speed.fast_forward_budget_ms 를 다 써서 진행한다.
func set_fast_forward(on: bool) -> void:
	if on != _fast:
		_reset_speed_window()
	_fast = on
	_sync_controls()


## 실제 배속 창 비우기: 다시 WARMUP_FRACTION 만큼 찰 때까지 "실제 —".
func _reset_speed_window() -> void:
	_hist_dt.clear()
	_hist_n.clear()
	_hist_time = 0.0
	_hist_ticks = 0.0
	_speed_label_wait = 0.0


func is_paused() -> bool:
	return _paused


func is_fast_forward() -> bool:
	return _fast


func target_speed() -> int:
	return _speed


## 최근 speed.actual_speed_window_s 동안 실제로 진행한 배속(잘리지 않은 프레임 시간 기준, 틱의 소수 몫까지 셈).
func actual_speed() -> float:
	if _hist_time <= 0.0 or _tps <= 0.0:
		return 0.0
	return _hist_ticks / _hist_time / _tps


# ════════════════════════════ 선택 ════════════════════════════

## 개체 선택(그 실험의 지도에만 고리 + 정보 창, 비교 모드면 정보 창 머리에 A/B). index = 실험 번호(0 = A, 1 = B).
## -1·없는 id·없는 실험이면 선택 해제(모든 지도의 고리를 지움). 죽은 개체 id 는 기록으로 표시.
## 다른 실험의 개체로 옮기면 앞 지도의 따라가기를 끄고, 정보 창 따라가기 단추를 새 지도 상태로 맞춘다.
func select_slime(id: int, index: int = 0) -> void:
	var x := experiment(index)
	if x == null or id < 0 or x.world.slime_info(id).is_empty():
		id = -1
	if id >= 0 and index != _selected_index:
		for p in _panes:
			p.map.follow_selected = false
		_selected_index = index
	_selected_index = clampi(_selected_index, 0, maxi(0, _panes.size() - 1))
	_selected = id
	for k in _panes.size():
		_panes[k].map.set_selected(id if k == _selected_index else -1)
	if id < 0:
		info_panel.clear()
	else:
		info_panel.set_tag(x.tag, tag_color(index))
		info_panel.show_slime(x.world, id)
	if not _panes.is_empty():
		info_panel.set_follow(_sel_map().follow_selected)


func selected_id() -> int:
	return _selected


## 선택한 개체가 속한 실험 번호(0 = A, 1 = B). 선택이 없으면 -1.
func selected_index() -> int:
	return _selected_index if _selected >= 0 else -1


## 선택(또는 마지막으로 선택했던) 실험의 지도: 따라가기·가계 이동·F 키가 쓴다.
func _sel_map() -> MapView:
	return _panes[clampi(_selected_index, 0, _panes.size() - 1)].map


func _on_slime_requested(id: int) -> void:
	# 정보 창 가계 단추: 같은 실험 안에서 옮겨 가고 그 지도에서 카메라를 맞춘다
	select_slime(id, _selected_index)
	if _selected >= 0:
		_sel_map().focus_on(id)


func _on_follow_toggled(on: bool) -> void:
	_sel_map().follow_selected = on


# ════════════════════════════ 진행 ════════════════════════════

## 한 프레임 진행: before_steps → 누적 시간만큼 step(틱마다 before_steps, 예산 안) → update_view(alpha) → 신호·알림·상태 표시.
## 지도가 둘(비교 모드)이면 before_steps·update_view 를 지도마다, 한 틱 = A 다음 B.
## _process 가 부르고, 검사·캡처는 직접 불러 프레임을 결정적으로 몬다. 이 프레임에 돈 틱 수를 돌려준다.
func advance_frame(delta: float) -> int:
	# 진행·알림은 잘린 프레임 시간(멈칫한 프레임이 한꺼번에 몰아 돌지 않게), 실제 배속 측정은 잘리지 않은 시간
	var raw := maxf(delta, 0.0)
	var step_dt := minf(raw, _max_delta)
	_age_toasts(step_dt)
	if world == null:
		return 0
	for p in _panes:
		p.map.before_steps()
	var n := 0
	var progress := 0.0
	last_budget_hit = false
	var t0 := Time.get_ticks_usec()
	if not _paused:
		if _fast:
			# 빨리 감기: 다음 틱까지 해도 예산 안이면 계속(적어도 1틱)
			var ff_us := _ff_budget_ms * USEC_PER_MS
			while true:
				_step_once()
				n += 1
				if float(Time.get_ticks_usec() - t0) + _step_us_est > ff_us:
					break
			# 빨리 감기 프레임은 "지금 틱의 끝"(alpha 1)을 그린다. 멈추거나 보통 속도로 돌아가도 그 자리에서 이어지게 1.
			_acc = 1.0
			last_budget_hit = true
			progress = float(n)
		else:
			var acc0 := _acc
			_acc += step_dt * _tps * float(_speed)
			var budget_us := _budget_ms * USEC_PER_MS
			while _acc >= 1.0:
				# 다음 틱까지 하면 예산을 넘을 것 같으면 멈춘다(적어도 1틱은 돎)
				if n > 0 and float(Time.get_ticks_usec() - t0) + _step_us_est > budget_us:
					# 따라가지 못한 몫은 버린다(밀린 틱이 쌓여 점점 더 느려지지 않게). 보간용 소수 부분만 남김
					_acc -= floorf(_acc)
					last_budget_hit = true
					break
				_step_once()
				_acc -= 1.0
				n += 1
			progress = float(n) + _acc - acc0
	last_sim_ms = float(Time.get_ticks_usec() - t0) / USEC_PER_MS
	var alpha := clampf(_acc, 0.0, 1.0)
	for p in _panes:
		p.map.update_view(alpha, step_dt)
	if _skip_record:
		_skip_record = false
	else:
		# 한 번의 아주 긴 멈칫(창 끌기 등)은 창 길이만큼만 센다
		_record_speed(minf(raw, _window_s), progress)
	if n > 0:
		ticked.emit(world)
	# 사건: 실험마다 비우고, signal 마다 깊은 사본 하나(청취자가 고쳐 써도 알림·연대기·다른 signal 의 청취자는 그대로.
	# 같은 signal 의 청취자끼리는 같은 배열을 받으므로 고쳐 쓰지 않는다 — ChroniclePanel·LabSound 는 읽기만)
	for k in experiments.size():
		var ev := experiments[k].world.drain_events()
		if ev.is_empty():
			continue
		if k == 0:
			events.emit(ev.duplicate(true))
		events_tagged.emit(k, ev.duplicate(true))
		for e in ev:
			_show_event(e, k)
	for k in experiments.size():
		if experiments[k].world.extinct_tick >= 0 and not _extinct_seen[k]:
			_on_extinct(k)
	_frame += 1
	var every := maxi(1, UiConfig.integer("info.refresh_frames"))
	if info_panel.current_id() >= 0 and _frame % every == 0:
		info_panel.refresh()
	_speed_label_wait -= raw
	_refresh_status(_speed_label_wait <= 0.0 or _hist_time < _window_s)
	return n


## 틱 하나: 지도마다 보간 기억(지금 틱 = 다음 그림의 한 틱 전) → 실험마다 step(A 다음 B, 기록하면 recorded)
## → 한 틱 비용 추정 갱신(모든 실험 몫을 합친 시간이라 비교 모드 예산이 둘 몫을 셈).
func _step_once() -> void:
	for p in _panes:
		p.map.before_steps()
	var s0 := Time.get_ticks_usec()
	for k in experiments.size():
		if experiments[k].step():
			recorded.emit(k, experiments[k].rows().back())
	var us := float(Time.get_ticks_usec() - s0)
	_step_us_est = us if _step_us_est <= 0.0 else lerpf(_step_us_est, us, _est_alpha)


## k 번째 실험이 멸종하는 순간 한 번: 정보 창 빈 안내를 멸종 문구로, 지도 표지는 _refresh_status 가 계속 보인다.
## 모든 실험이 멸종했으면(혼자 모드 = 그 실험) lab.pause_on_extinction 이면 멈춘다(헤드리스 실행기의 끝 조건과 같게).
## 비교 모드에서 한쪽만 멸종하면 멈추지 않는다 — 살아남은 쪽을 같은 틱으로 계속 견주게(멸종 알림·표지로 그 순간을 남김).
## 다시 재생하면 빈 지도가 계속 진행한다.
func _on_extinct(k: int) -> void:
	_extinct_seen[k] = true
	info_panel.set_empty_text(_empty_text())
	if _all_extinct() and bool(UiConfig.value("lab.pause_on_extinction", true)) and not _paused:
		set_paused(true)
		_extinct_paused = true


func _all_extinct() -> bool:
	for x in experiments:
		if x.world.extinct_tick < 0:
			return false
	return not experiments.is_empty()


## 정보 창 빈 안내: 멸종이 없으면 ""(기본 문구), 혼자면 "멸종했습니다 (틱 N) …", 비교 모드면 어느 쪽인지.
func _empty_text() -> String:
	var dead: Array[int] = []
	for k in experiments.size():
		if experiments[k].world.extinct_tick >= 0:
			dead.append(k)
	if dead.is_empty():
		return ""
	# 두 줄로(정보 창 폭 안에서 문장 가운데 낱말이 갈라지지 않게 — 줄은 정보 창이 여백 안에서 바꿈)
	if not is_comparing():
		return "멸종했습니다 (틱 %s)\n고를 개체가 없습니다" % _commas(experiments[0].world.extinct_tick)
	if dead.size() == experiments.size():
		return "A·B 모두 멸종했습니다\n고를 개체가 없습니다"
	var k := dead[0]
	return "%s 는 멸종했습니다 (틱 %s)\n%s 지도에서 고르세요" % [experiments[k].tag, _commas(experiments[k].world.extinct_tick),
			experiments[1 - k].tag]


## 실제 배속 창에 이 프레임(시간, 진행한 틱 몫)을 넣고 창보다 오래된 프레임을 뺀다.
func _record_speed(dt: float, progress: float) -> void:
	_hist_dt.append(dt)
	_hist_n.append(progress)
	_hist_time += dt
	_hist_ticks += progress
	while _hist_dt.size() > 1 and _hist_time - _hist_dt[0] >= _window_s:
		_hist_time -= _hist_dt.pop_front()
		_hist_ticks -= _hist_n.pop_front()


# ════════════════════════════ 입력 ════════════════════════════

## 단축키. 글 입력 칸(4단계 씨앗 칸 등)에 초점이 있거나 대화 상자가 떠 있으면 건드리지 않는다.
## 마우스 단추를 누르면 그 자리가 초점을 가진 글 칸 밖인지 먼저 본다(_release_text_focus).
func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.pressed and mb.button_index in RELEASE_BUTTONS:
			_release_text_focus(mb.position)
		return
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


## 글자를 적을 수 있는 칸에 초점이 있는가(읽기 전용 칸 — 고급 설정의 배열·글자 값 — 은 글자를 받지 않으므로 아님).
func _text_has_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	if f is LineEdit:
		return (f as LineEdit).editable
	if f is TextEdit:
		return (f as TextEdit).editable
	return false


## 글 칸(파라미터 패널의 숫자·씨앗 칸)에 초점이 있을 때 그 칸 밖(지도·단추·다른 패널)을 누르면 초점을 푼다.
## 단추·지도는 초점을 받지 않아(FOCUS_NONE — 스페이스가 단추를 누르지 않게) Godot 가 초점을 풀지 않으므로, 풀지 않으면
## 단축키가 계속 꺼진 채 스페이스·숫자가 칸에 들어가 다음 새 실험에 확정됐다(씨앗 42 → 423). 초점이 빠지면 ParamPanel 이
## 그 칸을 확정한다. SpinBox 안의 글 칸이면 SpinBox 전체(위·아래 화살표 포함)를 칸 안으로 본다. 대화 상자가 떠 있으면 그대로.
## pos = 뿌리 뷰포트 좌표(_input 의 사건 위치).
func _release_text_focus(pos: Vector2) -> void:
	var f := get_viewport().gui_get_focus_owner()
	if not (f is LineEdit or f is TextEdit) or _dialog_open():
		return
	var host: Control = f
	if f.get_parent() is SpinBox:
		host = f.get_parent() as Control
	var p := get_viewport().get_canvas_transform().affine_inverse() * pos
	if host.get_global_rect().has_point(p):
		return
	# SpinBox 는 초점이 빠질 때 글자를 지연 호출로 확정한다 — 같은 누름의 단추(새 실험)가 옛 값을 쓰지 않게 지금 확정
	if host is SpinBox:
		(host as SpinBox).apply()
	f.release_focus()


## 초점을 가진(또는 배타적인) 창 안 대화 상자·차림표가 떠 있는가(말풍선은 초점이 없어 해당 없음).
func _dialog_open() -> bool:
	for w in get_viewport().get_embedded_subwindows():
		if w.visible and (w.exclusive or w.has_focus()):
			return true
	return false


## 지도 전체 보기(Home·0 키 = 모든 지도, 지도 위 "전체 보기" 단추 = 그 지도): 카메라를 처음 맞춤으로, 따라가기 끔
## (정보 창 단추도 선택 지도의 상태로). index < 0 = 모든 지도.
func fit_map(index: int = -1) -> void:
	for k in _panes.size():
		if index < 0 or index == k:
			_panes[k].map.fit_map()
	if not _panes.is_empty():
		info_panel.set_follow(_sel_map().follow_selected)


func _handle_key(code: Key) -> bool:
	match code:
		KEY_SPACE:
			set_paused(not _paused)
			return true
		KEY_ESCAPE:
			select_slime(-1)
			return true
		KEY_F:
			# 따라가기는 선택한 개체의 지도(비교 모드면 그 실험의 지도)에서
			var mv := _sel_map()
			mv.follow_selected = not mv.follow_selected
			# 정보 창의 "따라가기" 단추도 같은 상태로(신호 없이)
			info_panel.set_follow(mv.follow_selected)
			if mv.follow_selected and _selected >= 0:
				mv.focus_on(_selected)
			# 비교 모드면 그 실험의 알림(이름표 group — 그 지도 칸에 뜨고 비교를 끝내면 함께 지워짐)
			var tag := experiments[_selected_index].tag if is_comparing() else ""
			var where := "%s 지도 " % tag if tag != "" else ""
			show_toast(where + ("따라가기 켬" if mv.follow_selected else "따라가기 끔"), "info", -1, tag)
			return true
		KEY_HOME, KEY_0, KEY_KP_0:
			fit_map()
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

## 위쪽 가운데 알림(ui.lab.toast_seconds 뒤 사라짐, 오류·경고는 toast_error_seconds). kind: 사건 종류(discovery·extinction 등)
## 또는 info·warn·error. 왼쪽 띠는 종류 색, 발견은 강조 색·멸종과 오류는 위험 색·경고는 경고 색 테두리
## (밭 잃음은 경고 색 띠만). tick >= 0 이면 끝에 흐리게 틱을 붙인다. 긴 문장은 지도 폭 안에서 줄을 바꾼다.
## lab.toast_coalesce_kinds 의 종류(밭 잃음 등)는 이미 보이는 같은 종류·같은 group(비교 모드 이름표) 알림을 새 문장으로
## 고쳐 쓰고 "×N" 을 붙인다. 최대 lab.toast_max 개: 넘치면 (방금 띄운 것을 빼고) 강조 알림이 아닌 것 가운데 오래된 것부터
## 지운다(모두 강조면 가장 오래된 것).
## 비교 모드에서 group("A"/"B") 이 있는 알림은 그 실험의 지도 칸 가운데 위에(칸 폭 안에서 줄바꿈 — 두 지도 사이를 걸쳐
## 다른 지도를 가리지 않게), 앞머리 "A · " 는 지도 표지와 같은 실험 색 이름표로 그린다(text·visible_toasts() 는 "A · …" 그대로).
## group 이 없는 알림(저장·내보내기·오류)은 공용 묶음(지도 자리 가운데, 비교 모드면 칸 알림 아래).
func show_toast(text: String, kind: String = "info", tick: int = -1, group: String = "") -> void:
	if kind in _coalesce:
		for idx in range(_toasts.size() - 1, -1, -1):
			var old: Dictionary = _toasts[idx]
			if old.kind != kind or str(old.group) != group:
				continue
			old.count = int(old.count) + 1
			old.text = text
			(old.body as Label).text = UiTheme.keep_words(_toast_body_text(text, group))
			var cl := old.count_label as Label
			cl.text = "×%d" % int(old.count)
			cl.visible = true
			var wl := old.when as Label
			wl.text = "틱 " + _commas(tick)
			wl.visible = tick >= 0
			old.left = _toast_life(kind)
			(old.panel as Control).modulate.a = 1.0
			_fit_toast(old)
			# 가장 새 알림 자리(맨 아래)로
			_toasts.remove_at(idx)
			_toasts.append(old)
			(old.box as Node).move_child(old.panel as Node, -1)
			return
	var col := _kind_color(kind)
	var pane := _toast_pane(group)
	var p := PanelContainer.new()
	p.theme_type_variation = UiTheme.TOAST
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _is_highlight(kind):
		var sb := (theme.get_stylebox("panel", UiTheme.TOAST) as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.border_color = Color(col, TOAST_HIGHLIGHT_ALPHA)
		p.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiConfig.integer("lab.toast_gap"))
	p.add_child(row)
	var stripe := ColorRect.new()
	stripe.color = col
	stripe.custom_minimum_size.x = UiConfig.num("lab.toast_stripe_width")
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stripe)
	# 비교 모드 실험 이름표(지도 표지와 같은 색 상자) — 본문에서는 "A · " 를 뺌
	var gi := Experiment.TAGS.find(group)
	if gi >= 0 and text.begins_with(group + " · "):
		var chip := _tag_chip(group, tag_color(gi))
		chip.name = "Tag"
		chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(chip)
	var tag := str(TOAST_TAGS.get(kind, ""))
	if kind == "discovery" and UiTheme.has_glyphs(GLYPH_DISCOVERY):
		# 좁은 비교 칸에서는 "★" 만(문장이 이미 "… 발견" — 머리 글자 몫만큼 본문이 덜 접힘)
		tag = GLYPH_DISCOVERY if pane >= 0 else GLYPH_DISCOVERY + " " + tag
	if tag != "":
		var t := Label.new()
		t.text = tag
		t.theme_type_variation = UiTheme.VALUE
		t.add_theme_color_override("font_color", col)
		t.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(t)
	var body := Label.new()
	# 낱말 단위 줄바꿈(한글 음절 사이에서 끊지 않게, 통합 때 고침). 빈칸 없는 긴 경로는 WORD_SMART 가 글자 단위로 끊음
	body.text = UiTheme.keep_words(_toast_body_text(text, group))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _is_highlight(kind):
		body.theme_type_variation = UiTheme.VALUE
	row.add_child(body)
	var count := Label.new()
	count.theme_type_variation = UiTheme.DIM
	count.visible = false
	count.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(count)
	var when := Label.new()
	when.text = "틱 " + _commas(tick)
	when.theme_type_variation = UiTheme.DIM
	when.visible = tick >= 0
	when.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(when)
	var box: VBoxContainer = _toast_box if pane < 0 else _panes[pane].toasts
	box.add_child(p)
	var entry := {panel = p, left = _toast_life(kind), kind = kind, group = group, text = text, body = body, count_label = count,
			when = when, count = 1, pane = pane, box = box}
	_toasts.append(entry)
	_fit_toast(entry)
	var cap := maxi(1, UiConfig.integer("lab.toast_max"))
	# 비교 모드 칸 알림은 칸마다 lab.toast_max ÷ 칸 수 개까지(좁은 칸에서 줄바꿈해 길어진 알림이 그 지도를 다 덮지 않게)
	if pane >= 0:
		_trim_toasts(maxi(1, cap / _panes.size()), pane)
	_trim_toasts(cap)


## 알림을 limit 개로 줄인다(pane >= 0 이면 그 칸의 알림만 셈, ALL_PANES = 모두). 방금 띄운 알림(맨 뒤)은 지우지 않는다 —
## 강조 알림으로 꽉 차 있어도 단축키 반응 같은 새 알림이 보이게. 강조 알림이 아닌 것 가운데 오래된 것부터, 모두 강조면
## 가장 오래된 것.
func _trim_toasts(limit: int, pane: int = ALL_PANES) -> void:
	while true:
		var idx: Array[int] = []
		for k in _toasts.size():
			if pane == ALL_PANES or int(_toasts[k].pane) == pane:
				idx.append(k)
		if idx.size() <= limit:
			return
		var drop := idx[0]
		for j in idx.size() - 1:
			if not _is_highlight(str(_toasts[idx[j]].kind)):
				drop = idx[j]
				break
		var gone: Dictionary = _toasts[drop]
		_toasts.remove_at(drop)
		(gone.panel as Node).queue_free()


## 알림이 보이는 시간(오류·경고는 lab.toast_error_seconds).
static func _toast_life(kind: String) -> float:
	return UiConfig.num("lab.toast_error_seconds" if kind in TOAST_LONG_KINDS else "lab.toast_seconds")


## 알림이 뜰 지도 칸: 비교 모드에서 group 이 실험 이름표("A"/"B")면 그 칸 번호, 아니면 -1(공용 묶음).
func _toast_pane(group: String) -> int:
	if _panes.size() < 2 or group == "":
		return -1
	var k := Experiment.TAGS.find(group)
	return k if k >= 0 and k < _panes.size() else -1


## 알림 본문 글자: 실험 이름표 상자를 그리는 알림("A · …")은 앞머리를 뺀다.
static func _toast_body_text(text: String, group: String) -> String:
	if group != "" and Experiment.TAGS.has(group) and text.begins_with(group + " · "):
		return text.substr(group.length() + 3)
	return text


## 알림 본문 폭: 한 줄 폭과 (lab.toast_max_width 와 지도 폭 − 양쪽 여백 중 작은 것 − 띠·머리·틱 몫) 중 작은 것.
## 비교 모드 칸 알림은 지도 폭 대신 그 칸 폭. 넘치면 줄을 바꾼다(AUTOWRAP_WORD_SMART — 빈칸 없는 긴 경로도 끊음).
## 지도 크기가 바뀌면 다시 맞춘다.
func _fit_toast(entry: Dictionary) -> void:
	var body := entry.body as Label
	var p := entry.panel as Control
	if not body.is_inside_tree():
		return
	var font := body.get_theme_font("font")
	var fs := body.get_theme_font_size("font_size")
	var natural := ceilf(font.get_string_size(body.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) + 1.0
	body.custom_minimum_size.x = 0.0
	var chrome := p.get_combined_minimum_size().x - body.get_combined_minimum_size().x
	var room := UiConfig.num("lab.toast_max_width")
	var width := _map_area.size.x if _map_area != null else 0.0
	var pane := int(entry.get("pane", -1))
	if pane >= 0 and pane < _panes.size():
		width = _panes[pane].width
	if width > 0.0:
		room = minf(room, width - 2.0 * UiConfig.num("lab.map_overlay_margin"))
	body.custom_minimum_size.x = maxf(1.0, minf(natural, room - chrome))


func _refit_toasts() -> void:
	for t in _toasts:
		_fit_toast(t)


## 알림을 지운다: 모두(세계가 바뀔 때) 또는 only_tagged 면 이름표(group)가 붙은 것만(비교를 끝낼 때 — 오류 등은 남김).
func _clear_toasts(only_tagged: bool = false) -> void:
	for i in range(_toasts.size() - 1, -1, -1):
		var t: Dictionary = _toasts[i]
		if only_tagged and str(t.group) == "":
			continue
		(t.panel as Node).queue_free()
		_toasts.remove_at(i)


## 공용 알림 묶음의 높이: 표지 줄 아래, 비교 모드에서 칸 알림이 있으면 그 아래(겹치지 않게). 칸 알림 묶음 크기가 바뀔 때마다.
func _place_shared_toasts() -> void:
	if _toast_box == null:
		return
	var top := _toast_top
	if _panes.size() > 1:
		var deepest := 0.0
		for p in _panes:
			if p.toasts != null and p.toasts.get_child_count() > 0:
				deepest = maxf(deepest, p.toasts.size.y)
		if deepest > 0.0:
			top += deepest + float(_toast_box.get_theme_constant("separation"))
	_toast_box.offset_top = top
	_toast_box.offset_bottom = top


## 지금 보이는 알림 [{kind, text, left, count, group}] (검사·캡처용). 비교 모드 사건 알림의 text 는 "A · …"/"B · …",
## group = 그 실험 이름표("" = 이름표 없음).
func visible_toasts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in _toasts:
		out.append({kind = t.kind, text = t.text, left = t.left, count = t.count, group = t.group})
	return out


## 사건 하나를 알림으로. 비교 모드면 앞에 "A · "/"B · "(밭 잃음 묶기도 실험마다 따로).
func _show_event(e: Dictionary, k: int = 0) -> void:
	var text := str(e.get("text", ""))
	var group := ""
	if is_comparing() and k >= 0 and k < experiments.size():
		group = experiments[k].tag
		text = "%s · %s" % [group, text]
	show_toast(text, str(e.get("kind", "info")), int(e.get("tick", -1)), group)


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

## 위쪽 막대·지도 표지 갱신. 틱·계절·낮밤은 실험마다 같으면 한 번, 다르면(비교 모드에서 시간 설정이 다른 예설정)
## "A값/B값", 날이 다르면(하루 길이가 다름) 날은 숨김. 혼자면 평균 세대·개체·문명, 비교 모드면 "[A] 개체 · 문명 │ [B] 개체 · 문명".
func _refresh_status(with_speed: bool) -> void:
	if world == null or _lbl_tick == null:
		return
	var ticks: Array[String] = []
	var days: Array[String] = []
	var seasons: Array[String] = []
	var lights: Array[String] = []
	for x in experiments:
		var w := x.world
		ticks.append(_commas(w.tick))
		days.append(_commas(w.tick / _day_ticks_of(w) + 1))
		seasons.append(SEASON_NAMES[w.season] if w.season >= 0 and w.season < SEASON_NAMES.size() else NO_SEASON)
		lights.append("낮" if w.light >= UiConfig.num("lab.day_light_threshold") else "밤")
	_lbl_tick.text = _joined(ticks)
	# 하루 길이가 다른 두 실험(고급 설정)은 같은 틱이라도 날이 달라 "날" 은 숨긴다(틱이 기준, 위쪽 막대가 최소 창 폭 안에)
	var same_day := _all_same(days)
	if _day_chip.visible != same_day:
		_day_chip.visible = same_day
	_lbl_day.text = days[0] if not days.is_empty() else ""
	_lbl_season.text = _joined(seasons)
	_lbl_daynight.text = _joined(lights)
	var sky := "text"
	if _lbl_daynight.text == "낮":
		sky = "day"
	elif _lbl_daynight.text == "밤":
		sky = "night"
	_tint(_lbl_daynight, UiTheme.color(sky))
	var cmp := is_comparing()
	if _single_box.visible == cmp:
		_single_box.visible = not cmp
		_cmp_box.visible = cmp
	if cmp:
		for k in mini(experiments.size(), _cmp_pop.size()):
			_pop_stage(experiments[k].world, _cmp_pop[k], _cmp_stage[k])
	else:
		var pop := world.population()
		# 개체가 없으면 평균 세대는 뜻이 없다(0.0 은 처음으로 되돌아간 것처럼 보임)
		_lbl_gen.text = "%.1f" % world.mean_generation() if pop > 0 else "—"
		_tint(_lbl_gen, UiTheme.color("text" if pop > 0 else "text_dim"))
		_pop_stage(world, _lbl_pop, _lbl_stage)
	if with_speed:
		_speed_label_wait = UiConfig.num("speed.label_refresh_s")
		_lbl_speed.text = speed_text()
		var behind := not _paused and not _fast and _hist_time >= _window_s * _behind_fill \
				and actual_speed() < float(_speed) * UiConfig.num("speed.behind_ratio")
		_tint(_lbl_speed, UiTheme.color("warn" if behind else "text"))
	for k in mini(_panes.size(), experiments.size()):
		var p := _panes[k]
		var w := experiments[k].world
		p.paused.visible = _paused
		p.extinct.visible = w.extinct_tick >= 0
		if p.extinct.visible:
			p.extinct.text = "멸종 · 틱 %s" % _commas(w.extinct_tick)
		# 나침반: 화면 위가 북쪽이 아니면(비교 모드에서 세로 칸에 맞춰 돌렸거나 사용자가 돌림) 북쪽 방향 화살표
		var turns := view_turns(k)
		p.north.visible = turns != 0
		var nt := "북 " + ARROWS[turns]
		if p.north.text != nt:
			p.north.text = nt
		_fit_title(p)
	# 정보 창의 방향 화살표도 선택한 지도의 화면 방향으로
	if not _panes.is_empty():
		info_panel.set_view_turns(view_turns(_selected_index))


## k 번째 지도의 화면이 북쪽 위에서 90° 씩 몇 번 돌아 있는지(0~3, 0 = 북쪽 위). 없는 지도면 0.
func view_turns(k: int) -> int:
	if k < 0 or k >= _panes.size():
		return 0
	var cam := _panes[k].map.get_camera() as MapView.OrbitCamera
	return cam.view_turns() if cam != null else 0


## 개체 수(0 이면 "멸종", 위험 색)와 문명 단계(0 단계는 흐리게).
func _pop_stage(w: SimWorld, pop_label: Label, stage_label: Label) -> void:
	var pop := w.population()
	pop_label.text = _commas(pop) if pop > 0 else "멸종"
	_tint(pop_label, UiTheme.color("text" if pop > 0 else "danger"))
	var st := clampi(w.stage, 0, SimWorld.STAGE_NAMES.size() - 1)
	stage_label.text = SimWorld.STAGE_NAMES[st]
	_tint(stage_label, UiTheme.color("accent" if st > 0 else "text_dim"))


## 모두 같으면 하나, 다르면 "A값/B값".
static func _joined(vals: Array[String]) -> String:
	if _all_same(vals):
		return vals[0] if not vals.is_empty() else ""
	return "/".join(vals)


static func _all_same(vals: Array[String]) -> bool:
	for v in vals:
		if v != vals[0]:
			return false
	return true


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


## 하루 틱 수(날 표시용). SIM-API 의 읽기 전용 cfg(time.day_ticks)를 읽기만 한다.
## 날·계절·빛은 모두 지금 틱(tick)을 뜻한다(SimWorld 가 step 끝에 다시 계산).
static func _day_ticks_of(w: SimWorld) -> int:
	var t: Variant = w.cfg.get("time")
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

## Column = TopBar / Body(HBox) = Main(VBox: Middle(HBox: LeftWrap | MapArea) / BottomWrap) | InfoPanel.
## 정보 창은 아래 자리 옆까지 세로 전체(두뇌 열지도가 스크롤 없이 들어가게 — V07), 아래 자리는 왼쪽 자리 + 지도 폭.
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

	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	col.add_child(body)
	var main := VBoxContainer.new()
	main.name = "Main"
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)
	body.add_child(main)
	var mid := HBoxContainer.new()
	mid.name = "Middle"
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	main.add_child(mid)
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
	_build_map_overlay()
	var a := _make_pane(0)
	_panes.append(a)
	map_view = a.map
	_map_container = a.container
	_map_viewport = a.viewport
	_map_title = a.title
	_paused_badge = a.paused
	_extinct_badge = a.extinct
	_fit_btn = a.fit
	_map_area.resized.connect(_layout_maps)

	_bottom_wrap = PanelContainer.new()
	_bottom_wrap.name = "BottomWrap"
	_bottom_wrap.theme_type_variation = UiTheme.DOCK
	_bottom_wrap.custom_minimum_size.y = UiConfig.num("lab.bottom_panel_height")
	_bottom_wrap.visible = false
	main.add_child(_bottom_wrap)
	bottom_dock = HBoxContainer.new()
	bottom_dock.name = "BottomDock"
	_bottom_wrap.add_child(bottom_dock)

	info_panel = InfoPanel.new()
	info_panel.name = "InfoPanel"
	info_panel.custom_minimum_size.x = UiConfig.num("lab.right_panel_width")
	body.add_child(info_panel)

	# 빈 자리는 숨기고, 무언가를 넣으면 보인다(접기 단추로 접은 자리는 숨긴 채)
	for dock: Control in [left_dock, bottom_dock]:
		dock.child_entered_tree.connect(func(_n: Node) -> void: _sync_docks.call_deferred())
		dock.child_exiting_tree.connect(func(_n: Node) -> void: _sync_docks.call_deferred())

	info_panel.slime_requested.connect(_on_slime_requested)
	info_panel.follow_toggled.connect(_on_follow_toggled)


## 4단계 패널을 자리에 넣고 bind_lab(self): ParamPanel → 왼쪽, GraphPanel(늘어남) + ChroniclePanel(폭 chronicle.width) → 아래,
## LabSound → 자식. 첫 실험을 열기 전에 부르므로 bind_lab 안에서 experiments 는 비어 있을 수 있다(첫 experiments_changed 가 옴).
func _place_panels() -> void:
	param_panel = ParamPanel.new()
	param_panel.name = "ParamPanel"
	param_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_dock.add_child(param_panel)
	graph_panel = GraphPanel.new()
	graph_panel.name = "GraphPanel"
	graph_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_dock.add_child(graph_panel)
	chronicle_panel = ChroniclePanel.new()
	chronicle_panel.name = "ChroniclePanel"
	chronicle_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_dock.add_child(chronicle_panel)
	_fit_bottom_dock()
	resized.connect(_fit_bottom_dock)
	lab_sound = LabSound.new()
	lab_sound.name = "LabSound"
	add_child(lab_sound)
	param_panel.bind_lab(self)
	graph_panel.bind_lab(self)
	chronicle_panel.bind_lab(self)
	lab_sound.bind_lab(self)


## 아래 자리 나누기(통합 때 더함): 연대기 폭 = 아래 자리 안쪽 폭 × chronicle.dock_frac 을
## [chronicle.min_width, chronicle.width] 로 자르고, 그래프 최소 폭이 들어가도록 더 줄인다(min_width 아래로는 안 줄임).
## 폭은 창 폭에서 정보 창을 뺀 값으로 센다(자리 크기로 세면 넘친 폭이 다시 들어와 돌고 돈다). 최소 창 1280 에서
## 연대기 420 + 그래프 최소 540 이 아래 자리(920)를 넘어 정보 창이 창 밖으로 밀리던 것을 고침(검사).
func _fit_bottom_dock() -> void:
	if chronicle_panel == null or not is_instance_valid(chronicle_panel) or info_panel == null:
		return
	var inner := size.x - info_panel.custom_minimum_size.x
	var sb := _bottom_wrap.get_theme_stylebox("panel")
	if sb != null:
		inner -= sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
	var w_min := UiConfig.num("chronicle.min_width")
	var w := clampf(roundf(inner * UiConfig.num("chronicle.dock_frac")), w_min, UiConfig.num("chronicle.width"))
	if graph_panel != null and is_instance_valid(graph_panel) and graph_panel.get_parent() == bottom_dock:
		var room := inner - float(bottom_dock.get_theme_constant("separation")) - graph_panel.get_combined_minimum_size().x
		w = maxf(w_min, minf(w, floorf(room)))
	if not is_equal_approx(chronicle_panel.custom_minimum_size.x, w):
		chronicle_panel.custom_minimum_size.x = w


## 자리 보이기: 자식이 있고 접지 않았으면 보임. 접기 단추는 자식이 있는 자리만.
func _sync_docks() -> void:
	if not is_instance_valid(left_dock):
		return
	var lc := _live_children(left_dock) > 0
	var bc := _live_children(bottom_dock) > 0
	_left_wrap.visible = lc and _left_open
	_bottom_wrap.visible = bc and _bottom_open
	_left_toggle.visible = lc
	_bottom_toggle.visible = bc
	_dock_toggles.visible = lc or bc
	_left_toggle.set_pressed_no_signal(_left_open)
	_bottom_toggle.set_pressed_no_signal(_bottom_open)
	_layout_maps()


## 왼쪽("left")·아래("bottom") 자리를 펴거나 접는다(지도 오른쪽 아래 단추와 같음). 지도는 남는 자리를 채운다.
func set_dock_open(which: String, open: bool) -> void:
	if which == DOCK_LEFT:
		_left_open = open
	elif which == DOCK_BOTTOM:
		_bottom_open = open
	_sync_docks()


func is_dock_open(which: String) -> bool:
	return _left_open if which == DOCK_LEFT else _bottom_open if which == DOCK_BOTTOM else false


static func _live_children(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if not ch.is_queued_for_deletion():
			c += 1
	return c


## 지도 수를 n 으로(비교 모드 B 지도는 필요할 때 만들고, 끝나면 트리에서 바로 빼서 지움 — 그 칸의 알림도). 배치를 다시 맞춘다.
## 비교 모드 지도는 세로로 긴 칸이면 돌려서 맞출 수 있게(ui.compare.portrait_yaw_deg — OrbitCamera.portrait_yaw), 혼자면 북쪽 위.
func _set_pane_count(n: int) -> void:
	while _panes.size() < n:
		_panes.append(_make_pane(_panes.size()))
	while _panes.size() > maxi(1, n):
		var p: MapPane = _panes.pop_back()
		for i in range(_toasts.size() - 1, -1, -1):
			if _toasts[i].box == p.toasts:
				_toasts.remove_at(i)
		for node: Node in [p.container, p.head, p.toasts]:
			_map_area.remove_child(node)
			node.queue_free()
	var turn := deg_to_rad(UiConfig.num("compare.portrait_yaw_deg")) if _panes.size() > 1 else 0.0
	for p in _panes:
		var cam := p.map.get_camera() as MapView.OrbitCamera
		if cam != null:
			cam.portrait_yaw = turn
			cam.portrait_gain = UiConfig.num("compare.portrait_gain_min")
	_layout_maps()


## k 번째 지도: MapContainer[B] ⊃ MapViewport ⊃ MapView(own_world_3d — 두 지도의 3D 세계가 섞이지 않게) + 표지 MapTitle[B].
## 지도 클릭은 select_slime(id, k).
func _make_pane(k: int) -> MapPane:
	var p := MapPane.new()
	var sfx := "" if k == 0 else Experiment.TAGS[k]
	p.container = SubViewportContainer.new()
	p.container.name = "MapContainer" + sfx
	p.container.stretch = true
	p.container.focus_mode = Control.FOCUS_NONE
	_map_area.add_child(p.container)
	# 지도는 맨 아래(표지·도움말·알림이 위)
	_map_area.move_child(p.container, k)
	p.viewport = SubViewport.new()
	p.viewport.name = "MapViewport"
	p.viewport.own_world_3d = true
	p.viewport.msaa_3d = clampi(UiConfig.integer("lab.map_msaa"), 0, 3) as Viewport.MSAA
	p.container.add_child(p.viewport)
	p.map = MapView.new()
	p.map.name = "MapView"
	p.viewport.add_child(p.map)
	p.map.slime_clicked.connect(select_slime.bind(k))
	_build_pane_head(p, k)
	# 이 칸의 실험 알림 묶음(비교 모드): 칸 가운데 위, 표지·지도 위에
	p.toasts = _make_toast_box("Toasts" + Experiment.TAGS[k])
	_map_area.add_child(p.toasts)
	p.toasts.resized.connect(_place_shared_toasts)
	return p


## 지도 왼쪽 위 표지: [이름표 A/B(비교 모드)] 실험 이름 [‖ 멈춤] [멸종 · 틱 N] [전체 보기]. 이름은 지도 폭에 맞춰 줄임(…).
func _build_pane_head(p: MapPane, k: int) -> void:
	var sfx := "" if k == 0 else Experiment.TAGS[k]
	var head := PanelContainer.new()
	head.name = "MapTitle" + sfx
	head.theme_type_variation = UiTheme.OVERLAY
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_area.add_child(head)
	_map_area.move_child(head, _hint.get_index())
	p.head = head
	var hrow := HBoxContainer.new()
	hrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hrow)
	p.tag = _tag_chip(Experiment.TAGS[k], tag_color(k))
	p.tag.name = "Tag"
	p.tag.visible = false
	hrow.add_child(p.tag)
	p.title = Label.new()
	p.title.name = "Title"
	p.title.theme_type_variation = UiTheme.DIM
	p.title.clip_text = true
	p.title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hrow.add_child(p.title)
	p.paused = Label.new()
	p.paused.theme_type_variation = UiTheme.VALUE
	p.paused.text = "%s 멈춤" % UiTheme.glyph_or(GLYPH_PAUSE, "")
	p.paused.add_theme_color_override("font_color", UiTheme.color("warn"))
	p.paused.visible = false
	hrow.add_child(p.paused)
	p.extinct = Label.new()
	p.extinct.name = "ExtinctBadge"
	p.extinct.theme_type_variation = UiTheme.VALUE
	p.extinct.add_theme_color_override("font_color", UiTheme.color("danger"))
	p.extinct.visible = false
	hrow.add_child(p.extinct)
	p.north = Label.new()
	p.north.name = "North"
	p.north.theme_type_variation = UiTheme.DIM
	p.north.visible = false
	hrow.add_child(p.north)
	p.fit = Button.new()
	p.fit.name = "FitButton"
	p.fit.text = FIT_TEXT
	p.fit.focus_mode = Control.FOCUS_NONE
	p.fit.mouse_filter = Control.MOUSE_FILTER_STOP
	p.fit.tooltip_text = "이 지도 전체가 보이게 카메라를 되돌림 (Home = 모든 지도)"
	p.fit.add_theme_font_size_override("font_size", UiConfig.integer("lab.font_size_small"))
	p.fit.pressed.connect(fit_map.bind(k))
	hrow.add_child(p.fit)


## 비교 모드 이름표: 실험 색 바탕의 작은 상자 + 어두운 굵은 글자(글자 자체에는 실험 색을 입히지 않음).
func _tag_chip(text: String, col: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", UiTheme.box(col, Color(0, 0, 0, 0), 0, UiConfig.integer("compare.tag_radius"),
			UiConfig.num("compare.tag_pad_h"), UiConfig.num("compare.tag_pad_v")))
	var l := Label.new()
	l.text = text
	l.theme_type_variation = UiTheme.VALUE
	l.add_theme_color_override("font_color", UiTheme.color("background"))
	l.add_theme_font_size_override("font_size", UiConfig.integer("lab.font_size_small"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(l)
	return chip


## 지도 이름(혼자 = 실험 이름, 비교 = 이름표 + 각 실험 이름)을 다시 쓰고 배치를 맞춘다.
func _update_titles() -> void:
	for k in mini(_panes.size(), experiments.size()):
		var p := _panes[k]
		p.tag.visible = is_comparing()
		p.title.text = experiments[k].label if is_comparing() else _title
		p.fit_key = ""
	_layout_maps()


## 지도 칸 배치: 혼자면 지도 자리 전체, 비교 모드면 A | B 를 반씩(사이 compare.gap_px, 픽셀 정수).
## 표지는 각 지도 왼쪽 위, 도움말은 왼쪽 아래, 자리 접기 단추는 오른쪽 아래, 알림은 표지 줄 아래 가운데.
func _layout_maps() -> void:
	if _map_area == null or _panes.is_empty():
		return
	var area := _map_area.size
	var n := _panes.size()
	var m := UiConfig.num("lab.map_overlay_margin")
	var gap := float(UiConfig.integer("compare.gap_px")) if n > 1 else 0.0
	var each := floorf(maxf(area.x - gap * float(n - 1), 0.0) / float(n))
	var x := 0.0
	var head_bottom := 0.0
	for k in n:
		var p := _panes[k]
		var w := each if k < n - 1 else maxf(area.x - x, 0.0)
		p.container.position = Vector2(x, 0.0)
		p.container.size = Vector2(w, area.y)
		p.width = w
		p.fit_key = ""
		_fit_title(p)
		p.head.position = Vector2(x + m, m)
		head_bottom = maxf(head_bottom, m + p.head.size.y)
		x += w + gap
	_fit_hint(area)
	# 알림은 지도 표지 줄 아래에서 시작(좁은 지도·비교 모드에서 표지를 가리지 않게). 비교 모드 칸 알림은 그 칸 가운데.
	_toast_top = head_bottom + UiConfig.num("lab.toast_margin_top")
	x = 0.0
	for k in n:
		var p := _panes[k]
		p.toasts.offset_left = roundf(x + p.width * 0.5)
		p.toasts.offset_right = p.toasts.offset_left
		p.toasts.offset_top = _toast_top
		p.toasts.offset_bottom = _toast_top
		x += p.width + gap
	_place_shared_toasts()
	_refit_toasts()


## 표지 폭 맞춤: 실험 이름 = min(한 줄 폭, 지도 폭 − 양쪽 여백 − 이름표·표지·단추 몫), 넘치면 "…". 조건이 바뀔 때만 잰다.
func _fit_title(p: MapPane) -> void:
	var key := "%s|%s|%s|%s|%s|%s|%s|%.0f" % [p.title.text, p.tag.visible, p.paused.visible, p.extinct.visible, p.extinct.text,
			p.north.visible, p.north.text, p.width]
	if key == p.fit_key or not p.title.is_inside_tree():
		return
	p.fit_key = key
	var font := p.title.get_theme_font("font")
	var fs := p.title.get_theme_font_size("font_size")
	var natural := ceilf(font.get_string_size(p.title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) + 1.0
	p.title.custom_minimum_size.x = 0.0
	var chrome := p.head.get_combined_minimum_size().x - p.title.get_combined_minimum_size().x
	var room := p.width - 2.0 * UiConfig.num("lab.map_overlay_margin")
	p.title.custom_minimum_size.x = maxf(0.0, minf(natural, room - chrome))
	p.head.reset_size()


## 조작 도움말(왼쪽 아래): 접기 단추 옆에 한 줄이 들어가면 한 줄, 아니면 마우스·키 두 줄, 그래도 넘치면 키 줄을 나눈
## 세 줄(그래도 넘치면 잘라 냄). 비교 모드에서는 A 지도 칸 안에 들어가는 가장 적은 줄로(두 지도 사이를 걸치지 않게 —
## 1280 창·자리 펼침에서는 세 줄), A 칸에 어느 것도 안 들어가면 지도 자리 전체 폭으로. 자리 접기 단추는 오른쪽 아래.
func _fit_hint(area: Vector2) -> void:
	var m := UiConfig.num("lab.map_overlay_margin")
	var room := area.x - 2.0 * m
	if _dock_toggles.visible:
		_dock_toggles.reset_size()
		_dock_toggles.position = Vector2(area.x - m - _dock_toggles.size.x, area.y - m - _dock_toggles.size.y)
		room -= _dock_toggles.size.x + m
	var font := _hint_label.get_theme_font("font")
	var fs := _hint_label.get_theme_font_size("font_size")
	var forms: Array[String] = [MAP_HINT, HINT_MOUSE + "\n" + HINT_KEYS, HINT_MOUSE + "\n" + HINT_KEYS_A + "\n" + HINT_KEYS_B]
	var widths: Array[float] = []
	for f in forms:
		var w := 0.0
		for line in f.split("\n"):
			w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		widths.append(w)
	var chrome := _hint.get_combined_minimum_size().x - _hint_label.get_combined_minimum_size().x
	var pick := -1
	if _panes.size() > 1:
		var room_a := minf(room, _panes[0].width - 2.0 * m)
		for i in forms.size():
			if widths[i] + chrome <= room_a:
				pick = i
				room = room_a
				break
	if pick < 0:
		pick = forms.size() - 1
		for i in forms.size():
			if widths[i] + chrome <= room:
				pick = i
				break
	var text := forms[pick]
	var natural := widths[pick]
	if _hint_label.text != text:
		_hint_label.text = text
	_hint_label.custom_minimum_size.x = maxf(0.0, minf(ceilf(natural) + 1.0, room - chrome))
	_hint.reset_size()
	_hint.position = Vector2(m, area.y - m - _hint.size.y)


## 위쪽 막대: [재생] [1배…64배] [빨리 감기] │ 틱·날·계절·낮밤 │ 평균 세대·개체·문명(비교 모드: [A] 개체 · 문명 │ [B] …)
## …… 목표/실제 배속. 묶음마다 작은 HBox 로 나눠 간격을 줄인다(최소 창 폭 lab.min_width 안에 가장 긴 표시가 들어가게, 검사).
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
	_day_chip = _lbl_day.get_parent() as Control
	var sky := _hbox(UiConfig.integer("lab.chip_inner_gap"))
	status.add_child(sky)
	_lbl_season = _value_label(sky)
	_dot(sky)
	_lbl_daynight = _value_label(sky)
	for l: Label in [_lbl_season, _lbl_daynight]:
		l.tooltip_text = "비교 모드에서 두 실험의 계절·낮밤이 다르면 \"A/B\""
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	status.add_child(_vsep())
	_single_box = _hbox(UiConfig.integer("lab.chip_gap"))
	status.add_child(_single_box)
	_lbl_gen = _chip(_single_box, "평균 세대")
	_lbl_pop = _chip(_single_box, "개체")
	_lbl_stage = _chip(_single_box, "문명")
	_cmp_box = _hbox(UiConfig.integer("lab.chip_gap"))
	_cmp_box.visible = false
	status.add_child(_cmp_box)
	for k in Experiment.TAGS.size():
		if k > 0:
			_cmp_box.add_child(_vsep())
		var g := _hbox(UiConfig.integer("lab.chip_inner_gap"))
		g.mouse_filter = Control.MOUSE_FILTER_PASS
		g.tooltip_text = "%s 실험: 개체 수 · 문명 단계" % Experiment.TAGS[k]
		_cmp_box.add_child(g)
		g.add_child(_tag_chip(Experiment.TAGS[k], tag_color(k)))
		_cmp_pop.append(_value_label(g))
		_dot(g)
		_cmp_stage.append(_value_label(g))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_lbl_speed = _value_label(row)
	_lbl_speed.tooltip_text = "목표 배속과 최근 %.0f초 동안 실제로 낸 배속" % _window_s
	_lbl_speed.mouse_filter = Control.MOUSE_FILTER_PASS
	return bar


## 지도 위 공용 표지: 왼쪽 아래 조작 도움말, 오른쪽 아래 자리 접기 단추, 위쪽 가운데 알림 묶음(지도마다의 표지는 _build_pane_head).
func _build_map_overlay() -> void:
	_hint = PanelContainer.new()
	_hint.name = "MapHint"
	_hint.theme_type_variation = UiTheme.OVERLAY
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_area.add_child(_hint)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = UiTheme.DIM
	_hint_label.clip_text = true
	_hint_label.text = MAP_HINT
	_hint.add_child(_hint_label)

	_dock_toggles = _hbox(UiConfig.integer("lab.speed_button_gap"))
	_dock_toggles.name = "DockToggles"
	_dock_toggles.visible = false
	_map_area.add_child(_dock_toggles)
	_left_toggle = _dock_toggle("LeftToggle", LEFT_TOGGLE_TEXT, "왼쪽 실험 조건 패널 보이기·숨기기", DOCK_LEFT)
	_bottom_toggle = _dock_toggle("BottomToggle", BOTTOM_TOGGLE_TEXT, "아래 그래프·연대기 보이기·숨기기", DOCK_BOTTOM)

	# 공용 알림 묶음(지도 자리 가운데 위). 비교 모드의 실험 알림은 칸마다의 묶음(_make_pane)
	_toast_box = _make_toast_box("Toasts")
	_toast_box.anchor_left = 0.5
	_toast_box.anchor_right = 0.5
	_toast_box.offset_top = UiConfig.num("lab.toast_margin_top")
	_toast_box.offset_bottom = _toast_box.offset_top
	_map_area.add_child(_toast_box)


## 알림 묶음(VBox): 마우스 통과, 가운데에서 양쪽으로 자람(위치는 _layout_maps 가 정함).
func _make_toast_box(node_name: String) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.name = node_name
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.grow_horizontal = Control.GROW_DIRECTION_BOTH
	b.alignment = BoxContainer.ALIGNMENT_BEGIN
	return b


## 자리 접기 단추(눌림 = 보임). 작은 글자, 초점 없음.
func _dock_toggle(node_name: String, text: String, tip: String, which: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", UiConfig.integer("lab.font_size_small"))
	b.toggled.connect(func(on: bool) -> void: set_dock_open(which, on))
	_dock_toggles.add_child(b)
	return b


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
