class_name ProceduralMotion
extends RefCounted
## The procedural animation layer (concepts_brief.md §7.4): motion of a model's root that
## fills in for clips a species doesn't have. FighterView applies transform() to a node
## between itself and the model, so it stacks with clips, knockback and the hit flash.
## - movement: a hop while walking (no walk clip); flying types hover and bob throughout
## - actions: a lunge (physical), a rear-back with squash and stretch (special), a spin
##   (status) and a backward tilt (hit), each when the species has no clip for it
## - always: leaning into movement (pitched forward by forward speed, banked by sideways
##   speed, twice as much for fliers), fliers swooping low at speed, and a squash on landing
## - sleep: slow breathing (no sleep clip)
## - faint: tipping over and sinking (no faint clip)
## Everything advances per video frame, scaled like the clips (0 in hit-stop), so renders
## are identical. Distances are shares of the fighter's height.

const ACTION_FRAMES := {"lunge": 12, "rear": 14, "spin": 16, "tilt": 10, "land": 8}
## Leaning: radians at LEAN_SPEED m/s forward or sideways, eased in by LEAN_EASE per frame.
const LEAN_PITCH := 0.18
const LEAN_ROLL := 0.12
const LEAN_SPEED := 5.0
const LEAN_EASE := 0.2
const FLIER_LEAN := 2.0
## Fliers drop by up to this share of their hover height when moving faster than walking:
## from SWOOP_FROM m/s, fully at SWOOP_FULL (a melee dash dives).
const SWOOP_DEPTH := 0.7
const SWOOP_FROM := 4.0
const SWOOP_FULL := 10.0
const LAND_SQUASH := 0.15
const LUNGE_DISTANCE := 0.35
const LUNGE_PITCH := 0.25
const REAR_DISTANCE := 0.15
const SQUASH := 0.12
const TILT_ANGLE := 0.35
const HOP_HEIGHT := 0.12
const HOP_SPEED := 0.5
const HOVER_HEIGHT := 0.35
const HOVER_BOB := 0.05
const HOVER_SPEED := 0.08
const BREATH := 0.03
const BREATH_SPEED := 0.12
const FAINT_FRAMES := 20
const FAINT_ANGLE := deg_to_rad(85.0)
const FAINT_SINK := 0.15

var height := 1.0
var hovers := false
var moving := false
var asleep := false
## Set each frame by the view: facing and the last tick's movement, on the floor.
var facing := Vector2.UP
var velocity := Vector2.ZERO
## Head turn toward the foe (radians about up): the view sets the target, eased here so it
## pauses in hit-stop like everything else.
var head_target := 0.0
var head_yaw := 0.0
var _lean := Vector2.ZERO
var _swoop := 0.0
var _action := ""
var _action_age := 0.0
var _fainting := false
var _faint_age := 0.0
## Running phase for hops, hover bobbing and breathing, in frames.
var _phase := 0.0


func _init(fighter_height: float, hovering: bool) -> void:
	height = fighter_height
	hovers = hovering


## Starts a one-off action ("lunge", "rear", "spin" or "tilt"), replacing any running one.
func start(action: String) -> void:
	if ACTION_FRAMES.has(action) and not _fainting:
		_action = action
		_action_age = 0.0


func faint() -> void:
	_fainting = true
	_action = ""


## Advances by one video frame at `time_scale` (0 freezes, below 1 is slow motion).
func next_frame(time_scale := 1.0) -> void:
	_phase += time_scale
	var forward := velocity.dot(facing)
	var sideways := velocity.dot(Vector2(-facing.y, facing.x))
	var strength := FLIER_LEAN if hovers else 1.0
	var target := Vector2(-LEAN_PITCH * forward, -LEAN_ROLL * sideways) * strength / LEAN_SPEED
	var ease := minf(1.0, LEAN_EASE * time_scale)
	_lean = _lean.lerp(target.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)), ease)
	_swoop = lerpf(_swoop, clampf(inverse_lerp(SWOOP_FROM, SWOOP_FULL, velocity.length()), 0.0, 1.0), ease)
	head_yaw = lerpf(head_yaw, 0.0 if _fainting else head_target, ease)
	if not _action.is_empty():
		_action_age += time_scale
		if _action_age >= ACTION_FRAMES[_action]:
			_action = ""
	if _fainting:
		_faint_age = minf(_faint_age + time_scale, FAINT_FRAMES)


## The root offset for the current frame, in the fighter's own space (-Z faces the foe).
func transform() -> Transform3D:
	var offset := Vector3.ZERO
	var rotation := Vector3.ZERO
	var scale := Vector3.ONE
	rotation.x += _lean.x
	rotation.z += _lean.y
	if hovers:
		offset.y += height * (HOVER_HEIGHT * (1.0 - SWOOP_DEPTH * _swoop) + HOVER_BOB * sin(_phase * HOVER_SPEED))
	elif moving:
		offset.y += height * HOP_HEIGHT * absf(sin(_phase * HOP_SPEED))
	if asleep:
		var breath := BREATH * sin(_phase * BREATH_SPEED)
		scale *= Vector3(1.0 - breath * 0.5, 1.0 + breath, 1.0 - breath * 0.5)
	if not _action.is_empty():
		var t: float = _action_age / ACTION_FRAMES[_action]
		match _action:
			"lunge":
				offset.z -= height * LUNGE_DISTANCE * sin(PI * t)
				rotation.x -= LUNGE_PITCH * sin(PI * t)
			"rear":
				var swing := sin(TAU * t)
				offset.z += height * REAR_DISTANCE * swing
				scale *= Vector3(1.0 - SQUASH * 0.5 * swing, 1.0 + SQUASH * swing, 1.0 - SQUASH * 0.5 * swing)
			"spin":
				rotation.y += TAU * smoothstep(0.0, 1.0, t)
			"tilt":
				rotation.x += TILT_ANGLE * sin(PI * t)
			"land":
				var squash := LAND_SQUASH * sin(PI * t)
				scale *= Vector3(1.0 + squash * 0.5, 1.0 - squash, 1.0 + squash * 0.5)
	if _fainting:
		var f := smoothstep(0.0, 1.0, _faint_age / FAINT_FRAMES)
		rotation.z += FAINT_ANGLE * f
		offset.y = lerpf(offset.y, -height * FAINT_SINK, f)
	# Scale after rotating, so squash and stretch follow the model's own axes.
	return Transform3D(Basis.from_euler(rotation) * Basis.from_scale(scale), offset)
