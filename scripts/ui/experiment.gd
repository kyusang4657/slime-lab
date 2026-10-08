class_name Experiment
extends RefCounted
## 실험 하나 = 세계(SimWorld) + 기록기(SimRecorder) + 만든 조건. 계약: docs/VIEW-API.md "Experiment".
## 기록은 헤드리스 실행기(tests/run_experiment.gd)와 **같은 줄**이 되게 한다:
## 만들 때(또는 스냅숏을 열 때) 한 줄, 그 뒤 tick % record.every == 0 이 되는 step 마다 한 줄, 그리고 멸종한 틱에 한 줄
## (실행기는 멸종에서 멈추며 끝 줄을 쓴다 — 그래서 그래프에 개체 수 0 줄·"멸종" 표시가 생김).
## 내보낼 때 마지막 기록 줄이 지금 틱이 아니면 지금 틱의 끝 줄을 파일에만 더한다(실행기의 끝 줄과 같음, tail_row()).
## 그래서 화면에서 내보낸 timeseries.csv 는 같은 씨앗·설정으로 그 틱까지(또는 멸종까지) 돌린 실행기 결과와 글자까지 같다(검사).
## 노드가 아니다(화면 없이 검사·캡처에서도 씀). 세계를 진행하는 것은 step()/step_n() 뿐이다.

## 비교 모드의 이름표(첫째 = A, 둘째 = B)
const TAGS: Array[String] = ["A", "B"]
## 이름에 쓰는 세 주요 값의 짧은 이름과 순서(파라미터 패널 "지금 실험" 줄과 같은 말 — ParamPanel.MAIN_SHORT 와 같음, 검사)
const SHORT_NAMES := {"mutation.rate": "돌연변이", "resources.scale": "자원", "population.initial": "개체"}
const SHORT_ORDER: Array[String] = ["mutation.rate", "resources.scale", "population.initial"]

var world: SimWorld
var recorder := SimRecorder.new()
## 만든 조건(스냅숏에서 열었으면 preset = "", overrides = {}, snapshot_path = 경로)
var preset := ""
var overrides: Dictionary = {}
var seed_value := 0
var snapshot_path := ""
## 화면 이름("기본 · 씨앗 1" 등)과 비교 이름표("A"/"B", 혼자면 "")
var label := ""
var tag := ""
var _every := 1


## 새 실험. 결과: {experiment, error}
static func create(preset_name: String, sets: Dictionary, seed_in: int) -> Dictionary:
	var b := SimConfig.build(preset_name, sets)
	if b.error != "":
		return {experiment = null, error = b.error}
	var w := SimWorld.new()
	var e := w.setup(b.config, seed_in)
	if e != "":
		return {experiment = null, error = e}
	var x := Experiment.new()
	x.preset = preset_name
	x.overrides = sets.duplicate(true)
	x.seed_value = seed_in
	x.label = default_label(preset_name, sets, seed_in)
	x._adopt(w)
	return {experiment = x, error = ""}


## 스냅숏에서 연 실험. 결과: {experiment, error, status}(status 는 SimSnapshot.load_file 과 같음)
static func from_snapshot(path: String) -> Dictionary:
	var r := SimSnapshot.load_file(path)
	var w: SimWorld = r.world
	if w == null:
		var err: String = r.error
		return {experiment = null, error = err if err != "" else "스냅숏을 열 수 없습니다", status = r.status}
	var x := Experiment.new()
	x.snapshot_path = path
	x.seed_value = w.seed_value
	x.label = "스냅숏 %s · 씨앗 %d" % [path.get_file(), w.seed_value]
	x._adopt(w)
	return {experiment = x, error = "", status = r.status}


## "예설정 이름 · 씨앗 N[ · 바꾼 값]". 바꾼 값은 무엇을 얼마로 바꿨는지 짧게(overrides_brief) — 값만 다른 두 실험
## (돌연변이율 0.08 과 0.02 를 견주는 비교 등)도 이름으로 가려진다. first = 먼저 적을 키(비교 모드에서 A·B 가 다른 키).
static func default_label(preset_name: String, sets: Dictionary, seed_in: int, first: Array = []) -> String:
	var name := preset_name
	var ps := SimConfig.presets()
	if ps.has(preset_name):
		name = str(ps[preset_name].get("label", preset_name))
	var s := "%s · 씨앗 %d" % [name, seed_in]
	var brief := overrides_brief(sets, UiConfig.integer("lab.label_max_overrides"), first)
	if brief != "":
		s += " · " + brief
	return s


## 바꾼 값 설명: 세 주요 값은 짧은 이름("돌연변이 0.08"), 나머지는 "키=값"(plants.regrow=0.5). 최대 max_n 개, 넘치면
## "외 K개"(max_n 0 이면 "바꾼 값 K개"). 순서: first 의 키 → 세 주요 값 → 나머지 키 이름 순. 바꾼 값이 없으면 "".
static func overrides_brief(sets: Dictionary, max_n: int, first: Array = []) -> String:
	var keys := ordered_keys(sets, first)
	var parts: Array[String] = []
	for i in mini(keys.size(), maxi(0, max_n)):
		parts.append(describe_value(keys[i], sets[keys[i]]))
	var rest := keys.size() - parts.size()
	var s := " · ".join(parts)
	if rest > 0:
		s += (" 외 %d개" % rest) if s != "" else ("바꾼 값 %d개" % rest)
	return s


## 바꾼 값 키의 설명 순서: first 에 있는 키(그 순서) → 세 주요 값 → 나머지(이름 순).
static func ordered_keys(sets: Dictionary, first: Array = []) -> Array[String]:
	var out: Array[String] = []
	for k in first:
		if sets.has(str(k)) and not out.has(str(k)):
			out.append(str(k))
	for k in SHORT_ORDER:
		if sets.has(k) and not out.has(k):
			out.append(k)
	var rest: Array[String] = []
	for k in sets:
		if not out.has(str(k)):
			rest.append(str(k))
	rest.sort()
	out.append_array(rest)
	return out


## 바꾼 값 하나: "돌연변이 0.08" / "plants.regrow=0.5"(수는 짧게 — 0.08, 150, 1.4).
static func describe_value(key: String, v: Variant) -> String:
	var txt := ""
	match typeof(v):
		TYPE_FLOAT:
			txt = String.num(float(v))
		TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			txt = str(v)
		_:
			txt = JSON.stringify(v)
	return "%s %s" % [str(SHORT_NAMES[key]), txt] if SHORT_NAMES.has(key) else "%s=%s" % [key, txt]


## 두 실험의 바꾼 값 가운데 값이 다른(한쪽에만 있는 것 포함) 키(이름 순). 비교 모드 이름이 A·B 를 가르는 키를 먼저 적게.
static func differing_keys(a: Dictionary, b: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for d: Dictionary in [a, b]:
		for k in d:
			var key := str(k)
			if out.has(key):
				continue
			if not (a.has(key) and b.has(key)) or not SimConfig.deep_equal(a[key], b[key]):
				out.append(key)
	out.sort()
	return out


func _adopt(w: SimWorld) -> void:
	world = w
	_every = maxi(1, int(world.cfg.record.every))
	recorder = SimRecorder.new()
	recorder.record(world)


## 한 틱 진행 + 기록(record.every 마다, 그리고 멸종한 틱 — 실행기가 멸종에서 멈추며 쓰는 끝 줄과 같은 줄).
## 이번 step 에서 한 줄을 기록했으면 true.
func step() -> bool:
	world.step()
	if world.tick % _every == 0 or world.tick == world.extinct_tick:
		recorder.record(world)
		return true
	return false


## n틱 진행(검사·캡처용). 기록한 줄 수를 돌려준다.
func step_n(n: int) -> int:
	var k := 0
	for i in n:
		if step():
			k += 1
	return k


## 지금까지 기록한 시계열 줄(SimRecorder.TIMESERIES_COLUMNS 키 사전, 읽기 전용으로 쓸 것).
func rows() -> Array:
	return recorder.rows


## 이름표가 붙은 화면 이름("A · 기본 · 씨앗 1", 혼자면 label 그대로)
func display_name() -> String:
	return label if tag == "" else "%s · %s" % [tag, label]


## 결과 폴더 쓰기: summary.json·timeseries.csv·chronicle.csv·(lineage.csv)·final.snapshot.json.
## 진행 중에도 쓸 수 있다. 마지막 기록 줄이 지금 틱이 아니면 tail_row() 를 timeseries.csv 에만 더한다(기록기·세계는 그대로).
## 실패한 파일 이름 목록(성공이면 빈 배열).
func export_dir(dir: String, with_lineage: bool = true) -> PackedStringArray:
	var abs_dir := ProjectSettings.globalize_path(dir)
	var rec := recorder
	var tail := tail_row()
	if not tail.is_empty():
		rec = SimRecorder.new()
		rec.rows = recorder.rows.duplicate()
		rec.rows.append(tail)
	var extra := {
		end_reason = "exported", source = "lab", preset = preset, overrides = overrides, label = label, tag = tag,
		snapshot_from = snapshot_path, rows = rec.rows.size(),
	}
	var failed := rec.write_all(abs_dir, world, extra, with_lineage)
	var serr := SimSnapshot.save_file(world, abs_dir.path_join("final.snapshot.json"))
	if serr != "":
		failed.append("final.snapshot.json(" + serr + ")")
	return failed


## 내보낼 때 더하는 끝 줄: 마지막 기록 줄이 지금 틱이면(record.every 의 배수·멸종한 틱·막 만든 실험) {}, 아니면 지금 틱의
## 한 줄 = 헤드리스 실행기가 그 틱에서 끝나며 쓰는 줄(마지막 기록 뒤의 출생·사망 수 포함). sample() 은 기간 카운터를 0 으로
## 되돌리므로 세계 **사본**(스냅숏 글 왕복 — 기간 카운터까지 담김)에서 부른다: 세계·기록기·다음 기록은 그대로(검사).
func tail_row() -> Dictionary:
	if world == null or (not recorder.rows.is_empty() and int(recorder.rows.back().tick) == world.tick):
		return {}
	var r := SimSnapshot.from_text(SimSnapshot.to_text(world))
	var copy: SimWorld = r.world
	if copy == null:
		push_warning("끝 줄을 만들 세계 사본 실패: %s" % str(r.error))
		return {}
	return copy.sample()


## 스냅숏 저장(성공 "").
func save_snapshot(path: String) -> String:
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	return SimSnapshot.save_file(world, abs_path)
