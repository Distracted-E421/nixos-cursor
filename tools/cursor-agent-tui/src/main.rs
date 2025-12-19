//! cursor-agent-tui - Lightweight TUI for Cursor AI
//!
//! A terminal-based interface for AI-assisted coding without Electron bloat.

mod api;
mod app;
mod auth;
mod config;
mod context;
mod error;
mod generated;
mod proto;
mod state;
mod tools;
mod tui;

// Re-export generated protobuf types
pub use generated::*;

use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use tracing::info;

#[derive(Parser)]
#[command(name = "cursor-agent")]
#[command(version, about = "Lightweight TUI for Cursor AI", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Working directory (defaults to current directory)
    #[arg(short = 'C', long)]
    directory: Option<PathBuf>,

    /// Enable verbose logging
    #[arg(short, long)]
    verbose: bool,

    /// Config file path
    #[arg(long)]
    config: Option<PathBuf>,
}

#[derive(Subcommand)]
enum Commands {
    /// Start interactive TUI session
    Chat {
        /// Initial message to send
        #[arg(short, long)]
        message: Option<String>,

        /// Files to include in context
        #[arg(short, long)]
        files: Vec<PathBuf>,
    },

    /// Extract and display authentication token
    Auth {
        /// Show token value (careful - sensitive!)
        #[arg(long)]
        show: bool,

        /// Test token validity
        #[arg(long)]
        test: bool,
    },

    /// Run a single query (non-interactive)
    Query {
        /// The query to send
        query: String,

        /// Files to include in context
        #[arg(short, long)]
        files: Vec<PathBuf>,

        /// Output format (text, json, markdown)
        #[arg(short, long, default_value = "text")]
        format: String,
    },

    /// Show configuration
    Config {
        /// Edit configuration
        #[arg(long)]
        edit: bool,
    },

    /// List available AI models
    Models {
        /// Show only agent-capable models
        #[arg(long)]
        agent_only: bool,

        /// Output format (text, json)
        #[arg(short, long, default_value = "text")]
        format: String,
    },

    /// Test proto-based chat (experimental)
    ProtoTest {
        /// Test message to send
        #[arg(default_value = "Hello! What's 2+2?")]
        message: String,

        /// Model to use
        #[arg(short, long, default_value = "claude-3.5-sonnet")]
        model: String,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Setup logging
    let log_level = if cli.verbose { "debug" } else { "info" };
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new(log_level)),
        )
        .with_target(false)
        .compact()
        .init();

    // Change directory if specified
    if let Some(dir) = &cli.directory {
        std::env::set_current_dir(dir)?;
        info!("Working directory: {}", dir.display());
    }

    // Load configuration
    let config = config::Config::load(cli.config.as_deref())?;

    match cli.command {
        Some(Commands::Chat { message, files }) => {
            cmd_chat(config, message, files).await
        }
        Some(Commands::Auth { show, test }) => {
            cmd_auth(config, show, test).await
        }
        Some(Commands::Query { query, files, format }) => {
            cmd_query(config, query, files, format).await
        }
        Some(Commands::Config { edit }) => {
            cmd_config(config, edit).await
        }
        Some(Commands::Models { agent_only, format }) => {
            cmd_models(config, agent_only, format).await
        }
        Some(Commands::ProtoTest { message, model }) => {
            cmd_proto_test(config, message, model).await
        }
        None => {
            // Default: start interactive TUI
            cmd_chat(config, None, vec![]).await
        }
    }
}

/// List available models
async fn cmd_models(config: config::Config, agent_only: bool, format: String) -> Result<()> {
    let auth = auth::AuthManager::new(&config)?;
    let token = auth.get_token().await?;
    let client = api::CursorClient::new(token, &config)?;

    let models = if agent_only {
        client.recommended_agent_models().await?
    } else {
        client.available_models_detailed().await?
    };

    match format.as_str() {
        "json" => {
            println!("{}", serde_json::to_string_pretty(&models)?);
        }
        _ => {
            println!("Available Models ({}):\n", models.len());
            for model in models {
                let thinking = if model.supports_thinking { " 🧠" } else { "" };
                let agent = if model.supports_agent { " 🤖" } else { "" };
                let default = if model.default_on { " ★" } else { "" };
                let display_name = model.client_display_name.as_deref().unwrap_or(&model.name);
                
                println!("  {}{}{}{}", display_name, default, agent, thinking);
                
                if let Some(tooltip) = &model.tooltip_data {
                    if let Some(content) = &tooltip.markdown_content {
                        // Strip HTML tags for simple display
                        let clean = content
                            .replace("<br />", "\n")
                            .replace("<br/>", "\n")
                            .replace("**", "")
                            .split("<span")
                            .next()
                            .unwrap_or(content)
                            .trim()
                            .to_string();
                        for line in clean.lines().take(2) {
                            if !line.trim().is_empty() {
                                println!("    {}", line.trim());
                            }
                        }
                    }
                }
                println!();
            }
            println!("Legend: ★ = default, 🤖 = agent, 🧠 = thinking");
        }
    }

    Ok(())
}

/// Start interactive chat TUI
async fn cmd_chat(
    config: config::Config,
    initial_message: Option<String>,
    initial_files: Vec<PathBuf>,
) -> Result<()> {
    info!("Starting cursor-agent TUI...");

    // Initialize authentication
    let auth = auth::AuthManager::new(&config)?;
    let token = auth.get_token().await?;
    info!("✓ Authentication ready");

    // Initialize API client
    let client = api::CursorClient::new(token, &config)?;
    info!("✓ API client ready");

    // Initialize context manager
    let mut context = context::ContextManager::new(std::env::current_dir()?);
    for file in initial_files {
        context.add_file(&file)?;
    }
    info!("✓ Context manager ready");

    // Initialize tool runner
    let tools = tools::ToolRunner::new(&config)?;
    info!("✓ Tool runner ready");

    // Initialize state manager
    let state = state::StateManager::new(&config)?;
    info!("✓ State manager ready");

    // Create application
    let app = app::App::new(client, context, tools, state, config)?;

    // Run TUI
    tui::run(app, initial_message).await
}

/// Handle auth command
async fn cmd_auth(config: config::Config, show: bool, test: bool) -> Result<()> {
    let auth = auth::AuthManager::new(&config)?;

    if test {
        println!("Testing authentication...");
        match auth.get_token().await {
            Ok(token) => {
                // Test with API call
                let client = api::CursorClient::new(token.clone(), &config)?;
                match client.check_auth().await {
                    Ok(_) => {
                        println!("✓ Authentication valid");
                        if show {
                            println!("Token: {}...{}", &token.value[..20], &token.value[token.value.len()-10..]);
                        }
                    }
                    Err(e) => {
                        println!("✗ Authentication failed: {}", e);
                    }
                }
            }
            Err(e) => {
                println!("✗ Could not get token: {}", e);
            }
        }
    } else if show {
        let token = auth.get_token().await?;
        println!("Token: {}", token.value);
    } else {
        // Just show token status
        match auth.get_token().await {
            Ok(token) => {
                println!("✓ Token available");
                println!("  Expires: {}", token.expires_at.map(|t| t.to_string()).unwrap_or("unknown".into()));
            }
            Err(e) => {
                println!("✗ No valid token: {}", e);
                println!("  Try logging into Cursor IDE first, or set CURSOR_TOKEN");
            }
        }
    }

    Ok(())
}

/// Run single query
async fn cmd_query(
    config: config::Config,
    query: String,
    files: Vec<PathBuf>,
    format: String,
) -> Result<()> {
    // Initialize
    let auth = auth::AuthManager::new(&config)?;
    let token = auth.get_token().await?;
    let client = api::CursorClient::new(token, &config)?;
    let mut context = context::ContextManager::new(std::env::current_dir()?);
    let tools = tools::ToolRunner::new(&config)?;

    // Add files to context
    for file in files {
        context.add_file(&file)?;
    }

    // Build and send request
    let ctx = context.build_context(&query);
    let mut stream = client.stream_chat(&query, ctx).await?;

    // Process stream
    use futures::StreamExt;
    while let Some(event) = stream.next().await {
        match event? {
            api::ChatEvent::Text(text) => {
                match format.as_str() {
                    "json" => {
                        println!("{}", serde_json::json!({"type": "text", "content": text}));
                    }
                    _ => print!("{}", text),
                }
            }
            api::ChatEvent::ToolCall { name, args } => {
                if format == "json" {
                    println!("{}", serde_json::json!({"type": "tool_call", "name": name, "args": args}));
                } else {
                    println!("\n[Tool: {}]", name);
                }
                
                // Execute tool
                let result = tools.execute(&name, &args).await?;
                
                if format == "json" {
                    println!("{}", serde_json::json!({"type": "tool_result", "name": name, "result": result}));
                } else {
                    println!("[Result: {} bytes]", result.len());
                }
            }
            api::ChatEvent::Done { usage } => {
                if format != "json" {
                    eprintln!("\n\n[Tokens: {} prompt, {} completion]", 
                             usage.prompt_tokens, usage.completion_tokens);
                }
            }
            _ => {}
        }
    }

    Ok(())
}

/// Test proto-based chat (experimental)
async fn cmd_proto_test(config: config::Config, message: String, model: String) -> Result<()> {
    println!("🧪 Proto-based Chat Test");
    println!("========================\n");
    println!("Message: {}", message);
    println!("Model: {}", model);
    println!();

    // Initialize
    let auth = auth::AuthManager::new(&config)?;
    let token = auth.get_token().await?;
    println!("✓ Authentication ready");

    let client = api::CursorClient::new(token, &config)?;
    println!("✓ API client ready");

    // Build empty context for simple test
    let ctx = context::Context {
        files: vec![],
        cwd: Some(std::env::current_dir()?.to_string_lossy().to_string()),
        git_branch: None,
    };

    println!("\n📡 Sending request using generated proto schema...\n");

    // Clone ctx for potential retry with legacy implementation
    let ctx_for_retry = ctx.clone();

    // Try proto-based chat
    match client.stream_chat_proto(&message, ctx, &model).await {
        Ok(mut stream) => {
            use futures::StreamExt;
            
            print!("Response: ");
            while let Some(event) = stream.next().await {
                match event {
                    Ok(api::ChatEvent::Text(text)) => {
                        print!("{}", text);
                        std::io::Write::flush(&mut std::io::stdout())?;
                    }
                    Ok(api::ChatEvent::ToolCall { name, args }) => {
                        println!("\n[Tool Call: {} with args: {}]", name, args);
                    }
                    Ok(api::ChatEvent::Done { usage }) => {
                        println!("\n\n✓ Done! Tokens: {} prompt, {} completion", 
                                 usage.prompt_tokens, usage.completion_tokens);
                    }
                    Ok(api::ChatEvent::Thinking) => {
                        print!(".");
                    }
                    Ok(api::ChatEvent::Error(e)) => {
                        println!("\n❌ Stream error: {}", e);
                    }
                    Err(e) => {
                        println!("\n❌ Error: {}", e);
                        break;
                    }
                    _ => {}
                }
            }
        }
        Err(e) => {
            println!("❌ Request failed: {:?}", e);
            println!("\nThis is expected until the proto schema is fully validated.");
            println!("The schema was reverse-engineered from Cursor's bundled code.");
            println!("\nDebug info:");
            println!("  - Endpoint: aiserver.v1.ChatService/StreamUnifiedChatWithToolsSSE");
            println!("  - Proto schema: tools/cursor-agent-tui/proto/aiserver.proto");
            println!("  - Generated types: tools/cursor-agent-tui/src/generated/aiserver.v1.rs");
            
            // Try the old implementation for comparison
            println!("\n🔄 Trying legacy implementation for comparison...\n");
            match client.stream_chat(&message, ctx_for_retry).await {
                Ok(mut stream) => {
                    use futures::StreamExt;
                    print!("Legacy response: ");
                    while let Some(event) = stream.next().await {
                        match event {
                            Ok(api::ChatEvent::Text(text)) => print!("{}", text),
                            Ok(api::ChatEvent::Done { .. }) => println!("\n✓ Legacy done"),
                            Ok(api::ChatEvent::Error(e)) => println!("\n❌ Legacy error: {}", e),
                            Err(e) => {
                                println!("\n❌ Legacy error: {:?}", e);
                                break;
                            }
                            _ => {}
                        }
                    }
                }
                Err(e2) => {
                    println!("Legacy also failed: {:?}", e2);
                }
            }
        }
    }

    Ok(())
}

/// Show/edit configuration
async fn cmd_config(config: config::Config, edit: bool) -> Result<()> {
    let path = config::Config::default_path();

    if edit {
        let editor = std::env::var("EDITOR").unwrap_or_else(|_| "nano".to_string());
        std::process::Command::new(&editor)
            .arg(&path)
            .status()?;
    } else {
        println!("Configuration file: {}", path.display());
        println!();
        if path.exists() {
            let content = std::fs::read_to_string(&path)?;
            println!("{}", content);
        } else {
            println!("# Default configuration (not yet saved)");
            println!("{}", toml::to_string_pretty(&config)?);
        }
    }

    Ok(())
}

