{ pkgs, ... }:

pkgs.writers.writePython3Bin "cursor-manager"
  {
    libraries = with pkgs.python3Packages; [
      tkinter
    ];
    flakeIgnore = [
      "E501" # Line too long
      "W503" # Line break before binary operator
      "E302" # Expected 2 blank lines
      "E305" # Expected 2 blank lines
      "W291" # Trailing whitespace
      "W293" # Blank line contains whitespace
      "E127" # Continuation line over-indented
      "E128" # Continuation line under-indented
    ];
  }
  ''
    """
    Cursor Version Manager v3.2 - Chat History & Auth Sync Edition
    """
    import tkinter as tk
    from tkinter import ttk, messagebox
    import subprocess
    import os
    import json
    import shutil
    import re
    import sqlite3
    
    from pathlib import Path
    from datetime import datetime

    # ═══════════════════════════════════════════════════════════════════════════
    # Configuration & Constants
    # ═══════════════════════════════════════════════════════════════════════════

    CONFIG_DIR = Path.home() / ".config" / "cursor-manager"
    CONFIG_FILE = CONFIG_DIR / "config.json"
    CURSOR_CONFIG_DIR = Path.home() / ".config" / "Cursor"

    DEFAULT_CONFIG = {
        "version": "3.1",
        "defaultVersion": "2.0.77",
        "settings": {
            "syncSettingsOnLaunch": True,
            "syncGlobalStorage": False,
            "persistentWindow": False,
            "theme": "vscode_dark",
            "window": {
                "width": 1000,
                "height": 700,
                "sidebarWidth": 280,
                "sidebarPosition": "left",
                "rememberPosition": True,
                "x": None,
                "y": None
            },
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
        },
        "history": {
            "diskUsage": []
        }
    }

    # Modern Palette - VS Code Dark+ Inspired
    THEMES = {
        "vscode_dark": {
            "bg": "#1e1e1e",
            "sidebar_bg": "#252526",
            "fg": "#d4d4d4",
            "fg_dim": "#808080",
            "accent": "#0078d4",
            "accent_hover": "#1a8cff",
            "accent_dim": "#264f78",
            "border": "#3c3c3c",
            "success": "#3fb950",
            "warning": "#d29922",
            "error": "#f85149",
            "input_bg": "#3c3c3c",
            "input_fg": "#cccccc",
            "card_bg": "#2d2d2d",
            "toggle_off": "#5a5a5a",
            "toggle_on": "#0078d4",
            "sash": "#007acc",
        },
        "vscode_light": {
            "bg": "#ffffff",
            "sidebar_bg": "#f3f3f3",
            "fg": "#333333",
            "fg_dim": "#666666",
            "accent": "#0078d4",
            "accent_hover": "#106ebe",
            "accent_dim": "#c7e0f4",
            "border": "#e0e0e0",
            "success": "#22863a",
            "warning": "#b08800",
            "error": "#cb2431",
            "input_bg": "#ffffff",
            "input_fg": "#333333",
            "card_bg": "#fafafa",
            "toggle_off": "#cccccc",
            "toggle_on": "#0078d4",
            "sash": "#0078d4",
        }
    }

    VERSIONS = {
        "2.1.x - Latest": {
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
        "2.0.x - Custom Modes": {
            "2.0.77 (Stable)": ("cursor-2.0.77", "2.0.77"),
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
            "2.0.11": ("cursor-2.0.11", "2.0.11"),
        },
        "1.7.x - Classic": {
            "1.7.54": ("cursor-1.7.54", "1.7.54"),
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
        "System": {
            "Default (System)": ("cursor", "default"),
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════
    # Utilities
    # ═══════════════════════════════════════════════════════════════════════════

    def deep_merge(base, override):
        result = base.copy()
        for key, value in override.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = deep_merge(result[key], value)
            else:
                result[key] = value
        return result

    def load_config():
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, 'r') as f:
                    return deep_merge(DEFAULT_CONFIG.copy(), json.load(f))
            except Exception:
                pass
        return DEFAULT_CONFIG.copy()

    def save_config(config):
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        try:
            with open(CONFIG_FILE, 'w') as f:
                json.dump(config, f, indent=2)
        except Exception as e:
            print(f"Error saving config: {e}")

    # ═══════════════════════════════════════════════════════════════════════════
    # Custom Widgets
    # ═══════════════════════════════════════════════════════════════════════════

    class ToggleSwitch(tk.Canvas):
        """Modern toggle switch widget."""
        def __init__(self, parent, colors, variable=None, command=None, **kwargs):
            self.width = 44
            self.height = 22
            super().__init__(parent, width=self.width, height=self.height, 
                             bg=colors["sidebar_bg"], highlightthickness=0, **kwargs)
            self.colors = colors
            self.variable = variable or tk.BooleanVar(value=False)
            self.command = command
            self.bind("<Button-1>", self.toggle)
            self.variable.trace_add("write", lambda *args: self.draw())
            self.draw()

        def toggle(self, event=None):
            self.variable.set(not self.variable.get())
            if self.command:
                self.command()

        def draw(self):
            self.delete("all")
            is_on = self.variable.get()
            
            # Track
            track_color = self.colors["toggle_on"] if is_on else self.colors["toggle_off"]
            self.create_rounded_rect(2, 2, self.width - 2, self.height - 2, 10, fill=track_color, outline="")
            
            # Knob
            knob_x = self.width - 13 if is_on else 13
            self.create_oval(knob_x - 8, 3, knob_x + 8, self.height - 3, fill="white", outline="")

        def create_rounded_rect(self, x1, y1, x2, y2, r, **kwargs):
            points = [
                x1 + r, y1, x2 - r, y1, x2, y1, x2, y1 + r,
                x2, y2 - r, x2, y2, x2 - r, y2, x1 + r, y2,
                x1, y2, x1, y2 - r, x1, y1 + r, x1, y1
            ]
            return self.create_polygon(points, smooth=True, **kwargs)

    class HistoricalGraph(tk.Canvas):
        """Graph with historical disk usage over time."""
        def __init__(self, parent, colors, width=500, height=120, **kwargs):
            super().__init__(parent, width=width, height=height, 
                             bg=colors["bg"], highlightthickness=0, **kwargs)
            self.colors = colors
            self.data = []
            self.bind("<Configure>", self.draw)

        def set_data(self, history_list):
            # history_list: [{"date": "YYYY-MM-DD", "caches": bytes, "versions": bytes}, ...]
            self.data = history_list[-14:]  # Last 14 entries
            self.draw()

        def draw(self, event=None):
            self.delete("all")
            w = self.winfo_width()
            h = self.winfo_height()
            
            if w < 50 or h < 50:
                return

            margin_left = 60
            margin_right = 20
            margin_top = 20
            margin_bottom = 30
            
            graph_w = w - margin_left - margin_right
            graph_h = h - margin_top - margin_bottom
            
            # Background grid
            for i in range(5):
                y = margin_top + (graph_h * i / 4)
                self.create_line(margin_left, y, w - margin_right, y, fill=self.colors["border"], dash=(2, 4))
            
            if not self.data:
                self.create_text(w / 2, h / 2, text="No historical data yet", fill=self.colors["fg_dim"], font=("Segoe UI", 9))
                return
            
            # Find max value for scaling
            all_values = []
            for entry in self.data:
                all_values.append(entry.get("caches", 0) + entry.get("versions", 0))
            max_val = max(all_values) if all_values else 1
            if max_val == 0:
                max_val = 1
            
            # Y-axis labels
            for i in range(5):
                y = margin_top + (graph_h * i / 4)
                val = max_val * (4 - i) / 4
                label = self.fmt_size(val)
                self.create_text(margin_left - 5, y, text=label, fill=self.colors["fg_dim"], font=("Segoe UI", 7), anchor="e")
            
            # Draw bars
            n = len(self.data)
            bar_width = max(8, (graph_w - (n - 1) * 4) / n)
            
            for i, entry in enumerate(self.data):
                x = margin_left + i * (bar_width + 4)
                
                c_val = entry.get("caches", 0)
                v_val = entry.get("versions", 0)
                total = c_val + v_val
                
                # Stacked bar
                total_h = (total / max_val) * graph_h
                c_h = (c_val / max_val) * graph_h
                
                # Versions (bottom, green)
                if v_val > 0:
                    self.create_rectangle(x, h - margin_bottom - total_h, 
                                         x + bar_width, h - margin_bottom - c_h,
                                         fill=self.colors["success"], outline="")
                
                # Caches (top, blue)
                if c_val > 0:
                    self.create_rectangle(x, h - margin_bottom - c_h, 
                                         x + bar_width, h - margin_bottom,
                                         fill=self.colors["accent"], outline="")
                
                # Date label (every few bars)
                if i % max(1, n // 5) == 0 or i == n - 1:
                    date_str = entry.get("date", "")[-5:]  # MM-DD
                    self.create_text(x + bar_width / 2, h - margin_bottom + 12, 
                                    text=date_str, fill=self.colors["fg_dim"], font=("Segoe UI", 7))
            
            # Legend
            self.create_rectangle(w - 100, 5, w - 90, 15, fill=self.colors["accent"], outline="")
            self.create_text(w - 85, 10, text="Caches", fill=self.colors["fg"], font=("Segoe UI", 8), anchor="w")
            self.create_rectangle(w - 100, 20, w - 90, 30, fill=self.colors["success"], outline="")
            self.create_text(w - 85, 25, text="Versions", fill=self.colors["fg"], font=("Segoe UI", 8), anchor="w")

        def fmt_size(self, b):
            for u in ['B', 'KB', 'MB', 'GB']:
                if b < 1024:
                    return f"{b:.0f}{u}"
                b /= 1024
            return f"{b:.0f}TB"

    class ModernCard(tk.Frame):
        """Card container with no jarring borders."""
        def __init__(self, parent, colors, title=None, **kwargs):
            super().__init__(parent, bg=colors["card_bg"], **kwargs)
            self.colors = colors
            
            if title:
                self.title_lbl = tk.Label(
                    self, text=title.upper(),
                    bg=colors["card_bg"], fg=colors["fg_dim"],
                    font=("Segoe UI", 9, "bold"), anchor="w"
                )
                self.title_lbl.pack(fill="x", padx=15, pady=(10, 5))
            
            self.inner = tk.Frame(self, bg=colors["card_bg"])
            self.inner.pack(fill="both", expand=True, padx=15, pady=(0, 10))

    # ═══════════════════════════════════════════════════════════════════════════
    # Auth & Chat Sync
    # ═══════════════════════════════════════════════════════════════════════════

    class AuthSync:
        """Handles authentication token synchronization between Cursor versions."""
        
        AUTH_KEYS = [
            "cursorAuth/accessToken",
            "cursorAuth/refreshToken", 
            "cursorAuth/cachedEmail",
            "cursorAuth/cachedSignUpType",
            "cursorAuth/stripeMembershipType",
            "cursorAuth/stripeSubscriptionStatus",
        ]
        
        @staticmethod
        def get_db_path(version=None):
            if version and version != "default":
                return Path.home() / f".cursor-{version}" / "User" / "globalStorage" / "state.vscdb"
            return CURSOR_CONFIG_DIR / "User" / "globalStorage" / "state.vscdb"
        
        @staticmethod
        def read_auth_tokens(version=None):
            """Read auth tokens from a specific version's database."""
            db_path = AuthSync.get_db_path(version)
            if not db_path.exists():
                return None
            
            tokens = {}
            try:
                conn = sqlite3.connect(str(db_path), timeout=5)
                cursor = conn.cursor()
                for key in AuthSync.AUTH_KEYS:
                    cursor.execute("SELECT value FROM ItemTable WHERE key = ?", (key,))
                    row = cursor.fetchone()
                    if row:
                        tokens[key] = row[0]
                conn.close()
                return tokens if tokens else None
            except Exception as e:
                print(f"Error reading auth from {version}: {e}")
                return None
        
        @staticmethod
        def write_auth_tokens(tokens, version):
            """Write auth tokens to a specific version's database."""
            db_path = AuthSync.get_db_path(version)
            db_path.parent.mkdir(parents=True, exist_ok=True)
            
            try:
                conn = sqlite3.connect(str(db_path), timeout=5)
                cursor = conn.cursor()
                cursor.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
                
                for key, value in tokens.items():
                    cursor.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (key, value))
                
                conn.commit()
                conn.close()
                return True
            except Exception as e:
                print(f"Error writing auth to {version}: {e}")
                return False
        
        @staticmethod
        def get_installed_versions():
            """Find all installed Cursor version directories."""
            versions = ["default"]  # Main Cursor installation
            for p in Path.home().iterdir():
                if p.name.startswith(".cursor-") and p.is_dir() and p.name != ".cursor":
                    ver = p.name.replace(".cursor-", "")
                    if (p / "User" / "globalStorage" / "state.vscdb").exists():
                        versions.append(ver)
            return versions
        
        @staticmethod
        def sync_auth_to_version(source_version, target_version):
            """Copy auth tokens from source to target version."""
            tokens = AuthSync.read_auth_tokens(source_version)
            if tokens:
                return AuthSync.write_auth_tokens(tokens, target_version)
            return False
        
        @staticmethod
        def sync_auth_to_all(source_version="default"):
            """Sync auth tokens from source to all installed versions."""
            tokens = AuthSync.read_auth_tokens(source_version)
            if not tokens:
                return False, "No auth tokens found in source"
            
            versions = AuthSync.get_installed_versions()
            synced = []
            for ver in versions:
                if ver != source_version:
                    if AuthSync.write_auth_tokens(tokens, ver):
                        synced.append(ver)
            
            return True, f"Synced to: {', '.join(synced)}" if synced else "No versions to sync"

    class ChatHistoryReader:
        """Reads and aggregates chat history from all Cursor versions."""
        
        @staticmethod
        def get_conversations(version=None):
            """Get all conversation IDs and metadata from a version."""
            db_path = AuthSync.get_db_path(version)
            if not db_path.exists():
                return []
            
            conversations = []
            try:
                conn = sqlite3.connect(str(db_path), timeout=5)
                cursor = conn.cursor()
                
                # Get unique conversation IDs from bubbleId keys
                cursor.execute("""
                    SELECT DISTINCT substr(key, 10, 36) as conv_id 
                    FROM cursorDiskKV 
                    WHERE key LIKE 'bubbleId:%'
                """)
                
                conv_ids = [row[0] for row in cursor.fetchall()]
                
                for conv_id in conv_ids:
                    # Get first message to extract a title/preview
                    cursor.execute("""
                        SELECT value FROM cursorDiskKV 
                        WHERE key LIKE ? 
                        ORDER BY key LIMIT 1
                    """, (f"bubbleId:{conv_id}:%",))
                    
                    row = cursor.fetchone()
                    title = "Untitled Chat"
                    pass  # timestamp placeholder
                    
                    if row:
                        try:
                            msg = json.loads(row[0])
                            # Try to get text content for title
                            if "text" in msg:
                                title = msg["text"][:60] + "..." if len(msg.get("text", "")) > 60 else msg.get("text", "Untitled")
                            elif "rawText" in msg:
                                title = msg["rawText"][:60] + "..." if len(msg.get("rawText", "")) > 60 else msg.get("rawText", "Untitled")
                        except Exception:
                            pass
                    
                    # Count messages
                    cursor.execute("SELECT COUNT(*) FROM cursorDiskKV WHERE key LIKE ?", (f"bubbleId:{conv_id}:%",))
                    msg_count = cursor.fetchone()[0]
                    
                    conversations.append({
                        "id": conv_id,
                        "title": title,
                        "version": version or "default",
                        "message_count": msg_count
                    })
                
                conn.close()
                return conversations
            except Exception as e:
                print(f"Error reading chats from {version}: {e}")
                return []
        
        @staticmethod
        def get_all_conversations():
            """Aggregate conversations from all installed versions."""
            all_convs = []
            for version in AuthSync.get_installed_versions():
                convs = ChatHistoryReader.get_conversations(version)
                all_convs.extend(convs)
            return all_convs

    # ═══════════════════════════════════════════════════════════════════════════
    # Main Application
    # ═══════════════════════════════════════════════════════════════════════════

    class CursorManager(tk.Tk):
        def __init__(self):
            super().__init__()
            self.config = load_config()
            
            theme_name = self.config.get("settings", {}).get("theme", "vscode_dark")
            self.colors = THEMES.get(theme_name, THEMES["vscode_dark"])
            
            self.title("Cursor Manager")
            self.configure(bg=self.colors["bg"])
            
            win_cfg = self.config.get("settings", {}).get("window", {})
            w, h = win_cfg.get("width", 1000), win_cfg.get("height", 700)
            
            if win_cfg.get("rememberPosition", True):
                x, y = win_cfg.get("x"), win_cfg.get("y")
                if x is not None and y is not None:
                    self.geometry(f"{w}x{h}+{x}+{y}")
                else:
                    self.geometry(f"{w}x{h}")
            else:
                self.geometry(f"{w}x{h}")
                
            self.minsize(800, 550)
            self.protocol("WM_DELETE_WINDOW", self.on_close)
            
            self.setup_styles()
            self.build_layout()
            
            self.after(100, self.refresh_disk_stats)

        def setup_styles(self):
            style = ttk.Style()
            style.theme_use('clam')
            
            style.configure("TFrame", background=self.colors["bg"])
            style.configure("Sidebar.TFrame", background=self.colors["sidebar_bg"])
            style.configure("TLabel", background=self.colors["bg"], foreground=self.colors["fg"], font=("Segoe UI", 10))
            
            # Buttons - no borders
            style.configure(
                "TButton",
                background=self.colors["accent"],
                foreground="white",
                borderwidth=0,
                focusthickness=0,
                font=("Segoe UI", 10, "bold"),
                padding=(16, 10)
            )
            style.map("TButton", background=[("active", self.colors["accent_hover"]), ("pressed", self.colors["accent_dim"])])
            
            style.configure(
                "Secondary.TButton",
                background=self.colors["input_bg"],
                foreground=self.colors["fg"],
                borderwidth=0,
                padding=(12, 8)
            )
            style.map("Secondary.TButton", background=[("active", self.colors["border"])])
            
            # Combobox - improved readability
            style.configure(
                "TCombobox", 
                fieldbackground=self.colors["input_bg"],
                background=self.colors["input_bg"],
                foreground=self.colors["input_fg"],
                arrowcolor=self.colors["fg"],
                borderwidth=0,
                padding=8
            )
            style.map("TCombobox", 
                      fieldbackground=[("readonly", self.colors["input_bg"])],
                      selectbackground=[("readonly", self.colors["accent_dim"])],
                      selectforeground=[("readonly", self.colors["fg"])])
            
            # Fix dropdown list colors
            self.option_add("*TCombobox*Listbox.background", self.colors["input_bg"])
            self.option_add("*TCombobox*Listbox.foreground", self.colors["input_fg"])
            self.option_add("*TCombobox*Listbox.selectBackground", self.colors["accent"])
            self.option_add("*TCombobox*Listbox.selectForeground", "white")
            
            # Notebook (Tabs)
            style.configure("TNotebook", background=self.colors["sidebar_bg"], borderwidth=0)
            style.configure(
                "TNotebook.Tab",
                background=self.colors["sidebar_bg"],
                foreground=self.colors["fg_dim"],
                padding=[16, 10],
                font=("Segoe UI", 9, "bold"),
                borderwidth=0
            )
            style.map(
                "TNotebook.Tab",
                background=[("selected", self.colors["accent_dim"])],
                foreground=[("selected", self.colors["fg"])]
            )
            
            # Panedwindow sash
            style.configure("TPanedwindow", background=self.colors["bg"])

        def build_layout(self):
            # Use PanedWindow for resizable sidebar
            self.paned = tk.PanedWindow(self, orient=tk.HORIZONTAL, bg=self.colors["border"],
                                         sashwidth=4, sashrelief=tk.FLAT, borderwidth=0)
            self.paned.pack(fill="both", expand=True)
            
            sidebar_pos = self.config["settings"]["window"].get("sidebarPosition", "left")
            sidebar_w = self.config["settings"]["window"].get("sidebarWidth", 280)
            
            # Sidebar
            self.sidebar = tk.Frame(self.paned, bg=self.colors["sidebar_bg"], width=sidebar_w)
            
            # Content
            self.content = tk.Frame(self.paned, bg=self.colors["bg"], padx=30, pady=25)
            
            if sidebar_pos == "left":
                self.paned.add(self.sidebar, minsize=220, width=sidebar_w)
                self.paned.add(self.content, minsize=400)
            else:
                self.paned.add(self.content, minsize=400)
                self.paned.add(self.sidebar, minsize=220, width=sidebar_w)
            
            self.build_sidebar()
            self.build_dashboard()

        def build_sidebar(self):
            # Header
            header = tk.Frame(self.sidebar, bg=self.colors["sidebar_bg"], pady=20, padx=20)
            header.pack(fill="x")
            
            tk.Label(header, text="CURSOR", bg=self.colors["sidebar_bg"], fg=self.colors["fg"], 
                     font=("Segoe UI", 18, "bold")).pack(anchor="w")
            tk.Label(header, text="MANAGER", bg=self.colors["sidebar_bg"], fg=self.colors["accent"], 
                     font=("Segoe UI", 18, "bold")).pack(anchor="w")
            tk.Label(header, text="v3.1", bg=self.colors["sidebar_bg"], fg=self.colors["fg_dim"], 
                     font=("Segoe UI", 9)).pack(anchor="w", pady=(5, 0))
            
            # Tabs
            self.notebook = ttk.Notebook(self.sidebar)
            self.notebook.pack(fill="both", expand=True, padx=0, pady=10)
            
            self.create_launch_tab()
            self.create_settings_tab()
            self.create_sync_tab()
            
            # Footer with dynamic arrow
            footer = tk.Frame(self.sidebar, bg=self.colors["sidebar_bg"], pady=12, padx=15)
            footer.pack(side="bottom", fill="x")
            
            self.sidebar_toggle_btn = tk.Label(
                footer, text=self.get_arrow_icon(), 
                bg=self.colors["sidebar_bg"], fg=self.colors["fg_dim"],
                font=("Segoe UI", 14), cursor="hand2"
            )
            self.sidebar_toggle_btn.pack(side="left")
            self.sidebar_toggle_btn.bind("<Button-1>", lambda e: self.toggle_sidebar())
            self.sidebar_toggle_btn.bind("<Enter>", lambda e: self.sidebar_toggle_btn.config(fg=self.colors["accent"]))
            self.sidebar_toggle_btn.bind("<Leave>", lambda e: self.sidebar_toggle_btn.config(fg=self.colors["fg_dim"]))

        def get_arrow_icon(self):
            pos = self.config["settings"]["window"].get("sidebarPosition", "left")
            return "◀" if pos == "left" else "▶"

        def create_launch_tab(self):
            frame = tk.Frame(self.notebook, bg=self.colors["sidebar_bg"], padx=20, pady=15)
            self.notebook.add(frame, text="  LAUNCH  ")
            
            tk.Label(frame, text="Era", bg=self.colors["sidebar_bg"], fg=self.colors["fg_dim"],
                     font=("Segoe UI", 9)).pack(anchor="w", pady=(0, 5))
            self.era_var = tk.StringVar()
            era_opts = list(VERSIONS.keys())
            self.era_combo = ttk.Combobox(frame, textvariable=self.era_var, values=era_opts, state="readonly", font=("Segoe UI", 10))
            self.era_combo.pack(fill="x", pady=(0, 15))
            self.era_combo.set(era_opts[1])
            self.era_combo.bind("<<ComboboxSelected>>", self.update_version_list)
            
            tk.Label(frame, text="Version", bg=self.colors["sidebar_bg"], fg=self.colors["fg_dim"],
                     font=("Segoe UI", 9)).pack(anchor="w", pady=(0, 5))
            self.ver_var = tk.StringVar()
            self.ver_combo = ttk.Combobox(frame, textvariable=self.ver_var, state="readonly", font=("Segoe UI", 10))
            self.ver_combo.pack(fill="x", pady=(0, 20))
            
            ttk.Button(frame, text="LAUNCH CURSOR", command=self.launch_app).pack(fill="x", pady=(0, 10))
            ttk.Button(frame, text="Set as Default", style="Secondary.TButton", command=self.set_default).pack(fill="x")
            
            self.update_version_list()

        def create_settings_tab(self):
            frame = tk.Frame(self.notebook, bg=self.colors["sidebar_bg"], padx=20, pady=15)
            self.notebook.add(frame, text="  SETTINGS  ")
            
            # Toggles with labels
            self.toggles = {}
            toggles_config = [
                ("persistentWindow", "Persistent Window", "settings.persistentWindow"),
                ("syncSettings", "Sync Settings", "settings.syncSettingsOnLaunch"),
                ("syncSnippets", "Sync Snippets", "dataControl.syncSnippets"),
                ("npmSecurity", "NPM Security", "security.npmSecurityEnabled"),
            ]
            
            for key, label, path in toggles_config:
                row = tk.Frame(frame, bg=self.colors["sidebar_bg"])
                row.pack(fill="x", pady=8)
                
                tk.Label(row, text=label, bg=self.colors["sidebar_bg"], fg=self.colors["fg"],
                         font=("Segoe UI", 10)).pack(side="left")
                
                parts = path.split(".")
                val = self.config
                for p in parts:
                    val = val.setdefault(p, {})
                current = val if isinstance(val, bool) else False
                
                var = tk.BooleanVar(value=current)
                toggle = ToggleSwitch(row, self.colors, variable=var, 
                                      command=lambda p=path, v=var: self.save_toggle(p, v))
                toggle.pack(side="right")
                self.toggles[key] = var
            
            # Theme selector
            tk.Label(frame, text="Theme", bg=self.colors["sidebar_bg"], fg=self.colors["fg_dim"],
                     font=("Segoe UI", 9)).pack(anchor="w", pady=(20, 5))
            self.theme_var = tk.StringVar(value=self.config["settings"].get("theme", "vscode_dark"))
            theme_cb = ttk.Combobox(frame, textvariable=self.theme_var, 
                                    values=["vscode_dark", "vscode_light"], state="readonly", font=("Segoe UI", 10))
            theme_cb.pack(fill="x")
            theme_cb.bind("<<ComboboxSelected>>", self.change_theme)

        def save_toggle(self, path, var):
            parts = path.split(".")
            target = self.config
            for p in parts[:-1]:
                target = target.setdefault(p, {})
            target[parts[-1]] = var.get()
            save_config(self.config)

        def create_sync_tab(self):
            frame = tk.Frame(self.notebook, bg=self.colors["sidebar_bg"], padx=20, pady=15)
            self.notebook.add(frame, text="  SYNC  ")
            
            # Auth Section
            auth_lbl = tk.Label(frame, text="AUTHENTICATION", bg=self.colors["sidebar_bg"], 
                               fg=self.colors["fg_dim"], font=("Segoe UI", 9, "bold"))
            auth_lbl.pack(anchor="w", pady=(0, 10))
            
            # Current auth status
            tokens = AuthSync.read_auth_tokens()
            if tokens and "cursorAuth/cachedEmail" in tokens:
                email = tokens["cursorAuth/cachedEmail"]
                if isinstance(email, bytes):
                    email = email.decode('utf-8', errors='ignore')
                status_text = f"Logged in: {email}"
                status_color = self.colors["success"]
            else:
                status_text = "Not logged in"
                status_color = self.colors["warning"]
            
            self.auth_status = tk.Label(frame, text=status_text, bg=self.colors["sidebar_bg"],
                                        fg=status_color, font=("Segoe UI", 9))
            self.auth_status.pack(anchor="w", pady=(0, 10))
            
            # Sync auth button
            ttk.Button(frame, text="Sync Auth to All Versions", 
                      command=self.sync_auth_all, style="Secondary.TButton").pack(fill="x", pady=(0, 5))
            
            # Version-specific sync
            tk.Label(frame, text="Sync to Version:", bg=self.colors["sidebar_bg"], 
                    fg=self.colors["fg_dim"], font=("Segoe UI", 9)).pack(anchor="w", pady=(15, 5))
            
            versions = AuthSync.get_installed_versions()
            self.sync_target_var = tk.StringVar(value=versions[0] if versions else "")
            sync_combo = ttk.Combobox(frame, textvariable=self.sync_target_var, 
                                      values=versions, state="readonly", font=("Segoe UI", 10))
            sync_combo.pack(fill="x", pady=(0, 5))
            
            ttk.Button(frame, text="Sync Auth to Selected", 
                      command=self.sync_auth_selected, style="Secondary.TButton").pack(fill="x")
            
            # Separator
            tk.Frame(frame, bg=self.colors["border"], height=1).pack(fill="x", pady=20)
            
            # Chat History Section  
            chat_lbl = tk.Label(frame, text="CHAT HISTORY", bg=self.colors["sidebar_bg"],
                               fg=self.colors["fg_dim"], font=("Segoe UI", 9, "bold"))
            chat_lbl.pack(anchor="w", pady=(0, 10))
            
            ttk.Button(frame, text="View All Chats", 
                      command=self.show_chat_browser, style="Secondary.TButton").pack(fill="x")

        def sync_auth_all(self):
            success, msg = AuthSync.sync_auth_to_all("default")
            if success:
                messagebox.showinfo("Auth Sync", f"✓ {msg}")
            else:
                messagebox.showerror("Auth Sync Failed", msg)

        def sync_auth_selected(self):
            target = self.sync_target_var.get()
            if not target:
                return
            if AuthSync.sync_auth_to_version("default", target):
                messagebox.showinfo("Auth Sync", f"✓ Synced auth to {target}")
            else:
                messagebox.showerror("Auth Sync Failed", f"Could not sync to {target}")

        def show_chat_browser(self):
            """Open chat history browser window."""
            ChatBrowserWindow(self, self.colors)

        def build_dashboard(self):
            # Header row
            header = tk.Frame(self.content, bg=self.colors["bg"])
            header.pack(fill="x", pady=(0, 25))
            
            tk.Label(header, text="Dashboard", bg=self.colors["bg"], fg=self.colors["fg"],
                     font=("Segoe UI", 22, "bold")).pack(side="left")
            
            # Status indicators
            status_frame = tk.Frame(header, bg=self.colors["bg"])
            status_frame.pack(side="right")
            
            def_ver = self.config.get("defaultVersion", "?")
            sec_on = self.config["security"]["npmSecurityEnabled"]
            
            tk.Label(status_frame, text="Default:", bg=self.colors["bg"], fg=self.colors["fg_dim"],
                     font=("Segoe UI", 9)).pack(side="left", padx=(0, 5))
            tk.Label(status_frame, text=def_ver, bg=self.colors["bg"], fg=self.colors["accent"],
                     font=("Segoe UI", 10, "bold")).pack(side="left", padx=(0, 20))
            
            tk.Label(status_frame, text="Security:", bg=self.colors["bg"], fg=self.colors["fg_dim"],
                     font=("Segoe UI", 9)).pack(side="left", padx=(0, 5))
            sec_color = self.colors["success"] if sec_on else self.colors["warning"]
            sec_text = "Active" if sec_on else "Off"
            tk.Label(status_frame, text=sec_text, bg=self.colors["bg"], fg=sec_color,
                     font=("Segoe UI", 10, "bold")).pack(side="left")

            # Storage card with historical graph
            storage = ModernCard(self.content, self.colors, title="Storage History")
            storage.pack(fill="x", pady=(0, 15))
            
            self.graph = HistoricalGraph(storage.inner, self.colors, height=130)
            self.graph.pack(fill="x", pady=(0, 10))
            
            self.disk_stats_lbl = tk.Label(storage.inner, text="Calculating...", 
                                            bg=self.colors["card_bg"], fg=self.colors["fg_dim"],
                                            font=("Segoe UI", 9))
            self.disk_stats_lbl.pack(anchor="w")
            
            # Actions card
            actions = ModernCard(self.content, self.colors, title="Maintenance")
            actions.pack(fill="x")
            
            btn_row = tk.Frame(actions.inner, bg=self.colors["card_bg"])
            btn_row.pack(fill="x")
            
            for txt, cmd in [("Clean Caches", self.clean_caches), 
                             ("Remove Old Versions", self.clean_orphans), 
                             ("Scan NPM", self.dummy_scan)]:
                b = ttk.Button(btn_row, text=txt, style="Secondary.TButton", command=cmd)
                b.pack(side="left", padx=(0, 10))

        # ═══════════════════════════════════════════════════════════════════════════
        # Logic
        # ═══════════════════════════════════════════════════════════════════════════

        def update_version_list(self, event=None):
            era = self.era_var.get()
            vers = list(VERSIONS.get(era, {}).keys())
            self.ver_combo['values'] = vers
            if vers:
                self.ver_combo.set(vers[0])

        def launch_app(self):
            era, ver_key = self.era_var.get(), self.ver_var.get()
            if not ver_key:
                return
            cmd, vid = VERSIONS[era][ver_key]
            
            if self.config["settings"]["syncSettingsOnLaunch"]:
                self.ensure_sync(vid)
                
            if shutil.which(cmd):
                subprocess.Popen([cmd], start_new_session=True)
            else:
                uri = os.environ.get("CURSOR_FLAKE_URI", "github:Distracted-E421/nixos-cursor")
                # Fix: Package names use hyphens, only dots become underscores
                pkg = cmd.replace(".", "_")  # cursor-2.1.20 -> cursor-2_1_20
                subprocess.Popen(["nix", "run", f"{uri}#{pkg}", "--impure"], start_new_session=True)
                
            if not self.config["settings"]["persistentWindow"]:
                self.destroy()

        def ensure_sync(self, vid):
            if vid == "default":
                return
            src = CURSOR_CONFIG_DIR / "User"
            dst = Path.home() / f".cursor-{vid}" / "User"
            if src.exists():
                dst.mkdir(parents=True, exist_ok=True)
                for f in ["settings.json", "keybindings.json"]:
                    if (src / f).exists() and not (dst / f).exists():
                        try:
                            shutil.copy2(src / f, dst / f)
                        except Exception:
                            pass

        def set_default(self):
            era, ver_key = self.era_var.get(), self.ver_var.get()
            if not ver_key:
                return
            _, vid = VERSIONS[era][ver_key]
            self.config["defaultVersion"] = vid
            save_config(self.config)
            messagebox.showinfo("Success", f"Default set to {vid}")

        def toggle_sidebar(self):
            current = self.config["settings"]["window"].get("sidebarPosition", "left")
            new_pos = "right" if current == "left" else "left"
            self.config["settings"]["window"]["sidebarPosition"] = new_pos
            save_config(self.config)
            
            # Rebuild layout
            self.paned.destroy()
            self.build_layout()
            self.refresh_disk_stats()
                
        def change_theme(self, event=None):
            new_theme = self.theme_var.get()
            self.config["settings"]["theme"] = new_theme
            save_config(self.config)
            messagebox.showinfo("Restart Required", "Please restart to apply theme changes.")

        def refresh_disk_stats(self):
            cache_dirs = ["Cache", "CachedData", "GPUCache", "Code Cache", "blob_storage", "Crashpad", "logs"]
            c_size = 0
            v_size = 0
            
            for d in cache_dirs:
                p = CURSOR_CONFIG_DIR / d
                if p.exists():
                    c_size += self.get_size(p)
                
            for p in Path.home().iterdir():
                if p.name.startswith(".cursor-") and p.name != ".cursor" and p.is_dir():
                    v_size += self.get_size(p)
            
            # Save to history
            today = datetime.now().strftime("%Y-%m-%d")
            history = self.config.get("history", {}).get("diskUsage", [])
            
            # Update or add today's entry
            found = False
            for entry in history:
                if entry.get("date") == today:
                    entry["caches"] = c_size
                    entry["versions"] = v_size
                    found = True
                    break
            
            if not found:
                history.append({"date": today, "caches": c_size, "versions": v_size})
            
            # Keep last 30 days
            history = history[-30:]
            self.config["history"] = {"diskUsage": history}
            save_config(self.config)
            
            self.graph.set_data(history)
            
            c_str = self.fmt_size(c_size)
            v_str = self.fmt_size(v_size)
            self.disk_stats_lbl.config(text=f"Today: Caches {c_str}  •  Versions {v_str}")

        def get_size(self, path):
            total = 0
            try:
                for e in path.rglob("*"):
                    if e.is_file():
                        total += e.stat().st_size
            except Exception:
                pass
            return total

        def fmt_size(self, b):
            for u in ['B', 'KB', 'MB', 'GB']:
                if b < 1024:
                    return f"{b:.1f} {u}"
                b /= 1024
            return f"{b:.1f} TB"

        def clean_caches(self):
            if messagebox.askyesno("Confirm", "Delete all cache directories?"):
                cache_dirs = ["Cache", "CachedData", "GPUCache", "Code Cache", "blob_storage", "Crashpad", "logs"]
                for d in cache_dirs:
                    p = CURSOR_CONFIG_DIR / d
                    if p.exists():
                        try:
                            shutil.rmtree(p)
                        except Exception:
                            pass
                self.refresh_disk_stats()
                
        def clean_orphans(self):
            if messagebox.askyesno("Confirm", "Delete all version-specific folders?"):
                for p in Path.home().iterdir():
                    if p.name.startswith(".cursor-") and p.name != ".cursor" and p.is_dir():
                        try:
                            shutil.rmtree(p)
                        except Exception:
                            pass
                self.refresh_disk_stats()

        def dummy_scan(self):
            messagebox.showinfo("Security", "NPM security scanning coming soon!")

    # ═══════════════════════════════════════════════════════════════════════════
    # Chat Browser Window
    # ═══════════════════════════════════════════════════════════════════════════

    class ChatBrowserWindow(tk.Toplevel):
        """Window to browse chat history across all Cursor versions."""
        
        def __init__(self, parent, colors):
            super().__init__(parent)
            self.colors = colors
            self.title("Chat History Browser")
            self.geometry("800x600")
            self.configure(bg=colors["bg"])
            
            self.build_ui()
            self.load_chats()
        
        def build_ui(self):
            # Header
            header = tk.Frame(self, bg=self.colors["bg"], pady=15, padx=20)
            header.pack(fill="x")
            
            tk.Label(header, text="Chat History", bg=self.colors["bg"], fg=self.colors["fg"],
                    font=("Segoe UI", 18, "bold")).pack(side="left")
            
            # Filter by version
            filter_frame = tk.Frame(header, bg=self.colors["bg"])
            filter_frame.pack(side="right")
            
            tk.Label(filter_frame, text="Filter:", bg=self.colors["bg"], fg=self.colors["fg_dim"],
                    font=("Segoe UI", 9)).pack(side="left", padx=(0, 5))
            
            versions = ["All"] + AuthSync.get_installed_versions()
            self.filter_var = tk.StringVar(value="All")
            filter_cb = ttk.Combobox(filter_frame, textvariable=self.filter_var, values=versions,
                                     state="readonly", width=15, font=("Segoe UI", 9))
            filter_cb.pack(side="left")
            filter_cb.bind("<<ComboboxSelected>>", lambda e: self.load_chats())
            
            # Chat list with scrollbar
            list_frame = tk.Frame(self, bg=self.colors["bg"], padx=20)
            list_frame.pack(fill="both", expand=True, pady=(0, 20))
            
            # Create Treeview for chat list
            columns = ("version", "messages", "title")
            self.tree = ttk.Treeview(list_frame, columns=columns, show="headings", height=20)
            
            self.tree.heading("version", text="Version")
            self.tree.heading("messages", text="Msgs")
            self.tree.heading("title", text="Title / First Message")
            
            self.tree.column("version", width=100, minwidth=80)
            self.tree.column("messages", width=60, minwidth=50)
            self.tree.column("title", width=500, minwidth=200)
            
            # Scrollbar
            scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=self.tree.yview)
            self.tree.configure(yscrollcommand=scrollbar.set)
            
            self.tree.pack(side="left", fill="both", expand=True)
            scrollbar.pack(side="right", fill="y")
            
            # Style the treeview
            style = ttk.Style()
            style.configure("Treeview", 
                           background=self.colors["card_bg"],
                           foreground=self.colors["fg"],
                           fieldbackground=self.colors["card_bg"],
                           font=("Segoe UI", 9))
            style.configure("Treeview.Heading",
                           background=self.colors["sidebar_bg"],
                           foreground=self.colors["fg"],
                           font=("Segoe UI", 9, "bold"))
            
            # Status bar
            self.status = tk.Label(self, text="Loading...", bg=self.colors["sidebar_bg"],
                                  fg=self.colors["fg_dim"], font=("Segoe UI", 9), pady=8)
            self.status.pack(fill="x", side="bottom")
        
        def load_chats(self):
            # Clear existing
            for item in self.tree.get_children():
                self.tree.delete(item)
            
            filter_ver = self.filter_var.get()
            
            if filter_ver == "All":
                conversations = ChatHistoryReader.get_all_conversations()
            else:
                conversations = ChatHistoryReader.get_conversations(
                    None if filter_ver == "default" else filter_ver
                )
            
            # Sort by message count (most active first)
            conversations.sort(key=lambda x: x["message_count"], reverse=True)
            
            for conv in conversations:
                ver_display = conv["version"] if conv["version"] != "default" else "Main"
                title = conv["title"] if conv["title"] else "Untitled"
                # Clean up title
                title = title.replace("\n", " ").strip()
                if len(title) > 80:
                    title = title[:77] + "..."
                
                self.tree.insert("", "end", values=(ver_display, conv["message_count"], title))
            
            total = len(conversations)
            plural = "s" if total != 1 else ""
            self.status.config(text=f"Found {total} conversation{plural}")

    # ═══════════════════════════════════════════════════════════════════════════
    # Entry Point  
    # ═══════════════════════════════════════════════════════════════════════════

    class CursorManagerOnClose:
        """Mixin for on_close - kept in CursorManager above."""
        pass

        def on_close(self):
            win_cfg = self.config["settings"]["window"]
            if win_cfg.get("rememberPosition", True):
                g = self.geometry()
                match = re.match(r'(\d+)x(\d+)(?:\+(-?\d+)\+(-?\d+))?', g)
                if match:
                    w, h, x, y = match.groups()
                    win_cfg["width"] = int(w)
                    win_cfg["height"] = int(h)
                    if x is not None and y is not None:
                        win_cfg["x"] = int(x)
                        win_cfg["y"] = int(y)
                
                # Save sidebar width from paned window
                try:
                    panes = self.paned.panes()
                    if panes:
                        pos = self.config["settings"]["window"].get("sidebarPosition", "left")
                        if pos == "left":
                            win_cfg["sidebarWidth"] = self.paned.panecget(panes[0], "width")
                        else:
                            win_cfg["sidebarWidth"] = self.paned.panecget(panes[1], "width")
                except Exception:
                    pass
                
                save_config(self.config)
            self.destroy()

    if __name__ == "__main__":
        app = CursorManager()
        app.mainloop()
  ''
