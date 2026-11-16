class_name PixelCanvas
extends RefCounted
## A flipbook sheet drawn pixel by pixel in Cobblemon's particle style (concepts_brief.md
## §12.5): every pixel is either fully opaque or fully clear, each sheet uses a handful of
## flat colours (no gradients), and frames sit side by side or stacked in equal cells.
## Drawing calls take coordinates inside the current frame's cell.

var image: Image
var cell := Vector2i.ONE
var frames := 1
var vertical := false
var _origin := Vector2i.ZERO


func _init(cell_size: Vector2i, frame_count := 1, stacked := false) -> void:
	cell = cell_size
	frames = frame_count
	vertical = stacked
	var size := Vector2i(cell.x, cell.y * frames) if vertical else Vector2i(cell.x * frames, cell.y)
	image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))


## Directs drawing to frame `index`.
func frame(index: int) -> void:
	_origin = Vector2i(0, cell.y * index) if vertical else Vector2i(cell.x * index, 0)


func pixel(x: int, y: int, colour: Color) -> void:
	if x < 0 or y < 0 or x >= cell.x or y >= cell.y:
		return
	image.set_pixel(_origin.x + x, _origin.y + y, Color(colour, 1.0))


func clear(x: int, y: int) -> void:
	if x >= 0 and y >= 0 and x < cell.x and y < cell.y:
		image.set_pixel(_origin.x + x, _origin.y + y, Color(0, 0, 0, 0))


func is_set(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < cell.x and y < cell.y and image.get_pixel(_origin.x + x, _origin.y + y).a > 0.5


## A filled disc centred on (cx, cy), which may sit between pixels.
func disc(cx: float, cy: float, radius: float, colour: Color) -> void:
	for y in cell.y:
		for x in cell.x:
			if Vector2(x + 0.5 - cx, y + 0.5 - cy).length() <= radius:
				pixel(x, y, colour)


## A ring between `inner` and `outer` radius.
func ring(cx: float, cy: float, inner: float, outer: float, colour: Color) -> void:
	for y in cell.y:
		for x in cell.x:
			var distance := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			if distance <= outer and distance >= inner:
				pixel(x, y, colour)


## A ring dithered to `share` of its pixels (a checkerboard at 0.5), the stepped stand-in
## for a soft falloff.
func dithered_ring(cx: float, cy: float, inner: float, outer: float, colour: Color, share: float) -> void:
	for y in cell.y:
		for x in cell.x:
			var distance := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			if distance <= outer and distance >= inner and _dither(x, y) < share:
				pixel(x, y, colour)


## A one-pixel line (Bresenham).
func line(from: Vector2i, to: Vector2i, colour: Color) -> void:
	var delta := (to - from).abs()
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var error := delta.x - delta.y
	var at := from
	while true:
		pixel(at.x, at.y, colour)
		if at == to:
			break
		var doubled := error * 2
		if doubled > -delta.y:
			error -= delta.y
			at.x += step.x
		if doubled < delta.x:
			error += delta.x
			at.y += step.y


## The arc of a circle from `start` to `end` degrees, `width` pixels thick.
func arc(cx: float, cy: float, radius: float, start: float, end: float, width: float, colour: Color) -> void:
	for y in cell.y:
		for x in cell.x:
			var offset := Vector2(x + 0.5 - cx, y + 0.5 - cy)
			if absf(offset.length() - radius) > width * 0.5:
				continue
			var angle := fposmod(rad_to_deg(atan2(offset.y, offset.x)) - start, 360.0)
			if angle <= fposmod(end - start, 360.0):
				pixel(x, y, colour)


## Darkens the edge of everything drawn so far: set pixels with a clear neighbour take
## `colour`, the one-pixel outline shading Cobblemon's pieces use.
func rim(colour: Color) -> void:
	var edges: Array[Vector2i] = []
	for y in cell.y:
		for x in cell.x:
			if is_set(x, y) and not (is_set(x - 1, y) and is_set(x + 1, y) and is_set(x, y - 1) and is_set(x, y + 1)):
				edges.append(Vector2i(x, y))
	for at in edges:
		pixel(at.x, at.y, colour)


## A 4x4 ordered-dither threshold in [0, 1) for a pixel.
static func _dither(x: int, y: int) -> float:
	const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	return BAYER[(y % 4) * 4 + (x % 4)] / 16.0
