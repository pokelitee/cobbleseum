class_name ModelPreview
extends SubViewportContainer
## A species' model on a slow turntable for the setup screen: a FighterView idling alone in a
## world of its own, lit like the HUD's portraits (FighterPortrait) and framed to its posed
## size, so long and tall bodies both fit.

const SPIN_SPEED := 0.5
## How far the camera looks down on the model, in radians.
const PITCH := 0.25
const FOV := 30.0
## Room around the model, as a share of its size.
const MARGIN := 1.05

var _viewport: SubViewport
var _turntable: Node3D
var _camera: Camera3D
var _view: FighterView
## Frames until the newly loaded model is framed, once its animation has posed it.
var _frame_in := -1
var _placeholder: Label


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	_turntable = Node3D.new()
	_viewport.add_child(_turntable)
	_camera = Camera3D.new()
	_camera.fov = FOV
	_viewport.add_child(_camera)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(30), 0)
	key.light_energy = 1.1
	_viewport.add_child(key)
	_placeholder = MenuTheme.title("", 30, MenuTheme.MUTED)
	_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_placeholder)


## Shows the model `look` (Appearance.resolve()) of roster `entry`, or a note when it can't be
## loaded.
func show_model(entry: Dictionary, look: Dictionary) -> void:
	if _view != null:
		_view.queue_free()
		_view = null
	var models := BattleView.MODELS_DIR
	_view = FighterView.from_model(models.path_join(look.model), entry.scale, entry.height, BattleView.skin_path(look))
	_placeholder.text = "" if _view != null else "No model in the cache;\nrun tools/assets.gd"
	if _view == null:
		return
	_view.set_hovering(_view.floats())
	_turntable.add_child(_view)
	_turntable.rotation.y = -0.6
	_frame_in = 2


func _process(delta: float) -> void:
	if _view == null:
		return
	_view.next_frame()
	_turntable.rotation.y += SPIN_SPEED * delta
	if _frame_in > 0:
		_frame_in -= 1
		if _frame_in == 0:
			_frame()


## Points the camera at the posed model so it fits whichever way the turntable faces it.
func _frame() -> void:
	var low := Vector3(INF, INF, INF)
	var high := -low
	for point in _view.posed_points():
		low = low.min(point)
		high = high.max(point)
	if low.x == INF:
		low = Vector3(-0.5, 0, -0.5)
		high = Vector3(0.5, 1, 0.5)
	var reach := Vector2(maxf(absf(low.x), absf(high.x)), maxf(absf(low.z), absf(high.z))).length()
	var height := high.y - low.y
	var aspect := size.x / maxf(size.y, 1.0)
	var half := maxf(height * 0.5, reach / maxf(aspect, 0.01)) * MARGIN
	# From the turntable's axis; the near side of a long body comes closer by up to `reach`.
	var distance := half / tan(deg_to_rad(FOV * 0.5)) + reach * 0.5
	var centre := Vector3(0, (low.y + high.y) * 0.5, 0)
	_camera.position = centre + Vector3(0, sin(PITCH), cos(PITCH)) * distance
	_camera.look_at(centre, Vector3.UP)
