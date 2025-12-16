#!/usr/bin/env nu
# Cursor Context Monitor - Real-time monitoring of data flow to/from agent
#
# Usage:
#   nu cursor-context-monitor.nu              # One-time snapshot
#   nu cursor-context-monitor.nu --watch      # Continuous monitoring
#   nu cursor-context-monitor.nu --export     # Export to JSON
#
# This monitors what context is being sent to the AI agent in Cursor.

const CURSOR_DB = $"($env.HOME)/.config/Cursor/User/globalStorage/state.vscdb"
const WORKSPACE_DIR = $"($env.HOME)/.config/Cursor/User/workspaceStorage"

# Color codes for output
def color [color: string, text: string] {
    match $color {
        "green" => $"(ansi green)($text)(ansi reset)"
        "red" => $"(ansi red)($text)(ansi reset)"
        "yellow" => $"(ansi yellow)($text)(ansi reset)"
        "blue" => $"(ansi blue)($text)(ansi reset)"
        "cyan" => $"(ansi cyan)($text)(ansi reset)"
        "magenta" => $"(ansi magenta)($text)(ansi reset)"
        "bold" => $"(ansi attr_bold)($text)(ansi reset)"
        _ => $text
    }
}

# Get database stats
def get-db-stats [] {
    let bubble_count = (sqlite3 $CURSOR_DB "SELECT COUNT(*) FROM cursorDiskKV WHERE key LIKE 'bubbleId:%'" | into int)
    let checkpoint_count = (sqlite3 $CURSOR_DB "SELECT COUNT(*) FROM cursorDiskKV WHERE key LIKE 'checkpointId:%'" | into int)
    let diff_count = (sqlite3 $CURSOR_DB "SELECT COUNT(*) FROM cursorDiskKV WHERE key LIKE 'codeBlockDiff:%'" | into int)
    let composer_count = (sqlite3 $CURSOR_DB "SELECT COUNT(*) FROM cursorDiskKV WHERE key LIKE 'composerData:%'" | into int)
    
    {
        messages: $bubble_count
        checkpoints: $checkpoint_count
        code_diffs: $diff_count
        conversations: $composer_count
    }
}

# Get latest bubble (message) info
def get-latest-bubble [] {
    let result = (sqlite3 $CURSOR_DB "
        SELECT key, value FROM cursorDiskKV 
        WHERE key LIKE 'bubbleId:%' 
        ORDER BY rowid DESC LIMIT 1
    " | lines | first | split column "|" key value)
    
    if ($result | is-empty) {
        return null
    }
    
    let key = ($result | first | get key)
    let value = ($result | first | get value | from json)
    
    {
        key: $key
        type: (if ($value | get -i type | default 0) == 1 { "user" } else { "assistant" })
        is_agentic: ($value | get -i isAgentic | default false)
        model: ($value | get -i modelInfo.modelName | default "unknown")
        has_thinking: (($value | get -i allThinkingBlocks | default [] | length) > 0)
        has_tool_calls: (($value | get -i toolResults | default [] | length) > 0)
        has_code_changes: (($value | get -i assistantSuggestedDiffs | default [] | length) > 0)
        attached_files: ($value | get -i attachedCodeChunks | default [] | length)
        rules_count: ($value | get -i cursorRules | default [] | length)
        docs_refs: ($value | get -i docsReferences | default [] | length)
        web_refs: ($value | get -i webReferences | default [] | length)
    }
}

# Get MCP server status
def get-mcp-status [] {
    let servers = (sqlite3 $CURSOR_DB "SELECT value FROM ItemTable WHERE key = 'mcpService.knownServerIds'" | from json | default [])
    $servers
}

# Get workspace conversations
def get-workspace-conversations [workspace_hash: string] {
    let ws_db = $"($WORKSPACE_DIR)/($workspace_hash)/state.vscdb"
    
    if not ($ws_db | path exists) {
        return []
    }
    
    let result = (sqlite3 $ws_db "SELECT value FROM ItemTable WHERE key = 'composer.composerData'" | default "")
    
    if ($result | is-empty) {
        return []
    }
    
    let data = ($result | from json)
    let composers = ($data | get -i allComposers | default [])
    
    $composers | where { |c| ($c | get -i type | default "") == "head" } | each { |c|
        {
            id: ($c | get -i composerId | default "")
            name: ($c | get -i name | default "Untitled")
            context_pct: ($c | get -i contextUsagePercent | default 0)
            lines_added: ($c | get -i totalLinesAdded | default 0)
            lines_removed: ($c | get -i totalLinesRemoved | default 0)
            is_agentic: ($c | get -i isAgentic | default false)
        }
    }
}

# Display dashboard
def display-dashboard [] {
    print (color "bold" "╔════════════════════════════════════════════════════════════════╗")
    print (color "bold" "║            🔍 CURSOR CONTEXT MONITOR                           ║")
    print (color "bold" "╚════════════════════════════════════════════════════════════════╝")
    print ""
    
    # Database stats
    let stats = (get-db-stats)
    print (color "cyan" "📊 Database Statistics")
    print $"   Messages:      (color 'green' ($stats.messages | into string))"
    print $"   Checkpoints:   (color 'yellow' ($stats.checkpoints | into string))"
    print $"   Code Diffs:    (color 'magenta' ($stats.code_diffs | into string))"
    print $"   Conversations: (color 'blue' ($stats.conversations | into string))"
    print ""
    
    # MCP Servers
    let mcp = (get-mcp-status)
    print (color "cyan" "🔧 MCP Servers")
    for server in $mcp {
        let name = ($server | str replace "user-" "")
        print $"   ✅ ($name)"
    }
    print ""
    
    # Latest message
    let latest = (get-latest-bubble)
    if ($latest != null) {
        print (color "cyan" "💬 Latest Message")
        let type_color = (if $latest.type == "user" { "yellow" } else { "green" })
        print $"   Type:          (color $type_color $latest.type)"
        print $"   Model:         ($latest.model)"
        print $"   Agentic:       (if $latest.is_agentic { (color 'green' '✓') } else { '✗' })"
        print $"   Thinking:      (if $latest.has_thinking { (color 'green' '✓') } else { '✗' })"
        print $"   Tool Calls:    (if $latest.has_tool_calls { (color 'green' '✓') } else { '✗' })"
        print $"   Code Changes:  (if $latest.has_code_changes { (color 'green' '✓') } else { '✗' })"
        print $"   Files:         ($latest.attached_files)"
        print $"   Rules:         ($latest.rules_count)"
        print $"   @docs:         ($latest.docs_refs)"
        print $"   @web:          ($latest.web_refs)"
    }
    print ""
    
    # Workspace conversations
    let workspaces = (ls $WORKSPACE_DIR | get name | each { |p| $p | path basename })
    print (color "cyan" "📁 Active Workspaces")
    for ws in $workspaces {
        let convs = (get-workspace-conversations $ws)
        if (($convs | length) > 0) {
            print $"   (color 'yellow' $ws)"
            for conv in ($convs | first 3) {
                let ctx_bar = (generate-bar $conv.context_pct)
                print $"      • ($conv.name | str substring 0..40)"
                print $"        Context: ($ctx_bar) ($conv.context_pct | math round -p 1)%"
            }
        }
    }
}

# Generate ASCII progress bar
def generate-bar [pct: float] {
    let filled = (($pct / 5) | math round | into int)
    let empty = (20 - $filled)
    let bar_filled = ("█" | str expand --times $filled)
    let bar_empty = ("░" | str expand --times $empty)
    
    if $pct > 80 {
        color "red" $"($bar_filled)($bar_empty)"
    } else if $pct > 50 {
        color "yellow" $"($bar_filled)($bar_empty)"
    } else {
        color "green" $"($bar_filled)($bar_empty)"
    }
}

# Watch mode - continuous monitoring
def watch-mode [] {
    loop {
        # Clear screen
        print -n (ansi cls)
        
        display-dashboard
        
        print ""
        print (color "cyan" "⏱️  Refreshing every 2 seconds... Press Ctrl+C to stop")
        
        sleep 2sec
    }
}

# Export to JSON
def export-data [] {
    let stats = (get-db-stats)
    let mcp = (get-mcp-status)
    let latest = (get-latest-bubble)
    
    let workspaces = (ls $WORKSPACE_DIR | get name | each { |p| 
        let ws = ($p | path basename)
        {
            hash: $ws
            conversations: (get-workspace-conversations $ws)
        }
    })
    
    {
        exported_at: (date now | format date "%Y-%m-%dT%H:%M:%S")
        database: $stats
        mcp_servers: $mcp
        latest_message: $latest
        workspaces: $workspaces
    } | to json
}

# Main entry point
def main [
    --watch (-w): bool  # Continuous monitoring mode
    --export (-e): bool # Export to JSON
] {
    if $export {
        export-data
    } else if $watch {
        watch-mode
    } else {
        display-dashboard
    }
}
