#include "swarm_lattice.h"
#include <cassert>
#include <cmath>
#include <iostream>
#include <vector>

namespace {

constexpr float EPSILON = 1e-5f;

bool approx_equal(float a, float b, float eps = EPSILON) {
    return std::fabs(a - b) <= eps;
}

float magnitude(const MorphologyResult &res) {
    return std::sqrt(res.offset_x * res.offset_x +
                     res.offset_y * res.offset_y +
                     res.height_warp * res.height_warp);
}

void test_world_to_iso_origin() {
    std::cout << "  [TEST] world_to_iso at (0, 0)... ";
    IsoCoord res1 = SwarmLattice::world_to_iso(0.0f, 0.0f);
    assert(approx_equal(res1.x, 0.0f));
    assert(approx_equal(res1.y, 0.0f));

    IsoCoord res2 = SwarmLattice::world_to_iso(0.0f, 0.0f, 64.0f, 32.0f);
    assert(approx_equal(res2.x, 0.0f));
    assert(approx_equal(res2.y, 0.0f));

    IsoCoord res3 = SwarmLattice::world_to_iso(0.0f, 0.0f, 128.0f, 64.0f);
    assert(approx_equal(res3.x, 0.0f));
    assert(approx_equal(res3.y, 0.0f));
    std::cout << "PASSED\n";
}

void test_world_to_iso_standard_points() {
    std::cout << "  [TEST] world_to_iso at (10, 10) with tile_w=64, tile_h=32... ";
    IsoCoord res = SwarmLattice::world_to_iso(10.0f, 10.0f, 64.0f, 32.0f);
    // iso_x = (10 - 10) * (64 / 2.0) = 0
    // iso_y = (10 + 10) * (32 / 2.0) = 20 * 16 = 320
    assert(approx_equal(res.x, 0.0f));
    assert(approx_equal(res.y, 320.0f));
    std::cout << "PASSED (iso_x=0, iso_y=320)\n";

    std::cout << "  [TEST] world_to_iso diamond axes symmetry... ";
    // (10, 0): iso_x = (10 - 0)*32 = 320, iso_y = (10 + 0)*16 = 160
    IsoCoord east = SwarmLattice::world_to_iso(10.0f, 0.0f, 64.0f, 32.0f);
    assert(approx_equal(east.x, 320.0f));
    assert(approx_equal(east.y, 160.0f));

    // (0, 10): iso_x = (0 - 10)*32 = -320, iso_y = (0 + 10)*16 = 160
    IsoCoord south = SwarmLattice::world_to_iso(0.0f, 10.0f, 64.0f, 32.0f);
    assert(approx_equal(south.x, -320.0f));
    assert(approx_equal(south.y, 160.0f));

    // (-10, -10): iso_x = 0, iso_y = -320
    IsoCoord north = SwarmLattice::world_to_iso(-10.0f, -10.0f, 64.0f, 32.0f);
    assert(approx_equal(north.x, 0.0f));
    assert(approx_equal(north.y, -320.0f));
    std::cout << "PASSED\n";
}

void test_compute_morphology_nominal_zero_offset() {
    std::cout << "  [TEST] compute_morphology produces 0 offset when cohesion=1.0 and pressure=0.0... ";
    const std::vector<int> sample_blocks = {0, 1, 2, 7, 42, 100, 256, 1024, 1855, 99999};
    for (int block_id : sample_blocks) {
        MorphologyResult res = SwarmLattice::compute_morphology(1.0f, 0.0f, block_id);
        assert(approx_equal(res.offset_x, 0.0f));
        assert(approx_equal(res.offset_y, 0.0f));
        assert(approx_equal(res.height_warp, 0.0f));
        assert(magnitude(res) == 0.0f);
    }
    std::cout << "PASSED (all sample blocks strictly 0 offset)\n";
}

void test_compute_morphology_clamped_stable() {
    std::cout << "  [TEST] compute_morphology clamping on over-stable inputs... ";
    MorphologyResult res1 = SwarmLattice::compute_morphology(1.2f, 0.0f, 42);
    assert(approx_equal(res1.offset_x, 0.0f));
    assert(approx_equal(res1.offset_y, 0.0f));
    assert(approx_equal(res1.height_warp, 0.0f));

    MorphologyResult res2 = SwarmLattice::compute_morphology(1.0f, -1.0f, 42);
    assert(approx_equal(res2.offset_x, 0.0f));
    assert(approx_equal(res2.offset_y, 0.0f));
    assert(approx_equal(res2.height_warp, 0.0f));
    std::cout << "PASSED\n";
}

void test_compute_morphology_progressive_displacement() {
    std::cout << "  [TEST] compute_morphology progressive non-zero displacement (<0.5 cohesion, >3.0 pressure)... ";
    const std::vector<int> sample_blocks = {0, 1, 5, 12, 42, 99, 1855};

    for (int block_id : sample_blocks) {
        // Cohesion < 0.5 (e.g. 0.4), Pressure > 3.0 (e.g. 3.5)
        MorphologyResult res_decayed = SwarmLattice::compute_morphology(0.4f, 3.5f, block_id);
        float mag = magnitude(res_decayed);
        assert(mag > 0.05f); // Non-zero displacement guaranteed
        assert(res_decayed.offset_x != 0.0f || res_decayed.offset_y != 0.0f || res_decayed.height_warp != 0.0f);

        // Progressiveness check: Displacement increases monotonically with rising stress
        MorphologyResult s0 = SwarmLattice::compute_morphology(1.0f, 0.0f, block_id); // nominal
        MorphologyResult s1 = SwarmLattice::compute_morphology(0.7f, 1.5f, block_id); // moderate
        MorphologyResult s2 = SwarmLattice::compute_morphology(0.4f, 3.5f, block_id); // high stress (<0.5, >3.0)
        MorphologyResult s3 = SwarmLattice::compute_morphology(0.1f, 5.0f, block_id); // critical surge

        float m0 = magnitude(s0);
        float m1 = magnitude(s1);
        float m2 = magnitude(s2);
        float m3 = magnitude(s3);

        assert(m0 == 0.0f);
        assert(m1 > m0);
        assert(m2 > m1);
        assert(m3 > m2);
    }
    std::cout << "PASSED (strictly progressive displacement)\n";
}

void test_morphology_1855_swarm_blocks() {
    std::cout << "  [TEST] compute_morphology over full 1855 swarm blocks... ";
    for (int block_id = 0; block_id < 1855; ++block_id) {
        MorphologyResult res = SwarmLattice::compute_morphology(0.35f, 4.2f, block_id);
        assert(!std::isnan(res.offset_x) && !std::isinf(res.offset_x));
        assert(!std::isnan(res.offset_y) && !std::isinf(res.offset_y));
        assert(!std::isnan(res.height_warp) && !std::isinf(res.height_warp));

        float mag = magnitude(res);
        assert(mag > 0.05f);

        // Determinism test: duplicate call yields identical values
        MorphologyResult res_repeat = SwarmLattice::compute_morphology(0.35f, 4.2f, block_id);
        assert(res.offset_x == res_repeat.offset_x);
        assert(res.offset_y == res_repeat.offset_y);
        assert(res.height_warp == res_repeat.height_warp);
    }
    std::cout << "PASSED (1855 blocks verified: robust, non-zero, deterministic)\n";
}

void test_instance_and_static_interop() {
    std::cout << "  [TEST] SwarmLattice instance vs static method consistency... ";
    SwarmLattice lattice;
    IsoCoord c1 = SwarmLattice::world_to_iso(5.0f, 8.0f, 64.0f, 32.0f);
    IsoCoord c2 = lattice.world_to_iso(5.0f, 8.0f, 64.0f, 32.0f);
    assert(c1.x == c2.x && c1.y == c2.y);

    MorphologyResult m1 = SwarmLattice::compute_morphology(0.5f, 2.0f, 12);
    MorphologyResult m2 = lattice.compute_morphology(0.5f, 2.0f, 12);
    assert(m1.offset_x == m2.offset_x && m1.offset_y == m2.offset_y && m1.height_warp == m2.height_warp);
    std::cout << "PASSED\n";
}

} // namespace

int main() {
    std::cout << "=== Running SwarmLattice C++ Unit Tests ===\n";
    test_world_to_iso_origin();
    test_world_to_iso_standard_points();
    test_compute_morphology_nominal_zero_offset();
    test_compute_morphology_clamped_stable();
    test_compute_morphology_progressive_displacement();
    test_morphology_1855_swarm_blocks();
    test_instance_and_static_interop();
    std::cout << "=== All SwarmLattice C++ tests PASSED successfully! ===\n";
    return 0;
}
