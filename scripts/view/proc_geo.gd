class_name ProcGeo
extends RefCounted
## 절차적 메시 조립기: 정점(v)·법선(n)·정점 색(c)·삼각형 번호(idx) 배열을 쌓아 ArrayMesh 하나로 만든다.
## 이전 프로젝트 little-monster-village(같은 저자, MIT)의 scripts/world/char_geo.gd(tri 의 자동 감김·도넛)와
## scripts/world/chars/demon_geo.gd(sculpt 조각 구·lathe 회전체)를 뼈·외곽선 없이 정적 메시용으로 옮겨 고쳤다.
## 좌표 관례: 위 +Y, 정면 -Z. 구의 극 = +Y, 경도 0 = 정면(-Z), 경도가 늘면 +X 쪽으로 돈다.

## 조각 겉면의 법선을 위도·경도 차분으로 구할 때의 각도 차(라디안)
const NORMAL_EPS := 0.01
## 극의 법선 = 극에서 이만큼 떨어진 작은 고리 법선들의 평균(꼭지가 기울어도 매끈하게)
const POLE_RING := 0.04
const POLE_SAMPLES := 8
## spread() 가 밀도 함수를 적분할 때 쓰는 표본 수
const SPREAD_SAMPLES := 720
## 이보다 작은 넓이(외적 길이 제곱)의 삼각형은 버린다(꼭짓점이 겹친 고리)
const DEGENERATE := 1e-14

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var idx := PackedInt32Array()
## 마지막 sculpt 의 격자(첫 정점 번호, 경도·위도 칸 수). grid_index·grid_loop 가 쓴다.
var grid_base := 0
var grid_segs := 0
var grid_rings := 0


## 정점 하나를 더하고 번호를 돌려준다. 법선은 단위 길이로 맞춘다.
func vert(p: Vector3, nn: Vector3, col: Color) -> int:
	v.append(p)
	n.append(nn.normalized())
	c.append(col)
	return v.size() - 1


## 삼각형. 세 정점 법선의 합을 바깥으로 보고 앞면 감김(Godot = 바깥에서 보아 시계 방향)을 자동으로 맞춘다.
## 넓이가 0 인 삼각형(극·꼭짓점에서 겹친 정점)은 넣지 않는다.
func tri(a: int, b: int, d: int) -> void:
	var cr := (v[b] - v[a]).cross(v[d] - v[a])
	if cr.length_squared() < DEGENERATE:
		return
	var nn := n[a] + n[b] + n[d]
	idx.append(a)
	if cr.dot(nn) > 0.0:
		idx.append(d)
		idx.append(b)
	else:
		idx.append(b)
		idx.append(d)


## 사각형 a-b-e-d(a→b 가 한 변, a→d 가 이웃 변, e 는 맞은편 꼭짓점)를 삼각형 둘로.
func quad(a: int, b: int, e: int, d: int) -> void:
	tri(a, b, d)
	tri(b, e, d)


## 단위 방향(위도 lat: 0 = +Y 극, 경도 lon: 0 = -Z)
static func direction(lat: float, lon: float) -> Vector3:
	return Vector3(sin(lat) * sin(lon), cos(lat), -sin(lat) * cos(lon))


## 단위 방향의 위도(0 = +Y 극 ~ PI = -Y 극)
static func lat_of(dir: Vector3) -> float:
	return acos(clampf(dir.y, -1.0, 1.0))


## 단위 방향의 경도(0 = -Z 정면, +X 쪽이 양수, -PI~PI)
static func lon_of(dir: Vector3) -> float:
	return atan2(dir.x, -dir.z)


## 가우스 혹: 방향 dir 이 중심 방향 cdir 에서 벗어난 각도에 따라 0~1(sigma = 라디안). demon_geo.bump 그대로.
static func bump(dir: Vector3, cdir: Vector3, sigma: float) -> float:
	var a := dir.angle_to(cdir)
	return exp(-(a * a) / (2.0 * sigma * sigma))


## 부드러운 최솟값(다항식 smin): 두 값이 k 안쪽으로 가까우면 모서리를 둥글린다.
static func smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


## 구간 [a0, a1] 을 count 칸으로 나눈 count + 1 개의 각도. density.call(각도) -> float(양수) 가 큰 곳에 칸이 촘촘하다.
## pins 의 각도에는 반드시 격자선이 놓인다(눈 윤곽을 감싸는 칸 묶음의 경계 등): 핀 사이 구간마다 밀도 적분에 비례해
## 칸 수를 나누고(최소 1, 큰 나머지 순) 구간 안에서 다시 밀도대로 나눈다. 적분 표를 만들어 역함수를 선형 보간한다.
static func spread(count: int, a0: float, a1: float, density: Callable, pins: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:
	var cum := PackedFloat64Array()
	cum.resize(SPREAD_SAMPLES + 1)
	cum[0] = 0.0
	var step := (a1 - a0) / float(SPREAD_SAMPLES)
	for k in SPREAD_SAMPLES:
		var mid := a0 + step * (float(k) + 0.5)
		cum[k + 1] = cum[k] + maxf(float(density.call(mid)), 0.0001) * step
	# 구간 경계: 양 끝 + 안쪽 핀(정렬, 겹침 제거)
	var edges := PackedFloat64Array([a0])
	var sorted_pins := pins.duplicate()
	sorted_pins.sort()
	for pin in sorted_pins:
		if pin > edges[edges.size() - 1] + 0.000001 and pin < a1 - 0.000001:
			edges.append(pin)
	edges.append(a1)
	var parts := edges.size() - 1
	# 구간별 칸 수: 밀도 적분 비례, 최소 1, 남는 칸은 나머지가 큰 구간부터
	var total := cum[SPREAD_SAMPLES]
	var share := PackedInt32Array()
	var rest: Array = []
	var used := 0
	for m in parts:
		var want := float(count) * (_cum_at(cum, a0, step, edges[m + 1]) - _cum_at(cum, a0, step, edges[m])) / total
		var got := maxi(1, int(floor(want)))
		share.append(got)
		used += got
		rest.append([want - float(got), m])
	rest.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
	var r := 0
	while used < count:
		share[int(rest[r % parts][1])] += 1
		used += 1
		r += 1
	while used > count:
		# 핀이 너무 많아 최소 1 칸씩만으로도 넘치면 가장 많이 받은 구간에서 덜어 낸다
		var big := 0
		for m in parts:
			if share[m] > share[big]:
				big = m
		if share[big] <= 1:
			break
		share[big] -= 1
		used -= 1
	var out := PackedFloat64Array([a0])
	for m in parts:
		var c0 := _cum_at(cum, a0, step, edges[m])
		var c1 := _cum_at(cum, a0, step, edges[m + 1])
		for i in range(1, share[m] + 1):
			out.append(edges[m + 1] if i == share[m] else _angle_at(cum, a0, step, lerpf(c0, c1, float(i) / float(share[m]))))
	return out


## 적분 표에서 각도 a 까지의 누적 밀도(선형 보간)
static func _cum_at(cum: PackedFloat64Array, a0: float, step: float, a: float) -> float:
	var x := clampf((a - a0) / step, 0.0, float(SPREAD_SAMPLES))
	var k := mini(int(floor(x)), SPREAD_SAMPLES - 1)
	return lerpf(cum[k], cum[k + 1], x - float(k))


## 누적 밀도 target 에 해당하는 각도(적분 표의 역, 이분 탐색 + 선형 보간)
static func _angle_at(cum: PackedFloat64Array, a0: float, step: float, target: float) -> float:
	var lo := 0
	var hi := SPREAD_SAMPLES
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] < target:
			lo = mid
		else:
			hi = mid
	var span := cum[hi] - cum[lo]
	var f := 0.0 if span <= 0.0 else clampf((target - cum[lo]) / span, 0.0, 1.0)
	return a0 + step * (float(lo) + f)


## 구 조각: shape.call(dir: Vector3) -> float(방향별 반지름 배수, 1.0 = 기본 구)로 중심 ce, 축별 반지름 r 의 구를 변형한다.
## 법선은 조각된 겉면을 위도·경도로 조금씩 움직인 차분의 외적으로 구해 매끈하다(demon_geo.sculpt).
## col_of.call(dir, p) -> Color 가 있으면 정점마다 색을 정한다(p = 중심 기준 조각된 점). 없으면 col 한 색.
## lats(rings + 1 개, 0 ~ PI)·lons(segs + 1 개, 처음과 끝이 TAU 차이)를 주면 그 각도에 격자를 놓는다. 비우면 고르게 나눈다.
## holes 의 칸 묶음(Rect2i: x = 경도 칸 j, y = 위도 칸 i)은 삼각형을 비워 둔다 — 같은 겉면 위에 다른 짜임(눈 고리 등)을 채울 자리.
## 격자 정점 번호는 grid_index(i, j), 구멍 둘레는 grid_loop(rect). 삼각형 수 = 2 × segs × (rings - 1)(두 극은 부채꼴) - 구멍.
func sculpt(ce: Vector3, r: Vector3, segs: int, rings: int, shape: Callable, col: Color = Color.WHITE,
		col_of: Callable = Callable(), lats: PackedFloat64Array = PackedFloat64Array(),
		lons: PackedFloat64Array = PackedFloat64Array(), holes: Array[Rect2i] = []) -> void:
	var la := lats
	if la.size() != rings + 1:
		la = PackedFloat64Array()
		for i in rings + 1:
			la.append(PI * float(i) / float(rings))
	var lo := lons
	if lo.size() != segs + 1:
		lo = PackedFloat64Array()
		for j in segs + 1:
			lo.append(TAU * float(j) / float(segs))
	grid_base = v.size()
	grid_segs = segs
	grid_rings = rings
	for i in rings + 1:
		var lat := la[i]
		var pole_n := Vector3.ZERO
		if i == 0 or i == rings:
			# 극: 둘레 작은 고리의 법선 평균(정점 사본 모두 같은 법선)
			var ring_lat := POLE_RING if i == 0 else PI - POLE_RING
			for k in POLE_SAMPLES:
				pole_n += _sculpt_n(r, ring_lat, TAU * float(k) / float(POLE_SAMPLES), shape)
			pole_n = pole_n.normalized()
		for j in segs + 1:
			var lon := lo[j]
			var p := sculpt_point(r, lat, lon, shape)
			var nn := pole_n if (i == 0 or i == rings) else _sculpt_n(r, lat, lon, shape)
			var cc := col
			if col_of.is_valid():
				cc = col_of.call(direction(lat, lon), p)
			vert(ce + p, nn, cc)
	for i in rings:
		for j in segs:
			var skip := false
			for h in holes:
				if h.has_point(Vector2i(j, i)):
					skip = true
			if skip:
				continue
			var a := grid_index(i, j)
			var b := a + 1
			var d := a + segs + 1
			var e := d + 1
			if i > 0:
				tri(a, b, d)
			if i < rings - 1:
				tri(b, e, d)


## 마지막 sculpt 격자의 (위도 i, 경도 j) 정점 번호
func grid_index(i: int, j: int) -> int:
	return grid_base + i * (grid_segs + 1) + j


## 칸 묶음 rect(x = j, y = i)의 둘레 정점 번호를 한 바퀴(위 변 → 오른쪽 변 → 아래 변 → 왼쪽 변) 순서로
func grid_loop(rect: Rect2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	var i0 := rect.position.y
	var j0 := rect.position.x
	var i1 := rect.end.y
	var j1 := rect.end.x
	for j in range(j0, j1):
		out.append(grid_index(i0, j))
	for i in range(i0, i1):
		out.append(grid_index(i, j1))
	for j in range(j1, j0, -1):
		out.append(grid_index(i1, j))
	for i in range(i1, i0, -1):
		out.append(grid_index(i, j0))
	return out


## 조각된 겉면의 점(중심 기준): 방향 × 축별 반지름 × 반지름 배수
static func sculpt_point(r: Vector3, lat: float, lon: float, shape: Callable) -> Vector3:
	var dir := direction(lat, lon)
	var k: float = shape.call(dir)
	return Vector3(dir.x * r.x, dir.y * r.y, dir.z * r.z) * k


## 조각된 겉면의 바깥 법선(위도·경도 중심 차분의 외적, 중심에서 멀어지는 쪽)
static func _sculpt_n(r: Vector3, lat: float, lon: float, shape: Callable) -> Vector3:
	var pa := sculpt_point(r, lat + NORMAL_EPS, lon, shape) - sculpt_point(r, lat - NORMAL_EPS, lon, shape)
	var pb := sculpt_point(r, lat, lon + NORMAL_EPS, shape) - sculpt_point(r, lat, lon - NORMAL_EPS, shape)
	var nn := pb.cross(pa).normalized()
	if nn.dot(sculpt_point(r, lat, lon, shape)) < 0.0:
		nn = -nn
	return nn


## 격자 밖의 정점 하나를 같은 조각 겉면(중심 ce, 반지름 r, shape) 위 방향 dir 에 둔다(법선도 겉면 그대로). 번호를 돌려준다.
func surface_vert(ce: Vector3, r: Vector3, dir: Vector3, shape: Callable, col: Color) -> int:
	var lat := lat_of(dir)
	var lon := lon_of(dir)
	return vert(ce + sculpt_point(r, lat, lon, shape), _sculpt_n(r, lat, lon, shape), col)


## 구 위의 점 center 에서 본 접평면 좌표(심사 투영, gnomonic): u = 경도가 느는 쪽(정면에서 +X), v = 위도가 느는 쪽(아래).
## 방향 dir 의 좌표 (u, v). 작은 각도에서는 라디안 각과 거의 같다.
static func tangent_uv(center: Vector3, dir: Vector3) -> Vector2:
	var lat := lat_of(center)
	var lon := lon_of(center)
	var eu := Vector3(cos(lon), 0.0, sin(lon))
	var ev := Vector3(cos(lat) * sin(lon), -sin(lat), -cos(lat) * cos(lon))
	var d := maxf(dir.dot(center), 0.0001)
	return Vector2(dir.dot(eu), dir.dot(ev)) / d


## tangent_uv 의 역: 점 center 의 접평면 좌표 (u, v) → 구 위 방향
static func tangent_dir(center: Vector3, uv: Vector2) -> Vector3:
	var lat := lat_of(center)
	var lon := lon_of(center)
	var eu := Vector3(cos(lon), 0.0, sin(lon))
	var ev := Vector3(cos(lat) * sin(lon), -sin(lat), -cos(lat) * cos(lon))
	return (center + eu * uv.x + ev * uv.y).normalized()


## 두 닫힌 고리를 삼각형 띠로 잇는다(정점 수가 달라도 됨). outer/inner = 정점 번호, ang_o/ang_i = 같은 중심 둘레의 각도.
## 두 고리 모두 그 중심에서 보아 별 모양(중심에서 뻗은 반직선이 한 번만 만남)이어야 한다. 각도 순으로 정렬해 쓰므로 순서는 자유.
## 삼각형 수 = 바깥 정점 수 + 안쪽 정점 수.
func zip_loops(outer: PackedInt32Array, ang_o: PackedFloat64Array, inner: PackedInt32Array, ang_i: PackedFloat64Array) -> void:
	var o := _sorted_loop(outer, ang_o)
	var q := _sorted_loop(inner, ang_i)
	var oi: PackedInt32Array = o[0]
	var oa: PackedFloat64Array = o[1]
	var ii: PackedInt32Array = q[0]
	var ia: PackedFloat64Array = q[1]
	var mo := oi.size()
	var mi := ii.size()
	# 각도를 안쪽 첫 정점 기준으로 펼친다: 바깥은 그와 가장 가까운 정점부터
	var start := 0
	var best := TAU
	for m in mo:
		var dd := absf(wrapf(oa[m] - ia[0], -PI, PI))
		if dd < best:
			best = dd
			start = m
	var uo := PackedFloat64Array()
	uo.resize(mo + 1)
	uo[0] = wrapf(oa[start] - ia[0], -PI, PI)
	for m in mo:
		uo[m + 1] = uo[m] + wrapf(oa[(start + m + 1) % mo] - oa[(start + m) % mo], 0.0, TAU)
	var ui := PackedFloat64Array()
	ui.resize(mi + 1)
	ui[0] = 0.0
	for k in mi:
		ui[k + 1] = ui[k] + wrapf(ia[(k + 1) % mi] - ia[k], 0.0, TAU)
	var a := 0
	var b := 0
	while a < mo or b < mi:
		var cur_o := oi[(start + a) % mo]
		var cur_i := ii[b % mi]
		if b >= mi or (a < mo and uo[a + 1] <= ui[b + 1]):
			tri(cur_o, oi[(start + a + 1) % mo], cur_i)
			a += 1
		else:
			tri(cur_o, ii[(b + 1) % mi], cur_i)
			b += 1


## 고리를 각도 순으로 정렬: [번호, 각도]
static func _sorted_loop(ids: PackedInt32Array, ang: PackedFloat64Array) -> Array:
	var order: Array = []
	for k in ids.size():
		order.append([ang[k], ids[k]])
	order.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var out_i := PackedInt32Array()
	var out_a := PackedFloat64Array()
	for e: Array in order:
		out_a.append(float(e[0]))
		out_i.append(int(e[1]))
	return [out_i, out_a]


## 닫힌 고리를 가운데 정점 하나로 부채꼴로 막는다.
func fan(center: int, loop: PackedInt32Array) -> void:
	for k in loop.size():
		tri(center, loop[k], loop[(k + 1) % loop.size()])


## 회전체: 프로파일 prof = [{y, r, col}](또는 단면이 타원이면 rx, rz)을 위에서 아래로. 고리끼리 정점을 공유해 매끈한 한 장이 된다.
## 법선은 프로파일 접선(앞뒤 마디 방향의 합)으로 구한다. 같은 자리의 마디를 두 번 넣으면 그 자리가 각진 모서리가 된다.
## 반지름 0 인 마디는 꼭짓점(뾰족한 끝). close_top/close_bottom 은 첫·끝 고리를 평평한 뚜껑으로 막는다.
## 경도 0 = 정면(-Z) 이고 segs 칸으로 고르게 돈다(lathe 는 demon_geo.lathe 에서 옮김).
func lathe(prof: Array, segs: int, close_top: bool = false, close_bottom: bool = false, center: Vector3 = Vector3.ZERO) -> void:
	var cnt := prof.size()
	if cnt < 2:
		return
	var base := v.size()
	for i in cnt:
		var P: Dictionary = prof[i]
		var y: float = P.y
		var rx: float = _prof_rx(P)
		var rz: float = _prof_rz(P)
		var col: Color = P.col
		# 프로파일 평면(반지름 s, 높이 y)의 접선: 길이 0 인 마디(각진 모서리용 겹침)는 빼고 앞뒤 방향을 더한다
		var t2 := Vector2.ZERO
		if i > 0:
			var Pp: Dictionary = prof[i - 1]
			var dp := Vector2((rx + rz) * 0.5 - (_prof_rx(Pp) + _prof_rz(Pp)) * 0.5, y - float(Pp.y))
			if dp.length() > 0.00001:
				t2 += dp.normalized()
		if i < cnt - 1:
			var Pn: Dictionary = prof[i + 1]
			var dn := Vector2((_prof_rx(Pn) + _prof_rz(Pn)) * 0.5 - (rx + rz) * 0.5, float(Pn.y) - y)
			if dn.length() > 0.00001:
				t2 += dn.normalized()
		# 위→아래로 내려가는 접선 (ds, dy) 의 바깥 법선 = (-dy, ds)
		var n2 := Vector2(-t2.y, t2.x).normalized() if t2.length() > 0.00001 else Vector2(1.0, 0.0)
		for j in segs + 1:
			var lon := TAU * float(j) / float(segs)
			var sx := sin(lon)
			var cz := -cos(lon)
			var p := center + Vector3(sx * rx, y, cz * rz)
			var radial := Vector3(sx / maxf(rx, 0.0001), 0.0, cz / maxf(rz, 0.0001)).normalized()
			vert(p, radial * n2.x + Vector3.UP * n2.y, col)
	for i in cnt - 1:
		for j in segs:
			var i0 := base + i * (segs + 1) + j
			var i1 := i0 + segs + 1
			quad(i0, i0 + 1, i1 + 1, i1)
	for k in 2:
		if (k == 0 and not close_top) or (k == 1 and not close_bottom):
			continue
		var P: Dictionary = prof[0] if k == 0 else prof[cnt - 1]
		var nn := Vector3.UP if k == 0 else Vector3.DOWN
		var cb := vert(center + Vector3(0.0, P.y, 0.0), nn, P.col)
		for j in segs:
			var lon := TAU * float(j) / float(segs)
			vert(center + Vector3(sin(lon) * _prof_rx(P), P.y, -cos(lon) * _prof_rz(P)), nn, P.col)
		for j in segs:
			tri(cb, cb + 1 + j, cb + 1 + (j + 1) % segs)


static func _prof_rx(P: Dictionary) -> float:
	return float(P.get("rx", P.get("r", 0.0)))


static func _prof_rz(P: Dictionary) -> float:
	return float(P.get("rz", P.get("r", 0.0)))


## 도넛(축 = +Y). 관 단면을 y 방향으로 flat 배 눌러 납작하게 할 수 있다(char_geo.torus 에 납작 비율을 더함).
func torus(ce: Vector3, big_r: float, tube_r: float, col: Color, segs: int = 32, rings: int = 6, flat: float = 1.0) -> void:
	var base := v.size()
	for i in segs + 1:
		var a := TAU * float(i) / float(segs)
		var cdir := Vector3(sin(a), 0.0, -cos(a))
		for j in rings + 1:
			var b := TAU * float(j) / float(rings)
			var p := ce + cdir * (big_r + tube_r * cos(b)) + Vector3.UP * (tube_r * flat * sin(b))
			# 눌린 타원 단면의 법선: (cos b, sin b / flat)
			var nn := cdir * cos(b) + Vector3.UP * (sin(b) / maxf(flat, 0.0001))
			vert(p, nn, col)
	for i in segs:
		for j in rings:
			var i0 := base + i * (rings + 1) + j
			var i1 := i0 + rings + 1
			quad(i0, i1, i1 + 1, i0 + 1)


## 양면 잎: 뿌리 root 에서 위로 솟았다가 out(수평 단위 벡터) 쪽으로 휘어 끝이 뾰족한 잎 한 장.
## 가운데 잎맥이 fold 만큼 솟은 V 단면이라 빛을 받으면 두 쪽의 밝기가 다르다. 뒷면은 법선을 뒤집은 사본(재질의 뒷면 컬링과 무관).
## 높이 h, 휘어 나가는 거리 reach, 최대 폭 w. 한 면 8 삼각형(양면 16). col_tip 으로 끝을 밝게 한다.
func leaf(root: Vector3, out: Vector3, h: float, reach: float, w: float, fold: float, col_base: Color, col_tip: Color) -> void:
	var o := Vector3(out.x, 0.0, out.z).normalized()
	var side := Vector3.UP.cross(o).normalized()
	# 잎맥을 따라가는 2차 베지어(뿌리 → 위 → 바깥으로 휨): 마디 4 개(뿌리·1/3·2/3·끝)
	var p1 := root + Vector3.UP * (h * 0.9) + o * (reach * 0.15)
	var p2 := root + Vector3.UP * h + o * reach
	var ts: Array[float] = [0.0, 0.4, 0.72, 1.0]
	var widths: Array[float] = [0.0, 1.0, 0.75, 0.0]
	for s: float in [1.0, -1.0]:
		var rows: Array = []
		for k in ts.size():
			var t: float = ts[k]
			var u := 1.0 - t
			var p := root * (u * u) + p1 * (2.0 * u * t) + p2 * (t * t)
			var along := ((p1 - root) * (2.0 * u) + (p2 - p1) * (2.0 * t)).normalized()
			var face_n := side.cross(along).normalized()
			if face_n.y < 0.0:
				face_n = -face_n
			var col := col_base.lerp(col_tip, t)
			var half := w * 0.5 * widths[k]
			var row := PackedInt32Array()
			if half <= 0.0:
				row.append(vert(p, face_n * s, col))
			else:
				# V 단면: 가장자리는 잎맥보다 fold 만큼 낮다(양쪽 법선은 바깥으로 조금 기운다)
				var drop := face_n * (fold * half)
				row.append(vert(p - side * half - drop, (face_n + side * 0.35).normalized() * s, col.darkened(0.08)))
				row.append(vert(p, face_n * s, col.lightened(0.06)))
				row.append(vert(p + side * half - drop, (face_n - side * 0.35).normalized() * s, col.darkened(0.08)))
			rows.append(row)
		for k in ts.size() - 1:
			var ra: PackedInt32Array = rows[k]
			var rb: PackedInt32Array = rows[k + 1]
			if ra.size() == 1:
				tri(ra[0], rb[0], rb[1])
				tri(ra[0], rb[1], rb[2])
			elif rb.size() == 1:
				tri(ra[0], ra[1], rb[0])
				tri(ra[1], ra[2], rb[0])
			else:
				quad(ra[0], ra[1], rb[1], rb[0])
				quad(ra[1], ra[2], rb[2], rb[1])


## 작은 양면 잎(떡잎·싹): 뿌리 root 에서 끝 tip 까지 마름모 한 장, 최대 폭 w(가운데보다 조금 뿌리 쪽). 한 면 2, 양면 4 삼각형.
func petal(root: Vector3, tip: Vector3, w: float, col_base: Color, col_tip: Color) -> void:
	var along := tip - root
	var side := along.cross(Vector3.UP)
	if side.length() < 0.00001:
		side = Vector3.RIGHT
	side = side.normalized()
	var face_n := side.cross(along).normalized()
	if face_n.y < 0.0:
		face_n = -face_n
	var mid := root + along * 0.42
	for s: float in [1.0, -1.0]:
		var nn := face_n * s
		var a := vert(root, nn, col_base)
		var b := vert(mid + side * (w * 0.5), nn, col_base.lerp(col_tip, 0.5))
		var t := vert(tip, nn, col_tip)
		var d := vert(mid - side * (w * 0.5), nn, col_base.lerp(col_tip, 0.5))
		quad(a, b, t, d)


## 정점 from 번부터 끝까지 옮긴다.
func translate(off: Vector3, from: int = 0) -> void:
	for i in range(from, v.size()):
		v[i] += off


## 정점 from 번부터 끝까지 균일 배율(원점 기준). 법선은 그대로.
func scale_uniform(k: float, from: int = 0) -> void:
	for i in range(from, v.size()):
		v[i] *= k


## 정점 from 번부터 끝까지 변환(위치는 xf, 법선은 xf.basis 의 역전치).
func transform(xf: Transform3D, from: int = 0) -> void:
	var nb := xf.basis.inverse().transposed()
	for i in range(from, v.size()):
		v[i] = xf * v[i]
		n[i] = (nb * n[i]).normalized()


## 정점들의 경계 상자
func bounds() -> AABB:
	if v.is_empty():
		return AABB()
	var box := AABB(v[0], Vector3.ZERO)
	for p in v:
		box = box.expand(p)
	return box


func triangles() -> int:
	return int(idx.size() / 3.0)


## ArrayMesh 로(정점·법선·정점 색·번호). material 을 주면 표면 재질로 붙인다.
func to_mesh(material: Material = null) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if material != null:
		m.surface_set_material(0, material)
	return m
