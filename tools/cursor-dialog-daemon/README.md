# Cursor Dialog Daemon

A D-Bus daemon that provides interactive dialogs for Cursor AI agents, enabling real-time user feedback without burning API requests.

## Features

- **Multiple Choice Dialogs** - Single or multi-select options with descriptions
- **Text Input** - Single line or multiline with optional validation
- **Confirmation** - Yes/No with customizable labels
- **Slider** - Numeric input with min/max/step
- **Toast Notifications** - Non-blocking status updates (success, warning, error, info)
- **Comment Field** - Every dialog has an optional comment field for context
- **Timer with Pause** - Auto-timeout with user-controllable pause

## Installation

### Via cursor-studio (Recommended)

```bash
# Enable the dialog feature (one-time setup)
cursor-studio dialog enable

# This will:
# - Build the daemon if needed
# - Start the daemon
# - Install Cursor rules for AI agents
```

### Manual Build

```bash
cd tools/cursor-dialog-daemon
cargo build --release

# Start daemon
./target/release/cursor-dialog-daemon

# In another terminal, test:
./target/release/cursor-dialog-cli ping
```

## Usage

### From cursor-studio

```bash
# Check status
cursor-studio dialog status

# Start/stop daemon
cursor-studio dialog start
cursor-studio dialog stop

# Enable/disable feature
cursor-studio dialog enable   # Installs rules + starts daemon
cursor-studio dialog disable  # Removes rules + stops daemon

# Test
cursor-studio dialog test
```

### CLI Examples

```bash
# Multiple choice
cursor-dialog-cli -t 60 choice \
  --title "Select Approach" \
  --prompt "How should I implement this?" \
  --options '[{"value":"fast","label":"⚡ Fast"},{"value":"safe","label":"🔒 Safe"}]'

# Text input
cursor-dialog-cli -t 90 text \
  --title "Project Name" \
  --prompt "Enter name:" \
  --placeholder "my-project"

# Confirmation
cursor-dialog-cli -t 30 confirm \
  --title "Proceed?" \
  --prompt "Delete 15 files?" \
  --yes "Delete" --no "Cancel"

# Slider
cursor-dialog-cli -t 45 slider \
  --title "Detail Level" \
  --prompt "Summary detail (1-10):" \
  --min 1 --max 10 --default 5

# Toast notifications
cursor-dialog-cli toast -m "Build complete!" -l success -d 3000
cursor-dialog-cli toast -m "Warning: low memory" -l warning -d 5000
cursor-dialog-cli toast -m "Error occurred" -l error -d 8000
```

### Response Format

All dialogs return JSON:

```json
{
  "id": "uuid",
  "selection": "value",
  "comment": "Optional user context",
  "cancelled": false,
  "timestamp": 1234567890
}
```

## Architecture

```
┌─────────────────┐     D-Bus IPC      ┌──────────────────┐
│ cursor-dialog-  │ ←───────────────→  │ cursor-dialog-   │
│ cli             │                     │ daemon           │
└─────────────────┘                     └────────┬─────────┘
                                                 │
       AI Agent uses CLI ───────────────────────►│
                                                 │
                                        ┌────────▼─────────┐
                                        │   egui/eframe    │
                                        │   GUI Window     │
                                        └──────────────────┘
                                                 │
       User interacts with dialog ◄──────────────┘
```

- **D-Bus Service**: `sh.cursor.studio.Dialog`
- **Object Path**: `/sh/cursor/studio/Dialog`
- **Interface**: `sh.cursor.studio.Dialog1`

## Build Profiles

```bash
# Fast builds (default release)
cargo build --release
# ~2.5 min clean build, 15MB binary

# Maximum optimization (for final release)
cargo build --profile release-max
# ~3.5 min clean build, smaller binary
```

## D-Bus Methods

| Method | Description |
|--------|-------------|
| `ShowChoice` | Multiple choice dialog |
| `ShowTextInput` | Text input dialog |
| `ShowConfirmation` | Yes/No dialog |
| `ShowSlider` | Numeric slider |
| `ShowProgress` | Progress indicator |
| `ShowFilePicker` | File/folder selection |
| `ShowToast` | Non-blocking notification |
| `Ping` | Health check |
| `GetInfo` | Version and capabilities |

## Cursor Rules

When enabled, the daemon installs rules at `~/.cursor/rules/interactive-dialogs.mdc` that instruct AI agents how to use the dialog system.

## Development

```bash
# Run with debug logging
RUST_LOG=debug cargo run

# Run tests
cargo test

# Check lints
cargo clippy
```

## License

MIT
