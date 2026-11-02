#ifndef SWARM_LATTICE_H
#define SWARM_LATTICE_H

#include <cmath>
#include <cstdint>

#ifdef GODOT_GDEXTENSION
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>

namespace godot {
#endif

// 2D Isometric coordinate output structure
struct IsoCoord {
    float x = 0.0f;
    float y = 0.0f;

    bool operator==(const IsoCoord &other) const {
        return x == other.x && y == other.y;
    }
    bool operator!=(const IsoCoord &other) const {
        return !(*this == other);
    }
};

using IsoVec2 = IsoCoord;

// Procedural morphology result containing lateral jitter and vertical height warp
struct MorphologyResult {
    float offset_x = 0.0f;
    float offset_y = 0.0f;
    float height_warp = 0.0f;

    bool operator==(const MorphologyResult &other) const {
        return offset_x == other.offset_x &&
               offset_y == other.offset_y &&
               height_warp == other.height_warp;
    }
    bool operator!=(const MorphologyResult &other) const {
        return !(*this == other);
    }
};

class SwarmLattice
#ifdef GODOT_GDEXTENSION
    : public RefCounted
#endif
{
#ifdef GODOT_GDEXTENSION
    GDCLASS(SwarmLattice, RefCounted);

protected:
    static void _bind_methods();
#endif

public:
    SwarmLattice() = default;
    ~SwarmLattice() = default;

    /**
     * Converts 2D cartesian grid coordinates to 2:1 isometric screen space.
     * Formula:
     *   iso_x = (x - y) * (tile_w / 2.0)
     *   iso_y = (x + y) * (tile_h / 2.0)
     */
    static IsoCoord world_to_iso(float x, float y, float tile_w = 64.0f, float tile_h = 32.0f);

    /**
     * Computes procedural jitter, structural degradation, and height shift for 1855 swarm blocks
     * based on falling cohesion (instability) and rising subterranean pressure.
     *
     * - cohesion: nominal 1.0 (stable) down to 0.0 (total decay).
     * - pressure: nominal 0.0 (stable) up to 5.0+ bar (extreme subterranean surge).
     * - block_id: deterministic seed for spatial/procedural variation.
     */
    static MorphologyResult compute_morphology(float cohesion, float pressure, int block_id = 0);

#ifdef GODOT_GDEXTENSION
    // Godot ClassDB binding wrappers for GDScript interoperability
    Vector2 world_to_iso_gd(float x, float y, float tile_w = 64.0f, float tile_h = 32.0f) const {
        IsoCoord c = world_to_iso(x, y, tile_w, tile_h);
        return Vector2(c.x, c.y);
    }

    Dictionary compute_morphology_gd(float cohesion, float pressure, int block_id = 0) const {
        MorphologyResult res = compute_morphology(cohesion, pressure, block_id);
        Dictionary d;
        d["offset_x"] = res.offset_x;
        d["offset_y"] = res.offset_y;
        d["height_warp"] = res.height_warp;
        d["x"] = res.offset_x;
        d["y"] = res.offset_y;
        d["z"] = res.height_warp;
        return d;
    }

    Vector3 compute_morphology_vec(float cohesion, float pressure, int block_id = 0) const {
        MorphologyResult res = compute_morphology(cohesion, pressure, block_id);
        return Vector3(res.offset_x, res.offset_y, res.height_warp);
    }

    Array compute_morphology_array(float cohesion, float pressure, int block_id = 0) const {
        MorphologyResult res = compute_morphology(cohesion, pressure, block_id);
        Array a;
        a.push_back(res.offset_x);
        a.push_back(res.offset_y);
        a.push_back(res.height_warp);
        return a;
    }
#endif
};

#ifdef GODOT_GDEXTENSION
} // namespace godot
#endif

#endif // SWARM_LATTICE_H
