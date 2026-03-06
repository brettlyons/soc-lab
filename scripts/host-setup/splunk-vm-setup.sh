#!/usr/bin/env bash
# splunk-vm-setup.sh — Install and configure Splunk Enterprise on the Splunk VM
#
# Run from aurora after the Splunk VM is up (autoinstall complete):
#   bash scripts/host-setup/splunk-vm-setup.sh
#
# Prerequisites:
#   - Splunk VM running at 192.168.10.40 (Ubuntu 24.04, labadmin user)
#   - SSH key: ~/.ssh/id_ed25519
#   - Splunk .deb downloaded from https://www.splunk.com/en_us/download/splunk-enterprise.html
#     Place at /tmp/splunk.deb on the Splunk VM, or set SPLUNK_DEB_URL below.
#
# What this does:
#   1. Downloads Splunk Enterprise .deb (if SPLUNK_DEB_URL is set)
#   2. Creates splunk system user
#   3. Installs Splunk, sets admin password via user-seed.conf
#   4. Starts Splunk as splunk user
#   5. Enables boot-start via init.d
#   6. Enables TCP receiver on port 9997 (for Splunk UFs)
#
# Credentials:
#   - Splunk web UI: http://192.168.10.40:8000
#   - Username: admin  Password: REDACTED
#
# Note: Splunk 10.x running as root is deprecated. This script creates a
# dedicated splunk system user and runs Splunk under that account.

set -euo pipefail

SPLUNK_HOST="192.168.10.40"
SPLUNK_SSH="ssh -i $HOME/.ssh/id_ed25519 -o StrictHostKeyChecking=no labadmin@${SPLUNK_HOST}"

# Set this to download automatically, or leave blank if .deb is already on the VM at /tmp/splunk.deb
# Get URL from: https://www.splunk.com/en_us/download/splunk-enterprise.html (Linux .deb)
SPLUNK_DEB_URL="${SPLUNK_DEB_URL:-}"

echo "=== Splunk VM Setup ==="

if [[ -n "$SPLUNK_DEB_URL" ]]; then
    echo "[1/5] Downloading Splunk .deb..."
    $SPLUNK_SSH "wget -q --show-progress -O /tmp/splunk.deb '${SPLUNK_DEB_URL}'"
else
    echo "[1/5] Checking for existing /tmp/splunk.deb on VM..."
    $SPLUNK_SSH "ls -lh /tmp/splunk.deb" || { echo "ERROR: /tmp/splunk.deb not found. Set SPLUNK_DEB_URL or copy the .deb to the VM first."; exit 1; }
fi

echo "[2/5] Installing Splunk .deb..."
$SPLUNK_SSH "sudo dpkg -i /tmp/splunk.deb 2>&1 | grep -v '^find:'"

echo "[3/5] Creating splunk system user and setting admin password..."
$SPLUNK_SSH "
    sudo useradd -r -m -s /bin/bash splunk 2>/dev/null || true
    sudo mkdir -p /opt/splunk/etc/system/local
    printf '[user_info]\nUSERNAME = admin\nPASSWORD = REDACTED\n' | sudo tee /opt/splunk/etc/system/local/user-seed.conf > /dev/null
    sudo chown -R splunk:splunk /opt/splunk
"

echo "[4/5] Starting Splunk (first run, accepts license)..."
$SPLUNK_SSH "sudo -u splunk /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt 2>&1 | grep -E 'Done|started|available|http://|ERROR'"

echo "[5/5] Enabling boot-start and Splunk UF receiver on port 9997..."
$SPLUNK_SSH "
    sudo /opt/splunk/bin/splunk enable boot-start -user splunk --accept-license --answer-yes --no-prompt 2>&1 | grep -v WARNING
    sudo -u splunk /opt/splunk/bin/splunk enable listen 9997 -auth admin:REDACTED 2>&1
"

echo ""
echo "=== Done ==="
echo "Splunk web UI: http://${SPLUNK_HOST}:8000"
echo "Username: admin   Password: REDACTED"
echo "UF receiver: TCP 9997"
echo ""
echo "Verify: curl -sk -o /dev/null -w '%{http_code}' http://${SPLUNK_HOST}:8000"
