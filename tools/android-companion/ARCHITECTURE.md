# Continuum Studio - Android Companion - Architecture Plan

## Project Naming

**Proposed Names** (Continuum Logic based):
- **Continuum Studio** - Simple, clear purpose
- **Continuum Studio** - Ties to workflow/AI assistance
- **Continuum Bridge** - Connects mobile to desktop
- **CL Companion** - Direct LLC reference

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    DESKTOP (Obsidian)                           │
├─────────────────────────────────────────────────────────────────┤
│  cursor-dialog-daemon                                           │
│  ├── D-Bus interface (local GUI)                               │
│  ├── WebSocket server (remote)                                 │
│  └── Photo receiver endpoint                                    │
│                                                                 │
│  continuum-studio (egui app)                                       │
│  └── Chat management, settings, etc.                           │
└──────────────────────┬──────────────────────────────────────────┘
                       │ Tailscale VPN
                       │ WebSocket/HTTP
┌──────────────────────▼──────────────────────────────────────────┐
│                    MOBILE (Android)                             │
├─────────────────────────────────────────────────────────────────┤
│  Continuum Studio (Kotlin + Jetpack Compose)                    │
│  ├── Dialog answering UI                                        │
│  │   ├── Choice dialogs                                        │
│  │   ├── Text input                                            │
│  │   ├── Confirmation                                          │
│  │   └── Comments (with voice-to-text!)                        │
│  │                                                              │
│  ├── Photo capture & send                                       │
│  │   └── Camera integration → upload to daemon                 │
│  │                                                              │
│  ├── Chat browser                                               │
│  │   └── View/search past conversations                        │
│  │                                                              │
│  ├── Push notifications (Firebase/local)                        │
│  │   └── Native Android notifications                          │
│  │                                                              │
│  └── Settings & connection management                           │
│       └── Tailscale IP, hold mode, etc.                        │
└─────────────────────────────────────────────────────────────────┘
```

## Technology Stack

### Android App
- **Language**: Kotlin
- **UI**: Jetpack Compose (declarative, modern)
- **Architecture**: MVVM with Repository pattern
- **Networking**: Ktor or OkHttp for WebSocket
- **Camera**: CameraX library
- **Notifications**: WorkManager + FCM or local
- **Storage**: Room for caching, DataStore for prefs

### Desktop Changes Needed
- Add photo upload endpoint to dialog-daemon
- Add new dialog type: `PhotoRequest`
- WebSocket message for triggering photo capture

### Build System
- **Primary**: Gradle (standard Android toolchain)
- **Nix Integration**: Nix flake for reproducible builds
  - Android SDK via nixpkgs
  - Kotlin compiler
  - Gradle wrapper

## New Dialog Type: PhotoRequest

```json
{
  "type": "PhotoRequest",
  "title": "Show me the error",
  "prompt": "Please take a photo of the console output",
  "allow_gallery": true,
  "max_size_kb": 1024,
  "timeout_ms": 120000
}
```

Response:
```json
{
  "selection": "photo_captured",
  "photo_data": "base64...",
  "mime_type": "image/jpeg"
}
```

## File Structure

```
nixos-cursor/tools/
├── android-companion/
│   ├── ARCHITECTURE.md          # This file
│   ├── flake.nix               # Nix devShell with Android SDK
│   ├── android-harness          # CLI harness for AI automation
│   ├── app/
│   │   ├── build.gradle.kts
│   │   └── src/
│   │       └── main/
│   │           ├── kotlin/
│   │           │   └── com/continuumlogic/remote/
│   │           │       ├── MainActivity.kt
│   │           │       ├── ui/
│   │           │       │   ├── dialog/DialogScreen.kt
│   │           │       │   ├── camera/CameraScreen.kt
│   │           │       │   └── theme/Theme.kt
│   │           │       ├── network/
│   │           │       │   └── WebSocketClient.kt
│   │           │       └── viewmodel/
│   │           │           └── DialogViewModel.kt
│   │           ├── res/
│   │           └── AndroidManifest.xml
│   ├── gradle/
│   └── settings.gradle.kts
```

## Android Harness (for AI automation)

Similar to godot-harness, but for Android development:

```bash
# Build the app
./android-harness build

# Install to connected device
./android-harness install

# Take screenshot of device
./android-harness screenshot

# Get device info
./android-harness info

# Run instrumented tests
./android-harness test

# View logcat
./android-harness logs

# Push file to device
./android-harness push <local> <remote>
```

## Nix-on-Droid Integration

Nix-on-Droid provides a Nix environment ON the Android device:
- NOT for building the app
- FOR running CLI tools on the phone
- Could run `cursor-dialog-cli` directly if built for ARM64

Potential use case:
- Run local scripts on phone
- Bridge to daemon without the app

## Development Phases

### Phase 1: Skeleton (Current)
- [ ] Create flake.nix with Android SDK
- [ ] Basic Compose project structure
- [ ] Connect to existing WebSocket server

### Phase 2: Core Features
- [ ] Dialog answering UI
- [ ] Push notifications
- [ ] Comment field with voice input

### Phase 3: Enhanced Features
- [ ] Photo capture & send
- [ ] Chat browser
- [ ] Settings management

### Phase 4: Polish
- [ ] Offline queue
- [ ] Connection status indicator
- [ ] Material You theming

## Research: Android Studio Automation

### JetBrains MCP Server (Investigated 2026-01-28)

JetBrains IDEs (Android Studio 2025.2+) have a built-in **MCP Server** for programmatic control.

**Discovery**: Settings → Tools → MCP Server

**MCP Tools Available**:
- `create_new_file` - Create project files
- `replace_text_in_file` - Edit code
- `execute_terminal_command` - Run gradle/shell
- `execute_run_configuration` - Run builds
- `get_file_problems` - Get IDE errors/warnings
- `rename_refactoring` - Refactor code
- `find_files_by_glob` - Search files

**Why NOT to use MCP directly**:
- Token-heavy protocol (lots of JSON overhead)
- Slow compared to direct IPC
- Limited compared to IDE internals

**Future Investigation**:
The MCP server is a wrapper around IntelliJ Platform APIs. For a proper harness:

1. **Investigate underlying mechanism**:
   - IntelliJ Platform Plugin SDK
   - IDE Action system (`com.intellij.openapi.actionSystem`)
   - Application Services
   - Project Services

2. **Potential faster approaches**:
   - **IDE Scripting Console**: Groovy/Kotlin scripts via `Tools → IDE Scripting Console`
   - **HTTP REST API**: Some IDEs have undocumented REST endpoints
   - **Plugin with IPC**: Build a thin plugin that exposes a Unix socket/named pipe
   - **JNI Bridge**: Direct Java method invocation from Rust

3. **Resources**:
   - [IntelliJ Platform SDK](https://plugins.jetbrains.com/docs/intellij/welcome.html)
   - [MCP Plugin Source](https://plugins.jetbrains.com/plugin/26071-mcp-server)
   - IDE internal actions: `Help → Find Action → (enable "Include non-menu actions")`

### Current Harness Capabilities

The `android-studio-harness` currently supports:
- ✅ Focus window (kdotool on Wayland)
- ✅ Screenshot (spectacle)
- ✅ Keyboard input (ydotool)
- ⚠️ Click by coordinates (unreliable on Wayland)
- ❌ Direct IDE control (needs MCP or plugin)

---

## Resolved Questions

1. **App Name**: **Continuum Studio** ✓
2. **Notifications**: TBD
3. **Voice Input**: TBD  
4. **Chat Browser**: TBD
