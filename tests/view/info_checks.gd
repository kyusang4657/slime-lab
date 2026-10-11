extends RefCounted
## InfoPanel·BrainView 검사. tests/run_view_tests.gd 가 불러 run(t) 을 부른다.
## 계약: docs/VIEW-API.md "InfoPanel". 픽셀은 tests/info_capture.gd 로 본다.

const SEED := 3
const WARMUP := 400
## 죽을 때까지 기다리는 최대 틱(최대 나이 + 흔들림보다 넉넉히)
const DEATH_GUARD := 1000
## 지켜볼 개체의 남은 수명 하한(틱): refresh 와 자식 단추 늘어남을 여러 번 겪도록
const MIN_LIFE_LEFT := 60
## 이 모듈이 적어도 하는 검사 수(중간에 스크립트 오류로 끊기면 실행기가 실패로 셈)
const MIN_CHECKS := 91
## 1600×900 실험실에서 정보 창 높이(창 높이 − 위쪽 막대 최소 높이) — V07
const LAB_HEIGHT_1600 := 900.0
## V07 을 재 볼 개체 수 한도
const V07_SAMPLES := 60
## 자동 줄바꿈 안내를 나눠 볼 가장 좁은 폭과 폭 간격(px) — 한 낱말보다 넓게
const WRAP_SWEEP_MIN := 160.0
const WRAP_SWEEP_STEP := 2.0
## v0.2 1단계 검사(DESIGN-v0.2 10절): 학습 세계(learn_basic + 기억 2 — 기억 출력 행은 배우지 않음을 보려고)를 돌릴 틱, 씨앗,
## 배운 두뇌가 바뀔 때까지 기다릴 최대 틱
const LEARN_TICKS := 300
const LEARN_SEED := 2
const LEARN_WAIT := 200
## 생애 단계 경계 표를 볼 (수명, 성숙, 어른 몫, 늙음 몫): 기본·몫 × 수명이 반올림 끝인 것·젊은 구간이 빔·어린 다음 바로 늙은·
## 성숙이 수명보다 큼
const STAGE_CASES := [[200, 30, 0.4, 0.8], [230, 30, 0.4, 0.8], [171, 30, 0.7, 0.9], [200, 30, 0.1, 0.8], [200, 30, 0.1, 0.1],
		[10, 3, 0.7, 0.7], [20, 30, 0.4, 0.8], [1, 0, 0.0, 1.0]]
## 차이 탭 색 상한(1·2·5 × 10^k, 아래는 info.heatmap_diff_min 0.01): [가장 큰 차이, 기대 상한]
const DIFF_SCALES := [[0.0, 0.01], [0.01, 0.01], [0.011, 0.02], [0.037, 0.05], [0.05, 0.05], [0.14, 0.2], [0.21, 0.5], [3.0, 5.0], [8.0, 10.0]]
const WorldCompare := preload("res://tests/view/world_compare.gd")


func run(t) -> void:
	var world: SimWorld = t.make_world({}, SEED)
	var ref: SimWorld = t.make_world({}, SEED)
	world.step_n(WARMUP)
	ref.step_n(WARMUP)
	var panel := InfoPanel.new()
	t.root.add_child(panel)
	await t.frames(1)

	# ── 빈 상태 ──
	t.check(panel.current_id() == -1 and panel.summary_text().contains("슬라임을 눌러 고르세요"), "처음엔 빈 안내 문구")
	var pw := UiConfig.num("lab.right_panel_width")
	t.check(is_equal_approx(panel.custom_minimum_size.x, pw), "정보 창 너비 = ui.lab.right_panel_width")

	# ── 살아 있는 개체: id·세대 ──
	var id := _pick(world)
	t.check(id >= 0, "부모·자식이 있는 살아 있는 개체를 찾음(id %d)" % id)
	if id < 0:
		panel.queue_free()
		return
	var d := world.slime_info(id)
	panel.show_slime(world, id)
	await t.frames(1)
	var sm := panel.summary_text()
	t.check(panel.current_id() == id, "current_id() = 보이는 id")
	t.check(sm.contains("#%d" % id) and sm.contains("%d세대" % int(d.gen)) and sm.contains("살아 있음"),
			"살아 있는 개체의 id·세대·생사 표시: " + sm)
	t.check(panel.get_combined_minimum_size().x <= pw + 0.5, "내용이 창 너비를 밀어내지 않음(%.0f)" % panel.get_combined_minimum_size().x)

	# ── 가계 단추: 부모·조부모·자식 id ──
	var parents := _ids(panel, InfoPanel.REL_PARENT)
	var exp_parents: Array[int] = [int(d.parent_a)]
	if int(d.parent_b) != SimWorld.NO_PARENT and int(d.parent_b) != int(d.parent_a):
		exp_parents.append(int(d.parent_b))
	t.check(parents == exp_parents, "부모 단추 id %s = %s" % [parents, exp_parents])
	var exp_gp: Array[int] = []
	for p in exp_parents:
		var pd := world.slime_info(p)
		for g in [int(pd.parent_a), int(pd.parent_b)]:
			if g != SimWorld.NO_PARENT and not exp_gp.has(g):
				exp_gp.append(g)
	t.check(_ids(panel, InfoPanel.REL_GRANDPARENT) == exp_gp, "조부모 단추 id(최대 4) = 부모의 부모")
	var kids := _ids(panel, InfoPanel.REL_CHILD)
	var exp_kids := Array(world.children_of(id, UiConfig.integer("info.children_max")))
	t.check(kids == exp_kids and not kids.is_empty(), "자식 단추 id = children_of(id, children_max) %s" % [kids])

	# ── 단추를 누르면 slime_requested(그 id) ──
	var got: Array[int] = []
	panel.slime_requested.connect(func(x: int) -> void: got.append(x))
	var pressed_ids: Array[int] = []
	for b in _buttons(panel):
		pressed_ids.append(int(b.get_meta(InfoPanel.META_ID)))
		b.pressed.emit()
	t.check(got == pressed_ids and got.size() == parents.size() + exp_gp.size() + kids.size(),
			"가계 단추를 누르면 그 id 로 slime_requested(%d개)" % got.size())

	# ── 따라가기 ──
	var follows: Array[bool] = []
	panel.follow_toggled.connect(func(on: bool) -> void: follows.append(on))
	var fb := _follow_button(panel)
	t.check(fb != null and fb.toggle_mode, "따라가기 토글 단추가 있음")
	if fb != null:
		fb.button_pressed = true
		fb.button_pressed = false
		t.check(follows == [true, false], "따라가기 단추 → follow_toggled(true/false)")
		panel.set_follow(true)
		t.check(fb.button_pressed and follows.size() == 2, "set_follow 는 단추만 맞추고 신호를 내지 않음")
		panel.set_follow(false)
	# 키보드: 따라가기·가계 단추가 초점을 받는다(Tab 으로 닿고 Enter 로 누름 — 검토 J16: 예전엔 모두 FOCUS_NONE).
	# 스페이스는 실험실이 먼저 받아 멈춤(lab_checks)
	var all_focus := fb != null and fb.focus_mode == Control.FOCUS_ALL and not _buttons(panel).is_empty()
	for b in _buttons(panel):
		all_focus = all_focus and b.focus_mode == Control.FOCUS_ALL
	t.check(all_focus, "따라가기·가계 단추 %d개가 키보드 초점을 받음" % _buttons(panel).size())

	# ── refresh 는 싸다: 자식 수가 그대로면 children_of 를 다시 부르지 않는다 ──
	var scans := panel.children_scans
	for k in 30:
		panel.refresh()
	t.check(panel.children_scans == scans, "같은 상태에서 refresh 30번 → 자식 목록을 다시 훑지 않음")

	# ── 지켜보는 중 진행 → 죽음 감지(ref 도 같은 틱만큼) ──
	var every := UiConfig.integer("info.refresh_frames")
	var guard := 0
	var kids_ok := true
	var evals := 0
	var kids0 := int(world.slime_info(id).children)
	var grew := 0
	while world.index_of_id(id) != -1 and guard < DEATH_GUARD:
		world.step()
		ref.step()
		guard += 1
		if guard % every == 0:
			panel.refresh()
			var want := mini(int(world.slime_info(id).children), UiConfig.integer("info.children_max"))
			if world.index_of_id(id) != -1:
				evals += 1
				if _ids(panel, InfoPanel.REL_CHILD).size() != want:
					kids_ok = false
				if int(world.slime_info(id).children) > kids0:
					grew = int(world.slime_info(id).children) - kids0
	# 검사가 정말 돌았는지(지켜본 개체가 2틱 만에 죽어 한 번도 견주지 않던 문제)
	t.check(evals >= 3 and grew > 0, "지켜보는 동안 자식 단추를 %d번 견주었고 자식이 %d 늘어남(%d틱 생존)" % [evals, grew, guard])
	t.check(kids_ok, "살아 있는 동안 새 자식이 생기면 자식 단추가 따라 늘어남")
	t.check(world.index_of_id(id) == -1, "개체가 %d틱 안에 죽음" % DEATH_GUARD)
	panel.refresh()
	var dd := world.slime_info(id)
	var cname: String = SimWorld.CAUSE_NAMES[int(dd.cause)]
	sm = panel.summary_text()
	t.check(panel.current_id() == id and sm.contains("죽음") and sm.contains(cname) and sm.contains(_fmt(int(dd.death))),
			"refresh 가 죽음(원인·사망 틱)으로 바꿈: " + sm)
	t.check(_follow_button(panel).disabled, "죽은 개체는 따라가기 단추가 꺼짐")

	# ── 죽은 개체(계통 기록만) 직접 보이기: 원인 표시, 두뇌 없음 ──
	var dead_id := -1
	for k in world.lin_pa.size():
		var x := world.slime_info(k)
		if not bool(x.alive) and int(x.cause) != SimWorld.CAUSE_ALIVE:
			dead_id = k
			break
	t.check(dead_id >= 0, "죽은 개체 기록이 있음")
	if dead_id >= 0:
		var xd := world.slime_info(dead_id)
		panel.show_slime(world, dead_id)
		sm = panel.summary_text()
		t.check(panel.current_id() == dead_id and sm.contains("죽음") and sm.contains(SimWorld.CAUSE_NAMES[int(xd.cause)]),
				"죽은 개체는 원인을 보임: " + sm)

	await _labels(t, panel, world, dead_id)

	# ── 없는 id·빈 세계 ──
	panel.show_slime(world, world.lin_pa.size() + 1000)
	t.check(panel.current_id() == -1 and panel.summary_text().contains("기록이 없습니다"), "없는 id → 안내 문구, current_id -1")
	panel.show_slime(world, -5)
	t.check(panel.current_id() == -1, "음수 id → current_id -1")
	panel.refresh()
	panel.show_slime(null, id)
	t.check(panel.current_id() == -1, "세계 없음 → 빈 상태")
	panel.show_slime(world, world.s_id[0])
	panel.clear()
	t.check(panel.current_id() == -1 and panel.summary_text().contains("슬라임을 눌러 고르세요") and _buttons(panel).is_empty(),
			"clear() → 빈 안내, 가계 단추 없음")

	# ── 화면은 세계를 바꾸지 않는다: 여러 개체를 보이고 refresh 를 많이 불러도 상태·카운터 그대로 ──
	# (역사 해시는 진행 없이는 바뀌지 않으므로 상태 배열을 직접 견준다)
	var snap0: SimWorld = t.make_world({}, SEED)
	snap0.step_n(world.tick)
	var e0 := world.total_energy()
	var b0 := world.period_births
	for i in mini(world.population(), 40):
		panel.show_slime(world, world.s_id[i])
		for k in 3:
			panel.refresh()
	for k in mini(world.lin_pa.size(), 40):
		panel.show_slime(world, k)
		panel.refresh()
	var diff0: String = t.same_state(world, snap0)
	t.check(diff0 == "" and world.total_energy() == e0 and world.period_births == b0,
			"보이기·refresh 를 여러 번 해도 세계 상태가 그대로 %s" % diff0)
	panel.show_slime(world, world.s_id[0])
	# 해시 검사점(hash.every)을 하나 이상 지날 때까지 정보 창을 거쳐 진행
	var he := int(world.cfg.hash.every)
	var start_tick := world.tick
	var target := (start_tick / he + 1) * he
	while world.tick <= target:
		world.step()
		ref.step()
		panel.refresh()
	t.check(world.tick / he > start_tick / he and world.history_hash == ref.history_hash and world.tick == ref.tick,
			"정보 창을 거쳐 진행해도 역사 해시가 같음(틱 %d → %d, 검사점 %d 지남)" % [start_tick, world.tick, target])
	var diff: String = t.same_state(world, ref)
	t.check(diff == "", "정보 창을 거쳐 진행한 끝 상태(개체·에너지·유전체·먹이)가 같음 %s" % diff)
	t.check(world.period_births == ref.period_births and world.drain_events().size() == ref.drain_events().size(),
			"정보 창이 sample()·drain_events() 를 부르지 않음")

	# ── BrainView: 최소 크기 = L 에서 계산(기억 0·2) ──
	var cell := UiConfig.num("info.heatmap_cell")
	var sizes: Array[Vector2] = []
	for m in [0, 2]:
		var wm: SimWorld = t.make_world({"brain.memory_units": m}, SEED)
		var bv := BrainView.new()
		var g: PackedFloat32Array = wm.slime_info(wm.s_id[0]).genome
		bv.set_genome(wm.L, g)
		var L: Dictionary = wm.L
		var want := Vector2(UiConfig.num("info.heatmap_label_width") + float(maxi(int(L.n_in), int(L.n_hid))) * cell,
				UiConfig.num("info.heatmap_header_height") + float(int(L.n_hid)) * cell + UiConfig.num("info.heatmap_block_gap")
				+ cell + float(int(L.n_out)) * cell + UiConfig.num("info.heatmap_legend_height"))
		t.check(bv.custom_minimum_size.is_equal_approx(want), "기억 %d: BrainView 최소 크기 %s = %s" % [m, bv.custom_minimum_size, want])
		sizes.append(bv.custom_minimum_size)
		# 칸 ↔ 유전체 위치
		var x0 := UiConfig.num("info.heatmap_label_width")
		var c1 := bv.cell_at(Vector2(x0 + cell * 2.5, UiConfig.num("info.heatmap_header_height") + cell * 1.5))
		t.check(c1.get("block", "") == BrainView.BLOCK_W1 and is_equal_approx(float(c1.weight), float(g[1 * int(L.n_in) + 2])),
				"기억 %d: 위 덩어리 칸(은닉 2, 입력 3) = w1[1·n_in+2]" % m)
		var y2 := UiConfig.num("info.heatmap_header_height") + float(int(L.n_hid)) * cell + UiConfig.num("info.heatmap_block_gap") + cell
		var q := int(L.n_out) - 1
		var c2 := bv.cell_at(Vector2(x0 + cell * 0.5, y2 + cell * (float(q) + 0.5)))
		t.check(c2.get("block", "") == BrainView.BLOCK_W2 and is_equal_approx(float(c2.weight), float(g[int(L.w2_offset) + q * int(L.n_hid)])),
				"기억 %d: 아래 덩어리 마지막 줄 = w2[(n_out-1)·n_hid]" % m)
		t.check(not str(c2.text).is_empty(), "칸 풍선 도움말 글자")
		# 정보 창에 넣어도 너비 안
		panel.show_slime(wm, wm.s_id[0])
		t.check(panel.get_combined_minimum_size().x <= pw + 0.5, "기억 %d 세계도 창 너비 안(%.0f)" % [m, panel.get_combined_minimum_size().x])
		bv.free()
	t.check(sizes.size() == 2 and (sizes[1] - sizes[0]).is_equal_approx(Vector2(2.0 * cell, 2.0 * cell)),
			"기억 2개 → 열지도가 가로·세로로 2칸씩 커짐")
	t.check(BrainView.input_name(SimBrain.BASE_INPUTS) == "기억 1" and BrainView.output_name(SimBrain.BASE_OUTPUTS + 1) == "기억 2",
			"기억 입력·출력 이름")
	# 색: 0 = 창 색, 양수는 양수 색 쪽, 음수는 음수 색 쪽, 상한에서 끝 색
	var clamp_w := 4.0
	var mid := UiConfig.color("theme.panel")
	var pos := UiConfig.color("info.heatmap_positive")
	var neg := UiConfig.color("info.heatmap_negative")
	t.check(BrainView.weight_color(0.0, clamp_w).is_equal_approx(mid) and BrainView.weight_color(clamp_w, clamp_w).is_equal_approx(pos)
			and BrainView.weight_color(-clamp_w * 2.0, clamp_w).is_equal_approx(neg), "열지도 색: 0·+상한·−상한(넘침은 자름)")
	var cp := BrainView.weight_color(1.0, clamp_w)
	var cn := BrainView.weight_color(-1.0, clamp_w)
	t.check(_dist(cp, pos) < _dist(mid, pos) and _dist(cn, neg) < _dist(mid, neg), "양수는 양수 색 쪽, 음수는 음수 색 쪽")

	# ── 자식이 표시 한도보다 많으면 한도만큼 단추 + "+K" (한도를 잠시 2 로 낮춘 창) ──
	var many := -1
	for k in world.lin_pa.size():
		if int(world.slime_info(k).children) >= 3:
			many = k
			break
	t.check(many >= 0, "자식이 3 이상인 개체 기록이 있음")
	if many >= 0:
		var info_cfg: Dictionary = UiConfig.data()["info"]
		var keep: Variant = info_cfg["children_max"]
		info_cfg["children_max"] = 2
		var p2 := InfoPanel.new()
		info_cfg["children_max"] = keep
		t.root.add_child(p2)
		p2.show_slime(world, many)
		var n := int(world.slime_info(many).children)
		var more := ""
		for lb in p2.find_children("*", "Label", true, false):
			if (lb as Label).visible and (lb as Label).text.begins_with("+"):
				more = (lb as Label).text
		t.check(_ids(p2, InfoPanel.REL_CHILD) == Array(world.children_of(many, 2)) and more == "+%d" % (n - 2),
				"자식 %d 중 한도 2 → 단추 2개 + \"%s\"" % [n, more])
		p2.queue_free()
	# ── 큰 두뇌(설정 범위 끝: 기억 16, 은닉 32·64)도 창 너비를 밀어내지 않음(열지도는 좁히거나 가로 스크롤) ──
	for sets in [{"brain.memory_units": 16}, {"brain.hidden": 32}, {"brain.hidden": 64}, {"brain.hidden": 64, "brain.memory_units": 16}]:
		var wb: SimWorld = t.make_world(sets, SEED)
		panel.show_slime(wb, wb.s_id[0])
		await t.frames(1)
		t.check(panel.get_combined_minimum_size().x <= pw + 0.5, "%s: 정보 창 최소 폭 %.0f ≤ %.0f" % [sets, panel.get_combined_minimum_size().x, pw])
		# 칸을 좁혀 들어가는 크기(열 40 까지)는 가로 스크롤 없이 창 안에 맞춤
		var cols := maxi(int(wb.L.n_in), int(wb.L.n_hid))
		if cols <= 40:
			var bwid: float = panel._brain.custom_minimum_size.x
			t.check(bwid <= InfoPanel.brain_width() + 0.5, "%s: 열지도 너비 %.0f ≤ %.0f(칸을 좁혀 맞춤, 가로 스크롤 없음)" % [sets, bwid, InfoPanel.brain_width()])
	t.check(BrainView.size_for(world.L, InfoPanel.brain_width()).x <= InfoPanel.brain_width() + 0.5
			and BrainView.cell_width_for(world.L, InfoPanel.brain_width()) == UiConfig.num("info.heatmap_cell"),
			"보통 두뇌(12-8-8)는 칸을 좁히지 않고 창 안")
	# ── 공용 테마를 이어받음: 따라가기 단추 여백 = theme.button_padding_*, 말풍선 = 공용 모양 ──
	var fsb := _follow_button(panel).get_theme_stylebox("normal") as StyleBoxFlat
	t.check(fsb != null and is_equal_approx(fsb.content_margin_left, UiConfig.num("theme.button_padding_h"))
			and is_equal_approx(fsb.content_margin_top, UiConfig.num("theme.button_padding_v")),
			"따라가기 단추 여백 = theme.button_padding_h/v")
	var tip := panel.get_theme_stylebox("panel", "TooltipPanel") as StyleBoxFlat
	t.check(tip != null and tip.bg_color.is_equal_approx(UiConfig.color("theme.topbar")), "정보 창 말풍선 = 공용 말풍선 모양")
	# ── V07: 1600×900 실험실 높이에서 보통 개체(자식 두 줄 이하)는 스크롤 없이 두뇌 범례까지(여유 info.min_vertical_slack) ──
	await _v07(t, panel, world)
	await _stage1(t, panel, world)
	panel.queue_free()
	await t.frames(1)


## 글 표기(검토 I47·I48·I49·I86): "운반" 단위, 멸종 안내 아래 클릭 도움말 숨김, 자동 줄바꿈 안내가 낱말 가운데서 끊기지 않음,
## "고른 행동" 이 아직 열리지 않은 단계의 줍기·심기면 "(시도 · 발견 전)"·흐린 색.
func _labels(t, panel: InfoPanel, world: SimWorld, dead_id: int) -> void:
	# I47: 운반 = 나르는 먹이 양 + 단위(예전엔 "0.6" 만)
	var wc: SimWorld = t.make_world({}, SEED)
	wc.s_carry[0] = 0.6
	panel.show_slime(wc, wc.s_id[0])
	t.check(panel._v_carry.text == "먹이 0.6" and InfoPanel.carry_text(0.0) == "없음",
			"운반 값에 단위: \"%s\"(없으면 \"%s\")" % [panel._v_carry.text, InfoPanel.carry_text(0.0)])
	# I49: 기록만 남은 개체의 두뇌 안내는 낱말 단위로 줄바꿈(예전엔 "…그릴 수 없" / "습니다.")
	if dead_id >= 0:
		panel.show_slime(world, dead_id)
		await t.frames(2)
		var note: Label = panel._brain_note
		var split := _wrap_split(note)
		t.check(note.visible and UiTheme.plain_text(note.text) == InfoPanel.NO_BRAIN_TEXT and split == "",
				"두뇌 없음 안내가 폭 %.0f(와 더 좁은 폭)에서 낱말 가운데서 끊기지 않음 %s" % [note.size.x, split])
	# I48·I49: 바꾼 빈 안내(멸종 등)면 아래 클릭 도움말을 숨김, 긴 안내도 낱말 단위로 줄바꿈
	panel.clear()
	t.check(panel.empty_hint_visible(), "기본 빈 안내 아래 클릭 도움말이 보임")
	panel.set_empty_text("멸종했습니다 (틱 1,234)\n고를 개체가 없습니다")
	t.check(not panel.empty_hint_visible() and panel.summary_text() == "멸종했습니다 (틱 1,234)\n고를 개체가 없습니다",
			"멸종 안내면 \"지도에서 슬라임을 클릭하면…\" 도움말을 숨김(안내 \"%s\")" % panel.summary_text())
	panel.set_empty_text("모든 실험이 멸종해 고를 개체가 없습니다 새 실험을 시작하거나 스냅숏을 여세요")
	await t.frames(2)
	var split2 := _wrap_split(panel._empty_label)
	t.check(split2 == "", "긴 빈 안내도 폭 %.0f(와 더 좁은 폭)에서 낱말 가운데서 끊기지 않음 %s" % [panel._empty_label.size.x, split2])
	panel.set_empty_text("")
	t.check(panel.empty_hint_visible() and panel.summary_text() == InfoPanel.EMPTY_TEXT, "안내를 되돌리면 도움말도 다시 보임")
	# I86: 발견 전의 줍기·심기는 효과 없는 시도 — 이름 뒤 표시·흐린 색, 단계가 열리면 이름만
	t.check(InfoPanel.action_text(SimBrain.ACT_PLANT, SimWorld.STAGE_STORE) == "심기" + InfoPanel.ATTEMPT_SUFFIX
			and InfoPanel.action_text(SimBrain.ACT_PLANT, SimWorld.STAGE_FARM) == "심기"
			and InfoPanel.action_text(SimBrain.ACT_GATHER, SimWorld.STAGE_NONE) == "줍기" + InfoPanel.ATTEMPT_SUFFIX
			and InfoPanel.action_text(SimBrain.ACT_GATHER, SimWorld.STAGE_FORAGE) == "줍기"
			and InfoPanel.action_text(SimBrain.ACT_EAT, SimWorld.STAGE_NONE) == "먹기",
			"고른 행동: 단계 전 줍기·심기만 \"(시도 · 발견 전)\"")
	var tried := -1
	var plain := -1
	for i in world.population():
		var a := world.s_last_action[i]
		if tried < 0 and (a == SimBrain.ACT_PLANT or a == SimBrain.ACT_GATHER) and InfoPanel.is_attempt(a, world.stage):
			tried = world.s_id[i]
		elif plain < 0 and not InfoPanel.ACTION_STAGE.has(a):
			plain = world.s_id[i]
	t.check(world.stage == SimWorld.STAGE_NONE and tried >= 0 and plain >= 0, "발견 전 세계(단계 %d)에 줍기·심기를 고른 개체 #%d·다른 행동 #%d" % [world.stage, tried, plain])
	if tried >= 0 and plain >= 0:
		panel.show_slime(world, tried)
		var tx: String = panel._v_action.text
		var tc: Color = panel._v_action.get_theme_color("font_color")
		panel.show_slime(world, plain)
		var px: String = panel._v_action.text
		var pc: Color = panel._v_action.get_theme_color("font_color")
		t.check(tx.ends_with(InfoPanel.ATTEMPT_SUFFIX) and tc.is_equal_approx(UiConfig.color("theme.text_dim"))
				and not px.contains("시도") and pc.is_equal_approx(UiConfig.color("theme.text")),
				"정보 창: 발견 전 시도 \"%s\"(흐린 색), 다른 행동 \"%s\"" % [tx, px])


## 자동 줄바꿈 Label 이 낱말 가운데(빈칸이 아닌 곳)에서 줄을 바꾸는지. Label 과 같은 글꼴·크기·줄바꿈 규칙(WORD_SMART)으로
## 지금 폭(줄 수가 Label 과 같은지도 봄 — 두 줄 이상)과 WRAP_SWEEP_MIN 부터 지금 폭까지 WRAP_SWEEP_STEP 마다의 폭에서 줄을 나눠,
## 줄을 빈칸으로 이으면 원래 글(낱말 잇개 뺌)이 되는지 본다(어느 폭에서 음절 사이로 끊길지는 글꼴에 따라 달라 여러 폭에서).
## 모두 빈칸에서만 끊으면 "", 아니면 처음 틀린 폭과 나뉜 줄.
func _wrap_split(lb: Label) -> String:
	var now := _wrap_lines(lb, lb.size.x)
	if now.size() < 2 or now.size() != lb.get_line_count():
		return "폭 %.0f: %s(Label %d줄)" % [lb.size.x, str(now), lb.get_line_count()]
	var want := " ".join(UiTheme.plain_text(lb.text).replace("\n", " ").split(" ", false))
	var wd := lb.size.x
	while wd >= WRAP_SWEEP_MIN:
		var lines := _wrap_lines(lb, wd)
		if " ".join(lines) != want:
			return "폭 %.0f: %s" % [wd, str(lines)]
		wd -= WRAP_SWEEP_STEP
	return ""


## Label 글을 그 글꼴·크기·WORD_SMART 규칙으로 폭 wd 에서 나눈 줄(낱말 잇개 뺌, 앞뒤 빈칸 뺌).
func _wrap_lines(lb: Label, wd: float) -> PackedStringArray:
	var p := TextParagraph.new()
	p.add_string(lb.text, lb.get_theme_font("font"), lb.get_theme_font_size("font_size"))
	p.width = wd
	p.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var lines := PackedStringArray()
	for i in p.get_line_count():
		var rg := p.get_line_range(i)
		lines.append(UiTheme.plain_text(lb.text.substr(rg.x, rg.y - rg.x)).strip_edges())
	return lines


func _v07(t, panel: InfoPanel, world: SimWorld) -> void:
	var h := LAB_HEIGHT_1600 - UiConfig.num("lab.top_bar_min_height")
	panel.size = Vector2(UiConfig.num("lab.right_panel_width"), h)
	var slack := UiConfig.num("info.min_vertical_slack")
	var worst := -INF
	var worst_id := -1
	var n := 0
	for i in world.population():
		if n >= V07_SAMPLES:
			break
		var id := world.s_id[i]
		var d := world.slime_info(id)
		if int(d.parent_a) == SimWorld.NO_PARENT:
			continue
		panel.show_slime(world, id)
		await t.frames(1)
		# 자식 두 줄 이하만(V07 의 범위)
		var rows := _flow_rows(panel)
		if rows > 2:
			continue
		n += 1
		var o := panel.content_overflow()
		if o > worst:
			worst = o
			worst_id = id
	t.check(n > 0 and worst <= -slack, "V07: 정보 창 %.0fpx 높이에서 개체 %d마리 모두 스크롤 없음(가장 빠듯한 #%d 여유 %.0fpx ≥ %.0f)" % [h, n, worst_id, -worst, slack])


## 자식 단추 흐름의 줄 수
func _flow_rows(panel: InfoPanel) -> int:
	var ys := {}
	for b in _buttons(panel):
		if str(b.get_meta(InfoPanel.META_REL)) == InfoPanel.REL_CHILD:
			ys[int(b.position.y)] = true
	return maxi(1, ys.size())


## 부모·조부모·자식이 모두 있고 남은 수명이 MIN_LIFE_LEFT 틱 이상인 살아 있는 개체 가운데, 같은 씨앗의 세계를 미리
## 돌려 보아 지켜보는 동안 자식이 늘어나는 개체(자식 단추가 늘어나는 경로를 실제로 겪게). 없으면 조건에 맞는 첫 개체.
func _pick(world: SimWorld) -> int:
	var cands: Array[int] = []
	var fallback := -1
	for i in world.population():
		var id := world.s_id[i]
		var d := world.slime_info(id)
		if int(d.children) < 1:
			continue
		if fallback < 0:
			fallback = id
		if int(d.max_age) - int(d.age) < MIN_LIFE_LEFT or int(d.parent_a) == SimWorld.NO_PARENT:
			continue
		var pd := world.slime_info(int(d.parent_a))
		if int(pd.parent_a) != SimWorld.NO_PARENT:
			cands.append(id)
	if cands.is_empty():
		return fallback
	var ahead := SimWorld.new()
	ahead.setup(world.cfg, world.seed_value)
	ahead.step_n(world.tick)
	var base := {}
	for id in cands:
		base[id] = int(ahead.slime_info(id).children)
	for k in MIN_LIFE_LEFT:
		ahead.step()
		for id in cands:
			if ahead.index_of_id(id) != -1 and int(ahead.slime_info(id).children) > int(base[id]):
				return id
	return cands[0]


func _buttons(panel: InfoPanel) -> Array[Button]:
	var out: Array[Button] = []
	for n in panel.find_children("*", "Button", true, false):
		if n.has_meta(InfoPanel.META_ID) and not n.is_queued_for_deletion():
			out.append(n as Button)
	return out


func _ids(panel: InfoPanel, rel: String) -> Array[int]:
	var out: Array[int] = []
	for b in _buttons(panel):
		if str(b.get_meta(InfoPanel.META_REL)) == rel:
			out.append(int(b.get_meta(InfoPanel.META_ID)))
	return out


func _follow_button(panel: InfoPanel) -> Button:
	for n in panel.find_children("*", "Button", true, false):
		if (n as Button).text == "따라가기":
			return n as Button
	return null


func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


## v0.2 1단계 화면(DESIGN-v0.2 10절): 생애 단계 나이 막대, 먹은 양, 학습 절, 두뇌 탭 타고난 / 배운 / 차이, 학습률 열.
## 학습을 끈 세계는 예전과 같고(탭·학습 절·학습률 열 없음, 그림 = 유전체), 켠 세계는 탭마다 다른 값.
func _stage1(t, panel: InfoPanel, world: SimWorld) -> void:
	# ── 생애 단계 경계 = SimBrain.life_stage 와 같은 판정(나이 0 ~ 수명 모든 값) ──
	var bad: Array[String] = []
	for c in STAGE_CASES:
		var mx: int = c[0]
		var mat: int = c[1]
		var b := InfoPanel.stage_bounds(mx, mat, c[2], c[3])
		for age in mx + 1:
			var want := SimBrain.life_stage(age, mx, mat, c[2], c[3])
			var got := SimBrain.LIFE_JUVENILE
			if age >= b[2]:
				got = SimBrain.LIFE_OLD
			elif age >= b[1]:
				got = SimBrain.LIFE_ADULT
			elif age >= b[0]:
				got = SimBrain.LIFE_YOUNG
			if got != want:
				bad.append("%s 나이 %d: 경계 %s → %d ≠ %d" % [str(c), age, b, got, want])
				break
	t.check(bad.is_empty(), "나이 막대 단계 경계 = SimBrain.life_stage(경우 %d개, 나이 0~수명): %s" % [STAGE_CASES.size(), "; ".join(bad)])
	var tb := InfoPanel.stage_ranges_text(InfoPanel.stage_bounds(200, 30, 0.1, 0.8), 200)
	t.check(tb.contains("어린 0~29") and not tb.contains("젊은") and tb.contains("어른 30~159") and tb.contains("늙은 160~200"),
			"단계 구간 말풍선(젊은 구간이 비면 뺌): " + tb.replace("\n", " / "))
	# ── 학습 끈 세계(기본): 나이 막대·먹은 양은 있고, 학습 절·탭·학습률 열은 없고 그림 = 유전체 ──
	var i0 := 0
	var id0 := world.s_id[i0]
	var d0 := world.slime_info(id0)
	panel.set_brain_mode(BrainView.MODE_DIFF)
	panel.show_slime(world, id0)
	await t.frames(1)
	var bv := panel.brain_view()
	var st0 := world.life_stage_of(i0)
	var cfg: Dictionary = world.cfg
	var b0 := InfoPanel.stage_bounds(int(d0.max_age), int(cfg.repro.maturity), float(cfg.life.adult_frac), float(cfg.life.old_frac))
	var want_ticks := PackedFloat64Array()
	for k in b0:
		if k > 0 and k < int(d0.max_age):
			want_ticks.append(float(k) / float(int(d0.max_age)))
	t.check(panel._v_age.text == "%d / %d틱 · %s" % [int(d0.age), int(d0.max_age), SimBrain.LIFE_STAGE_NAMES[st0]]
			and panel._age_bar.ticks == want_ticks and panel._age_bar.stage == st0
			and is_equal_approx(panel._age_bar.value, float(d0.age)) and is_equal_approx(panel._age_bar.max_value, float(d0.max_age)),
			"나이 막대: \"%s\", 눈금 %s = 단계 경계 ÷ 수명, 단계 %d" % [panel._v_age.text, panel._age_bar.ticks, st0])
	# 눈금은 가운데 글이 차지하는 가로 구간(글 폭 + 테두리 절반 + 여백)에 그리지 않음(1단계 검증 — 1600×900 실제 화면에서 금이 글자에
	# 닿아 '54 /¦209틱' 으로 읽혔음). 가운데(0.5)의 눈금은 빠지고 글 밖 왼쪽 눈금은 그려짐, 실제 개체의 그린 눈금은 모두 글 구간 밖
	var ab := panel._age_bar
	var span := ab.text_span()
	var font := panel._v_age.get_theme_font("font")
	var tw := font.get_string_size(panel._v_age.text, HORIZONTAL_ALIGNMENT_LEFT, -1, panel._v_age.get_theme_font_size("font_size")).x
	var outside := true
	for x in ab.drawn_tick_xs():
		outside = outside and (x + ab.tick_width * 0.5 < span.x or x - ab.tick_width * 0.5 > span.y)
	var keep := ab.ticks.duplicate()
	var left_f := (span.x - 2.0 * ab.tick_width) / ab.size.x
	ab.ticks = PackedFloat64Array([0.5, left_f])
	var mid_drawn := ab.drawn_tick_xs()
	ab.ticks = keep
	t.check(span.y - span.x >= tw and span.x > 0.0 and span.y < ab.size.x and outside and mid_drawn.size() == 1 and mid_drawn[0] < span.x,
			"나이 막대 눈금은 가운데 글 구간 %s(글 폭 %.0f + 테두리·여백, 막대 %.0f) 밖에만: 가운데 눈금은 빠지고 글 밖 눈금 %s 은 그림, 개체의 그린 눈금 %s" % [
			str(span), tw, ab.size.x, str(mid_drawn), str(ab.drawn_tick_xs())])
	var fill := panel._age_bar.get_theme_stylebox("fill") as StyleBoxFlat
	var stage_cols: Array = UiConfig.value("slime.life_stage_colors")
	t.check(fill != null and fill.bg_color.is_equal_approx(Color.from_string(str(stage_cols[st0]), Color.MAGENTA).darkened(InfoPanel.FILL_DARKEN)),
			"나이 막대 채움 = 생애 단계 색(ui.slime.life_stage_colors[%d])" % st0)
	t.check(panel._v_eaten.text == "에너지 %.1f" % world.s_eaten[i0], "먹은 양 = s_eaten: " + panel._v_eaten.text)
	t.check(not panel._sec_learn.visible and not panel.brain_tabs_visible() and not bv.has_learned() and not bv.has_eta()
			and bv.mode() == BrainView.MODE_INNATE, "학습 끈 세계: 학습 절·두뇌 탭·학습률 열 없음, 탭을 차이로 골라 두어도 타고난만")
	var same_off := true
	var L: Dictionary = world.L
	var g0: PackedFloat32Array = d0.genome
	for q in int(L.n_out):
		for j in int(L.n_hid):
			same_off = same_off and bv.weight_of(BrainView.BLOCK_W2, q, j) == float(g0[int(L.w2_offset) + q * int(L.n_hid) + j])
	for j in int(L.n_hid):
		for k in int(L.n_in):
			same_off = same_off and bv.weight_of(BrainView.BLOCK_W1, j, k) == float(g0[j * int(L.n_in) + k])
	t.check(same_off and bv.color_scale() == float(cfg.brain.weight_clamp)
			and bv.custom_minimum_size.is_equal_approx(BrainView.size_for(L, InfoPanel.brain_width()))
			and BrainView.eta_extra(L) == 0.0, "학습 끈 세계: 열지도 칸 = 유전체, 색 상한 = weight_clamp, 크기 그대로(학습률 열 0)")
	# 옛 스냅숏을 연 세계: 그 전에 태어난 개체의 먹은 양은 모름
	t.check(InfoPanel.eaten_text({id = 3, eaten = 0.0}, 5) == InfoPanel.EATEN_UNKNOWN and InfoPanel.eaten_text({id = 5, eaten = 1.5}, 5) == "에너지 1.5",
			"먹은 양: id < eaten_from_id 면 모름")
	# ── 차이 탭 색 상한 ──
	var sc_bad: Array[String] = []
	for c in DIFF_SCALES:
		var got := BrainView.diff_scale_for(c[0])
		if not is_equal_approx(got, c[1]):
			sc_bad.append("%s → %s" % [str(c[0]), str(got)])
	t.check(sc_bad.is_empty(), "차이 탭 색 상한 = 가장 큰 차이 이상의 1·2·5 × 10^k: %s" % ", ".join(sc_bad))
	# ── 학습 켠 세계(learn_basic + 기억 2) ──
	var wl: SimWorld = t.make_world({"brain.memory_units": 2}, LEARN_SEED, "learn_basic")
	if wl == null:
		t.check(false, "학습 세계를 만듦")
		return
	wl.step_n(LEARN_TICKS)
	var li := -1
	var best := 0.0
	for i in wl.population():
		var v := wl.learned_amount_of(i)
		if v > best and int(wl.s_max_age[i]) - int(wl.s_age[i]) > LEARN_WAIT:
			best = v
			li = i
	t.check(li >= 0 and best > 0.0, "배운 두뇌가 타고난 것과 다른 개체를 찾음(배운 양 %.4f)" % best)
	if li < 0:
		return
	var lid := wl.s_id[li]
	var before := WorldCompare.fingerprint(wl)
	panel.set_brain_mode(BrainView.MODE_INNATE)
	panel.show_slime(wl, lid)
	await t.frames(1)
	bv = panel.brain_view()
	var LL: Dictionary = wl.L
	var n_hid := int(LL.n_hid)
	var n_act := int(LL.n_act)
	var dl := wl.slime_info(lid)
	var gl: PackedFloat32Array = dl.genome
	var w2n := n_act * n_hid
	t.check(panel._sec_learn.visible and panel.brain_tabs_visible() and bv.has_learned() and bv.has_eta() and bv.mode() == BrainView.MODE_INNATE,
			"학습 켠 세계: 학습 절·두뇌 탭·학습률 열이 보임")
	t.check(panel._v_eta.text == "평균 %.3f" % float(dl.eta) and panel._v_dw.text == "%.4f" % wl.learned_amount_of(li)
			and panel._v_assim.text == "%.2f" % wl.assim_of(li),
			"학습 절 = slime_info.eta·learned_amount_of·assim_of: %s · %s · %s" % [panel._v_eta.text, panel._v_dw.text, panel._v_assim.text])
	# 탭마다 칸 값: 타고난 = 유전체, 배운 = 행동 행만 s_w2(기억 행·W1 은 유전체), 차이 = 배운 − 타고난(나머지 0)
	var tabs_ok := {}
	var any_diff := false
	for m in [BrainView.MODE_INNATE, BrainView.MODE_LEARNED, BrainView.MODE_DIFF]:
		panel.set_brain_mode(m)
		var ok: bool = bv.mode() == m
		for q in int(LL.n_out):
			for j in n_hid:
				var inn := float(gl[int(LL.w2_offset) + q * n_hid + j])
				var lw := wl.s_w2[li * w2n + q * n_hid + j] if q < n_act else inn
				var want_v := inn
				if m == BrainView.MODE_LEARNED:
					want_v = lw
				elif m == BrainView.MODE_DIFF:
					want_v = lw - inn
				ok = ok and bv.weight_of(BrainView.BLOCK_W2, q, j) == want_v
				if q < n_act and lw != inn:
					any_diff = true
		for j in n_hid:
			for k in int(LL.n_in):
				var w1v := float(gl[j * int(LL.n_in) + k])
				ok = ok and bv.weight_of(BrainView.BLOCK_W1, j, k) == (0.0 if m == BrainView.MODE_DIFF else w1v)
		tabs_ok[BrainView.MODE_NAMES[m]] = ok
	t.check(not tabs_ok.values().has(false) and any_diff,
			"탭 타고난 / 배운 / 차이 칸 값(행동 행만 배운 두뇌, 기억 행·입력층은 타고난, 차이 탭은 그 둘이 0): %s, 다른 칸 있음 %s" % [tabs_ok, any_diff])
	# 차이 탭 색 상한·범례, 배운 탭은 weight_clamp
	var mxd := 0.0
	for q in n_act:
		for j in n_hid:
			mxd = maxf(mxd, absf(wl.s_w2[li * w2n + q * n_hid + j] - float(gl[int(LL.w2_offset) + q * n_hid + j])))
	panel.set_brain_mode(BrainView.MODE_DIFF)
	await t.frames(1)
	var ds := bv.color_scale()
	t.check(ds == BrainView.diff_scale_for(mxd) and ds >= mxd and bv.last_scale == ds and bv.last_legend == BrainView.legend_texts(ds),
			"차이 탭 색 상한 %s ≥ 가장 큰 차이 %.4f, 범례 %s" % [str(ds), mxd, bv.last_legend])
	panel.set_brain_mode(BrainView.MODE_LEARNED)
	await t.frames(1)
	t.check(bv.last_scale == float(wl.cfg.brain.weight_clamp), "배운 탭 색 상한 = weight_clamp")
	# 학습률 열: 값 = 유전체 η, 칸 풍선
	var eta_ok := true
	for q in n_act:
		eta_ok = eta_ok and bv.eta_of(q) == float(gl[int(LL.eta_offset) + q])
	var cell := UiConfig.num("info.heatmap_cell")
	var cw := BrainView.cell_width_for(LL, InfoPanel.brain_width())
	var y2 := UiConfig.num("info.heatmap_header_height") + float(n_hid) * cell + UiConfig.num("info.heatmap_block_gap") + cell
	var ex := UiConfig.num("info.heatmap_label_width") + float(n_hid) * cw + BrainView.eta_extra(LL) - UiConfig.num("info.heatmap_eta_width") * 0.5
	var ce := bv.cell_at(Vector2(ex, y2 + cell * (float(SimBrain.ACT_EAT) + 0.5)))
	t.check(eta_ok and ce.get("block", "") == BrainView.BLOCK_ETA and int(ce.row) == SimBrain.ACT_EAT
			and float(ce.weight) == float(gl[int(LL.eta_offset) + SimBrain.ACT_EAT]) and str(ce.text).contains("학습률"),
			"학습률 열 = 유전체 학습률 유전자(먹기 칸 풍선: %s)" % str(ce.get("text", "")).replace("\n", " / "))
	t.check(bv.custom_minimum_size.x <= InfoPanel.brain_width() + 0.5 and panel.get_combined_minimum_size().x <= UiConfig.num("lab.right_panel_width") + 0.5,
			"학습률 열을 더해도 열지도 %.0f ≤ %.0f, 창 너비 그대로" % [bv.custom_minimum_size.x, InfoPanel.brain_width()])
	# 탭 단추: 누르면 그 탭, 다른 개체로 옮겨도 유지
	var tab_btns: Array[Button] = []
	for n in panel.find_children("*", "Button", true, false):
		if n.has_meta(InfoPanel.META_BRAIN_MODE):
			tab_btns.append(n as Button)
	t.check(tab_btns.size() == 3, "두뇌 탭 단추 3개")
	if tab_btns.size() == 3:
		tab_btns[BrainView.MODE_DIFF].pressed.emit()
		var other := wl.s_id[(li + 1) % wl.population()]
		panel.show_slime(wl, other)
		panel.show_slime(wl, lid)
		t.check(panel.brain_mode() == BrainView.MODE_DIFF and bv.mode() == BrainView.MODE_DIFF and tab_btns[BrainView.MODE_DIFF].button_pressed
				and not tab_btns[BrainView.MODE_INNATE].button_pressed, "탭 단추 '차이' → 차이 탭, 다른 개체로 옮겼다 와도 유지")
	# refresh 가 배운 두뇌를 다시 읽음(배운 두뇌가 바뀔 때까지 진행) — 정보 창은 세계를 바꾸지 않음
	var w0 := wl.s_w2.slice(li * w2n, (li + 1) * w2n)
	var waited := 0
	while waited < LEARN_WAIT and wl.index_of_id(lid) != -1:
		wl.step()
		waited += 1
		var ii := wl.index_of_id(lid)
		if ii >= 0 and wl.s_w2.slice(ii * w2n, (ii + 1) * w2n) != w0:
			break
	var ni := wl.index_of_id(lid)
	panel.refresh()
	var now_w2 := wl.s_w2.slice(ni * w2n, (ni + 1) * w2n) if ni >= 0 else PackedFloat64Array()
	var fresh := ni >= 0 and now_w2 != w0
	for q in n_act:
		for j in n_hid:
			if fresh:
				fresh = bv.weight_of(BrainView.BLOCK_W2, q, j) == now_w2[q * n_hid + j] - float(gl[int(LL.w2_offset) + q * n_hid + j])
	t.check(fresh and panel._v_dw.text == "%.4f" % wl.learned_amount_of(ni),
			"%d틱 뒤 배운 두뇌가 바뀌면 refresh 가 차이 탭·배운 양을 다시 읽음" % waited)
	var ref: SimWorld = t.make_world({"brain.memory_units": 2}, LEARN_SEED, "learn_basic")
	ref.step_n(wl.tick)
	t.check(WorldCompare.same(wl, ref) == "", "정보 창(학습 절·탭)을 거쳐도 학습 세계 상태(배운 두뇌·고리 포함)가 헤드리스와 같음 %s" % WorldCompare.same(wl, ref))
	before = WorldCompare.fingerprint(wl)
	for m in 3:
		panel.set_brain_mode(m)
		panel.refresh()
	t.check(WorldCompare.diff(before, wl) == "", "탭을 바꾸고 refresh 해도 세계 그대로")
	# 지켜보다 죽으면 마지막 배운 두뇌·탭을 남김
	var guard := 0
	while wl.index_of_id(lid) != -1 and guard < DEATH_GUARD:
		wl.step()
		guard += 1
	panel.refresh()
	t.check(wl.index_of_id(lid) == -1 and panel.brain_tabs_visible() and bv.has_learned() and UiTheme.plain_text(panel._brain_note.text).contains("죽기 직전"),
			"지켜보던 학습 개체가 죽으면 마지막 배운 두뇌와 탭이 남음(죽음 %s, 탭 %s, 배운 두뇌 %s, 안내 \"%s\")" % [
				wl.index_of_id(lid) == -1, panel.brain_tabs_visible(), bv.has_learned(), UiTheme.plain_text(panel._brain_note.text)])
	t.check(panel._v_eaten_dead.text == "에너지 %.1f" % float(wl.slime_info(lid).eaten), "죽은 개체의 먹은 양 = 평생: " + panel._v_eaten_dead.text)
	# 기록만 남은 학습 개체: 두뇌·탭 없음, 학습률 평균은 계통 기록, 배운 양은 모름
	panel.show_slime(wl, lid)
	t.check(not panel.brain_tabs_visible() and panel._sec_learn.visible and panel._v_eta.text == "평균 %.3f" % float(wl.slime_info(lid).eta)
			and panel._v_dw.text == InfoPanel.UNKNOWN_TEXT, "기록만 남은 학습 개체: 탭 없음, 학습률 = 계통 기록, 배운 양 모름")
	panel.set_brain_mode(BrainView.MODE_INNATE)
