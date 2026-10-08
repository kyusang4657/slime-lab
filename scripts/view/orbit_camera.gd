extends Camera3D
## 지도 관찰 창의 궤도 카메라: 땅 위 목표점을 중심으로 방위(yaw)·고각(pitch)·거리로 자리를 정한다.
## 수치는 config/ui.json 의 camera 절. MapView 가 preload 해서 쓴다(전역 클래스 이름 없이).
## 이전 프로젝트(little-monster-village, MIT)의 scripts/world/world_view.gd 의 _apply_camera()·pan_by_screen()·
## ground_point() 를 가져와 직교 카메라를 원근 궤도 카메라로 바꾸고 회전·고각 제한을 더했다.
##
## 방위 0 = 카메라가 남쪽(+Z)에서 북쪽(-Z)을 봄(화면 위 = 북). 고각은 수평면에서 위로 잰 각.

## 광선이 땅과 거의 나란할 때(교차 없음으로 침).
const RAY_EPS := 0.0001
## 원근 투영에서 화면 높이 1 픽셀이 목표 거리에서 차지하는 길이 = 2·tan(fov/2)/높이 의 계수.
const HALF := 0.5
## 지도 맞추기 되풀이 횟수(모서리 투영 → 가운데로·거리 고치기).
const FIT_ITERS := 12

var target := Vector3.ZERO
var yaw := 0.0
var pitch := 0.9
var distance := 60.0
## 목표점이 머무를 땅 범위(x, z). 크기 0 이면 제한 없음.
var bounds := Rect2()
## 세로로 긴 칸(비교 모드의 지도 한 칸)에서 지도를 더 크게 보려고 돌려 볼 방위 차(라디안, 0 = 끔).
## fit_rect 가 지금 방위와 이만큼 돌린 방위로 각각 맞춰 보고, 돌린 쪽 거리가 portrait_gain 배 이상 가까우면(지도가 그만큼
## 크게 보이면) 돌린 방위를 쓴다. LabMain 이 비교 모드 지도에 ui.compare.portrait_yaw_deg·portrait_gain_min 을 넣는다.
var portrait_yaw := 0.0
var portrait_gain := 1.15

var _d_min := 5.0
## 설정의 최대 거리(camera.distance_max)와 실제로 쓰는 최대 거리. 지도 전체를 맞추는 데 더 멀어야 하면(큰 지도)
## fit_rect 가 맞춘 거리 × camera.fit_zoom_out_factor 까지 늘린다(사용자가 언제든 전체를 볼 수 있게).
var _d_max_cfg := 95.0
var _d_max := 95.0
var _far_cfg := 500.0
var _zoom_out_k := 1.2
var _p_min := 0.4
var _p_max := 1.5
var _zoom_step := 1.12
var _rotate_speed := 0.006
var _pan_speed := 1.0
var _fit_margin := 1.05


func _init() -> void:
	_d_min = UiConfig.num("camera.distance_min")
	_d_max_cfg = UiConfig.num("camera.distance_max")
	_d_max = _d_max_cfg
	_zoom_out_k = maxf(1.0, UiConfig.num("camera.fit_zoom_out_factor"))
	_p_min = deg_to_rad(UiConfig.num("camera.pitch_min_deg"))
	_p_max = deg_to_rad(UiConfig.num("camera.pitch_max_deg"))
	_zoom_step = UiConfig.num("camera.zoom_step")
	_rotate_speed = UiConfig.num("camera.rotate_speed")
	_pan_speed = UiConfig.num("camera.pan_speed")
	_fit_margin = UiConfig.num("camera.fit_margin")
	fov = UiConfig.num("camera.fov_deg")
	near = UiConfig.num("camera.near")
	_far_cfg = UiConfig.num("camera.far")
	far = _far_cfg
	reset_orientation()
	distance = clampf(UiConfig.num("camera.distance_start"), _d_min, _d_max)


## 방위·고각을 설정의 처음 값으로.
func reset_orientation() -> void:
	yaw = deg_to_rad(UiConfig.num("camera.yaw_deg"))
	pitch = clampf(deg_to_rad(UiConfig.num("camera.pitch_deg")), _p_min, _p_max)


## 화면이 북쪽 위(방위 0)에서 몇 번 90° 돌아 있는지(가장 가까운 것, 0~3). 1 = 화면 위가 서쪽(북쪽은 오른쪽).
## 지도 위 나침반·정보 창 방향 화살표가 쓴다.
func view_turns() -> int:
	return posmod(roundi(yaw / (PI * HALF)), 4)


func distance_min() -> float:
	return _d_min


## 실제로 쓰는 최대 거리(설정값, 또는 큰 지도를 맞추느라 늘린 값).
func distance_max() -> float:
	return _d_max


## 목표점·거리·고각을 범위 안으로 넣고 카메라 변환을 다시 계산한다.
func apply() -> void:
	distance = clampf(distance, _d_min, _d_max)
	pitch = clampf(pitch, _p_min, _p_max)
	if bounds.size != Vector2.ZERO:
		target.x = clampf(target.x, bounds.position.x, bounds.end.x)
		target.z = clampf(target.z, bounds.position.y, bounds.end.y)
	var cp := cos(pitch)
	var off := Vector3(sin(yaw) * cp, sin(pitch), cos(yaw) * cp)
	var pos := target + off * distance
	# look_at 은 트리 밖에서도 되도록 직접 기저를 만든다
	transform = Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)


## 땅 사각형(x, z)이 화면에 다 들어오게 맞춘다. aspect = 화면 너비/높이.
## 네 모서리를 투영해 화면 가운데로 옮기고(목표점 이동) 넘치거나 남는 만큼 거리를 고치기를 몇 번 되풀이한다.
## 맞추는 동안은 최대 거리로 자르지 않고, 끝나면 최대 거리를 max(설정값, 맞춘 거리 × fit_zoom_out_factor)로,
## 먼 자르기 면을 그 거리 + 지도 대각선 이상으로 늘린다(설정 최대 거리보다 큰 지도도 처음에 다 보이게).
## portrait_yaw 가 0 이 아니면 그만큼 돌린 방위로도 맞춰 보고 더 크게 보이는 쪽(위 설명)을 남긴다.
func fit_rect(rect: Rect2, aspect: float) -> void:
	var yaw0 := yaw
	_fit_at(rect, aspect)
	if is_zero_approx(portrait_yaw):
		return
	var d0 := distance
	yaw = yaw0 + portrait_yaw
	_fit_at(rect, aspect)
	if distance * maxf(portrait_gain, 1.0) > d0:
		yaw = yaw0
		_fit_at(rect, aspect)


## 지금 방위·고각으로 fit_rect 의 맞추기(목표점·거리·최대 거리·먼 자르기 면).
func _fit_at(rect: Rect2, aspect: float) -> void:
	bounds = rect
	_d_max = INF
	target = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	var tv := tan(deg_to_rad(fov) * HALF)
	var th := tv * maxf(aspect, 0.1)
	var corners: Array[Vector3] = [
		Vector3(rect.position.x, 0.0, rect.position.y), Vector3(rect.end.x, 0.0, rect.position.y),
		Vector3(rect.end.x, 0.0, rect.end.y), Vector3(rect.position.x, 0.0, rect.end.y),
	]
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	for it in FIT_ITERS:
		apply()
		var inv := transform.affine_inverse()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in corners:
			var q := inv * p
			var dz := maxf(-q.z, RAY_EPS)
			var ndc := Vector2(q.x / (dz * th), q.y / (dz * tv))
			lo = lo.min(ndc)
			hi = hi.max(ndc)
		var mid := (lo + hi) * HALF
		var ext := maxf(hi.x - lo.x, hi.y - lo.y) * HALF
		# 화면 가운데로: 화면 위(+y)는 땅 앞쪽, 오른쪽(+x)은 땅 오른쪽
		target += right * mid.x * distance * th + fwd * mid.y * distance * tv / maxf(sin(pitch), 0.2)
		distance *= ext * _fit_margin
	_d_max = maxf(_d_max_cfg, distance * _zoom_out_k)
	far = maxf(_far_cfg, _d_max + rect.size.length())
	apply()


## 화면 픽셀 이동량만큼 땅을 끈다(거리에 비례). vp_height = 뷰포트 높이(픽셀).
func pan_pixels(rel: Vector2, vp_height: float) -> void:
	var per_px := 2.0 * tan(deg_to_rad(fov) * HALF) * distance / maxf(vp_height, 1.0) * _pan_speed
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	# 땅을 아래로 끌면 앞쪽이 보여야 하므로 목표가 앞으로 간다. 고각이 낮을수록 땅이 눌려 보이는 만큼 키운다.
	target += -right * rel.x * per_px + fwd * rel.y * per_px / maxf(sin(pitch), 0.2)
	apply()


## 휠 한 칸(steps > 0 = 가까이). 커서 아래 땅 점이 화면에서 대략 그대로 있도록 목표도 옮긴다.
func zoom_at(screen_pos: Vector2, steps: float) -> void:
	var old := distance
	distance = clampf(distance / pow(_zoom_step, steps), _d_min, _d_max)
	var g: Variant = ground_point(screen_pos)
	if g != null and old > 0.0:
		var gp: Vector3 = g
		target += (gp - target) * (1.0 - distance / old)
	apply()


## 오른쪽 끌기: 가로 = 방위, 세로 = 고각.
func rotate_pixels(rel: Vector2) -> void:
	yaw -= rel.x * _rotate_speed
	pitch += rel.y * _rotate_speed
	apply()


## 화면 점의 광선과 수평면 y = plane_y 의 교점. 없으면 null.
func ground_point(screen_pos: Vector2, plane_y: float = 0.0) -> Variant:
	var o := project_ray_origin(screen_pos)
	var d := project_ray_normal(screen_pos)
	if absf(d.y) < RAY_EPS:
		return null
	var t := (plane_y - o.y) / d.y
	if t < 0.0:
		return null
	return o + d * t
