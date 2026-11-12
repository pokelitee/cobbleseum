class_name Arena
extends Node3D
## The world around the battle (concepts_brief.md §12.7), from an arena preset (Arenas): the
## battle's own field (Terrain, §9.8) with its features and small details (ArenaFields), the
## venue around it (open land out to Terrain.WORLD_RADIUS with props on the hills, or a
## coliseum built by Stadium), and the preset's sky, sun, fog and weather. Everything is seeded
## by the battle, so every render of a battle is identical.
##
## Everything is blocks in the voxel style of Cobblemon's models: boxes drawn through
## MultiMeshes, and curved blocks (ring segments) built as exact meshes so rings have no gaps
## or overlaps. A surface shader (arena_surface.gdshader) adds pixel grain lined up with each
## face, and grime, so no outside art is needed.

## The battle floor's edge (the stadium's field), just past the simulation's wall.
const FLOOR_RADIUS := Rules.ARENA_RADIUS + 0.5
## Props on the land beyond the arena start just past its wall, densest in EDGE_BAND (they mark
## the edge, like a treeline), thinner further out.
const PROP_RADIUS := Rules.ARENA_RADIUS + 1.5
const EDGE_BAND := 3.0
const EDGE_DENSITY := 3.0
## Patch noise above this gives the patch colour (paths, gravel, ash).
const PATCH_THRESHOLD := 0.3
## Details grow where their own noise is above this (about half the ground), in patches.
const DETAIL_PATCH := 0.0
## Details are at full density out to DETAIL_FULL and thin out to none at DETAIL_END: the
## battle camera sees the arena and the treeline up close, and fog hides the hills beyond.
const DETAIL_FULL := Rules.ARENA_RADIUS + 6.0
const DETAIL_END := Rules.ARENA_RADIUS + 16.0
## Ground corners are nudged off the grid by up to this much, so it doesn't read as squares.
const CORNER_JITTER := 0.18
## Features' bases sink this far, so they sit in the faceted ground rather than on a corner.
const SINK := 0.3
## Where spectators may sit outside a stadium: ground this far out, at most this high.
const SEAT_RANGE := Vector2(FLOOR_RADIUS + 3.0, FLOOR_RADIUS + 12.0)
const SEAT_MAX_HEIGHT := 3.0
const WATER_SIZE := 240.0
const PARTICLE_AREA := Vector3(FLOOR_RADIUS * 3.0, 8, FLOOR_RADIUS * 3.0)
const SURFACE_SHADER := preload("res://game/presentation/arena/arena_surface.gdshader")
## Cameras stay this far inside the stadium's wall; elsewhere they may go CAMERA_OVERHANG past
## the arena's (see-through keeps the fighters in view if the land is in the way).
const CAMERA_MARGIN := 1.0
const CAMERA_OVERHANG := 2.0
## Curved faces are split every this many metres along the arc, so they look round.
const ARC_STEP := 0.25
## Ring blocks are about this long.
const RING_BLOCK := 1.0

var preset_name := ""
## The coliseum's colours (Stadium.theme), for an enclosed venue.
var theme := {}
## Places a spectator can stand, facing the floor's centre (world transforms).
var seats: Array[Transform3D] = []
## How far from the centre a camera may go before it would be inside the scenery.
var camera_limit := Rules.ARENA_RADIUS + CAMERA_OVERHANG

var _biome: Dictionary
## The battle's ground: the floor is built at its heights.
var _terrain: Terrain
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
## Blocks to draw: [Transform3D, Color], plain and glowing.
var _blocks: Array = []
var _glowing: Array = []
## Ring segments, built straight into meshes: {glow: SurfaceTool}.
var _arcs := {}
## The surface shader's materials, for see-through updates.
var _surfaces: Array[ShaderMaterial] = []
## How far the faceted ground is built: the whole world, or just the field inside a coliseum.
var _land_radius := Terrain.WORLD_RADIUS
var _enclosed := false
## Ground height by cell beyond the arena, so props sit on top.
var _heights := {}
## Each built cell's four corner heights ([-x-z, +x-z, +x+z, -x+z]), for surface_at().
var _tops := {}


## Builds the arena preset `name` (Arenas) seeded by `seed`, around the battle's `terrain`
## (flat if not given). `names` are the fighters' names, for the stadium's screens.
static func create(name: String, seed: int, names: Array = [], terrain: Terrain = null) -> Arena:
	var preset := Arenas.preset(name)
	assert(not preset.is_empty(), "unknown arena '%s'" % name)
	var arena := Arena.new()
	arena.name = "Arena"
	arena.preset_name = name
	arena._enclosed = Arenas.enclosed(name)
	arena._biome = _look(preset)
	if arena._enclosed:
		arena.theme = Stadium.theme(preset.get("theme", {}))
		arena._biome.moss = arena.theme.moss
		arena._biome.erase("water")
	arena._rng.seed = hash("%s|%d" % [name, seed])
	arena._noise.seed = seed
	arena._noise.frequency = 0.06
	if terrain == null:
		terrain = Terrain.flat(preset.field)
		terrain.enclosed = arena._enclosed
	arena._terrain = terrain
	arena._terrain.fill_world()
	arena._build(names)
	return arena


## The field's look (ArenaFields) under the preset's sky, light, fog and weather, read from
## its JSON (colours as "#rrggbb").
static func _look(preset: Dictionary) -> Dictionary:
	var look: Dictionary = ArenaFields.FIELDS[preset.field].duplicate()
	look.sky = (preset.sky as Array).map(func(c: String) -> Color: return Color.html(c))
	var angle: Array = preset.sun.angle
	look.sun = {"angle": Vector3(angle[0], angle[1], angle[2]), "colour": Color.html(preset.sun.colour), "energy": float(preset.sun.energy)}
	look.ambient = [Color.html(preset.ambient.colour), float(preset.ambient.energy)]
	look.fog = [Color.html(preset.fog.colour), float(preset.fog.density)]
	look.particles = str(preset.get("particles", ""))
	return look


func _build(names: Array) -> void:
	if _enclosed:
		Stadium.build(self, _rng, names, _terrain.field != "paved")
		camera_limit = Stadium.wall_radius() - CAMERA_MARGIN
	else:
		build_landscape(Terrain.WORLD_RADIUS)
		_build_props()
	_add_blocks(_blocks, false)
	_add_blocks(_glowing, true)
	for glow: bool in [false, true]:
		if _arcs.has(glow):
			_add_arc_mesh(_arcs[glow], glow)
	if _biome.has("water"):
		_add_water(float(_biome.water))
	_add_environment()
	_add_particles(str(_biome.particles))


func _colour(index: int) -> Color:
	return _biome.colours[index]


## Slight per-block shade variation, so flat areas don't look painted on.
func vary(colour: Color, amount := 0.04) -> Color:
	var shade := 1.0 + _rng.randf_range(-amount, amount)
	return Color(colour.r * shade, colour.g * shade, colour.b * shade)


func cells(radius: float) -> Array[Vector2]:
	var cells: Array[Vector2] = []
	var reach := ceili(radius)
	for i in range(-reach, reach):
		for j in range(-reach, reach):
			var centre := Vector2(i + 0.5, j + 0.5)
			if centre.length() <= radius:
				cells.append(centre)
	return cells


## A block with any transform (a unit box scaled, rotated and placed by `transform`).
func add_block(transform: Transform3D, colour: Color, glow := false) -> void:
	(_glowing if glow else _blocks).append([transform, colour])


## A block on a ring centred at `angle` (radians, from +x toward +z), from `inner` to
## `outer` metres out and `bottom` to `top` high, `width` long along the ring's middle.
func add_arc(angle: float, inner: float, outer: float, bottom: float, top: float, colour: Color, width: float, glow := false) -> void:
	var span := width / maxf((inner + outer) * 0.5, 0.01)
	add_sector(angle - span * 0.5, angle + span * 0.5, inner, outer, bottom, top, colour, glow)


## A whole ring of blocks about RING_BLOCK long, shaded slightly block by block, alternating
## with `alternate` if one is given. The blocks meet exactly.
func add_arc_ring(inner: float, outer: float, bottom: float, top: float, colour: Color, rng: RandomNumberGenerator,
		variation: float, alternate := Color(0, 0, 0, 0)) -> void:
	var segments := maxi(8, ceili(TAU * (inner + outer) * 0.5 / RING_BLOCK))
	for s in segments:
		var base := alternate if alternate.a > 0.0 and s % 2 == 1 else colour
		var shade := 1.0 + rng.randf_range(-variation, variation)
		add_sector(s * TAU / segments, (s + 1) * TAU / segments, inner, outer, bottom, top,
			Color(base.r * shade, base.g * shade, base.b * shade))


## A ring segment between angles `from` and `to`: its top and underside, its inner and
## outer faces (split every ARC_STEP so they look round) and its two ends. UV holds each
## face's metres, for the surface shader's pixel grid. The underside matters for what floats
## (the roof); with `inner` at 0 the segment is a wedge.
func add_sector(from: float, to: float, inner: float, outer: float, bottom: float, top: float, colour: Color, glow := false) -> void:
	var tool := _mesh_tool(glow)
	var steps := maxi(1, ceili((to - from) * maxf(outer, 0.01) / ARC_STEP))
	var up_top := Vector3.UP * top
	var up_bottom := Vector3.UP * bottom
	for i in steps:
		var a := lerpf(from, to, float(i) / steps)
		var b := lerpf(from, to, float(i + 1) / steps)
		var da := Vector3(cos(a), 0, sin(a))
		var db := Vector3(cos(b), 0, sin(b))
		var along_a := a - from
		var along_b := b - from
		var flat_uvs := [Vector2(along_a * inner, 0), Vector2(along_b * inner, 0),
			Vector2(along_b * outer, outer - inner), Vector2(along_a * outer, outer - inner)]
		for level: Array in [[up_top, Vector3.UP], [up_bottom, Vector3.DOWN]]:
			_quad(tool, colour, level[1],
				[da * inner + level[0], db * inner + level[0], db * outer + level[0], da * outer + level[0]], flat_uvs)
		var out := (da + db).normalized()
		for face: Array in [[outer, out], [inner, -out]]:
			var r: float = face[0]
			if r <= 0.0:
				continue
			_quad(tool, colour, face[1],
				[da * r + up_bottom, db * r + up_bottom, db * r + up_top, da * r + up_top],
				[Vector2(along_a * r, 0), Vector2(along_b * r, 0), Vector2(along_b * r, top - bottom), Vector2(along_a * r, top - bottom)])
	for end: Array in [[from, -1.0], [to, 1.0]]:
		var d := Vector3(cos(end[0]), 0, sin(end[0]))
		var tangent := Vector3(-d.z, 0, d.x) * float(end[1])
		_quad(tool, colour, tangent,
			[d * inner + up_bottom, d * outer + up_bottom, d * outer + up_top, d * inner + up_top],
			[Vector2(0, 0), Vector2(outer - inner, 0), Vector2(outer - inner, top - bottom), Vector2(0, top - bottom)])


## Two triangles facing `normal`, wound to match it whatever order the corners come in.
static func _quad(tool: SurfaceTool, colour: Color, normal: Vector3, corners: Array, uvs: Array) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	# Godot's front faces wind clockwise as seen from the front. The diagonals give the
	# quad's facing even when two corners meet (a wedge's point).
	if (corners[2] - corners[0]).cross(corners[3] - corners[1]).dot(normal) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i: int in order:
		tool.set_color(colour)
		tool.set_normal(normal)
		tool.set_uv(uvs[i])
		tool.add_vertex(corners[i])


## A box from `bottom` to `top` over the cell at `centre`, `size` wide.
func add_box(centre: Vector2, bottom: float, top: float, colour: Color, size := Vector2.ONE, glow := false) -> void:
	var height := maxf(top - bottom, 0.01)
	var basis := Basis.from_scale(Vector3(size.x, height, size.y))
	var entry := [Transform3D(basis, Vector3(centre.x, bottom + height * 0.5, centre.y)), colour]
	(_glowing if glow else _blocks).append(entry)


## The faceted ground out to `radius`, with the field's features and details; in the open,
## also the heights props stand on and seats on low ground nearby.
func build_landscape(radius: float) -> void:
	_land_radius = radius
	var water: float = _biome.get("water", -INF)
	for cell in _terrain.world_cells(radius):
		var ground := _terrain.ground_at(cell)
		var steep := _steepness(cell, ground)
		_ground_cell(cell, ground, vary(_surface(cell, ground, steep, water), 0.04))
		var kind := _terrain.kind_at(cell)
		if kind != Terrain.Kind.GROUND:
			_feature(kind, cell, ground, _terrain.height_at(cell))
		elif ground > water:
			_decorate(cell, ground, steep)
		var distance := cell.length()
		if not _enclosed and distance > Rules.ARENA_RADIUS + 1.0:
			_heights[cell] = ground
			if ground >= maxf(water, 0.0) and distance >= SEAT_RANGE.x and distance <= SEAT_RANGE.y and ground <= SEAT_MAX_HEIGHT and steep < 1.0:
				add_seat(cell, ground)


## One cell of the faceted ground: its top, with each corner at the average of the cells
## around it that are within a step of this one (so walkable ground slopes smoothly and cliffs
## stay sharp), and walls down to any lower neighbour (earth, or stone where it drops a metre
## or more). Corners are nudged off the grid, the same way for every cell that shares them.
func _ground_cell(cell: Vector2, ground: float, top_colour: Color) -> void:
	var tool := _mesh_tool(false)
	var i := int(floorf(cell.x))
	var j := int(floorf(cell.y))
	var corners: Array[Vector2i] = [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
	var heights: Array[float] = []
	var points: Array = []
	for corner in corners:
		var h := _corner_height(cell, ground, corner)
		heights.append(h)
		var xz := _corner_xz(corner)
		points.append(Vector3(xz.x, h, xz.y))
	_tops[Vector2i(i, j)] = heights
	LowPoly.face(tool, top_colour, points, points.map(func(p: Vector3) -> Vector2: return Vector2(p.x, p.z)), Vector3.UP)
	# Walls close the gap along each edge where this cell and its neighbour meet at different
	# heights. Each shared edge is built once (from the -x or -z cell, or from the cell at the
	# world's rim) and seen from both sides: the two cells' edges can cross, which a one-sided
	# wall facing one way would leave half hidden.
	# Corners run -x-z, +x-z, +x+z, -x+z, so each pair of corners borders one neighbour.
	var sides := [[0, 1, Vector2(0, -1)], [1, 2, Vector2(1, 0)], [2, 3, Vector2(0, 1)], [3, 0, Vector2(-1, 0)]]
	for side: Array in sides:
		var a: int = side[0]
		var b: int = side[1]
		var neighbour: Vector2 = cell + side[2]
		var inside := neighbour.length() <= _land_radius
		if inside and (side[2].x < 0.0 or side[2].y < 0.0):
			continue
		var n_ground := _terrain.ground_at(neighbour)
		var low_a := _corner_height(neighbour, n_ground, corners[a]) if inside else -4.0
		var low_b := _corner_height(neighbour, n_ground, corners[b]) if inside else -4.0
		if absf(heights[a] - low_a) < 1e-4 and absf(heights[b] - low_b) < 1e-4:
			continue
		var drop := maxf(absf(heights[a] - low_a), absf(heights[b] - low_b))
		# Small steps are the ground's own colour, shaded (the dark earth colour made them read
		# as cracks); a metre or more is a cliff of bare stone.
		var wall := vary(_colour(2) if drop >= 1.0 else top_colour.darkened(0.18), 0.05)
		var pa: Vector3 = points[a]
		var pb: Vector3 = points[b]
		var length := Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z))
		var out := Vector3(side[2].x, 0, side[2].y)
		var quad := [pa, pb, Vector3(pb.x, low_b, pb.z), Vector3(pa.x, low_a, pa.z)]
		var uvs := [Vector2(0, heights[a]), Vector2(length, heights[b]), Vector2(length, low_b), Vector2(0, low_a)]
		LowPoly.face(tool, wall, quad, uvs, out)
		LowPoly.face(tool, wall, quad, uvs, -out)


## A corner's height for `cell`. The four cells around the corner are grouped by height (from
## the lowest, a group spans at most a step), the same way whichever cell asks, and a cell gets
## its group's average. So cells that slope together share the corner exactly, and the ground
## only parts where a group ends: a step or a cliff.
func _corner_height(cell: Vector2, ground: float, corner: Vector2i) -> float:
	var around: Array[float] = []
	for di in [-0.5, 0.5]:
		for dj in [-0.5, 0.5]:
			around.append(_terrain.ground_at(Vector2(corner.x + di, corner.y + dj)))
	around.sort()
	var groups: Array = []
	for h in around:
		if groups.is_empty() or h - (groups[-1] as Array)[0] > Terrain.STEP + 1e-4:
			groups.append([h])
		else:
			(groups[-1] as Array).append(h)
	for group: Array in groups:
		if ground >= float(group[0]) - 1e-4 and ground <= float(group[-1]) + 1e-4:
			var total := 0.0
			for h: float in group:
				total += h
			return total / group.size()
	return ground


## A corner's place on the floor, nudged off the grid by up to CORNER_JITTER.
static func _corner_xz(corner: Vector2i) -> Vector2:
	var h := hash(corner)
	var dx := (float(h & 0xffff) / 65535.0 - 0.5) * 2.0 * CORNER_JITTER
	var dy := (float((h >> 16) & 0xffff) / 65535.0 - 0.5) * 2.0 * CORNER_JITTER
	return Vector2(corner.x + dx, corner.y + dy)


## The visible ground's height under `point` (between its cell's corners), or `fallback` where
## the faceted ground isn't built (the stadium) or something stands on the cell.
func surface_at(point: Vector2, fallback: float) -> float:
	var key := Vector2i(int(floorf(point.x)), int(floorf(point.y)))
	if not _tops.has(key) or _terrain.kind_at(point) != Terrain.Kind.GROUND:
		return fallback
	var h: Array[float] = _tops[key]
	var fx := point.x - key.x
	var fy := point.y - key.y
	return lerpf(lerpf(h[0], h[1], fx), lerpf(h[3], h[2], fx), fy)


func _mesh_tool(glow: bool) -> SurfaceTool:
	var tool: SurfaceTool = _arcs.get(glow)
	if tool == null:
		tool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_arcs[glow] = tool
	return tool


## The largest height difference to a neighbouring cell's ground.
func _steepness(cell: Vector2, ground: float) -> float:
	var steep := 0.0
	for side in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		steep = maxf(steep, absf(ground - _terrain.ground_at(cell + side)))
	return steep


## A cell's top: bare stone on steep ground, patches (paths, gravel, ash, trampled snow) where
## the patch noise is high, the higher-ground colour above a metre, else the biome's ground;
## darker under water.
func _surface(cell: Vector2, ground: float, steep: float, water: float) -> Color:
	if ground <= water:
		return _colour(4).darkened(0.25)
	if steep >= 1.0:
		return _colour(2)
	if _noise.get_noise_2d(cell.x * 1.7 + 100.0, cell.y * 1.7) > PATCH_THRESHOLD:
		return _colour(1)
	return _colour(3) if ground >= 1.0 else _colour(0)


## What stands on a cell, in low-poly shapes within about its footprint and up to the battle's
## height for it (so shots stop where the rock is seen), plus canopies above the trunks. Bases
## sink a little so they sit in the faceted ground.
func _feature(kind: Terrain.Kind, at: Vector2, ground: float, top: float) -> void:
	var stone := _colour(2)
	var tool := _mesh_tool(false)
	var base := Vector3(at.x, ground - SINK, at.y)
	var tall := top - ground + SINK
	var turn := _rng.randf() * TAU
	match kind:
		Terrain.Kind.ROCK:
			LowPoly.frustum(tool, vary(stone, 0.1), base, 0.66, 0.34, tall, 6, turn, 0.22, _rng)
		Terrain.Kind.BASALT:
			LowPoly.frustum(tool, vary(stone, 0.06), base, 0.54, 0.54, tall - 0.08, 6, 0.0)
			LowPoly.frustum(tool, stone.lightened(0.18), base + Vector3.UP * (tall - 0.08), 0.54, 0.5, 0.08, 6, 0.0)
		Terrain.Kind.STALAGMITE:
			LowPoly.frustum(tool, vary(stone, 0.08), base, 0.62, 0.0, tall, 6, turn, 0.18, _rng)
		Terrain.Kind.ICE:
			LowPoly.frustum(tool, vary(Color(0.72, 0.86, 0.96), 0.04), base, 0.58, 0.04, tall, 4, turn, 0.15, _rng)
		Terrain.Kind.CRYSTAL:
			var colour: Color = [Color(0.4, 0.85, 1.0), Color(0.75, 0.45, 1.0)][_rng.randi() % 2]
			LowPoly.frustum(_mesh_tool(true), colour, base, 0.28, 0.0, tall, 6, turn)
			LowPoly.frustum(_mesh_tool(true), colour, base + Vector3(0.22, 0, 0.15), 0.18, 0.0, tall * 0.6, 6, turn)
		Terrain.Kind.TREE:
			_tree(Vector3(at.x, ground, at.y), top - ground)
		Terrain.Kind.PINE:
			_pine(Vector3(at.x, ground, at.y), top - ground)
		Terrain.Kind.PALM:
			_palm(Vector3(at.x, ground, at.y), top - ground)
		Terrain.Kind.LOG:
			var along := Vector3.RIGHT
			if _terrain.kind_at(at + Vector2.UP) == Terrain.Kind.LOG or _terrain.kind_at(at + Vector2.DOWN) == Terrain.Kind.LOG:
				along = Vector3.BACK
			var radius := (top - ground) * 0.55
			LowPoly.log_(tool, vary(Color(0.45, 0.32, 0.2), 0.06), Vector3(at.x, ground + radius * 0.8, at.y), along, 1.02, radius, 7)


func _tree(base: Vector3, trunk: float) -> void:
	var tool := _mesh_tool(false)
	LowPoly.frustum(tool, vary(Color(0.42, 0.29, 0.18)), base - Vector3.UP * SINK, 0.32, 0.24, trunk + SINK, 6, _rng.randf() * TAU)
	LowPoly.ball(tool, vary(Color(0.29, 0.52, 0.23), 0.08), base + Vector3.UP * (trunk + 0.9), 1.6, 2.4, 7, _rng.randf() * TAU, _rng)


func _pine(base: Vector3, height: float) -> void:
	var tool := _mesh_tool(false)
	LowPoly.frustum(tool, Color(0.35, 0.25, 0.17), base - Vector3.UP * SINK, 0.24, 0.2, 1.2 + SINK, 6, 0.0)
	var green := Color(0.16, 0.34, 0.24)
	for layer in 3:
		var radius := 1.35 - layer * 0.35
		var bottom := base + Vector3.UP * (0.9 + layer * height * 0.27)
		var turn := _rng.randf() * TAU
		LowPoly.frustum(tool, vary(green, 0.06), bottom, radius, 0.0, 1.7 - layer * 0.15, 7, turn, 0.08, _rng)
		LowPoly.frustum(tool, Color(0.95, 0.97, 1.0), bottom + Vector3.UP * (1.7 - layer * 0.15) * 0.62, radius * 0.38, 0.0, (1.7 - layer * 0.15) * 0.38, 7, turn)


func _palm(base: Vector3, height: float) -> void:
	var tool := _mesh_tool(false)
	var lean := Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))
	var segments := 4
	for i in segments:
		var t := float(i) / segments
		LowPoly.frustum(tool, Color(0.55, 0.42, 0.27).darkened(0.08 * (i % 2)), base + lean * t * t + Vector3.UP * height * t,
			0.22 - t * 0.05, 0.2 - t * 0.05, height / segments, 6, 0.0)
	var crown := base + lean + Vector3.UP * height
	for leaf in 5:
		var angle := TAU * leaf / 5 + _rng.randf() * 0.4
		var direction := Vector3(cos(angle), -0.35, sin(angle)).normalized()
		LowPoly.log_(tool, vary(Color(0.24, 0.55, 0.22), 0.08), crown + direction * 1.0, direction, 2.0, 0.12, 4)


## Small things on the ground that the battle ignores, in low-poly shapes: clumps of grass,
## flowers, pebbles, shells, snow drifts, glowing cracks and mushrooms. They gather in patches
## (where the detail noise is high) as small clusters, and sit on the visible ground, which
## slopes smoothly where neighbours are within a step; only cliff edges are left bare.
func _decorate(at: Vector2, ground: float, steep: float) -> void:
	var kinds: Dictionary = _biome.get("details", {})
	if steep > Terrain.STEP + 1e-4 or kinds.is_empty():
		return
	if _noise.get_noise_2d(at.x * 0.8 - 300.0, at.y * 0.8) < DETAIL_PATCH:
		return
	var fade := clampf(inverse_lerp(DETAIL_END, DETAIL_FULL, at.length()), 0.0, 1.0)
	if _rng.randf() > float(_biome.get("detail", 0.0)) * fade:
		return
	var kind := _pick_detail(kinds)
	for n in _rng.randi_range(2, 5):
		var spot := at + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))
		_detail(kind, Vector3(spot.x, surface_at(spot, ground), spot.y))


func _pick_detail(kinds: Dictionary) -> String:
	var names: Array = kinds.keys()
	names.sort()
	var total := 0.0
	for name: String in names:
		total += float(kinds[name])
	var roll := _rng.randf() * total
	for name: String in names:
		roll -= float(kinds[name])
		if roll <= 0.0:
			return name
	return names[-1]


func _detail(kind: String, at: Vector3) -> void:
	var tool := _mesh_tool(false)
	var turn := _rng.randf() * TAU
	match kind:
		"grass":
			# A tuft: a low mound with a few blades poking out. Thin blades face away from the
			# light and shade dark, so they're lighter than the meadow and the mound carries most
			# of the clump's colour; on their own they read as black spikes.
			var green := _colour(0)
			LowPoly.frustum(tool, vary(green.lightened(0.06), 0.05), at - Vector3.UP * 0.03, 0.14, 0.05, 0.12, 6, turn, 0.2, _rng)
			for blade in _rng.randi_range(2, 4):
				var offset := Vector3(_rng.randf_range(-0.08, 0.08), 0, _rng.randf_range(-0.08, 0.08))
				LowPoly.frustum(tool, vary(green.lightened(0.28), 0.06), at + offset, 0.035, 0.0,
					_rng.randf_range(0.14, 0.22), 3, _rng.randf() * TAU)
		"flower":
			var colour: Color = [Color(0.95, 0.35, 0.35), Color(1.0, 0.85, 0.3), Color(0.96, 0.96, 1.0), Color(0.72, 0.52, 0.96)][_rng.randi() % 4]
			var height := _rng.randf_range(0.13, 0.2)
			LowPoly.frustum(tool, _colour(0).darkened(0.1), at - Vector3.UP * 0.02, 0.014, 0.01, height, 4, turn)
			LowPoly.ball(tool, colour, at + Vector3.UP * (height + 0.02), 0.045, 0.045, 5, turn, _rng)
		"pebble":
			var size := _rng.randf_range(0.06, 0.13)
			LowPoly.frustum(tool, vary(_colour(2), 0.12), at - Vector3.UP * 0.02, size, size * 0.6, size * 0.7, 5, turn, 0.25, _rng)
		"shell":
			var colour: Color = [Color(0.96, 0.9, 0.84), Color(0.95, 0.72, 0.66)][_rng.randi() % 2]
			LowPoly.frustum(tool, colour, at - Vector3.UP * 0.01, 0.08, 0.0, 0.05, 5, turn)
		"drift":
			LowPoly.frustum(tool, vary(_colour(3), 0.02), at - Vector3.UP * 0.05, _rng.randf_range(0.25, 0.45), 0.12, 0.12, 6, turn, 0.2, _rng)
		"crack":
			# A short jagged line of glowing segments, flush with the ground.
			var point := at
			var heading := turn
			for segment in _rng.randi_range(2, 4):
				var length := _rng.randf_range(0.15, 0.35)
				var middle := point + Vector3(cos(heading), 0, sin(heading)) * length * 0.5
				var basis := Basis(Vector3.UP, -heading) * Basis.from_scale(Vector3(length, 0.02, 0.04))
				add_block(Transform3D(basis, middle + Vector3.UP * 0.005), Color(1.0, 0.5, 0.12), true)
				point += Vector3(cos(heading), 0, sin(heading)) * length
				heading += _rng.randf_range(-0.9, 0.9)
		"mushroom":
			var colour: Color = [Color(0.6, 0.85, 0.95), Color(0.85, 0.55, 0.85)][_rng.randi() % 2]
			var height := _rng.randf_range(0.1, 0.2)
			LowPoly.frustum(tool, Color(0.8, 0.78, 0.72), at - Vector3.UP * 0.02, 0.025, 0.02, height, 5, turn)
			LowPoly.frustum(_mesh_tool(true), colour, at + Vector3.UP * height, 0.08, 0.0, 0.06, 6, turn)


func add_seat(cell: Vector2, height: float) -> void:
	var position := Vector3(cell.x, height, cell.y)
	var facing := Basis.looking_at(Vector3(-cell.x, 0, -cell.y).normalized(), Vector3.UP)
	seats.append(Transform3D(facing, position))


func _build_props() -> void:
	var props: Dictionary = _biome.props
	var kinds: Array = props.keys()
	kinds.sort()
	for cell in _heights:
		var distance: float = (cell as Vector2).length()
		var ground: float = _heights[cell]
		if _biome.has("water") and ground < 0.0:
			continue
		if distance < PROP_RADIUS:
			continue
		var density := EDGE_DENSITY if distance < PROP_RADIUS + EDGE_BAND else 1.0
		for kind: String in kinds:
			if _rng.randf() < float(props[kind]) * density:
				_prop(kind, cell, ground)
				break


func _prop(kind: String, at: Vector2, ground: float) -> void:
	var tool := _mesh_tool(false)
	var base := Vector3(at.x, ground - SINK, at.y)
	var turn := _rng.randf() * TAU
	match kind:
		"tree":
			_tree(Vector3(at.x, ground, at.y), _rng.randf_range(2.0, 4.0))
		"pine":
			_pine(Vector3(at.x, ground, at.y), _rng.randf_range(3.5, 5.0))
		"palm":
			_palm(Vector3(at.x, ground, at.y), _rng.randf_range(4.0, 6.0))
		"rock":
			var size := _rng.randf_range(0.6, 1.4)
			LowPoly.frustum(tool, vary(_colour(2), 0.1), base, size, size * 0.45, size * 1.1 + SINK, 6, turn, 0.25, _rng)
		"flowers":
			for i in _rng.randi_range(3, 6):
				var spot := at + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))
				_detail("flower", Vector3(spot.x, surface_at(spot, ground), spot.y))
		"lava":
			# A flat, ragged pool, a little proud of the ground so the facets don't cover it.
			var radius := _rng.randf_range(0.8, 1.5)
			LowPoly.frustum(_mesh_tool(true), Color(1.0, 0.45, 0.1), Vector3(at.x, ground - 0.1, at.y), radius, radius * 0.92, 0.16, 7, turn, 0.3, _rng)
		"spire":
			var height := _rng.randf_range(3.0, 8.0)
			LowPoly.frustum(tool, vary(_colour(4), 0.08), base, _rng.randf_range(0.6, 1.1), 0.0, height, 6, turn, 0.15, _rng)
		"ice":
			var size := _rng.randf_range(0.7, 1.3)
			LowPoly.frustum(tool, Color(0.72, 0.86, 0.96), base, size, 0.05, size * 2.4, 4, turn, 0.15, _rng)
		"crystal":
			var colour: Color = [Color(0.4, 0.85, 1.0), Color(0.75, 0.45, 1.0)][_rng.randi() % 2]
			LowPoly.frustum(_mesh_tool(true), colour, base, 0.3, 0.0, _rng.randf_range(1.0, 2.5), 6, turn)


func _add_blocks(blocks: Array, glow: bool) -> void:
	if blocks.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = BoxMesh.new()
	multimesh.instance_count = blocks.size()
	for i in blocks.size():
		multimesh.set_instance_transform(i, blocks[i][0])
		multimesh.set_instance_color(i, blocks[i][1])
	var material := _material(glow, false)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if glow else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)


func _add_arc_mesh(tool: SurfaceTool, glow: bool) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = tool.commit()
	instance.material_override = _material(glow, true)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if glow else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)


## Glowing blocks are unshaded; the rest get the surface shader, reading face metres from UV
## for ring segments (`face_uv`) or from the box's size for MultiMesh boxes.
func _material(glow: bool, face_uv: bool) -> Material:
	if glow:
		var unshaded := StandardMaterial3D.new()
		unshaded.vertex_color_use_as_albedo = true
		unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return unshaded
	var surface := ShaderMaterial.new()
	surface.shader = SURFACE_SHADER
	surface.set_shader_parameter("MOSS", float(_biome.get("moss", 0.0)))
	surface.set_shader_parameter("FACE_UV", face_uv)
	_surfaces.append(surface)
	return surface


## Lets the camera see the fighters through cover: anything between the camera and a
## fighter's chest (`chests`, world positions), above that fighter's ground, dissolves.
func set_sight(chests: Array[Vector3], grounds: Array[float]) -> void:
	for surface in _surfaces:
		surface.set_shader_parameter("SIGHT_ON", true)
		surface.set_shader_parameter("SIGHT_A", chests[0])
		surface.set_shader_parameter("SIGHT_B", chests[1])
		surface.set_shader_parameter("SIGHT_GROUND_A", grounds[0])
		surface.set_shader_parameter("SIGHT_GROUND_B", grounds[1])


func _add_water(level: float) -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(WATER_SIZE, WATER_SIZE)
	water.mesh = plane
	water.position.y = level
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.55, 0.8, 0.82)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.15
	material.metallic_specular = 0.8
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _add_environment() -> void:
	var sun_data: Dictionary = _biome.sun
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = sun_data.angle
	sun.light_color = sun_data.colour
	sun.light_energy = sun_data.energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	var environment := Environment.new()
	var sky_colours: Array = _biome.sky
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_colours[0]
	sky_material.sky_horizon_color = sky_colours[1]
	sky_material.ground_horizon_color = sky_colours[1]
	sky_material.ground_bottom_color = _colour(4)
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	var ambient: Array = _biome.ambient
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = ambient[0]
	environment.ambient_light_energy = ambient[1]
	var fog: Array = _biome.fog
	environment.fog_enabled = true
	environment.fog_light_color = fog[0]
	environment.fog_density = fog[1]
	environment.fog_sky_affect = 0.3
	# Contact shadows in creases and under rocks, so faceted shapes read.
	environment.ssao_enabled = true
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 1.8
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)


func _add_particles(kind: String) -> void:
	if kind.is_empty():
		return
	var particles := CPUParticles3D.new()
	particles.use_fixed_seed = true
	particles.seed = _rng.randi()
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = PARTICLE_AREA * 0.5
	particles.position.y = PARTICLE_AREA.y * 0.5
	var quad := QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	quad.material = material
	particles.mesh = quad
	match kind:
		"petals":
			_weather(particles, 70, 9.0, Vector3(0.4, -0.35, 0.1), 0.07, Color(1.0, 0.8, 0.88, 0.9))
		"sand":
			_weather(particles, 120, 4.0, Vector3(2.0, -0.05, 0.4), 0.07, Color(0.95, 0.88, 0.7, 0.6))
		"embers":
			particles.position.y = 0.2
			_weather(particles, 110, 5.0, Vector3(0.1, 0.9, 0.0), 0.12, Color(1.0, 0.55, 0.15, 1.0))
		"snow":
			_weather(particles, 300, 7.0, Vector3(0.2, -0.8, 0.0), 0.08, Color(1, 1, 1, 0.95))
		"dust":
			_weather(particles, 70, 10.0, Vector3(0.05, 0.05, 0.05), 0.08, Color(0.8, 0.85, 1.0, 0.5))
	add_child(particles)


## Weather drifts at `drift` (m/s) with a little spread; preprocessed so it fills the air from
## the first frame.
func _weather(particles: CPUParticles3D, amount: int, lifetime: float, drift: Vector3, size: float, colour: Color) -> void:
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.direction = drift.normalized() if drift.length() > 0.0 else Vector3.DOWN
	particles.spread = 25.0
	particles.gravity = Vector3.ZERO
	particles.initial_velocity_min = drift.length() * 0.7
	particles.initial_velocity_max = drift.length() * 1.3
	# Sized on the mesh: billboards ignore the particles' own scale.
	(particles.mesh as QuadMesh).size = Vector2(size, size)
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.3
	particles.color = colour
