extends RefCounted
## SlimeGeo·ProcGeo 검사(헤드리스): 삼각형 예산, 슬라임 모양(바닥 y 0, 정면 -Z 의 눈, 가로·세로 비), 법선(단위 길이·바깥쪽·감김),
## 정점 색, 닫힌 겉면(눈·입 구멍 메움에 틈이 없음), 캐시, 재질, 조립기 기본 도형. tests/run_view_tests.gd 가 불러 run(t) 을 부른다.

## 이 모듈이 적어도 하는 검사 수(중간에 스크립트 오류로 끊기면 실행기가 실패로 셈)
const MIN_CHECKS := 76
## 법선은 메시에 압축(8면체 부호화)되어 저장되므로 길이 허용 오차를 둔다
const NORMAL_TOL := 0.02
## 어두운 정점(눈·입) 판정 밝기
const DARK := 0.25
## 위치를 같은 점으로 묶을 때의 격자 크기(정점 두 벌 경계를 하나로)
const WELD := 0.00001


func run(t) -> void:
	_budgets(t)
	_slime_shape(t)
	_normals_and_colors(t)
	_closed_surface(t)
	_cache_and_materials(t)
	_props(t)
	_proc_geo(t)


## 메시마다 삼각형 예산(ui.json)과 triangle_count 가 번호 배열과 일치하는지
func _budgets(t) -> void:
	var budget := {
		slime_mesh = UiConfig.integer("slime.triangles_max"),
		plant_mesh = UiConfig.integer("buildings.plant_triangles_max"),
		berry_mesh = UiConfig.integer("buildings.berry_triangles_max"),
		storehouse_mesh = UiConfig.integer("buildings.store_triangles_max"),
		farm_mesh = UiConfig.integer("buildings.farm_triangles_max"),
		ring_mesh = UiConfig.integer("buildings.ring_triangles_max"),
	}
	for name: String in budget:
		var m: ArrayMesh = Callable(SlimeGeo, name).call()
		var tris := SlimeGeo.triangle_count(m)
		var arr := m.surface_get_arrays(0)
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		t.check(tris > 0 and tris <= int(budget[name]), "%s 삼각형 %d ≤ 예산 %d" % [name, tris, int(budget[name])])
		t.check(tris * 3 == ind.size(), "%s triangle_count 가 번호 배열과 같음(%d)" % [name, tris])
	# 번호 없는 메시·기본 도형도 센다
	var bm := BoxMesh.new()
	t.check(SlimeGeo.triangle_count(bm) == 12, "triangle_count(BoxMesh) = 12")
	var raw := ArrayMesh.new()
	var arr2 := []
	arr2.resize(Mesh.ARRAY_MAX)
	arr2[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.ZERO, Vector3.UP, Vector3.BACK])
	raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
	t.check(SlimeGeo.triangle_count(raw) == 2, "triangle_count(번호 없는 메시) = 2")
	t.check(SlimeGeo.triangle_count(null) == 0, "triangle_count(null) = 0")


## 슬라임: 바닥 y 0, 가장 넓은 가로 반지름 = ui.slime.radius, 가로·세로 비, 눈은 정면(-Z)의 좌우 두 무리, 몸은 흰색 계열
func _slime_shape(t) -> void:
	var m := SlimeGeo.slime_mesh()
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var box := m.get_aabb()
	var radius := UiConfig.num("slime.radius")
	t.check(absf(box.position.y) < 0.0001, "슬라임 바닥 y = 0 (%.5f)" % box.position.y)
	var wide := 0.0
	for p in v:
		wide = maxf(wide, Vector2(p.x, p.z).length())
	t.check(absf(wide - radius) < 0.001, "슬라임 가장 넓은 가로 반지름 = ui.slime.radius (%.4f)" % wide)
	var width := box.size.x
	var height := box.size.y
	t.check(width / height > 1.2 and width / height < 1.8, "슬라임 가로/높이 비 1.2~1.8 (%.2f)" % (width / height))
	t.check(absf(box.size.z - box.size.x) < 0.1 * width, "슬라임 앞뒤 폭 ≈ 좌우 폭 (%.3f / %.3f)" % [box.size.z, box.size.x])
	# 꼭지: 가장 높은 점이 가운데 근처(가로 반지름의 25% 안)
	var top := v[0]
	for p in v:
		if p.y > top.y:
			top = p
	t.check(Vector2(top.x, top.z).length() < 0.25 * radius, "슬라임 꼭대기가 가운데 근처")
	var left := 0
	var right := 0
	var dark_all_front := true
	var dark_y := 0.0
	var dark_n := 0
	var light := 0
	for i in v.size():
		var lum := col[i].get_luminance()
		if lum < DARK:
			dark_n += 1
			dark_y += v[i].y
			if v[i].z >= 0.0:
				dark_all_front = false
			if v[i].x < -0.02 * radius:
				left += 1
			elif v[i].x > 0.02 * radius:
				right += 1
		elif lum > 0.7:
			light += 1
	t.check(dark_n > 0 and dark_all_front, "눈·입(어두운 정점)은 모두 정면(-Z) 쪽 (%d개)" % dark_n)
	t.check(left >= 8 and right >= 8 and absi(left - right) <= 2, "두 눈이 좌우 대칭 (왼쪽 %d, 오른쪽 %d)" % [left, right])
	if dark_n > 0:
		var mean_y := dark_y / float(dark_n)
		t.check(mean_y > 0.3 * height and mean_y < 0.8 * height, "눈 높이가 몸의 30~80%% (%.0f%%)" % (100.0 * mean_y / height))
	t.check(float(light) / float(v.size()) > 0.6, "몸 정점 색 대부분이 흰색 계열(인스턴스 색이 곱해짐) (%d/%d)" % [light, v.size()])
	var shine := 0
	var shine_col := UiConfig.color("slime.eye_shine")
	for i in v.size():
		# 반사점: 흰 정점 중 눈 높이에서 정면 쪽(-Z 로 가장 튀어나온 쪽 절반)에 있는 것
		if col[i].is_equal_approx(shine_col) and v[i].z < -0.5 * radius and v[i].y > 0.45 * height:
			shine += 1
	t.check(shine >= 2, "눈마다 흰 반사점 정점이 있음 (%d)" % shine)


## 모든 메시: 법선 단위 길이, 정점 색 있음, 삼각형 감김이 법선과 맞음(앞면 = 바깥에서 시계 방향). 슬라임은 법선이 모두 바깥쪽.
func _normals_and_colors(t) -> void:
	for name in ["slime_mesh", "plant_mesh", "berry_mesh", "storehouse_mesh", "farm_mesh", "ring_mesh"]:
		var m: ArrayMesh = Callable(SlimeGeo, name).call()
		var arr := m.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var col: Variant = arr[Mesh.ARRAY_COLOR]
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var unit := true
		for x in nn:
			if absf(x.length() - 1.0) > NORMAL_TOL:
				unit = false
		t.check(nn.size() == v.size() and unit, "%s 법선이 정점마다 단위 길이" % name)
		t.check(col is PackedColorArray and (col as PackedColorArray).size() == v.size(), "%s 정점 색이 있음" % name)
		var wrong := 0
		for k in range(0, ind.size(), 3):
			var a := v[ind[k]]
			var b := v[ind[k + 1]]
			var c := v[ind[k + 2]]
			var face := (c - a).cross(b - a)
			if face.dot(nn[ind[k]] + nn[ind[k + 1]] + nn[ind[k + 2]]) <= 0.0:
				wrong += 1
		t.check(wrong == 0, "%s 삼각형 앞면 감김이 법선과 맞음 (어긋남 %d)" % [name, wrong])
	var sm := SlimeGeo.slime_mesh()
	var sa := sm.surface_get_arrays(0)
	var sv: PackedVector3Array = sa[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = sa[Mesh.ARRAY_NORMAL]
	var center := sm.get_aabb().get_center()
	var inward := 0
	for i in sv.size():
		if sn[i].dot(sv[i] - center) <= 0.0:
			inward += 1
	t.check(inward == 0, "슬라임 법선이 모두 바깥쪽(중심에서 멀어지는 쪽) (안쪽 %d)" % inward)


## 슬라임 겉면이 닫혀 있다: 위치로 정점을 묶으면 모든 모서리를 정확히 두 삼각형이 나눠 쓴다(눈·입 구멍 메움에 틈·겹침이 없음)
func _closed_surface(t) -> void:
	for name in ["slime_mesh"]:
		var m: ArrayMesh = Callable(SlimeGeo, name).call()
		var arr := m.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var weld := {}
		var id_of := PackedInt32Array()
		for p in v:
			var key := Vector3i(roundi(p.x / WELD), roundi(p.y / WELD), roundi(p.z / WELD))
			if not weld.has(key):
				weld[key] = weld.size()
			id_of.append(int(weld[key]))
		var edges := {}
		for k in range(0, ind.size(), 3):
			for e in 3:
				var a := id_of[ind[k + e]]
				var b := id_of[ind[k + (e + 1) % 3]]
				var key := Vector2i(mini(a, b), maxi(a, b))
				edges[key] = int(edges.get(key, 0)) + 1
		var open := 0
		for key: Vector2i in edges:
			if int(edges[key]) != 2:
				open += 1
		t.check(open == 0, "%s 겉면이 닫혀 있음(모서리마다 삼각형 둘, 어긋난 모서리 %d)" % [name, open])
		# 오일러 지표: 닫힌 구 = 정점 - 모서리 + 면 = 2
		var euler := weld.size() - edges.size() + int(ind.size() / 3.0)
		t.check(euler == 2, "%s 는 구와 같은 위상(오일러 지표 %d)" % [name, euler])


## 캐시(같은 객체), 재질(정점 색 사용, 투명 없음), 다시 만들어도 같은 배열(결정적)
func _cache_and_materials(t) -> void:
	for name in ["slime_mesh", "plant_mesh", "berry_mesh", "storehouse_mesh", "farm_mesh", "ring_mesh", "slime_material", "shared_material"]:
		var a: Variant = Callable(SlimeGeo, name).call()
		var b: Variant = Callable(SlimeGeo, name).call()
		t.check(a != null and is_same(a, b), "%s 캐시(두 번 불러도 같은 객체)" % name)
	for name in ["slime_material", "shared_material"]:
		var m: Variant = Callable(SlimeGeo, name).call()
		var ok: bool = m is StandardMaterial3D and (m as StandardMaterial3D).vertex_color_use_as_albedo \
			and (m as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
		t.check(ok, "%s: 정점 색을 바탕색으로, 투명 없음" % name)
	var sm := SlimeGeo.slime_material() as StandardMaterial3D
	t.check(sm.roughness < 0.5 and sm.rim_enabled, "슬라임 재질이 윤기 있음(거칠기 %.2f, 가장자리 빛)" % sm.roughness)
	t.check(is_same(SlimeGeo.slime_mesh().surface_get_material(0), SlimeGeo.slime_material()), "슬라임 메시 표면 재질 = slime_material()")
	var again := SlimeGeo._build_slime()
	var va: PackedVector3Array = again.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var vb: PackedVector3Array = SlimeGeo.slime_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	t.check(va == vb, "슬라임 메시를 다시 만들어도 같은 정점(결정적)")


## 풀포기·열매·저장고·밭·고리 크기와 바닥
func _props(t) -> void:
	for name in ["plant_mesh", "berry_mesh", "storehouse_mesh", "farm_mesh", "ring_mesh"]:
		var m: ArrayMesh = Callable(SlimeGeo, name).call()
		t.check(absf(m.get_aabb().position.y) < 0.0001, "%s 바닥 y = 0" % name)
	var plant := SlimeGeo.plant_mesh().get_aabb()
	t.check(absf(plant.size.y - 1.0) < 0.001, "풀포기 높이 1 (%.3f)" % plant.size.y)
	var berry := SlimeGeo.berry_mesh().get_aabb()
	t.check(berry.size.x > 0.85 and berry.size.x < 1.05 and berry.size.y < 1.1, "열매 지름 약 1 (%.2f × %.2f)" % [berry.size.x, berry.size.y])
	var store := SlimeGeo.storehouse_mesh()
	var sb := store.get_aabb()
	t.check(sb.size.x <= 1.0 and sb.size.z <= 1.0 and sb.size.y > 0.9 and sb.size.y < 1.2, "저장고가 한 칸 안(%.2f × %.2f × %.2f)" % [sb.size.x, sb.size.y, sb.size.z])
	var door := UiConfig.color("buildings.store_door")
	var sa := store.surface_get_arrays(0)
	var sv: PackedVector3Array = sa[Mesh.ARRAY_VERTEX]
	var sc: PackedColorArray = sa[Mesh.ARRAY_COLOR]
	var door_n := 0
	var door_front := true
	for i in sv.size():
		if sc[i].is_equal_approx(door) or sc[i].is_equal_approx(door.lightened(0.08)):
			door_n += 1
			if sv[i].z >= 0.0:
				door_front = false
	t.check(door_n > 0 and door_front, "저장고 문은 정면(-Z) (%d 정점)" % door_n)
	var farm := SlimeGeo.farm_mesh().get_aabb()
	t.check(farm.size.x <= 1.0 and farm.size.z <= 1.0 and farm.size.y < 0.25, "밭이 한 칸 안, 낮음(높이 %.2f)" % farm.size.y)
	var ring := SlimeGeo.ring_mesh().get_aabb()
	t.check(absf(ring.size.x * 0.5 - 1.0) < 0.01 and ring.size.y < 0.1, "고리 반지름 1, 납작함(높이 %.3f)" % ring.size.y)


## 조립기 기본 도형: 구 조각 삼각형 수·반지름·법선, 회전체 법선, 핀 격자, 고리 잇기
func _proc_geo(t) -> void:
	var g := ProcGeo.new()
	var one := func(_d: Vector3) -> float: return 1.0
	g.sculpt(Vector3.ZERO, Vector3.ONE, 12, 6, one)
	t.check(g.triangles() == 2 * 12 * 5, "구 조각 삼각형 수 = 2 × 칸 × (고리 - 1) (%d)" % g.triangles())
	var round_ok := true
	for i in g.v.size():
		if absf(g.v[i].length() - 1.0) > 0.0001 or g.n[i].dot(g.v[i]) < 0.999:
			round_ok = false
	t.check(round_ok, "구 조각(배수 1) = 단위 구, 법선 = 위치 방향")
	var h := ProcGeo.new()
	h.lathe([{y = 1.0, r = 0.5, col = Color.WHITE}, {y = 0.0, r = 0.5, col = Color.WHITE}], 8, true, true)
	var side_ok := true
	for i in 18:
		if absf(h.n[i].y) > 0.001:
			side_ok = false
	t.check(side_ok and h.triangles() == 8 * 2 + 8 * 2, "회전체 원기둥: 옆 법선 수평, 삼각형 %d" % h.triangles())
	var pins := PackedFloat64Array([0.3, 1.1])
	var s := ProcGeo.spread(10, 0.0, PI, func(_a: float) -> float: return 1.0, pins)
	t.check(s.size() == 11 and s.has(0.3) and s.has(1.1) and s[0] == 0.0 and s[10] == PI, "spread: 칸 수 + 1 개, 핀에 격자선")
	var mono := true
	for i in 10:
		if s[i + 1] <= s[i]:
			mono = false
	t.check(mono, "spread: 각도가 커지는 순서")
	var z := ProcGeo.new()
	var outer := PackedInt32Array()
	var ang_o := PackedFloat64Array()
	for k in 6:
		var a := TAU * float(k) / 6.0
		outer.append(z.vert(Vector3(cos(a), 0.0, sin(a)), Vector3.UP, Color.WHITE))
		ang_o.append(a)
	var inner := PackedInt32Array()
	var ang_i := PackedFloat64Array()
	for k in 10:
		var a := TAU * float(k) / 10.0 + 0.1
		inner.append(z.vert(Vector3(cos(a), 0.0, sin(a)) * 0.5, Vector3.UP, Color.WHITE))
		ang_i.append(a)
	z.zip_loops(outer, ang_o, inner, ang_i)
	t.check(z.triangles() == 16, "고리 잇기 삼각형 수 = 바깥 + 안쪽 정점 수 (%d)" % z.triangles())
