#ifndef REGISTER_TYPES_H
#define REGISTER_TYPES_H

#ifdef GODOT_GDEXTENSION
#include <godot_cpp/core/class_db.hpp>

void initialize_swarm_core_module(godot::ModuleInitializationLevel p_level);
void uninitialize_swarm_core_module(godot::ModuleInitializationLevel p_level);
#else
void initialize_swarm_core_module(int p_level);
void uninitialize_swarm_core_module(int p_level);
#endif

#endif // REGISTER_TYPES_H
