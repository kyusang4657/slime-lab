extends SceneTree
## 헤드리스 실험 실행기.
##   godot --headless --path . --script res://tests/run_experiment.gd -- --seed=42 --generations=1000 --out=results/seed42
## Windows 는 콘솔에 RESULT 줄이 보이는 Godot_v4.4.1-stable_win64_console.exe 로 같은 인자(docs/ANALYSIS.md "Windows").
## 선택: --preset=이름  --set=키=값(여러 번)  --max-ticks=N  --no-lineage  --snapshot-every=N  --resume=스냅숏.json  --quiet
## 인자 규칙(어기면 인자 오류): --seed 는 64비트 정수, --generations 는 0 보다 큰 유한한 수, --max-ticks 는 1~TICK_LIMIT,
## --snapshot-every 는 0(끔)~TICK_LIMIT 의 정수(1e5·10k 처럼 글자가 섞이면 거부). 상대 경로는 프로젝트 폴더(--path) 기준.
## --resume: 설정·씨앗은 스냅숏의 것을 쓴다 — --seed·--preset·--set 과 함께 주면 인자 오류. 이어 돌린 summary.json 은
## preset = ""·overrides = {}(스냅숏에는 예설정 이름이 없음 — 실험실에서 스냅숏을 연 실험과 같음, 실제 설정은 config),
## resumed_from = 실제로 읽은 파일, resume_status = "loaded"(본 파일) · "backup"(본 파일이 깨져 .bak 에서 — 경고 줄을 찍음).
## 이어 돌릴 스냅숏이 --out 폴더 바로 안에 있으면 거부(그 폴더를 비우며 지우게 되므로).
## 결과 폴더(--out): 없거나 비었으면 그대로 쓴다. 실행기가 쓰는 파일(OUT_FILES·snapshot-<틱>.json, 그리고 그 .tmp·.bak·.broken)만
## 있으면 그것을 모두 지우고 새로 쓴다(앞 실행의 lineage.csv·snapshot-N.json·.bak 이 새 결과와 섞이지 않게). OUT_KEEP(.gdignore·
## analyze.py 의 run.log·OS 가 만드는 파일)은 그대로 둔다. 그 밖의 파일이나 하위 폴더가 하나라도 있으면 아무것도 지우지 않고 오류 2.
## 설정 오류는 결과 폴더를 보기 전에 거른다(설정이 틀리면 앞 결과를 건드리지 않음).
## 쓰는 순서: (중간 스냅숏) → final.snapshot.json → SimRecorder.write_all(summary.json·CSV).
## 끝나는 조건: 살아 있는 개체 평균 세대 ≥ generations, 멸종, 틱 상한. 마지막 줄은 RESULT: ...(쓰기 실패면 끝에 write_failed=…).
## 종료 코드: 정상 0, 인자·설정·결과 폴더 오류 2, 파일 쓰기 실패 3(--snapshot-every 의 중간 스냅숏 포함 — 오류 줄도 찍고
## summary.json 의 write_failed 에도 적음). 검사: tools/test_runner_cli.py(명령줄 그대로), tests/run_tests.gd test_runner.

const PROGRESS_SECONDS := 10.0
## 틱 상한 2^31−1: 틱을 담는 세계 배열(PackedInt32Array)이 뒤집히지 않는 가장 큰 틱(검토 J01). 설정의 run.max_ticks 도 이 안에서 쓴다.
const TICK_LIMIT := 2147483647
## 64비트 정수의 끝(--seed 범위 — 넘으면 to_int 가 엔진 오류 줄만 찍고 말없이 잘라 버림)
const INT64_MAX := 9223372036854775807
## 실행기가 결과 폴더에 쓰는 파일. 같은 폴더를 다시 쓰면 지우고 새로 쓴다(각각 OUT_SUFFIXES 를 붙인 SimSnapshot 부산물까지).
const OUT_FILES: Array[String] = ["summary.json", "timeseries.csv", "chronicle.csv", "lineage.csv", "final.snapshot.json"]
## 저장 중 임시 파일·직전 정상본·깨진 파일 보관(SimSnapshot.save_file·load_file)
const OUT_SUFFIXES: Array[String] = [".tmp", ".bak", ".broken"]
## --snapshot-every 의 중간 스냅숏 이름
const SNAPSHOT_PATTERN := "^snapshot-\\d+\\.json$"
## 결과 폴더에 있어도 되고 지우지 않는 파일: Godot 가져오기 막기, analyze.py 의 실행 기록, OS 가 폴더마다 만드는 파일
const OUT_KEEP: Array[String] = [".gdignore", "run.log", ".DS_Store", "Thumbs.db", "desktop.ini"]
## 거부할 때 오류 문장에 적는 모르는 파일 수
const LIST_MAX := 5


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
	# 이어 돌리기와 함께 줄 수 없는 인자(설정·씨앗은 스냅숏의 것을 씀)
	var cond: Array[String] = []
	for s in args:
		if s == "--no-lineage":
			a.lineage = false
		elif s == "--quiet":
			a.quiet = true
		elif s.begins_with("--seed="):
			var r := int_arg("--seed", s.substr(7), -INT64_MAX - 1, INT64_MAX)
			if r.has("error"):
				return r
			a.seed = r.value
			_add_once(cond, "--seed")
		elif s.begins_with("--generations="):
			var g := s.substr(14)
			if not g.is_valid_float() or not is_finite(g.to_float()) or g.to_float() <= 0.0:
				return {error = "--generations 는 0 보다 큰 수여야 합니다: %s" % g}
			a.generations = g.to_float()
		elif s.begins_with("--out="):
			a.out = s.substr(6)
		elif s.begins_with("--preset="):
			a.preset = s.substr(9)
			_add_once(cond, "--preset")
		elif s.begins_with("--max-ticks="):
			var r := int_arg("--max-ticks", s.substr(12), 1, TICK_LIMIT)
			if r.has("error"):
				return r
			a.max_ticks = r.value
		elif s.begins_with("--snapshot-every="):
			var r := int_arg("--snapshot-every", s.substr(17), 0, TICK_LIMIT)
			if r.has("error"):
				return r
			a.snapshot_every = r.value
		elif s.begins_with("--resume="):
			a.resume = s.substr(9)
		elif s.begins_with("--set="):
			var kv := s.substr(6)
			var eq := kv.find("=")
			if eq <= 0:
				return {error = "--set 은 키=값 형식이어야 합니다: %s" % s}
			a.sets[kv.substr(0, eq)] = SimConfig.parse_value(kv.substr(eq + 1))
			_add_once(cond, "--set")
		else:
			return {error = "알 수 없는 인자: %s" % s}
	if a.out == "":
		return {error = "--out=결과폴더 가 필요합니다"}
	if a.resume != "" and not cond.is_empty():
		return {error = "--resume 은 스냅숏의 설정·씨앗으로 이어 돌립니다 — %s 와 함께 줄 수 없습니다" % "·".join(cond)}
	return a


static func _add_once(list: Array[String], s: String) -> void:
	if not list.has(s):
		list.append(s)


## 정수 인자 하나: 10진 정수(is_valid_int — "1e5"·"10k"·"abc" 거부)이고 64비트 안이며 lo~hi 인가. 결과: {value} 또는 {error}
static func int_arg(name: String, text: String, lo: int, hi: int) -> Dictionary:
	var bad := {error = "%s 는 %s~%s 의 정수여야 합니다: %s" % [name, str(lo), str(hi), text]}
	if not text.is_valid_int():
		return bad
	# 64비트를 넘는 글자는 to_int 전에 거른다(자릿수 비교)
	var digits := text.lstrip("+-").lstrip("0")
	var limit := str(INT64_MAX) if not text.begins_with("-") else str(INT64_MAX).left(-1) + "8"
	if digits.length() > limit.length() or (digits.length() == limit.length() and digits > limit):
		return bad
	var v := text.to_int()
	if v < lo or v > hi:
		return bad
	return {value = v}


## 실험 하나를 돌리고 결과를 쓴다. 종료 코드를 돌려준다.
static func run(a: Dictionary) -> int:
	var say: bool = not a.quiet and not a.get("silent", false)
	var wd: SimWorld
	var resumed_from := ""
	var resume_status := ""
	var out_dir: String = abs_path(a.out)
	if a.resume != "":
		var lr := SimSnapshot.load_file(a.resume)
		if lr.world == null:
			printerr("스냅숏을 읽을 수 없습니다: " + lr.error)
			return 2
		wd = lr.world
		resume_status = lr.status
		resumed_from = a.resume
		if lr.status == "backup":
			resumed_from = a.resume + ".bak"
			printerr("경고: %s 이(가) 깨져(%s) 백업 %s 에서 이어 돌립니다 — 백업은 같은 이름으로 앞서 저장한 다른 실험일 수 있습니다(summary.json 의 resume_status = backup)"
					% [a.resume, lr.error, resumed_from])
		if abs_path(resumed_from).get_base_dir() == out_dir:
			printerr("이어 돌릴 스냅숏이 결과 폴더 안에 있습니다(%s) — 결과 폴더를 비우며 지우게 되므로 다른 --out 을 주세요" % resumed_from)
			return 2
	else:
		var b := SimConfig.build(a.preset, a.sets)
		if b.error != "":
			printerr("설정 오류: " + b.error)
			return 2
		wd = SimWorld.new()
		var e := wd.setup(b.config, a.seed)
		# setup 이 중간에 스크립트 오류로 멈추면 ""(성공)과 같은 값을 돌려준다 — 마지막 단계(첫 역사 해시)까지 갔는지 본다(검토 I02)
		if e == "" and wd.history_hash == "":
			e = "세계를 만들다 멈췄습니다(설정 값이 맞지 않음 — 위의 SCRIPT ERROR 참고)"
		if e != "":
			printerr("설정 오류: " + e)
			return 2
	var cleared := clear_out_dir(out_dir)
	if cleared.error != "":
		printerr(cleared.error)
		return cleared.code
	if say and cleared.removed > 0:
		print("앞 실행의 결과 파일 %d개를 지우고 새로 씁니다: %s" % [cleared.removed, out_dir])
	var max_ticks: int = a.max_ticks if a.max_ticks > 0 else mini(int(wd.cfg.run.max_ticks), TICK_LIMIT)
	var rec := SimRecorder.new()
	var rec_every := int(wd.cfg.record.every)
	rec.record(wd)
	var t0 := Time.get_ticks_msec()
	var last_print := t0
	var last_tick := wd.tick
	var reason := ""
	var failed := PackedStringArray()
	SimRecorder.prepare_dir(out_dir)
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
			var sname := "snapshot-%d.json" % wd.tick
			var se := SimSnapshot.save_file(wd, out_dir.path_join(sname))
			if se != "":
				printerr("중간 스냅숏을 쓰지 못했습니다: %s (%s)" % [out_dir.path_join(sname), se])
				failed.append(sname + "(" + se + ")")
		if say and Time.get_ticks_msec() - last_print >= PROGRESS_SECONDS * 1000.0:
			var now := Time.get_ticks_msec()
			print("  t=%d pop=%d gen=%.1f civ=%s  %.0f틱/초" % [wd.tick, wd.population(), wd.mean_generation(),
					SimWorld.STAGE_NAMES[wd.stage], float(wd.tick - last_tick) * 1000.0 / float(now - last_print)])
			last_print = now
			last_tick = wd.tick
	# 끝 줄: 마지막 기록 줄이 지금 틱이 아니면 한 줄(이어 돌리자마자 끝나도 같은 틱을 두 번 쓰지 않음 — 실험실과 같은 줄, 검토 I23)
	if rec.rows.is_empty() or int(rec.rows.back().tick) != wd.tick:
		rec.record(wd)
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	var serr := SimSnapshot.save_file(wd, out_dir.path_join("final.snapshot.json"))
	if serr != "":
		printerr("최종 스냅숏을 쓰지 못했습니다: %s (%s)" % [out_dir.path_join("final.snapshot.json"), serr])
		failed.append("final.snapshot.json(" + serr + ")")
	# max_ticks = 실제로 쓴 틱 상한(--max-ticks 또는 설정 run.max_ticks): 분석 도구가 이어 돌리기 때 다른 상한의 결과를 가려냄.
	# 이어 돌렸으면 예설정·덮어쓰기는 알 수 없음(""·{} — 실제 설정은 config). write_failed = summary.json 보다 먼저 못 쓴 파일.
	var extra := {end_reason = reason, run_seconds = secs, generations_target = a.generations,
		preset = "" if a.resume != "" else a.preset, overrides = {} if a.resume != "" else a.sets,
		resumed_from = resumed_from, resume_status = resume_status, max_ticks = max_ticks, write_failed = Array(failed)}
	failed.append_array(rec.write_all(out_dir, wd, extra, a.lineage))
	if a.get("silent", false):
		return 0 if failed.is_empty() else 3
	# 씨앗은 str(): "%d" 는 INT64_MIN 에 부호를 두 번 붙임(검토 J31)
	print("RESULT: seed=%s generations=%.1f ticks=%d pop=%d civ=%d(%s) hash=%s time=%.1fs reason=%s%s" % [
		str(wd.seed_value), wd.mean_generation(), wd.tick, wd.population(), wd.stage, SimWorld.STAGE_NAMES[wd.stage],
		wd.history_hash.substr(0, 12), secs, reason, "" if failed.is_empty() else " write_failed=" + ",".join(failed)])
	return 0 if failed.is_empty() else 3


## 절대 경로(res://·user:// 는 풀고, 상대 경로는 작업 폴더 = --path 의 프로젝트 폴더 기준), 끝 "/" 없이 정리.
static func abs_path(p: String) -> String:
	var g := ProjectSettings.globalize_path(p)
	if g.is_relative_path():
		g = DirAccess.open(".").get_current_dir().path_join(g)
	return g.simplify_path()


## 실행기가 쓰는 결과 파일 이름인가(OUT_FILES·snapshot-<틱>.json 과 그 .tmp·.bak·.broken)
static func is_runner_file(name: String) -> bool:
	var base := name
	for suf in OUT_SUFFIXES:
		if base.ends_with(suf):
			base = base.left(-suf.length())
			break
	return OUT_FILES.has(base) or RegEx.create_from_string(SNAPSHOT_PATTERN).search(base) != null


## 결과 폴더 정리(머리 주석의 규칙). 결과: {removed = 지운 파일 수, error = "" 또는 오류 문장, code = 오류일 때 종료 코드}
static func clear_out_dir(dir: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(dir):
		return {removed = 0, error = "", code = 0}
	var d := DirAccess.open(dir)
	if d == null:
		return {removed = 0, error = "결과 폴더를 열 수 없습니다: %s (%s)" % [dir, error_string(DirAccess.get_open_error())], code = 3}
	d.include_hidden = true
	var unknown := PackedStringArray()
	for sub in d.get_directories():
		unknown.append(sub + "/")
	var stale := PackedStringArray()
	for f in d.get_files():
		if OUT_KEEP.has(f):
			continue
		if is_runner_file(f):
			stale.append(f)
		else:
			unknown.append(f)
	if not unknown.is_empty():
		var more := unknown.size() - mini(unknown.size(), LIST_MAX)
		return {removed = 0, code = 2, error = "결과 폴더 %s 에 실행기가 쓰지 않는 것이 있어 쓰지 않습니다: %s%s — 빈 폴더나 새 --out 을 주세요"
				% [dir, ", ".join(unknown.slice(0, LIST_MAX)), (" 외 %d개" % more) if more > 0 else ""]}
	for f in stale:
		if DirAccess.remove_absolute(dir.path_join(f)) != OK:
			return {removed = 0, code = 3, error = "앞 실행의 결과 파일을 지울 수 없습니다: %s" % dir.path_join(f)}
	return {removed = stale.size(), error = "", code = 0}
