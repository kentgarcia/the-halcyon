class_name GameScale
extends RefCounted
## Single source of truth for world dimensions. Everything is derived from TILE (one 64-px texture
## width). If TILE changes, the whole building rescales.

const TILE := 1.25               ## metres per tile; one Kenney texture width
const WALL_H := 2.5              ## everything is this tall: the house is low
const DOOR_W := 1.25
const DOOR_H := 2.5
const DOOR_LEAF_T := 0.06
const PLAYER_RADIUS := 0.4
const PLAYER_HEIGHT := 1.7
const PLAYER_CROUCH_HEIGHT := 1.1
const EYE_HEIGHT := 1.55
const EYE_CROUCH := 1.0
const WALK_SPEED := 2.2
const SPRINT_SPEED := 4.0
const CROUCH_SPEED := 1.2
const INTERACT_RANGE := 2.0
const INTERACT_CONE_DEG := 28.0
const FOV_DEFAULT := 75.0
const FOV_CAMCORDER := 55.0

## Physics layers (names also set in project.godot [layer_names]).
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_PROPS := 4
const LAYER_DOORS := 8
const LAYER_ENTITIES := 16
const LAYER_TRIGGERS := 32


static func tile_to_world(t: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3((t.x + 0.5) * TILE, y, (t.y + 0.5) * TILE)


static func world_to_tile(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.z / TILE))


static func tile_origin(t: Vector2i) -> Vector3:
	## North-west (min x, min z) corner of a tile at floor level.
	return Vector3(t.x * TILE, 0.0, t.y * TILE)
