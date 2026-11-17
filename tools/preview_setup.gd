extends SceneTree
## Screenshots the setup screen (SetupScreen) in each mode, for visual checks.
## Usage (needs a window, not --headless):
##   godot --path . --script res://tools/preview_setup.gd
## Writes cache/previews/setup_<mode>.png, and setup_error.png with a misspelt move; previews
## show Cobblemon art, so they stay in the cache.

const SETUPS := {
	"watch": {"mode": "watch", "sides": [{"species": "garchomp", "ai": "hard"}, {"species": "hydreigon", "shiny": "yes"}],
		"arena": "volcano", "seed": "7"},
	"play": {"mode": "play", "sides": [{"species": "cinderace", "item": "lifeorb"}, {"species": "blastoise", "ai": "normal"}]},
	"record": {"mode": "record", "sides": [{"species": "gastrodon", "form": "east"}, {"species": "wailord"}],
		"weather": "rain", "format": "both", "seconds": 15},
	"error": {"mode": "watch", "sides": [{"species": "garchomp", "moves": "earthquake, dragn claw"}, {"species": "blastoise"}]},
}
## Frames for the model previews to load and frame themselves.
const SETTLE_FRAMES := 30


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := ProjectSettings.globalize_path("res://cache/previews")
	DirAccess.make_dir_recursive_absolute(out_dir)
	SetupScreen._arguments_used = true
	for name: String in SETUPS:
		SetupScreen._last = SETUPS[name]
		var screen: SetupScreen = load(SetupScreen.SCENE).instantiate()
		root.add_child(screen)
		for i in SETTLE_FRAMES:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join("setup_%s.png" % name)
		root.get_texture().get_image().save_png(path)
		print("wrote %s: %s" % [path, screen._command.text])
		screen.queue_free()
		await process_frame
	quit()
