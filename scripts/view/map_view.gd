class_name MapView
extends Node3D
## 지도 관찰 창(3D). 계약: docs/VIEW-API.md "MapView". 시뮬레이션은 docs/SIM-API.md 의 질의로 읽기만 한다.
##
## 그리기 구성(그리기 호출 수가 개체 수와 무관하도록):
##   땅 = ArrayMesh 하나(칸마다 평평한 사각형 + 높이 차이의 옆면, 정점 색). 색은 ui.map.terrain_refresh_ticks 마다
##        위 사각형 부분의 색 영역만 다시 올린다(surface_update_attribute_region).
##   식물·바닥 먹이·슬라임·운반 열매·저장고·밭 = MultiMesh 하나씩. 선택 고리 = MeshInstance3D 하나.
## 보간: before_steps() 가 진행 전 위치(id → 칸)를 기억하고, update_view(alpha) 가 그 칸에서 지금 칸으로 옮긴다.
## 두 배열 모두 id 오름차순이므로 사전 없이 두 포인터로 맞춘다.

signal slime_clicked(id: int)

const OrbitCamera := preload("res://scripts/view/orbit_camera.gd")

## MultiMesh 버퍼 한 개체 몫(Transform3D 3×4 = 12, 색 4).
const XF := 12
const XFC := 16
## 화면 전용 칸 해시(무늬·흔들림). 정수 곱이 63비트 안에서 끝나는 상수.
const HASH_A := 73856093
const HASH_B := 19349663
const HASH_C := 83492791
const HASH_MASK := 0x7fffffff
const HASH_DIV := 2147483648.0
## 해시 갈래(같은 칸에서 서로 다른 값을 뽑기 위함).
const SALT_JITTER := 1
const SALT_PLANT_X := 2
const SALT_PLANT_Z := 3
const SALT_PLANT_YAW := 4
const SALT_PLANT_H := 5
const SALT_PLANT_TINT := 6
const SALT_STACK := 7
const SALT_BREATH := 8
## 북(0)·동(1)·남(2)·서(3) → 모델(정면 -Z)의 Y 회전 = -방향 × 90°.
const QUARTER := PI * 0.5
## 정점 색 RGBA8: 한 채널 최댓값, 불투명 알파 비트(가장 높은 바이트).
const BYTE := 255.0
const OPAQUE := 0xff << 24
## 옆면 그늘: 물 옆면은 물 색을 이만큼 어둡게, 모든 옆면의 아래 모서리는 위 모서리보다 이만큼 어둡게.
const SIDE_WATER_DARK := 0.35
const SIDE_BOTTOM_DARK := 0.25
## 뷰포트 크기를 아직 모를 때의 화면비.
const DEFAULT_ASPECT := 16.0 / 9.0
## 높이 차이가 이보다 작으면 옆면을 만들지 않음.
const SIDE_EPS := 0.001
## 겹친 개체가 이 수를 넘으면 둘레를 조금씩 넓힘.
const STACK_RING := 4
const STACK_GROW := 0.12
const STACK_MAX := 0.42
## 걸음 중 눌림·늘어남에서 부피를 대략 지키는 지수(가로 = 세로^-1/2).
const VOLUME_EXP := -0.5
## 둥근 그림자 원판: 안쪽 고리 반지름과 그 진하기(바깥 고리는 투명).
const DISC_INNER := 0.55
const DISC_INNER_ALPHA := 0.85
## 뛰어오르면 그림자가 이만큼까지 작아짐(높이 1 당).
const SHADOW_SHRINK := 1.5
## 먹기·줍기 동작의 고개 끄덕임 주기(틱당 반 번).
const BOB_FREQ := PI

var world: SimWorld
var follow_selected := false

var _camera: OrbitCamera
var _sun: DirectionalLight3D
var _env: Environment
var _terrain_mi: MeshInstance3D
var _terrain_mesh: ArrayMesh
var _plant_mm: MultiMesh
var _drop_mm: MultiMesh
var _slime_mm: MultiMesh
var _carry_mm: MultiMesh
var _shadow_mm: MultiMesh
var _store_mm: MultiMesh
var _farm_mm: MultiMesh
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _selected := -1

# ── ui.json 에서 한 번 읽는 값 ──
var _tile := 1.0
var _c_poor := Color()
var _c_rich := Color()
var _c_water := Color()
var _c_water_shore := Color()
var _c_rock := Color()
var _c_farm := Color()
var _c_bank := Color()
var _c_food := Color()
var _c_plant := Color()
var _c_drop := Color()
var _food_k := 0.0
var _jitter := 0.0
var _season_tints: Array[Color] = []
var _season_k := 0.0
var _water_depth := 0.0
var _rock_height := 0.0
var _skirt := 0.0
var _rock_side := 0.0
var _terrain_every := 10
var _terrain_min_frames := 1
var _plant_every := 2
var _plant_min_frames := 1
var _p_min := 0.0
var _p_max := 0.0
var _p_hide := 0.0
var _p_jit := 0.0
var _p_hjit := 0.0
var _p_tint_jit := 0.0
var _d_min := 0.0
var _d_max := 0.0
var _d_full := 1.0
var _carry_scale := 0.0
var _carry_gap := 0.0
var _ring_scale := 0.0
var _ring_lift := 0.0
var _ring_pulse := 0.0
var _ring_pulse_w := 0.0
var _breath_amp := 0.0
var _shadow_scale := 0.0
var _shadow_lift := 0.0
var _night_boost := 1.0
## 둥근 그림자를 빛이 떨어지는 쪽으로 미는 양(땅 위 x, z, 크기 1 기준).
var _shadow_off := Vector2.ZERO
var _breath_w := 0.0
var _bob := 0.0
var _pick_r := 0.0
var _farm_lift := 0.0
var _hop := 0.0
var _squash := 0.0
var _stack := 0.0
var _sat := 0.0
var _val := 0.0
var _radius := 0.0
var _click_px := 0.0
var _focus_dist := 0.0
var _follow_k := 0.0
var _light_day := 0.0
var _light_night := 0.0
var _amb_day := 0.0
var _amb_night := 0.0
var _c_light_day := Color()
var _c_light_night := Color()
var _c_amb_day := Color()
var _c_amb_night := Color()
var _c_bg_day := Color()
var _c_bg_night := Color()

# ── 메시 정보(바닥 맞춤·삼각형 수) ──
var _slime_base := 0.0
var _slime_top := 0.0
var _slime_center := 0.0
var _plant_base := 0.0
var _berry_base := 0.0
var _berry_mid := 0.0
var _store_base := 0.0
var _farm_base := 0.0
var _tri := {}
var _plant_col := Color.WHITE
var _crop_col := Color.WHITE
var _drop_col := Color.WHITE
var _store_col := Color.WHITE
var _farm_col := Color.WHITE

# ── 땅 ──
var _n_tiles := 0
var _top_rgba := PackedInt32Array()
var _static_rgba := PackedInt32Array()
var _jit := PackedFloat32Array()
var _fert_lo := 0.0
var _fert_inv := 1.0
var _terrain_tris := 0
var _terrain_tick := -1
var _terrain_frames := 0
var _terrain_last_us := 0

# ── 식물·바닥 먹이 ──
var _plant_tile := PackedInt32Array()
var _plant_cs := PackedFloat32Array()
var _plant_sn := PackedFloat32Array()
var _plant_hy := PackedFloat32Array()
var _plant_kind := PackedByteArray()
var _plant_tint := PackedFloat32Array()
var _plant_buf := PackedFloat32Array()
var _plant_inv_ref := 0.0
var _plant_visible := 0
var _plant_tick := -1
var _plant_frames := 0
var _plant_last_us := 0
var _drop_buf := PackedFloat32Array()
var _drop_tiles := PackedInt32Array()
var _drop_count := 0

# ── 슬라임 ──
var _slime_buf := PackedFloat32Array()
var _shadow_buf := PackedFloat32Array()
var _carry_buf := PackedFloat32Array()
var _carry_count := 0
var _tile_cnt := PackedInt32Array()
var _tile_slot := PackedInt32Array()
var _snap_id := PackedInt32Array()
var _snap_x := PackedInt32Array()
var _snap_y := PackedInt32Array()
var _snap_h := PackedInt32Array()
var _snap_tick := -1
var _prev_id := PackedInt32Array()
var _prev_x := PackedInt32Array()
var _prev_y := PackedInt32Array()
var _prev_h := PackedInt32Array()
var _has_prev := false
var _shown_tick := -1
## 마지막으로 그린 위치(고르기·선택 고리·따라가기용).
var _pick_id := PackedInt32Array()
var _pick_x := PackedFloat32Array()
var _pick_z := PackedFloat32Array()
var _sel_pos := Vector3.ZERO
var _sel_found := false
var _slime_last_us := 0
var _anim_time := 0.0

# ── 건물 ──
var _last_stores := PackedInt32Array()
var _last_farms := PackedInt32Array()

# ── 입력 ──
var _left_down := false
var _right_down := false
var _dragged := false
var _press_pos := Vector2.ZERO
## 묶은 뒤 사용자가(또는 focus_on·따라가기가) 카메라를 움직였는지. 아니면 뷰포트 크기가 바뀔 때 다시 맞춘다.
var _camera_touched := false


func _init() -> void:
	_load_ui()
	_build_nodes()


func _process(delta: float) -> void:
	_anim_time += delta


# ════════════════════════════ 만들기 ════════════════════════════

func _load_ui() -> void:
	_tile = UiConfig.num("map.tile_size")
	_c_poor = UiConfig.color("map.grass_poor")
	_c_rich = UiConfig.color("map.grass_rich")
	_c_water = UiConfig.color("map.water")
	_c_water_shore = UiConfig.color("map.water_shore")
	_c_rock = UiConfig.color("map.rock")
	_c_farm = UiConfig.color("map.farm")
	_c_bank = UiConfig.color("map.bank")
	_c_food = UiConfig.color("map.food_tint")
	_c_plant = UiConfig.color("map.plant_color")
	_c_drop = UiConfig.color("map.dropped_color")
	_food_k = UiConfig.num("map.food_tint_strength")
	_jitter = UiConfig.num("map.tile_jitter")
	_season_tints.clear()
	for s in UiConfig.value("map.season_tints", []):
		_season_tints.append(Color.from_string(str(s), Color.WHITE))
	_season_k = UiConfig.num("map.season_tint_strength")
	_water_depth = UiConfig.num("map.water_depth")
	_rock_height = UiConfig.num("map.rock_height")
	_skirt = UiConfig.num("map.skirt_depth")
	_rock_side = UiConfig.num("map.rock_side_shade")
	_terrain_every = maxi(1, UiConfig.integer("map.terrain_refresh_ticks"))
	_terrain_min_frames = maxi(1, UiConfig.integer("map.terrain_min_frames"))
	_plant_every = maxi(1, UiConfig.integer("map.plant_refresh_ticks"))
	_plant_min_frames = maxi(1, UiConfig.integer("map.plant_min_frames"))
	_p_min = UiConfig.num("map.plant_min_scale")
	_p_max = UiConfig.num("map.plant_max_scale")
	_p_hide = UiConfig.num("map.plant_hide_frac")
	_p_jit = UiConfig.num("map.plant_jitter")
	_p_hjit = UiConfig.num("map.plant_height_jitter")
	_p_tint_jit = UiConfig.num("map.plant_tint_jitter")
	_d_min = UiConfig.num("map.dropped_scale_min")
	_d_max = UiConfig.num("map.dropped_scale_max")
	_d_full = maxf(UiConfig.num("map.dropped_full"), 0.001)
	_carry_scale = UiConfig.num("map.carry_scale")
	_carry_gap = UiConfig.num("map.carry_gap")
	_ring_scale = UiConfig.num("map.ring_scale")
	_ring_lift = UiConfig.num("map.ring_lift")
	_ring_pulse = UiConfig.num("map.ring_pulse")
	_ring_pulse_w = TAU * UiConfig.num("map.ring_pulse_hz")
	_breath_amp = UiConfig.num("map.breath_amp")
	_shadow_scale = UiConfig.num("map.blob_shadow_scale")
	_shadow_lift = UiConfig.num("map.blob_shadow_lift")
	_night_boost = UiConfig.num("map.night_slime_boost")
	_breath_w = TAU * UiConfig.num("map.breath_hz")
	_bob = UiConfig.num("map.action_bob")
	_pick_r = UiConfig.num("map.pick_radius")
	_farm_lift = UiConfig.num("map.farm_lift")
	_hop = UiConfig.num("slime.hop_height")
	_squash = UiConfig.num("slime.squash")
	_stack = UiConfig.num("slime.stack_offset")
	_sat = UiConfig.num("slime.saturation")
	_val = UiConfig.num("slime.value")
	_radius = UiConfig.num("slime.radius")
	_click_px = UiConfig.num("camera.click_threshold_px")
	_focus_dist = UiConfig.num("camera.focus_distance")
	_follow_k = clampf(UiConfig.num("camera.follow_lerp"), 0.0, 1.0)
	_light_day = UiConfig.num("map.day_light_energy")
	_light_night = UiConfig.num("map.night_light_energy")
	_amb_day = UiConfig.num("map.day_ambient")
	_amb_night = UiConfig.num("map.night_ambient")
	_c_light_day = UiConfig.color("map.day_light_color")
	_c_light_night = UiConfig.color("map.night_light_color")
	_c_amb_day = UiConfig.color("map.day_ambient_color")
	_c_amb_night = UiConfig.color("map.night_ambient_color")
	_c_bg_day = UiConfig.color("map.day_background")
	_c_bg_night = UiConfig.color("map.night_background")


## 카메라·빛·환경·땅·MultiMesh 노드. 트리에 들어가기 전에 bind 해도 되도록 _init 에서 만든다.
func _build_nodes() -> void:
	_camera = OrbitCamera.new()
	_camera.name = "Camera"
	add_child(_camera)
	_camera.current = true

	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation = Vector3(deg_to_rad(UiConfig.num("map.light_pitch_deg")), deg_to_rad(UiConfig.num("map.light_yaw_deg")), 0.0)
	_sun.shadow_enabled = bool(UiConfig.value("map.shadows", false))
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = UiConfig.num("map.shadow_distance")
	_sun.shadow_opacity = UiConfig.num("map.shadow_opacity")
	var ray := _sun.transform.basis * Vector3.FORWARD
	_shadow_off = Vector2(ray.x, ray.z).normalized() * UiConfig.num("map.blob_shadow_offset") if Vector2(ray.x, ray.z).length() > 0.0 else Vector2.ZERO
	add_child(_sun)

	_terrain_mi = MeshInstance3D.new()
	_terrain_mi.name = "Terrain"
	var tm := StandardMaterial3D.new()
	tm.vertex_color_use_as_albedo = true
	tm.vertex_color_is_srgb = true
	tm.roughness = 1.0
	tm.metallic_specular = 0.0
	_terrain_mi.material_override = tm
	add_child(_terrain_mi)

	var shared := SlimeGeo.shared_material()
	_farm_mm = _add_mm("Farms", SlimeGeo.farm_mesh(), shared, true, false)
	_store_mm = _add_mm("Stores", SlimeGeo.storehouse_mesh(), shared, true, true)
	_plant_mm = _add_mm("Plants", SlimeGeo.plant_mesh(), shared, true, false)
	_drop_mm = _add_mm("Dropped", SlimeGeo.berry_mesh(), shared, true, false)
	_slime_mm = _add_mm("Slimes", SlimeGeo.slime_mesh(), SlimeGeo.slime_material(), true, true)
	_carry_mm = _add_mm("Carry", SlimeGeo.berry_mesh(), shared, true, true)
	# 슬라임 발밑 둥근 그림자(실시간 그림자 대신: Compatibility 에서 그림자 켜면 해가 두 번 더해져 밝아짐)
	var shm := StandardMaterial3D.new()
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.vertex_color_use_as_albedo = true
	shm.albedo_color = Color(0.0, 0.0, 0.0, UiConfig.num("map.blob_shadow_alpha"))
	shm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	shm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow_mm = _add_mm("SlimeShadows", _disc_mesh(UiConfig.integer("map.blob_shadow_segments")), shm, false, false)

	_ring = MeshInstance3D.new()
	_ring.name = "SelectRing"
	_ring.mesh = SlimeGeo.ring_mesh()
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = UiConfig.color("slime.selected_ring_color")
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)

	# 메시 바닥을 y 0 에 맞추는 값(조각 메시는 원래 바닥 0, 기본 도형 대용품은 가운데가 원점)
	var sa := SlimeGeo.slime_mesh().get_aabb()
	_slime_base = -sa.position.y
	_slime_top = sa.size.y
	_slime_center = sa.size.y * 0.5
	_plant_base = -SlimeGeo.plant_mesh().get_aabb().position.y
	var ba := SlimeGeo.berry_mesh().get_aabb()
	_berry_base = -ba.position.y
	_berry_mid = -(ba.position.y + ba.size.y * 0.5)
	_store_base = -SlimeGeo.storehouse_mesh().get_aabb().position.y
	_farm_base = -SlimeGeo.farm_mesh().get_aabb().position.y
	_tri = {
		slime = SlimeGeo.triangle_count(SlimeGeo.slime_mesh()), plant = SlimeGeo.triangle_count(SlimeGeo.plant_mesh()),
		berry = SlimeGeo.triangle_count(SlimeGeo.berry_mesh()), store = SlimeGeo.triangle_count(SlimeGeo.storehouse_mesh()),
		farm = SlimeGeo.triangle_count(SlimeGeo.farm_mesh()), ring = SlimeGeo.triangle_count(SlimeGeo.ring_mesh()),
	}
	# 대용품 메시(정점 색 없음)일 때 대신 쓸 색
	_plant_col = _tint_for(SlimeGeo.plant_mesh(), _c_plant)
	_crop_col = UiConfig.color("buildings.farm_crop") if _plant_col != Color.WHITE else Color.WHITE
	_drop_col = _tint_for(SlimeGeo.berry_mesh(), _c_drop)
	_store_col = _tint_for(SlimeGeo.storehouse_mesh(), UiConfig.color("buildings.store_wall"))
	_farm_col = _tint_for(SlimeGeo.farm_mesh(), UiConfig.color("buildings.farm_soil"))


func _add_mm(node_name: String, mesh: Mesh, mat: Material, colors: bool, shadows: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mm


## 바닥에 눕힌 부드러운 원판(반지름 1, 가운데 진하고 가장자리 투명). 둥근 그림자용.
static func _disc_mesh(segs: int) -> ArrayMesh:
	var v := PackedVector3Array([Vector3.ZERO])
	var cl := PackedColorArray([Color(1, 1, 1, 1)])
	var ix := PackedInt32Array()
	segs = maxi(segs, 6)
	for k in segs:
		var a := TAU * float(k) / float(segs)
		v.append(Vector3(cos(a) * DISC_INNER, 0.0, sin(a) * DISC_INNER))
		cl.append(Color(1, 1, 1, DISC_INNER_ALPHA))
		v.append(Vector3(cos(a), 0.0, sin(a)))
		cl.append(Color(1, 1, 1, 0))
	for k in segs:
		var i0 := 1 + 2 * k
		var i1 := 1 + 2 * ((k + 1) % segs)
		# 위에서 보아 시계 방향(앞면)
		ix.append_array([0, i0, i1, i0, i1 + 1, i1, i0, i0 + 1, i1 + 1])
	var nm := PackedVector3Array()
	nm.resize(v.size())
	nm.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nm
	arr[Mesh.ARRAY_COLOR] = cl
	arr[Mesh.ARRAY_INDEX] = ix
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## 메시에 정점 색이 있으면 흰색(메시 색 그대로), 없으면(기본 도형 대용품) 대신할 색.
static func _tint_for(mesh: Mesh, fallback: Color) -> Color:
	if mesh != null and mesh.get_surface_count() > 0 and (mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0:
		return Color.WHITE
	return fallback


## 화면 전용 칸 해시 0~1(시뮬레이션 난수와 무관, 결정적).
static func _hash01(c: int, salt: int) -> float:
	var h := (c * HASH_A + salt * HASH_B + HASH_C) & HASH_MASK
	h = ((h ^ (h >> 13)) * HASH_A) & HASH_MASK
	h = h ^ (h >> 16)
	return float(h & HASH_MASK) / HASH_DIV


func _tile_height(kind: int) -> float:
	match kind:
		SimGrid.TILE_WATER:
			return -_water_depth
		SimGrid.TILE_ROCK:
			return _rock_height
	return 0.0


# ════════════════════════════ 계약 ════════════════════════════

## 세계를 붙이고 땅·식물·건물·슬라임을 새로 만든다. 다른 세계로 다시 불러도 된다.
func bind(w: SimWorld) -> void:
	world = w
	_selected = -1
	_ring.visible = false
	_snap_tick = -1
	_has_prev = false
	_shown_tick = -1
	_terrain_tick = -1
	_plant_tick = -1
	_last_stores = PackedInt32Array()
	_last_farms = PackedInt32Array()
	# 앞 세계의 건물을 지운다(새 세계도 건물이 없으면 _sync_buildings 가 "바뀜 없음"으로 보고 넘어가므로)
	_store_mm.instance_count = 0
	_farm_mm.instance_count = 0
	_camera_touched = false
	if world == null:
		_terrain_mi.mesh = null
		for mm in [_plant_mm, _drop_mm, _slime_mm, _shadow_mm, _carry_mm, _store_mm, _farm_mm]:
			(mm as MultiMesh).instance_count = 0
		return
	_n_tiles = world.w * world.h
	_tile_cnt.resize(_n_tiles)
	_tile_cnt.fill(0)
	_tile_slot.resize(_n_tiles)
	_tile_slot.fill(0)
	_build_terrain()
	_build_plants()
	_frame_camera()
	update_view(1.0)


## 이 프레임에 step() 을 부르기 전에 호출. 보간용으로 지금 위치(id → 칸)를 기억한다.
func before_steps() -> void:
	if world == null or _snap_tick == world.tick:
		return
	_snap_id = world.s_id.duplicate()
	_snap_x = world.s_x.duplicate()
	_snap_y = world.s_y.duplicate()
	_snap_h = world.s_head.duplicate()
	_snap_tick = world.tick


## 매 프레임 step() 뒤에 호출. alpha(0~1) = 다음 틱까지의 진행률.
func update_view(alpha: float) -> void:
	if world == null:
		return
	var t := world.tick
	if t != _shown_tick:
		# 이번 프레임에 진행했다: 진행 전 기억을 "이전 위치"로 올린다(버퍼는 맞바꿔 다시 씀)
		if _snap_tick != -1 and _snap_tick != t:
			var a := _prev_id
			_prev_id = _snap_id
			_snap_id = a
			a = _prev_x
			_prev_x = _snap_x
			_snap_x = a
			a = _prev_y
			_prev_y = _snap_y
			_snap_y = a
			a = _prev_h
			_prev_h = _snap_h
			_snap_h = a
			_has_prev = true
		else:
			_has_prev = false
		_snap_tick = -1
		_shown_tick = t
	# 식물과 땅 색은 틱이 일정 이상 지났을 때만, 같은 프레임에 둘 다 하지 않게
	_plant_frames += 1
	_terrain_frames += 1
	var did_plants := false
	if _plant_tick == -1 or (t - _plant_tick >= _plant_every and _plant_frames >= _plant_min_frames) or t < _plant_tick:
		_refresh_plants()
		did_plants = true
	if _terrain_tick == -1 or ((t - _terrain_tick >= _terrain_every and _terrain_frames >= _terrain_min_frames) and not did_plants) or t < _terrain_tick:
		_recolor_terrain()
	_sync_buildings()
	_update_slimes(clampf(alpha, 0.0, 1.0))
	_update_light()
	_update_ring()
	if follow_selected and _sel_found:
		_camera_touched = true
		_camera.target = _camera.target.lerp(Vector3(_sel_pos.x, 0.0, _sel_pos.z), _follow_k)
		_camera.apply()


## 선택 표시(-1 = 없음). 죽은 개체면 표시하지 않는다.
func set_selected(id: int) -> void:
	_selected = id
	_sel_found = false
	_update_ring()


## 뷰포트 좌표의 광선을 슬라임 중심 높이의 수평면과 교차해 가장 가까운(그려진 위치 기준) 살아 있는 슬라임 id. 없으면 -1.
func pick_slime(screen_pos: Vector2) -> int:
	if world == null or not _camera.is_inside_tree():
		return -1
	var g: Variant = _camera.ground_point(screen_pos, _slime_center)
	if g == null:
		return -1
	var p: Vector3 = g
	var best := -1
	var best_d := _pick_r * _tile * _pick_r * _tile
	for i in _pick_id.size():
		var dx := _pick_x[i] - p.x
		var dz := _pick_z[i] - p.z
		var d := dx * dx + dz * dz
		if d < best_d:
			best_d = d
			best = _pick_id[i]
	return best


## 카메라를 그 개체로 옮긴다(너무 멀면 가까이 당김).
func focus_on(id: int) -> void:
	if world == null:
		return
	var i := world.index_of_id(id)
	if i == -1:
		return
	var p := _rendered_pos(id, i)
	_camera_touched = true
	_camera.target = Vector3(p.x, 0.0, p.z)
	if _camera.distance > _focus_dist:
		_camera.distance = _focus_dist
	_camera.apply()


func get_camera() -> Camera3D:
	return _camera


## 성능 기록용 수치.
func view_stats() -> Dictionary:
	if world == null:
		return {slimes = 0, plants = 0, stores = 0, farms = 0, triangles_estimate = 0}
	var n := world.s_id.size()
	var tris := _terrain_tris + n * int(_tri.slime) + _plant_visible * int(_tri.plant)
	tris += (_drop_count + _carry_count) * int(_tri.berry)
	tris += world.store_tiles.size() * int(_tri.store) + world.farms.size() * int(_tri.farm)
	if _ring.visible:
		tris += int(_tri.ring)
	return {
		slimes = n, plants = _plant_visible, stores = world.store_tiles.size(), farms = world.farms.size(),
		triangles_estimate = tris,
		slime_us = _slime_last_us, plant_us = _plant_last_us, terrain_us = _terrain_last_us,
	}


# ════════════════════════════ 땅 ════════════════════════════

## 땅 메시 하나: 앞부분 = 칸마다 위 사각형(칸 순서, 정점 4개), 뒷부분 = 높이 차이·지도 가장자리 옆면.
## 위 사각형의 색만 바뀌므로(풀밭 ↔ 밭, 먹이량, 계절) 색 영역 앞부분만 다시 올리면 된다.
func _build_terrain() -> void:
	var W := world.w
	var H := world.h
	var n := _n_tiles
	var heights := PackedFloat32Array()
	heights.resize(n)
	_jit.resize(n)
	_static_rgba.resize(n)
	for c in n:
		heights[c] = _tile_height(world.tiles[c])
		_jit[c] = 1.0 + _jitter * (2.0 * _hash01(c, SALT_JITTER) - 1.0)
	# 비옥도 범위(색 대비용, 화면 전용): 통과 가능 칸의 최소·최대
	var lo := INF
	var hi := -INF
	for c in n:
		if SimGrid.passable(world.tiles[c]):
			lo = minf(lo, world.fert[c])
			hi = maxf(hi, world.fert[c])
	if lo > hi:
		lo = 0.0
		hi = 1.0
	_fert_lo = lo
	_fert_inv = 1.0 / maxf(hi - lo, 0.001)
	# 물·바위 칸 색은 바뀌지 않으므로 미리 계산(물은 물가 쪽을 밝게)
	for c in n:
		var k := world.tiles[c]
		var col := Color.BLACK
		if k == SimGrid.TILE_WATER:
			var x := c % W
			var y := c / W
			var shore := false
			for d in SimGrid.DIR_COUNT:
				var nx: int = x + SimGrid.DX[d]
				var ny: int = y + SimGrid.DY[d]
				if nx >= 0 and ny >= 0 and nx < W and ny < H and world.tiles[ny * W + nx] != SimGrid.TILE_WATER:
					shore = true
			col = _c_water_shore if shore else _c_water
		elif k == SimGrid.TILE_ROCK:
			col = _c_rock
		var j := _jit[c]
		_static_rgba[c] = _rgba(col.r * j, col.g * j, col.b * j)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var tl := _tile
	# ① 위 사각형(칸 순서)
	for c in n:
		var x0 := float(c % W) * tl
		var z0 := float(c / W) * tl
		var hy := heights[c]
		_quad(verts, norms, cols, idx,
			Vector3(x0, hy, z0), Vector3(x0 + tl, hy, z0), Vector3(x0 + tl, hy, z0 + tl), Vector3(x0, hy, z0 + tl),
			Vector3.UP, Color.WHITE)
	# ② 옆면: 이웃(또는 지도 밖 = 바닥 깊이)이 더 낮은 쪽 모서리마다 세운다
	var floor_y := -_water_depth - _skirt
	for c in n:
		var x := c % W
		var y := c / W
		var hc := heights[c]
		var kind := world.tiles[c]
		var side := _c_bank
		if kind == SimGrid.TILE_ROCK:
			side = Color(_c_rock.r * _rock_side, _c_rock.g * _rock_side, _c_rock.b * _rock_side)
		elif kind == SimGrid.TILE_WATER:
			side = _c_water.darkened(SIDE_WATER_DARK)
		for d in SimGrid.DIR_COUNT:
			var nx: int = x + SimGrid.DX[d]
			var ny: int = y + SimGrid.DY[d]
			var hn := floor_y
			if nx >= 0 and ny >= 0 and nx < W and ny < H:
				hn = heights[ny * W + nx]
			if hn >= hc - SIDE_EPS:
				continue
			var x0 := float(x) * tl
			var z0 := float(y) * tl
			var a := Vector3.ZERO
			var b := Vector3.ZERO
			match d:
				0:
					a = Vector3(x0, 0.0, z0)
					b = Vector3(x0 + tl, 0.0, z0)
				1:
					a = Vector3(x0 + tl, 0.0, z0)
					b = Vector3(x0 + tl, 0.0, z0 + tl)
				2:
					a = Vector3(x0 + tl, 0.0, z0 + tl)
					b = Vector3(x0, 0.0, z0 + tl)
				_:
					a = Vector3(x0, 0.0, z0 + tl)
					b = Vector3(x0, 0.0, z0)
			var nrm := Vector3(float(SimGrid.DX[d]), 0.0, float(SimGrid.DY[d]))
			var lo_shade := side.darkened(SIDE_BOTTOM_DARK)
			_quad_grad(verts, norms, cols, idx,
				Vector3(a.x, hc, a.z), Vector3(b.x, hc, b.z), Vector3(b.x, hn, b.z), Vector3(a.x, hn, a.z),
				nrm, side, lo_shade)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	_terrain_mesh = ArrayMesh.new()
	_terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_terrain_mi.mesh = _terrain_mesh
	_terrain_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_terrain_tris = idx.size() / 3
	_top_rgba.resize(n * 4)
	_recolor_terrain()


## 사각형 하나(정점 4개, 삼각형 2개). 법선 n 쪽에서 보아 앞면이 되도록 감는 방향을 고른다(Godot 앞면 = 시계 방향).
static func _quad(v: PackedVector3Array, nm: PackedVector3Array, cl: PackedColorArray, ix: PackedInt32Array,
		p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, col: Color) -> void:
	_quad_grad(v, nm, cl, ix, p0, p1, p2, p3, n, col, col)


## 위 두 정점(p0, p1)은 col_top, 아래 두 정점(p2, p3)은 col_bottom.
static func _quad_grad(v: PackedVector3Array, nm: PackedVector3Array, cl: PackedColorArray, ix: PackedInt32Array,
		p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, col_top: Color, col_bottom: Color) -> void:
	var b := v.size()
	v.append(p0)
	v.append(p1)
	v.append(p2)
	v.append(p3)
	for k in 4:
		nm.append(n)
	cl.append(col_top)
	cl.append(col_top)
	cl.append(col_bottom)
	cl.append(col_bottom)
	if (p2 - p0).cross(p1 - p0).dot(n) > 0.0:
		ix.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	else:
		ix.append_array([b, b + 2, b + 1, b, b + 3, b + 2])


## 위 사각형 색 다시 계산: 풀밭 = 비옥도(척박 → 기름짐) + 먹이량만큼 먹이 색 + 계절 색, 밭 = 밭 색, 물·바위 = 고정.
## 칸마다 RGBA8 정수 하나를 정점 4개에 넣고 색 영역 앞부분만 올린다.
func _recolor_terrain() -> void:
	var t0 := Time.get_ticks_usec()
	var tiles := world.tiles
	var fert := world.fert
	var food := world.food
	var cap := world.food_cap
	var tint := Color.WHITE
	if world.season >= 0 and world.season < _season_tints.size():
		tint = Color.WHITE.lerp(_season_tints[world.season], _season_k)
	var pr := _c_poor.r * tint.r
	var pg := _c_poor.g * tint.g
	var pb := _c_poor.b * tint.b
	var rr := _c_rich.r * tint.r - pr
	var rg := _c_rich.g * tint.g - pg
	var rb := _c_rich.b * tint.b - pb
	var fr := _c_food.r * tint.r
	var fg := _c_food.g * tint.g
	var fb := _c_food.b * tint.b
	var fk := _food_k
	var lo := _fert_lo
	var inv := _fert_inv
	var farm := _c_farm
	var out := _top_rgba
	for c in _n_tiles:
		var k := tiles[c]
		var v := 0
		if k == SimGrid.TILE_GRASS:
			var u := clampf((fert[c] - lo) * inv, 0.0, 1.0)
			var r := pr + rr * u
			var g := pg + rg * u
			var b := pb + rb * u
			var cp := cap[c]
			if cp > 0.0:
				var f := food[c] / cp * fk
				r += (fr - r) * f
				g += (fg - g) * f
				b += (fb - b) * f
			var j := _jit[c] * BYTE
			v = (int(clampf(r * j, 0.0, BYTE)) | (int(clampf(g * j, 0.0, BYTE)) << 8)
				| (int(clampf(b * j, 0.0, BYTE)) << 16) | OPAQUE)
		elif k == SimGrid.TILE_FARM:
			var j2 := _jit[c]
			v = _rgba(farm.r * j2, farm.g * j2, farm.b * j2)
		else:
			v = _static_rgba[c]
		var o := c * 4
		out[o] = v
		out[o + 1] = v
		out[o + 2] = v
		out[o + 3] = v
	_terrain_mesh.surface_update_attribute_region(0, 0, out.to_byte_array())
	_terrain_tick = world.tick
	_terrain_frames = 0
	_terrain_last_us = Time.get_ticks_usec() - t0


## 정점 색 영역 한 칸(RGBA8, 작은 쪽 바이트가 R).
static func _rgba(r: float, g: float, b: float) -> int:
	return Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0)).to_abgr32()


## 칸 c 의 지금 위 사각형 색(검사용).
func terrain_tile_color(c: int) -> Color:
	if c < 0 or c * 4 >= _top_rgba.size():
		return Color.BLACK
	var v := _top_rgba[c * 4]
	return Color8(v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff)


# ════════════════════════════ 식물·바닥 먹이 ════════════════════════════

## 통과 가능 칸마다 풀포기 하나(물·바위는 바뀌지 않으므로 개수는 고정). 칸 안 위치·방향·키·밝기는 칸 해시.
func _build_plants() -> void:
	_plant_tile = PackedInt32Array()
	for c in _n_tiles:
		if SimGrid.passable(world.tiles[c]):
			_plant_tile.append(c)
	var n := _plant_tile.size()
	_plant_cs.resize(n)
	_plant_sn.resize(n)
	_plant_hy.resize(n)
	_plant_tint.resize(n)
	_plant_kind.resize(n)
	_plant_mm.instance_count = n
	_plant_buf.resize(n * XFC)
	_plant_buf.fill(0.0)
	var W := world.w
	for k in n:
		var c := _plant_tile[k]
		var yaw := TAU * _hash01(c, SALT_PLANT_YAW)
		_plant_cs[k] = cos(yaw)
		_plant_sn[k] = sin(yaw)
		_plant_hy[k] = 1.0 + _p_hjit * (2.0 * _hash01(c, SALT_PLANT_H) - 1.0)
		_plant_tint[k] = 1.0 + _p_tint_jit * (2.0 * _hash01(c, SALT_PLANT_TINT) - 1.0)
		var o := k * XFC
		_plant_buf[o + 3] = (float(c % W) + 0.5 + _p_jit * (2.0 * _hash01(c, SALT_PLANT_X) - 1.0)) * _tile
		_plant_buf[o + 11] = (float(c / W) + 0.5 + _p_jit * (2.0 * _hash01(c, SALT_PLANT_Z) - 1.0)) * _tile
		_plant_kind[k] = 255
	# 먹이량 기준: 풀밭 칸의 가장 큰 상한(밭은 상한이 더 커서 넘치면 최대 배율로 자름)
	var ref := 0.0
	for c in _plant_tile:
		if world.tiles[c] == SimGrid.TILE_GRASS:
			ref = maxf(ref, world.food_cap[c])
	_plant_inv_ref = 1.0 / ref if ref > 0.0 else 0.0
	_drop_tiles.resize(n)
	_drop_count = 0
	_drop_mm.instance_count = 0
	_drop_mm.visible_instance_count = 0
	_drop_buf.resize(0)


## 풀포기 크기(먹이량 비례, 거의 없으면 0 = 숨김)와 바닥 먹이 열매를 다시 쓴다. 바뀌는 값만 버퍼에 쓴다.
func _refresh_plants() -> void:
	var t0 := Time.get_ticks_usec()
	var food := world.food
	var tiles := world.tiles
	var dropped := world.dropped
	var buf := _plant_buf
	var inv := _plant_inv_ref
	var hide := _p_hide
	var smin := _p_min
	var sspan := _p_max - _p_min
	var base := _plant_base
	var vis := 0
	var nd := 0
	for k in _plant_tile.size():
		var c := _plant_tile[k]
		var f := food[c] * inv
		var s := 0.0
		if f > hide:
			s = smin + sspan * minf(f, 1.0)
			vis += 1
		var o := k * XFC
		var cs := _plant_cs[k] * s
		var sn := _plant_sn[k] * s
		var sy := s * _plant_hy[k]
		buf[o] = cs
		buf[o + 2] = sn
		buf[o + 5] = sy
		buf[o + 7] = base * sy
		buf[o + 8] = -sn
		buf[o + 10] = cs
		var kind := tiles[c]
		if kind != _plant_kind[k]:
			# 풀밭 ↔ 밭: 색만 바꿈(대용품 메시일 때만 밭 작물 색)
			_plant_kind[k] = kind
			var col := _crop_col if kind == SimGrid.TILE_FARM else _plant_col
			var b := _plant_tint[k]
			buf[o + 12] = col.r * b
			buf[o + 13] = col.g * b
			buf[o + 14] = col.b * b
			buf[o + 15] = 1.0
		if dropped[c] > 0.0:
			_drop_tiles[nd] = c
			nd += 1
	_plant_mm.buffer = buf
	_plant_visible = vis
	_write_dropped(nd)
	_plant_tick = world.tick
	_plant_frames = 0
	_plant_last_us = Time.get_ticks_usec() - t0


## 바닥 먹이 열매(칸 가운데에서 조금 비켜, 양에 따라 크기). 개수가 늘면 용량을 두 배로.
func _write_dropped(nd: int) -> void:
	if nd > _drop_mm.instance_count:
		var cap := maxi(nd, maxi(16, _drop_mm.instance_count * 2))
		_drop_mm.instance_count = cap
		_drop_buf.resize(cap * XFC)
		_drop_buf.fill(0.0)
	_drop_count = nd
	if nd == 0:
		_drop_mm.visible_instance_count = 0
		return
	var col := _drop_col
	var W := world.w
	var dropped := world.dropped
	var buf := _drop_buf
	for k in nd:
		var c := _drop_tiles[k]
		var s := _d_min + (_d_max - _d_min) * clampf(sqrt(dropped[c] / _d_full), 0.0, 1.0)
		var o := k * XFC
		buf[o] = s
		buf[o + 1] = 0.0
		buf[o + 2] = 0.0
		buf[o + 3] = (float(c % W) + 0.5 - _p_jit) * _tile
		buf[o + 4] = 0.0
		buf[o + 5] = s
		buf[o + 6] = 0.0
		buf[o + 7] = _berry_base * s
		buf[o + 8] = 0.0
		buf[o + 9] = 0.0
		buf[o + 10] = s
		buf[o + 11] = (float(c / W) + 0.5 + _p_jit) * _tile
		buf[o + 12] = col.r
		buf[o + 13] = col.g
		buf[o + 14] = col.b
		buf[o + 15] = 1.0
	_drop_mm.buffer = buf
	_drop_mm.visible_instance_count = nd


# ════════════════════════════ 슬라임 ════════════════════════════

## 개체마다 위치(이전 칸 → 지금 칸 보간 + 겹침 배치)·방향·통통 튐·눌림·숨쉬기·색을 MultiMesh 버퍼에 쓴다.
func _update_slimes(alpha: float) -> void:
	var t0 := Time.get_ticks_usec()
	var ids := world.s_id
	var sx := world.s_x
	var sy := world.s_y
	var sh := world.s_head
	var size := world.s_size
	var carry := world.s_carry
	var act := world.s_last_action
	var hue := world.lin_hue
	var n := ids.size()
	var W := world.w
	if _slime_mm.instance_count != n:
		_slime_mm.instance_count = n
		_slime_buf.resize(n * XFC)
		_shadow_mm.instance_count = n
		_shadow_buf.resize(n * XF)
		_pick_id.resize(n)
		_pick_x.resize(n)
		_pick_z.resize(n)
	if _carry_mm.instance_count < n:
		_carry_mm.instance_count = n
		_carry_buf.resize(n * XFC)
		_carry_buf.fill(0.0)
	# 칸별 개체 수(겹친 개체를 둘레에 나눠 놓기 위해)
	var cnt := _tile_cnt
	var slot := _tile_slot
	for i in n:
		cnt[sy[i] * W + sx[i]] += 1
	var e := alpha * alpha * (3.0 - 2.0 * alpha)
	var hop_s := sin(PI * alpha)
	var sq_s := sin(TAU * alpha)
	var bob_s := sin(BOB_FREQ * alpha)
	var tl := _tile
	var pn := _prev_id.size() if _has_prev else 0
	var pid := _prev_id
	var j := 0
	var buf := _slime_buf
	var sbuf := _shadow_buf
	var cbuf := _carry_buf
	var nc := 0
	var carry_col := _drop_col
	# 밤에는 슬라임 색을 조금 밝혀 어둠 속에서도 계통 색이 읽히게
	var gain := lerpf(_night_boost, 1.0, clampf(world.light, 0.0, 1.0))
	_sel_found = false
	for i in n:
		var id := ids[i]
		var x := sx[i]
		var y := sy[i]
		var hd := sh[i]
		var px := x
		var py := y
		var ph := hd
		if pn > 0:
			while j < pn and pid[j] < id:
				j += 1
			if j < pn and pid[j] == id:
				px = _prev_x[j]
				py = _prev_y[j]
				ph = _prev_h[j]
		var c := y * W + x
		var m := cnt[c]
		var ox := 0.0
		var oz := 0.0
		if m > 1:
			var k := slot[c]
			slot[c] = k + 1
			var ang := TAU * (float(k) / float(m) + _hash01(c, SALT_STACK))
			var r := minf(_stack * (1.0 + STACK_GROW * float(maxi(0, m - STACK_RING))), STACK_MAX) * tl
			ox = cos(ang) * r
			oz = sin(ang) * r
		var wx := (float(px) + (float(x - px)) * e + 0.5) * tl + ox
		var wz := (float(py) + (float(y - py)) * e + 0.5) * tl + oz
		var s := size[i]
		var hy := 0.0
		var stretch := 1.0
		if px != x or py != y:
			hy = _hop * s * hop_s
			stretch = 1.0 + _squash * sq_s
		else:
			var a := act[i]
			if a == SimBrain.ACT_EAT or a == SimBrain.ACT_GATHER or a == SimBrain.ACT_PLANT:
				stretch = 1.0 - _bob * bob_s
			else:
				stretch = 1.0 + _breath_amp * sin(_anim_time * _breath_w + TAU * _hash01(id, SALT_BREATH))
		var wide := pow(stretch, VOLUME_EXP) * s
		var tall := stretch * s
		var yaw := -float(hd) * QUARTER
		if ph != hd:
			yaw = lerp_angle(-float(ph) * QUARTER, yaw, e)
		var co := cos(yaw)
		var si := sin(yaw)
		var o := i * XFC
		buf[o] = co * wide
		buf[o + 1] = 0.0
		buf[o + 2] = si * wide
		buf[o + 3] = wx
		buf[o + 4] = 0.0
		buf[o + 5] = tall
		buf[o + 6] = 0.0
		buf[o + 7] = _slime_base * tall + hy
		buf[o + 8] = -si * wide
		buf[o + 9] = 0.0
		buf[o + 10] = co * wide
		buf[o + 11] = wz
		var col := Color.from_hsv(hue[id], _sat, _val)
		buf[o + 12] = col.r * gain
		buf[o + 13] = col.g * gain
		buf[o + 14] = col.b * gain
		buf[o + 15] = 1.0
		# 둥근 그림자: 뛰어오른 만큼 작게
		var sr := _radius * s * _shadow_scale / (1.0 + SHADOW_SHRINK * hy)
		var so := i * XF
		sbuf[so] = sr
		sbuf[so + 1] = 0.0
		sbuf[so + 2] = 0.0
		sbuf[so + 3] = wx + _shadow_off.x * s
		sbuf[so + 4] = 0.0
		sbuf[so + 5] = 1.0
		sbuf[so + 6] = 0.0
		sbuf[so + 7] = _shadow_lift
		sbuf[so + 8] = 0.0
		sbuf[so + 9] = 0.0
		sbuf[so + 10] = sr
		sbuf[so + 11] = wz + _shadow_off.y * s
		_pick_id[i] = id
		_pick_x[i] = wx
		_pick_z[i] = wz
		if id == _selected:
			_sel_found = true
			_sel_pos = Vector3(wx, 0.0, wz)
		if carry[i] > 0.0:
			var cs := _carry_scale * s
			var co2 := nc * XFC
			cbuf[co2] = cs
			cbuf[co2 + 3] = wx
			cbuf[co2 + 5] = cs
			cbuf[co2 + 7] = _slime_top * tall + hy + _carry_gap + cs * 0.5 + _berry_mid * cs
			cbuf[co2 + 10] = cs
			cbuf[co2 + 11] = wz
			cbuf[co2 + 12] = carry_col.r
			cbuf[co2 + 13] = carry_col.g
			cbuf[co2 + 14] = carry_col.b
			cbuf[co2 + 15] = 1.0
			nc += 1
	# 칸별 세기 되돌리기(다음 프레임에 다시 씀)
	for i in n:
		var c2 := sy[i] * W + sx[i]
		cnt[c2] = 0
		slot[c2] = 0
	if n > 0:
		_slime_mm.buffer = buf
		_shadow_mm.buffer = sbuf
	_carry_count = nc
	if _carry_mm.instance_count > 0:
		_carry_mm.buffer = cbuf
	_carry_mm.visible_instance_count = nc
	_slime_last_us = Time.get_ticks_usec() - t0


## 지금 그려진 위치(없으면 칸 가운데). 마지막 update_view 뒤에 세계가 더 진행했으면 그린 위치가 낡았으므로 칸 가운데.
func _rendered_pos(id: int, i: int) -> Vector3:
	if _shown_tick == world.tick:
		for k in _pick_id.size():
			if _pick_id[k] == id:
				return Vector3(_pick_x[k], 0.0, _pick_z[k])
	return Vector3((float(world.s_x[i]) + 0.5) * _tile, 0.0, (float(world.s_y[i]) + 0.5) * _tile)


## 개체 k 번째 인스턴스의 그려진 위치(검사용). 순서 = 배열 순서(id 오름차순).
func slime_instance_position(k: int) -> Vector3:
	if k < 0 or k >= _slime_mm.instance_count:
		return Vector3.ZERO
	var o := k * XFC
	return Vector3(_slime_buf[o + 3], _slime_buf[o + 7], _slime_buf[o + 11])


func _update_ring() -> void:
	if world == null or _selected < 0 or world.index_of_id(_selected) == -1:
		_ring.visible = false
		return
	var i := world.index_of_id(_selected)
	var p := _sel_pos if _sel_found else _rendered_pos(_selected, i)
	var s := _radius * world.s_size[i] * _ring_scale * (1.0 + _ring_pulse * sin(_anim_time * _ring_pulse_w))
	_ring.visible = true
	_ring.transform = Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(p.x, _ring_lift, p.z))


# ════════════════════════════ 건물 ════════════════════════════

## 저장고·밭 위치가 바뀌었을 때만 다시 쓴다(배열 내용 비교).
func _sync_buildings() -> void:
	if world.store_tiles != _last_stores:
		_last_stores = world.store_tiles.duplicate()
		# 저장고 정면(-Z, 문)을 남쪽(처음 카메라 쪽)으로: Y 축 반 바퀴
		_fill_static(_store_mm, _last_stores, _store_base, 0.0, _store_col, -1.0)
	if world.farms != _last_farms:
		_last_farms = world.farms.duplicate()
		_fill_static(_farm_mm, _last_farms, _farm_base, _farm_lift, _farm_col, 1.0)


## 칸 가운데에 크기 1 로 놓는다. face = 1(그대로) 또는 -1(Y 축 반 바퀴, x·z 뒤집기).
func _fill_static(mm: MultiMesh, cells: PackedInt32Array, base: float, lift: float, col: Color, face: float) -> void:
	var n := cells.size()
	mm.instance_count = n
	if n == 0:
		return
	var buf := PackedFloat32Array()
	buf.resize(n * XFC)
	var W := world.w
	for k in n:
		var c := cells[k]
		var o := k * XFC
		buf[o] = face
		buf[o + 3] = (float(c % W) + 0.5) * _tile
		buf[o + 5] = 1.0
		buf[o + 7] = base + lift
		buf[o + 10] = face
		buf[o + 11] = (float(c / W) + 0.5) * _tile
		buf[o + 12] = col.r
		buf[o + 13] = col.g
		buf[o + 14] = col.b
		buf[o + 15] = 1.0
	mm.buffer = buf


# ════════════════════════════ 빛·카메라 ════════════════════════════

## 낮밤: 해 세기·색, 주변광 세기·색, 배경을 world.light(0 밤 ~ 1 낮)로 섞는다. 밤은 푸르게.
func _update_light() -> void:
	var l := clampf(world.light, 0.0, 1.0)
	_sun.light_energy = lerpf(_light_night, _light_day, l)
	_sun.light_color = _c_light_night.lerp(_c_light_day, l)
	_env.ambient_light_energy = lerpf(_amb_night, _amb_day, l)
	_env.ambient_light_color = _c_amb_night.lerp(_c_amb_day, l)
	_env.background_color = _c_bg_night.lerp(_c_bg_day, l)


## 지도 전체가 들어오게 카메라를 둔다(방위·고각은 처음 값으로).
func _frame_camera() -> void:
	_camera.reset_orientation()
	var aspect := DEFAULT_ASPECT
	if is_inside_tree():
		var vs := get_viewport().get_visible_rect().size
		if vs.y > 0.0:
			aspect = vs.x / vs.y
	_camera.fit_rect(Rect2(0.0, 0.0, float(world.w) * _tile, float(world.h) * _tile), aspect)


## 트리에 들어오면: 자기 SubViewport 의 3D 세계를 따로 쓰게 하고(비교 모드에서 두 지도가 섞이지 않게),
## 뷰포트 크기가 정해지거나 바뀌면 사용자가 카메라를 아직 안 움직였을 때만 다시 맞춘다.
func _enter_tree() -> void:
	var vp := get_viewport()
	if vp is SubViewport and not (vp as SubViewport).own_world_3d:
		vp.set_deferred("own_world_3d", true)
	if not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)
	if world != null and not _camera_touched:
		_frame_camera.call_deferred()


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.disconnect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if world != null and not _camera_touched:
		_frame_camera()


# ════════════════════════════ 입력 ════════════════════════════

## 왼쪽 끌기 = 이동, 휠 = 확대·축소, 오른쪽 끌기 = 회전, 왼쪽 클릭(끌기 아님) = 고르기.
func _unhandled_input(event: InputEvent) -> void:
	var c := _camera
	var before := c.transform
	_handle_input(event, c)
	if c.transform != before:
		_camera_touched = true


func _handle_input(event: InputEvent, c: OrbitCamera) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_left_down = true
					_dragged = false
					_press_pos = mb.position
				elif _left_down:
					_left_down = false
					if not _dragged:
						slime_clicked.emit(pick_slime(mb.position))
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_RIGHT:
				_right_down = mb.pressed
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					var steps := mb.factor if mb.factor > 0.0 else 1.0
					c.zoom_at(mb.position, steps if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -steps)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _left_down and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_left_down = false
		if _right_down and (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) == 0:
			_right_down = false
		if _left_down:
			if not _dragged and mm.position.distance_to(_press_pos) > _click_px:
				_dragged = true
				# 문턱을 넘기까지 움직인 만큼도 함께 끈다
				c.pan_pixels(mm.position - _press_pos - mm.relative, _vp_height())
			if _dragged:
				c.pan_pixels(mm.relative, _vp_height())
			get_viewport().set_input_as_handled()
		elif _right_down:
			c.rotate_pixels(mm.relative)
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		c.zoom_at(mg.position, log(maxf(mg.factor, 0.01)) / log(UiConfig.num("camera.zoom_step")))
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		c.pan_pixels(-pg.delta * UiConfig.num("camera.gesture_pan_px"), _vp_height())
		get_viewport().set_input_as_handled()


func _vp_height() -> float:
	return get_viewport().get_visible_rect().size.y if is_inside_tree() else 1.0
