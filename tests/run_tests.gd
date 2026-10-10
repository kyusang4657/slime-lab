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
	"PackedFloat32Array", "PackedFloat64Array", "PackedStringArray", "absf", "absi", "minf", "maxf", "mini", "maxi",
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
	"to_int", "to_int32_array", "to_utf8_buffer",
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
		"test_extinction_no_resources", "test_memory_units", "test_performance", "test_farm_reachable",
		"test_time_after_step", "test_event_copies", "test_extinction_mean_gen",
		"test_config_rules", "test_presets_file", "test_night_threshold", "test_components_fast", "test_snapshot_corrupt",
		"test_recorder_files",
		"test_empty_start", "test_mate_once_per_tick", "test_store_max_count", "test_first_farm_once", "test_store_takes_pile",
		"test_child_energy_cap", "test_store_built_in_act", "test_spoil_lifetime", "test_growth_interval",
		"test_farm_abandon_any_growth", "test_light_curve", "test_store_not_on_farm", "test_action_names", "test_harsh_winter",
		"test_farm_rule_values", "test_civ_rule_values", "test_runner_guards",
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
## 대기열(_pending_events — 연대기는 저장되고, 알림은 연 뒤 새 사건부터). 나머지는 모두 왕복 뒤 값이 같아야 한다(test_snapshot_roundtrip).
const SNAPSHOT_SCRATCH: Array[String] = ["_in", "_hid", "_wts", "_out", "_bucket_head", "_bucket_next", "_mated", "csat", "_pending_events"]


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
	var bad_cfg: Dictionary = runner.parse_args(PackedStringArray(["--out=" + dir, "--set=없는.키=1", "--quiet"]))
	bad_cfg.silent = true
	check(runner.run(bad_cfg) == 2, "설정 오류 코드 2")
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
	}
	var leaked: Array[String] = []
	for name: String in cases:
		var d = JSON.parse_string(text)
		cases[name].call(d)
		var r = SimSnapshot.from_dict(d)
		if typeof(r) != TYPE_DICTIONARY or r.get("world") != null or str(r.get("error", "")) == "":
			leaked.append(name)
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
