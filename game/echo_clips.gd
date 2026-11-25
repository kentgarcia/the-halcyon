class_name EchoClips
extends RefCounted
## The ten Echo clip scripts (SPEC 4.3, 6): for every floor a clip of a previous Guest where the entity rule
## HOLDS (`<entity>_hold`) and one where it is INVERTED (`<entity>_inv`). Fairness Doctrine 1: the footage is
## always the true behaviour of the variant it is filed under, and FloorPlan only places the matching one.
##
## A clip is two pure functions of time: build(id, stage) dresses the set and spawns the actors, tick(id, stage, t)
## poses everything at clip time t (seconds) and sets the camera. Nothing here is random.
##
## Framing rule of thumb (the tape is 128x96): the figure that matters is 4-5 m from the lens, the lens is 42-52
## degrees, and a set is only as big as it needs to be. Local frame (see EchoStage): +X right, +Y up, the camera
## sits at +Z looking toward -Z. GameScale.TILE = 1.25 m.

const FACE_RIGHT := -PI * 0.5           ## yaw that points a figure's front (-Z) along +X
const FACE_LEFT := PI * 0.5             ## ... along -X
const FACE_AWAY := 0.0                  ## ... along -Z (away from the lens)
const FACE_CAM := PI                    ## ... along +Z (at the lens)

## duration in seconds (10 fps); label is what the viewfinder prints under the timecode.
const CLIPS := {
	&"hum_hold": {"dur": 12.0, "floor": &"yellow", "label": "TAPE - 1F - UNDATED"},
	&"hum_inv": {"dur": 12.5, "floor": &"yellow", "label": "TAPE - 1F - UNDATED"},
	&"foreman_hold": {"dur": 12.0, "floor": &"boiler", "label": "TAPE - B3 - UNDATED"},
	&"foreman_inv": {"dur": 12.5, "floor": &"boiler", "label": "TAPE - B3 - UNDATED"},
	&"lifeguard_hold": {"dur": 13.0, "floor": &"natatorium", "label": "TAPE - B2 - UNDATED"},
	&"lifeguard_inv": {"dur": 13.0, "floor": &"natatorium", "label": "TAPE - B2 - UNDATED"},
	&"queue_hold": {"dur": 13.0, "floor": &"blue", "label": "TAPE - B1 - UNDATED"},
	&"queue_inv": {"dur": 13.0, "floor": &"blue", "label": "TAPE - B1 - UNDATED"},
	&"greeter_hold": {"dur": 13.0, "floor": &"units", "label": "TAPE - 2F - UNDATED"},
	&"greeter_inv": {"dur": 13.0, "floor": &"units", "label": "TAPE - 2F - UNDATED"},
}

## seven-segment glyphs for the Queue board
const DIGITS := {
	0: "abcdef", 1: "bc", 2: "abdeg", 3: "abcdg", 4: "bcfg", 5: "acdfg", 6: "acdefg", 7: "abc", 8: "abcdefg", 9: "abcdfg",
}


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in CLIPS:
		out.append(k)
	return out


static func has(id: StringName) -> bool:
	return CLIPS.has(id)


static func duration(id: StringName) -> float:
	return float((CLIPS.get(id, {}) as Dictionary).get("dur", 0.0))


static func label(id: StringName) -> String:
	return String((CLIPS.get(id, {}) as Dictionary).get("label", "TAPE - UNDATED"))


static func floor_of(id: StringName) -> StringName:
	return StringName((CLIPS.get(id, {}) as Dictionary).get("floor", &"yellow"))


static func build(id: StringName, st: EchoStage) -> void:
	match id:
		&"hum_hold": _b_hum(st)
		&"hum_inv": _b_hum(st)
		&"foreman_hold": _b_foreman(st, false)
		&"foreman_inv": _b_foreman(st, true)
		&"lifeguard_hold": _b_lifeguard(st, false)
		&"lifeguard_inv": _b_lifeguard(st, true)
		&"queue_hold": _b_queue(st)
		&"queue_inv": _b_queue(st)
		&"greeter_hold": _b_greeter(st)
		&"greeter_inv": _b_greeter(st)


static func tick(id: StringName, st: EchoStage, t: float) -> void:
	match id:
		&"hum_hold": _t_hum_hold(st, t)
		&"hum_inv": _t_hum_inv(st, t)
		&"foreman_hold": _t_foreman_hold(st, t)
		&"foreman_inv": _t_foreman_inv(st, t)
		&"lifeguard_hold": _t_lifeguard_hold(st, t)
		&"lifeguard_inv": _t_lifeguard_inv(st, t)
		&"queue_hold": _t_queue_hold(st, t)
		&"queue_inv": _t_queue_inv(st, t)
		&"greeter_hold": _t_greeter_hold(st, t)
		&"greeter_inv": _t_greeter_inv(st, t)
	st.flush_light()


# ================================================================================================
# shared helpers
# ================================================================================================

static func _yaw_for(d: Vector3) -> float:
	## Yaw that points a figure's front (-Z) along the horizontal direction d.
	return atan2(-d.x, -d.z)


static func _ceil(st: EchoStage, suffix: String = "") -> StringName:
	return StringName("ceiling_%s%s" % [st.theme.ceiling_size, suffix])


static func _panel(over: Dictionary, cx: float, cz: float, m: StringName) -> void:
	## A 2x2-tile light panel block centred on (cx, cz) (both multiples of TILE).
	var tx := floori(cx / EchoStage.TILE + 0.001)
	var tz := floori(cz / EchoStage.TILE + 0.001)
	for dx in 2:
		for dz in 2:
			over[Vector2i(tx - 1 + dx, tz - 1 + dz)] = m


static func _room(st: EchoStage, x0: float, x1: float, z0: float, z1: float, over: Dictionary = {},
		back_open: Array = [], left_open: Array = [], right_open: Array = []) -> void:
	var th := st.theme
	var floor_mat: StringName = th.floor_variants[0]["mat"]
	var wall_mat: StringName = th.wall_clean[0]
	st.floor_area(floor_mat, x0, z0, x1, z1)
	st.ceiling_area(_ceil(st), x0, z0, x1, z1, over)
	st.wall(wall_mat, Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(0, 0, 1), back_open)
	st.wall(wall_mat, Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3(1, 0, 0), left_open)
	st.wall(wall_mat, Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(-1, 0, 0), right_open)


static func _guest(st: EchoStage, lamp: bool = false) -> EchoStage.Guest:
	var g := st.make_guest(lamp)
	st.actors["g"] = g
	return g


static func _cam(st: EchoStage, pos: Vector3, look: Vector3, fov: float) -> void:
	st.cam_pos = pos
	st.cam_look = look
	st.cam_fov = fov


static func _flash_in(t: float, at: float, dur: float = 0.3) -> bool:
	return t >= at and t < at + dur


static func _bob(t: float, rate: float, h: float) -> float:
	return absf(sin(t * rate)) * h


## The Guest runs (hips pumping, arms swinging).
static func _run_pose(g: EchoStage.Guest, t: float, speed: float) -> void:
	g.pose(0.0, t * 11.0, speed, 0.2 * speed, 0.7, 0.0, 0.0, 0.0)


# ================================================================================================
# THE HUM (1F Yellow): lit cells are safe when it HOLDS; it feeds on lit cells when INVERTED
# ================================================================================================

const HUM_CELL := Vector3(-1.25, 0.0, -2.5)     ## centre of the lit cell: x -2.5..0, z -3.75..-1.25


static func _b_hum(st: EchoStage) -> void:
	st.guest_jacket = "#6a9fd6"
	var over := {}
	var on := _ceil(st, "_light_on")
	var off := _ceil(st, "_light_off")
	for cx in [-6.25, -1.25, 3.75]:
		for cz in [-7.5, -2.5, 2.5]:
			_panel(over, cx, cz, on if (cx == HUM_CELL.x and cz == HUM_CELL.z) else off)
	_room(st, -7.5, 7.5, -10.0, 3.75, over)
	# a low filing cabinet and a water cooler give the dark cells a little furniture to hide in
	st.set_box("#4a4a3c", Vector3(3.4, 0.45, -8.9), Vector3(1.6, 0.9, 0.7))
	st.set_box("#4a4a3c", Vector3(-5.6, 0.45, -8.9), Vector3(1.6, 0.9, 0.7))
	st.set_box("#2e2e26", Vector3(5.6, 0.7, -5.6), Vector3(0.5, 1.4, 0.5))
	st.commit_set()
	st.set_ambient(0.2)
	st.fog_density = 0.01
	_guest(st, false)
	var h := st.silhouette(0, 2.45, 0.42, 0.4)
	h.scale = Vector3(1.5, 1.0, 1.0)
	st.actors["h"] = h


static func _hum_light(st: EchoStage, level: float, fill: Vector3 = Vector3.ZERO) -> void:
	st.clear_light()
	if fill != Vector3.ZERO:
		st.light_disc(fill.x, fill.z, 1.8, 0.2)       # just enough lens-glow to see a Guest crouched in the dark by
	st.light_disc(HUM_CELL.x, HUM_CELL.z, 3.3, 0.26 * level)
	st.light_rect(HUM_CELL.x - 1.25, HUM_CELL.z - 1.25, HUM_CELL.x + 1.25, HUM_CELL.z + 1.25, EchoStage.LIT * level)


static func _t_hum_hold(st: EchoStage, t: float) -> void:
	var g := st.actors["g"] as EchoStage.Guest
	var h := st.actors["h"] as Silhouette
	# the Guest walks into the lit cell and crouches in the middle of it, facing the lens
	var walk := EchoStage.ramp(t, 0.2, 2.6)
	g.position = Vector3(lerpf(-4.8, HUM_CELL.x, walk), 0.0, HUM_CELL.z)
	var moving := 1.0 - EchoStage.ramp(t, 2.3, 2.7)
	g.rotation.y = lerp_angle(FACE_RIGHT, FACE_CAM, EchoStage.smooth(t, 2.6, 3.4))
	var crouch := EchoStage.smooth(t, 3.0, 4.0)
	# a slow glance toward the dark as the Hum draws level
	var glance := EchoStage.smooth(t, 6.2, 7.0) * (1.0 - EchoStage.smooth(t, 9.6, 10.4))
	g.pose(crouch, t * 6.5, 0.5 * moving, 0.03, 0.55, 0.15, 0.06 + sin(t * 2.2) * 0.02, 0.7 * glance)
	# the Hum walks the dark beside the light; it stops at the edge and never steps in
	var hp := EchoStage.path(t, [
		[0.0, Vector3(6.4, 0, -2.6)], [2.4, Vector3(6.4, 0, -2.6)], [8.2, Vector3(0.6, 0, -2.6)],
		[9.8, Vector3(0.6, 0, -2.6)], [12.0, Vector3(3.4, 0, -5.4)]])
	h.position = hp + Vector3(0, _bob(t, 2.3, 0.04) * (1.0 if (t < 8.0 or t > 9.8) else 0.0), 0)
	h.rotation.z = sin(t * 1.3) * 0.03
	st.face_camera(h)
	h.set_presence(1.0, true)
	# the cell hums: its light dips and recovers as the Hum comes level
	var dip := 0.0
	if t > 7.6 and t < 10.2:
		dip = 0.3 * (0.5 + 0.5 * sin(t * 21.0))
	_hum_light(st, 1.0 - dip)
	_cam(st, EchoStage.path(t, [[0.0, Vector3(-0.2, 1.35, 1.9)], [12.0, Vector3(-0.3, 1.3, 1.6)]]), Vector3(-0.4, 0.95, -2.5), 48.0)


static func _t_hum_inv(st: EchoStage, t: float) -> void:
	var g := st.actors["g"] as EchoStage.Guest
	var h := st.actors["h"] as Silhouette
	# the Guest slips into the dark cell on the right, lamp off, and crouches facing the lens
	var gx := 2.6
	var walk := EchoStage.ramp(t, 0.2, 2.6)
	g.position = Vector3(lerpf(6.4, gx, walk), 0.0, -1.7)
	var moving := 1.0 - EchoStage.ramp(t, 2.3, 2.7)
	g.rotation.y = lerp_angle(FACE_LEFT, FACE_CAM, EchoStage.smooth(t, 2.6, 3.4))
	var crouch := EchoStage.smooth(t, 3.0, 4.0)
	var glance := EchoStage.smooth(t, 6.0, 7.0)
	g.pose(crouch, t * 6.5, 0.5 * moving, 0.03, 0.55, 0.15, 0.06 + sin(t * 2.0) * 0.02, -0.7 * glance)
	# the Hum circles the lit cell, round and round, and never looks the Guest's way
	var ang := PI + 0.6 * maxf(0.0, t - 2.4)
	var r := 1.75
	h.position = HUM_CELL + Vector3(cos(ang) * r, _bob(t, 2.3, 0.04), sin(ang) * r)
	h.visible = t > 2.2
	h.set_presence(1.0, true)
	st.face_camera(h)
	# the lit cell swells a little each time the Hum passes in front of it
	var surge := 0.15 * maxf(0.0, sin(ang))
	_hum_light(st, 1.0 + surge, g.position)
	_cam(st, EchoStage.path(t, [[0.0, Vector3(0.7, 1.4, 3.5)], [12.5, Vector3(0.5, 1.35, 3.2)]]), Vector3(0.6, 0.85, -2.3), 50.0)


# ================================================================================================
# THE FOREMAN (B3 Boiler): the alarm calls him to its source (HOLDS) or to the exit you run for (INVERTED)
# ================================================================================================

const BOILER_Z0 := -5.0                         ## the back wall; the fire door is x 1.25 .. 2.5 in it


static func _b_foreman(st: EchoStage, inverted: bool) -> void:
	st.guest_jacket = "#c4663c"
	var over := {}
	var on := _ceil(st, "_light_on")
	var off := _ceil(st, "_light_off")
	for cx in [-3.75, 0.0, 3.75]:
		for cz in [-2.5, 1.25]:
			_panel(over, cx, cz, on if (cx == 0.0 and cz == -2.5) else off)
	_room(st, -5.0, 5.0, BOILER_Z0, 3.75, over, [5])
	# the stairwell behind the fire door: a short landing, dark sides, a pale lit back wall
	var floor_mat: StringName = st.theme.floor_variants[0]["mat"]
	st.floor_area(floor_mat, 1.25, BOILER_Z0 - 1.5, 2.5, BOILER_Z0)
	st.set_box("#14181a", Vector3(1.21, 1.25, BOILER_Z0 - 0.75), Vector3(0.08, 2.5, 1.5))
	st.set_box("#14181a", Vector3(2.54, 1.25, BOILER_Z0 - 0.75), Vector3(0.08, 2.5, 1.5))
	st.set_box("#14181a", Vector3(1.875, 2.54, BOILER_Z0 - 0.75), Vector3(1.4, 0.08, 1.5))
	# pipes along the back wall, a boiler tank on the left for scale
	st.set_box("#5a4a42", Vector3(-1.4, 2.15, BOILER_Z0 + 0.14), Vector3(7.4, 0.24, 0.24))
	st.set_box("#3d3d3f", Vector3(-1.4, 1.7, BOILER_Z0 + 0.12), Vector3(7.4, 0.14, 0.14))
	for px in [-4.4, -0.6, 4.4]:
		st.set_box("#5a4a42", Vector3(px, 1.25, BOILER_Z0 + 0.14), Vector3(0.2, 2.5, 0.2))
	st.set_box("#3e464a", Vector3(-3.9, 1.0, -3.6), Vector3(1.3, 2.0, 1.3))
	st.set_box("#2a3033", Vector3(-3.9, 2.03, -3.6), Vector3(1.4, 0.08, 1.4))
	st.set_box("#a8331f", Vector3(-3.9, 1.3, -2.93), Vector3(0.3, 0.3, 0.05))
	st.commit_set()
	st.set_ambient(0.2)
	st.fog_density = 0.008
	# the stairwell's lit back wall and the EXIT sign over the door
	st.glow(Vector3(1.875, 1.2, BOILER_Z0 - 1.5), Vector3(1.1, 2.4, 0.04), "#789078", "Stairwell")
	st.glow(Vector3(1.875, 2.32, BOILER_Z0 + 0.06), Vector3(0.7, 0.2, 0.04), "#2f9a52", "ExitSign")
	# the alarm bell and its lamp, high on the wall
	var bell := st.prop(st.root, [
		["#e0382a", 0, 0, 0, 0.46, 0.34, 0.24],
		["#a82418", 0, -0.2, 0, 0.2, 0.08, 0.18],
		["#262626", 0, 0.2, 0, 0.08, 0.12, 0.08],
	], "Bell")
	bell.position = Vector3(-2.2, 2.0, BOILER_Z0 + 0.22)
	st.actors["bell"] = bell
	st.actors["lamp"] = st.glow(Vector3(-1.5, 2.0, BOILER_Z0 + 0.1), Vector3(0.24, 0.24, 0.06), "#c03020", "BellLamp")
	# the fire door itself, hinged at its left jamb, swinging out into the stairwell
	var door := st.door_leaf(Vector3(1.25, 0.0, BOILER_Z0), 0.0, "#7a2e24", "FireDoor")
	door.scale = Vector3(EchoStage.TILE / EchoStage.DOOR_LEAF_W, 1.0, 1.0)
	st.actors["door"] = door
	_guest(st, false)
	var f := st.silhouette(1, 2.4, 0.5, 0.0 if inverted else 0.5, Color(0.03, 0.03, 0.03))
	f.scale = Vector3(1.3, 1.0, 1.0)
	st.actors["f"] = f


static func _boiler_light(st: EchoStage, door_open: float) -> void:
	st.clear_light()
	st.light_rect(-4.6, -4.7, 4.6, 0.8, 0.26)
	st.light_rect(-1.25, -4.6, 1.25, -1.25, 0.5)
	st.light_disc(1.9, BOILER_Z0 + 0.6, 2.0, 0.55 * door_open)


static func _alarm(st: EchoStage, t: float) -> void:
	var bell := st.actors["bell"] as Node3D
	bell.rotation.z = sin(t * 33.0) * 0.3 if t > 0.3 else 0.0
	(st.actors["lamp"] as Node3D).visible = t > 0.3 and (int(t * 5.0) % 2) == 0


static func _boiler_cam(st: EchoStage, t: float, dur: float) -> void:
	_cam(st, EchoStage.path(t, [[0.0, Vector3(0.3, 1.55, 0.6)], [dur, Vector3(0.1, 1.5, 0.2)]]), Vector3(0.0, 1.05, -3.8), 54.0)


static func _t_foreman_hold(st: EchoStage, t: float) -> void:
	var g := st.actors["g"] as EchoStage.Guest
	var f := st.actors["f"] as Silhouette
	var door := st.actors["door"] as Node3D
	_alarm(st, t)
	# the Guest bolts across the back for the fire door and goes through it
	var gp := EchoStage.path(t, [[1.0, Vector3(-3.3, 0, -4.1)], [2.9, Vector3(1.6, 0, -4.2)], [3.5, Vector3(1.875, 0, -5.4)], [4.2, Vector3(1.875, 0, -6.2)]])
	g.position = gp
	g.visible = t > 1.0 and t < 4.3
	g.rotation.y = FACE_RIGHT if t < 3.0 else lerp_angle(FACE_RIGHT, FACE_AWAY, EchoStage.smooth(t, 3.0, 3.4))
	_run_pose(g, t, 1.0)
	var open := EchoStage.smooth(t, 2.0, 2.5) * (1.0 - EchoStage.smooth(t, 4.6, 5.3))
	door.rotation.y = open * 1.75
	_boiler_light(st, open)
	# the Foreman is in the room; the bell is what he turns to (the wrench changes hands as he turns)
	var turn := EchoStage.ramp(t, 1.6, 2.3)
	var walk := EchoStage.ramp(t, 2.3, 9.0)
	f.position = Vector3(-0.5, 0, -3.1).lerp(Vector3(-2.2, 0, -4.3), walk)
	f.position.y = _bob(t, 3.2, 0.04) * (1.0 if (walk > 0.0 and walk < 1.0) else 0.0)
	f.scale = Vector3(1.3 * cos(PI * turn), 1.0, 1.0)
	st.face_camera(f)
	_boiler_cam(st, t, 12.0)


static func _t_foreman_inv(st: EchoStage, t: float) -> void:
	var g := st.actors["g"] as EchoStage.Guest
	var f := st.actors["f"] as Silhouette
	var door := st.actors["door"] as Node3D
	_alarm(st, t)
	# the Guest runs for the exit, sees the door swing, and stops dead
	var gp: Vector3
	var speed := 1.0
	if t < 3.6:
		gp = EchoStage.path(t, [[1.0, Vector3(-3.3, 0, -4.1)], [3.6, Vector3(0.2, 0, -4.1)]])
		g.rotation.y = FACE_RIGHT
		speed = 1.0 - EchoStage.ramp(t, 3.1, 3.7)
	elif t < 5.2:
		gp = Vector3(0.2, 0, -4.1)
		g.rotation.y = FACE_RIGHT
		speed = 0.0
	else:
		# they back off, turn, and run the way they came
		gp = Vector3(0.2, 0, -4.1).lerp(Vector3(-4.8, 0, -3.8), EchoStage.ramp(t, 5.6, 8.4))
		g.rotation.y = lerp_angle(FACE_RIGHT, FACE_LEFT, EchoStage.smooth(t, 5.1, 5.6))
		speed = EchoStage.ramp(t, 5.2, 5.8)
	g.position = gp
	g.visible = t > 1.0 and gp.x > -4.7
	if speed > 0.01:
		_run_pose(g, t, speed)
	else:
		g.pose(0.0, 0.0, 0.0, 0.0, 0.5, 0.2, 0.0, 0.4 * EchoStage.ramp(t, 3.8, 4.2))
	# the door is thrown open from inside, and something is already standing there
	var open := EchoStage.smooth(t, 2.4, 2.9)
	door.rotation.y = open * 1.75
	_boiler_light(st, open)
	var fp := Vector3(1.9, 0, BOILER_Z0 - 0.55)
	if t > 8.0:
		fp = fp.lerp(Vector3(1.5, 0, -2.6), EchoStage.smooth(t, 8.0, 12.2))
	f.position = fp
	f.visible = true
	# in the doorway he stands a hand shorter than the lintel; stepping out he is his full height
	f.scale = Vector3(1.3, lerpf(0.84, 1.0, EchoStage.smooth(t, 8.0, 9.5)), 1.0)
	f.set_presence(1.0, true)
	st.face_camera(f)
	_boiler_cam(st, t, 12.5)


# ================================================================================================
# THE LIFEGUARD (B2 Natatorium): a whistle freezes the Guest; a second lets them go (HOLDS) or the chair is empty (INVERTED)
# ================================================================================================

const POOL_Z0 := -3.75                          ## far lip of the basin
const POOL_Z1 := -1.25                          ## near lip
const CHAIR := Vector3(1.0, 0.0, -4.1)
const DECK_Z := 0.3                             ## the line the Guest walks along
const PRINTS := 6                              ## wet footprints on the deck
const STOP_X := -0.2                             ## where the whistle catches them


static func _b_lifeguard(st: EchoStage, inverted: bool) -> void:
	st.guest_jacket = "#c4562e"
	var over := {}
	var on := _ceil(st, "_light_on")
	for cx in [-3.75, 1.25, 3.75]:
		for cz in [-5.0, 0.0, 3.75]:
			_panel(over, cx, cz, on)
	var floor_mat: StringName = st.theme.floor_variants[0]["mat"]
	var wall_mat: StringName = st.theme.wall_clean[0]
	var x0 := -5.0
	var x1 := 5.0
	var z0 := -6.25
	var z1 := 6.25
	st.floor_area(floor_mat, x0, POOL_Z1, x1, z1)
	st.floor_area(floor_mat, x0, z0, x1, POOL_Z0)
	st.floor_area(&"pool_water", x0, POOL_Z0, x1, POOL_Z1, -0.14)
	st.ceiling_area(_ceil(st), x0, z0, x1, z1, over)
	st.wall(wall_mat, Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(0, 0, 1))
	st.wall(wall_mat, Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3(1, 0, 0))
	st.wall(wall_mat, Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(-1, 0, 0))
	# pool lips (a pale coping) and the basin's inner walls
	st.set_box("#c9d6d8", Vector3(0, 0.01, POOL_Z1 + 0.06), Vector3(10.0, 0.04, 0.14))
	st.set_box("#c9d6d8", Vector3(0, 0.01, POOL_Z0 - 0.06), Vector3(10.0, 0.04, 0.14))
	st.set_box("#5b7478", Vector3(0, -0.07, POOL_Z1 + 0.01), Vector3(10.0, 0.14, 0.02))
	st.set_box("#5b7478", Vector3(0, -0.07, POOL_Z0 - 0.01), Vector3(10.0, 0.14, 0.02))
	# a pair of lane-rope floats and a depth sign on the far wall break up the flat tile
	st.set_box("#2a5a6e", Vector3(0, 1.3, z0 + 0.03), Vector3(10.0, 0.25, 0.04))
	st.commit_set()
	st.set_ambient(0.22)
	st.fog_density = 0.008
	var water := st.mat(&"pool_water") as ShaderMaterial
	water.set_shader_parameter("uv_scroll", Vector2.ZERO)
	# ripple lines on the water (calm and slow when it HOLDS; they travel toward the Guest when INVERTED)
	var ripples: Array[Node3D] = []
	for i in 9:
		ripples.append(st.prop(st.root, [["*#7fa6a9", 0, -0.13, 0, 0.9, 0.01, 0.04]], "Ripple"))
	st.actors["ripples"] = ripples
	# the lifeguard's high chair across the basin: the real entity silhouette, drawn a little over life size so it
	# survives 128x96. Occupied when the rule HOLDS; the same chair, empty, when it is INVERTED.
	var lg := st.silhouette(2, 3.3, 0.5, 0.0, Color(0.03, 0.035, 0.04))
	lg.scale = Vector3(1.4, 1.0, 1.0)
	lg.mat.set_shader_parameter("occupied", 0.0 if inverted else 1.0)
	lg.position = CHAIR
	st.actors["lg"] = lg
	st.actors["whistle"] = st.glow(CHAIR + Vector3(0.0, 2.2, 0.12), Vector3(0.42, 0.42, 0.06), "#ffffff", "Whistle")
	_guest(st, false)
	if inverted:
		var prints: Array[Node3D] = []
		for i in PRINTS:
			var pr := st.prop(st.root, [
				["#1c3b45", 0.0, 0.012, 0.0, 0.18, 0.012, 0.26],
				["#1c3b45", 0.0, 0.012, 0.22, 0.11, 0.012, 0.12],
			], "Print")
			pr.visible = false
			prints.append(pr)
		st.actors["prints"] = prints


static func _pool_light(st: EchoStage) -> void:
	st.clear_light()
	st.light_rect(-5.0, -6.25, 5.0, 6.25, 0.3)
	st.light_rect(-5.0, POOL_Z0, 5.0, POOL_Z1, 0.42)


static func _ripples(st: EchoStage, t: float, toward: bool) -> void:
	var rs: Array = st.actors["ripples"]
	for i in rs.size():
		var rp := rs[i] as Node3D
		var k := float(i) / float(rs.size())
		var x := -4.2 + float(i) * 1.05
		if toward:
			# bands of ripple running from the far lip toward the near lip, converging on the Guest
			var phase := fposmod(t * 0.3 + k, 1.0)
			rp.position = Vector3(lerpf(x, STOP_X + 0.4, phase * 0.7), 0.0, lerpf(POOL_Z0 + 0.1, POOL_Z1 - 0.1, phase))
			rp.visible = phase > 0.03 and phase < 0.97
		else:
			rp.position = Vector3(x + sin(t * 0.5 + float(i) * 1.7) * 0.2, 0.0, lerpf(POOL_Z0 + 0.2, POOL_Z1 - 0.2, k) + sin(t * 0.7 + float(i)) * 0.05)
			rp.visible = true


static func _whistle(st: EchoStage, t: float, at: Array) -> bool:
	var on := false
	for a in at:
		if _flash_in(t, float(a), 0.6):
			on = true
	(st.actors["whistle"] as Node3D).visible = on
	return on


static func _lifeguard_cam(st: EchoStage, t: float) -> void:
	_cam(st, EchoStage.path(t, [[0.0, Vector3(0.3, 1.9, 3.9)], [13.0, Vector3(0.5, 1.85, 3.6)]]), Vector3(0.4, 1.0, -2.0), 42.0)


static func _t_lifeguard_hold(st: EchoStage, t: float) -> void:
	var g := st.actors["g"] as EchoStage.Guest
	var lg := st.actors["lg"] as Silhouette
	_pool_light(st)
	_ripples(st, t, false)
	var blast := _whistle(st, t, [3.4, 9.2])
	# the Guest walks the deck, stops dead on the whistle (head snapping to the chair), and walks on at the second one
	var x := STOP_X
	var stopped := false
	if t < 3.4:
		x = STOP_X - 0.8 * (3.4 - t)
	elif t < 9.5:
		stopped = true
	else:
		x = STOP_X + 0.8 * (t - 9.5)
	g.position = Vector3(x, 0.0, DECK_Z)
	g.rotation.y = FACE_RIGHT
	var gait_t := t if t < 3.4 else (3.4 if t < 9.5 else 3.4 + (t - 9.5))
	var frozen := EchoStage.ramp(t, 3.4, 3.55) * (1.0 - EchoStage.ramp(t, 9.5, 9.7))
	g.pose(0.0, gait_t * 6.5, 0.5 * (0.0 if stopped else 1.0), 0.0, 0.4 - 0.35 * frozen, 0.0, 0.0, 0.85 * frozen)
	# the guard scans the water, slowly; the whistle is a white flash at their mouth
	lg.position = CHAIR + Vector3(sin(t * 0.8) * 0.04, 0.0, 0.0)
	lg.rotation.z = sin(t * 0.8) * 0.015
	lg.mat.set_shader_parameter("flash", 0.55 if blast else 0.0)
	st.face_camera(lg)
	_lifeguard_cam(st, t)


static func _t_lifeguard_inv(st: EchoStage, t: float) -> void:
	var g := st.actors["g"] as EchoStage.Guest
	var prints: Array = st.actors["prints"]
	_pool_light(st)
	_ripples(st, t, true)
	var blast := _whistle(st, t, [3.4])
	# the same walk, the same whistle, the same dead stop...
	var x := STOP_X - 0.8 * maxf(0.0, 3.4 - t)
	g.position = Vector3(x, 0.0, DECK_Z)
	g.rotation.y = FACE_RIGHT
	var frozen := EchoStage.ramp(t, 3.4, 3.55)
	# ...but nobody is in the chair. The Guest looks to it, then at the pool, then down at their feet
	var look := 0.85 * (1.0 - EchoStage.smooth(t, 5.0, 6.0))
	look += (0.5 * EchoStage.smooth(t, 6.4, 7.4)) * (1.0 - EchoStage.smooth(t, 9.5, 10.5))
	g.pose(0.0, minf(t, 3.4) * 6.5, 0.5 * (0.0 if t >= 3.4 else 1.0), 0.0, 0.4 - 0.35 * frozen, 0.0,
		0.5 * EchoStage.smooth(t, 9.5, 10.5), look * frozen)
	var lg := st.actors["lg"] as Silhouette
	lg.position = CHAIR
	st.face_camera(lg)
	# wet footprints come out of the water and cross the deck to the Guest's feet, one by one
	var lip_x := 1.9
	var n := prints.size()
	for i in n:
		var pr := prints[i] as Node3D
		var k := float(i) / float(n - 1)
		pr.visible = t >= 4.9 + 1.0 * float(i)
		var side := 0.13 if (i % 2) == 0 else -0.13
		var p := Vector3(lerpf(lip_x, STOP_X + 0.55, k) + side, 0.0, lerpf(POOL_Z1 + 0.15, DECK_Z - 0.1, k))
		pr.position = p
		var d := Vector3(STOP_X + 0.55 - lip_x, 0.0, DECK_Z - 0.1 - POOL_Z1 - 0.15)
		pr.rotation.y = _yaw_for(d)
	_lifeguard_cam(st, t)


# ================================================================================================
# THE QUEUE (B1 Blue Annex): called to the window (HOLDS) or the line steps toward you at each count (INVERTED)
# ================================================================================================

const QUEUE_Z0 := -6.25                         ## the board wall
const QUEUE_GUEST_Z := 0.0
const QUEUE_LINE_Z := [-1.9, -3.1, -4.3]
const QUEUE_LINE_X := [0.45, -0.1, 0.5]
const WINDOW_Z := -0.625                        ## the window door: right wall, z -1.25 .. 0.0


static func _seg_digit(st: EchoStage, parent: Node3D, d: int, x: float, color: String) -> void:
	var segs: String = DIGITS[d]
	var parts: Array = []
	var hw := 0.22                                # half the digit width (bar length 0.30)
	var hh := 0.42                                # half the digit height
	var th := 0.085
	var hb := Vector3(0.34, th, 0.03)
	var vb := Vector3(th, 0.38, 0.03)
	var layout := {
		"a": [0.0, hh, hb], "g": [0.0, 0.0, hb], "d": [0.0, -hh, hb],
		"f": [-hw, hh * 0.5, vb], "b": [hw, hh * 0.5, vb], "e": [-hw, -hh * 0.5, vb], "c": [hw, -hh * 0.5, vb],
	}
	for s in segs:
		var l: Array = layout[s]
		var sz: Vector3 = l[2]
		parts.append([color, x + float(l[0]), float(l[1]), 0.0, sz.x, sz.y, sz.z])
	st.prop(parent, parts, "Digit")


static func _board_values(st: EchoStage, values: Array) -> Dictionary:
	## One two-digit readout node per value; the clip shows the one it wants.
	var out := {}
	var board := st.actors["board"] as Node3D
	for v in values:
		var holder := Node3D.new()
		holder.name = "Readout%d" % int(v)
		board.add_child(holder)
		holder.visible = false
		_seg_digit(st, holder, int(v) / 10, -0.34, "*#d4701c")
		_seg_digit(st, holder, int(v) % 10, 0.34, "*#d4701c")
		out[int(v)] = holder
	return out


static func _b_queue(st: EchoStage) -> void:
	st.guest_jacket = "#d8d2b8"
	var over := {}
	var on := _ceil(st, "_light_on")
	var off := _ceil(st, "_light_off")
	for cz in [-3.75, 1.25]:
		_panel(over, 0.0, cz, on if cz == -3.75 else off)
	# corridor x -2.5 .. 2.5, board wall at z = -6.25; the window door is tile 5 of the right wall (z -1.25 .. 0.0)
	_room(st, -2.5, 2.5, QUEUE_Z0, 3.75, over, [], [], [5])
	# the room behind the window door
	var floor_mat: StringName = st.theme.floor_variants[0]["mat"]
	st.floor_area(floor_mat, 2.5, -1.25, 4.5, 0.0)
	st.set_box("#14181c", Vector3(3.5, 1.25, -1.3), Vector3(2.0, 2.5, 0.06))
	st.set_box("#14181c", Vector3(3.5, 1.25, 0.05), Vector3(2.0, 2.5, 0.06))
	st.set_box("#14181c", Vector3(4.55, 1.25, WINDOW_Z), Vector3(0.06, 2.5, 1.3))
	# a plain board panel and a rail the line shuffles along
	st.set_box("#0c0e10", Vector3(0.0, 1.95, QUEUE_Z0 + 0.04), Vector3(2.7, 1.05, 0.08))
	st.commit_set()
	st.set_ambient(0.2)
	st.fog_density = 0.01
	var board := Node3D.new()
	board.name = "Board"
	st.root.add_child(board)
	board.position = Vector3(0.0, 1.95, QUEUE_Z0 + 0.1)
	st.actors["board"] = board
	st.actors["readouts"] = _board_values(st, [12, 13, 14, 15])
	st.actors["window_glow"] = st.glow(Vector3(4.2, 1.1, WINDOW_Z), Vector3(0.05, 2.2, 1.2), "#c9a870", "WindowRoom")
	var door := st.door_leaf(Vector3(2.5, 0.0, WINDOW_Z - 0.625), FACE_RIGHT, "#4a3a2a", "WindowDoor")
	door.scale = Vector3(EchoStage.TILE / EchoStage.DOOR_LEAF_W, 1.0, 1.0)
	door.rotation.y = FACE_LEFT
	st.actors["door"] = door
	# the line, facing the board
	var line: Array[Silhouette] = []
	for i in 3:
		var s := st.silhouette(3, 2.05, 0.42, 0.55, Color(0.03, 0.035, 0.05))
		s.scale = Vector3(1.35, 1.0, 1.0)
		line.append(s)
	st.actors["line"] = line
	var g := _guest(st, false)
	# the ticket in the Guest's left hand
	st.part(g.arm_l, "#f4eed2", Vector3(0.0, -0.58, -0.1), Vector3(0.11, 0.15, 0.02), "Ticket")


static func _queue_light(st: EchoStage, board: float, window: float) -> void:
	st.clear_light()
	st.light_rect(-2.5, QUEUE_Z0, 2.5, -2.6, 0.34)
	st.light_rect(-2.5, -2.6, 2.5, 3.75, 0.22)
	st.light_rect(-1.5, QUEUE_Z0, 1.5, QUEUE_Z0 + 1.6, 0.5 * board)
	st.light_disc(2.3, WINDOW_Z, 1.9, 0.55 * window)


static func _readout(st: EchoStage, value: int, blank: bool) -> void:
	var ro: Dictionary = st.actors["readouts"]
	for k in ro:
		(ro[k] as Node3D).visible = (k == value) and not blank


static func _queue_cam(st: EchoStage, t: float, dur: float) -> void:
	_cam(st, EchoStage.path(t, [[0.0, Vector3(-1.75, 1.6, 3.2)], [dur, Vector3(-1.6, 1.6, 3.0)]]), Vector3(0.35, 1.2, -3.2), 50.0)


static func _t_queue_hold(st: EchoStage, t: float) -> void:
	var g := st.actors["g"] as EchoStage.Guest
	var line: Array = st.actors["line"]
	var door := st.actors["door"] as Node3D
	# the board counts 12 -> 13 -> 14 ...
	var count := 12
	var blank := false
	if t >= 3.4:
		count = 13
	if t >= 6.8:
		count = 14
	for at in [3.4, 6.8]:
		if t >= at and t < at + 0.35:
			blank = ((int(t * 20.0) % 2) == 0)
	_readout(st, count, blank)
	# ... and the window door opens for 14
	var wopen := EchoStage.smooth(t, 7.6, 8.2) * (1.0 - EchoStage.smooth(t, 11.8, 12.4))
	door.rotation.y = FACE_LEFT + wopen * 1.55
	(st.actors["window_glow"] as Node3D).visible = wopen > 0.05
	_queue_light(st, 1.0, wopen)
	# the line never moves a hair
	for i in line.size():
		var s := line[i] as Silhouette
		s.position = Vector3(QUEUE_LINE_X[i], 0.0, QUEUE_LINE_Z[i])
		st.face_camera(s)
	# the Guest waits holding up the ticket, is called, and steps out of the line to the window
	var gx := 0.0
	var gz := QUEUE_GUEST_Z
	var face := FACE_AWAY
	var moving := 0.0
	var walk := EchoStage.ramp(t, 8.6, 10.6)
	if t > 8.4:
		gx = lerpf(0.0, 2.7, walk)
		gz = lerpf(QUEUE_GUEST_Z, WINDOW_Z, walk)
		face = lerp_angle(FACE_AWAY, FACE_RIGHT, EchoStage.smooth(t, 8.4, 9.0))
		moving = 1.0 if (walk > 0.0 and walk < 1.0) else 0.0
	g.position = Vector3(gx, 0.0, gz)
	g.rotation.y = face
	g.visible = t < 11.0
	g.pose(0.0, t * 6.5, 0.5 * moving, 0.0, 0.4, 1.0, 0.04 * sin(t * 1.6), 0.0)
	_queue_cam(st, t, 13.0)


static func _t_queue_inv(st: EchoStage, t: float) -> void:
	var g := st.actors["g"] as EchoStage.Guest
	var line: Array = st.actors["line"]
	var door := st.actors["door"] as Node3D
	var count := 12
	var blank := false
	var steps := 0.0
	var back := 0.0
	for at in [3.0, 6.0, 9.0]:
		if t >= at:
			count += 1
		if t >= at and t < at + 0.35:
			blank = ((int(t * 20.0) % 2) == 0)
		# the whole line is a step closer, and nobody saw it move
		steps += 0.5 * EchoStage.smooth(t, float(at) + 0.15, float(at) + 0.45)
		back += 0.15 * EchoStage.smooth(t, float(at) + 0.6, float(at) + 1.1)
	_readout(st, count, blank)
	door.rotation.y = FACE_LEFT
	(st.actors["window_glow"] as Node3D).visible = false
	_queue_light(st, 1.0, 0.0)
	for i in line.size():
		var s := line[i] as Silhouette
		s.position = Vector3(QUEUE_LINE_X[i], 0.0, QUEUE_LINE_Z[i] + steps)
		st.face_camera(s)
	# the Guest gives ground a little each time and keeps holding the ticket out
	g.position = Vector3(0.0, 0.0, QUEUE_GUEST_Z + back)
	g.rotation.y = FACE_AWAY
	g.pose(0.0, -t * 6.5, 0.0, 0.0, 0.4, 1.0, 0.04 * sin(t * 1.6), 0.0)
	_queue_cam(st, t, 13.0)


# ================================================================================================
# THE GREETER (2F Units): a bellhop opens a door and leaves (HOLDS) or walks you into a room (INVERTED)
# ================================================================================================

const HALL_DOOR_Z := -3.125                     ## the left-wall door: tile 3, z -3.75 .. -2.5
const HALL_X0 := -2.5
const GX := 0.7                                ## the Guest's line down the corridor (left of the bellhop)


static func _b_greeter(st: EchoStage) -> void:
	st.guest_jacket = "#5f9fd0"
	var over := {}
	var on := _ceil(st, "_light_on")
	var off := _ceil(st, "_light_off")
	for cz in [-5.0, 0.0]:
		_panel(over, 0.0, cz, on if cz == -5.0 else off)
	# corridor x -2.5 .. 2.5, z -7.5 .. 3.75; a door in the left wall (tile 3) and two shut ones on the right
	_room(st, HALL_X0, 2.5, -7.5, 3.75, over, [], [3], [])
	var floor_mat: StringName = st.theme.floor_variants[0]["mat"]
	st.floor_area(floor_mat, HALL_X0 - 2.0, -3.75, HALL_X0, -2.5)
	st.set_box("#14110e", Vector3(HALL_X0 - 1.0, 1.25, -3.8), Vector3(2.0, 2.5, 0.06))
	st.set_box("#14110e", Vector3(HALL_X0 - 1.0, 1.25, -2.45), Vector3(2.0, 2.5, 0.06))
	st.set_box("#14110e", Vector3(HALL_X0 - 2.05, 1.25, HALL_DOOR_Z), Vector3(0.06, 2.5, 1.3))
	st.commit_set()
	st.set_ambient(0.2)
	st.fog_density = 0.01
	st.frame_box(Vector3(HALL_X0, 0, HALL_DOOR_Z), FACE_RIGHT)
	# the door leaf is hinged at the near jamb and opens into the room
	var door := st.door_leaf(Vector3(HALL_X0 + 0.04, 0.0, HALL_DOOR_Z + 0.625), FACE_LEFT, "#6a4528", "Door")
	door.scale = Vector3(EchoStage.TILE / EchoStage.DOOR_LEAF_W, 1.0, 1.0)
	st.actors["door"] = door
	st.actors["room_glow"] = st.glow(Vector3(HALL_X0 - 1.95, 1.1, HALL_DOOR_Z), Vector3(0.05, 2.2, 1.2), "#c8944c", "RoomGlow")
	# the two doors on the right wall stay shut
	for k in [2, 5]:
		var rz := -7.5 + (float(k) + 0.5) * EchoStage.TILE
		st.frame_box(Vector3(2.5, 0, rz), FACE_LEFT)
		var rd := st.door_leaf(Vector3(2.46, 0.0, rz + 0.625), FACE_LEFT, "#4e3520", "ShutDoor")
		rd.scale = Vector3(EchoStage.TILE / EchoStage.DOOR_LEAF_W, 1.0, 1.0)
		rd.rotation.y = FACE_LEFT
	# the bellhop: red tunic, one fixed painted smile
	var b := st.silhouette(4, 2.15, 0.45, 0.1, Color(0.06, 0.04, 0.04))
	b.mat.set_shader_parameter("accent_color", Color(0.52, 0.1, 0.09))
	b.scale = Vector3(1.3, 1.0, 1.0)
	st.actors["b"] = b
	_guest(st, false)
	st.actors["ding"] = st.glow(Vector3(0.7, 1.1, -3.6), Vector3(0.14, 0.14, 0.05), "#a89a70", "Ding")


static func _greeter_light(st: EchoStage, room: float) -> void:
	st.clear_light()
	st.light_rect(-2.5, -7.5, 2.5, -2.2, 0.36)
	st.light_rect(-2.5, -2.2, 2.5, 3.75, 0.2)
	st.light_disc(HALL_X0 - 0.4, HALL_DOOR_Z, 2.0, 0.55 * room)


static func _greeter_cam(st: EchoStage, t: float) -> void:
	_cam(st, EchoStage.path(t, [[0.0, Vector3(0.6, 1.6, 3.5)], [13.0, Vector3(0.3, 1.55, 3.1)]]), Vector3(-0.3, 1.15, -3.0), 50.0)


static func _t_greeter_hold(st: EchoStage, t: float) -> void:
	var g := st.actors["g"] as EchoStage.Guest
	var b := st.actors["b"] as Silhouette
	var door := st.actors["door"] as Node3D
	var ding := st.actors["ding"] as Node3D
	ding.visible = _flash_in(t, 3.0, 0.3)
	# the Guest walks toward the bellhop, stops, and answers (a raised hand, a nod)
	var walk := EchoStage.ramp(t, 0.0, 3.0)
	g.position = Vector3(GX, 0.0, lerpf(1.6, -0.5, walk))
	g.rotation.y = FACE_AWAY
	var moving := 1.0 - EchoStage.ramp(t, 2.7, 3.1)
	var answer := EchoStage.smooth(t, 3.5, 4.1) * (1.0 - EchoStage.smooth(t, 5.4, 6.0))
	g.pose(0.0, t * 6.5, 0.5 * moving, 0.0, 0.4 + 1.2 * answer, 0.0, 0.18 * answer * (0.5 + 0.5 * sin(t * 8.0)), 0.0)
	# the bellhop nods, walks to the left door, opens it, and stands by it
	var bp := EchoStage.path(t, [[0.0, Vector3(-0.5, 0, -2.6)], [5.6, Vector3(-0.5, 0, -2.6)], [7.2, Vector3(-1.6, 0, HALL_DOOR_Z - 0.1)],
		[13.0, Vector3(-1.6, 0, HALL_DOOR_Z - 0.1)]])
	var strolling := t > 5.6 and t < 7.2
	b.position = bp + Vector3(0, _bob(t, 3.4, 0.04) * (1.0 if strolling else 0.0), 0)
	b.scale = Vector3(1.3, 1.0 - 0.09 * absf(sin(TAU * EchoStage.ramp(t, 4.4, 5.6))), 1.0)
	st.face_camera(b)
	var open := EchoStage.smooth(t, 8.0, 8.9)
	door.rotation.y = FACE_LEFT + open * 1.5
	(st.actors["room_glow"] as Node3D).visible = open > 0.05
	_greeter_light(st, open)
	_greeter_cam(st, t)


static func _t_greeter_inv(st: EchoStage, t: float) -> void:
	var g := st.actors["g"] as EchoStage.Guest
	var b := st.actors["b"] as Silhouette
	var door := st.actors["door"] as Node3D
	var ding := st.actors["ding"] as Node3D
	ding.visible = _flash_in(t, 3.0, 0.3)
	# the same start: the Guest answers
	var walk := EchoStage.ramp(t, 0.0, 3.0)
	var gz := lerpf(1.6, -0.5, walk)
	var moving := 1.0 - EchoStage.ramp(t, 2.7, 3.1)
	var answer := EchoStage.smooth(t, 3.5, 4.1) * (1.0 - EchoStage.smooth(t, 5.4, 6.0))
	# then the bellhop comes down the corridor, takes them by the elbow, and walks them to the door at their side
	var come := EchoStage.smooth(t, 5.6, 7.8)
	var bp := Vector3(-0.5, 0, -2.6).lerp(Vector3(GX - 0.75, 0, gz - 0.5), come)
	var gp := Vector3(GX, 0.0, gz)
	var face := FACE_AWAY
	var gm := moving
	var towards := EchoStage.smooth(t, 8.4, 10.2)
	if t > 8.4:
		bp = Vector3(GX - 0.75, 0, gz - 0.5).lerp(Vector3(-1.6, 0, HALL_DOOR_Z + 0.35), towards)
		gp = Vector3(GX, 0.0, gz).lerp(Vector3(-1.3, 0.0, HALL_DOOR_Z + 0.9), towards)
		face = lerp_angle(FACE_AWAY, FACE_LEFT, EchoStage.smooth(t, 8.6, 9.8))
		gm = 1.0 if towards < 1.0 else 0.0
	var enter := EchoStage.ramp(t, 10.3, 11.7)
	if t > 10.3:
		bp = Vector3(-1.6, 0, HALL_DOOR_Z + 0.35).lerp(Vector3(-4.0, 0, HALL_DOOR_Z + 0.1), enter)
		gp = Vector3(-1.3, 0.0, HALL_DOOR_Z + 0.9).lerp(Vector3(-3.4, 0.0, HALL_DOOR_Z + 0.5), enter)
		face = FACE_LEFT
		gm = 1.0 if enter < 1.0 else 0.0
	b.position = bp + Vector3(0, _bob(t, 3.4, 0.04) * (1.0 if (come > 0.0 and come < 1.0) or (towards > 0.0 and towards < 1.0) or (enter > 0.0 and enter < 1.0) else 0.0), 0)
	st.face_camera(b)
	b.visible = t < 11.9
	g.position = gp
	g.rotation.y = face
	g.visible = t < 11.9
	g.pose(0.0, t * 6.5, 0.5 * gm, 0.0, 0.4 + 1.2 * answer, 0.0, 0.0, 0.0)
	# the door opens for them and shuts behind
	var open := EchoStage.smooth(t, 8.8, 9.6) * (1.0 - EchoStage.smooth(t, 11.8, 12.4))
	door.rotation.y = FACE_LEFT + open * 1.5
	(st.actors["room_glow"] as Node3D).visible = open > 0.05
	_greeter_light(st, open)
	_greeter_cam(st, t)
