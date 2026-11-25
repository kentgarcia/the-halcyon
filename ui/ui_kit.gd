class_name UIKit
extends RefCounted
## Shared look for every screen: tape-era monospace on dark panels. Built in code (no editor), so a
## single place to retheme. Text is native resolution and crisp over the low-res world.

const INK := Color(0.91, 0.88, 0.72)
const INK_DIM := Color(0.62, 0.60, 0.48)
const INK_WARN := Color(0.95, 0.55, 0.38)
const INK_GOOD := Color(0.62, 0.86, 0.55)
const PAPER := Color(0.86, 0.82, 0.66)
const PAPER_INK := Color(0.16, 0.13, 0.08)
const PANEL := Color(0.05, 0.045, 0.03, 0.92)
const PANEL_EDGE := Color(0.45, 0.40, 0.22, 1.0)
const ACCENT := Color(0.95, 0.80, 0.30)
const REC_RED := Color(0.92, 0.2, 0.18)

static var _font_bold: Font = null
static var _font_reg: Font = null
static var _theme: Theme = null


static func font_bold() -> Font:
	if _font_bold == null:
		_font_bold = load("res://fonts/LiberationMono-Bold.ttf")
	return _font_bold


static func font_regular() -> Font:
	if _font_reg == null:
		_font_reg = load("res://fonts/LiberationMono-Regular.ttf")
	return _font_reg


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font_regular()
	t.default_font_size = 18
	t.set_color("font_color", "Label", INK)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.7))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_font("font", "Button", font_bold())
	t.set_font_size("font_size", "Button", 20)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", INK_DIM)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.09, 0.05, 0.0) if state == "normal" else Color(0.18, 0.16, 0.08, 0.85)
		sb.set_border_width_all(0)
		if state == "focus":
			sb.set_border_width_all(1)
			sb.border_color = ACCENT
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		t.set_stylebox(state, "Button", sb)
	var pn := StyleBoxFlat.new()
	pn.bg_color = PANEL
	pn.border_color = PANEL_EDGE
	pn.set_border_width_all(1)
	pn.set_content_margin_all(14)
	t.set_stylebox("panel", "PanelContainer", pn)
	t.set_stylebox("panel", "Panel", pn)
	_theme = t
	return t


static func label(text: String, size: int = 18, color: Color = INK, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_bold())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func key_label(action: StringName) -> String:
	## "E", "Right Mouse", "A" ... whichever input is bound first.
	if not InputMap.has_action(action):
		return String(action)
	var ev := InputMap.action_get_events(action)
	var pad_text := ""
	for e in ev:
		if e is InputEventKey:
			var k := e as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			return OS.get_keycode_string(code)
		if e is InputEventMouseButton:
			match (e as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				_: return "Mouse"
		if e is InputEventJoypadButton and pad_text == "":
			pad_text = "Pad %d" % (e as InputEventJoypadButton).button_index
	return pad_text if pad_text != "" else String(action)


static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = theme()
	p.custom_minimum_size = min_size
	return p


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = theme()
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	return b


static func shadow_box(color: Color = Color(0, 0, 0, 0.6)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_content_margin_all(8)
	return sb
