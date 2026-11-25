class_name RuleDef
extends Resource
## One line of a floor's House Rules card (SPEC 4.1).

enum Kind { ENTITY, LAW, FLAVOR }

@export var id: StringName = &""
@export var floor_id: StringName = &""
@export var number: int = 1                 ## the printed number on the card
@export_multiline var text: String = ""
@export var kind: Kind = Kind.FLAVOR
@export var instinct: StringName = &""      ## for ENTITY rules, e.g. &"seek_light"
@export var law_key: StringName = &""       ## for LAW rules: the mechanic that makes it true
@export var foreshadow: String = ""         ## FLAVOR: what it hints at (documentation only)
@export var clause_id: StringName = &""     ## the Clause this rule can be torn into (if any)


func is_entity() -> bool:
	return kind == Kind.ENTITY


func is_true_for(truth: int) -> bool:
	## Law and Flavor rules are always true on Standard difficulty; the entity rule depends on the roll.
	if kind == Kind.ENTITY:
		return truth == RunState.Truth.HOLDS
	return true
