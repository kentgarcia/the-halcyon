class_name LightTint
extends Node
## Keeps an unshaded visual (Label3D text, decals) as dark as the light field says its spot is, so painted
## evidence reads like the walls around it and is not a glowing sticker in a dead corridor.

var target: Node3D = null
var base_color: Color = Color.WHITE
var field: LightField = null
var _t := 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	_t = 0.12
	var level := 0.12
	if field != null:
		level = clampf(field.level_at_tile(GameScale.world_to_tile(target.global_position)) * 1.15 + 0.1, 0.1, 1.0)
	var c := base_color * level
	c.a = base_color.a
	if target is Label3D:
		(target as Label3D).modulate = c
