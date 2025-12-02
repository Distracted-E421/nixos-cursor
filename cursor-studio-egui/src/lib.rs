//! Cursor Studio - Open Source Cursor IDE Manager
//!
//! Provides version management, chat library, security scanning, and sync.

pub mod approval;
pub mod chat;
pub mod database;
pub mod security;
pub mod theme;
pub mod version_registry;
pub mod versions;

// Re-export commonly used types
pub use approval::{ApprovalManager, ApprovalMode, ApprovalOperation, ApprovalResult};
pub use versions::{
    download_and_verify, download_and_verify_simple, download_version_sync,
    get_available_versions, get_cache_dir, get_latest_stable, get_version_info, install_version,
    is_version_installed, verify_hash, verify_hash_detailed, AvailableVersion, DownloadEvent,
    DownloadProgress, DownloadState, HashVerificationResult,
};
