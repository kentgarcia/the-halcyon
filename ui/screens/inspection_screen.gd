class_name InspectionScreen
extends ScreenBase
## Inspection (SPEC 3.4): in the elevator the card for the cleared floor is re-printed with each rule's true
## status, your notebook marks are scored silently, a correct Verdict pays a Courtesy, and you may tear one
## true rule off the card and keep it as a Clause (SPEC 4.10). Result: {courtesy: id, clause: id}.

var report: Dictionary = {}
var choice := {"courtesy": &"", "clause": &""}
var _box: VBoxContainer


func setup(p_args: Dictionary = {}) -> void:
	super.setup(p_args)
	report = args.get("report", {})
	dim_world = 0.9


func _build() -> void:
	_box = center_panel(780)
	_step_card()


func _clear() -> void:
	for c in _box.get_children():
		c.queue_free()


func _step_card() -> void:
	_clear()
	var def: FloorDef = report["def"]
	_box.add_child(UIKit.label("INSPECTION", 14, UIKit.INK_DIM, true))
	_box.add_child(UIKit.label(def.title, 28, UIKit.ACCENT, true))
	_box.add_child(HSeparator.new())
	for row in report["rows"]:
		var r: RuleDef = row["rule"]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		var txt := UIKit.label("%d.  %s" % [r.number, r.text], 18, UIKit.INK)
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt.custom_minimum_size = Vector2(430, 0)
		line.add_child(txt)
		var stamp := UIKit.label("TRUE" if row["true"] else "LIE", 18, UIKit.INK_GOOD if row["true"] else UIKit.INK_WARN, true)
		stamp.custom_minimum_size = Vector2(60, 0)
		line.add_child(stamp)
		var mark_txt := ""
		var mark_col := UIKit.INK_DIM
		match row["status"]:
			&"correct":
				mark_txt = "You marked: %s. Correct." % ("Trust" if row["mark"] == RunState.Mark.TRUST else "Lie")
				mark_col = UIKit.INK_GOOD
			&"wrong":
				mark_txt = "You marked: %s. Incorrect." % ("Trust" if row["mark"] == RunState.Mark.TRUST else "Lie")
				mark_col = UIKit.INK_WARN
			_:
				mark_txt = "Unmarked."
		line.add_child(UIKit.label(mark_txt, 15, mark_col))
		_box.add_child(line)
	var note := EntityNotes.note(def.entity_id, int(report["truth"]))
	if note != "":
		var nl := UIKit.label(note, 16, UIKit.INK_DIM)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size = Vector2(720, 0)
		_box.add_child(nl)
	var vtxt := ""
	match int(report["verdict_ok"]):
		1: vtxt = "Your Suggestion Box card was right. Management is pleased."
		0: vtxt = "Your Suggestion Box card was wrong. Management has noted it."
	if vtxt != "":
		_box.add_child(UIKit.label(vtxt, 16, UIKit.INK))
	_box.add_child(UIKit.button("Continue", func(): click(); _step_courtesy()))
	AudioDirector.play(&"stamp_thud")
	_focus_first()


func _step_courtesy() -> void:
	var offers: Array = report["courtesies"]
	if offers.is_empty():
		_step_clause()
		return
	_clear()
	AudioDirector.say(&"courtesy_pick")
	_box.add_child(UIKit.label("COURTESY", 14, UIKit.INK_DIM, true))
	_box.add_child(UIKit.label("Please select a courtesy.", 24, UIKit.ACCENT, true))
	for o in offers:
		var oid: StringName = o["id"]
		_box.add_child(UIKit.button(String(o["label"]), func(): click(); choice["courtesy"] = oid; _step_clause()))
	_box.add_child(UIKit.button("No, thank you", func(): click(); _step_clause()))
	_focus_first()


func _step_clause() -> void:
	var opts: Array = report["clause_options"]
	if opts.is_empty():
		_finish()
		return
	_clear()
	AudioDirector.say(&"clause_keep")
	_box.add_child(UIKit.label("KEEP ONE RULE", 14, UIKit.INK_DIM, true))
	_box.add_child(UIKit.label("Tear one true rule off the card. It binds both sides on every later floor.", 18, UIKit.INK))
	var cur: StringName = report.get("current_clause", &"")
	if cur != &"":
		var cd := FloorCatalog.clause_def(cur)
		if cd != null:
			_box.add_child(UIKit.label("Currently kept: \"%s\"  (a new one replaces it)" % cd.printed, 15, UIKit.INK_DIM))
	for cd in opts:
		var c: ClauseDef = cd
		var b := UIKit.button("\"%s\"" % c.printed, func(): click(); choice["clause"] = c.id; _finish())
		_box.add_child(b)
		var sides := UIKit.label("   House: %s\n   You:   %s" % [c.house_side, c.guest_side], 14, UIKit.INK_DIM)
		sides.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sides.custom_minimum_size = Vector2(720, 0)
		_box.add_child(sides)
	_box.add_child(UIKit.button("Keep nothing", func(): click(); _finish()))
	_focus_first()


func _finish() -> void:
	close(choice)
