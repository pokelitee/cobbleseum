class_name ArenaBiomes
extends RefCounted
## The arena biomes (concepts_brief.md §12.7): colours, sky, light, fog, weather and props for
## each, as plain data that Arena builds into a blocky world around the battle floor.
##
## Colours are [floor, floor alternate, rim, terrain top, terrain side]. Props are
## {kind: share of outer cells that get one}. Particles are a weather name Arena knows
## ("petals", "sand", "embers", "snow", "dust") or "".

## The biome names and the choice of biome are the simulation's (Terrain), since the
## terrain is part of the battle.

const BIOMES := {
	"grassland": {
		"colours": [Color(0.45, 0.62, 0.32), Color(0.41, 0.58, 0.29), Color(0.52, 0.5, 0.46), Color(0.38, 0.6, 0.28), Color(0.47, 0.34, 0.22)],
		"sky": [Color(0.32, 0.55, 0.9), Color(0.72, 0.84, 0.95)],
		"sun": {"angle": Vector3(-50, 35, 0), "colour": Color(1.0, 0.96, 0.88), "energy": 1.1},
		"ambient": [Color(0.62, 0.68, 0.75), 0.9],
		"fog": [Color(0.72, 0.84, 0.95), 0.004],
		"hills": 7.0,
		"props": {"tree": 0.05, "rock": 0.012, "flowers": 0.05},
		"particles": "petals",
	},
	"beach": {
		"colours": [Color(0.82, 0.74, 0.54), Color(0.78, 0.7, 0.5), Color(0.62, 0.56, 0.44), Color(0.84, 0.77, 0.56), Color(0.72, 0.64, 0.46)],
		"sky": [Color(0.2, 0.55, 0.95), Color(0.75, 0.9, 1.0)],
		"sun": {"angle": Vector3(-60, -20, 0), "colour": Color(1.0, 0.97, 0.9), "energy": 1.05},
		"ambient": [Color(0.7, 0.78, 0.85), 0.75],
		"fog": [Color(0.75, 0.9, 1.0), 0.003],
		"hills": 2.0,
		"water": -0.4,
		"props": {"palm": 0.03, "rock": 0.01},
		"particles": "sand",
	},
	"volcano": {
		"colours": [Color(0.22, 0.19, 0.18), Color(0.27, 0.22, 0.2), Color(0.35, 0.18, 0.12), Color(0.2, 0.17, 0.16), Color(0.14, 0.12, 0.12)],
		"sky": [Color(0.25, 0.08, 0.06), Color(0.85, 0.35, 0.15)],
		"sun": {"angle": Vector3(-35, 60, 0), "colour": Color(1.0, 0.6, 0.4), "energy": 0.9},
		"ambient": [Color(0.8, 0.45, 0.35), 0.7],
		"fog": [Color(0.55, 0.22, 0.12), 0.012],
		"hills": 9.0,
		"props": {"lava": 0.025, "spire": 0.02},
		"particles": "embers",
	},
	"snowfield": {
		"colours": [Color(0.84, 0.88, 0.93), Color(0.78, 0.83, 0.9), Color(0.55, 0.62, 0.7), Color(0.88, 0.92, 0.97), Color(0.55, 0.6, 0.66)],
		"sky": [Color(0.45, 0.58, 0.75), Color(0.85, 0.9, 0.95)],
		"sun": {"angle": Vector3(-30, 20, 0), "colour": Color(0.92, 0.95, 1.0), "energy": 0.8},
		"ambient": [Color(0.75, 0.82, 0.92), 0.7],
		"fog": [Color(0.85, 0.9, 0.96), 0.014],
		"hills": 8.0,
		"props": {"pine": 0.05, "ice": 0.015},
		"particles": "snow",
	},
	"cave": {
		"colours": [Color(0.36, 0.34, 0.33), Color(0.32, 0.3, 0.3), Color(0.24, 0.23, 0.24), Color(0.3, 0.28, 0.28), Color(0.22, 0.21, 0.21)],
		"sky": [Color(0.04, 0.04, 0.06), Color(0.08, 0.08, 0.1)],
		"sun": {"angle": Vector3(-80, 10, 0), "colour": Color(0.75, 0.8, 1.0), "energy": 0.55},
		"ambient": [Color(0.45, 0.45, 0.6), 0.6],
		"fog": [Color(0.06, 0.06, 0.09), 0.03],
		"hills": 14.0,
		"props": {"crystal": 0.03, "spire": 0.04},
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
		"hills": 0.0,
		"stadium": true,
		"moss": 0.35,
		"props": {},
		"particles": "",
	},
}
