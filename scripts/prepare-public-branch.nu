#!/usr/bin/env nu
# Prepare Public Branch - Automates dev → pre-release transition
# Usage: nu scripts/prepare-public-branch.nu <version-tag>
#
# Example: nu scripts/prepare-public-branch.nu v2.1.20-rc1

def header [title: string] {
    print $"(ansi blue)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━(ansi reset)"
    print $"(ansi blue)  ($title)(ansi reset)"
    print $"(ansi blue)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━(ansi reset)"
}

def main [
    version_tag: string  # Version tag (e.g., v2.1.20-rc1)
] {
    let target_branch = "pre-release"
    let source_branch = "dev"
    
    header $"Prepare Public Branch - ($source_branch) → ($target_branch)"
    print ""
    
    # Validate version tag format
    if not ($version_tag =~ '^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$') {
        print $"(ansi yellow)⚠️  Warning: Version tag doesn't match expected format (vX.Y.Z or vX.Y.Z-rcN)(ansi reset)"
        let reply = (input "Continue anyway? (y/N): ")
        if not ($reply =~ '^[Yy]$') {
            exit 1
        }
    }
    
    # Check for uncommitted changes
    let status = (git status --porcelain | str trim)
    if $status != "" {
        print $"(ansi red)❌ Error: Uncommitted changes detected(ansi reset)"
        print "Please commit or stash your changes before running this script."
        git status --short
        exit 1
    }
    
    # Ensure we're on dev branch
    let current_branch = (git rev-parse --abbrev-ref HEAD | str trim)
    if $current_branch != $source_branch {
        print $"(ansi yellow)⚠️  Not on ($source_branch) branch. Switching...(ansi reset)"
        git checkout $source_branch
    }
    
    print $"(ansi green)✓ On ($source_branch) branch(ansi reset)"
    print ""
    
    # Create pre-release branch if it doesn't exist
    let branch_exists = (git show-ref --verify --quiet $"refs/heads/($target_branch)" | complete).exit_code == 0
    if not $branch_exists {
        print $"(ansi yellow)⚠️  ($target_branch) branch doesn't exist. Creating...(ansi reset)"
        git checkout -b $target_branch
    } else {
        print $"(ansi green)✓ ($target_branch) branch exists(ansi reset)"
        git checkout $target_branch
    }
    
    # Merge dev into pre-release (without committing)
    print $"(ansi blue)📦 Merging ($source_branch) into ($target_branch)...(ansi reset)"
    let merge_result = (git merge $source_branch --no-commit --no-ff | complete)
    if $merge_result.exit_code != 0 {
        print $"(ansi red)❌ Merge conflicts detected(ansi reset)"
        print "Please resolve conflicts manually and re-run this script."
        git merge --abort
        exit 1
    }
    
    # Use public .gitignore (restrictive)
    print $"(ansi blue)🔧 Applying public .gitignore...(ansi reset)"
    if (".gitignore-public" | path exists) {
        cp .gitignore-public .gitignore
        git add .gitignore
    } else {
        print $"(ansi red)❌ ERROR: .gitignore-public not found(ansi reset)"
        exit 1
    }
    
    # Remove entire .cursor/ directory
    print $"(ansi blue)🧹 Removing entire .cursor/ directory...(ansi reset)"
    
    mut removed_files = []
    
    if (".cursor" | path exists) {
        do { git rm -rf --cached .cursor/ } | complete
        rm -rf .cursor/
        $removed_files = ($removed_files | append ".cursor/ (entire directory)")
        print $"(ansi green)  ✓ Removed entire .cursor/ directory(ansi reset)"
    } else {
        print $"(ansi yellow)  ⚠️  .cursor/ directory already removed(ansi reset)"
    }
    
    # Validate no sensitive content
    print ""
    print $"(ansi blue)🔍 Validating for sensitive content...(ansi reset)"
    
    mut validation_issues = []
    
    # Check for personal email addresses
    let email_check = (do {
        git grep -l "distracted\\.e421@gmail\\.com" -- . ':!.git' ':!scripts/' ':!*.md' ':!LICENSE' ':!cursor/' ':!home-manager-module/' ':!docs/'
    } | complete)
    
    if $email_check.exit_code == 0 and ($email_check.stdout | str trim) != "" {
        $validation_issues = ($validation_issues | append "Found personal email address in unexpected files")
    }
    
    # Check for absolute paths
    let path_check = (do {
        git grep -l "/home/e421/" -- . ':!.git' ':!scripts/' ':!*.md' ':!cursor/default.nix' ':!home-manager-module/' ':!docs/'
    } | complete)
    
    if $path_check.exit_code == 0 and ($path_check.stdout | str trim) != "" {
        $validation_issues = ($validation_issues | append "Found absolute paths in non-documentation files")
    }
    
    # Check for real API keys
    let key_check = (do {
        git grep -E "(github|api)_token\\s*=\\s*['\"][a-zA-Z0-9]{40,}['\"]" -- . ':!.git' ':!scripts/' ':!INTEGRATION_GUIDE.md' ':!docs/'
    } | complete)
    
    if $key_check.exit_code == 0 and ($key_check.stdout | str trim) != "" {
        $validation_issues = ($validation_issues | append "Found potential REAL API keys or secrets")
    }
    
    if ($validation_issues | length) > 0 {
        print $"(ansi red)❌ Validation failed:(ansi reset)"
        for issue in $validation_issues {
            print $"(ansi red)  • ($issue)(ansi reset)"
        }
        print ""
        print "Please fix these issues before continuing."
        git reset --hard HEAD
        exit 1
    }
    
    print $"(ansi green)✓ No sensitive content detected(ansi reset)"
    print ""
    
    # Commit the merge
    print $"(ansi blue)💾 Committing changes...(ansi reset)"
    git add -A
    
    let commit_msg = $"chore: Prepare ($version_tag) from ($source_branch)

Removed private artifacts:
($removed_files | each { |f| $'  - ($f)' } | str join '\n')

Ready for public release testing."
    
    git commit -m $commit_msg
    
    print $"(ansi green)✓ Committed to ($target_branch)(ansi reset)"
    
    # Tag the release candidate
    print $"(ansi blue)🏷️  Tagging as ($version_tag)...(ansi reset)"
    
    let changelog = (git log --oneline --no-merges $"($target_branch)..($source_branch)" | lines | first 5 | each { |l| $"  ($l)" } | str join "\n")
    
    let tag_msg = $"Release candidate ($version_tag)

Changelog:
($changelog)
- (see full history for details)
"
    
    git tag -a $version_tag -m $tag_msg
    
    print $"(ansi green)✓ Tagged as ($version_tag)(ansi reset)"
    print ""
    
    # Summary
    print $"(ansi blue)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━(ansi reset)"
    print $"(ansi green)✅ Preparation Complete(ansi reset)"
    print $"(ansi blue)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━(ansi reset)"
    print ""
    print $"(ansi yellow)Next steps:(ansi reset)"
    print "  1. Review changes:"
    print $"     (ansi blue)git diff ($source_branch)..($target_branch)(ansi reset)"
    print ""
    print "  2. Test the build:"
    print $"     (ansi blue)nix flake check(ansi reset)"
    print $"     (ansi blue)nix build .#cursor(ansi reset)"
    print ""
    print "  3. Push to GitHub (when ready):"
    print $"     (ansi blue)git push origin ($target_branch)(ansi reset)"
    print $"     (ansi blue)git push origin ($version_tag)(ansi reset)"
    print ""
    print $"(ansi yellow)⚠️  Remember: This will make ($target_branch) and ($version_tag) PUBLIC(ansi reset)"
    print ""
}
