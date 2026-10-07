class_name SimRecorder
extends RefCounted
## 실험 기록: 시계열(record.every 틱마다), 연대기, 계통 → CSV·JSON. 헤드리스 실행기와 화면이 같은 형식을 쓴다.
## CSV: UTF-8(BOM 없음), 쉼표, 영문 snake_case 열 이름, 소수점 ".".

const TIMESERIES_COLUMNS: Array[String] = [
	"tick", "day", "season", "light", "population", "births", "deaths", "mean_gen", "mean_energy",
	"mean_size", "mean_sense", "mean_age", "food_total", "dropped_total", "stored_total", "carry_total",
	"civ_stage", "storehouses", "farms", "forage_attempts", "store_drops", "farm_sprouts",
]
const CHRONICLE_COLUMNS: Array[String] = ["tick", "mean_gen", "kind", "actor_id", "text"]
const LINEAGE_COLUMNS: Array[String] = ["id", "parent_a", "parent_b", "gen", "birth_tick", "death_tick", "death_cause", "children", "size", "sense", "hue"]
## CSV 실수 소수 자릿수
const DECIMALS := 6

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
func write_all(dir: String, world: SimWorld, extra: Dictionary, with_lineage: bool = true) -> PackedStringArray:
	var failed := PackedStringArray()
	prepare_dir(dir)
	var files := {
		"summary.json": JSON.stringify(summary(world, extra), "\t"),
		"timeseries.csv": timeseries_csv(),
		"chronicle.csv": chronicle_csv(world),
	}
	if with_lineage:
		files["lineage.csv"] = lineage_csv(world)
	for name in files:
		if not write_text(dir.path_join(name), files[name]):
			failed.append(name)
	return failed


## 결과 폴더를 만들고, 프로젝트 안이면 Godot 가 CSV 를 가져오지 않도록 .gdignore 를 둔다.
static func prepare_dir(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var ig := dir.path_join(".gdignore")
	if not FileAccess.file_exists(ig):
		write_text(ig, "")


static func write_text(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("파일을 쓸 수 없습니다: %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(text)
	f.close()
	return true
