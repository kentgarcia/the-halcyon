extends Node
## Headless test runner. Finds res://tests/test_*.gd, runs every test_* method, prints a summary and
## exits non-zero on any failure. Usage: ./dev.sh test [filter]   (filter matches file or method name)
## Extra args: --soak=<n> to scale soak tests.

var filter := ""
var total := 0
var passed := 0
var failed_names: PackedStringArray = PackedStringArray()
var assertions := 0


func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	filter = String(args.get("filter", ""))
	SaveService.use_profile("test")        # tests never touch the player's save
	await get_tree().process_frame
	var files := _find_tests()
	var started := Time.get_ticks_msec()
	for f in files:
		await _run_file(f)
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	print("")
	print("==== %d/%d tests passed, %d assertions, %.1fs ====" % [passed, total, assertions, secs])
	for n in failed_names:
		print("FAILED: %s" % n)
	get_tree().quit(0 if failed_names.is_empty() else 1)


static func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if not a.begins_with("--"):
			continue
		var s := a.substr(2)
		var eq := s.find("=")
		if eq < 0:
			out[s] = "1"
		else:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out


func _find_tests() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open("res://tests")
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and n.begins_with("test_") and n.ends_with(".gd") and n != "test_runner.gd" and n != "test_case.gd":
			out.append("res://tests/" + n)
		n = d.get_next()
	out.sort()
	return out


func _run_file(path: String) -> void:
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		total += 1
		failed_names.append("%s (does not compile)" % path)
		print("FAIL  %s  (does not compile)" % path)
		return
	var methods: Array[String] = []
	for m in script.get_script_method_list():
		var mn: String = m["name"]
		if mn.begins_with("test_"):
			methods.append(mn)
	methods.sort()
	var file_match := filter == "" or path.contains(filter)
	for mn in methods:
		if not file_match and not mn.contains(filter):
			continue
		var inst: TestCase = script.new()
		inst.tree = get_tree()
		inst.current_test = "%s::%s" % [path.get_file(), mn]
		total += 1
		inst.before_each()
		await inst.call(mn)
		inst.after_each()
		assertions += inst.assertions
		if inst.failures.is_empty():
			passed += 1
			print("ok    %s" % inst.current_test)
		else:
			failed_names.append(inst.current_test)
			print("FAIL  %s" % inst.current_test)
			for f in inst.failures:
				print("        - %s" % f)
