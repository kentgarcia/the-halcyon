class_name TapeRecorder
extends Node
## Records what the guest's camera sees into TapeBuffers (SPEC 12.5, risk R1). A tiny secondary viewport
## shares the world; at 10 Hz we point its camera at the player's view, ask for one render, and read the
## pixels back after the frame is drawn. Readback cost is tracked in `readback_ms` (the spike's answer).
##
## Two buffers: `pov` always records the player's view (playback, Autopsy, your own tapes); `stake` records a
## planted camcorder in time-lapse (2 fps over ~3.5 min).

var main: Main = null
var player: Player = null
var tape_cam: Camera3D = null
var pov: TapeBuffer = TapeBuffer.new(450, 10.0)
var stake: TapeBuffer = TapeBuffer.new(420, 2.0)
var planted: Node3D = null              ## PlantedCamcorder while a stakeout is running
var enabled := true
var readback_ms := 0.0
var readback_max_ms := 0.0
var frames_taken := 0
var _t_pov := 0.0
var _t_stake := 0.0
var _waiting := false
var _target: TapeBuffer = null
var _t0 := 0


func setup(p_main: Main, p_player: Player) -> void:
	main = p_main
	player = p_player
	if main.tape_viewport.get_node_or_null("TapeCam") == null:
		tape_cam = Camera3D.new()
		tape_cam.name = "TapeCam"
		tape_cam.near = 0.05
		tape_cam.far = 60.0
		main.tape_viewport.add_child(tape_cam)
	else:
		tape_cam = main.tape_viewport.get_node("TapeCam")
	tape_cam.current = true
	# tape renders must not show stage-only helper overlays; nothing else to configure


func _process(delta: float) -> void:
	if not enabled or main == null or _waiting:
		return
	if player != null and is_instance_valid(player):
		_t_pov += delta
		if _t_pov >= 1.0 / pov.fps and (planted == null or true):
			_t_pov = 0.0
			_capture(pov, player.camera.global_transform, player.camera.fov)
			return
	if planted != null and is_instance_valid(planted):
		_t_stake += delta
		if _t_stake >= 1.0 / stake.fps:
			_t_stake = 0.0
			_capture(stake, planted.call("lens_transform"), 60.0)


func _capture(buffer: TapeBuffer, xform: Transform3D, fov: float) -> void:
	tape_cam.global_transform = xform
	tape_cam.fov = fov
	_target = buffer
	_waiting = true
	_t0 = Time.get_ticks_usec()
	main.tape_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.frame_post_draw.connect(_on_drawn, CONNECT_ONE_SHOT)


func _on_drawn() -> void:
	_waiting = false
	if _target == null:
		return
	var img := main.tape_viewport.get_texture().get_image()
	if img != null:
		_target.push_image(img)
		frames_taken += 1
	var ms := float(Time.get_ticks_usec() - _t0) / 1000.0
	readback_ms = lerpf(readback_ms, ms, 0.1) if readback_ms > 0.0 else ms
	readback_max_ms = maxf(readback_max_ms, ms)
	_target = null


func reset() -> void:
	pov.clear()
	stake.clear()
	planted = null


func start_stakeout(node: Node3D) -> void:
	planted = node
	stake.clear()
	_t_stake = 0.0


func end_stakeout() -> void:
	planted = null


func last_seconds(seconds_back: float) -> Array[PackedByteArray]:
	return pov.last_frames(seconds_back)
