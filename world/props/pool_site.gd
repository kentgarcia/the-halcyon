class_name PoolSite
extends RefCounted
## B2 Natatorium dressing shared by the Lifeguard and his P2 evidence recipes: the standing-water sheet of a room
## (ankle deep, with a dry deck along the walls) and its drain grates. Deterministic from the chunk, so the recipe
## (populate time) and the entity (tell time) agree. The water shader is where the Lifeguard's tell is SHOWN
## (calm vs rings travelling toward the guest, SPEC 6.3); the grates are the vents that pull a guest who moves
## during the freeze (HOLDS).

const WATER_Y := 0.04
const MIN_WATER := 12                    ## tiles: a smaller puddle is not a pool (the room stays dry)
const MAX_GRATES := 4
const GRATE_GAP := 5                     ## tiles between drain grates
const DRY_TAGS: Array[StringName] = [&"basin", &"gallery", &"bleachers", &"corridor", &"drain"]
const WET_BEATS: Array[StringName] = [&"choice", &"long", &"exam"]
const SHADER: Shader = preload("res://shaders/pool_water.gdshader")


static func water_tiles(spec: ChunkSpec) -> Array[Vector2i]:
	## Chunk-local tiles under water: open tiles with no slot, no thin wall and no wall within one tile (so a
	## one-tile dry deck rings the room and pillars stand IN the water). Rooms tagged dry (the drained basin,
	## corridors) and rooms that would only hold a puddle return [].
	var out: Array[Vector2i] = []
	if not WET_BEATS.has(spec.beat):
		return out
	for tag in DRY_TAGS:
		if spec.tags.has(tag):
			return out
	var slot_tiles := {}
	for sl: ChunkSpec.SlotDef in spec.slots:
		slot_tiles[sl.tile] = true
	for t: Vector2i in spec.open:
		if slot_tiles.has(t) or _has_thin(spec, t):
			continue
		var ok := true
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var n := t + Vector2i(dx, dy)
				if not spec.open.has(n) and not spec.pillars.has(n):
					ok = false
		if ok:
			out.append(t)
	if out.size() < MIN_WATER:
		out.clear()
	return out


static func has_pool(spec: ChunkSpec) -> bool:
	return not water_tiles(spec).is_empty()


static func _has_thin(spec: ChunkSpec, t: Vector2i) -> bool:
	for d in Dir.ALL:
		if spec.has_thin_wall(t, d):
			return true
	return false


static func material() -> ShaderMaterial:
	return MaterialLibrary.custom(&"pool_water_fx", SHADER, &"pool_water")


static func set_ripple(amp: float, calm: float, center: Vector3) -> void:
	var m := material()
	m.set_shader_parameter("ripple_amp", clampf(amp, 0.0, 1.0))
	m.set_shader_parameter("calm", clampf(calm, 0.0, 1.0))
	m.set_shader_parameter("ripple_center", center)


static func pool_of(chunk: Chunk) -> Dictionary:
	## Read-only: what ensure() built ({} when the room is dry or not yet built).
	if chunk != null and chunk.has_meta(&"pool"):
		return chunk.get_meta(&"pool")
	return {}


static func ensure(chunk: Chunk, session: Node = null) -> Dictionary:
	## Builds the room's water sheet and drain grates once.
	## Returns {water: {world tile: true}, grates: [Vector3 world], grate_nodes: [Node3D], tiles: [local]}.
	if chunk.has_meta(&"pool"):
		return chunk.get_meta(&"pool")
	var tiles := water_tiles(chunk.spec)
	if tiles.is_empty() or chunk.props_root == null:
		chunk.set_meta(&"pool", {})
		return {}
	var rng := _rng_for(chunk, session)
	var grate_tiles := pick_grates(tiles, rng)
	var grate_set := {}
	for g in grate_tiles:
		grate_set[g] = true
	var wmb := MeshBuilder.new()
	var water_world := {}
	for t in tiles:
		water_world[chunk.local_tile_to_world(t)] = true
		if grate_set.has(t):
			continue
		var c := ChunkBuilder.local_center(t)
		var h := GameScale.TILE * 0.5
		wmb.floor_quad(&"pool_water_fx", c.x - h, c.z - h, c.x + h, c.z + h, WATER_Y)
	var mat := material()
	var water := MeshInstance3D.new()
	water.name = "PoolWater"
	water.mesh = wmb.build(func(_k): return mat)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.props_root.add_child(water)
	var grate_world: Array[Vector3] = []
	var grate_nodes: Array[Node3D] = []
	for g in grate_tiles:
		var gn := _grate_node()
		chunk.props_root.add_child(gn)
		gn.position = ChunkBuilder.local_center(g)
		grate_nodes.append(gn)
		grate_world.append(GameScale.tile_to_world(chunk.local_tile_to_world(g)))
	var info := {"water": water_world, "grates": grate_world, "grate_nodes": grate_nodes, "tiles": tiles, "node": water}
	chunk.set_meta(&"pool", info)
	return info


static func pick_grates(tiles: Array[Vector2i], rng: RandomNumberGenerator) -> Array[Vector2i]:
	## Up to MAX_GRATES water tiles, spread out (relaxed when the pool is small), always at least one.
	var out: Array[Vector2i] = []
	if tiles.is_empty():
		return out
	var order := RngStreams.shuffled(rng, tiles)
	for gap in [GRATE_GAP, 3, 1]:
		for t: Vector2i in order:
			if out.size() >= MAX_GRATES:
				break
			var far := true
			for o in out:
				if absi(o.x - t.x) + absi(o.y - t.y) < gap:
					far = false
			if far:
				out.append(t)
		if out.size() >= 2:
			break
	return out


static func _rng_for(chunk: Chunk, session: Node) -> RandomNumberGenerator:
	if session != null and "plan" in session and session.plan != null:
		return session.plan.rng_for("pool:%s:%d" % [chunk.spec.id, chunk.uid])
	var r := RandomNumberGenerator.new()
	r.seed = RngStreams.mix(chunk.spec.id.hash(), chunk.uid ^ 0x70017)
	return r


static func _grate_node() -> Node3D:
	## A square drain grate set into the pool floor (1 m): rim, dark well, bars.
	var mb := MeshBuilder.new()
	mb.box(&"#59666b", Vector3(0, 0.012, 0), Vector3(1.04, 0.024, 1.04))
	mb.box(&"#0b0f10", Vector3(0, 0.016, 0), Vector3(0.92, 0.024, 0.92))
	for i in 7:
		var x := (float(i) - 3.0) * 0.13
		mb.box(&"#3b484c", Vector3(x, 0.03, 0), Vector3(0.05, 0.014, 0.92))
	var n := Node3D.new()
	n.name = "DrainGrate"
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	return n


static func nearest_grate(chunk: Chunk, from: Vector3) -> Vector3:
	## World position of the closest drain grate, or INF when the room has none.
	var info := pool_of(chunk)
	var best := Vector3.INF
	var bd := INF
	for g: Vector3 in info.get("grates", []):
		var d := Vector2(g.x - from.x, g.z - from.z).length()
		if d < bd:
			bd = d
			best = g
	return best
