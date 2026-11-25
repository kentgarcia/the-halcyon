class_name FloorDef
extends Resource
## Everything that distinguishes one floor of the Halcyon (SPEC 5.3, 8.1, Appendix B).

@export var id: StringName = &""
@export var index: int = 0                          ## climb order, 0 = B3 ... 5 = Lobby
@export var title: String = ""                      ## "Floor 1 (Offices)"
@export var short_name: String = ""                 ## "1F Yellow"
@export var theme_id: StringName = &"yellow"
@export var entity_id: StringName = &"hum"
@export var instinct: StringName = &"seek_light"
@export var p_inverted: float = 0.5
@export var beat_grammar: Array[StringName] = []    ## arrival, choice, long, exam, rest, departure ...
@export var rules: Array[RuleDef] = []
@export var evidence: Array[EvidenceDef] = []
@export var housekeeping_seconds: float = 540.0     ## 9 min (Appendix C)
@export var target_minutes: Vector2 = Vector2(8, 12)
@export var chunk_dir: String = ""                  ## res://content/chunks/yellow
@export var lab_beat: StringName = &"long"          ## which beat hosts the authored Test spot
@export var elevator_muzak: bool = true
@export var intro_pa: StringName = &""              ## PA line when the doors open


func entity_rule() -> RuleDef:
	for r in rules:
		if r.kind == RuleDef.Kind.ENTITY:
			return r
	return null


func rule_by_id(rule_id: StringName) -> RuleDef:
	for r in rules:
		if r.id == rule_id:
			return r
	return null


func evidence_for(variant: int) -> Array[EvidenceDef]:
	var out: Array[EvidenceDef] = []
	for e in evidence:
		if e.variant == variant:
			out.append(e)
	return out


@export var breaker_room: bool = false              ## a Breaker Room side room is offered before the exam (Yellow)
@export var fire_door_chance: float = 0.0           ## chance a shortcut door is a (loud) fire door instead of boarded
@export var alarm_floor: bool = false               ## fire doors trip an alarm that summons the entity (Boiler)
