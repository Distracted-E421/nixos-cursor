# AI Visual Feedback Workflow

## Overview

This document describes how to provide visual feedback to the AI assistant during Cursor Studio development using screenshots.

## How It Works

1. **Take Screenshot**: Run the screenshot script
2. **AI Views**: AI uses `mcp_filesystem_read_media_file` to view the image
3. **Feedback Loop**: AI can see UI state and provide specific guidance

## Quick Commands

### Take Screenshot

```bash
# Full screen capture (shows entire desktop)
~/nixos-cursor/scripts/ui-feedback.sh "Cursor Studio" "" full

# Active window (focus Cursor Studio first)
~/nixos-cursor/scripts/ui-feedback.sh "Cursor Studio" "" window

# Screenshots saved to: ~/nixos-cursor/screenshots/
# Latest always at: ~/nixos-cursor/screenshots/latest.png
```

### Request AI Review

After taking a screenshot, tell the AI:

> "I took a screenshot. Check ~/nixos-cursor/screenshots/latest.png for the current UI state."

The AI will use `read_media_file` to view it and provide feedback.

## Workflow Example

```
User: "The Index panel looks off. Let me grab a screenshot..."
User: [runs ui-feedback.sh]
User: "Check the latest screenshot and tell me what needs fixing."

AI: [views screenshot]
AI: "I can see the issue - the stats cards aren't aligned. The 'Sources' 
     card is 10px wider than 'Chunks'. Let me fix that..."
```

## Screenshots Directory

```
~/nixos-cursor/screenshots/
├── latest.png              # Symlink to most recent
├── cursor-studio-20251216_201342.png
├── cursor-studio-20251216_202015.png
└── ...
```

## Tips

1. **Focus the window** before taking window-specific screenshots
2. **Use meaningful names** for comparison: `ui-feedback.sh "Cursor Studio" "before-fix.png"`
3. **Take before/after** pairs when making UI changes
4. **Clean up old screenshots** periodically: `rm ~/nixos-cursor/screenshots/cursor-studio-*.png`

## Supported Capture Modes

| Mode | Flag | Description |
|------|------|-------------|
| Full | `full` | Entire screen (all monitors) |
| Window | `window` | Active/focused window only |
| Region | `region` | Interactive selection |

## Integration with Development

### Aliases (after rebuild)

```bash
ui-screenshot          # Default: window capture
ui-screenshot-full     # Full screen
ui-screenshot-window   # Active window
```

### In Cursor/Terminal

```bash
# Quick visual check
~/nixos-cursor/scripts/ui-feedback.sh && echo "Screenshot ready for AI review"
```

## Troubleshooting

### "Screenshot failed"

- Check if `spectacle` is installed: `which spectacle`
- For window capture, ensure the target window is focused
- Try full screen mode as fallback

### AI Can't See Image

The AI uses `mcp_filesystem_read_media_file` which requires:
- File must be in allowed directories (~/nixos-cursor is allowed)
- File must be a valid PNG/JPEG
- Path must be absolute or relative to workspace

## Future Improvements

- [ ] Automated screenshot on Cursor Studio launch
- [ ] Diff visualization between screenshots
- [ ] Annotation support (highlight specific areas)
- [ ] Integration with CI for visual regression testing

