"""
Pytest configuration and shared fixtures for Python script tests.
"""

import pytest
import tempfile
import json
from pathlib import Path
from datetime import datetime


@pytest.fixture
def temp_dir():
    """Create a temporary directory for test files."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def mock_context_store(temp_dir):
    """Create a mock context store file path."""
    return temp_dir / "context_store.json"


@pytest.fixture
def mock_docs_db(temp_dir):
    """Create a mock docs database path."""
    return temp_dir / "docs.db"


@pytest.fixture
def sample_context_items():
    """Sample context items for testing."""
    return [
        {
            "key": "nixos-config",
            "content": "NixOS configuration for homelab using flakes",
            "priority": 8,
            "category": "project",
            "created_at": datetime.now().isoformat(),
            "expires_at": None,
            "source": "test",
        },
        {
            "key": "gpu-setup",
            "content": "Obsidian has Intel Arc A770 + RTX 2080",
            "priority": 9,
            "category": "memory",
            "created_at": datetime.now().isoformat(),
            "expires_at": None,
            "source": "test",
        },
        {
            "key": "temp-note",
            "content": "Temporary debugging note",
            "priority": 3,
            "category": "memory",
            "created_at": datetime.now().isoformat(),
            "expires_at": (datetime.now()).isoformat(),  # Already expired
            "source": "test",
        },
    ]


@pytest.fixture
def sample_html_content():
    """Sample HTML content for docs indexing tests."""
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Test Documentation</title>
        <meta name="description" content="Test documentation for NixOS">
    </head>
    <body>
        <nav>Navigation should be removed</nav>
        <main>
            <h1>Getting Started with NixOS</h1>
            <p>NixOS is a Linux distribution built on top of the Nix package manager.</p>
            <h2>Installation</h2>
            <p>To install NixOS, download the ISO from the official website.</p>
            <h2>Configuration</h2>
            <p>Configuration is done declaratively using the Nix expression language.</p>
        </main>
        <footer>Footer should be removed</footer>
    </body>
    </html>
    """


@pytest.fixture
def sample_cursor_db_data():
    """Sample data mimicking Cursor's database structure."""
    return {
        "bubbles": [
            {
                "key": "bubbleId:conv1:msg1",
                "value": json.dumps({
                    "type": 1,  # User message
                    "createdAt": 1700000000000,
                    "content": "How do I configure NixOS?",
                    "tokenCount": 10,
                }),
            },
            {
                "key": "bubbleId:conv1:msg2",
                "value": json.dumps({
                    "type": 2,  # Assistant message
                    "createdAt": 1700000001000,
                    "modelInfo": {"modelName": "claude-3-sonnet"},
                    "content": "To configure NixOS, edit /etc/nixos/configuration.nix...",
                    "tokenCount": 150,
                    "allThinkingBlocks": [],
                    "toolResults": [],
                }),
            },
        ],
        "composers": {
            "allComposers": [
                {
                    "type": "head",
                    "composerId": "conv1",
                    "name": "NixOS Configuration Help",
                    "createdAt": 1700000000000,
                    "lastUpdatedAt": 1700000001000,
                    "isArchived": False,
                },
            ],
        },
    }

