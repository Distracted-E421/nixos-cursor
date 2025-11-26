//! Cursor Manager - Fast, reliable Cursor IDE version manager
//!
//! A Rust-based tool for managing multiple Cursor IDE installations
//! with support for version switching, instance isolation, and disk management.

mod config;
mod version;
mod instance;
mod download;
mod cli;

use anyhow::Result;
use clap::Parser;
use tracing_subscriber::{fmt, EnvFilter};

use cli::{Cli, Commands};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .with_target(false)
        .init();

    let cli = Cli::parse();

    match cli.command {
        Commands::List { all } => {
            cli::list_versions(all).await?;
        }
        Commands::Install { version, force } => {
            cli::install_version(&version, force).await?;
        }
        Commands::Use { version } => {
            cli::use_version(&version).await?;
        }
        Commands::Current => {
            cli::show_current().await?;
        }
        Commands::Uninstall { version, keep_data } => {
            cli::uninstall_version(&version, keep_data).await?;
        }
        Commands::Info { version } => {
            cli::show_info(&version).await?;
        }
        Commands::Clean { older_than, dry_run } => {
            cli::clean_versions(older_than, dry_run).await?;
        }
        Commands::Config { key, value } => {
            cli::manage_config(key, value).await?;
        }
    }

    Ok(())
}
