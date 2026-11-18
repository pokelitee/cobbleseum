class_name Appearance
extends RefCounted
## How a fighter looks (concepts_brief.md §12.8): shiny or not, and in which cosmetic form.
## A battle spec's fighters may carry "shiny" (true or false) and "form" (one of the species'
## cosmetic forms in the roster, such as "east" or "female"; "" for its own look). Both are
## presentation only: the simulation never reads them, so they change neither the battle nor
## its checksum. A spec made from flags gets them rolled from its seed (roll_missing()); a
## fighter without them, as in specs saved before they existed, keeps its species' own colours
## and look.

## Random stream for the rolls, after the simulation's streams and the view's.
const STREAM := 103
## The main games' odds of a shiny, per fighter.
const SHINY_CHANCE := 1.0 / 4096.0
## The --form value for a species' own look.
const BASE_FORM := "base"
## Random stream for each side's trainer (team battles), after the looks' own.
const TRAINER_STREAM := 104
## A side's "trainer" for none.
const NO_TRAINER := "none"


## Fills in "shiny" and "form" for the fighters of `spec` that lack them, rolled from its seed.
## Each side always takes the same draws, so one fighter's species never changes the other's roll;
## team members roll by slot, both sides' first members first.
static func roll_missing(spec: Dictionary, roster: Dictionary) -> void:
	var random := SimRandom.stream(int(spec.seed), STREAM)
	for fighter: Dictionary in members(spec):
		var rolled := roll(random, roster.get(str(fighter.get("species", "")), {}))
		if not fighter.has("form"):
			fighter.form = rolled.form
		if not fighter.has("shiny"):
			fighter.shiny = rolled.shiny and not _look(roster.get(str(fighter.species), {}), fighter.form).get("shiny", "").is_empty()
	# Team battles get a trainer a side, a generic one from the seed unless the spec names one.
	var trainers := SimRandom.stream(int(spec.seed), TRAINER_STREAM)
	for side: Dictionary in spec.get("fighters", []):
		var pick: String = TrainerView.GENERIC[trainers.next_u32() % TrainerView.GENERIC.size()]
		if not side.has("trainer") and Battle.members_of(side).size() > 1:
			side.trainer = pick


## The trainer a side's spec entry names, or "" for none.
static func trainer_of(side: Dictionary) -> String:
	var id := str(side.get("trainer", ""))
	return "" if id == NO_TRAINER else id


## One fighter's roll for its roster `entry`: a cosmetic form, each of them (but the female
## model) as likely as the species' own look; if it keeps its own look, the female model at its
## chance; and shiny at SHINY_CHANCE. Returns {"form", "shiny"}.
static func roll(random: SimRandom, entry: Dictionary) -> Dictionary:
	var form_draw := random.next_float()
	var gender_draw := random.next_float()
	var shiny_draw := random.next_float()
	var forms: Dictionary = entry.get("forms", {})
	var ids: Array = forms.keys()
	ids.sort()
	var cosmetic := ids.filter(func(id: String) -> bool: return not forms[id].has("chance"))
	var pick := floori(form_draw * (cosmetic.size() + 1))
	var form: String = cosmetic[pick - 1] if pick > 0 else ""
	if form.is_empty():
		for id: String in ids:
			if forms[id].has("chance") and gender_draw < float(forms[id].chance):
				form = id
				break
	return {"form": form, "shiny": shiny_draw < SHINY_CHANCE}


## Every team member's spec entry, by slot and then side: both sides' first members, then
## their second, and so on.
static func members(spec: Dictionary) -> Array:
	var teams: Array = spec.get("fighters", []).map(func(entry: Dictionary) -> Array: return Battle.members_of(entry))
	var found: Array = []
	var size: int = teams.reduce(func(most: int, team: Array) -> int: return maxi(most, team.size()), 0)
	for slot in size:
		for team: Array in teams:
			if slot < team.size():
				found.append(team[slot])
	return found


## Why the fighters' forms can't be shown, or "": every "form" must be one of its species'.
static func check(spec: Dictionary, roster: Dictionary) -> String:
	for fighter: Dictionary in members(spec):
		var form := str(fighter.get("form", ""))
		var forms: Dictionary = roster.get(str(fighter.get("species", "")), {}).get("forms", {})
		if not form.is_empty() and not forms.has(form):
			var known: Array = forms.keys()
			known.sort()
			return "%s has no cosmetic form '%s' (%s)" % [fighter.get("species", ""), form,
				"it has: " + ", ".join(known) if not known.is_empty() else "it has none"]
	return ""


## What to draw for `fighter` (a spec entry) of roster `entry`: {"model" (a file in the models
## folder), "skin" (a shiny skin there, or ""), "shiny" (whether it shows as shiny), "warning"
## ("" or why it shows less than its spec asks)}. With `models_dir`, the files must be there too.
## A form or shiny that can't be shown falls back to the species' own look and colours, so a
## clip never shows a broken model.
static func resolve(entry: Dictionary, fighter: Dictionary, models_dir := "") -> Dictionary:
	var name: String = entry.get("name", fighter.get("species", ""))
	var form := str(fighter.get("form", ""))
	var look := _look(entry, form)
	var shown := {"model": str(entry.get("model", "")), "skin": "", "shiny": false, "warning": ""}
	if not form.is_empty():
		if _present(str(look.get("model", "")), models_dir):
			shown.model = look.model
		else:
			look = entry
			shown.warning = "%s's form '%s' isn't in the cache; it shows in its own look" % [name, form]
	if not fighter.get("shiny", false):
		return shown
	var shiny := str(look.get("shiny", ""))
	if not _present(shiny, models_dir):
		shown.warning = "%s has no shiny colours in the cache; it shows in its normal ones" % name
	elif shiny.ends_with(".scn"):
		shown.model = shiny
		shown.shiny = true
	else:
		shown.skin = shiny
		shown.shiny = true
	return shown


static func _present(file: String, models_dir: String) -> bool:
	return not file.is_empty() and (models_dir.is_empty() or ResourceLoader.exists(models_dir.path_join(file)))


static func _look(entry: Dictionary, form: String) -> Dictionary:
	return entry.get("forms", {}).get(form, entry) if not form.is_empty() else entry
