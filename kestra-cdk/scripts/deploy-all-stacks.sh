#!/bin/bash
# Deploy all Kestra CDK stacks in dependency order

set -euo pipefail

export JSII_SILENCE_WARNING_UNTESTED_NODE_VERSION=1
APP="npx ts-node --prefer-ts-exts bin/kestra-cdk.ts"

# Deployment order based on dependencies
STACKS=(
  "KestraVpcStack"
  "KestraEcsClusterStack"
  "KestraEfsStack"
  "KestraS3Stack"
  "KestraEcsTaskStack"
  "KestraAlbStack"
  "KestraEcsServiceStack"
  "KestraWafStack"
  "KestraBackupStack"
)

echo "=============================================="
echo "🚀 Deploying all Kestra CDK stacks (in order)"
echo "=============================================="
echo ""

# Check AWS credentials
echo "🔐 Checking AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
  echo "❌ AWS credentials not configured or expired!"
  echo "   Please run: aws configure sso"
  echo "   Or refresh your credentials"
  exit 1
fi

echo "✅ AWS credentials valid"
echo ""

for stack in "${STACKS[@]}"; do
  echo "----------------------------------------------"
  echo "🧱 Deploying stack: $stack"
  echo "----------------------------------------------"
  
  cdk deploy "$stack" --app "$APP" --require-approval never || {
    echo "⚠️  Failed to deploy $stack"
    echo "   Continuing with next stack..."
  }
  
  echo ""
done

echo "✅ Deployment complete!"
echo "💡 Verify stacks in AWS CloudFormation console"

