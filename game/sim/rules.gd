class_name Rules
extends RefCounted
## Battle rules constants (concepts_brief.md §9). Starting values: batch simulation tunes them.
## Bump RULES_VERSION whenever a change alters battle outcomes; it is part of every battle spec.

const RULES_VERSION := 5
const TICK_RATE := 30
const LEVEL := 50
const IV := 31
const TIME_CAP_SECONDS := 90.0
## Overtime: from this point hits deal more damage, rising by OVERTIME_RAMP per second
## (x4 by the time cap), so slow matchups finish instead of timing out.
const OVERTIME_SECONDS := 60.0
const OVERTIME_RAMP := 0.1
## Multiplies the HP stat to set how long battles last (target 30-45 s).
const HP_MULTIPLIER := 22.0

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

## Dodging (§9.2): a short dash with invulnerability, from a few charges that recharge
## faster with Speed.
const DODGE_CHARGES := 2
const DODGE_DISTANCE := 2.5
const DODGE_SECONDS := 0.2
const DODGE_RECHARGE_SLOW := 3.0
const DODGE_RECHARGE_FAST := 1.5

## Move timings in seconds, per move kind.
const MELEE_REACH := 1.2
## Melee moves can start from this gap; the attacker dashes in during the wind-up.
const MELEE_DASH_RANGE := 3.0
const MELEE_DASH_SPEED := 10.0
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
## Area moves hit the opponent within this gap of the user when they release.
const AREA_RADIUS := 3.0
const AREA_WINDUP := 0.45
const AREA_RECOVERY := 0.4
## Multi-hit moves strike this far apart. Moves that hit 2-5 times roll the count with
## the main-series weights (2 and 3 hits 35% each, 4 and 5 hits 15% each).
const MULTI_HIT_INTERVAL := 0.12
const MULTI_HIT_WEIGHTS: Array[float] = [0.35, 0.35, 0.15, 0.15]
## Fixed-damage moves (Seismic Toss) cool down like a move of this power.
const FIXED_DAMAGE_POWER := 80
## Charge moves wind up longer; recharge moves recover longer.
const CHARGE_EXTRA := 0.9
const RECHARGE_EXTRA := 1.0

## Status-category moves (buffs, debuffs, heals, status): timings and a long base cooldown
## so they can't be chained.
const STATUS_MOVE_WINDUP := 0.4
const STATUS_MOVE_RECOVERY := 0.4
const STATUS_MOVE_COOLDOWN := 6.0

## Stat stages run from -6 to +6 with the main-series multipliers (§9.5).
const MAX_STAGE := 6

## Status conditions (§9.5). Damage over time is a share of max HP each second.
const STATUS_SECONDS := 12.0
const BURN_DAMAGE := 1.0 / 80.0
const POISON_DAMAGE := 1.0 / 64.0
## Bad poison deals this share times its level each second, the level rising every second.
const TOXIC_STEP := 1.0 / 320.0
## Burn halves physical damage dealt.
const BURN_ATTACK_FACTOR := 0.5
## Paralysis halves movement speed and sometimes stuns, rolled once a second.
const PARALYSIS_SPEED_FACTOR := 0.5
const PARALYSIS_STUN_CHANCE := 0.25
const PARALYSIS_STUN_SECONDS := 0.5
const SLEEP_MIN_SECONDS := 1.5
const SLEEP_MAX_SECONDS := 3.0
const FREEZE_SECONDS := 1.5
const CONFUSION_SECONDS := 6.0
const CONFUSION_CHANCE := 1.0 / 3.0
const CONFUSION_POWER := 40
const CONFUSION_RECOVERY := 0.5
## Types that can't get a status.
const STATUS_IMMUNITIES := {"brn": ["Fire"], "par": ["Electric"], "psn": ["Poison", "Steel"],
	"tox": ["Poison", "Steel"], "frz": ["Ice"]}

## Cooldown = base + power / power_divisor + pp_factor / PP: strong, scarce moves recharge slowly.
const COOLDOWN_BASE := 0.6
const COOLDOWN_POWER_DIVISOR := 60.0
const COOLDOWN_PP_FACTOR := 12.0


## Damage multiplier at a tick: 1 until overtime, then rising.
static func overtime_factor(tick: int) -> float:
	return 1.0 + OVERTIME_RAMP * maxf(0.0, tick / float(TICK_RATE) - OVERTIME_SECONDS)


static func seconds_to_ticks(seconds: float) -> int:
	return maxi(1, roundi(seconds * TICK_RATE))


## Main-series stat formula at Rules.LEVEL with full IVs, no EVs and a neutral nature.
static func stat(base: int) -> int:
	return int((2 * base + IV) * LEVEL / 100.0) + 5


static func hp_stat(base: int) -> int:
	return int((2 * base + IV) * LEVEL / 100.0) + LEVEL + 10


static func move_speed(speed_stat: int) -> float:
	return lerpf(MIN_MOVE_SPEED, MAX_MOVE_SPEED, clampf(speed_stat / SPEED_STAT_FOR_MAX, 0.0, 1.0))


## Seconds to recharge one dodge charge: faster for faster species.
static func dodge_recharge_seconds(speed_stat: int) -> float:
	return lerpf(DODGE_RECHARGE_SLOW, DODGE_RECHARGE_FAST, clampf(speed_stat / SPEED_STAT_FOR_MAX, 0.0, 1.0))


static func status_move_cooldown_seconds(pp: int) -> float:
	return STATUS_MOVE_COOLDOWN + COOLDOWN_PP_FACTOR / maxf(pp, 1.0)


## Main-series stat stage multiplier: +1 is x1.5, +2 is x2, -1 is x2/3, ...
static func stage_multiplier(stage: int) -> float:
	var clamped := clampi(stage, -MAX_STAGE, MAX_STAGE)
	return (2.0 + clamped) / 2.0 if clamped >= 0 else 2.0 / (2.0 - clamped)


static func cooldown_seconds(power: int, pp: int) -> float:
	return COOLDOWN_BASE + power / COOLDOWN_POWER_DIVISOR + COOLDOWN_PP_FACTOR / maxf(pp, 1.0)


static func projectile_speed(accuracy: Variant) -> float:
	var hit_chance := 1.0 if accuracy is bool else clampf(float(accuracy) / 100.0, 0.5, 1.0)
	return lerpf(PROJECTILE_MIN_SPEED, PROJECTILE_MAX_SPEED, (hit_chance - 0.5) / 0.5)


static func compressed_effectiveness(main_series: float) -> float:
	return TYPE_MULTIPLIERS.get(main_series, 1.0)
