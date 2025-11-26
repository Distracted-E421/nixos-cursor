#!/usr/bin/env nu

# Script: validate-urls.nu
# Purpose: Validate Cursor download URLs are accessible
# Usage: nu validate-urls.nu [options]
#
# Replaces: scripts/validation/validate-urls.sh

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

const VERSION = "2.0.0"

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

def header [title: string] {
    print $"(ansi blue)╔═══════════════════════════════════════════════════════════════════╗(ansi reset)"
    print $"(ansi blue)║     (ansi white_bold)($title)(ansi reset)(ansi blue)                        ║(ansi reset)"
    print $"(ansi blue)╚═══════════════════════════════════════════════════════════════════╝(ansi reset)"
    print ""
}

def success [msg: string] { print $"  (ansi green)✓(ansi reset) ($msg)" }
def fail [msg: string] { print $"  (ansi red)✗(ansi reset) ($msg)" }
def redirect [msg: string] { print $"  (ansi yellow)→(ansi reset) ($msg)" }

# Extract version from URL
def extract-version [url: string]: nothing -> string {
    let match = ($url | parse -r 'Cursor-(\d+\.\d+\.\d+)')
    if ($match | is-empty) {
        "unknown"
    } else {
        $match.0.capture0
    }
}

# Determine platform from URL
def extract-platform [url: string]: nothing -> string {
    if ($url =~ 'linux/x64') {
        "linux-x64"
    } else if ($url =~ 'darwin/universal') {
        "darwin-universal"
    } else if ($url =~ 'darwin/x64') {
        "darwin-x64"
    } else if ($url =~ 'darwin/arm64') {
        "darwin-arm64"
    } else {
        "unknown"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# VALIDATION FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Validate a single URL using curl (more reliable for redirects than http head)
def validate-url [url: string]: nothing -> record {
    let version = (extract-version $url)
    let platform = (extract-platform $url)
    
    # Use curl to check URL status (Nushell's http doesn't handle all edge cases well)
    let result = (do { 
        ^curl -sL -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 $url 
    } | complete)
    
    let http_code = if $result.exit_code == 0 {
        $result.stdout | str trim
    } else {
        "000"
    }
    
    let status = match $http_code {
        "200" => "ok"
        "301" | "302" | "303" | "307" | "308" => "redirect"
        "000" => "timeout"
        _ => "error"
    }
    
    {
        url: $url
        version: $version
        platform: $platform
        http_code: $http_code
        status: $status
    }
}

# Parse Linux x64 URL file
def parse-linux-urls [file_path: string]: nothing -> list {
    if not ($file_path | path exists) {
        print $"(ansi red)Linux URL file not found: ($file_path)(ansi reset)"
        return []
    }
    
    open $file_path 
    | lines 
    | where { |line| ($line starts-with "https://downloads.cursor.com") and ($line =~ 'linux/x64') }
}

# Parse Darwin URL file
def parse-darwin-urls [file_path: string]: nothing -> list {
    if not ($file_path | path exists) {
        print $"(ansi red)Darwin URL file not found: ($file_path)(ansi reset)"
        return []
    }
    
    open $file_path 
    | lines 
    | where { |line| ($line starts-with "https://downloads.cursor.com") and ($line =~ 'darwin/') }
}

# Validate URLs with progress output
def validate-urls-with-progress [urls: list, label: string]: nothing -> list {
    print $"(ansi cyan)($label)(ansi reset)"
    
    let total = ($urls | length)
    
    $urls | enumerate | each { |item|
        let idx = $item.index + 1
        let url = $item.item
        
        # Progress indicator every 10 URLs or at end
        if ($idx mod 10 == 0) or ($idx == $total) {
            print $"  [($idx)/($total)] validating..."
        }
        
        let result = (validate-url $url)
        
        # Print status
        match $result.status {
            "ok" => { success $"($result.version) \(($result.platform)\): (ansi green)200 OK(ansi reset)" }
            "redirect" => { redirect $"($result.version) \(($result.platform)\): (ansi yellow)($result.http_code) Redirect(ansi reset)" }
            "timeout" => { fail $"($result.version) \(($result.platform)\): (ansi red)Timeout(ansi reset)" }
            _ => { fail $"($result.version) \(($result.platform)\): (ansi red)($result.http_code)(ansi reset)" }
        }
        
        $result
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# REPORT GENERATION
# ─────────────────────────────────────────────────────────────────────────────

# Generate markdown report
def generate-report [results: list, output_dir: string] {
    let total = ($results | length)
    let valid = ($results | where { |r| $r.status == "ok" or $r.status == "redirect" } | length)
    let ok_only = ($results | where status == "ok" | length)
    let redirects = ($results | where status == "redirect" | length)
    let invalid = ($results | where { |r| $r.status == "timeout" or $r.status == "error" } | length)
    let success_rate = if $total > 0 { ($valid * 100 / $total | math round --precision 1) } else { 0 }
    
    let timestamp = (date now | format date "%Y-%m-%dT%H:%M:%S")
    
    let report = $"# Cursor URL Validation Report

Generated: ($timestamp)

## Summary

| Metric | Count |
|--------|-------|
| Total URLs | ($total) |
| Valid \(200 OK\) | ($ok_only) |
| Redirects \(3xx\) | ($redirects) |
| Invalid/Failed | ($invalid) |
| Success Rate | ($success_rate)% |

## Valid URLs

($results | where { |r| $r.status == 'ok' or $r.status == 'redirect' } | each { |r| $'($r.version)|($r.platform)|($r.url)|($r.http_code)' } | str join '\n')

## Invalid URLs

($results | where { |r| $r.status == 'timeout' or $r.status == 'error' } | each { |r| $'($r.version)|($r.platform)|($r.url)|($r.http_code)' } | str join '\n')
"
    
    # Save files
    mkdir $output_dir
    
    $report | save -f $"($output_dir)/validation-report.md"
    
    $results 
    | where { |r| $r.status == "ok" or $r.status == "redirect" } 
    | each { |r| $"($r.version)|($r.platform)|($r.url)|($r.http_code)" }
    | str join "\n"
    | save -f $"($output_dir)/valid-urls.txt"
    
    $results 
    | where { |r| $r.status == "timeout" or $r.status == "error" } 
    | each { |r| $"($r.version)|($r.platform)|($r.url)|($r.http_code)" }
    | str join "\n"
    | save -f $"($output_dir)/invalid-urls.txt"
    
    {
        total: $total
        valid: $valid
        ok_only: $ok_only
        redirects: $redirects
        invalid: $invalid
        success_rate: $success_rate
    }
}

# Print summary
def print-summary [stats: record, output_dir: string] {
    print ""
    header "Validation Summary"
    
    print $"  Total URLs checked: (ansi cyan)($stats.total)(ansi reset)"
    print $"  Valid \(200 OK\):     (ansi green)($stats.ok_only)(ansi reset)"
    print $"  Redirects \(3xx\):    (ansi yellow)($stats.redirects)(ansi reset)"
    print $"  Invalid/Failed:     (ansi red)($stats.invalid)(ansi reset)"
    print ""
    print $"  Report saved to: (ansi blue)($output_dir)/validation-report.md(ansi reset)"
    print ""
    
    if $stats.invalid > 0 {
        print $"(ansi yellow)⚠ Some URLs failed validation. Check ($output_dir)/invalid-urls.txt(ansi reset)"
        false
    } else {
        print $"(ansi green)✓ All URLs validated successfully!(ansi reset)"
        true
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

def main [
    --linux-only (-l)           # Only validate Linux URLs
    --darwin-only (-d)          # Only validate Darwin URLs
    --output (-o): string       # Output directory (default: .cursor/validation-results)
    --json (-j)                 # Output results as JSON
    --help (-h)                 # Show help
] {
    if $help {
        print "
Usage: nu validate-urls.nu [OPTIONS]

Validate Cursor download URLs are accessible

Options:
    -h, --help          Show this help
    -l, --linux-only    Only validate Linux URLs
    -d, --darwin-only   Only validate Darwin URLs
    -o, --output DIR    Output directory (default: .cursor/validation-results)
    -j, --json          Output results as JSON

Examples:
    nu validate-urls.nu                    # Validate all URLs
    nu validate-urls.nu --linux-only       # Only Linux URLs
    nu validate-urls.nu --json             # JSON output
    nu validate-urls.nu -o /tmp/results    # Custom output directory
"
        return
    }
    
    header "Cursor Download URL Validation"
    
    # Determine repo root
    let script_dir = ($env.FILE_PWD? | default ".")
    let repo_root = $"($script_dir)/../.."
    
    # Determine output directory
    let output_dir = if ($output | is-empty) {
        $"($repo_root)/.cursor/validation-results"
    } else {
        $output
    }
    
    # Collect all results
    mut all_results = []
    
    # Validate Linux URLs
    if not $darwin_only {
        let linux_file = $"($repo_root)/.cursor/linux -x64-version-urls.txt"
        let linux_urls = (parse-linux-urls $linux_file)
        
        if ($linux_urls | length) > 0 {
            let linux_results = (validate-urls-with-progress $linux_urls "Validating Linux x64 URLs...")
            $all_results = ($all_results | append $linux_results)
            print ""
        }
    }
    
    # Validate Darwin URLs
    if not $linux_only {
        let darwin_file = $"($repo_root)/.cursor/darwin-all-urls.txt"
        let darwin_urls = (parse-darwin-urls $darwin_file)
        
        if ($darwin_urls | length) > 0 {
            let darwin_results = (validate-urls-with-progress $darwin_urls "Validating Darwin (macOS) URLs...")
            $all_results = ($all_results | append $darwin_results)
        }
    }
    
    if ($all_results | length) == 0 {
        print $"(ansi yellow)No URLs found to validate(ansi reset)"
        return
    }
    
    # Output
    if $json {
        $all_results | to json
    } else {
        print ""
        print $"(ansi cyan)Generating validation report...(ansi reset)"
        
        let stats = (generate-report $all_results $output_dir)
        let success = (print-summary $stats $output_dir)
        
        if not $success {
            exit 1
        }
    }
}
