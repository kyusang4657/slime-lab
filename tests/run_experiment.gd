extends SceneTree
## 헤드리스 실험 실행기.
##   godot --headless --path . --script res://tests/run_experiment.gd -- --seed=42 --generations=1000 --out=results/seed42
## 선택: --preset=이름  --set=키=값(여러 번)  --max-ticks=N  --no-lineage  --snapshot-every=N  --resume=스냅숏.json  --quiet
## 끝나는 조건: 살아 있는 개체 평균 세대 ≥ generations, 멸종, 틱 상한. 마지막 줄은 RESULT: ...
## 종료 코드: 정상 0, 인자·설정 오류 2, 파일 쓰기 실패 3.

const PROGRESS_SECONDS := 10.0


func _init() -> void:
	var a := parse_args(OS.get_cmdline_user_args())
	if a.has("error"):
		printerr("인자 오류: " + a.error)
		quit(2)
		return
	var code := run(a)
	quit(code)


static func parse_args(args: PackedStringArray) -> Dictionary:
	var a := {seed = 1, generations = 100.0, out = "", preset = "default", sets = {}, max_ticks = -1,
		lineage = true, snapshot_every = 0, resume = "", quiet = false}
	for s in args:
		if s == "--no-lineage":
			a.lineage = false
		elif s == "--quiet":
			a.quiet = true
		elif s.begins_with("--seed="):
			if not s.substr(7).is_valid_int():
				return {error = "--seed 는 정수여야 합니다"}
			a.seed = s.substr(7).to_int()
		elif s.begins_with("--generations="):
			if not s.substr(14).is_valid_float():
				return {error = "--generations 는 수여야 합니다"}
			a.generations = s.substr(14).to_float()
		elif s.begins_with("--out="):
			a.out = s.substr(6)
		elif s.begins_with("--preset="):
			a.preset = s.substr(9)
		elif s.begins_with("--max-ticks="):
			a.max_ticks = s.substr(12).to_int()
		elif s.begins_with("--snapshot-every="):
			a.snapshot_every = s.substr(17).to_int()
		elif s.begins_with("--resume="):
			a.resume = s.substr(9)
		elif s.begins_with("--set="):
			var kv := s.substr(6)
			var eq := kv.find("=")
			if eq <= 0:
				return {error = "--set 은 키=값 형식이어야 합니다: %s" % s}
			a.sets[kv.substr(0, eq)] = SimConfig.parse_value(kv.substr(eq + 1))
		else:
			return {error = "알 수 없는 인자: %s" % s}
	if a.out == "":
		return {error = "--out=결과폴더 가 필요합니다"}
	return a


## 실험 하나를 돌리고 결과를 쓴다. 종료 코드를 돌려준다.
static func run(a: Dictionary) -> int:
	var wd: SimWorld
	var resumed_from := ""
	if a.resume != "":
		var lr := SimSnapshot.load_file(a.resume)
		if lr.world == null:
			printerr("스냅숏을 읽을 수 없습니다: " + lr.error)
			return 2
		wd = lr.world
		resumed_from = a.resume
	else:
		var b := SimConfig.build(a.preset, a.sets)
		if b.error != "":
			printerr("설정 오류: " + b.error)
			return 2
		wd = SimWorld.new()
		var e := wd.setup(b.config, a.seed)
		if e != "":
			printerr("설정 오류: " + e)
			return 2
	var max_ticks: int = a.max_ticks if a.max_ticks > 0 else int(wd.cfg.run.max_ticks)
	var rec := SimRecorder.new()
	var rec_every := int(wd.cfg.record.every)
	rec.record(wd)
	var t0 := Time.get_ticks_msec()
	var last_print := t0
	var last_tick := wd.tick
	var reason := ""
	SimRecorder.prepare_dir(ProjectSettings.globalize_path(a.out))
	while true:
		if wd.is_extinct():
			reason = "extinction"
			break
		if wd.mean_generation() >= a.generations:
			reason = "generations"
			break
		if wd.tick >= max_ticks:
			reason = "max_ticks"
			break
		wd.step()
		if wd.tick % rec_every == 0:
			rec.record(wd)
		if a.snapshot_every > 0 and wd.tick % a.snapshot_every == 0:
			SimSnapshot.save_file(wd, ProjectSettings.globalize_path(a.out).path_join("snapshot-%d.json" % wd.tick))
		if not a.quiet and Time.get_ticks_msec() - last_print >= PROGRESS_SECONDS * 1000.0:
			var now := Time.get_ticks_msec()
			print("  t=%d pop=%d gen=%.1f civ=%s  %.0f틱/초" % [wd.tick, wd.population(), wd.mean_generation(),
					SimWorld.STAGE_NAMES[wd.stage], float(wd.tick - last_tick) * 1000.0 / float(now - last_print)])
			last_print = now
			last_tick = wd.tick
	if wd.tick % rec_every != 0:
		rec.record(wd)
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	var out_dir: String = ProjectSettings.globalize_path(a.out)
	# max_ticks = 실제로 쓴 틱 상한(--max-ticks 또는 설정 run.max_ticks): 분석 도구가 이어 돌리기 때 다른 상한의 결과를 가려냄
	var extra := {end_reason = reason, run_seconds = secs, generations_target = a.generations, preset = a.preset,
		overrides = a.sets, resumed_from = resumed_from, max_ticks = max_ticks}
	var failed := rec.write_all(out_dir, wd, extra, a.lineage)
	var serr := SimSnapshot.save_file(wd, out_dir.path_join("final.snapshot.json"))
	if serr != "":
		failed.append("final.snapshot.json(" + serr + ")")
	if a.get("silent", false):
		return 0 if failed.is_empty() else 3
	print("RESULT: seed=%d generations=%.1f ticks=%d pop=%d civ=%d(%s) hash=%s time=%.1fs reason=%s%s" % [
		wd.seed_value, wd.mean_generation(), wd.tick, wd.population(), wd.stage, SimWorld.STAGE_NAMES[wd.stage],
		wd.history_hash.substr(0, 12), secs, reason, "" if failed.is_empty() else " write_failed=" + ",".join(failed)])
	return 0 if failed.is_empty() else 3
