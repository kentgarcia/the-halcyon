extends TestCase
## The Foreman (SPEC 6.2, B3 Boiler): pure rules (tell lead, truth-dependent exit choice, scrape direction, the
## strike rules), the staff Clause pass-through, and his P2 evidence recipes placed on every room that can host them.

class FakeStreamer extends RefCounted:
	var connections: Dictionary = {}


class FakeSession extends Node:
	var streamer: FakeStreamer = FakeStreamer.new()
	var plan: FloorPlan = null


const LEAD := 4.6                     ## DirectorTuning.tell_lead_seconds (4.0) + the Director's 0.6 s


func _evidence(id: StringName) -> EvidenceDef:
	for e: EvidenceDef in FloorCatalog.get_def(&"boiler").evidence:
		if e.id == id:
			return e
	return null


func _specs() -> Array[ChunkSpec]:
	ChunkLibrary.reload()
	var out: Array[ChunkSpec] = []
	for beat in AlarmSite.WORKING_BEATS:
		for s in ChunkLibrary.pool(&"boiler", beat):
			if not out.has(s):
				out.append(s)
	return out


func _build(spec: ChunkSpec, uid: int = 1) -> Chunk:
	return ChunkBuilder.build(spec, Themes.get_theme(&"boiler"), 0, Vector2i.ZERO, uid)


func _marks(root: Node, id: StringName) -> Array[EvidenceMark]:
	var out: Array[EvidenceMark] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is EvidenceMark and (n as EvidenceMark).def != null and (n as EvidenceMark).def.id == id:
			out.append(n)
		stack.append_array(n.get_children())
	return out


func _session_with_doors(chunk: Chunk) -> FakeSession:
	## A fake session whose streamer knows one real fire Door per exit of the chunk.
	var s := FakeSession.new()
	for ex: Dictionary in chunk.exit_world:
		var door := Door.create(&"fire", ex["tile"], ex["dir"])
		var conn := DoorConnection.new()
		conn.door = door
		conn.tile_a = door.tile_a
		conn.tile_b = door.tile_b
		conn.dir_ab = door.dir_ab
		s.streamer.connections[ChunkPlacer.edge_key(ex["tile"], ex["tile"] + ex["dir"])] = conn
		s.add_child(door)
	return s


# --- identity -------------------------------------------------------------------------------

func test_identity_and_factory() -> void:
	var f := Foreman.new()
	assert_eq(f.entity_id, &"foreman")
	assert_true(f.is_staff, "the Foreman is staff: the Clauses bind him")
	f.free()
	assert_true(EntityFactory.available(&"foreman"))
	var made := EntityFactory.create(&"foreman")
	assert_true(made is Foreman, "factory builds a Foreman")
	if made != null:
		made.free()


# --- pure rules -----------------------------------------------------------------------------

func test_tell_lasts_at_least_four_seconds_for_both_truths() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var ev := Foreman.tell_events(truth, LEAD)
		var scrape: Dictionary = {}
		for e in ev:
			assert_true(float(e["t"]) >= 0.0 and float(e["t"]) + float(e["dur"]) <= LEAD + 0.001, "%s cue stays inside the lead" % e["kind"])
			if e["kind"] == &"scrape":
				scrape = e
		assert_false(scrape.is_empty(), "the wrench scrape is always part of the tell")
		assert_near(float(scrape["t"]), 0.0, 0.0001, "the scrape starts with the tell")
		assert_true(float(scrape["dur"]) >= 4.0, "the scrape foretells the hazard for >= 4 s (Doctrine 2)")


func test_flicker_cue_only_when_the_card_lies() -> void:
	var holds := Foreman.tell_events(RunState.Truth.HOLDS, LEAD).map(func(e): return e["kind"])
	var inv := Foreman.tell_events(RunState.Truth.INVERTED, LEAD).map(func(e): return e["kind"])
	assert_false(holds.has(&"flicker"), "HOLDS: the exit sign burns steady")
	assert_true(inv.has(&"flicker"), "INVERTED: the exit sign flickers")
	assert_false(Foreman.sign_flickers(RunState.Truth.HOLDS))
	assert_true(Foreman.sign_flickers(RunState.Truth.INVERTED))


func test_exit_choice_depends_on_truth() -> void:
	var steps := [3, 11, 7]
	assert_eq(Foreman.pick_exit(steps, RunState.Truth.HOLDS), 1, "HOLDS: he enters by the exit farthest from the guest")
	assert_eq(Foreman.pick_exit(steps, RunState.Truth.INVERTED), 0, "INVERTED: he waits behind the nearest exit")
	assert_eq(Foreman.pick_exit([-1, 5, -1], RunState.Truth.HOLDS), 1, "unreachable exits are ignored")
	assert_eq(Foreman.pick_exit([-1, 5, -1], RunState.Truth.INVERTED), 1)
	assert_eq(Foreman.pick_exit([4, 4], RunState.Truth.INVERTED), 0, "ties go to the lower index")
	assert_eq(Foreman.pick_exit([-1, -1], RunState.Truth.HOLDS), -1, "no reachable exit: no choice")
	assert_eq(Foreman.pick_exit([], RunState.Truth.INVERTED), -1)


func test_scrape_direction_shows_the_truth() -> void:
	var door := Vector3(0, 0, 0)
	var src := Vector3(10, 0, 4)
	var holds := Foreman.scrape_route(RunState.Truth.HOLDS, door, src)
	var inv := Foreman.scrape_route(RunState.Truth.INVERTED, door, src)
	assert_eq(holds[0], door, "HOLDS: the scrape travels from the exit toward the alarm")
	assert_eq(holds[1], src)
	assert_eq(inv[0], src, "INVERTED: the scrape travels from the alarm to the exit and stops there")
	assert_eq(inv[1], door)


func test_strike_rules() -> void:
	var r := 1.8
	assert_true(Foreman.can_strike(RunState.Truth.HOLDS, Foreman.Mode.SEARCH, 1.0, false, false, r), "HOLDS: searching, guest underfoot")
	assert_false(Foreman.can_strike(RunState.Truth.HOLDS, Foreman.Mode.SEARCH, 3.0, false, false, r), "out of reach")
	assert_false(Foreman.can_strike(RunState.Truth.HOLDS, Foreman.Mode.GO, 1.0, false, false, r), "HOLDS: he is after the alarm, not the guest")
	assert_false(Foreman.can_strike(RunState.Truth.HOLDS, Foreman.Mode.SEARCH, 1.0, false, true, r), "a hidden guest is never struck")
	assert_true(Foreman.can_strike(RunState.Truth.INVERTED, Foreman.Mode.WINDUP, 1.0, true, false, r), "INVERTED: the guest at his open door")
	assert_false(Foreman.can_strike(RunState.Truth.INVERTED, Foreman.Mode.WINDUP, 1.0, false, false, r), "door shut: nothing to strike through")
	assert_false(Foreman.can_strike(RunState.Truth.INVERTED, Foreman.Mode.WAIT, 1.0, true, false, r), "no strike before the windup")
	assert_false(Foreman.can_strike(RunState.Truth.INVERTED, Foreman.Mode.WINDUP, 1.0, true, true, r), "a hidden guest is never struck")


func test_staff_rules_without_a_session_are_no_ops() -> void:
	var f := Foreman.new()
	assert_false(StaffRules.frozen(null))
	assert_near(StaffRules.speed_cap(null, f, 4.0), 4.0, 0.0001, "no Clause, no cap")
	assert_near(StaffRules.knock_seconds(null, f), 0.0, 0.0001)
	assert_true(StaffRules.may_open_door(null, null, f))
	assert_eq(StaffRules.door_gate(null, null, f, 0.0), &"open")
	f.free()


# --- the alarm bell and exit signs ----------------------------------------------------------

func test_every_working_room_gets_a_bell_away_from_the_doors() -> void:
	var hosted := 0
	for spec in _specs():
		var bell_site := AlarmSite.bell_site(spec, RandomNumberGenerator.new())
		if bell_site.is_empty():
			continue
		hosted += 1
		var t: Vector2i = bell_site["tile"]
		assert_true(spec.open.has(t), "%s: bell stands on an open tile" % spec.id)
		assert_false(spec.open.has(t + bell_site["dir"]), "%s: bell is on a wall face" % spec.id)
		for s: ChunkSpec.SocketDef in spec.exits + spec.entries:
			assert_true(absi(s.tile.x - t.x) + absi(s.tile.y - t.y) >= AlarmSite.MIN_DOOR_GAP, "%s: bell is not at a door" % spec.id)
	assert_gt(float(hosted), 0.0, "some boiler room can hold a bell")


func test_ensure_bell_is_idempotent() -> void:
	for spec in _specs():
		if AlarmSite.bell_site(spec, RandomNumberGenerator.new()).is_empty():
			continue
		var chunk := _build(spec)
		var a := AlarmSite.ensure_bell(chunk, null)
		var b := AlarmSite.ensure_bell(chunk, null)
		assert_not_null(a, "%s: a bell" % spec.id)
		assert_true(a == b, "%s: one bell per room" % spec.id)
		chunk.free()
		return


func test_exit_signs_ride_the_door_and_flicker_on_command() -> void:
	for spec in _specs():
		if spec.exits.is_empty() or not AlarmSite.is_working_room(spec):
			continue
		var chunk := _build(spec)
		var session := _session_with_doors(chunk)
		var signs := AlarmSite.ensure_signs(chunk, session)
		assert_eq(signs.size(), chunk.exit_world.size(), "%s: a sign on every exit door" % spec.id)
		for k in signs:
			var s: ExitSign = signs[k]
			assert_true(s.get_parent().name == "Hinge", "the sign is on the door leaf")
			s.set_flicker(true)
			assert_true(s.flickering)
			s.set_flicker(false)
			assert_false(s.flickering)
		assert_eq(AlarmSite.ensure_signs(chunk, session).size(), signs.size(), "idempotent")
		chunk.free()
		session.free()
		return


# --- evidence recipes -----------------------------------------------------------------------

func test_scrape_recipe_marks_every_room_that_can_host_it() -> void:
	var e := _evidence(&"boiler_trail_h")
	assert_not_null(e, "trail_h exists")
	assert_eq(e.variant, RunState.Truth.HOLDS, "scrapes are HOLDS evidence")
	var hosts := 0
	for spec in _specs():
		if not EvidenceRecipes.can_host(spec, e):
			continue
		hosts += 1
		var chunk := _build(spec)
		var session := _session_with_doors(chunk)
		EvidenceRecipes.place(chunk, e, RandomNumberGenerator.new(), session)
		var marks := _marks(chunk, &"boiler_trail_h")
		assert_gt(float(marks.size()), 0.0, "%s: scrape marks placed" % spec.id)
		for m in marks:
			assert_eq(m.def.variant, RunState.Truth.HOLDS, "%s: only HOLDS marks" % spec.id)
		chunk.free()
		session.free()
	assert_gt(float(hosts), 0.0, "some boiler room hosts the scrape trail")


func test_scrape_recipe_leads_from_the_exit_to_the_bell() -> void:
	## The mark nearest the bell sits closer to it than the mark nearest the exit (direction of travel is readable).
	var e := _evidence(&"boiler_trail_h")
	for spec in _specs():
		if not EvidenceRecipes.can_host(spec, e) or spec.exits.is_empty():
			continue
		var chunk := _build(spec)
		var bell := AlarmSite.ensure_bell(chunk, null)
		EvidenceRecipes.place(chunk, e, RandomNumberGenerator.new(), null)
		var marks := _marks(chunk, &"boiler_trail_h")
		var near_door := INF
		var near_bell := INF
		var door_pos := ChunkBuilder.local_center(spec.exits[0].tile)
		for m in marks:
			near_door = minf(near_door, Vector2(m.position.x - door_pos.x, m.position.z - door_pos.z).length())
			near_bell = minf(near_bell, Vector2(m.position.x - bell.position.x, m.position.z - bell.position.z).length())
		assert_lt(near_door, 3.0, "%s: streaks start at the exit" % spec.id)
		assert_lt(near_bell, 4.5, "%s: streaks end at the bell" % spec.id)
		chunk.free()
		return


func test_door_scratch_recipe_marks_the_door_leaf() -> void:
	var e := _evidence(&"boiler_scratch_i")
	assert_not_null(e, "scratch_i exists")
	assert_eq(e.variant, RunState.Truth.INVERTED, "door scratches are INVERTED evidence")
	var hosts := 0
	for spec in _specs():
		if not EvidenceRecipes.can_host(spec, e):
			continue
		hosts += 1
		var chunk := _build(spec)
		var session := _session_with_doors(chunk)
		EvidenceRecipes.place(chunk, e, RandomNumberGenerator.new(), session)
		var on_door := 0
		for conn: DoorConnection in session.streamer.connections.values():
			on_door += _marks(conn.door.pivot, &"boiler_scratch_i").size()
		assert_gt(float(on_door), 0.0, "%s: scratches on the door leaf" % spec.id)
		chunk.free()
		session.free()
	assert_gt(float(hosts), 0.0, "some boiler room hosts door scratches")


func test_door_scratch_falls_back_to_the_floor_without_doors() -> void:
	var e := _evidence(&"boiler_scratch_i")
	for spec in _specs():
		if not EvidenceRecipes.can_host(spec, e):
			continue
		var chunk := _build(spec)
		EvidenceRecipes.place(chunk, e, RandomNumberGenerator.new(), null)
		assert_gt(float(_marks(chunk, &"boiler_scratch_i").size()), 0.0, "%s: floor scratches when no door exists yet" % spec.id)
		chunk.free()
		return


func test_recipes_are_deterministic_from_the_rng() -> void:
	var e := _evidence(&"boiler_trail_h")
	for spec in _specs():
		if not EvidenceRecipes.can_host(spec, e):
			continue
		var counts: Array[int] = []
		for i in 2:
			var chunk := _build(spec, 7)
			var rng := RandomNumberGenerator.new()
			rng.seed = 4242
			EvidenceRecipes.place(chunk, e, rng, null)
			counts.append(_marks(chunk, &"boiler_trail_h").size())
			chunk.free()
		assert_eq(counts[0], counts[1], "%s: same seed, same marks" % spec.id)
		return
