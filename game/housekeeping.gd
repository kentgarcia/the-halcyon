class_name Housekeeping
extends Node
## Housekeeping (SPEC 6.9): the floor's soft clock and the one threat that follows you through the whole
## building. At 80 % of the clock the PA warns you; at 100 % a linen cart with one squeaking wheel enters at
## the arrival elevator and works forward, room by room, tidying: cells and doors back to how they were,
## dropped items gone, a planted camcorder to Lost & Found. If it finds you in a room it is cleaning you are
## "shown out" (-1 Nerve). It has no variant and no lie: it is the control the floor's liar is read against.
##
## Logical position is a main-beat index; the cart only becomes a physical node while it shares a room with
## the guest (so it costs nothing while the guest is elsewhere, and still works with streamed rooms).

const ROOM_SECONDS := 34.0          ## time the cart spends "working" each beat
const CART_SPEED := 1.9             ## m/s while visible: a walk, never faster (it is staff)
const SPAWN_DELAY := 6.0            ## seconds into a beat before the cart is physically in the room
const QUIET_SECONDS := 6.0          ## the cart stops outside a hide spot and the squeak stops (SPEC 7.1)
const SHOW_OUT_DIST := 1.1
const GRACE_SECONDS := 4.0          ## the cart must have been in the room this long before it can show you out (a tell, SPEC 4.2)

var session: Node = null
var clock_seconds: float = 540.0
var enabled := true
var warned := false
var active := false
var cart_beat := -1
var cart_in_beat := 0.0
var cart: Node3D = null
var cart_tile: Vector2i = Vector2i.ZERO
var _path: Array[Vector2i] = []
var _path_t := 0.0
var _quiet := 0.0
var _squeak: AudioStreamPlayer3D = null
var _far_on := false
var _cooldown := 0.0
var _cart_age := 0.0
var _gone := false


func setup(p_session: Node, seconds: float) -> void:
	session = p_session
	clock_seconds = seconds
	enabled = Settings.housekeeping_enabled


func _exit_tree() -> void:
	_kill_cart()
	_stop_far_squeak()


func _process(delta: float) -> void:
	if session == null or session.player == null or _gone:
		return
	if not enabled:
		return
	_tick_clock(delta)
	if active:
		_tick_cart(delta)


# --- clock ---------------------------------------------------------------------------------

func clock_running() -> bool:
	var pl: Player = session.player
	if pl.frozen:
		return false
	if session.encounter_active():
		return false                 # fairness: the clock pauses during an active Encounter
	var cur: Chunk = session.streamer.current
	if cur != null:
		var bp: FloorPlan.BeatPlan = cur.plan.get("bp", null)
		if bp != null and (bp.kind == &"arrival" or bp.kind == &"departure"):
			return false             # ... and inside elevators
	return true


func fraction() -> float:
	return clampf(RunState.floor_clock / maxf(1.0, clock_seconds), 0.0, 2.0)


func _tick_clock(delta: float) -> void:
	if not clock_running():
		return
	RunState.floor_clock += delta
	var f := fraction()
	var warn_at: float = (session.tuning as DirectorTuning).housekeeping_warn_fraction
	if f >= warn_at and not RunState.housekeeping_warned:
		RunState.housekeeping_warned = true
		warned = true
		AudioDirector.say(&"housekeeping_warn", &"true", true)
	if f >= 1.0 and not active:
		_arrive()


func _arrive() -> void:
	active = true
	cart_beat = 0
	cart_in_beat = 0.0
	AudioDirector.say(&"housekeeping_arrive", &"true", true)
	AudioDirector.cue("[Wheel squeak - far]", 3.0)
	_start_far_squeak()


# --- cart ----------------------------------------------------------------------------------

func _player_beat() -> int:
	var cur: Chunk = session.streamer.current
	if cur == null:
		return -1
	var bp: FloorPlan.BeatPlan = cur.plan.get("bp", null)
	if bp == null:
		return cur.beat_index
	return bp.index if bp.main else -2          # side rooms: the cart does not follow you in


func _beat_chunk(beat: int) -> Chunk:
	for uid in session.streamer.chunks:
		var c: Chunk = session.streamer.chunks[uid]
		if c.beat_index == beat:
			return c
	return null


func _tick_cart(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var last := (session.plan as FloorPlan).main_beats.size() - 1
	if cart_beat > last:
		_finish()
		return
	if cart == null and session.encounter_active():
		return                                    # the cart waits for the Encounter to end
	cart_in_beat += delta
	var pb := _player_beat()
	var chunk := _beat_chunk(cart_beat)
	# the room being worked is tidied once, when the cart has been there a while
	if cart_in_beat >= ROOM_SECONDS * 0.5 and chunk != null and not chunk.get_meta(&"tidied", false):
		if not (pb == cart_beat and cart != null):
			_tidy(chunk)
	if pb == cart_beat and cart_in_beat >= SPAWN_DELAY:
		_ensure_cart(chunk)
		_drive_cart(delta, chunk)
	else:
		_kill_cart()
		_update_far_squeak(pb)
		if cart_in_beat >= ROOM_SECONDS:
			_advance()


func _advance() -> void:
	cart_beat += 1
	cart_in_beat = 0.0
	_quiet = 0.0


func _finish() -> void:
	_gone = true
	_kill_cart()
	_stop_far_squeak()
	active = false


func _ensure_cart(chunk: Chunk) -> void:
	if cart != null or chunk == null:
		return
	cart = Node3D.new()
	cart.name = "HousekeepingCart"
	var sil := Silhouette.create(6, 1.5, 0.9, Color(0.12, 0.1, 0.07))
	cart.add_child(sil)
	session.stage.actors_root.add_child(cart)
	# enters through the room's entry socket (works forward)
	var t := chunk.world_open.keys()[0] as Vector2i
	if not chunk.entry_world.is_empty():
		t = chunk.entry_world[0]["tile"]
	cart_tile = t
	cart.global_position = GameScale.tile_to_world(t)
	_path.clear()
	_squeak = AudioDirector.play_looped_at(&"cart_squeak_loop", cart, -4.0)
	_stop_far_squeak()
	cart.add_to_group(&"entities")
	cart.set_meta(&"staff", true)
	_cart_age = 0.0


func _kill_cart() -> void:
	if _squeak != null and is_instance_valid(_squeak):
		AudioDirector.stop_player(_squeak)
	_squeak = null
	if cart != null and is_instance_valid(cart):
		cart.queue_free()
	cart = null


func _drive_cart(delta: float, chunk: Chunk) -> void:
	_cart_age += delta
	var pl: Player = session.player
	var ptile := GameScale.world_to_tile(pl.global_position)
	var grid: WorldGrid = session.grid
	# Brace a door and the cart skips this room (counterplay)
	if _entry_braced(chunk):
		_kill_cart()
		_advance()
		return
	# never enters an occupied Rest room
	var bp: FloorPlan.BeatPlan = chunk.plan.get("bp", null)
	if bp != null and bp.kind == &"rest":
		_kill_cart()
		cart_in_beat = maxf(0.0, ROOM_SECONDS - 4.0)
		return
	var dist := Vector2(cart.global_position.x - pl.global_position.x, cart.global_position.z - pl.global_position.z).length()
	if pl.hidden:
		# The quiet cart: it stops outside the room you are hiding in and the squeak stops
		if dist < 4.0:
			_quiet += delta
			if _squeak != null:
				_squeak.volume_db = -80.0
			if _quiet >= QUIET_SECONDS:
				_quiet = 0.0
				_tidy(chunk)
				_kill_cart()
				_advance()
			return
	elif _squeak != null:
		_squeak.volume_db = -4.0
	# path toward the guest, tile by tile
	_path_t -= delta
	if _path_t <= 0.0 or _path.is_empty():
		_path_t = 0.6
		_path = grid.path(cart_tile, ptile, {"max_nodes": 600}) if not pl.hidden else []
	if _path.size() > 1:
		var next_t := _path[1]
		var target := GameScale.tile_to_world(next_t)
		var cur := cart.global_position
		var d := target - cur
		d.y = 0.0
		var step := CART_SPEED * delta
		if d.length() <= step:
			cart.global_position = target
			cart_tile = next_t
			_path.pop_front()
		else:
			cart.global_position = cur + d.normalized() * step
	if dist <= SHOW_OUT_DIST and not pl.hidden and _cooldown <= 0.0 and _cart_age >= GRACE_SECONDS:
		_show_out(chunk)


func _entry_braced(chunk: Chunk) -> bool:
	for e in chunk.entry_world:
		var t: Vector2i = e["tile"]
		var d: Vector2i = e["dir"]
		var door := (session.grid as WorldGrid).door_on_edge(t, t + d)
		if door != null and door.braced:
			return true
	return false


func _show_out(chunk: Chunk) -> void:
	_cooldown = 6.0
	AudioDirector.play(&"hit_thud", -3.0)
	AudioDirector.say(&"remark_lost", &"true", false)
	session.player.nerve.lose_segment(&"housekeeping")
	session.on_player_hit(null, &"housekeeping")
	# move the guest to the room's forward exit (a corridor tile outside)
	var out: Vector3 = session.exit_position_of(chunk)
	session.player.teleport(out, session.player.rotation.y)
	EventBus.toast.emit("Housekeeping has shown you out.")
	_tidy(chunk)
	_kill_cart()
	_advance()


# --- tidy ----------------------------------------------------------------------------------

func _tidy(chunk: Chunk) -> void:
	if chunk == null or chunk.get_meta(&"tidied", false):
		return
	chunk.set_meta(&"tidied", true)
	for cell in chunk.cells:
		cell.tidy()
	for conn in session.streamer.connections.values():
		var dc: DoorConnection = conn
		if int(dc.side_a["uid"]) == chunk.uid or int(dc.side_b["uid"]) == chunk.uid:
			if dc.door != null and dc.door.is_open():
				dc.door.close_door(true)
	for n in chunk.props_root.get_children():
		if n is Pickup and (n as Pickup).dropped:
			n.queue_free()
	if session.camcorder.planted != null and session.camcorder.planted.chunk == chunk:
		session.send_camcorder_to_lost_and_found()
	chunk.mark_panels_dirty()


# --- far squeak (you can hear it coming) ----------------------------------------------------

func _start_far_squeak() -> void:
	AudioDirector.set_ambience(&"cart_squeak_loop", true, -8.0)
	_far_on = true


func _stop_far_squeak() -> void:
	if _far_on:
		AudioDirector.set_ambience(&"cart_squeak_loop", false)
		_far_on = false


func _update_far_squeak(player_beat: int) -> void:
	if not _far_on:
		_start_far_squeak()
	var gap := absi(player_beat - cart_beat) if player_beat >= 0 else 4
	AudioDirector.set_ambience_level(&"cart_squeak_loop", clampf(1.0 - float(gap) * 0.22, 0.12, 0.9))
