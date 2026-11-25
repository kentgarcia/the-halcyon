class_name DirectorCore
extends Node
## The Dread Director (SPEC 7): an invisible pacer. It decides WHEN things happen, never WHAT is true: rule
## truth, evidence and door tells belong to generation (Fairness Doctrine 4). It enforces:
##   - every Encounter is preceded by that entity's genuine Tell, >= Settings.tell_lead_seconds() earlier;
##   - >= `encounter_cooldown` between Encounters; <= 1 major + 2 minor per floor;
##   - a Relief at least every `relief_interval` seconds of exposure;
##   - phantom : tell : encounter ~ 3 : 2 : 1 (phantoms are harmless and may not imitate a real Tell).
## Plus a small repertoire of systemic scares (SPEC 7.1), each at most once per floor, never lethal.

enum Phase { QUIET, TELLING, ENCOUNTER, COOLDOWN }

var session: Node = null
var tuning: DirectorTuning = null
var enabled := true
var phase: int = Phase.QUIET
var t := 0.0
var exposure := 0.0
var major_used := 0
var minor_used := 0
var phantoms := 0
var tells := 0
var encounters := 0
var scares_used: Dictionary = {}          ## StringName -> true
var history: Array[Dictionary] = []       ## [{t, beat, detail}] for tests / the autopsy / debugging
var next_event_at := 0.0
var relief_until := 0.0
var last_encounter_end := -999.0
var last_remark := -999.0

var _entity: EntityBase = null
var _tell_t := 0.0
var _tell_kind: StringName = &"minor"
var _tell_chunk: Chunk = null
var _enc_t := 0.0
var _enc_limit := 40.0
var _pending_major := false
var _major_retry := 0.0
var _hide_t := 0.0
var _sprint_t := 0.0
var _dark_t := 0.0
var _lamp_t := 0.0
var _noise_accum := 0.0
var _company: Silhouette = null
var _company_t := 0.0


func setup(p_session: Node, p_tuning: DirectorTuning) -> void:
	session = p_session
	tuning = p_tuning
	next_event_at = tuning.first_event_delay
	EventBus.noise_emitted.connect(_on_noise)
	EventBus.door_peeked.connect(_on_peek)


func _exit_tree() -> void:
	if EventBus.noise_emitted.is_connected(_on_noise):
		EventBus.noise_emitted.disconnect(_on_noise)
	if EventBus.door_peeked.is_connected(_on_peek):
		EventBus.door_peeked.disconnect(_on_peek)
	if _company != null and is_instance_valid(_company):
		_company.queue_free()


func entity_active() -> bool:
	return phase == Phase.ENCOUNTER or phase == Phase.TELLING


func is_encounter_active() -> bool:
	return phase == Phase.ENCOUNTER


# --- main loop -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if session == null or session.player == null:
		return
	var pl: Player = session.player
	if pl.frozen or not enabled:
		return
	t += delta
	_update_dread(delta, pl)
	_monitor_behaviour(delta, pl)
	_tick_company(delta, pl)
	match phase:
		Phase.QUIET, Phase.COOLDOWN:
			_quiet_tick(delta)
		Phase.TELLING:
			_tell_tick(delta)
		Phase.ENCOUNTER:
			_encounter_tick(delta)
	var d := DreadDirector.normalized()
	if Main.instance != null:
		Main.instance.set_dread_visual(d)
		Main.instance.set_glitch(clampf((d - 0.55) * 1.4, 0.0, 0.8))


func _rng() -> RandomNumberGenerator:
	return RunState.stream(&"director")


func _log(beat: StringName, detail: String = "") -> void:
	history.append({"t": snappedf(t, 0.1), "beat": beat, "detail": detail})


# --- dread -----------------------------------------------------------------------------------

func _update_dread(delta: float, pl: Player) -> void:
	var level := 1.0
	if session.stage != null and session.stage.light_field != null:
		level = session.stage.light_field.level_at_tile(GameScale.world_to_tile(pl.global_position))
	var d := 0.0
	if level < 0.2 and not session.in_relief_zone():
		d += tuning.dread_in_dark_per_s
	elif level >= 0.6:
		d += tuning.dread_in_light_per_s
	d -= tuning.dread_decay_per_s * (DreadDirector.dread / 100.0)
	if phase == Phase.ENCOUNTER:
		d += 1.4
	elif phase == Phase.TELLING:
		d += 2.2
	if session.in_relief_zone():
		d -= 3.0
	DreadDirector.add_dread(d * delta + _noise_accum)
	_noise_accum = 0.0


func _on_noise(_pos: Vector3, loudness: float, kind: StringName) -> void:
	if kind == &"step" and loudness < 0.5:
		return
	_noise_accum += loudness * tuning.dread_noise_gain * 0.05


# --- quiet -----------------------------------------------------------------------------------

func _quiet_tick(delta: float) -> void:
	if session.in_relief_zone():
		exposure = maxf(0.0, exposure - delta * 3.0)
		return
	exposure += delta
	if _pending_major:
		_try_major(delta)
		return
	if t < tuning.first_event_delay or t < next_event_at or t < relief_until:
		return
	if exposure >= tuning.relief_interval:
		# guaranteed Relief: hold the building quiet for a while (Silence beat)
		relief_until = t + 22.0
		exposure = 0.0
		_log(&"relief", "exposure cap")
		return
	if session.exam_pending():
		return                                       # the exam beat owns the threat
	var wp := tuning.phantom_weight
	var wt := tuning.tell_weight
	var pick := RngStreams.weighted_index(_rng(), [wp, wt] if _can_encounter(&"minor") else [wp, 0.0])
	if pick == 1:
		_start_tell(&"minor")
	else:
		_phantom()
	next_event_at = t + _rng().randf_range(13.0, 24.0)


func _can_encounter(kind: StringName) -> bool:
	if _entity_for_floor() == null:
		return false
	if t - last_encounter_end < tuning.encounter_cooldown:
		return false
	if kind == &"major" and major_used >= tuning.max_major_per_floor:
		return false
	if kind == &"minor" and minor_used >= tuning.max_minor_per_floor:
		return false
	var cur: Chunk = session.streamer.current
	if cur == null or session.in_relief_zone():
		return false
	var bp: FloorPlan.BeatPlan = cur.plan.get("bp", null)
	if bp != null and not bp.main and bp.kind == &"side":
		return false
	return _entity_for_floor().can_exist_in(cur)


func _entity_for_floor() -> EntityBase:
	return session.entity as EntityBase


# --- tells & encounters ----------------------------------------------------------------------

func _start_tell(kind: StringName) -> bool:
	var ent := _entity_for_floor()
	var cur: Chunk = session.streamer.current
	if ent == null or cur == null:
		return false
	var lead := Settings.tell_lead_seconds(tuning.tell_lead_seconds) + 0.6
	if not ent.tell(lead, cur):
		return false
	_entity = ent
	_tell_kind = kind
	_tell_chunk = cur
	_tell_t = lead + _rng().randf_range(0.2, 1.2)
	phase = Phase.TELLING
	tells += 1
	EventBus.tell_started.emit(ent.entity_id, &"genuine", lead)
	_log(&"tell", "%s %s" % [ent.entity_id, kind])
	return true


func _tell_tick(delta: float) -> void:
	if session.streamer.current != _tell_chunk:
		# the guest left the room before it arrived: the Tell was real, the entity simply lost the scent
		if _entity != null and _entity.has_method("retire"):
			_entity.call("retire")
		phase = Phase.COOLDOWN
		next_event_at = t + 12.0
		_log(&"tell_void")
		return
	_tell_t -= delta
	if _tell_t > 0.0:
		return
	var duration := 60.0 if _tell_kind == &"major" else 38.0
	if _entity.has_method("encounter_duration"):
		# set pieces with their own clock (the Queue's ~3 min of forced stillness, the Lobby Audit)
		duration = float(_entity.call("encounter_duration", _tell_kind, duration))
	_enc_t = 0.0
	_enc_limit = duration
	phase = Phase.ENCOUNTER
	encounters += 1
	if _tell_kind == &"major":
		major_used += 1
	else:
		minor_used += 1
	if not _entity.encounter_ended.is_connected(_on_encounter_ended):
		_entity.encounter_ended.connect(_on_encounter_ended)
	_entity.begin_encounter(_tell_chunk, _tell_kind, duration)
	_log(&"encounter", "%s %s" % [_entity.entity_id, _tell_kind])


func _encounter_tick(delta: float) -> void:
	_enc_t += delta
	if _enc_t >= _enc_limit and _entity != null and _entity.active:
		_entity.stand_down()


func _on_encounter_ended(_e: EntityBase) -> void:
	phase = Phase.COOLDOWN
	last_encounter_end = t
	next_event_at = t + tuning.encounter_cooldown * 0.6
	DreadDirector.add_dread(-30.0)
	_log(&"encounter_end")


func on_exam_started() -> void:
	## The exam beat's Encounter: the one major of the floor. It still gets its Tell first.
	_pending_major = _entity_for_floor() != null and major_used < tuning.max_major_per_floor
	_major_retry = 0.0
	_log(&"exam_start")


func _try_major(delta: float) -> void:
	_major_retry -= delta
	if _major_retry > 0.0:
		return
	_major_retry = 2.5
	if t - last_encounter_end < tuning.encounter_cooldown * 0.5:
		return
	if _start_tell(&"major"):
		_pending_major = false


func force_encounter(kind: StringName = &"minor") -> bool:
	## Debug / test hook: bypasses pacing, never bypasses the Tell.
	return _start_tell(kind)


func request_encounter(kind: StringName = &"minor") -> bool:
	## An in-world cause (the guest tripping a fire-door alarm) asks for an Encounter. Unlike force_encounter this
	## keeps every pacing rule (cooldown, per-floor caps, relief zones, one at a time) and still plays the Tell first.
	if not enabled or phase == Phase.TELLING or phase == Phase.ENCOUNTER or not _can_encounter(kind):
		return false
	var ok := _start_tell(kind)
	if ok:
		_log(&"requested", String(kind))
	return ok


func on_blackout() -> void:
	## The guest is down: everything stands down.
	enabled = false
	if _entity != null and is_instance_valid(_entity):
		if _entity.active:
			_entity.stand_down()
		if _entity.has_method("retire"):
			_entity.call("retire")


# --- phantoms (harmless, SPEC 7) -------------------------------------------------------------

func _phantom() -> void:
	phantoms += 1
	var pl: Player = session.player
	var r := _rng()
	# try a systemic scare first now and then (each at most once per floor)
	if r.randf() < 0.30 and _try_scare():
		return
	var cur: Chunk = session.streamer.current
	var kinds: Array = [&"far_door", &"creak", &"far_steps", &"flicker", &"pa_click"]
	var kind: StringName = kinds[r.randi() % kinds.size()]
	var around := pl.global_position + Vector3(r.randf_range(-8.0, 8.0), 1.5, r.randf_range(-8.0, 8.0))
	match kind:
		&"far_door":
			AudioDirector.play_at(&"distant_door_close", around, -2.0)
			AudioDirector.cue("[Door closes - far]", 2.0)
		&"creak":
			AudioDirector.play_at(&"ceiling_creak", pl.global_position + Vector3(0, 2.4, 0) + Vector3(r.randf_range(-3, 3), 0, r.randf_range(-3, 3)), 0.0)
			AudioDirector.cue("[Ceiling creaks]", 2.0)
		&"far_steps":
			AudioDirector.play_at(&"step_carpet", around, 2.0, 0.85)
			AudioDirector.cue("[Footsteps - far]", 1.5)
		&"flicker":
			if cur != null and not cur.cells.is_empty():
				var cell: LightCell = cur.cells[r.randi() % cur.cells.size()]
				if cell.is_lit():
					cell.pulse_flicker(0.5)
					AudioDirector.play_at(&"bulb_flicker", cell.position, -4.0)
		_:
			AudioDirector.play(&"pa_click_on", -10.0)
			AudioDirector.play(&"pa_click_off", -10.0)
	_log(&"phantom", String(kind))


# --- repertoire scares (SPEC 7.1) ------------------------------------------------------------

func _try_scare() -> bool:
	var pl: Player = session.player
	var cc: Camcorder = session.camcorder
	# The knock: three slow knocks on the wardrobe you are in. Nothing opens it.
	if pl.hidden and _hide_t >= 4.0 and not scares_used.has(&"knock"):
		scares_used[&"knock"] = true
		AudioDirector.play_at(&"knock_slow", pl.global_position + Vector3(0, 1.2, 0) + (-pl.global_transform.basis.z) * 0.6, 2.0)
		AudioDirector.cue("[Three slow knocks]", 3.5)
		_log(&"scare", "knock")
		return true
	# The handle: while you hide, a door you can hear tries to open. Nothing comes in.
	if pl.hidden and _hide_t >= 4.0 and not scares_used.has(&"handle"):
		scares_used[&"handle"] = true
		AudioDirector.play_at(&"door_handle_try", pl.global_position + (-pl.global_transform.basis.z) * 2.0, 0.0)
		AudioDirector.cue("[A handle turns slowly]", 3.0)
		_log(&"scare", "handle")
		return true
	# Company in the dark: your lamp sweeps a dead cell that is occupied. It does not react.
	if cc != null and cc.is_lamp_on() and not scares_used.has(&"company") and _company == null:
		var cur: Chunk = session.streamer.current
		if cur != null:
			for cell in cur.cells:
				if cell.is_dead() and cc.lamp_hits(cell.position - Vector3(0, 1.0, 0), 5.5) and pl.global_position.distance_to(cell.position) > 3.0:
					scares_used[&"company"] = true
					_company = Silhouette.create(0, 2.2, 0.42)
					session.stage.actors_root.add_child(_company)
					_company.global_position = Vector3(cell.position.x, 0.0, cell.position.z)
					_company.set_presence(1.0)
					_company_t = 5.0
					_log(&"scare", "company")
					return true
	return false


func _tick_company(delta: float, pl: Player) -> void:
	if _company == null or not is_instance_valid(_company):
		_company = null
		return
	_company_t -= delta
	var near := pl.global_position.distance_to(_company.global_position) < 2.2
	if _company_t <= 0.0 or near:
		_company.set_presence(0.0)
		if _company.visible == false or near:
			_company.queue_free()
			_company = null


# --- Management reacts to behaviour (SPEC 6.10) ---------------------------------------------

func _monitor_behaviour(delta: float, pl: Player) -> void:
	_hide_t = _hide_t + delta if pl.hidden else 0.0
	_sprint_t = _sprint_t + delta if pl.sprinting else maxf(0.0, _sprint_t - delta)
	var level := 1.0
	if session.stage != null and session.stage.light_field != null:
		level = session.stage.light_field.level_at_tile(GameScale.world_to_tile(pl.global_position))
	_dark_t = _dark_t + delta if (level < 0.2 and not session.in_relief_zone()) else 0.0
	var cc: Camcorder = session.camcorder
	_lamp_t = _lamp_t + delta if (cc != null and cc.is_lamp_on()) else 0.0
	if _sprint_t > 3.0:
		_sprint_t = 0.0
		remark(&"remark_sprint")
	elif _hide_t > 25.0:
		_hide_t = 0.0
		remark(&"remark_hide_long")
	elif _dark_t > 40.0:
		_dark_t = 0.0
		remark(&"remark_darkness")
	elif _lamp_t > 45.0:
		_lamp_t = 0.0
		remark(&"remark_lamp")


func _on_peek(_door: Node) -> void:
	remark(&"remark_door_peek")


func remark(line_id: StringName) -> void:
	## One live remark per `pa_remark_gap` seconds, never during an Encounter.
	if t - last_remark < tuning.pa_remark_gap or phase == Phase.ENCOUNTER or phase == Phase.TELLING:
		return
	if AudioDirector.is_pa_busy():
		return
	last_remark = t
	AudioDirector.say(line_id)
