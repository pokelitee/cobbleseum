#include "molang.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>

namespace snowstorm {

namespace {

const float PI_F = 3.14159265358979f;
const float DEG = PI_F / 180.0f;

struct FunctionInfo {
	const char *name;
	Fn fn;
	int arguments;
};

const FunctionInfo FUNCTIONS[] = {
	{ "abs", Fn::ABS, 1 }, { "acos", Fn::ACOS, 1 }, { "asin", Fn::ASIN, 1 }, { "atan", Fn::ATAN, 1 },
	{ "atan2", Fn::ATAN2, 2 }, { "ceil", Fn::CEIL, 1 }, { "clamp", Fn::CLAMP, 3 }, { "cos", Fn::COS, 1 },
	{ "die_roll", Fn::DIE_ROLL, 3 }, { "die_roll_integer", Fn::DIE_ROLL_INTEGER, 3 }, { "exp", Fn::EXP, 1 },
	{ "floor", Fn::FLOOR, 1 }, { "hermite_blend", Fn::HERMITE_BLEND, 1 }, { "lerp", Fn::LERP, 3 },
	{ "lerprotate", Fn::LERPROTATE, 3 }, { "ln", Fn::LN, 1 }, { "max", Fn::MAX, 2 }, { "min", Fn::MIN, 2 },
	{ "min_angle", Fn::MIN_ANGLE, 1 }, { "mod", Fn::MOD, 2 }, { "pow", Fn::POW, 2 }, { "random", Fn::RANDOM, 2 },
	{ "random_integer", Fn::RANDOM_INTEGER, 2 }, { "round", Fn::ROUND, 1 }, { "sin", Fn::SIN, 1 },
	{ "sqrt", Fn::SQRT, 1 }, { "trunc", Fn::TRUNC, 1 },
};

// Scopes of names: v (variables, also t./temp./c./context.) and q (queries).
char scope_of(const std::string &prefix) {
	if (prefix == "v" || prefix == "variable" || prefix == "t" || prefix == "temp" || prefix == "c" || prefix == "context") {
		return 'v';
	}
	if (prefix == "q" || prefix == "query") {
		return 'q';
	}
	return 0;
}

float wrap_angle(float x) {
	float r = std::fmod(x + 180.0f, 360.0f);
	if (r < 0.0f) {
		r += 360.0f;
	}
	return r - 180.0f;
}

struct Token {
	enum Kind { NUMBER, NAME, SYMBOL, END } kind = END;
	float number = 0.0f;
	std::string text;
};

class Parser {
public:
	Parser(const std::string &source, Names &names) : names(names) {
		tokenize(source);
	}

	Program parse() {
		Program program;
		if (!error.empty()) {
			return fail(program);
		}
		bool any = false;
		while (!at_end()) {
			if (is(";")) {
				position++;
				continue;
			}
			if (any) {
				out.push_back({ Op::POP });
			}
			any = true;
			bool returns = false;
			int target = -1;
			if (peek().kind == Token::NAME && peek().text == "return") {
				position++;
				returns = true;
			} else if (peek().kind == Token::NAME && peek(1).kind == Token::SYMBOL && peek(1).text == "=") {
				target = variable_slot(peek().text);
				if (target < 0) {
					error = "cannot assign to '" + peek().text + "'";
					return fail(program);
				}
				position += 2;
			}
			ternary();
			if (!error.empty()) {
				return fail(program);
			}
			if (!at_end() && !is(";")) {
				error = "unexpected '" + describe(peek()) + "'";
				return fail(program);
			}
			if (target >= 0) {
				out.push_back({ Op::STORE_V, 0, target });
				written.push_back(target);
			}
			if (returns) {
				out.push_back({ Op::RETURN });
			}
		}
		if (!any) {
			return constant(0.0f);
		}
		program.code = out;
		program.reads = read;
		program.writes = written;
		program.uses_random = random;
		program.is_constant = false;
		if (out.size() == 1 && out[0].op == Op::CONST) {
			program.is_constant = true;
			program.constant = out[0].value;
			program.code.clear();
		}
		return program;
	}

	std::string error;

private:
	Names &names;
	std::vector<Token> tokens;
	size_t position = 0;
	std::vector<Instr> out;
	std::vector<int> read;
	std::vector<int> written;
	bool random = false;

	Program fail(Program program) {
		program.error = error;
		program.is_constant = true;
		program.constant = 0.0f;
		program.code.clear();
		return program;
	}

	void tokenize(const std::string &raw) {
		std::string text = raw;
		std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) { return (char)std::tolower(c); });
		size_t i = 0;
		while (i < text.size()) {
			char c = text[i];
			std::string pair = text.substr(i, 2);
			if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
				i++;
			} else if (std::isdigit((unsigned char)c) || (c == '.' && i + 1 < text.size() && std::isdigit((unsigned char)text[i + 1]))) {
				size_t start = i;
				while (i < text.size() && (std::isdigit((unsigned char)text[i]) || text[i] == '.')) {
					i++;
				}
				Token token;
				token.kind = Token::NUMBER;
				token.number = std::strtof(text.substr(start, i - start).c_str(), nullptr);
				tokens.push_back(token);
			} else if (c == '_' || (c >= 'a' && c <= 'z')) {
				size_t start = i;
				while (i < text.size() && (text[i] == '_' || text[i] == '.' || std::isdigit((unsigned char)text[i]) || (text[i] >= 'a' && text[i] <= 'z'))) {
					i++;
				}
				Token token;
				token.kind = Token::NAME;
				token.text = text.substr(start, i - start);
				tokens.push_back(token);
			} else if (pair == "<=" || pair == ">=" || pair == "==" || pair == "!=" || pair == "&&" || pair == "||") {
				tokens.push_back({ Token::SYMBOL, 0.0f, pair });
				i += 2;
			} else if (std::string("+-*/(),!<>?:;=").find(c) != std::string::npos) {
				tokens.push_back({ Token::SYMBOL, 0.0f, std::string(1, c) });
				i++;
			} else {
				error = std::string("unsupported character '") + c + "'";
				return;
			}
		}
	}

	const Token &peek(size_t offset = 0) const {
		static const Token end;
		return position + offset < tokens.size() ? tokens[position + offset] : end;
	}

	bool at_end() const {
		return position >= tokens.size();
	}

	bool is(const char *symbol) const {
		return peek().kind == Token::SYMBOL && peek().text == symbol;
	}

	static std::string describe(const Token &token) {
		if (token.kind == Token::NUMBER) {
			return std::to_string(token.number);
		}
		return token.kind == Token::END ? std::string("end") : token.text;
	}

	// The v slot for an assignable name, or -1.
	int variable_slot(const std::string &name) {
		size_t dot = name.find('.');
		if (dot == std::string::npos || scope_of(name.substr(0, dot)) != 'v') {
			return -1;
		}
		std::string member = name.substr(dot + 1);
		if (member.empty() || member.find('.') != std::string::npos) {
			return -1;
		}
		return names.variable(member);
	}

	void ternary() {
		logical_or();
		if (!is("?")) {
			return;
		}
		position++;
		ternary();
		if (!is(":")) {
			error = "expected ':'";
			return;
		}
		position++;
		ternary();
		out.push_back({ Op::SELECT });
	}

	void logical_or() {
		logical_and();
		while (is("||")) {
			position++;
			logical_and();
			out.push_back({ Op::OR });
		}
	}

	void logical_and() {
		comparison();
		while (is("&&")) {
			position++;
			comparison();
			out.push_back({ Op::AND });
		}
	}

	void comparison() {
		additive();
		static const std::pair<const char *, Op> OPS[] = {
			{ "<", Op::LT }, { "<=", Op::LE }, { ">", Op::GT }, { ">=", Op::GE }, { "==", Op::EQ }, { "!=", Op::NE },
		};
		for (const auto &entry : OPS) {
			if (is(entry.first)) {
				position++;
				additive();
				out.push_back({ entry.second });
				return;
			}
		}
	}

	void additive() {
		term();
		while (is("+") || is("-")) {
			Op op = is("+") ? Op::ADD : Op::SUB;
			position++;
			term();
			out.push_back({ op });
		}
	}

	void term() {
		unary();
		while (is("*") || is("/")) {
			Op op = is("*") ? Op::MUL : Op::DIV;
			position++;
			unary();
			out.push_back({ op });
		}
	}

	void unary() {
		if (is("-")) {
			position++;
			unary();
			out.push_back({ Op::NEG });
		} else if (is("+")) {
			position++;
			unary();
		} else if (is("!")) {
			position++;
			unary();
			out.push_back({ Op::NOT });
		} else {
			primary();
		}
	}

	void push_const(float value) {
		Instr instr{ Op::CONST };
		instr.value = value;
		out.push_back(instr);
	}

	void primary() {
		if (at_end()) {
			error = "unexpected end";
			return;
		}
		Token token = peek();
		position++;
		if (token.kind == Token::NUMBER) {
			push_const(token.number);
			return;
		}
		if (token.kind == Token::SYMBOL && token.text == "(") {
			ternary();
			if (!is(")")) {
				error = "expected ')'";
				return;
			}
			position++;
			return;
		}
		if (token.kind != Token::NAME) {
			error = "unexpected '" + describe(token) + "'";
			return;
		}
		const std::string &name = token.text;
		if (name == "math.pi") {
			push_const(PI_F);
			return;
		}
		if (name.rfind("math.", 0) == 0) {
			std::string function = name.substr(5);
			const FunctionInfo *info = nullptr;
			for (const FunctionInfo &candidate : FUNCTIONS) {
				if (function == candidate.name) {
					info = &candidate;
				}
			}
			if (info == nullptr || !is("(")) {
				error = "unsupported function '" + name + "'";
				return;
			}
			position++;
			int arguments = 0;
			while (!is(")")) {
				ternary();
				if (!error.empty()) {
					return;
				}
				arguments++;
				if (is(",")) {
					position++;
				} else if (!is(")")) {
					error = "expected ',' or ')'";
					return;
				}
			}
			position++;
			if (arguments != info->arguments) {
				error = name + " takes " + std::to_string(info->arguments) + " arguments";
				return;
			}
			if (info->fn == Fn::RANDOM || info->fn == Fn::RANDOM_INTEGER || info->fn == Fn::DIE_ROLL || info->fn == Fn::DIE_ROLL_INTEGER) {
				random = true;
			}
			Instr instr{ Op::CALL };
			instr.fn = (uint8_t)info->fn;
			out.push_back(instr);
			return;
		}
		if (name == "true" || name == "false") {
			push_const(name == "true" ? 1.0f : 0.0f);
			return;
		}
		size_t dot = name.find('.');
		char scope = dot == std::string::npos ? 0 : scope_of(name.substr(0, dot));
		std::string member = dot == std::string::npos ? "" : name.substr(dot + 1);
		if (scope == 0 || member.empty() || member.find('.') != std::string::npos) {
			error = "unsupported name '" + name + "'";
			return;
		}
		if (scope == 'q') {
			out.push_back({ Op::LOAD_Q, 0, names.query(member) });
		} else {
			int slot = names.variable(member);
			read.push_back(slot);
			out.push_back({ Op::LOAD_V, 0, slot });
		}
	}
};

} // namespace

void Rng::seed(uint64_t value) {
	state = 0;
	inc = (value << 1u) | 1u;
	next();
	state += 0x853c49e6748fea9bULL ^ value;
	next();
}

uint32_t Rng::next() {
	uint64_t old = state;
	state = old * 6364136223846793005ULL + inc;
	uint32_t shifted = (uint32_t)(((old >> 18u) ^ old) >> 27u);
	uint32_t rotation = (uint32_t)(old >> 59u);
	return (shifted >> rotation) | (shifted << ((-rotation) & 31));
}

float Rng::unit() {
	return (next() >> 8) * (1.0f / 16777216.0f);
}

float Rng::range(float low, float high) {
	return low + (high - low) * unit();
}

int Rng::integer(int low, int high) {
	if (high < low) {
		std::swap(low, high);
	}
	return low + (int)(next() % (uint32_t)(high - low + 1));
}

int Names::variable(const std::string &name) {
	auto found = v.find(name);
	if (found != v.end()) {
		return found->second;
	}
	int slot = (int)v.size();
	v[name] = slot;
	return slot;
}

int Names::query(const std::string &name) {
	auto found = q.find(name);
	if (found != q.end()) {
		return found->second;
	}
	int slot = (int)q.size();
	q[name] = slot;
	return slot;
}

// The deepest the stack gets running `code`, or -1 if it would underflow.
static int stack_depth(const std::vector<Instr> &code) {
	int depth = 0;
	int deepest = 0;
	for (const Instr &instr : code) {
		switch (instr.op) {
			case Op::CONST:
			case Op::LOAD_V:
			case Op::LOAD_Q:
				depth++;
				break;
			case Op::STORE_V:
			case Op::RETURN:
			case Op::NEG:
			case Op::NOT:
				break;
			case Op::SELECT:
				depth -= 2;
				break;
			case Op::CALL:
				for (const FunctionInfo &info : FUNCTIONS) {
					if ((uint8_t)info.fn == instr.fn) {
						depth -= info.arguments - 1;
					}
				}
				break;
			default:
				depth--;
				break;
		}
		if (depth < 1 && instr.op != Op::POP) {
			return -1;
		}
		deepest = std::max(deepest, depth);
	}
	return deepest;
}

Program compile(const std::string &text, Names &names) {
	Parser parser(text, names);
	Program program = parser.parse();
	if (program.error.empty() && !program.is_constant) {
		int depth = stack_depth(program.code);
		if (depth < 0 || depth > 64) {
			program = constant(0.0f);
			program.error = depth < 0 ? "malformed expression" : "expression nests too deeply";
		}
	}
	if (!program.error.empty()) {
		program.error += " in \"" + text + "\"";
	}
	return program;
}

Program constant(float value) {
	Program program;
	program.is_constant = true;
	program.constant = value;
	return program;
}

float Program::run(float *v, const float *q, Rng &rng) const {
	if (is_constant) {
		return constant;
	}
	float stack[64];
	int top = 0;
	for (const Instr &instr : code) {
		switch (instr.op) {
			case Op::CONST:
				stack[top++] = instr.value;
				break;
			case Op::LOAD_V:
				stack[top++] = v[instr.slot];
				break;
			case Op::LOAD_Q:
				stack[top++] = q[instr.slot];
				break;
			case Op::STORE_V:
				v[instr.slot] = stack[top - 1];
				break;
			case Op::POP:
				top--;
				break;
			case Op::RETURN:
				return stack[top - 1];
			case Op::NEG:
				stack[top - 1] = -stack[top - 1];
				break;
			case Op::NOT:
				stack[top - 1] = stack[top - 1] == 0.0f ? 1.0f : 0.0f;
				break;
			case Op::SELECT: {
				float no = stack[--top];
				float yes = stack[--top];
				float condition = stack[top - 1];
				stack[top - 1] = condition != 0.0f ? yes : no;
				break;
			}
			case Op::CALL: {
				float *a;
				switch ((Fn)instr.fn) {
					case Fn::ABS: a = &stack[top - 1]; a[0] = std::fabs(a[0]); break;
					case Fn::ACOS: a = &stack[top - 1]; a[0] = std::acos(a[0]) / DEG; break;
					case Fn::ASIN: a = &stack[top - 1]; a[0] = std::asin(a[0]) / DEG; break;
					case Fn::ATAN: a = &stack[top - 1]; a[0] = std::atan(a[0]) / DEG; break;
					case Fn::ATAN2: top--; a = &stack[top - 1]; a[0] = std::atan2(a[0], a[1]) / DEG; break;
					case Fn::CEIL: a = &stack[top - 1]; a[0] = std::ceil(a[0]); break;
					case Fn::CLAMP: top -= 2; a = &stack[top - 1]; a[0] = std::min(std::max(a[0], a[1]), a[2]); break;
					case Fn::COS: a = &stack[top - 1]; a[0] = std::cos(a[0] * DEG); break;
					case Fn::DIE_ROLL:
					case Fn::DIE_ROLL_INTEGER: {
						top -= 2;
						a = &stack[top - 1];
						float total = 0.0f;
						int count = std::max(0, (int)std::lround(a[0]));
						for (int i = 0; i < count; i++) {
							total += (Fn)instr.fn == Fn::DIE_ROLL ? rng.range(a[1], a[2])
									: (float)rng.integer((int)std::lround(a[1]), (int)std::lround(a[2]));
						}
						a[0] = total;
						break;
					}
					case Fn::EXP: a = &stack[top - 1]; a[0] = std::exp(a[0]); break;
					case Fn::FLOOR: a = &stack[top - 1]; a[0] = std::floor(a[0]); break;
					case Fn::HERMITE_BLEND: a = &stack[top - 1]; a[0] = 3.0f * a[0] * a[0] - 2.0f * a[0] * a[0] * a[0]; break;
					case Fn::LERP: top -= 2; a = &stack[top - 1]; a[0] = a[0] + (a[1] - a[0]) * a[2]; break;
					case Fn::LERPROTATE: top -= 2; a = &stack[top - 1]; a[0] = a[0] + wrap_angle(a[1] - a[0]) * a[2]; break;
					case Fn::LN: a = &stack[top - 1]; a[0] = std::log(a[0]); break;
					case Fn::MAX: top--; a = &stack[top - 1]; a[0] = std::max(a[0], a[1]); break;
					case Fn::MIN: top--; a = &stack[top - 1]; a[0] = std::min(a[0], a[1]); break;
					case Fn::MIN_ANGLE: a = &stack[top - 1]; a[0] = wrap_angle(a[0]); break;
					case Fn::MOD: top--; a = &stack[top - 1]; a[0] = a[1] != 0.0f ? std::fmod(a[0], a[1]) : 0.0f; break;
					case Fn::POW: top--; a = &stack[top - 1]; a[0] = std::pow(a[0], a[1]); break;
					case Fn::RANDOM: top--; a = &stack[top - 1]; a[0] = rng.range(a[0], a[1]); break;
					case Fn::RANDOM_INTEGER: top--; a = &stack[top - 1]; a[0] = (float)rng.integer((int)std::lround(a[0]), (int)std::lround(a[1])); break;
					case Fn::ROUND: a = &stack[top - 1]; a[0] = std::round(a[0]); break;
					case Fn::SIN: a = &stack[top - 1]; a[0] = std::sin(a[0] * DEG); break;
					case Fn::SQRT: a = &stack[top - 1]; a[0] = std::sqrt(std::max(a[0], 0.0f)); break;
					case Fn::TRUNC: a = &stack[top - 1]; a[0] = std::trunc(a[0]); break;
				}
				break;
			}
			default: {
				float right = stack[--top];
				float &left = stack[top - 1];
				switch (instr.op) {
					case Op::ADD: left = left + right; break;
					case Op::SUB: left = left - right; break;
					case Op::MUL: left = left * right; break;
					case Op::DIV: left = left / right; break;
					case Op::LT: left = left < right ? 1.0f : 0.0f; break;
					case Op::LE: left = left <= right ? 1.0f : 0.0f; break;
					case Op::GT: left = left > right ? 1.0f : 0.0f; break;
					case Op::GE: left = left >= right ? 1.0f : 0.0f; break;
					case Op::EQ: left = left == right ? 1.0f : 0.0f; break;
					case Op::NE: left = left != right ? 1.0f : 0.0f; break;
					case Op::AND: left = (left != 0.0f && right != 0.0f) ? 1.0f : 0.0f; break;
					case Op::OR: left = (left != 0.0f || right != 0.0f) ? 1.0f : 0.0f; break;
					default: break;
				}
				break;
			}
		}
	}
	return top > 0 ? stack[top - 1] : 0.0f;
}

} // namespace snowstorm
