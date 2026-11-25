class_name PauseScreen
extends ScreenBase
## Esc mid-floor. The world is paused. Resume, the notebook and the card (both opened on top of this screen),
## Settings, or abandon the run (back to the menu; the run resumes from the last elevator checkpoint).

var session: FloorSession = null
var _box: VBoxContainer
var _main_rows: VBoxContainer
var _confirm_rows: VBoxContainer


func setup(p_args: Dictionary = {}) -> void:
	super.setup(p_args)
	session = args.get("session") as FloorSession
	dim_world = 0.6


func _build() -> void:
	_box = center_panel(520)
	_box.add_child(UIKit.label("PAUSED", 30, UIKit.ACCENT, true))
	_box.add_child(UIKit.label("Management has placed your stay on hold.", 15, UIKit.INK_DIM))
	if session != null and session.def != null:
		_box.add_child(UIKit.label("%s  -  Guest no. %d" % [session.def.title, RunState.guest_number], 15, UIKit.INK_DIM))
	_box.add_child(HSeparator.new())

	_main_rows = VBoxContainer.new()
	_main_rows.add_theme_constant_override("separation", 6)
	_box.add_child(_main_rows)
	_main_rows.add_child(UIKit.button("Resume", func() -> void: _resume()))
	var nb := UIKit.button("Notebook  [%s]" % UIKit.key_label(&"notebook"), func() -> void: click(); open_child(&"notebook", {"session": session}))
	nb.disabled = session == null
	_main_rows.add_child(nb)
	var cd := UIKit.button("Re-read the card  [%s]" % UIKit.key_label(&"card"), func() -> void: click(); open_child(&"card", {"session": session, "mode": &"review"}))
	cd.disabled = session == null
	_main_rows.add_child(cd)
	_main_rows.add_child(UIKit.button("Settings", func() -> void: click(); open_child(&"settings")))
	_main_rows.add_child(UIKit.button("Abandon run", func() -> void: click(); _ask_abandon()))

	_confirm_rows = VBoxContainer.new()
	_confirm_rows.add_theme_constant_override("separation", 6)
	_confirm_rows.visible = false
	_box.add_child(_confirm_rows)
	_confirm_rows.add_child(ScreenWidgets.wrap("Leave the building and return to the front desk? This floor will be forgotten. \"Continue\" resumes from your last elevator.", 16, UIKit.INK))
	_confirm_rows.add_child(UIKit.button("Yes, abandon this run", func() -> void: click(); _abandon()))
	_confirm_rows.add_child(UIKit.button("No, keep going", func() -> void: click(); _cancel_abandon()))


func _ask_abandon() -> void:
	_main_rows.visible = false
	_confirm_rows.visible = true
	# the confirm rows are the last children: focus the safe answer
	var b := _confirm_rows.get_child(_confirm_rows.get_child_count() - 1) as Button
	if b != null:
		b.grab_focus()


func _cancel_abandon() -> void:
	_confirm_rows.visible = false
	_main_rows.visible = true
	_focus_first()


func _resume() -> void:
	click()
	close()


func _abandon() -> void:
	close(&"abandon")
	Game.show_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _confirm_rows != null and _confirm_rows.visible:
			_cancel_abandon()
		else:
			_resume()
