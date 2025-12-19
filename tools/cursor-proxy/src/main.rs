//! Cursor Proxy - Integrated transparent proxy for Cursor AI traffic
//!
//! Part of the cursor-studio tooling for enhanced Cursor IDE control.

mod capture;
mod cert;
mod config;
pub mod dashboard;
pub mod dashboard_egui;
mod dns;
mod error;
pub mod events;
pub mod injection;
pub mod ipc;
mod iptables;
mod pool;
mod proxy;

use crate::cert::CertificateAuthority;
use crate::config::Config;
use crate::error::{ProxyError, ProxyResult};
use crate::iptables::IptablesManager;
use crate::proxy::ProxyServer;

use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::sync::Arc;
use tracing::{error, info, Level};
use tracing_subscriber::FmtSubscriber;

/// Cursor Proxy - Transparent proxy for Cursor AI traffic interception
#[derive(Parser)]
#[command(name = "cursor-proxy")]
#[command(version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
    
    /// Enable verbose logging
    #[arg(short, long, global = true)]
    verbose: bool,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize proxy (generate CA, create config)
    Init {
        /// Force regeneration of CA certificate
        #[arg(long)]
        force: bool,
    },
    
    /// Start the proxy server
    Start {
        /// Port to listen on (default: 443 for DNS mode, 8443 for iptables mode)
        #[arg(short, long)]
        port: Option<u16>,
        
        /// Enable DNS-based interception (recommended) - requires /etc/hosts entry
        #[arg(long)]
        dns_mode: bool,
        
        /// Enable iptables transparent mode (legacy - has DNS rotation issues)
        #[arg(long)]
        transparent: bool,
        
        /// Run in foreground (don't daemonize)
        #[arg(long)]
        foreground: bool,
        
        /// Force start even if proxy is disabled in config
        #[arg(long)]
        force: bool,
    },
    
    /// Enable proxy in configuration
    Enable,
    
    /// Disable proxy in configuration (stops if running)
    Disable,
    
    /// Stop the proxy server
    Stop,
    
    /// Show proxy status
    Status,
    
    /// Trust the CA certificate
    TrustCa {
        /// Show CA certificate content instead of installing
        #[arg(long)]
        show: bool,
        
        /// Output path for CA certificate
        #[arg(long)]
        output: Option<PathBuf>,
    },
    
    /// Manage iptables rules
    Iptables {
        #[command(subcommand)]
        action: IptablesAction,
    },
    
    /// View captured payloads
    Captures {
        /// Search pattern
        pattern: Option<String>,
        
        /// Show only recent (last N hours)
        #[arg(long)]
        recent: Option<u32>,
    },
    
    /// Show configuration
    Config {
        /// Edit configuration file
        #[arg(long)]
        edit: bool,
    },
    
    /// Manage injection rules (system prompt, context, version spoofing)
    Inject {
        #[command(subcommand)]
        action: InjectAction,
    },
    
    /// Clean up (remove iptables rules, stop proxy)
    Cleanup {
        /// Also remove CA and config
        #[arg(long)]
        all: bool,
    },
    
    /// Launch real-time LED dashboard (connects to running proxy)
    Dashboard {
        /// Unix socket path to connect to
        #[arg(long)]
        socket: Option<PathBuf>,
    },
}

#[derive(Subcommand)]
enum IptablesAction {
    /// Add rules for Cursor API
    Add,
    /// Remove all managed rules
    Remove,
    /// Show current rules
    Show,
    /// Refresh rules (re-resolve DNS)
    Refresh,
    /// Emergency flush all NAT OUTPUT rules
    Flush,
}

#[derive(Subcommand)]
enum InjectAction {
    /// Enable injection
    Enable,
    /// Disable injection
    Disable,
    /// Show current injection status
    Status,
    /// Set system prompt
    Prompt {
        /// System prompt text (or path to file if starts with @)
        prompt: String,
    },
    /// Set version to spoof
    Version {
        /// Version string (e.g., "0.50.0")
        version: String,
    },
    /// Add a context file
    AddContext {
        /// Path to context file
        path: PathBuf,
    },
    /// Clear all context files
    ClearContext,
    /// Reload rules from file
    Reload,
    /// Edit injection rules file
    Edit,
}

#[tokio::main]
async fn main() {
    // Install rustls crypto provider (must be done before any TLS operations)
    rustls::crypto::ring::default_provider()
        .install_default()
        .expect("Failed to install rustls crypto provider");
    
    let cli = Cli::parse();
    
    // Setup logging
    let level = if cli.verbose { Level::DEBUG } else { Level::INFO };
    let _subscriber = FmtSubscriber::builder()
        .with_max_level(level)
        .with_target(false)
        .compact()
        .init();
    
    // Run command
    if let Err(e) = run_command(cli).await {
        error!("{}", e.display_for_user());
        std::process::exit(1);
    }
}

async fn run_command(cli: Cli) -> ProxyResult<()> {
    match cli.command {
        Commands::Init { force } => cmd_init(force).await,
        Commands::Start { port, dns_mode, transparent, foreground, force } => {
            cmd_start(port, dns_mode, transparent, foreground, force).await
        }
        Commands::Stop => cmd_stop().await,
        Commands::Status => cmd_status().await,
        Commands::TrustCa { show, output } => cmd_trust_ca(show, output).await,
        Commands::Iptables { action } => cmd_iptables(action).await,
        Commands::Captures { pattern, recent } => cmd_captures(pattern, recent).await,
        Commands::Config { edit } => cmd_config(edit).await,
        Commands::Cleanup { all } => cmd_cleanup(all).await,
        Commands::Dashboard { socket: _ } => cmd_dashboard().await,
        Commands::Enable => cmd_enable().await,
        Commands::Disable => cmd_disable().await,
        Commands::Inject { action } => cmd_inject(action).await,
    }
}

/// Manage injection rules
async fn cmd_inject(action: InjectAction) -> ProxyResult<()> {
    let mut config = Config::load()?;
    let injection_dir = dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".cursor-proxy");
    let rules_path = injection_dir.join("injection-rules.toml");
    
    match action {
        InjectAction::Enable => {
            config.injection.enabled = true;
            config.save()?;
            info!("✅ Injection enabled");
            println!("Injection is now ENABLED");
            println!("Restart the proxy for changes to take effect");
        }
        InjectAction::Disable => {
            config.injection.enabled = false;
            config.save()?;
            info!("❌ Injection disabled");
            println!("Injection is now DISABLED");
        }
        InjectAction::Status => {
            println!("═══════════════════════════════════════════════════");
            println!("          INJECTION STATUS");
            println!("═══════════════════════════════════════════════════");
            println!();
            println!("Enabled: {}", if config.injection.enabled { "✅ YES" } else { "❌ NO" });
            println!();
            
            if let Some(ref prompt) = config.injection.system_prompt {
                println!("System Prompt:");
                println!("  {}", prompt.lines().next().unwrap_or("(empty)"));
                if prompt.lines().count() > 1 {
                    println!("  ... ({} more lines)", prompt.lines().count() - 1);
                }
            } else {
                println!("System Prompt: (not set)");
            }
            println!();
            
            if let Some(ref version) = config.injection.spoof_version {
                println!("Spoofed Version: {}", version);
            } else {
                println!("Spoofed Version: (not set - using real version)");
            }
            println!();
            
            println!("Context Files: {}", config.injection.context_files.len());
            for path in &config.injection.context_files {
                let exists = path.exists();
                println!("  {} {}", if exists { "✅" } else { "❌" }, path.display());
            }
            println!();
            
            println!("Custom Headers: {}", config.injection.headers.len());
            for (key, value) in &config.injection.headers {
                println!("  {}: {}", key, value);
            }
            println!();
            println!("═══════════════════════════════════════════════════");
        }
        InjectAction::Prompt { prompt } => {
            let text = if prompt.starts_with('@') {
                // Read from file
                let path = &prompt[1..];
                std::fs::read_to_string(path)
                    .map_err(|e| error::ConfigError::NotFound(format!("Failed to read prompt file: {}", e)))?
            } else {
                prompt
            };
            
            config.injection.system_prompt = Some(text.clone());
            config.save()?;
            
            println!("✅ System prompt set ({} chars)", text.len());
            println!("Preview: {}...", text.chars().take(50).collect::<String>());
        }
        InjectAction::Version { version } => {
            config.injection.spoof_version = Some(version.clone());
            config.save()?;
            println!("✅ Version spoofing set to: {}", version);
            println!("All requests will use X-Cursor-Client-Version: {}", version);
        }
        InjectAction::AddContext { path } => {
            let abs_path = if path.is_absolute() {
                path
            } else {
                std::env::current_dir()?.join(path)
            };
            
            if !abs_path.exists() {
                return Err(error::ConfigError::NotFound(format!("File not found: {}", abs_path.display())).into());
            }
            
            if !config.injection.context_files.contains(&abs_path) {
                config.injection.context_files.push(abs_path.clone());
                config.save()?;
            }
            
            println!("✅ Added context file: {}", abs_path.display());
            println!("Total context files: {}", config.injection.context_files.len());
        }
        InjectAction::ClearContext => {
            let count = config.injection.context_files.len();
            config.injection.context_files.clear();
            config.save()?;
            println!("✅ Cleared {} context files", count);
        }
        InjectAction::Reload => {
            // TODO: Send IPC message to running proxy to reload
            println!("⚠️  Hot-reload not implemented yet");
            println!("Please restart the proxy for changes to take effect");
        }
        InjectAction::Edit => {
            // Ensure directory exists
            std::fs::create_dir_all(&injection_dir)?;
            
            // Create default rules file if not exists
            if !rules_path.exists() {
                let example = include_str!("../injection-rules.toml.example");
                std::fs::write(&rules_path, example)?;
            }
            
            // Open in editor
            let editor = std::env::var("EDITOR").unwrap_or_else(|_| "vim".to_string());
            let status = std::process::Command::new(&editor)
                .arg(&rules_path)
                .status()
                .map_err(|e| error::ConfigError::Write(format!("Failed to open editor: {}", e)))?;
            
            if status.success() {
                println!("✅ Rules file saved: {}", rules_path.display());
                println!("Restart the proxy for changes to take effect");
            }
        }
    }
    
    Ok(())
}

/// Launch real-time LED dashboard
async fn cmd_dashboard() -> ProxyResult<()> {
    use crate::dashboard::Dashboard;
    use crate::events::{EventBroadcaster, EventReceiver, ProxyEvent, UpstreamAction};
    use crate::ipc::IpcClient;
    use chrono::Utc;
    
    let client = IpcClient::new();
    
    if client.is_proxy_running() {
        // Connect to running proxy
        info!("Connecting to running proxy...");
        
        match client.connect().await {
            Ok(mut stream) => {
                info!("Connected! Starting dashboard...");
                
                // Create local broadcaster to feed dashboard
                let broadcaster = EventBroadcaster::new();
                let receiver = broadcaster.subscribe();
                
                // Spawn task to read from IPC and broadcast
                let bc = broadcaster.clone();
                tokio::spawn(async move {
                    while let Some(event) = stream.next().await {
                        bc.emit(event);
                    }
                });
                
                // Run dashboard
                let mut dashboard = Dashboard::new();
                dashboard.run(receiver).await;
            }
            Err(e) => {
                error!("Failed to connect to proxy: {}", e);
                info!("Starting demo mode instead...");
                run_demo_dashboard().await;
            }
        }
    } else {
        info!("No running proxy detected. Starting demo mode...");
        info!("To see live data, start the proxy first:");
        info!("  sudo cursor-proxy start --port 443 --foreground");
        info!("");
        run_demo_dashboard().await;
    }
    
    Ok(())
}

/// Run dashboard in demo mode with simulated events
async fn run_demo_dashboard() {
    use crate::events::{EventBroadcaster, ProxyEvent, UpstreamAction};
    use crate::dashboard::Dashboard;
    use chrono::Utc;
    
    let broadcaster = EventBroadcaster::new();
    let receiver = broadcaster.subscribe();
    
    // Spawn a task to generate demo events
    let demo_broadcaster = broadcaster.clone();
    tokio::spawn(async move {
        let mut conn_id = 0u64;
        let mut req_id = 0u64;
        
        loop {
            tokio::time::sleep(std::time::Duration::from_millis(500 + rand_delay())).await;
            
            conn_id += 1;
            req_id += 1;
            
            // Simulate various events
            let paths = [
                "/aiserver.v1.ChatService/StreamUnifiedChatWithToolsSSE",
                "/aiserver.v1.AiService/AvailableModels",
                "/aiserver.v1.AiService/CheckQueuePosition",
                "/aiserver.v1.AiService/UpdateVscodeProfile",
                "/aiserver.v1.AiService/ServerTime",
            ];
            
            let path = paths[conn_id as usize % paths.len()];
            let (service, endpoint) = crate::events::parse_path(path);
            
            demo_broadcaster.emit(ProxyEvent::ConnectionOpened {
                conn_id,
                peer_addr: "127.0.0.1:54321".to_string(),
                timestamp: Utc::now(),
            });
            
            demo_broadcaster.emit(ProxyEvent::RequestStarted {
                conn_id,
                request_id: req_id,
                method: "POST".to_string(),
                path: path.to_string(),
                service,
                endpoint: endpoint.clone(),
                timestamp: Utc::now(),
            });
            
            // Simulate request duration
            let duration = 50 + rand_delay() as u64;
            tokio::time::sleep(std::time::Duration::from_millis(duration)).await;
            
            let status = if rand_delay() > 180 { 502 } else { 200 };
            
            demo_broadcaster.emit(ProxyEvent::RequestCompleted {
                conn_id,
                request_id: req_id,
                status,
                duration_ms: duration,
                request_size: 256,
                response_size: Some(1024),
                timestamp: Utc::now(),
            });
            
            demo_broadcaster.emit(ProxyEvent::ConnectionClosed {
                conn_id,
                timestamp: Utc::now(),
                duration_ms: duration + 10,
            });
            
            // Sometimes emit capture event
            if conn_id % 3 == 0 {
                demo_broadcaster.emit(ProxyEvent::CaptureSaved {
                    conn_id,
                    path: format!("/root/.cursor-proxy/captures/{}.json", req_id),
                    size: 2048,
                    timestamp: Utc::now(),
                });
            }
            
            // Sometimes emit upstream event
            if conn_id % 5 == 0 {
                demo_broadcaster.emit(ProxyEvent::UpstreamConnection {
                    target: "api2.cursor.sh".to_string(),
                    action: UpstreamAction::Reused,
                    pool_size: 3,
                    timestamp: Utc::now(),
                });
            }
        }
    });
    
    // Run dashboard
    let mut dashboard = Dashboard::new();
    dashboard.run(receiver).await;
}

/// Simple pseudo-random delay (no external dep needed)
fn rand_delay() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .subsec_nanos();
    (nanos % 200) as u64
}

/// Initialize proxy (generate CA, create config)
async fn cmd_init(force: bool) -> ProxyResult<()> {
    info!("Initializing Cursor Proxy...");
    
    let mut config = Config::load().unwrap_or_default();
    config.expand_paths();
    config.ensure_directories()?;
    
    // Generate or load CA
    if force || !config.ca.cert_path.exists() {
        info!("Generating CA certificate...");
        let ca = CertificateAuthority::generate(&config.ca)?;
        ca.save(&config.ca.cert_path, &config.ca.key_path)?;
        
        info!("✓ CA certificate created at {:?}", config.ca.cert_path);
        info!("  Run 'cursor-proxy trust-ca' to add to system trust store");
    } else {
        info!("✓ CA certificate already exists at {:?}", config.ca.cert_path);
    }
    
    // Save config
    config.save()?;
    info!("✓ Configuration saved to {:?}", Config::default_path());
    
    info!("");
    info!("Initialization complete! Next steps:");
    info!("  1. Trust the CA: cursor-proxy trust-ca");
    info!("  2. Start proxy:  cursor-proxy start --transparent");
    info!("  3. Launch Cursor with: cursor-studio --proxy");
    
    Ok(())
}

/// Start the proxy server
async fn cmd_start(port: Option<u16>, dns_mode: bool, transparent: bool, foreground: bool, force: bool) -> ProxyResult<()> {
    let mut config = Config::load()?;
    config.expand_paths();
    
    // Check if proxy is disabled in config (unless --force is used)
    if !config.proxy.enabled && !force {
        info!("⚠️  Proxy is disabled in configuration");
        info!("To enable: cursor-proxy enable");
        info!("Or override: cursor-proxy start --force");
        return Ok(());
    }
    
    // Set appropriate default port based on mode
    let default_port = if dns_mode { 443 } else { 8443 };
    
    // Override port if specified
    config.proxy.port = port.unwrap_or(default_port);
    
    // DNS mode validation
    if dns_mode {
        info!("╔══════════════════════════════════════════════════════════════╗");
        info!("║              DNS-Based Interception Mode                      ║");
        info!("╠══════════════════════════════════════════════════════════════╣");
        info!("║ This mode requires:                                           ║");
        info!("║   1. /etc/hosts entry: 127.0.0.1 api2.cursor.sh              ║");
        info!("║   2. Port 443 access (CAP_NET_BIND_SERVICE or root)          ║");
        info!("║                                                               ║");
        info!("║ Advantages:                                                   ║");
        info!("║   - No DNS rotation problems (intercepts name, not IPs)       ║");
        info!("║   - More reliable than iptables approach                      ║");
        info!("║   - Easy to enable/disable (just edit /etc/hosts)            ║");
        info!("╚══════════════════════════════════════════════════════════════╝");
        
        // Check if /etc/hosts has the entry
        let hosts_content = std::fs::read_to_string("/etc/hosts").unwrap_or_default();
        if !hosts_content.contains("api2.cursor.sh") {
            error!("⚠️  /etc/hosts does not contain api2.cursor.sh entry!");
            error!("");
            error!("Add this line to /etc/hosts:");
            error!("  127.0.0.1 api2.cursor.sh");
            error!("");
            error!("On NixOS, add to configuration.nix:");
            error!("  networking.hosts.\"127.0.0.1\" = [ \"api2.cursor.sh\" ];");
            error!("");
            return Err(ProxyError::Internal("Missing /etc/hosts entry for DNS mode. Add: 127.0.0.1 api2.cursor.sh".into()));
        }
        
        info!("✓ /etc/hosts has api2.cursor.sh entry");
    }
    
    // Load CA
    let ca = CertificateAuthority::load_or_generate(&config.ca)?;
    
    // Create server (async - initializes DNS resolver)
    let mut server = ProxyServer::new(config.clone(), ca).await?;
    
    // Setup iptables transparent mode if requested (legacy)
    if transparent && !dns_mode {
        // Try to setup iptables - the commands use sudo internally
        // so we don't need to be root, just have sudo access
        match server.setup_transparent() {
            Ok(_) => {}
            Err(e) => {
                error!("Failed to setup transparent mode: {}", e);
                error!("Consider using --dns-mode instead (more reliable)");
                info!("Or launch Cursor with: cursor-studio --proxy");
            }
        }
    }
    
    // Start server
    let server = Arc::new(server);
    
    // Start IPC server for dashboard connections
    let ipc_server = crate::ipc::IpcServer::new(server.event_broadcaster());
    let socket_path = ipc_server.socket_path().to_path_buf();
    tokio::spawn(async move {
        if let Err(e) = ipc_server.run().await {
            error!("IPC server error: {}", e);
        }
    });
    info!("Dashboard IPC available at: {:?}", socket_path);
    info!("Run 'cursor-proxy dashboard' in another terminal to monitor");
    
    // Setup signal handlers
    let server_clone = Arc::clone(&server);
    tokio::spawn(async move {
        tokio::signal::ctrl_c().await.ok();
        info!("Received Ctrl+C, shutting down...");
        server_clone.stop();
        // Clean up socket
        let _ = std::fs::remove_file(&socket_path);
    });
    
    server.start().await
}

/// Stop the proxy server
async fn cmd_stop() -> ProxyResult<()> {
    info!("Stopping proxy...");
    
    // Check for PID file
    let pid_file = dirs::home_dir()
        .unwrap_or_default()
        .join(".cursor-proxy")
        .join("proxy.pid");
    
    if pid_file.exists() {
        let pid_str = std::fs::read_to_string(&pid_file)?;
        if let Ok(pid) = pid_str.trim().parse::<i32>() {
            // Try to kill the process
            unsafe {
                libc::kill(pid, libc::SIGTERM);
            }
            std::fs::remove_file(&pid_file)?;
            info!("✓ Stopped proxy (PID {})", pid);
        }
    } else {
        info!("No proxy running (no PID file found)");
    }
    
    // Clean up iptables rules
    if IptablesManager::is_available() && IptablesManager::has_root() {
        let config = Config::load()?;
        let manager = IptablesManager::new(config.proxy.port, false)?;
        let removed = manager.remove_all()?;
        if removed > 0 {
            info!("✓ Removed {} iptables rules", removed);
        }
    }
    
    Ok(())
}

/// Show proxy status
async fn cmd_status() -> ProxyResult<()> {
    let config = Config::load().unwrap_or_default();
    
    println!("Cursor Proxy Status");
    println!("═══════════════════");
    println!();
    
    // Check if running
    let pid_file = dirs::home_dir()
        .unwrap_or_default()
        .join(".cursor-proxy")
        .join("proxy.pid");
    
    if pid_file.exists() {
        let pid = std::fs::read_to_string(&pid_file).unwrap_or_default();
        println!("Status:  🟢 Running (PID {})", pid.trim());
    } else {
        println!("Status:  🔴 Not running");
    }
    
    println!("Port:    {}", config.proxy.port);
    
    // CA status
    let mut expanded_config = config.clone();
    expanded_config.expand_paths();
    
    if expanded_config.ca.cert_path.exists() {
        println!("CA:      ✓ {:?}", expanded_config.ca.cert_path);
    } else {
        println!("CA:      ✗ Not found (run 'cursor-proxy init')");
    }
    
    // iptables status
    if IptablesManager::is_available() {
        if let Ok(rules) = IptablesManager::list_all_rules() {
            let rule_count = rules.lines().filter(|l| l.contains("REDIRECT")).count();
            println!("iptables: {} redirect rules active", rule_count);
        }
    } else {
        println!("iptables: Not available");
    }
    
    println!();
    Ok(())
}

/// Trust CA certificate
async fn cmd_trust_ca(show: bool, output: Option<PathBuf>) -> ProxyResult<()> {
    let mut config = Config::load()?;
    config.expand_paths();
    
    let ca = CertificateAuthority::load_or_generate(&config.ca)?;
    let pem = ca.ca_cert_pem();
    
    if show {
        println!("{}", pem);
        return Ok(());
    }
    
    if let Some(path) = output {
        std::fs::write(&path, &pem)?;
        info!("✓ CA certificate written to {:?}", path);
        return Ok(());
    }
    
    // Show instructions for trusting
    info!("CA Certificate Location: {:?}", config.ca.cert_path);
    info!("");
    info!("To trust system-wide (NixOS):");
    info!("  Add to configuration.nix:");
    info!("    security.pki.certificateFiles = [ \"{}\" ];", config.ca.cert_path.display());
    info!("");
    info!("To trust for Cursor only:");
    info!("  Launch with: NODE_EXTRA_CA_CERTS=\"{}\" cursor", config.ca.cert_path.display());
    info!("");
    info!("Or copy the certificate:");
    info!("  cursor-proxy trust-ca --output /path/to/ca.pem");
    
    Ok(())
}

/// Manage iptables rules
async fn cmd_iptables(action: IptablesAction) -> ProxyResult<()> {
    let config = Config::load()?;
    
    match action {
        IptablesAction::Add => {
            let manager = IptablesManager::new(config.proxy.port, false)?;
            for target in &config.iptables.targets {
                let added = manager.add_domain(target)?;
                info!("Added {} IPs for {}", added.len(), target);
            }
        }
        
        IptablesAction::Remove => {
            let manager = IptablesManager::new(config.proxy.port, false)?;
            let removed = manager.remove_all()?;
            info!("Removed {} rules", removed);
        }
        
        IptablesAction::Show => {
            let rules = IptablesManager::list_all_rules()?;
            println!("{}", rules);
        }
        
        IptablesAction::Refresh => {
            let manager = IptablesManager::new(config.proxy.port, false)?;
            for target in &config.iptables.targets {
                manager.refresh_domain(target)?;
            }
            info!("Refreshed rules");
        }
        
        IptablesAction::Flush => {
            IptablesManager::flush_all()?;
            info!("Flushed all NAT OUTPUT rules");
        }
    }
    
    Ok(())
}

/// View captured payloads
async fn cmd_captures(pattern: Option<String>, recent: Option<u32>) -> ProxyResult<()> {
    let mut config = Config::load()?;
    config.expand_paths();
    
    let capture_dir = &config.capture.directory;
    
    if !capture_dir.exists() {
        info!("No captures directory found at {:?}", capture_dir);
        return Ok(());
    }
    
    info!("Captures directory: {:?}", capture_dir);
    
    // List capture files
    let mut files: Vec<_> = std::fs::read_dir(capture_dir)?
        .filter_map(|e| e.ok())
        .collect();
    
    files.sort_by_key(|e| e.file_name());
    
    for entry in files.iter().rev().take(20) {
        println!("  {}", entry.file_name().to_string_lossy());
    }
    
    if files.len() > 20 {
        println!("  ... and {} more", files.len() - 20);
    }
    
    Ok(())
}

/// Show/edit configuration
async fn cmd_config(edit: bool) -> ProxyResult<()> {
    let path = Config::default_path();
    
    if edit {
        // Open in editor
        let editor = std::env::var("EDITOR").unwrap_or_else(|_| "nano".to_string());
        std::process::Command::new(&editor)
            .arg(&path)
            .status()?;
    } else {
        // Show config
        if path.exists() {
            let content = std::fs::read_to_string(&path)?;
            println!("{}", content);
        } else {
            // Show default config
            let config = Config::default();
            let content = toml::to_string_pretty(&config)
                .map_err(|e| ProxyError::Internal(e.to_string()))?;
            println!("# Default configuration (not yet saved)\n");
            println!("{}", content);
        }
    }
    
    Ok(())
}

/// Enable proxy in configuration
async fn cmd_enable() -> ProxyResult<()> {
    let mut config = Config::load().unwrap_or_default();
    config.proxy.enabled = true;
    config.save()?;
    
    info!("✓ Proxy enabled in configuration");
    info!("  Start with: cursor-proxy start");
    Ok(())
}

/// Disable proxy in configuration
async fn cmd_disable() -> ProxyResult<()> {
    // First stop the proxy if running
    cmd_stop().await?;
    
    // Update configuration
    let mut config = Config::load().unwrap_or_default();
    config.proxy.enabled = false;
    config.save()?;
    
    info!("✓ Proxy disabled in configuration");
    info!("  To re-enable: cursor-proxy enable");
    Ok(())
}

/// Clean up everything
async fn cmd_cleanup(all: bool) -> ProxyResult<()> {
    info!("Cleaning up...");
    
    // Stop proxy first
    cmd_stop().await?;
    
    // Flush iptables
    if IptablesManager::is_available() && IptablesManager::has_root() {
        IptablesManager::flush_all()?;
        info!("✓ Flushed iptables rules");
    }
    
    if all {
        let proxy_dir = dirs::home_dir()
            .unwrap_or_default()
            .join(".cursor-proxy");
        
        if proxy_dir.exists() {
            std::fs::remove_dir_all(&proxy_dir)?;
            info!("✓ Removed {:?}", proxy_dir);
        }
        
        let config_path = Config::default_path();
        if config_path.exists() {
            std::fs::remove_file(&config_path)?;
            info!("✓ Removed {:?}", config_path);
        }
    }
    
    info!("✓ Cleanup complete");
    Ok(())
}

