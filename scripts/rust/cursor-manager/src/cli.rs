//! CLI command definitions and handlers

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use console::{style, Emoji};
use indicatif::{ProgressBar, ProgressStyle};

use crate::config::Config;
use crate::version::VersionManager;
use crate::download::Downloader;

static CHECK: Emoji = Emoji("✓ ", "* ");
static CROSS: Emoji = Emoji("✗ ", "x ");
static ARROW: Emoji = Emoji("→ ", "-> ");
static INFO: Emoji = Emoji("ℹ ", "i ");

#[derive(Parser)]
#[command(name = "cursor-manager")]
#[command(author, version, about = "Fast, reliable Cursor IDE version manager")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,

    /// Enable verbose output
    #[arg(short, long, global = true)]
    pub verbose: bool,
}

#[derive(Subcommand)]
pub enum Commands {
    /// List available Cursor versions
    List {
        /// Show all versions including pre-releases
        #[arg(short, long)]
        all: bool,
    },

    /// Install a specific Cursor version
    Install {
        /// Version to install (e.g., 2.1.34, latest, stable)
        version: String,

        /// Force reinstall even if already installed
        #[arg(short, long)]
        force: bool,
    },

    /// Switch to a specific Cursor version
    Use {
        /// Version to use
        version: String,
    },

    /// Show currently active Cursor version
    Current,

    /// Uninstall a Cursor version
    Uninstall {
        /// Version to uninstall
        version: String,

        /// Keep user data (settings, extensions)
        #[arg(short, long)]
        keep_data: bool,
    },

    /// Show detailed information about a version
    Info {
        /// Version to inspect (default: current)
        #[arg(default_value = "current")]
        version: String,
    },

    /// Clean up old versions and cache
    Clean {
        /// Remove versions older than N days
        #[arg(short, long)]
        older_than: Option<u32>,

        /// Show what would be removed without removing
        #[arg(short = 'n', long)]
        dry_run: bool,
    },

    /// Manage configuration
    Config {
        /// Configuration key
        key: Option<String>,

        /// Configuration value (omit to show current)
        value: Option<String>,
    },
}

/// List available versions
pub async fn list_versions(all: bool) -> Result<()> {
    let manager = VersionManager::new()?;
    let installed = manager.list_installed()?;
    let current = manager.current_version()?;

    println!("{}", style("Installed Cursor versions:").bold());
    println!();

    if installed.is_empty() {
        println!("  {} No versions installed", INFO);
        println!();
        println!("  Install one with: {} cursor-manager install latest", style("$").dim());
    } else {
        for version in &installed {
            let marker = if Some(version) == current.as_ref() {
                style("→").green().bold()
            } else {
                style(" ").dim()
            };

            let size = version.disk_size_human();
            println!("  {} {} {}", marker, style(&version.version).cyan(), style(size).dim());
        }
    }

    if all {
        println!();
        println!("{}", style("Available versions:").bold());
        let available = manager.list_available().await?;
        for version in available.iter().take(10) {
            let installed_marker = if installed.iter().any(|i| i.version == *version) {
                style("[installed]").green().dim()
            } else {
                style("").dim()
            };
            println!("  {} {}", style(version).cyan(), installed_marker);
        }
        if available.len() > 10 {
            println!("  {} ... and {} more", INFO, available.len() - 10);
        }
    }

    Ok(())
}

/// Install a specific version
pub async fn install_version(version: &str, force: bool) -> Result<()> {
    let manager = VersionManager::new()?;
    let downloader = Downloader::new()?;

    // Resolve version string
    let resolved = manager.resolve_version(version).await?;
    println!("{} Resolved {} to {}", INFO, style(version).cyan(), style(&resolved).green());

    // Check if already installed
    if manager.is_installed(&resolved)? && !force {
        println!("{} Version {} is already installed", CHECK, style(&resolved).green());
        println!("  Use {} to reinstall", style("--force").yellow());
        return Ok(());
    }

    // Download with progress
    println!("{} Downloading Cursor {}...", ARROW, style(&resolved).cyan());
    
    let pb = ProgressBar::new(100);
    pb.set_style(ProgressStyle::default_bar()
        .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({eta})")?
        .progress_chars("█▓░"));

    let path = downloader.download(&resolved, |progress| {
        pb.set_position(progress as u64);
    }).await?;

    pb.finish_with_message("Downloaded");

    // Install
    println!("{} Installing...", ARROW);
    manager.install(&resolved, &path)?;

    println!("{} Successfully installed Cursor {}", CHECK, style(&resolved).green());
    println!("  Switch to it with: {} cursor-manager use {}", style("$").dim(), resolved);

    Ok(())
}

/// Switch to a specific version
pub async fn use_version(version: &str) -> Result<()> {
    let manager = VersionManager::new()?;
    
    let resolved = manager.resolve_version(version).await?;

    if !manager.is_installed(&resolved)? {
        println!("{} Version {} is not installed", CROSS, style(&resolved).red());
        println!("  Install it first: {} cursor-manager install {}", style("$").dim(), resolved);
        return Ok(());
    }

    manager.set_current(&resolved)?;
    println!("{} Now using Cursor {}", CHECK, style(&resolved).green());

    Ok(())
}

/// Show current version
pub async fn show_current() -> Result<()> {
    let manager = VersionManager::new()?;

    match manager.current_version()? {
        Some(version) => {
            println!("{} {}", ARROW, style(&version.version).green().bold());
            println!("  Path: {}", style(&version.path.display()).dim());
            println!("  Size: {}", style(version.disk_size_human()).dim());
        }
        None => {
            println!("{} No version currently active", INFO);
            println!("  Set one with: {} cursor-manager use <version>", style("$").dim());
        }
    }

    Ok(())
}

/// Uninstall a version
pub async fn uninstall_version(version: &str, keep_data: bool) -> Result<()> {
    let manager = VersionManager::new()?;

    let resolved = manager.resolve_version(version).await?;

    if !manager.is_installed(&resolved)? {
        println!("{} Version {} is not installed", CROSS, style(&resolved).red());
        return Ok(());
    }

    // Confirm
    let current = manager.current_version()?;
    if current.as_ref().map(|v| &v.version) == Some(&resolved) {
        println!("{} Warning: This is your current active version", style("⚠").yellow());
    }

    manager.uninstall(&resolved, keep_data)?;
    println!("{} Uninstalled Cursor {}", CHECK, style(&resolved).green());

    if keep_data {
        println!("  User data was preserved");
    }

    Ok(())
}

/// Show info about a version
pub async fn show_info(version: &str) -> Result<()> {
    let manager = VersionManager::new()?;

    let resolved = if version == "current" {
        manager.current_version()?
            .map(|v| v.version.clone())
            .context("No current version set")?
    } else {
        manager.resolve_version(version).await?
    };

    let info = manager.get_version_info(&resolved)?;

    println!("{}", style(format!("Cursor {}", resolved)).bold());
    println!();
    println!("  {} Installed: {}", INFO, if info.installed { style("yes").green() } else { style("no").red() });
    
    if info.installed {
        println!("  {} Path: {}", INFO, style(&info.path.display()).dim());
        println!("  {} Size: {}", INFO, style(&info.disk_size_human).cyan());
        println!("  {} Installed: {}", INFO, style(&info.installed_at).dim());
    }

    println!("  {} Download URL: {}", INFO, style(&info.download_url).dim());

    Ok(())
}

/// Clean old versions
pub async fn clean_versions(older_than: Option<u32>, dry_run: bool) -> Result<()> {
    let manager = VersionManager::new()?;
    
    let candidates = manager.get_cleanup_candidates(older_than)?;

    if candidates.is_empty() {
        println!("{} Nothing to clean", CHECK);
        return Ok(());
    }

    let total_size: u64 = candidates.iter().map(|v| v.disk_size).sum();

    println!("{}", style("Versions to remove:").bold());
    for version in &candidates {
        println!("  {} {} ({})", ARROW, style(&version.version).cyan(), version.disk_size_human());
    }
    println!();
    println!("  Total: {}", style(format_size(total_size)).yellow());

    if dry_run {
        println!();
        println!("{} Dry run - no changes made", INFO);
    } else {
        for version in &candidates {
            manager.uninstall(&version.version, false)?;
            println!("{} Removed {}", CHECK, style(&version.version).dim());
        }
        println!();
        println!("{} Cleaned {} of disk space", CHECK, style(format_size(total_size)).green());
    }

    Ok(())
}

/// Manage configuration
pub async fn manage_config(key: Option<String>, value: Option<String>) -> Result<()> {
    let mut config = Config::load()?;

    match (key, value) {
        (None, _) => {
            // Show all config
            println!("{}", style("Configuration:").bold());
            println!();
            println!("  install_dir: {}", style(&config.install_dir.display()).cyan());
            println!("  data_dir: {}", style(&config.data_dir.display()).cyan());
            println!("  auto_cleanup: {}", style(config.auto_cleanup).cyan());
            println!("  keep_versions: {}", style(config.keep_versions).cyan());
        }
        (Some(key), None) => {
            // Show specific key
            let value = config.get(&key)?;
            println!("{}: {}", key, style(value).cyan());
        }
        (Some(key), Some(value)) => {
            // Set key
            config.set(&key, &value)?;
            config.save()?;
            println!("{} Set {} = {}", CHECK, key, style(value).green());
        }
    }

    Ok(())
}

fn format_size(bytes: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;

    if bytes >= GB {
        format!("{:.1} GB", bytes as f64 / GB as f64)
    } else if bytes >= MB {
        format!("{:.1} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.1} KB", bytes as f64 / KB as f64)
    } else {
        format!("{} B", bytes)
    }
}
