# AI Workspace

This directory is the AI assistant's persistent workspace for:

- **Drafting ideas** before touching real code
- **Tracking multi-step plans** with checkpoints
- **Managing experiments** via git branches
- **Contextual hints** based on current task

## Directory Structure

```
.ai-workspace/
├── context/           # Current task context detection
│   └── current.json   # What the AI is currently doing
├── scratchpad/        # Draft ideas, notes, exploration
│   └── *.md          # Markdown drafts (gitignored)
├── plans/            # Multi-step task tracking
│   └── *.json        # Plan definitions with checkpoints
├── experiments/      # Git experiment branch tracking
│   └── *.json        # Branch metadata and hypotheses
├── hints.md          # Current contextual hints for AI
└── relevant-tools.md # Tools relevant to current context
```

## Usage

The AI can:

1. **Draft before committing**: Write ideas to `scratchpad/` before touching main code
2. **Create experiment branches**: Try risky changes in isolated branches
3. **Track progress**: Use plans with checkpoints for complex tasks
4. **Review hints**: Read contextual reminders about available tools

## Privacy

- `scratchpad/` contents are gitignored
- This workspace is for AI thinking, not permanent documentation
- Clean up old drafts periodically

