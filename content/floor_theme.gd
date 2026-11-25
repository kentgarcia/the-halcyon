class_name FloorTheme
extends RefCounted
## The look of a floor: which library materials its walls/floors/ceilings use, plus fog and light colour.
## Pure data. Chunks reference materials by library name through this theme (CLAUDE.md).

var id: StringName = &"yellow"
var floor_variants: Array = []          ## [{"mat": &"carpet_green", "w": 0.8}, ...]
var floor_alt: StringName = &"carpet_green_detail"      ## used for ',' tiles
var wall_clean: Array[StringName] = []
var wall_damaged: Array[StringName] = []
var wall_weights: Array[float] = []
var pillar_mat: StringName = &"wall_yellow_small"
var ceiling_size: StringName = &"medium"
var ceiling_uneven_chance: float = 0.04
var fog_color: Color = Color(0.16, 0.14, 0.07)
var fog_density: float = 0.06
var light_color: Color = Color(1.0, 0.93, 0.74)
var ambient_floor: float = 0.045
var light_gain: float = 1.2
var lamp_color: Color = Color(1.0, 0.95, 0.82)
var panel_light_energy: float = 0.8
var door_default: StringName = &"door_wood"
var surface: StringName = &"carpet"        ## footstep set: carpet | concrete | tile | metal | water
var skybox_color: Color = Color(0.02, 0.02, 0.02)
var decay_bias: int = 0


func pick_floor(h: int) -> StringName:
	if floor_variants.is_empty():
		return &"carpet_green"
	var total := 0.0
	for v in floor_variants:
		total += float(v["w"])
	var roll := float(absi(h) % 1000) / 1000.0 * total
	var acc := 0.0
	for v in floor_variants:
		acc += float(v["w"])
		if roll < acc:
			return v["mat"]
	return floor_variants[0]["mat"]


func pick_wall(h: int, damaged_chance: float) -> StringName:
	var hv := absi(h)
	if not wall_damaged.is_empty() and damaged_chance > 0.0 and float(hv % 997) / 997.0 < damaged_chance:
		return wall_damaged[(hv / 997) % wall_damaged.size()]
	if wall_clean.is_empty():
		return &"wall_yellow"
	if wall_weights.size() != wall_clean.size():
		return wall_clean[(hv / 31) % wall_clean.size()]
	var total := 0.0
	for w in wall_weights:
		total += w
	var roll := float((hv / 31) % 1000) / 1000.0 * total
	var acc := 0.0
	for i in wall_clean.size():
		acc += wall_weights[i]
		if roll < acc:
			return wall_clean[i]
	return wall_clean[0]


func material_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for v in floor_variants:
		out.append(v["mat"])
	out.append(floor_alt)
	out.append_array(wall_clean)
	out.append_array(wall_damaged)
	out.append(pillar_mat)
	for suffix in ["", "_uneven", "_open", "_light_on", "_light_off", "_light_flicker"]:
		out.append(StringName("ceiling_%s%s" % [ceiling_size, suffix]))
	out.append(door_default)
	return out
