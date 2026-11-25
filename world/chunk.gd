class_name Chunk
extends Node3D
## A live, placed room. Built by ChunkBuilder from a ChunkSpec + FloorTheme.
## Tile math lives here: local tile <-> world tile for a placement of (rot quarter turns clockwise,
## integer tile offset of the local origin). The Node3D transform realises the same mapping
## (rotation about the local origin, then translation), so geometry is authored in local space.

var spec: ChunkSpec = null
var theme: FloorTheme = null
var uid: int = 0
var rot: int = 0
var offset: Vector2i = Vector2i.ZERO
var beat_index: int = -1
var plan: Dictionary = {}                ## per-beat plan data (evidence assignments etc.)

var cells: Array[LightCell] = []
var world_open: Dictionary = {}          ## WORLD tile -> true
var slot_nodes: Dictionary = {}          ## StringName kind -> Array[Node3D]
var interactables: Array[Node] = []
var geometry: MeshInstance3D = null
var panels: MeshInstance3D = null
var body: StaticBody3D = null
var props_root: Node3D = null
var panels_dirty: bool = true
var decay: int = 0
var pinned: bool = false                 ## a planted camcorder keeps its chunk alive
var tile_cell: Dictionary = {}           ## WORLD tile -> LightCell (region ownership)
var door_nodes: Array[Node3D] = []       ## doors owned by this chunk (exit sockets)
var entry_world: Array[Dictionary] = []  ## [{tile, dir}] world tile/dir of entry sockets
var exit_world: Array[Dictionary] = []   ## [{tile, dir, index}] world tile/dir of exit sockets


func setup_transform() -> void:
	position = Vector3(offset.x * GameScale.TILE, 0.0, offset.y * GameScale.TILE)
	rotation = Vector3(0.0, -rot * PI * 0.5, 0.0)


func local_tile_to_world(p: Vector2i) -> Vector2i:
	var c := Vector2(p.x + 0.5, p.y + 0.5)
	for _i in rot:
		c = Vector2(-c.y, c.x)
	return Vector2i(floori(c.x) + offset.x, floori(c.y) + offset.y)


func world_tile_to_local(w: Vector2i) -> Vector2i:
	var c := Vector2(w.x - offset.x + 0.5, w.y - offset.y + 0.5)
	for _i in posmod(4 - rot, 4):
		c = Vector2(-c.y, c.x)
	return Vector2i(floori(c.x), floori(c.y))


func local_dir_to_world(d: Vector2i) -> Vector2i:
	return Dir.rot(d, rot)


func world_dir_to_local(d: Vector2i) -> Vector2i:
	return Dir.rot(d, posmod(4 - rot, 4))


func tile_center(world_tile: Vector2i, y: float = 0.0) -> Vector3:
	return GameScale.tile_to_world(world_tile, y)


func contains_world_tile(w: Vector2i) -> bool:
	return world_open.has(w)


func cell_at(world_tile: Vector2i) -> LightCell:
	return tile_cell.get(world_tile, null)


func slots_of(kind: StringName) -> Array:
	return slot_nodes.get(kind, [])


func mark_panels_dirty() -> void:
	panels_dirty = true


func _process(_delta: float) -> void:
	if panels_dirty:
		panels_dirty = false
		ChunkBuilder.rebuild_panels(self)


func bounds_world() -> Rect2i:
	var r := Rect2i()
	var first := true
	for t: Vector2i in world_open:
		var tr := Rect2i(t, Vector2i.ONE)
		if first:
			r = tr
			first = false
		else:
			r = r.merge(tr)
	return r


func center_world() -> Vector3:
	var b := bounds_world()
	return Vector3((b.position.x + b.size.x * 0.5) * GameScale.TILE, 0.0, (b.position.y + b.size.y * 0.5) * GameScale.TILE)


func dispose() -> void:
	for c in cells:
		c.neighbors.clear()
	cells.clear()
	tile_cell.clear()
	queue_free()
