# Playwright MCP Quick Reference

**Last Updated:** 2025-10-28  
**MCP Server:** `cursor-browser-extension`  
**Status:** ✅ Operational

---

## 🚀 Quick Start

### First Time Setup

1. **Install Chromium Browser** (one-time):
   ```
   "Install the Playwright browser"
   ```

2. **Test Navigation**:
   ```
   "Navigate to http://example.com"
   ```

3. **Take First Screenshot**:
   ```
   "Take a screenshot"
   ```

---

## 📚 Common Commands

### Navigation

```
"Navigate to http://192.168.0.61:8123"
"Go to http://localhost:3000"
"Go back to previous page"
"Resize browser to 1920x1080"
```

### Page Inspection

```
"Take a snapshot of the page"
"Take a screenshot"
"Take a full-page screenshot"
"Show console messages"
"Show network requests"
```

### Interaction

```
"Click the login button (ref: button.login)"
"Type 'username' into the username field"
"Press Enter key"
"Fill form with username=admin, password=secret"
"Select 'Option 1' from dropdown"
```

### Tab Management

```
"List all open tabs"
"Open a new tab"
"Switch to tab 2"
"Close current tab"
```

### Advanced

```
"Run JavaScript: document.title"
"Accept the alert dialog"
"Dismiss the confirm dialog"
```

---

## 🎯 Common Workflows

### Health Check a Service

```
1. "Navigate to http://192.168.0.61:8123"
2. "Take a snapshot"
3. "Show console messages"
4. "Show network requests"
5. "Take a screenshot for documentation"
```

### Test Login Flow

```
1. "Navigate to http://localhost:8080/login"
2. "Take a snapshot"  # Get element refs
3. "Type 'admin' into username field (ref: input#username)"
4. "Type 'password' into password field (ref: input#password)"
5. "Click login button (ref: button[type='submit'])"
6. "Wait for 'Dashboard' text to appear"
7. "Take a screenshot"
```

### Debug Web App

```
1. "Navigate to http://localhost:3000"
2. "Show console messages"  # Check for JS errors
3. "Show network requests"  # Check for failed API calls
4. "Take a screenshot"      # Visual inspection
```

### Document Service UI

```
1. "Navigate to http://192.168.0.61:8123"
2. "Wait for 'Home Assistant' text to appear"
3. "Take a full-page screenshot"
4. Save with descriptive name for documentation
```

---

## 🔧 Tool Reference

### Core Tools

| Tool | Purpose | Example |
|------|---------|---------|
| `browser_navigate` | Go to URL | "Navigate to http://example.com" |
| `browser_navigate_back` | Previous page | "Go back" |
| `browser_snapshot` | Page structure | "Take a snapshot" |
| `browser_take_screenshot` | Visual capture | "Take a screenshot" |
| `browser_wait_for` | Wait for condition | "Wait for 'Login' text" |

### Interaction Tools

| Tool | Purpose | Example |
|------|---------|---------|
| `browser_click` | Click element | "Click button (ref: .login-btn)" |
| `browser_type` | Type text | "Type 'hello' into input" |
| `browser_hover` | Hover element | "Hover over menu (ref: nav.menu)" |
| `browser_press_key` | Keyboard input | "Press Enter" |
| `browser_fill_form` | Fill multiple fields | "Fill form with data" |
| `browser_select_option` | Select dropdown | "Select 'Option 1'" |
| `browser_drag` | Drag and drop | "Drag element1 to element2" |

### Debug Tools

| Tool | Purpose | Example |
|------|---------|---------|
| `browser_console_messages` | Get console logs | "Show console messages" |
| `browser_network_requests` | Get network activity | "Show network requests" |
| `browser_evaluate` | Run JavaScript | "Run JS: document.title" |

### Tab Tools

| Tool | Purpose | Example |
|------|---------|---------|
| `browser_tabs` (list) | List tabs | "List all tabs" |
| `browser_tabs` (new) | New tab | "Open new tab" |
| `browser_tabs` (select) | Switch tab | "Switch to tab 2" |
| `browser_tabs` (close) | Close tab | "Close current tab" |

---

## 💡 Best Practices

### 1. Always Snapshot Before Interacting

**Why:** Snapshot gives you element references (`ref`) needed for clicks/typing

```
❌ Bad:
"Click the login button"  # AI has no element reference

✅ Good:
"Take a snapshot"
"Click the login button (ref: button.login-btn)"
```

### 2. Use Snapshot, Not Screenshot for Actions

```
❌ Bad:
"Take a screenshot and click the button"  # Can't interact with image

✅ Good:
"Take a snapshot"  # Get actionable element tree
"Click button (ref: from snapshot)"
```

### 3. Wait for Dynamic Content

```
❌ Bad:
"Navigate to URL"
"Immediately click button"  # Might not be loaded yet

✅ Good:
"Navigate to URL"
"Wait for 'Dashboard' text to appear"
"Take snapshot"
"Click button"
```

### 4. Check Console and Network for Debugging

```
✅ Comprehensive debugging:
1. Navigate to page
2. Take snapshot (structure)
3. Show console messages (JS errors)
4. Show network requests (API failures)
5. Take screenshot (visual state)
```

### 5. Organize Screenshots

```
✅ Good naming:
- devices/Obsidian/reports/screenshots/YYYY-MM-DD/service-name.png
- docs/screenshots/feature-description-YYYY-MM-DD.png

❌ Bad naming:
- screenshot.png
- image1.png
```

---

## 🏠 Homelab Services

### Home Assistant

```
URL: http://192.168.0.61:8123
Common Tasks:
- "web health home-assistant"
- "Screenshot dashboard for docs"
- "Test automation trigger"
```

### Grafana (if deployed)

```
URL: http://obsidian:3000
Common Tasks:
- "web verify grafana"
- "Screenshot dashboard panels"
- "Test alert configuration"
```

### Local Dev Servers

```
URL: http://localhost:<port>
Common Tasks:
- "Test login flow"
- "Check console for errors"
- "Verify deployment"
```

---

## 🚨 Common Issues

### Issue: Browser Not Installed

**Symptoms:** Error about missing browser

**Solution:**
```
"Install the Playwright browser"
```

### Issue: Element Not Found

**Symptoms:** Can't click element

**Solutions:**
1. Take snapshot first to get element reference
2. Wait for element to load: "Wait for 'text' to appear"
3. Check if element exists in snapshot

### Issue: Page Not Loading

**Symptoms:** Timeout errors

**Solutions:**
1. Check URL is correct and accessible
2. Wait longer: "Wait for 5 seconds"
3. Check network requests for failures

### Issue: Screenshots in Wrong Location

**Symptoms:** Can't find screenshot files

**Solution:**
- Screenshots save to current directory by default
- Specify path: "Take screenshot, save as docs/screenshots/name.png"
- Organize by date/service for easy finding

---

## 🎨 Advanced Patterns

### Pattern: Multi-Page Workflow

```
Test complete user journey:
1. "Navigate to login page"
2. "Fill login form"
3. "Click submit"
4. "Wait for dashboard"
5. "Navigate to settings"
6. "Change configuration"
7. "Verify changes applied"
```

### Pattern: Visual Regression

```
Compare before/after:
1. "Take screenshot (before)"
2. Make changes
3. "Navigate to page again"
4. "Take screenshot (after)"
5. Compare visually
```

### Pattern: Automated Health Checks

```
For each service:
1. "Navigate to service URL"
2. "Take snapshot" (structure check)
3. "Show console messages" (error check)
4. "Show network requests" (API check)
5. Report: ✅ Healthy or ❌ Issues
```

### Pattern: Documentation Generation

```
Document all pages:
1. "Navigate to page 1"
2. "Take full-page screenshot"
3. "Navigate to page 2"
4. "Take full-page screenshot"
5. Generate markdown with all images
```

---

## 📊 Performance Tips

### Efficient Testing

```
✅ Batch operations:
"Navigate to URL, wait for text, take snapshot, show console, take screenshot"

❌ Individual operations:
"Navigate to URL"
"Wait for text"
"Take snapshot"
...
```

### Smart Debugging

```
✅ Get all debug info at once:
"Show console messages and network requests"

❌ Multiple separate requests:
"Show console"
[wait]
"Show network"
```

---

## 🔗 Integration with Other MCP Servers

### With Memory MCP

```
Store service URLs:
"Remember that Home Assistant is at http://192.168.0.61:8123"

Use later:
"What's the Home Assistant URL?"
"Navigate there and take screenshot"
```

### With Filesystem MCP

```
Save screenshots to docs:
1. "Take screenshot"
2. Save to docs/screenshots/ directory
3. Update documentation with image reference
```

### With GitHub MCP

```
Create issues with screenshots:
1. Find bug via browser testing
2. "Take screenshot"
3. "Create GitHub issue with screenshot"
```

---

## 📚 Related Documentation

- **Full Rule:** `.cursor/rules/playwright-browser-automation.mdc`
- **Commands:** `.cursor/COMMANDS.md` (Browser Automation section)
- **MCP Overview:** `.cursor/MCP.md`
- **Hooks:** `.cursor/hooks/browser-test-after-deploy.sh`

---

## 🎯 Quick Command Summary

| Use Case | Command Pattern |
|----------|----------------|
| Health check | `web health [service]` |
| Visual verify | `web verify [service]` |
| Test flow | `test [feature] in browser` |
| Debug errors | `check console at [url]` |
| Check network | `analyze network requests at [url]` |
| Screenshot docs | `screenshot [url] for docs` |
| Form automation | `fill form at [url] with [data]` |

---

**Remember:** Playwright is powerful for dynamic web content. Always snapshot before interacting, check console/network for debugging, and organize screenshots for easy reference.

**Need Help?** Check the full rule at `.cursor/rules/playwright-browser-automation.mdc` or ask "How do I use Playwright MCP for [task]?"
