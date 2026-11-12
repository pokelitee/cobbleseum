class_name CameraRig
extends RefCounted
## Turns the director's shots into moving camera placements (concepts_brief.md §12.3).
## - Every shot stays on the same side of the line between the fighters (the 180-degree
##   rule), so cuts never swap which fighter is on the left.
## - Distances scale with the fighters' rendered height, so framing holds from small to
##   large Pokémon.
## - Each shot type has its own move (arc, push-in, zoom, crane), timed by how far through
##   the shot it is, plus a small handheld wobble.
## - The camera is pushed out of any fighter it would end up inside.
## - Portrait frames sit further back and higher so both fighters fit the tall frame.
## Every value comes from the battle, the shot and a seeded stream, so re-renders match.

const AXIS_FOLLOW := 0.02
const SMOOTHING := 0.15
## How fast the camera blends when tracking whips into an impact instead of cutting.
const WHIP_SMOOTHING := 0.45
## Shot distances below are tuned for fighters of this height.
const REFERENCE_HEIGHT := 1.5
## The camera keeps at least this many fighter heights away from each fighter's centre.
const CLEARANCE := 0.75
## Wide shots arc around the fighters at this rate, in radians per second.
const WIDE_ARC_SPEED := 0.06
## Knockout sweep: half-width of the arc in radians, and its speed in radians per second.
const KNOCKOUT_ARC := 0.6
const KNOCKOUT_SPEED := 0.25
## Handheld wobble amplitude per shot, in metres for a reference-height fighter.
const WOBBLE := {
	Director.Shot.WIDE: 0.04, Director.Shot.OVER_SHOULDER: 0.07, Director.Shot.CLOSE_UP: 0.05,
	Director.Shot.TRACKING: 0.08, Director.Shot.IMPACT: 0.12, Director.Shot.KNOCKOUT: 0.05, Director.Shot.VICTORY: 0.03,
}
## Wobble frequencies in hertz; slow enough to read as a held camera, not shake.
const WOBBLE_FREQUENCIES: Array[float] = [0.31, 0.53, 0.89]

var portrait := false
var _heights: Array = [1.0, 1.0]
var _wobble_phases: Array[Vector3] = []
var _axis := Vector2(0, 1)
var _position := Vector3.ZERO
var _target := Vector3.ZERO
var _fov := 50.0
## The arena's camera limit: the eye never goes further than this from the centre, so it
## can't end up inside the stands or hills (Arena.camera_limit).
var limit := INF
var _last_shot := -1


## `random` seeds the handheld wobble; give it its own stream so it can't shift other choices.
func _init(is_portrait: bool, fighter_heights: Array, random: SimRandom) -> void:
	portrait = is_portrait
	_heights = fighter_heights
	for i in WOBBLE_FREQUENCIES.size():
		_wobble_phases.append(Vector3(random.next_float(), random.next_float(), random.next_float()) * TAU)


## Updates the camera for one frame. `shot_seconds` is presentation time since the shot
## began; `progress` runs 0 -> 1 across the shot's ticks; `seconds` is total presentation
## time (drives the wobble).
func apply(camera: Camera3D, segment: Dictionary, battle: Battle, shot_seconds: float, progress: float, seconds: float, new_shot: bool) -> void:
	var whip: bool = new_shot and _last_shot == Director.Shot.TRACKING and segment.shot == Director.Shot.IMPACT
	var cut := new_shot and not whip
	_last_shot = segment.shot
	var pose := pose_for(segment, battle, shot_seconds, progress, cut)
	# Shots are framed for the floor; lift them with the fighters' ground.
	var lift := Vector3.UP * (battle.fighters[0].ground + battle.fighters[1].ground) * 0.5
	pose.position += lift
	pose.target += lift
	var weight := 1.0 if cut else (WHIP_SMOOTHING if whip else SMOOTHING)
	_position = pose.position if cut else _position.lerp(pose.position, weight)
	_target = pose.target if cut else _target.lerp(pose.target, weight)
	_fov = pose.fov if cut else lerpf(_fov, pose.fov, weight)
	var k := _scale()
	var wobble := _wobble(seconds) * float(WOBBLE.get(segment.shot, 0.05)) * k
	camera.fov = _fov
	var eye := keep_inside(_position + wobble, limit)
	var look := _target + wobble * 0.5
	if eye.is_equal_approx(look):
		camera.position = eye
	else:
		camera.look_at_from_position(eye, look, Vector3.UP)


## `eye` pulled in toward the centre, if needed, to at most `radius` from it on the floor.
static func keep_inside(eye: Vector3, radius: float) -> Vector3:
	var flat := Vector2(eye.x, eye.z)
	if flat.length() <= radius:
		return eye
	flat = flat.normalized() * radius
	return Vector3(flat.x, eye.y, flat.y)


func pose_for(segment: Dictionary, battle: Battle, shot_seconds: float, progress: float, cut: bool) -> Dictionary:
	var side: int = segment.side
	var a := battle.fighters[0].position
	var b := battle.fighters[1].position
	if a.distance_to(b) > 0.01:
		_axis = (b - a).normalized() if cut else _axis.slerp((b - a).normalized(), AXIS_FOLLOW).normalized()
	# The camera's side of the line of action; keeps fighter A on screen-left.
	var across := Vector2(-_axis.y, _axis.x)
	var me := battle.fighters[side].position
	var other := battle.fighters[1 - side].position
	var toward := (other - me).normalized() if me.distance_to(other) > 0.01 else _axis * (1 if side == 0 else -1)
	var my_height: float = _heights[side]
	var k := _scale()
	var back := (1.3 if portrait else 1.0) * k
	var lift := (0.6 if portrait else 0.0) * k
	var widen := 8.0 if portrait else 0.0
	var eased := ease(clampf(progress, 0.0, 1.0), -1.8)  # ease in and out
	var pose: Dictionary
	match segment.shot:
		Director.Shot.OVER_SHOULDER:
			# Slow push-in toward the opponent.
			var push := lerpf(1.15, 0.85, eased)
			pose = _make(me - toward * 2.4 * back * push + across * 2.0 * back, 1.6 * k + lift, other, _heights[1 - side] * 0.5, 50 + widen)
		Director.Shot.CLOSE_UP:
			# Push in during the wind-up, arriving as the move releases.
			var push := lerpf(1.35, 0.8, eased)
			pose = _make(me + (toward * 2.4 + across * 2.0) * back * push, 0.9 * k + lift, me, my_height * 0.55, lerpf(44, 36, eased) + widen)
		Director.Shot.TRACKING:
			var projectile := _projectile_of(battle, side)
			var target: Vector2 = projectile if projectile != Vector2.INF else other
			pose = _make((a + b) * 0.5 + across * 5.0 * back, 1.6 * k + lift, target, 1.0, 50 + widen)
		Director.Shot.IMPACT:
			# Snap in tight on contact, then settle back out.
			var settle := 1.0 - exp(-shot_seconds * 4.0)
			pose = _make(me + (across * 2.6 - toward * 0.8) * back * lerpf(0.8, 1.0, settle), 0.8 * k + lift, me, my_height * 0.45, lerpf(30, 40, settle) + widen)
		Director.Shot.KNOCKOUT:
			# Sweep an arc on the far side of the fallen fighter and crane up as it goes down.
			var away := -toward
			var angle := atan2(away.y, away.x) + clampf(-KNOCKOUT_ARC + shot_seconds * KNOCKOUT_SPEED, -KNOCKOUT_ARC, KNOCKOUT_ARC)
			var orbit := Vector2(cos(angle), sin(angle)) * 3.2 * back
			pose = _make(me + orbit, (1.2 + 1.2 * eased) * k + lift, me, my_height * 0.3, 45 + widen)
		Director.Shot.VICTORY:
			# In front of the winner, slowly pushing in, a little to one side and below its eyes.
			var facing: Vector2 = battle.fighters[side].facing
			var front := facing.normalized() if facing.length() > 0.01 else toward
			var side_step := Vector2(-front.y, front.x)
			var push := lerpf(1.25, 1.0, eased)
			var distance := (1.6 + my_height * 1.4) * push * (1.15 if portrait else 1.0)
			pose = _make(me + (front + side_step * 0.35) * distance, my_height * 0.7 + lift, me, my_height * 0.55, 40 + widen)
		_:
			# Slow arc around the fighters, alternating direction from shot to shot.
			var middle := (a + b) * 0.5
			var arc_direction := 1.0 if (int(segment.start) / 7) % 2 == 0 else -1.0
			var angle := deg_to_rad(80.0) + arc_direction * WIDE_ARC_SPEED * shot_seconds
			var direction := (-_axis * cos(angle) + across * sin(angle)).normalized()
			var distance := (3.4 if not portrait else 4.0) * k + a.distance_to(b) * 0.6
			pose = _make(middle + direction * distance * (1.3 if portrait else 1.0), 1.8 * k + lift, middle, 1.0 * k, 45 + widen)
	pose.position = _clear_of_fighters(pose.position, battle)
	return pose


func _scale() -> float:
	return clampf(maxf(_heights[0], _heights[1]) / REFERENCE_HEIGHT, 0.6, 2.2)


## Smooth wobble in roughly [-1, 1] per axis from a few slow sine waves.
func _wobble(seconds: float) -> Vector3:
	var out := Vector3.ZERO
	for i in WOBBLE_FREQUENCIES.size():
		var phase := _wobble_phases[i]
		var w := TAU * WOBBLE_FREQUENCIES[i] * seconds
		out += Vector3(sin(w + phase.x), sin(w * 1.3 + phase.y), sin(w * 0.7 + phase.z))
	return out / WOBBLE_FREQUENCIES.size()


## Pushes the camera horizontally out of any fighter it would be inside.
func _clear_of_fighters(position: Vector3, battle: Battle) -> Vector3:
	var ground := Vector2(position.x, position.z)
	for side in 2:
		var centre := battle.fighters[side].position
		var keep: float = _heights[side] * CLEARANCE + battle.fighters[side].radius
		var offset := ground - centre
		if offset.length() < keep:
			ground = centre + (offset.normalized() if offset.length() > 0.01 else Vector2(-_axis.y, _axis.x)) * keep
	return Vector3(ground.x, position.y, ground.y)


static func _make(ground: Vector2, height: float, look: Vector2, look_height: float, fov: float) -> Dictionary:
	return {"position": Vector3(ground.x, height, ground.y), "target": Vector3(look.x, look_height, look.y), "fov": fov}


static func _projectile_of(battle: Battle, side: int) -> Vector2:
	for projectile in battle.projectiles:
		if projectile.owner == side:
			return projectile.position
	return Vector2.INF
