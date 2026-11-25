class_name EchoPlayer
extends RefCounted
## Echo tapes (SPEC 4.3, 4.11): short grainy clips of a previous Guest obeying or ignoring the floor's entity rule,
## and your own old death tapes. The footage is always the TRUE behaviour of this run's variant (Fairness
## Doctrine 1: the house may lie in what it says, never in what it shows).
##
## Echo clips are *authored sequences rendered into the same viewfinder path* (SPEC 12.5): when a tape is played
## we hang a tiny diorama (EchoStage, scripted by EchoClips) far from the play area, advance it a fixed 0.1 s per
## rendered frame and read each frame back from the shared 128x96 tape viewport exactly like TapeRecorder does,
## then hand the frames to Camcorder.begin_playback. While baking (~2-5 s) the live recorder is paused, the
## world viewport stops rendering and the player is frozen in front of "tape loading" static.
## Headless there is no rendering: playback degrades to a few frames of static.

const FPS := 10.0
const STEP := 1.0 / FPS
const WARMUP_FRAMES := 2
const MAX_CACHE := 3
const BATCH := 6                                    ## frames drawn per engine frame while baking

static var _cache: Dictionary = {}                  ## clip id -> Array[PackedByteArray] (finished frames)
static var _cache_order: Array[StringName] = []
static var _noise_pool: Array[PackedByteArray] = []
static var _busy := false
static var last_bake_ms := 0                        ## wall time of the most recent bake (dev metric)


# --- clip catalogue --------------------------------------------------------------------------

static func has_clip(clip: StringName) -> bool:
	return EchoClips.has(clip)


static func clip_ids() -> Array[StringName]:
	return EchoClips.ids()


static func clip_duration(clip: StringName) -> float:
	return EchoClips.duration(clip)


static func clip_label(clip: StringName) -> String:
	return EchoClips.label(clip)


static func clip_for(clip: StringName, truth: int) -> StringName:
	## The clip that is TRUE for this run's variant. FloorPlan only places the matching tape, so this is normally
	## the identity; if a mismatched tape ever reaches us, we still show the footage the run's truth allows.
	var s := String(clip)
	for suffix in ["_hold", "_inv"]:
		if s.ends_with(suffix):
			var want := s.trim_suffix(suffix) + ("_hold" if truth == RunState.Truth.HOLDS else "_inv")
			if want != s and EchoClips.has(StringName(want)):
				push_warning("EchoPlayer: tape '%s' does not match this run's variant; showing '%s'" % [clip, want])
				return StringName(want)
	return clip


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


# --- playing ---------------------------------------------------------------------------------

static func play(session: Node, clip: StringName, truth: int) -> void:
	## Called when a guest puts an Echo tape in the camcorder. Returns immediately; the clip starts after a short bake.
	if session == null or not is_instance_valid(session):
		return
	var id := clip_for(clip, truth)
	var cc: Camcorder = session.get("camcorder") as Camcorder
	if cc == null or not has_clip(id):
		return
	if _headless() or Main.instance == null:
		if Main.instance != null:
			cc.begin_playback(&"echo", static_frames(), FPS, clip_label(id))
		return
	_play_baked(session, id, cc)


static func play_own_death(session: Node, entry: Dictionary) -> void:
	## Your own old Autopsy footage (SPEC 4.11), exactly as it was recorded: never re-rendered, never altered.
	if session == null or not is_instance_valid(session) or Main.instance == null:
		return
	var cc: Camcorder = session.get("camcorder") as Camcorder
	if cc == null:
		return
	var tape: Dictionary = SaveService.load_tape(String(entry.get("tape", "")))
	var frames: Array[PackedByteArray] = []
	for f in tape.get("frames", []):
		frames.append(f)
	if frames.is_empty():
		EventBus.toast.emit("The tape is blank. Someone has taped over it.")
		return
	cc.begin_playback(&"echo", frames, float(tape.get("fps", 10)), "GUEST NO. %d - YOUR TAPE" % int(entry.get("guest", 0)))


static func _play_baked(session: Node, id: StringName, cc: Camcorder) -> void:
	if _busy:
		return
	if RunState.battery <= 0.0:
		EventBus.toast.emit("The camcorder is dead.")
		return
	if session.has_method("encounter_active") and session.encounter_active():
		EventBus.toast.emit("The tape sticks in the deck. Something is close.")
		return
	_busy = true
	var main := Main.instance
	var player: Player = session.get("player") as Player
	var was_frozen := player != null and player.frozen
	if player != null:
		player.frozen = true
	var prev_mix := 1.0 if cc.state == Camcorder.State.RAISED else 0.0
	AudioDirector.play(&"tape_glitch")
	main.set_cam_mix(1.0)
	main.set_glitch(0.55)
	var tex := ImageTexture.create_from_image(Image.create_empty(TapeBuffer.W, TapeBuffer.H, false, Image.FORMAT_RGB8))
	tex.update(TapeBuffer.to_image(_noise(0)))
	main.show_footage(tex)
	var tick := func(i: int, _n: int) -> void:
		tex.update(TapeBuffer.to_image(_noise(i)))
	var frames: Array[PackedByteArray]
	if _cache.has(id):
		frames = _cache[id]
		for i in 4:
			await session.get_tree().process_frame
			tick.call(i, 4)
	else:
		frames = await bake_frames(session, id, tick)
		_remember(id, frames)
	var alive := is_instance_valid(session) and not bool(session.get("blackout_done")) and not bool(session.get("cleared"))
	if alive and player != null and is_instance_valid(player) and not was_frozen:
		player.frozen = false
	main.set_glitch(0.0)
	main.set_cam_mix(prev_mix)
	if alive and not frames.is_empty():
		cc.begin_playback(&"echo", frames, FPS, clip_label(id))
	if not alive or cc.state != Camcorder.State.PLAYBACK:
		main.hide_footage()
	_busy = false


# --- baking ----------------------------------------------------------------------------------

static func bake_frames(session: Node, id: StringName, on_frame: Callable = Callable()) -> Array[PackedByteArray]:
	## Renders clip `id` to 128x96 RGB8 frames at 10 fps (coroutine: `await` it). Pauses the live recorder and the
	## world viewport while it runs and restores everything afterwards. Returns static when nothing can render.
	var main := Main.instance
	if main == null or _headless() or not has_clip(id):
		return static_frames()
	var t0 := Time.get_ticks_msec()
	var tree := main.get_tree()
	var vp := main.tape_viewport
	var rec: TapeRecorder = null
	if session != null and is_instance_valid(session):
		rec = session.get("recorder") as TapeRecorder
	var cam: Camera3D = rec.tape_cam if rec != null else (vp.get_node_or_null("TapeCam") as Camera3D)
	var made_cam := false
	if cam == null:
		cam = Camera3D.new()
		cam.name = "TapeCam"
		cam.near = 0.05
		cam.far = 60.0
		vp.add_child(cam)
		made_cam = true
	cam.current = true
	var prev_xform := cam.global_transform
	var prev_fov := cam.fov
	var prev_env := cam.environment
	var prev_rec := rec != null and rec.enabled
	var prev_game_mode := main.game_viewport.render_target_update_mode
	if rec != null:
		rec.enabled = false
		# a capture the recorder already asked for must land before we borrow the tape viewport
		var waited := 0
		while rec._waiting and waited < 120:
			waited += 1
			await tree.process_frame
	var parent: Node = main.game_viewport
	if session != null and is_instance_valid(session) and session.get("stage") != null:
		parent = session.get("stage")
	var stage := EchoStage.new(Themes.get_theme(EchoClips.floor_of(id)))
	stage.attach(parent)
	EchoClips.build(id, stage)
	cam.environment = stage.env
	main.game_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var n := int(round(EchoClips.duration(id) * FPS))
	var frames: Array[PackedByteArray] = []
	# Frames are drawn on demand (RenderingServer.force_draw without presenting) a handful per engine frame:
	# the bake does not depend on the window's vsync, and the "loading" static keeps animating between batches.
	var i := -WARMUP_FRAMES
	while i < n:
		if not is_instance_valid(main) or not is_instance_valid(stage.root):
			break
		for _k in BATCH:
			if i >= n:
				break
			EchoClips.tick(id, stage, maxf(0.0, float(i) * STEP))
			stage.apply_camera(cam)
			_sync_transforms(stage.root)
			cam.force_update_transform()
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			RenderingServer.force_draw(false)
			if i >= 0:
				var img := vp.get_texture().get_image()
				if img.get_format() != Image.FORMAT_RGB8:
					img.convert(Image.FORMAT_RGB8)
				frames.append(img.get_data())
			i += 1
		if on_frame.is_valid():
			on_frame.call(maxi(0, i), n)
		await tree.process_frame
	# put everything back
	stage.dispose()
	if is_instance_valid(cam):
		cam.environment = prev_env
		cam.global_transform = prev_xform
		cam.fov = prev_fov
		if made_cam:
			cam.queue_free()
	if is_instance_valid(main):
		main.game_viewport.render_target_update_mode = prev_game_mode
	if rec != null and is_instance_valid(rec):
		rec.enabled = prev_rec
	last_bake_ms = Time.get_ticks_msec() - t0
	return _finish(frames, id)


static func _sync_transforms(n: Node) -> void:
	## Node3D transform changes are pushed to the renderer at the end of the engine frame; a batch of draws inside one
	## frame has to push them itself.
	if n is Node3D:
		(n as Node3D).force_update_transform()
	for c in n.get_children():
		_sync_transforms(c)


static func _finish(frames: Array[PackedByteArray], id: StringName) -> Array[PackedByteArray]:
	## Tape character: a tracking flash as the tape starts, a few torn frames, and a burst of static at the cut.
	var out: Array[PackedByteArray] = []
	if frames.is_empty():
		return out
	out.append(_noise(0))
	out.append(_tear(frames[0], 0))
	for i in frames.size():
		out.append(frames[i])
	var inv := String(id).ends_with("_inv")
	var n := out.size()
	for k in [int(float(n) * 0.38), int(float(n) * 0.71)]:
		if k > 3 and k < n - 3:
			out[k] = _tear(out[k], k)
			out[k + 1] = _tear(out[k + 1], k + 3)
	var tail := 4 if inv else 2
	for j in tail:
		out[n - 1 - j] = _noise(j + 1) if j < tail - 1 or not inv else _tear(_noise(j), j)
	if inv:
		out[n - tail - 1] = _tear(out[n - tail - 1], 9)
	return out


static func _remember(id: StringName, frames: Array[PackedByteArray]) -> void:
	if frames.is_empty():
		return
	_cache[id] = frames
	_cache_order.erase(id)
	_cache_order.append(id)
	while _cache_order.size() > MAX_CACHE:
		_cache.erase(_cache_order.pop_front())


static func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()


# --- static and tape damage ------------------------------------------------------------------

static func _noise(i: int) -> PackedByteArray:
	## One of eight fixed frames of tape snow (grey luma noise), built once.
	if _noise_pool.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		for f in 8:
			var b := PackedByteArray()
			b.resize(TapeBuffer.FRAME_BYTES)
			var p := 0
			for y in TapeBuffer.H:
				var row_boost := 55 if (rng.randi() % 23) == 0 else 0
				for x in TapeBuffer.W:
					var v := clampi(int(rng.randi() % 90) + 14 + row_boost, 0, 255)
					b[p] = v
					b[p + 1] = v
					b[p + 2] = v
					p += 3
			_noise_pool.append(b)
	return _noise_pool[absi(i) % _noise_pool.size()]


static func static_frames() -> Array[PackedByteArray]:
	## A few frames of tape noise, used when a clip is unavailable (and in headless runs).
	var out: Array[PackedByteArray] = []
	for f in 12:
		out.append(_noise(f))
	return out


static func _tear(frame: PackedByteArray, seed_value: int) -> PackedByteArray:
	## A tracking glitch: a band of rows slides sideways, with a bright snowy row at its edge.
	var row := TapeBuffer.W * 3
	var y0 := 8 + (seed_value * 37) % 60
	var h := 10 + (seed_value * 13) % 14
	var shift := 3 + (seed_value * 7) % 9
	var out := PackedByteArray()
	for y in TapeBuffer.H:
		var line := frame.slice(y * row, (y + 1) * row)
		if y >= y0 and y < y0 + h:
			var s := ((shift * 3) % row) if (y - y0) % 2 == 0 else (((shift + 2) * 3) % row)
			line = line.slice(s) + line.slice(0, s)
			if y == y0:
				line = _noise(seed_value).slice(y * row, (y + 1) * row)
		out.append_array(line)
	return out


# --- dev helpers -----------------------------------------------------------------------------

static func contact_sheet(frames: Array[PackedByteArray], step: int = 10, cols: int = 4, scale: int = 2) -> Image:
	## Every `step`-th frame laid out in a grid (dev harness / review).
	var picks: Array[int] = []
	for i in range(0, frames.size(), maxi(1, step)):
		picks.append(i)
	var rows := int(ceil(float(picks.size()) / float(cols)))
	var w := TapeBuffer.W * scale
	var h := TapeBuffer.H * scale
	var sheet := Image.create(cols * (w + 2), rows * (h + 2), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.2, 0.0, 0.2))
	for k in picks.size():
		var img := TapeBuffer.to_image(frames[picks[k]])
		img.resize(w, h, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((k % cols) * (w + 2), (k / cols) * (h + 2)))
	return sheet
