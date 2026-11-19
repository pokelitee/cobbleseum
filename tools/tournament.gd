extends SceneTree
## Tournaments (concepts_brief.md §17, M19): a single-elimination bracket seeded from the species
## ranking, played deterministically from its seed (Tournament).
## Usage: godot --headless --path . --script res://tools/tournament.gd -- [options] [--record]
## Headless, it plays the bracket in seconds, prints the seeding, every game and the champion,
## and writes the tournament to results/tournaments/. With --record it then renders the whole
## tournament as one video per format in recordings/<date>_tournament<size>_<seed>/: a bracket card
## before each match, each game's clip (its round on the intro card, checked against the
## headless checksum like tools/record.gd's), and the champion card with the credits. The games'
## specs are saved beside it in specs/, so any game can be recorded or replayed on its own.

const Record := preload("res://tools/record.gd")
const OPTIONS: Array[String] = ["record", "format", "seconds", "mesh-fx"]
## Frames a card may overrun before --quit-after stops it.
const SAFETY_FRAMES := 60
const HELP := """Plays a tournament: a single-elimination bracket seeded from the species ranking.

Usage: godot --headless --path . --script res://tools/tournament.gd -- [options]

%s

Recording:
  --record                 also renders it as one video in recordings/ (needs a display and
                           ffmpeg; a few minutes a game)
  --format=vertical        vertical (1080x1920), landscape (1920x1080) or both
  --seconds=10             about how long each game's clip is, before its replay and victory
  --mesh-fx                draws our mesh move styles instead of Cobblemon's effects

Without --record it plays headless and writes results/tournaments/<date>_tournament<size>_<seed>.json.
To watch one in the window: godot --path . -- --tournament [options]

%s"""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var handled := Cli.info(args, HELP % [Tournament.HELP, Cli.INFO_HELP])
	if handled >= 0:
		return quit(handled)
	var parsed := Tournament.parse(args)
	if parsed.has("error"):
		return _fail(parsed.error)
	var problem := Cli.unknown_option(parsed.rest, OPTIONS, false)
	if not problem.is_empty():
		return _fail(problem)
	var record := false
	var format := Record.DEFAULT_FORMAT
	var seconds := Record.DEFAULT_SECONDS
	var view_args: PackedStringArray = []
	for arg: String in parsed.rest:
		if arg == "--record":
			record = true
		elif arg.begins_with("--format="):
			format = arg.get_slice("=", 1)
		elif arg.begins_with("--seconds="):
			seconds = maxf(1.0, arg.get_slice("=", 1).to_float())
		elif arg == "--mesh-fx":
			view_args.append(arg)
		else:
			return _fail("unexpected argument %s (see --help)" % arg)
	var formats: Array = VideoFormat.SIZES.keys() if format == "both" else [format]
	if not VideoFormat.SIZES.has(formats[0]):
		return _fail(Cli.unknown("format", format, VideoFormat.SIZES.keys() + ["both"]) + " (use vertical, landscape or both)")
	if record:
		if FileAccess.file_exists(Record.OVERRIDE_FILE):
			return _fail("%s exists, perhaps left by an interrupted recording; delete it and retry" % ProjectSettings.globalize_path(Record.OVERRIDE_FILE))
		if OS.execute("ffmpeg", ["-version"], [], true) != 0:
			return _fail("ffmpeg is needed to encode the video; install it and put it on PATH")
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		return _fail(loaded.error)
	var started := Time.get_ticks_msec()
	var made := TournamentRun.seeded(parsed.options, loaded.data)
	if made.has("error"):
		return _fail(made.error)
	var tournament: Dictionary = made.tournament
	print("\n".join(Tournament.describe(tournament)))
	problem = Tournament.play(tournament, loaded.data, _print_game)
	if not problem.is_empty():
		return _fail(problem)
	print("\n".join(Tournament.results(tournament)))
	var games: int = tournament.matches.reduce(func(sum: int, bout: Dictionary) -> int: return sum + bout.games.size(), 0)
	print("%d games in %.1f s" % [games, (Time.get_ticks_msec() - started) / 1000.0])
	var name := "%s_tournament%d_%d" % [Time.get_date_string_from_system(), tournament.options.size, tournament.options.seed]
	if not record:
		var dir := ProjectSettings.globalize_path("res://results/tournaments")
		Record._ensure_ignored(dir.get_base_dir())
		DirAccess.make_dir_recursive_absolute(dir)
		Record._write(dir.path_join(name + ".json"), JSON.stringify(tournament, "  "))
		print("wrote %s" % dir.path_join(name + ".json"))
		return quit(0)
	var recordings := ProjectSettings.globalize_path("res://recordings")
	Record._ensure_ignored(recordings)
	var out_dir := recordings.path_join(name + ("_mesh" if view_args.has("--mesh-fx") else ""))
	var err := _record(tournament, out_dir, formats, seconds, view_args)
	if not err.is_empty():
		return _fail(err)
	print("wrote %s" % out_dir)
	quit(0)


## One line per game as the bracket is played.
func _print_game(tournament: Dictionary, bout: Dictionary, game: Dictionary) -> void:
	var names: Array = game.sides.map(func(i: int) -> String: return tournament.entrants[i].name)
	var title := Tournament.match_title(tournament.options.size, bout.round, bout.index)
	if tournament.options.best_of > 1 or bout.games.size() > 1:
		title += " · Game %d" % bout.games.size()
	print("  %s: %s vs %s, %s after %.1f s" % [title, names[0], names[1],
		"draw" if game.winner < 0 else tournament.entrants[game.winner].name + " wins", game.ticks / float(Rules.TICK_RATE)])


## Renders `tournament` in each of `formats` to <out_dir>/tournament_<format>.mp4, with
## tournament.json, the games' specs and credits.txt beside it. Returns "" or an error.
static func _record(tournament: Dictionary, out_dir: String, formats: Array, seconds: float, view_args: PackedStringArray) -> String:
	var specs := out_dir.path_join("specs")
	DirAccess.make_dir_recursive_absolute(specs)
	var path := out_dir.path_join("tournament.json")
	Record._write(path, JSON.stringify(tournament, "  "))
	var trainers: bool = tournament.entrants.any(func(e: Dictionary) -> bool: return e.has("trainer"))
	var move_effects := not view_args.has("--mesh-fx") and CobblemonMoveFX.available()
	var reel := Tournament.reel(tournament)
	for step: Dictionary in reel:
		if step.has("game"):
			Record._write(_spec_path(specs, step), JSON.stringify(Tournament.spec_of(tournament, step.match, step.game), "  "))
	for format: String in formats:
		var parts: Array = []
		for step: Dictionary in reel:
			var movie := out_dir.path_join("part_%s_%03d.ogv" % [format, parts.size()])
			print("rendering %s %d/%d..." % [format, parts.size() + 1, reel.size()])
			var problem := ""
			if step.has("game"):
				var game: Dictionary = tournament.matches[step.match].games[step.game]
				var rendered := Record.render_battle(PackedStringArray([_spec_path(specs, step)]), format, movie, seconds, game.checksum,
					PackedStringArray(["--no-credits", "--title=" + Tournament.game_title(tournament, step.match, step.game)]) + view_args)
				problem = rendered.get("error", "")
			else:
				problem = _render_card(path, step, format, movie, move_effects, trainers)
			if not problem.is_empty():
				for part: String in parts:
					DirAccess.remove_absolute(part)
				return problem
			parts.append(movie)
		var video := out_dir.path_join("tournament_%s.mp4" % format)
		print("encoding %s..." % video)
		var problem := Record.encode(parts, video)
		if not problem.is_empty():
			return problem
	Record._write(out_dir.path_join("credits.txt"), Record.credits(move_effects, trainers))
	return ""


static func _spec_path(specs: String, step: Dictionary) -> String:
	return specs.path_join("match%02d_game%d.json" % [step.match + 1, step.game + 1])


## Renders one card (a bracket card, or the champion's with the credits) to `movie`.
static func _render_card(path: String, step: Dictionary, format: String, movie: String, move_effects: bool, trainers: bool) -> String:
	var champion: bool = step.has("champion")
	var args := ["--tournament-file=" + path, "--card=" + ("champion" if champion else str(step.card))]
	if move_effects:
		args.append("--move-effects")
	if trainers:
		args.append("--trainers")
	var frames := TournamentCard.CHAMPION_FRAMES + TournamentCard.CREDITS_FRAMES if champion else TournamentCard.BRACKET_FRAMES
	var rendered := Record.render_movie(TournamentCard.SCENE, args, format, movie, frames + SAFETY_FRAMES)
	var log: String = rendered.log
	if rendered.status != 0 or log.contains("SCRIPT ERROR"):
		DirAccess.remove_absolute(movie)
		return "rendering the %s card failed (exit %d):\n%s" % ["champion" if champion else "bracket", rendered.status, log.strip_edges().right(2000)]
	return ""


func _fail(message: String) -> void:
	printerr("error: " + message)
	quit(1)
