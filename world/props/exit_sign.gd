class_name ExitSign
extends Node3D
## A green EXIT plate stuck to the room side of an exit door (B3 Boiler). It is part of the Foreman's honest
## tell (SPEC 6.2): it burns steady while the house is honest and FLICKERS over the exit he waits behind when
## the card lies. It is parented to the door leaf so it swings with the door.

var flickering := false
var _on: MeshInstance3D = null
var _off: MeshInstance3D = null
var _label: Label3D = null
var _t := 0.0


static func create() -> ExitSign:
	var s := ExitSign.new()
	s.name = "ExitSign"
	var on := MeshBuilder.new()
	on.box(&"#101410", Vector3(0, 0, 0), Vector3(0.54, 0.2, 0.012))
	on.box(&"*#23b35e", Vector3(0, 0, 0.007), Vector3(0.5, 0.16, 0.004))
	var off := MeshBuilder.new()
	off.box(&"#101410", Vector3(0, 0, 0), Vector3(0.54, 0.2, 0.012))
	off.box(&"#0f3b22", Vector3(0, 0, 0.007), Vector3(0.5, 0.16, 0.004))
	s._on = _mesh("On", on)
	s._off = _mesh("Off", off)
	s._off.visible = false
	s.add_child(s._on)
	s.add_child(s._off)
	s._label = PropFactory.make_label("EXIT", Color(0.92, 1.0, 0.92), 0.14)
	s._label.position = Vector3(0, 0, 0.012)
	s._label.rotation.y = 0.0
	s._label.double_sided = true
	s.add_child(s._label)
	return s


static func _mesh(n: String, mb: MeshBuilder) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mb.build()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func attach(door: Door, room_on_side_a: bool) -> ExitSign:
	## One sign per door (idempotent). The leaf spans x 0..W from the hinge; side A is +Z.
	if door == null or door.pivot == null:
		return null
	if door.has_meta(&"exit_sign"):
		var old: Variant = door.get_meta(&"exit_sign")
		if is_instance_valid(old):
			return old as ExitSign
	var s := create()
	door.pivot.add_child(s)
	var face := 1.0 if room_on_side_a else -1.0
	s.position = Vector3(GameScale.DOOR_W * 0.5, GameScale.DOOR_H - 0.3, face * (GameScale.DOOR_LEAF_T * 0.5 + 0.012))
	s.rotation.y = 0.0 if room_on_side_a else PI
	door.set_meta(&"exit_sign", s)
	return s


func set_flicker(on: bool) -> void:
	flickering = on
	if not on:
		_show(true)


func _show(lit: bool) -> void:
	_on.visible = lit
	_off.visible = not lit
	_label.modulate = Color(0.92, 1.0, 0.92) if lit else Color(0.2, 0.34, 0.24)


func _process(delta: float) -> void:
	if not flickering:
		return
	_t += delta
	# a failing ballast: mostly dark with stuttering bright bursts (deterministic, no RNG needed)
	var v := sin(_t * 31.0) + sin(_t * 17.3 + 1.7) + sin(_t * 5.1)
	_show(v > 0.45)
