class_name TrayRecipe
extends RefCounted
## P2 evidence of the Greeter (SPEC 6.6): an untouched room-service tray beside a residential door. HOLDS: the doors
## beside the trays STAND OPEN (he opened them for the guests who answered). INVERTED: they are SHUT (he walked the
## guests in and closed them). EvidenceDef.params {doors: "open" | "shut"} says which, and the variant it supports is
## the only one ever placed (Fairness Doctrine 1).
##   static can_host(spec, e) / place(chunk, e, rng, session)   (see world/props/evidence_recipes.gd)
## SlotPopulator also routes every `T` slot of the Units floor through place_slot(), so the decorative trays of the
## floor never contradict the evidence: they, too, sit beside doors in the true state.

const PLAIN := [".", ",", "L", "l", "S"]
const MAX_CLUSTERS := 3


static func wall_spots(spec: ChunkSpec) -> Array[Dictionary]:
	## Plain floor tiles that touch a solid wall edge (no socket there): [{tile, wall}] in chunk-local tiles.
	var out: Array[Dictionary] = []
	var sock := spec.socket_edges()
	for t: Vector2i in spec.open:
		if not PLAIN.has(String(spec.open[t])):
			continue
		for d in Dir.ALL:
			if spec.open.has(t + d) or spec.pillars.has(t + d) or sock.has(ChunkSpec.edge_key(t, d)):
				continue
			out.append({"tile": t, "wall": d})
			break
	return out


static func can_host(spec: ChunkSpec, _e: EvidenceDef) -> bool:
	return wall_spots(spec).size() >= 3


static func place(chunk: Chunk, e: EvidenceDef, rng: RandomNumberGenerator, _session: Node) -> void:
	var open := String(e.params.get("doors", "open")) == "open"
	var spots := RngStreams.shuffled(rng, wall_spots(chunk.spec))
	var taken: Array[Vector2i] = []
	for s in spots:
		var t: Vector2i = s["tile"]
		var far := true
		for o in taken:
			if absi(o.x - t.x) + absi(o.y - t.y) < 4:
				far = false
		if not far:
			continue
		make_cluster(chunk, t, s["wall"], open, e, rng)
		taken.append(t)
		if taken.size() >= MAX_CLUSTERS:
			break


static func place_slot(chunk: Chunk, sl: ChunkSpec.SlotDef, truth: int, rng: RandomNumberGenerator) -> void:
	## A `T` slot on the Units floor: the tray, with a door beside it that is open (HOLDS) or shut (INVERTED).
	var sock := chunk.spec.socket_edges()
	for d in Dir.ALL:
		if chunk.spec.open.has(sl.tile + d) or chunk.spec.pillars.has(sl.tile + d) or sock.has(ChunkSpec.edge_key(sl.tile, d)):
			continue
		make_cluster(chunk, sl.tile, d, truth == RunState.Truth.HOLDS, null, rng)
		return
	# no wall to hang a door on: a lone tray on the floor
	var tray := PropFactory.make(&"tray")
	chunk.props_root.add_child(tray)
	tray.position = ChunkBuilder.local_center(sl.tile)


static func make_cluster(chunk: Chunk, tile: Vector2i, wall: Vector2i, doors_open: bool, e: EvidenceDef, rng: RandomNumberGenerator) -> Node3D:
	var holder: Node3D = EvidenceMark.create(e) if e != null else Node3D.new()
	if e == null:
		holder.name = "TrayDoor"
	chunk.props_root.add_child(holder)
	holder.position = ChunkBuilder.local_center(tile, 0.5) + Dir.to_vec3(wall) * (GameScale.TILE * 0.5)
	holder.rotation.y = Dir.yaw_of(-wall)
	var door := PropFactory.make(&"unit_door_open" if doors_open else &"unit_door_shut")
	door.position = Vector3(0, -0.5, 0)
	holder.add_child(door)
	var plate := PropFactory.make_label("%d" % (201 + rng.randi() % 38), Color(0.09, 0.07, 0.03), 0.1)
	plate.position = Vector3(0, 1.28, -0.1)
	plate.rotation.y = PI                          # a Label3D reads from +Z; the door's face is -Z
	holder.add_child(plate)
	var tray := PropFactory.make(&"tray")
	tray.position = Vector3(0.34, -0.5, -0.55)
	holder.add_child(tray)
	return holder
