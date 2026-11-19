class_name BedrockAnimation
extends RefCounted
## Bakes Bedrock animations (.animation.json, format 1.8.0) into Godot Animations
## (concepts_brief.md §7.3). Every channel is sampled at a fixed rate with Bedrock's own
## interpolation and Molang evaluated at each sample, then stored as linear tracks.
##
## Bedrock adds animated rotation (degrees) to a bone's rest rotation before building the
## basis, adds animated position (pixels) to its rest position, and multiplies scale.

const SAMPLE_RATE := 60.0
const CHANNELS: Array[String] = ["rotation", "position", "scale"]
## A loop with no length and no keyframes of its own, only Molang that reads the animation time
## (most of Cobblemon's idles), plays on continuously in Cobblemon. It is baked over the shortest
## period on the sample grid after which every steady sine and cosine in it is back where it
## started, to within LOOP_PHASE_TOLERANCE of a turn, and no longer than MAX_LOOP_PERIOD.
## Cobblemon's angles are mostly `q.anim_time*90*N`, a period of 4/N s, so most loops are 8 s or
## shorter; one with no such period (a few mix in 36 or 63 degrees a second) is baked over the
## period that comes closest, and jumps a little as it starts over.
const MAX_LOOP_PERIOD := 16.0
const LOOP_PHASE_TOLERANCE := 0.002


## Converts one animation's JSON (`source`). `rest_rotations` maps bone name -> Bedrock rest
## rotation [x, y, z]; `skeleton` supplies rest positions. Problems are appended to `report`
## ({"unknown_bones", "molang_errors", "molang_trailing", "unknown_names"} dictionaries used as sets).
static func build(source: Dictionary, animation_name: String, skeleton: Skeleton3D, rest_rotations: Dictionary,
		skeleton_path: String, report: Dictionary) -> Animation:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(animation_name)
	var channels := {}
	var last_key := 0.0
	for bone_name: String in source.get("bones", {}):
		if skeleton.find_bone(bone_name) < 0:
			report.get_or_add("unknown_bones", {})[bone_name] = true
			continue
		var bone: Dictionary = source.bones[bone_name]
		for channel_name in CHANNELS:
			if bone.has(channel_name):
				var channel := _compile_channel(bone[channel_name], report)
				channels[[bone_name, channel_name]] = channel
				if not channel.is_empty():
					last_key = maxf(last_key, channel[-1].time)
	var animation := Animation.new()
	var loop: Variant = source.get("loop", false)
	animation.loop_mode = Animation.LOOP_LINEAR if loop is bool and loop else Animation.LOOP_NONE
	var length := float(source.get("animation_length", last_key))
	if animation.loop_mode == Animation.LOOP_LINEAR and not source.has("animation_length") and last_key == 0.0:
		length = loop_period(_trig_rates(channels.values()))
	animation.length = maxf(length, 1.0 / SAMPLE_RATE)
	var samples := int(ceil(animation.length * SAMPLE_RATE)) + 1
	for key: Array in channels:
		var bone_name: String = key[0]
		var channel_name: String = key[1]
		var channel: Array = channels[key]
		var bone_index := skeleton.find_bone(bone_name)
		var track_type := Animation.TYPE_ROTATION_3D if channel_name == "rotation" else (
			Animation.TYPE_POSITION_3D if channel_name == "position" else Animation.TYPE_SCALE_3D)
		var track := animation.add_track(track_type)
		animation.track_set_path(track, "%s:%s" % [skeleton_path, bone_name])
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		var rest := skeleton.get_bone_rest(bone_index)
		var rest_rotation: Array = rest_rotations.get(bone_name, [0, 0, 0])
		# A constant channel needs one key; sampling it over a long loop would only bloat the file.
		for i in (1 if _is_constant(channel) else samples):
			var t := minf(i / SAMPLE_RATE, animation.length)
			var value := sample(channel, t, rng)
			match channel_name:
				"rotation":
					var degrees := [float(rest_rotation[0]) + value.x, float(rest_rotation[1]) + value.y, float(rest_rotation[2]) + value.z]
					animation.rotation_track_insert_key(track, t, BedrockGeometry.rotation_basis(degrees).get_rotation_quaternion())
				"position":
					animation.position_track_insert_key(track, t, rest.origin + BedrockGeometry.to_godot([value.x, value.y, value.z]))
				_:
					animation.scale_track_insert_key(track, t, value)
	return animation


## The shortest loop period for angles turning at `rates` (degrees per second), as described at
## MAX_LOOP_PERIOD; 0 when there are none.
static func loop_period(rates: Array[float]) -> float:
	if rates.is_empty():
		return 0.0
	var best := MAX_LOOP_PERIOD
	var best_miss := INF
	for step in range(1, int(MAX_LOOP_PERIOD * SAMPLE_RATE) + 1):
		var period := step / SAMPLE_RATE
		var miss := 0.0
		for rate in rates:
			# Every angle must come round at least once, or a slow one would pass at the first step.
			var turns := period * rate / 360.0
			miss = maxf(miss, absf(turns - maxf(roundf(turns), 1.0)))
		if miss <= LOOP_PHASE_TOLERANCE:
			return period
		if miss < best_miss:
			best_miss = miss
			best = period
	return best


static func _trig_rates(channels: Array) -> Array[float]:
	var rates: Array[float] = []
	for channel: Array in channels:
		for key: Dictionary in channel:
			for part: Variant in key.pre + key.post:
				if part is Molang:
					for rate in part.trig_rates():
						if not rate in rates:
							rates.append(rate)
	return rates


static func _is_constant(channel: Array) -> bool:
	if channel.size() != 1 or channel[0].pre != channel[0].post:
		return false
	for part: Variant in channel[0].pre + channel[0].post:
		if part is Molang:
			return false
	return true


static func _compile_channel(raw: Variant, report: Dictionary) -> Array:
	var keys: Array = []
	if raw is Dictionary and not (raw.has("pre") or raw.has("post") or raw.has("vector")):
		for time_text: String in raw:
			if not time_text.is_valid_float():
				continue  # e.g. "relative_to" settings
			keys.append(_compile_key(time_text.to_float(), raw[time_text], report))
		keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	else:
		keys.append(_compile_key(0.0, raw, report))
	return keys


static func _compile_key(time: float, raw: Variant, report: Dictionary) -> Dictionary:
	var smooth := false
	var pre: Variant = raw
	var post: Variant = raw
	if raw is Dictionary:
		smooth = raw.get("lerp_mode", "") == "catmullrom"
		post = raw.get("post", raw.get("vector", raw.get("pre", [0, 0, 0])))
		pre = raw.get("pre", post)
	return {"time": time, "pre": _compile_vector(pre, report), "post": _compile_vector(post, report), "smooth": smooth}


static func _compile_vector(raw: Variant, report: Dictionary) -> Array:
	var parts: Array = raw if raw is Array else [raw, raw, raw]
	var compiled: Array = []
	for i in 3:
		var part: Variant = parts[i] if i < parts.size() else 0.0
		if part is String:
			var expression := Molang.compile(part)
			if not expression.error.is_empty():
				report.get_or_add("molang_errors", {})[expression.error] = true
			if not expression.ignored.is_empty():
				report.get_or_add("molang_trailing", {})[expression.ignored] = true
			for name in expression.unknown_names:
				report.get_or_add("unknown_names", {})[name] = true
			compiled.append(expression)
		else:
			compiled.append(float(part))
	return compiled


static func _value(parts: Array, t: float, rng: RandomNumberGenerator) -> Vector3:
	var out := Vector3.ZERO
	for i in 3:
		out[i] = parts[i].evaluate(t, rng) if parts[i] is Molang else parts[i]
	return out


## Value of a compiled channel at time t. Between two keys the leaving key's "post" moves to
## the arriving key's "pre"; the segment is Catmull-Rom when either key asks for it.
static func sample(keys: Array, t: float, rng: RandomNumberGenerator) -> Vector3:
	if keys.size() == 1 or t <= keys[0].time:
		return _value(keys[0].pre if t < keys[0].time else keys[0].post, t, rng)
	if t >= keys[-1].time:
		return _value(keys[-1].post, t, rng)
	var i := 0
	while keys[i + 1].time <= t:
		i += 1
	var a: Dictionary = keys[i]
	var b: Dictionary = keys[i + 1]
	var s: float = (t - a.time) / (b.time - a.time)
	var start := _value(a.post, t, rng)
	var end := _value(b.pre, t, rng)
	if not (a.smooth or b.smooth):
		return start.lerp(end, s)
	var before := _value(keys[i - 1].post, t, rng) if i > 0 else start
	var after := _value(keys[i + 2].pre, t, rng) if i + 2 < keys.size() else end
	return _catmull_rom(before, start, end, after, s)


static func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, s: float) -> Vector3:
	var s2 := s * s
	var s3 := s2 * s
	return 0.5 * ((2.0 * p1) + (p2 - p0) * s + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * s2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * s3)
