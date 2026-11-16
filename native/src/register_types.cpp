// Registers the native move-effect classes (concepts_brief.md §12.5).
#include "snowstorm_core.h"
#include "snowstorm_program.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static void initialize(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(snowstorm::SnowstormProgram);
	GDREGISTER_CLASS(snowstorm::SnowstormCore);
}

static void uninitialize(ModuleInitializationLevel level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT cobbleseum_native_init(GDExtensionInterfaceGetProcAddress get_proc_address,
		const GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
	GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
	init.register_initializer(initialize);
	init.register_terminator(uninitialize);
	init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init.init();
}
}
