# npmscan MCP Server Setup

> **Purpose**: Let the AI agent inside Cursor check npm packages for malware, crypto-drainers, and known vulnerabilities before you install them.

## Overview

[npmscan.com](https://npmscan.com/) is a free, third-party malware detection service for the npm ecosystem, backed by a threat intelligence database (47K+ known threats, 2.5M+ scanned packages) and OSV.dev / GitHub Security Advisories for CVE data. It runs a public **MCP server** at `https://npmscan.com/api/mcp` — no account, no API key, nothing to configure.

Unlike every other MCP server in this repo, npmscan is **remote**: Cursor talks to it over HTTP instead of launching a local process. There's no npm package to install and no secret to manage.

This is agent-facing security research only — it does not scan or block anything automatically. It complements, but does not replace, the offline blocklist enforced by Cursor Studio's `SecurityScanner` (see [docs/internal/NPM_SECURITY_ARCHITECTURE.md](internal/NPM_SECURITY_ARCHITECTURE.md)).

## Setup

Enable it in your Home Manager config:

```nix
programs.cursor = {
  enable = true;
  mcp = {
    enable = true;
    npmscan.enable = true;
  };
};
```

Rebuild/activate your Home Manager generation, then **fully restart Cursor** (not just reload window) so it picks up the new `~/.cursor/mcp.json` entry:

```json
{
  "mcpServers": {
    "npmscan": {
      "type": "http",
      "url": "https://npmscan.com/api/mcp"
    }
  }
}
```

It's opt-in and defaults to off, since it's an external network service — enable it explicitly like `github`/`playwright`.

## Verify

Ask the agent:
```
"Use npmscan to check if event-stream@3.3.6 has any known issues"
```

If it calls an npmscan tool and returns a real result (rather than saying it has no such tool), you're set.

## Available Tools

| Tool | What it does |
|------|---------------|
| `search_packages` | Find npm packages by name or keyword |
| `get_package` | Latest version, maintainers, license, install scripts, publish history |
| `get_package_version` | Metadata for one pinned version (e.g. install scripts before you install it) |
| `query_vulnerabilities` | OSV.dev lookup for known vulnerabilities in a package (+ optional version) |
| `batch_query_vulnerabilities` | Same as above, up to 100 packages at once — good for scanning a whole `package.json` |
| `get_latest_advisories` | Reviewed GitHub Security Advisories, filterable by severity/category/CVE/GHSA ID |

Every result includes an `npmscanUrl` linking to a human-readable write-up on npmscan.com.

## Example Prompts

- "Before adding `left-pad` to package.json, check npmscan for known issues."
- "Batch-check all my dependencies in package.json against npmscan for vulnerabilities."
- "What are the latest critical npm security advisories?"
- "Does `event-stream` have any install scripts I should know about before I install version 3.3.6?"

## Rate Limits & Trust

- **No authentication** — public and free.
- **~30 requests/minute per IP** — the agent may occasionally hit this if you ask it to batch-check many packages back to back; it's a third-party service you don't control, so treat results as advisory, not a hard gate.
- Since it's unauthenticated and read-only, there's no token to rotate or leak — the only thing to weigh before enabling is that queries (package names you're curious about) are sent to a third party.

## Troubleshooting

### Agent says it has no npmscan tool
- Confirm `programs.cursor.mcp.npmscan.enable = true;` was applied and Cursor was **fully restarted**.
- Check `~/.cursor/mcp.json` contains the `npmscan` entry shown above.
- Check Cursor logs: View → Output → select "MCP" from the dropdown.

### Requests time out or get rate-limited
- You're likely over the ~30 req/min limit (e.g. asked for a large batch scan repeatedly). Wait a minute and retry, or scope the query to fewer packages.

## Self-Hosting / Override

If npmscan ever offers a private/self-hosted instance, or the endpoint changes, override the URL:

```nix
programs.cursor.mcp.npmscan.url = "https://your-instance.example.com/api/mcp";
```

---

*Last updated: 2026-08-10*
