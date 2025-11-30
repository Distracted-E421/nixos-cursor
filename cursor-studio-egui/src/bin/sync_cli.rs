//! CLI tool for testing chat sync functionality.
//!
//! Usage:
//!   cargo run --bin sync-cli -- import    # Import from Cursor SQLite
//!   cargo run --bin sync-cli -- stats     # Show sync store stats
//!   cargo run --bin sync-cli -- list      # List conversations
//!   cargo run --bin sync-cli -- search <query>  # Search conversations
//!   cargo run --bin sync-cli -- server-status <url>  # Check server health
//!   cargo run --bin sync-cli -- pull <url>  # Pull from server

use cursor_studio::chat::{SyncService, SyncClient, ClientConfig};
use std::env;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let args: Vec<String> = env::args().collect();
    let command = args.get(1).map(|s| s.as_str()).unwrap_or("help");

    println!("🔄 Cursor Chat Sync CLI");
    println!("========================\n");

    // Server commands don't need local store
    match command {
        "server-status" | "server-stats" | "pull" => {
            let server_url = args.get(2)
                .map(|s| s.as_str())
                .unwrap_or("http://localhost:8420");
            
            run_server_command(command, server_url)?;
            return Ok(());
        }
        _ => {}
    }

    // Local commands need the store
    let mut service = SyncService::new();
    println!("Device ID: {}", service.device_id());

    // Initialize the store
    println!("Initializing SurrealDB store...");
    service.initialize_store().await?;
    println!("✓ Store initialized\n");

    match command {
        "import" => {
            println!("📥 Importing from Cursor...");
            let result = service.import_from_cursor().await?;
            println!("\n✓ Import complete!");
            println!("  Imported: {}", result.imported);
            println!("  Skipped:  {}", result.skipped);
        }

        "stats" => {
            // First import to have data
            println!("📥 Importing from Cursor first...");
            let _ = service.import_from_cursor().await?;
            
            println!("\n📊 Fetching statistics...\n");
            let stats = service.get_stats().await?;
            println!("{}", stats);
        }

        "list" => {
            // First import to have data
            println!("📥 Importing from Cursor first...");
            let _ = service.import_from_cursor().await?;
            
            println!("\n📋 Listing conversations...\n");
            let conversations = service.list_conversations(20).await?;
            
            if conversations.is_empty() {
                println!("No conversations found.");
            } else {
                for (i, conv) in conversations.iter().enumerate() {
                    let title = conv.title.as_deref().unwrap_or("(untitled)");
                    let truncated: String = title.chars().take(50).collect();
                    println!(
                        "{:2}. {} ({} msgs, {} tokens)",
                        i + 1,
                        truncated,
                        conv.message_count,
                        conv.total_input_tokens + conv.total_output_tokens
                    );
                }
            }
        }

        "search" => {
            let query = args.get(2).map(|s| s.as_str()).unwrap_or("");
            if query.is_empty() {
                println!("Usage: sync-cli search <query>");
                return Ok(());
            }

            // First import to have data
            println!("📥 Importing from Cursor first...");
            let _ = service.import_from_cursor().await?;
            
            println!("\n🔍 Searching for '{}'...\n", query);
            let results = service.search(query, 10).await?;
            
            if results.is_empty() {
                println!("No results found for '{}'", query);
            } else {
                println!("Found {} results:\n", results.len());
                for (i, conv) in results.iter().enumerate() {
                    let title = conv.title.as_deref().unwrap_or("(untitled)");
                    println!("{}. {}", i + 1, title);
                }
            }
        }

        "help" | _ => {
            print_help();
        }
    }

    Ok(())
}

fn run_server_command(command: &str, server_url: &str) -> anyhow::Result<()> {
    let config = ClientConfig {
        server_url: server_url.to_string(),
        device_id: "cli-client".to_string(),
    };
    let client = SyncClient::new(config);

    match command {
        "server-status" => {
            println!("📡 Checking server at {}...\n", server_url);
            match client.health() {
                Ok(health) => {
                    println!("✓ Server is healthy!");
                    println!("  Version: {}", health.version);
                    println!("  Device ID: {}", health.device_id);
                    println!("  Conversations: {}", health.conversations);
                }
                Err(e) => {
                    println!("✗ Server unreachable: {}", e);
                }
            }
        }

        "server-stats" => {
            println!("📊 Fetching server stats from {}...\n", server_url);
            match client.stats() {
                Ok(stats) => {
                    println!("{}", serde_json::to_string_pretty(&stats)?);
                }
                Err(e) => {
                    println!("✗ Failed to get stats: {}", e);
                }
            }
        }

        "pull" => {
            println!("📥 Pulling from server {}...\n", server_url);
            match client.pull(Some(10)) {
                Ok(conversations) => {
                    println!("✓ Pulled {} conversations", conversations.len());
                    for (i, conv) in conversations.iter().take(5).enumerate() {
                        let title = conv.conversation.title.as_deref().unwrap_or("(untitled)");
                        let truncated: String = title.chars().take(50).collect();
                        println!("  {}. {}", i + 1, truncated);
                    }
                    if conversations.len() > 5 {
                        println!("  ... and {} more", conversations.len() - 5);
                    }
                }
                Err(e) => {
                    println!("✗ Failed to pull: {}", e);
                }
            }
        }

        _ => {}
    }

    Ok(())
}

fn print_help() {
    println!("Commands:");
    println!();
    println!("  LOCAL OPERATIONS:");
    println!("    import           Import conversations from Cursor SQLite");
    println!("    stats            Show statistics about synced conversations");
    println!("    list             List recent conversations");
    println!("    search <query>   Search conversations by title");
    println!();
    println!("  SERVER OPERATIONS:");
    println!("    server-status [url]  Check server health (default: localhost:8420)");
    println!("    server-stats [url]   Get server statistics");
    println!("    pull [url]           Pull conversations from server");
    println!();
    println!("Examples:");
    println!("  sync-cli import");
    println!("  sync-cli search nixos");
    println!("  sync-cli server-status http://192.168.1.100:8420");
    println!("  sync-cli pull http://framework:8420");
}
