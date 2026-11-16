extends SceneTree
## Prototype step for Cobblemon's own move effects (concepts_brief.md §12.5): copies the jar's
## particle effects, particle textures and scripted move effects into
## cache/build/cobblemon/<version>/move_fx/, where CobblemonMoveFX reads them.
## Usage: godot --headless --path . --script res://tools/extract_move_fx.gd
## Needs the Cobblemon jar already downloaded by tools/assets.gd. A full converter would fold
## these prefixes into sources.json and the Cobblemon build step instead.

const PREFIXES: Array[String] = [
	"assets/cobblemon/bedrock/particles/",
	"assets/cobblemon/textures/particle/",
	"data/cobblemon/action_effects/",
]


func _initialize() -> void:
	var manifest := AssetPipeline.load_manifest(ProjectSettings.globalize_path("res://sources.json"))
	if manifest.has("error"):
		printerr("error: " + str(manifest.error))
		quit(1)
		return
	var source: Dictionary = manifest.sources.cobblemon
	var jar := ProjectSettings.globalize_path("res://cache/downloads/%s.%s" % [source.sha256, source.archive])
	var out_dir := ProjectSettings.globalize_path(CobblemonMoveFX.ROOT)
	var written: Array = []
	var error := ZipReader.extract(jar, PREFIXES, out_dir, written)
	if not error.is_empty():
		printerr("error: " + error)
		quit(1)
		return
	print("wrote %d files to %s" % [written.size(), out_dir])
	quit(0)
