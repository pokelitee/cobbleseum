class_name ParticleMath
extends RefCounted
## Molang's math.* functions for ParticleMolang (angles in degrees, as in Bedrock). Random
## functions draw from `rng`, which each particle emitter seeds, so renders match.

var rng := RandomNumberGenerator.new()


func m_abs(x: float) -> float: return absf(x)
func m_acos(x: float) -> float: return rad_to_deg(acos(x))
func m_asin(x: float) -> float: return rad_to_deg(asin(x))
func m_atan(x: float) -> float: return rad_to_deg(atan(x))
func m_atan2(y: float, x: float) -> float: return rad_to_deg(atan2(y, x))
func m_ceil(x: float) -> float: return ceilf(x)
func m_clamp(x: float, low: float, high: float) -> float: return clampf(x, low, high)
func m_cos(x: float) -> float: return cos(deg_to_rad(x))
func m_exp(x: float) -> float: return exp(x)
func m_floor(x: float) -> float: return floorf(x)
func m_hermite_blend(x: float) -> float: return 3.0 * x * x - 2.0 * x * x * x
func m_lerp(a: float, b: float, t: float) -> float: return lerpf(a, b, t)
func m_lerprotate(a: float, b: float, t: float) -> float: return a + wrapf(b - a, -180.0, 180.0) * t
func m_ln(x: float) -> float: return log(x)
func m_max(a: float, b: float) -> float: return maxf(a, b)
func m_min(a: float, b: float) -> float: return minf(a, b)
func m_min_angle(x: float) -> float: return wrapf(x, -180.0, 180.0)
func m_mod(a: float, b: float) -> float: return fmod(a, b) if b != 0.0 else 0.0
func m_pow(a: float, b: float) -> float: return pow(a, b)
func m_round(x: float) -> float: return roundf(x)
func m_sin(x: float) -> float: return sin(deg_to_rad(x))
func m_sqrt(x: float) -> float: return sqrt(maxf(x, 0.0))
func m_trunc(x: float) -> float: return float(int(x))


func m_lt(a: float, b: float) -> float: return 1.0 if a < b else 0.0
func m_le(a: float, b: float) -> float: return 1.0 if a <= b else 0.0
func m_gt(a: float, b: float) -> float: return 1.0 if a > b else 0.0
func m_ge(a: float, b: float) -> float: return 1.0 if a >= b else 0.0
func m_eq(a: float, b: float) -> float: return 1.0 if a == b else 0.0
func m_ne(a: float, b: float) -> float: return 1.0 if a != b else 0.0
func m_and(a: float, b: float) -> float: return 1.0 if a != 0.0 and b != 0.0 else 0.0
func m_or(a: float, b: float) -> float: return 1.0 if a != 0.0 or b != 0.0 else 0.0
func m_not(a: float) -> float: return 1.0 if a == 0.0 else 0.0
## Molang's ?:. Both branches are evaluated (Expression has no short circuit); harmless here,
## as particle Molang has no side effects beyond drawing random numbers.
func m_select(condition: float, yes: float, no: float) -> float: return yes if condition != 0.0 else no


func m_random(low: float, high: float) -> float:
	return rng.randf_range(low, high)


func m_random_integer(low: float, high: float) -> float:
	return float(rng.randi_range(roundi(low), roundi(high)))


func m_die_roll(count: float, low: float, high: float) -> float:
	var total := 0.0
	for i in maxi(0, roundi(count)):
		total += rng.randf_range(low, high)
	return total


func m_die_roll_integer(count: float, low: float, high: float) -> float:
	var total := 0.0
	for i in maxi(0, roundi(count)):
		total += rng.randi_range(roundi(low), roundi(high))
	return total
