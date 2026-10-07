class_name SlimeGeo
extends RefCounted
## (뼈대) 절차적 메시. 계약: docs/VIEW-API.md "SlimeGeo". 실제 조각 메시로 바꿀 예정.

static var _cache: Dictionary = {}


static func _cached(key: String, maker: Callable) -> ArrayMesh:
	if not _cache.has(key):
		_cache[key] = maker.call()
	return _cache[key]


static func _from_primitive(p: PrimitiveMesh) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, p.get_mesh_arrays())
	return am


static func slime_mesh() -> ArrayMesh:
	return _cached("slime", func():
		var s := SphereMesh.new()
		s.radius = UiConfig.num("slime.radius")
		s.height = UiConfig.num("slime.radius") * 1.6
		s.radial_segments = 12
		s.rings = 6
		return _from_primitive(s))


static func slime_material() -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	return m


static func shared_material() -> Material:
	return slime_material()


static func plant_mesh() -> ArrayMesh:
	return _cached("plant", func():
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.4
		c.height = 1.0
		return _from_primitive(c))


static func berry_mesh() -> ArrayMesh:
	return _cached("berry", func():
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 1.0
		return _from_primitive(s))


static func storehouse_mesh() -> ArrayMesh:
	return _cached("store", func():
		var b := BoxMesh.new()
		b.size = Vector3(0.8, 0.6, 0.8)
		return _from_primitive(b))


static func farm_mesh() -> ArrayMesh:
	return _cached("farm", func():
		var b := BoxMesh.new()
		b.size = Vector3(1.0, 0.05, 1.0)
		return _from_primitive(b))


static func ring_mesh() -> ArrayMesh:
	return _cached("ring", func():
		var t := TorusMesh.new()
		t.inner_radius = 0.8
		t.outer_radius = 1.0
		return _from_primitive(t))


static func triangle_count(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		n += idx.size() / 3 if not idx.is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n
