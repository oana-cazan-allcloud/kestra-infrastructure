#!/bin/bash
# Helper script to diagnose and unblock stuck ALB

set -euo pipefail

STACK_NAME="${1:-KestraAlbStack}"
REGION="${AWS_REGION:-eu-central-1}"

echo "🔍 Diagnosing ALB Stack: $STACK_NAME"
echo "📍 Region: $REGION"
echo

# Check stack status
echo "📊 Stack Status:"
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null || echo "Stack not found or error accessing"

echo ""
echo "📋 Recent Events (last 10):"
aws cloudformation describe-stack-events \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --max-items 10 \
  --query 'StackEvents[*].[Timestamp,ResourceType,ResourceStatus,ResourceStatusReason]' \
  --output table 2>/dev/null || echo "Could not fetch events"

echo ""
echo "🔧 Common fixes for stuck ALB:"
echo "   1. If DELETE_IN_PROGRESS: Delete listeners/target groups manually"
echo "   2. If CREATE_IN_PROGRESS: Check security groups and subnets"
echo "   3. If name conflict: Delete old ALB with same name"
echo ""
echo "💡 To manually delete ALB resources:"
echo "   - Go to: https://console.aws.amazon.com/ec2/v2/home?region=$REGION#LoadBalancers:"
echo "   - Find ALB → Delete listeners → Delete target groups → Delete ALB"

