#!/bin/bash
# Clean up failed service stack and old services, then redeploy

set -e

REGION="${AWS_REGION:-eu-central-1}"
AWS_PROFILE="${AWS_PROFILE:-data-sandbox}"
CLUSTER_NAME="${CLUSTER_NAME:-kestra-cluster}"

export AWS_PROFILE

echo "🧹 Cleaning Up Failed Service Stack"
echo "===================================="
echo ""

# 1. Delete failed CloudFormation stack
echo "1️⃣  Deleting failed CloudFormation stack..."
if aws cloudformation describe-stacks --stack-name KestraEcsServiceStack --region "$REGION" &>/dev/null; then
    echo "   Stack exists, deleting..."
    aws cloudformation delete-stack --stack-name KestraEcsServiceStack --region "$REGION" 2>&1
    echo "   Waiting for stack deletion..."
    aws cloudformation wait stack-delete-complete --stack-name KestraEcsServiceStack --region "$REGION" 2>&1 || echo "   Stack deletion in progress..."
    echo "   ✅ Stack deletion initiated"
else
    echo "   ✅ Stack doesn't exist (already deleted)"
fi

echo ""
echo "2️⃣  Finding and cleaning up old services..."
SERVICES=$(aws ecs list-services --cluster "$CLUSTER_NAME" --region "$REGION" --query 'serviceArns[*]' --output text 2>/dev/null)

if [ -z "$SERVICES" ] || [ "$SERVICES" == "None" ]; then
    echo "   ✅ No services found"
else
    for SERVICE_ARN in $SERVICES; do
        SERVICE_NAME=$(echo "$SERVICE_ARN" | awk -F'/' '{print $NF}')
        echo "   Found service: $SERVICE_NAME"
        
        # Scale down to 0
        echo "   Scaling down to 0..."
        aws ecs update-service \
            --cluster "$CLUSTER_NAME" \
            --service "$SERVICE_NAME" \
            --desired-count 0 \
            --region "$REGION" 2>&1 | grep -v "An error occurred" || true
        
        # Wait a bit
        sleep 5
        
        # Delete service
        echo "   Deleting service..."
        aws ecs delete-service \
            --cluster "$CLUSTER_NAME" \
            --service "$SERVICE_NAME" \
            --region "$REGION" 2>&1 | grep -v "An error occurred" || true
        
        echo "   ✅ Service deletion initiated: $SERVICE_NAME"
    done
fi

echo ""
echo "3️⃣  Waiting for services to be deleted..."
sleep 10

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Now you can deploy the service stack:"
echo "  npx cdk deploy KestraEcsServiceStack --require-approval never"

