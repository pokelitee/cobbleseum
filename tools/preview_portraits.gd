extends SceneTree
## Renders HUD portraits (FighterPortrait) side by side for visual checks.
## Usage (needs a window, not --headless):
##   godot --path . --script res://tools/preview_portraits.gd -- [species ...]
## Writes cache/previews/portraits.png, a grid of portraits on a dark plate colour; previews
## show Cobblemon art, so they stay in the cache.

## A spread of body shapes: bipeds, quadrupeds, serpents, fliers, round and headless bodies, and
## very tall, long and small species.
const SPECIES: Array[String] = ["blastoise", "cinderace", "machamp", "mrmime", "lucario", "garchomp",
	"arcanine", "rapidash", "tauros", "eevee", "pikachu", "snorlax",
	"onix", "gyarados", "rayquaza", "ekans", "steelix", "lapras",
	"charizard", "dragonite", "pidgeot", "butterfree", "zubat", "hydreigon",
	"voltorb", "gengar", "jigglypuff", "ditto", "magnemite", "magikarp",
	"wailord", "joltik", "psyduck", "squirtle", "bulbasaur", "wailmer"]
const COLUMNS := 6


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		printerr("error: " + loaded.error)
		return quit(1)
	var species: Array = Array(OS.get_cmdline_user_args())
	if species.is_empty():
		species = SPECIES
	var portraits: Array[FighterPortrait] = []
	for id: String in species:
		var entry: Dictionary = loaded.data.roster.get(id, {})
		if entry.is_empty():
			printerr("error: '%s' is not in the roster" % id)
			return quit(1)
		var portrait := FighterPortrait.create(BattleView.MODELS_DIR.path_join(entry.model), entry.scale, entry.height)
		if portrait == null:
			printerr("error: cannot load the model %s" % entry.model)
			return quit(1)
		root.add_child(portrait)
		portraits.append(portrait)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var cell := FighterPortrait.SIZE
	var rows := ceili(portraits.size() / float(COLUMNS))
	var sheet := Image.create(cell * mini(COLUMNS, portraits.size()), cell * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Hud.PLATE)
	for i in portraits.size():
		var image := portraits[i].get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(i % COLUMNS, i / COLUMNS) * cell)
	var out_dir := ProjectSettings.globalize_path("res://cache/previews")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := out_dir.path_join("portraits.png")
	sheet.save_png(path)
	print("wrote " + path)
	quit()
