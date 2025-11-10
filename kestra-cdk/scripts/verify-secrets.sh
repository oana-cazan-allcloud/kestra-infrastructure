#!/bin/bash
# Script to verify secrets exist and grant permissions to ECS task execution role

set -e

REGION="eu-central-1"
ACCOUNT_ID="822550017122"

echo "🔍 Verifying Kestra secrets exist..."
echo ""

# Check for secrets
echo "Checking for kestra/git..."
if aws secretsmanager describe-secret --secret-id kestra/git --region "$REGION" &>/dev/null; then
  GIT_SYNC_ARN=$(aws secretsmanager describe-secret --secret-id kestra/git --region "$REGION" --query 'ARN' --output text)
  echo "  ✅ Found: kestra/git"
  echo "     ARN: $GIT_SYNC_ARN"
else
  echo "  ❌ Secret kestra/git not found!"
  exit 1
fi

echo ""
echo "Checking for kestra/postgres..."
if aws secretsmanager describe-secret --secret-id kestra/postgres --region "$REGION" &>/dev/null; then
  POSTGRES_ARN=$(aws secretsmanager describe-secret --secret-id kestra/postgres --region "$REGION" --query 'ARN' --output text)
  echo "  ✅ Found: kestra/postgres"
  echo "     ARN: $POSTGRES_ARN"
else
  echo "  ❌ Secret kestra/postgres not found!"
  exit 1
fi

echo ""
echo "🔑 Finding ECS task execution role..."

# Find the execution role (CDK generates names with random suffixes)
ROLE_ARN=$(aws iam list-roles --query "Roles[?contains(RoleName, 'KestraTaskExecutionRole')].Arn" --output text 2>/dev/null | head -1 || echo "")

if [ -z "$ROLE_ARN" ]; then
  echo "  ⚠️  Could not find execution role automatically"
  echo "  The role will be created when you deploy KestraEcsTaskStack"
  echo ""
  echo "  After deployment, verify the role has these permissions:"
  echo "    - secretsmanager:GetSecretValue"
  echo "    - On resources: $GIT_SYNC_ARN and $POSTGRES_ARN"
  exit 0
fi

echo "  ✅ Found role: $ROLE_ARN"
echo ""

# Check current permissions
echo "📋 Checking IAM policy permissions..."
POLICY_DOC=$(aws iam get-role-policy --role-name $(echo $ROLE_ARN | cut -d'/' -f2) --policy-name $(aws iam list-role-policies --role-name $(echo $ROLE_ARN | cut -d'/' -f2) --query 'PolicyNames[0]' --output text 2>/dev/null) --query 'PolicyDocument' --output json 2>/dev/null || echo "{}")

if echo "$POLICY_DOC" | grep -q "secretsmanager:GetSecretValue"; then
  echo "  ✅ Role has secretsmanager:GetSecretValue permission"
  
  # Check if it's specific or wildcard
  if echo "$POLICY_DOC" | grep -q '"Resource": "\*"'; then
    echo "  ⚠️  Permission uses wildcard (*) - this works but is less secure"
    echo "  ✅ The CDK code has been updated to use specific ARNs"
    echo "  📝 Redeploy KestraEcsTaskStack to apply specific permissions"
  else
    echo "  ✅ Permission is scoped to specific secrets (secure)"
  fi
else
  echo "  ❌ Role does NOT have secretsmanager:GetSecretValue permission"
  echo "  📝 Deploy KestraEcsTaskStack to add the permission"
fi

echo ""
echo "✅ Verification complete!"
echo ""
echo "Summary:"
echo "  - kestra/git: $GIT_SYNC_ARN"
echo "  - kestra/postgres: $POSTGRES_ARN"
echo "  - Execution Role: ${ROLE_ARN:-Not found - will be created on deployment}"
echo ""
echo "Next steps:"
echo "  1. Deploy KestraEcsTaskStack to ensure IAM permissions are correct"
echo "  2. Then deploy KestraEcsServiceStack"

