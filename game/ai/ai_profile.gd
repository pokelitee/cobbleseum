class_name AIProfile
extends Resource
## A difficulty profile for UtilityAI (concepts_brief.md §11). Profiles live in
## game/ai/profiles/ as resources; rankings use "ranked" on both sides.

## Ticks behind the opponent's true state the AI sees it.
@export var reaction_delay_ticks := 6
## Ticks between full re-evaluations; between them the AI keeps its last choice.
@export var decision_interval_ticks := 3
## Chance a decision takes the second-best action instead of the best.
@export_range(0.0, 1.0) var mistake_chance := 0.05
## Chance of dodging a given incoming attack at all, rolled once per threat.
@export_range(0.0, 1.0) var dodge_chance := 0.6
