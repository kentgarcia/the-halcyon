extends TestCase
## The Greeter (SPEC 6.6, 2F Units): identity, the tell lead, "moves only while unobserved", the HOLDS and INVERTED
## outcomes of answering and ignoring, rhythmic vs irregular knocks, the smile, the staff Clauses, and his tray
## evidence (open doors on HOLDS, shut on INVERTED).

const EXAM := &"uni_exam_greeter_corridor"
const LEAD := 4.6

var _fx: CrowdFixture = null
var _snap: Dictionary = {}


func before_each() -> void:
	_snap = {"clause": RunState.clause, "void": RunState.clause_void, "nerve": RunState.nerve}


func after_each() -> void:
	if _fx != null and is_instance_valid(_fx):
		_fx.dispose()
	_fx = null
	RunState.clause = _snap["clause"]
	RunState.clause_void = _snap["void"]
	RunState.set_nerve(_snap["nerve"])


func _room(truth: int, chunk_id: StringName = EXAM) -> Greeter:
	_fx = CrowdFixture.create(tree.root, &"units", chunk_id, truth)
	RunState.set_nerve(RunState.nerve_max)
	var g := Greeter.new()
	g.manual = true
	g.observed_override = 0
	_fx.add_entity(g)
	return g


func _live(truth: int) -> Greeter:
	var g := _room(truth)
	assert_true(g.tell(LEAD, _fx.chunk), "the tell starts in the exam corridor")
	g.begin_encounter(_fx.chunk, &"major", g.encounter_duration(&"major", 60.0))
	return g


func _run(g: Greeter, seconds: float, dt: float = 0.1) -> void:
	var t := 0.0
	while t < seconds and g.mode != Greeter.Mode.OFF:
		g.step(dt)
		t += dt


func _until(g: Greeter, mode: int, max_s: float = 40.0) -> bool:
	var t := 0.0
	while t < max_s and g.mode != mode and g.mode != Greeter.Mode.OFF:
		g.step(0.1)
		t += 0.1
	return g.mode == mode


func _hide_the_guest() -> void:
	var hides: Array = _fx.chunk.slot_nodes.get(&"hide", [])
	assert_true(hides.size() > 0, "the corridor has wardrobes to hide in")
	_fx.player.enter_hide(hides[0] as HideSpot, 1.4)


# --- identity / tell --------------------------------------------------------------------------

func test_identity_and_factory() -> void:
	var g := Greeter.new()
	assert_eq(g.entity_id, &"greeter")
	assert_true(g.is_staff, "the Greeter is staff: the Clauses bind him")
	g.free()
	assert_true(EntityFactory.available(&"greeter"))
	var made := EntityFactory.create(&"greeter")
	assert_true(made is Greeter)
	if made != null:
		made.free()


func test_tell_lasts_at_least_four_seconds_and_he_stands_at_the_far_end() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var g := _room(truth)
		assert_true(g.tell(LEAD, _fx.chunk))
		assert_true(g.tell_lead >= 4.0, "the genuine tell leads by >= 4 s (the bell)")
		assert_eq(g.mode, Greeter.Mode.STAND)
		var field: Dictionary = _fx.session.grid.distance_field(GameScale.world_to_tile(_fx.player.global_position), 60)
		assert_true(int(field.get(g.tile, 0)) >= 20, "he stands in the doorframe at the far end of the corridor")
		_fx.dispose()
		_fx = null


# --- he moves only while unobserved ----------------------------------------------------------

func test_he_moves_only_while_he_is_not_watched() -> void:
	var g := _live(RunState.Truth.HOLDS)
	var start := g.global_position
	g.observed_override = 1
	_run(g, 4.0)
	assert_true(g.global_position.distance_to(start) < 0.01, "watched: he does not take a step")
	g.observed_override = 0
	_run(g, 4.0)
	assert_true(g.global_position.distance_to(start) > 4.0, "unwatched: he is suddenly closer")


func test_the_real_view_cone_decides_what_watched_means() -> void:
	var g := _live(RunState.Truth.HOLDS)
	g.observed_override = -1
	var corridor_start := _fx.player.global_position
	_fx.face(g.global_position + Vector3(0, 1.7, 0))
	assert_true(StaffKit.guest_observes(_fx.session, g.head_point()), "looking straight down the corridor at him: watched")
	_fx.player.rotation.y += PI
	assert_false(StaffKit.guest_observes(_fx.session, g.head_point()), "facing away: not watched")
	assert_true(corridor_start.distance_to(_fx.player.global_position) < 0.01)


func test_a_whistle_freezes_him_where_he_stands() -> void:
	var g := _live(RunState.Truth.HOLDS)
	var start := g.global_position
	_fx.session.staff_frozen_flag = true
	_run(g, 3.0)
	assert_true(g.global_position.distance_to(start) < 0.01, "frozen staff do not move")
	_fx.session.staff_frozen_flag = false
	_run(g, 3.0)
	assert_true(g.global_position.distance_to(start) > 2.0, "and move again afterwards")


func test_walk_encouraged_caps_him_at_a_walk_while_he_can_see_the_guest() -> void:
	var g := _live(RunState.Truth.HOLDS)
	RunState.clause = &""
	assert_near(g.walk_speed(), CrowdTuning.load_default().greeter_speed, 0.0001, "no Clause: his full pace")
	RunState.clause = &"walk_encouraged"
	RunState.clause_void = false
	g.global_position = _fx.player.global_position + Vector3(2.5, 0.0, 0.0)
	assert_true(g.walk_speed() <= GameScale.WALK_SPEED + 0.0001, "walk_encouraged: never faster than a walk in the guest's sight")


# --- HOLDS: answering -------------------------------------------------------------------------

func _greeted(truth: int) -> Greeter:
	var g := _live(truth)
	assert_true(_until(g, Greeter.Mode.GREET, 40.0), "he walks up and greets (unwatched)")
	assert_true(g.distance_to_player() <= CrowdTuning.load_default().greeter_greet_dist + 0.05, "from speaking distance")
	return g


func test_holds_answering_makes_him_nod_open_a_door_and_leave() -> void:
	var g := _greeted(RunState.Truth.HOLDS)
	g.answer()
	assert_true(g.answered)
	assert_eq(g.mode, Greeter.Mode.GUIDE)
	_run(g, 40.0)
	assert_not_null(g.opened_door, "he opened a door")
	assert_true(g.opened_door.is_open() or g.opened_door.state == Door.State.OPEN, "and it stands open")
	assert_eq(g.mode, Greeter.Mode.OFF, "then he is gone")
	assert_false(g.escorted)
	assert_eq(RunState.nerve, RunState.nerve_max, "HOLDS: answering costs nothing")


func test_staff_knock_clause_makes_him_knock_for_five_seconds_first() -> void:
	var times: Array[float] = []
	for clause in [&"", &"staff_knock"]:
		RunState.clause = clause
		RunState.clause_void = false
		var g := _greeted(RunState.Truth.HOLDS)
		g.answer()
		var t := 0.0
		while t < 80.0 and g.opened_door == null and g.mode != Greeter.Mode.OFF:
			g.step(0.1)
			t += 0.1
		# time from reaching the door to opening it: the Clause adds the knocks
		var opener_t := 0.0
		if g.opener != null:
			opener_t = g.opener.t
		times.append(opener_t)
		assert_not_null(g.opened_door, "he opens it in the end (clause '%s')" % clause)
		_fx.dispose()
		_fx = null
	assert_true(times[1] >= 5.0 - 0.001, "staff_knock: he knocks ~5 s before opening (%.2f)" % times[1])
	assert_true(times[0] < 1.0, "no Clause: he just opens it (%.2f)" % times[0])


func test_doors_close_clause_keeps_him_from_a_door_the_guest_just_shut() -> void:
	RunState.clause = &"doors_close"
	RunState.clause_void = false
	var g := _greeted(RunState.Truth.HOLDS)
	g.answer()
	var picked: Dictionary = g._pick_guide_door()
	var door: Door = picked["door"]
	_fx.put_player(door.global_position + Vector3(0, 0, 1.0), 0.0)
	EventBus.door_closed.emit(door)                      # the guest shuts it (ClauseService notes the time)
	assert_false(StaffRules.may_open_door(_fx.session, door, g), "the Clause forbids staff to open it for 8 s")
	assert_eq(StaffRules.door_gate(_fx.session, door, g, 10.0), &"wait", "so the opener waits")
	_fx.session.clauses._process(8.5)
	assert_true(StaffRules.may_open_door(_fx.session, door, g), "and allows it afterwards")
	assert_eq(StaffRules.door_gate(_fx.session, door, g, 10.0), &"open")


# --- HOLDS: ignoring --------------------------------------------------------------------------

func test_holds_ignoring_him_has_him_follow_ask_again_and_in_the_end_insist() -> void:
	var g := _greeted(RunState.Truth.HOLDS)
	_run(g, 120.0)
	assert_true(g.ignored, "the answer window passed")
	assert_true(g.repeats >= 1, "he asked again")
	assert_true(g.insisted, "HOLDS: ignoring an honest greeting ends in an insistence")
	assert_eq(RunState.nerve, RunState.nerve_max - 1, "a warning: one segment, never lethal at full Nerve")


func test_holds_hiding_from_him_gets_three_slow_rhythmic_knocks() -> void:
	var g := _greeted(RunState.Truth.HOLDS)
	_run(g, 16.0)                                         # greeting ignored: he follows
	_hide_the_guest()
	_run(g, 60.0)
	assert_eq(g.knock_count, 3, "HOLDS: three knocks")
	var gaps: Array[float] = []
	for i in range(1, g.knock_log.size()):
		gaps.append(g.knock_log[i] - g.knock_log[i - 1])
	assert_eq(gaps.size(), 2)
	assert_near(gaps[0], gaps[1], 0.002, "HOLDS: the knocks are rhythmic (equal gaps)")
	assert_eq(StaffKit.knock_sound(RunState.Truth.HOLDS), &"knock_slow")


# --- INVERTED ---------------------------------------------------------------------------------

func test_inverted_answering_walks_the_guest_into_a_room_with_no_exit() -> void:
	var g := _greeted(RunState.Truth.INVERTED)
	# one door of the room leads to a closet: the only honest "unit with no exit"
	var doors := StaffKit.chunk_doors(_fx.session, _fx.chunk)
	assert_true(doors.size() >= 1)
	var trap: Door = doors[0]["door"]
	(trap.connection as DoorConnection).plan["role"] = &"closet"
	g.answer()
	assert_true(g.escorted, "INVERTED: answering is the wrong play")
	assert_eq(g.mode, Greeter.Mode.ESCORT)
	_run(g, 4.0)
	assert_true(trap.sealed, "the door behind the guest is held shut")
	assert_eq(RunState.nerve, RunState.nerve_max - 1, "a hit that lands as a warning, not a blackout")
	assert_true(RunState.nerve > 0)
	assert_false(_fx.player.speed_mods.has(&"escort"), "the guest can move again")
	_run(g, CrowdTuning.load_default().greeter_escort_hold + 6.0)
	assert_false(trap.sealed, "he lets the door go in the end")
	assert_false(g.active, "the encounter stood down")


func test_inverted_answering_in_a_room_without_a_dead_end_is_shown_out() -> void:
	var g := _greeted(RunState.Truth.INVERTED)
	g.answer()
	_run(g, 12.0)
	assert_true(g.escorted)
	assert_true(RunState.nerve >= RunState.nerve_max - 1 and RunState.nerve > 0, "never lethal at full Nerve")
	assert_eq(_fx.session.hits.size(), 1, "exactly one hit")


func test_inverted_ignoring_him_is_safe_and_hiding_gets_one_to_three_irregular_knocks() -> void:
	var g := _greeted(RunState.Truth.INVERTED)
	_run(g, 40.0)
	assert_true(g.ignored)
	assert_false(g.escorted)
	assert_eq(RunState.nerve, RunState.nerve_max, "INVERTED: ignoring costs nothing")
	_hide_the_guest()
	_run(g, 60.0)
	assert_true(g.knock_count >= 1 and g.knock_count <= 3, "INVERTED: one to three knocks (%d)" % g.knock_count)
	assert_eq(StaffKit.knock_sound(RunState.Truth.INVERTED), &"knock_irregular")
	assert_eq(RunState.nerve, RunState.nerve_max)


func test_knock_rhythm_is_the_honest_tell_for_every_seed() -> void:
	for seed in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var holds := StaffKit.knock_times(RunState.Truth.HOLDS, 3, 1.2, rng)
		assert_eq(holds.size(), 3)
		assert_near(holds[1] - holds[0], holds[2] - holds[1], 0.0001, "HOLDS knocks are evenly spaced")
		var inv := StaffKit.knock_times(RunState.Truth.INVERTED, 3, 1.2, rng)
		var g1 := inv[1] - inv[0]
		var g2 := inv[2] - inv[1]
		assert_true(absf(g1 - g2) > 0.05, "INVERTED knocks are not evenly spaced (seed %d: %.2f vs %.2f)" % [seed, g1, g2])


func test_the_painted_smile_is_one_frame_on_holds_and_drifts_on_inverted() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var g := _live(truth)
		var seen := {}
		var t := 0.0
		while t < 12.0:
			g.step(0.1)
			t += 0.1
			var v: Variant = g.sil.mat.get_shader_parameter("smile_seed")
			seen[snappedf(0.0 if v == null else float(v), 0.001)] = true
		if truth == RunState.Truth.HOLDS:
			assert_eq(seen.size(), 1, "HOLDS: one fixed smile")
		else:
			assert_true(seen.size() >= 3, "INVERTED: subtly different frames (%d)" % seen.size())
		_fx.dispose()
		_fx = null


func test_stand_down_always_ends_the_encounter() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var g := _live(truth)
		_run(g, 3.0)
		g.stand_down()
		assert_false(g.active)
		assert_false(_fx.player.nerve.in_danger)
		_run(g, 5.0)
		assert_eq(g.mode, Greeter.Mode.OFF, "he leaves")
		_fx.dispose()
		_fx = null


# --- evidence ---------------------------------------------------------------------------------

func _marks(root: Node, id: StringName) -> Array[EvidenceMark]:
	var out: Array[EvidenceMark] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is EvidenceMark and (n as EvidenceMark).def != null and (n as EvidenceMark).def.id == id:
			out.append(n)
		stack.append_array(n.get_children())
	return out


func _count_named(root: Node, node_name: String) -> int:
	var n := 1 if root.name == node_name else 0
	for c in root.get_children():
		n += _count_named(c, node_name)
	return n


func _evidence(id: StringName) -> EvidenceDef:
	for e: EvidenceDef in FloorCatalog.get_def(&"units").evidence:
		if e.id == id:
			return e
	return null


func test_tray_recipe_puts_open_doors_beside_trays_on_holds_and_shut_doors_on_inverted() -> void:
	ChunkLibrary.reload()
	var hosts := 0
	for beat in [&"choice", &"long", &"exam"]:
		for spec in ChunkLibrary.pool(&"units", beat):
			var eh := _evidence(&"units_tray_h")
			if not TrayRecipe.can_host(spec, eh):
				continue
			hosts += 1
			for e in [eh, _evidence(&"units_tray_i")]:
				var chunk := ChunkBuilder.build(spec, Themes.get_theme(&"units"), 0, Vector2i.ZERO, 9)
				tree.root.add_child(chunk)
				var rng := RandomNumberGenerator.new()
				rng.seed = 77
				EvidenceRecipes.place(chunk, e, rng, null)
				var marks := _marks(chunk, e.id)
				assert_true(marks.size() >= 1, "%s: %s is placed" % [spec.id, e.id])
				var open_doors := 0
				var shut_doors := 0
				for m in marks:
					open_doors += _count_named(m, "UnitDoorOpen")
					shut_doors += _count_named(m, "UnitDoorShut")
				if e.id == &"units_tray_h":
					assert_true(open_doors >= 1 and shut_doors == 0, "%s: HOLDS trays sit beside OPEN doors" % spec.id)
				else:
					assert_true(shut_doors >= 1 and open_doors == 0, "%s: INVERTED trays sit beside SHUT doors" % spec.id)
				tree.root.remove_child(chunk)
				chunk.free()
	assert_true(hosts >= 3, "several units rooms can host the trays (%d)" % hosts)


func test_decorative_trays_never_contradict_the_evidence() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var g := _room(truth)
		var open_doors := _count_named(_fx.chunk, "UnitDoorOpen")
		var shut_doors := _count_named(_fx.chunk, "UnitDoorShut")
		assert_true(open_doors + shut_doors >= 1, "the corridor's T slots hang doors beside their trays")
		if truth == RunState.Truth.HOLDS:
			assert_eq(shut_doors, 0, "HOLDS: no shut door beside a tray")
		else:
			assert_eq(open_doors, 0, "INVERTED: no open door beside a tray")
		g.free()
		_fx.dispose()
		_fx = null
