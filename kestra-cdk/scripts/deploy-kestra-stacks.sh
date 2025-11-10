#!/bin/bash
# Deploy all Kestra CDK stacks in dependency order

set -euo pipefail

APP="npx ts-node --prefer-ts-exts bin/kestra-cdk.ts"

# npx cdk deploy KestraVpcStack 
# Ordered from the base infrastructure upwards
STACKS=(
  "KestraEcsClusterStack"
  "KestraEfsStack"
  "KestraS3Stack"
  "KestraEcsTaskStack"
  "KestraAlbStack"
  "KestraEcsServiceStack",
  "KestraWafStack"
)

echo "=============================================="
echo "🚀 Deploying all Kestra CDK stacks (in order)"
echo "=============================================="
echo

read -p "Proceed with deployment? (y/n) " confirm
if [[ "$confirm" != "y" ]]; then
  echo "❌ Deployment canceled."
  exit 0
fi

for stack in "${STACKS[@]}"; do
  echo "----------------------------------------------"
  echo "🧱 Deploying stack: $stack"
  echo "----------------------------------------------"

  cdk deploy "$stack" --app "$APP" --require-approval never || {
    echo "⚠️  Failed to deploy $stack. Continuing..."
  }

  echo
done

echo "✅ All stacks deployed successfully!"
echo "💡 You can verify them in the AWS CloudFormation console."
