class_name TournamentRun
extends RefCounted
## A tournament watched in the window (concepts_brief.md §17, M19), from the setup screen or
## `godot --path . -- --tournament [options]`. The whole bracket is played headless first, in
## about a second, so every result is known; then the reel (Tournament.reel()) shows a bracket
## card before each match, each game in the battle view as a watched battle (its round on the
## intro card, no credits card), and the champion card, which ends with the credits and offers
## a rematch of the same tournament or the menu. Esc goes back to the menu at any point.

## Where the games' specs are written for the battle view to read.
const SPECS_DIR := "user://tournament"

static var tournament := {}
## The step of the reel on screen, -1 before the first.
static var step := -1
static var _reel: Array[Dictionary] = []


## Plays the tournament `args` describe (Tournament flags) and shows its first card. Returns ""
## or why it can't start.
static func launch(tree: SceneTree, args: PackedStringArray) -> String:
	var parsed := Tournament.parse(args)
	if parsed.has("error"):
		return parsed.error
	var unknown := Cli.unknown_option(parsed.rest, Tournament.KEYS, false)
	if not unknown.is_empty():
		return unknown
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		return loaded.error
	var made := seeded(parsed.options, loaded.data)
	if made.has("error"):
		return made.error
	var problem := Tournament.play(made.tournament, loaded.data)
	if not problem.is_empty():
		return problem
	print("\n".join(Tournament.describe(made.tournament) + Tournament.results(made.tournament)))
	start(tree, made.tournament)
	return ""


## The tournament `options` describe, drawn and seeded, after the same checks as the command
## line's: {"tournament"} or {"error"}. It seeds from --ranking, else the newest ranking under
## results/ (Tournament.find_ranking()), else by base stat total.
static func seeded(options: Dictionary, data: BattleData) -> Dictionary:
	if not options.ai in Cli.profiles() + ["stand_in"]:
		return {"error": Cli.unknown("AI profile", options.ai, Cli.profiles())}
	if not str(options.arena).is_empty() and not Arenas.all().has(options.arena):
		return {"error": Cli.unknown("arena", options.arena, Arenas.names())}
	var ranking := Tournament.load_ranking(options.ranking) if not str(options.ranking).is_empty() \
		else Tournament.find_ranking(ProjectSettings.globalize_path("res://results"), Controllers.DEFAULT_AI, Rules.RULES_VERSION)
	if ranking.has("error"):
		return ranking
	return Tournament.create(options, data, ranking)


static func start(tree: SceneTree, played: Dictionary) -> void:
	tournament = played
	_reel = Tournament.reel(played)
	restart(tree)


static func active() -> bool:
	return not tournament.is_empty()


static func stop() -> void:
	tournament = {}
	_reel.clear()
	step = -1


## Shows the tournament again from its first card.
static func restart(tree: SceneTree) -> void:
	step = -1
	advance(tree)


## The reel's step on screen ({} when none).
static func current() -> Dictionary:
	return _reel[step] if step >= 0 and step < _reel.size() else {}


## Moves on to the next card or game.
static func advance(tree: SceneTree) -> void:
	step = mini(step + 1, _reel.size() - 1)
	var next := current()
	if not next.has("game"):
		tree.change_scene_to_file(TournamentCard.SCENE)
		return
	var dir := ProjectSettings.globalize_path(SPECS_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("game.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(Tournament.spec_of(tournament, next.match, next.game)))
	file.close()
	BattleView.launch_args = PackedStringArray([path, "--no-credits",
		"--title=" + Tournament.game_title(tournament, next.match, next.game)])
	tree.change_scene_to_file(SetupScreen.VIEW_SCENE)
