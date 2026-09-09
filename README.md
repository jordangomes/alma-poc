# AlmaLinux 10 Automated Build: `ansible-pull`, Himmelblau, TPM 2.0 FDE, and OpenSCAP Baseline Hardening

This repository provides an automated, enterprise-ready build framework for **AlmaLinux 10** Workstations and Servers. It integrates:
- **Kickstart Provisioning (`ks.cfg`)**: Unattended installation with GPT layout, LUKS2 Full Disk Encryption, OpenSCAP compliance baseline (`%addon org_fedora_oscap`), and automated bootstrap.
- **UEFI & TPM 2.0 Auto-Unlock (`systemd-cryptenroll`)**: Measured boot hardware binding against PCRs `0+2+7` (Firmware, Option ROMs, Secure Boot) for zero-touch auto-unlocking at boot.
- **BitLocker-Style Recovery Keys & Escrow**: Unique per-machine 128-bit Base32 recovery keys (`xxxxxx-xxxxxx-...`) enrolled in LUKS2 and escrowed locally to `/root/.luks-recovery-key.txt` (or enterprise vault/webhook).
- **`ansible-pull` Engine**: Continuous configuration convergence managed via systemd timers directly from Git.
- **Himmelblau Authentication**: Microsoft Entra ID (Azure AD) and Intune integration for desktop GDM SSO, terminal/SSH logins, MFA, and PAM/NSS resolution.
- **OpenSCAP Baseline Hardening**: Automated compliance baseline (CIS Level 1, STIG, Essential Eight) generated directly from official SCAP Security Guide (SSG) datastreams.

---

## Directory Structure

```
.
├── kickstart/
│   └── ks.cfg                           # Automated Kickstart configuration (GPT + LUKS2)
├── systemd/
│   ├── ansible-pull.service             # Systemd service unit for pull execution
│   └── ansible-pull.timer               # Systemd timer unit (30m cadence + on-boot)
├── ansible/
│   ├── ansible.cfg                      # Local Ansible execution configuration
│   ├── local.yml                        # Main orchestration playbook
│   ├── oscap_baseline.yml               # OpenSCAP-generated compliance remediation playbook
│   ├── inventory/
│   │   └── hosts.yml                    # Localhost inventory definition
│   ├── group_vars/
│   │   ├── all.yml                      # Global baseline variables & Git repo settings
│   │   ├── himmelblau.yml               # Entra ID & Himmelblau parameters
│   │   └── security.yml                 # OpenSCAP, TPM 2.0 & LUKS2 FDE parameters
│   └── roles/
│       ├── tpm_fde/                     # Enrolls TPM2 auto-unlock & BitLocker-style recovery keys
│       ├── bootstrap_pull/              # Maintains systemd timers & pull unit
│       ├── himmelblau_auth/             # Installs & configures Himmelblau PAM/NSS & daemons
│       └── workstation_baseline/        # Enterprise workstation overrides & adjustments
├── scripts/
│   ├── generate-oscap-playbook.sh       # Generates oscap_baseline.yml via OpenSCAP
│   ├── build-iso.sh                     # Injects Kickstart into an AlmaLinux 10 ISO
│   ├── test-in-vm.sh                    # Launches local test VM using QEMU/KVM with OVMF UEFI & swtpm
│   ├── bootstrap-manual.sh              # Manually triggers ansible-pull on existing system
│   └── verify-compliance.sh             # Audits compliance, TPM2/LUKS2 state & generates HTML report
└── tests/
    └── syntax-check.sh                  # Syntax and playbook integrity validator
```

---

## Quick Start

### 1. Configure Parameters
Edit `ansible/group_vars/all.yml`, `ansible/group_vars/security.yml`, and `ansible/group_vars/himmelblau.yml` to specify your repository, TPM/FDE, and Entra ID tenant settings:

```yaml
# ansible/group_vars/all.yml
ansible_pull_repo_url: "https://github.com/your-org/alma-poc.git"
ansible_pull_repo_branch: "main"

# ansible/group_vars/security.yml
tpm_fde_enabled: true
tpm_fde_pcrs: "0+2+7"
tpm_fde_generate_recovery_key: true
tpm_fde_escrow_backend: "local"

# ansible/group_vars/himmelblau.yml
himmelblau_domain: "yourdomain.onmicrosoft.com"
himmelblau_tenant_id: "00000000-0000-0000-0000-000000000000"
himmelblau_app_id: "optional-app-client-id"
```

### 2. Validate Playbook Syntax
```bash
bash tests/syntax-check.sh
```

### 3. Run on an Existing Machine
Run the manual bootstrap script to install dependencies and execute `ansible-pull`:
```bash
sudo bash scripts/bootstrap-manual.sh
```

### 4. Build a Custom Kickstart ISO & Test in VM
```bash
# Remaster ISO with embedded ks.cfg
bash scripts/build-iso.sh /path/to/AlmaLinux-10-x86_64-netinst.iso

# Test in QEMU/KVM with UEFI (OVMF) and virtual TPM 2.0 (swtpm)
bash scripts/test-in-vm.sh --reset-disk
```

### 5. Verify Compliance, TPM 2.0 & FDE
```bash
sudo bash scripts/verify-compliance.sh
```
This audits:
1. `ansible-pull` systemd service and timer status
2. Himmelblau Entra ID authentication and PAM profiles
3. CIS Benchmark Level 1 kernel parameters and audit rules
4. UEFI boot mode, Secure Boot, TPM 2.0 device presence, LUKS2 keyslots (`systemd-tpm2`, `systemd-recovery`), and local recovery key escrow file
5. OpenSCAP CIS evaluation report generated at `/tmp/compliance-report.html`

---

## Security & Encryption Architecture

### TPM 2.0 Measured Boot Policy
The LUKS2 volume key is sealed against PCRs:
- **PCR 0**: Core system firmware executable code
- **PCR 2**: Option ROMs and UEFI drivers
- **PCR 7**: Secure Boot state and certificates (PK, KEK, db, dbx)

If firmware or certificates change, the system falls back to the console recovery prompt.

### BitLocker-Style Recovery Key Escrow
Each system receives a unique, 128-bit Base32 recovery key formatted as `xxxxxx-xxxxxx-xxxxxx-xxxxxx-xxxxxx-xxxxxx-xxxxxx-xxxxxx`.
- **Local storage**: Saved to `/root/.luks-recovery-key.txt` (mode `0400`).
- **Disaster Recovery**: Allows manual unlocking if TPM PCR measurements fail.
