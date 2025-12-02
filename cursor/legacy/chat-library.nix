{pkgs, ...}:
pkgs.writers.writePython3Bin "cursor-chat-library"
{
  libraries = with pkgs.python3Packages; [tkinter];
  flakeIgnore = [
    "E501"
    "W503"
    "E302"
    "E305"
    "E306"
    "W291"
    "W293"
    "E127"
    "E128"
    "E226"
    "E701"
    "E722"
    "E741"
    "F401"
    "F841"
  ];
}
''
  """
  Cursor Chat Library v2.0 - VS Code-style UI Architecture
  Features:
  - Activity Bar (far left) - mode switching
  - Primary Sidebar (left) - context-sensitive panels
  - Editor Area (center) - tabbed content
  - Secondary Sidebar (right) - widgets/tools
  - Status Bar (bottom)
  - Widget/Plugin architecture for extensibility
  """
  import tkinter as tk
  from tkinter import ttk, messagebox, simpledialog
  import sqlite3
  import json
  import hashlib
  import re
  from pathlib import Path
  from datetime import datetime
  from typing import Optional, List, Dict, Any, Callable
  from abc import ABC, abstractmethod

  # ═══════════════════════════════════════════════════════════════════════════
  # Theme & Configuration
  # ═══════════════════════════════════════════════════════════════════════════

  CHAT_DB_DIR = Path.home() / ".config" / "cursor-manager"
  CHAT_DB_PATH = CHAT_DB_DIR / "chats.db"
  EXPORTS_DIR = CHAT_DB_DIR / "exports"
  CONTEXT_DIR = CHAT_DB_DIR / "context"

  # VS Code Dark+ Theme
  THEME = {
      "bg": "#1e1e1e",
      "editor_bg": "#1e1e1e",
      "sidebar_bg": "#252526",
      "activitybar_bg": "#333333",
      "statusbar_bg": "#007acc",
      "tab_bg": "#2d2d2d",
      "tab_active_bg": "#1e1e1e",
      "tab_border": "#252526",
      "fg": "#cccccc",
      "fg_dim": "#808080",
      "fg_bright": "#ffffff",
      "accent": "#0078d4",
      "accent_hover": "#1a8cff",
      "accent_dim": "#264f78",
      "border": "#3c3c3c",
      "success": "#3fb950",
      "warning": "#cca700",
      "error": "#f85149",
      "input_bg": "#3c3c3c",
      "input_fg": "#cccccc",
      "selection": "#264f78",
      "list_hover": "#2a2d2e",
      "list_active": "#37373d",
      "code_bg": "#1a1a1a",
      "h1": "#569cd6",
      "h2": "#4ec9b0",
      "h3": "#dcdcaa",
      "scrollbar_bg": "#1e1e1e",
      "scrollbar_thumb": "#424242",
  }

  DEFAULT_CATEGORIES = [
      ("Uncategorized", "#6e6e6e", "Not yet categorized"),
      ("Debugging", "#f85149", "Bug fixes"),
      ("Feature", "#3fb950", "New features"),
      ("Refactor", "#d29922", "Code cleanup"),
      ("Docs", "#0078d4", "Documentation"),
      ("Config", "#a371f7", "Configuration"),
      ("Learning", "#58a6ff", "Questions"),
      ("Architecture", "#f778ba", "Design"),
  ]

  SCHEMA = """
  CREATE TABLE IF NOT EXISTS conversations (
      id TEXT PRIMARY KEY,
      source_version TEXT NOT NULL,
      imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      original_title TEXT,
      ai_title TEXT,
      ai_summary TEXT,
      category_id INTEGER DEFAULT 1,
      user_tags TEXT DEFAULT '[]',
      message_count INTEGER DEFAULT 0,
      workspace_path TEXT,
      is_favorite INTEGER DEFAULT 0,
      is_archived INTEGER DEFAULT 0,
      content_hash TEXT
  );

  CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      role TEXT NOT NULL,
      content TEXT,
      raw_content TEXT,
      metadata TEXT DEFAULT '{}'
  );

  CREATE TABLE IF NOT EXISTS categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      color TEXT DEFAULT '#808080',
      description TEXT,
      sort_order INTEGER DEFAULT 0
  );

  CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
      content, conversation_id, content='messages', content_rowid='rowid'
  );

  CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
      INSERT INTO messages_fts(rowid, content, conversation_id)
      VALUES (new.rowid, new.content, new.conversation_id);
  END;

  CREATE INDEX IF NOT EXISTS idx_conv_cat ON conversations(category_id);
  CREATE INDEX IF NOT EXISTS idx_msg_conv ON messages(conversation_id);
  """

  # ═══════════════════════════════════════════════════════════════════════════
  # Database
  # ═══════════════════════════════════════════════════════════════════════════

  class ChatDatabase:
      _instance = None

      def __new__(cls):
          if cls._instance is None:
              cls._instance = super().__new__(cls)
              cls._instance._init()
          return cls._instance

      def _init(self):
          CHAT_DB_DIR.mkdir(parents=True, exist_ok=True)
          EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
          CONTEXT_DIR.mkdir(parents=True, exist_ok=True)

          conn = sqlite3.connect(str(CHAT_DB_PATH))
          conn.executescript(SCHEMA)
          cursor = conn.cursor()

          try:
              cursor.execute("ALTER TABLE conversations ADD COLUMN user_tags TEXT DEFAULT '[]'")
          except Exception:
              pass

          cursor.execute("SELECT COUNT(*) FROM categories")
          if cursor.fetchone()[0] == 0:
              for i, (name, color, desc) in enumerate(DEFAULT_CATEGORIES):
                  cursor.execute(
                      "INSERT INTO categories (name, color, description, sort_order) VALUES (?, ?, ?, ?)",
                      (name, color, desc, i)
                  )
          conn.commit()
          conn.close()

      def _connect(self):
          conn = sqlite3.connect(str(CHAT_DB_PATH))
          conn.row_factory = sqlite3.Row
          return conn

      def extract_content(self, msg_data: dict) -> str:
          """Extract text content from various Cursor message formats."""
          # Direct text field
          if msg_data.get("text"):
              return str(msg_data["text"])

          # rawText field
          if msg_data.get("rawText"):
              return str(msg_data["rawText"])

          # message field (some formats)
          if msg_data.get("message"):
              return str(msg_data["message"])

          # fullText (streaming result)
          if msg_data.get("fullText"):
              return str(msg_data["fullText"])

          # richText structure
          if "richText" in msg_data:
              try:
                  rt = msg_data["richText"]
                  if isinstance(rt, str):
                      rt = json.loads(rt)

                  texts = []
                  def extract(node):
                      if isinstance(node, dict):
                          if "text" in node:
                              texts.append(node["text"])
                          for child in node.get("children", []):
                              extract(child)
                      elif isinstance(node, list):
                          for item in node:
                              extract(item)

                  if "root" in rt:
                      extract(rt["root"])
                      return " ".join(texts)
              except Exception:
                  pass

          # capabilityStatuses sometimes contains text
          if "capabilityStatuses" in msg_data:
              try:
                  caps = msg_data["capabilityStatuses"]
                  if isinstance(caps, dict):
                      for status in caps.values():
                          if isinstance(status, dict) and "text" in status:
                              return str(status["text"])
              except Exception:
                  pass

          return ""

      def import_from_cursor(self, db_path: Path, version: str = "default"):
          if not db_path.exists():
              return {"imported": 0, "skipped": 0}

          results = {"imported": 0, "skipped": 0, "errors": []}

          try:
              src_conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
              src_conn.row_factory = sqlite3.Row
              src = src_conn.cursor()

              # Get all conversation IDs
              src.execute("SELECT DISTINCT substr(key, 10, 36) FROM cursorDiskKV WHERE key LIKE 'bubbleId:%'")
              conv_ids = [r[0] for r in src.fetchall()]

              dst_conn = self._connect()
              dst = dst_conn.cursor()

              for conv_id in conv_ids:
                  try:
                      src.execute("SELECT key, value FROM cursorDiskKV WHERE key LIKE ? ORDER BY key",
                                 (f"bubbleId:{conv_id}:%",))
                      rows = src.fetchall()

                      if not rows:
                          continue

                      # Create content hash
                      content_hash = hashlib.md5("".join(str(r[1]) for r in rows).encode()).hexdigest()

                      # Check duplicate
                      dst.execute("SELECT id FROM conversations WHERE content_hash = ?", (content_hash,))
                      if dst.fetchone():
                          results["skipped"] += 1
                          continue

                      messages = []
                      title_candidates = []

                      for i, (key, value) in enumerate(rows):
                          try:
                              data = json.loads(value) if isinstance(value, str) else json.loads(value.decode('utf-8'))
                              msg_id = key.split(":")[-1]

                              msg_type = data.get("type", 0)
                              role = "assistant" if msg_type == 1 else "user"
                              content = self.extract_content(data)

                              if role == "user" and content and len(title_candidates) < 3:
                                  title_candidates.append(content.replace("\n", " ").strip()[:100])

                              messages.append({
                                  "id": msg_id,
                                  "seq": i,
                                  "role": role,
                                  "content": content,
                                  "raw": value if isinstance(value, str) else value.decode('utf-8', errors='replace'),
                              })
                          except Exception as e:
                              results["errors"].append(str(e)[:50])

                      if not messages:
                          continue

                      title = (title_candidates[0][:57] + "...") if title_candidates and len(title_candidates[0]) > 60 else (title_candidates[0] if title_candidates else "Untitled")

                      dst.execute("""
                          INSERT INTO conversations (id, source_version, original_title, message_count, content_hash, category_id)
                          VALUES (?, ?, ?, ?, ?, 1)
                      """, (conv_id, version, title, len(messages), content_hash))

                      for msg in messages:
                          dst.execute("""
                              INSERT OR IGNORE INTO messages (id, conversation_id, sequence, role, content, raw_content)
                              VALUES (?, ?, ?, ?, ?, ?)
                          """, (msg["id"], conv_id, msg["seq"], msg["role"], msg["content"], msg["raw"]))

                      results["imported"] += 1
                  except Exception as e:
                      results["errors"].append(str(e)[:100])

              dst_conn.commit()
              dst_conn.close()
              src_conn.close()
          except Exception as e:
              results["errors"].append(str(e))

          return results

      def import_all(self):
          results = {"total_imported": 0, "total_skipped": 0}

          # Main Cursor
          main = Path.home() / ".config" / "Cursor" / "User" / "globalStorage" / "state.vscdb"
          if main.exists():
              r = self.import_from_cursor(main, "default")
              results["total_imported"] += r.get("imported", 0)
              results["total_skipped"] += r.get("skipped", 0)

          # Version-specific
          for p in Path.home().iterdir():
              if p.name.startswith(".cursor-") and p.is_dir():
                  ver = p.name.replace(".cursor-", "")
                  db = p / "User" / "globalStorage" / "state.vscdb"
                  if db.exists():
                      r = self.import_from_cursor(db, ver)
                      results["total_imported"] += r.get("imported", 0)
                      results["total_skipped"] += r.get("skipped", 0)

          return results

      def clear_all(self):
          conn = self._connect()
          conn.execute("DELETE FROM messages")
          conn.execute("DELETE FROM conversations")
          conn.commit()
          conn.close()

      def get_conversations(self, category_id=None, fav_only=False, search=None, limit=200):
          conn = self._connect()
          cur = conn.cursor()

          sql = """
              SELECT c.*, cat.name as category_name, cat.color as category_color
              FROM conversations c
              LEFT JOIN categories cat ON c.category_id = cat.id
              WHERE c.is_archived = 0
          """
          params = []

          if category_id:
              sql += " AND c.category_id = ?"
              params.append(category_id)

          if fav_only:
              sql += " AND c.is_favorite = 1"

          if search:
              sql = """
                  SELECT c.*, cat.name as category_name, cat.color as category_color
                  FROM conversations c
                  LEFT JOIN categories cat ON c.category_id = cat.id
                  WHERE c.id IN (SELECT DISTINCT conversation_id FROM messages_fts WHERE messages_fts MATCH ?)
                  AND c.is_archived = 0
              """
              params = [search]

          sql += " ORDER BY c.imported_at DESC LIMIT ?"
          params.append(limit)

          cur.execute(sql, params)
          rows = cur.fetchall()
          conn.close()
          return [dict(r) for r in rows]

      def get_conversation(self, conv_id):
          conn = self._connect()
          cur = conn.cursor()

          cur.execute("""
              SELECT c.*, cat.name as category_name FROM conversations c
              LEFT JOIN categories cat ON c.category_id = cat.id WHERE c.id = ?
          """, (conv_id,))
          conv = cur.fetchone()

          if not conv:
              conn.close()
              return None

          result = dict(conv)
          cur.execute("SELECT * FROM messages WHERE conversation_id = ? ORDER BY sequence", (conv_id,))
          result["messages"] = [dict(r) for r in cur.fetchall()]
          conn.close()
          return result

      def get_categories(self):
          conn = self._connect()
          cur = conn.cursor()
          cur.execute("SELECT * FROM categories ORDER BY sort_order")
          rows = cur.fetchall()
          conn.close()
          return [dict(r) for r in rows]

      def get_stats(self):
          conn = self._connect()
          cur = conn.cursor()

          cur.execute("SELECT COUNT(*) FROM conversations WHERE is_archived = 0")
          total = cur.fetchone()[0]

          cur.execute("SELECT COUNT(*) FROM messages")
          msgs = cur.fetchone()[0]

          cur.execute("SELECT COUNT(*) FROM conversations WHERE is_favorite = 1")
          favs = cur.fetchone()[0]

          cur.execute("SELECT source_version, COUNT(*) FROM conversations WHERE is_archived = 0 GROUP BY source_version")
          by_ver = {r[0]: r[1] for r in cur.fetchall()}

          conn.close()
          return {"total": total, "messages": msgs, "favorites": favs, "by_version": by_ver}

      def toggle_favorite(self, conv_id):
          conn = self._connect()
          conn.execute("UPDATE conversations SET is_favorite = NOT is_favorite WHERE id = ?", (conv_id,))
          conn.commit()
          conn.close()

      def update_category(self, conv_id, cat_id):
          conn = self._connect()
          conn.execute("UPDATE conversations SET category_id = ? WHERE id = ?", (cat_id, conv_id))
          conn.commit()
          conn.close()

      def add_tag(self, conv_id, tag):
          conn = self._connect()
          cur = conn.cursor()
          cur.execute("SELECT user_tags FROM conversations WHERE id = ?", (conv_id,))
          row = cur.fetchone()
          if row:
              tags = json.loads(row[0] or "[]")
              if tag not in tags:
                  tags.append(tag)
                  conn.execute("UPDATE conversations SET user_tags = ? WHERE id = ?", (json.dumps(tags), conv_id))
                  conn.commit()
          conn.close()

      def export_markdown(self, conv_id, output_dir=None):
          conv = self.get_conversation(conv_id)
          if not conv:
              return None

          out_dir = output_dir or EXPORTS_DIR
          out_dir.mkdir(parents=True, exist_ok=True)

          title = conv.get("ai_title") or conv.get("original_title") or "Untitled"
          safe = "".join(c if c.isalnum() or c in " -_" else "_" for c in title)[:40]
          path = out_dir / f"{datetime.now().strftime('%Y%m%d')}_{safe}_{conv_id[:8]}.md"

          lines = [f"# {title}\n"]
          for msg in conv.get("messages", []):
              role = "User" if msg["role"] == "user" else "Assistant"
              content = msg.get("content") or ""
              lines.append(f"\n## {role}\n\n{content}\n")

          path.write_text("\n".join(lines))
          return path

  # ═══════════════════════════════════════════════════════════════════════════
  # Widget Base Classes (Plugin Architecture)
  # ═══════════════════════════════════════════════════════════════════════════

  class Widget(ABC):
      """Base class for all widgets - enables plugin-like extensibility."""

      def __init__(self, parent, theme: dict, app: 'VSCodeApp'):
          self.parent = parent
          self.theme = theme
          self.app = app
          self.frame = tk.Frame(parent, bg=theme["sidebar_bg"])

      @property
      @abstractmethod
      def title(self) -> str:
          pass

      @property
      def icon(self) -> str:
          return "◼"

      @abstractmethod
      def build(self):
          pass

      def refresh(self):
          pass

      def pack(self, **kwargs):
          self.frame.pack(**kwargs)

      def pack_forget(self):
          self.frame.pack_forget()

  class TabContent(ABC):
      """Base class for tab content - enables modular editor tabs."""

      def __init__(self, parent, theme: dict, app: 'VSCodeApp'):
          self.parent = parent
          self.theme = theme
          self.app = app
          self.frame = tk.Frame(parent, bg=theme["editor_bg"])

      @property
      @abstractmethod
      def title(self) -> str:
          pass

      @property
      def can_close(self) -> bool:
          return True

      @abstractmethod
      def build(self):
          pass

      def on_focus(self):
          pass

      def on_blur(self):
          pass

  # ═══════════════════════════════════════════════════════════════════════════
  # Widgets
  # ═══════════════════════════════════════════════════════════════════════════

  class ExplorerWidget(Widget):
      """File explorer-style chat list."""

      title = "EXPLORER"
      icon = "📁"

      def build(self):
          self.frame.configure(bg=self.theme["sidebar_bg"])

          # Header
          hdr = tk.Frame(self.frame, bg=self.theme["sidebar_bg"])
          hdr.pack(fill="x", padx=10, pady=(10, 5))

          tk.Label(hdr, text=self.title, bg=self.theme["sidebar_bg"], fg=self.theme["fg_dim"],
                  font=("Segoe UI", 9, "bold")).pack(side="left")

          # Refresh button
          ref = tk.Label(hdr, text="↻", bg=self.theme["sidebar_bg"], fg=self.theme["fg_dim"],
                        font=("Segoe UI", 10), cursor="hand2")
          ref.pack(side="right")
          ref.bind("<Button-1>", lambda e: self.refresh())

          # Chat list
          list_frame = tk.Frame(self.frame, bg=self.theme["sidebar_bg"])
          list_frame.pack(fill="both", expand=True, padx=5)

          self.chat_list = tk.Frame(list_frame, bg=self.theme["sidebar_bg"])
          self.chat_list.pack(fill="both", expand=True)

          self.refresh()

      def refresh(self):
          for w in self.chat_list.winfo_children():
              w.destroy()

          db = ChatDatabase()
          convs = db.get_conversations(limit=50)

          for conv in convs:
              self._add_chat_item(conv)

      def _add_chat_item(self, conv):
          item = tk.Frame(self.chat_list, bg=self.theme["sidebar_bg"], cursor="hand2")
          item.pack(fill="x", pady=1)

          # Favorite indicator
          fav = "★" if conv.get("is_favorite") else "☆"
          fav_lbl = tk.Label(item, text=fav, bg=self.theme["sidebar_bg"],
                            fg=self.theme["warning"] if conv.get("is_favorite") else self.theme["fg_dim"],
                            font=("Segoe UI", 9), cursor="hand2")
          fav_lbl.pack(side="left", padx=(5, 2))
          fav_lbl.bind("<Button-1>", lambda e, c=conv: self._toggle_fav(c))

          # Title
          title = (conv.get("ai_title") or conv.get("original_title") or "Untitled")[:40]
          title_lbl = tk.Label(item, text=title, bg=self.theme["sidebar_bg"], fg=self.theme["fg"],
                              font=("Segoe UI", 9), anchor="w")
          title_lbl.pack(side="left", fill="x", expand=True, padx=2)

          # Message count
          cnt = tk.Label(item, text=str(conv.get("message_count", 0)),
                        bg=self.theme["sidebar_bg"], fg=self.theme["fg_dim"],
                        font=("Segoe UI", 8))
          cnt.pack(side="right", padx=5)

          # Bindings
          for w in [item, title_lbl]:
              w.bind("<Enter>", lambda e, i=item: i.configure(bg=self.theme["list_hover"]))
              w.bind("<Leave>", lambda e, i=item: i.configure(bg=self.theme["sidebar_bg"]))
              w.bind("<Button-1>", lambda e, c=conv: self.app.open_conversation(c["id"]))

      def _toggle_fav(self, conv):
          ChatDatabase().toggle_favorite(conv["id"])
          self.refresh()

  class SearchWidget(Widget):
      """Search across all chats."""

      title = "SEARCH"
      icon = "🔍"

      def build(self):
          self.frame.configure(bg=self.theme["sidebar_bg"])

          # Header
          tk.Label(self.frame, text=self.title, bg=self.theme["sidebar_bg"], fg=self.theme["fg_dim"],
                  font=("Segoe UI", 9, "bold")).pack(anchor="w", padx=10, pady=(10, 5))

          # Search input
          self.search_var = tk.StringVar()
          entry = tk.Entry(self.frame, textvariable=self.search_var, bg=self.theme["input_bg"],
                          fg=self.theme["input_fg"], font=("Segoe UI", 10), relief="flat",
                          insertbackground=self.theme["fg"])
          entry.pack(fill="x", padx=10, pady=5, ipady=5)
          entry.bind("<Return>", lambda e: self._search())

          # Results
          self.results = tk.Frame(self.frame, bg=self.theme["sidebar_bg"])
          self.results.pack(fill="both", expand=True, padx=5)

      def _search(self):
          for w in self.results.winfo_children():
              w.destroy()

          query = self.search_var.get().strip()
          if not query:
              return

          db = ChatDatabase()
          convs = db.get_conversations(search=query, limit=30)

          tk.Label(self.results, text=f"{len(convs)} results", bg=self.theme["sidebar_bg"],
                  fg=self.theme["fg_dim"], font=("Segoe UI", 8)).pack(anchor="w", padx=5, pady=5)

          for conv in convs:
              title = (conv.get("ai_title") or conv.get("original_title") or "Untitled")[:35]
              item = tk.Label(self.results, text=title, bg=self.theme["sidebar_bg"], fg=self.theme["fg"],
                             font=("Segoe UI", 9), anchor="w", cursor="hand2")
              item.pack(fill="x", padx=5, pady=1)
              item.bind("<Button-1>", lambda e, c=conv: self.app.open_conversation(c["id"]))
              item.bind("<Enter>", lambda e, i=item: i.configure(bg=self.theme["list_hover"]))
              item.bind("<Leave>", lambda e, i=item: i.configure(bg=self.theme["sidebar_bg"]))

  class FilterWidget(Widget):
      """Category and version filters."""

      title = "FILTERS"
      icon = "⚙"

      def build(self):
          self.frame.configure(bg=self.theme["sidebar_bg"])

          tk.Label(self.frame, text=self.title, bg=self.theme["sidebar_bg"], fg=self.theme["fg_dim"],
                  font=("Segoe UI", 9, "bold")).pack(anchor="w", padx=10, pady=(10, 5))

          # Category filter
          tk.Label(self.frame, text="Category", bg=self.theme["sidebar_bg"], fg=self.theme["fg_dim"],
                  font=("Segoe UI", 8)).pack(anchor="w", padx=10)

          cats = ChatDatabase().get_categories()
          cat_names = ["All"] + [c["name"] for c in cats]

          self.cat_var = tk.StringVar(value="All")
          cat_cb = ttk.Combobox(self.frame, textvariable=self.cat_var, values=cat_names,
                               state="readonly", font=("Segoe UI", 9))
          cat_cb.pack(fill="x", padx=10, pady=5)
          cat_cb.bind("<<ComboboxSelected>>", lambda e: self.app.refresh_explorer())

          # Favorites only
          self.fav_var = tk.BooleanVar(value=False)
          fav = tk.Checkbutton(self.frame, text="Favorites only", variable=self.fav_var,
                              bg=self.theme["sidebar_bg"], fg=self.theme["fg"],
                              selectcolor=self.theme["input_bg"], highlightthickness=0,
                              command=self.app.refresh_explorer)
          fav.pack(anchor="w", padx=10, pady=5)

  class ToolsWidget(Widget):
      """Quick action tools."""

      title = "TOOLS"
      icon = "🛠"

      def build(self):
          self.frame.configure(bg=self.theme["sidebar_bg"])

          tk.Label(self.frame, text=self.title, bg=self.theme["sidebar_bg"], fg=self.theme["fg_dim"],
                  font=("Segoe UI", 9, "bold")).pack(anchor="w", padx=10, pady=(10, 10))

          tools = [
              ("↻ Import Chats", self._import),
              ("🗑 Clear & Reimport", self._clear_reimport),
              ("⬇ Export All", self._export_all),
              ("📊 Show Stats", self._show_stats),
          ]

          for text, cmd in tools:
              btn = tk.Label(self.frame, text=text, bg=self.theme["sidebar_bg"], fg=self.theme["fg"],
                            font=("Segoe UI", 9), pady=6, cursor="hand2")
              btn.pack(fill="x", padx=10, pady=1)
              btn.bind("<Button-1>", lambda e, c=cmd: c())
              btn.bind("<Enter>", lambda e, b=btn: b.configure(bg=self.theme["list_hover"]))
              btn.bind("<Leave>", lambda e, b=btn: b.configure(bg=self.theme["sidebar_bg"]))

      def _import(self):
          db = ChatDatabase()
          results = db.import_all()
          messagebox.showinfo("Import", f"Imported: {results['total_imported']}\nSkipped: {results['total_skipped']}")
          self.app.refresh_explorer()

      def _clear_reimport(self):
          if messagebox.askyesno("Confirm", "Delete all and reimport?"):
              db = ChatDatabase()
              db.clear_all()
              results = db.import_all()
              messagebox.showinfo("Done", f"Imported: {results['total_imported']}")
              self.app.refresh_explorer()

      def _export_all(self):
          db = ChatDatabase()
          convs = db.get_conversations(limit=1000)
          count = 0
          for c in convs:
              if db.export_markdown(c["id"]):
                  count += 1
          messagebox.showinfo("Export", f"Exported {count} to:\n{EXPORTS_DIR}")

      def _show_stats(self):
          stats = ChatDatabase().get_stats()
          msg = f"Conversations: {stats['total']}\nMessages: {stats['messages']}\nFavorites: {stats['favorites']}"
          messagebox.showinfo("Stats", msg)

  class TagsWidget(Widget):
      """User tags for current conversation."""

      title = "TAGS"
      icon = "🏷"

      def __init__(self, *args, **kwargs):
          super().__init__(*args, **kwargs)
          self.current_conv_id = None

      def build(self):
          self.frame.configure(bg=self.theme["sidebar_bg"])

          hdr = tk.Frame(self.frame, bg=self.theme["sidebar_bg"])
          hdr.pack(fill="x", padx=10, pady=(10, 5))

          tk.Label(hdr, text=self.title, bg=self.theme["sidebar_bg"], fg=self.theme["fg_dim"],
                  font=("Segoe UI", 9, "bold")).pack(side="left")

          add_btn = tk.Label(hdr, text="+", bg=self.theme["sidebar_bg"], fg=self.theme["accent"],
                            font=("Segoe UI", 12, "bold"), cursor="hand2")
          add_btn.pack(side="right")
          add_btn.bind("<Button-1>", lambda e: self._add_tag())

          self.tags_frame = tk.Frame(self.frame, bg=self.theme["sidebar_bg"])
          self.tags_frame.pack(fill="both", expand=True, padx=10)

      def set_conversation(self, conv_id):
          self.current_conv_id = conv_id
          self.refresh()

      def refresh(self):
          for w in self.tags_frame.winfo_children():
              w.destroy()

          if not self.current_conv_id:
              tk.Label(self.tags_frame, text="No chat selected", bg=self.theme["sidebar_bg"],
                      fg=self.theme["fg_dim"], font=("Segoe UI", 8)).pack()
              return

          conv = ChatDatabase().get_conversation(self.current_conv_id)
          if not conv:
              return

          tags = json.loads(conv.get("user_tags") or "[]")

          if not tags:
              tk.Label(self.tags_frame, text="No tags yet", bg=self.theme["sidebar_bg"],
                      fg=self.theme["fg_dim"], font=("Segoe UI", 8)).pack()
              return

          for tag in tags:
              tag_lbl = tk.Label(self.tags_frame, text=tag, bg=self.theme["accent_dim"],
                                fg=self.theme["fg"], font=("Segoe UI", 8), padx=8, pady=2)
              tag_lbl.pack(side="left", padx=2, pady=2)

      def _add_tag(self):
          if not self.current_conv_id:
              return

          tag = simpledialog.askstring("Add Tag", "Enter tag:", parent=self.frame)
          if tag:
              ChatDatabase().add_tag(self.current_conv_id, tag.strip())
              self.refresh()

  # ═══════════════════════════════════════════════════════════════════════════
  # Tab Contents
  # ═══════════════════════════════════════════════════════════════════════════

  class DashboardTab(TabContent):
      """Welcome/Dashboard tab - always open."""

      title = "Dashboard"
      can_close = False

      def build(self):
          self.frame.configure(bg=self.theme["editor_bg"])

          # Center content
          center = tk.Frame(self.frame, bg=self.theme["editor_bg"])
          center.place(relx=0.5, rely=0.4, anchor="center")

          tk.Label(center, text="CURSOR", bg=self.theme["editor_bg"], fg=self.theme["fg"],
                  font=("Segoe UI", 32, "bold")).pack()
          tk.Label(center, text="CHAT LIBRARY", bg=self.theme["editor_bg"], fg=self.theme["accent"],
                  font=("Segoe UI", 32, "bold")).pack()
          tk.Label(center, text="v2.0", bg=self.theme["editor_bg"], fg=self.theme["fg_dim"],
                  font=("Segoe UI", 12)).pack(pady=(5, 20))

          # Stats
          stats = ChatDatabase().get_stats()
          stats_txt = f"📊 {stats['total']} chats  •  💬 {stats['messages']} messages  •  ⭐ {stats['favorites']} favorites"
          tk.Label(center, text=stats_txt, bg=self.theme["editor_bg"], fg=self.theme["fg_dim"],
                  font=("Segoe UI", 10)).pack(pady=10)

          # Quick actions
          actions = tk.Frame(center, bg=self.theme["editor_bg"])
          actions.pack(pady=20)

          for text, cmd in [("Import from Cursor", self._import), ("Open Random Chat", self._random)]:
              btn = tk.Label(actions, text=text, bg=self.theme["accent_dim"], fg=self.theme["fg"],
                            font=("Segoe UI", 10), padx=20, pady=10, cursor="hand2")
              btn.pack(side="left", padx=10)
              btn.bind("<Button-1>", lambda e, c=cmd: c())
              btn.bind("<Enter>", lambda e, b=btn: b.configure(bg=self.theme["accent"]))
              btn.bind("<Leave>", lambda e, b=btn: b.configure(bg=self.theme["accent_dim"]))

      def _import(self):
          results = ChatDatabase().import_all()
          messagebox.showinfo("Import", f"Imported: {results['total_imported']}\nSkipped: {results['total_skipped']}")
          self.app.refresh_explorer()
          self.build()  # Refresh stats

      def _random(self):
          import random
          convs = ChatDatabase().get_conversations(limit=100)
          if convs:
              c = random.choice(convs)
              self.app.open_conversation(c["id"])

  class ConversationTab(TabContent):
      """Displays a single conversation with markdown rendering."""

      def __init__(self, parent, theme, app, conv_id):
          super().__init__(parent, theme, app)
          self.conv_id = conv_id
          self.conv = ChatDatabase().get_conversation(conv_id)
          self._title = (self.conv.get("ai_title") or self.conv.get("original_title") or "Chat")[:25] if self.conv else "Chat"

      @property
      def title(self):
          return self._title

      def build(self):
          self.frame.configure(bg=self.theme["editor_bg"])

          if not self.conv:
              tk.Label(self.frame, text="Conversation not found", bg=self.theme["editor_bg"],
                      fg=self.theme["error"]).pack(expand=True)
              return

          # Header bar
          header = tk.Frame(self.frame, bg=self.theme["sidebar_bg"], pady=10, padx=15)
          header.pack(fill="x")

          title = self.conv.get("ai_title") or self.conv.get("original_title") or "Untitled"
          tk.Label(header, text=title[:60], bg=self.theme["sidebar_bg"], fg=self.theme["fg"],
                  font=("Segoe UI", 12, "bold")).pack(side="left")

          info = f"{self.conv.get('message_count', 0)} msgs • {self.conv.get('category_name', 'Uncategorized')}"
          tk.Label(header, text=info, bg=self.theme["sidebar_bg"], fg=self.theme["fg_dim"],
                  font=("Segoe UI", 9)).pack(side="right")

          # View mode toggle
          self.view_mode = tk.StringVar(value="rendered")
          toggle = tk.Frame(header, bg=self.theme["sidebar_bg"])
          toggle.pack(side="right", padx=20)

          for mode, txt in [("rendered", "Rendered"), ("raw", "Raw")]:
              btn = tk.Label(toggle, text=txt, bg=self.theme["sidebar_bg"], fg=self.theme["fg_dim"],
                            font=("Segoe UI", 8), padx=8, pady=2, cursor="hand2")
              btn.pack(side="left", padx=2)
              btn.bind("<Button-1>", lambda e, m=mode: self._set_mode(m))

          # Content area
          content = tk.Frame(self.frame, bg=self.theme["editor_bg"])
          content.pack(fill="both", expand=True, padx=15, pady=10)

          self.text = tk.Text(content, bg=self.theme["editor_bg"], fg=self.theme["fg"],
                             font=("Consolas", 10), wrap="word", relief="flat", padx=10, pady=10,
                             insertbackground=self.theme["fg"], borderwidth=0, highlightthickness=0)

          scrollbar = tk.Frame(content, bg=self.theme["scrollbar_bg"], width=10)
          scrollbar.pack(side="right", fill="y")

          self.text.pack(side="left", fill="both", expand=True)

          self._setup_tags()
          self._render()

      def _setup_tags(self):
          self.text.tag_configure("user", foreground=self.theme["accent"], font=("Segoe UI", 11, "bold"))
          self.text.tag_configure("assistant", foreground=self.theme["success"], font=("Segoe UI", 11, "bold"))
          self.text.tag_configure("sep", foreground=self.theme["border"])
          self.text.tag_configure("h1", foreground=self.theme["h1"], font=("Segoe UI", 14, "bold"))
          self.text.tag_configure("h2", foreground=self.theme["h2"], font=("Segoe UI", 12, "bold"))
          self.text.tag_configure("h3", foreground=self.theme["h3"], font=("Segoe UI", 11, "bold"))
          self.text.tag_configure("code", foreground="#d7ba7d", background=self.theme["code_bg"], font=("Consolas", 9))
          self.text.tag_configure("codeblock", foreground=self.theme["fg"], background=self.theme["code_bg"],
                                 font=("Consolas", 9), lmargin1=10, lmargin2=10)

      def _set_mode(self, mode):
          self.view_mode.set(mode)
          self._render()

      def _render(self):
          self.text.config(state="normal")
          self.text.delete("1.0", "end")

          for msg in self.conv.get("messages", []):
              role = msg.get("role", "user")
              content = msg.get("content") or ""

              if role == "user":
                  self.text.insert("end", "\n👤 USER\n", "user")
              else:
                  self.text.insert("end", "\n🤖 ASSISTANT\n", "assistant")

              self.text.insert("end", "─" * 60 + "\n", "sep")

              if self.view_mode.get() == "rendered":
                  self._render_markdown(content)
              else:
                  self.text.insert("end", content + "\n")

              self.text.insert("end", "\n")

          self.text.config(state="disabled")

      def _render_markdown(self, content):
          if not content:
              return

          lines = content.split("\n")
          i = 0
          in_code = False
          code_lines = []

          while i < len(lines):
              line = lines[i]

              if line.startswith("```"):
                  if in_code:
                      self.text.insert("end", "\n".join(code_lines) + "\n", "codeblock")
                      code_lines = []
                      in_code = False
                  else:
                      in_code = True
                  i += 1
                  continue

              if in_code:
                  code_lines.append(line)
                  i += 1
                  continue

              if line.startswith("### "):
                  self.text.insert("end", line[4:] + "\n", "h3")
              elif line.startswith("## "):
                  self.text.insert("end", line[3:] + "\n", "h2")
              elif line.startswith("# "):
                  self.text.insert("end", line[2:] + "\n", "h1")
              elif line.strip() in ["---", "***"]:
                  self.text.insert("end", "─" * 40 + "\n", "sep")
              elif line.strip().startswith("- "):
                  self.text.insert("end", "  • " + line.strip()[2:] + "\n")
              else:
                  # Inline code
                  parts = re.split(r'(`[^`]+`)', line)
                  for part in parts:
                      if part.startswith('`') and part.endswith('`'):
                          self.text.insert("end", part[1:-1], "code")
                      else:
                          self.text.insert("end", part)
                  self.text.insert("end", "\n")

              i += 1

      def on_focus(self):
          # Update tags widget
          if hasattr(self.app, 'tags_widget'):
              self.app.tags_widget.set_conversation(self.conv_id)

  # ═══════════════════════════════════════════════════════════════════════════
  # Main Application
  # ═══════════════════════════════════════════════════════════════════════════

  class VSCodeApp(tk.Tk):
      """VS Code-style application with modular widget architecture."""

      def __init__(self):
          super().__init__()
          self.theme = THEME
          self.tabs = {}
          self.active_tab = None
          self.widgets_left = []
          self.widgets_right = []

          self.title("Cursor Chat Library")
          self.geometry("1400x900")
          self.configure(bg=self.theme["bg"])
          self.minsize(1100, 700)

          self._setup_styles()
          self._build_layout()
          self._register_widgets()
          self._open_dashboard()

      def _setup_styles(self):
          style = ttk.Style()
          style.theme_use('clam')

          style.configure("TCombobox", fieldbackground=self.theme["input_bg"],
                         background=self.theme["input_bg"], foreground=self.theme["input_fg"],
                         borderwidth=0, arrowcolor=self.theme["fg"])
          style.map("TCombobox", fieldbackground=[("readonly", self.theme["input_bg"])])

          self.option_add("*TCombobox*Listbox.background", self.theme["input_bg"])
          self.option_add("*TCombobox*Listbox.foreground", self.theme["input_fg"])

      def _build_layout(self):
          # Main container
          main = tk.Frame(self, bg=self.theme["bg"])
          main.pack(fill="both", expand=True)

          # Activity Bar (far left - icons)
          self.activity_bar = tk.Frame(main, bg=self.theme["activitybar_bg"], width=48)
          self.activity_bar.pack(side="left", fill="y")
          self.activity_bar.pack_propagate(False)

          # Primary Sidebar (left)
          self.sidebar_left = tk.Frame(main, bg=self.theme["sidebar_bg"], width=260)
          self.sidebar_left.pack(side="left", fill="y")
          self.sidebar_left.pack_propagate(False)

          # Right section (editor + optional right sidebar)
          right_section = tk.Frame(main, bg=self.theme["bg"])
          right_section.pack(side="left", fill="both", expand=True)

          # Secondary Sidebar (right) - initially hidden
          self.sidebar_right = tk.Frame(right_section, bg=self.theme["sidebar_bg"], width=220)
          self.sidebar_right_visible = False

          # Editor area (center)
          self.editor_area = tk.Frame(right_section, bg=self.theme["editor_bg"])
          self.editor_area.pack(side="left", fill="both", expand=True)

          # Tab bar
          self.tab_bar = tk.Frame(self.editor_area, bg=self.theme["tab_bg"], height=35)
          self.tab_bar.pack(fill="x")
          self.tab_bar.pack_propagate(False)

          # Tab content area
          self.tab_content = tk.Frame(self.editor_area, bg=self.theme["editor_bg"])
          self.tab_content.pack(fill="both", expand=True)

          # Status Bar (bottom)
          self.status_bar = tk.Frame(self, bg=self.theme["statusbar_bg"], height=22)
          self.status_bar.pack(side="bottom", fill="x")
          self.status_bar.pack_propagate(False)

          self._build_activity_bar()
          self._build_status_bar()

      def _build_activity_bar(self):
          # Activity bar icons for different modes
          modes = [
              ("📁", "Explorer", self._show_explorer),
              ("🔍", "Search", self._show_search),
              ("⚙", "Settings", self._show_settings),
          ]

          for icon, tooltip, cmd in modes:
              btn = tk.Label(self.activity_bar, text=icon, bg=self.theme["activitybar_bg"],
                            fg=self.theme["fg_dim"], font=("Segoe UI", 16), pady=10, cursor="hand2")
              btn.pack(fill="x")
              btn.bind("<Button-1>", lambda e, c=cmd: c())
              btn.bind("<Enter>", lambda e, b=btn: b.configure(fg=self.theme["fg"]))
              btn.bind("<Leave>", lambda e, b=btn: b.configure(fg=self.theme["fg_dim"]))

          # Toggle right sidebar at bottom
          tk.Frame(self.activity_bar, bg=self.theme["activitybar_bg"]).pack(fill="both", expand=True)

          toggle_right = tk.Label(self.activity_bar, text="◧", bg=self.theme["activitybar_bg"],
                                 fg=self.theme["fg_dim"], font=("Segoe UI", 14), pady=10, cursor="hand2")
          toggle_right.pack(side="bottom", fill="x")
          toggle_right.bind("<Button-1>", lambda e: self._toggle_right_sidebar())

      def _build_status_bar(self):
          # Left side - stats
          self.status_left = tk.Label(self.status_bar, text="Loading...",
                                     bg=self.theme["statusbar_bg"], fg="white",
                                     font=("Segoe UI", 9), padx=10)
          self.status_left.pack(side="left")

          # Right side - version
          tk.Label(self.status_bar, text="v2.0", bg=self.theme["statusbar_bg"], fg="white",
                  font=("Segoe UI", 9), padx=10).pack(side="right")

          self._update_status()

      def _update_status(self):
          stats = ChatDatabase().get_stats()
          self.status_left.config(text=f"📊 {stats['total']} chats  •  💬 {stats['messages']} messages")

      def _register_widgets(self):
          # Clear existing widgets
          for w in self.sidebar_left.winfo_children():
              w.destroy()

          # Create and register left sidebar widgets
          self.explorer_widget = ExplorerWidget(self.sidebar_left, self.theme, self)
          self.search_widget = SearchWidget(self.sidebar_left, self.theme, self)
          self.filter_widget = FilterWidget(self.sidebar_left, self.theme, self)

          self.widgets_left = [self.explorer_widget, self.search_widget, self.filter_widget]

          # Right sidebar widgets
          self.tools_widget = ToolsWidget(self.sidebar_right, self.theme, self)
          self.tags_widget = TagsWidget(self.sidebar_right, self.theme, self)

          self.widgets_right = [self.tools_widget, self.tags_widget]

          # Show default view
          self._show_explorer()

      def _show_explorer(self):
          for w in self.widgets_left:
              w.pack_forget()

          self.explorer_widget.build()
          self.explorer_widget.pack(fill="both", expand=True)

          self.filter_widget.build()
          self.filter_widget.pack(fill="x", side="bottom")

      def _show_search(self):
          for w in self.widgets_left:
              w.pack_forget()

          self.search_widget.build()
          self.search_widget.pack(fill="both", expand=True)

      def _show_settings(self):
          messagebox.showinfo("Settings", "Settings panel coming soon!")

      def _toggle_right_sidebar(self):
          if self.sidebar_right_visible:
              self.sidebar_right.pack_forget()
              self.sidebar_right_visible = False
          else:
              self.sidebar_right.pack(side="right", fill="y", before=self.editor_area)

              for w in self.widgets_right:
                  w.build()
                  w.pack(fill="x")

              self.sidebar_right_visible = True

      def refresh_explorer(self):
          if hasattr(self, 'explorer_widget'):
              self.explorer_widget.refresh()
          self._update_status()

      def _open_dashboard(self):
          tab = DashboardTab(self.tab_content, self.theme, self)
          tab.build()
          self._add_tab("dashboard", tab)

      def open_conversation(self, conv_id):
          # Check if already open
          if conv_id in self.tabs:
              self._activate_tab(conv_id)
              return

          tab = ConversationTab(self.tab_content, self.theme, self, conv_id)
          tab.build()
          self._add_tab(conv_id, tab)

      def _add_tab(self, tab_id, tab_content):
          self.tabs[tab_id] = tab_content
          self._refresh_tab_bar()
          self._activate_tab(tab_id)

      def _refresh_tab_bar(self):
          for w in self.tab_bar.winfo_children():
              w.destroy()

          for tab_id, tab in self.tabs.items():
              is_active = tab_id == self.active_tab

              tab_frame = tk.Frame(self.tab_bar, bg=self.theme["tab_active_bg"] if is_active else self.theme["tab_bg"])
              tab_frame.pack(side="left", padx=(0, 1))

              title_lbl = tk.Label(tab_frame, text=tab.title,
                                  bg=tab_frame.cget("bg"), fg=self.theme["fg"] if is_active else self.theme["fg_dim"],
                                  font=("Segoe UI", 9), padx=10, pady=5, cursor="hand2")
              title_lbl.pack(side="left")
              title_lbl.bind("<Button-1>", lambda e, tid=tab_id: self._activate_tab(tid))

              if tab.can_close:
                  close_lbl = tk.Label(tab_frame, text="×", bg=tab_frame.cget("bg"),
                                      fg=self.theme["fg_dim"], font=("Segoe UI", 10), padx=5, cursor="hand2")
                  close_lbl.pack(side="left")
                  close_lbl.bind("<Button-1>", lambda e, tid=tab_id: self._close_tab(tid))
                  close_lbl.bind("<Enter>", lambda e, l=close_lbl: l.configure(fg=self.theme["error"]))
                  close_lbl.bind("<Leave>", lambda e, l=close_lbl: l.configure(fg=self.theme["fg_dim"]))

      def _activate_tab(self, tab_id):
          if self.active_tab:
              self.tabs[self.active_tab].frame.pack_forget()
              self.tabs[self.active_tab].on_blur()

          self.active_tab = tab_id
          self.tabs[tab_id].frame.pack(fill="both", expand=True)
          self.tabs[tab_id].on_focus()
          self._refresh_tab_bar()

      def _close_tab(self, tab_id):
          if tab_id not in self.tabs:
              return

          tab = self.tabs[tab_id]
          if not tab.can_close:
              return

          tab.frame.destroy()
          del self.tabs[tab_id]

          if self.active_tab == tab_id:
              # Activate another tab
              if self.tabs:
                  self._activate_tab(list(self.tabs.keys())[0])
              else:
                  self.active_tab = None
          else:
              self._refresh_tab_bar()


  if __name__ == "__main__":
      app = VSCodeApp()
      app.mainloop()
''
