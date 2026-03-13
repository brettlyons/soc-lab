#!/usr/bin/env bash
# build-iso.sh — Build unattended Windows Server 2022 DC01 ISO
#
# Usage: ./build-iso.sh <winserver-iso> [virtio-win.iso]
#   winserver-iso  path to WindowsServer2022*.iso (eval from Microsoft Eval Center)
#   virtio-iso     path to virtio-win.iso (default: soc-lab/isos/virtio-win.iso)
#
# Password read from: pass show soc-lab/dc01-admin
# Output ISO: soc-lab/isos/DC01_unattended.iso
#
# Requirements: xorriso, pass, sudo access

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <winserver2022-iso> [virtio-win.iso]"
    echo "Download eval ISO from: https://www.microsoft.com/en-us/evalcenter/"
    exit 1
fi

WINDOWS_ISO="$1"
VIRTIO_ISO="${2:-${REPO_ROOT}/isos/virtio-win.iso}"
OUTPUT_ISO="${REPO_ROOT}/isos/DC01_unattended.iso"

WORK_DIR="/tmp/win2022_dc01_build_$$"
WIN_MNT="${WORK_DIR}/win_mnt"
WIN_MOD="${WORK_DIR}/win_mod"
VIRTIO_MNT="${WORK_DIR}/virtio_mnt"

cleanup() {
    sudo umount "$WIN_MNT"    2>/dev/null || true
    sudo umount "$VIRTIO_MNT" 2>/dev/null || true
    sudo rm -rf "$WORK_DIR"
}
trap cleanup EXIT

for cmd in xorriso pass; do
    command -v "$cmd" &>/dev/null || { log_error "Missing: $cmd"; exit 1; }
done

[[ -f "$WINDOWS_ISO" ]] || { log_error "Windows Server ISO not found: $WINDOWS_ISO"; exit 1; }
[[ -f "$VIRTIO_ISO"  ]] || { log_error "VirtIO ISO not found: $VIRTIO_ISO"; exit 1; }

log_info "Reading DC01 admin password from pass store..."
DC01_PASS="$(pass show soc-lab/dc01-admin)"

log_info "Building DC01 ISO"
log_info "Source:  $WINDOWS_ISO"
log_info "Output:  $OUTPUT_ISO"

mkdir -p "$WIN_MNT" "$WIN_MOD" "$VIRTIO_MNT"

log_info "Mounting and copying Windows Server ISO..."
sudo mount -o loop,ro "$WINDOWS_ISO" "$WIN_MNT"
sudo cp -r "$WIN_MNT"/. "$WIN_MOD"/

log_info "Injecting VirtIO drivers (2k22)..."
sudo mount -o loop,ro "$VIRTIO_ISO" "$VIRTIO_MNT"
sudo cp -r "$VIRTIO_MNT"/viostor "$WIN_MOD"/
sudo cp -r "$VIRTIO_MNT"/NetKVM  "$WIN_MOD"/
sudo mkdir -p "$WIN_MOD/\$WinPEDriver\$"
sudo cp -r "$VIRTIO_MNT"/viostor/2k22/amd64/. "$WIN_MOD/\$WinPEDriver\$/"
sudo cp -r "$VIRTIO_MNT"/NetKVM/2k22/amd64/.  "$WIN_MOD/\$WinPEDriver\$/"
sudo umount "$VIRTIO_MNT"

log_info "Generating Autounattend.xml with credentials..."
sed "s/DC01_ADMIN_PASS_PLACEHOLDER/${DC01_PASS}/g" \
    "${SCRIPT_DIR}/Autounattend.xml" > "${WORK_DIR}/Autounattend.xml"
sudo cp "${WORK_DIR}/Autounattend.xml" "$WIN_MOD"/

sudo umount "$WIN_MNT"

log_info "Creating bootable ISO..."
xorriso -as mkisofs \
    -iso-level 4 \
    -rock \
    -disable-deep-relocation \
    -untranslated-filenames \
    -b boot/etfsboot.com \
    -no-emul-boot \
    -boot-load-size 8 \
    -eltorito-alt-boot \
    -eltorito-platform efi \
    -b efi/microsoft/boot/efisys_noprompt.bin \
    -no-emul-boot \
    -o "$OUTPUT_ISO" \
    "$WIN_MOD"

log_info "Done: $OUTPUT_ISO"
ls -lh "$OUTPUT_ISO"
log_warn "After VM boots and promotes to DC, update dnsmasq.conf to forward lab.local -> 192.168.10.20"
