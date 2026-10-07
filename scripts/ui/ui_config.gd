class_name UiConfig
extends RefCounted
## config/ui.json(화면 수치의 단일 기준)을 읽는다. 시뮬레이션 수치는 SimConfig(sim-defaults.json).

const PATH := "res://config/ui.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(d) != TYPE_DICTIONARY:
			push_error("화면 설정 파일을 읽을 수 없습니다: %s" % PATH)
			return {}
		_data = d
	return _data


## "절.키" 값. 없으면 fallback 을 돌려주고 오류를 남긴다(오타가 조용히 묻히지 않게).
static func value(dotted: String, fallback: Variant = null) -> Variant:
	var node: Variant = data()
	for p in dotted.split("."):
		if typeof(node) != TYPE_DICTIONARY or not node.has(p):
			push_error("화면 설정 키가 없습니다: %s" % dotted)
			return fallback
		node = node[p]
	return node


static func num(dotted: String) -> float:
	return float(value(dotted, 0.0))


static func integer(dotted: String) -> int:
	return int(value(dotted, 0))


static func color(dotted: String) -> Color:
	return Color.from_string(str(value(dotted, "#ff00ff")), Color.MAGENTA)


static func section(name: String) -> Dictionary:
	var s: Variant = data().get(name, {})
	return s if typeof(s) == TYPE_DICTIONARY else {}
