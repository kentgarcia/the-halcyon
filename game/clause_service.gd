class_name ClauseService
extends Node
## Clauses (SPEC 4.10): a kept rule binds BOTH sides. This service holds the House side queries entities call
## and polls the Guest side for breaches ("Break your side and the Clause is void for the rest of the floor").
## The house honours its side exactly as printed (Doctrine 10). Staff = Greeter, Foreman, Lifeguard,
## Housekeeping, Management; the Hum and the Queue are NOT staff.
##
##   walk_encouraged  House: staff never out-walk a walk while they can see you.   Guest: don't sprint in sight of staff.
##   doors_close      House: no staff opens a door within 8 s of you closing it.   Guest: don't reopen a door you came through.
##   staff_knock      House: staff knock three times (~5 s) before any door.       Guest: you knock too (doors take 2 s, noisy).
##   stay_lit         House: lit cells are sanctuary from every entity.            Guest: <= 20 s continuously in the dark.
##   take_number      House: only one entity pursues you at once.                  Guest: wait 15 s at the elevator for its chime.
##   whistle          House: you carry a whistle (freezes staff 3 s, once/floor).  Guest: any whistle you hear binds you (stop 3 s).

const DARK_LIMIT := 20.0
const DOOR_GRACE := 8.0
const KNOCK_SECONDS := 5.0
const GUEST_KNOCK := 2.0
const WHISTLE_FREEZE := 3.0
const ELEVATOR_WAIT := 15.0
const SIGHT_RANGE := 14.0

var session: Node = null
var _closed_at: Dictionary = {}          ## Door instance id -> seconds (session clock) when the guest closed it
var _crossed: Dictionary = {}            ## Door instance id -> true: doors the guest came through
var _prev_chunk: Chunk = null
var _dark_t := 0.0
var _bound_until := 0.0
var _whistle_used := false
var _pursuer: EntityBase = null
var _acc := 0.0
var _clock := 0.0


func setup(p_session: Node) -> void:
	session = p_session
	EventBus.door_closed.connect(_on_door_closed)
	EventBus.door_opened.connect(_on_door_opened)
	EventBus.chunk_entered.connect(_on_chunk_entered)


func _exit_tree() -> void:
	for pair in [[EventBus.door_closed, _on_door_closed], [EventBus.door_opened, _on_door_opened], [EventBus.chunk_entered, _on_chunk_entered]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


func floor_started() -> void:
	## The `whistle` Clause hands the guest a whistle at the start of each floor.
	_whistle_used = false
	if active(&"whistle") and RunState.pocket == &"":
		RunState.set_pocket(&"whistle")


func active(clause_id: StringName) -> bool:
	return RunState.clause == clause_id and not RunState.clause_void


# --- House side (entities call these) --------------------------------------------------------

func speed_cap_for(entity: EntityBase, base_speed: float) -> float:
	## walk_encouraged: staff do not move faster than a walk while they can see the guest.
	if not active(&"walk_encouraged") or not entity.is_staff:
		return base_speed
	if entity.global_position.distance_to(session.player.global_position) <= SIGHT_RANGE and _sees(entity):
		return minf(base_speed, GameScale.WALK_SPEED)
	return base_speed


func entity_may_open_door(door: Door, entity: EntityBase = null) -> bool:
	## doors_close: nobody on staff opens a door the guest closed within the last 8 s.
	if not active(&"doors_close") or (entity != null and not entity.is_staff):
		return true
	var t: float = float(_closed_at.get(door.get_instance_id(), -999.0))
	return _clock - t >= DOOR_GRACE


func knock_seconds(entity: EntityBase = null) -> float:
	## staff_knock: how long staff knock before opening any door (0 = no Clause).
	if active(&"staff_knock") and (entity == null or entity.is_staff):
		return KNOCK_SECONDS
	return 0.0


func lit_sanctuary(tile: Vector2i) -> bool:
	## stay_lit: a lit cell is sanctuary from every entity on later floors.
	if not active(&"stay_lit"):
		return false
	var c: Chunk = session.streamer.chunk_at_tile(tile)
	if c == null:
		return false
	var cell := c.cell_at(tile)
	return cell != null and cell.is_lit()


func claim_pursuit(entity: EntityBase) -> bool:
	## take_number: only one entity may pursue the guest at once.
	if not active(&"take_number"):
		return true
	if _pursuer == null or not is_instance_valid(_pursuer) or not _pursuer.active or _pursuer == entity:
		_pursuer = entity
		return true
	return false


func release_pursuit(entity: EntityBase) -> void:
	if _pursuer == entity:
		_pursuer = null


func staff_frozen() -> bool:
	return session.staff_frozen()


func whistle_available() -> bool:
	return active(&"whistle") and RunState.pocket == &"whistle" and not _whistle_used


func blow_whistle() -> bool:
	if not whistle_available():
		return false
	_whistle_used = true
	RunState.set_pocket(&"")
	AudioDirector.play(&"whistle_blast")
	AudioDirector.cue("[Whistle]", 1.5)
	EventBus.noise_emitted.emit(session.player.global_position, 1.0, &"whistle")
	session.freeze_staff(WHISTLE_FREEZE)
	EventBus.toast.emit("Staff stop where they stand.")
	return true


# --- Guest side (breaches void the Clause) ---------------------------------------------------

func guest_door_delay(door: Door) -> float:
	## staff_knock (guest side): you must knock too; closed doors take 2 s and make noise.
	return GUEST_KNOCK if active(&"staff_knock") and door.is_closed() else 0.0


func knock_then(door: Door, delay: float, cb: Callable) -> void:
	AudioDirector.play_at(&"knock_slow", door.global_position, -4.0)
	EventBus.noise_emitted.emit(door.global_position, 0.5, &"knock")
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(door) and cb.is_valid():
		cb.call()


func whistle_heard(seconds: float = WHISTLE_FREEZE) -> void:
	## A whistle blew (the Lifeguard's, or yours): with the whistle Clause in force it binds the guest too.
	if active(&"whistle"):
		_bound_until = _clock + seconds


func void_clause(reason: String) -> void:
	if RunState.clause == &"" or RunState.clause_void:
		return
	RunState.clause_void = true
	EventBus.clause_voided.emit(RunState.clause)
	AudioDirector.say(&"remark_clause_break", &"true", true)
	EventBus.toast.emit("That rule no longer applies to you. (%s)" % reason)


func _process(delta: float) -> void:
	if session == null or session.player == null or RunState.clause == &"" or RunState.clause_void:
		_clock += delta
		return
	_clock += delta
	_acc += delta
	if _acc < 0.15:
		return
	var dt := _acc
	_acc = 0.0
	var pl: Player = session.player
	if pl.frozen:
		return
	match RunState.clause:
		&"walk_encouraged":
			if pl.sprinting and _staff_sees_guest():
				void_clause("you ran in sight of staff")
		&"stay_lit":
			var level: float = session.stage.light_field.level_at_tile(GameScale.world_to_tile(pl.global_position))
			if level < 0.2 and not session.in_relief_zone():
				_dark_t += dt
				if _dark_t > DARK_LIMIT:
					void_clause("more than 20 s in the dark")
			else:
				_dark_t = 0.0
		&"whistle":
			if _clock < _bound_until and Vector2(pl.velocity.x, pl.velocity.z).length() > 0.6:
				void_clause("you moved when the whistle blew")


func _on_door_closed(door: Node) -> void:
	if door == null or session == null or session.player == null:
		return
	if (door as Node3D).global_position.distance_to(session.player.global_position) < 3.5:
		_closed_at[door.get_instance_id()] = _clock


func _on_door_opened(door: Node, _type: StringName) -> void:
	if not active(&"doors_close") or session == null or session.player == null:
		return
	if _crossed.has(door.get_instance_id()) and (door as Node3D).global_position.distance_to(session.player.global_position) < 3.0:
		void_clause("you reopened a door you came through")


func _on_chunk_entered(chunk: Node) -> void:
	var c := chunk as Chunk
	if c == null or session == null:
		return
	if _prev_chunk != null and is_instance_valid(_prev_chunk) and _prev_chunk != c:
		for conn in session.streamer.connections.values():
			var dc: DoorConnection = conn
			var a := int(dc.side_a["uid"])
			var b := int(dc.side_b["uid"])
			if (a == _prev_chunk.uid and b == c.uid) or (b == _prev_chunk.uid and a == c.uid):
				if dc.door != null:
					_crossed[dc.door.get_instance_id()] = true
	_prev_chunk = c


func _staff_sees_guest() -> bool:
	for n in get_tree().get_nodes_in_group(&"entities"):
		if (n is EntityBase and (n as EntityBase).is_staff or (n is Node3D and n.get_meta(&"staff", false))) and _sees(n):
			if (n as Node3D).global_position.distance_to(session.player.global_position) <= SIGHT_RANGE:
				return true
	return false


func _sees(n: Node3D) -> bool:
	var pl: Player = session.player
	var from := n.global_position + Vector3(0, 1.6, 0)
	var q := PhysicsRayQueryParameters3D.create(from, pl.camera.global_position, GameScale.LAYER_WORLD | GameScale.LAYER_DOORS)
	q.exclude = [pl.get_rid()]
	return pl.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
