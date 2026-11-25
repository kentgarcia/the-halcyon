class_name ChunkPlacer
extends RefCounted
## Chunk placement math (SPEC 8.3). A placement is (rot quarter turns clockwise, integer tile offset of
## the chunk's local origin). To connect a chunk through one of its sockets to a door edge, the socket's
## tile must land on the tile just beyond the door and its outward direction must point back at the door.


static func rot_center(local_tile: Vector2i, k: int) -> Vector2:
	var c := Vector2(local_tile.x + 0.5, local_tile.y + 0.5)
	for _i in posmod(k, 4):
		c = Vector2(-c.y, c.x)
	return c


static func tile_to_world(local_tile: Vector2i, rot: int, offset: Vector2i) -> Vector2i:
	var c := rot_center(local_tile, rot)
	return Vector2i(floori(c.x) + offset.x, floori(c.y) + offset.y)


static func placement_for_socket(socket: ChunkSpec.SocketDef, target_tile: Vector2i, target_outward: Vector2i) -> Dictionary:
	## target_tile: the world tile the socket's tile must occupy (the tile beyond the door).
	## target_outward: the world direction the socket must face (back toward the door).
	var k := Dir.turns_between(socket.dir, target_outward)
	var c := rot_center(socket.tile, k)
	var offset := target_tile - Vector2i(floori(c.x), floori(c.y))
	return {"rot": k, "offset": offset}


static func world_tiles(spec: ChunkSpec, rot: int, offset: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t: Vector2i in spec.open:
		out.append(tile_to_world(t, rot, offset))
	return out


static func fits(spec: ChunkSpec, rot: int, offset: Vector2i, occupied: Dictionary) -> bool:
	for t: Vector2i in spec.open:
		if occupied.has(tile_to_world(t, rot, offset)):
			return false
	return true


static func edge_key(a: Vector2i, b: Vector2i) -> String:
	## Canonical key of the edge between two adjacent tiles, independent of which side asks.
	var lo := a
	var hi := b
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		lo = b
		hi = a
	return "%d,%d|%d,%d" % [lo.x, lo.y, hi.x, hi.y]
