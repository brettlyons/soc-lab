#!/usr/bin/env bash
# build-iso.sh — Build unattended Windows 11 workstation ISO
#
# Usage: ./build-iso.sh <hostname> <windows-iso> [virtio-win.iso]
#   hostname     e.g. WIN-USER01, WIN-USER02
#   windows-iso  path to Win11_*.iso
#   virtio-iso   path to virtio-win.iso (default: soc-lab/isos/virtio-win.iso)
#
# Password read from: pass show soc-lab/windows-workstation
# Output ISO:  soc-lab/isos/<hostname>_unattended.iso
#
# Requirements: xorriso, pass, sudo access

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <hostname> <windows-iso> [virtio-win.iso]"
    echo "Example: $0 WIN-USER01 ~/Downloads/Win11_25H2_English_x64.iso"
    exit 1
fi

HOSTNAME="$1"
WINDOWS_ISO="$2"
VIRTIO_ISO="${3:-${REPO_ROOT}/isos/virtio-win.iso}"
OUTPUT_ISO="${REPO_ROOT}/isos/${HOSTNAME}_unattended.iso"

WORK_DIR="/tmp/win11_workstation_build_$$"
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

[[ -f "$WINDOWS_ISO" ]] || { log_error "Windows ISO not found: $WINDOWS_ISO"; exit 1; }
[[ -f "$VIRTIO_ISO"  ]] || { log_error "VirtIO ISO not found: $VIRTIO_ISO";  exit 1; }

log_info "Reading labadmin password from pass store..."
LABADMIN_PASS="$(pass show soc-lab/windows-workstation)"

log_info "Building workstation ISO: $HOSTNAME"
log_info "Source:  $WINDOWS_ISO"
log_info "Output:  $OUTPUT_ISO"

mkdir -p "$WIN_MNT" "$WIN_MOD" "$VIRTIO_MNT"

log_info "Mounting and copying Windows ISO..."
sudo mount -o loop,ro "$WINDOWS_ISO" "$WIN_MNT"
sudo cp -r "$WIN_MNT"/. "$WIN_MOD"/

log_info "Injecting VirtIO drivers..."
sudo mount -o loop,ro "$VIRTIO_ISO" "$VIRTIO_MNT"
sudo cp -r "$VIRTIO_MNT"/viostor "$WIN_MOD"/
sudo cp -r "$VIRTIO_MNT"/NetKVM  "$WIN_MOD"/
sudo mkdir -p "$WIN_MOD/\$WinPEDriver\$"
sudo cp -r "$VIRTIO_MNT"/viostor/w11/amd64/. "$WIN_MOD/\$WinPEDriver\$/"
sudo cp -r "$VIRTIO_MNT"/NetKVM/w11/amd64/.  "$WIN_MOD/\$WinPEDriver\$/"
sudo umount "$VIRTIO_MNT"

log_info "Generating Autounattend.xml..."
sed -e "s/HOSTNAME_PLACEHOLDER/${HOSTNAME}/g" \
    -e "s/LABADMIN_PASS_PLACEHOLDER/${LABADMIN_PASS}/g" \
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
