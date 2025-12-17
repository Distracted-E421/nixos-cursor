//! Modes panel UI - comprehensive custom mode management
//!
//! Features:
//! - Create/edit/delete custom modes
//! - Tool access configuration (allowlist/blocklist)
//! - Model selection with overrides
//! - System prompt editing
//! - Context injection settings
//! - Quick mode switching
//! - Profile management (unlimited profiles)

use egui::{self, Color32, CursorIcon, RichText, TextWrapMode};
use super::{CustomMode, ModeRegistry, ModeConfig, ToolAccess, ModelConfig, ContextConfig};
use super::config::AccessMode;
use super::injection::{ModeInjector, InjectionTarget};
use std::path::PathBuf;
use std::collections::HashSet;

// Re-export Theme from parent for UI styling
use crate::theme::Theme;

/// Events emitted by the modes panel
#[derive(Debug, Clone)]
pub enum ModesPanelEvent {
    /// Mode was switched
    ModeActivated(String),
    /// Mode was created/updated
    ModeUpdated(String),
    /// Mode was deleted
    ModeDeleted(String),
    /// Mode was injected to Cursor
    ModeInjected { mode: String, target: InjectionTarget },
    /// Quick swap to vanilla
    VanillaSwap { from_mode: String },
}

/// UI state for the modes panel
pub struct ModesPanel {
    /// Mode registry
    pub registry: ModeRegistry,
    
    /// Currently selected mode for editing
    selected_mode: Option<String>,
    
    /// Editor state
    editor: ModeEditor,
    
    /// Config
    config: ModeConfig,
    
    /// Project root for injection
    project_root: PathBuf,
    
    /// Show mode creation dialog
    show_create_dialog: bool,
    
    /// Show delete confirmation
    show_delete_confirm: Option<String>,
    
    /// New mode name input
    new_mode_name: String,
    
    /// Status message
    status_message: Option<(String, bool)>, // (message, is_error)
    
    /// Events to emit
    events: Vec<ModesPanelEvent>,
}

/// Editor state for a single mode
#[derive(Default)]
struct ModeEditor {
    name: String,
    description: String,
    icon: String,
    system_prompt: String,
    
    // Tool access
    tool_mode: AccessMode,
    tool_list_input: String,
    allowed_tools: HashSet<String>,
    blocked_tools: HashSet<String>,
    
    // Model config
    model_primary: String,
    model_fallback: String,
    temperature: String,
    max_tokens: String,
    
    // Context config
    include_environment: bool,
    include_git: bool,
    include_project: bool,
    include_files_input: String,
    custom_injection: String,
    
    // State
    is_dirty: bool,
}

impl ModesPanel {
    /// Create a new modes panel
    pub fn new(project_root: PathBuf) -> Self {
        let modes_dir = dirs::config_dir()
            .unwrap_or_else(|| PathBuf::from(".config"))
            .join("cursor-studio")
            .join("modes");
        
        let registry = ModeRegistry::load(modes_dir);
        
        Self {
            registry,
            selected_mode: None,
            editor: ModeEditor::default(),
            config: ModeConfig::default(),
            project_root,
            show_create_dialog: false,
            show_delete_confirm: None,
            new_mode_name: String::new(),
            status_message: None,
            events: Vec::new(),
        }
    }
    
    /// Take pending events
    pub fn take_events(&mut self) -> Vec<ModesPanelEvent> {
        std::mem::take(&mut self.events)
    }
    
    /// Main UI render function
    pub fn show(&mut self, ui: &mut egui::Ui, theme: &Theme) {
        egui::ScrollArea::vertical()
            .auto_shrink([false; 2])
            .show(ui, |ui| {
                ui.add_space(12.0);
                
                // Header
                self.show_header(ui, theme);
                
                ui.add_space(16.0);
                
                // Quick mode switcher
                self.show_mode_switcher(ui, theme);
                
                ui.add_space(16.0);
                
                // Mode list
                self.show_mode_list(ui, theme);
                
                ui.add_space(16.0);
                
                // Mode editor (if one is selected)
                if self.selected_mode.is_some() {
                    self.show_mode_editor(ui, theme);
                }
                
                ui.add_space(16.0);
                
                // Injection controls
                self.show_injection_controls(ui, theme);
                
                // Status message
                if let Some((msg, is_error)) = &self.status_message {
                    ui.add_space(8.0);
                    let color = if *is_error { Color32::from_rgb(255, 100, 100) } else { theme.accent };
                    ui.label(RichText::new(msg).color(color).size(12.0));
                }
            });
        
        // Dialogs
        self.show_create_dialog(ui, theme);
        self.show_delete_dialog(ui, theme);
    }
    
    fn show_header(&mut self, ui: &mut egui::Ui, theme: &Theme) {
        ui.horizontal(|ui| {
            ui.label(RichText::new("🎭").size(20.0));
            ui.label(RichText::new("MODES").size(14.0).strong().color(theme.fg));
            
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.add(egui::Button::new("➕ New").small()).clicked() {
                    self.show_create_dialog = true;
                    self.new_mode_name.clear();
                }
            });
        });
        
        ui.add_space(4.0);
        ui.label(
            RichText::new("Custom modes for tool control, prompts & models")
                .size(11.0)
                .color(theme.fg_dim),
        );
    }
    
    fn show_mode_switcher(&mut self, ui: &mut egui::Ui, theme: &Theme) {
        // Collect mode info before the UI to avoid borrow issues
        let mode_entries: Vec<(String, String)> = self.registry.modes.iter()
            .map(|(name, mode)| (name.clone(), mode.icon.clone()))
            .collect();
        
        let active_name = self.registry.active_mode.clone().unwrap_or_else(|| "None".to_string());
        let active_icon = self.registry.active()
            .map(|m| m.icon.clone())
            .unwrap_or_else(|| "❓".to_string());
        
        ui.group(|ui| {
            ui.horizontal(|ui| {
                ui.label(RichText::new("Active Mode:").size(12.0).color(theme.fg_dim));
                
                let mut new_active: Option<String> = None;
                let mut go_vanilla = false;
                
                egui::ComboBox::from_id_salt("active_mode_selector")
                    .selected_text(format!("{} {}", active_icon, active_name))
                    .show_ui(ui, |ui| {
                        for (name, icon) in &mode_entries {
                            let display = format!("{} {}", icon, name);
                            let is_selected = self.registry.active_mode.as_ref() == Some(name);
                            if ui.selectable_label(is_selected, display).clicked() {
                                new_active = Some(name.clone());
                            }
                        }
                        ui.separator();
                        if ui.selectable_label(self.registry.active_mode.is_none(), "❌ No Mode (Vanilla)").clicked() {
                            go_vanilla = true;
                        }
                    });
                
                // Apply changes after ComboBox
                if let Some(name) = new_active {
                    self.registry.active_mode = Some(name.clone());
                    self.events.push(ModesPanelEvent::ModeActivated(name));
                }
                if go_vanilla {
                    if let Some(old) = self.registry.active_mode.take() {
                        self.events.push(ModesPanelEvent::VanillaSwap { from_mode: old });
                    }
                }
                
                // Quick vanilla swap button
                if self.registry.active_mode.is_some() {
                    if ui.small_button("⟲ Vanilla").on_hover_text("Quick swap to vanilla Cursor").clicked() {
                        if let Some(old) = self.registry.active_mode.take() {
                            self.events.push(ModesPanelEvent::VanillaSwap { from_mode: old });
                        }
                    }
                }
            });
        });
    }
    
    fn show_mode_list(&mut self, ui: &mut egui::Ui, theme: &Theme) {
        ui.label(RichText::new("Available Modes").size(12.0).strong().color(theme.fg));
        ui.add_space(4.0);
        
        // Collect mode data upfront to avoid borrow issues
        #[derive(Clone)]
        struct ModeDisplayInfo {
            name: String,
            icon: String,
            description: String,
            builtin: bool,
            tool_mode: AccessMode,
            tools_allowed_count: usize,
            tools_blocked_count: usize,
            model_primary: String,
        }
        
        let mode_infos: Vec<ModeDisplayInfo> = self.registry.modes.iter()
            .map(|(name, mode)| ModeDisplayInfo {
                name: name.clone(),
                icon: mode.icon.clone(),
                description: mode.description.clone(),
                builtin: mode.builtin,
                tool_mode: mode.tools.mode,
                tools_allowed_count: mode.tools.allowed.len(),
                tools_blocked_count: mode.tools.blocked.len(),
                model_primary: mode.model.primary.clone(),
            })
            .collect();
        
        // Actions to perform after iteration
        let mut edit_mode: Option<String> = None;
        let mut delete_mode: Option<String> = None;
        let mut activate_mode: Option<String> = None;
        
        for info in &mode_infos {
            let is_active = self.registry.active_mode.as_ref() == Some(&info.name);
            let is_selected = self.selected_mode.as_ref() == Some(&info.name);
            
            let frame_color = if is_selected {
                theme.accent.gamma_multiply(0.3)
            } else if is_active {
                theme.accent.gamma_multiply(0.15)
            } else {
                theme.sidebar_bg
            };
            
            egui::Frame::none()
                .fill(frame_color)
                .rounding(6.0)
                .inner_margin(8.0)
                .show(ui, |ui| {
                    ui.horizontal(|ui| {
                        // Icon and name
                        ui.label(RichText::new(&info.icon).size(16.0));
                        ui.vertical(|ui| {
                            ui.horizontal(|ui| {
                                ui.label(RichText::new(&info.name).strong().color(theme.fg));
                                if is_active {
                                    ui.label(RichText::new("●").size(8.0).color(theme.accent));
                                }
                                if info.builtin {
                                    ui.label(RichText::new("[built-in]").size(9.0).color(theme.fg_dim));
                                }
                            });
                            ui.label(RichText::new(&info.description).size(10.0).color(theme.fg_dim));
                            
                            // Tool/model summary
                            ui.horizontal(|ui| {
                                let tool_badge = match info.tool_mode {
                                    AccessMode::AllAllowed => "🔓 All Tools".to_string(),
                                    AccessMode::Allowlist => format!("🔒 {} tools", info.tools_allowed_count),
                                    AccessMode::Blocklist => format!("🚫 {} blocked", info.tools_blocked_count),
                                };
                                ui.label(RichText::new(tool_badge).size(9.0).color(theme.fg_dim));
                                ui.label(RichText::new("•").size(9.0).color(theme.fg_dim));
                                ui.label(RichText::new(&info.model_primary).size(9.0).color(theme.fg_dim));
                            });
                        });
                        
                        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                            // Edit button
                            if ui.small_button("✏️").on_hover_text("Edit mode").clicked() {
                                edit_mode = Some(info.name.clone());
                            }
                            
                            // Delete button (not for built-ins)
                            if !info.builtin {
                                if ui.small_button("🗑️").on_hover_text("Delete mode").clicked() {
                                    delete_mode = Some(info.name.clone());
                                }
                            }
                            
                            // Activate button
                            if !is_active {
                                if ui.small_button("▶️").on_hover_text("Activate this mode").clicked() {
                                    activate_mode = Some(info.name.clone());
                                }
                            }
                        });
                    });
                });
            
            ui.add_space(4.0);
        }
        
        // Apply actions after iteration
        if let Some(name) = edit_mode {
            self.selected_mode = Some(name.clone());
            self.load_mode_to_editor(&name);
        }
        if let Some(name) = delete_mode {
            self.show_delete_confirm = Some(name);
        }
        if let Some(name) = activate_mode {
            self.registry.set_active(&name);
            self.events.push(ModesPanelEvent::ModeActivated(name));
        }
    }
    
    fn show_mode_editor(&mut self, ui: &mut egui::Ui, theme: &Theme) {
        let Some(ref mode_name) = self.selected_mode.clone() else { return };
        
        ui.separator();
        ui.add_space(8.0);
        
        // Editor header
        ui.horizontal(|ui| {
            ui.label(RichText::new("📝").size(16.0));
            ui.label(RichText::new(format!("Editing: {}", mode_name)).size(13.0).strong().color(theme.fg));
            
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button("✖ Close").clicked() {
                    self.selected_mode = None;
                }
                
                if self.editor.is_dirty {
                    if ui.button("💾 Save").clicked() {
                        self.save_mode_from_editor();
                    }
                }
            });
        });
        
        ui.add_space(8.0);
        
        // Tabbed sections
        egui::CollapsingHeader::new("🏷️ Basic Info")
            .default_open(true)
            .show(ui, |ui| {
                self.show_basic_info_editor(ui, theme);
            });
        
        egui::CollapsingHeader::new("📜 System Prompt")
            .default_open(true)
            .show(ui, |ui| {
                self.show_prompt_editor(ui, theme);
            });
        
        egui::CollapsingHeader::new("🔧 Tool Access")
            .default_open(false)
            .show(ui, |ui| {
                self.show_tools_editor(ui, theme);
            });
        
        egui::CollapsingHeader::new("🤖 Model Configuration")
            .default_open(false)
            .show(ui, |ui| {
                self.show_model_editor(ui, theme);
            });
        
        egui::CollapsingHeader::new("🌍 Context Injection")
            .default_open(false)
            .show(ui, |ui| {
                self.show_context_editor(ui, theme);
            });
    }
    
    fn show_basic_info_editor(&mut self, ui: &mut egui::Ui, theme: &Theme) {
        egui::Grid::new("basic_info_grid")
            .num_columns(2)
            .spacing([8.0, 4.0])
            .show(ui, |ui| {
                ui.label("Name:");
                if ui.text_edit_singleline(&mut self.editor.name).changed() {
                    self.editor.is_dirty = true;
                }
                ui.end_row();
                
                ui.label("Icon:");
                if ui.text_edit_singleline(&mut self.editor.icon).changed() {
                    self.editor.is_dirty = true;
                }
                ui.end_row();
                
                ui.label("Description:");
                if ui.text_edit_singleline(&mut self.editor.description).changed() {
                    self.editor.is_dirty = true;
                }
                ui.end_row();
            });
    }
    
    fn show_prompt_editor(&mut self, ui: &mut egui::Ui, theme: &Theme) {
        ui.label(RichText::new("System prompt injected at the start of every conversation:").size(10.0).color(theme.fg_dim));
        ui.add_space(4.0);
        
        let text_edit = egui::TextEdit::multiline(&mut self.editor.system_prompt)
            .desired_width(f32::INFINITY)
            .desired_rows(10)
            .font(egui::TextStyle::Monospace);
        
        if ui.add(text_edit).changed() {
            self.editor.is_dirty = true;
        }
        
        ui.add_space(4.0);
        ui.label(RichText::new(format!("{} characters", self.editor.system_prompt.len())).size(9.0).color(theme.fg_dim));
    }
    
    fn show_tools_editor(&mut self, ui: &mut egui::Ui, theme: &Theme) {
        ui.label(RichText::new("Control which tools the AI can use:").size(10.0).color(theme.fg_dim));
        ui.add_space(4.0);
        
        ui.horizontal(|ui| {
            ui.label("Access Mode:");
            egui::ComboBox::from_id_salt("tool_access_mode")
                .selected_text(match self.editor.tool_mode {
                    AccessMode::AllAllowed => "🔓 All Allowed",
                    AccessMode::Allowlist => "🔒 Allowlist Only",
                    AccessMode::Blocklist => "🚫 Blocklist",
                })
                .show_ui(ui, |ui| {
                    if ui.selectable_value(&mut self.editor.tool_mode, AccessMode::AllAllowed, "🔓 All Allowed").changed() {
                        self.editor.is_dirty = true;
                    }
                    if ui.selectable_value(&mut self.editor.tool_mode, AccessMode::Allowlist, "🔒 Allowlist Only").changed() {
                        self.editor.is_dirty = true;
                    }
                    if ui.selectable_value(&mut self.editor.tool_mode, AccessMode::Blocklist, "🚫 Blocklist").changed() {
                        self.editor.is_dirty = true;
                    }
                });
        });
        
        ui.add_space(8.0);
        
        match self.editor.tool_mode {
            AccessMode::AllAllowed => {
                ui.label(RichText::new("All tools are available to the AI.").color(theme.fg_dim));
            }
            AccessMode::Allowlist => {
                ui.label("Only these tools will be available:");
                self.show_tool_list_editor(ui, theme, true);
            }
            AccessMode::Blocklist => {
                ui.label("These tools will be blocked:");
                self.show_tool_list_editor(ui, theme, false);
            }
        }
        
        ui.add_space(8.0);
        ui.label(RichText::new("Common tools: read_file, write, edit_file, delete_file, grep, run_terminal_cmd").size(9.0).color(theme.fg_dim));
    }
    
    fn show_tool_list_editor(&mut self, ui: &mut egui::Ui, theme: &Theme, is_allowlist: bool) {
        let tools = if is_allowlist { &mut self.editor.allowed_tools } else { &mut self.editor.blocked_tools };
        
        // Show current tools
        let tools_vec: Vec<_> = tools.iter().cloned().collect();
        ui.horizontal_wrapped(|ui| {
            for tool in &tools_vec {
                ui.horizontal(|ui| {
                    ui.label(RichText::new(format!("• {}", tool)).size(11.0));
                    if ui.small_button("×").clicked() {
                        tools.remove(tool);
                        self.editor.is_dirty = true;
                    }
                });
            }
        });
        
        // Add tool input
        ui.horizontal(|ui| {
            ui.text_edit_singleline(&mut self.editor.tool_list_input);
            if ui.button("Add").clicked() && !self.editor.tool_list_input.is_empty() {
                tools.insert(self.editor.tool_list_input.clone());
                self.editor.tool_list_input.clear();
                self.editor.is_dirty = true;
            }
        });
        
        // Quick add buttons
        ui.horizontal_wrapped(|ui| {
            ui.label(RichText::new("Quick add:").size(10.0).color(theme.fg_dim));
            let common_tools = ["read_file", "write", "edit_file", "delete_file", "grep", "run_terminal_cmd", "mcp_memory_create_entities", "mcp_github_create_pull_request"];
            for tool in common_tools {
                if !tools.contains(tool) {
                    if ui.small_button(tool).clicked() {
                        tools.insert(tool.to_string());
                        self.editor.is_dirty = true;
                    }
                }
            }
        });
    }
    
    fn show_model_editor(&mut self, ui: &mut egui::Ui, theme: &Theme) {
        ui.label(RichText::new("Configure model preferences for this mode:").size(10.0).color(theme.fg_dim));
        ui.add_space(4.0);
        
        egui::Grid::new("model_config_grid")
            .num_columns(2)
            .spacing([8.0, 4.0])
            .show(ui, |ui| {
                ui.label("Primary Model:");
                egui::ComboBox::from_id_salt("primary_model")
                    .selected_text(&self.editor.model_primary)
                    .show_ui(ui, |ui| {
                        let models = [
                            "claude-opus-4",
                            "claude-4.5-sonnet",
                            "claude-4-sonnet",
                            "claude-3.5-haiku",
                            "gpt-4o",
                            "gpt-4-turbo",
                            "o1",
                            "o1-mini",
                            "gemini-2.0-flash",
                        ];
                        for model in models {
                            if ui.selectable_value(&mut self.editor.model_primary, model.to_string(), model).changed() {
                                self.editor.is_dirty = true;
                            }
                        }
                    });
                ui.end_row();
                
                ui.label("Fallback Model:");
                if ui.text_edit_singleline(&mut self.editor.model_fallback).changed() {
                    self.editor.is_dirty = true;
                }
                ui.end_row();
                
                ui.label("Temperature:");
                ui.horizontal(|ui| {
                    if ui.text_edit_singleline(&mut self.editor.temperature).changed() {
                        self.editor.is_dirty = true;
                    }
                    ui.label(RichText::new("(0.0-2.0, empty=default)").size(9.0).color(theme.fg_dim));
                });
                ui.end_row();
                
                ui.label("Max Tokens:");
                ui.horizontal(|ui| {
                    if ui.text_edit_singleline(&mut self.editor.max_tokens).changed() {
                        self.editor.is_dirty = true;
                    }
                    ui.label(RichText::new("(empty=default)").size(9.0).color(theme.fg_dim));
                });
                ui.end_row();
            });
        
        ui.add_space(8.0);
        
        // Model override info
        ui.group(|ui| {
            ui.label(RichText::new("💡 Model Override").size(11.0).color(theme.accent));
            ui.label(RichText::new(
                "When this mode is active, Cursor Studio will inject model preferences into the context. \
                 The actual model used depends on your Cursor subscription and availability."
            ).size(10.0).color(theme.fg_dim));
        });
    }
    
    fn show_context_editor(&mut self, ui: &mut egui::Ui, theme: &Theme) {
        ui.label(RichText::new("Control what context is automatically injected:").size(10.0).color(theme.fg_dim));
        ui.add_space(4.0);
        
        ui.horizontal(|ui| {
            if ui.checkbox(&mut self.editor.include_environment, "Include environment info").changed() {
                self.editor.is_dirty = true;
            }
            ui.label(RichText::new("(hostname, OS, user)").size(9.0).color(theme.fg_dim));
        });
        
        ui.horizontal(|ui| {
            if ui.checkbox(&mut self.editor.include_git, "Include git state").changed() {
                self.editor.is_dirty = true;
            }
            ui.label(RichText::new("(branch, uncommitted, status)").size(9.0).color(theme.fg_dim));
        });
        
        ui.horizontal(|ui| {
            if ui.checkbox(&mut self.editor.include_project, "Include project context").changed() {
                self.editor.is_dirty = true;
            }
            ui.label(RichText::new("(project-specific hints)").size(9.0).color(theme.fg_dim));
        });
        
        ui.add_space(8.0);
        
        ui.label("Additional files to include:");
        ui.label(RichText::new("(one path per line, relative to project root)").size(9.0).color(theme.fg_dim));
        if ui.text_edit_multiline(&mut self.editor.include_files_input).changed() {
            self.editor.is_dirty = true;
        }
        
        ui.add_space(8.0);
        
        ui.label("Custom injection:");
        ui.label(RichText::new("(raw text appended to context)").size(9.0).color(theme.fg_dim));
        if ui.text_edit_multiline(&mut self.editor.custom_injection).changed() {
            self.editor.is_dirty = true;
        }
    }
    
    fn show_injection_controls(&mut self, ui: &mut egui::Ui, theme: &Theme) {
        if self.registry.active_mode.is_none() {
            return;
        }
        
        ui.separator();
        ui.add_space(8.0);
        
        ui.label(RichText::new("🚀 Inject Active Mode").size(12.0).strong().color(theme.fg));
        ui.label(RichText::new("Apply mode configuration to Cursor:").size(10.0).color(theme.fg_dim));
        
        ui.add_space(4.0);
        
        ui.horizontal(|ui| {
            if ui.button("📄 .cursorrules").on_hover_text("Generate .cursorrules in project root").clicked() {
                self.inject_mode(InjectionTarget::CursorRules);
            }
            
            if ui.button("📁 .cursor/rules/").on_hover_text("Generate mode file in .cursor/rules/").clicked() {
                self.inject_mode(InjectionTarget::CursorRulesDir);
            }
            
            if ui.button("🧠 AI Workspace").on_hover_text("Update .ai-workspace/ context").clicked() {
                self.inject_mode(InjectionTarget::AiWorkspace);
            }
            
            if ui.button("🎯 All").on_hover_text("Inject to all targets").clicked() {
                self.inject_mode(InjectionTarget::All);
            }
        });
    }
    
    fn show_create_dialog(&mut self, ui: &mut egui::Ui, _theme: &Theme) {
        if !self.show_create_dialog {
            return;
        }
        
        let mut should_create = false;
        let mut should_cancel = false;
        
        egui::Window::new("Create New Mode")
            .collapsible(false)
            .resizable(false)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .show(ui.ctx(), |ui| {
                ui.label("Mode Name:");
                ui.text_edit_singleline(&mut self.new_mode_name);
                
                ui.add_space(8.0);
                
                ui.horizontal(|ui| {
                    if ui.button("Cancel").clicked() {
                        should_cancel = true;
                    }
                    
                    let valid = !self.new_mode_name.is_empty() 
                        && !self.registry.modes.contains_key(&self.new_mode_name);
                    
                    ui.add_enabled_ui(valid, |ui| {
                        if ui.button("Create").clicked() {
                            should_create = true;
                        }
                    });
                });
            });
        
        // Handle actions after dialog closes
        if should_cancel {
            self.show_create_dialog = false;
        }
        if should_create {
            let name = self.new_mode_name.clone();
            let mode = CustomMode::new(&name, "New custom mode");
            self.registry.upsert(mode);
            let _ = self.registry.save();
            self.events.push(ModesPanelEvent::ModeUpdated(name.clone()));
            self.selected_mode = Some(name.clone());
            self.load_mode_to_editor(&name);
            self.show_create_dialog = false;
        }
    }
    
    fn show_delete_dialog(&mut self, ui: &mut egui::Ui, _theme: &Theme) {
        let Some(ref mode_name) = self.show_delete_confirm.clone() else { return };
        
        egui::Window::new("Delete Mode?")
            .collapsible(false)
            .resizable(false)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .show(ui.ctx(), |ui| {
                ui.label(format!("Are you sure you want to delete '{}'?", mode_name));
                ui.label(RichText::new("This cannot be undone.").color(Color32::from_rgb(255, 100, 100)));
                
                ui.add_space(8.0);
                
                ui.horizontal(|ui| {
                    if ui.button("Cancel").clicked() {
                        self.show_delete_confirm = None;
                    }
                    
                    if ui.button(RichText::new("Delete").color(Color32::from_rgb(255, 100, 100))).clicked() {
                        self.registry.remove(&mode_name);
                        let _ = self.registry.save();
                        self.events.push(ModesPanelEvent::ModeDeleted(mode_name.clone()));
                        if self.selected_mode.as_ref() == Some(&mode_name) {
                            self.selected_mode = None;
                        }
                        self.show_delete_confirm = None;
                    }
                });
            });
    }
    
    fn load_mode_to_editor(&mut self, name: &str) {
        let Some(mode) = self.registry.modes.get(name) else { return };
        
        self.editor.name = mode.name.clone();
        self.editor.description = mode.description.clone();
        self.editor.icon = mode.icon.clone();
        self.editor.system_prompt = mode.system_prompt.clone();
        
        self.editor.tool_mode = mode.tools.mode;
        self.editor.allowed_tools = mode.tools.allowed.clone();
        self.editor.blocked_tools = mode.tools.blocked.clone();
        
        self.editor.model_primary = mode.model.primary.clone();
        self.editor.model_fallback = mode.model.fallback.clone().unwrap_or_default();
        self.editor.temperature = mode.model.temperature.map(|t| t.to_string()).unwrap_or_default();
        self.editor.max_tokens = mode.model.max_tokens.map(|t| t.to_string()).unwrap_or_default();
        
        self.editor.include_environment = mode.context.include_environment;
        self.editor.include_git = mode.context.include_git;
        self.editor.include_project = mode.context.include_project;
        self.editor.include_files_input = mode.context.include_files.join("\n");
        self.editor.custom_injection = mode.context.custom_injection.clone();
        
        self.editor.is_dirty = false;
    }
    
    fn save_mode_from_editor(&mut self) {
        let mode = CustomMode {
            name: self.editor.name.clone(),
            description: self.editor.description.clone(),
            icon: self.editor.icon.clone(),
            system_prompt: self.editor.system_prompt.clone(),
            tools: ToolAccess {
                mode: self.editor.tool_mode,
                allowed: self.editor.allowed_tools.clone(),
                blocked: self.editor.blocked_tools.clone(),
            },
            model: ModelConfig {
                primary: self.editor.model_primary.clone(),
                fallback: if self.editor.model_fallback.is_empty() { None } else { Some(self.editor.model_fallback.clone()) },
                temperature: self.editor.temperature.parse().ok(),
                max_tokens: self.editor.max_tokens.parse().ok(),
            },
            context: ContextConfig {
                include_environment: self.editor.include_environment,
                include_git: self.editor.include_git,
                include_project: self.editor.include_project,
                include_files: self.editor.include_files_input.lines().map(|s| s.to_string()).collect(),
                custom_injection: self.editor.custom_injection.clone(),
            },
            builtin: false,
            created_at: self.registry.modes.get(&self.editor.name)
                .and_then(|m| m.created_at.clone()),
            modified_at: Some(chrono::Utc::now().to_rfc3339()),
        };
        
        let name = mode.name.clone();
        self.registry.upsert(mode);
        let _ = self.registry.save();
        self.events.push(ModesPanelEvent::ModeUpdated(name));
        self.editor.is_dirty = false;
        self.status_message = Some(("Mode saved!".to_string(), false));
    }
    
    fn inject_mode(&mut self, target: InjectionTarget) {
        let Some(ref mode_name) = self.registry.active_mode else {
            self.status_message = Some(("No active mode".to_string(), true));
            return;
        };
        
        let Some(mode) = self.registry.modes.get(mode_name) else {
            self.status_message = Some(("Mode not found".to_string(), true));
            return;
        };
        
        let injector = ModeInjector::new(self.project_root.clone());
        match injector.inject(mode, target) {
            Ok(paths) => {
                self.status_message = Some((format!("Injected to {} files", paths.len()), false));
                self.events.push(ModesPanelEvent::ModeInjected { 
                    mode: mode_name.clone(), 
                    target 
                });
            }
            Err(e) => {
                self.status_message = Some((format!("Error: {}", e), true));
            }
        }
    }
}

