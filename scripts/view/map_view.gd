class_name MapView
extends Node3D
## 지도 관찰 창(3D). 계약: docs/VIEW-API.md "MapView". 시뮬레이션은 docs/SIM-API.md 의 질의로 읽기만 한다.
##
## 그리기 구성(그리기 호출 수가 개체 수와 무관하도록):
##   땅 = 덩어리마다 ArrayMesh 하나(칸마다 평평한 사각형 + 높이 차이의 옆면, 정점 색). 색은 ui.map.terrain_refresh_ticks 마다
##        위 사각형 부분의 색 영역만 다시 올린다(surface_update_attribute_region).
##   풀포기 = 덩어리마다 MultiMesh 하나. 바닥 먹이·슬라임·운반 열매·저장고·밭 = MultiMesh 하나씩. 선택 고리 = MeshInstance3D 하나.
##   덩어리 = ui.map.chunk_tiles² 칸(기본 지도 64×48 은 덩어리 하나). 큰 지도에서는 식물·땅 색 갱신 한 바퀴를 한 프레임에
##   덩어리 하나씩 나눠 돌고, 먹이량·칸 종류가 바뀐 풀포기·색이 바뀐 칸만 버퍼에 쓰며, 쓴 덩어리만 올린다
##   (한 프레임 비용이 지도 크기가 아니라 덩어리 크기에 비례 — 검토 I52).
## 보간: before_steps() 가 진행 전 위치(id → 칸)를 기억하고, update_view(alpha) 가 그 칸에서 지금 칸으로 옮긴다.
## 두 배열 모두 id 오름차순이므로 사전 없이 두 포인터로 맞춘다. 보간은 언제나 **마지막 한 틱**만:
## LabMain 은 step() 마다 그 직전에 before_steps() 를 불러 기억이 지금 틱의 한 틱 전이 되게 하고,
## 기억이 두 틱 이상 낡았으면(한 번만 부르고 여러 틱 진행) 보간하지 않고 지금 칸에 그린다.
## 겹친 개체의 둘레 자리(겹침 배치·저장고 문 앞)도 이전 틱 자리에서 지금 자리로 함께 보간한다.

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
## 저장고 문(과 문 앞 자리)을 낼 이웃을 찾는 순서(SimGrid 방향 번호: 남·동·서·북 — 처음 카메라 쪽부터).
const DOOR_ORDER: Array[int] = [2, 1, 3, 0]
## 정점 색 RGBA8: 한 채널 최댓값, 불투명 알파 비트(가장 높은 바이트).
const BYTE := 255.0
const OPAQUE := 0xff << 24
## 뷰포트 크기를 아직 모를 때의 화면비.
const DEFAULT_ASPECT := 16.0 / 9.0
## 높이 차이가 이보다 작으면 옆면을 만들지 않음.
const SIDE_EPS := 0.001
## 걸음 중 눌림·늘어남에서 부피를 대략 지키는 지수(가로 = 세로^-1/2).
const VOLUME_EXP := -0.5
## 고리 메시 바깥 반지름(SlimeGeo.ring_mesh, 배율 1). 화면 최소 크기를 반지름으로 바꿀 때 쓴다.
const RING_OUTER := 1.0
var world: SimWorld
var follow_selected := false

var _camera: OrbitCamera
var _sun: DirectionalLight3D
var _env: Environment
## 첫 덩어리의 땅·풀포기(노드 이름 "Terrain"·"Plants"). 덩어리가 여럿이면 나머지는 "Terrain_k"·"Plants_k".
var _terrain_mi: MeshInstance3D
var _plant_mm: MultiMesh
var _drop_mm: MultiMesh
var _slime_mm: MultiMesh
var _carry_mm: MultiMesh
var _shadow_mm: MultiMesh
var _store_mm: MultiMesh
var _farm_mm: MultiMesh
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
## 멀리서(화면 최소 크기로 키운 고리) 쓰는 재질: 깊이 검사 없이 맨 위에 그려 풀·밭·다른 개체에 가리지 않게
var _ring_mat_top: StandardMaterial3D
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
## 옆면 그늘: 물 옆면은 물 색을 이만큼 어둡게, 모든 옆면의 아래 모서리는 위 모서리보다 이만큼 어둡게.
var _water_side_dark := 0.0
var _side_bottom_dark := 0.0
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
## 먹기·줍기 끄덕임: alpha(틱 진행률) 1 당 각도(라디안) = TAU × map.action_bob_per_tick.
var _bob_w := 0.0
## 뛰어오르면 둥근 그림자가 작아지는 정도(높이 1 당).
var _shadow_shrink := 0.0
var _pick_r := 0.0
var _farm_lift := 0.0
var _hop := 0.0
var _squash := 0.0
var _stack := 0.0
## 겹친 개체가 slime.stack_ring 을 넘으면 한 마리마다 둘레를 stack_grow 배씩 넓히되 stack_offset × stack_max_k 까지.
var _stack_ring := 0
var _stack_grow := 0.0
var _stack_max := 0.0
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
var _store_off := 0.0
var _store_arc := 0.0
var _store_arc_max := 0.0
var _occ_scale := 1.0
var _ring_min_px := 0.0
var _slime_min_px := 0.0
var _scale_max := 1.0
var _follow_fps := 60.0

# ── 메시 정보(바닥 맞춤·삼각형 수) ──
var _slime_base := 0.0
var _slime_top := 0.0
var _slime_center := 0.0
## 고르기용 슬라임 메시(지역 좌표): 삼각형(세 점씩), 경계 상자, 원점에서 상자 가장 먼 모서리까지 거리
var _body_tris := PackedVector3Array()
var _body_box := AABB()
var _body_reach := 0.0
var _plant_base := 0.0
var _berry_base := 0.0
var _berry_mid := 0.0
var _store_base := 0.0
var _farm_base := 0.0
## 밭 칸의 땅 높이(흙판 윗면)와 선택 고리를 올릴 높이(이랑 꼭대기). 슬라임·그림자·고리가 흙판에 묻히지 않게.
var _farm_ground := 0.0
var _farm_ring := 0.0
var _tri := {}
var _plant_col := Color.WHITE
var _crop_col := Color.WHITE
var _drop_col := Color.WHITE
var _store_col := Color.WHITE
var _farm_col := Color.WHITE

# ── 덩어리(큰 지도) ──
var _chunk := 64
var _n_chunks := 1
## 덩어리 k 의 칸 범위(행 우선, 덩어리 순서도 행 우선)
var _chunk_rect: Array[Rect2i] = []
var _terrain_mis: Array[MeshInstance3D] = []
var _terrain_meshes: Array[ArrayMesh] = []
var _plant_mms: Array[MultiMesh] = []

# ── 땅 ──
var _n_tiles := 0
## 위 사각형 색(RGBA8, 정점 4개씩)을 덩어리 순서로 이어 붙인 것. 칸 c 의 자리 = _tile_pos[c], 덩어리 k = _tchunk_start[k] ~ [k + 1]
var _top_rgba := PackedInt32Array()
var _tile_pos := PackedInt32Array()
var _tchunk_start := PackedInt32Array()
var _static_rgba := PackedInt32Array()
var _jit := PackedFloat32Array()
var _fert_lo := 0.0
var _fert_inv := 1.0
var _terrain_tris := 0
var _terrain_tick := -1
var _terrain_frames := 0
var _terrain_last_us := 0
## 땅 색 갱신 한 바퀴가 진행 중인지와 다음 덩어리, 이번 프레임에 다시 칠한 칸 수
var _terrain_pass := false
var _terrain_cursor := 0
var _terrain_last_n := 0

# ── 식물·바닥 먹이 ──
var _plant_tile := PackedInt32Array()
var _plant_cs := PackedFloat32Array()
var _plant_sn := PackedFloat32Array()
var _plant_hy := PackedFloat32Array()
var _plant_kind := PackedByteArray()
var _plant_tint := PackedFloat32Array()
var _plant_buf := PackedFloat32Array()
var _plant_inv_ref := 0.0
## 칸 → 풀포기 번호(-1 없음), 풀포기마다 줄이기 전 배율(먹이량, 바뀌었는지 정확히 견주려고 64비트), 슬라임이 서 있어 줄였는지(1)
var _plant_of_tile := PackedInt32Array()
var _plant_s := PackedFloat64Array()
var _plant_occ := PackedByteArray()
var _plant_stamp := PackedInt32Array()
var _stamp := 0
var _shrunk := PackedInt32Array()
var _plant_visible := 0
var _plant_tick := -1
var _plant_frames := 0
var _plant_last_us := 0
## 풀포기는 덩어리 순서로 놓는다: 덩어리 k = _pchunk_start[k] ~ [k + 1], 풀포기 → 덩어리, 덩어리마다 보이는 수·바닥 먹이 칸
var _pchunk_start := PackedInt32Array()
var _plant_chunk := PackedInt32Array()
var _pchunk_vis := PackedInt32Array()
var _chunk_drops: Array[PackedInt32Array] = []
## 버퍼를 고쳐 다시 올려야 할 덩어리(표시·목록)
var _pchunk_dirty := PackedByteArray()
var _dirty_chunks := PackedInt32Array()
## 식물 갱신 한 바퀴가 진행 중인지와 다음 덩어리, 이번 프레임에 본 풀포기 수, 마지막 프레임이 식물 갱신이었는지
var _plant_pass := false
var _plant_cursor := 0
var _plant_last_n := 0
var _last_was_plants := false
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
## 둘레 자리(겹침·저장고 문 앞) [x0, z0, x1, z1, …]: 지금 배열 순서 / 이전 배열 순서. 틱이 바뀔 때만 다시 계산.
var _cur_off := PackedFloat32Array()
var _prev_off := PackedFloat32Array()
var _offsets_tick := -1
## 저장고 칸 표시(칸마다 0 = 저장고 아님, 1 + 문 방향(0~3), 1 + DIR_COUNT = 둘레가 모두 막힘). 저장고 목록이 바뀔 때 다시 만든다.
var _store_mask := PackedByteArray()
## 표시 배율(멀리서 작은 슬라임을 키움, 1 = 실제 크기). update_view 마다 카메라 거리로 정한다.
var _display_k := 1.0
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
	_water_side_dark = UiConfig.num("map.water_side_dark")
	_side_bottom_dark = UiConfig.num("map.side_bottom_dark")
	_terrain_every = maxi(1, UiConfig.integer("map.terrain_refresh_ticks"))
	_terrain_min_frames = maxi(1, UiConfig.integer("map.terrain_min_frames"))
	_plant_every = maxi(1, UiConfig.integer("map.plant_refresh_ticks"))
	_plant_min_frames = maxi(1, UiConfig.integer("map.plant_min_frames"))
	_chunk = maxi(1, UiConfig.integer("map.chunk_tiles"))
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
	_bob_w = TAU * UiConfig.num("map.action_bob_per_tick")
	_shadow_shrink = UiConfig.num("map.blob_shadow_shrink")
	_pick_r = UiConfig.num("map.pick_radius")
	_farm_lift = UiConfig.num("map.farm_lift")
	_hop = UiConfig.num("slime.hop_height")
	_squash = UiConfig.num("slime.squash")
	_stack = UiConfig.num("slime.stack_offset")
	_stack_ring = UiConfig.integer("slime.stack_ring")
	_stack_grow = UiConfig.num("slime.stack_grow")
	_stack_max = stack_max()
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
	_store_off = UiConfig.num("map.store_slime_offset")
	_store_arc = deg_to_rad(UiConfig.num("map.store_slime_arc_deg"))
	_store_arc_max = deg_to_rad(UiConfig.num("map.store_slime_arc_max_deg"))
	_occ_scale = clampf(UiConfig.num("map.plant_occupied_scale"), 0.0, 1.0)
	_ring_min_px = UiConfig.num("map.ring_min_px")
	_slime_min_px = UiConfig.num("map.slime_min_px")
	_scale_max = maxf(1.0, UiConfig.num("map.slime_display_scale_max"))
	_follow_fps = maxf(1.0, UiConfig.num("camera.follow_ref_fps"))


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
	_terrain_mis = [_terrain_mi]
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
	_plant_mms = [_plant_mm]
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
	var disc := _disc_mesh(UiConfig.integer("map.blob_shadow_segments"), UiConfig.num("map.blob_shadow_inner"), UiConfig.num("map.blob_shadow_inner_alpha"))
	_shadow_mm = _add_mm("SlimeShadows", disc, shm, false, false)

	_ring = MeshInstance3D.new()
	_ring.name = "SelectRing"
	_ring.mesh = SlimeGeo.ring_mesh()
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = UiConfig.color("slime.selected_ring_color")
	_ring_mat_top = _ring_mat.duplicate() as StandardMaterial3D
	_ring_mat_top.no_depth_test = true
	_ring_mat_top.render_priority = 1
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)

	# 메시 바닥을 y 0 에 맞추는 값(조각 메시는 원래 바닥 0, 기본 도형 대용품은 가운데가 원점)
	var sa := SlimeGeo.slime_mesh().get_aabb()
	_slime_base = -sa.position.y
	_slime_top = sa.size.y
	_slime_center = sa.size.y * 0.5
	_body_tris = _triangles_of(SlimeGeo.slime_mesh())
	_body_box = sa
	_body_reach = sa.get_center().length() + sa.size.length() * 0.5
	_plant_base = -SlimeGeo.plant_mesh().get_aabb().position.y
	var ba := SlimeGeo.berry_mesh().get_aabb()
	_berry_base = -ba.position.y
	_berry_mid = -(ba.position.y + ba.size.y * 0.5)
	_store_base = -SlimeGeo.storehouse_mesh().get_aabb().position.y
	_farm_base = -SlimeGeo.farm_mesh().get_aabb().position.y
	_farm_ground = _farm_lift + SlimeGeo.FARM_THICK
	_farm_ring = _farm_ground + SlimeGeo.FARM_RIDGE_H
	_tri = {
		slime = SlimeGeo.triangle_count(SlimeGeo.slime_mesh()), plant = SlimeGeo.triangle_count(SlimeGeo.plant_mesh()),
		berry = SlimeGeo.triangle_count(SlimeGeo.berry_mesh()), store = SlimeGeo.triangle_count(SlimeGeo.storehouse_mesh()),
		farm = SlimeGeo.triangle_count(SlimeGeo.farm_mesh()), ring = SlimeGeo.triangle_count(SlimeGeo.ring_mesh()),
		shadow = SlimeGeo.triangle_count(disc),
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
## inner = 안쪽 고리 반지름, inner_alpha = 그 진하기(가운데 1, 바깥 고리는 투명).
static func _disc_mesh(segs: int, inner: float, inner_alpha: float) -> ArrayMesh:
	var v := PackedVector3Array([Vector3.ZERO])
	var cl := PackedColorArray([Color(1, 1, 1, 1)])
	var ix := PackedInt32Array()
	segs = maxi(segs, 6)
	for k in segs:
		var a := TAU * float(k) / float(segs)
		v.append(Vector3(cos(a) * inner, 0.0, sin(a) * inner))
		cl.append(Color(1, 1, 1, inner_alpha))
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


## 메시의 모든 삼각형 꼭짓점(세 점씩, 번호가 없으면 정점 순서대로). 고르기용.
static func _triangles_of(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mesh == null:
		return out
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: Variant = arr[Mesh.ARRAY_INDEX]
		if ix is PackedInt32Array and not (ix as PackedInt32Array).is_empty():
			for k in ix as PackedInt32Array:
				out.append(v[k])
		else:
			out.append_array(v.slice(0, v.size() - v.size() % 3))
	return out


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
	_terrain_pass = false
	_plant_pass = false
	_offsets_tick = -1
	_last_stores = PackedInt32Array()
	_last_farms = PackedInt32Array()
	_store_mask = PackedByteArray()
	# 앞 세계의 건물을 지운다(새 세계도 건물이 없으면 _sync_buildings 가 "바뀜 없음"으로 보고 넘어가므로)
	_store_mm.instance_count = 0
	_farm_mm.instance_count = 0
	_camera_touched = false
	if world == null:
		_set_chunks(0, 0)
		for mm in [_plant_mm, _drop_mm, _slime_mm, _shadow_mm, _carry_mm, _store_mm, _farm_mm]:
			(mm as MultiMesh).instance_count = 0
		return
	_set_chunks(world.w, world.h)
	_n_tiles = world.w * world.h
	_tile_cnt.resize(_n_tiles)
	_tile_cnt.fill(0)
	_tile_slot.resize(_n_tiles)
	_tile_slot.fill(0)
	_store_mask.resize(_n_tiles)
	_store_mask.fill(0)
	_build_terrain()
	_build_plants()
	_frame_camera()
	update_view(1.0)


## 지도(W×H 칸)를 _chunk² 칸 덩어리로 나누고 덩어리마다 땅 MeshInstance3D·풀포기 MultiMesh 노드를 맞춘다
## (첫 덩어리는 늘 있는 "Terrain"·"Plants", 남는 노드는 지움). W·H 가 0 이면 덩어리 하나에 메시 없음.
func _set_chunks(W: int, H: int) -> void:
	var ncx := maxi(1, ceili(float(W) / float(_chunk)))
	var ncy := maxi(1, ceili(float(H) / float(_chunk)))
	_n_chunks = ncx * ncy
	_chunk_rect.clear()
	for cy in ncy:
		for cx in ncx:
			var x0 := cx * _chunk
			var y0 := cy * _chunk
			_chunk_rect.append(Rect2i(x0, y0, mini(_chunk, W - x0), mini(_chunk, H - y0)))
	while _terrain_mis.size() > _n_chunks:
		var mi: MeshInstance3D = _terrain_mis.pop_back()
		remove_child(mi)
		mi.free()
	while _terrain_mis.size() < _n_chunks:
		var mi := MeshInstance3D.new()
		mi.name = "Terrain_%d" % _terrain_mis.size()
		mi.material_override = _terrain_mi.material_override
		add_child(mi)
		_terrain_mis.append(mi)
	while _plant_mms.size() > _n_chunks:
		var mm: MultiMesh = _plant_mms.pop_back()
		var node := get_node_or_null("Plants_%d" % _plant_mms.size())
		if node != null:
			remove_child(node)
			node.free()
		mm.instance_count = 0
	while _plant_mms.size() < _n_chunks:
		_plant_mms.append(_add_mm("Plants_%d" % _plant_mms.size(), SlimeGeo.plant_mesh(), SlimeGeo.shared_material(), true, false))
	_terrain_meshes.resize(_n_chunks)
	for k in _n_chunks:
		_terrain_mis[k].mesh = null
		_terrain_meshes[k] = null


## step() 을 부르기 **직전마다** 호출(LabMain 은 한 프레임에 여러 틱을 돌리면 틱마다 부른다). 보간용으로 지금 위치(id → 칸)를
## 기억한다. 틱이 바뀌었을 때만 복사하므로 같은 틱에 여러 번 불러도 된다. 마지막 기억 = 그린 틱의 한 틱 전.
func before_steps() -> void:
	if world == null or _snap_tick == world.tick:
		return
	_snap_id = world.s_id.duplicate()
	_snap_x = world.s_x.duplicate()
	_snap_y = world.s_y.duplicate()
	_snap_h = world.s_head.duplicate()
	_snap_tick = world.tick


## 지도 전체가 들어오게 카메라를 처음 방위·고각으로 되돌리고 따라가기를 끈다(Home 키·"전체 보기" 단추).
## 사용자가 다시 카메라를 움직이기 전까지는 bind 직후처럼 뷰포트 크기가 바뀌면 다시 맞춘다.
func fit_map() -> void:
	if world == null:
		return
	follow_selected = false
	_frame_camera()
	_camera_touched = false


## 겹친 개체 둘레 반지름의 상한(칸 단위, 타일 크기를 곱하기 전) = ui.slime.stack_offset × ui.slime.stack_max_k.
static func stack_max() -> float:
	return UiConfig.num("slime.stack_offset") * UiConfig.num("slime.stack_max_k")


## 지금 표시 배율(멀리서 작은 슬라임을 키운 배수, 가까이서는 1). 검사·캡처용.
func display_scale() -> float:
	return _display_k


## 매 프레임 step() 뒤에 호출. alpha(0~1) = 마지막 틱의 진행률(보간·통통 튐).
## delta = 이 프레임의 시간(초, 따라가기 카메라의 부드러움을 프레임 빠르기와 무관하게).
func update_view(alpha: float, delta: float = 1.0 / 60.0) -> void:
	if world == null:
		return
	var t := world.tick
	if t != _shown_tick:
		# 이번 프레임에 진행했다: 진행 전 기억을 "이전 위치"로 올린다(버퍼는 맞바꿔 다시 씀).
		# 기억이 한 틱 전이 아니면(여러 틱을 기억 없이 진행) 낡은 출발점에서 미끄러지지 않게 보간하지 않는다.
		if _snap_tick != -1 and _snap_tick == t - 1:
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
	_sync_buildings()
	# 둘레 자리·풀포기 줄이기는 틱이 바뀌었을 때만(같은 틱 안에서는 점유가 그대로)
	if _offsets_tick != t or _cur_off.size() != world.s_id.size() * 2:
		_cur_off = _calc_offsets(world.s_x, world.s_y)
		_prev_off = _calc_offsets(_prev_x, _prev_y) if _has_prev else PackedFloat32Array()
		_update_plant_occupancy()
		_offsets_tick = t
	# 식물과 땅 색: 한 바퀴는 틱이 일정 이상 지났을 때 시작해 한 프레임에 덩어리 하나씩(기본 지도는 덩어리 하나라 한 프레임에 끝).
	# 같은 프레임에 둘 다 하지 않고, 두 바퀴가 함께 진행 중이면 번갈아. 묶은 직후·세계가 되돌아가면 전체를 한 번에.
	_plant_frames += 1
	_terrain_frames += 1
	_plant_last_n = 0
	_terrain_last_n = 0
	var did_plants := false
	var plants_due := _plant_pass or (t - _plant_tick >= _plant_every and _plant_frames >= _plant_min_frames)
	var terrain_due := _terrain_pass or (t - _terrain_tick >= _terrain_every and _terrain_frames >= _terrain_min_frames)
	if _plant_tick == -1 or t < _plant_tick:
		_refresh_plants(true)
		did_plants = true
	elif plants_due and not (terrain_due and _last_was_plants):
		_refresh_plants(false)
		did_plants = true
	elif not _dirty_chunks.is_empty():
		_upload_plant_chunks()
	if _terrain_tick == -1 or t < _terrain_tick:
		_recolor_terrain(true)
	elif not did_plants and terrain_due:
		_recolor_terrain(false)
	_last_was_plants = did_plants
	_display_k = _calc_display_scale()
	_update_slimes(clampf(alpha, 0.0, 1.0))
	_update_light()
	_update_ring()
	if follow_selected and _sel_found:
		_camera_touched = true
		# 프레임 빠르기와 무관하게: follow_lerp 는 기준 프레임(follow_ref_fps) 한 장에 좁히는 몫
		var k := clampf(1.0 - pow(1.0 - _follow_k, maxf(delta, 0.0) * _follow_fps), 0.0, 1.0)
		_camera.target = _camera.target.lerp(Vector3(_sel_pos.x, 0.0, _sel_pos.z), k)
		_camera.apply()


## 선택 표시(-1 = 없음). 죽은 개체면 표시하지 않는다.
func set_selected(id: int) -> void:
	_selected = id
	_sel_found = false
	_update_ring()


## 뷰포트 좌표의 광선으로 살아 있는 슬라임 id 를 고른다(없으면 -1).
## ① 그린 몸(인스턴스 변환 = 크기·표시 배율·늘어남·뜀·땅 높이를 입힌 슬라임 메시 삼각형)에 광선이 맞는 개체 가운데
##    가장 앞(카메라에 가장 가까운) 것 — 겹친 칸·낮은 고각에서도 보이는 앞 개체를 고른다(검토 I53).
## ② 아무 몸에도 맞지 않으면 광선을 슬라임 중심 높이의 수평면과 교차해 pick_radius × 표시 배율 칸 안의 가장 가까운
##    (그려진 위치 기준) 개체 — 작은 몸의 둘레를 눌러도 고를 수 있게.
func pick_slime(screen_pos: Vector2) -> int:
	if world == null or not _camera.is_inside_tree():
		return -1
	var hit := _pick_body(screen_pos)
	if hit != -1:
		return hit
	# 표시 배율로 키운 몸에 맞춰 교차 높이·반경도 키운다
	var g: Variant = _camera.ground_point(screen_pos, _slime_center * _display_k)
	if g == null:
		return -1
	var p: Vector3 = g
	var best := -1
	var pr := _pick_r * _tile * _display_k
	var best_d := pr * pr
	for i in _pick_id.size():
		var dx := _pick_x[i] - p.x
		var dz := _pick_z[i] - p.z
		var d := dx * dx + dz * dz
		if d < best_d:
			best_d = d
			best = _pick_id[i]
	return best


## 광선이 맞는 그린 몸(슬라임 메시 삼각형) 가운데 가장 앞 개체의 id(없으면 -1). 몸을 감싸는 구 → 지역 경계 상자로 먼저
## 거르고(이미 찾은 것보다 뒤면 건너뜀) 남은 개체만 삼각형을 본다. 광선 매개변수 t 는 지역 좌표로 바꿔도 같아 개체끼리 견준다.
func _pick_body(screen_pos: Vector2) -> int:
	var o := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var buf := _slime_buf
	var tris := _body_tris
	var n := mini(_pick_id.size(), _slime_mm.instance_count)
	var best := -1
	var best_t := INF
	for i in n:
		var b := i * XFC
		var bs := Basis(Vector3(buf[b], buf[b + 4], buf[b + 8]), Vector3(buf[b + 1], buf[b + 5], buf[b + 9]),
				Vector3(buf[b + 2], buf[b + 6], buf[b + 10]))
		var org := Vector3(buf[b + 3], buf[b + 7], buf[b + 11])
		var sc := bs.get_scale()
		var k := maxf(sc.x, maxf(sc.y, sc.z))
		var to := org - o
		if k <= 0.0 or (to - dir * to.dot(dir)).length() > _body_reach * k:
			continue
		var inv := Transform3D(bs, org).affine_inverse()
		var lo := inv * o
		var ld := inv.basis * dir
		var ll := ld.length_squared()
		var entry: Variant = _body_box.intersects_ray(lo, ld)
		if entry == null or ll <= 0.0 or ((entry as Vector3) - lo).dot(ld) / ll >= best_t:
			continue
		for q in range(0, tris.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(lo, ld, tris[q], tris[q + 1], tris[q + 2])
			if hit == null:
				continue
			var t := ((hit as Vector3) - lo).dot(ld) / ll
			if t >= 0.0 and t < best_t:
				best_t = t
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


## 성능 기록용 수치. plants = 먹이가 있어 보이는 풀포기 수, triangles_estimate = 그리기에 넘기는 삼각형
## (숨긴 풀포기도 배율 0 인스턴스로 넘어가므로 풀포기 인스턴스 전부 + 슬라임 발밑 그림자 포함).
## chunks = 덩어리 수, plant_n·terrain_n = 이번 프레임에 다시 본 풀포기·칸 수(갱신이 없었으면 0), *_us = 마지막 갱신 시간.
func view_stats() -> Dictionary:
	if world == null:
		return {slimes = 0, plants = 0, stores = 0, farms = 0, triangles_estimate = 0, chunks = 0, plant_n = 0, terrain_n = 0}
	var n := world.s_id.size()
	var tris := _terrain_tris + n * (int(_tri.slime) + int(_tri.shadow)) + _plant_tile.size() * int(_tri.plant)
	tris += (_drop_count + _carry_count) * int(_tri.berry)
	tris += world.store_tiles.size() * int(_tri.store) + world.farms.size() * int(_tri.farm)
	if _ring.visible:
		tris += int(_tri.ring)
	return {
		slimes = n, plants = _plant_visible, stores = world.store_tiles.size(), farms = world.farms.size(),
		triangles_estimate = tris, chunks = _n_chunks, plant_n = _plant_last_n, terrain_n = _terrain_last_n,
		slime_us = _slime_last_us, plant_us = _plant_last_us, terrain_us = _terrain_last_us,
	}


# ════════════════════════════ 땅 ════════════════════════════

## 덩어리마다 땅 메시 하나: 앞부분 = 칸마다 위 사각형(덩어리 안 행 우선, 정점 4개), 뒷부분 = 높이 차이·지도 가장자리 옆면.
## 위 사각형의 색만 바뀌므로(풀밭 ↔ 밭, 먹이량, 계절) 색 영역 앞부분만 다시 올리면 된다. 덩어리 하나(기본 지도)면 칸 순서 그대로.
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

	_tile_pos.resize(n)
	_tchunk_start.resize(_n_chunks + 1)
	_terrain_tris = 0
	var pos := 0
	for k in _n_chunks:
		_tchunk_start[k] = pos
		var r := _chunk_rect[k]
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		_terrain_quads(r, heights, verts, norms, cols, idx)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				_tile_pos[y * W + x] = pos
				pos += 1
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_terrain_meshes[k] = mesh
		_terrain_mis[k].mesh = mesh
		_terrain_mis[k].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_terrain_tris += idx.size() / 3
	_tchunk_start[_n_chunks] = pos
	_top_rgba.resize(n * 4)
	# 새 메시는 흰색이라 모든 칸을 "바뀜"으로(색 값에는 늘 불투명 알파가 있어 0 과 같지 않다)
	_top_rgba.fill(0)
	_recolor_terrain(true)


## 덩어리 r 의 땅 사각형: ① 위 사각형(행 우선) ② 옆면 — 이웃(또는 지도 밖 = 바닥 깊이)이 더 낮은 쪽 모서리마다.
func _terrain_quads(r: Rect2i, heights: PackedFloat32Array, verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, idx: PackedInt32Array) -> void:
	var W := world.w
	var H := world.h
	var tl := _tile
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var x0 := float(x) * tl
			var z0 := float(y) * tl
			var hy := heights[y * W + x]
			_quad(verts, norms, cols, idx,
				Vector3(x0, hy, z0), Vector3(x0 + tl, hy, z0), Vector3(x0 + tl, hy, z0 + tl), Vector3(x0, hy, z0 + tl),
				Vector3.UP, Color.WHITE)
	var floor_y := -_water_depth - _skirt
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := y * W + x
			var hc := heights[c]
			var kind := world.tiles[c]
			var side := _c_bank
			if kind == SimGrid.TILE_ROCK:
				side = Color(_c_rock.r * _rock_side, _c_rock.g * _rock_side, _c_rock.b * _rock_side)
			elif kind == SimGrid.TILE_WATER:
				side = _c_water.darkened(_water_side_dark)
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
				var lo_shade := side.darkened(_side_bottom_dark)
				_quad_grad(verts, norms, cols, idx,
					Vector3(a.x, hc, a.z), Vector3(b.x, hc, b.z), Vector3(b.x, hn, b.z), Vector3(a.x, hn, a.z),
					nrm, side, lo_shade)


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
## 칸마다 RGBA8 정수 하나를 정점 4개에 넣고, 색이 바뀐 칸이 있는 덩어리만 색 영역 앞부분을 올린다.
## full = 모든 덩어리를 지금(묶은 직후·세계가 되돌아감), 아니면 진행 중인 한 바퀴의 다음 덩어리 하나(없으면 새 바퀴를 시작).
func _recolor_terrain(full: bool) -> void:
	var t0 := Time.get_ticks_usec()
	if full or not _terrain_pass:
		_terrain_pass = true
		_terrain_cursor = 0
		_terrain_tick = world.tick
	var tint := Color.WHITE
	if world.season >= 0 and world.season < _season_tints.size():
		tint = Color.WHITE.lerp(_season_tints[world.season], _season_k)
	var last := _n_chunks if full else _terrain_cursor + 1
	var done := 0
	while _terrain_cursor < last:
		done += _recolor_chunk(_terrain_cursor, tint)
		_terrain_cursor += 1
	if _terrain_cursor >= _n_chunks:
		_terrain_pass = false
		_terrain_frames = 0
	_terrain_last_n = done
	_terrain_last_us = Time.get_ticks_usec() - t0


## 덩어리 k 의 위 사각형 색을 다시 계산해 바뀐 칸만 쓰고, 하나라도 바뀌었으면 그 메시의 색 영역을 올린다. 본 칸 수.
func _recolor_chunk(k: int, tint: Color) -> int:
	var tiles := world.tiles
	var fert := world.fert
	var food := world.food
	var cap := world.food_cap
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
	var W := world.w
	var r := _chunk_rect[k]
	var o := _tchunk_start[k] * 4
	var changed := false
	for y in range(r.position.y, r.end.y):
		for c in range(y * W + r.position.x, y * W + r.end.x):
			var kind := tiles[c]
			var v := 0
			if kind == SimGrid.TILE_GRASS:
				var u := clampf((fert[c] - lo) * inv, 0.0, 1.0)
				var cr := pr + rr * u
				var cg := pg + rg * u
				var cb := pb + rb * u
				var cp := cap[c]
				if cp > 0.0:
					var f := food[c] / cp * fk
					cr += (fr - cr) * f
					cg += (fg - cg) * f
					cb += (fb - cb) * f
				var j := _jit[c] * BYTE
				v = (int(clampf(cr * j, 0.0, BYTE)) | (int(clampf(cg * j, 0.0, BYTE)) << 8)
					| (int(clampf(cb * j, 0.0, BYTE)) << 16) | OPAQUE)
			elif kind == SimGrid.TILE_FARM:
				var j2 := _jit[c]
				v = _rgba(farm.r * j2, farm.g * j2, farm.b * j2)
			else:
				v = _static_rgba[c]
			if out[o] != v:
				out[o] = v
				out[o + 1] = v
				out[o + 2] = v
				out[o + 3] = v
				changed = true
			o += 4
	if changed:
		var a := _tchunk_start[k] * 4
		var region := out if _n_chunks == 1 else out.slice(a, _tchunk_start[k + 1] * 4)
		_terrain_meshes[k].surface_update_attribute_region(0, 0, region.to_byte_array())
	return r.size.x * r.size.y


## 정점 색 영역 한 칸(RGBA8, 작은 쪽 바이트가 R).
static func _rgba(r: float, g: float, b: float) -> int:
	return Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0)).to_abgr32()


## 칸 c 의 지금 위 사각형 색(검사용).
func terrain_tile_color(c: int) -> Color:
	if c < 0 or c >= _tile_pos.size() or _tile_pos[c] * 4 >= _top_rgba.size():
		return Color.BLACK
	var v := _top_rgba[_tile_pos[c] * 4]
	return Color8(v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff)


# ════════════════════════════ 식물·바닥 먹이 ════════════════════════════

## 통과 가능 칸마다 풀포기 하나(물·바위는 바뀌지 않으므로 개수는 고정). 칸 안 위치·방향·키·밝기는 칸 해시.
## 풀포기는 덩어리 순서(덩어리 안 행 우선)로 놓는다 — 덩어리 하나(기본 지도)면 칸 순서 그대로.
func _build_plants() -> void:
	_plant_tile = PackedInt32Array()
	_plant_chunk = PackedInt32Array()
	_pchunk_start.resize(_n_chunks + 1)
	var W0 := world.w
	for k in _n_chunks:
		_pchunk_start[k] = _plant_tile.size()
		var r := _chunk_rect[k]
		for y in range(r.position.y, r.end.y):
			for c in range(y * W0 + r.position.x, y * W0 + r.end.x):
				if SimGrid.passable(world.tiles[c]):
					_plant_tile.append(c)
					_plant_chunk.append(k)
	_pchunk_start[_n_chunks] = _plant_tile.size()
	_pchunk_vis.resize(_n_chunks)
	_pchunk_vis.fill(0)
	_pchunk_dirty.resize(_n_chunks)
	_pchunk_dirty.fill(0)
	_dirty_chunks = PackedInt32Array()
	_chunk_drops.resize(_n_chunks)
	for k in _n_chunks:
		_chunk_drops[k] = PackedInt32Array()
		_plant_mms[k].instance_count = _pchunk_start[k + 1] - _pchunk_start[k]
	var n := _plant_tile.size()
	_plant_cs.resize(n)
	_plant_sn.resize(n)
	_plant_hy.resize(n)
	_plant_tint.resize(n)
	_plant_kind.resize(n)
	_plant_s.resize(n)
	_plant_s.fill(0.0)
	_plant_occ.resize(n)
	_plant_occ.fill(0)
	_plant_stamp.resize(n)
	_plant_stamp.fill(0)
	_stamp = 0
	_shrunk = PackedInt32Array()
	_plant_of_tile.resize(_n_tiles)
	_plant_of_tile.fill(-1)
	for k in n:
		_plant_of_tile[_plant_tile[k]] = k
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


## 풀포기 크기(먹이량 비례, 거의 없으면 0 = 숨김)와 바닥 먹이 열매를 다시 쓴다. 먹이량 배율·칸 종류가 바뀐 풀포기만 버퍼에 쓰고
## 쓴 덩어리만 올린다. full = 모든 덩어리를 지금(묶은 직후·세계가 되돌아감), 아니면 진행 중인 한 바퀴의 다음 덩어리 하나
## (없으면 새 바퀴를 시작) — 한 프레임 비용이 지도 크기가 아니라 덩어리 크기(ui.map.chunk_tiles²)에 비례한다.
func _refresh_plants(full: bool) -> void:
	var t0 := Time.get_ticks_usec()
	if full or not _plant_pass:
		_plant_pass = true
		_plant_cursor = 0
		_plant_tick = world.tick
	var last := _n_chunks if full else _plant_cursor + 1
	var done := 0
	while _plant_cursor < last:
		done += _refresh_plant_chunk(_plant_cursor)
		_plant_cursor += 1
	if _plant_cursor >= _n_chunks:
		_plant_pass = false
		_plant_frames = 0
	var vis := 0
	var nd := 0
	for k in _n_chunks:
		vis += _pchunk_vis[k]
		var drops := _chunk_drops[k]
		for c in drops:
			_drop_tiles[nd] = c
			nd += 1
	_plant_visible = vis
	_upload_plant_chunks()
	_write_dropped(nd)
	_plant_last_n = done
	_plant_last_us = Time.get_ticks_usec() - t0


## 덩어리 j 의 풀포기: 배율을 다시 계산해 바뀐 것만 버퍼에 쓰고(쓰면 덩어리를 올릴 목록에), 보이는 수·바닥 먹이 칸을 센다. 본 풀포기 수.
func _refresh_plant_chunk(j: int) -> int:
	var food := world.food
	var tiles := world.tiles
	var dropped := world.dropped
	var buf := _plant_buf
	var inv := _plant_inv_ref
	var hide := _p_hide
	var smin := _p_min
	var sspan := _p_max - _p_min
	var base := _plant_base
	var occ := _plant_occ
	var ps := _plant_s
	var vis := 0
	var drops := PackedInt32Array()
	var wrote := false
	var k0 := _pchunk_start[j]
	var k1 := _pchunk_start[j + 1]
	for k in range(k0, k1):
		var c := _plant_tile[k]
		var f := food[c] * inv
		var s := 0.0
		if f > hide:
			s = smin + sspan * minf(f, 1.0)
			vis += 1
		if dropped[c] > 0.0:
			drops.append(c)
		var kind := tiles[c]
		if s == ps[k] and kind == _plant_kind[k]:
			continue
		wrote = true
		ps[k] = s
		# 슬라임이 서 있는 칸의 풀포기는 몸을 뚫고 나오지 않게 줄인다(_update_plant_occupancy)
		if occ[k] != 0:
			s *= _occ_scale
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
		if kind != _plant_kind[k]:
			# 풀밭 ↔ 밭: 색만 바꿈(대용품 메시일 때만 밭 작물 색)
			_plant_kind[k] = kind
			var col := _crop_col if kind == SimGrid.TILE_FARM else _plant_col
			var b := _plant_tint[k]
			buf[o + 12] = col.r * b
			buf[o + 13] = col.g * b
			buf[o + 14] = col.b * b
			buf[o + 15] = 1.0
	_pchunk_vis[j] = vis
	_chunk_drops[j] = drops
	if wrote:
		_mark_plant_chunk(j)
	return k1 - k0


## 덩어리 j 의 풀포기 버퍼를 다시 올려야 한다고 적는다.
func _mark_plant_chunk(j: int) -> void:
	if _pchunk_dirty[j] == 0:
		_pchunk_dirty[j] = 1
		_dirty_chunks.append(j)


## 적어 둔 덩어리의 풀포기 버퍼만 올린다(덩어리 하나면 버퍼 전체 그대로).
func _upload_plant_chunks() -> void:
	for j in _dirty_chunks:
		_pchunk_dirty[j] = 0
		var a := _pchunk_start[j]
		var b := _pchunk_start[j + 1]
		if b > a:
			_plant_mms[j].buffer = _plant_buf if _n_chunks == 1 else _plant_buf.slice(a * XFC, b * XFC)
	_dirty_chunks = PackedInt32Array()


## 슬라임이 서 있는(또는 이번 틱에 떠난) 칸의 풀포기를 map.plant_occupied_scale 배로 줄이고, 비게 된 칸은 되돌린다.
## 틱이 바뀔 때만 부르고, 바뀐 풀포기의 변환만 버퍼에 다시 쓴다(올리기는 update_view 가 바뀐 덩어리만 한 번).
func _update_plant_occupancy() -> void:
	if _occ_scale >= 1.0 or _plant_occ.size() != _plant_tile.size() or _plant_of_tile.size() != _n_tiles:
		return
	_stamp += 1
	var now := PackedInt32Array()
	var W := world.w
	for pass_i in 2:
		var xs := world.s_x if pass_i == 0 else _prev_x
		var ys := world.s_y if pass_i == 0 else _prev_y
		if pass_i == 1 and not _has_prev:
			break
		for i in xs.size():
			var p := _plant_of_tile[ys[i] * W + xs[i]]
			if p < 0 or _plant_stamp[p] == _stamp:
				continue
			_plant_stamp[p] = _stamp
			now.append(p)
			if _plant_occ[p] == 0:
				_plant_occ[p] = 1
				_write_plant_basis(p)
	for p in _shrunk:
		if _plant_stamp[p] != _stamp:
			_plant_occ[p] = 0
			_write_plant_basis(p)
	_shrunk = now


## 풀포기 k 의 3×3 기저(방향·배율)만 다시 쓴다(먹이량 배율 × 점유 줄이기). 덩어리 하나(기본 지도)면 덩어리째 올리게 적고,
## 여럿이면 그 인스턴스 하나만 바로 보낸다(개체가 여러 덩어리에 흩어져도 덩어리 버퍼 전체를 다시 올리지 않게).
func _write_plant_basis(k: int) -> void:
	var s := _plant_s[k] * (_occ_scale if _plant_occ[k] != 0 else 1.0)
	var o := k * XFC
	var cs := _plant_cs[k] * s
	var sn := _plant_sn[k] * s
	var sy := s * _plant_hy[k]
	_plant_buf[o] = cs
	_plant_buf[o + 2] = sn
	_plant_buf[o + 5] = sy
	_plant_buf[o + 7] = _plant_base * sy
	_plant_buf[o + 8] = -sn
	_plant_buf[o + 10] = cs
	var j := _plant_chunk[k]
	if _n_chunks == 1 or _pchunk_dirty[j] != 0:
		_mark_plant_chunk(j)
	else:
		_plant_mms[j].set_instance_transform(k - _pchunk_start[j], Transform3D(Vector3(cs, 0.0, -sn), Vector3(0.0, sy, 0.0),
				Vector3(sn, 0.0, cs), Vector3(_plant_buf[o + 3], _plant_buf[o + 7], _plant_buf[o + 11])))


## 칸 c 의 땅 높이(밭은 흙판 윗면, 나머지 0 — 물·바위 칸에는 슬라임이 서지 않음).
func _ground_at(c: int) -> float:
	return _farm_ground if world.tiles[c] == SimGrid.TILE_FARM else 0.0


## 칸 점유에 따른 둘레 자리 [x0, z0, x1, z1, …](배열 순서 = id 오름차순 = 칸 안 자리 순서).
## 여러 개체가 한 칸에 있으면 slime.stack_offset 둘레에 나누고, 저장고 칸이면 움집 안에 묻히지 않게
## 문 앞(_door_dir: 지나갈 수 있는 이웃 쪽, 보통 남쪽 +Z) 반지름 map.store_slime_offset 의 호에 나눠 세운다.
## 이전 틱 배열로도 불러 둘레 자리를 보간한다.
func _calc_offsets(xs: PackedInt32Array, ys: PackedInt32Array) -> PackedFloat32Array:
	var n := xs.size()
	var out := PackedFloat32Array()
	out.resize(n * 2)
	if n == 0 or _tile_cnt.size() != _n_tiles:
		return out
	var W := world.w
	var cnt := _tile_cnt
	var slot := _tile_slot
	var stores := _store_mask.size() == _n_tiles
	var tl := _tile
	for i in n:
		cnt[ys[i] * W + xs[i]] += 1
	for i in n:
		var c := ys[i] * W + xs[i]
		var m := cnt[c]
		var k := slot[c]
		slot[c] = k + 1
		var ox := 0.0
		var oz := 0.0
		if stores and _store_mask[c] != 0:
			var step := _store_arc if m < 2 else minf(_store_arc, _store_arc_max / float(m - 1))
			var a := (float(k) - float(m - 1) * 0.5) * step
			# 문 방향 이웃 쪽(지나갈 수 있는 칸)으로. 둘레가 모두 막힌 저장고는 남쪽, 몸이 칸 밖으로 나가지 않는 반지름까지만
			var d := int(_store_mask[c]) - 1
			var r := _store_off
			var face := 0.0
			if d < SimGrid.DIR_COUNT:
				face = atan2(float(SimGrid.DX[d]), float(SimGrid.DY[d]))
			else:
				r = minf(_store_off, 0.5 - _radius)
			ox = sin(face + a) * r * tl
			oz = cos(face + a) * r * tl
		elif m > 1:
			var ang := TAU * (float(k) / float(m) + _hash01(c, SALT_STACK))
			var r := minf(_stack * (1.0 + _stack_grow * float(maxi(0, m - _stack_ring))), _stack_max) * tl
			ox = cos(ang) * r
			oz = sin(ang) * r
		out[i * 2] = ox
		out[i * 2 + 1] = oz
	# 칸별 세기 되돌리기(다음에 다시 씀)
	for i in n:
		var c2 := ys[i] * W + xs[i]
		cnt[c2] = 0
		slot[c2] = 0
	return out


## 표시 배율: 카메라 목표 거리에서 크기 1 슬라임의 화면 지름이 map.slime_min_px 보다 작으면 그만큼 키운다
## (최대 map.slime_display_scale_max). 가까이(focus_distance 근처)서는 1 = 실제 크기. 시뮬레이션과 무관.
func _calc_display_scale() -> float:
	if _slime_min_px <= 0.0 or not is_inside_tree() or not _camera.is_inside_tree():
		return 1.0
	var px_per_unit := _vp_height() / maxf(2.0 * tan(deg_to_rad(_camera.fov) * 0.5) * _camera.distance, 0.0001)
	var slime_px := 2.0 * _radius * px_per_unit
	if slime_px <= 0.0:
		return 1.0
	return clampf(_slime_min_px / slime_px, 1.0, _scale_max)


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

## 개체마다 위치(이전 칸 → 지금 칸 보간, 둘레 자리도 이전 → 지금 보간)·방향·통통 튐·눌림·숨쉬기·색을 MultiMesh 버퍼에 쓴다.
## 밭 칸에서는 흙판 위에 올리고(땅 높이도 보간), 표시 배율(_display_k)만큼 몸·그림자·열매를 키운다(자리는 그대로).
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
	var co_off := _cur_off
	var po_off := _prev_off
	var e := alpha * alpha * (3.0 - 2.0 * alpha)
	var hop_s := sin(PI * alpha)
	var sq_s := sin(TAU * alpha)
	var bob_s := sin(_bob_w * alpha)
	var tl := _tile
	var dk := _display_k
	var pn := _prev_id.size() if _has_prev and po_off.size() == _prev_id.size() * 2 else 0
	var pid := _prev_id
	var j := 0
	var buf := _slime_buf
	var sbuf := _shadow_buf
	var cbuf := _carry_buf
	var nc := 0
	var carry_col := _drop_col
	# 밤에는 슬라임 색을 조금 밝혀 어둠 속에서도 계통 색이 읽히게
	var gain := lerpf(_night_boost, 1.0, clampf(world.light, 0.0, 1.0))
	var stage := world.stage
	_sel_found = false
	for i in n:
		var id := ids[i]
		var x := sx[i]
		var y := sy[i]
		var hd := sh[i]
		var c := y * W + x
		var ox := co_off[i * 2]
		var oz := co_off[i * 2 + 1]
		var px := x
		var py := y
		var ph := hd
		var pox := ox
		var poz := oz
		if pn > 0:
			while j < pn and pid[j] < id:
				j += 1
			if j < pn and pid[j] == id:
				px = _prev_x[j]
				py = _prev_y[j]
				ph = _prev_h[j]
				pox = po_off[j * 2]
				poz = po_off[j * 2 + 1]
		var wx := lerpf((float(px) + 0.5) * tl + pox, (float(x) + 0.5) * tl + ox, e)
		var wz := lerpf((float(py) + 0.5) * tl + poz, (float(y) + 0.5) * tl + oz, e)
		var g := _ground_at(c)
		if px != x or py != y:
			g = lerpf(_ground_at(py * W + px), g, e)
		var s := size[i] * dk
		var hy := 0.0
		var stretch := 1.0
		if px != x or py != y:
			hy = _hop * s * hop_s
			stretch = 1.0 + _squash * sq_s
		else:
			# 먹기·줍기·심기 눌림. 아직 열리지 않은 줍기·심기(발견 전의 효과 없는 시도)는 정보 창처럼 "하는 중" 으로 보이지 않게
			# 숨쉬기만(InfoPanel.is_attempt — 검토 I86 의 지도 몫)
			var a := act[i]
			if a == SimBrain.ACT_EAT or ((a == SimBrain.ACT_GATHER or a == SimBrain.ACT_PLANT) and not InfoPanel.is_attempt(a, stage)):
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
		buf[o + 7] = _slime_base * tall + hy + g
		buf[o + 8] = -si * wide
		buf[o + 9] = 0.0
		buf[o + 10] = co * wide
		buf[o + 11] = wz
		var col := Color.from_hsv(hue[id], _sat, _val)
		buf[o + 12] = col.r * gain
		buf[o + 13] = col.g * gain
		buf[o + 14] = col.b * gain
		buf[o + 15] = 1.0
		# 둥근 그림자: 뛰어오른 만큼 작게(땅 높이 위)
		var sr := _radius * s * _shadow_scale / (1.0 + _shadow_shrink * hy)
		var so := i * XF
		sbuf[so] = sr
		sbuf[so + 1] = 0.0
		sbuf[so + 2] = 0.0
		sbuf[so + 3] = wx + _shadow_off.x * s
		sbuf[so + 4] = 0.0
		sbuf[so + 5] = 1.0
		sbuf[so + 6] = 0.0
		sbuf[so + 7] = _shadow_lift + g
		sbuf[so + 8] = 0.0
		sbuf[so + 9] = 0.0
		sbuf[so + 10] = sr
		sbuf[so + 11] = wz + _shadow_off.y * s
		_pick_id[i] = id
		_pick_x[i] = wx
		_pick_z[i] = wz
		if id == _selected:
			_sel_found = true
			_sel_pos = Vector3(wx, g, wz)
		if carry[i] > 0.0:
			var cs := _carry_scale * s
			var co2 := nc * XFC
			cbuf[co2] = cs
			cbuf[co2 + 3] = wx
			cbuf[co2 + 5] = cs
			cbuf[co2 + 7] = _slime_top * tall + hy + g + _carry_gap * dk + cs * 0.5 + _berry_mid * cs
			cbuf[co2 + 10] = cs
			cbuf[co2 + 11] = wz
			cbuf[co2 + 12] = carry_col.r
			cbuf[co2 + 13] = carry_col.g
			cbuf[co2 + 14] = carry_col.b
			cbuf[co2 + 15] = 1.0
			nc += 1
	if n > 0:
		_slime_mm.buffer = buf
		_shadow_mm.buffer = sbuf
	_carry_count = nc
	if _carry_mm.instance_count > 0:
		_carry_mm.buffer = cbuf
	_carry_mm.visible_instance_count = nc
	_slime_last_us = Time.get_ticks_usec() - t0


## 지금 그려진 위치(없으면 칸 가운데, y = 땅 높이). 마지막 update_view 뒤에 세계가 더 진행했으면 그린 위치가 낡았으므로 칸 가운데.
func _rendered_pos(id: int, i: int) -> Vector3:
	var c := world.s_y[i] * world.w + world.s_x[i]
	if _shown_tick == world.tick:
		for k in _pick_id.size():
			if _pick_id[k] == id:
				return Vector3(_pick_x[k], _ground_at(c), _pick_z[k])
	return Vector3((float(world.s_x[i]) + 0.5) * _tile, _ground_at(c), (float(world.s_y[i]) + 0.5) * _tile)


## 개체 k 번째 인스턴스의 그려진 위치(검사용). 순서 = 배열 순서(id 오름차순).
func slime_instance_position(k: int) -> Vector3:
	if k < 0 or k >= _slime_mm.instance_count:
		return Vector3.ZERO
	var o := k * XFC
	return Vector3(_slime_buf[o + 3], _slime_buf[o + 7], _slime_buf[o + 11])


## k 번째 슬라임 인스턴스의 축별 배율(가로 = 기저 0열 길이, 세로, 앞뒤). 크기 × 표시 배율 × 늘어남(검사용).
func slime_instance_scale(k: int) -> Vector3:
	if k < 0 or k >= _slime_mm.instance_count:
		return Vector3.ZERO
	var o := k * XFC
	return Vector3(Vector2(_slime_buf[o], _slime_buf[o + 8]).length(), _slime_buf[o + 5], Vector2(_slime_buf[o + 2], _slime_buf[o + 10]).length())


## 칸 c 의 풀포기 세로 배율 (그린 값, 먹이량만으로 정한 값). 풀포기가 없으면 (-1, -1). 검사용.
func plant_scale_at(c: int) -> Vector2:
	if c < 0 or c >= _plant_of_tile.size() or _plant_of_tile[c] < 0:
		return Vector2(-1.0, -1.0)
	var k := _plant_of_tile[c]
	return Vector2(_plant_buf[k * XFC + 5], _plant_s[k] * _plant_hy[k])


## k 번째 슬라임 그림자 인스턴스의 위치(검사용).
func shadow_instance_position(k: int) -> Vector3:
	if k < 0 or k >= _shadow_mm.instance_count:
		return Vector3.ZERO
	var o := k * XF
	return Vector3(_shadow_buf[o + 3], _shadow_buf[o + 7], _shadow_buf[o + 11])


## 선택 고리: 개체 발밑(밭 칸이면 이랑 위). 실제 크기 = 반지름 × 크기 × ring_scale × 표시 배율이고,
## 그 화면 지름이 map.ring_min_px 보다 작으면(멀리서 본 전경) 최소 크기로 키우고 맨 위에 그린다(풀·밭·다른 개체에 안 가림).
func _update_ring() -> void:
	if world == null or _selected < 0 or world.index_of_id(_selected) == -1:
		_ring.visible = false
		return
	var i := world.index_of_id(_selected)
	var p := _sel_pos if _sel_found else _rendered_pos(_selected, i)
	var c := world.s_y[i] * world.w + world.s_x[i]
	var y := (_farm_ring if world.tiles[c] == SimGrid.TILE_FARM else p.y) + _ring_lift
	var s := _radius * world.s_size[i] * _ring_scale * _display_k
	var far := false
	if _ring_min_px > 0.0 and _camera.is_inside_tree():
		var d := _camera.global_position.distance_to(Vector3(p.x, y, p.z))
		var per_px := 2.0 * d * tan(deg_to_rad(_camera.fov) * 0.5) / maxf(_vp_height(), 1.0)
		var min_s := _ring_min_px * 0.5 * per_px / RING_OUTER
		if min_s > s:
			s = min_s
			far = true
	s *= 1.0 + _ring_pulse * sin(_anim_time * _ring_pulse_w)
	var mat := _ring_mat_top if far else _ring_mat
	if _ring.material_override != mat:
		_ring.material_override = mat
	_ring.visible = true
	_ring.transform = Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(p.x, y, p.z))


## 선택 고리의 지금 바깥 반지름(월드)과 맨 위 그리기 여부(검사용).
func ring_info() -> Dictionary:
	return {visible = _ring.visible, radius = _ring.transform.basis.get_scale().x * RING_OUTER, on_top = _ring.material_override == _ring_mat_top,
			position = _ring.position}


# ════════════════════════════ 건물 ════════════════════════════

## 저장고·밭 위치가 바뀌었을 때만 다시 쓴다(배열 내용 비교).
func _sync_buildings() -> void:
	if world.store_tiles != _last_stores:
		_last_stores = world.store_tiles.duplicate()
		# 저장고 칸 표시(문 앞 자리용). 둘레 자리를 다시 계산하게 한다.
		_store_mask.resize(_n_tiles)
		_store_mask.fill(0)
		for c in _last_stores:
			if c >= 0 and c < _n_tiles:
				_store_mask[c] = 1
		# 저장고 정면(-Z, 문)을 문 앞 자리 쪽(지나갈 수 있는 이웃, 보통 남쪽 = 처음 카메라 쪽)으로 돌린다
		var yaws := PackedFloat32Array()
		for c in _last_stores:
			var d := _door_dir(c) if c >= 0 and c < _n_tiles else -1
			if d >= 0:
				_store_mask[c] = 1 + d
			elif c >= 0 and c < _n_tiles:
				_store_mask[c] = 1 + SimGrid.DIR_COUNT
			yaws.append(-float(d if d >= 0 else DOOR_ORDER[0]) * QUARTER)
		_offsets_tick = -1
		_fill_static(_store_mm, _last_stores, _store_base, 0.0, _store_col, yaws)
	if world.farms != _last_farms:
		_last_farms = world.farms.duplicate()
		_fill_static(_farm_mm, _last_farms, _farm_base, _farm_lift, _farm_col, PackedFloat32Array())


## 저장고 칸 c 의 문 방향(SimGrid 방향 번호): DOOR_ORDER(남 → 동 → 서 → 북) 가운데 지도 안·지나갈 수 있고 다른 저장고가 아닌
## 첫 이웃, 없으면 지나갈 수 있는 첫 이웃, 그것도 없으면 -1. 물·바위·지도 끝은 바뀌지 않으므로 저장고 목록이 바뀔 때만 부른다.
## 문 앞에 선 개체가 바위 속에 묻히거나 지도 밖 허공에 걸리지 않게(검토 I54).
func _door_dir(c: int) -> int:
	var W := world.w
	var x := c % W
	var y := c / W
	var fallback := -1
	for d in DOOR_ORDER:
		var nx: int = x + SimGrid.DX[d]
		var ny: int = y + SimGrid.DY[d]
		if nx < 0 or ny < 0 or nx >= W or ny >= world.h or not SimGrid.passable(world.tiles[ny * W + nx]):
			continue
		if _store_mask[ny * W + nx] == 0:
			return d
		if fallback == -1:
			fallback = d
	return fallback


## 칸 가운데에 크기 1 로 놓는다. yaws = 칸마다 Y 축 회전(라디안, 모자라면 0). 직각 회전만 쓰므로 cos·sin 을 반올림해 정확히.
func _fill_static(mm: MultiMesh, cells: PackedInt32Array, base: float, lift: float, col: Color, yaws: PackedFloat32Array) -> void:
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
		var co := 1.0
		var si := 0.0
		if k < yaws.size():
			# + 0.0: 반올림한 -0 을 0 으로
			co = roundf(cos(yaws[k])) + 0.0
			si = roundf(sin(yaws[k])) + 0.0
		buf[o] = co
		buf[o + 2] = si
		buf[o + 3] = (float(c % W) + 0.5) * _tile
		buf[o + 5] = 1.0
		buf[o + 7] = base + lift
		buf[o + 8] = 0.0 - si
		buf[o + 10] = co
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
