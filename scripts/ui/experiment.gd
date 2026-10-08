class_name Experiment
extends RefCounted
## 실험 하나 = 세계(SimWorld) + 기록기(SimRecorder) + 만든 조건. 계약: docs/VIEW-API.md "Experiment".
## 기록은 헤드리스 실행기(tests/run_experiment.gd)와 **같은 줄**이 되게 한다:
## 만들 때(또는 스냅숏을 열 때) 한 줄, 그 뒤 tick % record.every == 0 이 되는 step 마다 한 줄.
## 화면에서 내보낸 timeseries.csv 는 같은 씨앗·설정·틱 수의 실행기 결과와 글자까지 같다(검사).
## 노드가 아니다(화면 없이 검사·캡처에서도 씀). 세계를 진행하는 것은 step()/step_n() 뿐이다.

## 비교 모드의 이름표(첫째 = A, 둘째 = B)
const TAGS: Array[String] = ["A", "B"]

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


## "예설정 이름 · 씨앗 N[ · 바꾼 값 K개]"
static func default_label(preset_name: String, sets: Dictionary, seed_in: int) -> String:
	var name := preset_name
	var ps := SimConfig.presets()
	if ps.has(preset_name):
		name = str(ps[preset_name].get("label", preset_name))
	var s := "%s · 씨앗 %d" % [name, seed_in]
	if not sets.is_empty():
		s += " · 바꾼 값 %d개" % sets.size()
	return s


func _adopt(w: SimWorld) -> void:
	world = w
	_every = maxi(1, int(world.cfg.record.every))
	recorder = SimRecorder.new()
	recorder.record(world)


## 한 틱 진행 + (record.every 마다) 기록. 이번 step 에서 한 줄을 기록했으면 true.
func step() -> bool:
	world.step()
	if world.tick % _every == 0:
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
## 진행 중에도 쓸 수 있다(끝 줄을 따로 기록하지 않음 — sample() 이 기간 카운터를 0 으로 되돌려 이후 기록을 바꾸므로).
## 실패한 파일 이름 목록(성공이면 빈 배열).
func export_dir(dir: String, with_lineage: bool = true) -> PackedStringArray:
	var abs_dir := ProjectSettings.globalize_path(dir)
	var extra := {
		end_reason = "exported", source = "lab", preset = preset, overrides = overrides, label = label, tag = tag,
		snapshot_from = snapshot_path, rows = recorder.rows.size(),
	}
	var failed := recorder.write_all(abs_dir, world, extra, with_lineage)
	var serr := SimSnapshot.save_file(world, abs_dir.path_join("final.snapshot.json"))
	if serr != "":
		failed.append("final.snapshot.json(" + serr + ")")
	return failed


## 스냅숏 저장(성공 "").
func save_snapshot(path: String) -> String:
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	return SimSnapshot.save_file(world, abs_path)
