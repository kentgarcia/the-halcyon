class_name MaterialLibrary
extends RefCounted
## Materials are requested by library NAME (the Kenney file stem), never by raw texture path
## (CLAUDE.md non-negotiable). Every material uses the world surface shader: nearest + mipmaps,
## lit by the light field, with family flags applied here (SPEC Appendix A):
##   doorway_*, *_arch_open  -> alpha scissor + double sided
##   ceiling_*_light_on      -> self-lit
##   ceiling_*_light_flicker -> synthetic name: the _on texture on a shared, script-animated material
##   pool_water*             -> scrolling UV (vents stay static)

const TEX_DIR := "res://assets/third_party/kenney_retro_liminal/PNG/"
const SHADER_1S: Shader = preload("res://shaders/world_surface.gdshader")
const SHADER_2S: Shader = preload("res://shaders/world_surface_2s.gdshader")

static var _mats: Dictionary = {}               ## StringName -> ShaderMaterial
static var _tex_cache: Dictionary = {}          ## StringName -> Texture2D
static var _flicker_mats: Array[ShaderMaterial] = []
static var _white: Texture2D = null
static var _exists_cache: Dictionary = {}

# Light-field state pushed to every material.
static var field_texture: Texture2D = null
static var field_rect := Vector4(0.0, 0.0, 0.0, 0.0)
static var light_color := Color(1.0, 0.93, 0.74)
static var ambient_floor := 0.05
static var light_gain := 1.15
static var dread_dim := 0.0
static var vertex_snap := 0.0


static func has_texture(mat_name: StringName) -> bool:
	if _exists_cache.has(mat_name):
		return _exists_cache[mat_name]
	var p := _path_of(_base_name(mat_name))
	var ok := ResourceLoader.exists(p) or FileAccess.file_exists(ProjectSettings.globalize_path(p))
	_exists_cache[mat_name] = ok
	return ok


static func get_material(mat_name: StringName) -> ShaderMaterial:
	if _mats.has(mat_name):
		return _mats[mat_name]
	var m := _make(mat_name)
	_mats[mat_name] = m
	return m


static func solid(mat_name: StringName, color: Color, self_lit: float = 0.0) -> ShaderMaterial:
	## A flat-colour material for props/entities built from cubes (no texture).
	var key := StringName("solid:%s" % mat_name)
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER_1S
	m.set_shader_parameter("albedo_tex", _white_texture())
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("emission_boost", self_lit)
	_push_field(m)
	_mats[key] = m
	return m


static func unlit_color(mat_name: StringName, color: Color) -> ShaderMaterial:
	## Ignores the light field (used for things that glow by themselves: LCD, REC dot, signs).
	var key := StringName("unlit:%s" % mat_name)
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER_1S
	m.set_shader_parameter("albedo_tex", _white_texture())
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("emission_boost", 1.0)
	m.set_shader_parameter("lit_by_field", 0.0)
	_push_field(m)
	_mats[key] = m
	return m


static func custom(mat_name: StringName, shader: Shader, albedo_base: StringName) -> ShaderMaterial:
	## A library-tracked material with its own shader (water ripples). The shader must declare the same
	## light-field uniforms as the world surface shader so every set_field()/set_ambient() push reaches it.
	var key := StringName("custom:%s" % mat_name)
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("albedo_tex", _texture(String(albedo_base)))
	_push_field(m)
	_mats[key] = m
	return m


static func flicker_materials() -> Array[ShaderMaterial]:
	return _flicker_mats


static func set_field(texture: Texture2D, rect: Vector4) -> void:
	field_texture = texture
	field_rect = rect
	for m in _all():
		m.set_shader_parameter("light_map", texture)
		m.set_shader_parameter("light_rect", rect)


static func set_light_color(c: Color) -> void:
	light_color = c
	for m in _all():
		m.set_shader_parameter("light_color", c)


static func set_ambient(floor_level: float, gain: float) -> void:
	ambient_floor = floor_level
	light_gain = gain
	for m in _all():
		m.set_shader_parameter("ambient_floor", floor_level)
		m.set_shader_parameter("light_gain", gain * 1.25)      # LightField.HEADROOM


static func set_dread_dim(v: float) -> void:
	if absf(v - dread_dim) < 0.01:
		return
	dread_dim = v
	for m in _all():
		m.set_shader_parameter("dread_dim", v)


static func set_vertex_snap(v: float) -> void:
	vertex_snap = v
	for m in _all():
		m.set_shader_parameter("vertex_snap", v)


static func clear_cache() -> void:
	_mats.clear()
	_tex_cache.clear()
	_flicker_mats.clear()


# --- internals -----------------------------------------------------------------------------

static func _all() -> Array:
	return _mats.values()


static func _base_name(mat_name: StringName) -> String:
	var s := String(mat_name)
	if s.ends_with("_light_flicker"):
		return s.trim_suffix("_flicker") + "_on"
	return s


static func _path_of(base: String) -> String:
	return TEX_DIR + base + ".png"


static func _make(mat_name: StringName) -> ShaderMaterial:
	var s := String(mat_name)
	var base := _base_name(mat_name)
	var m := ShaderMaterial.new()
	var two_sided := s.begins_with("doorway_") or s.ends_with("_arch_open")
	m.shader = SHADER_2S if two_sided else SHADER_1S
	m.set_shader_parameter("albedo_tex", _texture(base))
	if two_sided:
		m.set_shader_parameter("scissor_cut", 0.5)
	if s.begins_with("ceiling_") and s.ends_with("_light_on"):
		m.set_shader_parameter("emission_boost", 0.6)
	if s.ends_with("_light_flicker"):
		m.set_shader_parameter("emission_boost", 0.6)
		_flicker_mats.append(m)
	if s.begins_with("pool_water") and not s.ends_with("_vent"):
		m.set_shader_parameter("uv_scroll", Vector2(0.028, 0.017))
	_push_field(m)
	return m


static func _push_field(m: ShaderMaterial) -> void:
	if field_texture != null:
		m.set_shader_parameter("light_map", field_texture)
	m.set_shader_parameter("light_rect", field_rect)
	m.set_shader_parameter("light_color", light_color)
	m.set_shader_parameter("ambient_floor", ambient_floor)
	m.set_shader_parameter("light_gain", light_gain * 1.25)    # LightField.HEADROOM
	m.set_shader_parameter("dread_dim", dread_dim)
	m.set_shader_parameter("vertex_snap", vertex_snap)


static func _texture(base: String) -> Texture2D:
	var key := StringName(base)
	if _tex_cache.has(key):
		return _tex_cache[key]
	var path := _path_of(base)
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	else:
		# Not imported yet (fresh checkout / headless before `dev.sh import`): load the PNG directly.
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null:
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
	if tex == null:
		push_warning("MaterialLibrary: unknown material '%s'" % base)
		tex = _white_texture()
	_tex_cache[key] = tex
	return tex


static func _white_texture() -> Texture2D:
	if _white == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white
