class_name CobblemonSpecies
extends RefCounted
## Locates a species' files inside the extracted Cobblemon tree (concepts_brief.md §5.2).

const BEDROCK := "assets/cobblemon/bedrock/pokemon"


## Files for a species folder such as "0009_blastoise", using its base resolver variation
## (the one with no aspects). Returns {"geo", "texture", "poser"} paths or {"error"}.
static func base_files(root: String, folder: String) -> Dictionary:
	var resolver_dir := root.path_join(BEDROCK).path_join("resolvers").path_join(folder)
	var resolvers := DirAccess.get_files_at(resolver_dir)
	if resolvers.is_empty():
		return {"error": "no resolver for %s" % folder}
	for resolver_file in resolvers:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(resolver_dir.path_join(resolver_file)))
		if not data is Dictionary:
			continue
		for variation: Dictionary in data.get("variations", []):
			if variation.get("aspects", []).is_empty() and variation.has("model"):
				var geo := root.path_join(BEDROCK).path_join("models").path_join(folder).path_join(
					(variation.model as String).get_slice(":", 1) + ".json")
				if not FileAccess.file_exists(geo):
					return {"error": "%s: model %s not found at %s" % [folder, variation.model, geo]}
				return {
					"geo": geo,
					"texture": resource_path(root, variation.get("texture", "")),
					"poser": (variation.get("poser", "") as String).get_slice(":", 1),
				}
	return {"error": "%s: no base variation with a model" % folder}


## "cobblemon:textures/x.png" -> <root>/assets/cobblemon/textures/x.png
static func resource_path(root: String, id: String) -> String:
	if not id.contains(":"):
		return ""
	return root.path_join("assets").path_join(id.get_slice(":", 0)).path_join(id.get_slice(":", 1))


static func load_texture(path: String) -> Texture2D:
	var image := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	return ImageTexture.create_from_image(image) if image != null else null
