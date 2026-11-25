class_name AutopsyScreen
extends ScreenBase
## Autopsy (SPEC 4.4): after a Blackout, the last 20 s from the tape, the rule line, and what was true.
## Always skippable; Retry unlocks after 1.5 s so a mashed button cannot skip the lesson by accident.

var info: Dictionary = {}
var frames: Array = []
var fps := 10.0
var _tex: ImageTexture
var _rect: TextureRect
var _t := 0.0
var _retry: Button
var _bar: ProgressBar


func setup(p_args: Dictionary = {}) -> void:
	super.setup(p_args)
	info = args.get("info", {})
	frames = info.get("frames", [])
	fps = float(info.get("fps", 10.0))
	dim_world = 1.0


func _build() -> void:
	var def: FloorDef = FloorCatalog.get_def(StringName(info.get("floor_id", &"yellow")))
	var truth := int(info.get("truth", 0))
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 60
	root.offset_right = -60
	root.offset_top = 50
	root.offset_bottom = -50
	root.add_theme_constant_override("separation", 30)
	add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.4
	root.add_child(left)
	left.add_child(UIKit.label("AUTOPSY  -  GUEST NO. %d" % RunState.guest_number, 18, UIKit.REC_RED, true))
	_tex = ImageTexture.create_from_image(Image.create_empty(TapeBuffer.W, TapeBuffer.H, false, Image.FORMAT_RGB8))
	_rect = TextureRect.new()
	_rect.texture = _tex
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rect.custom_minimum_size = Vector2(512, 384)
	left.add_child(_rect)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	left.add_child(_bar)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	root.add_child(right)
	right.add_child(UIKit.label(def.title, 22, UIKit.ACCENT, true))
	var rule_text := String(info.get("rule", ""))
	if rule_text != "":
		var rl := UIKit.label("Rule %d: \"%s\"" % [int(info.get("rule_number", 0)), rule_text], 20, UIKit.INK, true)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(rl)
		var verdict := "On this run, that rule was TRUE." if truth == RunState.Truth.HOLDS else "On this run, that rule was a LIE."
		right.add_child(UIKit.label(verdict, 20, UIKit.INK_GOOD if truth == RunState.Truth.HOLDS else UIKit.INK_WARN, true))
	var note := EntityNotes.note(def.entity_id, truth)
	if note != "":
		var nl := UIKit.label(note, 18, UIKit.INK)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(nl)
	var cause := String(info.get("cause", ""))
	if cause != "":
		right.add_child(UIKit.label("Last seen: %s" % _cause_name(cause), 15, UIKit.INK_DIM))
	right.add_child(UIKit.label("The next attempt is a different building. Your notebook remembers.", 15, UIKit.INK_DIM))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp)
	_retry = UIKit.button("Try again", func(): click(); close(&"retry"))
	_retry.disabled = true
	right.add_child(_retry)
	right.add_child(UIKit.button("Skip", func(): click(); close(&"retry")))
	AudioDirector.play(&"cam_rewind_loop", -6.0)


func _cause_name(cause: String) -> String:
	match cause:
		"housekeeping": return "Housekeeping"
		"verdict": return "a wrong Verdict"
		_: return EntityNotes.name_of(StringName(cause)) if EntityNotes.NAMES.has(StringName(cause)) else cause


func _process(delta: float) -> void:
	_t += delta
	if _retry != null and _retry.disabled and _t > 1.5:
		_retry.disabled = false
		_retry.grab_focus()
	if frames.is_empty() or _tex == null:
		return
	var n := frames.size()
	var i := int(_t * fps) % n
	var b: PackedByteArray = frames[i]
	if b.size() == TapeBuffer.FRAME_BYTES:
		_tex.update(TapeBuffer.to_image(b))
	if _bar != null:
		_bar.value = 100.0 * float(i) / float(n)
