{ pkgs, ... }:

pkgs.writers.writePython3Bin "cursor-manager" {
  libraries = [ pkgs.python3Packages.tkinter ];
} ''
import tkinter as tk
from tkinter import ttk, messagebox
import subprocess
import os
import json
import shutil

# Configuration
CONFIG_DIR = os.path.expanduser("~/.config/Cursor")
ISOLATED_BASE = os.path.expanduser("~/.cursor-")

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
        self.geometry("500x400")
        self.configure(bg=COLORS["bg"])
        self.resizable(True, True)

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

        # Combobox styling
        style.configure(
            "TCombobox",
            fieldbackground=COLORS["button_bg"],
            background=COLORS["button_bg"],
            foreground=COLORS["fg"],
            arrowcolor=COLORS["fg"],
            borderwidth=1,
            relief="solid"
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

        # Settings Sync Checkbox
        self.sync_var = tk.BooleanVar(value=True)
        sync_chk = tk.Checkbutton(
            options_frame,
            text="Sync Settings & Keybindings",
            variable=self.sync_var,
            bg=COLORS["bg"],
            fg=COLORS["fg"],
            selectcolor=COLORS["button_bg"],
            activebackground=COLORS["bg"],
            activeforeground=COLORS["fg"],
            font=("Segoe UI", 9)
        )
        sync_chk.pack(anchor="w", padx=5)

        # Global State Sync Checkbox
        self.global_sync_var = tk.BooleanVar(value=False)
        global_chk = tk.Checkbutton(
            options_frame,
            text="Share Docs & Auth (Experimental)",
            variable=self.global_sync_var,
            bg=COLORS["bg"],
            fg=COLORS["fg"],
            selectcolor=COLORS["button_bg"],
            activebackground=COLORS["bg"],
            activeforeground=COLORS["fg"],
            font=("Segoe UI", 9)
        )
        global_chk.pack(anchor="w", padx=5)

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

        # Footer
        footer_text = (
            "Cursor Version Manager v2.0 (RC3.2)\n"
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
                flake_uri = os.environ.get(
                    "CURSOR_FLAKE_URI",
                    "github:Distracted-E421/nixos-cursor"
                )

                print(f"🚀 Launching via Nix: {flake_uri}#{pkg_name}")
                subprocess.Popen([
                    "nix", "run",
                    f"{flake_uri}#{pkg_name}",
                    "--impure"
                ], start_new_session=True)

            self.destroy()
        except Exception as e:
            messagebox.showerror("Launch Error", f"Failed to launch: {e}")


if __name__ == "__main__":
    app = CursorManager()
    app.mainloop()
''
