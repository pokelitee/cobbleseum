class_name MoveFxSprites
extends RefCounted
## Our own pixel-art particle textures in Cobblemon's style (concepts_brief.md §12.5), drawn
## from the recipes below into the Cobblemon build's move_fx/ textures:
## - replacements for the Minecraft textures Cobblemon ships in textures/particle/vanilla/,
##   which we never use: each keeps its size and flipbook layout, so effects index it the same;
## - textures some effects name that the jar doesn't have;
## - copies of real Cobblemon textures to the misspelled paths some effects use.
## Style: opaque or clear pixels only, one to four flat colours, white and light grey for the
## pieces effects tint, a few DawnBringer-32 colours for the ones that keep their own.
## Randomness comes from fixed seeds, so every build draws the same pixels.

const VANILLA_DIR := "vanilla"
## Misspelled texture paths some effects use -> the Cobblemon texture they mean.
const COPIES := {
	"textures/textures/moves/thunder_actorbolt": "moves/thunder_actorbolt",
	"textures/textures/moves/thunder_bigbolt": "moves/thunder_bigbolt",
	"generic/impact/impact-fire": "generic/impact/impact_fire",
	"impact-fire": "generic/impact/impact_fire",
}

const WHITE := Color("ffffff")
const PALE := Color("e3e3e3")
const LIGHT := Color("c6c6c6")
const MID := Color("a4a4a4")
const SMOKE := [Color("a0a0a0"), Color("878787"), Color("6d6d6d"), Color("575757")]
const BLUES := [Color("cbdbfc"), Color("5fcde4"), Color("639bff"), Color("5b6ee1")]
const FIRE := [Color("fbf236"), Color("df7126"), Color("ac3232")]
const PINKS := [Color("f4c4e0"), Color("d77bba"), Color("a8508f")]

## Texture path (as CobblemonMoveFX resolves it, without ".png") -> [cell size, frames,
## stacked, recipe method].
const RECIPES := {
	"vanilla/generic": [Vector2i(8, 8), 8, false, "_generic"],
	"vanilla/spiral": [Vector2i(8, 8), 8, false, "_spiral"],
	"vanilla/small_explosion": [Vector2i(16, 16), 9, true, "_explosion"],
	"vanilla/big_smoke": [Vector2i(16, 16), 12, true, "_smoke"],
	"vanilla/big_smoke_white": [Vector2i(16, 16), 12, true, "_smoke_white"],
	"vanilla/critical_hit": [Vector2i(8, 8), 1, false, "_critical"],
	"vanilla/bubble": [Vector2i(8, 8), 1, false, "_bubble"],
	"vanilla/bubble_pop": [Vector2i(16, 16), 5, true, "_bubble_pop"],
	"vanilla/flash": [Vector2i(32, 32), 1, false, "_flash"],
	"vanilla/lava": [Vector2i(8, 8), 1, false, "_lava"],
	"vanilla/flame": [Vector2i(8, 8), 1, false, "_flame"],
	"vanilla/gust": [Vector2i(32, 32), 12, false, "_gust"],
	"vanilla/small_gust": [Vector2i(8, 8), 7, false, "_small_gust"],
	"vanilla/cherry_petal": [Vector2i(12, 9), 1, false, "_petal"],
	"flash": [Vector2i(16, 16), 1, false, "_flash"],
	"charge_orb": [Vector2i(8, 8), 1, false, "_orb"],
	"textures/blocks/wool_colored_white": [Vector2i(16, 16), 1, false, "_wool"],
}


## Draws every recipe into `textures_dir` (the build's textures/particle folder), after
## removing the Minecraft textures. Returns "" or what went wrong.
func render_all(textures_dir: String) -> String:
	var vanilla := textures_dir.path_join(VANILLA_DIR)
	if DirAccess.dir_exists_absolute(vanilla):
		for file in DirAccess.get_files_at(vanilla):
			if DirAccess.remove_absolute(vanilla.path_join(file)) != OK:
				return "cannot remove %s" % vanilla.path_join(file)
	for path: String in RECIPES:
		var canvas := draw(path)
		var target := textures_dir.path_join(path + ".png")
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if canvas.image.save_png(target) != OK:
			return "cannot write %s" % target
	for path: String in COPIES:
		var source := textures_dir.path_join(str(COPIES[path]) + ".png")
		var target := textures_dir.path_join(path + ".png")
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if DirAccess.copy_absolute(source, target) != OK:
			return "cannot copy %s to %s" % [source, target]
	return ""


## The sheet for one recipe.
func draw(path: String) -> PixelCanvas:
	var recipe: Array = RECIPES[path]
	var canvas := PixelCanvas.new(recipe[0], recipe[1], recipe[2])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(path)
	for index in canvas.frames:
		canvas.frame(index)
		call(recipe[3], canvas, index, rng)
	return canvas


## Dots growing from one pixel (frame 0) to nearly the whole cell (effects play it backwards).
func _generic(c: PixelCanvas, index: int, _rng: RandomNumberGenerator) -> void:
	var radius := 0.75 + index * 0.43
	c.disc(4.0, 4.0, radius, WHITE)
	if index >= 4:
		c.rim(PALE)


## A spiral arm lengthening frame by frame, bright at its head.
func _spiral(c: PixelCanvas, index: int, _rng: RandomNumberGenerator) -> void:
	var steps := 3 + index * 2
	for i in steps:
		var t := float(i) / maxf(1.0, steps - 1)
		var angle := t * TAU * 1.1
		var radius := 0.4 + t * 3.2
		var shade: Color = [MID, LIGHT, PALE, WHITE][mini(3, int(t * 4.0))]
		c.pixel(roundi(3.5 + cos(angle) * radius), roundi(3.5 + sin(angle) * radius), shade)


## Puffs bursting outwards and breaking up.
func _explosion(c: PixelCanvas, index: int, rng: RandomNumberGenerator) -> void:
	var t := index / 8.0
	var puffs := 6
	for i in puffs:
		var angle := TAU * i / puffs + 0.4
		var distance := 1.5 + t * 5.0
		var radius := maxf(0.0, 3.6 - t * 3.0 + rng.randf_range(-0.4, 0.4))
		if radius > 0.6:
			c.disc(8.0 + cos(angle) * distance, 8.0 + sin(angle) * distance, radius, WHITE)
	if index < 3:
		c.disc(8.0, 8.0, 3.5 - index, WHITE)
	if index >= 6:
		for i in 10:
			if rng.randf() < 0.6:
				c.clear(rng.randi_range(0, 15), rng.randi_range(0, 15))


func _smoke(c: PixelCanvas, index: int, rng: RandomNumberGenerator) -> void:
	_smoke_with(c, index, rng, SMOKE)


func _smoke_white(c: PixelCanvas, index: int, rng: RandomNumberGenerator) -> void:
	_smoke_with(c, index, rng, [WHITE, PALE, LIGHT, MID])


## A clump of round puffs that shrinks and frays as it ages (frame 0 is the freshest).
func _smoke_with(c: PixelCanvas, index: int, rng: RandomNumberGenerator, shades: Array) -> void:
	var t := index / 11.0
	var size := 6.5 - t * 4.5
	for i in 3:
		var angle := TAU * i / 3.0 + rng.randf() * 0.6
		c.disc(8.0 + cos(angle) * size * 0.45, 8.0 + sin(angle) * size * 0.45, size * 0.7, shades[1])
	c.disc(7.0, 7.0, size * 0.5, shades[0])
	c.rim(shades[2])
	for i in int(t * 24.0):
		c.clear(rng.randi_range(0, 15), rng.randi_range(0, 15))
	if index > 8:
		c.rim(shades[3])


## A small four-pointed star with dimmer diagonals.
func _critical(c: PixelCanvas, _index: int, _rng: RandomNumberGenerator) -> void:
	for i in range(1, 7):
		c.pixel(i, 3, WHITE)
		c.pixel(3, i, WHITE)
	for d in [Vector2i(2, 2), Vector2i(4, 2), Vector2i(2, 4), Vector2i(4, 4)]:
		c.pixel(d.x, d.y, LIGHT)
	c.pixel(3, 3, WHITE)


## A bubble: a blue ring with a pale highlight.
func _bubble(c: PixelCanvas, _index: int, _rng: RandomNumberGenerator) -> void:
	c.ring(4.0, 4.0, 2.2, 3.6, BLUES[2])
	c.pixel(2, 2, BLUES[0])
	c.pixel(3, 2, BLUES[1])


## A bubble that bursts into scattering droplets.
func _bubble_pop(c: PixelCanvas, index: int, rng: RandomNumberGenerator) -> void:
	if index == 0:
		c.ring(8.0, 8.0, 3.5, 5.0, BLUES[2])
		c.pixel(5, 5, BLUES[0])
		c.pixel(6, 5, BLUES[1])
		return
	var distance := 3.5 + index * 1.4
	var drops := 8
	for i in drops:
		if index >= 3 and rng.randf() < 0.3 * (index - 2):
			continue
		var angle := TAU * i / drops + index * 0.2
		var shade: Color = BLUES[3] if index > 2 else BLUES[2]
		c.disc(8.0 + cos(angle) * distance, 8.0 + sin(angle) * distance, 1.2 if index < 3 else 0.7, shade)


## A flash: a solid core inside rings dithered thinner towards the edge.
func _flash(c: PixelCanvas, _index: int, _rng: RandomNumberGenerator) -> void:
	var centre := c.cell.x * 0.5
	var radius := c.cell.x * 0.5
	c.disc(centre, centre, radius * 0.35, WHITE)
	c.dithered_ring(centre, centre, radius * 0.35, radius * 0.55, WHITE, 0.75)
	c.dithered_ring(centre, centre, radius * 0.55, radius * 0.75, WHITE, 0.5)
	c.dithered_ring(centre, centre, radius * 0.75, radius * 0.95, WHITE, 0.25)


## A molten droplet.
func _lava(c: PixelCanvas, _index: int, _rng: RandomNumberGenerator) -> void:
	c.disc(4.0, 4.5, 2.6, FIRE[1])
	c.disc(3.6, 4.0, 1.5, FIRE[0])
	c.pixel(5, 6, FIRE[2])
	c.pixel(3, 3, WHITE)


## A flame tongue, yellow at the core and red at the tip.
func _flame(c: PixelCanvas, _index: int, _rng: RandomNumberGenerator) -> void:
	c.disc(4.0, 5.2, 2.6, FIRE[1])
	for y in range(1, 4):
		c.pixel(4, y, FIRE[1])
		c.pixel(3, y + 1, FIRE[1])
	c.pixel(4, 0, FIRE[2])
	c.pixel(3, 1, FIRE[2])
	c.disc(4.0, 5.5, 1.4, FIRE[0])


## Wind: two arcs sweeping round, growing in then thinning out.
func _gust(c: PixelCanvas, index: int, _rng: RandomNumberGenerator) -> void:
	var t := index / 11.0
	var sweep := 60.0 + sin(t * PI) * 200.0
	var start := index * 30.0
	c.arc(16.0, 16.0, 6.0 + t * 8.0, start, start + sweep, 2.0 if t < 0.7 else 1.0, WHITE)
	c.arc(16.0, 16.0, 3.0 + t * 6.0, start + 180.0, start + 180.0 + sweep * 0.6, 1.0, LIGHT)


## A small swirl of wind.
func _small_gust(c: PixelCanvas, index: int, _rng: RandomNumberGenerator) -> void:
	var t := index / 6.0
	c.arc(4.0, 4.0, 1.5 + t * 2.0, index * 50.0, index * 50.0 + 90.0 + sin(t * PI) * 140.0, 1.0, WHITE)


## A cherry petal with a notched tip.
func _petal(c: PixelCanvas, _index: int, _rng: RandomNumberGenerator) -> void:
	for y in c.cell.y:
		for x in c.cell.x:
			var p := Vector2((x + 0.5 - 6.0) / 5.5, (y + 0.5 - 4.5) / 3.8)
			if p.length() <= 1.0:
				c.pixel(x, y, PINKS[1] if p.x > -0.2 else PINKS[0])
	c.rim(PINKS[2])
	c.clear(11, 4)
	c.clear(10, 4)


## A small glowing orb.
func _orb(c: PixelCanvas, _index: int, _rng: RandomNumberGenerator) -> void:
	c.disc(4.0, 4.0, 3.4, PALE)
	c.disc(4.0, 4.0, 2.2, WHITE)


## Off-white cloth with a faint woven pattern.
func _wool(c: PixelCanvas, _index: int, rng: RandomNumberGenerator) -> void:
	for y in c.cell.y:
		for x in c.cell.x:
			var weave := (x + y * 2) % 5 == 0
			c.pixel(x, y, PALE if weave or rng.randf() < 0.08 else WHITE)
