class_name Arena
extends Node3D
## A blocky arena around the battle floor (concepts_brief.md §12.7): the floor and its rim,
## terrain that stays flat near the floor (room for the camera) and rises into hills further
## out, props, stands, sky, sun, fog and weather, all from one biome (ArenaBiomes) and seeded
## by the battle, so every render of a battle is identical. Presentation only: the battle
## itself is always the flat round arena of §9.1.
##
## Everything is blocks in the voxel style of Cobblemon's models: boxes drawn through
## MultiMeshes, and curved blocks (ring segments) built as exact meshes so rings have no gaps
## or overlaps. A surface shader (arena_surface.gdshader) adds pixel grain lined up with each
## face, and grime, so no outside art is needed. The stadium has a builder of its own (Stadium).

## The floor reaches just past the simulation's wall, with a raised rim around it.
const FLOOR_RADIUS := Rules.ARENA_RADIUS + 0.5
const RIM_WIDTH := 1.0
const RIM_HEIGHT := 0.4
## Distances below are from the floor's edge, so the world follows the arena's size.
## Terrain stays within a block of the floor out to CLEAR_RADIUS, where the camera roams.
const CLEAR_RADIUS := FLOOR_RADIUS + 6.5
const OUTER_RADIUS := FLOOR_RADIUS + 31.5
## Props stand beyond this; only low ones (flowers) come closer.
const PROP_RADIUS := FLOOR_RADIUS + 9.5
const LOW_PROP_RADIUS := FLOOR_RADIUS + 2.5
## Where spectators may sit outside a stadium: terrain this far out, at most this high.
const SEAT_RANGE := Vector2(FLOOR_RADIUS + 5.5, FLOOR_RADIUS + 13.5)
const SEAT_MAX_HEIGHT := 3.0
const WATER_SIZE := 240.0
const PARTICLE_AREA := Vector3(FLOOR_RADIUS * 3.5, 8, FLOOR_RADIUS * 3.5)
const SURFACE_SHADER := preload("res://game/presentation/arena/arena_surface.gdshader")
## Cameras stay this far inside where the world rises (Stadium's wall, or the clear ground).
const CAMERA_MARGIN := 1.0
## Curved faces are split every this many metres along the arc, so they look round.
const ARC_STEP := 0.25
## Ring blocks are about this long.
const RING_BLOCK := 1.0

var biome_name := ""
## Places a spectator can stand, facing the floor's centre (world transforms).
var seats: Array[Transform3D] = []
## How far from the centre a camera may go before it would be inside the scenery.
var camera_limit := CLEAR_RADIUS - CAMERA_MARGIN

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
## Terrain height by cell, so props sit on top.
var _heights := {}


## Builds the arena for `name` (one of Terrain.BIOMES) seeded by `seed`, around the battle's
## `terrain` (flat if not given). `names` are the fighters' names, for the stadium's screens.
static func create(name: String, seed: int, names: Array = [], terrain: Terrain = null) -> Arena:
	var arena := Arena.new()
	arena.name = "Arena"
	arena.biome_name = name
	arena._biome = ArenaBiomes.BIOMES[name]
	arena._rng.seed = hash("%s|%d" % [name, seed])
	arena._noise.seed = seed
	arena._noise.frequency = 0.06
	arena._terrain = terrain if terrain != null else Terrain.flat(name)
	arena._build(names)
	return arena


func _build(names: Array) -> void:
	if _biome.get("stadium", false):
		Stadium.build(self, _rng, names)
		camera_limit = Stadium.wall_radius() - CAMERA_MARGIN
	else:
		_build_floor()
		_build_terrain()
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
	var tool: SurfaceTool = _arcs.get(glow)
	if tool == null:
		tool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_arcs[glow] = tool
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


func _build_floor() -> void:
	for cell in cells(FLOOR_RADIUS + RIM_WIDTH):
		var distance := cell.length()
		if distance > FLOOR_RADIUS:
			add_box(cell, -1.0, RIM_HEIGHT, vary(_colour(2)))
			continue
		var checker := (int(floor(cell.x)) + int(floor(cell.y))) % 2 == 0
		var floor_colour := _colour(0) if checker else _colour(1)
		var height := _terrain.height_at(cell)
		if height <= 0.0:
			add_box(cell, -1.0, 0.0, vary(floor_colour, 0.02))
		elif _is_pillar(cell, height):
			# Cover: a pillar of the biome's rock, with a cap.
			add_box(cell, -1.0, height - 0.25, vary(_colour(4), 0.06))
			add_box(cell, height - 0.25, height, vary(_colour(2), 0.06))
		else:
			# Raised ground: earth sides, the floor's own surface on top.
			add_box(cell, -1.0, height - 0.25, vary(_colour(4), 0.04))
			add_box(cell, height - 0.25, height, vary(_colour(3), 0.03))


## A cell standing well above all four neighbours is a pillar of cover, not raised ground.
func _is_pillar(cell: Vector2, height: float) -> bool:
	for side in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		if _terrain.height_at(cell + side) > height - 1.0:
			return false
	return true


func _build_terrain() -> void:
	var hills := float(_biome.hills)
	var under_water := _biome.has("water")
	for cell in cells(OUTER_RADIUS):
		var distance := cell.length()
		if distance <= FLOOR_RADIUS + RIM_WIDTH:
			continue
		var bump := _noise.get_noise_2d(cell.x, cell.y)
		var rise := clampf((distance - CLEAR_RADIUS) / (OUTER_RADIUS - CLEAR_RADIUS), 0.0, 1.0)
		var height := 0.0
		if under_water:
			# Sand slopes down into the sea beyond the clear ring, with a few sandbars.
			height = roundf(bump * 1.2 - rise * 4.0)
		elif distance < CLEAR_RADIUS:
			height = maxf(0.0, roundf(bump * 1.2)) if distance > LOW_PROP_RADIUS else 0.0
		else:
			height = roundf(rise * rise * hills + (bump * 0.5 + 0.5) * (1.0 + rise * hills * 0.6))
		_heights[cell] = height
		var top := _colour(3)
		if under_water and height <= -1.0:
			top = _colour(4)
		add_box(cell, -3.0, height - 0.25, vary(_colour(4)))
		add_box(cell, height - 0.25, height, vary(top))
		if height >= 0.0 and distance >= SEAT_RANGE.x and distance <= SEAT_RANGE.y and height <= SEAT_MAX_HEIGHT:
			add_seat(cell, height)


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
		for kind: String in kinds:
			var low := kind == "flowers" or kind == "lava"
			if distance < (LOW_PROP_RADIUS if low else PROP_RADIUS):
				continue
			if _rng.randf() < float(props[kind]):
				_prop(kind, cell, ground)
				break


func _prop(kind: String, at: Vector2, ground: float) -> void:
	match kind:
		"tree":
			var trunk := _rng.randi_range(2, 4)
			add_box(at, ground, ground + trunk, vary(Color(0.42, 0.29, 0.18)), Vector2(0.8, 0.8))
			add_box(at, ground + trunk - 0.5, ground + trunk + 2.0, vary(Color(0.27, 0.5, 0.22), 0.08), Vector2(3, 3))
			add_box(at, ground + trunk + 2.0, ground + trunk + 3.0, vary(Color(0.3, 0.55, 0.24), 0.08), Vector2(1.6, 1.6))
		"pine":
			var trunk := _rng.randi_range(1, 2)
			add_box(at, ground, ground + trunk, Color(0.35, 0.25, 0.17), Vector2(0.7, 0.7))
			for layer in 3:
				var width := 3.0 - layer
				var bottom := ground + trunk + layer * 1.2
				add_box(at, bottom, bottom + 1.2, vary(Color(0.16, 0.34, 0.24)), Vector2(width, width))
				add_box(at, bottom + 1.2, bottom + 1.4, Color(0.95, 0.97, 1.0), Vector2(width * 0.7, width * 0.7))
		"palm":
			var height := _rng.randi_range(4, 6)
			var lean := Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))
			for i in height:
				add_box(at + lean * (float(i) / height), ground + i, ground + i + 1, Color(0.55, 0.42, 0.27), Vector2(0.5, 0.5))
			var crown := at + lean
			add_box(crown, ground + height, ground + height + 0.3, vary(Color(0.24, 0.55, 0.22)), Vector2(4.0, 0.8))
			add_box(crown, ground + height, ground + height + 0.3, vary(Color(0.24, 0.55, 0.22)), Vector2(0.8, 4.0))
		"rock":
			var size := _rng.randf_range(0.8, 1.8)
			add_box(at, ground, ground + size * 0.8, vary(Color(0.5, 0.5, 0.52), 0.1), Vector2(size, size * 0.9))
		"flowers":
			var colours := [Color(0.95, 0.35, 0.35), Color(1.0, 0.85, 0.3), Color(0.95, 0.95, 1.0), Color(0.7, 0.5, 0.95)]
			for i in 3:
				var spot := at + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))
				add_box(spot, ground, ground + 0.25, colours[_rng.randi() % colours.size()], Vector2(0.2, 0.2))
		"lava":
			add_box(at, ground - 0.2, ground + 0.05, Color(1.0, 0.45, 0.1), Vector2(_rng.randf_range(1.5, 3.0), _rng.randf_range(1.5, 3.0)), true)
		"spire":
			var height := _rng.randi_range(3, 8)
			var width := _rng.randf_range(0.8, 1.6)
			add_box(at, ground, ground + height, vary(_colour(4), 0.08), Vector2(width, width))
			add_box(at, ground + height, ground + height + 1.0, vary(_colour(4), 0.08), Vector2(width * 0.5, width * 0.5))
		"ice":
			var size := _rng.randf_range(1.0, 2.2)
			add_box(at, ground, ground + size * 1.5, Color(0.7, 0.85, 0.95), Vector2(size, size))
		"crystal":
			var colour: Color = [Color(0.4, 0.85, 1.0), Color(0.75, 0.45, 1.0)][_rng.randi() % 2]
			var height := _rng.randf_range(1.0, 2.5)
			add_box(at, ground, ground + height, colour, Vector2(0.5, 0.5), true)
			add_box(at + Vector2(0.4, 0.2), ground, ground + height * 0.6, colour, Vector2(0.35, 0.35), true)


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
			_weather(particles, 90, 9.0, Vector3(0.4, -0.35, 0.1), 0.14, Color(1.0, 0.8, 0.88, 0.9))
		"sand":
			_weather(particles, 120, 4.0, Vector3(2.0, -0.05, 0.4), 0.07, Color(0.95, 0.88, 0.7, 0.6))
		"embers":
			particles.position.y = 0.2
			_weather(particles, 110, 5.0, Vector3(0.1, 0.9, 0.0), 0.12, Color(1.0, 0.55, 0.15, 1.0))
		"snow":
			_weather(particles, 260, 7.0, Vector3(0.2, -0.8, 0.0), 0.13, Color(1, 1, 1, 0.95))
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
