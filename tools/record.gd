extends SceneTree
## Records a battle as video clips (concepts_brief.md §12).
## Usage: godot --headless --path . --script res://tools/record.gd -- <spec.json>
##        [--seconds=10] [--format=vertical|landscape|both] [--ai-debug]
## Instead of <spec.json>, --watch=<species> [--vs=] [--ai=] [--vs-ai=] [--seed=] (SpecFlags)
## describes an AI-against-AI battle.
## --ai-debug records the AI debug overlay on top (for reviewing AI behaviour, not posting).
##
## 1. Runs the battle headless to find where it ends and its checksum.
## 2. For each format, launches a second Godot with Movie Maker on the battle view. The view
##    plans the presentation (hit-stop, slow motion, camera shots), plays the most exciting
##    window of about --seconds (see Highlights; usually ending on the knockout), and checks
##    the rendered battle's checksum against the headless one.
## 3. Encodes H.264 MP4 with ffmpeg as clip_<format>.mp4 and writes battle.json and
##    credits.txt beside it in recordings/<date>_<a>-vs-<b>_<seed>/.

const VIEW_SCENE := "res://game/presentation/battle_view.tscn"
const DEFAULT_SECONDS := 10.0
const SAFETY_FRAMES := 300
const DEFAULT_FORMAT := "vertical"
## Godot reads this file from the project folder at startup (see VideoFormat.override_config).
const OVERRIDE_FILE := "res://override.cfg"

## The clip window the view reported: {"start": tick, "end": tick}.
var _window := {}
## Extra arguments passed through to the battle view.
var _view_args: PackedStringArray = []
const CREDITS := """Pokémon models, textures, animations and sounds: Cobblemon (https://cobblemon.com),
licensed CC BY-NC 3.0. Non-commercial use only.
Battle data: Pokémon Showdown (MIT).
Fonts: Lilita One and Nunito (SIL Open Font License 1.1).
Pokémon and Pokémon character names are trademarks of Nintendo, Creatures Inc. and GAME FREAK.
Made with Cobbleseum, an unaffiliated fan project.
"""


func _initialize() -> void:
	var spec_path := ""
	var seconds := DEFAULT_SECONDS
	var format := DEFAULT_FORMAT
	var parsed := SpecFlags.parse(OS.get_cmdline_user_args())
	var flag_spec := SpecFlags.to_spec(parsed.flags)
	if flag_spec.has("error"):
		return _fail(flag_spec.error)
	if not flag_spec.is_empty() and flag_spec.fighters[0].ai == "player":
		return _fail("--play needs a player; record its replay instead (recordings/replays/)")
	for arg: String in parsed.rest:
		if arg.begins_with("--seconds="):
			seconds = maxf(1.0, arg.get_slice("=", 1).to_float())
		elif arg.begins_with("--format="):
			format = arg.get_slice("=", 1)
		elif arg == "--ai-debug":
			_view_args.append(arg)
		else:
			spec_path = arg
	if spec_path.is_empty() and flag_spec.is_empty():
		return _fail("usage: -- <spec.json> | --watch=<species> [--vs=] [--ai=] [--vs-ai=] [--seed=]" +
			" [--seconds=10] [--format=vertical|landscape|both] [--ai-debug]")
	var formats: Array = VideoFormat.SIZES.keys() if format == "both" else [format]
	if not VideoFormat.SIZES.has(formats[0]):
		return _fail("unknown format '%s' (use vertical, landscape or both)" % format)
	if FileAccess.file_exists(OVERRIDE_FILE):
		return _fail("%s exists, perhaps left by an interrupted recording; delete it and retry" % ProjectSettings.globalize_path(OVERRIDE_FILE))
	spec_path = ProjectSettings.globalize_path(spec_path) if spec_path.begins_with("res://") else spec_path
	var spec: Variant = flag_spec if not flag_spec.is_empty() else JSON.parse_string(FileAccess.get_file_as_string(spec_path))
	if not spec is Dictionary:
		return _fail("cannot read battle spec %s" % spec_path)
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		return _fail(loaded.error)
	if OS.execute("ffmpeg", ["-version"], [], true) != 0:
		return _fail("ffmpeg is needed to encode the clip; install it and put it on PATH")

	var controllers := Controllers.for_spec(spec)
	if controllers.has("error"):
		return _fail(controllers.error)
	var created := Battle.create(spec, loaded.data, controllers.controllers)
	if created.has("error"):
		return _fail(created.error)
	var battle: Battle = created.battle
	var end_tick := battle.run()

	var names: PackedStringArray = []
	for entry: Dictionary in spec.fighters:
		names.append(str(entry.species))
	var recordings := ProjectSettings.globalize_path("res://recordings")
	_ensure_ignored(recordings)
	var out_dir := recordings.path_join("%s_%s_%d" % [Time.get_date_string_from_system(), "-vs-".join(names), int(spec.seed)])
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("battle: %s after %d ticks, checksum %s" % [Battle.Result.keys()[battle.result], end_tick, battle.checksum().left(12)])
	for clip_format: String in formats:
		# A battle from flags goes to the view as flags, its seed fixed so both runs match.
		var source := SpecFlags.from_spec(spec) if not flag_spec.is_empty() else PackedStringArray([spec_path])
		var err := _render(source, clip_format, out_dir, seconds, battle.checksum())
		if not err.is_empty():
			return _fail(err)

	var record := {
		"spec": spec, "rules_version": Rules.RULES_VERSION, "result": Battle.Result.keys()[battle.result],
		"end_tick": end_tick, "clip_seconds": seconds, "clip_window": _window, "formats": formats, "checksum": battle.checksum(),
		"events": battle.events,
	}
	_write(out_dir.path_join("battle.json"), JSON.stringify(record, "  "))
	_write(out_dir.path_join("credits.txt"), CREDITS)
	print("wrote %s" % out_dir)
	quit(0)


## Renders one format to <out_dir>/clip_<format>.mp4. Returns an error message or "".
func _render(source: PackedStringArray, format: String, out_dir: String, seconds: float, checksum: String) -> String:
	var movie := out_dir.path_join("clip_%s.ogv" % format)
	var clip := out_dir.path_join("clip_%s.mp4" % format)
	print("rendering %s..." % format)
	_write(OVERRIDE_FILE, VideoFormat.override_config(format))
	var output: Array = []
	# --quit-after is a safety net: if the view fails to load it would otherwise never exit.
	var status := OS.execute(OS.get_executable_path(), [
		"--path", ProjectSettings.globalize_path("res://"),
		"--write-movie", movie, "--fixed-fps", str(Rules.TICK_RATE),
		"--quit-after", str(roundi(seconds * Rules.TICK_RATE) + SAFETY_FRAMES),
		VIEW_SCENE, "--",
	] + Array(source) + [
		"--clip-seconds=%s" % seconds,
		"--expect-checksum=%s" % checksum,
	] + Array(_view_args), output, true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OVERRIDE_FILE))
	var log := "".join(output)
	var problem := render_problem(log, status, checksum)
	if not problem.is_empty():
		DirAccess.remove_absolute(movie)
		return "rendering %s %s (exit %d):
%s" % [format, problem, status, log.strip_edges().right(2000)]
	for line in log.split("
"):
		if line.begins_with(BattleView.CLIP_WINDOW + " "):
			_window = {"start": line.get_slice(" ", 1).to_int(), "end": line.get_slice(" ", 2).to_int()}
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


## Why a render can't be used, or "": it failed, didn't verify against the headless run's
## checksum, or logged a script error. GDScript errors don't stop the view, so a clip could
## otherwise look fine while effects silently broke.
static func render_problem(log: String, status: int, checksum: String) -> String:
	if status != 0:
		return "failed"
	if not log.contains("%s %s" % [BattleView.CHECKSUM_OK, checksum]):
		return "didn't verify"
	if log.contains("SCRIPT ERROR"):
		return "logged script errors"
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
