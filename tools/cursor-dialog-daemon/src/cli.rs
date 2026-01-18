//! CLI tool for testing the Dialog Daemon
//!
//! # Usage
//!
//! Show a multiple choice dialog:
//! ```bash
//! cursor-dialog-cli choice \
//!   --title "Summary Detail Level" \
//!   --prompt "How detailed should the task summary be?" \
//!   --options '[{"value":"minimal","label":"Minimal"},{"value":"standard","label":"Standard"},{"value":"verbose","label":"Verbose"}]'
//! ```
//!
//! Show a text input:
//! ```bash
//! cursor-dialog-cli text \
//!   --title "Project Name" \
//!   --prompt "Enter a name for your project:" \
//!   --placeholder "my-awesome-project"
//! ```
//!
//! Show a confirmation:
//! ```bash
//! cursor-dialog-cli confirm \
//!   --title "Apply Changes" \
//!   --prompt "Apply 15 file changes to the codebase?"
//! ```

use clap::{Parser, Subcommand};
use serde_json::json;
use tracing::{error, info};
use zbus::Connection;

#[derive(Parser, Debug)]
#[command(name = "cursor-dialog-cli")]
#[command(about = "CLI tool for testing Cursor Dialog Daemon")]
#[command(version)]
struct Args {
    #[command(subcommand)]
    command: Commands,

    /// Timeout in seconds (0 for no timeout)
    #[arg(long, short, default_value = "30")]
    timeout: u32,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Show a multiple choice dialog
    Choice {
        #[arg(long, short)]
        title: String,
        #[arg(long, short)]
        prompt: String,
        /// JSON array of options
        #[arg(long, short)]
        options: String,
        /// Default selected value
        #[arg(long)]
        default: Option<String>,
        /// Allow multiple selections
        #[arg(long)]
        multi: bool,
    },

    /// Show a text input dialog
    Text {
        #[arg(long, short)]
        title: String,
        #[arg(long, short)]
        prompt: String,
        #[arg(long)]
        placeholder: Option<String>,
        #[arg(long)]
        default: Option<String>,
        /// Enable multiline input
        #[arg(long)]
        multiline: bool,
        /// Validation regex
        #[arg(long)]
        validation: Option<String>,
    },

    /// Show a confirmation dialog
    Confirm {
        #[arg(long, short)]
        title: String,
        #[arg(long, short)]
        prompt: String,
        /// Label for Yes button
        #[arg(long, default_value = "Yes")]
        yes: String,
        /// Label for No button
        #[arg(long, default_value = "No")]
        no: String,
        /// Default to Yes
        #[arg(long)]
        default_yes: bool,
    },

    /// Show a slider dialog
    Slider {
        #[arg(long, short)]
        title: String,
        #[arg(long, short)]
        prompt: String,
        #[arg(long, default_value = "0")]
        min: f64,
        #[arg(long, default_value = "100")]
        max: f64,
        #[arg(long, default_value = "1")]
        step: f64,
        #[arg(long, default_value = "50")]
        default: f64,
        /// Unit label (e.g., "%", "tokens")
        #[arg(long)]
        unit: Option<String>,
    },

    /// Show a toast notification (non-blocking)
    Toast {
        /// Message to display
        #[arg(long, short)]
        message: String,
        /// Severity level: info, success, warning, error
        #[arg(long, short, default_value = "info")]
        level: String,
        /// Duration in ms (0 = until dismissed, default 5000)
        #[arg(long, short, default_value = "5000")]
        duration: u32,
    },

    /// Check daemon status
    Ping,

    /// Get daemon info
    Info,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("info")
        .with_target(false)
        .init();

    let args = Args::parse();
    let timeout_ms = args.timeout * 1000;

    // Connect to D-Bus
    let connection = Connection::session().await?;

    let proxy = zbus::Proxy::new(
        &connection,
        "sh.cursor.studio.Dialog",
        "/sh/cursor/studio/Dialog",
        "sh.cursor.studio.Dialog1",
    )
    .await?;

    let result: String = match args.command {
        Commands::Choice {
            title,
            prompt,
            options,
            default,
            multi,
        } => {
            proxy
                .call(
                    "ShowChoice",
                    &(
                        title,
                        prompt,
                        options,
                        default.unwrap_or_default(),
                        multi,
                        timeout_ms,
                    ),
                )
                .await?
        }

        Commands::Text {
            title,
            prompt,
            placeholder,
            default,
            multiline,
            validation,
        } => {
            proxy
                .call(
                    "ShowTextInput",
                    &(
                        title,
                        prompt,
                        placeholder.unwrap_or_default(),
                        default.unwrap_or_default(),
                        multiline,
                        validation.unwrap_or_default(),
                        timeout_ms,
                    ),
                )
                .await?
        }

        Commands::Confirm {
            title,
            prompt,
            yes,
            no,
            default_yes,
        } => {
            proxy
                .call(
                    "ShowConfirmation",
                    &(title, prompt, yes, no, default_yes, timeout_ms),
                )
                .await?
        }

        Commands::Slider {
            title,
            prompt,
            min,
            max,
            step,
            default,
            unit,
        } => {
            proxy
                .call(
                    "ShowSlider",
                    &(
                        title,
                        prompt,
                        min,
                        max,
                        step,
                        default,
                        unit.unwrap_or_default(),
                        timeout_ms,
                    ),
                )
                .await?
        }

        Commands::Toast {
            message,
            level,
            duration,
        } => {
            let result: String = proxy
                .call("ShowToast", &(message, level, duration))
                .await?;
            println!("{}", result);
            return Ok(());
        }

        Commands::Ping => {
            let pong: String = proxy.call("Ping", &()).await?;
            println!("Daemon response: {}", pong);
            return Ok(());
        }

        Commands::Info => {
            proxy.call("GetInfo", &()).await?
        }
    };

    // Parse and pretty-print the result
    match serde_json::from_str::<serde_json::Value>(&result) {
        Ok(json) => {
            println!("{}", serde_json::to_string_pretty(&json)?);
            
            // Exit with error if cancelled
            if json.get("cancelled").and_then(|v| v.as_bool()).unwrap_or(false) {
                std::process::exit(1);
            }
        }
        Err(_) => {
            println!("{}", result);
        }
    }

    Ok(())
}

