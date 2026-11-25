class_name MarkShapes
extends RefCounted
## Thin rotated marks for evidence recipes (scrapes, scratches, wet prints). MeshBuilder only has axis-aligned
## boxes, so these emit single quads at any angle on the floor (facing up) or on a door leaf (facing +Z / -Z).
## Corners are always clockwise as seen from the front (Godot front faces).


static func floor_rect(mb: MeshBuilder, mat: StringName, center: Vector3, along: Vector2, length: float, width: float, y: float = 0.0) -> void:
	## A length x width rectangle lying on the floor around `center` (xz), long axis along `along` (xz direction).
	var u := along.normalized() if along.length() > 0.0001 else Vector2(1, 0)
	var v := Vector2(-u.y, u.x)
	var hl := length * 0.5
	var hw := width * 0.5
	var c := Vector2(center.x, center.z)
	var p0 := c - u * hl - v * hw
	var p1 := c + u * hl - v * hw
	var p2 := c + u * hl + v * hw
	var p3 := c - u * hl + v * hw
	mb.quad(mat, Vector3(p0.x, y, p0.y), Vector3(p1.x, y, p1.y), Vector3(p2.x, y, p2.y), Vector3(p3.x, y, p3.y), Vector3.UP)


static func floor_line(mb: MeshBuilder, mat: StringName, a: Vector3, b: Vector3, width: float, y: float = 0.0) -> void:
	## A line of `width` from a to b (xz) on the floor.
	var d := Vector2(b.x - a.x, b.z - a.z)
	if d.length() < 0.001:
		return
	floor_rect(mb, mat, (a + b) * 0.5, d, d.length(), width, y)


static func leaf_line(mb: MeshBuilder, mat: StringName, p0: Vector2, p1: Vector2, width: float, z: float, facing_plus_z: bool = true) -> void:
	## A line on a door leaf (leaf-local xy) at depth z, visible from +Z (or -Z when facing_plus_z is false).
	var d := p1 - p0
	if d.length() < 0.001:
		return
	var dir := d.normalized()
	var n := Vector2(dir.y, -dir.x) * (width * 0.5)
	var bl := p0 - n
	var tl := p1 - n
	var tr := p1 + n
	var br := p0 + n
	if facing_plus_z:
		mb.quad(mat, Vector3(bl.x, bl.y, z), Vector3(tl.x, tl.y, z), Vector3(tr.x, tr.y, z), Vector3(br.x, br.y, z), Vector3(0, 0, 1))
	else:
		mb.quad(mat, Vector3(br.x, br.y, z), Vector3(tr.x, tr.y, z), Vector3(tl.x, tl.y, z), Vector3(bl.x, bl.y, z), Vector3(0, 0, -1))


static func mark_node(def: EvidenceDef, mb: MeshBuilder) -> EvidenceMark:
	## An EvidenceMark carrying the mesh (needs light or the lamp to be read, SPEC 4.3).
	var holder := EvidenceMark.create(def)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	holder.needs_light = true
	return holder
