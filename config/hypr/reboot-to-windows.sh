#!/usr/bin/env bash
set -euo pipefail

# Your Windows Boot ID
WIN_BOOTNUM="0000"

# 1. Verify we are actually changing the var, or fail fast
echo "Setting next boot to Windows Boot Manager ($WIN_BOOTNUM)..."
if sudo efibootmgr -n "$WIN_BOOTNUM"; then
    echo "Success. Rebooting now..."
    # 2. Give the session a second to breathe, then kill it.
    # Using 'shutdown -r now' is standard, but if it still hangs,
    # swap the line below for: systemctl reboot -i
    sudo shutdown -r now
else
    echo "Error: Failed to set EFI variable. Is efivarfs mounted?"
    exit 1
fi