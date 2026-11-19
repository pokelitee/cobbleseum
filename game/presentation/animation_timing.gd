class_name AnimationTiming
extends RefCounted
## Reads timing from a model's animations (concepts_brief.md §7.4), so FighterView can fit
## them to the battle: when an attack animation strikes, and whether an idle holds still.

## Steps at which animations are sampled, in seconds.
const SAMPLE := 1.0 / 30.0
## The strike is looked for within this share of an attack animation: before it is the
## wind-up, after it the follow-through.
const STRIKE_WINDOW := Vector2(0.15, 0.7)
## An idle holds still when no bone turns more than STILL_TURN (radians) or moves more than
## STILL_MOVE (model units) away from its first pose over the whole loop.
const STILL_TURN := 0.01
const STILL_MOVE := 0.01


## The strike in an attack animation: the moment its bones turn fastest, in seconds. Cobblemon's
## attack animations run 3 s and strike about 1.2 s in, where its own battles play the hit.
static func strike_time(animation: Animation) -> float:
	var best := 0.0
	var best_time := animation.length * 0.4
	var time := maxf(SAMPLE, animation.length * STRIKE_WINDOW.x)
	while time <= animation.length * STRIKE_WINDOW.y:
		var turning := 0.0
		for track in animation.get_track_count():
			if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				turning += animation.rotation_track_interpolate(track, time - SAMPLE).angle_to(animation.rotation_track_interpolate(track, time))
		if turning > best:
			best = turning
			best_time = time
		time += SAMPLE
	return best_time


## Whether an animation holds one pose throughout. Some converted idles do (317 of 1,005
## species), and some walks.
static func is_still(animation: Animation) -> bool:
	for track in animation.get_track_count():
		var type := animation.track_get_type(track)
		if (type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D) or animation.track_get_key_count(track) < 2:
			continue
		var time := SAMPLE
		while time <= animation.length:
			if type == Animation.TYPE_ROTATION_3D:
				if animation.rotation_track_interpolate(track, 0.0).angle_to(animation.rotation_track_interpolate(track, time)) > STILL_TURN:
					return false
			elif animation.position_track_interpolate(track, 0.0).distance_to(animation.position_track_interpolate(track, time)) > STILL_MOVE:
				return false
			time += SAMPLE
	return true
