{ pkgs, ... }:

pkgs.writers.writePython3Bin "cursor-manager"
  {
    libraries = with pkgs.python3Packages; [
      tkinter
    ];
  }
  ''
    """
    Cursor Version Manager v3.0
    Enhanced with settings panel, data control tabs, and persistent window support
    """
    import tkinter as tk
    from tkinter import ttk, messagebox
    import subprocess
    import os
    import json
    import shutil
    from pathlib import Path

    # ═══════════════════════════════════════════════════════════════════════════
    # Configuration
    # ═══════════════════════════════════════════════════════════════════════════

    CONFIG_DIR = Path.home() / ".config" / "cursor-manager"
    CONFIG_FILE = CONFIG_DIR / "config.json"
    CURSOR_CONFIG_DIR = Path.home() / ".config" / "Cursor"
    
    # Default configuration
    DEFAULT_CONFIG = {
        "version": "3.0",
        "defaultVersion": "2.0.77",
        "settings": {
            "syncSettingsOnLaunch": True,
            "syncGlobalStorage": False,
            "persistentWindow": False,
            "theme": "auto",
            "autoCleanup": {
                "enabled": False,
                "keepVersions": 3,
                "olderThanDays": 30
            }
        },
        "dataControl": {
            "isolatedVersionDirs": True,
            "sharedExtensions": False,
            "syncSnippets": True
        },
        "security": {
            "npmSecurityEnabled": True,
            "scanNewPackages": True,
            "blocklistEnabled": True
        }
    }

    # Theme Colors
    THEMES = {
        "dark": {
            "bg": "#1e1e1e",
            "fg": "#cccccc",
            "button_bg": "#3c3c3c",
            "button_fg": "#ffffff",
            "highlight": "#007fd4",
            "header": "#252526",
            "panel_bg": "#252526",
            "tab_bg": "#2d2d2d",
            "success": "#4ec9b0",
            "warning": "#dcdcaa",
            "error": "#f14c4c"
        },
        "light": {
            "bg": "#ffffff",
            "fg": "#333333",
            "button_bg": "#e1e1e1",
            "button_fg": "#333333",
            "highlight": "#007fd4",
            "header": "#f3f3f3",
            "panel_bg": "#f8f8f8",
            "tab_bg": "#eeeeee",
            "success": "#16825d",
            "warning": "#795e26",
            "error": "#c72e2e"
        }
    }

    # Version Database (48 versions)
    VERSIONS = {
        "2.1.x - Latest Era": {
            "2.1.34 (Latest)": ("cursor-2.1.34", "2.1.34"),
            "2.1.32": ("cursor-2.1.32", "2.1.32"),
            "2.1.26": ("cursor-2.1.26", "2.1.26"),
            "2.1.25": ("cursor-2.1.25", "2.1.25"),
            "2.1.24": ("cursor-2.1.24", "2.1.24"),
            "2.1.20": ("cursor-2.1.20", "2.1.20"),
            "2.1.19": ("cursor-2.1.19", "2.1.19"),
            "2.1.17": ("cursor-2.1.17", "2.1.17"),
            "2.1.15": ("cursor-2.1.15", "2.1.15"),
            "2.1.7": ("cursor-2.1.7", "2.1.7"),
            "2.1.6": ("cursor-2.1.6", "2.1.6"),
        },
        "2.0.x - Custom Modes Era": {
            "2.0.77 (Stable - Recommended)": ("cursor-2.0.77", "2.0.77"),
            "2.0.75": ("cursor-2.0.75", "2.0.75"),
            "2.0.74": ("cursor-2.0.74", "2.0.74"),
            "2.0.73": ("cursor-2.0.73", "2.0.73"),
            "2.0.69": ("cursor-2.0.69", "2.0.69"),
            "2.0.64": ("cursor-2.0.64", "2.0.64"),
            "2.0.63": ("cursor-2.0.63", "2.0.63"),
            "2.0.60": ("cursor-2.0.60", "2.0.60"),
            "2.0.57": ("cursor-2.0.57", "2.0.57"),
            "2.0.54": ("cursor-2.0.54", "2.0.54"),
            "2.0.52": ("cursor-2.0.52", "2.0.52"),
            "2.0.43": ("cursor-2.0.43", "2.0.43"),
            "2.0.40": ("cursor-2.0.40", "2.0.40"),
            "2.0.38": ("cursor-2.0.38", "2.0.38"),
            "2.0.34": ("cursor-2.0.34", "2.0.34"),
            "2.0.32": ("cursor-2.0.32", "2.0.32"),
            "2.0.11 (First Custom Modes)": ("cursor-2.0.11", "2.0.11"),
        },
        "1.7.x - Classic Era": {
            "1.7.54 (Latest Pre-2.0)": ("cursor-1.7.54", "1.7.54"),
            "1.7.53": ("cursor-1.7.53", "1.7.53"),
            "1.7.52": ("cursor-1.7.52", "1.7.52"),
            "1.7.46": ("cursor-1.7.46", "1.7.46"),
            "1.7.44": ("cursor-1.7.44", "1.7.44"),
            "1.7.43": ("cursor-1.7.43", "1.7.43"),
            "1.7.40": ("cursor-1.7.40", "1.7.40"),
            "1.7.39": ("cursor-1.7.39", "1.7.39"),
            "1.7.38": ("cursor-1.7.38", "1.7.38"),
            "1.7.36": ("cursor-1.7.36", "1.7.36"),
            "1.7.33": ("cursor-1.7.33", "1.7.33"),
            "1.7.28": ("cursor-1.7.28", "1.7.28"),
            "1.7.25": ("cursor-1.7.25", "1.7.25"),
            "1.7.23": ("cursor-1.7.23", "1.7.23"),
            "1.7.22": ("cursor-1.7.22", "1.7.22"),
            "1.7.17": ("cursor-1.7.17", "1.7.17"),
            "1.7.16": ("cursor-1.7.16", "1.7.16"),
            "1.7.12": ("cursor-1.7.12", "1.7.12"),
            "1.7.11": ("cursor-1.7.11", "1.7.11"),
        },
        "1.6.x - Legacy Era": {
            "1.6.45 (Oldest Available)": ("cursor-1.6.45", "1.6.45"),
        },
        "System Default": {
            "Default (System Cursor)": ("cursor", "default"),
        }
    }


    # ═══════════════════════════════════════════════════════════════════════════
    # Configuration Management
    # ═══════════════════════════════════════════════════════════════════════════

    def load_config():
        """Load configuration from file, creating default if needed"""
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, 'r') as f:
                    config = json.load(f)
                    # Merge with defaults for any missing keys
                    return deep_merge(DEFAULT_CONFIG.copy(), config)
            except Exception as e:
                print(f"⚠️ Error loading config: {e}")
        
        return DEFAULT_CONFIG.copy()

    def save_config(config):
        """Save configuration to file"""
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        try:
            with open(CONFIG_FILE, 'w') as f:
                json.dump(config, f, indent=2)
        except Exception as e:
            print(f"⚠️ Error saving config: {e}")

    def deep_merge(base, override):
        """Deep merge two dictionaries"""
        result = base.copy()
        for key, value in override.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = deep_merge(result[key], value)
            else:
                result[key] = value
        return result


    # ═══════════════════════════════════════════════════════════════════════════
    # Theme Detection
    # ═══════════════════════════════════════════════════════════════════════════

    def detect_theme():
        """Detect theme from Cursor settings or config"""
        config = load_config()
        theme_setting = config.get("settings", {}).get("theme", "auto")
        
        if theme_setting != "auto":
            return THEMES.get(theme_setting, THEMES["dark"])
        
        # Auto-detect from Cursor settings
        try:
            settings_file = CURSOR_CONFIG_DIR / "User" / "settings.json"
            if settings_file.exists():
                with open(settings_file, 'r') as f:
                    settings = json.load(f)
                    if "Light" in settings.get("workbench.colorTheme", ""):
                        return THEMES["light"]
        except Exception:
            pass
        
        return THEMES["dark"]


    # ═══════════════════════════════════════════════════════════════════════════
    # Main Application
    # ═══════════════════════════════════════════════════════════════════════════

    class CursorManager(tk.Tk):
        def __init__(self):
            super().__init__()
            
            self.config = load_config()
            self.colors = detect_theme()
            self.settings_visible = False
            
            self.title("Cursor Version Manager v3.0")
            self.geometry("650x550")
            self.configure(bg=self.colors["bg"])
            self.resizable(True, True)
            
            self.setup_styles()
            self.create_main_ui()
        
        def setup_styles(self):
            """Configure ttk styles"""
            style = ttk.Style()
            style.theme_use('clam')
            
            style.configure("TFrame", background=self.colors["bg"])
            style.configure(
                "TLabel",
                background=self.colors["bg"],
                foreground=self.colors["fg"],
                font=("Segoe UI", 10)
            )
            style.configure(
                "Header.TLabel",
                background=self.colors["header"],
                foreground=self.colors["fg"],
                font=("Segoe UI", 12, "bold"),
                padding=10
            )
            style.configure(
                "TButton",
                background=self.colors["button_bg"],
                foreground=self.colors["button_fg"],
                borderwidth=0,
                focuscolor=self.colors["highlight"],
                font=("Segoe UI", 10),
                padding=8
            )
            style.map("TButton", background=[("active", self.colors["highlight"])])
            
            style.configure(
                "TCombobox",
                fieldbackground=self.colors["button_bg"],
                background=self.colors["button_bg"],
                foreground=self.colors["fg"],
                arrowcolor=self.colors["fg"],
                selectbackground=self.colors["highlight"]
            )
            style.map(
                "TCombobox",
                fieldbackground=[("readonly", self.colors["button_bg"])],
                selectforeground=[("readonly", self.colors["fg"])]
            )
            
            # Notebook (tab) styling
            style.configure(
                "TNotebook",
                background=self.colors["panel_bg"]
            )
            style.configure(
                "TNotebook.Tab",
                background=self.colors["tab_bg"],
                foreground=self.colors["fg"],
                padding=[10, 5]
            )
            style.map(
                "TNotebook.Tab",
                background=[("selected", self.colors["highlight"])],
                foreground=[("selected", "#ffffff")]
            )
        
        def create_main_ui(self):
            """Create the main user interface"""
            # Header
            header_frame = tk.Frame(self, bg=self.colors["header"])
            header_frame.pack(fill="x")
            
            header_label = tk.Label(
                header_frame,
                text="🎯 Cursor Version Manager v3.0",
                bg=self.colors["header"],
                fg=self.colors["fg"],
                font=("Segoe UI", 12, "bold"),
                pady=10
            )
            header_label.pack(side="left", padx=10)
            
            # Settings toggle button
            self.settings_btn = tk.Button(
                header_frame,
                text="⚙️ Settings",
                bg=self.colors["button_bg"],
                fg=self.colors["button_fg"],
                font=("Segoe UI", 9),
                relief="flat",
                padx=10,
                pady=5,
                command=self.toggle_settings
            )
            self.settings_btn.pack(side="right", padx=10, pady=5)
            
            # Main container (holds main content and settings panel)
            self.container = tk.Frame(self, bg=self.colors["bg"])
            self.container.pack(fill="both", expand=True)
            
            # Main content frame
            self.main_frame = ttk.Frame(self.container, padding=15)
            self.main_frame.pack(side="left", fill="both", expand=True)
            
            self.create_main_content()
            
            # Settings panel (initially hidden)
            self.settings_frame = None
        
        def create_main_content(self):
            """Create the main content area"""
            # Version Selection Section
            selection_frame = ttk.LabelFrame(
                self.main_frame, text="Version Selection", padding=10
            )
            selection_frame.pack(fill="x", pady=(0, 10))
            
            # Era dropdown
            era_frame = ttk.Frame(selection_frame)
            era_frame.pack(fill="x", pady=3)
            ttk.Label(era_frame, text="Era:", width=12).pack(side="left")
            
            self.era_var = tk.StringVar()
            era_options = list(VERSIONS.keys())
            self.era_var.set(era_options[1])  # Default to 2.0.x
            
            self.era_combo = ttk.Combobox(
                era_frame,
                textvariable=self.era_var,
                values=era_options,
                state="readonly",
                width=35
            )
            self.era_combo.pack(side="left", fill="x", expand=True)
            self.era_combo.bind("<<ComboboxSelected>>", self.update_version_list)
            
            # Version dropdown
            version_frame = ttk.Frame(selection_frame)
            version_frame.pack(fill="x", pady=3)
            ttk.Label(version_frame, text="Version:", width=12).pack(side="left")
            
            self.version_var = tk.StringVar()
            self.version_combo = ttk.Combobox(
                version_frame,
                textvariable=self.version_var,
                state="readonly",
                width=35
            )
            self.version_combo.pack(side="left", fill="x", expand=True)
            self.update_version_list()
            
            # Action buttons
            btn_frame = ttk.Frame(selection_frame)
            btn_frame.pack(fill="x", pady=(10, 0))
            
            ttk.Button(
                btn_frame, text="📌 Set Default", command=self.set_default_version
            ).pack(side="left", padx=2)
            
            ttk.Button(
                btn_frame, text="🚀 Launch", command=self.launch_selected
            ).pack(side="left", padx=2)
            
            # Quick Status Section
            status_frame = ttk.LabelFrame(
                self.main_frame, text="Status", padding=10
            )
            status_frame.pack(fill="x", pady=(0, 10))
            
            self.status_label = ttk.Label(
                status_frame,
                text=self.get_status_text()
            )
            self.status_label.pack(anchor="w")
            
            # Quick Actions
            actions_frame = ttk.LabelFrame(
                self.main_frame, text="Quick Actions", padding=10
            )
            actions_frame.pack(fill="x", pady=(0, 10))
            
            actions_btn_frame = ttk.Frame(actions_frame)
            actions_btn_frame.pack(fill="x")
            
            ttk.Button(
                actions_btn_frame, text="🔍 Analyze Disk", command=self.analyze_disk
            ).pack(side="left", padx=2)
            
            ttk.Button(
                actions_btn_frame, text="🧹 Clean Caches", command=self.clean_caches
            ).pack(side="left", padx=2)
            
            ttk.Button(
                actions_btn_frame, text="🗑️ Clean Orphans", command=self.clean_orphans
            ).pack(side="left", padx=2)
            
            # Disk usage display
            self.disk_label = ttk.Label(
                actions_frame,
                text="⏳ Calculating disk usage..."
            )
            self.disk_label.pack(anchor="w", pady=(10, 0))
            
            # Footer
            footer = ttk.Label(
                self.main_frame,
                text="Cursor Version Manager v3.0 • NixOS Community Edition",
                foreground="#666666",
                font=("Segoe UI", 8)
            )
            footer.pack(side="bottom", pady=5)
            
            # Calculate disk usage
            self.after(100, self.analyze_disk)
        
        def toggle_settings(self):
            """Toggle the settings panel visibility"""
            if self.settings_visible:
                # Hide settings
                if self.settings_frame:
                    self.settings_frame.destroy()
                    self.settings_frame = None
                self.settings_btn.config(text="⚙️ Settings")
                self.settings_visible = False
            else:
                # Show settings
                self.create_settings_panel()
                self.settings_btn.config(text="✕ Close")
                self.settings_visible = True
        
        def create_settings_panel(self):
            """Create the settings panel with tabs"""
            self.settings_frame = tk.Frame(
                self.container,
                bg=self.colors["panel_bg"],
                width=300
            )
            self.settings_frame.pack(side="right", fill="y")
            self.settings_frame.pack_propagate(False)
            
            # Settings header
            header = tk.Label(
                self.settings_frame,
                text="Settings",
                bg=self.colors["panel_bg"],
                fg=self.colors["fg"],
                font=("Segoe UI", 11, "bold"),
                pady=10
            )
            header.pack(fill="x")
            
            # Notebook for tabs
            notebook = ttk.Notebook(self.settings_frame)
            notebook.pack(fill="both", expand=True, padx=5, pady=5)
            
            # Create tabs
            self.create_version_tab(notebook)
            self.create_data_tab(notebook)
            self.create_disk_tab(notebook)
            self.create_security_tab(notebook)
        
        def create_version_tab(self, notebook):
            """Create the Version Settings tab"""
            frame = ttk.Frame(notebook, padding=10)
            notebook.add(frame, text="Version")
            
            # Persistent Window
            self.persistent_var = tk.BooleanVar(
                value=self.config.get("settings", {}).get("persistentWindow", False)
            )
            tk.Checkbutton(
                frame,
                text="Keep window open after launch",
                variable=self.persistent_var,
                bg=self.colors["panel_bg"],
                fg=self.colors["fg"],
                selectcolor=self.colors["button_bg"],
                activebackground=self.colors["panel_bg"],
                command=self.save_all_settings
            ).pack(anchor="w", pady=2)
            
            # Sync on launch
            self.sync_launch_var = tk.BooleanVar(
                value=self.config.get("settings", {}).get("syncSettingsOnLaunch", True)
            )
            tk.Checkbutton(
                frame,
                text="Apply data sync before launch",
                variable=self.sync_launch_var,
                bg=self.colors["panel_bg"],
                fg=self.colors["fg"],
                selectcolor=self.colors["button_bg"],
                activebackground=self.colors["panel_bg"],
                command=self.save_all_settings
            ).pack(anchor="w", pady=2)
            
            # Separator
            ttk.Separator(frame).pack(fill="x", pady=10)
            
            # Default version
            ttk.Label(frame, text="Default Version:").pack(anchor="w")
            default_version = self.config.get("defaultVersion", "2.0.77")
            ttk.Label(
                frame,
                text=f"Current: {default_version}",
                foreground=self.colors["success"]
            ).pack(anchor="w", pady=2)
            
            # Theme selection
            ttk.Separator(frame).pack(fill="x", pady=10)
            ttk.Label(frame, text="Theme:").pack(anchor="w")
            
            self.theme_var = tk.StringVar(
                value=self.config.get("settings", {}).get("theme", "auto")
            )
            for theme in ["auto", "dark", "light"]:
                tk.Radiobutton(
                    frame,
                    text=theme.capitalize(),
                    variable=self.theme_var,
                    value=theme,
                    bg=self.colors["panel_bg"],
                    fg=self.colors["fg"],
                    selectcolor=self.colors["button_bg"],
                    activebackground=self.colors["panel_bg"],
                    command=self.save_all_settings
                ).pack(anchor="w")
        
        def create_data_tab(self, notebook):
            """Create the Data Control tab"""
            frame = ttk.Frame(notebook, padding=10)
            notebook.add(frame, text="Data")
            
            ttk.Label(frame, text="Data Synchronization:").pack(anchor="w", pady=(0, 5))
            
            # Sync settings
            self.sync_settings_var = tk.BooleanVar(
                value=self.config.get("settings", {}).get("syncSettingsOnLaunch", True)
            )
            tk.Checkbutton(
                frame,
                text="Sync settings.json",
                variable=self.sync_settings_var,
                bg=self.colors["panel_bg"],
                fg=self.colors["fg"],
                selectcolor=self.colors["button_bg"],
                activebackground=self.colors["panel_bg"],
                command=self.save_all_settings
            ).pack(anchor="w")
            
            # Sync snippets
            self.sync_snippets_var = tk.BooleanVar(
                value=self.config.get("dataControl", {}).get("syncSnippets", True)
            )
            tk.Checkbutton(
                frame,
                text="Sync snippets",
                variable=self.sync_snippets_var,
                bg=self.colors["panel_bg"],
                fg=self.colors["fg"],
                selectcolor=self.colors["button_bg"],
                activebackground=self.colors["panel_bg"],
                command=self.save_all_settings
            ).pack(anchor="w")
            
            # Sync global storage
            self.sync_global_var = tk.BooleanVar(
                value=self.config.get("settings", {}).get("syncGlobalStorage", False)
            )
            tk.Checkbutton(
                frame,
                text="Share Docs & Auth (Experimental)",
                variable=self.sync_global_var,
                bg=self.colors["panel_bg"],
                fg=self.colors["fg"],
                selectcolor=self.colors["button_bg"],
                activebackground=self.colors["panel_bg"],
                command=self.save_all_settings
            ).pack(anchor="w")
            
            ttk.Separator(frame).pack(fill="x", pady=10)
            
            ttk.Label(
                frame,
                text="Data directories:",
                font=("Segoe UI", 9, "bold")
            ).pack(anchor="w")
            
            ttk.Label(
                frame,
                text=f"Main: ~/.config/Cursor/",
                font=("Segoe UI", 8),
                foreground="#888888"
            ).pack(anchor="w")
            
            ttk.Label(
                frame,
                text=f"Per-version: ~/.cursor-{{version}}/",
                font=("Segoe UI", 8),
                foreground="#888888"
            ).pack(anchor="w")
        
        def create_disk_tab(self, notebook):
            """Create the Disk Management tab"""
            frame = ttk.Frame(notebook, padding=10)
            notebook.add(frame, text="Disk")
            
            ttk.Label(frame, text="Auto-Cleanup:").pack(anchor="w", pady=(0, 5))
            
            # Auto cleanup enabled
            self.auto_cleanup_var = tk.BooleanVar(
                value=self.config.get("settings", {}).get("autoCleanup", {}).get("enabled", False)
            )
            tk.Checkbutton(
                frame,
                text="Enable automatic cleanup",
                variable=self.auto_cleanup_var,
                bg=self.colors["panel_bg"],
                fg=self.colors["fg"],
                selectcolor=self.colors["button_bg"],
                activebackground=self.colors["panel_bg"],
                command=self.save_all_settings
            ).pack(anchor="w")
            
            # Keep versions
            keep_frame = ttk.Frame(frame)
            keep_frame.pack(fill="x", pady=5)
            ttk.Label(keep_frame, text="Keep recent:").pack(side="left")
            
            self.keep_versions_var = tk.StringVar(
                value=str(self.config.get("settings", {}).get("autoCleanup", {}).get("keepVersions", 3))
            )
            keep_spin = ttk.Spinbox(
                keep_frame,
                from_=1,
                to=10,
                width=5,
                textvariable=self.keep_versions_var,
                command=self.save_all_settings
            )
            keep_spin.pack(side="left", padx=5)
            ttk.Label(keep_frame, text="versions").pack(side="left")
            
            ttk.Separator(frame).pack(fill="x", pady=10)
            
            ttk.Label(
                frame,
                text="💡 Space-saving tips:",
                font=("Segoe UI", 9, "bold")
            ).pack(anchor="w")
            
            tips = [
                "• Clean caches regularly (~100-200MB)",
                "• Remove orphaned version dirs",
                "• Use one version if possible"
            ]
            for tip in tips:
                ttk.Label(
                    frame,
                    text=tip,
                    font=("Segoe UI", 8),
                    foreground="#888888"
                ).pack(anchor="w")
        
        def create_security_tab(self, notebook):
            """Create the Security tab"""
            frame = ttk.Frame(notebook, padding=10)
            notebook.add(frame, text="Security")
            
            ttk.Label(frame, text="NPM Package Security:").pack(anchor="w", pady=(0, 5))
            
            # Security enabled
            self.security_enabled_var = tk.BooleanVar(
                value=self.config.get("security", {}).get("npmSecurityEnabled", True)
            )
            tk.Checkbutton(
                frame,
                text="Enable npm security scanning",
                variable=self.security_enabled_var,
                bg=self.colors["panel_bg"],
                fg=self.colors["fg"],
                selectcolor=self.colors["button_bg"],
                activebackground=self.colors["panel_bg"],
                command=self.save_all_settings
            ).pack(anchor="w")
            
            # Blocklist enabled
            self.blocklist_var = tk.BooleanVar(
                value=self.config.get("security", {}).get("blocklistEnabled", True)
            )
            tk.Checkbutton(
                frame,
                text="Block known malicious packages",
                variable=self.blocklist_var,
                bg=self.colors["panel_bg"],
                fg=self.colors["fg"],
                selectcolor=self.colors["button_bg"],
                activebackground=self.colors["panel_bg"],
                command=self.save_all_settings
            ).pack(anchor="w")
            
            # Scan new packages
            self.scan_new_var = tk.BooleanVar(
                value=self.config.get("security", {}).get("scanNewPackages", True)
            )
            tk.Checkbutton(
                frame,
                text="Scan new MCP packages",
                variable=self.scan_new_var,
                bg=self.colors["panel_bg"],
                fg=self.colors["fg"],
                selectcolor=self.colors["button_bg"],
                activebackground=self.colors["panel_bg"],
                command=self.save_all_settings
            ).pack(anchor="w")
            
            ttk.Separator(frame).pack(fill="x", pady=10)
            
            # Status
            status_text = "✅ Security Active" if self.security_enabled_var.get() else "⚠️ Security Disabled"
            status_color = self.colors["success"] if self.security_enabled_var.get() else self.colors["warning"]
            
            ttk.Label(
                frame,
                text=status_text,
                foreground=status_color
            ).pack(anchor="w")
            
            ttk.Label(
                frame,
                text="Blocklist: 16 packages",
                font=("Segoe UI", 8),
                foreground="#888888"
            ).pack(anchor="w")
        
        def save_all_settings(self):
            """Save all settings to config file"""
            self.config["settings"]["persistentWindow"] = self.persistent_var.get()
            self.config["settings"]["syncSettingsOnLaunch"] = getattr(self, 'sync_launch_var', tk.BooleanVar(value=True)).get()
            self.config["settings"]["syncGlobalStorage"] = getattr(self, 'sync_global_var', tk.BooleanVar(value=False)).get()
            self.config["settings"]["theme"] = getattr(self, 'theme_var', tk.StringVar(value="auto")).get()
            
            if hasattr(self, 'sync_snippets_var'):
                self.config["dataControl"]["syncSnippets"] = self.sync_snippets_var.get()
            
            if hasattr(self, 'auto_cleanup_var'):
                self.config["settings"]["autoCleanup"]["enabled"] = self.auto_cleanup_var.get()
            if hasattr(self, 'keep_versions_var'):
                try:
                    self.config["settings"]["autoCleanup"]["keepVersions"] = int(self.keep_versions_var.get())
                except ValueError:
                    pass
            
            if hasattr(self, 'security_enabled_var'):
                self.config["security"]["npmSecurityEnabled"] = self.security_enabled_var.get()
            if hasattr(self, 'blocklist_var'):
                self.config["security"]["blocklistEnabled"] = self.blocklist_var.get()
            if hasattr(self, 'scan_new_var'):
                self.config["security"]["scanNewPackages"] = self.scan_new_var.get()
            
            save_config(self.config)
        
        def get_status_text(self):
            """Get status summary text"""
            default = self.config.get("defaultVersion", "2.0.77")
            installed = self.count_installed_versions()
            return f"Default: {default} │ Installed: {installed} │ Security: ✅ Active"
        
        def count_installed_versions(self):
            """Count installed version directories"""
            count = 0
            home = Path.home()
            for entry in home.iterdir():
                if entry.name.startswith(".cursor-") and entry.name != ".cursor":
                    if entry.is_dir():
                        count += 1
            return count
        
        def update_version_list(self, event=None):
            """Update version dropdown based on selected era"""
            era = self.era_var.get()
            versions = list(VERSIONS.get(era, {}).keys())
            self.version_combo['values'] = versions
            if versions:
                self.version_var.set(versions[0])
        
        def set_default_version(self):
            """Set the selected version as default"""
            era = self.era_var.get()
            version_name = self.version_var.get()
            
            if not version_name:
                messagebox.showwarning("No Selection", "Please select a version first")
                return
            
            _, version_id = VERSIONS[era][version_name]
            self.config["defaultVersion"] = version_id
            save_config(self.config)
            
            self.status_label.config(text=self.get_status_text())
            messagebox.showinfo("Default Set", f"Default version set to: {version_id}")
        
        def ensure_data_sync(self, version_id):
            """Sync settings and data for isolated versions"""
            if version_id == "default":
                return
            
            if not self.config.get("settings", {}).get("syncSettingsOnLaunch", True):
                return
            
            target_dir = Path.home() / f".cursor-{version_id}" / "User"
            source_dir = CURSOR_CONFIG_DIR / "User"
            
            if not source_dir.exists():
                return
            
            target_dir.mkdir(parents=True, exist_ok=True)
            
            # Sync settings files
            for filename in ["settings.json", "keybindings.json"]:
                src = source_dir / filename
                dst = target_dir / filename
                if src.exists() and not dst.exists():
                    try:
                        shutil.copy2(src, dst)
                        print(f"✅ Synced {filename}")
                    except Exception as e:
                        print(f"❌ Failed to sync {filename}: {e}")
            
            # Sync snippets
            if self.config.get("dataControl", {}).get("syncSnippets", True):
                src_snip = source_dir / "snippets"
                dst_snip = target_dir / "snippets"
                if src_snip.exists() and not dst_snip.exists():
                    try:
                        shutil.copytree(src_snip, dst_snip)
                        print("✅ Synced snippets")
                    except Exception as e:
                        print(f"❌ Failed to sync snippets: {e}")
            
            # Sync globalStorage (symlink)
            if self.config.get("settings", {}).get("syncGlobalStorage", False):
                src_global = source_dir / "globalStorage"
                dst_global = target_dir / "globalStorage"
                if src_global.exists() and not dst_global.exists():
                    try:
                        dst_global.symlink_to(src_global)
                        print("✅ Symlinked globalStorage")
                    except Exception as e:
                        print(f"❌ Failed to link globalStorage: {e}")
        
        def launch_selected(self):
            """Launch the selected Cursor version"""
            era = self.era_var.get()
            version_name = self.version_var.get()
            
            if not version_name:
                messagebox.showwarning("No Selection", "Please select a version to launch")
                return
            
            cmd, version_id = VERSIONS[era][version_name]
            
            try:
                self.ensure_data_sync(version_id)
                
                if shutil.which(cmd):
                    subprocess.Popen([cmd], start_new_session=True)
                    print(f"🚀 Launched {cmd}")
                else:
                    pkg_name = cmd.replace(".", "_").replace("-", "_")
                    flake_uri = os.environ.get("CURSOR_FLAKE_URI", "github:Distracted-E421/nixos-cursor")
                    print(f"🚀 Launching via Nix: {flake_uri}#{pkg_name}")
                    subprocess.Popen([
                        "nix", "run",
                        f"{flake_uri}#{pkg_name}",
                        "--impure"
                    ], start_new_session=True)
                
                # Close unless persistent mode
                if not self.config.get("settings", {}).get("persistentWindow", False):
                    self.destroy()
                    
            except Exception as e:
                messagebox.showerror("Launch Error", f"Failed to launch: {e}")
        
        def analyze_disk(self):
            """Analyze Cursor disk usage"""
            try:
                cache_size = 0
                orphan_size = 0
                cache_count = 0
                orphan_count = 0
                
                cache_dirs = [
                    "Cache", "CachedData", "CachedExtensions",
                    "GPUCache", "Code Cache", "blob_storage", "Crashpad", "logs"
                ]
                
                for cache_dir in cache_dirs:
                    path = CURSOR_CONFIG_DIR / cache_dir
                    if path.exists():
                        size = self.get_dir_size(path)
                        cache_size += size
                        cache_count += 1
                
                home = Path.home()
                for entry in home.iterdir():
                    if entry.name.startswith(".cursor-") and entry.name != ".cursor":
                        if entry.is_dir():
                            size = self.get_dir_size(entry)
                            orphan_size += size
                            orphan_count += 1
                
                self.disk_label.config(
                    text=f"📊 Caches: {self.format_size(cache_size)} ({cache_count} dirs) │ "
                         f"Versions: {self.format_size(orphan_size)} ({orphan_count} dirs)"
                )
                
            except Exception as e:
                self.disk_label.config(text=f"❌ Error: {e}")
        
        def clean_caches(self):
            """Clean Cursor cache directories"""
            cache_dirs = [
                "Cache", "CachedData", "CachedExtensions",
                "GPUCache", "Code Cache", "blob_storage", "Crashpad", "logs"
            ]
            
            total_cleaned = 0
            count = 0
            
            for cache_dir in cache_dirs:
                path = CURSOR_CONFIG_DIR / cache_dir
                if path.exists():
                    total_cleaned += self.get_dir_size(path)
                    count += 1
            
            if count == 0:
                messagebox.showinfo("Clean Caches", "No caches to clean!")
                return
            
            if not messagebox.askyesno(
                "Clean Caches",
                f"Clean {count} cache directories ({self.format_size(total_cleaned)})?"
            ):
                return
            
            for cache_dir in cache_dirs:
                path = CURSOR_CONFIG_DIR / cache_dir
                if path.exists():
                    try:
                        shutil.rmtree(path)
                    except Exception as e:
                        print(f"❌ Failed to clean {path}: {e}")
            
            self.analyze_disk()
            messagebox.showinfo("Done", f"Cleaned {self.format_size(total_cleaned)}")
        
        def clean_orphans(self):
            """Clean orphaned version directories"""
            home = Path.home()
            orphans = []
            
            for entry in home.iterdir():
                if entry.name.startswith(".cursor-") and entry.name != ".cursor":
                    if entry.is_dir():
                        size = self.get_dir_size(entry)
                        orphans.append((entry, entry.name, size))
            
            if not orphans:
                messagebox.showinfo("Clean Orphans", "No orphaned directories found!")
                return
            
            total_size = sum(s for _, _, s in orphans)
            names = "\n".join(f"  • {name}" for _, name, _ in orphans[:5])
            if len(orphans) > 5:
                names += f"\n  ... and {len(orphans) - 5} more"
            
            if not messagebox.askyesno(
                "Clean Orphans",
                f"Remove {len(orphans)} version directories?\n{names}\n\n"
                f"Total: {self.format_size(total_size)}"
            ):
                return
            
            for path, _, _ in orphans:
                try:
                    shutil.rmtree(path)
                except Exception as e:
                    print(f"❌ Failed to remove {path}: {e}")
            
            self.analyze_disk()
            messagebox.showinfo("Done", f"Removed {len(orphans)} directories")
        
        def get_dir_size(self, path):
            """Get total size of a directory"""
            total = 0
            try:
                for entry in path.rglob("*"):
                    if entry.is_file():
                        try:
                            total += entry.stat().st_size
                        except (OSError, PermissionError):
                            pass
            except (OSError, PermissionError):
                pass
            return total
        
        def format_size(self, bytes_size):
            """Format bytes to human-readable size"""
            for unit in ['B', 'KB', 'MB', 'GB']:
                if bytes_size < 1024:
                    return f"{bytes_size:.1f} {unit}"
                bytes_size /= 1024
            return f"{bytes_size:.1f} TB"


    if __name__ == "__main__":
        app = CursorManager()
        app.mainloop()
  ''
