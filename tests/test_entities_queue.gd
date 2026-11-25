extends TestCase
## The Queue (SPEC 6.4, B1 Blue Annex): the tell lead, the ticket for BOTH variants (HOLDS: a place and a call;
## INVERTED: a claim that draws the line in), the chime window, the not-staff / take_number Clause rules and the P2
## evidence (ticket stubs ahead of / behind the line).

const EXAM := &"blu_exam_queue_corridor"
const LEAD := 4.6

var _fx: CrowdFixture = null
var _snap: Dictionary = {}


func before_each() -> void:
	_snap = {"clause": RunState.clause, "void": RunState.clause_void, "nerve": RunState.nerve, "truths": RunState.truths.duplicate()}


func after_each() -> void:
	if _fx != null and is_instance_valid(_fx):
		_fx.dispose()
	_fx = null
	RunState.clause = _snap["clause"]
	RunState.clause_void = _snap["void"]
	RunState.truths = _snap["truths"]
	RunState.set_nerve(_snap["nerve"])


func _room(truth: int, chunk_id: StringName = EXAM) -> QueueLine:
	_fx = CrowdFixture.create(tree.root, &"blue", chunk_id, truth)
	RunState.set_nerve(RunState.nerve_max)
	var q := QueueLine.new()
	q.manual = true
	_fx.add_entity(q)
	return q


func _live(truth: int) -> QueueLine:
	var q := _room(truth)
	assert_true(q.tell(LEAD, _fx.chunk), "the tell starts in the exam corridor")
	q.begin_encounter(_fx.chunk, &"major", q.encounter_duration(&"major", 60.0))
	_fx.put_player(q.wait_pos, 0.0)
	return q


func _run(q: QueueLine, seconds: float, dt: float = 0.25) -> void:
	var t := 0.0
	while t < seconds and q.mode != QueueLine.Mode.DONE:
		q.step(dt)
		t += dt


# --- identity / tell ---------------------------------------------------------------------------

func test_identity_and_factory() -> void:
	var q := QueueLine.new()
	assert_eq(q.entity_id, &"queue")
	assert_false(q.is_staff, "the Queue is NOT staff: no Clause binds it (a deliberate gap)")
	q.free()
	assert_true(EntityFactory.available(&"queue"))
	var made := EntityFactory.create(&"queue")
	assert_true(made is QueueLine)
	if made != null:
		made.free()


func test_tell_lasts_at_least_four_seconds_and_shows_the_line_and_the_board() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var q := _room(truth)
		assert_true(q.tell(LEAD, _fx.chunk))
		assert_true(q.tell_lead >= 4.0, "the genuine tell leads by >= 4 s")
		assert_true(q.figures.size() >= QueueLine.MIN_FIGURES, "a line of figures")
		assert_not_null(q.board, "the NOW SERVING board wakes during the tell")
		assert_eq(q.board.glitchy, truth == RunState.Truth.INVERTED, "the board's face is the variant's honest tell")
		# the figures appear one by one over the lead, the tail (nearest) last
		var last_appear := 0.0
		for f in q.figures:
			last_appear = maxf(last_appear, f.appear_at)
		assert_true(last_appear <= q.tell_lead and last_appear > 1.0, "the line fades in over the tell")
		_fx.dispose()
		_fx = null


func test_it_also_works_as_a_minor_in_a_plain_corridor() -> void:
	_fx = CrowdFixture.create(tree.root, &"blue", &"blu_choice_bench_corridor", RunState.Truth.HOLDS, &"choice")
	var q := QueueLine.new()
	q.manual = true
	_fx.add_entity(q)
	if not q.can_exist_in(_fx.chunk):
		return                           # this room has no straight wall-hugging run: another one will host it
	assert_true(q.tell(LEAD, _fx.chunk), "a minor plans its own line, dispenser and board")
	assert_not_null(q.board)
	assert_not_null(q.dispenser)
	q.begin_encounter(_fx.chunk, &"minor", q.encounter_duration(&"minor", 38.0))
	assert_true(q.active)
	assert_eq(q.encounter_duration(&"minor", 38.0), CrowdTuning.load_default().queue_minor_duration)


# --- the ticket --------------------------------------------------------------------------------

func test_holds_a_ticket_is_a_place_and_the_number_is_called() -> void:
	var q := _live(RunState.Truth.HOLDS)
	var it := q.dispenser_it
	assert_not_null(it, "the dispenser is live in the encounter")
	assert_true(it.available(_fx.player))
	it.do_tap(_fx.player)
	assert_true(q.ticket >= 1 and q.ticket < q.board_value, "a number behind the one being served")
	_run(q, 220.0)
	assert_true(q.called, "HOLDS: waiting in the line gets the number called")
	assert_eq(q.lurches, 0, "HOLDS: the line never steps toward a waiting guest")
	assert_true(_fx.session.hits.is_empty(), "HOLDS: waiting is safe")
	var opened := false
	for e in StaffKit.chunk_doors(_fx.session, _fx.chunk):
		opened = opened or not (e["door"] as Door).is_closed()
	assert_true(opened, "HOLDS: the window door opens when the number is called")


func test_holds_leaving_the_line_turns_every_head_and_costs_one_segment() -> void:
	var q := _live(RunState.Truth.HOLDS)
	q.take_ticket()
	_run(q, 2.0)
	var out := q.wait_pos + Vector3(0, 0, 0)
	var field: Dictionary = _fx.session.grid.distance_field(GameScale.world_to_tile(q.wait_pos), 30)
	var far_tile := GameScale.world_to_tile(q.wait_pos)
	for t: Vector2i in field:
		if int(field[t]) >= 6 and int(field[t]) <= 9 and _fx.chunk.world_open.has(t):
			far_tile = t
			break
	out = GameScale.tile_to_world(far_tile)
	_fx.put_player(out, 0.0)
	_run(q, 120.0)
	assert_true(q.alerts >= 1, "HOLDS: leaving the line turns every head")
	assert_true(RunState.nerve > 0, "never lethal at full Nerve")
	if not _fx.session.hits.is_empty():
		assert_eq(RunState.nerve, RunState.nerve_max - 1, "one warning, not a blackout")


func test_inverted_a_ticket_is_a_claim_and_each_tick_the_line_steps_in() -> void:
	var q := _live(RunState.Truth.INVERTED)
	q.take_ticket()
	assert_true(q.ticket >= 1)
	_run(q, 21.0)
	assert_eq(q.tick_count, 1, "the board counted once")
	assert_eq(q.lurches, 1, "INVERTED: every count the whole line steps toward the ticket-holder")
	_run(q, 260.0)
	assert_true(q.lurches >= 3, "and again every count")
	assert_false(q.called, "INVERTED: the number is never honoured")
	assert_true(RunState.nerve > 0, "never lethal at full Nerve")
	assert_true(_fx.session.hits.size() <= 1 or RunState.nerve >= 1)


func test_inverted_no_ticket_means_the_line_stays_put() -> void:
	var q := _live(RunState.Truth.INVERTED)
	_run(q, 85.0)
	assert_true(q.tick_count >= 3, "the board counts on")
	assert_eq(q.lurches, 0, "INVERTED: with no number there is nothing to claim")
	assert_true(_fx.session.hits.is_empty(), "taking no number is safe")


func test_the_chime_window_lets_a_guest_slip_along_the_line_only_in_inverted() -> void:
	# a guest moving about near the line, outside the waiting spot: noise draws the heads, except in the 3 s chime
	# window of the INVERTED line, when every face is turned to the board
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var q := _live(truth)
		var spot := q.wait_pos
		var field: Dictionary = _fx.session.grid.distance_field(GameScale.world_to_tile(q.wait_pos), 20)
		for t: Vector2i in field:
			var d := int(field[t])
			if d >= 5 and d <= 7 and _fx.chunk.world_open.has(t):
				spot = GameScale.tile_to_world(t)
				break
		_fx.put_player(spot, 0.0)
		_fx.player.velocity = Vector3(2.0, 0.0, 0.0)
		# outside the window: suspicion rises (both variants)
		q.chime_left = 0.0
		q.tick_t = 99.0
		q.suspicion = 0.0
		q.step(0.5)
		var outside := q.suspicion
		assert_true(outside > 0.0, "outside the chime, moving beside the line draws attention (truth %d)" % truth)
		# inside the window
		q.suspicion = 0.0
		q.chime_left = 3.0
		q.step(0.5)
		if truth == RunState.Truth.INVERTED:
			assert_eq(q.suspicion, 0.0, "INVERTED: in the chime window every face is on the board")
		else:
			assert_true(q.suspicion > 0.0, "HOLDS: the chime hides nothing")
		_fx.dispose()
		_fx = null


func test_stand_down_completes_and_the_door_to_the_window_can_be_left() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var q := _live(truth)
		_run(q, 5.0)
		q.stand_down()
		assert_false(q.active, "the encounter ends")
		assert_eq(q.mode, QueueLine.Mode.DONE)
		assert_false(_fx.player.nerve.in_danger, "Nerve regen resumes")
		_fx.dispose()
		_fx = null


# --- Clause: take_number -----------------------------------------------------------------------

func test_take_number_clause_serves_one_pursuer_at_a_time() -> void:
	var q := _live(RunState.Truth.INVERTED)
	RunState.clause = &"take_number"
	RunState.clause_void = false
	var other := EntityBase.new()
	other.setup(_fx.session, 0)
	_fx.stage.actors_root.add_child(other)
	other.active = true
	assert_true(_fx.session.clauses.claim_pursuit(other), "another entity is already pursuing the guest")
	q.take_ticket()
	_run(q, 45.0)
	assert_true(q.tick_count >= 2)
	assert_eq(q.lurches, 0, "take_number: the line waits its turn while another entity pursues")
	_fx.session.clauses.release_pursuit(other)
	_run(q, 25.0)
	assert_true(q.lurches >= 1, "and steps in once the other is done")
	other.queue_free()


# --- evidence ----------------------------------------------------------------------------------

func _marks(root: Node, id: StringName) -> Array[EvidenceMark]:
	var out: Array[EvidenceMark] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is EvidenceMark and (n as EvidenceMark).def != null and (n as EvidenceMark).def.id == id:
			out.append(n)
		stack.append_array(n.get_children())
	return out


func _evidence(id: StringName) -> EvidenceDef:
	for e: EvidenceDef in FloorCatalog.get_def(&"blue").evidence:
		if e.id == id:
			return e
	return null


func test_stubs_recipe_places_only_the_variant_that_is_true_and_ahead_vs_behind() -> void:
	ChunkLibrary.reload()
	var hosts := 0
	for spec in ChunkLibrary.pool(&"blue", &"choice") + ChunkLibrary.pool(&"blue", &"long"):
		var eh := _evidence(&"blue_stubs_h")
		var ei := _evidence(&"blue_stubs_i")
		if not StubsRecipe.can_host(spec, eh):
			continue
		hosts += 1
		var cs: Array[Vector3] = []
		for e in [eh, ei]:
			var chunk := ChunkBuilder.build(spec, Themes.get_theme(&"blue"), 0, Vector2i.ZERO, 7)
			tree.root.add_child(chunk)
			var rng := RandomNumberGenerator.new()
			rng.seed = 4242                              # the same run and guide direction for both variants
			EvidenceRecipes.place(chunk, e, rng, null)
			var marks := _marks(chunk, e.id)
			assert_true(marks.size() >= 3, "%s: %s places at least 3 stub clusters" % [spec.id, e.id])
			var other := _marks(chunk, &"blue_stubs_i" if e.id == &"blue_stubs_h" else &"blue_stubs_h")
			assert_true(other.is_empty(), "%s: never the other variant's mark in the same room" % spec.id)
			var sum := Vector3.ZERO
			for m in marks:
				sum += m.position
			cs.append(sum / float(marks.size()))
			tree.root.remove_child(chunk)
			chunk.free()
		assert_true(cs[0].distance_to(cs[1]) >= GameScale.TILE * 1.5, "%s: ahead of the line and behind it are different ends of the guide" % spec.id)
	assert_true(hosts >= 2, "several blue rooms can host the stubs (%d)" % hosts)
