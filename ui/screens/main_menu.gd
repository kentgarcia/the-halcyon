class_name MainMenu
extends ScreenBase
## The front desk. Continue (only with a checkpoint save), New Run, Settings, Quit.
## Closes with {"action": &"continue"} or {"action": &"new"}; Game._on_menu_closed starts the run.

var _title: Label
var _t := 0.0


func setup(p_args: Dictionary = {}) -> void:
	super.setup(p_args)
	pauses_world = false
	dim_world = 1.0


func _build() -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(480, 0)
	v.add_theme_constant_override("separation", 10)
	cc.add_child(v)

	_title = UIKit.label("THE HALCYON", 64, UIKit.ACCENT, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	var sub := UIKit.label("Please review the House Rules.", 18, UIKit.INK_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(ScreenWidgets.spacer(26))

	var has_run := Game.has_saved_run()
	if has_run:
		var cont := _menu_button("Continue", func() -> void: click(); close({"action": &"continue"}))
		v.add_child(cont)
		var info := UIKit.label(_saved_run_line(), 14, UIKit.INK_DIM)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(info)
	v.add_child(_menu_button("New Run", func() -> void: click(); close({"action": &"new"})))
	v.add_child(_menu_button("Settings", func() -> void: click(); open_child(&"settings", {"dim": 1.0})))
	v.add_child(_menu_button("Quit", func() -> void: click(); get_tree().quit()))

	v.add_child(ScreenWidgets.spacer(30))
	v.add_child(HSeparator.new())
	var stats := UIKit.label(_stats_line(), 15, UIKit.INK_DIM)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stats)
	var endings := UIKit.label(_endings_line(), 15, UIKit.INK_DIM)
	endings.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(endings)
	var hint := UIKit.label("Arrow keys / D-pad to choose.  Enter / A to select.", 13, UIKit.INK_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


func _menu_button(text: String, cb: Callable) -> Button:
	var b := UIKit.button(text, cb)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 24)
	return b


func _saved_run_line() -> String:
	var run: Dictionary = SaveService.data.get("run", {})
	var fid := StringName(String(run.get("floor_id", "")))
	var def := FloorCatalog.get_def(fid) if fid != &"" else null
	var where := def.short_name if def != null else "the elevator"
	return "Resume at %s  -  Guest no. %d" % [where, int(run.get("guest_number", 1))]


func _stats_line() -> String:
	var st: Dictionary = SaveService.data.get("stats", {})
	return "Floors cleared: %d     Blackouts: %d" % [int(st.get("floors_cleared", 0)), int(st.get("blackouts", 0))]


func _endings_line() -> String:
	var seen := 0
	for e in [&"checkout", &"desk", &"burn"]:
		if SaveService.has_ending(e):
			seen += 1
	return "Endings seen: %d of 3     Next guest: no. %d" % [seen, int(SaveService.data.get("next_guest", 1))]


func _process(delta: float) -> void:
	# A tired sign: slow brightness drift plus one brief dip every few seconds. Deterministic (no RNG).
	_t += delta
	if _title == null:
		return
	if Settings.reduce_motion or Settings.safe_flicker:
		_title.modulate.a = 1.0
		return
	var a := 0.95 + 0.05 * sin(_t * 1.7) * sin(_t * 0.37)
	if fmod(_t, 13.0) > 12.8:
		a = 0.6        # one dip, 0.2 s, every 13 s: far below the 3 Hz flash limit
	_title.modulate.a = a
