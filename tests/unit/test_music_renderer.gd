extends TestCase


static func _buffer(values: Array) -> Array[PackedFloat32Array]:
	return [PackedFloat32Array(values), PackedFloat32Array(values)]


static func _sine(amplitude: float, hz: float, seconds := 1.0) -> Array[PackedFloat32Array]:
	var values := PackedFloat32Array()
	values.resize(roundi(seconds * MusicRenderer.RATE))
	for i in values.size():
		values[i] = amplitude * sin(TAU * hz * i / MusicRenderer.RATE)
	return [values, values.duplicate()]


func test_splice_keeps_the_intro_and_the_second_pass() -> void:
	var spliced := MusicRenderer.splice(_buffer([1, 2, 3, 4, 5, 6, 7, 8, 9]), 2, Vector2i(5, 8))
	assert_eq(spliced[0], PackedFloat32Array([1, 2, 6, 7, 8]))
	assert_eq(spliced[1], PackedFloat32Array([1, 2, 6, 7, 8]))


func test_loudness_weights_bass_down() -> void:
	var mid := MusicRenderer.loudness(_sine(0.1, 1000.0))
	var bass := MusicRenderer.loudness(_sine(0.1, 40.0))
	assert_true(mid - bass > 3.0, "the same level reads quieter in the bass: %.1f vs %.1f" % [mid, bass])


func test_normalize_brings_every_track_to_one_loudness() -> void:
	var results: Array[float] = []
	for amplitude in [0.02, 0.2]:
		var layers := {}
		for layer in MusicArranger.LAYERS:
			layers[layer] = _sine(amplitude if layer == "lead_0" else 0.0, 1000.0)
		MusicRenderer.normalize(layers)
		var mix: Array = layers.lead_0
		results.append(MusicRenderer.loudness(mix))
	assert_almost_eq(results[0], MusicRenderer.TARGET_LOUDNESS, 0.1)
	assert_almost_eq(results[1], MusicRenderer.TARGET_LOUDNESS, 0.1)


func test_normalize_never_lets_a_layer_clip() -> void:
	var layers := {}
	for layer in MusicArranger.LAYERS:
		layers[layer] = _sine(0.001, 1000.0)
	layers.drums_1 = _sine(0.5, 1000.0)
	MusicRenderer.normalize(layers)
	var peak := 0.0
	for x: float in layers.drums_1[0]:
		peak = maxf(peak, absf(x))
	assert_almost_eq(peak, MusicRenderer.LAYER_PEAK, 0.01)


func test_eq_bands_cut_where_they_say() -> void:
	var cut := _sine(0.5, 320.0)
	MusicRenderer._equalize(cut[0], [{"type": "peak", "hz": 320.0, "db": -6.0, "q": 1.0}])
	var peak := 0.0
	for i in range(MusicRenderer.RATE / 2, cut[0].size()):  # past the filter's settling
		peak = maxf(peak, absf(cut[0][i]))
	assert_almost_eq(linear_to_db(peak / 0.5), -6.0, 0.2)
