class_name ErrorCounter
extends Logger
## Collects errors Godot logs while it's installed (OS.add_logger). GDScript runtime errors
## don't propagate to the caller: the failing call returns a default value and execution
## goes on. The test runner and the asset pipeline use this to notice them anyway.

var errors: PackedStringArray = []


func _log_error(function: String, file: String, line: int, code: String,
		rationale: String, _editor_notify: bool, _error_type: int,
		_script_backtrace: Array[ScriptBacktrace]) -> void:
	errors.append("%s (%s:%d in %s)" % [rationale if not rationale.is_empty() else code, file, line, function])


func _log_message(_message: String, _error: bool) -> void:
	pass
