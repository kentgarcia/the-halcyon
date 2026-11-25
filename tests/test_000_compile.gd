extends TestCase
## Every script in the project must compile. Catches parse errors the moment they are introduced.


func test_all_scripts_compile() -> void:
	var files: Array[String] = []
	_collect("res://", files)
	files.sort()
	var bad := 0
	for f in files:
		var s := load(f) as GDScript
		if s == null or not s.can_instantiate():
			bad += 1
			fail("does not compile: %s" % f)
	assert_gt(files.size(), 10.0, "found scripts to check")
	assert_eq(bad, 0, "scripts that fail to compile")


func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var p := dir_path.path_join(n)
		if d.current_is_dir():
			if not n.begins_with(".") and n != "mcp" and n != "addons" and n != "node_modules" and n != "third_party":
				_collect(p, out)
		elif n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()
