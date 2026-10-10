class_name SimRecorder
extends RefCounted
## 실험 기록: 시계열(record.every 틱마다), 연대기, 계통 → CSV·JSON. 헤드리스 실행기와 화면이 같은 형식을 쓴다.
## CSV: BOM 붙은 UTF-8(한국어 Windows 엑셀이 두 번 클릭으로 열어도 한글이 깨지지 않게), 쉼표, 영문 snake_case 열 이름,
## 소수점 ".". BOM 은 파일에 쓸 때만 붙인다(timeseries_csv() 같은 글에는 없음 — Godot 의 파일 읽기는 BOM 을 건너뜀).

const TIMESERIES_COLUMNS: Array[String] = [
	"tick", "day", "season", "light", "population", "births", "deaths", "mean_gen", "mean_energy",
	"mean_size", "mean_sense", "mean_age", "food_total", "dropped_total", "stored_total", "carry_total",
	"civ_stage", "storehouses", "farms", "forage_attempts", "store_drops", "farm_sprouts",
]
const CHRONICLE_COLUMNS: Array[String] = ["tick", "mean_gen", "kind", "actor_id", "text"]
const LINEAGE_COLUMNS: Array[String] = ["id", "parent_a", "parent_b", "gen", "birth_tick", "death_tick", "death_cause", "children", "size", "sense", "hue"]
## CSV 실수 소수 자릿수
const DECIMALS := 6
## UTF-8 BOM(EF BB BF).
const UTF8_BOM: Array[int] = [0xEF, 0xBB, 0xBF]
const SUMMARY_FILE := "summary.json"

var rows: Array = []


func record(world: SimWorld) -> void:
	rows.append(world.sample())


static func fmt(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT:
		return String.num(v, DECIMALS)
	return str(v)


static func csv_escape(s: String) -> String:
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s


func timeseries_csv() -> String:
	var lines := PackedStringArray([",".join(TIMESERIES_COLUMNS)])
	for r in rows:
		var cells := PackedStringArray()
		for c in TIMESERIES_COLUMNS:
			cells.append(fmt(r[c]))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


static func chronicle_csv(world: SimWorld) -> String:
	var lines := PackedStringArray([",".join(CHRONICLE_COLUMNS)])
	for e in world.chronicle:
		lines.append(",".join([str(int(e.tick)), fmt(float(e.mean_gen)), e.kind, str(int(e.actor)), csv_escape(e.text)]))
	return "\n".join(lines) + "\n"


static func lineage_csv(world: SimWorld) -> String:
	var lines := PackedStringArray([",".join(LINEAGE_COLUMNS)])
	for id in world.lin_pa.size():
		lines.append(",".join([str(id), str(world.lin_pa[id]), str(world.lin_pb[id]), str(world.lin_gen[id]),
				str(world.lin_birth[id]), str(world.lin_death[id]), str(world.lin_cause[id]), str(world.lin_children[id]),
				fmt(float(world.lin_size[id])), fmt(float(world.lin_sense[id])), fmt(float(world.lin_hue[id]))]))
	return "\n".join(lines) + "\n"


static func summary(world: SimWorld, extra: Dictionary) -> Dictionary:
	var disc := {}
	for st in range(SimWorld.STAGE_FORAGE, SimWorld.STAGE_FARM + 1):
		disc[SimWorld.STAGE_NAMES[st]] = world.discovery_tick[st]
	var d := {
		app_version = ProjectSettings.get_setting("application/config/version", ""),
		seed = world.seed_value, tick = world.tick, population = world.population(),
		peak_population = world.peak_population, mean_generation = world.mean_generation(),
		total_births = world.total_births, total_deaths = world.total_deaths,
		civ_stage = world.stage, civ_stage_name = SimWorld.STAGE_NAMES[world.stage],
		discovery_ticks = disc, storehouses = world.store_tiles.size(), farms = world.farms.size(),
		extinct_tick = world.extinct_tick, history_hash = world.history_hash, config = world.cfg,
	}
	d.merge(extra)
	return d


## 결과 폴더에 파일을 쓴다. 실패한 파일 이름 목록을 돌려준다(성공이면 빈 배열).
## summary.json 은 CSV 를 다 쓴 뒤 마지막에(임시 이름 → 바꾸기) 쓴다: summary.json 이 있으면 CSV 도 다 쓰인 것이다
## (분석 도구가 끝난 실행으로 봄). 그래서 쓰기 전에 앞선 summary.json 을 지우고, CSV 하나라도 못 쓰면 쓰지 않는다.
func write_all(dir: String, world: SimWorld, extra: Dictionary, with_lineage: bool = true) -> PackedStringArray:
	var failed := PackedStringArray()
	prepare_dir(dir)
	var summary_path := dir.path_join(SUMMARY_FILE)
	if FileAccess.file_exists(summary_path):
		DirAccess.remove_absolute(summary_path)
	var files := {
		"timeseries.csv": timeseries_csv(),
		"chronicle.csv": chronicle_csv(world),
	}
	if with_lineage:
		files["lineage.csv"] = lineage_csv(world)
	for name in files:
		if not write_text(dir.path_join(name), files[name], true):
			failed.append(name)
	if not failed.is_empty():
		failed.append(SUMMARY_FILE + "(앞 파일을 쓰지 못해 쓰지 않음)")
		return failed
	var tmp := summary_path + ".tmp"
	if not write_text(tmp, JSON.stringify(summary(world, extra), "\t")):
		DirAccess.remove_absolute(tmp)
		failed.append(SUMMARY_FILE)
		return failed
	var err := DirAccess.rename_absolute(tmp, summary_path)
	if err != OK:
		push_error("파일을 바꿀 수 없습니다: %s (%s)" % [summary_path, error_string(err)])
		DirAccess.remove_absolute(tmp)
		failed.append(SUMMARY_FILE)
	return failed


## 결과 폴더를 만들고, 프로젝트 안이면 Godot 가 CSV 를 가져오지 않도록 .gdignore 를 둔다.
static func prepare_dir(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var ig := dir.path_join(".gdignore")
	if not FileAccess.file_exists(ig):
		write_text(ig, "")


## path 에 글을 쓴다(bom 이면 UTF-8 BOM 을 앞에). 다 쓰였는지 닫은 뒤 파일 길이로 확인한다 —
## 디스크가 차면 쓰기가 성공처럼 돌아오고 닫을 때 잘리므로(0바이트 CSV 를 성공으로 세지 않게).
static func write_text(path: String, text: String, bom: bool = false) -> bool:
	var data := text.to_utf8_buffer()
	if bom:
		data = PackedByteArray(UTF8_BOM) + data
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("파일을 쓸 수 없습니다: %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	var ok := f.store_buffer(data)
	var werr := f.get_error()
	f.close()
	var r := FileAccess.open(path, FileAccess.READ)
	var size := r.get_length() if r != null else -1
	if r != null:
		r.close()
	if not ok or (werr != OK and werr != ERR_FILE_EOF) or size != data.size():
		push_error("파일을 다 쓰지 못했습니다: %s (%d / %d 바이트)" % [path, maxi(size, 0), data.size()])
		return false
	return true
