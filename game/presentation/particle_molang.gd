class_name ParticleMolang
extends RefCounted
## Molang for Bedrock particle effects (concepts_brief.md §12.5, Cobblemon's move effects).
## Parses the Molang subset Cobblemon's particles use (numbers, arithmetic, comparisons,
## && || !, ?:, math.* calls, v./q./t. names, `name = value;` statements and `return`) and
## translates it to Godot Expressions, which run natively. Asset text is parsed by our own
## grammar first, so nothing outside that grammar reaches Expression.
## Names read through two dictionaries: `v` (variables, also t./temp./c./context.) and `q`
## (queries). The caller fills both, including 0 for every name in `names`.

const PREFIXES := {
	"v": "v", "variable": "v", "t": "v", "temp": "v", "c": "v", "context": "v",
	"q": "q", "query": "q",
}
## Supported math functions and their argument counts; see ParticleMath.
const FUNCTIONS := {
	"abs": 1, "acos": 1, "asin": 1, "atan": 1, "atan2": 2, "ceil": 1, "clamp": 3, "cos": 1,
	"die_roll": 3, "die_roll_integer": 3, "exp": 1, "floor": 1, "hermite_blend": 1, "lerp": 3,
	"lerprotate": 3, "ln": 1, "max": 2, "min": 2, "min_angle": 1, "mod": 2, "pow": 2,
	"random": 2, "random_integer": 2, "round": 1, "sin": 1, "sqrt": 1, "trunc": 1,
}
## Comparisons and logic become ParticleMath calls returning 1.0 or 0.0, as Molang's do
## (Expression's own operators return booleans, and it can't nest `a if c else b`).
const COMPARISONS := {"<": "m_lt", "<=": "m_le", ">": "m_gt", ">=": "m_ge", "==": "m_eq", "!=": "m_ne"}

## Empty when the text parsed; otherwise why it didn't (and evaluate() returns 0).
var error := ""
## Every v. and q. name the program reads or writes, as "v.name" / "q.name".
var names: Dictionary = {}
## A constant when the source is a plain number.
var constant := 0.0
var is_constant := false

## [{"target": "" or variable name, "expression": Expression, "return": bool}]
var _statements: Array = []
var _tokens: Array = []
var _position := 0


## Compiles a JSON value: a number, a Molang string, or null (0).
static func compile(source: Variant) -> ParticleMolang:
	var program := ParticleMolang.new()
	if source == null:
		program.is_constant = true
	elif source is float or source is int:
		program.is_constant = true
		program.constant = float(source)
	elif source is bool:
		program.is_constant = true
		program.constant = 1.0 if source else 0.0
	elif source is String:
		program._compile(source)
	else:
		program.error = "unsupported Molang value %s" % str(source)
		program.is_constant = true
	return program


## Runs the program and returns its value (the last statement's, or the returned one).
## Assignments write into `v`.
func evaluate(v: Dictionary, q: Dictionary, math: ParticleMath) -> float:
	if is_constant:
		return constant
	var value := 0.0
	for statement: Dictionary in _statements:
		var result: Variant = (statement.expression as Expression).execute([v, q], math)
		value = float(result) if result is float or result is int else (1.0 if result is bool and result else 0.0)
		if statement.target != "":
			v[statement.target] = value
		if statement["return"]:
			return value
	return value


func _compile(text: String) -> void:
	var source := text.strip_edges().to_lower()
	if source.is_valid_float():
		is_constant = true
		constant = source.to_float()
		return
	_tokens = _tokenize(source)
	if not error.is_empty():
		return _fail(text)
	_position = 0
	while _position < _tokens.size():
		if _at(";"):
			_position += 1
			continue
		var statement := {"target": "", "return": false}
		if _at("return"):
			_position += 1
			statement["return"] = true
		elif _peek() is String and _is_name(_peek()) and _peek_at(1) is String and _peek_at(1) == "=":
			var target := _variable_key(_peek())
			if target.is_empty():
				error = "cannot assign to '%s'" % _peek()
				return _fail(text)
			statement.target = target
			_position += 2
		var emitted := _parse_ternary()
		if not error.is_empty():
			return _fail(text)
		if _position < _tokens.size() and not _at(";"):
			error = "unexpected '%s'" % str(_peek())
			return _fail(text)
		var expression := Expression.new()
		if expression.parse(emitted, ["v", "q"]) != OK:
			error = "cannot translate (%s)" % expression.get_error_text()
			return _fail(text)
		statement.expression = expression
		_statements.append(statement)
	if _statements.is_empty():
		is_constant = true


func _fail(text: String) -> void:
	error = "%s in \"%s\"" % [error, text]
	_statements = []
	is_constant = true
	constant = 0.0


func _tokenize(text: String) -> Array:
	var tokens: Array = []
	var i := 0
	while i < text.length():
		var c := text[i]
		var pair := text.substr(i, 2)
		if c in " \t\n\r":
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
		elif pair in ["<=", ">=", "==", "!=", "&&", "||"]:
			tokens.append(pair)
			i += 2
		elif c in "+-*/(),!<>?:;=":
			tokens.append(c)
			i += 1
		else:
			error = "unsupported character '%s'" % c
			return []
	return tokens


func _peek() -> Variant:
	return _tokens[_position] if _position < _tokens.size() else null


func _at(text: String) -> bool:
	var token: Variant = _peek()
	return token is String and token == text


func _peek_at(offset: int) -> Variant:
	return _tokens[_position + offset] if _position + offset < _tokens.size() else null


static func _is_name(token: Variant) -> bool:
	return token is String and (token[0] == "_" or (token[0] >= "a" and token[0] <= "z"))


## "v.name" style key for a variable or query token, or "" when it isn't one.
func _variable_key(token: String) -> String:
	var dot := token.find(".")
	if dot < 0 or not PREFIXES.has(token.substr(0, dot)):
		return ""
	var scope: String = PREFIXES[token.substr(0, dot)]
	var name := token.substr(dot + 1)
	if name.is_empty() or name.contains("."):
		return ""
	names["%s.%s" % [scope, name]] = true
	return name if scope == "v" else ""


func _parse_ternary() -> String:
	var condition := _parse_or()
	if not _at("?"):
		return condition
	_position += 1
	var yes := _parse_ternary()
	if not _at(":"):
		error = "expected ':'"
		return ""
	_position += 1
	var no := _parse_ternary()
	return "m_select(%s, %s, %s)" % [condition, yes, no]


func _parse_or() -> String:
	var left := _parse_and()
	while _at("||"):
		_position += 1
		var right := _parse_and()
		left = "m_or(%s, %s)" % [left, right]
	return left


func _parse_and() -> String:
	var left := _parse_comparison()
	while _at("&&"):
		_position += 1
		var right := _parse_comparison()
		left = "m_and(%s, %s)" % [left, right]
	return left


func _parse_comparison() -> String:
	var left := _parse_additive()
	if _peek() is String and COMPARISONS.has(_peek()):
		var op: String = _peek()
		_position += 1
		var right := _parse_additive()
		left = "%s(%s, %s)" % [COMPARISONS[op], left, right]
	return left


func _parse_additive() -> String:
	var left := _parse_term()
	while _peek() is String and (_at("+") or _at("-")):
		var op: String = _peek()
		_position += 1
		left = "(%s %s %s)" % [left, op, _parse_term()]
	return left


func _parse_term() -> String:
	var left := _parse_unary()
	while _peek() is String and (_at("*") or _at("/")):
		var op: String = _peek()
		_position += 1
		left = "(%s %s %s)" % [left, op, _parse_unary()]
	return left


func _parse_unary() -> String:
	var token: Variant = _peek()
	if token is String and token == "-":
		_position += 1
		return "(-%s)" % _parse_unary()
	if token is String and token == "+":
		_position += 1
		return _parse_unary()
	if token is String and token == "!":
		_position += 1
		return "m_not(%s)" % _parse_unary()
	return _parse_primary()


func _parse_primary() -> String:
	var token: Variant = _peek()
	if token == null:
		error = "unexpected end"
		return "0.0"
	_position += 1
	if token is float:
		return "%s" % _float_literal(token)
	if token is String and token == "(":
		var inner := _parse_ternary()
		if not _at(")"):
			error = "expected ')'"
		_position += 1
		return "(%s)" % inner
	if not _is_name(token):
		error = "unexpected '%s'" % str(token)
		return "0.0"
	var name: String = token
	if name == "math.pi":
		return _float_literal(PI)
	if name.begins_with("math."):
		var function := name.substr(5)
		if not FUNCTIONS.has(function) or not _at("("):
			error = "unsupported function '%s'" % name
			return "0.0"
		_position += 1
		var arguments: Array[String] = []
		while not _at(")"):
			arguments.append(_parse_ternary())
			if not error.is_empty():
				return "0.0"
			if _at(","):
				_position += 1
			elif not _at(")"):
				error = "expected ',' or ')'"
				return "0.0"
		_position += 1
		if arguments.size() != FUNCTIONS[function]:
			error = "math.%s takes %d arguments" % [function, FUNCTIONS[function]]
			return "0.0"
		return "m_%s(%s)" % [function, ", ".join(arguments)]
	var dot := name.find(".")
	if dot > 0 and PREFIXES.has(name.substr(0, dot)):
		var key := _variable_key(name)
		var scope: String = PREFIXES[name.substr(0, dot)]
		var member := name.substr(dot + 1)
		if member.is_empty() or member.contains("."):
			error = "unsupported name '%s'" % name
			return "0.0"
		if scope == "q":
			return "q.%s" % name.substr(dot + 1)
		if key.is_empty():
			error = "unsupported name '%s'" % name
			return "0.0"
		return "v.%s" % key
	if name == "true" or name == "false":
		return "1.0" if name == "true" else "0.0"
	error = "unsupported name '%s'" % name
	return "0.0"


static func _float_literal(value: float) -> String:
	var text := String.num(value, 8)
	return text if text.contains(".") or text.contains("e") else text + ".0"
