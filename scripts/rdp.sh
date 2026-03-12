#!/usr/bin/env bash
# rdp.sh — FZF picker to RDP into any Windows lab VM
#
# Usage: ./scripts/rdp.sh
#
# Passwords pulled from pass store — never appear on the command line.
# Add new VMs to the HOSTS array as they come online.

set -euo pipefail

# VM definitions: "display name|ip|user|pass-key"
HOSTS=(
    "win-forensic  (192.168.10.50) — analyst account|192.168.10.50|analyst|soc-lab/windows-analyst"
    "win-user01    (192.168.10.30) — labadmin|192.168.10.30|labadmin|soc-lab/windows-workstation"
    "win-user02    (192.168.10.31) — labadmin|192.168.10.31|labadmin|soc-lab/windows-workstation"
    "dc01          (192.168.10.20) — Administrator|192.168.10.20|Administrator|soc-lab/dc01-admin"
)

# Pick a host
SELECTED=$(printf '%s\n' "${HOSTS[@]}" | cut -d'|' -f1 | fzf --prompt="RDP > " --height=40% --border) || exit 0

# Look up the full entry
ENTRY=$(printf '%s\n' "${HOSTS[@]}" | grep "^${SELECTED}|")
IP=$(echo "$ENTRY"   | cut -d'|' -f2)
USER=$(echo "$ENTRY" | cut -d'|' -f3)
PASSKEY=$(echo "$ENTRY" | cut -d'|' -f4)

PASS=$(pass show "$PASSKEY")

echo "Connecting to $SELECTED ..."
printf '/v:%s\n/u:%s\n/p:%s\n/size:3840x2160\n/scale:180\n/scale-desktop:180\n/scale-device:180\n/cert:ignore\n/clipboard\n/log-level:ERROR\n' \
    "$IP" "$USER" "$PASS" \
    | xfreerdp /args-from:stdin
