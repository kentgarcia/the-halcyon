extends TestCase
## Management / The Audit (SPEC 6.7, Lobby): the tell lead, the five compressed checks for BOTH variants, the order
## learned, Clause hooks, the Nerve cost, and the desk with its three endings (Burn the Card is gated).

const HALL := &"lob_exam_audit_hall"
const BOARDROOM := &"lob_exam_boardroom"
const LEAD := 4.6                     ## DirectorTuning.tell_lead_seconds (4.0) + the Director's 0.6 s

var _snap: Dictionary = {}
var _fx: CrowdFixture = null


func before_each() -> void:
	_snap = {
		"cleared": RunState.cleared_floors.duplicate(), "truths": RunState.truths.duplicate(),
		"marks": RunState.entity_mark_ok.duplicate(), "clause": RunState.clause, "void": RunState.clause_void,
		"nerve": RunState.nerve, "max": RunState.nerve_max,
	}


func after_each() -> void:
	if _fx != null and is_instance_valid(_fx):
		_fx.dispose()
	_fx = null
	RunState.cleared_floors.assign(_snap["cleared"])
	RunState.truths = _snap["truths"]
	RunState.entity_mark_ok = _snap["marks"]
	RunState.clause = _snap["clause"]
	RunState.clause_void = _snap["void"]
	RunState.nerve_max = _snap["max"]
	RunState.set_nerve(_snap["nerve"])


func _hall(truth: int = RunState.Truth.HOLDS, chunk_id: StringName = HALL) -> CrowdFixture:
	_fx = CrowdFixture.create(tree.root, &"lobby", chunk_id, truth)
	RunState.set_nerve(RunState.nerve_max)
	return _fx


func _audit(fx: CrowdFixture) -> LobbyAudit:
	var a := LobbyAudit.new()
	a.manual = true
	fx.add_entity(a)
	a.ending_hook = func(e: StringName) -> void: pass
	return a


func _check(fx: CrowdFixture, floor_id: StringName, truth: int) -> AuditChecks.Check:
	var crowd := CrowdTuning.load_default()
	var c := AuditChecks.make(floor_id, truth, fx.session, crowd)
	var anchors := fx.anchors()
	c.build(fx.chunk, anchors[1].global_position)
	c.reveal()
	return c


func _run(c: AuditChecks.Check, seconds: float, guest: Vector3, speed: float = 0.0, dt: float = 0.1) -> void:
	var t := 0.0
	while t < seconds and c.state == AuditChecks.State.RUNNING:
		c.step(dt, guest, speed)
		t += dt


# --- identity / ids ----------------------------------------------------------------------------

func test_identity_and_factory() -> void:
	var a := LobbyAudit.new()
	assert_eq(a.entity_id, &"audit")
	assert_true(a.is_staff, "Management is staff: the Clauses bind it")
	a.free()
	assert_true(EntityFactory.available(&"audit"))
	assert_true(EntityFactory.available(&"management"), "the Lobby floor def names its entity management")
	var made := EntityFactory.create(FloorCatalog.get_def(&"lobby").entity_id)
	assert_true(made is LobbyAudit, "the Lobby's entity is the Audit")
	if made != null:
		made.free()


func test_every_pa_line_the_audit_says_exists() -> void:
	var pa: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/pa_lines.json"))
	var ids := {}
	for l in (pa as Dictionary).get("lines", []):
		ids[String((l as Dictionary).get("id", ""))] = true
	var re := RegEx.new()
	re.compile("_say\\(&\"([a-z0-9_]+)\"")
	for path in ["res://entities/lobby_audit.gd"]:
		for r in re.search_all(FileAccess.get_file_as_string(path)):
			assert_true(ids.has(r.get_string(1)), "%s says '%s' which is not in pa_lines.json" % [path, r.get_string(1)])
	for def in FloorCatalog.clause_defs():
		assert_true(ids.has("audit_clause_%s" % def.id), "no readback line for Clause %s" % def.id)
	for f in AuditChecks.ORDER:
		assert_true(ids.has(String(AuditChecks.rule_line_id(f))), "no rule line for %s" % f)
	for id in ["audit_open", "audit_checkout", "audit_desk", "audit_burn"]:
		assert_true(ids.has(id), id)


# --- the checks: both truths, right and wrong play --------------------------------------------

func test_run_check_both_truths() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var fx := _hall(truth)
		var c: AuditChecks.RunCheck = _check(fx, &"boiler", truth)
		# right play
		c.begin()
		if truth == RunState.Truth.HOLDS:
			_run(c, 3.0, c.exit_pos)
			assert_eq(c.state, AuditChecks.State.PASSED, "HOLDS: reaching the exit passes")
		else:
			_run(c, 40.0, c.station)
			assert_eq(c.state, AuditChecks.State.PASSED, "INVERTED: staying clear passes")
			assert_not_null(c.foreman, "INVERTED: a Foreman stands on the exit, in plain view")
		# wrong play
		c.rearm()
		c.begin()
		if truth == RunState.Truth.HOLDS:
			_run(c, 40.0, c.station)
			assert_eq(c.state, AuditChecks.State.FAILED, "HOLDS: never leaving fails")
			assert_null(c.foreman, "HOLDS: nobody on the exit")
		else:
			_run(c, 3.0, c.exit_pos)
			assert_eq(c.state, AuditChecks.State.FAILED, "INVERTED: walking into the Foreman fails")
		c.teardown()
		fx.dispose()
		_fx = null


func test_freeze_check_both_truths() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var fx := _hall(truth)
		var c: AuditChecks.FreezeCheck = _check(fx, &"natatorium", truth)
		var here := c.station
		c.begin()
		if truth == RunState.Truth.HOLDS:
			_run(c, 12.0, here, 0.0)
			assert_eq(c.state, AuditChecks.State.PASSED, "HOLDS: standing still through the whistle passes")
			assert_not_null(c.chair_figure, "HOLDS: the lifeguard stays in the chair")
			c.rearm()
			c.begin()
			_run(c, 2.2, here, 0.0)                          # whistle at 1.0, the reaction grace is over by 1.8
			_run(c, 3.0, here + Vector3(2.0, 0, 0), 3.0)
			assert_eq(c.state, AuditChecks.State.FAILED, "HOLDS: moving on the whistle fails")
			c.rearm()
			c.begin()
			_run(c, 1.05, here, 0.0)
			_run(c, 0.4, here + Vector3(0.8, 0, 0), 2.0)       # still coming to a stop when the whistle blew
			_run(c, 12.0, here + Vector3(0.8, 0, 0), 0.0)
			assert_eq(c.state, AuditChecks.State.PASSED, "HOLDS: a guest who was walking gets a moment to stop")
		else:
			assert_null(c.chair_figure, "INVERTED: the chair is empty")
			assert_not_null(c.walker, "INVERTED: he is on foot")
			var p := here
			var t := 0.0
			while t < 14.0 and c.state == AuditChecks.State.RUNNING:
				p += Vector3(0.0, 0.0, 0.3 if int(t * 2.0) % 2 == 0 else -0.3)
				c.step(0.1, p, 3.0)
				t += 0.1
			assert_eq(c.state, AuditChecks.State.PASSED, "INVERTED: keeping moving passes")
			c.rearm()
			c.begin()
			_run(c, 30.0, here, 0.0)
			assert_eq(c.state, AuditChecks.State.FAILED, "INVERTED: standing still is seen")
		c.teardown()
		fx.dispose()
		_fx = null


func test_wait_check_both_truths() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var fx := _hall(truth)
		var c: AuditChecks.WaitCheck = _check(fx, &"blue", truth)
		c.begin()
		c.take_number()
		if truth == RunState.Truth.HOLDS:
			_run(c, 40.0, c.station)
			assert_eq(c.state, AuditChecks.State.PASSED, "HOLDS: a number and a wait passes")
			assert_true(c.called, "HOLDS: the number is called")
			c.rearm()
			c.begin()
			c.take_number()
			_run(c, 3.0, c.station + Vector3(9.0, 0, 0))
			assert_eq(c.state, AuditChecks.State.FAILED, "HOLDS: leaving the line fails")
			c.rearm()
			c.begin()
			_run(c, 40.0, c.station)
			assert_eq(c.state, AuditChecks.State.FAILED, "HOLDS: never taking a number fails")
		else:
			assert_eq(c.state, AuditChecks.State.FAILED, "INVERTED: a ticket is a claim: taking one fails")
			c.rearm()
			c.begin()
			_run(c, 40.0, c.station)
			assert_eq(c.state, AuditChecks.State.PASSED, "INVERTED: taking none passes")
			assert_eq(c.ticket, -1)
		c.teardown()
		fx.dispose()
		_fx = null


func test_light_check_both_truths() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var fx := _hall(truth)
		var c: AuditChecks.LightCheck = _check(fx, &"yellow", truth)
		var good := c.lit_pos if truth == RunState.Truth.HOLDS else c.dark_pos
		var bad := c.dark_pos if truth == RunState.Truth.HOLDS else c.lit_pos
		c.begin()
		_run(c, 30.0, good)
		assert_eq(c.state, AuditChecks.State.PASSED, "standing on the right pad passes (truth %d)" % truth)
		c.rearm()
		c.begin()
		_run(c, 30.0, bad)
		assert_eq(c.state, AuditChecks.State.FAILED, "standing on the wrong pad fails (truth %d)" % truth)
		assert_eq(c.reason, &"wrong_pad")
		c.rearm()
		c.begin()
		_run(c, 40.0, c.station)
		assert_eq(c.state, AuditChecks.State.FAILED, "standing on neither runs the clock out (truth %d)" % truth)
		c.teardown()
		fx.dispose()
		_fx = null


func test_answer_check_both_truths() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		var fx := _hall(truth)
		var c: AuditChecks.AnswerCheck = _check(fx, &"units", truth)
		c.begin()
		c.answer()
		assert_eq(c.state, AuditChecks.State.PASSED if truth == RunState.Truth.HOLDS else AuditChecks.State.FAILED,
			"answering %s (truth %d)" % ["passes" if truth == RunState.Truth.HOLDS else "fails", truth])
		c.rearm()
		c.begin()
		_run(c, 40.0, c.station)
		assert_eq(c.state, AuditChecks.State.FAILED if truth == RunState.Truth.HOLDS else AuditChecks.State.PASSED,
			"ignoring %s (truth %d)" % ["fails" if truth == RunState.Truth.HOLDS else "passes", truth])
		c.teardown()
		fx.dispose()
		_fx = null


func test_staff_knock_clause_makes_the_bellhop_knock_first() -> void:
	var fx := _hall(RunState.Truth.HOLDS)
	var audit := _audit(fx)
	RunState.clause = &"staff_knock"
	RunState.clause_void = false
	var c: AuditChecks.AnswerCheck = _check(fx, &"units", RunState.Truth.HOLDS)
	c.audit = audit
	c.begin()
	c.answer()
	assert_eq(c.state, AuditChecks.State.RUNNING, "under staff_knock the door is not opened at once")
	_run(c, 2.0, c.station)
	assert_eq(c.state, AuditChecks.State.RUNNING, "still knocking after 2 s")
	_run(c, 4.0, c.station)
	assert_eq(c.state, AuditChecks.State.PASSED, "the door opens after ~5 s of knocks")
	assert_eq(c.knocks_made, 3, "three knocks")
	c.teardown()


# --- the whole Audit ---------------------------------------------------------------------------

func _drive_perfect(a: LobbyAudit, fx: CrowdFixture, max_steps: int = 6000) -> void:
	## A guest who always plays each check correctly for its variant.
	var steps := 0
	while a.mode != LobbyAudit.Mode.DESK and a.mode != LobbyAudit.Mode.ENDED and steps < max_steps:
		steps += 1
		var c := a.current_check()
		if c != null and a.mode == LobbyAudit.Mode.CHECKS:
			var at := c.station
			var speed := 0.0
			if c is AuditChecks.RunCheck and c.state == AuditChecks.State.RUNNING and c.holds():
				at = (c as AuditChecks.RunCheck).exit_pos
			elif c is AuditChecks.LightCheck and c.state == AuditChecks.State.RUNNING:
				at = (c as AuditChecks.LightCheck).lit_pos if c.holds() else (c as AuditChecks.LightCheck).dark_pos
			elif c is AuditChecks.FreezeCheck and c.state == AuditChecks.State.RUNNING and not c.holds():
				at = c.station + Vector3(0, 0, 0.3 if (steps / 5) % 2 == 0 else -0.3)
				speed = 3.0
			fx.player.global_position = at
			fx.player.velocity = Vector3(speed, 0, 0)
			if c.state == AuditChecks.State.RUNNING:
				if c is AuditChecks.WaitCheck and c.holds() and (c as AuditChecks.WaitCheck).ticket < 0:
					(c as AuditChecks.WaitCheck).take_number()
				elif c is AuditChecks.AnswerCheck and c.holds():
					(c as AuditChecks.AnswerCheck).answer()
		a.step(0.1)


func test_tell_lead_and_order_learned() -> void:
	RunState.cleared_floors.assign([&"natatorium", &"boiler", &"units", &"yellow", &"blue"] as Array[StringName])
	RunState.truths = {&"natatorium": 1, &"boiler": 0, &"units": 1, &"yellow": 0, &"blue": 1}
	var fx := _hall()
	var a := _audit(fx)
	assert_eq(a.audit_order(), [&"natatorium", &"boiler", &"units", &"yellow", &"blue"] as Array[StringName], "the order learned")
	assert_true(a.can_exist_in(fx.chunk), "the audit hall can host it")
	assert_true(a.tell(LEAD, fx.chunk), "the tell starts in the exam hall")
	assert_true(a.tell_lead >= 4.0, "the genuine tell leads by >= 4 s")
	assert_eq(a.checks.size(), 5, "five checks")
	var got: Array[StringName] = []
	for c in a.checks:
		got.append(c.floor_id)
	assert_eq(got, [&"natatorium", &"boiler", &"units", &"yellow", &"blue"] as Array[StringName], "checks follow the order learned")
	for c in a.checks:
		assert_eq(c.truth, RunState.entity_truth(c.floor_id), "%s runs with the variant it rolled" % c.floor_id)
	# stations run from the entrance to the desk; the desk is the farthest anchor
	var entry: Vector2i = fx.chunk.entry_world[0]["tile"]
	var field: Dictionary = fx.session.grid.distance_field(entry, 120)
	var last := -1
	for c in a.checks:
		var d := int(field.get(GameScale.world_to_tile(c.station), 9999))
		assert_true(d >= last, "stations are ordered away from the entrance")
		last = d
	assert_true(int(field.get(GameScale.world_to_tile(a.desk_pos), 0)) >= last, "the desk is the farthest anchor")
	var other := _hall(RunState.Truth.HOLDS, BOARDROOM)
	var b := _audit(other)
	assert_true(b.can_exist_in(other.chunk), "the boardroom variant can host it too")
	assert_true(b.tell(LEAD, other.chunk))
	assert_eq(b.checks.size(), 5)


func test_a_floor_not_yet_learned_is_not_audited() -> void:
	RunState.cleared_floors.assign([&"boiler", &"blue"] as Array[StringName])
	var fx := _hall()
	var a := _audit(fx)
	assert_true(a.tell(LEAD, fx.chunk))
	assert_eq(a.checks.size(), 2, "only what the guest learned is audited")


func test_perfect_guest_reaches_the_desk_without_losing_nerve() -> void:
	for truth in [RunState.Truth.HOLDS, RunState.Truth.INVERTED]:
		RunState.cleared_floors.assign(AuditChecks.ORDER)
		RunState.truths = {&"boiler": truth, &"natatorium": 1 - truth, &"blue": truth, &"yellow": 1 - truth, &"units": truth}
		var fx := _hall()
		var a := _audit(fx)
		assert_true(a.tell(LEAD, fx.chunk))
		a.begin_encounter(fx.chunk, &"major", a.encounter_duration(&"major", 60.0))
		assert_true(a.active)
		_drive_perfect(a, fx)
		assert_eq(a.mode, LobbyAudit.Mode.DESK, "a perfect guest reaches the desk")
		assert_eq(a.passes, 5, "all five checks passed")
		assert_eq(a.fails, 0)
		assert_eq(RunState.nerve, RunState.nerve_max, "no Nerve lost")
		assert_true(a.desk_nodes.has(&"checkout") and a.desk_nodes.has(&"desk"), "exit door and chair at the desk")
		fx.dispose()
		_fx = null


func test_failing_a_check_costs_nerve_but_is_never_lethal_at_full_nerve() -> void:
	RunState.cleared_floors.assign([&"units"] as Array[StringName])
	RunState.truths = {&"units": RunState.Truth.HOLDS}
	var fx := _hall()
	var a := _audit(fx)
	assert_true(a.tell(LEAD, fx.chunk))
	a.begin_encounter(fx.chunk, &"major", 900.0)
	RunState.set_nerve(RunState.nerve_max)
	# let the intro end, stand on the station and ignore the bellhop (HOLDS: wrong)
	var c: AuditChecks.AnswerCheck = null
	for i in 400:
		a.step(0.1)
		c = a.current_check() as AuditChecks.AnswerCheck
		if c != null and a.mode == LobbyAudit.Mode.CHECKS:
			fx.player.global_position = c.station
			if c.state == AuditChecks.State.PENDING and not fx.player.global_position.is_equal_approx(c.station):
				pass
		if a.fails > 0:
			break
	assert_eq(a.fails, 1, "the ignored bellhop failed the check")
	assert_eq(RunState.nerve, RunState.nerve_max - 1, "one Nerve segment lost, not all of them")
	assert_true(RunState.nerve > 0, "never lethal at full Nerve")
	assert_eq(fx.session.hits[0], &"audit", "the hit is attributed to the Audit")
	assert_eq(c.state, AuditChecks.State.PENDING, "offered once more")


func test_a_failed_check_is_waived_after_one_retry_and_the_desk_opens() -> void:
	RunState.cleared_floors.assign([&"units"] as Array[StringName])
	RunState.truths = {&"units": RunState.Truth.HOLDS}
	var fx := _hall()
	var a := _audit(fx)
	assert_true(a.tell(LEAD, fx.chunk))
	a.begin_encounter(fx.chunk, &"major", 900.0)
	var steps := 0
	while a.mode != LobbyAudit.Mode.DESK and steps < 8000:
		steps += 1
		var c := a.current_check()
		if c != null and a.mode == LobbyAudit.Mode.CHECKS:
			# step on the pad, then off it again between attempts, ignoring the bellhop every time
			var on := c.state == AuditChecks.State.RUNNING or (c.state == AuditChecks.State.PENDING and (steps / 40) % 2 == 0)
			fx.player.global_position = c.station if on else c.station + Vector3(6, 0, 0)
		RunState.set_nerve(RunState.nerve_max)           # keep the guest alive: this test is about the flow
		a.step(0.1)
	assert_eq(a.mode, LobbyAudit.Mode.DESK, "the desk opens even after failing")
	assert_eq(a.fails, 2, "two failed attempts (one retry)")
	assert_eq(a.waived, 1, "then the check is waived")


func test_a_failed_retry_is_only_noted_one_hit_per_check() -> void:
	RunState.cleared_floors.assign([&"units"] as Array[StringName])
	RunState.truths = {&"units": RunState.Truth.HOLDS}
	var fx := _hall()
	var a := _audit(fx)
	assert_true(a.tell(LEAD, fx.chunk))
	a.begin_encounter(fx.chunk, &"major", 900.0)
	var steps := 0
	while a.mode != LobbyAudit.Mode.DESK and steps < 8000:
		steps += 1
		var c := a.current_check()
		if c != null and a.mode == LobbyAudit.Mode.CHECKS:
			var on := c.state == AuditChecks.State.RUNNING or (c.state == AuditChecks.State.PENDING and (steps / 40) % 2 == 0)
			fx.player.global_position = c.station if on else c.station + Vector3(6, 0, 0)
		a.step(0.1)
	assert_eq(a.fails, 2, "failed twice")
	assert_eq(fx.session.hits.size(), 1, "only the first failure of a check costs Nerve; the failed retry is noted")


func test_a_lethal_hit_during_a_check_does_not_crash_the_audit() -> void:
	RunState.cleared_floors.assign([&"units"] as Array[StringName])
	RunState.truths = {&"units": RunState.Truth.HOLDS}
	var fx := _hall()
	var a := _audit(fx)
	assert_true(a.tell(LEAD, fx.chunk))
	a.begin_encounter(fx.chunk, &"major", 900.0)
	# the guest's last segment goes: the session tears the entity down from inside the hit
	fx.session.on_hit_cb = func() -> void: a.retire()
	for i in 600:
		var c := a.current_check()
		if c != null and a.mode == LobbyAudit.Mode.CHECKS:
			fx.player.global_position = c.station
		a.step(0.1)
		if a.mode == LobbyAudit.Mode.OFF or not a.active:
			break
	assert_true(a.fails >= 1, "a check failed and the hit tore the Audit down mid-call")
	assert_eq(a.current_check(), null, "nothing left to re-arm")


func test_clock_running_out_waives_the_rest_and_opens_the_desk() -> void:
	RunState.cleared_floors.assign(AuditChecks.ORDER)
	var fx := _hall()
	var a := _audit(fx)
	assert_true(a.tell(LEAD, fx.chunk))
	a.begin_encounter(fx.chunk, &"major", 30.0)
	for i in 400:
		a.step(0.1)
	assert_eq(a.mode, LobbyAudit.Mode.DESK, "the Audit completes itself on Management's clock")
	assert_true(a.timed_out)


# --- the desk and the endings ------------------------------------------------------------------

func _desk(mark_ok: bool) -> Array:
	RunState.cleared_floors.assign(AuditChecks.ORDER)
	for f in AuditChecks.ORDER:
		RunState.entity_mark_ok[f] = mark_ok
	var fx := _hall()
	var a := _audit(fx)
	var got: Array[StringName] = []
	a.ending_hook = func(e: StringName) -> void: got.append(e)
	assert_true(a.tell(LEAD, fx.chunk))
	a.begin_encounter(fx.chunk, &"major", 900.0)
	_drive_perfect(a, fx)
	assert_eq(a.mode, LobbyAudit.Mode.DESK)
	return [a, got, fx]


func test_check_out_and_take_the_desk_are_always_offered() -> void:
	for ending in [&"checkout", &"desk"]:
		var r := _desk(false)
		var a: LobbyAudit = r[0]
		var got: Array[StringName] = r[1]
		assert_true(a.desk_nodes.has(ending), "%s is in the world" % ending)
		var it := _interactable_of(a.desk_nodes[ending])
		assert_not_null(it, "%s has an interactable" % ending)
		assert_true(it.available(a.player()), "%s is usable at the desk" % ending)
		it.do_tap(a.player())
		assert_eq(got, [ending] as Array[StringName], "%s reports its ending" % ending)
		assert_eq(a.ending, ending)
		assert_false(a.choose(&"checkout"), "an ending is taken once")
		_fx.dispose()
		_fx = null


func test_burn_the_card_is_gated_on_every_entity_rule_marked_correctly() -> void:
	var r := _desk(false)
	var a: LobbyAudit = r[0]
	var got: Array[StringName] = r[1]
	assert_false(a.desk_nodes.has(&"burn"), "no card on the desk when a rule was marked wrong")
	assert_false(a.burn_available())
	assert_false(a.choose(&"burn"), "burn cannot be forced")
	assert_true(got.is_empty())
	_fx.dispose()
	_fx = null
	var r2 := _desk(true)
	var b: LobbyAudit = r2[0]
	var got2: Array[StringName] = r2[1]
	assert_true(b.burn_available())
	assert_true(b.desk_nodes.has(&"burn"), "the card is on the desk")
	var it := _interactable_of(b.desk_nodes[&"burn"])
	it.do_tap(b.player())
	assert_eq(got2, [&"burn"] as Array[StringName], "taking the card burns it")
	# one wrong mark on any earlier floor withdraws it
	_fx.dispose()
	_fx = null
	RunState.entity_mark_ok[&"blue"] = false
	assert_false(LobbyAudit.new().burn_available())


func test_endings_go_through_game_on_ending_not_complete_floor() -> void:
	var src := FileAccess.get_file_as_string("res://entities/lobby_audit.gd")
	assert_true(src.contains("Game.on_ending(ending)"), "the default ending hook is Game.on_ending")
	var code := ""
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line.split("##")[0] + "\n"
	assert_false(code.contains("complete_floor"), "the Audit never calls session.complete_floor()")


func test_walk_encouraged_slows_the_freeze_walker_while_it_sees_the_guest() -> void:
	var fx := _hall(RunState.Truth.INVERTED)
	var a := _audit(fx)
	var c: AuditChecks.FreezeCheck = _check(fx, &"natatorium", RunState.Truth.INVERTED)
	c.audit = a
	RunState.clause = &""
	assert_near(c._cap(AuditChecks.FreezeCheck.WALKER_SPEED), AuditChecks.FreezeCheck.WALKER_SPEED, 0.0001, "no Clause: full speed")
	RunState.clause = &"walk_encouraged"
	RunState.clause_void = false
	a.global_position = c.station + Vector3(0, 0, 0)
	fx.player.global_position = c.station + Vector3(1.0, 0, 0)
	assert_true(c._cap(AuditChecks.FreezeCheck.WALKER_SPEED) <= GameScale.WALK_SPEED + 0.0001,
		"walk_encouraged: staff never out-walk a walk while they can see the guest")
	c.teardown()


func test_take_number_lets_one_pursuer_move_at_a_time() -> void:
	var fx := _hall(RunState.Truth.INVERTED)
	var a := _audit(fx)
	RunState.clause = &"take_number"
	RunState.clause_void = false
	var other := EntityBase.new()
	other.setup(fx.session, 0)
	fx.stage.actors_root.add_child(other)
	other.active = true
	assert_true(fx.session.clauses.claim_pursuit(other), "the first pursuer is served")
	var c: AuditChecks.FreezeCheck = _check(fx, &"natatorium", RunState.Truth.INVERTED)
	c.audit = a
	a.active = true
	assert_false(c._claim(), "a second pursuer waits its turn under take_number")
	fx.session.clauses.release_pursuit(other)
	assert_true(c._claim(), "and is served once the first is done")
	c.teardown()
	other.queue_free()


func _interactable_of(n: Node) -> Interactable:
	for c in n.get_children():
		if c is Interactable:
			return c
	return null
