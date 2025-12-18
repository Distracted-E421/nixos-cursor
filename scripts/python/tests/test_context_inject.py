"""
Tests for cursor_context_inject.py - Context Injection MCP Server

This tests the ContextStore and context item management functionality.
"""

import pytest
import json
from datetime import datetime, timedelta
from pathlib import Path
import sys

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from cursor_context_inject import (
    ContextItem,
    ContextStore,
    CONTEXT_STORE,
)


class TestContextItem:
    """Tests for ContextItem dataclass."""
    
    def test_context_item_creation(self):
        """Test basic context item creation."""
        item = ContextItem(
            key="test-key",
            content="Test content",
            priority=5,
            category="memory",
            created_at=datetime.now().isoformat(),
        )
        
        assert item.key == "test-key"
        assert item.content == "Test content"
        assert item.priority == 5
        assert item.category == "memory"
        assert item.expires_at is None
        assert item.source is None
    
    def test_context_item_with_optional_fields(self):
        """Test context item with all optional fields."""
        now = datetime.now()
        expires = now + timedelta(hours=24)
        
        item = ContextItem(
            key="full-item",
            content="Full content",
            priority=8,
            category="project",
            created_at=now.isoformat(),
            expires_at=expires.isoformat(),
            source="conversation-123",
        )
        
        assert item.expires_at == expires.isoformat()
        assert item.source == "conversation-123"
    
    def test_context_item_serialization(self):
        """Test context item can be serialized to JSON."""
        from dataclasses import asdict
        
        item = ContextItem(
            key="serialize-test",
            content="Content",
            priority=5,
            category="memory",
            created_at="2024-01-01T00:00:00",
        )
        
        data = asdict(item)
        json_str = json.dumps(data)
        loaded = json.loads(json_str)
        
        assert loaded["key"] == "serialize-test"
        assert loaded["priority"] == 5


class TestContextStore:
    """Tests for ContextStore class."""
    
    @pytest.fixture
    def store(self, temp_dir, monkeypatch):
        """Create a ContextStore with a temp path."""
        test_path = temp_dir / "test_context.json"
        monkeypatch.setattr("cursor_context_inject.CONTEXT_STORE", test_path)
        return ContextStore()
    
    def test_store_empty_initially(self, store):
        """Test that a new store is empty."""
        assert len(store.items) == 0
    
    def test_add_item(self, store):
        """Test adding a context item."""
        item = ContextItem(
            key="test-add",
            content="Added content",
            priority=5,
            category="memory",
            created_at=datetime.now().isoformat(),
        )
        
        store.add(item)
        
        assert "test-add" in store.items
        assert store.items["test-add"].content == "Added content"
    
    def test_get_item(self, store):
        """Test retrieving a context item."""
        item = ContextItem(
            key="test-get",
            content="Get me",
            priority=5,
            category="memory",
            created_at=datetime.now().isoformat(),
        )
        store.add(item)
        
        retrieved = store.get("test-get")
        assert retrieved is not None
        assert retrieved.content == "Get me"
    
    def test_get_nonexistent_item(self, store):
        """Test getting an item that doesn't exist."""
        retrieved = store.get("nonexistent")
        assert retrieved is None
    
    def test_remove_item(self, store):
        """Test removing a context item."""
        item = ContextItem(
            key="test-remove",
            content="Remove me",
            priority=5,
            category="memory",
            created_at=datetime.now().isoformat(),
        )
        store.add(item)
        
        assert store.remove("test-remove") is True
        assert store.get("test-remove") is None
    
    def test_remove_nonexistent_item(self, store):
        """Test removing an item that doesn't exist."""
        assert store.remove("nonexistent") is False
    
    def test_search_by_content(self, store, sample_context_items):
        """Test searching context by content."""
        for item_data in sample_context_items:
            item = ContextItem(**item_data)
            store.add(item)
        
        # Search for "NixOS"
        results = store.search("nixos")
        assert len(results) >= 1
        assert any("nixos" in r.content.lower() for r in results)
    
    def test_search_by_key(self, store, sample_context_items):
        """Test searching context by key."""
        for item_data in sample_context_items:
            item = ContextItem(**item_data)
            store.add(item)
        
        results = store.search("gpu")
        assert len(results) >= 1
        assert any("gpu" in r.key.lower() for r in results)
    
    def test_search_by_category(self, store, sample_context_items):
        """Test searching with category filter."""
        for item_data in sample_context_items:
            item = ContextItem(**item_data)
            store.add(item)
        
        results = store.search("", category="project")
        assert all(r.category == "project" for r in results)
    
    def test_search_results_sorted_by_priority(self, store):
        """Test that search results are sorted by priority."""
        items = [
            ContextItem(key="low", content="test", priority=1, category="memory",
                       created_at=datetime.now().isoformat()),
            ContextItem(key="high", content="test", priority=9, category="memory",
                       created_at=datetime.now().isoformat()),
            ContextItem(key="medium", content="test", priority=5, category="memory",
                       created_at=datetime.now().isoformat()),
        ]
        
        for item in items:
            store.add(item)
        
        results = store.search("test")
        priorities = [r.priority for r in results]
        assert priorities == sorted(priorities, reverse=True)
    
    def test_get_by_category(self, store, sample_context_items):
        """Test getting all items in a category."""
        for item_data in sample_context_items:
            item = ContextItem(**item_data)
            store.add(item)
        
        memory_items = store.get_by_category("memory")
        assert all(item.category == "memory" for item in memory_items)
    
    def test_get_all_context_respects_token_limit(self, store):
        """Test that get_all_context respects token limit."""
        # Add a large item
        large_content = "A" * 50000  # 50KB of content
        item = ContextItem(
            key="large",
            content=large_content,
            priority=5,
            category="memory",
            created_at=datetime.now().isoformat(),
        )
        store.add(item)
        
        # With small token limit, should truncate
        context = store.get_all_context(max_tokens=100)
        assert len(context) < len(large_content)
    
    def test_persistence(self, temp_dir, monkeypatch):
        """Test that context persists across store instances."""
        test_path = temp_dir / "persist_test.json"
        monkeypatch.setattr("cursor_context_inject.CONTEXT_STORE", test_path)
        
        # Create store and add item
        store1 = ContextStore()
        item = ContextItem(
            key="persist-test",
            content="Should persist",
            priority=5,
            category="memory",
            created_at=datetime.now().isoformat(),
        )
        store1.add(item)
        
        # Create new store instance (simulating restart)
        store2 = ContextStore()
        
        # Item should still be there
        retrieved = store2.get("persist-test")
        assert retrieved is not None
        assert retrieved.content == "Should persist"
    
    def test_update_existing_item(self, store):
        """Test that adding an item with existing key updates it."""
        item1 = ContextItem(
            key="update-test",
            content="Original",
            priority=5,
            category="memory",
            created_at=datetime.now().isoformat(),
        )
        store.add(item1)
        
        item2 = ContextItem(
            key="update-test",
            content="Updated",
            priority=8,
            category="project",
            created_at=datetime.now().isoformat(),
        )
        store.add(item2)
        
        retrieved = store.get("update-test")
        assert retrieved.content == "Updated"
        assert retrieved.priority == 8
        assert retrieved.category == "project"


class TestContextCategories:
    """Tests for context category handling."""
    
    @pytest.fixture
    def store(self, temp_dir, monkeypatch):
        """Create a ContextStore with a temp path."""
        test_path = temp_dir / "test_context.json"
        monkeypatch.setattr("cursor_context_inject.CONTEXT_STORE", test_path)
        return ContextStore()
    
    def test_valid_categories(self, store):
        """Test that valid categories work correctly."""
        categories = ["memory", "docs", "conversation", "project"]
        
        for i, cat in enumerate(categories):
            item = ContextItem(
                key=f"cat-{cat}",
                content=f"Content for {cat}",
                priority=5,
                category=cat,
                created_at=datetime.now().isoformat(),
            )
            store.add(item)
        
        for cat in categories:
            items = store.get_by_category(cat)
            assert len(items) == 1
            assert items[0].category == cat


class TestContextExpiration:
    """Tests for context expiration handling."""
    
    @pytest.fixture
    def store(self, temp_dir, monkeypatch):
        """Create a ContextStore with a temp path."""
        test_path = temp_dir / "test_context.json"
        monkeypatch.setattr("cursor_context_inject.CONTEXT_STORE", test_path)
        return ContextStore()
    
    def test_expired_items_excluded_from_search(self, store):
        """Test that expired items are excluded from search results."""
        past = datetime.now() - timedelta(hours=1)
        
        item = ContextItem(
            key="expired",
            content="Should not appear",
            priority=10,
            category="memory",
            created_at=(datetime.now() - timedelta(days=1)).isoformat(),
            expires_at=past.isoformat(),
        )
        store.add(item)
        
        results = store.search("appear")
        assert len(results) == 0
    
    def test_non_expired_items_included(self, store):
        """Test that non-expired items are included in search results."""
        future = datetime.now() + timedelta(hours=24)
        
        item = ContextItem(
            key="not-expired",
            content="Should appear in search",
            priority=5,
            category="memory",
            created_at=datetime.now().isoformat(),
            expires_at=future.isoformat(),
        )
        store.add(item)
        
        results = store.search("appear")
        assert len(results) == 1
    
    def test_items_without_expiration_always_included(self, store):
        """Test that items without expiration are always included."""
        item = ContextItem(
            key="no-expiry",
            content="Always available",
            priority=5,
            category="memory",
            created_at=datetime.now().isoformat(),
            expires_at=None,
        )
        store.add(item)
        
        results = store.search("available")
        assert len(results) == 1

