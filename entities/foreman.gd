class_name Foreman
extends EntityBase
## The Foreman (SPEC 6.2): B3 Boiler, Run. Card rule: "If an alarm sounds, leave at once through the nearest exit."
## A 2.3 m hard hat who drags a pipe wrench (the scrape is the motif). He is STAFF: the Clauses bind him.
##
##   HOLDS     the alarm (a bell, or a fire door the guest opened) summons him TO THE ALARM SOURCE. He comes in through
##             the exit farthest from the guest, runs to the source, searches it ~20 s and goes home. He is heading for
##             the source, not the guest: leaving by the nearest exit is correct, and running is fine.
##   INVERTED  he waits BEHIND THE NEAREST EXIT. The alarm calls him to the exit the guest is about to take; open that
##             door and he is standing in it. Retreat and hide: if the guest makes for a different exit he follows
##             behind the walls (4.5 s, with that exit's sign flickering the whole time).
##
## Tell (both, >= the Director's lead): the wrench scrape runs through the pipes (HOLDS: from the exits toward the alarm;
## INVERTED: from the alarm to the exit), the boards creak, and the exit sign over his exit FLICKERS (INVERTED) or burns
## steady (HOLDS; there it is the door he is about to open that gets a handle-try). Never lethal at full Nerve.
## Evidence for the active variant only: world/props/recipes/scrape.gd (HOLDS), door_scratch.gd (INVERTED).

enum Mode { OFF, ENTER, GO, SEARCH, RETURN, WAIT, WINDUP, RETREAT }

const STRIKE_PAD := 0.8                  ## the guest may back off this much further during the windup
const NEAR_DOOR := 3.2                   ## metres: an open door this close shows him to the guest
const SEARCH_RADIUS := 4                 ## tiles combed around the alarm source
const RETREAT_SECONDS := 2.5
const CREAK_AT := 0.5                    ## fraction of the lead

var mode: int = Mode.OFF
var sil: Silhouette = null
var tile: Vector2i = Vector2i(-99999, -99999)
var path: Array[Vector2i] = []
var path_i := 0
var exit_ex: Dictionary = {}             ## the exit he uses (HOLDS) / waits behind (INVERTED): {tile, dir, index} (world)
var exit_door: Door = null
var src_pos := Vector3.ZERO              ## the alarm source (world)
var src_tile: Vector2i = Vector2i.ZERO   ## nearest open tile of the room to the source
var src_is_door := false
var perceives := false

var _alarm_source: Dictionary = {}       ## set by a tripped fire door: {door, pos}
var _alarm_until := 0.0                  ## clock (Time.get_ticks_msec()/1000) until which a tripped alarm rings
var _door_alarm: AudioStreamPlayer3D = null
var _bell: AlarmBell = null
var _scrape: AudioStreamPlayer3D = null
var _tell_tween: Tween = null
var _flicker_index := -1
var _search_left := 0.0
var _wander_t := 0.0
var _knock_t := 0.0
var _knock_played := false
var _windup := 0.0
var _retreat_t := 0.0
var _reloc_t := 0.0
var _reloc_ex: Dictionary = {}
var _reloc_cool := 0.0
var _reloc_check := 0.0
var _check_t := 0.0
var _away_t := 0.0


func _init() -> void:
	entity_id = &"foreman"
	is_staff = true


func _ready() -> void:
	add_to_group(&"entities")
	sil = Silhouette.create(1, 2.3, 0.42)
	add_child(sil)
	sil.set_presence(0.0, true)


func setup(p_session: Node, p_truth: int) -> void:
	super.setup(p_session, p_truth)
	var streamer: ChunkStreamer = session.streamer
	if streamer != null:
		streamer.chunk_loaded.connect(_dress)
		for c: Chunk in streamer.chunks.values():
			_dress(c)
	EventBus.door_opened.connect(_on_door_opened)
	EventBus.noise_emitted.connect(_on_noise)


func _exit_tree() -> void:
	if EventBus.door_opened.is_connected(_on_door_opened):
		EventBus.door_opened.disconnect(_on_door_opened)
	if EventBus.noise_emitted.is_connected(_on_noise):
		EventBus.noise_emitted.disconnect(_on_noise)
	_stop_scrape()
	_stop_door_alarm()


func _dress(chunk: Chunk) -> void:
	## The Boiler's rooms carry an alarm bell each and an EXIT sign on every usable exit door.
	if chunk == null or not AlarmSite.is_working_room(chunk.spec):
		return
	AlarmSite.ensure_bell(chunk, session)
	AlarmSite.ensure_signs(chunk, session)


# --- pure rules (unit-tested) ---------------------------------------------------------------

static func pick_exit(steps: Array, p_truth: int) -> int:
	## steps[i] = walking steps from the guest to exit i (negative = unreachable). HOLDS: he comes in through the exit
	## FARTHEST from the guest, so leaving by the nearest one never meets him. INVERTED: he waits behind the NEAREST
	## exit, the one the guest is about to take. Ties go to the lower index. Returns -1 when nothing is reachable.
	var best := -1
	for i in steps.size():
		var s: int = int(steps[i])
		if s < 0:
			continue
		if best < 0:
			best = i
		elif p_truth == RunState.Truth.HOLDS and s > int(steps[best]):
			best = i
		elif p_truth == RunState.Truth.INVERTED and s < int(steps[best]):
			best = i
	return best


static func scrape_route(p_truth: int, door_pos: Vector3, source_pos: Vector3) -> Array[Vector3]:
	## [from, to] of the wrench scrape through the pipes: HOLDS runs away from the exit toward the alarm; INVERTED runs
	## from the alarm to the exit and stays there (SPEC 6.2 Tells: "wrench scrape direction").
	if p_truth == RunState.Truth.HOLDS:
		return [door_pos, source_pos]
	return [source_pos, door_pos]


static func sign_flickers(p_truth: int) -> bool:
	## The exit sign flickers over his exit when the card lies; it burns steady when the house is honest.
	return p_truth == RunState.Truth.INVERTED


static func tell_events(p_truth: int, lead: float) -> Array[Dictionary]:
	## The timeline of the genuine tell, seconds from its start. Every event lies inside the lead, so the hazard is
	## foretold for the whole lead (Doctrine 2). `dur` = how long the cue lasts.
	var ev: Array[Dictionary] = [{"t": 0.0, "kind": &"scrape", "dur": lead}]
	if sign_flickers(p_truth):
		ev.append({"t": 0.0, "kind": &"flicker", "dur": lead})
	ev.append({"t": lead * CREAK_AT, "kind": &"creak", "dur": 1.0})
	if p_truth == RunState.Truth.HOLDS:
		ev.append({"t": maxf(0.0, lead - 1.2), "kind": &"handle", "dur": 1.2})
	return ev


static func can_strike(p_truth: int, m: int, dist: float, door_open: bool, hidden: bool, strike_range: float) -> bool:
	## When he may hurt the guest. HOLDS: only while searching, and only what he stumbles on (he is after the alarm,
	## not the guest). INVERTED: only the guest standing at his open door.
	if hidden:
		return false
	if p_truth == RunState.Truth.HOLDS:
		return m == Mode.SEARCH and dist <= strike_range
	return m == Mode.WINDUP and door_open and dist <= strike_range + STRIKE_PAD


# --- world queries --------------------------------------------------------------------------

func _grid() -> WorldGrid:
	return session.grid as WorldGrid


func _tune() -> DirectorTuning:
	var t: Object = session.get("tuning") if session != null else null
	return t as DirectorTuning if t != null else DirectorTuning.new()


func _clock() -> float:
	return Time.get_ticks_msec() / 1000.0


func _chunk_has(t: Vector2i) -> bool:
	return home_chunk != null and is_instance_valid(home_chunk) and home_chunk.world_open.has(t)


func exit_candidates(chunk: Chunk) -> Array[Dictionary]:
	## Usable exits of the room with the guest's walking distance to each: [{ex, door, steps}].
	var out: Array[Dictionary] = []
	var field := _grid().distance_field(player_tile(), 90)
	for ex: Dictionary in chunk.exit_world:
		var door := AlarmSite.exit_door(session, ex)
		if not AlarmSite.usable(door):
			continue
		out.append({"ex": ex, "door": door, "steps": int(field.get(ex["tile"], -1))})
	return out


func _resolve_source(chunk: Chunk) -> bool:
	## The alarm source of this encounter: a fire door the guest tripped, else the room's bell.
	var door: Variant = _alarm_source.get("door", null)
	if door != null and is_instance_valid(door) and _clock() < _alarm_until:
		src_pos = _alarm_source["pos"]
		src_is_door = true
		src_tile = _nearest_open_tile(chunk, src_pos)
		_bell = null
		return true
	_alarm_source = {}
	_bell = AlarmSite.ensure_bell(chunk, session)
	if _bell == null:
		return false
	src_pos = _bell.global_position
	src_is_door = false
	src_tile = _bell.world_tile
	return true


func _nearest_open_tile(chunk: Chunk, pos: Vector3) -> Vector2i:
	var best := Vector2i.ZERO
	var bd := INF
	for t: Vector2i in chunk.world_open:
		var d := Vector2(GameScale.tile_to_world(t).x - pos.x, GameScale.tile_to_world(t).z - pos.z).length()
		if d < bd:
			bd = d
			best = t
	return best


# --- Director interface ---------------------------------------------------------------------

func can_exist_in(chunk: Chunk) -> bool:
	return AlarmSite.is_working_room(chunk.spec) and not chunk.exit_world.is_empty() and chunk.world_open.size() >= 24


func tell(lead: float, chunk: Chunk) -> bool:
	## Pick his exit and the alarm source, then play the genuine tell. False when there is no usable exit / source.
	home_chunk = chunk
	if not _prepare(chunk):
		return false
	var route := scrape_route(truth, AlarmSite.exit_center(exit_ex, 1.0), src_pos)
	global_position = route[0]
	_stop_scrape()
	_scrape = AudioDirector.play_looped_at(&"wrench_scrape_loop", self, -2.0)
	for ev in tell_events(truth, lead):
		var t: float = ev["t"]
		match ev["kind"]:
			&"scrape":
				if _tell_tween != null:
					_tell_tween.kill()
				_tell_tween = create_tween()
				_tell_tween.tween_property(self, "global_position", route[1], lead * 0.92).set_trans(Tween.TRANS_SINE)
				AudioDirector.cue("[Wrench scrapes through the pipes]", minf(lead, 3.0))
			&"flicker":
				_set_flicker(int(exit_ex["index"]), true)
			&"creak":
				get_tree().create_timer(t).timeout.connect(func():
					if is_instance_valid(self) and not active:
						AudioDirector.play_at(&"ceiling_creak", route[1] + Vector3(0, 1.2, 0), -2.0))
			&"handle":
				get_tree().create_timer(t).timeout.connect(func():
					if is_instance_valid(self) and not active and exit_door != null and is_instance_valid(exit_door):
						AudioDirector.play_at(&"door_handle_try", exit_door.global_position + Vector3(0, 1.0, 0), 0.0))
	EventBus.tell_started.emit(entity_id, &"scrape", lead)
	return true


func _prepare(chunk: Chunk) -> bool:
	var cands := exit_candidates(chunk)
	if cands.is_empty():
		return false
	if not _resolve_source(chunk):
		return false
	var steps: Array = []
	for c in cands:
		steps.append(int(c["steps"]))
	var i := pick_exit(steps, truth)
	if i < 0:
		return false
	exit_ex = cands[i]["ex"]
	exit_door = cands[i]["door"]
	if truth == RunState.Truth.HOLDS:
		var p := _grid().path(exit_ex["tile"], src_tile, {"allow": _inside, "max_nodes": 2000})
		if p.is_empty() and exit_ex["tile"] != src_tile:
			return false
	return true


func _inside(t: Vector2i) -> bool:
	return _chunk_has(t)


func begin_encounter(chunk: Chunk, kind: StringName, duration: float) -> void:
	if _tell_tween != null:
		_tell_tween.kill()
	home_chunk = chunk
	if exit_ex.is_empty() and not _prepare(chunk):
		super.begin_encounter(chunk, kind, duration)
		stand_down()
		return
	super.begin_encounter(chunk, kind, duration)
	_ring(minf(duration, _tune().foreman_alarm_seconds))
	_reloc_t = 0.0
	_reloc_ex = {}
	_reloc_cool = 2.0
	_windup = 0.0
	if truth == RunState.Truth.HOLDS:
		_stop_scrape()
		mode = Mode.ENTER
		_knock_t = 0.0
		_knock_played = false
		_search_left = _tune().foreman_search_seconds
		_place_world(tile_world(AlarmSite.beyond_tile(exit_ex)))
		sil.set_presence(0.0, true)
	else:
		mode = Mode.WAIT
		_place_world(tile_world(AlarmSite.beyond_tile(exit_ex)))
		sil.set_presence(1.0)
		_set_flicker(int(exit_ex["index"]), true)
		if _scrape != null and is_instance_valid(_scrape):
			_scrape.volume_db = -8.0
		else:
			_scrape = AudioDirector.play_looped_at(&"wrench_scrape_loop", self, -8.0)


func stand_down() -> void:
	if _tell_tween != null:
		_tell_tween.kill()
	_stop_scrape()
	_clear_flicker()
	_silence_alarm()
	super.stand_down()
	if mode != Mode.OFF:
		sil.set_presence(0.0)
		mode = Mode.OFF
	exit_ex = {}
	exit_door = null
	_alarm_source = {}
	path.clear()


func retire() -> void:
	## The guest left before it arrived, or the floor is over: he fades out wherever he is.
	if _tell_tween != null:
		_tell_tween.kill()
	_stop_scrape()
	_clear_flicker()
	sil.set_presence(0.0)
	mode = Mode.OFF
	if active:
		stand_down()
	exit_ex = {}
	exit_door = null


func on_session_reset() -> void:
	super.on_session_reset()
	retire()


# --- alarm ----------------------------------------------------------------------------------

func trip_alarm(door: Door) -> void:
	## A fire door opens on an alarm floor: the alarm rings at the door, and the house asks the Director for an
	## Encounter (pacing rules still apply, and the Tell still comes first). Without one the alarm just rings.
	var secs := _tune().foreman_alarm_seconds
	_alarm_until = _clock() + secs
	_alarm_source = {"door": door, "pos": door.global_position + Vector3(0, 1.4, 0)}
	_stop_door_alarm()
	_door_alarm = AudioDirector.play_looped_at(&"alarm_loop", door, -2.0)
	AudioDirector.cue("[Alarm rings]", 3.0)
	EventBus.noise_emitted.emit(door.global_position, 1.0, &"alarm")
	var dir: Object = session.get("director")
	if dir != null:
		dir.call("request_encounter", &"minor")


func _on_door_opened(door: Node, door_type: StringName) -> void:
	if door_type != &"fire" or session == null or session.def == null or not session.def.alarm_floor:
		return
	if active or mode != Mode.OFF or _clock() < _alarm_until:
		return
	var d := door as Door
	if d != null:
		trip_alarm(d)


func _on_noise(_pos: Vector3, _loudness: float, kind: StringName) -> void:
	## Breakers kill the alarm (SPEC 6.2 Counterplay). HOLDS: he loses the scent and goes home. INVERTED: the trap at
	## the exit was never the alarm's doing, so he stays.
	if kind != &"breaker":
		return
	var ringing := (_bell != null and is_instance_valid(_bell) and _bell.ringing) or (_door_alarm != null and is_instance_valid(_door_alarm))
	if not ringing:
		return
	_silence_alarm()
	_stop_door_alarm()
	_alarm_until = 0.0
	AudioDirector.cue("[The alarm dies]", 2.0)
	if truth == RunState.Truth.HOLDS and mode in [Mode.ENTER, Mode.GO, Mode.SEARCH]:
		_go_home()


func _ring(seconds: float) -> void:
	if src_is_door:
		return                       # the door alarm is already ringing (trip_alarm)
	if _bell != null and is_instance_valid(_bell):
		_bell.ring(seconds)


func _silence_alarm() -> void:
	if _bell != null and is_instance_valid(_bell):
		_bell.silence()
	if src_is_door:
		_stop_door_alarm()


func _stop_door_alarm() -> void:
	if _door_alarm != null and is_instance_valid(_door_alarm):
		AudioDirector.stop_player(_door_alarm)
		_door_alarm.queue_free()
	_door_alarm = null


func _stop_scrape() -> void:
	if _scrape != null and is_instance_valid(_scrape):
		AudioDirector.stop_player(_scrape)
		_scrape.queue_free()
	_scrape = null


func _tick_alarm() -> void:
	if _door_alarm != null and _clock() >= _alarm_until and not active:
		_stop_door_alarm()
	if mode == Mode.OFF and not active and not _alarm_source.is_empty() and _clock() >= _alarm_until:
		_alarm_source = {}


# --- exit signs -----------------------------------------------------------------------------

func _signs() -> Dictionary:
	if home_chunk == null or not is_instance_valid(home_chunk):
		return {}
	return AlarmSite.ensure_signs(home_chunk, session)


func _set_flicker(index: int, on: bool) -> void:
	var s: ExitSign = _signs().get(index, null)
	if s != null:
		s.set_flicker(on)
	if on:
		_flicker_index = index


func _clear_flicker() -> void:
	for s: ExitSign in _signs().values():
		s.set_flicker(false)
	_flicker_index = -1


# --- behaviour ------------------------------------------------------------------------------

func _place_world(p: Vector3) -> void:
	global_position = Vector3(p.x, 0.0, p.z)
	tile = GameScale.world_to_tile(global_position)


func _process(delta: float) -> void:
	if session == null or session.player == null:
		return
	_tick_alarm()
	if mode == Mode.OFF:
		return
	var pl := player()
	if home_chunk == null or not is_instance_valid(home_chunk):
		retire()
		return
	if StaffRules.frozen(session):
		return                                         # the guest's whistle: staff stand where they are
	if not home_chunk.world_open.has(player_tile()):
		_away_t += delta
		if _away_t > 2.5 and active:
			stand_down()
			return
	else:
		_away_t = 0.0
	if active:
		encounter_time += delta
		if encounter_time >= encounter_limit:
			stand_down()
			return
	_update_perception(delta)
	match mode:
		Mode.ENTER: _enter(delta)
		Mode.GO: _go(delta)
		Mode.SEARCH: _search(delta, pl)
		Mode.RETURN: _return(delta)
		Mode.WAIT: _wait(delta, pl)
		Mode.WINDUP: _windup_tick(delta, pl)
		Mode.RETREAT: _retreat(delta)


func _update_perception(delta: float) -> void:
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.25
	var pl := player()
	perceives = false
	if pl.hidden or distance_to_player() > _tune().foreman_sight_range:
		return
	perceives = _sees_player()


func _sees_player() -> bool:
	var pl := player()
	var from := global_position + Vector3(0, 1.8, 0)
	return _grid().line_of_sight(from, pl.camera.global_position, pl.get_world_3d().direct_space_state, [pl.get_rid()])


# HOLDS ---------------------------------------------------------------------------------------

func _enter(delta: float) -> void:
	## He is outside the exit door. Staff knock before opening any door (Clause), and wait out a door the guest
	## closed less than 8 s ago.
	if exit_door == null or not is_instance_valid(exit_door):
		stand_down()
		return
	if exit_door.state != Door.State.CLOSED:
		_step_in()
		return
	match StaffRules.door_gate(session, exit_door, self, _knock_t):
		&"knock":
			if not _knock_played:
				_knock_played = true
				AudioDirector.play_at(&"knock_slow", exit_door.global_position + Vector3(0, 1.2, 0), 0.0)
				AudioDirector.cue("[Three knocks]", 3.0)
				EventBus.noise_emitted.emit(exit_door.global_position, 0.5, &"knock")
			_knock_t += delta
		&"wait":
			pass
		_:
			exit_door.force_open_by_entity(exit_door.side_of(global_position))
			_step_in()


func _step_in() -> void:
	_place_world(tile_world(exit_ex["tile"]))
	sil.set_presence(1.0)
	_scrape = AudioDirector.play_looped_at(&"wrench_scrape_loop", self, -4.0) if _scrape == null else _scrape
	mode = Mode.GO
	_set_path(src_tile)
	if path.size() <= 1:
		_begin_search()


func _set_path(goal: Vector2i) -> void:
	path = _grid().path(tile, goal, {"allow": _inside, "max_nodes": 2500})
	path_i = 1


func _go(delta: float) -> void:
	_follow(delta, _tune().foreman_run_speed)
	if path.is_empty() or path_i >= path.size():
		_begin_search()


func _begin_search() -> void:
	mode = Mode.SEARCH
	_wander_t = 0.0
	path.clear()


func _search(delta: float, pl: Player) -> void:
	_search_left -= delta
	_wander_t -= delta
	if path.is_empty() or path_i >= path.size():
		if _wander_t <= 0.0:
			_wander_t = 2.0 + RunState.stream(&"entity").randf() * 2.0
			var goal := _wander_goal()
			if goal != tile:
				_set_path(goal)
	_follow(delta, _tune().foreman_walk_speed)
	if can_strike(truth, mode, distance_to_player(), true, pl.hidden, _tune().foreman_strike_range) and perceives:
		if hit_player(&"foreman"):
			AudioDirector.play_at(&"stinger_low", global_position, -2.0)
			sil.flash(0.8)
			_go_home()
			return
	if _search_left <= 0.0:
		_go_home()


func _wander_goal() -> Vector2i:
	var field := _grid().distance_field(src_tile, SEARCH_RADIUS)
	var cands: Array[Vector2i] = []
	for t: Vector2i in field:
		if _chunk_has(t) and int(field[t]) >= 1:
			cands.append(t)
	if cands.is_empty():
		return tile
	return cands[RunState.stream(&"entity").randi() % cands.size()]


func _go_home() -> void:
	mode = Mode.RETURN
	_set_path(exit_ex["tile"])


func _return(delta: float) -> void:
	_follow(delta, _tune().foreman_walk_speed)
	if path.is_empty() or path_i >= path.size():
		stand_down()


# INVERTED ------------------------------------------------------------------------------------

func _door_open() -> bool:
	return exit_door != null and is_instance_valid(exit_door) and exit_door.state == Door.State.OPEN and absf(exit_door.angle) > 0.5


func _wait(delta: float, pl: Player) -> void:
	if exit_door == null or not is_instance_valid(exit_door):
		stand_down()
		return
	_reloc_cool = maxf(0.0, _reloc_cool - delta)
	if not _reloc_ex.is_empty():
		_reloc_t -= delta
		if _reloc_t <= 0.0:
			_arrive_at(_reloc_ex)
	else:
		_check_other_exit(delta)
	if _door_open() and not pl.hidden and distance_to_player() <= NEAR_DOOR:
		mode = Mode.WINDUP
		_windup = 0.0
		sil.flash(0.5)
		AudioDirector.play_at(&"stinger_low", global_position, -6.0)


func _check_other_exit(delta: float) -> void:
	## "The alarm calls him to the exit you are about to take": when the guest is clearly closer to another exit he
	## goes there behind the walls. The new exit's sign flickers for the whole relocation (the tell), and the old one
	## stays dangerous until he has gone.
	_reloc_check -= delta
	if _reloc_cool > 0.0 or _reloc_check > 0.0:
		return
	_reloc_check = 0.5
	var cands := exit_candidates(home_chunk)
	var cur_steps := -1
	var best: Dictionary = {}
	for c in cands:
		if int(c["ex"]["index"]) == int(exit_ex["index"]):
			cur_steps = int(c["steps"])
		if int(c["steps"]) >= 0 and (best.is_empty() or int(c["steps"]) < int(best["steps"])):
			best = c
	if best.is_empty() or int(best["ex"]["index"]) == int(exit_ex["index"]):
		return
	if cur_steps < 0 or cur_steps - int(best["steps"]) >= 4:
		_reloc_ex = best["ex"]
		_reloc_t = _tune().foreman_reloc_seconds
		_reloc_cool = _tune().foreman_reloc_seconds + 3.0
		_set_flicker(int(_reloc_ex["index"]), true)
		AudioDirector.cue("[The scrape moves along the wall]", 2.5)
		if _tell_tween != null:
			_tell_tween.kill()
		_tell_tween = create_tween()
		_tell_tween.tween_property(self, "global_position", tile_world(AlarmSite.beyond_tile(_reloc_ex)) + Vector3(0, 1.0, 0), _reloc_t * 0.9)
		sil.set_presence(0.0)


func _arrive_at(ex: Dictionary) -> void:
	var old := int(exit_ex["index"])
	exit_ex = ex
	exit_door = AlarmSite.exit_door(session, ex)
	_reloc_ex = {}
	_place_world(tile_world(AlarmSite.beyond_tile(ex)))
	sil.set_presence(1.0)
	var s: ExitSign = _signs().get(old, null)
	if s != null:
		s.set_flicker(false)
	_flicker_index = int(ex["index"])


func _windup_tick(delta: float, pl: Player) -> void:
	_windup += delta
	if _windup < _tune().foreman_ambush_windup:
		return
	if can_strike(truth, mode, distance_to_player(), _door_open(), pl.hidden, _tune().foreman_strike_range):
		_place_world(tile_world(exit_ex["tile"]))                # he steps through the door
		sil.flash(1.0)
		if hit_player(&"foreman"):
			AudioDirector.play_at(&"stinger_low", global_position, -2.0)
		mode = Mode.RETREAT
		_retreat_t = RETREAT_SECONDS
		sil.set_presence(0.0)
	else:
		mode = Mode.WAIT                                           # the guest backed off in time


func _retreat(delta: float) -> void:
	_retreat_t -= delta
	if _retreat_t <= 0.0:
		stand_down()


# movement ------------------------------------------------------------------------------------

func _follow(delta: float, base_speed: float) -> void:
	if path.is_empty() or path_i >= path.size():
		return
	var speed := StaffRules.speed_cap(session, self, base_speed)
	var target := tile_world(path[path_i])
	var to := target - global_position
	to.y = 0.0
	var step := speed * delta
	if to.length() <= step:
		global_position = Vector3(target.x, 0.0, target.z)
		tile = path[path_i]
		path_i += 1
	else:
		global_position += to.normalized() * step
		tile = GameScale.world_to_tile(global_position)
