#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "mcp>=0.1.0",
#     "httpx>=0.25.0",
#     "beautifulsoup4>=4.12.0",
#     "sqlite-utils>=3.35.0",
# ]
# ///
"""
Cursor Docs MCP Server - Custom Documentation System

This MCP server provides an alternative to Cursor's built-in @docs feature,
allowing you to:
- Add documentation URLs for indexing
- Search indexed documentation
- Get relevant chunks for queries
- Manage your own docs database

This is part of the Data Pipeline Control objectives for v0.3.0.

Usage:
    # Run as MCP server (for Cursor)
    uv run cursor_docs_mcp.py serve

    # CLI commands for management
    uv run cursor_docs_mcp.py add https://docs.example.com/
    uv run cursor_docs_mcp.py search "how to configure"
    uv run cursor_docs_mcp.py list
"""

import asyncio
import hashlib
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional
from dataclasses import dataclass

# MCP imports (will be available when running with uv)
try:
    from mcp.server import Server
    from mcp.types import Tool, TextContent
    HAS_MCP = True
except ImportError:
    HAS_MCP = False

import httpx
from bs4 import BeautifulSoup

# Configuration
DOCS_DB = Path.home() / ".local/share/cursor-studio/docs.db"
CHUNK_SIZE = 1500  # Characters per chunk
CHUNK_OVERLAP = 200  # Overlap between chunks


@dataclass
class DocChunk:
    """A chunk of documentation content."""
    id: str
    doc_id: str
    url: str
    title: str
    content: str
    position: int
    created_at: str


@dataclass
class DocSource:
    """A documentation source (website/page)."""
    id: str
    url: str
    title: str
    description: str
    chunks_count: int
    last_indexed: str
    status: str


def init_db():
    """Initialize the documentation database."""
    import sqlite_utils
    
    DOCS_DB.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite_utils.Database(DOCS_DB)
    
    # Create tables if they don't exist
    if "doc_sources" not in db.table_names():
        db["doc_sources"].create({
            "id": str,
            "url": str,
            "title": str,
            "description": str,
            "chunks_count": int,
            "last_indexed": str,
            "status": str,
        }, pk="id")
    
    if "doc_chunks" not in db.table_names():
        db["doc_chunks"].create({
            "id": str,
            "doc_id": str,
            "url": str,
            "title": str,
            "content": str,
            "position": int,
            "created_at": str,
        }, pk="id")
        db["doc_chunks"].create_index(["doc_id"])
        # Enable FTS for content search
        db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS doc_chunks_fts 
            USING fts5(content, title, url, content=doc_chunks, content_rowid=rowid)
        """)
        # Triggers to keep FTS in sync
        db.execute("""
            CREATE TRIGGER IF NOT EXISTS doc_chunks_ai AFTER INSERT ON doc_chunks BEGIN
                INSERT INTO doc_chunks_fts(rowid, content, title, url) 
                VALUES (new.rowid, new.content, new.title, new.url);
            END
        """)
    
    return db


async def fetch_page(url: str) -> tuple[str, str, str]:
    """Fetch a page and extract clean text content."""
    async with httpx.AsyncClient(follow_redirects=True, timeout=30.0) as client:
        response = await client.get(url, headers={
            "User-Agent": "CursorDocs/1.0 (Documentation Indexer)"
        })
        response.raise_for_status()
        html = response.text
    
    soup = BeautifulSoup(html, "html.parser")
    
    # Remove script and style elements
    for script in soup(["script", "style", "nav", "footer", "header"]):
        script.decompose()
    
    # Get title
    title = soup.title.string if soup.title else url
    
    # Get description from meta
    description = ""
    meta_desc = soup.find("meta", attrs={"name": "description"})
    if meta_desc:
        description = meta_desc.get("content", "")
    
    # Get main content
    main = soup.find("main") or soup.find("article") or soup.body
    if main:
        text = main.get_text(separator="\n", strip=True)
    else:
        text = soup.get_text(separator="\n", strip=True)
    
    # Clean up whitespace
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r' {2,}', ' ', text)
    
    return title, description, text


def chunk_text(text: str, chunk_size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> list[str]:
    """Split text into overlapping chunks."""
    chunks = []
    start = 0
    
    while start < len(text):
        end = start + chunk_size
        
        # Try to break at a sentence or paragraph boundary
        if end < len(text):
            # Look for paragraph break
            para_break = text.rfind('\n\n', start, end)
            if para_break > start + chunk_size // 2:
                end = para_break
            else:
                # Look for sentence break
                sent_break = text.rfind('. ', start, end)
                if sent_break > start + chunk_size // 2:
                    end = sent_break + 1
        
        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)
        
        start = end - overlap if end < len(text) else end
    
    return chunks


async def index_url(url: str) -> DocSource:
    """Index a URL and store chunks in the database."""
    import sqlite_utils
    
    db = sqlite_utils.Database(DOCS_DB)
    
    # Generate ID from URL
    doc_id = hashlib.sha256(url.encode()).hexdigest()[:16]
    
    # Check if already indexed
    existing = list(db["doc_sources"].rows_where("id = ?", [doc_id]))
    if existing:
        # Update existing
        pass
    
    try:
        title, description, text = await fetch_page(url)
        
        # Create chunks
        chunks = chunk_text(text)
        now = datetime.now().isoformat()
        
        # Delete existing chunks for this doc
        db.execute("DELETE FROM doc_chunks WHERE doc_id = ?", [doc_id])
        
        # Insert new chunks
        for i, content in enumerate(chunks):
            chunk_id = f"{doc_id}:{i}"
            db["doc_chunks"].insert({
                "id": chunk_id,
                "doc_id": doc_id,
                "url": url,
                "title": title,
                "content": content,
                "position": i,
                "created_at": now,
            }, replace=True)
        
        # Update source
        doc_source = {
            "id": doc_id,
            "url": url,
            "title": title,
            "description": description[:500] if description else "",
            "chunks_count": len(chunks),
            "last_indexed": now,
            "status": "indexed",
        }
        db["doc_sources"].insert(doc_source, replace=True)
        
        return DocSource(**doc_source)
    
    except Exception as e:
        # Record error
        db["doc_sources"].insert({
            "id": doc_id,
            "url": url,
            "title": "",
            "description": "",
            "chunks_count": 0,
            "last_indexed": datetime.now().isoformat(),
            "status": f"error: {str(e)[:100]}",
        }, replace=True)
        raise


def search_docs(query: str, limit: int = 5) -> list[DocChunk]:
    """Search indexed documentation using FTS."""
    import sqlite_utils
    
    db = sqlite_utils.Database(DOCS_DB)
    
    # Use FTS5 for search
    results = db.execute("""
        SELECT c.id, c.doc_id, c.url, c.title, c.content, c.position, c.created_at,
               bm25(doc_chunks_fts) as rank
        FROM doc_chunks_fts fts
        JOIN doc_chunks c ON fts.rowid = c.rowid
        WHERE doc_chunks_fts MATCH ?
        ORDER BY rank
        LIMIT ?
    """, [query, limit]).fetchall()
    
    return [
        DocChunk(
            id=r[0],
            doc_id=r[1],
            url=r[2],
            title=r[3],
            content=r[4],
            position=r[5],
            created_at=r[6],
        )
        for r in results
    ]


def list_sources() -> list[DocSource]:
    """List all indexed documentation sources."""
    import sqlite_utils
    
    db = sqlite_utils.Database(DOCS_DB)
    
    return [
        DocSource(**row)
        for row in db["doc_sources"].rows
    ]


def delete_source(doc_id: str) -> bool:
    """Delete a documentation source and its chunks."""
    import sqlite_utils
    
    db = sqlite_utils.Database(DOCS_DB)
    
    db.execute("DELETE FROM doc_chunks WHERE doc_id = ?", [doc_id])
    db.execute("DELETE FROM doc_sources WHERE id = ?", [doc_id])
    
    return True


# ============== MCP Server Implementation ==============

if HAS_MCP:
    server = Server("cursor-docs")

    @server.tool()
    async def add_documentation(url: str) -> str:
        """
        Add a documentation URL to be indexed and searchable.
        
        Args:
            url: The URL of the documentation page to index
            
        Returns:
            Status message with indexing results
        """
        init_db()
        try:
            doc = await index_url(url)
            return f"✅ Indexed '{doc.title}' ({doc.chunks_count} chunks)"
        except Exception as e:
            return f"❌ Failed to index: {str(e)}"

    @server.tool()
    async def search_documentation(query: str, limit: int = 5) -> str:
        """
        Search indexed documentation for relevant content.
        
        Args:
            query: The search query
            limit: Maximum number of results (default 5)
            
        Returns:
            Relevant documentation chunks with citations
        """
        init_db()
        chunks = search_docs(query, limit)
        
        if not chunks:
            return "No relevant documentation found."
        
        result = f"Found {len(chunks)} relevant sections:\n\n"
        for i, chunk in enumerate(chunks, 1):
            result += f"### {i}. {chunk.title}\n"
            result += f"**Source:** {chunk.url}\n\n"
            result += f"{chunk.content[:800]}...\n\n"
            result += "---\n\n"
        
        return result

    @server.tool()
    async def list_documentation() -> str:
        """
        List all indexed documentation sources.
        
        Returns:
            Table of indexed documentation with stats
        """
        init_db()
        sources = list_sources()
        
        if not sources:
            return "No documentation indexed yet. Use add_documentation() to add some."
        
        result = "| Title | URL | Chunks | Status |\n"
        result += "|-------|-----|--------|--------|\n"
        for src in sources:
            title = src.title[:30] + "..." if len(src.title) > 30 else src.title
            url = src.url[:40] + "..." if len(src.url) > 40 else src.url
            result += f"| {title} | {url} | {src.chunks_count} | {src.status} |\n"
        
        return result

    @server.tool()
    async def remove_documentation(url_or_id: str) -> str:
        """
        Remove a documentation source from the index.
        
        Args:
            url_or_id: The URL or ID of the documentation to remove
            
        Returns:
            Confirmation message
        """
        init_db()
        
        # Try as ID first
        if len(url_or_id) == 16:
            delete_source(url_or_id)
            return f"✅ Removed documentation {url_or_id}"
        
        # Try as URL
        doc_id = hashlib.sha256(url_or_id.encode()).hexdigest()[:16]
        delete_source(doc_id)
        return f"✅ Removed documentation for {url_or_id}"

    @server.tool()
    async def get_documentation_context(topic: str) -> str:
        """
        Get comprehensive documentation context for a topic.
        Useful for providing background information to the agent.
        
        Args:
            topic: The topic to get context for
            
        Returns:
            Combined relevant documentation
        """
        init_db()
        chunks = search_docs(topic, limit=10)
        
        if not chunks:
            return f"No documentation found for '{topic}'"
        
        # Combine chunks, deduplicating similar content
        seen_urls = set()
        context = f"# Documentation Context: {topic}\n\n"
        
        for chunk in chunks:
            if chunk.url not in seen_urls:
                seen_urls.add(chunk.url)
                context += f"## From: {chunk.title}\n"
                context += f"*Source: {chunk.url}*\n\n"
            context += f"{chunk.content}\n\n"
        
        return context


# ============== CLI Implementation ==============

async def cli_add(url: str):
    """CLI: Add a documentation URL."""
    init_db()
    print(f"📥 Indexing {url}...")
    try:
        doc = await index_url(url)
        print(f"✅ Indexed '{doc.title}'")
        print(f"   Chunks: {doc.chunks_count}")
        print(f"   ID: {doc.id}")
    except Exception as e:
        print(f"❌ Failed: {e}")


def cli_search(query: str):
    """CLI: Search documentation."""
    init_db()
    print(f"🔍 Searching for: {query}\n")
    chunks = search_docs(query)
    
    if not chunks:
        print("No results found.")
        return
    
    for i, chunk in enumerate(chunks, 1):
        print(f"━━━ Result {i} ━━━")
        print(f"Title: {chunk.title}")
        print(f"URL: {chunk.url}")
        print(f"Content:\n{chunk.content[:500]}...")
        print()


def cli_list():
    """CLI: List all documentation sources."""
    init_db()
    sources = list_sources()
    
    if not sources:
        print("No documentation indexed yet.")
        return
    
    print(f"📚 Indexed Documentation ({len(sources)} sources)\n")
    for src in sources:
        status_icon = "✅" if src.status == "indexed" else "❌"
        print(f"{status_icon} {src.title}")
        print(f"   URL: {src.url}")
        print(f"   Chunks: {src.chunks_count}")
        print(f"   Last indexed: {src.last_indexed}")
        print()


async def cli_serve():
    """CLI: Run as MCP server."""
    if not HAS_MCP:
        print("❌ MCP library not installed. Run with 'uv run' to get dependencies.")
        sys.exit(1)
    
    from mcp.server.stdio import stdio_server
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "serve":
        asyncio.run(cli_serve())
    elif command == "add":
        if len(sys.argv) < 3:
            print("Usage: cursor_docs_mcp.py add <url>")
            sys.exit(1)
        asyncio.run(cli_add(sys.argv[2]))
    elif command == "search":
        if len(sys.argv) < 3:
            print("Usage: cursor_docs_mcp.py search <query>")
            sys.exit(1)
        cli_search(" ".join(sys.argv[2:]))
    elif command == "list":
        cli_list()
    else:
        print(f"Unknown command: {command}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
