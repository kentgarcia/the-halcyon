class_name FloorSession
extends Node
## One floor of play, end to end: builds the stage, plan, streamer, player, camcorder, HUD, entity, Director and
## Housekeeping and wires them together (SPEC 12.2). It is `Game.session`; props, the camcorder and entities talk
## to it through a small, documented surface.
##
## Lifecycle:  setup(def, opts)  ->  (Game shows the House Rules card)  ->  begin_play()  ->  ... ->
##             floor_cleared (guest reached the departure elevator)  or  blacked_out (Nerve hit zero).

signal ready_for_card(session: FloorSession)
signal exam_started()
signal floor_cleared(session: FloorSession)
signal blacked_out(info: Dictionary)
signal verdict_changed(verdict: int)

const PA_FLOOR_LINE := {
	&"boiler": &"floor_b3", &"natatorium": &"floor_b2", &"blue": &"floor_b1",
	&"yellow": &"floor_f1", &"units": &"floor_f2", &"lobby": &"floor_l",
}
const PA_RULE_PREFIX := {
	&"boiler": "b3", &"natatorium": "b2", &"blue": "b1", &"yellow": "f1", &"units": "f2", &"lobby": "l",
}
const AMBIENCE := {
	&"boiler": [&"amb_boiler_rumble"], &"natatorium": [&"amb_pool_water"], &"blue": [&"amb_hum_bed", &"amb_queue_whispers"],
	&"yellow": [&"amb_hum_bed"], &"units": [&"amb_hum_bed"], &"lobby": [&"amb_lobby_warm"],
}
const CLEAR_DELAY := 2.4

var def: FloorDef
var plan: FloorPlan
var truth: int = RunState.Truth.HOLDS
var opts: Dictionary = {}
var tuning: DirectorTuning
var stage: Stage
var streamer: ChunkStreamer
var grid: WorldGrid
var circuits: Circuits
var player: Player
var recorder: TapeRecorder
var camcorder: Camcorder
var hud: Hud
var viewfinder: Viewfinder
var director: DirectorCore
var housekeeping: Housekeeping
var evidence: EvidenceTracker
var clauses: ClauseService
var staff_frozen_until := 0.0              ## Time.get_ticks_msec()/1000 basis: staff stand still until then (whistle)
var entity: EntityBase = null
var freeze_frames: Array[Dictionary] = []        ## [{image, from_playback, chunk, t}]
var pa_horns: Array[Node3D] = []
var lost_found: Array[Dictionary] = []           ## camcorder tapes Housekeeping took
var play_time := 0.0
var started := false
var exam_entered := false
var cleared := false
var blackout_done := false
var first_chunk: Chunk = null
var last_hit_source: StringName = &""
var _clear_t := -1.0
var _audio_t := 0.0
var _arrival_door: Door = null


# --- setup -----------------------------------------------------------------------------------

func setup(p_def: FloorDef, p_opts: Dictionary = {}) -> void:
	def = p_def
	opts = p_opts
	name = "FloorSession"
	Game.session = self
	tuning = load("res://data/director_tuning.tres") as DirectorTuning
	if tuning == null:
		tuning = DirectorTuning.new()
	truth = _roll_truth()
	RunState.set_truth(def.id, truth)
	# stickers from an earlier attempt at this floor are not "found" in the new layout
	for variant in [0, 1]:
		for e: EvidenceDef in def.evidence_for(variant):
			RunState.evidence_found.erase(e.id)

	stage = Game.make_stage()
	stage.apply_theme(Themes.get_theme(def.theme_id))
	plan = FloorPlan.create(def, truth, RunState.rng, {
		"mastered": bool(opts.get("mastered", false)),
		"guided": Settings.guided_rules,
	})
	streamer = ChunkStreamer.new()
	streamer.name = "Streamer"
	stage.add_child(streamer)
	streamer.setup(stage, plan)
	grid = WorldGrid.new(streamer)
	circuits = Circuits.new()
	circuits.streamer = streamer
	for k in plan.initial_circuits:
		circuits.set_default(StringName(k), bool(plan.initial_circuits[k]))
	plan.populator = func(chunk: Chunk, bp: Object) -> void: SlotPopulator.populate(chunk, bp, self, true)

	var first_bp: FloorPlan.BeatPlan = plan.main_beats[0]
	first_chunk = streamer.spawn_initial(first_bp.spec, 0, 0, Vector2i(0, 0), {"bp": first_bp, "decay": 0})
	_spawn_player()
	_build_systems()
	_build_ui()
	streamer.player = player
	_wire_events()
	_start_ambience()
	RunState.set_nerve(RunState.nerve_max)
	EventBus.floor_started.emit(def.id)
	Main.instance.set_fade(1.0)
	ready_for_card.emit(self)
	_prewarm_rooms()


func _prewarm_rooms() -> void:
	## One room per frame while the card is being read / the car is arriving: the geometry, collision and light
	## topology of every planned main room is cached, so opening a door later costs node creation, not a hitch.
	for bp: FloorPlan.BeatPlan in plan.main_beats:
		if bp.index == 0 or bp.spec == null:
			continue
		await get_tree().process_frame
		if not is_inside_tree() or plan == null:
			return
		ChunkBuilder.warm(bp.spec, plan.theme_for(bp.index), bp.decay)


func _roll_truth() -> int:
	if opts.has("truth"):
		return int(opts["truth"])
	var r := RunState.stream(&"rules")
	return RunState.Truth.INVERTED if r.randf() < def.p_inverted else RunState.Truth.HOLDS


func _spawn_player() -> void:
	player = Player.new()
	stage.actors_root.add_child(player)
	var pos := GameScale.tile_to_world(Vector2i(2, 3))
	var yaw := 0.0
	var anchors: Array = first_chunk.slot_nodes.get(&"anchor", [])
	if not anchors.is_empty():
		var a: Node3D = anchors[0]
		pos = a.global_position
	# face the car door (the exit socket)
	if not first_chunk.exit_world.is_empty():
		var ex: Dictionary = first_chunk.exit_world[0]
		var dir: Vector2i = ex["dir"]
		yaw = Dir.yaw_of(dir)
	player.teleport(pos, yaw)
	player.surface = Themes.get_theme(def.theme_id).surface
	player.frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if DisplayServer.get_name() != "headless" else Input.MOUSE_MODE_VISIBLE


func _build_systems() -> void:
	recorder = TapeRecorder.new()
	recorder.name = "TapeRecorder"
	add_child(recorder)
	recorder.setup(Main.instance, player)
	recorder.enabled = DisplayServer.get_name() != "headless" and not bool(opts.get("no_tape", false))
	camcorder = Camcorder.new()
	camcorder.name = "Camcorder"
	add_child(camcorder)
	camcorder.setup(player, recorder)
	evidence = EvidenceTracker.new()
	evidence.name = "EvidenceTracker"
	evidence.session = self
	add_child(evidence)
	clauses = ClauseService.new()
	clauses.name = "Clauses"
	add_child(clauses)
	clauses.setup(self)
	director = DirectorCore.new()
	director.name = "Director"
	add_child(director)
	director.setup(self, tuning)
	director.enabled = false
	housekeeping = Housekeeping.new()
	housekeeping.name = "Housekeeping"
	add_child(housekeeping)
	housekeeping.setup(self, def.housekeeping_seconds * float(opts.get("clock_scale", 1.0)))
	housekeeping.enabled = housekeeping.enabled and not bool(opts.get("no_housekeeping", false))
	entity = EntityFactory.create(def.entity_id)
	if entity != null:
		entity.setup(self, truth)
		stage.actors_root.add_child(entity)


func _build_ui() -> void:
	hud = Hud.new()
	hud.name = "Hud"
	hud.player = player
	Main.instance.ui.add_child(hud)
	viewfinder = Viewfinder.new()
	viewfinder.name = "Viewfinder"
	viewfinder.camcorder = camcorder
	Main.instance.ui.add_child(viewfinder)


func _wire_events() -> void:
	EventBus.chunk_entered.connect(_on_chunk_entered)
	EventBus.blackout.connect(_on_blackout)
	streamer.chunk_loaded.connect(_on_chunk_loaded)


func _start_ambience() -> void:
	AudioDirector.stop_all_ambience()
	for id in AMBIENCE.get(def.id, [&"amb_hum_bed"]):
		AudioDirector.set_ambience(id, true)
	AudioDirector.set_ambience(&"amb_dark_pressure", true)
	AudioDirector.set_ambience_level(&"amb_dark_pressure", 0.0)
	AudioDirector.set_ambience(&"amb_dread_drone", true)
	AudioDirector.set_ambience_level(&"amb_dread_drone", 0.0)
	AudioDirector.set_ambience(&"amb_heartbeat", true)
	AudioDirector.set_ambience_level(&"amb_heartbeat", 0.0)


func teardown() -> void:
	## Frees everything this session made (the Stage is freed by Game.make_stage on the next floor).
	for pair in [[EventBus.chunk_entered, _on_chunk_entered], [EventBus.blackout, _on_blackout]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	DreadDirector.reset()
	if Main.instance != null:
		Main.instance.set_dread_visual(0.0)
		Main.instance.set_glitch(0.0)
		Main.instance.set_cam_mix(0.0)
		Main.instance.set_desaturate(0.0)
		if Main.instance.showing_footage():
			Main.instance.hide_footage()
	if hud != null and is_instance_valid(hud):
		hud.queue_free()
	if viewfinder != null and is_instance_valid(viewfinder):
		viewfinder.queue_free()
	AudioDirector.stop_all_ambience()
	AudioDirector.clear_pa()
	if Game.session == self:
		Game.session = null
	queue_free()


# --- play ------------------------------------------------------------------------------------

func rule_pa_lines() -> Array[Dictionary]:
	## The PA reads the card aloud: [{id, take}] in printed order. The entity rule carries the *false take*
	## (with the barely audible mic pop) when INVERTED (SPEC 4.5); the Lobby is perfect.
	var out: Array[Dictionary] = []
	var prefix: String = PA_RULE_PREFIX.get(def.id, "f1")
	for r in def.rules:
		var take: StringName = &"true"
		if r.kind == RuleDef.Kind.ENTITY and truth == RunState.Truth.INVERTED and def.id != &"lobby":
			take = &"false"
		out.append({"id": StringName("rule_%s_%d" % [prefix, r.number]), "take": take})
	return out


func begin_play() -> void:
	## The card has been read: the car doors open and the floor is live.
	if started:
		return
	started = true
	clauses.floor_started()
	player.frozen = false
	Main.instance.fade_to(0.0, 1.0)
	AudioDirector.play(&"elevator_doors_open")
	AudioDirector.say(PA_FLOOR_LINE.get(def.id, &"floor_f1"))
	_open_arrival_door()
	director.enabled = not bool(opts.get("no_director", false))


func _open_arrival_door() -> void:
	for conn in streamer.connections.values():
		var dc: DoorConnection = conn
		if int(dc.side_a["uid"]) == first_chunk.uid and dc.door != null and dc.plan.get("type", &"") != &"stuck":
			_arrival_door = dc.door
			dc.door.open_door(dc.door.side_of(player.global_position), true)
			return


func _process(delta: float) -> void:
	if not started or cleared or blackout_done:
		return
	_hotkeys()
	play_time += delta
	if _clear_t >= 0.0:
		_clear_t -= delta
		if _clear_t <= 0.0:
			_do_clear()
	_audio_t += delta
	if _audio_t >= 0.25:
		_audio_t = 0.0
		_update_audio_layers()


func _hotkeys() -> void:
	if Game.screen_open() or player.frozen:
		return
	var inp := player.input
	if inp.just_pressed(&"notebook"):
		Game.open_notebook(self)
	elif inp.just_pressed(&"card"):
		Game.open(&"card", {"session": self, "mode": &"review"})
	elif inp.just_pressed(&"pause"):
		Game.open(&"pause", {"session": self})
	elif inp.just_pressed(&"use_item") and RunState.pocket == &"whistle":
		clauses.blow_whistle()


func complete_floor() -> void:
	## For floors without a departure elevator (the Lobby): the floor's last beat calls this.
	if _clear_t < 0.0 and not cleared:
		_clear_t = 0.5


func _update_audio_layers() -> void:
	var d := DreadDirector.normalized()
	AudioDirector.set_ambience_level(&"amb_dark_pressure", clampf(d * 1.3, 0.0, 1.0))
	AudioDirector.set_ambience_level(&"amb_dread_drone", clampf((d - 0.45) * 2.0, 0.0, 1.0))
	var missing := 1.0 - float(RunState.nerve) / float(maxi(1, RunState.nerve_max))
	AudioDirector.set_ambience_level(&"amb_heartbeat", clampf(missing * 1.1 if RunState.nerve < RunState.nerve_max else 0.0, 0.0, 1.0))


# --- chunk flow ------------------------------------------------------------------------------

func _beat_of(chunk: Chunk) -> FloorPlan.BeatPlan:
	return chunk.plan.get("bp", null) as FloorPlan.BeatPlan


func current_beat() -> FloorPlan.BeatPlan:
	if streamer == null or streamer.current == null:
		return null
	return _beat_of(streamer.current)


func in_relief_zone() -> bool:
	var bp := current_beat()
	return bp != null and (bp.kind == &"arrival" or bp.kind == &"departure" or bp.kind == &"rest")


func exam_pending() -> bool:
	return exam_entered


func encounter_active() -> bool:
	return director != null and director.entity_active()


func _on_chunk_loaded(chunk: Chunk) -> void:
	var bp := _beat_of(chunk)
	if bp != null and bp.kind == &"departure":
		_place_lost_and_found(chunk)


func _on_chunk_entered(chunk: Node) -> void:
	var c := chunk as Chunk
	if c == null or cleared:
		return
	var bp := _beat_of(c)
	# ambient entity in the lab room (the Hum in the Long Room: the authored Test, SPEC 6.5)
	_ambient_entity(c, bp)
	if bp == null:
		return
	if bp.kind == &"exam" and not exam_entered:
		exam_entered = true
		_apply_verdict_cost()
		exam_started.emit()
		director.on_exam_started()
	if bp.kind == &"departure" and _clear_t < 0.0:
		_clear_t = CLEAR_DELAY
		if clause_active(&"take_number"):
			_clear_t += ClauseService.ELEVATOR_WAIT      # guest side: wait for the elevator's call chime
			EventBus.toast.emit("Please wait for the chime.")
			get_tree().create_timer(ClauseService.ELEVATOR_WAIT).timeout.connect(func(): AudioDirector.play(&"queue_chime"))


func _ambient_entity(c: Chunk, bp: FloorPlan.BeatPlan) -> void:
	if entity == null or not entity.has_method("spawn_ambient"):
		return
	if entity.active or director.entity_active():
		return
	var is_lab := bp != null and bp.main and bp.kind == def.lab_beat
	if is_lab:
		var anchors: Array = c.slot_nodes.get(&"anchor", [])
		if anchors.is_empty():
			return
		var rng := plan.rng_for("ambient:%d" % bp.index)
		var a: Node3D = anchors[rng.randi() % anchors.size()]
		entity.call("spawn_ambient", c, GameScale.world_to_tile(a.global_position))
	elif entity.has_method("retire"):
		entity.call("retire")


func exit_position_of(chunk: Chunk) -> Vector3:
	## Where a guest "shown out" of a room ends up: back at the door they came in by.
	if not chunk.entry_world.is_empty():
		return GameScale.tile_to_world(chunk.entry_world[0]["tile"])
	if not chunk.exit_world.is_empty():
		return GameScale.tile_to_world(chunk.exit_world[0]["tile"])
	return GameScale.tile_to_world(chunk.world_open.keys()[0])


func _do_clear() -> void:
	if cleared:
		return
	cleared = true
	player.frozen = true
	director.enabled = false
	if entity != null and entity.active:
		entity.stand_down()
	Main.instance.fade_to(1.0, 0.9)
	AudioDirector.play(&"elevator_doors_close")
	await get_tree().create_timer(1.0).timeout
	EventBus.floor_cleared.emit(def.id)
	floor_cleared.emit(self)


# --- verdict (SPEC 4.9) ----------------------------------------------------------------------

func correct_verdict() -> int:
	return RunState.Mark.TRUST if truth == RunState.Truth.HOLDS else RunState.Mark.LIE


func verdict_filed() -> bool:
	return RunState.verdict != -1


func open_suggestion_box() -> void:
	Game.open_suggestion_box(self)


func file_verdict(v: int) -> void:
	if verdict_filed():
		return
	RunState.verdict = v
	RunState.verdict_correct = 1 if v == correct_verdict() else 0
	AudioDirector.play(&"box_slot")
	EventBus.verdict_filed.emit(def.id, v)
	verdict_changed.emit(v)
	director.remark(&"remark_verdict")


func _apply_verdict_cost() -> void:
	## A wrong Verdict costs a Nerve segment when the exam starts (never lethal at full Nerve).
	if verdict_filed() and RunState.verdict_correct == 0:
		if RunState.nerve > 1:
			player.nerve.lose_segment(&"verdict")
		EventBus.toast.emit("Management has noted your feedback.")


# --- services used by props / camcorder / entities ------------------------------------------

func clause_active(clause_id: StringName) -> bool:
	## A Clause is in force when kept and not voided this floor (SPEC 4.10). Entities honour their House side.
	return RunState.clause == clause_id and not RunState.clause_void


func staff_frozen() -> bool:
	return Time.get_ticks_msec() / 1000.0 < staff_frozen_until


func freeze_staff(seconds: float) -> void:
	staff_frozen_until = Time.get_ticks_msec() / 1000.0 + seconds


func on_item_taken(item_id: StringName, _pickup: Node) -> void:
	if item_id == &"bulb":
		director.remark(&"remark_bulb")


func register_pa_horn(horn: Node3D) -> void:
	pa_horns.append(horn)


func add_freeze_frame(img: Image, from_playback: bool) -> void:
	var label := ""
	var bp := current_beat()
	if bp != null:
		label = "%s" % String(bp.kind)
	freeze_frames.append({"image": img, "from_playback": from_playback, "room": label, "t": snappedf(play_time, 1.0),
		"floor": def.id})


func plant_camcorder(pos: Vector3, yaw: float) -> PlantedCamcorder:
	var chunk := streamer.current
	var node := PlantedCamcorder.create(recorder, chunk, pos, yaw)
	stage.actors_root.add_child(node)
	node.global_position = pos
	director.remark(&"remark_plant_camera")
	return node


func retrieve_camcorder(node: PlantedCamcorder) -> void:
	camcorder.on_retrieved(node)
	node.release()
	EventBus.toast.emit("Camcorder back in hand. [%s] to rewind what it saw." % UIKit.key_label(&"playback"))
	if recorder.stake.count > 0:
		camcorder.begin_playback(&"stake", [], recorder.stake.fps, "STAKEOUT")


func send_camcorder_to_lost_and_found() -> void:
	## Housekeeping tidied a planted camcorder away. It is on the shelf by the departure elevator.
	var node := camcorder.planted
	camcorder.lost_and_found()
	lost_found.append({"frames": recorder.stake.last_frames(220.0), "fps": recorder.stake.fps})
	if node != null and is_instance_valid(node):
		node.release()
	EventBus.toast.emit("Housekeeping has taken your camcorder to Lost & Found.")


func _place_lost_and_found(chunk: Chunk) -> void:
	# a shelf beside the departure elevator holds the camcorder if Housekeeping took it
	var shelf := PropFactory.make(&"lost_found")
	chunk.props_root.add_child(shelf)
	var anchors: Array = chunk.slot_nodes.get(&"anchor", [])
	var pos := Vector3.ZERO
	if not anchors.is_empty():
		pos = (anchors[0] as Node3D).position + Vector3(1.0, 0, 0)
	elif not chunk.world_open.is_empty():
		pos = chunk.to_local(GameScale.tile_to_world(chunk.world_open.keys()[0]))
	shelf.position = pos
	var it := Interactable.new()
	it.name = "Use"
	it.position = Vector3(0, 0.9, 0)
	it.prompt_cb = func(_p): return "Collect your camcorder"
	it.can_cb = func(_p): return camcorder.state == Camcorder.State.ABSENT and camcorder.planted == null and not lost_found.is_empty()
	it.tap_cb = func(_p): _collect_lost_and_found()
	shelf.add_child(it)


func _collect_lost_and_found() -> void:
	if lost_found.is_empty():
		return
	var entry: Dictionary = lost_found.pop_back()
	camcorder.restore_from_lost_and_found()
	EventBus.toast.emit("Lost & Found has your camcorder. It kept recording.")
	var frames: Array[PackedByteArray] = entry.get("frames", [] as Array[PackedByteArray])
	if not frames.is_empty():
		camcorder.begin_playback(&"echo", frames, float(entry.get("fps", 2.0)), "LOST & FOUND")


func play_echo(tape: Node) -> void:
	## Echo clips are rendered by EchoPlayer (game/echo_player.gd): 10-15 s of a previous Guest obeying or
	## ignoring the rule. The footage is always the TRUE behaviour of this run's variant.
	var own: Variant = tape.get("own_death")
	if own is Dictionary and not (own as Dictionary).is_empty():
		EchoPlayer.play_own_death(self, own as Dictionary)       # your own footage, exactly as recorded (SPEC 4.11)
		return
	var clip: StringName = tape.get("clip_id")
	var ev_id: StringName = tape.get("evidence_id")
	if EchoPlayer.has_clip(clip):
		EchoPlayer.play(self, clip, truth)
	else:
		camcorder.begin_playback(&"echo", EchoPlayer.static_frames(), 10.0, "UNLABELLED TAPE")
	for e in def.evidence:
		if e.id == ev_id:
			evidence.note(e)


func on_player_hit(source: Object, source_name: StringName) -> void:
	last_hit_source = source_name if source == null else StringName(source.get("entity_id") if source.get("entity_id") != null else source_name)
	DreadDirector.add_dread(14.0)
	if hud != null:
		hud.queue_redraw()


func _on_blackout() -> void:
	if blackout_done:
		return
	blackout_done = true
	player.frozen = true
	director.on_blackout()
	if camcorder.in_playback():
		camcorder.end_playback()
	var frames := recorder.pov.last_frames(20.0)
	var info := {
		"floor_id": def.id,
		"truth": truth,
		"frames": frames,
		"fps": recorder.pov.fps,
		"cause": last_hit_source,
		"rule": def.entity_rule().text if def.entity_rule() != null else "",
		"rule_number": def.entity_rule().number if def.entity_rule() != null else 0,
		"instinct": def.instinct,
	}
	AudioDirector.play(&"blackout_whoomp")
	var tw := Main.instance.fade_to(1.0, 0.9)
	await tw.finished
	blacked_out.emit(info)
