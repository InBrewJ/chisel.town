use std::time::Duration;

use axum::{
    extract::ws::{Message, WebSocket, WebSocketUpgrade},
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use tower_http::cors::CorsLayer;

use crate::simulation::SimulationEngine;

/// Tick interval in milliseconds (~15 Hz)
pub const TICK_INTERVAL_MS: u64 = 66;
/// Delta time advanced per tick
pub const TICK_DT: f32 = 0.0666;

/// Builds and configures the Axum router for the Chisel Town 1855 server.
pub fn create_app() -> Router {
    Router::new()
        .route("/health", get(health_handler))
        .route("/ws", get(ws_handler))
        .layer(CorsLayer::permissive())
}

/// Health check endpoint returning {"status": "ok"}
async fn health_handler() -> impl IntoResponse {
    Json(json!({ "status": "ok" }))
}

/// WebSocket upgrade handler that accepts connection upgrades to `/ws`.
async fn ws_handler(ws: WebSocketUpgrade) -> impl IntoResponse {
    ws.on_upgrade(handle_socket)
}

/// Handles an active WebSocket connection, running an isolated SimulationEngine
/// session at ~15 Hz (66ms interval, dt = 0.0666s).
async fn handle_socket(socket: WebSocket) {
    let (mut sender, mut receiver) = socket.split();
    let mut engine = SimulationEngine::new();
    let mut interval = tokio::time::interval(Duration::from_millis(TICK_INTERVAL_MS));
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

    loop {
        tokio::select! {
            _ = interval.tick() => {
                let state = engine.tick(TICK_DT);
                let json_data = match serde_json::to_string(&state) {
                    Ok(payload) => payload,
                    Err(err) => {
                        eprintln!("Error serializing WorldState: {err}");
                        break;
                    }
                };

                if sender.send(Message::Text(json_data)).await.is_err() {
                    // Socket closed by client or broken pipe
                    break;
                }
            }
            client_msg = receiver.next() => {
                match client_msg {
                    Some(Ok(Message::Close(_))) | None => {
                        // Clean disconnect or EOF
                        break;
                    }
                    Some(Ok(Message::Ping(ping))) => {
                        if sender.send(Message::Pong(ping)).await.is_err() {
                            break;
                        }
                    }
                    Some(Ok(Message::Text(text))) => {
                        if let Ok(action) = serde_json::from_str::<crate::simulation::ClientAction>(&text) {
                            engine.handle_action(action);
                        }
                    }
                    Some(Ok(_)) => {
                        // Ignore binary client messages
                    }
                    Some(Err(_)) => {
                        break;
                    }
                }
            }
        }
    }
}
