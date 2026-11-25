class_name Player
extends CharacterBody3D
## First-person guest (SPEC 3.2). No combat, no stamina bar. Walk 2.2 / sprint 4.0 / crouch 1.2 m/s.
## All input comes from the PlayerInput component. Footsteps post noise events that entities hear.

signal interact_focus_changed(interactable: Interactable)

const GRAVITY := 18.0
const ACCEL := 14.0
const FRICTION := 18.0
const STEP_LENGTH := {&"walk": 1.55, &"sprint": 1.95, &"crouch": 1.15}
const NOISE := {&"walk": 0.3, &"sprint": 1.0, &"crouch": 0.1}

var input: PlayerInput
var head: Node3D
var camera: Camera3D
var capsule: CapsuleShape3D
var col: CollisionShape3D
var nerve: Nerve
var camcorder: Node = null          ## Camcorder component (added by the run setup)

var surface: StringName = &"carpet"
var crouching := false
var sprinting := false
var hidden := false                 ## inside a hide spot
var frozen := false                 ## no movement (cutscenes, playback with no world)
var speed_mods: Dictionary = {}     ## name -> multiplier
var eye_height := GameScale.EYE_HEIGHT
var pitch := 0.0
var look_locked := false
var hide_spot: Node3D = null         ## the HideSpot we are in (null when not hiding)
var _hide_yaw := 0.0
var _hide_range := deg_to_rad(55.0)
var _hide_eye := 1.0
var _hide_prev_crouch := false
var _bob_phase := 0.0
var _step_accum := 0.0
var _height := GameScale.PLAYER_HEIGHT
var _fov_target := Settings.fov
var _shake := 0.0

var focus: Interactable = null
var interact_progress := 0.0        ## 0..1 for HOLD_PROGRESS interactions (HUD ring)
var _held: Interactable = null
var _held_time := 0.0
var _hold_fired := false
var _wait_release := false
var _focus_cd := 0.0
var _last_prompt := ""


func _ready() -> void:
	add_to_group(&"player")
	collision_layer = GameScale.LAYER_PLAYER
	collision_mask = GameScale.LAYER_WORLD | GameScale.LAYER_DOORS | GameScale.LAYER_PROPS
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = 0.3
	floor_stop_on_slope = true

	col = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = GameScale.PLAYER_RADIUS
	capsule.height = GameScale.PLAYER_HEIGHT
	col.shape = capsule
	col.position = Vector3(0.0, GameScale.PLAYER_HEIGHT * 0.5, 0.0)
	add_child(col)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, eye_height, 0.0)
	add_child(head)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = Settings.fov
	camera.near = 0.05
	camera.far = 80.0
	head.add_child(camera)

	input = PlayerInput.new()
	input.name = "PlayerInput"
	add_child(input)
	nerve = Nerve.new()
	nerve.name = "Nerve"
	add_child(nerve)
	camera.current = true


func _process(delta: float) -> void:
	_update_look(delta)
	_update_height(delta)
	_update_focus(delta)
	_update_interaction(delta)
	_update_camera(delta)


func _physics_process(delta: float) -> void:
	if frozen or hidden:
		velocity = Vector3(0.0, velocity.y, 0.0)
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	var mv := input.move
	var wish := Vector3.ZERO
	if mv.length() > 0.01:
		var basis_y := Basis(Vector3.UP, rotation.y)
		wish = (basis_y * Vector3(mv.x, 0.0, -mv.y)).normalized() * mv.length()
	var gait := &"walk"
	var spd := GameScale.WALK_SPEED
	sprinting = false
	if crouching:
		gait = &"crouch"
		spd = GameScale.CROUCH_SPEED
	elif input.sprint_requested() and mv.y > 0.3 and not _speed_blocked():
		gait = &"sprint"
		spd = GameScale.SPRINT_SPEED
		sprinting = true
	for k in speed_mods:
		spd *= float(speed_mods[k])
	var target := wish * spd
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if wish.length() > 0.01:
		horiz = horiz.move_toward(target, ACCEL * spd * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, FRICTION * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	_footsteps(delta, gait, horiz.length())


func _speed_blocked() -> bool:
	return speed_mods.has(&"camcorder") or speed_mods.has(&"carry")


# --- look / camera --------------------------------------------------------------------------

func _update_look(_delta: float) -> void:
	if look_locked or frozen:
		return
	var l := input.look
	if l != Vector2.ZERO:
		rotation.y -= l.x
		var pmax := 85.0
		if hidden:
			rotation.y = _hide_yaw + clampf(angle_difference(_hide_yaw, rotation.y) * -1.0, -_hide_range, _hide_range) * -1.0
			pmax = 22.0
		pitch = clampf(pitch - l.y, deg_to_rad(-pmax), deg_to_rad(pmax))
		head.rotation.x = pitch


func _update_height(delta: float) -> void:
	var want_crouch := false
	if Settings.crouch_toggle:
		if input.just_pressed(&"crouch") and not hidden:
			if crouching and _can_stand():
				crouching = false
			else:
				crouching = true
		want_crouch = crouching
	else:
		want_crouch = input.is_down(&"crouch")
		if not want_crouch and crouching and not _can_stand():
			want_crouch = true
		crouching = want_crouch
	var target_h := GameScale.PLAYER_CROUCH_HEIGHT if crouching else GameScale.PLAYER_HEIGHT
	_height = move_toward(_height, target_h, 4.5 * delta)
	capsule.height = _height
	col.position.y = _height * 0.5
	var target_eye := GameScale.EYE_CROUCH if crouching else GameScale.EYE_HEIGHT
	if hidden:
		target_eye = _hide_eye
	eye_height = move_toward(eye_height, target_eye, 3.0 * delta)


func _can_stand() -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.2, 0), global_position + Vector3(0, GameScale.PLAYER_HEIGHT + 0.1, 0), GameScale.LAYER_WORLD)
	q.exclude = [get_rid()]
	return space.intersect_ray(q).is_empty()


func _update_camera(delta: float) -> void:
	var bob := 0.0
	if Settings.head_bob and not Settings.reduce_motion and is_on_floor():
		var sp := Vector2(velocity.x, velocity.z).length()
		if sp > 0.2:
			_bob_phase += sp * delta * 4.2
			bob = sin(_bob_phase) * (0.028 if sprinting else 0.016) * clampf(sp / 2.2, 0.0, 1.6)
	var shake_off := Vector3.ZERO
	if _shake > 0.0 and not Settings.reduce_motion:
		_shake = maxf(0.0, _shake - delta * 1.6)
		shake_off = Vector3(_cos().randf_range(-1.0, 1.0), _cos().randf_range(-1.0, 1.0), 0.0) * _shake * 0.02
	head.position = Vector3(0.0, eye_height + bob, 0.0) + shake_off
	camera.fov = lerpf(camera.fov, _fov_target, clampf(delta * 8.0, 0.0, 1.0))


func _cos() -> RandomNumberGenerator:
	return RunState.stream(&"cosmetic")


func set_fov_target(f: float) -> void:
	_fov_target = f


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func eye_position() -> Vector3:
	return head.global_position


func look_direction() -> Vector3:
	return -camera.global_transform.basis.z


func teleport(pos: Vector3, yaw: float = 0.0) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	rotation.y = yaw
	pitch = 0.0
	head.rotation.x = 0.0


# --- footsteps ------------------------------------------------------------------------------

func _footsteps(delta: float, gait: StringName, speed: float) -> void:
	if speed < 0.4 or not is_on_floor():
		_step_accum = 0.0
		return
	_step_accum += speed * delta
	if _step_accum >= float(STEP_LENGTH[gait]):
		_step_accum = 0.0
		var snd := StringName("step_%s" % surface)
		AudioDirector.play(snd, -2.0 if gait == &"crouch" else 0.0, _cos().randf_range(0.94, 1.06) if gait != &"crouch" else 0.9)
		EventBus.noise_emitted.emit(global_position, float(NOISE[gait]), &"step")


func noise_level() -> float:
	## Current instantaneous noise (used by sensors that sample rather than listen).
	var sp := Vector2(velocity.x, velocity.z).length()
	if hidden or sp < 0.4:
		return 0.0
	if sprinting:
		return float(NOISE[&"sprint"])
	return float(NOISE[&"crouch"]) if crouching else float(NOISE[&"walk"])


# --- interaction ----------------------------------------------------------------------------

func _update_focus(delta: float) -> void:
	_focus_cd -= delta
	if _focus_cd > 0.0:
		return
	_focus_cd = 0.05
	var best: Interactable = null
	if not hidden or true:
		best = _pick_focus()
	if best != focus:
		focus = best
		interact_focus_changed.emit(focus)
	var text := ""
	if focus != null and not frozen:
		text = focus.current_prompt(self)
	if text != _last_prompt:
		_last_prompt = text
		EventBus.prompt_changed.emit(text)


func _pick_focus() -> Interactable:
	if frozen or not input.enabled:
		return null
	var cam_pos := camera.global_position
	var fwd := look_direction()
	var cone := deg_to_rad(GameScale.INTERACT_CONE_DEG)
	var cands: Array = []
	for n in get_tree().get_nodes_in_group(&"interactable"):
		var it := n as Interactable
		if it == null or not it.is_inside_tree() or not it.available(self):
			continue
		var p := it.global_position
		var to := p - cam_pos
		var dist := to.length()
		if dist > it.max_range or dist < 0.01:
			continue
		var ang := fwd.angle_to(to)
		if ang > cone:
			continue
		cands.append({"it": it, "score": ang * 2.0 + dist * 0.25, "pos": p})
	if cands.is_empty():
		return null
	cands.sort_custom(func(a, b): return a["score"] < b["score"])
	var space := get_world_3d().direct_space_state
	for c in cands:
		var q := PhysicsRayQueryParameters3D.create(cam_pos, c["pos"], GameScale.LAYER_WORLD | GameScale.LAYER_DOORS)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit["position"] as Vector3).distance_to(c["pos"]) < 0.55:
			return c["it"]
	return null


func _update_interaction(delta: float) -> void:
	interact_progress = 0.0
	if frozen:
		return
	if hidden:
		if input.just_pressed(&"interact"):
			exit_hide()
		return
	if _held != null:
		var it := _held
		var valid := is_instance_valid(it) and it.is_inside_tree() and it.available(self) \
			and it.global_position.distance_to(camera.global_position) <= it.max_range + 0.6
		if not valid:
			_end_hold(true)
		elif input.is_down(&"interact"):
			_held_time += delta
			match it.mode:
				Interactable.Mode.HOLD_PROGRESS:
					interact_progress = clampf(_held_time / maxf(0.01, it.hold_duration), 0.0, 1.0)
					if _held_time >= it.hold_duration:
						it.do_tap(self)
						_held = null
						_wait_release = true
				Interactable.Mode.HOLD_LIVE:
					if not _hold_fired and _held_time >= it.hold_threshold:
						_hold_fired = true
						it.do_hold_start(self)
		else:
			_end_hold(false)
	if _wait_release:
		if not input.is_down(&"interact"):
			_wait_release = false
		return
	if input.just_pressed(&"interact") and _held == null and focus != null and focus.available(self):
		match focus.mode:
			Interactable.Mode.TAP:
				focus.do_tap(self)
			_:
				_held = focus
				_held_time = 0.0
				_hold_fired = false


func _end_hold(cancelled: bool) -> void:
	var it := _held
	_held = null
	if it == null or not is_instance_valid(it):
		return
	if it.mode == Interactable.Mode.HOLD_LIVE:
		if _hold_fired:
			it.do_hold_end(self)
		elif not cancelled:
			it.do_tap(self)
	_hold_fired = false
	_held_time = 0.0


func cancel_interaction() -> void:
	_end_hold(true)


# --- hiding (SPEC 3.2) ----------------------------------------------------------------------

func enter_hide(spot: Node3D, eye: float, yaw_range_deg: float = 55.0) -> void:
	## Noise ~0, sight ~0, view limited to a slat's width. The caller (HideSpot) owns the visuals.
	if hidden:
		return
	cancel_interaction()
	hide_spot = spot
	hidden = true
	_hide_prev_crouch = crouching
	crouching = true
	_hide_eye = eye
	_hide_range = deg_to_rad(yaw_range_deg)
	col.disabled = true
	global_position = spot.global_position
	_hide_yaw = spot.global_rotation.y
	rotation.y = _hide_yaw
	pitch = 0.0
	head.rotation.x = 0.0
	velocity = Vector3.ZERO
	EventBus.hide_changed.emit(true)


func exit_hide() -> void:
	if not hidden:
		return
	var spot := hide_spot
	hidden = false
	hide_spot = null
	col.disabled = false
	crouching = _hide_prev_crouch
	if spot != null and is_instance_valid(spot) and spot.has_method("exit_position"):
		global_position = spot.exit_position()
		if spot.has_method("on_exit"):
			spot.on_exit()
	EventBus.hide_changed.emit(false)
