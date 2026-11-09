extends SceneTree
## Records a battle as video clips (concepts_brief.md §12).
## Usage: godot --headless --path . --script res://tools/record.gd -- <spec.json>
##        [--seconds=10] [--format=vertical|landscape|both]
##
## 1. Runs the battle headless to find where it ends and its checksum.
## 2. For each format, launches a second Godot with Movie Maker on the battle view, skipping
##    ahead so the clip covers the last --seconds (ending TAIL_SECONDS after the knockout),
##    and checking the rendered battle's checksum against the headless one.
## 3. Encodes H.264 MP4 with ffmpeg as clip_<format>.mp4 and writes battle.json and
##    credits.txt beside it in recordings/<date>_<a>-vs-<b>_<seed>/.

const VIEW_SCENE := "res://game/presentation/battle_view.tscn"
const TAIL_SECONDS := 2.0
const DEFAULT_SECONDS := 10.0
const SAFETY_FRAMES := 300
const DEFAULT_FORMAT := "vertical"
## Godot reads this file from the project folder at startup (see VideoFormat.override_config).
const OVERRIDE_FILE := "res://override.cfg"
const CREDITS := """Pokémon models, textures and animations: Cobblemon (https://cobblemon.com),
licensed CC BY-NC 3.0. Non-commercial use only.
Battle data: Pokémon Showdown (MIT).
Pokémon and Pokémon character names are trademarks of Nintendo, Creatures Inc. and GAME FREAK.
Made with Cobbleseum, an unaffiliated fan project.
"""


func _initialize() -> void:
	var spec_path := ""
	var seconds := DEFAULT_SECONDS
	var format := DEFAULT_FORMAT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			seconds = maxf(1.0, arg.get_slice("=", 1).to_float())
		elif arg.begins_with("--format="):
			format = arg.get_slice("=", 1)
		else:
			spec_path = arg
	if spec_path.is_empty():
		return _fail("usage: -- <spec.json> [--seconds=10] [--format=vertical|landscape|both]")
	var formats: Array = VideoFormat.SIZES.keys() if format == "both" else [format]
	if not VideoFormat.SIZES.has(formats[0]):
		return _fail("unknown format '%s' (use vertical, landscape or both)" % format)
	if FileAccess.file_exists(OVERRIDE_FILE):
		return _fail("%s exists, perhaps left by an interrupted recording; delete it and retry" % ProjectSettings.globalize_path(OVERRIDE_FILE))
	spec_path = ProjectSettings.globalize_path(spec_path) if spec_path.begins_with("res://") else spec_path
	var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(spec_path))
	if not spec is Dictionary:
		return _fail("cannot read battle spec %s" % spec_path)
	var loaded := BattleData.load_showdown()
	if loaded.has("error"):
		return _fail(loaded.error)
	if OS.execute("ffmpeg", ["-version"], [], true) != 0:
		return _fail("ffmpeg is needed to encode the clip; install it and put it on PATH")

	var created := Battle.create(spec, loaded.data, SimpleAI.pair(int(spec.seed)))
	if created.has("error"):
		return _fail(created.error)
	var battle: Battle = created.battle
	var end_tick := battle.run()
	var until_tick := end_tick + Rules.seconds_to_ticks(TAIL_SECONDS)
	var from_tick := maxi(0, until_tick - Rules.seconds_to_ticks(seconds))

	var names: PackedStringArray = []
	for entry: Dictionary in spec.fighters:
		names.append(str(entry.species))
	var recordings := ProjectSettings.globalize_path("res://recordings")
	_ensure_ignored(recordings)
	var out_dir := recordings.path_join("%s_%s_%d" % [Time.get_date_string_from_system(), "-vs-".join(names), int(spec.seed)])
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("battle: %s, checksum %s; clip ticks %d-%d" % [Battle.Result.keys()[battle.result], battle.checksum().left(12), from_tick, until_tick])
	for clip_format: String in formats:
		var err := _render(spec_path, clip_format, out_dir, from_tick, until_tick, battle.checksum())
		if not err.is_empty():
			return _fail(err)

	var record := {
		"spec": spec, "rules_version": Rules.RULES_VERSION, "result": Battle.Result.keys()[battle.result],
		"end_tick": end_tick, "clip_ticks": [from_tick, until_tick], "formats": formats, "checksum": battle.checksum(),
		"events": battle.events,
	}
	_write(out_dir.path_join("battle.json"), JSON.stringify(record, "  "))
	_write(out_dir.path_join("credits.txt"), CREDITS)
	print("wrote %s" % out_dir)
	quit(0)


## Renders one format to <out_dir>/clip_<format>.mp4. Returns an error message or "".
func _render(spec_path: String, format: String, out_dir: String, from_tick: int, until_tick: int, checksum: String) -> String:
	var movie := out_dir.path_join("clip_%s.ogv" % format)
	var clip := out_dir.path_join("clip_%s.mp4" % format)
	print("rendering %s..." % format)
	_write(OVERRIDE_FILE, VideoFormat.override_config(format))
	var output: Array = []
	# --quit-after is a safety net: if the view fails to load it would otherwise never exit.
	var status := OS.execute(OS.get_executable_path(), [
		"--path", ProjectSettings.globalize_path("res://"),
		"--write-movie", movie, "--fixed-fps", str(Rules.TICK_RATE),
		"--quit-after", str(until_tick - from_tick + SAFETY_FRAMES),
		VIEW_SCENE, "--",
		spec_path, "--from-tick=%d" % from_tick, "--until-tick=%d" % until_tick,
		"--expect-checksum=%s" % checksum,
	], output, true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OVERRIDE_FILE))
	var log := "".join(output)
	if status != 0 or not log.contains("%s %s" % [BattleView.CHECKSUM_OK, checksum]):
		DirAccess.remove_absolute(movie)
		return "rendering %s failed or didn't verify (exit %d):
%s" % [format, status, log.strip_edges().right(2000)]
	print("encoding %s..." % clip)
	output.clear()
	status = OS.execute("ffmpeg", ["-y", "-loglevel", "error", "-i", movie,
		"-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
		"-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", clip], output, true)
	DirAccess.remove_absolute(movie)
	if status != 0:
		return "ffmpeg failed:
%s" % "".join(output).strip_edges()
	return ""


## Recordings live inside the project folder, so keep the editor from importing them.
static func _ensure_ignored(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	if not FileAccess.file_exists(dir.path_join(".gdignore")):
		FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE).close()


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _fail(message: String) -> void:
	printerr("error: " + message)
	quit(1)
