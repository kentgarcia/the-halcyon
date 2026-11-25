class_name Hum
extends EntityBase
## The Hum (SPEC 6.5): a tall dark silhouette that lives in the building's light cells. 1F Yellow, Seek light.
##
##   HOLDS     moves only through DEAD cells. Lit cells are sanctuary. The camcorder lamp stuns it for 4 s.
##   INVERTED  drawn to LIT cells. Ignores a still, quiet guest standing in the dark. The lamp, a lit cell
##             or a loud sprint make the guest perceivable. The lamp is the worst thing you can do.
##
## Tell (both): the building's hum drops a half-step, then HOLDS: a bulb ahead dies; INVERTED: a bulb ahead
## surges. The proximity buzz (HOLDS dips, INVERTED rises) is the quiet P1 evidence. Never lethal at full Nerve.

enum Mode { OFF, IDLE, HUNT, STUNNED, RETREAT }

const SPEED_HUNT := 5.0
const SPEED_IDLE := 1.25
const STUN_RANGE := 7.0
const ATTACK_DIST := 1.15
const STUN_COOLDOWN := 1.2
const HALF_STEP := 0.9439

var mode: int = Mode.OFF
var sil: Silhouette = null
var tile: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var path_i := 0
var spawn_tile: Vector2i = Vector2i(-99999, -99999)
var stun_t := 0.0
var stun_cd := 0.0
var retreat_t := 0.0
var dwell := 0.0
var perceives := false
var _lose_t := 0.0
var _decide_t := 0.0
var _perceive_t := 0.0
var _buzz: AudioStreamPlayer3D = null
var _tell_cell: LightCell = null
var _fading := false
var _away_t := 0.0


func _ready() -> void:
	entity_id = &"hum"
	is_staff = false
	add_to_group(&"entities")
	sil = Silhouette.create(0, 2.3, 0.42)
	add_child(sil)
	sil.set_presence(0.0, true)
	EventBus.light_changed.connect(_on_light_changed)


func _exit_tree() -> void:
	if EventBus.light_changed.is_connected(_on_light_changed):
		EventBus.light_changed.disconnect(_on_light_changed)
	_stop_buzz()


# --- world queries --------------------------------------------------------------------------

func _grid() -> WorldGrid:
	return session.grid as WorldGrid


func _cell_of(t: Vector2i) -> LightCell:
	var c: Chunk = session.streamer.chunk_at_tile(t)
	return c.cell_at(t) if c != null else null


func is_dark(t: Vector2i) -> bool:
	var cell := _cell_of(t)
	return cell == null or cell.is_dead()


func _chunk_has(t: Vector2i) -> bool:
	return home_chunk != null and is_instance_valid(home_chunk) and home_chunk.world_open.has(t)


func current_cell() -> LightCell:
	return _cell_of(tile)


func _allowed(t: Vector2i) -> bool:
	if not _chunk_has(t):
		return false
	return is_dark(t) if truth == RunState.Truth.HOLDS else true


# --- Director interface ---------------------------------------------------------------------

func can_exist_in(chunk: Chunk) -> bool:
	return chunk.cells.size() >= 2


func tell(lead: float, chunk: Chunk) -> bool:
	## Pick the cell the Hum will come from and play the genuine tell. 6-16 steps from the guest.
	home_chunk = chunk
	var pt := player_tile()
	var field := _grid().distance_field(pt, 18)
	var cands: Array[LightCell] = []
	for c in chunk.cells:
		var d: int = int(field.get(c.tile, 999))
		if d >= 6 and d <= 18:
			if truth == RunState.Truth.HOLDS and c.is_lit() and c.powered:
				cands.append(c)
			elif truth == RunState.Truth.INVERTED and c.is_lit() and c.powered:
				cands.append(c)
	var rng := RunState.stream(&"director")
	spawn_tile = Vector2i(-99999, -99999)
	_tell_cell = null
	if not cands.is_empty():
		# prefer a cell ahead of the guest: it must be something they can notice
		var fwd := player().look_direction()
		fwd.y = 0.0
		var scored: Array = []
		for c in cands:
			var to := (c.position - player().global_position)
			to.y = 0.0
			scored.append({"c": c, "s": fwd.dot(to.normalized()) + rng.randf() * 0.6})
		scored.sort_custom(func(a, b): return a["s"] > b["s"])
		_tell_cell = scored[0]["c"]
	elif truth == RunState.Truth.HOLDS:
		# nothing lit to kill: the Hum is already coming through the dark. Use the farthest dead cell.
		var best: LightCell = null
		var bd := -1
		for c2 in chunk.cells:
			var dd: int = int(field.get(c2.tile, 0))
			if c2.is_dead() and dd >= 6 and dd > bd:
				bd = dd
				best = c2
		_tell_cell = best
	if _tell_cell == null:
		return false
	spawn_tile = _tell_cell.tile
	AudioDirector.play(&"hum_drop")
	AudioDirector.set_hum_pitch(HALF_STEP)
	var cell := _tell_cell
	if truth == RunState.Truth.HOLDS:
		if cell.is_lit():
			cell.pulse_flicker(minf(lead * 0.4, 1.6))
			get_tree().create_timer(minf(lead * 0.45, 1.8)).timeout.connect(func():
				if is_instance_valid(home_chunk) and cell.is_lit():
					cell.set_tube(false)
					AudioDirector.play_at(&"bulb_pop", cell.position))
	else:
		var tw := create_tween()
		tw.tween_property(cell, "boost", 0.25, 0.5)
		tw.tween_interval(maxf(0.5, lead - 1.4))
		tw.tween_property(cell, "boost", 0.0, 1.0)
		AudioDirector.play_at(&"bulb_flicker", cell.position, -6.0)
	EventBus.tell_started.emit(entity_id, &"light", lead)
	return true


func begin_encounter(chunk: Chunk, kind: StringName, duration: float) -> void:
	super.begin_encounter(chunk, kind, duration)
	_fading = false
	var t := spawn_tile
	if not _chunk_has(t):
		t = _fallback_spawn()
	_place(t)
	mode = Mode.HUNT
	sil.set_presence(1.0)
	_start_buzz()
	_decide_t = 0.0
	dwell = 0.0
	path.clear()


func spawn_ambient(chunk: Chunk, t: Vector2i) -> void:
	## A silhouette that is simply there (the Long Room), reacting to light but not hunting.
	home_chunk = chunk
	_place(t)
	mode = Mode.IDLE
	active = false
	sil.set_presence(1.0)
	_start_buzz()
	path.clear()
	dwell = 2.0


func retire() -> void:
	if mode == Mode.OFF:
		return
	_fading = true
	sil.set_presence(0.0)
	mode = Mode.OFF
	_stop_buzz()
	AudioDirector.set_hum_pitch(1.0)
	if active:
		stand_down()


func stand_down() -> void:
	AudioDirector.set_hum_pitch(1.0)
	super.stand_down()
	if mode == Mode.HUNT or mode == Mode.STUNNED or mode == Mode.RETREAT:
		mode = Mode.IDLE if _chunk_has(tile) else Mode.OFF
	if mode == Mode.OFF:
		sil.set_presence(0.0)
		_stop_buzz()


func _fallback_spawn() -> Vector2i:
	var pt := player_tile()
	var field := _grid().distance_field(pt, 40)
	var best := Vector2i(-99999, -99999)
	var bd := -1
	for t: Vector2i in field:
		if not _chunk_has(t):
			continue
		if truth == RunState.Truth.HOLDS and not is_dark(t):
			continue
		var d: int = int(field[t])
		if d > bd and d <= 30:
			bd = d
			best = t
	if best.x < -9000:
		best = pt
	return best


func _place(t: Vector2i) -> void:
	tile = t
	global_position = tile_world(t)


# --- behaviour ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if mode == Mode.OFF or session == null:
		return
	var pl := player()
	if pl == null:
		return
	stun_cd = maxf(0.0, stun_cd - delta)
	_update_buzz()
	# leave when the guest has left the room for good
	if home_chunk == null or not is_instance_valid(home_chunk):
		retire()
		return
	if not home_chunk.world_open.has(player_tile()):
		_away_t += delta
		if _away_t > 3.0 and not active:
			retire()
			return
		if _away_t > 6.0:
			stand_down()
			retire()
			return
	else:
		_away_t = 0.0
	if active:
		encounter_time += delta
		if encounter_time >= encounter_limit and mode != Mode.STUNNED:
			stand_down()
			return
	match mode:
		Mode.IDLE: _idle(delta)
		Mode.HUNT: _hunt(delta)
		Mode.STUNNED: _stunned(delta)
		Mode.RETREAT: _retreat(delta)
	_check_lamp(delta)


func _check_lamp(_delta: float) -> void:
	if truth != RunState.Truth.HOLDS or mode == Mode.OFF or mode == Mode.STUNNED or stun_cd > 0.0:
		return
	var cc: Camcorder = session.camcorder as Camcorder
	if cc != null and cc.lamp_hits(global_position + Vector3(0, 1.2, 0), STUN_RANGE):
		stun_t = tuning().hum_lamp_stun
		stun_cd = stun_t + STUN_COOLDOWN
		mode = Mode.STUNNED
		sil.flash(1.0)
		AudioDirector.play_at(&"static_burst", global_position, -4.0)
		path.clear()


func _stunned(delta: float) -> void:
	stun_t -= delta
	if int(stun_t * 6.0) % 2 == 0:
		sil.flash(0.35)
	if stun_t <= 0.0:
		retreat_t = 1.6
		mode = Mode.RETREAT
		path.clear()


func _retreat(delta: float) -> void:
	retreat_t -= delta
	if path.is_empty() or path_i >= path.size():
		var goal := _far_tile_from(player_tile(), 8)
		path = _grid().path(tile, goal, {"allow": _allowed, "max_nodes": 500})
		path_i = 1
	_follow(delta, SPEED_HUNT * 0.8)
	if retreat_t <= 0.0:
		mode = Mode.HUNT if active else Mode.IDLE
		path.clear()
		_decide_t = 0.0


func _far_tile_from(from: Vector2i, min_steps: int) -> Vector2i:
	var field := _grid().distance_field(from, 24)
	var best := tile
	var bd := -1
	for t: Vector2i in field:
		if not _allowed(t):
			continue
		var d: int = int(field[t])
		if d >= min_steps and d > bd:
			bd = d
			best = t
	return best


func _hunt(delta: float) -> void:
	var pl := player()
	var pt := player_tile()
	_decide_t -= delta
	_perceive_t -= delta
	if _perceive_t <= 0.0:
		_perceive_t = 0.2
		_update_perception()
	if _decide_t <= 0.0:
		_decide_t = 0.3
		_pick_path(pt)
	_follow(delta, SPEED_HUNT)
	# attack
	if distance_to_player() < ATTACK_DIST and not pl.hidden:
		var can := false
		if truth == RunState.Truth.HOLDS:
			can = is_dark(player_tile())
		else:
			can = perceives
		if can and hit_player(&"hum"):
			mode = Mode.RETREAT
			retreat_t = 5.0
			path.clear()
			AudioDirector.play_at(&"stinger_low", global_position, -2.0)


func _update_perception() -> void:
	var pl := player()
	var was := perceives
	var seen := false
	if not pl.hidden and truth == RunState.Truth.INVERTED:
		var d := distance_to_player()
		var lit_player := not is_dark(player_tile())
		var cc: Camcorder = session.camcorder as Camcorder
		var lamp := cc != null and cc.is_lamp_on()
		var loud := pl.noise_level() >= 0.9
		seen = (lit_player and d <= 18.0) or (lamp and d <= 14.0) or (loud and d <= 9.0)
	if seen:
		_lose_t = 4.0
		perceives = true
	else:
		_lose_t -= 0.2
		if _lose_t <= 0.0:
			perceives = false
	if perceives != was:
		path.clear()


func _pick_path(pt: Vector2i) -> void:
	if truth == RunState.Truth.HOLDS:
		var goal := pt
		if not is_dark(pt):
			goal = _nearest_dark_to(pt)
		if goal == tile:
			path.clear()
			return
		path = _grid().path(tile, goal, {"allow": _allowed, "max_nodes": 700})
		path_i = 1
	else:
		if perceives:
			path = _grid().path(tile, pt, {"allow": _allowed, "max_nodes": 700})
			path_i = 1
			return
		# not perceived: drift from lit cell to lit cell, feeding
		if path.is_empty() or path_i >= path.size():
			dwell -= 0.3
			if dwell <= 0.0:
				var goal2 := _random_lit_tile()
				if goal2 != tile:
					path = _grid().path(tile, goal2, {"allow": _allowed, "max_nodes": 700})
					path_i = 1
				dwell = 3.0 + RunState.stream(&"director").randf() * 3.0


func _nearest_dark_to(pt: Vector2i) -> Vector2i:
	var field := _grid().distance_field(pt, 14)
	var best := tile
	var bd := 9999
	for t: Vector2i in field:
		if _chunk_has(t) and is_dark(t) and int(field[t]) < bd:
			bd = int(field[t])
			best = t
	return best


func _random_lit_tile() -> Vector2i:
	var rng := RunState.stream(&"director")
	var cells: Array[LightCell] = []
	for c in home_chunk.cells:
		if c.is_lit() and c.powered:
			cells.append(c)
	if cells.is_empty():
		return tile
	return cells[rng.randi() % cells.size()].tile


func _idle(delta: float) -> void:
	# an ambient silhouette: stays, shifts, reacts to light (the lab's Test, SPEC Appendix B)
	if path.is_empty() or path_i >= path.size():
		dwell -= delta
		if dwell <= 0.0:
			dwell = 3.0 + RunState.stream(&"director").randf() * 4.0
			var goal := _near_allowed_tile(5)
			if goal != tile:
				path = _grid().path(tile, goal, {"allow": _allowed, "max_nodes": 300})
				path_i = 1
	_follow(delta, SPEED_IDLE)


func _near_allowed_tile(steps: int) -> Vector2i:
	var field := _grid().distance_field(tile, steps)
	var cands: Array[Vector2i] = []
	for t: Vector2i in field:
		if _allowed(t) and int(field[t]) >= 2:
			cands.append(t)
	if cands.is_empty():
		return tile
	return cands[RunState.stream(&"director").randi() % cands.size()]


func _on_light_changed(cell: Object, state: int) -> void:
	## The lab's Test: a newly lit cell near the silhouette. HOLDS retreats from it; INVERTED drifts to it.
	if mode == Mode.OFF or mode == Mode.STUNNED or home_chunk == null or not is_instance_valid(home_chunk):
		return
	var lc := cell as LightCell
	if lc == null or lc.chunk != home_chunk:
		return
	if state == LightCell.State.DEAD:
		return
	var d := absi(lc.tile.x - tile.x) + absi(lc.tile.y - tile.y)
	if truth == RunState.Truth.HOLDS:
		if d <= 9:
			var goal := _far_tile_from(lc.tile, 9)
			path = _grid().path(tile, goal, {"allow": _allowed, "max_nodes": 600})
			path_i = 1
			dwell = 6.0
			if mode == Mode.IDLE:
				sil.flash(0.4)
	else:
		if d <= 26 and mode != Mode.RETREAT:
			path = _grid().path(tile, lc.tile, {"allow": _allowed, "max_nodes": 900})
			path_i = 1
			dwell = 8.0


func _follow(delta: float, speed: float) -> void:
	if path.is_empty() or path_i >= path.size():
		return
	var target := tile_world(path[path_i])
	var to := target - global_position
	to.y = 0.0
	var step := speed * delta
	if to.length() <= step:
		global_position = target
		tile = path[path_i]
		path_i += 1
	else:
		global_position += to.normalized() * step
		tile = GameScale.world_to_tile(global_position)


# --- audio ----------------------------------------------------------------------------------

func _start_buzz() -> void:
	if _buzz == null or not is_instance_valid(_buzz):
		_buzz = AudioDirector.play_looped_at(&"amb_buzz_cell", self, -14.0)


func _stop_buzz() -> void:
	if _buzz != null and is_instance_valid(_buzz):
		AudioDirector.stop_player(_buzz)
	_buzz = null


func _update_buzz() -> void:
	if _buzz == null or not is_instance_valid(_buzz):
		return
	var d := clampf(distance_to_player() / 22.0, 0.0, 1.0)
	# P1 evidence (Appendix B): the buzz DIPS as it approaches (HOLDS) and RISES (INVERTED)
	if truth == RunState.Truth.HOLDS:
		_buzz.pitch_scale = lerpf(0.72, 1.0, d)
	else:
		_buzz.pitch_scale = lerpf(1.32, 1.0, d)
