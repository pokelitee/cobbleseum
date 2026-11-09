extends RefCounted
## Build step for the Showdown source: exports its data modules to JSON (concepts_brief.md §5.1).
## Showdown ships data as compiled JavaScript, so this is the one place the project needs Node.js.

const MIN_NODE_MAJOR := 20
const EXPORT_SCRIPT := "res://tools/sources/showdown_export.mjs"
## Extra files whose changes invalidate the build stamp.
const DEPENDENCIES: Array[String] = [EXPORT_SCRIPT]


func build(source_dir: String, out_dir: String) -> String:
	var output: Array = []
	if OS.execute("node", ["--version"], output, true) != 0:
		return "Node.js %d or later is required for the Showdown export, but `node --version` failed. Install Node.js and make sure `node` is on PATH." % MIN_NODE_MAJOR
	var version := str(output[0]).strip_edges()
	var major := version.trim_prefix("v").get_slice(".", 0).to_int()
	if major < MIN_NODE_MAJOR:
		return "Node.js %d or later is required for the Showdown export; found %s" % [MIN_NODE_MAJOR, version]
	output.clear()
	var args := [
		ProjectSettings.globalize_path(EXPORT_SCRIPT),
		source_dir.path_join("package/dist/data"),
		out_dir,
	]
	if OS.execute("node", args, output, true) != 0:
		return "Showdown data export failed:\n%s" % "".join(output).strip_edges()
	return ""
