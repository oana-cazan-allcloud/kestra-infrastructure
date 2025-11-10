#!/bin/bash
# Safe teardown for all Kestra CDK stacks in dependency order

set -euo pipefail

# Handle EPIPE errors gracefully (broken pipe when grep closes early)
trap 'exit 0' SIGPIPE || true

APP="npx ts-node --prefer-ts-exts bin/kestra-cdk.ts"  # 👈 CDK app entrypoint

# Ordered top-down: highest dependency destroyed first
STACKS=(
  "KestraEcsServiceStack"
  "KestraAlbStack"
  "KestraEcsTaskStack"
  "KestraS3Stack"
  "KestraEfsStack"
  "KestraEcsClusterStack"
  "KestraCdkStack"
)

echo "=============================================="
echo "⚠️  This will destroy all Kestra CDK stacks!"
echo "=============================================="
echo
read -p "Do you really want to continue? (y/n) " confirm
if [[ "$confirm" != "y" ]]; then
  echo "❌ Aborted."
  exit 0
fi

echo
echo "🧹 Starting cleanup..."

# Function to scale down AutoScaling Group before deletion
scale_down_asg() {
  local stack_name=$1
  local region="${AWS_REGION:-eu-central-1}"
  
  echo "📉 Checking for AutoScaling Groups in stack: $stack_name"
  
  # Get ASG name from CloudFormation stack outputs
  local asg_name=$(aws cloudformation describe-stacks \
    --stack-name "$stack_name" \
    --region "$region" \
    --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
    --output text 2>/dev/null || echo "")
  
  if [[ -n "$asg_name" && "$asg_name" != "None" ]]; then
    echo "🔍 Found ASG: $asg_name"
    
    # Get current desired capacity
    local current_capacity=$(aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "$asg_name" \
      --region "$region" \
      --query 'AutoScalingGroups[0].DesiredCapacity' \
      --output text 2>/dev/null || echo "0")
    
    if [[ "$current_capacity" -gt 0 ]]; then
      echo "📉 Scaling down ASG from $current_capacity to 0..."
      aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name "$asg_name" \
        --min-size 0 \
        --desired-capacity 0 \
        --region "$region" 2>/dev/null || true
      
      echo "⏳ Waiting for instances to terminate (this may take a few minutes)..."
      local max_wait=300  # 5 minutes max wait
      local elapsed=0
      while [[ $elapsed -lt $max_wait ]]; do
        local instance_count=$(aws autoscaling describe-auto-scaling-groups \
          --auto-scaling-group-names "$asg_name" \
          --region "$region" \
          --query 'AutoScalingGroups[0].Instances | length(@)' \
          --output text 2>/dev/null || echo "0")
        
        if [[ "$instance_count" -eq 0 ]]; then
          echo "✅ All instances terminated"
          break
        fi
        
        echo "   Still waiting... ($instance_count instance(s) remaining)"
        sleep 10
        elapsed=$((elapsed + 10))
      done
      
      if [[ $elapsed -ge $max_wait ]]; then
        echo "⚠️  Timeout waiting for instances to terminate. Proceeding anyway..."
      fi
    else
      echo "ℹ️  ASG already at 0 capacity"
    fi
  else
    echo "ℹ️  No ASG found in stack outputs"
  fi
}

# Get list of available stacks (handle EPIPE by reading all output first)
AVAILABLE_STACKS=$(cdk list --app "$APP" 2>&1 || true)

for stack in "${STACKS[@]}"; do
  echo "----------------------------------------------"
  echo "🚀 Destroying stack: $stack"
  echo "----------------------------------------------"
  
  # Check if stack exists in the list
  if echo "$AVAILABLE_STACKS" | grep -q "^$stack$" 2>/dev/null || true; then
    # Special handling for EcsClusterStack - scale down ASG first
    if [[ "$stack" == "KestraEcsClusterStack" ]]; then
      echo "🔄 Pre-scaling ASG before stack deletion..."
      scale_down_asg "$stack" || {
        echo "⚠️  Failed to scale down ASG. Continuing with destroy anyway..."
      }
      echo
    fi
    
    # Use --require-approval never to avoid interactive prompts
    # Let CDK output go directly to avoid EPIPE issues
    # Use || true to continue even if destroy fails
    cdk destroy "$stack" --app "$APP" --force --require-approval never || {
      echo "⚠️  Failed to destroy $stack. Continuing..."
    }
  else
    echo "ℹ️  Stack $stack not found — skipping."
  fi
done

echo
echo "✅ All cleanup operations completed!"
echo "💡 Verify in AWS CloudFormation console (should show DELETE_COMPLETE)"
