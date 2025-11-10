#!/bin/bash
# Quick script to unblock stuck ASG deletion
# This script helps stop/unblock a stuck CloudFormation deletion

set -euo pipefail

STACK_NAME="${1:-KestraEcsClusterStack}"
REGION="${AWS_REGION:-eu-central-1}"

echo "🛑 Attempting to unblock stuck deletion for: $STACK_NAME"
echo "📍 Region: $REGION"
echo

# Method 1: Try to get ASG from stack outputs
echo "📋 Method 1: Checking stack outputs..."
ASG_NAME=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
  --output text 2>/dev/null || echo "")

# Method 2: If outputs not available, search for ASG by name pattern
if [[ -z "$ASG_NAME" || "$ASG_NAME" == "None" ]]; then
  echo "📋 Method 2: Searching for ASG by name pattern..."
  ASG_NAME=$(aws autoscaling describe-auto-scaling-groups \
    --region "$REGION" \
    --query "AutoScalingGroups[?contains(AutoScalingGroupName, 'Kestra') || contains(AutoScalingGroupName, 'kestra')].AutoScalingGroupName" \
    --output text 2>/dev/null | awk '{print $1}' || echo "")
fi

# Method 3: Get ASG from stack resources
if [[ -z "$ASG_NAME" || "$ASG_NAME" == "None" ]]; then
  echo "📋 Method 3: Checking stack resources..."
  ASG_NAME=$(aws cloudformation describe-stack-resources \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "StackResources[?ResourceType=='AWS::AutoScaling::AutoScalingGroup'].PhysicalResourceId" \
    --output text 2>/dev/null | awk '{print $1}' || echo "")
fi

if [[ -z "$ASG_NAME" || "$ASG_NAME" == "None" ]]; then
  echo ""
  echo "⚠️  Could not find ASG automatically."
  echo ""
  echo "🔧 Manual steps to stop the deletion:"
  echo "   1. Go to AWS Console → EC2 → Auto Scaling Groups"
  echo "   2. Find the ASG (look for 'Kestra' in the name)"
  echo "   3. Edit → Set Min/Desired/Max to 0"
  echo "   4. Wait for instances to terminate"
  echo ""
  echo "   Or use AWS Console → CloudFormation → Cancel stack operation"
  echo "   (Note: DELETE_IN_PROGRESS cannot be canceled, but scaling down ASG will unblock it)"
  exit 1
fi

echo "✅ Found ASG: $ASG_NAME"
echo

# Get current capacity
CURRENT_CAPACITY=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --region "$REGION" \
  --query 'AutoScalingGroups[0].DesiredCapacity' \
  --output text 2>/dev/null || echo "0")

INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --region "$REGION" \
  --query 'AutoScalingGroups[0].length(Instances)' \
  --output text 2>/dev/null || echo "0")

echo "📊 Current state:"
echo "   Desired Capacity: $CURRENT_CAPACITY"
echo "   Running Instances: $INSTANCE_COUNT"
echo

if [[ "$CURRENT_CAPACITY" -eq 0 && "$INSTANCE_COUNT" -eq 0 ]]; then
  echo "✅ ASG is already scaled down. CloudFormation should proceed."
  exit 0
fi

echo "🛑 Stopping ASG by scaling down to 0..."
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --min-size 0 \
  --desired-capacity 0 \
  --max-size 0 \
  --region "$REGION"

echo ""
echo "✅ ASG scaling initiated!"
echo "⏳ CloudFormation deletion should now proceed."
echo ""
echo "💡 Monitor progress:"
echo "   aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION"
echo ""
echo "   Or check AWS Console → CloudFormation → $STACK_NAME"
