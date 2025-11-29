{ pkgs, ... }:

pkgs.writers.writePython3Bin "cursor-chat-library"
  {
    libraries = with pkgs.python3Packages; [
      tkinter
    ];
    flakeIgnore = [
      "E501" "W503" "E302" "E305" "W291" "W293" "E127" "E128" "E226" "E701" "E722"
    ];
  }
  ''
"""
Cursor Chat Library - Full-featured chat management with markdown preview
"""
import tkinter as tk
from tkinter import ttk, messagebox, filedialog
from tkinter import font as tkfont
import sqlite3
import json
import hashlib
import re
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Any

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

CHAT_DB_DIR = Path.home() / ".config" / "cursor-manager"
CHAT_DB_PATH = CHAT_DB_DIR / "chats.db"
EXPORTS_DIR = CHAT_DB_DIR / "exports"
CONTEXT_DIR = CHAT_DB_DIR / "context"

DEFAULT_CATEGORIES = [
    ("General", "#808080", "Uncategorized conversations"),
    ("Debugging", "#f85149", "Bug fixes and troubleshooting"),
    ("Feature Development", "#3fb950", "New feature implementation"),
    ("Refactoring", "#d29922", "Code cleanup and optimization"),
    ("Documentation", "#0078d4", "Docs, comments, READMEs"),
    ("Configuration", "#a371f7", "Config files, settings, setup"),
    ("Learning", "#58a6ff", "Questions, explanations, tutorials"),
    ("Architecture", "#f778ba", "Design decisions, planning"),
]

COLORS = {
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
    "code_bg": "#1a1a1a",
    "header1": "#569cd6",
    "header2": "#4ec9b0",
    "header3": "#dcdcaa",
    "bold": "#ffffff",
    "italic": "#ce9178",
    "link": "#3794ff",
    "inline_code": "#d7ba7d",
}

SCHEMA = """
CREATE TABLE IF NOT EXISTS conversations (
    id TEXT PRIMARY KEY,
    source_version TEXT NOT NULL,
    imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    original_title TEXT,
    ai_title TEXT,
    ai_summary TEXT,
    category_id INTEGER DEFAULT 1,
    tags TEXT DEFAULT '[]',
    message_count INTEGER DEFAULT 0,
    first_message_at TIMESTAMP,
    last_message_at TIMESTAMP,
    workspace_path TEXT,
    exported_at TIMESTAMP,
    is_favorite INTEGER DEFAULT 0,
    is_archived INTEGER DEFAULT 0,
    content_hash TEXT,
    FOREIGN KEY (category_id) REFERENCES categories(id)
);

CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL,
    sequence INTEGER NOT NULL,
    role TEXT NOT NULL,
    content TEXT,
    raw_content TEXT,
    timestamp TIMESTAMP,
    metadata TEXT DEFAULT '{}',
    FOREIGN KEY (conversation_id) REFERENCES conversations(id)
);

CREATE TABLE IF NOT EXISTS categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    color TEXT DEFAULT '#808080',
    description TEXT,
    sort_order INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS exports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id TEXT,
    exported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    export_path TEXT NOT NULL,
    format TEXT NOT NULL,
    include_metadata INTEGER DEFAULT 0,
    FOREIGN KEY (conversation_id) REFERENCES conversations(id)
);

CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
    content, conversation_id, content='messages', content_rowid='rowid'
);

CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
    INSERT INTO messages_fts(rowid, content, conversation_id) 
    VALUES (new.rowid, new.content, new.conversation_id);
END;

CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_conv_category ON conversations(category_id);
"""

# ═══════════════════════════════════════════════════════════════════════════
# Database Class
# ═══════════════════════════════════════════════════════════════════════════

class ChatDatabase:
    def __init__(self, db_path: Path = CHAT_DB_PATH):
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
        CONTEXT_DIR.mkdir(parents=True, exist_ok=True)
        self._init_db()
    
    def _init_db(self):
        conn = sqlite3.connect(str(self.db_path))
        conn.executescript(SCHEMA)
        cursor = conn.cursor()
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
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        return conn
    
    def import_from_cursor(self, cursor_db_path: Path, version: str = "default"):
        if not cursor_db_path.exists():
            return {"success": False, "error": "Database not found", "imported": 0}
        
        results = {"success": True, "imported": 0, "skipped": 0, "errors": []}
        
        try:
            cursor_conn = sqlite3.connect(f"file:{cursor_db_path}?mode=ro", uri=True)
            cursor_conn.row_factory = sqlite3.Row
            cursor = cursor_conn.cursor()
            
            cursor.execute("""
                SELECT DISTINCT substr(key, 10, 36) as conv_id 
                FROM cursorDiskKV WHERE key LIKE 'bubbleId:%'
            """)
            conv_ids = [row[0] for row in cursor.fetchall()]
            
            our_conn = self._connect()
            our_cursor = our_conn.cursor()
            
            for conv_id in conv_ids:
                try:
                    cursor.execute("""
                        SELECT key, value FROM cursorDiskKV 
                        WHERE key LIKE ? ORDER BY key
                    """, (f"bubbleId:{conv_id}:%",))
                    
                    messages_data = cursor.fetchall()
                    if not messages_data:
                        continue
                    
                    content_hash = hashlib.md5(
                        "".join(str(m[1]) for m in messages_data).encode()
                    ).hexdigest()
                    
                    our_cursor.execute(
                        "SELECT id FROM conversations WHERE content_hash = ?", 
                        (content_hash,)
                    )
                    if our_cursor.fetchone():
                        results["skipped"] += 1
                        continue
                    
                    messages = []
                    title_candidates = []
                    
                    for i, (key, value) in enumerate(messages_data):
                        try:
                            msg = json.loads(value)
                            msg_id = key.split(":")[-1]
                            role = "assistant" if msg.get("type") == 1 else "user"
                            content = msg.get("text") or msg.get("rawText") or ""
                            
                            if role == "user" and content and len(title_candidates) < 3:
                                title_candidates.append(content[:100])
                            
                            messages.append({
                                "id": msg_id, "sequence": i, "role": role,
                                "content": content, "raw": value,
                                "metadata": json.dumps({"type": msg.get("type")})
                            })
                        except Exception:
                            pass
                    
                    if not messages:
                        continue
                    
                    title = title_candidates[0][:57] + "..." if title_candidates and len(title_candidates[0]) > 60 else (title_candidates[0] if title_candidates else "Untitled Chat")
                    
                    our_cursor.execute("""
                        INSERT INTO conversations 
                        (id, source_version, original_title, message_count, content_hash)
                        VALUES (?, ?, ?, ?, ?)
                    """, (conv_id, version, title, len(messages), content_hash))
                    
                    for msg in messages:
                        our_cursor.execute("""
                            INSERT OR IGNORE INTO messages 
                            (id, conversation_id, sequence, role, content, raw_content, metadata)
                            VALUES (?, ?, ?, ?, ?, ?, ?)
                        """, (msg["id"], conv_id, msg["sequence"], msg["role"], 
                              msg["content"], msg["raw"], msg["metadata"]))
                    
                    results["imported"] += 1
                except Exception as e:
                    results["errors"].append(str(e))
            
            our_conn.commit()
            our_conn.close()
            cursor_conn.close()
        except Exception as e:
            results["success"] = False
            results["error"] = str(e)
        
        return results
    
    def import_all_versions(self):
        cursor_config = Path.home() / ".config" / "Cursor"
        results = {"versions": {}, "total_imported": 0, "total_skipped": 0}
        
        main_db = cursor_config / "User" / "globalStorage" / "state.vscdb"
        if main_db.exists():
            r = self.import_from_cursor(main_db, "default")
            results["versions"]["default"] = r
            results["total_imported"] += r.get("imported", 0)
            results["total_skipped"] += r.get("skipped", 0)
        
        for p in Path.home().iterdir():
            if p.name.startswith(".cursor-") and p.is_dir():
                ver = p.name.replace(".cursor-", "")
                db_path = p / "User" / "globalStorage" / "state.vscdb"
                if db_path.exists():
                    r = self.import_from_cursor(db_path, ver)
                    results["versions"][ver] = r
                    results["total_imported"] += r.get("imported", 0)
                    results["total_skipped"] += r.get("skipped", 0)
        
        return results
    
    def get_conversations(self, category_id=None, favorites_only=False, search=None, limit=100, offset=0):
        conn = self._connect()
        cursor = conn.cursor()
        
        query = """
            SELECT c.*, cat.name as category_name, cat.color as category_color
            FROM conversations c
            LEFT JOIN categories cat ON c.category_id = cat.id
            WHERE c.is_archived = 0
        """
        params = []
        
        if category_id:
            query += " AND c.category_id = ?"
            params.append(category_id)
        
        if favorites_only:
            query += " AND c.is_favorite = 1"
        
        if search:
            query = """
                SELECT c.*, cat.name as category_name, cat.color as category_color
                FROM conversations c
                LEFT JOIN categories cat ON c.category_id = cat.id
                WHERE c.id IN (
                    SELECT DISTINCT conversation_id FROM messages_fts WHERE messages_fts MATCH ?
                ) AND c.is_archived = 0
            """
            params = [search]
        
        query += " ORDER BY c.imported_at DESC LIMIT ? OFFSET ?"
        params.extend([limit, offset])
        
        cursor.execute(query, params)
        rows = cursor.fetchall()
        conn.close()
        return [dict(row) for row in rows]
    
    def get_conversation(self, conv_id):
        conn = self._connect()
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT c.*, cat.name as category_name, cat.color as category_color
            FROM conversations c
            LEFT JOIN categories cat ON c.category_id = cat.id
            WHERE c.id = ?
        """, (conv_id,))
        conv = cursor.fetchone()
        
        if not conv:
            conn.close()
            return None
        
        result = dict(conv)
        cursor.execute("SELECT * FROM messages WHERE conversation_id = ? ORDER BY sequence", (conv_id,))
        result["messages"] = [dict(row) for row in cursor.fetchall()]
        conn.close()
        return result
    
    def get_categories(self):
        conn = self._connect()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM categories ORDER BY sort_order")
        rows = cursor.fetchall()
        conn.close()
        return [dict(row) for row in rows]
    
    def get_stats(self):
        conn = self._connect()
        cursor = conn.cursor()
        
        stats = {}
        cursor.execute("SELECT COUNT(*) FROM conversations WHERE is_archived = 0")
        stats["total_conversations"] = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM messages")
        stats["total_messages"] = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM conversations WHERE is_favorite = 1")
        stats["favorites"] = cursor.fetchone()[0]
        
        cursor.execute("""
            SELECT source_version, COUNT(*) FROM conversations 
            WHERE is_archived = 0 GROUP BY source_version
        """)
        stats["by_version"] = {row[0]: row[1] for row in cursor.fetchall()}
        
        conn.close()
        return stats
    
    def update_conversation(self, conv_id, **kwargs):
        allowed = {"ai_title", "ai_summary", "category_id", "tags", 
                   "workspace_path", "is_favorite", "is_archived"}
        updates = {k: v for k, v in kwargs.items() if k in allowed}
        if not updates:
            return False
        
        conn = self._connect()
        cursor = conn.cursor()
        set_clause = ", ".join(f"{k} = ?" for k in updates.keys())
        params = list(updates.values()) + [conv_id]
        cursor.execute(f"UPDATE conversations SET {set_clause} WHERE id = ?", params)
        conn.commit()
        conn.close()
        return True
    
    def toggle_favorite(self, conv_id):
        conn = self._connect()
        cursor = conn.cursor()
        cursor.execute("UPDATE conversations SET is_favorite = NOT is_favorite WHERE id = ?", (conv_id,))
        conn.commit()
        conn.close()
        return True
    
    def export_to_markdown(self, conv_id, output_dir=None, include_metadata=True):
        conv = self.get_conversation(conv_id)
        if not conv:
            return None
        
        output_dir = output_dir or EXPORTS_DIR
        output_dir.mkdir(parents=True, exist_ok=True)
        
        title = conv.get("ai_title") or conv.get("original_title") or "Untitled"
        safe_title = "".join(c if c.isalnum() or c in " -_" else "_" for c in title)[:50]
        date_str = datetime.now().strftime("%Y%m%d")
        filename = f"{date_str}_{safe_title}_{conv_id[:8]}.md"
        output_path = output_dir / filename
        
        lines = []
        if include_metadata:
            lines.extend(["---", f"id: {conv_id}", f"title: {title}",
                         f"category: {conv.get('category_name', 'General')}",
                         f"source_version: {conv.get('source_version', 'unknown')}",
                         f"message_count: {conv.get('message_count', 0)}",
                         f"exported_at: {datetime.now().isoformat()}", "---\n"])
        
        lines.append(f"# {title}\n")
        
        for msg in conv.get("messages", []):
            role = msg["role"]
            content = msg["content"] or ""
            lines.append("## " + ("User" if role == "user" else "Assistant") + "\n")
            lines.append(content)
            lines.append("\n---\n")
        
        output_path.write_text("\n".join(lines))
        return output_path
    
    def bulk_export(self, conv_ids=None, output_dir=None):
        results = {"exported": [], "failed": [], "output_dir": str(output_dir or EXPORTS_DIR)}
        
        if conv_ids is None:
            convs = self.get_conversations(limit=10000)
            conv_ids = [c["id"] for c in convs]
        
        for conv_id in conv_ids:
            try:
                path = self.export_to_markdown(conv_id, output_dir)
                if path:
                    results["exported"].append({"id": conv_id, "path": str(path)})
            except Exception as e:
                results["failed"].append({"id": conv_id, "error": str(e)})
        
        return results
    
    def generate_context_file(self, conv_ids, output_name, style="summary"):
        output_path = CONTEXT_DIR / f"{output_name}.context.md"
        
        lines = ["# Context from Previous Conversations\n",
                f"*Generated: {datetime.now().isoformat()}*\n", "---\n"]
        
        for conv_id in conv_ids:
            conv = self.get_conversation(conv_id)
            if not conv:
                continue
            
            title = conv.get("ai_title") or conv.get("original_title") or "Untitled"
            lines.append(f"## {title}\n")
            
            if style == "summary" and conv.get("ai_summary"):
                lines.append(f"{conv['ai_summary']}\n")
            else:
                for msg in conv.get("messages", [])[:4]:
                    role = "User" if msg["role"] == "user" else "Assistant"
                    content = (msg["content"] or "")[:500]
                    lines.append(f"**{role}:** {content}\n")
            lines.append("\n---\n")
        
        output_path.write_text("\n".join(lines))
        return output_path
    
    def generate_title_request(self, conv_id):
        conv = self.get_conversation(conv_id)
        if not conv:
            return None
        
        messages = conv.get("messages", [])[:6]
        request_path = CONTEXT_DIR / f"title_request_{conv_id[:8]}.md"
        
        content = f"""# Title Generation Request

Please generate a concise, descriptive title (max 60 chars) for this conversation.

## Current Title
{conv.get('original_title', 'Untitled')}

## Conversation Preview

"""
        for msg in messages:
            role = "User" if msg["role"] == "user" else "Assistant"
            text = (msg["content"] or "")[:300]
            content += f"**{role}:** {text}\n\n"
        
        content += """
---
Respond with ONLY the title, nothing else.
"""
        request_path.write_text(content)
        return request_path

# ═══════════════════════════════════════════════════════════════════════════
# Markdown Renderer
# ═══════════════════════════════════════════════════════════════════════════

class MarkdownRenderer:
    """Renders markdown in a Text widget using tags."""
    
    def __init__(self, text_widget, colors):
        self.text = text_widget
        self.colors = colors
        self._setup_tags()
    
    def _setup_tags(self):
        # Headers
        self.text.tag_configure("h1", foreground=self.colors["header1"], 
                                font=("Segoe UI", 18, "bold"), spacing1=15, spacing3=10)
        self.text.tag_configure("h2", foreground=self.colors["header2"],
                                font=("Segoe UI", 14, "bold"), spacing1=12, spacing3=8)
        self.text.tag_configure("h3", foreground=self.colors["header3"],
                                font=("Segoe UI", 12, "bold"), spacing1=10, spacing3=6)
        
        # Text styles
        self.text.tag_configure("bold", foreground=self.colors["bold"], font=("Segoe UI", 10, "bold"))
        self.text.tag_configure("italic", foreground=self.colors["italic"], font=("Segoe UI", 10, "italic"))
        self.text.tag_configure("code", foreground=self.colors["inline_code"], 
                                background=self.colors["code_bg"], font=("Consolas", 10))
        self.text.tag_configure("link", foreground=self.colors["link"], underline=True)
        
        # Code blocks
        self.text.tag_configure("codeblock", foreground=self.colors["fg"], 
                                background=self.colors["code_bg"], font=("Consolas", 9),
                                lmargin1=20, lmargin2=20, rmargin=20, spacing1=5, spacing3=5)
        
        # Lists
        self.text.tag_configure("listitem", lmargin1=20, lmargin2=35)
        
        # Blockquote
        self.text.tag_configure("quote", foreground=self.colors["fg_dim"], 
                                lmargin1=20, lmargin2=20, font=("Segoe UI", 10, "italic"))
        
        # Separator
        self.text.tag_configure("separator", foreground=self.colors["border"])
        
        # Role headers
        self.text.tag_configure("user_role", foreground=self.colors["accent"], 
                                font=("Segoe UI", 12, "bold"), spacing1=15)
        self.text.tag_configure("assistant_role", foreground=self.colors["success"],
                                font=("Segoe UI", 12, "bold"), spacing1=15)
    
    def render(self, markdown_text):
        """Render markdown text into the Text widget."""
        self.text.config(state="normal")
        self.text.delete("1.0", "end")
        
        lines = markdown_text.split("\n")
        i = 0
        in_code_block = False
        code_block_content = []
        
        while i < len(lines):
            line = lines[i]
            
            # Code blocks
            if line.startswith("```"):
                if in_code_block:
                    # End code block
                    self.text.insert("end", "\n".join(code_block_content) + "\n", "codeblock")
                    code_block_content = []
                    in_code_block = False
                else:
                    in_code_block = True
                i += 1
                continue
            
            if in_code_block:
                code_block_content.append(line)
                i += 1
                continue
            
            # Headers
            if line.startswith("### "):
                self.text.insert("end", line[4:] + "\n", "h3")
            elif line.startswith("## "):
                self.text.insert("end", line[3:] + "\n", "h2")
            elif line.startswith("# "):
                self.text.insert("end", line[2:] + "\n", "h1")
            
            # Horizontal rules
            elif line.strip() in ["---", "***", "___"]:
                self.text.insert("end", "─" * 60 + "\n", "separator")
            
            # Blockquotes
            elif line.startswith("> "):
                self.text.insert("end", line[2:] + "\n", "quote")
            
            # List items
            elif line.strip().startswith("- ") or line.strip().startswith("* "):
                self.text.insert("end", "  • " + line.strip()[2:] + "\n", "listitem")
            elif re.match(r"^\d+\. ", line.strip()):
                self.text.insert("end", "  " + line.strip() + "\n", "listitem")
            
            # Regular text with inline formatting
            else:
                self._render_inline(line + "\n")
            
            i += 1
    
    def _render_inline(self, text):
        """Render inline markdown elements."""
        # Pattern for inline code, bold, italic, links
        patterns = [
            (r"`([^`]+)`", "code"),
            (r"\*\*([^*]+)\*\*", "bold"),
            (r"__([^_]+)__", "bold"),
            (r"\*([^*]+)\*", "italic"),
            (r"_([^_]+)_", "italic"),
            (r"\[([^\]]+)\]\([^)]+\)", "link"),
        ]
        
        # Simple approach: just insert with basic formatting detection
        # For a production app, you'd want a proper parser
        
        pos = 0
        result = []
        
        # Find code blocks first
        code_pattern = re.compile(r"`([^`]+)`")
        bold_pattern = re.compile(r"\*\*([^*]+)\*\*")
        italic_pattern = re.compile(r"\*([^*]+)\*")
        
        segments = []
        last_end = 0
        
        # Find all inline code
        for match in code_pattern.finditer(text):
            if match.start() > last_end:
                segments.append((text[last_end:match.start()], None))
            segments.append((match.group(1), "code"))
            last_end = match.end()
        
        if last_end < len(text):
            segments.append((text[last_end:], None))
        
        # Now process each segment for bold/italic
        for segment_text, segment_tag in segments:
            if segment_tag:
                self.text.insert("end", segment_text, segment_tag)
            else:
                # Check for bold
                bold_parts = []
                last_end = 0
                for match in bold_pattern.finditer(segment_text):
                    if match.start() > last_end:
                        bold_parts.append((segment_text[last_end:match.start()], None))
                    bold_parts.append((match.group(1), "bold"))
                    last_end = match.end()
                if last_end < len(segment_text):
                    bold_parts.append((segment_text[last_end:], None))
                
                for part_text, part_tag in bold_parts:
                    if part_tag:
                        self.text.insert("end", part_text, part_tag)
                    else:
                        self.text.insert("end", part_text)
    
    def render_conversation(self, messages):
        """Render a conversation with role headers."""
        self.text.config(state="normal")
        self.text.delete("1.0", "end")
        
        for msg in messages:
            role = msg["role"]
            content = msg["content"] or ""
            
            # Role header
            if role == "user":
                self.text.insert("end", "👤 USER\n", "user_role")
            else:
                self.text.insert("end", "🤖 ASSISTANT\n", "assistant_role")
            
            self.text.insert("end", "─" * 50 + "\n", "separator")
            
            # Render message content
            self._render_message_content(content)
            self.text.insert("end", "\n\n")
        
        self.text.config(state="disabled")
    
    def _render_message_content(self, content):
        """Render message content with markdown."""
        lines = content.split("\n")
        i = 0
        in_code_block = False
        code_block_content = []
        code_lang = ""
        
        while i < len(lines):
            line = lines[i]
            
            # Code blocks
            if line.startswith("```"):
                if in_code_block:
                    self.text.insert("end", "\n".join(code_block_content) + "\n", "codeblock")
                    code_block_content = []
                    in_code_block = False
                else:
                    code_lang = line[3:].strip()
                    in_code_block = True
                i += 1
                continue
            
            if in_code_block:
                code_block_content.append(line)
                i += 1
                continue
            
            # Headers
            if line.startswith("### "):
                self.text.insert("end", line[4:] + "\n", "h3")
            elif line.startswith("## "):
                self.text.insert("end", line[3:] + "\n", "h2")
            elif line.startswith("# "):
                self.text.insert("end", line[2:] + "\n", "h1")
            elif line.strip() in ["---", "***"]:
                self.text.insert("end", "─" * 40 + "\n", "separator")
            elif line.startswith("> "):
                self.text.insert("end", line[2:] + "\n", "quote")
            elif line.strip().startswith("- "):
                self.text.insert("end", "  • " + line.strip()[2:] + "\n", "listitem")
            else:
                self._render_inline(line + "\n")
            
            i += 1

# ═══════════════════════════════════════════════════════════════════════════
# Conversation Detail Window
# ═══════════════════════════════════════════════════════════════════════════

class ConversationDetailWindow(tk.Toplevel):
    """Window showing conversation with markdown preview toggle."""
    
    def __init__(self, parent, conv_id, db, colors):
        super().__init__(parent)
        self.db = db
        self.colors = colors
        self.conv_id = conv_id
        self.conv = db.get_conversation(conv_id)
        
        if not self.conv:
            self.destroy()
            return
        
        title = self.conv.get("ai_title") or self.conv.get("original_title") or "Chat"
        self.title(title[:60])
        self.geometry("900x700")
        self.configure(bg=colors["bg"])
        self.minsize(700, 500)
        
        self.view_mode = tk.StringVar(value="rendered")
        self.build_ui()
        self.load_content()
    
    def build_ui(self):
        # Header
        header = tk.Frame(self, bg=self.colors["sidebar_bg"], pady=15, padx=20)
        header.pack(fill="x")
        
        title = self.conv.get("ai_title") or self.conv.get("original_title") or "Untitled"
        tk.Label(header, text=title[:70], bg=self.colors["sidebar_bg"],
                fg=self.colors["fg"], font=("Segoe UI", 14, "bold"), wraplength=600,
                justify="left").pack(anchor="w")
        
        info = f"{self.conv.get('message_count', 0)} messages • {self.conv.get('category_name', 'General')} • {self.conv.get('source_version', 'default')}"
        tk.Label(header, text=info, bg=self.colors["sidebar_bg"],
                fg=self.colors["fg_dim"], font=("Segoe UI", 9)).pack(anchor="w")
        
        # View mode toggle
        toggle_frame = tk.Frame(header, bg=self.colors["sidebar_bg"])
        toggle_frame.pack(anchor="e", pady=(10, 0))
        
        tk.Label(toggle_frame, text="View:", bg=self.colors["sidebar_bg"],
                fg=self.colors["fg_dim"], font=("Segoe UI", 9)).pack(side="left", padx=(0, 10))
        
        ttk.Radiobutton(toggle_frame, text="Rendered", variable=self.view_mode,
                       value="rendered", command=self.load_content).pack(side="left", padx=5)
        ttk.Radiobutton(toggle_frame, text="Raw", variable=self.view_mode,
                       value="raw", command=self.load_content).pack(side="left", padx=5)
        
        # Content area with scrollbar
        content_frame = tk.Frame(self, bg=self.colors["bg"], padx=20, pady=10)
        content_frame.pack(fill="both", expand=True)
        
        self.text = tk.Text(content_frame, bg=self.colors["card_bg"], fg=self.colors["fg"],
                           font=("Consolas", 10), wrap="word", relief="flat",
                           insertbackground=self.colors["fg"], padx=15, pady=10)
        scrollbar = ttk.Scrollbar(content_frame, orient="vertical", command=self.text.yview)
        self.text.configure(yscrollcommand=scrollbar.set)
        
        self.text.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        self.renderer = MarkdownRenderer(self.text, self.colors)
        
        # Bottom actions
        actions = tk.Frame(self, bg=self.colors["sidebar_bg"], pady=10, padx=20)
        actions.pack(fill="x")
        
        ttk.Button(actions, text="Export to Markdown",
                  command=self.export_md).pack(side="left", padx=(0, 10))
        ttk.Button(actions, text="Copy to Clipboard",
                  command=self.copy_to_clipboard).pack(side="left", padx=(0, 10))
        ttk.Button(actions, text="Generate Title Request",
                  command=self.gen_title).pack(side="left")
    
    def load_content(self):
        mode = self.view_mode.get()
        
        if mode == "rendered":
            self.renderer.render_conversation(self.conv.get("messages", []))
        else:
            self.text.config(state="normal")
            self.text.delete("1.0", "end")
            
            for msg in self.conv.get("messages", []):
                role = "👤 USER" if msg["role"] == "user" else "🤖 ASSISTANT"
                self.text.insert("end", f"\n{role}\n")
                self.text.insert("end", "-" * 60 + "\n")
                self.text.insert("end", (msg["content"] or "") + "\n\n")
            
            self.text.config(state="disabled")
    
    def export_md(self):
        path = self.db.export_to_markdown(self.conv_id)
        if path:
            messagebox.showinfo("Exported", f"Saved to:\n{path}")
    
    def copy_to_clipboard(self):
        content = []
        for msg in self.conv.get("messages", []):
            role = "User" if msg["role"] == "user" else "Assistant"
            content.append(f"## {role}\n\n{msg['content']}\n")
        
        self.clipboard_clear()
        self.clipboard_append("\n".join(content))
        messagebox.showinfo("Copied", "Conversation copied to clipboard")
    
    def gen_title(self):
        path = self.db.generate_title_request(self.conv_id)
        if path:
            messagebox.showinfo("Request Generated",
                               f"Title request file created:\n{path}\n\n"
                               "Open this file in Cursor and ask AI to generate a title.")

# ═══════════════════════════════════════════════════════════════════════════
# Main Chat Library Window
# ═══════════════════════════════════════════════════════════════════════════

class ChatLibraryWindow(tk.Tk):
    """Main chat library window."""
    
    def __init__(self):
        super().__init__()
        self.colors = COLORS
        self.db = ChatDatabase()
        self.selected_ids = set()
        
        self.title("Cursor Chat Library")
        self.geometry("1200x800")
        self.configure(bg=self.colors["bg"])
        self.minsize(1000, 600)
        
        self.setup_styles()
        self.build_ui()
        self.load_stats()
        self.load_chats()
    
    def setup_styles(self):
        style = ttk.Style()
        style.theme_use('clam')
        
        style.configure("TFrame", background=self.colors["bg"])
        style.configure("TLabel", background=self.colors["bg"], foreground=self.colors["fg"])
        style.configure("TButton", background=self.colors["accent"], foreground="white",
                       borderwidth=0, focusthickness=0, padding=(12, 8))
        style.map("TButton", background=[("active", self.colors["accent_hover"])])
        
        style.configure("TCombobox", fieldbackground=self.colors["input_bg"],
                       background=self.colors["input_bg"], foreground=self.colors["input_fg"])
        
        style.configure("Treeview", background=self.colors["card_bg"],
                       foreground=self.colors["fg"], fieldbackground=self.colors["card_bg"],
                       font=("Segoe UI", 9), rowheight=28)
        style.configure("Treeview.Heading", background=self.colors["sidebar_bg"],
                       foreground=self.colors["fg"], font=("Segoe UI", 9, "bold"))
        style.map("Treeview", background=[("selected", self.colors["accent_dim"])])
        
        self.option_add("*TCombobox*Listbox.background", self.colors["input_bg"])
        self.option_add("*TCombobox*Listbox.foreground", self.colors["input_fg"])
    
    def build_ui(self):
        # Main paned layout
        self.paned = tk.PanedWindow(self, orient=tk.HORIZONTAL, bg=self.colors["border"],
                                     sashwidth=4, borderwidth=0)
        self.paned.pack(fill="both", expand=True)
        
        # Sidebar
        self.sidebar = tk.Frame(self.paned, bg=self.colors["sidebar_bg"], width=280)
        self.paned.add(self.sidebar, minsize=220)
        
        # Content
        self.content = tk.Frame(self.paned, bg=self.colors["bg"])
        self.paned.add(self.content, minsize=600)
        
        self.build_sidebar()
        self.build_content()
    
    def build_sidebar(self):
        # Header
        header = tk.Frame(self.sidebar, bg=self.colors["sidebar_bg"], pady=20, padx=20)
        header.pack(fill="x")
        
        tk.Label(header, text="CHAT", bg=self.colors["sidebar_bg"], fg=self.colors["fg"],
                font=("Segoe UI", 20, "bold")).pack(anchor="w")
        tk.Label(header, text="LIBRARY", bg=self.colors["sidebar_bg"], fg=self.colors["accent"],
                font=("Segoe UI", 20, "bold")).pack(anchor="w")
        
        # Stats
        stats_frame = tk.Frame(self.sidebar, bg=self.colors["sidebar_bg"], padx=20, pady=10)
        stats_frame.pack(fill="x")
        
        self.stats_label = tk.Label(stats_frame, text="Loading...",
                                   bg=self.colors["sidebar_bg"], fg=self.colors["fg_dim"],
                                   font=("Segoe UI", 9), justify="left")
        self.stats_label.pack(anchor="w")
        
        # Separator
        tk.Frame(self.sidebar, bg=self.colors["border"], height=1).pack(fill="x", pady=15)
        
        # Filters
        filter_frame = tk.Frame(self.sidebar, bg=self.colors["sidebar_bg"], padx=20)
        filter_frame.pack(fill="x")
        
        tk.Label(filter_frame, text="FILTERS", bg=self.colors["sidebar_bg"],
                fg=self.colors["fg_dim"], font=("Segoe UI", 9, "bold")).pack(anchor="w", pady=(0, 10))
        
        # Category filter
        tk.Label(filter_frame, text="Category", bg=self.colors["sidebar_bg"],
                fg=self.colors["fg_dim"], font=("Segoe UI", 9)).pack(anchor="w")
        
        self.categories = self.db.get_categories()
        cat_names = ["All"] + [c["name"] for c in self.categories]
        self.category_var = tk.StringVar(value="All")
        cat_combo = ttk.Combobox(filter_frame, textvariable=self.category_var,
                                values=cat_names, state="readonly", font=("Segoe UI", 9))
        cat_combo.pack(fill="x", pady=(0, 10))
        cat_combo.bind("<<ComboboxSelected>>", lambda e: self.load_chats())
        
        # Version filter
        tk.Label(filter_frame, text="Version", bg=self.colors["sidebar_bg"],
                fg=self.colors["fg_dim"], font=("Segoe UI", 9)).pack(anchor="w")
        
        stats = self.db.get_stats()
        versions = ["All"] + list(stats.get("by_version", {}).keys())
        self.version_var = tk.StringVar(value="All")
        ver_combo = ttk.Combobox(filter_frame, textvariable=self.version_var,
                                values=versions, state="readonly", font=("Segoe UI", 9))
        ver_combo.pack(fill="x", pady=(0, 10))
        ver_combo.bind("<<ComboboxSelected>>", lambda e: self.load_chats())
        
        # Favorites
        self.fav_var = tk.BooleanVar(value=False)
        fav_check = tk.Checkbutton(filter_frame, text="Favorites only", variable=self.fav_var,
                                  bg=self.colors["sidebar_bg"], fg=self.colors["fg"],
                                  selectcolor=self.colors["card_bg"], command=self.load_chats)
        fav_check.pack(anchor="w", pady=5)
        
        # Separator
        tk.Frame(self.sidebar, bg=self.colors["border"], height=1).pack(fill="x", pady=15)
        
        # Actions
        actions = tk.Frame(self.sidebar, bg=self.colors["sidebar_bg"], padx=20)
        actions.pack(fill="x")
        
        tk.Label(actions, text="ACTIONS", bg=self.colors["sidebar_bg"],
                fg=self.colors["fg_dim"], font=("Segoe UI", 9, "bold")).pack(anchor="w", pady=(0, 10))
        
        ttk.Button(actions, text="↻ Import from Cursor", command=self.import_chats).pack(fill="x", pady=2)
        ttk.Button(actions, text="⬇ Export Selected", command=self.export_selected).pack(fill="x", pady=2)
        ttk.Button(actions, text="⬇ Export All", command=self.export_all).pack(fill="x", pady=2)
        ttk.Button(actions, text="📄 Generate Context", command=self.generate_context).pack(fill="x", pady=2)
    
    def build_content(self):
        # Search bar
        search_frame = tk.Frame(self.content, bg=self.colors["bg"], pady=15, padx=20)
        search_frame.pack(fill="x")
        
        tk.Label(search_frame, text="🔍", bg=self.colors["bg"], fg=self.colors["fg_dim"],
                font=("Segoe UI", 14)).pack(side="left", padx=(0, 10))
        
        self.search_var = tk.StringVar()
        search_entry = tk.Entry(search_frame, textvariable=self.search_var,
                               bg=self.colors["input_bg"], fg=self.colors["input_fg"],
                               font=("Segoe UI", 11), insertbackground=self.colors["fg"],
                               relief="flat", highlightthickness=1,
                               highlightbackground=self.colors["border"])
        search_entry.pack(side="left", fill="x", expand=True, ipady=8, ipadx=10)
        search_entry.bind("<Return>", lambda e: self.search_chats())
        
        ttk.Button(search_frame, text="Search", command=self.search_chats).pack(side="left", padx=(10, 5))
        ttk.Button(search_frame, text="Clear", command=self.clear_search).pack(side="left")
        
        # Chat list
        list_frame = tk.Frame(self.content, bg=self.colors["bg"], padx=20)
        list_frame.pack(fill="both", expand=True, pady=(0, 10))
        
        columns = ("select", "fav", "category", "version", "msgs", "title")
        self.tree = ttk.Treeview(list_frame, columns=columns, show="headings", height=20)
        
        self.tree.heading("select", text="☐")
        self.tree.heading("fav", text="★")
        self.tree.heading("category", text="Category")
        self.tree.heading("version", text="Version")
        self.tree.heading("msgs", text="Msgs")
        self.tree.heading("title", text="Title")
        
        self.tree.column("select", width=30, minwidth=30, anchor="center")
        self.tree.column("fav", width=30, minwidth=30, anchor="center")
        self.tree.column("category", width=100, minwidth=80)
        self.tree.column("version", width=70, minwidth=60)
        self.tree.column("msgs", width=50, minwidth=40, anchor="center")
        self.tree.column("title", width=500, minwidth=200)
        
        scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        
        self.tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        
        self.tree.bind("<Double-1>", self.on_double_click)
        self.tree.bind("<Button-1>", self.on_click)
        
        # Status bar
        status_frame = tk.Frame(self.content, bg=self.colors["sidebar_bg"], pady=8, padx=20)
        status_frame.pack(fill="x", side="bottom")
        
        self.status_label = tk.Label(status_frame, text="Loading...",
                                    bg=self.colors["sidebar_bg"], fg=self.colors["fg_dim"],
                                    font=("Segoe UI", 9))
        self.status_label.pack(side="left")
        
        self.selection_label = tk.Label(status_frame, text="",
                                       bg=self.colors["sidebar_bg"], fg=self.colors["accent"],
                                       font=("Segoe UI", 9))
        self.selection_label.pack(side="right")
    
    def load_stats(self):
        stats = self.db.get_stats()
        text = f"📊 {stats['total_conversations']} chats  •  💬 {stats['total_messages']} messages  •  ⭐ {stats['favorites']} favorites"
        self.stats_label.config(text=text)
    
    def load_chats(self):
        for item in self.tree.get_children():
            self.tree.delete(item)
        
        category_id = None
        if self.category_var.get() != "All":
            cat = next((c for c in self.categories if c["name"] == self.category_var.get()), None)
            if cat:
                category_id = cat["id"]
        
        convs = self.db.get_conversations(category_id=category_id, favorites_only=self.fav_var.get(), limit=500)
        
        if self.version_var.get() != "All":
            convs = [c for c in convs if c["source_version"] == self.version_var.get()]
        
        for conv in convs:
            sel = "☑" if conv["id"] in self.selected_ids else "☐"
            fav = "★" if conv.get("is_favorite") else "☆"
            cat = conv.get("category_name", "General")
            ver = conv.get("source_version", "default")
            if ver == "default":
                ver = "Main"
            msgs = conv.get("message_count", 0)
            title = (conv.get("ai_title") or conv.get("original_title") or "Untitled").replace("\n", " ")[:80]
            
            self.tree.insert("", "end", iid=conv["id"], values=(sel, fav, cat, ver, msgs, title))
        
        self.status_label.config(text=f"Showing {len(convs)} conversations")
        self.update_selection_label()
    
    def update_selection_label(self):
        count = len(self.selected_ids)
        if count > 0:
            self.selection_label.config(text=f"{count} selected")
        else:
            self.selection_label.config(text="")
    
    def on_click(self, event):
        region = self.tree.identify_region(event.x, event.y)
        if region != "cell":
            return
        
        column = self.tree.identify_column(event.x)
        item = self.tree.identify_row(event.y)
        
        if not item:
            return
        
        if column == "#1":  # Select
            if item in self.selected_ids:
                self.selected_ids.remove(item)
            else:
                self.selected_ids.add(item)
            self.update_row(item)
            self.update_selection_label()
        
        elif column == "#2":  # Favorite
            self.db.toggle_favorite(item)
            self.update_row(item)
    
    def update_row(self, item):
        conv = self.db.get_conversation(item)
        if not conv:
            return
        
        sel = "☑" if item in self.selected_ids else "☐"
        fav = "★" if conv.get("is_favorite") else "☆"
        cat = conv.get("category_name", "General")
        ver = conv.get("source_version", "default")
        if ver == "default":
            ver = "Main"
        msgs = conv.get("message_count", 0)
        title = (conv.get("ai_title") or conv.get("original_title") or "Untitled").replace("\n", " ")[:80]
        
        self.tree.item(item, values=(sel, fav, cat, ver, msgs, title))
    
    def on_double_click(self, event):
        item = self.tree.identify_row(event.y)
        if item:
            ConversationDetailWindow(self, item, self.db, self.colors)
    
    def search_chats(self):
        query = self.search_var.get().strip()
        if not query:
            self.load_chats()
            return
        
        for item in self.tree.get_children():
            self.tree.delete(item)
        
        convs = self.db.get_conversations(search=query, limit=500)
        
        for conv in convs:
            sel = "☑" if conv["id"] in self.selected_ids else "☐"
            fav = "★" if conv.get("is_favorite") else "☆"
            cat = conv.get("category_name", "General")
            ver = conv.get("source_version", "default")
            if ver == "default":
                ver = "Main"
            msgs = conv.get("message_count", 0)
            title = (conv.get("ai_title") or conv.get("original_title") or "Untitled").replace("\n", " ")[:80]
            
            self.tree.insert("", "end", iid=conv["id"], values=(sel, fav, cat, ver, msgs, title))
        
        self.status_label.config(text=f"Found {len(convs)} matching '{query}'")
    
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
            messagebox.showwarning("No Selection", "Select conversations using the ☐ checkbox first.")
            return
        
        results = self.db.bulk_export(conv_ids=list(self.selected_ids))
        messagebox.showinfo("Export Complete",
                           f"Exported {len(results['exported'])} to:\n{results['output_dir']}")
    
    def export_all(self):
        if not messagebox.askyesno("Confirm", "Export all conversations?"):
            return
        results = self.db.bulk_export()
        messagebox.showinfo("Export Complete",
                           f"Exported {len(results['exported'])} to:\n{results['output_dir']}")
    
    def generate_context(self):
        if not self.selected_ids:
            messagebox.showwarning("No Selection", "Select conversations first.")
            return
        
        dialog = tk.Toplevel(self)
        dialog.title("Generate Context File")
        dialog.geometry("400x180")
        dialog.configure(bg=self.colors["bg"])
        dialog.transient(self)
        dialog.grab_set()
        
        tk.Label(dialog, text="Context file name:", bg=self.colors["bg"],
                fg=self.colors["fg"]).pack(pady=(20, 5))
        
        name_var = tk.StringVar(value="workspace-context")
        tk.Entry(dialog, textvariable=name_var, bg=self.colors["input_bg"],
                fg=self.colors["input_fg"]).pack(fill="x", padx=20, ipady=5)
        
        tk.Label(dialog, text="Style:", bg=self.colors["bg"], fg=self.colors["fg"]).pack(pady=(15, 5))
        
        style_var = tk.StringVar(value="summary")
        ttk.Combobox(dialog, textvariable=style_var, values=["summary", "full", "key_points"],
                    state="readonly").pack(fill="x", padx=20)
        
        def do_gen():
            path = self.db.generate_context_file(list(self.selected_ids), name_var.get(), style_var.get())
            dialog.destroy()
            messagebox.showinfo("Generated", f"Context file saved to:\n{path}")
        
        ttk.Button(dialog, text="Generate", command=do_gen).pack(pady=15)


if __name__ == "__main__":
    app = ChatLibraryWindow()
    app.mainloop()
  ''
