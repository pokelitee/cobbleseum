class_name Stadium
extends RefCounted
## The stadium arena (concepts_brief.md §12.7): a round coliseum built from blocks around the
## battle floor, big enough to read as a stadium rather than a low wall.
##
## From the centre out:
## - the field: rings of pale stone paving with painted lines (boundary, halfway line,
##   centre circle);
## - an apron of grey-green paving with a trainer's box at each end;
## - a stone wall with a coping;
## - the lower stands, a concourse, the upper stands and a parapet, split into SECTIONS by
##   pillars, with a tunnel into the lower rows of every other section;
## - a roof ring on posts with a floodlight bank along its inner edge;
## - banners on the parapet in each side's colour (side 0 on the -z half, side 1 on +z);
## - a big screen set into the upper stands at each end (behind each side's starting
##   point), showing the fighters' names where the battle's cameras see it.
## Rings are exact ring segments about a metre long, like Cobblemon's voxels.

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
## The screens: width along the upper stands, and their angles (behind each side's start).
const SCREEN_WIDTH := 15.0
const SCREEN_ANGLES: Array[float] = [-PI * 0.5, PI * 0.5]
const SCREEN_RISE := 2.0

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
	_screens(arena, names)
	arena.add_arc_ring(outer_radius(), GROUND_RADIUS, -1.0, -0.05, GROUND, rng, 0.06)


static func _field(arena: Arena, rng: RandomNumberGenerator) -> void:
	var radius := field_radius()
	var ring := 0.0
	while ring < radius:
		var next := minf(ring + 1.0, radius)
		arena.add_arc_ring(ring, next, -1.0, 0.0, SLAB, rng, 0.03, SLAB_DARK)
		ring = next
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


## Whether `angle` is behind one of the screens (no upper rows, pillars or banners there).
static func _behind_screen(angle: float) -> bool:
	var half := SCREEN_WIDTH * 0.5 / row(LOWER_ROWS).x
	for centre in SCREEN_ANGLES:
		if absf(angle_difference(angle, centre)) < half:
			return true
	return false


static func _near_pillar(angle: float, radius: float) -> bool:
	var to_pillar := fposmod(angle, TAU / SECTIONS)
	var distance := minf(to_pillar, TAU / SECTIONS - to_pillar) * radius
	return distance < PILLAR_WIDTH * 0.5


static func _stands(arena: Arena, rng: RandomNumberGenerator) -> void:
	var rows := LOWER_ROWS + UPPER_ROWS
	for index in rows:
		var at := row(index)
		var colour := SEATS if index % 2 == 0 else SEATS_ALT
		var segments := ceili(TAU * at.x / Arena.RING_BLOCK)
		for s in segments:
			var from := s * TAU / segments
			var to := (s + 1) * TAU / segments
			var angle := (from + to) * 0.5
			var top := at.y
			if index >= LOWER_ROWS and _behind_screen(angle):
				continue
			if index < TUNNEL_ROWS and _in_tunnel(angle, at.x):
				# The tunnel: a dark opening under the rows above.
				arena.add_sector(from, to, at.x, at.x + ROW_DEPTH, -1.0, WALL_HEIGHT * 0.9, TUNNEL)
				arena.add_sector(from, to, at.x, at.x + ROW_DEPTH, WALL_HEIGHT * 0.9, top, arena.vary(STONE_DARK))
				continue
			arena.add_sector(from, to, at.x, at.x + ROW_DEPTH, -1.0, top, arena.vary(colour, 0.04))
			if not _near_pillar(angle, at.x):
				arena.add_seat(Vector2(cos(angle), sin(angle)) * (at.x + ROW_DEPTH * 0.5), top)
	# The concourse between the tiers.
	var concourse_start := row(LOWER_ROWS - 1).x + ROW_DEPTH
	arena.add_arc_ring(concourse_start, concourse_start + CONCOURSE, -1.0, row(LOWER_ROWS - 1).y, STONE, rng, 0.05)
	# The parapet behind the top row.
	var back := outer_radius()
	arena.add_arc_ring(back, back + 0.6, -1.0, top_height(), STONE, rng, 0.07, STONE_DARK)
	# Pillars between sections, a little proud of the rows, stepping up from the wall to the
	# parapet without a break.
	for section in SECTIONS:
		var angle := section * TAU / SECTIONS
		var shade := arena.vary(STONE_DARK, 0.05)
		for index in rows:
			var at := row(index)
			if index >= LOWER_ROWS and _behind_screen(angle):
				continue
			arena.add_arc(angle, at.x, at.x + ROW_DEPTH, at.y - ROW_RISE - 0.05, at.y + 0.35, shade, PILLAR_WIDTH)


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
		if _behind_screen(angle):
			continue
		arena.add_arc(angle, radius - 0.08, radius, top_height() - 5.5, top_height() - 0.2, SIDE_COLOURS[side], 2.4)


## A screen at each end, set into the upper stands where the rows are left out: a stone
## frame filling the tier, the glowing screen on its face, and the fighters' names on it.
static func _screens(arena: Arena, names: Array) -> void:
	var front := row(LOWER_ROWS).x
	var bottom := row(LOWER_ROWS - 1).y
	var half := SCREEN_WIDTH * 0.5 / front
	# The screen rises a little above the stands, so it reads from the field.
	var screen_bottom := bottom + 0.6
	var screen_top := top_height() + SCREEN_RISE
	for centre in SCREEN_ANGLES:
		arena.add_sector(centre - half, centre + half, front, outer_radius(), -1.0, screen_top + 0.5, STONE_DARK)
		var inset := 0.25 / front
		arena.add_sector(centre - half + inset, centre + half - inset, front - 0.12, front,
			screen_bottom, screen_top, SCREEN, true)
		if names.size() != 2:
			continue
		var label := Label3D.new()
		label.text = "%s\nVS\n%s" % [str(names[0]).to_upper(), str(names[1]).to_upper()]
		label.font_size = 180
		# Three lines filling about four fifths of the screen's height.
		label.pixel_size = (screen_top - screen_bottom) * 0.8 / (3.0 * 1.3 * label.font_size)
		label.outline_size = 0
		label.modulate = Color(1.0, 0.92, 0.6)
		label.shaded = false
		var direction := Vector3(cos(centre), 0, sin(centre))
		# In front of the screen's curve: a flat label close to it would dip behind its edges.
		var bulge := pow(SCREEN_WIDTH * 0.5, 2.0) / (2.0 * front)
		label.position = direction * (front - 0.15 - bulge) + Vector3.UP * (screen_bottom + screen_top) * 0.5
		# Label3D reads from +Z; turn that toward the centre.
		label.rotation.y = atan2(-direction.x, -direction.z)
		arena.add_child(label)
