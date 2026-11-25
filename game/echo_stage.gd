class_name EchoStage
extends RefCounted
## The little set an Echo clip is filmed on (SPEC 4.3, 12.5). It is built far from the play area, lit by its
## OWN small light field (the same shader path as the real floor, so a "lit cell" here looks like a lit cell
## there), populated with a box-built Guest and the same dithered silhouettes the real entities use, and
## filmed through the shared tape viewport by EchoPlayer.
##
## Local frame: +X right, +Y up, the camera sits at +Z looking toward -Z, y = 0 is the floor. Everything in
## the set is in local metres; ORIGIN is where it hangs in the world.

const ORIGIN := Vector3(4000.0, 0.0, 4000.0)
const TILE := GameScale.TILE
const WALL := GameScale.WALL_H
const FIELD_N := 32                    ## texels per side of the set's own light field
const FIELD_SPAN := 20.0               ## metres covered by it, centred on the origin
const LIT := 0.8                       ## texture value of a fully ON cell (LightField.HEADROOM = 1.25)
const DOOR_H := 2.1
const DOOR_LEAF_W := 1.0

var root: Node3D = null
var theme: FloorTheme = null
var actors: Dictionary = {}            ## free-form handles the clip script keeps (name -> node/value)
var cam_pos := Vector3(0.0, 1.4, 4.5)
var cam_look := Vector3(0.0, 1.0, -3.0)
var cam_fov := 52.0
var ambient := 0.10
var fog_density := 0.02
var env: Environment = null
var guest_jacket := "#b4543a"          ## the Guest's coat; each clip picks one that stands off its set

var _mats: Dictionary = {}             ## key -> ShaderMaterial (per-stage copies carrying the set's light field)
var _set := MeshBuilder.new()
var _field_img: Image = null
var _field_tex: ImageTexture = null
var _field := PackedFloat32Array()
var _field_dirty := true


func _init(p_theme: FloorTheme) -> void:
	theme = p_theme
	_field.resize(FIELD_N * FIELD_N)
	_field_img = Image.create_empty(FIELD_N, FIELD_N, false, Image.FORMAT_R8)
	_field_tex = ImageTexture.create_from_image(_field_img)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.015, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0, 0, 0)
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = theme.fog_color
	env.fog_density = fog_density
	env.fog_sky_affect = 1.0


func attach(parent: Node) -> void:
	root = Node3D.new()
	root.name = "EchoStage"
	parent.add_child(root)
	root.global_position = ORIGIN


func dispose() -> void:
	if root != null and is_instance_valid(root):
		root.queue_free()
	root = null
	actors.clear()
	_mats.clear()


# --- camera ---------------------------------------------------------------------------------

func apply_camera(cam: Camera3D) -> void:
	cam.fov = cam_fov
	cam.global_position = ORIGIN + cam_pos
	cam.look_at(ORIGIN + cam_look, Vector3.UP)
	env.fog_density = fog_density


func to_world(local: Vector3) -> Vector3:
	return ORIGIN + local


# --- materials & the set's own light field --------------------------------------------------

func mat(key: StringName) -> Material:
	## Library material (or "#rrggbb" / "*#rrggbb") copied so it samples THIS set's light field.
	if _mats.has(key):
		return _mats[key]
	var base := MeshBuilder.default_resolver(key) as ShaderMaterial
	var m := base.duplicate() as ShaderMaterial
	m.set_shader_parameter("light_map", _field_tex)
	m.set_shader_parameter("light_rect", Vector4(ORIGIN.x - FIELD_SPAN * 0.5, ORIGIN.z - FIELD_SPAN * 0.5, 1.0 / FIELD_SPAN, 1.0 / FIELD_SPAN))
	m.set_shader_parameter("light_color", theme.light_color)
	m.set_shader_parameter("light_gain", theme.light_gain * 1.25)
	m.set_shader_parameter("ambient_floor", ambient)
	_mats[key] = m
	return m


func _resolve(key: StringName) -> Material:
	return mat(key)


func set_ambient(v: float) -> void:
	ambient = v
	for k in _mats:
		(_mats[k] as ShaderMaterial).set_shader_parameter("ambient_floor", v)


func clear_light(v: float = 0.0) -> void:
	_field.fill(v)
	_field_dirty = true


func light_rect(x0: float, z0: float, x1: float, z1: float, v: float = LIT) -> void:
	## Anti-aliased rectangle of light (local metres): each texel takes `v` times the share of it the rect covers.
	var step := FIELD_SPAN / float(FIELD_N)
	var lo := -FIELD_SPAN * 0.5
	for j in FIELD_N:
		var tz0 := lo + float(j) * step
		var oz := clampf(minf(z1, tz0 + step) - maxf(z0, tz0), 0.0, step) / step
		if oz <= 0.0:
			continue
		for i in FIELD_N:
			var tx0 := lo + float(i) * step
			var ox := clampf(minf(x1, tx0 + step) - maxf(x0, tx0), 0.0, step) / step
			if ox > 0.0:
				var k := j * FIELD_N + i
				_field[k] = maxf(_field[k], v * ox * oz)
	_field_dirty = true


func light_disc(cx: float, cz: float, r: float, v: float = LIT) -> void:
	## A soft pool of light (the camcorder lamp, a spill from a doorway).
	var step := FIELD_SPAN / float(FIELD_N)
	var lo := -FIELD_SPAN * 0.5
	for j in FIELD_N:
		var pz := lo + (float(j) + 0.5) * step
		for i in FIELD_N:
			var px := lo + (float(i) + 0.5) * step
			var d := Vector2(px - cx, pz - cz).length()
			var f := clampf((r + step * 0.5 - d) / step, 0.0, 1.0)
			if f > 0.0:
				var k := j * FIELD_N + i
				_field[k] = maxf(_field[k], v * f)
	_field_dirty = true


func flush_light() -> void:
	if not _field_dirty:
		return
	for j in FIELD_N:
		for i in FIELD_N:
			var c := clampf(_field[j * FIELD_N + i], 0.0, 1.0)
			_field_img.set_pixel(i, j, Color(c, 0.0, 0.0))
	_field_tex.update(_field_img)
	_field_dirty = false


# --- the static set -------------------------------------------------------------------------

func floor_area(m: StringName, x0: float, z0: float, x1: float, z1: float, y: float = 0.0) -> void:
	var nx := maxi(1, int(round((x1 - x0) / TILE)))
	var nz := maxi(1, int(round((z1 - z0) / TILE)))
	var sx := (x1 - x0) / float(nx)
	var sz := (z1 - z0) / float(nz)
	for j in nz:
		for i in nx:
			_set.floor_quad(m, x0 + float(i) * sx, z0 + float(j) * sz, x0 + float(i + 1) * sx, z0 + float(j + 1) * sz, y)


func ceiling_area(m: StringName, x0: float, z0: float, x1: float, z1: float, overrides: Dictionary = {}, y: float = WALL) -> void:
	## One quad per tile; `overrides` maps Vector2i(floor(x/TILE), floor(z/TILE)) -> another material (light panels).
	var nx := maxi(1, int(round((x1 - x0) / TILE)))
	var nz := maxi(1, int(round((z1 - z0) / TILE)))
	for j in nz:
		for i in nx:
			var ax := x0 + float(i) * TILE
			var az := z0 + float(j) * TILE
			var key := Vector2i(floori((ax + 0.01) / TILE), floori((az + 0.01) / TILE))
			_set.ceiling_quad(overrides.get(key, m), ax, az, ax + TILE, az + TILE, y)


func wall(m: StringName, a: Vector3, b: Vector3, n: Vector3, openings: Array = [], door_h: float = DOOR_H) -> void:
	## An axis-aligned wall run from a to b (floor level), one quad per tile, visible from the side `n` points to.
	## `openings` holds tile indices (counted from a) left open as doorways (header only above door_h).
	var length := a.distance_to(b)
	var count := maxi(1, int(round(length / TILE)))
	var d := (b - a) / float(count)
	var w := d.length()
	var right := (-n).cross(Vector3.UP)
	for k in count:
		var c := a + d * (float(k) + 0.5)
		var bl := c - right * (w * 0.5)
		var br := c + right * (w * 0.5)
		if openings.has(k):
			_wall_seg(m, bl, br, n, door_h, WALL)
		else:
			_wall_seg(m, bl, br, n, 0.0, WALL)


func _wall_seg(m: StringName, bl: Vector3, br: Vector3, n: Vector3, y0: float, y1: float) -> void:
	var vb := 1.0 - y0 / WALL
	var vt := 1.0 - y1 / WALL
	_set.quad(m, bl + Vector3(0, y0, 0), bl + Vector3(0, y1, 0), br + Vector3(0, y1, 0), br + Vector3(0, y0, 0), n,
		Vector2(0, vb), Vector2(0, vt), Vector2(1, vt), Vector2(1, vb))


func set_box(color: String, center: Vector3, size: Vector3) -> void:
	_set.box(StringName(color), center, size)


func commit_set() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Set"
	mi.mesh = _set.build(Callable(self, "_resolve"))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	_set = MeshBuilder.new()
	return mi


# --- movable props --------------------------------------------------------------------------

func part(parent: Node3D, color: String, center: Vector3, size: Vector3, name_: String = "Part") -> MeshInstance3D:
	## One coloured box as its own node (pivot at the parent's origin).
	var mb := MeshBuilder.new()
	mb.box(StringName(color), center, size)
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = mb.build(Callable(self, "_resolve"))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func prop(parent: Node3D, parts: Array, name_: String = "Prop") -> Node3D:
	## A Node3D holding one merged mesh from [[color, cx, cy, cz, sx, sy, sz], ...]; returns the node.
	var mb := MeshBuilder.new()
	for p in parts:
		mb.box(StringName(String(p[0])), Vector3(float(p[1]), float(p[2]), float(p[3])), Vector3(float(p[4]), float(p[5]), float(p[6])))
	var n := Node3D.new()
	n.name = name_
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mb.build(Callable(self, "_resolve"))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	parent.add_child(n)
	return n


func door_leaf(pos: Vector3, yaw: float, color: String = "#5a3d25", name_: String = "Door") -> Node3D:
	## A door leaf hinged at its local origin; the leaf extends toward local +X, closed.
	var n := prop(root, [
		[color, DOOR_LEAF_W * 0.5, DOOR_H * 0.5, 0.0, DOOR_LEAF_W, DOOR_H, GameScale.DOOR_LEAF_T],
		["#b9a24a", DOOR_LEAF_W - 0.1, 1.0, 0.05, 0.05, 0.05, 0.05],
		["#b9a24a", DOOR_LEAF_W - 0.1, 1.0, -0.05, 0.05, 0.05, 0.05],
	], name_)
	n.position = pos
	n.rotation.y = yaw
	return n


func frame_box(pos: Vector3, yaw: float, w: float = TILE, color: String = "#2b1d12") -> Node3D:
	## Door jambs and header around a doorway of width w whose centre is at pos (frame faces local -Z/+Z).
	var n := prop(root, [
		[color, -w * 0.5, DOOR_H * 0.5, 0.0, 0.08, DOOR_H, 0.14],
		[color, w * 0.5, DOOR_H * 0.5, 0.0, 0.08, DOOR_H, 0.14],
		[color, 0.0, DOOR_H + 0.03, 0.0, w + 0.08, 0.07, 0.14],
	], "Frame")
	n.position = pos
	n.rotation.y = yaw
	return n


func glow(pos: Vector3, size: Vector3, color: String = "#fff4c0", name_: String = "Glow") -> MeshInstance3D:
	## A self-lit box (light panels, signs, the bell lamp, the board digits).
	var holder := Node3D.new()
	holder.name = name_
	root.add_child(holder)
	holder.position = pos
	return part(holder, "*" + color, Vector3.ZERO, size, name_ + "Mesh")


# --- figures ---------------------------------------------------------------------------------

func silhouette(shape_id: int, height: float, aspect: float = 0.42, boost: float = 0.0, body: Color = Color(0.02, 0.018, 0.015)) -> Silhouette:
	## The real entity billboard (same shader, same shapes) with its own per-frame logic switched off:
	## the clip script orients and dissolves it, so a recording is reproducible.
	var s := Silhouette.create(shape_id, height, aspect, body)
	s.process_mode = Node.PROCESS_MODE_DISABLED
	s.face_camera = false
	s.mat.set_shader_parameter("cam_boost", boost)
	s.mat.set_shader_parameter("crawl", 0.1)           # barely any internal crawl: at 128x96 it reads as holes
	root.add_child(s)
	return s


func face_camera(node: Node3D) -> void:
	## Billboard `node` toward the film camera (rotation about Y only), keeping any X-mirroring the script set.
	var to := cam_pos - node.position
	node.rotation.y = atan2(to.x, to.z)


func make_guest(lamp: bool = false) -> Guest:
	var g := Guest.new()
	g.build(self, lamp)
	root.add_child(g)
	return g


# --- time helpers (static: clip scripts are pure functions of t) -----------------------------

static func ramp(t: float, t0: float, t1: float) -> float:
	return clampf((t - t0) / maxf(0.0001, t1 - t0), 0.0, 1.0)


static func smooth(t: float, t0: float, t1: float) -> float:
	var x := ramp(t, t0, t1)
	return x * x * (3.0 - 2.0 * x)


static func path(t: float, keys: Array) -> Vector3:
	## keys = [[time, Vector3], ...] ascending; linear between, clamped at the ends.
	var n := keys.size()
	if t <= float(keys[0][0]):
		return keys[0][1]
	for i in range(1, n):
		var t1 := float(keys[i][0])
		if t <= t1:
			var t0 := float(keys[i - 1][0])
			return (keys[i - 1][1] as Vector3).lerp(keys[i][1], (t - t0) / maxf(0.0001, t1 - t0))
	return keys[n - 1][1]


static func val(t: float, keys: Array) -> float:
	## keys = [[time, float], ...]
	var n := keys.size()
	if t <= float(keys[0][0]):
		return float(keys[0][1])
	for i in range(1, n):
		var t1 := float(keys[i][0])
		if t <= t1:
			var t0 := float(keys[i - 1][0])
			return lerpf(float(keys[i - 1][1]), float(keys[i][1]), (t - t0) / maxf(0.0001, t1 - t0))
	return float(keys[n - 1][1])


# ================================================================================================
# The Guest: a blocky, drab person with a camcorder. Poses are numbers so a clip is a pure function of t.
# ================================================================================================

class Guest extends Node3D:
	const THIGH := 0.42
	const SHIN := 0.45
	const FOOT := 0.05
	var hips: Node3D
	var torso: Node3D
	var head: Node3D
	var arm_l: Node3D
	var arm_r: Node3D
	var thigh_l: Node3D
	var shin_l: Node3D
	var foot_l: Node3D
	var thigh_r: Node3D
	var shin_r: Node3D
	var foot_r: Node3D
	var lamp_box: MeshInstance3D
	var led_box: MeshInstance3D

	func build(st: EchoStage, lamp_on: bool) -> void:
		name = "Guest"
		var jacket := st.guest_jacket
		var trousers := "#2d3039"
		var skin := "#c9ab8e"
		hips = Node3D.new()
		hips.name = "Hips"
		add_child(hips)
		torso = Node3D.new()
		torso.name = "Torso"
		hips.add_child(torso)
		st.part(torso, jacket, Vector3(0, 0.30, 0), Vector3(0.40, 0.56, 0.23), "Chest")
		st.part(torso, "#3a3028", Vector3(0, 0.03, 0), Vector3(0.40, 0.07, 0.23), "Belt")
		head = Node3D.new()
		head.name = "Head"
		head.position = Vector3(0, 0.60, 0)
		torso.add_child(head)
		st.part(head, skin, Vector3(0, 0.12, 0), Vector3(0.22, 0.24, 0.22), "Skull")
		st.part(head, "#3b2b20", Vector3(0, 0.22, 0.02), Vector3(0.23, 0.06, 0.24), "Hair")
		arm_l = _arm(st, -0.26, jacket, skin)
		arm_r = _arm(st, 0.26, jacket, skin)
		# the camcorder in the right hand
		st.part(arm_r, "#202020", Vector3(0, -0.52, -0.11), Vector3(0.10, 0.10, 0.22), "Camcorder")
		led_box = st.part(arm_r, "*#ff2a2a", Vector3(0.0, -0.46, -0.05), Vector3(0.03, 0.03, 0.03), "RecLed")
		lamp_box = st.part(arm_r, "*#fff2b8", Vector3(0.0, -0.52, -0.235), Vector3(0.07, 0.07, 0.03), "Lamp")
		lamp_box.visible = lamp_on
		var legs := _leg(st, -0.10, trousers)
		thigh_l = legs[0]
		shin_l = legs[1]
		foot_l = legs[2]
		legs = _leg(st, 0.10, trousers)
		thigh_r = legs[0]
		shin_r = legs[1]
		foot_r = legs[2]
		pose()

	func _arm(st: EchoStage, x: float, jacket: String, skin: String) -> Node3D:
		var a := Node3D.new()
		a.name = "Arm"
		a.position = Vector3(x, 0.52, 0)
		torso.add_child(a)
		st.part(a, jacket, Vector3(0, -0.20, 0), Vector3(0.11, 0.42, 0.12), "Sleeve")
		st.part(a, skin, Vector3(0, -0.47, 0), Vector3(0.09, 0.10, 0.09), "Hand")
		return a

	func _leg(st: EchoStage, x: float, trousers: String) -> Array[Node3D]:
		var th := Node3D.new()
		th.name = "Thigh"
		th.position = Vector3(x, 0, 0)
		hips.add_child(th)
		st.part(th, trousers, Vector3(0, -THIGH * 0.5, 0), Vector3(0.15, THIGH, 0.16), "ThighMesh")
		var sh := Node3D.new()
		sh.name = "Shin"
		sh.position = Vector3(0, -THIGH, 0)
		th.add_child(sh)
		st.part(sh, trousers, Vector3(0, -SHIN * 0.5, 0), Vector3(0.13, SHIN, 0.14), "ShinMesh")
		var ft := Node3D.new()
		ft.name = "Foot"
		ft.position = Vector3(0, -SHIN, 0)
		sh.add_child(ft)
		st.part(ft, "#15161a", Vector3(0, -0.03, -0.07), Vector3(0.12, 0.06, 0.27), "FootMesh")
		var out: Array[Node3D] = [th, sh, ft]
		return out

	func pose(crouch: float = 0.0, phase: float = 0.0, amp: float = 0.0, lean: float = 0.0,
			arm_r_fwd: float = 0.35, arm_l_fwd: float = 0.0, nod: float = 0.0, head_yaw: float = 0.0) -> void:
		## crouch 0..1 (1 = a deep squat), phase = gait phase (radians), amp 0..1 (0 still, 0.5 walk, 1 run),
		## lean = torso forward lean (rad), arm_*_fwd = arm swing forward (rad, added to the gait swing),
		## nod = head pitch (rad, positive = look down), head_yaw = head turn (rad, positive = to the guest's left).
		var swing := 0.62 * amp
		var tl := crouch * 1.45 + swing * sin(phase)
		var tr := crouch * 1.45 + swing * sin(phase + PI)
		var kl := -crouch * 2.45 - amp * 1.0 * maxf(0.0, cos(phase))
		var kr := -crouch * 2.45 - amp * 1.0 * maxf(0.0, cos(phase + PI))
		var hl := THIGH * cos(tl) + SHIN * cos(tl + kl)
		var hr := THIGH * cos(tr) + SHIN * cos(tr + kr)
		hips.position.y = maxf(hl, hr) + FOOT
		thigh_l.rotation.x = tl
		shin_l.rotation.x = kl
		foot_l.rotation.x = -(tl + kl)
		thigh_r.rotation.x = tr
		shin_r.rotation.x = kr
		foot_r.rotation.x = -(tr + kr)
		torso.rotation.x = -(lean + crouch * 0.6)
		arm_l.rotation.x = arm_l_fwd - 0.55 * amp * sin(phase) + crouch * 0.5
		arm_r.rotation.x = arm_r_fwd - 0.25 * amp * sin(phase + PI) + crouch * 0.5
		head.rotation.x = (lean + crouch * 0.6) - nod
		head.rotation.y = head_yaw

	func stand_height() -> float:
		return THIGH + SHIN + FOOT + 0.84
