#!/usr/bin/env bash
# ==============================================================================
# Script: generate-cis-from-oscap.sh
# Purpose: Uses oscap CLI to generate Ansible CIS Level 1 remediation tasks
#          from the official SCAP Security Guide (SSG) datastream.
# ==============================================================================

set -euo pipefail

PROFILE="xccdf_org.ssgproject.content_profile_cis_workstation_l1"
OUTPUT_FILE="ansible/roles/cis_level1/tasks/oscap_generated_remediations.yml"
DS_SEARCH_PATHS=(
    "/usr/share/xml/scap/ssg/content/ssg-almalinux10-ds.xml"
    "/usr/share/xml/scap/ssg/content/ssg-cs10-ds.xml"
    "/usr/share/xml/scap/ssg/content/ssg-rhel10-ds.xml"
    "/usr/share/xml/scap/ssg/content/ssg-almalinux9-ds.xml"
)

echo "=== [OpenSCAP CIS Generator] Searching for SCAP DataStream ==="

DS_PATH=""
for path in "${DS_SEARCH_PATHS[@]}"; do
    if [ -f "$path" ]; then
        DS_PATH="$path"
        break
    fi
done

if [ -z "$DS_PATH" ]; then
    echo "ERROR: No compatible SCAP datastream found in /usr/share/xml/scap/ssg/content/."
    echo "Please install scap-security-guide: sudo dnf install -y scap-security-guide openscap-scanner"
    exit 1
fi

echo "Found DataStream: $DS_PATH"
echo "Target Profile:   $PROFILE"
echo "Output Path:      $OUTPUT_FILE"

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "Running oscap xccdf generate fix..."
oscap xccdf generate fix \
    --profile "$PROFILE" \
    --fix-type ansible \
    --output "$OUTPUT_FILE" \
    "$DS_PATH"

echo "=== Generation Completed Successfully ==="
echo "Generated $(wc -l < "$OUTPUT_FILE") lines of Ansible tasks in $OUTPUT_FILE"
