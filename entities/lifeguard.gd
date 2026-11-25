class_name Lifeguard
extends EntityBase
## The Lifeguard (SPEC 6.3): B2 Natatorium, Freeze. Card rule: "No running. When the whistle blows, stop where you stand."
## A tall figure in the high chair across the pool, motionless, visible across the fog. He is STAFF: the Clauses bind him.
##
##   HOLDS     the whistle means FREEZE. He scans; a SECOND blast releases. A guest who moves during the freeze is
##             pulled to the nearest drain vent (Nerve loss, once; the second blast comes soon after).
##   INVERTED  the whistle is bait. While the guest stands still he climbs down and walks the pool edge toward them;
##             the moment they move he stops. The right answer is to keep moving and get to cover (a doorway, a
##             locker): a hidden guest is not stalked.
##
## Tell (both, >= the Director's lead): a test chirp of the whistle (pitch: normal when the card is honest, flat and
## low when it lies) and the water SHOWS the truth: INVERTED rings of light travel inward to the guest, HOLDS the
## surface goes glassy (the drift stops). Evidence for the active variant only: recipes drain_scratch (HOLDS: calm
## water, grates scored with fingernails) and wet_prints (INVERTED). Never lethal at full Nerve.

enum Mode { OFF, SEATED, FROZEN, RELEASED, STALK, RETURN }

const RELEASE_SECONDS := 1.4
const GIVE_UP_HIDDEN := 7.0              ## INVERTED: seconds a guest may stay hidden before he walks home
const STEP_EVERY := 0.85                 ## seconds of walking between footsteps
const WATER_EASE := 1.2                  ## how fast the surface changes (units per second)

var mode: int = Mode.OFF
var sil: Silhouette = null               ## the high chair, with him in it (fixed in the world at the seat)
var walker: Silhouette = null            ## him on foot (INVERTED)
var seat_tile: Vector2i = Vector2i(-99999, -99999)
var seat_pos := Vector3.ZERO
var tile: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var path_i := 0
var on_foot := false

var _pitch := 1.0
var _freeze_t := 0.0
var _freeze_len := 8.0
var _move_t := 0.0
var _viol_cd := 0.0
var _pull_t := 0.0
var _pull_to := Vector3.ZERO
var _release_t := 0.0
var _still_t := 0.0
var _hidden_t := 0.0
var _path_t := 0.0
var _step_acc := 0.0
var _away_t := 0.0
var _amp := 0.0
var _calm := 0.0
var _amp_t := 0.0
var _calm_t := 0.0
var _water_hot := false


func _init() -> void:
	entity_id = &"lifeguard"
	is_staff = true


func _ready() -> void:
	add_to_group(&"entities")
	sil = Silhouette.create(2, 2.4, 0.5)
	sil.top_level = true
	add_child(sil)
	sil.set_presence(0.0, true)
	walker = Silhouette.create(7, 2.3, 0.42)
	add_child(walker)
	walker.set_presence(0.0, true)


func setup(p_session: Node, p_truth: int) -> void:
	super.setup(p_session, p_truth)
	var streamer: ChunkStreamer = session.streamer
	if streamer != null:
		streamer.chunk_loaded.connect(_dress)
		for c: Chunk in streamer.chunks.values():
			_dress(c)


func _exit_tree() -> void:
	PoolSite.set_ripple(0.0, 0.0, Vector3.ZERO)


func _dress(chunk: Chunk) -> void:
	## Wet rooms get their water sheet and drain grates the moment they load.
	if chunk != null:
		PoolSite.ensure(chunk, session)


# --- pure rules (unit-tested) ---------------------------------------------------------------

static func whistle_pitch(p_truth: int, inverted_ratio: float = 0.8) -> float:
	## The whistle's pitch is part of the tell: clean when the card is honest, flat and low when it lies.
	return 1.0 if p_truth == RunState.Truth.HOLDS else inverted_ratio


static func tell_events(p_truth: int, lead: float) -> Array[Dictionary]:
	## Seconds from the start of the tell. The water cue spans the whole lead (Doctrine 2); the chirp carries the pitch.
	var water: StringName = &"calm" if p_truth == RunState.Truth.HOLDS else &"ripple"
	return [{"t": 0.0, "kind": water, "dur": lead}, {"t": 0.4, "kind": &"chirp", "dur": 1.4}]


static func moved_during_freeze(speed: float, since_whistle: float, hidden: bool, still_speed: float, grace: float) -> bool:
	## HOLDS: a guest who is still moving once the grace to stop is over broke the freeze. Hidden guests are not seen.
	return not hidden and since_whistle >= grace and speed > still_speed


static func is_still(speed: float, hidden: bool, still_speed: float) -> bool:
	return not hidden and speed <= still_speed


static func advances(still_t: float, hidden_t: float, delay: float) -> bool:
	## INVERTED: he walks only while the guest has stood still for `delay`, and never at a guest who is hiding.
	return still_t >= delay and hidden_t < 0.5


# --- world queries --------------------------------------------------------------------------

func _grid() -> WorldGrid:
	return session.grid as WorldGrid


func _tune() -> DirectorTuning:
	var t: Object = session.get("tuning") if session != null else null
	return t as DirectorTuning if t != null else DirectorTuning.new()


func _chunk_has(t: Vector2i) -> bool:
	return home_chunk != null and is_instance_valid(home_chunk) and home_chunk.world_open.has(t)


func _in_water(t: Vector2i) -> bool:
	var w: Dictionary = PoolSite.pool_of(home_chunk).get("water", {})
	return w.has(t)


func _speed(pl: Player) -> float:
	return Vector2(pl.velocity.x, pl.velocity.z).length()


# --- Director interface ---------------------------------------------------------------------

func can_exist_in(chunk: Chunk) -> bool:
	return PoolSite.has_pool(chunk.spec)


func tell(lead: float, chunk: Chunk) -> bool:
	## He takes his chair (the room's anchor, or the far deck), the whistle chirps, the water shows the truth.
	home_chunk = chunk
	if PoolSite.ensure(chunk, session).is_empty():
		return false
	if not _ensure_seat(chunk):
		return false
	_pitch = whistle_pitch(truth, _tune().lifeguard_pitch_inverted)
	for ev in tell_events(truth, lead):
		match ev["kind"]:
			&"calm":
				_amp_t = 0.0
				_calm_t = 1.0
				AudioDirector.cue("[The water goes still]", 2.0)
			&"ripple":
				_amp_t = 1.0
				_calm_t = 0.0
				AudioDirector.cue("[Water laps toward you]", 2.0)
			&"chirp":
				var t: float = ev["t"]
				get_tree().create_timer(t).timeout.connect(func():
					if is_instance_valid(self) and mode != Mode.OFF:
						AudioDirector.play_at(&"whistle_blast", seat_pos + Vector3(0, 2.0, 0), -12.0, _pitch))
	EventBus.tell_started.emit(entity_id, &"water", lead)
	return true


func _ensure_seat(chunk: Chunk) -> bool:
	if mode != Mode.OFF and _chunk_has(seat_tile):
		return true
	var anchors: Array = chunk.slot_nodes.get(&"anchor", [])
	if not anchors.is_empty():
		seat_tile = GameScale.world_to_tile((anchors[0] as Node3D).global_position)
	else:
		seat_tile = _far_deck_tile()
	if not _chunk_has(seat_tile):
		return false
	_sit(false)
	return true


func _far_deck_tile() -> Vector2i:
	## No chair anchored in this room: the far end of the deck, well across the water from the guest.
	var field := _grid().distance_field(player_tile(), 40)
	var best := Vector2i(-99999, -99999)
	var bd := -1
	for t: Vector2i in field:
		if not _chunk_has(t) or _in_water(t):
			continue
		var d: int = int(field[t])
		if d >= 5 and d > bd:
			bd = d
			best = t
	return best


func _sit(instant: bool) -> void:
	seat_pos = tile_world(seat_tile)
	sil.global_position = seat_pos
	sil.mat.set_shader_parameter("occupied", 1.0)
	sil.set_presence(1.0, instant)
	mode = Mode.SEATED
	on_foot = false
	walker.set_presence(0.0, true)


func spawn_ambient(chunk: Chunk, t: Vector2i) -> void:
	## The chair is simply occupied (the long room): motionless, across the basin.
	home_chunk = chunk
	seat_tile = t
	active = false
	_sit(false)


func begin_encounter(chunk: Chunk, kind: StringName, duration: float) -> void:
	home_chunk = chunk
	super.begin_encounter(chunk, kind, duration)
	if not _ensure_seat(chunk):
		stand_down()
		return
	_pitch = whistle_pitch(truth, _tune().lifeguard_pitch_inverted)
	_whistle(1.0)
	StaffRules.whistle_heard(session)
	_move_t = 0.0
	_viol_cd = 0.0
	_pull_t = 0.0
	_still_t = 0.0
	_hidden_t = 0.0
	_freeze_t = 0.0
	if truth == RunState.Truth.HOLDS:
		var tn := _tune()
		_freeze_len = RunState.stream(&"entity").randf_range(tn.lifeguard_freeze_min, tn.lifeguard_freeze_max)
		_amp_t = 0.0
		_calm_t = 1.0
		mode = Mode.FROZEN
	else:
		_amp_t = 1.0
		_calm_t = 0.0
		mode = Mode.STALK


func _whistle(ratio: float) -> void:
	AudioDirector.play_at(&"whistle_blast", seat_pos + Vector3(0, 2.0, 0), 4.0, _pitch * ratio)
	AudioDirector.cue("[Whistle]", 1.5)


func stand_down() -> void:
	_amp_t = 0.0
	_calm_t = 0.0
	_pull_t = 0.0
	if on_foot:
		_back_in_chair()
	super.stand_down()
	if mode != Mode.OFF and _chunk_has(seat_tile):
		mode = Mode.SEATED
	else:
		mode = Mode.OFF


func retire() -> void:
	## The guest left the room (or the floor ended): the chair empties out of sight.
	if active:
		stand_down()
	_amp_t = 0.0
	_calm_t = 0.0
	_pull_t = 0.0
	sil.set_presence(0.0)
	walker.set_presence(0.0)
	on_foot = false
	mode = Mode.OFF


func on_session_reset() -> void:
	super.on_session_reset()
	retire()


# --- behaviour ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if session == null or session.player == null:
		return
	_update_water(delta)
	_update_surface()
	if mode == Mode.OFF:
		return
	var pl := player()
	if home_chunk == null or not is_instance_valid(home_chunk):
		retire()
		return
	if StaffRules.frozen(session):
		return                                      # the guest's whistle: staff stand where they are
	if not home_chunk.world_open.has(player_tile()):
		_away_t += delta
		if active and _away_t > 2.5:
			stand_down()
			return
		if not active and _away_t > 4.0:
			retire()
			return
	else:
		_away_t = 0.0
	if active:
		encounter_time += delta
		if encounter_time >= encounter_limit:
			stand_down()
			return
	match mode:
		Mode.FROZEN: _frozen(delta, pl)
		Mode.RELEASED: _released(delta)
		Mode.STALK: _stalk(delta, pl)
		Mode.RETURN: _return(delta)


# HOLDS ---------------------------------------------------------------------------------------

func _frozen(delta: float, pl: Player) -> void:
	var tn := _tune()
	_freeze_t += delta
	_viol_cd = maxf(0.0, _viol_cd - delta)
	if moved_during_freeze(_speed(pl), _freeze_t, pl.hidden, tn.lifeguard_still_speed, tn.lifeguard_move_grace):
		_move_t += delta
	else:
		_move_t = 0.0
	if _move_t >= 0.2 and _viol_cd <= 0.0:
		_violate(pl)
	_pull(delta, pl)
	if _freeze_t >= _freeze_len:
		_release()


func _violate(pl: Player) -> void:
	## The guest moved while frozen: a drain vent takes hold (Nerve loss) and the second blast is not far off.
	_viol_cd = 2.6
	_freeze_len = minf(_freeze_len, _freeze_t + 2.4)       # the second blast comes before a second hit can land
	var g := PoolSite.nearest_grate(home_chunk, pl.global_position)
	if g != Vector3.INF:
		_pull_t = _tune().lifeguard_pull_seconds
		_pull_to = g
		AudioDirector.play_at(&"water_ripple", g + Vector3(0, 0.3, 0), 3.0)
		AudioDirector.cue("[Drain gurgles]", 2.0)
	hit_player(&"lifeguard")


func _pull(delta: float, pl: Player) -> void:
	if _pull_t <= 0.0:
		return
	_pull_t -= delta
	if pl.hidden:
		return
	var to := _pull_to - pl.global_position
	to.y = 0.0
	if to.length() > 0.9:
		pl.move_and_collide(to.normalized() * _tune().lifeguard_pull_speed * delta)


func _release() -> void:
	## The second blast: you may move.
	mode = Mode.RELEASED
	_release_t = RELEASE_SECONDS
	_amp_t = 0.0
	_calm_t = 0.0
	_whistle(1.12)


func _released(delta: float) -> void:
	_release_t -= delta
	if _release_t <= 0.0:
		stand_down()


# INVERTED ------------------------------------------------------------------------------------

func _stalk(delta: float, pl: Player) -> void:
	var tn := _tune()
	var still := is_still(_speed(pl), pl.hidden, tn.lifeguard_still_speed)
	_still_t = _still_t + delta if still else 0.0
	_hidden_t = _hidden_t + delta if pl.hidden else 0.0
	var go := advances(_still_t, _hidden_t, tn.lifeguard_still_delay)
	if go and not on_foot:
		_climb_down()
	if not on_foot:
		return
	if _hidden_t > GIVE_UP_HIDDEN:
		_walk_home()
		return
	if not go:
		return                                      # you moved (or hid): he stops where he is
	_path_t -= delta
	if _path_t <= 0.0:
		_path_t = 0.4
		path = _grid().path(tile, player_tile(), {"allow": _inside, "cost": _edge_cost, "max_nodes": 2500})
		path_i = 1
	_follow(delta, tn.lifeguard_walk_speed)
	if distance_to_player() <= tn.lifeguard_strike_range and not pl.hidden:
		if hit_player(&"lifeguard"):
			AudioDirector.play_at(&"stinger_low", global_position, -2.0)
			walker.flash(0.9)
			_walk_home()


func _inside(t: Vector2i) -> bool:
	return _chunk_has(t)


func _edge_cost(t: Vector2i) -> float:
	## He walks the pool EDGE: wading through the water costs a detour's worth.
	return 2.5 if _in_water(t) else 0.0


func _climb_down() -> void:
	on_foot = true
	sil.mat.set_shader_parameter("occupied", 0.0)         # the chair is empty (the Echo tape shows exactly this)
	global_position = Vector3(seat_pos.x, 0.0, seat_pos.z)
	tile = seat_tile
	walker.set_presence(1.0)
	AudioDirector.cue("[Wet footsteps]", 2.0)
	path.clear()
	_path_t = 0.0


func _walk_home() -> void:
	mode = Mode.RETURN
	path = _grid().path(tile, seat_tile, {"allow": _inside, "max_nodes": 2500})
	path_i = 1


func _return(delta: float) -> void:
	_follow(delta, _tune().lifeguard_walk_speed)
	if path.is_empty() or path_i >= path.size() or tile == seat_tile:
		stand_down()


func _back_in_chair() -> void:
	on_foot = false
	walker.set_presence(0.0)
	sil.mat.set_shader_parameter("occupied", 1.0)


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
	_step_acc += delta
	if _step_acc >= STEP_EVERY:
		_step_acc = 0.0
		AudioDirector.play_at(&"step_water" if _in_water(tile) else &"step_tile", global_position, -4.0, 0.85)


# water + surface -----------------------------------------------------------------------------

func _update_water(delta: float) -> void:
	_amp = move_toward(_amp, _amp_t, delta * WATER_EASE)
	_calm = move_toward(_calm, _calm_t, delta * WATER_EASE)
	var live := _amp > 0.001 or _calm > 0.001
	if live or _water_hot:
		var pl := player()
		PoolSite.set_ripple(_amp, _calm, pl.global_position if pl != null else Vector3.ZERO)
		_water_hot = live


func _update_surface() -> void:
	## Footsteps splash while the guest wades through a flooded room.
	var pl := player()
	if pl == null or session.streamer == null:
		return
	var c: Chunk = session.streamer.chunk_at_tile(player_tile())
	var wet := false
	if c != null:
		wet = (PoolSite.pool_of(c).get("water", {}) as Dictionary).has(player_tile())
	if wet:
		pl.surface = &"water"
	elif pl.surface == &"water":
		pl.surface = Themes.get_theme(session.def.theme_id).surface
