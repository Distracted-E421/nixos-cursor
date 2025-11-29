"""
Cursor Chat Database Manager
Provides persistent storage, categorization, and export for Cursor chat history.
"""
import sqlite3
import json
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Any

# Database location
CHAT_DB_DIR = Path.home() / ".config" / "cursor-manager"
CHAT_DB_PATH = CHAT_DB_DIR / "chats.db"
EXPORTS_DIR = CHAT_DB_DIR / "exports"
CONTEXT_DIR = CHAT_DB_DIR / "context"

# Default categories with colors (hex)
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

SCHEMA = """
-- Conversations table
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

-- Messages table  
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

-- Categories table
CREATE TABLE IF NOT EXISTS categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    color TEXT DEFAULT '#808080',
    description TEXT,
    sort_order INTEGER DEFAULT 0
);

-- Export history
CREATE TABLE IF NOT EXISTS exports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id TEXT,
    exported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    export_path TEXT NOT NULL,
    format TEXT NOT NULL,
    include_metadata INTEGER DEFAULT 0,
    FOREIGN KEY (conversation_id) REFERENCES conversations(id)
);

-- Full-text search
CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
    content,
    conversation_id,
    content='messages',
    content_rowid='rowid'
);

-- Triggers for FTS sync
CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
    INSERT INTO messages_fts(rowid, content, conversation_id) 
    VALUES (new.rowid, new.content, new.conversation_id);
END;

CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content, conversation_id) 
    VALUES('delete', old.rowid, old.content, old.conversation_id);
END;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_conv_category ON conversations(category_id);
CREATE INDEX IF NOT EXISTS idx_conv_workspace ON conversations(workspace_path);
CREATE INDEX IF NOT EXISTS idx_conv_favorite ON conversations(is_favorite);
"""


class ChatDatabase:
    """Manages the cursor-manager chat database."""
    
    def __init__(self, db_path: Path = CHAT_DB_PATH):
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
        CONTEXT_DIR.mkdir(parents=True, exist_ok=True)
        self._init_db()
    
    def _init_db(self):
        """Initialize database schema."""
        conn = sqlite3.connect(str(self.db_path))
        conn.executescript(SCHEMA)
        
        # Insert default categories if empty
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
    
    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        return conn
    
    # ─────────────────────────────────────────────────────────────────────────
    # Import from Cursor
    # ─────────────────────────────────────────────────────────────────────────
    
    def import_from_cursor(self, cursor_db_path: Path, version: str = "default") -> Dict[str, Any]:
        """Import conversations from a Cursor state.vscdb database."""
        if not cursor_db_path.exists():
            return {"success": False, "error": "Database not found", "imported": 0}
        
        results = {"success": True, "imported": 0, "skipped": 0, "errors": []}
        
        try:
            # Connect to Cursor's database (read-only)
            cursor_conn = sqlite3.connect(f"file:{cursor_db_path}?mode=ro", uri=True)
            cursor_conn.row_factory = sqlite3.Row
            
            # Get all conversation IDs
            cursor = cursor_conn.cursor()
            cursor.execute("""
                SELECT DISTINCT substr(key, 10, 36) as conv_id 
                FROM cursorDiskKV 
                WHERE key LIKE 'bubbleId:%'
            """)
            conv_ids = [row[0] for row in cursor.fetchall()]
            
            our_conn = self._connect()
            our_cursor = our_conn.cursor()
            
            for conv_id in conv_ids:
                try:
                    # Check if already imported (by content hash)
                    cursor.execute("""
                        SELECT key, value FROM cursorDiskKV 
                        WHERE key LIKE ? ORDER BY key
                    """, (f"bubbleId:{conv_id}:%",))
                    
                    messages_data = cursor.fetchall()
                    if not messages_data:
                        continue
                    
                    # Create content hash to detect duplicates
                    content_hash = hashlib.md5(
                        "".join(str(m[1]) for m in messages_data).encode()
                    ).hexdigest()
                    
                    # Check for existing
                    our_cursor.execute(
                        "SELECT id FROM conversations WHERE content_hash = ?", 
                        (content_hash,)
                    )
                    if our_cursor.fetchone():
                        results["skipped"] += 1
                        continue
                    
                    # Parse messages
                    messages = []
                    first_ts = None
                    last_ts = None
                    title_candidates = []
                    
                    for i, (key, value) in enumerate(messages_data):
                        try:
                            msg = json.loads(value)
                            msg_id = key.split(":")[-1]
                            
                            # Extract role and content
                            role = "assistant" if msg.get("type") == 1 else "user"
                            content = msg.get("text") or msg.get("rawText") or ""
                            
                            # Track first user message for title
                            if role == "user" and content and len(title_candidates) < 3:
                                title_candidates.append(content[:100])
                            
                            messages.append({
                                "id": msg_id,
                                "sequence": i,
                                "role": role,
                                "content": content,
                                "raw": value,
                                "metadata": json.dumps({
                                    "type": msg.get("type"),
                                    "bubbleId": msg.get("bubbleId"),
                                })
                            })
                        except Exception as e:
                            results["errors"].append(f"Message parse error: {e}")
                    
                    if not messages:
                        continue
                    
                    # Generate title from first user message
                    title = "Untitled Chat"
                    if title_candidates:
                        title = title_candidates[0]
                        if len(title) > 60:
                            title = title[:57] + "..."
                    
                    # Insert conversation
                    our_cursor.execute("""
                        INSERT INTO conversations 
                        (id, source_version, original_title, message_count, content_hash)
                        VALUES (?, ?, ?, ?, ?)
                    """, (conv_id, version, title, len(messages), content_hash))
                    
                    # Insert messages
                    for msg in messages:
                        our_cursor.execute("""
                            INSERT OR IGNORE INTO messages 
                            (id, conversation_id, sequence, role, content, raw_content, metadata)
                            VALUES (?, ?, ?, ?, ?, ?, ?)
                        """, (msg["id"], conv_id, msg["sequence"], msg["role"], 
                              msg["content"], msg["raw"], msg["metadata"]))
                    
                    results["imported"] += 1
                    
                except Exception as e:
                    results["errors"].append(f"Conv {conv_id}: {e}")
            
            our_conn.commit()
            our_conn.close()
            cursor_conn.close()
            
        except Exception as e:
            results["success"] = False
            results["error"] = str(e)
        
        return results
    
    def import_all_versions(self) -> Dict[str, Any]:
        """Import from all Cursor installations."""
        cursor_config = Path.home() / ".config" / "Cursor"
        results = {"versions": {}, "total_imported": 0, "total_skipped": 0}
        
        # Main installation
        main_db = cursor_config / "User" / "globalStorage" / "state.vscdb"
        if main_db.exists():
            r = self.import_from_cursor(main_db, "default")
            results["versions"]["default"] = r
            results["total_imported"] += r.get("imported", 0)
            results["total_skipped"] += r.get("skipped", 0)
        
        # Version-specific installations
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
    
    # ─────────────────────────────────────────────────────────────────────────
    # Query & Browse
    # ─────────────────────────────────────────────────────────────────────────
    
    def get_conversations(
        self, 
        category_id: Optional[int] = None,
        workspace: Optional[str] = None,
        favorites_only: bool = False,
        search: Optional[str] = None,
        limit: int = 100,
        offset: int = 0
    ) -> List[Dict]:
        """Get conversations with filters."""
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
        
        if workspace:
            query += " AND c.workspace_path = ?"
            params.append(workspace)
        
        if favorites_only:
            query += " AND c.is_favorite = 1"
        
        if search:
            # Use FTS for search
            query = f"""
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
    
    def get_conversation(self, conv_id: str) -> Optional[Dict]:
        """Get a single conversation with messages."""
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
        
        cursor.execute("""
            SELECT * FROM messages WHERE conversation_id = ? ORDER BY sequence
        """, (conv_id,))
        result["messages"] = [dict(row) for row in cursor.fetchall()]
        
        conn.close()
        return result
    
    def get_categories(self) -> List[Dict]:
        """Get all categories."""
        conn = self._connect()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM categories ORDER BY sort_order")
        rows = cursor.fetchall()
        conn.close()
        return [dict(row) for row in rows]
    
    def get_stats(self) -> Dict:
        """Get database statistics."""
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
            SELECT cat.name, COUNT(c.id) as count 
            FROM categories cat
            LEFT JOIN conversations c ON c.category_id = cat.id AND c.is_archived = 0
            GROUP BY cat.id ORDER BY cat.sort_order
        """)
        stats["by_category"] = {row[0]: row[1] for row in cursor.fetchall()}
        
        cursor.execute("""
            SELECT source_version, COUNT(*) FROM conversations 
            WHERE is_archived = 0 GROUP BY source_version
        """)
        stats["by_version"] = {row[0]: row[1] for row in cursor.fetchall()}
        
        conn.close()
        return stats
    
    # ─────────────────────────────────────────────────────────────────────────
    # Update & Organize
    # ─────────────────────────────────────────────────────────────────────────
    
    def update_conversation(self, conv_id: str, **kwargs) -> bool:
        """Update conversation fields."""
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
    
    def set_category(self, conv_id: str, category_id: int) -> bool:
        return self.update_conversation(conv_id, category_id=category_id)
    
    def toggle_favorite(self, conv_id: str) -> bool:
        conn = self._connect()
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE conversations SET is_favorite = NOT is_favorite WHERE id = ?",
            (conv_id,)
        )
        conn.commit()
        conn.close()
        return True
    
    def archive_conversation(self, conv_id: str) -> bool:
        return self.update_conversation(conv_id, is_archived=1)
    
    # ─────────────────────────────────────────────────────────────────────────
    # Export
    # ─────────────────────────────────────────────────────────────────────────
    
    def export_to_markdown(
        self, 
        conv_id: str, 
        output_dir: Optional[Path] = None,
        include_metadata: bool = True
    ) -> Optional[Path]:
        """Export a conversation to markdown."""
        conv = self.get_conversation(conv_id)
        if not conv:
            return None
        
        output_dir = output_dir or EXPORTS_DIR
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Generate filename
        title = conv.get("ai_title") or conv.get("original_title") or "Untitled"
        safe_title = "".join(c if c.isalnum() or c in " -_" else "_" for c in title)[:50]
        date_str = datetime.now().strftime("%Y%m%d")
        filename = f"{date_str}_{safe_title}_{conv_id[:8]}.md"
        output_path = output_dir / filename
        
        # Build markdown
        lines = []
        
        if include_metadata:
            lines.append("---")
            lines.append(f"id: {conv_id}")
            lines.append(f"title: {title}")
            if conv.get("ai_summary"):
                lines.append(f"summary: {conv['ai_summary']}")
            lines.append(f"category: {conv.get('category_name', 'General')}")
            lines.append(f"source_version: {conv.get('source_version', 'unknown')}")
            lines.append(f"message_count: {conv.get('message_count', 0)}")
            lines.append(f"exported_at: {datetime.now().isoformat()}")
            if conv.get("tags"):
                lines.append(f"tags: {conv['tags']}")
            lines.append("---\n")
        
        lines.append(f"# {title}\n")
        
        for msg in conv.get("messages", []):
            role = msg["role"]
            content = msg["content"] or ""
            
            if role == "user":
                lines.append("## 👤 User\n")
            else:
                lines.append("## 🤖 Assistant\n")
            
            lines.append(content)
            lines.append("\n---\n")
        
        output_path.write_text("\n".join(lines))
        
        # Record export
        conn = self._connect()
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO exports (conversation_id, export_path, format, include_metadata)
            VALUES (?, ?, 'markdown', ?)
        """, (conv_id, str(output_path), 1 if include_metadata else 0))
        cursor.execute(
            "UPDATE conversations SET exported_at = CURRENT_TIMESTAMP WHERE id = ?",
            (conv_id,)
        )
        conn.commit()
        conn.close()
        
        return output_path
    
    def bulk_export(
        self, 
        conv_ids: Optional[List[str]] = None,
        category_id: Optional[int] = None,
        output_dir: Optional[Path] = None
    ) -> Dict[str, Any]:
        """Export multiple conversations."""
        results = {"exported": [], "failed": [], "output_dir": str(output_dir or EXPORTS_DIR)}
        
        if conv_ids is None:
            # Export all non-archived
            convs = self.get_conversations(category_id=category_id, limit=10000)
            conv_ids = [c["id"] for c in convs]
        
        for conv_id in conv_ids:
            try:
                path = self.export_to_markdown(conv_id, output_dir)
                if path:
                    results["exported"].append({"id": conv_id, "path": str(path)})
                else:
                    results["failed"].append({"id": conv_id, "error": "Not found"})
            except Exception as e:
                results["failed"].append({"id": conv_id, "error": str(e)})
        
        return results
    
    # ─────────────────────────────────────────────────────────────────────────
    # Context Generation (for re-injection into Cursor)
    # ─────────────────────────────────────────────────────────────────────────
    
    def generate_context_file(
        self,
        conv_ids: List[str],
        output_name: str,
        style: str = "summary"  # 'summary', 'full', 'key_points'
    ) -> Path:
        """Generate a context file for workspace injection."""
        output_path = CONTEXT_DIR / f"{output_name}.context.md"
        
        lines = [
            "# Context from Previous Conversations\n",
            f"*Generated: {datetime.now().isoformat()}*\n",
            f"*Style: {style}*\n",
            "---\n"
        ]
        
        for conv_id in conv_ids:
            conv = self.get_conversation(conv_id)
            if not conv:
                continue
            
            title = conv.get("ai_title") or conv.get("original_title") or "Untitled"
            
            if style == "summary":
                lines.append(f"## {title}\n")
                if conv.get("ai_summary"):
                    lines.append(f"{conv['ai_summary']}\n")
                else:
                    # Just first few exchanges
                    for msg in conv.get("messages", [])[:4]:
                        role = "User" if msg["role"] == "user" else "Assistant"
                        content = (msg["content"] or "")[:500]
                        if len(msg.get("content", "")) > 500:
                            content += "..."
                        lines.append(f"**{role}:** {content}\n")
                lines.append("\n---\n")
            
            elif style == "full":
                lines.append(f"## {title}\n")
                for msg in conv.get("messages", []):
                    role = "User" if msg["role"] == "user" else "Assistant"
                    lines.append(f"### {role}\n{msg['content']}\n")
                lines.append("\n---\n")
            
            elif style == "key_points":
                lines.append(f"## {title}\n")
                if conv.get("ai_summary"):
                    lines.append(f"**Summary:** {conv['ai_summary']}\n")
                lines.append(f"**Messages:** {conv.get('message_count', 0)}\n")
                lines.append(f"**Category:** {conv.get('category_name', 'General')}\n")
                lines.append("\n")
        
        output_path.write_text("\n".join(lines))
        return output_path
    
    # ─────────────────────────────────────────────────────────────────────────
    # LLM Title/Summary Generation (creates files for Cursor to process)
    # ─────────────────────────────────────────────────────────────────────────
    
    def generate_title_request(self, conv_id: str) -> Optional[Path]:
        """Generate a file that can be fed to Cursor for AI title generation."""
        conv = self.get_conversation(conv_id)
        if not conv:
            return None
        
        # Get first few messages for context
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

## Instructions

Respond with ONLY the title, nothing else. The title should:
- Be descriptive of the main topic/goal
- Be 60 characters or less
- Not include quotes or special characters
- Capture the essence of what was being worked on

Example good titles:
- "NixOS Flake Configuration for Dual GPU Setup"
- "Debugging Hyprland Login Loop Issue"
- "Python Async HTTP Client Implementation"
"""
        
        request_path.write_text(content)
        return request_path
    
    def apply_ai_title(self, conv_id: str, title: str) -> bool:
        """Apply an AI-generated title to a conversation."""
        return self.update_conversation(conv_id, ai_title=title.strip()[:100])
    
    def generate_summary_request(self, conv_id: str) -> Optional[Path]:
        """Generate a file for AI summary generation."""
        conv = self.get_conversation(conv_id)
        if not conv:
            return None
        
        messages = conv.get("messages", [])
        
        request_path = CONTEXT_DIR / f"summary_request_{conv_id[:8]}.md"
        
        content = f"""# Summary Generation Request

Please generate a concise summary (2-4 sentences) of this conversation.

## Conversation ({len(messages)} messages)

"""
        # Include all messages but truncate long ones
        for msg in messages:
            role = "User" if msg["role"] == "user" else "Assistant"
            text = msg["content"] or ""
            if len(text) > 500:
                text = text[:500] + "... [truncated]"
            content += f"**{role}:** {text}\n\n"
        
        content += """
---

## Instructions

Respond with ONLY the summary, nothing else. The summary should:
- Be 2-4 sentences
- Capture what was accomplished or discussed
- Mention key technologies/concepts involved
- Be useful for quickly understanding what this chat was about
"""
        
        request_path.write_text(content)
        return request_path
    
    def apply_ai_summary(self, conv_id: str, summary: str) -> bool:
        """Apply an AI-generated summary to a conversation."""
        return self.update_conversation(conv_id, ai_summary=summary.strip()[:500])
    
    def generate_category_request(self, conv_id: str) -> Optional[Path]:
        """Generate a file for AI category suggestion."""
        conv = self.get_conversation(conv_id)
        if not conv:
            return None
        
        categories = self.get_categories()
        messages = conv.get("messages", [])[:6]
        
        request_path = CONTEXT_DIR / f"category_request_{conv_id[:8]}.md"
        
        content = f"""# Category Suggestion Request

Please suggest the best category for this conversation.

## Available Categories

"""
        for cat in categories:
            content += f"- **{cat['name']}**: {cat['description']}\n"
        
        content += f"""
## Conversation Preview

"""
        for msg in messages:
            role = "User" if msg["role"] == "user" else "Assistant"
            text = (msg["content"] or "")[:300]
            content += f"**{role}:** {text}\n\n"
        
        content += """
---

## Instructions

Respond with ONLY the category name, nothing else.
Choose from the available categories listed above.
"""
        
        request_path.write_text(content)
        return request_path


# Convenience function for quick import
def quick_import():
    """Import all chats from all Cursor versions."""
    db = ChatDatabase()
    return db.import_all_versions()


if __name__ == "__main__":
    # CLI for testing
    import sys
    
    db = ChatDatabase()
    
    if len(sys.argv) < 2:
        print("Usage: chat_db.py <command> [args]")
        print("Commands: import, stats, list, export <id>, export-all")
        sys.exit(1)
    
    cmd = sys.argv[1]
    
    if cmd == "import":
        results = db.import_all_versions()
        print(f"Imported: {results['total_imported']}, Skipped: {results['total_skipped']}")
        for ver, r in results["versions"].items():
            print(f"  {ver}: {r.get('imported', 0)} imported, {r.get('skipped', 0)} skipped")
    
    elif cmd == "stats":
        stats = db.get_stats()
        print(f"Total conversations: {stats['total_conversations']}")
        print(f"Total messages: {stats['total_messages']}")
        print(f"Favorites: {stats['favorites']}")
        print("By category:")
        for cat, count in stats["by_category"].items():
            print(f"  {cat}: {count}")
    
    elif cmd == "list":
        convs = db.get_conversations(limit=20)
        for c in convs:
            print(f"[{c['id'][:8]}] {c['original_title'][:50]} ({c['message_count']} msgs)")
    
    elif cmd == "export" and len(sys.argv) > 2:
        conv_id = sys.argv[2]
        # Find full ID
        convs = db.get_conversations(limit=1000)
        full_id = next((c["id"] for c in convs if c["id"].startswith(conv_id)), None)
        if full_id:
            path = db.export_to_markdown(full_id)
            print(f"Exported to: {path}")
        else:
            print(f"Conversation not found: {conv_id}")
    
    elif cmd == "export-all":
        results = db.bulk_export()
        print(f"Exported {len(results['exported'])} conversations to {results['output_dir']}")
