class_name EntityFactory
extends RefCounted
## Floor entity id -> instance. Entities that are not built yet return null: the floor then plays without an
## Encounter (the Director simply never fires one) and the soak test reports it.

const SCRIPTS := {
	&"hum": "res://entities/hum.gd",
	&"foreman": "res://entities/foreman.gd",
	&"lifeguard": "res://entities/lifeguard.gd",
	&"queue": "res://entities/queue_line.gd",
	&"greeter": "res://entities/greeter.gd",
	&"audit": "res://entities/lobby_audit.gd",
	&"management": "res://entities/lobby_audit.gd",     # the Lobby floor def names its entity "management"
}


static func create(entity_id: StringName) -> EntityBase:
	var path: String = SCRIPTS.get(entity_id, "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	var scr: GDScript = load(path)
	return scr.new() as EntityBase


static func available(entity_id: StringName) -> bool:
	var path: String = SCRIPTS.get(entity_id, "")
	return path != "" and ResourceLoader.exists(path)
