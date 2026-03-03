#!/usr/bin/env bash
# host-network-setup.sh — Idempotent host-level networking setup for the SOC lab
# Run on aurora after a fresh OS install or if lab networking breaks.
# Safe to re-run; all operations are idempotent.
#
# What this does:
#   1. Prevents NetworkManager from grabbing libvirt bridge interfaces (virbr*)
#   2. Installs libvirt network hook to add lab routes when default network starts
#   3. Reserves fw-router a fixed IP via libvirt DHCP (192.168.122.10)
#   4. Enables VM autostart (fw-router, wazuh)
#   5. Adds lab routes immediately (if virbr0 is already up)
#
# Prerequisites:
#   - libvirt "default" network running (virbr0)
#   - libvirt "lab-net" and "lab-sandbox" networks created
#   - fw-router VM defined with MAC 52:54:00:ca:03:ea on the default (WAN) NIC
#   - wazuh VM defined
#
# NOTE: The NM dispatcher (99-soc-lab-routes) is NOT used for routes — NM does not
# manage virbr* interfaces (by design), so dispatcher events never fire for virbr0.
# Routes are added by the libvirt network hook instead.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== SOC Lab: Host Network Setup ==="

# --------------------------------------------------------------------------
# 1. Tell NetworkManager to leave libvirt interfaces alone
#    Without this, NM grabs virbr0 as its own bridge, blocking libvirt from
#    starting the "default" network on boot.
# --------------------------------------------------------------------------
echo "[1/5] Configuring NetworkManager to ignore libvirt interfaces..."
sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/unmanaged-libvirt.conf > /dev/null << 'EOF'
[keyfile]
unmanaged-devices=interface-name:virbr*,interface-name:vnet*,interface-name:veth*
EOF
sudo systemctl reload NetworkManager
echo "      Installed: /etc/NetworkManager/conf.d/unmanaged-libvirt.conf"

# --------------------------------------------------------------------------
# 2. Libvirt network hook — adds lab routes when default network starts
#    NM dispatcher cannot be used because NM doesn't manage virbr* interfaces.
#    Libvirt calls /etc/libvirt/hooks/network with: <name> <action> begin -
# --------------------------------------------------------------------------
echo "[2/5] Installing libvirt network hook for lab routes..."
sudo mkdir -p /etc/libvirt/hooks
sudo cp "$SCRIPT_DIR/libvirt-network-hook" /etc/libvirt/hooks/network
sudo chmod +x /etc/libvirt/hooks/network
echo "      Installed: /etc/libvirt/hooks/network"

# --------------------------------------------------------------------------
# 3. Reserve fw-router a fixed IP via libvirt DHCP
#    MAC: 52:54:00:ca:03:ea -> 192.168.122.10
# --------------------------------------------------------------------------
echo "[3/5] Reserving fw-router DHCP address (192.168.122.10)..."
sudo virsh --connect qemu:///system net-update default add ip-dhcp-host \
    '<host mac="52:54:00:ca:03:ea" name="fw-router" ip="192.168.122.10"/>' \
    --live --config 2>/dev/null \
    && echo "      Reserved: 52:54:00:ca:03:ea -> 192.168.122.10" \
    || echo "      Already reserved (or update failed — check: sudo virsh --connect qemu:///system net-dumpxml default)"

# --------------------------------------------------------------------------
# 4. Enable VM autostart
# --------------------------------------------------------------------------
echo "[4/5] Enabling VM autostart..."
sudo virsh --connect qemu:///system autostart fw-router && echo "      fw-router: autostart enabled"
sudo virsh --connect qemu:///system autostart wazuh    && echo "      wazuh:     autostart enabled"

# --------------------------------------------------------------------------
# 5. Add routes immediately (in case virbr0 is already up)
# --------------------------------------------------------------------------
echo "[5/5] Adding lab routes now (if not already present)..."
sudo ip route replace 192.168.10.0/24 via 192.168.122.10 dev virbr0 \
    && echo "      Set: 192.168.10.0/24 via 192.168.122.10"
sudo ip route replace 192.168.40.0/24 via 192.168.122.10 dev virbr0 \
    && echo "      Set: 192.168.40.0/24 via 192.168.122.10"

echo ""
echo "=== Done. Verify with: ==="
echo "  ip route show | grep 192.168"
echo "  sudo virsh --connect qemu:///system net-dumpxml default | grep host"
echo "  sudo virsh --connect qemu:///system dominfo fw-router | grep -i autostart"
echo "  ssh -i ~/.ssh/fw-router-key root@192.168.122.10 hostname"
