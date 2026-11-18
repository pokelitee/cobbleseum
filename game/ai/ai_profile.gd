class_name AIProfile
extends Resource
## An AI profile: settings for UtilityAI (concepts_brief.md §11). Profiles live in
## game/ai/profiles/ as resources; rankings use "ranked" on both sides.

## Ticks behind the opponent's true state the AI sees it.
@export var reaction_delay_ticks := 6
## Ticks between full re-evaluations; between them the AI keeps its last choice.
@export var decision_interval_ticks := 3
## Chance a decision takes the second-best action instead of the best.
@export_range(0.0, 1.0) var mistake_chance := 0.05
## Chance of dodging a given incoming attack at all, rolled once per threat.
@export_range(0.0, 1.0) var dodge_chance := 0.6
## Chance of feinting when the chance comes up (the foe down to its last dodge charge, a
## melee or area move ready and in reach), rolled once per chance.
@export_range(0.0, 1.0) var feint_chance := 0.0
## Chance, per threat it may react to (its dodge roll succeeded), that raising a guard is also
## an option.
@export_range(0.0, 1.0) var guard_chance := 0.0
## Chance of switching when a bench member would do clearly better against the foe (team
## battles), rolled once per such chance.
@export_range(0.0, 1.0) var switch_chance := 0.0
