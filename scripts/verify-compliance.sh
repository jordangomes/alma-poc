#!/usr/bin/env bash
# ==============================================================================
# Script: verify-compliance.sh
# Purpose: Comprehensive audit of AlmaLinux 10 build state:
#          - ansible-pull systemd units
#          - Himmelblau daemon & authselect status
#          - OpenSCAP CIS Level 1 Workstation compliance evaluation
#          - UEFI, TPM 2.0, LUKS2 Full Disk Encryption & Recovery Escrow
# ==============================================================================

set -uo pipefail

echo "================================================================================"
echo "          AlmaLinux 10 Workstation Compliance & State Verification              "
echo "================================================================================"

echo ""
echo "--- [1/5] Checking ansible-pull Systemd Units ---"
systemctl status ansible-pull.timer --no-pager || echo "ansible-pull.timer: Inactive or missing"
systemctl status ansible-pull.service --no-pager || echo "ansible-pull.service: Not running (oneshot)"

echo ""
echo "--- [2/5] Checking Himmelblau Authentication & Daemons ---"
systemctl is-active himmelblaud >/dev/null 2>&1 && systemctl status himmelblaud --no-pager || echo "himmelblaud: Inactive / Not running"
if command -v authselect &>/dev/null; then
    echo "Current Authselect Profile:"
    authselect current || true
fi

echo ""
echo "--- [3/5] Checking Core CIS Hardening Parameters ---"
echo "Sysctl net.ipv4.ip_forward: $(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 'N/A')"
echo "Sysctl kernel.randomize_va_space: $(sysctl -n kernel.randomize_va_space 2>/dev/null || echo 'N/A')"
echo "Sysctl fs.suid_dumpable: $(sysctl -n fs.suid_dumpable 2>/dev/null || echo 'N/A')"
if command -v auditctl &>/dev/null; then
    echo "Audit Rules Count: $(auditctl -l 2>/dev/null | wc -l)"
fi

echo ""
echo "--- [4/5] Checking UEFI, TPM 2.0, LUKS2 FDE & Key Escrow ---"
echo "Boot Mode:"
if [ -d "/sys/firmware/efi" ]; then
    echo "  [PASS] Booted in UEFI Mode"
else
    echo "  [INFO] Booted in Legacy BIOS Mode"
fi

echo "Secure Boot Status:"
if command -v mokutil &>/dev/null; then
    mokutil --sb-state 2>/dev/null || echo "  Unable to query Secure Boot state"
else
    echo "  mokutil not installed"
fi

echo "TPM 2.0 Device:"
if [ -e "/dev/tpmrm0" ] || [ -e "/dev/tpm0" ]; then
    echo "  [PASS] TPM 2.0 device present (/dev/tpmrm0 or /dev/tpm0)"
    if command -v tpm2_pcrread &>/dev/null; then
        echo "  Reading PCR 0, 2, 7 (sha256):"
        tpm2_pcrread sha256:0,2,7 2>/dev/null || echo "  (TPM PCR read requires appropriate privileges)"
    fi
else
    echo "  [WARN] No TPM 2.0 device detected"
fi

echo "Full Disk Encryption (LUKS2):"
LUKS_DEVS=$(blkid -t TYPE=crypto_LUKS -o device 2>/dev/null || true)
if [ -n "$LUKS_DEVS" ]; then
    for dev in $LUKS_DEVS; do
        echo "  [PASS] Encrypted LUKS device found: $dev"
        if command -v cryptsetup &>/dev/null; then
            echo "  Tokens & Keyslots in $dev:"
            cryptsetup luksDump "$dev" 2>/dev/null | grep -E "systemd-tpm2|systemd-recovery|Keyslot:|Token:" || true
        fi
    done
else
    echo "  [WARN] No crypto_LUKS block devices detected"
fi

echo "Recovery Key Escrow File:"
if [ -f "/root/.luks-recovery-key.txt" ]; then
    PERMS=$(stat -c "%a" /root/.luks-recovery-key.txt 2>/dev/null || echo "N/A")
    echo "  [PASS] /root/.luks-recovery-key.txt exists (permissions: $PERMS)"
else
    echo "  [INFO] No local recovery key file at /root/.luks-recovery-key.txt"
fi

echo "/etc/crypttab Configuration:"
if [ -f "/etc/crypttab" ]; then
    cat /etc/crypttab
else
    echo "  /etc/crypttab not present"
fi

echo ""
echo "--- [5/5] Running OpenSCAP CIS Level 1 Compliance Scan ---"
DS_SEARCH_PATHS=(
    "/usr/share/xml/scap/ssg/content/ssg-almalinux10-ds.xml"
    "/usr/share/xml/scap/ssg/content/ssg-cs10-ds.xml"
    "/usr/share/xml/scap/ssg/content/ssg-rhel10-ds.xml"
    "/usr/share/xml/scap/ssg/content/ssg-almalinux9-ds.xml"
)

DS_PATH=""
for path in "${DS_SEARCH_PATHS[@]}"; do
    if [ -f "$path" ]; then
        DS_PATH="$path"
        break
    fi
done

if [ -n "$DS_PATH" ] && command -v oscap &>/dev/null; then
    REPORT_FILE="/tmp/compliance-report.html"
    RESULTS_FILE="/tmp/compliance-results.xml"
    PROFILE="${1:-xccdf_org.ssgproject.content_profile_cis_workstation_l1}"

    echo "Running oscap xccdf eval with profile: $PROFILE"
    echo "Using DataStream: $DS_PATH..."
    oscap xccdf eval \
        --profile "$PROFILE" \
        --results "$RESULTS_FILE" \
        --report "$REPORT_FILE" \
        "$DS_PATH" || true

    echo "OpenSCAP Scan Report generated at: $REPORT_FILE"
    echo "OpenSCAP Scan Results XML at:      $RESULTS_FILE"
else
    echo "WARNING: oscap or SCAP datastream not installed. Skipping OpenSCAP HTML evaluation."
    echo "Install with: sudo dnf install -y openscap-scanner scap-security-guide"
fi

echo ""
echo "================================================================================"
echo " Verification Complete. Review the results above or check /tmp/compliance-report.html "
echo "================================================================================"
