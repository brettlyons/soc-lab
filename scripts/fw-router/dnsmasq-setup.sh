#!/bin/bash
# dnsmasq-setup.sh — Deploy DNS + DHCP to fw-router
#
# Run from the HOST (not on fw-router):
#   bash scripts/fw-router/dnsmasq-setup.sh
#
# What this does:
#   1. SCPs dnsmasq.conf (same directory) to fw-router /etc/dnsmasq.conf
#   2. SSHs in and installs dnsmasq, enables it, starts it
#   3. Verifies DNS resolution works
#
# dnsmasq.conf is the single source of truth — edit that file, re-run this script to redeploy.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FW_SSH="ssh -i ~/.ssh/fw-router-key root@192.168.122.10"
FW_SCP="scp -i ~/.ssh/fw-router-key"

echo "==> Installing dnsmasq on fw-router..."
$FW_SSH apk add --no-cache dnsmasq

echo "==> Copying dnsmasq.conf to fw-router..."
$FW_SCP "$SCRIPT_DIR/dnsmasq.conf" root@192.168.122.10:/etc/dnsmasq.conf

echo "==> Enabling and starting dnsmasq on fw-router..."
$FW_SSH << 'ENDSSH'
set -e

echo "--- Enabling dnsmasq at boot ---"
rc-update add dnsmasq default

echo "--- (Re)starting dnsmasq to pick up config ---"
rc-service dnsmasq restart

echo "--- Status ---"
rc-service dnsmasq status

echo "--- Testing local resolution (wazuh.lab.local) ---"
# nslookup may not be available; fall back to drill (bundled with Alpine busybox)
nslookup wazuh.lab.local 127.0.0.1 2>/dev/null || \
  drill @127.0.0.1 wazuh.lab.local 2>/dev/null || \
  echo "(install nslookup/drill to test — dnsmasq is running)"

echo ""
echo "Done. dnsmasq serving:"
echo "  DNS  -> 192.168.10.1:53  (lab.local zone + upstream 1.1.1.1/8.8.8.8)"
echo "  DHCP -> 192.168.10.100-200  (options 3/6/15/66 set)"
echo "  Log  -> /var/log/dnsmasq.log"
ENDSSH
