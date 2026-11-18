class_name TeamBalls
extends Control
## A team battle's side on its name plate (concepts_brief.md §12.5, M15): one ball per team
## member, in team order, as in the games: a healthy one red and white, one with a status
## condition tinted in the status's colour, a fainted one dark grey. The one out sits a little
## raised. Drawn in-house as pixel art; read from the battle every video frame.

const PIXEL := 3.0
const GAP := 6.0
## A ball, one string per row: "r" the top half, "w" the bottom, "o" the outline and band, "b"
## the button.
const BALL := [
	"..oooo..",
	".orrrro.",
	"orrrrrro",
	"oooobooo",
	"owwwwwwo",
	"owwwwwwo",
	".owwwwo.",
	"..oooo..",
]
const RED := Color("e8403a")
const WHITE := Color("f2f2f2")
const OUTLINE := Color("20222a")
const FAINTED := Color("55585f")
const RAISE := 4.0

## Per member: "healthy", "fainted" or a status code; and which is out.
var _states: Array[String] = []
var _out := -1
var _scale := 1.0


func _init(hud_scale: float) -> void:
	_scale = hud_scale
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows `team` (Battle.teams[side]) with `out` the fighter out now.
func show_team(team: Array, out: Fighter) -> void:
	var states: Array[String] = []
	for fighter: Fighter in team:
		states.append("fainted" if fighter.is_knocked_out() else (fighter.status if not fighter.status.is_empty() else "healthy"))
	var out_slot := out.slot if out != null else -1
	if states == _states and out_slot == _out:
		return
	_states = states
	_out = out_slot
	custom_minimum_size = Vector2(width_for(states.size(), _scale), (BALL.size() * PIXEL + RAISE) * _scale)
	size = custom_minimum_size
	queue_redraw()


## The row's width for `count` balls.
static func width_for(count: int, hud_scale: float) -> float:
	return (count * BALL[0].length() * PIXEL + maxi(count - 1, 0) * GAP) * hud_scale


## A member's state at `index`, for tests.
func state(index: int) -> String:
	return _states[index]


func _draw() -> void:
	var step := (BALL[0].length() * PIXEL + GAP) * _scale
	var pixel := PIXEL * _scale
	for i in _states.size():
		var state_name := _states[i]
		var top := RED
		var bottom := WHITE
		if state_name == "fainted":
			top = FAINTED
			bottom = FAINTED.lightened(0.15)
		elif state_name != "healthy":
			var tint: Color = Hud.STATUS_BADGES.get(state_name, ["", RED])[1]
			top = tint
			bottom = WHITE.lerp(tint, 0.45)
		var origin := Vector2(i * step, 0.0 if i == _out else RAISE * _scale)
		for y in BALL.size():
			var row: String = BALL[y]
			for x in row.length():
				var colour: Color
				match row[x]:
					"r":
						colour = top
					"w":
						colour = bottom
					"o":
						colour = OUTLINE
					"b":
						colour = WHITE if state_name != "fainted" else FAINTED.lightened(0.3)
					_:
						continue
				draw_rect(Rect2(origin + Vector2(x, y) * pixel, Vector2(pixel, pixel)), colour)
