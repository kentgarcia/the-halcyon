class_name SettingsScreen
extends ScreenBase
## Options (SPEC 11.3): Display, Comfort, Audio, Accessibility, Controls. Every change goes through
## Settings.set_value() so it applies live and is saved. Fully operable from keyboard / gamepad: arrows move,
## Enter toggles or cycles (Left/Right cycle too), Left/Right drag sliders, Esc goes back.

const TABS: Array[String] = ["Display", "Comfort", "Audio", "Accessibility", "Controls"]
const CONTROL_W := 300.0
const RENDER_PRESETS: Array = [240, 360, 480, 720, 0]
const RENDER_NAMES: Array[String] = ["240p  (chunky)", "360p  (default)", "480p", "720p", "Native"]
const FPS_PRESETS: Array = [0, 30, 60, 90, 120, 144, 240]
const TELL_PRESETS: Array = [1.0, 1.5, 2.0]
const TELL_NAMES: Array[String] = ["x1.0  (standard)", "x1.5", "x2.0"]
const NERVE_PRESETS: Array = [2, 3, 4]
const NERVE_NAMES: Array[String] = ["2 hits  (hard)", "3 hits  (standard)", "4 hits  (gentle)"]
const DENSITY_PRESETS: Array = [0.75, 1.0, 1.5, 2.0]
const DENSITY_NAMES: Array[String] = ["Sparse", "Standard", "Generous", "Plentiful"]
const DEFAULT_SENSITIVITY := 0.0022
const CONTROL_ROWS: Array = [
	["Move", &"move_forward"], ["Sprint", &"sprint"], ["Crouch", &"crouch"], ["Interact", &"interact"],
	["Raise camcorder", &"camcorder"], ["Lamp", &"lamp"], ["Playback", &"playback"], ["Freeze Frame", &"freeze_frame"],
	["Stakeout", &"stakeout"], ["House Rules card", &"card"], ["Notebook", &"notebook"], ["Pause", &"pause"],
]

static var _slider_theme: Theme = null

var _tab := -1
var _initial_tab := 0
var _bar: HFlowContainer
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _dragging := false
var _last_tick_ms := 0


func setup(p_args: Dictionary = {}) -> void:
	super.setup(p_args)
	_initial_tab = int(args.get("tab", 0))
	dim_world = float(args.get("dim", 0.85))


func _build() -> void:
	var v := ScreenWidgets.frame(self, 980.0)
	v.add_child(UIKit.label("SETTINGS", 28, UIKit.ACCENT, true))
	_bar = ScreenWidgets.tab_bar(PackedStringArray(TABS), _select_tab, _enter_tab)
	v.add_child(_bar)
	v.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	v.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	_scroll.add_child(_rows)
	v.add_child(HSeparator.new())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 20)
	v.add_child(foot)
	foot.add_child(UIKit.button("Back", func() -> void: _back()))
	var note := UIKit.label("Changes apply at once and are saved.   Esc: back   PgUp / PgDn or LB / RB: change tab", 13, UIKit.INK_DIM)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(note)
	_select_tab(clampi(_initial_tab, 0, TABS.size() - 1))


# --- tabs -------------------------------------------------------------------------------------

func _select_tab(i: int) -> void:
	if i == _tab:
		return
	_tab = i
	ScreenWidgets.tab_mark(_bar, i)
	ScreenWidgets.clear_children(_rows)
	_scroll.scroll_vertical = 0
	match i:
		0: _tab_display()
		1: _tab_comfort()
		2: _tab_audio()
		3: _tab_access()
		4: _tab_controls()


func _focus_first() -> void:
	# focusing a tab selects it, so start on the tab that is showing
	if _bar != null and _tab >= 0 and _tab < _bar.get_child_count():
		(_bar.get_child(_tab) as Control).grab_focus()
	else:
		super._focus_first()


func _enter_tab(_i: int) -> void:
	var c := _first_focusable(_rows)
	if c != null:
		c.grab_focus()


func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		var ctl := c as Control
		if ctl != null and ctl.focus_mode != Control.FOCUS_NONE and ctl.is_visible_in_tree():
			if not (ctl is BaseButton and (ctl as BaseButton).disabled):
				return ctl
		var r := _first_focusable(c)
		if r != null:
			return r
	return null


func _tab_display() -> void:
	_add_cycler(&"render_height", "Render resolution", RENDER_PRESETS, RENDER_NAMES, "Internal 3D height. Lower is chunkier and cheaper; the tape finish and text stay sharp.")
	_add_slider(&"retro_intensity", "Tape finish", 0.0, 1.0, 0.05, "pct", "Grain, scanlines and colour bleed.")
	_add_slider(&"vertex_snap", "Vertex wobble", 0.0, 1.0, 0.05, "pct", "Optional old-console jitter. Off by default.")
	_add_toggle(&"fullscreen", "Fullscreen")
	_add_toggle(&"vsync", "VSync")
	_add_cycler(&"max_fps", "Frame limit", FPS_PRESETS, ["Unlimited", "30", "60", "90", "120", "144", "240"])


func _tab_comfort() -> void:
	_add_slider(&"fov", "Field of view", 60.0, 110.0, 1.0, "deg")
	_add_slider(&"mouse_sensitivity", "Mouse sensitivity", 0.25, 4.0, 0.05, "x", "", DEFAULT_SENSITIVITY)
	_add_toggle(&"invert_y", "Invert look (Y axis)")
	_add_toggle(&"head_bob", "Head bob")
	_add_toggle(&"reduce_motion", "Reduce motion", "Turns off head bob, screen shake and vignette pulsing.")
	_add_toggle(&"safe_flicker", "Safe flicker", "Caps light flicker and the glitch band. Nothing flashes faster than 3 Hz.")
	_add_toggle(&"camcorder_toggle", "Camcorder: toggle instead of hold", "Press once to raise and again to lower, instead of holding.")
	_add_toggle(&"crouch_toggle", "Crouch: toggle instead of hold")


func _tab_audio() -> void:
	_add_slider(&"vol_master", "Master", 0.0, 1.0, 0.05, "pct")
	_add_slider(&"vol_world", "World", 0.0, 1.0, 0.05, "pct", "Doors, footsteps, the building itself.")
	_add_slider(&"vol_hum", "The Hum", 0.0, 1.0, 0.05, "pct", "The fluorescent drone under everything.")
	_add_slider(&"vol_pa", "Management (PA)", 0.0, 1.0, 0.05, "pct")
	_add_slider(&"vol_tape", "Tape", 0.0, 1.0, 0.05, "pct", "Camcorder sounds and recorded footage.")
	_add_slider(&"vol_muzak", "Muzak", 0.0, 1.0, 0.05, "pct", "The elevator.")
	_add_slider(&"vol_dread", "Dread", 0.0, 1.0, 0.05, "pct", "Drones, heartbeat and stingers.")


func _tab_access() -> void:
	_add_toggle(&"subtitles", "Subtitles", "Management's announcements, as text.")
	_add_toggle(&"sound_subtitles", "Sound subtitles", "Gameplay sounds in brackets, for example [Scrape - left].")
	_add_toggle(&"sound_radar", "Sound radar", "Shows the direction of warning sounds.")
	_add_cycler(&"tell_time_mult", "Tell time", TELL_PRESETS, TELL_NAMES, "How long a warning lasts before something can hurt you. Never shorter than 4 seconds.")
	_add_cycler(&"nerve_hits", "Nerve", NERVE_PRESETS, NERVE_NAMES, "Hits you can take before a Blackout. Applies from your next run.")
	_add_toggle(&"guided_rules", "Guided rules", "After Inspection, the card gently marks the lie. Never before.")
	_add_toggle(&"housekeeping_enabled", "Housekeeping", "The floor timer. Turn it off to explore without being tidied away.")
	_add_cycler(&"evidence_density", "Evidence density", DENSITY_PRESETS, DENSITY_NAMES, "Extra evidence on each floor. The minimum is always enough to deduce the rule.")


func _tab_controls() -> void:
	_rows.add_child(ScreenWidgets.wrap("Rebinding is not available yet. Current bindings:", 16, UIKit.INK_DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(grid)
	for head in ["Action", "Keyboard and mouse", "Gamepad"]:
		grid.add_child(UIKit.label(head, 14, UIKit.INK_DIM, true))
	for row in CONTROL_ROWS:
		var action: StringName = row[1]
		var name_l := UIKit.label(String(row[0]), 18)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_l)
		grid.add_child(UIKit.label(_keys_text(action), 18, UIKit.ACCENT, true))
		grid.add_child(UIKit.label(_pad_text(action), 18, UIKit.INK))
	_rows.add_child(ScreenWidgets.spacer(6))
	_rows.add_child(ScreenWidgets.wrap("Hold Interact on a door to peek; hold it while something tries the handle to brace. Hold %s to set the camcorder down." % UIKit.key_label(&"stakeout"), 14, UIKit.INK_DIM))


func _keys_text(action: StringName) -> String:
	if action == &"move_forward":
		return "%s %s %s %s" % [UIKit.key_label(&"move_forward"), UIKit.key_label(&"move_left"), UIKit.key_label(&"move_back"), UIKit.key_label(&"move_right")]
	return UIKit.key_label(action)


func _pad_text(action: StringName) -> String:
	if action == &"move_forward":
		return "Left stick"
	if not InputMap.has_action(action):
		return "-"
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			return _pad_button_name((e as InputEventJoypadButton).button_index)
		if e is InputEventJoypadMotion:
			var m := e as InputEventJoypadMotion
			match m.axis:
				JOY_AXIS_TRIGGER_LEFT: return "LT"
				JOY_AXIS_TRIGGER_RIGHT: return "RT"
				_: return "Stick"
	return "-"


func _pad_button_name(b: int) -> String:
	match b:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_BACK: return "Select"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return "D-pad up"
		JOY_BUTTON_DPAD_DOWN: return "D-pad down (hold)"
		JOY_BUTTON_DPAD_LEFT: return "D-pad left"
		JOY_BUTTON_DPAD_RIGHT: return "D-pad right"
		_: return "Button %d" % b


# --- row builders -----------------------------------------------------------------------------

func _row(label: String, ctrl: Control, hint: String = "") -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := ScreenWidgets.wrap(label, 18)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	ctrl.custom_minimum_size.x = maxf(ctrl.custom_minimum_size.x, CONTROL_W)
	if ctrl is Button:
		ctrl.add_theme_stylebox_override("normal", _button_box())
	h.add_child(ctrl)
	outer.add_child(h)
	if hint != "":
		var hl := ScreenWidgets.wrap(hint, 13, UIKit.INK_DIM)
		outer.add_child(hl)
	outer.add_child(ScreenWidgets.spacer(4))
	_rows.add_child(outer)


static func _button_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.105, 0.055, 0.8)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.3, 0.27, 0.14)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _on_off(v: bool) -> String:
	return "On" if v else "Off"


func _add_toggle(key: StringName, label: String, hint: String = "") -> void:
	var b := UIKit.button(_on_off(bool(Settings.get(key))), func() -> void: pass)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(func() -> void:
		var nv := not bool(Settings.get(key))
		Settings.set_value(key, nv)
		b.text = _on_off(nv)
		click())
	_row(label, b, hint)


func _add_cycler(key: StringName, label: String, values: Array, names: Array, hint: String = "") -> void:
	var vals := values.duplicate()
	var nms := names.duplicate()
	var cur: Variant = Settings.get(key)
	var idx := -1
	for i in vals.size():
		if is_equal_approx(float(vals[i]), float(cur)):
			idx = i
	if idx < 0:
		# a value set from the config file that is not one of the presets: keep it as an extra choice
		vals.append(cur)
		nms.append(str(cur))
		idx = vals.size() - 1
	var state := {"i": idx}
	var b := UIKit.button("", func() -> void: pass)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.text = "<  %s  >" % String(nms[idx])
	var step := func(d: int) -> void:
		state["i"] = posmod(int(state["i"]) + d, vals.size())
		var i2: int = state["i"]
		Settings.set_value(key, vals[i2])
		b.text = "<  %s  >" % String(nms[i2])
		click()
	b.pressed.connect(func() -> void: step.call(1))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed(&"ui_left"):
			step.call(-1)
			b.accept_event()
		elif e.is_action_pressed(&"ui_right"):
			step.call(1)
			b.accept_event())
	_row(label, b, hint)


func _add_slider(key: StringName, label: String, lo: float, hi: float, step: float, kind: String, hint: String = "", unit: float = 1.0) -> void:
	var s := HSlider.new()
	s.theme = _get_slider_theme()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.set_value_no_signal(float(Settings.get(key)) / unit)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(190, 26)
	s.focus_mode = Control.FOCUS_ALL
	s.scrollable = false          # the wheel scrolls the list, it must not change a volume by accident
	var val := UIKit.label(_fmt(kind, s.value), 17, UIKit.ACCENT, true)
	val.custom_minimum_size = Vector2(80, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, v * unit)
		val.text = _fmt(kind, v)
		if not _dragging:
			_tick())
	s.drag_started.connect(func() -> void: _dragging = true)
	s.drag_ended.connect(func(_changed: bool) -> void:
		_dragging = false
		click())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.custom_minimum_size.x = CONTROL_W
	h.add_child(s)
	h.add_child(val)
	_row(label, h, hint)


func _fmt(kind: String, v: float) -> String:
	match kind:
		"pct": return "%d%%" % roundi(v * 100.0)
		"deg": return "%d deg" % roundi(v)
		"x": return "%.2fx" % v
		_: return "%.2f" % v


func _tick() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_tick_ms > 110:
		_last_tick_ms = now
		AudioDirector.play(&"ui_click", -8.0)


static func _get_slider_theme() -> Theme:
	if _slider_theme != null:
		return _slider_theme
	var t := Theme.new()
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.2, 0.18, 0.1, 1.0)
	track.set_border_width_all(1)
	track.border_color = UIKit.PANEL_EDGE
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.55, 0.47, 0.18, 1.0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hi := StyleBoxFlat.new()
	fill_hi.bg_color = UIKit.ACCENT
	fill_hi.content_margin_top = 3
	fill_hi.content_margin_bottom = 3
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(1)
	focus.border_color = UIKit.ACCENT
	focus.set_expand_margin_all(3)
	t.set_stylebox("focus", "HSlider", focus)
	t.set_icon("grabber", "HSlider", _knob(UIKit.INK))
	t.set_icon("grabber_highlight", "HSlider", _knob(UIKit.ACCENT))
	t.set_icon("grabber_disabled", "HSlider", _knob(UIKit.INK_DIM))
	_slider_theme = t
	return t


static func _knob(c: Color) -> Texture2D:
	var img := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


# --- navigation -------------------------------------------------------------------------------

func _back() -> void:
	click()
	Settings.save_settings()
	close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()
		return
	var d := ScreenWidgets.tab_delta(event)
	if d != 0:
		get_viewport().set_input_as_handled()
		var n := clampi(_tab + d, 0, TABS.size() - 1)
		if n != _tab:
			_select_tab(n)
			(_bar.get_child(n) as Control).grab_focus()
		return
	var owner_ctl := get_viewport().gui_get_focus_owner()
	if (owner_ctl == null or owner_ctl.get_parent() == _bar) and ScreenWidgets.scroll_by_input(_scroll, event):
		get_viewport().set_input_as_handled()
