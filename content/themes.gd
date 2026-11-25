class_name Themes
extends RefCounted
## The look of each floor, by id. Pure data over library material names (never raw texture paths).

static var _cache: Dictionary = {}


static func get_theme(id: StringName) -> FloorTheme:
	if _cache.has(id):
		return _cache[id]
	var t: FloorTheme
	match id:
		&"yellow": t = _yellow()
		&"boiler": t = _boiler()
		&"natatorium": t = _natatorium()
		&"blue": t = _blue()
		&"units": t = _units()
		&"lobby": t = _lobby()
		&"elevator": t = _elevator()
		_: t = _yellow()
	_cache[id] = t
	return t


static func _yellow() -> FloorTheme:
	var t := FloorTheme.new()
	t.id = &"yellow"
	t.floor_variants = [
		{"mat": &"carpet_green", "w": 0.80},
		{"mat": &"carpet_green_detail", "w": 0.14},
		{"mat": &"carpet_green_fluff", "w": 0.06},
	]
	t.floor_alt = &"carpet_green_detail"
	t.wall_clean = [&"wall_yellow_pattern", &"wall_yellow_pattern_panel", &"wall_yellow_pattern_light", &"wall_yellow_pattern_light_panel"]
	t.wall_weights = [0.50, 0.28, 0.12, 0.10]
	t.wall_damaged = [&"wall_yellow_pattern_damaged", &"wall_yellow_pattern_light_damaged", &"wall_yellow_pattern_panel_damaged", &"wall_yellow_pattern_light_panel_damaged"]
	t.pillar_mat = &"wall_yellow_pattern_small"
	t.ceiling_size = &"medium"
	t.fog_color = Color(0.20, 0.17, 0.08)
	t.fog_density = 0.04
	t.light_color = Color(1.0, 0.92, 0.70)
	t.ambient_floor = 0.09
	t.light_gain = 1.3
	t.door_default = &"door_wood"
	return t


static func _boiler() -> FloorTheme:
	var t := FloorTheme.new()
	t.id = &"boiler"
	t.floor_variants = [
		{"mat": &"metal_structure", "w": 0.6},
		{"mat": &"metal_structure_bolts", "w": 0.4},
	]
	t.floor_alt = &"metal_structure_bolts"
	t.wall_clean = [&"wall_concrete", &"wall_concrete_dirt"]
	t.wall_weights = [0.6, 0.4]
	t.wall_damaged = [&"wall_concrete_dirt"]
	t.pillar_mat = &"wall_concrete_small"
	t.ceiling_size = &"large"
	t.fog_color = Color(0.13, 0.07, 0.05)
	t.fog_density = 0.07
	t.light_color = Color(1.0, 0.72, 0.5)
	t.ambient_floor = 0.04
	t.light_gain = 1.15
	t.door_default = &"door_emergency_exit"
	t.surface = &"metal"
	return t


static func _natatorium() -> FloorTheme:
	var t := FloorTheme.new()
	t.id = &"natatorium"
	t.floor_variants = [
		{"mat": &"pool_tiles", "w": 0.55},
		{"mat": &"pool_tiles_medium", "w": 0.2},
		{"mat": &"pool_tiles_small", "w": 0.15},
		{"mat": &"pool_tiles_line", "w": 0.1},
	]
	t.floor_alt = &"pool_tiles_medium_uneven"
	t.wall_clean = [&"pool_wall", &"pool_wall_uneven"]
	t.wall_weights = [0.7, 0.3]
	t.wall_damaged = [&"pool_wall_dirt", &"pool_wall_uneven_dirt"]
	t.pillar_mat = &"pool_side"
	t.ceiling_size = &"large"
	t.fog_color = Color(0.07, 0.13, 0.15)
	t.fog_density = 0.06
	t.light_color = Color(0.82, 0.95, 1.0)
	t.ambient_floor = 0.05
	t.light_gain = 1.25
	t.door_default = &"door_wood_light"
	t.surface = &"tile"
	return t


static func _blue() -> FloorTheme:
	var t := FloorTheme.new()
	t.id = &"blue"
	t.floor_variants = [
		{"mat": &"carpet_green", "w": 0.7},
		{"mat": &"carpet_green_detail", "w": 0.3},
	]
	t.floor_alt = &"carpet_green_detail"
	t.wall_clean = [&"wall_blue_stripes", &"wall_blue_stripes_panel", &"wall_blue_stripes_light", &"wall_blue_stripes_light_panel", &"wall_blue_panel"]
	t.wall_weights = [0.35, 0.25, 0.15, 0.15, 0.10]
	t.wall_damaged = [&"wall_blue_stripes_damaged", &"wall_blue_stripes_light_damaged", &"wall_blue_stripes_panel_damaged", &"wall_blue_stripes_light_panel_damaged"]
	t.pillar_mat = &"wall_blue_stripes_small"
	t.ceiling_size = &"small"
	t.fog_color = Color(0.07, 0.10, 0.15)
	t.fog_density = 0.06
	t.light_color = Color(0.86, 0.93, 1.0)
	t.ambient_floor = 0.05
	t.light_gain = 1.2
	t.door_default = &"door_wood_light"
	return t


static func _units() -> FloorTheme:
	var t := FloorTheme.new()
	t.id = &"units"
	t.floor_variants = [
		{"mat": &"carpet_red", "w": 0.8},
		{"mat": &"carpet_red_detail", "w": 0.13},
		{"mat": &"carpet_red_fluff", "w": 0.07},
	]
	t.floor_alt = &"carpet_red_detail"
	t.wall_clean = [&"wall_yellow_pattern_light", &"wall_yellow_pattern_light_panel", &"wall_yellow_light_panel", &"wall_yellow_pattern_panel"]
	t.wall_weights = [0.35, 0.35, 0.15, 0.15]
	t.wall_damaged = [&"wall_yellow_pattern_light_damaged", &"wall_yellow_pattern_light_panel_damaged"]
	t.pillar_mat = &"wall_yellow_pattern_small"
	t.ceiling_size = &"small"
	t.fog_color = Color(0.14, 0.08, 0.06)
	t.fog_density = 0.05
	t.light_color = Color(1.0, 0.86, 0.68)
	t.ambient_floor = 0.055
	t.light_gain = 1.2
	t.door_default = &"door_wood"
	return t


static func _lobby() -> FloorTheme:
	var t := FloorTheme.new()
	t.id = &"lobby"
	t.floor_variants = [
		{"mat": &"carpet_red", "w": 0.85},
		{"mat": &"carpet_red_detail", "w": 0.15},
	]
	t.floor_alt = &"carpet_red_detail"
	t.wall_clean = [&"wall_yellow_panel", &"wall_yellow_light_panel", &"wall_yellow_arch", &"wall_yellow_arch_detailed"]
	t.wall_weights = [0.4, 0.4, 0.1, 0.1]
	t.wall_damaged = [&"wall_yellow_pattern_panel_damaged"]
	t.pillar_mat = &"wall_yellow_small"
	t.ceiling_size = &"large"
	t.fog_color = Color(0.17, 0.11, 0.08)
	t.fog_density = 0.035
	t.light_color = Color(1.0, 0.88, 0.7)
	t.ambient_floor = 0.07
	t.light_gain = 1.3
	t.door_default = &"door_wood_ornate"
	return t


static func _elevator() -> FloorTheme:
	var t := FloorTheme.new()
	t.id = &"elevator"
	t.floor_variants = [{"mat": &"carpet_red", "w": 1.0}]
	t.floor_alt = &"carpet_red_detail"
	t.wall_clean = [&"wall_yellow_light_panel"]
	t.wall_weights = [1.0]
	t.wall_damaged = []
	t.pillar_mat = &"wall_yellow_small"
	t.ceiling_size = &"large"
	t.fog_color = Color(0.1, 0.07, 0.05)
	t.fog_density = 0.02
	t.light_color = Color(1.0, 0.9, 0.72)
	t.ambient_floor = 0.1
	t.light_gain = 1.3
	t.door_default = &"door_elevator"
	return t
