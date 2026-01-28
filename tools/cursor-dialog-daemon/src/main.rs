//! Cursor Dialog Daemon
//!
//! D-Bus service providing interactive dialogs for AI agents.
//!
//! # Architecture
//!
//! - Main thread: Runs the egui GUI
//! - Background tokio runtime: Handles D-Bus async operations and web server
//! - Sync channels bridge between async D-Bus and sync GUI
//! - Web server provides PWA for remote access via Tailscale
//!
//! # Usage
//!
//! Start the daemon:
//! ```bash
//! cursor-dialog-daemon
//! cursor-dialog-daemon --web-port 8080  # Enable web access
//! ```

mod dbus_interface;
mod dialog;
mod gui;
mod web;

use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};
use tracing::{error, info, warn};
use tracing_subscriber::EnvFilter;

use clap::Parser;

#[derive(Parser, Debug)]
#[command(name = "cursor-dialog-daemon")]
#[command(about = "D-Bus daemon for Cursor agent interactive dialogs")]
#[command(version)]
struct Args {
    /// Run in headless mode (no GUI, for testing)
    #[arg(long)]
    headless: bool,

    /// Log level (trace, debug, info, warn, error)
    #[arg(long, default_value = "info")]
    log_level: String,

    /// Don't register with D-Bus (for GUI testing)
    #[arg(long)]
    no_dbus: bool,

    /// Enable web server for remote access (PWA)
    #[arg(long)]
    web_port: Option<u16>,
}

fn main() -> anyhow::Result<()> {
    let args = Args::parse();

    // Initialize logging
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(&args.log_level));
    
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(false)
        .init();

    info!("Starting Cursor Dialog Daemon v{}", env!("CARGO_PKG_VERSION"));

    // Create a multi-threaded tokio runtime
    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .worker_threads(2)
        .build()
        .expect("Failed to build tokio runtime");

    // Create dialog manager (shared state)
    let manager = Arc::new(RwLock::new(dialog::DialogManager::new()));

    // Create async channel for dialog requests
    let (async_tx, async_rx) = mpsc::channel(32);
    
    // Create sync channel for GUI
    let (sync_tx, sync_rx) = std::sync::mpsc::channel();

    // Start D-Bus service within the tokio runtime
    let no_dbus = args.no_dbus;
    let _dbus_guard = rt.enter();  // Enter runtime context for any async work
    
    rt.spawn(async move {
        if !no_dbus {
            match dbus_interface::start_dbus_service(async_tx).await {
                Ok(conn) => {
                    info!("D-Bus service started successfully");
                    // Keep connection alive - this task runs forever
                    loop {
                        tokio::time::sleep(tokio::time::Duration::from_secs(3600)).await;
                        let _ = &conn;
                    }
                }
                Err(e) => {
                    error!("Failed to start D-Bus service: {}", e);
                    error!("Hint: Make sure D-Bus session bus is running");
                }
            }
        } else {
            info!("D-Bus registration disabled");
        }
    });

    // Start web server for remote access (PWA)
    if let Some(port) = args.web_port {
        let web_manager = manager.clone();
        rt.spawn(async move {
            match web::start_web_server(web_manager, port).await {
                Ok(_updates_tx) => {
                    info!("Web server started on port {}", port);
                    info!("Remote access via Tailscale: http://obsidian:{}", port);
                }
                Err(e) => {
                    error!("Failed to start web server: {}", e);
                }
            }
        });
    }

    // Bridge task: forward from async to sync channel
    rt.spawn(async move {
        let mut async_rx = async_rx;
        while let Some(msg) = async_rx.recv().await {
            if sync_tx.send(msg).is_err() {
                warn!("GUI channel closed");
                break;
            }
        }
    });

    // Give D-Bus a moment to register
    std::thread::sleep(std::time::Duration::from_millis(500));

    if args.headless {
        info!("Running in headless mode (no GUI)");
        info!("Press Ctrl+C to stop");
        
        // Block forever (D-Bus tasks keep running)
        loop {
            std::thread::sleep(std::time::Duration::from_secs(3600));
        }
    } else {
        info!("Starting GUI...");
        
        let gui_manager = manager.clone();
        
        // Run GUI on main thread (required for graphics)
        if let Err(e) = gui::run_gui_sync(gui_manager, sync_rx) {
            error!("GUI error: {}", e);
        }
        
        info!("GUI closed");
    }

    Ok(())
}
