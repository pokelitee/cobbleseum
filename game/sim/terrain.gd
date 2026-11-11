class_name Terrain
extends RefCounted
## Battle terrain (concepts_brief.md §9.8): a ground height for every 1 m cell of the arena,
## in 0.5 m steps, generated from the battle seed for its biome. Plateaus rise from the floor
## with a ramp of 0.5 m steps down one side and cliffs elsewhere; pillars of cover stand on
## the ground. Each fighter's starting spot is kept flat and open.
##
## The battle is still played on the floor plane, with heights on top:
## - a fighter stands at the height of the cell under its centre, and can't step up onto a
##   cell more than Rules.CLIMB higher (fliers Rules.FLY_CLIMB); stepping down is free;
## - projectiles fly in 3D and stop when the ground or a pillar rises above them;
## - melee and area moves only reach across small height differences.

## Which arena a battle is in (the biome's look and its terrain).
const BIOMES: Array[String] = ["grassland", "beach", "volcano", "snowfield", "cave", "stadium"]
## Biomes that suit each type, for picking an arena from the fighters.
const BY_TYPE := {
	"Fire": "volcano", "Ice": "snowfield", "Water": "beach", "Rock": "cave", "Ground": "cave",
	"Ghost": "cave", "Dark": "cave", "Grass": "grassland", "Bug": "grassland", "Flying": "grassland",
	"Steel": "stadium", "Fighting": "stadium", "Normal": "stadium",
}
## Per biome: plateau count and height (metres, in STEP multiples), pillar count and height.
## The stadium is the flat classic.
const SHAPES := {
	"grassland": {"plateaus": Vector2i(2, 3), "plateau_height": Vector2(0.5, 1.0), "pillars": Vector2i(6, 9), "pillar_height": Vector2(2.0, 3.0)},
	"beach": {"plateaus": Vector2i(2, 3), "plateau_height": Vector2(0.5, 0.5), "pillars": Vector2i(4, 6), "pillar_height": Vector2(1.5, 2.0)},
	"volcano": {"plateaus": Vector2i(3, 4), "plateau_height": Vector2(1.0, 1.5), "pillars": Vector2i(8, 11), "pillar_height": Vector2(2.5, 4.0)},
	"snowfield": {"plateaus": Vector2i(2, 3), "plateau_height": Vector2(0.5, 1.0), "pillars": Vector2i(6, 9), "pillar_height": Vector2(2.0, 2.5)},
	"cave": {"plateaus": Vector2i(3, 4), "plateau_height": Vector2(0.5, 1.5), "pillars": Vector2i(10, 13), "pillar_height": Vector2(3.0, 4.0)},
	"stadium": {"plateaus": Vector2i(0, 0), "plateau_height": Vector2(0.0, 0.0), "pillars": Vector2i(0, 0), "pillar_height": Vector2(0.0, 0.0)},
}
const STEP := 0.5
## Kept flat and open around each starting spot.
const START_CLEAR := 2.5
const PLATEAU_RADIUS := Vector2(2.0, 3.5)
## The share of a plateau's edge, around a random direction, that steps down as a ramp.
const RAMP_SHARE := 0.3
## Pillars keep this far from the wall and from each other.
const PILLAR_WALL_MARGIN := 1.5
const PILLAR_SPACING := 3.0
## Projectile and sight lines are checked every this many metres.
const LINE_STEP := 0.25

## Cells within this many of another count as near it (see _nearby_top).
const NEAR_CELLS := 3

var biome := "stadium"
var _reach := 0
var _size := 0
var _heights := PackedFloat32Array()
## For each cell, the highest ground within NEAR_CELLS of it, and the highest anywhere, so the
## checks that run every tick can stop early where nothing nearby rises.
var _nearby_top := PackedFloat32Array()
var _highest := 0.0


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


## A flat arena (tests, and the stadium).
static func flat(biome_name := "stadium") -> Terrain:
	var terrain := Terrain.new()
	terrain.biome = biome_name
	terrain._reach = ceili(Rules.ARENA_RADIUS) + 1
	terrain._size = terrain._reach * 2
	terrain._heights.resize(terrain._size * terrain._size)
	terrain._nearby_top.resize(terrain._size * terrain._size)
	return terrain


## The terrain of `biome_name`, from the battle's terrain stream.
static func generate(biome_name: String, random: SimRandom) -> Terrain:
	var terrain := flat(biome_name)
	var shape: Dictionary = SHAPES.get(biome_name, SHAPES.stadium)
	var starts: Array[Vector2] = [Vector2(0, -0.5 * Rules.START_DISTANCE), Vector2(0, 0.5 * Rules.START_DISTANCE)]
	var plateaus := _pick(random, shape.plateaus)
	for p in plateaus:
		for attempt in 20:
			var radius := lerpf(PLATEAU_RADIUS.x, PLATEAU_RADIUS.y, random.next_float())
			var centre := _random_point(random, Rules.ARENA_RADIUS - radius - 1.0)
			if starts.any(func(s: Vector2) -> bool: return s.distance_to(centre) < START_CLEAR + radius + 2.0):
				continue
			var height := snappedf(lerpf(shape.plateau_height.x, shape.plateau_height.y, random.next_float()), STEP)
			terrain._raise_plateau(centre, radius, maxf(height, STEP), random.next_float() * TAU)
			break
	var pillars: Array[Vector2] = []
	for p in _pick(random, shape.pillars):
		for attempt in 30:
			var at := _random_point(random, Rules.ARENA_RADIUS - PILLAR_WALL_MARGIN)
			var cell := Vector2(floorf(at.x) + 0.5, floorf(at.y) + 0.5)
			if starts.any(func(s: Vector2) -> bool: return s.distance_to(cell) < START_CLEAR + 1.0):
				continue
			if pillars.any(func(q: Vector2) -> bool: return q.distance_to(cell) < PILLAR_SPACING):
				continue
			var height := snappedf(lerpf(shape.pillar_height.x, shape.pillar_height.y, random.next_float()), STEP)
			terrain._put(cell, terrain.height_at(cell) + height)
			pillars.append(cell)
			break
	terrain._summarise()
	return terrain


func _summarise() -> void:
	_nearby_top.resize(_heights.size())
	_highest = 0.0
	for i in _size:
		for j in _size:
			var top := 0.0
			for di in range(-NEAR_CELLS, NEAR_CELLS + 1):
				for dj in range(-NEAR_CELLS, NEAR_CELLS + 1):
					var a := i + di
					var b := j + dj
					if a >= 0 and b >= 0 and a < _size and b < _size:
						top = maxf(top, _heights[a * _size + b])
			_nearby_top[i * _size + j] = top
			_highest = maxf(_highest, _heights[i * _size + j])


static func _pick(random: SimRandom, range_: Vector2i) -> int:
	return range_.x + int(random.next_u32() % (range_.y - range_.x + 1))


static func _random_point(random: SimRandom, within: float) -> Vector2:
	var angle := random.next_float() * TAU
	return Vector2(cos(angle), sin(angle)) * within * sqrt(random.next_float())


func _raise_plateau(centre: Vector2, radius: float, height: float, ramp_angle: float) -> void:
	var ramp_cells := int(height / STEP)
	for cell in cells():
		var distance := cell.distance_to(centre)
		var level := 0.0
		if distance <= radius:
			level = height
		elif distance <= radius + ramp_cells:
			var off := absf(angle_difference((cell - centre).angle(), ramp_angle))
			if off <= RAMP_SHARE * PI:
				level = height - ceilf(distance - radius) * STEP
		if level > height_at(cell):
			_put(cell, level)


## Every cell's centre inside the arena.
func cells() -> Array[Vector2]:
	var found: Array[Vector2] = []
	for i in range(-_reach, _reach):
		for j in range(-_reach, _reach):
			var centre := Vector2(i + 0.5, j + 0.5)
			if centre.length() <= Rules.ARENA_RADIUS + 0.5:
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


## The ground height under `point` (0 outside the grid).
func height_at(point: Vector2) -> float:
	var index := _index(point)
	return _heights[index] if index >= 0 else 0.0


## `position` pushed out of every cell a fighter of `radius` standing at `ground` can't climb
## onto (more than `climb` higher), so it slides along cliffs and pillars.
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


## The highest ground in the arena (for tests and cameras).
func highest() -> float:
	return _highest
