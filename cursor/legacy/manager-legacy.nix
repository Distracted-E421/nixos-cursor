{ pkgs, ... }:

pkgs.writers.writePython3Bin "cursor-manager"
  {
    libraries = [ pkgs.python3Packages.tkinter ];
  }
  ''
    import tkinter as tk
    from tkinter import ttk, messagebox
    import subprocess
    import os
    import json
    import shutil

    # Configuration
    CONFIG_DIR = os.path.expanduser("~/.config/Cursor")
    ISOLATED_BASE = os.path.expanduser("~/.cursor-")
    MANAGER_CONFIG = os.path.expanduser("~/.config/cursor-manager.json")

    # Theme Colors (Default Dark Modern mimic)
    COLORS = {
        "bg": "#1e1e1e",
        "fg": "#cccccc",
        "button_bg": "#3c3c3c",
        "button_fg": "#ffffff",
        "highlight": "#007fd4",
        "header": "#252526"
    }

    # Try to read settings.json for overrides
    try:
        with open(os.path.join(CONFIG_DIR, "User/settings.json"), 'r') as f:
            settings = json.load(f)
            # simplistic check for light theme
            if "Light" in settings.get("workbench.colorTheme", ""):
                COLORS = {
                    "bg": "#ffffff",
                    "fg": "#333333",
                    "button_bg": "#e1e1e1",
                    "button_fg": "#333333",
                    "highlight": "#007fd4",
                    "header": "#f3f3f3"
                }
    except Exception:
        pass


    # Version Database (37 versions organized by era)
    VERSIONS = {
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


    class CursorManager(tk.Tk):
        def __init__(self):
            super().__init__()

            self.title("Cursor Version Manager - RC3.2")
            self.geometry("550x500")  # Larger window to prevent button cutoff
            self.configure(bg=COLORS["bg"])
            self.resizable(True, True)

            # Load persistent settings
            self.load_settings()

            # Style
            style = ttk.Style()
            style.theme_use('clam')

            style.configure("TFrame", background=COLORS["bg"])
            style.configure(
                "TLabel",
                background=COLORS["bg"],
                foreground=COLORS["fg"],
                font=("Segoe UI", 10)
            )
            style.configure(
                "Header.TLabel",
                background=COLORS["header"],
                foreground=COLORS["fg"],
                font=("Segoe UI", 12, "bold"),
                padding=10
            )
            style.configure(
                "TButton",
                background=COLORS["button_bg"],
                foreground=COLORS["button_fg"],
                borderwidth=0,
                focuscolor=COLORS["highlight"],
                font=("Segoe UI", 10),
                padding=10
            )
            style.map("TButton", background=[("active", COLORS["highlight"])])

            # Combobox styling - better contrast
            style.configure(
                "TCombobox",
                fieldbackground=COLORS["button_bg"],
                background=COLORS["button_bg"],
                foreground=COLORS["fg"],
                arrowcolor=COLORS["fg"],
                borderwidth=1,
                relief="solid",
                selectbackground=COLORS["highlight"],
                selectforeground=COLORS["fg"]
            )
            style.map(
                "TCombobox",
                fieldbackground=[("readonly", COLORS["button_bg"])],
                selectbackground=[("readonly", COLORS["button_bg"])],
                selectforeground=[("readonly", COLORS["fg"])]
            )

            # Header
            header = ttk.Label(
                self,
                text="🎯 Cursor Version Manager (37 Versions)",
                style="Header.TLabel"
            )
            header.pack(fill="x")

            # Content
            content = ttk.Frame(self, padding=20)
            content.pack(fill="both", expand=True)

            # Version Selection Section
            selection_frame = ttk.Frame(content)
            selection_frame.pack(fill="x", pady=(0, 15))

            # Era Selection Label
            era_label = ttk.Label(
                selection_frame,
                text="Select Version Era:",
                font=("Segoe UI", 10, "bold")
            )
            era_label.pack(anchor="w", pady=(0, 5))

            # Era Dropdown
            self.era_var = tk.StringVar()
            era_options = list(VERSIONS.keys())
            self.era_var.set(era_options[0])  # Default to 2.0.x

            self.era_combo = ttk.Combobox(
                selection_frame,
                textvariable=self.era_var,
                values=era_options,
                state="readonly",
                width=40,
                font=("Segoe UI", 10)
            )
            self.era_combo.pack(fill="x", pady=(0, 10))
            self.era_combo.bind("<<ComboboxSelected>>", self.update_version_list)

            # Version Selection Label
            version_label = ttk.Label(
                selection_frame,
                text="Select Specific Version:",
                font=("Segoe UI", 10, "bold")
            )
            version_label.pack(anchor="w", pady=(0, 5))

            # Version Dropdown
            self.version_var = tk.StringVar()
            self.version_combo = ttk.Combobox(
                selection_frame,
                textvariable=self.version_var,
                state="readonly",
                width=40,
                font=("Segoe UI", 10)
            )
            self.version_combo.pack(fill="x", pady=(0, 15))

            # Initialize version list
            self.update_version_list()

            # Options Section
            options_frame = ttk.Frame(content)
            options_frame.pack(fill="x", pady=(0, 15))

            options_header = ttk.Label(
                options_frame,
                text="⚙️ Data Sync Options:",
                font=("Segoe UI", 10, "bold")
            )
            options_header.pack(anchor="w", pady=(0, 5))

            # Settings Sync Checkbox (larger, more visible)
            self.sync_var = tk.BooleanVar(value=self.saved_sync_settings)
            sync_chk = tk.Checkbutton(
                options_frame,
                text="Sync Settings & Keybindings",
                variable=self.sync_var,
                bg=COLORS["bg"],
                fg=COLORS["fg"],
                selectcolor=COLORS["button_bg"],
                activebackground=COLORS["bg"],
                activeforeground=COLORS["fg"],
                font=("Segoe UI", 10),
                command=self.save_settings
            )
            sync_chk.pack(anchor="w", padx=5, pady=3)

            # Global State Sync Checkbox (larger, more visible)
            self.global_sync_var = tk.BooleanVar(value=self.saved_global_sync)
            global_chk = tk.Checkbutton(
                options_frame,
                text="Share Docs & Auth (Experimental)",
                variable=self.global_sync_var,
                bg=COLORS["bg"],
                fg=COLORS["fg"],
                selectcolor=COLORS["button_bg"],
                activebackground=COLORS["bg"],
                activeforeground=COLORS["fg"],
                font=("Segoe UI", 10),
                command=self.save_settings
            )
            global_chk.pack(anchor="w", padx=5, pady=3)

            # Launch Button
            launch_btn = ttk.Button(
                content,
                text="🚀 Launch Selected Version",
                command=self.launch_selected
            )
            launch_btn.pack(fill="x", pady=(10, 0))

            # Info Section
            info_frame = ttk.Frame(content)
            info_frame.pack(fill="x", pady=(15, 0))

            info_text = (
                "ℹ️ RC3.2 - 37 Versions Available\n"
                "• 2.0.x: 17 versions with custom modes\n"
                "• 1.7.x: 19 classic pre-2.0 versions\n"
                "• 1.6.x: 1 legacy version"
            )
            info_label = ttk.Label(
                info_frame,
                text=info_text,
                justify="left",
                font=("Segoe UI", 8),
                foreground="#888888"
            )
            info_label.pack(anchor="w")

            # Maintenance Section
            maint_frame = ttk.LabelFrame(
                content,
                text="💾 Disk Management",
                padding=5
            )
            maint_frame.pack(fill="x", pady=(15, 0))

            # Disk usage label
            self.disk_label = ttk.Label(
                maint_frame,
                text="⏳ Calculating disk usage...",
                font=("Segoe UI", 9)
            )
            self.disk_label.pack(anchor="w", padx=5, pady=(0, 5))

            # Maintenance buttons frame
            maint_btns = ttk.Frame(maint_frame)
            maint_btns.pack(fill="x", pady=5)

            ttk.Button(
                maint_btns,
                text="🔍 Analyze",
                command=self.analyze_disk,
                width=12
            ).pack(side="left", padx=2)

            ttk.Button(
                maint_btns,
                text="🧹 Clean Caches",
                command=self.clean_caches,
                width=12
            ).pack(side="left", padx=2)

            ttk.Button(
                maint_btns,
                text="🗑️ Clean Orphans",
                command=self.clean_orphans,
                width=12
            ).pack(side="left", padx=2)

            # Update disk usage on start
            self.after(100, self.analyze_disk)

            # Footer
            footer_text = (
                "Cursor Version Manager v2.1 (RC4)\n"
                "NixOS Community Edition • Credits: oslook"
            )
            footer = ttk.Label(
                content,
                text=footer_text,
                justify="center",
                font=("Segoe UI", 8),
                foreground="#666666"
            )
            footer.pack(side="bottom", pady=(10, 0))

        def load_settings(self):
            """Load persistent settings from config file"""
            self.saved_sync_settings = True  # Default
            self.saved_global_sync = False  # Default

            try:
                if os.path.exists(MANAGER_CONFIG):
                    with open(MANAGER_CONFIG, 'r') as f:
                        config = json.load(f)
                        self.saved_sync_settings = config.get(
                            "sync_settings", True
                        )
                        self.saved_global_sync = config.get(
                            "global_sync", False
                        )
            except Exception as e:
                print(f"⚠️ Could not load settings: {e}")

        def save_settings(self):
            """Save settings to persistent config file"""
            try:
                os.makedirs(os.path.dirname(MANAGER_CONFIG), exist_ok=True)
                config = {
                    "sync_settings": self.sync_var.get(),
                    "global_sync": self.global_sync_var.get()
                }
                with open(MANAGER_CONFIG, 'w') as f:
                    json.dump(config, f, indent=2)
            except Exception as e:
                print(f"⚠️ Could not save settings: {e}")

        def update_version_list(self, event=None):
            """Update version dropdown based on selected era"""
            era = self.era_var.get()
            versions = list(VERSIONS.get(era, {}).keys())

            self.version_combo['values'] = versions
            if versions:
                self.version_var.set(versions[0])  # Select first version

        def ensure_data_sync(self, version_id):
            """Sync settings and data for isolated versions"""
            if version_id == "default":
                return

            target_dir = os.path.expanduser(f"~/.cursor-{version_id}/User")
            source_dir = os.path.join(CONFIG_DIR, "User")

            if not os.path.exists(source_dir):
                return

            # Create target structure
            os.makedirs(target_dir, exist_ok=True)

            # 1. Basic Settings Sync (Copy)
            if self.sync_var.get():
                for filename in ["settings.json", "keybindings.json"]:
                    src = os.path.join(source_dir, filename)
                    dst = os.path.join(target_dir, filename)
                    if os.path.exists(src) and not os.path.exists(dst):
                        try:
                            shutil.copy2(src, dst)
                            print(f"✅ Synced {filename}")
                        except Exception as e:
                            print(f"❌ Failed to sync {filename}: {e}")

                # Snippets
                src_snip = os.path.join(source_dir, "snippets")
                dst_snip = os.path.join(target_dir, "snippets")
                if os.path.exists(src_snip) and not os.path.exists(dst_snip):
                    try:
                        shutil.copytree(src_snip, dst_snip)
                        print("✅ Synced snippets")
                    except Exception as e:
                        print(f"❌ Failed to sync snippets: {e}")

            # 2. Global State Sync (Symlink)
            if self.global_sync_var.get():
                src_global = os.path.join(source_dir, "globalStorage")
                dst_global = os.path.join(target_dir, "globalStorage")

                if os.path.exists(src_global):
                    if os.path.exists(dst_global):
                        if os.path.islink(dst_global):
                            print("✅ GlobalStorage already linked")
                        else:
                            print("⚠️ Global storage exists and is not a link")
                    else:
                        try:
                            os.symlink(src_global, dst_global)
                            print("✅ Symlinked globalStorage (Docs/Auth shared)")
                        except Exception as e:
                            print(f"❌ Failed to link globalStorage: {e}")

        def launch_selected(self):
            """Launch the selected Cursor version"""
            era = self.era_var.get()
            version_name = self.version_var.get()

            if not version_name:
                messagebox.showwarning(
                    "No Selection",
                    "Please select a version to launch"
                )
                return

            cmd, version_id = VERSIONS[era][version_name]

            try:
                self.ensure_data_sync(version_id)

                # Check if command exists in PATH
                if shutil.which(cmd):
                    subprocess.Popen([cmd], start_new_session=True)
                    print(f"🚀 Launched {cmd} from PATH")
                else:
                    # Try nix run
                    pkg_name = cmd.replace(".", "_")

                    # Use configured flake URI or default to GitHub
                    # Check CURSOR_FLAKE_URI env var first (highest priority)
                    flake_uri = os.environ.get("CURSOR_FLAKE_URI")
                    if not flake_uri:
                        flake_uri = "github:Distracted-E421/nixos-cursor"

                    print(f"🚀 Launching via Nix: {flake_uri}#{pkg_name}")
                    subprocess.Popen([
                        "nix", "run",
                        f"{flake_uri}#{pkg_name}",
                        "--impure"
                    ], start_new_session=True)

                self.destroy()
            except Exception as e:
                messagebox.showerror("Launch Error", f"Failed to launch: {e}")

        def analyze_disk(self):
            """Analyze Cursor disk usage"""
            try:
                total_size = 0
                cache_size = 0
                orphan_size = 0
                cache_count = 0
                orphan_count = 0

                # Cache directories
                cache_dirs = [
                    "Cache", "CachedData", "CachedExtensions",
                    "GPUCache", "Code Cache", "blob_storage", "Crashpad", "logs"
                ]

                for cache_dir in cache_dirs:
                    path = os.path.join(CONFIG_DIR, cache_dir)
                    if os.path.exists(path):
                        size = self.get_dir_size(path)
                        cache_size += size
                        cache_count += 1
                        total_size += size

                # Orphaned version directories
                home = os.path.expanduser("~")
                for entry in os.listdir(home):
                    if entry.startswith(".cursor-") and entry != ".cursor":
                        path = os.path.join(home, entry)
                        if os.path.isdir(path):
                            size = self.get_dir_size(path)
                            orphan_size += size
                            orphan_count += 1
                            total_size += size

                # Main config size
                if os.path.exists(CONFIG_DIR):
                    config_size = self.get_dir_size(CONFIG_DIR) - cache_size
                    total_size += config_size

                self.disk_label.config(
                    text=f"📊 Cache: {self.format_size(cache_size)} "
                    f"({cache_count} dirs) | "
                    f"Versions: {self.format_size(orphan_size)} "
                    f"({orphan_count} dirs)"
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

            # Calculate what would be cleaned
            for cache_dir in cache_dirs:
                path = os.path.join(CONFIG_DIR, cache_dir)
                if os.path.exists(path):
                    size = self.get_dir_size(path)
                    total_cleaned += size
                    count += 1

            if count == 0:
                messagebox.showinfo("Clean Caches", "No caches to clean!")
                return

            result = messagebox.askyesno(
                "Clean Caches",
                f"This will clean {count} cache directories\n"
                f"({self.format_size(total_cleaned)}).\n\n"
                "Cursor will recreate these as needed.\n"
                "Continue?"
            )

            if not result:
                return

            for cache_dir in cache_dirs:
                path = os.path.join(CONFIG_DIR, cache_dir)
                if os.path.exists(path):
                    try:
                        shutil.rmtree(path)
                        print(f"✅ Cleaned: {path}")
                    except Exception as e:
                        print(f"❌ Failed to clean {path}: {e}")

            self.analyze_disk()
            messagebox.showinfo(
                "Clean Caches",
                f"Cleaned {self.format_size(total_cleaned)} from caches!"
            )

        def clean_orphans(self):
            """Clean orphaned version directories"""
            home = os.path.expanduser("~")
            orphans = []

            for entry in os.listdir(home):
                if entry.startswith(".cursor-") and entry != ".cursor":
                    path = os.path.join(home, entry)
                    if os.path.isdir(path):
                        size = self.get_dir_size(path)
                        orphans.append((path, entry, size))

            if not orphans:
                messagebox.showinfo(
                    "Clean Orphans", "No orphaned directories found!")
                return

            total_size = sum(s for _, _, s in orphans)
            names = "\n".join(f"  • {name}" for _, name, _ in orphans[:5])
            if len(orphans) > 5:
                names += f"\n  ... and {len(orphans) - 5} more"

            result = messagebox.askyesno(
                "Clean Orphans",
                f"Found {len(orphans)} version directories:\n{names}\n\n"
                f"Total: {self.format_size(total_size)}\n\n"
                "⚠️ This will delete settings for old versions.\n"
                "Continue?"
            )

            if not result:
                return

            cleaned = 0
            for path, name, _ in orphans:
                try:
                    shutil.rmtree(path)
                    print(f"✅ Removed: {path}")
                    cleaned += 1
                except Exception as e:
                    print(f"❌ Failed to remove {path}: {e}")

            self.analyze_disk()
            messagebox.showinfo(
                "Clean Orphans",
                f"Removed {cleaned}/{len(orphans)} directories "
                f"({self.format_size(total_size)})"
            )

        def get_dir_size(self, path):
            """Get total size of a directory in bytes"""
            total = 0
            try:
                for entry in os.scandir(path):
                    if entry.is_file(follow_symlinks=False):
                        total += entry.stat().st_size
                    elif entry.is_dir(follow_symlinks=False):
                        total += self.get_dir_size(entry.path)
            except PermissionError:
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
