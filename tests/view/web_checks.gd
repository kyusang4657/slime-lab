extends RefCounted
## 웹 체험판용 내려받기 검사: 결과 zip 의 내용, 스냅숏 JSON, 파라미터 패널의 웹 모드 단추.
## (브라우저 내려받기 호출 자체는 웹에서만 — 데스크톱에서는 같은 바이트를 user://downloads/ 에 저장해 확인)
## zip 을 만든 임시 폴더는 숨은 .gdignore 까지 지워져 남지 않는다(혼자·비교). 검사가 쓴 파일도 끝에 지운다.
## 웹의 임시 폴더 이름은 프로세스 번호 없이, 묶기 실패는 알림 하나에 실패한 파일 이름.

const MIN_CHECKS := 29


## 내보내기에서 두 파일을 실패로 돌려주는 실험(실제 디스크 오류 없이 — 엔진 ERROR 줄 없이 — 실패 길을 검사)
class FailingExperiment extends Experiment:
	func export_dir(_dir: String, _with_lineage: bool = true) -> PackedStringArray:
		return PackedStringArray(["summary.json", "timeseries.csv"])



func run(t) -> void:
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(2)
	lab.set_process(false)
	var written: Array[String] = []
	t.check(lab.new_experiment("default", {}, 3) == "", "실험 만들기")
	lab.step_ticks(120)
	var bytes := lab.results_zip_bytes()
	t.check(bytes.size() > 0, "결과 zip 바이트 %d" % bytes.size())
	t.check(lab.last_zip_tmp_dir != "" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(lab.last_zip_tmp_dir))
			and not FileAccess.file_exists(ProjectSettings.globalize_path(lab.last_zip_tmp_dir) + ".zip"),
			"zip 을 만든 임시 폴더·zip 이 남지 않음(숨은 .gdignore 까지 지움) %s" % lab.last_zip_tmp_dir)
	var zpath := ProjectSettings.globalize_path("user://web_checks-%d.zip" % OS.get_process_id())
	written.append(zpath)
	var f := FileAccess.open(zpath, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var zr := ZIPReader.new()
	t.check(zr.open(zpath) == OK, "zip 열기")
	var names := zr.get_files()
	for want in ["summary.json", "timeseries.csv", "chronicle.csv", "lineage.csv", "final.snapshot.json"]:
		t.check(names.has(want), "zip 안에 %s (%s)" % [want, names])
	t.check(not names.has(".gdignore"), "zip 에 숨은 파일 없음")
	var ts := zr.read_file("timeseries.csv").get_string_from_utf8()
	t.check(ts == lab.experiments[0].recorder.timeseries_csv(), "zip 의 시계열 = 기록기 CSV")
	zr.close()
	# 스냅숏 내려받기(데스크톱: user://downloads/) → 다시 열면 같은 해시
	t.check(lab.download_snapshot(0) == "" and lab.last_download_name.ends_with(".json") and lab.last_download_name.contains("-seed3-tick120"),
			"스냅숏 내려받기 이름 %s" % lab.last_download_name)
	var snap := "user://downloads/" + lab.last_download_name
	written.append(ProjectSettings.globalize_path(snap))
	var r := Experiment.from_snapshot(snap)
	t.check(r.experiment != null and r.experiment.world.history_hash == lab.world.history_hash, "내려받은 스냅숏을 열면 같은 해시")
	t.check(lab.download_results() == "" and lab.last_download_name.ends_with(".zip"), "결과 내려받기 이름 %s" % lab.last_download_name)
	written.append(ProjectSettings.globalize_path("user://downloads/" + lab.last_download_name))
	# 비교 모드: zip 에 A/·B/, 임시 폴더 남지 않음, 스냅숏 이름은 그 실험의 씨앗(B = 씨앗 4), 결과 이름에 두 씨앗
	t.check(lab.start_compare({preset = "default", seed = 3}, {preset = "default", seed = 4}) == "", "비교 시작(씨앗 3 | 4)")
	lab.step_ticks(40)
	var cbytes := lab.results_zip_bytes()
	t.check(cbytes.size() > 0 and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(lab.last_zip_tmp_dir)),
			"비교 모드 zip(%d 바이트), 임시 폴더(A/·B/)도 남지 않음" % cbytes.size())
	f = FileAccess.open(zpath, FileAccess.WRITE)
	f.store_buffer(cbytes)
	f.close()
	t.check(zr.open(zpath) == OK and zr.get_files().has("A/timeseries.csv") and zr.get_files().has("B/timeseries.csv"), "비교 zip 에 A/·B/")
	zr.close()
	t.check(lab.download_snapshot(1) == "" and lab.last_download_name.contains("-seed4-tick40") and lab.last_download_name.ends_with("-B.json"),
			"B 스냅숏 이름에 B 의 씨앗: %s" % lab.last_download_name)
	written.append(ProjectSettings.globalize_path("user://downloads/" + lab.last_download_name))
	t.check(lab.download_results() == "" and lab.last_download_name.contains("-seed3-vs-seed4"), "비교 결과 이름에 두 씨앗: %s" % lab.last_download_name)
	written.append(ProjectSettings.globalize_path("user://downloads/" + lab.last_download_name))
	lab.new_experiment("default", {}, 3)
	# 웹의 임시 폴더 이름: 프로세스 번호 없이 µs + 번호(웹 엔진은 OS.get_process_id() 를 지원하지 않아 내려받을 때마다
	# 브라우저 콘솔에 엔진 오류 두 줄 — 검토 I39), 데스크톱은 그대로 프로세스 번호
	var d1 := LabMain.zip_tmp_dir(true)
	var d2 := LabMain.zip_tmp_dir(true)
	t.check(d1 != d2 and d1.begins_with(LabMain.WEB_EXPORT_DIR + "/web-") and not d1.contains("/%d-" % OS.get_process_id()),
			"웹 임시 폴더 이름에 프로세스 번호 없음(%s · %s)" % [d1, d2])
	t.check(LabMain.zip_tmp_dir(false).begins_with("%s/%d-" % [LabMain.WEB_EXPORT_DIR, OS.get_process_id()]), "데스크톱 임시 폴더 이름은 프로세스 번호")
	# 묶기 실패: 알림 하나, 어느 실험의 어느 파일인지(검토 I40: 예전엔 "결과를 묶을 수 없습니다" 만 — 파일 이름이 없었고, 패널이
	# 알림을 하나 더 띄움)
	var good: Experiment = Experiment.create("default", {}, 3).experiment
	var bad := FailingExperiment.new()
	bad.preset = "default"
	bad.seed_value = 4
	bad.label = Experiment.default_label("default", {}, 4)
	bad._adopt(t.make_world({}, 4))
	lab._adopt_list([good, bad])
	var msg := lab.download_results()
	var errs := 0
	for v in lab.visible_toasts():
		errs += 1 if v.kind == "error" else 0
	t.check(msg == "결과를 묶을 수 없습니다: B/summary.json, B/timeseries.csv" and errs == 1 and lab.visible_toasts()[-1].text == msg,
			"비교 모드 묶기 실패 = 알림 하나·실패한 파일(%s, 오류 알림 %d)" % [msg, errs])
	t.check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(lab.last_zip_tmp_dir)), "실패해도 임시 폴더를 지움")
	lab._adopt_list([bad])
	t.check(lab.download_results() == "결과를 묶을 수 없습니다: summary.json, timeseries.csv", "혼자 모드 묶기 실패 = 파일 이름만")
	lab.new_experiment("default", {}, 3)
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
		written.append(ProjectSettings.globalize_path("user://downloads/" + lab.last_download_name))
		pp.set_web_mode(false)
		t.check(pp._export_btn.text == "CSV 내보내기" and pp._open_btn.visible, "데스크톱 모드로 되돌림")
	lab.queue_free()
	await t.frames(1)
	# 이 검사가 쓴 파일(내려받기·zip)을 지운다(사용자 실험 폴더 옆에 남지 않게)
	var left := 0
	for p in written:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
		left += 1 if FileAccess.file_exists(p) else 0
	t.check(left == 0, "검사가 쓴 파일 %d개를 지움" % written.size())
