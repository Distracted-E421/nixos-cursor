# Cursor Agent Configurations for nixos-cursor

This directory contains project-specific agent instructions for the Cursor Protocol Tools project.

## Agents

### `maxim-cursor-dev.md/json`
- **Model**: Claude Sonnet 4.5 / Claude Opus 4
- **Role**: Protocol reverse engineering, proxy development, TUI implementation
- **Cost**: 2 requests per interaction

### `gorky-cursor-dev.md/json`
- **Model**: Google Gemini 3 Pro
- **Role**: Protocol testing, traffic analysis, rapid iteration
- **Cost**: 1 request per interaction (50% cheaper!)

## Usage

Copy these to `.cursor/agents/` for use in Cursor:

```bash
cp docs/agents/*.md .cursor/agents/
cp docs/agents/*.json .cursor/agents/
```

Or reference directly in Cursor chat:
```
@docs/agents/maxim-cursor-dev.md Implement feature X
@docs/agents/gorky-cursor-dev.md Test feature X
```

## Key Principle

**Isolation First**: Always test proxy/injection in isolated environments:
```bash
cursor-backup quick              # Backup first
cursor-test --env experiment     # Isolated testing
cursor-versions run 2.0.77       # Specific version
```

Never test on your main Cursor installation!
