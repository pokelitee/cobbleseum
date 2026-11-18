class_name TrainerView
extends Node3D
## A side's trainer (concepts_brief.md §12.7, M15): the games' trainer sprite, billboarded upright
## in the side's trainer's box. It throws a ball to send a Pokémon out, calls one back with a red
## beam, and reacts: a hop at a big hit by its own side, a droop when one of its team is knocked
## out, hops of joy when its side wins. Presentation only; the sprite comes from the git-ignored
## cache (sources.json's trainer_<id> entries), and a trainer missing there isn't drawn.

const SOURCES_DIR := "res://cache/sources"
## Trainers a team battle's sides get from the seed when the spec names none: the games'
## generic trainer classes.
const GENERIC: Array[String] = ["acetrainer", "acetrainerf", "youngster", "lass", "veteran", "veteranf", "hiker", "swimmer"]
## Every trainer sources.json fetches: the generic classes and characters from the games and the
## anime, for staging their battles.
const ALL: Array[String] = ["acetrainer", "acetrainerf", "ash", "blue", "brock", "cynthia", "hiker", "hop", "iris", "lance",
	"lass", "leon", "marnie", "misty", "n", "red", "serena", "steven", "swimmer", "veteran", "veteranf", "youngster"]
## The sprite's pixels to metres: a 70-pixel figure stands about 1.75 m.
const PIXEL_SIZE := 0.025
## A thrown ball's flight in frames and its arc's height; a recall beam's life.
const THROW_FRAMES := 14
const ARC_HEIGHT := 2.2
const BEAM_FRAMES := 10
const HOP_FRAMES := 12
const HOP_HEIGHT := 0.25
const DROOP_FRAMES := 45
const BALL_RADIUS := 0.12

var _sprite: Sprite3D
var _home := Vector3.ZERO
var _frame := 0
var _hop := -1
var _hops_left := 0
var _droop := 0
## Balls in flight: {"node", "from", "to", "age", "landed": Callable}.
var _balls: Array[Dictionary] = []
## Recall beams fading: {"node", "age"}.
var _beams: Array[Dictionary] = []


## The trainer sprite `id`, or null when the cache doesn't have it.
static func create(id: String) -> TrainerView:
	var path := sprite_path(id)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	var view := TrainerView.new()
	var sprite := Sprite3D.new()
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.pixel_size = PIXEL_SIZE
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.centered = false
	sprite.offset = Vector2(-image.get_width() * 0.5, 0)
	view._sprite = sprite
	view.add_child(sprite)
	return view


static func sprite_path(id: String) -> String:
	return SOURCES_DIR.path_join("trainer_%s/1/%s.png" % [id, id])


## Stands the trainer at `spot`, on the ground.
func stand_at(spot: Vector3) -> void:
	_home = spot
	position = spot


## Throws a ball from the trainer to `target` (a point on the ground); `landed` runs as it lands.
func throw_to(target: Vector3, landed: Callable) -> void:
	hop()
	var ball := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = BALL_RADIUS
	mesh.height = BALL_RADIUS * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	ball.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_texture = _ball_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ball.material_override = material
	get_parent().add_child(ball)
	var from := _home + Vector3.UP * 1.3
	ball.global_position = from
	_balls.append({"node": ball, "from": from, "to": target + Vector3.UP * BALL_RADIUS, "age": 0, "landed": landed})


## A red beam from the trainer to `target` (a fighter's chest), fading out.
func recall_from(target: Vector3) -> void:
	var beam := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var from := _home + Vector3.UP * 1.3
	mesh.size = Vector3(0.08, 0.08, maxf(from.distance_to(target), 0.1))
	beam.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Brighter than its colour, so it blooms.
	material.albedo_color = Color(2.2, 0.35, 0.3, 1.0)
	beam.material_override = material
	get_parent().add_child(beam)
	beam.global_position = (from + target) * 0.5
	if not from.is_equal_approx(target):
		beam.look_at(target, Vector3.UP if absf((target - from).normalized().y) < 0.99 else Vector3.RIGHT)
	_beams.append({"node": beam, "age": 0})


## A quick hop, as at a big hit by its side.
func hop() -> void:
	if _hop < 0:
		_hop = 0


## Hops of joy until the end.
func celebrate() -> void:
	_hops_left = 1 << 20
	hop()


## Slumps for a while: one of its team was knocked out (`lasting` for the last one).
func droop(lasting := false) -> void:
	_droop = 1 << 20 if lasting else DROOP_FRAMES
	_hops_left = 0


func next_frame() -> void:
	_frame += 1
	var lift := 0.0
	if _hop >= 0:
		var t := float(_hop) / HOP_FRAMES
		lift = sin(t * PI) * HOP_HEIGHT
		_hop += 1
		if _hop > HOP_FRAMES:
			_hop = -1
			if _hops_left > 0:
				_hops_left -= 1
				_hop = 0
	var breath := 1.0 + sin(_frame * 0.08) * 0.012
	var slump := 0.92 if _droop > 0 else 1.0
	if _droop > 0:
		_droop -= 1
	position = _home + Vector3.UP * lift
	_sprite.scale = Vector3(1.0 / sqrt(breath * slump), breath * slump, 1.0)
	_sprite.modulate = Color(0.75, 0.75, 0.8) if slump < 1.0 else Color.WHITE
	for ball in _balls.duplicate():
		ball.age += 1
		var t := float(ball.age) / THROW_FRAMES
		var node: MeshInstance3D = ball.node
		node.global_position = (ball.from as Vector3).lerp(ball.to, t) + Vector3.UP * sin(t * PI) * ARC_HEIGHT
		node.rotation.x += 0.5
		if ball.age >= THROW_FRAMES:
			node.queue_free()
			_balls.erase(ball)
			(ball.landed as Callable).call()
	for beam in _beams.duplicate():
		beam.age += 1
		var material := (beam.node as MeshInstance3D).material_override as StandardMaterial3D
		material.albedo_color.a = 1.0 - float(beam.age) / BEAM_FRAMES
		if beam.age >= BEAM_FRAMES:
			(beam.node as Node).queue_free()
			_beams.erase(beam)


## Whether a ball is still in the air (a send-out waiting on it).
func throwing() -> bool:
	return not _balls.is_empty()


## A ball's two halves: red over white, with a dark band (the sphere's UVs wrap around it).
static func _ball_texture() -> ImageTexture:
	var image := Image.create(4, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		var colour := Color(0.9, 0.15, 0.15) if y < 3 else (Color(0.1, 0.1, 0.12) if y < 5 else Color(0.95, 0.95, 0.95))
		for x in 4:
			image.set_pixel(x, y, colour)
	return ImageTexture.create_from_image(image)
