extends TestCase
## tools/sprites: our own particle textures in Cobblemon's pixel style.

const MAX_COLOURS := 6


func test_every_recipe_keeps_its_size_and_layout() -> void:
	var sprites := MoveFxSprites.new()
	for path: String in MoveFxSprites.RECIPES:
		var recipe: Array = MoveFxSprites.RECIPES[path]
		var cell: Vector2i = recipe[0]
		var frames: int = recipe[1]
		var expected := Vector2i(cell.x, cell.y * frames) if recipe[2] else Vector2i(cell.x * frames, cell.y)
		assert_eq(sprites.draw(path).image.get_size(), expected, path)


## Opaque or clear pixels only, a handful of flat colours, and something in every frame.
func test_every_recipe_follows_the_pixel_style() -> void:
	var sprites := MoveFxSprites.new()
	for path: String in MoveFxSprites.RECIPES:
		var canvas := sprites.draw(path)
		var colours := {}
		var image := canvas.image
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				assert_true(pixel.a == 0.0 or pixel.a == 1.0, "%s has only opaque or clear pixels" % path)
				if pixel.a == 1.0:
					colours[pixel.to_html(false)] = true
		assert_true(colours.size() >= 1 and colours.size() <= MAX_COLOURS, "%s uses %d colours" % [path, colours.size()])
		for index in canvas.frames:
			canvas.frame(index)
			var drawn := false
			for y in canvas.cell.y:
				for x in canvas.cell.x:
					drawn = drawn or canvas.is_set(x, y)
			assert_true(drawn, "%s frame %d isn't empty" % [path, index])


func test_drawing_is_the_same_every_time() -> void:
	for path: String in MoveFxSprites.RECIPES:
		assert_eq(MoveFxSprites.new().draw(path).image.get_data(), MoveFxSprites.new().draw(path).image.get_data(), path)


## The build replaces the Minecraft textures and fills the misspelled paths.
func test_render_all_replaces_vanilla_and_copies_misspellings() -> void:
	var dir := OS.get_user_data_dir().path_join("test_move_fx_sprites")
	DirAccess.make_dir_recursive_absolute(dir.path_join("vanilla"))
	var stray := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	stray.save_png(dir.path_join("vanilla/not_ours.png"))
	for source: String in MoveFxSprites.COPIES.values():
		DirAccess.make_dir_recursive_absolute(dir.path_join(source).get_base_dir())
		stray.save_png(dir.path_join(source + ".png"))
	assert_eq(MoveFxSprites.new().render_all(dir), "")
	assert_false(FileAccess.file_exists(dir.path_join("vanilla/not_ours.png")), "Minecraft textures are removed")
	for path: String in MoveFxSprites.RECIPES:
		assert_true(FileAccess.file_exists(dir.path_join(path + ".png")), path)
	for path: String in MoveFxSprites.COPIES:
		assert_true(FileAccess.file_exists(dir.path_join(path + ".png")), path)
	_remove(dir)


func _remove(path: String) -> void:
	for sub in DirAccess.get_directories_at(path):
		_remove(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
