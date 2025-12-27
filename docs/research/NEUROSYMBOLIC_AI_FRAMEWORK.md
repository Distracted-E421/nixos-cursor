# Neuro-Symbolic AI Framework Research

**Created**: 2025-12-27
**Status**: Research & Planning Phase
**Hardware**: Obsidian (RTX 2080 8GB + Arc A770 16GB)

## Executive Summary

This document outlines research into building a **neuro-symbolic AI framework** that combines:

- Large Language Models (LLMs) for natural language understanding
- Small Language Models (SLMs) for specialized reasoning tasks
- Symbolic reasoning systems for formal logic and knowledge grounding
- Co-routine architectures for stateful, interruptible AI workflows

The goal is to create a framework that leverages **local hardware** (Obsidian's dual GPUs) to achieve capabilities beyond what pure neural or pure symbolic systems can deliver alone.

---

## 1. Problem Statement: Why Neuro-Symbolic?

### Limitations of Pure Neural (LLM) Systems

| Problem | Description |
|---------|-------------|
| **Hallucination** | LLMs confidently generate false information |
| **Opaque Reasoning** | No explainability - "black box" decisions |
| **Knowledge Cutoff** | Training data has a fixed date |
| **Logical Consistency** | Cannot guarantee logical validity |
| **Symbol Grounding** | Symbols lack connection to real-world referents |

### Limitations of Pure Symbolic Systems

| Problem | Description |
|---------|-------------|
| **Brittleness** | Require hand-crafted rules for every case |
| **Knowledge Acquisition** | Extremely expensive to build knowledge bases |
| **Natural Language** | Cannot handle ambiguity in human language |
| **Learning** | Cannot learn from experience without explicit programming |

### The Neuro-Symbolic Promise

> **"Combine neural learning with symbolic reasoning to get the best of both worlds"**

- Neural systems **learn** from data, handle ambiguity
- Symbolic systems **reason** formally, provide guarantees
- Together: learning + reasoning + explainability

---

## 2. Key Concepts

### 2.1 Symbol Grounding

**The Symbol Grounding Problem**: How do abstract symbols acquire meaning?

In traditional AI, symbols (like `DOG`, `CAT`, `LOVES`) are arbitrary tokens without inherent meaning. **Symbol grounding** connects symbols to:

- Real-world entities (percepts, actions)
- Embeddings in neural vector spaces
- Other symbols via relational structure

**Solutions Being Explored**:

1. **Embedding-Based Grounding**: Symbols map to regions in embedding space

   ```
   SYMBOL("dog") → embedding_space_region([0.23, -0.45, 0.12, ...])
   ```

2. **Multi-Modal Grounding**: Symbols connect to images, audio, sensor data

   ```
   SYMBOL("red") → visual_classifier(image) → True/False
   ```

3. **Knowledge Graph Grounding**: Symbols defined by relationships

   ```
   dog → is_a → mammal
   dog → has_property → four_legs
   dog → sounds_like → bark
   ```

### 2.2 Co-Routines for AI

**Co-routines** are program structures that can:

- **Suspend** execution at any point
- **Resume** from the suspended state later
- **Yield** intermediate results
- Maintain **state** across invocations

**Why Co-Routines for AI?**

Traditional LLM calls are **stateless**: input → output, then forget everything. Co-routines enable:

```
┌─────────────────────────────────────────────────────────────────┐
│                     AI Reasoning Co-Routine                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   user_query ──► YIELD(initial_thoughts)                        │
│                        │                                         │
│                  [wait for user feedback / tool results]         │
│                        │                                         │
│   feedback ──────► YIELD(refined_plan)                          │
│                        │                                         │
│                  [execute tools, gather evidence]                │
│                        │                                         │
│   evidence ──────► YIELD(conclusions)                           │
│                        │                                         │
│                  [validate with symbolic reasoner]               │
│                        │                                         │
│   validation ────► RETURN(final_answer + proof)                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Benefits**:

- **Interruptible reasoning**: Stop, inspect, modify, continue
- **State persistence**: Remember context across steps
- **Tool integration**: Call external systems mid-reasoning
- **Human-in-the-loop**: Get feedback at decision points
- **Backtracking**: Return to previous states if reasoning fails

### 2.3 Logical Neural Networks (LNN)

**IBM's LNN** is a key architecture where:

- Every **neuron has a logical meaning** (AND, OR, IMPLIES, etc.)
- Inference is **omnidirectional** (can reason forward or backward)
- Learning minimizes **logical contradiction**
- Maintains **bounds on truth values** (uncertainty)

```python
# Example LNN structure
from lnn import Model, Predicate, Variable, And, Implies

# Define predicates
Person = Predicate("Person")
Mortal = Predicate("Mortal")
x = Variable("x")

# Encode knowledge
model = Model()
model.add_knowledge(
    Implies(Person(x), Mortal(x))  # All persons are mortal
)
model.add_data(Person("Socrates"))  # Socrates is a person

# Reason in any direction
model.infer()  # Concludes: Mortal("Socrates") with bounds
```

**Key Properties**:

- **Interpretable**: Every weight maps to logical confidence
- **Differentiable**: Can train end-to-end
- **Uncertainty-aware**: Bounds propagate through network
- **Open-world**: Handles incomplete knowledge

---

## 3. Architecture Proposal

### 3.1 System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    NEURO-SYMBOLIC REASONING FRAMEWORK                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐               │
│  │   Natural    │    │   Symbolic   │    │  Knowledge   │               │
│  │   Language   │◄──►│   Reasoner   │◄──►│    Graph     │               │
│  │   Interface  │    │   (LNN/ASP)  │    │   (Grounding)│               │
│  └──────────────┘    └──────────────┘    └──────────────┘               │
│         │                   │                    │                       │
│         ▼                   ▼                    ▼                       │
│  ┌───────────────────────────────────────────────────────────┐          │
│  │                   CO-ROUTINE ORCHESTRATOR                  │          │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────────────┐  │          │
│  │  │ Parse   │→│ Ground  │→│ Reason  │→│ Verify/Explain  │  │          │
│  │  │ (LLM)   │ │ (SLM)   │ │ (LNN)   │ │ (LLM + Logic)   │  │          │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────────────┘  │          │
│  │       ▲           │           │               │           │          │
│  │       └───────────┴───────────┴───────────────┘           │          │
│  │                    YIELD / RESUME                          │          │
│  └───────────────────────────────────────────────────────────┘          │
│                              │                                           │
│         ┌────────────────────┼────────────────────┐                     │
│         ▼                    ▼                    ▼                     │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐               │
│  │  RTX 2080    │    │  Arc A770    │    │   Vector     │               │
│  │  (7B models) │    │  (14B models)│    │   Store      │               │
│  │  Port 11434  │    │  Port 11435  │    │  (Embeddings)│               │
│  └──────────────┘    └──────────────┘    └──────────────┘               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Component Responsibilities

#### 3.2.1 Natural Language Interface

- **Model**: `qwen2.5:7b` or `qwen2.5-coder:7b` (RTX 2080)
- **Tasks**:
  - Parse user queries into structured intents
  - Generate natural language explanations
  - Handle ambiguity and clarification

#### 3.2.2 Symbol Grounder (SLM)

- **Model**: Small specialized model (3B params or custom-trained)
- **Tasks**:
  - Map natural language to knowledge graph entities
  - Resolve coreferences and entity mentions
  - Extract predicates and relations

#### 3.2.3 Symbolic Reasoner

- **Engine**: IBM LNN or Answer Set Programming (Clingo)
- **Tasks**:
  - Perform logical inference
  - Check consistency
  - Generate explanations/proofs

#### 3.2.4 Knowledge Graph

- **Storage**: SurrealDB (graph + vector hybrid)
- **Tasks**:
  - Store grounded symbols
  - Maintain relationships
  - Provide context for reasoning

#### 3.2.5 Co-Routine Orchestrator

- **Implementation**: Elixir GenServer or Python async
- **Tasks**:
  - Manage reasoning workflow
  - Handle interrupts/resumes
  - Coordinate components

### 3.3 Data Flow Example

**Query**: "Is Socrates mortal? Explain your reasoning."

```
1. [NL Interface] Parse query
   YIELD: {intent: "query", predicate: "mortal", entity: "Socrates", explain: true}

2. [Symbol Grounder] Ground entities
   YIELD: {entity_id: "person:socrates", grounded: true, confidence: 0.98}

3. [Knowledge Graph] Retrieve context
   YIELD: {
     facts: ["person:socrates rdf:type Person"],
     rules: ["Person(x) → Mortal(x)"]
   }

4. [Symbolic Reasoner] Perform inference
   YIELD: {
     conclusion: "Mortal(person:socrates)",
     truth_bounds: [0.95, 1.0],
     proof: ["Person(socrates) ∧ (Person(x) → Mortal(x)) ⊢ Mortal(socrates)"]
   }

5. [NL Interface] Generate explanation
   RETURN: "Yes, Socrates is mortal. Here's the reasoning:
            1. We know Socrates is a person (given fact)
            2. We have the rule: All persons are mortal
            3. By modus ponens, Socrates is mortal
            Confidence: 95-100%"
```

---

## 4. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)

**Goal**: Basic co-routine architecture with LLM integration

- [ ] Create Elixir GenServer for co-routine orchestration
- [ ] Integrate Ollama models (qwen2.5:7b, qwen2.5-coder:7b)
- [ ] Build simple YIELD/RESUME protocol
- [ ] Test stateful reasoning chains

**Deliverable**: Working co-routine demo with LLM

### Phase 2: Symbol Grounding (Weeks 3-4)

**Goal**: Connect LLM output to structured symbols

- [ ] Design symbol schema (predicates, entities, relations)
- [ ] Build entity extraction module (using SLM)
- [ ] Implement embedding-based grounding
- [ ] Create knowledge graph in SurrealDB

**Deliverable**: NL → Symbols pipeline

### Phase 3: Logical Reasoning (Weeks 5-6)

**Goal**: Add symbolic reasoning engine

- [ ] Evaluate IBM LNN vs Clingo (ASP)
- [ ] Implement chosen reasoner integration
- [ ] Build proof generation module
- [ ] Connect to co-routine orchestrator

**Deliverable**: Full reasoning pipeline with proofs

### Phase 4: Training Custom Models (Weeks 7-8)

**Goal**: Train specialized SLMs on local hardware

- [ ] Create training data for symbol grounding
- [ ] Fine-tune small model (Phi-3 or Qwen-2.5:3B)
- [ ] Evaluate on grounding benchmarks
- [ ] Integrate custom model into pipeline

**Deliverable**: Custom-trained grounding model

### Phase 5: Integration & Testing (Weeks 9-10)

**Goal**: End-to-end system with evaluation

- [ ] Create test suite with reasoning problems
- [ ] Benchmark against pure LLM baseline
- [ ] Document limitations and failure modes
- [ ] Optimize latency and throughput

**Deliverable**: Production-ready framework

---

## 5. Key Research References

### Papers

1. **Logical Neural Networks** (Riegel et al., 2020)
   - arXiv:2006.13155
   - Core LNN architecture

2. **DSPy: Compiling Declarative LM Calls** (Khattab et al., 2023)
   - arXiv:2310.03714
   - Programming (not prompting) LLMs

3. **NS3D: Neuro-Symbolic Grounding of 3D Objects** (2023)
   - arXiv:2303.13483
   - Symbol grounding in 3D scenes

4. **GENOME: Generative Neuro-Symbolic Visual Reasoning** (2023)
   - arXiv:2311.04901
   - Module growth and reuse

5. **Neurosymbolic AI as Antithesis to Scaling Laws** (2024)
   - Efficient neuro-symbolic integration

### Repositories

| Repo | Description | Stars |
|------|-------------|-------|
| [IBM/LNN](https://github.com/IBM/LNN) | Logical Neural Networks | 600+ |
| [stanfordnlp/dspy](https://github.com/stanfordnlp/dspy) | Programming LLMs | 23k+ |
| [ruslanmv/Neuro-symbolic-interaction](https://github.com/ruslanmv/Neuro-symbolic-interaction) | LLM + OWL ontology | - |
| [LAMDASZ-ML/Awesome-LLM-Reasoning-with-NeSy](https://github.com/LAMDASZ-ML/Awesome-LLM-Reasoning-with-NeSy) | Curated resources | - |

### Tools

| Tool | Purpose |
|------|---------|
| **Ollama** | Local LLM inference |
| **DSPy** | LLM programming framework |
| **IBM LNN** | Neuro-symbolic reasoning |
| **Clingo** | Answer Set Programming |
| **SurrealDB** | Graph + Vector database |
| **AllegroGraph** | Knowledge graph platform |

---

## 6. Hardware Utilization Plan

### Obsidian GPU Allocation

| GPU | VRAM | Port | Models | Role | Status |
|-----|------|------|--------|------|--------|
| **RTX 2080** | 8GB | 11434 | qwen2.5:7b, qwen2.5-coder:7b | NL interface, code generation | ✅ Working |
| **Arc A770** | 16GB | 11435 | ⚠️ See issues below | Large reasoning, grounding | ⚠️ Vulkan Issues |

### ⚠️ CRITICAL: Arc A770 Vulkan Backend Issues (2025-12-27)

**Problem Discovered**: The Arc A770 with Ollama's Vulkan backend produces **gibberish output** for inference.

**Symptoms**:

- Models download and load successfully
- `ollama list` shows models correctly
- Running inference produces repetitive, nonsensical text:

  ```
  "D is not is the most of the most of the most of the least of the most..."
  ```

**Tested Models**:

- `qwen2.5:7b` - ❌ Gibberish output
- `qwen2.5:14b` - ❌ Gibberish output

**Root Cause**: Vulkan compute shader compatibility issues with Intel Arc GPUs in Ollama.

**Potential Solutions**:

1. **Use llama.cpp with SYCL/Level Zero** (Recommended for Arc)

   ```bash
   # Intel's oneAPI SYCL backend has better Arc support
   git clone https://github.com/ggerganov/llama.cpp
   cd llama.cpp
   cmake -B build -DGGML_SYCL=ON -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx
   cmake --build build --config Release
   ```

2. **Use IPEX-LLM** (Intel's optimized LLM runtime)

   ```bash
   pip install --pre --upgrade ipex-llm[xpu] --extra-index-url https://pytorch-extension.intel.com/release-whl/stable/xpu/us/
   ```

3. **CPU Offload** for Arc A770 workloads until Vulkan fixed

   ```bash
   OLLAMA_HOST=http://localhost:11435 OLLAMA_NUM_GPU=0 ollama run qwen2.5:14b
   ```

4. **Wait for Ollama Vulkan fixes** - Track: <https://github.com/ollama/ollama/issues>

**Current Workaround**: Use RTX 2080 (port 11434) for all inference until Arc issues resolved.

### Model Loading Strategy

```python
# Pseudo-code for model management
class ModelManager:
    def load_for_task(self, task):
        if task == "nl_interface":
            return OllamaClient(port=11434, model="qwen2.5:7b")
        elif task == "grounding":
            return OllamaClient(port=11435, model="qwen2.5:14b")
        elif task == "coding":
            return OllamaClient(port=11434, model="qwen2.5-coder:7b")
        elif task == "embeddings":
            return OllamaClient(port=11435, model="nomic-embed-text")
```

### Training on Local Hardware

For fine-tuning small models (3-7B):

- **RTX 2080**: LoRA fine-tuning of 3B models
- **Arc A770**: LoRA fine-tuning of 7B models (SYCL backend)
- **CPU (32GB RAM)**: Data preprocessing, evaluation

### Distributed Inference with llama.cpp

For larger models and batch workloads, we can distribute inference across multiple machines using llama.cpp's RPC backend.

**Network Constraint**: ~1 Gbps connection between devices (Tailscale mesh)

**Architecture**:

```
┌─────────────────────────────────────────────────────────────────────┐
│                 DISTRIBUTED INFERENCE CLUSTER                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Obsidian (Master)                 Framework (Worker)               │
│   ┌───────────────────┐            ┌───────────────────┐            │
│   │  RTX 2080 (8GB)   │◄──RPC──────│  CPU (16 threads) │            │
│   │  Arc A770 (SYCL)  │            │  32GB RAM         │            │
│   │  llama.cpp master │            │  llama.cpp worker │            │
│   └───────────────────┘            └───────────────────┘            │
│            │                                │                        │
│            │                                │                        │
│            ▼                                ▼                        │
│   ┌─────────────────────────────────────────────────────┐           │
│   │          TENSOR PARALLELISM (split layers)          │           │
│   │   Layers 0-20: Obsidian GPUs                        │           │
│   │   Layers 21-40: Framework CPU                       │           │
│   └─────────────────────────────────────────────────────┘           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**llama.cpp RPC Setup**:

```bash
# On Framework (worker node)
./llama-rpc-server --host 0.0.0.0 --port 50052

# On Obsidian (master node)
./llama-cli -m model.gguf \
  --rpc framework:50052 \
  -ngl 99 \
  --tensor-split 0.6,0.4
```

**Use Cases for Distributed Inference**:

| Use Case | Models | Latency Tolerance | Priority |
|----------|--------|-------------------|----------|
| Batch document embedding | Large embedders | High (seconds) | Low |
| Knowledge graph construction | 70B+ models | Very high (minutes) | Background |
| Model fine-tuning data prep | Instruction tuning | Offline | Scheduled |
| Overnight reasoning tasks | Complex chains | Hours | Cron job |

**Bandwidth Considerations** (1 Gbps = ~125 MB/s):

- Token generation: ~100 bytes/token → ~1M tokens/sec max
- Tensor transfer: ~100MB per layer → ~1 sec/layer sync
- Acceptable for batch, not real-time interactive

---

## 6.5 Elixir LNN Port (cursor-docs Integration)

An Elixir port of IBM's Logical Neural Networks has been implemented at:
`services/cursor-docs/lib/cursor_docs/ai/lnn/`

### Module Structure

```
lib/cursor_docs/ai/lnn/
├── model.ex        # Main LNN container (GenServer)
├── formula.ex      # Base module + Fact type
├── connectives.ex  # And, Or, Not, Implies, Iff, Predicate, Proposition
├── graph.ex        # DAG for formula dependencies
└── python.ex       # Optional Python interop for training
```

### Key Features

| Feature | Status | Notes |
|---------|--------|-------|
| Propositional logic | ✅ | And, Or, Not, Implies, Iff |
| First-order predicates | ✅ | With groundings |
| Upward inference | ✅ | Leaf to root |
| Downward inference | ✅ | Root to leaf |
| Belief bounds | ✅ | [L, U] ∈ [0,1]² |
| Lukasiewicz semantics | ✅ | Differentiable t-norms |
| Training (gradient descent) | 🔄 | Via Python interop |
| Nx tensor integration | 📋 | Planned |

### Usage Example

```elixir
alias CursorDocs.AI.LNN
alias CursorDocs.AI.LNN.Connectives.{Proposition, Implies}
alias CursorDocs.AI.LNN.Formula.Fact

# Create model
{:ok, model} = LNN.new_model("Weather")

# Define knowledge
raining = Proposition.new("Raining")
wet = Proposition.new("Wet")
rule = Implies.new(raining, wet)

# Add to model
{:ok, model} = LNN.Model.add_knowledge(model, rule)
{:ok, model} = LNN.Model.add_data(model, raining, Fact.true_val())

# Infer
{:ok, model, stats} = LNN.Model.infer(model)
# => Wet bounds = {1.0, 1.0} (TRUE via modus ponens)
```

### Integration with Neuro-Symbolic Pipeline

The LNN module integrates with the neuro-symbolic orchestrator:

```
Query → Parser (LLM) → Grounder (Embedding) → LNN Reasoner → Explainer
                                                    ↑
                                              Elixir LNN Port
```

### Design Decision: Why Elixir, Not Python?

| Aspect | Elixir | Python |
|--------|--------|--------|
| **OTP supervision** | ✅ Fault-tolerant | ❌ Manual |
| **Concurrency** | ✅ BEAM VM | ❌ GIL limits |
| **Integration** | ✅ cursor-docs native | 🔄 Subprocess |
| **Training** | 🔄 Via Python port | ✅ PyTorch native |
| **Hot reloading** | ✅ Built-in | ❌ Restart required |

**Conclusion**: Elixir for inference (real-time, fault-tolerant), Python for training (PyTorch).

---

## 7. Open Questions

1. **Which symbolic reasoner?**
   - IBM LNN: ✅ **Selected** - Elixir port implemented
   - Clingo (ASP): Mature, well-documented, but not differentiable
   - Custom: Build lightweight reasoner for specific use case?

2. **Grounding granularity?**
   - Entity-level: Ground "Socrates" → entity_123
   - Predicate-level: Ground "is mortal" → predicate_456
   - Full semantic: Ground entire sentences to logical forms

3. **Co-routine implementation?**
   - Elixir: Built for concurrency, OTP supervision
   - Python asyncio: More ML library support
   - Rust: Performance, but steep learning curve

4. **Training data for grounding?**
   - Use existing NLU datasets?
   - Synthetic generation from knowledge graphs?
   - Domain-specific annotation?

5. **Evaluation metrics?**
   - Reasoning accuracy vs pure LLM
   - Explainability quality
   - Latency/throughput
   - Robustness to adversarial inputs

---

## 8. Next Steps

1. **Download and test IBM LNN** on Obsidian
2. **Experiment with DSPy** for structured LLM programming
3. **Pull additional Ollama models** (qwen2.5-coder:7b done, try deepseek-coder:6.7b)
4. **Create proof-of-concept** co-routine in Elixir
5. **Define initial symbol schema** for cursor-docs use case

---

## Appendix A: Model VRAM Requirements

| Model | Params | Quantization | VRAM Required |
|-------|--------|--------------|---------------|
| qwen2.5:3b | 3.1B | Q4_K_M | ~2GB |
| qwen2.5:7b | 7.6B | Q4_K_M | ~5GB |
| qwen2.5-coder:7b | 7B | Q4_K_M | ~5GB |
| qwen2.5:14b | 14B | Q4_K_M | ~9GB |
| deepseek-coder:6.7b | 6.7B | Q4_K_M | ~4.5GB |
| nomic-embed-text | 137M | FP16 | ~0.5GB |

## Appendix B: Co-Routine State Machine

```
         ┌───────────────────────────────────────────┐
         │                                           │
         ▼                                           │
    ┌─────────┐     query      ┌─────────────┐      │
    │  IDLE   │───────────────►│   PARSING   │      │
    └─────────┘                └─────────────┘      │
         ▲                           │              │
         │                      yield│              │
         │                           ▼              │
    ┌─────────┐                ┌─────────────┐      │
    │ FAILED  │◄───error───────│  GROUNDING  │      │
    └─────────┘                └─────────────┘      │
         │                           │              │
         │                      yield│              │
         │                           ▼              │
         │                     ┌─────────────┐      │
         └─────error───────────│  REASONING  │      │
                               └─────────────┘      │
                                     │              │
                                yield│              │
                                     ▼              │
                               ┌─────────────┐      │
                               │ EXPLAINING  │──────┘
                               └─────────────┘   return
                                     │
                                     ▼
                               ┌─────────────┐
                               │  COMPLETE   │
                               └─────────────┘
```

## Appendix C: Integration with cursor-docs

The neuro-symbolic framework will extend cursor-docs:

```elixir
# lib/cursor_docs/ai/neurosymbolic.ex
defmodule CursorDocs.AI.Neurosymbolic do
  @moduledoc """
  Neuro-symbolic reasoning for enhanced documentation search.
  """
  
  use GenServer
  
  # Co-routine states
  @states [:idle, :parsing, :grounding, :reasoning, :explaining, :complete, :failed]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Begin a reasoning chain for a query.
  Returns a session_id for tracking.
  """
  def reason(query) do
    GenServer.call(__MODULE__, {:reason, query})
  end
  
  @doc """
  Get current state of a reasoning session.
  """
  def state(session_id) do
    GenServer.call(__MODULE__, {:state, session_id})
  end
  
  @doc """
  Resume a suspended reasoning session with new input.
  """
  def resume(session_id, input) do
    GenServer.call(__MODULE__, {:resume, session_id, input})
  end
end
```

---

## 9. IBM Logical Neural Networks (LNN) Deep Dive

### 9.1 Core Architecture

IBM's LNN is a **neural network where every neuron has a logical meaning**. Unlike traditional neural networks where activations are opaque, LNN neurons correspond to:

- **Propositions**: `P`, `Q` (Boolean facts)
- **Predicates**: `Person(x)`, `Mortal(x)` (relations over entities)
- **Connectives**: `AND`, `OR`, `NOT`, `IMPLIES`, `IFF`
- **Quantifiers**: `FORALL`, `EXISTS`

**Key Structure**:

```
                    LNN Model
                       │
    ┌──────────────────┼──────────────────┐
    │                  │                  │
    ▼                  ▼                  ▼
┌─────────┐      ┌─────────┐      ┌─────────┐
│Predicate│      │Predicate│      │  Rule   │
│ Person  │      │ Mortal  │      │Implies  │
└────┬────┘      └────┬────┘      └────┬────┘
     │                │                │
     └────────────────┴────────────────┘
                      │
              ┌───────┴───────┐
              │  Inference    │
              │  (Forward &   │
              │   Backward)   │
              └───────────────┘
```

### 9.2 Omnidirectional Inference

Traditional neural nets are **feedforward only**. LNN supports:

1. **Forward Inference (Modus Ponens)**:
   - Given: `Person(Socrates)` and `Person(x) → Mortal(x)`
   - Conclude: `Mortal(Socrates)`

2. **Backward Inference (Abduction)**:
   - Given: `Mortal(Socrates)` and `Person(x) → Mortal(x)`
   - Hypothesize: `Person(Socrates)` might be true

3. **Contrapositive Inference**:
   - Given: `¬Mortal(Entity)` and `Person(x) → Mortal(x)`
   - Conclude: `¬Person(Entity)`

### 9.3 Truth Value Bounds

LNN represents truth with **bounds** [lower, upper]:

- `[1.0, 1.0]` = TRUE (certain)
- `[0.0, 0.0]` = FALSE (certain)
- `[0.0, 1.0]` = UNKNOWN
- `[0.3, 0.8]` = Uncertain (30-80% likely true)

**Propagation Example**:

```
Person(Socrates) = [1.0, 1.0]  (TRUE)
Person(x) → Mortal(x) = [0.95, 1.0]  (High confidence rule)

After inference:
Mortal(Socrates) = [0.95, 1.0]  (Bounds propagate)
```

### 9.4 LNN API Structure (Python)

```python
from lnn import (
    Model, Predicate, Variable, Implies, And, Or, Not,
    Fact, World, Direction
)

# Create model
model = Model()

# Define predicates
Person = Predicate("Person")
Mortal = Predicate("Mortal")
Greek = Predicate("Greek")

# Define variable
x = Variable("x")

# Add rules
model.add_knowledge(
    Implies(Person(x), Mortal(x)),  # All persons are mortal
    Implies(Greek(x), Person(x))    # All Greeks are persons
)

# Add facts
model.add_data({
    Person: {
        "Socrates": Fact.TRUE,
        "Plato": Fact.TRUE
    },
    Greek: {
        "Socrates": Fact.TRUE
    }
})

# Run inference
model.infer()

# Query results
print(model[Mortal]["Socrates"])  # [1.0, 1.0] - TRUE
print(model[Mortal]["Plato"])     # [1.0, 1.0] - TRUE
```

### 9.5 When to Use LNN vs Other Approaches

| Approach | Best For | Limitations |
|----------|----------|-------------|
| **IBM LNN** | Formal reasoning with uncertainty, explainability | Complex setup, Python-only |
| **ASP (Clingo)** | Combinatorial problems, answer sets | No uncertainty, not differentiable |
| **Prolog** | Rule-based systems, backtracking | No learning, limited scalability |
| **Custom Rules** | Simple domain-specific logic | Manual maintenance, no learning |

### 9.6 LNN Integration Strategy for cursor-docs

**Recommended Approach**: Use LNN for **reasoning validation**, not primary inference.

```
┌─────────────────────────────────────────────────────────────┐
│                     cursor-docs Pipeline                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Query ──► [LLM Parse] ──► [LLM Reason] ──► [LNN Verify]   │
│                                      │              │        │
│                                      │              ▼        │
│                                      │       ┌───────────┐  │
│                                      │       │ Consistent?│  │
│                                      │       └─────┬─────┘  │
│                                      │           Yes│No     │
│                                      │              │       │
│                                      ▼              ▼       │
│                               [Final Answer]  [Retry/Flag] │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Benefits**:

- LLM handles natural language complexity
- LNN provides logical guarantees
- Errors caught before user sees them

---

## 10. Distributed Inference with llama.cpp

### 10.1 llama.cpp RPC (Remote Procedure Call)

llama.cpp supports **distributed inference** via its RPC backend, allowing you to:

- Split model layers across multiple machines
- Use remote GPU/CPU resources for inference
- Build a **compute cluster** for large models

**Architecture**:

```
                    ┌────────────────┐
                    │   Main Host    │
                    │  (Obsidian)    │
                    │  llama-server  │
                    └───────┬────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│  RPC Worker 1 │   │  RPC Worker 2 │   │  RPC Worker 3 │
│ (neon-laptop) │   │  (framework)  │   │  (pi-server)  │
│   CPU Only    │   │   CPU Only    │   │   ARM64 CPU   │
│   16 layers   │   │   16 layers   │   │   8 layers    │
└───────────────┘   └───────────────┘   └───────────────┘
```

### 10.2 llama.cpp RPC Setup

**On Worker Machines** (e.g., neon-laptop, framework):

```bash
# Install llama.cpp
nix shell nixpkgs#llama-cpp

# Start RPC server
./llama-rpc-server --host 0.0.0.0 --port 50052

# Or with CPU-specific optimizations
./llama-rpc-server --host 0.0.0.0 --port 50052 --threads 8
```

**On Main Host** (Obsidian):

```bash
# Run inference with remote workers
./llama-cli -m model.gguf \
    --rpc neon-laptop:50052,framework:50052 \
    --tensor-split 0.4,0.3,0.3 \  # Split weights across workers
    -p "Your prompt here"
```

### 10.3 Hybrid GPU + CPU Strategy

For our homelab with 1Gbps network:

**Scenario: Running 70B model (too large for any single GPU)**

```
┌──────────────────────────────────────────────────────────────┐
│                    MODEL LAYER DISTRIBUTION                   │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  Obsidian (Main)                                              │
│  ├── Arc A770 (16GB): Layers 0-15 (first 16 transformer)     │
│  └── RTX 2080 (8GB): Layers 16-23 (next 8 transformer)       │
│                                                               │
│  neon-laptop (RPC Worker)                                     │
│  └── CPU (32GB RAM): Layers 24-39 (16 layers)                │
│                                                               │
│  framework (RPC Worker)                                       │
│  └── CPU (64GB RAM): Layers 40-55 (16 layers)                │
│                                                               │
│  pi-server (RPC Worker - slow but available)                  │
│  └── ARM64 CPU (8GB): Layers 56-70 (final layers)            │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

**Network Bandwidth Consideration**:

- 1Gbps ≈ 125 MB/s
- Per-token activations: ~1-2MB for 70B model
- Latency per layer hop: ~10-20ms
- **Suitable for**: Batch processing, not real-time chat

### 10.4 When to Use Distributed Inference

| Use Case | Recommended Approach |
|----------|---------------------|
| **Real-time chat** | Local GPU only (RTX 2080 or A770) |
| **Batch embeddings** | Distributed across workers |
| **Large model reasoning** | Distributed with GPU + CPU |
| **Training/Fine-tuning** | Local GPU (A770 16GB) |
| **Document analysis** | Batch on distributed cluster |

### 10.5 NixOS Configuration for llama.cpp Workers

```nix
# nixos/modules/llama-worker.nix
{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    llama-cpp
  ];

  systemd.services.llama-rpc = {
    description = "llama.cpp RPC Worker";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.llama-cpp}/bin/llama-rpc-server --host 0.0.0.0 --port 50052 --threads 8";
      Restart = "always";
      RestartSec = "10";
    };
  };

  # Open firewall for RPC
  networking.firewall.allowedTCPPorts = [ 50052 ];
}
```

---

## 11. Co-Routine Architecture in Elixir

### 11.1 GenServer-Based Co-Routines

Elixir's GenServer provides a natural foundation for co-routines:

```elixir
defmodule CursorDocs.AI.Neurosymbolic.Orchestrator do
  use GenServer
  require Logger

  # State machine for reasoning sessions
  @states [:idle, :parsing, :grounding, :reasoning, :explaining, :complete, :failed]

  defstruct [
    :session_id,
    :query,
    :state,
    :context,
    :history,
    :started_at,
    :suspended_at
  ]

  ## Client API

  @doc "Start a new reasoning session"
  def reason(query) do
    session_id = UUID.generate()
    GenServer.cast(__MODULE__, {:start_session, session_id, query})
    {:ok, session_id}
  end

  @doc "Resume a suspended session"
  def resume(session_id, input) do
    GenServer.call(__MODULE__, {:resume, session_id, input})
  end

  @doc "Get session state"
  def get_state(session_id) do
    GenServer.call(__MODULE__, {:get_state, session_id})
  end

  @doc "Suspend a session"
  def suspend(session_id) do
    GenServer.call(__MODULE__, {:suspend, session_id})
  end

  ## Server Callbacks

  @impl true
  def handle_cast({:start_session, session_id, query}, state) do
    session = %__MODULE__{
      session_id: session_id,
      query: query,
      state: :parsing,
      context: %{},
      history: [],
      started_at: DateTime.utc_now()
    }
    
    # Start async processing
    Task.start(fn -> process_session(session) end)
    
    {:noreply, Map.put(state.sessions, session_id, session)}
  end

  ## Processing Pipeline

  defp process_session(session) do
    session
    |> step_parse()
    |> step_ground()
    |> step_reason()
    |> step_explain()
    |> complete_session()
  end

  defp step_parse(%{state: :parsing} = session) do
    Logger.info("Parsing: #{session.query}")
    
    case CursorDocs.AI.Neurosymbolic.Parser.parse(session.query) do
      {:ok, parsed} ->
        %{session | 
          state: :grounding, 
          context: Map.put(session.context, :parsed, parsed),
          history: [{:parse, :ok, DateTime.utc_now()} | session.history]
        }
      
      {:yield, :need_clarification, context} ->
        # SUSPEND - wait for user input
        suspend_session(session, :need_clarification, context)
      
      {:error, reason} ->
        fail_session(session, {:parse_error, reason})
    end
  end

  # ... similar for other steps
end
```

### 11.2 Session Persistence

For long-running reasoning sessions:

```elixir
defmodule CursorDocs.AI.Neurosymbolic.SessionStore do
  @moduledoc "Persist reasoning sessions to survive restarts"
  
  use GenServer
  
  @table :neurosymbolic_sessions
  
  def init(_) do
    :ets.new(@table, [:named_table, :set, :public])
    {:ok, %{}}
  end
  
  def save(session) do
    :ets.insert(@table, {session.session_id, session})
    :ok
  end
  
  def load(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, session}] -> {:ok, session}
      [] -> {:error, :not_found}
    end
  end
  
  def list_suspended do
    :ets.match_object(@table, {:_, %{state: :suspended}})
    |> Enum.map(fn {_id, session} -> session end)
  end
end
```

---

## 12. Current Model Inventory

### 12.1 Available Models on Obsidian

| Model | Size | VRAM | Port | GPU | Use Case |
|-------|------|------|------|-----|----------|
| `qwen2.5:3b` | 1.9GB | ~2GB | 11434 | RTX 2080 | Fast prototyping |
| `qwen2.5:7b` | 4.7GB | ~5GB | 11434 | RTX 2080 | General reasoning |
| `qwen2.5-coder:7b` | 4.7GB | ~5GB | 11434 | RTX 2080 | Code generation |
| `qwen2.5:14b` | 9.0GB | ~10GB | 11435 | Arc A770 | Complex reasoning |
| `nomic-embed-text` | 274MB | ~0.5GB | 11434 | RTX 2080 | Embeddings |

### 12.2 GPU Allocation Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                    OPTIMAL GPU ALLOCATION                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  RTX 2080 (8GB VRAM) - Port 11434                               │
│  ├── qwen2.5:7b (5GB) - Primary reasoning                       │
│  ├── qwen2.5-coder:7b (5GB) - Code tasks [swap with 7b]         │
│  ├── nomic-embed-text (0.5GB) - Embeddings [always loaded]      │
│  └── Reserved: 2.5GB for context/KV cache                       │
│                                                                  │
│  Arc A770 (16GB VRAM) - Port 11435                              │
│  ├── qwen2.5:14b (10GB) - Complex reasoning                     │
│  ├── [Future] mistral:7b or deepseek:7b                         │
│  └── Reserved: 6GB for context/KV cache + future models         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 12.3 Model Selection Logic

```elixir
defmodule CursorDocs.AI.ModelSelector do
  @moduledoc "Select optimal model based on task and GPU availability"
  
  @rtx_2080_port 11434
  @arc_a770_port 11435
  
  def select_model(task, opts \\ []) do
    complexity = Keyword.get(opts, :complexity, :medium)
    require_code = Keyword.get(opts, :code, false)
    
    case {task, complexity, require_code} do
      {:embedding, _, _} ->
        {:ok, %{model: "nomic-embed-text", port: @rtx_2080_port}}
      
      {:parse, :low, _} ->
        {:ok, %{model: "qwen2.5:3b", port: @rtx_2080_port}}
      
      {:parse, :medium, _} ->
        {:ok, %{model: "qwen2.5:7b", port: @rtx_2080_port}}
      
      {:reason, :high, false} ->
        {:ok, %{model: "qwen2.5:14b", port: @arc_a770_port}}
      
      {:code, _, true} ->
        {:ok, %{model: "qwen2.5-coder:7b", port: @rtx_2080_port}}
      
      {_, _, _} ->
        {:ok, %{model: "qwen2.5:7b", port: @rtx_2080_port}}
    end
  end
end
```

---

## 13. llama.cpp SYCL Backend for Intel Arc

### 13.1 Arc A770 + llama.cpp SYCL Status

**Key Findings** (2025-12-27):

The llama.cpp SYCL backend is **officially verified** for Intel Arc A770:

| Metric | Value |
|--------|-------|
| **Inference Speed** | ~55 tokens/s (up from 42 t/s before optimization) |
| **Supported Models** | All GGUF quantization types including IQ variants |
| **Backend** | Level-Zero + Intel oneAPI |
| **Memory Handling** | Supports >4GB allocations (as of Nov 2025) |

### 13.2 Ollama Vulkan Issues

**Problem**: Ollama's Vulkan backend produces gibberish on Arc A770

```
OLLAMA_HOST=http://localhost:11435 ollama run qwen2.5:14b "Explain NixOS"
# Output: "D is not is the most of the most of the least..."
```

**Root Cause**: Intel Vulkan shader compatibility issues with certain model architectures.

**Solutions**:

1. **llama.cpp with SYCL** (Recommended) - Native Intel GPU support via Level-Zero
2. **IPEX-LLM** - Intel's optimized Python runtime
3. **CPU offload** - Use RTX 2080 for generation, Arc for embeddings only

### 13.3 Building llama.cpp with SYCL on NixOS

**Requirements Added to `gpu-intel.nix`**:

```nix
# Level-Zero (oneAPI low-level interface)
level-zero

# SYCL support via AdaptiveCpp (formerly hipSYCL)
adaptivecpp
```

**Manual Build Process** (until Nix overlay is complete):

```bash
# 1. Install Intel oneAPI Base Toolkit (required for icx/icpx compilers)
#    Download from: https://www.intel.com/content/www/us/en/developer/tools/oneapi/base-toolkit-download.html

# 2. Source environment
source /opt/intel/oneapi/setvars.sh

# 3. Verify SYCL devices
sycl-ls
# Expected: [level_zero:gpu] Intel Arc A770

# 4. Build llama.cpp
cd ~/llama.cpp
cmake -B build -DGGML_SYCL=ON -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx
cmake --build build --config Release -j 16

# 5. Run inference
./build/bin/llama-cli -m /path/to/model.gguf -ngl 33 -p "Hello" -n 50
```

### 13.4 NixOS Integration Strategy

**Option A: Manual oneAPI Installation**

- Download Intel oneAPI toolkit to `/opt/intel`
- Use Nix shell with `LD_LIBRARY_PATH` pointing to oneAPI libs
- Most flexible, requires manual management

**Option B: AdaptiveCpp (hipSYCL)**

- Already in nixpkgs as `adaptivecpp`
- Open-source SYCL implementation
- Works with Level-Zero backend
- May require custom llama.cpp derivation

**Option C: Docker Container**

- Use official Intel llama.cpp SYCL Docker image
- Cleanest separation from host system
- Recommended for production deployments

### 13.5 Performance Comparison

| Backend | Arc A770 Speed | Notes |
|---------|----------------|-------|
| **SYCL (Level-Zero)** | ~55 t/s | Official, optimized |
| **Vulkan (Ollama)** | Broken | Gibberish output |
| **OpenCL** | ~30 t/s | Fallback, slower |
| **CPU (AVX512)** | ~10 t/s | i9-9900KS baseline |

### 13.6 Future: Dual-GPU SYCL

llama.cpp SYCL supports multi-GPU via `--split-mode`:

```bash
# Layer-based splitting across GPUs
./llama-cli -m model.gguf --split-mode layer -ngl 99

# Automatic device selection
GGML_SYCL_VISIBLE_DEVICES=0,1 ./llama-cli -m model.gguf
```

**Potential Setup**:

- Arc A770 (16GB): Main inference
- RTX 2080 via CUDA: Secondary for overflow

---

## 14. Next Steps

### Immediate (This Week)

1. [ ] Install Intel oneAPI Base Toolkit on Obsidian
2. [ ] Build llama.cpp with SYCL backend
3. [ ] Benchmark Arc A770 vs Ollama Vulkan vs RTX 2080 CUDA
4. [ ] Complete Elixir LNN modus ponens implementation

### Short-Term (Next 2 Weeks)

1. [ ] Create Nix overlay for llama.cpp-sycl
2. [ ] Integrate llama.cpp SYCL into cursor-docs via Port
3. [ ] Complete neuro-symbolic orchestrator integration
4. [ ] Set up distributed inference prototype with neon-laptop

### Medium-Term (Next Month)

1. [ ] Full LNN training loop in Elixir/Nx
2. [ ] DSPy integration for prompt optimization
3. [ ] Kubernetes deployment of inference endpoints
4. [ ] Symbol grounding with embedding-based approach

---

*Document Version: 0.3.0*
*Last Updated: 2025-12-27*
*Added: llama.cpp SYCL findings, Arc A770 Vulkan issues, build instructions, next steps*
