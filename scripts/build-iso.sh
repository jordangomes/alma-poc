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

# Extract boot configs from base ISO (GRUB and ISOLINUX)
ISOLINUX_CFG="$BUILD_DIR/isolinux.cfg"

xorriso -osirrox on -indev "$BASE_ISO" \
    -extract /boot/grub2/grub.cfg "$BIOS_GRUB" \
    -extract /EFI/BOOT/grub.cfg "$EFI_GRUB" \
    -extract /isolinux/isolinux.cfg "$ISOLINUX_CFG" 2>/dev/null || true

# Determine ISO Volume Label so inst.ks works identically on both USB drives and CD-ROMs
ISO_LABEL=$(grep -h -o -E 'inst\.stage2=hd:LABEL=[^ ]+' "$BIOS_GRUB" "$EFI_GRUB" "$ISOLINUX_CFG" 2>/dev/null | head -n 1 | sed 's/inst\.stage2=hd:LABEL=//' | tr -d '"'\''\r\n' || true)
if [ -z "$ISO_LABEL" ]; then
    ISO_LABEL=$(xorriso -indev "$BASE_ISO" -pvd_info 2>/dev/null | grep -i 'Volume Id' | sed 's/.*Volume Id[ ]*:[ ]*//' | tr -d '"'\''\r\n' || true)
fi

if [ -n "$ISO_LABEL" ]; then
    echo "Detected ISO Volume Label: $ISO_LABEL"
    KS_PARAM="inst.ks=hd:LABEL=${ISO_LABEL}:/ks.cfg"
else
    echo "Warning: Could not determine ISO Volume Label. Falling back to cdrom:/ks.cfg"
    KS_PARAM="inst.ks=cdrom:/ks.cfg"
fi

# Modify BIOS GRUB config
if [ -f "$BIOS_GRUB" ]; then
    echo "Configuring BIOS GRUB menu..."
    sed -i 's/set default="1"/set default="0"/' "$BIOS_GRUB"
    sed -i 's/set timeout=60/set timeout=5/' "$BIOS_GRUB"
    sed -i 's/menuentry '\''Install AlmaLinux 10/menuentry '\''Install AlmaLinux 10 Workstation (Automated CIS Hardened)/' "$BIOS_GRUB"
    sed -i "s|linux /images/pxeboot/vmlinuz |linux /images/pxeboot/vmlinuz $KS_PARAM |g" "$BIOS_GRUB"
fi

# Modify EFI GRUB config
if [ -f "$EFI_GRUB" ]; then
    echo "Configuring EFI GRUB menu..."
    sed -i 's/set default="1"/set default="0"/' "$EFI_GRUB"
    sed -i 's/set timeout=60/set timeout=5/' "$EFI_GRUB"
    sed -i 's/menuentry '\''Install AlmaLinux 10/menuentry '\''Install AlmaLinux 10 Workstation (Automated CIS Hardened)/' "$EFI_GRUB"
    sed -i "s|linuxefi /images/pxeboot/vmlinuz |linuxefi /images/pxeboot/vmlinuz $KS_PARAM |g" "$EFI_GRUB"
    sed -i "s|linux /images/pxeboot/vmlinuz |linux /images/pxeboot/vmlinuz $KS_PARAM |g" "$EFI_GRUB"
fi

# Modify ISOLINUX config (if present for legacy BIOS)
if [ -f "$ISOLINUX_CFG" ]; then
    echo "Configuring ISOLINUX menu..."
    sed -i 's/default vesamenu.c32/default linux/' "$ISOLINUX_CFG" 2>/dev/null || true
    sed -i 's/timeout 600/timeout 50/' "$ISOLINUX_CFG" 2>/dev/null || true
    sed -i "s|append initrd=initrd.img |append initrd=initrd.img $KS_PARAM |g" "$ISOLINUX_CFG"
fi

# Remove existing output file if present to avoid xorriso media conflict
rm -f "$OUTPUT_ISO"

# Build xorriso map arguments only for files that actually exist
XORRISO_MAP_ARGS=()
XORRISO_MAP_ARGS+=(-map "$KS_FILE" /ks.cfg)
XORRISO_MAP_ARGS+=(-map ansible /ansible)

if [ -f "$BIOS_GRUB" ]; then
    XORRISO_MAP_ARGS+=(-map "$BIOS_GRUB" /boot/grub2/grub.cfg)
fi
if [ -f "$EFI_GRUB" ]; then
    XORRISO_MAP_ARGS+=(-map "$EFI_GRUB" /EFI/BOOT/grub.cfg)
fi
if [ -f "$ISOLINUX_CFG" ]; then
    XORRISO_MAP_ARGS+=(-map "$ISOLINUX_CFG" /isolinux/isolinux.cfg)
fi

echo "Repacking bootable hybrid ISO with xorriso (preserving hybrid MBR/GPT/EFI boot sectors)..."
xorriso -indev "$BASE_ISO" \
    -outdev "$OUTPUT_ISO" \
    -blank as_needed \
    "${XORRISO_MAP_ARGS[@]}" \
    -boot_image any replay

echo "=== [ISO Builder] ISO Created Successfully: $OUTPUT_ISO ==="
