# AlmaLinux 10 Automated Build: `ansible-pull`, Himmelblau, and OpenSCAP Baseline Hardening

This repository provides an automated, enterprise-ready build framework for **AlmaLinux 10** Workstations and Servers. It integrates:
- **Kickstart Provisioning (`ks.cfg`)**: Unattended installation with partition layout, OpenSCAP compliance baseline (`%addon org_fedora_oscap`), and automated bootstrap.
- **`ansible-pull` Engine**: Continuous configuration convergence managed via systemd timers directly from Git.
- **Himmelblau Authentication**: Microsoft Entra ID (Azure AD) and Intune integration for desktop GDM SSO, terminal/SSH logins, MFA, and PAM/NSS resolution.
- **OpenSCAP Baseline Hardening**: Automated compliance baseline (CIS Level 1, STIG, Essential Eight) generated directly from official SCAP Security Guide (SSG) datastreams.

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
│   ├── oscap_baseline.yml               # OpenSCAP-generated compliance remediation playbook
│   ├── inventory/
│   │   └── hosts.yml                    # Localhost inventory definition
│   ├── group_vars/
│   │   ├── all.yml                      # Global baseline variables & Git repo settings
│   │   ├── himmelblau.yml               # Entra ID & Himmelblau parameters
│   │   └── security.yml                 # OpenSCAP profile and security parameters
│   └── roles/
│       ├── bootstrap_pull/              # Maintains systemd timers & pull unit
│       ├── himmelblau_auth/             # Installs & configures Himmelblau PAM/NSS & daemons
│       └── workstation_baseline/        # Enterprise workstation overrides & adjustments
├── scripts/
│   ├── generate-oscap-playbook.sh       # Generates oscap_baseline.yml via OpenSCAP
│   ├── build-iso.sh                     # Injects Kickstart into an AlmaLinux 10 ISO
│   ├── test-in-vm.sh                    # Launches local test VM using QEMU/KVM
│   ├── bootstrap-manual.sh              # Manually triggers ansible-pull on existing system
│   └── verify-compliance.sh             # Audits compliance & generates HTML report
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
This generates an OpenSCAP evaluation report at `/tmp/compliance-report.html`.

