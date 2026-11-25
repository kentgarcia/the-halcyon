class_name SuggestionBoxScreen
extends ScreenBase
## The Suggestion Box (SPEC 4.9): one Verdict per floor, any time before the exam. Right = a Courtesy at the
## elevator. Wrong = -1 Nerve when the exam starts. Not filing costs nothing. The house never reacts to it.

var session: FloorSession = null


func setup(p_args: Dictionary = {}) -> void:
	super.setup(p_args)
	session = args.get("session") as FloorSession
	dim_world = 0.55


func _build() -> void:
	var rule := session.def.entity_rule() if session != null else null
	var v := center_panel(720)
	v.add_child(UIKit.label("SUGGESTION BOX", 30, UIKit.ACCENT, true))
	v.add_child(UIKit.label("Management values your feedback.", 16, UIKit.INK_DIM))
	v.add_child(HSeparator.new())
	if rule == null:
		v.add_child(UIKit.label("There is nothing to comment on here.", 18))
		v.add_child(UIKit.button("Close", func(): close()))
		return
	var q := UIKit.label("Rule %d: \"%s\"" % [rule.number, rule.text], 22, UIKit.INK, true)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size = Vector2(660, 0)
	v.add_child(q)
	if session.verdict_filed():
		var done := "TRUST" if RunState.verdict == RunState.Mark.TRUST else "LIE"
		v.add_child(UIKit.label("Your card is already filed: %s. It is final for this floor." % done, 18, UIKit.INK_DIM))
		v.add_child(UIKit.button("Close", func(): close()))
		return
	v.add_child(UIKit.label("Is this rule honest on this floor, today?", 18))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	row.add_child(UIKit.button("It is TRUE - trust it", func(): _file(RunState.Mark.TRUST)))
	row.add_child(UIKit.button("It is a LIE", func(): _file(RunState.Mark.LIE)))
	var note := UIKit.label("File once. Final for this floor.\nRight: a Courtesy at Inspection.  Wrong: you lose a Nerve segment when the exam starts.\nNot filing costs nothing.", 14, UIKit.INK_DIM)
	v.add_child(note)
	v.add_child(UIKit.button("Not yet", func(): close()))


func _file(mark: int) -> void:
	var rule := session.def.entity_rule()
	click()
	session.file_verdict(mark)
	if rule != null:
		RunState.mark_rule(rule.id, mark)
	EventBus.toast.emit("Comment card filed.")
	close(mark)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
