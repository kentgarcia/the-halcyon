extends TestCase
## Every sound id / PA line id referenced in code must exist (audio/manifest.json, data/pa_lines.json).
## A missing id is silent at runtime (the director only warns), so this is the only thing that catches typos.

const SOUND_CALLS := ["play", "play_at", "play_looped_at", "set_ambience", "set_ambience_level", "has_sound", "sound_duration"]
const SAY_CALLS := ["say"]


func _gd_files(dir: String, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append("%s/%s" % [dir, f])
	for d in DirAccess.get_directories_at(dir):
		if d != "addons" and d != ".godot" and d != "tests" and d != "mcp" and not d.begins_with("."):
			_gd_files("%s/%s" % [dir, d], out)


func test_sound_and_line_ids_exist() -> void:
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://audio/manifest.json"))
	assert_true(m is Dictionary, "manifest.json parses")
	var sounds: Dictionary = (m as Dictionary).get("sounds", {})
	var voice: Dictionary = (m as Dictionary).get("voice", {})
	var pa: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/pa_lines.json"))
	var line_ids := {}
	for l in (pa as Dictionary).get("lines", []):
		line_ids[String((l as Dictionary).get("id", ""))] = true
	var files := PackedStringArray()
	_gd_files("res://", files)
	var re_sound := RegEx.new()
	re_sound.compile("AudioDirector\\.(%s)\\(\\s*&\"([a-z0-9_]+)\"" % "|".join(SOUND_CALLS))
	var re_say := RegEx.new()
	re_say.compile("AudioDirector\\.(%s)\\(\\s*&\"([a-z0-9_]+)\"" % "|".join(SAY_CALLS))
	var checked := 0
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for r in re_sound.search_all(text):
			var id := r.get_string(2)
			checked += 1
			assert_true(sounds.has(id), "%s: sound '%s' is not in audio/manifest.json" % [path, id])
		for r in re_say.search_all(text):
			var id2 := r.get_string(2)
			checked += 1
			assert_true(line_ids.has(id2) or voice.has(id2), "%s: PA line '%s' is not in data/pa_lines.json" % [path, id2])
	assert_true(checked > 20, "audio id lint scanned %d references (expected many)" % checked)
