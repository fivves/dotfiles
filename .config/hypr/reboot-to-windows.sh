#!/usr/bin/env bash
set -euo pipefail

# Change this to your actual Windows entry number
WIN_BOOTNUM="0000"

sudo efibootmgr -n "$WIN_BOOTNUM"
systemctl reboot