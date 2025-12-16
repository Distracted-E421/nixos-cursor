# Changelog

All notable changes to cursor-docs will be documented in this file.

## [0.3.0-pre] - 2025-12-16 (Pre-release)

### Added

#### 🧠 Pluggable AI Provider Architecture

A complete rethink of how cursor-docs handles embeddings and AI, designed to be **useful without being a problem app**.

**New AI Modules:**

- `CursorDocs.AI.Provider` - Behaviour for embedding providers with auto-detection
- `CursorDocs.AI.Hardware` - Hardware detection (CPU, GPU, RAM, VRAM)
- `CursorDocs.AI.ModelRegistry` - Verified models with benchmarks
- `CursorDocs.AI.Ollama` - Uses existing Ollama installation
- `CursorDocs.AI.Local` - Direct ONNX inference (no daemon)
- `CursorDocs.AI.Disabled` - FTS5-only fallback (always works)

#### 📦 Tiered Vector Storage Architecture

Full implementation of the tiered storage system for users from zero-setup to power users.

**Storage Tiers:**

| Tier | Backend | Features | Use Case |
|------|---------|----------|----------|
| 1 | Disabled | FTS5 only | Zero setup, just works |
| 2 | sqlite-vss | Embedded vectors | Semantic search, no daemon |
| 3 | SurrealDB | Vectors + graphs | Power users, full pipeline |

**New Storage Modules:**

- `CursorDocs.Storage.Vector` - Vector storage behaviour and detection
- `CursorDocs.Storage.Vector.Disabled` - FTS5-only fallback
- `CursorDocs.Storage.Vector.SQLiteVss` - Embedded vector search
- `CursorDocs.Storage.Vector.SurrealDB` - Full-featured server backend
- `CursorDocs.Embeddings.Generator` - AI embedding orchestration
- `CursorDocs.Search` - Unified search (keyword/semantic/hybrid)

**Key Features:**

- **Hardware Detection**: Detects NVIDIA/AMD/Intel GPUs, CPU capabilities
- **Graceful SurrealDB startup** - Lazy connect, low priority systemd service
- **Auto-detection** - Automatically selects best available backend
- **Hybrid search** - Combines semantic + keyword for best results
- **Hardware-aware batching** - Adjusts batch size based on system resources
- **Graceful degradation** - Falls back to simpler backends automatically

### Changed

- Updated Application supervisor to conditionally start AI/vector services
- Search module now supports multiple modes: `:keyword`, `:semantic`, `:hybrid`

---

## [0.2.0] - 2025-12-16

A complete rethink of how cursor-docs handles embeddings and AI, designed to be **useful without being a problem app**.

**New Modules:**

- `CursorDocs.AI.Provider` - Behaviour for embedding providers with auto-detection
- `CursorDocs.AI.Hardware` - Hardware detection (CPU, GPU, RAM, VRAM)
- `CursorDocs.AI.ModelRegistry` - Verified models with benchmarks
- `CursorDocs.AI.Ollama` - Uses existing Ollama installation
- `CursorDocs.AI.Local` - Direct ONNX inference (no daemon)
- `CursorDocs.AI.Disabled` - FTS5-only fallback (always works)

**Hardware Detection Features:**

- Detects NVIDIA GPUs via `nvidia-smi`
- Detects Intel Arc GPUs via `lspci`
- Detects AMD GPUs via `rocm-smi`
- Detects CPU capabilities (AVX, AVX2, AVX512)
- Recommends appropriate models and batch sizes
- Determines if background embeddings are safe

**Provider Priority:**

1. Ollama (if running)
2. Local ONNX (if models downloaded)
3. Disabled (graceful fallback to FTS5)

**Model Registry:**

| Model | Provider | Dims | Quality | Speed | Tier |
|-------|----------|------|---------|-------|------|
| nomic-embed-text | ollama | 768 | 92% | 75% | recommended |
| all-minilm | ollama | 384 | 82% | 95% | fast |
| mxbai-embed-large | ollama | 1024 | 94% | 60% | quality |
| all-minilm-l6-v2 | local | 384 | 82% | 95% | fast |

### Design Philosophy

> "cursor-docs should be useful without being a problem app"

- **No forced dependencies** - Works with SQLite + FTS5 alone
- **No background daemons** - Unless user explicitly wants them
- **Hardware-aware** - Detects and uses what's available
- **Pluggable** - Use Ollama, local models, or cloud APIs
- **Graceful degradation** - Falls back to FTS5 if AI unavailable

### Documentation

- New [AI_PROVIDER_ARCHITECTURE.md](docs/AI_PROVIDER_ARCHITECTURE.md)
- Updated README with AI provider section
- Database recommendation (sqlite-vss vs SurrealDB)

## [0.2.0] - 2025-12-16

### Added

- **Security Quarantine Pipeline** - All scraped content goes through security validation
- **Duplicate Prevention** - FTS5 index properly clears old entries on re-scrape
- Content is now filtered by security tier (clean, flagged, quarantined, blocked)

### Fixed

- Duplicate search results caused by FTS5 accumulation
- Security pipeline integration in scraper workflow

## [0.1.0] - 2025-12-15

### Added

- Initial release
- SQLite storage with FTS5 full-text search
- Cursor database sync
- Rate-limited web scraping
- Content extraction and chunking
- Basic security validation
- CLI commands: add, search, list, status, sync

