class_name EntityBase
extends Node3D
## Common shell of every floor entity (SPEC 6.1): a variant (HOLDS / INVERTED), a genuine Tell that the
## Director must play >= 4 s before the Encounter, an Encounter, and a way to stand down. Entities act on the
## world through the session (grid, circuits, doors, noise events) and hurt the guest only through Nerve.

signal encounter_began(entity: EntityBase)
signal encounter_ended(entity: EntityBase)

var session: Node = null                 ## FloorSession (typed loosely to avoid a class cycle)
var entity_id: StringName = &""
var truth: int = RunState.Truth.HOLDS
var is_staff := false                    ## Greeter, Foreman, Lifeguard, Housekeeping, Management (Clauses bind them)
var active := false                      ## an Encounter is running
var home_chunk: Chunk = null
var encounter_kind: StringName = &"minor"
var encounter_time := 0.0
var encounter_limit := 45.0


func setup(p_session: Node, p_truth: int) -> void:
	session = p_session
	truth = p_truth


func player() -> Player:
	return session.player as Player


func tuning() -> DirectorTuning:
	return session.tuning as DirectorTuning


## --- Director interface ---------------------------------------------------------------------

func tell(_lead: float, _chunk: Chunk) -> bool:
	## Start the genuine tell. Return false if this entity cannot tell right now (no suitable spot): the
	## Director will not follow up with an Encounter.
	return false


func begin_encounter(chunk: Chunk, kind: StringName, duration: float) -> void:
	home_chunk = chunk
	encounter_kind = kind
	encounter_limit = duration
	encounter_time = 0.0
	active = true
	player().nerve.in_danger = true
	EventBus.encounter_started.emit(entity_id)
	encounter_began.emit(self)


func stand_down() -> void:
	if not active:
		return
	active = false
	player().nerve.in_danger = false
	EventBus.encounter_ended.emit(entity_id)
	encounter_ended.emit(self)


func can_exist_in(_chunk: Chunk) -> bool:
	return true


func on_session_reset() -> void:
	active = false


## --- helpers --------------------------------------------------------------------------------

func hit_player(source: StringName, amount: int = 1) -> bool:
	var pl := player()
	var landed := pl.nerve.hit(source, amount)
	if landed:
		AudioDirector.play(&"hit_thud")
		pl.shake(1.0)
		session.on_player_hit(self, source)
	return landed


func player_tile() -> Vector2i:
	return GameScale.world_to_tile(player().global_position)


func tile_world(t: Vector2i) -> Vector3:
	return GameScale.tile_to_world(t)


func distance_to_player() -> float:
	var d := player().global_position - global_position
	d.y = 0.0
	return d.length()
