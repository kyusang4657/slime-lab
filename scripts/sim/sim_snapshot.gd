class_name SimSnapshot
extends RefCounted
## 세계 스냅숏(저장·복원). 형식: docs/DESIGN-v0.1.md 8.3.
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
			farm_sprouts = wd.farm_sprouts, store_drops_total = f64_hex(wd.store_drops_total),
			drop_total_tile = b64(wd.drop_total_tile), region_drop = b64(wd.region_drop),
			store_tiles = b64(wd.store_tiles), store_food = b64(wd.store_food),
		},
		slimes = {
			count = wd.s_id.size(), id = b64(wd.s_id), x = b64(wd.s_x), y = b64(wd.s_y), head = b64(wd.s_head),
			age = b64(wd.s_age), gen = b64(wd.s_gen), max_age = b64(wd.s_max_age), last_repro = b64(wd.s_last_repro),
			last_action = b64(wd.s_last_action), energy = b64(wd.s_energy), carry = b64(wd.s_carry),
			mem = b64(wd.s_mem), genome = b64(wd.s_genome),
		},
		lineage = {
			count = wd.lin_pa.size(), pa = b64(wd.lin_pa), pb = b64(wd.lin_pb), gen = b64(wd.lin_gen),
			birth = b64(wd.lin_birth), death = b64(wd.lin_death), cause = b64(wd.lin_cause),
			children = b64(wd.lin_children), size = b64(wd.lin_size), sense = b64(wd.lin_sense), hue = b64(wd.lin_hue),
		},
		stats = {
			led_initial = f64_hex(wd.led_initial), led_eaten = f64_hex(wd.led_eaten), led_spent = f64_hex(wd.led_spent),
			led_repro_loss = f64_hex(wd.led_repro_loss), led_died = f64_hex(wd.led_died),
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
static func from_dict(d: Variant) -> Dictionary:
	var err := validate(d)
	if err != "":
		return {world = null, error = err}
	var wd := SimWorld.new()
	var cfg: Dictionary = d.config
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
	for c in wd.drop_list:
		wd.drop_listed[c] = 1
	for c in wd.w * wd.h:
		wd._update_tile_rates(c)
	var cv: Dictionary = d.civ
	wd.stage = int(cv.stage)
	for k in wd.discovery_tick.size():
		wd.discovery_tick[k] = int(cv.discovery_tick[k])
	wd.forage_attempts = int(cv.forage_attempts)
	wd.farm_sprouts = int(cv.farm_sprouts)
	wd.store_drops_total = hex_f64(cv.store_drops_total)
	wd.drop_total_tile = _bytes(cv, "drop_total_tile").to_float64_array()
	wd.region_drop = _bytes(cv, "region_drop").to_float64_array()
	wd.store_tiles = _bytes(cv, "store_tiles").to_int32_array()
	wd.store_food = _bytes(cv, "store_food").to_float64_array()
	wd._rebuild_stores()
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
	var st: Dictionary = d.stats
	wd.led_initial = hex_f64(st.led_initial)
	wd.led_eaten = hex_f64(st.led_eaten)
	wd.led_spent = hex_f64(st.led_spent)
	wd.led_repro_loss = hex_f64(st.led_repro_loss)
	wd.led_died = hex_f64(st.led_died)
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
	# 유전체에서 계산하는 값과 칸별 개체 수는 저장하지 않고 다시 만든다(검증 뒤에)
	var n := wd.s_id.size()
	for i in n:
		wd._append_derived(wd.s_genome.slice(i * wd._G, (i + 1) * wd._G))
		wd.s_dead.append(0)
		wd.count_grid[wd.s_y[i] * wd.w + wd.s_x[i]] += 1
	wd._compute_time()
	return {world = wd, error = ""}


static func from_text(text: String) -> Dictionary:
	var d = JSON.parse_string(text)
	if d == null:
		return {world = null, error = "JSON 을 읽을 수 없습니다"}
	return from_dict(d)


## 겉모양 검사(키·종류·형식·버전·설정).
static func validate(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "스냅숏이 사전이 아닙니다"
	if d.get("format") != FORMAT:
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
	var cerr := SimConfig.validate(d.config)
	if cerr != "":
		return "설정 오류: " + cerr
	if not String(d.rng.get("world", "")).is_valid_int() or not String(d.rng.get("life", "")).is_valid_int():
		return "난수 상태가 정수 문자열이 아닙니다"
	return ""


## 복원한 세계의 내부 일관성 검사(길이·범위·순서·유전체 길이).
static func validate_world(wd: SimWorld) -> String:
	var cells := wd.w * wd.h
	if wd.tiles.size() != cells or wd.food.size() != cells or wd.fert.size() != cells or wd.dropped.size() != cells \
			or wd.drop_timer.size() != cells or wd.sat.size() != (wd.w + 1) * (wd.h + 1) or wd.farm_visit.size() != cells \
			or wd.base_fert.size() != cells or wd.drop_total_tile.size() != cells or wd.region_drop.size() != wd.regions_x * wd.regions_y:
		return "지도 배열 길이가 맞지 않습니다"
	var n := wd.s_id.size()
	for arr in [wd.s_x, wd.s_y, wd.s_head, wd.s_age, wd.s_gen, wd.s_max_age, wd.s_last_repro, wd.s_last_action, wd.s_energy, wd.s_carry]:
		if arr.size() != n:
			return "슬라임 배열 길이가 맞지 않습니다"
	if wd.s_genome.size() != n * wd._G:
		return "유전체 길이가 맞지 않습니다(개체 %d × 유전자 %d 이어야 함, 실제 %d)" % [n, wd._G, wd.s_genome.size()]
	if wd.s_mem.size() != n * wd._n_mem:
		return "기억 배열 길이가 맞지 않습니다"
	var lc := wd.lin_pa.size()
	for arr in [wd.lin_pb, wd.lin_gen, wd.lin_birth, wd.lin_death, wd.lin_cause, wd.lin_children, wd.lin_size, wd.lin_sense, wd.lin_hue]:
		if arr.size() != lc:
			return "계통 배열 길이가 맞지 않습니다"
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
		if is_nan(wd.s_energy[i]) or is_inf(wd.s_energy[i]):
			return "개체 에너지가 수가 아닙니다"
	for c in wd.store_tiles:
		if c < 0 or c >= cells:
			return "저장고 위치가 지도 밖입니다"
	if wd.store_food.size() != wd.store_tiles.size():
		return "저장고 배열 길이가 맞지 않습니다"
	if wd.stage < SimWorld.STAGE_NONE or wd.stage > SimWorld.STAGE_FARM:
		return "문명 단계가 잘못되었습니다"
	if wd.tick < 0:
		return "틱이 음수입니다"
	return ""


# ════════════ 파일 저장(임시 파일 → 검증 → 교체, .bak 보관) ════════════

## path 에 저장. 성공 "" / 실패 문장.
static func save_file(wd: SimWorld, path: String) -> String:
	var text := to_text(wd)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "저장 실패: %s" % error_string(FileAccess.get_open_error())
	f.store_string(text)
	f.close()
	var check := from_text(FileAccess.get_file_as_string(tmp))
	if check.error != "":
		return "저장 검증 실패: " + check.error
	var bak := path + ".bak"
	if FileAccess.file_exists(path):
		if from_text(FileAccess.get_file_as_string(path)).error == "":
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(bak)
			DirAccess.copy_absolute(path, bak)
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return "저장 교체 실패: %s" % error_string(err)
	return ""


## path 에서 읽기. 본 파일이 깨졌으면 .bak 으로, 그것도 안 되면 실패. 결과: {world, status, error}
## status: "loaded" | "backup" | "failed". 깨진 본 파일은 .broken 으로 보관한다.
static func load_file(path: String) -> Dictionary:
	var first_err := "파일이 없습니다"
	if FileAccess.file_exists(path):
		var r := from_text(FileAccess.get_file_as_string(path))
		if r.error == "":
			return {world = r.world, status = "loaded", error = ""}
		first_err = r.error
		DirAccess.copy_absolute(path, path + ".broken")
	var bak := path + ".bak"
	if FileAccess.file_exists(bak):
		var rb := from_text(FileAccess.get_file_as_string(bak))
		if rb.error == "":
			return {world = rb.world, status = "backup", error = first_err}
	return {world = null, status = "failed", error = first_err}
