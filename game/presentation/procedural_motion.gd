class_name ProceduralMotion
extends RefCounted
## The procedural animation layer (concepts_brief.md §7.4): motion of a model's root that
## fills in for animations a species doesn't have. FighterView applies transform() to a node
## between itself and the model, so it stacks with animations, knockback and the hit flash.
## - movement: a hop while walking (no walk animation); flying types hover and bob throughout
## - actions: a lunge (physical), a rear-back with squash and stretch (special), a spin
##   (status) and a backward tilt (hit), each when the species has no animation for it
## - always: leaning into movement (pitched forward by forward speed, banked by sideways
##   speed, twice as much for fliers), fliers swooping low at speed, and a squash on landing
## - sleep: slow breathing (no sleep animation)
## - idle: subtle breathing and a slight bob when the species' idle holds one pose (about 340
##   do in Cobblemon itself) or it has none
## - serpents (BodyWave): a wave down the body instead of hopping, gentle at rest, stronger
##   and faster when moving; on a knockout they drop to the ground rather than tipping over
## - faint: tipping over onto its side, resting on the ground (no faint animation); with a
##   faint animation, only dropping out of a hover and lifting what the animation sinks
## Everything advances per video frame, scaled like the animations (0 in hit-stop), so renders
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
## Breathing at rest for a still idle: gentler and slower than asleep (a cycle of about 3 s),
## with a slight rise and fall of the whole body.
const IDLE_BREATH := 0.015
const IDLE_BREATH_SPEED := 0.07
const IDLE_BOB := 0.008
## Where in a fitted action its strike falls, as a share of it: the lunge's furthest reach and
## the rear-back's spring forward. A fitted action's length stays within FIT_RANGE times its own.
const STRIKE_SHARE := {"lunge": 0.5, "rear": 0.75}
const FIT_RANGE := Vector2(0.6, 2.5)
const FAINT_FRAMES := 20
const FAINT_ANGLE := deg_to_rad(85.0)
## How far a fainted model settles into the ground, as a share of its height, so it doesn't
## float over the arena's faceted ground.
const FAINT_SINK := 0.03
## The share of the fainted model's silhouette allowed below the ground: outstretched fins,
## wings and tails, so the body lies on the ground rather than balancing on a wingtip.
const FAINT_REST_SHARE := 0.05
## Serpents' body wave: its strength at rest (1 at LEAN_SPEED m/s), and how fast it travels
## (radians per frame) at rest and at LEAN_SPEED.
const WAVE_REST := 0.35
const WAVE_REST_SPEED := 0.06
const WAVE_MOVING_SPEED := 0.22

var height := 1.0
var hovers := false
var moving := false
var asleep := false
## Breathes at rest: the species' idle holds still.
var breathes := false
## A serpent with a BodyWave: it slithers rather than hops, and doesn't tip over when it faints.
var slithers := false
## The BodyWave's phase and strength.
var wave_phase := 0.0
var wave_strength := 0.0
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
var _action_frames := 1.0
var _fainting := false
var _faint_age := 0.0
## The fainting model's silhouette seen from the front (x, y in the model's space), so it can
## be lifted to rest on the ground as it tips over rather than through it.
var _faint_outline := PackedVector2Array()
var _lift_angle := NAN
var _lift := 0.0
## What the standing pose already dips below its feet, eased out as it tips over.
var _standing_lift := 0.0
## False when the species faints with an animation of its own: the model then only drops to
## the ground, raised by `ground_lift`.
var _tips := true
## Set by the view while a faint animation plays: how far to raise the model so the animation
## doesn't sink it into the ground.
var ground_lift := 0.0
## Running phase for hops, hover bobbing and breathing, in frames.
var _phase := 0.0


func _init(fighter_height: float, hovering: bool) -> void:
	height = fighter_height
	hovers = hovering


## Starts a one-off action ("lunge", "rear", "spin" or "tilt"), replacing any running one.
## `strike_frames`, when given, fits a lunge or rear-back so its strike lands that many frames on.
func start(action: String, strike_frames := 0.0) -> void:
	if ACTION_FRAMES.has(action) and not _fainting:
		_action = action
		_action_age = 0.0
		_action_frames = ACTION_FRAMES[action]
		if strike_frames > 0.0 and STRIKE_SHARE.has(action):
			_action_frames = clampf(strike_frames / STRIKE_SHARE[action], _action_frames * FIT_RANGE.x, _action_frames * FIT_RANGE.y)


## Tips over. `outline` is the model's posed silhouette seen from the front (any points in the
## model's x-y plane); without one the model tips over about its feet.
func faint(outline := PackedVector2Array()) -> void:
	_fainting = true
	_action = ""
	_faint_outline = outline
	_lift_angle = NAN
	_standing_lift = _ground_lift(0.0)
	_tips = true


## Faints with the species' own faint animation: drops out of a hover onto the ground, raised
## by `ground_lift`, without tipping over.
func fall() -> void:
	_fainting = true
	_action = ""
	_tips = false


## Stands up again after a faint, for the instant replay.
func revive() -> void:
	_fainting = false
	_faint_age = 0.0
	ground_lift = 0.0


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
		if _action_age >= _action_frames:
			_action = ""
	if _fainting:
		_faint_age = minf(_faint_age + time_scale, FAINT_FRAMES)
	if slithers:
		var pace := clampf(velocity.length() / LEAN_SPEED, 0.0, 1.0)
		wave_strength = lerpf(wave_strength, 0.0 if _fainting else lerpf(WAVE_REST, 1.0, pace), ease)
		wave_phase += time_scale * lerpf(WAVE_REST_SPEED, WAVE_MOVING_SPEED, pace)


## The root offset for the current frame, in the fighter's own space (-Z faces the foe).
func transform() -> Transform3D:
	var offset := Vector3.ZERO
	var rotation := Vector3.ZERO
	var scale := Vector3.ONE
	rotation.x += _lean.x
	rotation.z += _lean.y
	if hovers:
		offset.y += height * (HOVER_HEIGHT * (1.0 - SWOOP_DEPTH * _swoop) + HOVER_BOB * sin(_phase * HOVER_SPEED))
	elif moving and not slithers:
		offset.y += height * HOP_HEIGHT * absf(sin(_phase * HOP_SPEED))
	if asleep:
		var breath := BREATH * sin(_phase * BREATH_SPEED)
		scale *= Vector3(1.0 - breath * 0.5, 1.0 + breath, 1.0 - breath * 0.5)
	elif breathes and not _fainting:
		var breath := sin(_phase * IDLE_BREATH_SPEED)
		scale *= Vector3(1.0 - IDLE_BREATH * breath * 0.5, 1.0 + IDLE_BREATH * breath, 1.0 - IDLE_BREATH * breath * 0.5)
		if not hovers:
			offset.y += height * IDLE_BOB * (0.5 + 0.5 * breath)
	if not _action.is_empty():
		var t: float = _action_age / _action_frames
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
		# A serpent tipped onto its side would stand its coils on end.
		if _tips and not slithers:
			rotation.z += FAINT_ANGLE * f
			# Fully lifted at every angle, so the body never passes through the ground on the way down.
			offset.y = lerpf(offset.y, -height * FAINT_SINK, f) + _ground_lift(FAINT_ANGLE * f) - _standing_lift * (1.0 - f)
		else:
			offset.y = lerpf(offset.y, 0.0, f) + ground_lift
	# Scale after rotating, so squash and stretch follow the model's own axes.
	return Transform3D(Basis.from_euler(rotation) * Basis.from_scale(scale), offset)


## How far to raise the faint outline, rolled by `angle` about the feet, so all but
## FAINT_REST_SHARE of it is above the ground.
func _ground_lift(angle: float) -> float:
	if _faint_outline.is_empty():
		return 0.0
	if angle == _lift_angle:
		return _lift
	var heights := PackedFloat32Array()
	heights.resize(_faint_outline.size())
	for i in _faint_outline.size():
		heights[i] = _faint_outline[i].x * sin(angle) + _faint_outline[i].y * cos(angle)
	heights.sort()
	_lift_angle = angle
	_lift = maxf(0.0, -heights[int(heights.size() * FAINT_REST_SHARE)])
	return _lift
