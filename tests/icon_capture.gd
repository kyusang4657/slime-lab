extends SceneTree
## 앱 아이콘 만들기(외부 이미지 없음): SlimeGeo 슬라임을 투명 바탕에 렌더링해 assets/icon.png(256×256)로 저장.
## xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 512x512 --script res://tests/icon_capture.gd
## 결과 그림은 저장소에 넣고 project.godot 의 application/config/icon 이 가리킨다(웹 내보내기의 파비콘도 이것).

const SIZE := 256
const HUE := 0.47
const OUT := "res://assets/icon.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.55
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var mm := MeshInstance3D.new()
	mm.mesh = SlimeGeo.slime_mesh()
	mm.material_override = SlimeGeo.slime_material()
	var col := Color.from_hsv(HUE, UiConfig.num("slime.saturation"), UiConfig.num("slime.value"))
	# MultiMesh 인스턴스 색 대신 재질 알베도로 계통 색을 곱한다(아이콘 하나뿐)
	var mat: StandardMaterial3D = (SlimeGeo.slime_material() as StandardMaterial3D).duplicate()
	mat.albedo_color = col
	mm.material_override = mat
	vp.add_child(mm)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var aabb := mm.mesh.get_aabb()
	cam.size = maxf(aabb.size.x, aabb.size.y) * 1.25
	vp.add_child(cam)
	var c := aabb.get_center()
	cam.look_at_from_position(c + Vector3(0.0, aabb.size.y * 0.35, -2.0), c, Vector3.UP)
	for i in 8:
		await process_frame
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var err := img.save_png(ProjectSettings.globalize_path(OUT))
	print("icon: %s (%s)" % [OUT, error_string(err)])
	quit(0 if err == OK else 1)
