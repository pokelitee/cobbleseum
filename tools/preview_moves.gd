extends SceneTree
## Renders each move style for visual checks of MoveFX (concepts_brief.md §12.5).
## Usage (needs a window, not --headless):
##   godot --path . --script res://tools/preview_moves.gd -- [style ...]
## Two fighters stand apart under a fixed side-on camera. For each style, one move is
## wound up and thrown (or swung) from left to right, and four moments are captured:
## wind-up, early and late in flight (or the strike), and the hit. Writes
## cache/previews/move_<style>.png; previews show Cobblemon art, so they stay in the cache.

const SHOT_SIZE := Vector2i(480, 360)
const GAP := 6.0
const SPECIES: Array[String] = ["blastoise", "cinderace"]
## A type per style, so each preview shows a typical colour.
const TYPES := {
	"orb": "Fairy", "bullet": "Ghost", "beam": "Ice", "bolt": "Electric", "stream": "Fire", "pulse": "Dark",
	"sound": "Bug", "wind": "Flying", "powder": "Grass", "skyfall": "Dragon", "erupt": "Rock",
	"quake": "Ground", "mind": "Psychic", "explosion": "Normal", "strike": "Normal", "punch": "Electric",
	"kick": "Fighting", "bite": "Dark", "slash": "Dark", "rush": "Fire",
}
const FLIGHT_FRAMES := 18

## The project's stretch settings fix the root viewport's size, so shots render here.
var _viewport: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_viewport = SubViewport.new()
	_viewport.size = SHOT_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		printerr("error: " + loaded.error)
		return quit(1)
	var styles: Array = Array(OS.get_cmdline_user_args())
	if styles.is_empty():
		styles = MoveStyle.MELEE + MoveStyle.RANGED
	var out_dir := ProjectSettings.globalize_path("res://cache/previews")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for style: String in styles:
		if not TYPES.has(style):
			printerr("error: unknown style '%s'" % style)
			return quit(1)
		var path := out_dir.path_join("move_%s.png" % style)
		await _render(loaded.data, style, path)
		print("%s: wrote %s" % [style, path])
	quit(0)


func _render(data: BattleData, style: String, path: String) -> void:
	var stage := _stage()
	_viewport.add_child(stage)
	var camera: Camera3D = stage.get_node("Camera")
	camera.make_current()
	camera.look_at_from_position(Vector3(0, 2.2, 8.5), Vector3(0, 1.0, 0))
	var views: Array[FighterView] = []
	var battle := Battle.new()
	var melee := MoveStyle.MELEE.has(style)
	var move := BattleMove.new()
	move.id = "preview_" + style
	move.name = style
	move.kind = BattleMove.Kind.MELEE if melee else BattleMove.Kind.PROJECTILE
	move.type = TYPES[style]
	move.power = 90
	for side in 2:
		var entry: Dictionary = data.roster[SPECIES[side]]
		var view := FighterView.from_model(BattleView.MODELS_DIR.path_join(entry.model), entry.scale, entry.height)
		stage.add_child(view)
		var gap: float = GAP
		if melee:
			gap = float(data.roster[SPECIES[0]].radius) + float(data.roster[SPECIES[1]].radius) + 0.9
		var position := Vector2((-0.5 if side == 0 else 0.5) * gap, 0)
		view.place(position, Vector2(1 if side == 0 else -1, 0))
		views.append(view)
		var fighter := Fighter.new()
		fighter.side = side
		fighter.position = position
		fighter.radius = entry.radius
		fighter.moves = [move]
		battle.fighters.append(fighter)
	var fx := MoveFX.new()
	fx.styles = {move.id: style}
	stage.add_child(fx)

	var sheet := Image.create(SHOT_SIZE.x * 4, SHOT_SIZE.y, false, Image.FORMAT_RGBA8)
	fx.windup(views[0], move)
	await _frames(fx, battle, MoveFX.WINDUP_FRAMES / 2)
	await _capture(sheet, 0)
	await _frames(fx, battle, MoveFX.WINDUP_FRAMES / 2)
	if melee:
		fx.melee(views[0], views[1], move)
		await _frames(fx, battle, 2)
		await _capture(sheet, 1)
		await _frames(fx, battle, 3)
		await _capture(sheet, 2)
	else:
		var start: Vector2 = battle.fighters[0].position + Vector2(battle.fighters[0].radius, 0)
		var end: Vector2 = battle.fighters[1].position - Vector2(battle.fighters[1].radius, 0)
		var projectile := {"owner": 0, "move": 0, "position": start, "velocity": (end - start) / FLIGHT_FRAMES}
		battle.projectiles.append(projectile)
		for i in FLIGHT_FRAMES:
			fx.sync_projectiles(battle)
			await _frames(fx, battle, 1)
			if i == FLIGHT_FRAMES * 2 / 5:
				await _capture(sheet, 1)
			if i == FLIGHT_FRAMES * 4 / 5:
				await _capture(sheet, 2)
			projectile.position += projectile.velocity
		battle.projectiles.clear()
		fx.sync_projectiles(battle)
	fx.hit(views[1], move, true)
	await _frames(fx, battle, 3)
	await _capture(sheet, 3)
	sheet.save_png(path)
	stage.queue_free()
	await process_frame


func _frames(fx: MoveFX, _battle: Battle, count: int) -> void:
	for i in count:
		fx.next_frame()
		await process_frame


func _capture(sheet: Image, slot: int) -> void:
	await process_frame
	await process_frame
	var image := _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	sheet.blit_rect(image, Rect2i(Vector2i.ZERO, SHOT_SIZE), Vector2i(slot * SHOT_SIZE.x, 0))


func _stage() -> Node3D:
	var stage := Node3D.new()
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 50
	stage.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(30, 30)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.42, 0.55, 0.38)
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.53, 0.72, 0.9)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.65, 0.65, 0.7)
	stage.add_child(environment)
	return stage
