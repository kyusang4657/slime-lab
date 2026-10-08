extends SceneTree
## 타임랩스 프레임 찍기(README·포트폴리오 영상용): 실험실 전체를 띄워 fast_civ·씨앗 5 를 진행하며 프레임마다 PNG 를 남긴다.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tests/timelapse_capture.gd -- --out=폴더
##   ffmpeg 로 묶기: tools/make_timelapse.sh 폴더 (mp4 + gif)
## 인자: --out=폴더(필수), --seed=N(5), --ticks=N(1800). 32배(1/30초 프레임마다 약 6.4틱)로 진행.
## 영상 뒤쪽 1/3 은 저장고 근처 개체를 골라 따라가며 가까이 본다.

var _out := ""
var _seed := 5
var _ticks := 1800
const MAX_DIST := 8
var _last := Vector2i(-1, -1)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--seed="):
			_seed = a.substr(7).to_int()
		elif a.begins_with("--ticks="):
			_ticks = a.substr(8).to_int()
	_run.call_deferred()


func _run() -> void:
	if _out == "":
		printerr("--out=폴더 가 필요합니다")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	root.add_child(lab)
	for i in 3:
		await process_frame
	lab.set_process(false)
	var err := lab.new_experiment("fast_civ", {}, _seed)
	if err != "":
		printerr(err)
		quit(1)
		return
	# 32배로 실제 진행(1/30초 프레임마다 약 6.4틱). 캡처는 느려도 결과가 같게 프레임 예산을 끈다(검사 도구라서 내부 값을 직접 씀).
	lab._budget_ms = 1.0e9
	lab.set_paused(false)
	lab.set_speed(32)
	var frames := int(float(_ticks) / (UiConfig.num("speed.ticks_per_second_1x") * 32.0 / 30.0))
	var zoomed := false
	for f in frames:
		if not zoomed and f >= frames * 2 / 3:
			zoomed = true
			_follow_near_store(lab, -1, -1)
		elif zoomed and lab.world.index_of_id(lab.selected_id()) == -1:
			# 따라가던 개체가 죽으면(수명 약 200틱 < 영상 뒷부분) 마지막으로 본 자리 가까이의 다른 개체로 넘긴다
			_follow_near_store(lab, _last.x, _last.y)
		var si := lab.world.index_of_id(lab.selected_id())
		if si >= 0:
			_last = Vector2i(lab.world.s_x[si], lab.world.s_y[si])
		lab.advance_frame(1.0 / 30.0)
		await process_frame
		var img := root.get_texture().get_image()
		img.save_png(_out.path_join("f%05d.png" % f))
	print("timelapse: %d프레임, 틱 %d, 문명 %s" % [frames, lab.world.tick, SimWorld.STAGE_NAMES[lab.world.stage]])
	quit(0)


## 저장고(없으면 지도 가운데) 가까이(맨해튼 거리 MAX_DIST 안) 개체 가운데 남은 수명이 가장 긴 개체를 골라 따라간다(영상 끝까지 살아 있게).
## near_x·near_y 가 0 이상이면 그 칸(죽은 개체를 마지막으로 본 자리) 가까이에서 고른다.
func _follow_near_store(lab: LabMain, near_x: int, near_y: int) -> void:
	var w := lab.world
	if w.population() == 0:
		return
	var cx := w.w / 2
	var cy := w.h / 2
	if near_x >= 0 and near_y >= 0:
		cx = near_x
		cy = near_y
	elif not w.store_tiles.is_empty():
		cx = w.store_tiles[0] % w.w
		cy = w.store_tiles[0] / w.w
	var best := -1
	for i in w.population():
		var d := absi(w.s_x[i] - cx) + absi(w.s_y[i] - cy)
		if d <= MAX_DIST and (best == -1 or _life_left(w, i) > _life_left(w, best)):
			best = i
	if best == -1:
		best = 0
	var id := w.s_id[best]
	lab.select_slime(id, 0)
	lab.map_view.focus_on(id)
	lab.map_view.follow_selected = true


static func _life_left(w: SimWorld, i: int) -> int:
	var info := w.slime_info(w.s_id[i])
	return int(info.max_age) - int(info.age)
