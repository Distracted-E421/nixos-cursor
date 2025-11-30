//! Cursor Chat Sync Server
//!
//! A REST API server for synchronizing chat history across devices.
//!
//! # Usage
//!
//! ```bash
//! # Start server with defaults (port 8420)
//! cargo run --bin sync-server
//!
//! # Custom port
//! cargo run --bin sync-server -- --port 8080
//!
//! # Import local chats first, then serve
//! cargo run --bin sync-server -- --import
//! ```

use cursor_studio::chat::{
    server::{start_server, ServerConfig},
    crdt::DeviceId,
    surreal::SurrealStore,
    cursor_parser::CursorParser,
};
use std::env;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,tower_http=debug".into()),
        )
        .init();

    println!("🔄 Cursor Chat Sync Server");
    println!("==========================\n");

    // Parse command line arguments (simple manual parsing)
    let args: Vec<String> = env::args().collect();
    
    let mut config = ServerConfig::default();
    let mut do_import = false;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--port" | "-p" => {
                i += 1;
                if let Some(port_str) = args.get(i) {
                    config.port = port_str.parse().unwrap_or(8420);
                }
            }
            "--host" | "-h" => {
                i += 1;
                if let Some(host) = args.get(i) {
                    config.host = host.clone();
                }
            }
            "--import" | "-i" => {
                do_import = true;
            }
            "--no-cors" => {
                config.enable_cors = false;
            }
            "--help" => {
                print_help();
                return Ok(());
            }
            _ => {
                eprintln!("Unknown argument: {}", args[i]);
                print_help();
                return Ok(());
            }
        }
        i += 1;
    }

    // Load or create device ID
    let device_id = load_or_create_device_id();
    println!("Device ID: {}", device_id);

    // Initialize SurrealDB store
    println!("Initializing SurrealDB store...");
    let store = SurrealStore::new_memory(device_id.clone()).await?;
    println!("✓ Store initialized\n");

    // Optionally import from local Cursor
    if do_import {
        println!("📥 Importing from local Cursor database...");
        match import_local_chats(&store).await {
            Ok((imported, skipped)) => {
                println!("✓ Imported {} conversations ({} skipped)\n", imported, skipped);
            }
            Err(e) => {
                println!("⚠ Import failed: {} (continuing anyway)\n", e);
            }
        }
    }

    // Start the server
    start_server(config, store, device_id).await?;

    Ok(())
}

fn print_help() {
    println!("Cursor Chat Sync Server");
    println!();
    println!("USAGE:");
    println!("    sync-server [OPTIONS]");
    println!();
    println!("OPTIONS:");
    println!("    -p, --port <PORT>    Port to listen on (default: 8420)");
    println!("    -h, --host <HOST>    Host to bind to (default: 0.0.0.0)");
    println!("    -i, --import         Import local Cursor chats on startup");
    println!("        --no-cors        Disable CORS headers");
    println!("        --help           Show this help message");
    println!();
    println!("EXAMPLES:");
    println!("    sync-server                     # Start on port 8420");
    println!("    sync-server --port 8080         # Custom port");
    println!("    sync-server --import            # Import local chats first");
    println!("    sync-server --import --port 80  # Both");
}

fn load_or_create_device_id() -> DeviceId {
    use std::path::PathBuf;
    
    let config_dir = dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("cursor-studio");
    
    let device_id_path = config_dir.join("server_device_id");
    
    if let Ok(id_str) = std::fs::read_to_string(&device_id_path) {
        log::info!("Loaded existing server device ID");
        DeviceId::from_string(id_str.trim().to_string())
    } else {
        let new_id = DeviceId::new();
        log::info!("Generated new server device ID: {}", new_id);
        
        // Try to save it
        if let Err(e) = std::fs::create_dir_all(&config_dir) {
            log::warn!("Failed to create config dir: {}", e);
        }
        if let Err(e) = std::fs::write(&device_id_path, new_id.0.as_bytes()) {
            log::warn!("Failed to save device ID: {}", e);
        }
        
        new_id
    }
}

async fn import_local_chats(store: &SurrealStore) -> anyhow::Result<(usize, usize)> {
    let parser = CursorParser::new_default()?;
    let conversations = parser.parse_all()?;
    
    let mut imported = 0;
    let mut skipped = 0;
    
    for conv in &conversations {
        if let Ok(Some(_)) = store.get_conversation(&conv.id.to_string()).await {
            skipped += 1;
            continue;
        }
        
        if store.upsert_conversation(conv).await.is_ok() {
            imported += 1;
        }
    }
    
    Ok((imported, skipped))
}
