extends SceneTree
## 정보 창 캡처(가상 디스플레이, 픽셀 확인용):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/info_capture.gd -- --out=폴더
## 기본 예설정 세계를 TICKS 틱 진행한 뒤 정보 창 하나만(원래 너비, 테마 배경 위) 띄워 찍는다.
##   info-alive.png  부모·조부모·자식이 있는 살아 있는 개체(따라가기 켬)
##   info-dead.png   지켜보던 중 죽은 개체(refresh 가 죽음을 감지, 마지막 두뇌 유지)
## --extra 를 주면 참고용도 찍는다: info-alive-720.png(1280×720 높이, 스크롤), info-record.png(기록만 남은
##   죽은 조상, 두뇌 없음), info-memory.png(기억 뉴런 2개 세계), info-empty.png(빈 안내)
## 인자: --out=폴더(기본 res://docs/screenshots/v0.1), --seed=N, --ticks=N, --extra

const TICKS := 1500
const SEED := 1
## 창 둘레에 남길 배경 폭(픽셀)
const MARGIN := 16
## 1280×720 화면에서 정보 창 높이(위 막대 몫을 뺀 근사)
const SHORT_HEIGHT := 720

var _out := "res://docs/screenshots/v0.1"
var _seed := SEED
var _ticks := TICKS
var _extra := false


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--seed="):
			_seed = int(a.substr(7))
		elif a.begins_with("--ticks="):
			_ticks = int(a.substr(8))
		elif a == "--extra":
			_extra = true
	DirAccess.make_dir_recursive_absolute(_out)
	var b := SimConfig.build("default", {})
	var world := SimWorld.new()
	world.setup(b.config, _seed)
	world.step_n(_ticks)
	var id := _pick(world)
	print("고른 개체 #%d (틱 %d, 개체 수 %d)" % [id, world.tick, world.population()])
	var bg := ColorRect.new()
	bg.color = UiConfig.color("theme.background")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var panel := InfoPanel.new()
	var pw := UiConfig.num("lab.right_panel_width")
	var full_h := float(root.size.y)
	panel.position = Vector2(MARGIN, 0)
	panel.size = Vector2(pw, full_h)
	root.add_child(panel)
	# ① 살아 있는 개체
	panel.show_slime(world, id)
	panel.set_follow(true)
	await _frames(4)
	_shot(panel, "info-alive.png")
	# ② 1280×720 높이(스크롤이 생기는지)
	if _extra:
		panel.size = Vector2(pw, SHORT_HEIGHT)
		await _frames(4)
		_shot(panel, "info-alive-720.png")
		panel.size = Vector2(pw, full_h)
	# ③ 지켜보던 개체가 죽을 때까지 진행(refresh 가 죽음을 감지)
	var guard := 0
	while world.index_of_id(id) != -1 and guard < 2000:
		world.step()
		guard += 1
		if guard % UiConfig.integer("info.refresh_frames") == 0:
			panel.refresh()
	panel.refresh()
	await _frames(4)
	print("#%d 죽음 감지: %s" % [id, panel.summary_text()])
	_shot(panel, "info-dead.png")
	if not _extra:
		quit(0)
		return
	# ④ 기록만 남은 조상(두뇌 없음)
	var d := world.slime_info(id)
	var anc := int(d.parent_a)
	if anc != SimWorld.NO_PARENT:
		panel.show_slime(world, anc)
		await _frames(4)
		_shot(panel, "info-record.png")
	# ⑤ 기억 뉴런 2개 세계
	var bm := SimConfig.build("default", {"brain.memory_units": 2})
	var wm := SimWorld.new()
	wm.setup(bm.config, _seed)
	wm.step_n(300)
	panel.show_slime(wm, _pick(wm))
	await _frames(4)
	_shot(panel, "info-memory.png")
	# ⑥ 빈 안내
	panel.clear()
	await _frames(4)
	_shot(panel, "info-empty.png")
	quit(0)


## 부모·조부모가 있고 자식이 많은(한 줄 넘게) 살아 있는 개체. 에너지가 중간쯤이면 더 좋다.
func _pick(world: SimWorld) -> int:
	var best := -1
	var best_score := -1.0
	for i in world.population():
		var id := world.s_id[i]
		var d := world.slime_info(id)
		var score := float(int(d.children))
		if int(d.parent_a) != SimWorld.NO_PARENT:
			score += 100.0
			var pd := world.slime_info(int(d.parent_a))
			if int(pd.parent_a) != SimWorld.NO_PARENT:
				score += 100.0
		if int(d.parent_b) != SimWorld.NO_PARENT:
			score += 20.0
		score += 5.0 * (1.0 - absf(float(d.energy) / float(d.energy_max) - 0.6))
		if score > best_score:
			best_score = score
			best = id
	return best


func _shot(panel: Control, name: String) -> void:
	var img := root.get_texture().get_image()
	var r := Rect2i(0, 0, int(panel.size.x) + MARGIN * 2, int(panel.size.y))
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(r)
	var path := _out.path_join(name)
	var err := crop.save_png(path)
	print("저장 %s (%dx%d) %s" % [path, crop.get_width(), crop.get_height(), "" if err == OK else "실패 %d" % err])
