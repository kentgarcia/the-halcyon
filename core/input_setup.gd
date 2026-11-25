class_name InputSetup
extends RefCounted
## Registers every gameplay action with keyboard+mouse and gamepad defaults (SPEC 11.2).
## Done in code so the project has no hand-edited InputMap section. Gameplay code never reads Input
## directly: it goes through PlayerInput.

const ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"look_left", &"look_right", &"look_up", &"look_down",
	&"sprint", &"crouch", &"interact", &"camcorder", &"lamp", &"playback",
	&"freeze_frame", &"stakeout", &"card", &"notebook", &"pause", &"use_item",
]


static func ensure_actions() -> void:
	_key(&"move_forward", KEY_W)
	_key(&"move_forward", KEY_UP)
	_key(&"move_back", KEY_S)
	_key(&"move_back", KEY_DOWN)
	_key(&"move_left", KEY_A)
	_key(&"move_left", KEY_LEFT)
	_key(&"move_right", KEY_D)
	_key(&"move_right", KEY_RIGHT)
	_axis(&"move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis(&"move_right", JOY_AXIS_LEFT_X, 1.0)
	_axis(&"move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_axis(&"move_back", JOY_AXIS_LEFT_Y, 1.0)
	_axis(&"look_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis(&"look_right", JOY_AXIS_RIGHT_X, 1.0)
	_axis(&"look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis(&"look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_key(&"sprint", KEY_SHIFT)
	_pad(&"sprint", JOY_BUTTON_LEFT_STICK)
	_key(&"crouch", KEY_CTRL)
	_key(&"crouch", KEY_C)
	_pad(&"crouch", JOY_BUTTON_B)
	_key(&"interact", KEY_E)
	_pad(&"interact", JOY_BUTTON_A)
	_mouse(&"camcorder", MOUSE_BUTTON_RIGHT)
	_axis(&"camcorder", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_key(&"lamp", KEY_F)
	_pad(&"lamp", JOY_BUTTON_LEFT_SHOULDER)
	_key(&"playback", KEY_R)
	_pad(&"playback", JOY_BUTTON_RIGHT_SHOULDER)
	_mouse(&"freeze_frame", MOUSE_BUTTON_LEFT)
	_axis(&"freeze_frame", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_key(&"stakeout", KEY_G)
	_pad(&"stakeout", JOY_BUTTON_DPAD_DOWN)
	_key(&"use_item", KEY_X)
	_pad(&"use_item", JOY_BUTTON_X)
	_key(&"card", KEY_Q)
	_pad(&"card", JOY_BUTTON_Y)
	_key(&"notebook", KEY_TAB)
	_pad(&"notebook", JOY_BUTTON_BACK)
	_key(&"pause", KEY_ESCAPE)
	_pad(&"pause", JOY_BUTTON_START)
	for a in ACTIONS:
		InputMap.action_set_deadzone(a, 0.25)


static func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


static func _key(action: StringName, keycode: Key) -> void:
	_ensure(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


static func _mouse(action: StringName, button: MouseButton) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


static func _pad(action: StringName, button: JoyButton) -> void:
	_ensure(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


static func _axis(action: StringName, axis: JoyAxis, value: float) -> void:
	_ensure(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)
