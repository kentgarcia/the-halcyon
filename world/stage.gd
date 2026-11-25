class_name Stage
extends Node3D
## The 3D world of one floor: environment, chunk container, light field. Lives inside Main's low-res
## SubViewport. Systems attach as children (player, doors, entities); Stage itself holds no gameplay.

var env_node: WorldEnvironment
var environment: Environment
var chunks_root: Node3D
var actors_root: Node3D
var light_field: LightField
var theme: FloorTheme
var chunks: Dictionary = {}               ## uid -> Chunk


func _init() -> void:
	name = "Stage"


func _ready() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.01, 0.01, 0.01)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0, 0, 0)
	environment.ambient_light_energy = 0.0
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	env_node = WorldEnvironment.new()
	env_node.environment = environment
	add_child(env_node)

	chunks_root = Node3D.new()
	chunks_root.name = "Chunks"
	add_child(chunks_root)
	actors_root = Node3D.new()
	actors_root.name = "Actors"
	add_child(actors_root)

	light_field = LightField.new()
	light_field.name = "LightField"
	add_child(light_field)


func apply_theme(t: FloorTheme) -> void:
	theme = t
	environment.fog_light_color = t.fog_color
	environment.fog_density = t.fog_density
	environment.fog_aerial_perspective = 0.0
	environment.fog_sky_affect = 1.0
	environment.background_color = t.fog_color * 0.5
	MaterialLibrary.set_light_color(t.light_color)
	MaterialLibrary.set_ambient(t.ambient_floor, t.light_gain)


func add_chunk(c: Chunk) -> void:
	chunks[c.uid] = c
	chunks_root.add_child(c)
	light_field.register_chunk(c)


func remove_chunk(c: Chunk) -> void:
	light_field.unregister_chunk(c)
	chunks.erase(c.uid)
	c.dispose()


func clear_chunks() -> void:
	for uid in chunks.keys():
		remove_chunk(chunks[uid])
	chunks.clear()
