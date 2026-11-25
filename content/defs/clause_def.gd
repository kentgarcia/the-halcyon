class_name ClauseDef
extends Resource
## A rule kept as a contract that binds both sides (SPEC 4.10). Effects are applied by ClauseService.

@export var id: StringName = &""
@export var source_rule: StringName = &""
@export_multiline var printed: String = ""
@export_multiline var house_side: String = ""
@export_multiline var guest_side: String = ""
@export var requires_holds: bool = false      ## only offered when the entity rule HELD
@export var tags: Array[StringName] = []
