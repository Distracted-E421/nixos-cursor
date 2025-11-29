#!/usr/bin/env nu
# Release to Main - Automates pre-release → main transition
# Usage: nu scripts/release-to-main.nu v2.1.20

# Colors
def green [msg: string] { $"(ansi green)($msg)(ansi reset)" }
def red [msg: string] { $"(ansi red)($msg)(ansi reset)" }
def yellow [msg: string] { $"(ansi yellow)($msg)(ansi reset)" }
def blue [msg: string] { $"(ansi blue)($msg)(ansi reset)" }

def header [title: string] {
    print $"(blue '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
    print $"(blue $'  ($title)')"
    print $"(blue '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
}

def main [version_tag: string] {
    let source_branch = "pre-release"
    let target_branch = "main"
    
    header $"Release to Main - ($source_branch) → ($target_branch)"
    print ""
    
    # Validate version format (stable - no -rc suffix)
    if not ($version_tag =~ '^v[0-9]+\.[0-9]+\.[0-9]+$') {
        print (red "❌ Error: Stable version should not have -rc suffix")
        print "Expected format: vX.Y.Z (e.g., v2.1.20)"
        exit 1
    }
    
    # Check for uncommitted changes
    let status = (git status --porcelain | str trim)
    if $status != "" {
        print (red "❌ Error: Uncommitted changes detected")
        git status --short
        exit 1
    }
    
    # Ensure pre-release branch exists
    let branches = (git branch --list $source_branch)
    if ($branches | str trim) == "" {
        print (red $"❌ Error: ($source_branch) branch doesn't exist")
        exit 1
    }
    
    # Switch to main branch
    let current = (git rev-parse --abbrev-ref HEAD | str trim)
    if $current != $target_branch {
        print (yellow $"⚠️  Not on ($target_branch) branch. Switching...")
        git checkout $target_branch
    }
    
    print (green $"✓ On ($target_branch) branch")
    print ""
    
    # Confirm release
    print (yellow "⚠️  This will:")
    print $"  1. Merge ($source_branch) into ($target_branch)"
    print $"  2. Tag as ($version_tag)"
    print "  3. Push to public GitHub repository"
    print ""
    
    let confirm = (input "Are you sure you want to proceed? (yes/N): ")
    if $confirm != "yes" {
        print "Aborted."
        exit 0
    }
    
    # Merge pre-release into main
    print (blue $"📦 Merging ($source_branch) into ($target_branch)...")
    try {
        git merge $source_branch --no-ff -m $"chore: Release ($version_tag)"
    } catch {
        print (red "❌ Merge conflicts detected")
        print "Please resolve conflicts manually."
        exit 1
    }
    
    print (green $"✓ Merged ($source_branch) into ($target_branch)")
    
    # Tag the stable release
    print (blue $"🏷️  Tagging as ($version_tag)...")
    
    let changelog = (git log --oneline --no-merges $"($target_branch)^..($target_branch)" 
        | lines 
        | take 10 
        | each { $"  - ($in)" } 
        | str join "\n")
    
    git tag -a $version_tag -m $"Release ($version_tag)

Changelog:
($changelog)

See full release notes at:
https://github.com/Distracted-E421/nixos-cursor/releases/tag/($version_tag)"
    
    print (green $"✓ Tagged as ($version_tag)")
    print ""
    
    # Run tests
    print (blue "🧪 Running tests...")
    let check_result = (do { nix flake check } | complete)
    if $check_result.exit_code != 0 {
        print (red "❌ Nix flake check failed")
        exit 1
    }
    print (green "✓ Tests passed")
    print ""
    
    # Build package
    print (blue "🔨 Building package...")
    let build_result = (do { nix build ".#cursor" } | complete)
    if $build_result.exit_code != 0 {
        print (red "❌ Build failed")
        exit 1
    }
    print (green "✓ Build successful")
    print ""
    
    # Summary
    header "✅ Release Prepared"
    print ""
    print (yellow "Final steps:")
    print "  1. Review the release:"
    print $"     (blue 'git log --oneline -10')"
    print $"     (blue $'git show ($version_tag)')"
    print ""
    print "  2. Push to GitHub:"
    print $"     (blue $'git push origin ($target_branch)')"
    print $"     (blue $'git push origin ($version_tag)')"
    print ""
    print "  3. Create GitHub Release:"
    print "     https://github.com/Distracted-E421/nixos-cursor/releases/new"
    print $"     - Tag: ($version_tag)"
    print $"     - Title: nixos-cursor ($version_tag)"
    print ""
    print "  4. Sync back to dev:"
    print $"     (blue $'git checkout dev && git merge ($target_branch)')"
}
