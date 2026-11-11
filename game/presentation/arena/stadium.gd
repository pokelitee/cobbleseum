class_name Stadium
extends RefCounted
## The stadium arena (concepts_brief.md §12.7): a round coliseum built from blocks around the
## battle floor, big enough to read as a stadium rather than a low wall.
##
## From the centre out:
## - the field: pale stone slabs with painted lines (boundary, halfway line, centre circle);
## - an apron of grey-green paving with a trainer's box at each end;
## - a stone wall with a coping;
## - the lower stands, a concourse, the upper stands and a parapet, split into SECTIONS by
##   pillars, with a tunnel into the lower rows of every other section;
## - a roof ring on posts with a floodlight bank along its inner edge;
## - banners on the parapet in each side's colour (side 0 on the -z half, side 1 on +z);
## - a scoreboard tower behind the far stands with the fighters' names.
## Rings are built from blocks about a metre long, like Cobblemon's voxels.

const APRON_WIDTH := 3.5
const WALL_THICKNESS := 0.8
const WALL_HEIGHT := 2.4
const ROW_DEPTH := 0.85
const ROW_RISE := 0.45
const LOWER_ROWS := 12
const CONCOURSE := 2.5
const UPPER_ROWS := 9
const PARAPET := 1.2
const SECTIONS := 16
const TUNNEL_ROWS := 4
const TUNNEL_WIDTH := 2.6
const PILLAR_WIDTH := 0.7
const ROOF_DEPTH := 7.0
const ROOF_THICKNESS := 0.6
const ROOF_CLEARANCE := 4.5
const LINE_WIDTH := 0.14
const GROUND_RADIUS := 70.0

const STONE := Color(0.62, 0.63, 0.6)
const STONE_DARK := Color(0.48, 0.5, 0.47)
const SLAB := Color(0.78, 0.71, 0.58)
const SLAB_DARK := Color(0.73, 0.66, 0.53)
const APRON := Color(0.48, 0.53, 0.48)
const APRON_LIGHT := Color(0.54, 0.59, 0.54)
const SEATS := Color(0.56, 0.57, 0.55)
const SEATS_ALT := Color(0.5, 0.52, 0.5)
const LINE := Color(0.95, 0.95, 0.92)
const TUNNEL := Color(0.08, 0.08, 0.09)
const BRONZE := Color(0.33, 0.43, 0.38)
const GROUND := Color(0.36, 0.48, 0.3)
const FLOODLIGHT := Color(1.0, 0.97, 0.85)
const SCREEN := Color(0.05, 0.07, 0.1)
const SIDE_COLOURS: Array[Color] = [Color(0.78, 0.22, 0.2), Color(0.2, 0.38, 0.75)]


static func field_radius() -> float:
	return Arena.FLOOR_RADIUS


static func wall_radius() -> float:
	return field_radius() + APRON_WIDTH


## Where row `index` (0 = front of the lower stands) starts and how high its top is.
static func row(index: int) -> Vector2:
	var start := wall_radius() + WALL_THICKNESS
	if index < LOWER_ROWS:
		return Vector2(start + index * ROW_DEPTH, WALL_HEIGHT + (index + 1) * ROW_RISE)
	var upper := index - LOWER_ROWS
	var concourse_height := WALL_HEIGHT + LOWER_ROWS * ROW_RISE
	return Vector2(start + LOWER_ROWS * ROW_DEPTH + CONCOURSE + upper * ROW_DEPTH,
		concourse_height + (upper + 1) * ROW_RISE)


static func outer_radius() -> float:
	return row(LOWER_ROWS + UPPER_ROWS - 1).x + ROW_DEPTH


static func top_height() -> float:
	return row(LOWER_ROWS + UPPER_ROWS - 1).y + PARAPET


## Builds everything into `arena`. `names` are the two fighters' names, for the scoreboard.
static func build(arena: Arena, rng: RandomNumberGenerator, names: Array) -> void:
	_field(arena, rng)
	_apron(arena, rng)
	_wall(arena, rng)
	_stands(arena, rng)
	_roof(arena, rng)
	_banners(arena)
	_scoreboard(arena, names)
	arena.add_arc_ring(outer_radius(), GROUND_RADIUS, -1.0, -0.05, GROUND, rng, 0.06)


static func _field(arena: Arena, rng: RandomNumberGenerator) -> void:
	var radius := field_radius()
	for cell in arena.cells(radius):
		var checker := (int(floor(cell.x)) + int(floor(cell.y))) % 2 == 0
		arena.add_box(cell, -1.0, 0.0, arena.vary(SLAB if checker else SLAB_DARK, 0.03))
	# Painted lines a hair above the slabs.
	var lift := 0.012
	arena.add_arc_ring(radius - 0.45, radius - 0.45 + LINE_WIDTH, -0.01, lift, LINE, rng, 0.0)
	arena.add_arc_ring(2.2, 2.2 + LINE_WIDTH, -0.01, lift, LINE, rng, 0.0)
	arena.add_block(Transform3D(Basis.from_scale(Vector3((radius - 0.45) * 2.0, 0.02, LINE_WIDTH)), Vector3(0, lift - 0.01, 0)), LINE)


static func _apron(arena: Arena, rng: RandomNumberGenerator) -> void:
	arena.add_arc_ring(field_radius(), wall_radius(), -1.0, 0.0, APRON, rng, 0.05, APRON_LIGHT)
	# A trainer's box at each end, outlined in white.
	for side in 2:
		var z := (field_radius() + APRON_WIDTH * 0.5) * (-1.0 if side == 0 else 1.0)
		var size := Vector2(2.4, 1.6)
		for edge in [Vector3(0, 0, -size.y * 0.5), Vector3(0, 0, size.y * 0.5)]:
			arena.add_block(Transform3D(Basis.from_scale(Vector3(size.x, 0.02, LINE_WIDTH)), Vector3(0, 0.002, z) + edge), LINE)
		for edge in [Vector3(-size.x * 0.5, 0, 0), Vector3(size.x * 0.5, 0, 0)]:
			arena.add_block(Transform3D(Basis.from_scale(Vector3(LINE_WIDTH, 0.02, size.y)), Vector3(0, 0.002, z) + edge), LINE)


static func _wall(arena: Arena, rng: RandomNumberGenerator) -> void:
	var inner := wall_radius()
	arena.add_arc_ring(inner, inner + WALL_THICKNESS, -1.0, WALL_HEIGHT, STONE, rng, 0.07, STONE_DARK)
	arena.add_arc_ring(inner - 0.12, inner + WALL_THICKNESS + 0.12, WALL_HEIGHT, WALL_HEIGHT + 0.25, BRONZE, rng, 0.04)


static func _section(angle: float) -> int:
	return int(floor(fposmod(angle, TAU) / TAU * SECTIONS))


## Whether `angle` falls in the tunnel of its section (every other section has one, centred).
static func _in_tunnel(angle: float, radius: float) -> bool:
	var section := _section(angle)
	if section % 2 == 1:
		return false
	var centre := (section + 0.5) * TAU / SECTIONS
	return absf(angle_difference(angle, centre)) * radius < TUNNEL_WIDTH * 0.5


static func _near_pillar(angle: float, radius: float) -> bool:
	var to_pillar := fposmod(angle, TAU / SECTIONS)
	var distance := minf(to_pillar, TAU / SECTIONS - to_pillar) * radius
	return distance < PILLAR_WIDTH * 0.5


static func _stands(arena: Arena, rng: RandomNumberGenerator) -> void:
	var rows := LOWER_ROWS + UPPER_ROWS
	for index in rows:
		var at := row(index)
		var colour := SEATS if index % 2 == 0 else SEATS_ALT
		var segments := ceili(TAU * at.x / 1.0)
		for s in segments:
			var angle := (s + 0.5) * TAU / segments
			var top := at.y
			if index < TUNNEL_ROWS and _in_tunnel(angle, at.x):
				# The tunnel: a dark opening under the rows above.
				arena.add_arc(angle, at.x, at.x + ROW_DEPTH, -1.0, WALL_HEIGHT * 0.9, TUNNEL, TAU * at.x / segments * 1.02)
				arena.add_arc(angle, at.x, at.x + ROW_DEPTH, WALL_HEIGHT * 0.9, top, arena.vary(STONE_DARK), TAU * at.x / segments * 1.02)
				continue
			arena.add_arc(angle, at.x, at.x + ROW_DEPTH, -1.0, top, arena.vary(colour, 0.04), TAU * at.x / segments * 1.02)
			if not _near_pillar(angle, at.x):
				arena.add_seat(Vector2(cos(angle), sin(angle)) * (at.x + ROW_DEPTH * 0.5), top)
	# The concourse between the tiers.
	var concourse_start := row(LOWER_ROWS - 1).x + ROW_DEPTH
	arena.add_arc_ring(concourse_start, concourse_start + CONCOURSE, -1.0, row(LOWER_ROWS - 1).y, STONE, rng, 0.05)
	# The parapet behind the top row.
	var back := outer_radius()
	arena.add_arc_ring(back, back + 0.6, -1.0, top_height(), STONE, rng, 0.07, STONE_DARK)
	# Pillars between sections, a little proud of the rows, from the wall to the parapet.
	for section in SECTIONS:
		var angle := section * TAU / SECTIONS
		for index in range(0, rows, 2):
			var at := row(index)
			arena.add_arc(angle, at.x, at.x + ROW_DEPTH * 2.0, at.y - 1.0, at.y + 0.35, arena.vary(STONE_DARK, 0.05), PILLAR_WIDTH)


static func _roof(arena: Arena, rng: RandomNumberGenerator) -> void:
	var outer := outer_radius() + 0.6
	var height := top_height() + ROOF_CLEARANCE
	arena.add_arc_ring(outer - ROOF_DEPTH, outer, height, height + ROOF_THICKNESS, STONE_DARK, rng, 0.05)
	for section in SECTIONS:
		var angle := section * TAU / SECTIONS
		arena.add_arc(angle, outer - 0.3, outer + 0.5, -1.0, height, arena.vary(STONE, 0.05), 0.8)
		for light in 2:
			var along := angle + (light + 0.5) * TAU / SECTIONS / 2.0
			arena.add_arc(along, outer - ROOF_DEPTH - 0.1, outer - ROOF_DEPTH + 0.5, height - 0.5, height, FLOODLIGHT, 1.8, true)


static func _banners(arena: Arena) -> void:
	var radius := outer_radius() - 0.05
	for section in SECTIONS:
		var angle := (section + 0.5) * TAU / SECTIONS
		var side := 0 if sin(angle) < 0.0 else 1
		arena.add_arc(angle, radius - 0.08, radius, top_height() - 5.5, top_height() - 0.2, SIDE_COLOURS[side], 2.4)


static func _scoreboard(arena: Arena, names: Array) -> void:
	var distance := outer_radius() + 6.0
	# The screen sits above the roof ring, which would otherwise hide its lower half.
	var screen_bottom := top_height() + ROOF_CLEARANCE + ROOF_THICKNESS + 0.8
	var height := screen_bottom + 7.0
	var width := 16.0
	for x in [-width * 0.5 - 1.0, width * 0.5 + 1.0]:
		arena.add_block(Transform3D(Basis.from_scale(Vector3(2.0, height + 1.0, 2.0)), Vector3(x, (height + 1.0) * 0.5 - 1.0, distance)), STONE_DARK)
	arena.add_block(Transform3D(Basis.from_scale(Vector3(width + 4.0, 1.2, 1.6)), Vector3(0, height + 0.6, distance)), BRONZE)
	arena.add_block(Transform3D(Basis.from_scale(Vector3(width, height - screen_bottom, 0.4)),
		Vector3(0, (height + screen_bottom) * 0.5, distance - 0.6)), SCREEN, true)
	if names.size() == 2:
		var label := Label3D.new()
		label.text = "%s\nVS\n%s" % [str(names[0]).to_upper(), str(names[1]).to_upper()]
		label.font_size = 200
		label.pixel_size = 0.009
		label.outline_size = 0
		label.modulate = Color(1.0, 0.92, 0.6)
		label.shaded = false
		label.position = Vector3(0, (height + screen_bottom) * 0.5, distance - 0.85)
		label.rotation.y = PI
		arena.add_child(label)
