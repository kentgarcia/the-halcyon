class_name IntroScreen
extends ScreenBase
## First launch: a 20-second sequence of text cards (the Halcyon, the card, the camcorder, the welcome).
## Skippable at any time. Closes with no result.

const FADE_IN := 0.8
const HOLD := 3.6
const FADE_OUT := 0.8
const LAST_HOLD := 3.2

var _beats: Array[Dictionary] = []
var _beat := -1
var _t := 0.0
var _head: Label
var _body: Label
var _count: Label
var _content: Control


func setup(p_args: Dictionary = {}) -> void:
	super.setup(p_args)
	dim_world = 1.0
	pauses_world = true
	_beats = [
		{"head": "THE HALCYON", "body": "A hotel with no name on the door. It has always been a hotel. You have a reservation, though you do not remember making one."},
		{"head": "THE CARD", "body": "On every floor you are handed a card of House Rules, and Management reads it aloud. Management is polite. Management may be mistaken. What the building shows you is never mistaken."},
		{"head": "THE CAMCORDER", "body": "You carry a camcorder. Hold [%s] to raise it. Press [%s] to watch the last forty-five seconds again. Footage does not lie. Neither does the floor. Only the voice." % [UIKit.key_label(&"camcorder"), UIKit.key_label(&"playback")]},
		{"head": "", "body": "Welcome to The Halcyon. Please review the House Rules.", "last": true},
	]


func _build() -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(620, 0)
	v.add_theme_constant_override("separation", 18)
	cc.add_child(v)
	_content = v
	_head = UIKit.label("", 16, UIKit.ACCENT, true)
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_head)
	_body = ScreenWidgets.wrap("", 26, UIKit.INK)
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_body)

	# bottom bar: progress + skip
	var bar := HBoxContainer.new()
	ScreenWidgets.anchor_rect(bar, 0.04, 0.9, 0.96, 0.97)
	add_child(bar)
	_count = UIKit.label("", 14, UIKit.INK_DIM)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_count)
	bar.add_child(UIKit.button("Skip  [Esc]", func() -> void: _skip_all()))
	gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_next_beat())
	_next_beat()


func _next_beat() -> void:
	_beat += 1
	if _beat >= _beats.size():
		close()
		return
	_t = 0.0
	var b := _beats[_beat]
	_head.text = String(b["head"])
	_head.visible = String(b["head"]) != ""
	_body.text = String(b["body"])
	var last := bool(b.get("last", false))
	_body.add_theme_font_size_override("font_size", 34 if last else 26)
	_body.add_theme_color_override("font_color", UIKit.ACCENT if last else UIKit.INK)
	_count.text = "%d / %d" % [_beat + 1, _beats.size()]
	_content.modulate.a = 0.0
	match _beat:
		1: AudioDirector.play(&"card_flip", -8.0)
		2: AudioDirector.play(&"cam_rec_beep", -8.0)
		3: AudioDirector.say(&"welcome_first")


func _skip_all() -> void:
	click()
	close()


func _process(delta: float) -> void:
	if _beat < 0 or _beat >= _beats.size():
		return
	_t += delta
	var last := bool(_beats[_beat].get("last", false))
	var fade_in := FADE_IN * (1.5 if last else 1.0)
	var hold := LAST_HOLD if last else HOLD
	var a := 1.0
	if _t < fade_in:
		a = _t / fade_in
	elif _t > fade_in + hold:
		a = 1.0 - (_t - fade_in - hold) / FADE_OUT
	if Settings.reduce_motion:
		a = 1.0 if (_t >= 0.15 and _t <= fade_in + hold) else 0.0
	_content.modulate.a = clampf(a, 0.0, 1.0)
	if _t >= fade_in + hold + FADE_OUT:
		_next_beat()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_skip_all()
	elif event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		_next_beat()
