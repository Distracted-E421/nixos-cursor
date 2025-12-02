//! Cursor Version Registry
//!
//! Comprehensive version management supporting:
//! - All platforms (Linux x64/arm64, macOS x64/arm64/universal)
//! - External hash registry (can be updated without recompiling)
//! - Manual import fallback
//! - 48+ versions from 1.6.45 to 2.1.34

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::path::PathBuf;

/// Supported platforms
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Platform {
    LinuxX64,
    LinuxArm64,
    DarwinX64,
    DarwinArm64,
    DarwinUniversal,
}

impl Platform {
    /// Get the current platform
    pub fn current() -> Self {
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        return Platform::LinuxX64;
        
        #[cfg(all(target_os = "linux", target_arch = "aarch64"))]
        return Platform::LinuxArm64;
        
        #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
        return Platform::DarwinX64;
        
        #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
        return Platform::DarwinArm64;
        
        // Fallback for other platforms during development
        #[cfg(not(any(
            all(target_os = "linux", target_arch = "x86_64"),
            all(target_os = "linux", target_arch = "aarch64"),
            all(target_os = "macos", target_arch = "x86_64"),
            all(target_os = "macos", target_arch = "aarch64"),
        )))]
        Platform::LinuxX64
    }
    
    /// Get file extension for this platform
    pub fn extension(&self) -> &'static str {
        match self {
            Platform::LinuxX64 | Platform::LinuxArm64 => "AppImage",
            Platform::DarwinX64 | Platform::DarwinArm64 | Platform::DarwinUniversal => "dmg",
        }
    }
    
    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            Platform::LinuxX64 => "Linux x64",
            Platform::LinuxArm64 => "Linux ARM64",
            Platform::DarwinX64 => "macOS Intel",
            Platform::DarwinArm64 => "macOS Apple Silicon",
            Platform::DarwinUniversal => "macOS Universal",
        }
    }
    
    /// Get URL path component
    pub fn url_path(&self) -> &'static str {
        match self {
            Platform::LinuxX64 => "linux/x64",
            Platform::LinuxArm64 => "linux/arm64",
            Platform::DarwinX64 => "darwin/x64",
            Platform::DarwinArm64 => "darwin/arm64",
            Platform::DarwinUniversal => "darwin/universal",
        }
    }
    
    /// Get filename for a version
    pub fn filename(&self, version: &str) -> String {
        match self {
            Platform::LinuxX64 => format!("Cursor-{}-x86_64.AppImage", version),
            Platform::LinuxArm64 => format!("Cursor-{}-aarch64.AppImage", version),
            Platform::DarwinX64 => "Cursor-darwin-x64.dmg".to_string(),
            Platform::DarwinArm64 => "Cursor-darwin-arm64.dmg".to_string(),
            Platform::DarwinUniversal => "Cursor-darwin-universal.dmg".to_string(),
        }
    }
    
    /// All platforms
    pub fn all() -> &'static [Platform] {
        &[
            Platform::LinuxX64,
            Platform::LinuxArm64,
            Platform::DarwinX64,
            Platform::DarwinArm64,
            Platform::DarwinUniversal,
        ]
    }
}

/// A Cursor version with all platform variants
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CursorVersion {
    pub version: String,
    pub commit_hash: String,
    pub release_date: Option<String>,
    pub is_stable: bool,
    /// Notes about this version (e.g., "Last version with custom modes")
    pub notes: Option<String>,
    /// Hashes per platform (can be updated externally)
    #[serde(default)]
    pub hashes: HashMap<Platform, String>,
}

impl CursorVersion {
    /// Generate download URL for a platform
    pub fn download_url(&self, platform: Platform) -> String {
        format!(
            "https://downloads.cursor.com/production/{}/{}/{}",
            self.commit_hash,
            platform.url_path(),
            platform.filename(&self.version)
        )
    }
    
    /// Get hash for current platform
    pub fn hash_for_platform(&self, platform: Platform) -> Option<&String> {
        self.hashes.get(&platform)
    }
    
    /// Check if hash is available for current platform
    pub fn has_hash(&self, platform: Platform) -> bool {
        self.hashes.contains_key(&platform)
    }
}

/// The version registry - can be loaded from file or use embedded defaults
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionRegistry {
    /// Schema version for future compatibility
    pub schema_version: u32,
    /// Last updated timestamp
    pub updated: String,
    /// All versions
    pub versions: Vec<CursorVersion>,
}

impl Default for VersionRegistry {
    fn default() -> Self {
        Self::embedded()
    }
}

impl VersionRegistry {
    /// Create registry with all known versions (embedded in binary)
    pub fn embedded() -> Self {
        Self {
            schema_version: 1,
            updated: "2025-12-01".to_string(),
            versions: get_all_versions(),
        }
    }
    
    /// Load from external JSON file, falling back to embedded
    pub fn load() -> Self {
        if let Some(path) = Self::registry_path() {
            if path.exists() {
                if let Ok(content) = std::fs::read_to_string(&path) {
                    if let Ok(registry) = serde_json::from_str::<VersionRegistry>(&content) {
                        log::info!("Loaded version registry from {}", path.display());
                        return registry;
                    }
                }
            }
        }
        Self::embedded()
    }
    
    /// Save to external file
    pub fn save(&self) -> Result<PathBuf> {
        let path = Self::registry_path().context("No config directory available")?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let content = serde_json::to_string_pretty(self)?;
        std::fs::write(&path, content)?;
        Ok(path)
    }
    
    /// Path to external registry file
    pub fn registry_path() -> Option<PathBuf> {
        dirs::config_dir().map(|d| d.join("cursor-studio").join("version-registry.json"))
    }
    
    /// Get version by string
    pub fn get_version(&self, version: &str) -> Option<&CursorVersion> {
        self.versions.iter().find(|v| v.version == version)
    }
    
    /// Get latest stable version
    pub fn latest_stable(&self) -> Option<&CursorVersion> {
        self.versions.iter().find(|v| v.is_stable)
    }
    
    /// Update hash for a version/platform
    pub fn update_hash(&mut self, version: &str, platform: Platform, hash: String) -> bool {
        if let Some(v) = self.versions.iter_mut().find(|v| v.version == version) {
            v.hashes.insert(platform, hash);
            true
        } else {
            false
        }
    }
    
    /// Get all versions
    pub fn all_versions(&self) -> &[CursorVersion] {
        &self.versions
    }
    
    /// Get versions for a specific era
    pub fn versions_in_range(&self, major: u32, minor_start: u32, minor_end: u32) -> Vec<&CursorVersion> {
        self.versions.iter()
            .filter(|v| {
                let parts: Vec<&str> = v.version.split('.').collect();
                if parts.len() >= 2 {
                    if let (Ok(maj), Ok(min)) = (parts[0].parse::<u32>(), parts[1].parse::<u32>()) {
                        return maj == major && min >= minor_start && min <= minor_end;
                    }
                }
                false
            })
            .collect()
    }
}

/// Compute SHA256 hash of a file in SRI format
pub fn compute_hash(path: &PathBuf) -> Result<String> {
    let content = std::fs::read(path)?;
    let mut hasher = Sha256::new();
    hasher.update(&content);
    let hash = hasher.finalize();
    let base64 = base64::Engine::encode(
        &base64::engine::general_purpose::STANDARD,
        hash,
    );
    Ok(format!("sha256-{}", base64))
}

/// Verify a file against expected hash
pub fn verify_file_hash(path: &PathBuf, expected: &str) -> Result<bool> {
    let computed = compute_hash(path)?;
    Ok(computed == expected)
}

/// All known versions - comprehensive list from URL files
fn get_all_versions() -> Vec<CursorVersion> {
    vec![
        // ============================================
        // 2.1.x Era - Latest versions
        // ============================================
        CursorVersion {
            version: "2.1.34".into(),
            commit_hash: "609c37304ae83141fd217c4ae638bf532185650f".into(),
            release_date: Some("2024-11".into()),
            is_stable: true,
            notes: Some("Latest stable".into()),
            hashes: HashMap::from([
                (Platform::LinuxX64, "sha256-NPs0P+cnPo3KMdezhAkPR4TwpcvIrSuoX+40NsKyfzA=".into()),
            ]),
        },
        CursorVersion {
            version: "2.1.32".into(),
            commit_hash: "ef979b1b43d85eee2a274c25fd62d5502006e425".into(),
            release_date: Some("2024-11".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::from([
                (Platform::LinuxX64, "sha256-CKLUa5qaT8njAyPMRz6+iX9KSYyvNoyLZFZi6wmR4g0=".into()),
            ]),
        },
        CursorVersion {
            version: "2.1.26".into(),
            commit_hash: "f628a4761be40b8869ca61a6189cafd14756dff4".into(),
            release_date: Some("2024-11".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::from([
                (Platform::LinuxX64, "sha256-lkvrgWjVfTozcADOjA/liZ0j5pPgXv9YvR5l0adGxBE=".into()),
            ]),
        },
        CursorVersion {
            version: "2.1.25".into(),
            commit_hash: "7584ea888f7eb7bf76c9873a8f71b28f034a982e".into(),
            release_date: Some("2024-11".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::from([
                (Platform::LinuxX64, "sha256-TybCKg+7GAMfiFNw3bbHJ9uSUwhKUjbjfUOb9JlFlMM=".into()),
            ]),
        },
        CursorVersion {
            version: "2.1.24".into(),
            commit_hash: "ac32b095dae9b8e0cfede6c5ebc55e589ee50e1b".into(),
            release_date: Some("2024-11".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::from([
                (Platform::LinuxX64, "sha256-dlpdOCoUU61dDgmRrCcmBZ4WSGjtrP5G7vQfLRkUI9o=".into()),
            ]),
        },
        CursorVersion {
            version: "2.1.20".into(),
            commit_hash: "a8d8905b06c8da1739af6f789efd59c28ac2a680".into(),
            release_date: Some("2024-10".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::from([
                (Platform::LinuxX64, "sha256-V/5KDAJlXPLMQelnUgnfv2v3skxkb1V/n3Qn0qtwHaA=".into()),
            ]),
        },
        CursorVersion {
            version: "2.1.19".into(),
            commit_hash: "39a966b4048ef6b8024b27d4812a50d88de29cc3".into(),
            release_date: Some("2024-10".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.1.17".into(),
            commit_hash: "6757269838ae9ac4caaa2be13f396fdfbcf1f9a6".into(),
            release_date: Some("2024-10".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.1.15".into(),
            commit_hash: "a022145cbf8aea0babc3b039a98551c1518de024".into(),
            release_date: Some("2024-10".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.1.7".into(),
            commit_hash: "3d2e45538bcc4fd7ed28cc113c2110b26a824a00".into(),
            release_date: Some("2024-10".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.1.6".into(),
            commit_hash: "92340560ea81cb6168e2027596519d68af6c90a1".into(),
            release_date: Some("2024-10".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        
        // ============================================
        // 2.0.x Era - Custom Modes Era (pre-removal)
        // ============================================
        CursorVersion {
            version: "2.0.77".into(),
            commit_hash: "ba90f2f88e4911312761abab9492c42442117cfe".into(),
            release_date: Some("2024-10".into()),
            is_stable: true,
            notes: Some("Last 2.0.x - recommended for custom modes".into()),
            hashes: HashMap::from([
                (Platform::LinuxX64, "sha256-/r7cmjgFhec7fEKUfFKw3vUoB9LJB2P/646cMeRKp/0=".into()),
            ]),
        },
        CursorVersion {
            version: "2.0.75".into(),
            commit_hash: "9e7a27b76730ca7fe4aecaeafc58bac1e2c82121".into(),
            release_date: Some("2024-10".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.74".into(),
            commit_hash: "a965544b869cfb53b46806974091f97565545e48".into(),
            release_date: Some("2024-10".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.73".into(),
            commit_hash: "55b873ebecb5923d3b947d7e67e841d3ac781886".into(),
            release_date: Some("2024-10".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.69".into(),
            commit_hash: "63fcac100bd5d5749f2a98aa47d65f6eca61db39".into(),
            release_date: Some("2024-09".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.64".into(),
            commit_hash: "25412918da7e74b2686b25d62da1f01cfcd27683".into(),
            release_date: Some("2024-09".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.63".into(),
            commit_hash: "505046dcfad2acda3d066e32b7cd8b6e2dc1fdcd".into(),
            release_date: Some("2024-09".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.60".into(),
            commit_hash: "c6d93c13f57509f77eb65783b28e75a857b74c03".into(),
            release_date: Some("2024-09".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.57".into(),
            commit_hash: "eb037ef2bfba33ac568b0da614cb1c7b738455d6".into(),
            release_date: Some("2024-09".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.54".into(),
            commit_hash: "7a31bffd467aa2d9adfda69076eb924e9062cb27".into(),
            release_date: Some("2024-08".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.52".into(),
            commit_hash: "2125c48207a2a9aa55bce3d0af552912c84175d9".into(),
            release_date: Some("2024-08".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.43".into(),
            commit_hash: "8e4da76ad196925accaa169efcae28c45454cce3".into(),
            release_date: Some("2024-08".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.40".into(),
            commit_hash: "a9b73428ca6aeb2d24623da2841a271543735562".into(),
            release_date: Some("2024-08".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.38".into(),
            commit_hash: "3fa438a81d579067162dd8767025b788454e6f93".into(),
            release_date: Some("2024-07".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.34".into(),
            commit_hash: "45fd70f3fe72037444ba35c9e51ce86a1977ac11".into(),
            release_date: Some("2024-07".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.32".into(),
            commit_hash: "9a5dd36e54f13fb9c0e74490ec44d080dbc5df53".into(),
            release_date: Some("2024-07".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "2.0.11".into(),
            commit_hash: "4aa02949dc5065af49f2f6f72e3278386a3f7116".into(),
            release_date: Some("2024-06".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        
        // ============================================
        // 1.7.x Era - Classic Era
        // ============================================
        CursorVersion {
            version: "1.7.54".into(),
            commit_hash: "5c17eb2968a37f66bc6662f48d6356a100b67be8".into(),
            release_date: Some("2024-09".into()),
            is_stable: true,
            notes: Some("Latest pre-2.0".into()),
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.53".into(),
            commit_hash: "ab6b80c19b51fe71d58e69d8ed3802be587b3418".into(),
            release_date: Some("2024-09".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.52".into(),
            commit_hash: "9675251a06b1314d50ff34b0cbe5109b78f848cd".into(),
            release_date: Some("2024-09".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.46".into(),
            commit_hash: "b9e5948c1ad20443a5cecba6b84a3c9b99d62582".into(),
            release_date: Some("2024-08".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.44".into(),
            commit_hash: "9d178a4a5589981b62546448bb32920a8219a5de".into(),
            release_date: Some("2024-08".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.43".into(),
            commit_hash: "df279210b53cf4686036054b15400aa2fe06d6dd".into(),
            release_date: Some("2024-08".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.40".into(),
            commit_hash: "df79b2380cd32922cad03529b0dc0c946c311856".into(),
            release_date: Some("2024-08".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.39".into(),
            commit_hash: "a9c77ceae65b77ff772d6adfe05f24d8ebcb2794".into(),
            release_date: Some("2024-08".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.38".into(),
            commit_hash: "fe5d1728063e86edeeda5bebd2c8e14bf4d0f96a".into(),
            release_date: Some("2024-08".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.36".into(),
            commit_hash: "493c403e4a45c5f971d1c76cc74febd0968d57d8".into(),
            release_date: Some("2024-08".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.33".into(),
            commit_hash: "a84f941711ad680a635c8a3456002833186c484f".into(),
            release_date: Some("2024-07".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.28".into(),
            commit_hash: "adb0f9e3e4f184bba7f3fa6dbfd72ad0ebb8cfd8".into(),
            release_date: Some("2024-07".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.25".into(),
            commit_hash: "429604585b94ab2b96a4dabff4660f41d5b7fb8f".into(),
            release_date: Some("2024-07".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.23".into(),
            commit_hash: "5069385c5a69db511722405ab5aeadc01579afd8".into(),
            release_date: Some("2024-07".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.22".into(),
            commit_hash: "31b1fbfcec1bf758f7140645f005fc78b5df355b".into(),
            release_date: Some("2024-06".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.17".into(),
            commit_hash: "34881053400013f38e2354f1479c88c9067039a2".into(),
            release_date: Some("2024-06".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.16".into(),
            commit_hash: "39476a6453a2a2903ed6446529255038f81c929f".into(),
            release_date: Some("2024-06".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.12".into(),
            commit_hash: "b3f1951240d5016648330fab51192dc03e8d705a".into(),
            release_date: Some("2024-06".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        CursorVersion {
            version: "1.7.11".into(),
            commit_hash: "867f14c797c14c23a187097ea179bc97d215a7c4".into(),
            release_date: Some("2024-05".into()),
            is_stable: true,
            notes: None,
            hashes: HashMap::new(),
        },
        
        // ============================================
        // 1.6.x Era - Legacy
        // ============================================
        CursorVersion {
            version: "1.6.45".into(),
            commit_hash: "3ccce8f55d8cca49f6d28b491a844c699b8719a3".into(),
            release_date: Some("2024-05".into()),
            is_stable: true,
            notes: Some("Legacy - pre-dates custom modes".into()),
            hashes: HashMap::new(),
        },
    ]
}

/// Manual import helper - imports a downloaded file and computes its hash
pub struct ManualImport;

impl ManualImport {
    /// Import a manually downloaded file
    /// 
    /// Returns (installed_path, computed_hash)
    pub fn import(
        source_path: &PathBuf,
        version: &str,
        platform: Platform,
    ) -> Result<(PathBuf, String)> {
        // Validate file exists
        if !source_path.exists() {
            anyhow::bail!("Source file does not exist: {}", source_path.display());
        }
        
        // Compute hash
        let hash = compute_hash(source_path)?;
        
        // Create cache directory
        let cache_dir = dirs::cache_dir()
            .unwrap_or_else(|| PathBuf::from("/tmp"))
            .join("cursor-studio")
            .join("downloads");
        std::fs::create_dir_all(&cache_dir)?;
        
        // Copy to cache with correct filename
        let filename = platform.filename(version);
        let dest_path = cache_dir.join(&filename);
        
        std::fs::copy(source_path, &dest_path)?;
        
        // Make executable on Linux
        #[cfg(unix)]
        if matches!(platform, Platform::LinuxX64 | Platform::LinuxArm64) {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&dest_path)?.permissions();
            perms.set_mode(0o755);
            std::fs::set_permissions(&dest_path, perms)?;
        }
        
        Ok((dest_path, hash))
    }
    
    /// Show download URL for manual download
    pub fn get_download_url(version: &CursorVersion, platform: Platform) -> String {
        version.download_url(platform)
    }
    
    /// Show all download URLs for a version
    pub fn get_all_download_urls(version: &CursorVersion) -> Vec<(Platform, String)> {
        Platform::all()
            .iter()
            .map(|&p| (p, version.download_url(p)))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_platform_current() {
        let p = Platform::current();
        assert!(matches!(p, Platform::LinuxX64 | Platform::LinuxArm64 | 
                          Platform::DarwinX64 | Platform::DarwinArm64 | Platform::DarwinUniversal));
    }

    #[test]
    fn test_version_url_generation() {
        let registry = VersionRegistry::embedded();
        let v = registry.get_version("2.1.34").unwrap();
        let url = v.download_url(Platform::LinuxX64);
        assert!(url.contains("609c37304ae83141fd217c4ae638bf532185650f"));
        assert!(url.contains("linux/x64"));
        assert!(url.contains("Cursor-2.1.34-x86_64.AppImage"));
    }

    #[test]
    fn test_registry_has_all_versions() {
        let registry = VersionRegistry::embedded();
        assert!(registry.versions.len() >= 40); // We have ~48 versions
    }

    #[test]
    fn test_latest_stable() {
        let registry = VersionRegistry::embedded();
        let latest = registry.latest_stable().unwrap();
        assert_eq!(latest.version, "2.1.34");
    }
}
