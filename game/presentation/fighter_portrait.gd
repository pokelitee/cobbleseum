class_name FighterPortrait
extends SubViewport
## A fighter's HUD portrait (concepts_brief.md §12.5): a second copy of its model, alone in a
## world of its own, posed in its idle animation's first frame and drawn once from a
## three-quarter angle on a transparent background. Rendered at load time from the cached
## model, so no image is stored anywhere.
##
## Framing is a head-and-shoulders bust, like a character select's: an orthographic square on
## the posed head (the head bone's cuboids and those of the bones under it), centred on it and
## kept within the silhouette, HEAD_SHARE times the head's height and at least HEAD_WIDTH_SHARE
## times its width. The head is measured without the HEAD_TRIM share of its points at each end
## of each axis, so whiskers, horns and crests don't size it, and the square's top sits
## HEAD_TOP_ROOM of that height above it, or at the head's very top if that is lower. Small
## round species, whose head is most of them, get the whole body: whenever the square would
## take WHOLE_SHARE of the body's larger extent or more. So do species without a head bone,
## which are mostly round heads already (Voltorb, Gengar).

const SIZE := 256
const VIEW_DIRECTION := Vector3(0.5, 0.15, -1.0)
const HEAD_SHARE := 2.4
const HEAD_WIDTH_SHARE := 1.4
const HEAD_TOP_ROOM := 0.7
const HEAD_TRIM := 0.1
const WHOLE_SHARE := 0.85
## Room around the framed part, as a share of the square.
const MARGIN := 0.06

var _view: FighterView


## A portrait of the converted species scene at `path` (wearing `skin`, if given; see
## FighterView.from_model()), or null if the model can't be loaded. Add it to the tree for it to
## draw; its texture is valid from then on.
static func create(path: String, scale: float, model_height: float, skin := "") -> FighterPortrait:
	var view := FighterView.from_model(path, scale, model_height, skin)
	if view == null:
		return null
	var portrait := FighterPortrait.new()
	portrait.size = Vector2i(SIZE, SIZE)
	portrait.own_world_3d = true
	portrait.transparent_bg = true
	portrait.msaa_3d = Viewport.MSAA_4X
	portrait.render_target_update_mode = SubViewport.UPDATE_ONCE
	# The copy holds still: no blinks, fidgets or animation after the first pose.
	view.set_process(false)
	portrait._view = view
	portrait.add_child(view)
	portrait._light()
	return portrait


## Frames the shot once the copy is in the tree, where its animation can pose it.
func _ready() -> void:
	_view.pose_still()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var shot := frame(_view.posed_points(), _view.head_points(), VIEW_DIRECTION)
	camera.size = shot.size
	camera.transform = shot.transform
	camera.current = true
	add_child(camera)


## The orthographic shot of `points`, the posed body, seen along -`direction`, framed on
## `head`, the posed head's points (empty without one): {"transform", "size"}.
static func frame(points: PackedVector3Array, head: PackedVector3Array, direction: Vector3) -> Dictionary:
	var back := direction.normalized()
	var basis := Basis.looking_at(-back, Vector3.UP)
	var body := _bounds(points, basis) if not points.is_empty() else AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
	var whole := maxf(body.size.x, body.size.y)
	var side := whole
	var centre_x := body.get_center().x
	var top := body.end.y
	if not head.is_empty():
		var face := _bounds(head, basis, HEAD_TRIM)
		side = maxf(face.size.y * HEAD_SHARE, face.size.x * HEAD_WIDTH_SHARE)
		centre_x = face.get_center().x
		top = minf(_bounds(head, basis).end.y, face.end.y + face.size.y * HEAD_TOP_ROOM)
	if side >= whole * WHOLE_SHARE:
		side = whole
		centre_x = body.get_center().x
		top = body.get_center().y + whole * 0.5
	else:
		# Kept within the silhouette, so the square never shows empty space beside the body or
		# under its feet (a head low on the body, as in a grazing pose).
		centre_x = clampf(centre_x, body.position.x + side * 0.5, body.end.x - side * 0.5) if side < body.size.x 			else body.get_center().x
		top = maxf(top, body.position.y + side) if side < body.size.y else body.end.y
	var square := side * (1.0 + 2.0 * MARGIN)
	var centre_y := top + side * MARGIN - square * 0.5
	var eye := basis.x * centre_x + basis.y * centre_y + back * (body.end.z + 1.0)
	return {"transform": Transform3D(basis, eye), "size": square}


## The bounds of `points` along `basis`'s axes (x right, y up, z back toward the camera),
## leaving out the `trim` share of points at each end of each axis.
static func _bounds(points: PackedVector3Array, basis: Basis, trim := 0.0) -> AABB:
	var axes: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for point in points:
		for axis in 3:
			axes[axis].append(point.dot(basis[axis]))
	var low := Vector3.ZERO
	var high := Vector3.ZERO
	var skip := mini(floori(points.size() * trim), (points.size() - 1) / 2)
	for axis in 3:
		axes[axis].sort()
		low[axis] = axes[axis][skip]
		high[axis] = axes[axis][-1 - skip]
	return AABB(low, high - low)


func _light() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(30), 0)
	key.light_energy = 1.1
	add_child(key)
