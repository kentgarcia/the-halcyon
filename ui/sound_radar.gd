class_name SoundRadar
extends Control
## Accessibility (SPEC 11.3): a faint ring of chevrons around the crosshair that shows which way a sound came from.
## Off by default (Settings.sound_radar). It only ever echoes sounds the game really played, so it can never lie:
## the house may lie in what it says, never in what it shows (SPEC 4.2).

const RING_R := 74.0
const LIFE := 1.8
const MAX_RANGE := 40.0
## Everyday sounds the guest causes or already knows about are not worth a chevron.
const MUNDANE_PREFIXES: Array[String] = ["step_", "switch_", "battery_", "bulb_insert", "bulb_remove", "cam_", "door_open", "door_close", "pickup"]

var player: Player = null
var _marks: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.sound_heard.connect(_on_sound)


func _exit_tree() -> void:
	if EventBus.sound_heard.is_connected(_on_sound):
		EventBus.sound_heard.disconnect(_on_sound)


func _on_sound(id: StringName, pos: Vector3) -> void:
	if not Settings.sound_radar or player == null or player.camera == null:
		return
	if is_mundane(id):
		return
	var dist := player.camera.global_position.distance_to(pos)
	if dist > MAX_RANGE:
		return
	_marks.append({"pos": pos, "t": LIFE, "id": id})
	if _marks.size() > 8:
		_marks.pop_front()


func _process(delta: float) -> void:
	for m in _marks:
		m["t"] = float(m["t"]) - delta
	_marks = _marks.filter(func(m): return float(m["t"]) > 0.0)
	visible = Settings.sound_radar and not _marks.is_empty()
	if visible:
		queue_redraw()


func bearing_of(pos: Vector3) -> float:
	return bearing(player.camera.global_transform, pos)


static func bearing(cam: Transform3D, pos: Vector3) -> float:
	## Radians clockwise from straight ahead (0 = in front, PI/2 = right, PI = behind).
	var local := cam.basis.inverse() * (pos - cam.origin)
	return atan2(local.x, -local.z)


static func is_mundane(id: StringName) -> bool:
	var name := String(id)
	for pre in MUNDANE_PREFIXES:
		if name.begins_with(pre):
			return true
	return false


func _draw() -> void:
	if player == null or player.camera == null:
		return
	var c := size * 0.5
	for m in _marks:
		var a := bearing_of(m["pos"])
		var fade := clampf(float(m["t"]) / LIFE, 0.0, 1.0)
		var dist := player.camera.global_position.distance_to(m["pos"])
		var alpha := fade * clampf(1.2 - dist / MAX_RANGE, 0.35, 1.0)
		var dir := Vector2(sin(a), -cos(a))
		var tip := c + dir * (RING_R + 10.0)
		var base := c + dir * (RING_R - 6.0)
		var side := Vector2(-dir.y, dir.x) * 7.0
		var col := Color(0.95, 0.82, 0.45, alpha)
		draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), col)
