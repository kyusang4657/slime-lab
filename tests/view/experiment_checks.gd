extends RefCounted
## Experiment(세계 + 기록기) 검사: 화면 쪽 기록·내보내기가 헤드리스 실행기와 같은 결과를 낸다.
## record.every 의 배수 틱, 배수가 아닌 틱(내보낼 때 끝 줄), 멸종해 저절로 멈춘 틱(멸종한 틱의 줄) 모두.
## 실험 이름(바꾼 값을 짧게 — 값만 다른 두 실험도 이름이 갈림).

## 이 모듈이 적어도 하는 검사 수(중간에 스크립트 오류로 끊기면 실행기가 실패로 셈)
const MIN_CHECKS := 49
const TICKS := 400
## record.every(20)의 배수가 아닌 내보내기 틱과, 그 뒤 기록이 그대로인지 보려고 더 진행할 틱(배수)
const ODD_TICKS := 407
const ODD_AFTER := 420
const DT := 1.0 / 60.0
## 멸종 장면: 자원 없는 예설정·씨앗 1 은 약 220틱에 멸종(record.every 의 배수가 아닌 틱)
const EXTINCT_PRESET := "no_resources"
const EXTINCT_SEED := 1
const EXTINCT_FRAMES := 4000
## 임시 폴더(프로세스마다 따로 — 다른 검사 실행과 섞이지 않게, 처음과 끝에 지움: 앞 실행이 남긴 파일이 내보내기
## 회귀를 가리지 않게)
var tmp := "user://test_experiment-%d" % OS.get_process_id()


func run(t) -> void:
	var root := ProjectSettings.globalize_path(tmp)
	_clean_dir(root)
	t.check(not DirAccess.dir_exists_absolute(root), "임시 폴더를 비우고 시작(%s)" % root)
	var r := Experiment.create("default", {}, 42)
	var x: Experiment = r.experiment
	t.check(r.error == "" and x != null, "실험 만들기: " + str(r.error))
	if x == null:
		return
	t.check(x.rows().size() == 1 and int(x.rows()[0].tick) == 0, "만들 때 첫 줄을 기록")
	x.step_n(TICKS)
	var every := int(x.world.cfg.record.every)
	t.check(x.rows().size() == TICKS / every + 1, "record.every(%d)마다 한 줄: %d줄" % [every, x.rows().size()])
	t.check(Experiment.create("없는예설정", {}, 1).error != "", "없는 예설정 거부")
	t.check(x.label.contains("씨앗 42") and x.display_name() == x.label, "화면 이름")
	t.check(x.tail_row().is_empty(), "마지막 기록 줄이 지금 틱이면 내보낼 끝 줄 없음")
	# 같은 씨앗·틱 수의 헤드리스 실행기 결과와 글자까지 같은 timeseries.csv
	var dir := root.path_join("lab")
	var rdir := root.path_join("runner")
	t.check(x.export_dir(dir).is_empty(), "내보내기 성공")
	for f in ["summary.json", "timeseries.csv", "chronicle.csv", "lineage.csv", "final.snapshot.json"]:
		t.check(FileAccess.file_exists(dir.path_join(f)), "내보낸 파일 %s" % f)
	var run_csv := _runner(t, rdir, "default", 42, TICKS)
	var lab_csv := FileAccess.get_file_as_string(dir.path_join("timeseries.csv"))
	t.check(lab_csv != "" and lab_csv == run_csv, "화면 쪽 timeseries.csv = 실행기 결과(%d / %d 글자)" % [lab_csv.length(), run_csv.length()])
	t.check(FileAccess.get_file_as_string(dir.path_join("chronicle.csv")) == FileAccess.get_file_as_string(rdir.path_join("chronicle.csv")), "chronicle.csv 도 같음")
	var sm = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("summary.json")))
	t.check(typeof(sm) == TYPE_DICTIONARY and sm.source == "lab" and sm.history_hash == x.world.history_hash, "요약에 출처·해시")
	# 내보낸 스냅숏에서 연 실험은 이어서 같은 역사
	var r2 := Experiment.from_snapshot(dir.path_join("final.snapshot.json"))
	var y: Experiment = r2.experiment
	t.check(y != null and y.world.tick == TICKS and y.snapshot_path != "", "내보낸 스냅숏 열기")
	if y != null:
		x.step_n(120)
		y.step_n(120)
		t.check(x.world.history_hash == y.world.history_hash, "스냅숏에서 이어 돌린 해시가 같음")
		var last_x: Dictionary = x.rows().back()
		var last_y: Dictionary = y.rows().back()
		t.check(SimConfig.deep_equal(last_x, last_y), "이어 돌린 마지막 기록 줄이 같음")
	t.check(Experiment.from_snapshot("user://없는파일.json").experiment == null, "없는 스냅숏 거부")
	_odd_tick(t, root)
	_labels(t)
	# LabMain 을 거쳐 진행해도 기록·신호가 같다
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(1)
	lab.set_process(false)
	t.check(lab.new_experiment("default", {}, 42) == "" and lab.experiments.size() == 1, "실험실: 실험 하나")
	var got := [0]
	var count_rows := func(_i: int, _row: Dictionary) -> void: got[0] += 1
	lab.recorded.connect(count_rows)
	lab.step_ticks(TICKS)
	t.check(got[0] == TICKS / every and lab.experiments[0].rows().size() == TICKS / every + 1, "실험실 recorded 신호 %d번" % got[0])
	t.check(lab.experiments[0].recorder.timeseries_csv() == run_csv, "실험실을 거친 기록 = 실행기 결과")
	lab.recorded.disconnect(count_rows)
	await _extinct(t, lab, root)
	lab.queue_free()
	await t.frames(1)
	_clean_dir(root)
	t.check(not DirAccess.dir_exists_absolute(root), "끝나면 임시 폴더를 지움(숨은 .gdignore 까지)")


## record.every 의 배수가 아닌 틱에 내보내도 = 실행기(--max-ticks=그 틱)의 끝 줄까지 같음. 내보내기는 기록기·세계를
## 바꾸지 않음(끝 줄은 세계 사본에서 — 그 뒤 기록도 실행기와 같음).
func _odd_tick(t, root: String) -> void:
	var z: Experiment = Experiment.create("default", {}, 42).experiment
	z.step_n(ODD_TICKS)
	var rows0 := z.rows().size()
	var hash0 := z.world.history_hash
	var tail := z.tail_row()
	t.check(int(tail.get("tick", -1)) == ODD_TICKS and z.rows().size() == rows0, "배수가 아닌 틱(%d): 끝 줄은 지금 틱, 기록기는 그대로(%d줄)" % [ODD_TICKS, rows0])
	var dir := root.path_join("odd_lab")
	var rdir := root.path_join("odd_runner")
	t.check(z.export_dir(dir).is_empty(), "배수가 아닌 틱에 내보내기")
	var run_csv := _runner(t, rdir, "default", 42, ODD_TICKS)
	var lab_csv := FileAccess.get_file_as_string(dir.path_join("timeseries.csv"))
	t.check(lab_csv != "" and lab_csv == run_csv and lab_csv.strip_edges().split("\n").size() == rows0 + 2,
			"배수가 아닌 틱의 timeseries.csv = 실행기(--max-ticks=%d, 끝 줄 포함 %d / %d 글자)" % [ODD_TICKS, lab_csv.length(), run_csv.length()])
	var sm = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("summary.json")))
	t.check(typeof(sm) == TYPE_DICTIONARY and int(sm.rows) == rows0 + 1, "요약의 rows = 파일의 줄 수(%s)" % str(sm.get("rows") if typeof(sm) == TYPE_DICTIONARY else "?"))
	t.check(z.rows().size() == rows0 and z.world.history_hash == hash0 and z.world.tick == ODD_TICKS, "내보내기 뒤 세계·기록기 그대로")
	# 내보내기가 기간 출생·사망 수를 0 으로 되돌렸다면 다음 기록 줄이 실행기와 달라짐
	z.step_n(ODD_AFTER - ODD_TICKS)
	var after_csv := _runner(t, root.path_join("odd_runner2"), "default", 42, ODD_AFTER)
	t.check(z.recorder.timeseries_csv() == after_csv, "내보낸 뒤 이어 기록한 줄(틱 %d)도 실행기와 같음" % ODD_AFTER)


## 멸종: 실험실을 프레임으로 돌려 멸종하는 순간 저절로 멈춤 → 마지막 기록 줄 = 멸종한 틱·개체 0(그래프 "멸종" 표시) →
## 바로(배수에 맞추지 않고) 내보낸 CSV = 실행기(멸종에서 멈추며 끝 줄) 결과.
func _extinct(t, lab: LabMain, root: String) -> void:
	t.check(lab.new_experiment(EXTINCT_PRESET, {}, EXTINCT_SEED) == "", "멸종 실험(%s · 씨앗 %d)" % [EXTINCT_PRESET, EXTINCT_SEED])
	lab.set_paused(false)
	lab.set_speed(16)
	var frames := 0
	while not lab.is_paused() and frames < EXTINCT_FRAMES:
		lab.advance_frame(DT)
		frames += 1
	var x := lab.experiment(0)
	var w := lab.world
	var et := w.extinct_tick
	var every := int(w.cfg.record.every)
	t.check(et > 0 and lab.is_paused() and w.tick == et and et % every != 0, "멸종하는 순간 멈춤(틱 %d, record.every %d 의 배수 아님)" % [et, every])
	var last: Dictionary = x.rows().back() if not x.rows().is_empty() else {}
	t.check(int(last.get("tick", -1)) == et and int(last.get("population", -1)) == 0, "마지막 기록 줄 = 멸종한 틱 %d·개체 0 (%s)" % [et, str(last.get("tick"))])
	var gs: Array = lab.graph_panel.series
	t.check(not gs.is_empty() and int(gs[0].extinct_row) >= 0, "그래프에 멸종 줄(개체 수 그래프의 \"멸종\" 표시)")
	var dir := root.path_join("extinct_lab")
	t.check(lab.export_csv(dir) == "", "멸종해 멈춘 채 바로 내보내기")
	var rdir := root.path_join("extinct_runner")
	var run_csv := _runner(t, rdir, EXTINCT_PRESET, EXTINCT_SEED, -1)
	var lab_csv := FileAccess.get_file_as_string(dir.path_join("timeseries.csv"))
	t.check(lab_csv != "" and lab_csv == run_csv, "멸종한 실험의 timeseries.csv = 실행기(멸종에서 멈춤) 결과(%d / %d 글자)" % [lab_csv.length(), run_csv.length()])
	t.check(FileAccess.get_file_as_string(dir.path_join("chronicle.csv")) == FileAccess.get_file_as_string(rdir.path_join("chronicle.csv")),
			"멸종한 실험의 chronicle.csv 도 같음")
	var sm = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("summary.json")))
	t.check(typeof(sm) == TYPE_DICTIONARY and int(sm.extinct_tick) == et and int(sm.population) == 0, "요약: 멸종 틱 %d·개체 0" % et)


## 실험 이름: 바꾼 값을 짧게(세 주요 값 = 짧은 이름, 나머지 = 키=값), 최대 lab.label_max_overrides 개 + "외 K개".
func _labels(t) -> void:
	t.check(Experiment.SHORT_NAMES == ParamPanel.MAIN_SHORT and Experiment.SHORT_ORDER == ParamPanel.MAIN_KEYS, "짧은 이름 = 파라미터 패널 \"지금 실험\" 줄의 말")
	var a := Experiment.default_label("default", {"mutation.rate": 0.08}, 1)
	var b := Experiment.default_label("default", {"mutation.rate": 0.02}, 1)
	t.check(a != b and a.ends_with("돌연변이 0.08") and b.ends_with("돌연변이 0.02"), "값만 다른 두 실험의 이름이 다름: \"%s\" / \"%s\"" % [a, b])
	var c := Experiment.default_label("default", {"plants.regrow": 0.5, "population.initial": 150}, 3)
	t.check(c.contains("씨앗 3 · 개체 150 · plants.regrow=0.5"), "주요 값(짧은 이름) 먼저, 나머지는 키=값: \"%s\"" % c)
	var many := {"mutation.rate": 0.1, "brain.hidden": 12, "plants.regrow": 0.5, "time.day_ticks": 50}
	var n := UiConfig.integer("lab.label_max_overrides")
	var d := Experiment.default_label("default", many, 1)
	t.check(n >= 1 and d.ends_with("외 %d개" % (many.size() - n)) and d.contains("돌연변이 0.1"), "바꾼 값이 %d개 넘으면 \"외 K개\": \"%s\"" % [n, d])
	var plain := Experiment.default_label("default", {}, 1)
	t.check(plain.ends_with(" · 씨앗 1") and plain.count(" · ") == 1, "바꾼 값이 없으면 \"예설정 · 씨앗 N\": \"%s\"" % plain)
	t.check(Experiment.overrides_brief(many, 0) == "바꾼 값 %d개" % many.size(), "한도 0 이면 \"바꾼 값 K개\"")
	# 비교 모드: A·B 가 다른 키를 먼저(같은 고급 키가 많아 한도를 넘어도 이름이 갈림)
	var sa := {"brain.hidden": 12, "plants.regrow": 0.5, "time.day_ticks": 50, "time.season_days": 3}
	var sb := sa.duplicate()
	sb["time.season_days"] = 5
	var diff := Experiment.differing_keys(sa, sb)
	var la := Experiment.default_label("default", sa, 1, diff)
	var lb := Experiment.default_label("default", sb, 1, diff)
	t.check(diff == ["time.season_days"] and la != lb and la.contains("time.season_days=3") and lb.contains("time.season_days=5"),
			"다른 키를 먼저: \"%s\" / \"%s\"" % [la, lb])


## 헤드리스 실행기를 돌려 그 timeseries.csv(실패면 ""). max_ticks < 0 = 설정의 상한(멸종 등에서 끝남).
func _runner(t, rdir: String, preset: String, seed_value: int, max_ticks: int) -> String:
	var runner = load("res://tests/run_experiment.gd")
	var args := PackedStringArray(["--seed=%d" % seed_value, "--preset=" + preset, "--generations=1000000", "--out=" + rdir, "--quiet"])
	if max_ticks > 0:
		args.append("--max-ticks=%d" % max_ticks)
	var a: Dictionary = runner.parse_args(args)
	a.silent = true
	t.check(runner.run(a) == 0, "실행기 실행(%s · 씨앗 %d · %s)" % [preset, seed_value, str(max_ticks) if max_ticks > 0 else "끝까지"])
	return FileAccess.get_file_as_string(rdir.path_join("timeseries.csv"))


## 폴더를 통째로 지운다(숨은 .gdignore·.bak 까지).
static func _clean_dir(abs_dir: String) -> void:
	var d := DirAccess.open(abs_dir)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		_clean_dir(abs_dir.path_join(sub))
	for f in d.get_files():
		DirAccess.remove_absolute(abs_dir.path_join(f))
	DirAccess.remove_absolute(abs_dir)
