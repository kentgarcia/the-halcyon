class_name Camcorder
extends Node
## The Tape (SPEC 3.2.1): the guest's one tool. Stowed -> Raised (viewfinder, narrow FOV, slower, lamp) ->
## Playback (the last 45 s; you cannot see the world) -> Freeze Frame (a still into the notebook) ->
## Stakeout (set it down; it keeps recording in time-lapse). Every use is a trade: information for
## vulnerability (blind spots, narrow view, battery).

enum State { STOWED, RAISED, PLAYBACK, ABSENT }

const FOV_RAISED := GameScale.FOV_CAMCORDER
const SPEED_RAISED := 0.6
const DRAIN_LAMP := 0.4
const DRAIN_PLAYBACK := 0.8
const DRAIN_RAISED := 0.1
const DRAIN_PLANTED := 0.05
const STAKEOUT_HOLD := 0.7
const LAMP_RANGE := 6.0
const LAMP_CONE_DEG := 28.0

var player: Player = null
var recorder: TapeRecorder = null
var state: int = State.STOWED
var lamp_on := true
var lamp: SpotLight3D = null
var planted: PlantedCamcorder = null
var echo_label := ""                      ## non-empty while an Echo tape / stakeout tape is being watched
var pb_frames: Array[PackedByteArray] = []
var pb_fps := 10.0
var pb_pos := 0.0
var pb_playing := true
var pb_texture: ImageTexture = null
var pb_source := &"pov"                   ## pov | stake | echo
var stakeout_progress := 0.0
var _raise_held := false
var _low_battery_warned := false
var _dead_toast := 0.0


func setup(p_player: Player, p_recorder: TapeRecorder) -> void:
	player = p_player
	recorder = p_recorder
	player.camcorder = self
	lamp = SpotLight3D.new()
	lamp.name = "Lamp"
	lamp.spot_range = LAMP_RANGE
	lamp.spot_angle = LAMP_CONE_DEG
	lamp.spot_angle_attenuation = 0.8
	lamp.light_energy = 1.7
	lamp.light_color = Color(1.0, 0.95, 0.82)
	lamp.shadow_enabled = false
	lamp.visible = false
	player.camera.add_child(lamp)
	pb_texture = ImageTexture.create_from_image(Image.create_empty(TapeBuffer.W, TapeBuffer.H, false, Image.FORMAT_RGB8))


func _exit_tree() -> void:
	if player != null and is_instance_valid(player):
		player.speed_mods.erase(&"camcorder")
	if Main.instance != null:
		Main.instance.set_cam_mix(0.0)
		if Main.instance.showing_footage():
			Main.instance.hide_footage()


# --- queries --------------------------------------------------------------------------------

func is_raised() -> bool:
	return state == State.RAISED


func in_playback() -> bool:
	return state == State.PLAYBACK


func is_lamp_on() -> bool:
	return state == State.RAISED and lamp_on and RunState.battery > 0.0 and not player.hidden


func leaking_light() -> bool:
	## The LCD glow through a wardrobe's slats can give you away (SPEC 3.2).
	return player.hidden and (state == State.PLAYBACK or state == State.RAISED)


func lamp_hits(point: Vector3, max_dist: float = LAMP_RANGE) -> bool:
	if not is_lamp_on():
		return false
	var cam := player.camera.global_position
	var to := point - cam
	var d := to.length()
	if d > max_dist or d < 0.05:
		return false
	if player.look_direction().angle_to(to) > deg_to_rad(LAMP_CONE_DEG):
		return false
	var q := PhysicsRayQueryParameters3D.create(cam, point, GameScale.LAYER_WORLD | GameScale.LAYER_DOORS)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(point) < 0.6


# --- state ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var inp := player.input
	if _dead_toast > 0.0:
		_dead_toast -= delta
	if state != State.ABSENT:
		_handle_input(inp, delta)
	_drain(delta)
	_update_playback(delta, inp)
	_present()


func _handle_input(inp: PlayerInput, delta: float) -> void:
	var want_raised := false
	if Settings.camcorder_toggle:
		if inp.just_pressed(&"camcorder"):
			_raise_held = not _raise_held
		want_raised = _raise_held
	else:
		want_raised = inp.is_down(&"camcorder")
		_raise_held = want_raised
	if player.frozen:
		want_raised = false
	if want_raised and RunState.battery <= 0.0:
		want_raised = false
		if inp.just_pressed(&"camcorder") and _dead_toast <= 0.0:
			_dead_toast = 2.0
			EventBus.toast.emit("The camcorder is dead.")
	match state:
		State.STOWED:
			if want_raised:
				_set_state(State.RAISED)
		State.RAISED:
			if not want_raised:
				_set_state(State.STOWED)
			else:
				if inp.just_pressed(&"lamp") and not player.hidden:
					lamp_on = not lamp_on
					AudioDirector.play(&"cam_lamp_click")
				if inp.just_pressed(&"playback"):
					begin_playback(&"pov")
				if inp.just_pressed(&"freeze_frame"):
					freeze_frame(false)
				_stakeout_input(inp, delta)
		State.PLAYBACK:
			if not want_raised and echo_label == "":
				_set_state(State.STOWED)
			elif inp.just_pressed(&"playback") or (echo_label != "" and inp.just_pressed(&"camcorder")):
				end_playback()
			if inp.just_pressed(&"freeze_frame"):
				freeze_frame(true)
	if state != State.RAISED:
		stakeout_progress = 0.0


func _stakeout_input(inp: PlayerInput, delta: float) -> void:
	if planted != null or player.hidden:
		return
	if inp.is_down(&"stakeout"):
		stakeout_progress += delta / STAKEOUT_HOLD
		if stakeout_progress >= 1.0:
			stakeout_progress = 0.0
			plant()
	else:
		stakeout_progress = 0.0


func _set_state(s: int) -> void:
	if s == state:
		return
	var prev := state
	state = s
	match s:
		State.RAISED:
			if prev == State.STOWED:
				lamp_on = true
				AudioDirector.play(&"cam_raise")
				player.speed_mods[&"camcorder"] = SPEED_RAISED
				player.set_fov_target(FOV_RAISED)
				Main.instance.set_cam_mix(1.0)
			elif prev == State.PLAYBACK:
				_leave_playback_view()
		State.STOWED:
			if prev == State.RAISED or prev == State.PLAYBACK:
				AudioDirector.play(&"cam_lower")
			player.speed_mods.erase(&"camcorder")
			player.set_fov_target(Settings.fov)
			Main.instance.set_cam_mix(0.0)
			if prev == State.PLAYBACK:
				_leave_playback_view()
			stakeout_progress = 0.0
		State.PLAYBACK:
			pass
		State.ABSENT:
			player.speed_mods.erase(&"camcorder")
			player.set_fov_target(Settings.fov)
			Main.instance.set_cam_mix(0.0)
			if prev == State.PLAYBACK:
				_leave_playback_view()
	EventBus.camcorder_state_changed.emit(state)


func _leave_playback_view() -> void:
	Main.instance.hide_footage()
	player.look_locked = false
	echo_label = ""


# --- playback -------------------------------------------------------------------------------

func begin_playback(source: StringName = &"pov", frames: Array[PackedByteArray] = [], fps: float = 10.0, label: String = "") -> void:
	if RunState.battery <= 0.0:
		return
	pb_source = source
	match source:
		&"pov":
			pb_frames = recorder.pov.last_frames(45.0)
			pb_fps = recorder.pov.fps
		&"stake":
			pb_frames = recorder.stake.last_frames(220.0)
			pb_fps = recorder.stake.fps
		_:
			pb_frames = frames
			pb_fps = fps
	echo_label = label
	if pb_frames.is_empty():
		EventBus.toast.emit("Nothing on the tape yet.")
		return
	pb_pos = 0.0
	pb_playing = true
	if state == State.STOWED:
		player.speed_mods[&"camcorder"] = SPEED_RAISED
	_set_state(State.PLAYBACK)
	player.look_locked = true
	AudioDirector.play(&"cam_rewind_loop" if pb_source == &"pov" else &"cam_tape_insert")
	Main.instance.show_footage(pb_texture)
	_upload(0)
	EventBus.camcorder_state_changed.emit(state)


func end_playback() -> void:
	if state != State.PLAYBACK:
		return
	if echo_label != "":
		# an Echo tape / stakeout tape: back to the world, camcorder lowered
		_set_state(State.STOWED)
		return
	_set_state(State.RAISED)


func _update_playback(delta: float, inp: PlayerInput) -> void:
	if state != State.PLAYBACK or pb_frames.is_empty():
		return
	var scrub := inp.move.x
	if absf(scrub) > 0.1:
		pb_pos += scrub * delta * pb_fps * 4.0
		pb_playing = false
	elif inp.just_pressed(&"interact"):
		pb_playing = not pb_playing
	elif pb_playing:
		pb_pos += delta * pb_fps
	if pb_pos >= float(pb_frames.size()):
		pb_pos = 0.0 if pb_source != &"pov" else float(pb_frames.size() - 1)
		pb_playing = pb_source != &"pov"
	pb_pos = clampf(pb_pos, 0.0, float(pb_frames.size() - 1))
	_upload(int(pb_pos))


func _upload(i: int) -> void:
	if i < 0 or i >= pb_frames.size() or pb_frames[i].size() != TapeBuffer.FRAME_BYTES:
		return
	pb_texture.update(TapeBuffer.to_image(pb_frames[i]))


func playback_time() -> float:
	return pb_pos / pb_fps


func playback_length() -> float:
	return float(pb_frames.size()) / pb_fps


# --- freeze frame ---------------------------------------------------------------------------

func freeze_frame(from_playback: bool) -> void:
	if RunState.freeze_frames_left <= 0:
		EventBus.toast.emit("No frames left on this floor.")
		return
	var img: Image
	if from_playback:
		var i := clampi(int(pb_pos), 0, pb_frames.size() - 1)
		img = TapeBuffer.to_image(pb_frames[i])
		img.resize(TapeBuffer.W * 3, TapeBuffer.H * 3, Image.INTERPOLATE_NEAREST)
	else:
		img = Main.instance.game_viewport.get_texture().get_image()
		img.resize(256, 144, Image.INTERPOLATE_NEAREST)
	RunState.freeze_frames_left -= 1
	AudioDirector.play(&"cam_freeze_shutter")
	EventBus.freeze_frame_taken.emit(RunState.freeze_frames_left)
	var session: Node = Game.session
	if session != null and session.has_method("add_freeze_frame"):
		session.add_freeze_frame(img, from_playback)
	EventBus.toast.emit("Freeze Frame saved to the notebook. (%d left)" % RunState.freeze_frames_left)


# --- stakeout -------------------------------------------------------------------------------

func plant() -> void:
	var session: Node = Game.session
	if session == null or not session.has_method("plant_camcorder"):
		return
	var cam := player.camera
	var from := cam.global_position
	var dir := player.look_direction()
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2.0, GameScale.LAYER_WORLD | GameScale.LAYER_PROPS)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	var pos: Vector3
	if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.6:
		pos = hit["position"]
	else:
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		var at := from + flat * 1.0
		var q2 := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 3.0, GameScale.LAYER_WORLD | GameScale.LAYER_PROPS)
		q2.exclude = [player.get_rid()]
		var h2 := space.intersect_ray(q2)
		pos = h2["position"] if not h2.is_empty() else Vector3(at.x, 0.0, at.z)
	var yaw := player.rotation.y
	AudioDirector.play(&"cam_plant_thunk")
	var node: PlantedCamcorder = session.plant_camcorder(pos, yaw)
	if node == null:
		return
	planted = node
	recorder.start_stakeout(node)
	_set_state(State.ABSENT)
	EventBus.toast.emit("Camcorder set down. It keeps recording.")


func on_retrieved(node: PlantedCamcorder) -> void:
	if planted == node:
		planted = null
	recorder.end_stakeout()
	if state == State.ABSENT:
		state = State.STOWED
		EventBus.camcorder_state_changed.emit(state)
	AudioDirector.play(&"cam_plant_thunk", -4.0)


func lost_and_found() -> void:
	## Housekeeping tidied it away: it is on the shelf by the departure elevator (the guest is without it).
	planted = null
	recorder.end_stakeout()
	if state != State.ABSENT:
		_set_state(State.ABSENT)


func restore_from_lost_and_found() -> void:
	if state == State.ABSENT and planted == null:
		state = State.STOWED
		EventBus.camcorder_state_changed.emit(state)


# --- battery / presentation -----------------------------------------------------------------

func _drain(delta: float) -> void:
	var rate := 0.0
	match state:
		State.RAISED:
			rate = DRAIN_LAMP if is_lamp_on() else DRAIN_RAISED
		State.PLAYBACK:
			rate = DRAIN_PLAYBACK
		State.ABSENT:
			rate = DRAIN_PLANTED
	if rate > 0.0:
		RunState.set_battery(RunState.battery - rate * delta)
		if RunState.battery <= 15.0 and not _low_battery_warned and RunState.battery > 0.0:
			_low_battery_warned = true
			AudioDirector.play(&"cam_battery_low")
			EventBus.toast.emit("Battery low.")
		if RunState.battery > 15.0:
			_low_battery_warned = false
		if RunState.battery <= 0.0:
			if state == State.PLAYBACK:
				_set_state(State.STOWED)
			elif state == State.RAISED:
				_set_state(State.STOWED)
			EventBus.toast.emit("The camcorder is dead.")


func _present() -> void:
	if lamp != null:
		var on := is_lamp_on()
		if lamp.visible != on:
			lamp.visible = on
