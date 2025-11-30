//! CLI tool for testing chat sync functionality.
//!
//! Usage:
//!   cargo run --bin sync_cli -- import    # Import from Cursor SQLite
//!   cargo run --bin sync_cli -- stats     # Show sync store stats
//!   cargo run --bin sync_cli -- list      # List conversations
//!   cargo run --bin sync_cli -- search <query>  # Search conversations

use cursor_studio::chat::SyncService;
use std::env;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let args: Vec<String> = env::args().collect();
    let command = args.get(1).map(|s| s.as_str()).unwrap_or("help");

    println!("🔄 Cursor Chat Sync CLI");
    println!("========================\n");

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
                println!("Usage: sync_cli search <query>");
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
            println!("Commands:");
            println!("  import  - Import conversations from Cursor SQLite");
            println!("  stats   - Show statistics about synced conversations");
            println!("  list    - List recent conversations");
            println!("  search  - Search conversations by title");
            println!("\nExample:");
            println!("  cargo run --bin sync_cli -- import");
            println!("  cargo run --bin sync_cli -- search nixos");
        }
    }

    Ok(())
}
