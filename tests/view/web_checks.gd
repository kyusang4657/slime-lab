extends RefCounted
## 웹 체험판용 내려받기 검사: 결과 zip 의 내용, 스냅숏 JSON, 파라미터 패널의 웹 모드 단추.
## (브라우저 내려받기 호출 자체는 웹에서만 — 데스크톱에서는 같은 바이트를 user://downloads/ 에 저장해 확인)

const MIN_CHECKS := 14


func run(t) -> void:
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(2)
	lab.set_process(false)
	t.check(lab.new_experiment("default", {}, 3) == "", "실험 만들기")
	lab.step_ticks(120)
	var bytes := lab.results_zip_bytes()
	t.check(bytes.size() > 0, "결과 zip 바이트 %d" % bytes.size())
	var zpath := ProjectSettings.globalize_path("user://web_checks.zip")
	var f := FileAccess.open(zpath, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var zr := ZIPReader.new()
	t.check(zr.open(zpath) == OK, "zip 열기")
	var names := zr.get_files()
	for want in ["summary.json", "timeseries.csv", "chronicle.csv", "lineage.csv", "final.snapshot.json"]:
		t.check(names.has(want), "zip 안에 %s (%s)" % [want, names])
	var ts := zr.read_file("timeseries.csv").get_string_from_utf8()
	t.check(ts == lab.experiments[0].recorder.timeseries_csv(), "zip 의 시계열 = 기록기 CSV")
	zr.close()
	# 스냅숏 내려받기(데스크톱: user://downloads/) → 다시 열면 같은 해시
	t.check(lab.download_snapshot(0) == "" and lab.last_download_name.ends_with(".json"), "스냅숏 내려받기 이름 %s" % lab.last_download_name)
	var snap := "user://downloads/" + lab.last_download_name
	var r := Experiment.from_snapshot(snap)
	t.check(r.experiment != null and r.experiment.world.history_hash == lab.world.history_hash, "내려받은 스냅숏을 열면 같은 해시")
	t.check(lab.download_results() == "" and lab.last_download_name.ends_with(".zip"), "결과 내려받기 이름 %s" % lab.last_download_name)
	# 파라미터 패널의 웹 모드
	var pp: ParamPanel = null
	for n in lab.find_children("*", "ParamPanel", true, false):
		pp = n
	t.check(pp != null, "파라미터 패널이 있음")
	if pp != null:
		pp.set_web_mode(true)
		t.check(pp._export_btn.text.contains("내려받기") and pp._save_btn.text.contains("내려받기") and not pp._open_btn.visible, "웹 모드: 내려받기 단추, 스냅숏 열기 숨김")
		lab.last_download_name = ""
		pp._on_export()
		t.check(lab.last_download_name.ends_with(".zip"), "웹 모드 내보내기 단추 → 결과 zip")
		pp.set_web_mode(false)
		t.check(pp._export_btn.text == "CSV 내보내기" and pp._open_btn.visible, "데스크톱 모드로 되돌림")
	lab.queue_free()
	await t.frames(1)
