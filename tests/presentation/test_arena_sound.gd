extends TestCase


func test_a_coliseum_murmurs_as_loud_as_it_is_full() -> void:
	var full := ArenaSound.bed_for(true, "grassland", 1.0)
	var half := ArenaSound.bed_for(true, "grassland", 0.5)
	assert_eq(full.file, ArenaSound.MURMUR.file)
	assert_almost_eq(full.db, ArenaSound.MURMUR.db, 0.001)
	assert_almost_eq(half.db, ArenaSound.MURMUR.db - 6.02, 0.01, "half the seats, 6 dB quieter")
	assert_eq(ArenaSound.bed_for(true, "grassland", 0.0), {}, "empty stands are silent")


func test_open_fields_play_their_own_ambience() -> void:
	for field: String in ArenaSound.FIELDS:
		assert_eq(ArenaSound.bed_for(false, field, 0.75).file, ArenaSound.FIELDS[field].file, field)
	assert_eq(ArenaSound.bed_for(false, "paved", 0.75), {}, "a field without ambience is quiet")


func test_every_field_and_recording_has_a_source() -> void:
	var sources: Dictionary = AssetPipeline.load_manifest("res://sources.json").sources
	var sounds: Array = [ArenaSound.MURMUR, ArenaSound.ROAR]
	sounds.append_array(ArenaSound.CHEERS)
	sounds.append_array(ArenaSound.FIELDS.values())
	for sound: Dictionary in sounds:
		assert_true(sources.has(sound.source), sound.source)
		assert_eq(sources[sound.source].extract, [sound.file], sound.source)
		assert_eq(sources[sound.source].version, "1", sound.source)
	for field: String in ArenaSound.FIELDS:
		assert_true(Terrain.FIELDS.has(field), field)


func test_cheers_follow_the_crowd() -> void:
	assert_almost_eq(ArenaSound.cheer_volume(-8.0, 1.0), -8.0, 0.001)
	assert_almost_eq(ArenaSound.cheer_volume(-8.0, 0.5), -14.02, 0.01)
	assert_true(ArenaSound.cheer_volume(-8.0, 0.0) < -50.0, "a calm crowd is near silent")


func test_missing_recordings_are_skipped() -> void:
	var sound := ArenaSound.new()
	sound.setup(true, "grassland", 1.0, TestFiles.fresh_dir("no_crowd"))
	sound.start()
	sound.cheer()
	sound.roar()
	sound.next_frame(1.0)
	assert_eq(sound.get_child_count(), 0)
	sound.free()
