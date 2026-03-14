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
    "win-user01    (192.168.10.30) — mscott (domain)|192.168.10.30|LAB\mscott|soc-lab/domain-users/mscott"
    "win-user01    (192.168.10.30) — dschrute (domain)|192.168.10.30|LAB\dschrute|soc-lab/domain-users/dschrute"
    "win-user02    (192.168.10.31) — labadmin|192.168.10.31|labadmin|soc-lab/windows-workstation"
    "win-user02    (192.168.10.31) — mscott (domain)|192.168.10.31|LAB\mscott|soc-lab/domain-users/mscott"
    "win-user02    (192.168.10.31) — dschrute (domain)|192.168.10.31|LAB\dschrute|soc-lab/domain-users/dschrute"
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

# Split DOMAIN\user into separate /d: and /u: args to avoid host-side Kerberos negotiation.
# Always use /sec:tls so xfreerdp doesn't try to resolve the AD KDC from the linux host.
if [[ "$USER" == *\\* ]]; then
    DOMAIN="${USER%%\\*}"
    USERNAME="${USER##*\\}"
    AUTH_ARGS="/d:${DOMAIN}\n/u:${USERNAME}"
else
    AUTH_ARGS="/u:${USER}"
fi

echo "Connecting to $SELECTED ..."
# /sec:nla — Windows requires NLA after domain join. Falls back to NTLM when host
# has no Kerberos config for LAB realm (aurora has no /etc/krb5.conf for LAB).
# /sec:tls was tried first but Windows rejects it (security negotiation failure).
printf "/v:%s\n${AUTH_ARGS}\n/p:%s\n/sec:nla\n/size:3840x2160\n/scale:180\n/scale-desktop:180\n/scale-device:180\n/cert:ignore\n/clipboard\n/log-level:ERROR\n" \
    "$IP" "$PASS" \
    | xfreerdp /args-from:stdin

# Original single /u: form (works for local users, fails for domain users with Kerberos error):
# printf '/v:%s\n/u:%s\n/p:%s\n/size:3840x2160\n/scale:180\n/scale-desktop:180\n/scale-device:180\n/cert:ignore\n/clipboard\n/log-level:ERROR\n' \
#     "$IP" "$USER" "$PASS" \
#     | xfreerdp /args-from:stdin
