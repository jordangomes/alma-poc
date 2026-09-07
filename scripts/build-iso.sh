#!/usr/bin/env bash
# ==============================================================================
# Script: build-iso.sh
# Purpose: Injects Kickstart (ks.cfg) into an AlmaLinux 10 Netinstall ISO
#          and creates a bootable, unattended installation ISO image using xorriso.
# ==============================================================================

set -euo pipefail

BASE_ISO="${1:-}"
OUTPUT_ISO="${2:-alma10-workstation-unattended.iso}"
KS_FILE="kickstart/ks.cfg"
BUILD_DIR="$(mktemp -d -t alma10-iso-build-XXXXXX)"

if [ -z "$BASE_ISO" ] || [ ! -f "$BASE_ISO" ]; then
    echo "Usage: $0 <path-to-almalinux10-boot.iso> [output-iso-name.iso]"
    echo "Example: $0 /home/jordan/Downloads/AlmaLinux-10.2-x86_64-boot.iso alma10-workstation-unattended.iso"
    exit 1
fi

if [ ! -f "$KS_FILE" ]; then
    echo "ERROR: Kickstart file $KS_FILE not found."
    exit 1
fi

if ! command -v xorriso &>/dev/null; then
    echo "ERROR: 'xorriso' command not found. Please install xorriso."
    exit 1
fi

echo "=== [ISO Builder] Preparing workspace ==="
echo "Base ISO:   $BASE_ISO"
echo "Output ISO: $OUTPUT_ISO"
echo "Kickstart:  $KS_FILE"
echo "Build Dir:  $BUILD_DIR"

trap 'rm -rf "$BUILD_DIR"' EXIT

echo "Extracting and updating GRUB configurations..."
BIOS_GRUB="$BUILD_DIR/bios-grub.cfg"
EFI_GRUB="$BUILD_DIR/efi-grub.cfg"

# Extract GRUB boot configs from base ISO
xorriso -osirrox on -indev "$BASE_ISO" \
    -extract /boot/grub2/grub.cfg "$BIOS_GRUB" \
    -extract /EFI/BOOT/grub.cfg "$EFI_GRUB" 2>/dev/null || true

# Modify BIOS GRUB config
if [ -f "$BIOS_GRUB" ]; then
    echo "Configuring BIOS GRUB menu..."
    sed -i 's/set default="1"/set default="0"/' "$BIOS_GRUB"
    sed -i 's/set timeout=60/set timeout=5/' "$BIOS_GRUB"
    sed -i 's|linux /images/pxeboot/vmlinuz inst.stage2|linux /images/pxeboot/vmlinuz inst.ks=cdrom:/ks.cfg inst.stage2|g' "$BIOS_GRUB"
fi

# Modify EFI GRUB config
if [ -f "$EFI_GRUB" ]; then
    echo "Configuring EFI GRUB menu..."
    sed -i 's/set default="1"/set default="0"/' "$EFI_GRUB"
    sed -i 's/set timeout=60/set timeout=5/' "$EFI_GRUB"
    sed -i 's|linuxefi /images/pxeboot/vmlinuz inst.stage2|linuxefi /images/pxeboot/vmlinuz inst.ks=cdrom:/ks.cfg inst.stage2|g' "$EFI_GRUB"
fi

# Remove existing output file if present to avoid xorriso media conflict
rm -f "$OUTPUT_ISO"

echo "Repacking bootable hybrid ISO with xorriso (preserving hybrid MBR/GPT/EFI boot sectors)..."
xorriso -indev "$BASE_ISO" \
    -outdev "$OUTPUT_ISO" \
    -blank as_needed \
    -map "$KS_FILE" /ks.cfg \
    -map ansible /ansible \
    ${BIOS_GRUB:+-map "$BIOS_GRUB" /boot/grub2/grub.cfg} \
    ${EFI_GRUB:+-map "$EFI_GRUB" /EFI/BOOT/grub.cfg} \
    -boot_image any replay

echo "=== [ISO Builder] ISO Created Successfully: $OUTPUT_ISO ==="
