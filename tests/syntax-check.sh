#!/usr/bin/env bash
# ==============================================================================
# Script: syntax-check.sh
# Purpose: Validates YAML syntax and checks Ansible playbooks/roles integrity.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== [Syntax Validator] Checking AlmaLinux 10 Build Configuration ==="

# 1. Check if python3 and pyyaml / ansible are installed
if command -v ansible-playbook &>/dev/null; then
    echo "Running ansible-playbook --syntax-check on ansible/local.yml..."
    ansible-playbook -i "$REPO_ROOT/ansible/inventory/hosts.yml" "$REPO_ROOT/ansible/local.yml" --syntax-check
    echo "Ansible syntax check passed!"
else
    echo "ansible-playbook command not found in current environment, running Python YAML parser check..."
    python3 -c "
import yaml, glob

files = glob.glob('$REPO_ROOT/ansible/**/*.yml', recursive=True) + glob.glob('$REPO_ROOT/ansible/**/*.yaml', recursive=True)
for f in files:
    try:
        with open(f, 'r') as stream:
            list(yaml.safe_load_all(stream))
        print(f'OK: {f}')
    except Exception as e:
        print(f'FAIL: {f}: {e}')
        exit(1)
print('All YAML files are syntactically valid!')
"
fi

echo "=== All syntax and structure validation checks passed! ==="
