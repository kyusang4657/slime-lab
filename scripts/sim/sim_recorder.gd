class_name SimRecorder
extends RefCounted
## 실험 기록: 시계열(record.every 틱마다), 연대기, 계통 → CSV·JSON. 헤드리스 실행기와 화면이 같은 형식을 쓴다.
## CSV: BOM 붙은 UTF-8(한국어 Windows 엑셀이 두 번 클릭으로 열어도 한글이 깨지지 않게), 쉼표, 영문 snake_case 열 이름,
## 소수점 ".". BOM 은 파일에 쓸 때만 붙인다(timeseries_csv() 같은 글에는 없음 — Godot 의 파일 읽기는 BOM 을 건너뜀).

## 시계열 열: v0.1 22열(순서·값·뜻 그대로) 뒤에 v0.2 열을 단계마다 끝에 붙인다(DESIGN-v0.2 9.3). 0단계 = ACT_COLUMNS·EFF_COLUMNS,
## 1단계 = STAGE1_COLUMNS(이 목록은 v0.1 22열 + ACT_COLUMNS + EFF_COLUMNS + STAGE1_COLUMNS 를 그대로 이은 것 — 검사 test_act_counts).
const TIMESERIES_COLUMNS: Array[String] = [
	"tick", "day", "season", "light", "population", "births", "deaths", "mean_gen", "mean_energy",
	"mean_size", "mean_sense", "mean_age", "food_total", "dropped_total", "stored_total", "carry_total",
	"civ_stage", "storehouses", "farms", "forage_attempts", "store_drops", "farm_sprouts",
	"act_forward", "act_left", "act_right", "act_eat", "act_rest", "act_gather", "act_drop", "act_plant",
	"eff_forward", "eff_left", "eff_right", "eff_eat", "eff_rest", "eff_gather", "eff_drop", "eff_plant",
	"stage_juvenile", "stage_young", "stage_adult", "stage_old", "mean_size_eff",
	"learn_events", "eta_mean", "dw_mean", "rbar_mean", "pmax_mean",
]
## 구간 행동별 고른 횟수·효과가 난 횟수 열(행동 번호 SimBrain.ACT_* 순서 — SimWorld.period_act·period_eff, DESIGN-v0.2 11.1).
const ACT_COLUMNS: Array[String] = ["act_forward", "act_left", "act_right", "act_eat", "act_rest", "act_gather", "act_drop", "act_plant"]
const EFF_COLUMNS: Array[String] = ["eff_forward", "eff_left", "eff_right", "eff_eat", "eff_rest", "eff_gather", "eff_drop", "eff_plant"]
## 1단계 열(DESIGN-v0.2 9.3): 생애 단계별 개체 수(SimBrain.LIFE_* 순서 — LIFE_STAGE_COLUMNS)·유효 크기 평균(늘 계산), 구간 학습 갱신 수·
## 평균 η·평균 배운 양·평균 기준선·구간 판단마다 가장 큰 행동 확률의 평균(학습을 켰을 때만 — 끄면 0).
const STAGE1_COLUMNS: Array[String] = ["stage_juvenile", "stage_young", "stage_adult", "stage_old", "mean_size_eff",
	"learn_events", "eta_mean", "dw_mean", "rbar_mean", "pmax_mean"]
const LIFE_STAGE_COLUMNS: Array[String] = ["stage_juvenile", "stage_young", "stage_adult", "stage_old"]
const CHRONICLE_COLUMNS: Array[String] = ["tick", "mean_gen", "kind", "actor_id", "text"]
## 계통 열: v0.1 11열 뒤에 v0.2 열(DESIGN-v0.2 9.4). eaten = 평생 먹은 에너지(죽은 개체는 죽을 때, 살아 있는 개체는 쓸 때의 값).
## 개체별 셈이 없던 옛 스냅숏에서 이어 돌린 세계는 그때까지 태어난 개체(id < SimWorld.eaten_from_id)의 eaten 을 비워 둔다(평생 값을 모름).
## 1단계: eta(태어날 때 η 평균)·dw(배운 양)·dw_juv(어린 동안 배운 양)·assim(동화 지수 — 11.2). 학습을 끄면 0.
const LINEAGE_COLUMNS: Array[String] = ["id", "parent_a", "parent_b", "gen", "birth_tick", "death_tick", "death_cause", "children", "size", "sense", "hue", "eaten",
	"eta", "dw", "dw_juv", "assim"]
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
	# 평생 먹은 양: 죽은 개체는 lin_eaten, 살아 있는 개체는 지금의 s_eaten. 셈을 시작하기 전에 태어난 개체는 빈 칸
	var eaten := world.lin_eaten.duplicate()
	for i in world.s_id.size():
		eaten[world.s_id[i]] = world.s_eaten[i]
	# 학습(1단계): 죽은 개체는 계통 값, 살아 있는 개체는 지금 값(배운 양·어린 동안 배운 양·동화 지수). 학습을 끄면 0
	var on := world.lin_eta.size() == world.lin_pa.size() and world.lin_pa.size() > 0
	var dw := PackedFloat64Array()
	var dw_juv := PackedFloat64Array()
	var assim := PackedFloat64Array()
	if on:
		for id in world.lin_pa.size():
			dw.append(float(world.lin_dw[id]))
			dw_juv.append(float(world.lin_dw_juv[id]))
			assim.append(float(world.lin_assim[id]))
		for i in world.s_id.size():
			var lid := world.s_id[i]
			dw[lid] = world.learned_amount_of(i)
			dw_juv[lid] = world.s_dw_juv[i]
			assim[lid] = world.assim_of(i)
	for id in world.lin_pa.size():
		var learn_cells: Array = [fmt(float(world.lin_eta[id])), fmt(dw[id]), fmt(dw_juv[id]), fmt(assim[id])] if on else [fmt(0.0), fmt(0.0), fmt(0.0), fmt(0.0)]
		lines.append(",".join([str(id), str(world.lin_pa[id]), str(world.lin_pb[id]), str(world.lin_gen[id]),
				str(world.lin_birth[id]), str(world.lin_death[id]), str(world.lin_cause[id]), str(world.lin_children[id]),
				fmt(float(world.lin_size[id])), fmt(float(world.lin_sense[id])), fmt(float(world.lin_hue[id])),
				fmt(eaten[id]) if id >= world.eaten_from_id else ""] + learn_cells))
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
		# 열 목록(DESIGN-v0.2 9.5): 단계마다 열이 늘므로 분석 도구가 손 사본 대신 이것으로 읽는다
		timeseries_columns = TIMESERIES_COLUMNS, lineage_columns = LINEAGE_COLUMNS,
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
