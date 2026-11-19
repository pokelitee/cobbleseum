class_name FieldLooks
extends Node3D
## How field and side conditions (concepts_brief.md §9.11, rules version 35) look on the field:
## - Trick Room, Magic Room and Wonder Room: a cage of glowing pixel-grid lines around the arena
##   in the room's colour (rooms up together nest a little apart);
## - Gravity: a dark ceiling hanging low over the arena and heavy streaks pressing down from it
##   (bright streaks read as rain);
## - Tailwind: pale streaks blowing past the side's fighters toward the foe.
## Each fades in and out with the battle's state over FADE_FRAMES, so clips that start mid-battle
## and the instant replay show what was up. Particles have fixed seeds, so every render of a
## battle is the same.

const FADE_FRAMES := 12
const COLOURS := {"trickroom": Color(1.0, 0.4, 0.85), "magicroom": Color(0.55, 0.5, 1.0), "wonderroom": Color(0.35, 0.95, 0.85),
	"gravity": Color(0.45, 0.3, 0.75), "tailwind": Color(0.55, 1.0, 0.7)}
const ROOMS: Array[String] = ["trickroom", "magicroom", "wonderroom"]
## The rooms' cage: its radius (inside the wall, a step in for each room up with it), height,
## and grid cells (metres).
const CAGE_RADIUS := 13.6
const CAGE_STEP := 0.45
const CAGE_HEIGHT := 7.0
const CELL := 1.75
const TEXTURE_PIXELS := 16
## Tailwind's streaks blow around this much ground about the side's fighter.
const WIND_AREA := Vector3(5.0, 2.0, 5.0)
const WIND_SPEED := 9.0
## Gravity's ceiling: its height and darkest opacity.
const CEILING_HEIGHT := 6.0
const CEILING_ALPHA := 0.35

var _seed := 0
var _cages := {}
var _alphas := {}
var _gravity: CPUParticles3D
var _gravity_material: StandardMaterial3D
var _ceiling: MeshInstance3D
var _winds: Array = [null, null]
var _wind_materials: Array = [null, null]
var _texture: ImageTexture


func setup(seed: int) -> void:
	_seed = seed
	_texture = _grid_texture()


## Shows the conditions up in `conditions` by one video frame. `fronts` are each side's first
## fighter's view up (Tailwind blows around it, toward the other side's).
func sync(conditions: ArenaConditions, fronts: Array[FighterView]) -> void:
	var index := 0
	for name in ROOMS:
		var alpha := _fade(name, conditions.has_field(name))
		if alpha <= 0.0 and not _cages.has(name):
			continue
		var cage: MeshInstance3D = _cages.get(name, null)
		if cage == null:
			cage = _cage(name)
			_cages[name] = cage
		cage.visible = alpha > 0.0
		if cage.visible:
			cage.scale = Vector3.ONE * (1.0 - CAGE_STEP * index / CAGE_RADIUS)
			(cage.material_override as StandardMaterial3D).albedo_color.a = alpha
			index += 1
	var pressing := _fade("gravity", conditions.has_field("gravity"))
	if pressing > 0.0 and _gravity == null:
		_gravity = _gravity_streaks()
		_ceiling = _gravity_ceiling()
	if _gravity != null:
		_gravity.visible = pressing > 0.0
		_ceiling.visible = pressing > 0.0
		_gravity_material.albedo_color.a = pressing
		(_ceiling.material_override as StandardMaterial3D).albedo_color.a = pressing * CEILING_ALPHA
	for side in 2:
		var key := "tailwind%d" % side
		var blowing := _fade(key, conditions.sides[side].has("tailwind"))
		if blowing > 0.0 and _winds[side] == null:
			_winds[side] = _wind(side)
		var wind: CPUParticles3D = _winds[side]
		if wind == null:
			continue
		wind.visible = blowing > 0.0
		(_wind_materials[side] as StandardMaterial3D).albedo_color.a = blowing
		var me := fronts[side]
		var foe := fronts[1 - side]
		var toward := foe.global_position - me.global_position
		toward.y = 0.0
		toward = toward.normalized() if toward.length_squared() > 1e-6 else Vector3.FORWARD
		# The streaks fly along the emitter's forward axis, so it looks at the foe.
		wind.global_position = me.global_position + Vector3.UP * WIND_AREA.y * 0.5 - toward * WIND_AREA.z * 0.3
		wind.global_basis = Basis.looking_at(toward, Vector3.UP)


## The shown strength (0-1) of `key` after one frame toward `up`.
func _fade(key: String, up: bool) -> float:
	var alpha: float = move_toward(float(_alphas.get(key, 0.0)), 1.0 if up else 0.0, 1.0 / FADE_FRAMES)
	_alphas[key] = alpha
	return alpha


## A room's cage: an open cylinder with a lid, its faces tiled with the grid texture.
func _cage(name: String) -> MeshInstance3D:
	var cage := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = CAGE_RADIUS
	mesh.bottom_radius = CAGE_RADIUS
	mesh.height = CAGE_HEIGHT
	mesh.cap_bottom = false
	mesh.radial_segments = 48
	mesh.rings = 1
	cage.mesh = mesh
	cage.position.y = CAGE_HEIGHT * 0.5
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = _texture
	material.uv1_scale = Vector3(TAU * CAGE_RADIUS / CELL, CAGE_HEIGHT / CELL, 1.0)
	# Brighter than white, so the lines bloom.
	var colour: Color = COLOURS[name]
	material.albedo_color = Color(colour.r * 1.5, colour.g * 1.5, colour.b * 1.5, 0.0)
	cage.material_override = material
	cage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cage)
	return cage


func _gravity_streaks() -> CPUParticles3D:
	var particles := _particles("gravity")
	particles.emission_box_extents = Arena.PARTICLE_AREA * 0.5
	particles.position.y = Arena.PARTICLE_AREA.y * 0.5
	particles.position.y = CEILING_HEIGHT * 0.5
	particles.emission_box_extents.y = CEILING_HEIGHT * 0.5
	particles.amount = 260
	particles.lifetime = 0.4
	particles.preprocess = 0.4
	particles.direction = Vector3.DOWN
	particles.initial_velocity_min = 14.0
	particles.initial_velocity_max = 18.0
	particles.spread = 2.0
	(particles.mesh as QuadMesh).size = Vector2(0.09, 1.4)
	particles.color = Color(0.22, 0.1, 0.38, 0.85)
	_gravity_material = (particles.mesh as QuadMesh).material
	_gravity_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	return particles


## A dark disc over the arena at CEILING_HEIGHT, its edge fading out.
func _gravity_ceiling() -> MeshInstance3D:
	var ceiling := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = CAGE_RADIUS
	mesh.bottom_radius = CAGE_RADIUS
	mesh.height = 0.05
	mesh.radial_segments = 48
	ceiling.mesh = mesh
	ceiling.position.y = CEILING_HEIGHT
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.12, 0.05, 0.22, 0.0)
	ceiling.material_override = material
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ceiling)
	return ceiling


func _wind(side: int) -> CPUParticles3D:
	var particles := _particles("tailwind%d" % side)
	particles.emission_box_extents = WIND_AREA * 0.5
	particles.amount = 120
	particles.lifetime = 0.6
	particles.preprocess = 0.6
	particles.direction = Vector3.FORWARD
	particles.initial_velocity_min = WIND_SPEED * 0.8
	particles.initial_velocity_max = WIND_SPEED * 1.2
	particles.spread = 6.0
	particles.local_coords = true
	(particles.mesh as QuadMesh).size = Vector2(0.8, 0.06)
	_wind_materials[side] = (particles.mesh as QuadMesh).material
	return particles


func _particles(key: String) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.use_fixed_seed = true
	particles.seed = hash("%d|%s" % [_seed, key])
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.gravity = Vector3.ZERO
	var quad := QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1, 1, 1, 0)
	material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	material.distance_fade_min_distance = ArenaWeather.NEAR_FADE.x
	material.distance_fade_max_distance = ArenaWeather.NEAR_FADE.y
	quad.material = material
	particles.mesh = quad
	var colour: Color = COLOURS["tailwind" if key.begins_with("tailwind") else key]
	particles.color = Color(colour.r * 1.3, colour.g * 1.3, colour.b * 1.3, 0.7)
	add_child(particles)
	return particles


## A white pixel-art grid cell: bright two-pixel lines along its edges and a faint fill.
static func _grid_texture() -> ImageTexture:
	var image := Image.create(TEXTURE_PIXELS, TEXTURE_PIXELS, false, Image.FORMAT_RGBA8)
	for y in TEXTURE_PIXELS:
		for x in TEXTURE_PIXELS:
			var line := x == 0 or y == 0
			var glow := x == 1 or y == 1
			image.set_pixel(x, y, Color(1, 1, 1, 0.85 if line else (0.35 if glow else 0.02)))
	return ImageTexture.create_from_image(image)
