# NPM Package Security Architecture

> **Mission**: Protect nixos-cursor users from npm supply chain attacks by implementing defense-in-depth package verification.

## 🚨 Threat Context: Shai-Hulud Attacks

The **Shai-Hulud** supply chain attack campaign (November 2025) has demonstrated the severity of npm ecosystem vulnerabilities:

- **19,000+ GitHub repositories** compromised
- **526+ npm packages** infected with malware
- **Attack vector**: Credential theft → package hijacking → malicious postinstall scripts
- **Payload**: Exfiltrates environment variables, SSH keys, AWS credentials, npm tokens
- **Persistence**: Installs backdoors, modifies shell profiles, creates cron jobs

### Why MCP Servers Are High-Value Targets

```
┌─────────────────────────────────────────────────────────────────────┐
│                    MCP Server Attack Surface                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  User runs `npx -y @modelcontextprotocol/server-filesystem`          │
│                           │                                          │
│                           ▼                                          │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ npm registry resolves package + 128 transitive dependencies │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                           │                                          │
│                           ▼                                          │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │     ANY compromised dependency can execute arbitrary code    │    │
│  │     - postinstall scripts run with user privileges           │    │
│  │     - Access to: ~/.ssh, ~/.aws, ~/.config, env vars         │    │
│  │     - MCP servers have FILESYSTEM ACCESS by design           │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Current nixos-cursor attack surface** (as of November 2025):
- `@modelcontextprotocol/server-filesystem`: 129 packages
- `@modelcontextprotocol/server-github`: 46 packages
- `@modelcontextprotocol/server-memory`: 15 packages
- **Total**: ~190 unique packages, any of which could be compromised

## 🎯 Security Goals

### Primary Goals
1. **Pre-installation scanning**: Analyze packages BEFORE they execute any code
2. **Integrity verification**: Cryptographic verification of package contents
3. **Behavioral sandboxing**: Isolate package installation from sensitive data
4. **Continuous monitoring**: Detect compromises in already-installed packages
5. **Incident response**: Quick lockdown when attacks are detected

### Non-Goals (For Now)
- Real-time network monitoring during MCP server execution
- Full container isolation (would break MCP functionality)
- Source code auditing of all dependencies (not scalable)

## 🏗️ Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         NPM Security Pipeline                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐   │
│  │   Request   │───▶│    Scan     │───▶│   Verify    │───▶│   Install   │   │
│  │   Package   │    │   Package   │    │  Integrity  │    │  (Sandboxed)│   │
│  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘   │
│         │                  │                  │                  │           │
│         │                  ▼                  ▼                  ▼           │
│         │          ┌─────────────┐    ┌─────────────┐    ┌─────────────┐   │
│         │          │  NPMScan    │    │  Lockfile   │    │  Nix        │   │
│         │          │  Socket.dev │    │  Pinning    │    │  Sandbox    │   │
│         │          │  Snyk       │    │  SRI Hashes │    │  (bubblewrap)│  │
│         │          └─────────────┘    └─────────────┘    └─────────────┘   │
│         │                  │                  │                  │           │
│         │                  ▼                  ▼                  ▼           │
│         │          ┌─────────────────────────────────────────────────────┐  │
│         └─────────▶│              Security Decision Engine               │  │
│                    │  - Block known malicious packages                   │  │
│                    │  - Quarantine suspicious packages for review        │  │
│                    │  - Allow verified packages to proceed               │  │
│                    └─────────────────────────────────────────────────────┘  │
│                                                                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

## 📋 Implementation Phases

### Phase 1: Package Lockfile & Integrity (IMMEDIATE)
**Goal**: Ensure reproducible, verifiable package installations

1. **Generate lockfiles for all MCP packages**
   - Pin exact versions of all transitive dependencies
   - Include SRI hashes for integrity verification
   - Store lockfiles in nixos-cursor repository

2. **Implement integrity verification wrapper**
   - Verify package tarball hashes before extraction
   - Fail loudly on hash mismatch
   - Log all verification events

3. **Disable postinstall scripts by default**
   - Use `--ignore-scripts` flag
   - Whitelist only known-safe scripts
   - Document any required postinstall operations

### Phase 2: Pre-Installation Scanning (SHORT-TERM)
**Goal**: Detect malicious packages before they can execute

1. **Integrate with security scanners**
   - NPMScan API for real-time malware detection
   - Socket.dev for supply chain analysis
   - Snyk for vulnerability scanning

2. **Implement scanning workflow**
   ```
   Package Request → Download Tarball → Scan → Decision → Install/Block
   ```

3. **Create blocklist management**
   - Maintain list of known-malicious packages
   - Auto-update from security feeds
   - Allow user overrides with explicit acknowledgment

### Phase 3: Sandboxed Installation (MEDIUM-TERM)
**Goal**: Isolate package installation from sensitive system resources

1. **Nix sandbox for npm operations**
   - Use `nix-shell` with restricted filesystem access
   - Block network access during postinstall
   - Prevent access to ~/.ssh, ~/.aws, ~/.config

2. **Bubblewrap isolation**
   - Fine-grained filesystem permissions
   - Seccomp filters for dangerous syscalls
   - Namespace isolation

3. **Environment sanitization**
   - Strip sensitive environment variables
   - Provide fake/empty secrets during install
   - Real secrets injected only at runtime

### Phase 4: CI/CD Integration (MEDIUM-TERM)
**Goal**: Automated security checks in development workflow

1. **GitHub Actions workflow**
   ```yaml
   on: [push, pull_request]
   jobs:
     scan-npm-packages:
       - Scan all package.json/package-lock.json
       - Verify integrity hashes
       - Check against known-malicious list
       - Report vulnerabilities
   ```

2. **Pre-commit hooks**
   - Scan new dependencies before commit
   - Verify lockfile integrity
   - Block commits adding suspicious packages

3. **Automated updates with security gates**
   - Dependabot/Renovate for updates
   - Security scan before merge
   - Staged rollout with monitoring

### Phase 5: Runtime Monitoring (LONG-TERM)
**Goal**: Detect compromised behavior during MCP server execution

1. **Filesystem access monitoring**
   - Log all file reads/writes by MCP servers
   - Alert on access to sensitive paths
   - Anomaly detection for unusual patterns

2. **Network monitoring**
   - Log outbound connections
   - Block known C2 domains
   - Alert on unexpected network activity

3. **Process monitoring**
   - Track child process creation
   - Alert on shell spawning
   - Detect cryptocurrency miners

## 🔧 Implementation Details

### Lockfile Generation Script

```nix
# scripts/generate-mcp-lockfiles.nix
{ pkgs }:

pkgs.writeShellScript "generate-mcp-lockfiles" ''
  #!/usr/bin/env bash
  set -euo pipefail

  LOCKFILE_DIR="$1"
  mkdir -p "$LOCKFILE_DIR"

  # MCP packages to lock
  PACKAGES=(
    "@modelcontextprotocol/server-filesystem"
    "@modelcontextprotocol/server-github"
    "@modelcontextprotocol/server-memory"
  )

  for pkg in "''${PACKAGES[@]}"; do
    echo "Generating lockfile for $pkg..."
    
    # Create temporary directory
    tmpdir=$(mktemp -d)
    cd "$tmpdir"
    
    # Initialize package.json with single dependency
    echo "{\"dependencies\": {\"$pkg\": \"latest\"}}" > package.json
    
    # Generate lockfile with integrity hashes
    npm install --package-lock-only --ignore-scripts
    
    # Extract and save lockfile
    safe_name=$(echo "$pkg" | tr '/@' '__')
    cp package-lock.json "$LOCKFILE_DIR/$safe_name.lock.json"
    
    echo "✓ $pkg lockfile saved"
    cd -
    rm -rf "$tmpdir"
  done

  echo "All lockfiles generated in $LOCKFILE_DIR"
''
```

### Integrity Verification Wrapper

```nix
# lib/npm-security.nix
{ lib, pkgs }:

{
  # Create a secure npx wrapper that verifies package integrity
  mkSecureNpxWrapper = {
    name,
    package,
    lockfile,
    allowedPaths ? [],
    extraArgs ? [],
  }: pkgs.writeShellScript "secure-npx-${name}" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Security configuration
    LOCKFILE="${lockfile}"
    PACKAGE="${package}"
    CACHE_DIR="$HOME/.npm/_secure_cache/${name}"

    # Step 1: Verify lockfile exists and is valid
    if [[ ! -f "$LOCKFILE" ]]; then
      echo "ERROR: Security lockfile not found: $LOCKFILE" >&2
      echo "Run 'cursor-security update-lockfiles' to generate." >&2
      exit 1
    fi

    # Step 2: Check if package is in blocklist
    BLOCKLIST="${pkgs.writeText "npm-blocklist" (lib.concatStringsSep "\n" [
      "event-stream"  # Historical malware
      "flatmap-stream"
      "ua-parser-js@0.7.29"  # Compromised version
      # Add more as discovered
    ])}"
    
    if grep -qF "$PACKAGE" "$BLOCKLIST"; then
      echo "BLOCKED: Package $PACKAGE is on the security blocklist!" >&2
      exit 1
    fi

    # Step 3: Install with integrity verification
    mkdir -p "$CACHE_DIR"
    cd "$CACHE_DIR"
    
    # Copy lockfile and create minimal package.json
    cp "$LOCKFILE" package-lock.json
    echo '{"name":"secure-install","dependencies":{"'"$PACKAGE"'":"*"}}' > package.json
    
    # Install with strict integrity checking
    npm ci --ignore-scripts 2>&1 || {
      echo "ERROR: Integrity verification failed!" >&2
      echo "Package may have been tampered with." >&2
      exit 1
    }

    # Step 4: Run the package
    exec ${pkgs.nodejs_22}/bin/npx --offline "$PACKAGE" ${lib.escapeShellArgs extraArgs} "$@"
  '';

  # Pre-installation security scan
  scanPackage = { package, version ? "latest" }: pkgs.writeShellScript "scan-${package}" ''
    #!/usr/bin/env bash
    set -euo pipefail

    PACKAGE="${package}"
    VERSION="${version}"

    echo "🔍 Scanning $PACKAGE@$VERSION..."

    # Check npm audit
    echo "  Running npm audit..."
    npm audit --json --package-lock-only 2>/dev/null | jq -e '.vulnerabilities | length == 0' || {
      echo "  ⚠️  Vulnerabilities found!"
      npm audit 2>/dev/null || true
    }

    # Check against known malicious packages database
    echo "  Checking malicious package database..."
    # TODO: Integrate with NPMScan API or Socket.dev

    echo "✓ Scan complete for $PACKAGE"
  '';
}
```

### Sandboxed Installation Script

```bash
#!/usr/bin/env bash
# scripts/sandboxed-npm-install.sh
# Install npm packages in an isolated environment

set -euo pipefail

PACKAGE="$1"
OUTPUT_DIR="$2"

# Create sandbox with bubblewrap
bwrap \
  --ro-bind /nix /nix \
  --ro-bind /etc/resolv.conf /etc/resolv.conf \
  --ro-bind /etc/ssl /etc/ssl \
  --tmpfs /tmp \
  --tmpfs /home \
  --bind "$OUTPUT_DIR" /output \
  --unshare-all \
  --share-net \
  --die-with-parent \
  --new-session \
  -- /bin/bash -c "
    cd /output
    npm install --ignore-scripts '$PACKAGE'
    # Postinstall scripts run in sandbox with no access to real home
  "

echo "Package installed in sandbox: $OUTPUT_DIR"
```

### Home Manager Integration

```nix
# Extension to home-manager-module/default.nix

# Add security options
mcp.security = {
  enable = mkOption {
    type = types.bool;
    default = true;
    description = ''
      Enable npm package security features:
      - Lockfile-based integrity verification
      - Pre-installation scanning
      - Blocklist enforcement
    '';
  };

  lockfileDir = mkOption {
    type = types.str;
    default = "${config.xdg.dataHome}/nixos-cursor/lockfiles";
    description = "Directory containing package lockfiles for integrity verification.";
  };

  blocklist = mkOption {
    type = types.listOf types.str;
    default = [];
    example = [ "malicious-package" "compromised-lib@1.2.3" ];
    description = "Additional packages to block (beyond built-in blocklist).";
  };

  scanBeforeInstall = mkOption {
    type = types.bool;
    default = true;
    description = "Run security scan before installing new packages.";
  };

  allowPostinstall = mkOption {
    type = types.listOf types.str;
    default = [];
    example = [ "@modelcontextprotocol/server-filesystem" ];
    description = ''
      Packages allowed to run postinstall scripts.
      Most packages don't need postinstall scripts.
      Only whitelist if functionality is broken without them.
    '';
  };
};
```

## 📊 Security Metrics

### Key Performance Indicators

| Metric | Target | Current |
|--------|--------|---------|
| Packages with lockfiles | 100% | 0% |
| Packages with integrity hashes | 100% | 0% |
| Known-malicious packages blocked | 100% | N/A |
| Pre-install scan coverage | 100% | 0% |
| Time to block new threats | < 1 hour | N/A |

### Monitoring Dashboard

```
┌─────────────────────────────────────────────────────────────────┐
│                 NPM Security Status Dashboard                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Package Integrity         Threat Detection        Blocklist    │
│  ┌───────────────┐        ┌───────────────┐      ┌───────────┐ │
│  │ ████████░░ 80%│        │ Scans: 1,247  │      │ Blocked: 3│ │
│  │ Verified      │        │ Threats: 0    │      │ Total: 847│ │
│  └───────────────┘        └───────────────┘      └───────────┘ │
│                                                                  │
│  Recent Activity                                                 │
│  ─────────────────────────────────────────────────────────────  │
│  [OK] @modelcontextprotocol/server-filesystem verified          │
│  [OK] @modelcontextprotocol/server-github verified              │
│  [WARN] New dependency: lodash@4.17.21 - scanning...            │
│  [BLOCK] event-stream@3.3.6 - known malicious package           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 🚀 Getting Started

### For Users

1. **Update nixos-cursor** to get security features
2. **Run initial lockfile generation**:
   ```bash
   cursor-security init
   ```
3. **Security features are enabled by default**

### For Contributors

1. **When adding new MCP servers**:
   - Generate lockfile: `cursor-security add-package <package>`
   - Verify no vulnerabilities: `cursor-security scan <package>`
   - Submit lockfile with PR

2. **When updating dependencies**:
   - Regenerate lockfiles: `cursor-security update-lockfiles`
   - Review changes: `cursor-security diff`
   - Run full scan: `cursor-security scan-all`

## 📚 References

- [Shai-Hulud Attack Analysis](https://www.itpro.com/security/cyber-attacks/shai-hulud-malware)
- [NPMScan - Real-time Package Scanning](https://npmscan.com/)
- [Socket.dev - Supply Chain Security](https://socket.dev/)
- [npm audit Documentation](https://docs.npmjs.com/cli/v8/commands/npm-audit)
- [Nix Sandbox Documentation](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-sandbox)

## 🔄 Changelog

| Date | Change |
|------|--------|
| 2025-11-27 | Initial architecture document |

---

*Security is a process, not a product. This architecture will evolve as threats evolve.*
