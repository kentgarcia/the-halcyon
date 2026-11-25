extends TestCase
## CLAUDE.md non-negotiables as code: no global RNG, no direct Input reads outside PlayerInput/InputSetup,
## no raw texture paths outside the material library.

const ALLOW_INPUT := ["core/components/player_input.gd", "core/input_setup.gd", "autoload/settings.gd", "main.gd", "tools/dev/"]


func _scripts() -> Array[String]:
	var out: Array[String] = []
	_collect("res://", out)
	return out


func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var p := dir_path.path_join(n)
		if d.current_is_dir():
			if not n.begins_with(".") and n not in ["mcp", "addons", "node_modules", "third_party", "tests"]:
				_collect(p, out)
		elif n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()


func test_no_global_randomness() -> void:
	var rx := RegEx.new()
	rx.compile("(?<![.\\w])(randf|randi|randf_range|randi_range|randfn|randomize|shuffle)\\(")
	assert_gt(_scripts().size(), 15.0, "lint scans the project scripts")
	assert_not_null(rx.search("var x = randf()"), "regex catches a global call")
	assert_null(rx.search("var x = rng.randf()"), "regex ignores generator calls")
	for f in _scripts():
		var txt := FileAccess.get_file_as_string(f)
		for i in txt.split("\n").size():
			var line := txt.split("\n")[i]
			var code := line.split("#")[0]
			if rx.search(code) != null:
				fail("global RNG call in %s:%d: %s" % [f, i + 1, line.strip_edges()])


func test_gameplay_does_not_read_input_directly() -> void:
	var rx := RegEx.new()
	rx.compile("\\bInput\\.(is_action|get_vector|get_axis|is_key|is_mouse|get_action)")
	for f in _scripts():
		var rel := f.trim_prefix("res://")
		var allowed := false
		for a in ALLOW_INPUT:
			if rel.begins_with(a):
				allowed = true
		if allowed:
			continue
		var txt := FileAccess.get_file_as_string(f)
		var lines := txt.split("\n")
		for i in lines.size():
			if rx.search(lines[i].split("#")[0]) != null:
				fail("direct Input read in %s:%d" % [f, i + 1])


func test_no_raw_kenney_paths_outside_library() -> void:
	for f in _scripts():
		if f.ends_with("material_library.gd"):
			continue
		var txt := FileAccess.get_file_as_string(f)
		if txt.contains("kenney_retro_liminal/PNG"):
			fail("raw texture path in %s (use MaterialLibrary names)" % f)
