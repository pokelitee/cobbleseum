extends SceneTree
## Asset pipeline entry point (concepts_brief.md §6).
## Usage: godot --headless --path . --script res://tools/assets.gd -- [source ...] [--offline]
## With no source names, every source in sources.json is processed.

const MANIFEST := "res://sources.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var offline := args.has("--offline")
	for arg in args:
		if arg.begins_with("--") and arg != "--offline":
			return _fail("unknown option %s" % arg)

	var manifest := AssetPipeline.load_manifest(MANIFEST)
	if manifest.has("error"):
		return _fail(manifest.error)
	var sources: Dictionary = manifest.sources
	var ids: Array = Array(args).filter(func(a: String) -> bool: return not a.begins_with("--"))
	for id: String in ids:
		if not sources.has(id):
			return _fail("unknown source '%s' (known: %s)" % [id, ", ".join(sources.keys())])
	if ids.is_empty():
		ids = sources.keys()

	var pipeline := AssetPipeline.new(ProjectSettings.globalize_path("res://cache"), offline)
	var err := pipeline.prepare_cache()
	if not err.is_empty():
		return _fail(err)
	for id: String in ids:
		var source: Dictionary = sources[id]
		err = await pipeline.fetch(id, source, self)
		if err.is_empty():
			err = pipeline.extract(id, source)
		if err.is_empty():
			err = pipeline.build(id, source)
		if not err.is_empty():
			return _fail(err)
		print("%s %s: ready" % [id, source.version])
	quit(0)


func _fail(message: String) -> void:
	printerr("error: " + message)
	quit(1)
