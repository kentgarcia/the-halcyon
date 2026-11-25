class_name StaffRules
extends RefCounted
## The House side of the Clauses, as seen by staff (SPEC 4.10, Doctrine 10): the Foreman and the Lifeguard ask
## these before they move fast, open a door, or act while a whistle has frozen staff. Every query is a thin wrapper
## over the session's ClauseService and degrades to "no Clause in force" when there is no session (tests, previews).


static func _svc(session: Node) -> Object:
	return session.get("clauses") if session != null else null


static func frozen(session: Node) -> bool:
	## The guest's whistle (Clause `whistle`) freezes staff for 3 s, once per floor.
	if session != null and session.has_method("staff_frozen"):
		return bool(session.call("staff_frozen"))
	return false


static func speed_cap(session: Node, entity: EntityBase, base_speed: float) -> float:
	## `walk_encouraged`: nothing on staff moves faster than a walk while it can see the guest.
	var svc := _svc(session)
	if svc != null:
		return float(svc.call("speed_cap_for", entity, base_speed))
	return base_speed


static func may_open_door(session: Node, door: Door, entity: EntityBase) -> bool:
	## `doors_close`: no staff opens a door within 8 s of the guest closing it.
	var svc := _svc(session)
	if svc != null and door != null:
		return bool(svc.call("entity_may_open_door", door, entity))
	return true


static func knock_seconds(session: Node, entity: EntityBase) -> float:
	## `staff_knock`: three knocks (about 5 s) before any door. 0 when the Clause is not in force.
	var svc := _svc(session)
	if svc != null:
		return float(svc.call("knock_seconds", entity))
	return 0.0


static func whistle_heard(session: Node) -> void:
	## A staff whistle binds a guest who carries the `whistle` Clause too (guest side).
	var svc := _svc(session)
	if svc != null:
		svc.call("whistle_heard")


static func door_gate(session: Node, door: Door, entity: EntityBase, knocked_for: float) -> StringName:
	## What a staff member standing at a door may do right now:
	##   &"knock"  keep knocking (staff_knock not yet served)    &"wait"  doors_close grace not over
	##   &"open"   free to open it
	if door == null:
		return &"open"
	if knocked_for < knock_seconds(session, entity):
		return &"knock"
	if not may_open_door(session, door, entity):
		return &"wait"
	return &"open"
