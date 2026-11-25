class_name ScreenWidgets
extends RefCounted
## Small builders shared by the larger screens (settings, notebook, ending, intro): a width-capped framed
## panel, wrapped labels, a keyboard/gamepad friendly tab bar. Everything is anchor/container based, so the
## same screen lays out at 1024x576, 1280x720 and 1920x1080.


static func anchor_rect(c: Control, l: float, t: float, r: float, b: float) -> void:
	## Anchors a control to a fraction of its parent with zero offsets (plain set_anchors_preset gives size 0).
	c.anchor_left = l
	c.anchor_top = t
	c.anchor_right = r
	c.anchor_bottom = b
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


## Anchors `node` to the host with a top/bottom margin (fraction of height) and side margins that keep it no
## wider than `max_width` (re-fitted whenever the host resizes).
static func column(host: Control, node: Control, max_width: float = 1100.0, margin_y: float = 0.07, min_margin_x: float = 0.04) -> void:
	var fit := func() -> void:
		var w := maxf(host.size.x, 1.0)
		var mx := clampf((w - max_width) * 0.5 / w, min_margin_x, 0.45)
		anchor_rect(node, mx, margin_y, 1.0 - mx, 1.0 - margin_y)
	fit.call()
	host.resized.connect(fit)


## A bordered panel filling the host except for margins; it never grows wider than `max_width`. Returns the
## VBox inside it.
static func frame(host: Control, max_width: float = 1100.0, margin_y: float = 0.07, min_margin_x: float = 0.04) -> VBoxContainer:
	var p := UIKit.panel()
	host.add_child(p)
	column(host, p, max_width, margin_y, min_margin_x)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	return v


static func wrap(text: String, size: int = 18, color: Color = UIKit.INK, bold: bool = false) -> Label:
	var l := UIKit.label(text, size, color, bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func spacer(h: float = 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func clear_children(n: Node) -> void:
	## Detaches immediately (so focus searches never see them) and frees at end of frame.
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


# --- tab bar ----------------------------------------------------------------------------------

static var _tab_on: StyleBoxFlat = null


static func _tab_style() -> StyleBoxFlat:
	if _tab_on == null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.18, 0.16, 0.08, 0.85)
		sb.border_color = UIKit.ACCENT
		sb.border_width_bottom = 3
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		_tab_on = sb
	return _tab_on


## Buttons in an HFlow. Focusing a tab (arrow keys) shows it; pressing it (Enter/click) shows it and calls
## `on_activate(i)` so the caller can move focus into the content.
static func tab_bar(labels: PackedStringArray, on_select: Callable, on_activate: Callable) -> HFlowContainer:
	var hb := HFlowContainer.new()
	hb.add_theme_constant_override("h_separation", 4)
	hb.add_theme_constant_override("v_separation", 4)
	for i in labels.size():
		var idx := i
		var b := UIKit.button(labels[i], func() -> void:
			on_select.call(idx)
			on_activate.call(idx))
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.focus_entered.connect(func() -> void: on_select.call(idx))
		hb.add_child(b)
	return hb


static func tab_mark(bar: Control, active: int) -> void:
	var i := 0
	for c in bar.get_children():
		var b := c as Button
		if b == null:
			continue
		if i == active:
			b.add_theme_stylebox_override("normal", _tab_style())
			b.add_theme_color_override("font_color", UIKit.ACCENT)
		else:
			b.remove_theme_stylebox_override("normal")
			b.remove_theme_color_override("font_color")
		i += 1


## -1 / +1 for "previous / next tab" input: gamepad shoulders, PageUp / PageDown. 0 otherwise.
static func tab_delta(event: InputEvent) -> int:
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_LEFT_SHOULDER: return -1
			JOY_BUTTON_RIGHT_SHOULDER: return 1
	if event.is_action_pressed(&"ui_page_up"):
		return -1
	if event.is_action_pressed(&"ui_page_down"):
		return 1
	return 0


## Scroll a ScrollContainer from the keyboard when nothing inside it can take focus. Returns true if handled.
static func scroll_by_input(scroll: ScrollContainer, event: InputEvent) -> bool:
	if scroll == null:
		return false
	var step := 90
	if event.is_action_pressed(&"ui_down"):
		scroll.scroll_vertical += step
		return true
	if event.is_action_pressed(&"ui_up"):
		scroll.scroll_vertical -= step
		return true
	return false


static func paper_box(margin: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIKit.PAPER
	sb.border_color = Color(0.35, 0.3, 0.16)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(margin)
	return sb


## "m:ss" for a number of seconds.
static func clock(seconds: float) -> String:
	var s := maxi(0, int(round(seconds)))
	return "%d:%02d" % [floori(s / 60.0), s % 60]
