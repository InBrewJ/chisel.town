use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum StoryPhase {
    Decanting,
    MurkWandering,
    TheDig,
    ToxicCollapse,
    ColdReset,
}

pub const CRIBSHEET_QUOTES: &[&str] = &[
    "There is nothing you can swallow to save, or realise, a mind",
    "Amateurs talk strategy, professionals talk logistics",
    "The optimizer is only as good as its input statistics",
    "Darran killed his son over and over, not just to save him, but to convince himself that any end justified the right means.",
    "Cruel men believe in a cruel god and use their belief to excuse their cruelty.",
    "I looked at him with pity, as if he were a man without any legs. He used to run to me - but now all he did was hunch over his machines in despair.",
];

#[derive(Debug, Clone)]
pub struct QuoteEngine {
    quotes: Vec<String>,
}

impl Default for QuoteEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl QuoteEngine {
    pub fn new() -> Self {
        Self {
            quotes: CRIBSHEET_QUOTES.iter().map(|&s| s.to_string()).collect(),
        }
    }

    pub fn from_slice(quotes: &[&str]) -> Self {
        Self {
            quotes: quotes.iter().map(|&s| s.to_string()).collect(),
        }
    }

    pub fn random_quote(&self) -> &str {
        if self.quotes.is_empty() {
            return "The optimizer watches in silence.";
        }
        use rand::seq::SliceRandom;
        let mut rng = rand::thread_rng();
        self.quotes
            .choose(&mut rng)
            .map(|s| s.as_str())
            .unwrap_or("The optimizer watches in silence.")
    }

    pub fn quote_for_phase(&self, phase: StoryPhase) -> &str {
        match phase {
            StoryPhase::Decanting => {
                "Cruel men believe in a cruel god and use their belief to excuse their cruelty."
            }
            StoryPhase::MurkWandering => {
                "There is nothing you can swallow to save, or realise, a mind"
            }
            StoryPhase::TheDig => "The optimizer is only as good as its input statistics",
            StoryPhase::ToxicCollapse => {
                "Darran killed his son over and over, not just to save him, but to convince himself that any end justified the right means."
            }
            StoryPhase::ColdReset => {
                "I looked at him with pity, as if he were a man without any legs. He used to run to me - but now all he did was hunch over his machines in despair."
            }
        }
    }

    pub fn quotes(&self) -> &[String] {
        &self.quotes
    }
}

pub fn phase_for_time(elapsed_seconds: f32) -> StoryPhase {
    if elapsed_seconds >= 180.0 {
        StoryPhase::ColdReset
    } else if elapsed_seconds >= 165.0 {
        StoryPhase::ToxicCollapse
    } else if elapsed_seconds >= 140.0 {
        StoryPhase::TheDig
    } else if elapsed_seconds >= 45.0 {
        StoryPhase::MurkWandering
    } else {
        StoryPhase::Decanting
    }
}

pub fn bob_transmission_for(phase: StoryPhase, clone_num: usize) -> String {
    match phase {
        StoryPhase::Decanting => {
            format!("Decanting cycle complete. Clone {:02} stabilized.", clone_num)
        }
        StoryPhase::MurkWandering => {
            "Sarah left her key on the bench, Darran. Amateurs talk strategy, professionals talk logistics. He's heading straight for the murk.".to_string()
        }
        StoryPhase::TheDig => {
            "Fault line fracture detected. Carl is excavating the sealed barrier. Subterranean pressure critical.".to_string()
        }
        StoryPhase::ToxicCollapse => {
            format!(
                "Fume toxicity critical. Clone {:02} is non-responsive. Preparing containment.",
                clone_num
            )
        }
        StoryPhase::ColdReset => {
            format!(
                "Cold reset initiated. Purging chamber. Preparing Clone {:02}.",
                clone_num + 1
            )
        }
    }
}

pub fn chronicler_log_for(phase: StoryPhase, clone_num: usize) -> String {
    match phase {
        StoryPhase::Decanting => {
            format!(
                "Darran Hollus initializes experiment cycle. Clone {:02} released into containment quadrant.",
                clone_num
            )
        }
        StoryPhase::MurkWandering => {
            "Carl deviates toward the western fissure. The subterranean seepage exerts an inexplicable draw.".to_string()
        }
        StoryPhase::TheDig => {
            "The optimizer is only as good as its input statistics. We alter the nurture until the outcome inverts.".to_string()
        }
        StoryPhase::ToxicCollapse => {
            "Darran killed his son over and over, not just to save him, but to convince himself that any end justified the right means.".to_string()
        }
        StoryPhase::ColdReset => {
            format!(
                "Clone {:02} decommissioned. Memory imprint logged for optimizer adjustment.",
                clone_num
            )
        }
    }
}

pub fn carl_muttering_for(phase: StoryPhase, corridor_p: f32, dig_p: f32, rock_hit: bool) -> String {
    match phase {
        StoryPhase::Decanting => {
            "Amniotic nutrient circulation steady. Awaiting release vector...".to_string()
        }
        StoryPhase::MurkWandering => {
            if corridor_p < 0.35 {
                "The fog... it smells like kerosene and scorched iron. Just keep walking through the buildings.".to_string()
            } else if corridor_p < 0.75 {
                "Father said stay within the inner quadrant. But the humming beneath the bricks... it calls.".to_string()
            } else {
                "Almost at the hazard fissure. Shovel is gripped tight in hand. I have to break through.".to_string()
            }
        }
        StoryPhase::TheDig => {
            if rock_hit {
                "CLANG! Hard bedrock encountered! The seam splits: left basalt vein looks softer, right fault looks fractured.".to_string()
            } else if dig_p < 0.4 {
                "Dig! Strike the gravel! Clear the loose soot before the tremors collapse the tunnel!".to_string()
            } else if dig_p < 0.8 {
                "The pick bites into the dark rock. Black sweat in my eyes... faster!".to_string()
            } else {
                "Cracks spreading! Black viscous oil is weeping through the seam... one final blow!".to_string()
            }
        }
        StoryPhase::ToxicCollapse => {
            "The barrier ruptured! It's flooding! DARRAN!... Father! Cold... black... *choking*".to_string()
        }
        StoryPhase::ColdReset => {
            "Telemetry flatlined. Purging quadrant for subsequent iteration.".to_string()
        }
    }
}
