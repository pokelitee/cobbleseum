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
## - Doubles (M17): the line of action runs between the sides' middles, wide and
##   over-the-shoulder shots frame all four, and shots on one fighter (its "slot") look at it
##   and at its target.
## Every value comes from the battle, the shot and a seeded stream, so re-renders match.

const AXIS_FOLLOW := 0.02
const SMOOTHING := 0.15
## A new shot whose camera would sit near the current one (eyes within NEAR_DISTANCE, times
## the fighters' scale, and looking within NEAR_ANGLE of the same way) eases onto it over
## BLEND_SECONDS instead of cutting; tracking whips into an impact over WHIP_SECONDS.
const NEAR_DISTANCE := 3.0
const NEAR_ANGLE := deg_to_rad(40.0)
const BLEND_SECONDS := 0.4
const WHIP_SECONDS := 0.2
## Shot distances below are tuned for fighters of this height.
const REFERENCE_HEIGHT := 1.5
## The camera keeps at least this many fighter heights away from each fighter's centre.
const CLEARANCE := 0.75
## Wide shots arc around the fighters at this rate, in radians per second.
const WIDE_ARC_SPEED := 0.06
## Knockout sweep: half-width of the arc in radians, and its speed in radians per second.
const KNOCKOUT_ARC := 0.6
const KNOCKOUT_SPEED := 0.25
## Eye height of a low over-the-shoulder shot (a segment with "low"), for a reference-height
## fighter.
const LOW_SHOULDER_HEIGHT := 0.7
## Handheld wobble amplitude per shot, in metres for a reference-height fighter.
const WOBBLE := {
	Director.Shot.WIDE: 0.04, Director.Shot.OVER_SHOULDER: 0.07, Director.Shot.CLOSE_UP: 0.05,
	Director.Shot.TRACKING: 0.08, Director.Shot.IMPACT: 0.12, Director.Shot.KNOCKOUT: 0.05, Director.Shot.VICTORY: 0.03,
}
## Wobble frequencies in hertz; slow enough to read as a held camera, not shake.
const WOBBLE_FREQUENCIES: Array[float] = [0.31, 0.53, 0.89]
## Doubles: a shot whose view another fighter blocks swings around its target by this much
## (degrees) at a time, or rises this far (for a reference-height fighter).
const UNBLOCK_SWING := 30.0
const UNBLOCK_LIFT := 1.8

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
## Whether the last apply() cut to a new shot rather than moving the camera.
var cut := false
## Where the camera was as the current shot began ({"position", "target", "fov"}), and how
## long it eases from there; {} before the first shot.
var _blend_from: Dictionary = {}
var _blend_seconds := 0.0


## The height of the fighter out at `index` (Battle.index_of; its side in singles), after a team
## battle sends out another.
func set_height(index: int, height: float) -> void:
	_heights[index] = height


## `random` seeds the handheld wobble; give it its own stream so it can't shift other choices.
## `fighter_heights` are the fighters' out, by Battle.index_of.


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
	_last_shot = segment.shot
	var pose := pose_for(segment, battle, shot_seconds, progress, new_shot)
	# Shots are framed for the floor; lift them with the fighters' ground.
	var ground := 0.0
	for fighter in battle.fighters:
		ground += fighter.ground
	var lift := Vector3.UP * ground / battle.fighters.size()
	pose.position += lift
	pose.target += lift
	cut = new_shot and not (whip or _near(pose))
	if new_shot:
		_blend_from = {"position": _position, "target": _target, "fov": _fov}
		_blend_seconds = 0.0 if cut else (WHIP_SECONDS if whip else BLEND_SECONDS)
	if cut:
		_position = pose.position
		_target = pose.target
		_fov = pose.fov
	elif shot_seconds < _blend_seconds:
		# Eases from where the last shot left the camera onto the new one, which keeps moving.
		var weight := smoothstep(0.0, _blend_seconds, shot_seconds)
		_position = (_blend_from.position as Vector3).lerp(pose.position, weight)
		_target = (_blend_from.target as Vector3).lerp(pose.target, weight)
		_fov = lerpf(_blend_from.fov, pose.fov, weight)
	else:
		_position = _position.lerp(pose.position, SMOOTHING)
		_target = _target.lerp(pose.target, SMOOTHING)
		_fov = lerpf(_fov, pose.fov, SMOOTHING)
	var k := _scale()
	var wobble := _wobble(seconds) * float(WOBBLE.get(segment.shot, 0.05)) * k
	camera.fov = _fov
	var eye := keep_inside(_position + wobble, limit)
	var look := _target + wobble * 0.5
	if eye.is_equal_approx(look):
		camera.position = eye
	else:
		camera.look_at_from_position(eye, look, Vector3.UP)


## Whether a new shot's `pose` is close enough to where the camera is to blend rather than cut.
func _near(pose: Dictionary) -> bool:
	if _blend_from.is_empty() and _position == Vector3.ZERO:
		return false
	var looking := _target - _position
	var will_look: Vector3 = pose.target - pose.position
	if looking.length_squared() < 1e-6 or will_look.length_squared() < 1e-6:
		return false
	return _position.distance_to(pose.position) <= NEAR_DISTANCE * _scale() and looking.angle_to(will_look) <= NEAR_ANGLE


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
	var focus := battle.fighters[side]
	var facing_foe := battle.fighters[1 - side]
	var span := a.distance_to(b)
	if battle.doubles:
		a = _middle(battle, 0)
		b = _middle(battle, 1)
		focus = _focus(battle, segment)
		facing_foe = _foe_of(battle, segment, focus)
		span = _span(battle)
	if a.distance_to(b) > 0.01:
		_axis = (b - a).normalized() if cut else _axis.slerp((b - a).normalized(), AXIS_FOLLOW).normalized()
	# The camera's side of the line of action; keeps fighter A on screen-left.
	var across := Vector2(-_axis.y, _axis.x)
	var me := focus.position
	var other := facing_foe.position
	var toward := (other - me).normalized() if me.distance_to(other) > 0.01 else _axis * (1 if side == 0 else -1)
	var my_height: float = _height_of(battle, focus)
	var other_height: float = _height_of(battle, facing_foe)
	var k := _scale()
	var back := (1.3 if portrait else 1.0) * k
	var lift := (0.6 if portrait else 0.0) * k
	var widen := 8.0 if portrait else 0.0
	var eased := ease(clampf(progress, 0.0, 1.0), -1.8)  # ease in and out
	var pose: Dictionary
	match segment.shot:
		Director.Shot.OVER_SHOULDER:
			# Slow push-in toward the opponent; the instant replay's version sits low.
			var push := lerpf(1.15, 0.85, eased)
			var eye_height := (LOW_SHOULDER_HEIGHT if segment.get("low", false) else 1.6) * k + lift
			if battle.doubles and not segment.has("slot"):
				# Over the side's shoulder at everyone: from behind its middle, toward the foes'.
				var behind := (b - a).normalized() * (1 if side == 0 else -1)
				var mine := a if side == 0 else b
				pose = _make(mine - behind * (2.4 + span * 0.25) * back * push + across * 2.4 * back, eye_height,
					(a + b) * 0.5 + behind * span * 0.15, 0.8 * k, 52 + widen)
			else:
				pose = _make(me - toward * 2.4 * back * push + across * 2.0 * back, eye_height, other, other_height * 0.5, 50 + widen)
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
			var facing: Vector2 = focus.facing
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
			if battle.doubles:
				middle = _middle(battle, -1)
			var distance := (3.4 if not portrait else 4.0) * k + span * (0.75 if battle.doubles and portrait else 0.6)
			pose = _make(middle + direction * distance * (1.3 if portrait else 1.0), 1.8 * k + lift, middle, 1.0 * k, 45 + widen)
	if battle.doubles and segment.shot != Director.Shot.WIDE:
		pose = _unblocked(pose, battle, [focus, facing_foe])
	pose.position = _clear_of_fighters(pose.position, battle)
	return pose


## Doubles: `pose`, or the first of a few nearby poses (swung around its target, then raised)
## that no fighter other than `keep` stands in front of; the raised one if none is clear.
func _unblocked(pose: Dictionary, battle: Battle, keep: Array) -> Dictionary:
	var target: Vector3 = pose.target
	var eye: Vector3 = pose.position
	var flat := Vector2(eye.x - target.x, eye.z - target.z)
	var tries: Array[Vector3] = [eye]
	for degrees: float in [UNBLOCK_SWING, -UNBLOCK_SWING, 2.0 * UNBLOCK_SWING, -2.0 * UNBLOCK_SWING]:
		var turned := flat.rotated(deg_to_rad(degrees))
		tries.append(Vector3(target.x + turned.x, eye.y, target.z + turned.y))
	var raised := eye + Vector3.UP * UNBLOCK_LIFT * _scale()
	tries.append(raised)
	for candidate in tries:
		if not _blocked(candidate, target, battle, keep):
			return {"position": candidate, "target": target, "fov": pose.fov}
	return {"position": raised, "target": target, "fov": pose.fov}


## Whether a fighter up, other than those in `keep`, stands between `eye` and `target`.
func _blocked(eye: Vector3, target: Vector3, battle: Battle, keep: Array) -> bool:
	for index in battle.fighters.size():
		var fighter := battle.fighters[index]
		if keep.has(fighter) or fighter.is_knocked_out():
			continue
		var height: float = _heights[index]
		var body := Vector3(fighter.position.x, height * 0.5, fighter.position.y)
		var line := target - eye
		var along := clampf((body - eye).dot(line) / maxf(line.length_squared(), 1e-6), 0.0, 1.0)
		if along > 0.02 and along < 0.98 and (eye + line * along).distance_to(body) < maxf(height * 0.5, fighter.radius):
			return true
	return false


func _scale() -> float:
	var tallest := 0.0
	for height: float in _heights:
		tallest = maxf(tallest, height)
	return clampf(tallest / REFERENCE_HEIGHT, 0.6, 2.2)


## The height of a fighter out (by its place), or the reference height for one that isn't.
func _height_of(battle: Battle, fighter: Fighter) -> float:
	var index := battle.fighters.find(fighter)
	return _heights[index] if index >= 0 and index < _heights.size() else REFERENCE_HEIGHT


## Doubles: the middle of `side`'s fighters out and up (of everyone's for -1), else of all out.
static func _middle(battle: Battle, side: int) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for fighter in battle.fighters:
		if (side < 0 or fighter.side == side) and not fighter.is_knocked_out():
			total += fighter.position
			count += 1
	if count == 0:
		for fighter in battle.fighters:
			if side < 0 or fighter.side == side:
				total += fighter.position
				count += 1
	return total / count


## Doubles: the most distance between two fighters out and up.
static func _span(battle: Battle) -> float:
	var span := 0.0
	for i in battle.fighters.size():
		for j in range(i + 1, battle.fighters.size()):
			if not battle.fighters[i].is_knocked_out() and not battle.fighters[j].is_knocked_out():
				span = maxf(span, battle.fighters[i].position.distance_to(battle.fighters[j].position))
	return span


## Doubles: the fighter a shot is on: its "slot" of its side's team, else the side's first up.
static func _focus(battle: Battle, segment: Dictionary) -> Fighter:
	var side: int = segment.side
	if segment.has("slot") and int(segment.slot) < battle.teams[side].size():
		return battle.teams[side][int(segment.slot)]
	var out := battle.out(side)
	for fighter in out:
		if not fighter.is_knocked_out():
			return fighter
	return out[0]


## Doubles: who the focus faces: the shot's "target_slot" of the other side, else the focus's
## target if it's out, else the other side's first up.
static func _foe_of(battle: Battle, segment: Dictionary, focus: Fighter) -> Fighter:
	var side := 1 - int(segment.side)
	if segment.has("target_slot") and int(segment.target_slot) < battle.teams[side].size():
		return battle.teams[side][int(segment.target_slot)]
	if battle.fighters.has(focus):
		return battle.target_of(focus)
	return _focus(battle, {"side": side})


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
	for index in battle.fighters.size():
		var centre := battle.fighters[index].position
		var keep: float = _heights[index] * CLEARANCE + battle.fighters[index].radius
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
