## Headless test runner. No addon dependency -- scripts/core/ is pure
## RefCounted, so plain asserts are enough.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Exits non-zero on failure so it can gate a commit.
extends SceneTree

var _failures: Array[String] = []
var _checks: int = 0
var _current: String = ""

func _initialize() -> void:
	var suites: Array[String] = _discover("res://tests")
	for path: String in suites:
		var script: GDScript = load(path)
		var suite: Object = script.new()
		suite.set("runner", self)
		for method: Dictionary in script.get_script_method_list():
			var name: String = method["name"]
			if name.begins_with("test_"):
				_current = "%s::%s" % [path.get_file(), name]
				suite.call(name)

	print("\n%d checks, %d failed" % [_checks, _failures.size()])
	for f: String in _failures:
		print("  FAIL  " + f)
	quit(1 if _failures.size() > 0 else 0)

func _discover(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for f: String in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	out.sort()
	return out

func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("%s: %s" % [_current, message])

func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: %s (got %s, expected %s)" % [_current, message, actual, expected])
