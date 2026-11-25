class_name EndingScreen
extends ScreenBase
## The three epilogues, in Management's voice (dry, warm, never a threat). Text types out slowly and is
## skippable. args.ending is &"checkout" | &"desk" | &"burn". Result: {"action": &"new"} or {"action": &"menu"}.
##
## CHECKOUT  - you leave; the building keeps your number.
## DESK      - you become Management; the voice is yours.
## BURN      - the true exit; only valid when every entity rule was marked correctly at Inspection
##             (RunState.entity_mark_ok). Otherwise the card will not take the flame.

const CPS := 36.0                  ## typing speed, characters per second
const PARAGRAPH_PAUSE := 0.85
const OPENING_PAUSE := 1.2

const ENDINGS := {
	&"checkout": {
		"title": "CHECKOUT",
		"voice": &"audit_checkout",
		"tagline": "Checkout is at eleven. It was always at eleven.",
		"lines": [
			"The elevator opens on the front doors. They are held for you, as doors here always are.",
			"Outside it is morning. It is quiet and very bright, and you cannot remember what the light was like before.",
			"Behind you, someone at the desk draws a line under your name in the ledger. It is a neat line.",
			"Your room has been cleaned. Your number has been kept. Management keeps all of them.",
			"Thank you for staying at The Halcyon. We look forward to your return.",
		],
		"footer": "Guest no. %d has checked out.",
	},
	&"desk": {
		"title": "TAKE THE DESK",
		"voice": &"audit_desk",
		"tagline": "The desk is yours, if you want it.",
		"lines": [
			"The desk is warm, as if someone has only just stood up.",
			"There is a bell, a ledger and a microphone. Your name is already in the ledger, on the first line, in your handwriting.",
			"You press the button. The building listens. When you speak, the voice that fills the halls is warm and dry and a little kind, and it takes you a moment to recognise it.",
			"Somewhere below, an elevator chimes. A guest steps out and looks around for a card.",
			"You read them the rules. You are careful to say each one clearly. You are not required to say them truthfully.",
		],
		"footer": "Guest no. %d is now Management.",
	},
	&"burn": {
		"title": "BURN THE CARD",
		"voice": &"audit_burn",
		"tagline": "You have been a wonderful guest. That is unfortunate.",
		"lines": [
			"You know now which lines were lying. You always did, a little.",
			"The match is in the drawer under the desk. It lights the first time, which nothing in this building has ever done.",
			"The card burns without smoke. The rules darken in the order they were printed. The ash does not fall. It rises.",
			"Somewhere in the walls the hum stops mid-note. The lights hold still.",
			"Behind the desk there is a door that is not on any plan. It is plain. It is not locked.",
			"Outside it is night, with weather in it. Nobody says goodbye.",
		],
		"footer": "Guest no. %d is not on the register.",
	},
	&"burn_failed": {
		"title": "THE CARD WILL NOT BURN",
		"voice": &"audit_checkout",
		"tagline": "Checkout is at eleven. It was always at eleven.",
		"lines": [
			"You strike the match. The card does not catch.",
			"It is a very good card. It has been read to a great many guests, and it has learned what they do with it.",
			"There are lines on it you trusted that lied, or doubted that did not. The card knows which. It is patient about it.",
			"The match burns down to your fingers. Management notes that you tried.",
			"Thank you for staying at The Halcyon. We look forward to your return.",
		],
		"footer": "Guest no. %d has checked out.",
	},
}
const ENDING_ORDER: Array[StringName] = [&"checkout", &"desk", &"burn"]
const ENDING_NAMES := {&"checkout": "Checkout", &"desk": "Take the desk", &"burn": "Burn the card"}

var ending: StringName = &"checkout"
var _content_key: StringName = &"checkout"
var _labels: Array[Label] = []
var _i := 0
var _chars := 0.0
var _hold := OPENING_PAUSE
var _done := false
var _scroll: ScrollContainer
var _tail: VBoxContainer
var _buttons: Button = null


## True when the entity rule of every floor below the Lobby was marked correctly at its Inspection
## (the same test as LobbyAudit.burn_available(); the Lobby's own rule is decided at the desk, not here).
static func burn_is_valid() -> bool:
	for fid in FloorCatalog.ORDER:
		if fid != &"lobby" and not bool(RunState.entity_mark_ok.get(fid, false)):
			return false
	return true


func setup(p_args: Dictionary = {}) -> void:
	super.setup(p_args)
	ending = StringName(args.get("ending", &"checkout"))
	if not ENDING_ORDER.has(ending):
		ending = &"checkout"
	_content_key = ending
	if ending == &"burn" and not bool(args.get("burn_valid", burn_is_valid())):
		_content_key = &"burn_failed"
	dim_world = 1.0


func _build() -> void:
	var data: Dictionary = ENDINGS[_content_key]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	ScreenWidgets.column(self, v, 760.0, 0.07)

	var title := UIKit.label(String(data["title"]), 38, UIKit.ACCENT, true)
	v.add_child(title)
	v.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 14)
	_scroll.add_child(text)

	var tag := ScreenWidgets.wrap(String(data["tagline"]), 22, UIKit.INK_DIM, true)
	_add_typed(text, tag)
	for line in data["lines"]:
		_add_typed(text, ScreenWidgets.wrap(String(line), 20, UIKit.INK))
	var foot := ScreenWidgets.wrap(String(data["footer"]) % RunState.guest_number, 16, UIKit.ACCENT, true)
	_add_typed(text, foot)

	_tail = VBoxContainer.new()
	_tail.add_theme_constant_override("separation", 8)
	_tail.visible = false
	v.add_child(_tail)
	_tail.add_child(HSeparator.new())
	_tail.add_child(UIKit.label(_endings_line(), 15, UIKit.INK_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_tail.add_child(row)
	_buttons = UIKit.button("New run", func() -> void: click(); close({"action": &"new"}))
	row.add_child(_buttons)
	row.add_child(UIKit.button("Main menu", func() -> void: click(); close({"action": &"menu"})))

	var skip_hint := UIKit.label("[%s] or click: skip" % UIKit.key_label(&"interact"), 13, UIKit.INK_DIM)
	skip_hint.name = "SkipHint"
	v.add_child(skip_hint)
	# The root control swallows mouse clicks (MOUSE_FILTER_STOP), so a click-to-skip has to come from gui_input.
	gui_input.connect(func(e: InputEvent) -> void:
		if not _done and e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			skip())
	AudioDirector.say(StringName(data["voice"]))


func _add_typed(parent: Control, l: Label) -> void:
	l.visible_characters = 0
	parent.add_child(l)
	_labels.append(l)


func _endings_line() -> String:
	var names: Array[String] = []
	for e in ENDING_ORDER:
		var seen := SaveService.has_ending(e) or (e == ending and _content_key == ending)
		names.append(String(ENDING_NAMES[e]) if seen else "???")
	return "Endings seen: " + ",  ".join(PackedStringArray(names))


func _process(delta: float) -> void:
	if _done or _labels.is_empty():
		return
	if _hold > 0.0:
		_hold -= delta
		return
	var l := _labels[_i]
	if _chars == 0.0:
		_scroll_to.call_deferred(l)
	_chars += delta * CPS
	if int(_chars) >= l.text.length():
		l.visible_characters = -1
		_i += 1
		_chars = 0.0
		_hold = PARAGRAPH_PAUSE
		if _i >= _labels.size():
			_finish()
	else:
		l.visible_characters = int(_chars)


func _scroll_to(c: Control) -> void:
	if _scroll != null and is_instance_valid(c) and _scroll.is_ancestor_of(c):
		_scroll.ensure_control_visible(c)


func skip() -> void:
	## Reveal everything at once.
	for l in _labels:
		l.visible_characters = -1
	_i = _labels.size()
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	var sk := find_child("SkipHint", true, false) as Control
	if sk != null:
		sk.visible = false
	_tail.visible = true
	if not Settings.reduce_motion:
		_tail.modulate.a = 0.0
		create_tween().tween_property(_tail, "modulate:a", 1.0, 0.6)
	if _buttons != null:
		_buttons.grab_focus.call_deferred()


func is_done() -> bool:
	return _done


func _unhandled_input(event: InputEvent) -> void:
	var press := event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept") \
		or event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")
	if not press:
		return
	if not _done:
		get_viewport().set_input_as_handled()
		skip()
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close({"action": &"menu"})
