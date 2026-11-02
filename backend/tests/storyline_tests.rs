use chisel_server::storyline::{QuoteEngine, StoryPhase, CRIBSHEET_QUOTES};
use chisel_server::simulation::{SimulationEngine, WorldState};

#[test]
fn test_initial_state_at_zero() {
    let mut engine = SimulationEngine::new();
    let state = engine.tick(0.0);

    assert_eq!(state.phase, StoryPhase::Decanting);
    assert_eq!(state.elapsed_seconds, 0.0);
    assert!((state.town_cohesion - 0.90).abs() < 0.05, "Cohesion should start ~0.90, got {}", state.town_cohesion);
    assert!((state.carl_paranoia - 0.15).abs() < 0.05, "Paranoia should start low ~0.15, got {}", state.carl_paranoia);
    assert!((state.subterranean_pressure - 2.1).abs() < 0.2, "Pressure should start ~2.1 MPa, got {}", state.subterranean_pressure);
    assert_eq!(state.carl_position, (10.0, 10.0), "Carl starts at Decanting Lab (10.0, 10.0)");
    assert!(state.bob_transmission.contains("Clone 01"), "Bob transmission should mention Clone 01: {}", state.bob_transmission);
    assert!(state.bob_transmission.contains("stabilized"), "Bob transmission should mention stabilized: {}", state.bob_transmission);
    assert!(state.chronicler_log.contains("Darran Hollus"), "Chronicler log should mention Darran Hollus: {}", state.chronicler_log);
    assert!(!state.active_quote.is_empty(), "Active quote should not be empty");
}

#[test]
fn test_phase_transitions() {
    let mut engine = SimulationEngine::new();

    // 0s .. 45s: Decanting
    let s0 = engine.tick(0.0);
    assert_eq!(s0.phase, StoryPhase::Decanting);

    let s30 = engine.tick(30.0);
    assert_eq!(s30.phase, StoryPhase::Decanting);

    // 45s .. 140s: MurkWandering
    let s45 = engine.tick(15.0); // total 45.0s
    assert_eq!(s45.phase, StoryPhase::MurkWandering);

    let s60 = engine.tick(15.0); // total 60.0s
    assert_eq!(s60.phase, StoryPhase::MurkWandering);
    assert!(s60.bob_transmission.contains("Amateurs talk strategy, professionals talk logistics"), 
        "Bob transmission should include quote: {}", s60.bob_transmission);

    // 140s .. 165s: TheDig
    let s140 = engine.tick(80.0); // total 140.0s
    assert_eq!(s140.phase, StoryPhase::TheDig);

    let s145 = engine.tick(5.0); // total 145.0s
    assert_eq!(s145.phase, StoryPhase::TheDig);
    assert!(s145.chronicler_log.contains("The optimizer is only as good as its input statistics"),
        "Chronicler log should include quote: {}", s145.chronicler_log);

    // 165s .. 180s: ToxicCollapse
    let s165 = engine.tick(20.0); // total 165.0s
    assert_eq!(s165.phase, StoryPhase::ToxicCollapse);

    let s170 = engine.tick(5.0); // total 170.0s
    assert_eq!(s170.phase, StoryPhase::ToxicCollapse);
    assert!(s170.chronicler_log.contains("Darran killed his son over and over"),
        "Chronicler log should contain Darran quote: {}", s170.chronicler_log);
    assert!(s170.bob_transmission.contains("Fume toxicity critical"),
        "Bob transmission should alert fume toxicity: {}", s170.bob_transmission);

    // >= 180s: ColdReset
    let s180 = engine.tick(10.0); // total 180.0s
    assert_eq!(s180.phase, StoryPhase::ColdReset);
}

#[test]
fn test_metric_dynamics_and_paranoia_rise() {
    let mut engine = SimulationEngine::new();

    let s_0 = engine.tick(0.0);
    let s_60 = engine.tick(60.0);
    let s_145 = engine.tick(85.0); // total 145.0s
    let s_170 = engine.tick(25.0); // total 170.0s

    // Carl paranoia rises monotonically as town cohesion degrades
    assert!(s_60.carl_paranoia > s_0.carl_paranoia, "Paranoia should rise at 60s: {} vs {}", s_60.carl_paranoia, s_0.carl_paranoia);
    assert!(s_145.carl_paranoia > s_60.carl_paranoia, "Paranoia should rise at 145s: {} vs {}", s_145.carl_paranoia, s_60.carl_paranoia);
    assert!(s_170.carl_paranoia >= s_145.carl_paranoia, "Paranoia should peak at 170s: {} vs {}", s_170.carl_paranoia, s_145.carl_paranoia);
    assert!(s_170.carl_paranoia >= 0.90, "Paranoia peaks above 0.90: {}", s_170.carl_paranoia);

    // Town cohesion degrades
    assert!(s_60.town_cohesion < s_0.town_cohesion, "Cohesion degrades at 60s: {} vs {}", s_60.town_cohesion, s_0.town_cohesion);
    assert!(s_145.town_cohesion < s_60.town_cohesion, "Cohesion degrades at 145s: {} vs {}", s_145.town_cohesion, s_60.town_cohesion);
    assert!(s_170.town_cohesion < s_145.town_cohesion, "Cohesion degrades further at 170s: {} vs {}", s_170.town_cohesion, s_145.town_cohesion);

    // Subterranean pressure rises towards fault breach
    assert!(s_60.subterranean_pressure > s_0.subterranean_pressure);
    assert!(s_145.subterranean_pressure > s_60.subterranean_pressure);
    assert!(s_170.subterranean_pressure > s_145.subterranean_pressure);

    // Carl positions progress
    assert_eq!(s_0.carl_position, (10.0, 10.0));
    assert!(s_60.carl_position.0 > 10.0 && s_60.carl_position.0 < 50.0);
    assert!(s_145.carl_position.0 >= 50.0 && s_145.carl_position.0 <= 60.0);
    assert_eq!(s_170.carl_position, (60.0, 60.0));
}

#[test]
fn test_reset_and_clock_rollover_at_180s() {
    let mut engine = SimulationEngine::new();

    let s180 = engine.tick(180.0);
    assert_eq!(s180.phase, StoryPhase::ColdReset);
    assert!(!s180.town_cohesion.is_nan(), "Cohesion must not be NaN");
    assert!(!s180.carl_paranoia.is_nan(), "Paranoia must not be NaN");
    assert!(!s180.subterranean_pressure.is_nan(), "Pressure must not be NaN");
    assert!(!s180.carl_position.0.is_nan(), "Position x must not be NaN");
    assert!(!s180.carl_position.1.is_nan(), "Position y must not be NaN");

    // Next tick resets loop smoothly for Clone 02 preparation
    let s_next = engine.tick(1.0);
    assert_eq!(s_next.phase, StoryPhase::Decanting);
    assert_eq!(s_next.elapsed_seconds, 1.0);
    assert!((s_next.town_cohesion - 0.90).abs() < 0.05);
    assert!((s_next.carl_paranoia - 0.15).abs() < 0.05);
    assert!(s_next.bob_transmission.contains("Clone 02"), "Should indicate Clone 02: {}", s_next.bob_transmission);
}

#[test]
fn test_quotes_pool_and_engine() {
    assert_eq!(CRIBSHEET_QUOTES.len(), 6);

    let required = [
        "There is nothing you can swallow to save, or realise, a mind",
        "Amateurs talk strategy, professionals talk logistics",
        "The optimizer is only as good as its input statistics",
        "Darran killed his son over and over, not just to save him, but to convince himself that any end justified the right means.",
        "Cruel men believe in a cruel god and use their belief to excuse their cruelty.",
        "I looked at him with pity, as if he were a man without any legs. He used to run to me - but now all he did was hunch over his machines in despair.",
    ];

    for req in &required {
        assert!(
            CRIBSHEET_QUOTES.contains(req),
            "CRIBSHEET_QUOTES missing verbatim quote: {}",
            req
        );
    }

    let qe = QuoteEngine::new();
    let q = qe.random_quote();
    assert!(!q.is_empty());
    assert!(CRIBSHEET_QUOTES.contains(&q));

    // Empty pool safety: should not panic
    let empty_qe = QuoteEngine::from_slice(&[]);
    let empty_q = empty_qe.random_quote();
    assert!(!empty_q.is_empty(), "Empty quote engine should return safe fallback quote, not panic");
}

#[test]
fn test_world_state_json_serialization() {
    let mut engine = SimulationEngine::new();
    let state = engine.tick(45.0);

    let json = serde_json::to_string(&state).expect("Serialization to JSON must succeed");
    assert!(json.contains("\"phase\":\"MurkWandering\""));
    assert!(json.contains("\"elapsed_seconds\":45.0"));

    let deserialized: WorldState = serde_json::from_str(&json).expect("Deserialization must succeed");
    assert_eq!(deserialized.phase, StoryPhase::MurkWandering);
    assert_eq!(deserialized.elapsed_seconds, 45.0);
    assert_eq!(deserialized.carl_position, state.carl_position);
}
