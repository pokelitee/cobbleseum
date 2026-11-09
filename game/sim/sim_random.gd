class_name SimRandom
extends RefCounted
## Deterministic random numbers for the simulation (concepts_brief.md §10): mulberry32,
## implemented with 32-bit arithmetic so results match the reference JavaScript version
## on every platform and never depend on Godot's own generator.

const MASK := 0xFFFFFFFF

var state: int


func _init(seed: int) -> void:
	state = seed & MASK


## A generator for one named stream (battle, AI side A, ...), derived from the battle seed
## so changing one stream's usage never shifts another's numbers.
static func stream(battle_seed: int, stream_id: int) -> SimRandom:
	var mixer := SimRandom.new(battle_seed ^ mul32(stream_id + 1, 0x9E3779B9))
	return SimRandom.new(mixer.next_u32())


## Next unsigned 32-bit value.
func next_u32() -> int:
	state = (state + 0x6D2B79F5) & MASK
	var t := mul32(state ^ (state >> 15), 1 | state)
	t = ((t + mul32(t ^ (t >> 7), 61 | t)) & MASK) ^ t
	return (t ^ (t >> 14)) & MASK


## Uniform float in [0, 1).
func next_float() -> float:
	return next_u32() / 4294967296.0


func range_float(low: float, high: float) -> float:
	return low + (high - low) * next_float()


## True with probability `chance` (0..1).
func chance(probability: float) -> bool:
	return next_float() < probability


## 32-bit multiply (like JavaScript's Math.imul, unsigned) without overflowing 64-bit ints.
static func mul32(a: int, b: int) -> int:
	a &= MASK
	b &= MASK
	var low := (a & 0xFFFF) * (b & 0xFFFF)
	var cross := ((a >> 16) * (b & 0xFFFF) + (a & 0xFFFF) * (b >> 16)) & 0xFFFF
	return (low + (cross << 16)) & MASK
