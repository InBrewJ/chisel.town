use chisel_server::simulation::{ClientAction, DigState, SimulationEngine};
use chisel_server::storyline::StoryPhase;

#[test]
fn test_decanting_pauses_until_release() {
    let mut engine = SimulationEngine::new();
    assert_eq!(engine.phase(), StoryPhase::Decanting);
    assert!(!engine.is_released());

    // Multiple ticks should not advance to MurkWandering without release
    for _ in 0..100 {
        let state = engine.tick(0.1);
        assert_eq!(state.phase, StoryPhase::Decanting);
        assert_eq!(state.carl_corridor_progress, 0.0);
    }

    // Tune parameters
    engine.handle_action(ClientAction::TuneParameters {
        cohesion: Some(0.82),
        paranoia: Some(0.25),
        pressure: Some(2.45),
    });
    let state = engine.current_state();
    assert!((state.town_cohesion - 0.82).abs() < 1e-4);
    assert!((state.carl_paranoia - 0.25).abs() < 1e-4);
    assert!((state.subterranean_pressure - 2.45).abs() < 1e-4);

    // Release clone
    engine.handle_action(ClientAction::ReleaseClone);
    assert!(engine.is_released());

    let state = engine.tick(0.1);
    assert_eq!(state.phase, StoryPhase::MurkWandering);
}

#[test]
fn test_murk_wandering_player_movement_to_dig() {
    let mut engine = SimulationEngine::new();
    engine.handle_action(ClientAction::ReleaseClone);
    engine.tick(0.1);
    assert_eq!(engine.phase(), StoryPhase::MurkWandering);

    // Advance player through corridor
    for _ in 0..4 {
        engine.handle_action(ClientAction::PlayerMove { step: 0.25 });
        engine.tick(0.05);
    }

    let state = engine.current_state();
    assert!(state.carl_corridor_progress >= 1.0);
    assert_eq!(state.phase, StoryPhase::TheDig);
    assert!(!state.active_subtitles.is_empty());
}

#[test]
fn test_dig_minigame_bedrock_choice_and_collapse() {
    let mut engine = SimulationEngine::new();
    engine.handle_action(ClientAction::ReleaseClone);
    engine.tick(0.1);
    engine.handle_action(ClientAction::PlayerMove { step: 1.0 });
    engine.tick(0.1);
    assert_eq!(engine.phase(), StoryPhase::TheDig);

    // Dig strikes up to rock obstacle (0.5)
    for _ in 0..5 {
        engine.handle_action(ClientAction::DigStrike);
        engine.tick(0.05);
    }

    let state = engine.current_state();
    assert!(state.dig_progress >= 0.5);
    assert_eq!(state.dig_state, DigState::RockEncountered);

    // Attempting further dig strike before branching should stall
    let progress_before = state.dig_progress;
    engine.handle_action(ClientAction::DigStrike);
    let state = engine.current_state();
    assert_eq!(state.dig_progress, progress_before);

    // Wrong branch ("right") should be rejected/stalled
    engine.handle_action(ClientAction::DigBranch {
        choice: "right".to_string(),
    });
    let state = engine.current_state();
    assert_eq!(state.dig_state, DigState::RockEncountered);

    // Correct branch ("left" - softer basalt vein)
    engine.handle_action(ClientAction::DigBranch {
        choice: "left".to_string(),
    });
    let state = engine.current_state();
    assert_eq!(state.dig_state, DigState::Digging);

    // Dig to completion
    for _ in 0..5 {
        engine.handle_action(ClientAction::DigStrike);
        engine.tick(0.05);
    }

    let state = engine.current_state();
    assert!(state.dig_progress >= 1.0);
    assert_eq!(state.dig_state, DigState::Breached);
    assert_eq!(state.phase, StoryPhase::ToxicCollapse);

    // Toxic collapse advances into reset for C2
    for _ in 0..60 {
        engine.tick(0.1);
    }
    let state = engine.current_state();
    assert_eq!(state.clone_number, 2);
    assert_eq!(state.phase, StoryPhase::Decanting);
    assert!(!state.available_morphologies.is_empty());
}
