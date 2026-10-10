extends RefCounted
## 4단계 종단 검사(통합): 실제 실험실 장면에 실제 패널(ParamPanel·GraphPanel·ChroniclePanel·LabSound)을 함께 띄워
## 패널 → 실험실 → 시뮬레이션 → 그래프·연대기로 이어지는 길을 확인한다. 프레임은 advance_frame 으로 직접 몬다.
## ① 파라미터 패널 값 → 새 실험의 설정·씨앗(헤드리스와 같은 역사) ② 패널로 비교 시작 → 지도 둘, 그래프 계열 둘, 연대기 A/B 줄
## ③ 연대기 줄을 실제 마우스로 누름 → 그 실험의 행위자 선택 + 그래프 시점 표시 ④ 패널의 CSV 내보내기 = 헤드리스 실행기 결과(글자까지)
## ⑤ 스냅숏 저장 → 열기 = 같은 상태·해시(비교 모드의 -A/-B 파일도) ⑥ 소리 상자 ↔ LabSound.enabled ⑦ 한국어 낱말 단위 줄바꿈.
## 창은 최소 창(lab.min_width × lab.min_height — 검토 J29 뒤 1280×640).

const MIN_CHECKS := 61
## "세계 그대로" 비교(스냅숏 모든 절 — 틱을 진행하지 않은 채 역사 해시를 견주면 아무것도 증명하지 못함, 검토 I89)
const WorldCompare := preload("res://tests/view/world_compare.gd")
const DT := 1.0 / 60.0
## 임시 폴더(프로세스마다 따로 — 저장소 사본 여럿에서 함께 돌려도 섞이지 않게, 처음과 끝에 숨은 파일까지 지움)
var TMP := "user://integration4_checks-%d" % OS.get_process_id()
## 비교 장면: A = demo_fast·씨앗 1(돌연변이율만 바꿈), B = demo_fast·씨앗 2(세대 이정표만 바꿈 — B 줄이 연대기에 꼭 생기게)
const A_SETS := {"mutation.rate": 0.1}
const B_SETS := {"record.generation_milestone": 5}
## B 에 첫 밭(행위자가 있는 사건)이 생길 때까지 진행하는 틱 한도
const FARM_MAX_TICKS := 3000
## 프레임으로 진행하는 한도(64배)
const FRAME_CAP := 4000


func run(t) -> void:
	var root_size: Vector2i = t.root.size
	t.root.size = Vector2i(UiConfig.integer("lab.min_width"), UiConfig.integer("lab.min_height"))
	_clean_dir(ProjectSettings.globalize_path(TMP))
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(2)
	lab.set_process(false)
	t.check(lab.param_panel != null and lab.graph_panel != null and lab.chronicle_panel != null and lab.lab_sound != null,
			"실험실에 실제 패널 넷(ParamPanel·GraphPanel·ChroniclePanel·LabSound)")
	await _param_apply(t, lab)
	await _compare(t, lab)
	await _chronicle_click(t, lab)
	_csv_export(t, lab)
	await _snapshot(t, lab)
	_sound(t, lab)
	_keep_words(t)
	lab.queue_free()
	await t.frames(1)
	t.root.size = root_size
	_clean_dir(ProjectSettings.globalize_path(TMP))
	t.check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TMP)), "임시 폴더를 지움(숨은 파일까지)")


## ① 파라미터 패널(예설정·씨앗·세 주요 값·고급 설정 키) → 새 실험 → 실제 세계 설정·씨앗, 화면을 거쳐도 헤드리스와 같은 역사.
func _param_apply(t, lab: LabMain) -> void:
	var pp := lab.param_panel
	var before_seed := lab.world.seed_value
	var sets := {"mutation.rate": 0.08, "resources.scale": 1.4, "population.initial": 150, "time.day_ticks": 50}
	var errs := pp.set_value("preset", "demo_fast") + pp.set_value("seed", 7)
	for k: String in sets:
		errs += pp.set_value(k, sets[k])
	t.check(errs == "", "패널에 값 넣기(예설정·씨앗·세 값·고급 키) 오류 없음 %s" % errs)
	t.check(lab.world.seed_value == before_seed and pp.status_text().begins_with("바꾼 값"),
			"값을 바꿔도 지금 실험은 그대로, 상태 줄 \"%s\"" % pp.status_text())
	var s := pp.current_settings(0)
	t.check(s.preset == "demo_fast" and int(s.seed) == 7 and SimConfig.deep_equal(s.overrides, sets), "current_settings = 넣은 조건 %s" % str(s))
	t.check(pp.apply() == "", "새 실험(패널 apply)")
	var w := lab.world
	t.check(w.seed_value == 7 and is_equal_approx(float(w.cfg.mutation.rate), 0.08) and is_equal_approx(float(w.cfg.resources.scale), 1.4)
			and int(w.cfg.population.initial) == 150 and int(w.cfg.time.day_ticks) == 50 and w.population() == 150,
			"새 세계의 설정·씨앗·개체 수가 패널 값(씨앗 %d, 개체 %d)" % [w.seed_value, w.population()])
	var x := lab.experiment(0)
	t.check(x.preset == "demo_fast" and SimConfig.deep_equal(x.overrides, sets), "실험의 만든 조건 = 예설정 + 바꾼 값 4개")
	t.check(pp.status_text() == ParamPanel.TEXT_SAME, "적용하면 \"%s\"" % ParamPanel.TEXT_SAME)
	t.check(lab.graph_panel.series_points(0, 0) == 1 and lab.chronicle_panel.item_count() == 0, "새 실험 → 그래프는 첫 줄만, 연대기 비움")
	# 64배 실제 프레임 길로 진행 → 헤드리스와 같은 상태
	await _run_frames(t, lab, 240)
	var ref: SimWorld = t.make_world(sets, 7, "demo_fast")
	ref.step_n(lab.world.tick)
	var diff: String = t.same_state(lab.world, ref)
	t.check(diff == "" and ref.history_hash == lab.world.history_hash, "패널로 만든 실험을 화면으로 %d틱 진행해도 헤드리스와 같음 %s" % [lab.world.tick, diff])
	var rows := x.rows().size()
	var gp := lab.graph_panel
	var drawn: Array = await _drawn_series(t, gp)
	t.check(rows > 1 and gp.series_points(0, 0) == rows and drawn == [[0], [0], [0]],
			"패널이 기록 %d줄을 모두 받고, 그래프 세 개가 저마다 그 계열을 그림 %s" % [rows, str(drawn)])
	t.check(lab.chronicle_panel.item_count() == mini(lab.world.chronicle.size(), lab.chronicle_panel.max_items),
			"연대기 줄 = 세계 연대기(%d)" % lab.world.chronicle.size())


## ② 패널로 비교: 비교 모드 → A·B 칸 조건 → 나란히 시작 → 지도 둘, 각 설정, 그래프 계열 둘(범례 둘), 연대기 A/B 줄, 해시 둘.
func _compare(t, lab: LabMain) -> void:
	var pp := lab.param_panel
	pp.set_compare_mode(true)
	t.check(pp.is_compare_mode() and not lab.is_comparing(), "비교 모드 단추: B 칸만 나타나고 아직 시작 안 함")
	var errs := pp.set_value("preset", "demo_fast", 0) + pp.set_value("preset", "demo_fast", 1)
	pp.revert()
	errs += pp.set_value("seed", 1, 0) + pp.set_value("seed", 2, 1)
	for k: String in A_SETS:
		errs += pp.set_value(k, A_SETS[k], 0)
	for k: String in B_SETS:
		errs += pp.set_value(k, B_SETS[k], 1)
	t.check(errs == "" and SimConfig.deep_equal(pp.current_settings(0).overrides, A_SETS) and SimConfig.deep_equal(pp.current_settings(1).overrides, B_SETS),
			"A·B 칸 조건(A %s / B %s)" % [str(pp.current_settings(0)), str(pp.current_settings(1))])
	t.check(pp.apply_compare() == "", "나란히 시작(패널 apply_compare)")
	t.check(lab.is_comparing() and lab.experiments.size() == 2 and lab.map_view_of(1) != null and lab.map_view_of(1).is_inside_tree(), "지도 둘(A | B)")
	var a := lab.experiment(0)
	var b := lab.experiment(1)
	var dm := float(SimConfig.build("demo_fast", {}).config.mutation.rate)
	t.check(is_equal_approx(float(a.world.cfg.mutation.rate), 0.1) and is_equal_approx(float(b.world.cfg.mutation.rate), dm)
			and int(b.world.cfg.record.generation_milestone) == 5 and int(a.world.cfg.record.generation_milestone) != 5
			and a.world.seed_value == 1 and b.world.seed_value == 2,
			"A·B 세계가 각 칸의 조건(씨앗 1·2, 바꾼 값은 그 칸에만)")
	t.check(pp.status_text() == ParamPanel.TEXT_SAME, "나란히 시작하면 \"%s\"" % ParamPanel.TEXT_SAME)
	var legend := lab.graph_panel.legend_texts()
	t.check(legend.size() == 2 and legend[0] == a.display_name() and legend[1] == b.display_name(), "그래프 범례 둘 = A·B 이름 %s" % str(legend))
	# B 에 첫 밭(행위자 있는 사건)이 생길 때까지 실제 프레임으로(64배)
	lab.set_paused(false)
	lab.set_speed(64)
	var frames := 0
	while frames < FRAME_CAP and b.world.tick < FARM_MAX_TICKS and not _has_kind(b.world, "first_farm"):
		lab.advance_frame(DT)
		frames += 1
	lab.advance_frame(DT)
	t.check(_has_kind(b.world, "first_farm"), "B 에 첫 밭(틱 %d, 프레임 %d)" % [b.world.tick, frames])
	t.check(a.world.tick == b.world.tick, "두 세계가 같은 틱(%d)" % a.world.tick)
	var ra: SimWorld = t.make_world(A_SETS, 1, "demo_fast")
	ra.step_n(a.world.tick)
	var rb: SimWorld = t.make_world(B_SETS, 2, "demo_fast")
	rb.step_n(b.world.tick)
	var da: String = t.same_state(a.world, ra)
	var db: String = t.same_state(b.world, rb)
	t.check(da == "" and db == "" and ra.history_hash == a.world.history_hash and rb.history_hash == b.world.history_hash,
			"패널로 시작한 비교를 화면으로 진행해도 A·B 모두 헤드리스와 같음 %s %s" % [da, db])
	var gp := lab.graph_panel
	# 그래프마다 실제로 그린 선의 계열(GraphView.last_lines)을 본다 — series_points 는 그래프와 상관없이 기록 줄 수라 그래프
	# 하나가 B 를 빠뜨리거나 숨어도 통과했음(검토 I38)
	var drawn: Array = await _drawn_series(t, gp)
	t.check(gp.series_points(0, 0) == a.rows().size() and gp.series_points(0, 1) == b.rows().size() and a.rows().size() > 1 and b.rows().size() > 1
			and gp.graph_count() == 3 and drawn == [[0, 1], [0, 1], [0, 1]],
			"그래프 세 개가 저마다 계열 둘을 그림 %s(A %d줄 · B %d줄)" % [str(drawn), a.rows().size(), b.rows().size()])
	var cp := lab.chronicle_panel
	var n_a := 0
	var n_b := 0
	var tags_ok := true
	for i in cp.item_count():
		var it := cp.item(i)
		if int(it.index) == 0:
			n_a += 1
			tags_ok = tags_ok and cp.item_text(i).begins_with("A · ")
		else:
			n_b += 1
			tags_ok = tags_ok and cp.item_text(i).begins_with("B · ")
	var total := a.world.chronicle.size() + b.world.chronicle.size()
	t.check(n_a > 0 and n_b > 0 and tags_ok, "연대기에 A 줄 %d · B 줄 %d, 줄 앞 이름표" % [n_a, n_b])
	t.check(cp.item_count() == mini(total, cp.max_items), "연대기 줄 수 = 두 세계 연대기 합(%d / %d)" % [cp.item_count(), total])
	var toasts_ok := true
	for v in lab.visible_toasts():
		var tx := str(v.text)
		if str(v.kind) in ["discovery", "store_built", "first_farm", "farm_lost", "milestone", "extinction"]:
			toasts_ok = toasts_ok and (tx.begins_with("A · ") or tx.begins_with("B · "))
	t.check(toasts_ok, "사건 알림 앞에 A·/B· (%d개)" % lab.visible_toasts().size())


## ③ 연대기의 B 첫 밭 줄을 실제 마우스로 누름 → B 의 행위자 선택(정보 창 이름표 B, 고리는 B 지도에만) + 그래프 시점 표시.
## 행위자 없는 A 줄은 시점만 바꾸고 선택은 그대로. 누르기는 시뮬레이션을 바꾸지 않음.
func _chronicle_click(t, lab: LabMain) -> void:
	lab.set_paused(true)
	lab.advance_frame(DT)
	var cp := lab.chronicle_panel
	cp.set_filter(ChroniclePanel.FILTER_ALL)
	var bi := -1
	for i in cp.item_count():
		if int(cp.item(i).actor) >= 0 and int(cp.item(i).index) == 1:
			bi = i
			break
	t.check(bi >= 0, "연대기에 B 의 행위자 있는 줄(첫 밭)")
	if bi < 0:
		return
	var it := cp.item(bi)
	var fp_a := WorldCompare.fingerprint(lab.experiment(0).world)
	var fp_b := WorldCompare.fingerprint(lab.experiment(1).world)
	var tick0 := lab.world.tick
	cp.scroll_to_item(bi)
	await t.frames(2)
	var r := cp.item_rect(bi)
	t.check(r.size.y > 0.0 and lab.get_global_rect().encloses(r), "그 줄이 화면(최소 창 %s) 안에 보임 %s" % [str(t.root.size), str(r)])
	_click(t, r.get_center())
	await t.frames(1)
	lab.advance_frame(DT)
	var actor := int(it.actor)
	t.check(lab.selected_id() == actor and lab.selected_index() == 1, "누르면 B 의 행위자 #%d 선택(지금 #%d · 실험 %d)" % [actor, lab.selected_id(), lab.selected_index()])
	t.check(lab.graph_panel.cursor_tick == int(it.tick), "그래프 시점 표시 = 그 줄의 틱 %d(지금 %d)" % [int(it.tick), lab.graph_panel.cursor_tick])
	# 값만이 아니라 세 그래프가 실제로 그 틱에 시점 표시선을 그림(GraphView.last_cursor). 이 장면의 첫 밭 틱은 이미 가로축 안이라
	# 검토 I15(마지막 기록 줄 뒤 사건)는 잡지 못한다 — I15 를 지키는 검사는 graph_checks _cursor_tail_checks(검토 최종 확인).
	await t.frames(2)
	var drawn := true
	for g in 3:
		var cur: Array = lab.graph_panel.view(g).last_cursor
		drawn = drawn and cur.any(func(c: Dictionary) -> bool: return int(c.tick) == int(it.tick))
	t.check(drawn, "세 그래프 모두 틱 %d 에 시점 표시선을 그림(%s)" % [int(it.tick), str(lab.graph_panel.view(0).last_cursor)])
	t.check(lab.info_panel.current_id() == actor and lab.info_panel.current_tag() == "B", "정보 창 = #%d, 머리 이름표 B" % actor)
	var alive := lab.experiment(1).world.index_of_id(actor) >= 0
	var ring_b: Dictionary = lab.map_view_of(1).ring_info()
	var ring_a: Dictionary = lab.map_view_of(0).ring_info()
	t.check(bool(ring_b.visible) == alive and not bool(ring_a.visible), "고리는 B 지도에만(살아 있음 %s)" % str(alive))
	# 행위자 없는 A 줄: 시점만
	var ai := -1
	for i in cp.item_count():
		if int(cp.item(i).actor) < 0 and int(cp.item(i).index) == 0:
			ai = i
			break
	if ai >= 0:
		var ia := cp.item(ai)
		cp.scroll_to_item(ai)
		await t.frames(2)
		_click(t, cp.item_rect(ai).get_center())
		await t.frames(1)
		t.check(lab.graph_panel.cursor_tick == int(ia.tick) and lab.selected_id() == actor and lab.selected_index() == 1,
				"행위자 없는 A 줄: 시점만 틱 %d, 선택 그대로" % int(ia.tick))
	# 멈춘 채라 틱이 그대로 — 역사 해시는 검사점에서만 바뀌므로 스냅숏의 모든 절(에너지·유전체·난수 상태 등)을 견준다
	var da := WorldCompare.diff(fp_a, lab.experiment(0).world)
	var db := WorldCompare.diff(fp_b, lab.experiment(1).world)
	t.check(lab.world.tick == tick0 and da == "" and db == "", "연대기를 눌러도 두 세계 그대로(스냅숏 모든 절) A[%s] B[%s]" % [da, db])


## ④ 패널의 CSV 내보내기(export_to = 단추가 부르는 함수) → 비교면 dir/A·dir/B. 각 timeseries.csv·chronicle.csv 가
## 같은 예설정·바꾼 값·씨앗·틱 수의 헤드리스 실행기 결과와 글자까지 같다 — record.every 의 배수가 아닌 틱에서도(실행기는
## 그 틱에 끝 줄을 하나 더 쓰고, 화면은 내보낼 때 같은 끝 줄을 파일에 더함).
func _csv_export(t, lab: LabMain) -> void:
	var a := lab.experiment(0)
	var b := lab.experiment(1)
	# 배수가 아닌 틱에서 내보낸다(배수면 한 틱 더 — 끝 줄 길을 늘 지나게)
	var every := int(a.world.cfg.record.every)
	if a.world.tick % every == 0:
		lab.step_ticks(1)
	var ticks := a.world.tick
	t.check(ticks % every != 0, "record.every(%d)의 배수가 아닌 틱 %d 에서 내보냄" % [every, ticks])
	var dir := TMP.path_join("compare")
	t.check(lab.param_panel.export_to(dir) == "", "패널에서 비교 결과 내보내기(틱 %d)" % ticks)
	var same_a := _same_as_runner(t, ProjectSettings.globalize_path(dir.path_join("A")), "demo_fast", A_SETS, 1, ticks, "runner_a")
	var same_b := _same_as_runner(t, ProjectSettings.globalize_path(dir.path_join("B")), "demo_fast", B_SETS, 2, ticks, "runner_b")
	t.check(same_a, "A/timeseries.csv·chronicle.csv = 헤드리스 실행기(demo_fast · 씨앗 1 · %s · %d틱)" % [str(A_SETS), ticks])
	t.check(same_b, "B/timeseries.csv·chronicle.csv = 헤드리스 실행기(demo_fast · 씨앗 2 · %s · %d틱)" % [str(B_SETS), ticks])
	var sm = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(dir.path_join("B/summary.json"))))
	t.check(typeof(sm) == TYPE_DICTIONARY and sm.source == "lab" and sm.tag == "B" and sm.history_hash == b.world.history_hash, "B/summary.json 출처·이름표·해시")
	var toast_ok := false
	for v in lab.visible_toasts():
		toast_ok = toast_ok or str(v.text).begins_with("결과를 내보냈습니다: " + ProjectSettings.globalize_path(dir))
	t.check(toast_ok, "내보내기 알림에 절대 경로")


## ⑤ 스냅숏: 비교 중 저장 → -A/-B 두 파일. 혼자 모드 저장 → 더 진행 → 열기 = 저장한 틱·해시·상태, 이어 돌려도 헤드리스와 같음.
func _snapshot(t, lab: LabMain) -> void:
	var pp := lab.param_panel
	var cmp := TMP.path_join("cmp.json")
	var hb := lab.experiment(1).world.history_hash
	var tb := lab.experiment(1).world.tick
	var fp_b := WorldCompare.fingerprint(lab.experiment(1).world)
	# 저장 대화 상자의 기본 이름은 두 씨앗(G44 — 예전엔 A 씨앗만이라 -B.json 에도 A 의 씨앗이 붙었음)
	var dn := pp._default_snapshot_name()
	t.check(dn.contains("-seed1-vs-seed2-tick%d" % lab.world.tick) and dn.ends_with(".json"), "비교 중 스냅숏 기본 이름에 두 씨앗: %s" % dn)
	t.check(pp.save_snapshot_to(cmp) == "" and FileAccess.file_exists(TMP.path_join("cmp-A.json")) and FileAccess.file_exists(TMP.path_join("cmp-B.json")),
			"비교 중 스냅숏 저장 → cmp-A.json · cmp-B.json")
	t.check(pp.open_snapshot_from(TMP.path_join("cmp-B.json")) == "" and not lab.is_comparing() and lab.world.history_hash == hb and lab.world.tick == tb
			and lab.world.seed_value == 2, "B 스냅숏을 열면 혼자 모드로 B 의 세계(틱 %d, 해시 같음)" % tb)
	var dopen := WorldCompare.diff(fp_b, lab.world, WorldCompare.OPENED_IGNORE)
	t.check(dopen == "", "연 B 세계 = 저장한 B 세계(스냅숏 모든 절 — 열 때 첫 기록 줄이 가져간 기간 출생·사망 수만 빼고) %s" % dopen)
	t.check(not pp.is_compare_mode() and pp.status_text() == ParamPanel.TEXT_SAME, "스냅숏을 열면 비교 모드 끔·\"%s\"" % ParamPanel.TEXT_SAME)
	t.check(lab.graph_panel.series_points(0, 0) == 1 and lab.graph_panel.legend_texts().size() == 1, "그래프는 연 스냅숏의 첫 줄부터(범례 하나)")
	t.check(lab.chronicle_panel.item_count() == mini(lab.world.chronicle.size(), lab.chronicle_panel.max_items) and lab.chronicle_panel.item_count() > 0,
			"연대기는 스냅숏에 담긴 지난 사건(%d)" % lab.world.chronicle.size())
	# 혼자 모드 저장 → 더 진행 → 열기
	var path := TMP.path_join("single.json")
	var t0 := lab.world.tick
	var h0 := lab.world.history_hash
	t.check(pp.save_snapshot_to(path) == "" and FileAccess.file_exists(path), "혼자 모드 스냅숏 저장(틱 %d)" % t0)
	await _run_frames(t, lab, 120)
	t.check(lab.world.tick > t0, "저장 뒤 더 진행(틱 %d)" % lab.world.tick)
	t.check(pp.open_snapshot_from(path) == "" and lab.world.tick == t0 and lab.world.history_hash == h0, "열면 저장한 틱·해시(%d)" % t0)
	var ref: SimWorld = t.make_world(B_SETS, 2, "demo_fast")
	ref.step_n(t0)
	var d0: String = t.same_state(lab.world, ref)
	t.check(d0 == "", "연 세계 = 처음부터 돌린 헤드리스 세계(같은 틱) %s" % d0)
	await _run_frames(t, lab, 150)
	ref.step_n(lab.world.tick - t0)
	var d1: String = t.same_state(lab.world, ref)
	t.check(d1 == "" and ref.history_hash == lab.world.history_hash, "열고 화면으로 이어 돌려도(틱 %d) 헤드리스와 같음 %s" % [lab.world.tick, d1])
	t.check(pp.open_snapshot_from(TMP.path_join("없는파일.json")) != "" and lab.world.tick > t0 and pp.error_text() != "", "없는 파일: 오류 글, 지금 실험 그대로")


## ⑥ 패널의 "소리" 상자 ↔ LabSound.enabled(끄면 재생 안 함).
func _sound(t, lab: LabMain) -> void:
	var cb := lab.param_panel.control("sound") as CheckBox
	t.check(cb != null and not cb.disabled and cb.button_pressed == lab.lab_sound.enabled, "소리 상자가 LabSound 를 찾아 켜짐 상태를 보임")
	if cb == null:
		return
	t.check(lab.events_tagged.is_connected(lab.lab_sound._on_events), "실험실의 LabSound 가 사건(events_tagged)에 붙어 있음")
	var was := lab.lab_sound.enabled
	cb.button_pressed = false
	t.check(not lab.lab_sound.enabled and not lab.lab_sound.play_event("discovery"), "소리 끄기 → LabSound.enabled 꺼짐, 재생 안 함")
	cb.button_pressed = true
	t.check(lab.lab_sound.enabled, "소리 켜기 → 다시 켜짐")
	lab.lab_sound.enabled = was


## ⑦ UiTheme.keep_words: 폭은 그대로, 한글 낱말 가운데("발/견")에서 줄을 바꾸지 않음. plain_text 로 되돌림.
func _keep_words(t) -> void:
	var f := UiTheme.regular_font()
	var s := "A · 시연·검사용(아주 빠른 발견) · 씨앗 1"
	var k := UiTheme.keep_words(s)
	t.check(is_equal_approx(f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, f.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
			and UiTheme.plain_text(k) == s, "keep_words: 글자 폭 같음, plain_text 로 되돌림")
	var p := TextParagraph.new()
	p.add_string(k, f, 15)
	p.width = 200.0
	p.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var lines: Array[String] = []
	for i in p.get_line_count():
		var rg := p.get_line_range(i)
		lines.append(UiTheme.plain_text(k.substr(rg.x, rg.y - rg.x)).strip_edges())
	t.check(lines.size() == 2 and lines[1].begins_with("발견)"), "keep_words: 빈칸에서만 줄바꿈 %s" % str(lines))


# ════════════════════════════ 도움 ════════════════════════════

## 64배로 실제 프레임 길(advance_frame)을 따라 n틱 넘게 진행한다(멈춤 풂).
func _run_frames(t, lab: LabMain, n: int) -> void:
	lab.set_paused(false)
	lab.set_speed(64)
	var start := lab.world.tick
	var frames := 0
	while lab.world.tick < start + n and frames < FRAME_CAP:
		lab.advance_frame(DT)
		frames += 1
	lab.set_paused(true)
	lab.advance_frame(DT)
	await t.frames(1)


## 그래프마다 실제로 그린 선의 계열 번호(다시 그린 뒤 GraphView.last_lines 에서 점이 있는 선 — 정렬). 이번에 다시 그려지지
## 않은(숨은 등) 그래프는 빈 목록. 결과는 그래프 순서대로의 배열(예: [[0, 1], [0, 1], [0, 1]]).
func _drawn_series(t, gp: GraphPanel) -> Array:
	var before: Array[int] = []
	for g in gp.graph_count():
		before.append(gp.view(g).draw_count)
	gp.redraw_now()
	await t.frames(2)
	var out := []
	for g in gp.graph_count():
		var v := gp.view(g)
		var got := {}
		if v.draw_count > before[g] and v.is_visible_in_tree():
			for l in v.last_lines:
				if int(l.points) > 0:
					got[int(l.series)] = true
		var keys := got.keys()
		keys.sort()
		out.append(keys)
	return out


static func _has_kind(w: SimWorld, kind: String) -> bool:
	for e in w.chronicle:
		if str(e.kind) == kind:
			return true
	return false


## 내보낸 폴더의 timeseries.csv·chronicle.csv 가 같은 조건 헤드리스 실행기 결과와 같은지
func _same_as_runner(t, lab_dir: String, preset: String, sets: Dictionary, seed_value: int, ticks: int, sub: String) -> bool:
	var rdir := ProjectSettings.globalize_path(TMP.path_join(sub))
	var args := PackedStringArray(["--seed=%d" % seed_value, "--preset=" + preset, "--generations=1000000", "--max-ticks=%d" % ticks, "--out=" + rdir, "--quiet"])
	for k: String in sets:
		args.append("--set=%s=%s" % [k, JSON.stringify(sets[k])])
	var runner = load("res://tests/run_experiment.gd")
	var a: Dictionary = runner.parse_args(args)
	if a.has("error"):
		t.check(false, "실행기 인자 %s" % str(a.error))
		return false
	a.silent = true
	if runner.run(a) != 0:
		return false
	var ok := true
	for f in ["timeseries.csv", "chronicle.csv"]:
		var x := FileAccess.get_file_as_string(lab_dir.path_join(f))
		var y := FileAccess.get_file_as_string(rdir.path_join(f))
		ok = ok and x != "" and x == y
	return ok


## 뷰포트에 실제 마우스 입력(움직임 → 왼쪽 누름 → 뗌)
func _click(t, pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	t.root.push_input(mm)
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = pos
		mb.global_position = pos
		t.root.push_input(mb)


## 폴더를 통째로 지운다(숨은 .gdignore 까지 — 빠뜨리면 폴더가 남음).
static func _clean_dir(abs_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	var d := DirAccess.open(abs_dir)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		_clean_dir(abs_dir.path_join(sub))
	for f in d.get_files():
		DirAccess.remove_absolute(abs_dir.path_join(f))
	DirAccess.remove_absolute(abs_dir)
