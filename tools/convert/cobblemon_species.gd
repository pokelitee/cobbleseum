class_name CobblemonSpecies
extends RefCounted
## Locates a species' files inside the extracted Cobblemon tree (concepts_brief.md §5.2).

const BEDROCK := "assets/cobblemon/bedrock/pokemon"


## Files for a species folder such as "0009_blastoise" with the given aspects, such as
## ["alolan"]. Resolver variations apply in order: each one whose aspects are all in
## `aspects` overrides the model, texture and poser before it, so ["alolan"] starts from the
## base variation and swaps in the Alolan files. Returns {"geo", "texture", "poser",
## "layers"} or {"error"}; "layers" lists texture overlays drawn over the model
## ({"texture": path, "emissive": bool}), such as glowing eyes or Vivillon's wing patterns.
static func files(root: String, folder: String, aspects: Array = []) -> Dictionary:
	var resolver_dir := root.path_join(BEDROCK).path_join("resolvers").path_join(folder)
	var resolvers: Array = []
	for resolver_file in DirAccess.get_files_at(resolver_dir) if DirAccess.dir_exists_absolute(resolver_dir) else PackedStringArray():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(resolver_dir.path_join(resolver_file)))
		if data is Dictionary:
			resolvers.append(data)
	if resolvers.is_empty():
		return {"error": "no resolver for %s" % folder}
	resolvers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))
	var chosen := {}
	for data: Dictionary in resolvers:
		for variation: Dictionary in data.get("variations", []):
			if (variation.get("aspects", []) as Array).all(func(a: Variant) -> bool: return aspects.has(a)):
				for field in ["model", "texture", "poser", "layers"]:
					if variation.has(field):
						chosen[field] = variation[field]
	if not chosen.has("model"):
		return {"error": "%s: no variation with a model for aspects %s" % [folder, aspects]}
	var geo := root.path_join(BEDROCK).path_join("models").path_join(folder).path_join(
		(chosen.model as String).get_slice(":", 1) + ".json")
	if not FileAccess.file_exists(geo):
		return {"error": "%s: model %s not found at %s" % [folder, chosen.model, geo]}
	var layers: Array[Dictionary] = []
	for layer: Variant in chosen.get("layers", []):
		if layer is Dictionary:
			var path := resource_path(root, layer.get("texture", ""))
			if not path.is_empty():
				# Some resolvers write the flag as a string; only true (or "true") means emissive.
				var emissive: Variant = layer.get("emissive", false)
				layers.append({"texture": path, "emissive": str(emissive) == "true"})
	return {
		"geo": geo,
		"texture": resource_path(root, chosen.get("texture", "")),
		"poser": (chosen.get("poser", "") as String).get_slice(":", 1),
		"layers": layers,
	}


## "cobblemon:textures/x.png" -> <root>/assets/cobblemon/textures/x.png.
## Animated textures are {"frames": [...], "fps": n}; until flipbooks are supported the
## first frame stands in for the whole animation.
static func resource_path(root: String, texture: Variant) -> String:
	var id: Variant = texture
	if texture is Dictionary:
		var frames: Array = texture.get("frames", [])
		id = frames[0] if not frames.is_empty() else ""
	if not id is String or not id.contains(":"):
		return ""
	return root.path_join("assets").path_join(id.get_slice(":", 0)).path_join(id.get_slice(":", 1))


static func load_texture(path: String) -> Texture2D:
	var image := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	return ImageTexture.create_from_image(image) if image != null else null
