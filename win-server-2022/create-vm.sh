#!/usr/bin/env bash
# create-vm.sh — Create and boot the dc01 KVM VM
#
# Run AFTER build-iso.sh has produced isos/DC01_unattended.iso.
#
# Usage: ./create-vm.sh
#
# IMPORTANT GOTCHAS (learned the hard way):
#
# 1. Do NOT use --cdrom or vol= for the ISO. If you later run:
#      virsh undefine dc01 --remove-all-storage --nvram
#    libvirt will DELETE any storage volumes it "owns" — including the ISO
#    if it was registered as a volume. Use --disk path=...,device=cdrom
#    so the ISO stays as a plain file libvirt doesn't track.
#
# 2. Destroying with --nvram is required for UEFI VMs. Without --nvram,
#    undefine fails: "cannot undefine domain with nvram".
#
# 3. Use path= for the main disk too, not vol=, for the same reason.
#    qemu-img create the disk first, then reference it by path.
#
# 4. The VM is created with --noreboot so it runs the install then stops.
#    Start manually after: virsh --connect qemu:///system start dc01
#    (install reboots happen automatically during Windows setup)
#
# Rebuild workflow (if you need to start over):
#   virsh --connect qemu:///system destroy dc01 2>/dev/null
#   virsh --connect qemu:///system undefine dc01 --nvram
#   rm -f /var/lib/libvirt/images/soc-lab/dc01.qcow2
#   bash win-server-2022/build-iso.sh <eval-iso> [virtio-iso]
#   bash win-server-2022/create-vm.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DISK=/var/lib/libvirt/images/soc-lab/dc01.qcow2
ISO="${REPO_ROOT}/isos/DC01_unattended.iso"
MAC=52:54:00:b6:10:1e   # dnsmasq reservation → 192.168.10.20

[[ -f "$ISO" ]] || { echo "ERROR: ISO not found: $ISO — run build-iso.sh first"; exit 1; }

# Remove any stale VM definition (ignore errors if it doesn't exist)
virsh --connect qemu:///system destroy dc01 2>/dev/null || true
virsh --connect qemu:///system undefine dc01 --nvram 2>/dev/null || true
rm -f "$DISK"

echo "Creating disk: $DISK (60GB)"
qemu-img create -f qcow2 "$DISK" 60G

echo "Creating VM dc01..."
virt-install \
  --connect qemu:///system \
  --name dc01 \
  --memory 4096 \
  --vcpus 2 \
  --disk path="${DISK}",bus=virtio \
  --disk path="${ISO}",device=cdrom,readonly=on \
  --os-variant win2k22 \
  --network network=lab-net,model=virtio,mac="${MAC}" \
  --graphics spice \
  --video qxl \
  --boot uefi \
  --noautoconsole \
  --noreboot

echo ""
echo "DC01 VM created. Windows install is running."
echo "Watch progress: virt-manager (connect to dc01)"
echo ""
echo "After install completes and DC promotion reboots finish (~15-20 min):"
echo "  1. Verify: ping dc01.lab.local from host"
echo "  2. RDP:    bash scripts/rdp.sh  (select dc01)"
echo "  3. Update dnsmasq to forward lab.local → 192.168.10.20 (DC01 AD DNS)"
