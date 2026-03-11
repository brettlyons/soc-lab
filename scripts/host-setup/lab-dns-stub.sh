#!/usr/bin/env bash
# lab-dns-stub.sh — Configure systemd-resolved to use fw-router for lab.local DNS
#
# Run on aurora (host) after dnsmasq is running on fw-router.
# Safe to re-run; idempotent.
#
# What this does:
#   Adds a stub zone so that *.lab.local queries go to 192.168.10.1 (fw-router).
#   All other DNS traffic uses your normal resolver. No global DNS change.
#
# After running: ping wazuh.lab.local, ssh splunk.lab.local, etc. work from the host.

set -euo pipefail

STUB_DIR=/etc/systemd/resolved.conf.d
STUB_FILE="$STUB_DIR/lab-local.conf"
FW_DNS=192.168.122.10   # fw-router WAN IP — reachable from the host via virbr0

echo "=== SOC Lab: Host DNS Stub Zone Setup ==="

echo "[1/3] Writing systemd-resolved stub zone for lab.local..."
sudo mkdir -p "$STUB_DIR"
sudo tee "$STUB_FILE" > /dev/null << EOF
[Resolve]
# Route *.lab.local queries to fw-router dnsmasq
# All other queries use the normal resolver
DNS=${FW_DNS}
Domains=~lab.local
EOF
echo "      Installed: $STUB_FILE"

echo "[2/3] Restarting systemd-resolved..."
sudo systemctl restart systemd-resolved
echo "      Done."

echo "[3/3] Verifying resolution..."
# dig with a short timeout avoids hanging if fw-router DNS isn't reachable yet
RESULT=$(dig +short +timeout=3 +tries=1 @${FW_DNS} wazuh.lab.local 2>/dev/null)
if [ "$RESULT" = "192.168.10.10" ]; then
    echo "      wazuh.lab.local -> 192.168.10.10  [OK]"
    echo "      DNS stub zone is working."
else
    echo "      WARNING: could not reach ${FW_DNS}:53"
    echo "      Stub zone is configured but DNS isn't answering yet."
    echo "      Check: bash scripts/fw-router/nftables-deploy.sh"
    echo "        then: dig +short @${FW_DNS} wazuh.lab.local"
fi

echo ""
echo "Done. *.lab.local now resolves from the host via fw-router."
echo "  ping fw-router.lab.local"
echo "  ping wazuh.lab.local"
echo "  ping splunk.lab.local"
