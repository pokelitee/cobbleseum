extends SceneTree
## Draws every MoveFxSprites recipe onto one sheet, enlarged with hard pixel edges, for
## checking our own particle textures by eye (concepts_brief.md §12.5).
## Usage: godot --headless --path . --script res://tools/preview_sprites.gd
## Writes cache/previews/move_fx_sprites.png: one row per texture, in recipe order, on a
## mid-grey checkerboard so white and clear pixels both show.

const SCALE := 6
const GAP := 8
const ROW_WIDTH := 1100


func _initialize() -> void:
	var sprites := MoveFxSprites.new()
	var sheets: Array[Image] = []
	for path: String in MoveFxSprites.RECIPES:
		var image := sprites.draw(path).image
		# Tall stacked sheets are laid out as a row of frames so every row stays short.
		var recipe: Array = MoveFxSprites.RECIPES[path]
		if recipe[2]:
			var cell: Vector2i = recipe[0]
			var row := Image.create(cell.x * int(recipe[1]), cell.y, false, Image.FORMAT_RGBA8)
			for i in int(recipe[1]):
				row.blit_rect(image, Rect2i(0, cell.y * i, cell.x, cell.y), Vector2i(cell.x * i, 0))
			image = row
		image.resize(image.get_width() * SCALE, image.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
		sheets.append(image)
	var height := GAP
	var width := 0
	for image in sheets:
		height += image.get_height() + GAP
		width = maxi(width, image.get_width())
	width = maxi(width + GAP * 2, ROW_WIDTH)
	var sheet := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			sheet.set_pixel(x, y, Color(0.42, 0.42, 0.45) if (x / 12 + y / 12) % 2 == 0 else Color(0.36, 0.36, 0.39))
	var top := GAP
	for image in sheets:
		sheet.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(GAP, top))
		top += image.get_height() + GAP
	var out := ProjectSettings.globalize_path("res://cache/previews/move_fx_sprites.png")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	sheet.save_png(out)
	print("wrote %s (%d textures)" % [out, sheets.size()])
	quit(0)
