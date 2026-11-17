class_name FighterPortrait
extends SubViewport
## A fighter's HUD portrait (concepts_brief.md §12.5): a second copy of its model, alone in a
## world of its own, posed in its idle animation's first frame and drawn once from a
## three-quarter angle on a transparent background. Rendered at load time from the cached
## model, so no image is stored anywhere.
##
## Framing comes from the posed silhouette, since head bones sit anywhere from the top of a
## neck to the middle of a round body: an orthographic square at the top of the silhouette,
## BUST_SHARE of its height for tall bodies (a bust), as wide as the body for stocky ones, as
## tall as the body for long ones, and the whole body when that is no bigger than WHOLE_BODY
## metres. Horizontally it centres on the head bone, when there is one, kept within the
## silhouette.

const SIZE := 256
const VIEW_DIRECTION := Vector3(0.5, 0.15, -1.0)
const BUST_SHARE := 0.6
const WHOLE_BODY := 0.9
## Room around the framed part, as a share of the square.
const MARGIN := 0.06

var _view: FighterView


## A portrait of the converted species scene at `path`, or null if the model can't be loaded.
## Add it to the tree for it to draw; its texture is valid from then on.
static func create(path: String, scale: float, model_height: float) -> FighterPortrait:
	var view := FighterView.from_model(path, scale, model_height)
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
	var shot := frame(_view.posed_points(), _view.head_position(), VIEW_DIRECTION)
	camera.size = shot.size
	camera.transform = shot.transform
	camera.current = true
	add_child(camera)


## The orthographic shot of `points` seen along -`direction`: {"transform", "size"}.
static func frame(points: PackedVector3Array, head: Variant, direction: Vector3) -> Dictionary:
	var back := direction.normalized()
	var basis := Basis.looking_at(-back, Vector3.UP)
	var right := basis.x
	var up := basis.y
	var low := Vector3(INF, INF, INF)
	var high := -low
	for point in points:
		var p := Vector3(point.dot(right), point.dot(up), point.dot(back))
		low = low.min(p)
		high = high.max(p)
	if points.is_empty():
		low = Vector3(-0.5, 0.0, -0.5)
		high = Vector3(0.5, 1.0, 0.5)
	var width := high.x - low.x
	var height := high.y - low.y
	var side := maxf(height * BUST_SHARE, minf(width, height))
	if maxf(width, height) <= WHOLE_BODY:
		side = maxf(width, height)
	var centre_x := (low.x + high.x) * 0.5
	if head != null and side < width:
		centre_x = clampf((head as Vector3).dot(right), low.x + side * 0.5, high.x - side * 0.5)
	var square := side * (1.0 + 2.0 * MARGIN)
	var centre := Vector2(centre_x, high.y + side * MARGIN - square * 0.5)
	var eye := right * centre.x + up * centre.y + back * (high.z + 1.0)
	return {"transform": Transform3D(basis, eye), "size": square}


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
