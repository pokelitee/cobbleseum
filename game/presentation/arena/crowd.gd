class_name Crowd
extends Node3D
## Spectators (concepts_brief.md §12.7), in venues with stands only: a crowd of low-poly
## figures filling most of the coliseum's seats, drawn as one MultiMesh and animated in its
## shader (crowd.gdshader), and a few watchers of the arena's types in the front row. They
## sway while they wait and cheer at big hits and knockouts: figures hop and raise their arms
## (more of them the bigger the moment), and the watchers cry. Presentation only, seeded by
## the battle.

const SHADER := preload("res://game/presentation/arena/crowd.gdshader")
## A preset's "crowd" may set "fill" (the share of seats taken, 0 to 1) and "watchers" (how
## many watchers sit in the front row, up to Arenas.MAX_WATCHERS); these are the defaults.
const FILL := 0.75
const WATCHERS := 4
## The heights (metres) of Pokémon that fit a seat.
const WATCHER_HEIGHT := Vector2(0.4, 2.2)
## Figures this close to a watcher's seat make room for it.
const WATCHER_ROOM := 1.6
## Excitement falls by this share per frame once a cheer's hold ends.
const CALM := 0.04
## Where the arms hang from (metres up the figure); the shader raises them about it.
const SHOULDER := 0.92
## Cheers at least this excited make the watchers cry.
const LOUD := 0.8
const SHIRTS: Array[Color] = [
	Color(0.85, 0.25, 0.22), Color(0.22, 0.42, 0.8), Color(0.95, 0.8, 0.25), Color(0.3, 0.65, 0.35),
	Color(0.92, 0.92, 0.9), Color(0.55, 0.35, 0.7), Color(0.95, 0.55, 0.2), Color(0.25, 0.25, 0.28),
]

## The watchers, and the figures' MultiMesh (null without stands).
var watchers: Array[FighterView] = []
var figures: MultiMeshInstance3D
var excitement := 0.0
## This arena's share of seats taken and number of watchers.
var fill := FILL
var watcher_count := WATCHERS

var _material: ShaderMaterial
var _time := 0.0
var _time_scale := 1.0
var _hold := 0
var _rng := RandomNumberGenerator.new()
## Seats left for figures (world transforms), and the front row's, for the watchers.
var _seats: Array[Transform3D] = []
var _front: Array[Transform3D] = []
## Each watcher's place on the floor, re-applied every frame so its head follows the battle.
var _watcher_places: Array[Vector2] = []
var _watcher_heights: Array[float] = []


## The crowd for `arena`, seeded by `seed`: figures in the seats of a venue with stands, none
## in the open, as the preset's crowd `settings` say. Add watchers with add_watcher() before
## the figures are placed by build().
static func create(arena: Arena, seed: int, settings: Dictionary = {}) -> Crowd:
	var crowd := Crowd.new()
	crowd.name = "Crowd"
	crowd.fill = float(settings.get("fill", FILL))
	crowd.watcher_count = int(settings.get("watchers", WATCHERS))
	crowd._rng.seed = hash("crowd|%d" % seed)
	if arena.theme.is_empty():
		return crowd
	var front_height := Coliseum.row(0).y
	for seat in arena.seats:
		crowd._seats.append(seat)
		if is_equal_approx(seat.origin.y, front_height):
			crowd._front.append(seat)
	return crowd


## Species that could watch an arena that suits `types`: ones of those types that fit
## a seat, not the fighters themselves, picked by `rng` (sorted first, so the pick is repeatable).
static func choose_watchers(types: Array, roster: Dictionary, species: Dictionary, exclude: Array,
		rng: RandomNumberGenerator, count := WATCHERS) -> Array[String]:
	var candidates: Array[String] = []
	for id: String in roster:
		var height := float(roster[id].get("height", 0.0))
		if id in exclude or height < WATCHER_HEIGHT.x or height > WATCHER_HEIGHT.y:
			continue
		var own: Array = species.get(id, {}).get("types", [])
		if own.any(func(type: Variant) -> bool: return type in types):
			candidates.append(id)
	candidates.sort()
	var chosen: Array[String] = []
	while chosen.size() < count and not candidates.is_empty():
		chosen.append(candidates.pop_at(rng.randi() % candidates.size()))
	return chosen


## The seats the watchers take: spread around the front row, one per share of the circle.
func watcher_seats(count: int) -> Array[Transform3D]:
	var picked: Array[Transform3D] = []
	if _front.is_empty():
		return picked
	for i in count:
		var angle := (i + 0.5 + _rng.randf_range(-0.2, 0.2)) * TAU / count
		var best := _front[0]
		for seat in _front:
			if _angle_gap(seat, angle) < _angle_gap(best, angle):
				best = seat
		picked.append(best)
	return picked


## Seats a watcher at `seat`, facing the field and watching `fighter`, and clears the figures
## around it.
func add_watcher(view: FighterView, seat: Transform3D, fighter: FighterView) -> void:
	add_child(view)
	var at := Vector2(seat.origin.x, seat.origin.z)
	view.watch(fighter)
	view.place(at, -at.normalized(), seat.origin.y)
	watchers.append(view)
	_watcher_places.append(at)
	_watcher_heights.append(seat.origin.y)
	_seats = _seats.filter(func(s: Transform3D) -> bool: return s.origin.distance_to(seat.origin) > WATCHER_ROOM)


## Places the figures in a share of the remaining seats.
func build() -> void:
	var taken: Array[Transform3D] = []
	for seat in _seats:
		if _rng.randf() < fill:
			taken.append(seat)
	if taken.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _figure_mesh()
	multimesh.instance_count = taken.size()
	for i in taken.size():
		var seat := taken[i]
		# A little off the seat's centre and turned, so the rows don't look stamped.
		var turn := Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3))
		var size := _rng.randf_range(0.9, 1.1)
		var offset := seat.basis.x * _rng.randf_range(-0.15, 0.15)
		multimesh.set_instance_transform(i, Transform3D(seat.basis * turn * Basis.from_scale(Vector3.ONE * size), seat.origin + offset))
		var shirt := SHIRTS[_rng.randi() % SHIRTS.size()]
		var shade := _rng.randf_range(0.85, 1.1)
		var packed := (float(_rng.randi() % 4) + _rng.randf() * 0.999) / 4.0
		multimesh.set_instance_custom_data(i, Color(shirt.r * shade, shirt.g * shade, shirt.b * shade, packed))
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	figures = MultiMeshInstance3D.new()
	figures.multimesh = multimesh
	figures.material_override = _material
	figures.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(figures)


## Raises the excitement to `strength` (0 to 1), held for `hold_frames` before it calms.
func cheer(strength: float, hold_frames := 0) -> void:
	if strength >= LOUD and excitement < LOUD:
		for view in watchers:
			view.play_role("cry")
	excitement = maxf(excitement, clampf(strength, 0.0, 1.0))
	_hold = maxi(_hold, hold_frames)


## Animation speed relative to normal, as for the fighters: 0 freezes (hit-stop).
func set_time_scale(scale: float) -> void:
	_time_scale = scale
	for view in watchers:
		view.set_time_scale(scale)


## Advances the crowd by one video frame.
func next_frame() -> void:
	for i in watchers.size():
		watchers[i].next_frame()
		watchers[i].place(_watcher_places[i], -_watcher_places[i].normalized(), _watcher_heights[i])
	if _time_scale <= 0.0:
		return
	_time += _time_scale / Rules.TICK_RATE
	if _hold > 0:
		_hold -= 1
	else:
		excitement *= 1.0 - CALM * _time_scale
	if _material != null:
		_material.set_shader_parameter("crowd_time", _time)
		_material.set_shader_parameter("excitement", excitement)


static func _angle_gap(seat: Transform3D, angle: float) -> float:
	return absf(angle_difference(atan2(seat.origin.z, seat.origin.x), angle))


## One spectator, about 1.2 m tall: legs, a shirt, arms hanging from the shoulders (marked for
## the shader to raise) and a head. Vertex colours are the shader's masks, not colours.
static func _figure_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shirt := Color(1, 0, 0)
	var legs := Color(0.5, 0, 0)
	var arm := Color(1, 1, 0)
	var skin := Color(0, 0, 0)
	LowPoly.frustum(tool, legs, Vector3.ZERO, 0.16, 0.17, 0.45, 5, 0.0)
	LowPoly.frustum(tool, shirt, Vector3.UP * 0.45, 0.2, 0.17, 0.5, 6, 0.0)
	for side: float in [-1.0, 1.0]:
		LowPoly.frustum(tool, arm, Vector3(side * 0.24, 0.5, 0), 0.055, 0.065, SHOULDER - 0.5, 4, PI * 0.25)
	LowPoly.ball(tool, skin, Vector3.UP * 1.1, 0.14, 0.26, 6, 0.0, null)
	return tool.commit()
