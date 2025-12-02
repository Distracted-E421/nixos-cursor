#!/usr/bin/env nu
# NPM Security Module - Complete Test Suite
# 
# Usage:
#   nu run-all-tests.nu              # Run offline tests
#   nu run-all-tests.nu --network    # Include network tests

let script_dir = ($env.FILE_PWD? | default ".")

def main [
    --network  # Include network tests (slower)
] {
    print "╔═══════════════════════════════════════════════════════════════════╗"
    print "║        NPM Security Module - Complete Test Suite                  ║"
    print "╚═══════════════════════════════════════════════════════════════════╝"
    print ""
    print $"Date: (date now | format date '%Y-%m-%d %H:%M:%S')"
    print $"Directory: ($script_dir)"
    print ""
    
    mut failed_suites = 0
    
    # Run blocklist tests
    print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print $"(ansi blue)Running: Blocklist Tests(ansi reset)"
    print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    let blocklist_result = do { nu $"($script_dir)/test-blocklist.nu" } | complete
    if $blocklist_result.exit_code == 0 {
        print $"(ansi green)✓ Blocklist tests passed(ansi reset)"
    } else {
        print $"(ansi red)✗ Blocklist tests failed(ansi reset)"
        $failed_suites += 1
    }
    print ""
    
    # Run scanner tests
    print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print $"(ansi blue)Running: Scanner Tests [offline](ansi reset)"
    print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    let scanner_result = do { nu $"($script_dir)/test-scanner.nu" } | complete
    if $scanner_result.exit_code == 0 {
        print $"(ansi green)✓ Scanner tests passed(ansi reset)"
    } else {
        print $"(ansi red)✗ Scanner tests failed(ansi reset)"
        $failed_suites += 1
    }
    print ""
    
    # Run network tests if requested
    if $network {
        print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print $"(ansi blue)Running: Scanner Tests [network](ansi reset)"
        print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        let network_result = do { nu $"($script_dir)/test-scanner.nu" --network } | complete
        if $network_result.exit_code == 0 {
            print $"(ansi green)✓ Network tests passed(ansi reset)"
        } else {
            print $"(ansi red)✗ Network tests failed(ansi reset)"
            $failed_suites += 1
        }
        print ""
    }
    
    # Final summary
    print ""
    print "╔═══════════════════════════════════════════════════════════════════╗"
    print "║                     FINAL TEST SUMMARY                            ║"
    print "╚═══════════════════════════════════════════════════════════════════╝"
    print ""
    
    if $failed_suites == 0 {
        print $"(ansi green)All test suites passed!(ansi reset)"
        print ""
        print "Next steps:"
        print "  1. Run with --network for full validation"
        print "  2. Manually test cursor-security CLI commands"
        print "  3. Test in a real Cursor installation"
        exit 0
    } else {
        print $"(ansi red)($failed_suites) test suite[s] failed(ansi reset)"
        print ""
        print "Fix failures before merging to main."
        exit 1
    }
}
