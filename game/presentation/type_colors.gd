class_name TypeColors
extends RefCounted
## One signature colour per Pokémon type, used to theme move effects.

const COLORS := {
	"Normal": Color("c6c6a7"), "Fire": Color("ff7a2e"), "Water": Color("4c8dff"),
	"Electric": Color("ffd93d"), "Grass": Color("5ccf5c"), "Ice": Color("8ff0ff"),
	"Fighting": Color("d9483b"), "Poison": Color("b45ad6"), "Ground": Color("e0b45c"),
	"Flying": Color("a3b8ff"), "Psychic": Color("ff5f9e"), "Bug": Color("a8c22a"),
	"Rock": Color("c9a94c"), "Ghost": Color("7a5fb5"), "Dragon": Color("7a5cff"),
	"Dark": Color("6b5848"), "Steel": Color("b8c4d9"), "Fairy": Color("ffa3d1"),
}


static func of(type: String) -> Color:
	return COLORS.get(type, Color.WHITE)
