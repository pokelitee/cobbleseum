extends TestCase
## Loads every script under game/ and tools/, so a parse error in one no test touches
## (such as the battle view) still fails the suite.


func test_every_script_compiles() -> void:
	for root in ["res://game", "res://tools"]:
		for path in _scripts(root):
			var script: Script = load(path)
			assert_true(script != null and script.can_instantiate(), "%s doesn't compile" % path)


func _scripts(dir: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_scripts(dir.path_join(sub)))
	return found
