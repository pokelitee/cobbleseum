class_name ArenaLighting
extends RefCounted
## How an arena is lit and graded (concepts_brief.md §12.7): Cobblemon in Minecraft under a
## gentle shader pack. The preset's look sets the place (sky, sun, ambient, fog, floodlights,
## exposure); everything else is the same in every arena, so adding one stays adding a file:
## - a Filmic tonemap with a little extra saturation, so highlights roll off without
##   washing out type colours;
## - bloom only past HDR_THRESHOLD, which daylit surfaces never reach: only glowing things
##   (Arena.GLOW_ENERGY, move visuals, emissive layers on models) bloom;
## - soft sun shadows that harden toward contact (PCSS), fitted to what the cameras see;
## - screen-space ambient occlusion for creases and the bases of rocks. Screen-space indirect
##   light was tried and left out: it cost live play about a fifth of its frame rate in a full
##   coliseum for a barely visible tint.

const SATURATION := 1.1
const HDR_THRESHOLD := 1.2
const GLOW_INTENSITY := 0.9
const GLOW_STRENGTH := 1.0
## The sun's apparent size in degrees: how soft its shadows get away from contact.
const SUN_SIZE := 1.5
## Shadows reach as far as the cameras see clearly; fog hides what's further.
const SHADOW_DISTANCE := 45.0
const SSAO_RADIUS := 1.2
const SSAO_INTENSITY := 1.6


## Adds the sun, the world environment and (for a preset that has them) floodlights to `arena`.
static func add(arena: Arena, look: Dictionary) -> void:
	var sun_data: Dictionary = look.sun
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = sun_data.angle
	sun.light_color = sun_data.colour
	sun.light_energy = sun_data.energy
	sun.light_angular_distance = SUN_SIZE
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = SHADOW_DISTANCE
	arena.add_child(sun)
	var world := WorldEnvironment.new()
	world.environment = environment(look)
	arena.add_child(world)
	var floodlights: Dictionary = look.floodlights
	if floodlights.energy > 0.0:
		Coliseum.add_floodlights(arena, floodlights.colour, floodlights.energy)


static func environment(look: Dictionary) -> Environment:
	var environment := Environment.new()
	var sky_colours: Array = look.sky
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_colours[0]
	sky_material.sky_horizon_color = sky_colours[1]
	sky_material.ground_horizon_color = sky_colours[1]
	sky_material.ground_bottom_color = look.colours[4]
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	var ambient: Array = look.ambient
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = ambient[0]
	environment.ambient_light_energy = ambient[1]
	var fog: Array = look.fog
	environment.fog_enabled = true
	environment.fog_light_color = fog[0]
	environment.fog_density = fog[1]
	environment.fog_sky_affect = 0.3
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = look.exposure
	environment.adjustment_enabled = true
	environment.adjustment_saturation = SATURATION
	environment.glow_enabled = true
	environment.glow_hdr_threshold = HDR_THRESHOLD
	environment.glow_intensity = GLOW_INTENSITY
	environment.glow_strength = GLOW_STRENGTH
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.ssao_enabled = true
	environment.ssao_radius = SSAO_RADIUS
	environment.ssao_intensity = SSAO_INTENSITY
	return environment
