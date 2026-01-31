use anyhow::Result;
use cursor_core::auth::{extract_auth_from_db, get_auth_db_path};
use cursor_core::client::Client;
use tracing::{info, error};

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    println!("Starting Cursor TUI (tonic)...");
    info!("Starting Cursor TUI...");

    let db_path = get_auth_db_path();
    println!("Reading auth from: {:?}", db_path);

    match extract_auth_from_db(&db_path) {
        Ok(auth) => {
            let masked_token = if auth.access_token.len() > 10 {
                format!("{}...", &auth.access_token[..10])
            } else {
                "Too short".to_string()
            };
            println!("Successfully extracted auth!");
            println!("Access Token: {}", masked_token);

            println!("Creating client...");
            match Client::new(auth).await {
                Ok(mut client) => {
                    println!("Sending dummy request...");
                    if let Err(e) = client.send_dummy_request().await {
                        error!("Request failed: {:?}", e);
                        println!("Request failed: {:?}", e);
                    }
                },
                Err(e) => {
                    println!("Failed to create client: {:?}", e);
                }
            }
        }
        Err(e) => {
            println!("Failed to extract auth: {:?}", e);
            if !db_path.exists() {
                println!("Database file does not exist at path");
            }
        }
    }

    Ok(())
}
