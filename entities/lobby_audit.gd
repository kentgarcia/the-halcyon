class_name LobbyAudit
extends EntityBase
## Management, the Lobby's exam: THE AUDIT (SPEC 6.7). Not a chase. The PA reads the rules you learned in a PERFECT
## voice (no secret mic-pop on the Lobby), reads back the Clause you kept, then the exam hall re-stages each earlier
## floor's instinct test as a compressed ~25 s check, in the order you learned them, each with the variant that floor
## rolled this run (RunState.truths). The notebook is the only help (AuditChecks has the per-floor rules).
##
##   fail a check   a Nerve hit (never lethal at full Nerve), the check is offered once more, then waived.
##   all resolved   the DESK: three things in the world, each a deliberate act, never a menu:
##                    the EXIT door   -> Check Out        (always)
##                    the CHAIR       -> Take the Desk    (always)
##                    the CARD        -> Burn the Card    (only when every earlier floor's entity rule was marked
##                                                          correctly at its Inspection: RunState.entity_mark_ok)
## The ending is reported with Game.on_ending(...) (or `ending_hook` in tests), never through complete_floor().
##
## Clauses (House side), all through ClauseService: walk_encouraged caps the walker of the Freeze check; staff_knock
## makes the bellhop knock three times before his door; take_number lets one pursuer move at a time; doors_close has
## no staff-opened door here to bind. The Clause is read back by the PA, and the Lobby alone has it in force.

signal audit_finished(ending: StringName)

enum Mode { OFF, TELL, INTRO, CHECKS, DESK, ENDED }

const ENDINGS: Array[StringName] = [&"checkout", &"desk", &"burn"]

var crowd: CrowdTuning = null
var mode: int = Mode.OFF
var order: Array[StringName] = []                ## floors audited, in the order learned
var checks: Array[AuditChecks.Check] = []
var check_index := -1
var passes := 0
var fails := 0                                   ## failed attempts (each cost a Nerve hit)
var waived := 0                                  ## checks given up on after a retry
var ending: StringName = &""
var ending_hook: Callable = Callable()           ## (ending: StringName); default is Game.on_ending
var manual := false                              ## tests drive step() themselves
var tell_lead := 0.0
var desk_pos := Vector3.ZERO
var desk_nodes: Dictionary = {}                  ## ending id -> Node3D carrying its Interactable
var read_lines: Array[StringName] = []           ## PA lines queued (tests)
var preamble_done := false
var timed_out := false

var _clock := 0.0
var _tell_t := 0.0
var _chime2 := -1.0
var _gap := 0.0
var _rearm := false
var _end_t := -1.0


func _init() -> void:
	entity_id = &"audit"
	is_staff = true                              # Clauses bind staff


func _ready() -> void:
	crowd = CrowdTuning.load_default()
	add_to_group(&"entities")


func _exit_tree() -> void:
	_clear_stage()


# --- queries ----------------------------------------------------------------------------------

func current_check() -> AuditChecks.Check:
	return checks[check_index] if check_index >= 0 and check_index < checks.size() else null


func audit_order() -> Array[StringName]:
	## The floors learned this run, in order. A debug run that starts in the Lobby audits all five.
	var out: Array[StringName] = []
	for f in RunState.cleared_floors:
		if AuditChecks.ORDER.has(f) and not out.has(f):
			out.append(f)
	if out.is_empty():
		out.assign(AuditChecks.ORDER)
	return out


func burn_available() -> bool:
	## Burn the Card: every entity rule of the five earlier floors marked correctly at its Inspection.
	for f in AuditChecks.ORDER:
		if not bool(RunState.entity_mark_ok.get(f, false)):
			return false
	return true


func _anchors(chunk: Chunk) -> Array[Node3D]:
	## The hall's anchors, nearest the entrance first. The last one (farthest) is Management's desk.
	var raw: Array = chunk.slot_nodes.get(&"anchor", [])
	var origin := player_tile()
	if not chunk.entry_world.is_empty():
		origin = chunk.entry_world[0]["tile"]
	var field: Dictionary = (session.grid as WorldGrid).distance_field(origin, 120)
	var list: Array[Node3D] = []
	for a: Node3D in raw:
		list.append(a)
	list.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var da := int(field.get(GameScale.world_to_tile(a.global_position), 9999))
		var db := int(field.get(GameScale.world_to_tile(b.global_position), 9999))
		return da < db)
	return list


# --- Director interface -----------------------------------------------------------------------

func can_exist_in(chunk: Chunk) -> bool:
	return chunk.spec.tags.has(&"audit") and chunk.slot_nodes.get(&"anchor", []).size() >= 3


func encounter_duration(_kind: StringName, _default: float) -> float:
	return crowd.audit_duration


func tell(lead: float, chunk: Chunk) -> bool:
	## The PA chimes (twice), the stage lights up station by station. The lead is the genuine tell: >= `lead` s.
	if not can_exist_in(chunk):
		return false
	if mode != Mode.OFF:
		retire()
	home_chunk = chunk
	order = audit_order()
	_build_stage(chunk)
	if checks.is_empty():
		return false
	tell_lead = lead
	_tell_t = 0.0
	_chime2 = maxf(1.0, lead - 1.4)
	mode = Mode.TELL
	AudioDirector.play(&"pa_chime")
	AudioDirector.cue("[PA chime]", 2.0)
	EventBus.tell_started.emit(entity_id, &"chime", lead)
	return true


func begin_encounter(chunk: Chunk, kind: StringName, duration: float) -> void:
	if mode == Mode.OFF and not tell(4.5, chunk):
		return
	super.begin_encounter(chunk, kind, duration)
	mode = Mode.INTRO
	_gap = crowd.audit_intro_gap
	_read_preamble()


func stand_down() -> void:
	if not active:
		return
	super.stand_down()
	# the clock ran out (Director): whatever is left is waived and the desk opens; any other stand-down is a retire
	if mode == Mode.INTRO or mode == Mode.CHECKS:
		_waive_rest()
		_enter_desk()


func retire() -> void:
	if active:
		active = false
		if player() != null:
			player().nerve.in_danger = false
	_clear_stage()
	mode = Mode.OFF


func on_session_reset() -> void:
	super.on_session_reset()
	_clear_stage()
	mode = Mode.OFF


func _clear_stage() -> void:
	for c in checks:
		c.teardown()
	checks.clear()
	check_index = -1
	for k in desk_nodes:
		var n: Node3D = desk_nodes[k]
		if n != null and is_instance_valid(n):
			n.queue_free()
	desk_nodes.clear()


# --- the stage --------------------------------------------------------------------------------

func _build_stage(chunk: Chunk) -> void:
	_clear_stage()
	var anchors := _anchors(chunk)
	if anchors.size() < 2:
		return
	desk_pos = anchors[anchors.size() - 1].global_position
	var stations := anchors.slice(0, anchors.size() - 1)
	for i in mini(order.size(), stations.size()):
		var f := order[i]
		var c := AuditChecks.make(f, RunState.entity_truth(f), session, crowd)
		if c == null:
			continue
		c.audit = self
		c.build(chunk, (stations[i] as Node3D).global_position)
		checks.append(c)


func _read_preamble() -> void:
	## The PA in its perfect voice: welcome, every rule the guest learned (the entity rules: the ones that could lie,
	## now with no mic-pop), then the Clause. Subtitle-only until the voice files exist.
	read_lines.clear()
	_say(&"audit_open")
	_say(&"audit_intro")
	for f in order:
		_say(AuditChecks.rule_line_id(f))
	_read_clause()
	preamble_done = true


func _say(id: StringName, priority: bool = false) -> void:
	read_lines.append(id)
	AudioDirector.say(id, &"true", priority)


func _read_clause() -> void:
	var cid := RunState.clause
	if cid == &"":
		_say(&"audit_no_clause")
		return
	if RunState.clause_void:
		_say(&"remark_clause_break")
		return
	_say(&"audit_clause")
	_say(StringName("audit_clause_%s" % cid))
	_say(&"audit_clause_force")


# --- per-frame --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not manual:
		step(delta)


func step(delta: float) -> void:
	_clock += delta
	if mode == Mode.OFF or session == null or player() == null:
		return
	if home_chunk == null or not is_instance_valid(home_chunk):
		retire()
		return
	if _end_t >= 0.0:
		_end_t -= delta
		if _end_t < 0.0:
			_call_ending()
		return
	match mode:
		Mode.TELL:
			_tell_t += delta
			if _chime2 > 0.0 and _tell_t >= _chime2:
				_chime2 = -1.0
				AudioDirector.play(&"pa_chime")
		Mode.INTRO:
			_tick_clock(delta)
			_gap -= delta
			if _gap <= 0.0:
				mode = Mode.CHECKS
				check_index = 0
				_reveal(current_check())
		Mode.CHECKS:
			_tick_clock(delta)
			_checks_tick(delta)
		_:
			pass


func _tick_clock(delta: float) -> void:
	if not active:
		return
	encounter_time += delta
	if encounter_time >= encounter_limit - 0.5 and not timed_out:
		timed_out = true
		_say(&"audit_timeout")
		_waive_rest()
		_enter_desk()


func _reveal(c: AuditChecks.Check) -> void:
	if c == null:
		_enter_desk()
		return
	c.reveal()
	_rearm = false


func _checks_tick(delta: float) -> void:
	var c := current_check()
	if c == null:
		_enter_desk()
		return
	var pl := player()
	pl.nerve.in_danger = c.state == AuditChecks.State.RUNNING
	if _gap > 0.0:
		_gap -= delta
		return
	var gp := pl.global_position
	var speed := Vector2(pl.velocity.x, pl.velocity.z).length()
	if c.state == AuditChecks.State.RUNNING:
		c.step(delta, gp, speed)
	# a check can also be settled by the guest between frames (answering the bellhop, taking a number)
	if c.state == AuditChecks.State.PASSED:
		_check_passed(c)
		return
	if c.state == AuditChecks.State.FAILED:
		_check_failed(c)
		return
	if c.state == AuditChecks.State.PENDING:
		if _rearm:
			if not c.guest_on_pad(gp):
				_rearm = false                 # a retry needs the guest to step off and on again
			return
		if c.guest_on_pad(gp):
			_begin_check(c)


func _begin_check(c: AuditChecks.Check) -> void:
	c.begin()
	# the rule being tested, read again in the perfect voice, ahead of anything else queued
	_say(AuditChecks.rule_line_id(c.floor_id), true)


func _check_passed(c: AuditChecks.Check) -> void:
	passes += 1
	AudioDirector.play(&"stamp_thud", -4.0)
	_say(&"audit_pass")
	EventBus.toast.emit("Noted.")
	_advance(c)


func _check_failed(c: AuditChecks.Check) -> void:
	fails += 1
	var retry: bool = crowd.audit_retry_once and c.attempts < 2
	if not crowd.audit_retry_once or retry:
		hit_player(&"audit")                    # the first failure of a check is the warning (never lethal at full Nerve);
		if mode != Mode.CHECKS or c.root == null:  # a failed retry is only noted. A lethal hit tears the Audit down at once
			return
	AudioDirector.play(&"stamp_thud", 0.0)
	_say(&"audit_fail")
	EventBus.toast.emit("That will be noted.")
	if retry:
		c.rearm()
		_rearm = true
		_gap = crowd.audit_intro_gap
		return
	waived += 1
	_advance(c)


func _advance(_c: AuditChecks.Check) -> void:
	check_index += 1
	_gap = 2.0
	if check_index >= checks.size():
		_enter_desk()
	else:
		_reveal(current_check())


func _waive_rest() -> void:
	while check_index >= 0 and check_index < checks.size():
		var c := checks[check_index]
		if c.state != AuditChecks.State.PASSED:
			waived += 1
		check_index += 1


# --- the desk ---------------------------------------------------------------------------------

func _enter_desk() -> void:
	if mode == Mode.DESK or mode == Mode.ENDED:
		return
	mode = Mode.DESK
	check_index = checks.size()
	if player() != null:
		player().nerve.in_danger = false
	_say(&"audit_desk_ready")
	_build_desk(home_chunk)


func _wall_spot(chunk: Chunk, from_tile: Vector2i) -> Dictionary:
	## The wall nearest the desk to hang the exit door on: {tile, wall} (tile = the open tile against the wall).
	var best: Dictionary = {}
	var best_d := 99
	for d in Dir.ALL:
		var t := from_tile
		var n := 0
		while chunk.world_open.has(t + d) and n < 12:
			t += d
			n += 1
		if n >= 2 and n < best_d and not chunk.exit_world.any(func(e): return e["tile"] == t):
			best_d = n
			best = {"tile": t, "wall": d}
	return best


func _build_desk(chunk: Chunk) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	var dt := GameScale.world_to_tile(desk_pos)
	var blocked := AuditChecks.solid_tiles(chunk)
	# the chair: where Management sits, turned toward the room
	var chair := PropFactory.make(&"chair")
	chunk.props_root.add_child(chair)
	chair.global_position = desk_pos
	var face := Vector2i(-1, 0)
	var best_open := -1
	for d in Dir.ALL:
		var open := 0
		var t := dt
		while chunk.world_open.has(t + d) and open < 8:
			t += d
			open += 1
		if open > best_open:
			best_open = open
			face = d
	chair.global_rotation = Vector3(0.0, Dir.yaw_of(face), 0.0)
	_desk_it(&"desk", chair, Vector3(0, 0.9, 0), "Take the desk", func(): choose(&"desk"))
	# the exit door on the nearest wall
	var spot := _wall_spot(chunk, dt)
	if not spot.is_empty():
		var wt: Vector2i = spot["tile"]
		var wd: Vector2i = spot["wall"]
		var door := PropFactory.make(&"exit_door")
		chunk.props_root.add_child(door)
		door.global_position = GameScale.tile_to_world(wt) + Dir.to_vec3(wd) * (GameScale.TILE * 0.5 - 0.02)
		door.global_rotation = Vector3(0.0, Dir.yaw_of(-wd), 0.0)
		_desk_it(&"checkout", door, Vector3(0, 1.1, -0.35), "Check out", func(): choose(&"checkout"))
		_exit_plate(door)
	else:
		var door2 := PropFactory.make(&"exit_door")
		chunk.props_root.add_child(door2)
		door2.global_position = desk_pos + Vector3(1.0, 0, 0)
		_desk_it(&"checkout", door2, Vector3(0, 1.1, -0.35), "Check out", func(): choose(&"checkout"))
		_exit_plate(door2)
	# the card on the desk, only when it has been earned
	if burn_available():
		var desk_tile := dt
		var best_d := 1e9
		for sl: ChunkSpec.SlotDef in chunk.spec.slots:
			if sl.kind == &"desk":
				var wt2 := chunk.local_tile_to_world(sl.tile)
				var dd := float((wt2 - dt).length_squared())
				if dd < best_d:
					best_d = dd
					desk_tile = wt2
		var card := PropFactory.make(&"key_card")
		chunk.props_root.add_child(card)
		card.global_position = GameScale.tile_to_world(desk_tile, 0.76)
		card.global_rotation = Vector3(0.0, 0.4, 0.0)
		_desk_it(&"burn", card, Vector3(0, 0.1, 0), "Burn the card", func(): choose(&"burn"))
	AudioDirector.cue("[A chair turns]", 2.0)


func _exit_plate(door: Node3D) -> void:
	## EXIT on the lit plate above the door (the prop's face is -Z; a Label3D reads from +Z, so it is turned round)
	var lab := PropFactory.make_label("EXIT", Color(0.02, 0.1, 0.05), 0.2)
	lab.position = Vector3(0, 2.28, -0.125)
	lab.rotation.y = PI
	door.add_child(lab)


func _desk_it(id: StringName, parent: Node3D, at: Vector3, prompt: String, cb: Callable) -> void:
	var it := Interactable.new()
	it.name = "Desk_%s" % id
	it.position = at
	it.max_range = GameScale.INTERACT_RANGE + 0.6
	it.prompt = prompt
	it.can_cb = func(_p): return mode == Mode.DESK
	it.tap_cb = func(_p): cb.call()
	parent.add_child(it)
	desk_nodes[id] = parent


func choose(ending_id: StringName) -> bool:
	## A deliberate act at the desk. True when the ending was taken.
	if mode != Mode.DESK or not ENDINGS.has(ending_id):
		return false
	if ending_id == &"burn" and not burn_available():
		return false
	ending = ending_id
	mode = Mode.ENDED
	if player() != null:
		player().frozen = true
		player().nerve.in_danger = false
	if session != null and session.director != null:
		session.director.enabled = false
	match ending_id:
		&"checkout": _say(&"audit_checkout", true)
		&"desk": _say(&"audit_desk", true)
		&"burn": _say(&"audit_burn", true)
	if Main.instance != null and not manual:
		Main.instance.fade_to(1.0, 1.4)
	if manual:
		_call_ending()
	else:
		_end_t = 1.8
	return true


func _call_ending() -> void:
	_end_t = -1.0
	audit_finished.emit(ending)
	if ending_hook.is_valid():
		ending_hook.call(ending)
	else:
		Game.on_ending(ending)
