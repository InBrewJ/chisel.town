#include "swarm_lattice.h"
#include <algorithm>
#include <cmath>

#ifdef GODOT_GDEXTENSION
namespace godot {

void SwarmLattice::_bind_methods() {
    ClassDB::bind_method(D_METHOD("world_to_iso", "x", "y", "tile_w", "tile_h"), &SwarmLattice::world_to_iso_gd, DEFVAL(64.0), DEFVAL(32.0));
    ClassDB::bind_method(D_METHOD("compute_morphology", "cohesion", "pressure", "block_id"), &SwarmLattice::compute_morphology_gd, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("compute_morphology_vec", "cohesion", "pressure", "block_id"), &SwarmLattice::compute_morphology_vec, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("compute_morphology_array", "cohesion", "pressure", "block_id"), &SwarmLattice::compute_morphology_array, DEFVAL(0));
}

} // namespace godot
#endif

#ifdef GODOT_GDEXTENSION
using namespace godot;
#endif

IsoCoord SwarmLattice::world_to_iso(float x, float y, float tile_w, float tile_h) {
    IsoCoord result;
    result.x = (x - y) * (tile_w / 2.0f);
    result.y = (x + y) * (tile_h / 2.0f);
    return result;
}

MorphologyResult SwarmLattice::compute_morphology(float cohesion, float pressure, int block_id) {
    // Nominal baseline: cohesion = 1.0 (fully stable), pressure = 0.0 (no subterranean stress).
    // Factors are clamped at 0.0 to prevent negative degradation.
    float decay_factor = std::max(0.0f, 1.0f - cohesion);
    float pressure_factor = std::max(0.0f, pressure);

    // If perfectly stable (nominal baseline), displacement is strictly zero
    if (decay_factor == 0.0f && pressure_factor == 0.0f) {
        return {0.0f, 0.0f, 0.0f};
    }

    // Deterministic murmur-style hash of block_id to obtain well-distributed spatial phase angles
    uint32_t u = static_cast<uint32_t>(block_id) + 0x9e3779b9u;
    u ^= u >> 16;
    u *= 0x45d9f3bu;
    u ^= u >> 16;
    u *= 0x45d9f3bu;
    u ^= u >> 16;

    // Map to spherical distribution: azimuth phi in [0, 2*pi), polar angle theta in [0.15*pi, 0.85*pi]
    constexpr float TWO_PI = 6.28318530717958647692f;
    constexpr float PI = 3.14159265358979323846f;

    float phi = (static_cast<float>(u & 0xFFFF) / 65536.0f) * TWO_PI;
    // Bounding theta ensures non-zero projection on both lateral and vertical axes
    float theta = 0.15f * PI + ((static_cast<float>((u >> 16) & 0xFFFF) / 65536.0f) * 0.70f * PI);

    float dir_x = std::sin(theta) * std::cos(phi);
    float dir_y = std::sin(theta) * std::sin(phi);
    float dir_z = std::cos(theta);

    // Lateral amplitude: driven heavily by decay factor (cohesion degradation loosening blocks)
    // with secondary coupling to subterranean pressure
    float lateral_amplitude = decay_factor * 3.5f + pressure_factor * 0.5f;

    // Vertical amplitude: driven heavily by subterranean pressure (uplift/heave)
    // with secondary coupling to structural settling
    float vertical_amplitude = pressure_factor * 1.8f + decay_factor * 0.8f;

    MorphologyResult result;
    result.offset_x = dir_x * lateral_amplitude;
    result.offset_y = dir_y * lateral_amplitude * 0.5f; // 2:1 isometric aspect ratio
    result.height_warp = dir_z * vertical_amplitude;

    return result;
}
