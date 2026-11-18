class_name MarkTextures
extends RefCounted
## Pixel-art textures for battlefield marks (BattleMarks, concepts_brief.md §12.5), drawn
## in-house when first asked for: opaque or clear pixels only, a few flat colours, from fixed
## seeds, so every build and every render draws the same pixels. The arena's ground colour
## shades the marks made of earth (cracks, craters, scuffs, a scorch's edge), so they read as
## the field's own ground broken up rather than paint; stains, frost and glows take the move's
## type colour. Each kind has VARIANTS drawings, and glowing pixels (embers, sparks, an energy
## burn's rim) go into a second image. Scuffs are drawn along one of DIRECTIONS ways, since
## BattleMarks only turns marks by right angles.

const KINDS: Array[String] = ["scorch", "frost", "splash", "cracks", "crater", "scuff"]
const VARIANTS := 3
const DIRECTIONS := 16
const PIXELS_PER_METRE := 16
## Pixels across a texture: hit marks are drawn for about 2 m and area marks for about 4 m, at
## the arena's 16 pixels per metre (§12.7).
const SMALL := 32
const LARGE := 64
const CHAR := Color(0.12, 0.1, 0.09)
const FROST_LIGHT := Color(0.94, 0.97, 1.0)
const FROST_FILL := Color(0.72, 0.86, 0.97)
const FROST_DEEP := Color(0.5, 0.7, 0.92)
const EMBER := Color(1.0, 0.42, 0.12)

## "kind|type|variant|direction|ground" -> draw()'s images.
var _cache := {}


static func size_of(kind: String) -> int:
	return LARGE if kind in ["cracks", "crater"] else SMALL


## draw()'s images, drawn once.
func get_images(kind: String, type: String, variant: int, ground: Color, direction := 0) -> Dictionary:
	var key := "%s|%s|%d|%d|%s" % [kind, type, variant, direction, ground.to_html(false)]
	if not _cache.has(key):
		_cache[key] = draw(kind, type, variant, ground, direction)
	return _cache[key]


## Draws one mark: `kind` for a move of `type` on ground of `ground` colour, a scuff along
## `direction` (of DIRECTIONS, from +x toward +y). {"albedo": Image, "emission": Image or null,
## "glow_colour": the one colour its glowing pixels have}.
static func draw(kind: String, type: String, variant: int, ground: Color, direction := 0) -> Dictionary:
	var n := size_of(kind)
	var albedo := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var emission := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var random := SimRandom.new(hash("%s|%s|%d" % [kind, type, variant]))
	var colour := TypeColors.of(type)
	var glows := false
	match kind:
		"scorch":
			glows = _scorch(albedo, emission, random, type, colour, ground)
		"frost":
			_frost(albedo, random)
		"splash":
			_splash(albedo, random, colour)
		"cracks":
			_cracks(albedo, random, ground, colour, type)
		"crater":
			glows = _crater(albedo, emission, random, ground, colour, type)
		"scuff":
			_scuff(albedo, random, ground)
			albedo = _turned(albedo, TAU * direction / DIRECTIONS)
	var glow_colour := EMBER if type == "Fire" else colour
	return {"albedo": albedo, "emission": emission if glows else null, "glow_colour": glow_colour}


## A blob whose edge wobbles with the angle: the share of the radius it reaches toward `angle`.
static func _edge(random: SimRandom, lobes: int) -> PackedFloat32Array:
	var edge := PackedFloat32Array()
	edge.resize(lobes)
	for i in lobes:
		edge[i] = random.range_float(0.7, 1.0)
	return edge


static func _edge_at(edge: PackedFloat32Array, angle: float) -> float:
	var t := fposmod(angle / TAU, 1.0) * edge.size()
	var i := int(t)
	var f := t - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(edge[i], edge[(i + 1) % edge.size()], f)


## Where a pixel sits: its distance from the centre as a share of the half-width, and angle.
static func _polar(n: int, x: int, y: int) -> Vector2:
	var offset := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5)
	return Vector2(offset.length() / (n * 0.5), offset.angle())


static func _put(image: Image, x: int, y: int, colour: Color) -> void:
	if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
		image.set_pixel(x, y, colour)


## A wandering line from `from` out along `angle`, `length` pixels long, turning a little at
## each step; returns the pixels it crossed.
static func _walk(random: SimRandom, from: Vector2, angle: float, length: int, wander: float) -> Array[Vector2i]:
	var pixels: Array[Vector2i] = []
	var at := from
	for step in length:
		angle += random.range_float(-wander, wander)
		at += Vector2.from_angle(angle)
		pixels.append(Vector2i(floori(at.x), floori(at.y)))
	return pixels


## A burn: a charred core inside a ring of the ground darkened, its edge broken into flecks.
## Fire leaves embers in the char, Electric bright forks running out, and the energy types
## (Dragon, Psychic, Fairy, Ghost, Dark) a rim of their colour; those pixels glow.
static func _scorch(albedo: Image, emission: Image, random: SimRandom, type: String, colour: Color, ground: Color) -> bool:
	var n := albedo.get_width()
	var edge := _edge(random, 7)
	var mid := ground.darkened(0.55)
	var glows := false
	for y in n:
		for x in n:
			var p := _polar(n, x, y)
			var reach := _edge_at(edge, p.y) * 0.9
			if p.x > reach:
				continue
			var fleck := random.next_float()
			if p.x > reach * 0.8 and fleck < 0.45:
				continue
			if p.x < reach * 0.5 or (p.x < reach * 0.7 and fleck < 0.5):
				albedo.set_pixel(x, y, CHAR)
				if type == "Fire" and p.x < reach * 0.6 and fleck < 0.08:
					albedo.set_pixel(x, y, EMBER)
					emission.set_pixel(x, y, EMBER)
					glows = true
			else:
				albedo.set_pixel(x, y, mid)
				if type not in ["Fire", "Electric"] and p.x > reach * 0.72 and fleck > 0.8:
					albedo.set_pixel(x, y, colour)
					emission.set_pixel(x, y, colour)
					glows = true
	if type == "Electric":
		for fork in 5:
			var angle := TAU * (fork + random.range_float(-0.3, 0.3)) / 5.0
			for pixel in _walk(random, Vector2(n, n) * 0.5, angle, int(n * 0.45), 0.6):
				_put(albedo, pixel.x, pixel.y, colour)
				_put(emission, pixel.x, pixel.y, colour)
		glows = true
	return glows


## Frost: a pale icy fill with six spiky arms of light ice and short branches, flecked deeper.
static func _frost(albedo: Image, random: SimRandom) -> void:
	var n := albedo.get_width()
	var edge := _edge(random, 6)
	for y in n:
		for x in n:
			var p := _polar(n, x, y)
			var reach := _edge_at(edge, p.y) * 0.55
			if p.x < reach and random.next_float() < 1.0 - p.x / reach * 0.5:
				albedo.set_pixel(x, y, FROST_DEEP if random.next_float() < 0.15 else FROST_FILL)
	var turn := random.range_float(0.0, TAU)
	for arm in 6:
		var angle := turn + TAU * arm / 6.0
		var pixels := _walk(random, Vector2(n, n) * 0.5, angle, int(n * random.range_float(0.38, 0.48)), 0.12)
		for i in pixels.size():
			_put(albedo, pixels[i].x, pixels[i].y, FROST_LIGHT)
			if i > 3 and i % 4 == 0:
				for side in [-1.0, 1.0]:
					for twig in _walk(random, Vector2(pixels[i]) + Vector2(0.5, 0.5), angle + side * 1.0, 3 + random.next_u32() % 3, 0.1):
						_put(albedo, twig.x, twig.y, FROST_LIGHT)


## A splash stain in the type's colour: a lobed blob, shaded darker toward its edge, with
## droplets flung around it.
static func _splash(albedo: Image, random: SimRandom, colour: Color) -> void:
	var n := albedo.get_width()
	var edge := _edge(random, 9)
	var dark := colour.darkened(0.35)
	var light := colour.lightened(0.25)
	for y in n:
		for x in n:
			var p := _polar(n, x, y)
			var reach := _edge_at(edge, p.y) * 0.6
			if p.x > reach:
				continue
			var shade := dark if p.x > reach * 0.75 else colour
			if p.x < reach * 0.35 and random.next_float() < 0.2:
				shade = light
			albedo.set_pixel(x, y, shade)
	for drop in 10:
		var angle := random.range_float(0.0, TAU)
		var distance := random.range_float(0.65, 0.95) * n * 0.5
		var at := Vector2(n, n) * 0.5 + Vector2.from_angle(angle) * distance
		var big := random.next_float() < 0.3
		for dx in (2 if big else 1):
			for dy in (2 if big else 1):
				_put(albedo, floori(at.x) + dx, floori(at.y) + dy, dark)


## Cracks: a dark pit at the centre and jagged lines running out from it, branching, edged in
## a shade between the crack and the ground. Ground-shaking moves of a type with a colour of
## its own show a few of its pixels in the pit.
static func _cracks(albedo: Image, random: SimRandom, ground: Color, colour: Color, type: String) -> void:
	var n := albedo.get_width()
	var deep := ground.darkened(0.65)
	var lip := ground.darkened(0.35)
	var lines: Array[Vector2i] = []
	var count := 6 + random.next_u32() % 3
	for i in count:
		var angle := TAU * (i + random.range_float(-0.3, 0.3)) / count
		var pixels := _walk(random, Vector2(n, n) * 0.5, angle, int(n * random.range_float(0.3, 0.47)), 0.5)
		lines.append_array(pixels)
		if pixels.size() > 8:
			var at: Vector2 = Vector2(pixels[pixels.size() / 2]) + Vector2(0.5, 0.5)
			lines.append_array(_walk(random, at, angle + random.range_float(-1.2, 1.2), int(n * 0.12), 0.5))
	for pixel in lines:
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var near := pixel + offset
			if near.x >= 0 and near.y >= 0 and near.x < n and near.y < n and albedo.get_pixel(near.x, near.y).a == 0.0:
				albedo.set_pixel(near.x, near.y, lip)
	for pixel in lines:
		_put(albedo, pixel.x, pixel.y, deep)
	var pit := n * 0.07
	for y in n:
		for x in n:
			if Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() < pit:
				albedo.set_pixel(x, y, deep if random.next_float() > 0.2 or type in ["Normal", "Ground", "Rock"] else colour)


## A crater ring: a raised rim of lighter, broken ground around a floor of darker ground with
## rubble, scorched (with glowing embers) for Fire and touched with the type's colour otherwise.
static func _crater(albedo: Image, emission: Image, random: SimRandom, ground: Color, colour: Color, type: String) -> bool:
	var n := albedo.get_width()
	var edge := _edge(random, 11)
	var rim := ground.lightened(0.18)
	var floor_ := ground.darkened(0.3)
	var rubble := ground.darkened(0.55)
	var glows := false
	for y in n:
		for x in n:
			var p := _polar(n, x, y)
			var reach := _edge_at(edge, p.y) * 0.95
			if p.x > reach:
				continue
			var roll := random.next_float()
			if p.x > reach * 0.72:
				if roll < 0.75 - (p.x - reach * 0.72) / (reach * 0.28) * 0.5:
					albedo.set_pixel(x, y, rim if roll > 0.12 else rubble)
			elif p.x > reach * 0.6:
				albedo.set_pixel(x, y, rubble)
			elif roll < 0.55:
				albedo.set_pixel(x, y, floor_)
				if type == "Fire" and p.x < reach * 0.4:
					albedo.set_pixel(x, y, CHAR if roll > 0.05 else EMBER)
					if roll <= 0.05:
						emission.set_pixel(x, y, EMBER)
						glows = true
				elif type not in ["Normal", "Ground", "Rock", "Fighting", "Steel"] and roll < 0.06:
					albedo.set_pixel(x, y, colour)
			elif roll < 0.62:
				albedo.set_pixel(x, y, rubble)
	return glows


## `image` turned by `angle` about its centre, pixel for pixel.
static func _turned(image: Image, angle: float) -> Image:
	if is_zero_approx(angle):
		return image
	var n := image.get_width()
	var turned := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var centre := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var from := (Vector2(x + 0.5, y + 0.5) - centre).rotated(-angle) + centre
			var fx := floori(from.x)
			var fy := floori(from.y)
			if fx >= 0 and fy >= 0 and fx < n and fy < n:
				turned.set_pixel(x, y, image.get_pixel(fx, fy))
	return turned


## Scuffs: skid streaks along +x (turned along the blow afterwards), dark gouges with a
## lighter spray of ground at their ends.
static func _scuff(albedo: Image, random: SimRandom, ground: Color) -> void:
	var n := albedo.get_width()
	var gouge := ground.darkened(0.45)
	var spray := ground.lightened(0.15)
	for streak in 5:
		var y := int(n * 0.5 + random.range_float(-0.2, 0.2) * n)
		var start := int(random.range_float(0.1, 0.35) * n)
		var end := int(random.range_float(0.6, 0.9) * n)
		for x in range(start, end):
			if random.next_float() < 0.9:
				_put(albedo, x, y, gouge)
			if random.next_float() < 0.15:
				y = clampi(y + (1 if random.next_float() < 0.5 else -1), 1, n - 2)
		for fleck in 4:
			_put(albedo, end + random.next_u32() % 3, y + int(random.range_float(-2, 3)), spray)
