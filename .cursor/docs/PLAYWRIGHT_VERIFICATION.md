# Playwright MCP Verification Checklist

**Date:** 2025-10-28  
**Purpose:** Verify Playwright MCP integration is working correctly

---

## ✅ Configuration Verification

### 1. MCP Server Configuration

```bash
# Verify Playwright is in mcp.json
cat ~/.cursor/mcp.json | jq '.mcpServers | keys' | grep "cursor-browser-extension"
```

**Expected:** `"cursor-browser-extension"` appears in list

**Status:** ✅ Verified - Server configured

### 2. Dependencies Check

```bash
# Verify all MCP dependencies
which npx && which uvx && ls -la /home/e421/go/bin/d2mcp
```

**Expected:** All commands succeed

**Status:** ✅ Verified - All dependencies present

### 3. Hook Configuration

```bash
# Verify hook is registered
cat ~/.cursor/hooks.json | jq '.hooks.afterFileEdit'
```

**Expected:** `browser-test-after-deploy.sh` in array

**Status:** ✅ Verified - Hook registered

### 4. Hook Executable

```bash
# Verify hook is executable
ls -l /home/e421/homelab/.cursor/hooks/browser-test-after-deploy.sh
```

**Expected:** `-rwxr-xr-x` (executable flag set)

**Status:** ✅ Verified - Hook executable

---

## 📚 Documentation Verification

### Files Created

- [x] `.cursor/rules/playwright-browser-automation.mdc` (700+ lines)
- [x] `.cursor/hooks/browser-test-after-deploy.sh` (executable)
- [x] `.cursor/docs/PLAYWRIGHT_MCP_QUICK_REFERENCE.md` (400+ lines)
- [x] `.cursor/docs/PLAYWRIGHT_INTEGRATION_SUMMARY.md` (comprehensive)
- [x] `.cursor/docs/PLAYWRIGHT_VERIFICATION.md` (this file)

### Files Updated

- [x] `~/.cursor/mcp.json` (Playwright server added)
- [x] `~/.cursor/hooks.json` (Hook registered)
- [x] `.cursor/COMMANDS.md` (Section 6 added)
- [x] `.cursor/MCP.md` (Section 6 added)
- [x] `.cursor/rules/mcp-server-integration.mdc` (Examples 3 & 4 added)

---

## 🔧 Functional Testing

### Test 1: Basic Navigation

**Command:** "Navigate to http://example.com"

**Expected Behavior:**
1. Playwright MCP tool activates
2. Browser navigates to URL
3. Page loads successfully

**Status:** ⏳ Requires Cursor restart to test

### Test 2: Page Snapshot

**Command:** "Navigate to http://example.com and take a snapshot"

**Expected Behavior:**
1. Navigation succeeds
2. Accessibility tree snapshot returned
3. Element references visible

**Status:** ⏳ Requires Cursor restart to test

### Test 3: Screenshot Capture

**Command:** "Navigate to http://example.com and take a screenshot"

**Expected Behavior:**
1. Navigation succeeds
2. Screenshot captured
3. File saved with timestamp

**Status:** ⏳ Requires Cursor restart to test

### Test 4: Console Messages

**Command:** "Navigate to http://example.com and show console messages"

**Expected Behavior:**
1. Navigation succeeds
2. Console logs collected
3. Messages displayed (even if empty)

**Status:** ⏳ Requires Cursor restart to test

### Test 5: Network Requests

**Command:** "Navigate to http://example.com and show network requests"

**Expected Behavior:**
1. Navigation succeeds
2. Network activity captured
3. Requests listed with status codes

**Status:** ⏳ Requires Cursor restart to test

---

## 🏠 Homelab Service Testing

### Home Assistant Health Check

**Command:** "web health home-assistant"

**Expected Behavior:**
1. Navigate to http://192.168.0.61:8123
2. Snapshot verifies login form
3. Console checked for errors
4. Network requests analyzed
5. Screenshot saved to reports
6. Health status reported

**Prerequisites:**
- Home Assistant running on pi-server
- Network accessible from Obsidian
- Service on port 8123

**Status:** ⏳ Ready to test after Cursor restart

### Local Service Test

**Command:** "Navigate to http://localhost:3000"

**Expected Behavior:**
- If service running: Page loads
- If service not running: Connection refused error (expected)
- Error handling graceful

**Status:** ⏳ Ready to test after Cursor restart

---

## 🎯 Command Pattern Verification

### Command: web health

**Pattern:** `web health [service-name]`

**Test Cases:**
- [x] Documented in COMMANDS.md
- [x] Examples provided in COMMANDS.md
- [x] Rule guidance in playwright-browser-automation.mdc
- [x] Quick reference entry in PLAYWRIGHT_MCP_QUICK_REFERENCE.md

### Command: web verify

**Pattern:** `web verify [service-name]`

**Test Cases:**
- [x] Documented in COMMANDS.md
- [x] Examples provided
- [x] Rule guidance provided
- [x] Quick reference entry

### Command: test [feature] in browser

**Pattern:** `test [feature] in browser`

**Test Cases:**
- [x] Documented in COMMANDS.md
- [x] Examples provided
- [x] Rule guidance provided
- [x] Quick reference entry

### Command: check console at [url]

**Pattern:** `check console at [url]`

**Test Cases:**
- [x] Documented in COMMANDS.md
- [x] Examples provided
- [x] Rule guidance provided
- [x] Quick reference entry

---

## 🔗 Integration Verification

### With Memory MCP

**Test:** "Remember that Home Assistant is at http://192.168.0.61:8123"

**Expected:**
1. Memory entity created
2. URL stored for future reference
3. Can retrieve with "What's the Home Assistant URL?"

**Status:** ⏳ Ready to test

### With Filesystem MCP

**Test:** Take screenshot and save to organized directory

**Expected:**
1. Screenshot captured via Playwright
2. File saved via Filesystem MCP
3. Path verified: devices/Obsidian/reports/screenshots/

**Status:** ⏳ Ready to test

### With GitHub MCP

**Test:** Create issue with browser testing evidence

**Expected:**
1. Browser test identifies issue
2. Screenshot captured
3. GitHub issue created with screenshot link

**Status:** ⏳ Ready to test (requires actual issue)

---

## 🎓 Memory MCP Verification

### Knowledge Stored

**Entities Created:**
- [x] "Playwright MCP Integration" (System Configuration)
- [x] "Browser Automation Commands" (Workflow Pattern)

**Verification Command:** "What do you know about Playwright MCP?"

**Expected Response:**
- Integration date (2025-10-28)
- Configuration details
- Command patterns
- Best practices
- Service URLs

**Status:** ✅ Memory entries created successfully

---

## 📋 Pre-Use Checklist

Before first use, complete these steps:

### 1. Restart Cursor

**Why:** Load new MCP configuration

**Command:**
```bash
# Close Cursor completely
# Reopen Cursor
# Verify MCP servers loaded in Output → MCP
```

**Status:** ⏳ User action required

### 2. Install Chromium Browser

**Why:** First-time Playwright setup

**Command:** "Install the Playwright browser"

**Expected:** Browser downloads and installs automatically

**Status:** ⏳ Will complete on first use

### 3. Test Basic Navigation

**Why:** Verify MCP server is responding

**Command:** "Navigate to http://example.com"

**Expected:** Browser navigates successfully

**Status:** ⏳ Pending Cursor restart

---

## 🚀 Post-Restart Test Sequence

### Recommended Test Order

1. **Basic Navigation**
   ```
   "Navigate to http://example.com"
   ```

2. **Snapshot Test**
   ```
   "Take a snapshot of the page"
   ```

3. **Screenshot Test**
   ```
   "Take a screenshot"
   ```

4. **Console Check**
   ```
   "Show console messages"
   ```

5. **Network Analysis**
   ```
   "Show network requests"
   ```

6. **Home Assistant Health Check** (if accessible)
   ```
   "web health home-assistant"
   ```

---

## ✅ Success Criteria

Integration is successful if:

- ✅ **Configuration:** MCP server in mcp.json
- ✅ **Dependencies:** All tools installed (npx, uvx, d2mcp)
- ✅ **Hooks:** browser-test-after-deploy.sh registered and executable
- ✅ **Documentation:** All 5 files created/updated
- ✅ **Rules:** playwright-browser-automation.mdc applied
- ✅ **Commands:** 8 command patterns documented
- ✅ **Memory:** Integration knowledge stored
- ⏳ **Functional:** Browser navigation works (after restart)
- ⏳ **Integration:** Works with other MCP servers (after restart)

---

## 🐛 Troubleshooting

### Issue: MCP Server Not Loading

**Symptoms:** Playwright tools not available in Cursor

**Solutions:**
1. Restart Cursor completely
2. Check `~/.cursor/mcp.json` syntax (valid JSON)
3. Verify npx is in PATH: `which npx`
4. Check Cursor logs: Output → MCP

### Issue: Browser Not Installing

**Symptoms:** Error about missing browser

**Solutions:**
1. Run: "Install the Playwright browser"
2. Check network connectivity
3. Verify disk space available
4. Check npm/npx working: `npx --version`

### Issue: Hook Not Triggering

**Symptoms:** No suggestions after deployment file edits

**Solutions:**
1. Verify hook is executable: `ls -l .cursor/hooks/browser-test-after-deploy.sh`
2. Check hooks.json registration
3. Verify modified files match patterns in hook
4. Check hook script for syntax errors

---

## 📊 Integration Status Summary

| Component | Status | Notes |
|-----------|--------|-------|
| MCP Config | ✅ Complete | Server configured in mcp.json |
| Dependencies | ✅ Verified | npx, uvx, d2mcp all present |
| Rules | ✅ Complete | 700+ line comprehensive rule |
| Commands | ✅ Complete | 8 command patterns documented |
| Hooks | ✅ Complete | Deployment verification hook |
| Documentation | ✅ Complete | 4 comprehensive docs |
| Memory | ✅ Complete | Integration knowledge stored |
| Functional Testing | ⏳ Pending | Requires Cursor restart |
| Integration Testing | ⏳ Pending | Requires functional test pass |

---

## 🎯 Next Actions

1. **Restart Cursor** to load MCP configuration
2. **Run test sequence** to verify functionality
3. **Test Home Assistant** health check (if accessible)
4. **Create screenshot directory structure**:
   ```bash
   mkdir -p devices/Obsidian/reports/screenshots/$(date +%Y-%m-%d)
   mkdir -p docs/screenshots
   ```
5. **Store service URLs** in Memory MCP for quick access
6. **Begin using** browser automation in workflows

---

**Integration Complete:** All configuration and documentation finished. Ready for use after Cursor restart.

**Estimated Time to Full Operational:** ~5 minutes (restart + browser install + basic tests)
