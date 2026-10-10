class_name SlimeGeo
extends RefCounted
## 절차적 메시: 슬라임(구 하나를 조각한 물방울)·풀포기·열매·저장고·밭·선택 고리. 계약: docs/VIEW-API.md "SlimeGeo".
## 모든 메시는 바닥 y 0, 정면 -Z, 정점 색을 쓰며 처음 한 번만 만들어 캐시한다. 조립은 ProcGeo(이전 프로젝트 기법).
## 색·크기·광택은 config/ui.json 의 slime·buildings 절, 모양을 정하는 계수는 아래 이름 붙은 상수.

# ---------------------------------------------------------------- 슬라임 모양(단위 반지름 기준, 조각 함수 계수)

## 가로 반지름(단위)과 아래쪽이 처져 넓어지는 정도
const BODY_SIDE := 1.0
const BODY_SAG := 0.03
## 처짐이 시작·끝나는 방향 높이(dir.y)
const SAG_FROM := 0.3
const SAG_TO := -0.45
## 위 반쪽·아래 반쪽 높이(바닥을 자르기 전 타원)
const BODY_TOP := 0.86
const BODY_LOW := 0.8
## 납작한 바닥: 중심 아래 깊이와 가장자리 둥글기(부드러운 최솟값 폭)
const FLOOR_DEPTH := 0.4
const FLOOR_SOFT := 0.3
## 정수리 꼭지: 높이·폭(라디안)·뒤(+Z)로 기우는 정도
const TIP_HEIGHT := 0.17
const TIP_SIGMA := 0.34
const TIP_LEAN := 0.12

## 눈: 중심 위도(위 극에서)·경도(정면에서 좌우), 가로·세로 반지름(눈 중심 접평면 좌표 ≈ 단위 구 위 라디안)
const EYE_LAT := 1.06
const EYE_LON := 0.4
const EYE_W := 0.158
const EYE_H := 0.222
## 반사점: 눈 중심에서의 위치(눈 반지름 단위, 두 눈 모두 같은 쪽 위)와 반지름(눈 가로 반지름 단위)
const SHINE_U := 0.28
const SHINE_V := -0.42
const SHINE_R := 0.36
## 입: 중심 위도와 가로 반지름·아래로 처진 깊이(위 변은 곧고 아래는 둥근 "ᴗ" 모양)
const MOUTH_LAT := 1.41
const MOUTH_W := 0.075
const MOUTH_H := 0.06
## 고리 정점 수: 눈 윤곽·반사점·입 윤곽(삼각형 수를 정한다)
const EYE_RING := 16
const SHINE_RING := 6
const MOUTH_RING := 8
## 눈·입 둘레에 비워 둘 격자 칸의 여유(모양 반지름의 배수)
const HOLE_MARGIN := 1.12
## 바닥 둘레 어둡게: 중심 아래 이 높이 구간(단위)에서 서서히
const RIM_FROM := -0.05
const RIM_TO := 0.4

## 격자: 정면(경도 0 근처)과 눈 높이 띠에 정점을 모으고, 바닥 둘레(모서리가 둥글게 꺾이는 곳)는 촘촘히, 납작한 바닥은 성기게
const FRONT_DENSITY := 0.5
const FRONT_SIGMA := 0.7
const TOP_DENSITY := 1.0
const EYE_BAND_DENSITY := 0.6
const EYE_BAND_SIGMA := 0.3
const RIM_LAT := 1.9
const RIM_SIGMA := 0.25
const RIM_DENSITY := 1.0
const FLOOR_LAT := 2.3
const FLOOR_DENSITY := 0.08

# ---------------------------------------------------------------- 풀포기·열매·건물 모양

## 풀포기: 바깥 잎 수(낮고 넓게 휨)와 안쪽 잎 수(곧게 높이 1)
const PLANT_OUTER := 5
const PLANT_INNER := 2
## 풀포기 바깥 잎: 방향 흔들림(라디안 폭·수열 빈도), 키(가운데·흔들림 폭·빈도·위상), 뿌리를 가운데에서 띄운 거리,
## 휘어 나가는 거리·잎 폭·접힘(V 단면, 바깥·안쪽 잎 같음)
const PLANT_YAW_WOBBLE := 0.35
const PLANT_YAW_FREQ := 2.3
const PLANT_OUTER_H := 0.56
const PLANT_OUTER_H_VAR := 0.12
const PLANT_OUTER_H_FREQ := 1.7
const PLANT_OUTER_H_PHASE := 0.4
const PLANT_OUTER_ROOT := 0.03
const PLANT_OUTER_REACH := 0.44
const PLANT_OUTER_W := 0.26
const PLANT_LEAF_FOLD := 0.3
## 풀포기 안쪽 잎: 첫 잎 방향(라디안, 둘째는 반 바퀴 돌림), 뿌리 거리, 잎마다 줄어드는 키, 휘어 나가는 거리·폭, 끝 색 밝힘
const PLANT_INNER_YAW := 0.9
const PLANT_INNER_ROOT := 0.02
const PLANT_INNER_H_STEP := 0.1
const PLANT_INNER_REACH := 0.16
const PLANT_INNER_W := 0.2
const PLANT_INNER_TIP_LIGHT := 0.1
## 열매: 조각 구 격자, 꼭지 오목함, 잎
const BERRY_SEGS := 8
const BERRY_RINGS := 5
const BERRY_DIMPLE := 0.22
## 열매 반지름(가로·세로·앞뒤)과 꼭지 오목함의 폭(라디안), 위쪽 밝힘·아래쪽 어둡힘(볕)
const BERRY_RADII := Vector3(0.5, 0.44, 0.5)
const BERRY_DIMPLE_SIGMA := 0.4
const BERRY_TOP_LIGHT := 0.18
const BERRY_BOTTOM_DARK := 0.25
## 열매 잎: 뿌리를 꼭대기에서 내린 깊이, 뻗는 방향, 키·거리·폭·접힘, 뿌리 쪽 어둡힘
const BERRY_LEAF_SINK := 0.1
const BERRY_LEAF_DIR := Vector3(0.6, 0.0, 0.4)
const BERRY_LEAF_H := 0.2
const BERRY_LEAF_REACH := 0.36
const BERRY_LEAF_W := 0.26
const BERRY_LEAF_FOLD := 0.25
const BERRY_LEAF_BASE_DARK := 0.15
## 저장고·고리 둘레 칸 수
const STORE_SEGS := 12
## 저장고 옆모습 표의 색 갈래(벽: 흙벽·돌 띠, 지붕: 이엉·층 시작의 밝은 이엉·층 끝의 겹친 자국)
const TONE_WALL := 0
const TONE_FOOTING := 1
const TONE_ROOF := 0
const TONE_ROOF_LITE := 1
const TONE_ROOF_LIP := 2
## 저장고 벽 옆모습(위→아래) [높이, 반지름, 색 갈래, 어둡힘]: 처마 밑에서 시작해 아래로 조금 불룩, 바닥 둘레는 돌 띠
const STORE_WALL_PROFILE := [
	[0.6, 0.31, TONE_WALL, 0.3],
	[0.35, 0.335, TONE_WALL, 0.0],
	[0.09, 0.35, TONE_WALL, 0.08],
	[0.09, 0.37, TONE_FOOTING, 0.0],
	[0.0, 0.375, TONE_FOOTING, 0.15],
]
## 돌 띠 = 벽 색을 이만큼 어둡게
const STORE_FOOTING_DARK := 0.35
## 저장고 지붕 옆모습(위→아래) [높이, 반지름, 색 갈래, 어둡힘]: 꼭대기 → 이엉 세 층(층 끝마다 안으로 살짝 들어가 겹친 자국,
## 다음 층은 밝게 시작) → 처마 끝(처마 반지름 0.47) → 처마 밑(벽 쪽으로)
const STORE_ROOF_PROFILE := [
	[1.1, 0.0, TONE_ROOF, 0.15],
	[0.96, 0.15, TONE_ROOF, 0.0],
	[0.94, 0.13, TONE_ROOF_LIP, 0.0],
	[0.94, 0.18, TONE_ROOF_LITE, 0.0],
	[0.8, 0.31, TONE_ROOF, 0.0],
	[0.78, 0.29, TONE_ROOF_LIP, 0.0],
	[0.78, 0.34, TONE_ROOF_LITE, 0.0],
	[0.56, 0.47, TONE_ROOF, 0.05],
	[0.53, 0.46, TONE_ROOF_LIP, 0.0],
	[0.6, 0.31, TONE_ROOF, 0.5],
]
## 층 시작 이엉의 밝힘, 층 끝 겹친 자국의 어둡힘
const STORE_ROOF_LITE := 0.2
const STORE_ROOF_LIP := 0.3
## 문: 붙이는 원통 벽의 반지름·문 폭·높이(위는 반원), 위쪽 밝힘
const STORE_DOOR_WALL_R := 0.36
const STORE_DOOR_W := 0.17
const STORE_DOOR_H := 0.31
const STORE_DOOR_TOP_LIGHT := 0.08
const RING_SEGS := 36
const RING_TUBE := 4
## 고리: 관 중심 반지름·관 반지름·납작 비율(바깥 반지름 = 1)
const RING_CENTER := 0.9
const RING_TUBE_R := 0.1
const RING_FLAT := 0.3
## 밭: 판 크기·두께, 이랑 수·간격·폭·높이, 이랑당 싹 수
const FARM_SIZE := 0.96
const FARM_THICK := 0.03
const FARM_RIDGES := 3
const FARM_RIDGE_GAP := 0.3
const FARM_RIDGE_W := 0.11
const FARM_RIDGE_H := 0.05
const FARM_SPROUTS := 4
## 싹 떡잎: 높이·옆으로 벌어짐·폭
const SPROUT_H := 0.1
const SPROUT_REACH := 0.07
const SPROUT_W := 0.06
## 흙판 윗면·옆면 어둡힘(옆면 아래 모서리는 SLAB_BOTTOM_DARK 만큼 더), 상자 판의 옆면 수
const FARM_TOP_DARK := 0.12
const FARM_SIDE_DARK := 0.3
const SLAB_BOTTOM_DARK := 0.2
const SLAB_FACES := 4
## 이랑 양 끝을 판 끝에서 들인 거리, 싹 줄의 양 끝 여백
const FARM_RIDGE_INSET := 0.04
const FARM_SPROUT_INSET := 0.14
## 싹 방향: 이랑·싹 번호에 따라 SPROUT_TURN 라디안씩 SPROUT_TURN_STEPS 갈래로 돌림. 뿌리 높이(이랑 높이의 배), 떡잎 뿌리 쪽 어둡힘
const SPROUT_TURN := 0.6
const SPROUT_TURN_STEPS := 3
const SPROUT_ROOT_K := 0.9
const SPROUT_BASE_DARK := 0.25
## 이랑: 단면 법선을 옆으로 기울이는 정도, 꼭대기 밝힘(단면 높이 1 당), 양 끝 막이 어둡힘
const RIDGE_NORMAL_TILT := 1.6
const RIDGE_TOP_LIGHT := 0.1
const RIDGE_CAP_DARK := 0.15
## 이랑 단면(가로 -1~1 = 폭, 세로 0~1 = 높이)
const RIDGE_PROFILE: Array[Vector2] = [Vector2(-1.0, 0.0), Vector2(-0.6, 0.65), Vector2(0.0, 1.0), Vector2(0.6, 0.65), Vector2(1.0, 0.0)]

static var _cache: Dictionary = {}


static func _cached(key: String, maker: Callable) -> Variant:
	if not _cache.has(key):
		_cache[key] = maker.call()
	return _cache[key]


# ================================================================ 슬라임

## 슬라임 한 마리: 구 하나를 조각한 물방울(바닥 납작, 위는 둥근 지붕에 작은 꼭지, 정면 -Z).
## 두 눈·반사점·입은 같은 메시의 정점 색. 몸은 흰색 계열이라 MultiMesh 인스턴스 색이 곱해져 계통 색이 된다.
static func slime_mesh() -> ArrayMesh:
	return _cached("slime", _build_slime)


static func _build_slime() -> ArrayMesh:
	var segs := UiConfig.integer("slime.segments")
	var rings := UiConfig.integer("slime.rings")
	# 두 눈·입 자리: 그 모양을 감싸는 격자 칸 묶음을 비워 두고, 같은 조각 겉면 위에 윤곽을 따라가는 고리 짜임으로 채운다
	# (격자 정점 색만으로는 400 삼각형 안에서 눈이 번진 얼룩이 되므로 윤곽에 정점을 두 벌 두어 또렷하게).
	# 눈을 감싸는 위도·경도 범위에 격자선을 핀으로 박아 구멍이 눈에 꼭 맞는 칸 묶음이 되게 한다.
	var eye_r := _extent(ProcGeo.direction(EYE_LAT, EYE_LON), _eye_outline(EYE_RING))
	var eye_l := Rect2(-eye_r.end.x, eye_r.position.y, eye_r.size.x, eye_r.size.y)
	var lons := ProcGeo.spread(segs, -PI, PI, _lon_density,
		PackedFloat64Array([eye_l.position.x, eye_l.end.x, eye_r.position.x, eye_r.end.x]))
	var lats := ProcGeo.spread(rings, 0.0, PI, _lat_density, PackedFloat64Array([eye_r.position.y, eye_r.end.y]))
	var eyes: Array[Vector3] = [ProcGeo.direction(EYE_LAT, -EYE_LON), ProcGeo.direction(EYE_LAT, EYE_LON)]
	var mouth := ProcGeo.direction(MOUTH_LAT, 0.0)
	# 입 구멍: 두 눈 구멍 사이의 경도 칸 전부(눈 구멍과 칸이 겹치지 않음), 위도는 입을 감싸는 칸
	var mouth_ext := _extent(mouth, _mouth_outline())
	mouth_ext = Rect2(eye_l.end.x, mouth_ext.position.y, eye_r.position.x - eye_l.end.x, mouth_ext.size.y)
	var holes: Array[Rect2i] = [_cells(lats, lons, eye_l), _cells(lats, lons, eye_r), _cells(lats, lons, mouth_ext)]
	var g := ProcGeo.new()
	g.sculpt(Vector3.ZERO, Vector3.ONE, segs, rings, _slime_shape, Color.WHITE, _body_color, lats, lons, holes)
	for k in eyes.size():
		_eye_patch(g, holes[k], eyes[k])
	_mouth_patch(g, holes[eyes.size()], mouth)
	# 가장 넓은 가로 반지름 = ui.slime.radius, 바닥 = y 0
	var wide := 0.0
	for p in g.v:
		wide = maxf(wide, Vector2(p.x, p.z).length())
	g.scale_uniform(UiConfig.num("slime.radius") / wide)
	g.translate(Vector3(0.0, -g.bounds().position.y, 0.0))
	return g.to_mesh(slime_material())


## 방향 → 반지름 배수: 위·아래 높이가 다른 타원 + 정수리 꼭지 + 납작한 바닥(부드러운 모서리)
static func _slime_shape(dir: Vector3) -> float:
	var y := dir.y
	var sag := clampf((SAG_FROM - y) / (SAG_FROM - SAG_TO), 0.0, 1.0)
	var side := BODY_SIDE * (1.0 + BODY_SAG * sag * sag * (3.0 - 2.0 * sag))
	var b := BODY_TOP if y > 0.0 else BODY_LOW
	var k := 1.0 / sqrt((1.0 - y * y) / (side * side) + y * y / (b * b))
	k += TIP_HEIGHT * ProcGeo.bump(dir, Vector3(0.0, 1.0, TIP_LEAN).normalized(), TIP_SIGMA)
	if y < -0.0001:
		k = ProcGeo.smin(k, FLOOR_DEPTH / -y, FLOOR_SOFT)
	return k


## 몸 정점 색: 흰색 계열, 바닥 둘레는 조금 어둡게(인스턴스 색이 곱해져 계통 색의 젤리가 된다)
static func _body_color(_dir: Vector3, p: Vector3) -> Color:
	var rim := clampf((-p.y - RIM_FROM) / (RIM_TO - RIM_FROM), 0.0, 1.0)
	return UiConfig.color("slime.body_color").lerp(UiConfig.color("slime.body_bottom"), rim)


## 방향 d 의 겉면에서의 몸 색
static func _body_at(d: Vector3) -> Color:
	return _body_color(d, ProcGeo.sculpt_point(Vector3.ONE, ProcGeo.lat_of(d), ProcGeo.lon_of(d), _slime_shape))


## 눈 윤곽(접평면 좌표, 고리 정점 count 개): 세로로 긴 타원
static func _eye_outline(count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in count:
		var a := TAU * float(k) / float(count)
		out.append(Vector2(EYE_W * cos(a), EYE_H * sin(a)))
	return out


## 입 윤곽(접평면 좌표, v 가 아래): 위 변은 곧고 아래는 반타원으로 둥근 "ᴗ". 오른쪽 끝 → 아래 → 왼쪽 끝 → 위 변 순서(한 바퀴).
static func _mouth_outline() -> PackedVector2Array:
	var out := PackedVector2Array()
	var arc := MOUTH_RING - 2
	for k in arc:
		var a := PI * float(k) / float(arc - 1)
		out.append(Vector2(MOUTH_W * cos(a), MOUTH_H * sin(a)))
	out.append(Vector2(-MOUTH_W / 3.0, -MOUTH_H * 0.08))
	out.append(Vector2(MOUTH_W / 3.0, -MOUTH_H * 0.08))
	return out


## 윤곽(중심 c 의 접평면 좌표)을 여유 HOLE_MARGIN 배로 감싼 경도·위도 범위(x = 경도, y = 위도)
static func _extent(c: Vector3, outline: PackedVector2Array) -> Rect2:
	var lat0 := PI
	var lat1 := 0.0
	var lon0 := PI
	var lon1 := -PI
	for uv in outline:
		var d := ProcGeo.tangent_dir(c, uv * HOLE_MARGIN)
		lat0 = minf(lat0, ProcGeo.lat_of(d))
		lat1 = maxf(lat1, ProcGeo.lat_of(d))
		lon0 = minf(lon0, ProcGeo.lon_of(d))
		lon1 = maxf(lon1, ProcGeo.lon_of(d))
	return Rect2(lon0, lat0, lon1 - lon0, lat1 - lat0)


## 경도·위도 범위 ext 를 덮는 가장 작은 격자 칸 묶음(x = 경도 칸 j, y = 위도 칸 i)
static func _cells(lats: PackedFloat64Array, lons: PackedFloat64Array, ext: Rect2) -> Rect2i:
	const EPS := 0.000001
	var i0 := 0
	while i0 + 1 < lats.size() and lats[i0 + 1] <= ext.position.y + EPS:
		i0 += 1
	var i1 := i0 + 1
	while i1 < lats.size() - 1 and lats[i1] < ext.end.y - EPS:
		i1 += 1
	var j0 := 0
	while j0 + 1 < lons.size() and lons[j0 + 1] <= ext.position.x + EPS:
		j0 += 1
	var j1 := j0 + 1
	while j1 < lons.size() - 1 and lons[j1] < ext.end.x - EPS:
		j1 += 1
	return Rect2i(j0, i0, j1 - j0, i1 - i0)


## 눈 한 쪽: 격자 구멍 둘레 → 눈 윤곽(몸 색·눈 색 두 벌, 또렷한 경계) → 반사점 윤곽(눈 색·흰색 두 벌) → 반사점 가운데.
## 눈동자는 위가 짙고 아래로 갈수록 살짝 밝다(젤리 눈의 윤기).
static func _eye_patch(g: ProcGeo, hole: Rect2i, c: Vector3) -> void:
	var outer := g.grid_loop(hole)
	var ang_o := _loop_angles(g, outer, c, Vector2.ZERO)
	var outline := _eye_outline(EYE_RING)
	var shine_c := Vector2(SHINE_U * EYE_W, SHINE_V * EYE_H)
	var shine_r := SHINE_R * EYE_W
	var rim_out := PackedInt32Array()
	var rim_in := PackedInt32Array()
	var ang_rim := PackedFloat64Array()
	var ang_rim_s := PackedFloat64Array()
	for uv in outline:
		var d := ProcGeo.tangent_dir(c, uv)
		rim_out.append(g.surface_vert(Vector3.ZERO, Vector3.ONE, d, _slime_shape, _body_at(d)))
		rim_in.append(g.surface_vert(Vector3.ZERO, Vector3.ONE, d, _slime_shape, _eye_color(uv)))
		ang_rim.append(atan2(uv.y, uv.x))
		ang_rim_s.append(atan2(uv.y - shine_c.y, uv.x - shine_c.x))
	g.zip_loops(outer, ang_o, rim_out, ang_rim)
	var sh_out := PackedInt32Array()
	var sh_in := PackedInt32Array()
	var ang_sh := PackedFloat64Array()
	for k in SHINE_RING:
		var a := TAU * float(k) / float(SHINE_RING)
		var uv := shine_c + Vector2(cos(a), sin(a)) * shine_r
		var d := ProcGeo.tangent_dir(c, uv)
		sh_out.append(g.surface_vert(Vector3.ZERO, Vector3.ONE, d, _slime_shape, _eye_color(uv)))
		sh_in.append(g.surface_vert(Vector3.ZERO, Vector3.ONE, d, _slime_shape, UiConfig.color("slime.eye_shine")))
		ang_sh.append(a)
	g.zip_loops(rim_in, ang_rim_s, sh_out, ang_sh)
	var mid := g.surface_vert(Vector3.ZERO, Vector3.ONE, ProcGeo.tangent_dir(c, shine_c), _slime_shape, UiConfig.color("slime.eye_shine"))
	g.fan(mid, sh_in)


## 눈동자 색(접평면 좌표 uv): 위는 짙고 아래로 갈수록 살짝 밝은 남색
static func _eye_color(uv: Vector2) -> Color:
	var t := clampf(uv.y / EYE_H * 0.5 + 0.5, 0.0, 1.0)
	return UiConfig.color("slime.eye_color").lerp(UiConfig.color("slime.eye_lower"), t * t)


## 입: 격자 구멍 둘레 → 입 윤곽(몸 색·입 색 두 벌) → 가운데
static func _mouth_patch(g: ProcGeo, hole: Rect2i, c: Vector3) -> void:
	var outline := _mouth_outline()
	var center := Vector2(0.0, MOUTH_H * 0.4)
	var outer := g.grid_loop(hole)
	var ang_o := _loop_angles(g, outer, c, center)
	var m_out := PackedInt32Array()
	var m_in := PackedInt32Array()
	var ang := PackedFloat64Array()
	var col := UiConfig.color("slime.mouth_color")
	for uv in outline:
		var d := ProcGeo.tangent_dir(c, uv)
		m_out.append(g.surface_vert(Vector3.ZERO, Vector3.ONE, d, _slime_shape, _body_at(d)))
		m_in.append(g.surface_vert(Vector3.ZERO, Vector3.ONE, d, _slime_shape, col))
		ang.append(atan2(uv.y - center.y, uv.x - center.x))
	g.zip_loops(outer, ang_o, m_out, ang)
	# 윤곽은 가운데 둘레를 한 방향으로 도는 순서로 만들었으므로 그대로 부채꼴
	g.fan(g.surface_vert(Vector3.ZERO, Vector3.ONE, ProcGeo.tangent_dir(c, center), _slime_shape, col), m_in)


## 고리 정점들의 각도(중심 c 의 접평면에서 점 center 둘레)
static func _loop_angles(g: ProcGeo, ids: PackedInt32Array, c: Vector3, center: Vector2) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for id in ids:
		var uv := ProcGeo.tangent_uv(c, g.v[id].normalized()) - center
		out.append(atan2(uv.y, uv.x))
	return out


## 경도 격자 밀도: 정면 근처가 촘촘하다
static func _lon_density(lon: float) -> float:
	var a := wrapf(lon, -PI, PI)
	return 1.0 + FRONT_DENSITY * exp(-(a * a) / (2.0 * FRONT_SIGMA * FRONT_SIGMA))


## 위도 격자 밀도: 정수리는 조금 성기고, 눈 높이 띠와 바닥 둘레가 촘촘하며, 납작한 바닥은 거의 비운다
static func _lat_density(lat: float) -> float:
	if lat > FLOOR_LAT:
		return FLOOR_DENSITY
	var top := TOP_DENSITY + (1.0 - TOP_DENSITY) * clampf(lat / EYE_LAT, 0.0, 1.0)
	var de := lat - EYE_LAT
	var dr := lat - RIM_LAT
	return top + EYE_BAND_DENSITY * exp(-(de * de) / (2.0 * EYE_BAND_SIGMA * EYE_BAND_SIGMA)) \
		+ RIM_DENSITY * exp(-(dr * dr) / (2.0 * RIM_SIGMA * RIM_SIGMA))


## 슬라임 재질: 정점 색을 바탕색으로(MultiMesh 인스턴스 색이 곱해짐), 낮은 거칠기·강한 반사·가장자리 빛으로 윤기 나는 젤리.
## 투명은 쓰지 않는다(MultiMesh 정렬 문제).
static func slime_material() -> Material:
	return _cached("mat_slime", func() -> Material:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = UiConfig.num("slime.roughness")
		m.metallic_specular = UiConfig.num("slime.specular")
		m.rim_enabled = true
		m.rim = UiConfig.num("slime.rim")
		m.rim_tint = UiConfig.num("slime.rim_tint")
		return m)


## 식물·건물 공용 재질(정점 색, 거친 무광)
static func shared_material() -> Material:
	return _cached("mat_shared", func() -> Material:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = UiConfig.num("buildings.roughness")
		m.metallic_specular = UiConfig.num("buildings.specular")
		return m)


# ================================================================ 풀포기·열매

## 풀포기: 뿌리에서 솟아 바깥으로 휘는 뾰족한 잎 여러 장(양면). 바닥 y 0, 가장 높은 잎 끝 y 1. 둥근 슬라임과 실루엣이 다르다.
static func plant_mesh() -> ArrayMesh:
	return _cached("plant", func() -> ArrayMesh:
		var g := ProcGeo.new()
		var base := UiConfig.color("buildings.plant_base")
		var tip := UiConfig.color("buildings.plant_tip")
		for k in PLANT_OUTER:
			# 잎마다 각도·길이를 조금씩 달리해 자연스럽게(고정 수열이라 결정적)
			var a := TAU * float(k) / float(PLANT_OUTER) + PLANT_YAW_WOBBLE * sin(float(k) * PLANT_YAW_FREQ)
			var out := Vector3(sin(a), 0.0, -cos(a))
			var h := PLANT_OUTER_H + PLANT_OUTER_H_VAR * sin(float(k) * PLANT_OUTER_H_FREQ + PLANT_OUTER_H_PHASE)
			g.leaf(out * PLANT_OUTER_ROOT, out, h, PLANT_OUTER_REACH, PLANT_OUTER_W, PLANT_LEAF_FOLD, base, tip)
		for k in PLANT_INNER:
			var a := PI * float(k) + PLANT_INNER_YAW
			var out := Vector3(sin(a), 0.0, -cos(a))
			g.leaf(out * PLANT_INNER_ROOT, out, 1.0 - PLANT_INNER_H_STEP * float(k), PLANT_INNER_REACH, PLANT_INNER_W, PLANT_LEAF_FOLD,
				base, tip.lightened(PLANT_INNER_TIP_LIGHT))
		var top := g.bounds().end.y
		g.scale_uniform(1.0 / top)
		return g.to_mesh(shared_material()))


## 열매: 살짝 눌린 둥근 열매(꼭지 쪽 오목) + 작은 잎. 지름 약 1, 바닥 y 0.
static func berry_mesh() -> ArrayMesh:
	return _cached("berry", func() -> ArrayMesh:
		var g := ProcGeo.new()
		var skin := UiConfig.color("buildings.berry_skin")
		var leaf := UiConfig.color("buildings.berry_leaf")
		var shape := func(dir: Vector3) -> float:
			return 1.0 - BERRY_DIMPLE * ProcGeo.bump(dir, Vector3.UP, BERRY_DIMPLE_SIGMA)
		var paint := func(dir: Vector3, _p: Vector3) -> Color:
			# 위는 볕을 받아 밝고 아래는 짙게
			return skin.lightened(BERRY_TOP_LIGHT * maxf(dir.y, 0.0)).darkened(BERRY_BOTTOM_DARK * maxf(-dir.y, 0.0))
		g.sculpt(Vector3.ZERO, BERRY_RADII, BERRY_SEGS, BERRY_RINGS, shape, skin, paint)
		g.translate(Vector3(0.0, -g.bounds().position.y, 0.0))
		var top := g.bounds().end.y
		g.leaf(Vector3(0.0, top - BERRY_LEAF_SINK, 0.0), BERRY_LEAF_DIR, BERRY_LEAF_H, BERRY_LEAF_REACH, BERRY_LEAF_W, BERRY_LEAF_FOLD,
			leaf.darkened(BERRY_LEAF_BASE_DARK), leaf)
		return g.to_mesh(shared_material()))


# ================================================================ 건물

## 저장고: 회전체 움집. 흙벽 원통(아래 돌 띠) + 층층이 이은 이엉 원뿔 지붕(처마가 벽 밖으로) + 정면(-Z) 어두운 문.
## 한 칸(지름 약 0.9, 높이 약 1.1)에 들어간다.
static func storehouse_mesh() -> ArrayMesh:
	return _cached("store", func() -> ArrayMesh:
		var g := ProcGeo.new()
		var wall := UiConfig.color("buildings.store_wall")
		var roof := UiConfig.color("buildings.store_roof")
		# 벽·지붕 옆모습 표(STORE_WALL_PROFILE·STORE_ROOF_PROFILE)를 돌린다
		g.lathe(_profile(STORE_WALL_PROFILE, [wall, wall.darkened(STORE_FOOTING_DARK)]), STORE_SEGS)
		g.lathe(_profile(STORE_ROOF_PROFILE, [roof, roof.lightened(STORE_ROOF_LITE), roof.darkened(STORE_ROOF_LIP)]), STORE_SEGS)
		_door(g, STORE_DOOR_WALL_R, STORE_DOOR_W, STORE_DOOR_H, UiConfig.color("buildings.store_door"))
		return g.to_mesh(shared_material()))


## 옆모습 표 [높이, 반지름, 색 갈래, 어둡힘] → ProcGeo.lathe 마디({y, r, col}). 색 = tones[갈래] 를 어둡힘만큼 어둡게.
static func _profile(rows: Array, tones: Array) -> Array:
	var out := []
	for q: Array in rows:
		out.append({y = float(q[0]), r = float(q[1]), col = (tones[int(q[2])] as Color).darkened(float(q[3]))})
	return out


## 정면(-Z) 벽에 붙는 아치 문: 원통 벽(반지름 wall_r)을 따라 휜 판. 폭 w, 높이 h(위는 반원).
static func _door(g: ProcGeo, wall_r: float, w: float, h: float, col: Color) -> void:
	const COLS := 6
	const LIFT := 0.006
	var half := w * 0.5
	var arch_y := h - half
	var row_lo := PackedInt32Array()
	var row_hi := PackedInt32Array()
	for k in COLS + 1:
		var x := lerpf(-half, half, float(k) / float(COLS))
		var top := arch_y + sqrt(maxf(half * half - x * x, 0.0))
		var z := -sqrt(maxf(wall_r * wall_r - x * x, 0.0)) - LIFT
		var nn := Vector3(x, 0.0, z).normalized()
		row_lo.append(g.vert(Vector3(x, 0.0, z), nn, col))
		row_hi.append(g.vert(Vector3(x, top, z), nn, col.lightened(STORE_DOOR_TOP_LIGHT)))
	for k in COLS:
		g.quad(row_lo[k], row_lo[k + 1], row_hi[k + 1], row_hi[k])


## 밭: 한 칸 흙판 위에 Z 방향으로 달리는 이랑 세 줄, 이랑마다 떡잎 싹이 줄지어 있다. 높이가 낮다.
static func farm_mesh() -> ArrayMesh:
	return _cached("farm", func() -> ArrayMesh:
		var g := ProcGeo.new()
		var soil := UiConfig.color("buildings.farm_soil")
		var crop := UiConfig.color("buildings.farm_crop")
		var half := FARM_SIZE * 0.5
		# 흙판(윗면 + 네 옆면)
		_slab(g, Vector3(0.0, FARM_THICK * 0.5, 0.0), Vector3(FARM_SIZE, FARM_THICK, FARM_SIZE), soil.darkened(FARM_TOP_DARK), soil.darkened(FARM_SIDE_DARK))
		for r in FARM_RIDGES:
			var cx := (float(r) - float(FARM_RIDGES - 1) * 0.5) * FARM_RIDGE_GAP
			_ridge(g, cx, FARM_THICK, half - FARM_RIDGE_INSET, soil)
			for s in FARM_SPROUTS:
				var z := lerpf(-half + FARM_SPROUT_INSET, half - FARM_SPROUT_INSET, float(s) / float(FARM_SPROUTS - 1))
				var turn := SPROUT_TURN * float((r + s) % SPROUT_TURN_STEPS)
				var root := Vector3(cx, FARM_THICK + FARM_RIDGE_H * SPROUT_ROOT_K, z)
				# 떡잎 두 장(V 자로 벌어짐)
				for side: float in [1.0, -1.0]:
					var out := Vector3(cos(turn) * side, 0.0, sin(turn) * side)
					g.petal(root, root + out * SPROUT_REACH + Vector3.UP * SPROUT_H, SPROUT_W, crop.darkened(SPROUT_BASE_DARK), crop)
		return g.to_mesh(shared_material()))


## 상자 판(윗면 + 네 옆면, 아랫면 없음)
static func _slab(g: ProcGeo, ce: Vector3, size: Vector3, top_col: Color, side_col: Color) -> void:
	var h := size * 0.5
	var b0 := g.v.size()
	for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		g.vert(ce + Vector3(h.x * q.x, h.y, h.z * q.y), Vector3.UP, top_col)
	g.quad(b0, b0 + 1, b0 + 2, b0 + 3)
	for f in SLAB_FACES:
		var a := TAU * float(f) / float(SLAB_FACES)
		var nn := Vector3(sin(a), 0.0, -cos(a))
		var t := Vector3.UP.cross(nn)
		var c := ce + Vector3(nn.x * h.x, 0.0, nn.z * h.z)
		var w := absf(t.x) * h.x + absf(t.z) * h.z
		var s0 := g.vert(c - t * w + Vector3.UP * h.y, nn, side_col)
		var s1 := g.vert(c + t * w + Vector3.UP * h.y, nn, side_col)
		var s2 := g.vert(c + t * w - Vector3.UP * h.y, nn, side_col.darkened(SLAB_BOTTOM_DARK))
		var s3 := g.vert(c - t * w - Vector3.UP * h.y, nn, side_col.darkened(SLAB_BOTTOM_DARK))
		g.quad(s0, s1, s2, s3)


## 이랑 한 줄: x = cx 를 중심으로 Z 방향(-half ~ half)으로 달리는 둥근 둔덕. 단면 5 점, 양 끝은 막는다.
static func _ridge(g: ProcGeo, cx: float, y0: float, half: float, soil: Color) -> void:
	var ends: Array = []
	for zs: float in [-1.0, 1.0]:
		var row := PackedInt32Array()
		for k in RIDGE_PROFILE.size():
			var q: Vector2 = RIDGE_PROFILE[k]
			var p := Vector3(cx + q.x * FARM_RIDGE_W, y0 + q.y * FARM_RIDGE_H, zs * half)
			# 둔덕 단면의 바깥 법선(가운데는 위, 양옆은 비스듬히)
			var nn := Vector3(q.x * FARM_RIDGE_H / FARM_RIDGE_W * RIDGE_NORMAL_TILT, 1.0, 0.0)
			row.append(g.vert(p, nn, soil.lightened(RIDGE_TOP_LIGHT * q.y)))
		ends.append(row)
	var ra: PackedInt32Array = ends[0]
	var rb: PackedInt32Array = ends[1]
	for k in RIDGE_PROFILE.size() - 1:
		g.quad(ra[k], ra[k + 1], rb[k + 1], rb[k])
	# 양 끝 막이(단면 다각형 부채꼴)
	for e in 2:
		var zs := -1.0 if e == 0 else 1.0
		var nn := Vector3(0.0, 0.0, zs)
		var cap := PackedInt32Array()
		for k in RIDGE_PROFILE.size():
			var q: Vector2 = RIDGE_PROFILE[k]
			cap.append(g.vert(Vector3(cx + q.x * FARM_RIDGE_W, y0 + q.y * FARM_RIDGE_H, zs * half), nn, soil.darkened(RIDGE_CAP_DARK)))
		for k in range(1, RIDGE_PROFILE.size() - 1):
			g.tri(cap[0], cap[k], cap[k + 1])


## 선택 표시 고리: 바닥에 놓인 납작한 도넛(바깥 반지름 1, 바닥 y 0). 흰색이라 재질·인스턴스 색으로 칠한다.
static func ring_mesh() -> ArrayMesh:
	return _cached("ring", func() -> ArrayMesh:
		var g := ProcGeo.new()
		g.torus(Vector3(0.0, RING_TUBE_R * RING_FLAT, 0.0), RING_CENTER, RING_TUBE_R, Color.WHITE, RING_SEGS, RING_TUBE, RING_FLAT)
		return g.to_mesh(shared_material()))


## 메시의 삼각형 수(모든 표면, 번호가 있으면 번호 수 / 3, 없으면 정점 수 / 3)
static func triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh:
			var am := mesh as ArrayMesh
			var il := am.surface_get_array_index_len(s)
			total += int((il if il > 0 else am.surface_get_array_len(s)) / 3.0)
		else:
			var arr := mesh.surface_get_arrays(s)
			var ind: Variant = arr[Mesh.ARRAY_INDEX]
			if ind is PackedInt32Array and not (ind as PackedInt32Array).is_empty():
				total += int((ind as PackedInt32Array).size() / 3.0)
			else:
				total += int((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3.0)
	return total
