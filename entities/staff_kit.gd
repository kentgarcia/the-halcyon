class_name StaffKit
extends RefCounted
## Helpers shared by the "people" entities (Queue, Greeter, Lobby Audit): what the guest can see, which doors a
## chunk has, rhythmic vs irregular knocking (the Greeter's P1 tell, SPEC 6.6) and a staff door opener. The Clause
## hooks themselves (walk_encouraged / staff_knock / doors_close / take_number) live in ClauseService and are asked
## through StaffRules, exactly like the Foreman and the Lifeguard do. Nothing here changes what is TRUE in the world.


# --- observation ----------------------------------------------------------------------------

static func guest_observes(session: Node, point: Vector3, max_dist: float = 48.0) -> bool:
	## True while the guest is LIVE-watching `point` (in the view cone, line of sight clear). A guest looking
	## through a raised camcorder still counts (a narrower cone); a guest watching a tape does not, and neither
	## does a planted camcorder: its tape is the one honest way to watch a Greeter walk (SPEC 6.6).
	var pl := session.player as Player
	if pl == null or pl.camera == null or not pl.camera.is_inside_tree():
		return false
	var cc: Camcorder = session.camcorder as Camcorder
	if cc != null and cc.in_playback():
		return false
	var cam := pl.camera
	var from := cam.global_position
	var to := point - from
	var dist := to.length()
	if dist > max_dist:
		return false
	if dist < 0.6:
		return true
	var local := cam.global_transform.basis.inverse() * to
	if local.z >= 0.0:
		return false
	var vsize := cam.get_viewport().get_visible_rect().size
	var aspect := maxf(0.5, vsize.x / maxf(1.0, vsize.y))
	var vhalf := deg_to_rad(cam.fov) * 0.5
	var hhalf := atan(tan(vhalf) * aspect)
	if atan2(absf(local.x), -local.z) > hhalf or atan2(absf(local.y), -local.z) > vhalf:
		return false
	return los_clear(pl, from, point)


static func los_clear(pl: Player, from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, GameScale.LAYER_WORLD | GameScale.LAYER_DOORS)
	q.exclude = [pl.get_rid()]
	var hit := pl.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(to) < 0.5


static func clause(session: Node, clause_id: StringName) -> bool:
	return session != null and session.has_method("clause_active") and bool(session.clause_active(clause_id))


# --- doors ----------------------------------------------------------------------------------

static func chunk_doors(session: Node, chunk: Chunk) -> Array[Dictionary]:
	## The doors on a chunk's exit sockets: [{door, tile, dir, index, role, forward, dead_end}]. `forward` is the door
	## to the next main beat; `dead_end` doors lead to closets / vaults / breaker rooms (rooms with no other exit).
	var out: Array[Dictionary] = []
	if chunk == null or session == null:
		return out
	var grid := session.grid as WorldGrid
	var bp: FloorPlan.BeatPlan = chunk.plan.get("bp", null) as FloorPlan.BeatPlan
	for e in chunk.exit_world:
		var tile: Vector2i = e["tile"]
		var dir: Vector2i = e["dir"]
		var d := grid.door_on_edge(tile, tile + dir)
		if d == null:
			continue
		var role: StringName = &"forward"
		if d.connection != null:
			role = StringName((d.connection as DoorConnection).plan.get("role", &"forward"))
		var is_fwd := bp != null and bp.main and int(e["index"]) == bp.forward_exit
		out.append({
			"door": d, "tile": tile, "dir": dir, "index": int(e["index"]), "role": role, "forward": is_fwd,
			"dead_end": role in [&"closet", &"vault", &"breaker"],
		})
	return out


static func door_pos(d: Door) -> Vector3:
	return d.global_position + Vector3(0, 1.2, 0)


# --- knocks ---------------------------------------------------------------------------------

static func knock_times(truth: int, count: int, base_gap: float, rng: RandomNumberGenerator) -> Array[float]:
	## Offsets (s) of each knock. HOLDS is rhythmic: one steady gap. INVERTED is irregular: no two gaps alike.
	var out: Array[float] = [0.0]
	var t := 0.0
	var prev_gap := base_gap
	for _i in range(1, count):
		var gap := base_gap
		if truth == RunState.Truth.INVERTED:
			for _try in 6:
				gap = base_gap * rng.randf_range(0.35, 2.1)
				if absf(gap - prev_gap) > base_gap * 0.3:
					break
		t += gap
		prev_gap = gap
		out.append(t)
	return out


static func knock_sound(truth: int) -> StringName:
	return &"knock_slow" if truth == RunState.Truth.HOLDS else &"knock_irregular"


# --- the staff door opener ------------------------------------------------------------------

class DoorOpener extends RefCounted:
	## Opens one door the way staff are allowed to: honouring staff_knock (three knocks over ~5 s first) and
	## doors_close (not within 8 s of the guest closing it), both asked of the ClauseService through StaffRules.
	## Drive it with step(delta); `done` flips when the door has been opened (or it gave up).
	var door: Door = null
	var session: Node = null
	var entity: EntityBase = null
	var t := 0.0
	var done := false
	var opened := false
	var knocks: Array[float] = []
	var knock_i := 0

	func start(p_session: Node, p_door: Door, p_entity: EntityBase) -> void:
		session = p_session
		door = p_door
		entity = p_entity
		t = 0.0
		done = false
		opened = false
		knock_i = 0
		knocks.clear()
		if StaffRules.knock_seconds(session, entity) > 0.0:
			knocks = [0.0, 2.2, 4.4]

	func step(delta: float) -> void:
		if done or door == null or not is_instance_valid(door):
			done = true
			return
		t += delta
		while knock_i < knocks.size() and t >= knocks[knock_i]:
			AudioDirector.play_at(&"knock_slow", StaffKit.door_pos(door), 0.0)
			AudioDirector.cue("[Knock, knock, knock]", 1.2)
			knock_i += 1
		if StaffRules.door_gate(session, door, entity, t) != &"open":
			return                                   # still knocking, or the guest closed it under 8 s ago
		var pl := session.player as Player
		var side := door.side_of(pl.global_position) if pl != null else 1
		door.open_door(side)
		opened = true
		done = true
