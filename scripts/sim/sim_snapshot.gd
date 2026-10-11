class_name SimSnapshot
extends RefCounted
## 세계 스냅숏(저장·복원). 형식: docs/DESIGN-v0.1.md 8.3, v0.2 에서 더한 키는 docs/DESIGN-v0.2.md 9.1(*_ADDED 상수).
## 메타·설정은 사람이 읽는 JSON(설정 값은 SimConfig.validate 가 JSON 왕복을 보장), 배열은 리틀엔디언 base64, 실수 단일 값은 float64 비트 16진 문자열.
## (Godot 4.4.1 의 JSON.stringify 는 full_precision 을 켜도 실수를 비트 단위로 왕복하지 못한다 — TEST-REPORT 참고.)
##
## 저장 관리(SnapshotStore 부분)는 이전 프로젝트 save_manager.gd 방식: 임시 파일 → 검증 → 교체, 직전 정상본 .bak, 깨진 파일 .broken 보관.

const FORMAT := "slime-lab-snapshot"
const VERSION := 1
const F64_BYTES := 8


static func b64(arr: Variant) -> String:
	var raw: PackedByteArray = arr if typeof(arr) == TYPE_PACKED_BYTE_ARRAY else arr.to_byte_array()
	if raw.is_empty():
		return ""
	return Marshalls.raw_to_base64(raw)


static func f64_hex(v: float) -> String:
	return PackedFloat64Array([v]).to_byte_array().hex_encode()


static func hex_f64(s: String) -> float:
	var b := s.hex_decode()
	if b.size() != F64_BYTES:
		return NAN
	return b.to_float64_array()[0]


static func _bytes(d: Dictionary, key: String) -> PackedByteArray:
	if typeof(d.get(key)) != TYPE_STRING or d[key] == "":
		return PackedByteArray()
	return Marshalls.base64_to_raw(d[key])


static func to_dict(wd: SimWorld) -> Dictionary:
	return {
		format = FORMAT, version = VERSION,
		app_version = ProjectSettings.get_setting("application/config/version", ""),
		seed = str(wd.seed_value), tick = wd.tick,
		config = wd.cfg,
		rng = {world = wd.rng_world.get_state_string(), life = wd.rng_life.get_state_string()},
		map = {
			tiles = b64(wd.tiles), fert = b64(wd.fert), base_fert = b64(wd.base_fert), food = b64(wd.food),
			dropped = b64(wd.dropped), drop_timer = b64(wd.drop_timer), drop_list = b64(wd.drop_list),
			sat = b64(wd.sat), farm_visit = b64(wd.farm_visit), farms = b64(wd.farms),
		},
		civ = {
			stage = wd.stage, discovery_tick = wd.discovery_tick, forage_attempts = wd.forage_attempts,
			farm_sprouts = wd.farm_sprouts, first_farm_tick = wd.first_farm_tick, store_drops_total = f64_hex(wd.store_drops_total),
			drop_total_tile = b64(wd.drop_total_tile), region_drop = b64(wd.region_drop),
			store_tiles = b64(wd.store_tiles), store_food = b64(wd.store_food),
		},
		slimes = {
			count = wd.s_id.size(), id = b64(wd.s_id), x = b64(wd.s_x), y = b64(wd.s_y), head = b64(wd.s_head),
			age = b64(wd.s_age), gen = b64(wd.s_gen), max_age = b64(wd.s_max_age), last_repro = b64(wd.s_last_repro),
			last_action = b64(wd.s_last_action), energy = b64(wd.s_energy), carry = b64(wd.s_carry),
			mem = b64(wd.s_mem), genome = b64(wd.s_genome), last_eff = b64(wd.s_last_eff), eaten = b64(wd.s_eaten),
		},
		lineage = {
			count = wd.lin_pa.size(), pa = b64(wd.lin_pa), pb = b64(wd.lin_pb), gen = b64(wd.lin_gen),
			birth = b64(wd.lin_birth), death = b64(wd.lin_death), cause = b64(wd.lin_cause),
			children = b64(wd.lin_children), size = b64(wd.lin_size), sense = b64(wd.lin_sense), hue = b64(wd.lin_hue),
			eaten = b64(wd.lin_eaten),
		},
		stats = {
			led_initial = f64_hex(wd.led_initial), led_eaten = f64_hex(wd.led_eaten), led_spent = f64_hex(wd.led_spent),
			led_repro_loss = f64_hex(wd.led_repro_loss), led_died = f64_hex(wd.led_died),
			led_eaten_open = f64_hex(wd.led_eaten_open), eaten_from_id = wd.eaten_from_id,
			period_act = b64(wd.period_act), period_eff = b64(wd.period_eff),
			total_births = wd.total_births, total_deaths = wd.total_deaths, period_births = wd.period_births,
			period_deaths = wd.period_deaths, peak_population = wd.peak_population, next_milestone = wd.next_milestone,
			extinct_tick = wd.extinct_tick,
		},
		history_hash = wd.history_hash,
		chronicle = wd.chronicle,
	}


static func to_text(wd: SimWorld) -> String:
	return JSON.stringify(to_dict(wd), "\t")


## 스냅숏에서 세계를 만든다. 결과: {world, error}. error 가 "" 이면 성공.
## 하위 키·종류·길이·범위를 모두 검사한 뒤에야 칸 번호를 첨자로 쓴다(구조가 틀린 파일이 스크립트 오류로 끝나지 않고 오류 문장이 되게).
static func from_dict(d: Variant) -> Dictionary:
	var err := validate(d)
	if err != "":
		return {world = null, error = err}
	var wd := SimWorld.new()
	var cfg := with_added_keys(d.config)
	wd._load_config(cfg)
	wd.seed_value = int(d.seed)
	wd.tick = int(d.tick)
	wd.rng_world = SimRng.new()
	wd.rng_world.set_state_string(d.rng.world)
	wd.rng_life = SimRng.new()
	wd.rng_life.set_state_string(d.rng.life)
	wd._alloc_map()
	var m: Dictionary = d.map
	wd.tiles = _bytes(m, "tiles")
	wd.fert = _bytes(m, "fert").to_float64_array()
	wd.base_fert = _bytes(m, "base_fert").to_float64_array()
	wd.food = _bytes(m, "food").to_float64_array()
	wd.dropped = _bytes(m, "dropped").to_float64_array()
	wd.drop_timer = _bytes(m, "drop_timer").to_int32_array()
	wd.drop_list = _bytes(m, "drop_list").to_int32_array()
	wd.sat = _bytes(m, "sat").to_float64_array()
	wd.farm_visit = _bytes(m, "farm_visit").to_int32_array()
	wd.farms = _bytes(m, "farms").to_int32_array()
	var cv: Dictionary = d.civ
	wd.stage = int(cv.stage)
	for k in wd.discovery_tick.size():
		wd.discovery_tick[k] = int(cv.discovery_tick[k])
	wd.forage_attempts = int(cv.forage_attempts)
	wd.farm_sprouts = int(cv.farm_sprouts)
	wd.first_farm_tick = int(cv.first_farm_tick) if cv.has("first_farm_tick") else _first_farm_from(d.chronicle)
	wd.store_drops_total = hex_f64(cv.store_drops_total)
	wd.drop_total_tile = _bytes(cv, "drop_total_tile").to_float64_array()
	wd.region_drop = _bytes(cv, "region_drop").to_float64_array()
	wd.store_tiles = _bytes(cv, "store_tiles").to_int32_array()
	wd.store_food = _bytes(cv, "store_food").to_float64_array()
	var s: Dictionary = d.slimes
	wd.s_id = _bytes(s, "id").to_int32_array()
	wd.s_x = _bytes(s, "x").to_int32_array()
	wd.s_y = _bytes(s, "y").to_int32_array()
	wd.s_head = _bytes(s, "head").to_int32_array()
	wd.s_age = _bytes(s, "age").to_int32_array()
	wd.s_gen = _bytes(s, "gen").to_int32_array()
	wd.s_max_age = _bytes(s, "max_age").to_int32_array()
	wd.s_last_repro = _bytes(s, "last_repro").to_int32_array()
	wd.s_last_action = _bytes(s, "last_action").to_int32_array()
	wd.s_energy = _bytes(s, "energy").to_float64_array()
	wd.s_carry = _bytes(s, "carry").to_float64_array()
	wd.s_mem = _bytes(s, "mem").to_float64_array()
	wd.s_genome = _bytes(s, "genome").to_float32_array()
	# v0.2 에서 더한 키(SLIMES_B64_ADDED·LINEAGE_B64_ADDED·STATS_*_ADDED): 옛 파일에 없으면 DESIGN-v0.2 9.1 의 값으로 채움
	var n0 := wd.s_id.size()
	if s.has("last_eff"):
		wd.s_last_eff = _bytes(s, "last_eff")
	else:
		wd.s_last_eff.resize(n0)
		wd.s_last_eff.fill(0)
	if s.has("eaten"):
		wd.s_eaten = _bytes(s, "eaten").to_float64_array()
	else:
		wd.s_eaten.resize(n0)
		wd.s_eaten.fill(0.0)
	var ln: Dictionary = d.lineage
	wd.lin_pa = _bytes(ln, "pa").to_int32_array()
	wd.lin_pb = _bytes(ln, "pb").to_int32_array()
	wd.lin_gen = _bytes(ln, "gen").to_int32_array()
	wd.lin_birth = _bytes(ln, "birth").to_int32_array()
	wd.lin_death = _bytes(ln, "death").to_int32_array()
	wd.lin_cause = _bytes(ln, "cause")
	wd.lin_children = _bytes(ln, "children").to_int32_array()
	wd.lin_size = _bytes(ln, "size").to_float32_array()
	wd.lin_sense = _bytes(ln, "sense").to_float32_array()
	wd.lin_hue = _bytes(ln, "hue").to_float32_array()
	if ln.has("eaten"):
		wd.lin_eaten = _bytes(ln, "eaten").to_float64_array()
	else:
		wd.lin_eaten.resize(wd.lin_pa.size())
		wd.lin_eaten.fill(0.0)
	var st: Dictionary = d.stats
	wd.led_initial = hex_f64(st.led_initial)
	wd.led_eaten = hex_f64(st.led_eaten)
	wd.led_spent = hex_f64(st.led_spent)
	wd.led_repro_loss = hex_f64(st.led_repro_loss)
	wd.led_died = hex_f64(st.led_died)
	# 개체별 먹은 양이 없던 옛 파일: 연 틱부터 셈(그때까지 먹은 양은 장부의 시작점으로, 그때까지 태어난 개체는 평생 값을 모름)
	wd.led_eaten_open = hex_f64(st.led_eaten_open) if st.has("led_eaten_open") else wd.led_eaten
	wd.eaten_from_id = int(st.eaten_from_id) if st.has("eaten_from_id") else wd.lin_pa.size()
	if st.has("period_act"):
		wd.period_act = _bytes(st, "period_act").to_int64_array()
	if st.has("period_eff"):
		wd.period_eff = _bytes(st, "period_eff").to_int64_array()
	wd.total_births = int(st.total_births)
	wd.total_deaths = int(st.total_deaths)
	wd.period_births = int(st.period_births)
	wd.period_deaths = int(st.period_deaths)
	wd.peak_population = int(st.peak_population)
	wd.next_milestone = int(st.next_milestone)
	wd.extinct_tick = int(st.extinct_tick)
	wd.history_hash = d.history_hash
	wd.chronicle = []
	for e in d.chronicle:
		var ee: Dictionary = e.duplicate()
		for key in ["tick", "actor", "stage", "tile"]:
			if ee.has(key):
				ee[key] = int(ee[key])
		wd.chronicle.append(ee)
	var post := validate_world(wd)
	if post != "":
		return {world = null, error = post}
	# 검증 뒤에 칸 번호를 첨자로 쓰는 것들: 바닥 먹이 목록 표시, 칸 성장 속도, 저장고 자리·거리장
	for c in wd.drop_list:
		wd.drop_listed[c] = 1
	for c in wd.w * wd.h:
		wd._update_tile_rates(c)
	wd._rebuild_stores()
	# 유전체에서 계산하는 값과 칸별 개체 수는 저장하지 않고 다시 만든다(검증 뒤에)
	var n := wd.s_id.size()
	for i in n:
		wd._append_derived(wd.s_genome.slice(i * wd._G, (i + 1) * wd._G))
		wd.s_dead.append(0)
		wd.count_grid[wd.s_y[i] * wd.w + wd.s_x[i]] += 1
	wd._compute_time()
	return {world = wd, error = ""}


## 옛 스냅숏(civ.first_farm_tick 없음)의 첫 밭 틱: 연대기의 첫 first_farm 사건 틱(없으면 -1).
static func _first_farm_from(chronicle: Array) -> int:
	for e in chronicle:
		if str(e.get("kind", "")) == "first_farm":
			return int(e.tick)
	return -1


static func from_text(text: String) -> Dictionary:
	var d = JSON.parse_string(text)
	if d == null:
		return {world = null, error = "JSON 을 읽을 수 없습니다"}
	return from_dict(d)


## 스냅숏 형식 1 을 만든 뒤에 더한 설정 키(있는 절의 새 잎). 옛 스냅숏에 없으면 기본값(= 그 키가 생기기 전 코드의 동작)으로 채운다.
const CONFIG_KEYS_ADDED: Array[String] = ["time.night_light_threshold", "repro.inherit", "life.adult_frac", "life.old_frac",
	"body.grow_enabled", "body.birth_size_frac"]
## 형식 1 을 만든 뒤에 더한 설정 절(DESIGN-v0.2 8·9.2). 옛 스냅숏에 그 절이 통째로 없으면 기본값 절을 통째로 넣는다
## (CONFIG_KEYS_ADDED 는 절이 있을 때만 잎을 채우므로). 1단계 = learn(기본값은 학습 끔 — 옛 실행과 같은 동작).
const SECTIONS_ADDED: Array[String] = ["learn"]
## 하위 절의 키(값 종류: b64 = base64 글자, hex = float64 비트 16진 글자, int = 정수인 수).
const MAP_B64: Array[String] = ["tiles", "fert", "base_fert", "food", "dropped", "drop_timer", "drop_list", "sat", "farm_visit", "farms"]
const CIV_B64: Array[String] = ["drop_total_tile", "region_drop", "store_tiles", "store_food"]
const CIV_INT: Array[String] = ["stage", "forage_attempts", "farm_sprouts"]
const CIV_HEX: Array[String] = ["store_drops_total"]
## 형식 1 을 만든 뒤에 더한 civ 정수 키. 있으면 정수여야 하고, 옛 스냅숏에 없으면 연대기에서 다시 만든다(첫 밭 틱).
const CIV_INT_ADDED: Array[String] = ["first_farm_tick"]
const SLIMES_B64: Array[String] = ["id", "x", "y", "head", "age", "gen", "max_age", "last_repro", "last_action", "energy", "carry", "mem", "genome"]
const LINEAGE_B64: Array[String] = ["pa", "pb", "gen", "birth", "death", "cause", "children", "size", "sense", "hue"]
const STATS_HEX: Array[String] = ["led_initial", "led_eaten", "led_spent", "led_repro_loss", "led_died"]
const STATS_INT: Array[String] = ["total_births", "total_deaths", "period_births", "period_deaths", "peak_population", "next_milestone", "extinct_tick"]
## v0.2 에서 더한 키(DESIGN-v0.2 9.1). 있으면 꼴·길이·범위를 검사하고, 옛 스냅숏에 없으면 9.1 표의 '옛 파일에 없으면' 값으로 채운다:
## slimes.last_eff·eaten = 0, lineage.eaten = 0, stats.period_act·period_eff = 0 8개(i64), stats.led_eaten_open = 연 틱의 led_eaten,
## stats.eaten_from_id = 연 틱의 계통 수.
const SLIMES_B64_ADDED: Array[String] = ["last_eff", "eaten"]
const LINEAGE_B64_ADDED: Array[String] = ["eaten"]
const STATS_B64_ADDED: Array[String] = ["period_act", "period_eff"]
const STATS_HEX_ADDED: Array[String] = ["led_eaten_open"]
const STATS_INT_ADDED: Array[String] = ["eaten_from_id"]
## 연대기 사건의 필수 키(글자·수)와, 있으면 수여야 하는 키.
const EVENT_TEXT: Array[String] = ["kind", "text"]
const EVENT_NUM: Array[String] = ["tick", "actor", "mean_gen"]
const EVENT_OPT_NUM: Array[String] = ["stage", "tile"]


## SECTIONS_ADDED 를 검사가 바꿔 볼 수 있는 자리(시험용 새 절 — test_snapshot_v01_fixture). 평소에는 SECTIONS_ADDED 그대로.
static var _sections_added: Array = SECTIONS_ADDED


## 설정 사본을 옛 스냅숏용으로 채운다: SECTIONS_ADDED 가운데 통째로 없는 절은 기본값 절 그대로, 그다음 CONFIG_KEYS_ADDED 가운데
## 없는 잎 키(절이 있을 때)는 기본값으로. 예전에는 잎만 채워 새 절을 기본값에 넣는 순간 옛 스냅숏이 모두 "설정 키가 없습니다"로
## 거부됐을 것(DESIGN-v0.2 9.2).
static func with_added_keys(config: Dictionary) -> Dictionary:
	var out := config.duplicate(true)
	var defs := SimConfig.defaults()
	for sec_name in _sections_added:
		if not out.has(sec_name) and typeof(defs.get(sec_name)) == TYPE_DICTIONARY:
			out[sec_name] = (defs[sec_name] as Dictionary).duplicate(true)
	for key in CONFIG_KEYS_ADDED:
		var parts := key.split(".")
		var sec = out.get(parts[0])
		if typeof(sec) == TYPE_DICTIONARY and not sec.has(parts[1]):
			sec[parts[1]] = SimConfig.get_value(defs, key)
	return out


## 겉모양 검사(키·종류·형식·버전·설정, 하위 절의 키·값 종류·16진 길이·발견 틱 수).
static func validate(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "스냅숏이 사전이 아닙니다"
	if typeof(d.get("format")) != TYPE_STRING or d.format != FORMAT:
		return "형식이 %s 가 아닙니다" % FORMAT
	if typeof(d.get("version")) != TYPE_FLOAT or int(d.version) != VERSION:
		return "지원하지 않는 버전입니다: %s" % str(d.get("version"))
	for key in ["config", "rng", "map", "civ", "slimes", "lineage", "stats"]:
		if typeof(d.get(key)) != TYPE_DICTIONARY:
			return "항목이 없습니다: %s" % key
	if typeof(d.get("chronicle")) != TYPE_ARRAY or typeof(d.get("history_hash")) != TYPE_STRING:
		return "연대기·해시가 없습니다"
	if typeof(d.get("seed")) != TYPE_STRING or not String(d.seed).is_valid_int():
		return "씨앗이 정수 문자열이 아닙니다"
	if not _is_int(d.get("tick")):
		return "틱이 정수가 아닙니다"
	var cerr := SimConfig.validate(with_added_keys(d.config))
	if cerr != "":
		return "설정 오류: " + cerr
	for k in ["world", "life"]:
		if typeof(d.rng.get(k)) != TYPE_STRING or not String(d.rng[k]).is_valid_int():
			return "난수 상태가 정수 문자열이 아닙니다: rng.%s" % k
	var e := _check_keys(d.map, "map", MAP_B64, [], [])
	if e == "":
		e = _check_keys(d.civ, "civ", CIV_B64, CIV_INT, CIV_HEX)
	if e == "":
		e = _check_keys(d.slimes, "slimes", SLIMES_B64, [], [])
	if e == "":
		e = _check_keys(d.lineage, "lineage", LINEAGE_B64, [], [])
	if e == "":
		e = _check_keys(d.stats, "stats", [], STATS_INT, STATS_HEX)
	# v0.2 에서 더한 키: 있을 때만 꼴을 봄(길이는 validate_world)
	if e == "":
		e = _check_keys(d.slimes, "slimes", _present(d.slimes, SLIMES_B64_ADDED), [], [])
	if e == "":
		e = _check_keys(d.lineage, "lineage", _present(d.lineage, LINEAGE_B64_ADDED), [], [])
	if e == "":
		e = _check_keys(d.stats, "stats", _present(d.stats, STATS_B64_ADDED), _present(d.stats, STATS_INT_ADDED), _present(d.stats, STATS_HEX_ADDED))
	if e != "":
		return e
	for k in CIV_INT_ADDED:
		if d.civ.has(k) and (not _is_int(d.civ[k]) or int(d.civ[k]) < -1):
			return "civ.%s 가 정수(-1 이상)가 아닙니다" % k
	var dt = d.civ.get("discovery_tick")
	if typeof(dt) != TYPE_ARRAY or (dt as Array).size() != SimWorld.STAGE_FARM + 1:
		return "civ.discovery_tick 은 단계 %d개의 배열이어야 합니다" % (SimWorld.STAGE_FARM + 1)
	for t in dt:
		if not _is_int(t) or int(t) < -1:
			return "civ.discovery_tick 값이 잘못되었습니다: %s" % str(t)
	for ev in d.chronicle:
		if typeof(ev) != TYPE_DICTIONARY:
			return "연대기 항목이 사전이 아닙니다"
		for k in EVENT_TEXT:
			if typeof(ev.get(k)) != TYPE_STRING:
				return "연대기 항목에 %s(글자)가 없습니다" % k
		for k in EVENT_NUM:
			if not _is_num(ev.get(k)):
				return "연대기 항목에 %s(수)가 없습니다" % k
		for k in EVENT_OPT_NUM:
			if ev.has(k) and not _is_num(ev[k]):
				return "연대기 항목의 %s 가 수가 아닙니다" % k
	return ""


## 절 sec 의 키: b64 는 글자(빈 글자 = 빈 배열), int 는 정수인 수, hex 는 float64 비트 16진 글자(16자, 유한한 수).
static func _check_keys(sec: Dictionary, name: String, b64_keys: Array, int_keys: Array, hex_keys: Array) -> String:
	for k in b64_keys:
		if typeof(sec.get(k)) != TYPE_STRING:
			return "%s.%s 가 없거나 글자가 아닙니다" % [name, k]
	for k in int_keys:
		if not _is_int(sec.get(k)):
			return "%s.%s 가 없거나 정수가 아닙니다" % [name, k]
	for k in hex_keys:
		var v = sec.get(k)
		if typeof(v) != TYPE_STRING or (v as String).length() != F64_BYTES * 2 or (v as String).hex_decode().size() != F64_BYTES:
			return "%s.%s 가 없거나 실수 16진 글자(16자)가 아닙니다" % [name, k]
		if not is_finite(hex_f64(v)):
			return "%s.%s 가 유한한 수가 아닙니다" % [name, k]
	return ""


## keys 가운데 sec 에 있는 것만.
static func _present(sec: Dictionary, keys: Array[String]) -> Array:
	var out := []
	for k in keys:
		if sec.has(k):
			out.append(k)
	return out


static func _is_num(v: Variant) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v))


static func _is_int(v: Variant) -> bool:
	return _is_num(v) and float(v) == floorf(float(v))


## 실수 배열이 모두 유한한지.
static func _finite(arr: Variant) -> bool:
	for v in arr:
		if not is_finite(v):
			return false
	return true


## 칸 번호 배열이 모두 지도 안인지.
static func _cells_ok(arr: PackedInt32Array, cells: int) -> bool:
	for c in arr:
		if c < 0 or c >= cells:
			return false
	return true


## 복원한 세계의 내부 일관성 검사(길이·범위·순서·유전체 길이·칸 번호·유한한 수). from_dict 가 칸 번호를 첨자로 쓰기 전에 부른다.
static func validate_world(wd: SimWorld) -> String:
	var cells := wd.w * wd.h
	if wd.tiles.size() != cells or wd.food.size() != cells or wd.fert.size() != cells or wd.dropped.size() != cells \
			or wd.drop_timer.size() != cells or wd.sat.size() != (wd.w + 1) * (wd.h + 1) or wd.farm_visit.size() != cells \
			or wd.base_fert.size() != cells or wd.drop_total_tile.size() != cells or wd.region_drop.size() != wd.regions_x * wd.regions_y:
		return "지도 배열 길이가 맞지 않습니다"
	for t in wd.tiles:
		if t > SimGrid.TILE_FARM:
			return "칸 종류가 잘못되었습니다: %d" % t
	if not _cells_ok(wd.drop_list, cells) or not _cells_ok(wd.farms, cells):
		return "바닥 먹이·밭 칸 번호가 지도 밖입니다"
	for arr in [wd.fert, wd.base_fert, wd.food, wd.dropped, wd.sat, wd.drop_total_tile, wd.region_drop, wd.store_food]:
		if not _finite(arr):
			return "지도·저장고 값에 유한하지 않은 수가 있습니다"
	var n := wd.s_id.size()
	for arr in [wd.s_x, wd.s_y, wd.s_head, wd.s_age, wd.s_gen, wd.s_max_age, wd.s_last_repro, wd.s_last_action, wd.s_energy, wd.s_carry]:
		if arr.size() != n:
			return "슬라임 배열 길이가 맞지 않습니다"
	if wd.s_genome.size() != n * wd._G:
		return "유전체 길이가 맞지 않습니다(개체 %d × 유전자 %d 이어야 함, 실제 %d)" % [n, wd._G, wd.s_genome.size()]
	if wd.s_mem.size() != n * wd._n_mem:
		return "기억 배열 길이가 맞지 않습니다"
	if not _finite(wd.s_genome) or not _finite(wd.s_mem) or not _finite(wd.s_carry):
		return "유전체·기억·운반 값에 유한하지 않은 수가 있습니다"
	if wd.s_last_eff.size() != n or wd.s_eaten.size() != n:
		return "슬라임 배열 길이가 맞지 않습니다(last_eff·eaten)"
	for v in wd.s_last_eff:
		if v > 1:
			return "개체의 효과 표시(last_eff)가 0·1 이 아닙니다"
	if not _finite(wd.s_eaten) or not _finite(wd.lin_eaten):
		return "먹은 양(eaten)에 유한하지 않은 수가 있습니다"
	for arr in [wd.s_eaten, wd.lin_eaten]:
		for v in arr:
			if v < 0.0:
				return "먹은 양(eaten)에 음수가 있습니다: %s" % str(v)
	if wd.period_act.size() != SimBrain.BASE_OUTPUTS or wd.period_eff.size() != SimBrain.BASE_OUTPUTS:
		return "행동 셈(period_act·period_eff)은 행동 %d개의 배열이어야 합니다" % SimBrain.BASE_OUTPUTS
	for a in SimBrain.BASE_OUTPUTS:
		if wd.period_act[a] < 0 or wd.period_eff[a] < 0 or wd.period_eff[a] > wd.period_act[a]:
			return "행동 셈이 잘못되었습니다(행동 %d: 고름 %d, 효과 %d)" % [a, wd.period_act[a], wd.period_eff[a]]
	var lc := wd.lin_pa.size()
	for arr in [wd.lin_pb, wd.lin_gen, wd.lin_birth, wd.lin_death, wd.lin_cause, wd.lin_children, wd.lin_size, wd.lin_sense, wd.lin_hue, wd.lin_eaten]:
		if arr.size() != lc:
			return "계통 배열 길이가 맞지 않습니다"
	for id in lc:
		if wd.lin_pa[id] < SimWorld.NO_PARENT or wd.lin_pa[id] >= id or wd.lin_pb[id] < SimWorld.NO_PARENT or wd.lin_pb[id] >= id:
			return "계통의 부모 id 가 잘못되었습니다(개체 %d)" % id
		if wd.lin_cause[id] > SimWorld.CAUSE_OLD:
			return "계통의 사망 원인이 잘못되었습니다(개체 %d)" % id
		if wd.lin_cause[id] == SimWorld.CAUSE_ALIVE and wd.lin_eaten[id] != 0.0:
			return "살아 있는 개체의 계통 먹은 양(lineage.eaten)은 0 이어야 합니다(개체 %d: %s — 죽을 때 씀)" % [id, str(wd.lin_eaten[id])]
	if wd.eaten_from_id < 0 or wd.eaten_from_id > lc:
		return "먹은 양을 센 첫 개체 id(eaten_from_id %d)가 계통 0~%d 밖입니다" % [wd.eaten_from_id, lc]
	var prev := -1
	for i in n:
		if wd.s_id[i] <= prev or wd.s_id[i] >= lc:
			return "개체 id 순서·범위가 잘못되었습니다"
		prev = wd.s_id[i]
		if wd.s_x[i] < 0 or wd.s_y[i] < 0 or wd.s_x[i] >= wd.w or wd.s_y[i] >= wd.h:
			return "개체 위치가 지도 밖입니다"
		if not SimGrid.passable(wd.tiles[wd.s_y[i] * wd.w + wd.s_x[i]]):
			return "개체가 지날 수 없는 칸에 있습니다"
		if wd.s_head[i] < 0 or wd.s_head[i] >= SimGrid.DIR_COUNT:
			return "개체 방향이 잘못되었습니다"
		if wd.s_last_action[i] < 0 or wd.s_last_action[i] >= SimBrain.BASE_OUTPUTS:
			return "개체의 마지막 행동이 잘못되었습니다"
		if is_nan(wd.s_energy[i]) or is_inf(wd.s_energy[i]):
			return "개체 에너지가 수가 아닙니다"
	if not _cells_ok(wd.store_tiles, cells):
		return "저장고 위치가 지도 밖입니다"
	if wd.store_food.size() != wd.store_tiles.size():
		return "저장고 배열 길이가 맞지 않습니다"
	if wd.stage < SimWorld.STAGE_NONE or wd.stage > SimWorld.STAGE_FARM:
		return "문명 단계가 잘못되었습니다"
	if wd.tick < 0:
		return "틱이 음수입니다"
	for v in [wd.led_initial, wd.led_eaten, wd.led_spent, wd.led_repro_loss, wd.led_died, wd.store_drops_total, wd.led_eaten_open]:
		if not is_finite(v):
			return "장부 값이 유한한 수가 아닙니다"
	if wd.led_eaten_open < 0.0 or wd.led_eaten_open > wd.led_eaten:
		return "먹은 양 장부의 시작점(led_eaten_open %s)이 0~led_eaten(%s) 밖입니다" % [str(wd.led_eaten_open), str(wd.led_eaten)]
	return ""


# ════════════ 파일 저장(임시 파일 → 검증 → 교체, .bak 보관) ════════════

## path 에 저장. 성공 "" / 실패 문장(파일 이름을 담음). 실패는 반환값을 버리는 호출자가 있어도 로그에 남도록 push_error 로도 알린다
## (이전 save_manager 와 같음). 쓰기·검증에 실패한 임시 파일은 지운다(교체 실패면 그것이 유일한 새 사본이라 남김).
static func save_file(wd: SimWorld, path: String) -> String:
	var text := to_text(wd)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _save_failed("저장 실패 — %s 를 열 수 없음(%s)" % [tmp.get_file(), error_string(FileAccess.get_open_error())], path)
	var ok := f.store_string(text)
	f.close()
	if not ok:
		DirAccess.remove_absolute(tmp)
		return _save_failed("저장 실패 — %s 를 다 쓰지 못함" % tmp.get_file(), path)
	var check := from_text(FileAccess.get_file_as_string(tmp))
	if check.error != "":
		DirAccess.remove_absolute(tmp)
		return _save_failed("저장 검증 실패(%s): %s" % [path.get_file(), check.error], path)
	var bak := path + ".bak"
	if FileAccess.file_exists(path):
		if from_text(FileAccess.get_file_as_string(path)).error == "":
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(bak)
			DirAccess.copy_absolute(path, bak)
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return _save_failed("저장 교체 실패 — %s → %s(%s)" % [tmp.get_file(), path.get_file(), error_string(err)], path)
	return ""


static func _save_failed(msg: String, path: String) -> String:
	push_error("%s [%s]" % [msg, path])
	return msg


## path 에서 읽기. 본 파일이 깨졌으면 .bak 으로, 그것도 안 되면 실패. 결과: {world, status, error}
## status: "loaded" | "backup" | "failed". 깨진 본 파일은 .broken 으로 보관한다.
static func load_file(path: String) -> Dictionary:
	var first_err := "파일이 없습니다"
	if FileAccess.file_exists(path):
		var r := from_text(FileAccess.get_file_as_string(path))
		if r.get("world") != null and str(r.get("error", "?")) == "":
			return {world = r.world, status = "loaded", error = ""}
		first_err = str(r.get("error", "스냅숏을 읽지 못했습니다"))
		DirAccess.copy_absolute(path, path + ".broken")
	var bak := path + ".bak"
	if FileAccess.file_exists(bak):
		var rb := from_text(FileAccess.get_file_as_string(bak))
		if rb.get("world") != null and str(rb.get("error", "?")) == "":
			return {world = rb.world, status = "backup", error = first_err}
	return {world = null, status = "failed", error = first_err}
