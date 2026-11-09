class_name CameraRig
extends RefCounted
## Turns the director's shots into camera placements (concepts_brief.md §12.3).
## - Every shot stays on the same side of the line between the fighters (the 180-degree
##   rule), so cuts never swap which fighter is on the left.
## - Distances scale with the fighters' rendered height, so framing holds from small to
##   large Pokémon.
## - The camera is pushed out of any fighter it would end up inside.
## - Portrait frames sit further back and higher so both fighters fit the tall frame.

const AXIS_FOLLOW := 0.02
const SMOOTHING := 0.15
## Shot distances below are tuned for fighters of this height.
const REFERENCE_HEIGHT := 1.5
## The camera keeps at least this many fighter heights away from each fighter's centre.
const CLEARANCE := 0.75
## Knockout sweep: half-width of the arc in radians, and its speed in radians per second.
const KNOCKOUT_ARC := 0.6
const KNOCKOUT_SPEED := 0.25

var portrait := false
var _heights: Array = [1.0, 1.0]
var _axis := Vector2(0, 1)
var _position := Vector3.ZERO
var _target := Vector3.ZERO
var _fov := 50.0


func _init(is_portrait: bool, fighter_heights: Array) -> void:
	portrait = is_portrait
	_heights = fighter_heights


## Updates the camera for this frame. `cut` snaps to the new shot instead of easing into it.
## `shot_seconds` is presentation time since the shot began.
func apply(camera: Camera3D, segment: Dictionary, battle: Battle, shot_seconds: float, cut: bool) -> void:
	var pose := pose_for(segment.shot, segment.side, battle, shot_seconds, cut)
	var weight := 1.0 if cut else SMOOTHING
	_position = pose.position if cut else _position.lerp(pose.position, weight)
	_target = pose.target if cut else _target.lerp(pose.target, weight)
	_fov = pose.fov if cut else lerpf(_fov, pose.fov, weight)
	camera.position = _position
	camera.fov = _fov
	if not _position.is_equal_approx(_target):
		camera.look_at(_target, Vector3.UP)


func pose_for(shot: Director.Shot, side: int, battle: Battle, shot_seconds: float, cut: bool) -> Dictionary:
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
	var k := clampf(maxf(_heights[0], _heights[1]) / REFERENCE_HEIGHT, 0.6, 2.2)
	var back := (1.3 if portrait else 1.0) * k
	var lift := (0.6 if portrait else 0.0) * k
	var widen := 8.0 if portrait else 0.0
	var pose: Dictionary
	match shot:
		Director.Shot.OVER_SHOULDER:
			pose = _make(me - toward * 2.4 * back + across * 2.0 * back, 1.6 * k + lift, other, _heights[1 - side] * 0.5, 50 + widen)
		Director.Shot.CLOSE_UP:
			pose = _make(me + toward * 2.4 * back + across * 2.0 * back, 0.9 * k + lift, me, my_height * 0.55, 40 + widen)
		Director.Shot.TRACKING:
			var projectile := _projectile_of(battle, side)
			var target: Vector2 = projectile if projectile != Vector2.INF else other
			pose = _make((a + b) * 0.5 + across * 5.0 * back, 1.6 * k + lift, target, 1.0, 50 + widen)
		Director.Shot.IMPACT:
			pose = _make(me + across * 2.6 * back - toward * 0.8 * back, 0.8 * k + lift, me, my_height * 0.45, 38 + widen)
		Director.Shot.KNOCKOUT:
			# Sweep an arc on the far side of the fallen fighter, away from the winner.
			var away := -toward
			var angle := atan2(away.y, away.x) + clampf(-KNOCKOUT_ARC + shot_seconds * KNOCKOUT_SPEED, -KNOCKOUT_ARC, KNOCKOUT_ARC)
			var orbit := Vector2(cos(angle), sin(angle)) * 3.2 * back
			pose = _make(me + orbit, 1.2 * k + lift, me, my_height * 0.3, 45 + widen)
		_:
			var middle := (a + b) * 0.5
			var direction := (-_axis * cos(deg_to_rad(80.0)) + across * sin(deg_to_rad(80.0))).normalized()
			var distance := (3.4 if not portrait else 4.0) * k + a.distance_to(b) * 0.6
			pose = _make(middle + direction * distance * (1.3 if portrait else 1.0), 1.8 * k + lift, middle, 1.0 * k, 45 + widen)
	pose.position = _clear_of_fighters(pose.position, battle)
	return pose


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
