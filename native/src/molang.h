// Molang for Bedrock particle effects (concepts_brief.md §12.5, Cobblemon's move effects):
// the subset Cobblemon's particles use (numbers, arithmetic, comparisons, && || !, ?:,
// math.* calls, v./q./t. names, `name = value;` statements and `return`), compiled to bytecode
// for a small stack machine. Asset text is only ever parsed by this grammar, never run as code.
#pragma once

#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace snowstorm {

// Deterministic random numbers (PCG32), so renders match on every platform.
struct Rng {
	uint64_t state = 0x853c49e6748fea9bULL;
	uint64_t inc = 0xda3e39cb94b95bdbULL;

	void seed(uint64_t value);
	uint32_t next();
	// [0, 1)
	float unit();
	float range(float low, float high);
	int integer(int low, int high);
};

// Variable and query names of one effect, mapped to slots.
struct Names {
	std::map<std::string, int> v;
	std::map<std::string, int> q;

	int variable(const std::string &name);
	int query(const std::string &name);
};

enum class Op : uint8_t {
	CONST, LOAD_V, LOAD_Q, STORE_V, POP, RETURN,
	ADD, SUB, MUL, DIV, NEG,
	LT, LE, GT, GE, EQ, NE, AND, OR, NOT, SELECT,
	CALL,
};

enum class Fn : uint8_t {
	ABS, ACOS, ASIN, ATAN, ATAN2, CEIL, CLAMP, COS, DIE_ROLL, DIE_ROLL_INTEGER, EXP, FLOOR,
	HERMITE_BLEND, LERP, LERPROTATE, LN, MAX, MIN, MIN_ANGLE, MOD, POW, RANDOM, RANDOM_INTEGER,
	ROUND, SIN, SQRT, TRUNC,
};

struct Instr {
	Op op;
	uint8_t fn = 0;
	int slot = 0;
	float value = 0.0f;
};

struct Program {
	std::vector<Instr> code;
	bool is_constant = true;
	float constant = 0.0f;
	bool uses_random = false;
	// Whether the value can differ between particles of one emitter in one frame; set by the
	// effect once it knows which variables vary.
	bool per_particle = true;
	// Variable slots read (for that analysis) and written.
	std::vector<int> reads;
	std::vector<int> writes;
	// Empty when the text compiled; otherwise why it didn't (and the program yields 0).
	std::string error;

	float run(float *v, const float *q, Rng &rng) const;
};

// Compiles Molang text; names get slots in `names`.
Program compile(const std::string &text, Names &names);
Program constant(float value);

} // namespace snowstorm
