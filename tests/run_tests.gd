extends SceneTree
## 헤드리스 자동 검사:  godot --headless --path . --script res://tests/run_tests.gd
## 이전 프로젝트(little-monster-village)의 방식: check(조건, 설명)을 쌓고 마지막 줄에 RESULT 를 출력한다.
## 테스트 함수가 끝까지 실행되지 않으면(스크립트 오류) 실패로 센다: 검사 함수는 끝에서 done() 을 부르고, 오류로 중간에 끊기면
## 그 줄에 닿지 않는다(Godot 은 오류 난 함수만 멈추고 계속 돌므로 — 예전엔 검사를 하나도 하지 않은 함수만 잡았음, I33).
## 선택 인자: --only=test_이름(쉼표로 여러 개, 모르는 이름이 있으면 아무것도 돌리지 않고 실패 — J15)  --skip-slow

const SIM_DIR := "res://scripts/sim"
## 매직 넘버 검사에서 빼는 파일: 설정 로더(범위 검사의 상한·하한은 시뮬레이션 수치가 아님)
const MAGIC_EXEMPT: Array[String] = ["sim_config.gd"]
## 코드에 그대로 써도 되는 수(DESIGN 7.1 의 목록 — 음수 −1 은 1 로 셈). 이 표기 그대로만 받는다: 1_000·.25·0b1011·1e6·2.0 처럼
## 다른 꼴로 적은 수는 모두 매직 넘버(예전 정규식은 밑줄·앞 0 없는 소수·2진수를 보지 못했음, I36).
const MAGIC_ALLOWED: Array[String] = ["0", "1", "2", "0.0", "1.0", "0.5"]
## 수 글자(16진·2진·밑줄·앞 0 없는 소수·지수 표기까지). 앞뒤가 이름·점이면 수가 아님(t2·x.size).
const NUM_PATTERN := "(?<![A-Za-z_0-9.])(0[xX][0-9a-fA-F_]+|0[bB][01_]+|[0-9][0-9_]*(\\.[0-9_]*)?([eE][+-]?[0-9][0-9_]*)?|\\.[0-9][0-9_]*([eE][+-]?[0-9][0-9_]*)?)(?![A-Za-z_0-9.])"
## 시뮬레이션 코드가 받는 이 없이 부르는 전역 함수·생성자의 허용 목록(I36 — 예전엔 sin·pow 같은 금지 목록이라 asin·ease·
## db_to_linear·전역 randf()/randi()·seed() 를 놓쳤음). 시뮬레이션 파일에 정의한 함수는 저절로 허용. 이름을 더할 때는 플랫폼마다
## 같은 비트인지(사칙연산·sqrt·비교·정수 연산뿐인지) 확인할 것 — README·DESIGN D10 "사칙연산·sqrt 만".
const ALLOWED_GLOBAL_CALLS: Array[String] = [
	"int", "float", "str", "bool", "typeof", "type_string", "range", "String", "PackedByteArray", "PackedInt32Array",
	"PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array", "PackedStringArray", "absf", "absi", "minf", "maxf", "mini", "maxi",
	"clampf", "clampi", "floorf", "sqrt", "snappedf", "is_finite", "is_inf", "is_nan", "push_error", "error_string",
]
## 받는 이가 있는 메서드 호출(.이름()의 허용 목록 — 배열·사전·글자·파일·JSON·정규식 다루기와 SimRng 안의 RandomNumberGenerator.randi 뿐.
## Vector2.rotated·angle·from_angle·slerp·lerp 같은 수학 메서드는 없음). 시뮬레이션 파일에 정의한 함수는 저절로 허용.
const ALLOWED_METHODS: Array[String] = [
	"append", "append_array", "base64_to_raw", "begins_with", "close", "contains", "copy_absolute", "create_from_string",
	"duplicate", "erase", "file_exists", "fill", "get", "get_error", "get_file", "get_file_as_string", "get_length",
	"get_open_error", "get_setting", "get_string", "has", "hex_decode", "hex_encode", "is_empty", "is_valid_int", "join",
	"keys", "length", "make_dir_recursive_absolute", "merge", "new", "num", "open", "parse", "parse_string", "path_join",
	"randi", "raw_to_base64", "remove_absolute", "rename_absolute", "replace", "resize", "search_all", "sha256_text", "size",
	"slice", "split", "store_buffer", "store_string", "stringify", "to_byte_array", "to_float32_array", "to_float64_array",
	"to_int", "to_int32_array", "to_int64_array", "to_utf8_buffer",
]
## 뒤에 괄호가 와도 함수 호출이 아닌 GDScript 낱말(func 는 이름 없는 함수).
const GD_KEYWORDS: Array[String] = ["if", "elif", "while", "for", "match", "return", "and", "or", "not", "in", "is", "as", "func"]
## 난수 생성기를 직접 만들 수 있는 유일한 파일(나머지는 씨앗을 받은 SimRng 만 — DESIGN 7절).
const RNG_FILE := "sim_rng.gd"
## 농사 도달 검사(S15): 이 예설정·씨앗 조합 중 하나라도 평균 100세대 안에 농사(3단계)에 도달해야 한다.
## 연구용 fast_civ 를 먼저 본다(씨앗 1: 2,040틱·평균 28.5세대에 농사 — docs/TUNING-fast_civ.md, 검토 고침 g1b 의 규칙 고침 뒤 다시 잼).
## 규칙 고침 전에는 3,321틱·49.0세대 — 식물 갱신 간격 사이의 빛을 더하도록 바꾼 J02 가 기본 역사를 바꿈(나머지는 채집 발견 뒤 — 바닥 먹이·저장고·밭이 생긴 뒤의 역사만).
## 검사 전체는 4코어 컨테이너에서 약 20초(씨앗 1 농사까지 + 씨앗 2·3 채집까지).
const FARM_PRESETS: Array[String] = ["fast_civ", "demo_fast", "default"]
const FARM_SEEDS: Array[int] = [1, 2, 3]
const FARM_GENERATIONS := 100.0
## fast_civ 다시 맞춤의 목표는 S15 와 따로 검사한다(S15 는 demo_fast 로도 통과하므로): FARM_SEEDS 의 첫 씨앗이
## fast_civ 그대로 평균 FARM_GENERATIONS 세대 안에 농사. 결정적이므로 문서에 적은 시각도 고정한다 —
## 시뮬레이션·설정을 일부러 바꿨다면 다시 재서 이 두 값과 TUNING-fast_civ.md·TEST-REPORT(W11·6절)를 함께 고칠 것.
const FAST_CIV_SEED1_FARM_TICK := 2040
const FAST_CIV_SEED1_FARM_GEN := 28.5
## fast_civ 의 채집은 FARM_SEEDS 모두에서 진화 도중(이 평균 세대 이상)에 열려야 한다.
## 이전 값은 씨앗 1~3 이 4.35·0.22·0.49세대(첫 무작위 두뇌의 행동), 지금은 21.7·3.3·25.9세대(규칙 고침 전 33.9·4.2·23.3).
## 씨앗 1~3 만 본다: 씨앗 7 은 지금 값에서도 알려진 예외(채집·저장·농사 0.23·0.34·1.89세대 — 첫 세대 폭발,
## TUNING-fast_civ.md "목표와 다른 점").
const FAST_CIV_MIN_FORAGE_GEN := 2.0
## 성능(I34): 실제 시계 수치(개체·틱당 µs·틱/초)는 기록만 하고, 합격 기준은 같은 프로세스에서 번갈아 잰 기준 일(두뇌 순전파 모양의
## 곱셈·덧셈 고리) 한 번에 대한 배수 — 기계가 느리거나 다른 일로 바쁘면 둘이 함께 느려지므로 기계 속도에 덜 묶인다.
## 지금 기본·씨앗 2(평균 169마리)는 개체·틱당 기준 일 약 700번(이 컨테이너, 26~29µs). 예전 기준 "개체·틱당 < 50µs" 는
## Actions 28µs 로 여유가 두 배가 안 되는 실제 시계 단언이었다.
const PERF_MAX_RATIO := 1750.0
const PERF_REF_LEN := 256
const PERF_REF_REPS := 2000
const PERF_ROUNDS := 8
## 상대 성능(DESIGN-v0.2 12.5, test_performance_relative): 씨앗·데우기 틱·번갈아 돌리는 덩어리 틱. 0단계 한도 = 켬 = 끔(같은 설정)의
## 비가 [1 / 이 값, 이 값] 안. 0단계에 이 컨테이너에서 20번 잰 비: 0.903~1.093(중앙값 1.011, 표준편차 0.048 — max(비, 1/비) 1.107)이라
## 같은 일의 잡음이 약 ±10% — 여유를 더해 1.25.
const PERF_REL_SEED := 2
const PERF_REL_WARMUP := 800
const PERF_REL_CHUNK := 50
const PERF_REL_SAME_MAX := 1.25
## 1단계 상대 성능(DESIGN-v0.2 12.5 표 — 켬 = learn_basic 의 스위치, 끔 = 기본): 한도 = 같은 일의 잡음 최댓값 1.107 + 1단계 장치의 잰 비용 ÷
## 27.3µs(13절), 소수 둘째 자리로 올림. 잰 비용은 TEST-REPORT "v0.2 1단계" 절.
const PERF_REL_STAGE1_SETS := {"learn.enabled": true, "body.grow_enabled": true}
const PERF_REL_STAGE1_MAX := 1.33
## 연결 요소 계산(test_components_fast)의 상한: 같은 크기 지도를 한 번 훑는 거리장(BFS) 시간의 이 배수(지금 약 0.9배, 예전
## 계산은 요소 수 × 칸 수라 수천 배).
const COMPONENTS_MAX_RATIO := 10.0
## 실행기 자체를 검사하는 함수(기본 목록에는 없고 --only 로만 — test_runner_guards 가 따로 띄운 실행기에서 부름).
const SELF_TESTS: Array[String] = ["selftest_abort_midway"]

var _pass := 0
var _fail := 0
var _report: Array[String] = []
var _only: PackedStringArray = []
var _skip_slow := false
var _finished := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7).split(",")
		elif a == "--skip-slow":
			_skip_slow = true
	var tests := [
		"test_config", "test_static_rules", "test_rng", "test_terrain", "test_brain_layout_forward",
		"test_brain_genetics", "test_policy", "test_world_think_matches", "test_plants_light_resources",
		"test_energy_ledger", "test_death_causes", "test_reproduction", "test_population_cap",
		"test_discovery_forage", "test_discovery_store", "test_storehouse_rules", "test_farm_rules",
		"test_determinism", "test_snapshot_roundtrip", "test_snapshot_files", "test_runner",
		"test_extinction_no_resources", "test_memory_units", "test_performance", "test_performance_relative", "test_farm_reachable",
		"test_time_after_step", "test_event_copies", "test_extinction_mean_gen",
		"test_config_rules", "test_presets_file", "test_night_threshold", "test_components_fast", "test_snapshot_corrupt",
		"test_recorder_files", "test_tick_basis",
		"test_empty_start", "test_mate_once_per_tick", "test_store_max_count", "test_first_farm_once", "test_store_takes_pile", "test_store_tile_plants",
		"test_child_energy_cap", "test_store_built_in_act", "test_spoil_lifetime", "test_growth_interval",
		"test_farm_abandon_any_growth", "test_light_curve", "test_store_not_on_farm", "test_action_names", "test_harsh_winter",
		"test_farm_rule_values", "test_civ_rule_values", "test_runner_guards",
		"test_v01_golden", "test_act_counts", "test_eaten_ledger", "test_snapshot_v02_roundtrip", "test_snapshot_v01_fixture",
		"test_v02_config", "test_chance_baseline",
		"test_life_stage", "test_body_growth", "test_learn_genome", "test_learn_update_hand", "test_learning_picks", "test_learn_clamp",
		"test_learn_ledger", "test_learn_snapshot", "test_lamarck", "test_learn_freeze", "test_learn_config", "test_reset_learned",
	]
	# --only 의 이름은 모두 있는 검사여야 한다(J15): 오타 난 이름을 말없이 빼고 '0개·0 failed·종료 코드 0' 으로 끝나지 않게
	var unknown := PackedStringArray()
	for name in _only:
		if not tests.has(name) and not SELF_TESTS.has(name):
			unknown.append("\"%s\"" % name)
	if not unknown.is_empty():
		printerr("  실패: --only 에 모르는 검사 이름: %s (검사 목록은 tests/run_tests.gd 의 tests)" % ", ".join(unknown))
		print("RESULT: 0 checks passed, 1 failed")
		quit(1)
		return
	var order := tests.duplicate()
	order.append_array(SELF_TESTS)
	var ran := 0
	for t in order:
		# 실행기 자체를 검사하는 함수(SELF_TESTS)는 --only 로 이름을 댈 때만
		if (_only.is_empty() and SELF_TESTS.has(t)) or (not _only.is_empty() and not _only.has(t)):
			continue
		ran += 1
		var before := _fail
		var checks := _pass + _fail
		var t0 := Time.get_ticks_msec()
		_finished = false
		call(t)
		var did := _pass + _fail - checks
		if not _finished:
			_fail += 1
			printerr("  실패: %s 가 끝까지 실행되지 않음(스크립트 오류 — 검사 %d개 뒤 끊김)" % [t, did])
		elif did == 0:
			_fail += 1
			printerr("  실패: %s 가 검사를 하나도 하지 않음" % t)
		_report.append("%s %s (%.1fs)" % ["PASS" if _fail == before else "FAIL", t, float(Time.get_ticks_msec() - t0) / 1000.0])
	if ran == 0:
		_fail += 1
		printerr("  실패: 돌린 검사가 없음")
	print("\n".join(_report))
	print("RESULT: %d checks passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  실패: " + what)


## 검사 함수의 끝(그리고 일부러 일찍 끝내는 return 앞)에서 부른다 — 실행기가 이것으로 함수가 끝까지 돌았는지 본다.
func done() -> void:
	_finished = true


func cfg_with(sets: Dictionary = {}, preset: String = "default") -> Dictionary:
	var b := SimConfig.build(preset, sets)
	if b.error != "":
		printerr("  설정 오류: " + b.error)
	return b.config


func world(sets: Dictionary = {}, seed_value: int = 1, preset: String = "default") -> SimWorld:
	var wd := SimWorld.new()
	var e := wd.setup(cfg_with(sets, preset), seed_value)
	if e != "":
		printerr("  세계 만들기 실패: " + e)
	return wd


## 검사용 임시 폴더(사용자 폴더 아래, 프로세스마다 따로 — 다른 실행과 섞이지 않게). 앞 실행이 남긴 것은 지우고 돌려준다
## (쓰는 검사가 끝에 remove_tree 로 지움 — 4단계 최종 점검: 예전엔 user://test_snap·test_runner 가 실제 사용자 폴더에 남았음).
func tmp_dir(name: String) -> String:
	var dir := ProjectSettings.globalize_path("user://%s-%d" % [name, OS.get_process_id()])
	remove_tree(dir)
	return dir


## 폴더를 통째로 지운다(숨은 .gdignore·.bak 까지).
static func remove_tree(abs_dir: String) -> void:
	var d := DirAccess.open(abs_dir)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		remove_tree(abs_dir.path_join(sub))
	for f in d.get_files():
		DirAccess.remove_absolute(abs_dir.path_join(f))
	DirAccess.remove_absolute(abs_dir)


## 슬라임 없는 작은 세계(규칙 단위 검사용 — 슬라임은 add_slime 으로 손으로 놓는다). setup 은 개체 0 인 세계를 틱 0 멸종으로
## 기록하므로(I08) 그 기록을 지운다(손으로 놓은 개체가 사라질 때의 멸종을 보는 검사가 있음).
func empty_world(sets: Dictionary = {}) -> SimWorld:
	var s := {"population.initial": 0}
	s.merge(sets, true)
	var wd := world(s)
	wd.extinct_tick = -1
	wd.chronicle.clear()
	wd._pending_events.clear()
	return wd


## p 와 다른 발견 구역(discovery.region_size)에 있는 풀밭 칸 번호.
func other_region_grass(wd: SimWorld, p: Vector2i) -> int:
	var rs := int(wd.cfg.discovery.region_size)
	for c in wd.w * wd.h:
		if wd.tiles[c] == SimGrid.TILE_GRASS and ((c % wd.w) / rs != p.x / rs or (c / wd.w) / rs != p.y / rs):
			return c
	return -1


## 통과 가능한 풀밭 칸 하나(오른쪽·아래 이웃도 풀밭).
func grass_spot(wd: SimWorld) -> Vector2i:
	for y in range(2, wd.h - 2):
		for x in range(2, wd.w - 2):
			var ok := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if wd.tiles[(y + dy) * wd.w + x + dx] != SimGrid.TILE_GRASS:
						ok = false
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func add_slime(wd: SimWorld, p: Vector2i, energy_frac: float = 0.9, age: int = 100, head: int = 1) -> int:
	var g := SimBrain.random_genome(wd.cfg, wd.L, wd.rng_life)
	var id := wd._spawn(p.x, p.y, head, g, 0.0, 0, SimWorld.NO_PARENT, SimWorld.NO_PARENT, age)
	var i := wd.index_of_id(id)
	wd.s_energy[i] = energy_frac * wd.s_emax[i]
	wd.led_initial += wd.s_energy[i]
	return id


# ───────────────────────── 설정 ─────────────────────────

func test_config() -> void:
	var b := SimConfig.build("default", {})
	check(b.error == "", "기본 설정이 검증을 통과: " + b.error)
	for p in SimConfig.preset_names():
		var bp := SimConfig.build(p, {})
		check(bp.error == "", "예설정 %s 이 만들어짐: %s" % [p, bp.error])
	check(SimConfig.build("default", {"mutation.rat": 0.1}).error != "", "알 수 없는 키 거부")
	check(SimConfig.build("default", {"mutation.rate": "많이"}).error != "", "종류가 다른 값 거부")
	check(SimConfig.build("default", {"mutation.rate": 2.0}).error != "", "범위 밖 값 거부")
	check(SimConfig.build("없는예설정", {}).error != "", "없는 예설정 거부")
	check(SimConfig.build("default", {"seasons.growth": [1.0, 2.0]}).error != "", "계절 배열 길이 거부")
	check(SimConfig.build("default", {"mutation.rate": 0.1234567890123456789}).error != "", "JSON 으로 왕복하지 않는 수 거부")
	var c2 := cfg_with({"mutation.rate": 0.08, "population.initial": 50})
	check(c2.mutation.rate == 0.08 and int(c2.population.initial) == 50, "덮어쓰기 적용(정수 → 실수 칸 허용)")
	var j = JSON.parse_string(JSON.stringify(c2))
	check(SimConfig.deep_equal(j, c2) and SimConfig.validate(j) == "", "설정이 JSON 으로 그대로 왕복")
	check(SimConfig.parse_value("0.3") == 0.3 and SimConfig.parse_value("[1,2]") == [1.0, 2.0] and SimConfig.parse_value("글자") == "글자", "명령줄 값 해석")
	done()


## 매직 넘버·허용 목록 밖 함수 정적 검사(시뮬레이션 코드). 먼저 검사기 자체가 알려진 꼴을 잡는지 본다(정규식이 다시 눈멀지 않게).
func test_static_rules() -> void:
	# 검사기 자기 검사(I36): 한 줄씩 넣어 잡히는지 — 위반 꼴은 하나 이상, 허용 꼴은 하나도 없어야 함
	var probe_defined := {"_helper": true}
	var bad_lines := PackedStringArray([
		"var a := 1_000 * x", "var b := .25 * x", "var c := 0b1011 * x", "var d := 1e6 * x", "var e := 37 * x", "var f := 2.0 * x",
		"var g := 0x1F", "x = x ** 0.5", "x **= 2", "x = x * randf()", "x = float(randi() % 2)", "x = randf_range(0.0, 1.0)",
		"seed(1)", "randomize()", "x = asin(y) + acos(y)", "x = sinh(y)", "x = ease(t, e)", "x = db_to_linear(y)", "x = sin(y)",
		"x = pow(y, 2)", "x = lerpf(a, b, t)", "var v := Vector2.from_angle(a)", "v = v.rotated(b)", "x = v.angle()",
		"var r := RandomNumberGenerator.new()",
	])
	var missed := PackedStringArray()
	for ln in bad_lines:
		var hit := _scan_sim_lines("probe.gd", PackedStringArray([ln]), probe_defined)
		if hit.magic.is_empty() and hit.calls.is_empty():
			missed.append(ln)
	check(missed.is_empty(), "검사기가 위반 꼴 %d개를 모두 잡음(놓친 줄: %s)" % [bad_lines.size(), " | ".join(missed)])
	var ok_lines := PackedStringArray([
		"var a := minf(x, 1.0) * 0.5 + 2 - 1", "x = sqrt(y) - 0.0", "s = \"37 sin( randf() 1_000\"  # .25 asin(", "arr.append(0)",
		"x = _helper(y)", "const K := 37", "var t2 := s_x.size()", "var w := int(cfg.map.width)", "if (a and b) or not (c):",
		"var f2 := func(v): return v",
	])
	var noisy := PackedStringArray()
	for ln in ok_lines:
		var hit := _scan_sim_lines("probe.gd", PackedStringArray([ln]), probe_defined)
		if not hit.magic.is_empty() or not hit.calls.is_empty():
			noisy.append("%s → %s" % [ln, str(hit)])
	check(noisy.is_empty(), "허용 꼴은 잡지 않음(잘못 잡은 줄: %s)" % " | ".join(noisy))
	check(_scan_sim_lines(RNG_FILE, PackedStringArray(["var _r := RandomNumberGenerator.new()"]), {}).calls.is_empty(),
			"RandomNumberGenerator 는 %s 안에서만 받음" % RNG_FILE)
	# 실제 시뮬레이션 코드
	var files := DirAccess.get_files_at(SIM_DIR)
	check(files.size() >= 8, "시뮬레이션 파일을 찾음 (%d)" % files.size())
	var sources := {}
	var defined := {}
	var def_re := RegEx.create_from_string("^\\s*(?:static\\s+)?func\\s+([A-Za-z_]\\w*)")
	for f in files:
		if not f.ends_with(".gd"):
			continue
		sources[f] = FileAccess.get_file_as_string(SIM_DIR.path_join(f)).split("\n")
		for ln: String in sources[f]:
			var m := def_re.search(ln)
			if m != null:
				defined[m.get_string(1)] = true
	var magic: Array[String] = []
	var calls: Array[String] = []
	for f: String in sources:
		var hit := _scan_sim_lines(f, sources[f], defined)
		calls.append_array(hit.calls)
		if not MAGIC_EXEMPT.has(f):
			magic.append_array(hit.magic)
	check(magic.is_empty(), "시뮬레이션 코드에 매직 넘버 없음: " + ", ".join(magic))
	check(calls.is_empty(), "시뮬레이션 코드의 함수 호출·연산자가 허용 목록 안(플랫폼마다 다를 수 있는 수학·전역 난수 없음): " + ", ".join(calls))
	done()


## 정적 검사 한 파일분: {magic = [...], calls = [...]}. magic 은 MAGIC_ALLOWED 밖의 수(const 줄 제외), calls 는 허용 목록 밖의
## 호출(전역·메서드)·거듭제곱 연산자(**)·SimRng 밖의 RandomNumberGenerator. defined = 시뮬레이션 파일에 정의된 함수 이름(허용).
func _scan_sim_lines(fname: String, lines: PackedStringArray, defined: Dictionary) -> Dictionary:
	var num_re := RegEx.create_from_string(NUM_PATTERN)
	var call_re := RegEx.create_from_string("(?<![A-Za-z_0-9])([A-Za-z_][A-Za-z_0-9]*)\\s*\\(")
	var magic: Array[String] = []
	var calls: Array[String] = []
	for li in lines.size():
		var code := _strip_line(lines[li])
		if code.strip_edges() == "":
			continue
		var at := "%s:%d " % [fname, li + 1]
		if code.contains("**"):
			calls.append(at + "**")
		if fname != RNG_FILE and code.contains("RandomNumberGenerator"):
			calls.append(at + "RandomNumberGenerator")
		for m in call_re.search_all(code):
			var name := m.get_string(1)
			var k := m.get_start(1) - 1
			while k >= 0 and code[k] == " ":
				k -= 1
			var is_method := k >= 0 and code[k] == "."
			if defined.has(name) or GD_KEYWORDS.has(name):
				continue
			if is_method and not ALLOWED_METHODS.has(name):
				calls.append(at + "." + name + "(")
			elif not is_method and not ALLOWED_GLOBAL_CALLS.has(name):
				calls.append(at + name + "(")
		if code.strip_edges().begins_with("const "):
			continue
		for m in num_re.search_all(code):
			if not MAGIC_ALLOWED.has(m.get_string()):
				magic.append(at + m.get_string())
	return {magic = magic, calls = calls}


## 주석·문자열을 지운 코드 한 줄.
func _strip_line(line: String) -> String:
	var out := ""
	var in_str := false
	var q := ""
	var i := 0
	while i < line.length():
		var ch := line[i]
		if in_str:
			if ch == "\\":
				i += 2
				continue
			if ch == q:
				in_str = false
			i += 1
			continue
		if ch == "\"" or ch == "'":
			in_str = true
			q = ch
			out += " "
			i += 1
			continue
		if ch == "#":
			break
		out += ch
		i += 1
	return out


# ───────────────────────── 난수·지형 ─────────────────────────

func test_rng() -> void:
	var a := SimRng.new(7)
	var b := SimRng.new(7)
	var same := true
	for i in 1000:
		if a.uniform() != b.uniform():
			same = false
	check(same, "같은 씨앗 같은 수열")
	var st := a.get_state_string()
	var x1 := [a.uniform(), a.normal(), a.below(10)]
	var c := SimRng.new(0)
	check(c.set_state_string(st), "상태 문자열 복원")
	check([c.uniform(), c.normal(), c.below(10)] == x1, "상태 복원 후 같은 수열")
	check(not c.set_state_string("abc"), "잘못된 상태 거부")
	var n := 20000
	var s := 0.0
	var s2 := 0.0
	var lo := 1.0
	var hi := 0.0
	var below_ok := true
	for i in n:
		var v := a.normal()
		s += v
		s2 += v * v
		var u := a.uniform()
		lo = minf(lo, u)
		hi = maxf(hi, u)
		var k := a.below(5)
		if k < 0 or k >= 5:
			below_ok = false
	var mean := s / n
	var var_ := s2 / n - mean * mean
	check(absf(mean) < 0.03 and absf(var_ - 1.0) < 0.05, "정규 근사 평균 %.3f 분산 %.3f" % [mean, var_])
	check(lo >= 0.0 and hi < 1.0, "균등 범위 [0,1)")
	check(below_ok and a.below(0) == 0, "below 범위")
	done()


func test_terrain() -> void:
	var cfg := cfg_with()
	var t1 := SimTerrain.generate(cfg, 5)
	var t2 := SimTerrain.generate(cfg, 5)
	var t3 := SimTerrain.generate(cfg, 6)
	check(t1.tiles == t2.tiles and t1.fertility == t2.fertility, "같은 씨앗 같은 지형")
	check(t1.tiles != t3.tiles, "다른 씨앗 다른 지형")
	var w := int(cfg.map.width)
	var h := int(cfg.map.height)
	for sd in [1, 2, 3, 4, 5]:
		var t := SimTerrain.generate(cfg, sd)
		var comp := SimGrid.components(t.tiles, w, h)
		var open := 0
		for c in w * h:
			if SimGrid.passable(t.tiles[c]):
				open += 1
				if t.fertility[c] < float(cfg.map.fertility_floor) or t.fertility[c] > 1.0:
					check(false, "비옥도 범위 (씨앗 %d)" % sd)
		check(comp.sizes.size() == 1, "씨앗 %d: 통과 가능 영역이 하나로 이어짐 (%d개)" % [sd, comp.sizes.size()])
		var frac := float(open) / float(w * h)
		check(frac > 0.4 and frac < 0.95, "씨앗 %d: 땅 비율 %.2f" % [sd, frac])
	var dist := SimGrid.distance_field(t1.tiles, w, h, PackedInt32Array())
	check(dist[0] == SimGrid.FAR, "출발점 없으면 모두 FAR")
	# 지형 씨앗은 64비트 전체를 씀(J14): 2^32 차이 나는 씨앗도 다른 지도, 0 ~ 2^32 − 1 은 씨앗 그대로(지금까지의 지도·해시)
	var same_lo := []
	for pair in [[1, 4294967297], [-1, 4294967295], [5, 30064771077], [42, -4294967254], [0, 4294967296]]:
		var ta := SimTerrain.generate(cfg, pair[0])
		var tb := SimTerrain.generate(cfg, pair[1])
		if ta.tiles == tb.tiles and ta.fertility == tb.fertility:
			same_lo.append(pair)
	check(same_lo.is_empty(), "아래 32비트만 같은 씨앗은 다른 지형(같았던 쌍: %s)" % str(same_lo))
	check(SimTerrain.terrain_seed(0) == 0 and SimTerrain.terrain_seed(1) == 1 and SimTerrain.terrain_seed(4294967295) == 4294967295,
			"씨앗 0 ~ 2^32 − 1 의 지형 씨앗은 그대로")
	# 연결 요소(I31): 한 번 훑는 계산이 요소마다 거리장을 만드는 예전 계산과 같은 번호·크기
	var fine := cfg_with({"map.noise_cell": 1, "map.noise_detail_cell": 1, "map.rock_noise_cell": 1, "map.water_level": 0.5})
	var ft := SimTerrain.generate(fine, 3)
	var raw: PackedByteArray = ft.tiles.duplicate()
	for c in raw.size():
		if raw[c] == SimGrid.TILE_ROCK and (c * 7) % 3 == 0:
			raw[c] = SimGrid.TILE_GRASS
	var got := SimGrid.components(raw, w, h)
	var ref := _components_ref(raw, w, h)
	check(got.sizes.size() > 50 and got.labels == ref.labels and got.sizes == ref.sizes,
			"연결 요소 번호·크기 = 요소마다 거리장으로 센 값(잘게 갈라진 지형, 요소 %d개)" % got.sizes.size())
	done()


## 연결 요소의 참값: 요소마다 거리장을 새로 만든다(예전 SimGrid.components — 느리지만 뻔한 계산).
static func _components_ref(tiles: PackedByteArray, w: int, h: int) -> Dictionary:
	var labels := PackedInt32Array()
	labels.resize(w * h)
	labels.fill(-1)
	var sizes := PackedInt32Array()
	for c in w * h:
		if labels[c] != -1 or not SimGrid.passable(tiles[c]):
			continue
		var id := sizes.size()
		var d := SimGrid.distance_field(tiles, w, h, PackedInt32Array([c]))
		var count := 0
		for i in w * h:
			if d[i] != SimGrid.FAR:
				labels[i] = id
				count += 1
		sizes.append(count)
	return {labels = labels, sizes = sizes}


# ───────────────────────── 두뇌 ─────────────────────────

func test_brain_layout_forward() -> void:
	var cfg := cfg_with()
	var L := SimBrain.layout(cfg)
	check(L.n_in == 12 and L.n_hid == 8 and L.n_out == 8 and L.genes == 163, "구조 12-8-8, 유전자 163")
	var L2 := SimBrain.layout(cfg_with({"brain.memory_units": 2}))
	check(L2.n_in == 14 and L2.n_out == 10 and L2.genes == 14 * 8 + 10 * 8 + 3, "기억 2: 14-8-10, 유전자 195")
	# 손으로 계산: 은닉 0 이 입력 0(편향)만 2.0 으로 받음 → softsign(2) = 2/3. 출력 3(먹기)이 은닉 0 을 3.0 으로 받음 → 2.0
	var g := PackedFloat32Array()
	g.resize(L.genes)
	g[0] = 2.0
	g[L.w2_offset + 3 * L.n_hid + 0] = 3.0
	var inp := PackedFloat64Array()
	inp.resize(L.n_in)
	inp[0] = 1.0
	var r := SimBrain.forward(L, g, 0, inp, 4)
	check(is_equal_approx(r.hidden[0], 2.0 / 3.0) and r.hidden[1] == 0.0, "은닉 softsign 값")
	check(is_equal_approx(r.out[3], 2.0) and r.action == SimBrain.ACT_EAT, "출력 값과 가장 큰 행동")
	var psum := 0.0
	for p in r.probs:
		psum += p
	check(is_equal_approx(psum, 1.0) and r.probs[3] > r.probs[0], "확률 합 1, 먹기 확률이 가장 큼")
	check(SimBrain.softsign(0.0) == 0.0 and SimBrain.softsign(-1.0) == -0.5, "softsign")
	# 기억 2(I12): 은닉 0 이 기억 입력 0(번호 12)만 2.0 으로 받음 → 2/3, 기억 출력 0(번호 8)이 은닉 0 을 3.0 으로 받음 → 2.0.
	# 행동은 기본 출력 8개에서만 고름(기억 출력이 가장 커도 행동이 아님)
	var gm := PackedFloat32Array()
	gm.resize(L2.genes)
	gm[SimBrain.BASE_INPUTS] = 2.0
	gm[L2.w2_offset + SimBrain.BASE_OUTPUTS * L2.n_hid + 0] = 3.0
	var im := PackedFloat64Array()
	im.resize(L2.n_in)
	im[SimBrain.BASE_INPUTS] = 1.0
	var rm := SimBrain.forward(L2, gm, 0, im, 4)
	check(is_equal_approx(rm.hidden[0], 2.0 / 3.0) and is_equal_approx(rm.out[SimBrain.BASE_OUTPUTS], 2.0) and rm.out[SimBrain.BASE_OUTPUTS + 1] == 0.0
			and rm.action == SimBrain.ACT_FORWARD and rm.probs.size() == SimBrain.BASE_OUTPUTS,
			"기억 2: 기억 입력 → 은닉 → 기억 출력 값(%.3f), 행동은 기본 출력에서만" % rm.out[SimBrain.BASE_OUTPUTS])
	done()


func test_brain_genetics() -> void:
	var cfg := cfg_with()
	var L := SimBrain.layout(cfg)
	var rng := SimRng.new(3)
	var a := SimBrain.random_genome(cfg, L, rng)
	var b := SimBrain.random_genome(cfg, L, rng)
	check(a.size() == L.genes and a != b, "초기 유전체 길이와 다양성")
	var t: int = L.trait_offset
	check(a[t + SimBrain.TRAIT_SIZE] == float(cfg.traits.size_init) and a[t + SimBrain.TRAIT_SENSE] == float(cfg.traits.sense_init), "초기 특성 = 초기값")
	check(SimBrain.crossover(L, a, a, rng) == a, "같은 부모 교차 = 그대로")
	# 덩어리 보존: a = +1, b = -1 이면 은닉 j 의 들어오는·나가는 가중치 부호가 같아야 한다 — 기억 0 과 2(기억 입력·출력 가중치도
	# 그 은닉 뉴런의 덩어리, I12)
	for mem: int in [0, 2]:
		var Lm := SimBrain.layout(cfg_with({"brain.memory_units": mem}))
		var pa := PackedFloat32Array()
		pa.resize(Lm.genes)
		pa.fill(1.0)
		var pb := PackedFloat32Array()
		pb.resize(Lm.genes)
		pb.fill(-1.0)
		var mixed_any := false
		var block_ok := true
		for trial in 20:
			var c := SimBrain.crossover(Lm, pa, pb, rng)
			var signs := {}
			for j in Lm.n_hid:
				var sgn: float = c[j * Lm.n_in]
				signs[sgn] = true
				for i in Lm.n_in:
					if c[j * Lm.n_in + i] != sgn:
						block_ok = false
				for q in Lm.n_out:
					if c[Lm.w2_offset + q * Lm.n_hid + j] != sgn:
						block_ok = false
			if signs.size() == 2:
				mixed_any = true
		check(block_ok, "기억 %d: 교차가 뉴런 덩어리를 깨지 않음(입력 %d·출력 %d)" % [mem, Lm.n_in, Lm.n_out])
		check(mixed_any, "기억 %d: 교차가 두 부모를 섞음" % mem)
	var cfg0 := cfg_with({"mutation.rate": 0.0})
	var g0 := a.duplicate()
	check(SimBrain.mutate(cfg0, L, g0, rng) == 0 and g0 == a, "돌연변이율 0 → 바뀌지 않음")
	var cfg1 := cfg_with({"mutation.rate": 1.0, "mutation.sigma": 50.0})
	var g1 := a.duplicate()
	for k in 5:
		SimBrain.mutate(cfg1, L, g1, rng)
	var in_range := true
	for i in t:
		if absf(g1[i]) > float(cfg.brain.weight_clamp):
			in_range = false
	check(in_range, "가중치가 ±weight_clamp 안")
	# 경계값은 float32 로 저장되므로 float32 반올림 오차(1e-6)까지 허용
	check(g1[t + SimBrain.TRAIT_SIZE] >= float(cfg.traits.size_min) - 1e-6 and g1[t + SimBrain.TRAIT_SIZE] <= float(cfg.traits.size_max) + 1e-6, "크기 범위")
	check(g1[t + SimBrain.TRAIT_SENSE] >= float(cfg.traits.sense_min) - 1e-6 and g1[t + SimBrain.TRAIT_SENSE] <= float(cfg.traits.sense_max) + 1e-6, "감지 범위")
	check(g1[t + SimBrain.TRAIT_HUE] >= 0.0 and g1[t + SimBrain.TRAIT_HUE] < 1.0, "색 범위 [0,1)")
	# float32 반올림: 저장 배열 값은 float32 로 정확히 표현됨
	var f32 := PackedFloat32Array([g1[5]])
	check(f32[0] == g1[5], "유전자 값이 float32")
	done()


func test_policy() -> void:
	check(SimBrain.policy_weight(0.0, 4) == 1.0, "출력 0 의 가중치 1")
	check(SimBrain.policy_weight(10.0, 4) > SimBrain.policy_weight(1.0, 4) and SimBrain.policy_weight(-10.0, 4) < SimBrain.policy_weight(-1.0, 4), "가중치 단조 증가")
	check(SimBrain.policy_weight(-1e9, 4) >= 0.0, "가중치는 음수가 아님")
	var o := PackedFloat64Array([1.0, 3.0, 3.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	check(SimBrain.argmax_action(o) == 1, "같은 최댓값이면 작은 번호")
	done()


## SimWorld._think 의 펼친 계산이 SimBrain.forward·_quad 와 같은지 — 기억 0 과 2 세계 모두(I12). 기억 2 세계에서는 되먹임도:
## 판단 전 기억 값(s_mem)이 그대로 입력 BASE_INPUTS + k 로 들어가고, 판단 뒤 s_mem = softsign(기억 출력 k).
func test_world_think_matches() -> void:
	for mem: int in [0, 2]:
		var wd := world({"brain.memory_units": mem}, 4)
		wd.step_n(30)
		var ok_out := true
		var ok_quad := true
		var feed_bad := 0
		var back_bad := 0
		for i in mini(wd.population(), 60):
			var x := wd.s_x[i]
			var y := wd.s_y[i]
			var hd := wd.s_head[i]
			# 개체마다 다른 기억 값을 넣어 둠(그 값이 입력으로 들어가는지)
			var before := PackedFloat64Array()
			for k in mem:
				var v := (0.3 + 0.2 * k) * (1.0 if i % 2 == 0 else -1.0)
				wd.s_mem[i * mem + k] = v
				before.append(v)
			wd._think(i, x, y, y * wd.w + x, hd, wd.s_emax[i])
			for k in mem:
				if wd._in[SimBrain.BASE_INPUTS + k] != before[k]:
					feed_bad += 1
				if wd.s_mem[i * mem + k] != SimBrain.softsign(wd._out[SimBrain.BASE_OUTPUTS + k]):
					back_bad += 1
			var r := SimBrain.forward(wd.L, wd.s_genome, i * wd._G, wd._in, wd._sharpness)
			for q in wd._n_out:
				if r.out[q] != wd._out[q]:
					ok_out = false
			var rr := wd.s_sense[i]
			if wd.light < float(wd.cfg.time.night_light_threshold):
				rr = maxi(1, int(float(rr) * float(wd.cfg.sense.night_factor)))
			if wd._quad(x, y, hd, 1, rr, -rr, rr) != wd._in[SimBrain.IN_FOOD_AHEAD] or wd._quad(x, y, hd, -rr, rr, -rr, -1) != wd._in[SimBrain.IN_FOOD_LEFT] \
					or wd._quad(x, y, hd, -rr, rr, 1, rr) != wd._in[SimBrain.IN_FOOD_RIGHT]:
				ok_quad = false
		check(wd._n_out == SimBrain.BASE_OUTPUTS + mem and ok_out, "기억 %d: 세계 안 순전파 = SimBrain.forward (비트 단위, 출력 %d개)" % [mem, wd._n_out])
		check(ok_quad, "기억 %d: 펼친 영역 감지 = _quad (네 방향)" % mem)
		if mem > 0:
			check(feed_bad == 0, "기억 %d: 판단 전 기억 값이 입력 %d~%d 로 들어감(틀린 값 %d)" % [mem, SimBrain.BASE_INPUTS, SimBrain.BASE_INPUTS + mem - 1, feed_bad])
			check(back_bad == 0, "기억 %d: 판단 뒤 기억 값 = softsign(기억 출력)(틀린 값 %d)" % [mem, back_bad])
		# 정책 확률: 같은 출력이면 세계의 뽑기 가중치와 SimBrain.policy_weight 가 같다
		wd._pick_action()
		var same := true
		for q in SimBrain.BASE_OUTPUTS:
			if wd._wts[q] != SimBrain.policy_weight(wd._out[q], wd._sharpness):
				same = false
		check(same, "기억 %d: 펼친 정책 가중치 = policy_weight" % mem)
	# 평생 학습을 켠 세계(DESIGN-v0.2 14.2 검사 기준 8): 행동 행은 배운 두뇌, 기억 행은 유전체 — SimBrain.forward_phen 과 비트 단위로 같음.
	# 배운 두뇌가 실제로 타고난 것과 달라진 뒤에 견줌(같으면 유전체 순전파와 견줘도 통과하므로 — 그 경우도 세어 보임)
	for mem: int in [0, 2]:
		var wl := world({"learn.enabled": true, "brain.memory_units": mem}, 4)
		wl.step_n(60)
		var bad_out := 0
		var learned := 0
		var differs_from_genome := 0
		for i in mini(wl.population(), 60):
			if wl.learned_amount_of(i) > 0.0:
				learned += 1
			wl._think(i, wl.s_x[i], wl.s_y[i], wl.s_y[i] * wl.w + wl.s_x[i], wl.s_head[i], wl.s_emax[i])
			var rp := SimBrain.forward_phen(wl.L, wl.s_genome, i * wl._G, wl.s_w2, i * wl._w2n, wl._in, wl._sharpness)
			var rg := SimBrain.forward(wl.L, wl.s_genome, i * wl._G, wl._in, wl._sharpness)
			for q in wl._n_out:
				if rp.out[q] != wl._out[q]:
					bad_out += 1
			if rg.out != wl._out:
				differs_from_genome += 1
		check(learned > 0 and differs_from_genome > 0 and bad_out == 0,
				"학습 켬·기억 %d: 세계 안 순전파 = SimBrain.forward_phen(비트 단위, 출력 %d개 — 틀린 값 %d, 배운 개체 %d, 유전체 순전파와 다른 개체 %d)" % [
				mem, wl._n_out, bad_out, learned, differs_from_genome])
	# 되먹임이 실제 흐름에서 다음 틱 판단을 바꿈: 같은 세계 둘 중 하나만 기억 값을 바꾸면 그 개체의 다음 판단 출력이 달라짐
	var wa := world({"brain.memory_units": 2}, 4)
	wa.step_n(30)
	var wb: SimWorld = SimSnapshot.from_text(SimSnapshot.to_text(wa)).world
	var differ := 0
	for i in mini(wa.population(), 40):
		wb.s_mem[i * 2] = -wa.s_mem[i * 2] if wa.s_mem[i * 2] != 0.0 else 0.5
		wa._think(i, wa.s_x[i], wa.s_y[i], wa.s_y[i] * wa.w + wa.s_x[i], wa.s_head[i], wa.s_emax[i])
		wb._think(i, wb.s_x[i], wb.s_y[i], wb.s_y[i] * wb.w + wb.s_x[i], wb.s_head[i], wb.s_emax[i])
		if wa._out != wb._out:
			differ += 1
	check(differ > 0, "기억 2: 기억 값만 다른 두 세계의 판단 출력이 다름(%d마리)" % differ)
	done()


# ───────────────────────── 생태 ─────────────────────────

func test_plants_light_resources() -> void:
	var wd := empty_world()
	# 성장은 그 갱신이 덮는 틱들(tick ~ tick + update_every − 1)의 빛으로 셈(J02) — 밤 구간 첫 틱에서 갱신(덮는 틱 모두 밤)
	var lit_ticks := int(float(wd.cfg.time.day_ticks) * float(wd.cfg.time.daylight_fraction))
	wd.tick = lit_ticks
	for c in wd.w * wd.h:
		wd.food[c] = 0.0
	wd._grow_plants()
	var grew := false
	for c in wd.w * wd.h:
		if wd.food[c] > 0.0:
			grew = true
	check(not grew, "밤(빛 0, night_growth 0)에는 식물이 자라지 않음")
	wd.tick = int(wd.cfg.time.twilight_ticks)
	wd._grow_plants()
	var grew2 := false
	for c in wd.w * wd.h:
		if wd.food[c] > 0.0:
			grew2 = true
		if wd.food[c] > wd.food_cap[c] + 1e-12:
			check(false, "먹이가 상한을 넘음")
	check(grew2, "낮에는 자람")
	var w0 := world({"resources.scale": 0.0, "population.initial": 0})
	w0.step_n(200)
	check(w0.sum_of(w0.food) == 0.0, "자원량 0 → 먹이 0")
	var wt := empty_world()
	var day := int(wt.cfg.time.day_ticks)
	var lights := PackedFloat64Array()
	for t in day:
		wt.tick = t
		wt._compute_time()
		lights.append(wt.light)
	check(lights.has(1.0) and lights.has(0.0), "하루에 낮과 밤이 있음")
	wt.tick = day * int(wt.cfg.time.season_days) * 3
	wt._compute_time()
	check(wt.season == 3 and wt.season_growth == float(wt.cfg.seasons.growth[3]), "네 번째 계절 = 겨울 성장 배수")
	var wns := empty_world({"time.season_days": 0})
	wns._compute_time()
	check(wns.season == -1 and wns.season_growth == 1.0, "계절 끔")
	done()


func test_energy_ledger() -> void:
	var wd := world({}, 9)
	var worst := 0.0
	for k in 600:
		wd.step()
		if k % 50 == 0:
			worst = maxf(worst, absf(wd.total_energy() - wd.ledger_expected()))
	worst = maxf(worst, absf(wd.total_energy() - wd.ledger_expected()))
	# GDScript 의 % 형식에는 지수 표기(%e)가 없다 → String.num_scientific
	check(worst < 1e-6, "에너지 장부 오차 %s (없는 데서 에너지가 생기지 않음)" % String.num_scientific(worst))
	check(wd.total_births > 0 and wd.total_deaths > 0, "600틱 동안 출생·사망이 있음")
	# 저장분·운반분 먹기도 장부에(I32): 위 세계(기본·씨앗 9·600틱)는 채집 전이라 그 길을 지나지 않음
	var we := empty_world()
	var p := grass_spot(we)
	var c := p.y * we.w + p.x
	we.store_tiles.append(c)
	we.store_food.append(50.0)
	we._rebuild_stores()
	we.stage = SimWorld.STAGE_STORE
	var i := we.index_of_id(add_slime(we, p, 0.2))
	var e0 := we.s_energy[i]
	var l0 := we.led_eaten
	we._eat(i, c, we.s_size[i], we.s_emax[i])
	check(we.store_food[0] < 50.0 and we.s_energy[i] > e0 and absf((we.led_eaten - l0) - (we.s_energy[i] - e0)) < 1e-12, "저장고 칸에서 먹은 에너지 %.3f 가 장부에 같은 만큼" % (we.s_energy[i] - e0))
	var q := c + 1
	we.food[q] = 0.0
	we.dropped[q] = 0.0
	we.s_carry[i] = 2.0
	e0 = we.s_energy[i]
	l0 = we.led_eaten
	we._eat(i, q, we.s_size[i], we.s_emax[i])
	check(we.s_carry[i] < 2.0 and we.s_energy[i] > e0 and absf((we.led_eaten - l0) - (we.s_energy[i] - e0)) < 1e-12, "빈 칸에서 운반분을 먹은 에너지 %.3f 가 장부에 같은 만큼" % (we.s_energy[i] - e0))
	check(absf(we.total_energy() - we.ledger_expected()) < 1e-9, "손으로 놓은 세계의 장부 오차 0")
	# 밭 단계 실제 흐름: 저장고·운반·밭이 있는 세계를 매 틱 잼
	var fr: Dictionary = farm_runs()[0]
	var fw: SimWorld = fr.world
	check(fw.stage == SimWorld.STAGE_FARM and fr.max_carry > 0.0 and fr.max_stored > 0.0 and fr.worst_ledger < 1e-6,
			"%s·씨앗 %d·%d틱(농사, 운반 최대 %.0f·저장 최대 %.0f): 매 틱 장부 오차 %s" % [FARM_RUN_PRESET, FARM_RUN_SEED, FARM_RUN_TICKS,
			fr.max_carry, fr.max_stored, String.num_scientific(fr.worst_ledger)])
	done()


func test_death_causes() -> void:
	var wd := empty_world()
	var p := grass_spot(wd)
	wd.food[p.y * wd.w + p.x] = 0.0
	var a := add_slime(wd, p, 0.0001, 10)
	var b := add_slime(wd, p, 0.9, 10)
	var ib := wd.index_of_id(b)
	wd.s_max_age[ib] = 11
	wd.step()
	check(wd.lin_cause[a] == SimWorld.CAUSE_STARVED and wd.lin_death[a] == 0, "에너지 0 → 굶어 죽음")
	check(wd.lin_cause[b] == SimWorld.CAUSE_OLD, "최대 나이 → 늙어 죽음")
	check(wd.population() == 0 and wd.count_grid[p.y * wd.w + p.x] == 0, "죽은 개체가 칸 수에서 빠짐")
	check(wd.is_extinct() and wd.extinct_tick == 1, "멸종 기록")
	done()


func test_reproduction() -> void:
	var wd := empty_world({"mutation.rate": 0.0})
	var p := grass_spot(wd)
	var a := add_slime(wd, p, 0.9, 100)
	var b := add_slime(wd, p + Vector2i(1, 0), 0.9, 100)
	var ea := wd.s_energy[wd.index_of_id(a)]
	var eb := wd.s_energy[wd.index_of_id(b)]
	wd.s_dead.fill(0)
	wd._reproduce()
	check(wd.population() == 3, "조건이 맞는 이웃 둘 → 자식 하나")
	var c := 2
	var rp: Dictionary = wd.cfg.repro
	var expect := (float(rp.cost_frac) * ea + float(rp.cost_frac) * eb) * float(rp.transfer_efficiency)
	check(is_equal_approx(wd.s_energy[wd.index_of_id(c)], expect), "자식 에너지 = 부모가 낸 몫 × 효율")
	check(wd.lin_pa[c] == a and wd.lin_pb[c] == b and wd.lin_gen[c] == 1, "부모·세대 기록")
	check(wd.lin_children[a] == 1 and wd.lin_children[b] == 1, "부모 자식 수")
	var gc := wd.s_genome.slice(2 * wd._G, 3 * wd._G)
	var ga := wd.s_genome.slice(0, wd._G)
	var gb := wd.s_genome.slice(wd._G, 2 * wd._G)
	var from_parents := true
	for i in wd._G:
		if gc[i] != ga[i] and gc[i] != gb[i]:
			from_parents = false
	check(from_parents, "돌연변이 0 이면 자식 유전자는 모두 부모 중 하나의 값")
	wd.s_dead.fill(0)
	wd._reproduce()
	check(wd.population() == 3, "쿨다운 중에는 다시 번식하지 않음")
	var w2 := empty_world()
	var q := grass_spot(w2)
	add_slime(w2, q, 0.9, 1)
	add_slime(w2, q, 0.9, 1)
	w2.s_dead.fill(0)
	w2._reproduce()
	check(w2.population() == 2, "미성숙 개체는 번식하지 않음")
	var w3 := empty_world()
	var r := grass_spot(w3)
	add_slime(w3, r, 0.9, 100)
	add_slime(w3, r + Vector2i(int(w3.cfg.repro.mate_radius) + 1, 0), 0.9, 100)
	w3.s_dead.fill(0)
	w3._reproduce()
	check(w3.population() == 2, "짝 반경 밖이면 번식하지 않음")
	var w4 := empty_world({"repro.asexual_when_alone": true})
	add_slime(w4, grass_spot(w4), 0.9, 100)
	w4.s_dead.fill(0)
	w4._reproduce()
	check(w4.population() == 2 and w4.lin_pb[1] == SimWorld.NO_PARENT, "혼자 번식 켜면 분열")
	done()


func test_population_cap() -> void:
	var wd := world({"population.cap": 150, "population.initial": 100}, 2)
	var over := false
	for k in 800:
		wd.step()
		if wd.population() > 150:
			over = true
	check(not over, "개체 수가 상한을 넘지 않음 (최고 %d)" % wd.peak_population)
	done()


# ───────────────────────── 발견·건물 ─────────────────────────

func test_discovery_forage() -> void:
	var wd := empty_world()
	var p := grass_spot(wd)
	var id := add_slime(wd, p, 1.0)
	var i := wd.index_of_id(id)
	wd.food[p.y * wd.w + p.x] = 5.0
	# 발견 전 줍기: 효과 없이 시도만 센다
	wd.s_last_action[i] = SimBrain.ACT_GATHER
	wd.cfg.brain.think_every = 1000000
	wd._think_every = 1000000
	wd.tick = 1
	wd._act_all()
	check(wd.s_carry[i] == 0.0 and wd.forage_attempts == 1, "발견 전 줍기는 효과 없이 시도 1회")
	wd.forage_attempts = int(wd.cfg.discovery.forage_threshold) - 1
	wd._check_civ()
	check(wd.stage == SimWorld.STAGE_NONE, "임계 전에는 발견 안 됨")
	wd.forage_attempts += 1
	wd._check_civ()
	wd._check_civ()
	var n_disc := 0
	for e in wd.chronicle:
		if e.kind == "discovery":
			n_disc += 1
	check(wd.stage == SimWorld.STAGE_FORAGE and n_disc == 1, "임계에서 채집 발견 정확히 한 번")
	wd._act_all()
	check(wd.s_carry[i] > 0.0, "발견 후 줍기는 운반량을 늘림")
	var events := wd.drain_events()
	check(events.size() >= 1 and wd.drain_events().is_empty(), "화면용 사건은 한 번만 꺼내짐")
	done()


func test_discovery_store() -> void:
	var wd := empty_world()
	var p := grass_spot(wd)
	var id := add_slime(wd, p)
	var i := wd.index_of_id(id)
	var c := p.y * wd.w + p.x
	var thr := float(wd.cfg.discovery.store_threshold)
	# 채집 전 내려놓기는 저장 발견 집계에 들어가지 않음(운반 자체가 불가능하지만 규칙으로도 막음)
	wd.s_carry[i] = thr + 1.0
	wd._drop(i, c)
	check(wd.stage == SimWorld.STAGE_NONE and wd.store_tiles.is_empty() and wd.region_drop[0] + wd.store_drops_total == 0.0, "채집 전에는 저장 발견 집계 없음")
	wd.stage = SimWorld.STAGE_FORAGE
	wd.s_carry[i] = thr * 0.5
	wd._drop(i, c)
	check(wd.store_tiles.is_empty(), "구역 임계 전에는 저장고 없음")
	wd.s_carry[i] = thr * 0.6
	wd._drop(i, c)
	check(wd.stage == SimWorld.STAGE_STORE and wd.store_tiles.size() == 1 and wd.store_tiles[0] == c, "구역 임계 → 저장 발견, 가장 많이 놓인 칸에 저장고")
	check(wd.store_at[c] == 0 and wd.store_dist[c] == 0, "저장고 위치·거리장")
	# 가까운 구역에서 다시 넘으면 간격 규칙으로 짓지 않음
	var p2 := p + Vector2i(1, 0)
	var c2 := p2.y * wd.w + p2.x
	wd.s_carry[i] = thr * 1.1
	wd._drop(i, c2)
	check(wd.store_tiles.size() == 1, "최소 간격 안에는 저장고를 더 짓지 않음")
	done()


func test_storehouse_rules() -> void:
	var wd := empty_world()
	var p := grass_spot(wd)
	var c := p.y * wd.w + p.x
	wd.stage = SimWorld.STAGE_STORE
	wd.store_tiles.append(c)
	wd.store_food.append(0.0)
	wd._rebuild_stores()
	var id := add_slime(wd, p)
	var i := wd.index_of_id(id)
	wd.s_carry[i] = 5.0
	wd._drop(i, c)
	check(wd.store_food[0] == 5.0 and wd.s_carry[i] == 0.0 and wd.dropped[c] == 0.0, "저장고 칸에 내려놓으면 저장")
	wd.s_carry[i] = float(wd.cfg.store.capacity)
	wd._drop(i, c)
	check(wd.store_food[0] == float(wd.cfg.store.capacity) and wd.s_carry[i] == 5.0, "용량을 넘는 몫은 운반으로 남음")
	wd.s_carry[i] = 0.0
	wd.s_energy[i] = 1.0
	var before: float = wd.store_food[0]
	wd._eat(i, c, wd.s_size[i], wd.s_emax[i])
	check(wd.store_food[0] < before and wd.s_energy[i] > 1.0, "저장고 칸에서 먹으면 저장분을 먹음")
	# 저장분은 썩지 않음
	wd.s_energy[i] = wd.s_emax[i]
	wd.s_max_age[i] = 1000000
	var stored: float = wd.store_food[0]
	wd.s_last_action[i] = SimBrain.ACT_REST
	wd._think_every = 1000000
	wd.tick = 1
	for k in 300:
		wd.s_energy[i] = wd.s_emax[i]
		wd._spoil_dropped()
		wd._act_all()
	check(wd.store_food[0] == stored, "저장분은 시간이 지나도 줄지 않음")
	# 바닥 먹이는 썩음(내려놓은 틱의 ⑥ 포함 spoil_ticks + 1 번째 ⑥ 에서 — 실제 틱 흐름의 수명은 test_spoil_lifetime)
	wd._put_dropped(c + 1, 3.0)
	for k in int(wd.cfg.dropped.spoil_ticks) + 1:
		wd._spoil_dropped()
	check(wd.dropped[c + 1] == 0.0 and wd.drop_listed[c + 1] == 0, "바닥 먹이는 spoil_ticks 뒤 사라짐")
	done()


func test_farm_rules() -> void:
	var wd := empty_world()
	var p := grass_spot(wd)
	var c := p.y * wd.w + p.x
	wd.store_tiles.append(c)
	wd.store_food.append(0.0)
	wd._rebuild_stores()
	wd.stage = SimWorld.STAGE_STORE
	var id := add_slime(wd, p + Vector2i(0, 1), 0.9, 100, 1)
	var i := wd.index_of_id(id)
	wd.s_carry[i] = 3.0
	var target := Vector2i(p.x + 1, p.y + 1)
	var tc := target.y * wd.w + target.x
	# 농사 발견 전 심기는 효과 없음
	wd.s_last_action[i] = SimBrain.ACT_PLANT
	wd._think_every = 1000000
	wd.tick = 1
	wd._act_all()
	check(wd.tiles[tc] == SimGrid.TILE_GRASS and wd.s_carry[i] == 3.0, "농사 전 심기는 효과 없음")
	# 저장고 근처 싹 → 농사 발견
	wd.farm_sprouts = int(wd.cfg.discovery.farm_threshold)
	wd._check_civ()
	check(wd.stage == SimWorld.STAGE_FARM, "싹 임계 → 농사 발견")
	wd._act_all()
	check(wd.tiles[tc] == SimGrid.TILE_FARM and wd.farms.size() == 1 and wd.s_carry[i] == 3.0 - float(wd.cfg.farm.seed_cost), "심기 → 앞 칸이 밭, 씨앗 비용")
	var ff: Dictionary = wd.chronicle.back() if not wd.chronicle.is_empty() else {}
	check(str(ff.get("kind", "")) == "first_farm" and str(ff.get("text", "")) == "첫 밭 — #%d, (%d, %d) 에 심음" % [id, target.x, target.y],
			"첫 밭 사건 문장은 숫자 뒤 조사 없이(\"#1030 가\" 아님): " + str(ff.get("text", "")))
	check(wd.food_cap[tc] > float(wd.cfg.plants.max_food) * float(wd.base_fert[tc]) and wd.fert[tc] == 1.0, "밭은 비옥도 1·상한 증가")
	# 버려진 밭은 풀밭으로
	wd.tick = wd.farm_visit[tc] + int(wd.cfg.farm.abandon_ticks) + 1
	wd._abandon_farms()
	check(wd.tiles[tc] == SimGrid.TILE_GRASS and wd.farms.is_empty(), "abandon_ticks 동안 안 밟은 밭은 풀밭으로")
	# 싹 규칙: 저장고 근처 풀밭에서 썩은 먹이가 싹틀 수 있음(확률 1 로)
	var w2 := empty_world({"dropped.sprout_chance": 1.0})
	var q := grass_spot(w2)
	var qc := q.y * w2.w + q.x
	w2.store_tiles.append(qc)
	w2.store_food.append(0.0)
	w2._rebuild_stores()
	w2.stage = SimWorld.STAGE_STORE
	var f0 := w2.base_fert[qc + 1]
	w2._put_dropped(qc + 1, 2.0)
	for k in int(w2.cfg.dropped.spoil_ticks) + 1:
		w2._spoil_dropped()
	check(w2.farm_sprouts == 1 and w2.base_fert[qc + 1] > f0, "저장고 근처 싹 1번, 비옥도 증가")
	done()


# ───────────────────────── 결정성·저장 ─────────────────────────

func run_hash(seed_value: int, ticks: int, sets: Dictionary = {}) -> Array:
	var wd := world(sets, seed_value)
	var rec := SimRecorder.new()
	for k in ticks:
		wd.step()
		if wd.tick % int(wd.cfg.record.every) == 0:
			rec.record(wd)
	return [wd.history_hash, rec.timeseries_csv(), wd]


## 밭 단계 기준 실행(I09·I10·I32). demo_fast·씨앗 2 는 263틱에 농사를 열어 FARM_RUN_SNAP(600)틱에 밭 35곳·저장고 4개이고,
## 그 뒤 farm.abandon_ticks(300) 넘게 더 돌며 밭을 심고 잃는다(600 ~ 1,000틱 버려짐 사건 20번 남짓). 같은 설정을 두 번 돌린 세계
## (결정성)·600틱 스냅숏(왕복)·매 틱 장부 오차를 한 번에 만들고 여러 검사가 읽기만 한다(규칙 검사 시간을 아끼려고 — 약 8초).
## 예전 결정성·왕복·장부 검사는 채집·저장 단계까지만 돌아 밭 규칙(심기·밭 성장·버려짐)과 farm_visit 를 거치지 않았다.
const FARM_RUN_PRESET := "demo_fast"
const FARM_RUN_SEED := 2
const FARM_RUN_SNAP := 600
const FARM_RUN_TICKS := 1000
var _farm_runs: Array = []


## [첫 실행, 둘째 실행] — 각각 {world, csv, snap(FARM_RUN_SNAP 틱 스냅숏 글), worst_ledger, max_carry, max_stored}(장부·운반·저장은 첫 실행만 잼).
func farm_runs() -> Array:
	if not _farm_runs.is_empty():
		return _farm_runs
	for k in 2:
		var wd := world({}, FARM_RUN_SEED, FARM_RUN_PRESET)
		var rec := SimRecorder.new()
		var run := {snap = "", worst_ledger = 0.0, max_carry = 0.0, max_stored = 0.0}
		while wd.tick < FARM_RUN_TICKS:
			wd.step()
			if wd.tick % int(wd.cfg.record.every) == 0:
				rec.record(wd)
			if k == 0:
				run.worst_ledger = maxf(run.worst_ledger, absf(wd.total_energy() - wd.ledger_expected()))
				run.max_carry = maxf(run.max_carry, wd.sum_of(wd.s_carry))
				run.max_stored = maxf(run.max_stored, wd.sum_of(wd.store_food))
			if wd.tick == FARM_RUN_SNAP:
				run.snap = SimSnapshot.to_text(wd)
		run.world = wd
		run.csv = rec.timeseries_csv()
		_farm_runs.append(run)
	return _farm_runs


## 연대기에서 kind 사건의 수(after 틱 뒤의 것만).
static func count_events(wd: SimWorld, kind: String, after: int = -1) -> int:
	var n := 0
	for e in wd.chronicle:
		if str(e.kind) == kind and int(e.tick) > after:
			n += 1
	return n


func test_determinism() -> void:
	var a := run_hash(11, 1500)
	var b := run_hash(11, 1500)
	var c := run_hash(12, 1500)
	check(a[0] == b[0] and a[0] != "", "같은 씨앗 → 같은 역사 해시")
	check(a[1] == b[1], "같은 씨앗 → 같은 시계열 CSV")
	check(a[0] != c[0], "다른 씨앗 → 다른 해시")
	var wa: SimWorld = a[2]
	var wb: SimWorld = b[2]
	check(wa.s_genome == wb.s_genome and wa.lin_gen == wb.lin_gen, "같은 씨앗 → 같은 유전체·계통")
	var d := run_hash(11, 1500, {"mutation.rate": 0.1})
	check(a[0] != d[0], "파라미터가 다르면 다른 해시")
	# 밭 단계(I10): 기본·씨앗 11 은 1,500틱에도 채집 단계라 심기·밭 성장·버려짐을 거치지 않음 — 밭을 심고 잃는 세계를 두 번
	var fr := farm_runs()
	var fa: SimWorld = fr[0].world
	var fb: SimWorld = fr[1].world
	var lost := count_events(fa, "farm_lost")
	check(fa.stage == SimWorld.STAGE_FARM and fa.first_farm_tick >= 0 and fa.farms.size() > 0 and lost > 0,
			"%s·씨앗 %d·%d틱: 농사 단계에서 밭을 심고 잃음(첫 밭 틱 %d, 밭 %d곳, 버려짐 사건 %d번)" % [FARM_RUN_PRESET, FARM_RUN_SEED,
			FARM_RUN_TICKS, fa.first_farm_tick, fa.farms.size(), lost])
	check(fa.history_hash == fb.history_hash and fr[0].csv == fr[1].csv, "밭 단계: 같은 씨앗 → 같은 역사 해시·시계열 CSV")
	check(SimSnapshot.to_text(fa) == SimSnapshot.to_text(fb), "밭 단계: 같은 씨앗 → 같은 전체 상태(밭·farm_visit·연대기까지)")
	done()


func test_snapshot_roundtrip() -> void:
	var wd := world({}, 21)
	wd.step_n(700)
	# 저장 단계(씨앗 21 은 338틱에 저장 발견)에 손으로 저장고를 하나 더 만든다 — 밭은 아래 밭 단계 왕복에서
	var p := grass_spot(wd)
	wd.store_tiles.append(p.y * wd.w + p.x)
	wd.store_food.append(12.5)
	wd._rebuild_stores()
	var text := SimSnapshot.to_text(wd)
	var r := SimSnapshot.from_text(text)
	check(r.error == "", "스냅숏 복원: " + str(r.error))
	if r.world == null:
		done()
		return
	var w2: SimWorld = r.world
	check(SimSnapshot.to_text(w2) == text, "복원 → 다시 직렬화가 같은 글자")
	wd.step_n(400)
	w2.step_n(400)
	check(wd.history_hash == w2.history_hash and wd.tick == w2.tick, "복원 후 이어 돌린 해시 = 끊김 없이 돌린 해시")
	check(SimSnapshot.to_text(wd) == SimSnapshot.to_text(w2), "이어 돌린 뒤 전체 상태가 같음")
	# 기억 뉴런을 켠 세계도 왕복
	var wm := world({"brain.memory_units": 2}, 3)
	wm.step_n(200)
	var rm := SimSnapshot.from_text(SimSnapshot.to_text(wm))
	check(rm.error == "", "기억 2 스냅숏 복원")
	if rm.world != null:
		wm.step_n(100)
		rm.world.step_n(100)
		check(wm.history_hash == rm.world.history_hash and SimSnapshot.to_text(wm) == SimSnapshot.to_text(rm.world), "기억 2 왕복 후 같은 해시·전체 상태")
	# 밭 단계 왕복(I09): 600틱(밭 35곳) 스냅숏에서 이어 돌린 세계 = 끊김 없이 돌린 세계(farm.abandon_ticks 보다 길게 — 왕복한 farm_visit 로
	# 밭을 잃음). 예전엔 저장 단계까지만 왕복해 farm_visit 를 저장·복원에서 함께 빼도 통과했다.
	var fr := farm_runs()
	var fa: SimWorld = fr[0].world
	var rf := SimSnapshot.from_text(fr[0].snap)
	check(rf.error == "" and rf.world != null and rf.world.tick == FARM_RUN_SNAP and rf.world.farms.size() > 0,
			"밭 단계 스냅숏 복원(틱 %d, 밭 %d곳): %s" % [FARM_RUN_SNAP, rf.world.farms.size() if rf.world != null else -1, str(rf.error)])
	if rf.world != null:
		var wf: SimWorld = rf.world
		var rec := SimRecorder.new()
		while wf.tick < FARM_RUN_TICKS:
			wf.step()
			if wf.tick % int(wf.cfg.record.every) == 0:
				rec.record(wf)
		var lost := count_events(fa, "farm_lost", FARM_RUN_SNAP)
		check(lost > 0 and FARM_RUN_TICKS - FARM_RUN_SNAP > int(fa.cfg.farm.abandon_ticks), "왕복 뒤 구간(%d틱 > 버려짐 %d틱)에 밭을 잃음(%d번)" % [
				FARM_RUN_TICKS - FARM_RUN_SNAP, int(fa.cfg.farm.abandon_ticks), lost])
		check(wf.history_hash == fa.history_hash and SimSnapshot.to_text(wf) == SimSnapshot.to_text(fa),
				"밭 단계 스냅숏에서 %d틱 이어 돌린 해시·전체 상태 = 끊김 없이 돌린 것(밭 %d곳 / %d곳)" % [FARM_RUN_TICKS - FARM_RUN_SNAP, wf.farms.size(), fa.farms.size()])
	# 구조(I09): 세계의 모든 상태 변수가 왕복 뒤 같음 — 저장·복원 양쪽에서 함께 빠진 변수는 '다시 직렬화한 글이 같음'으로는 못 잡음.
	# 틱 안에서만 쓰는 계산 자리(SNAPSHOT_SCRATCH)만 빼고, 저장하지 않고 다시 만드는 값(s_size·store_dist·count_grid 등)도 견줌
	var rt: SimWorld = SimSnapshot.from_text(SimSnapshot.to_text(fa)).world
	var vars := world_state_vars(fa)
	check(vars.size() > 60 and rt != null and world_vars_differ(fa, rt).is_empty(),
			"밭 단계 세계(%d틱)의 상태 변수 %d개가 모두 왕복(다른 변수: %s)" % [fa.tick, vars.size(), ", ".join(world_vars_differ(fa, rt)) if rt != null else "복원 실패"])
	var missing: Array[String] = []
	for name in SNAPSHOT_SCRATCH:
		if not vars.has(name) and not world_state_vars(fa, true).has(name):
			missing.append(name)
	check(missing.is_empty(), "왕복에서 빼는 계산 자리 이름이 모두 SimWorld 변수(낡은 이름: %s)" % ", ".join(missing))
	# 거부
	var d = JSON.parse_string(text)
	d.version = 99
	check(SimSnapshot.from_dict(d).error != "", "다른 버전 거부")
	d = JSON.parse_string(text)
	d.slimes.genome = SimSnapshot.b64(wd.s_genome.slice(0, wd._G * 2))
	check(SimSnapshot.from_dict(d).error.contains("유전체"), "유전체 길이가 틀리면 거부")
	d = JSON.parse_string(text)
	d.config.brain.hidden = 9
	check(SimSnapshot.from_dict(d).error != "", "설정과 맞지 않는 유전체(은닉 수 변경) 거부")
	d = JSON.parse_string(text)
	d.format = "other"
	check(SimSnapshot.from_dict(d).error != "", "다른 형식 거부")
	check(SimSnapshot.from_text("{깨짐").error != "", "깨진 JSON 거부")
	check(SimSnapshot.hex_f64(SimSnapshot.f64_hex(0.1 + 0.2)) == 0.1 + 0.2 and SimSnapshot.hex_f64(SimSnapshot.f64_hex(1e-300)) == 1e-300, "실수 비트 왕복")
	done()


## 세계 변수 가운데 스냅숏에 담지 않는 것: 틱 안에서만 쓰는 계산 자리(다음 판단·번식·행동이 처음부터 다시 채움)와 화면 알림
## 대기열(_pending_events — 연대기는 저장되고, 알림은 연 뒤 새 사건부터). _pick_total 은 마지막 정책 뽑기의 가중치 합(그 판단의 고리 쓰기에만
## 씀 — DESIGN-v0.2 3.4). 나머지는 모두 왕복 뒤 값이 같아야 한다(test_snapshot_roundtrip).
const SNAPSHOT_SCRATCH: Array[String] = ["_in", "_hid", "_wts", "_out", "_bucket_head", "_bucket_next", "_mated", "csat", "_pending_events",
	"_pick_total"]


## SimWorld 스크립트 변수 이름들(with_scratch 가 거짓이면 SNAPSHOT_SCRATCH 를 뺌).
static func world_state_vars(wd: SimWorld, with_scratch: bool = false) -> Array[String]:
	var out: Array[String] = []
	for p in wd.get_script().get_script_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and (with_scratch or not SNAPSHOT_SCRATCH.has(str(p.name))):
			out.append(str(p.name))
	return out


## 두 세계에서 값이 다른 상태 변수 이름들(난수 생성기는 상태 글, 사전·배열은 정수·실수를 같게 보는 SimConfig.deep_equal 이나
## JSON 글 — 연대기의 평균 세대는 JSON 글로 왕복하므로 글이 같으면 같음).
static func world_vars_differ(a: SimWorld, b: SimWorld) -> Array[String]:
	var out: Array[String] = []
	for name in world_state_vars(a):
		var va = a.get(name)
		var vb = b.get(name)
		var same := false
		if va is SimRng and vb is SimRng:
			same = va.get_state_string() == vb.get_state_string()
		else:
			same = SimConfig.deep_equal(va, vb) or (typeof(va) == TYPE_ARRAY and JSON.stringify(va) == JSON.stringify(vb))
		if not same:
			out.append(name)
	return out


func test_snapshot_files() -> void:
	var dir := tmp_dir("test_snap")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("exp.json")
	var wd := world({}, 5)
	wd.step_n(100)
	check(SimSnapshot.save_file(wd, path) == "", "저장 성공")
	var h1 := wd.history_hash
	wd.step_n(100)
	check(SimSnapshot.save_file(wd, path) == "" and FileAccess.file_exists(path + ".bak"), "두 번째 저장 → 직전 정상본 .bak")
	var l1 := SimSnapshot.load_file(path)
	check(l1.status == "loaded" and l1.world != null and SimSnapshot.to_text(l1.world) == SimSnapshot.to_text(wd), "불러오기(전체 상태가 같음)")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"format\": \"slime-lab-snapshot\", 깨진 파일")
	f.close()
	var l2 := SimSnapshot.load_file(path)
	check(l2.status == "backup" and l2.world != null and l2.world.history_hash == h1, "깨진 본 파일 → 백업으로 복구")
	check(FileAccess.file_exists(path + ".broken"), "깨진 파일을 .broken 으로 보관")
	DirAccess.remove_absolute(path + ".bak")
	var l3 := SimSnapshot.load_file(path)
	check(l3.status == "failed" and l3.world == null, "백업도 없으면 실패를 알림")
	remove_tree(dir)
	check(not DirAccess.dir_exists_absolute(dir), "끝나면 임시 폴더를 지움(%s)" % dir)
	done()


func test_runner() -> void:
	var runner = load("res://tests/run_experiment.gd")
	var bad: Dictionary = runner.parse_args(PackedStringArray(["--seed=abc", "--out=x"]))
	check(bad.has("error"), "잘못된 씨앗 인자 거부")
	check(runner.parse_args(PackedStringArray(["--seed=1"])).has("error"), "--out 없으면 거부")
	check(runner.parse_args(PackedStringArray(["--out=x", "--모름"])).has("error"), "알 수 없는 인자 거부")
	var dir := tmp_dir("test_runner")
	var a: Dictionary = runner.parse_args(PackedStringArray(["--seed=3", "--generations=3", "--out=" + dir, "--quiet", "--set=mutation.rate=0.07"]))
	check(not a.has("error") and a.sets["mutation.rate"] == 0.07, "인자 해석")
	a.silent = true
	var code: int = runner.run(a)
	check(code == 0, "실행 성공 코드 0")
	for f in ["summary.json", "timeseries.csv", "chronicle.csv", "lineage.csv", "final.snapshot.json", ".gdignore"]:
		check(FileAccess.file_exists(dir.path_join(f)), "결과 파일 %s" % f)
	var ts := FileAccess.get_file_as_string(dir.path_join("timeseries.csv")).split("\n", false)
	check(ts.size() > 2 and ts[0] == ",".join(SimRecorder.TIMESERIES_COLUMNS), "시계열 열 이름·행 (%d행)" % ts.size())
	check(ts[1].split(",").size() == SimRecorder.TIMESERIES_COLUMNS.size(), "시계열 열 수")
	var lg := FileAccess.get_file_as_string(dir.path_join("lineage.csv")).split("\n", false)
	check(lg[0] == ",".join(SimRecorder.LINEAGE_COLUMNS) and lg.size() > 200, "계통 CSV")
	check(FileAccess.get_file_as_bytes(dir.path_join("chronicle.csv")).slice(0, 3) == PackedByteArray([0xEF, 0xBB, 0xBF]),
			"실행기 chronicle.csv 는 BOM 붙은 UTF-8(한국어 Windows 엑셀)")
	var sm = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("summary.json")))
	check(sm.end_reason == "generations" and sm.mean_generation >= 3.0 and sm.config.mutation.rate == 0.07, "요약: 끝난 이유·세대·실제 설정")
	check(int(sm.get("max_ticks", -1)) == int(sm.config.run.max_ticks), "요약: 실제로 쓴 틱 상한(max_ticks %s)" % str(sm.get("max_ticks")))
	# 열 목록(DESIGN-v0.2 9.5 — 분석 도구가 손 사본 대신 읽음)과 반사실 재생에서 바꾼 키(처음부터 돌리면 {})
	check(PackedStringArray(sm.get("timeseries_columns", [])) == PackedStringArray(SimRecorder.TIMESERIES_COLUMNS)
			and PackedStringArray(sm.get("lineage_columns", [])) == PackedStringArray(SimRecorder.LINEAGE_COLUMNS),
			"요약: timeseries_columns·lineage_columns = SimRecorder 의 열")
	check(typeof(sm.get("forked")) == TYPE_DICTIONARY and sm.forked.is_empty(), "요약: forked = {}(반사실 재생이 아님)")
	# features(DESIGN-v0.2 9.5): 켠 장치 스위치만(SimRecorder.FEATURE_SWITCHES 순서). 기본은 빔, 대조 설정(freeze·우연 기준)은 장치가 아님
	check(typeof(sm.get("features")) == TYPE_ARRAY and sm.features.is_empty() and sm.get("reset_learned") == false,
			"요약: features = [](기본 — 켠 장치 없음), reset_learned = false")
	var feats := {}
	for p in [["learn_basic", {}], ["learn_basic", {"learn.freeze": true}], ["chance_baseline", {"body.grow_enabled": true}],
			["default", {"learn.freeze": true, "learn.cost_per_eta": 0.5}]]:
		var fb := SimConfig.build(p[0], p[1])
		feats["%s %s" % [p[0], str(p[1])]] = ",".join(SimRecorder.features(fb.config)) if fb.error == "" else fb.error
	check(feats.values() == ["body.grow_enabled,learn.enabled", "body.grow_enabled,learn.enabled", "body.grow_enabled", ""],
			"features = 켠 장치 스위치(몸 자람 → 학습 순서, freeze·꺼진 장치의 키는 넣지 않음): %s" % str(feats))
	var bad_cfg: Dictionary = runner.parse_args(PackedStringArray(["--out=" + dir, "--set=없는.키=1", "--quiet"]))
	bad_cfg.silent = true
	check(runner.run(bad_cfg) == 2, "설정 오류 코드 2")
	# --fork-set(반사실 재생, DESIGN-v0.2 11.4): --resume 과만, 키=값 꼴, 값은 --set 과 같은 해석
	check(runner.parse_args(PackedStringArray(["--out=x", "--fork-set=mutation.rate=0.2"])).get("error", "").contains("--resume"),
			"--fork-set 은 --resume 없이 주면 인자 오류")
	check(runner.parse_args(PackedStringArray(["--out=x", "--resume=s.json", "--fork-set=mutation.rate"])).has("error"),
			"--fork-set 은 키=값 꼴")
	var fa: Dictionary = runner.parse_args(PackedStringArray(["--out=x", "--resume=s.json", "--fork-set=mutation.rate=0.2",
			"--fork-set=brain.policy=argmax"]))
	check(not fa.has("error") and fa.fork_sets == {"mutation.rate": 0.2, "brain.policy": "argmax"}, "--fork-set 해석(여러 번)")
	# fork_world: 바꾸지 않으면 같은 세계(스냅숏 글), 바꾼 키만 다르고 원래 세계는 그대로, 저장된 배열 길이를 바꾸는 키는 오류
	var fw := world({}, 3)
	fw.step_n(30)
	var fk0: Dictionary = runner.fork_world(fw, {})
	check(fk0.world != null and SimSnapshot.to_text(fk0.world) == SimSnapshot.to_text(fw), "fork_world 에 바꿀 키가 없으면 같은 세계")
	var fk1: Dictionary = runner.fork_world(fw, {"mutation.rate": 0.2})
	check(fk1.world != null and fk1.world.cfg.mutation.rate == 0.2 and fw.cfg.mutation.rate != 0.2 and fk1.world.tick == fw.tick
			and fk1.world.history_hash == fw.history_hash, "fork_world: 바꾼 키만(같은 틱·해시에서 갈라짐, 원래 세계 설정은 그대로)")
	for bad_key in [{"brain.hidden": 12}, {"없는.키": 1}, {"mutation.rate": -1}]:
		var fkb: Dictionary = runner.fork_world(fw, bad_key)
		check(fkb.world == null and str(fkb.error).begins_with("--fork-set"), "fork_world 거부 %s: %s" % [str(bad_key), str(fkb.error)])
	remove_tree(dir)
	check(not DirAccess.dir_exists_absolute(dir), "끝나면 임시 폴더를 지움(숨은 .gdignore 까지, %s)" % dir)
	done()


## 자원 0 → 멸종, 그 원인은 굶주림(I35). 시점만 보면 번식이 일찍 멈춘 세계는 굶주림 규칙이 없어도 늙어서 그 안에 사라진다
## (굶어 죽지 않게 한 변이: 234틱 멸종·굶주림 0·노화 250). 그래서 죽음의 대부분과 마지막 죽음이 굶주림인지도 본다
## (씨앗 1: 221틱 멸종, 굶주림 193·노화 73 — 노화는 처음부터 나이 든 개체).
func test_extinction_no_resources() -> void:
	var wd := world({}, 1, "no_resources")
	var limit := int(wd.cfg.life.max_age) + int(wd.cfg.life.max_age_jitter) + 10
	while not wd.is_extinct() and wd.tick < limit:
		wd.step()
	check(wd.is_extinct(), "자원 0 → %d틱 안에 멸종 (t=%d)" % [limit, wd.tick])
	check(wd.chronicle.size() > 0 and wd.chronicle[wd.chronicle.size() - 1].kind == "extinction", "연대기에 멸종 기록")
	var starved := 0
	var old := 0
	var last_starved := 0
	for id in wd.lin_cause.size():
		if wd.lin_cause[id] == SimWorld.CAUSE_STARVED:
			starved += 1
			if wd.lin_death[id] == wd.extinct_tick - 1:
				last_starved += 1
		elif wd.lin_cause[id] == SimWorld.CAUSE_OLD:
			old += 1
	check(starved > old and last_starved > 0 and starved + old == wd.lin_cause.size(),
			"자원 0 의 죽음은 대부분 굶주림, 마지막 틱의 죽음도 굶주림(굶주림 %d · 노화 %d, 마지막 틱 굶주림 %d)" % [starved, old, last_starved])
	done()


func test_memory_units() -> void:
	var wd := world({"brain.memory_units": 2}, 8)
	wd.step_n(300)
	var nonzero := false
	for v in wd.s_mem:
		if v != 0.0:
			nonzero = true
		if absf(v) >= 1.0:
			check(false, "기억 값은 softsign 범위 (-1, 1)")
	check(wd.s_mem.size() == wd.population() * 2, "기억 배열 길이 = 개체 × 2")
	check(nonzero, "기억 값이 갱신됨")
	done()


func test_performance() -> void:
	var wd := world({}, 2)
	wd.step_n(800)
	var g := PackedFloat32Array()
	g.resize(PERF_REF_LEN)
	var x := PackedFloat64Array()
	x.resize(PERF_REF_LEN)
	for k in PERF_REF_LEN:
		g[k] = float(k % 7) * 0.1
		x[k] = float(k % 5) * 0.2
	# 기준 일과 세계 진행을 번갈아(부하가 한쪽에만 걸리지 않게) 400틱
	var ticks_per_round := 50
	var ref_us := 0
	var step_us := 0
	var st := 0
	for r in PERF_ROUNDS:
		ref_us += _perf_ref_chunk(g, x)
		var t0 := Time.get_ticks_usec()
		for k in ticks_per_round:
			st += wd.population()
			wd.step()
		step_us += Time.get_ticks_usec() - t0
	var ticks := PERF_ROUNDS * ticks_per_round
	var us := float(step_us) / float(maxi(st, 1))
	var op_us := float(ref_us) / float(PERF_ROUNDS * PERF_REF_REPS * PERF_REF_LEN)
	var ratio := us / maxf(op_us, 1e-9)
	print("  성능: 평균 개체 %.0f, 개체·틱당 %.1fµs, %.0f틱/초 (기준 일 %.4fµs — 개체·틱당 기준 일 %.0f번)" % [float(st) / float(ticks), us,
			float(ticks) * 1e6 / float(maxi(step_us, 1)), op_us, ratio])
	check(st > 0 and ratio < PERF_MAX_RATIO, "개체·틱당 비용 = 기준 일 %.0f번 < %.0f번(실제 시계 %.1fµs 는 기록만)" % [ratio, PERF_MAX_RATIO, us])
	done()


## 상대 성능(DESIGN-v0.2 12.5): 같은 프로세스에서 두 세계(씨앗 PERF_REL_SEED, PERF_REL_WARMUP 틱 뒤)를 PERF_REL_CHUNK 틱씩 번갈아
## PERF_ROUNDS 바퀴(400틱씩) 돌려 개체·틱당 비용의 비(켬 ÷ 끔)를 잰다. 바퀴마다 먼저 도는 쪽을 바꿔 순서 치우침을 줄인다. 두 설정이
## 같으면 끔 세계는 켬 세계의 스냅숏 사본(데우기 한 번 — 같은 일을 하므로 비는 잡음만). 결과: {ratio, on_us, off_us, on_pop, off_pop}.
func perf_relative(on_sets: Dictionary, off_sets: Dictionary, preset: String = "default") -> Dictionary:
	var won := world(on_sets, PERF_REL_SEED, preset)
	won.step_n(PERF_REL_WARMUP)
	var woff: SimWorld
	if SimConfig.deep_equal(on_sets, off_sets):
		woff = SimSnapshot.from_text(SimSnapshot.to_text(won)).world
	else:
		woff = world(off_sets, PERF_REL_SEED, preset)
		woff.step_n(PERF_REL_WARMUP)
	var ws: Array[SimWorld] = [won, woff]
	var us := PackedInt64Array([0, 0])
	var st := PackedInt64Array([0, 0])
	for r in PERF_ROUNDS:
		for k in 2:
			var j := (k + r) % 2
			var w: SimWorld = ws[j]
			var t0 := Time.get_ticks_usec()
			for t in PERF_REL_CHUNK:
				st[j] += w.population()
				w.step()
			us[j] += Time.get_ticks_usec() - t0
	var on_us := float(us[0]) / float(maxi(st[0], 1))
	var off_us := float(us[1]) / float(maxi(st[1], 1))
	var ticks := float(PERF_ROUNDS * PERF_REL_CHUNK)
	return {ratio = on_us / maxf(off_us, 1e-9), on_us = on_us, off_us = off_us, on_pop = float(st[0]) / ticks, off_pop = float(st[1]) / ticks}


## 상대 성능 틀(DESIGN-v0.2 12.5·14.1 범위 8): 켬 = 끔(같은 기본 설정)이면 비는 잡음만 — [1 / 한도, 한도] 안이어야 한다.
## 1단계(14.2 검사 기준 15): 같은 함수로 켬(학습·몸 자람)·끔(기본)을 견주고 12.5 표의 1단계 한도(PERF_REL_STAGE1_MAX).
func test_performance_relative() -> void:
	var r := perf_relative({}, {})
	print("  상대 성능(켬 = 끔, 기본·씨앗 %d): 비 %.3f (켬 %.2fµs · 끔 %.2fµs, 평균 개체 %.0f·%.0f)" % [PERF_REL_SEED, r.ratio, r.on_us, r.off_us,
			r.on_pop, r.off_pop])
	check(r.on_pop > 0.0 and r.on_pop == r.off_pop and r.ratio <= PERF_REL_SAME_MAX and r.ratio >= 1.0 / PERF_REL_SAME_MAX,
			"켬 = 끔 세계의 개체·틱당 비용 비 %.3f 가 [1/%.2f, %.2f] 안(같은 일 — 평균 개체 %.0f)" % [r.ratio, PERF_REL_SAME_MAX, PERF_REL_SAME_MAX, r.on_pop])
	var r1 := perf_relative(PERF_REL_STAGE1_SETS, {})
	print("  상대 성능(1단계 학습·몸 자람 켬 ÷ 끔, 기본·씨앗 %d): 비 %.3f (켬 %.2fµs · 끔 %.2fµs — 차 %.2fµs, 평균 개체 %.0f·%.0f)" % [PERF_REL_SEED,
			r1.ratio, r1.on_us, r1.off_us, r1.on_us - r1.off_us, r1.on_pop, r1.off_pop])
	check(r1.on_pop > 0.0 and r1.off_pop > 0.0 and r1.ratio <= PERF_REL_STAGE1_MAX,
			"1단계 켬(학습·몸 자람) ÷ 끔의 개체·틱당 비용 비 %.3f ≤ %.2f(12.5 표의 1단계 한도 — 켬 %.2fµs · 끔 %.2fµs)" % [r1.ratio, PERF_REL_STAGE1_MAX,
			r1.on_us, r1.off_us])
	done()


## 기준 일 한 덩어리(PERF_REF_REPS × PERF_REF_LEN 번 곱셈·덧셈 + softsign — 두뇌 순전파 모양)에 걸린 µs.
func _perf_ref_chunk(g: PackedFloat32Array, x: PackedFloat64Array) -> int:
	var t0 := Time.get_ticks_usec()
	var s := 0.0
	for r in PERF_REF_REPS:
		for k in PERF_REF_LEN:
			s += g[k] * x[k]
		s = s / (1.0 + absf(s))
	var us := Time.get_ticks_usec() - t0
	return us if is_finite(s) else us + 1


func test_farm_reachable() -> void:
	if _skip_slow:
		check(true, "느린 검사 건너뜀")
		done()
		return
	# 연대기에서 채집 발견 사건의 평균 세대(-1 = 아직)
	var forage_gen := func(w: SimWorld) -> float:
		for e in w.chronicle:
			if str(e.kind) == "discovery" and int(e.get("stage", -1)) == SimWorld.STAGE_FORAGE:
				return float(e.mean_gen)
		return -1.0
	var fast_forage := {}
	var found := ""
	var tried := PackedStringArray()
	# fast_civ 첫 씨앗의 농사 시각(-1 = 평균 FARM_GENERATIONS 세대 안에 못 함). 위 반복이 가장 먼저 돌리는 조합이라 시간이 더 들지 않음
	var fast1_tick := -1
	var fast1_gen := -1.0
	for p in FARM_PRESETS:
		for sd in FARM_SEEDS:
			var wd := world({}, sd, p)
			while not wd.is_extinct() and wd.stage < SimWorld.STAGE_FARM and wd.mean_generation() < FARM_GENERATIONS:
				wd.step()
			tried.append("%s/씨앗%d: %s(평균 %.1f세대, t=%d)" % [p, sd, SimWorld.STAGE_NAMES[wd.stage], wd.mean_generation(), wd.tick])
			if p == "fast_civ":
				fast_forage[sd] = forage_gen.call(wd)
				if sd == FARM_SEEDS[0] and wd.stage == SimWorld.STAGE_FARM:
					fast1_tick = wd.discovery_tick[SimWorld.STAGE_FARM]
					fast1_gen = wd.mean_generation()
			if wd.stage == SimWorld.STAGE_FARM:
				found = tried[tried.size() - 1]
				break
		if found != "":
			break
	print("  농사 도달 시도: " + "; ".join(tried))
	check(found != "", "평균 %d세대 안에 농사에 도달하는 예설정이 있음: %s" % [int(FARM_GENERATIONS), found])
	if not FARM_PRESETS.has("fast_civ"):
		done()
		return
	# fast_civ 자체가 목표대로(S15 의 "아무 예설정" 과 따로 — demo_fast 가 농사해도 이것은 실패)
	check(fast1_tick >= 0 and fast1_gen < FARM_GENERATIONS, "fast_civ 씨앗 %d 이 평균 %d세대 안에 농사: %s" % [FARM_SEEDS[0],
			int(FARM_GENERATIONS), ("틱 %d·평균 %.1f세대" % [fast1_tick, fast1_gen]) if fast1_tick >= 0 else "못 함"])
	check(fast1_tick == FAST_CIV_SEED1_FARM_TICK and absf(fast1_gen - FAST_CIV_SEED1_FARM_GEN) < 0.05,
			"fast_civ 씨앗 %d 의 농사 시각이 문서 값과 같음(결정성): 틱 %d·평균 %.2f세대(문서 %d틱·%.1f세대)" % [FARM_SEEDS[0],
			fast1_tick, fast1_gen, FAST_CIV_SEED1_FARM_TICK, FAST_CIV_SEED1_FARM_GEN])
	# fast_civ: 채집이 첫 무작위 두뇌들의 행동으로 곧바로 열리지 않음(위에서 돌리지 않은 씨앗은 채집 발견까지만 진행)
	var gens := PackedStringArray()
	var all_late := true
	for sd in FARM_SEEDS:
		if not fast_forage.has(sd):
			var wf := world({}, sd, "fast_civ")
			while not wf.is_extinct() and wf.stage < SimWorld.STAGE_FORAGE and wf.mean_generation() < FARM_GENERATIONS:
				wf.step()
			fast_forage[sd] = forage_gen.call(wf)
		var g: float = fast_forage[sd]
		gens.append("씨앗%d %.2f" % [sd, g])
		if g < FAST_CIV_MIN_FORAGE_GEN:
			all_late = false
	check(all_late, "fast_civ 의 채집이 진화 도중에 열림(평균 세대 ≥ %.0f): %s" % [FAST_CIV_MIN_FORAGE_GEN, ", ".join(gens)])
	done()


## 틱 사이(step 뒤·처음·스냅숏을 연 뒤)의 빛·계절은 언제나 지금 tick 을 뜻한다
## (화면의 "날 9 · 봄" 과 기록 CSV 의 season·light 가 경계 틱에서 어긋나지 않게).
func test_time_after_step() -> void:
	var wd := world({"population.initial": 20})
	var day := int(wd.cfg.time.day_ticks)
	var sd := int(wd.cfg.time.season_days)
	var year := day * sd * SimWorld.SEASON_COUNT
	var probe := empty_world()
	var ok := true
	var rows_ok := true
	var bad := ""
	for k in year + 2:
		wd.step()
		probe.tick = wd.tick
		probe._compute_time()
		if wd.season != (wd.tick / day / sd) % SimWorld.SEASON_COUNT or wd.light != probe.light:
			ok = false
			bad = "틱 %d: 계절 %d 빛 %.2f" % [wd.tick, wd.season, wd.light]
		var row := wd.sample()
		if int(row.season) != (int(row.day) / sd) % SimWorld.SEASON_COUNT:
			rows_ok = false
	check(ok, "step 뒤 빛·계절 = 지금 틱의 값(한 해 %d틱) %s" % [year + 2, bad])
	check(rows_ok, "기록 줄(sample)의 계절이 날 열과 맞음")
	var w2 := world({"population.initial": 20})
	w2.step_n(year)
	check(w2.season == 0 and w2.tick == year, "한 해가 지난 경계 틱 %d 은 봄(계절 %d)" % [year, w2.season])
	var r := SimSnapshot.from_text(SimSnapshot.to_text(w2))
	var w3: SimWorld = r.world
	check(w3 != null and w3.season == w2.season and w3.light == w2.light, "스냅숏을 연 세계도 같은 빛·계절")
	done()


## drain_events() 가 돌려주는 사건은 연대기와 따로인 사본(받는 쪽이 고쳐 써도 연대기·기록이 그대로)
func test_event_copies() -> void:
	var wd := world({}, 1, "demo_fast")
	var guard := 0
	while wd.chronicle.is_empty() and guard < 5000:
		wd.step()
		guard += 1
	var ev := wd.drain_events()
	check(not ev.is_empty(), "사건이 생김(%d틱)" % wd.tick)
	if ev.is_empty():
		done()
		return
	var before := str(wd.chronicle[0].text)
	ev[0]["text"] = "바뀜"
	check(str(wd.chronicle[0].text) == before, "꺼낸 사건을 고쳐도 연대기는 그대로")
	done()


## 멸종 사건의 평균 세대 = 마지막 개체군(마지막 틱에 죽은 개체)의 평균 세대. 예전에는 개체가 모두 사라진 뒤에 재서
## 늘 0.0 이었다(연대기 창·chronicle.csv 가 "0.0세대 멸종"). 역사 해시는 연대기를 담지 않으므로 그대로.
func test_extinction_mean_gen() -> void:
	var sets := {"resources.scale": 0.5}
	var wd := world(sets, 1)
	var last := 0.0
	var births := 0
	while not wd.is_extinct() and wd.tick < 3000:
		last = wd.mean_generation()
		births = wd.total_births
		wd.step()
	check(wd.is_extinct() and wd.tick == wd.extinct_tick, "자원 절반·씨앗 1 → 멸종(t=%d)" % wd.tick)
	var ev: Dictionary = wd.chronicle.back() if not wd.chronicle.is_empty() else {}
	check(str(ev.get("kind", "")) == "extinction" and int(ev.get("tick", -1)) == wd.extinct_tick, "연대기 끝 = 멸종 사건")
	var s := 0
	var n := 0
	for id in wd.lin_death.size():
		if wd.lin_death[id] == wd.extinct_tick - 1:
			s += wd.lin_gen[id]
			n += 1
	var want := snappedf(float(s) / float(maxi(n, 1)), SimWorld.EVENT_GEN_STEP)
	var got := float(ev.get("mean_gen", -1.0))
	check(n > 0 and got > 0.0 and got == want, "멸종 사건의 평균 세대 %.2f = 마지막 틱에 죽은 %d마리의 평균 %.2f(0 아님)" % [got, n, want])
	check(wd.total_births == births and got == snappedf(last, SimWorld.EVENT_GEN_STEP),
			"마지막 틱에 출생 없음 → 멸종 직전(마지막으로 살아 있던 틱 끝)의 mean_generation() %.2f 와 같음" % last)
	var csv := SimRecorder.chronicle_csv(wd).split("\n", false)
	check(csv[csv.size() - 1].begins_with("%d,%s,extinction," % [wd.extinct_tick, SimRecorder.fmt(got)]), "chronicle.csv 멸종 줄에도 같은 값: " + csv[csv.size() - 1])
	# 상태를 따로 두지 않음: 멸종 한 틱 전에 저장한 스냅숏을 이어 돌려도 같은 사건·해시
	var w2 := world(sets, 1)
	w2.step_n(wd.extinct_tick - 1)
	var r := SimSnapshot.from_text(SimSnapshot.to_text(w2))
	var w3: SimWorld = r.world
	check(w3 != null, "멸종 한 틱 전 스냅숏 복원")
	if w3 == null:
		done()
		return
	w3.step()
	var e3: Dictionary = w3.chronicle.back() if not w3.chronicle.is_empty() else {}
	# 역사 해시는 hash.every 틱마다만 바뀌어 한 틱 이어 돌린 차이를 담지 못함(이 멸종은 548틱 — 547 → 548 사이에 검사점 없음) →
	# 해시가 아니라 전체 상태 글로 견줌(I89)
	check(w3.is_extinct() and str(e3.get("kind", "")) == "extinction" and float(e3.get("mean_gen", -1.0)) == got
			and SimSnapshot.to_text(w3) == SimSnapshot.to_text(wd),
			"스냅숏에서 이어 돌린 멸종 사건도 평균 %.2f세대 · 같은 전체 상태" % float(e3.get("mean_gen", -1.0)))
	# 번식 없이 사라진 세계(첫 세대뿐)는 0 이 맞음
	var w0 := world({}, 1, "no_resources")
	while not w0.is_extinct() and w0.tick < 3000:
		w0.step()
	check(w0.is_extinct() and float(w0.chronicle.back().mean_gen) == 0.0, "첫 세대만 살다 사라지면 평균 0세대")
	done()


# ───────────────────────── 설정 검사·파일(검토 고침 g1a) ─────────────────────────

## 이름표(sim-labels.json)의 범위가 모두 실제 검사(I01·I02·I03·I85·J01·I43). 규칙 표와 이름표가 같은지는 tools/test_sim_labels.py.
func test_config_rules() -> void:
	# 0 으로 나누는 키: 0 을 거부(I01). 감지 하한은 반올림해 1칸 이상이 되게 0.5 이상.
	var zero_ok: Array[String] = []
	for k in ["carry.max", "plants.max_food", "sense.crowd_norm", "store.capacity", "body.energy_per_size", "eat.bite",
			"eat.efficiency", "brain.weight_clamp", "discovery.store_threshold", "map.noise_cell", "map.noise_detail_cell",
			"map.rock_noise_cell"]:
		if SimConfig.build("default", {k: 0}).error == "":
			zero_ok.append(k)
	check(zero_ok.is_empty(), "0 나눗수 키에 0 을 거부(통과한 키: %s)" % ", ".join(zero_ok))
	check(SimConfig.build("default", {"traits.sense_min": 0.4, "traits.sense_init": 0.4}).error != "", "감지 반경 하한 0.5 미만 거부(반올림 0칸 → 낮에 0 으로 나눔)")
	# 허용되는 가장 작은 값들로도 두뇌 입력·출력에 NaN·무한이 없다
	var wmin := world({"carry.max": 1e-6, "plants.max_food": 1e-6, "sense.crowd_norm": 1e-6, "store.capacity": 1e-6,
			"traits.sense_min": 0.5, "traits.sense_init": 0.5, "eat.efficiency": 1e-6}, 1)
	wmin.step_n(30)
	var p := grass_spot(wmin)
	wmin.store_tiles.append(p.y * wmin.w + p.x)
	wmin.store_food.append(0.0)
	wmin._rebuild_stores()
	var bad_in := 0
	for light in [1.0, 0.0]:
		wmin.light = light
		for i in wmin.population():
			wmin._think(i, wmin.s_x[i], wmin.s_y[i], wmin.s_y[i] * wmin.w + wmin.s_x[i], wmin.s_head[i], wmin.s_emax[i])
			for v in wmin._in:
				if not is_finite(v):
					bad_in += 1
			for v in wmin._out:
				if not is_finite(v):
					bad_in += 1
	check(wmin.population() > 0 and bad_in == 0, "가장 작은 허용 값에서 두뇌 입력·출력 NaN 없음(낮·밤, 개체 %d, 유한하지 않은 값 %d)" % [wmin.population(), bad_in])
	# 모든 수 키: 범위 밖(하한 아래·상한 위, "0 초과" 면 하한 자체)과 정수 키의 소수를 거부하고 오류에 키 이름을 적음
	var ints := SimConfig.int_keys()
	var leaks: Array[String] = []
	for r in SimConfig.RULES:
		var key: String = r[0]
		var vals := [float(r[2]) + 1.0, float(r[1]) if (r.size() > 3 and r[3] == SimConfig.ABOVE) else float(r[1]) - 1.0]
		if ints.has(key):
			vals.append(float(r[1]) + 0.5)
		for v in vals:
			var e := str(SimConfig.build("default", {key: v}).error)
			if e == "" or not e.contains(key):
				leaks.append("%s=%s(%s)" % [key, str(v), e])
	check(leaks.is_empty(), "모든 수 키의 범위 밖·소수 값을 키 이름과 함께 거부(%d개 규칙, 샌 값: %s)" % [SimConfig.RULES.size(), ", ".join(leaks)])
	# 모든 잎 키가 규칙(수·배열·글자) 또는 참·거짓 종류 검사에 들어 있음
	var ruled := {}
	for r in SimConfig.RULES:
		ruled[r[0]] = true
	for r in SimConfig.ARRAY_RULES:
		ruled[r[0]] = true
	for k in SimConfig.CHOICES:
		ruled[k] = true
	var unruled: Array[String] = []
	var d := SimConfig.defaults()
	for sec in d:
		if typeof(d[sec]) == TYPE_DICTIONARY:
			for k in d[sec]:
				if typeof(d[sec][k]) != TYPE_BOOL and not ruled.has("%s.%s" % [sec, k]):
					unruled.append("%s.%s" % [sec, k])
	check(unruled.is_empty(), "규칙이 없는 잎 키 없음: " + ", ".join(unruled))
	check(ints.has("population.initial") and ints.has("map.width") and not ints.has("mutation.rate") and not ints.has("time.night_light_threshold"),
			"정수 키 = sim-defaults.json 에 소수점 없이 적힌 키")
	# 정수 키의 소수(I03): 잘라서 돌리고 기록에는 소수로 남던 값
	for kv in [["population.initial", 150.7], ["map.width", 40.9], ["brain.hidden", 8.5]]:
		check(SimConfig.build("default", {kv[0]: kv[1]}).error.contains("정수"), "정수 키 %s = %s 거부" % kv)
	check(SimConfig.build("default", {"population.initial": 150.0}).error == "", "정수 키에 소수점 붙은 정수(150.0)는 받음")
	# 부호(I03): 없는 데서 에너지가 생기던 음수
	for kv in [["metab.base", -1.0], ["eat.bite", -3.0], ["plants.regrow", -0.1], ["repro.cooldown", -5], ["dropped.sprout_food", -1.0]]:
		check(SimConfig.build("default", {kv[0]: kv[1]}).error != "", "%s = %s 거부" % kv)
	# 관계(I03): 해 뜨고 지는 시간 ≤ 낮 길이의 절반, 수명 흔들림 < 최대 나이
	check(SimConfig.build("default", {"time.twilight_ticks": 30}).error.contains("twilight"), "twilight 30 > 60 × 0.6 ÷ 2 거부(빛이 0.97 → 0.2 로 뛰던 값)")
	check(SimConfig.build("default", {"time.twilight_ticks": 18}).error == "", "twilight 18 = 60 × 0.6 ÷ 2 는 받음(경계)")
	var tw := world({"time.twilight_ticks": 18, "population.initial": 0})
	var jump := 0.0
	var prev := tw.light
	for k in int(tw.cfg.time.day_ticks):
		tw.step()
		jump = maxf(jump, absf(tw.light - prev))
		prev = tw.light
	check(jump <= 1.0 / 18.0 + 1e-9, "twilight 경계 값에서 빛이 한 틱에 1/18 넘게 뛰지 않음(최대 %.3f)" % jump)
	check(SimConfig.build("default", {"life.max_age_jitter": 500}).error.contains("max_age"), "수명 흔들림 500 ≥ 최대 나이 200 거부(0 이하 수명)")
	check(SimConfig.build("default", {"life.max_age_jitter": 199}).error == "", "수명 흔들림 199 < 200 은 받음")
	# 틱 단위 키 상한(J01): int32 배열에서 뒤집히던 값
	for k in ["life.max_age", "repro.cooldown", "dropped.spoil_ticks", "population.initial_age_spread", "farm.abandon_ticks", "run.max_ticks", "repro.maturity"]:
		check(SimConfig.build("default", {k: 3000000000}).error != "", "틱 단위 %s = 3e9 거부" % k)
	check(SimConfig.TICK_MAX * 2 < 2147483647, "최대 나이 + 흔들림(둘 다 TICK_MAX 까지)이 int32 안")
	var wl := world({"life.max_age": SimConfig.TICK_MAX, "life.max_age_jitter": SimConfig.TICK_MAX - 1, "repro.cooldown": SimConfig.TICK_MAX})
	var neg := 0
	for i in wl.population():
		if wl.s_max_age[i] <= 0 or wl.s_last_repro[i] > 0:
			neg += 1
	check(wl.population() > 0 and neg == 0, "상한 값에서도 수명·번식 틱이 뒤집히지 않음(뒤집힌 개체 %d)" % neg)
	# 고를 값(I85)
	check(SimConfig.CHOICES["brain.policy"] == [SimBrain.POLICY_SAMPLE, SimBrain.POLICY_ARGMAX], "brain.policy 고를 값 = SimBrain.POLICY_*")
	for bad in ["smaple", "Sample", "", " sample", "random"]:
		check(SimConfig.build("default", {"brain.policy": bad}).error.contains("brain.policy"), "brain.policy = \"%s\" 거부(말없이 argmax 로 돌던 값)" % bad)
	check(SimConfig.build("default", {"brain.policy": "argmax"}).error == "", "brain.policy = argmax 는 받음")
	for g in [[1.0, 1.0, 1.0, "a"], [1.0, 1.0, 1.0, -5.0], [1.0, 1.0, 1.0, null], [1.0, 1.0, 1.0, 101.0]]:
		check(SimConfig.build("default", {"seasons.growth": g}).error.contains("seasons.growth"), "seasons.growth = %s 거부" % str(g))
	check(SimConfig.parse_value("argmax") == "argmax" and SimConfig.parse_value("\"argmax\"") == "argmax", "명령줄 글자 값은 따옴표 없이도 글자")
	# 절 통째 덮어쓰기(I02): 모르는 키·빠진 키가 섞이지 않게 거부
	check(SimConfig.build("default", {"body": {"energy_per_size": 40.0}}).error.contains("절"), "절(body)에 사전을 넣으면 거부")
	var rep: Dictionary = SimConfig.defaults().repro
	rep["bogus_key"] = 1.0
	check(SimConfig.build("default", {"repro": rep}).error != "", "절(repro)에 모르는 키를 섞은 사전도 거부")
	var c_missing := SimConfig.defaults()
	(c_missing.body as Dictionary).erase("start_energy_frac")
	check(SimConfig.validate(c_missing).contains("body.start_energy_frac"), "빠진 잎 키를 validate 가 거부: " + SimConfig.validate(c_missing))
	var c_extra := SimConfig.defaults()
	c_extra.metab["bogus"] = 1.0
	check(SimConfig.validate(c_extra).contains("metab.bogus"), "모르는 잎 키를 validate 가 거부")
	var c_kind := SimConfig.defaults()
	c_kind.repro.asexual_when_alone = 1.0
	check(SimConfig.validate(c_kind) != "", "참·거짓 키에 수를 넣으면 validate 가 거부")
	var runner = load("res://tests/run_experiment.gd")
	var dir := tmp_dir("test_config_rules")
	var a: Dictionary = runner.parse_args(PackedStringArray(["--out=" + dir, "--quiet", "--set=body={\"energy_per_size\":40}"]))
	a.silent = true
	check(not a.has("error") and runner.run(a) == 2 and not FileAccess.file_exists(dir.path_join("summary.json")),
			"실행기 --set=body={…} → 설정 오류 코드 2, 결과 폴더 안 씀")
	for arg in ["--set=carry.max=0", "--set=population.initial=150.7", "--set=map.noise_cell=0", "--set=brain.policy=smaple",
			"--set=life.max_age=3000000000"]:
		var out := dir.path_join(arg.md5_text())
		var a2: Dictionary = runner.parse_args(PackedStringArray(["--out=" + out, "--quiet", "--max-ticks=50", arg]))
		a2.silent = true
		check(not a2.has("error") and runner.run(a2) == 2 and not FileAccess.file_exists(out.path_join("summary.json")), "실행기 %s → 설정 오류 코드 2" % arg)
	remove_tree(dir)
	# 오류 문장(I43): 정수 키는 정수로, 숫자 뒤 조사 없이
	var e1 := str(SimConfig.build("default", {"time.day_ticks": 1}).error)
	check(e1.contains("time.day_ticks = 1:") and not e1.contains("1.0") and not e1.contains(" 가 범위"), "범위 오류 문장: " + e1)
	var e2 := str(SimConfig.build("default", {"mutation.rate": 2.0}).error)
	check(e2.contains("mutation.rate = 2:") and e2.contains("0~1"), "실수 키 오류 문장: " + e2)
	# 64비트를 넘는 큰 수는 정수 키라도 적은 값 그대로(INT64_MIN 으로 바뀌지 않게 — 검토 최종 확인)
	for big: float in [1e20, -1e20]:
		var e3 := str(SimConfig.build("default", {"time.day_ticks": big}).error)
		check(e3.contains("time.day_ticks = %s:" % str(big)) and not e3.contains(str(-9223372036854775807 - 1)), "큰 수 오류 문장: " + e3)
	done()


## 예설정 파일을 읽지 못하면 경로를 담은 오류(J09) — '알 수 없는 예설정: default' 로 잘못 알리지 않게.
func test_presets_file() -> void:
	var dir := tmp_dir("test_presets")
	DirAccess.make_dir_recursive_absolute(dir)
	var broken := dir.path_join("presets.json")
	var f := FileAccess.open(broken, FileAccess.WRITE)
	f.store_string("{\"default\": 깨짐")
	f.close()
	for path in [dir.path_join("없음.json"), broken]:
		SimConfig._presets_path = path
		SimConfig._presets_cache = {}
		var e := str(SimConfig.build("default", {}).error)
		check(e.contains("예설정 파일") and e.contains(path), "예설정 파일을 읽지 못함 → 경로를 담은 오류: " + e)
		check(SimConfig.presets().is_empty(), "읽지 못한 예설정 목록은 빈 사전")
	SimConfig._presets_path = SimConfig.PRESETS_PATH
	SimConfig._presets_cache = {}
	check(SimConfig.build("default", {}).error == "" and SimConfig.preset_names().has("fast_civ"), "원래 파일로 돌리면 다시 읽음")
	check(SimConfig.build("", {}).error == "", "예설정 없이(빈 이름) 만들기는 예설정 파일과 상관없음")
	remove_tree(dir)
	done()


## 밤 판정 문턱(I77): 시뮬레이션 코드의 0.5 가 아니라 설정 time.night_light_threshold(기본 0.5 = 예전 역사 그대로).
func test_night_threshold() -> void:
	check(float(cfg_with().time.night_light_threshold) == 0.5, "기본 밤 문턱 0.5")
	var results := {}
	for th in [0.5, 0.9]:
		var wd := world({"time.night_light_threshold": th}, 4)
		wd.step_n(30)
		wd.light = 0.8
		var night_used := 0
		var differ := 0
		var wrong := 0
		for i in mini(wd.population(), 80):
			var x := wd.s_x[i]
			var y := wd.s_y[i]
			var hd := wd.s_head[i]
			wd._think(i, x, y, y * wd.w + x, hd, wd.s_emax[i])
			var rd := wd.s_sense[i]
			var rn := maxi(1, int(float(rd) * float(wd.cfg.sense.night_factor)))
			var qd := wd._quad(x, y, hd, 1, rd, -rd, rd)
			var qn := wd._quad(x, y, hd, 1, rn, -rn, rn)
			if qd != qn:
				differ += 1
			var want := qn if 0.8 < th else qd
			if wd._in[SimBrain.IN_FOOD_AHEAD] != want:
				wrong += 1
			elif want == qn and qd != qn:
				night_used += 1
		results[th] = [differ, wrong, night_used]
	check(results[0.5][0] > 0 and results[0.5][1] == 0, "문턱 0.5 · 빛 0.8 = 낮(감지 반경 그대로): %s" % str(results[0.5]))
	check(results[0.9][0] > 0 and results[0.9][1] == 0 and results[0.9][2] > 0, "문턱 0.9 · 빛 0.8 = 밤(감지 반경 × night_factor): %s" % str(results[0.9]))
	done()


## 잘게 갈라진 큰 지도에서도 연결 요소 계산이 칸 수에 비례(I31). 예전 계산(요소마다 거리장)은 192×192 바둑판에서 십수 초.
## 기준은 실제 시계가 아니라 같은 크기 풀밭을 한 번 훑는 거리장 시간의 배수(I34 — 예전 기준 "3,000ms 안"은 기계 속도 단언).
func test_components_fast() -> void:
	var n := 192
	var t := PackedByteArray()
	t.resize(n * n)
	var open := PackedByteArray()
	open.resize(n * n)
	open.fill(SimGrid.TILE_GRASS)
	for y in n:
		for x in n:
			t[y * n + x] = SimGrid.TILE_GRASS if (x + y) % 2 == 0 else SimGrid.TILE_ROCK
	var bfs_us := 1 << 30
	for k in 3:
		var tb := Time.get_ticks_usec()
		SimGrid.distance_field(open, n, n, PackedInt32Array([0]))
		bfs_us = mini(bfs_us, Time.get_ticks_usec() - tb)
	var t0 := Time.get_ticks_usec()
	var comp := SimGrid.components(t, n, n)
	var comp_us := Time.get_ticks_usec() - t0
	check(comp.sizes.size() == n * n / 2 and comp.labels[1] == -1 and comp.labels[2] == 1, "바둑판 %d×%d: 요소 %d개" % [n, n, comp.sizes.size()])
	var ratio := float(comp_us) / float(maxi(bfs_us, 1))
	check(ratio < COMPONENTS_MAX_RATIO, "연결 요소 계산 %.0fms = 풀밭 거리장 한 번(%.0fms)의 %.1f배 < %.0f배(요소 %d개 — 예전 계산은 요소 수 × 칸 수)" % [
			float(comp_us) / 1000.0, float(bfs_us) / 1000.0, ratio, COMPONENTS_MAX_RATIO, comp.sizes.size()])
	done()


## 구조가 틀린 스냅숏(JSON 은 정상)은 스크립트 오류 없이 오류 문장으로 거부하고, 본 파일이 그러면 .bak 으로 복구(I04).
## 옛 스냅숏(설정에 time.night_light_threshold 가 없음)은 기본값으로 채워 그대로 이어 돎.
func test_snapshot_corrupt() -> void:
	var wd := world({}, 21)
	wd.step_n(300)
	var p := grass_spot(wd)
	wd.store_tiles.append(p.y * wd.w + p.x)
	wd.store_food.append(12.5)
	wd._rebuild_stores()
	wd._put_dropped(p.y * wd.w + p.x + 1, 2.0)
	var text := SimSnapshot.to_text(wd)
	var big := SimSnapshot.b64(PackedInt32Array([0, 999999]))
	var dead_id := -1
	for id in wd.lin_death.size():
		if wd.lin_death[id] >= 0:
			dead_id = id
			break
	check(dead_id >= 0 and wd.population() > 0, "300틱 세계에 죽은 개체(#%d)와 산 개체가 있음(먹은 양 범위 사례용)" % dead_id)
	var cases := {
		"civ.discovery_tick 없음": func(d): d.civ.erase("discovery_tick"),
		"civ.discovery_tick 길이 1": func(d): d.civ.discovery_tick = [-1],
		"stats.led_initial 없음": func(d): d.stats.erase("led_initial"),
		"stats.led_eaten 16진 zz": func(d): d.stats.led_eaten = "zz",
		"civ.store_drops_total 짧은 16진": func(d): d.civ.store_drops_total = "0000",
		"stats.led_spent NaN": func(d): d.stats.led_spent = SimSnapshot.f64_hex(NAN),
		"map.drop_list 지도 밖": func(d): d.map.drop_list = big,
		"map.farms 지도 밖": func(d): d.map.farms = big,
		"civ.store_tiles 지도 밖": func(d): d.civ.store_tiles = big,
		"map.tiles 짧음": func(d): d.map.tiles = "AAAA",
		"map.food 없음": func(d): d.map.erase("food"),
		"slimes.genome 숫자": func(d): d.slimes.genome = 3,
		"lineage.pa 부모 id 가 자기보다 큼": func(d): d.lineage.pa = SimSnapshot.b64(PackedInt32Array(range(wd.lin_pa.size()))),
		"stats.total_births 글자": func(d): d.stats.total_births = "많이",
		"연대기 항목 text 없음": func(d): d.chronicle.append({tick = 1.0, kind = "milestone", actor = -1.0, mean_gen = 0.0}),
		"tick 없음": func(d): d.erase("tick"),
		"설정의 절 통째로 빠짐": func(d): d.config.erase("carry"),
		# 종류가 틀린 형식·난수 상태(검토 최종 확인 I04): 스크립트 오류로 검증을 건너뛰지 않고 그 이유로 거부
		"format 숫자": func(d): d.format = 1.0,
		"format 사전": func(d): d.format = {},
		"rng.world 숫자": func(d): d.rng.world = 5.0,
		"rng.life 배열": func(d): d.rng.life = [1],
		"rng.world null": func(d): d.rng.world = null,
		# v0.2 에서 더한 키(DESIGN-v0.2 9.1): 없으면 채우지만, 있으면 꼴·길이·범위를 검사
		"slimes.last_eff 길이 1": func(d): d.slimes.last_eff = SimSnapshot.b64(PackedByteArray([1])),
		"slimes.last_eff 값 2": func(d): d.slimes.last_eff = SimSnapshot.b64(_filled_bytes(wd.population(), 2)),
		"slimes.eaten 숫자": func(d): d.slimes.eaten = 3.0,
		"lineage.eaten 짧음": func(d): d.lineage.eaten = SimSnapshot.b64(PackedFloat64Array([1.0])),
		"lineage.eaten NaN": func(d): d.lineage.eaten = SimSnapshot.b64(_nan_tail(wd.lin_pa.size())),
		"stats.period_act 길이 7": func(d): d.stats.period_act = SimSnapshot.b64(PackedInt64Array([0, 0, 0, 0, 0, 0, 0])),
		"stats.period_eff > period_act": func(d): d.stats.period_eff = SimSnapshot.b64(PackedInt64Array([999999, 0, 0, 0, 0, 0, 0, 0])),
		"stats.led_eaten_open 짧은 16진": func(d): d.stats.led_eaten_open = "00",
		"stats.led_eaten_open NaN": func(d): d.stats.led_eaten_open = SimSnapshot.f64_hex(NAN),
		# 범위(검증 지적): 먹은 양은 음수가 아니고, 살아 있는 개체의 계통 값은 0(죽을 때 씀), 장부 시작점은 0~led_eaten, 첫 개체 id 는 계통 안
		"slimes.eaten 음수": func(d): d.slimes.eaten = _f64_set(wd.s_eaten, 0, -1e6),
		"lineage.eaten 음수(죽은 개체)": func(d): d.lineage.eaten = _f64_set(wd.lin_eaten, dead_id, -5.0),
		"lineage.eaten 살아 있는 개체 ≠ 0": func(d): d.lineage.eaten = _f64_set(wd.lin_eaten, wd.s_id[0], 1.0),
		"stats.led_eaten_open > led_eaten": func(d): d.stats.led_eaten_open = SimSnapshot.f64_hex(wd.led_eaten + 1.0),
		"stats.led_eaten_open 음수": func(d): d.stats.led_eaten_open = SimSnapshot.f64_hex(-1.0),
		"stats.eaten_from_id 계통 밖": func(d): d.stats.eaten_from_id = float(wd.lin_pa.size() + 1),
		"stats.eaten_from_id 음수": func(d): d.stats.eaten_from_id = -1.0,
		"stats.eaten_from_id 글자": func(d): d.stats.eaten_from_id = "0",
	}
	var reason := {"format 숫자": "형식", "format 사전": "형식", "rng.world 숫자": "rng.world", "rng.life 배열": "rng.life", "rng.world null": "rng.world",
		"stats.period_act 길이 7": "행동 셈", "stats.period_eff > period_act": "행동 셈",
		"slimes.eaten 음수": "음수", "lineage.eaten 음수(죽은 개체)": "음수", "lineage.eaten 살아 있는 개체 ≠ 0": "살아 있는",
		"stats.led_eaten_open > led_eaten": "시작점", "stats.led_eaten_open 음수": "시작점",
		"stats.eaten_from_id 계통 밖": "eaten_from_id", "stats.eaten_from_id 음수": "eaten_from_id", "stats.eaten_from_id 글자": "eaten_from_id"}
	var leaked: Array[String] = []
	for name: String in cases:
		var d = JSON.parse_string(text)
		cases[name].call(d)
		var r = SimSnapshot.from_dict(d)
		if typeof(r) != TYPE_DICTIONARY or r.get("world") != null or str(r.get("error", "")) == "":
			leaked.append(name)
		elif reason.has(name) and not str(r.error).contains(reason[name]):
			leaked.append("%s(이유 '%s')" % [name, str(r.error)])
	check(leaked.is_empty(), "구조가 틀린 스냅숏 %d종을 오류 문장으로 거부(샌 것: %s)" % [cases.size(), ", ".join(leaked)])
	var ok := SimSnapshot.from_text(text)
	check(ok.error == "" and SimSnapshot.to_text(ok.world) == text, "멀쩡한 스냅숏은 그대로 왕복")
	# 하위 키 하나가 빠진 본 파일 + 정상 .bak → 백업으로 복구, 본 파일은 .broken
	var dir := tmp_dir("test_snap_corrupt")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("exp.json")
	check(SimSnapshot.save_file(wd, path) == "", "저장")
	var h1 := wd.history_hash
	wd.step_n(50)
	check(SimSnapshot.save_file(wd, path) == "" and FileAccess.file_exists(path + ".bak"), "두 번째 저장 → .bak")
	var dd = JSON.parse_string(FileAccess.get_file_as_string(path))
	dd.civ.erase("discovery_tick")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(dd))
	f.close()
	var l := SimSnapshot.load_file(path)
	check(str(l.get("status", "")) == "backup" and l.get("world") != null and l.world.history_hash == h1 and str(l.get("error", "")).contains("discovery_tick"),
			"하위 키가 빠진 본 파일 → .bak 으로 복구(status %s, %s)" % [str(l.get("status", "")), str(l.get("error", ""))])
	check(FileAccess.file_exists(path + ".broken"), "구조가 틀린 본 파일을 .broken 으로 보관")
	remove_tree(dir)
	# 옛 스냅숏: 설정에 나중에 더한 키가 없음 → 기본값으로 채우고 이어 돌린 역사가 같음
	var w2 := world({}, 6)
	w2.step_n(200)
	var od = JSON.parse_string(SimSnapshot.to_text(w2))
	od.config.time.erase("night_light_threshold")
	var ro := SimSnapshot.from_dict(od)
	check(ro.error == "" and ro.world != null and float(ro.world.cfg.time.night_light_threshold) == 0.5, "설정에 밤 문턱이 없는 옛 스냅숏 → 기본값 0.5 로 엶: " + str(ro.error))
	if ro.world != null:
		w2.step_n(150)
		ro.world.step_n(150)
		check(ro.world.history_hash == w2.history_hash, "옛 스냅숏에서 이어 돌린 해시 = 끊김 없이 돌린 해시")
	done()


static func _filled_bytes(n: int, v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	b.fill(v)
	return b


## 실수 배열 사본의 i 번째를 v 로 바꾼 base64(스냅숏 값).
static func _f64_set(arr: PackedFloat64Array, i: int, v: float) -> String:
	var a := arr.duplicate()
	a[i] = v
	return SimSnapshot.b64(a)


## 길이 n 의 실수 배열(마지막만 NaN).
static func _nan_tail(n: int) -> PackedFloat64Array:
	var a := PackedFloat64Array()
	a.resize(n)
	a[n - 1] = NAN
	return a


## 결과 파일의 틱 기준(DESIGN 8.4 "틱 기준" — 검토 J26): 매 틱 기록한 시계열을 계통 기록으로 다시 세고, 사건의 tick·mean_gen 이
## 어느 상태인지 본다. 개체는 birth < t ≤ death 인 줄 t 에(초기 개체는 0 ≤ t), 줄의 출생·사망 = 틱 번호가 [앞 줄, t) 인 개체,
## 채집·농사 발견의 mean_gen = 틱 T+1 상태, 저장 발견·저장고 = 틱 T 상태, 이정표 = 적힌 틱(진행한 뒤 틱)의 상태.
func test_tick_basis() -> void:
	var wd := world({"record.every": 1, "record.generation_milestone": 1}, 2, "fast_civ")
	var rec := SimRecorder.new()
	rec.record(wd)
	while wd.discovery_tick[SimWorld.STAGE_FARM] < 0 and wd.tick < int(wd.cfg.run.max_ticks) and not wd.is_extinct():
		wd.step()
		rec.record(wd)
	wd.step()
	rec.record(wd)
	var rows := rec.rows
	check(wd.discovery_tick[SimWorld.STAGE_FARM] >= 0 and int(rows.back().tick) == rows.size() - 1, "농사 발견까지 매 틱 기록(%d줄)" % rows.size())
	var n := rows.size()
	var pop := PackedInt32Array()
	var births := PackedInt32Array()
	var deaths := PackedInt32Array()
	pop.resize(n)
	births.resize(n)
	deaths.resize(n)
	for i in wd.lin_birth.size():
		var initial := wd.lin_pa[i] < 0 and wd.lin_pb[i] < 0
		var b := wd.lin_birth[i]
		var d := wd.lin_death[i] if wd.lin_death[i] >= 0 else n
		for t in range(b if initial else b + 1, mini(d + 1, n)):
			pop[t] += 1
		if not initial and b + 1 < n:
			births[b + 1] += 1
		if wd.lin_death[i] >= 0 and d + 1 < n:
			deaths[d + 1] += 1
	var bad := PackedStringArray()
	for t in n:
		var r: Dictionary = rows[t]
		if int(r.population) != pop[t] or (t > 0 and (int(r.births) != births[t] or int(r.deaths) != deaths[t])):
			bad.append("줄 %d: 개체 %d/%d 출생 %d/%d 사망 %d/%d" % [t, r.population, pop[t], r.births, births[t], r.deaths, deaths[t]])
	check(bad.is_empty(), "계통 기록(birth < t ≤ death, 초기 개체 0 ≤ t)으로 다시 센 개체·출생·사망 = 시계열(%d줄, 어긋난 줄 %d: %s)"
			% [n, bad.size(), ", ".join(bad.slice(0, 3))])
	var gen_at := func(t: int) -> float: return snappedf(float(rows[t].mean_gen), SimWorld.EVENT_GEN_STEP)
	var seen := {}
	var wrong := PackedStringArray()
	for e in wd.chronicle:
		var t := int(e.tick)
		var want := -1
		match str(e.kind):
			"discovery":
				want = t if int(e.stage) == SimWorld.STAGE_STORE else t + 1
			"store_built", "first_farm":
				want = t
			"milestone":
				want = t
		if want < 0 or want >= n:
			continue
		seen[str(e.kind)] = true
		if not is_equal_approx(float(e.mean_gen), gen_at.call(want)):
			wrong.append("%s(틱 %d) %.2f ≠ 줄 %d 의 %.2f" % [e.kind, t, float(e.mean_gen), want, gen_at.call(want)])
	check(seen.has("discovery") and seen.has("store_built") and seen.has("milestone") and wrong.is_empty(),
			"연대기 mean_gen 의 기준(채집·농사 T+1, 저장·저장고·첫 밭 T, 이정표 = 적힌 틱): 본 종류 %s, 어긋난 것 %s" % [seen.keys(), wrong])
	done()


## 기록기·스냅숏 파일 쓰기(J07·I07·I19·J10): CSV 는 BOM 붙은 UTF-8, summary.json 은 CSV 를 다 쓴 뒤 마지막(못 쓰면 안 씀),
## 검증에 실패한 스냅숏 임시 파일은 지우고 실패 문장에 파일 이름.
func test_recorder_files() -> void:
	var wd := world({}, 2, "demo_fast")
	var rec := SimRecorder.new()
	for k in 3:
		wd.step_n(20)
		rec.record(wd)
	var dir := tmp_dir("test_recorder")
	check(rec.write_all(dir, wd, {end_reason = "test"}).is_empty(), "결과 폴더 쓰기 성공")
	var bom := PackedByteArray([0xEF, 0xBB, 0xBF])
	for fn in ["timeseries.csv", "chronicle.csv", "lineage.csv"]:
		var b := FileAccess.get_file_as_bytes(dir.path_join(fn))
		check(b.size() > 3 and b.slice(0, 3) == bom, "%s 는 BOM(EF BB BF) 붙은 UTF-8" % fn)
	var ts := FileAccess.get_file_as_bytes(dir.path_join("timeseries.csv"))
	check(ts.slice(3).get_string_from_utf8() == rec.timeseries_csv(), "BOM 뒤 내용 = timeseries_csv()(BOM 은 파일에만)")
	var sb := FileAccess.get_file_as_bytes(dir.path_join("summary.json"))
	check(sb.size() > 0 and sb[0] == "{".unicode_at(0) and typeof(JSON.parse_string(sb.get_string_from_utf8())) == TYPE_DICTIONARY, "summary.json 은 BOM 없는 JSON")
	check(not FileAccess.file_exists(dir.path_join("summary.json.tmp")), "summary.json 임시 파일이 남지 않음")
	# CSV 하나를 못 쓰면 summary.json 을 쓰지 않고 앞선 것도 지움(summary.json 이 있으면 CSV 도 다 쓰인 것)
	DirAccess.remove_absolute(dir.path_join("chronicle.csv"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("chronicle.csv"))
	var failed := rec.write_all(dir, wd, {end_reason = "test"})
	check(failed.has("chronicle.csv") and not FileAccess.file_exists(dir.path_join("summary.json")),
			"chronicle.csv 를 못 쓰면 summary.json 이 없음(실패 목록 %s)" % ", ".join(failed))
	check(" ".join(failed).contains("summary.json"), "실패 목록에 summary.json 을 쓰지 않았다는 줄")
	# 쓴 길이 확인: 다 쓰인 파일만 성공
	var probe := dir.path_join("probe.txt")
	check(SimRecorder.write_text(probe, "가나다", true) and FileAccess.get_file_as_bytes(probe).size() == 3 + "가나다".to_utf8_buffer().size(), "write_text: BOM + 글")
	check(not SimRecorder.write_text(dir.path_join("chronicle.csv"), "x"), "열 수 없는 자리(폴더)에 쓰기 → 실패")
	remove_tree(dir)
	# 스냅숏: 검증에 실패하면 임시 파일을 지우고, 실패 문장에 파일 이름(반환값을 버려도 로그에 push_error)
	var sdir := tmp_dir("test_snap_fail")
	DirAccess.make_dir_recursive_absolute(sdir)
	var path := sdir.path_join("snapshot-20.json")
	var bad := world({}, 3)
	bad.step_n(5)
	bad.s_energy[0] = NAN
	var e1 := SimSnapshot.save_file(bad, path)
	check(e1 != "" and e1.contains("snapshot-20.json") and not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path),
			"검증 실패 → 임시 파일을 지우고 파일 이름을 담은 실패 문장: " + e1)
	DirAccess.make_dir_recursive_absolute(path + ".tmp")
	var e2 := SimSnapshot.save_file(wd, path)
	check(e2 != "" and e2.contains("snapshot-20.json.tmp"), "임시 파일을 열 수 없음 → 파일 이름을 담은 실패 문장: " + e2)
	remove_tree(sdir)
	done()


# ───────────────────────── 규칙 고침(검토 고침 g1b) ─────────────────────────

## 처음부터 개체가 없는 세계(I08): setup 이 틱 0 멸종·멸종 사건을 남겨, 실행기(틱 0 에서 끝남)와 실험실(Experiment)의
## timeseries·chronicle 이 글자까지 같다. 예전: 실행기는 extinct_tick −1·빈 연대기, 실험실은 한 틱 더 돌아 틱 1 멸종·2줄.
func test_empty_start() -> void:
	for sets in [{"population.initial": 0}, {"map.water_level": 1.0}]:
		var wd := world(sets)
		var ev: Dictionary = wd.chronicle.back() if not wd.chronicle.is_empty() else {}
		check(wd.is_extinct() and wd.extinct_tick == 0 and wd.chronicle.size() == 1 and str(ev.get("kind", "")) == "extinction"
				and int(ev.get("tick", -1)) == 0, "처음부터 개체 0(%s) → 틱 0 멸종·멸종 사건 하나(extinct_tick %d, 사건 %d개)" % [
				str(sets), wd.extinct_tick, wd.chronicle.size()])
		wd.step_n(3)
		check(wd.extinct_tick == 0 and wd.chronicle.size() == 1, "빈 세계를 더 돌려도 멸종 틱 0·사건 하나 그대로")
	var runner = load("res://tests/run_experiment.gd")
	var dir := tmp_dir("test_empty_start")
	var a: Dictionary = runner.parse_args(PackedStringArray(["--out=" + dir.path_join("runner"), "--quiet", "--seed=1", "--set=population.initial=0"]))
	a.silent = true
	check(not a.has("error") and runner.run(a) == 0, "실행기: 개체 0 실험도 결과를 씀")
	var sm = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("runner/summary.json")))
	check(typeof(sm) == TYPE_DICTIONARY and sm.end_reason == "extinction" and int(sm.extinct_tick) == 0 and int(sm.tick) == 0,
			"실행기 요약: 끝난 이유 extinction 과 멸종 틱 0 이 맞음(예전 extinct_tick −1): %s" % str(sm.get("extinct_tick") if typeof(sm) == TYPE_DICTIONARY else sm))
	var r := Experiment.create("default", {"population.initial": 0}, 1)
	var x: Experiment = r.experiment
	check(x != null, "실험실 실험 만들기: " + str(r.error))
	if x == null:
		done()
		return
	x.step_n(5)
	check(x.export_dir(dir.path_join("lab")).is_empty(), "실험실 결과 내보내기")
	for fn in ["timeseries.csv", "chronicle.csv"]:
		var lab_b := FileAccess.get_file_as_bytes(dir.path_join("lab").path_join(fn))
		var run_b := FileAccess.get_file_as_bytes(dir.path_join("runner").path_join(fn))
		check(lab_b.size() > 3 and lab_b == run_b, "개체 0 실험의 %s: 실험실 = 실행기(글자까지, %d줄 / %d줄)" % [fn,
				lab_b.get_string_from_utf8().split("\n", false).size(), run_b.get_string_from_utf8().split("\n", false).size()])
	remove_tree(dir)
	done()


## 쿨다운 0 이어도 한 틱에 한 번만 짝지음(I24). 예전: 같은 칸 세 마리에서 한 번의 _reproduce 로 자식 3(개체 a 가 세 번).
func test_mate_once_per_tick() -> void:
	var wd := empty_world({"repro.cooldown": 0, "mutation.rate": 0.0})
	var p := grass_spot(wd)
	for k in 3:
		add_slime(wd, p, 0.9, 100)
	wd.s_dead.fill(0)
	wd._reproduce()
	check(wd.population() == 4 and wd.lin_children[0] == 1 and wd.lin_children[1] == 1 and wd.lin_children[2] == 0,
			"쿨다운 0 · 같은 칸 세 마리 → 자식 하나(부모마다 자식 %d·%d·%d)" % [wd.lin_children[0], wd.lin_children[1], wd.lin_children[2]])
	# 일반 흐름: 기본·씨앗 1·쿨다운 0 으로 600틱 — 같은 틱에 두 번 짝지은 부모가 없음(예전 61번)
	var w2 := world({"repro.cooldown": 0}, 1)
	w2.step_n(600)
	var seen := {}
	var twice := 0
	for id in w2.lin_pa.size():
		for par in [w2.lin_pa[id], w2.lin_pb[id]]:
			if par == SimWorld.NO_PARENT:
				continue
			var key := "%d@%d" % [par, w2.lin_birth[id]]
			if seen.has(key):
				twice += 1
			seen[key] = true
	check(w2.total_births > 0 and twice == 0, "기본·쿨다운 0·600틱: 한 틱에 두 번 짝지은 부모 %d번(출생 %d)" % [twice, w2.total_births])
	done()


## 저장고 최대 수에는 저장 발견 때 짓는 첫 저장고도 든다(I25): 0 은 거부(예전엔 0 이어도 1개 — 1 과 같은 역사), 1 이면 그 하나뿐.
func test_store_max_count() -> void:
	check(SimConfig.build("default", {"store.max_count": 0}).error.contains("store.max_count"), "저장고 최대 수 0 거부: " + str(SimConfig.build("default", {"store.max_count": 0}).error))
	check(SimConfig.build("default", {"store.max_count": 1}).error == "", "저장고 최대 수 1 은 받음")
	var wd := empty_world({"store.max_count": 1, "store.min_spacing": 0})
	var p := grass_spot(wd)
	var id := add_slime(wd, p)
	var i := wd.index_of_id(id)
	wd.stage = SimWorld.STAGE_FORAGE
	var thr := float(wd.cfg.discovery.store_threshold)
	wd.s_carry[i] = thr
	wd._drop(i, p.y * wd.w + p.x)
	var far := other_region_grass(wd, p)
	for k in 3:
		wd.s_carry[i] = thr
		wd._drop(i, far)
	check(wd.stage == SimWorld.STAGE_STORE and wd.store_tiles.size() == 1, "최대 수 1: 저장 발견 때의 저장고 하나뿐(지금 %d개)" % wd.store_tiles.size())
	done()


## '첫 밭' 사건은 세계에서 한 번(I26): 밭을 모두 잃고 다시 심어도 다시 나오지 않음. 첫 밭 틱은 스냅숏에 담기고, 그 키가 없는
## 옛 스냅숏은 연대기에서 다시 만든다.
func test_first_farm_once() -> void:
	var wd := empty_world()
	var p := grass_spot(wd)
	var c := p.y * wd.w + p.x
	wd.store_tiles.append(c)
	wd.store_food.append(0.0)
	wd._rebuild_stores()
	wd.stage = SimWorld.STAGE_FARM
	var id := add_slime(wd, p + Vector2i(0, 1), 0.9, 100, 1)
	var i := wd.index_of_id(id)
	wd.s_carry[i] = 3.0
	wd.s_last_action[i] = SimBrain.ACT_PLANT
	wd._think_every = 1000000
	wd.tick = 1
	wd._act_all()
	var tc := (p.y + 1) * wd.w + p.x + 1
	check(wd.tiles[tc] == SimGrid.TILE_FARM and wd.first_farm_tick == 1, "심기 → 첫 밭 틱 %d" % wd.first_farm_tick)
	var count_ff := func(w: SimWorld) -> int:
		var n := 0
		for e in w.chronicle:
			if str(e.kind) == "first_farm":
				n += 1
		return n
	# 스냅숏 왕복·옛 스냅숏(키 없음 → 연대기에서)
	var text := SimSnapshot.to_text(wd)
	var r1 := SimSnapshot.from_text(text)
	var od = JSON.parse_string(text)
	od.civ.erase("first_farm_tick")
	var r2 := SimSnapshot.from_dict(od)
	check(r1.world != null and r1.world.first_farm_tick == 1 and r2.world != null and r2.world.first_farm_tick == 1,
			"첫 밭 틱이 스냅숏 왕복(키가 없는 옛 스냅숏은 연대기에서 %s)" % str(r2.world.first_farm_tick if r2.world != null else r2.error))
	var bad = JSON.parse_string(text)
	bad.civ.first_farm_tick = "x"
	check(SimSnapshot.from_dict(bad).error.contains("first_farm_tick"), "첫 밭 틱이 정수가 아닌 스냅숏 거부")
	for w: SimWorld in [wd, r1.world, r2.world]:
		var k := w.index_of_id(id)
		w.tick = w.farm_visit[tc] + int(w.cfg.farm.abandon_ticks) + 1
		w._abandon_farms()
		var lost := w.farms.is_empty() and w.tiles[tc] == SimGrid.TILE_GRASS
		w.s_carry[k] = 3.0
		w.s_last_action[k] = SimBrain.ACT_PLANT
		w._think_every = 1000000
		w._act_all()
		check(lost and w.tiles[tc] == SimGrid.TILE_FARM and count_ff.call(w) == 1 and w.first_farm_tick == 1,
				"밭을 모두 잃고(%s) 다시 심어도 '첫 밭' 사건은 한 번(%d번)" % [str(lost), count_ff.call(w)])
	done()


## 저장고를 지은 칸의 바닥 먹이 더미는 저장분으로(I27) — 예전엔 dropped 에 남아 그 칸의 입력(발밑 먹이)·먹기에 안 잡힌 채 썩음.
## 저장고 칸에서 죽은 개체의 운반분도 저장분으로(용량까지, 남는 몫만 바닥).
func test_store_takes_pile() -> void:
	var wd := empty_world()
	var p := grass_spot(wd)
	var c := p.y * wd.w + p.x
	var id := add_slime(wd, p)
	var i := wd.index_of_id(id)
	wd.stage = SimWorld.STAGE_FORAGE
	var thr := float(wd.cfg.discovery.store_threshold)
	var cap := float(wd.cfg.store.capacity)
	wd.s_carry[i] = thr + 10.0
	wd._drop(i, c)
	check(wd.store_tiles.size() == 1 and wd.store_tiles[0] == c and wd.store_food[0] == thr + 10.0 and wd.dropped[c] == 0.0,
			"저장고를 짓는 칸의 더미 %.0f → 저장분 %.1f, 바닥 %.1f" % [thr + 10.0, wd.store_food[0] if not wd.store_food.is_empty() else -1.0, wd.dropped[c]])
	wd._think(i, p.x, p.y, c, wd.s_head[i], wd.s_emax[i])
	check(wd._in[SimBrain.IN_FOOD_HERE] == (thr + 10.0) / cap, "저장고 칸의 발밑 먹이 입력이 그 먹이를 봄(%.3f)" % wd._in[SimBrain.IN_FOOD_HERE])
	wd.s_energy[i] = 1.0
	wd._eat(i, c, wd.s_size[i], wd.s_emax[i])
	check(wd.s_energy[i] > 1.0 and wd.store_food[0] < thr + 10.0, "저장고 칸에서 그 먹이를 먹을 수 있음")
	# 용량을 넘는 더미: 용량까지만 저장분, 넘친 몫은 바닥
	var w2 := empty_world()
	var q := grass_spot(w2)
	var qc := q.y * w2.w + q.x
	var i2 := w2.index_of_id(add_slime(w2, q))
	w2.stage = SimWorld.STAGE_FORAGE
	w2.s_carry[i2] = cap + 50.0
	w2._drop(i2, qc)
	check(w2.store_food.size() == 1 and w2.store_food[0] == cap and w2.dropped[qc] == 50.0, "용량을 넘는 더미는 용량까지 저장분, 넘친 50 은 바닥")
	# 저장고 칸에서 죽은 개체의 운반분
	var w3 := empty_world()
	var s := grass_spot(w3)
	var sc := s.y * w3.w + s.x
	w3.store_tiles.append(sc)
	w3.store_food.append(cap - 2.0)
	w3._rebuild_stores()
	var i3 := w3.index_of_id(add_slime(w3, s))
	w3.s_carry[i3] = 5.0
	w3.s_dead[i3] = SimWorld.CAUSE_STARVED
	w3._remove_dead()
	check(w3.store_food[0] == cap and w3.dropped[sc] == 3.0, "저장고 칸에서 죽은 개체의 운반분 5 → 저장분이 용량까지(+2), 남은 3 은 바닥")
	done()


## 저장고 칸의 풀(규칙 — DESIGN 6절 "저장고 칸의 풀", 검토 최종 확인에서 고치지 않고 규칙으로 둠): 풀은 그 칸에서도 자라지만
## 그 칸의 입력(발밑 먹이)·먹기는 저장분만 보고, 풀은 줍기로만 꺼낸다. 이 규칙을 바꾸면 저장고가 생긴 뒤의 모든 역사가 바뀐다.
func test_store_tile_plants() -> void:
	var wd := empty_world()
	var p := grass_spot(wd)
	var c := p.y * wd.w + p.x
	var i := wd.index_of_id(add_slime(wd, p))
	wd.store_tiles.append(c)
	wd.store_food.append(0.0)
	wd._rebuild_stores()
	check(wd.grow_rate[c] > 0.0 and wd.food_cap[c] > 0.0, "저장고 칸에도 풀이 자람(성장 %.4f·상한 %.2f)" % [wd.grow_rate[c], wd.food_cap[c]])
	var plant := 5.0
	wd.food[c] = plant
	wd._think(i, p.x, p.y, c, wd.s_head[i], wd.s_emax[i])
	check(wd._in[SimBrain.IN_FOOD_HERE] == 0.0, "저장고 칸의 발밑 먹이 입력은 저장분만(풀 %.0f, 입력 %.3f)" % [plant, wd._in[SimBrain.IN_FOOD_HERE]])
	wd.s_energy[i] = 1.0
	wd.s_carry[i] = 0.0
	wd._eat(i, c, wd.s_size[i], wd.s_emax[i])
	check(wd.s_energy[i] == 1.0 and wd.food[c] == plant, "저장고 칸에서 먹기는 저장분만(저장분 0 → 풀 그대로 %.1f)" % wd.food[c])
	wd._gather(i, c, wd.s_size[i])
	check(wd.s_carry[i] > 0.0 and is_equal_approx(wd.food[c] + wd.s_carry[i], plant), "저장고 칸의 풀은 줍기로 꺼냄(운반 %.2f)" % wd.s_carry[i])
	done()


## 자식 에너지는 자식의 최대 에너지까지(I28) — 넘친 몫은 장부 led_repro_loss 로(장부 그대로). 예전: 번식 비용 0.6·효율 1.0 에서
## 최대의 1.2배(400틱 동안 최대를 넘은 슬라임·틱 171).
func test_child_energy_cap() -> void:
	var sets := {"repro.cost_frac": 0.6, "repro.transfer_efficiency": 1.0}
	var wd := empty_world({"repro.cost_frac": 0.6, "repro.transfer_efficiency": 1.0, "mutation.rate": 0.0})
	var p := grass_spot(wd)
	add_slime(wd, p, 1.0, 100)
	add_slime(wd, p, 1.0, 100)
	wd.s_dead.fill(0)
	wd._reproduce()
	var k := wd.index_of_id(2)
	check(wd.population() == 3 and wd.s_energy[k] == wd.s_emax[k], "가득 찬 두 부모 · 비용 0.6 · 효율 1 → 자식 에너지 = 자식 최대(%.2f / %.2f)" % [wd.s_energy[k], wd.s_emax[k]])
	check(absf(wd.total_energy() - wd.ledger_expected()) < 1e-9, "넘친 몫은 번식 손실로 장부에 남음")
	var w2 := world(sets, 1)
	var over := 0
	var worst := 0.0
	for t in 400:
		w2.step()
		for j in w2.population():
			if w2.s_energy[j] > w2.s_emax[j]:
				over += 1
		worst = maxf(worst, absf(w2.total_energy() - w2.ledger_expected()))
	check(over == 0 and worst < 1e-6, "비용 0.6·효율 1·씨앗 1·400틱: 최대 에너지를 넘은 슬라임·틱 %d, 장부 오차 %s" % [over, String.num_scientific(worst)])
	done()


## 저장고 짓기·저장 발견은 ③ 의 내려놓기 순간(I29): 같은 틱 뒤 차례 개체가 그 저장고를 입력으로 본다. 파일 머리의 틱 순서 주석이
## 이것을 적는다(예전 주석·DESIGN 9절은 "⑦ 발견 판정·건물").
func test_store_built_in_act() -> void:
	var wd := empty_world()
	var p := grass_spot(wd)
	var a := wd.index_of_id(add_slime(wd, p, 0.9, 100, 1))
	var q := p + Vector2i(int(wd.cfg.repro.mate_radius) + 2, 0)
	if q.x >= wd.w or not SimGrid.passable(wd.tiles[q.y * wd.w + q.x]):
		q = p + Vector2i(0, int(wd.cfg.repro.mate_radius) + 2)
	var b := wd.index_of_id(add_slime(wd, q, 0.9, 100, 1))
	wd.stage = SimWorld.STAGE_FORAGE
	wd.s_carry[a] = float(wd.cfg.discovery.store_threshold)
	wd.s_last_action[a] = SimBrain.ACT_DROP
	# a(id 0)는 이 틱에 판단하지 않고 내려놓기를 되풀이, b(id 1)는 판단(think_every 2, 틱 1)
	wd._think_every = 2
	wd.tick = 1
	wd.step()
	var ev_tick := -1
	for e in wd.chronicle:
		if str(e.kind) == "store_built":
			ev_tick = int(e.tick)
	check(wd.discovery_tick[SimWorld.STAGE_STORE] == 1 and ev_tick == 1, "저장 발견·저장고 1호가 내려놓은 틱 1 에(발견 틱 %d, 사건 틱 %d)" % [wd.discovery_tick[SimWorld.STAGE_STORE], ev_tick])
	check(wd.store_dist[q.y * wd.w + q.x] != SimGrid.FAR and wd._in[SimBrain.IN_STORE_NEAR] > 0.0,
			"같은 틱 뒤 차례 개체(b)의 판단에 그 저장고가 보임(저장고 가까움 %.3f)" % wd._in[SimBrain.IN_STORE_NEAR])
	var head := FileAccess.get_file_as_string("res://scripts/sim/sim_world.gd").split("const STAGE_NONE", true, 1)[0]
	check(head.contains("저장고 짓기와 저장 발견은 ⑦ 이 아니라 ③") and head.contains("⑦ 채집·농사 발견 판정"), "sim_world.gd 머리의 틱 순서 주석이 실제 순서(저장고는 ③)를 적음")
	done()


## 바닥 먹이 수명(I30·J12): 실제 틱 흐름에서 내려놓은 틱부터 꼭 spoil_ticks 틱 뒤에 썩는다(예전 spoil_ticks − 1). 타이머는 칸마다
## 하나라 더 내려놓으면 더미 전체가 다시 센다 — 이름표(말풍선·CONFIG.md)도 그렇게 적는다.
func test_spoil_lifetime() -> void:
	var spoil := int(cfg_with().dropped.spoil_ticks)
	var gone_at := func(wd: SimWorld, c: int, more_at: int) -> int:
		var t0 := wd.tick
		var limit := t0 + 4 * spoil
		while wd.tick < limit:
			if wd.tick == more_at:
				wd._put_dropped(c, 1.0)
			var t := wd.tick
			wd.step()
			if wd.dropped[c] == 0.0:
				return t
		return -1
	var wd := empty_world({"dropped.sprout_chance": 0.0})
	var p := grass_spot(wd)
	var c := p.y * wd.w + p.x
	wd.tick = 7
	wd._put_dropped(c, 5.0)
	var g1: int = gone_at.call(wd, c, -1)
	check(g1 - 7 == spoil, "틱 7 에 내려놓은 먹이가 틱 %d 에 사라짐 = 수명 %d틱(spoil_ticks %d)" % [g1, g1 - 7, spoil])
	var w2 := empty_world({"dropped.sprout_chance": 0.0})
	w2.tick = 7
	w2._put_dropped(c, 5.0)
	var g2: int = gone_at.call(w2, c, 7 + 80)
	check(g2 == 7 + 80 + spoil, "틱 87 에 더 놓으면 더미 전체(처음 5 포함)가 틱 %d 에 사라짐(= 87 + %d)" % [g2, spoil])
	var help := str(SimConfig.load_json("res://config/sim-labels.json")["dropped.spoil_ticks"].help)
	check(help.contains("마지막으로 내려놓은 틱부터") and help.contains("더 내려놓으면 더미 전체가 다시 셈"), "이름표: 썩는 시간은 칸 더미의 마지막 내려놓기부터(다시 셈): " + help)
	done()


## 식물 갱신 간격은 성능용(J02): 간격과 상관없이 같은 양이 자란다(그 사이 틱마다의 빛·계절을 더함). 예전엔 갱신 틱의 빛을 간격 전체에
## 곱해 12 는 −20%, 20 은 −33%, 하루 길이(60)의 배수면 늘 빛 0 인 틱에 갱신해 전혀 자라지 않았다.
func test_growth_interval() -> void:
	var totals := {}
	for every in [1, 2, 4, 7, 12, 20, 60]:
		var wd := world({"population.initial": 0, "plants.initial_fill": 0.0, "plants.max_food": 1e9, "plants.update_every": every})
		wd.step_n(420)
		totals[every] = wd.sum_of(wd.food)
	var base: float = totals[1]
	var bad := PackedStringArray()
	for every in totals:
		if absf(float(totals[every]) - base) > base * 1e-9:
			bad.append("%d: %.1f" % [every, float(totals[every])])
	check(base > 0.0 and bad.is_empty(), "갱신 간격 1·2·4·7·12·20·60 의 420틱 성장 합이 같음(간격 1: %.1f, 다른 것: %s)" % [base, ", ".join(bad)])
	done()


## 밭 버려짐은 매 틱, 성장 속도와 상관없이(J03): 밭 성장 배수 0 이어도, 식물 갱신 간격이 7 이어도 마지막으로 밟은 틱 + abandon_ticks + 1
## 에 풀밭으로. 예전엔 성장 속도 0 인 칸은 판정을 건너뛰어 영영 밭으로 남았고, 판정은 갱신 틱에만 돌았다.
func test_farm_abandon_any_growth() -> void:
	for sets in [{"farm.growth_mult": 0.0}, {"plants.update_every": 7}]:
		var wd := empty_world(sets)
		var p := grass_spot(wd)
		wd.store_tiles.append(p.y * wd.w + p.x)
		wd.store_food.append(0.0)
		wd._rebuild_stores()
		wd.stage = SimWorld.STAGE_FARM
		var i := wd.index_of_id(add_slime(wd, p + Vector2i(0, 1), 0.9, 100, 1))
		wd.s_carry[i] = 3.0
		wd.s_last_action[i] = SimBrain.ACT_PLANT
		wd._think_every = 1000000
		wd.tick = 1
		wd._act_all()
		wd.s_last_action[i] = SimBrain.ACT_REST
		wd.s_max_age[i] = 1000000
		var tc := (p.y + 1) * wd.w + p.x + 1
		var due := wd.farm_visit[tc] + int(wd.cfg.farm.abandon_ticks) + 1
		wd.tick = due - 1
		wd.s_energy[i] = wd.s_emax[i]
		wd.step()
		var kept := wd.tiles[tc] == SimGrid.TILE_FARM
		wd.step()
		var lost_tick := -1
		for e in wd.chronicle:
			if str(e.kind) == "farm_lost":
				lost_tick = int(e.tick)
		check(kept and wd.tiles[tc] == SimGrid.TILE_GRASS and wd.farms.is_empty() and lost_tick == due,
				"%s: 밭이 틱 %d 까지 남고 틱 %d 에 풀밭으로(버려짐 사건 틱 %d)" % [str(sets), due - 1, due, lost_tick])
	done()


## 빛 곡선(J11): 해 뜨고 지는 램프는 낮 구간 안쪽에 있어 하루 빛 합 = 낮 틱 − twilight, 빛 1 인 틱 = 낮 틱 − 2·twilight + 1.
## 이름표는 낮 비율을 '빛이 0 보다 큰 몫'으로, twilight 는 하루 빛 합·성장을 줄인다고 적는다(예전 '낮(빛 1)인 몫').
func test_light_curve() -> void:
	var bad := PackedStringArray()
	for tw in [0, 3, 6, 12, 18]:
		var wd := empty_world({"time.twilight_ticks": tw})
		var day := int(wd.cfg.time.day_ticks)
		var lit := int(float(day) * float(wd.cfg.time.daylight_fraction))
		var total := 0.0
		var ones := 0
		for t in day:
			var l := wd._light_at(t)
			total += l
			if l == 1.0:
				ones += 1
		var want_ones: int = lit - 2 * tw + 1 if tw > 0 else lit
		if absf(total - float(lit - tw)) > 1e-9 or ones != want_ones:
			bad.append("tw %d: 합 %.2f 빛1 %d" % [tw, total, ones])
	check(bad.is_empty(), "하루 빛 합 = 낮 틱 − twilight, 빛 1 인 틱 = 낮 틱 − 2·twilight + 1 (틀린 것: %s)" % ", ".join(bad))
	var labels: Dictionary = SimConfig.load_json("res://config/sim-labels.json")
	var hf := str(labels["time.daylight_fraction"].help)
	var ht := str(labels["time.twilight_ticks"].help)
	check(not hf.contains("빛 1)") and hf.contains("빛이 0 보다 큰 몫") and ht.contains("하루 빛 합 = 낮 틱 - 이 값"),
			"이름표: 낮 비율 = 빛이 0 보다 큰 몫, twilight 는 하루 빛 합을 줄임: %s / %s" % [hf, ht])
	done()


## 밭 칸에는 저장고를 짓지 않는다(J13): farm.radius ≥ store.min_spacing 이면 예전엔 가장 많이 놓인 밭 칸 위에 저장고가 지어져
## 저장고이자 밭으로 두 번 셈(fast_civ·씨앗 2·max_count 40·min_spacing 3·radius 12: 1,183틱 저장고 28호가 밭 위).
func test_store_not_on_farm() -> void:
	var sets := {"farm.radius": 12, "store.min_spacing": 3, "store.max_count": 40}
	var wd := empty_world(sets)
	var p := grass_spot(wd)
	wd.store_tiles.append(p.y * wd.w + p.x)
	wd.store_food.append(0.0)
	wd._rebuild_stores()
	wd.stage = SimWorld.STAGE_FARM
	var rs := int(wd.cfg.discovery.region_size)
	# 저장고에서 3칸 이상 떨어진, 저장고와 다른 구역의 풀밭 칸을 밭으로 만들고 그 칸에 가장 많이 놓인 것으로
	var f := -1
	for y in wd.h:
		for x in wd.w:
			var cc := y * wd.w + x
			if f == -1 and wd.tiles[cc] == SimGrid.TILE_GRASS and absi(x - p.x) + absi(y - p.y) >= 3 and (x / rs != p.x / rs or y / rs != p.y / rs) \
					and wd.store_dist[cc] <= int(wd.cfg.farm.radius):
				f = cc
	var r := (f / wd.w / rs) * wd.regions_x + (f % wd.w) / rs
	wd.tiles[f] = SimGrid.TILE_FARM
	wd.farms.append(f)
	wd.drop_total_tile[f] = 100.0
	wd.region_drop[r] = float(wd.cfg.discovery.store_threshold)
	wd._check_store_region(r)
	check(f != -1 and not wd.store_tiles.has(f) and wd.store_tiles.size() == 1, "가장 많이 놓인 칸이 밭이면 그 위에 저장고를 짓지 않음(저장고 %d개)" % wd.store_tiles.size())
	# 실제 흐름: 저장고 ∩ 밭 = ∅
	var w2 := world(sets, 2, "fast_civ")
	var both := 0
	for k in 12:
		w2.step_n(100)
		for c in w2.farms:
			if w2.store_at[c] != SimWorld.NO_STORE:
				both += 1
	check(w2.stage == SimWorld.STAGE_FARM and both == 0, "fast_civ·씨앗 2·밭 반경 12·간격 3: 1,200틱 동안 저장고이자 밭인 칸 %d(단계 %d, 저장고 %d)" % [both, w2.stage, w2.store_tiles.size()])
	done()


## 행동 이름(I47): 왼쪽·오른쪽은 제자리에서 방향만 바꾼다 — 화면 이름도 "돌기"(예전 "왼쪽으로"·"오른쪽으로" 는 이동처럼 읽힘).
func test_action_names() -> void:
	var wd := empty_world()
	var p := grass_spot(wd)
	var moved := false
	var turned := true
	for act in [SimBrain.ACT_LEFT, SimBrain.ACT_RIGHT]:
		var i := wd.index_of_id(add_slime(wd, p, 0.9, 100, 1))
		wd.s_last_action[i] = act
		wd._think_every = 1000000
		wd.tick = 1
		wd._act_all()
		moved = moved or wd.s_x[i] != p.x or wd.s_y[i] != p.y
		turned = turned and wd.s_head[i] == (SimGrid.left_of(1) if act == SimBrain.ACT_LEFT else SimGrid.right_of(1))
	var nl := SimBrain.ACTION_NAMES[SimBrain.ACT_LEFT]
	var nr := SimBrain.ACTION_NAMES[SimBrain.ACT_RIGHT]
	check(not moved and turned and nl.ends_with("돌기") and nr.ends_with("돌기") and nl.begins_with("왼쪽") and nr.begins_with("오른쪽"),
			"왼쪽·오른쪽 행동은 제자리 돌기, 이름도 \"%s\"·\"%s\"" % [nl, nr])
	done()


## 예설정 harsh_winter 는 멸종 조건(J22): presets.json 의 화면 이름·_comment 가 그렇게 적고(tools/test_sim_labels.py), 적은 결과
## (씨앗 1 은 첫 겨울 중 1,118틱에 멸종)를 여기서 고정한다(느린 검사 — --skip-slow 면 건너뜀).
const HARSH_SEED1_EXTINCT := 1118


func test_harsh_winter() -> void:
	var p: Dictionary = SimConfig.presets().get("harsh_winter", {})
	check(str(p.get("label", "")).contains("멸종") and str(p.get("_comment", "")).contains("%s틱" % _commas(HARSH_SEED1_EXTINCT)),
			"harsh_winter 화면 이름·설명이 멸종 조건과 씨앗 1 의 멸종 틱을 적음: %s" % str(p.get("label", "")))
	if _skip_slow:
		check(true, "느린 검사 건너뜀")
		done()
		return
	var wd := world({}, 1, "harsh_winter")
	while not wd.is_extinct() and wd.tick < 8000:
		wd.step()
	check(wd.extinct_tick == HARSH_SEED1_EXTINCT, "harsh_winter 씨앗 1 은 틱 %d 에 멸종(문서 %d)" % [wd.extinct_tick, HARSH_SEED1_EXTINCT])
	done()


# ───────────────────────── 밭·문명 규칙 값(검토 고침 g1b 검사 보강) ─────────────────────────

## 저장고 하나(p 칸)를 둔 빈 세계의 단계를 정한다.
func with_store(wd: SimWorld, p: Vector2i, stage: int) -> int:
	var c := p.y * wd.w + p.x
	wd.store_tiles.append(c)
	wd.store_food.append(0.0)
	wd._rebuild_stores()
	wd.stage = stage
	return c


## 저장고에서 걷는 거리가 dist 인 풀밭 칸과, 그 칸을 바라보고 설 수 있는 이웃: [선 칸, 방향, 대상 칸]. 없으면 [].
func facing_at_dist(wd: SimWorld, dist: int) -> Array:
	for c in wd.w * wd.h:
		if wd.tiles[c] != SimGrid.TILE_GRASS or wd.store_at[c] != SimWorld.NO_STORE or wd.store_dist[c] != dist:
			continue
		for hd in SimGrid.DIR_COUNT:
			var sx: int = c % wd.w - SimGrid.DX[hd]
			var sy: int = c / wd.w - SimGrid.DY[hd]
			if sx >= 0 and sy >= 0 and sx < wd.w and sy < wd.h and SimGrid.passable(wd.tiles[sy * wd.w + sx]):
				return [Vector2i(sx, sy), hd, c]
	return []


## 슬라임 한 마리가 이번 틱에 판단 없이 act 를 하게 하고 한 번 행동시킨다.
func act_once(wd: SimWorld, i: int, act: int, at_tick: int) -> void:
	wd.s_last_action[i] = act
	wd._think_every = 1000000
	wd.tick = at_tick
	wd._act_all()


## 밭 규칙 값(I11): 심기는 저장고에서 걷는 거리 farm.radius 안 풀밭만, 밭 성장 속도 = 같은 비옥도 풀밭 × growth_mult·상한 × max_mult,
## 계절 배수가 winter_floor 보다 낮으면 밭은 winter_floor 로 자람(풀밭은 계절 배수 그대로), 밭을 밟으면 버려짐 시계가 다시 셈.
## 예전엔 반경·겨울 하한·성장 배수 줄을 지워도 규칙 검사 전체가 통과했다(밭이 생긴 뒤의 규칙은 어떤 검사도 지나지 않음).
func test_farm_rule_values() -> void:
	var cfg := cfg_with()
	var radius := int(cfg.farm.radius)
	var abandon := int(cfg.farm.abandon_ticks)
	# (1) 심기 반경: 거리 radius + 1 은 거부(풀밭·운반량 그대로), radius 는 심음
	var planted := {}
	for d in [radius + 1, radius]:
		var wd := empty_world({"plants.update_every": 1})
		with_store(wd, grass_spot(wd), SimWorld.STAGE_FARM)
		var f := facing_at_dist(wd, d)
		check(not f.is_empty(), "저장고에서 거리 %d 인 풀밭과 그 앞에 설 칸이 있음" % d)
		if f.is_empty():
			continue
		var i := wd.index_of_id(add_slime(wd, f[0], 0.9, 100, f[1]))
		wd.s_carry[i] = 3.0
		act_once(wd, i, SimBrain.ACT_PLANT, 1)
		var c: int = f[2]
		if d > radius:
			check(wd.tiles[c] == SimGrid.TILE_GRASS and wd.farms.is_empty() and wd.s_carry[i] == 3.0,
					"저장고에서 %d칸(반경 %d 밖) 풀밭에는 심지 않음(칸 %d, 밭 %d곳)" % [d, radius, wd.tiles[c], wd.farms.size()])
		else:
			check(wd.tiles[c] == SimGrid.TILE_FARM and wd.farms.size() == 1 and wd.s_carry[i] == 3.0 - float(cfg.farm.seed_cost),
					"저장고에서 %d칸(반경 안)이면 심음" % d)
			planted = {world = wd, cell = c, slime = i, stand = f[0], head = f[1]}
	if planted.is_empty():
		done()
		return
	var wf: SimWorld = planted.world
	var fc: int = planted.cell
	# (2) 성장 배수: 같은 비옥도(1)로 맞춘 풀밭 칸과 견줌
	var q := -1
	for c in wf.w * wf.h:
		if c != fc and wf.tiles[c] == SimGrid.TILE_GRASS and wf.store_at[c] == SimWorld.NO_STORE:
			q = c
			break
	wf.fert[q] = 1.0
	wf._update_tile_rates(q)
	check(wf.fert[fc] == 1.0 and is_equal_approx(wf.grow_rate[fc], wf.grow_rate[q] * float(cfg.farm.growth_mult))
			and is_equal_approx(wf.food_cap[fc], wf.food_cap[q] * float(cfg.farm.max_mult)),
			"밭 성장 속도 %.3f = 풀밭 %.3f × growth_mult %.1f, 상한 %.1f = 풀밭 %.1f × max_mult %.1f" % [wf.grow_rate[fc], wf.grow_rate[q],
			float(cfg.farm.growth_mult), wf.food_cap[fc], wf.food_cap[q], float(cfg.farm.max_mult)])
	# (3) 겨울 하한: 빛 1 인 겨울 틱(계절 배수 0.3 < 하한 0.4)과 여름 틱(1.2 > 하한)에 한 틱(update_every 1) 자란 양
	var day := int(cfg.time.day_ticks)
	var season_len := day * int(cfg.time.season_days)
	var tw := int(cfg.time.twilight_ticks)
	var floor_v := float(cfg.farm.winter_floor)
	var grown := PackedStringArray()
	var growth_ok := true
	for si in [3, 1]:
		var sg := float(cfg.seasons.growth[si])
		wf.tick = season_len * si + tw
		check(wf._light_at(wf.tick) == 1.0 and wf._season_at(wf.tick) == si, "검사 틱 %d 은 빛 1·계절 %d" % [wf.tick, si])
		wf.food[fc] = 0.0
		wf.food[q] = 0.0
		wf._grow_plants()
		var want_farm := wf.grow_rate[fc] * maxf(sg, floor_v)
		var want_grass := wf.grow_rate[q] * sg
		grown.append("계절 %d: 밭 %.4f(기대 %.4f) 풀밭 %.4f(기대 %.4f)" % [si, wf.food[fc], want_farm, wf.food[q], want_grass])
		if not is_equal_approx(wf.food[fc], want_farm) or not is_equal_approx(wf.food[q], want_grass):
			growth_ok = false
	check(float(cfg.seasons.growth[3]) < floor_v and growth_ok,
			"밭은 max(계절 배수, winter_floor %.1f) 로, 풀밭은 계절 배수로 자람: %s" % [floor_v, "; ".join(grown)])
	# (4) 밭을 밟으면 버려짐 시계가 다시: 심은 틱 1 → abandon − 10 틱에 밟음 → 1 + abandon + 1 에도 남고, 밟은 틱 + abandon + 1 에 풀밭
	var i: int = planted.slime
	var stepped := 1 + abandon - 10
	act_once(wf, i, SimBrain.ACT_FORWARD, stepped)
	var on_farm := wf.s_y[i] * wf.w + wf.s_x[i] == fc
	wf.tick = 1 + abandon + 1
	wf._abandon_farms()
	var kept := wf.tiles[fc] == SimGrid.TILE_FARM
	wf.tick = stepped + abandon + 1
	wf._abandon_farms()
	check(on_farm and wf.farm_visit[fc] == stepped and kept and wf.tiles[fc] == SimGrid.TILE_GRASS,
			"밭을 밟은 틱 %d 부터 다시 셈: 심은 틱 기준 기한(%d)에는 남고(%s) 밟은 틱 기준 기한(%d)에 풀밭으로" % [stepped, 1 + abandon + 1,
			str(kept), stepped + abandon + 1])
	done()


## 문명 규칙 값(I11): 저장고 최대 수·최소 간격(둘째는 간격 밖이면 지음), 농사 싹은 저장고에서 discovery.farm_radius 안만 셈,
## 채집 시도는 배부르고 먹이가 있을 때만 셈, 운반은 carry.max × 크기에서 멈춤, 죽으면 운반분이 바닥에 남음.
## 예전엔 이 규칙들이 fast_civ 씨앗 1 의 농사 발견 시각 하나로만 걸려 어느 규칙이 깨졌는지 알 수 없었다.
func test_civ_rule_values() -> void:
	# (a) 저장고: 구역마다 임계만큼 내려놓음 — 간격(min_spacing) 밖이면 지음, max_count 개가 되면 더 짓지 않음
	var wd := empty_world()
	var spacing := int(wd.cfg.store.min_spacing)
	var max_count := int(wd.cfg.store.max_count)
	var rs := int(wd.cfg.discovery.region_size)
	var thr := float(wd.cfg.discovery.store_threshold)
	var picks := PackedInt32Array()
	for c in wd.w * wd.h:
		if wd.tiles[c] != SimGrid.TILE_GRASS:
			continue
		var ok := true
		for o in picks:
			if absi(o % wd.w - c % wd.w) + absi(o / wd.w - c / wd.w) < spacing or ((o % wd.w) / rs == (c % wd.w) / rs and (o / wd.w) / rs == (c / wd.w) / rs):
				ok = false
				break
		if ok:
			picks.append(c)
		if picks.size() > max_count:
			break
	check(picks.size() == max_count + 1, "서로 간격 %d 밖·다른 구역인 풀밭 %d칸을 찾음(%d칸)" % [spacing, max_count + 1, picks.size()])
	var i := wd.index_of_id(add_slime(wd, grass_spot(wd)))
	wd.stage = SimWorld.STAGE_FORAGE
	var counts := PackedInt32Array()
	for c in picks:
		wd.s_carry[i] = thr
		wd._drop(i, c)
		counts.append(wd.store_tiles.size())
	check(counts.size() == max_count + 1 and counts[1] == 2 and counts[max_count - 1] == max_count and counts[max_count] == max_count,
			"간격 밖 구역마다 저장고를 지어 %d개까지, 그다음은 짓지 않음(내려놓을 때마다 저장고 수 %s)" % [max_count, str(counts)])
	# (b) 농사 싹은 저장고에서 걷는 거리 discovery.farm_radius 안만 셈(그 밖의 싹도 트지만 세지 않음)
	var w2 := empty_world({"dropped.sprout_chance": 1.0})
	with_store(w2, grass_spot(w2), SimWorld.STAGE_STORE)
	var fr := int(w2.cfg.discovery.farm_radius)
	var inside := facing_at_dist(w2, fr)
	var outside := facing_at_dist(w2, fr + 1)
	check(not inside.is_empty() and not outside.is_empty(), "저장고에서 거리 %d·%d 인 풀밭이 있음" % [fr, fr + 1])
	if not inside.is_empty() and not outside.is_empty():
		var f_out := w2.base_fert[outside[2]]
		w2._put_dropped(inside[2], 2.0)
		w2._put_dropped(outside[2], 2.0)
		for k in int(w2.cfg.dropped.spoil_ticks) + 1:
			w2._spoil_dropped()
		check(w2.farm_sprouts == 1 and w2.base_fert[outside[2]] > f_out,
				"싹 둘 가운데 반경 %d 안의 것만 농사 싹으로 셈(셈 %d, 밖의 싹도 비옥도는 오름)" % [fr, w2.farm_sprouts])
	# (c) 채집 시도는 배부르고(forage_min_energy_frac 이상) 그 칸에 먹이가 있을 때만
	var w3 := empty_world()
	var p3 := grass_spot(w3)
	var c3 := p3.y * w3.w + p3.x
	var i3 := w3.index_of_id(add_slime(w3, p3, 1.0))
	var frac := float(w3.cfg.discovery.forage_min_energy_frac)
	w3.food[c3] = 5.0
	w3.s_energy[i3] = (frac - 0.1) * w3.s_emax[i3]
	act_once(w3, i3, SimBrain.ACT_GATHER, 1)
	var hungry := w3.forage_attempts
	w3.s_energy[i3] = w3.s_emax[i3]
	w3.food[c3] = 0.0
	w3.dropped[c3] = 0.0
	act_once(w3, i3, SimBrain.ACT_GATHER, 2)
	var empty_tile := w3.forage_attempts
	w3.s_energy[i3] = w3.s_emax[i3]
	w3.food[c3] = 5.0
	act_once(w3, i3, SimBrain.ACT_GATHER, 3)
	check(hungry == 0 and empty_tile == 0 and w3.forage_attempts == 1,
			"채집 시도: 배고프면 %d, 빈 칸이면 %d, 배부르고 먹이 있으면 %d (기대 0·0·1)" % [hungry, empty_tile, w3.forage_attempts])
	# (d) 운반 상한: 먹이가 많은 칸에서 계속 주워도 carry.max × 크기에서 멈춤
	var w4 := empty_world()
	var p4 := grass_spot(w4)
	var c4 := p4.y * w4.w + p4.x
	var i4 := w4.index_of_id(add_slime(w4, p4, 1.0))
	w4.stage = SimWorld.STAGE_FORAGE
	w4.dropped[c4] = 1000.0
	for k in 30:
		w4.s_energy[i4] = w4.s_emax[i4]
		act_once(w4, i4, SimBrain.ACT_GATHER, k + 1)
	var cap := float(w4.cfg.carry.max) * w4.s_size[i4]
	check(w4.s_carry[i4] == cap and w4.dropped[c4] == 1000.0 - cap, "30번 주워도 운반량 %.1f = carry.max × 크기 %.1f" % [w4.s_carry[i4], cap])
	# (e) 죽으면 운반분이 그 칸(저장고 아님)의 바닥 먹이로
	w4.dropped[c4] = 0.0
	w4.s_carry[i4] = 4.0
	w4.s_dead[i4] = SimWorld.CAUSE_STARVED
	w4._remove_dead()
	check(w4.population() == 0 and w4.dropped[c4] == 4.0 and w4.drop_listed[c4] == 1, "굶어 죽은 개체의 운반분 4 → 그 칸 바닥 먹이 %.1f" % w4.dropped[c4])
	done()


# ───────────────────────── v0.2 0단계: 관찰 바닥(DESIGN-v0.2 14.1) ─────────────────────────

## v0.1 금 값(DESIGN-v0.2 12.1): 0단계 코드를 바꾸기 전에 v0.1.0 코드(3830afb — 시뮬레이션은 3e53998 그대로)로 잰 값.
## [이름, 예설정, 덮어쓰기, 씨앗, 틱, 역사 해시(64자), timeseries.csv 의 v0.1 22열 글의 SHA-256, 느린 검사]. 기록 방식은 실행기와 같다
## (틱 0 줄, record.every 배수마다, 끝 줄 — 1번의 SHA-256 = 실행기 --seed=1 --generations=100 의 timeseries.csv 에서 BOM 을 뗀 글).
## 1~5 는 sample 정책·판단 1틱마다·혼자 분열 끔이고, 6 이 판단하지 않은 틱의 되풀이·argmax·혼자 분열(b == i)을 덮는다
## (279틱에 멸종 — 그 전에 출생 115, 그 가운데 혼자 분열 78). 새 장치를 모두 끈 세계는 모든 단계에서 이 값 그대로여야 한다.
const V01_GOLDEN := [
	["S19 기본·씨앗 1·6,391틱(평균 100세대)", "default", {}, 1, 6391,
		"171a3a4f1a5ff834851c008ef1b33f17d1f671cd8bb7b857d0a330f75450eb6d", "aeb65cb0b94f978422fb037061ba4196d5e03124995ba97347ca490f8ed88d18", true],
	["기본·씨앗 11·1,500틱", "default", {}, 11, 1500,
		"77d84598c4996b24c322738ad1ea6bafbfacd4005bdf13f054b30123f7719932", "cd64b7d887354be1e64de073e785ccd35e5415308ac6e0fc203e2a2f21dba62f", false],
	["demo_fast·씨앗 2·1,000틱(밭 단계)", "demo_fast", {}, 2, 1000,
		"879c26462ba33b36281f79d9a6d6fd92fe4ea4ebba2a6699b62ac584c26845d3", "5c66fd7fcd187dcf84ec51c626174003c9a644b77fe17eb6b401ec570477b4d1", false],
	["기억 2·씨앗 5·1,000틱", "default", {"brain.memory_units": 2}, 5, 1000,
		"6d91774daed66cc417c96f5086a5b3bebd78577bd66c8f0e322c72c4ba247153", "b0e8c0a246babb4277016ffb9d79ab7519e4c0f86498b7518ae984d4be67ec23", false],
	["fast_civ·씨앗 1·3,400틱", "fast_civ", {}, 1, 3400,
		"88a400eb539b2cc17e0d270f56da0d40da646a794fbf7d3cb77dd5283fa302eb", "f4ef868cb786007b3494fe67e4302d82f00740c2e21a096663ba46adadb025b3", true],
	["argmax·판단 3틱·혼자 분열·씨앗 7·1,000틱", "default", {"brain.policy": "argmax", "brain.think_every": 3, "repro.asexual_when_alone": true}, 7, 1000,
		"44929f8442f0bc95835cbe214be4d878570dcf6b24f019d6c7d1686e1b7c4691", "110bf754b763d49953b632e10659e865870ec9972bdc8e4611e215d135baa5d8", false],
]
## 꺼진 1단계 장치(learn.enabled·body.grow_enabled 끔)의 다른 키와 생애 단계 비율: 바꿔도 역사에 닿지 않아야 함(금 값 그대로 — 14.2 검사 기준 1).
const V01_OFF_KEYS := {"learn.freeze": true, "learn.cost_per_eta": 1.0, "learn.lamarck_frac": 1.0, "learn.ring_len": 3, "learn.diag_factor": "none",
	"learn.stage_mult": [0.5, 0.5, 0.5, 0.5], "body.birth_size_frac": 0.2, "life.adult_frac": 0.1, "life.old_frac": 0.2}
## v0.1.0 실행기로 만든 스냅숏(--seed=42 --max-ticks=200 의 final.snapshot.json, DESIGN-v0.1 8.3 예시와 같은 실행)과,
## 그것을 열어 100틱 이어 돌린 역사 해시·22열 SHA-256(연 틱 줄부터 — 기록 방식은 위와 같음).
const V01_FIXTURE := "res://tests/fixtures/v0.1.0-seed42-t200.snapshot.json"
const V01_FIXTURE_TICKS := 100
const V01_FIXTURE_GOLDEN: Array[String] = [
	"6bd975acd1c93346dc0ecc07569cd44c71e2757c37d6d5f1c1454c67e9b0ac2d", "09419527150c16c265a4ec4811f2d10a080fbd154b19bcf259c91548e95dc56d",
]
## lineage.csv 의 v0.1 열 수(v0.2 의 열은 이 뒤에 붙음 — DESIGN-v0.2 9.4).
const V01_LINEAGE_COUNT := 11
## 32비트 부호 있는 정수의 최댓값(행동 셈이 이것을 넘어도 넘치지 않는지 — test_snapshot_v02_roundtrip).
const I32_MAX := 2147483647
## v0.1 의 timeseries.csv 22열(순서 그대로 — v0.2 의 열은 이 뒤에 붙음, DESIGN-v0.2 9.3). 금 값의 사영은 이 열만 잇는다.
const V01_TIMESERIES_COLUMNS: Array[String] = [
	"tick", "day", "season", "light", "population", "births", "deaths", "mean_gen", "mean_energy",
	"mean_size", "mean_sense", "mean_age", "food_total", "dropped_total", "stored_total", "carry_total",
	"civ_stage", "storehouses", "farms", "forage_attempts", "store_drops", "farm_sprouts",
]


## 실행기와 같은 방식으로 기록하며 wd 를 틱 until 까지 돌린다(지금 틱 줄, record.every 배수마다, 끝 줄). 기록기를 돌려준다.
static func record_until(wd: SimWorld, until: int) -> SimRecorder:
	var rec := SimRecorder.new()
	rec.record(wd)
	while wd.tick < until:
		wd.step()
		if wd.tick % int(wd.cfg.record.every) == 0:
			rec.record(wd)
	if int(rec.rows.back().tick) != wd.tick:
		rec.record(wd)
	return rec


## 기록 줄들을 cols 열만으로 이은 CSV 글(SimRecorder.timeseries_csv 와 같은 꼴 — BOM 없음).
static func csv_of(rows: Array, cols: Array[String]) -> String:
	var lines := PackedStringArray([",".join(cols)])
	for r in rows:
		var cells := PackedStringArray()
		for c in cols:
			cells.append(SimRecorder.fmt(r[c]))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


## 새 장치를 모두 끈 세계 = v0.1 금 값(역사 해시와 22열 사영의 SHA-256), v0.1.0 픽스처가 열리고 이어 돌린 값도 금 값.
## --skip-slow 면 느린 두 실행(S19·fast_civ 3,400틱)은 건너뜀(S19 는 CI 의 100세대 단계가 실행기 해시로도 봄).
func test_v01_golden() -> void:
	check(SimRecorder.TIMESERIES_COLUMNS.slice(0, V01_TIMESERIES_COLUMNS.size()) == V01_TIMESERIES_COLUMNS,
			"timeseries.csv 의 앞 %d열 = v0.1 열(이름·순서 그대로)" % V01_TIMESERIES_COLUMNS.size())
	for g in V01_GOLDEN:
		if g[7] and _skip_slow:
			continue
		var wd := world(g[2], g[3], g[1])
		var rec := record_until(wd, g[4])
		var sha := csv_of(rec.rows, V01_TIMESERIES_COLUMNS).sha256_text()
		check(wd.history_hash == g[5] and sha == g[6], "금 값 %s: 역사 해시 %s(금 %s), 22열 SHA-256 %s(금 %s)" % [g[0],
				wd.history_hash.substr(0, 12), str(g[5]).substr(0, 12), sha.substr(0, 12), str(g[6]).substr(0, 12)])
	# 꺼진 1단계 장치의 키만 바꾼 세계(학습·몸 자람 끔 — DESIGN-v0.2 14.2 검사 기준 1): 금 값 2번(기본·씨앗 11·1,500틱) 그대로
	var g2: Array = V01_GOLDEN[1]
	var wo := world(V01_OFF_KEYS, g2[3], g2[1])
	var reco := record_until(wo, g2[4])
	var sha_o := csv_of(reco.rows, V01_TIMESERIES_COLUMNS).sha256_text()
	check(wo.history_hash == g2[5] and sha_o == g2[6], "꺼진 장치의 키만 바꾼 세계(%s): 금 값 %s 그대로(해시 %s, 22열 %s)" % [
			", ".join(PackedStringArray(V01_OFF_KEYS.keys())), g2[0], wo.history_hash.substr(0, 12), sha_o.substr(0, 12)])
	var r := SimSnapshot.from_text(FileAccess.get_file_as_string(V01_FIXTURE))
	check(r.error == "" and r.world != null, "v0.1.0 픽스처가 열림: " + str(r.error))
	if r.world != null:
		var fw: SimWorld = r.world
		var rec2 := record_until(fw, fw.tick + V01_FIXTURE_TICKS)
		var sha2 := csv_of(rec2.rows, V01_TIMESERIES_COLUMNS).sha256_text()
		check(fw.history_hash == V01_FIXTURE_GOLDEN[0] and sha2 == V01_FIXTURE_GOLDEN[1],
				"v0.1.0 픽스처에서 %d틱 이어 돌린 해시 %s·22열 SHA-256 %s = 금 값" % [V01_FIXTURE_TICKS, fw.history_hash.substr(0, 12), sha2.substr(0, 12)])
	done()


## 행동 셈을 볼 흐름(DESIGN-v0.2 14.1 검사 기준 2): [덮어쓰기, 씨앗, 예설정, 틱, 농사까지 가야 하는가]. 둘째는 판단 3틱(되풀이 틱)·
## argmax·혼자 분열, 셋째는 채집·저장·농사를 모두 여는 흐름(263틱에 농사 — 농사에 닿지 못하면 실패: 문명 행동의 효과 검사가 말없이
## 빠지지 않게).
const ACT_FLOWS := [
	[{}, 3, "default", 600, false],
	[{"brain.policy": "argmax", "brain.think_every": 3, "repro.asexual_when_alone": true}, 7, "default", 270, false],
	[{}, 2, "demo_fast", 1000, true],
]


## 손 장면 하나: 개체 i 가 이번 틱에 판단 없이 act 를 한 번 했을 때의 [s_last_eff, 이번 틱 period_act[act], period_eff[act]].
func eff_once(wd: SimWorld, i: int, act: int) -> Array:
	wd.period_act.fill(0)
	wd.period_eff.fill(0)
	act_once(wd, i, act, wd.tick + 1)
	return [wd.s_last_eff[i], wd.period_act[act], wd.period_eff[act]]


## 행동 셈 act/eff(DESIGN-v0.2 11.1·14.1 검사 기준 2): 기록 줄마다 Σ act = 구간 동안 ③ 에 들어간 개체 수의 합(매 틱 진행 전
## population() 합 — 판단 3틱 세계의 되풀이 포함), eff ≤ act, 돌기·쉬기는 eff = act, 채집 전 eff_gather = 0, 농사 전 eff_plant = 0.
## 개체마다도: 진행 전후 상태로 다시 센 효과(옮김·먹은 양·운반 변화) = s_last_eff. 손 장면으로 효과가 아닌 경우(가득 찬 저장고·벽·배부름·
## 운반 가득·발견 전)를 하나씩.
func test_act_counts() -> void:
	check(",".join(SimRecorder.TIMESERIES_COLUMNS) == ",".join(V01_TIMESERIES_COLUMNS + SimRecorder.ACT_COLUMNS + SimRecorder.EFF_COLUMNS + SimRecorder.STAGE1_COLUMNS)
			and SimRecorder.ACT_COLUMNS.size() == SimBrain.BASE_OUTPUTS and SimRecorder.EFF_COLUMNS.size() == SimBrain.BASE_OUTPUTS,
			"timeseries.csv 열 = v0.1 22열 + act_* 8 + eff_* 8(행동 번호 순서) + 1단계 10열")
	var always := [SimBrain.ACT_LEFT, SimBrain.ACT_RIGHT, SimBrain.ACT_REST]
	var seed_cost := float(cfg_with().farm.seed_cost)
	check(seed_cost > 0.0, "기본 씨앗 비용 > 0(심기 효과를 운반 감소로 다시 셀 수 있음)")
	for f in ACT_FLOWS:
		var wd := world(f[0], f[1], f[2])
		var every := int(wd.cfg.record.every)
		wd.sample()
		var pop_sum := 0
		var rows := 0
		var bad := PackedStringArray()
		var per_bad := PackedStringArray()
		var totals := PackedInt32Array()
		totals.resize(SimBrain.BASE_OUTPUTS * 2)
		var think_skips := 0
		var born_bad := 0
		var born_first := -1
		while wd.tick < int(f[3]):
			# 진행 전 개체 상태(id → [x, y, 먹은 양, 운반])
			var before := {}
			for i in wd.population():
				before[wd.s_id[i]] = [wd.s_x[i], wd.s_y[i], wd.s_eaten[i], wd.s_carry[i]]
				if (wd.tick + wd.s_id[i]) % wd._think_every != 0:
					think_skips += 1
			pop_sum += wd.population()
			wd.step()
			for i in wd.population():
				var id := wd.s_id[i]
				if not before.has(id):
					if wd.s_last_eff[i] != 0:
						born_bad += 1
						if born_first < 0:
							born_first = id
					continue
				var b: Array = before[id]
				var a := wd.s_last_action[i]
				var want := 1
				match a:
					SimBrain.ACT_FORWARD:
						want = 1 if wd.s_x[i] != b[0] or wd.s_y[i] != b[1] else 0
					SimBrain.ACT_EAT:
						want = 1 if wd.s_eaten[i] > b[2] else 0
					SimBrain.ACT_GATHER:
						want = 1 if wd.s_carry[i] > b[3] else 0
					SimBrain.ACT_DROP, SimBrain.ACT_PLANT:
						want = 1 if wd.s_carry[i] < b[3] else 0
				if wd.s_last_eff[i] != want and per_bad.size() < 5:
					per_bad.append("틱 %d #%d 행동 %d 효과 %d(다시 센 값 %d)" % [wd.tick - 1, id, a, wd.s_last_eff[i], want])
			if wd.tick % every != 0 and wd.tick < int(f[3]):
				continue
			var r := wd.sample()
			rows += 1
			var s_act := 0
			for a in SimBrain.BASE_OUTPUTS:
				var na: int = r[SimRecorder.ACT_COLUMNS[a]]
				var ne: int = r[SimRecorder.EFF_COLUMNS[a]]
				s_act += na
				totals[a] += na
				totals[SimBrain.BASE_OUTPUTS + a] += ne
				if ne > na or (always.has(a) and ne != na):
					bad.append("틱 %d 행동 %d: 고름 %d 효과 %d" % [r.tick, a, na, ne])
			if s_act != pop_sum:
				bad.append("틱 %d: Σ act %d ≠ 진행 전 개체 수 합 %d" % [r.tick, s_act, pop_sum])
			if int(r.civ_stage) < SimWorld.STAGE_FORAGE and int(r.eff_gather) != 0:
				bad.append("틱 %d: 채집 전 eff_gather %d" % [r.tick, r.eff_gather])
			if int(r.civ_stage) < SimWorld.STAGE_FARM and int(r.eff_plant) != 0:
				bad.append("틱 %d: 농사 전 eff_plant %d" % [r.tick, r.eff_plant])
			pop_sum = 0
		check(rows > 0 and bad.is_empty(), "%s·씨앗 %d %s: 기록 줄 %d개의 Σ act = 진행 전 개체 수 합, eff ≤ act, 돌기·쉬기 eff = act, 발견 전 줍기·심기 효과 0(%s)" % [
				f[2], f[1], str(f[0]), rows, "; ".join(bad.slice(0, 4))])
		# 갓 태어난 개체는 아직 행동하지 않았으므로 표시 0. 틀린 개체는 수만 센다(실패 문장이 개체마다 길어지지 않게)
		if born_bad > 0:
			per_bad.append("갓 태어난 개체 %d마리의 효과 표시가 0 이 아님(첫 #%d)" % [born_bad, born_first])
		check(per_bad.is_empty(), "%s·씨앗 %d: 개체마다 효과 표시 = 진행 전후로 다시 센 효과(%s)" % [f[2], f[1], "; ".join(per_bad)])
		if wd._think_every > 1:
			check(think_skips > 0, "판단 %d틱 세계: 판단하지 않은 틱의 되풀이도 셈(되풀이 %d번)" % [wd._think_every, think_skips])
		if f[4]:
			check(wd.stage == SimWorld.STAGE_FARM and totals[SimBrain.BASE_OUTPUTS + SimBrain.ACT_GATHER] > 0 and totals[SimBrain.BASE_OUTPUTS + SimBrain.ACT_DROP] > 0
					and totals[SimBrain.BASE_OUTPUTS + SimBrain.ACT_PLANT] > 0 and totals[SimBrain.BASE_OUTPUTS + SimBrain.ACT_EAT] > 0,
					"%s·씨앗 %d·%d틱: 농사에 닿고 줍기·내려놓기·심기·먹기 효과가 셈에 잡힘(단계 %d, 효과 %s)" % [f[2], f[1], f[3], wd.stage, str(totals.slice(SimBrain.BASE_OUTPUTS))])
	# 손 장면: 효과가 아닌 경우·효과인 경우
	var wd2 := empty_world()
	var p := grass_spot(wd2)
	var c := p.y * wd2.w + p.x
	var i := wd2.index_of_id(add_slime(wd2, p, 1.0, 100, 1))
	wd2.s_max_age[i] = 1000000
	var res := {}
	wd2.food[c] = 5.0
	res["발견 전 줍기"] = eff_once(wd2, i, SimBrain.ACT_GATHER)
	var fa0 := wd2.forage_attempts
	wd2.s_energy[i] = wd2.s_emax[i]
	res["배부른 먹기"] = eff_once(wd2, i, SimBrain.ACT_EAT)
	wd2.s_energy[i] = 0.5 * wd2.s_emax[i]
	res["배고픈 먹기"] = eff_once(wd2, i, SimBrain.ACT_EAT)
	wd2.stage = SimWorld.STAGE_FORAGE
	wd2.food[c] = 5.0
	wd2.s_carry[i] = 0.0
	res["채집 뒤 줍기"] = eff_once(wd2, i, SimBrain.ACT_GATHER)
	wd2.s_carry[i] = float(wd2.cfg.carry.max) * wd2.s_size[i]
	wd2.food[c] = 5.0
	res["운반 가득 줍기"] = eff_once(wd2, i, SimBrain.ACT_GATHER)
	res["농사 전 심기"] = eff_once(wd2, i, SimBrain.ACT_PLANT)
	wd2.s_carry[i] = 2.0
	res["바닥에 내려놓기"] = eff_once(wd2, i, SimBrain.ACT_DROP)
	res["빈손 내려놓기"] = eff_once(wd2, i, SimBrain.ACT_DROP)
	# 저장고 장면은 따로(한 세계에 개체가 하나여야 이번 틱 셈이 그 개체의 것)
	var w3 := empty_world()
	var p3 := grass_spot(w3)
	var st := w3.index_of_id(add_slime(w3, p3, 1.0, 100, 1))
	with_store(w3, p3, SimWorld.STAGE_STORE)
	w3.store_food[0] = float(w3.cfg.store.capacity)
	w3.s_carry[st] = 3.0
	res["가득 찬 저장고에 내려놓기"] = eff_once(w3, st, SimBrain.ACT_DROP)
	w3.store_food[0] = 0.0
	res["빈 저장고에 내려놓기"] = eff_once(w3, st, SimBrain.ACT_DROP)
	var front := (p.y + SimGrid.DY[1]) * wd2.w + p.x + SimGrid.DX[1]
	wd2.s_head[i] = 1
	wd2.tiles[front] = SimGrid.TILE_ROCK
	res["바위 쪽 앞으로"] = eff_once(wd2, i, SimBrain.ACT_FORWARD)
	wd2.tiles[front] = SimGrid.TILE_GRASS
	res["풀밭 쪽 앞으로"] = eff_once(wd2, i, SimBrain.ACT_FORWARD)
	res["쉬기"] = eff_once(wd2, i, SimBrain.ACT_REST)
	res["왼쪽 돌기"] = eff_once(wd2, i, SimBrain.ACT_LEFT)
	var want := {"발견 전 줍기": 0, "배부른 먹기": 0, "배고픈 먹기": 1, "채집 뒤 줍기": 1, "운반 가득 줍기": 0, "농사 전 심기": 0,
		"바닥에 내려놓기": 1, "빈손 내려놓기": 0, "가득 찬 저장고에 내려놓기": 0, "빈 저장고에 내려놓기": 1, "바위 쪽 앞으로": 0, "풀밭 쪽 앞으로": 1, "쉬기": 1, "왼쪽 돌기": 1}
	var wrong := PackedStringArray()
	for k: String in want:
		var got: Array = res[k]
		if got[0] != want[k] or got[1] != 1 or got[2] != want[k]:
			wrong.append("%s: 표시 %d·고름 %d·효과 %d(기대 효과 %d)" % [k, got[0], got[1], got[2], want[k]])
	check(wrong.is_empty() and fa0 == 1, "손 장면 %d개의 효과 판정(발견 전 줍기는 시도 %d회로만): %s" % [want.size(), fa0, "; ".join(wrong)])
	var r2 := wd2.sample()
	var zero := true
	for a in SimBrain.BASE_OUTPUTS:
		zero = zero and wd2.period_act[a] == 0 and wd2.period_eff[a] == 0
	check(zero and int(r2.act_left) == 1 and int(r2.eff_left) == 1 and int(r2.act_rest) == 0, "sample() 이 구간 행동 셈(마지막 장면의 왼쪽 돌기 1)을 줄에 싣고 0 으로 되돌림")
	done()


## 먹은 양 장부(DESIGN-v0.2 12.2): Σ 죽은 개체 lin_eaten + Σ 살아 있는 s_eaten = led_eaten − led_eaten_open(상대 오차 1e-9).
static func eaten_gap(wd: SimWorld) -> float:
	var s := 0.0
	for id in wd.lin_eaten.size():
		if wd.lin_death[id] >= 0:
			s += wd.lin_eaten[id]
	for v in wd.s_eaten:
		s += v
	return absf(s - (wd.led_eaten - wd.led_eaten_open)) / maxf(1.0, absf(wd.led_eaten))


## 평생 먹은 양(14.1 범위 3): 장부가 매 기록 틱에 맞고(채집 전 흐름과 저장고·운반·밭이 있는 흐름), 살아 있는 개체의 lin_eaten 은 0,
## lineage.csv 의 eaten 은 죽은 개체 = lin_eaten · 살아 있는 개체 = s_eaten.
func test_eaten_ledger() -> void:
	var wd := world({}, 9)
	var worst := 0.0
	var alive_lin := 0
	for k in 600:
		wd.step()
		if k % 20 == 0:
			worst = maxf(worst, eaten_gap(wd))
	for i in wd.population():
		if wd.lin_eaten[wd.s_id[i]] != 0.0:
			alive_lin += 1
	check(wd.led_eaten > 0.0 and wd.led_eaten_open == 0.0 and worst < 1e-9 and wd.total_deaths > 0,
			"기본·씨앗 9·600틱: 먹은 양 장부 상대 오차 %s(led_eaten %.1f, 사망 %d)" % [String.num_scientific(worst), wd.led_eaten, wd.total_deaths])
	check(alive_lin == 0, "살아 있는 개체의 lin_eaten 은 0(죽을 때 씀 — 0 아닌 개체 %d)" % alive_lin)
	var fa: SimWorld = farm_runs()[0].world
	check(fa.stage == SimWorld.STAGE_FARM and fa.store_tiles.size() > 0 and eaten_gap(fa) < 1e-9,
			"%s·씨앗 %d·%d틱(저장고·운반·밭): 먹은 양 장부 상대 오차 %s" % [FARM_RUN_PRESET, FARM_RUN_SEED, FARM_RUN_TICKS, String.num_scientific(eaten_gap(fa))])
	var lines := SimRecorder.lineage_csv(fa).split("\n", false)
	var col := SimRecorder.LINEAGE_COLUMNS.find("eaten")
	var off := PackedStringArray()
	var col_sum := 0.0
	for id in fa.lin_pa.size():
		var i := fa.index_of_id(id)
		var want := fa.s_eaten[i] if i != -1 else fa.lin_eaten[id]
		var cell := lines[id + 1].split(",")[col]
		col_sum += cell.to_float()
		if cell != SimRecorder.fmt(want) and off.size() < 3:
			off.append("#%d %s ≠ %s" % [id, cell, SimRecorder.fmt(want)])
	check(col == V01_LINEAGE_COUNT and off.is_empty(), "lineage.csv 의 v0.1 11열 뒤 첫 열 eaten = 죽은 개체 lin_eaten·살아 있는 개체 s_eaten(%s)" % ", ".join(off))
	check(absf(col_sum - (fa.led_eaten - fa.led_eaten_open)) < 1e-6 * float(fa.lin_pa.size()) + 1e-9,
			"lineage.csv eaten 열의 합 %.3f = 먹은 양 장부 %.3f(소수 6자리 반올림 안)" % [col_sum, fa.led_eaten - fa.led_eaten_open])
	done()


## 왕복(14.1 검사 기준 3): 500틱(기록 줄 틱)·510틱(구간 한가운데 — 행동 셈이 쌓인 채) 스냅숏에서 이어 돌린 1,000틱 = 곧장 1,000틱 —
## 새 열이 든 timeseries.csv(그 틱 뒤 줄)·eaten 이 든 lineage.csv·전체 상태 글·역사 해시까지.
func test_snapshot_v02_roundtrip() -> void:
	var wd := world({}, 21)
	var rec := SimRecorder.new()
	rec.record(wd)
	var snaps := {}
	var every := int(wd.cfg.record.every)
	while wd.tick < 1000:
		wd.step()
		if wd.tick % every == 0:
			rec.record(wd)
		if wd.tick == 500 or wd.tick == 510:
			snaps[wd.tick] = SimSnapshot.to_text(wd)
	var mid = JSON.parse_string(snaps[510])
	var mid_act := Marshalls.base64_to_raw(str(mid.stats.get("period_act", ""))).to_int64_array()
	var mid_sum := 0
	for v in mid_act:
		mid_sum += v
	check(mid_sum > 0 and mid.slimes.has("last_eff") and mid.slimes.has("eaten") and mid.lineage.has("eaten") and mid.stats.has("led_eaten_open"),
			"510틱 스냅숏에 v0.2 키와 구간 중간의 행동 셈(합 %d)이 담김" % mid_sum)
	for t: int in snaps:
		var r := SimSnapshot.from_text(snaps[t])
		check(r.error == "" and r.world != null, "%d틱 스냅숏 열기: %s" % [t, str(r.error)])
		if r.world == null:
			continue
		var w2: SimWorld = r.world
		var rec2 := SimRecorder.new()
		while w2.tick < 1000:
			w2.step()
			if w2.tick % every == 0:
				rec2.record(w2)
		var want: Array = []
		for row in rec.rows:
			if int(row.tick) > t:
				want.append(row)
		var a := csv_of(want, SimRecorder.TIMESERIES_COLUMNS)
		var b := csv_of(rec2.rows, SimRecorder.TIMESERIES_COLUMNS)
		check(want.size() > 0 and a == b, "%d틱 → 열기 → 1,000틱의 timeseries.csv(%d열·%d줄) = 곧장 1,000틱" % [t, SimRecorder.TIMESERIES_COLUMNS.size(), want.size()])
		check(SimRecorder.lineage_csv(w2) == SimRecorder.lineage_csv(wd) and SimSnapshot.to_text(w2) == SimSnapshot.to_text(wd)
				and w2.history_hash == wd.history_hash, "%d틱 → 열기 → 1,000틱의 lineage.csv(eaten 포함)·전체 상태·해시 = 곧장 1,000틱" % t)
	# 행동 셈은 64비트(9.1): 한 구간의 개체·틱 합이 2^31 을 넘는 설정(개체 상한 × record.every — 검사를 통과하는 범위 안)에서도
	# 넘쳐 음수가 되지 않고, 그 세계를 저장·열 수 있음(예전 32비트는 음수 → validate_world 가 "행동 셈이 잘못" 으로 거부)
	var wb := world({}, 21)
	wb.step_n(20)
	wb.period_act.fill(I32_MAX)
	wb.period_eff.fill(I32_MAX)
	var pop0 := wb.population()
	wb.step()
	var over := 0
	var all_big := true
	for a in SimBrain.BASE_OUTPUTS:
		over += wb.period_act[a] - I32_MAX
		all_big = all_big and wb.period_act[a] >= I32_MAX and wb.period_eff[a] >= I32_MAX
	var rb := SimSnapshot.from_text(SimSnapshot.to_text(wb))
	check(all_big and over == pop0 and rb.world != null and rb.world.period_act == wb.period_act and rb.world.period_eff == wb.period_eff,
			"행동 셈이 2^31 − 1 을 넘어도(한 틱 더 — 개체 %d) 넘치지 않고 저장·열기 왕복(고름 합 증가 %d, %s)" % [pop0, over, str(rb.error)])
	done()


## v0.1.0 픽스처(14.1 검사 기준 4): 옛 형식(v0.2 키·repro.inherit 없음)이 열리고 9.1 의 '옛 파일에 없으면' 값으로 채워짐, 이어 돌린
## 세계의 먹은 양 장부가 맞음, 다시 저장하면 새 키가 들어가 왕복. 시험용 새 절을 기본값에 넣어도 SECTIONS_ADDED 로 열림(9.2) —
## 그 절을 지운 v0.2 스냅숏도.
func test_snapshot_v01_fixture() -> void:
	var text := FileAccess.get_file_as_string(V01_FIXTURE)
	var d = JSON.parse_string(text)
	check(typeof(d) == TYPE_DICTIONARY and str(d.app_version) == "0.1.0" and not d.config.repro.has("inherit") and not d.slimes.has("last_eff")
			and not d.slimes.has("eaten") and not d.lineage.has("eaten") and not d.stats.has("period_act") and not d.stats.has("led_eaten_open"),
			"픽스처는 v0.1.0 형식(repro.inherit·v0.2 키 없음)")
	var r := SimSnapshot.from_dict(d)
	check(r.error == "" and r.world != null, "v0.1.0 픽스처 열기: " + str(r.error))
	if r.world == null:
		done()
		return
	var w: SimWorld = r.world
	var zeros := true
	for v in w.s_last_eff:
		zeros = zeros and v == 0
	for v in w.s_eaten:
		zeros = zeros and v == 0.0
	for v in w.lin_eaten:
		zeros = zeros and v == 0.0
	for a in SimBrain.BASE_OUTPUTS:
		zeros = zeros and w.period_act[a] == 0 and w.period_eff[a] == 0
	var lc0 := w.lin_pa.size()
	check(str(w.cfg.repro.inherit) == SimWorld.INHERIT_GENOME and zeros and w.s_last_eff.size() == w.population() and w.lin_eaten.size() == lc0
			and SimSnapshot.f64_hex(w.led_eaten_open) == str(d.stats.led_eaten) and w.led_eaten > 0.0 and w.eaten_from_id == lc0,
			"옛 파일에 없는 키: repro.inherit = genome, last_eff·eaten·lineage eaten·행동 셈 = 0, led_eaten_open = 연 틱의 led_eaten(%.1f), eaten_from_id = 연 틱의 계통 수 %d(%d)" % [
			w.led_eaten, lc0, w.eaten_from_id])
	w.step_n(300)
	check(eaten_gap(w) < 1e-9 and w.led_eaten > w.led_eaten_open, "픽스처에서 300틱 이어 돌린 세계의 먹은 양 장부 상대 오차 %s(연 뒤 먹은 양 %.1f)" % [
			String.num_scientific(eaten_gap(w)), w.led_eaten - w.led_eaten_open])
	# lineage.csv: 연 틱 전에 태어난 개체(평생 값을 모름 — 0 이거나 연 뒤의 몫)는 eaten 칸이 비고, 연 뒤에 태어난 개체는 값이 있음(검증 지적)
	var col := SimRecorder.LINEAGE_COLUMNS.find("eaten")
	var lines := SimRecorder.lineage_csv(w).split("\n", false)
	var wrong := PackedStringArray()
	for id in w.lin_pa.size():
		var cell := lines[id + 1].split(",")[col]
		if (cell == "") != (id < lc0) and wrong.size() < 3:
			wrong.append("#%d '%s'" % [id, cell])
	check(w.lin_pa.size() > lc0 and wrong.is_empty(), "이어 돌린 lineage.csv 의 eaten: 연 틱 전 개체 %d명은 빈 칸, 그 뒤 %d명은 값(%s)" % [
			lc0, w.lin_pa.size() - lc0, ", ".join(wrong)])
	var t2 := SimSnapshot.to_text(w)
	var r2 := SimSnapshot.from_text(t2)
	check(r2.world != null and SimSnapshot.to_text(r2.world) == t2 and str(JSON.parse_string(t2).config.repro.inherit) == "genome",
			"이어 돌린 세계를 다시 저장하면 v0.2 키·repro.inherit 가 들어가고 글자 그대로 왕복")
	# 1단계 절(learn)·키(life.adult_frac 등): 옛 파일에 없으니 SECTIONS_ADDED·CONFIG_KEYS_ADDED 가 기본값(학습·몸 자람 끔)으로 채움
	check(SimSnapshot.SECTIONS_ADDED.has("learn") and not d.config.has("learn") and SimConfig.deep_equal(w.cfg.learn, SimConfig.defaults().learn)
			and float(w.cfg.life.adult_frac) == float(SimConfig.defaults().life.adult_frac) and not bool(w.cfg.body.grow_enabled)
			and w.s_w2.is_empty() and w.lin_eta.is_empty() and w.led_learn == 0.0,
			"옛 파일에 없는 1단계 설정: learn 절·life.adult_frac·body.grow_enabled 등을 기본값(학습·몸 자람 끔)으로 채움, 학습 배열은 빈 배열")
	# 시험용 새 절: 기본값에 절을 더하면 그 절이 없는 옛 파일은 SECTIONS_ADDED 없이는 거부, 있으면 기본값 절로 채워 열림
	SimConfig.defaults()
	SimConfig._defaults_cache["probe_section"] = {"probe_on": false}
	SimSnapshot._sections_added = SimSnapshot.SECTIONS_ADDED
	var e_without := str(SimSnapshot.from_text(text).error)
	var with_probe: Array = SimSnapshot.SECTIONS_ADDED.duplicate()
	with_probe.append("probe_section")
	SimSnapshot._sections_added = with_probe
	var r3 := SimSnapshot.from_text(text)
	var w4 := world({}, 3)
	w4.step_n(50)
	var d4 = JSON.parse_string(SimSnapshot.to_text(w4))
	var had := (d4.config as Dictionary).has("probe_section")
	d4.config.erase("probe_section")
	var r4 := SimSnapshot.from_dict(d4)
	SimConfig._defaults_cache.erase("probe_section")
	SimSnapshot._sections_added = SimSnapshot.SECTIONS_ADDED
	check(e_without.contains("probe_section"), "새 절을 SECTIONS_ADDED 에 넣지 않으면 옛 파일 거부(설정 키가 없음): " + e_without)
	check(r3.world != null and SimConfig.deep_equal(r3.world.cfg.get("probe_section"), {"probe_on": false}), "새 절이 SECTIONS_ADDED 에 있으면 기본값 절로 채워 엶: " + str(r3.error))
	if r3.world != null:
		r3.world.step_n(V01_FIXTURE_TICKS)
		check(r3.world.history_hash == V01_FIXTURE_GOLDEN[0], "새 절을 채워 연 픽스처도 %d틱 이어 돌린 해시 = 금 값" % V01_FIXTURE_TICKS)
	check(had and r4.error == "" and r4.world != null, "새 절을 지운 v0.2 스냅숏도 열림: " + str(r4.error))
	check(SimConfig.validate(SimConfig.defaults()) == "" and not SimConfig.defaults().has("probe_section"), "시험용 절을 치운 뒤 기본값 그대로")
	done()


## v0.2 0단계 설정(14.1 범위 4·5, 검사 기준 5): 정수 원소 규칙(INT_ELEMS)이 1.5 를 거부, repro.inherit 의 고를 값·옛 설정 키·예설정.
func test_v02_config() -> void:
	var rule := ["probe.table", 0, 15, SimConfig.INT_ELEMS]
	var e15 := SimConfig.check_array_rule([1.0, 1.5], rule)
	check(e15.contains("probe.table") and e15.contains("정수"), "정수 원소 규칙이 1.5 를 거부: " + e15)
	check(SimConfig.check_array_rule([0.0, 15.0, 7], rule) == "", "정수 원소(0·15·7)는 받음")
	check(SimConfig.check_array_rule([16.0], rule).contains("범위") and SimConfig.check_array_rule(["a"], rule).contains("수여야"), "정수 원소 규칙도 범위·수 검사")
	check(SimConfig.check_array_rule([1.5], ["probe.table", 0, 15]) == "", "넷째 칸이 없는 배열 규칙은 소수를 받음(seasons.growth 처럼)")
	check(SimConfig.CHOICES["repro.inherit"] == [SimWorld.INHERIT_GENOME, SimWorld.INHERIT_RANDOM] and str(cfg_with().repro.inherit) == SimWorld.INHERIT_GENOME,
			"repro.inherit 고를 값 = SimWorld.INHERIT_*, 기본 genome")
	for bad in ["Random", "", "lamarck", 1.0]:
		check(str(SimConfig.build("default", {"repro.inherit": bad}).error) != "", "repro.inherit = %s 거부" % str(bad))
	check(SimSnapshot.CONFIG_KEYS_ADDED.has("repro.inherit"), "repro.inherit 는 옛 설정용 CONFIG_KEYS_ADDED 에 있음")
	var cb := SimConfig.build("chance_baseline", {})
	check(cb.error == "" and str(cb.config.repro.inherit) == SimWorld.INHERIT_RANDOM, "예설정 chance_baseline = repro.inherit random")
	done()


## 우연 기준(DESIGN-v0.2 11.3·14.1 검사 기준 6): random 이면 자식 유전체 = 같은 rng_life 상태에서 SimBrain.random_genome 이 뽑을 값
## (부모 교차와 다름, 크기·감지 = traits.*_init, 색은 균등 뽑기), 혼자 분열도. 같은 씨앗 두 번 같은 해시, genome 이면 금 값(test_v01_golden).
func test_chance_baseline() -> void:
	for asexual: bool in [false, true]:
		var wd := empty_world({"mutation.rate": 0.0, "repro.inherit": "random", "repro.asexual_when_alone": asexual})
		var p := grass_spot(wd)
		add_slime(wd, p, 0.9, 100)
		if not asexual:
			add_slime(wd, p + Vector2i(1, 0), 0.9, 100)
		var t := wd._to
		for i in wd.population():
			wd.s_genome[i * wd._G + t + SimBrain.TRAIT_SIZE] = float(wd.cfg.traits.size_max)
			wd.s_genome[i * wd._G + t + SimBrain.TRAIT_SENSE] = float(wd.cfg.traits.sense_max)
		var probe := SimRng.new()
		probe.set_state_string(wd.rng_life.get_state_string())
		var want := SimBrain.random_genome(wd.cfg, wd.L, probe)
		var n0 := wd.population()
		wd.s_dead.fill(0)
		wd._reproduce()
		var k := wd.index_of_id(n0)
		var gc := wd.s_genome.slice(k * wd._G, (k + 1) * wd._G) if k != -1 else PackedFloat32Array()
		var from_parents := true
		for gi in wd._G:
			var any_parent := false
			for pi in n0:
				if gc.size() == wd._G and gc[gi] == wd.s_genome[pi * wd._G + gi]:
					any_parent = true
			from_parents = from_parents and any_parent
		check(k != -1 and gc == want and not from_parents, "%s: 자식 유전체 = 같은 난수 상태의 random_genome(부모 교차와 다름)" % ("혼자 분열" if asexual else "짝"))
		check(k != -1 and gc[t + SimBrain.TRAIT_SIZE] == float(wd.cfg.traits.size_init) and gc[t + SimBrain.TRAIT_SENSE] == float(wd.cfg.traits.sense_init)
				and wd.lin_pa[n0] == 0 and wd.lin_pb[n0] == (SimWorld.NO_PARENT if asexual else 1) and wd.lin_gen[n0] == 1,
				"%s: 자식 크기·감지 = traits.*_init(부모는 최대값), 부모·세대 기록은 그대로" % ("혼자 분열" if asexual else "짝"))
	var a := world({}, 3, "chance_baseline")
	a.step_n(600)
	var b := world({}, 3, "chance_baseline")
	b.step_n(600)
	var g := world({}, 3)
	g.step_n(600)
	check(a.total_births > 0 and a.history_hash == b.history_hash and SimSnapshot.to_text(a) == SimSnapshot.to_text(b) and a.history_hash != g.history_hash,
			"chance_baseline·씨앗 3·600틱: 같은 씨앗 두 번 같은 해시·전체 상태(출생 %d), genome 세계와 다른 해시" % a.total_births)
	done()


# ───────────────────────── v0.2 1단계: 성장 + 스스로 학습(DESIGN-v0.2 14.2) ─────────────────────────

## 생애 단계 경계 표(14.2 검사 기준 10, DESIGN-v0.2 2.1): [나이, 수명, 성숙, adult_frac, old_frac, 기대 단계, 설명].
const LIFE_STAGE_TABLE := [
	[29, 200, 30, 0.4, 0.8, SimBrain.LIFE_JUVENILE, "나이 29(성숙 30 전)"],
	[30, 200, 30, 0.4, 0.8, SimBrain.LIFE_YOUNG, "나이 30(성숙)"],
	[79, 200, 30, 0.4, 0.8, SimBrain.LIFE_YOUNG, "나이 79(0.4 × 200 전)"],
	[80, 200, 30, 0.4, 0.8, SimBrain.LIFE_ADULT, "나이 80(= 0.4 × 200)"],
	[159, 200, 30, 0.4, 0.8, SimBrain.LIFE_ADULT, "나이 159(0.8 × 200 전)"],
	[160, 200, 30, 0.4, 0.8, SimBrain.LIFE_OLD, "나이 160(= 0.8 × 200)"],
	[29, 200, 30, 0.1, 0.8, SimBrain.LIFE_JUVENILE, "adult 0.1 × 200 < 성숙: 나이 29"],
	[30, 200, 30, 0.1, 0.8, SimBrain.LIFE_ADULT, "adult 0.1 × 200 < 성숙: 나이 30 은 젊은 없이 어른"],
	[25, 200, 30, 0.05, 0.1, SimBrain.LIFE_JUVENILE, "old 0.1 × 200 < 성숙: 나이 25 는 어린"],
	[30, 200, 30, 0.05, 0.1, SimBrain.LIFE_OLD, "old 0.1 × 200 < 성숙: 나이 30 은 어린 다음 바로 늙은"],
	[0, 200, 0, 0.4, 0.8, SimBrain.LIFE_YOUNG, "성숙 0: 나이 0 은 젊은"],
	[100, 250, 30, 0.4, 0.8, SimBrain.LIFE_ADULT, "수명 250(흔들림): 나이 100 = 0.4 × 250"],
]
## 몸 자람 검사의 유전자 크기(1 이 아닌 값 — f × 유전자가 f 와 다르게).
const GROW_GENE_SIZE := 1.3
## 손 계산 갱신(검사 기준 3)의 은닉 수·고리 길이(정적 함수는 이 값을 인자로 받음 — 세계 설정과 따로).
const HAND_HID := 2
const HAND_RING := 4


## 생애 단계(14.2 범위 1·검사 기준 10): 경계 표, 세계의 life_stage_of = 정적 판정(세계 설정의 성숙·비율), 시계열 stage_* 의 합 = 개체 수,
## 관계 검사(adult_frac ≤ old_frac).
func test_life_stage() -> void:
	check(SimBrain.LIFE_STAGE_NAMES == ["어린", "젊은", "어른", "늙은"] and SimRecorder.LIFE_STAGE_COLUMNS
			== ["stage_juvenile", "stage_young", "stage_adult", "stage_old"], "생애 단계 이름 4개(어린·젊은·어른·늙은) = 시계열 stage_* 4열 순서")
	var wrong := PackedStringArray()
	for r in LIFE_STAGE_TABLE:
		var got := SimBrain.life_stage(r[0], r[1], r[2], r[3], r[4])
		if got != r[5]:
			wrong.append("%s → %s(기대 %s)" % [r[6], SimBrain.LIFE_STAGE_NAMES[got], SimBrain.LIFE_STAGE_NAMES[r[5]]])
	check(wrong.is_empty(), "생애 단계 경계 표 %d줄(29/30·79/80·159/160, 젊은 구간이 비는 경우, 어린 다음 바로 늙은): %s" % [LIFE_STAGE_TABLE.size(), "; ".join(wrong)])
	var wd := world({"life.adult_frac": 0.3, "life.old_frac": 0.6}, 4)
	wd.step_n(150)
	var mat := int(wd.cfg.repro.maturity)
	var bad := 0
	for i in wd.population():
		if wd.life_stage_of(i) != SimBrain.life_stage(wd.s_age[i], wd.s_max_age[i], mat, 0.3, 0.6):
			bad += 1
	var row := wd.sample()
	var total := 0
	var all_seen := true
	for col in SimRecorder.LIFE_STAGE_COLUMNS:
		total += int(row[col])
		all_seen = all_seen and int(row[col]) > 0
	check(bad == 0 and total == wd.population() and all_seen,
			"세계(adult 0.3·old 0.6·150틱): life_stage_of = 정적 판정(틀린 개체 %d), stage_* 합 %d = 개체 %d, 네 단계 모두 있음(%s)" % [
			bad, total, wd.population(), str([row.stage_juvenile, row.stage_young, row.stage_adult, row.stage_old])])
	var e1 := str(SimConfig.build("default", {"life.adult_frac": 0.9}).error)
	check(e1.contains("life.adult_frac") and e1.contains("life.old_frac"), "관계 검사: 어른 시작 0.9 > 늙음 시작 0.8 거부: " + e1)
	check(SimConfig.build("default", {"life.adult_frac": 0.8}).error == "", "어른 시작 = 늙음 시작(0.8)은 받음(어른 구간이 빔)")
	done()


## 몸 자람(14.2 범위 2·검사 기준 9, DESIGN-v0.2 2.2): 갓 태어난 크기 = f × 유전자, 매 틱 유전자 × g(나이), 성숙 때 유전자 그대로,
## 최대 에너지가 따라감, 자식 에너지 상한 = 태어날 때의 최대 에너지(넘치는 몫은 번식 손실 장부), 초기 개체(나이 0~40) 에너지 =
## 비율 × 그 나이의 최대 ≤ 최대, mean_size 는 유전자 크기 평균(v0.1 뜻)·mean_size_eff 는 실제 크기 평균, 끄면 v0.1 그대로.
func test_body_growth() -> void:
	check(SimBrain.growth_factor(0, 30, 0.5) == 0.5 and SimBrain.growth_factor(15, 30, 0.5) == 0.75 and SimBrain.growth_factor(30, 30, 0.5) == 1.0
			and SimBrain.growth_factor(31, 30, 0.1) == 1.0 and SimBrain.growth_factor(5, 0, 0.5) == 1.0,
			"크기 비율 g: 나이 0 → 0.5, 15 → 0.75, 30(성숙) → 1, 성숙 뒤 1(f 0.1 이어도 정확히), 성숙 0 이면 1")
	var wd := empty_world({"body.grow_enabled": true, "mutation.rate": 0.0})
	var f := float(wd.cfg.body.birth_size_frac)
	var mat := int(wd.cfg.repro.maturity)
	var eps := float(wd.cfg.body.energy_per_size)
	var p := grass_spot(wd)
	var g := SimBrain.random_genome(wd.cfg, wd.L, wd.rng_life)
	g[wd._to + SimBrain.TRAIT_SIZE] = GROW_GENE_SIZE
	var gene := float(g[wd._to + SimBrain.TRAIT_SIZE])
	var id := wd._spawn(p.x, p.y, 1, g, 0.0, 0, SimWorld.NO_PARENT, SimWorld.NO_PARENT, 0)
	var i := wd.index_of_id(id)
	check(wd.s_size[i] == gene * f and wd.s_emax[i] == eps * (gene * f) and float(wd.lin_size[id]) == gene,
			"갓 태어난 크기 %.4f = f %.2f × 유전자 %.4f, 최대 에너지 = 몸 크기 × energy_per_size(계통 size 는 유전자)" % [wd.s_size[i], f, gene])
	wd.s_max_age[i] = 1000000
	var bad := PackedStringArray()
	var prev := wd.s_size[i]
	var grew := true
	while wd.s_age[wd.index_of_id(id)] < mat + 3:
		i = wd.index_of_id(id)
		wd.s_energy[i] = 0.5 * wd.s_emax[i]
		wd.step()
		i = wd.index_of_id(id)
		var want := gene * SimBrain.growth_factor(wd.s_age[i], mat, f)
		if (wd.s_size[i] != want or wd.s_emax[i] != eps * want) and bad.size() < 3:
			bad.append("나이 %d: 크기 %s(기대 %s)" % [wd.s_age[i], str(wd.s_size[i]), str(want)])
		if wd.s_age[i] <= mat and wd.s_size[i] <= prev:
			grew = false
		prev = wd.s_size[i]
	check(bad.is_empty() and grew and wd.s_size[i] == gene and wd.s_emax[i] == eps * gene,
			"매 틱 크기 = 유전자 × g(나이)·최대 에너지가 따라감, 성숙(%d틱)까지 늘고 그 뒤 유전자 크기 그대로(%s)" % [mat, "; ".join(bad)])
	# 자식: 크기 = f × 유전자, 에너지는 태어날 때의 최대 에너지로 잘림(번식 비용 0.9 — 넘치게)
	var w2 := empty_world({"body.grow_enabled": true, "mutation.rate": 0.0, "repro.cost_frac": 0.9})
	var p2 := grass_spot(w2)
	add_slime(w2, p2, 1.0, 100)
	add_slime(w2, p2 + Vector2i(1, 0), 1.0, 100)
	var n0 := w2.population()
	w2.s_dead.fill(0)
	w2._reproduce()
	var k := w2.index_of_id(n0)
	var cg := float(w2.s_genome[k * w2._G + w2._to + SimBrain.TRAIT_SIZE]) if k != -1 else 0.0
	check(k != -1 and w2.s_size[k] == cg * f and w2.s_energy[k] == w2.s_emax[k] and w2.s_emax[k] == eps * (cg * f)
			and w2.led_repro_loss > 0.0 and absf(w2.total_energy() - w2.ledger_expected()) < 1e-9,
			"자식 크기 = f × 유전자, 자식 에너지 = 태어날 때의 최대 에너지 %.2f(넘친 몫은 번식 손실 장부 — 장부 오차 0)" % (w2.s_emax[k] if k != -1 else -1.0))
	# 초기 개체(나이 0~population.initial_age_spread): 처음 에너지 = start_energy_frac × 그 나이의 최대 에너지
	var w3 := world({"body.grow_enabled": true}, 3)
	var sf := float(w3.cfg.body.start_energy_frac)
	var over := 0
	var small := 0
	for j in w3.population():
		if w3.s_energy[j] > w3.s_emax[j] or w3.s_energy[j] != sf * w3.s_emax[j]:
			over += 1
		if w3.s_age[j] < mat and w3.s_size[j] < float(w3.s_genome[j * w3._G + w3._to + SimBrain.TRAIT_SIZE]):
			small += 1
	check(over == 0 and small > 0, "초기 개체 %d마리(나이 0~%d)의 에너지 = %.1f × 그 나이의 최대 ≤ 최대(어긋난 개체 %d, 작은 몸 %d)" % [
			w3.population(), int(w3.cfg.population.initial_age_spread), sf, over, small])
	var r3 := w3.sample()
	check(float(r3.mean_size) == w3._mean_gene_size() and float(r3.mean_size_eff) == w3.mean_of(w3.s_size) and float(r3.mean_size_eff) < float(r3.mean_size),
			"켜면 mean_size = 유전자 크기 평균 %.4f(v0.1 뜻), mean_size_eff = 실제 크기 평균 %.4f" % [float(r3.mean_size), float(r3.mean_size_eff)])
	var w4 := world({}, 3)
	var same := 0
	for j in w4.population():
		if w4.s_size[j] == float(w4.s_genome[j * w4._G + w4._to + SimBrain.TRAIT_SIZE]):
			same += 1
	var r4 := w4.sample()
	check(same == w4.population() and float(r4.mean_size) == float(r4.mean_size_eff), "끄면 크기 = 유전자 크기, mean_size = mean_size_eff(v0.1 그대로)")
	done()


## 유전체 구간과 난수 뽑기(14.2 범위 3·검사 기준 1·2, DESIGN-v0.2 3.7): 학습 끔 163·켬 171(η 8 은 특성 뒤)·기억 2 와 함께 203,
## 무작위 첫 유전체의 η = eta_init(난수 없이 — 뽑기 수 그대로), 교차는 η 를 유전자마다 부모 한쪽에서, 돌연변이율 0 이면 그대로, 범위
## [0, eta_max]. 번식 1번당 rng_life 뽑기 수: 끔 = v0.1(은닉 + 특성 + 가중치 + 특성 + 방향 + 수명 = 176), 켬 = + η 교차 8 + 돌연변이 8.
func test_learn_genome() -> void:
	var c0 := cfg_with()
	var c1 := cfg_with({"learn.enabled": true})
	var L0 := SimBrain.layout(c0)
	var L1 := SimBrain.layout(c1)
	var L2 := SimBrain.layout(cfg_with({"learn.enabled": true, "brain.memory_units": 2}))
	check(L0.genes == 163 and L0.eta_len == 0 and L0.n_act == SimBrain.BASE_OUTPUTS and L0.eta_offset == L0.trait_offset + SimBrain.TRAIT_GENES,
			"학습 끔: 유전자 163, η 구간 길이 0(배치 [W1][W2][특성 3])")
	check(L1.genes == 171 and L1.eta_len == SimBrain.ETA_GENES and L1.eta_offset == 163 and L1.trait_offset == L0.trait_offset and L2.genes == 203,
			"학습 켬: 171 = 163 + η 8(특성 뒤 163 부터), 기억 2 와 함께 203")
	var ra := SimRng.new(9)
	var rb := SimRng.new(9)
	var g0 := SimBrain.random_genome(c0, L0, ra)
	var g1 := SimBrain.random_genome(c1, L1, rb)
	var eta_ok := true
	for k in SimBrain.ETA_GENES:
		eta_ok = eta_ok and g1[L1.eta_offset + k] == float(PackedFloat32Array([float(c1.learn.eta_init)])[0])
	check(eta_ok and ra.get_state_string() == rb.get_state_string() and g1.slice(0, L0.genes) == g0,
			"무작위 첫 유전체: η = eta_init, 난수를 쓰지 않아 앞 163 유전자·뽑기 수가 학습 끔과 같음")
	var pa := g1.duplicate()
	var pb := g1.duplicate()
	for k in SimBrain.ETA_GENES:
		pa[L1.eta_offset + k] = 0.125
		pb[L1.eta_offset + k] = 0.375
	var mixed := false
	var from_parent := true
	var rng := SimRng.new(4)
	for trial in 20:
		var ch := SimBrain.crossover(L1, pa, pb, rng)
		var seen := {}
		for k in SimBrain.ETA_GENES:
			var v: float = ch[L1.eta_offset + k]
			from_parent = from_parent and (v == 0.125 or v == 0.375)
			seen[v] = true
		mixed = mixed or seen.size() == 2
	check(from_parent and mixed, "교차: η 는 유전자마다 부모 한쪽에서(한 자식 안에서도 섞임)")
	var pa0 := pa.duplicate()
	var gm := pa.duplicate()
	SimBrain.mutate(cfg_with({"learn.enabled": true, "mutation.rate": 0.0}), L1, gm, rng)
	var cfg_big := cfg_with({"learn.enabled": true, "mutation.rate": 1.0, "mutation.sigma": 50.0})
	var in_range := true
	var moved := false
	for t in 5:
		SimBrain.mutate(cfg_big, L1, pa, rng)
		for k in SimBrain.ETA_GENES:
			var v := float(pa[L1.eta_offset + k])
			in_range = in_range and v >= 0.0 and v <= float(cfg_big.learn.eta_max)
			moved = moved or v != 0.125
	check(gm == pa0, "돌연변이율 0 → η(와 모든 유전자) 그대로")
	check(in_range and moved, "돌연변이: η 가 바뀌고 [0, eta_max] 로 잘림")
	# 번식 1번당 rng_life 뽑기 수(돌연변이율 0 — 정규 근사 뽑기 없음)
	var hid := int(c0.brain.hidden)
	var v01_draws: int = hid + SimBrain.TRAIT_GENES + int(L0.trait_offset) + SimBrain.TRAIT_GENES + 2
	var draws := []
	for on: bool in [false, true]:
		var w := empty_world({"learn.enabled": on, "mutation.rate": 0.0})
		var p := grass_spot(w)
		add_slime(w, p, 0.9, 100)
		add_slime(w, p + Vector2i(1, 0), 0.9, 100)
		var probe := SimRng.new()
		probe.set_state_string(w.rng_life.get_state_string())
		var want := v01_draws + (2 * SimBrain.ETA_GENES if on else 0)
		for k in want:
			probe.uniform()
		w.s_dead.fill(0)
		w._reproduce()
		draws.append(w.population() == 3 and probe.get_state_string() == w.rng_life.get_state_string())
	check(draws[0] and draws[1], "번식 1번당 rng_life 뽑기: 학습 끔 %d번 = v0.1, 켬 %d번(η 교차·돌연변이 + 16) — %s" % [v01_draws,
			v01_draws + 2 * SimBrain.ETA_GENES, str(draws)])
	done()


## 손 계산 갱신(14.2 검사 기준 3, DESIGN-v0.2 3.5): 정한 고리(행동·보정 e·은닉)·δ·배수·η·λ 로 한 번 갱신한 배운 두뇌의 비트가 손으로 셈한
## 값과 같음(2진 소수만 써서 반올림 없이 — 자르기 한 칸 포함). 세계 경로(_learn)도 같은 식(정적 함수와 비트 일치, 기준선·어린 동안 배운 양·
## 갱신 수), 놀람이 문턱보다 작으면 고치지 않음. 보정 e: diag_e 손 값과, 세계가 판단 때 고리에 쓰는 e = diag_e(exact·none 각각).
func test_learn_update_hand() -> void:
	check(SimBrain.diag_e(-1.0, 0.5, 4, true) == 1.0 and SimBrain.diag_e(0.0, 0.25, 4, true) == 3.0 and SimBrain.diag_e(-3.0, 0.5, 2, true) == 0.25
			and SimBrain.diag_e(1.0, 0.5, 4, true) == 0.5 * 4.0 * (1.0 / 6.0) and SimBrain.diag_e(1.0, 0.25, 4, false) == 0.75,
			"보정 e: exact = (1 − π)·k·d(o) — o −1·0·−3·1 손 값, none = 1 − π")
	var lam := SimBrain.decay_table(0.5, HAND_RING)
	check(lam == PackedFloat64Array([1.0, 0.5, 0.25, 0.125]) and SimBrain.decay_table(0.8, 8)[7] == 0.8 * 0.8 * 0.8 * 0.8 * 0.8 * 0.8 * 0.8,
			"λᵐ 표 = 거듭 곱(0.5 → 1·0.5·0.25·0.125, 0.8⁷)")
	# 고리(다음 자리 1): m 0 → 칸 0(행동 3), m 1 → 칸 3(행동 5), m 2 → 칸 2(행동 3), m 3 → 칸 1(빈칸)
	var ring_a := PackedInt32Array([3, SimWorld.RING_EMPTY, 3, 5])
	var ring_e := PackedFloat32Array([1.0, 9.0, 0.5, 0.25])
	var ring_h := PackedFloat32Array([0.5, -0.25, 1.0, 1.0, 0.25, 0.5, 1.0, -0.5])
	var w2 := PackedFloat64Array()
	w2.resize(SimBrain.BASE_OUTPUTS * HAND_HID)
	w2.fill(0.75)
	w2[3 * HAND_HID] = 0.125
	w2[3 * HAND_HID + 1] = -0.25
	w2[5 * HAND_HID] = 3.9375
	w2[5 * HAND_HID + 1] = 0.0
	var genome := PackedFloat32Array()
	genome.resize(SimBrain.BASE_OUTPUTS)
	genome[3] = 0.25
	genome[5] = 4.0
	var moved := SimBrain.learn_update(w2, 0, HAND_HID, ring_a, ring_e, ring_h, 0, HAND_RING, 1, 0.5, 1.0, genome, 0, lam, 4.0)
	# 손 계산: c = δ 0.5 × 배수 1 × η × λᵐ × e. m0: c = 0.125 → 행동 3 += [0.0625, −0.03125], m1: c = 0.5 × 4 × 0.5 × 0.25 = 0.25 →
	# 행동 5 += [0.25, −0.125](3.9375 + 0.25 = 4.1875 → 자름 4), m2: c = 0.5 × 0.25 × 0.25 × 0.5 = 0.015625 → 행동 3 += [0.00390625, 0.0078125]
	var want := PackedFloat64Array()
	want.resize(SimBrain.BASE_OUTPUTS * HAND_HID)
	want.fill(0.75)
	want[3 * HAND_HID] = 0.19140625
	want[3 * HAND_HID + 1] = -0.2734375
	want[5 * HAND_HID] = 4.0
	want[5 * HAND_HID + 1] = -0.125
	check(w2 == want and moved == 0.29296875, "정적 learn_update: 손 계산 비트(행동 3 = %s, 행동 5 = %s — 자른 칸 포함, 바뀐 양 %s = 0.29296875, 빈칸·다른 행은 그대로)" % [
			str(w2.slice(3 * HAND_HID, 4 * HAND_HID)), str(w2.slice(5 * HAND_HID, 6 * HAND_HID)), str(moved)])
	# 세계 경로: 한 개체의 고리·배운 두뇌·η·기준선을 정하고 한 틱 쉬게 함(판단 없이 — 고리는 그대로) → 보상 δ = −비용 ÷ 한입 − 기준선 0.5
	# (문턱을 넘는 음의 놀람)으로 _act 가 고친 배운 두뇌 = 같은 δ 의 정적 learn_update 비트, 기준선 += β δ, 어린 동안 배운 양(어린 단계만)
	for case in [["어린", 5, true], ["어른", 120, false]]:
		var wd := empty_world({"learn.enabled": true})
		var p := grass_spot(wd)
		var i := wd.index_of_id(add_slime(wd, p, 0.5, case[1], 1))
		wd.s_max_age[i] = 200
		var hn := wd._ring
		var nh := wd._n_hid
		for s in hn:
			wd.s_ring_a[i * hn + s] = (s * 3) % SimBrain.BASE_OUTPUTS if s != 2 else SimWorld.RING_EMPTY
			wd.s_ring_e[i * hn + s] = 0.5 + 0.25 * float(s)
			for j in nh:
				wd.s_ring_h[(i * hn + s) * nh + j] = 0.125 * float((s + j) % 5) - 0.25
		wd.s_ring_pos[i] = 3
		for k in SimBrain.ETA_GENES:
			wd.s_genome[i * wd._G + wd._eta_o + k] = 0.0625 * float(k + 1)
		wd.s_rbar[i] = 0.5
		var e_before := wd.s_energy[i]
		var size := wd.s_size[i]
		var st := SimBrain.life_stage(wd.s_age[i], wd.s_max_age[i], wd._maturity, wd._adult_frac, wd._old_frac)
		var before := wd.s_w2.duplicate()
		var ref := wd.s_w2.duplicate()
		act_once(wd, i, SimBrain.ACT_REST, wd.tick + 1)
		var delta := (wd.s_energy[i] - e_before) / (float(wd.cfg.eat.bite) * float(wd.cfg.eat.efficiency) * size) - 0.5
		var mv := SimBrain.learn_update(ref, i * wd._w2n, nh, wd.s_ring_a, wd.s_ring_e, wd.s_ring_h, i * hn, hn, 3, delta,
				float(wd.cfg.learn.stage_mult[st]), wd.s_genome, i * wd._G + wd._eta_o, SimBrain.decay_table(float(wd.cfg.learn.decay), hn),
				float(wd.cfg.brain.weight_clamp))
		check(ref != before and wd.s_w2 == ref and wd.s_rbar[i] == 0.5 + float(wd.cfg.learn.baseline_rate) * delta and wd.period_learn == 1
				and wd.s_dw_juv[i] == (mv if case[2] else 0.0),
				"세계 경로(%s, 단계 %s, 쉬기 δ %.4f) = 정적 learn_update 비트, 기준선 += β δ, 갱신 1번, 어린 동안 배운 양 %s(정적 %s)" % [case[0],
				SimBrain.LIFE_STAGE_NAMES[st], delta, str(wd.s_dw_juv[i]), str(mv)])
		# 놀람이 문턱보다 작으면 고치지 않음(기준선은 고침)
		var w_before := wd.s_w2.duplicate()
		wd.s_rbar[i] = 0.0
		var e1 := wd.s_energy[i]
		act_once(wd, i, SimBrain.ACT_REST, wd.tick + 1)
		var d1 := (wd.s_energy[i] - e1) / (float(wd.cfg.eat.bite) * float(wd.cfg.eat.efficiency) * size)
		check(absf(d1) < float(wd.cfg.learn.min_surprise) and wd.s_w2 == w_before and wd.period_learn == 1
				and wd.s_rbar[i] == float(wd.cfg.learn.baseline_rate) * d1,
				"%s: 놀람 %.4f < 문턱 %.2f 이면 배운 두뇌 그대로(기준선만 고침)" % [case[0], d1, float(wd.cfg.learn.min_surprise)])
		var row := wd.sample()
		check(int(row.learn_events) == 1 and wd.period_learn == 0 and float(row.rbar_mean) == wd.s_rbar[i],
				"%s: sample() 이 구간 학습 갱신 수(1)·평균 기준선을 줄에 싣고 갱신 수를 0 으로 되돌림" % case[0])
	# 판단 때 고리 쓰기: 보정 e = diag_e(o, π, k)(exact·none), 행동·은닉(float32)·다음 자리
	for mode in [SimBrain.DIAG_EXACT, SimBrain.DIAG_NONE]:
		var wl := world({"learn.enabled": true, "learn.diag_factor": mode}, 2)
		wl.step_n(20)
		wl.sample()
		var bad := 0
		var nz := 0
		var pmax_sum := 0.0
		var calls := 0
		for i in mini(wl.population(), 40):
			var pos := wl.s_ring_pos[i]
			var a := wl._think(i, wl.s_x[i], wl.s_y[i], wl.s_y[i] * wl.w + wl.s_x[i], wl.s_head[i], wl.s_emax[i])
			var slot := i * wl._ring + pos
			var e := SimBrain.diag_e(wl._out[a], wl._wts[a] / wl._pick_total, wl._sharpness, mode == SimBrain.DIAG_EXACT)
			var hs := PackedFloat32Array()
			for v in wl._hid:
				hs.append(v)
			if wl.s_ring_a[slot] != a or wl.s_ring_e[slot] != PackedFloat32Array([e])[0] or wl.s_ring_h.slice(slot * wl._n_hid, (slot + 1) * wl._n_hid) != hs \
					or wl.s_ring_pos[i] != (pos + 1) % wl._ring:
				bad += 1
			if e != 1.0 - wl._wts[a] / wl._pick_total:
				nz += 1
			var top := 0.0
			for q in SimBrain.BASE_OUTPUTS:
				top = maxf(top, wl._wts[q])
			pmax_sum += top / wl._pick_total
			calls += 1
		check(bad == 0 and (nz > 0) == (mode == SimBrain.DIAG_EXACT), "diag_factor %s: 판단 때 고리 = (행동, diag_e(o, π, k), 은닉 float32), 다음 자리 + 1(틀린 개체 %d)" % [mode, bad])
		var pm := float(wl.sample().pmax_mean)
		check(calls > 0 and pm == pmax_sum / float(calls) and pm >= 1.0 / float(SimBrain.BASE_OUTPUTS) and pm <= 1.0 and wl.period_think == 0
				and wl.period_pmax == 0.0, "diag_factor %s: pmax_mean %.4f = 판단 %d번의 가장 큰 행동 확률 평균(sample 뒤 0 으로)" % [mode, pm, calls])
	done()


## "학습이 고른다"(14.2 검사 기준 4): 개체 하나(수명 1000), 매 틱 시작에 에너지 = 0.5 × 최대, 발밑 먹이를 plants.max_food 로 다시 채우는
## 고정 장면 200틱. 200틱 전·후의 먹기 확률을 같은 고정 입력(_in 사본)에서 SimBrain.forward_phen 으로 견줌: 켬이면 처음보다 큼,
## freeze 면 처음과 같음(비트).
func test_learning_picks() -> void:
	var res := {}
	for freeze: bool in [false, true]:
		var wd := empty_world({"learn.enabled": true, "learn.freeze": freeze, "life.max_age": 1000})
		var p := grass_spot(wd)
		var id := add_slime(wd, p, 0.5, 100, 1)
		var i := wd.index_of_id(id)
		var c := p.y * wd.w + p.x
		var mf := float(wd.cfg.plants.max_food)
		wd.food[c] = mf
		var probe: SimWorld = SimSnapshot.from_text(SimSnapshot.to_text(wd)).world
		probe._think(i, p.x, p.y, c, probe.s_head[i], probe.s_emax[i])
		var fixed := probe._in.duplicate()
		var before: float = SimBrain.forward_phen(wd.L, wd.s_genome, i * wd._G, wd.s_w2, i * wd._w2n, fixed, wd._sharpness).probs[SimBrain.ACT_EAT]
		var eats := 0
		for t in 200:
			i = wd.index_of_id(id)
			wd.s_energy[i] = 0.5 * wd.s_emax[i]
			wd.food[wd.s_y[i] * wd.w + wd.s_x[i]] = mf
			wd.step()
			i = wd.index_of_id(id)
			if wd.s_last_action[i] == SimBrain.ACT_EAT:
				eats += 1
		i = wd.index_of_id(id)
		var after: float = SimBrain.forward_phen(wd.L, wd.s_genome, i * wd._G, wd.s_w2, i * wd._w2n, fixed, wd._sharpness).probs[SimBrain.ACT_EAT]
		res[freeze] = [before, after, eats, wd.period_learn]
	check(res[false][1] > res[false][0], "켬: 200틱 뒤 고정 입력의 먹기 확률 %.4f > 처음 %.4f(먹기 %d번)" % [res[false][1], res[false][0], res[false][2]])
	check(res[true][1] == res[true][0] and res[true][0] == res[false][0], "freeze: 200틱 뒤 먹기 확률 %.4f = 처음 %.4f(비트 — 먹기 %d번, 갱신 %d번)" % [
			res[true][1], res[true][0], res[true][2], res[true][3]])
	done()


## 자르기(14.2 검사 기준 5): 모든 배운 가중치 abs(w) ≤ brain.weight_clamp — 학습률을 크게 해(비용 0 — η 100 의 학습 비용은 굶어 죽게 함)
## 자르기가 실제로 일어나는 세계와 learn_basic.
func test_learn_clamp() -> void:
	for sets in [{"learn.eta_init": 100.0, "learn.eta_max": 100.0, "learn.min_surprise": 0.0, "learn.cost_per_eta": 0.0}, {}]:
		var wd := world(sets, 2, "learn_basic")
		wd.step_n(300)
		var clamp_w := float(wd.cfg.brain.weight_clamp)
		var top := 0.0
		var at_edge := 0
		for v in wd.s_w2:
			top = maxf(top, absf(v))
			if absf(v) == clamp_w:
				at_edge += 1
		var big: bool = sets.has("learn.eta_init")
		check(wd.s_w2.size() > 0 and top <= clamp_w and (at_edge > 0 or not big), "%s: 배운 가중치 %d개 모두 abs ≤ %.1f(최대 %.4f, 경계 값 %d개)" % [
				"η 100·문턱 0" if big else "learn_basic", wd.s_w2.size(), clamp_w, top, at_edge])
	done()


## 장부(14.2 검사 기준 6, DESIGN-v0.2 3.6·12.2): 학습 비용을 낸 세계의 에너지 장부, led_learn = 개체·틱마다 학습 비용의 합, 쉬어도 줄지
## 않음(쉬기 배수 뒤에 더함), learn.cost_per_eta = 0 이면 led_learn = 0, 먹은 양 장부.
func test_learn_ledger() -> void:
	var wd := world({}, 9, "learn_basic")
	var worst := 0.0
	var expect := 0.0
	for k in 600:
		expect += wd.sum_of(wd.s_clearn)
		wd.step()
		worst = maxf(worst, absf(wd.total_energy() - wd.ledger_expected()))
	check(worst < 1e-6 and wd.total_births > 0 and wd.total_deaths > 0, "learn_basic·씨앗 9·600틱: 에너지 장부 오차 %s(학습 비용 포함)" % String.num_scientific(worst))
	check(wd.led_learn > 0.0 and wd.led_learn < wd.led_spent and absf(wd.led_learn - expect) <= 1e-9 * expect,
			"led_learn %.4f = 개체·틱마다 학습 비용의 합 %.4f(< led_spent %.1f)" % [wd.led_learn, expect, wd.led_spent])
	check(eaten_gap(wd) < 1e-9, "먹은 양 장부 상대 오차 %s" % String.num_scientific(eaten_gap(wd)))
	# 쉬기: 비용 = (기본 대사 × 크기 + 감지 비용 × 반경) × 쉬기 배수 + 학습 비용(η 평균 × cost_per_eta)
	var we := empty_world({"learn.enabled": true})
	var p := grass_spot(we)
	var i := we.index_of_id(add_slime(we, p, 0.5, 100, 1))
	for k in SimBrain.ETA_GENES:
		we.s_genome[i * we._G + we._eta_o + k] = 0.25
	we.s_clearn[i] = float(we.cfg.learn.cost_per_eta) * we.eta_mean_of_genome(we.s_genome, i * we._G)
	var spent0 := we.led_spent
	act_once(we, i, SimBrain.ACT_REST, we.tick + 1)
	var base := (float(we.cfg.metab.base) * we.s_size[i] + float(we.cfg.metab.sense_cost) * float(we.s_sense[i])) * float(we.cfg.metab.rest_factor)
	var c_learn := float(we.cfg.learn.cost_per_eta) * 0.25
	check(spent0 == 0.0 and we.led_spent == base + c_learn and we.led_learn == c_learn,
			"쉬기 한 틱의 비용 %.5f = 대사 × 쉬기 배수 %.5f + 학습 비용 %.4f(η 0.25 × %.2f — 쉬어도 줄지 않음)" % [we.led_spent, base, c_learn,
			float(we.cfg.learn.cost_per_eta)])
	var w0 := world({"learn.cost_per_eta": 0.0}, 9, "learn_basic")
	w0.step_n(100)
	check(w0.led_learn == 0.0 and absf(w0.total_energy() - w0.ledger_expected()) < 1e-6, "learn.cost_per_eta = 0 이면 led_learn = 0")
	done()


## 결정성·왕복(14.2 검사 기준 7): 같은 씨앗 두 번 같은 글, 500 + 500 = 1,000(새 열이 든 timeseries.csv·학습 열이 든 lineage.csv·
## 전체 상태·해시), 새 상태 변수가 모두 왕복, 해시 꼬리(Σ 배운 두뇌·Σ 기준선 — 바꾸면 해시가 바뀜), 학습 상태가 틀린 스냅숏 거부.
func test_learn_snapshot() -> void:
	var a := world({}, 5, "learn_basic")
	a.step_n(300)
	var b := world({}, 5, "learn_basic")
	b.step_n(300)
	check(a.history_hash == b.history_hash and SimSnapshot.to_text(a) == SimSnapshot.to_text(b) and a.s_w2.size() > 0,
			"learn_basic·씨앗 5·300틱: 같은 씨앗 두 번 같은 해시·전체 상태 글")
	var wd := world({}, 21, "learn_basic")
	var rec := SimRecorder.new()
	rec.record(wd)
	var snaps := {}
	var every := int(wd.cfg.record.every)
	while wd.tick < 1000:
		wd.step()
		if wd.tick % every == 0:
			rec.record(wd)
		if wd.tick == 500 or wd.tick == 510:
			snaps[wd.tick] = SimSnapshot.to_text(wd)
	var learned_rows := 0
	for row in rec.rows:
		if int(row.learn_events) > 0 and float(row.pmax_mean) > 0.0 and float(row.eta_mean) > 0.0 and float(row.dw_mean) > 0.0:
			learned_rows += 1
	check(not wd.is_extinct() and learned_rows > 0, "learn_basic·씨앗 21: 1,000틱 살아 있고 학습 열이 채워진 기록 줄 %d개" % learned_rows)
	for t: int in snaps:
		var r := SimSnapshot.from_text(snaps[t])
		check(r.error == "" and r.world != null, "%d틱 학습 스냅숏 열기: %s" % [t, str(r.error)])
		if r.world == null:
			continue
		var w2: SimWorld = r.world
		var rec2 := SimRecorder.new()
		while w2.tick < 1000:
			w2.step()
			if w2.tick % every == 0:
				rec2.record(w2)
		var want: Array = []
		for row in rec.rows:
			if int(row.tick) > t:
				want.append(row)
		check(want.size() > 0 and csv_of(want, SimRecorder.TIMESERIES_COLUMNS) == csv_of(rec2.rows, SimRecorder.TIMESERIES_COLUMNS)
				and SimRecorder.lineage_csv(w2) == SimRecorder.lineage_csv(wd) and SimSnapshot.to_text(w2) == SimSnapshot.to_text(wd)
				and w2.history_hash == wd.history_hash,
				"%d틱 → 열기 → 1,000틱 = 곧장 1,000틱(timeseries %d열·lineage %d열·전체 상태·해시)" % [t, SimRecorder.TIMESERIES_COLUMNS.size(),
				SimRecorder.LINEAGE_COLUMNS.size()])
	var rt: SimWorld = SimSnapshot.from_text(SimSnapshot.to_text(wd)).world
	var diff: Array[String] = ["복원 실패"]
	if rt != null:
		diff = world_vars_differ(wd, rt)
	check(rt != null and diff.is_empty() and rt.s_w2 == wd.s_w2 and rt.s_ring_h == wd.s_ring_h and rt.lin_assim == wd.lin_assim,
			"학습 세계의 상태 변수 %d개가 모두 왕복(다른 변수: %s)" % [world_state_vars(wd).size(), ", ".join(diff)])
	# 해시 꼬리: 같은 세계 사본의 배운 가중치 하나(또는 기준선 하나)만 바꾸면 다음 해시 검사점이 달라짐, 그대로면 같음
	var hb: SimWorld = SimSnapshot.from_text(SimSnapshot.to_text(wd)).world
	var hc: SimWorld = SimSnapshot.from_text(SimSnapshot.to_text(wd)).world
	var hd: SimWorld = SimSnapshot.from_text(SimSnapshot.to_text(wd)).world
	hc.s_w2[0] += 0.5
	hd.s_rbar[0] += 0.5
	for x: SimWorld in [hb, hc, hd]:
		x._hash_step()
	check(hb.history_hash != hc.history_hash and hb.history_hash != hd.history_hash and SimSnapshot.from_text(SimSnapshot.to_text(wd)).world.history_hash == wd.history_hash,
			"해시 꼬리: 배운 가중치·기준선만 바꿔도 다음 해시가 달라짐(학습 끈 세계의 줄은 v0.1 그대로 — test_v01_golden)")
	# 학습 끈 세계: 학습 배열·계통 학습 열은 빈 배열("")
	var off = JSON.parse_string(SimSnapshot.to_text(world({}, 3)))
	var empty_keys := true
	for k in ["w2", "rbar", "dw_juv", "ring_a", "ring_pos", "ring_e", "ring_h"]:
		empty_keys = empty_keys and str(off.slimes.get(k, "?")) == ""
	for k in ["eta", "dw", "dw_juv", "assim"]:
		empty_keys = empty_keys and str(off.lineage.get(k, "?")) == ""
	check(empty_keys and str(off.stats.get("led_learn", "")) == SimSnapshot.f64_hex(0.0), "학습 끈 세계의 학습 배열은 길이 0(\"\"), 학습 장부 0")
	# 거부(구조가 틀린 학습 스냅숏)
	var text := SimSnapshot.to_text(wd)
	var n := wd.population()
	var ring := wd._ring
	var dead_id := -1
	for id in wd.lin_death.size():
		if wd.lin_death[id] >= 0:
			dead_id = id
			break
	var cases := {
		"slimes.w2 짧음": func(d): d.slimes.w2 = SimSnapshot.b64(wd.s_w2.slice(0, wd._w2n)),
		"slimes.ring_a 행동 8": func(d): d.slimes.ring_a = SimSnapshot.b64(_i32_set(wd.s_ring_a, 0, SimBrain.BASE_OUTPUTS)),
		"slimes.ring_a 행동 -2": func(d): d.slimes.ring_a = SimSnapshot.b64(_i32_set(wd.s_ring_a, 0, -2)),
		"slimes.ring_pos = H": func(d): d.slimes.ring_pos = SimSnapshot.b64(_i32_set(wd.s_ring_pos, n - 1, ring)),
		"slimes.ring_h 없음": func(d): d.slimes.ring_h = "",
		"slimes.rbar NaN": func(d): d.slimes.rbar = SimSnapshot.b64(_nan_tail(n)),
		"slimes.dw_juv 음수": func(d): d.slimes.dw_juv = _f64_set(wd.s_dw_juv, 0, -1.0),
		"lineage.assim 1.5": func(d): d.lineage.assim = SimSnapshot.b64(_f32_set(wd.lin_assim, dead_id, 1.5)),
		"lineage.dw 살아 있는 개체 ≠ 0": func(d): d.lineage.dw = SimSnapshot.b64(_f32_set(wd.lin_dw, wd.s_id[0], 0.5)),
		"lineage.eta 짧음": func(d): d.lineage.eta = SimSnapshot.b64(wd.lin_eta.slice(0, 3)),
		"stats.led_learn > led_spent": func(d): d.stats.led_learn = SimSnapshot.f64_hex(wd.led_spent + 1.0),
		"stats.period_pmax > period_think": func(d): d.stats.period_pmax = SimSnapshot.f64_hex(float(wd.period_think) + 1.0),
		"stats.period_learn 글자": func(d): d.stats.period_learn = "1",
		"learn.enabled 끔(배열 길이가 설정과 다름)": func(d): d.config.learn.enabled = false,
		"learn.ring_len 4(고리 길이가 설정과 다름)": func(d): d.config.learn.ring_len = 4.0,
	}
	var reason := {"slimes.ring_a 행동 8": "행동 번호", "slimes.ring_a 행동 -2": "행동 번호", "slimes.ring_pos = H": "다음 자리",
		"lineage.assim 1.5": "동화", "lineage.dw 살아 있는 개체 ≠ 0": "살아 있는", "stats.led_learn > led_spent": "학습 비용",
		"stats.period_pmax > period_think": "학습 셈", "slimes.dw_juv 음수": "음수"}
	var leaked: Array[String] = []
	for name: String in cases:
		var d = JSON.parse_string(text)
		cases[name].call(d)
		var r = SimSnapshot.from_dict(d)
		if r.get("world") != null or str(r.get("error", "")) == "":
			leaked.append(name)
		elif reason.has(name) and not str(r.error).contains(reason[name]):
			leaked.append("%s(이유 '%s')" % [name, str(r.error)])
	check(dead_id >= 0 and leaked.is_empty(), "구조가 틀린 학습 스냅숏 %d종을 오류 문장으로 거부(샌 것: %s)" % [cases.size(), ", ".join(leaked)])
	done()


static func _i32_set(arr: PackedInt32Array, i: int, v: int) -> PackedInt32Array:
	var a := arr.duplicate()
	a[i] = v
	return a


static func _f32_set(arr: PackedFloat32Array, i: int, v: float) -> PackedFloat32Array:
	var a := arr.duplicate()
	a[i] = v
	return a


## 라마르크 비교(14.2 범위 6·검사 기준 11, DESIGN-v0.2 3.7): 부모 둘의 유전체를 같게(교차가 바꾸지 않게)·돌연변이율 0 으로 두고 배운
## 두뇌만 다르게 손으로 정함. lamarck_frac 0 → 자식 유전체 = 부모 유전체 그대로, 1 → 자식 W2 행동 행 = float32(자름(타고난 + (ΔW_a + ΔW_b) ÷ 2)),
## 혼자 분열이면 b = a(ΔW_a 그대로). 자식의 배운 두뇌 = 자식 유전체 W2. 우연 기준(random)에서는 쓰지 않음.
func test_lamarck() -> void:
	for frac: float in [0.0, 1.0]:
		for asexual: bool in [false, true]:
			var wd := empty_world({"learn.enabled": true, "mutation.rate": 0.0, "learn.lamarck_frac": frac, "repro.asexual_when_alone": asexual})
			var p := grass_spot(wd)
			add_slime(wd, p, 0.9, 100)
			if not asexual:
				add_slime(wd, p + Vector2i(1, 0), 0.9, 100)
			var G := wd._G
			var g0 := wd.s_genome.slice(0, G)
			g0[wd._w2o + 1] = 3.9375
			var n0 := wd.population()
			for i in n0:
				for k in G:
					wd.s_genome[i * G + k] = g0[k]
				for k in wd._w2n:
					# 부모 a 의 배운 − 타고난 = 0.5, 부모 b = −0.25(첫 칸은 둘 다 + 0.5 — 3.9375 + 0.5 → 자름)
					var dv := 0.5 if i == 0 or k == 1 else -0.25
					wd.s_w2[i * wd._w2n + k] = float(g0[wd._w2o + k]) + dv
			wd.s_dead.fill(0)
			wd._reproduce()
			var c := wd.index_of_id(n0)
			var gc := wd.s_genome.slice(c * G, (c + 1) * G) if c != -1 else PackedFloat32Array()
			var want := g0.duplicate()
			if frac > 0.0:
				for k in wd._w2n:
					var da := wd.s_w2[k] - float(g0[wd._w2o + k])
					var db := wd.s_w2[(n0 - 1) * wd._w2n + k] - float(g0[wd._w2o + k])
					want[wd._w2o + k] = clampf(float(g0[wd._w2o + k]) + frac * ((da + db) * 0.5), -4.0, 4.0)
			var w2_ok := c != -1
			for k in wd._w2n:
				w2_ok = w2_ok and wd.s_w2[c * wd._w2n + k] == float(gc[wd._w2o + k])
			var label := "%s·lamarck %.0f" % ["혼자 분열" if asexual else "짝", frac]
			check(c != -1 and gc == want and w2_ok and (frac == 0.0 or gc[wd._w2o + 1] == 4.0),
					"%s: 자식 유전체 = %s, 자식의 배운 두뇌 = 자식 유전체 W2" % [label, "부모 유전체 그대로" if frac == 0.0 else
					"타고난 + (ΔW_a + ΔW_b) ÷ 2(float32·자름 — 혼자 분열이면 ΔW_a)"])
	# 우연 기준: 부모와 상관없는 새 유전체(라마르크 몫을 더하지 않음)
	var wr := empty_world({"learn.enabled": true, "mutation.rate": 0.0, "learn.lamarck_frac": 1.0, "repro.inherit": "random"})
	var pr := grass_spot(wr)
	add_slime(wr, pr, 0.9, 100)
	add_slime(wr, pr + Vector2i(1, 0), 0.9, 100)
	for k in wr.s_w2.size():
		wr.s_w2[k] += 0.5
	var probe := SimRng.new()
	probe.set_state_string(wr.rng_life.get_state_string())
	var gr := SimBrain.random_genome(wr.cfg, wr.L, probe)
	wr.s_dead.fill(0)
	wr._reproduce()
	var kr := wr.index_of_id(2)
	check(kr != -1 and wr.s_genome.slice(kr * wr._G, (kr + 1) * wr._G) == gr, "우연 기준(random)은 라마르크 몫을 더하지 않음(자식 = random_genome)")
	done()


## learn.freeze(14.2 검사 기준 12): 500틱 동안 배운 두뇌 = 유전체 W2 행동 행 그대로(모든 개체), 고리는 채워짐, 갱신 0, 학습 비용·기준선은
## 그대로 셈. 같은 씨앗의 학습 켬 세계는 배운 두뇌가 바뀜(대조).
func test_learn_freeze() -> void:
	var wd := world({"learn.enabled": true, "learn.freeze": true}, 6)
	var learn_events := 0
	for t in 500:
		wd.step()
		learn_events += wd.period_learn
		wd.period_learn = 0
	var changed := 0
	var unfilled := 0
	var rbar_nz := 0
	for i in wd.population():
		if wd.learned_amount_of(i) != 0.0:
			changed += 1
		if wd.s_age[i] >= wd._ring:
			for s in wd._ring:
				if wd.s_ring_a[i * wd._ring + s] == SimWorld.RING_EMPTY:
					unfilled += 1
		if wd.s_rbar[i] != 0.0:
			rbar_nz += 1
	var row := wd.sample()
	check(float(row.dw_mean) == 0.0 and int(row.learn_events) == 0 and float(row.eta_mean) > 0.0, "freeze: 시계열 dw_mean 0·learn_events 0·eta_mean %.4f" % float(row.eta_mean))
	check(wd.population() > 0 and changed == 0 and unfilled == 0 and learn_events == 0 and wd.led_learn > 0.0 and rbar_nz > 0,
			"freeze·씨앗 6·500틱: 배운 두뇌 = 유전체(바뀐 개체 %d/%d), 고리가 채워짐(빈칸 %d), 갱신 %d번, 학습 비용 %.2f·기준선은 셈" % [changed,
			wd.population(), unfilled, learn_events, wd.led_learn])
	var wl := world({"learn.enabled": true}, 6)
	wl.step_n(100)
	var moved := 0
	for i in wl.population():
		if wl.learned_amount_of(i) > 0.0:
			moved += 1
	var rl := wl.sample()
	check(moved > 0 and float(rl.dw_mean) > 0.0, "대조: 같은 씨앗의 학습 켬 세계는 100틱에 배운 두뇌가 바뀐 개체 %d마리(dw_mean %.4f)" % [moved, float(rl.dw_mean)])
	done()


## 관계 검사(14.2 범위 5·검사 기준 13, DESIGN-v0.2 3.5·8): learn.enabled 와 argmax·think_every 2·sharpness 0 을 각각 거부(학습 끔이면 받음),
## eta_init ≤ eta_max, 고를 값·배열 규칙, 옛 설정용 SECTIONS_ADDED·CONFIG_KEYS_ADDED, 예설정 learn_basic.
func test_learn_config() -> void:
	for kv in [["brain.policy", "argmax"], ["brain.think_every", 2], ["brain.sharpness", 0]]:
		var e := str(SimConfig.build("default", {"learn.enabled": true, kv[0]: kv[1]}).error)
		check(e.contains("learn.enabled") and e.contains(kv[0]), "learn.enabled 와 %s = %s 거부: %s" % [kv[0], str(kv[1]), e])
		check(SimConfig.build("default", {kv[0]: kv[1]}).error == "", "학습 끔이면 %s = %s 는 받음(v0.1 실험 그대로)" % [kv[0], str(kv[1])])
	check(SimConfig.build("default", {"learn.enabled": true, "brain.sharpness": 1}).error == "", "learn.enabled 와 sharpness 1 은 받음")
	var e2 := str(SimConfig.build("default", {"learn.eta_init": 0.6}).error)
	check(e2.contains("learn.eta_init") and e2.contains("learn.eta_max"), "eta_init 0.6 > eta_max 0.5 거부: " + e2)
	check(SimConfig.build("default", {"learn.eta_init": 0.5}).error == "", "eta_init = eta_max 는 받음")
	check(SimConfig.CHOICES["learn.diag_factor"] == [SimBrain.DIAG_EXACT, SimBrain.DIAG_NONE] and str(cfg_with().learn.diag_factor) == SimBrain.DIAG_EXACT,
			"learn.diag_factor 고를 값 = SimBrain.DIAG_*, 기본 exact")
	for bad in [["learn.diag_factor", "Exact"], ["learn.stage_mult", [1.0, 0.5, 0.2]], ["learn.stage_mult", [1.0, 0.5, 0.2, 1.5]],
			["learn.ring_len", 0], ["learn.ring_len", 2.5], ["learn.baseline_rate", 0.0], ["body.birth_size_frac", 0.0]]:
		check(str(SimConfig.build("default", {bad[0]: bad[1]}).error).contains(bad[0]), "%s = %s 거부" % [bad[0], str(bad[1])])
	check(SimSnapshot.SECTIONS_ADDED.has("learn") and SimSnapshot.CONFIG_KEYS_ADDED.has("life.adult_frac") and SimSnapshot.CONFIG_KEYS_ADDED.has("life.old_frac")
			and SimSnapshot.CONFIG_KEYS_ADDED.has("body.grow_enabled") and SimSnapshot.CONFIG_KEYS_ADDED.has("body.birth_size_frac"),
			"옛 설정 채우기: SECTIONS_ADDED 에 learn, CONFIG_KEYS_ADDED 에 life.adult_frac·old_frac·body.grow_enabled·birth_size_frac")
	var lb := SimConfig.build("learn_basic", {})
	check(lb.error == "" and bool(lb.config.learn.enabled) and bool(lb.config.body.grow_enabled) and not bool(cfg_with().learn.enabled)
			and not bool(cfg_with().body.grow_enabled), "예설정 learn_basic = 학습·몸 자람 켬, 기본은 둘 다 끔")
	done()


## --fork-reset-learned(14.2 검사 기준 14, DESIGN-v0.2 11.2): 되돌린 뒤 모든 개체의 배운 두뇌 = 유전체 W2 행동 행, 기준선 0, 고리가 빔
## (어린 동안 배운 양은 그대로). 학습 끈 세계는 거부(아무것도 안 바뀜). 실행기: --resume 없이 주면 인자 오류, 학습 끈 스냅숏은 종료
## 코드 2, 학습 스냅숏은 되돌린 세계로 이어 돌림(summary.json 의 reset_learned).
func test_reset_learned() -> void:
	var wd := world({"learn.enabled": true}, 7)
	wd.step_n(150)
	var learned := 0
	for i in wd.population():
		if wd.learned_amount_of(i) > 0.0:
			learned += 1
	var juv := wd.s_dw_juv.duplicate()
	check(learned > 0 and wd.reset_learned(), "150틱 학습 세계(배운 개체 %d)에서 reset_learned" % learned)
	var bad := 0
	for i in wd.population():
		for k in wd._w2n:
			if wd.s_w2[i * wd._w2n + k] != float(wd.s_genome[i * wd._G + wd._w2o + k]):
				bad += 1
	var ring_empty := true
	for v in wd.s_ring_a:
		ring_empty = ring_empty and v == SimWorld.RING_EMPTY
	for v in wd.s_ring_pos:
		ring_empty = ring_empty and v == 0
	for v in wd.s_ring_e:
		ring_empty = ring_empty and v == 0.0
	for v in wd.s_ring_h:
		ring_empty = ring_empty and v == 0.0
	var rbar_zero := true
	for v in wd.s_rbar:
		rbar_zero = rbar_zero and v == 0.0
	check(bad == 0 and ring_empty and rbar_zero and wd.s_dw_juv == juv, "되돌린 뒤 배운 두뇌 = 유전체 W2 행동 행(다른 칸 %d), 기준선 0, 고리 빔, 어린 동안 배운 양 그대로" % bad)
	var off := world({}, 7)
	off.step_n(20)
	var t0 := SimSnapshot.to_text(off)
	check(not off.reset_learned() and SimSnapshot.to_text(off) == t0, "학습 끈 세계: reset_learned 거부(false), 바뀐 것 없음")
	var runner = load("res://tests/run_experiment.gd")
	check(str(runner.parse_args(PackedStringArray(["--out=x", "--fork-reset-learned"])).get("error", "")).contains("--resume"),
			"--fork-reset-learned 는 --resume 없이 주면 인자 오류")
	var pa: Dictionary = runner.parse_args(PackedStringArray(["--out=x", "--resume=s.json", "--fork-reset-learned", "--fork-set=learn.freeze=true"]))
	check(not pa.has("error") and pa.fork_reset and pa.fork_sets == {"learn.freeze": true}, "--fork-reset-learned·--fork-set 해석")
	var dir := tmp_dir("test_reset_learned")
	DirAccess.make_dir_recursive_absolute(dir)
	var snap := dir.path_join("learn.json")
	var ws := world({"learn.enabled": true}, 7)
	ws.step_n(150)
	SimSnapshot.save_file(ws, snap)
	var out := dir.path_join("out")
	var a: Dictionary = runner.parse_args(PackedStringArray(["--out=" + out, "--resume=" + snap, "--fork-reset-learned", "--fork-set=learn.freeze=true",
			"--max-ticks=%d" % (ws.tick + 30), "--generations=1000000000", "--quiet"]))
	a.silent = true
	var code: int = runner.run(a)
	var sm = JSON.parse_string(FileAccess.get_file_as_string(out.path_join("summary.json")))
	var fin: SimWorld = SimSnapshot.load_file(out.path_join("final.snapshot.json")).world
	var still := 0
	if fin != null:
		for i in fin.population():
			if fin.learned_amount_of(i) != 0.0:
				still += 1
	check(code == 0 and typeof(sm) == TYPE_DICTIONARY and sm.get("reset_learned") == true and fin != null and fin.tick == ws.tick + 30 and still == 0,
			"실행기 --resume --fork-reset-learned --fork-set=learn.freeze=true: 30틱 뒤에도 배운 두뇌 = 유전체(다른 개체 %d), summary.reset_learned = true" % still)
	var snap_off := dir.path_join("off.json")
	SimSnapshot.save_file(off, snap_off)
	var b: Dictionary = runner.parse_args(PackedStringArray(["--out=" + dir.path_join("out2"), "--resume=" + snap_off, "--fork-reset-learned", "--quiet"]))
	b.silent = true
	check(runner.run(b) == 2 and not FileAccess.file_exists(dir.path_join("out2").path_join("summary.json")), "학습 끈 스냅숏에 --fork-reset-learned → 종료 코드 2")
	remove_tree(dir)
	done()


## 검사 실행기 자체(I33·J15): 검사 몇 개를 한 뒤 스크립트 오류로 끊긴 함수는 실패(종료 코드 1), --only 에 모르는 이름이 있으면 아무것도
## 돌리지 않고 실패. 오류를 일부러 내는 함수(selftest_abort_midway)는 이 실행기를 따로 띄워 돌린다 — 그 오류 줄이 이 실행의 로그
## (CI 가 SCRIPT ERROR 를 찾는 곳)에 섞이지 않게 출력은 받아서 결과만 본다.
func test_runner_guards() -> void:
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var cases := [
		# [--only 값, 기대 종료 코드, 출력에 있어야 할 글, 설명]
		["test_policy", 0, "RESULT: 4 checks passed, 0 failed", "맞는 이름 하나는 그 검사만 돌고 통과(대조)"],
		["selftest_abort_midway", 1, "RESULT: 1 checks passed, 1 failed", "검사 1개 뒤 스크립트 오류로 끊긴 함수 → 실패"],
		["test_policy,test_polcy", 1, "RESULT: 0 checks passed, 1 failed", "모르는 이름(오타)이 섞이면 아무것도 돌리지 않고 실패"],
	]
	for c in cases:
		var out := []
		var code := OS.execute(exe, ["--headless", "--path", proj, "--script", "res://tests/run_tests.gd", "--", "--only=" + str(c[0])], out, true)
		var text := "\n".join(out)
		var why := ""
		if c[1] == 1 and c[0] == "selftest_abort_midway":
			why = "끝까지 실행되지 않음"
		elif c[1] == 1:
			why = "모르는 검사 이름: \"test_polcy\""
		check(code == c[1] and text.contains(c[2]) and (why == "" or text.contains(why)),
				"%s: --only=%s → 종료 코드 %d(기대 %d), \"%s\"%s" % [c[3], c[0], code, c[1], c[2], " · \"" + why + "\"" if why != "" else ""])
	done()


## test_runner_guards 가 따로 띄운 실행기에서만 돈다(SELF_TESTS): 검사 하나를 한 뒤 일부러 스크립트 오류를 내 함수가 끊긴다.
func selftest_abort_midway() -> void:
	check(true, "끊기기 전 검사 하나")
	var boom = null
	boom.no_such_method()
	done()


static func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
