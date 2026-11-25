class_name ChunkStreamer
extends Node
## Instantiates rooms lazily as doors open and unloads them behind the guest (SPEC 8.4).
## Doors belong to DoorConnections; a chunk is built when a door starts to open (the swing hides the
## seam), aligned socket-to-door by ChunkPlacer, and evicted when more than `max_live` are alive.
##
## A `provider` supplies content (the floor plan): see FloorPlan. Interface:
##   resolve(conn: DoorConnection, from_side: Dictionary) -> Dictionary
##       {spec: ChunkSpec, beat: int, socket: int, plan: Dictionary}   or {} when nothing can be built
##   door_type_for(chunk: Chunk, socket: ChunkSpec.SocketDef) -> Dictionary  {type, tells, ...}
##   theme_for(beat: int) -> FloorTheme

signal chunk_loaded(chunk: Chunk)
signal chunk_unloaded(uid: int)
signal current_chunk_changed(chunk: Chunk)
signal connection_created(conn: DoorConnection)

var stage: Stage = null
var provider: Object = null
var max_live := 4
var chunks: Dictionary = {}          ## uid -> Chunk
var connections: Dictionary = {}     ## edge key -> DoorConnection
var occupied: Dictionary = {}        ## world tile -> uid
var current: Chunk = null
var player: Node3D = null
var build_ms_last := 0.0
var build_ms_max := 0.0
var build_split := ""             ## where the slowest build spent its time (dev/perf)
var _next_uid := 1
var _prune_timer := 0.0
var _doors_root: Node3D = null


func setup(p_stage: Stage, p_provider: Object) -> void:
	stage = p_stage
	provider = p_provider
	_doors_root = Node3D.new()
	_doors_root.name = "Doors"
	stage.add_child(_doors_root)


func clear() -> void:
	for uid in chunks.keys():
		_unload(chunks[uid])
	for k in connections.keys():
		_drop_connection(connections[k])
	connections.clear()
	occupied.clear()
	current = null


func _process(delta: float) -> void:
	if player == null or stage == null:
		return
	var t := GameScale.world_to_tile(player.global_position)
	var uid: int = occupied.get(t, -1)
	var c: Chunk = chunks.get(uid, null)
	if c != null and c != current:
		current = c
		current_chunk_changed.emit(c)
		EventBus.chunk_entered.emit(c)
		stage.light_field.set_focus(t)
		_prune()
	elif c != null:
		stage.light_field.set_focus(t)
	_prune_timer += delta
	if _prune_timer > 0.5:
		_prune_timer = 0.0
		_prune()


# --- building -------------------------------------------------------------------------------

func spawn_initial(spec: ChunkSpec, beat: int, rot: int, offset: Vector2i, plan: Dictionary = {}) -> Chunk:
	var theme: FloorTheme = provider.theme_for(beat) if provider != null and provider.has_method("theme_for") else stage.theme
	return _build_and_register(spec, theme, rot, offset, beat, plan)


func _build_and_register(spec: ChunkSpec, theme: FloorTheme, rot: int, offset: Vector2i, beat: int, plan: Dictionary) -> Chunk:
	var t0 := Time.get_ticks_usec()
	var uid := _next_uid
	_next_uid += 1
	var chunk := ChunkBuilder.build(spec, theme, rot, offset, uid, beat, plan)
	var t1 := Time.get_ticks_usec()
	stage.add_chunk(chunk)
	chunks[uid] = chunk
	for t in chunk.world_open:
		occupied[t] = uid
	_register_sockets(chunk)
	var t2 := Time.get_ticks_usec()
	if provider != null and provider.has_method("populate"):
		provider.populate(chunk, self)
	var t3 := Time.get_ticks_usec()
	build_ms_last = (t3 - t0) / 1000.0
	if build_ms_last >= build_ms_max:
		build_split = "builder %.1f (%s)  register %.1f  populate %.1f ms (%s)" % [(t1 - t0) / 1000.0, ChunkBuilder.last_split, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, spec.id]
	build_ms_max = maxf(build_ms_max, build_ms_last)
	chunk_loaded.emit(chunk)
	return chunk


func _register_sockets(chunk: Chunk) -> void:
	var all_sockets: Array[ChunkSpec.SocketDef] = []
	all_sockets.append_array(chunk.spec.exits)
	all_sockets.append_array(chunk.spec.entries)
	for s in all_sockets:
		var wt := chunk.local_tile_to_world(s.tile)
		var wd := chunk.local_dir_to_world(s.dir)
		var other := wt + wd
		var key := ChunkPlacer.edge_key(wt, other)
		var side := {"uid": chunk.uid, "beat": chunk.beat_index, "spec": chunk.spec.id, "socket": _socket_id(s)}
		if connections.has(key):
			var conn: DoorConnection = connections[key]
			if conn.tile_a == wt:
				conn.side_a = side
			else:
				conn.side_b = side
			continue
		var info := {"type": &"stuck" if s.kind == &"entry" else &"unit"}
		if provider != null and provider.has_method("door_type_for"):
			info = provider.door_type_for(chunk, s)
		var door := Door.create(StringName(info.get("type", &"unit")), wt, wd)
		for tell in info.get("tells", []):
			door.tells.append(tell)
		var conn2 := DoorConnection.new()
		conn2.key = key
		conn2.door = door
		conn2.tile_a = wt
		conn2.tile_b = other
		conn2.dir_ab = wd
		conn2.side_a = side
		conn2.plan = info
		door.connection = conn2
		door.opening.connect(_on_door_opening)
		connections[key] = conn2
		_doors_root.add_child(door)
		if not door.tells.is_empty():
			door.build_tells()         # after add_child: tells include looped positional audio
		connection_created.emit(conn2)


static func _socket_id(s: ChunkSpec.SocketDef) -> int:
	## entries are encoded as 100 + index so exits and entries share one id space
	return s.index if s.kind == &"exit" else 100 + s.index


static func socket_from_id(spec: ChunkSpec, id: int) -> ChunkSpec.SocketDef:
	if id >= 100:
		return spec.entries[id - 100] if id - 100 < spec.entries.size() else null
	return spec.exits[id] if id < spec.exits.size() else null


func _on_door_opening(door: Door) -> void:
	var conn := door.connection as DoorConnection
	if conn == null:
		return
	var player_side := door.side_of(player.global_position) if player != null else 1
	# the far side is the one the player is NOT on
	var far_is_b := player_side > 0
	var far_side: Dictionary = conn.side_b if far_is_b else conn.side_a
	if conn.is_live(far_side):
		return
	var near_side: Dictionary = conn.side_a if far_is_b else conn.side_b
	_build_far_side(conn, far_is_b, near_side)


func _build_far_side(conn: DoorConnection, far_is_b: bool, near_side: Dictionary) -> void:
	if provider == null:
		return
	var far_info: Dictionary = conn.side_b if far_is_b else conn.side_a
	var res: Dictionary = provider.resolve(conn, near_side, far_info)
	if res.is_empty():
		return
	var spec: ChunkSpec = res["spec"]
	var sock := socket_from_id(spec, int(res["socket"]))
	if sock == null:
		push_warning("ChunkStreamer: spec %s has no socket %s" % [spec.id, res["socket"]])
		return
	var far_tile := conn.tile_b if far_is_b else conn.tile_a
	var door_dir := conn.dir_ab if far_is_b else -conn.dir_ab        # direction from near side to far side
	var pl := ChunkPlacer.placement_for_socket(sock, far_tile, -door_dir)
	var rot: int = pl["rot"]
	var offset: Vector2i = pl["offset"]
	if not ChunkPlacer.fits(spec, rot, offset, occupied):
		var tried := {spec.id: [int(res["socket"])]}
		var found := false
		if provider.has_method("fallback_candidates"):
			for alt: Dictionary in provider.fallback_candidates(conn, near_side, far_info, tried):
				var alt_spec: ChunkSpec = alt["spec"]
				var alt_sock := socket_from_id(alt_spec, int(alt["socket"]))
				if alt_sock == null:
					continue
				var alt_pl := ChunkPlacer.placement_for_socket(alt_sock, far_tile, -door_dir)
				if ChunkPlacer.fits(alt_spec, alt_pl["rot"], alt_pl["offset"], occupied):
					spec = alt_spec
					rot = alt_pl["rot"]
					offset = alt_pl["offset"]
					res = alt
					found = true
					if provider.has_method("on_fallback_used"):
						provider.on_fallback_used(alt)
					break
		if not found:
			var hit := {}
			for t: Vector2i in ChunkPlacer.world_tiles(spec, rot, offset):
				if occupied.has(t):
					var oc: Chunk = chunks.get(int(occupied[t]))
					hit[oc.spec.id if oc != null else "?"] = true
			push_warning("ChunkStreamer: %s does not fit at the door and no alternative does (overlaps %s)" % [spec.id, hit.keys()])
			return
	var theme: FloorTheme = provider.theme_for(int(res["beat"]))
	_build_and_register(spec, theme, rot, offset, int(res["beat"]), res.get("plan", {}))
	_prune()


# --- unloading ------------------------------------------------------------------------------

func neighbors_of(chunk: Chunk) -> Array[Chunk]:
	var out: Array[Chunk] = []
	for k in connections:
		var conn: DoorConnection = connections[k]
		var ua := int(conn.side_a["uid"])
		var ub := int(conn.side_b["uid"])
		if ua == chunk.uid and ub >= 0 and chunks.has(ub):
			out.append(chunks[ub])
		elif ub == chunk.uid and ua >= 0 and chunks.has(ua):
			out.append(chunks[ua])
	return out


func _prune() -> void:
	if current == null or player == null:
		return
	var keep := {current.uid: true}
	for n in neighbors_of(current):
		keep[n.uid] = true
	for uid in chunks:
		if (chunks[uid] as Chunk).pinned:
			keep[uid] = true
	# 1) anything outside the keep set whose doors are closed and which is out of earshot goes
	for uid in chunks.keys():
		if keep.has(uid):
			continue
		var c: Chunk = chunks[uid]
		if _any_door_open(c):
			continue
		if _distance_to_chunk(c) < 8.0:
			continue
		_unload(c)
	# 2) over budget: evict the farthest kept neighbour whose doors are closed (never current/pinned)
	while chunks.size() > max_live:
		var victim: Chunk = null
		var far := -1.0
		for uid in chunks:
			var c2: Chunk = chunks[uid]
			if c2 == current or c2.pinned or _any_door_open(c2):
				continue
			var d := _distance_to_chunk(c2)
			if d > far:
				far = d
				victim = c2
		if victim == null:
			break
		_unload(victim)


func _any_door_open(c: Chunk) -> bool:
	for k in connections:
		var conn: DoorConnection = connections[k]
		if int(conn.side_a["uid"]) == c.uid or int(conn.side_b["uid"]) == c.uid:
			if conn.door != null and not conn.door.is_closed():
				return true
	return false


func _distance_to_chunk(c: Chunk) -> float:
	if player == null:
		return 0.0
	var best := INF
	var pp := player.global_position
	for t: Vector2i in c.world_open:
		var d := pp.distance_to(GameScale.tile_to_world(t))
		if d < best:
			best = d
	return best


func _unload(c: Chunk) -> void:
	var uid := c.uid
	for t: Vector2i in c.world_open:
		if occupied.get(t, -1) == uid:
			occupied.erase(t)
	for k in connections.keys():
		var conn: DoorConnection = connections[k]
		if int(conn.side_a["uid"]) == uid:
			conn.side_a["uid"] = -1
		if int(conn.side_b["uid"]) == uid:
			conn.side_b["uid"] = -1
		if conn.both_dead():
			_drop_connection(conn)
			connections.erase(k)
	chunks.erase(uid)
	stage.remove_chunk(c)
	chunk_unloaded.emit(uid)
	EventBus.chunk_unloaded.emit(uid)


func _drop_connection(conn: DoorConnection) -> void:
	if conn.door != null and is_instance_valid(conn.door):
		conn.door.queue_free()


func chunk_at_tile(t: Vector2i) -> Chunk:
	return chunks.get(occupied.get(t, -1), null)


func live_count() -> int:
	return chunks.size()
