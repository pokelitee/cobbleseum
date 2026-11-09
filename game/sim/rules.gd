class_name Rules
extends RefCounted
## Battle rules constants (concepts_brief.md §9). Starting values: batch simulation tunes them.
## Bump RULES_VERSION whenever a change alters battle outcomes; it is part of every battle spec.

const RULES_VERSION := 1
const TICK_RATE := 30
const LEVEL := 50
const IV := 31
const TIME_CAP_SECONDS := 90.0
## Multiplies the HP stat to set how long battles last (target 30-45 s).
const HP_MULTIPLIER := 8.0

const ARENA_RADIUS := 8.0
const START_DISTANCE := 8.0
## Movement speed in metres per second, mapped from the Speed stat.
const MIN_MOVE_SPEED := 2.0
const MAX_MOVE_SPEED := 5.0
const SPEED_STAT_FOR_MAX := 150.0

const STAB := 1.5
const CRIT_CHANCE := 1.0 / 24.0
const CRIT_MULTIPLIER := 1.5
const ROLL_MIN := 0.85
const ROLL_MAX := 1.0
## Main-series effectiveness -> Cobbleseum effectiveness (compressed so fights stay winnable).
const TYPE_MULTIPLIERS := {4.0: 1.6, 2.0: 1.3, 1.0: 1.0, 0.5: 0.8, 0.25: 0.6, 0.0: 0.25}

## Move timings in seconds, per move kind.
const MELEE_REACH := 1.2
const MELEE_WINDUP := 0.25
const MELEE_RECOVERY := 0.35
const PROJECTILE_RANGE := 7.0
const PROJECTILE_WINDUP := 0.35
const PROJECTILE_RECOVERY := 0.3
const PROJECTILE_RADIUS := 0.3
## Projectile speed in metres per second rises with move accuracy, so accurate moves are
## harder to sidestep.
const PROJECTILE_MIN_SPEED := 8.0
const PROJECTILE_MAX_SPEED := 16.0
## Priority moves wind up faster.
const PRIORITY_WINDUP_FACTOR := 0.5
## Cooldown = base + power / power_divisor + pp_factor / PP: strong, scarce moves recharge slowly.
const COOLDOWN_BASE := 0.6
const COOLDOWN_POWER_DIVISOR := 60.0
const COOLDOWN_PP_FACTOR := 12.0


static func seconds_to_ticks(seconds: float) -> int:
	return maxi(1, roundi(seconds * TICK_RATE))


## Main-series stat formula at Rules.LEVEL with full IVs, no EVs and a neutral nature.
static func stat(base: int) -> int:
	return int((2 * base + IV) * LEVEL / 100.0) + 5


static func hp_stat(base: int) -> int:
	return int((2 * base + IV) * LEVEL / 100.0) + LEVEL + 10


static func move_speed(speed_stat: int) -> float:
	return lerpf(MIN_MOVE_SPEED, MAX_MOVE_SPEED, clampf(speed_stat / SPEED_STAT_FOR_MAX, 0.0, 1.0))


static func cooldown_seconds(power: int, pp: int) -> float:
	return COOLDOWN_BASE + power / COOLDOWN_POWER_DIVISOR + COOLDOWN_PP_FACTOR / maxf(pp, 1.0)


static func projectile_speed(accuracy: Variant) -> float:
	var hit_chance := 1.0 if accuracy is bool else clampf(float(accuracy) / 100.0, 0.5, 1.0)
	return lerpf(PROJECTILE_MIN_SPEED, PROJECTILE_MAX_SPEED, (hit_chance - 0.5) / 0.5)


static func compressed_effectiveness(main_series: float) -> float:
	return TYPE_MULTIPLIERS.get(main_series, 1.0)
