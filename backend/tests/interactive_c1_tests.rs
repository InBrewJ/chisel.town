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

#[test]
fn test_nan_float_inputs_do_not_panic() {
    let mut engine = SimulationEngine::new();
    // Passing NaN should safely be ignored rather than panicking on clamp
    engine.handle_action(ClientAction::TuneParameters {
        cohesion: Some(f32::NAN),
        paranoia: Some(f32::INFINITY),
        pressure: Some(f32::NEG_INFINITY),
    });
    let state = engine.current_state();
    assert!(!state.town_cohesion.is_nan());
    assert!(!state.carl_paranoia.is_nan());
    assert!(!state.subterranean_pressure.is_nan());

    engine.handle_action(ClientAction::PlayerMove { step: f32::NAN });
    let state = engine.current_state();
    assert!(!state.carl_corridor_progress.is_nan());
}

#[test]
fn test_decanting_elapsed_seconds_increments_while_phase_stays_decanting() {
    let mut engine = SimulationEngine::new();
    assert_eq!(engine.phase(), StoryPhase::Decanting);
    let mut prev_time = 0.0;
    for _ in 0..50 {
        let state = engine.tick(0.1);
        assert_eq!(state.phase, StoryPhase::Decanting);
        assert!(state.elapsed_seconds > prev_time);
        prev_time = state.elapsed_seconds;
    }
}

#[test]
fn test_interactive_mode_does_not_expire_at_180s() {
    let mut engine = SimulationEngine::new();
    engine.handle_action(ClientAction::ReleaseClone);
    engine.tick(0.1);
    assert_eq!(engine.phase(), StoryPhase::MurkWandering);

    // Player takes their time (e.g. 300 seconds exploring corridor)
    for _ in 0..3000 {
        let state = engine.tick(0.1);
        // Should remain in MurkWandering until player actually advances to dig
        assert_eq!(state.phase, StoryPhase::MurkWandering);
    }
}

#[test]
fn test_place_building_and_swarm_stacking() {
    let mut engine = SimulationEngine::new();
    assert_eq!(engine.phase(), StoryPhase::Decanting);

    // Place building at site 1
    engine.handle_action(ClientAction::PlaceBuilding {
        site_id: 1,
        building_type: "Mercy Hospital".to_string(),
    });
    let state = engine.current_state();
    assert_eq!(state.town_buildings.len(), 1);
    assert_eq!(state.town_buildings[0].site_id, 1);
    assert_eq!(state.town_buildings[0].tier, 1);
    assert_eq!(state.town_buildings[0].building_type, "Mercy Hospital");

    // Stack a school on the same site 1
    engine.handle_action(ClientAction::PlaceBuilding {
        site_id: 1,
        building_type: "Academy School".to_string(),
    });
    let state = engine.current_state();
    assert_eq!(state.town_buildings.len(), 1);
    assert_eq!(state.town_buildings[0].tier, 2);
    assert_eq!(
        state.town_buildings[0].building_type,
        "Academy School (Stacked over Mercy Hospital)"
    );
}

#[test]
fn test_cross_cycle_building_persistence() {
    let mut engine = SimulationEngine::new();
    engine.handle_action(ClientAction::PlaceBuilding {
        site_id: 0,
        building_type: "Iron Barricade".to_string(),
    });
    assert_eq!(engine.current_state().town_buildings.len(), 1);

    // Trigger clone reset
    engine.reset_for_next_clone();
    let state = engine.current_state();
    assert_eq!(state.clone_number, 2);
    // Buildings must persist across cycles
    assert_eq!(state.town_buildings.len(), 1);
}

#[test]
fn test_encounter_dialogue_reduces_paranoia() {
    let mut engine = SimulationEngine::new();
    engine.handle_action(ClientAction::TuneParameters {
        cohesion: None,
        paranoia: Some(0.80),
        pressure: None,
    });
    assert_eq!(engine.current_state().carl_paranoia, 0.80);

    engine.handle_action(ClientAction::EncounterDialogue {
        character: "Josiah H Foray".to_string(),
    });
    let state = engine.current_state();
    assert!((state.carl_paranoia - 0.45).abs() < 1e-4);
}

