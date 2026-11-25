class_name MeshBuilder
extends RefCounted
## Accumulates quads per material and commits ONE surface per material, so a whole chunk is a handful
## of draw calls. Godot front faces are CLOCKWISE: every quad takes its four corners clockwise as seen
## from the front (the side the normal points to).
##
## Material keys: a library name (e.g. &"wall_yellow"), or "#rrggbb" for a flat colour (cube props).

class Batch extends RefCounted:
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()

var _batches: Dictionary = {}     ## StringName -> Batch
var _order: Array[StringName] = []


func is_empty() -> bool:
	return _batches.is_empty()


func quad_count() -> int:
	var n := 0
	for k in _batches:
		n += (_batches[k] as Batch).indices.size() / 6
	return n


func quad(mat: StringName, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3,
		ua: Vector2 = Vector2(0, 0), ub: Vector2 = Vector2(0, 1),
		uc: Vector2 = Vector2(1, 1), ud: Vector2 = Vector2(1, 0)) -> void:
	var bt := _batch(mat)
	var base := bt.verts.size()
	bt.verts.append(a)
	bt.verts.append(b)
	bt.verts.append(c)
	bt.verts.append(d)
	bt.normals.append(normal)
	bt.normals.append(normal)
	bt.normals.append(normal)
	bt.normals.append(normal)
	bt.uvs.append(ua)
	bt.uvs.append(ub)
	bt.uvs.append(uc)
	bt.uvs.append(ud)
	bt.indices.append(base)
	bt.indices.append(base + 1)
	bt.indices.append(base + 2)
	bt.indices.append(base)
	bt.indices.append(base + 2)
	bt.indices.append(base + 3)


func box(mat: StringName, center: Vector3, size: Vector3, skip_bottom: bool = false) -> void:
	## Axis-aligned box, outward faces. Corners clockwise from outside each face.
	var h := size * 0.5
	var x0 := center.x - h.x
	var x1 := center.x + h.x
	var y0 := center.y - h.y
	var y1 := center.y + h.y
	var z0 := center.z - h.z
	var z1 := center.z + h.z
	# +Z (south) face, seen from +Z looking toward -Z: right = +X... clockwise = BL, TL, TR, BR
	quad(mat, Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3(0, 0, 1),
		Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	# -Z (north) face, seen from -Z looking toward +Z: right = -X
	quad(mat, Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3(0, 0, -1),
		Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	# +X (east) face, seen from +X: right = -Z
	quad(mat, Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3(1, 0, 0),
		Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	# -X (west) face, seen from -X: right = +Z
	quad(mat, Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3(-1, 0, 0),
		Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	# +Y (top), seen from above: clockwise = NW, NE, SE, SW
	quad(mat, Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(0, 1, 0),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	if not skip_bottom:
		# -Y (bottom), seen from below: clockwise = NW, SW, SE, NE
		quad(mat, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(0, -1, 0),
			Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))


func floor_quad(mat: StringName, x0: float, z0: float, x1: float, z1: float, y: float = 0.0) -> void:
	quad(mat, Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1), Vector3.UP,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


func ceiling_quad(mat: StringName, x0: float, z0: float, x1: float, z1: float, y: float) -> void:
	quad(mat, Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), Vector3.DOWN,
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))


func wall_quad(mat: StringName, edge_center: Vector3, dir: Vector2i, width: float, height: float,
		y0: float = 0.0, uv_x0: float = 0.0, uv_x1: float = 1.0) -> void:
	## A wall plane on the edge toward `dir` of a tile whose edge midpoint is `edge_center` (y ignored),
	## facing INTO the tile (normal = -dir). Viewed from inside the tile looking toward dir,
	## right = dir rotated clockwise. Corners clockwise: BL, TL, TR, BR.
	var right := Dir.to_vec3(Dir.rot(dir, 1))
	var half := right * (width * 0.5)
	var c := Vector3(edge_center.x, 0.0, edge_center.z)
	var bl := c - half + Vector3(0, y0, 0)
	var br := c + half + Vector3(0, y0, 0)
	var tl := bl + Vector3(0, height, 0)
	var tr := br + Vector3(0, height, 0)
	quad(mat, bl, tl, tr, br, -Dir.to_vec3(dir),
		Vector2(uv_x0, 1), Vector2(uv_x0, 0), Vector2(uv_x1, 0), Vector2(uv_x1, 1))


func build(resolver: Callable = Callable()) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var keys: Array = _batches.keys()
	keys.sort_custom(func(a, b): return String(a) < String(b))
	for k in keys:
		var bt: Batch = _batches[k]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = bt.verts
		arrays[Mesh.ARRAY_NORMAL] = bt.normals
		arrays[Mesh.ARRAY_TEX_UV] = bt.uvs
		arrays[Mesh.ARRAY_INDEX] = bt.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat: Material
		if resolver.is_valid():
			mat = resolver.call(k)
		else:
			mat = default_resolver(k)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


static func default_resolver(key: StringName) -> Material:
	var s := String(key)
	if s.begins_with("#"):
		return MaterialLibrary.solid(key, Color(s))
	if s.begins_with("*"):
		# self-lit flat colour, e.g. "*#ffcc66"
		return MaterialLibrary.unlit_color(key, Color(s.substr(1)))
	return MaterialLibrary.get_material(key)


func _batch(mat: StringName) -> Batch:
	if not _batches.has(mat):
		_batches[mat] = Batch.new()
		_order.append(mat)
	return _batches[mat]
