class_name MusicRenderer
extends RefCounted
## Renders arranged notes (MusicArranger) through a SoundFont into one stereo buffer per layer,
## with an echo on the lead and a shared reverb, at RATE.
##
## A track's buffers run from the start of the intro to the end of its loop. Whatever rings
## past the loop's end (releases, echoes, reverb) is folded back onto the loop's start, so the
## loop repeats seamlessly; the first pass also hears it, faintly, over the intro's own tail.

const RATE := 48000
## Loudness of a track's default mix (drums, bass, harmony and lead variant 0), as RMS.
const TARGET_RMS_DB := -18.0
## The loudest any mix of layers, the climax included, may peak.
const PEAK := 0.95
const ECHO_FEEDBACK := 0.28
const ECHO_LEVEL := 0.22
const ECHO_SPREAD := 0.011
const REVERB_LEVEL := 0.3
## Comb and all-pass delays (samples at 44.1 kHz) of the Schroeder reverb.
const COMBS: Array[int] = [1557, 1617, 1491, 1422]
const ALL_PASSES: Array[int] = [556, 225]
const HIGH_PASS_HZ := 40.0
## Seconds rendered past the last note so its release and the reverb can ring out.
const TAIL := 3.0

var font: SoundFont
var _cache := {}


func _init(sound_font: SoundFont) -> void:
	font = sound_font
	font.rate = RATE


## Samples per 16th note at a tempo.
static func step_samples(bpm: float) -> float:
	return RATE * 15.0 / bpm


## Renders a looping track. Returns {"layers": {name: [left, right]}, "loop_begin": sample,
## "loop_end": sample}; every layer is loop_end samples long and shares one gain.
func render_track(arranged: Dictionary, bpm: float) -> Dictionary:
	var per_step := step_samples(bpm)
	var loop_begin := roundi(arranged.loop_start * per_step)
	var loop_end := roundi(arranged.loop_end * per_step)
	var layers := _render_layers(arranged.notes, per_step, loop_end + roundi(TAIL * RATE))
	for name: String in layers:
		layers[name] = _fold(layers[name], loop_begin, loop_end)
	_normalize(layers)
	return {"layers": layers, "loop_begin": loop_begin, "loop_end": loop_end}


## Renders a one-shot piece (the victory sting) into a single stereo buffer, ending once it
## has rung out.
func render_once(notes: Array, bpm: float, peak := 0.8) -> Array[PackedFloat32Array]:
	var per_step := step_samples(bpm)
	var last := 0.0
	for note: Dictionary in notes:
		last = maxf(last, note.step + note.length)
	var layers := _render_layers(notes, per_step, roundi(last * per_step) + roundi(TAIL * RATE))
	var mixed: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	for name: String in layers:
		mixed = _sum(mixed, layers[name])
	_scale([mixed], peak / maxf(_peak(mixed), 1e-6))
	return mixed


## Writes a 16-bit stereo WAV file; returns an error message, or "".
static func write_wav(path: String, buffer: Array[PackedFloat32Array]) -> String:
	var count := buffer[0].size()
	var data := PackedByteArray()
	data.resize(count * 4)
	for i in count:
		data.encode_s16(i * 4, int(clampf(buffer[0][i], -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(buffer[1][i], -1.0, 1.0) * 32767.0))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data.size())
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)  # PCM
	file.store_16(2)
	file.store_32(RATE)
	file.store_32(RATE * 4)
	file.store_16(4)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data.size())
	file.store_buffer(data)
	file.close()
	return ""


func _render_layers(notes: Array, per_step: float, length: int) -> Dictionary:
	var dry := {}
	var reverb := {}
	var echo := {}
	for note: Dictionary in notes:
		var layer: String = note.layer
		if not dry.has(layer):
			dry[layer] = _silence(length)
			reverb[layer] = PackedFloat32Array()
			reverb[layer].resize(length)
			echo[layer] = PackedFloat32Array()
			echo[layer].resize(length)
		var rendered := _note(note, per_step)
		var start := roundi(note.step * per_step)
		var left: float = note.gain * (1.0 - maxf(0.0, note.pan))
		var right: float = note.gain * (1.0 + minf(0.0, note.pan))
		var out: Array = dry[layer]
		var count := mini(rendered[0].size(), length - start)
		for i in count:
			var l: float = rendered[0][i] * left
			var r: float = rendered[1][i] * right
			out[0][start + i] += l
			out[1][start + i] += r
			var mono := (l + r) * 0.5
			reverb[layer][start + i] += mono * note.reverb
			echo[layer][start + i] += mono * note.echo
	for layer: String in dry:
		_add_echo(dry[layer], echo[layer], per_step)
		_add_reverb(dry[layer], reverb[layer])
		for channel in 2:
			dry[layer][channel] = _high_pass(_high_pass(dry[layer][channel]))
	return dry


## A note's samples, rendered once per distinct sound and reused.
func _note(note: Dictionary, per_step: float) -> Array[PackedFloat32Array]:
	var seconds: float = note.length * per_step / RATE
	var key := "%d|%d|%d|%d|%d" % [note.bank, note.program, note.key, note.velocity, roundi(seconds * 1000.0)]
	if not _cache.has(key):
		_cache[key] = font.note(note.bank, note.program, note.key, note.velocity, seconds)
	return _cache[key]


func _add_echo(out: Array, send: PackedFloat32Array, per_step: float) -> void:
	var delay := roundi(per_step * 3.0)  # a dotted 8th
	for i in range(delay, send.size()):
		send[i] += send[i - delay] * ECHO_FEEDBACK
	var spread := roundi(ECHO_SPREAD * RATE)
	for i in range(delay, send.size()):
		out[0][i] += send[i - delay] * ECHO_LEVEL
		if i - delay - spread >= 0:
			out[1][i] += send[i - delay - spread] * ECHO_LEVEL


func _add_reverb(out: Array, send: PackedFloat32Array) -> void:
	for channel in 2:
		var wet := PackedFloat32Array()
		wet.resize(send.size())
		for comb in COMBS:
			var size := int((comb + channel * 37) * RATE / 44100.0)
			var line := PackedFloat32Array()
			line.resize(size)
			var k := 0
			var damped := 0.0
			for i in send.size():
				var delayed := line[k]
				damped = delayed * 0.7 + damped * 0.3
				line[k] = send[i] + damped * 0.8
				k = (k + 1) % size
				wet[i] += delayed * 0.25
		for pass_delay in ALL_PASSES:
			var size := int((pass_delay + channel * 23) * RATE / 44100.0)
			var line := PackedFloat32Array()
			line.resize(size)
			var k := 0
			for i in wet.size():
				var delayed := line[k]
				var x := wet[i]
				line[k] = x + delayed * 0.5
				wet[i] = delayed - x
				k = (k + 1) % size
		var target: PackedFloat32Array = out[channel]
		for i in target.size():
			target[i] += wet[i] * REVERB_LEVEL
		out[channel] = target


static func _high_pass(buffer: PackedFloat32Array) -> PackedFloat32Array:
	var k := exp(-TAU * HIGH_PASS_HZ / RATE)
	var previous_in := 0.0
	var previous_out := 0.0
	for i in buffer.size():
		var x := buffer[i]
		previous_out = k * (previous_out + x - previous_in)
		previous_in = x
		buffer[i] = previous_out
	return buffer


static func _fold(buffer: Array, loop_begin: int, loop_end: int) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	for channel in 2:
		var samples: PackedFloat32Array = buffer[channel]
		var loop_length := loop_end - loop_begin
		for i in range(loop_end, samples.size()):
			samples[loop_begin + (i - loop_end) % loop_length] += samples[i]
		samples.resize(loop_end)
		out.append(samples)
	return out


## Scales every layer by one gain: the default mix to TARGET_RMS_DB, unless some mix of
## variants and the climax would then peak above PEAK.
static func _normalize(layers: Dictionary) -> void:
	var default := _sum(_sum(_sum(layers.drums_0, layers.bass), layers.harmony), layers.lead_0)
	var rms := _rms(default)
	var gain := db_to_linear(TARGET_RMS_DB) / maxf(rms, 1e-6)
	var loudest := 0.0
	for drums in ["drums_0", "drums_1"]:
		for lead in ["lead_0", "lead_1"]:
			var mix := _sum(_sum(_sum(_sum(layers[drums], layers.bass), layers.harmony), layers[lead]), layers.climax)
			loudest = maxf(loudest, _peak(mix))
	gain = minf(gain, PEAK / maxf(loudest, 1e-6))
	_scale(layers.values(), gain)


static func _silence(length: int) -> Array[PackedFloat32Array]:
	var left := PackedFloat32Array()
	left.resize(length)
	var right := PackedFloat32Array()
	right.resize(length)
	return [left, right]


static func _sum(a: Array, b: Array) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	for channel in 2:
		var x: PackedFloat32Array = a[channel].duplicate()
		var y: PackedFloat32Array = b[channel]
		if y.size() > x.size():
			x.resize(y.size())
		for i in y.size():
			x[i] += y[i]
		out.append(x)
	return out


static func _rms(buffer: Array) -> float:
	var total := 0.0
	var count := 0
	for channel in 2:
		for x: float in buffer[channel]:
			total += x * x
		count += buffer[channel].size()
	return sqrt(total / maxi(count, 1))


static func _peak(buffer: Array) -> float:
	var peak := 0.0
	for channel in 2:
		for x: float in buffer[channel]:
			peak = maxf(peak, absf(x))
	return peak


static func _scale(buffers: Array, gain: float) -> void:
	for buffer: Array in buffers:
		for channel in 2:
			var samples: PackedFloat32Array = buffer[channel]
			for i in samples.size():
				samples[i] *= gain
			buffer[channel] = samples
