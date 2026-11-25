class_name DoorTypes
extends RefCounted
## Door Grammar (SPEC 5.2): a door's texture is a rumor about what's behind it. Each type fixes the
## look, the noise, and how it opens. Rooms/odds per type live in the floor generator.

const TYPES := {
	&"unit": {"tex": &"door_wood", "noise": 0.4, "mode": "live", "rumor": "Ordinary."},
	&"quiet": {"tex": &"door_wood_light", "noise": 0.3, "mode": "live", "rumor": "Residential. Calm."},
	&"management": {"tex": &"door_wood_ornate", "noise": 0.3, "mode": "live", "rumor": "Official."},
	&"management_light": {"tex": &"door_wood_light_ornate", "noise": 0.3, "mode": "live", "rumor": "Official."},
	&"boarded": {"tex": &"door_wood_boarded", "noise": 0.6, "mode": "progress", "duration": 2.5, "needs": &"crowbar", "rumor": "Blocked."},
	&"fire": {"tex": &"door_emergency_exit", "noise": 0.8, "mode": "live", "alarm": true, "rumor": "Fast. Loud."},
	&"exit": {"tex": &"door_emergency_exit_sign", "noise": 0.8, "mode": "live", "alarm": true, "rumor": "Way out."},
	&"sealed": {"tex": &"door_emergency_exit_tape", "noise": 0.5, "mode": "progress", "duration": 1.6, "rumor": "Quarantine."},
	&"fire_boarded": {"tex": &"door_emergency_exit_boarded", "noise": 0.7, "mode": "progress", "duration": 3.0, "needs": &"crowbar", "rumor": "Blocked. Loud."},
	&"elevator": {"tex": &"door_elevator", "noise": 0.2, "mode": "elevator", "rumor": "Safe transit."},
	&"elevator_oos": {"tex": &"door_elevator_tape", "noise": 0.2, "mode": "locked", "needs": &"fuse", "rumor": "Almost."},
	&"stuck": {"tex": &"door_wood", "noise": 0.2, "mode": "locked", "needs": &"never", "rumor": "Painted shut."},
}


static func get_def(type: StringName) -> Dictionary:
	return TYPES.get(type, TYPES[&"unit"])


static func has_type(type: StringName) -> bool:
	return TYPES.has(type)


static func all_types() -> Array:
	return TYPES.keys()
