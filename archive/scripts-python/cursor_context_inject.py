#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "mcp>=0.1.0",
# ]
# ///
"""
Cursor Context Injection MCP Server

This MCP server allows injecting arbitrary context into the agent's context window.
Use cases:
- Resume previous conversations with context summary
- Inject project-specific knowledge
- Provide persistent memory across sessions
- Add custom documentation without indexing

Part of the Data Pipeline Control objectives for v0.4.0.

Usage:
    # Add to MCP configuration:
    {
      "mcpServers": {
        "context-inject": {
          "command": "uv",
          "args": ["run", "/path/to/cursor_context_inject.py", "serve"]
        }
      }
    }
"""

import asyncio
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional
from dataclasses import dataclass, asdict

try:
    from mcp.server import Server
    from mcp.types import Tool, TextContent
    HAS_MCP = True
except ImportError:
    HAS_MCP = False

# Storage
CONTEXT_STORE = Path.home() / ".local/share/cursor-studio/injected_context.json"


@dataclass
class ContextItem:
    """An item of injected context."""
    key: str
    content: str
    priority: int  # 1-10, higher = more important
    category: str  # "memory", "docs", "conversation", "project"
    created_at: str
    expires_at: Optional[str] = None
    source: Optional[str] = None


class ContextStore:
    """Persistent storage for injected context."""
    
    def __init__(self):
        self.items: dict[str, ContextItem] = {}
        self.load()
    
    def load(self):
        """Load context from disk."""
        if CONTEXT_STORE.exists():
            try:
                data = json.loads(CONTEXT_STORE.read_text())
                self.items = {
                    k: ContextItem(**v) for k, v in data.items()
                }
            except (json.JSONDecodeError, TypeError):
                self.items = {}
    
    def save(self):
        """Save context to disk."""
        CONTEXT_STORE.parent.mkdir(parents=True, exist_ok=True)
        data = {k: asdict(v) for k, v in self.items.items()}
        CONTEXT_STORE.write_text(json.dumps(data, indent=2))
    
    def add(self, item: ContextItem) -> None:
        """Add or update a context item."""
        self.items[item.key] = item
        self.save()
    
    def get(self, key: str) -> Optional[ContextItem]:
        """Get a context item by key."""
        return self.items.get(key)
    
    def remove(self, key: str) -> bool:
        """Remove a context item."""
        if key in self.items:
            del self.items[key]
            self.save()
            return True
        return False
    
    def search(self, query: str, category: Optional[str] = None) -> list[ContextItem]:
        """Search for context items matching query."""
        results = []
        query_lower = query.lower()
        
        for item in self.items.values():
            # Check expiration
            if item.expires_at:
                if datetime.fromisoformat(item.expires_at) < datetime.now():
                    continue
            
            # Filter by category
            if category and item.category != category:
                continue
            
            # Check if query matches
            if (query_lower in item.key.lower() or 
                query_lower in item.content.lower() or
                query_lower in item.category.lower()):
                results.append(item)
        
        # Sort by priority
        results.sort(key=lambda x: x.priority, reverse=True)
        return results
    
    def get_by_category(self, category: str) -> list[ContextItem]:
        """Get all items in a category."""
        return [
            item for item in self.items.values()
            if item.category == category
        ]
    
    def get_all_context(self, max_tokens: int = 10000) -> str:
        """Get all context formatted for injection, within token limit."""
        # Sort by priority, then by creation date
        all_items = sorted(
            self.items.values(),
            key=lambda x: (x.priority, x.created_at),
            reverse=True
        )
        
        context_parts = []
        total_chars = 0
        char_limit = max_tokens * 4  # Rough estimate: 1 token ≈ 4 chars
        
        for item in all_items:
            item_text = f"## {item.category.title()}: {item.key}\n{item.content}\n"
            if total_chars + len(item_text) > char_limit:
                break
            context_parts.append(item_text)
            total_chars += len(item_text)
        
        if not context_parts:
            return "No injected context available."
        
        return "# Injected Context\n\n" + "\n---\n\n".join(context_parts)


# Global store
store = ContextStore()


# ============== MCP Server Implementation ==============

if HAS_MCP:
    server = Server("context-inject")

    @server.tool()
    async def inject_context(
        key: str,
        content: str,
        category: str = "memory",
        priority: int = 5,
        expires_hours: Optional[int] = None,
        source: Optional[str] = None
    ) -> str:
        """
        Inject context that will be available in future conversations.
        
        Args:
            key: Unique identifier for this context (use descriptive names)
            content: The context content to inject
            category: Category - "memory", "docs", "conversation", "project"
            priority: 1-10, higher priority items are included first
            expires_hours: Optional hours until expiration (None = never)
            source: Optional source description (e.g., "conversation-123")
            
        Returns:
            Confirmation message
        """
        now = datetime.now()
        expires_at = None
        if expires_hours:
            from datetime import timedelta
            expires_at = (now + timedelta(hours=expires_hours)).isoformat()
        
        item = ContextItem(
            key=key,
            content=content,
            priority=max(1, min(10, priority)),
            category=category,
            created_at=now.isoformat(),
            expires_at=expires_at,
            source=source,
        )
        
        store.add(item)
        return f"✅ Context '{key}' injected (category: {category}, priority: {priority})"

    @server.tool()
    async def get_injected_context(
        query: Optional[str] = None,
        category: Optional[str] = None,
        max_tokens: int = 5000
    ) -> str:
        """
        Retrieve injected context. Call this to access previously stored context.
        
        Args:
            query: Optional search query to filter context
            category: Optional category filter ("memory", "docs", "conversation", "project")
            max_tokens: Maximum tokens to return (default 5000)
            
        Returns:
            Formatted context for inclusion in conversation
        """
        if query:
            items = store.search(query, category)
        elif category:
            items = store.get_by_category(category)
        else:
            return store.get_all_context(max_tokens)
        
        if not items:
            return f"No context found{' for query: ' + query if query else ''}"
        
        parts = []
        for item in items[:10]:  # Limit to 10 items
            parts.append(f"### {item.key}\n*Category: {item.category} | Priority: {item.priority}*\n\n{item.content}")
        
        return "# Retrieved Context\n\n" + "\n\n---\n\n".join(parts)

    @server.tool()
    async def list_injected_context() -> str:
        """
        List all injected context items without content.
        
        Returns:
            Table of context items with metadata
        """
        if not store.items:
            return "No context items stored."
        
        result = "| Key | Category | Priority | Created | Expires |\n"
        result += "|-----|----------|----------|---------|--------|\n"
        
        for item in sorted(store.items.values(), key=lambda x: x.priority, reverse=True):
            expires = item.expires_at[:10] if item.expires_at else "Never"
            result += f"| {item.key[:30]} | {item.category} | {item.priority} | {item.created_at[:10]} | {expires} |\n"
        
        return result

    @server.tool()
    async def remove_injected_context(key: str) -> str:
        """
        Remove an injected context item.
        
        Args:
            key: The key of the context to remove
            
        Returns:
            Confirmation message
        """
        if store.remove(key):
            return f"✅ Removed context '{key}'"
        return f"❌ Context '{key}' not found"

    @server.tool()
    async def summarize_conversation_for_injection(
        conversation_summary: str,
        key: str,
        priority: int = 7
    ) -> str:
        """
        Store a conversation summary for future reference.
        Use this to remember important context from the current conversation.
        
        Args:
            conversation_summary: A summary of the current conversation
            key: Unique key for this summary (e.g., "nixos-migration-plan")
            priority: Priority 1-10 (default 7 for conversation summaries)
            
        Returns:
            Confirmation message
        """
        item = ContextItem(
            key=key,
            content=conversation_summary,
            priority=priority,
            category="conversation",
            created_at=datetime.now().isoformat(),
            source="conversation_summary",
        )
        store.add(item)
        return f"✅ Conversation summary stored as '{key}'"

    @server.tool()
    async def inject_project_context(
        project_name: str,
        context: str,
        priority: int = 8
    ) -> str:
        """
        Inject project-specific context that should be available in all conversations
        about this project.
        
        Args:
            project_name: Name of the project
            context: Project context (architecture, conventions, important files, etc.)
            priority: Priority 1-10 (default 8 for project context)
            
        Returns:
            Confirmation message
        """
        key = f"project:{project_name}"
        item = ContextItem(
            key=key,
            content=context,
            priority=priority,
            category="project",
            created_at=datetime.now().isoformat(),
        )
        store.add(item)
        return f"✅ Project context for '{project_name}' stored"


# ============== CLI ==============

def cli_list():
    """List all context items."""
    if not store.items:
        print("No context items stored.")
        return
    
    print(f"📚 Injected Context ({len(store.items)} items)\n")
    for item in sorted(store.items.values(), key=lambda x: x.priority, reverse=True):
        print(f"  [{item.priority}] {item.category}/{item.key}")
        print(f"      Created: {item.created_at[:16]}")
        print(f"      Content: {item.content[:100]}...")
        print()


def cli_add(key: str, content: str, category: str = "memory", priority: int = 5):
    """Add context from CLI."""
    item = ContextItem(
        key=key,
        content=content,
        priority=priority,
        category=category,
        created_at=datetime.now().isoformat(),
    )
    store.add(item)
    print(f"✅ Added context '{key}'")


def cli_remove(key: str):
    """Remove context from CLI."""
    if store.remove(key):
        print(f"✅ Removed '{key}'")
    else:
        print(f"❌ Not found: '{key}'")


def cli_show(key: str):
    """Show a specific context item."""
    item = store.get(key)
    if item:
        print(f"Key: {item.key}")
        print(f"Category: {item.category}")
        print(f"Priority: {item.priority}")
        print(f"Created: {item.created_at}")
        print(f"Expires: {item.expires_at or 'Never'}")
        print(f"Source: {item.source or 'N/A'}")
        print(f"\nContent:\n{item.content}")
    else:
        print(f"❌ Not found: '{key}'")


async def cli_serve():
    """Run as MCP server."""
    if not HAS_MCP:
        print("❌ MCP library not available")
        sys.exit(1)
    
    from mcp.server.stdio import stdio_server
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    cmd = sys.argv[1]
    
    if cmd == "serve":
        asyncio.run(cli_serve())
    elif cmd == "list":
        cli_list()
    elif cmd == "add":
        if len(sys.argv) < 4:
            print("Usage: cursor_context_inject.py add <key> <content> [category] [priority]")
            sys.exit(1)
        cli_add(
            sys.argv[2],
            sys.argv[3],
            sys.argv[4] if len(sys.argv) > 4 else "memory",
            int(sys.argv[5]) if len(sys.argv) > 5 else 5,
        )
    elif cmd == "remove":
        if len(sys.argv) < 3:
            print("Usage: cursor_context_inject.py remove <key>")
            sys.exit(1)
        cli_remove(sys.argv[2])
    elif cmd == "show":
        if len(sys.argv) < 3:
            print("Usage: cursor_context_inject.py show <key>")
            sys.exit(1)
        cli_show(sys.argv[2])
    else:
        print(f"Unknown command: {cmd}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
