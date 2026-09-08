#!/usr/bin/env bash
# ==============================================================================
# Script: bootstrap-manual.sh
# Purpose: Manually bootstrap and trigger ansible-pull on any existing AlmaLinux 10 machine.
# ==============================================================================

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (or via sudo)."
    exit 1
fi

GIT_REPO="${1:-https://github.com/example-org/alma-poc.git}"
GIT_BRANCH="${2:-main}"
LOCAL_ANSIBLE_DIR="/var/lib/ansible/local"

echo "=== [Manual Bootstrap] Starting AlmaLinux 10 ansible-pull bootstrap ==="
echo "Repository: $GIT_REPO"
echo "Branch:     $GIT_BRANCH"

echo "1. Installing prerequisite packages (git, ansible-core, epel-release, python3)..."
dnf install -y git ansible-core epel-release python3 python3-pip authselect chrony audit aide

mkdir -p /etc/ansible
cat <<'EOF' > /etc/ansible/ansible.cfg
[defaults]
inventory = /var/lib/ansible/local/ansible/inventory/hosts.yml
interpreter_python = auto_silent
retry_files_enabled = False
stdout_callback = default
callbacks_enabled = timer, profile_tasks
roles_path = /var/lib/ansible/local/ansible/roles
collections_path = /var/lib/ansible/local/ansible/collections:/usr/share/ansible/collections:~/.ansible/collections
EOF

echo "2. Setting up local repository at $LOCAL_ANSIBLE_DIR..."
mkdir -p "$LOCAL_ANSIBLE_DIR"

if [ -d "$LOCAL_ANSIBLE_DIR/.git" ]; then
    echo "Existing git repository found. Pulling latest changes..."
    git -C "$LOCAL_ANSIBLE_DIR" pull --rebase
else
    echo "Cloning repository..."
    git clone -b "$GIT_BRANCH" "$GIT_REPO" "$LOCAL_ANSIBLE_DIR"
fi

echo "3. Installing required Ansible collections (community.general, ansible.posix)..."
if [ -f "$LOCAL_ANSIBLE_DIR/ansible/requirements.yml" ]; then
    ansible-galaxy collection install -r "$LOCAL_ANSIBLE_DIR/ansible/requirements.yml" -p /usr/share/ansible/collections
fi

echo "4. Executing local playbook..."
ansible-playbook \
    -i "$LOCAL_ANSIBLE_DIR/ansible/inventory/hosts.yml" \
    "$LOCAL_ANSIBLE_DIR/ansible/local.yml" \
    --connection=local

echo "=== [Manual Bootstrap] Completed Successfully ==="
