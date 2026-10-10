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
const MIN_CHECKS := 56
## 1600×900 실험실에서 정보 창 높이(창 높이 − 위쪽 막대 최소 높이) — V07
const LAB_HEIGHT_1600 := 900.0
## V07 을 재 볼 개체 수 한도
const V07_SAMPLES := 60


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
	panel.queue_free()
	await t.frames(1)


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
