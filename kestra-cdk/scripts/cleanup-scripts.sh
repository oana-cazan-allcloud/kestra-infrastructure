#!/bin/bash
# Delete outdated and duplicate scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=============================================="
echo "🗑️  Deleting Outdated Scripts"
echo "=============================================="
echo ""

# Scripts to delete
DELETE_SCRIPTS=(
  # Duplicates
  "deploy-kestra-stacks.sh"
  "check-deployed-stacks.sh"
  
  # Outdated/Troubleshooting
  "check-deployment-status.sh"
  "check-whats-deployed.sh"
  "check-task-definition.sh"
  "check-tasks-health.sh"
  "check-service-conflicts.sh"
  "check-sg-usage.sh"
  "check-security-groups.sh"
  "diagnose-alb.sh"
  "diagnose-task-startup.sh"
  "diagnose-tasks.sh"
  "explain-tasks.sh"
  "fix-inactive-task-def.sh"
  "prevent-deletion-guide.sh"
  "replace-container-instance.sh"
  "show-efs-sg.sh"
  "test-container-instance-dns.sh"
  "unblock-asg-deletion.sh"
  "why-no-tasks.sh"
  "cleanup-failed-service.sh"
  "create-efs-directories.sh"
)

DELETED=0
NOT_FOUND=0

for script in "${DELETE_SCRIPTS[@]}"; do
  if [ -f "$script" ]; then
    echo "Deleting: $script"
    rm "$script"
    DELETED=$((DELETED + 1))
  else
    echo "Not found: $script"
    NOT_FOUND=$((NOT_FOUND + 1))
  fi
done

echo ""
echo "=============================================="
echo "✅ Deleted: $DELETED scripts"
echo "⚠️  Not found: $NOT_FOUND scripts"
echo "=============================================="

