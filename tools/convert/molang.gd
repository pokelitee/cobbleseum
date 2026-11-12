class_name Molang
extends RefCounted
## Parser and evaluator for the subset of Molang found in Cobblemon's animation files:
## numbers, + - * /, unary - + !, parentheses, math.* functions, and query/variable names.
## Only the animation time is known when baking animations, so every other name evaluates to 0
## and is listed in `unknown_names` for the converter's report. Asset text is never run as code.

enum Kind { NUMBER, NAME, CALL, NEGATE, NOT, BINARY }

## Supported math functions and their argument counts.
const FUNCTIONS := {
	"abs": 1, "acos": 1, "asin": 1, "atan": 1, "atan2": 2, "ceil": 1, "clamp": 3, "cos": 1,
	"exp": 1, "floor": 1, "lerp": 3, "ln": 1, "max": 2, "min": 2, "mod": 2, "pow": 2,
	"random": 2, "random_integer": 2, "round": 1, "sin": 1, "sqrt": 1, "trunc": 1,
}
const ANIM_TIME_NAMES: Array[String] = ["q.anim_time", "query.anim_time"]

## Empty when the text parsed; otherwise why it didn't (and evaluate() returns 0).
var error := ""
## Names the expression reads that evaluate to 0 because they're unknown at bake time.
var unknown_names: PackedStringArray = []

var _tokens: Array = []
var _position := 0
var _root: Array = []


static func compile(text: String) -> Molang:
	var expression := Molang.new()
	expression._parse(text)
	return expression


## Evaluates at the given animation time; `rng` serves math.random and math.random_integer.
func evaluate(anim_time: float, rng: RandomNumberGenerator) -> float:
	return 0.0 if not error.is_empty() else _eval(_root, anim_time, rng)


func _parse(text: String) -> void:
	_tokens = _tokenize(text.strip_edges().to_lower().trim_suffix(";"))
	if not error.is_empty():
		return
	_position = 0
	_root = _parse_additive()
	if error.is_empty() and _position < _tokens.size():
		error = "unexpected '%s'" % _tokens[_position]
	if not error.is_empty():
		error = "%s in \"%s\"" % [error, text]
		_root = []


func _tokenize(text: String) -> Array:
	var tokens: Array = []
	var i := 0
	while i < text.length():
		var c := text[i]
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			i += 1
		elif c.is_valid_int() or (c == "." and i + 1 < text.length() and text[i + 1].is_valid_int()):
			var start := i
			while i < text.length() and (text[i].is_valid_int() or text[i] == "."):
				i += 1
			tokens.append(text.substr(start, i - start).to_float())
		elif c == "_" or (c >= "a" and c <= "z"):
			var start := i
			while i < text.length() and (text[i] == "_" or text[i] == "." or text[i].is_valid_int() or (text[i] >= "a" and text[i] <= "z")):
				i += 1
			tokens.append(text.substr(start, i - start))
		elif c in "+-*/(),!":
			tokens.append(c)
			i += 1
		else:
			error = "unsupported character '%s'" % c
			return []
	return tokens


func _peek() -> Variant:
	return _tokens[_position] if _position < _tokens.size() else null


func _take(expected: String) -> bool:
	if _peek() is String and _peek() == expected:
		_position += 1
		return true
	return false


func _parse_additive() -> Array:
	var left := _parse_multiplicative()
	while error.is_empty() and (_peek() is String) and (_peek() == "+" or _peek() == "-"):
		var op: String = _tokens[_position]
		_position += 1
		left = [Kind.BINARY, op, left, _parse_multiplicative()]
	return left


func _parse_multiplicative() -> Array:
	var left := _parse_unary()
	while error.is_empty() and (_peek() is String) and (_peek() == "*" or _peek() == "/"):
		var op: String = _tokens[_position]
		_position += 1
		left = [Kind.BINARY, op, left, _parse_unary()]
	return left


func _parse_unary() -> Array:
	if _take("-"):
		return [Kind.NEGATE, _parse_unary()]
	if _take("+"):
		return _parse_unary()
	if _take("!"):
		return [Kind.NOT, _parse_unary()]
	return _parse_primary()


func _parse_primary() -> Array:
	var token: Variant = _peek()
	if token == null:
		error = "unexpected end of expression"
		return []
	_position += 1
	if token is float:
		return [Kind.NUMBER, token]
	if token == "(":
		var inner := _parse_additive()
		if error.is_empty() and not _take(")"):
			error = "missing ')'"
		return inner
	if token is String and (token[0] == "_" or (token[0] >= "a" and token[0] <= "z")):
		return _parse_name(token)
	error = "unexpected '%s'" % token
	return []


func _parse_name(name: String) -> Array:
	if name == "math.pi":
		return [Kind.NUMBER, PI]
	if not _take("("):
		if not name in ANIM_TIME_NAMES and not name in unknown_names:
			unknown_names.append(name)
		return [Kind.NAME, name]
	var args: Array = []
	if not _take(")"):
		while error.is_empty():
			args.append(_parse_additive())
			if _take(")"):
				break
			if not _take(","):
				error = "expected ',' or ')' in call to %s" % name
	if not name.begins_with("math."):
		# Query functions such as q.r.velocity_y(0) describe live entity state (riding, targets),
		# which doesn't exist when baking an animation, so they behave like unknown names.
		if not name in unknown_names:
			unknown_names.append(name)
		return [Kind.NAME, name]
	var function := name.trim_prefix("math.")
	if not FUNCTIONS.has(function):
		error = "unknown function %s" % name
	elif args.size() != FUNCTIONS[function]:
		error = "%s takes %d arguments, got %d" % [name, FUNCTIONS[function], args.size()]
	return [Kind.CALL, function, args]


func _eval(node: Array, t: float, rng: RandomNumberGenerator) -> float:
	match node[0]:
		Kind.NUMBER:
			return node[1]
		Kind.NAME:
			return t if node[1] in ANIM_TIME_NAMES else 0.0
		Kind.NEGATE:
			return -_eval(node[1], t, rng)
		Kind.NOT:
			return 1.0 if _eval(node[1], t, rng) == 0.0 else 0.0
		Kind.BINARY:
			var a := _eval(node[2], t, rng)
			var b := _eval(node[3], t, rng)
			match node[1]:
				"+": return a + b
				"-": return a - b
				"*": return a * b
				_: return 0.0 if b == 0.0 else a / b
	var args: Array[float] = []
	for arg: Array in node[2]:
		args.append(_eval(arg, t, rng))
	return _call(node[1], args, rng)


## Molang's trigonometry works in degrees.
static func _call(function: String, a: Array[float], rng: RandomNumberGenerator) -> float:
	match function:
		"abs": return absf(a[0])
		"acos": return rad_to_deg(acos(a[0]))
		"asin": return rad_to_deg(asin(a[0]))
		"atan": return rad_to_deg(atan(a[0]))
		"atan2": return rad_to_deg(atan2(a[0], a[1]))
		"ceil": return ceilf(a[0])
		"clamp": return clampf(a[0], a[1], a[2])
		"cos": return cos(deg_to_rad(a[0]))
		"exp": return exp(a[0])
		"floor": return floorf(a[0])
		"lerp": return lerpf(a[0], a[1], a[2])
		"ln": return log(a[0])
		"max": return maxf(a[0], a[1])
		"min": return minf(a[0], a[1])
		"mod": return fmod(a[0], a[1]) if a[1] != 0.0 else 0.0
		"pow": return pow(a[0], a[1])
		"random": return rng.randf_range(a[0], a[1])
		"random_integer": return float(rng.randi_range(int(a[0]), int(a[1])))
		"round": return roundf(a[0])
		"sin": return sin(deg_to_rad(a[0]))
		"sqrt": return sqrt(a[0])
		_: return float(int(a[0]))  # trunc
