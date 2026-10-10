extends SceneTree
## 헤드리스 자동 검사:  godot --headless --path . --script res://tests/run_tests.gd
## 이전 프로젝트(little-monster-village)의 방식: check(조건, 설명)을 쌓고 마지막 줄에 RESULT 를 출력한다.
## 테스트 함수가 끝까지 실행되지 않으면(스크립트 오류) 실패로 센다.
## 선택 인자: --only=test_이름(쉼표로 여러 개)  --skip-slow

const SIM_DIR := "res://scripts/sim"
## 매직 넘버 검사에서 빼는 파일: 설정 로더(범위 검사의 상한·하한은 시뮬레이션 수치가 아님)
const MAGIC_EXEMPT: Array[String] = ["sim_config.gd"]
## 코드에 그대로 써도 되는 수
const MAGIC_ALLOWED: Array[String] = ["0", "1", "2", "0.0", "1.0", "0.5", "2.0"]
const FORBIDDEN_MATH: Array[String] = ["sin", "cos", "tan", "exp", "log", "pow", "tanh", "atan", "atan2", "randfn", "randf_range", "randi_range"]
## 농사 도달 검사(S15): 이 예설정·씨앗 조합 중 하나라도 평균 100세대 안에 농사(3단계)에 도달해야 한다.
## 연구용 fast_civ 를 먼저 본다(씨앗 1: 3,321틱·평균 49.0세대에 농사 — docs/TUNING-fast_civ.md).
## 검사 전체는 4코어 컨테이너에서 약 20초(씨앗 1 농사까지 + 씨앗 2·3 채집까지).
const FARM_PRESETS: Array[String] = ["fast_civ", "demo_fast", "default"]
const FARM_SEEDS: Array[int] = [1, 2, 3]
const FARM_GENERATIONS := 100.0
## fast_civ 다시 맞춤의 목표는 S15 와 따로 검사한다(S15 는 demo_fast 로도 통과하므로): FARM_SEEDS 의 첫 씨앗이
## fast_civ 그대로 평균 FARM_GENERATIONS 세대 안에 농사. 결정적이므로 문서에 적은 시각도 고정한다 —
## 시뮬레이션·설정을 일부러 바꿨다면 다시 재서 이 두 값과 TUNING-fast_civ.md·TEST-REPORT(W11·6절)를 함께 고칠 것.
const FAST_CIV_SEED1_FARM_TICK := 3321
const FAST_CIV_SEED1_FARM_GEN := 49.0
## fast_civ 의 채집은 FARM_SEEDS 모두에서 진화 도중(이 평균 세대 이상)에 열려야 한다.
## 이전 값은 씨앗 1~3 이 4.35·0.22·0.49세대(첫 무작위 두뇌의 행동), 지금은 33.9·4.2·23.3세대.
## 씨앗 1~3 만 본다: 씨앗 7 은 지금 값에서도 알려진 예외(채집·저장·농사 0.24·0.32·1.98세대 — 첫 세대 폭발,
## TUNING-fast_civ.md "목표와 다른 점").
const FAST_CIV_MIN_FORAGE_GEN := 2.0
## 성능 기록: 개체·틱당 마이크로초가 이 값의 두 배를 넘으면 실패(CI 기계 차이를 감안한 느슨한 상한).
const PERF_TARGET_US := 25.0

var _pass := 0
var _fail := 0
var _report: Array[String] = []
var _only: PackedStringArray = []
var _skip_slow := false


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
	]
	for t in tests:
		if not _only.is_empty() and not _only.has(t):
			continue
		var before := _fail
		var checks := _pass + _fail
		var t0 := Time.get_ticks_msec()
		call(t)
		if _pass + _fail == checks:
			_fail += 1
			printerr("  실패: %s 가 끝까지 실행되지 않음(스크립트 오류)" % t)
		_report.append("%s %s (%.1fs)" % ["PASS" if _fail == before else "FAIL", t, float(Time.get_ticks_msec() - t0) / 1000.0])
	print("\n".join(_report))
	print("RESULT: %d checks passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  실패: " + what)


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


## 슬라임 없는 작은 세계(규칙 단위 검사용).
func empty_world(sets: Dictionary = {}) -> SimWorld:
	var s := {"population.initial": 0}
	s.merge(sets, true)
	return world(s)


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


## 매직 넘버·금지 수학 함수 정적 검사(시뮬레이션 코드).
func test_static_rules() -> void:
	var files := DirAccess.get_files_at(SIM_DIR)
	check(files.size() >= 8, "시뮬레이션 파일을 찾음 (%d)" % files.size())
	var num_re := RegEx.create_from_string("(?<![A-Za-z_0-9.])(0x[0-9a-fA-F]+|\\d+\\.\\d+(e-?\\d+)?|\\d+(e-?\\d+)?)(?![A-Za-z_0-9])")
	var fn_re := RegEx.create_from_string("(?<![A-Za-z_0-9.])(" + "|".join(FORBIDDEN_MATH) + ")\\s*\\(")
	var magic: Array[String] = []
	var forbidden: Array[String] = []
	for f in files:
		if not f.ends_with(".gd"):
			continue
		var lines := FileAccess.get_file_as_string(SIM_DIR.path_join(f)).split("\n")
		for li in lines.size():
			var code := _strip_line(lines[li])
			if code.strip_edges() == "":
				continue
			for m in fn_re.search_all(code):
				forbidden.append("%s:%d %s" % [f, li + 1, m.get_string()])
			if MAGIC_EXEMPT.has(f) or code.strip_edges().begins_with("const "):
				continue
			for m in num_re.search_all(code):
				if not MAGIC_ALLOWED.has(m.get_string()):
					magic.append("%s:%d %s" % [f, li + 1, m.get_string()])
	check(magic.is_empty(), "시뮬레이션 코드에 매직 넘버 없음: " + ", ".join(magic))
	check(forbidden.is_empty(), "플랫폼마다 다를 수 있는 수학 함수 없음: " + ", ".join(forbidden))


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
	# 덩어리 보존: a = +1, b = -1 이면 은닉 j 의 들어오는·나가는 가중치 부호가 같아야 한다
	var pa := PackedFloat32Array()
	pa.resize(L.genes)
	pa.fill(1.0)
	var pb := PackedFloat32Array()
	pb.resize(L.genes)
	pb.fill(-1.0)
	var mixed_any := false
	var block_ok := true
	for trial in 20:
		var c := SimBrain.crossover(L, pa, pb, rng)
		var signs := {}
		for j in L.n_hid:
			var sgn: float = c[j * L.n_in]
			signs[sgn] = true
			for i in L.n_in:
				if c[j * L.n_in + i] != sgn:
					block_ok = false
			for q in L.n_out:
				if c[L.w2_offset + q * L.n_hid + j] != sgn:
					block_ok = false
		if signs.size() == 2:
			mixed_any = true
	check(block_ok, "교차가 뉴런 덩어리를 깨지 않음")
	check(mixed_any, "교차가 두 부모를 섞음")
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


func test_policy() -> void:
	check(SimBrain.policy_weight(0.0, 4) == 1.0, "출력 0 의 가중치 1")
	check(SimBrain.policy_weight(10.0, 4) > SimBrain.policy_weight(1.0, 4) and SimBrain.policy_weight(-10.0, 4) < SimBrain.policy_weight(-1.0, 4), "가중치 단조 증가")
	check(SimBrain.policy_weight(-1e9, 4) >= 0.0, "가중치는 음수가 아님")
	var o := PackedFloat64Array([1.0, 3.0, 3.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	check(SimBrain.argmax_action(o) == 1, "같은 최댓값이면 작은 번호")


## SimWorld._think 의 펼친 계산이 SimBrain.forward·_quad 와 같은지.
func test_world_think_matches() -> void:
	var wd := world({}, 4)
	wd.step_n(30)
	var ok_out := true
	var ok_quad := true
	for i in mini(wd.population(), 60):
		var x := wd.s_x[i]
		var y := wd.s_y[i]
		var hd := wd.s_head[i]
		wd._think(i, x, y, y * wd.w + x, hd, wd.s_emax[i])
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
	check(ok_out, "세계 안 순전파 = SimBrain.forward (비트 단위)")
	check(ok_quad, "펼친 영역 감지 = _quad (네 방향)")
	# 정책 확률: 같은 출력이면 세계의 뽑기 가중치와 SimBrain.policy_weight 가 같다
	wd._pick_action()
	var same := true
	for q in SimBrain.BASE_OUTPUTS:
		if wd._wts[q] != SimBrain.policy_weight(wd._out[q], wd._sharpness):
			same = false
	check(same, "펼친 정책 가중치 = policy_weight")


# ───────────────────────── 생태 ─────────────────────────

func test_plants_light_resources() -> void:
	var wd := empty_world()
	wd.light = 0.0
	var before := wd.food.duplicate()
	for c in wd.w * wd.h:
		wd.food[c] = 0.0
	wd._grow_plants()
	var grew := false
	for c in wd.w * wd.h:
		if wd.food[c] > 0.0:
			grew = true
	check(not grew, "밤(빛 0, night_growth 0)에는 식물이 자라지 않음")
	wd.light = 1.0
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


func test_population_cap() -> void:
	var wd := world({"population.cap": 150, "population.initial": 100}, 2)
	var over := false
	for k in 800:
		wd.step()
		if wd.population() > 150:
			over = true
	check(not over, "개체 수가 상한을 넘지 않음 (최고 %d)" % wd.peak_population)


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
	# 바닥 먹이는 썩음
	wd._put_dropped(c + 1, 3.0)
	for k in int(wd.cfg.dropped.spoil_ticks):
		wd._spoil_dropped()
	check(wd.dropped[c + 1] == 0.0 and wd.drop_listed[c + 1] == 0, "바닥 먹이는 spoil_ticks 뒤 사라짐")


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
	wd._grow_plants()
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
	for k in int(w2.cfg.dropped.spoil_ticks):
		w2._spoil_dropped()
	check(w2.farm_sprouts == 1 and w2.base_fert[qc + 1] > f0, "저장고 근처 싹 1번, 비옥도 증가")


# ───────────────────────── 결정성·저장 ─────────────────────────

func run_hash(seed_value: int, ticks: int, sets: Dictionary = {}) -> Array:
	var wd := world(sets, seed_value)
	var rec := SimRecorder.new()
	for k in ticks:
		wd.step()
		if wd.tick % int(wd.cfg.record.every) == 0:
			rec.record(wd)
	return [wd.history_hash, rec.timeseries_csv(), wd]


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


func test_snapshot_roundtrip() -> void:
	var wd := world({}, 21)
	wd.step_n(700)
	# 저장 발견 상태까지 포함되도록 저장고·밭을 하나씩 만든다
	var p := grass_spot(wd)
	wd.store_tiles.append(p.y * wd.w + p.x)
	wd.store_food.append(12.5)
	wd._rebuild_stores()
	var text := SimSnapshot.to_text(wd)
	var r := SimSnapshot.from_text(text)
	check(r.error == "", "스냅숏 복원: " + str(r.error))
	if r.world == null:
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
		check(wm.history_hash == rm.world.history_hash, "기억 2 왕복 후 같은 해시")
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
	check(l1.status == "loaded" and l1.world.history_hash == wd.history_hash, "불러오기")
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


func test_extinction_no_resources() -> void:
	var wd := world({}, 1, "no_resources")
	var limit := int(wd.cfg.life.max_age) + int(wd.cfg.life.max_age_jitter) + 10
	while not wd.is_extinct() and wd.tick < limit:
		wd.step()
	check(wd.is_extinct(), "자원 0 → %d틱 안에 멸종 (t=%d)" % [limit, wd.tick])
	check(wd.chronicle.size() > 0 and wd.chronicle[wd.chronicle.size() - 1].kind == "extinction", "연대기에 멸종 기록")


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


func test_performance() -> void:
	var wd := world({}, 2)
	wd.step_n(800)
	var t0 := Time.get_ticks_usec()
	var st := 0
	for k in 400:
		st += wd.population()
		wd.step()
	var us := float(Time.get_ticks_usec() - t0) / float(maxi(st, 1))
	print("  성능: 평균 개체 %.0f, 개체·틱당 %.1fµs, %.0f틱/초" % [float(st) / 400.0, us, 400.0 * 1e6 / float(Time.get_ticks_usec() - t0)])
	check(us < PERF_TARGET_US * 2.0, "개체·틱당 %.1fµs < %.0fµs" % [us, PERF_TARGET_US * 2.0])


func test_farm_reachable() -> void:
	if _skip_slow:
		check(true, "느린 검사 건너뜀")
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
		return
	var before := str(wd.chronicle[0].text)
	ev[0]["text"] = "바뀜"
	check(str(wd.chronicle[0].text) == before, "꺼낸 사건을 고쳐도 연대기는 그대로")


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
		return
	w3.step()
	var e3: Dictionary = w3.chronicle.back() if not w3.chronicle.is_empty() else {}
	check(w3.is_extinct() and str(e3.get("kind", "")) == "extinction" and float(e3.get("mean_gen", -1.0)) == got and w3.history_hash == wd.history_hash,
			"스냅숏에서 이어 돌린 멸종 사건도 평균 %.2f세대 · 같은 해시" % float(e3.get("mean_gen", -1.0)))
	# 번식 없이 사라진 세계(첫 세대뿐)는 0 이 맞음
	var w0 := world({}, 1, "no_resources")
	while not w0.is_extinct() and w0.tick < 3000:
		w0.step()
	check(w0.is_extinct() and float(w0.chronicle.back().mean_gen) == 0.0, "첫 세대만 살다 사라지면 평균 0세대")


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


## 잘게 갈라진 큰 지도에서도 연결 요소 계산이 칸 수에 비례(I31). 예전 계산(요소마다 거리장)은 192×192 바둑판에서 십수 초.
func test_components_fast() -> void:
	var n := 192
	var t := PackedByteArray()
	t.resize(n * n)
	for y in n:
		for x in n:
			t[y * n + x] = SimGrid.TILE_GRASS if (x + y) % 2 == 0 else SimGrid.TILE_ROCK
	var t0 := Time.get_ticks_msec()
	var comp := SimGrid.components(t, n, n)
	var ms := Time.get_ticks_msec() - t0
	check(comp.sizes.size() == n * n / 2 and comp.labels[1] == -1 and comp.labels[2] == 1, "바둑판 %d×%d: 요소 %d개" % [n, n, comp.sizes.size()])
	check(ms < 3000, "연결 요소 계산 %d ms < 3000 ms(요소 %d개 — 예전 계산은 요소 수 × 칸 수)" % [ms, comp.sizes.size()])


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
