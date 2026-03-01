#!/usr/bin/env bash
#
# build-iso.sh - Build unattended Windows 11 ISO for Intune lab
#
# Creates a modified Windows 11 ISO with:
#   - Autounattend.xml for unattended install
#   - VirtIO drivers for QEMU/KVM
#   - SPICE guest tools for clipboard/display integration
#
# Requirements: curl, xorriso, sudo access
#
# Usage: ./build-iso.sh /path/to/Win11_24H2_English_x64.iso [output.iso]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Script directory (where Autounattend.xml lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Parse arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <windows-iso-path> [output-iso-path]"
    echo "Example: $0 ~/Downloads/Win11_24H2_English_x64.iso"
    exit 1
fi

WINDOWS_ISO="$1"
OUTPUT_ISO="${2:-${SCRIPT_DIR}/Win11_unattended.iso}"

# URLs for downloads
VIRTIO_WIN_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
SPICE_TOOLS_URL="https://www.spice-space.org/download/windows/spice-guest-tools/spice-guest-tools-latest.exe"

# Temp directories
WORK_DIR="/tmp/win11_build_$$"
WIN_MNT="${WORK_DIR}/win_mnt"
WIN_MOD="${WORK_DIR}/win_mod"
VIRTIO_MNT="${WORK_DIR}/virtio_mnt"
DOWNLOADS="${WORK_DIR}/downloads"

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    sudo umount "$WIN_MNT" 2>/dev/null || true
    sudo umount "$VIRTIO_MNT" 2>/dev/null || true
    sudo rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Check required tools
check_requirements() {
    local missing=()

    for cmd in curl xorriso; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        echo "Install them with your package manager:"
        echo "  Debian/Ubuntu: sudo apt install ${missing[*]}"
        echo "  Fedora: sudo dnf install ${missing[*]}"
        echo "  Arch: sudo pacman -S ${missing[*]}"
        echo "  NixOS: nix-shell -p ${missing[*]}"
        exit 1
    fi

    if [[ ! -f "$WINDOWS_ISO" ]]; then
        log_error "Windows ISO not found: $WINDOWS_ISO"
        exit 1
    fi

    if [[ ! -f "${SCRIPT_DIR}/Autounattend.xml" ]]; then
        log_error "Autounattend.xml not found in ${SCRIPT_DIR}"
        exit 1
    fi
}

# Download a file if not already cached
download_if_needed() {
    local url="$1"
    local dest="$2"

    if [[ -f "$dest" ]]; then
        log_info "Using cached: $(basename "$dest")"
    else
        log_info "Downloading: $(basename "$dest")"
        curl -L -o "$dest" "$url"
    fi
}

main() {
    log_info "Building unattended Windows 11 ISO"
    log_info "Source: $WINDOWS_ISO"
    log_info "Output: $OUTPUT_ISO"

    check_requirements

    # Create directories
    mkdir -p "$WIN_MNT" "$WIN_MOD" "$VIRTIO_MNT" "$DOWNLOADS"

    # Download dependencies
    download_if_needed "$VIRTIO_WIN_URL" "${DOWNLOADS}/virtio-win.iso"
    download_if_needed "$SPICE_TOOLS_URL" "${DOWNLOADS}/spice-guest-tools.exe"

    # Mount Windows ISO
    log_info "Mounting Windows ISO..."
    sudo mount -o loop,ro "$WINDOWS_ISO" "$WIN_MNT"

    # Copy Windows ISO contents
    log_info "Copying Windows files (this may take a while)..."
    sudo cp -r "$WIN_MNT"/* "$WIN_MOD"/

    # Mount VirtIO ISO
    log_info "Mounting VirtIO drivers..."
    sudo mount -o loop,ro "${DOWNLOADS}/virtio-win.iso" "$VIRTIO_MNT"

    # Add Autounattend.xml
    log_info "Adding Autounattend.xml..."
    sudo cp "${SCRIPT_DIR}/Autounattend.xml" "$WIN_MOD"/

    # Add VirtIO drivers
    log_info "Adding VirtIO drivers..."
    sudo cp -r "$VIRTIO_MNT"/viostor "$WIN_MOD"/
    sudo cp -r "$VIRTIO_MNT"/NetKVM "$WIN_MOD"/

    # Add drivers to $WinPEDriver$ for automatic loading
    log_info "Setting up WinPE driver injection..."
    sudo mkdir -p "$WIN_MOD/\$WinPEDriver\$"
    sudo cp -r "$VIRTIO_MNT"/viostor/w11/amd64/* "$WIN_MOD/\$WinPEDriver\$/"
    sudo cp -r "$VIRTIO_MNT"/NetKVM/w11/amd64/* "$WIN_MOD/\$WinPEDriver\$/"

    # Add SPICE guest tools
    log_info "Adding SPICE guest tools..."
    sudo cp "${DOWNLOADS}/spice-guest-tools.exe" "$WIN_MOD"/

    # Unmount VirtIO
    sudo umount "$VIRTIO_MNT"

    # Create the ISO
    log_info "Creating bootable ISO (this may take a few minutes)..."
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

    log_info "ISO created successfully: $OUTPUT_ISO"
    ls -lh "$OUTPUT_ISO"
}

main
