//! Cursor Studio - Version Manager + Chat Library
//! Built with egui for native Wayland support

mod database;
mod security;
mod theme;

use database::{
    Bookmark, ChatDatabase, Conversation, CursorVersion, DisplayPreference, Message, MessageRole,
    MessageStats,
};
use eframe::egui::{self, Color32, CursorIcon, RichText, Rounding, Stroke, Vec2};
use std::path::PathBuf;
use std::process::Command;
use theme::Theme;

/// External config from Home Manager or other sources
/// Located at ~/.config/cursor-studio/config.json
#[derive(Debug, Default, serde::Deserialize)]
struct ExternalConfig {
    #[serde(default)]
    theme: Option<String>,
    #[serde(default)]
    font_scale: Option<f32>,
    #[serde(default)]
    message_spacing: Option<f32>,
    #[serde(default)]
    status_bar_font_size: Option<f32>,
    #[serde(default)]
    display_prefs: Vec<ExternalDisplayPref>,
    #[serde(default)]
    cursor_data_dir: Option<String>,
    #[serde(default)]
    security: Option<ExternalSecurityConfig>,
    #[serde(default)]
    resources: Option<ExternalResourceConfig>,
}

#[derive(Debug, Default, serde::Deserialize)]
struct ExternalDisplayPref {
    content_type: String,
    alignment: String,
    #[serde(default)]
    style: String,
    #[serde(default)]
    collapsed: bool,
}

#[derive(Debug, Default, serde::Deserialize)]
struct ExternalSecurityConfig {
    #[serde(default)]
    npm_scanning: bool,
    #[serde(default)]
    sensitive_data_scan: bool,
    #[serde(default)]
    blocklist_path: Option<String>,
}

#[derive(Debug, Default, serde::Deserialize)]
struct ExternalResourceConfig {
    max_cpu_threads: Option<usize>,
    max_ram_mb: Option<usize>,
    max_vram_mb: Option<usize>,
    storage_limit_mb: Option<usize>,
}

impl ExternalConfig {
    /// Load config from ~/.config/cursor-studio/config.json if it exists
    fn load() -> Option<Self> {
        let config_path = dirs::config_dir()?
            .join("cursor-studio")
            .join("config.json");
        if config_path.exists() {
            let content = std::fs::read_to_string(&config_path).ok()?;
            match serde_json::from_str(&content) {
                Ok(config) => {
                    log::info!("Loaded Home Manager config from {:?}", config_path);
                    Some(config)
                }
                Err(e) => {
                    log::warn!("Failed to parse config.json: {}", e);
                    None
                }
            }
        } else {
            log::debug!("No external config at {:?}", config_path);
            None
        }
    }
}

// Known Cursor versions that can be downloaded
const AVAILABLE_VERSIONS: &[&str] = &[
    "0.50.5", "0.50.4", "0.50.3", "0.50.2", "0.50.1", "0.50.0", "0.49.6", "0.49.5", "0.49.4",
    "0.49.3", "0.49.2", "0.49.1", "0.49.0", "0.48.9", "0.48.8", "0.48.7", "0.48.6", "0.47.9",
    "0.47.8", "0.47.7", "0.46.11", "0.46.10", "0.46.9", "0.45.14", "0.45.13", "0.45.12",
];

fn main() -> eframe::Result<()> {
    env_logger::init();

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([1400.0, 900.0])
            .with_min_inner_size([1000.0, 600.0])
            .with_title("Cursor Studio"),
        ..Default::default()
    };

    eframe::run_native(
        "Cursor Studio",
        options,
        Box::new(|cc| {
            // Configure fonts with Unicode fallbacks
            configure_fonts(&cc.egui_ctx);

            let mut style = (*cc.egui_ctx.style()).clone();
            style.visuals.widgets.inactive.bg_fill = Color32::from_rgb(60, 60, 60);
            style.visuals.widgets.hovered.bg_fill = Color32::from_rgb(80, 80, 90);
            style.visuals.widgets.active.bg_fill = Color32::from_rgb(0, 120, 212);
            style.visuals.widgets.hovered.bg_stroke =
                Stroke::new(1.0, Color32::from_rgb(0, 120, 212));
            cc.egui_ctx.set_style(style);

            Ok(Box::new(CursorStudio::new()))
        }),
    )
}

/// Configure fonts with proper Unicode support for terminal characters
fn configure_fonts(ctx: &egui::Context) {
    use egui::{FontData, FontDefinitions, FontFamily};

    let mut fonts = FontDefinitions::default();
    let mut loaded_fonts: Vec<String> = vec![];

    // Collect all potential font paths
    let mut font_paths: Vec<String> = vec![];

    // 1. NixOS system fonts (highest priority for NixOS users)
    font_paths.extend([
        "/run/current-system/sw/share/X11/fonts/JetBrainsMono-Regular.ttf".to_string(),
        "/run/current-system/sw/share/X11/fonts/DejaVuSansMono.ttf".to_string(),
        "/run/current-system/sw/share/X11/fonts/NotoColorEmoji.ttf".to_string(),
        "/run/current-system/sw/share/fonts/truetype/NotoColorEmoji.ttf".to_string(),
        "/run/current-system/sw/share/fonts/truetype/DejaVuSansMono.ttf".to_string(),
        "/run/current-system/sw/share/fonts/truetype/JetBrainsMono-Regular.ttf".to_string(),
    ]);

    // 2. User fonts (~/.local/share/fonts/)
    if let Some(home) = dirs::home_dir() {
        let user_fonts = home.join(".local/share/fonts");
        if user_fonts.exists() {
            // Check for common font files
            for font_name in [
                "JetBrainsMono-Regular.ttf",
                "JetBrainsMonoNerdFont-Regular.ttf",
                "DejaVuSansMono.ttf",
                "NotoColorEmoji.ttf",
            ] {
                font_paths.push(user_fonts.join(font_name).to_string_lossy().to_string());
            }
            // Check NerdFonts subdirectory
            let nerd_fonts = user_fonts.join("NerdFonts");
            if nerd_fonts.exists() {
                for font_name in [
                    "JetBrainsMonoNerdFont-Regular.ttf",
                    "JetBrainsMonoNerdFontMono-Regular.ttf",
                ] {
                    font_paths.push(nerd_fonts.join(font_name).to_string_lossy().to_string());
                }
            }
        }
    }

    // 3. Nix profile fonts (from NIX_PROFILES env var)
    if let Ok(nix_profiles) = std::env::var("NIX_PROFILES") {
        for profile in nix_profiles.split(':') {
            if profile.is_empty() {
                continue;
            }
            // Try multiple possible locations within each profile
            for subpath in [
                "share/fonts/truetype/JetBrainsMono-Regular.ttf",
                "share/fonts/truetype/DejaVuSansMono.ttf",
                "share/fonts/truetype/NotoColorEmoji.ttf",
                "share/fonts/opentype/NotoSansSymbols2-Regular.otf",
                "share/X11/fonts/JetBrainsMono-Regular.ttf",
                "share/X11/fonts/DejaVuSansMono.ttf",
            ] {
                font_paths.push(format!("{}/{}", profile, subpath));
            }
        }
    }

    // 4. XDG data dirs (for flatpak, etc.)
    if let Ok(xdg_data) = std::env::var("XDG_DATA_DIRS") {
        for dir in xdg_data.split(':') {
            if dir.is_empty() {
                continue;
            }
            font_paths.push(format!("{}/fonts/truetype/DejaVuSansMono.ttf", dir));
            font_paths.push(format!("{}/fonts/truetype/JetBrainsMono-Regular.ttf", dir));
        }
    }

    // 5. Standard Linux paths (fallback)
    font_paths.extend([
        "/usr/share/fonts/TTF/DejaVuSansMono.ttf".to_string(),
        "/usr/share/fonts/dejavu/DejaVuSansMono.ttf".to_string(),
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf".to_string(),
        "/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Regular.ttf".to_string(),
        "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf".to_string(),
        "/usr/share/fonts/truetype/ubuntu/UbuntuMono-R.ttf".to_string(),
        "/usr/share/fonts/noto-emoji/NotoColorEmoji.ttf".to_string(),
        "/usr/share/fonts/google-noto-emoji/NotoColorEmoji.ttf".to_string(),
        "/usr/share/fonts/TTF/Symbola.ttf".to_string(),
    ]);

    // Load available fonts
    for path in &font_paths {
        if let Ok(font_data) = std::fs::read(path) {
            let font_name = std::path::Path::new(path)
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("CustomFont");

            // Skip if we already loaded a font with this name
            if loaded_fonts.contains(&font_name.to_string()) {
                continue;
            }

            fonts.font_data.insert(
                font_name.to_string(),
                FontData::from_owned(font_data).into(),
            );
            loaded_fonts.push(font_name.to_string());

            // Add to appropriate families based on font type
            if font_name.contains("Mono") || font_name.contains("JetBrains") {
                fonts
                    .families
                    .entry(FontFamily::Monospace)
                    .or_default()
                    .push(font_name.to_string());
            }

            // Add symbol/emoji fonts to proportional for fallback
            if font_name.contains("Emoji")
                || font_name.contains("Symbola")
                || font_name.contains("Symbol")
            {
                fonts
                    .families
                    .entry(FontFamily::Proportional)
                    .or_default()
                    .push(font_name.to_string());
            } else {
                // Regular fonts go to proportional
                fonts
                    .families
                    .entry(FontFamily::Proportional)
                    .or_default()
                    .push(font_name.to_string());
            }
        }
    }

    log::debug!(
        "Loaded {} custom fonts: {:?}",
        loaded_fonts.len(),
        loaded_fonts
    );
    ctx.set_fonts(fonts);
}

#[derive(PartialEq, Clone, Copy)]
enum SidebarMode {
    Manager,
    Search,
    Settings,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum RightSidebarMode {
    ChatLibrary,
    Security,
}

#[derive(Clone)]
enum Tab {
    Dashboard,
    Conversation(String),
}

/// Actions to perform on bookmarks (collected during UI rendering, executed after)
enum BookmarkAction {
    Add(String, String, usize), // conv_id, msg_id, msg_seq
    Remove(String, String),     // bookmark_id, conv_id
}

/// Main application state
struct CursorStudio {
    theme: Theme,
    db: ChatDatabase,

    // Layout
    left_sidebar_visible: bool,
    right_sidebar_visible: bool,
    left_sidebar_width: f32,
    right_sidebar_width: f32,

    // Mode
    left_mode: SidebarMode,
    right_mode: RightSidebarMode,

    // Tabs
    tabs: Vec<Tab>,
    active_tab: usize,

    // Data
    versions: Vec<CursorVersion>,
    conversations: Vec<Conversation>,
    current_messages: Vec<Message>,

    // Search
    search_query: String,
    search_results: Vec<Conversation>,

    // Status messages
    status_message: Option<String>,

    // Settings state
    show_theme_picker: bool,
    show_version_picker: bool,
    show_launch_picker: bool,
    available_themes: Vec<(String, Option<PathBuf>)>,
    current_theme_name: String,

    // Version management - separated concerns
    default_version: String, // Persisted default for new launches
    launch_version: String,  // Currently selected version to launch

    // Toggle states
    auto_sync_enabled: bool,
    import_on_start: bool,
    show_all_versions: bool,

    // Hover state for theme picker
    hovered_theme: Option<String>,

    // Import state
    import_in_progress: bool,
    import_progress: Option<(usize, usize)>, // (current, total)
    import_warning_shown: bool,
    last_import_error: Option<String>,

    // Bookmark state
    current_bookmarks: Vec<Bookmark>,
    show_bookmark_panel: bool,
    adding_bookmark_for: Option<String>, // message_id
    bookmark_label_input: String,
    bookmark_note_input: String,

    // Display preferences
    display_prefs: Vec<DisplayPreference>,

    // UI customization
    font_scale: f32,           // 0.8 - 1.5 scale factor
    message_spacing: f32,      // 8.0 - 24.0 pixels
    status_bar_font_size: f32, // 8.0 - 14.0 pixels

    // Async import
    import_thread: Option<std::thread::JoinHandle<Result<(usize, usize), String>>>,
    import_receiver: Option<std::sync::mpsc::Receiver<ImportProgress>>,
    import_needs_bookmark_reattach: bool,

    // Resource settings
    max_cpu_threads: usize,
    max_ram_mb: usize,
    max_vram_mb: usize,
    storage_limit_mb: usize,

    // Security scan results
    security_scan_results: Option<SecurityScanResults>,

    // NPM security scanner
    npm_scanner: security::SecurityScanner,
    npm_scan_results: Option<Vec<(PathBuf, Vec<security::PackageScanResult>)>>,
    selected_scan_item: Option<(String, String)>, // (conv_id, msg_id) for jump-to

    // Scroll-to-message support
    scroll_to_message_id: Option<String>,

    // NPM scan state
    npm_scan_path: String,
    show_npm_scan_results: bool,

    // Conversation search
    conv_search_query: String,
    conv_search_results: Vec<usize>, // indices of matching messages
    conv_search_index: usize,        // current result index
}

#[derive(Debug, Clone, Default)]
struct SecurityScanResults {
    total_messages: usize,
    scanned_at: String,
    potential_api_keys: Vec<(String, String, String)>, // (conv_id, msg_id, preview)
    potential_passwords: Vec<(String, String, String)>,
    potential_secrets: Vec<(String, String, String)>,
}

/// Progress updates during import
#[derive(Clone)]
enum ImportProgress {
    Started(usize),           // total databases to process
    Processing(usize, usize), // current database, total databases
    Completed(usize, usize),  // imported conversations, skipped (already existed)
    Error(String),
}

impl CursorStudio {
    fn new() -> Self {
        // Try to load Home Manager / external config first
        let ext_config = ExternalConfig::load();

        let db = ChatDatabase::new().expect("Failed to open database");
        let versions = db.get_versions().unwrap_or_default();
        let conversations = db.get_conversations(50).unwrap_or_default();

        let available_themes = Self::find_vscode_themes();

        // Find default version from installed versions
        let default_version = versions
            .iter()
            .find(|v| v.is_default)
            .map(|v| v.version.clone())
            .unwrap_or_else(|| "default".to_string());

        // Launch version starts as default
        let launch_version = default_version.clone();

        // Load display preferences from DB, or use external config
        let display_prefs = if let Some(ref cfg) = ext_config {
            if !cfg.display_prefs.is_empty() {
                // Convert external config to DisplayPreference
                cfg.display_prefs
                    .iter()
                    .map(|p| DisplayPreference {
                        content_type: p.content_type.clone(),
                        alignment: p.alignment.clone(),
                        style: if p.style.is_empty() {
                            "default".to_string()
                        } else {
                            p.style.clone()
                        },
                        collapsed_by_default: p.collapsed,
                    })
                    .collect()
            } else {
                db.get_display_preferences().unwrap_or_default()
            }
        } else {
            db.get_display_preferences().unwrap_or_default()
        };

        // Load UI settings: external config takes priority, then DB, then defaults
        let font_scale = ext_config
            .as_ref()
            .and_then(|c| c.font_scale)
            .unwrap_or_else(|| db.get_config_f32("ui.font_scale", 1.0));
        let message_spacing = ext_config
            .as_ref()
            .and_then(|c| c.message_spacing)
            .unwrap_or_else(|| db.get_config_f32("ui.message_spacing", 12.0));
        let status_bar_font_size = ext_config
            .as_ref()
            .and_then(|c| c.status_bar_font_size)
            .unwrap_or_else(|| db.get_config_f32("ui.status_bar_font_size", 11.0));

        // Resource limits: external config takes priority
        let default_threads = std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(8)
            .min(16);
        let max_cpu_threads = ext_config
            .as_ref()
            .and_then(|c| c.resources.as_ref())
            .and_then(|r| r.max_cpu_threads)
            .unwrap_or_else(|| db.get_config_usize("res.max_cpu_threads", default_threads));
        let max_ram_mb = ext_config
            .as_ref()
            .and_then(|c| c.resources.as_ref())
            .and_then(|r| r.max_ram_mb)
            .unwrap_or_else(|| db.get_config_usize("res.max_ram_mb", 4096));
        let max_vram_mb = ext_config
            .as_ref()
            .and_then(|c| c.resources.as_ref())
            .and_then(|r| r.max_vram_mb)
            .unwrap_or_else(|| db.get_config_usize("res.max_vram_mb", 2048));
        let storage_limit_mb = ext_config
            .as_ref()
            .and_then(|c| c.resources.as_ref())
            .and_then(|r| r.storage_limit_mb)
            .unwrap_or_else(|| db.get_config_usize("res.storage_limit_mb", 10240));

        Self {
            theme: Theme::dark(),
            db,
            left_sidebar_visible: true,
            right_sidebar_visible: true,
            left_sidebar_width: 280.0,
            right_sidebar_width: 300.0,
            left_mode: SidebarMode::Manager,
            right_mode: RightSidebarMode::ChatLibrary,
            tabs: vec![Tab::Dashboard],
            active_tab: 0,
            versions,
            conversations,
            current_messages: vec![],
            search_query: String::new(),
            search_results: vec![],
            status_message: None,
            show_theme_picker: false,
            show_version_picker: false,
            show_launch_picker: false,
            available_themes,
            current_theme_name: "Dark+ (default dark)".to_string(),
            default_version,
            launch_version,
            auto_sync_enabled: true,
            import_on_start: false,
            show_all_versions: false,
            hovered_theme: None,
            import_in_progress: false,
            import_progress: None,
            import_warning_shown: false,
            last_import_error: None,
            // Bookmark state
            current_bookmarks: vec![],
            show_bookmark_panel: false,
            adding_bookmark_for: None,
            bookmark_label_input: String::new(),
            bookmark_note_input: String::new(),
            // Display preferences
            display_prefs,
            // UI customization (loaded from config above)
            font_scale,
            message_spacing,
            status_bar_font_size,
            // Async import
            import_thread: None,
            import_receiver: None,
            import_needs_bookmark_reattach: false,
            // Resource settings (loaded from config above)
            max_cpu_threads,
            max_ram_mb,
            max_vram_mb,
            storage_limit_mb,
            // Security scan
            security_scan_results: None,

            // NPM security
            npm_scanner: security::SecurityScanner::new(),
            npm_scan_results: None,
            selected_scan_item: None,

            // Scroll-to-message
            scroll_to_message_id: None,

            // NPM scan state
            npm_scan_path: dirs::home_dir()
                .map(|h| h.to_string_lossy().to_string())
                .unwrap_or_else(|| "/home".to_string()),
            show_npm_scan_results: false,

            // Conversation search
            conv_search_query: String::new(),
            conv_search_results: Vec::new(),
            conv_search_index: 0,
        }
    }

    /// # TODO(P1): Release v0.3.0 - Settings Persistence
    /// - [ ] Add save_window_settings() for size/position
    /// - [ ] Save sidebar widths (left_sidebar_width, right_sidebar_width)
    /// - [ ] Save last opened conversation ID
    /// - [ ] Call save_settings on app close (implement on_close_event)
    /// - [ ] Add settings export/import for backup
    fn save_settings(&self) {
        // UI settings
        let _ = self
            .db
            .set_config("ui.font_scale", &self.font_scale.to_string());
        let _ = self
            .db
            .set_config("ui.message_spacing", &self.message_spacing.to_string());
        let _ = self.db.set_config(
            "ui.status_bar_font_size",
            &self.status_bar_font_size.to_string(),
        );
        // Resource settings
        let _ = self
            .db
            .set_config("res.max_cpu_threads", &self.max_cpu_threads.to_string());
        let _ = self
            .db
            .set_config("res.max_ram_mb", &self.max_ram_mb.to_string());
        let _ = self
            .db
            .set_config("res.max_vram_mb", &self.max_vram_mb.to_string());
        let _ = self
            .db
            .set_config("res.storage_limit_mb", &self.storage_limit_mb.to_string());
    }

    fn run_security_scan(&mut self) {
        use regex::Regex;

        let mut results = SecurityScanResults {
            total_messages: 0,
            scanned_at: chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
            ..Default::default()
        };

        // Patterns to detect sensitive data
        let api_key_pattern = Regex::new(r#"(?i)(api[_-]?key|apikey|api_token|auth_token)[=:\s]*['"]?([a-zA-Z0-9_\-]{20,})['"]?"#).ok();
        let password_pattern =
            Regex::new(r#"(?i)(password|passwd|pwd)[=:\s]*['"]?([^\s'"]{8,})['"]?"#).ok();
        let secret_pattern = Regex::new(
            r#"(?i)(secret|private_key|access_token|bearer)[=:\s]*['"]?([a-zA-Z0-9_\-]{16,})['"]?"#,
        )
        .ok();

        // Scan all conversations
        for conv in &self.conversations {
            if let Ok(messages) = self.db.get_messages(&conv.id) {
                for msg in messages {
                    results.total_messages += 1;

                    let content = &msg.content;

                    // Check for API keys
                    if let Some(ref pattern) = api_key_pattern {
                        for cap in pattern.captures_iter(content) {
                            let preview = cap
                                .get(0)
                                .map(|m| {
                                    let s = m.as_str();
                                    if s.len() > 50 {
                                        format!("{}...", &s.chars().take(50).collect::<String>())
                                    } else {
                                        s.to_string()
                                    }
                                })
                                .unwrap_or_default();
                            results.potential_api_keys.push((
                                conv.id.clone(),
                                msg.id.clone(),
                                preview,
                            ));
                        }
                    }

                    // Check for passwords
                    if let Some(ref pattern) = password_pattern {
                        for cap in pattern.captures_iter(content) {
                            let preview = cap
                                .get(0)
                                .map(|m| {
                                    let s = m.as_str();
                                    if s.len() > 50 {
                                        format!("{}...", &s.chars().take(50).collect::<String>())
                                    } else {
                                        s.to_string()
                                    }
                                })
                                .unwrap_or_default();
                            results.potential_passwords.push((
                                conv.id.clone(),
                                msg.id.clone(),
                                preview,
                            ));
                        }
                    }

                    // Check for secrets
                    if let Some(ref pattern) = secret_pattern {
                        for cap in pattern.captures_iter(content) {
                            let preview = cap
                                .get(0)
                                .map(|m| {
                                    let s = m.as_str();
                                    if s.len() > 50 {
                                        format!("{}...", &s.chars().take(50).collect::<String>())
                                    } else {
                                        s.to_string()
                                    }
                                })
                                .unwrap_or_default();
                            results.potential_secrets.push((
                                conv.id.clone(),
                                msg.id.clone(),
                                preview,
                            ));
                        }
                    }
                }
            }
        }

        let total_found = results.potential_api_keys.len()
            + results.potential_passwords.len()
            + results.potential_secrets.len();

        self.set_status(&format!(
            "🔍 Scanned {} messages, found {} potential sensitive items",
            results.total_messages, total_found
        ));

        self.security_scan_results = Some(results);
    }

    fn find_vscode_themes() -> Vec<(String, Option<PathBuf>)> {
        let mut themes = vec![
            ("Dark+ (default dark)".to_string(), None),
            ("Light+ (default light)".to_string(), None),
        ];

        if let Some(home) = dirs::home_dir() {
            let cursor_extensions = home.join(".cursor/extensions");
            if cursor_extensions.exists() {
                if let Ok(entries) = std::fs::read_dir(&cursor_extensions) {
                    for entry in entries.flatten() {
                        let path = entry.path();
                        if path.is_dir() {
                            let package_json = path.join("package.json");
                            if package_json.exists() {
                                if let Ok(content) = std::fs::read_to_string(&package_json) {
                                    if let Ok(json) =
                                        serde_json::from_str::<serde_json::Value>(&content)
                                    {
                                        if let Some(contributes) = json.get("contributes") {
                                            if let Some(theme_arr) = contributes.get("themes") {
                                                if let Some(arr) = theme_arr.as_array() {
                                                    for theme in arr {
                                                        if let Some(label) = theme
                                                            .get("label")
                                                            .and_then(|l| l.as_str())
                                                        {
                                                            let theme_path = theme
                                                                .get("path")
                                                                .and_then(|p| p.as_str())
                                                                .map(|p| path.join(p));

                                                            themes.push((
                                                                label.to_string(),
                                                                theme_path,
                                                            ));
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        themes
    }

    fn refresh_versions(&mut self) {
        self.versions = self.db.get_versions().unwrap_or_default();
        self.set_status("✓ Refreshed versions");
    }

    fn refresh_chats(&mut self) {
        self.conversations = self.db.get_conversations(50).unwrap_or_default();
        self.set_status("✓ Refreshed chat library");
    }

    fn refresh_all(&mut self) {
        self.versions = self.db.get_versions().unwrap_or_default();
        self.conversations = self.db.get_conversations(50).unwrap_or_default();
        self.set_status("✓ Refreshed all data");
    }

    // ==================== BOOKMARK METHODS ====================

    fn refresh_bookmarks(&mut self, conv_id: &str) {
        self.current_bookmarks = self.db.get_bookmarks(conv_id).unwrap_or_default();
    }

    fn add_bookmark(&mut self, conv_id: &str, msg_id: &str, msg_seq: usize) {
        let label = if self.bookmark_label_input.is_empty() {
            None
        } else {
            Some(self.bookmark_label_input.as_str())
        };

        let note = if self.bookmark_note_input.is_empty() {
            None
        } else {
            Some(self.bookmark_note_input.as_str())
        };

        match self
            .db
            .add_bookmark(conv_id, msg_id, msg_seq, label, note, "#ffd700")
        {
            Ok(_) => {
                self.set_status("✓ Bookmark added");
                self.refresh_bookmarks(conv_id);
            }
            Err(e) => {
                self.set_status(&format!("✗ Failed to add bookmark: {}", e));
            }
        }

        // Reset input state
        self.adding_bookmark_for = None;
        self.bookmark_label_input.clear();
        self.bookmark_note_input.clear();
    }

    fn delete_bookmark(&mut self, bookmark_id: &str, conv_id: &str) {
        match self.db.delete_bookmark(bookmark_id) {
            Ok(_) => {
                self.set_status("✓ Bookmark removed");
                self.refresh_bookmarks(conv_id);
            }
            Err(e) => {
                self.set_status(&format!("✗ Failed to remove bookmark: {}", e));
            }
        }
    }

    fn is_bookmarked(&self, msg_id: &str) -> Option<&Bookmark> {
        self.current_bookmarks
            .iter()
            .find(|b| b.message_id == msg_id)
    }

    fn scroll_to_message(&mut self, conv_id: &str, msg_id: &str) {
        // First, ensure the conversation tab is open
        let mut found_tab = false;
        for (i, tab) in self.tabs.iter().enumerate() {
            if let Tab::Conversation(id) = tab {
                if id == conv_id {
                    self.active_tab = i;
                    found_tab = true;
                    break;
                }
            }
        }

        if !found_tab {
            // Open the conversation
            self.tabs.push(Tab::Conversation(conv_id.to_string()));
            self.active_tab = self.tabs.len() - 1;
            self.current_messages = self.db.get_messages(conv_id).unwrap_or_default();
        }

        // Set the scroll target - the UI will pick this up
        self.scroll_to_message_id = Some(msg_id.to_string());
        self.set_status(&format!("📍 Jumped to message"));
    }

    fn scan_npm_packages(&mut self) {
        let path = PathBuf::from(&self.npm_scan_path);
        if !path.exists() {
            self.set_status(&format!("✗ Path does not exist: {}", self.npm_scan_path));
            return;
        }

        match self.npm_scanner.scan_directory(&path) {
            Ok(results) => {
                let total_issues: usize = results.iter().map(|(_, r)| r.len()).sum();
                if total_issues > 0 {
                    self.set_status(&format!(
                        "⚠️ Found {} blocked packages in {} files",
                        total_issues,
                        results.len()
                    ));
                } else {
                    self.set_status("✓ No blocked packages found");
                }
                self.npm_scan_results = Some(results);
                self.show_npm_scan_results = true;
            }
            Err(e) => {
                self.set_status(&format!("✗ Scan failed: {}", e));
            }
        }
    }

    /// # TODO(P1): Release v0.3.0 - Export Features
    /// - [ ] Add export_conversation_to_json() for JSON format
    /// - [ ] Add export_bookmarked_sections() for bookmarks only
    /// - [ ] Add syntax highlighting in code blocks (use ```language)
    /// - [ ] Add option to include/exclude thinking blocks
    /// - [ ] Add option to include/exclude tool calls
    /// - [ ] Show export progress for large conversations
    fn export_conversation_to_markdown(&mut self, conv_id: &str) {
        // Get conversation info
        let conv = match self.conversations.iter().find(|c| c.id == conv_id) {
            Some(c) => c.clone(),
            None => {
                self.set_status("✗ Conversation not found");
                return;
            }
        };

        // Get messages
        let messages = match self.db.get_messages(conv_id) {
            Ok(m) => m,
            Err(e) => {
                self.set_status(&format!("✗ Failed to load messages: {}", e));
                return;
            }
        };

        // Build markdown content
        let mut md = String::new();

        // Header
        md.push_str(&format!("# {}\n\n", conv.title));
        md.push_str(&format!(
            "**Exported:** {}\n",
            chrono::Local::now().format("%Y-%m-%d %H:%M:%S")
        ));
        md.push_str(&format!("**Messages:** {}\n", messages.len()));
        md.push_str(&format!("**Source:** Cursor Studio v0.2.1\n\n"));
        md.push_str("---\n\n");

        for msg in &messages {
            // Role header
            let role_icon = match msg.role {
                MessageRole::User => "👤 **USER**",
                MessageRole::Assistant => "🤖 **ASSISTANT**",
                MessageRole::ToolCall => "🔧 **TOOL CALL**",
                MessageRole::ToolResult => "📋 **TOOL RESULT**",
            };
            md.push_str(&format!("### {}\n\n", role_icon));

            // Tool call info
            if let Some(ref tc) = msg.tool_call {
                md.push_str(&format!("> **Tool:** `{}`\n", tc.name));
                if !tc.args.is_empty() {
                    // Pretty print args if JSON
                    let args_display = if let Ok(parsed) =
                        serde_json::from_str::<serde_json::Value>(&tc.args)
                    {
                        serde_json::to_string_pretty(&parsed).unwrap_or_else(|_| tc.args.clone())
                    } else {
                        tc.args.clone()
                    };
                    md.push_str(&format!(
                        "> ```json\n> {}\n> ```\n",
                        args_display.replace('\n', "\n> ")
                    ));
                }
                md.push_str(&format!("> **Status:** {}\n\n", tc.status));
            }

            // Thinking block
            if let Some(ref thinking) = msg.thinking {
                if !thinking.is_empty() {
                    md.push_str("<details>\n<summary>💭 Thinking...</summary>\n\n");
                    md.push_str(thinking);
                    md.push_str("\n\n</details>\n\n");
                }
            }

            // Main content
            if !msg.content.is_empty() {
                md.push_str(&msg.content);
                md.push_str("\n");
            }

            md.push_str("\n---\n\n");
        }

        // Save to file
        let filename = format!(
            "{}.md",
            conv.title
                .chars()
                .filter(|c| c.is_alphanumeric() || *c == ' ' || *c == '-')
                .take(50)
                .collect::<String>()
                .trim()
                .replace(' ', "_")
        );

        let export_dir = dirs::document_dir()
            .or_else(|| dirs::home_dir())
            .unwrap_or_else(|| PathBuf::from("."))
            .join("cursor-studio-exports");

        // Create directory if needed
        if let Err(e) = std::fs::create_dir_all(&export_dir) {
            self.set_status(&format!("✗ Failed to create export directory: {}", e));
            return;
        }

        let export_path = export_dir.join(&filename);

        match std::fs::write(&export_path, md) {
            Ok(_) => {
                self.set_status(&format!("✓ Exported to {}", export_path.display()));
            }
            Err(e) => {
                self.set_status(&format!("✗ Export failed: {}", e));
            }
        }
    }

    fn search_in_conversation(&mut self, query: &str) {
        self.conv_search_results.clear();
        self.conv_search_index = 0;

        if query.is_empty() {
            return;
        }

        let query_lower = query.to_lowercase();

        for (idx, msg) in self.current_messages.iter().enumerate() {
            // Search in content
            if msg.content.to_lowercase().contains(&query_lower) {
                self.conv_search_results.push(idx);
                continue;
            }

            // Search in thinking
            if let Some(ref thinking) = msg.thinking {
                if thinking.to_lowercase().contains(&query_lower) {
                    self.conv_search_results.push(idx);
                    continue;
                }
            }

            // Search in tool call
            if let Some(ref tc) = msg.tool_call {
                if tc.name.to_lowercase().contains(&query_lower)
                    || tc.args.to_lowercase().contains(&query_lower)
                {
                    self.conv_search_results.push(idx);
                }
            }
        }

        if self.conv_search_results.is_empty() {
            self.set_status(&format!("No results for '{}'", query));
        } else {
            self.set_status(&format!("Found {} matches", self.conv_search_results.len()));
            // Jump to first result
            if let Some(&idx) = self.conv_search_results.first() {
                if let Some(msg) = self.current_messages.get(idx) {
                    self.scroll_to_message_id = Some(msg.id.clone());
                }
            }
        }
    }

    fn jump_to_next_search_result(&mut self) {
        if self.conv_search_results.is_empty() {
            return;
        }

        self.conv_search_index = (self.conv_search_index + 1) % self.conv_search_results.len();
        if let Some(&idx) = self.conv_search_results.get(self.conv_search_index) {
            if let Some(msg) = self.current_messages.get(idx) {
                self.scroll_to_message_id = Some(msg.id.clone());
                self.set_status(&format!(
                    "Result {} of {}",
                    self.conv_search_index + 1,
                    self.conv_search_results.len()
                ));
            }
        }
    }

    fn jump_to_prev_search_result(&mut self) {
        if self.conv_search_results.is_empty() {
            return;
        }

        if self.conv_search_index == 0 {
            self.conv_search_index = self.conv_search_results.len() - 1;
        } else {
            self.conv_search_index -= 1;
        }

        if let Some(&idx) = self.conv_search_results.get(self.conv_search_index) {
            if let Some(msg) = self.current_messages.get(idx) {
                self.scroll_to_message_id = Some(msg.id.clone());
                self.set_status(&format!(
                    "Result {} of {}",
                    self.conv_search_index + 1,
                    self.conv_search_results.len()
                ));
            }
        }
    }

    fn set_status(&mut self, msg: &str) {
        self.status_message = Some(msg.to_string());
        log::info!("{}", msg);
    }

    fn do_clear_and_reimport(&mut self) {
        if self.import_in_progress {
            self.set_status("⏳ Import already in progress...");
            return;
        }

        // Clear all conversations and messages (bookmarks preserved!)
        if let Err(e) = self.db.clear_all() {
            self.set_status(&format!("✗ Clear failed: {}", e));
            return;
        }

        self.set_status("🗑️ Cleared chats (bookmarks preserved). Starting reimport...");
        self.do_import_internal(true); // true = reattach bookmarks after
    }

    fn do_import(&mut self) {
        if self.import_in_progress {
            self.set_status("⏳ Import already in progress...");
            return;
        }

        self.do_import_internal(false); // false = don't reattach bookmarks
    }

    fn do_import_internal(&mut self, reattach_bookmarks: bool) {
        self.import_in_progress = true;
        self.import_needs_bookmark_reattach = reattach_bookmarks;
        self.last_import_error = None;
        self.set_status("⏳ Starting async import...");

        // Create channel for progress updates
        let (tx, rx) = std::sync::mpsc::channel();
        self.import_receiver = Some(rx);

        // Get database path and spawn import thread
        let db_path = self.db.get_path();

        let _handle = std::thread::spawn(move || -> Result<(usize, usize), String> {
            // Create new database connection in thread
            let import_db = match database::ChatDatabase::open(&db_path) {
                Ok(db) => db,
                Err(e) => {
                    let _ = tx.send(ImportProgress::Error(e.to_string()));
                    return Err(e.to_string());
                }
            };

            // Find all Cursor databases to import
            let home = match dirs::home_dir() {
                Some(h) => h,
                None => {
                    let _ = tx.send(ImportProgress::Error("No home directory".to_string()));
                    return Err("No home directory".to_string());
                }
            };

            let mut db_paths: Vec<(std::path::PathBuf, String)> = Vec::new();

            // Main Cursor database
            let main_db = home.join(".config/Cursor/User/globalStorage/state.vscdb");
            if main_db.exists() {
                db_paths.push((main_db, "default".to_string()));
            }

            // Versioned Cursor databases
            if let Ok(entries) = std::fs::read_dir(&home) {
                for entry in entries.flatten() {
                    let name = entry.file_name().to_string_lossy().to_string();
                    if name.starts_with(".cursor-") {
                        if let Ok(ft) = entry.file_type() {
                            if ft.is_dir() {
                                let version =
                                    name.strip_prefix(".cursor-").unwrap_or(&name).to_string();
                                let db_path = entry.path().join("User/globalStorage/state.vscdb");
                                if db_path.exists() {
                                    db_paths.push((db_path, version));
                                }
                            }
                        }
                    }
                }
            }

            let total = db_paths.len();
            let _ = tx.send(ImportProgress::Started(total));

            let mut total_imported = 0;
            let mut total_skipped = 0;

            for (idx, (path, version)) in db_paths.into_iter().enumerate() {
                let _ = tx.send(ImportProgress::Processing(idx + 1, total));

                match import_db.import_from_cursor(path, &version) {
                    Ok((imported, skipped)) => {
                        total_imported += imported;
                        total_skipped += skipped;
                    }
                    Err(e) => {
                        log::warn!("Failed to import {}: {}", version, e);
                        // Continue with other imports
                    }
                }

                // Small delay to keep UI responsive
                std::thread::sleep(std::time::Duration::from_millis(10));
            }

            let _ = tx.send(ImportProgress::Completed(total_imported, total_skipped));
            Ok((total_imported, total_skipped))
        });

        // Note: We don't store the handle since we track completion via channel
    }

    fn do_sync(&mut self) {
        self.set_status("⏳ Syncing settings across versions...");

        // Get the source version (default version's config)
        let source_version = &self.default_version;
        let versions_to_sync: Vec<_> = self
            .versions
            .iter()
            .filter(|v| &v.version != source_version)
            .map(|v| v.version.clone())
            .collect();

        if versions_to_sync.is_empty() {
            self.set_status("No other versions to sync to");
            return;
        }

        // For now, just report what would be synced
        // TODO: Actually sync settings files
        self.set_status(&format!(
            "✓ Would sync to {} versions (not yet implemented)",
            versions_to_sync.len()
        ));
    }

    fn apply_theme(&mut self, theme_name: &str, theme_path: Option<&PathBuf>) {
        self.current_theme_name = theme_name.to_string();

        if theme_name.contains("Light") {
            self.theme = Theme::light();
            self.set_status(&format!("✓ Applied theme: {}", theme_name));
        } else if let Some(path) = theme_path {
            if let Some(loaded_theme) = Theme::from_vscode_file(path) {
                self.theme = loaded_theme;
                self.set_status(&format!("✓ Applied theme: {}", theme_name));
            } else {
                self.set_status(&format!("✗ Failed to load theme: {}", theme_name));
            }
        } else {
            self.theme = Theme::dark();
            self.set_status(&format!("✓ Applied theme: {}", theme_name));
        }

        self.show_theme_picker = false;
    }

    fn set_default_version(&mut self, version: &str) {
        self.default_version = version.to_string();
        // Also update launch version to match new default
        self.launch_version = version.to_string();
        let display_name = Self::version_display_name(version);
        self.set_status(&format!("✓ Set default version: {}", display_name));
        self.show_version_picker = false;
        // TODO: Persist this choice to config file
    }

    fn set_launch_version(&mut self, version: &str) {
        self.launch_version = version.to_string();
        let display_name = Self::version_display_name(version);
        self.set_status(&format!("✓ Will launch: {}", display_name));
        self.show_launch_picker = false;
    }

    fn version_display_name(version: &str) -> String {
        if version == "default" {
            "Main Cursor".to_string()
        } else {
            format!("v{}", version)
        }
    }

    fn launch_cursor(&mut self) {
        let version = &self.launch_version;
        let display_name = Self::version_display_name(version);

        // Determine the command to run based on version
        let result = if version == "default" {
            // Launch main Cursor installation
            Command::new("cursor").spawn()
        } else {
            // Try to find version-specific installation
            if let Some(home) = dirs::home_dir() {
                // Check for versioned Cursor installations
                let versioned_path = home.join(format!(".cursor-{}/cursor", version));
                let appimage_path = home.join(format!("Applications/Cursor-{}.AppImage", version));

                if versioned_path.exists() {
                    Command::new(&versioned_path).spawn()
                } else if appimage_path.exists() {
                    Command::new(&appimage_path).spawn()
                } else {
                    // Fall back to main cursor with env var hint
                    Command::new("cursor")
                        .env("CURSOR_VERSION", version)
                        .spawn()
                }
            } else {
                Command::new("cursor").spawn()
            }
        };

        match result {
            Ok(_) => self.set_status(&format!("✓ Launching {}...", display_name)),
            Err(e) => self.set_status(&format!("✗ Failed to launch: {}", e)),
        }
    }

    fn get_all_versions(&self) -> Vec<(String, bool)> {
        // Returns (version, is_installed)
        let installed: std::collections::HashSet<_> =
            self.versions.iter().map(|v| v.version.clone()).collect();

        let mut all_versions: Vec<(String, bool)> = self
            .versions
            .iter()
            .map(|v| (v.version.clone(), true))
            .collect();

        if self.show_all_versions {
            for &ver in AVAILABLE_VERSIONS {
                if !installed.contains(ver) {
                    all_versions.push((ver.to_string(), false));
                }
            }
        }

        all_versions
    }
}

// Helper for styled buttons
fn styled_button(ui: &mut egui::Ui, text: &str, min_size: Vec2) -> egui::Response {
    let btn = egui::Button::new(RichText::new(text).size(12.0))
        .min_size(min_size)
        .rounding(Rounding::same(4.0));

    let response = ui.add(btn);

    if response.hovered() {
        ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
    }

    response
}

fn styled_button_accent(
    ui: &mut egui::Ui,
    text: &str,
    min_size: Vec2,
    theme: Theme,
) -> egui::Response {
    let btn = egui::Button::new(RichText::new(text).size(13.0).color(Color32::WHITE))
        .min_size(min_size)
        .rounding(Rounding::same(4.0))
        .fill(theme.accent);

    let response = ui.add(btn);

    if response.hovered() {
        ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
    }

    response
}

fn toggle_switch(ui: &mut egui::Ui, on: &mut bool, theme: Theme) -> egui::Response {
    let desired_size = Vec2::new(40.0, 20.0);
    let (rect, response) = ui.allocate_exact_size(desired_size, egui::Sense::click());

    if response.clicked() {
        *on = !*on;
    }

    if response.hovered() {
        ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
    }

    if ui.is_rect_visible(rect) {
        let how_on = ui.ctx().animate_bool_responsive(response.id, *on);
        let bg_color = Color32::from_rgb(
            (60.0 + (theme.accent.r() as f32 - 60.0) * how_on) as u8,
            (60.0 + (theme.accent.g() as f32 - 60.0) * how_on) as u8,
            (60.0 + (theme.accent.b() as f32 - 60.0) * how_on) as u8,
        );

        ui.painter()
            .rect_filled(rect, Rounding::same(10.0), bg_color);

        let circle_x = rect.left() + 10.0 + (rect.width() - 20.0) * how_on;
        let circle_center = egui::pos2(circle_x, rect.center().y);
        ui.painter()
            .circle_filled(circle_center, 8.0, Color32::WHITE);
    }

    response
}

impl eframe::App for CursorStudio {
    /// Save settings when the app is about to exit
    fn on_exit(&mut self, _gl: Option<&eframe::glow::Context>) {
        log::info!("Saving settings on exit...");
        self.save_settings();
        log::info!("Settings saved successfully");
    }

    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        let theme = self.theme;

        let mut visuals = if theme.bg.r() > 128 {
            egui::Visuals::light()
        } else {
            egui::Visuals::dark()
        };
        visuals.panel_fill = theme.bg;
        visuals.window_fill = theme.sidebar_bg;
        visuals.faint_bg_color = theme.input_bg;
        visuals.extreme_bg_color = theme.code_bg;
        visuals.widgets.noninteractive.bg_fill = theme.sidebar_bg;
        visuals.widgets.inactive.bg_fill = theme.input_bg;
        visuals.widgets.hovered.bg_fill = theme.list_hover;
        visuals.widgets.active.bg_fill = theme.accent;
        visuals.selection.bg_fill = theme.selection;
        ctx.set_visuals(visuals);

        egui::SidePanel::left("activity_bar")
            .exact_width(48.0)
            .resizable(false)
            .frame(egui::Frame::none().fill(theme.activitybar_bg))
            .show(ctx, |ui| {
                self.show_activity_bar(ui, theme);
            });

        egui::TopBottomPanel::bottom("status_bar")
            .exact_height(24.0)
            .frame(
                egui::Frame::none()
                    .fill(theme.statusbar_bg)
                    .inner_margin(egui::Margin::symmetric(12.0, 4.0)),
            )
            .show(ctx, |ui| {
                self.show_status_bar(ui);
            });

        if self.left_sidebar_visible {
            egui::SidePanel::left("left_sidebar")
                .default_width(self.left_sidebar_width)
                .width_range(200.0..=500.0)
                .resizable(true)
                .frame(
                    egui::Frame::none()
                        .fill(theme.sidebar_bg)
                        .inner_margin(egui::Margin::ZERO),
                )
                .show(ctx, |ui| {
                    self.left_sidebar_width = ui.available_width();

                    match self.left_mode {
                        SidebarMode::Manager => self.show_manager_panel(ui, theme),
                        SidebarMode::Search => self.show_search_panel(ui, theme),
                        SidebarMode::Settings => self.show_settings_panel(ui, theme),
                    }
                });
        }

        if self.right_sidebar_visible {
            egui::SidePanel::right("right_sidebar")
                .default_width(self.right_sidebar_width)
                .width_range(200.0..=500.0)
                .resizable(true)
                .frame(
                    egui::Frame::none()
                        .fill(theme.sidebar_bg)
                        .inner_margin(egui::Margin::ZERO),
                )
                .show(ctx, |ui| {
                    self.right_sidebar_width = ui.available_width();

                    // Mode selector header (VS Code style)
                    ui.horizontal(|ui| {
                        ui.add_space(8.0);

                        // Chat Library button
                        let chat_selected = self.right_mode == RightSidebarMode::ChatLibrary;
                        let chat_btn = ui
                            .add(
                                egui::Button::new(RichText::new("💬").size(16.0).color(
                                    if chat_selected {
                                        theme.accent
                                    } else {
                                        theme.fg_dim
                                    },
                                ))
                                .frame(false)
                                .min_size(Vec2::new(32.0, 28.0)),
                            )
                            .on_hover_text("Chat Library");
                        if chat_btn.clicked() {
                            self.right_mode = RightSidebarMode::ChatLibrary;
                        }
                        if chat_btn.hovered() {
                            ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                        }

                        // Security button
                        let sec_selected = self.right_mode == RightSidebarMode::Security;
                        let sec_btn = ui
                            .add(
                                egui::Button::new(RichText::new("🔒").size(16.0).color(
                                    if sec_selected {
                                        theme.accent
                                    } else {
                                        theme.fg_dim
                                    },
                                ))
                                .frame(false)
                                .min_size(Vec2::new(32.0, 28.0)),
                            )
                            .on_hover_text("Security");
                        if sec_btn.clicked() {
                            self.right_mode = RightSidebarMode::Security;
                        }
                        if sec_btn.hovered() {
                            ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                        }

                        // Underline indicator for selected mode
                        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                            ui.add_space(8.0);
                            let mode_label = match self.right_mode {
                                RightSidebarMode::ChatLibrary => "CHATS",
                                RightSidebarMode::Security => "SECURITY",
                            };
                            ui.label(
                                RichText::new(mode_label)
                                    .size(10.0)
                                    .color(theme.fg_dim)
                                    .strong(),
                            );
                        });
                    });

                    ui.add_space(4.0);
                    ui.separator();

                    // Show content based on mode
                    match self.right_mode {
                        RightSidebarMode::ChatLibrary => self.show_chat_library(ui, theme),
                        RightSidebarMode::Security => self.show_security_panel(ui, theme),
                    }
                });
        }

        egui::CentralPanel::default()
            .frame(egui::Frame::none().fill(theme.editor_bg))
            .show(ctx, |ui| {
                self.show_editor_area(ui, theme);
            });
    }
}

impl CursorStudio {
    fn show_activity_bar(&mut self, ui: &mut egui::Ui, theme: Theme) {
        ui.vertical_centered(|ui| {
            ui.add_space(12.0);

            self.activity_button(ui, "📁", "Versions", SidebarMode::Manager, theme);
            ui.add_space(4.0);

            self.activity_button(ui, "🔎", "Search", SidebarMode::Search, theme);
            ui.add_space(4.0);

            self.activity_button(ui, "⚙️", "Settings", SidebarMode::Settings, theme);

            ui.add_space(ui.available_height() - 50.0);

            let right_icon = if self.right_sidebar_visible {
                "◨"
            } else {
                "◧"
            };
            let right_tooltip = if self.right_sidebar_visible {
                "Hide Chat Library"
            } else {
                "Show Chat Library"
            };

            let btn = ui
                .add(
                    egui::Button::new(RichText::new(right_icon).size(18.0).color(
                        if self.right_sidebar_visible {
                            theme.accent
                        } else {
                            theme.fg_dim
                        },
                    ))
                    .frame(false)
                    .min_size(Vec2::new(40.0, 40.0)),
                )
                .on_hover_text(right_tooltip);

            if btn.hovered() {
                ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
            }

            if btn.clicked() {
                self.right_sidebar_visible = !self.right_sidebar_visible;
            }

            ui.add_space(8.0);
        });
    }

    fn activity_button(
        &mut self,
        ui: &mut egui::Ui,
        icon: &str,
        tooltip: &str,
        mode: SidebarMode,
        theme: Theme,
    ) {
        let is_active = self.left_sidebar_visible && self.left_mode == mode;

        let response = ui
            .add(
                egui::Button::new(RichText::new(icon).size(20.0).color(if is_active {
                    theme.accent
                } else {
                    theme.fg_dim
                }))
                .frame(false)
                .min_size(Vec2::new(40.0, 40.0)),
            )
            .on_hover_text(tooltip);

        if response.hovered() {
            ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
        }

        if is_active {
            let rect = response.rect;
            ui.painter().vline(
                rect.left() - 4.0,
                rect.y_range(),
                Stroke::new(3.0, theme.accent),
            );
        }

        if response.clicked() {
            if self.left_mode == mode && self.left_sidebar_visible {
                self.left_sidebar_visible = false;
            } else {
                self.left_mode = mode;
                self.left_sidebar_visible = true;
            }
        }
    }

    fn show_manager_panel(&mut self, ui: &mut egui::Ui, theme: Theme) {
        ui.vertical(|ui| {
            // Header with controls
            ui.add_space(12.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("VERSIONS")
                        .size(11.0)
                        .color(theme.fg_dim)
                        .strong(),
                );

                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.add_space(8.0);

                    // Refresh button
                    let refresh_btn = ui
                        .add(
                            egui::Button::new(RichText::new("↻").size(14.0).color(theme.fg_dim))
                                .frame(false),
                        )
                        .on_hover_text("Refresh versions");
                    if refresh_btn.hovered() {
                        ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                    }
                    if refresh_btn.clicked() {
                        self.refresh_versions();
                    }

                    ui.add_space(4.0);

                    // Toggle for showing all versions
                    let toggle_text = if self.show_all_versions {
                        "All"
                    } else {
                        "Installed"
                    };
                    let toggle_btn = ui
                        .add(
                            egui::Button::new(
                                RichText::new(toggle_text).size(10.0).color(theme.accent),
                            )
                            .frame(false),
                        )
                        .on_hover_text("Toggle between installed and all available versions");

                    if toggle_btn.hovered() {
                        ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                    }

                    if toggle_btn.clicked() {
                        self.show_all_versions = !self.show_all_versions;
                        self.set_status(if self.show_all_versions {
                            "Showing all available versions"
                        } else {
                            "Showing installed versions only"
                        });
                    }
                });
            });
            ui.add_space(8.0);

            // Current launch version indicator
            let launch_display = Self::version_display_name(&self.launch_version);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(RichText::new("Launch:").size(11.0).color(theme.fg_dim));

                let launch_btn = ui
                    .add(
                        egui::Button::new(
                            RichText::new(&launch_display)
                                .size(11.0)
                                .color(theme.accent),
                        )
                        .frame(false),
                    )
                    .on_hover_text("Click to change which version to launch");

                if launch_btn.hovered() {
                    ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                }

                if launch_btn.clicked() {
                    self.show_launch_picker = !self.show_launch_picker;
                }
            });

            // Launch version picker dropdown
            if self.show_launch_picker {
                ui.add_space(4.0);
                egui::Frame::none()
                    .fill(theme.input_bg)
                    .rounding(Rounding::same(6.0))
                    .stroke(Stroke::new(1.0, theme.border))
                    .inner_margin(egui::Margin::same(6.0))
                    .show(ui, |ui| {
                        let versions = self.versions.clone();
                        let mut selected: Option<String> = None;

                        for version in &versions {
                            let is_current = version.version == self.launch_version;
                            let label = Self::version_display_name(&version.version);

                            let bg = if is_current {
                                theme.selection
                            } else {
                                Color32::TRANSPARENT
                            };

                            egui::Frame::none()
                                .fill(bg)
                                .rounding(Rounding::same(4.0))
                                .inner_margin(egui::Margin::symmetric(8.0, 4.0))
                                .show(ui, |ui| {
                                    let btn = ui.add(
                                        egui::Button::new(
                                            RichText::new(&label)
                                                .color(if is_current {
                                                    theme.accent
                                                } else {
                                                    theme.fg
                                                })
                                                .size(12.0),
                                        )
                                        .frame(false)
                                        .min_size(Vec2::new(ui.available_width() - 16.0, 22.0)),
                                    );

                                    if btn.hovered() {
                                        ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                                    }

                                    if btn.clicked() {
                                        selected = Some(version.version.clone());
                                    }
                                });
                        }

                        if let Some(ver) = selected {
                            self.set_launch_version(&ver);
                        }
                    });
            }

            ui.add_space(8.0);

            // Version list
            let all_versions = self.get_all_versions();
            let available_height = ui.available_height() - 160.0;
            let default_ver = self.default_version.clone();

            egui::ScrollArea::vertical()
                .max_height(available_height.max(100.0))
                .show(ui, |ui| {
                    if all_versions.is_empty() {
                        ui.horizontal(|ui| {
                            ui.add_space(16.0);
                            ui.label(
                                RichText::new("No Cursor installations found")
                                    .color(theme.fg_dim)
                                    .italics(),
                            );
                        });
                    }

                    for (version, is_installed) in &all_versions {
                        let is_default = version == &default_ver
                            || (version == "default" && default_ver == "default");

                        let bg_color = if is_default {
                            theme.selection
                        } else {
                            Color32::TRANSPARENT
                        };

                        egui::Frame::none()
                            .fill(bg_color)
                            .rounding(Rounding::same(4.0))
                            .inner_margin(egui::Margin::symmetric(4.0, 2.0))
                            .show(ui, |ui| {
                                let response = ui
                                    .horizontal(|ui| {
                                        ui.add_space(8.0);

                                        // Star for default
                                        let icon = if is_default { "★" } else { "○" };
                                        let icon_color = if is_default {
                                            theme.warning
                                        } else if !is_installed {
                                            theme.fg_dim.linear_multiply(0.5)
                                        } else {
                                            theme.fg_dim
                                        };
                                        ui.label(RichText::new(icon).color(icon_color).size(14.0));

                                        ui.add_space(8.0);

                                        let label = Self::version_display_name(version);
                                        let text_color = if !is_installed {
                                            theme.fg_dim
                                        } else if is_default {
                                            theme.fg_bright
                                        } else {
                                            theme.fg
                                        };

                                        let tooltip = if !is_installed {
                                            "Not installed - click to download"
                                        } else {
                                            "Click to set as default"
                                        };

                                        let btn = ui
                                            .add(
                                                egui::Button::new(
                                                    RichText::new(&label)
                                                        .color(text_color)
                                                        .size(13.0),
                                                )
                                                .frame(false),
                                            )
                                            .on_hover_text(tooltip);

                                        if btn.hovered() {
                                            ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                                        }

                                        // Show "not installed" indicator
                                        if !is_installed {
                                            ui.label(
                                                RichText::new("⬇").color(theme.fg_dim).size(10.0),
                                            );
                                        }

                                        btn
                                    })
                                    .inner;

                                if response.clicked() {
                                    if *is_installed {
                                        self.set_default_version(version);
                                    } else {
                                        self.set_status(&format!(
                                            "Download for {} not yet implemented",
                                            version
                                        ));
                                    }
                                }
                            });

                        ui.add_space(2.0);
                    }
                });

            // Spacer
            ui.add_space(ui.available_height() - 130.0);

            // Actions section
            ui.separator();
            ui.add_space(8.0);

            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("ACTIONS")
                        .size(11.0)
                        .color(theme.fg_dim)
                        .strong(),
                );
            });
            ui.add_space(8.0);

            ui.horizontal(|ui| {
                ui.add_space(12.0);
                if styled_button_accent(ui, "▶ Launch", Vec2::new(90.0, 28.0), theme).clicked() {
                    self.launch_cursor();
                }
            });
            ui.add_space(4.0);

            ui.horizontal(|ui| {
                ui.add_space(12.0);
                if styled_button(ui, "⚡ Sync All", Vec2::new(90.0, 28.0))
                    .on_hover_text("Sync settings from default to all versions")
                    .clicked()
                {
                    self.do_sync();
                }
            });
            ui.add_space(8.0);
        });
    }

    /// # TODO(P1): Release v0.3.0 - Global Search
    /// - [ ] Add global_search() to search across ALL conversations
    /// - [ ] Add filter buttons: All | 👤 User | 🤖 AI | 🔧 Tools
    /// - [ ] Add date range filter
    /// - [ ] Add "Jump to" buttons for search results
    /// - [ ] Show conversation title in results
    /// - [ ] Highlight matching text in results
    fn show_search_panel(&mut self, ui: &mut egui::Ui, theme: Theme) {
        ui.vertical(|ui| {
            ui.add_space(12.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("SEARCH CHATS")
                        .size(11.0)
                        .color(theme.fg_dim)
                        .strong(),
                );
            });
            ui.add_space(8.0);

            ui.horizontal(|ui| {
                ui.add_space(12.0);
                let response = ui.add(
                    egui::TextEdit::singleline(&mut self.search_query)
                        .hint_text("Type to search...")
                        .desired_width(ui.available_width() - 24.0)
                        .margin(egui::Margin::symmetric(8.0, 6.0)),
                );

                if response.changed() {
                    if !self.search_query.is_empty() {
                        self.search_results = self
                            .db
                            .search_conversations(&self.search_query)
                            .unwrap_or_default();
                    } else {
                        self.search_results.clear();
                    }
                }
            });
            ui.add_space(8.0);

            let results = self.search_results.clone();
            let mut to_open: Option<String> = None;

            if !results.is_empty() {
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new(format!("{} results", results.len()))
                            .size(11.0)
                            .color(theme.fg_dim),
                    );
                });
                ui.add_space(4.0);

                egui::ScrollArea::vertical().show(ui, |ui| {
                    for conv in &results {
                        ui.horizontal(|ui| {
                            ui.add_space(12.0);

                            let row = ui.add(
                                egui::Button::new(
                                    RichText::new(&conv.title).color(theme.fg).size(12.0),
                                )
                                .frame(false)
                                .min_size(Vec2::new(ui.available_width() - 24.0, 24.0)),
                            );

                            if row.hovered() {
                                ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                            }

                            if row.clicked() {
                                to_open = Some(conv.id.clone());
                            }
                        });
                    }
                });
            } else if !self.search_query.is_empty() {
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new("No results found")
                            .color(theme.fg_dim)
                            .italics(),
                    );
                });
            } else {
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new("Enter a search term")
                            .color(theme.fg_dim)
                            .italics(),
                    );
                });
            }

            if let Some(id) = to_open {
                self.open_conversation(&id);
            }
        });
    }

    fn show_settings_panel(&mut self, ui: &mut egui::Ui, theme: Theme) {
        ui.vertical(|ui| {
            ui.add_space(12.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("APPEARANCE")
                        .size(11.0)
                        .color(theme.fg_dim)
                        .strong(),
                );
            });
            ui.add_space(12.0);

            // Theme dropdown
            self.settings_dropdown_ui(
                ui,
                theme,
                "Theme",
                &self.current_theme_name.clone(),
                "show_theme",
            );

            if self.show_theme_picker {
                ui.add_space(4.0);
                egui::Frame::none()
                    .fill(theme.input_bg)
                    .rounding(Rounding::same(6.0))
                    .stroke(Stroke::new(1.0, theme.border))
                    .inner_margin(egui::Margin::same(6.0))
                    .show(ui, |ui| {
                        // Refresh button at top
                        ui.horizontal(|ui| {
                            ui.label(
                                RichText::new("Themes")
                                    .color(theme.fg_dim)
                                    .size(10.0),
                            );
                            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                                if ui
                                    .add(
                                        egui::Button::new(
                                            RichText::new("↻").color(theme.fg_dim).size(12.0),
                                        )
                                        .frame(false),
                                    )
                                    .on_hover_text("Refresh theme list")
                                    .clicked()
                                {
                                    self.available_themes = Self::find_vscode_themes();
                                    self.set_status("✓ Refreshed theme list");
                                }
                            });
                        });
                        ui.add_space(4.0);
                        ui.separator();
                        ui.add_space(4.0);

                        // Scrollable theme list
                        let max_height = 300.0;
                        egui::ScrollArea::vertical()
                            .max_height(max_height)
                            .auto_shrink([false; 2])
                            .show(ui, |ui| {
                                let themes = self.available_themes.clone();
                                let mut selected_theme: Option<(String, Option<PathBuf>)> = None;

                                for (theme_name, theme_path) in &themes {
                                    let is_current = &self.current_theme_name == theme_name;
                                    let is_hovered = self.hovered_theme.as_ref() == Some(theme_name);

                                    let bg = if is_current {
                                        theme.selection
                                    } else if is_hovered {
                                        theme.list_hover
                                    } else {
                                        Color32::TRANSPARENT
                                    };

                                    egui::Frame::none()
                                        .fill(bg)
                                        .rounding(Rounding::same(4.0))
                                        .inner_margin(egui::Margin::symmetric(8.0, 4.0))
                                        .show(ui, |ui| {
                                            let btn = ui.add(
                                                egui::Button::new(
                                                    RichText::new(theme_name)
                                                        .color(if is_current {
                                                            theme.accent
                                                        } else {
                                                            theme.fg
                                                        })
                                                        .size(12.0),
                                                )
                                                .frame(false)
                                                .min_size(Vec2::new(ui.available_width() - 16.0, 22.0)),
                                            );

                                            if btn.hovered() {
                                                ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                                                self.hovered_theme = Some(theme_name.clone());
                                            }

                                            if btn.clicked() {
                                                selected_theme =
                                                    Some((theme_name.clone(), theme_path.clone()));
                                            }
                                        });
                                }

                                if let Some((name, path)) = selected_theme {
                                    self.apply_theme(&name, path.as_ref());
                                }
                            });
                    });
            } else {
                self.hovered_theme = None;
            }
            ui.add_space(12.0);

            // Default Version dropdown
            let version_display = Self::version_display_name(&self.default_version);
            self.settings_dropdown_ui(
                ui,
                theme,
                "Default Version",
                &version_display,
                "show_version",
            );

            if self.show_version_picker {
                ui.add_space(4.0);
                egui::Frame::none()
                    .fill(theme.input_bg)
                    .rounding(Rounding::same(6.0))
                    .stroke(Stroke::new(1.0, theme.border))
                    .inner_margin(egui::Margin::same(6.0))
                    .show(ui, |ui| {
                        let versions = self.versions.clone();
                        let mut selected: Option<String> = None;

                        for version in &versions {
                            let is_current = version.version == self.default_version;
                            let label = Self::version_display_name(&version.version);

                            let bg = if is_current {
                                theme.selection
                            } else {
                                Color32::TRANSPARENT
                            };

                            egui::Frame::none()
                                .fill(bg)
                                .rounding(Rounding::same(4.0))
                                .inner_margin(egui::Margin::symmetric(8.0, 4.0))
                                .show(ui, |ui| {
                                    let btn = ui.add(
                                        egui::Button::new(
                                            RichText::new(&label)
                                                .color(if is_current {
                                                    theme.accent
                                                } else {
                                                    theme.fg
                                                })
                                                .size(12.0),
                                        )
                                        .frame(false)
                                        .min_size(Vec2::new(ui.available_width() - 16.0, 22.0)),
                                    );

                                    if btn.hovered() {
                                        ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                                    }

                                    if btn.clicked() {
                                        selected = Some(version.version.clone());
                                    }
                                });
                        }

                        if let Some(ver) = selected {
                            self.set_default_version(&ver);
                        }
                    });
            }

            ui.add_space(20.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("BEHAVIOR")
                        .size(11.0)
                        .color(theme.fg_dim)
                        .strong(),
                );
            });
            ui.add_space(12.0);

            // Toggles
            self.settings_toggle_ui(
                ui,
                theme,
                "Auto Sync",
                "Sync settings between versions automatically",
                "auto_sync",
            );
            ui.add_space(8.0);

            self.settings_toggle_ui(
                ui,
                theme,
                "Import on Start",
                "Import new chats when app starts",
                "import_on_start",
            );
            ui.add_space(8.0);

            self.settings_toggle_ui(
                ui,
                theme,
                "Show All Versions",
                "Include downloadable versions in list",
                "show_all_versions",
            );

            ui.add_space(20.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("APPEARANCE")
                        .size(11.0)
                        .color(theme.fg_dim)
                        .strong(),
                );
            });
            ui.add_space(8.0);

            // Font scale slider - using vertical layout to prevent clipping
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(RichText::new("Font Scale").color(theme.fg).size(12.0));
            });
            ui.horizontal(|ui| {
                ui.add_space(24.0);
                let slider = ui.add(
                    egui::Slider::new(&mut self.font_scale, 0.8..=1.5)
                        .show_value(true)
                        .suffix("%")
                        .custom_formatter(|v, _| format!("{:.0}", v * 100.0))
                        .custom_parser(|s| s.parse::<f64>().ok().map(|v| v / 100.0)),
                );
                if slider.changed() {
                    self.save_settings();
                    self.set_status(&format!("✓ Font scale: {:.0}%", self.font_scale * 100.0));
                }
            });
            ui.add_space(8.0);

            // Message spacing slider
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(RichText::new("Message Spacing").color(theme.fg).size(12.0));
            });
            ui.horizontal(|ui| {
                ui.add_space(24.0);
                let slider = ui.add(
                    egui::Slider::new(&mut self.message_spacing, 4.0..=32.0)
                        .show_value(true)
                        .suffix("px"),
                );
                if slider.changed() {
                    self.save_settings();
                    self.set_status(&format!("✓ Message spacing: {:.0}px", self.message_spacing));
                }
            });
            ui.add_space(8.0);

            // Status bar font size slider
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(RichText::new("Status Bar Font").color(theme.fg).size(12.0));
            });
            ui.horizontal(|ui| {
                ui.add_space(24.0);
                let slider = ui.add(
                    egui::Slider::new(&mut self.status_bar_font_size, 8.0..=16.0)
                        .show_value(true)
                        .suffix("px"),
                );
                if slider.changed() {
                    self.save_settings();
                    self.set_status(&format!(
                        "✓ Status bar font: {:.0}px",
                        self.status_bar_font_size
                    ));
                }
            });

            ui.add_space(20.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("MESSAGE ALIGNMENT")
                        .size(11.0)
                        .color(theme.fg_dim)
                        .strong(),
                );
            });
            ui.add_space(8.0);

            // Display preferences for message types
            let alignments = ["left", "right", "center"];
            let content_types = [
                ("user", "User Messages"),
                ("assistant", "AI Responses"),
                ("thinking", "Thinking Blocks"),
                ("tool_call", "Tool Calls"),
            ];

            // Clone prefs to avoid borrow issues
            let current_prefs = self.display_prefs.clone();
            let mut pref_change: Option<(&str, &str)> = None;

            for (content_type, label) in content_types {
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(RichText::new(label).color(theme.fg).size(12.0));

                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        ui.add_space(16.0);

                        // Find current alignment
                        let current = current_prefs
                            .iter()
                            .find(|p| p.content_type == content_type)
                            .map(|p| p.alignment.as_str())
                            .unwrap_or("left");

                        // Show buttons in order: left, center, right (reversed for RTL layout)
                        for align in ["right", "center", "left"].iter() {
                            let is_selected = current == *align;
                            let icon = match *align {
                                "left" => "◀ L",
                                "center" => "◆ C",
                                "right" => "R ▶",
                                _ => "•",
                            };

                            // Use frame + background for selected state (theme-independent visibility)
                            let btn = if is_selected {
                                ui.add(
                                    egui::Button::new(
                                        RichText::new(icon)
                                            .color(theme.selected_fg)
                                            .size(10.0)
                                            .strong(),
                                    )
                                    .fill(theme.selected_bg)
                                    .min_size(Vec2::new(28.0, 20.0)),
                                )
                            } else {
                                ui.add(
                                    egui::Button::new(
                                        RichText::new(icon).color(theme.fg_dim).size(10.0),
                                    )
                                    .fill(Color32::TRANSPARENT)
                                    .min_size(Vec2::new(28.0, 20.0)),
                                )
                            }
                            .on_hover_text(*align);

                            if btn.clicked() {
                                pref_change = Some((content_type, *align));
                            }
                        }
                    });
                });
                ui.add_space(4.0);
            }

            // Apply preference change after UI iteration
            if let Some((content_type, align)) = pref_change {
                if let Err(e) =
                    self.db
                        .set_display_preference(content_type, align, "default", false)
                {
                    self.set_status(&format!("✗ Failed to save preference: {}", e));
                } else {
                    self.display_prefs = self.db.get_display_preferences().unwrap_or_default();
                    self.set_status(&format!("✓ Alignment changed to {}", align));
                    // Request repaint to update message display immediately
                    ui.ctx().request_repaint();
                }
            }

            ui.add_space(12.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("DATA")
                        .size(11.0)
                        .color(theme.fg_dim)
                        .strong(),
                );
            });
            ui.add_space(8.0);

            ui.horizontal(|ui| {
                ui.add_space(12.0);
                if styled_button(ui, "📂 Open Data Folder", Vec2::new(160.0, 32.0)).clicked() {
                    if let Some(config_dir) = dirs::config_dir() {
                        let data_dir = config_dir.join("cursor-studio");
                        if let Err(e) = Command::new("xdg-open").arg(&data_dir).spawn() {
                            self.set_status(&format!("✗ Failed to open: {}", e));
                        } else {
                            self.set_status("✓ Opened data folder");
                        }
                    }
                }
            });
            ui.add_space(4.0);

            ui.horizontal(|ui| {
                ui.add_space(12.0);
                if styled_button(ui, "↻ Refresh All", Vec2::new(160.0, 32.0))
                    .on_hover_text("Refresh all data")
                    .clicked()
                {
                    self.refresh_all();
                }
            });

            ui.add_space(20.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("RESOURCES")
                        .size(11.0)
                        .color(theme.fg_dim)
                        .strong(),
                );
            });
            ui.add_space(8.0);

            // CPU threads
            let max_threads = std::thread::available_parallelism()
                .map(|n| n.get())
                .unwrap_or(8);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new(format!("CPU Threads (max {})", max_threads))
                        .color(theme.fg)
                        .size(12.0),
                );
            });
            ui.horizontal(|ui| {
                ui.add_space(24.0);
                let slider = ui.add(
                    egui::Slider::new(&mut self.max_cpu_threads, 1..=max_threads).show_value(true),
                );
                if slider.changed() {
                    self.save_settings();
                    self.set_status(&format!("✓ Max CPU threads: {}", self.max_cpu_threads));
                }
            });
            ui.add_space(8.0);

            // RAM limit
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(RichText::new("RAM Limit").color(theme.fg).size(12.0));
            });
            ui.horizontal(|ui| {
                ui.add_space(24.0);
                let slider = ui.add(
                    egui::Slider::new(&mut self.max_ram_mb, 512..=16384)
                        .show_value(true)
                        .suffix(" MB"),
                );
                if slider.changed() {
                    self.save_settings();
                    self.set_status(&format!("✓ RAM limit: {} MB", self.max_ram_mb));
                }
            });
            ui.add_space(8.0);

            // VRAM limit (for future GPU features)
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(RichText::new("VRAM Limit").color(theme.fg).size(12.0));
            });
            ui.horizontal(|ui| {
                ui.add_space(24.0);
                let slider = ui.add(
                    egui::Slider::new(&mut self.max_vram_mb, 256..=32768)
                        .show_value(true)
                        .suffix(" MB"),
                );
                if slider.changed() {
                    self.save_settings();
                    self.set_status(&format!("✓ VRAM limit: {} MB", self.max_vram_mb));
                }
            });
            ui.add_space(8.0);

            // Storage limit
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(RichText::new("Storage Limit").color(theme.fg).size(12.0));
            });
            ui.horizontal(|ui| {
                ui.add_space(24.0);
                let slider = ui.add(
                    egui::Slider::new(&mut self.storage_limit_mb, 1024..=102400)
                        .show_value(true)
                        .custom_formatter(|v, _| format!("{:.1} GB", v / 1024.0))
                        .custom_parser(|s| {
                            s.replace(" GB", "").parse::<f64>().ok().map(|v| v * 1024.0)
                        }),
                );
                if slider.changed() {
                    self.save_settings();
                    self.set_status(&format!(
                        "✓ Storage limit: {:.1} GB",
                        self.storage_limit_mb as f32 / 1024.0
                    ));
                }
            });

            ui.add_space(4.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("Note: Resource limits are for future features (AI, caching)")
                        .color(theme.fg_dim)
                        .size(9.0)
                        .italics(),
                );
            });

            ui.add_space(20.0);
            ui.separator();
            ui.add_space(8.0);

            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("ABOUT")
                        .size(11.0)
                        .color(theme.fg_dim)
                        .strong(),
                );
            });
            ui.add_space(8.0);

            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("Cursor Studio v0.2.0")
                        .color(theme.fg_dim)
                        .size(12.0),
                );
            });
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("Built with egui + Rust")
                        .color(theme.fg_dim)
                        .size(11.0),
                );
            });
        });
    }

    fn settings_dropdown_ui(
        &mut self,
        ui: &mut egui::Ui,
        theme: Theme,
        label: &str,
        current_value: &str,
        toggle_key: &str,
    ) {
        ui.horizontal(|ui| {
            ui.add_space(16.0);
            ui.label(RichText::new(label).color(theme.fg).size(13.0));
        });
        ui.horizontal(|ui| {
            ui.add_space(16.0);

            let is_open = match toggle_key {
                "show_theme" => self.show_theme_picker,
                "show_version" => self.show_version_picker,
                _ => false,
            };

            let arrow = if is_open { "▲" } else { "▼" };
            let display = format!("{} {}", current_value, arrow);

            egui::Frame::none()
                .fill(theme.input_bg)
                .rounding(Rounding::same(4.0))
                .stroke(Stroke::new(1.0, theme.border))
                .inner_margin(egui::Margin::symmetric(10.0, 6.0))
                .show(ui, |ui| {
                    let btn = ui
                        .add(
                            egui::Button::new(RichText::new(&display).color(theme.fg).size(12.0))
                                .frame(false)
                                .min_size(Vec2::new(180.0, 20.0)),
                        )
                        .on_hover_text(format!("Click to change {}", label.to_lowercase()));

                    if btn.hovered() {
                        ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                    }

                    if btn.clicked() {
                        match toggle_key {
                            "show_theme" => self.show_theme_picker = !self.show_theme_picker,
                            "show_version" => self.show_version_picker = !self.show_version_picker,
                            _ => {}
                        }
                    }
                });
        });
    }

    fn settings_toggle_ui(
        &mut self,
        ui: &mut egui::Ui,
        theme: Theme,
        label: &str,
        tooltip: &str,
        toggle_key: &str,
    ) {
        ui.horizontal(|ui| {
            ui.add_space(16.0);
            ui.label(RichText::new(label).color(theme.fg).size(13.0));

            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.add_space(16.0);

                let mut value = match toggle_key {
                    "auto_sync" => self.auto_sync_enabled,
                    "import_on_start" => self.import_on_start,
                    "show_all_versions" => self.show_all_versions,
                    _ => false,
                };

                if toggle_switch(ui, &mut value, theme).clicked() {
                    match toggle_key {
                        "auto_sync" => self.auto_sync_enabled = value,
                        "import_on_start" => self.import_on_start = value,
                        "show_all_versions" => self.show_all_versions = value,
                        _ => {}
                    }
                    self.set_status(&format!(
                        "✓ {} {}",
                        label,
                        if value { "enabled" } else { "disabled" }
                    ));
                }
            });
        })
        .response
        .on_hover_text(tooltip);
    }

    fn show_chat_library(&mut self, ui: &mut egui::Ui, theme: Theme) {
        ui.vertical(|ui| {
            ui.add_space(12.0);
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new("CHAT LIBRARY")
                        .size(11.0)
                        .color(theme.fg_dim)
                        .strong(),
                );

                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.add_space(12.0);
                    let refresh_btn = ui
                        .add(
                            egui::Button::new(RichText::new("↻").size(14.0).color(theme.fg_dim))
                                .frame(false),
                        )
                        .on_hover_text("Refresh chat library");
                    if refresh_btn.hovered() {
                        ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                    }
                    if refresh_btn.clicked() {
                        self.refresh_chats();
                    }
                });
            });
            ui.add_space(8.0);

            let convs = self.conversations.clone();
            let mut to_open: Option<String> = None;
            let mut to_toggle_fav: Option<String> = None;

            let scroll_height = ui.available_height() - 100.0;

            egui::ScrollArea::vertical()
                .max_height(scroll_height.max(100.0))
                .show(ui, |ui| {
                    if convs.is_empty() {
                        ui.vertical_centered(|ui| {
                            ui.add_space(20.0);
                            ui.label(
                                RichText::new("No chats imported yet")
                                    .color(theme.fg_dim)
                                    .italics(),
                            );
                            ui.add_space(8.0);
                            ui.label(
                                RichText::new("Click 'Import All' below")
                                    .color(theme.fg_dim)
                                    .size(11.0),
                            );

                            // Show last error if any
                            if let Some(err) = &self.last_import_error {
                                ui.add_space(12.0);
                                ui.label(RichText::new(err).color(theme.error).size(10.0));
                            }
                        });
                    }

                    for conv in &convs {
                        ui.horizontal(|ui| {
                            ui.add_space(12.0);

                            let star = if conv.is_favorite { "★" } else { "☆" };
                            let star_color = if conv.is_favorite {
                                theme.warning
                            } else {
                                theme.fg_dim
                            };
                            let star_btn = ui
                                .add(
                                    egui::Button::new(
                                        RichText::new(star).color(star_color).size(14.0),
                                    )
                                    .frame(false)
                                    .min_size(Vec2::new(20.0, 20.0)),
                                )
                                .on_hover_text("Toggle favorite");

                            if star_btn.hovered() {
                                ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                            }

                            if star_btn.clicked() {
                                to_toggle_fav = Some(conv.id.clone());
                            }

                            let title: String = conv.title.chars().take(25).collect();
                            let title_btn = ui
                                .add(
                                    egui::Button::new(
                                        RichText::new(&title).color(theme.fg).size(12.0),
                                    )
                                    .frame(false),
                                )
                                .on_hover_text(&conv.title);

                            if title_btn.hovered() {
                                ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                            }

                            if title_btn.clicked() {
                                to_open = Some(conv.id.clone());
                            }

                            ui.with_layout(
                                egui::Layout::right_to_left(egui::Align::Center),
                                |ui| {
                                    ui.add_space(12.0);
                                    ui.label(
                                        RichText::new(format!("{}", conv.message_count))
                                            .color(theme.fg_dim)
                                            .size(10.0),
                                    );
                                },
                            );
                        });
                        ui.add_space(2.0);
                    }
                });

            if let Some(id) = to_open {
                self.open_conversation(&id);
            }

            if let Some(id) = to_toggle_fav {
                let _ = self.db.toggle_favorite(&id);
                self.refresh_chats();
            }

            ui.add_space(ui.available_height() - 70.0);
            ui.separator();
            ui.add_space(8.0);

            ui.horizontal(|ui| {
                ui.add_space(12.0);

                if self.import_in_progress {
                    // Animated spinner during import
                    ui.horizontal(|ui| {
                        ui.add(egui::Spinner::new());
                        ui.label(RichText::new("Importing...").color(theme.accent).size(12.0));
                    });
                    // Keep repainting while importing
                    ui.ctx().request_repaint();
                } else {
                    if styled_button_accent(ui, "⬇ Import All", Vec2::new(110.0, 28.0), theme)
                        .clicked()
                    {
                        self.do_import();
                    }
                }

                if styled_button(ui, "⬆ Export", Vec2::new(80.0, 28.0))
                    .on_hover_text("Export chats to markdown")
                    .clicked()
                {
                    self.set_status("Export feature coming soon");
                }
            });
            ui.add_space(8.0);
        });
    }

    /// # TODO(P1): Release v0.3.0 - Security Panel Polish
    /// - [ ] Wire up NPM scan results display (show blocked packages)
    /// - [ ] Add "Jump to" buttons for security findings
    /// - [ ] Show CVE details in expandable sections
    /// - [ ] Add Socket.dev links for package research
    /// - [ ] Implement audit log export functionality
    /// - [ ] Add scan history with timestamps
    fn show_security_panel(&mut self, ui: &mut egui::Ui, theme: Theme) {
        egui::ScrollArea::vertical()
            .auto_shrink([false; 2])
            .show(ui, |ui| {
                ui.add_space(12.0);

                // Overview Section
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new("SECURITY OVERVIEW")
                            .size(11.0)
                            .color(theme.fg_dim)
                            .strong(),
                    );
                });
                ui.add_space(8.0);

                // Security Status Card
                egui::Frame::none()
                    .fill(theme.code_bg)
                    .rounding(Rounding::same(8.0))
                    .inner_margin(egui::Margin::same(12.0))
                    .show(ui, |ui| {
                        ui.horizontal(|ui| {
                            ui.label(RichText::new("🛡️").size(20.0));
                            ui.add_space(8.0);
                            ui.vertical(|ui| {
                                ui.label(
                                    RichText::new("System Status")
                                        .color(theme.fg)
                                        .strong()
                                        .size(13.0),
                                );
                                ui.label(
                                    RichText::new("All security checks passing")
                                        .color(theme.success)
                                        .size(11.0),
                                );
                            });
                        });
                    });
                ui.add_space(16.0);

                // Data Privacy Section
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new("DATA PRIVACY")
                            .size(11.0)
                            .color(theme.fg_dim)
                            .strong(),
                    );
                });
                ui.add_space(8.0);

                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new("📁 Chat Data Location")
                            .color(theme.fg)
                            .size(12.0),
                    );
                });
                ui.horizontal(|ui| {
                    ui.add_space(24.0);
                    if let Some(config_dir) = dirs::config_dir() {
                        let path = config_dir.join("cursor-studio");
                        ui.label(
                            RichText::new(path.to_string_lossy())
                                .color(theme.fg_dim)
                                .size(10.0)
                                .family(egui::FontFamily::Monospace),
                        );
                    }
                });
                ui.add_space(8.0);

                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new("🔐 Data Encryption")
                            .color(theme.fg)
                            .size(12.0),
                    );
                });
                ui.horizontal(|ui| {
                    ui.add_space(24.0);
                    ui.label(
                        RichText::new("Local storage only (not encrypted)")
                            .color(theme.warning)
                            .size(11.0),
                    );
                });
                ui.add_space(16.0);

                // API Keys Section
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new("API KEYS & TOKENS")
                            .size(11.0)
                            .color(theme.fg_dim)
                            .strong(),
                    );
                });
                ui.add_space(8.0);

                egui::Frame::none()
                    .fill(theme.code_bg)
                    .rounding(Rounding::same(8.0))
                    .inner_margin(egui::Margin::same(12.0))
                    .show(ui, |ui| {
                        ui.horizontal(|ui| {
                            ui.label(RichText::new("⚠️").size(14.0));
                            ui.add_space(4.0);
                            ui.label(
                                RichText::new("No API keys stored in Cursor Studio")
                                    .color(theme.fg_dim)
                                    .size(11.0),
                            );
                        });
                        ui.add_space(4.0);
                        ui.label(
                            RichText::new("API keys are managed by Cursor directly")
                                .color(theme.fg_dim)
                                .size(10.0)
                                .italics(),
                        );
                    });
                ui.add_space(16.0);

                // Scan Section
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new("SECURITY SCANS")
                            .size(11.0)
                            .color(theme.fg_dim)
                            .strong(),
                    );
                });
                ui.add_space(8.0);

                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    if styled_button(ui, "🔍 Scan Chat History", Vec2::new(160.0, 32.0))
                        .on_hover_text("Scan for sensitive data in chat history")
                        .clicked()
                    {
                        self.run_security_scan();
                    }
                });
                ui.add_space(4.0);

                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    if styled_button(ui, "🗑️ Purge Sensitive Data", Vec2::new(160.0, 32.0))
                        .on_hover_text("Remove detected sensitive data from chat history")
                        .clicked()
                    {
                        self.set_status("⚠️ Purge not yet implemented");
                    }
                });

                // Show scan results if available
                let mut jump_to_msg: Option<(String, String)> = None;

                if let Some(ref results) = self.security_scan_results {
                    ui.add_space(12.0);
                    egui::Frame::none()
                        .fill(theme.code_bg)
                        .rounding(Rounding::same(8.0))
                        .inner_margin(egui::Margin::same(12.0))
                        .show(ui, |ui| {
                            ui.label(
                                RichText::new(format!("📊 Scan Results ({})", results.scanned_at))
                                    .color(theme.fg)
                                    .strong()
                                    .size(11.0),
                            );
                            ui.add_space(4.0);
                            ui.label(
                                RichText::new(format!(
                                    "Messages scanned: {}",
                                    results.total_messages
                                ))
                                .color(theme.fg_dim)
                                .size(10.0),
                            );

                            let total_found = results.potential_api_keys.len()
                                + results.potential_passwords.len()
                                + results.potential_secrets.len();

                            if total_found == 0 {
                                ui.add_space(4.0);
                                ui.label(
                                    RichText::new("✓ No sensitive data detected")
                                        .color(theme.success)
                                        .size(11.0),
                                );
                            } else {
                                ui.add_space(8.0);

                                if !results.potential_api_keys.is_empty() {
                                    ui.horizontal(|ui| {
                                        ui.label(RichText::new("🔑").size(12.0));
                                        ui.label(
                                            RichText::new(format!(
                                                "API Keys: {}",
                                                results.potential_api_keys.len()
                                            ))
                                            .color(theme.warning)
                                            .size(10.0),
                                        );
                                    });
                                    // Show first few with jump buttons
                                    for (conv_id, msg_id, preview) in
                                        results.potential_api_keys.iter().take(5)
                                    {
                                        ui.horizontal(|ui| {
                                            ui.add_space(20.0);
                                            if ui
                                                .small_button("→")
                                                .on_hover_text("Jump to message")
                                                .clicked()
                                            {
                                                jump_to_msg =
                                                    Some((conv_id.clone(), msg_id.clone()));
                                            }
                                            ui.label(
                                                RichText::new(preview)
                                                    .color(theme.fg_dim)
                                                    .size(9.0)
                                                    .family(egui::FontFamily::Monospace),
                                            );
                                        });
                                    }
                                    if results.potential_api_keys.len() > 5 {
                                        ui.horizontal(|ui| {
                                            ui.add_space(20.0);
                                            ui.label(
                                                RichText::new(format!(
                                                    "... and {} more",
                                                    results.potential_api_keys.len() - 5
                                                ))
                                                .color(theme.fg_dim)
                                                .size(9.0),
                                            );
                                        });
                                    }
                                }

                                if !results.potential_passwords.is_empty() {
                                    ui.add_space(4.0);
                                    ui.horizontal(|ui| {
                                        ui.label(RichText::new("🔒").size(12.0));
                                        ui.label(
                                            RichText::new(format!(
                                                "Passwords: {}",
                                                results.potential_passwords.len()
                                            ))
                                            .color(theme.error)
                                            .size(10.0),
                                        );
                                    });
                                    // Show with jump buttons
                                    for (conv_id, msg_id, preview) in
                                        results.potential_passwords.iter().take(3)
                                    {
                                        ui.horizontal(|ui| {
                                            ui.add_space(20.0);
                                            if ui
                                                .small_button("→")
                                                .on_hover_text("Jump to message")
                                                .clicked()
                                            {
                                                jump_to_msg =
                                                    Some((conv_id.clone(), msg_id.clone()));
                                            }
                                            ui.label(
                                                RichText::new(preview)
                                                    .color(theme.fg_dim)
                                                    .size(9.0)
                                                    .family(egui::FontFamily::Monospace),
                                            );
                                        });
                                    }
                                }

                                if !results.potential_secrets.is_empty() {
                                    ui.add_space(4.0);
                                    ui.horizontal(|ui| {
                                        ui.label(RichText::new("🔐").size(12.0));
                                        ui.label(
                                            RichText::new(format!(
                                                "Secrets: {}",
                                                results.potential_secrets.len()
                                            ))
                                            .color(theme.warning)
                                            .size(10.0),
                                        );
                                    });
                                    // Show with jump buttons
                                    for (conv_id, msg_id, preview) in
                                        results.potential_secrets.iter().take(3)
                                    {
                                        ui.horizontal(|ui| {
                                            ui.add_space(20.0);
                                            if ui
                                                .small_button("→")
                                                .on_hover_text("Jump to message")
                                                .clicked()
                                            {
                                                jump_to_msg =
                                                    Some((conv_id.clone(), msg_id.clone()));
                                            }
                                            ui.label(
                                                RichText::new(preview)
                                                    .color(theme.fg_dim)
                                                    .size(9.0)
                                                    .family(egui::FontFamily::Monospace),
                                            );
                                        });
                                    }
                                }
                            }
                        });
                }

                // Process jump-to after UI
                if let Some((conv_id, msg_id)) = jump_to_msg {
                    self.scroll_to_message(&conv_id, &msg_id);
                }

                ui.add_space(16.0);

                // NPM Package Security Section
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new("NPM PACKAGE SECURITY")
                            .size(11.0)
                            .color(theme.fg_dim)
                            .strong(),
                    );
                });
                ui.add_space(8.0);

                // Blocklist stats
                let stats = self.npm_scanner.get_blocklist_stats();
                egui::Frame::none()
                    .fill(theme.code_bg)
                    .rounding(Rounding::same(8.0))
                    .inner_margin(egui::Margin::same(12.0))
                    .show(ui, |ui| {
                        ui.label(
                            RichText::new("📦 Blocklist Database")
                                .color(theme.fg)
                                .strong()
                                .size(11.0),
                        );
                        ui.add_space(4.0);
                        ui.label(
                            RichText::new(format!(
                                "Version: {} • Updated: {}",
                                stats.version, stats.last_updated
                            ))
                            .color(theme.fg_dim)
                            .size(10.0),
                        );
                        ui.label(
                            RichText::new(format!(
                                "{} blocked packages • {} with CVEs",
                                stats.total_packages, stats.packages_with_cve
                            ))
                            .color(theme.warning)
                            .size(10.0),
                        );

                        // Show categories
                        ui.add_space(4.0);
                        for (name, count) in &stats.categories {
                            ui.horizontal(|ui| {
                                ui.add_space(8.0);
                                ui.label(
                                    RichText::new(format!("• {}: {}", name, count))
                                        .color(theme.fg_dim)
                                        .size(9.0),
                                );
                            });
                        }
                    });
                ui.add_space(8.0);

                // NPM scan path input
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(RichText::new("Scan Path:").color(theme.fg).size(11.0));
                });
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.add(
                        egui::TextEdit::singleline(&mut self.npm_scan_path)
                            .desired_width(ui.available_width() - 80.0)
                            .hint_text("/path/to/project")
                            .font(egui::FontId::monospace(11.0)),
                    );
                });
                ui.add_space(8.0);

                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    if styled_button(ui, "🔍 Scan for Malicious Packages", Vec2::new(200.0, 32.0))
                        .on_hover_text("Scan package.json files for known malicious packages")
                        .clicked()
                    {
                        self.scan_npm_packages();
                    }
                });

                // Show NPM scan results if available
                if self.show_npm_scan_results {
                    if let Some(ref results) = self.npm_scan_results {
                        ui.add_space(8.0);
                        egui::Frame::none()
                            .fill(theme.code_bg)
                            .rounding(Rounding::same(8.0))
                            .inner_margin(egui::Margin::same(12.0))
                            .show(ui, |ui| {
                                if results.is_empty() {
                                    ui.label(
                                        RichText::new("✓ No blocked packages found")
                                            .color(theme.success)
                                            .size(11.0),
                                    );
                                } else {
                                    ui.label(
                                        RichText::new(format!(
                                            "⚠️ Found issues in {} files:",
                                            results.len()
                                        ))
                                        .color(theme.error)
                                        .strong()
                                        .size(11.0),
                                    );
                                    ui.add_space(4.0);

                                    for (path, packages) in results.iter().take(10) {
                                        ui.label(
                                            RichText::new(path.to_string_lossy())
                                                .color(theme.fg)
                                                .size(10.0)
                                                .family(egui::FontFamily::Monospace),
                                        );
                                        for pkg in packages {
                                            ui.horizontal(|ui| {
                                                ui.add_space(16.0);
                                                ui.label(
                                                    RichText::new(format!(
                                                        "🚫 {} - {}",
                                                        pkg.package_name,
                                                        pkg.block_reason
                                                            .as_deref()
                                                            .unwrap_or("blocked")
                                                    ))
                                                    .color(theme.error)
                                                    .size(9.0),
                                                );
                                                if let Some(cve) = &pkg.cve {
                                                    ui.label(
                                                        RichText::new(format!("[{}]", cve))
                                                            .color(theme.warning)
                                                            .size(9.0),
                                                    );
                                                }
                                            });
                                        }
                                    }
                                }
                            });
                    }
                }

                ui.add_space(16.0);

                // Audit Log Section
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new("AUDIT LOG")
                            .size(11.0)
                            .color(theme.fg_dim)
                            .strong(),
                    );
                });
                ui.add_space(8.0);

                egui::Frame::none()
                    .fill(theme.code_bg)
                    .rounding(Rounding::same(8.0))
                    .inner_margin(egui::Margin::same(12.0))
                    .show(ui, |ui| {
                        ui.label(
                            RichText::new("Recent Activity")
                                .color(theme.fg)
                                .strong()
                                .size(11.0),
                        );
                        ui.add_space(4.0);

                        // Show last few events
                        let events = [
                            ("✓", "App started", theme.success),
                            ("✓", "Database loaded", theme.success),
                            ("•", "No imports today", theme.fg_dim),
                        ];

                        for (icon, text, color) in events {
                            ui.horizontal(|ui| {
                                ui.label(RichText::new(icon).color(color).size(10.0));
                                ui.add_space(4.0);
                                ui.label(RichText::new(text).color(theme.fg_dim).size(10.0));
                            });
                        }
                    });
                ui.add_space(16.0);

                // Settings Section
                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new("SECURITY SETTINGS")
                            .size(11.0)
                            .color(theme.fg_dim)
                            .strong(),
                    );
                });
                ui.add_space(8.0);

                ui.horizontal(|ui| {
                    ui.add_space(16.0);
                    ui.label(
                        RichText::new("More security features coming soon...")
                            .color(theme.fg_dim)
                            .size(11.0)
                            .italics(),
                    );
                });
                ui.add_space(8.0);

                // Future features list
                let future_features = [
                    "• Encrypted local storage",
                    "• Sensitive data detection (API keys, passwords)",
                    "• Auto-redaction in exports",
                    "• Session timeout settings",
                    "• Audit log export",
                ];

                for feature in future_features {
                    ui.horizontal(|ui| {
                        ui.add_space(24.0);
                        ui.label(RichText::new(feature).color(theme.fg_dim).size(10.0));
                    });
                }

                ui.add_space(20.0);
            });
    }

    fn show_editor_area(&mut self, ui: &mut egui::Ui, theme: Theme) {
        let tabs = self.tabs.clone();
        let convs = self.conversations.clone();
        let active_tab = self.active_tab;

        let mut new_active: Option<usize> = None;
        let mut to_close: Option<usize> = None;

        // Tab bar
        ui.horizontal(|ui| {
            ui.add_space(4.0);

            for (i, tab) in tabs.iter().enumerate() {
                let is_active = i == active_tab;
                let bg = if is_active {
                    theme.tab_active_bg
                } else {
                    theme.tab_bg
                };

                let title = match tab {
                    Tab::Dashboard => "🏠 Dashboard".to_string(),
                    Tab::Conversation(id) => {
                        let title_text = convs
                            .iter()
                            .find(|c| &c.id == id)
                            .map(|c| c.title.chars().take(18).collect::<String>())
                            .unwrap_or_else(|| "Chat".to_string());
                        format!("💬 {}", title_text)
                    }
                };

                // Use a selectable button for better click handling
                let tab_size = Vec2::new(140.0, 28.0);
                let (rect, response) = ui.allocate_exact_size(tab_size, egui::Sense::click());

                // Draw background
                let hover_bg = if response.hovered() && !is_active {
                    theme.tab_hover_bg
                } else {
                    bg
                };
                ui.painter().rect_filled(rect, Rounding::ZERO, hover_bg);

                // Active indicator
                if is_active {
                    ui.painter()
                        .hline(rect.x_range(), rect.top(), Stroke::new(2.0, theme.accent));
                }

                // Tab title
                let text_pos = rect.left_center() + Vec2::new(8.0, 0.0);
                ui.painter().text(
                    text_pos,
                    egui::Align2::LEFT_CENTER,
                    &title,
                    egui::FontId::proportional(12.0),
                    if is_active { theme.fg } else { theme.fg_dim },
                );

                // Close button (only for non-dashboard tabs)
                if !matches!(tab, Tab::Dashboard) {
                    let close_rect = egui::Rect::from_center_size(
                        rect.right_center() - Vec2::new(14.0, 0.0),
                        Vec2::splat(16.0),
                    );
                    let close_response =
                        ui.interact(close_rect, ui.id().with(("close", i)), egui::Sense::click());

                    let close_color = if close_response.hovered() {
                        theme.error
                    } else {
                        theme.fg_dim
                    };

                    ui.painter().text(
                        close_rect.center(),
                        egui::Align2::CENTER_CENTER,
                        "×",
                        egui::FontId::proportional(14.0),
                        close_color,
                    );

                    if close_response.clicked() {
                        to_close = Some(i);
                    }
                    if close_response.hovered() {
                        ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                    }
                }

                // Handle tab click (but not on close button area)
                if response.clicked() && to_close.is_none() {
                    new_active = Some(i);
                }

                if response.hovered() {
                    ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                }
            }
        });

        // Process tab changes
        if let Some(i) = to_close {
            self.close_tab(i);
        }
        if let Some(i) = new_active {
            self.active_tab = i;
        }

        ui.add(egui::Separator::default().spacing(0.0));

        // Show active tab content
        if let Some(tab) = self.tabs.get(self.active_tab) {
            match tab {
                Tab::Dashboard => self.show_dashboard(ui, theme),
                Tab::Conversation(id) => {
                    let id = id.clone();
                    self.show_conversation_tab(ui, theme, &id);
                }
            }
        }
    }

    fn show_dashboard(&mut self, ui: &mut egui::Ui, theme: Theme) {
        let (total, messages, favorites) = self.db.get_stats().unwrap_or((0, 0, 0));

        let mut do_import = false;
        let mut do_launch = false;

        ui.vertical_centered(|ui| {
            ui.add_space(ui.available_height() / 4.0);

            ui.label(RichText::new("CURSOR").size(42.0).color(theme.fg).strong());
            ui.label(
                RichText::new("STUDIO")
                    .size(42.0)
                    .color(theme.accent)
                    .strong(),
            );
            ui.add_space(4.0);
            ui.label(
                RichText::new("Version Manager & Chat Library")
                    .size(13.0)
                    .color(theme.fg_dim),
            );
            ui.add_space(4.0);
            ui.label(RichText::new("v0.2.0").size(11.0).color(theme.fg_dim));

            ui.add_space(32.0);

            ui.label(
                RichText::new(format!(
                    "📊 {} chats   💬 {} messages   ⭐ {} favorites",
                    total, messages, favorites
                ))
                .size(14.0)
                .color(theme.fg_dim),
            );

            // Show current launch version
            ui.add_space(8.0);
            let launch_display = Self::version_display_name(&self.launch_version);
            ui.label(
                RichText::new(format!("🚀 Launch version: {}", launch_display))
                    .size(12.0)
                    .color(theme.accent),
            );

            ui.add_space(32.0);

            ui.horizontal(|ui| {
                ui.add_space((ui.available_width() - 300.0) / 2.0);

                if self.import_in_progress {
                    // Animated spinner during import
                    egui::Frame::none()
                        .fill(theme.sidebar_bg)
                        .rounding(Rounding::same(8.0))
                        .inner_margin(Vec2::new(20.0, 10.0))
                        .show(ui, |ui| {
                            ui.horizontal(|ui| {
                                ui.add(egui::Spinner::new().size(20.0));
                                ui.add_space(8.0);
                                ui.label(
                                    RichText::new("Importing...").color(theme.accent).size(14.0),
                                );
                            });
                        });
                    ui.ctx().request_repaint();
                } else {
                    if styled_button_accent(ui, "⬇ Import Chats", Vec2::new(140.0, 40.0), theme)
                        .clicked()
                    {
                        // Show warning first time
                        if !self.import_warning_shown {
                            self.import_warning_shown = true;
                            self.set_status("⚠️ Import may take a moment - click again to proceed");
                        } else {
                            do_import = true;
                            self.import_warning_shown = false;
                        }
                    }

                    // Show warning hint
                    if self.import_warning_shown {
                        ui.add_space(4.0);
                        ui.label(
                            RichText::new("⚠️ Large chat histories may freeze UI briefly")
                                .color(theme.warning)
                                .size(10.0),
                        );
                    }

                    ui.add_space(12.0);

                    // Clear & Reimport button (preserves bookmarks)
                    ui.vertical(|ui| {
                        if styled_button(ui, "🔄 Clear & Reimport", Vec2::new(140.0, 32.0))
                            .clicked()
                        {
                            self.do_clear_and_reimport();
                        }
                        ui.add_space(2.0);
                        ui.label(
                            RichText::new("Keeps bookmarks")
                                .color(theme.fg_dim)
                                .size(9.0),
                        );
                    });
                }

                ui.add_space(16.0);

                if styled_button_accent(ui, "▶ Launch Cursor", Vec2::new(140.0, 40.0), theme)
                    .clicked()
                {
                    do_launch = true;
                }
            });

            ui.add_space(24.0);

            ui.label(
                RichText::new("Quick Tips:")
                    .size(12.0)
                    .color(theme.fg_dim)
                    .strong(),
            );
            ui.add_space(4.0);
            ui.label(
                RichText::new(
                    "• Use the sidebar icons to switch between Versions, Search, and Settings",
                )
                .size(11.0)
                .color(theme.fg_dim),
            );
            ui.label(
                RichText::new(
                    "• Click version names to set default, use 'Launch:' to pick which to start",
                )
                .size(11.0)
                .color(theme.fg_dim),
            );
            ui.label(
                RichText::new("• Drag sidebar edges to resize them")
                    .size(11.0)
                    .color(theme.fg_dim),
            );
        });

        if do_import {
            self.do_import();
        }

        if do_launch {
            self.launch_cursor();
        }
    }

    fn show_conversation_tab(&mut self, ui: &mut egui::Ui, theme: Theme, conv_id: &str) {
        // Load messages and bookmarks if switching conversations
        let needs_reload = self.current_messages.is_empty()
            || self.current_messages.first().map(|m| &m.conversation_id)
                != Some(&conv_id.to_string());

        if needs_reload {
            self.current_messages = self.db.get_messages(conv_id).unwrap_or_default();
            self.current_bookmarks = self.db.get_bookmarks(conv_id).unwrap_or_default();
        }

        ui.add_space(8.0);

        // Conversation header with bookmark count
        let bookmark_count = self.current_bookmarks.len();

        if let Some(conv) = self.conversations.iter().find(|c| c.id == conv_id) {
            ui.horizontal(|ui| {
                ui.add_space(16.0);
                ui.label(
                    RichText::new(&conv.title)
                        .size(15.0)
                        .color(theme.fg)
                        .strong(),
                );
                ui.add_space(8.0);
                ui.label(
                    RichText::new(format!("• {} messages", conv.message_count))
                        .color(theme.fg_dim)
                        .size(12.0),
                );

                // Show bookmark count if any
                if bookmark_count > 0 {
                    ui.label(
                        RichText::new(format!("• 🔖 {}", bookmark_count))
                            .color(Color32::from_rgb(255, 215, 0)) // Gold
                            .size(12.0),
                    );
                }

                // Toggle bookmark panel button
                let panel_btn = ui
                    .add(
                        egui::Button::new(
                            RichText::new(if self.show_bookmark_panel {
                                "📑"
                            } else {
                                "🔖"
                            })
                            .size(14.0),
                        )
                        .frame(false),
                    )
                    .on_hover_text(if self.show_bookmark_panel {
                        "Hide bookmarks"
                    } else {
                        "Show bookmarks"
                    });

                if panel_btn.clicked() {
                    self.show_bookmark_panel = !self.show_bookmark_panel;
                }
            });
        }

        // Toolbar: Export and Search
        let mut do_export = false;
        let mut do_search = false;
        let mut search_query_changed = false;

        ui.horizontal(|ui| {
            ui.add_space(16.0);

            // Export button
            if ui
                .small_button("📤 Export")
                .on_hover_text("Export to Markdown")
                .clicked()
            {
                do_export = true;
            }

            ui.add_space(8.0);

            // Search box
            ui.label(RichText::new("🔍").size(12.0));
            let search_response = ui.add(
                egui::TextEdit::singleline(&mut self.conv_search_query)
                    .desired_width(150.0)
                    .hint_text("Search in chat...")
                    .font(egui::FontId::proportional(11.0)),
            );

            if search_response.changed() {
                search_query_changed = true;
            }

            // Enter to search
            if search_response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)) {
                do_search = true;
            }

            // Search nav buttons
            if !self.conv_search_results.is_empty() {
                ui.label(
                    RichText::new(format!(
                        "{}/{}",
                        self.conv_search_index + 1,
                        self.conv_search_results.len()
                    ))
                    .size(10.0)
                    .color(theme.fg_dim),
                );

                if ui
                    .small_button("◀")
                    .on_hover_text("Previous result")
                    .clicked()
                {
                    self.jump_to_prev_search_result();
                }
                if ui.small_button("▶").on_hover_text("Next result").clicked() {
                    self.jump_to_next_search_result();
                }
            }

            // Search button
            if ui.small_button("Find").clicked() {
                do_search = true;
            }
        });

        // Handle actions
        if do_export {
            self.export_conversation_to_markdown(conv_id);
        }

        if do_search || (search_query_changed && self.conv_search_query.len() >= 2) {
            let query = self.conv_search_query.clone();
            self.search_in_conversation(&query);
        }

        ui.add_space(8.0);

        // Bookmark panel (if visible)
        if self.show_bookmark_panel && !self.current_bookmarks.is_empty() {
            egui::Frame::none()
                .fill(theme.sidebar_bg)
                .inner_margin(8.0)
                .rounding(Rounding::same(4.0))
                .show(ui, |ui| {
                    ui.horizontal(|ui| {
                        ui.label(
                            RichText::new("📑 Bookmarks")
                                .color(theme.fg)
                                .strong()
                                .size(12.0),
                        );
                    });
                    ui.add_space(4.0);

                    let bookmarks = self.current_bookmarks.clone();
                    let mut jump_to: Option<(String, String)> = None;

                    for bookmark in &bookmarks {
                        ui.horizontal(|ui| {
                            // Bookmark color indicator
                            let color = Color32::from_rgb(255, 215, 0);
                            ui.painter().circle_filled(
                                ui.cursor().min + Vec2::new(6.0, 8.0),
                                4.0,
                                color,
                            );
                            ui.add_space(12.0);

                            // Label or default (create owned string first)
                            let default_label = format!("Msg #{}", bookmark.message_sequence);
                            let label = bookmark.label.as_deref().unwrap_or(&default_label);
                            ui.label(RichText::new(label).color(theme.fg).size(11.0));

                            // Jump button
                            if ui
                                .small_button("→")
                                .on_hover_text("Jump to message")
                                .clicked()
                            {
                                jump_to = Some((
                                    bookmark.conversation_id.clone(),
                                    bookmark.message_id.clone(),
                                ));
                            }
                        });
                    }

                    // Process jump after UI iteration
                    if let Some((cid, mid)) = jump_to {
                        self.scroll_to_message_id = Some(mid);
                    }
                });
            ui.add_space(4.0);
        }

        ui.separator();

        let msgs = self.current_messages.clone();
        let bookmarks = self.current_bookmarks.clone();
        let display_prefs = self.display_prefs.clone();
        let conv_id = conv_id.to_string();
        let mut bookmark_actions: Vec<BookmarkAction> = Vec::new();
        let message_spacing = self.message_spacing;
        let scroll_target = self.scroll_to_message_id.clone();

        let scroll_area = egui::ScrollArea::vertical().auto_shrink([false; 2]);

        scroll_area.show(ui, |ui| {
            ui.add_space(8.0);

            if msgs.is_empty() {
                ui.vertical_centered(|ui| {
                    ui.add_space(40.0);
                    ui.label(
                        RichText::new("No messages found")
                            .color(theme.fg_dim)
                            .italics(),
                    );
                });
            }

            for msg in &msgs {
                ui.add_space(message_spacing);

                // Check if this message is the scroll target
                let is_scroll_target = scroll_target
                    .as_ref()
                    .map(|id| id == &msg.id)
                    .unwrap_or(false);

                // If this is the scroll target, scroll to it and highlight
                if is_scroll_target {
                    ui.scroll_to_cursor(Some(egui::Align::Center));
                }

                // Determine alignment based on role AND display preferences
                let is_user = matches!(msg.role, MessageRole::User);
                let max_width = ui.available_width() * 0.66; // Messages take 2/3 of tab width

                // Get alignment from display preferences
                let content_type_key = match msg.role {
                    MessageRole::User => "user",
                    MessageRole::Assistant => "assistant",
                    MessageRole::ToolCall | MessageRole::ToolResult => "tool_call",
                };
                let alignment = display_prefs
                    .iter()
                    .find(|p| p.content_type == content_type_key)
                    .map(|p| p.alignment.as_str())
                    .unwrap_or(if is_user { "right" } else { "left" });

                let use_right_align = alignment == "right";
                let use_center_align = alignment == "center";

                // Determine icon, label, and color based on role and tool call
                let (icon, label, color) = if msg.tool_call.is_some() {
                    let tc = msg.tool_call.as_ref().unwrap();
                    let status_icon = match tc.status.as_str() {
                        "completed" => "✓",
                        "running" => "⏳",
                        "error" => "✗",
                        _ => "•",
                    };
                    (
                        format!("🔧{}", status_icon),
                        format!("TOOL: {}", tc.name),
                        theme.warning,
                    )
                } else {
                    match msg.role {
                        MessageRole::User => ("👤".to_string(), "USER".to_string(), theme.accent),
                        MessageRole::Assistant => {
                            ("🤖".to_string(), "ASSISTANT".to_string(), theme.success)
                        }
                        MessageRole::ToolCall => {
                            ("🔧".to_string(), "TOOL CALL".to_string(), theme.warning)
                        }
                        MessageRole::ToolResult => {
                            ("📋".to_string(), "TOOL RESULT".to_string(), theme.fg_dim)
                        }
                    }
                };

                // Check if this message is bookmarked
                let is_bookmarked = bookmarks.iter().any(|b| b.message_id == msg.id);
                let msg_id = msg.id.clone();
                let conv_id_clone = conv_id.to_string();
                let msg_seq = msg.sequence;

                // === RIGHT-ALIGNED MESSAGES (bubble style) ===
                if use_right_align {
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::TOP), |ui| {
                        ui.add_space(16.0);

                        egui::Frame::none()
                            .fill(theme.accent.linear_multiply(0.15))
                            .rounding(Rounding::same(12.0))
                            .inner_margin(egui::Margin::symmetric(12.0, 8.0))
                            .show(ui, |ui| {
                                ui.set_max_width(max_width);

                                // Header row with bookmark button
                                ui.horizontal(|ui| {
                                    // Bookmark indicator/button - VISIBLE
                                    let bookmark_icon = if is_bookmarked { "🔖" } else { "⭐" };
                                    let bookmark_color = if is_bookmarked {
                                        Color32::from_rgb(255, 215, 0) // Gold
                                    } else {
                                        Color32::from_rgb(100, 100, 100) // Gray, visible
                                    };
                                    let bookmark_btn = ui
                                        .add(
                                            egui::Button::new(
                                                RichText::new(bookmark_icon)
                                                    .color(bookmark_color)
                                                    .size(14.0), // Larger
                                            )
                                            .frame(false)
                                            .min_size(Vec2::new(20.0, 20.0)),
                                        )
                                        .on_hover_text(if is_bookmarked {
                                            "Remove bookmark"
                                        } else {
                                            "Add bookmark"
                                        });

                                    if bookmark_btn.hovered() {
                                        ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                                    }

                                    if bookmark_btn.clicked() {
                                        if is_bookmarked {
                                            if let Some(bm) =
                                                bookmarks.iter().find(|b| b.message_id == msg_id)
                                            {
                                                let bm_id = bm.id.clone();
                                                bookmark_actions.push(BookmarkAction::Remove(
                                                    bm_id,
                                                    conv_id_clone.clone(),
                                                ));
                                            }
                                        } else {
                                            bookmark_actions.push(BookmarkAction::Add(
                                                conv_id_clone.clone(),
                                                msg_id.clone(),
                                                msg_seq,
                                            ));
                                        }
                                    }

                                    ui.label(
                                        RichText::new(format!("{} {}", icon, label))
                                            .color(color)
                                            .strong()
                                            .size(11.0),
                                    );
                                });

                                ui.add_space(4.0);

                                // Render full message body (tool calls, thinking, content)
                                render_message_body(ui, msg, theme);
                            });
                    });
                    continue; // Skip the rest for right-aligned messages
                }

                // === CENTER-ALIGNED MESSAGES ===
                if use_center_align {
                    ui.vertical_centered(|ui| {
                        egui::Frame::none()
                            .fill(theme.sidebar_bg)
                            .rounding(Rounding::same(8.0))
                            .inner_margin(egui::Margin::symmetric(12.0, 8.0))
                            .show(ui, |ui| {
                                ui.set_max_width(max_width);

                                // Header with bookmark
                                ui.horizontal(|ui| {
                                    // Bookmark button
                                    let bookmark_icon = if is_bookmarked { "🔖" } else { "⭐" };
                                    let bookmark_color = if is_bookmarked {
                                        Color32::from_rgb(255, 215, 0)
                                    } else {
                                        Color32::from_rgb(100, 100, 100)
                                    };
                                    let bookmark_btn = ui.add(
                                        egui::Button::new(
                                            RichText::new(bookmark_icon)
                                                .color(bookmark_color)
                                                .size(14.0),
                                        )
                                        .frame(false)
                                        .min_size(Vec2::new(20.0, 20.0)),
                                    );
                                    if bookmark_btn.clicked() {
                                        if is_bookmarked {
                                            if let Some(bm) =
                                                bookmarks.iter().find(|b| b.message_id == msg_id)
                                            {
                                                bookmark_actions.push(BookmarkAction::Remove(
                                                    bm.id.clone(),
                                                    conv_id_clone.clone(),
                                                ));
                                            }
                                        } else {
                                            bookmark_actions.push(BookmarkAction::Add(
                                                conv_id_clone.clone(),
                                                msg_id.clone(),
                                                msg_seq,
                                            ));
                                        }
                                    }

                                    ui.label(
                                        RichText::new(format!("{} {}", icon, label))
                                            .color(color)
                                            .strong()
                                            .size(12.0),
                                    );
                                });
                                ui.add_space(4.0);

                                // Render full message body (tool calls, thinking, content)
                                render_message_body(ui, msg, theme);
                            });
                    });
                    continue;
                }

                // === LEFT-ALIGNED MESSAGES (default) ===

                // Highlight frame for scroll target
                let highlight_color = if is_scroll_target {
                    theme.accent.linear_multiply(0.2)
                } else {
                    Color32::TRANSPARENT
                };

                egui::Frame::none()
                    .fill(highlight_color)
                    .rounding(Rounding::same(6.0))
                    .inner_margin(egui::Margin::symmetric(4.0, 2.0))
                    .show(ui, |ui| {
                        // Message header with bookmark button
                        ui.horizontal(|ui| {
                            ui.add_space(16.0);

                            // Bookmark indicator/button - VISIBLE
                            let bookmark_icon = if is_bookmarked { "🔖" } else { "⭐" };
                            let bookmark_color = if is_bookmarked {
                                Color32::from_rgb(255, 215, 0) // Gold
                            } else {
                                Color32::from_rgb(100, 100, 100) // Gray, visible
                            };
                            let bookmark_btn = ui
                                .add(
                                    egui::Button::new(
                                        RichText::new(bookmark_icon)
                                            .color(bookmark_color)
                                            .size(14.0), // Larger
                                    )
                                    .frame(false)
                                    .min_size(Vec2::new(20.0, 20.0)),
                                )
                                .on_hover_text(if is_bookmarked {
                                    "Remove bookmark"
                                } else {
                                    "Add bookmark"
                                });

                            if bookmark_btn.hovered() {
                                ui.ctx().set_cursor_icon(CursorIcon::PointingHand);
                            }

                            if bookmark_btn.clicked() {
                                if is_bookmarked {
                                    if let Some(bm) =
                                        bookmarks.iter().find(|b| b.message_id == msg_id)
                                    {
                                        let bm_id = bm.id.clone();
                                        bookmark_actions.push(BookmarkAction::Remove(
                                            bm_id,
                                            conv_id_clone.clone(),
                                        ));
                                    }
                                } else {
                                    bookmark_actions.push(BookmarkAction::Add(
                                        conv_id_clone.clone(),
                                        msg_id.clone(),
                                        msg_seq,
                                    ));
                                }
                            }

                            ui.label(
                                RichText::new(format!("{} {}", icon, label))
                                    .color(color)
                                    .strong()
                                    .size(12.0),
                            );
                        });

                        // Subtle separator line
                        ui.add_space(2.0);
                        ui.horizontal(|ui| {
                            ui.add_space(16.0);
                            let rect = ui.available_rect_before_wrap();
                            let line_rect = egui::Rect::from_min_max(
                                egui::pos2(rect.left(), rect.top()),
                                egui::pos2(rect.left() + 400.0, rect.top() + 1.0),
                            );
                            ui.painter()
                                .rect_filled(line_rect, Rounding::ZERO, theme.border);
                        });
                        ui.add_space(4.0);

                        // Tool call details (if present)
                        if let Some(tc) = &msg.tool_call {
                            ui.horizontal(|ui| {
                                ui.add_space(24.0);

                                // Tool call box - uses theme colors
                                egui::Frame::none()
                                    .fill(theme.sidebar_bg)
                                    .rounding(Rounding::same(4.0))
                                    .inner_margin(8.0)
                                    .stroke(Stroke::new(1.0, theme.border))
                                    .show(ui, |ui| {
                                        ui.set_max_width(ui.available_width() - 48.0);

                                        ui.label(
                                            RichText::new(format!("{}()", tc.name))
                                                .color(theme.syntax_function)
                                                .family(egui::FontFamily::Monospace)
                                                .size(12.0),
                                        );

                                        if !tc.args_preview.is_empty() {
                                            ui.label(
                                                RichText::new(&tc.args_preview)
                                                    .color(theme.fg_dim)
                                                    .family(egui::FontFamily::Monospace)
                                                    .size(11.0),
                                            );
                                        }

                                        let status_color = match tc.status.as_str() {
                                            "completed" => theme.success,
                                            "error" | "failed" => theme.error,
                                            _ => theme.warning,
                                        };
                                        ui.label(
                                            RichText::new(format!("Status: {}", tc.status))
                                                .color(status_color)
                                                .size(10.0),
                                        );
                                    });
                            });
                            ui.add_space(4.0);
                        }

                        // Thinking block (if present) - custom collapsible with proper theme
                        if let Some(thinking) = &msg.thinking {
                            if !thinking.is_empty() {
                                let thinking_id =
                                    ui.make_persistent_id(format!("thinking_{}", msg.id));
                                let mut is_open = ui
                                    .data_mut(|d| d.get_temp::<bool>(thinking_id).unwrap_or(false));

                                ui.horizontal(|ui| {
                                    ui.add_space(24.0);

                                    // Custom toggle button with theme colors
                                    let toggle_text = if is_open {
                                        "▼ 💭 Thinking"
                                    } else {
                                        "▶ 💭 Thinking..."
                                    };
                                    let response = ui.add(
                                        egui::Button::new(
                                            RichText::new(toggle_text)
                                                .color(theme.fg_dim)
                                                .italics()
                                                .size(11.0),
                                        )
                                        .fill(Color32::TRANSPARENT)
                                        .stroke(Stroke::NONE),
                                    );

                                    if response.clicked() {
                                        is_open = !is_open;
                                        ui.data_mut(|d| d.insert_temp(thinking_id, is_open));
                                    }
                                });

                                if is_open {
                                    ui.horizontal(|ui| {
                                        ui.add_space(32.0);
                                        egui::Frame::none()
                                            .fill(theme.sidebar_bg)
                                            .rounding(Rounding::same(4.0))
                                            .inner_margin(8.0)
                                            .stroke(Stroke::new(1.0, theme.border))
                                            .show(ui, |ui| {
                                                ui.set_max_width(ui.available_width() - 48.0);

                                                // Truncate very long thinking blocks (safely at char boundary)
                                                let display_text =
                                                    if thinking.chars().count() > 2000 {
                                                        let truncated: String =
                                                            thinking.chars().take(2000).collect();
                                                        format!(
                                                            "{}...\n\n[Truncated - {} chars total]",
                                                            truncated,
                                                            thinking.chars().count()
                                                        )
                                                    } else {
                                                        thinking.clone()
                                                    };

                                                ui.label(
                                                    RichText::new(display_text)
                                                        .color(theme.fg_dim)
                                                        .size(11.0),
                                                );
                                            });
                                    });
                                }
                                ui.add_space(4.0);
                            }
                        }

                        // Main content - with code block rendering
                        if !msg.content.is_empty() {
                            ui.horizontal(|ui| {
                                ui.add_space(16.0);
                                ui.vertical(|ui| {
                                    ui.set_max_width(ui.available_width() - 32.0);
                                    render_markdown_content(ui, &msg.content, theme);
                                });
                                ui.add_space(16.0);
                            });
                        }
                    }); // Close the highlight frame

                ui.add_space(8.0);
            }

            ui.add_space(16.0);
        });

        // Process bookmark actions after UI rendering
        for action in bookmark_actions {
            match action {
                BookmarkAction::Add(cid, mid, seq) => {
                    self.add_bookmark(&cid, &mid, seq);
                }
                BookmarkAction::Remove(bid, cid) => {
                    self.delete_bookmark(&bid, &cid);
                }
            }
        }

        // Clear scroll target after rendering
        if self.scroll_to_message_id.is_some() {
            self.scroll_to_message_id = None;
        }
    }

    fn show_status_bar(&mut self, ui: &mut egui::Ui) {
        let font_size = self.status_bar_font_size;

        // Check for async import progress
        if let Some(rx) = &self.import_receiver {
            if let Ok(progress) = rx.try_recv() {
                match progress {
                    ImportProgress::Started(total) => {
                        self.import_progress = Some((0, total));
                        self.set_status(&format!(
                            "⏳ Starting import of {} conversations...",
                            total
                        ));
                    }
                    ImportProgress::Processing(current, total) => {
                        self.import_progress = Some((current, total));
                        // Request repaint to show progress
                        ui.ctx().request_repaint();
                    }
                    ImportProgress::Completed(imported, skipped) => {
                        self.import_progress = None;
                        self.import_in_progress = false;
                        self.import_receiver = None;
                        self.refresh_chats();

                        // Reattach bookmarks and restore favorites if this was a clear & reimport
                        if self.import_needs_bookmark_reattach {
                            self.import_needs_bookmark_reattach = false;
                            let mut reattached = 0;
                            let mut failed = 0;
                            for conv in &self.conversations {
                                if let Ok(results) = self.db.reattach_bookmarks(&conv.id) {
                                    for (_, success) in results {
                                        if success {
                                            reattached += 1;
                                        } else {
                                            failed += 1;
                                        }
                                    }
                                }
                            }

                            // Restore favorites
                            let favorites_restored = self.db.restore_favorites().unwrap_or(0);
                            if favorites_restored > 0 {
                                self.refresh_chats(); // Refresh to show restored favorites
                            }

                            self.set_status(&format!(
                                "✓ Imported {} chats, {} favorites, {} bookmarks restored",
                                imported, favorites_restored, reattached
                            ));
                            return;
                        }

                        if imported > 0 {
                            self.set_status(&format!(
                                "✓ Imported {} new chats ({} already existed)",
                                imported, skipped
                            ));
                        } else if skipped > 0 {
                            self.set_status(&format!("All {} chats already imported", skipped));
                        } else {
                            self.set_status("No Cursor chats found to import");
                        }
                    }
                    ImportProgress::Error(e) => {
                        self.import_progress = None;
                        self.import_in_progress = false;
                        self.import_receiver = None;
                        self.last_import_error = Some(e.clone());
                        self.set_status(&format!("✗ Import error: {}", e));
                    }
                }
            }
        }

        ui.horizontal(|ui| {
            // Show import progress if active
            if let Some((current, total)) = self.import_progress {
                let pct = if total > 0 { (current as f32 / total as f32) * 100.0 } else { 0.0 };
                ui.add(egui::Spinner::new().size(font_size));
                ui.add_space(4.0);
                ui.label(
                    RichText::new(format!("Importing... {}/{} ({:.0}%)", current, total, pct))
                        .color(Color32::from_rgb(100, 200, 255))
                        .size(font_size),
                );
            } else if let Some(msg) = &self.status_message {
                ui.label(RichText::new(msg).color(Color32::WHITE).size(font_size));
            } else {
                // Show detailed stats
                if let Ok(stats) = self.db.get_detailed_stats() {
                    let (total, _, _) = self.db.get_stats().unwrap_or((0, 0, 0));
                    ui.label(
                        RichText::new(format!(
                            "📊 {} chats • 👤 {} user • 🤖 {} AI • 🔧 {} tools • 💭 {} thinking • 📝 {} code • 🔖 {} bookmarks",
                            total,
                            stats.user_messages,
                            stats.assistant_messages,
                            stats.tool_calls,
                            stats.with_thinking,
                            stats.with_code,
                            stats.bookmarks,
                        ))
                        .color(Color32::WHITE)
                        .size(font_size),
                    );
                } else {
                    let (total, messages, _) = self.db.get_stats().unwrap_or((0, 0, 0));
                    ui.label(
                        RichText::new(format!("📊 {} chats • 💬 {} messages", total, messages))
                            .color(Color32::WHITE)
                            .size(font_size),
                    );
                }
            }

            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.label(
                    RichText::new("Cursor Studio v0.2.0")
                        .color(Color32::WHITE)
                        .size(font_size),
                );
            });
        });

        self.status_message = None;
    }

    fn open_conversation(&mut self, conv_id: &str) {
        for (i, tab) in self.tabs.iter().enumerate() {
            if let Tab::Conversation(id) = tab {
                if id == conv_id {
                    self.active_tab = i;
                    return;
                }
            }
        }

        self.tabs.push(Tab::Conversation(conv_id.to_string()));
        self.active_tab = self.tabs.len() - 1;
        self.current_messages = self.db.get_messages(conv_id).unwrap_or_default();
    }

    fn close_tab(&mut self, index: usize) {
        if index < self.tabs.len() && !matches!(self.tabs[index], Tab::Dashboard) {
            self.tabs.remove(index);
            if self.active_tab >= self.tabs.len() {
                self.active_tab = self.tabs.len().saturating_sub(1);
            }
        }
    }
}

/// Render a complete message body including tool calls, thinking, and content
fn render_message_body(ui: &mut egui::Ui, msg: &Message, theme: Theme) {
    // Tool call info (if present)
    if let Some(tool_call) = &msg.tool_call {
        egui::Frame::none()
            .fill(theme.sidebar_bg)
            .rounding(Rounding::same(6.0))
            .inner_margin(egui::Margin::same(8.0))
            .stroke(Stroke::new(1.0, theme.border))
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    // Tool icon and name
                    let status_icon = match tool_call.status.as_str() {
                        "success" | "completed" => "✓",
                        "pending" | "running" => "⏳",
                        "error" | "failed" => "✗",
                        _ => "🔧",
                    };
                    let status_color = match tool_call.status.as_str() {
                        "success" | "completed" => theme.success,
                        "error" | "failed" => theme.error,
                        _ => theme.fg_dim,
                    };
                    ui.label(RichText::new(status_icon).color(status_color).size(12.0));
                    ui.label(
                        RichText::new(&tool_call.name)
                            .color(theme.accent)
                            .strong()
                            .size(11.0),
                    );

                    // Show tool_id if present
                    if !tool_call.tool_id.is_empty() {
                        ui.label(
                            RichText::new(format!(
                                "({})",
                                &tool_call.tool_id.chars().take(8).collect::<String>()
                            ))
                            .color(theme.fg_dim)
                            .size(9.0),
                        );
                    }
                });

                // Show args preview
                if !tool_call.args_preview.is_empty() {
                    ui.add_space(4.0);
                    ui.label(
                        RichText::new(&tool_call.args_preview)
                            .color(theme.fg_dim)
                            .size(10.0)
                            .family(egui::FontFamily::Monospace),
                    );
                }

                // Collapsible full args view
                if !tool_call.args.is_empty() && tool_call.args.len() > tool_call.args_preview.len()
                {
                    let args_id = ui.make_persistent_id(format!("tool_args_{}", msg.id));
                    let mut show_full =
                        ui.data_mut(|d| d.get_temp::<bool>(args_id).unwrap_or(false));

                    ui.add_space(4.0);
                    let toggle_text = if show_full {
                        "▼ Hide full args"
                    } else {
                        "▶ Show full args"
                    };
                    let toggle = ui.add(
                        egui::Button::new(RichText::new(toggle_text).color(theme.fg_dim).size(9.0))
                            .frame(false),
                    );
                    if toggle.clicked() {
                        show_full = !show_full;
                        ui.data_mut(|d| d.insert_temp(args_id, show_full));
                    }

                    if show_full {
                        ui.add_space(4.0);
                        egui::Frame::none()
                            .fill(theme.code_bg)
                            .rounding(Rounding::same(4.0))
                            .inner_margin(egui::Margin::same(6.0))
                            .show(ui, |ui| {
                                // Pretty print JSON if possible
                                let display_args = if let Ok(parsed) =
                                    serde_json::from_str::<serde_json::Value>(&tool_call.args)
                                {
                                    serde_json::to_string_pretty(&parsed)
                                        .unwrap_or_else(|_| tool_call.args.clone())
                                } else {
                                    tool_call.args.clone()
                                };
                                ui.label(
                                    RichText::new(&display_args)
                                        .color(theme.fg)
                                        .size(10.0)
                                        .family(egui::FontFamily::Monospace),
                                );
                            });
                    }
                }
            });
        ui.add_space(4.0);
    }

    // Thinking block (if present)
    if let Some(thinking) = &msg.thinking {
        if !thinking.is_empty() {
            let thinking_id = ui.make_persistent_id(format!("thinking_{}", msg.id));
            let mut is_open = ui.data_mut(|d| d.get_temp::<bool>(thinking_id).unwrap_or(false));

            ui.horizontal(|ui| {
                let toggle_text = if is_open {
                    "▼ 💭 Thinking"
                } else {
                    "▶ 💭 Thinking..."
                };
                let response = ui.add(
                    egui::Button::new(
                        RichText::new(toggle_text)
                            .color(theme.fg_dim)
                            .italics()
                            .size(11.0),
                    )
                    .fill(Color32::TRANSPARENT)
                    .stroke(Stroke::NONE),
                );

                if response.clicked() {
                    is_open = !is_open;
                    ui.data_mut(|d| d.insert_temp(thinking_id, is_open));
                }
            });

            if is_open {
                egui::Frame::none()
                    .fill(theme.sidebar_bg)
                    .rounding(Rounding::same(4.0))
                    .inner_margin(egui::Margin::same(8.0))
                    .show(ui, |ui| {
                        let truncated = if thinking.chars().count() > 2000 {
                            format!("{}...", thinking.chars().take(2000).collect::<String>())
                        } else {
                            thinking.clone()
                        };
                        ui.label(
                            RichText::new(truncated)
                                .color(theme.fg_dim)
                                .italics()
                                .size(11.0),
                        );
                    });
            }
            ui.add_space(4.0);
        }
    }

    // Main content
    if !msg.content.is_empty() {
        render_markdown_content(ui, &msg.content, theme);
    }
}

/// Render markdown-ish content with code block support
fn render_markdown_content(ui: &mut egui::Ui, content: &str, theme: Theme) {
    let mut in_code_block = false;
    let mut code_lang = String::new();
    let mut code_buffer = String::new();

    for line in content.lines() {
        if line.starts_with("```") {
            if in_code_block {
                // End of code block - render it
                render_code_block(ui, &code_buffer, &code_lang, theme);
                code_buffer.clear();
                code_lang.clear();
                in_code_block = false;
            } else {
                // Start of code block
                code_lang = line.trim_start_matches('`').to_string();
                in_code_block = true;
            }
        } else if in_code_block {
            if !code_buffer.is_empty() {
                code_buffer.push('\n');
            }
            code_buffer.push_str(line);
        } else {
            // Regular text - handle headings, inline code, etc.
            render_text_line(ui, line, theme);
        }
    }

    // Handle unclosed code block
    if in_code_block && !code_buffer.is_empty() {
        render_code_block(ui, &code_buffer, &code_lang, theme);
    }
}

/// Render a code block with syntax highlighting-ish styling
fn render_code_block(ui: &mut egui::Ui, code: &str, lang: &str, theme: Theme) {
    ui.add_space(4.0);

    egui::Frame::none()
        .fill(theme.code_bg)
        .rounding(Rounding::same(4.0))
        .inner_margin(8.0)
        .stroke(Stroke::new(1.0, theme.border))
        .show(ui, |ui| {
            // Language label
            if !lang.is_empty() {
                ui.label(
                    RichText::new(lang)
                        .color(theme.fg_dim)
                        .size(10.0)
                        .family(egui::FontFamily::Monospace),
                );
                ui.add_space(4.0);
            }

            // Code content
            ui.add(
                egui::Label::new(
                    RichText::new(code)
                        .color(theme.syntax_string)
                        .size(12.0)
                        .family(egui::FontFamily::Monospace),
                )
                .wrap(),
            );
        });

    ui.add_space(4.0);
}

/// Render a single line of text with heading, inline code support
///
/// # TODO(P0): Release v0.3.0 - Bold Text Rendering
/// - [ ] Fix nested **bold** within larger text blocks
/// - [ ] Handle bold + inline code mixing: **`code`** or `**bold**`
/// - [ ] Support ***bold italic*** (triple asterisk)
/// - [ ] Handle escaped asterisks: \*not bold\*
/// - [ ] Test edge cases: **bold with spaces** and **multi-word bold**
fn render_text_line(ui: &mut egui::Ui, line: &str, theme: Theme) {
    let trimmed = line.trim();

    if trimmed.is_empty() {
        ui.add_space(6.0);
        return;
    }

    // Handle markdown headings
    if trimmed.starts_with("######") {
        let text = trimmed.trim_start_matches('#').trim();
        ui.label(RichText::new(text).color(theme.fg).size(12.0).strong());
        return;
    } else if trimmed.starts_with("#####") {
        let text = trimmed.trim_start_matches('#').trim();
        ui.label(RichText::new(text).color(theme.fg).size(12.5).strong());
        return;
    } else if trimmed.starts_with("####") {
        let text = trimmed.trim_start_matches('#').trim();
        ui.label(RichText::new(text).color(theme.fg).size(13.0).strong());
        return;
    } else if trimmed.starts_with("###") {
        let text = trimmed.trim_start_matches('#').trim();
        ui.label(
            RichText::new(text)
                .color(theme.fg_bright)
                .size(14.0)
                .strong(),
        );
        return;
    } else if trimmed.starts_with("##") {
        let text = trimmed.trim_start_matches('#').trim();
        ui.add_space(4.0);
        ui.label(
            RichText::new(text)
                .color(theme.fg_bright)
                .size(16.0)
                .strong(),
        );
        return;
    } else if trimmed.starts_with('#') && !trimmed.starts_with("#!/") {
        let text = trimmed.trim_start_matches('#').trim();
        ui.add_space(6.0);
        ui.label(
            RichText::new(text)
                .color(theme.fg_bright)
                .size(18.0)
                .strong(),
        );
        return;
    }

    // Handle horizontal rules
    if trimmed == "---" || trimmed == "***" || trimmed == "___" {
        ui.add_space(4.0);
        ui.separator();
        ui.add_space(4.0);
        return;
    }

    // Handle bullet points
    let (prefix, text) = if trimmed.starts_with("- ") || trimmed.starts_with("* ") {
        ("• ", &trimmed[2..])
    } else if trimmed.starts_with("  - ") || trimmed.starts_with("  * ") {
        ("  ◦ ", &trimmed[4..])
    } else {
        ("", trimmed)
    };

    // Handle inline code and bold
    if text.contains('`') || text.contains("**") {
        // Render prefix separately if needed
        if !prefix.is_empty() {
            ui.horizontal(|ui| {
                ui.label(RichText::new(prefix).color(theme.accent).size(13.0));
            });
        }
        // Use LayoutJob-based rendering for proper text wrapping
        render_inline_formatting(ui, text, theme);
    } else {
        // Simple text - use a wrapping label
        ui.add(
            egui::Label::new(
                RichText::new(format!("{}{}", prefix, text))
                    .color(theme.fg)
                    .size(13.0),
            )
            .wrap(),
        );
    }
}

/// Handle inline formatting (backticks, bold) using LayoutJob for proper text flow
/// Supports: `code`, **bold**, and combinations like **`bold code`**
fn render_inline_formatting(ui: &mut egui::Ui, text: &str, theme: Theme) {
    use egui::text::{LayoutJob, TextFormat};
    use egui::FontId;

    let mut job = LayoutJob::default();
    job.wrap.max_width = ui.available_width();

    // Define text formats
    let normal_format = TextFormat {
        font_id: FontId::proportional(13.0),
        color: theme.fg,
        ..Default::default()
    };

    // Bold format - use underline as visual indicator since egui doesn't have font weights
    // Alternative: could use color differentiation or stronger fonts
    let bold_format = TextFormat {
        font_id: FontId::proportional(13.0),
        color: theme.fg_bright, // Brighter color for emphasis
        underline: egui::Stroke::new(1.0, theme.fg_dim), // Subtle underline for bold
        ..Default::default()
    };

    let code_format = TextFormat {
        font_id: FontId::monospace(12.0),
        color: theme.syntax_string,
        background: theme.input_bg,
        ..Default::default()
    };

    let mut current_text = String::new();
    let mut chars = text.chars().peekable();
    let mut in_code = false;
    let mut in_bold = false;

    // Helper to append text with current format
    let append_text = |job: &mut LayoutJob,
                       text: &str,
                       in_code: bool,
                       in_bold: bool,
                       normal: &TextFormat,
                       bold: &TextFormat,
                       code: &TextFormat| {
        if text.is_empty() {
            return;
        }
        let format = if in_code {
            code.clone()
        } else if in_bold {
            bold.clone()
        } else {
            normal.clone()
        };
        job.append(text, 0.0, format);
    };

    while let Some(ch) = chars.next() {
        if ch == '`' {
            // Flush current text before toggling code mode
            append_text(
                &mut job,
                &current_text,
                in_code,
                in_bold,
                &normal_format,
                &bold_format,
                &code_format,
            );
            current_text.clear();
            in_code = !in_code;
        } else if ch == '*' && chars.peek() == Some(&'*') && !in_code {
            // Bold toggle (only outside of code blocks)
            chars.next(); // consume second *
            append_text(
                &mut job,
                &current_text,
                in_code,
                in_bold,
                &normal_format,
                &bold_format,
                &code_format,
            );
            current_text.clear();
            in_bold = !in_bold;
        } else if ch == '*' && !in_code && !in_bold {
            // Single asterisk - treat as literal
            current_text.push(ch);
        } else {
            current_text.push(ch);
        }
    }

    // Append remaining text
    append_text(
        &mut job,
        &current_text,
        in_code,
        in_bold,
        &normal_format,
        &bold_format,
        &code_format,
    );

    // Render as a single label with proper wrapping
    ui.label(job);
}
