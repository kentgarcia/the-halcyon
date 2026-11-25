class_name QueueBoard
extends Node3D
## The NOW SERVING board of the Blue Annex (SPEC 6.4). Its colour and typeface are the Queue's honest tell:
##   HOLDS     steady amber digits in the clean face Management's voice uses.
##   INVERTED  the same board, but it glitches: the hue slips, a digit is replaced for a frame, the text shudders.
## It shows what the Queue is really doing, so it is TRUE in both variants (Fairness Doctrine 1).

const AMBER := Color(0.97, 0.78, 0.36)
const SICK := Color(0.5, 0.95, 0.82)
const BRUISE := Color(0.93, 0.34, 0.62)
const GLITCH_CHARS := "#?%0189X"

var title: Label3D = null
var digits: Label3D = null
var number := -1
var live := false
var glitchy := false
var _t := 0.0
var _glitch_t := 0.0
var _hue_t := 0.0
var _bold: Font = load("res://fonts/LiberationMono-Bold.ttf")
var _thin: Font = load("res://fonts/LiberationMono-Regular.ttf")


static func create() -> QueueBoard:
	var b := QueueBoard.new()
	b.name = "QueueBoard"
	b.add_child(PropFactory.make(&"queue_board"))
	b.title = PropFactory.make_label("NOW SERVING", AMBER * 0.5, 0.15)
	b.title.position = Vector3(0, 2.2, -0.112)
	b.title.rotation.y = PI                       # a Label3D reads from +Z; the board's face is -Z
	b.add_child(b.title)
	b.digits = PropFactory.make_label("--", AMBER * 0.5, 0.42)
	b.digits.position = Vector3(0, 1.84, -0.112)
	b.digits.rotation.y = PI
	b.add_child(b.digits)
	return b


func set_idle() -> void:
	live = false
	glitchy = false
	number = -1
	_apply("--", AMBER * 0.45)


func activate(truth: int) -> void:
	## The tell: the board wakes in the colour (and face) of the variant it belongs to.
	live = true
	glitchy = truth == RunState.Truth.INVERTED
	digits.font = _thin if glitchy else _bold
	title.font = _thin if glitchy else _bold
	_apply(_text(), AMBER)


func close() -> void:
	live = false
	glitchy = false
	digits.font = _bold
	title.font = _bold
	_apply("--", AMBER * 0.3)
	title.text = "CLOSED"


func set_number(n: int) -> void:
	number = n
	if live:
		_apply(_text(), digits.modulate)


func _text() -> String:
	return "--" if number < 0 else "%02d" % number


func _apply(text: String, color: Color) -> void:
	digits.text = text
	digits.modulate = color
	title.modulate = color * 0.8
	title.text = "NOW SERVING"


func _process(delta: float) -> void:
	if not glitchy or not live:
		return
	var rng := RunState.stream(&"cosmetic")
	_t += delta
	_hue_t -= delta
	if _hue_t <= 0.0:
		_hue_t = rng.randf_range(0.25, 1.1)
		var pick := rng.randi() % 3
		var col: Color = AMBER if pick == 0 else (SICK if pick == 1 else BRUISE)
		digits.modulate = col
		title.modulate = col * 0.8
	_glitch_t -= delta
	if _glitch_t <= 0.0:
		_glitch_t = rng.randf_range(0.2, 0.9)
		var s := _text()
		if rng.randf() < 0.55 and s.length() > 0:
			var i := rng.randi() % s.length()
			s = s.substr(0, i) + GLITCH_CHARS[rng.randi() % GLITCH_CHARS.length()] + s.substr(i + 1)
		digits.text = s
		digits.position.x = rng.randf_range(-0.05, 0.05)
		get_tree().create_timer(0.08).timeout.connect(func():
			if is_instance_valid(digits):
				digits.text = _text()
				digits.position.x = 0.0)
