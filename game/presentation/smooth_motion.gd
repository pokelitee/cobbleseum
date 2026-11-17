class_name SmoothMotion
extends RefCounted
## Draws the presentation smoothly between its video frames (concepts_brief.md §12.2). The
## presentation advances in steps of 1/30 s, like the simulation, so a window refreshing at
## 60 Hz or more would show some steps twice and skip others. Each display frame instead shows
## the tracked nodes (fighters, their procedural motion, the camera, projectiles) part of the
## way from where the step before last left them to where the last step did. That draws them
## up to one step behind, in exchange for even motion.
##
## Everything that steps the presentation must see the nodes where the steps put them, so
## restore() puts them back before each step and capture() records them after it. Recordings
## advance exactly one step per frame and never call show(), so they are unchanged.

## Node3D -> {"from": Transform3D, "to": Transform3D, "new": bool}.
var _nodes: Dictionary = {}
var _camera: Camera3D
var _fov_from := 0.0
var _fov_to := 0.0
var _snap_all := false
var _shown := false


## Smooths `node`'s transform from the next step on. A node added during a step starts where
## that step put it.
func track(node: Node3D) -> void:
	if not _nodes.has(node):
		_nodes[node] = {"from": node.transform, "to": node.transform, "new": true}


## Smooths the camera's transform and field of view.
func track_camera(camera: Camera3D) -> void:
	_camera = camera
	_fov_from = camera.fov
	_fov_to = camera.fov
	track(camera)


## The next step jumps `node` rather than moving it (a camera cut): it shows where it lands.
func snap(node: Node3D) -> void:
	if _nodes.has(node):
		_nodes[node].new = true


## The next step jumps everything (cutting into or out of the instant replay).
func snap_all() -> void:
	_snap_all = true


## Puts every node back where the last step left it, before the next step.
func restore() -> void:
	if not _shown:
		return
	_shown = false
	for node: Variant in _nodes.keys():
		if is_instance_valid(node):
			(node as Node3D).transform = _nodes[node].to
	if is_instance_valid(_camera):
		_camera.fov = _fov_to


## Records where a step left every node; what it moved from is where the step before left it.
func capture() -> void:
	var camera_jumps: bool = _snap_all or (is_instance_valid(_camera) and _nodes.has(_camera) and _nodes[_camera].new)
	for node: Variant in _nodes.keys():
		if not is_instance_valid(node):
			_nodes.erase(node)
			continue
		var entry: Dictionary = _nodes[node]
		var now := (node as Node3D).transform
		entry.from = now if entry.new or _snap_all else entry.to
		entry.to = now
		entry.new = false
	if is_instance_valid(_camera):
		_fov_from = _camera.fov if camera_jumps else _fov_to
		_fov_to = _camera.fov
	_snap_all = false


## Shows every node `weight` (0 to 1) of the way through the last step.
func show(weight: float) -> void:
	_shown = true
	for node: Variant in _nodes.keys():
		if is_instance_valid(node):
			var entry: Dictionary = _nodes[node]
			(node as Node3D).transform = (entry.from as Transform3D).interpolate_with(entry.to, weight)
	if is_instance_valid(_camera):
		_camera.fov = lerpf(_fov_from, _fov_to, weight)


## How far `node` is drawn from where the last step left it, in its parent's space: things
## riding it (particle effects) shift by as much to stay with it. Zero for untracked nodes.
func offset_of(node: Node3D) -> Vector3:
	if not _shown or not _nodes.has(node) or not is_instance_valid(node):
		return Vector3.ZERO
	return node.transform.origin - (_nodes[node].to as Transform3D).origin
