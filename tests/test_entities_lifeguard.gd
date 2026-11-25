extends TestCase
## The Lifeguard (SPEC 6.3, B2 Natatorium): pure rules (tell lead, whistle pitch, freeze / stalk rules), the flooded
## rooms and drain grates he works with, and his P2 evidence recipes placed on every room that can host them.

const LEAD := 4.6                     ## DirectorTuning.tell_lead_seconds (4.0) + the Director's 0.6 s


func _evidence(id: StringName) -> EvidenceDef:
	for e: EvidenceDef in FloorCatalog.get_def(&"natatorium").evidence:
		if e.id == id:
			return e
	return null


func _specs() -> Array[ChunkSpec]:
	ChunkLibrary.reload()
	var out: Array[ChunkSpec] = []
	for beat in PoolSite.WET_BEATS:
		for s in ChunkLibrary.pool(&"natatorium", beat):
			if not out.has(s):
				out.append(s)
	return out


func _wet_specs() -> Array[ChunkSpec]:
	var out: Array[ChunkSpec] = []
	for s in _specs():
		if PoolSite.has_pool(s):
			out.append(s)
	return out


func _build(spec: ChunkSpec, uid: int = 1) -> Chunk:
	return ChunkBuilder.build(spec, Themes.get_theme(&"natatorium"), 0, Vector2i.ZERO, uid)


func _marks(root: Node, id: StringName) -> Array[EvidenceMark]:
	var out: Array[EvidenceMark] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is EvidenceMark and (n as EvidenceMark).def != null and (n as EvidenceMark).def.id == id:
			out.append(n)
		stack.append_array(n.get_children())
	return out


# --- identity -------------------------------------------------------------------------------

func test_identity_and_factory() -> void:
	var l := Lifeguard.new()
	assert_eq(l.entity_id, &"lifeguard")
	assert_true(l.is_staff, "the Lifeguard is staff: the Clauses bind him")
	l.free()
	assert_true(EntityFactory.available(&"lifeguard"))
	var made := EntityFactory.create(&"lifeguard")
	assert_true(made is Lifeguard, "factory builds a Lifeguard")
	if made != null:
		made.free()


# --- pure rules -----------------------------------------------------------------------------

func test_tell_lasts_at_least_four_seconds_for_both_truths() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var cue: Dictionary = {}
		for e in Lifeguard.tell_events(truth, LEAD):
			assert_true(float(e["t"]) >= 0.0 and float(e["t"]) + float(e["dur"]) <= LEAD + 0.001, "%s stays inside the lead" % e["kind"])
			if e["kind"] == &"calm" or e["kind"] == &"ripple":
				cue = e
		assert_false(cue.is_empty(), "the water always shows the truth")
		assert_near(float(cue["t"]), 0.0, 0.0001, "the water cue starts with the tell")
		assert_true(float(cue["dur"]) >= 4.0, "the water foretells the hazard for >= 4 s (Doctrine 2)")


func test_water_shows_calm_for_holds_and_ripples_for_inverted() -> void:
	var holds := Lifeguard.tell_events(RunState.Truth.HOLDS, LEAD).map(func(e): return e["kind"])
	var inv := Lifeguard.tell_events(RunState.Truth.INVERTED, LEAD).map(func(e): return e["kind"])
	assert_true(holds.has(&"calm") and not holds.has(&"ripple"), "HOLDS: glassy water")
	assert_true(inv.has(&"ripple") and not inv.has(&"calm"), "INVERTED: rings travel toward the guest")
	assert_true(holds.has(&"chirp") and inv.has(&"chirp"), "both truths chirp the whistle in the tell")


func test_whistle_pitch_gives_the_lie_away() -> void:
	var honest := Lifeguard.whistle_pitch(RunState.Truth.HOLDS)
	var lying := Lifeguard.whistle_pitch(RunState.Truth.INVERTED)
	assert_near(honest, 1.0, 0.0001, "the honest whistle is clean")
	assert_lt(lying, honest - 0.1, "the lying whistle is audibly flat")
	assert_near(Lifeguard.whistle_pitch(RunState.Truth.INVERTED, 0.7), 0.7, 0.0001, "the ratio is tunable")


func test_freeze_rules_holds() -> void:
	var still := 0.35
	var grace := 0.7
	assert_false(Lifeguard.moved_during_freeze(3.0, 0.3, false, still, grace), "within the grace you may still be slowing")
	assert_true(Lifeguard.moved_during_freeze(3.0, 1.0, false, still, grace), "moving after the grace broke the freeze")
	assert_false(Lifeguard.moved_during_freeze(0.1, 5.0, false, still, grace), "standing still is obeying")
	assert_false(Lifeguard.moved_during_freeze(3.0, 5.0, true, still, grace), "a hidden guest is not watched")


func test_stalk_rules_inverted() -> void:
	var still := 0.35
	var delay := 0.8
	assert_true(Lifeguard.is_still(0.0, false, still))
	assert_false(Lifeguard.is_still(2.0, false, still), "moving is not standing still")
	assert_false(Lifeguard.is_still(0.0, true, still), "a hidden guest is not 'standing there'")
	assert_false(Lifeguard.advances(0.2, 0.0, delay), "he waits for the guest to be properly still")
	assert_true(Lifeguard.advances(1.0, 0.0, delay), "still guest: he walks")
	assert_false(Lifeguard.advances(5.0, 1.0, delay), "a hidden guest is not stalked")


func test_lifeguard_cannot_exist_in_dry_rooms() -> void:
	var l := Lifeguard.new()
	var wet := 0
	var dry := 0
	for s in _specs():
		var chunk := _build(s)
		if PoolSite.has_pool(s):
			wet += 1
			assert_true(l.can_exist_in(chunk), "%s: wet room" % s.id)
		else:
			dry += 1
			assert_false(l.can_exist_in(chunk), "%s: dry room" % s.id)
		chunk.free()
	assert_gt(float(wet), 0.0, "some natatorium room is flooded")
	l.free()


# --- pool dressing --------------------------------------------------------------------------

func test_water_tiles_leave_a_dry_deck() -> void:
	for spec in _specs():
		var tiles := PoolSite.water_tiles(spec)
		if tiles.is_empty():
			continue
		assert_gte_size(tiles.size(), PoolSite.MIN_WATER, "%s: a pool is not a puddle" % spec.id)
		var slot_tiles := {}
		for sl: ChunkSpec.SlotDef in spec.slots:
			slot_tiles[sl.tile] = true
		for t in tiles:
			assert_false(slot_tiles.has(t), "%s: no water under a prop slot" % spec.id)
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var n: Vector2i = t + Vector2i(dx, dy)
					assert_true(spec.open.has(n) or spec.pillars.has(n), "%s: water keeps a tile from the wall" % spec.id)
		for tag in PoolSite.DRY_TAGS:
			assert_false(spec.tags.has(tag), "%s: %s rooms stay dry" % [spec.id, tag])


func assert_gte_size(n: int, minimum: int, msg: String) -> void:
	assert_true(n >= minimum, "%s (%d < %d)" % [msg, n, minimum])


func test_grates_are_picked_from_the_water() -> void:
	for spec in _wet_specs():
		var tiles := PoolSite.water_tiles(spec)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var grates := PoolSite.pick_grates(tiles, rng)
		assert_true(grates.size() >= 1 and grates.size() <= PoolSite.MAX_GRATES, "%s: 1..%d grates" % [spec.id, PoolSite.MAX_GRATES])
		for g in grates:
			assert_true(tiles.has(g), "%s: a grate sits in the water" % spec.id)


func test_ensure_floods_a_room_once_and_finds_the_nearest_grate() -> void:
	for spec in _wet_specs():
		var chunk := _build(spec)
		var a := PoolSite.ensure(chunk, null)
		var b := PoolSite.ensure(chunk, null)
		assert_false(a.is_empty(), "%s: a pool" % spec.id)
		assert_true(a == b, "%s: built once" % spec.id)
		assert_gt(float((a["water"] as Dictionary).size()), 0.0, "%s: world-tile water set" % spec.id)
		var g: Vector3 = a["grates"][0]
		assert_true(PoolSite.nearest_grate(chunk, g + Vector3(0.2, 0, 0.1)).is_equal_approx(g), "%s: nearest grate is the one underfoot" % spec.id)
		assert_eq(PoolSite.nearest_grate(null, Vector3.ZERO), Vector3.INF, "no chunk, no grate")
		chunk.free()
		return
	assert_true(false, "no wet room to test")


func test_water_material_carries_the_tell_uniforms() -> void:
	var m := PoolSite.material()
	assert_true(m is ShaderMaterial)
	PoolSite.set_ripple(0.8, 0.0, Vector3(3, 0, 4))
	assert_near(float(m.get_shader_parameter("ripple_amp")), 0.8, 0.0001)
	assert_near(float(m.get_shader_parameter("calm")), 0.0, 0.0001)
	PoolSite.set_ripple(0.0, 1.0, Vector3.ZERO)
	assert_near(float(m.get_shader_parameter("ripple_amp")), 0.0, 0.0001, "calm: no rings")
	assert_near(float(m.get_shader_parameter("calm")), 1.0, 0.0001, "calm: glassy")
	PoolSite.set_ripple(0.0, 0.0, Vector3.ZERO)
	assert_true(PoolSite.material() == m, "one shared material (MaterialLibrary pushes the light field into it)")


# --- evidence recipes -----------------------------------------------------------------------

func test_drain_scratch_recipe_marks_the_grates() -> void:
	var e := _evidence(&"natatorium_ripple_h")
	assert_not_null(e, "ripple_h exists")
	assert_eq(e.variant, RunState.Truth.HOLDS, "drain scratches are HOLDS evidence")
	var hosts := 0
	for spec in _specs():
		if not EvidenceRecipes.can_host(spec, e):
			continue
		hosts += 1
		var chunk := _build(spec)
		EvidenceRecipes.place(chunk, e, RandomNumberGenerator.new(), null)
		var marks := _marks(chunk, &"natatorium_ripple_h")
		var grates: Array = PoolSite.pool_of(chunk).get("grate_nodes", [])
		assert_gt(float(marks.size()), 0.0, "%s: scratches on the grates" % spec.id)
		assert_eq(marks.size(), grates.size(), "%s: one scored mark per grate" % spec.id)
		for m in marks:
			assert_eq(m.def.variant, RunState.Truth.HOLDS)
		chunk.free()
	assert_gt(float(hosts), 0.0, "some natatorium room hosts drain scratches")


func test_wet_prints_recipe_marks_the_deck() -> void:
	var e := _evidence(&"natatorium_foot_i")
	assert_not_null(e, "foot_i exists")
	assert_eq(e.variant, RunState.Truth.INVERTED, "wet prints are INVERTED evidence")
	var hosts := 0
	for spec in _specs():
		if not EvidenceRecipes.can_host(spec, e):
			continue
		hosts += 1
		var chunk := _build(spec)
		EvidenceRecipes.place(chunk, e, RandomNumberGenerator.new(), null)
		var marks := _marks(chunk, &"natatorium_foot_i")
		assert_gt(float(marks.size()), 0.0, "%s: wet prints placed" % spec.id)
		for m in marks:
			assert_eq(m.def.variant, RunState.Truth.INVERTED)
		chunk.free()
	assert_gt(float(hosts), 0.0, "some natatorium room hosts wet prints")


func test_only_the_active_variant_gets_marks() -> void:
	## The wrong-variant recipe is simply never asked to place, but flooding a room must not leave stray evidence.
	for spec in _wet_specs():
		var chunk := _build(spec)
		PoolSite.ensure(chunk, null)
		assert_eq(_marks(chunk, &"natatorium_ripple_h").size(), 0, "%s: flooding places no HOLDS evidence" % spec.id)
		assert_eq(_marks(chunk, &"natatorium_foot_i").size(), 0, "%s: flooding places no INVERTED evidence" % spec.id)
		chunk.free()
		return


func test_recipes_are_deterministic_from_the_rng() -> void:
	var e := _evidence(&"natatorium_foot_i")
	for spec in _wet_specs():
		var counts: Array[int] = []
		for i in 2:
			var chunk := _build(spec, 9)
			var rng := RandomNumberGenerator.new()
			rng.seed = 777
			EvidenceRecipes.place(chunk, e, rng, null)
			counts.append(_marks(chunk, &"natatorium_foot_i").size())
			chunk.free()
		assert_eq(counts[0], counts[1], "%s: same seed, same prints" % spec.id)
		return
