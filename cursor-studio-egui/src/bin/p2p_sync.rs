//! P2P Sync Daemon
//!
//! A standalone daemon that syncs chat history with other devices on the local network.
//!
//! # Usage
//!
//! ```bash
//! # Start daemon with auto-discovery
//! cargo run --bin p2p-sync
//!
//! # Custom port
//! cargo run --bin p2p-sync -- --port 4001
//! ```

use cursor_studio::chat::{
    crdt::DeviceId,
    p2p::{P2PConfig, P2PEvent, P2PService, SyncRequest, SyncResponse},
    surreal::SurrealStore,
    cursor_parser::CursorParser,
};
use std::env;
use std::sync::Arc;
use tokio::sync::RwLock;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize logging
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    println!("🔗 Cursor Chat P2P Sync Daemon");
    println!("==============================\n");

    // Parse command line arguments
    let args: Vec<String> = env::args().collect();
    let mut config = P2PConfig::default();
    let mut do_import = false;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--port" | "-p" => {
                i += 1;
                if let Some(port_str) = args.get(i) {
                    config.port = port_str.parse().unwrap_or(0);
                }
            }
            "--name" | "-n" => {
                i += 1;
                if let Some(name) = args.get(i) {
                    config.device_name = name.clone();
                }
            }
            "--import" | "-i" => {
                do_import = true;
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
    println!("Device Name: {}", config.device_name);

    // Initialize SurrealDB store
    println!("\nInitializing store...");
    let store = SurrealStore::new_memory(device_id.clone()).await?;
    let store = Arc::new(RwLock::new(store));
    
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

    // Create P2P service
    println!("Starting P2P service...");
    let (service, mut event_rx, swarm) = P2PService::new(config.clone())?;
    
    println!("Peer ID: {}", service.peer_id());
    println!("\n🔍 Searching for peers on local network...\n");

    // Clone store for the event handler
    let store_clone = store.clone();

    // Spawn the swarm runner - service owns the swarm
    tokio::spawn(async move {
        if let Err(e) = service.run(swarm).await {
            log::error!("P2P service error: {}", e);
        }
    });

    // Handle events
    while let Some(event) = event_rx.recv().await {
        match event {
            P2PEvent::Listening(addr) => {
                println!("📡 Listening on {}", addr);
            }
            
            P2PEvent::PeerDiscovered(peer) => {
                println!("✨ Discovered peer: {}", peer.peer_id);
                if let Some(name) = &peer.device_name {
                    println!("   Name: {}", name);
                }
                for addr in &peer.addrs {
                    println!("   Address: {}", addr);
                }
            }
            
            P2PEvent::PeerExpired(peer_id) => {
                println!("👋 Peer disconnected: {}", peer_id);
            }
            
            P2PEvent::SyncRequest { peer_id, request, .. } => {
                println!("📨 Sync request from {}: {:?}", peer_id, request);
                // Note: Response handling requires swarm access
                // For now, just log the request
                // Full implementation would need a command channel back to the swarm task
                
                match request {
                    SyncRequest::Status => {
                        let store = store_clone.read().await;
                        let count = store.count().await.unwrap_or(0);
                        println!("   (Would respond with {} conversations)", count);
                    }
                    SyncRequest::Pull { limit, .. } => {
                        println!("   (Would send up to {} conversations)", limit);
                    }
                    SyncRequest::Push { conversations } => {
                        println!("   (Would merge {} conversations)", conversations.len());
                    }
                }
            }
            
            P2PEvent::SyncResponse { peer_id, response } => {
                match response {
                    SyncResponse::Status { device_id: did, device_name: dn, conversation_count, .. } => {
                        println!("📊 Status from {}", peer_id);
                        println!("   Device: {} ({})", dn, did);
                        println!("   Conversations: {}", conversation_count);
                    }
                    
                    SyncResponse::Pull { conversations, .. } => {
                        println!("📥 Received {} conversations from {}", conversations.len(), peer_id);
                        let store = store_clone.read().await;
                        let mut merged = 0;
                        for conv in conversations {
                            if store.merge_conversation(&conv).await.is_ok() {
                                merged += 1;
                            }
                        }
                        println!("   Merged: {}", merged);
                    }
                    
                    SyncResponse::PushAck { accepted, rejected } => {
                        println!("✓ Push acknowledged: {} accepted, {} rejected", accepted, rejected);
                    }
                    
                    SyncResponse::Error { message } => {
                        println!("✗ Error from {}: {}", peer_id, message);
                    }
                }
            }
            
            P2PEvent::Error(msg) => {
                println!("⚠ Error: {}", msg);
            }
        }
    }

    Ok(())
}

fn print_help() {
    println!("Cursor Chat P2P Sync Daemon");
    println!();
    println!("USAGE:");
    println!("    p2p-sync [OPTIONS]");
    println!();
    println!("OPTIONS:");
    println!("    -p, --port <PORT>    Port to listen on (default: random)");
    println!("    -n, --name <NAME>    Device name for discovery");
    println!("    -i, --import         Import local Cursor chats on startup");
    println!("        --help           Show this help message");
    println!();
    println!("EXAMPLES:");
    println!("    p2p-sync                         # Start with auto-discovery");
    println!("    p2p-sync --port 4001             # Fixed port");
    println!("    p2p-sync --import --name laptop  # Import + custom name");
}

fn load_or_create_device_id() -> DeviceId {
    use std::path::PathBuf;
    
    let config_dir = dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("cursor-studio");
    
    let device_id_path = config_dir.join("device_id");
    
    if let Ok(id_str) = std::fs::read_to_string(&device_id_path) {
        log::info!("Loaded existing device ID");
        DeviceId::from_string(id_str.trim().to_string())
    } else {
        let new_id = DeviceId::new();
        log::info!("Generated new device ID: {}", new_id);
        
        if let Err(e) = std::fs::create_dir_all(&config_dir) {
            log::warn!("Failed to create config dir: {}", e);
        }
        if let Err(e) = std::fs::write(&device_id_path, new_id.0.as_bytes()) {
            log::warn!("Failed to save device ID: {}", e);
        }
        
        new_id
    }
}

async fn import_local_chats(store: &Arc<RwLock<SurrealStore>>) -> anyhow::Result<(usize, usize)> {
    let parser = CursorParser::new_default()?;
    let conversations = parser.parse_all()?;
    
    let store = store.read().await;
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
