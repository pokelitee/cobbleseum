class_name Rules
extends RefCounted
## Battle rules constants (concepts_brief.md §9). Starting values: batch simulation tunes them.
## Bump RULES_VERSION whenever a change alters battle outcomes; saved battle specs record it
## and won't replay under another.

const RULES_VERSION := 35
const TICK_RATE := 30
const LEVEL := 50
const IV := 31
const TIME_CAP_SECONDS := 90.0
## Overtime: from this point hits deal more damage, rising by OVERTIME_RAMP per second
## (x4 by the time cap), so slow matchups finish instead of timing out.
const OVERTIME_SECONDS := 60.0
const OVERTIME_RAMP := 0.1
## Multiplies the HP stat to set how long battles last (target 30-45 s).
const HP_MULTIPLIER := 19.0
## Team battles (§9.1): a side brings 1-MAX_TEAM Pokémon, one out at a time. After a knockout
## with more to come there's a lull of KNOCKOUT_LULL_SECONDS, then the next one is sent out at
## its side's start spot, taking SEND_OUT_SECONDS to land, shielded throughout. Until it lands
## the fighter left standing can only walk.
## Pace (§9.1): every fighter's HP is scaled by team_hp_factor() of the larger team's size, so a
## knockout comes faster the more there are to get through, and the overtime clock restarts at
## each send-out after a knockout, its overtime and cap scaled by the same factor.
const MAX_TEAM := 6
const KNOCKOUT_LULL_SECONDS := 2.0
const SEND_OUT_SECONDS := 1.0
const TEAM_HP_EXPONENT := 0.5
## Switching (§9.1): a fighter that could act can be recalled for a healthy bench member,
## which lands where it stood over SWITCH_SECONDS, open to hits and unable to act. Every
## send-out (a switch or the pick after a knockout) starts a side-wide SWITCH_COOLDOWN_SECONDS.
const SWITCH_SECONDS := 1.0
const SWITCH_COOLDOWN_SECONDS := 5.0
## Doubles (M17): two of each side's team of MIN_DOUBLES_TEAM-MAX_TEAM out at once, standing
## DOUBLES_SPREAD either side of their side's start spot. A spread move (an area move) that hits
## more than one fighter deals SPREAD_FACTOR to each, as in the main series.
const MIN_DOUBLES_TEAM := 2
const DOUBLES_SPREAD := 2.5
const SPREAD_FACTOR := 0.75
## Doubles' pace: every fighter's HP takes the team factor of a team this size, whatever the
## team's size (doubles_hp_factor()).
const DOUBLES_PACE_SIZE := 2
## Doubles' ally moves (§9.11): Helping Hand boosts the ally's next damaging move (if it comes
## within HELPING_HAND_SECONDS); Dragon Cheer raises its critical-hit chance for a while; Follow
## Me and Rage Powder draw every foe's attacks, and Wide Guard blocks spread moves on the side,
## each with a cooldown longer than it lasts.
const HELPING_HAND_FACTOR := 1.5
const HELPING_HAND_SECONDS := 4.0
const CHEER_CRIT_CHANCE := 1.0 / 8.0
const CHEER_SECONDS := 12.0
const REDIRECT_SECONDS := 4.0
const REDIRECT_COOLDOWN := 12.0
const WIDE_GUARD_SECONDS := 1.0
const WIDE_GUARD_COOLDOWN := 12.0

const ARENA_RADIUS := 14.0
## Terrain (§9.8): the most a fighter can step up (fliers more); projectiles leave and aim at
## CHEST_HEIGHT above the ground and hit within PROJECTILE_VERTICAL_REACH of it; melee and area
## moves only reach across height differences up to their limits.
const CLIMB := 0.5
const FLY_CLIMB := 1.5
const CHEST_HEIGHT := 0.8
const PROJECTILE_VERTICAL_REACH := 1.0
const MELEE_HEIGHT := 1.0
const AREA_HEIGHT := 1.5
const START_DISTANCE := 10.0
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
## Facing turns at a limited rate (degrees per second), faster while winding up (aiming).
## Walking, a fighter faces between the foe and where it's going (MOVE_FACING_WEIGHT is how
## much the walk counts at full speed), so it turns away to run and squares up to fight.
const TURN_RATE := 360.0
const AIM_TURN_RATE := 900.0
const MOVE_FACING_WEIGHT := 1.2
## Walking speeds up and slows down at this rate (m/s²); knockback slides out at the same rate.
const ACCELERATION := 14.0
## Agility scales acceleration and turning by body: the square root of the Speed stat over
## AGILITY_SPEED_STAT (a base-100 species at level 50), times (KNOCKBACK_REFERENCE_KG /
## weight) ^ AGILITY_WEIGHT_POWER, within AGILITY_LIMITS. Heavy, slow species lumber; light,
## fast ones dart.
const AGILITY_SPEED_STAT := 120.0
const AGILITY_WEIGHT_POWER := 0.15
const AGILITY_LIMITS := Vector2(0.6, 1.5)
## Flying types brake at this share of their acceleration, so they glide to a stop.
const GLIDE_BRAKING := 0.5
## A hit taking KNOCKBACK_FULL_SHARE of the defender's max HP (or more) knocks it back at
## KNOCKBACK_SPEED m/s, less for smaller hits; lighter species fly further, heavier less,
## by the square root of KNOCKBACK_REFERENCE_KG / weight within KNOCKBACK_WEIGHT_LIMITS.
const KNOCKBACK_SPEED := 5.0
const KNOCKBACK_FULL_SHARE := 0.08
const KNOCKBACK_REFERENCE_KG := 50.0
const KNOCKBACK_WEIGHT_LIMITS := Vector2(0.5, 1.5)

const DODGE_CHARGES := 2
const DODGE_DISTANCE := 2.5
const DODGE_SECONDS := 0.2
const DODGE_RECHARGE_SLOW := 3.0
const DODGE_RECHARGE_FAST := 1.5
## Feints (§9.2): a melee or area move's wind-up that breaks off, unreleased, with
## FEINT_BREAK_TICKS left. It spends no move cooldown, only the fighter's feint cooldown.
## Breaking off late enough draws a dodge from an AI that waits for a strike's last moments.
const FEINT_BREAK_TICKS := 3
const FEINT_COOLDOWN := 3.0

## Guarding (§9.2): a short parry against hits from within GUARD_ARC degrees of the facing. A
## blocked melee strike staggers the attacker for at least PARRY_STAGGER; a guard that blocked
## nothing ends in GUARD_RECOVERY. The cooldown runs from when the guard is raised.
const GUARD_SECONDS := 0.35
const GUARD_RECOVERY := 0.3
const GUARD_COOLDOWN := 3.0
const GUARD_ARC := 90.0
const PARRY_STAGGER := 0.5

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
## Heals are a channel: a long wind-up that any hit cancels (the cooldown is still spent), and
## they restore this share of the main-series amount. In real time a heal costs a fraction of
## a second rather than a turn, so a full-strength, uninterruptible Roost was worth close to
## an extra bar of HP.
const HEAL_WINDUP := 1.2
const HEAL_FACTOR := 0.5

## Arena conditions (§9.11): weather and surges last this long from a move or an ability, longer
## with the item that extends them (Damp Rock, Terrain Extender). A starting weather from the
## arena or spec lasts the battle.
const WEATHER_SECONDS := 20.0
const WEATHER_EXTENDED_SECONDS := 32.0
## An arena move cools down this long, longer than its condition lasts: casting one costs under
## a second, so with a status move's cooldown a weather stayed up all battle (a paired probe put
## carrying one at +23 points of win rate).
const ARENA_MOVE_COOLDOWN := 30.0
## Screens (Reflect, Light Screen, Aurora Veil) last SCREEN_SECONDS (longer with Light Clay),
## and their moves cool down for SCREEN_COOLDOWN, so a screen is up a little over half the time.
const SCREEN_SECONDS := 8.0
const SCREEN_EXTENDED_SECONDS := 13.0
const SCREEN_COOLDOWN := 14.0
## Entry hazards (§9.11) are cheap to lay and last until cleared, so their moves cool down for
## HAZARD_COOLDOWN between layers.
const HAZARD_COOLDOWN := 12.0
## Field and side conditions (§9.11, rules version 35): Trick Room, Gravity, the rooms, Safeguard
## and Mist last the main series' five turns read as weather is (FIELD_SECONDS), Tailwind its four;
## their moves cool down like the other arena moves (ARENA_MOVE_COOLDOWN). Court Change swaps the
## sides' conditions and cools down like a hazard; Haze like any status move.
const FIELD_SECONDS := 20.0
const TAILWIND_SECONDS := 16.0
## Trick Room mirrors a Speed stat within the band from the roster's slowest (a base-5 species) to
## SPEED_STAT_FOR_MAX, so the slowest walk, turn and recharge dodges like the fastest.
const SLOWEST_SPEED_STAT := 25.0

## Stat stages run from -6 to +6 with the main-series multipliers (§9.5). They wear off:
## every STAGE_DECAY_SECONDS without a change, each stage moves one step back toward 0.
const MAX_STAGE := 6
const STAGE_DECAY_SECONDS := 6.0

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
## The HP factor for team battles of `size` a side (at most): 1 for one-on-one.
static func team_hp_factor(size: int) -> float:
	return pow(maxf(size, 1.0), -TEAM_HP_EXPONENT)


## The HP factor for doubles of any team size: a team of two's. With two out a side, each
## fighter takes hits from two foes, so a knockout comes about as fast as in a singles team battle
## a size smaller; this keeps a 4v4 at about 90-120 s and a 6v6 at about 2.5-3 minutes.
static func doubles_hp_factor() -> float:
	return team_hp_factor(DOUBLES_PACE_SIZE)


static func overtime_factor(tick: int, overtime_seconds := OVERTIME_SECONDS) -> float:
	return 1.0 + OVERTIME_RAMP * maxf(0.0, tick / float(TICK_RATE) - overtime_seconds)


static func seconds_to_ticks(seconds: float) -> int:
	return maxi(1, roundi(seconds * TICK_RATE))


## Main-series stat formula at Rules.LEVEL with full IVs, no EVs and a neutral nature.
static func stat(base: int) -> int:
	return int((2 * base + IV) * LEVEL / 100.0) + 5


static func hp_stat(base: int) -> int:
	return int((2 * base + IV) * LEVEL / 100.0) + LEVEL + 10


static func agility(speed_stat: float, weight_kg: float) -> float:
	var value := sqrt(speed_stat / AGILITY_SPEED_STAT) * pow(KNOCKBACK_REFERENCE_KG / maxf(weight_kg, 0.1), AGILITY_WEIGHT_POWER)
	return clampf(value, AGILITY_LIMITS.x, AGILITY_LIMITS.y)


static func knockback_speed(damage_share: float, weight_kg: float) -> float:
	var weight_factor := clampf(sqrt(KNOCKBACK_REFERENCE_KG / maxf(weight_kg, 0.1)), KNOCKBACK_WEIGHT_LIMITS.x, KNOCKBACK_WEIGHT_LIMITS.y)
	return KNOCKBACK_SPEED * clampf(damage_share / KNOCKBACK_FULL_SHARE, 0.0, 1.0) * weight_factor


static func move_speed(speed_stat: float) -> float:
	return lerpf(MIN_MOVE_SPEED, MAX_MOVE_SPEED, clampf(speed_stat / SPEED_STAT_FOR_MAX, 0.0, 1.0))


## Seconds to recharge one dodge charge: faster for faster species.
static func dodge_recharge_seconds(speed_stat: float) -> float:
	return lerpf(DODGE_RECHARGE_SLOW, DODGE_RECHARGE_FAST, clampf(speed_stat / SPEED_STAT_FOR_MAX, 0.0, 1.0))


## A Speed stat as Trick Room reads it: mirrored within SLOWEST_SPEED_STAT-SPEED_STAT_FOR_MAX.
static func mirrored_speed(speed_stat: float) -> float:
	return SPEED_STAT_FOR_MAX + SLOWEST_SPEED_STAT - clampf(speed_stat, SLOWEST_SPEED_STAT, SPEED_STAT_FOR_MAX)


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
