extends SceneTree
## 지도 관찰 창 캡처(가상 디스플레이에서):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/map_capture.gd -- --out=폴더
## 예설정 demo_fast·씨앗 1 을 농사 단계(약 1,700틱)까지 돌린 뒤 MapView 를 1600×900 SubViewport 에 띄워
## 전경(map-overview)·저장고 부근 가까이(map-closeup)·밤(map-night)을 JPG(품질 0.85)로 찍는다.
## 선택 인자: --ticks=N(시작 틱, 기본 1764), --size=WxH

const SIZE_LIMIT := 500 * 1024
const JPG_QUALITY := 0.85
## 진행 틱 수(낮 한가운데·밭이 몇 칸 생긴 때).
const DEFAULT_TICKS := 1764
## 찍기 전에 화면을 거쳐 진행할 틱(보간 기억이 생기게).
const WARM_TICKS := 4
## 가까이 장면의 카메라.
const CLOSE_DISTANCE := 13.0
const CLOSE_PITCH_DEG := 48.0
const CLOSE_YAW_DEG := 24.0
## 밤 장면의 카메라(조금 기울여 전경보다 가까이).
const NIGHT_DISTANCE := 38.0
const NIGHT_PITCH_DEG := 50.0
const NIGHT_YAW_DEG := -18.0

var _out := "res://docs/screenshots/v0.1"
var _sv: SubViewport
var _mv: MapView
var _world: SimWorld


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ticks := DEFAULT_TICKS
	var size := Vector2i(1600, 900)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--ticks="):
			ticks = int(a.substr(8))
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			size = Vector2i(int(p[0]), int(p[1]))
	DirAccess.make_dir_recursive_absolute(_abs(_out))
	_sv = SubViewport.new()
	_sv.size = size
	_sv.own_world_3d = true
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_sv)
	_mv = MapView.new()
	_sv.add_child(_mv)

	var b := SimConfig.build("demo_fast", {})
	_world = SimWorld.new()
	_world.setup(b.config, 1)
	var t0 := Time.get_ticks_msec()
	_world.step_n(ticks - WARM_TICKS)
	print("진행 %d틱 %.1f초: 인구 %d, 단계 %d, 저장고 %d, 밭 %d, 빛 %.2f" % [_world.tick, float(Time.get_ticks_msec() - t0) / 1000.0,
		_world.population(), _world.stage, _world.store_tiles.size(), _world.farms.size(), _world.light])
	_mv.bind(_world)
	_advance(WARM_TICKS, 0.5)
	await _frames(3)
	print("통계: ", _mv.view_stats())
	await _save("map-overview")

	# 가까이: 첫 저장고 부근, 운반 중인 개체 하나 고르기
	if _world.store_tiles.size() > 0:
		var c: int = _world.store_tiles[0]
		var cam: Camera3D = _mv.get_camera()
		cam.set("target", Vector3((float(c % _world.w) + 0.5), 0.0, (float(c / _world.w) + 0.5) + 1.0))
		cam.set("distance", CLOSE_DISTANCE)
		cam.set("pitch", deg_to_rad(CLOSE_PITCH_DEG))
		cam.set("yaw", deg_to_rad(CLOSE_YAW_DEG))
		cam.call("apply")
		var best := -1
		var best_d := INF
		for i in _world.population():
			var d := Vector2(_world.s_x[i] - c % _world.w, _world.s_y[i] - c / _world.w).length()
			if d < best_d and _world.s_carry[i] > 0.0:
				best_d = d
				best = _world.s_id[i]
		_mv.set_selected(best)
	_advance(1, 0.45)
	await _frames(3)
	await _save("map-closeup")

	# 밤: 빛이 0 이 될 때까지 화면을 거쳐 진행
	_mv.set_selected(-1)
	var guard := 0
	while _world.light > 0.0 and guard < 200:
		_advance(1, 1.0)
		guard += 1
	_advance(6, 0.5)
	var cam2: Camera3D = _mv.get_camera()
	cam2.set("distance", NIGHT_DISTANCE)
	cam2.set("pitch", deg_to_rad(NIGHT_PITCH_DEG))
	cam2.set("yaw", deg_to_rad(NIGHT_YAW_DEG))
	cam2.set("target", Vector3(float(_world.w) * 0.5, 0.0, float(_world.h) * 0.5))
	cam2.call("apply")
	_mv.update_view(0.5)
	await _frames(3)
	print("밤 틱 %d 빛 %.2f" % [_world.tick, _world.light])
	await _save("map-night")
	quit(0)


## 화면을 거쳐 n 틱 진행(LabMain 과 같은 순서).
func _advance(n: int, alpha: float) -> void:
	for k in n:
		_mv.before_steps()
		_world.step()
		_mv.update_view(alpha)


func _frames(n: int) -> void:
	for k in n:
		await process_frame
	await RenderingServer.frame_post_draw


## 3D 장면이라 JPG 로 저장한다(PNG 의 절반 아래 크기, 글자가 없어 손실이 눈에 띄지 않음).
func _save(name: String) -> void:
	var img := _sv.get_texture().get_image()
	var path := _abs(_out).path_join(name + ".jpg")
	img.save_jpg(path, JPG_QUALITY)
	var sz := FileAccess.get_file_as_bytes(path).size()
	print("저장: %s (%d KB)%s" % [path, sz / 1024, "" if sz <= SIZE_LIMIT else " — 크기 한도 초과"])


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p
