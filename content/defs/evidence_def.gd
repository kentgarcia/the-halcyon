class_name EvidenceDef
extends Resource
## A piece of world evidence for one variant of an entity rule (SPEC 4.3). Evidence is always TRUE for
## the run it is placed in (Fairness Doctrine 1). `variant` says which truth it supports.

enum Kind { GRAFFITI, PROP_STATE, AUDIO_CUE, DOOR_STATE, TAPE_CLIP, CAM_ONLY, TEST }

@export var id: StringName = &""
@export var floor_id: StringName = &""
@export var kind: Kind = Kind.GRAFFITI
@export var variant: int = RunState.Truth.HOLDS
@export_range(1, 3) var prominence: int = 3
@export var slot_kind: StringName = &"graffiti"    ## the chunk slot kind that can host it
@export var text: String = ""                      ## graffiti text / sign text / label
@export var note: String = ""                      ## what the notebook sticker says once found
@export var params: Dictionary = {}                ## recipe parameters used by the spawner
