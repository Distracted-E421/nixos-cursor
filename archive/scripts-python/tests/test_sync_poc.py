"""
Tests for cursor_sync_poc.py - Conversation Sync POC

This tests the sync functionality for Cursor conversations.
"""

import pytest
import json
import sqlite3
from datetime import datetime
from pathlib import Path
import sys

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from cursor_sync_poc import (
    init_external_db,
    EXTERNAL_DB,
)


class TestDatabaseInit:
    """Tests for database initialization."""
    
    @pytest.fixture
    def external_db(self, temp_dir, monkeypatch):
        """Create a test external database."""
        test_db = temp_dir / "test_conversations.db"
        monkeypatch.setattr("cursor_sync_poc.EXTERNAL_DB", test_db)
        return init_external_db()
    
    def test_init_creates_tables(self, external_db):
        """Test that init_external_db creates all required tables."""
        cursor = external_db.cursor()
        
        # Get all table names
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [row[0] for row in cursor.fetchall()]
        
        assert "sync_metadata" in tables
        assert "conversations" in tables
        assert "messages" in tables
        assert "tool_calls" in tables
    
    def test_init_creates_indexes(self, external_db):
        """Test that init_external_db creates indexes."""
        cursor = external_db.cursor()
        
        cursor.execute("SELECT name FROM sqlite_master WHERE type='index'")
        indexes = [row[0] for row in cursor.fetchall()]
        
        assert "idx_messages_conversation" in indexes
        assert "idx_messages_created" in indexes
        assert "idx_tool_calls_message" in indexes
    
    def test_init_idempotent(self, temp_dir, monkeypatch):
        """Test that init_external_db can be called multiple times."""
        test_db = temp_dir / "test_conversations.db"
        monkeypatch.setattr("cursor_sync_poc.EXTERNAL_DB", test_db)
        
        # Call init twice
        db1 = init_external_db()
        db1.close()
        
        db2 = init_external_db()
        
        # Should not error and should have tables
        cursor = db2.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [row[0] for row in cursor.fetchall()]
        
        assert "conversations" in tables
        db2.close()


class TestConversationStorage:
    """Tests for conversation storage."""
    
    @pytest.fixture
    def db(self, temp_dir, monkeypatch):
        """Create a test database with sample data."""
        test_db = temp_dir / "test_conversations.db"
        monkeypatch.setattr("cursor_sync_poc.EXTERNAL_DB", test_db)
        conn = init_external_db()
        return conn
    
    def test_insert_conversation(self, db):
        """Test inserting a conversation."""
        db.execute("""
            INSERT INTO conversations (id, name, workspace, created_at, updated_at, is_archived, raw_data)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, [
            "conv-1",
            "Test Conversation",
            "workspace-hash",
            1700000000000,
            1700001000000,
            0,
            json.dumps({"test": "data"})
        ])
        db.commit()
        
        cursor = db.cursor()
        cursor.execute("SELECT * FROM conversations WHERE id = ?", ["conv-1"])
        row = cursor.fetchone()
        
        assert row is not None
    
    def test_insert_message(self, db):
        """Test inserting a message."""
        # First insert a conversation
        db.execute("""
            INSERT INTO conversations (id, name, created_at, updated_at, is_archived)
            VALUES (?, ?, ?, ?, ?)
        """, ["conv-1", "Test", 0, 0, 0])
        
        # Then insert a message
        db.execute("""
            INSERT INTO messages (id, conversation_id, type, created_at, model_name, token_count, 
                                  has_thinking, has_tool_calls, has_code_changes, raw_data)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            "msg-1",
            "conv-1",
            1,  # User message
            1700000000000,
            None,
            10,
            0,
            0,
            0,
            json.dumps({"content": "Hello"})
        ])
        db.commit()
        
        cursor = db.cursor()
        cursor.execute("SELECT * FROM messages WHERE id = ?", ["msg-1"])
        row = cursor.fetchone()
        
        assert row is not None
    
    def test_insert_tool_call(self, db):
        """Test inserting a tool call."""
        # Setup conversation and message
        db.execute("INSERT INTO conversations (id, name, created_at, updated_at, is_archived) VALUES (?, ?, ?, ?, ?)",
                   ["conv-1", "Test", 0, 0, 0])
        db.execute("""
            INSERT INTO messages (id, conversation_id, type, created_at, has_tool_calls)
            VALUES (?, ?, ?, ?, ?)
        """, ["msg-1", "conv-1", 2, 0, 1])
        
        # Insert tool call
        db.execute("""
            INSERT INTO tool_calls (message_id, tool_name, server_name, success, duration_ms)
            VALUES (?, ?, ?, ?, ?)
        """, ["msg-1", "read_file", "filesystem", 1, 150])
        db.commit()
        
        cursor = db.cursor()
        cursor.execute("SELECT * FROM tool_calls WHERE message_id = ?", ["msg-1"])
        row = cursor.fetchone()
        
        assert row is not None


class TestSyncMetadata:
    """Tests for sync metadata tracking."""
    
    @pytest.fixture
    def db(self, temp_dir, monkeypatch):
        """Create a test database."""
        test_db = temp_dir / "test_conversations.db"
        monkeypatch.setattr("cursor_sync_poc.EXTERNAL_DB", test_db)
        return init_external_db()
    
    def test_store_last_sync(self, db):
        """Test storing last sync timestamp."""
        now = datetime.now().isoformat()
        
        db.execute("""
            INSERT OR REPLACE INTO sync_metadata (key, value)
            VALUES ('last_sync', ?)
        """, [now])
        db.commit()
        
        cursor = db.cursor()
        cursor.execute("SELECT value FROM sync_metadata WHERE key = 'last_sync'")
        row = cursor.fetchone()
        
        assert row is not None
        assert row[0] == now
    
    def test_update_last_sync(self, db):
        """Test updating last sync timestamp."""
        # Insert initial value
        db.execute("INSERT INTO sync_metadata (key, value) VALUES ('last_sync', '2024-01-01')")
        db.commit()
        
        # Update it
        db.execute("INSERT OR REPLACE INTO sync_metadata (key, value) VALUES ('last_sync', '2024-01-02')")
        db.commit()
        
        cursor = db.cursor()
        cursor.execute("SELECT value FROM sync_metadata WHERE key = 'last_sync'")
        row = cursor.fetchone()
        
        assert row[0] == "2024-01-02"


class TestMessageTypes:
    """Tests for message type handling."""
    
    @pytest.fixture
    def db(self, temp_dir, monkeypatch):
        """Create a test database with messages."""
        test_db = temp_dir / "test_conversations.db"
        monkeypatch.setattr("cursor_sync_poc.EXTERNAL_DB", test_db)
        conn = init_external_db()
        
        # Add a conversation
        conn.execute("INSERT INTO conversations (id, name, created_at, updated_at, is_archived) VALUES (?, ?, ?, ?, ?)",
                     ["conv-1", "Test", 0, 0, 0])
        
        # Add messages of different types
        conn.execute("""
            INSERT INTO messages (id, conversation_id, type, created_at)
            VALUES (?, ?, ?, ?)
        """, ["msg-user", "conv-1", 1, 0])  # User
        
        conn.execute("""
            INSERT INTO messages (id, conversation_id, type, created_at, model_name)
            VALUES (?, ?, ?, ?, ?)
        """, ["msg-assistant", "conv-1", 2, 1, "claude-3-sonnet"])  # Assistant
        
        conn.commit()
        return conn
    
    def test_query_user_messages(self, db):
        """Test querying user messages."""
        cursor = db.cursor()
        cursor.execute("SELECT id FROM messages WHERE type = 1")
        rows = cursor.fetchall()
        
        assert len(rows) == 1
        assert rows[0][0] == "msg-user"
    
    def test_query_assistant_messages(self, db):
        """Test querying assistant messages."""
        cursor = db.cursor()
        cursor.execute("SELECT id, model_name FROM messages WHERE type = 2")
        rows = cursor.fetchall()
        
        assert len(rows) == 1
        assert rows[0][0] == "msg-assistant"
        assert rows[0][1] == "claude-3-sonnet"


class TestForeignKeyConstraints:
    """Tests for foreign key relationships."""
    
    @pytest.fixture
    def db(self, temp_dir, monkeypatch):
        """Create a test database."""
        test_db = temp_dir / "test_conversations.db"
        monkeypatch.setattr("cursor_sync_poc.EXTERNAL_DB", test_db)
        conn = init_external_db()
        conn.execute("PRAGMA foreign_keys = ON")
        return conn
    
    def test_messages_reference_conversations(self, db):
        """Test that messages properly reference conversations."""
        # Add conversation first
        db.execute("INSERT INTO conversations (id, name, created_at, updated_at, is_archived) VALUES (?, ?, ?, ?, ?)",
                   ["conv-1", "Test", 0, 0, 0])
        
        # Message should work
        db.execute("INSERT INTO messages (id, conversation_id, type, created_at) VALUES (?, ?, ?, ?)",
                   ["msg-1", "conv-1", 1, 0])
        db.commit()
        
        # Query with join
        cursor = db.cursor()
        cursor.execute("""
            SELECT m.id, c.name
            FROM messages m
            JOIN conversations c ON m.conversation_id = c.id
            WHERE m.id = ?
        """, ["msg-1"])
        row = cursor.fetchone()
        
        assert row is not None
        assert row[0] == "msg-1"
        assert row[1] == "Test"
    
    def test_tool_calls_reference_messages(self, db):
        """Test that tool_calls properly reference messages."""
        # Setup
        db.execute("INSERT INTO conversations (id, name, created_at, updated_at, is_archived) VALUES (?, ?, ?, ?, ?)",
                   ["conv-1", "Test", 0, 0, 0])
        db.execute("INSERT INTO messages (id, conversation_id, type, created_at) VALUES (?, ?, ?, ?)",
                   ["msg-1", "conv-1", 2, 0])
        db.execute("INSERT INTO tool_calls (message_id, tool_name, success) VALUES (?, ?, ?)",
                   ["msg-1", "test_tool", 1])
        db.commit()
        
        # Query with join
        cursor = db.cursor()
        cursor.execute("""
            SELECT t.tool_name, m.conversation_id
            FROM tool_calls t
            JOIN messages m ON t.message_id = m.id
        """)
        row = cursor.fetchone()
        
        assert row is not None
        assert row[0] == "test_tool"
        assert row[1] == "conv-1"


class TestDataIntegrity:
    """Tests for data integrity and edge cases."""
    
    @pytest.fixture
    def db(self, temp_dir, monkeypatch):
        """Create a test database."""
        test_db = temp_dir / "test_conversations.db"
        monkeypatch.setattr("cursor_sync_poc.EXTERNAL_DB", test_db)
        return init_external_db()
    
    def test_json_raw_data_storage(self, db):
        """Test that JSON raw_data is stored and retrieved correctly."""
        raw_data = {
            "complex": {
                "nested": ["array", "values"],
                "number": 42,
                "boolean": True,
            }
        }
        
        db.execute("""
            INSERT INTO conversations (id, name, created_at, updated_at, is_archived, raw_data)
            VALUES (?, ?, ?, ?, ?, ?)
        """, ["conv-1", "Test", 0, 0, 0, json.dumps(raw_data)])
        db.commit()
        
        cursor = db.cursor()
        cursor.execute("SELECT raw_data FROM conversations WHERE id = ?", ["conv-1"])
        row = cursor.fetchone()
        
        loaded = json.loads(row[0])
        assert loaded == raw_data
    
    def test_null_optional_fields(self, db):
        """Test handling of NULL optional fields."""
        db.execute("""
            INSERT INTO messages (id, conversation_id, type, created_at, model_name, token_count)
            VALUES (?, ?, ?, ?, ?, ?)
        """, ["msg-1", "conv-1", 1, 0, None, None])
        db.commit()
        
        cursor = db.cursor()
        cursor.execute("SELECT model_name, token_count FROM messages WHERE id = ?", ["msg-1"])
        row = cursor.fetchone()
        
        assert row[0] is None
        assert row[1] is None
    
    def test_large_content_storage(self, db):
        """Test storing large content in raw_data."""
        large_content = "A" * 100000  # 100KB of content
        
        db.execute("""
            INSERT INTO messages (id, conversation_id, type, created_at, raw_data)
            VALUES (?, ?, ?, ?, ?)
        """, ["msg-1", "conv-1", 2, 0, json.dumps({"content": large_content})])
        db.commit()
        
        cursor = db.cursor()
        cursor.execute("SELECT raw_data FROM messages WHERE id = ?", ["msg-1"])
        row = cursor.fetchone()
        
        loaded = json.loads(row[0])
        assert loaded["content"] == large_content

