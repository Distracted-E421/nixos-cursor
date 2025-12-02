//! Cursor Studio CLI - Command-line interface for version management
//!
//! A terminal-based interface for managing Cursor IDE versions,
//! downloading updates, and managing chat history.

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use console::{style, Emoji};
use indicatif::{ProgressBar, ProgressStyle};
use std::path::PathBuf;

// Import from main library
use cursor_studio::approval::{ApprovalManager, ApprovalMode, ApprovalOperation, ApprovalResult};
use cursor_studio::versions::{
    get_available_versions, get_cache_dir, get_version_info,
    install_version, is_version_installed,
};
use cursor_studio::version_registry::{
    CursorVersion, ManualImport, Platform, VersionRegistry, compute_hash,
};

static CHECK: Emoji<'_, '_> = Emoji("✓ ", "+ ");
static CROSS: Emoji<'_, '_> = Emoji("✗ ", "x ");
static ARROW: Emoji<'_, '_> = Emoji("→ ", "-> ");
static INFO: Emoji<'_, '_> = Emoji("ℹ ", "i ");
static DOWNLOAD: Emoji<'_, '_> = Emoji("⬇ ", "v ");
static PACKAGE: Emoji<'_, '_> = Emoji("📦 ", "[] ");

#[derive(Parser)]
#[command(name = "cursor-cli")]
#[command(author = "e421")]
#[command(version = "0.2.1")]
#[command(about = "Cursor Studio CLI - Manage Cursor IDE versions from the terminal")]
#[command(long_about = r#"
Cursor Studio CLI provides terminal-based management of Cursor IDE installations.

Features:
  • List installed and available versions
  • Download new versions with hash verification
  • Install and switch between versions
  • View version details and disk usage

Examples:
  cursor-cli list                    # List all versions
  cursor-cli list --available        # Show downloadable versions
  cursor-cli download 2.1.34         # Download a specific version
  cursor-cli install 2.1.34          # Download and install
  cursor-cli info 2.0.77             # Show version details
"#)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,

    /// Enable verbose output
    #[arg(short, long, global = true)]
    pub verbose: bool,

    /// Skip confirmation prompts (auto-approve)
    #[arg(short = 'y', long, global = true)]
    pub yes: bool,
}

#[derive(Subcommand)]
pub enum Commands {
    /// List Cursor versions
    List {
        /// Show available versions for download
        #[arg(short, long)]
        available: bool,

        /// Show all versions (installed + available)
        #[arg(short = 'A', long)]
        all: bool,
    },

    /// Download a Cursor version
    Download {
        /// Version to download (e.g., 2.1.34, latest)
        version: String,

        /// Force re-download even if cached
        #[arg(short, long)]
        force: bool,

        /// Skip hash verification
        #[arg(long)]
        skip_verify: bool,
    },

    /// Install a Cursor version (download + set up)
    Install {
        /// Version to install
        version: String,

        /// Don't set as default after installing
        #[arg(long)]
        no_default: bool,
    },

    /// Show information about a version
    Info {
        /// Version to inspect (default: latest installed)
        #[arg(default_value = "latest")]
        version: String,
    },

    /// Clean up old downloads and versions
    Clean {
        /// Remove versions older than N days
        #[arg(short, long)]
        older_than: Option<u32>,

        /// Show what would be removed without removing
        #[arg(short = 'n', long)]
        dry_run: bool,

        /// Only clean download cache, not installed versions
        #[arg(short, long)]
        cache_only: bool,
    },

    /// Launch Cursor IDE
    Launch {
        /// Version to launch (default: current)
        #[arg(default_value = "current")]
        version: String,
    },

    /// Show cache and storage info
    Cache,

    /// Compute or verify hash for a file or version
    Hash {
        /// Version number or path to AppImage file
        target: String,

        /// Verify against expected hash instead of computing
        #[arg(short, long)]
        verify: bool,
    },

    /// Check all version hashes are still valid (downloads and verifies)
    VerifyHashes {
        /// Only check versions that have hashes defined
        #[arg(long)]
        only_with_hash: bool,

        /// Don't actually download, just show what would be checked
        #[arg(short = 'n', long)]
        dry_run: bool,
    },

    /// Import a manually downloaded file
    Import {
        /// Path to the downloaded file (AppImage or DMG)
        file: PathBuf,

        /// Version number (e.g., "2.1.34")
        #[arg(short, long)]
        version: String,

        /// Platform (auto-detected from filename if not specified)
        #[arg(short, long)]
        platform: Option<String>,

        /// Update the hash registry after import
        #[arg(long)]
        update_registry: bool,
    },

    /// Show download URLs for manual download
    Urls {
        /// Version number (e.g., "2.1.34", "latest", "2.0.77")
        version: String,

        /// Show all platforms (default: current platform only)
        #[arg(short, long)]
        all: bool,
    },

    /// Export the hash registry to a JSON file (for backup/sharing)
    ExportRegistry {
        /// Output file path (default: stdout)
        #[arg(short, long)]
        output: Option<PathBuf>,
    },

    /// Import/update hash registry from a JSON file
    ImportRegistry {
        /// Input file path
        file: PathBuf,

        /// Merge with existing registry instead of replacing
        #[arg(short, long)]
        merge: bool,
    },
}

fn main() -> Result<()> {
    // Initialize logging
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("warn")).init();

    let cli = Cli::parse();

    // Set up approval mode based on --yes flag
    let approval_mode = if cli.yes {
        ApprovalMode::AutoApprove
    } else {
        ApprovalMode::Terminal
    };
    let mut approval = ApprovalManager::new(approval_mode);

    match cli.command {
        Commands::List { available, all } => cmd_list(available, all),
        Commands::Download {
            version,
            force,
            skip_verify,
        } => cmd_download(&version, force, skip_verify, &mut approval),
        Commands::Install { version, no_default } => {
            cmd_install(&version, no_default, &mut approval)
        }
        Commands::Info { version } => cmd_info(&version),
        Commands::Clean {
            older_than,
            dry_run,
            cache_only,
        } => cmd_clean(older_than, dry_run, cache_only, &mut approval),
        Commands::Launch { version } => cmd_launch(&version),
        Commands::Cache => cmd_cache(),
        Commands::Hash { target, verify } => cmd_hash(&target, verify),
        Commands::VerifyHashes { only_with_hash, dry_run } => cmd_verify_hashes(only_with_hash, dry_run),
        Commands::Import { file, version, platform, update_registry } => {
            cmd_import(&file, &version, platform.as_deref(), update_registry)
        }
        Commands::Urls { version, all } => cmd_urls(&version, all),
        Commands::ExportRegistry { output } => cmd_export_registry(output.as_ref()),
        Commands::ImportRegistry { file, merge } => cmd_import_registry(&file, merge),
    }
}

/// List versions
fn cmd_list(available: bool, all: bool) -> Result<()> {
    let versions = get_available_versions();

    if available || all {
        println!(
            "\n{}",
            style("Available Cursor Versions").bold().underlined()
        );
        println!();

        for v in &versions {
            let installed = is_version_installed(&v.version);
            let marker = if installed {
                style("●").green()
            } else {
                style("○").dim()
            };
            let status = if installed {
                style(" [installed]").green().dim()
            } else {
                style("").dim()
            };
            let hash_indicator = if v.sha256_hash.is_some() {
                style(" ✓").green().dim()
            } else {
                style(" ?").yellow().dim()
            };

            println!(
                "  {} {} v{}{}{}",
                marker,
                if v.is_stable {
                    style("stable").cyan()
                } else {
                    style("dev").yellow()
                },
                style(&v.version).white().bold(),
                status,
                hash_indicator
            );

            if let Some(ref date) = v.release_date {
                println!("      Released: {}", style(date).dim());
            }
        }

        println!();
        println!(
            "  {} = hash verified, {} = no hash available",
            style("✓").green(),
            style("?").yellow()
        );
    }

    // Show installed versions
    if !available || all {
        println!(
            "\n{}",
            style("Installed Versions").bold().underlined()
        );
        println!();

        let installed: Vec<_> = versions
            .iter()
            .filter(|v| is_version_installed(&v.version))
            .collect();

        if installed.is_empty() {
            println!("  {} No versions installed", INFO);
            println!();
            println!(
                "  Install one with: {} cursor-cli install latest",
                style("$").dim()
            );
        } else {
            for v in installed {
                println!(
                    "  {} v{}",
                    style("●").green(),
                    style(&v.version).white().bold()
                );
            }
        }
    }

    println!();
    Ok(())
}

/// Download a version
fn cmd_download(
    version: &str,
    force: bool,
    skip_verify: bool,
    approval: &mut ApprovalManager,
) -> Result<()> {
    // Resolve "latest" to actual version
    let resolved = if version == "latest" {
        let versions = get_available_versions();
        versions.first().map(|v| v.version.clone())
    } else {
        Some(version.to_string())
    };

    let version_str = resolved.context("No versions available")?;

    let version_info = get_version_info(&version_str)
        .context(format!("Version {} not found in available versions", version_str))?;

    // Check cache
    let cache_dir = get_cache_dir();
    let cached_path = cache_dir.join(format!("Cursor-{}-x86_64.AppImage", version_str));

    if cached_path.exists() && !force {
        println!(
            "{} Version {} already cached at {}",
            CHECK,
            style(&version_str).cyan(),
            style(cached_path.display()).dim()
        );
        println!(
            "  Use {} to re-download",
            style("--force").yellow()
        );
        return Ok(());
    }

    // Request approval
    let operation = ApprovalOperation::Download {
        version: version_str.clone(),
        size_estimate: Some(150_000_000),
    };

    if approval.request(operation) != ApprovalResult::Approved {
        println!("{} Download cancelled", CROSS);
        return Ok(());
    }

    // Create progress bar
    let pb = ProgressBar::new(100);
    pb.set_style(
        ProgressStyle::default_bar()
            .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos}% {msg}")?
            .progress_chars("█▓░"),
    );
    pb.set_message(format!("Downloading v{}", version_str));

    // Download with hash verification using channel for progress
    // Use channel for progress updates from download thread
    let (progress_tx, progress_rx) = std::sync::mpsc::channel::<f32>();
    let version_clone = version_info.clone();
    let cache_clone = cache_dir.clone();
    let do_verify = !skip_verify && version_info.sha256_hash.is_some();
    
    // Spawn download thread
    let download_handle = std::thread::spawn(move || {
        use cursor_studio::versions::download_version_sync;
        
        let result = download_version_sync(&version_clone, &cache_clone, move |progress| {
            let _ = progress_tx.send(progress);
        });
        
        // If download succeeded and we should verify, do verification
        match result {
            Ok(path) if do_verify => {
                if let Some(ref hash) = version_clone.sha256_hash {
                    match cursor_studio::versions::verify_hash(&path, hash) {
                        Ok(true) => Ok((path, Some(true))),
                        Ok(false) => {
                            let _ = std::fs::remove_file(&path);
                            Err(anyhow::anyhow!("Hash verification failed"))
                        }
                        Err(e) => {
                            log::warn!("Hash verification error: {}", e);
                            Ok((path, None)) // Continue despite verification error
                        }
                    }
                } else {
                    Ok((path, None))
                }
            }
            Ok(path) => Ok((path, None)),
            Err(e) => Err(e),
        }
    });

    // Update progress bar from main thread
    loop {
        match progress_rx.recv_timeout(std::time::Duration::from_millis(50)) {
            Ok(progress) => {
                pb.set_position(progress as u64);
            }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                if download_handle.is_finished() {
                    break;
                }
            }
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                break;
            }
        }
    }

    // Get the final result
    match download_handle.join() {
        Ok(Ok((path, hash_status))) => {
            pb.finish_and_clear();
            println!(
                "{} Downloaded v{} to {}",
                CHECK,
                style(&version_str).green(),
                style(path.display()).dim()
            );
            match hash_status {
                Some(true) => {
                    println!("  {} Hash verified", style("✓").green());
                }
                Some(false) => {
                    // Won't happen - we return error on mismatch
                }
                None if skip_verify => {
                    println!(
                        "  {} Hash verification skipped",
                        style("⚠").yellow()
                    );
                }
                None => {
                    // No hash available or verification error
                }
            }
        }
        Ok(Err(e)) => {
            pb.finish_and_clear();
            let err_str = e.to_string();
            println!("{} Download failed: {}", CROSS, style(&err_str).red());
            anyhow::bail!("{}", err_str);
        }
        Err(_) => {
            pb.finish_and_clear();
            println!("{} Download thread panicked", CROSS);
            anyhow::bail!("Download thread panicked");
        }
    }

    Ok(())
}

/// Install a version
fn cmd_install(version: &str, no_default: bool, approval: &mut ApprovalManager) -> Result<()> {
    // First download
    cmd_download(version, false, false, approval)?;

    // Then install
    let resolved = if version == "latest" {
        let versions = get_available_versions();
        versions.first().map(|v| v.version.clone())
    } else {
        Some(version.to_string())
    };

    let version_str = resolved.context("No versions available")?;
    let cache_dir = get_cache_dir();
    let cached_path = cache_dir.join(format!("Cursor-{}-x86_64.AppImage", version_str));

    if !cached_path.exists() {
        anyhow::bail!("Downloaded file not found at {}", cached_path.display());
    }

    // Request approval for install
    let operation = ApprovalOperation::Install {
        version: version_str.clone(),
        path: cached_path.display().to_string(),
    };

    if approval.request(operation) != ApprovalResult::Approved {
        println!("{} Installation cancelled", CROSS);
        return Ok(());
    }

    println!("{} Installing v{}...", ARROW, style(&version_str).cyan());

    match install_version(&cached_path, &version_str) {
        Ok(install_path) => {
            println!(
                "{} Installed to {}",
                CHECK,
                style(install_path.display()).dim()
            );

            if !no_default {
                println!(
                    "{} Set as default version",
                    CHECK
                );
            }
        }
        Err(e) => {
            let err_str = e.to_string();
            println!("{} Installation failed: {}", CROSS, style(&err_str).red());
            anyhow::bail!("{}", err_str);
        }
    }

    Ok(())
}

/// Show version info
fn cmd_info(version: &str) -> Result<()> {
    let resolved = if version == "latest" {
        let versions = get_available_versions();
        versions.first().map(|v| v.version.clone())
    } else {
        Some(version.to_string())
    };

    let version_str = resolved.context("No versions available")?;
    let version_info = get_version_info(&version_str)
        .context(format!("Version {} not found", version_str))?;

    println!();
    println!(
        "{} Cursor IDE v{}",
        PACKAGE,
        style(&version_str).cyan().bold()
    );
    println!();

    let installed = is_version_installed(&version_str);
    println!(
        "  Status:       {}",
        if installed {
            style("Installed").green()
        } else {
            style("Not installed").yellow()
        }
    );

    println!(
        "  Stable:       {}",
        if version_info.is_stable {
            style("Yes").green()
        } else {
            style("No (development)").yellow()
        }
    );

    if let Some(ref date) = version_info.release_date {
        println!("  Released:     {}", date);
    }

    if let Some(ref hash) = version_info.sha256_hash {
        println!("  SHA256:       {}", style(hash).dim());
    } else {
        println!(
            "  SHA256:       {}",
            style("Not available").yellow()
        );
    }

    if let Some(ref commit) = version_info.commit_hash {
        println!("  Commit:       {}", style(&commit[..12]).dim());
    }

    println!();
    println!("  Download URL:");
    println!("    {}", style(&version_info.download_url).dim());

    // Check if cached
    let cache_dir = get_cache_dir();
    let cached_path = cache_dir.join(format!("Cursor-{}-x86_64.AppImage", version_str));
    if cached_path.exists() {
        if let Ok(metadata) = std::fs::metadata(&cached_path) {
            let size_mb = metadata.len() as f64 / 1024.0 / 1024.0;
            println!();
            println!(
                "  Cached:       {} ({:.1} MB)",
                style(cached_path.display()).dim(),
                size_mb
            );
        }
    }

    println!();
    Ok(())
}

/// Clean cache and old versions
fn cmd_clean(
    _older_than: Option<u32>,
    dry_run: bool,
    cache_only: bool,
    approval: &mut ApprovalManager,
) -> Result<()> {
    let cache_dir = get_cache_dir();

    if !cache_dir.exists() {
        println!("{} Cache directory is empty", INFO);
        return Ok(());
    }

    // Find files in cache
    let mut total_size: u64 = 0;
    let mut files_to_remove: Vec<PathBuf> = Vec::new();

    for entry in std::fs::read_dir(&cache_dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_file() {
            if let Ok(metadata) = std::fs::metadata(&path) {
                total_size += metadata.len();
                files_to_remove.push(path);
            }
        }
    }

    if files_to_remove.is_empty() {
        println!("{} Nothing to clean", INFO);
        return Ok(());
    }

    let size_mb = total_size as f64 / 1024.0 / 1024.0;
    println!(
        "\n{} Found {} file(s) totaling {:.1} MB:",
        INFO,
        files_to_remove.len(),
        size_mb
    );

    for path in &files_to_remove {
        println!(
            "  {} {}",
            ARROW,
            style(path.file_name().unwrap_or_default().to_string_lossy()).dim()
        );
    }

    if dry_run {
        println!();
        println!("{} Dry run - no changes made", INFO);
        return Ok(());
    }

    // Request approval
    let operation = ApprovalOperation::Custom {
        title: format!("Clean {} files ({:.1} MB)", files_to_remove.len(), size_mb),
        description: "Remove cached downloads".to_string(),
    };

    if approval.request(operation) != ApprovalResult::Approved {
        println!("{} Cleanup cancelled", CROSS);
        return Ok(());
    }

    // Remove files
    let mut removed_size: u64 = 0;
    for path in &files_to_remove {
        if let Ok(metadata) = std::fs::metadata(&path) {
            removed_size += metadata.len();
        }
        if let Err(e) = std::fs::remove_file(&path) {
            println!(
                "{} Failed to remove {}: {}",
                CROSS,
                path.display(),
                e
            );
        }
    }

    let removed_mb = removed_size as f64 / 1024.0 / 1024.0;
    println!(
        "\n{} Cleaned {:.1} MB",
        CHECK,
        removed_mb
    );

    if !cache_only {
        println!(
            "  {} Version cleanup not yet implemented",
            style("Note:").yellow()
        );
    }

    Ok(())
}

/// Launch Cursor
fn cmd_launch(version: &str) -> Result<()> {
    let version_to_launch = if version == "current" {
        // Find first installed version
        let versions = get_available_versions();
        versions
            .iter()
            .find(|v| is_version_installed(&v.version))
            .map(|v| v.version.clone())
    } else {
        Some(version.to_string())
    };

    match version_to_launch {
        Some(v) => {
            println!("{} Launching Cursor v{}...", ARROW, style(&v).cyan());

            // Try to find and launch
            if let Some(home) = dirs::home_dir() {
                // Check for installed AppImage
                let install_path = home
                    .join(format!(".cursor-studio/versions/cursor-{}", v))
                    .join(format!("Cursor-{}.AppImage", v));

                if install_path.exists() {
                    match std::process::Command::new(&install_path).spawn() {
                        Ok(_) => {
                            println!("{} Launched successfully", CHECK);
                        }
                        Err(e) => {
                            println!("{} Failed to launch: {}", CROSS, e);
                        }
                    }
                } else {
                    // Try system cursor command
                    match std::process::Command::new("cursor").spawn() {
                        Ok(_) => {
                            println!("{} Launched system Cursor", CHECK);
                        }
                        Err(e) => {
                            println!("{} Failed to launch: {}", CROSS, e);
                            println!(
                                "  Try installing first: {} cursor-cli install {}",
                                style("$").dim(),
                                v
                            );
                        }
                    }
                }
            }
        }
        None => {
            println!("{} No version installed", CROSS);
            println!(
                "  Install one with: {} cursor-cli install latest",
                style("$").dim()
            );
        }
    }

    Ok(())
}

/// Show cache info
fn cmd_cache() -> Result<()> {
    let cache_dir = get_cache_dir();

    println!();
    println!("{}", style("Cache Information").bold().underlined());
    println!();

    println!("  Location: {}", style(cache_dir.display()).dim());

    if cache_dir.exists() {
        let mut total_size: u64 = 0;
        let mut file_count = 0;

        for entry in std::fs::read_dir(&cache_dir)? {
            let entry = entry?;
            if entry.path().is_file() {
                if let Ok(metadata) = std::fs::metadata(entry.path()) {
                    total_size += metadata.len();
                    file_count += 1;
                }
            }
        }

        let size_mb = total_size as f64 / 1024.0 / 1024.0;
        println!("  Files:    {}", file_count);
        println!("  Size:     {:.1} MB", size_mb);
    } else {
        println!("  Status:   {}", style("Empty").dim());
    }

    // Check install directory
    if let Some(home) = dirs::home_dir() {
        let install_dir = home.join(".cursor-studio/versions");
        println!();
        println!("  Install dir: {}", style(install_dir.display()).dim());

        if install_dir.exists() {
            let mut version_count = 0;
            for entry in std::fs::read_dir(&install_dir)? {
                let entry = entry?;
                if entry.path().is_dir() {
                    version_count += 1;
                }
            }
            println!("  Versions:    {}", version_count);
        } else {
            println!("  Status:      {}", style("No versions installed").dim());
        }
    }

    println!();
    Ok(())
}

/// Compute or verify hash for a file or version
fn cmd_hash(target: &str, verify: bool) -> Result<()> {
    use sha2::{Digest, Sha256};
    
    // Determine if target is a version or a file path
    let file_path = if target.contains('/') || (target.contains('.') && target.ends_with(".AppImage")) {
        // It's a file path
        PathBuf::from(target)
    } else {
        // It's a version - check cache
        let cache_dir = get_cache_dir();
        let cached = cache_dir.join(format!("Cursor-{}-x86_64.AppImage", target));
        if cached.exists() {
            cached
        } else {
            println!("{} File not found in cache for version {}", CROSS, target);
            println!("  Download first with: {} cursor-cli download {}", style("$").dim(), target);
            anyhow::bail!("File not found");
        }
    };

    if !file_path.exists() {
        println!("{} File not found: {}", CROSS, file_path.display());
        anyhow::bail!("File not found");
    }

    println!();
    println!("{} Computing hash for: {}", INFO, style(file_path.display()).dim());
    
    // Read file and compute hash
    let pb = ProgressBar::new_spinner();
    pb.set_message("Reading file...");
    pb.enable_steady_tick(std::time::Duration::from_millis(100));
    
    let file_content = std::fs::read(&file_path)?;
    let file_size = file_content.len() as f64 / 1024.0 / 1024.0;
    
    pb.set_message("Computing SHA256...");
    let mut hasher = Sha256::new();
    hasher.update(&file_content);
    let hash = hasher.finalize();
    
    // Convert to base64 (SRI format)
    let hash_base64 = base64::Engine::encode(
        &base64::engine::general_purpose::STANDARD,
        hash,
    );
    let sri_hash = format!("sha256-{}", hash_base64);
    
    pb.finish_and_clear();

    println!();
    println!("  File size: {:.1} MB", file_size);
    println!("  SHA256:    {}", style(&sri_hash).cyan().bold());
    println!();

    if verify {
        // Try to find expected hash
        if let Some(version_info) = get_version_info(target) {
            if let Some(ref expected) = version_info.sha256_hash {
                if &sri_hash == expected {
                    println!("  {} Hash matches expected value!", style("✓").green().bold());
                } else {
                    println!("  {} Hash MISMATCH!", style("✗").red().bold());
                    println!("  Expected: {}", style(expected).dim());
                    println!("  Got:      {}", style(&sri_hash).red());
                }
            } else {
                println!("  {} No expected hash defined for version {}", style("⚠").yellow(), target);
            }
        } else {
            println!("  {} Version {} not found in registry", style("⚠").yellow(), target);
        }
    } else {
        // Show as copyable code
        println!("  Copy for versions.rs:");
        println!("    {}", style(format!("sha256_hash: Some(\"{}\".into()),", sri_hash)).green());
    }

    println!();
    Ok(())
}

/// Verify all version hashes are still valid
fn cmd_verify_hashes(only_with_hash: bool, dry_run: bool) -> Result<()> {
    use sha2::{Digest, Sha256};
    
    let versions = get_available_versions();
    let to_check: Vec<_> = if only_with_hash {
        versions.iter().filter(|v| v.sha256_hash.is_some()).collect()
    } else {
        versions.iter().collect()
    };

    println!();
    println!("{}", style("Hash Verification Report").bold().underlined());
    println!();
    println!("  Checking {} versions{}...", 
        to_check.len(),
        if only_with_hash { " (with hashes)" } else { "" }
    );
    println!();

    if dry_run {
        for v in &to_check {
            let hash_status = if v.sha256_hash.is_some() { 
                style("has hash").green() 
            } else { 
                style("no hash").yellow() 
            };
            println!("  {} v{} - {}", ARROW, v.version, hash_status);
        }
        println!();
        println!("  {} Dry run - no downloads performed", INFO);
        return Ok(());
    }

    let cache_dir = get_cache_dir();
    std::fs::create_dir_all(&cache_dir)?;

    let mut passed = 0;
    let mut failed = 0;
    let mut no_hash = 0;
    let mut download_failed = 0;
    let mut results: Vec<(String, String, Option<String>)> = Vec::new();

    for v in &to_check {
        print!("  {} v{}: ", ARROW, v.version);
        std::io::Write::flush(&mut std::io::stdout())?;

        // Check if already cached
        let cached_path = cache_dir.join(format!("Cursor-{}-x86_64.AppImage", v.version));
        
        let file_path = if cached_path.exists() {
            print!("cached, ");
            std::io::Write::flush(&mut std::io::stdout())?;
            cached_path
        } else {
            // Download
            print!("downloading... ");
            std::io::Write::flush(&mut std::io::stdout())?;
            
            match cursor_studio::versions::download_version_sync(v, &cache_dir, |_| {}) {
                Ok(path) => path,
                Err(e) => {
                    println!("{} ({})", style("download failed").red(), e);
                    download_failed += 1;
                    continue;
                }
            }
        };

        // Compute hash
        let file_content = std::fs::read(&file_path)?;
        let mut hasher = Sha256::new();
        hasher.update(&file_content);
        let hash = hasher.finalize();
        let hash_base64 = base64::Engine::encode(
            &base64::engine::general_purpose::STANDARD,
            hash,
        );
        let computed_hash = format!("sha256-{}", hash_base64);

        // Compare
        if let Some(ref expected) = v.sha256_hash {
            if &computed_hash == expected {
                println!("{}", style("✓ verified").green());
                passed += 1;
                results.push((v.version.clone(), "verified".into(), None));
            } else {
                println!("{}", style("✗ MISMATCH").red().bold());
                println!("      Expected: {}", style(expected).dim());
                println!("      Got:      {}", style(&computed_hash).yellow());
                failed += 1;
                results.push((v.version.clone(), "mismatch".into(), Some(computed_hash.clone())));
            }
        } else {
            println!("{} ({})", style("no hash defined").yellow(), &computed_hash[..20]);
            no_hash += 1;
            results.push((v.version.clone(), "no hash".into(), Some(computed_hash.clone())));
        }
    }

    println!();
    println!("{}", style("Summary").bold().underlined());
    println!();
    println!("  {} Passed:          {}", style("✓").green(), passed);
    if failed > 0 {
        println!("  {} Failed:          {}", style("✗").red(), failed);
    }
    if no_hash > 0 {
        println!("  {} No hash defined: {}", style("?").yellow(), no_hash);
    }
    if download_failed > 0 {
        println!("  {} Download failed: {}", style("⬇").red(), download_failed);
    }

    // If there were mismatches or missing hashes, show update suggestions
    let needs_update: Vec<_> = results.iter()
        .filter(|(_, status, hash)| status == "mismatch" || (status == "no hash" && hash.is_some()))
        .collect();

    if !needs_update.is_empty() {
        println!();
        println!("{}", style("Suggested hash updates for versions.rs:").bold());
        println!();
        for (version, status, hash) in needs_update {
            if let Some(h) = hash {
                println!("  // v{} - {}", version, status);
                println!("  {}", style(format!("sha256_hash: Some(\"{}\".into()),", h)).cyan());
                println!();
            }
        }
    }

    println!();
    Ok(())
}

/// Import a manually downloaded file
fn cmd_import(
    file: &PathBuf,
    version: &str,
    platform_str: Option<&str>,
    update_registry: bool,
) -> Result<()> {
    println!();
    println!("{}", style("Manual Import").bold().underlined());
    println!();

    // Detect platform from filename if not specified
    let platform = if let Some(p) = platform_str {
        match p.to_lowercase().as_str() {
            "linux-x64" | "linux_x64" | "linux64" => Platform::LinuxX64,
            "linux-arm64" | "linux_arm64" | "linuxarm" => Platform::LinuxArm64,
            "darwin-x64" | "macos-intel" | "mac-intel" => Platform::DarwinX64,
            "darwin-arm64" | "macos-arm64" | "mac-arm" => Platform::DarwinArm64,
            "darwin-universal" | "macos-universal" | "mac-universal" => Platform::DarwinUniversal,
            _ => {
                println!("{} Unknown platform: {}", CROSS, p);
                println!("  Valid options: linux-x64, linux-arm64, darwin-x64, darwin-arm64, darwin-universal");
                anyhow::bail!("Unknown platform");
            }
        }
    } else {
        // Try to detect from filename
        let filename = file.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("");
        
        if filename.contains("x86_64") || filename.contains("x64") {
            if filename.ends_with(".AppImage") {
                Platform::LinuxX64
            } else {
                Platform::DarwinX64
            }
        } else if filename.contains("aarch64") || filename.contains("arm64") {
            if filename.ends_with(".AppImage") {
                Platform::LinuxArm64
            } else {
                Platform::DarwinArm64
            }
        } else if filename.contains("universal") {
            Platform::DarwinUniversal
        } else {
            // Default to current platform
            Platform::current()
        }
    };

    println!("  File:     {}", style(file.display()).dim());
    println!("  Version:  {}", style(version).cyan());
    println!("  Platform: {}", style(platform.display_name()).green());
    println!();

    // Perform import
    let (dest_path, hash) = ManualImport::import(file, version, platform)?;

    println!("  {} Imported successfully!", CHECK);
    println!("  Destination: {}", style(dest_path.display()).dim());
    println!("  SHA256:      {}", style(&hash).cyan());

    // Update registry if requested
    if update_registry {
        println!();
        let mut registry = VersionRegistry::load();
        if registry.update_hash(version, platform, hash.clone()) {
            match registry.save() {
                Ok(path) => {
                    println!("  {} Registry updated: {}", CHECK, style(path.display()).dim());
                }
                Err(e) => {
                    println!("  {} Failed to save registry: {}", CROSS, e);
                }
            }
        } else {
            println!("  {} Version {} not found in registry", style("⚠").yellow(), version);
            println!("  Hash for manual use: {}", style(&hash).cyan());
        }
    }

    println!();
    Ok(())
}

/// Show download URLs for manual download
fn cmd_urls(version: &str, show_all: bool) -> Result<()> {
    let registry = VersionRegistry::load();
    
    // Resolve version
    let version_str = if version == "latest" {
        registry.latest_stable()
            .map(|v| v.version.as_str())
            .unwrap_or("2.1.34")
    } else {
        version
    };

    let cursor_version = registry.get_version(version_str)
        .context(format!("Version {} not found in registry", version_str))?;

    println!();
    println!("{} Download URLs for Cursor v{}", INFO, style(&cursor_version.version).cyan().bold());
    if let Some(ref notes) = cursor_version.notes {
        println!("  {}", style(notes).dim());
    }
    println!();

    let current_platform = Platform::current();

    if show_all {
        println!("{}", style("All Platforms:").bold());
        println!();
        for platform in Platform::all() {
            let url = cursor_version.download_url(*platform);
            let has_hash = cursor_version.has_hash(*platform);
            let hash_indicator = if has_hash { 
                style("✓").green().to_string() 
            } else { 
                style("?").yellow().to_string() 
            };
            
            let is_current = *platform == current_platform;
            let marker = if is_current { " ← current" } else { "" };
            
            println!("  {} {} {}{}", hash_indicator, style(platform.display_name()).bold(), style(marker).dim(), "");
            println!("    {}", style(&url).cyan());
            println!();
        }
    } else {
        println!("{} (use {} to see all platforms)", 
            style(current_platform.display_name()).bold(),
            style("--all").dim()
        );
        println!();
        let url = cursor_version.download_url(current_platform);
        println!("  {}", style(&url).cyan().bold());
        
        if let Some(hash) = cursor_version.hash_for_platform(current_platform) {
            println!();
            println!("  Expected hash: {}", style(hash).dim());
        } else {
            println!();
            println!("  {} No hash available - run {} after download", 
                style("⚠").yellow(),
                style(format!("cursor-cli import --version {} <file>", version_str)).dim()
            );
        }
    }

    println!();
    println!("{}", style("After downloading, import with:").dim());
    println!("  cursor-cli import --version {} <downloaded_file>", version_str);
    println!();

    Ok(())
}

/// Export registry to JSON
fn cmd_export_registry(output: Option<&PathBuf>) -> Result<()> {
    let registry = VersionRegistry::load();
    let json = serde_json::to_string_pretty(&registry)?;

    if let Some(path) = output {
        std::fs::write(path, &json)?;
        println!("{} Registry exported to {}", CHECK, style(path.display()).cyan());
    } else {
        println!("{}", json);
    }

    Ok(())
}

/// Import registry from JSON
fn cmd_import_registry(file: &PathBuf, merge: bool) -> Result<()> {
    println!();
    
    let content = std::fs::read_to_string(file)?;
    let imported: VersionRegistry = serde_json::from_str(&content)?;

    if merge {
        let mut current = VersionRegistry::load();
        let mut updated = 0;
        
        for imported_version in &imported.versions {
            for (platform, hash) in &imported_version.hashes {
                if current.update_hash(&imported_version.version, *platform, hash.clone()) {
                    updated += 1;
                }
            }
        }
        
        let path = current.save()?;
        println!("{} Merged {} hash(es) into registry", CHECK, updated);
        println!("  Saved to: {}", style(path.display()).dim());
    } else {
        let path = imported.save()?;
        println!("{} Registry replaced with {} versions", CHECK, imported.versions.len());
        println!("  Saved to: {}", style(path.display()).dim());
    }

    println!();
    Ok(())
}
