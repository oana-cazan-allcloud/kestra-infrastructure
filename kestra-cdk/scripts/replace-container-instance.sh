#!/bin/bash
# Replace container instance to pick up new security groups and IAM role

set -e

REGION="${AWS_REGION:-eu-central-1}"
AWS_PROFILE="${AWS_PROFILE:-data-sandbox}"
INSTANCE_ID="${1}"

export AWS_PROFILE

if [ -z "$INSTANCE_ID" ]; then
    echo "Finding container instance..."
    CLUSTER_NAME="kestra-cluster"
    INSTANCE_ARN=$(aws ecs list-container-instances --cluster "$CLUSTER_NAME" --region "$REGION" --query 'containerInstanceArns[0]' --output text 2>/dev/null)
    
    if [ -z "$INSTANCE_ARN" ] || [ "$INSTANCE_ARN" == "None" ]; then
        echo "❌ No container instances found"
        exit 1
    fi
    
    INSTANCE_ID=$(aws ecs describe-container-instances \
        --cluster "$CLUSTER_NAME" \
        --container-instances "$INSTANCE_ARN" \
        --region "$REGION" \
        --query 'containerInstances[0].ec2InstanceId' \
        --output text 2>/dev/null)
fi

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
    echo "❌ Could not find container instance"
    exit 1
fi

echo "🔄 Replacing Container Instance"
echo "================================"
echo ""
echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo ""
echo "This will:"
echo "  1. Terminate the current instance"
echo "  2. Auto Scaling Group will launch a new instance"
echo "  3. New instance will have updated security groups and IAM role"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo "Terminating instance..."
aws autoscaling terminate-instance-in-auto-scaling-group \
    --instance-id "$INSTANCE_ID" \
    --should-decrement-desired-capacity \
    --region "$REGION" 2>&1

echo ""
echo "✅ Instance termination initiated"
echo ""
echo "The Auto Scaling Group will launch a new instance in a few minutes."
echo "Monitor with: ./scripts/check-cluster-resources.sh"

