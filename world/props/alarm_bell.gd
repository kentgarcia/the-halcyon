class_name AlarmBell
extends Node3D
## A wall alarm bell with a red strobe (B3 Boiler). The alarm is what summons the Foreman (SPEC 6.2): the
## bell is the "alarm source" of its room. Wall-mounted prop convention: back plane at z = 0, front is -Z.

var local_tile: Vector2i = Vector2i.ZERO      ## open tile in front of the bell (chunk-local)
var world_tile: Vector2i = Vector2i.ZERO
var ringing := false
var _loop: AudioStreamPlayer3D = null
var _gong: MeshInstance3D = null
var _strobe: MeshInstance3D = null
var _t := 0.0
var _left := 0.0


static func create() -> AlarmBell:
	var b := AlarmBell.new()
	b.name = "AlarmBell"
	var plate := MeshBuilder.new()
	plate.box(&"#4a1b1b", Vector3(0, 0, -0.02), Vector3(0.42, 0.42, 0.04))
	plate.box(&"#2a2a2d", Vector3(0, -0.18, -0.05), Vector3(0.36, 0.03, 0.03))
	var pm := MeshInstance3D.new()
	pm.name = "Plate"
	pm.mesh = plate.build()
	pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(pm)
	var gong := MeshBuilder.new()
	gong.box(&"#b08d2a", Vector3(0, 0, 0), Vector3(0.30, 0.30, 0.06))
	gong.box(&"#c9a227", Vector3(0, 0, -0.045), Vector3(0.22, 0.22, 0.05))
	gong.box(&"#e0c24a", Vector3(0, 0, -0.08), Vector3(0.12, 0.12, 0.04))
	b._gong = MeshInstance3D.new()
	b._gong.name = "Gong"
	b._gong.mesh = gong.build()
	b._gong.position = Vector3(0, 0, -0.09)
	b._gong.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(b._gong)
	var lamp := MeshBuilder.new()
	lamp.box(&"*#ff3b2a", Vector3(0, 0, 0), Vector3(0.12, 0.09, 0.07))
	b._strobe = MeshInstance3D.new()
	b._strobe.name = "Strobe"
	b._strobe.mesh = lamp.build()
	b._strobe.position = Vector3(0, 0.3, -0.05)
	b._strobe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b._strobe.visible = false
	b.add_child(b._strobe)
	return b


func ring(seconds: float) -> void:
	## Start (or extend) the alarm. The loop is a positional emitter on the bell itself.
	_left = maxf(_left, seconds)
	if ringing:
		return
	ringing = true
	_t = 0.0
	if _loop == null or not is_instance_valid(_loop):
		_loop = AudioDirector.play_looped_at(&"alarm_loop", self, -2.0)


func silence() -> void:
	ringing = false
	_left = 0.0
	if _loop != null and is_instance_valid(_loop):
		AudioDirector.stop_player(_loop)
		_loop.queue_free()
	_loop = null
	if _strobe != null:
		_strobe.visible = false
	if _gong != null:
		_gong.rotation = Vector3.ZERO


func _exit_tree() -> void:
	if _loop != null and is_instance_valid(_loop):
		_loop.stop()


func _process(delta: float) -> void:
	if not ringing:
		return
	_t += delta
	_left -= delta
	_strobe.visible = fmod(_t, 0.7) < 0.35
	_gong.rotation.z = sin(_t * 46.0) * 0.1
	if _left <= 0.0:
		silence()
