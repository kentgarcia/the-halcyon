class_name AlarmSite
extends RefCounted
## B3 Boiler dressing shared by the Foreman and his P2 evidence recipes: one alarm bell per working room, an
## EXIT sign on every usable exit door, and a few room-geometry helpers (BFS route, door lookups). Everything is
## a deterministic function of the chunk, so the evidence recipe (run at populate time) and the entity (run at
## tell time) always agree on where the bell is.

const BELL_Y := 1.95
const MIN_DOOR_GAP := 3                  ## tiles: a bell is never this close to a socket
const WORKING_BEATS: Array[StringName] = [&"choice", &"long", &"exam"]


static func is_working_room(spec: ChunkSpec) -> bool:
	return WORKING_BEATS.has(spec.beat)


# --- bell -----------------------------------------------------------------------------------

static func bell_site(spec: ChunkSpec, rng: RandomNumberGenerator) -> Dictionary:
	## {tile, dir} (chunk-local): an open tile with a free wall face, as far from every socket as possible.
	var slot_tiles := {}
	for sl: ChunkSpec.SlotDef in spec.slots:
		slot_tiles[sl.tile] = true
	var sockets: Array[Vector2i] = []
	for s: ChunkSpec.SocketDef in spec.exits:
		sockets.append(s.tile)
	for s: ChunkSpec.SocketDef in spec.entries:
		sockets.append(s.tile)
	var socket_edges := spec.socket_edges()
	var cands: Array = []
	for t: Vector2i in spec.open:
		if slot_tiles.has(t):
			continue
		var gap := 999
		for st in sockets:
			gap = mini(gap, absi(st.x - t.x) + absi(st.y - t.y))
		if gap < MIN_DOOR_GAP:
			continue
		for d in Dir.ALL:
			var n: Vector2i = t + d
			if spec.open.has(n) or spec.pillars.has(n) or socket_edges.has(ChunkSpec.edge_key(t, d)):
				continue
			cands.append({"tile": t, "dir": d, "score": gap})
	if cands.is_empty():
		return {}
	cands.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]) or (int(a["score"]) == int(b["score"]) and _tile_less(a["tile"], b["tile"])))
	var top := mini(cands.size(), 4)
	return cands[rng.randi() % top]


static func _tile_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


static func _rng_for(chunk: Chunk, session: Node, key: String) -> RandomNumberGenerator:
	if session != null and "plan" in session and session.plan != null:
		return session.plan.rng_for("%s:%s:%d" % [key, chunk.spec.id, chunk.uid])
	var r := RandomNumberGenerator.new()
	r.seed = RngStreams.mix(RngStreams.mix(chunk.spec.id.hash(), chunk.uid), key.hash())
	return r


static func ensure_bell(chunk: Chunk, session: Node = null) -> AlarmBell:
	## The room's alarm bell (idempotent). Null when the room has no free wall.
	if chunk.has_meta(&"alarm_bell"):
		var old: Variant = chunk.get_meta(&"alarm_bell")
		if is_instance_valid(old):
			return old as AlarmBell
	if chunk.props_root == null:
		return null
	var site := bell_site(chunk.spec, _rng_for(chunk, session, "bell"))
	if site.is_empty():
		return null
	var t: Vector2i = site["tile"]
	var d: Vector2i = site["dir"]
	var bell := AlarmBell.create()
	chunk.props_root.add_child(bell)
	bell.position = ChunkBuilder.local_center(t, BELL_Y) + Dir.to_vec3(d) * (GameScale.TILE * 0.5)
	bell.rotation.y = Dir.yaw_of(-d)
	bell.local_tile = t
	bell.world_tile = chunk.local_tile_to_world(t)
	chunk.set_meta(&"alarm_bell", bell)
	return bell


# --- doors / exits --------------------------------------------------------------------------

static func exit_door(session: Node, ex: Dictionary) -> Door:
	## The Door on an exit entry of Chunk.exit_world ({tile, dir, index}); null without a streamer.
	if session == null or not "streamer" in session or session.streamer == null:
		return null
	var key := ChunkPlacer.edge_key(ex["tile"], ex["tile"] + ex["dir"])
	var conn: DoorConnection = session.streamer.connections.get(key, null)
	return conn.door if conn != null else null


static func usable(door: Door) -> bool:
	## A door the guest could simply walk through (not painted shut, boarded, taped or an elevator).
	return door != null and not door.sealed and door.locked_by == &"" and door.door_type != &"elevator" \
		and String(door.def.get("mode", "live")) == "live"


static func room_on_side_a(door: Door, ex: Dictionary) -> bool:
	return door.tile_a == ex["tile"]


static func exit_center(ex: Dictionary, y: float = 0.0) -> Vector3:
	return GameScale.tile_to_world(ex["tile"], y) + Dir.to_vec3(ex["dir"]) * (GameScale.TILE * 0.5)


static func beyond_tile(ex: Dictionary) -> Vector2i:
	## World tile just outside the exit door: where something "behind the exit" stands.
	return ex["tile"] + ex["dir"]


static func ensure_signs(chunk: Chunk, session: Node) -> Dictionary:
	## An EXIT sign on every usable exit door of a working room. Returns exit index -> ExitSign.
	var out := {}
	if not is_working_room(chunk.spec):
		return out
	for ex: Dictionary in chunk.exit_world:
		var door := exit_door(session, ex)
		if not usable(door):
			continue
		var s := ExitSign.attach(door, room_on_side_a(door, ex))
		if s != null:
			out[int(ex["index"])] = s
	return out


# --- room routes ----------------------------------------------------------------------------

static func local_path(spec: ChunkSpec, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	## BFS over the room's own tiles (thin walls respected). [from, ..., to] or [] when unreachable.
	var out: Array[Vector2i] = []
	if not spec.open.has(from) or not spec.open.has(to):
		return out
	var came := {from: from}
	var q: Array[Vector2i] = [from]
	var qi := 0
	while qi < q.size():
		var cur := q[qi]
		qi += 1
		if cur == to:
			break
		for d in Dir.ALL:
			if spec.can_step(cur, d):
				var n := cur + d
				if not came.has(n):
					came[n] = cur
					q.append(n)
	if not came.has(to):
		return out
	var p := to
	out.push_front(p)
	while p != from:
		p = came[p]
		out.push_front(p)
	return out
