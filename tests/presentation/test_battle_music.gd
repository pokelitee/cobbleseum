extends TestCase

const LOOP_BEGIN := 100
const LOOP_END := 400


## A rendered-music folder with two tiny tracks, each with two drum and lead variants.
func _music_dir() -> String:
	var dir := TestFiles.fresh_dir("battle_music")
	var silence: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	silence[0].resize(LOOP_END)
	silence[1].resize(LOOP_END)
	var tracks := {}
	for id in ["alpha", "beta"]:
		DirAccess.make_dir_recursive_absolute(dir.path_join(id))
		var layers := {}
		for layer in MusicArranger.LAYERS:
			assert_eq(MusicRenderer.write_wav(dir.path_join("%s/%s.wav" % [id, layer]), silence), "")
			layers[layer] = "%s/%s.wav" % [id, layer]
		tracks[id] = {"title": id, "bpm": 180.0, "loop_begin": LOOP_BEGIN, "loop_end": LOOP_END, "layers": layers}
	assert_eq(MusicRenderer.write_wav(dir.path_join("victory.wav"), silence), "")
	TestFiles.write_text(dir.path_join("music.json"), JSON.stringify({"rate": 48000, "tracks": tracks, "sting": "victory.wav"}))
	return dir


func _music(seed := 1) -> BattleMusic:
	var music := BattleMusic.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(music)
	assert_true(music.setup(SimRandom.stream(seed, 102), _music_dir()))
	return music


func _frames(music: BattleMusic, count: int) -> void:
	for i in count:
		music.next_frame()


func test_the_seed_picks_the_track_and_variants() -> void:
	var tracks := {"b": {"layers": {"drums_0": "", "drums_1": "", "lead_0": ""}}, "a": {"layers": {"drums_0": "", "lead_0": "", "lead_1": ""}}}
	var first := BattleMusic.choose(tracks, SimRandom.stream(7, 102))
	assert_eq(BattleMusic.choose(tracks, SimRandom.stream(7, 102)), first, "the same seed, the same music")
	var seen := {}
	for seed in 40:
		var choice := BattleMusic.choose(tracks, SimRandom.stream(seed, 102))
		seen[choice.track] = true
		var drums_count := 2 if choice.track == "b" else 1
		assert_true(choice.variants.drums < drums_count and choice.variants.lead < 3 - drums_count, str(choice))
	assert_eq(seen.size(), 2, "both tracks get picked")


func test_loops_after_the_intro() -> void:
	var music := _music()
	var stream: AudioStreamSynchronized = music._music.stream
	var layer: AudioStreamWAV = stream.get_sync_stream(0)
	assert_eq(layer.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(layer.loop_begin, LOOP_BEGIN)
	assert_eq(layer.loop_end, LOOP_END)
	assert_eq(stream.stream_count, 5, "drums, lead, bass, harmony and climax")
	music.free()


func test_fades_in_and_cuts_at_the_knockout() -> void:
	var music := _music()
	music.start()
	assert_eq(music.music_db(), BattleMusic.SILENT_DB)
	_frames(music, BattleMusic.FADE_IN_FRAMES)
	assert_eq(music.music_db(), 0.0)
	music.knockout()
	_frames(music, BattleMusic.CUT_FRAMES)
	assert_eq(music.music_db(), BattleMusic.SILENT_DB)
	music.free()


func test_overtime_brings_in_the_climax() -> void:
	var music := _music()
	music.start()
	assert_eq(music.climax_db(), BattleMusic.SILENT_DB)
	music.overtime()
	_frames(music, BattleMusic.CLIMAX_FRAMES)
	assert_eq(music.climax_db(), 0.0)
	music.free()


func test_the_sting_waits_for_its_delay() -> void:
	var music := _music()
	music.start()
	music.victory(5)
	_frames(music, 5)
	assert_false(music.sting_started())
	_frames(music, 1)
	assert_true(music.sting_started())
	music.free()


func test_fades_move_evenly_in_amplitude() -> void:
	assert_almost_eq(BattleMusic.fade_db(0.0, BattleMusic.SILENT_DB, 0.5), -6.02, 0.05, "halfway is half the amplitude")
	assert_almost_eq(BattleMusic.fade_db(BattleMusic.SILENT_DB, 0.0, 0.5), -6.02, 0.05)
	assert_eq(BattleMusic.fade_db(-12.0, 0.0, 1.0), 0.0)
	assert_eq(BattleMusic.fade_db(0.0, BattleMusic.SILENT_DB, 1.0), BattleMusic.SILENT_DB)


func test_the_credits_cancel_a_sting_still_waiting() -> void:
	var music := _music()
	music.start()
	music.victory(10)
	music.fade_out(60)
	_frames(music, 20)
	assert_false(music.sting_started())
	music.free()


func test_a_draw_fades_out() -> void:
	var music := _music()
	music.start()
	_frames(music, BattleMusic.FADE_IN_FRAMES)
	music.draw()
	_frames(music, BattleMusic.DRAW_FRAMES / 2)
	assert_true(music.music_db() < 0.0 and music.music_db() > BattleMusic.SILENT_DB, "halfway through the fade")
	_frames(music, BattleMusic.DRAW_FRAMES)
	assert_eq(music.music_db(), BattleMusic.SILENT_DB)
	music.free()


func test_without_rendered_music_every_cue_is_silent() -> void:
	var music := BattleMusic.new()
	assert_false(music.setup(SimRandom.stream(1, 102), TestFiles.fresh_dir("no_music")))
	music.start()
	music.overtime()
	music.knockout()
	music.victory()
	music.draw()
	_frames(music, 3)
	assert_eq(music.music_db(), BattleMusic.SILENT_DB)
	assert_false(music.sting_started())
	music.free()


func test_the_bus_layout_has_the_mix_buses() -> void:
	for bus in [BattleMusic.BUS, ArenaSound.BUS, BattleSound.BUS]:
		assert_true(AudioServer.get_bus_index(bus) > 0, "bus %s" % bus)
	var music := AudioServer.get_bus_index(BattleMusic.BUS)
	var duck: AudioEffectCompressor = AudioServer.get_bus_effect(music, 0)
	assert_eq(duck.sidechain, BattleSound.BUS, "the music ducks under the battle's sounds")
