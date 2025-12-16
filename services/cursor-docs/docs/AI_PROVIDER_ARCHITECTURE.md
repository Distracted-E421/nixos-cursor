# cursor-docs AI Provider Architecture

## Philosophy

> "cursor-docs should be useful without being a problem app"

This means:
- **No forced dependencies** - Works with SQLite + FTS5 alone
- **No background daemons** - Unless user explicitly wants them
- **Hardware-aware** - Detects and uses what's available efficiently
- **Pluggable** - Use Ollama, local models, or cloud APIs
- **Graceful degradation** - Falls back to FTS5 if AI unavailable

## Provider Hierarchy

```
CursorDocs.AI.Provider (behaviour)
├── CursorDocs.AI.Ollama      # Uses existing Ollama installation
├── CursorDocs.AI.Local       # Direct ONNX/llama.cpp (no daemon)
├── CursorDocs.AI.OpenAI      # Cloud API fallback (future)
└── CursorDocs.AI.Disabled    # FTS5-only mode
```

### Detection Priority

1. **User-configured provider** (if set and available)
2. **Ollama** (if running on localhost:11434 or configured port)
3. **Local ONNX** (if models downloaded and runtime available)
4. **Disabled** (graceful fallback to FTS5)

## Hardware Detection

```elixir
# Automatic detection
profile = CursorDocs.AI.Hardware.detect()

# Example output:
%{
  cpu: %{
    cores: 8,
    threads: 16,
    model: "Intel i9-9900KS",
    avx2: true
  },
  ram_mb: 32768,
  gpus: [
    %{vendor: :intel, name: "Arc A770", vram_mb: 16384},
    %{vendor: :nvidia, name: "RTX 2080", vram_mb: 8192}
  ],
  platform: :linux,
  arch: :x86_64
}
```

### Hardware-Aware Recommendations

| Hardware | Recommended Model | Batch Size | Notes |
|----------|-------------------|------------|-------|
| GPU 8GB+ | nomic-embed-text | 32 | Best quality |
| GPU 4GB | all-minilm | 16 | Good balance |
| CPU only + 16GB RAM | bge-small-en-v1.5 | 8 | Local ONNX |
| CPU only + 8GB RAM | all-minilm-l6-v2 | 4 | Tiny model |
| ARM (Pi, etc) | all-minilm-l6-v2 | 2 | CPU optimized |

## Model Registry

Verified models with benchmarks:

| Model | Provider | Dimensions | Quality | Speed | Size |
|-------|----------|------------|---------|-------|------|
| nomic-embed-text | ollama | 768 | 92% | 75% | 274MB |
| all-minilm | ollama | 384 | 82% | 95% | 45MB |
| mxbai-embed-large | ollama | 1024 | 94% | 60% | 670MB |
| all-minilm-l6-v2 | local | 384 | 82% | 95% | 22MB |
| bge-small-en-v1.5 | local | 384 | 86% | 90% | 33MB |

### Custom Models

Users can add custom models:

```elixir
# In config.exs
config :cursor_docs, CursorDocs.AI.Ollama,
  model: "my-custom-embedding-model"
```

## Configuration Examples

### Default (Auto-detect)

```elixir
# No config needed - cursor-docs will:
# 1. Detect hardware
# 2. Find available providers
# 3. Select best model
```

### Explicit Ollama

```elixir
config :cursor_docs, :ai_provider, CursorDocs.AI.Ollama

config :cursor_docs, CursorDocs.AI.Ollama,
  base_url: "http://localhost:11434",
  model: "nomic-embed-text"
```

### Multi-GPU (Like Obsidian)

```elixir
config :cursor_docs, CursorDocs.AI.Ollama,
  instances: [
    %{url: "http://localhost:11434", gpu: "RTX 2080"},
    %{url: "http://localhost:11435", gpu: "Arc A770"}
  ],
  strategy: :round_robin
```

### Local-Only (No Daemon)

```elixir
config :cursor_docs, :ai_provider, CursorDocs.AI.Local

config :cursor_docs, CursorDocs.AI.Local,
  backend: :onnx,
  model: "all-minilm-l6-v2",
  device: :cpu,
  threads: 4
```

### Disabled (FTS5 Only)

```elixir
config :cursor_docs, :ai_provider, CursorDocs.AI.Disabled
```

---

# Database Architecture Decision

## The Question

> Is SurrealDB the best choice? SQLite is fine for smaller datasets, but lots of this will be embeddings for vectors or documents.

## Analysis

### SQLite + FTS5 (Current)

**Pros:**
- Single file, portable
- No daemon process
- Battle-tested, mature
- Works everywhere
- Fast for text search

**Cons:**
- No native vector operations
- Limited to FTS5 for similarity
- Can't do true semantic search without extension

### SQLite + sqlite-vss

**Pros:**
- Still single file
- Adds vector similarity search
- No daemon
- ~100x faster vector search than manual

**Cons:**
- Requires extension compilation
- Less portable (native code)
- Newer, less tested

### SurrealDB

**Pros:**
- Multi-model (docs, graphs, vectors)
- Built-in vector search
- Cross-domain queries
- Single query language

**Cons:**
- Requires daemon process
- More memory overhead
- Less mature than alternatives
- Could be a "problem app"

### LanceDB

**Pros:**
- Embedded (no daemon)
- Rust-based, fast
- Optimized for vectors
- Columnar storage

**Cons:**
- Newer
- Less Elixir support
- Separate from main data

### Qdrant

**Pros:**
- Best vector performance
- Well documented
- Production-ready

**Cons:**
- Separate server process
- Another thing to manage

## Recommendation

**Hybrid approach:**

```
┌─────────────────────────────────────────────┐
│             cursor-docs Storage             │
├─────────────────────────────────────────────┤
│                                             │
│  ┌───────────────┐   ┌───────────────────┐  │
│  │   SQLite      │   │  Vector Store     │  │
│  │   (metadata)  │   │  (embeddings)     │  │
│  │               │   │                   │  │
│  │ • Sources     │   │ • sqlite-vss      │  │
│  │ • Chunks      │   │   (default)       │  │
│  │ • FTS5 index  │   │                   │  │
│  │ • Jobs        │   │ • LanceDB         │  │
│  │ • Alerts      │   │   (optional)      │  │
│  └───────────────┘   │                   │  │
│         │            │ • Qdrant          │  │
│         │            │   (power users)   │  │
│         └────────────┴───────────────────┘  │
│                                             │
└─────────────────────────────────────────────┘
```

### Tier 1: sqlite-vss (Default)

- Ships with cursor-docs
- Single file, no daemon
- Good enough for most use cases
- ~50k vectors = ~100MB

### Tier 2: LanceDB (Optional)

- For users with larger datasets
- Still embedded, no daemon
- Better performance at scale
- ~500k+ vectors

### Tier 3: Qdrant (Power Users)

- For production deployments
- Best performance
- Requires separate server
- Multi-tenant support

## Implementation Plan

### Phase 1: FTS5 Only (Current)

- SQLite with FTS5
- Keyword search
- Works without any AI

### Phase 2: sqlite-vss Integration

```elixir
defmodule CursorDocs.Storage.Vector do
  @behaviour CursorDocs.Storage.VectorBehaviour

  # sqlite-vss implementation
  def store_embedding(chunk_id, embedding) do
    # INSERT INTO embeddings VALUES (?, ?)
  end

  def search_similar(embedding, limit) do
    # SELECT * FROM embeddings WHERE vss_search(...)
  end
end
```

### Phase 3: Pluggable Backends

```elixir
# config.exs
config :cursor_docs, :vector_store, CursorDocs.Storage.Vector.SqliteVss
# or
config :cursor_docs, :vector_store, CursorDocs.Storage.Vector.LanceDB
# or
config :cursor_docs, :vector_store, CursorDocs.Storage.Vector.Qdrant
```

---

## "Don't Be a Problem App" Checklist

- [ ] **No forced daemons** - Works without Ollama, Qdrant, etc.
- [ ] **No startup delay** - Lazy load AI models
- [ ] **No background CPU** - Only process when asked
- [ ] **No memory bloat** - Unload models when idle
- [ ] **No disk space surprise** - Clear model sizes upfront
- [ ] **Graceful degradation** - FTS5 fallback always works
- [ ] **Explicit opt-in** - User chooses AI features
- [ ] **Easy disable** - Single config to turn off AI
- [ ] **Resource limits** - Configurable batch sizes
- [ ] **Hardware detection** - Adapt to available resources

---

## API Summary

```elixir
# Check what's available
CursorDocs.AI.Provider.status()

# Get hardware profile
CursorDocs.AI.Hardware.summary()

# Get recommended model
CursorDocs.AI.ModelRegistry.recommended()

# Generate embedding
CursorDocs.AI.Provider.embed("search query")

# Search with vectors (future)
CursorDocs.search("query", mode: :semantic)
# vs
CursorDocs.search("query", mode: :keyword)  # FTS5
```

---

## File Structure

```
lib/cursor_docs/ai/
├── provider.ex        # Behaviour + detection
├── hardware.ex        # Hardware detection
├── model_registry.ex  # Verified models
├── ollama.ex          # Ollama provider
├── local.ex           # ONNX/llama.cpp provider
├── disabled.ex        # FTS5-only fallback
└── openai.ex          # Cloud API (future)

lib/cursor_docs/storage/
├── sqlite.ex          # SQLite + FTS5
├── vector/
│   ├── behaviour.ex   # Vector store behaviour
│   ├── sqlite_vss.ex  # sqlite-vss implementation
│   ├── lance_db.ex    # LanceDB implementation
│   └── qdrant.ex      # Qdrant implementation
```

