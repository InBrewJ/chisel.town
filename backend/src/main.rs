use chisel_server::simulation::SimulationEngine;

#[tokio::main]
async fn main() {
    println!("Chisel Town 1855 Server v0.1.0 starting...");

    let mut engine = SimulationEngine::new();
    let initial_state = engine.tick(0.0);
    println!(
        "Simulation initialized at phase {:?}, elapsed: {:.1}s. Transmission: {}",
        initial_state.phase, initial_state.elapsed_seconds, initial_state.bob_transmission
    );
}
