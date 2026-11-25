class_name PlayerInput
extends Node
## The only place gameplay input is read (CLAUDE.md non-negotiable; also the seam for touch and
## co-op). Hardware mode polls the InputMap; scripted mode lets bots and tests drive the same fields,
## so everything downstream behaves identically.
##
## Per idle frame (process priority -100) it snapshots: down / just_pressed / just_released /
## hold time per action, plus `move` and `look`. Consumers read them in their own _process.

enum Mode { HARDWARE, SCRIPTED }

var mode: int = Mode.HARDWARE
var enabled := true                    ## false while menus/notebook/cutscenes own the input
var mouse_look := true

var move: Vector2 = Vector2.ZERO       ## x = strafe right, y = forward
var look: Vector2 = Vector2.ZERO       ## radians this frame (x = yaw right, y = pitch down)

var _down: Dictionary = {}
var _prev: Dictionary = {}
var _pressed: Dictionary = {}
var _released: Dictionary = {}
var _hold: Dictionary = {}
var _mouse_accum := Vector2.ZERO

# scripted sources
var virtual_down: Dictionary = {}
var virtual_move: Vector2 = Vector2.ZERO
var virtual_look: Vector2 = Vector2.ZERO
var _tap_queue: Array = []             ## actions to be down for exactly one frame
var _last_frame := -1                  ## last process frame this node ran (a gap means the tree was paused)


func _ready() -> void:
	process_priority = -100
	process_physics_priority = -100


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.HARDWARE or not enabled or not mouse_look:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_accum += (event as InputEventMouseMotion).relative


func _process(delta: float) -> void:
	_prev = _down.duplicate()
	var frame := Engine.get_process_frames()
	var resumed := _last_frame >= 0 and frame - _last_frame > 1
	_last_frame = frame
	var cur := {}
	if enabled:
		if mode == Mode.HARDWARE:
			for a in InputSetup.ACTIONS:
				cur[a] = Input.is_action_pressed(a)
			move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
			var sens := Settings.mouse_sensitivity
			var yinv := -1.0 if Settings.invert_y else 1.0
			look = Vector2(_mouse_accum.x * sens, _mouse_accum.y * sens * yinv)
			var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
			look += stick * 2.6 * delta * Vector2(1.0, yinv)
		else:
			for a in InputSetup.ACTIONS:
				cur[a] = bool(virtual_down.get(a, false))
			for a2 in _tap_queue:
				cur[a2] = true
			_tap_queue.clear()
			move = virtual_move
			look = virtual_look
			virtual_look = Vector2.ZERO
	else:
		move = Vector2.ZERO
		look = Vector2.ZERO
		for a in InputSetup.ACTIONS:
			cur[a] = false
	_mouse_accum = Vector2.ZERO
	_down = cur
	if resumed and mode == Mode.HARDWARE:
		# The tree was paused (a menu owned the input). A key still held when it resumes - typically the key that
		# closed the menu, e.g. Esc closing the notebook - is not a fresh press, or it would open the next menu.
		_prev = cur.duplicate()
	for a in InputSetup.ACTIONS:
		var d: bool = cur.get(a, false)
		var p: bool = _prev.get(a, false)
		_pressed[a] = d and not p
		_released[a] = p and not d
		_hold[a] = (float(_hold.get(a, 0.0)) + delta) if d else 0.0


# --- queries --------------------------------------------------------------------------------

func is_down(action: StringName) -> bool:
	return bool(_down.get(action, false))


func just_pressed(action: StringName) -> bool:
	return bool(_pressed.get(action, false))


func just_released(action: StringName) -> bool:
	return bool(_released.get(action, false))


func hold_time(action: StringName) -> float:
	return float(_hold.get(action, 0.0))


func sprint_requested() -> bool:
	return is_down(&"sprint")


# --- scripted driving (bots, tests) ---------------------------------------------------------

func script_mode(on: bool = true) -> void:
	mode = Mode.SCRIPTED if on else Mode.HARDWARE


func hold(action: StringName, down: bool = true) -> void:
	virtual_down[action] = down


func tap(action: StringName) -> void:
	_tap_queue.append(action)


func set_move(v: Vector2) -> void:
	virtual_move = v.limit_length(1.0)


func add_look(yaw: float, pitch: float) -> void:
	virtual_look += Vector2(yaw, pitch)


func release_all() -> void:
	virtual_down.clear()
	virtual_move = Vector2.ZERO
	virtual_look = Vector2.ZERO
