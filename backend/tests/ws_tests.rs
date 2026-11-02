use std::net::SocketAddr;
use std::time::Duration;
use futures_util::StreamExt;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::Message;

use chisel_server::create_app;
use chisel_server::{StoryPhase, WorldState};

/// Helper function to spawn the Axum server on an OS-assigned ephemeral port (127.0.0.1:0).
async fn spawn_test_server() -> SocketAddr {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("Failed to bind ephemeral listener");
    let addr = listener.local_addr().expect("Failed to get local address");

    let app = create_app();

    tokio::spawn(async move {
        axum::serve(listener, app)
            .await
            .expect("Server error in background task");
    });

    addr
}

#[tokio::test]
async fn test_health_endpoint() {
    let addr = spawn_test_server().await;

    let mut stream = TcpStream::connect(addr)
        .await
        .expect("Failed to connect to test server");

    let request = format!(
        "GET /health HTTP/1.1\r\nHost: {}\r\nConnection: close\r\n\r\n",
        addr
    );
    stream
        .write_all(request.as_bytes())
        .await
        .expect("Failed to write HTTP request");

    let mut response = String::new();
    stream
        .read_to_string(&mut response)
        .await
        .expect("Failed to read HTTP response");

    assert!(
        response.starts_with("HTTP/1.1 200 OK"),
        "Expected HTTP 200 OK, got: {}",
        response
    );

    let body = response
        .split("\r\n\r\n")
        .nth(1)
        .expect("Missing HTTP response body");

    let v: serde_json::Value =
        serde_json::from_str(body.trim()).expect("Failed to parse JSON body");
    assert_eq!(v["status"], "ok");
}

#[tokio::test]
async fn test_ws_streaming_frames_and_monotonicity() {
    let addr = spawn_test_server().await;

    let ws_url = format!("ws://{}/ws", addr);
    let (mut ws_stream, response) = connect_async(&ws_url)
        .await
        .expect("Failed to connect to WebSocket endpoint");

    assert_eq!(
        response.status(),
        101,
        "Expected 101 Switching Protocols status"
    );

    let mut prev_elapsed: f32 = -1.0;
    let mut frames_received = 0;

    for _ in 0..5 {
        let msg = tokio::time::timeout(Duration::from_secs(2), ws_stream.next())
            .await
            .expect("WebSocket read timed out waiting for frame")
            .expect("WebSocket stream unexpectedly closed")
            .expect("WebSocket error receiving frame");

        match msg {
            Message::Text(text) => {
                let state: WorldState = serde_json::from_str(&text)
                    .expect("Failed to deserialize WorldState JSON packet");

                assert!(
                    state.elapsed_seconds > prev_elapsed,
                    "Frame elapsed_seconds must increment monotonically: {} <= {}",
                    state.elapsed_seconds,
                    prev_elapsed
                );
                assert_eq!(
                    state.phase,
                    StoryPhase::Decanting,
                    "Expected initial frames to be in Decanting phase, got: {:?}",
                    state.phase
                );

                prev_elapsed = state.elapsed_seconds;
                frames_received += 1;
            }
            other => panic!("Expected Message::Text containing WorldState, got {:?}", other),
        }
    }

    assert_eq!(frames_received, 5);
}

#[tokio::test]
async fn test_isolated_sessions_per_connection() {
    let addr = spawn_test_server().await;
    let ws_url = format!("ws://{}/ws", addr);

    // Client 1 connects and reads 3 frames
    let (mut client1, _) = connect_async(&ws_url)
        .await
        .expect("Client 1 failed to connect");

    for _ in 0..3 {
        let _ = client1.next().await;
    }

    // Client 2 connects fresh
    let (mut client2, _) = connect_async(&ws_url)
        .await
        .expect("Client 2 failed to connect");

    let msg = tokio::time::timeout(Duration::from_secs(2), client2.next())
        .await
        .expect("Timeout waiting for client 2 frame")
        .expect("Client 2 stream closed")
        .expect("Client 2 WS error");

    if let Message::Text(text) = msg {
        let state: WorldState = serde_json::from_str(&text).expect("Deserialization failed");
        // Fresh session should start near 0.0s (e.g. first tick dt=0.0666)
        assert!(
            state.elapsed_seconds < 0.1,
            "Client 2 session should be fresh at t=0, but got elapsed_seconds={}",
            state.elapsed_seconds
        );
        assert_eq!(state.phase, StoryPhase::Decanting);
    } else {
        panic!("Expected text frame");
    }
}
