# GitHub MCP Server Setup

> **Purpose**: Enable Cursor to create issues, PRs, commits, and manage repositories directly.

## Overview

The GitHub MCP server allows Claude to interact with GitHub on your behalf. This requires a Personal Access Token (PAT) for authentication.

## Setup

### 1. Create Personal Access Token

1. Go to: https://github.com/settings/tokens?type=beta (Fine-grained tokens)

2. Click **"Generate new token"**

3. Configure:
   | Setting | Value |
   |---------|-------|
   | Name | `cursor-mcp` |
   | Expiration | 90 days (set calendar reminder!) |
   | Repository access | All repositories (or select specific) |

4. **Permissions** (minimum required):
   | Permission | Access | Why |
   |------------|--------|-----|
   | Contents | Read & Write | Push commits, create files |
   | Issues | Read & Write | Create/update issues |
   | Pull requests | Read & Write | Create/merge PRs |
   | Metadata | Read | Required base permission |

5. Generate and **copy the token immediately**

### 2. Configure MCP

Edit `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-github"
      ],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "github_pat_XXXXXXXXXXXX"
      }
    }
  }
}
```

### 3. Restart Cursor

After updating `mcp.json`, **fully restart Cursor** (not just reload window).

### 4. Verify

Ask Claude to run a simple GitHub operation:
```
"List my recent commits on nixos-cursor"
```

If it works without "Requires authentication" errors, you're set!

## Token Storage Options

### Option A: Direct in mcp.json (Simple)
```json
"env": {
  "GITHUB_PERSONAL_ACCESS_TOKEN": "github_pat_XXXX"
}
```
- ✅ Simple
- ❌ Token visible in plaintext file

### Option B: Environment Variable (More Secure)
```json
"env": {
  "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
}
```
Then in your shell config (`~/.zshrc`):
```bash
export GITHUB_TOKEN="github_pat_XXXX"
```
- ✅ Token not in mcp.json
- ✅ Works across tools that use GITHUB_TOKEN
- ❌ Requires shell restart

### Option C: Home Manager (NixOS - Best)
```nix
# In your home.nix
programs.cursor = {
  enable = true;
  mcp.servers.github = {
    command = "npx";
    args = [ "-y" "@modelcontextprotocol/server-github" ];
    env = {
      GITHUB_PERSONAL_ACCESS_TOKEN = "$(cat /run/secrets/github-token)";
    };
  };
};
```
Combined with agenix/sops for secrets management.
- ✅ Declarative
- ✅ Secrets encrypted
- ❌ More complex setup

## Multi-Machine Sync

### The Challenge
- `mcp.json` contains your PAT
- You don't want to commit tokens to git
- You want the same config on multiple machines

### Solution: Separate Token File

1. Store token in `~/.config/cursor-secrets/github-token`:
   ```bash
   mkdir -p ~/.config/cursor-secrets
   echo "github_pat_XXXX" > ~/.config/cursor-secrets/github-token
   chmod 600 ~/.config/cursor-secrets/github-token
   ```

2. Use a wrapper script in mcp.json:
   ```json
   "github": {
     "command": "bash",
     "args": [
       "-c",
       "GITHUB_PERSONAL_ACCESS_TOKEN=$(cat ~/.config/cursor-secrets/github-token) npx -y @modelcontextprotocol/server-github"
     ]
   }
   ```

3. Sync `mcp.json` via git/dotfiles
4. Manually create token file on each machine (or use secrets sync)

## Token Renewal

Fine-grained tokens expire (max 1 year, recommended 90 days).

**Set a calendar reminder!**

When renewing:
1. Generate new token at https://github.com/settings/tokens?type=beta
2. Update `~/.cursor/mcp.json` (or token file)
3. Restart Cursor
4. Revoke old token at GitHub

## Troubleshooting

### "Requires authentication" Error
- Token not set or wrong
- Token expired
- Cursor not restarted after config change

### "Resource not accessible" Error
- Token permissions insufficient
- Try regenerating with more permissions

### MCP Server Not Starting
```bash
# Check if npx works
npx -y @modelcontextprotocol/server-github --help

# Check Cursor logs
# View → Output → Select "MCP" from dropdown
```

## Security Notes

1. **Never commit tokens to git**
2. **Use fine-grained tokens** (not classic PATs) - they're scoped and expire
3. **Minimum permissions** - only grant what you need
4. **Rotate regularly** - 90 days is reasonable
5. **Revoke if compromised** - https://github.com/settings/tokens

## Capabilities When Authenticated

| Action | Command Example |
|--------|-----------------|
| Create issue | `mcp_github_create_issue` |
| Create PR | `mcp_github_create_pull_request` |
| Push files | `mcp_github_push_files` |
| Search code | `mcp_github_search_code` |
| Merge PR | `mcp_github_merge_pull_request` |
| Fork repo | `mcp_github_fork_repository` |

---

*Last updated: 2025-11-25*
