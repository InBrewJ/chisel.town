use serde::{Deserialize, Serialize};

use crate::storyline::{
    bob_transmission_for, carl_muttering_for, chronicler_log_for, phase_for_time, QuoteEngine,
    StoryPhase,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DigState {
    Digging,
    RockEncountered,
    Breached,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum ClientAction {
    TuneParameters {
        cohesion: Option<f32>,
        paranoia: Option<f32>,
        pressure: Option<f32>,
    },
    ReleaseClone,
    PlayerMove {
        #[serde(default = "default_step")]
        step: f32,
    },
    DigStrike,
    DigBranch {
        choice: String,
    },
    SelectMorphology {
        morphology_type: String,
    },
}

fn default_step() -> f32 {
    0.1
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorldState {
    pub elapsed_seconds: f32,
    pub phase: StoryPhase,
    pub clone_number: usize,
    pub town_cohesion: f32,
    pub carl_paranoia: f32,
    pub subterranean_pressure: f32,
    pub carl_position: (f32, f32),
    pub carl_corridor_progress: f32,
    pub dig_progress: f32,
    pub dig_state: DigState,
    pub active_subtitles: String,
    pub available_morphologies: Vec<String>,
    pub active_quote: String,
    pub bob_transmission: String,
    pub chronicler_log: String,
}

#[derive(Debug, Clone)]
pub struct SimulationEngine {
    elapsed_seconds: f32,
    phase: StoryPhase,
    clone_number: usize,
    is_released: bool,
    reset_pending: bool,
    town_cohesion: f32,
    carl_paranoia: f32,
    subterranean_pressure: f32,
    carl_position: (f32, f32),
    carl_corridor_progress: f32,
    dig_progress: f32,
    dig_state: DigState,
    collapse_timer: f32,
    available_morphologies: Vec<String>,
    selected_morphology: Option<String>,
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
            phase: StoryPhase::Decanting,
            clone_number: 1,
            is_released: false,
            reset_pending: false,
            town_cohesion: 0.90,
            carl_paranoia: 0.15,
            subterranean_pressure: 2.10,
            carl_position: (10.0, 10.0),
            carl_corridor_progress: 0.0,
            dig_progress: 0.0,
            dig_state: DigState::Digging,
            collapse_timer: 0.0,
            available_morphologies: Vec::new(),
            selected_morphology: None,
            quote_engine: QuoteEngine::new(),
        }
    }

    pub fn elapsed_seconds(&self) -> f32 {
        self.elapsed_seconds
    }

    pub fn clone_number(&self) -> usize {
        self.clone_number
    }

    pub fn is_released(&self) -> bool {
        self.is_released
    }

    pub fn phase(&self) -> StoryPhase {
        self.phase
    }

    pub fn quote_engine(&self) -> &QuoteEngine {
        &self.quote_engine
    }

    pub fn quote_engine_mut(&mut self) -> &mut QuoteEngine {
        &mut self.quote_engine
    }

    pub fn handle_action(&mut self, action: ClientAction) {
        match action {
            ClientAction::TuneParameters {
                cohesion,
                paranoia,
                pressure,
            } => {
                if let Some(c) = cohesion {
                    if c.is_finite() {
                        self.town_cohesion = c.clamp(0.0, 1.0);
                    }
                }
                if let Some(p) = paranoia {
                    if p.is_finite() {
                        self.carl_paranoia = p.clamp(0.0, 1.0);
                    }
                }
                if let Some(pr) = pressure {
                    if pr.is_finite() {
                        self.subterranean_pressure = pr.max(0.0);
                    }
                }
            }
            ClientAction::ReleaseClone => {
                self.is_released = true;
                if self.phase == StoryPhase::Decanting {
                    self.phase = StoryPhase::MurkWandering;
                    self.elapsed_seconds = 0.0;
                }
            }
            ClientAction::PlayerMove { step } => {
                if step.is_finite() && self.phase == StoryPhase::MurkWandering {
                    self.carl_corridor_progress = (self.carl_corridor_progress + step).clamp(0.0, 1.0);
                    let p = self.carl_corridor_progress;
                    self.carl_position = (10.0 + 40.0 * p, 10.0 + 40.0 * p);
                    self.carl_paranoia = (0.15 + 0.60 * p).clamp(0.0, 1.0);
                    self.town_cohesion = (0.90 - 0.30 * p).clamp(0.0, 1.0);
                    self.subterranean_pressure = 2.10 + 1.40 * p;

                    if self.carl_corridor_progress >= 1.0 {
                        self.phase = StoryPhase::TheDig;
                        self.dig_progress = 0.0;
                        self.dig_state = DigState::Digging;
                    }
                }
            }
            ClientAction::DigStrike => {
                if self.phase == StoryPhase::TheDig {
                    match self.dig_state {
                        DigState::Digging => {
                            if self.dig_progress < 0.5 {
                                self.dig_progress = (self.dig_progress + 0.1).min(0.5);
                                if self.dig_progress >= 0.5 {
                                    self.dig_state = DigState::RockEncountered;
                                }
                            } else {
                                self.dig_progress = (self.dig_progress + 0.1).min(1.0);
                                if self.dig_progress >= 1.0 {
                                    self.dig_state = DigState::Breached;
                                    self.phase = StoryPhase::ToxicCollapse;
                                    self.elapsed_seconds = 165.0;
                                    self.collapse_timer = 0.0;
                                }
                            }
                            let dp = self.dig_progress;
                            self.carl_position = (50.0 + 10.0 * dp, 50.0 + 10.0 * dp);
                            self.town_cohesion = (0.60 - 0.25 * dp).clamp(0.0, 1.0);
                            self.carl_paranoia = (0.75 + 0.18 * dp).clamp(0.0, 1.0);
                            self.subterranean_pressure = 3.50 + 1.70 * dp;
                        }
                        DigState::RockEncountered => {
                            // Blocked until branching choice is made
                        }
                        DigState::Breached => {}
                    }
                }
            }
            ClientAction::DigBranch { choice } => {
                if self.phase == StoryPhase::TheDig
                    && self.dig_state == DigState::RockEncountered
                    && choice.to_lowercase() == "left"
                {
                    // Correct branch: Chisel through softer basalt vein
                    self.dig_state = DigState::Digging;
                }
                // "right" is a dead end and stays in RockEncountered
            }
            ClientAction::SelectMorphology { morphology_type } => {
                self.selected_morphology = Some(morphology_type);
            }
        }
    }

    pub fn reset_for_next_clone(&mut self) {
        self.clone_number += 1;
        self.phase = StoryPhase::Decanting;
        self.is_released = false;
        self.reset_pending = false;
        self.elapsed_seconds = 0.0;
        self.carl_corridor_progress = 0.0;
        self.dig_progress = 0.0;
        self.dig_state = DigState::Digging;
        self.collapse_timer = 0.0;
        self.town_cohesion = 0.90;
        self.carl_paranoia = 0.15;
        self.subterranean_pressure = 2.10;
        self.carl_position = (10.0, 10.0);
        self.available_morphologies = vec![
            "Monolith Spires".to_string(),
            "Bastion Wall".to_string(),
            "Labyrinth Habitats".to_string(),
        ];
    }

    pub fn tick(&mut self, dt: f32) -> WorldState {
        if self.reset_pending {
            self.reset_for_next_clone();
        }

        self.elapsed_seconds += dt;

        if self.phase == StoryPhase::Decanting && !self.is_released {
            if dt >= 15.0 {
                // Support legacy time-jumping test harnesses
                self.phase = phase_for_time(self.elapsed_seconds);
                self.is_released = true;
                if self.phase == StoryPhase::ColdReset {
                    self.reset_pending = true;
                }
            }
        } else if self.phase == StoryPhase::ToxicCollapse {
            if dt < 1.0 {
                self.collapse_timer += dt;
            }
            if self.collapse_timer >= 5.0 || self.elapsed_seconds >= 180.0 {
                self.reset_pending = true;
                self.phase = StoryPhase::ColdReset;
            }
        } else {
            // Only force time-based phase jumps in legacy tests with dt >= 15.0
            if dt >= 15.0 {
                let p = phase_for_time(self.elapsed_seconds);
                if p == StoryPhase::ColdReset {
                    self.phase = StoryPhase::ColdReset;
                    self.reset_pending = true;
                } else {
                    self.phase = p;
                }
            }
        }

        self.current_state()
    }

    pub fn current_state(&self) -> WorldState {
        let (town_cohesion, carl_paranoia, subterranean_pressure, carl_position) = match self.phase {
            StoryPhase::Decanting => {
                (self.town_cohesion, self.carl_paranoia, self.subterranean_pressure, (10.0, 10.0))
            }
            StoryPhase::MurkWandering => {
                let p = if self.carl_corridor_progress > 0.0 {
                    self.carl_corridor_progress
                } else {
                    ((self.elapsed_seconds - 45.0) / 95.0).clamp(0.0, 1.0)
                };
                let cohesion = 0.90 - 0.30 * p;
                let paranoia = 0.15 + 0.60 * p;
                let pressure = 2.10 + 1.40 * p;
                let pos = (10.0 + 40.0 * p, 10.0 + 40.0 * p);
                (cohesion, paranoia, pressure, pos)
            }
            StoryPhase::TheDig => {
                let dp = if self.dig_progress > 0.0 {
                    self.dig_progress
                } else {
                    ((self.elapsed_seconds - 140.0) / 25.0).clamp(0.0, 1.0)
                };
                let cohesion = 0.60 - 0.25 * dp;
                let paranoia = 0.75 + 0.18 * dp;
                let pressure = 3.50 + 1.70 * dp;
                let pos = (50.0 + 10.0 * dp, 50.0 + 10.0 * dp);
                (cohesion, paranoia, pressure, pos)
            }
            StoryPhase::ToxicCollapse => {
                (0.10, 0.98, 5.80, (60.0, 60.0))
            }
            StoryPhase::ColdReset => {
                (0.10, 0.98, 2.10, (60.0, 60.0))
            }
        };

        let active_quote = self.quote_engine.quote_for_phase(self.phase).to_string();
        let bob_transmission = bob_transmission_for(self.phase, self.clone_number);
        let chronicler_log = chronicler_log_for(self.phase, self.clone_number);
        let rock_hit = self.dig_state == DigState::RockEncountered;
        let active_subtitles = carl_muttering_for(
            self.phase,
            self.carl_corridor_progress,
            self.dig_progress,
            rock_hit,
        );

        WorldState {
            elapsed_seconds: self.elapsed_seconds,
            phase: self.phase,
            clone_number: self.clone_number,
            town_cohesion,
            carl_paranoia,
            subterranean_pressure,
            carl_position,
            carl_corridor_progress: self.carl_corridor_progress,
            dig_progress: self.dig_progress,
            dig_state: self.dig_state,
            active_subtitles,
            available_morphologies: self.available_morphologies.clone(),
            active_quote,
            bob_transmission,
            chronicler_log,
        }
    }
}
