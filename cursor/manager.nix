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


class CursorManager(tk.Tk):
    def __init__(self):
        super().__init__()

        self.title("Cursor Version Manager")
        self.geometry("400x450")
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
            padding=8
        )
        style.map("TButton", background=[("active", COLORS["highlight"])])

        # Header
        header = ttk.Label(
            self,
            text="Select Cursor Version",
            style="Header.TLabel"
        )
        header.pack(fill="x")

        # Content
        content = ttk.Frame(self, padding=20)
        content.pack(fill="both", expand=True)

        # Options
        self.sync_var = tk.BooleanVar(value=True)
        chk = tk.Checkbutton(
            content,
            text="Sync Settings (keybindings, settings.json)",
            variable=self.sync_var,
            bg=COLORS["bg"],
            fg=COLORS["fg"],
            selectcolor=COLORS["button_bg"],
            activebackground=COLORS["bg"],
            activeforeground=COLORS["fg"],
            highlightthickness=0
        )
        chk.pack(pady=(0, 10), anchor="w")

        self.global_sync_var = tk.BooleanVar(value=False)
        chk_global = tk.Checkbutton(
            content,
            text="Sync Global State (Docs, Auth) [Experimental]",
            variable=self.global_sync_var,
            bg=COLORS["bg"],
            fg=COLORS["fg"],
            selectcolor=COLORS["button_bg"],
            activebackground=COLORS["bg"],
            activeforeground=COLORS["fg"],
            highlightthickness=0
        )
        chk_global.pack(pady=(0, 20), anchor="w")

        # Versions
        self.add_version_btn(
            content,
            "Launch 2.0.77 (Stable)",
            "Latest stable with custom modes",
            "cursor-2.0.77",
            "2.0.77"
        )
        self.add_version_btn(
            content,
            "Launch 1.7.54 (Classic)",
            "Pre-2.0 legacy version",
            "cursor-1.7.54",
            "1.7.54"
        )
        self.add_version_btn(
            content,
            "Launch System Default",
            "Default installed version",
            "cursor",
            "default"
        )

        # Footer
        footer_text = "Cursor Version Manager v1.1\nNixOS Community Edition"
        footer = ttk.Label(
            content,
            text=footer_text,
            justify="center",
            font=("Segoe UI", 8),
            foreground="#666666"
        )
        footer.pack(side="bottom", pady=10)

    def add_version_btn(self, parent, text, desc, cmd, version_id):
        frame = ttk.Frame(parent)
        frame.pack(fill="x", pady=5)

        btn = ttk.Button(
            frame,
            text=text,
            command=lambda: self.launch(cmd, version_id)
        )
        btn.pack(fill="x")

        lbl = ttk.Label(
            frame,
            text=desc,
            font=("Segoe UI", 8),
            foreground="#888888"
        )
        lbl.pack(anchor="w", padx=2)

    def ensure_data_sync(self, version_id):
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
                        print(f"Synced {filename}")
                    except Exception as e:
                        print(f"Failed to sync {filename}: {e}")

            # Snippets
            src_snip = os.path.join(source_dir, "snippets")
            dst_snip = os.path.join(target_dir, "snippets")
            if os.path.exists(src_snip) and not os.path.exists(dst_snip):
                try:
                    shutil.copytree(src_snip, dst_snip)
                    print("Synced snippets")
                except Exception as e:
                    print(f"Failed to sync snippets: {e}")

        # 2. Global State Sync (Symlink)
        if self.global_sync_var.get():
            # This is where Docs likely live (globalStorage/state.vscdb)
            src_global = os.path.join(source_dir, "globalStorage")
            dst_global = os.path.join(target_dir, "globalStorage")

            if os.path.exists(src_global):
                if os.path.exists(dst_global):
                    if os.path.islink(dst_global):
                        pass  # Already linked
                    else:
                        print("Global storage exists and is not a link.")
                else:
                    try:
                        os.symlink(src_global, dst_global)
                        print("Symlinked globalStorage (Docs/Auth shared)")
                    except Exception as e:
                        print(f"Failed to link globalStorage: {e}")

    def launch(self, cmd, version_id):
        try:
            self.ensure_data_sync(version_id)

            # Check if command exists
            if shutil.which(cmd):
                subprocess.Popen([cmd], start_new_session=True)
            else:
                # Try nix run
                # cursor-2.0.77 -> cursor-2_0_77
                pkg_name = cmd.replace(".", "_")
                if pkg_name == "cursor":
                    pkg_name = "cursor"

                # Use configured flake URI or default to GitHub
                flake_uri = os.environ.get(
                    "CURSOR_FLAKE_URI",
                    "github:Distracted-E421/nixos-cursor"
                )

                subprocess.Popen([
                    "nix", "run",
                    f"{flake_uri}#{pkg_name}",
                    "--impure"
                ], start_new_session=True)

            self.destroy()
        except Exception as e:
            messagebox.showerror("Error", f"Failed to launch: {e}")


if __name__ == "__main__":
    app = CursorManager()
    app.mainloop()
''
