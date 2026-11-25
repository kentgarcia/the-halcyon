class_name AuditChecks
extends RefCounted
## The Lobby Audit's compressed instinct checks (SPEC 6.7). Each earlier floor's instinct test is re-staged on a
## station of the exam hall, ~25 s long, with the variant that floor rolled this run. The Lobby's PA is perfect, so
## the only help is what the stage SHOWS (always true, Fairness Doctrine 1) and the notebook.
##
##   floor       instinct     HOLDS: correct play                    INVERTED: correct play
##   boiler      run          leave through the marked exit           stay away: a Foreman stands on it
##   natatorium  freeze       stand still when the whistle blows      keep moving: the empty chair, a walker
##   blue        wait         take a number and keep your place       take none: the line steps toward a ticket
##   yellow      seek_light   stand in the light                      stand in the dark
##   units       answer       answer the bellhop                      ignore the bellhop
##
## A Check is pure state + a few props: the LobbyAudit entity feeds it the guest's position and speed, so the same
## rules run in tests with no player. Failing a Check is the entity's business (a Nerve hit, never lethal at full Nerve).

enum State { PENDING, RUNNING, PASSED, FAILED }

const ORDER: Array[StringName] = [&"boiler", &"natatorium", &"blue", &"yellow", &"units"]

const COLOR_LOCKED := "#3a2222"
const COLOR_READY := "#6b5a26"
const COLOR_LIVE := "#3c8a52"
const COLOR_DONE := "#2e4a6b"
const LIT_PAD := "#fff0b0"
const DARK_PAD := "#060606"


static func make(floor_id: StringName, truth: int, session: Node, crowd: CrowdTuning) -> Check:
	var c: Check
	match floor_id:
		&"boiler": c = RunCheck.new()
		&"natatorium": c = FreezeCheck.new()
		&"blue": c = WaitCheck.new()
		&"yellow": c = LightCheck.new()
		&"units": c = AnswerCheck.new()
		_: return null
	c.floor_id = floor_id
	c.truth = truth
	c.session = session
	c.crowd = crowd
	c.window = crowd.audit_check_seconds
	return c


static func rule_text(floor_id: StringName) -> String:
	var def := FloorCatalog.get_def(floor_id)
	var r := def.entity_rule()
	return r.text if r != null else ""


static func rule_line_id(floor_id: StringName) -> StringName:
	## The PA line the Audit reads for a floor's entity rule (always the true take: the Lobby is perfect).
	var def := FloorCatalog.get_def(floor_id)
	var r := def.entity_rule()
	var prefix: String = FloorSession.PA_RULE_PREFIX.get(floor_id, "f1")
	return StringName("rule_%s_%d" % [prefix, r.number if r != null else 1])


# --- layout helpers --------------------------------------------------------------------------

static func solid_tiles(chunk: Chunk) -> Dictionary:
	## World tiles carrying a solid prop (so a staged marker is never buried in a desk or a plant).
	var out := {}
	for sl: ChunkSpec.SlotDef in chunk.spec.slots:
		if sl.kind in [&"desk", &"hide_desk", &"chair", &"plant", &"boxes", &"cabinet", &"cooler", &"stanchion", &"wet_sign", &"hide_closet", &"anchor"]:
			out[chunk.local_tile_to_world(sl.tile)] = true
	return out


static func ring_tiles(session: Node, chunk: Chunk, center: Vector2i, dmin: int, dmax: int, blocked: Dictionary) -> Array[Vector2i]:
	var field: Dictionary = (session.grid as WorldGrid).distance_field(center, dmax)
	var out: Array[Vector2i] = []
	for t: Vector2i in field:
		var d := int(field[t])
		if d >= dmin and d <= dmax and chunk.world_open.has(t) and not blocked.has(t):
			out.append(t)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


static func box_mesh(parts: Array) -> MeshInstance3D:
	## parts: [[color, center, size], ...] -> one surface per colour ("*#rrggbb" is self-lit).
	var mb := MeshBuilder.new()
	for p in parts:
		mb.box(StringName(p[0]), p[1], p[2])
	var mi := MeshInstance3D.new()
	mi.mesh = mb.build()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- the base check --------------------------------------------------------------------------

class Check extends RefCounted:
	var floor_id: StringName = &""
	var truth: int = RunState.Truth.HOLDS
	var session: Node = null
	var crowd: CrowdTuning = null
	var chunk: Chunk = null
	var station := Vector3.ZERO               ## the standing spot that starts the check (world)
	var root: Node3D = null                   ## staged props; world-axis aligned (local offsets == world offsets)
	var pad: MeshInstance3D = null
	var window := 25.0
	var activate_radius := 1.7
	var state: int = State.PENDING
	var elapsed := 0.0
	var attempts := 0
	var reason: StringName = &""
	var revealed := false
	var figures: Array[Silhouette] = []
	var interactables: Array[Interactable] = []
	var audit: EntityBase = null              ## the LobbyAudit: staff, so Clauses bind its figures

	func holds() -> bool:
		return truth == RunState.Truth.HOLDS

	func instinct() -> StringName:
		return StringName(FloorCatalog.get_def(floor_id).instinct)

	func correct_play() -> String:
		return ""

	# --- lifecycle ---
	func build(p_chunk: Chunk, p_station: Vector3) -> void:
		chunk = p_chunk
		station = Vector3(p_station.x, 0.0, p_station.z)
		root = Node3D.new()
		root.name = "AuditStation_%s" % floor_id
		chunk.props_root.add_child(root)
		root.global_position = station
		root.global_rotation = Vector3.ZERO
		pad = AuditChecks.box_mesh([[AuditChecks.COLOR_LOCKED, Vector3(0, 0.006, 0), Vector3(1.5, 0.008, 1.5)]])
		pad.name = "Pad"
		root.add_child(pad)
		_build_props()
		for f in figures:
			f.set_presence(0.0, true)
		_set_enabled(false)

	func reveal() -> void:
		## This station is next: its figures appear and its pad shows ready.
		revealed = true
		_pad_color(AuditChecks.COLOR_READY)
		for f in figures:
			f.set_presence(1.0)
		_on_reveal()

	func begin() -> void:
		state = State.RUNNING
		elapsed = 0.0
		attempts += 1
		reason = &""
		_pad_color(AuditChecks.COLOR_LIVE)
		_set_enabled(true)
		_on_begin()

	func step(delta: float, guest: Vector3, speed: float) -> void:
		if state != State.RUNNING:
			return
		elapsed += delta
		_on_step(delta, guest, speed)
		if state == State.RUNNING and elapsed >= window:
			_on_timeout()

	func succeed(why: StringName) -> void:
		if state != State.RUNNING:
			return
		state = State.PASSED
		reason = why
		_finish()
		_pad_color(AuditChecks.COLOR_DONE)

	func fail(why: StringName) -> void:
		if state != State.RUNNING:
			return
		state = State.FAILED
		reason = why
		_finish()
		_pad_color(AuditChecks.COLOR_LOCKED)

	func rearm() -> void:
		## Back to PENDING for a retry (the staging is reset, the figures stay).
		if root == null:
			return
		state = State.PENDING
		elapsed = 0.0
		_reset()
		_pad_color(AuditChecks.COLOR_READY if revealed else AuditChecks.COLOR_LOCKED)

	func teardown() -> void:
		_set_enabled(false)
		if root != null and is_instance_valid(root):
			root.queue_free()
		root = null
		figures.clear()
		interactables.clear()

	func guest_on_pad(guest: Vector3) -> bool:
		return Vector2(guest.x - station.x, guest.z - station.z).length() <= activate_radius

	# --- helpers for subclasses ---
	func _cap(base_speed: float) -> float:
		## Clause walk_encouraged: staff never out-walk a walk while they can see the guest.
		return StaffRules.speed_cap(session, audit, base_speed) if audit != null else base_speed

	func _claim() -> bool:
		## Clause take_number: only one entity pursues the guest at once.
		var svc: Object = session.get("clauses") if session != null else null
		return svc == null or audit == null or bool(svc.call("claim_pursuit", audit))

	func _release() -> void:
		var svc: Object = session.get("clauses") if session != null else null
		if svc != null and audit != null:
			svc.call("release_pursuit", audit)

	func _pad_color(color: String) -> void:
		if pad == null or root == null or not is_instance_valid(root):
			return
		var old := pad
		pad = AuditChecks.box_mesh([[color, Vector3(0, 0.006, 0), Vector3(1.5, 0.008, 1.5)]])
		pad.name = "Pad"
		root.add_child(pad)
		root.remove_child(old)
		old.queue_free()

	func _set_enabled(on: bool) -> void:
		for it in interactables:
			if is_instance_valid(it):
				it.enabled = on

	func _figure(shape: int, height: float, aspect: float, at: Vector3, accent: Color = Color(0, 0, 0, 0)) -> Silhouette:
		var s := Silhouette.create(shape, height, aspect)
		if accent.a > 0.0:
			s.mat.set_shader_parameter("accent_color", accent)
		root.add_child(s)
		s.position = at
		figures.append(s)
		return s

	func _interactable(parent: Node3D, at: Vector3, prompt: String, cb: Callable) -> Interactable:
		var it := Interactable.new()
		it.position = at
		it.max_range = GameScale.INTERACT_RANGE + 1.0
		it.prompt = prompt
		it.tap_cb = func(_p): cb.call()
		parent.add_child(it)
		interactables.append(it)
		return it

	func _spot(dmin: int, dmax: int, avoid: Array[Vector3], min_gap: float = 3.0) -> Vector3:
		## An open tile between dmin..dmax tiles from the station, clear of solid props and of `avoid`.
		var rng := RunState.stream(&"entity")
		var blocked := AuditChecks.solid_tiles(chunk)
		var st := GameScale.world_to_tile(station)
		var pool := AuditChecks.ring_tiles(session, chunk, st, dmin, dmax, blocked)
		var good: Array[Vector3] = []
		for t in pool:
			var w := GameScale.tile_to_world(t)
			var ok := true
			for a in avoid:
				if Vector2(w.x - a.x, w.z - a.z).length() < min_gap:
					ok = false
					break
			if ok:
				good.append(w)
		if good.is_empty():
			for t in pool:
				good.append(GameScale.tile_to_world(t))
		if good.is_empty():
			return station + Vector3(2.0, 0.0, 0.0)
		return good[rng.randi() % good.size()]

	# --- hooks ---
	func _build_props() -> void:
		pass

	func _on_reveal() -> void:
		pass

	func _on_begin() -> void:
		pass

	func _on_step(_delta: float, _guest: Vector3, _speed: float) -> void:
		pass

	func _on_timeout() -> void:
		fail(&"timeout")

	func _finish() -> void:
		_set_enabled(false)
		_release()

	func _reset() -> void:
		pass


# --- boiler: RUN ------------------------------------------------------------------------------

class RunCheck extends Check:
	## The alarm rings at the station. The marked exit is across the hall. HOLDS: the exit is clear, leave by it.
	## INVERTED: a Foreman stands on the exit (visible all along), so the exit is the one place not to go.
	var exit_pos := Vector3.ZERO
	var foreman: Silhouette = null
	var _alarm: AudioStreamPlayer3D = null

	func correct_play() -> String:
		return "reach the marked exit" if holds() else "stay away from the exit the Foreman stands on"

	func _build_props() -> void:
		var near: Array[Vector3] = []
		exit_pos = _spot(5, 9, near)
		# the alarm bell on a post at the pad
		root.add_child(AuditChecks.box_mesh([
			[PropFactory.METAL_DARK, Vector3(0.7, 0.55, 0), Vector3(0.08, 1.1, 0.08)],
			[PropFactory.RED, Vector3(0.7, 1.16, 0), Vector3(0.3, 0.22, 0.3)],
			[PropFactory.METAL, Vector3(0.7, 1.3, 0), Vector3(0.1, 0.06, 0.1)],
		]))
		# the marked exit: a green mat and a lit EXIT plate on a post, turned to face the station
		var mark := Node3D.new()
		mark.name = "ExitMark"
		root.add_child(mark)
		mark.position = exit_pos - station
		var to := station - exit_pos
		mark.rotation.y = atan2(to.x, to.z)                  # local +Z (where the text reads from) faces the station
		mark.add_child(AuditChecks.box_mesh([
			["*#2f8f58", Vector3(0, 0.008, 0), Vector3(1.3, 0.008, 1.3)],
			["*#b8ffd4", Vector3(0, 0.012, 0), Vector3(0.9, 0.006, 0.12)],
			[PropFactory.METAL_DARK, Vector3(0, 0.9, 0.55), Vector3(0.06, 1.8, 0.06)],
			["*#4cf08a", Vector3(0, 1.75, 0.55), Vector3(0.5, 0.16, 0.04)],
		]))
		var lab := PropFactory.make_label("EXIT", Color(0.03, 0.12, 0.06), 0.2)
		lab.position = Vector3(0, 1.75, 0.58)
		mark.add_child(lab)
		if not holds():
			foreman = _figure(1, 2.3, 0.42, exit_pos - station)

	func _on_begin() -> void:
		_alarm = AudioDirector.play_looped_at(&"alarm_loop", root, 0.0)
		if _alarm != null:
			_alarm.position = Vector3(0.7, 1.4, 0)
		AudioDirector.cue("[Alarm]", 3.0)
		EventBus.toast.emit("An alarm is sounding.")

	func _on_step(_delta: float, guest: Vector3, _speed: float) -> void:
		var d := Vector2(guest.x - exit_pos.x, guest.z - exit_pos.z).length()
		if holds():
			if d <= 1.6:
				succeed(&"left_by_exit")
		elif d <= 2.6:
			fail(&"walked_into_foreman")

	func _on_timeout() -> void:
		if holds():
			fail(&"did_not_leave")
		else:
			succeed(&"stayed_clear")

	func _finish() -> void:
		super._finish()
		if _alarm != null and is_instance_valid(_alarm):
			_alarm.stop()
			_alarm.queue_free()
		_alarm = null


# --- natatorium: FREEZE -----------------------------------------------------------------------

class FreezeCheck extends Check:
	## The whistle blows. HOLDS: the lifeguard stays in the chair: stand still and a second whistle lets you go.
	## INVERTED: the chair is empty; a walker comes toward whoever stands still, so keep moving.
	const WHISTLE_AT := 1.0
	const HOLD_FOR := 4.0
	const STILL_SPEED := 0.4
	const GRACE := 0.8                        ## the guest was walking onto the pad: time to hear the whistle and come to a stop
	const MOVE_NEEDED := 9.0
	const WALKER_SPEED := 2.6                 ## faster than a walk: "Walking is encouraged" slows him while he sees you

	var whistled := false
	var whistle_pos := Vector3.ZERO
	var still_time := 0.0
	var walker: Silhouette = null
	var walker_start := Vector3.ZERO
	var chair_figure: Silhouette = null
	var walker_dist := 0.0

	func correct_play() -> String:
		return "stand still until the second whistle" if holds() else "keep moving after the whistle"

	func _build_props() -> void:
		var near: Array[Vector3] = []
		walker_start = _spot(5, 8, near)
		if holds():
			chair_figure = _figure(2, 2.4, 0.5, walker_start - station)      # the lifeguard stays in the chair
		else:
			var ch := PropFactory.make(&"chair")                              # the chair is empty: he is on foot
			root.add_child(ch)
			ch.position = walker_start - station
			ch.scale = Vector3(1.6, 1.6, 1.6)
			walker = _figure(7, 2.3, 0.42, walker_start - station + Vector3(0.9, 0, 0))

	func _on_begin() -> void:
		whistled = false
		still_time = 0.0
		if walker != null:
			walker.position = walker_start - station + Vector3(0.9, 0, 0)
		walker_dist = 99.0

	func _on_step(delta: float, guest: Vector3, speed: float) -> void:
		if not whistled:
			if elapsed >= WHISTLE_AT:
				whistled = true
				whistle_pos = guest
				still_time = 0.0
				AudioDirector.play_at(&"whistle_blast", root.global_position + Vector3(0, 1.8, 0), 0.0)
				AudioDirector.cue("[Whistle]", 1.5)
			return
		var since := elapsed - WHISTLE_AT
		if holds():
			if since < GRACE:
				whistle_pos = guest              # still stopping: the still-point is where the guest ends up
				return
			if Vector2(guest.x - whistle_pos.x, guest.z - whistle_pos.z).length() > 0.9:
				fail(&"moved_on_the_whistle")
			elif since >= HOLD_FOR:
				AudioDirector.play_at(&"whistle_blast", root.global_position + Vector3(0, 1.8, 0), -3.0)
				succeed(&"stood_still")
		else:
			still_time = still_time + delta if speed < STILL_SPEED else maxf(0.0, still_time - delta)
			var gp := Vector3(guest.x, 0.0, guest.z)
			var wp := root.global_position + walker.position
			walker_dist = Vector2(gp.x - wp.x, gp.z - wp.z).length()
			if speed < STILL_SPEED and walker_dist > 1.3 and _claim():
				var dir := (gp - wp)
				dir.y = 0.0
				walker.position += dir.normalized() * _cap(WALKER_SPEED) * delta
			if walker_dist <= 1.3:
				fail(&"seen_standing_still")
			elif since >= MOVE_NEEDED:
				succeed(&"kept_moving")

	func _on_timeout() -> void:
		if holds():
			fail(&"never_stopped")
		else:
			succeed(&"kept_moving")


# --- blue: WAIT -------------------------------------------------------------------------------

class WaitCheck extends Check:
	## A dispenser, the NOW SERVING board and three figures in line. HOLDS: take a number and keep your place until it
	## is called. INVERTED: the ticket is a claim: each tick the line steps toward you, so take none.
	const TICK := 6.0
	const START := 14
	const TAKE_BY := 9.0
	const LEAVE_RADIUS := 4.5

	var board: QueueBoard = null
	var board_value := START
	var ticket := -1
	var tick_count := 0
	var called := false
	var left_line := false
	var line: Array[Silhouette] = []
	var dispenser: Node3D = null
	var _tick_t := 0.0
	var _chime_t := 0.0
	var _guest := Vector3.ZERO

	func correct_play() -> String:
		return "take a number and wait to be called" if holds() else "take no number"

	func _build_props() -> void:
		var near: Array[Vector3] = []
		var line_dir := _spot(3, 4, near) - station
		line_dir.y = 0.0
		if line_dir.length() < 0.5:
			line_dir = Vector3(1, 0, 0)
		line_dir = line_dir.normalized()
		var side := Vector3(-line_dir.z, 0, line_dir.x)
		dispenser = PropFactory.make(&"number_dispenser")
		root.add_child(dispenser)
		dispenser.position = Vector3(0, 0.0, 0) + side * 0.9
		root.add_child(AuditChecks.box_mesh([[PropFactory.METAL_DARK, side * 0.9 + Vector3(0, 0.55, 0.0), Vector3(0.1, 1.1, 0.1)]]))
		_interactable(dispenser, Vector3(0, 1.1, -0.2), "Take a number", func(): take_number())
		for i in 3:
			line.append(_figure(3, 2.3, 0.42, line_dir * (1.6 + 1.0 * float(i)) - side * 0.2))
		board = QueueBoard.create()
		root.add_child(board)
		board.position = line_dir * 3.0 + side * 1.6 + Vector3(0, 0, 0)
		board.rotation.y = atan2(board.position.x, board.position.z)      # its front (-Z) faces the station
		root.add_child(AuditChecks.box_mesh([[PropFactory.METAL_DARK, board.position + Vector3(0, 0.95, 0), Vector3(0.1, 1.9, 0.1)]]))
		board.set_idle()

	func _on_reveal() -> void:
		board.set_number(START)

	func _on_begin() -> void:
		board_value = START
		ticket = -1
		tick_count = 0
		called = false
		left_line = false
		_tick_t = TICK
		board.activate(truth)
		board.set_number(board_value)
		for f in line:
			f.mat.set_shader_parameter("face_amount", 0.0)

	func take_number() -> void:
		if state != State.RUNNING or ticket >= 0:
			return
		ticket = maxi(1, board_value - 3)
		AudioDirector.play(&"pickup_item", -4.0)
		EventBus.toast.emit("Number %02d. Now serving %02d. Please wait to be called." % [ticket, board_value])
		if not holds():
			# the ticket was a claim: the line has already started to step toward the guest
			fail(&"took_a_number")

	func _on_step(delta: float, guest: Vector3, _speed: float) -> void:
		_guest = guest
		_tick_t -= delta
		if _chime_t > 0.0:
			_chime_t -= delta
			if _chime_t <= 0.0:
				for f in line:
					f.mat.set_shader_parameter("face_amount", 0.0)
		if _tick_t <= 0.0 and state == State.RUNNING:
			_tick_t = TICK
			tick_count += 1
			board_value -= 1
			board.set_number(board_value)
			AudioDirector.play_at(&"queue_chime", root.global_position + Vector3(0, 1.9, 0), 0.0)
			for f in line:
				f.mat.set_shader_parameter("face_amount", 1.0)      # every face turns to the board for the chime
				f.mat.set_shader_parameter("face_side", 0.0)
			_chime_t = 3.0
			if holds() and ticket >= 0 and board_value <= ticket:
				called = true
				AudioDirector.cue("[Chime]", 2.0)
				EventBus.toast.emit("Number %02d. Please proceed to the window." % ticket)
				succeed(&"called")
				return
		if holds():
			if ticket >= 0 and Vector2(guest.x - station.x, guest.z - station.z).length() > LEAVE_RADIUS:
				left_line = true
				fail(&"left_the_line")
			elif ticket < 0 and elapsed >= TAKE_BY:
				fail(&"never_took_a_number")

	func _on_timeout() -> void:
		if holds():
			fail(&"not_called")
		else:
			succeed(&"no_number")

	func _reset() -> void:
		ticket = -1
		board_value = START


# --- yellow: SEEK_LIGHT -----------------------------------------------------------------------

class LightCheck extends Check:
	## Two pads: one in a pool of light, one in the dark; the Hum waits beside the WRONG one for the variant. HOLDS: stand
	## in the light (claw marks ring the dark pad). INVERTED: stand in the dark (scorch halos ring the lit pad).
	const NEED := 15.0
	const WRONG_LIMIT := 3.0

	var lit_pos := Vector3.ZERO
	var dark_pos := Vector3.ZERO
	var hum: Silhouette = null
	var good_time := 0.0
	var bad_time := 0.0

	func correct_play() -> String:
		return "stand on the lit pad" if holds() else "stand on the dark pad"

	func _build_props() -> void:
		var blocked := AuditChecks.solid_tiles(chunk)
		var st := GameScale.world_to_tile(station)
		var pool := AuditChecks.ring_tiles(session, chunk, st, 2, 3, blocked)
		var rng := RunState.stream(&"entity")
		var best_a := station + Vector3(2.5, 0, 0)
		var best_b := station + Vector3(-2.5, 0, 0)
		var best_d := -1.0
		for k in 12:
			if pool.size() < 2:
				break
			var a := GameScale.tile_to_world(pool[rng.randi() % pool.size()])
			var b := GameScale.tile_to_world(pool[rng.randi() % pool.size()])
			var d := Vector2(a.x - b.x, a.z - b.z).length()
			if d > best_d:
				best_d = d
				best_a = a
				best_b = b
		lit_pos = best_a
		dark_pos = best_b
		var lit := Node3D.new()
		root.add_child(lit)
		lit.position = lit_pos - station
		var lit_parts: Array = [[AuditChecks.LIT_PAD, Vector3(0, 0.01, 0), Vector3(1.5, 0.008, 1.5)]]
		var dark := Node3D.new()
		root.add_child(dark)
		dark.position = dark_pos - station
		var dark_parts: Array = [[AuditChecks.DARK_PAD, Vector3(0, 0.01, 0), Vector3(1.5, 0.008, 1.5)]]
		if holds():
			# claw marks ring the dark pad; the lit one is clean
			for i in 5:
				var ang := float(i) / 5.0 * TAU
				var p := Vector3(cos(ang) * 1.0, 0.014, sin(ang) * 1.0)
				for j in 3:
					dark_parts.append(["#7d776d", p + Vector3(sin(ang) * 0.05 * float(j - 1), 0, -cos(ang) * 0.05 * float(j - 1)), Vector3(0.05 + 0.1 * absf(sin(ang)), 0.004, 0.05 + 0.1 * absf(cos(ang)))])
		else:
			# scorched halos ring the lit pad; the dark one is clean
			for i in 8:
				var ang2 := float(i) / 8.0 * TAU
				lit_parts.append(["#2b1a0e", Vector3(cos(ang2) * 0.95, 0.014, sin(ang2) * 0.95), Vector3(0.28, 0.004, 0.28)])
		lit.add_child(AuditChecks.box_mesh(lit_parts))
		dark.add_child(AuditChecks.box_mesh(dark_parts))
		# the Hum waits beside the wrong pad (it is attracted to the place the card's advice would send you)
		var wrong := dark_pos if holds() else lit_pos
		var away := (wrong - station)
		away.y = 0.0
		hum = _figure(0, 2.3, 0.42, wrong - station + away.normalized() * 1.9)

	func _on_begin() -> void:
		good_time = 0.0
		bad_time = 0.0
		AudioDirector.play(&"hum_drop", -4.0)
		AudioDirector.cue("[The hum drops]", 3.0)

	func _on_step(delta: float, guest: Vector3, _speed: float) -> void:
		var on_lit := Vector2(guest.x - lit_pos.x, guest.z - lit_pos.z).length() <= 1.0
		var on_dark := Vector2(guest.x - dark_pos.x, guest.z - dark_pos.z).length() <= 1.0
		var good := on_lit if holds() else on_dark
		var bad := on_dark if holds() else on_lit
		good_time = good_time + delta if good else good_time
		bad_time = bad_time + delta if bad else maxf(0.0, bad_time - delta)
		if bad_time >= WRONG_LIMIT:
			fail(&"wrong_pad")
		elif good_time >= NEED:
			succeed(&"held_the_pad")

	func _on_timeout() -> void:
		fail(&"lost_the_pad")

	func _reset() -> void:
		good_time = 0.0
		bad_time = 0.0


# --- units: ANSWER ----------------------------------------------------------------------------

class AnswerCheck extends Check:
	## A bellhop faces you and speaks after a bell. HOLDS: answer him (he nods and opens a door).
	## INVERTED: don't (he steps close and walks you somewhere you can't leave); ignored, he goes away.
	var greeter: Silhouette = null
	var answered := false
	var knock_wait := 0.0
	var knocks_made := 0
	var _answered_at := 0.0
	var _smile_t := 0.0

	func correct_play() -> String:
		return "answer the bellhop" if holds() else "ignore the bellhop"

	func _build_props() -> void:
		var near: Array[Vector3] = []
		var at := _spot(3, 5, near)
		greeter = _figure(4, 2.3, 0.42, at - station, Color(0.52, 0.06, 0.07))
		var holder := Node3D.new()
		root.add_child(holder)
		holder.position = at - station
		_interactable(holder, Vector3(0, 1.4, 0), "Answer politely", func(): answer())

	func _on_begin() -> void:
		answered = false
		AudioDirector.play_at(&"greeter_bell", root.global_position + greeter.position + Vector3(0, 1.5, 0), 0.0)
		AudioDirector.cue("[Bell]", 2.0)
		EventBus.subtitle.emit("\"Good evening, Guest. May I help you?\"", 4.0)

	func answer() -> void:
		if state != State.RUNNING or answered:
			return
		answered = true
		_answered_at = elapsed
		if holds():
			EventBus.subtitle.emit("\"Of course. This way, please.\"", 3.0)
			# Clause staff_knock: staff knock three times (~5 s) before they open any door
			knock_wait = StaffRules.knock_seconds(session, audit) if audit != null else 0.0
			knocks_made = 0
			if knock_wait <= 0.0:
				_open_door()
		else:
			EventBus.subtitle.emit("\"Allow me.\"", 2.0)
			fail(&"answered_the_bellhop")

	func _open_door() -> void:
		AudioDirector.play_at(&"door_open", root.global_position + greeter.position, -4.0)
		succeed(&"answered")

	func _on_step(delta: float, _guest: Vector3, _speed: float) -> void:
		if holds():
			if answered and knock_wait > 0.0:
				var due := int(floor(_since_answer() / 2.2)) + 1
				while knocks_made < mini(due, 3):
					AudioDirector.play_at(&"knock_slow", root.global_position + greeter.position, 0.0)
					AudioDirector.cue("[Knock, knock, knock]", 1.2)
					knocks_made += 1
				if _since_answer() >= knock_wait:
					_open_door()
			return
		_smile_t -= delta
		if _smile_t <= 0.0:                      # the painted smile drifts between subtly different frames
			_smile_t = RunState.stream(&"cosmetic").randf_range(0.5, 1.4)
			var s := RunState.stream(&"cosmetic").randf_range(-1.0, 1.0)
			greeter.mat.set_shader_parameter("smile_seed", s if absf(s) > 0.25 else 0.6)

	func _since_answer() -> float:
		return elapsed - _answered_at

	func _on_timeout() -> void:
		if holds() and answered:
			_open_door()                          # he was still knocking when the window closed: the answer counts
		elif holds():
			fail(&"ignored")
		else:
			AudioDirector.play_at(&"knock_irregular", root.global_position + greeter.position, 0.0)
			succeed(&"ignored")
