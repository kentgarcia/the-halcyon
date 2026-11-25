class_name NotebookScreen
extends ScreenBase
## The Notebook (SPEC 3.2): the player's deduction tool. Tabs: this floor's rules with Trust / Lie / ? marks,
## the evidence stickers found so far, Freeze Frames, past attempts on this floor, and the kept Clause.
## Fairness: it never says which rule is the entity rule or whether any rule is true, and it only lists
## evidence that was found AND is true for this run (SPEC 4.2). Tab / Esc / E close it.

const TABS: Array[String] = ["This floor", "Evidence", "Frames", "Past attempts", "Kept rule"]
const KIND_NAMES := {
	EvidenceDef.Kind.GRAFFITI: "GRAFFITI", EvidenceDef.Kind.PROP_STATE: "THE ROOM", EvidenceDef.Kind.AUDIO_CUE: "SOUND",
	EvidenceDef.Kind.DOOR_STATE: "DOOR", EvidenceDef.Kind.TAPE_CLIP: "TAPE", EvidenceDef.Kind.CAM_ONLY: "THROUGH THE LENS",
	EvidenceDef.Kind.TEST: "EXPERIMENT",
}
const THUMB := Vector2(208, 160)

var session: FloorSession = null
var _def: FloorDef = null
var _tab := -1
var _initial_tab := 0
var _bar: HFlowContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _stats: Label
var _viewer: Control = null
var _viewer_from: Control = null
var _mark_buttons: Dictionary = {}     ## rule_id -> Button


func setup(p_args: Dictionary = {}) -> void:
	super.setup(p_args)
	session = args.get("session") as FloorSession
	_def = session.def if session != null else null
	_initial_tab = int(args.get("tab", 0))
	dim_world = 0.85


func _build() -> void:
	var v := ScreenWidgets.frame(self, 1000.0)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var title := UIKit.label("NOTEBOOK", 28, UIKit.ACCENT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UIKit.button("Close  [%s]" % UIKit.key_label(&"notebook"), func() -> void: _close_notebook()))
	_stats = UIKit.label("", 15, UIKit.INK_DIM)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_stats)
	_refresh_stats()
	_bar = ScreenWidgets.tab_bar(PackedStringArray(TABS), _select_tab, _enter_tab)
	v.add_child(_bar)
	v.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	v.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	_scroll.add_child(_content)
	_select_tab(clampi(_initial_tab, 0, TABS.size() - 1))
	AudioDirector.play(&"notebook_page")


func _refresh_stats() -> void:
	var pocket := Items.display_name(RunState.pocket) if RunState.pocket != &"" else "empty"
	var nerve := "#".repeat(clampi(RunState.nerve, 0, 8)) + "-".repeat(clampi(RunState.nerve_max - RunState.nerve, 0, 8))
	_stats.text = "Guest no. %d    Nerve [%s]    Battery %d%%    Pocket: %s" % [
		RunState.guest_number, nerve, roundi(RunState.battery), pocket]


# --- tabs -------------------------------------------------------------------------------------

func _select_tab(i: int) -> void:
	if i == _tab:
		return
	_tab = i
	ScreenWidgets.tab_mark(_bar, i)
	ScreenWidgets.clear_children(_content)
	_mark_buttons.clear()
	_scroll.scroll_vertical = 0
	match i:
		0: _tab_floor()
		1: _tab_evidence()
		2: _tab_frames()
		3: _tab_attempts()
		4: _tab_clause()
	_relayout.call_deferred()


## Wrapped labels learn their final height one layout pass late; nudge the containers so panels fit the text.
func _relayout() -> void:
	if _content == null or not is_inside_tree():
		return
	for c in _content.get_children():
		if c is Container:
			(c as Container).queue_sort()
		(c as Control).update_minimum_size()
	_content.queue_sort()


func _focus_first() -> void:
	if _bar != null and _tab >= 0 and _tab < _bar.get_child_count():
		(_bar.get_child(_tab) as Control).grab_focus()
	else:
		super._focus_first()


func _enter_tab(_i: int) -> void:
	var b := _find_button(_content)
	if b != null:
		b.grab_focus()


func _empty_note(text: String) -> void:
	_content.add_child(ScreenWidgets.wrap(text, 17, UIKit.INK_DIM))


# (a) this floor ----------------------------------------------------------------------------

func _tab_floor() -> void:
	if _def == null:
		_empty_note("There is no floor to write about.")
		return
	_content.add_child(UIKit.label(_def.title, 24, UIKit.ACCENT, true))
	var attempt := RunState.floor_attempt + 1
	_content.add_child(UIKit.label("Attempt %d.   Printed card, as read to you:" % attempt, 15, UIKit.INK_DIM))
	for r in _def.rules:
		_content.add_child(_rule_row(r))
	_content.add_child(ScreenWidgets.spacer(2))
	_content.add_child(ScreenWidgets.wrap("Mark each rule: ? (undecided), Trust or Lie. Management will not tell you whether you are right until Inspection or an Autopsy.", 14, UIKit.INK_DIM))


func _rule_row(r: RuleDef) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var num := UIKit.label("%d." % r.number, 20, UIKit.ACCENT, true)
	num.custom_minimum_size = Vector2(34, 0)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(num)
	var txt := ScreenWidgets.wrap(r.text, 20, UIKit.INK)
	txt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(txt)
	var rid := r.id
	var b := UIKit.button(_mark_text(RunState.mark_of(rid)), func() -> void: pass)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(150, 0)
	b.pressed.connect(func() -> void: _cycle_mark(rid, b))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed(&"ui_left"):
			_cycle_mark(rid, b, -1)
			b.accept_event()
		elif e.is_action_pressed(&"ui_right"):
			_cycle_mark(rid, b, 1)
			b.accept_event())
	_style_mark(b, RunState.mark_of(rid))
	_mark_buttons[rid] = b
	row.add_child(b)
	return row


static func _mark_text(m: int) -> String:
	match m:
		RunState.Mark.TRUST: return "[ TRUST ]"
		RunState.Mark.LIE: return "[ LIE ]"
		_: return "[ ? ]"


func _style_mark(b: Button, m: int) -> void:
	# Never colour-code truth/lie (SPEC 11.3): the word carries the meaning; brightness only says "decided".
	b.add_theme_color_override("font_color", UIKit.INK_DIM if m == RunState.Mark.UNKNOWN else UIKit.INK)


func _cycle_mark(rule_id: StringName, b: Button, dir: int = 1) -> void:
	var cur := RunState.mark_of(rule_id)
	var nxt := posmod(cur + dir, 3)      # UNKNOWN -> TRUST -> LIE -> UNKNOWN
	RunState.mark_rule(rule_id, nxt)
	b.text = _mark_text(nxt)
	_style_mark(b, nxt)
	AudioDirector.play(&"pen_scratch", -4.0)


# (b) evidence ------------------------------------------------------------------------------

func found_evidence() -> Array[EvidenceDef]:
	## Only what was found AND is true for the current run. The def list holds both variants; the
	## `variant == truth` check also guards against a sticker left over from a different roll of this floor.
	var out: Array[EvidenceDef] = []
	if _def == null:
		return out
	var truth := session.truth if session != null else RunState.Truth.HOLDS
	for e in _def.evidence:
		if RunState.evidence_found.has(e.id) and e.variant == truth:
			out.append(e)
	return out


func _tab_evidence() -> void:
	var found := found_evidence()
	var n := found.size()
	_content.add_child(UIKit.label("%d piece%s found" % [n, "" if n == 1 else "s"], 22, UIKit.ACCENT, true))
	if n == 0:
		_empty_note("Nothing yet. Read the walls, look under the lights, and use the camcorder: some things only show through the lens.")
		return
	for e in found:
		_content.add_child(_sticker(e))
	_content.add_child(ScreenWidgets.wrap("What you find here is real. What you are told is only advice.", 14, UIKit.INK_DIM))


func _sticker(e: EvidenceDef) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ScreenWidgets.paper_box(12))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	p.add_child(vb)
	var kind := UIKit.label(String(KIND_NAMES.get(e.kind, "NOTE")), 13, Color(0.42, 0.34, 0.14), true)
	kind.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	vb.add_child(kind)
	var note := e.note if e.note != "" else e.text
	var l := ScreenWidgets.wrap(note, 19, UIKit.PAPER_INK)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	vb.add_child(l)
	return p


# (c) frames --------------------------------------------------------------------------------

func _tab_frames() -> void:
	var frames: Array[Dictionary] = []
	if session != null:
		frames = session.freeze_frames
	_content.add_child(UIKit.label("Freeze Frames: %d taken, %d left on this floor" % [frames.size(), RunState.freeze_frames_left], 20, UIKit.ACCENT, true))
	if frames.is_empty():
		_empty_note("None yet. Raise the camcorder, then take a Freeze Frame (%s) to keep a still of something you want to remember." % UIKit.key_label(&"freeze_frame"))
		return
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(flow)
	var n := 0
	for fr in frames:
		var img: Image = fr.get("image") as Image
		if img == null or img.is_empty():
			continue
		n += 1
		var tex := ImageTexture.create_from_image(img)
		var caption := _frame_caption(fr, n)
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		var b := UIKit.button("", func() -> void: pass)
		b.icon = tex
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = THUMB
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.add_theme_stylebox_override("normal", _thumb_box())
		b.tooltip_text = caption
		b.pressed.connect(func() -> void: _open_viewer(tex, caption, b))
		cell.add_child(b)
		var cl := UIKit.label(caption, 13, UIKit.INK_DIM)
		cl.custom_minimum_size = Vector2(THUMB.x, 0)
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cell.add_child(cl)
		flow.add_child(cell)


func _thumb_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.set_border_width_all(1)
	sb.border_color = UIKit.PANEL_EDGE
	sb.set_content_margin_all(8)
	return sb


func _frame_caption(fr: Dictionary, n: int) -> String:
	var room := String(fr.get("room", ""))
	var s := "#%d  at %s" % [n, ScreenWidgets.clock(float(fr.get("t", 0.0)))]
	if room != "":
		s += "  -  " + room
	if bool(fr.get("from_playback", false)):
		s += "  (from tape)"
	return s


func _open_viewer(tex: Texture2D, caption: String, from: Control) -> void:
	_close_viewer()
	click()
	_viewer_from = from
	_viewer = Control.new()
	_viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_viewer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewer.add_child(dim)
	var box := VBoxContainer.new()
	ScreenWidgets.anchor_rect(box, 0.1, 0.06, 0.9, 0.94)
	box.add_theme_constant_override("separation", 8)
	_viewer.add_child(box)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tr.custom_minimum_size = Vector2(256, 192)
	box.add_child(tr)
	var cap := UIKit.label(caption, 18, UIKit.INK)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)
	var cb := UIKit.button("Close", func() -> void: _close_viewer())
	cb.alignment = HORIZONTAL_ALIGNMENT_CENTER
	cb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cb.custom_minimum_size = Vector2(260, 0)
	box.add_child(cb)
	cb.grab_focus()


## Opens the first Freeze Frame in the enlarged viewer (dev harness and tests). False if there is none.
func open_first_frame() -> bool:
	_select_tab(2)
	for cell in _content.find_children("*", "Button", true, false):
		var b := cell as Button
		if b != null and b.icon != null:
			b.pressed.emit()
			return true
	return false


func _close_viewer() -> void:
	if _viewer == null:
		return
	_viewer.queue_free()
	_viewer = null
	if _viewer_from != null and is_instance_valid(_viewer_from):
		_viewer_from.grab_focus.call_deferred()
	_viewer_from = null


# (d) past attempts -------------------------------------------------------------------------

func _tab_attempts() -> void:
	if _def == null:
		_empty_note("Nothing on record.")
		return
	var attempts: Array = SaveService.page(_def.id).get("attempts", [])
	_content.add_child(UIKit.label("%s: %d on record" % [_def.short_name, attempts.size()], 22, UIKit.ACCENT, true))
	if attempts.is_empty():
		_empty_note("No earlier attempts on this floor. The building will remember this one.")
		return
	_content.add_child(ScreenWidgets.wrap("Newest first. The rule is re-rolled every attempt: what held last time may lie now.", 14, UIKit.INK_DIM))
	var total := attempts.size()
	for i in total:
		var a: Dictionary = attempts[total - 1 - i]
		_content.add_child(_attempt_row(total - i, a))


func _attempt_row(number: int, a: Dictionary) -> Control:
	var p := PanelContainer.new()
	var sb := UIKit.shadow_box(Color(0.1, 0.09, 0.05, 0.7))
	sb.set_border_width_all(1)
	sb.border_color = Color(0.3, 0.27, 0.14)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)
	var result := String(a.get("result", ""))
	var head := "#%d   %s   %s" % [number, "Cleared" if result == "cleared" else "Blackout", ScreenWidgets.clock(float(a.get("t", 0.0)))]
	vb.add_child(UIKit.label(head, 18, UIKit.INK, true))
	var parts: Array[String] = []
	var rule_text := String(a.get("rule", ""))
	if rule_text != "":
		parts.append("The rule: \"%s\"" % rule_text)
	if a.has("truth"):
		var held := int(a["truth"]) == RunState.Truth.HOLDS
		parts.append("%s %s." % ["That rule" if rule_text != "" else "The entity rule", "held" if held else "lied"])
	var cause := String(a.get("cause", ""))
	if cause != "":
		parts.append("Ended by: %s." % _cause_name(cause))
	if a.has("marks_ok"):
		parts.append("Your mark on the entity rule was %s." % ("right" if bool(a["marks_ok"]) else "wrong"))
	if not parts.is_empty():
		vb.add_child(ScreenWidgets.wrap("  ".join(PackedStringArray(parts)), 15, UIKit.INK_DIM))
	return p


func _cause_name(cause: String) -> String:
	match cause:
		"housekeeping": return "Housekeeping"
		"verdict": return "a wrong Verdict"
		_: return EntityNotes.name_of(StringName(cause)) if EntityNotes.NAMES.has(StringName(cause)) else cause


# (e) kept rule -----------------------------------------------------------------------------

func _tab_clause() -> void:
	var cd: ClauseDef = FloorCatalog.clause_def(RunState.clause) if RunState.clause != &"" else null
	_content.add_child(UIKit.label("The rule you kept", 22, UIKit.ACCENT, true))
	if cd == null:
		_empty_note("You have not kept a rule. At Inspection you may tear one true rule off the card; it then binds the house and you on every later floor.")
		return
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ScreenWidgets.paper_box(14))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)
	var printed := ScreenWidgets.wrap("\"%s\"" % cd.printed, 22, UIKit.PAPER_INK, true)
	printed.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	vb.add_child(printed)
	_content.add_child(p)
	_content.add_child(_side("THE HOUSE MUST", cd.house_side))
	_content.add_child(_side("YOU MUST", cd.guest_side))
	var status := "VOID for the rest of this floor. You broke your side; Management noted it, politely." if RunState.clause_void \
		else "In force. Break your side and it is void for the rest of the floor."
	_content.add_child(UIKit.label("Status: " + ("VOID" if RunState.clause_void else "IN FORCE"), 18, UIKit.INK, true))
	_content.add_child(ScreenWidgets.wrap(status, 15, UIKit.INK_DIM))


func _side(head: String, body: String) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.add_child(UIKit.label(head, 13, UIKit.INK_DIM, true))
	vb.add_child(ScreenWidgets.wrap(body, 18, UIKit.INK))
	return vb


# --- input ------------------------------------------------------------------------------------

func _close_notebook() -> void:
	if _viewer != null:
		_close_viewer()
		return
	AudioDirector.play(&"notebook_page", -6.0)
	close()


func _input(event: InputEvent) -> void:
	super._input(event)
	# Tab is "focus next" to the GUI, which would eat it before _unhandled_input: catch it here.
	if event.is_action_pressed(&"notebook") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_close_notebook()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"interact"):
		if event.is_action_pressed(&"interact") and event is InputEventJoypadButton and _viewer == null:
			# gamepad A is both "interact" and "accept": let it press the focused button instead of closing
			return
		get_viewport().set_input_as_handled()
		_close_notebook()
		return
	if _viewer != null:
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
