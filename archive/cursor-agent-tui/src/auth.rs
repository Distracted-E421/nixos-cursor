//! Authentication management for cursor-agent-tui

use crate::config::Config;
use crate::error::{AgentError, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::Path;
use tracing::{debug, info, warn};

/// Authentication token
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthToken {
    /// The actual token value
    pub value: String,
    /// When the token expires (if known)
    pub expires_at: Option<DateTime<Utc>>,
    /// Token source
    pub source: TokenSource,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TokenSource {
    /// Extracted from Cursor IDE storage
    CursorIde,
    /// From environment variable
    Environment,
    /// From our own token storage
    Stored,
    /// Manually provided
    Manual,
}

/// Manages authentication tokens
pub struct AuthManager {
    config: Config,
    cached_token: Option<AuthToken>,
}

impl AuthManager {
    /// Create a new auth manager
    pub fn new(config: &Config) -> Result<Self> {
        Ok(Self {
            config: config.clone(),
            cached_token: None,
        })
    }

    /// Get a valid authentication token
    pub async fn get_token(&self) -> Result<AuthToken> {
        // Check cache first
        if let Some(ref token) = self.cached_token {
            if !Self::is_expired(token) {
                return Ok(token.clone());
            }
        }

        // Try sources in order
        // 1. Environment variable
        if self.config.auth.allow_env_token {
            if let Ok(token) = std::env::var("CURSOR_TOKEN") {
                debug!("Using token from CURSOR_TOKEN environment variable");
                return Ok(AuthToken {
                    value: token,
                    expires_at: None,
                    source: TokenSource::Environment,
                });
            }
        }

        // 2. Our stored token
        if let Ok(token) = self.load_stored_token() {
            if !Self::is_expired(&token) {
                debug!("Using stored token");
                return Ok(token);
            }
        }

        // 3. Extract from Cursor IDE
        if let Some(ref cursor_path) = self.config.auth.cursor_storage_path {
            if let Ok(token) = Self::extract_from_cursor(cursor_path) {
                info!("Extracted token from Cursor IDE storage");
                return Ok(token);
            }
        }

        Err(AgentError::TokenNotFound)
    }

    /// Check if token is expired
    fn is_expired(token: &AuthToken) -> bool {
        if let Some(expires_at) = token.expires_at {
            expires_at < Utc::now()
        } else {
            false // Unknown expiry = assume valid
        }
    }

    /// Load token from our storage
    fn load_stored_token(&self) -> Result<AuthToken> {
        let path = &self.config.auth.token_path;
        if !path.exists() {
            return Err(AgentError::TokenNotFound);
        }

        let content = std::fs::read_to_string(path)?;
        let token: AuthToken = serde_json::from_str(&content)?;
        Ok(token)
    }

    /// Store token for later use
    pub fn store_token(&self, token: &AuthToken) -> Result<()> {
        let path = &self.config.auth.token_path;
        
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let content = serde_json::to_string_pretty(token)?;
        std::fs::write(path, content)?;

        // Set restrictive permissions on Unix
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(path)?.permissions();
            perms.set_mode(0o600);
            std::fs::set_permissions(path, perms)?;
        }

        Ok(())
    }

    /// Extract token from Cursor IDE storage
    fn extract_from_cursor(cursor_path: &Path) -> Result<AuthToken> {
        // Cursor stores tokens in various places depending on version
        // Try known locations
        
        let possible_paths = [
            // SQLite global storage (most common)
            cursor_path.join("User/globalStorage/state.vscdb"),
            // Newer Cursor versions
            cursor_path.join("User/globalStorage/cursor.auth/token"),
            // Server storage
            cursor_path.join("cursor-server/data/auth.json"),
        ];

        for path in &possible_paths {
            if path.exists() {
                if path.extension().map(|e| e == "vscdb").unwrap_or(false) {
                    // SQLite database
                    if let Ok(token) = Self::extract_from_sqlite(path) {
                        return Ok(token);
                    }
                } else {
                    // JSON file
                    if let Ok(content) = std::fs::read_to_string(path) {
                        if let Ok(token) = Self::parse_token_file(&content) {
                            return Ok(token);
                        }
                    }
                }
            }
        }

        // Try looking for accessToken in the SQLite database
        let state_db = cursor_path.join("User/globalStorage/state.vscdb");
        if state_db.exists() {
            if let Ok(token) = Self::extract_from_sqlite(&state_db) {
                return Ok(token);
            }
        }

        Err(AgentError::TokenNotFound)
    }

    /// Extract token from Cursor's SQLite database
    fn extract_from_sqlite(db_path: &Path) -> Result<AuthToken> {
        // Open database in read-only mode
        let conn = rusqlite::Connection::open_with_flags(
            db_path,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
        ).map_err(|e| AgentError::Auth(format!("Failed to open database: {}", e)))?;

        // The token is stored in ItemTable with key "cursorAuth/accessToken"
        // Try different key patterns in order of likelihood
        let key_patterns = [
            "cursorAuth/accessToken",      // Current Cursor format
            "cursorAuth.accessToken",      // Alternative format
            "cursor.accessToken",          // Older format
            "cursor/accessToken",          // Alternative
        ];

        for pattern in &key_patterns {
            let result: std::result::Result<String, _> = conn.query_row(
                "SELECT value FROM ItemTable WHERE key = ?",
                [pattern],
                |row| row.get(0),
            );

            if let Ok(value) = result {
                // The value might be JSON encoded (wrapped in quotes)
                let token_value = if value.starts_with('"') && value.ends_with('"') {
                    serde_json::from_str::<String>(&value).unwrap_or(value)
                } else {
                    value
                };

                // Validate it looks like a JWT
                if token_value.starts_with("eyJ") {
                    info!("Found auth token with key: {}", pattern);
                    return Ok(AuthToken {
                        value: token_value,
                        expires_at: None,
                        source: TokenSource::CursorIde,
                    });
                }
            }
        }

        // Fallback: try to find any token-like value in ItemTable
        let result: std::result::Result<String, _> = conn.query_row(
            "SELECT value FROM ItemTable WHERE key LIKE '%accessToken%' AND value LIKE 'eyJ%' LIMIT 1",
            [],
            |row| row.get(0),
        );

        if let Ok(value) = result {
            info!("Found auth token via fallback search");
            return Ok(AuthToken {
                value,
                expires_at: None,
                source: TokenSource::CursorIde,
            });
        }

        // Last resort: check cursorDiskKV table
        let result: std::result::Result<String, _> = conn.query_row(
            "SELECT value FROM cursorDiskKV WHERE key LIKE '%accessToken%' AND value LIKE 'eyJ%' LIMIT 1",
            [],
            |row| row.get(0),
        );

        if let Ok(value) = result {
            return Ok(AuthToken {
                value,
                expires_at: None,
                source: TokenSource::CursorIde,
            });
        }

        Err(AgentError::TokenNotFound)
    }

    /// Parse token from JSON file
    fn parse_token_file(content: &str) -> Result<AuthToken> {
        #[derive(Deserialize)]
        struct AuthFile {
            #[serde(alias = "accessToken")]
            access_token: Option<String>,
            token: Option<String>,
        }

        let parsed: AuthFile = serde_json::from_str(content)?;
        let value = parsed.access_token.or(parsed.token)
            .ok_or(AgentError::TokenNotFound)?;

        Ok(AuthToken {
            value,
            expires_at: None,
            source: TokenSource::CursorIde,
        })
    }
}

