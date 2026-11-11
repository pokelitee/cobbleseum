class_name ArenaBiomes
extends RefCounted
## The arena biomes (concepts_brief.md §12.7): colours, sky, light, fog, weather, props and
## small details for each, as plain data that Arena builds the world from.
##
## Colours are [ground, patches (paths, gravel, ash), stone (cliffs and rock), higher ground,
## earth (the sides of the ground)]. Props are {kind: share of cells beyond the arena that get
## one}. Details are small things on level ground that the battle ignores: `detail` is the share
## of cells that get one, `details` lists [colour, Vector2(width, height), glowing?]. Particles
## are a weather name Arena knows ("petals", "sand", "embers", "snow", "dust") or "".

## The biome names and the choice of biome are the simulation's (Terrain), since the
## terrain is part of the battle.

const BIOMES := {
	"grassland": {
		"colours": [Color(0.42, 0.6, 0.3), Color(0.56, 0.47, 0.32), Color(0.53, 0.53, 0.52), Color(0.36, 0.55, 0.27), Color(0.47, 0.34, 0.22)],
		"sky": [Color(0.32, 0.55, 0.9), Color(0.72, 0.84, 0.95)],
		"sun": {"angle": Vector3(-50, 35, 0), "colour": Color(1.0, 0.96, 0.88), "energy": 1.1},
		"ambient": [Color(0.62, 0.68, 0.75), 0.9],
		"fog": [Color(0.72, 0.84, 0.95), 0.004],
		"props": {"tree": 0.05, "rock": 0.012, "flowers": 0.05},
		"detail": 0.22,
		"details": [[Color(0.3, 0.52, 0.22), Vector2(0.12, 0.3)], [Color(0.33, 0.57, 0.25), Vector2(0.1, 0.22)], [Color(0.95, 0.4, 0.4), Vector2(0.12, 0.2)], [Color(1.0, 0.86, 0.35), Vector2(0.12, 0.2)], [Color(0.95, 0.95, 1.0), Vector2(0.1, 0.18)], [Color(0.55, 0.55, 0.55), Vector2(0.18, 0.1)]],
		"particles": "petals",
	},
	"beach": {
		"colours": [Color(0.84, 0.76, 0.56), Color(0.74, 0.66, 0.48), Color(0.55, 0.52, 0.48), Color(0.88, 0.8, 0.6), Color(0.72, 0.64, 0.46)],
		"sky": [Color(0.2, 0.55, 0.95), Color(0.75, 0.9, 1.0)],
		"sun": {"angle": Vector3(-60, -20, 0), "colour": Color(1.0, 0.97, 0.9), "energy": 1.05},
		"ambient": [Color(0.7, 0.78, 0.85), 0.75],
		"fog": [Color(0.75, 0.9, 1.0), 0.003],
		"water": -0.4,
		"props": {"palm": 0.03, "rock": 0.01},
		"detail": 0.08,
		"details": [[Color(0.95, 0.9, 0.85), Vector2(0.14, 0.06)], [Color(0.95, 0.7, 0.65), Vector2(0.12, 0.06)], [Color(0.6, 0.58, 0.55), Vector2(0.16, 0.08)], [Color(0.45, 0.6, 0.3), Vector2(0.1, 0.25)]],
		"particles": "sand",
	},
	"volcano": {
		"colours": [Color(0.25, 0.21, 0.2), Color(0.38, 0.34, 0.32), Color(0.2, 0.18, 0.18), Color(0.36, 0.22, 0.17), Color(0.17, 0.15, 0.14)],
		"sky": [Color(0.25, 0.08, 0.06), Color(0.85, 0.35, 0.15)],
		"sun": {"angle": Vector3(-35, 60, 0), "colour": Color(1.0, 0.6, 0.4), "energy": 0.9},
		"ambient": [Color(0.8, 0.45, 0.35), 0.7],
		"fog": [Color(0.55, 0.22, 0.12), 0.012],
		"props": {"lava": 0.025, "spire": 0.02},
		"detail": 0.1,
		"details": [[Color(1.0, 0.45, 0.1), Vector2(0.5, 0.02), true], [Color(1.0, 0.6, 0.15), Vector2(0.3, 0.02), true], [Color(0.3, 0.27, 0.26), Vector2(0.2, 0.12)]],
		"particles": "embers",
	},
	"snowfield": {
		"colours": [Color(0.88, 0.92, 0.97), Color(0.74, 0.8, 0.88), Color(0.5, 0.53, 0.58), Color(0.93, 0.96, 1.0), Color(0.48, 0.5, 0.55)],
		"sky": [Color(0.45, 0.58, 0.75), Color(0.85, 0.9, 0.95)],
		"sun": {"angle": Vector3(-30, 20, 0), "colour": Color(0.92, 0.95, 1.0), "energy": 0.8},
		"ambient": [Color(0.75, 0.82, 0.92), 0.7],
		"fog": [Color(0.85, 0.9, 0.96), 0.014],
		"props": {"pine": 0.05, "ice": 0.015},
		"detail": 0.08,
		"details": [[Color(0.96, 0.98, 1.0), Vector2(0.4, 0.12)], [Color(0.5, 0.53, 0.58), Vector2(0.16, 0.1)], [Color(0.3, 0.45, 0.35), Vector2(0.1, 0.22)]],
		"particles": "snow",
	},
	"cave": {
		"colours": [Color(0.34, 0.32, 0.31), Color(0.42, 0.4, 0.38), Color(0.29, 0.28, 0.29), Color(0.31, 0.34, 0.29), Color(0.22, 0.21, 0.21)],
		"sky": [Color(0.04, 0.04, 0.06), Color(0.08, 0.08, 0.1)],
		"sun": {"angle": Vector3(-80, 10, 0), "colour": Color(0.75, 0.8, 1.0), "energy": 0.55},
		"ambient": [Color(0.45, 0.45, 0.6), 0.6],
		"fog": [Color(0.06, 0.06, 0.09), 0.03],
		"props": {"crystal": 0.03, "spire": 0.04},
		"detail": 0.12,
		"details": [[Color(0.45, 0.43, 0.41), Vector2(0.16, 0.08)], [Color(0.85, 0.55, 0.75), Vector2(0.12, 0.18), true], [Color(0.55, 0.85, 0.95), Vector2(0.1, 0.15), true], [Color(0.75, 0.68, 0.55), Vector2(0.12, 0.14)]],
		"particles": "dust",
	},
	# A cool, slightly dim day under thin haze, so the moves' colours stand out; the
	# coliseum itself comes from Stadium.
	"stadium": {
		"colours": [Color(0.78, 0.71, 0.58), Color(0.73, 0.66, 0.53), Color(0.62, 0.63, 0.6), Color(0.36, 0.48, 0.3), Color(0.45, 0.47, 0.44)],
		"sky": [Color(0.32, 0.5, 0.78), Color(0.72, 0.8, 0.88)],
		"sun": {"angle": Vector3(-56, 35, 0), "colour": Color(0.98, 0.95, 0.9), "energy": 0.9},
		"ambient": [Color(0.6, 0.66, 0.76), 0.75],
		"fog": [Color(0.72, 0.78, 0.85), 0.0012],
		"stadium": true,
		"moss": 0.35,
		"props": {},
		"particles": "",
	},
}
