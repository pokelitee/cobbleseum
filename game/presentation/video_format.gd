class_name VideoFormat
extends RefCounted
## Output formats for play and recording. Play defaults to landscape; clips can be rendered
## in either format from the same battle, since battles are deterministic.

const SIZES := {
	"landscape": Vector2i(1920, 1080),
	"vertical": Vector2i(1080, 1920),
}
const DEFAULT := "landscape"


static func is_portrait(size: Vector2) -> bool:
	return size.y > size.x


## Contents of an override.cfg that makes Godot start with the format's viewport size.
## Movie Maker fixes its output size at startup, so the size can't be changed from a script.
static func override_config(format: String) -> String:
	var size: Vector2i = SIZES[format]
	var window := Vector2i(size) / 3
	return ("; Written by tools/record.gd for one render; safe to delete.\n[display]\n" +
		"window/size/viewport_width=%d\nwindow/size/viewport_height=%d\n" +
		"window/size/window_width_override=%d\nwindow/size/window_height_override=%d\n") % [
			size.x, size.y, window.x, window.y]
