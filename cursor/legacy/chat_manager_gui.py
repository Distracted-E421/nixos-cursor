"""
Enhanced Chat Browser GUI for Cursor Manager
Provides full-featured chat management with search, export, and AI integration.
"""
import tkinter as tk
from tkinter import ttk, messagebox, filedialog
from pathlib import Path
import json

# Import our chat database module
from chat_db import ChatDatabase, EXPORTS_DIR, CONTEXT_DIR


class EnhancedChatBrowser(tk.Toplevel):
    """Full-featured chat browser with search, categorization, and export."""
    
    def __init__(self, parent, colors):
        super().__init__(parent)
        self.colors = colors
        self.db = ChatDatabase()
        self.selected_ids = set()
        
        self.title("Chat Library")
        self.geometry("1100x750")
        self.configure(bg=colors["bg"])
        self.minsize(900, 600)
        
        self.build_ui()
        self.load_stats()
        self.load_chats()
    
    def build_ui(self):
        # Main container with sidebar
        self.paned = tk.PanedWindow(self, orient=tk.HORIZONTAL, bg=self.colors["border"],
                                     sashwidth=4, borderwidth=0)
        self.paned.pack(fill="both", expand=True)
        
        # Left sidebar - filters and stats
        self.sidebar = tk.Frame(self.paned, bg=self.colors["sidebar_bg"], width=250)
        self.paned.add(self.sidebar, minsize=200)
        
        # Main content
        self.content = tk.Frame(self.paned, bg=self.colors["bg"])
        self.paned.add(self.content, minsize=500)
        
        self.build_sidebar()
        self.build_content()
    
    def build_sidebar(self):
        # Header
        header = tk.Frame(self.sidebar, bg=self.colors["sidebar_bg"], pady=15, padx=15)
        header.pack(fill="x")
        
        tk.Label(header, text="CHAT LIBRARY", bg=self.colors["sidebar_bg"],
                fg=self.colors["fg"], font=("Segoe UI", 14, "bold")).pack(anchor="w")
        
        # Stats section
        stats_frame = tk.Frame(self.sidebar, bg=self.colors["sidebar_bg"], padx=15, pady=10)
        stats_frame.pack(fill="x")
        
        self.stats_label = tk.Label(stats_frame, text="Loading...",
                                    bg=self.colors["sidebar_bg"], fg=self.colors["fg_dim"],
                                    font=("Segoe UI", 9), justify="left")
        self.stats_label.pack(anchor="w")
        
        # Separator
        tk.Frame(self.sidebar, bg=self.colors["border"], height=1).pack(fill="x", pady=10)
        
        # Filter section
        filter_label = tk.Label(self.sidebar, text="FILTERS", bg=self.colors["sidebar_bg"],
                               fg=self.colors["fg_dim"], font=("Segoe UI", 9, "bold"),
                               padx=15)
        filter_label.pack(anchor="w", pady=(0, 10))
        
        filter_frame = tk.Frame(self.sidebar, bg=self.colors["sidebar_bg"], padx=15)
        filter_frame.pack(fill="x")
        
        # Category filter
        tk.Label(filter_frame, text="Category", bg=self.colors["sidebar_bg"],
                fg=self.colors["fg_dim"], font=("Segoe UI", 9)).pack(anchor="w")
        
        self.categories = self.db.get_categories()
        cat_names = ["All Categories"] + [c["name"] for c in self.categories]
        self.category_var = tk.StringVar(value="All Categories")
        cat_combo = ttk.Combobox(filter_frame, textvariable=self.category_var,
                                 values=cat_names, state="readonly", font=("Segoe UI", 9))
        cat_combo.pack(fill="x", pady=(0, 10))
        cat_combo.bind("<<ComboboxSelected>>", lambda e: self.load_chats())
        
        # Source version filter
        tk.Label(filter_frame, text="Source Version", bg=self.colors["sidebar_bg"],
                fg=self.colors["fg_dim"], font=("Segoe UI", 9)).pack(anchor="w")
        
        stats = self.db.get_stats()
        versions = ["All Versions"] + list(stats.get("by_version", {}).keys())
        self.version_var = tk.StringVar(value="All Versions")
        ver_combo = ttk.Combobox(filter_frame, textvariable=self.version_var,
                                 values=versions, state="readonly", font=("Segoe UI", 9))
        ver_combo.pack(fill="x", pady=(0, 10))
        ver_combo.bind("<<ComboboxSelected>>", lambda e: self.load_chats())
        
        # Favorites toggle
        self.favorites_var = tk.BooleanVar(value=False)
        fav_check = tk.Checkbutton(filter_frame, text="Favorites only",
                                   variable=self.favorites_var,
                                   bg=self.colors["sidebar_bg"], fg=self.colors["fg"],
                                   selectcolor=self.colors["card_bg"],
                                   activebackground=self.colors["sidebar_bg"],
                                   command=self.load_chats)
        fav_check.pack(anchor="w", pady=(5, 10))
        
        # Separator
        tk.Frame(self.sidebar, bg=self.colors["border"], height=1).pack(fill="x", pady=10)
        
        # Actions section
        actions_label = tk.Label(self.sidebar, text="ACTIONS", bg=self.colors["sidebar_bg"],
                                fg=self.colors["fg_dim"], font=("Segoe UI", 9, "bold"),
                                padx=15)
        actions_label.pack(anchor="w", pady=(0, 10))
        
        actions_frame = tk.Frame(self.sidebar, bg=self.colors["sidebar_bg"], padx=15)
        actions_frame.pack(fill="x")
        
        ttk.Button(actions_frame, text="↻ Import from Cursor",
                  command=self.import_chats).pack(fill="x", pady=2)
        ttk.Button(actions_frame, text="⬇ Export Selected",
                  command=self.export_selected).pack(fill="x", pady=2)
        ttk.Button(actions_frame, text="⬇ Export All",
                  command=self.export_all).pack(fill="x", pady=2)
        ttk.Button(actions_frame, text="📄 Generate Context File",
                  command=self.generate_context).pack(fill="x", pady=2)
        
        # Separator
        tk.Frame(self.sidebar, bg=self.colors["border"], height=1).pack(fill="x", pady=10)
        
        # AI section
        ai_label = tk.Label(self.sidebar, text="AI TOOLS", bg=self.colors["sidebar_bg"],
                           fg=self.colors["fg_dim"], font=("Segoe UI", 9, "bold"),
                           padx=15)
        ai_label.pack(anchor="w", pady=(0, 10))
        
        ai_frame = tk.Frame(self.sidebar, bg=self.colors["sidebar_bg"], padx=15)
        ai_frame.pack(fill="x")
        
        ttk.Button(ai_frame, text="🏷️ Generate Title Request",
                  command=self.gen_title_request).pack(fill="x", pady=2)
        ttk.Button(ai_frame, text="📝 Generate Summary Request",
                  command=self.gen_summary_request).pack(fill="x", pady=2)
        ttk.Button(ai_frame, text="📁 Suggest Category",
                  command=self.gen_category_request).pack(fill="x", pady=2)
    
    def build_content(self):
        # Search bar
        search_frame = tk.Frame(self.content, bg=self.colors["bg"], pady=15, padx=20)
        search_frame.pack(fill="x")
        
        tk.Label(search_frame, text="🔍", bg=self.colors["bg"], fg=self.colors["fg_dim"],
                font=("Segoe UI", 12)).pack(side="left", padx=(0, 10))
        
        self.search_var = tk.StringVar()
        search_entry = tk.Entry(search_frame, textvariable=self.search_var,
                               bg=self.colors["input_bg"], fg=self.colors["input_fg"],
                               font=("Segoe UI", 11), insertbackground=self.colors["fg"],
                               relief="flat", highlightthickness=1,
                               highlightbackground=self.colors["border"])
        search_entry.pack(side="left", fill="x", expand=True, ipady=8, ipadx=10)
        search_entry.bind("<Return>", lambda e: self.search_chats())
        
        ttk.Button(search_frame, text="Search", command=self.search_chats).pack(side="left", padx=(10, 0))
        ttk.Button(search_frame, text="Clear", command=self.clear_search).pack(side="left", padx=(5, 0))
        
        # Selection info bar
        self.selection_frame = tk.Frame(self.content, bg=self.colors["accent_dim"], pady=8, padx=20)
        # Hidden by default
        
        self.selection_label = tk.Label(self.selection_frame, text="0 selected",
                                        bg=self.colors["accent_dim"], fg=self.colors["fg"],
                                        font=("Segoe UI", 9))
        self.selection_label.pack(side="left")
        
        # Chat list with scrollbar
        list_frame = tk.Frame(self.content, bg=self.colors["bg"], padx=20)
        list_frame.pack(fill="both", expand=True, pady=(0, 10))
        
        # Create Treeview for chat list
        columns = ("select", "favorite", "category", "version", "msgs", "title")
        self.tree = ttk.Treeview(list_frame, columns=columns, show="headings", height=20,
                                 selectmode="extended")
        
        self.tree.heading("select", text="☐")
        self.tree.heading("favorite", text="★")
        self.tree.heading("category", text="Category")
        self.tree.heading("version", text="Version")
        self.tree.heading("msgs", text="Msgs")
        self.tree.heading("title", text="Title")
        
        self.tree.column("select", width=30, minwidth=30, anchor="center")
        self.tree.column("favorite", width=30, minwidth=30, anchor="center")
        self.tree.column("category", width=100, minwidth=80)
        self.tree.column("version", width=80, minwidth=60)
        self.tree.column("msgs", width=50, minwidth=40, anchor="center")
        self.tree.column("title", width=500, minwidth=200)
        
        # Scrollbar
        scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        
        self.tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        # Bindings
        self.tree.bind("<Double-1>", self.on_double_click)
        self.tree.bind("<Button-1>", self.on_click)
        self.tree.bind("<<TreeviewSelect>>", self.on_selection_change)
        
        # Style the treeview
        style = ttk.Style()
        style.configure("Treeview",
                       background=self.colors["card_bg"],
                       foreground=self.colors["fg"],
                       fieldbackground=self.colors["card_bg"],
                       font=("Segoe UI", 9),
                       rowheight=28)
        style.configure("Treeview.Heading",
                       background=self.colors["sidebar_bg"],
                       foreground=self.colors["fg"],
                       font=("Segoe UI", 9, "bold"))
        style.map("Treeview",
                 background=[("selected", self.colors["accent_dim"])],
                 foreground=[("selected", self.colors["fg"])])
        
        # Status bar
        status_frame = tk.Frame(self.content, bg=self.colors["sidebar_bg"], pady=8, padx=20)
        status_frame.pack(fill="x", side="bottom")
        
        self.status_label = tk.Label(status_frame, text="Loading...",
                                    bg=self.colors["sidebar_bg"], fg=self.colors["fg_dim"],
                                    font=("Segoe UI", 9))
        self.status_label.pack(side="left")
        
        self.export_path_label = tk.Label(status_frame, text=f"Export: {EXPORTS_DIR}",
                                         bg=self.colors["sidebar_bg"], fg=self.colors["fg_dim"],
                                         font=("Segoe UI", 8))
        self.export_path_label.pack(side="right")
    
    def load_stats(self):
        stats = self.db.get_stats()
        text = f"📊 {stats['total_conversations']} chats\n"
        text += f"💬 {stats['total_messages']} messages\n"
        text += f"⭐ {stats['favorites']} favorites"
        self.stats_label.config(text=text)
    
    def load_chats(self):
        # Clear existing
        for item in self.tree.get_children():
            self.tree.delete(item)
        
        # Get filter values
        category_id = None
        if self.category_var.get() != "All Categories":
            cat_name = self.category_var.get()
            cat = next((c for c in self.categories if c["name"] == cat_name), None)
            if cat:
                category_id = cat["id"]
        
        favorites_only = self.favorites_var.get()
        
        # Query database
        conversations = self.db.get_conversations(
            category_id=category_id,
            favorites_only=favorites_only,
            limit=500
        )
        
        # Filter by version if needed
        version_filter = self.version_var.get()
        if version_filter != "All Versions":
            conversations = [c for c in conversations if c["source_version"] == version_filter]
        
        # Populate tree
        for conv in conversations:
            select_icon = "☑" if conv["id"] in self.selected_ids else "☐"
            fav_icon = "★" if conv.get("is_favorite") else "☆"
            category = conv.get("category_name", "General")
            version = conv.get("source_version", "default")
            if version == "default":
                version = "Main"
            msgs = conv.get("message_count", 0)
            title = conv.get("ai_title") or conv.get("original_title") or "Untitled"
            title = title.replace("\n", " ").strip()[:80]
            
            self.tree.insert("", "end", iid=conv["id"],
                           values=(select_icon, fav_icon, category, version, msgs, title))
        
        self.status_label.config(text=f"Showing {len(conversations)} conversations")
        self.update_selection_bar()
    
    def on_click(self, event):
        region = self.tree.identify_region(event.x, event.y)
        if region != "cell":
            return
        
        column = self.tree.identify_column(event.x)
        item = self.tree.identify_row(event.y)
        
        if not item:
            return
        
        if column == "#1":  # Select column
            if item in self.selected_ids:
                self.selected_ids.remove(item)
            else:
                self.selected_ids.add(item)
            self.update_row(item)
            self.update_selection_bar()
        
        elif column == "#2":  # Favorite column
            self.db.toggle_favorite(item)
            self.update_row(item)
    
    def update_row(self, item):
        conv = self.db.get_conversation(item)
        if not conv:
            return
        
        select_icon = "☑" if item in self.selected_ids else "☐"
        fav_icon = "★" if conv.get("is_favorite") else "☆"
        category = conv.get("category_name", "General")
        version = conv.get("source_version", "default")
        if version == "default":
            version = "Main"
        msgs = conv.get("message_count", 0)
        title = conv.get("ai_title") or conv.get("original_title") or "Untitled"
        title = title.replace("\n", " ").strip()[:80]
        
        self.tree.item(item, values=(select_icon, fav_icon, category, version, msgs, title))
    
    def update_selection_bar(self):
        count = len(self.selected_ids)
        if count > 0:
            self.selection_frame.pack(fill="x", before=self.tree.master)
            self.selection_label.config(text=f"{count} conversation{'s' if count > 1 else ''} selected")
        else:
            self.selection_frame.pack_forget()
    
    def on_selection_change(self, event):
        pass  # We handle selection manually via checkboxes
    
    def on_double_click(self, event):
        item = self.tree.identify_row(event.y)
        if item:
            self.show_conversation(item)
    
    def show_conversation(self, conv_id):
        """Open conversation detail view."""
        conv = self.db.get_conversation(conv_id)
        if not conv:
            return
        
        # Create detail window
        detail = tk.Toplevel(self)
        detail.title(conv.get("ai_title") or conv.get("original_title") or "Chat Detail")
        detail.geometry("800x600")
        detail.configure(bg=self.colors["bg"])
        
        # Header
        header = tk.Frame(detail, bg=self.colors["sidebar_bg"], pady=15, padx=20)
        header.pack(fill="x")
        
        title = conv.get("ai_title") or conv.get("original_title") or "Untitled"
        tk.Label(header, text=title[:60], bg=self.colors["sidebar_bg"],
                fg=self.colors["fg"], font=("Segoe UI", 14, "bold")).pack(anchor="w")
        
        info_text = f"{conv.get('message_count', 0)} messages • {conv.get('category_name', 'General')} • {conv.get('source_version', 'default')}"
        tk.Label(header, text=info_text, bg=self.colors["sidebar_bg"],
                fg=self.colors["fg_dim"], font=("Segoe UI", 9)).pack(anchor="w")
        
        # Messages
        msg_frame = tk.Frame(detail, bg=self.colors["bg"], padx=20, pady=10)
        msg_frame.pack(fill="both", expand=True)
        
        # Text widget with scrollbar
        text = tk.Text(msg_frame, bg=self.colors["card_bg"], fg=self.colors["fg"],
                      font=("Consolas", 10), wrap="word", relief="flat",
                      insertbackground=self.colors["fg"])
        scrollbar = ttk.Scrollbar(msg_frame, orient="vertical", command=text.yview)
        text.configure(yscrollcommand=scrollbar.set)
        
        text.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        # Configure tags for roles
        text.tag_configure("user", foreground=self.colors["accent"])
        text.tag_configure("assistant", foreground=self.colors["success"])
        text.tag_configure("separator", foreground=self.colors["border"])
        
        # Insert messages
        for msg in conv.get("messages", []):
            role = "👤 USER" if msg["role"] == "user" else "🤖 ASSISTANT"
            tag = "user" if msg["role"] == "user" else "assistant"
            
            text.insert("end", f"\n{role}\n", tag)
            text.insert("end", "-" * 60 + "\n", "separator")
            text.insert("end", (msg["content"] or "") + "\n\n")
        
        text.config(state="disabled")
        
        # Bottom actions
        actions = tk.Frame(detail, bg=self.colors["sidebar_bg"], pady=10, padx=20)
        actions.pack(fill="x")
        
        ttk.Button(actions, text="Export to Markdown",
                  command=lambda: self.export_single(conv_id)).pack(side="left", padx=(0, 10))
        ttk.Button(actions, text="Generate Title Request",
                  command=lambda: self.gen_title_for(conv_id)).pack(side="left", padx=(0, 10))
        ttk.Button(actions, text="Set Category",
                  command=lambda: self.set_category_dialog(conv_id)).pack(side="left")
    
    def search_chats(self):
        query = self.search_var.get().strip()
        if not query:
            self.load_chats()
            return
        
        # Clear existing
        for item in self.tree.get_children():
            self.tree.delete(item)
        
        conversations = self.db.get_conversations(search=query, limit=500)
        
        for conv in conversations:
            select_icon = "☑" if conv["id"] in self.selected_ids else "☐"
            fav_icon = "★" if conv.get("is_favorite") else "☆"
            category = conv.get("category_name", "General")
            version = conv.get("source_version", "default")
            if version == "default":
                version = "Main"
            msgs = conv.get("message_count", 0)
            title = conv.get("ai_title") or conv.get("original_title") or "Untitled"
            title = title.replace("\n", " ").strip()[:80]
            
            self.tree.insert("", "end", iid=conv["id"],
                           values=(select_icon, fav_icon, category, version, msgs, title))
        
        self.status_label.config(text=f"Found {len(conversations)} conversations matching '{query}'")
    
    def clear_search(self):
        self.search_var.set("")
        self.load_chats()
    
    def import_chats(self):
        results = self.db.import_all_versions()
        messagebox.showinfo("Import Complete",
                           f"Imported: {results['total_imported']}\n"
                           f"Skipped (duplicates): {results['total_skipped']}")
        self.load_stats()
        self.load_chats()
    
    def export_selected(self):
        if not self.selected_ids:
            messagebox.showwarning("No Selection", "Please select conversations to export.")
            return
        
        results = self.db.bulk_export(conv_ids=list(self.selected_ids))
        messagebox.showinfo("Export Complete",
                           f"Exported {len(results['exported'])} conversations\n"
                           f"to {results['output_dir']}")
    
    def export_all(self):
        if not messagebox.askyesno("Export All", "Export all conversations to markdown?"):
            return
        
        results = self.db.bulk_export()
        messagebox.showinfo("Export Complete",
                           f"Exported {len(results['exported'])} conversations\n"
                           f"to {results['output_dir']}")
    
    def export_single(self, conv_id):
        path = self.db.export_to_markdown(conv_id)
        if path:
            messagebox.showinfo("Exported", f"Saved to:\n{path}")
    
    def generate_context(self):
        if not self.selected_ids:
            messagebox.showwarning("No Selection", "Please select conversations for context.")
            return
        
        # Ask for context name
        dialog = tk.Toplevel(self)
        dialog.title("Generate Context File")
        dialog.geometry("400x200")
        dialog.configure(bg=self.colors["bg"])
        dialog.transient(self)
        dialog.grab_set()
        
        tk.Label(dialog, text="Context File Name:", bg=self.colors["bg"],
                fg=self.colors["fg"], font=("Segoe UI", 10)).pack(pady=(20, 5))
        
        name_var = tk.StringVar(value="workspace-context")
        name_entry = tk.Entry(dialog, textvariable=name_var, font=("Segoe UI", 11),
                             bg=self.colors["input_bg"], fg=self.colors["input_fg"])
        name_entry.pack(fill="x", padx=20, ipady=5)
        
        tk.Label(dialog, text="Style:", bg=self.colors["bg"],
                fg=self.colors["fg"], font=("Segoe UI", 10)).pack(pady=(15, 5))
        
        style_var = tk.StringVar(value="summary")
        style_combo = ttk.Combobox(dialog, textvariable=style_var,
                                   values=["summary", "full", "key_points"],
                                   state="readonly", font=("Segoe UI", 10))
        style_combo.pack(fill="x", padx=20)
        
        def do_generate():
            path = self.db.generate_context_file(
                list(self.selected_ids),
                name_var.get(),
                style_var.get()
            )
            dialog.destroy()
            messagebox.showinfo("Context Generated", f"Saved to:\n{path}")
        
        ttk.Button(dialog, text="Generate", command=do_generate).pack(pady=20)
    
    def gen_title_request(self):
        selected = self.tree.selection()
        if not selected:
            messagebox.showwarning("No Selection", "Please select a conversation first.")
            return
        
        conv_id = selected[0]
        path = self.db.generate_title_request(conv_id)
        if path:
            messagebox.showinfo("Request Generated",
                               f"Title request file created:\n{path}\n\n"
                               "Open this file in Cursor and ask AI to generate a title.")
    
    def gen_title_for(self, conv_id):
        path = self.db.generate_title_request(conv_id)
        if path:
            messagebox.showinfo("Request Generated",
                               f"Title request file created:\n{path}\n\n"
                               "Open this file in Cursor and ask AI to generate a title.")
    
    def gen_summary_request(self):
        selected = self.tree.selection()
        if not selected:
            messagebox.showwarning("No Selection", "Please select a conversation first.")
            return
        
        conv_id = selected[0]
        path = self.db.generate_summary_request(conv_id)
        if path:
            messagebox.showinfo("Request Generated",
                               f"Summary request file created:\n{path}\n\n"
                               "Open this file in Cursor and ask AI to generate a summary.")
    
    def gen_category_request(self):
        selected = self.tree.selection()
        if not selected:
            messagebox.showwarning("No Selection", "Please select a conversation first.")
            return
        
        conv_id = selected[0]
        path = self.db.generate_category_request(conv_id)
        if path:
            messagebox.showinfo("Request Generated",
                               f"Category suggestion file created:\n{path}\n\n"
                               "Open this file in Cursor and ask AI to suggest a category.")
    
    def set_category_dialog(self, conv_id):
        dialog = tk.Toplevel(self)
        dialog.title("Set Category")
        dialog.geometry("300x150")
        dialog.configure(bg=self.colors["bg"])
        dialog.transient(self)
        dialog.grab_set()
        
        tk.Label(dialog, text="Select Category:", bg=self.colors["bg"],
                fg=self.colors["fg"], font=("Segoe UI", 10)).pack(pady=(20, 10))
        
        cat_names = [c["name"] for c in self.categories]
        cat_var = tk.StringVar(value=cat_names[0])
        cat_combo = ttk.Combobox(dialog, textvariable=cat_var, values=cat_names,
                                 state="readonly", font=("Segoe UI", 10))
        cat_combo.pack(fill="x", padx=20)
        
        def do_set():
            cat_name = cat_var.get()
            cat = next((c for c in self.categories if c["name"] == cat_name), None)
            if cat:
                self.db.set_category(conv_id, cat["id"])
            dialog.destroy()
            self.load_chats()
        
        ttk.Button(dialog, text="Set", command=do_set).pack(pady=20)


if __name__ == "__main__":
    # Standalone test
    root = tk.Tk()
    root.withdraw()
    
    colors = {
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
    }
    
    browser = EnhancedChatBrowser(root, colors)
    browser.mainloop()
