---
name: Bug Report
about: Report a bug in nixos-cursor RC1
title: '[BUG] '
labels: bug
assignees: ''

---

**Describe the bug**
A clear and concise description of what the bug is.

**System Information**
Please run these commands and paste the output:

```bash
nixos-version
uname -m
echo $XDG_CURRENT_DESKTOP
echo $WAYLAND_DISPLAY  # or $DISPLAY for X11
nix-shell -p glxinfo --run "glxinfo | grep 'OpenGL renderer'"
```

**To Reproduce**
Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Expected behavior**
A clear and concise description of what you expected to happen.

**Actual behavior**
What actually happened.

**Logs/Errors**
If applicable, paste any error messages or logs here.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Additional context**
Add any other context about the problem here.
