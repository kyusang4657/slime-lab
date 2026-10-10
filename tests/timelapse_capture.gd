extends SceneTree
## 타임랩스 프레임 찍기(README·포트폴리오 영상용): 실험실 전체를 띄워 fast_civ·씨앗 2 를 진행하며 프레임마다 PNG 를 남긴다.
## 씨앗 2 는 1,800틱 안에 채집 374 → 저장 422 → 농사 812틱, 첫 밭 869틱, 1,200틱부터 개체가 상한(250) 근처, 끝에 밭 101칸
## (규칙 고침 g1b 뒤 다시 고름 — 전에 쓴 씨앗 5 는 1,500틱 무렵 개체가 46까지 줄고 끝에 밭 18칸).
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tests/timelapse_capture.gd -- --out=폴더
##   ffmpeg 로 묶기: tools/make_timelapse.sh 폴더 (webm·mp4·gif·포스터 jpg)
## 인자: --out=폴더(필수), --seed=N(2), --ticks=N(1800). 32배(1/30초 프레임마다 약 6.4틱)로 진행.
## 영상 뒤쪽 1/3 은 둘레에 밭이 가장 많은 저장고 근처 개체를 골라 따라가며 가까이 본다(죽으면 같은 저장고 근처의 다른 개체).

var _out := ""
var _seed := 2
var _ticks := 1800
const MAX_DIST := 8
## 영상 뒷부분에서 따라갈 개체를 고르는 자리(처음 고를 때 정한 저장고 칸)
var _anchor := Vector2i(-1, -1)


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
			# 따라가던 개체가 죽으면(수명 약 200틱 < 영상 뒷부분) 처음 고른 저장고 가까이의 다른 개체로 넘긴다
			# (죽은 자리 가까이로 넘기면 개체를 따라 밭에서 멀어져 영상 끝이 지도 가장자리의 빈 땅이 됨)
			_follow_near_store(lab, _anchor.x, _anchor.y)
		lab.advance_frame(1.0 / 30.0)
		await process_frame
		var img := root.get_texture().get_image()
		img.save_png(_out.path_join("f%05d.png" % f))
	print("timelapse: %d프레임, 틱 %d, 문명 %s" % [frames, lab.world.tick, SimWorld.STAGE_NAMES[lab.world.stage]])
	quit(0)


## 저장고(없으면 지도 가운데) 가까이(맨해튼 거리 MAX_DIST 안) 개체 가운데 남은 수명이 가장 긴 개체를 골라 따라간다(영상 끝까지 살아 있게).
## 저장고는 둘레(MAX_DIST 안)에 밭이 가장 많은 것(같으면 먼저 지은 것 — 씨앗 2 의 저장고 1호는 밭 없는 지도 모서리 (3, 2)).
## near_x·near_y 가 0 이상이면 그 칸(처음 고른 저장고 _anchor) 가까이에서 고르고, 아니면 고른 저장고를 _anchor 로 기억한다.
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
		var store := _store_with_most_farms(w)
		cx = store % w.w
		cy = store / w.w
	if near_x < 0 or near_y < 0:
		_anchor = Vector2i(cx, cy)
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


## 둘레(맨해튼 거리 MAX_DIST 안)에 밭이 가장 많은 저장고의 칸 번호(같으면 먼저 지은 것).
static func _store_with_most_farms(w: SimWorld) -> int:
	var best := w.store_tiles[0]
	var best_n := -1
	for c in w.store_tiles:
		var n := 0
		for f in w.farms:
			if absi(f % w.w - c % w.w) + absi(f / w.w - c / w.w) <= MAX_DIST:
				n += 1
		if n > best_n:
			best = c
			best_n = n
	return best


static func _life_left(w: SimWorld, i: int) -> int:
	var info := w.slime_info(w.s_id[i])
	return int(info.max_age) - int(info.age)
