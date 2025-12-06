#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "watchfiles>=0.21.0",
# ]
# ///
"""
Cursor Conversation Sync - Proof of Concept

Syncs Cursor IDE conversations to an external SQLite database for redundancy.
This is a POC for the Data Pipeline Control objectives in v0.3.0/v0.4.0.

Usage:
    uv run cursor_sync_poc.py sync       # One-time sync
    uv run cursor_sync_poc.py watch      # Continuous sync with file watching
    uv run cursor_sync_poc.py stats      # Show sync statistics
    uv run cursor_sync_poc.py export     # Export conversations to JSON

⚠️  SPECULATIVE: This script reads from Cursor's internal database.
    Database schema may change between Cursor versions.
"""

import sqlite3
import json
import sys
import time
from pathlib import Path
from datetime import datetime
from typing import Optional

# Paths
CURSOR_DB = Path.home() / ".config/Cursor/User/globalStorage/state.vscdb"
EXTERNAL_DB = Path.home() / ".local/share/cursor-studio/conversations.db"
EXPORT_DIR = Path.home() / ".local/share/cursor-studio/exports"


def init_external_db() -> sqlite3.Connection:
    """Initialize the external sync database."""
    EXTERNAL_DB.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(EXTERNAL_DB)
    
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS sync_metadata (
            key TEXT PRIMARY KEY,
            value TEXT
        );
        
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            name TEXT,
            workspace TEXT,
            model TEXT,
            created_at INTEGER,
            updated_at INTEGER,
            message_count INTEGER DEFAULT 0,
            total_tokens INTEGER DEFAULT 0,
            is_agentic INTEGER DEFAULT 0,
            is_archived INTEGER DEFAULT 0,
            raw_data JSON
        );
        
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            type INTEGER,
            created_at INTEGER,
            model_name TEXT,
            token_count INTEGER DEFAULT 0,
            has_thinking INTEGER DEFAULT 0,
            has_tool_calls INTEGER DEFAULT 0,
            has_code_changes INTEGER DEFAULT 0,
            raw_data JSON,
            FOREIGN KEY (conversation_id) REFERENCES conversations(id)
        );
        
        CREATE TABLE IF NOT EXISTS tool_calls (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            message_id TEXT NOT NULL,
            tool_name TEXT,
            server_name TEXT,
            success INTEGER,
            duration_ms INTEGER,
            FOREIGN KEY (message_id) REFERENCES messages(id)
        );
        
        CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);
        CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at);
        CREATE INDEX IF NOT EXISTS idx_tool_calls_message ON tool_calls(message_id);
    """)
    
    conn.commit()
    return conn


def open_cursor_db_readonly() -> Optional[sqlite3.Connection]:
    """Open Cursor's database in read-only mode."""
    if not CURSOR_DB.exists():
        print(f"❌ Cursor database not found: {CURSOR_DB}")
        return None
    
    try:
        conn = sqlite3.connect(f"file:{CURSOR_DB}?mode=ro", uri=True)
        return conn
    except sqlite3.OperationalError as e:
        print(f"❌ Could not open Cursor database: {e}")
        print("   (Is Cursor running? Try closing it briefly)")
        return None


def sync_conversations(cursor_conn: sqlite3.Connection, external_conn: sqlite3.Connection) -> dict:
    """Sync all conversations from Cursor to external database."""
    stats = {
        "conversations": 0,
        "messages": 0,
        "tool_calls": 0,
        "errors": 0,
    }
    
    # Get all bubble messages
    bubbles = cursor_conn.execute(
        "SELECT key, value FROM cursorDiskKV WHERE key LIKE 'bubbleId:%'"
    ).fetchall()
    
    for key, value in bubbles:
        try:
            parts = key.split(":")
            if len(parts) < 3:
                continue
                
            conv_id = parts[1]
            bubble_id = parts[2]
            data = json.loads(value)
            
            # Extract message metadata (handle potential non-primitive types)
            msg_type = data.get("type", 0)
            if not isinstance(msg_type, int):
                msg_type = 0
            created_at = data.get("createdAt")
            if not isinstance(created_at, (int, type(None))):
                created_at = None
            model_info = data.get("modelInfo", {})
            if isinstance(model_info, dict):
                model_name = model_info.get("modelName")
            else:
                model_name = None
            token_count = data.get("tokenCount", 0)
            if not isinstance(token_count, int):
                token_count = 0
            thinking_blocks = data.get("allThinkingBlocks", [])
            tool_results = data.get("toolResults", [])
            code_changes = data.get("assistantSuggestedDiffs", [])
            
            # Insert/update message
            external_conn.execute("""
                INSERT OR REPLACE INTO messages 
                (id, conversation_id, type, created_at, model_name, token_count, 
                 has_thinking, has_tool_calls, has_code_changes, raw_data)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                bubble_id, conv_id, msg_type, created_at, model_name, token_count,
                1 if thinking_blocks else 0,
                1 if tool_results else 0,
                1 if code_changes else 0,
                value
            ))
            
            # Extract tool calls
            for tool in tool_results:
                if isinstance(tool, dict):
                    external_conn.execute("""
                        INSERT INTO tool_calls (message_id, tool_name, server_name, success, duration_ms)
                        VALUES (?, ?, ?, ?, ?)
                    """, (
                        bubble_id,
                        tool.get("name"),
                        tool.get("server"),
                        1 if tool.get("success") else 0,
                        tool.get("duration")
                    ))
                    stats["tool_calls"] += 1
            
            stats["messages"] += 1
            
        except (json.JSONDecodeError, KeyError) as e:
            stats["errors"] += 1
    
    # Try to get conversation metadata from workspace storage databases
    workspace_storage = Path.home() / ".config/Cursor/User/workspaceStorage"
    if workspace_storage.exists():
        for ws_dir in workspace_storage.iterdir():
            ws_db = ws_dir / "state.vscdb"
            if ws_db.exists():
                try:
                    ws_conn = sqlite3.connect(f"file:{ws_db}?mode=ro", uri=True)
                    rows = ws_conn.execute("""
                        SELECT value FROM ItemTable 
                        WHERE key = 'composer.composerData'
                    """).fetchall()
                    
                    for (value,) in rows:
                        try:
                            composer_data = json.loads(value)
                            composers = composer_data.get("allComposers", [])
                            
                            for comp in composers:
                                if comp.get("type") == "head":
                                    conv_id = comp.get("composerId")
                                    if conv_id:
                                        external_conn.execute("""
                                            INSERT OR REPLACE INTO conversations
                                            (id, name, workspace, created_at, updated_at, is_archived, raw_data)
                                            VALUES (?, ?, ?, ?, ?, ?, ?)
                                        """, (
                                            conv_id,
                                            comp.get("name", "Untitled"),
                                            str(ws_dir.name),  # workspace hash
                                            comp.get("createdAt"),
                                            comp.get("lastUpdatedAt"),
                                            1 if comp.get("isArchived") else 0,
                                            json.dumps(comp)
                                        ))
                                        stats["conversations"] += 1
                        except json.JSONDecodeError:
                            pass
                    
                    ws_conn.close()
                except sqlite3.OperationalError:
                    pass  # Workspace database locked or unavailable
    
    # Update sync timestamp
    external_conn.execute("""
        INSERT OR REPLACE INTO sync_metadata (key, value)
        VALUES ('last_sync', ?)
    """, (datetime.now().isoformat(),))
    
    external_conn.commit()
    return stats


def show_stats(external_conn: sqlite3.Connection):
    """Show sync statistics."""
    print("\n📊 Cursor Sync Statistics\n")
    
    # Last sync
    row = external_conn.execute(
        "SELECT value FROM sync_metadata WHERE key = 'last_sync'"
    ).fetchone()
    if row:
        print(f"🕐 Last sync: {row[0]}")
    
    # Counts
    msg_count = external_conn.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
    conv_count = external_conn.execute("SELECT COUNT(*) FROM conversations").fetchone()[0]
    tool_count = external_conn.execute("SELECT COUNT(*) FROM tool_calls").fetchone()[0]
    
    print(f"\n📝 Messages:      {msg_count:,}")
    print(f"💬 Conversations: {conv_count:,}")
    print(f"🔧 Tool Calls:    {tool_count:,}")
    
    # Database size
    db_size = EXTERNAL_DB.stat().st_size / 1024 / 1024
    print(f"\n💾 Database size: {db_size:.2f} MB")
    print(f"📁 Location: {EXTERNAL_DB}")
    
    # Recent conversations
    print("\n📋 Recent Conversations:")
    rows = external_conn.execute("""
        SELECT name, updated_at, 
               (SELECT COUNT(*) FROM messages WHERE conversation_id = conversations.id) as msg_count
        FROM conversations
        ORDER BY updated_at DESC
        LIMIT 5
    """).fetchall()
    
    for name, updated_at, msg_count in rows:
        if updated_at:
            ts = datetime.fromtimestamp(updated_at / 1000).strftime("%Y-%m-%d %H:%M")
        else:
            ts = "Unknown"
        name = name[:50] if name else "Untitled"
        print(f"  • {name} ({msg_count} msgs, {ts})")


def export_conversations(external_conn: sqlite3.Connection, output_path: Optional[Path] = None):
    """Export conversations to JSON for external use."""
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    
    if output_path is None:
        output_path = EXPORT_DIR / f"conversations_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    
    conversations = []
    
    for row in external_conn.execute("""
        SELECT id, name, created_at, updated_at, is_archived, raw_data
        FROM conversations
        ORDER BY updated_at DESC
    """).fetchall():
        conv_id, name, created_at, updated_at, is_archived, raw_data = row
        
        # Get messages for this conversation
        messages = []
        for msg_row in external_conn.execute("""
            SELECT id, type, created_at, model_name, token_count, 
                   has_thinking, has_tool_calls, has_code_changes, raw_data
            FROM messages
            WHERE conversation_id = ?
            ORDER BY created_at
        """, (conv_id,)).fetchall():
            msg_id, msg_type, created, model, tokens, thinking, tools, code, data = msg_row
            messages.append({
                "id": msg_id,
                "type": "user" if msg_type == 1 else "assistant",
                "created_at": created,
                "model": model,
                "token_count": tokens,
                "has_thinking": bool(thinking),
                "has_tool_calls": bool(tools),
                "has_code_changes": bool(code),
            })
        
        conversations.append({
            "id": conv_id,
            "name": name,
            "created_at": created_at,
            "updated_at": updated_at,
            "is_archived": bool(is_archived),
            "message_count": len(messages),
            "messages": messages,
        })
    
    with open(output_path, "w") as f:
        json.dump({
            "exported_at": datetime.now().isoformat(),
            "exported_by": "cursor-sync-poc",
            "conversation_count": len(conversations),
            "conversations": conversations,
        }, f, indent=2)
    
    print(f"✅ Exported {len(conversations)} conversations to {output_path}")


def watch_and_sync():
    """Continuously watch for changes and sync."""
    from watchfiles import watch
    
    print(f"👀 Watching {CURSOR_DB} for changes...")
    print("   Press Ctrl+C to stop\n")
    
    external_conn = init_external_db()
    
    for changes in watch(CURSOR_DB.parent):
        for change_type, path in changes:
            if Path(path).name == "state.vscdb":
                print(f"\n🔄 Change detected, syncing...")
                cursor_conn = open_cursor_db_readonly()
                if cursor_conn:
                    try:
                        stats = sync_conversations(cursor_conn, external_conn)
                        print(f"   ✅ Synced: {stats['messages']} messages, {stats['tool_calls']} tool calls")
                    finally:
                        cursor_conn.close()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "sync":
        print("🔄 Syncing Cursor conversations...")
        cursor_conn = open_cursor_db_readonly()
        if not cursor_conn:
            sys.exit(1)
        
        external_conn = init_external_db()
        
        try:
            stats = sync_conversations(cursor_conn, external_conn)
            print(f"\n✅ Sync complete!")
            print(f"   Messages:      {stats['messages']:,}")
            print(f"   Conversations: {stats['conversations']:,}")
            print(f"   Tool Calls:    {stats['tool_calls']:,}")
            if stats['errors']:
                print(f"   ⚠️  Errors:     {stats['errors']}")
        finally:
            cursor_conn.close()
            external_conn.close()
    
    elif command == "watch":
        watch_and_sync()
    
    elif command == "stats":
        if not EXTERNAL_DB.exists():
            print("❌ No sync database found. Run 'sync' first.")
            sys.exit(1)
        
        external_conn = sqlite3.connect(EXTERNAL_DB)
        show_stats(external_conn)
        external_conn.close()
    
    elif command == "export":
        if not EXTERNAL_DB.exists():
            print("❌ No sync database found. Run 'sync' first.")
            sys.exit(1)
        
        external_conn = sqlite3.connect(EXTERNAL_DB)
        output = Path(sys.argv[2]) if len(sys.argv) > 2 else None
        export_conversations(external_conn, output)
        external_conn.close()
    
    else:
        print(f"❌ Unknown command: {command}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
