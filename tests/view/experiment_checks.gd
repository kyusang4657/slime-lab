extends RefCounted
## Experiment(세계 + 기록기) 검사: 화면 쪽 기록·내보내기가 헤드리스 실행기와 같은 결과를 낸다.

const MIN_CHECKS := 12
const TICKS := 400


func run(t) -> void:
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
	# 같은 씨앗·틱 수의 헤드리스 실행기 결과와 글자까지 같은 timeseries.csv
	var dir := ProjectSettings.globalize_path("user://test_experiment/lab")
	var rdir := ProjectSettings.globalize_path("user://test_experiment/runner")
	t.check(x.export_dir(dir).is_empty(), "내보내기 성공")
	for f in ["summary.json", "timeseries.csv", "chronicle.csv", "lineage.csv", "final.snapshot.json"]:
		t.check(FileAccess.file_exists(dir.path_join(f)), "내보낸 파일 %s" % f)
	var runner = load("res://tests/run_experiment.gd")
	var a: Dictionary = runner.parse_args(PackedStringArray(["--seed=42", "--generations=1000000", "--max-ticks=%d" % TICKS, "--out=" + rdir, "--quiet"]))
	a.silent = true
	t.check(runner.run(a) == 0, "실행기 실행")
	var lab_csv := FileAccess.get_file_as_string(dir.path_join("timeseries.csv"))
	var run_csv := FileAccess.get_file_as_string(rdir.path_join("timeseries.csv"))
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
	# LabMain 을 거쳐 진행해도 기록·신호가 같다
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(1)
	lab.set_process(false)
	t.check(lab.new_experiment("default", {}, 42) == "" and lab.experiments.size() == 1, "실험실: 실험 하나")
	var got := [0]
	lab.recorded.connect(func(_i: int, _row: Dictionary): got[0] += 1)
	lab.step_ticks(TICKS)
	t.check(got[0] == TICKS / every and lab.experiments[0].rows().size() == TICKS / every + 1, "실험실 recorded 신호 %d번" % got[0])
	t.check(lab.experiments[0].recorder.timeseries_csv() == run_csv, "실험실을 거친 기록 = 실행기 결과")
	lab.queue_free()
	await t.frames(1)
