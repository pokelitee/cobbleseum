extends TestCase

## Outputs of the reference JavaScript mulberry32 (Math.imul-based) for these seeds.
const REFERENCE := {
	0: [1144304738, 1416247, 958946056, 627933444, 2007157716],
	1: [2693262067, 11749833, 2265367787, 4213581821, 4159151403],
	123456789: [1107202814, 4169434471, 3372958138, 885470128, 1301683845],
	4294967295: [3850105811, 813802916, 3073704848, 4054706436, 3630262831],
}


func test_matches_reference_outputs() -> void:
	for seed: int in REFERENCE:
		var rng := SimRandom.new(seed)
		var got: Array = []
		for i in 5:
			got.append(rng.next_u32())
		assert_eq(got, REFERENCE[seed], "seed %d" % seed)


func test_mul32_wraps_like_imul() -> void:
	assert_eq(SimRandom.mul32(0xFFFFFFFF, 0xFFFFFFFF), 1)
	assert_eq(SimRandom.mul32(0x10000, 0x10000), 0)
	assert_eq(SimRandom.mul32(12345, 6789), 83810205)


func test_streams_are_independent_and_repeatable() -> void:
	var a := SimRandom.stream(42, 0)
	var b := SimRandom.stream(42, 1)
	assert_true(a.next_u32() != b.next_u32())
	assert_eq(SimRandom.stream(42, 1).next_u32(), SimRandom.stream(42, 1).next_u32())


func test_float_helpers_stay_in_range() -> void:
	var rng := SimRandom.new(7)
	for i in 1000:
		var value := rng.range_float(0.85, 1.0)
		assert_true(value >= 0.85 and value < 1.0)
