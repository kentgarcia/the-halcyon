class_name TestCase
extends RefCounted
## Base class for tests. Methods named test_* are run by tests/test_runner.gd.
## Lifecycle hooks: before_each(), after_each(). Tests may `await` (e.g. process frames).

var tree: SceneTree = null
var failures: PackedStringArray = PackedStringArray()
var assertions := 0
var current_test := ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])


func assert_true(cond: bool, msg: String = "expected true") -> void:
	assertions += 1
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg: String = "expected false") -> void:
	assertions += 1
	if cond:
		fail(msg)


func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	assertions += 1
	if a != b:
		fail("%s (got %s, expected %s)" % [msg, str(a), str(b)])


func assert_ne(a: Variant, b: Variant, msg: String = "") -> void:
	assertions += 1
	if a == b:
		fail("%s (both %s)" % [msg, str(a)])


func assert_near(a: float, b: float, eps: float = 0.0001, msg: String = "") -> void:
	assertions += 1
	if absf(a - b) > eps:
		fail("%s (got %f, expected %f +/- %f)" % [msg, a, b, eps])


func assert_not_null(v: Variant, msg: String = "expected non-null") -> void:
	assertions += 1
	if v == null:
		fail(msg)


func assert_null(v: Variant, msg: String = "expected null") -> void:
	assertions += 1
	if v != null:
		fail(msg)


func assert_lt(a: float, b: float, msg: String = "") -> void:
	assertions += 1
	if not (a < b):
		fail("%s (%f !< %f)" % [msg, a, b])


func assert_gt(a: float, b: float, msg: String = "") -> void:
	assertions += 1
	if not (a > b):
		fail("%s (%f !> %f)" % [msg, a, b])


func wait_frames(n: int) -> void:
	for _i in n:
		await tree.process_frame
