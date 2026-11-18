class_name BattleMarks
extends Node3D
## Battlefield marks (concepts_brief.md §12.5): hits leave marks on the arena's ground by move
## style and type (scorch, frost, cracks, crater rings, splash stains, scuffs), and area and
## ground-shaking moves throw debris that settles where it lands. They last the whole battle, up
## to CAP at once: past that, the oldest dissolves away in steps. Presentation only.
##
## - Marks are painted into a canvas over the field, MarkTextures.PIXELS_PER_METRE pixels a
##   metre, that the arena's surface shader draws on its upward faces (Arena.set_marks): one
##   texture read per pixel of ground however many marks there are, on the same pixel grid as the
##   ground's grain, and never on fighters, effects or the crowd. Projected decals cost the GPU
##   several milliseconds a frame at the cap.
## - Glowing pixels (embers, sparks) go into a second canvas whose alpha holds the frame they were
##   made on, so the shader cools them in steps without repainting.
## - Each mark's randomness (its drawing, turn and debris) comes from the battle seed and the
##   mark's key, not from what was shown before, so a clip that starts mid-battle (marks made
##   during the skip ahead, already settled) shows the same ground as the whole battle.
## - Debris is one pooled MultiMesh of DEBRIS_POOL chunks; the oldest chunk is reused when the
##   pool is full.
## - Nothing here knows how many fighters there are: callers place marks in the world.

const CAP := 40
## The oldest mark's fade, in video frames and dissolve steps.
const FADE_FRAMES := 30
const FADE_STEPS := 4
## The canvas covers this square of floor, centred on the arena: the field and the edge of
## the largest mark at its wall.
const CANVAS_METRES := 34.0
## Fresh burns and sparks glow, cooling to nothing in steps.
const GLOW_FRAMES := 60
const GLOW_STEPS := 5
const GLOW_ENERGY := 3.0
## Glow canvas alphas count frames round this cycle (one value is kept for "not glowing").
const GLOW_CYCLE := 254
## A hit's mark radius, from a light hit to one taking HEAVY_SHARE of the defender's HP or
## more; critical and super-effective hits are BIG_FACTOR larger.
const HIT_RADIUS := Vector2(0.45, 1.3)
const HEAVY_SHARE := 0.3
const BIG_FACTOR := 1.15
## Area moves' marks cover about this share of the move's reach around the user.
const AREA_SHARE := 0.7
const GROUND_RADIUS := 1.2
const SKY_RADIUS := 1.0
const BLOCKED_RADIUS := 0.4
const DEBRIS_POOL := 120
const DEBRIS_PER_MARK := Vector2i(8, 13)
const DEBRIS_SIZE := Vector2(0.06, 0.15)
const GRAVITY := 18.0
## How a chunk is flung: outward and upward speeds in m/s.
const FLING_OUT := Vector2(1.2, 3.5)
const FLING_UP := Vector2(3.0, 6.0)
const BOUNCE := 0.3
## A chunk still flying after this many frames is set down where it is.
const MAX_FLIGHT := 90
const STREAM := 103
const SPLASH_TYPES: Array[String] = ["Water", "Poison", "Grass", "Bug"]
const EARTH_TYPES: Array[String] = ["Ground", "Rock", "Steel", "Fighting"]
const SCUFF_TYPES: Array[String] = ["Normal", "Flying"]
const GROUND_STYLES: Array[String] = ["quake", "erupt"]
const CRATER_STYLES: Array[String] = ["skyfall", "explosion"]
const FRAME := 1.0 / Rules.TICK_RATE

## Where the canvas's first pixel's corner is on the floor.
var origin := Vector2.ONE * -CANVAS_METRES * 0.5
## The canvases the arena draws: marks' colours, and their glows.
var albedo_texture: ImageTexture
var glow_texture: ImageTexture
## Marks shown, oldest first: {"image": Image (as drawn now, dissolved while fading), "whole":
## Image, "glow": Image (its glowing pixels, stamped with the frame) or null, "rect": Rect2i on
## the canvas, "born": frame made, "key": int, "level": dissolve steps left (FADE_STEPS when
## whole), "fade": frames left fading (-1 while not), "chunks": pool indices of its debris}.
var _marks: Array[Dictionary] = []
var _canvas: Image
var _glow_canvas: Image
var _dirty := false
var _frame := 0
var _textures := MarkTextures.new()
## "pixels|level" -> Image whose opaque pixels are those a mark keeps at that dissolve level.
var _dissolves := {}
var _base := 0
var _arena: Arena
var _debris: MultiMeshInstance3D
## The pool: {"position", "velocity", "spin", "turn", "size", "flying", "frames", "bounced",
## "mark" (its mark's key, or -1 when free), "used" (when it was thrown)}.
var _chunks: Array[Dictionary] = []
var _thrown := 0


## Marks on `arena`'s ground, from the battle's seed.
func setup(battle_seed: int, arena: Arena) -> void:
	_base = SimRandom.stream(battle_seed, STREAM).next_u32()
	_arena = arena
	var pixels := roundi(CANVAS_METRES * MarkTextures.PIXELS_PER_METRE)
	_canvas = Image.create(pixels, pixels, false, Image.FORMAT_RGBA8)
	_glow_canvas = Image.create(pixels, pixels, false, Image.FORMAT_RGBA8)
	albedo_texture = ImageTexture.create_from_image(_canvas)
	glow_texture = ImageTexture.create_from_image(_glow_canvas)
	arena.set_marks(albedo_texture, glow_texture, origin, GLOW_FRAMES, GLOW_STEPS, GLOW_ENERGY)
	arena.set_marks_frame(frame_code())
	_build_debris()


## Draws ahead every mark `pairs` ([kind, type] each) can leave, so drawing one never holds up
## a frame mid-battle.
func prepare(pairs: Array) -> void:
	for pair: Array in pairs:
		for variant in MarkTextures.VARIANTS:
			for direction in (MarkTextures.DIRECTIONS if pair[0] == "scuff" else 1):
				_textures.get_images(pair[0], pair[1], variant, _arena.ground_colour(), direction)


## The marks a move can leave: [kind, type] pairs (a hit and, for area moves, its blast).
static func kinds_for(style: String, type: String, melee: bool, area: bool) -> Array:
	var kinds := [[describe(style, type, melee, false, 0.0, false).kind, type]]
	if area:
		kinds.append([describe(style, type, melee, true, 0.0, false).kind, type])
	return kinds


## What a hit leaves: {"kind", "radius", "debris", "along" (turned along the blow)}. `area`
## for an area move's blast around its user; `share` is the share of the defender's HP taken.
static func describe(style: String, type: String, melee: bool, area: bool, share: float, big: bool) -> Dictionary:
	if area or style in GROUND_STYLES:
		var kind := "cracks" if style in GROUND_STYLES or type in EARTH_TYPES else "crater"
		var radius := Rules.AREA_RADIUS * AREA_SHARE if area else GROUND_RADIUS
		return {"kind": kind, "radius": radius, "debris": true, "along": false}
	if style in CRATER_STYLES:
		return {"kind": "crater", "radius": SKY_RADIUS * (BIG_FACTOR if big else 1.0), "debris": true, "along": false}
	var radius := lerpf(HIT_RADIUS.x, HIT_RADIUS.y, clampf(share / HEAVY_SHARE, 0.0, 1.0)) * (BIG_FACTOR if big else 1.0)
	var kind := "scorch"
	if type == "Ice":
		kind = "frost"
	elif type in SPLASH_TYPES:
		kind = "splash"
	elif type in SCUFF_TYPES or (melee and type in EARTH_TYPES):
		kind = "scuff"
	elif type in EARTH_TYPES:
		kind = "cracks"
	return {"kind": kind, "radius": radius, "debris": false, "along": kind == "scuff"}


## Leaves a mark centred on `at` (on the floor), `ground` high where the arena has no built
## ground there. `along` is the blow's direction on the floor, for marks turned along it. `key`
## tells this mark apart from every other in the battle (the same key gives the same mark). A
## `settled` mark is shown as it ends up: no glow, its debris already landed.
func add(description: Dictionary, type: String, at: Vector2, ground: float, along: Vector2, key: int, settled := false) -> void:
	var random := SimRandom.new(_base ^ SimRandom.mul32(key + 1, 0x85EBCA6B))
	var kind: String = description.kind
	var radius: float = description.radius
	var variant := int(random.next_u32() % MarkTextures.VARIANTS)
	var turn := int(random.next_u32() % 8)
	var direction := 0
	if description.along:
		direction = posmod(roundi(along.angle() / TAU * MarkTextures.DIRECTIONS), MarkTextures.DIRECTIONS)
		turn = 0
	var drawn := _textures.get_images(kind, type, variant, _arena.ground_colour(), direction)
	var pixels := maxi(4, roundi(radius * 2.0 * MarkTextures.PIXELS_PER_METRE))
	var centre := ((at - origin) * MarkTextures.PIXELS_PER_METRE).floor()
	var rect := Rect2i(Vector2i(centre) - Vector2i.ONE * (pixels / 2), Vector2i.ONE * pixels)
	var glow: Image = null
	if drawn.emission != null and not settled:
		# Each mark glows in one colour, so the frame goes into the alpha with one fill.
		var shape := _prepared(drawn.emission, pixels, turn)
		var colour: Color = drawn.glow_colour
		var stamp := Image.create(pixels, pixels, false, Image.FORMAT_RGBA8)
		stamp.fill(Color(colour.r, colour.g, colour.b, (_frame % GLOW_CYCLE + 1) / 255.0))
		glow = Image.create(pixels, pixels, false, Image.FORMAT_RGBA8)
		glow.blit_rect_mask(stamp, shape, Rect2i(Vector2i.ZERO, shape.get_size()), Vector2i.ZERO)
	var image := _prepared(drawn.albedo, pixels, turn)
	var mark := {"image": image, "whole": image, "glow": glow, "rect": rect, "born": _frame,
		"key": key, "level": FADE_STEPS, "fade": -1, "chunks": []}
	_marks.append(mark)
	_paint(mark, rect)
	_dirty = true
	if description.debris:
		var height := _ground(at, ground)
		_throw(mark, type, Vector3(at.x, height, at.y), radius, random, settled)
	_cap()
	_upload()


## Marks shown (fading ones included).
func count() -> int:
	return _marks.size()


## Chunks of debris out, flying or settled.
func debris_count() -> int:
	return _chunks.filter(func(chunk: Dictionary) -> bool: return int(chunk.mark) >= 0).size()


## The canvas's colour under `point` on the floor (clear where unmarked).
func colour_at(point: Vector2) -> Color:
	return _canvas_pixel(_canvas, point)


## The glow canvas under `point`: its colour, and in alpha the frame code it was made on.
func glow_at(point: Vector2) -> Color:
	return _canvas_pixel(_glow_canvas, point)


## The marks' clock as the shader reads it (glow canvas alphas count from it).
func frame_code() -> float:
	return float(_frame % GLOW_CYCLE)


func next_frame() -> void:
	_frame += 1
	for mark in _marks.duplicate():
		if mark.glow != null and _frame - int(mark.born) >= GLOW_FRAMES:
			mark.glow = null
			_repaint(mark.rect)
		if int(mark.fade) >= 0:
			mark.fade = int(mark.fade) - 1
			var level := ceili(float(mark.fade) / FADE_FRAMES * FADE_STEPS)
			if level != int(mark.level):
				mark.level = level
				mark.image = _dissolved(mark.whole, level)
				mark.glow = null
				for index: int in mark.chunks:
					if int(_chunks[index].mark) == int(mark.key):
						_place(index, float(level) / FADE_STEPS)
				if level <= 0:
					_drop(mark)
				_repaint(mark.rect)
	_upload()
	_arena.set_marks_frame(frame_code())
	for index in _chunks.size():
		var chunk := _chunks[index]
		if int(chunk.mark) >= 0 and chunk.flying:
			_fly(chunk)
			_place(index)


func _canvas_pixel(canvas: Image, point: Vector2) -> Color:
	var pixel := Vector2i(((point - origin) * MarkTextures.PIXELS_PER_METRE).floor())
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= canvas.get_width() or pixel.y >= canvas.get_height():
		return Color(0, 0, 0, 0)
	return canvas.get_pixel(pixel.x, pixel.y)


## A mark's drawing sized to `pixels` (nearest, so its pixels stay square) and turned by right
## angles and a flip (`turn`, 0-7), for variety.
static func _prepared(source: Image, pixels: int, turn: int) -> Image:
	var image := source.duplicate() as Image
	image.resize(pixels, pixels, Image.INTERPOLATE_NEAREST)
	for i in turn % 4:
		image.rotate_90(CLOCKWISE)
	if turn >= 4:
		image.flip_x()
	return image


## Paints `mark` into the canvases within `clip`, dissolved to its level: a share of its pixels
## (picked by a hash, so the same ones go first every time) drops out per step.
func _paint(mark: Dictionary, clip: Rect2i) -> void:
	var rect: Rect2i = mark.rect
	var inside := rect.intersection(clip).intersection(Rect2i(Vector2i.ZERO, _canvas.get_size()))
	if inside.size.x <= 0 or inside.size.y <= 0:
		return
	var source := Rect2i(inside.position - rect.position, inside.size)
	var image: Image = mark.image
	var glow: Image = mark.glow
	_canvas.blit_rect_mask(image, image, source, inside.position)
	if glow != null:
		_glow_canvas.blit_rect_mask(glow, glow, source, inside.position)


## `image` with only the pixels it keeps at dissolve `level`.
func _dissolved(image: Image, level: int) -> Image:
	var size := image.get_size()
	var key := "%d|%d" % [size.x, level]
	if not _dissolves.has(key):
		var mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		for y in size.y:
			for x in size.x:
				if (SimRandom.mul32(x * 73856093 ^ y * 19349663, 0x9E3779B9) >> 16) % FADE_STEPS < level:
					mask.set_pixel(x, y, Color.WHITE)
		_dissolves[key] = mask
	var kept := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	kept.blit_rect_mask(image, _dissolves[key], Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	return kept


## Clears `rect` of both canvases and paints back every mark over it, oldest first.
func _repaint(rect: Rect2i) -> void:
	_canvas.fill_rect(rect, Color(0, 0, 0, 0))
	_glow_canvas.fill_rect(rect, Color(0, 0, 0, 0))
	for mark in _marks:
		if (mark.rect as Rect2i).intersects(rect):
			_paint(mark, rect)
	_dirty = true


func _upload() -> void:
	if _dirty:
		albedo_texture.update(_canvas)
		glow_texture.update(_glow_canvas)
		_dirty = false


func _ground(at: Vector2, fallback: float) -> float:
	return _arena.surface_at(at, fallback)


## Starts the oldest marks fading once more than CAP are left that aren't.
func _cap() -> void:
	var standing := _marks.filter(func(mark: Dictionary) -> bool: return int(mark.fade) < 0)
	for i in maxi(0, standing.size() - CAP):
		standing[i].fade = FADE_FRAMES


func _drop(mark: Dictionary) -> void:
	for index: int in mark.chunks:
		if int(_chunks[index].mark) == int(mark.key):
			_free_chunk(index)
	_marks.erase(mark)


func _build_debris() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shape := RandomNumberGenerator.new()
	shape.seed = 7
	LowPoly.frustum(tool, Color.WHITE, Vector3(0, -0.5, 0), 0.6, 0.35, 1.0, 5, 0.3, 0.3, shape)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = tool.commit()
	multimesh.instance_count = DEBRIS_POOL
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	_debris = MultiMeshInstance3D.new()
	_debris.multimesh = multimesh
	_debris.material_override = material
	add_child(_debris)
	for index in DEBRIS_POOL:
		_chunks.append({"mark": -1, "used": -1})
		_free_chunk(index)


func _free_chunk(index: int) -> void:
	_chunks[index].mark = -1
	_debris.multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3.DOWN * 50.0))


## A free chunk, or the one thrown longest ago.
func _take_chunk() -> int:
	var oldest := 0
	for index in _chunks.size():
		if int(_chunks[index].mark) < 0:
			return index
		if int(_chunks[index].used) < int(_chunks[oldest].used):
			oldest = index
	return oldest


## Flings chunks of the ground (and a few of the type's colour) out of the mark.
func _throw(mark: Dictionary, type: String, centre: Vector3, radius: float, random: SimRandom, settled: bool) -> void:
	var amount := DEBRIS_PER_MARK.x + int(random.next_u32() % (DEBRIS_PER_MARK.y - DEBRIS_PER_MARK.x + 1))
	var tinted := MarkTextures.FROST_LIGHT if type == "Ice" else MarkTextures.CHAR if type == "Fire" else TypeColors.of(type)
	var ground := _arena.ground_colour()
	for i in amount:
		var index := _take_chunk()
		var angle := random.range_float(0.0, TAU)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var colour := ground.darkened(random.range_float(0.0, 0.35))
		if type not in ["Normal", "Ground", "Rock"] and random.next_float() < 0.35:
			colour = tinted
		_thrown += 1
		_chunks[index] = {"mark": mark.key, "used": _thrown, "flying": true, "frames": 0, "bounced": false,
			"position": centre + out * radius * random.range_float(0.1, 0.4) + Vector3.UP * 0.1,
			"velocity": out * random.range_float(FLING_OUT.x, FLING_OUT.y) + Vector3.UP * random.range_float(FLING_UP.x, FLING_UP.y),
			"spin": Vector3(random.range_float(-9, 9), random.range_float(-9, 9), random.range_float(-9, 9)),
			"turn": Vector3(random.range_float(0, TAU), random.range_float(0, TAU), 0.0),
			"size": random.range_float(DEBRIS_SIZE.x, DEBRIS_SIZE.y), "ground": centre.y}
		_debris.multimesh.set_instance_color(index, colour)
		(mark.chunks as Array).append(index)
		if settled:
			while _chunks[index].flying:
				_fly(_chunks[index])
		_place(index)


## One frame of a chunk's flight: it falls, bounces once off the ground and then lies there,
## half sunk.
func _fly(chunk: Dictionary) -> void:
	chunk.frames = int(chunk.frames) + 1
	var velocity: Vector3 = chunk.velocity
	velocity.y -= GRAVITY * FRAME
	var position: Vector3 = chunk.position + velocity * FRAME
	chunk.turn = (chunk.turn as Vector3) + (chunk.spin as Vector3) * FRAME
	var floor_at := _ground(Vector2(position.x, position.z), float(chunk.ground))
	var size: float = chunk.size
	if position.y <= floor_at + size * 0.5 and velocity.y < 0.0 or int(chunk.frames) >= MAX_FLIGHT:
		if not chunk.bounced and velocity.y < -2.0 and int(chunk.frames) < MAX_FLIGHT:
			chunk.bounced = true
			velocity = Vector3(velocity.x * 0.5, -velocity.y * BOUNCE, velocity.z * 0.5)
			chunk.spin = (chunk.spin as Vector3) * 0.5
			position.y = floor_at + size * 0.5
		else:
			chunk.flying = false
			position.y = floor_at + size * 0.2
	chunk.velocity = velocity
	chunk.position = position


func _place(index: int, scale := 1.0) -> void:
	var chunk := _chunks[index]
	var size: float = chunk.size * maxf(scale, 0.0001)
	var turn: Vector3 = chunk.turn
	_debris.multimesh.set_instance_transform(index, Transform3D(Basis.from_euler(turn).scaled(Vector3.ONE * size), chunk.position))
