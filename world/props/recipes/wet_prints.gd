extends RefCounted
## P2 recipe `wet_prints` (B2 Natatorium, INVERTED): wet footprints come out of the water and lead to the places
## where Guests stood still. True evidence: the INVERTED Lifeguard walks the pool edge toward a guest who stands
## still (SPEC 6.3). Trails run over the dry deck and end in a stationary pair and a drip, so the direction of
## travel (toward the still spot) reads off the prints.

const WET := &"#16272d"
const DRIP := &"#122127"
const MAX_SPOTS := 3
const SPOT_GAP := 6
const PRINTS_PER_MARK := 4
const STRIDE := 0.5


static func can_host(spec: ChunkSpec, _e: EvidenceDef) -> bool:
	return PoolSite.has_pool(spec)


static func place(chunk: Chunk, e: EvidenceDef, rng: RandomNumberGenerator, session: Node) -> void:
	var info := PoolSite.ensure(chunk, session)
	if info.is_empty():
		return
	var water := {}
	for t: Vector2i in info["tiles"]:
		water[t] = true
	for spot in spots(chunk.spec, water, rng):
		_trail(chunk, e, chunk.spec, spot, water, rng)


static func spots(spec: ChunkSpec, water: Dictionary, rng: RandomNumberGenerator) -> Array[Vector2i]:
	## Deck tiles beside the water where a guest would plausibly freeze, nearest the doors first.
	var slot_tiles := {}
	for sl: ChunkSpec.SlotDef in spec.slots:
		slot_tiles[sl.tile] = true
	var sockets: Array[Vector2i] = []
	for s: ChunkSpec.SocketDef in spec.exits:
		sockets.append(s.tile)
	for s: ChunkSpec.SocketDef in spec.entries:
		sockets.append(s.tile)
	var cands: Array = []
	for t: Vector2i in spec.open:
		if water.has(t) or slot_tiles.has(t):
			continue
		var wet_next := false
		for d in Dir.ALL:
			if water.has(t + d):
				wet_next = true
		if not wet_next:
			continue
		var gap := 999
		for st in sockets:
			gap = mini(gap, absi(st.x - t.x) + absi(st.y - t.y))
		if gap < 2:
			continue
		cands.append({"tile": t, "score": float(gap) + rng.randf() * 4.0})
	cands.sort_custom(func(a, b): return float(a["score"]) < float(b["score"]))
	var out: Array[Vector2i] = []
	for c in cands:
		var t: Vector2i = c["tile"]
		var far := true
		for o in out:
			if absi(o.x - t.x) + absi(o.y - t.y) < SPOT_GAP:
				far = false
		if far:
			out.append(t)
		if out.size() >= MAX_SPOTS:
			break
	return out


static func _deck_route(spec: ChunkSpec, spot: Vector2i, water: Dictionary) -> Array[Vector2i]:
	## [water-edge deck tile, ..., spot]: the longest dry walk (<= 7 steps) from the water to the spot.
	var came := {spot: spot}
	var depth := {spot: 0}
	var q: Array[Vector2i] = [spot]
	var qi := 0
	var best := spot
	while qi < q.size():
		var cur := q[qi]
		qi += 1
		if int(depth[cur]) >= 7:
			continue
		for d in Dir.ALL:
			var n := cur + d
			if not spec.can_step(cur, d) or water.has(n) or came.has(n):
				continue
			came[n] = cur
			depth[n] = int(depth[cur]) + 1
			q.append(n)
			var touches := false
			for d2 in Dir.ALL:
				if water.has(n + d2):
					touches = true
			if touches and int(depth[n]) > int(depth[best]):
				best = n
	var route: Array[Vector2i] = [best]
	var p := best
	while p != spot:
		# walk from the start back toward the spot: follow `came` (which points toward the spot)
		p = came[p]
		route.append(p)
	return route


static func _trail(chunk: Chunk, e: EvidenceDef, spec: ChunkSpec, spot: Vector2i, water: Dictionary, rng: RandomNumberGenerator) -> void:
	var route := _deck_route(spec, spot, water)
	var pts: Array[Vector3] = []
	# start at the water's edge: half a tile out of the first deck tile toward the water
	var first := route[0]
	var wet_dir := Vector2i.ZERO
	for d in Dir.ALL:
		if water.has(first + d):
			wet_dir = d
	pts.append(ChunkBuilder.local_center(first) + Dir.to_vec3(wet_dir) * (GameScale.TILE * 0.5))
	for t in route:
		pts.append(ChunkBuilder.local_center(t))
	# prints along the polyline, alternating feet, grouped into a few findable marks
	var prints: Array[Dictionary] = []
	var left := true
	var carry := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		if seg < 0.01:
			continue
		var dir := (b - a) / seg
		var side := Vector3(-dir.z, 0.0, dir.x)
		var s := STRIDE - carry
		while s <= seg:
			var jitter := rng.randf_range(-0.02, 0.02)
			prints.append({"pos": a + dir * s + side * ((0.085 if left else -0.085) + jitter), "dir": dir})
			left = not left
			s += STRIDE
		carry = seg - (s - STRIDE)
	var i0 := 0
	while i0 < prints.size():
		var group := prints.slice(i0, mini(i0 + PRINTS_PER_MARK, prints.size()))
		i0 += PRINTS_PER_MARK
		var centre := Vector3.ZERO
		for p in group:
			centre += (p["pos"] as Vector3)
		centre /= float(group.size())
		var mb := MeshBuilder.new()
		for p in group:
			_foot(mb, (p["pos"] as Vector3) - centre, p["dir"])
		var mark := MarkShapes.mark_node(e, mb)
		chunk.props_root.add_child(mark)
		mark.position = Vector3(centre.x, 0.0, centre.z)
		mark.read_radius = 7.5
	# the still spot: a stationary pair side by side and a drip
	var end: Vector3 = pts[pts.size() - 1]
	var last_dir := (pts[pts.size() - 1] - pts[maxi(0, pts.size() - 2)])
	last_dir.y = 0.0
	last_dir = last_dir.normalized() if last_dir.length() > 0.01 else Vector3(1, 0, 0)
	var smb := MeshBuilder.new()
	var side2 := Vector3(-last_dir.z, 0.0, last_dir.x)
	MarkShapes.floor_rect(smb, DRIP, Vector3.ZERO, Vector2(last_dir.x, last_dir.z), 0.62, 0.5, 0.010)
	_foot(smb, side2 * 0.11, last_dir)
	_foot(smb, -side2 * 0.11, last_dir)
	var smark := MarkShapes.mark_node(e, smb)
	chunk.props_root.add_child(smark)
	smark.position = Vector3(end.x, 0.0, end.z)
	smark.read_radius = 7.5


static func _foot(mb: MeshBuilder, at: Vector3, dir: Vector3) -> void:
	## One wet footprint (heel + ball) pointing along `dir`.
	var d2 := Vector2(dir.x, dir.z)
	var heel := at - dir * 0.11
	var ball := at + dir * 0.075
	MarkShapes.floor_rect(mb, WET, Vector3(heel.x, 0.0, heel.z), d2, 0.14, 0.11, 0.011)
	MarkShapes.floor_rect(mb, WET, Vector3(ball.x, 0.0, ball.z), d2, 0.19, 0.15, 0.011)
