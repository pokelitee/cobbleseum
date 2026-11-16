class_name MusicArranger
extends RefCounted
## Turns a track's score (tools/music/scores/*.json) into notes on General MIDI instruments,
## grouped into the layers the game mixes (BattleMusic): drums and lead in two variants each,
## bass, harmony, and the climax layer that overtime fades in.
##
## A score holds what is particular to a track: tempo, scale, chords, melodies and the intro.
## The arrangement rules here hold what the tracks share: each section has one 16th-note driver,
## one lead, bass, drums, and brass stabs in the melody's gaps, by the section's role:
## - "main": staccato strings drive; a synth lead with trumpet answers, a harmony a third
##   below in its second half;
## - "lift": a square arpeggio drives; the trumpet leads with strings an octave below;
## - "contrast": a pedal bass and staccato strings under held strings; trumpets carry the line,
##   brass and horns answer, and its last bar rises back into the loop.
## The intro (a run, 3-3-2 hits, a vamp) plays once; the sections loop.
##
## Melodies sound as written on the lead; every other written line sounds an octave lower.

const STEPS_PER_BAR := 16
const LAYERS: Array[String] = ["drums_0", "drums_1", "bass", "harmony", "lead_0", "lead_1", "climax"]
const ROLES: Array[String] = ["main", "lift", "contrast"]
const INTRO_BARS := 3
const SECTION_BARS := 8

# General MIDI programs (0-based) and drum keys.
const TRUMPET := 56
const BRASS := 61
const HORNS := 60
const FAST_STRINGS := 48
const SLOW_STRINGS := 49
const SQUARE := 80
const SYNTH_BASS := 38
const TIMPANI := 47
const ORCH_HIT := 55
const DRUMS := 128
const KICK := 36
const SNARE := 38
const CLAP := 39
const HAT := 42
const OPEN_HAT := 46
const CRASH := 49
const RIDE := 51
const TOMS: Array[int] = [50, 48, 47, 45, 43, 41]
const NOTE_NAMES := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

var _notes: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _arp_side := 1.0


## Reads a score file. Returns {"score": Dictionary} with its keys and chords as whole numbers,
## or {"error": String}. One-shot pieces (with "parts") are checked by one_shot_problem().
static func load_score(path: String) -> Dictionary:
	var score: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var err := one_shot_problem(score) if score is Dictionary and score.has("parts") else problem(score)
	if not err.is_empty():
		return {"error": "%s: %s" % [path, err]}
	if score.has("chords"):
		for name: String in score.chords:
			score.chords[name] = _ints(score.chords[name])
		score.leads = _ints(score.leads)
		score.scale = _ints(score.scale)
		for section: Dictionary in score.sections:
			section.rise = _ints(section.get("rise", []))
	return {"score": score}


static func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	for value: Variant in values:
		out.append(int(value))
	return out


## Returns a description of what is wrong with a score, or "" if it can be arranged.
static func problem(score: Variant) -> String:
	if not score is Dictionary:
		return "not a JSON object"
	for key in ["title", "bpm", "scale", "chords", "intro", "sections", "leads"]:
		if not score.has(key):
			return "missing \"%s\"" % key
	if not (score.bpm is float and score.bpm >= 60.0 and score.bpm <= 240.0):
		return "\"bpm\" must be a number from 60 to 240"
	if not (score.leads is Array and score.leads.size() == 2):
		return "\"leads\" must list two General MIDI programs, one per lead variant"
	var chords: Dictionary = score.chords
	for name: String in chords:
		if not (chords[name] is Array and chords[name].size() >= 3):
			return "chord %s needs at least three notes" % name
	var sections: Array = score.sections
	if sections.size() != ROLES.size():
		return "needs three sections, one per role (%s)" % ", ".join(ROLES)
	for i in sections.size():
		var section: Dictionary = sections[i]
		if section.get("role", "") != ROLES[i]:
			return "section %d must have the role \"%s\"" % [i + 1, ROLES[i]]
		for key in ["chords", "melody"]:
			if not (section.get(key) is Array and section[key].size() == SECTION_BARS):
				return "section %d needs %d bars of \"%s\"" % [i + 1, SECTION_BARS, key]
		for bar: Array in section.chords:
			var steps := 0
			for part: Array in bar:
				if not chords.has(part[0]):
					return "section %d uses unknown chord %s" % [i + 1, part[0]]
				steps += int(part[1])
			if steps != STEPS_PER_BAR:
				return "section %d has a bar of chords %d steps long" % [i + 1, steps]
		for key in ["melody", "response", "answer", "horn"]:
			for line: String in section.get(key, []):
				var length := line_length(line)
				if length < 0:
					return "section %d has a bad note in \"%s\": %s" % [i + 1, key, line]
				if length > STEPS_PER_BAR:
					return "section %d has a bar of \"%s\" %d steps long" % [i + 1, key, length]
	var intro: Dictionary = score.intro
	for key in ["hit", "vamp"]:
		if not chords.has(intro.get(key, "")):
			return "intro \"%s\" must name a chord" % key
	if line_length(intro.get("run", "")) != STEPS_PER_BAR:
		return "intro \"run\" must be one bar of notes"
	return ""


## The length of a written line in 16ths, or -1 if a note can't be read.
static func line_length(line: String) -> int:
	if line.is_empty():
		return 0
	var steps := 0
	for token in line.split(" "):
		var parts := token.split(":")
		if parts.size() != 2 or not parts[1].is_valid_int() or (parts[0] != "r" and midi(parts[0]) < 0):
			return -1
		steps += int(parts[1])
	return steps


## The MIDI key of a note name such as "C#5" or "Bb4", or -1.
static func midi(name: String) -> int:
	if name.length() < 2 or not NOTE_NAMES.has(name[0]):
		return -1
	var semitone: int = NOTE_NAMES[name[0]]
	var i := 1
	if name[i] == "#":
		semitone += 1
		i += 1
	elif name[i] == "b":
		semitone -= 1
		i += 1
	if not name.substr(i).is_valid_int():
		return -1
	return 12 * (int(name.substr(i)) + 1) + semitone


## The bass note for a chord: its root, between G1 and F#2.
static func bass_root(notes: Array) -> int:
	return 31 + posmod(int(notes[0]) - 7, 12)


## The note a diatonic third below `key` in a scale given as pitch classes.
static func third_below(key: int, scale: Array) -> int:
	var pitch_class := posmod(key, 12)
	var sorted := scale.map(func(p: Variant) -> int: return posmod(int(p), 12))
	sorted.sort()
	var degree := sorted.find(pitch_class)
	if degree < 0:
		# A raised note (a leading tone) takes the major third below, as the harmonic minor does.
		return key - (4 if posmod(key - 4, 12) in sorted else 3)
	var below: int = sorted[posmod(degree - 2, sorted.size())]
	return key - posmod(pitch_class - below, 12)


## True when a bar's melody opens with a note held for at least six 16ths.
static func opens_long(line: String) -> bool:
	var first := line.split(" ")[0].split(":")
	return first.size() == 2 and first[0] != "r" and int(first[1]) >= 6


## Arranges a valid score. Returns {"notes": [...], "loop_start": step, "loop_end": step}, where
## each note is {"layer", "step", "length" (16ths), "bank", "program", "key", "velocity",
## "gain", "pan", "reverb", "echo"}. The same score always gives the same notes.
func arrange(score: Dictionary) -> Dictionary:
	_notes = []
	_rng.seed = hash(score.title)
	_arp_side = 1.0
	_intro(score)
	var bar := INTRO_BARS
	var sections: Array = score.sections
	for s in sections.size():
		var section: Dictionary = sections[s]
		for index in SECTION_BARS:
			var next_chord: String
			if index + 1 < SECTION_BARS:
				next_chord = section.chords[index + 1][0][0]
			else:
				next_chord = sections[(s + 1) % sections.size()].chords[0][0][0]
			_section_bar(score, section, index, bar * STEPS_PER_BAR, score.chords[next_chord])
			bar += 1
	return {"notes": _notes, "loop_start": INTRO_BARS * STEPS_PER_BAR, "loop_end": bar * STEPS_PER_BAR}


## Returns what is wrong with a one-shot piece's score (the victory sting), or "".
## It lists "parts": each a "line" played at the written pitch on one General MIDI "program"
## (with "bank" 128 for drums), at a "velocity" and "gain", optionally panned.
static func one_shot_problem(score: Variant) -> String:
	if not (score is Dictionary and score.get("bpm") is float and score.get("parts") is Array and not score.parts.is_empty()):
		return "needs a \"bpm\" and a list of \"parts\""
	for part: Variant in score.parts:
		if not (part is Dictionary and part.get("line") is String and part.get("program") is float):
			return "every part needs a \"program\" and a \"line\""
		if line_length(part.line) < 0:
			return "bad note in \"%s\"" % part.line
	return ""


## Notes of a valid one-shot piece, all in the layer "once".
func arrange_once(score: Dictionary) -> Array[Dictionary]:
	_notes = []
	for part: Dictionary in score.parts:
		var s := 0
		for token: String in part.line.split(" "):
			var parts := token.split(":")
			if parts[0] != "r":
				_add("once", s, int(parts[1]) * 0.95, int(part.program), midi(parts[0]), int(part.get("velocity", 100)),
					float(part.get("gain", 0.5)), float(part.get("pan", 0.0)), 0.35, 0.0, int(part.get("bank", 0)))
			s += int(parts[1])
	return _notes


func _add(layer: String, step: float, length: float, program: int, key: int, velocity: int, gain: float,
		pan := 0.0, reverb := 0.25, echo := 0.0, bank := 0) -> void:
	_notes.append({"layer": layer, "step": step, "length": length, "bank": bank, "program": program, "key": key,
		"velocity": clampi(velocity, 1, 127), "gain": gain, "pan": pan, "reverb": reverb, "echo": echo})


func _drum(layers: Array, step: float, key: int, velocity: int, gain: float, pan := 0.0, reverb := 0.15) -> void:
	for layer: String in layers:
		_add(layer, step, 4.0, 0, key, velocity, gain, pan, reverb, 0.0, DRUMS)


func _both(base: String, step: float, length: float, program: int, key: int, velocity: int, gain: float,
		pan := 0.0, reverb := 0.25, echo := 0.0) -> void:
	for variant in 2:
		_add("%s_%d" % [base, variant], step, length, program, key, velocity, gain, pan, reverb, echo)


func _intro(score: Dictionary) -> void:
	var intro: Dictionary = score.intro
	var drums := ["drums_0", "drums_1"]
	var roll: int = bass_root(score.chords[intro.hit]) + 12
	var step := 0
	for token: String in intro.run.split(" "):
		var parts := token.split(":")
		if parts[0] != "r":
			var key := midi(parts[0])
			_add("harmony", step, 0.9, FAST_STRINGS, key, 90 + step * 2, 0.5, -0.2, 0.3)
			_add("harmony", step, 0.9, FAST_STRINGS, key - 12, 90 + step * 2, 0.4, 0.2, 0.3)
			_add("harmony", step, 0.9, BRASS, key - 12, 80 + step * 2, 0.3, 0.0, 0.3)
		step += int(parts[1])
	_timpani_roll(0, STEPS_PER_BAR, roll)
	var hits := STEPS_PER_BAR
	var hit_chord: Array = score.chords[intro.hit]
	for s in [0, 3, 6]:
		var at: int = hits + s
		for n: int in hit_chord:
			_add("harmony", at, 2.0, BRASS, n, 120, 0.4)
			_add("harmony", at, 2.0, BRASS, n + 12, 110, 0.25)
		_add("harmony", at, 2.0, ORCH_HIT, int(hit_chord[0]) + 12, 115, 0.5)
		_add("bass", at, 2.0, SYNTH_BASS, bass_root(hit_chord) + 12, 120, 1.0)
		_add("harmony", at, 3.0, TIMPANI, roll, 120, 0.8)
		_drum(drums, at, KICK, 120, 0.9)
		_drum(drums, at, CRASH if s == 0 else SNARE, 115, 0.6)
	_drum(drums, hits + 8, KICK, 110, 0.9)
	_drum(drums, hits + 9, SNARE, 80, 0.5)
	for s in range(10, 16):
		_drum(drums, hits + s, TOMS[s - 10], 90 + 5 * (s - 10), 0.7, 0.3 - 0.12 * (s - 10))
	var vamp := 2 * STEPS_PER_BAR
	var vamp_chord: Array = score.chords[intro.vamp]
	var root := bass_root(vamp_chord)
	for s in STEPS_PER_BAR:
		if s % 2 == 0:
			_add("bass", vamp + s, 1.2, SYNTH_BASS, root + (12 if s % 4 == 2 else 0), 110, 1.0)
		_ostinato(vamp + s, s, vamp_chord)
		if s in [0, 3, 6]:
			for n: int in vamp_chord:
				_add("harmony", vamp + s, 1.6, BRASS, n, 110, 0.3)
	_groove(vamp, "main", true, false)


func _ostinato(step: int, s: int, chord: Array) -> void:
	var accent := s % 8 in [0, 3, 6]
	_add("harmony", step, 0.45, FAST_STRINGS, int(chord[0]) - 12 + (12 if s % 8 == 6 else 0), 108 if accent else 72, 0.5, -0.35, 0.2)


func _section_bar(score: Dictionary, section: Dictionary, index: int, start: int, next_chord: Array) -> void:
	var role: String = section.role
	var second := index >= SECTION_BARS / 2
	var melody: String = section.melody[index]
	var next_root := bass_root(next_chord)
	var step := 0
	for part: Array in section.chords[index]:
		var chord: Array = score.chords[part[0]]
		var root := bass_root(chord)
		var length := int(part[1])
		if role != "main" or second:
			for n: int in chord:
				_add("harmony", start + step, length, SLOW_STRINGS, n + (0 if role == "contrast" else 12), 70, 0.24, 0.0, 0.35)
		for s in range(step, step + length):
			var at := start + s
			if role == "contrast":
				_contrast_step(at, s, index, chord, root, section)
				continue
			if s % 2 == 0:
				var note := root + (12 if s % 4 == 2 else 0)
				if s == 14 and next_root != root:
					note = next_root - 1 if next_root > root else next_root + 1
				_add("bass", at, 1.2, SYNTH_BASS, note, 110, 1.0)
			if s == 15:
				_add("bass", at, 0.6, SYNTH_BASS, root + 12, 90, 0.8)
			if role == "main":
				_ostinato(at, s, chord)
			else:
				_arp_side = -_arp_side
				var order := [0, 1, 2, 1, 0, 2, 1, 2]
				_add("harmony", at, 0.6, SQUARE, int(chord[order[s % 8] % chord.size()]) + 12, 85, 0.2, 0.6 * _arp_side, 0.15)
			var stab: bool = s in [0, 3, 6] and step == 0 and (opens_long(melody) or score.get("stabs", "") == "every_bar")
			if stab:
				for n: int in chord:
					_add("harmony", at, 1.6, BRASS, n - 12, 105, 0.28, 0.0, 0.25)
		step += length
	_groove(start, role, index == SECTION_BARS - 1, second)
	_climax(start, role, index, score.chords[section.chords[index][0][0]], melody)
	var first_chord: Array = score.chords[section.chords[index][0][0]]
	if index == 0:
		_orchestra_hit(start, first_chord, role == "main")
	if role == "contrast":
		if index == SECTION_BARS - 1:
			_timpani_roll(start + 8, 8, bass_root(first_chord) + 12)
		_line(start, melody, "trumpets")
		_line(start, _bar_line(section, "answer", index), "answer")
		_line(start, _bar_line(section, "horn", index), "horn")
	elif role == "main":
		_line(start, melody, "lead", score.leads)
		if second:
			_harmony(start, melody, score.scale)
		_line(start, _bar_line(section, "response", index), "trumpet")
	else:
		_line(start, melody, "trumpet lead")


## A section's optional line ("response", "answer", "horn") for one bar, or "" if it has none.
static func _bar_line(section: Dictionary, key: String, index: int) -> String:
	var lines: Array = section.get(key, [])
	return lines[index] if index < lines.size() else ""


func _contrast_step(at: int, s: int, index: int, chord: Array, root: int, section: Dictionary) -> void:
	if s % 2 == 0:
		_add("bass", at, 0.9, SYNTH_BASS, root + (7 if s % 8 == 6 else 0), 105, 0.9)
	var accent := s % 8 in [0, 3, 6]
	_add("harmony", at, 0.5, FAST_STRINGS, int(chord[0]) - 12 + (12 if s % 8 == 6 else 0), 105 if accent else 70, 0.45, -0.3, 0.2)
	if s in [0, 10]:
		for n: int in chord:
			_add("harmony", at, 3.0, BRASS, n, 95, 0.3, 0.0, 0.3)
	var rise: Array = section.get("rise", [])
	if index == SECTION_BARS - 1 and s >= 8 and s % 2 == 0 and (s - 8) / 2 < rise.size():
		var key: int = rise[(s - 8) / 2]
		_both("lead", at, 1.8, TRUMPET, key + 12, 105, 0.7, 0.2, 0.3)
		_add("harmony", at, 1.8, BRASS, key, 105, 0.5, -0.2, 0.3)


func _line(start: int, line: String, voice: String, leads: Array = []) -> void:
	if line.is_empty():
		return
	var s := 0
	for token in line.split(" "):
		var parts := token.split(":")
		var length := int(parts[1])
		if parts[0] != "r":
			var key := midi(parts[0])
			var at := start + s
			var held := length * 0.92
			match voice:
				"lead":
					for variant in 2:
						_add("lead_%d" % variant, at, held, int(leads[variant]), key, 95, 0.7, 0.0, 0.25, 0.22)
				"trumpet lead":
					_both("lead", at, held, TRUMPET, key, 105, 0.75, 0.0, 0.3, 0.12)
					_both("lead", at, held, FAST_STRINGS if length < 4 else SLOW_STRINGS, key - 12, 90, 0.4, -0.3, 0.3)
				"trumpet":
					_both("lead", at, held, TRUMPET, key - 12, 100, 0.6, 0.25, 0.3, 0.1)
				"trumpets":
					_both("lead", at, held, TRUMPET, key - 12, 105, 0.75, 0.2, 0.3, 0.1)
					_both("lead", at, held, BRASS, key - 24, 100, 0.45, -0.2, 0.3)
				"answer":
					var short := minf(held, 1.6)
					_both("lead", at, short, TRUMPET, key - 12, 110, 0.6, 0.35, 0.3)
					_both("lead", at, short, BRASS, key - 12, 105, 0.45, -0.35, 0.3)
				"horn":
					_both("lead", at, held, HORNS, key - 12, 95, 0.8, -0.4, 0.4)
		s += length


func _harmony(start: int, line: String, scale: Array) -> void:
	var s := 0
	for token in line.split(" "):
		var parts := token.split(":")
		var length := int(parts[1])
		if parts[0] != "r":
			_both("lead", start + s, length * 0.92, TRUMPET, third_below(midi(parts[0]), scale), 85, 0.35, 0.4, 0.3)
		s += length


## Drums for one bar, in both variants: 0 is a rock beat, 1 drives a kick on every beat
## with open hats on the off-beats. The contrast is half-time in both, building to a fill.
func _groove(start: int, role: String, fill: bool, second: bool) -> void:
	for variant in 2:
		var layer := ["drums_%d" % variant]
		for s in STEPS_PER_BAR:
			var at := start + s
			var jitter := _rng.randi_range(-8, 8)
			if role == "contrast":
				if s in ([0, 10] if variant == 0 else [0, 6, 10]) and not (fill and s >= 8):
					_drum(layer, at, KICK, 115, 0.9)
				if s == 8 and not fill:
					_drum(layer, at, SNARE, 110, 0.7)
				if not (fill and s >= 8):
					_drum(layer, at, HAT, (60 if s % 2 == 1 else 85) + jitter, 0.3, 0.3)
				if fill:
					_drum(layer, at, SNARE, 40 + 5 * s + jitter, 0.6)
					if s >= 8 and s % 2 == 0:
						_drum(layer, at, TOMS[2 + (s - 8) / 2], 105, 0.7, 0.2 - 0.075 * (s - 8))
				continue
			var kicks: Array
			if variant == 1:
				kicks = [0, 4, 8, 12]
			elif second:
				kicks = [0, 3, 6, 10] if role == "main" else [0, 6, 10, 14]
			else:
				kicks = [0, 6, 10]
			if s in kicks and not (fill and s >= 12):
				_drum(layer, at, KICK, 118, 0.9)
			if s in [4, 12]:
				_drum(layer, at, SNARE, 115, 0.7)
				if second and role == "main":
					_drum(layer, at, CLAP, 100, 0.4)
			if fill and s >= 12:
				_drum(layer, at, SNARE, 75 + 10 * (s - 12) + jitter, 0.6)
			if variant == 1:
				if s % 4 == 2:
					_drum(layer, at, OPEN_HAT, 85 + jitter, 0.3, 0.3)
			elif second and role == "lift":
				if s % 4 == 0:
					_drum(layer, at, RIDE, 90 + jitter, 0.35, 0.35)
			elif s % 2 == 0:
				_drum(layer, at, HAT, (75 if s % 4 == 0 else 95) + jitter, 0.3, 0.3)


## Overtime's extra intensity: 16th hats, timpani on the downbeat, a crash every four bars,
## and brass doubling the melody an octave down outside the contrast.
func _climax(start: int, role: String, index: int, chord: Array, melody: String) -> void:
	for s in STEPS_PER_BAR:
		_add("climax", start + s, 4.0, 0, HAT, [90, 55, 75, 55][s % 4] + _rng.randi_range(-6, 6), 0.3, 0.35, 0.15, 0.0, DRUMS)
	_add("climax", start, 3.0, TIMPANI, bass_root(chord) + 12, 115, 0.7, 0.0, 0.3)
	if index % 4 == 0:
		_add("climax", start, 4.0, 0, CRASH, 110, 0.5, 0.3, 0.3, 0.0, DRUMS)
	if role == "contrast" or melody.is_empty():
		return
	var s := 0
	for token in melody.split(" "):
		var parts := token.split(":")
		if parts[0] != "r":
			_add("climax", start + s, int(parts[1]) * 0.92, BRASS, midi(parts[0]) - 12, 100, 0.35, -0.2, 0.3)
		s += int(parts[1])


func _timpani_roll(step: int, steps: int, key: int) -> void:
	for s in steps:
		_add("harmony", step + s, 1.5, TIMPANI, key, 55 + int(65.0 * s / steps) + _rng.randi_range(-6, 6), 0.7, 0.0, 0.3)


func _orchestra_hit(step: int, chord: Array, big: bool) -> void:
	_add("harmony", step, 3.0, ORCH_HIT, int(chord[0]) + 12, 115, 0.45 if big else 0.3, 0.0, 0.4)
	_add("harmony", step, 4.0, TIMPANI, bass_root(chord) + 12, 120, 0.9, 0.0, 0.3)
	if big:
		_drum(["drums_0", "drums_1"], step, CRASH, 120, 0.6, -0.3, 0.3)
		for n: int in chord:
			_add("harmony", step, 2.0, BRASS, n + 12, 120, 0.25)
