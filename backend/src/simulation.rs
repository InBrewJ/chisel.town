use serde::{Deserialize, Serialize};

use crate::storyline::{
    bob_transmission_for, chronicler_log_for, phase_for_time, QuoteEngine, StoryPhase,
};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorldState {
    pub elapsed_seconds: f32,
    pub phase: StoryPhase,
    pub town_cohesion: f32,
    pub carl_paranoia: f32,
    pub subterranean_pressure: f32,
    pub carl_position: (f32, f32),
    pub active_quote: String,
    pub bob_transmission: String,
    pub chronicler_log: String,
}

#[derive(Debug, Clone)]
pub struct SimulationEngine {
    elapsed_seconds: f32,
    clone_number: usize,
    reset_pending: bool,
    quote_engine: QuoteEngine,
}

impl Default for SimulationEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl SimulationEngine {
    pub fn new() -> Self {
        Self {
            elapsed_seconds: 0.0,
            clone_number: 1,
            reset_pending: false,
            quote_engine: QuoteEngine::new(),
        }
    }

    pub fn elapsed_seconds(&self) -> f32 {
        self.elapsed_seconds
    }

    pub fn clone_number(&self) -> usize {
        self.clone_number
    }

    pub fn phase(&self) -> StoryPhase {
        phase_for_time(self.elapsed_seconds)
    }

    pub fn quote_engine(&self) -> &QuoteEngine {
        &self.quote_engine
    }

    pub fn quote_engine_mut(&mut self) -> &mut QuoteEngine {
        &mut self.quote_engine
    }

    pub fn reset(&mut self) {
        self.elapsed_seconds = 0.0;
        self.clone_number += 1;
        self.reset_pending = false;
    }

    pub fn tick(&mut self, dt: f32) -> WorldState {
        if self.reset_pending {
            self.reset();
        }

        self.elapsed_seconds += dt;

        let phase = phase_for_time(self.elapsed_seconds);

        if phase == StoryPhase::ColdReset {
            self.reset_pending = true;
        }

        self.generate_world_state(phase)
    }

    pub fn current_state(&self) -> WorldState {
        self.generate_world_state(self.phase())
    }

    fn generate_world_state(&self, phase: StoryPhase) -> WorldState {
        let t = self.elapsed_seconds;

        let (town_cohesion, carl_paranoia, subterranean_pressure, carl_position) = match phase {
            StoryPhase::Decanting => {
                // 0.0s .. 45.0s:
                // Cohesion stable ~0.90, Paranoia low ~0.15, Pressure baseline ~2.1 MPa
                // Carl at Decanting Lab (10.0, 10.0)
                (0.90, 0.15, 2.10, (10.0, 10.0))
            }
            StoryPhase::MurkWandering => {
                // 45.0s .. 140.0s (span: 95.0s)
                let p = ((t - 45.0) / 95.0).clamp(0.0, 1.0);
                let cohesion = 0.90 - 0.30 * p; // 0.90 -> 0.60
                let paranoia = 0.15 + 0.60 * p; // 0.15 -> 0.75
                let pressure = 2.10 + 1.40 * p; // 2.10 -> 3.50 MPa
                let pos_x = 10.0 + 40.0 * p;     // 10.0 -> 50.0
                let pos_y = 10.0 + 40.0 * p;     // 10.0 -> 50.0
                (cohesion, paranoia, pressure, (pos_x, pos_y))
            }
            StoryPhase::TheDig => {
                // 140.0s .. 165.0s (span: 25.0s)
                let p = ((t - 140.0) / 25.0).clamp(0.0, 1.0);
                let cohesion = 0.60 - 0.25 * p; // 0.60 -> 0.35
                let paranoia = 0.75 + 0.18 * p; // 0.75 -> 0.93
                let pressure = 3.50 + 1.70 * p; // 3.50 -> 5.20 MPa
                let pos_x = 50.0 + 10.0 * p;    // 50.0 -> 60.0
                let pos_y = 50.0 + 10.0 * p;    // 50.0 -> 60.0
                (cohesion, paranoia, pressure, (pos_x, pos_y))
            }
            StoryPhase::ToxicCollapse => {
                // 165.0s .. 180.0s (span: 15.0s)
                let p = ((t - 165.0) / 15.0).clamp(0.0, 1.0);
                let cohesion = 0.35 - 0.25 * p; // 0.35 -> 0.10
                let paranoia = 0.93 + 0.05 * p; // 0.93 -> 0.98
                let pressure = 5.20 + 0.60 * p; // 5.20 -> 5.80 MPa
                (cohesion, paranoia, pressure, (60.0, 60.0))
            }
            StoryPhase::ColdReset => {
                // Smooth reset baseline metrics, ensuring finite numbers and zero NaN
                (0.10, 0.98, 2.10, (60.0, 60.0))
            }
        };

        let active_quote = self.quote_engine.quote_for_phase(phase).to_string();
        let bob_transmission = bob_transmission_for(phase, self.clone_number);
        let chronicler_log = chronicler_log_for(phase, self.clone_number);

        WorldState {
            elapsed_seconds: self.elapsed_seconds,
            phase,
            town_cohesion,
            carl_paranoia,
            subterranean_pressure,
            carl_position,
            active_quote,
            bob_transmission,
            chronicler_log,
        }
    }
}
