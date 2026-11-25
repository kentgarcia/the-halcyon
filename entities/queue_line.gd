class_name QueueLine
extends EntityBase
## The Queue (SPEC 6.4): B1 Blue Annex, instinct *Wait*. Card rule: "Please take a number and wait to be called.
## Do not leave the line."  8-14 identical figures stand in a corridor facing the windows, each holding a ticket;
## their heads turn a few degrees per minute. A ticket dispenser, a NOW SERVING board. NOT staff, and the only
## entity that never chases: it is the floor's exam (a ~3 minute forced stillness) and also works as a minor.
##
##   Every ~20 s the board counts down and a chime sounds: for 3 s ALL faces turn to the board (the "called" window).
##
##   HOLDS     Take a ticket (number N): the board counts down to N in 2-3 minutes. Waiting is safe. When N is called
##             the window door opens and the line lets you walk to it. LEAVING the line (or cutting along it with no
##             ticket) turns every head to you; if you stay out, the line closes in.
##   INVERTED  The ticket is a claim: each time the board counts the whole line takes a step TOWARD you. Correct: take
##             no number, and slip along the wall only during the 3 s chime window; outside it, a guest who moves
##             along the line is noticed and the line closes in.
##
## The closing-in is the only threat (a Nerve hit at arm's length, then the line goes back to its places): never
## lethal at full Nerve. Tells (both): whispered numbers, and the board's colour/typeface: Management's clean amber
## (HOLDS) vs a board that glitches (INVERTED).

enum Mode { OFF, TELL, LIVE, ALERT, DONE }

class Figure extends RefCounted:
	var sil: Silhouette = null
	var home: Vector2i = Vector2i.ZERO
	var tile: Vector2i = Vector2i.ZERO
	var pos: Vector3 = Vector3.ZERO
	var fwd: Vector3 = Vector3(0, 0, -1)
	var gaze := 0.0                       ## signed head turn from `fwd` toward the guest (radians)
	var creep := 0.0                      ## slow, steady turn toward the guest (radians)
	var creep_rate := 0.0
	var appear_at := 0.0
	var shown := false

const FIGURE_HEIGHT := 2.25
const FIGURE_ASPECT := 0.42
const MAX_FIGURES := 14
const MIN_FIGURES := 6
const WATCH_RANGE := 6.5                  ## figures notice a guest this close to the line
const FIGURE_SPEED := 3.0

var crowd: CrowdTuning = null
var mode: int = Mode.OFF
var figures: Array[Figure] = []
var slots: Array[Vector2i] = []           ## head -> tail
var wait_pos: Vector3 = Vector3.ZERO      ## where a guest waits: in front of the dispenser
var head_pos: Vector3 = Vector3.ZERO
var board: QueueBoard = null
var dispenser: Node3D = null
var dispenser_it: Interactable = null
var spawned_props: Array[Node] = []
var manual := false                       ## tests drive step() themselves

var ticket := -1                          ## the guest's number (-1 = none)
var board_value := 0
var tick_count := 0
var tick_t := 0.0
var chime_left := 0.0
var suspicion := 0.0
var lurches := 0
var called := false
var called_safe_t := 0.0
var passed_head := false
var tell_lead := 0.0
var tell_clock := 0.0
var alert_t := 0.0
var alert_reason: StringName = &""
var alerts := 0

var _gen_line_len := 0.0
var _leave_t := 0.0
var _away_t := 0.0
var _step_t := 0.0
var _whisper_t := 0.0
var _finish_t := -1.0
var _calm_hidden_t := 0.0
var _far_t := 0.0
var _dist_from_wait: Dictionary = {}
var _head_dist := 0
var _last_hit := false
var _exam_layout := false


func _init() -> void:
	entity_id = &"queue"
	is_staff = false                      # the Queue is not staff: no Clause binds it (SPEC 4.10)


func _ready() -> void:
	crowd = CrowdTuning.load_default()
	add_to_group(&"entities")


# --- layout ---------------------------------------------------------------------------------

func _grid() -> WorldGrid:
	return session.grid as WorldGrid


func _chunk_has(t: Vector2i) -> bool:
	return home_chunk != null and is_instance_valid(home_chunk) and home_chunk.world_open.has(t)


func can_exist_in(chunk: Chunk) -> bool:
	if chunk.spec.tags.has(&"queue"):
		return true
	return not _find_run(chunk).is_empty()


func _plan_layout(chunk: Chunk) -> bool:
	slots.clear()
	_exam_layout = chunk.spec.tags.has(&"queue") and chunk.slot_nodes.has(&"anchor")
	var ok := false
	if _exam_layout:
		ok = _layout_exam(chunk)
	if not ok:
		_exam_layout = false
		ok = _layout_run(chunk)
	if not ok:
		return false
	# geodesic distance from the waiting spot: used to tell when the guest has slipped past the head of the line
	var wt := GameScale.world_to_tile(wait_pos)
	_dist_from_wait = _grid().distance_field(wt, 80)
	_head_dist = int(_dist_from_wait.get(slots[0], 0))
	return true


func _layout_exam(chunk: Chunk) -> bool:
	var anchors: Array = chunk.slot_nodes.get(&"anchor", [])
	if anchors.size() < MIN_FIGURES:
		return false
	var disp: Array = chunk.slot_nodes.get(&"dispenser", [])
	var from_tile := player_tile()
	if not disp.is_empty():
		dispenser = disp[0]
		var front := dispenser.global_position + (-dispenser.global_transform.basis.z) * 0.4
		from_tile = GameScale.world_to_tile(front)
		wait_pos = Vector3(front.x, 0.0, front.z)
	else:
		wait_pos = GameScale.tile_to_world(from_tile)
	var field := _grid().distance_field(from_tile, 90)
	var ranked: Array = []
	for a: Node3D in anchors:
		var t := GameScale.world_to_tile(a.global_position)
		ranked.append({"t": t, "d": int(field.get(t, -1))})
	ranked = ranked.filter(func(r): return r["d"] >= 0)
	ranked.sort_custom(func(a, b): return a["d"] > b["d"])           # farthest from the dispenser = the head
	for r in ranked.slice(0, MAX_FIGURES):
		slots.append(r["t"])
	if slots.size() < MIN_FIGURES:
		return false
	var bd: Array = chunk.slot_nodes.get(&"board", [])
	if not bd.is_empty():
		board = bd[0] as QueueBoard
	return true


func _layout_run(chunk: Chunk) -> bool:
	var plan := _find_run(chunk)
	if plan.is_empty():
		return false
	slots.assign(plan["slots"])
	wait_pos = GameScale.tile_to_world(plan["wait_tile"])
	# spawn the dispenser and the board ourselves (a minor's room is not a queue room)
	var wall: Vector2i = plan["wall"]
	dispenser = PropFactory.make(&"number_dispenser")
	_attach_prop(chunk, dispenser, GameScale.tile_to_world(plan["wait_tile"]) + Dir.to_vec3(wall) * (GameScale.TILE * 0.5), Dir.yaw_of(-wall))
	var head_tile: Vector2i = slots[0]
	var end_dir: Vector2i = plan["dir"]
	var board_wall := end_dir if not _grid().can_step(head_tile, end_dir) else wall
	var qb := QueueBoard.create()
	_attach_prop(chunk, qb, GameScale.tile_to_world(head_tile) + Dir.to_vec3(board_wall) * (GameScale.TILE * 0.5), Dir.yaw_of(-board_wall))
	board = qb
	return true


func _attach_prop(chunk: Chunk, node: Node3D, world_pos: Vector3, yaw: float) -> void:
	chunk.props_root.add_child(node)
	node.global_position = world_pos
	node.global_rotation = Vector3(0.0, yaw, 0.0)
	spawned_props.append(node)


func _find_run(chunk: Chunk) -> Dictionary:
	## A straight, wall-hugging run of floor in a room: {slots: head->tail tiles, wait_tile, dir (toward the head),
	## wall (the wall side)}. Empty when the room has no run long enough for MIN_FIGURES.
	var grid := _grid()
	var pt := player_tile()
	var field := grid.distance_field(pt, 40)
	var best: Dictionary = {}
	var best_score := -1e9
	for t: Vector2i in chunk.world_open:
		for d in Dir.ALL:
			var prev := t - d
			if chunk.world_open.has(prev) and grid.can_step(prev, d):
				continue                                          # not the start of a maximal run
			var run: Array[Vector2i] = [t]
			var cur := t
			while chunk.world_open.has(cur + d) and grid.can_step(cur, d) and run.size() < 40:
				cur += d
				run.append(cur)
			if run.size() < MIN_FIGURES + 1:
				continue
			for k in [1, 3]:
				var w := Dir.rot(d, k)
				var walled := 0
				var open_side := 0
				for r in run:
					if not grid.can_step(r, w):
						walled += 1
					if grid.can_step(r, -w):
						open_side += 1
				if walled < run.size() - 1 or open_side < run.size() - 1:
					continue
				# orient tail -> head with the head farther from the guest
				var oriented := run.duplicate()
				var dir := d
				if int(field.get(run[0], 0)) > int(field.get(run[run.size() - 1], 0)):
					oriented.reverse()
					dir = -d
				var spacing := 2 if oriented.size() >= 2 * MIN_FIGURES + 3 else 1
				var n := mini(MAX_FIGURES, (oriented.size() - 2) / spacing + 1)
				if n < MIN_FIGURES:
					continue
				var tail_dist := int(field.get(oriented[0], 99))
				var score := float(n) * 2.0 - absf(float(tail_dist) - 6.0) * 0.6
				if score > best_score:
					best_score = score
					var sl: Array[Vector2i] = []
					var last := oriented.size() - 1
					for i in n:
						sl.append(oriented[last - i * spacing])
					# the guest waits just behind the tail figure
					var tail_idx := last - (n - 1) * spacing
					var wait_tile: Vector2i = oriented[maxi(0, tail_idx - 1)]
					best = {"slots": sl, "wait_tile": wait_tile, "dir": dir, "wall": w}
	return best


# --- Director interface ---------------------------------------------------------------------

func encounter_duration(kind: StringName, _default: float) -> float:
	return crowd.queue_exam_duration if kind == &"major" else crowd.queue_minor_duration


func tell(lead: float, chunk: Chunk) -> bool:
	## The genuine tell, >= `lead` s: numbers whispered at the line, the board waking in its true colour/face, the
	## figures fading in one by one. (The Director stacks these on purpose: this is the stillness set piece.)
	if mode != Mode.OFF and mode != Mode.DONE:
		retire()
	_clear_world()
	home_chunk = chunk
	if not _plan_layout(chunk):
		return false
	tell_lead = lead
	_build_figures()
	mode = Mode.TELL
	tell_clock = 0.0
	ticket = -1
	called = false
	passed_head = false
	suspicion = 0.0
	alerts = 0
	lurches = 0
	tick_count = 0
	_finish_t = -1.0
	_last_hit = false
	_leave_t = 0.0
	var rng := RunState.stream(&"entity")
	board_value = rng.randi_range(46, 79)
	if board != null:
		board.activate(truth)
		board.set_number(board_value)
	AudioDirector.play_at(&"whisper_numbers", head_pos, 0.0)
	AudioDirector.cue("[Numbers, whispered]", 3.0)
	_whisper_t = 7.0
	EventBus.tell_started.emit(entity_id, &"board", lead)
	return true


func begin_encounter(chunk: Chunk, kind: StringName, duration: float) -> void:
	if figures.is_empty():
		if not tell(4.5, chunk):
			return
	super.begin_encounter(chunk, kind, duration)
	mode = Mode.LIVE
	tick_t = crowd.queue_board_period
	chime_left = 0.0
	_away_t = 0.0
	_enable_dispenser(true)
	for f in figures:
		_show(f)


func stand_down() -> void:
	if not active:
		return
	super.stand_down()
	_release_pursuit()
	_enable_dispenser(false)
	_return_home()
	mode = Mode.DONE
	suspicion = 0.0
	if board != null and is_instance_valid(board):
		board.close()
	if encounter_kind != &"major":
		_fade_out()


func retire() -> void:
	if active:
		stand_down()
	_enable_dispenser(false)
	_fade_out()
	if board != null and is_instance_valid(board) and mode != Mode.OFF:
		board.set_idle()
	mode = Mode.OFF


func on_session_reset() -> void:
	super.on_session_reset()
	_clear_world()
	mode = Mode.OFF


func _exit_tree() -> void:
	_clear_world()


# --- building the world ---------------------------------------------------------------------

func _build_figures() -> void:
	var rng := RunState.stream(&"cosmetic")
	figures.clear()
	var n := slots.size()
	for i in n:
		var f := Figure.new()
		f.home = slots[i]
		f.tile = slots[i]
		f.pos = GameScale.tile_to_world(slots[i])
		f.sil = Silhouette.create(3, FIGURE_HEIGHT, FIGURE_ASPECT)
		add_child(f.sil)
		f.sil.global_position = f.pos
		f.sil.set_presence(0.0, true)
		f.creep_rate = deg_to_rad(crowd.queue_head_creep_deg_per_min * rng.randf_range(0.5, 1.5)) / 60.0
		f.appear_at = (tell_lead * 0.8) * float(i + 1) / float(n)          # the head appears first, the tail (nearest) last
		figures.append(f)
	# everyone faces the one ahead (head -> tail order: figure i looks at figure i-1; the head keeps its neighbour's)
	for i in n:
		var f2 := figures[i]
		var ahead: Vector3
		if i == 0:
			ahead = figures[0].pos - figures[1].pos if n > 1 else Vector3(0, 0, -1)
		else:
			ahead = figures[i - 1].pos - f2.pos
		ahead.y = 0.0
		f2.fwd = ahead.normalized() if ahead.length() > 0.01 else Vector3(0, 0, -1)
	head_pos = figures[0].pos


func _show(f: Figure) -> void:
	if not f.shown:
		f.shown = true
		f.sil.set_presence(1.0)


func _fade_out() -> void:
	for f in figures:
		f.shown = false
		if f.sil != null and is_instance_valid(f.sil):
			f.sil.set_presence(0.0)
	var dead := figures.duplicate()
	if is_inside_tree() and not dead.is_empty():
		get_tree().create_timer(3.0).timeout.connect(func():
			for f in dead:
				if f.sil != null and is_instance_valid(f.sil) and not f.shown:
					f.sil.queue_free())


func _clear_world() -> void:
	for f in figures:
		if f.sil != null and is_instance_valid(f.sil):
			f.sil.queue_free()
	figures.clear()
	for p in spawned_props:
		if is_instance_valid(p):
			p.queue_free()
	spawned_props.clear()
	if dispenser_it != null and is_instance_valid(dispenser_it):
		dispenser_it.queue_free()
	dispenser_it = null
	dispenser = null
	board = null


func _enable_dispenser(on: bool) -> void:
	if not on:
		if dispenser_it != null and is_instance_valid(dispenser_it):
			dispenser_it.enabled = false
		return
	if dispenser == null or not is_instance_valid(dispenser):
		return
	if dispenser_it == null or not is_instance_valid(dispenser_it):
		dispenser_it = Interactable.new()
		dispenser_it.name = "TakeANumber"
		dispenser_it.position = Vector3(0, 1.1, -0.2)
		dispenser_it.max_range = GameScale.INTERACT_RANGE + 0.3
		dispenser_it.prompt_cb = func(_p): return "Take a number" if ticket < 0 else "Your number: %02d" % ticket
		dispenser_it.tap_cb = func(_p): take_ticket()
		dispenser.add_child(dispenser_it)
	dispenser_it.enabled = true


# --- the ticket -----------------------------------------------------------------------------

func take_ticket() -> void:
	## Interact on the dispenser. HOLDS: an honest place in the line. INVERTED: a claim.
	if mode != Mode.LIVE and mode != Mode.ALERT:
		return
	if ticket >= 0:
		EventBus.toast.emit("Your number is %02d. Now serving %02d." % [ticket, board_value])
		return
	var rng := RunState.stream(&"entity")
	var k := rng.randi_range(crowd.queue_wait_ticks_min, crowd.queue_wait_ticks_max)
	ticket = maxi(1, board_value - k)
	AudioDirector.play(&"pickup_item", -4.0)
	EventBus.toast.emit("Number %02d. Now serving %02d. Please wait to be called." % [ticket, board_value])


# --- per-frame ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not manual:
		step(delta)


func step(delta: float) -> void:
	if mode == Mode.OFF or session == null or player() == null:
		return
	if home_chunk == null or not is_instance_valid(home_chunk):
		retire()
		return
	if mode == Mode.TELL:
		tell_clock += delta
		for f in figures:
			if tell_clock >= f.appear_at:
				_show(f)
		_whisper_t -= delta
		if _whisper_t <= 0.0:
			_whisper_t = 7.0
			AudioDirector.play_at(&"whisper_numbers", head_pos, -3.0)
		_update_gaze(delta)
		return
	if mode == Mode.DONE:
		_move_figures(delta)
		_update_gaze(delta)
		return
	if active:
		encounter_time += delta
		if encounter_time >= encounter_limit:
			stand_down()
			return
	# the guest left the room: the line loses interest
	if not _chunk_has(player_tile()):
		_away_t += delta
		if _away_t > 3.5:
			if active:
				stand_down()
			return
	else:
		_away_t = 0.0
	_tick_board(delta)
	_guest_rules(delta)
	_move_figures(delta)
	_update_gaze(delta)
	_check_hit()
	_check_finish(delta)
	_whisper_t -= delta
	if _whisper_t <= 0.0:
		_whisper_t = 9.0 - 4.0 * suspicion
		AudioDirector.play_at(&"whisper_numbers", head_pos, -6.0 + 7.0 * suspicion)


func _tick_board(delta: float) -> void:
	chime_left = maxf(0.0, chime_left - delta)
	called_safe_t = maxf(0.0, called_safe_t - delta)
	tick_t -= delta
	if tick_t > 0.0:
		return
	tick_t = crowd.queue_board_period
	tick_count += 1
	board_value -= 1
	if board_value < 1:
		board_value = 99
	if board != null:
		board.set_number(board_value)
	chime_left = crowd.queue_chime_window
	AudioDirector.play_at(&"queue_chime", head_pos, 2.0)
	AudioDirector.cue("[Chime]", 2.0)
	if ticket >= 0 and truth == RunState.Truth.INVERTED and _claim_pursuit():
		_lurch()                                   # the ticket was a claim: the whole line steps toward you
	if ticket >= 0 and board_value == ticket and truth == RunState.Truth.HOLDS and not called:
		_on_called()


func _on_called() -> void:
	called = true
	called_safe_t = 30.0
	suspicion = 0.0
	if mode == Mode.ALERT:
		_calm()
	EventBus.toast.emit("Number %02d. Please proceed to the window." % ticket)
	var door := _window_door()
	if door != null:
		door.open_door(door.side_of(player().global_position))


func _window_door() -> Door:
	var best: Door = null
	var best_d := INF
	for e in StaffKit.chunk_doors(session, home_chunk):
		var d: Door = e["door"]
		if bool(e["forward"]):
			return d
		var dist := d.global_position.distance_to(head_pos)
		if dist < best_d and not d.sealed:
			best_d = dist
			best = d
	return best


func guest_in_line() -> bool:
	var g := player().global_position
	return Vector2(g.x - wait_pos.x, g.z - wait_pos.z).length() <= crowd.queue_leave_radius


func _nearest_figure_dist() -> float:
	var g := player().global_position
	var best := INF
	for f in figures:
		best = minf(best, Vector2(g.x - f.pos.x, g.z - f.pos.z).length())
	return best


func _guest_rules(delta: float) -> void:
	var pl := player()
	var in_line := guest_in_line()
	var near := _nearest_figure_dist() <= WATCH_RANGE
	if mode == Mode.ALERT:
		alert_t += delta
		_alert_tick(delta)
		return
	if called_safe_t > 0.0:
		suspicion = maxf(0.0, suspicion - crowd.queue_suspicion_decay * 3.0 * delta)
		return
	# --- HOLDS: a ticket is a place; leaving it (or cutting the line without one) turns every head
	if truth == RunState.Truth.HOLDS:
		if ticket >= 0 and not in_line:
			_leave_t += delta
			suspicion = maxf(suspicion, clampf(_leave_t / 1.2, 0.0, 1.0))
			if _leave_t >= 1.2:
				_alarm(&"left_line")
			return
		_leave_t = 0.0
	# --- no ticket (or INVERTED): moving along the line draws attention; in INVERTED the chime blinds them
	var rising := not in_line and near and not pl.hidden and ticket < 0
	if truth == RunState.Truth.INVERTED and ticket >= 0:
		rising = false                              # a ticket-holder is already claimed: the lurch handles them
	if rising and not (truth == RunState.Truth.INVERTED and chime_left > 0.0):
		suspicion += pl.noise_level() * crowd.queue_suspicion_gain * delta
	else:
		var decay := crowd.queue_suspicion_decay * (4.0 if chime_left > 0.0 else 1.0)
		suspicion = maxf(0.0, suspicion - decay * delta)
	suspicion = clampf(suspicion, 0.0, 1.0)
	if suspicion >= 1.0:
		_alarm(&"noticed")


func _alarm(reason: StringName) -> void:
	if mode == Mode.ALERT:
		return
	mode = Mode.ALERT
	alert_t = 0.0
	_step_t = 0.0
	alert_reason = reason
	alerts += 1
	suspicion = 1.0
	_calm_hidden_t = 0.0
	_far_t = 0.0
	AudioDirector.play_at(&"stinger_low", head_pos, -6.0)
	AudioDirector.cue("[Every head turns]", 2.5)


func _alert_tick(delta: float) -> void:
	var pl := player()
	# ways out: back in line (a ticket in HOLDS), hidden, or far from every face
	if guest_in_line() and (truth == RunState.Truth.HOLDS or ticket < 0) and not pl.hidden:
		_calm()
		return
	_calm_hidden_t = _calm_hidden_t + delta if pl.hidden else 0.0
	_far_t = _far_t + delta if _nearest_figure_dist() > 14.0 else 0.0
	if _calm_hidden_t > 3.0 or _far_t > 3.0:
		_calm()
		return
	if alert_t < crowd.queue_stare_time:
		return
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = crowd.queue_step_time
		if _claim_pursuit():                         # Clause take_number: only one entity pursues at once
			_lurch()


func _claim_pursuit() -> bool:
	var svc: Object = session.get("clauses") if session != null else null
	return svc == null or bool(svc.call("claim_pursuit", self))


func _release_pursuit() -> void:
	var svc: Object = session.get("clauses") if session != null else null
	if svc != null:
		svc.call("release_pursuit", self)


func _calm() -> void:
	_release_pursuit()
	mode = Mode.LIVE
	suspicion = 0.25
	_leave_t = 0.0
	alert_t = 0.0
	_return_home()


func _check_hit() -> void:
	var pl := player()
	if pl.hidden or mode == Mode.DONE or _last_hit or called_safe_t > 0.0:
		return                                       # a called number walks past the line to the window unharmed
	var g := pl.global_position
	for f in figures:
		if f.shown and Vector2(g.x - f.pos.x, g.z - f.pos.z).length() <= crowd.queue_hit_dist:
			_last_hit = true
			hit_player(&"queue")
			AudioDirector.play_at(&"stinger_low", f.pos, -2.0)
			# the line goes back to its places and the exam is over: a warning, not a chase
			finish_after(1.2)
			_return_home()
			mode = Mode.LIVE
			return


func finish_after(seconds: float) -> void:
	_finish_t = seconds


func _check_finish(delta: float) -> void:
	if _finish_t >= 0.0:
		_finish_t -= delta
		if _finish_t <= 0.0:
			_finish_t = -1.0
			stand_down()
			_last_hit = false
		return
	if passed_head:
		return
	# slipped (or was called) past the head of the line: the stillness is over
	var gt := player_tile()
	var d: int = int(_dist_from_wait.get(gt, 9999))
	if d >= _head_dist + 2 and (called or ticket < 0 or truth == RunState.Truth.INVERTED):
		passed_head = true
		_return_home()
		_finish_t = 2.5
	elif called and not _chunk_has(gt):
		passed_head = true
		_finish_t = 1.0


# --- the line moves -------------------------------------------------------------------------

func _occupied(t: Vector2i, except: Figure) -> bool:
	for f in figures:
		if f != except and f.tile == t:
			return true
	return false


func _lurch() -> void:
	## Every figure takes one step along the shortest path to the guest (the nearest figures first).
	lurches += 1
	var gt := player_tile()
	var order := figures.duplicate()
	var g := player().global_position
	order.sort_custom(func(a, b): return a.pos.distance_to(g) < b.pos.distance_to(g))
	for f: Figure in order:
		var path := _grid().path(f.tile, gt, {"allow": func(t): return _chunk_has(t) and not _occupied(t, f), "max_nodes": 400})
		if path.size() >= 3:
			f.tile = path[1]


func _return_home() -> void:
	for f in figures:
		f.tile = f.home


func _move_figures(delta: float) -> void:
	for f in figures:
		var target := GameScale.tile_to_world(f.tile)
		var d := target - f.pos
		d.y = 0.0
		var step := FIGURE_SPEED * delta
		f.pos = target if d.length() <= step else f.pos + d.normalized() * step


func _update_gaze(delta: float) -> void:
	var pl := player()
	var g := pl.global_position
	var cam_pos := pl.camera.global_position if pl.camera != null else g
	var cam_right := pl.camera.global_transform.basis.x if pl.camera != null else Vector3.RIGHT
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	for f in figures:
		if f.sil == null or not is_instance_valid(f.sil):
			continue          # faded out and freed (the figures list outlives the silhouettes by a tween)
		var to_g := g - f.pos
		to_g.y = 0.0
		var ang := _signed_angle(f.fwd, to_g) if to_g.length() > 0.1 else 0.0
		var rate_creep := f.creep_rate * (1.0 if mode == Mode.LIVE or mode == Mode.ALERT else 0.0)
		f.creep = minf(f.creep + rate_creep * delta, PI * 0.5)
		var want := 0.0
		if mode == Mode.ALERT:
			want = ang
		elif chime_left > 0.0:
			want = 0.0
		elif mode == Mode.DONE or mode == Mode.TELL:
			want = 0.0
		else:
			var mag := minf(absf(ang), f.creep + suspicion * PI * 0.9)
			want = signf(ang) * mag
		var rate := deg_to_rad(380.0 if chime_left > 0.0 else (220.0 if mode == Mode.ALERT else 70.0))
		f.gaze = move_toward(f.gaze, want, rate * delta)
		# what the viewer sees of the face
		var gaze_dir := _rotate_xz(f.fwd, f.gaze)
		var to_cam := cam_pos - f.pos
		to_cam.y = 0.0
		to_cam = to_cam.normalized()
		var away := acos(clampf(-gaze_dir.dot(to_cam), -1.0, 1.0))        # 0 = looking straight away from the viewer
		var amount := smoothstep(deg_to_rad(18.0), deg_to_rad(160.0), away)
		f.sil.mat.set_shader_parameter("face_amount", amount)
		f.sil.mat.set_shader_parameter("face_side", clampf(gaze_dir.dot(cam_right) * 1.4, -1.0, 1.0))
		f.sil.global_position = Vector3(f.pos.x, 0.0, f.pos.z)


static func _signed_angle(from: Vector3, to: Vector3) -> float:
	return atan2(from.x * to.z - from.z * to.x, from.x * to.x + from.z * to.z)


static func _rotate_xz(v: Vector3, a: float) -> Vector3:
	return Vector3(v.x * cos(a) - v.z * sin(a), 0.0, v.x * sin(a) + v.z * cos(a))
