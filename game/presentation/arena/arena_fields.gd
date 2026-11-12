class_name ArenaFields
extends RefCounted
## How each field (Terrain.FIELDS) looks (concepts_brief.md §12.7): its colours, props and
## small details, as plain data that Arena builds the ground from. The sky, light, fog and
## particles come from the arena preset (Arenas), so a field can sit under any of them.
##
## Colours are [ground, patches (paths, gravel, ash), stone (cliffs and rock), higher ground,
## earth (the sides of the ground)]. Props are {kind: share of cells beyond the arena that get
## one}; open venues only. Details are small things on the ground that the battle ignores,
## grouped in patches: `detail` is the share of cells inside a patch (near the arena) that get
## a cluster, `details` is {kind: weight} over the kinds Arena knows ("grass", "flower",
## "pebble", "shell", "drift", "crack", "mushroom"). `water` is the sea level, for open venues.

const FIELDS := {
	"grassland": {
		"colours": [Color(0.42, 0.6, 0.3), Color(0.56, 0.47, 0.32), Color(0.53, 0.53, 0.52), Color(0.36, 0.55, 0.27), Color(0.47, 0.34, 0.22)],
		"props": {"tree": 0.05, "rock": 0.012, "flowers": 0.05},
		"detail": 0.55,
		"details": {"grass": 6, "flower": 2, "pebble": 1},
	},
	"beach": {
		"colours": [Color(0.84, 0.76, 0.56), Color(0.74, 0.66, 0.48), Color(0.55, 0.52, 0.48), Color(0.88, 0.8, 0.6), Color(0.72, 0.64, 0.46)],
		"water": -0.4,
		"props": {"palm": 0.03, "rock": 0.01},
		"detail": 0.25,
		"details": {"shell": 3, "pebble": 2, "grass": 1},
	},
	"volcano": {
		"colours": [Color(0.25, 0.21, 0.2), Color(0.38, 0.34, 0.32), Color(0.2, 0.18, 0.18), Color(0.36, 0.22, 0.17), Color(0.17, 0.15, 0.14)],
		"props": {"lava": 0.025, "spire": 0.02},
		"detail": 0.3,
		"details": {"crack": 3, "pebble": 2},
	},
	"snowfield": {
		"colours": [Color(0.88, 0.92, 0.97), Color(0.74, 0.8, 0.88), Color(0.5, 0.53, 0.58), Color(0.93, 0.96, 1.0), Color(0.48, 0.5, 0.55)],
		"props": {"pine": 0.05, "ice": 0.015},
		"detail": 0.3,
		"details": {"drift": 3, "pebble": 1, "grass": 1},
	},
	"cave": {
		"colours": [Color(0.34, 0.32, 0.31), Color(0.42, 0.4, 0.38), Color(0.29, 0.28, 0.29), Color(0.31, 0.34, 0.29), Color(0.22, 0.21, 0.21)],
		"props": {"crystal": 0.03, "spire": 0.04},
		"detail": 0.35,
		"details": {"pebble": 3, "mushroom": 2},
	},
	# The coliseum's paving (Coliseum) has its own colours; these are for anything else on it.
	"paved": {
		"colours": [Color(0.78, 0.71, 0.58), Color(0.73, 0.66, 0.53), Color(0.62, 0.63, 0.6), Color(0.36, 0.48, 0.3), Color(0.45, 0.47, 0.44)],
		"props": {},
	},
}
