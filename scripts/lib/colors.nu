# Shared color definitions for Nushell scripts
# Source this in other scripts: use lib/colors.nu *

# Box drawing characters
export const BOX_TL = "╔"
export const BOX_TR = "╗"
export const BOX_BL = "╚"
export const BOX_BR = "╝"
export const BOX_H = "═"
export const BOX_V = "║"

# Print a header box
export def header [title: string, width: int = 70] {
    let pad_left = (($width - ($title | str length) - 2) / 2 | math floor)
    let pad_right = ($width - ($title | str length) - 2 - $pad_left)
    
    print $"(ansi blue)($BOX_TL)('' | fill -c $BOX_H -w $width)($BOX_TR)(ansi reset)"
    print $"(ansi blue)($BOX_V)('' | fill -w $pad_left)(ansi white_bold)($title)(ansi reset)(ansi blue)('' | fill -w $pad_right)($BOX_V)(ansi reset)"
    print $"(ansi blue)($BOX_BL)('' | fill -c $BOX_H -w $width)($BOX_BR)(ansi reset)"
}

# Status indicators
export def success [msg: string] { print $"(ansi green)✓(ansi reset)  ($msg)" }
export def warn [msg: string] { print $"(ansi yellow)⚠(ansi reset)  ($msg)" }
export def error [msg: string] { print $"(ansi red)✗(ansi reset)  ($msg)" }
export def info [msg: string] { print $"(ansi cyan)ℹ(ansi reset)  ($msg)" }

# Format bytes as human-readable
export def format-bytes [bytes: int] {
    $bytes | into filesize
}

# Bold text
export def bold [text: string] {
    $"(ansi white_bold)($text)(ansi reset)"
}

# Cyan text (for commands, paths)
export def cmd [text: string] {
    $"(ansi cyan)($text)(ansi reset)"
}

# Yellow text (for values, sizes)
export def value [text: string] {
    $"(ansi yellow)($text)(ansi reset)"
}
