#!/usr/bin/env bash
#
# build-iso.sh — Build unattended Windows 11 forensic workstation ISO
#
# Reads analyst password from: pass show soc-lab/windows-analyst
# Substitutes into Autounattend.xml template, bakes into bootable ISO.
#
# Requirements: xorriso, pass, sudo access
# Usage: ./build-iso.sh <path/to/Win11_*.iso> [path/to/virtio-win.iso] [output.iso]
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <windows-iso> [virtio-win.iso] [output.iso]"
    echo "Example: $0 ~/Downloads/Win11_25H2_English_x64.iso ~/Downloads/virtio-win.iso"
    exit 1
fi

WINDOWS_ISO="$1"
VIRTIO_ISO="${2:-${HOME}/Downloads/virtio-win.iso}"
OUTPUT_ISO="${3:-${SCRIPT_DIR}/Win11_forensic_unattended.iso}"

WORK_DIR="/tmp/win11_forensic_build_$$"
WIN_MNT="${WORK_DIR}/win_mnt"
WIN_MOD="${WORK_DIR}/win_mod"
VIRTIO_MNT="${WORK_DIR}/virtio_mnt"

cleanup() {
    log_info "Cleaning up..."
    sudo umount "$WIN_MNT"    2>/dev/null || true
    sudo umount "$VIRTIO_MNT" 2>/dev/null || true
    sudo rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Verify required tools and files
for cmd in xorriso pass; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Missing required tool: $cmd"
        exit 1
    fi
done

[[ -f "$WINDOWS_ISO" ]] || { log_error "Windows ISO not found: $WINDOWS_ISO"; exit 1; }
[[ -f "$VIRTIO_ISO" ]]  || { log_error "VirtIO ISO not found: $VIRTIO_ISO";  exit 1; }
[[ -f "${SCRIPT_DIR}/Autounattend.xml" ]] || { log_error "Autounattend.xml not found"; exit 1; }

# Retrieve password from pass store (never echoed to terminal)
log_info "Reading analyst password from pass store..."
ANALYST_PASS="$(pass show soc-lab/windows-analyst)"

log_info "Building forensic workstation ISO"
log_info "Source:  $WINDOWS_ISO"
log_info "VirtIO:  $VIRTIO_ISO"
log_info "Output:  $OUTPUT_ISO"

mkdir -p "$WIN_MNT" "$WIN_MOD" "$VIRTIO_MNT"

# Mount and copy Windows ISO
log_info "Mounting Windows ISO..."
sudo mount -o loop,ro "$WINDOWS_ISO" "$WIN_MNT"

log_info "Copying Windows files (this takes a few minutes)..."
sudo cp -r "$WIN_MNT"/. "$WIN_MOD"/

# Mount VirtIO ISO and inject drivers
log_info "Injecting VirtIO drivers..."
sudo mount -o loop,ro "$VIRTIO_ISO" "$VIRTIO_MNT"
sudo cp -r "$VIRTIO_MNT"/viostor "$WIN_MOD"/
sudo cp -r "$VIRTIO_MNT"/NetKVM  "$WIN_MOD"/
sudo mkdir -p "$WIN_MOD/\$WinPEDriver\$"
sudo cp -r "$VIRTIO_MNT"/viostor/w11/amd64/. "$WIN_MOD/\$WinPEDriver\$/"
sudo cp -r "$VIRTIO_MNT"/NetKVM/w11/amd64/.  "$WIN_MOD/\$WinPEDriver\$/"
sudo umount "$VIRTIO_MNT"

# Substitute password into Autounattend.xml and add to ISO root
log_info "Generating Autounattend.xml with credentials..."
sed "s/ANALYST_PASS_PLACEHOLDER/${ANALYST_PASS}/g" \
    "${SCRIPT_DIR}/Autounattend.xml" > "${WORK_DIR}/Autounattend.xml"
sudo cp "${WORK_DIR}/Autounattend.xml" "$WIN_MOD"/

# Download and embed SPICE guest tools if available
SPICE_EXE="${HOME}/Downloads/spice-guest-tools-latest.exe"
if [[ -f "$SPICE_EXE" ]]; then
    log_info "Adding SPICE guest tools..."
    sudo cp "$SPICE_EXE" "$WIN_MOD/spice-guest-tools.exe"
else
    log_warn "SPICE guest tools not found at $SPICE_EXE — skipping (clipboard/display redirect won't work)"
    log_warn "Download from: https://www.spice-space.org/download/windows/spice-guest-tools/spice-guest-tools-latest.exe"
fi

sudo umount "$WIN_MNT"

# Build bootable ISO (UEFI + BIOS dual-boot)
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
