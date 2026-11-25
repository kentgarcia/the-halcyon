class_name ScreenBase
extends Control
## Base of every full-screen UI (card, notebook, menus...). Hosted by Game.open(): added to Main.ui, pauses the
## world while open (unless `pauses_world` is false), frees the mouse, and gives focus to the first button.
## Contract for authors: `extends ScreenBase`, define `setup(args: Dictionary)`, build the UI in `_build()`,
## and call `close(result)` when done. Never read gameplay state you do not need; never mutate RunState except
## through its methods.

signal closed(result: Variant)

var pauses_world := true
var dim_world := 0.0                      ## 0..1 black backdrop behind the panel (0 = world visible)
var args: Dictionary = {}
var _result: Variant = null
var _closed := false


func setup(p_args: Dictionary = {}) -> void:
	args = p_args


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIKit.theme()
	if dim_world > 0.0:
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, dim_world)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	_build()
	call_deferred("_focus_first")


func _build() -> void:
	pass


func _focus_first() -> void:
	var b := _find_button(self)
	if b != null and is_inside_tree():
		b.grab_focus()


func _find_button(n: Node) -> Button:
	for c in n.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Button and not (c as Button).disabled and (c as Button).focus_mode != Control.FOCUS_NONE and (c as Button).is_visible_in_tree():
			return c
		var r := _find_button(c)
		if r != null:
			return r
	return null


func close(result: Variant = null) -> void:
	if _closed:
		return
	_closed = true
	_result = result
	closed.emit(result)
	if is_inside_tree():
		queue_free()


## Opens another screen on top of this one. This screen hides while the child is open (stacked panels would
## show through each other) and, when the child closes, shows again and gives the focus back to whatever had it
## (a freed screen takes its focused button with it, which would otherwise strand keyboard/gamepad users).
## Returns null when there is no Game/Main to host it (headless tests).
func open_child(screen_id: StringName, child_args: Dictionary = {}) -> ScreenBase:
	if Game.main == null:
		return null
	var back: Variant = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var s := Game.open(screen_id, child_args)
	if s != null:
		visible = false
		s.closed.connect(func(_r: Variant) -> void: _restore.call_deferred(back), CONNECT_ONE_SHOT)
	return s


func _restore(back: Variant) -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	visible = true
	if is_instance_valid(back) and back is Control and (back as Control).is_visible_in_tree() \
			and (back as Control).focus_mode != Control.FOCUS_NONE:
		(back as Control).grab_focus()
	else:
		_focus_first()


## Keyboard/gamepad safety net: if nothing has focus (a focused button was freed, or the mouse cleared it),
## the first navigation or accept press puts focus back on the first button instead of doing nothing.
## Subclasses that override `_input` must call `super(event)`.
func _input(event: InputEvent) -> void:
	if not is_inside_tree() or get_viewport().gui_get_focus_owner() != null:
		return
	if event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_left") \
			or event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_accept"):
		var b := _find_button(self)
		if b != null:
			b.grab_focus()
			get_viewport().set_input_as_handled()


func click() -> void:
	AudioDirector.play(&"ui_click")


## Centered panel helper: returns the VBox inside a bordered panel of the given width.
func center_panel(width: float = 760.0) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var p := UIKit.panel(Vector2(width, 0))
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	return v
