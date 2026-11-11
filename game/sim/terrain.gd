class_name Terrain
extends RefCounted
## Battle terrain (concepts_brief.md §9.8): one continuous landscape, a ground height for every
## 1 m cell in 0.5 m steps, generated from the battle seed for its biome. Inside the arena it
## stays gentle: noise mounds whose contours become terraces, walkable where neighbouring cells
## differ by a step and cliffs where they differ more. Beyond the arena's wall it rises into
## hills (or, at the beach, falls into the sea), so the battle area is part of the world rather
## than a disc cut out of it. Features stand on the ground: rock clusters, trees, logs, basalt
## columns, stalagmites, ice spikes and crystals. Each fighter's starting spot is kept level and
## open, and the two starts are always connected by walkable ground.
##
## The battle is still played on the floor plane, with heights on top:
## - a fighter stands at the height of the cell under its centre, and can't step up onto a
##   cell more than Rules.CLIMB higher (fliers Rules.FLY_CLIMB); stepping down is free;
## - projectiles fly in 3D and stop when the ground or a feature rises above them;
## - melee and area moves only reach across small height differences.
## The battle only generates the arena and a margin around it (BATTLE_RADIUS); the
## presentation calls fill_world() for the rest of the land out to WORLD_RADIUS, from the same
## noise, and builds the world from the same heights and kinds.

## Which arena a battle is in (the biome's look and its terrain).
const BIOMES: Array[String] = ["grassland", "beach", "volcano", "snowfield", "cave", "stadium"]
## Biomes that suit each type, for picking an arena from the fighters.
const BY_TYPE := {
	"Fire": "volcano", "Ice": "snowfield", "Water": "beach", "Rock": "cave", "Ground": "cave",
	"Ghost": "cave", "Dark": "cave", "Grass": "grassland", "Bug": "grassland", "Flying": "grassland",
	"Steel": "stadium", "Fighting": "stadium", "Normal": "stadium",
}
## What stands in a cell, for the presentation (the battle only uses heights).
enum Kind { GROUND, ROCK, TREE, PINE, PALM, LOG, BASALT, STALAGMITE, ICE, CRYSTAL }
## Per biome: how high the arena's mounds rise (metres, before snapping to STEP), how high the
## hills beyond the wall rise, and how many of each feature stand inside the arena. A feature
## count is a range. The stadium is the flat classic.
const SHAPES := {
	"grassland": {"mounds": 1.6, "hills": 8.0, "features": {"tree": Vector2i(5, 8), "rock": Vector2i(3, 5), "log": Vector2i(1, 2)}},
	"beach": {"mounds": 1.1, "hills": -5.0, "features": {"palm": Vector2i(3, 5), "rock": Vector2i(2, 4), "log": Vector2i(2, 3)}},
	"volcano": {"mounds": 2.2, "hills": 10.0, "features": {"basalt": Vector2i(4, 6), "rock": Vector2i(3, 4)}},
	"snowfield": {"mounds": 1.6, "hills": 9.0, "features": {"pine": Vector2i(5, 8), "ice": Vector2i(3, 5), "rock": Vector2i(2, 3)}},
	"cave": {"mounds": 2.2, "hills": 15.0, "features": {"stalagmite": Vector2i(9, 13), "crystal": Vector2i(3, 5), "rock": Vector2i(2, 3)}},
	"stadium": {"mounds": 0.0, "hills": 0.0, "features": {}},
}
const STEP := 0.5
## How far the generated world reaches (the presentation's terrain).
const WORLD_RADIUS := Rules.ARENA_RADIUS + 30.0
const BATTLE_RADIUS := Rules.ARENA_RADIUS + NEAR_CELLS + 2.0
## The hills rise over this distance beyond the wall.
const HILL_RISE := 14.0
## Noise frequencies: the arena's mounds and the hills beyond.
const MOUND_FREQUENCY := 0.075
const HILL_FREQUENCY := 0.045
## Kept level and open around each starting spot, blending back into the land over START_BLEND.
const START_CLEAR := 2.5
const START_BLEND := 2.0
## Features keep this far from the wall and from each other's centres.
const FEATURE_WALL_MARGIN := 1.5
const FEATURE_SPACING := 2.5
## If the starts aren't connected, try again with the land and features toned down this much,
## up to RETRIES times, then fall back to flat ground.
const RETRY_SCALE := 0.7
const RETRIES := 4
## Projectile and sight lines are checked every this many metres.
const LINE_STEP := 0.25
## Cells within this many of another count as near it (see _nearby_top).
const NEAR_CELLS := 3

var biome := "stadium"
var _reach := 0
var _size := 0
var _heights := PackedFloat32Array()
## The ground under any feature, and what stands in each cell (Kind).
var _ground := PackedFloat32Array()
var _kinds := PackedByteArray()
## For each cell in the arena, the highest ground within NEAR_CELLS of it, and the highest in
## the arena, so the checks that run every tick can stop early where nothing nearby rises.
var _nearby_top := PackedFloat32Array()
var _highest := 0.0
## How the land was shaped, so fill_world() can extend it.
var _shape := {}
var _noise_seed := 0
var _scale := 1.0
var _filled_to := 0.0


## The arena for a battle: `requested` if it names a biome, else one picked by `seed` from the
## biomes the fighters' types suit, plus grassland and stadium.
static func choose_biome(requested: String, types: Array, seed: int) -> String:
	if requested in BIOMES:
		return requested
	var options: Array[String] = ["grassland", "stadium"]
	for type: String in types:
		var suited: String = BY_TYPE.get(type, "")
		if not suited.is_empty() and not options.has(suited):
			options.append(suited)
	options.sort()
	return options[posmod(seed, options.size())]


## A flat world (tests, and the stadium).
static func flat(biome_name := "stadium") -> Terrain:
	var terrain := Terrain.new()
	terrain.biome = biome_name
	terrain._reach = ceili(WORLD_RADIUS) + 1
	terrain._size = terrain._reach * 2
	var cells := terrain._size * terrain._size
	terrain._heights.resize(cells)
	terrain._ground.resize(cells)
	terrain._kinds.resize(cells)
	terrain._nearby_top.resize(cells)
	return terrain


## The terrain of `biome_name`, from the battle's terrain stream.
static func generate(biome_name: String, random: SimRandom) -> Terrain:
	var shape: Dictionary = SHAPES.get(biome_name, SHAPES.stadium)
	var noise_seed := int(random.next_u32() & 0x7fffffff)
	var scale := 1.0
	for attempt in RETRIES + 1:
		var terrain := flat(biome_name)
		terrain._shape = shape
		terrain._noise_seed = noise_seed
		terrain._scale = scale
		if shape.mounds > 0.0 or shape.hills != 0.0:
			terrain._shape_land(BATTLE_RADIUS, 0.0)
			terrain._place_features(shape.features, random, scale)
		terrain._summarise()
		if terrain.starts_connected():
			return terrain
		scale *= RETRY_SCALE
	var fallback := flat(biome_name)
	fallback._summarise()
	return fallback


static func starts() -> Array[Vector2]:
	return [Vector2(0, -0.5 * Rules.START_DISTANCE), Vector2(0, 0.5 * Rules.START_DISTANCE)]


## Extends the land beyond the battle's part out to WORLD_RADIUS (the presentation's world).
## The battle never looks there, so it only costs a battle that's shown.
func fill_world() -> void:
	if _filled_to < WORLD_RADIUS and (_shape.get("mounds", 0.0) > 0.0 or _shape.get("hills", 0.0) != 0.0):
		_shape_land(WORLD_RADIUS, _filled_to)


## Shapes the land in the ring from `inside` to `radius` (cells already shaped are kept).
func _shape_land(radius: float, inside: float) -> void:
	var shape := _shape
	var scale := _scale
	var mounds := FastNoiseLite.new()
	mounds.seed = _noise_seed
	mounds.frequency = MOUND_FREQUENCY
	var hills := FastNoiseLite.new()
	hills.seed = _noise_seed + 1
	hills.frequency = HILL_FREQUENCY
	var level := []
	for start in starts():
		level.append(_raw_height(start, shape, mounds, hills, scale))
	_filled_to = radius
	for cell in world_cells(radius):
		if cell.length() <= inside:
			continue
		var raw := _raw_height(cell, shape, mounds, hills, scale)
		# Level the starting spots, blending back into the land around them.
		for s in 2:
			var distance := cell.distance_to(starts()[s])
			if distance < START_CLEAR + START_BLEND:
				var keep := clampf((distance - START_CLEAR) / START_BLEND, 0.0, 1.0)
				raw = lerpf(snappedf(level[s], STEP), raw, keep)
		var height := snappedf(raw, STEP)
		_put(cell, height)
		_put_ground(cell, height)


## The land's height at `point` before snapping: mounds inside the arena (half of the ground
## stays low, the rest rises in mounds), easing into hills beyond the wall.
static func _raw_height(point: Vector2, shape: Dictionary, mounds: FastNoiseLite, hills: FastNoiseLite, scale: float) -> float:
	var inner := float(shape.mounds) * scale * maxf(0.0, mounds.get_noise_2d(point.x, point.y)) * 2.0
	var distance := point.length()
	if distance <= Rules.ARENA_RADIUS:
		return inner
	var rise := smoothstep(0.0, 1.0, (distance - Rules.ARENA_RADIUS) / HILL_RISE)
	var hill := float(shape.hills) * (0.55 + 0.45 * hills.get_noise_2d(point.x, point.y))
	return lerpf(inner, hill, rise)


func _place_features(counts: Dictionary, random: SimRandom, scale: float) -> void:
	var kinds: Array = counts.keys()
	kinds.sort()
	var centres: Array[Vector2] = []
	for kind: String in kinds:
		var range_: Vector2i = counts[kind]
		var wanted := roundi((range_.x + int(random.next_u32() % (range_.y - range_.x + 1))) * scale)
		for n in wanted:
			for attempt in 30:
				var angle := random.next_float() * TAU
				var reach := (Rules.ARENA_RADIUS - FEATURE_WALL_MARGIN) * sqrt(random.next_float())
				var at := Vector2(cos(angle), sin(angle)) * reach
				var cell := Vector2(floorf(at.x) + 0.5, floorf(at.y) + 0.5)
				if starts().any(func(s: Vector2) -> bool: return s.distance_to(cell) < START_CLEAR + 1.5):
					continue
				if centres.any(func(c: Vector2) -> bool: return c.distance_to(cell) < FEATURE_SPACING):
					continue
				_stamp(kind, cell, random)
				centres.append(cell)
				break


## Raises one feature of `kind` at `cell`, on top of the ground.
func _stamp(kind: String, cell: Vector2, random: SimRandom) -> void:
	match kind:
		"rock":
			# A cluster: a tall centre and a few lower stones around it.
			var top := snappedf(lerpf(2.0, 3.0, random.next_float()), STEP)
			_raise(cell, top, Kind.ROCK)
			for n in 2 + int(random.next_u32() % 4):
				var side := _neighbour(cell, random)
				_raise(side, maxf(1.0, snappedf(top - lerpf(0.5, 1.5, random.next_float()), STEP)), Kind.ROCK)
		"tree":
			_raise(cell, 3.5, Kind.TREE)
		"pine":
			_raise(cell, 4.0, Kind.PINE)
		"palm":
			_raise(cell, 4.0, Kind.PALM)
		"log":
			# A fallen log two or three cells long, low enough to step onto.
			var along := Vector2(1, 0) if random.chance(0.5) else Vector2(0, 1)
			for i in 2 + int(random.next_u32() % 2):
				_raise(cell + along * i, STEP, Kind.LOG)
		"basalt":
			# A cluster of columns of stepped heights.
			var top := snappedf(lerpf(2.5, 4.0, random.next_float()), STEP)
			_raise(cell, top, Kind.BASALT)
			for n in 3 + int(random.next_u32() % 3):
				_raise(_neighbour(cell, random), maxf(1.0, snappedf(top - lerpf(0.5, 2.0, random.next_float()), STEP)), Kind.BASALT)
		"stalagmite":
			var top := snappedf(lerpf(2.5, 4.5, random.next_float()), STEP)
			_raise(cell, top, Kind.STALAGMITE)
			if random.chance(0.5):
				_raise(_neighbour(cell, random), snappedf(top * 0.5, STEP), Kind.STALAGMITE)
		"ice":
			_raise(cell, snappedf(lerpf(2.0, 3.5, random.next_float()), STEP), Kind.ICE)
			if random.chance(0.5):
				_raise(_neighbour(cell, random), 1.5, Kind.ICE)
		"crystal":
			_raise(cell, snappedf(lerpf(1.5, 2.5, random.next_float()), STEP), Kind.CRYSTAL)


func _neighbour(cell: Vector2, random: SimRandom) -> Vector2:
	var sides := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	return cell + sides[random.next_u32() % sides.size()]


## Puts a feature `height` above the ground at `cell` (inside the arena only).
func _raise(cell: Vector2, height: float, kind: Kind) -> void:
	if cell.length() > Rules.ARENA_RADIUS - 0.5:
		return
	var top := ground_at(cell) + height
	if top > height_at(cell):
		_put(cell, top)
		var index := _index(cell)
		if index >= 0:
			_kinds[index] = kind


## Whether each start can walk to the other (up at most Rules.CLIMB per cell, down freely).
func starts_connected() -> bool:
	var ends := starts()
	return _reachable(ends[0], ends[1]) and _reachable(ends[1], ends[0])


func _reachable(from: Vector2, to: Vector2) -> bool:
	var start := Vector2(floorf(from.x) + 0.5, floorf(from.y) + 0.5)
	var goal := Vector2(floorf(to.x) + 0.5, floorf(to.y) + 0.5)
	var seen := {start: true}
	var queue: Array[Vector2] = [start]
	while not queue.is_empty():
		var cell: Vector2 = queue.pop_front()
		if cell == goal:
			return true
		for side in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var next: Vector2 = cell + side
			if seen.has(next) or next.length() > Rules.ARENA_RADIUS - 0.5:
				continue
			if height_at(next) - height_at(cell) > Rules.CLIMB + 1e-4:
				continue
			seen[next] = true
			queue.append(next)
	return false


func _summarise() -> void:
	_highest = 0.0
	var arena := ceili(Rules.ARENA_RADIUS) + NEAR_CELLS + 1
	for i in range(_reach - arena, _reach + arena):
		for j in range(_reach - arena, _reach + arena):
			var top := 0.0
			for di in range(-NEAR_CELLS, NEAR_CELLS + 1):
				for dj in range(-NEAR_CELLS, NEAR_CELLS + 1):
					var a := i + di
					var b := j + dj
					if a >= 0 and b >= 0 and a < _size and b < _size:
						top = maxf(top, _heights[a * _size + b])
			_nearby_top[i * _size + j] = top
			if Vector2(i - _reach + 0.5, j - _reach + 0.5).length() <= Rules.ARENA_RADIUS + 0.5:
				_highest = maxf(_highest, _heights[i * _size + j])


## Every cell's centre inside the arena.
func cells() -> Array[Vector2]:
	return world_cells(Rules.ARENA_RADIUS + 0.5)


## Every cell's centre within `radius` of the middle.
func world_cells(radius: float) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var reach := mini(_reach, ceili(radius) + 1)
	for i in range(-reach, reach):
		for j in range(-reach, reach):
			var centre := Vector2(i + 0.5, j + 0.5)
			if centre.length() <= radius:
				found.append(centre)
	return found


func _index(point: Vector2) -> int:
	var i := int(floorf(point.x)) + _reach
	var j := int(floorf(point.y)) + _reach
	if i < 0 or j < 0 or i >= _size or j >= _size:
		return -1
	return i * _size + j


func _put(point: Vector2, height: float) -> void:
	var index := _index(point)
	if index >= 0:
		_heights[index] = height


func _put_ground(point: Vector2, height: float) -> void:
	var index := _index(point)
	if index >= 0:
		_ground[index] = height


## The height of whatever is under `point`, ground or feature (0 outside the world).
func height_at(point: Vector2) -> float:
	var index := _index(point)
	return _heights[index] if index >= 0 else 0.0


## The ground under any feature at `point`.
func ground_at(point: Vector2) -> float:
	var index := _index(point)
	return _ground[index] if index >= 0 else 0.0


## What stands at `point` (Kind.GROUND for bare ground).
func kind_at(point: Vector2) -> Kind:
	var index := _index(point)
	return _kinds[index] as Kind if index >= 0 else Kind.GROUND


## `position` pushed out of every cell a fighter of `radius` standing at `ground` can't climb
## onto (more than `climb` higher), so it slides along cliffs and features.
func push_out(position: Vector2, radius: float, ground: float, climb: float) -> Vector2:
	var index := _index(position)
	if index < 0 or _nearby_top[index] <= ground + climb + 1e-4:
		return position
	var result := position
	for pass_ in 2:
		for i in range(int(floorf(result.x - radius)) - 1, int(floorf(result.x + radius)) + 2):
			for j in range(int(floorf(result.y - radius)) - 1, int(floorf(result.y + radius)) + 2):
				var corner := Vector2(i, j)
				if height_at(corner + Vector2(0.5, 0.5)) <= ground + climb + 1e-4:
					continue
				var nearest := Vector2(clampf(result.x, i, i + 1), clampf(result.y, j, j + 1))
				var away := result - nearest
				if away.length_squared() < 1e-10:
					# The centre is inside the cell: leave by the nearest side.
					var exits := [Vector2(i - radius, result.y), Vector2(i + 1 + radius, result.y),
						Vector2(result.x, j - radius), Vector2(result.x, j + 1 + radius)]
					exits.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(result) < b.distance_squared_to(result))
					result = exits[0]
				elif away.length() < radius:
					result = nearest + away.normalized() * radius
	return result


## Whether a straight line from `from` to `to` (x, height, z) stays above the ground.
func clear_line(from: Vector3, to: Vector3) -> bool:
	if minf(from.y, to.y) >= _highest:
		return true
	var length := Vector2(to.x - from.x, to.z - from.z).length()
	var steps := maxi(1, ceili(length / LINE_STEP))
	for s in range(1, steps):
		var point := from.lerp(to, float(s) / steps)
		if height_at(Vector2(point.x, point.z)) > point.y:
			return false
	return true


## The direction closest to `wanted` that a fighter at `position` can walk without running
## into ground it can't climb (checked a little ahead), or Vector2.ZERO if `wanted` is zero.
func steer(position: Vector2, radius: float, ground: float, climb: float, wanted: Vector2) -> Vector2:
	if wanted.length_squared() < 1e-8:
		return Vector2.ZERO
	var probe := radius + 0.6
	for turn in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8]:
		var direction: Vector2 = wanted.rotated(turn * PI / 8.0)
		var ahead: Vector2 = position + direction.normalized() * probe
		if height_at(ahead) <= ground + climb + 1e-4 and ahead.length() < Rules.ARENA_RADIUS - radius:
			return direction
	return wanted


## The highest ground or feature in the arena (for tests and cameras).
func highest() -> float:
	return _highest
