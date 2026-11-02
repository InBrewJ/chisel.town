use std::net::SocketAddr;
use chisel_server::create_app;

#[tokio::main]
async fn main() {
    println!("Chisel Town 1855 Server v0.1.0 starting...");

    let app = create_app();
    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    println!("Listening on ws://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("Failed to bind TCP listener to 0.0.0.0:8080");

    axum::serve(listener, app)
        .await
        .expect("Server encountered an unrecoverable error");
}
