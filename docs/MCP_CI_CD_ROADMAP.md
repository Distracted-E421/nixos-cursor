# MCP Server CI/CD Pipeline Roadmap

This document outlines the roadmap for implementing a CI/CD pipeline for MCP servers and future tool protocol support.

## Current State

### Active MCP Servers
- **filesystem** - File operations (read, write, list directories)
- **memory** - Persistent context storage
- **nixos** - NixOS package/option search
- **github** - Git operations, issues, PRs
- **playwright** - Browser automation

### Configuration
MCP servers are configured in `~/.cursor/mcp.json` (managed by Home Manager).

## Phase 1: MCP Server Health Monitoring (Current)

### Goals
1. Detect when MCP servers fail to start
2. Monitor server health during Cursor sessions
3. Alert on server crashes or timeouts

### Implementation
```yaml
# .github/workflows/mcp-health.yml
name: MCP Server Health Check

on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  check-mcp-servers:
    runs-on: ubuntu-latest
    steps:
      - name: Test filesystem MCP
        run: |
          echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | \
            npx -y @modelcontextprotocol/server-filesystem /tmp
          
      - name: Test memory MCP
        run: |
          echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | \
            npx -y @modelcontextprotocol/server-memory
```

## Phase 2: MCP Server Version Pinning

### Goals
1. Pin MCP server versions for reproducibility
2. Test upgrades before deployment
3. Rollback capability

### Implementation
```nix
# In Home Manager module
programs.cursor.mcpServers = {
  filesystem = {
    package = pkgs.nodePackages."@modelcontextprotocol/server-filesystem";
    version = "0.6.2";  # Pinned version
    args = [ "/home/user/projects" ];
  };
  
  memory = {
    package = pkgs.mcp-server-memory;
    version = "2025.9.25";
  };
};
```

## Phase 3: First-Class Tool Support

### Goals
1. Support tools beyond MCP (future protocols)
2. Unified tool configuration
3. Tool capability discovery

### Proposed Architecture
```
┌─────────────────────────────────────────────┐
│              Cursor IDE                      │
├─────────────────────────────────────────────┤
│         Tool Protocol Adapter                │
│  ┌─────────┐ ┌─────────┐ ┌─────────────────┐│
│  │   MCP   │ │ Future  │ │  Native Tools   ││
│  │ Servers │ │Protocol │ │ (grep, edit)    ││
│  └─────────┘ └─────────┘ └─────────────────┘│
└─────────────────────────────────────────────┘
```

### Tool Categories
1. **MCP Servers** - Current implementation
2. **LSP Extensions** - Language server protocol tools
3. **Native Tools** - Built-in Cursor tools
4. **Custom Protocols** - Future tool protocols

## Phase 4: CI/CD Pipeline

### Workflow Structure
```
┌────────────────────────────────────────────────────────┐
│                    GitHub Actions                       │
├────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐ │
│  │   Build     │───▶│    Test     │───▶│   Deploy    │ │
│  │   MCP       │    │   Tools     │    │   Config    │ │
│  └─────────────┘    └─────────────┘    └─────────────┘ │
│         │                  │                  │         │
│         ▼                  ▼                  ▼         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐ │
│  │  Nix Build  │    │  Protocol   │    │  Cachix     │ │
│  │  Packages   │    │  Compliance │    │   Push      │ │
│  └─────────────┘    └─────────────┘    └─────────────┘ │
│                                                         │
└────────────────────────────────────────────────────────┘
```

### CI Jobs
1. **build-mcp-packages** - Build all MCP server packages
2. **test-mcp-protocol** - Verify MCP protocol compliance
3. **test-tool-integration** - Test tool invocation
4. **deploy-to-cachix** - Push built packages to cache

### CD Jobs
1. **update-home-manager** - Update module with new versions
2. **notify-users** - Create release notes
3. **rollback-on-failure** - Automatic rollback mechanism

## Phase 5: Tool Discovery and Registration

### Goals
1. Automatic tool discovery from flake
2. Tool capability introspection
3. Dynamic tool loading

### Implementation
```nix
# flake.nix
{
  outputs = { ... }: {
    # Tool registry
    tools = {
      mcp = {
        filesystem = ./mcp/filesystem;
        memory = ./mcp/memory;
        nixos = ./mcp/nixos;
      };
      
      native = {
        grep = ./tools/grep;
        edit = ./tools/edit;
      };
    };
    
    # Tool metadata
    toolMeta = {
      filesystem = {
        description = "File system operations";
        capabilities = [ "read" "write" "list" ];
        protocol = "mcp";
      };
    };
  };
}
```

## Timeline

| Phase | Target | Status |
|-------|--------|--------|
| Phase 1 | Q1 2025 | 🟡 In Progress |
| Phase 2 | Q2 2025 | 📋 Planned |
| Phase 3 | Q3 2025 | 📋 Planned |
| Phase 4 | Q3 2025 | 📋 Planned |
| Phase 5 | Q4 2025 | 📋 Planned |

## Related Documentation

- [MCP GitHub Setup](./MCP_GITHUB_SETUP.md)
- [Secrets Management](./SECRETS_MANAGEMENT.md)
- [Auto Update Implementation](./AUTO_UPDATE_IMPLEMENTATION.md)

## Contributing

To contribute to MCP server development:

1. Create a new MCP server in `mcp/` directory
2. Add Nix packaging in `mcp/<server>/default.nix`
3. Add tests in `tests/mcp/<server>/`
4. Update this roadmap with new capabilities

