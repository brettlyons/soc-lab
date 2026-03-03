#!/usr/bin/env bash
# host-network-setup.sh — Idempotent host-level networking setup for the SOC lab
# Run on aurora after a fresh OS install or if lab networking breaks.
# Safe to re-run; all operations are idempotent.
#
# What this does:
#   1. Prevents NetworkManager from grabbing libvirt bridge interfaces (virbr*)
#   2. Installs systemd unit to add lab routes after virtnetworkd starts
#   3. Reserves fw-router a fixed IP via libvirt DHCP (192.168.122.10)
#   4. Enables VM autostart (fw-router, wazuh)
#   5. Adds lab routes immediately (if virbr0 is already up)
#
# Prerequisites:
#   - libvirt "default" and "lab-net" networks created and active
#   - fw-router VM defined with MAC 52:54:00:ca:03:ea on the default (WAN) NIC
#   - wazuh VM defined
#
# NOTE: lab-sandbox network is disabled due to a libvirt bug (reports "already in
# use by virbr0" regardless of bridge name). lab-sandbox NIC has been removed from
# fw-router and wazuh. Revisit in Phase 10 when sandbox VM is needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== SOC Lab: Host Network Setup ==="

# --------------------------------------------------------------------------
# 1. Tell NetworkManager to leave libvirt interfaces alone
#    Without this, NM grabs virbr0 as its own bridge, blocking libvirt from
#    starting the "default" network on boot.
# --------------------------------------------------------------------------
echo "[1/4] Configuring NetworkManager to ignore libvirt interfaces..."
sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/unmanaged-libvirt.conf > /dev/null << 'EOF'
[keyfile]
unmanaged-devices=interface-name:virbr*,interface-name:vnet*,interface-name:veth*
EOF
sudo systemctl reload NetworkManager
echo "      Installed: /etc/NetworkManager/conf.d/unmanaged-libvirt.conf"

# --------------------------------------------------------------------------
# 2. Systemd unit to add lab routes after virtnetworkd starts
#    NM dispatcher does not fire for unmanaged (virbr*) interfaces.
#    Libvirt hooks require SELinux tuning and caused network taint issues.
#    A simple systemd oneshot unit is the most reliable approach.
# --------------------------------------------------------------------------
echo "[2/4] Installing soc-lab-routes systemd unit..."
sudo tee /etc/systemd/system/soc-lab-routes.service > /dev/null << 'EOF'
[Unit]
Description=SOC Lab - Add lab network routes
After=virtnetworkd.service
Wants=virtnetworkd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sleep 8
ExecStart=/sbin/ip route replace 192.168.10.0/24 via 192.168.122.10 dev virbr0
ExecStart=/sbin/ip route replace 192.168.40.0/24 via 192.168.122.10 dev virbr0

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable soc-lab-routes.service
echo "      Installed and enabled: soc-lab-routes.service"

# --------------------------------------------------------------------------
# 3. Reserve fw-router a fixed IP via libvirt DHCP
#    MAC: 52:54:00:ca:03:ea -> 192.168.122.10
# --------------------------------------------------------------------------
echo "[3/4] Reserving fw-router DHCP address (192.168.122.10)..."
sudo virsh --connect qemu:///system net-update default add ip-dhcp-host \
    '<host mac="52:54:00:ca:03:ea" name="fw-router" ip="192.168.122.10"/>' \
    --live --config 2>/dev/null \
    && echo "      Reserved: 52:54:00:ca:03:ea -> 192.168.122.10" \
    || echo "      Already reserved (check: virsh --connect qemu:///system net-dumpxml default)"

# --------------------------------------------------------------------------
# 4. Enable VM autostart
# --------------------------------------------------------------------------
echo "[4/4] Enabling VM autostart..."
sudo virsh --connect qemu:///system autostart fw-router && echo "      fw-router: autostart enabled"
sudo virsh --connect qemu:///system autostart wazuh    && echo "      wazuh:     autostart enabled"

# Add routes immediately if virbr0 is already up
sudo ip route replace 192.168.10.0/24 via 192.168.122.10 dev virbr0 2>/dev/null && \
    echo "      Routes added immediately (virbr0 is up)" || true

echo ""
echo "=== Done. Verify with: ==="
echo "  virsh --connect qemu:///system list --all"
echo "  ip route show | grep 192.168"
echo "  ssh -i ~/.ssh/fw-router-key root@192.168.122.10 hostname"
