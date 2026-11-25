class_name CardScreen
extends ScreenBase
## The House Rules card (SPEC 4.1): printed identically every run; Management reads it aloud at the elevator.
## Mode `issue` (arrival: PA reads the lines, the world is dark) or `review` (the Q key mid-floor).

var session: FloorSession = null
var mode: StringName = &"issue"


func setup(p_args: Dictionary = {}) -> void:
	super.setup(p_args)
	session = args.get("session") as FloorSession
	mode = StringName(args.get("mode", &"issue"))
	dim_world = 0.82 if mode == &"issue" else 0.6


func _build() -> void:
	if session == null:
		return
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var paper := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIKit.PAPER
	sb.border_color = Color(0.35, 0.3, 0.16)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(34)
	paper.add_theme_stylebox_override("panel", sb)
	paper.custom_minimum_size = Vector2(700, 0)
	cc.add_child(paper)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	paper.add_child(v)
	v.add_child(_ink("THE HALCYON", 15, true, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_ink("HOUSE RULES", 38, true, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_ink(session.def.title, 20, false, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_ink("Guest no. %d" % RunState.guest_number, 14, false, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(HSeparator.new())
	for r in session.def.rules:
		var l := _ink("%d.  %s" % [r.number, r.text], 22, false)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(620, 0)
		v.add_child(l)
	v.add_child(HSeparator.new())
	v.add_child(_ink("Management is not responsible for loss, injury, or interpretation.", 13, false, HORIZONTAL_ALIGNMENT_CENTER))
	var b := UIKit.button("Continue  [%s]" % UIKit.key_label(&"interact") if mode == &"issue" else "Close  [%s]" % UIKit.key_label(&"card"), func(): _done())
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(b)
	if mode == &"issue":
		AudioDirector.play(&"card_flip")
		for line in session.rule_pa_lines():
			AudioDirector.say(line["id"], line["take"])


func _ink(text: String, size: int, bold: bool, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UIKit.label(text, size, UIKit.PAPER_INK, bold)
	l.horizontal_alignment = align as HorizontalAlignment
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return l


func _done() -> void:
	AudioDirector.play(&"card_flip", -4.0)
	close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"card") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_done()
