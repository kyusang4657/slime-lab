extends SceneTree
## 절차적 메시 모음 캡처(가상 디스플레이에서 그림을 찍는다. 헤드리스에서는 화면이 없어 못 찍음):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/geo_capture.gd -- --out=폴더
## 네 칸을 한 장(1600×900)으로 모아 <폴더>/geo-lineup.png 로 저장한다(기본 폴더 res://docs/screenshots/v0.1).
##   ① 계통 색 6가지(크기 1.0, 정면)  ② 크기 0.6·1.0·1.6 × 정면·3/4·옆(직교 투영이라 크기를 그대로 비교)
##   ③ 풀포기·열매·저장고·밭·선택 고리·운반  ④ 지도 배율(게임 카메라 각도·거리, 가운데를 1:1 픽셀로 잘라 실제로 보이는 크기)
## 선택: --panels(칸마다 따로도 저장), --closeup(슬라임 세 마리를 크게 찍은 확인용 그림 두 장만).
## 슬라임은 지도처럼 메시 하나를 MultiMesh 로 그리고 인스턴스 색(계통 색)을 곱한다.

const W := 1600
const H := 900
const HALF_W := 800
const HALF_H := 450
const HUES: Array[float] = [0.0, 0.08, 0.15, 0.33, 0.55, 0.76]
const SIZES: Array[float] = [0.6, 1.0, 1.6]
## 무대(칸)마다 세계 좌표를 멀리 떨어뜨려 서로 비치지 않게
const STAGE_GAP := 60.0
## 지도 배율 칸의 카메라 거리(슬라임 크기 1 이 약 30 픽셀)
const MAP_DISTANCE := 22.0
## 캡처 조명(지도 창의 낮 조명과 비슷하게, 바탕이 하얗게 날지 않도록)
const SUN := 0.95
const AMBIENT := 0.35
const GROUND := Color("858278")
const GRASS := Color("4f8d3d")
const SKY := Color("c9d3dc")
const INK := Color("15181d")
const LSB_MASK := 0xFE

var _out := "res://docs/screenshots/v0.1"
var _panels := false
var _closeup := false
var _cam: Camera3D
var _label: Label


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--panels":
			_panels = true
		elif a == "--closeup":
			_closeup = true
	DirAccess.make_dir_recursive_absolute(_abs(_out))
	root.size = Vector2i(W, H)
	_setup_world()
	if _closeup:
		await _closeup_shots()
		quit(0)
		return
	var shots: Array[Image] = []
	shots.append(await _panel_hues())
	shots.append(await _panel_sizes())
	shots.append(await _panel_props())
	shots.append(await _panel_map())
	# 한 장으로 모으기(칸 사이 2 픽셀 선)
	var sheet := Image.create(W, H, false, Image.FORMAT_RGB8)
	sheet.fill(INK)
	for i in shots.size():
		var at := Vector2i((i % 2) * HALF_W, (i >> 1) * HALF_H)
		sheet.blit_rect(shots[i], Rect2i(0, 0, HALF_W, HALF_H), at)
	sheet.fill_rect(Rect2i(HALF_W - 1, 0, 2, H), INK)
	sheet.fill_rect(Rect2i(0, HALF_H - 1, W, 2), INK)
	# 저장소에 넣는 그림이라 400 KB 아래로: 채널마다 최하위 비트를 버린다(7비트, 눈으로는 구별되지 않음)
	var px := sheet.get_data()
	for i in px.size():
		px[i] = px[i] & LSB_MASK
	sheet.set_data(W, H, false, Image.FORMAT_RGB8, px)
	var path := _abs(_out).path_join("geo-lineup.png")
	var err := sheet.save_png(path)
	print("저장: %s (%s)" % [path, "성공" if err == OK else "실패 %d" % err])
	if _panels:
		for i in shots.size():
			shots[i].save_png(_abs(_out).path_join("geo-panel-%d.png" % (i + 1)))
	print("RESULT: geo capture %s" % ("ok" if err == OK else "failed"))
	quit(0 if err == OK else 1)


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p


# ---------------------------------------------------------------- 칸

## ① 계통 색 6가지, 크기 1.0, 정면(카메라가 -Z 쪽에서 봄)
func _panel_hues() -> Image:
	var s := _stage(0, GROUND)
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for i in HUES.size():
		xf.append(_slime_xf(Vector3((2.5 - float(i)) * 0.74, 0.0, 0.0), 1.0, 0.0))
		cols.append(_hue(HUES[i]))
	_slimes(s, xf, cols)
	return await _shoot(s, Vector3(0.0, 0.95, -3.3), Vector3(0.0, 0.18, 0.0), "계통 색 6가지 · 크기 1.0 · 정면", 1)


## ② 크기(왼→오 0.6·1.0·1.6) × 보는 방향(앞줄 정면, 가운데 3/4, 뒷줄 옆). 직교 투영.
func _panel_sizes() -> Image:
	var s := _stage(1, GROUND)
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var yaws: Array[float] = [0.0, PI * 0.25, PI * 0.5]
	var xs: Array[float] = [1.75, 0.15, -1.85]
	for r in yaws.size():
		for k in SIZES.size():
			xf.append(_slime_xf(Vector3(xs[k], 0.0, float(r) * 2.2), SIZES[k], yaws[r]))
			cols.append(_hue(HUES[(r * 2 + k + 1) % HUES.size()]))
	_slimes(s, xf, cols)
	return await _shoot(s, Vector3(0.0, 2.2, -5.5), Vector3(0.0, 0.0, 2.2), "크기 0.6 · 1.0 · 1.6  ×  정면 · 3/4 · 옆(직교)", 1, 3.6)


## ③ 풀포기(배율 4가지)·열매·저장고·밭·선택 고리·머리 위 운반
func _panel_props() -> Image:
	var s := _stage(2, GROUND)
	_prop(s, SlimeGeo.storehouse_mesh(), Vector3(1.15, 0.0, 0.55), 1.0, 0.25)
	_prop(s, SlimeGeo.farm_mesh(), Vector3(0.0, 0.0, 0.6), 1.0, 0.0)
	_prop(s, SlimeGeo.farm_mesh(), Vector3(-1.0, 0.0, 0.6), 1.0, 0.0)
	var plant_scales: Array[float] = [0.55, 0.42, 0.3, 0.16]
	for k in plant_scales.size():
		_prop(s, SlimeGeo.plant_mesh(), Vector3(1.6 - float(k) * 0.4, 0.0, -0.45), plant_scales[k], float(k) * 1.3)
	_prop(s, SlimeGeo.berry_mesh(), Vector3(0.05, 0.0, -0.8), 0.18, 0.0)
	_prop(s, SlimeGeo.berry_mesh(), Vector3(-0.2, 0.0, -0.62), 0.18, 1.0)
	var xf: Array[Transform3D] = [_slime_xf(Vector3(-0.65, 0.0, -0.5), 1.0, -0.35), _slime_xf(Vector3(-1.45, 0.0, -0.3), 1.3, 0.45)]
	var cols: Array[Color] = [_hue(0.55), _hue(0.08)]
	_slimes(s, xf, cols)
	# 머리 위에 열매를 나르는 슬라임(크기 1.3), 선택 고리를 두른 슬라임(크기 1.0)
	var head := SlimeGeo.slime_mesh().get_aabb().end.y * 1.3
	_prop(s, SlimeGeo.berry_mesh(), Vector3(-1.45, head - 0.01, -0.3), 0.2, 0.5)
	var ring := _prop(s, SlimeGeo.ring_mesh(), Vector3(-0.65, 0.0, -0.5), UiConfig.num("slime.radius") * 1.45, 0.0)
	ring.material_override = _ring_material()
	return await _shoot(s, Vector3(0.0, 1.9, -2.85), Vector3(0.0, 0.12, 0.08), "풀포기(배율 4가지) · 열매 · 저장고 · 밭 · 선택 고리 · 운반", 1)


## ④ 지도 배율: 게임 카메라 각도(ui.camera.pitch_deg)와 거리 MAP_DISTANCE, 가운데를 1:1 로 잘라냄
func _panel_map() -> Image:
	var s := _stage(3, GRASS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	# 저장고·밭 칸(z = 1.5, x = -0.5 ~ 2.5)은 비워 둔다
	var used := {Vector2i(2, 1): true, Vector2i(1, 1): true, Vector2i(0, 1): true, Vector2i(-1, 1): true}
	for i in 22:
		var cell := Vector2i(rng.randi_range(-7, 6), rng.randi_range(-4, 3))
		while used.has(cell):
			cell = Vector2i(rng.randi_range(-7, 6), rng.randi_range(-4, 3))
		used[cell] = true
		var at := Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)
		var size := SIZES[i % SIZES.size()] if i < 9 else rng.randf_range(0.6, 1.6)
		xfs.append(_slime_xf(at, size, rng.randf_range(-PI, PI) * 0.6))
		cols.append(_hue(HUES[i % HUES.size()]))
	_slimes(s, xfs, cols)
	for i in 30:
		var cell := Vector2i(rng.randi_range(-8, 7), rng.randi_range(-5, 4))
		if used.has(cell):
			continue
		used[cell] = true
		var at := Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)
		_prop(s, SlimeGeo.plant_mesh(), at, rng.randf_range(UiConfig.num("map.plant_min_scale"), UiConfig.num("map.plant_max_scale")), rng.randf() * TAU)
	_prop(s, SlimeGeo.storehouse_mesh(), Vector3(2.5, 0.0, 1.5), 1.0, 0.0)
	for k in 3:
		_prop(s, SlimeGeo.farm_mesh(), Vector3(1.5 - float(k), 0.0, 1.5), 1.0, 0.0)
	_prop(s, SlimeGeo.berry_mesh(), Vector3(-1.3, 0.0, -0.7), 0.2, 0.0)
	var first := xfs[0]
	var ring := _prop(s, SlimeGeo.ring_mesh(), first.origin, UiConfig.num("slime.radius") * 1.45 * first.basis.get_scale().x, 0.0)
	ring.material_override = _ring_material()
	var pitch := deg_to_rad(UiConfig.num("camera.pitch_deg"))
	var eye := Vector3(0.0, sin(pitch), -cos(pitch)) * MAP_DISTANCE
	return await _shoot(s, eye, Vector3.ZERO, "지도 배율 · 카메라 거리 %d · 1:1 픽셀(크기 1 ≈ 30px)" % int(MAP_DISTANCE), 0)


## 확인용(--closeup): 슬라임 세 마리(정면·3/4·옆)를 크게, 앞에서 한 장·위(지도 각도)에서 한 장
func _closeup_shots() -> void:
	var s := _stage(5, GROUND)
	var xf: Array[Transform3D] = [_slime_xf(Vector3(0.75, 0.0, 0.0), 1.0, 0.0), _slime_xf(Vector3(0.0, 0.0, 0.0), 1.0, PI * 0.25), _slime_xf(Vector3(-0.75, 0.0, 0.0), 1.0, PI * 0.5)]
	var cols: Array[Color] = [_hue(0.55), _hue(0.33), _hue(0.0)]
	_slimes(s, xf, cols)
	var img := await _shoot(s, Vector3(0.0, 0.75, -1.9), Vector3(0.0, 0.2, 0.0), "", 2)
	img.save_png(_abs(_out).path_join("geo-closeup.png"))
	var pitch := deg_to_rad(UiConfig.num("camera.pitch_deg"))
	var top := await _shoot(s, Vector3(0.0, sin(pitch), -cos(pitch)) * 2.6, Vector3(0.0, 0.1, 0.0), "", 2)
	top.save_png(_abs(_out).path_join("geo-closeup-top.png"))


# ---------------------------------------------------------------- 무대 꾸리기

## 빛·환경·카메라·글자(칸 제목)
func _setup_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dfe8f0")
	env.ambient_light_energy = AMBIENT
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = SUN
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-140.0), 0.0)
	root.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = UiConfig.num("camera.fov_deg")
	root.add_child(_cam)
	_cam.make_current()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_label = Label.new()
	_label.add_theme_color_override("font_color", INK)
	layer.add_child(_label)


func _stage(i: int, ground: Color) -> Node3D:
	var s := Node3D.new()
	s.position = Vector3(float(i) * STAGE_GAP, 0.0, 0.0)
	root.add_child(s)
	var pm := PlaneMesh.new()
	pm.size = Vector2(STAGE_GAP, STAGE_GAP)
	var m := StandardMaterial3D.new()
	m.albedo_color = ground
	m.roughness = 1.0
	m.metallic_specular = 0.0
	pm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	s.add_child(mi)
	return s


## 슬라임 변환: 바닥 위치, 크기(균일 배율), 몸 돌림(0 = 정면 -Z, 양수 = 위에서 보아 시계 반대)
static func _slime_xf(at: Vector3, size: float, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at)


static func _hue(h: float) -> Color:
	return Color.from_hsv(h, UiConfig.num("slime.saturation"), UiConfig.num("slime.value"))


## 지도와 같은 방식: 슬라임 메시 하나를 MultiMesh 로, 인스턴스 색 = 계통 색
func _slimes(stage: Node3D, xfs: Array[Transform3D], cols: Array[Color]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = SlimeGeo.slime_mesh()
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = SlimeGeo.slime_material()
	stage.add_child(mmi)


func _prop(stage: Node3D, mesh: Mesh, at: Vector3, sc: float, yaw: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), at)
	stage.add_child(mi)
	return mi


func _ring_material() -> Material:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = UiConfig.color("slime.selected_ring_color")
	return m


## 카메라를 무대 기준 eye 에 두고 target 을 보며 찍는다. ortho > 0 이면 직교 투영(세로 크기).
## mode 1 = 전체를 반으로 줄임(매끈하게), 0 = 가운데를 1:1 로 잘라냄, 2 = 전체 그대로.
func _shoot(stage: Node3D, eye: Vector3, target: Vector3, title: String, mode: int, ortho: float = 0.0) -> Image:
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL if ortho > 0.0 else Camera3D.PROJECTION_PERSPECTIVE
	if ortho > 0.0:
		_cam.size = ortho
	_cam.position = stage.position + eye
	_cam.look_at(stage.position + target, Vector3.UP)
	_label.text = title
	_label.add_theme_font_size_override("font_size", 34 if mode == 1 else 17)
	_label.position = Vector2(24, 16) if mode == 1 else Vector2(W / 4.0 + 12.0, H / 4.0 + 8.0)
	for k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	if mode == 2:
		return img
	if mode == 1:
		img.resize(HALF_W, HALF_H, Image.INTERPOLATE_LANCZOS)
		return img
	return img.get_region(Rect2i(HALF_W >> 1, HALF_H >> 1, HALF_W, HALF_H))
