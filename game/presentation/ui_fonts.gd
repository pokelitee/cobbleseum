class_name UiFonts
extends RefCounted
## The game's fonts (concepts_brief.md §12.5), both under the SIL Open Font License (licences
## beside them in fonts/): Lilita One, a chunky display face for names, titles, move banners
## and callouts, and Nunito ExtraBold for everything else.

const DISPLAY := preload("res://game/presentation/fonts/LilitaOne-Regular.ttf")
const BODY := preload("res://game/presentation/fonts/body.tres")


## Makes BODY the font of every control that doesn't pick one. Set at startup rather than as
## the project's custom font, which Godot loads before a fresh checkout has imported the font
## files and so logs load errors on the first import.
static func use_by_default() -> void:
	ThemeDB.get_default_theme().default_font = BODY
