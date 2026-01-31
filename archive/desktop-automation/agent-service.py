#!/usr/bin/env python3
"""
Desktop Automation Service - Direct LLM Integration (NO MCP)

This service exposes desktop automation capabilities via:
1. DBus interface for local IPC
2. Unix socket for fast communication
3. Direct function calls from Python

NOT MCP because:
- MCP is slow (JSON-RPC overhead)
- MCP is vulnerable (supply chain attacks on npm packages)
- MCP wastes tokens (verbose tool schemas)
- We control both ends, so we can be more efficient

Instead, we:
- Define tools directly in system prompt
- Use structured output parsing
- Call this service via subprocess or DBus
"""

import json
import subprocess
import shutil
from pathlib import Path
from typing import Optional, Dict, Any, List
from dataclasses import dataclass, asdict
import time

# ============================================================================
# TOOL DEFINITIONS (for LLM system prompt)
# ============================================================================

TOOL_DEFINITIONS = """
## Desktop Automation Tools

You have access to desktop automation. Call tools using this format:
<tool name="TOOL_NAME">{"param": "value"}</tool>

Available tools:

### Window Management
- `windows_list` - List all open windows
- `windows_search` - Search by name: {"pattern": "Firefox"}
- `windows_focus` - Focus window: {"window_id": "xxx"} or {"pattern": "name"}
- `windows_move` - Move window: {"window_id": "xxx", "x": 100, "y": 100}
- `windows_close` - Close window: {"window_id": "xxx"}

### Input Simulation
- `mouse_move` - Move cursor: {"x": 500, "y": 300} (absolute pixels)
- `mouse_click` - Click: {"button": "left"} (left/right/middle)
- `type_text` - Type: {"text": "Hello world"}
- `press_key` - Keyboard: {"keys": "ctrl+c"} or {"keys": "Return"}

### Screenshots
- `screenshot_monitor` - Capture current monitor
- `screenshot_window` - Capture active window
- `screenshot_full` - Capture all monitors

### System
- `desktop_switch` - Switch virtual desktop: {"desktop_id": "xxx"}
- `desktop_create` - Create new desktop: {"name": "AI Workspace"}
- `system_status` - Get current system state

Example:
<tool name="windows_search">{"pattern": "Cursor"}</tool>
<tool name="mouse_move">{"x": 500, "y": 300}</tool>
<tool name="mouse_click">{"button": "left"}</tool>
"""

# ============================================================================
# CORE IMPLEMENTATION
# ============================================================================

@dataclass
class ToolResult:
    success: bool
    data: Optional[Dict[str, Any]] = None
    error: Optional[str] = None

def run_kdotool(args: List[str]) -> str:
    """Run kdotool command and return output."""
    result = subprocess.run(
        ["kdotool"] + args,
        capture_output=True,
        text=True
    )
    return result.stdout.strip()

def run_dotool(commands: str) -> bool:
    """Send commands to dotool."""
    try:
        result = subprocess.run(
            ["dotool"],
            input=commands,
            capture_output=True,
            text=True
        )
        return result.returncode == 0
    except Exception as e:
        print(f"dotool error: {e}")
        return False

def run_qdbus(service: str, path: str, method: str, *args) -> str:
    """Run qdbus command."""
    cmd = ["qdbus", service, path, method] + list(args)
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout.strip()

# ============================================================================
# TOOL IMPLEMENTATIONS
# ============================================================================

def windows_list() -> ToolResult:
    """List all windows."""
    try:
        ids = run_kdotool(["search", "."]).split("\n")
        windows = []
        for wid in ids:
            if not wid:
                continue
            name = run_kdotool(["getwindowname", wid])
            classname = run_kdotool(["getwindowclassname", wid])
            geom_raw = run_kdotool(["getwindowgeometry", wid])
            
            geom = {}
            for line in geom_raw.split("\n"):
                if ":" in line:
                    key, val = line.split(":", 1)
                    try:
                        geom[key.strip().lower()] = int(val.strip())
                    except ValueError:
                        geom[key.strip().lower()] = val.strip()
            
            windows.append({
                "id": wid,
                "name": name,
                "class": classname,
                **geom
            })
        return ToolResult(success=True, data={"windows": windows})
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def windows_search(pattern: str) -> ToolResult:
    """Search for windows by name pattern."""
    try:
        ids = run_kdotool(["search", "--name", pattern]).split("\n")
        ids = [i for i in ids if i.strip()]
        return ToolResult(success=True, data={"window_ids": ids, "count": len(ids)})
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def windows_focus(window_id: Optional[str] = None, pattern: Optional[str] = None) -> ToolResult:
    """Focus a window by ID or pattern."""
    try:
        if pattern:
            ids = run_kdotool(["search", "--name", pattern]).split("\n")
            ids = [i for i in ids if i.strip()]
            if not ids:
                return ToolResult(success=False, error=f"No window matching '{pattern}'")
            window_id = ids[0]
        
        if not window_id:
            return ToolResult(success=False, error="No window_id or pattern provided")
        
        run_kdotool(["windowactivate", window_id])
        return ToolResult(success=True, data={"focused": window_id})
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def windows_move(window_id: str, x: int, y: int) -> ToolResult:
    """Move a window."""
    try:
        run_kdotool(["windowmove", window_id, str(x), str(y)])
        return ToolResult(success=True, data={"window_id": window_id, "x": x, "y": y})
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def windows_close(window_id: str) -> ToolResult:
    """Close a window."""
    try:
        run_kdotool(["windowclose", window_id])
        return ToolResult(success=True, data={"closed": window_id})
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def mouse_move(x: int, y: int) -> ToolResult:
    """Move mouse to absolute position."""
    try:
        # dotool uses percentage, so we need screen dimensions
        # For now, assume 1920x1080 and convert
        # TODO: Query actual screen size
        pct_x = x / 1920
        pct_y = y / 1080
        run_dotool(f"mouseto {pct_x} {pct_y}")
        return ToolResult(success=True, data={"x": x, "y": y})
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def mouse_click(button: str = "left") -> ToolResult:
    """Click mouse button."""
    try:
        run_dotool(f"click {button}")
        return ToolResult(success=True, data={"button": button})
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def type_text(text: str) -> ToolResult:
    """Type text."""
    try:
        run_dotool(f"type {text}")
        return ToolResult(success=True, data={"typed": len(text)})
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def press_key(keys: str) -> ToolResult:
    """Press key combination."""
    try:
        run_dotool(f"key {keys}")
        return ToolResult(success=True, data={"keys": keys})
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def screenshot_monitor(output: Optional[str] = None) -> ToolResult:
    """Take screenshot of current monitor."""
    try:
        if not output:
            ts = time.strftime("%Y%m%d-%H%M%S")
            output = str(Path.home() / "Pictures" / f"screenshot-{ts}.png")
        
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["spectacle", "-b", "-m", "-n", "-o", output], check=True)
        time.sleep(0.5)
        
        if Path(output).exists():
            return ToolResult(success=True, data={"path": output})
        return ToolResult(success=False, error="Screenshot file not created")
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def screenshot_window(output: Optional[str] = None) -> ToolResult:
    """Take screenshot of active window."""
    try:
        if not output:
            ts = time.strftime("%Y%m%d-%H%M%S")
            output = str(Path.home() / "Pictures" / f"window-{ts}.png")
        
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["spectacle", "-b", "-a", "-n", "-o", output], check=True)
        time.sleep(0.5)
        
        if Path(output).exists():
            return ToolResult(success=True, data={"path": output})
        return ToolResult(success=False, error="Screenshot file not created")
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def screenshot_full(output: Optional[str] = None) -> ToolResult:
    """Take screenshot of full desktop."""
    try:
        if not output:
            ts = time.strftime("%Y%m%d-%H%M%S")
            output = str(Path.home() / "Pictures" / f"full-{ts}.png")
        
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["spectacle", "-b", "-f", "-n", "-o", output], check=True)
        time.sleep(0.5)
        
        if Path(output).exists():
            return ToolResult(success=True, data={"path": output})
        return ToolResult(success=False, error="Screenshot file not created")
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def desktop_switch(desktop_id: str) -> ToolResult:
    """Switch to virtual desktop."""
    try:
        run_qdbus(
            "org.kde.KWin",
            "/VirtualDesktopManager",
            "org.kde.KWin.VirtualDesktopManager.setCurrent",
            desktop_id
        )
        return ToolResult(success=True, data={"desktop_id": desktop_id})
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def desktop_create(name: str = "AI Workspace") -> ToolResult:
    """Create new virtual desktop."""
    try:
        count = int(run_qdbus(
            "org.kde.KWin",
            "/VirtualDesktopManager",
            "org.kde.KWin.VirtualDesktopManager.count"
        ))
        run_qdbus(
            "org.kde.KWin",
            "/VirtualDesktopManager",
            "org.kde.KWin.VirtualDesktopManager.createDesktop",
            str(count),
            name
        )
        return ToolResult(success=True, data={"name": name, "position": count})
    except Exception as e:
        return ToolResult(success=False, error=str(e))

def system_status() -> ToolResult:
    """Get current system status."""
    try:
        # Active window
        active_id = run_kdotool(["getactivewindow"])
        active_name = run_kdotool(["getwindowname", active_id]) if active_id else None
        
        # Current desktop
        desktop_id = run_qdbus(
            "org.kde.KWin",
            "/VirtualDesktopManager",
            "org.kde.KWin.VirtualDesktopManager.current"
        )
        
        # Input tools
        dotool_available = shutil.which("dotool") is not None
        kdotool_available = shutil.which("kdotool") is not None
        
        return ToolResult(success=True, data={
            "active_window": {"id": active_id, "name": active_name},
            "desktop_id": desktop_id,
            "tools": {
                "dotool": dotool_available,
                "kdotool": kdotool_available
            }
        })
    except Exception as e:
        return ToolResult(success=False, error=str(e))

# ============================================================================
# TOOL DISPATCH
# ============================================================================

TOOLS = {
    "windows_list": lambda p: windows_list(),
    "windows_search": lambda p: windows_search(p["pattern"]),
    "windows_focus": lambda p: windows_focus(p.get("window_id"), p.get("pattern")),
    "windows_move": lambda p: windows_move(p["window_id"], p["x"], p["y"]),
    "windows_close": lambda p: windows_close(p["window_id"]),
    "mouse_move": lambda p: mouse_move(p["x"], p["y"]),
    "mouse_click": lambda p: mouse_click(p.get("button", "left")),
    "type_text": lambda p: type_text(p["text"]),
    "press_key": lambda p: press_key(p["keys"]),
    "screenshot_monitor": lambda p: screenshot_monitor(p.get("output")),
    "screenshot_window": lambda p: screenshot_window(p.get("output")),
    "screenshot_full": lambda p: screenshot_full(p.get("output")),
    "desktop_switch": lambda p: desktop_switch(p["desktop_id"]),
    "desktop_create": lambda p: desktop_create(p.get("name", "AI Workspace")),
    "system_status": lambda p: system_status(),
}

def execute_tool(name: str, params: Dict[str, Any]) -> Dict[str, Any]:
    """Execute a tool by name with parameters."""
    if name not in TOOLS:
        return asdict(ToolResult(success=False, error=f"Unknown tool: {name}"))
    
    try:
        result = TOOLS[name](params)
        return asdict(result)
    except Exception as e:
        return asdict(ToolResult(success=False, error=str(e)))

def parse_and_execute(text: str) -> List[Dict[str, Any]]:
    """Parse tool calls from LLM output and execute them."""
    import re
    
    pattern = r'<tool name="([^"]+)">({.*?})</tool>'
    matches = re.findall(pattern, text, re.DOTALL)
    
    results = []
    for name, params_str in matches:
        try:
            params = json.loads(params_str)
        except json.JSONDecodeError:
            params = {}
        
        result = execute_tool(name, params)
        results.append({"tool": name, "params": params, "result": result})
    
    return results

# ============================================================================
# CLI INTERFACE
# ============================================================================

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Desktop Automation Service")
        print("==========================")
        print()
        print("Usage:")
        print("  agent-service.py <tool_name> [json_params]")
        print("  agent-service.py --parse '<tool ...>...</tool>'")
        print("  agent-service.py --prompt  # Print tool definitions for LLM")
        print()
        print("Available tools:", ", ".join(TOOLS.keys()))
        sys.exit(0)
    
    if sys.argv[1] == "--prompt":
        print(TOOL_DEFINITIONS)
        sys.exit(0)
    
    if sys.argv[1] == "--parse":
        text = sys.argv[2] if len(sys.argv) > 2 else sys.stdin.read()
        results = parse_and_execute(text)
        print(json.dumps(results, indent=2))
        sys.exit(0)
    
    tool_name = sys.argv[1]
    params = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    
    result = execute_tool(tool_name, params)
    print(json.dumps(result, indent=2))

