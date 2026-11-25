class_name Silhouette
extends Node3D
## A dithered billboard figure (see shaders/entity_silhouette.gdshader). Faces the camera around Y.
## Owned and moved by an entity; this node only draws.

const SHADER: Shader = preload("res://shaders/entity_silhouette.gdshader")

var mesh: MeshInstance3D
var mat: ShaderMaterial
var height := 2.3
var width := 1.0
var face_camera := true
var _flash := 0.0
var _presence := 1.0
var _presence_target := 1.0


static func create(shape_id: int, p_height: float = 2.3, aspect: float = 0.42, p_body: Color = Color(0.02, 0.018, 0.015)) -> Silhouette:
	var s := Silhouette.new()
	s.height = p_height
	s.width = p_height * aspect
	s.name = "Silhouette"
	s.mat = ShaderMaterial.new()
	s.mat.shader = SHADER
	s.mat.set_shader_parameter("shape_id", shape_id)
	s.mat.set_shader_parameter("aspect", aspect)
	s.mat.set_shader_parameter("body_color", p_body)
	var q := QuadMesh.new()
	q.size = Vector2(s.width, p_height)
	s.mesh = MeshInstance3D.new()
	s.mesh.mesh = q
	s.mesh.material_override = s.mat
	s.mesh.position = Vector3(0, p_height * 0.5, 0)
	s.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(s.mesh)
	return s


func set_presence(v: float, instant: bool = false) -> void:
	_presence_target = clampf(v, 0.0, 1.0)
	if instant:
		_presence = _presence_target
		mat.set_shader_parameter("presence", _presence)


func flash(amount: float = 1.0) -> void:
	_flash = amount


func _process(delta: float) -> void:
	_presence = move_toward(_presence, _presence_target, delta * 1.5)
	mat.set_shader_parameter("presence", _presence)
	visible = _presence > 0.01
	_flash = maxf(0.0, _flash - delta * 3.0)
	mat.set_shader_parameter("flash", _flash)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var to := cam.global_position - global_position
		if face_camera:
			rotation.y = atan2(to.x, to.z)
		var cc: Node = Game.session.camcorder if Game.session != null and "camcorder" in Game.session else null
		var boost := 0.0
		if cc != null and cc.has_method("is_raised") and (cc.is_raised() or cc.in_playback()):
			boost = 1.0
		mat.set_shader_parameter("cam_boost", boost)
