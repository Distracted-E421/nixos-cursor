#!/usr/bin/env nu
# Validate Public Branch - Checks for leaked private content
# Usage: nu scripts/validate-public-branch.nu [branch]
#
# Example: nu scripts/validate-public-branch.nu pre-release

def header [title: string] {
    print $"(ansi blue)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━(ansi reset)"
    print $"(ansi blue)  ($title)(ansi reset)"
    print $"(ansi blue)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━(ansi reset)"
}

def main [
    branch: string = "pre-release"  # Branch to validate
] {
    header $"Validate Public Branch: ($branch)"
    print ""
    
    # Check if branch exists
    let branch_exists = (git show-ref --verify --quiet $"refs/heads/($branch)" | complete).exit_code == 0
    if not $branch_exists {
        print $"(ansi red)❌ Error: Branch ($branch) doesn't exist(ansi reset)"
        exit 1
    }
    
    # Store current branch
    let current_branch = (git rev-parse --abbrev-ref HEAD | str trim)
    
    # Switch to branch if needed
    if $current_branch != $branch {
        git checkout $branch --quiet
        print $"(ansi green)✓ Switched to ($branch)(ansi reset)"
    }
    
    mut issues = 0
    
    # Check 1: Private .cursor/ files
    print $"(ansi blue)🔍 Checking for private .cursor/ files...(ansi reset)"
    
    let private_cursor_files = [
        ".cursor/chat-history/"
        ".cursor/maxim.json"
        ".cursor/gorky.json"
        ".cursor/docs/CURSOR_HOOKS_INTEGRATION_COMPLETE.md"
        ".cursor/docs/CURSOR_RULES_INTEGRATION_SUCCESS.md"
    ]
    
    for file in $private_cursor_files {
        if ($file | path exists) {
            print $"(ansi red)  ❌ Found private file: ($file)(ansi reset)"
            $issues += 1
        }
    }
    
    if $issues == 0 {
        print $"(ansi green)  ✓ No private .cursor/ files found(ansi reset)"
    }
    
    # Check 2: Personal email addresses
    print $"(ansi blue)🔍 Checking for personal email addresses...(ansi reset)"
    
    let email_check = (do {
        git grep -l "distracted\\.e421@gmail\\.com" -- . ':!LICENSE' ':!BRANCHING_STRATEGY.md' ':!scripts/' ':!.cursor/'
    } | complete)
    
    if $email_check.exit_code == 0 and ($email_check.stdout | str trim) != "" {
        print $"(ansi red)  ❌ Found personal email in tracked files(ansi reset)"
        $issues += 1
    } else {
        print $"(ansi green)  ✓ No personal email leaks(ansi reset)"
    }
    
    # Check 3: Absolute paths
    print $"(ansi blue)🔍 Checking for absolute paths...(ansi reset)"
    
    let path_check = (do {
        git grep -l "/home/e421/" -- . ':!.git' ':!scripts/' ':!.cursor/'
    } | complete)
    
    if $path_check.exit_code == 0 and ($path_check.stdout | str trim) != "" {
        print $"(ansi red)  ❌ Found absolute paths (/home/e421/)(ansi reset)"
        $issues += 1
    } else {
        print $"(ansi green)  ✓ No absolute paths found(ansi reset)"
    }
    
    # Check 4: API keys/tokens
    print $"(ansi blue)🔍 Checking for API keys and secrets...(ansi reset)"
    
    let secret_check = (do {
        git grep -iE "(api[_-]?key|github[_-]?token|secret|password)\\s*=\\s*['\"][^'\"]{20,}['\"]" -- . ':!.git' ':!scripts/' ':!.cursor/' ':!BRANCHING_STRATEGY.md'
    } | complete)
    
    if $secret_check.exit_code == 0 and ($secret_check.stdout | str trim) != "" {
        print $"(ansi red)  ❌ Found potential API keys or secrets(ansi reset)"
        $issues += 1
    } else {
        print $"(ansi green)  ✓ No API keys or secrets found(ansi reset)"
    }
    
    # Check 5: TODO/FIXME in critical files
    print $"(ansi blue)🔍 Checking for unresolved TODOs in critical files...(ansi reset)"
    
    let todo_check = (do {
        git grep -l -E "(TODO|FIXME|HACK)" -- '*.nix' 'flake.nix' 'cursor/default.nix'
    } | complete)
    
    if $todo_check.exit_code == 0 and ($todo_check.stdout | str trim) != "" {
        print $"(ansi yellow)  ⚠️  Found TODOs in critical files:(ansi reset)"
        $todo_check.stdout | lines | each { |f| print $"(ansi yellow)    - ($f)(ansi reset)" }
        print $"(ansi yellow)  (Review if these are acceptable for release)(ansi reset)"
    }
    
    # Check 6: Nix flake validation
    print $"(ansi blue)🔍 Running nix flake check...(ansi reset)"
    
    let flake_check = (nix flake check --no-build 2>&1 | complete)
    if ($flake_check.stdout + $flake_check.stderr | str downcase | str contains "error") {
        print $"(ansi red)  ❌ Nix flake check failed(ansi reset)"
        $issues += 1
    } else {
        print $"(ansi green)  ✓ Nix flake check passed(ansi reset)"
    }
    
    # Check 7: Documentation completeness
    print $"(ansi blue)🔍 Checking documentation completeness...(ansi reset)"
    
    let required_docs = [
        "README.md"
        "LICENSE"
        "BRANCHING_STRATEGY.md"
        "cursor/README.md"
    ]
    
    for doc in $required_docs {
        if not ($doc | path exists) {
            print $"(ansi red)  ❌ Missing: ($doc)(ansi reset)"
            $issues += 1
        }
    }
    
    if $issues == 0 {
        print $"(ansi green)  ✓ All required documentation present(ansi reset)"
    }
    
    # Check 8: File size check (large files)
    print $"(ansi blue)🔍 Checking for large files (>1MB)...(ansi reset)"
    
    let large_files = (glob **/* 
        | where { |f| 
            ($f | path type) == "file" 
            and not ($f | str starts-with ".git/")
            and not ($f | str starts-with "result/")
            and not ($f | str contains ".cursor/chat-history/")
            and ((ls -l $f | get 0.size) > 1MB)
        })
    
    if ($large_files | length) > 0 {
        print $"(ansi yellow)  ⚠️  Found large files (>1MB):(ansi reset)"
        for file in $large_files {
            let size = (ls -l $file | get 0.size)
            print $"(ansi yellow)    - ($file) \(($size)\)(ansi reset)"
        }
        print $"(ansi yellow)  (Consider if these should be in the repository)(ansi reset)"
    }
    
    # Summary
    print ""
    print $"(ansi blue)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━(ansi reset)"
    
    if $issues == 0 {
        print $"(ansi green)✅ Validation Passed(ansi reset)"
        print $"(ansi green)Branch ($branch) is ready for public release(ansi reset)"
    } else {
        print $"(ansi red)❌ Validation Failed(ansi reset)"
        print $"(ansi red)Found ($issues) issue\(s\) that must be fixed(ansi reset)"
    }
    
    print $"(ansi blue)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━(ansi reset)"
    print ""
    
    # Return to original branch
    if $current_branch != $branch {
        git checkout $current_branch --quiet
    }
    
    if $issues > 0 {
        exit 1
    }
}
