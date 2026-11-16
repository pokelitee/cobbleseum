extends RefCounted
## Build step for the GeneralUser GS source: renders the battle music (concepts_brief.md §12.5)
## from the original scores in tools/music/scores with the bank's instruments. Writes, per track,
## one WAV per layer (MusicArranger.LAYERS) into <track>/, the victory sting as victory.wav, and
## music.json, which BattleMusic reads: each track's title, tempo, loop points and layer files.
## Rendering takes a few minutes; it reruns only when a score or the music scripts change.

const BANK := "GeneralUser-GS.sf2"
const SCORES_DIR := "res://tools/music/scores"
const TRACKS: Array[String] = ["clash", "overdrive", "summit"]
const STING := "victory"
## Extra files whose changes invalidate the build stamp.
const DEPENDENCIES: Array[String] = [
	"res://tools/music/sound_font.gd",
	"res://tools/music/music_arranger.gd",
	"res://tools/music/music_renderer.gd",
	"res://tools/music/scores/clash.json",
	"res://tools/music/scores/overdrive.json",
	"res://tools/music/scores/summit.json",
	"res://tools/music/scores/victory.json",
]


func build(source_dir: String, out_dir: String) -> String:
	var font := SoundFont.new()
	var err := font.load_file(source_dir.path_join(BANK))
	if not err.is_empty():
		return err
	var renderer := MusicRenderer.new(font)
	var manifest := {"rate": MusicRenderer.RATE, "tracks": {}, "sting": STING + ".wav"}
	for id in TRACKS:
		var loaded := MusicArranger.load_score(SCORES_DIR.path_join(id + ".json"))
		if loaded.has("error"):
			return loaded.error
		var score: Dictionary = loaded.score
		var started := Time.get_ticks_msec()
		var track := renderer.render_track(MusicArranger.new().arrange(score), score.bpm, score.get("eq", []))
		var dir := out_dir.path_join(id)
		DirAccess.make_dir_recursive_absolute(dir)
		var files := {}
		for layer: String in track.layers:
			err = MusicRenderer.write_wav(dir.path_join(layer + ".wav"), track.layers[layer])
			if not err.is_empty():
				return err
			files[layer] = "%s/%s.wav" % [id, layer]
		manifest.tracks[id] = {"title": score.title, "bpm": score.bpm, "loop_begin": track.loop_begin,
			"loop_end": track.loop_end, "layers": files}
		print("  %s rendered in %.0f s" % [score.title, (Time.get_ticks_msec() - started) / 1000.0])
	var sting := MusicArranger.load_score(SCORES_DIR.path_join(STING + ".json"))
	if sting.has("error"):
		return sting.error
	var notes := MusicArranger.new().arrange_once(sting.score)
	err = MusicRenderer.write_wav(out_dir.path_join(STING + ".wav"), renderer.render_once(notes, sting.score.bpm))
	if not err.is_empty():
		return err
	var file := FileAccess.open(out_dir.path_join("music.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  "))
	file.close()
	return ""
