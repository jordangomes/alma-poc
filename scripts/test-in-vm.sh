#!/usr/bin/env bash
# ==============================================================================
# Script: test-in-vm.sh
# Purpose: Spins up a local QEMU/KVM virtual machine with UEFI (OVMF) and
#          TPM 2.0 (swtpm) to test the unattended AlmaLinux 10 installation,
#          LUKS2 Full Disk Encryption, and ansible-pull convergence end-to-end.
# ==============================================================================

set -euo pipefail

ISO_PATH="alma10-workstation-unattended.iso"
DISK_PATH="alma10-test-disk.qcow2"
DISK_SIZE="50G"
RAM="4096"
CPUS="4"
SPICE_PORT="5930"
RESET_DISK=0
USE_UEFI=1
USE_TPM=1

# Parse arguments flexibly
for arg in "$@"; do
    case "$arg" in
        --reset-disk)
            RESET_DISK=1
            ;;
        --uefi)
            USE_UEFI=1
            ;;
        --bios)
            USE_UEFI=0
            ;;
        --tpm)
            USE_TPM=1
            ;;
        --no-tpm)
            USE_TPM=0
            ;;
        *.iso)
            ISO_PATH="$arg"
            ;;
        -h|--help)
            echo "Usage: $0 [options] [path-to-iso]"
            echo "Options:"
            echo "  --reset-disk    Wipe and recreate a clean virtual disk image and TPM/NVRAM state"
            echo "  --uefi          Boot in UEFI mode with OVMF (default: enabled)"
            echo "  --bios          Boot in legacy BIOS mode"
            echo "  --tpm           Enable emulated TPM 2.0 device via swtpm (default: enabled)"
            echo "  --no-tpm        Disable TPM 2.0 device"
            echo "  --help, -h      Show this help message"
            exit 0
            ;;
        *)
            if [ -f "$arg" ]; then
                ISO_PATH="$arg"
            fi
            ;;
    esac
done

if [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: ISO image not found at '$ISO_PATH'."
    echo "Please build the ISO first using 'bash scripts/build-iso.sh <base.iso>' or specify an ISO path."
    exit 1
fi

# Locate QEMU binary
QEMU_BIN=""
for candidate in /usr/libexec/qemu-kvm /usr/bin/qemu-kvm qemu-kvm qemu-system-x86_64; do
    if command -v "$candidate" &>/dev/null || [ -x "$candidate" ]; then
        QEMU_BIN="$candidate"
        break
    fi
done

if [ -z "$QEMU_BIN" ]; then
    echo "ERROR: QEMU binary not found."
    echo "Please install qemu-kvm: sudo dnf install -y qemu-kvm qemu-img virt-viewer"
    exit 1
fi

if ! command -v qemu-img &>/dev/null; then
    echo "ERROR: 'qemu-img' not found. Please install qemu-img: sudo dnf install -y qemu-img"
    exit 1
fi

echo "=== [VM Tester] Preparing QEMU test environment ==="
echo "QEMU Binary: $QEMU_BIN"
echo "ISO Image:   $ISO_PATH"
echo "Disk Image:  $DISK_PATH ($DISK_SIZE)"
echo "Memory:      ${RAM}MB"
echo "CPUs:        $CPUS"
echo "Machine:     q35 (Modern PCIe)"
echo "Firmware:    $([ "$USE_UEFI" -eq 1 ] && echo 'UEFI (OVMF)' || echo 'Legacy BIOS')"
echo "TPM 2.0:     $([ "$USE_TPM" -eq 1 ] && echo 'Enabled (swtpm)' || echo 'Disabled')"
echo "SPICE Port:  127.0.0.1:${SPICE_PORT}"
echo "SSH Port:    localhost:2222 -> VM:22"

if [ "$RESET_DISK" -eq 1 ] || [ ! -f "$DISK_PATH" ]; then
    echo "Creating clean virtual disk ($DISK_SIZE)..."
    rm -f "$DISK_PATH"
    qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE"
else
    echo "Using existing virtual disk: $DISK_PATH (use --reset-disk to wipe and re-create)"
fi

# Determine acceleration (KVM or TCG fallback)
KVM_FLAG="-accel tcg"
if [ -w /dev/kvm ] || [ -r /dev/kvm ]; then
    KVM_FLAG="-enable-kvm"
fi

# Setup UEFI (OVMF) if enabled
UEFI_ARGS=()
VARS_PATH="alma10-ovmf-vars.fd"
if [ "$USE_UEFI" -eq 1 ]; then
    OVMF_CODE=""
    OVMF_VARS_TEMPLATE=""
    for code_cand in \
        /usr/share/edk2/ovmf/OVMF_CODE.secboot.fd \
        /usr/share/edk2/ovmf/OVMF_CODE.fd \
        /usr/share/OVMF/OVMF_CODE.secboot.fd \
        /usr/share/OVMF/OVMF_CODE.fd; do
        if [ -f "$code_cand" ]; then
            OVMF_CODE="$code_cand"
            break
        fi
    done

    for vars_cand in \
        /usr/share/edk2/ovmf/OVMF_VARS.secboot.fd \
        /usr/share/edk2/ovmf/OVMF_VARS.fd \
        /usr/share/OVMF/OVMF_VARS.secboot.fd \
        /usr/share/OVMF/OVMF_VARS.fd; do
        if [ -f "$vars_cand" ]; then
            OVMF_VARS_TEMPLATE="$vars_cand"
            break
        fi
    done

    if [ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS_TEMPLATE" ]; then
        if [ "$RESET_DISK" -eq 1 ] || [ ! -f "$VARS_PATH" ]; then
            echo "Initializing fresh UEFI NVRAM variables from template..."
            cp "$OVMF_VARS_TEMPLATE" "$VARS_PATH"
        fi
        UEFI_ARGS=(
            -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE"
            -drive if=pflash,format=raw,file="$VARS_PATH"
        )
    else
        echo "WARNING: OVMF firmware not found in standard paths. Falling back to BIOS mode."
        USE_UEFI=0
    fi
fi

# Setup TPM 2.0 (swtpm) if enabled
TPM_ARGS=()
SWTPM_PID=""
TPM_STATE_DIR="$(pwd)/.alma10-tpm-state"
TPM_SOCK="$TPM_STATE_DIR/swtpm-sock"

if [ "$USE_TPM" -eq 1 ]; then
    if command -v swtpm &>/dev/null; then
        if [ "$RESET_DISK" -eq 1 ]; then
            echo "Resetting TPM 2.0 state directory..."
            rm -rf "$TPM_STATE_DIR"
        fi
        mkdir -p "$TPM_STATE_DIR"
        rm -f "$TPM_SOCK"

        echo "Starting background swtpm TPM 2.0 emulator..."
        swtpm socket \
            --tpm2 \
            --tpmstate dir="$TPM_STATE_DIR" \
            --ctrl type=unixio,path="$TPM_SOCK" \
            --log level=5 &
        SWTPM_PID=$!
        sleep 0.5

        TPM_ARGS=(
            -chardev "socket,id=chrtpm,path=$TPM_SOCK"
            -tpmdev "emulator,id=tpm0,chardev=chrtpm"
            -device "tpm-tis,tpmdev=tpm0"
        )
    else
        echo "WARNING: 'swtpm' command not found. TPM 2.0 emulation disabled."
        USE_TPM=0
    fi
fi

# Spawn graphical viewer (remote-viewer / virt-viewer) if running under GUI
VIEWER_PID=""
if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if command -v remote-viewer &>/dev/null; then
        (
            sleep 1.5
            remote-viewer "spice://127.0.0.1:${SPICE_PORT}" --title="AlmaLinux 10 Workstation VM" >/dev/null 2>&1 || true
        ) &
        VIEWER_PID=$!
    elif command -v virt-viewer &>/dev/null; then
        (
            sleep 1.5
            virt-viewer --connect=spice://127.0.0.1:${SPICE_PORT} >/dev/null 2>&1 || true
        ) &
        VIEWER_PID=$!
    fi
fi

cleanup() {
    echo "Shutting down VM resources..."
    if [ -n "$VIEWER_PID" ] && kill -0 "$VIEWER_PID" 2>/dev/null; then
        kill "$VIEWER_PID" 2>/dev/null || true
    fi
    if [ -n "$SWTPM_PID" ] && kill -0 "$SWTPM_PID" 2>/dev/null; then
        kill "$SWTPM_PID" 2>/dev/null || true
    fi
    rm -f "$TPM_SOCK" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "Launching QEMU Virtual Machine..."
"$QEMU_BIN" \
    -machine q35 \
    $KVM_FLAG \
    -m "$RAM" \
    -smp "$CPUS" \
    -cpu host \
    "${UEFI_ARGS[@]}" \
    "${TPM_ARGS[@]}" \
    -drive file="$DISK_PATH",format=qcow2,if=virtio \
    -cdrom "$ISO_PATH" \
    -boot order=c,once=d \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -vga virtio \
    -spice "port=${SPICE_PORT},addr=127.0.0.1,disable-ticketing=on"
