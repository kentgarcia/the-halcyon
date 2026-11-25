class_name Greeter
extends EntityBase
## The Greeter (SPEC 6.6): 2F Units, instinct *Answer*. Card rule: "Staff are here to help. If addressed by staff,
## please answer politely." A bellhop in a red tunic and white gloves with ONE painted smile, standing in a doorframe
## at the far end of the corridor. He faces the guest whenever seen and MOVES ONLY WHILE UNOBSERVED: look at him and
## he is still; look away and he is closer. A planted camcorder never freezes him (its Stakeout tape is the one honest
## way to watch him walk); a guest watching a tape is not watching the room either. Staff: Clauses bind him.
##
##   HOLDS     Answer (Interact) -> he nods, goes to a door and OPENS it (the way on; sometimes a key room), and leaves.
##             Ignore him -> he follows at distance, asks again, and in the end insists; hide and he KNOCKS on your
##             hiding spot, three slow, rhythmic knocks.
##   INVERTED  Answer -> he steps close and ESCORTS you into a unit with no exit (a dead-end room whose door he holds
##             shut for a while). Correct: ignore him, break line of sight, hide; he knocks one to three times,
##             irregularly, tries the handle, and goes.
##
## Tells (both): a bell ding before he speaks; the painted smile is one fixed frame (HOLDS) or drifts between subtly
## different frames (INVERTED); the knocks are rhythmic (HOLDS, knock_slow) or irregular (INVERTED, knock_irregular).
## A hit is always a Nerve warning first; never lethal at full Nerve.

enum Mode { OFF, STAND, APPROACH, GREET, GUIDE, ESCORT, STALK, KNOCK, LEAVE }

const HEIGHT := 2.3
const ASPECT := 0.42
const RED := Color(0.52, 0.06, 0.07)
const FADE_STARE := 10.0                  ## a guide that is stared at this long lets the door open and goes

var crowd: CrowdTuning = null
var mode: int = Mode.OFF
var sil: Silhouette = null
var tile: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var path_i := 0
var spawn_tile: Vector2i = Vector2i(-99999, -99999)
var manual := false                       ## tests drive step() themselves
var observed_override := -1               ## tests: -1 auto, 0 never observed, 1 always observed
var observed := false
var answered := false
var ignored := false
var repeats := 0
var insisted := false
var escorted := false
var opened_door: Door = null
var tell_lead := 0.0
var knock_log: Array[float] = []          ## times (s since the first knock) of the knocks he made: the P1 tell, testable
var knock_count := 0
var opener: StaffKit.DoorOpener = null
var it: Interactable = null

var _clock := 0.0
var _obs_t := 0.0
var _greet_t := 0.0
var _stare_t := 0.0
var _smile_t := 0.0
var _bell_t := -1.0
var _bob := 0.0
var _goal: Vector2i = Vector2i(-99999, -99999)
var _target_door: Dictionary = {}
var _stage := 0
var _stage_t := 0.0
var _knock_times: Array[float] = []
var _knock_i := 0
var _knock_t0 := 0.0
var _hide_pos := Vector3.ZERO
var _away_t := 0.0
var _leave_t := 0.0
var _escort_door: Dictionary = {}
var _ignore_t := 0.0
var _repath_cd := 0.0
var _approach_slack := 0.0


func _init() -> void:
	entity_id = &"greeter"
	is_staff = true                              # Clauses bind staff


func _ready() -> void:
	crowd = CrowdTuning.load_default()
	add_to_group(&"entities")
	sil = Silhouette.create(4, HEIGHT, ASPECT)
	sil.mat.set_shader_parameter("accent_color", RED)
	add_child(sil)
	sil.set_presence(0.0, true)


# --- world queries --------------------------------------------------------------------------

func _grid() -> WorldGrid:
	return session.grid as WorldGrid


func _chunk_has(t: Vector2i) -> bool:
	return home_chunk != null and is_instance_valid(home_chunk) and home_chunk.world_open.has(t)


func _place(t: Vector2i) -> void:
	tile = t
	global_position = tile_world(t)
	path.clear()


func head_point() -> Vector3:
	return global_position + Vector3(0, 1.7, 0)


func is_observed() -> bool:
	if observed_override >= 0:
		return observed_override == 1
	return observed


# --- Director interface ---------------------------------------------------------------------

func can_exist_in(chunk: Chunk) -> bool:
	return chunk.world_open.size() >= 40


func encounter_duration(kind: StringName, _default: float) -> float:
	return crowd.greeter_exam_duration if kind == &"major" else crowd.greeter_minor_duration


func _far_end(chunk: Chunk) -> Vector2i:
	## His doorframe: the anchor (`u`) or exit socket farthest from the guest; else the farthest open tile.
	var pt := player_tile()
	var field := _grid().distance_field(pt, 60)
	var best := Vector2i(-99999, -99999)
	var bd := -1
	var cands: Array[Vector2i] = []
	for a: Node3D in chunk.slot_nodes.get(&"anchor", []):
		cands.append(GameScale.world_to_tile(a.global_position))
	if cands.is_empty():
		for e in chunk.exit_world:
			cands.append(e["tile"])
	if cands.is_empty():
		cands.assign(chunk.world_open.keys())
	for t in cands:
		var d := int(field.get(t, -1))
		if d > bd and chunk.world_open.has(t):
			bd = d
			best = t
	return best


func tell(lead: float, chunk: Chunk) -> bool:
	## A bell, then a bellhop standing in a doorframe at the far end. The genuine tell lasts >= `lead` s: the first ding
	## now, the figure fading in over the lead, a second ding just before he speaks.
	if mode != Mode.OFF:
		retire()
	home_chunk = chunk
	spawn_tile = _far_end(chunk)
	if spawn_tile.x < -9000:
		return false
	var field := _grid().distance_field(player_tile(), 60)
	if int(field.get(spawn_tile, 0)) < 6:
		return false                       # too close: not "the far end of the corridor"
	_place(spawn_tile)
	_reset_state()
	tell_lead = lead
	mode = Mode.STAND
	sil.set_presence(1.0)
	_bell(global_position)
	_bell_t = maxf(0.5, lead - 1.6)
	AudioDirector.cue("[Bell]", 2.0)
	EventBus.tell_started.emit(entity_id, &"bell", lead)
	return true


func _reset_state() -> void:
	answered = false
	ignored = false
	repeats = 0
	insisted = false
	escorted = false
	opened_door = null
	knock_log.clear()
	knock_count = 0
	_greet_t = 0.0
	_stare_t = 0.0
	_ignore_t = 0.0
	_approach_slack = 0.0
	_stage = 0
	_stage_t = 0.0
	_goal = Vector2i(-99999, -99999)
	_away_t = 0.0
	_leave_t = 0.0
	opener = null


func begin_encounter(chunk: Chunk, kind: StringName, duration: float) -> void:
	if mode == Mode.OFF:
		if not tell(4.5, chunk):
			return
	super.begin_encounter(chunk, kind, duration)
	mode = Mode.APPROACH
	_make_interactable()


func stand_down() -> void:
	if not active:
		return
	super.stand_down()
	_release_pursuit()
	_drop_interactable()
	_unseal_escort()
	if mode != Mode.OFF:
		_begin_leave()


func retire() -> void:
	if active:
		stand_down()
	_drop_interactable()
	_unseal_escort()
	if sil != null:
		sil.set_presence(0.0)
	mode = Mode.OFF
	opener = null


func on_session_reset() -> void:
	super.on_session_reset()
	retire()


func _make_interactable() -> void:
	if it != null and is_instance_valid(it):
		it.enabled = true
		return
	it = Interactable.new()
	it.name = "Answer"
	it.position = Vector3(0, 1.4, 0)
	it.max_range = GameScale.INTERACT_RANGE + 1.2
	it.prompt_cb = func(_p): return "Answer politely"
	it.can_cb = func(_p): return mode == Mode.GREET or (mode == Mode.STALK and ignored and not answered)
	it.tap_cb = func(_p): answer()
	add_child(it)


func _drop_interactable() -> void:
	if it != null and is_instance_valid(it):
		it.enabled = false


# --- audio / speech -------------------------------------------------------------------------

func _bell(at: Vector3) -> void:
	AudioDirector.play_at(&"greeter_bell", at + Vector3(0, 1.5, 0), 0.0)


func _say(text: String, seconds: float = 4.0) -> void:
	EventBus.subtitle.emit(text, seconds)


# --- behaviour ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not manual:
		step(delta)


func step(delta: float) -> void:
	_clock += delta
	if mode == Mode.OFF or session == null or player() == null:
		return
	# --- he is only ever still while he is watched
	_obs_t -= delta
	if _obs_t <= 0.0:
		_obs_t = 0.08
		observed = StaffKit.guest_observes(session, head_point()) if sil.visible or mode == Mode.STAND else false
	_update_smile(delta)
	if home_chunk == null or not is_instance_valid(home_chunk):
		retire()
		return
	if mode == Mode.STAND:
		_bell_t -= delta
		if _bell_t > -0.5 and _bell_t <= 0.0:
			_bell_t = -1.0
			_bell(global_position)
		return
	if active:
		encounter_time += delta
		if encounter_time >= encounter_limit and mode != Mode.ESCORT:
			stand_down()
			return
	if not _chunk_has(player_tile()) and mode != Mode.ESCORT and mode != Mode.LEAVE:
		_away_t += delta
		if _away_t > 4.0:
			if active:
				stand_down()
			return
	else:
		_away_t = 0.0
	match mode:
		Mode.APPROACH: _approach(delta)
		Mode.GREET: _greet(delta)
		Mode.GUIDE: _guide(delta)
		Mode.ESCORT: _escort(delta)
		Mode.STALK: _stalk(delta)
		Mode.KNOCK: _knock(delta)
		Mode.LEAVE: _leave(delta)


func _update_smile(delta: float) -> void:
	## The painted smile: one fixed frame (HOLDS) or a face that never quite repeats itself (INVERTED).
	if truth == RunState.Truth.HOLDS or sil == null:
		return
	_smile_t -= delta
	if _smile_t <= 0.0:
		_smile_t = RunState.stream(&"cosmetic").randf_range(0.5, 1.4)
		var s := RunState.stream(&"cosmetic").randf_range(-1.0, 1.0)
		sil.mat.set_shader_parameter("smile_seed", s if absf(s) > 0.25 else 0.6 * signf(s + 0.001))


func walk_speed() -> float:
	## "Walking is encouraged": staff never out-walk a walk while they can see the guest (ClauseService).
	return StaffRules.speed_cap(session, self, crowd.greeter_speed)


func _walk(delta: float, goal: Vector2i) -> bool:
	## Moves along the path to `goal` ONLY while unobserved. True once he has arrived.
	if tile == goal and path.is_empty():
		return true
	_repath_cd -= delta
	var stale := path.is_empty() or path_i >= path.size() or (_repath_cd <= 0.0 and absi(goal.x - _goal.x) + absi(goal.y - _goal.y) > 1)
	if stale:
		_repath_cd = 0.5
		_goal = goal
		path = _grid().path(tile, goal, {"allow": func(t): return _chunk_has(t), "max_nodes": 900})
		path_i = 1
		if path.size() < 2:
			path.clear()
			return true
	if is_observed() or StaffRules.frozen(session):
		return false                         # watched, or a whistle froze staff: he stands where he is
	_bob += delta * 7.0
	sil.position.y = absf(sin(_bob)) * 0.05
	var target := tile_world(path[path_i])
	var to := target - global_position
	to.y = 0.0
	var step_len := walk_speed() * delta
	if to.length() <= step_len:
		global_position = target
		tile = path[path_i]
		path_i += 1
		if path_i >= path.size():
			path.clear()
			sil.position.y = 0.0
			return true
	else:
		global_position += to.normalized() * step_len
		tile = GameScale.world_to_tile(global_position)
	return false


func _tile_near_guest(dist_m: float) -> Vector2i:
	## The tile on his path to the guest that is about `dist_m` from them.
	var pt := player_tile()
	var p := _grid().path(tile, pt, {"allow": func(t): return _chunk_has(t), "max_nodes": 900})
	if p.size() < 2:
		return tile
	var steps_back := int(round(dist_m / GameScale.TILE))
	var idx := maxi(0, p.size() - 1 - steps_back)
	return p[idx]


func _approach(delta: float) -> void:
	if distance_to_player() <= crowd.greeter_greet_dist:
		_start_greet()
		return
	if _walk(delta, _tile_near_guest(maxf(1.0, crowd.greeter_greet_dist - 0.4 - _approach_slack))):
		# arrived at the tile but still out of speaking range (the guest stands off-centre): stand a little closer
		_approach_slack += 0.7
	if distance_to_player() <= crowd.greeter_greet_dist:
		_start_greet()


func _start_greet() -> void:
	mode = Mode.GREET
	path.clear()
	_greet_t = crowd.greeter_answer_window
	_bell(global_position)                     # the ding comes BEFORE he speaks
	AudioDirector.cue("[Bell]", 1.5)
	_say("\"Good evening, Guest. May I help you?\"")


func answer() -> void:
	## Interact on him. HOLDS: he opens a door. INVERTED: he escorts the guest into a unit with no exit.
	if answered or not (mode == Mode.GREET or mode == Mode.STALK):
		return
	answered = true
	path.clear()
	_stage = 0
	_stage_t = 0.0
	_drop_interactable()
	if truth == RunState.Truth.HOLDS:
		_bell(global_position)
		_say("\"Of course. This way, please.\"", 3.0)
		mode = Mode.GUIDE
		_target_door = _pick_guide_door()
	else:
		escorted = true
		_say("\"Allow me.\"", 2.0)
		mode = Mode.ESCORT
		_escort_door = _pick_escort_door()
		player().speed_mods[&"escort"] = 0.0
		_fade(1.0, 0.5)


func _greet(delta: float) -> void:
	_greet_t -= delta
	# face him and he waits; step away and he waits too: he only ever speaks first from 2.7 m
	if _greet_t <= 0.0:
		ignored = true
		mode = Mode.STALK
		_ignore_t = 0.0
		_say("...", 1.0)


# --- HOLDS: he opens a door -----------------------------------------------------------------

func _pick_guide_door() -> Dictionary:
	var list := StaffKit.chunk_doors(session, home_chunk)
	var fwd: Dictionary = {}
	var key: Array[Dictionary] = []
	for d in list:
		if bool(d["forward"]):
			fwd = d
		elif bool(d["dead_end"]) and not (d["door"] as Door).sealed:
			key.append(d)
	var rng := RunState.stream(&"entity")
	# the way on, and now and then a key room (a side room worth having opened)
	if not key.is_empty() and (fwd.is_empty() or encounter_kind != &"major" and rng.randf() < 0.4):
		return key[rng.randi() % key.size()]
	if not fwd.is_empty():
		return fwd
	return list[0] if not list.is_empty() else {}


func _guide(delta: float) -> void:
	if _target_door.is_empty():
		_begin_leave()
		return
	var door: Door = _target_door["door"]
	match _stage:
		0:                                  # a nod, then he turns for the door (only while he is not watched)
			_stage_t += delta
			sil.position.y = -absf(sin(_stage_t * 5.0)) * 0.06 if _stage_t < 0.9 else 0.0
			if _stage_t >= 1.0:
				_stage = 1
		1:                                  # walk to the door
			if is_observed():
				_stare_t += delta
			else:
				_stare_t = 0.0
			var beside: Vector2i = _target_door["tile"]
			var arrived := _walk(delta, beside)
			if arrived or _stare_t >= FADE_STARE:
				# arrived (or stared at for too long: the door opens by itself and he is simply gone)
				opener = StaffKit.DoorOpener.new()
				opener.start(session, door, self)
				_stage = 2
		2:                                  # open it like staff must: knocks first under the Clause, never within 8 s of a close
			opener.step(delta)
			if opener.done:
				opened_door = door
				_bell(global_position)
				_say("\"After you.\"", 2.5)
				_stage = 3
				_stage_t = 0.0
		3:
			_stage_t += delta
			if _stage_t >= 2.0:
				_begin_leave()


# --- INVERTED: he escorts the guest into a room with no exit ---------------------------------

func _pick_escort_door() -> Dictionary:
	## The nearest dead-end door (closet / vault / breaker room): the only honest "unit with no exit". The way on is
	## never used as a trap. Empty when the room has none (the guest is then simply shown back out to the entrance).
	var pl := player().global_position
	var best: Dictionary = {}
	var best_d := INF
	for d in StaffKit.chunk_doors(session, home_chunk):
		var door: Door = d["door"]
		if door.sealed or not bool(d["dead_end"]) or not StaffRules.may_open_door(session, door, self):
			continue
		var dd := door.global_position.distance_to(pl)
		if dd < best_d:
			best_d = dd
			best = d
	return best


func _escort(delta: float) -> void:
	_stage_t += delta
	match _stage:
		0:                                  # the screen goes dark: he is not watched, so he can step close
			if _stage_t >= 0.6:
				_stage = 1
				_stage_t = 0.0
				var pl := player()
				var fwd := -pl.global_transform.basis.z
				fwd.y = 0.0
				_place(GameScale.world_to_tile(pl.global_position + fwd.normalized() * 1.1))
				_place_safe_near_guest()
				AudioDirector.play_at(&"step_carpet", global_position, -4.0)
		1:                                  # the long walk, heard and not seen
			if _stage_t >= 1.2:
				_stage = 2
				_stage_t = 0.0
				_lock_in()
		2:                                  # the door holds
			if _stage_t >= crowd.greeter_escort_hold:
				_unseal_escort()
				AudioDirector.play_at(&"door_handle_try", _escort_pos(), 0.0)
				AudioDirector.cue("[A handle turns]", 2.0)
				_stage = 3
				_stage_t = 0.0
		3:
			if _stage_t >= 2.5:
				stand_down()


func _place_safe_near_guest() -> void:
	if not _chunk_has(tile):
		_place(player_tile())


func _escort_pos() -> Vector3:
	if _escort_door.is_empty():
		return global_position
	return StaffKit.door_pos(_escort_door["door"])


func _lock_in() -> void:
	## Move the guest through the door, shut it behind them and hold it: the unit with no exit.
	var pl := player()
	if _escort_door.is_empty():
		# no door to use: shown out at the room's entrance instead (same cost, no trap)
		pl.teleport(session.exit_position_of(home_chunk), pl.rotation.y)
	else:
		var door: Door = _escort_door["door"]
		var dtile: Vector2i = _escort_door["tile"]
		var dir: Vector2i = _escort_door["dir"]
		door.open_door(door.side_of(pl.global_position), true)          # builds the room behind it
		var beyond := dtile + dir
		var dest := GameScale.tile_to_world(beyond) + Dir.to_vec3(dir) * 0.3
		pl.teleport(dest, Dir.yaw_of(-dir))
		door.close_door(true)
		door.sealed = true
		_escort_door["was_sealed"] = true
		AudioDirector.play_at(&"door_close", door.global_position, 0.0)
		AudioDirector.play_at(&"door_locked", door.global_position, -2.0)
		_place(dtile)
	pl.speed_mods.erase(&"escort")
	EventBus.toast.emit("The door will not open.")
	_fade(0.0, 0.9)
	hit_player(&"greeter")                  # a warning at full Nerve, never lethal


func _unseal_escort() -> void:
	if not _escort_door.is_empty() and bool(_escort_door.get("was_sealed", false)):
		var door: Door = _escort_door["door"]
		if is_instance_valid(door):
			door.sealed = false
		_escort_door["was_sealed"] = false
	if player() != null:
		player().speed_mods.erase(&"escort")


func _fade(to: float, seconds: float) -> void:
	if Main.instance != null:
		Main.instance.fade_to(to, seconds)


# --- ignored: he follows, insists, and knocks ------------------------------------------------

func _stalk(delta: float) -> void:
	var pl := player()
	_ignore_t += delta
	if pl.hidden:
		_start_knock()
		return
	var close := truth == RunState.Truth.HOLDS and repeats >= 1
	var want := 1.3 if close else crowd.greeter_follow_dist          # "closer each time" once he has asked again
	if distance_to_player() > want + 0.6 and _claim_pursuit():
		_walk(delta, _tile_near_guest(want))
	if truth == RunState.Truth.HOLDS:
		# an honest card: "answer politely". He asks again, closer each time, and in the end insists.
		if _ignore_t >= 7.0 * float(repeats + 1) and repeats < 3:
			repeats += 1
			_bell(global_position)
			_say("\"I did say, may I help you?\"" if repeats == 1 else "\"It would be no trouble.\"", 3.0)
		if repeats >= 3 and distance_to_player() <= crowd.greeter_insist_dist + 1.2 and not insisted:
			insisted = true
			hit_player(&"greeter")
			_say("\"I must insist.\"", 2.5)
			_begin_leave()


func _claim_pursuit() -> bool:
	## Clause take_number: only one entity pursues the guest at once.
	var svc: Object = session.get("clauses") if session != null else null
	return svc == null or bool(svc.call("claim_pursuit", self))


func _release_pursuit() -> void:
	var svc: Object = session.get("clauses") if session != null else null
	if svc != null:
		svc.call("release_pursuit", self)


func _start_knock() -> void:
	var pl := player()
	mode = Mode.KNOCK
	_stage = 0
	_stage_t = 0.0
	var spot := pl.hide_spot
	if spot != null and is_instance_valid(spot) and spot.has_method("exit_position"):
		_hide_pos = spot.exit_position()
	else:
		_hide_pos = pl.global_position
	path.clear()


func _knock(delta: float) -> void:
	var pl := player()
	if not pl.hidden and _stage < 2:
		mode = Mode.STALK                  # you came out: he is still there
		return
	var rng := RunState.stream(&"entity")
	match _stage:
		0:                                  # walk to the hiding place (the hidden guest's view is a slat wide)
			var goal := GameScale.world_to_tile(_hide_pos)
			if not _chunk_has(goal):
				goal = _tile_near_guest(1.0)
			if _walk(delta, goal) or tile == goal:
				var count := 3 if (truth == RunState.Truth.HOLDS or StaffRules.knock_seconds(session, self) > 0.0) else 1 + rng.randi() % 3
				_knock_times = StaffKit.knock_times(truth, count, crowd.greeter_knock_gap, rng)
				_knock_i = 0
				_knock_t0 = _clock
				_stage = 1
		1:
			var t := _clock - _knock_t0
			while _knock_i < _knock_times.size() and t >= _knock_times[_knock_i]:
				AudioDirector.play_at(StaffKit.knock_sound(truth), _hide_pos + Vector3(0, 1.1, 0), 3.0)
				AudioDirector.cue("[Knock]", 0.8)
				knock_log.append(snappedf(_knock_times[_knock_i], 0.001))
				knock_count += 1
				_knock_i += 1
			if _knock_i >= _knock_times.size():
				_stage = 2
				_stage_t = 0.0
				if truth == RunState.Truth.INVERTED:
					get_tree().create_timer(0.8).timeout.connect(func():
						AudioDirector.play_at(&"door_handle_try", _hide_pos + Vector3(0, 1.0, 0), 0.0)
						AudioDirector.cue("[A handle turns]", 2.0))
		2:
			_stage_t += delta
			var patience := 6.0 if truth == RunState.Truth.HOLDS else 3.5
			if _stage_t >= patience:
				_begin_leave()


# --- leaving ---------------------------------------------------------------------------------

func _begin_leave() -> void:
	if mode == Mode.LEAVE or mode == Mode.OFF:
		return
	mode = Mode.LEAVE
	_leave_t = 0.0
	path.clear()


func _leave(delta: float) -> void:
	_leave_t += delta
	if _leave_t > 0.5 and sil.visible and not is_observed():
		sil.set_presence(0.0)              # not walking off in plain sight: he is simply gone
	if _leave_t > 2.5 or (_leave_t > 1.2 and not sil.visible):
		sil.set_presence(0.0)
		if active:
			stand_down()
		mode = Mode.OFF
