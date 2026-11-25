class_name Door
extends Node3D
## A door on the edge between two tiles (SPEC 5.2, 3.2.2). Owned by a DoorConnection, not by a chunk,
## so it survives either neighbouring chunk unloading.
##
## Local axes: -Z points from side A to side B (dir_ab). The hinge is on the left as seen from A.
## Swing: rotation.y = +theta swings the leaf toward B, -theta toward A. The door always swings AWAY
## from whoever opens it. Peek cracks it ~15 degrees while the button is held.

signal opening(door: Door)
signal opened(door: Door)
signal closed(door: Door)

const OPEN_ANGLE := deg_to_rad(100.0)
const PEEK_ANGLE := deg_to_rad(15.0)
const SWING_SPEED := 3.4

enum State { CLOSED, OPEN, PEEK }

var door_type: StringName = &"unit"
var def: Dictionary = {}
var tile_a: Vector2i = Vector2i.ZERO
var tile_b: Vector2i = Vector2i.ZERO
var dir_ab: Vector2i = Vector2i(0, -1)
var connection: RefCounted = null
var state: int = State.CLOSED
var angle: float = 0.0                     ## signed current swing
var target: float = 0.0
var swing_sign: float = 1.0
var locked_by: StringName = &""            ## item id needed, &"never" = painted shut
var sealed := false                        ## decorative, never opens
var tells: Array[StringName] = []
var interactable: Interactable = null
var body: StaticBody3D = null
var shape: CollisionShape3D = null
var pivot: Node3D = null
var leaf_mat_name: StringName = &"door_wood"
var braced := false
var _auto_close_timer := 0.0
var _opener_side := 1
var _player_crossed := false
var _handle_try_until := 0.0


static func create(type: StringName, a: Vector2i, d: Vector2i) -> Door:
	var door := Door.new()
	door.door_type = type
	door.def = DoorTypes.get_def(type)
	door.tile_a = a
	door.dir_ab = d
	door.tile_b = a + d
	door.name = "Door_%d_%d_%s" % [a.x, a.y, Dir.name_of(d)]
	door.locked_by = StringName(door.def.get("needs", &""))
	if String(door.def.get("mode", "live")) == "locked":
		door.sealed = true
	door._build()
	return door


func edge_center() -> Vector3:
	var T := GameScale.TILE
	return Vector3((tile_a.x + 0.5 + dir_ab.x * 0.5) * T, 0.0, (tile_a.y + 0.5 + dir_ab.y * 0.5) * T)


func _build() -> void:
	var T := GameScale.TILE
	var H := GameScale.DOOR_H
	var W := GameScale.DOOR_W
	var t := GameScale.DOOR_LEAF_T
	position = edge_center()
	rotation = Vector3(0.0, Dir.yaw_of(dir_ab), 0.0)

	pivot = Node3D.new()
	pivot.name = "Hinge"
	pivot.position = Vector3(-W * 0.5, 0.0, 0.0)
	add_child(pivot)

	var mb := MeshBuilder.new()
	var tex: StringName = StringName(def.get("tex", &"door_wood"))
	leaf_mat_name = tex
	# leaf spans x in [0, W] from the hinge; front faces side A (+Z), back faces side B (-Z)
	mb.box(&"#3b2a1c", Vector3(W * 0.5, H * 0.5, 0.0), Vector3(W, H, t))
	var e := 0.002
	mb.quad(tex, Vector3(0, 0, t * 0.5 + e), Vector3(0, H, t * 0.5 + e), Vector3(W, H, t * 0.5 + e), Vector3(W, 0, t * 0.5 + e),
		Vector3(0, 0, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	mb.quad(tex, Vector3(W, 0, -t * 0.5 - e), Vector3(W, H, -t * 0.5 - e), Vector3(0, H, -t * 0.5 - e), Vector3(0, 0, -t * 0.5 - e),
		Vector3(0, 0, -1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	var mi := MeshInstance3D.new()
	mi.name = "Leaf"
	mi.mesh = mb.build()
	pivot.add_child(mi)

	body = StaticBody3D.new()
	body.name = "Blocker"
	body.collision_layer = GameScale.LAYER_DOORS
	body.collision_mask = 0
	shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(W, H, 0.14)
	shape.shape = bs
	shape.position = Vector3(W * 0.5, H * 0.5, 0.0)
	body.add_child(shape)
	pivot.add_child(body)

	interactable = Interactable.new()
	interactable.name = "Use"
	interactable.position = Vector3(0.0, 1.2, 0.0)
	interactable.tag = &"door"
	interactable.data = {"door": self}
	var mode := String(def.get("mode", "live"))
	if mode == "progress":
		interactable.mode = Interactable.Mode.HOLD_PROGRESS
		interactable.hold_duration = float(def.get("duration", 2.0))
	elif mode == "locked":
		interactable.mode = Interactable.Mode.TAP
	else:
		interactable.mode = Interactable.Mode.HOLD_LIVE
		interactable.hold_threshold = 0.38
	interactable.prompt_cb = _prompt
	interactable.tap_cb = _on_tap
	interactable.hold_start_cb = _on_hold_start
	interactable.hold_end_cb = _on_hold_end
	add_child(interactable)


# --- state ----------------------------------------------------------------------------------

func is_open() -> bool:
	return state == State.OPEN


func is_closed() -> bool:
	return state == State.CLOSED and absf(angle) < 0.01


func side_of(world_pos: Vector3) -> int:
	## +1 when on side A, -1 when on side B.
	var rel := world_pos - global_position
	var d := Dir.to_vec3(dir_ab)
	return 1 if rel.dot(d) < 0.0 else -1


func _prompt(player: Node) -> String:
	if sealed:
		return "It won't open"
	if state == State.OPEN:
		return "Close"
	if state == State.PEEK:
		return ""
	var mode := String(def.get("mode", "live"))
	if mode == "progress":
		return "Pry open" if locked_by == &"crowbar" else "Tear the tape"
	return "Open"


func _on_tap(player: Node) -> void:
	if sealed:
		AudioDirector.play_at(&"door_locked", global_position)
		EventBus.toast.emit("It won't open.")
		EventBus.noise_emitted.emit(global_position, 0.15, &"door_locked")
		return
	var side := side_of(player.global_position) if player != null else 1
	if state == State.OPEN:
		close_door()
		return
	if locked_by == &"crowbar" and RunState.pocket != &"crowbar":
		AudioDirector.play_at(&"door_locked", global_position)
		EventBus.toast.emit("Boarded shut. You need something to pry with.")
		return
	if braced:
		return
	var sess: Node = Game.session
	if sess != null and sess.get("clauses") != null:
		var delay: float = sess.clauses.guest_door_delay(self)
		if delay > 0.0:
			sess.clauses.knock_then(self, delay, func(): open_door(side))     # "Staff must knock": so must you
			return
	open_door(side)


func _on_hold_start(player: Node) -> void:
	if sealed or state != State.CLOSED:
		return
	var side := side_of(player.global_position) if player != null else 1
	peek_start(side)


func _on_hold_end(_player: Node) -> void:
	if state == State.PEEK:
		peek_end()


func open_door(side: int, quiet: bool = false) -> void:
	if state == State.OPEN:
		return
	if state == State.CLOSED:
		opening.emit(self)
	_opener_side = side
	swing_sign = 1.0 if side > 0 else -1.0
	state = State.OPEN
	target = OPEN_ANGLE
	_auto_close_timer = 0.0
	_player_crossed = false
	if not quiet:
		var snd := &"elevator_doors_open" if door_type == &"elevator" else &"door_open"
		AudioDirector.play_at(snd, global_position)
		EventBus.noise_emitted.emit(global_position, float(def.get("noise", 0.4)), &"door")
	EventBus.door_opened.emit(self, door_type)
	opened.emit(self)


func close_door(quiet: bool = false) -> void:
	if state == State.CLOSED:
		return
	state = State.CLOSED
	target = 0.0
	if not quiet:
		var snd := &"elevator_doors_close" if door_type == &"elevator" else &"door_close"
		AudioDirector.play_at(snd, global_position)
		EventBus.noise_emitted.emit(global_position, 0.3, &"door")
	EventBus.door_closed.emit(self)


func peek_start(side: int) -> void:
	if state != State.CLOSED or braced:
		return
	opening.emit(self)
	swing_sign = 1.0 if side > 0 else -1.0
	state = State.PEEK
	target = PEEK_ANGLE
	AudioDirector.play_at(&"door_creak", global_position, -6.0)
	EventBus.noise_emitted.emit(global_position, 0.1, &"door_peek")
	EventBus.door_peeked.emit(self)


func peek_end() -> void:
	if state != State.PEEK:
		return
	state = State.CLOSED
	target = 0.0


func force_open_by_entity(entity_side: int) -> void:
	## Entities never open a door instantly: callers play the handle-try tell first (SPEC 3.2.2).
	open_door(entity_side)


func is_blocking() -> bool:
	return absf(angle) < 0.55


# --- per frame ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var signed_target := target * swing_sign
	if not is_equal_approx(angle, signed_target):
		angle = move_toward(angle, signed_target, SWING_SPEED * delta)
		pivot.rotation.y = angle
		var blocking := is_blocking()
		if shape.disabled == blocking:
			shape.set_deferred("disabled", not blocking)
	if state == State.OPEN:
		_auto_close(delta)


func _auto_close(delta: float) -> void:
	## "Doors close behind you" (Law rule): once the guest has passed through and moved clear, it swings shut.
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	if p == null:
		return
	var dist := p.global_position.distance_to(global_position)
	var side := side_of(p.global_position)
	if side != _opener_side:
		_player_crossed = true
	if dist < 1.3:
		_auto_close_timer = 0.0
		return
	if _player_crossed and dist > 1.7:
		_auto_close_timer += delta
		if _auto_close_timer > 0.9 and not _entity_in_way():
			close_door()
	elif dist > 6.0:
		_auto_close_timer += delta
		if _auto_close_timer > 3.0:
			close_door()


func _entity_in_way() -> bool:
	for e in get_tree().get_nodes_in_group(&"entities"):
		if e is Node3D and (e as Node3D).global_position.distance_to(global_position) < 1.2:
			return true
	return false


# --- tells (SPEC 5.2: no door is a pure gamble) ----------------------------------------------

func build_tells() -> void:
	## Visible/audible hints on the approach side (side A, local +Z) that honestly correlate with the room
	## behind (the floor plan only ever assigns a tell the room really has: Fairness Doctrine 1).
	var T := GameScale.DOOR_W
	var mb := MeshBuilder.new()
	var any := false
	for tell in tells:
		match tell:
			&"light_under":
				mb.box(&"*#ffe9a8", Vector3(0.0, 0.007, 0.07), Vector3(T * 0.9, 0.012, 0.10))
				any = true
			&"dark_under":
				mb.box(&"#050403", Vector3(0.0, 0.004, 0.07), Vector3(T * 0.9, 0.008, 0.10))
				any = true
			&"boards_creak", &"alarm_bar":
				pass
			&"draft":
				pass
			&"muzak":
				AudioDirector.play_looped_at(&"muzak_elevator", self, -30.0)
	if any:
		var mi := MeshInstance3D.new()
		mi.name = "Tells"
		mi.mesh = mb.build()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
