#!/bin/bash
#
# system_summary.sh - System Information Summary
#
# Displays system information using fastfetch.
#

if command -v fastfetch >/dev/null 2>&1; then
    fastfetch
else
    echo -e "\033[1;33m⚠️  [WARNING]\033[0m fastfetch is not installed. Install it with:"
    echo "    sudo apt install fastfetch   # Debian/Ubuntu"
    echo "    sudo pacman -S fastfetch     # Arch Linux"
fi
