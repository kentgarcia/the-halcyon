class_name PropFactory
extends RefCounted
## Cube-list props (SPEC 13.2 fallback: "a handful of cube props are cheap"). Every prop is built from
## coloured boxes through MeshBuilder: one surface per colour, lit by the light field like the walls.
##
## Conventions: origin at the centre of the footprint on the floor; FRONT is -Z. Wall-mounted props have
## their back plane at z = 0 and extend toward -Z (so placing the origin on the wall surface and facing
## away from the wall is all a slot needs). Dimensions are metres, derived from GameScale where they
## relate to the building.

const WOOD := "#6b4a2c"
const WOOD_DARK := "#43301f"
const WOOD_LIGHT := "#8a6a43"
const METAL := "#6d7176"
const METAL_DARK := "#383b40"
const PAPER := "#d9d3b6"
const BEIGE := "#b7ab8c"
const GREEN := "#3e6b3b"
const POT := "#7a4e38"
const CARD := "#9d7a4a"
const RED := "#8e2a2a"
const YELLOW := "#c9a227"
const BLACK := "#121212"
const WHITE := "#e8e8e0"
const BLUE_GLASS := "#7aa6c4"
const FABRIC := "#4a5a63"

## Footprint radius (m) used for collision and for keeping props out of doorways.
const FOOTPRINT := {
	&"desk": Vector3(1.1, 0.75, 0.62),
	&"hide_desk": Vector3(1.1, 0.75, 0.62),
	&"closet": Vector3(0.95, 2.0, 0.6),
	&"hide_closet": Vector3(0.95, 2.0, 0.6),
	&"cabinet": Vector3(0.5, 1.3, 0.6),
	&"cooler": Vector3(0.34, 1.35, 0.4),
	&"plant": Vector3(0.45, 1.0, 0.45),
	&"boxes": Vector3(0.7, 0.9, 0.55),
	&"chair": Vector3(0.45, 0.9, 0.45),
}


static func make(kind: StringName, rng: RandomNumberGenerator = null) -> Node3D:
	## Returns a Node3D with a MeshInstance3D (and a StaticBody3D for solid props). Unknown kinds -> empty node.
	var mb := MeshBuilder.new()
	var root := Node3D.new()
	root.name = String(kind).capitalize().replace(" ", "")
	var solid := true
	match kind:
		&"desk", &"hide_desk": _desk(mb, kind == &"hide_desk")
		&"closet", &"hide_closet": _closet(mb)
		&"cabinet": _cabinet(mb)
		&"breaker": _breaker(mb); solid = false
		&"switch": _switch(mb); solid = false
		&"cooler": _cooler(mb)
		&"suggestion_box": _suggestion_box(mb); solid = false
		&"charger": _charger(mb); solid = false
		&"pa_horn": _pa_horn(mb); solid = false
		&"plant": _plant(mb)
		&"boxes": _boxes(mb)
		&"chair": _chair(mb)
		&"poster": _poster(mb, rng); solid = false
		&"vent": _vent(mb); solid = false
		&"sign": _sign_plate(mb); solid = false
		&"tape": _tape(mb); solid = false
		&"battery": _battery(mb); solid = false
		&"bulb": _bulb(mb); solid = false
		&"crowbar": _crowbar(mb); solid = false
		&"fuse": _fuse(mb); solid = false
		&"key": _key(mb); solid = false
		&"camcorder": _camcorder_prop(mb); solid = false
		&"lost_found": _shelf(mb)
		&"number_dispenser": _dispenser(mb); solid = false
		&"stanchion": _stanchion(mb)
		&"wet_sign": _wet_sign(mb)
		&"tray": _tray(mb); solid = false
		&"desk_lamp": _desk_lamp(mb); solid = false
		&"clock": _clock(mb); solid = false
		&"queue_board": _queue_board(mb); solid = false
		&"unit_door_shut": _unit_door(mb, false); solid = false
		&"unit_door_open": _unit_door(mb, true); solid = false
		&"exit_door": _exit_door(mb); solid = false
		&"key_card": _key_card(mb); solid = false
		_: return root
	var mesh := mb.build()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if solid and FOOTPRINT.has(kind):
		var sb := StaticBody3D.new()
		sb.name = "Body"
		sb.collision_layer = GameScale.LAYER_PROPS | GameScale.LAYER_WORLD
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var fp: Vector3 = FOOTPRINT[kind]
		bs.size = fp
		cs.shape = bs
		var back := kind in [&"closet", &"hide_closet", &"cabinet"]
		cs.position = Vector3(0.0, fp.y * 0.5, -fp.z * 0.5 if back else 0.0)
		sb.add_child(cs)
		root.add_child(sb)
	return root


static func _c(mb: MeshBuilder, color: String, cx: float, cy: float, cz: float, sx: float, sy: float, sz: float) -> void:
	mb.box(StringName(color), Vector3(cx, cy, cz), Vector3(sx, sy, sz))


static func _lit(mb: MeshBuilder, color: String, cx: float, cy: float, cz: float, sx: float, sy: float, sz: float) -> void:
	## self-lit (ignores the light field): LEDs, LCDs, glowing tubes
	mb.box(StringName("*" + color), Vector3(cx, cy, cz), Vector3(sx, sy, sz))


# --- furniture ------------------------------------------------------------------------------

static func _desk(mb: MeshBuilder, hide: bool) -> void:
	_c(mb, WOOD, 0, 0.72, 0, 1.1, 0.06, 0.62)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_c(mb, WOOD_DARK, sx * 0.5, 0.35, sz * 0.26, 0.06, 0.70, 0.06)
	_c(mb, WOOD_DARK, 0, 0.42, 0.27, 1.0, 0.55, 0.04)
	_c(mb, WOOD, 0.4, 0.35, 0.0, 0.28, 0.68, 0.52)
	_c(mb, WOOD_DARK, 0.4, 0.5, -0.265, 0.22, 0.02, 0.01)
	_c(mb, WOOD_DARK, 0.4, 0.25, -0.265, 0.22, 0.02, 0.01)
	_c(mb, PAPER, -0.2, 0.755, 0.05, 0.28, 0.01, 0.2)
	if not hide:
		_c(mb, METAL_DARK, -0.35, 0.8, 0.12, 0.3, 0.1, 0.02)
		_c(mb, METAL_DARK, -0.35, 0.76, 0.12, 0.08, 0.04, 0.08)


static func _closet(mb: MeshBuilder) -> void:
	_c(mb, WOOD, 0, 1.0, -0.3, 0.95, 2.0, 0.6)
	_c(mb, WOOD_DARK, -0.235, 1.0, -0.605, 0.44, 1.84, 0.012)
	_c(mb, WOOD_DARK, 0.235, 1.0, -0.605, 0.44, 1.84, 0.012)
	for i in 7:
		var y := 0.35 + i * 0.22
		_c(mb, BLACK, -0.235, y, -0.612, 0.34, 0.025, 0.004)
		_c(mb, BLACK, 0.235, y, -0.612, 0.34, 0.025, 0.004)
	_c(mb, METAL, -0.05, 1.0, -0.62, 0.025, 0.14, 0.025)
	_c(mb, METAL, 0.05, 1.0, -0.62, 0.025, 0.14, 0.025)


static func _cabinet(mb: MeshBuilder) -> void:
	_c(mb, METAL, 0, 0.65, -0.3, 0.5, 1.3, 0.6)
	for i in 3:
		var y := 0.25 + i * 0.4
		_c(mb, METAL_DARK, 0, y, -0.605, 0.42, 0.01, 0.01)
		_c(mb, METAL_DARK, 0, y + 0.12, -0.61, 0.14, 0.03, 0.02)


static func _cooler(mb: MeshBuilder) -> void:
	_c(mb, BEIGE, 0, 0.45, -0.22, 0.34, 0.9, 0.4)
	_c(mb, METAL_DARK, 0, 0.62, -0.43, 0.2, 0.04, 0.03)
	mb.box(&"*#9cc4dc", Vector3(0, 1.12, -0.22), Vector3(0.26, 0.4, 0.26))
	_c(mb, WHITE, 0, 0.93, -0.22, 0.2, 0.06, 0.2)


static func _plant(mb: MeshBuilder) -> void:
	_c(mb, POT, 0, 0.2, 0, 0.4, 0.4, 0.4)
	_c(mb, "#2a1a10", 0, 0.41, 0, 0.34, 0.03, 0.34)
	_c(mb, GREEN, 0, 0.72, 0, 0.36, 0.5, 0.36)
	_c(mb, "#4a7b44", 0.1, 0.95, 0.05, 0.3, 0.3, 0.3)
	_c(mb, "#35602f", -0.12, 0.85, -0.08, 0.26, 0.34, 0.26)


static func _boxes(mb: MeshBuilder) -> void:
	_c(mb, CARD, 0, 0.25, 0, 0.62, 0.5, 0.5)
	_c(mb, "#8d6c3e", 0.04, 0.65, 0.02, 0.46, 0.3, 0.4)
	_c(mb, PAPER, 0, 0.5, -0.255, 0.3, 0.01, 0.01)
	_c(mb, "#b08d58", -0.45, 0.17, -0.1, 0.3, 0.34, 0.32)


static func _chair(mb: MeshBuilder) -> void:
	_c(mb, FABRIC, 0, 0.45, 0, 0.45, 0.06, 0.45)
	_c(mb, FABRIC, 0, 0.78, 0.2, 0.45, 0.55, 0.06)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_c(mb, METAL_DARK, sx * 0.19, 0.21, sz * 0.19, 0.04, 0.42, 0.04)


static func _shelf(mb: MeshBuilder) -> void:
	_c(mb, METAL_DARK, 0, 0.9, -0.2, 1.1, 1.8, 0.04)
	for i in 4:
		_c(mb, METAL, 0, 0.3 + i * 0.5, -0.4, 1.1, 0.04, 0.45)
	_c(mb, WHITE, 0, 1.9, -0.45, 0.8, 0.12, 0.02)


# --- wall furniture -------------------------------------------------------------------------

static func _breaker(mb: MeshBuilder) -> void:
	_c(mb, METAL_DARK, 0, 1.4, -0.07, 0.56, 0.74, 0.14)
	_c(mb, METAL, 0, 1.4, -0.145, 0.46, 0.64, 0.01)
	_c(mb, YELLOW, 0, 1.72, -0.15, 0.46, 0.05, 0.01)
	_c(mb, PAPER, 0.12, 1.55, -0.155, 0.12, 0.09, 0.005)
	_c(mb, BLACK, 0, 1.38, -0.155, 0.12, 0.4, 0.01)


static func _switch(mb: MeshBuilder) -> void:
	_c(mb, "#cfc7a8", 0, 1.25, -0.015, 0.12, 0.18, 0.03)
	_c(mb, METAL, 0, 1.25, -0.04, 0.03, 0.07, 0.03)


static func _suggestion_box(mb: MeshBuilder) -> void:
	_c(mb, WOOD_DARK, 0, 1.2, -0.1, 0.36, 0.36, 0.2)
	_c(mb, BLACK, 0, 1.3, -0.205, 0.22, 0.02, 0.01)
	_c(mb, PAPER, 0, 1.46, -0.015, 0.4, 0.13, 0.02)
	_c(mb, METAL, 0.14, 1.1, -0.21, 0.04, 0.05, 0.02)


static func _charger(mb: MeshBuilder) -> void:
	_c(mb, METAL_DARK, 0, 1.0, -0.05, 0.32, 0.42, 0.1)
	_c(mb, METAL, 0, 0.9, -0.14, 0.22, 0.12, 0.08)
	_lit(mb, "#55e07a", 0, 1.14, -0.11, 0.18, 0.025, 0.01)
	_lit(mb, "#55e07a", 0, 1.08, -0.11, 0.1, 0.025, 0.01)


static func _pa_horn(mb: MeshBuilder) -> void:
	_c(mb, METAL, 0, 2.0, -0.12, 0.3, 0.24, 0.24)
	_c(mb, METAL_DARK, 0, 2.0, -0.25, 0.22, 0.18, 0.04)
	_c(mb, METAL_DARK, 0, 2.0, -0.02, 0.14, 0.14, 0.04)


static func _poster(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var cols := ["#8f7a52", "#5d7a74", "#9a5a48", "#6c6f8f"]
	var pick: String = cols[(rng.randi() if rng != null else 0) % cols.size()]
	_c(mb, "#2a241b", 0, 1.4, -0.012, 0.64, 0.84, 0.024)
	_c(mb, pick, 0, 1.4, -0.026, 0.56, 0.76, 0.01)
	_c(mb, "#d8d0b0", 0, 1.62, -0.034, 0.36, 0.1, 0.01)
	_c(mb, "#d8d0b0", 0, 1.28, -0.034, 0.3, 0.04, 0.01)
	_c(mb, "#d8d0b0", 0, 1.18, -0.034, 0.22, 0.04, 0.01)


static func _vent(mb: MeshBuilder) -> void:
	_c(mb, METAL, 0, 2.0, -0.04, 0.72, 0.36, 0.08)
	for i in 5:
		_c(mb, BLACK, 0, 1.88 + i * 0.06, -0.085, 0.62, 0.02, 0.01)


static func _sign_plate(mb: MeshBuilder) -> void:
	_c(mb, "#cfc6a3", 0, 1.5, -0.015, 0.52, 0.26, 0.03)
	_c(mb, "#8d8466", 0, 1.5, -0.032, 0.5, 0.24, 0.005)


static func _clock(mb: MeshBuilder) -> void:
	_c(mb, BLACK, 0, 2.05, -0.03, 0.36, 0.36, 0.06)
	_c(mb, WHITE, 0, 2.05, -0.065, 0.31, 0.31, 0.01)
	_c(mb, BLACK, 0, 2.1, -0.075, 0.02, 0.12, 0.005)
	_c(mb, BLACK, 0.05, 2.05, -0.075, 0.1, 0.02, 0.005)


# --- pickups --------------------------------------------------------------------------------

static func _tape(mb: MeshBuilder) -> void:
	_c(mb, "#1c1c1f", 0, 0.035, 0, 0.19, 0.025, 0.105)
	_c(mb, "#cfc8ac", 0, 0.049, 0, 0.12, 0.004, 0.07)
	_lit(mb, "#ff6a4a", 0.06, 0.052, -0.02, 0.025, 0.003, 0.025)


static func _battery(mb: MeshBuilder) -> void:
	_c(mb, "#2a2a2e", 0, 0.05, 0, 0.1, 0.1, 0.16)
	_c(mb, YELLOW, 0, 0.056, 0, 0.102, 0.03, 0.162)
	_c(mb, METAL, 0, 0.11, 0.05, 0.04, 0.02, 0.04)


static func _bulb(mb: MeshBuilder) -> void:
	## a fluorescent tube lying on the floor
	_lit(mb, "#e9f3e0", 0, 0.035, 0, 0.05, 0.05, 0.62)
	_c(mb, METAL, 0, 0.035, 0.32, 0.055, 0.055, 0.03)
	_c(mb, METAL, 0, 0.035, -0.32, 0.055, 0.055, 0.03)


static func _crowbar(mb: MeshBuilder) -> void:
	_c(mb, "#7a2323", 0, 0.025, 0, 0.035, 0.035, 0.6)
	_c(mb, "#7a2323", 0, 0.025, -0.3, 0.035, 0.035, 0.09)
	_c(mb, METAL_DARK, 0.03, 0.025, -0.335, 0.08, 0.03, 0.03)


static func _fuse(mb: MeshBuilder) -> void:
	_c(mb, "#cfc9b2", 0, 0.04, 0, 0.05, 0.05, 0.14)
	_c(mb, METAL, 0, 0.04, 0.08, 0.055, 0.055, 0.03)
	_c(mb, METAL, 0, 0.04, -0.08, 0.055, 0.055, 0.03)


static func _key(mb: MeshBuilder) -> void:
	_c(mb, "#b99a3a", 0, 0.015, 0, 0.03, 0.015, 0.13)
	_c(mb, "#b99a3a", 0, 0.015, -0.08, 0.07, 0.015, 0.07)
	_c(mb, "#b99a3a", 0.02, 0.015, 0.05, 0.04, 0.015, 0.02)


static func _camcorder_prop(mb: MeshBuilder) -> void:
	_c(mb, "#2b2d31", 0, 0.09, 0, 0.1, 0.12, 0.2)
	_c(mb, "#1a1b1e", 0, 0.1, -0.12, 0.07, 0.07, 0.06)
	_lit(mb, "#e03030", 0.03, 0.17, 0.05, 0.02, 0.02, 0.02)


static func _dispenser(mb: MeshBuilder) -> void:
	_c(mb, RED, 0, 1.2, -0.08, 0.28, 0.4, 0.16)
	_c(mb, PAPER, 0, 1.05, -0.17, 0.2, 0.1, 0.02)
	_c(mb, BLACK, 0, 1.25, -0.165, 0.18, 0.03, 0.01)


static func _stanchion(mb: MeshBuilder) -> void:
	_c(mb, METAL, 0, 0.45, 0, 0.05, 0.9, 0.05)
	_c(mb, METAL_DARK, 0, 0.02, 0, 0.3, 0.04, 0.3)
	_c(mb, RED, 0.3, 0.8, 0, 0.55, 0.05, 0.03)


static func _wet_sign(mb: MeshBuilder) -> void:
	_c(mb, YELLOW, 0, 0.3, 0, 0.3, 0.6, 0.04)
	_c(mb, "#e9c530", 0.0, 0.3, -0.03, 0.26, 0.5, 0.01)
	_c(mb, BLACK, 0.0, 0.34, -0.04, 0.1, 0.16, 0.005)


static func _tray(mb: MeshBuilder) -> void:
	_c(mb, METAL, 0, 0.03, 0, 0.42, 0.03, 0.3)
	_c(mb, WHITE, -0.08, 0.075, 0, 0.14, 0.06, 0.14)
	_c(mb, "#d9c8a0", 0.1, 0.06, 0.03, 0.12, 0.03, 0.1)


static func _desk_lamp(mb: MeshBuilder) -> void:
	_c(mb, METAL_DARK, 0, 0.01, 0, 0.14, 0.02, 0.14)
	_c(mb, METAL_DARK, 0, 0.2, 0, 0.02, 0.4, 0.02)
	_lit(mb, "#ffe9a8", 0, 0.42, -0.05, 0.18, 0.05, 0.14)


# --- people-floor props (Queue board, unit doors, the Lobby desk) ---------------------------

static func _queue_board(mb: MeshBuilder) -> void:
	## NOW SERVING: a black panel on a dark frame. The digits are Label3Ds added by QueueBoard.
	_c(mb, METAL_DARK, 0, 1.95, -0.05, 1.7, 0.86, 0.1)
	_c(mb, BLACK, 0, 1.95, -0.105, 1.58, 0.74, 0.01)
	_c(mb, METAL, 0, 1.45, -0.05, 0.06, 0.1, 0.06)


static func _unit_door(mb: MeshBuilder, open: bool) -> void:
	## A decorative residential door set into a wall (z = 0 is the wall plane, the room is -Z). Open: a dark
	## doorway and the leaf swung back against the corridor wall. Shut: the leaf flush. Evidence reads the state.
	_c(mb, "#2a1e14", 0, 1.06, -0.04, 1.0, 2.12, 0.08)             # frame
	if open:
		_c(mb, "#030303", 0, 1.0, -0.085, 0.86, 2.0, 0.01)         # the dark beyond
		_c(mb, "#4a3422", -0.47, 1.0, -0.5, 0.04, 2.0, 0.84)       # leaf swung into the corridor
		_c(mb, METAL, -0.45, 1.0, -0.88, 0.03, 0.04, 0.06)
	else:
		_c(mb, "#4a3422", 0, 1.0, -0.075, 0.86, 2.0, 0.03)         # shut leaf
		_c(mb, "#3a291a", 0, 1.35, -0.093, 0.62, 0.7, 0.005)
		_c(mb, "#3a291a", 0, 0.62, -0.093, 0.62, 0.7, 0.005)
		_c(mb, METAL, 0.33, 1.0, -0.1, 0.04, 0.04, 0.05)
	_c(mb, "#b99a3a", 0, 1.78, -0.095, 0.14, 0.07, 0.006)         # the number plate


static func _exit_door(mb: MeshBuilder) -> void:
	_c(mb, METAL_DARK, 0, 1.2, -0.05, 1.12, 2.4, 0.1)
	_c(mb, "#6f7d6c", 0, 1.0, -0.12, 0.9, 2.0, 0.04)
	_c(mb, METAL, 0.33, 1.0, -0.16, 0.04, 0.12, 0.05)
	_lit(mb, "#4cf08a", 0, 2.28, -0.11, 0.4, 0.14, 0.02)


static func _key_card(mb: MeshBuilder) -> void:
	## the key card on the desk: yours, with your Guest number
	_c(mb, "#1b1b22", 0, 0.012, 0, 0.24, 0.012, 0.15)
	_lit(mb, "#ffd34a", 0.075, 0.021, 0, 0.06, 0.004, 0.15)         # the stripe glows: the one thing on the desk you can find
	_c(mb, WHITE, -0.03, 0.021, 0.035, 0.12, 0.004, 0.045)


# --- text decals ----------------------------------------------------------------------------

static func make_label(text: String, color: Color, size_m: float, bold: bool = true) -> Label3D:
	## Painted text on a surface. Label3D is unshaded, so EvidenceMark tints it by the light field.
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.font = load("res://fonts/LiberationMono-Bold.ttf") if bold else load("res://fonts/LiberationMono-Regular.ttf")
	l.font_size = 48
	l.pixel_size = size_m / 48.0
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.no_depth_test = false
	return l
