class_name SimConfig
extends RefCounted
## config/*.json 을 읽어 실험 설정을 만든다. 수치의 단일 기준은 JSON 이다.
## 실험 설정 = 기본값(sim-defaults.json) + 예설정(presets.json) + 덮어쓰기("a.b=값").

const DEFAULTS_PATH := "res://config/sim-defaults.json"
const PRESETS_PATH := "res://config/presets.json"

static var _defaults_cache: Dictionary = {}
static var _presets_cache: Dictionary = {}


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## 기본값의 깊은 사본.
static func defaults() -> Dictionary:
	if _defaults_cache.is_empty():
		var d = load_json(DEFAULTS_PATH)
		if typeof(d) != TYPE_DICTIONARY:
			push_error("설정 파일을 읽을 수 없습니다: %s" % DEFAULTS_PATH)
			return {}
		_defaults_cache = d
	return _defaults_cache.duplicate(true)


static func presets() -> Dictionary:
	if _presets_cache.is_empty():
		var d = load_json(PRESETS_PATH)
		if typeof(d) == TYPE_DICTIONARY:
			_presets_cache = d
	var out := _presets_cache.duplicate(true)
	out.erase("_comment")
	return out


static func preset_names() -> PackedStringArray:
	var names := PackedStringArray()
	for k in presets().keys():
		names.append(k)
	return names


## 실험 설정을 만든다. 결과: {config, error}. error 가 "" 이면 성공.
static func build(preset: String = "default", overrides: Dictionary = {}) -> Dictionary:
	var cfg := defaults()
	if cfg.is_empty():
		return {config = {}, error = "기본 설정을 읽지 못했습니다"}
	var ps := presets()
	if preset != "":
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


## "a.b" 키에 값을 넣는다. 기본값에 없는 키나 종류가 다른 값은 거부한다(오타가 조용히 무시되지 않게).
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
static func parse_value(text: String) -> Variant:
	var j = JSON.parse_string(text)
	if j == null and text != "null":
		return text
	return j


static func get_value(cfg: Dictionary, dotted: String) -> Variant:
	var node: Variant = cfg
	for p in dotted.split("."):
		if typeof(node) != TYPE_DICTIONARY or not node.has(p):
			return null
		node = node[p]
	return node


## 범위와 관계 검사. 문제가 없으면 "".
static func validate(cfg: Dictionary) -> String:
	var rules := [
		["map.width", 8, 1024], ["map.height", 8, 1024],
		["time.day_ticks", 2, 100000], ["plants.max_food", 0.0, 1e9], ["plants.update_every", 1, 1000],
		["resources.scale", 0.0, 100.0], ["plants.initial_fill", 0.0, 1.0],
		["eat.efficiency", 0.0, 1.0], ["repro.transfer_efficiency", 0.0, 1.0], ["repro.cost_frac", 0.0, 1.0],
		["population.initial", 0, 100000], ["population.cap", 1, 100000],
		["brain.hidden", 1, 64], ["brain.memory_units", 0, 16], ["brain.think_every", 1, 100],
		["mutation.rate", 0.0, 1.0], ["mutation.sigma", 0.0, 100.0],
		["traits.size_min", 0.01, 100.0], ["traits.sense_min", 0.0, 64.0],
		["discovery.region_size", 1, 1024], ["hash.every", 1, 1000000], ["record.every", 1, 1000000],
	]
	for r in rules:
		var v = get_value(cfg, r[0])
		if v == null:
			return "설정 키가 없습니다: %s" % r[0]
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return "설정 %s 는 수여야 합니다" % r[0]
		if v < r[1] or v > r[2]:
			return "설정 %s = %s 가 범위 [%s, %s] 밖입니다" % [r[0], v, r[1], r[2]]
	if cfg.seasons.growth.size() != 4:
		return "seasons.growth 는 계절 4개여야 합니다"
	if cfg.traits.size_min > cfg.traits.size_init or cfg.traits.size_init > cfg.traits.size_max:
		return "traits.size_init 이 size_min~size_max 밖입니다"
	if cfg.traits.sense_min > cfg.traits.sense_init or cfg.traits.sense_init > cfg.traits.sense_max:
		return "traits.sense_init 이 sense_min~sense_max 밖입니다"
	if cfg.time.daylight_fraction < 0.0 or cfg.time.daylight_fraction > 1.0:
		return "time.daylight_fraction 은 0~1 이어야 합니다"
	# 스냅숏은 설정을 JSON 글자로 저장한다. 글자로 바꿨다 다시 읽어 같은 값이 되어야 한다(유효숫자 15자리 이내).
	var again = JSON.parse_string(JSON.stringify(cfg))
	if not deep_equal(again, cfg):
		return "설정 값 중 JSON 으로 정확히 왕복하지 않는 수가 있습니다(유효숫자 15자리 이내로 적어 주세요)"
	return ""


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

