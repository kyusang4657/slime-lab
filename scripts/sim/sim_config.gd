class_name SimConfig
extends RefCounted
## config/*.json 을 읽어 실험 설정을 만든다. 수치의 단일 기준은 JSON 이다.
## 실험 설정 = 기본값(sim-defaults.json) + 예설정(presets.json) + 덮어쓰기("a.b=값").

const DEFAULTS_PATH := "res://config/sim-defaults.json"
const PRESETS_PATH := "res://config/presets.json"

## 틱 단위 키·실행 틱의 상한. 틱 값은 PackedInt32Array(2^31 − 1 까지)에 담기므로 그보다 작게 —
## 최대 나이 + 수명 흔들림(둘 다 이 값까지)도 2^31 − 1 을 넘지 않는다.
const TICK_MAX := 1000000000
## 범위 규칙의 넷째 칸: 하한을 빼는 범위("0 초과" — 나눗수로 쓰여 0 이면 0 으로 나눔).
const ABOVE := "초과"
## 수 잎 키의 범위 [키, 하한, 상한(, ABOVE)]. 모든 수 잎 키가 여기에 있다. config/sim-labels.json 의 범위 글과 같은 수
## (tools/test_sim_labels.py 가 대조). 정수 키(sim-defaults.json 에 소수점 없이 적힌 키)는 정수만 받는다.
const RULES := [
	["map.width", 8, 1024], ["map.height", 8, 1024],
	["map.noise_cell", 1, 1024], ["map.noise_detail_cell", 1, 1024], ["map.noise_detail_weight", 0.0, 1.0],
	["map.water_level", 0.0, 1.0], ["map.rock_noise_cell", 1, 1024], ["map.rock_level", 0.0, 1.0],
	["map.fertility_floor", 0.0, 1.0],
	["time.day_ticks", 2, 100000], ["time.daylight_fraction", 0.0, 1.0], ["time.twilight_ticks", 0, 100000],
	["time.season_days", 0, 100000], ["time.night_light_threshold", 0.0, 1.0],
	["plants.max_food", 0.0, 1e9, ABOVE], ["plants.regrow", 0.0, 1e6], ["plants.night_growth", 0.0, 1.0],
	["plants.update_every", 1, 1000], ["plants.initial_fill", 0.0, 1.0],
	["resources.scale", 0.0, 100.0],
	["dropped.spoil_ticks", 1, TICK_MAX], ["dropped.sprout_chance", 0.0, 1.0], ["dropped.sprout_food", 0.0, 1e6],
	["dropped.sprout_fertility", 0.0, 1.0],
	["body.energy_per_size", 0.0, 1e6, ABOVE], ["body.start_energy_frac", 0.0, 1.0],
	["metab.base", 0.0, 1e6], ["metab.sense_cost", 0.0, 1e6], ["metab.move", 0.0, 1e6], ["metab.rest_factor", 0.0, 1.0],
	["eat.bite", 0.0, 1e6, ABOVE], ["eat.efficiency", 0.0, 1.0, ABOVE],
	["life.max_age", 1, TICK_MAX], ["life.max_age_jitter", 0, TICK_MAX],
	["repro.maturity", 0, TICK_MAX], ["repro.min_energy_frac", 0.0, 1.0], ["repro.cost_frac", 0.0, 1.0],
	["repro.transfer_efficiency", 0.0, 1.0], ["repro.cooldown", 0, TICK_MAX], ["repro.mate_radius", 0, 100000],
	["population.initial", 0, 100000], ["population.cap", 1, 100000], ["population.initial_age_spread", 0, TICK_MAX],
	["sense.crowd_radius", 0, 100000], ["sense.crowd_norm", 0.0, 1e6, ABOVE], ["sense.night_factor", 0.0, 1.0],
	["traits.size_min", 0.01, 100.0], ["traits.size_max", 0.01, 100.0], ["traits.size_init", 0.01, 100.0],
	["traits.sense_min", 0.5, 64.0], ["traits.sense_max", 0.5, 64.0], ["traits.sense_init", 0.5, 64.0],
	["traits.mutation_scale_size", 0.0, 100.0], ["traits.mutation_scale_sense", 0.0, 100.0],
	["traits.mutation_scale_hue", 0.0, 100.0],
	["brain.hidden", 1, 64], ["brain.memory_units", 0, 16], ["brain.think_every", 1, 100],
	["brain.weight_clamp", 0.0, 1e6, ABOVE], ["brain.init_range", 0.0, 1e6], ["brain.sharpness", 0, 64],
	["mutation.rate", 0.0, 1.0], ["mutation.sigma", 0.0, 100.0],
	["carry.max", 0.0, 1e6, ABOVE],
	["store.capacity", 0.0, 1e9, ABOVE], ["store.max_count", 1, 100000], ["store.min_spacing", 0, 100000],
	["farm.radius", 0, 100000], ["farm.seed_cost", 0.0, 1e6], ["farm.growth_mult", 0.0, 100.0],
	["farm.max_mult", 0.0, 100.0], ["farm.winter_floor", 0.0, 100.0], ["farm.abandon_ticks", 1, TICK_MAX],
	["discovery.region_size", 1, 1024], ["discovery.forage_min_energy_frac", 0.0, 1.0],
	["discovery.forage_threshold", 1, 1000000000], ["discovery.store_threshold", 0.0, 1e9, ABOVE],
	["discovery.farm_radius", 0, 100000], ["discovery.farm_threshold", 1, 1000000000],
	["hash.every", 1, 1000000], ["record.every", 1, 1000000], ["record.generation_milestone", 0, 1000000],
	["run.max_ticks", 1, TICK_MAX],
]
## 배열 잎 키: 원소마다 [키, 하한, 상한](원소는 수, 길이는 기본값과 같아야 함).
const ARRAY_RULES := [
	["seasons.growth", 0.0, 100.0],
]
## 글자 잎 키: 고를 수 있는 값(SimBrain.POLICY_* 와 같음 — 검사).
const CHOICES := {
	"brain.policy": ["sample", "argmax"],
}

static var _defaults_cache: Dictionary = {}
static var _presets_cache: Dictionary = {}
static var _int_keys_cache: Dictionary = {}
## 예설정 파일 경로(검사가 읽지 못하는 파일로 바꿔 봄).
static var _presets_path := PRESETS_PATH


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## 기본값의 깊은 사본.
static func defaults() -> Dictionary:
	if not _load_defaults():
		return {}
	return _defaults_cache.duplicate(true)


static func _load_defaults() -> bool:
	if _defaults_cache.is_empty():
		var d = load_json(DEFAULTS_PATH)
		if typeof(d) != TYPE_DICTIONARY:
			push_error("설정 파일을 읽을 수 없습니다: %s" % DEFAULTS_PATH)
			return false
		_defaults_cache = d
	return true


## 예설정 파일을 읽는다. 읽지 못하면(없음·깨짐·사전이 아님) 경로를 알리고 false.
static func _load_presets() -> bool:
	if _presets_cache.is_empty():
		var d = load_json(_presets_path)
		if typeof(d) != TYPE_DICTIONARY:
			push_error("설정 파일을 읽을 수 없습니다: %s" % _presets_path)
			return false
		_presets_cache = d
	return true


static func presets() -> Dictionary:
	if not _load_presets():
		return {}
	var out := _presets_cache.duplicate(true)
	out.erase("_comment")
	return out


static func preset_names() -> PackedStringArray:
	var names := PackedStringArray()
	for k in presets().keys():
		names.append(k)
	return names


## 정수 키 집합(키 → true). JSON 을 읽으면 수가 모두 실수가 되므로 sim-defaults.json 글자에서 소수점 없이 적힌 수를 고른다
## (ParamPanel 의 정수 칸과 같은 판정).
static func int_keys() -> Dictionary:
	if _int_keys_cache.is_empty():
		var text := FileAccess.get_file_as_string(DEFAULTS_PATH)
		var sec_re := RegEx.create_from_string("\"(\\w+)\"\\s*:\\s*\\{([^{}]*)\\}")
		var int_re := RegEx.create_from_string("\"(\\w+)\"\\s*:\\s*(-?\\d+)\\s*(?=[,}\\s])")
		for m in sec_re.search_all(text):
			for l in int_re.search_all(m.get_string(2)):
				_int_keys_cache[m.get_string(1) + "." + l.get_string(1)] = true
	return _int_keys_cache


## 실험 설정을 만든다. 결과: {config, error}. error 가 "" 이면 성공.
static func build(preset: String = "default", overrides: Dictionary = {}) -> Dictionary:
	var cfg := defaults()
	if cfg.is_empty():
		return {config = {}, error = "기본 설정을 읽지 못했습니다: %s" % DEFAULTS_PATH}
	if preset != "":
		if not _load_presets():
			return {config = {}, error = "예설정 파일을 읽지 못했습니다: %s" % _presets_path}
		var ps := presets()
		if not ps.has(preset):
			return {config = {}, error = "알 수 없는 예설정: %s" % preset}
		var sets: Dictionary = ps[preset].get("set", {})
		for k in sets:
			var e := set_value(cfg, k, sets[k])
			if e != "":
				return {config = {}, error = "예설정 %s: %s" % [preset, e]}
	for k in overrides:
		var e2 := set_value(cfg, k, overrides[k])
		if e2 != "":
			return {config = {}, error = e2}
	var err := validate(cfg)
	return {config = cfg if err == "" else {}, error = err}


## "a.b" 잎 키에 값을 넣는다. 기본값에 없는 키나 종류가 다른 값은 거부한다(오타가 조용히 무시되지 않게).
## 절("body" 같은 사전)은 통째로 바꾸지 않는다 — 안의 모르는 키·빠진 키가 섞이지 않게 잎 키로만 바꾼다.
static func set_value(cfg: Dictionary, dotted: String, value: Variant) -> String:
	var parts := dotted.split(".")
	var node: Variant = cfg
	for i in parts.size() - 1:
		if typeof(node) != TYPE_DICTIONARY or not node.has(parts[i]):
			return "알 수 없는 설정 키: %s" % dotted
		node = node[parts[i]]
	var leaf := parts[parts.size() - 1]
	if typeof(node) != TYPE_DICTIONARY or not node.has(leaf):
		return "알 수 없는 설정 키: %s" % dotted
	var old: Variant = node[leaf]
	if typeof(old) == TYPE_DICTIONARY:
		return "설정 %s 는 절입니다 — 잎 키(%s.키)로 하나씩 바꿔 주세요" % [dotted, dotted]
	var v: Variant = value
	if typeof(old) == TYPE_FLOAT and typeof(v) == TYPE_INT:
		v = float(v)
	if typeof(old) != typeof(v):
		return "설정 %s 의 종류가 다릅니다(기존 %s, 새 값 %s)" % [dotted, type_string(typeof(old)), type_string(typeof(v))]
	if typeof(old) == TYPE_ARRAY and (old as Array).size() != (v as Array).size():
		return "설정 %s 의 길이가 다릅니다" % dotted
	node[leaf] = v
	return ""


## 명령줄 "--set=a.b=값" 의 값 부분을 해석한다(JSON 으로 읽히면 JSON, 아니면 문자열).
## JSON 인스턴스로 읽어 글자 값(예: argmax)에 엔진 'Parse JSON failed' 줄이 남지 않게 한다.
static func parse_value(text: String) -> Variant:
	var j := JSON.new()
	if j.parse(text) != OK:
		return text
	return j.data


static func get_value(cfg: Dictionary, dotted: String) -> Variant:
	var node: Variant = cfg
	for p in dotted.split("."):
		if typeof(node) != TYPE_DICTIONARY or not node.has(p):
			return null
		node = node[p]
	return node


## 정수로 적는 수의 크기 상한: 이보다 크면 int 로 바꿀 때 64비트를 넘쳐 다른 값(INT64_MIN)이 되므로 그대로 적는다.
const INT_TEXT_MAX := 1e15


## 수 값을 글로(정수 키는 정수로 — JSON 에서 읽은 수가 실수라 "1.0" 으로 보이지 않게, 아주 큰 수는 그대로).
static func num_text(v: Variant, as_int: bool) -> String:
	var f := float(v)
	if is_finite(f) and absf(f) < INT_TEXT_MAX and (as_int or f == floorf(f)):
		return str(int(f))
	return str(v)


## 규칙의 범위 글("8~1024", "0 초과 ~ 1000000").
static func range_text(r: Array) -> String:
	var lo := num_text(r[1], typeof(r[1]) == TYPE_INT)
	var hi := num_text(r[2], typeof(r[2]) == TYPE_INT)
	if r.size() > 3 and r[3] == ABOVE:
		return "%s 초과 ~ %s" % [lo, hi]
	return "%s~%s" % [lo, hi]


## 구조·범위·정수·고를 값·관계 검사. 문제가 없으면 "".
static func validate(cfg: Dictionary) -> String:
	if not _load_defaults():
		return "기본 설정을 읽지 못했습니다: %s" % DEFAULTS_PATH
	# 구조: 절·잎 키가 기본값과 같고(빠진 키·모르는 키 없음) 잎 값의 종류도 같다("_" 로 시작하는 설명 키는 뺌).
	var shape := _check_shape(cfg, _defaults_cache, "")
	if shape != "":
		return shape
	var ints := int_keys()
	for r in RULES:
		var key: String = r[0]
		var v = get_value(cfg, key)
		var as_int := ints.has(key)
		if not is_finite(float(v)):
			return "설정 %s = %s: 유한한 수여야 합니다" % [key, str(v)]
		if as_int and float(v) != floorf(float(v)):
			return "설정 %s = %s: 정수여야 합니다" % [key, str(v)]
		var below: bool = v <= r[1] if (r.size() > 3 and r[3] == ABOVE) else v < r[1]
		if below or v > r[2]:
			return "설정 %s = %s: 범위 %s 밖입니다" % [key, num_text(v, as_int), range_text(r)]
	for r in ARRAY_RULES:
		var key2: String = r[0]
		for x in get_value(cfg, key2):
			if typeof(x) != TYPE_FLOAT and typeof(x) != TYPE_INT:
				return "설정 %s 의 원소는 수여야 합니다: %s" % [key2, str(x)]
			if not is_finite(float(x)) or x < r[1] or x > r[2]:
				return "설정 %s 의 원소 %s: 범위 %s 밖입니다" % [key2, num_text(x, false), range_text(r)]
	for key3: String in CHOICES:
		var c = get_value(cfg, key3)
		if not (CHOICES[key3] as Array).has(c):
			return "설정 %s = \"%s\": %s 가운데 하나여야 합니다" % [key3, str(c), " / ".join(PackedStringArray(CHOICES[key3]))]
	if cfg.traits.size_min > cfg.traits.size_init or cfg.traits.size_init > cfg.traits.size_max:
		return "traits.size_init 이 size_min~size_max 밖입니다"
	if cfg.traits.sense_min > cfg.traits.sense_init or cfg.traits.sense_init > cfg.traits.sense_max:
		return "traits.sense_init 이 sense_min~sense_max 밖입니다"
	# 빛 곡선: 해 뜨고 지는 시간이 낮 길이의 절반을 넘으면 한낮 없이 빛이 끊겨 뛴다.
	var half_day := float(cfg.time.day_ticks) * float(cfg.time.daylight_fraction) / 2.0
	if float(cfg.time.twilight_ticks) > half_day:
		return "설정 time.twilight_ticks = %s: 하루 길이 × 낮 비율 ÷ 2 = %s 이하여야 합니다" % [
				num_text(cfg.time.twilight_ticks, true), num_text(half_day, false)]
	# 수명: 최대 나이 ± 흔들림이 1틱 이상이 되게.
	if cfg.life.max_age_jitter >= cfg.life.max_age:
		return "설정 life.max_age_jitter = %s: life.max_age(%s)보다 작아야 합니다" % [
				num_text(cfg.life.max_age_jitter, true), num_text(cfg.life.max_age, true)]
	# 스냅숏은 설정을 JSON 글자로 저장한다. 글자로 바꿨다 다시 읽어 같은 값이 되어야 한다(유효숫자 15자리 이내).
	var again = JSON.parse_string(JSON.stringify(cfg))
	if not deep_equal(again, cfg):
		return "설정 값 중 JSON 으로 정확히 왕복하지 않는 수가 있습니다(유효숫자 15자리 이내로 적어 주세요)"
	return ""


## cfg 가 기본값 ref 와 같은 모양인지(prefix = 절 이름 + "."). 문제가 없으면 "".
static func _check_shape(cfg: Dictionary, ref: Dictionary, prefix: String) -> String:
	for k: String in ref:
		if not k.begins_with("_") and not cfg.has(k):
			return "설정 키가 없습니다: %s" % (prefix + k)
	for k: String in cfg:
		if k.begins_with("_"):
			continue
		if not ref.has(k):
			return "알 수 없는 설정 키: %s" % (prefix + k)
		var a: Variant = cfg[k]
		var b: Variant = ref[k]
		if typeof(b) == TYPE_DICTIONARY:
			if typeof(a) != TYPE_DICTIONARY:
				return "설정 %s 는 절(사전)이어야 합니다" % (prefix + k)
			var e := _check_shape(a, b, prefix + k + ".")
			if e != "":
				return e
		elif not _same_kind(a, b):
			return "설정 %s 의 종류가 다릅니다(기본 %s, 값 %s)" % [prefix + k, type_string(typeof(b)), type_string(typeof(a))]
		elif typeof(b) == TYPE_ARRAY and (a as Array).size() != (b as Array).size():
			return "설정 %s 의 길이가 다릅니다" % (prefix + k)
	return ""


static func _same_kind(a: Variant, b: Variant) -> bool:
	var na := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var nb := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	return na == nb if (na or nb) else typeof(a) == typeof(b)


static func deep_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not deep_equal(a[k], b[k]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not deep_equal(a[i], b[i]):
				return false
		return true
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b
