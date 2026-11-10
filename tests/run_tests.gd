extends SceneTree
## Headless test runner.
## Usage: godot --headless --path . --script res://tests/run_tests.gd
## Runs every test_* method in res://tests/**/test_*.gd and exits non-zero on any failure.

const TEST_ROOT := "res://tests"


func _initialize() -> void:
	_run.call_deferred()


## Runs after the first frame starts, so tests can add nodes to a live scene tree.
func _run() -> void:
	await process_frame
	# A test that hits a runtime error would otherwise look like a pass; count logged errors.
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var total := 0
	var failed := 0
	for path in _find_tests(TEST_ROOT):
		var script: GDScript = load(path)
		# A script with a parse error can still load, with no methods and nothing to run.
		if script == null or not script.can_instantiate():
			printerr("FAIL %s: could not load script" % path)
			failed += 1
			continue
		for test_name in _test_methods(script):
			total += 1
			counter.errors.clear()
			var test_case: TestCase = script.new()
			test_case.call(test_name)
			var problems := test_case.failures.duplicate()
			# Errors a test deliberately causes (expected_errors) aren't failures.
			problems.append_array(counter.errors.slice(test_case.expected_errors))
			if problems.is_empty():
				print("PASS %s:%s" % [path, test_name])
			else:
				failed += 1
				for problem in problems:
					printerr("FAIL %s:%s - %s" % [path, test_name, problem])
	OS.remove_logger(counter)
	print("%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 or total == 0 else 0)


func _find_tests(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for sub in DirAccess.get_directories_at(dir_path):
		found.append_array(_find_tests(dir_path.path_join(sub)))
	for file in DirAccess.get_files_at(dir_path):
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	found.sort()
	return found


func _test_methods(script: GDScript) -> PackedStringArray:
	var names: PackedStringArray = []
	for method in script.get_script_method_list():
		var method_name: String = method.name
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	return names
