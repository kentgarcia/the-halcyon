class_name Dir
extends RefCounted
## Tile-grid directions. Tile coordinates are (x, z); north is -z (Godot forward), east is +x.
## Quarter-turn rotation k is CLOCKWISE when viewed from above.

const N := Vector2i(0, -1)
const E := Vector2i(1, 0)
const S := Vector2i(0, 1)
const W := Vector2i(-1, 0)
const ALL: Array[Vector2i] = [N, E, S, W]
const ALL8: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]


static func rot(v: Vector2i, k: int) -> Vector2i:
	## Rotate a tile vector by k quarter turns clockwise: N(0,-1) -> E(1,0) -> S(0,1) -> W(-1,0).
	var r := v
	for _i in range(posmod(k, 4)):
		r = Vector2i(-r.y, r.x)
	return r


static func index_of(d: Vector2i) -> int:
	return ALL.find(d)


static func turns_between(from_dir: Vector2i, to_dir: Vector2i) -> int:
	## Number of clockwise quarter turns taking from_dir to to_dir.
	for k in 4:
		if rot(from_dir, k) == to_dir:
			return k
	return 0


static func yaw_of(d: Vector2i) -> float:
	## Godot Y rotation (radians) that makes a model's local -Z axis face tile direction d.
	return atan2(-float(d.x), -float(d.y))


static func to_vec3(d: Vector2i) -> Vector3:
	return Vector3(d.x, 0.0, d.y)


static func name_of(d: Vector2i) -> String:
	match d:
		N: return "N"
		E: return "E"
		S: return "S"
		W: return "W"
	return "?"
