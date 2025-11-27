# NPM Security Module

> **Protecting nixos-cursor users from npm supply chain attacks**

This module provides defense-in-depth security for npm packages used by MCP servers.

## 🚨 Why This Matters

MCP servers pull npm packages that have **deep dependency trees**:

| Package | Transitive Dependencies |
|---------|------------------------|
| `@modelcontextprotocol/server-filesystem` | 129 packages |
| `@modelcontextprotocol/server-github` | 46 packages |
| `@modelcontextprotocol/server-memory` | 15 packages |

**Any one of these packages could be compromised** (as demonstrated by the Shai-Hulud attacks in November 2025).

## 🛡️ Features

### 1. Blocklist Enforcement
Known malicious packages are blocked before they can execute:

```bash
# Check if a package is blocked
cursor-security check event-stream
# ❌ BLOCKED: event-stream is on the blocklist
```

### 2. Integrity Verification
Lockfiles with SRI hashes ensure packages haven't been tampered with:

```bash
# Generate lockfile for a package
cursor-security generate-lockfile @modelcontextprotocol/server-filesystem
```

### 3. Pattern Scanning
Scan packages for suspicious patterns before installation:

```bash
# Scan a package for IOC patterns
cursor-security scan @some/suspicious-package
```

### 4. CI/CD Integration
GitHub Actions workflow automatically scans all MCP packages on every PR.

## 📦 Files

```
security/
├── default.nix           # Main Nix module
├── README.md             # This file
├── blocklists/
│   ├── known-malicious.json    # Blocklist database
│   └── blocklist-schema.json   # JSON schema
└── lockfiles/            # Generated lockfiles (gitignored)
```

## 🔧 Usage

### In Home Manager

```nix
programs.cursor = {
  enable = true;
  mcp = {
    enable = true;
    # Security is enabled by default
    security = {
      enable = true;  # default: true
      scanBeforeInstall = true;  # default: true
      blocklist = [
        # Add custom blocked packages
        "suspicious-package"
      ];
    };
  };
};
```

### CLI Commands

```bash
# Show security status
cursor-security status

# Scan a package
cursor-security scan @modelcontextprotocol/server-filesystem

# Check blocklist
cursor-security check event-stream

# Generate lockfile
cursor-security generate-lockfile @modelcontextprotocol/server-github

# Audit cached packages
cursor-security audit
```

## 🗄️ Blocklist Format

The blocklist is a JSON file with the following structure:

```json
{
  "version": "1.0.0",
  "lastUpdated": "2025-11-27T00:00:00Z",
  "packages": {
    "category_name": {
      "description": "Category description",
      "packages": [
        {
          "name": "package-name",
          "versions": ["1.2.3", "*"],
          "reason": "Why it's blocked",
          "cve": "CVE-2021-xxxxx",
          "discovered": "2021-01-01"
        }
      ]
    }
  }
}
```

## 🔄 Updating the Blocklist

The blocklist is updated with nixos-cursor releases:

```bash
# Update your flake to get latest blocklist
nix flake update
```

To report a malicious package, open an issue or PR at:
https://github.com/e421/nixos-cursor/issues

## 📚 References

- [NPM Security Architecture](../docs/NPM_SECURITY_ARCHITECTURE.md) - Full design document
- [Shai-Hulud Attack Analysis](https://www.itpro.com/security/cyber-attacks/shai-hulud-malware)
- [Socket.dev](https://socket.dev/) - Supply chain security
- [Snyk](https://snyk.io/) - Vulnerability scanning

## 🤝 Contributing

1. **Add new malicious packages** to `blocklists/known-malicious.json`
2. **Improve IOC patterns** in the `shai_hulud_2025.indicators_of_compromise` section
3. **Test scanning** with `cursor-security scan <package>`
4. **Submit PR** with description of the threat

---

*Security is a process, not a product.*
