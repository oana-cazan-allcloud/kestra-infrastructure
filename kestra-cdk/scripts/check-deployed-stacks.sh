#!/bin/bash
# Check which Kestra CDK stacks are deployed

set -euo pipefail

REGION="${AWS_REGION:-eu-central-1}"

echo "=============================================="
echo "📋 Checking Deployed Kestra CDK Stacks"
echo "=============================================="
echo ""

# Check AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
  echo "❌ AWS credentials not configured or expired!"
  echo "   Please run: aws configure sso"
  echo "   Or refresh your credentials"
  exit 1
fi

echo "✅ AWS credentials valid"
echo ""

# Expected stacks
EXPECTED_STACKS=(
  "KestraVpcStack"
  "KestraEcsClusterStack"
  "KestraEfsStack"
  "KestraS3Stack"
  "KestraEcsTaskStack"
  "KestraAlbStack"
  "KestraEcsServiceStack"
  "KestraWafStack"
  "KestraBackupStack"
  "KestraCdkStack"
)

echo "🔍 Checking active stacks (CREATE_COMPLETE, UPDATE_COMPLETE)..."
echo ""
ACTIVE_STACKS=$(aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?contains(StackName, 'Kestra')].StackName" \
  --output text \
  --region "$REGION" 2>/dev/null || echo "")

if [ -n "$ACTIVE_STACKS" ]; then
  echo "✅ ACTIVE STACKS:"
  for stack in $ACTIVE_STACKS; do
    echo "   ✓ $stack"
  done
else
  echo "   (none found)"
fi

echo ""
echo "⚠️  Checking in-progress stacks..."
echo ""
IN_PROGRESS=$(aws cloudformation list-stacks \
  --stack-status-filter CREATE_IN_PROGRESS UPDATE_IN_PROGRESS ROLLBACK_IN_PROGRESS \
  --query "StackSummaries[?contains(StackName, 'Kestra')].{Name:StackName,Status:StackStatus}" \
  --output table \
  --region "$REGION" 2>/dev/null || echo "")

if [ -n "$IN_PROGRESS" ] && [ "$IN_PROGRESS" != "None" ]; then
  echo "$IN_PROGRESS"
else
  echo "   (none found)"
fi

echo ""
echo "❌ Checking failed/rolled back stacks..."
echo ""
FAILED_STACKS=$(aws cloudformation list-stacks \
  --stack-status-filter CREATE_FAILED UPDATE_FAILED DELETE_FAILED ROLLBACK_COMPLETE UPDATE_ROLLBACK_COMPLETE \
  --query "StackSummaries[?contains(StackName, 'Kestra')].{Name:StackName,Status:StackStatus}" \
  --output table \
  --region "$REGION" 2>/dev/null || echo "")

if [ -n "$FAILED_STACKS" ] && [ "$FAILED_STACKS" != "None" ]; then
  echo "$FAILED_STACKS"
else
  echo "   (none found)"
fi

echo ""
echo "=============================================="
echo "📊 Summary"
echo "=============================================="
echo ""

# Count stacks
ACTIVE_COUNT=$(echo "$ACTIVE_STACKS" | wc -w | tr -d ' ')
echo "Active stacks: $ACTIVE_COUNT / ${#EXPECTED_STACKS[@]}"

echo ""
echo "Missing stacks:"
MISSING_COUNT=0
for expected in "${EXPECTED_STACKS[@]}"; do
  if ! echo "$ACTIVE_STACKS" | grep -q "$expected"; then
    echo "   - $expected"
    MISSING_COUNT=$((MISSING_COUNT + 1))
  fi
done

if [ $MISSING_COUNT -eq 0 ]; then
  echo "   (all stacks deployed!)"
fi

echo ""
echo "💡 To deploy missing stacks, run:"
echo "   ./scripts/deploy-all-stacks.sh"

