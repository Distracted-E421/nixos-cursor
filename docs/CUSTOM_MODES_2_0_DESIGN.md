# Custom Modes 2.0: Proxy-Based Design

## 🎯 Goal

Restore full custom modes functionality for Cursor 2.4.x by integrating mode management with the proven proxy injection system.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Custom Modes 2.0                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐    ┌───────────────────────────────────┐ │
│  │  Mode Manager    │    │       Delivery Layer              │ │
│  │  (CLI / EGUI)    │    │                                   │ │
│  │                  │    │  ┌─────────────┐  ┌────────────┐ │ │
│  │  • Mode CRUD     │───▶│  │ Proxy Mode  │  │ File Mode  │ │ │
│  │  • System Prompt │    │  │ (Primary)   │  │ (Fallback) │ │ │
│  │  • Tool Access   │    │  │             │  │            │ │ │
│  │  • Model Config  │    │  │ cursor-proxy│  │.cursorrules│ │ │
│  │  • Context       │    │  └─────────────┘  └────────────┘ │ │
│  └──────────────────┘    └───────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Cursor IDE                                │
│                                                                 │
│  [Requests] ──▶ [cursor-proxy] ──▶ [api2.cursor.sh]             │
│                      │                                           │
│                      ▼                                           │
│               [Injected System Context]                          │
└─────────────────────────────────────────────────────────────────┘
```

## 📦 Components

### 1. Mode Definition (Existing)

```rust
// cursor-studio-egui/src/modes/config.rs
pub struct CustomMode {
    pub name: String,
    pub icon: String,
    pub description: String,
    pub system_prompt: String,       // Core instruction
    pub tools: ToolAccess,           // Allowlist/blocklist
    pub model: ModelConfig,          // Primary/fallback
    pub context: ContextConfig,      // Environment, git, etc.
}
```

### 2. Injection Bridge (New)

A new component that translates `CustomMode` → `InjectionConfig`:

```rust
// cursor-studio-egui/src/modes/proxy_bridge.rs
pub struct ProxyBridge {
    socket_path: PathBuf,  // ~/.cursor-proxy/control.sock
}

impl ProxyBridge {
    /// Send mode configuration to running proxy
    pub async fn set_mode(&self, mode: &CustomMode) -> Result<()> {
        let config = self.mode_to_injection(mode);
        self.send_config(config).await
    }
    
    /// Convert mode to injection config
    fn mode_to_injection(&self, mode: &CustomMode) -> InjectionConfig {
        let system_prompt = self.build_full_prompt(mode);
        
        InjectionConfig {
            enabled: true,
            system_prompt: Some(system_prompt),
            context_files: mode.context.additional_files.clone(),
            headers: HashMap::new(),
            spoof_version: None,
        }
    }
    
    /// Build complete system prompt from mode
    fn build_full_prompt(&self, mode: &CustomMode) -> String {
        let mut prompt = String::new();
        
        // Mode identity
        prompt.push_str(&format!("# Active Mode: {} {}\n\n", mode.icon, mode.name));
        prompt.push_str(&mode.description);
        prompt.push_str("\n\n");
        
        // System prompt
        prompt.push_str(&mode.system_prompt);
        prompt.push_str("\n\n");
        
        // Tool restrictions
        prompt.push_str(&self.build_tool_section(&mode.tools));
        
        // Model hints
        prompt.push_str(&format!(
            "\n## Model Configuration\nOptimized for: {}\n",
            mode.model.primary
        ));
        
        prompt
    }
}
```

### 3. Proxy Control API (New Addition to cursor-proxy)

Add a Unix socket or HTTP endpoint for runtime config:

```rust
// cursor-proxy: Add control socket handler
async fn start_control_socket(
    state: Arc<ProxyState>,
    path: PathBuf,
) -> Result<()> {
    let listener = UnixListener::bind(&path)?;
    
    loop {
        let (stream, _) = listener.accept().await?;
        let state = Arc::clone(&state);
        
        tokio::spawn(async move {
            handle_control_message(stream, state).await;
        });
    }
}

async fn handle_control_message(
    mut stream: UnixStream,
    state: Arc<ProxyState>,
) {
    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).await.unwrap();
    
    if let Ok(config) = serde_json::from_slice::<InjectionConfig>(&buf) {
        state.injection.update_config(config).await;
        stream.write_all(b"OK").await.unwrap();
    }
}
```

## 🔄 Workflow

### Mode Activation

1. User selects mode in CLI/GUI
2. Mode Manager builds full system prompt
3. **If proxy running**: Send config via control socket
4. **If proxy not running**: Fall back to file-based injection
5. Confirmation shown to user

### Hot Reload Flow

```
User clicks "Code Review" mode
         │
         ▼
    Mode Manager
         │
         ├──▶ Check: Is proxy running?
         │         │
         │    YES  │  NO
         │    │    │
         ▼    ▼    ▼
    Send to proxy │ Write to files
    via socket    │ (.cursorrules)
         │        │
         ▼        ▼
       ✓ Active  ✓ Active
       (instant) (next request)
```

## 📝 System Prompt Structure

When mode is activated, the injected context looks like:

```markdown
# Active Mode: 🔍 Code Review

Expert code reviewer focusing on quality, security, and best practices.

## Your Role
You are a meticulous code reviewer. Focus on:
- Security vulnerabilities
- Performance issues
- Code clarity and maintainability
- Best practices adherence

## Tool Access (BLOCKLIST)
You may NOT use these tools:
- `run_terminal_cmd` (no executing code)
- `write` (no modifying files)
- `delete_file` (no deleting)

All other tools are allowed.

## Model Configuration
Optimized for: claude-opus-4

## Environment
- Host: Obsidian
- OS: NixOS 25.11
- User: e421
- Project: nixos-cursor
- Branch: main (3 uncommitted changes)
```

## 🔧 Implementation Plan

### Phase 1: Control Socket (Priority)
1. Add Unix socket listener to cursor-proxy
2. Implement JSON config protocol
3. Test runtime config updates

### Phase 2: Bridge Module
1. Create `proxy_bridge.rs` in cursor-studio-egui
2. Implement mode → injection config conversion
3. Add proxy detection and fallback logic

### Phase 3: CLI Integration
1. Add `cursor-modes set <mode>` command
2. Add `cursor-modes list` command
3. Add `cursor-modes status` command

### Phase 4: GUI Integration
1. Update EGUI mode panel
2. Add proxy status indicator
3. Show active mode badge

## 📂 File Locations

```
~/.cursor-proxy/
├── control.sock       # Unix socket for runtime control
├── ca-cert.pem        # CA certificate
├── ca-key.pem         # CA private key
└── injection.toml     # Fallback config file

~/.config/cursor-studio/
├── modes/
│   ├── registry.json  # Active mode tracking
│   ├── agent.json
│   ├── code-review.json
│   ├── planning.json
│   └── maxim.json     # Custom modes
└── config.toml        # Studio settings
```

## 🔐 Security Considerations

1. **Socket permissions**: 0600 on control.sock
2. **Config validation**: Validate all JSON before applying
3. **Prompt sanitization**: Escape special characters
4. **Version check**: Ensure proxy/client compatibility

## ✅ Success Criteria

- [ ] Mode changes take effect within 100ms
- [ ] Works with Cursor 2.4.x versions
- [ ] Graceful fallback when proxy unavailable
- [ ] No request failures due to injection
- [ ] Tool restrictions properly enforced by AI

## 📊 Comparison

| Feature | File-Based | Proxy-Based |
|---------|-----------|-------------|
| Latency | Next request | Instant |
| Reliability | Depends on Cursor | 100% (we control) |
| System prompt | May be filtered | Always injected |
| Tool restrictions | Hint only | Enforced via prompt |
| Version compat | Unknown | Works with all |

