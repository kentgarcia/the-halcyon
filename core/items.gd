class_name Items
extends RefCounted
## Pocket items (SPEC 3.2.3). One slot. `battery` is consumed on pickup instead of pocketed.

const DEFS := {
	&"crowbar": {"name": "Crowbar", "prompt": "Take the crowbar", "hint": "Pries boarded doors. Loud."},
	&"fuse": {"name": "Fuse", "prompt": "Take the fuse", "hint": "Powers a taped elevator or a breaker."},
	&"key": {"name": "Key", "prompt": "Take the key", "hint": "Opens Management doors."},
	&"bulb": {"name": "Fluorescent tube", "prompt": "Take the tube", "hint": "Fit it in a dead fixture. You move the light."},
	&"whistle": {"name": "Whistle", "prompt": "Take the whistle", "hint": "One blast freezes all staff for 3 s."},
	&"battery": {"name": "Battery", "prompt": "Take the battery", "hint": "+50 to the camcorder."},
}


static func display_name(id: StringName) -> String:
	return String(DEFS.get(id, {}).get("name", id))


static func prompt_for(id: StringName) -> String:
	return String(DEFS.get(id, {}).get("prompt", "Take"))


static func hint_for(id: StringName) -> String:
	return String(DEFS.get(id, {}).get("hint", ""))


static func is_consumable(id: StringName) -> bool:
	return id == &"battery"
