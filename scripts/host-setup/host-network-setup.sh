#!/usr/bin/env bash
# host-network-setup.sh — Idempotent host-level networking setup for the SOC lab
# Run on aurora after a fresh OS install or if lab networking breaks.
# Safe to re-run; all operations are idempotent.
#
# What this does:
#   1. Installs the NM dispatcher script for persistent lab routes
#   2. Reserves fw-router a fixed IP via libvirt DHCP (192.168.122.10)
#   3. Enables VM autostart (fw-router, wazuh)
#   4. Adds lab routes immediately (don't wait for virbr0 bounce)
#
# Prerequisites:
#   - libvirt "default" network running (virbr0)
#   - libvirt "lab-net" and "lab-sandbox" networks created
#   - fw-router VM defined with MAC 52:54:00:ca:03:ea on the default (WAN) NIC
#   - wazuh VM defined

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== SOC Lab: Host Network Setup ==="

# --------------------------------------------------------------------------
# 1. NM dispatcher script for persistent lab routes
# --------------------------------------------------------------------------
echo "[1/4] Installing NetworkManager dispatcher script..."
sudo cp "$SCRIPT_DIR/99-soc-lab-routes" /etc/NetworkManager/dispatcher.d/99-soc-lab-routes
sudo chmod 755 /etc/NetworkManager/dispatcher.d/99-soc-lab-routes
echo "      Installed: /etc/NetworkManager/dispatcher.d/99-soc-lab-routes"

# --------------------------------------------------------------------------
# 2. Reserve fw-router a fixed IP via libvirt DHCP
#    MAC: 52:54:00:ca:03:ea -> 192.168.122.10
#    (virsh net-update is idempotent if the entry already exists)
# --------------------------------------------------------------------------
echo "[2/4] Reserving fw-router DHCP address (192.168.122.10)..."
sudo virsh net-update default add ip-dhcp-host \
    '<host mac="52:54:00:ca:03:ea" name="fw-router" ip="192.168.122.10"/>' \
    --live --config 2>/dev/null \
    && echo "      Reserved: 52:54:00:ca:03:ea -> 192.168.122.10" \
    || echo "      Already reserved (or update failed — check: sudo virsh net-dumpxml default)"

# --------------------------------------------------------------------------
# 3. Enable VM autostart
# --------------------------------------------------------------------------
echo "[3/4] Enabling VM autostart..."
sudo virsh autostart fw-router && echo "      fw-router: autostart enabled"
sudo virsh autostart wazuh    && echo "      wazuh:     autostart enabled"

# --------------------------------------------------------------------------
# 4. Add routes immediately (in case virbr0 is already up)
# --------------------------------------------------------------------------
echo "[4/4] Adding lab routes (if not already present)..."
sudo ip route add 192.168.10.0/24 via 192.168.122.10 dev virbr0 2>/dev/null \
    && echo "      Added: 192.168.10.0/24 via 192.168.122.10" \
    || echo "      Already present: 192.168.10.0/24"
sudo ip route add 192.168.40.0/24 via 192.168.122.10 dev virbr0 2>/dev/null \
    && echo "      Added: 192.168.40.0/24 via 192.168.122.10" \
    || echo "      Already present: 192.168.40.0/24"

echo ""
echo "=== Done. Verify with: ==="
echo "  ip route show | grep 192.168"
echo "  sudo virsh net-dumpxml default | grep host"
echo "  sudo virsh dominfo fw-router | grep autostart"
echo "  ssh -i ~/.ssh/fw-router-key root@192.168.122.10 hostname"
