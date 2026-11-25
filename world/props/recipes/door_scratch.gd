extends RefCounted
## P2 recipe `door_scratch` (B3 Boiler, INVERTED): scratches on the inside of the exit doors. True evidence: the
## INVERTED Foreman waits behind the nearest exit (SPEC 6.2). The marks are children of the door leaf (they swing
## with it) on the face the guest sees from the room, and they only exist on doors that really are exits.

const CLAW := &"#d2c39f"
const GOUGE := &"#1d140c"
const SETS_PER_DOOR := 3


static func can_host(spec: ChunkSpec, _e: EvidenceDef) -> bool:
	return not spec.exits.is_empty()


static func place(chunk: Chunk, e: EvidenceDef, rng: RandomNumberGenerator, session: Node) -> void:
	var done := 0
	for ex: Dictionary in chunk.exit_world:
		var door := AlarmSite.exit_door(session, ex)
		if door == null or door.pivot == null or not AlarmSite.usable(door):
			continue
		var room_a := AlarmSite.room_on_side_a(door, ex)
		var z := (GameScale.DOOR_LEAF_T * 0.5 + 0.004) * (1.0 if room_a else -1.0)
		for i in SETS_PER_DOOR:
			var x := GameScale.DOOR_W * (0.2 + 0.28 * float(i)) + rng.randf_range(-0.05, 0.05)
			var y := rng.randf_range(0.7, 1.75)
			var mb := MeshBuilder.new()
			_claws(mb, rng, z, room_a)
			var mark := MarkShapes.mark_node(e, mb)
			door.pivot.add_child(mark)
			mark.position = Vector3(x, y, 0.0)
			done += 1
	if done == 0:
		_fallback(chunk, e, rng)


static func _claws(mb: MeshBuilder, rng: RandomNumberGenerator, z: float, plus_z: bool) -> void:
	## Four parallel gouges with a darker core, slightly slanted, 40-60 cm long.
	var tilt := rng.randf_range(-0.28, 0.28)
	var len := rng.randf_range(0.42, 0.62)
	var dir := Vector2(sin(tilt), cos(tilt))
	for k in 4:
		var off := (float(k) - 1.5) * 0.052
		var p0 := Vector2(off, -len * 0.5) - Vector2(0, 0)
		var p1 := p0 + dir * len
		MarkShapes.leaf_line(mb, GOUGE, p0, p1, 0.026, z, plus_z)
		MarkShapes.leaf_line(mb, CLAW, p0, p1, 0.012, z + (0.002 if plus_z else -0.002), plus_z)


static func _fallback(chunk: Chunk, e: EvidenceDef, rng: RandomNumberGenerator) -> void:
	## No live door to hang the marks on (a chunk preview): scratch the floor in front of each exit instead.
	for s: ChunkSpec.SocketDef in chunk.spec.exits:
		var c := ChunkBuilder.local_center(s.tile)
		var mb := MeshBuilder.new()
		for k in 4:
			var off := (float(k) - 1.5) * 0.06
			MarkShapes.floor_line(mb, CLAW, Vector3(off, 0, -0.25), Vector3(off + rng.randf_range(-0.05, 0.05), 0, 0.25), 0.014, 0.012)
		var mark := MarkShapes.mark_node(e, mb)
		chunk.props_root.add_child(mark)
		mark.position = c + Dir.to_vec3(s.dir) * (GameScale.TILE * 0.3)
