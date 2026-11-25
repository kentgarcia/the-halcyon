class_name WorldGrid
extends RefCounted
## Tile-level walkability and pathing across the live chunks (SPEC 8.4: tile-grid A* instead of a baked
## navmesh). A step is legal when both tiles are open, no thin wall lies between them,
## and — when it crosses a chunk boundary — a door stands on that edge (and is not sealed).

var streamer: ChunkStreamer


func _init(p_streamer: ChunkStreamer = null) -> void:
	streamer = p_streamer


func chunk_at(t: Vector2i) -> Chunk:
	return streamer.chunk_at_tile(t) if streamer != null else null


func is_open(t: Vector2i) -> bool:
	return streamer != null and streamer.occupied.has(t)


func door_on_edge(a: Vector2i, b: Vector2i) -> Door:
	var conn: DoorConnection = streamer.connections.get(ChunkPlacer.edge_key(a, b), null)
	return conn.door if conn != null else null


func can_step(t: Vector2i, d: Vector2i, through_closed_doors: bool = true) -> bool:
	var c := chunk_at(t)
	if c == null:
		return false
	var n := t + d
	var cn := chunk_at(n)
	if cn == null:
		return false
	if c == cn:
		return c.spec.can_step(c.world_tile_to_local(t), c.world_dir_to_local(d))
	var door := door_on_edge(t, n)
	if door == null or door.sealed:
		return false
	return through_closed_doors or not door.is_closed()


func neighbors(t: Vector2i, through_closed_doors: bool = true) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in Dir.ALL:
		if can_step(t, d, through_closed_doors):
			out.append(t + d)
	return out


func path(from: Vector2i, to: Vector2i, opts: Dictionary = {}) -> Array[Vector2i]:
	## A* over tiles. opts: closed_doors (bool, default true), max_nodes (int), cost (Callable(tile)->float extra cost),
	## allow (Callable(tile)->bool: tiles the walker may enter; the goal itself is always allowed).
	## Returns [from, ..., to] or [] when unreachable.
	var out: Array[Vector2i] = []
	if not is_open(from) or not is_open(to):
		return out
	if from == to:
		out.append(from)
		return out
	var through_closed: bool = bool(opts.get("closed_doors", true))
	var max_nodes: int = int(opts.get("max_nodes", 1500))
	var cost_cb: Callable = opts.get("cost", Callable())
	var allow_cb: Callable = opts.get("allow", Callable())
	var open_heap: Array = []                 # [f, tile]
	var g: Dictionary = {from: 0.0}
	var came: Dictionary = {}
	var closed: Dictionary = {}
	_heap_push(open_heap, [_h(from, to), from])
	var expanded := 0
	while not open_heap.is_empty():
		var cur: Vector2i = _heap_pop(open_heap)[1]
		if closed.has(cur):
			continue
		if cur == to:
			var p: Array[Vector2i] = [cur]
			while came.has(p[0]):
				p.push_front(came[p[0]])
			return p
		closed[cur] = true
		expanded += 1
		if expanded > max_nodes:
			break
		for d in Dir.ALL:
			if not can_step(cur, d, through_closed):
				continue
			var n := cur + d
			if closed.has(n):
				continue
			if allow_cb.is_valid() and n != to and not bool(allow_cb.call(n)):
				continue
			var step := 1.0
			if cost_cb.is_valid():
				step += float(cost_cb.call(n))
			var ng: float = float(g[cur]) + step
			if not g.has(n) or ng < float(g[n]):
				g[n] = ng
				came[n] = cur
				_heap_push(open_heap, [ng + _h(n, to), n])
	return out


func distance_field(from: Vector2i, max_dist: int, through_closed_doors: bool = true) -> Dictionary:
	## BFS: tile -> steps (only tiles within max_dist).
	var dist: Dictionary = {from: 0}
	var q: Array[Vector2i] = [from]
	var qi := 0
	while qi < q.size():
		var cur: Vector2i = q[qi]
		qi += 1
		var dcur: int = dist[cur]
		if dcur >= max_dist:
			continue
		for d in Dir.ALL:
			if can_step(cur, d, through_closed_doors):
				var n := cur + d
				if not dist.has(n):
					dist[n] = dcur + 1
					q.append(n)
	return dist


func line_of_sight(a: Vector3, b: Vector3, space: PhysicsDirectSpaceState3D, exclude: Array[RID] = []) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, GameScale.LAYER_WORLD | GameScale.LAYER_DOORS)
	q.exclude = exclude
	return space.intersect_ray(q).is_empty()


func random_open_tile_near(center: Vector2i, min_r: int, max_r: int, rng: RandomNumberGenerator) -> Vector2i:
	var field := distance_field(center, max_r)
	var cands: Array[Vector2i] = []
	for t: Vector2i in field:
		if int(field[t]) >= min_r:
			cands.append(t)
	if cands.is_empty():
		return center
	return cands[rng.randi() % cands.size()]


static func _h(a: Vector2i, b: Vector2i) -> float:
	return float(absi(a.x - b.x) + absi(a.y - b.y))


static func _heap_push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if float(h[p][0]) <= float(h[i][0]):
			break
		var tmp = h[p]
		h[p] = h[i]
		h[i] = tmp
		i = p


static func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		var n := h.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var s := i
			if l < n and float(h[l][0]) < float(h[s][0]):
				s = l
			if r < n and float(h[r][0]) < float(h[s][0]):
				s = r
			if s == i:
				break
			var tmp = h[s]
			h[s] = h[i]
			h[i] = tmp
			i = s
	return top
