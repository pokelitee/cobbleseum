class_name ScreenPanes
extends Node3D
## How screens (concepts_brief.md §9.11) look: a translucent pane in the screen's colour, with a
## pixel-art border, standing between a shielded fighter and its foe and facing the foe. A
## side's panes follow its fighter every frame and fade in and out with the battle's state; Aurora
## Veil and Reflect with Light Screen stand a little apart so both show.

const COLOURS := {"reflect": Color(1.0, 0.45, 0.75), "lightscreen": Color(1.0, 0.85, 0.3), "auroraveil": Color(0.55, 0.95, 1.0)}
const FADE_FRAMES := 8
## The pane stands this far beyond the fighter's hitbox, toward the foe.
const GAP := 0.35
const STACK := 0.12
## The border texture's pixels (16 to the pane's width).
const TEXTURE_PIXELS := 16

var _panes := [{}, {}]
var _alphas := [{}, {}]
var _texture: ImageTexture


func _ready() -> void:
	_texture = _border_texture()


## Places each side's panes for the screens up (`screens`, ArenaConditions.screens) in front of
## `views`, facing each other's fighter, and fades them by one video frame.
func sync(screens: Array[Dictionary], views: Array[FighterView], radii: Array[float]) -> void:
	for side in 2:
		var me := views[side]
		var foe := views[1 - side]
		var toward := foe.global_position - me.global_position
		toward.y = 0.0
		if toward.length_squared() < 1e-6:
			toward = Vector3.FORWARD
		toward = toward.normalized()
		var index := 0
		for name: String in COLOURS:
			var target := 1.0 if screens[side].has(name) else 0.0
			var alpha: float = move_toward(float(_alphas[side].get(name, 0.0)), target, 1.0 / FADE_FRAMES)
			_alphas[side][name] = alpha
			if alpha <= 0.0 and not _panes[side].has(name):
				continue
			var pane: MeshInstance3D = _panes[side].get(name, null)
			if pane == null:
				pane = _pane(name)
				_panes[side][name] = pane
			pane.visible = alpha > 0.0
			if not pane.visible:
				continue
			var size := maxf(me.height * 1.2, 1.0)
			(pane.mesh as QuadMesh).size = Vector2(size, size)
			var distance := radii[side] + GAP + STACK * index
			pane.global_position = me.global_position + toward * distance + Vector3.UP * size * 0.5
			pane.look_at(pane.global_position + toward, Vector3.UP)
			(pane.material_override as StandardMaterial3D).albedo_color.a = alpha
			index += 1


func _pane(name: String) -> MeshInstance3D:
	var pane := MeshInstance3D.new()
	pane.mesh = QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = _texture
	# Brighter than white, so the border blooms.
	var colour: Color = COLOURS[name]
	material.albedo_color = Color(colour.r * 1.6, colour.g * 1.6, colour.b * 1.6, 0.0)
	pane.material_override = material
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pane)
	return pane


## A white pixel-art pane: a solid two-pixel border, a faint fill and a few diagonal glints.
static func _border_texture() -> ImageTexture:
	var image := Image.create(TEXTURE_PIXELS, TEXTURE_PIXELS, false, Image.FORMAT_RGBA8)
	var last := TEXTURE_PIXELS - 1
	for y in TEXTURE_PIXELS:
		for x in TEXTURE_PIXELS:
			var edge := mini(mini(x, y), mini(last - x, last - y))
			var alpha := 0.9 if edge == 0 else (0.55 if edge == 1 else 0.14)
			if edge > 1 and (x + y) % 9 == 0 and x < TEXTURE_PIXELS / 2:
				alpha = 0.45
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(image)
