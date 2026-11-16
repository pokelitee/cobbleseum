class_name SoundFont
extends RefCounted
## Reads a SoundFont 2 bank and renders single notes from it, for MusicRenderer.
## Covers what General MIDI banks need for this music: preset and instrument zones with key and
## velocity ranges, tuning, sample loops, the volume envelope, attenuation, pan and a low-pass
## for a static filter cutoff. Modulators are not read; velocity follows a squared curve, close
## to the default velocity-to-attenuation modulator.

## Generators whose preset-level values add to the instrument's (SoundFont 2.04, §9.4).
const ADDITIVE: Array[int] = [8, 9, 17, 33, 34, 35, 36, 37, 38, 48, 51, 52, 56]
const DEFAULTS := {8: 13500, 9: 0, 17: 0, 33: -12000, 34: -12000, 35: -12000, 36: -12000, 37: 0, 38: -12000,
	48: 0, 51: 0, 52: 0, 54: 0, 56: 100, 58: -1}
const KEY_RANGE := 43
const VEL_RANGE := 44
const INSTRUMENT := 41
const SAMPLE_ID := 53
## Bank 128 holds the drum kits.
const DRUM_BANK := 128
## Releases longer than this are cut short; nothing in a battle track needs a longer tail.
const MAX_RELEASE := 2.5
## A note stops once its release falls this far (dB) below full level.
const SILENT_DB := -80.0
## initialFilterFc at or above this (absolute cents) leaves the sound unfiltered.
const OPEN_FILTER := 13000.0

var rate := 48000
var _data := PackedByteArray()
var _smpl := 0
var _phdr: Array[Dictionary] = []
var _pbag: Array[int] = []
var _pgen: Array = []
var _inst: Array[int] = []
var _ibag: Array[int] = []
var _igen: Array = []
var _shdr: Array[Dictionary] = []
var _samples := {}
var _presets := {}


## Loads a bank; returns an error message, or "" on success.
func load_file(path: String) -> String:
	_data = FileAccess.get_file_as_bytes(path)
	if _data.size() < 12 or _data.slice(0, 4).get_string_from_ascii() != "RIFF" or _data.slice(8, 12).get_string_from_ascii() != "sfbk":
		return "%s is not a SoundFont 2 file" % path
	var p := 12
	while p + 8 <= _data.size():
		var id := _data.slice(p, p + 4).get_string_from_ascii()
		var size := _data.decode_u32(p + 4)
		if id == "LIST":
			var q := p + 12
			var end := mini(p + 8 + size, _data.size())
			while q + 8 <= end:
				var chunk := _data.slice(q, q + 4).get_string_from_ascii()
				var chunk_size := _data.decode_u32(q + 4)
				_read_chunk(chunk, q + 8, chunk_size)
				q += 8 + chunk_size + (chunk_size & 1)
		p += 8 + size + (size & 1)
	if _phdr.size() < 2 or _shdr.is_empty() or _smpl == 0:
		return "%s has no presets or samples" % path
	for i in _phdr.size() - 1:  # the last header is the terminal record
		_presets[_phdr[i].bank * 256 + _phdr[i].preset] = i
	return ""


func has_preset(bank: int, program: int) -> bool:
	return _presets.has(bank * 256 + program)


func preset_name(bank: int, program: int) -> String:
	return _phdr[_presets[bank * 256 + program]].name if has_preset(bank, program) else ""


## Renders one note held for `duration` seconds plus its release: [left, right] buffers at `rate`.
func note(bank: int, program: int, key: int, velocity: int, duration: float) -> Array[PackedFloat32Array]:
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	for zone in zones(bank, program, key, velocity):
		var voice := _voice(zone, key, velocity, duration)
		if voice[0].size() > left.size():
			left.resize(voice[0].size())
			right.resize(voice[0].size())
		for i in voice[0].size():
			left[i] += voice[0][i]
			right[i] += voice[1][i]
	return [left, right]


## The generator values of every instrument zone that sounds for this key and velocity, with
## instrument global zones applied and preset values added (SoundFont 2.04, §9.4).
func zones(bank: int, program: int, key: int, velocity: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not has_preset(bank, program):
		return out
	var index: int = _presets[bank * 256 + program]
	var preset_zones := _zone_list(_pbag, _pgen, _phdr[index].bag, _phdr[index + 1].bag)
	var preset_global := {}
	for zi in preset_zones.size():
		var zone: Dictionary = preset_zones[zi]
		if not zone.has(INSTRUMENT):
			if zi == 0:
				preset_global = zone
			continue
		if not _in_range(zone, preset_global, key, velocity):
			continue
		var preset_values := preset_global.duplicate()
		preset_values.merge(zone, true)
		var instrument: int = zone[INSTRUMENT]
		var instrument_zones := _zone_list(_ibag, _igen, _inst[instrument], _inst[instrument + 1])
		var instrument_global := {}
		for ji in instrument_zones.size():
			var local: Dictionary = instrument_zones[ji]
			if not local.has(SAMPLE_ID):
				if ji == 0:
					instrument_global = local
				continue
			if not _in_range(local, instrument_global, key, velocity):
				continue
			var values := DEFAULTS.duplicate()
			values.merge(instrument_global, true)
			values.merge(local, true)
			for gen: int in preset_values:
				if gen in ADDITIVE:
					values[gen] = values.get(gen, 0) + preset_values[gen]
			out.append(values)
	return out


func _read_chunk(id: String, offset: int, size: int) -> void:
	match id:
		"smpl":
			_smpl = offset
		"phdr":
			for r in range(offset, offset + size, 38):
				_phdr.append({"name": _data.slice(r, r + 20).get_string_from_ascii(), "preset": _data.decode_u16(r + 20),
					"bank": _data.decode_u16(r + 22), "bag": _data.decode_u16(r + 24)})
		"pbag":
			for r in range(offset, offset + size, 4):
				_pbag.append(_data.decode_u16(r))
		"ibag":
			for r in range(offset, offset + size, 4):
				_ibag.append(_data.decode_u16(r))
		"pgen":
			for r in range(offset, offset + size, 4):
				_pgen.append([_data.decode_u16(r), _data.decode_s16(r + 2), _data[r + 2], _data[r + 3]])
		"igen":
			for r in range(offset, offset + size, 4):
				_igen.append([_data.decode_u16(r), _data.decode_s16(r + 2), _data[r + 2], _data[r + 3]])
		"inst":
			for r in range(offset, offset + size, 22):
				_inst.append(_data.decode_u16(r + 20))
		"shdr":
			for r in range(offset, offset + size, 46):
				_shdr.append({"start": _data.decode_u32(r + 20), "end": _data.decode_u32(r + 24),
					"loop_start": _data.decode_u32(r + 28), "loop_end": _data.decode_u32(r + 32),
					"rate": _data.decode_u32(r + 36), "pitch": _data[r + 40], "correction": _data.decode_s8(r + 41)})


static func _zone_list(bags: Array[int], gens: Array, first: int, last: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in range(first, last):
		var zone := {}
		for g in range(bags[b], bags[b + 1]):
			var gen: Array = gens[g]
			zone[gen[0]] = Vector2i(gen[2], gen[3]) if gen[0] == KEY_RANGE or gen[0] == VEL_RANGE else gen[1]
		out.append(zone)
	return out


static func _in_range(zone: Dictionary, global: Dictionary, key: int, velocity: int) -> bool:
	var keys: Vector2i = zone.get(KEY_RANGE, global.get(KEY_RANGE, Vector2i(0, 127)))
	var velocities: Vector2i = zone.get(VEL_RANGE, global.get(VEL_RANGE, Vector2i(0, 127)))
	return key >= keys.x and key <= keys.y and velocity >= velocities.x and velocity <= velocities.y


func _sample(id: int) -> PackedFloat32Array:
	if not _samples.has(id):
		var header: Dictionary = _shdr[id]
		var count: int = maxi(0, header.end - header.start)
		var values := PackedFloat32Array()
		values.resize(count)
		var base: int = _smpl + header.start * 2
		for i in count:
			values[i] = _data.decode_s16(base + i * 2) / 32768.0
		_samples[id] = values
	return _samples[id]


static func _seconds(timecents: float) -> float:
	return pow(2.0, timecents / 1200.0)


func _voice(zone: Dictionary, key: int, velocity: int, duration: float) -> Array[PackedFloat32Array]:
	var header: Dictionary = _shdr[zone[SAMPLE_ID]]
	var sample := _sample(zone[SAMPLE_ID])
	var loop_start: int = header.loop_start - header.start + zone.get(2, 0) + 32768 * zone.get(45, 0)
	var loop_end: int = header.loop_end - header.start + zone.get(3, 0) + 32768 * zone.get(50, 0)
	var looping: bool = (int(zone[54]) & 1) == 1 and loop_end > loop_start
	var root: int = zone[58] if zone[58] >= 0 else header.pitch
	var cents: float = (key - root) * zone[56] + zone[51] * 100 + zone[52] + header.correction
	var step: float = pow(2.0, cents / 1200.0) * header.rate / rate
	# initialAttenuation is scaled by 0.4, as most players do, to match how banks are voiced.
	var gain := pow(10.0, -zone[48] * 0.4 / 200.0) * pow(velocity / 127.0, 2.0)
	var pan := clampf(zone[17] / 500.0, -1.0, 1.0)
	var gain_left := cos((pan + 1.0) * PI / 4.0) * gain
	var gain_right := sin((pan + 1.0) * PI / 4.0) * gain
	var delay := _seconds(zone[33])
	var attack := _seconds(zone[34])
	var hold := _seconds(zone[35])
	var decay := _seconds(zone[36])
	var sustain_db := -clampf(zone[37], 0.0, 1440.0) / 10.0
	var release := minf(_seconds(zone[38]), MAX_RELEASE)
	var cutoff: float = zone[8]
	var filtered := cutoff < OPEN_FILTER
	var coeff := 1.0 - exp(-TAU * minf(8.176 * pow(2.0, cutoff / 1200.0), rate * 0.45) / rate)
	var total := int((duration + release) * rate)
	var release_at := int(duration * rate)
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(total)
	right.resize(total)
	var position := 0.0
	var smoothed := 0.0
	var level_db := 0.0
	var release_db := 0.0
	var length := sample.size()
	var used := total
	for i in total:
		var t := float(i) / rate
		var envelope: float
		if i < release_at:
			if t < delay:
				envelope = 0.0
				level_db = SILENT_DB
			elif t < delay + attack:
				envelope = (t - delay) / attack
				level_db = linear_to_db(maxf(envelope, 1e-4))
			elif t < delay + attack + hold:
				envelope = 1.0
				level_db = 0.0
			else:
				level_db = maxf(sustain_db, -96.0 * (t - delay - attack - hold) / decay)
				envelope = db_to_linear(level_db)
			release_db = level_db
		else:
			var db := release_db - 96.0 * (t - duration) / release
			if db < SILENT_DB:
				used = i
				break
			envelope = db_to_linear(db)
		var index := int(position)
		if index + 1 >= length:
			used = i
			break
		var frac := position - index
		var x := sample[index] * (1.0 - frac) + sample[index + 1] * frac
		if filtered:
			smoothed += coeff * (x - smoothed)
			x = smoothed
		left[i] = x * envelope * gain_left
		right[i] = x * envelope * gain_right
		position += step
		if looping and position >= loop_end:
			position -= loop_end - loop_start
	left.resize(used)
	right.resize(used)
	return [left, right]
