class_name DoorConnection
extends RefCounted
## The link between two chunks through one door edge. Owns the Door; survives either chunk unloading
## (so a door you walked through can still be opened onto a freshly built room: "forgetful house").
## Side info = {uid, beat, spec, socket}; uid is -1 while that side is not live.

var key: String = ""
var door: Door = null
var tile_a: Vector2i = Vector2i.ZERO      ## door.tile_a side
var tile_b: Vector2i = Vector2i.ZERO
var dir_ab: Vector2i = Vector2i.ZERO
var side_a: Dictionary = {"uid": -1, "beat": -1, "spec": &"", "socket": -1}
var side_b: Dictionary = {"uid": -1, "beat": -1, "spec": &"", "socket": -1}
var plan: Dictionary = {}                 ## door plan: {type, dest_beat, tells, ...}


func side_for_tile(t: Vector2i) -> Dictionary:
	return side_a if t == tile_a else side_b


func other_side_of_uid(uid: int) -> Dictionary:
	return side_b if int(side_a["uid"]) == uid else side_a


func is_live(side: Dictionary) -> bool:
	return int(side["uid"]) >= 0


func both_dead() -> bool:
	return int(side_a["uid"]) < 0 and int(side_b["uid"]) < 0
