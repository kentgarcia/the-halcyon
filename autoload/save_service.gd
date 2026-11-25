extends Node
## user://save.json, versioned. The notebook is the save file: "a player who dies 10 times and one who
## never dies should differ only in what they've understood" (SPEC pillar 2).

const PATH := "user://save.json"
const TAPE_DIR := "user://tapes"
const VERSION := 1
const MAX_DEATHS := 12

var data: Dictionary = {}
var path: String = PATH                ## where the save lives; dev tools and tests switch profile (see use_profile)
var tape_dir: String = TAPE_DIR


func use_profile(profile: String) -> void:
	## Dev runs, bots and tests must never touch the player's real save (cleared floors, guest number, tapes).
	if profile == "":
		path = PATH
		tape_dir = TAPE_DIR
	else:
		path = "user://save_%s.json" % profile
		tape_dir = "user://tapes_%s" % profile
	load_save()


func _ready() -> void:
	load_save()


func default_data() -> Dictionary:
	return {
		"version": VERSION,
		"next_guest": 1,
		"notebook": {},        # floor_id -> {"attempts": [..], "stickers": [..], "cleared": bool}
		"endings": [],
		"deaths": [],          # newest first, capped at MAX_DEATHS
		"stats": {"runs_started": 0, "floors_cleared": 0, "blackouts": 0, "checkouts": 0},
		"run": {},             # RunState.to_dict() at the last elevator checkpoint
		"intro_seen": false,
		"tutorial": {},        # id -> true (one-off teaching tapes etc.)
	}


func load_save() -> void:
	data = default_data()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveService: corrupt save ignored")
		return
	data = _migrate(parsed as Dictionary)


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveService: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))


func wipe() -> void:
	data = default_data()
	save()


func _migrate(d: Dictionary) -> Dictionary:
	var out := default_data()
	for k in out:
		if d.has(k):
			out[k] = d[k]
	out["version"] = VERSION
	return out


# --- notebook -------------------------------------------------------------------------------

func page(floor_id: StringName) -> Dictionary:
	var nb: Dictionary = data["notebook"]
	var key := String(floor_id)
	if not nb.has(key):
		nb[key] = {"attempts": [], "stickers": [], "cleared": false, "labels": {}}
	return nb[key]


func log_attempt(floor_id: StringName, attempt: Dictionary) -> void:
	var p := page(floor_id)
	var arr: Array = p["attempts"]
	arr.append(attempt)
	while arr.size() > 24:
		arr.pop_front()


func add_sticker(floor_id: StringName, sticker: Dictionary) -> void:
	page(floor_id)["stickers"].append(sticker)


func mark_cleared(floor_id: StringName) -> void:
	page(floor_id)["cleared"] = true
	data["stats"]["floors_cleared"] = int(data["stats"].get("floors_cleared", 0)) + 1


func is_cleared(floor_id: StringName) -> bool:
	return bool(page(floor_id).get("cleared", false))


func take_guest_number() -> int:
	var n: int = int(data["next_guest"])
	data["next_guest"] = n + 1
	return n


func add_ending(ending: StringName) -> void:
	var arr: Array = data["endings"]
	if not arr.has(String(ending)):
		arr.append(String(ending))


func has_ending(ending: StringName) -> bool:
	return (data["endings"] as Array).has(String(ending))


func record_death(entry: Dictionary) -> void:
	var arr: Array = data["deaths"]
	arr.push_front(entry)
	while arr.size() > MAX_DEATHS:
		var old: Dictionary = arr.pop_back()
		var tape := String(old.get("tape", ""))
		if tape != "" and FileAccess.file_exists(tape):
			DirAccess.remove_absolute(tape)
	data["stats"]["blackouts"] = int(data["stats"].get("blackouts", 0)) + 1


func flag(id: StringName) -> bool:
	return bool((data["tutorial"] as Dictionary).get(String(id), false))


func set_flag(id: StringName) -> void:
	(data["tutorial"] as Dictionary)[String(id)] = true


# --- own-death tapes (SPEC 4.11) -------------------------------------------------------------

func save_death_tape(floor_id: StringName, truth: int, guest: int, frames: Array, fps: float) -> void:
	## Keeps the last seconds of a Blackout as a tape file; Autopsy shows it and later floors may hide it in a vault.
	DirAccess.make_dir_recursive_absolute(tape_dir)
	var typed: Array[PackedByteArray] = []
	for fr in frames:
		typed.append(fr)
	var tape_path := "%s/g%d_%s_%d.tape" % [tape_dir, guest, floor_id, Time.get_ticks_msec()]
	var f := FileAccess.open(tape_path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(TapeBuffer.pack(typed, fps))
	record_death({"floor": String(floor_id), "truth": truth, "guest": guest, "tape": tape_path})


func load_tape(tape_file: String) -> Dictionary:
	if tape_file == "" or not FileAccess.file_exists(tape_file):
		return {"frames": [], "fps": 10}
	return TapeBuffer.unpack(FileAccess.get_file_as_bytes(tape_file))


func deaths_on(floor_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in data["deaths"]:
		if String(d.get("floor", "")) == String(floor_id):
			out.append(d)
	return out
