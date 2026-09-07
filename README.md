# AlmaLinux 10 Automated Build: `ansible-pull`, Himmelblau, and CIS Level 1 Hardening

This repository provides an automated, enterprise-ready build framework for **AlmaLinux 10** Workstations and Servers. It integrates:
- **Kickstart Provisioning (`ks.cfg`)**: Unattended installation with partition layout, OpenSCAP baseline (`%addon org_fedora_oscap`), and automated bootstrap.
- **`ansible-pull` Engine**: Continuous configuration convergence managed via systemd timers directly from Git.
- **Himmelblau Authentication**: Microsoft Entra ID (Azure AD) and Intune integration for desktop GDM SSO, terminal/SSH logins, MFA, and PAM/NSS resolution.
- **CIS Benchmark Level 1 Hardening**: Hardening rules aligned with Center for Internet Security (CIS) Level 1 controls and OpenSCAP SCAP Security Guide (SSG) datastreams.

---

## Directory Structure

```
.
├── kickstart/
│   └── ks.cfg                           # Automated Kickstart configuration
├── systemd/
│   ├── ansible-pull.service             # Systemd service unit for pull execution
│   └── ansible-pull.timer               # Systemd timer unit (30m cadence + on-boot)
├── ansible/
│   ├── ansible.cfg                      # Local Ansible execution configuration
│   ├── local.yml                        # Main orchestration playbook
│   ├── inventory/
│   │   └── hosts.yml                    # Localhost inventory definition
│   ├── group_vars/
│   │   ├── all.yml                      # Global baseline variables & Git repo settings
│   │   ├── himmelblau.yml               # Entra ID & Himmelblau parameters
│   │   └── cis_hardening.yml            # CIS Level 1 toggles and tuning variables
│   └── roles/
│       ├── bootstrap_pull/              # Maintains systemd timers & pull unit
│       ├── himmelblau_auth/             # Installs & configures Himmelblau PAM/NSS & daemons
│       └── cis_level1/                  # Enforces CIS Level 1 benchmark controls
├── scripts/
│   ├── generate-cis-from-oscap.sh       # Generates Ansible remediation tasks via OpenSCAP
│   ├── build-iso.sh                     # Injects Kickstart into an AlmaLinux 10 ISO
│   ├── test-in-vm.sh                    # Launches local test VM using QEMU/KVM
│   ├── bootstrap-manual.sh              # Manually triggers ansible-pull on existing system
│   └── verify-compliance.sh             # Audits CIS compliance & generates HTML report
└── tests/
    └── syntax-check.sh                  # Syntax and playbook integrity validator
```

---

## Quick Start

### 1. Configure Parameters
Edit `ansible/group_vars/all.yml` and `ansible/group_vars/himmelblau.yml` to specify your repository and Entra ID tenant settings:

```yaml
# ansible/group_vars/all.yml
ansible_pull_repo_url: "https://github.com/your-org/alma-poc.git"
ansible_pull_repo_branch: "main"

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

# Test in QEMU/KVM
bash scripts/test-in-vm.sh
```

### 5. Verify Compliance & Audit
```bash
sudo bash scripts/verify-compliance.sh
```
This generates an OpenSCAP evaluation report at `/tmp/cis-report.html`.
