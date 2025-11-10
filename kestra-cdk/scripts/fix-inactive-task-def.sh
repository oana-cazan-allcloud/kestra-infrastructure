#!/bin/bash
# Script to fix inactive task definition issue by updating service to use latest active revision

set -e

REGION="eu-central-1"
CLUSTER_NAME="kestra-cluster"
SERVICE_NAME_PREFIX="KestraEcsServiceStack-KestraService"
TASK_FAMILY_PREFIX="KestraEcsTaskStack-KestraTaskDef"

echo "🔧 Fixing inactive task definition issue..."
echo ""

# Find the service
echo "Finding ECS service..."
SERVICE_NAME=$(aws ecs list-services --cluster "$CLUSTER_NAME" --region "$REGION" --query "serviceArns[?contains(@, '$SERVICE_NAME_PREFIX')]" --output text 2>/dev/null | head -1 | cut -d'/' -f3 || echo "")

if [ -z "$SERVICE_NAME" ]; then
  echo "  ℹ️  Service not found. This is fine if deploying for the first time."
  echo ""
  echo "  Solution: Deploy stacks in this order:"
  echo "    1. npx cdk deploy KestraEcsTaskStack"
  echo "    2. npx cdk deploy KestraEcsServiceStack"
  exit 0
fi

echo "  ✅ Found service: $SERVICE_NAME"
echo ""

# Get current task definition
CURRENT_TASK_DEF=$(aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --region "$REGION" \
  --query 'services[0].taskDefinition' \
  --output text 2>/dev/null || echo "")

if [ -z "$CURRENT_TASK_DEF" ]; then
  echo "  ❌ Could not get current task definition"
  exit 1
fi

echo "  Current Task Definition: $CURRENT_TASK_DEF"
echo ""

# Check if it's inactive
TASK_DEF_STATUS=$(aws ecs describe-task-definition \
  --task-definition "$CURRENT_TASK_DEF" \
  --region "$REGION" \
  --query 'taskDefinition.status' \
  --output text 2>/dev/null || echo "UNKNOWN")

echo "  Task Definition Status: $TASK_DEF_STATUS"
echo ""

if [ "$TASK_DEF_STATUS" == "INACTIVE" ]; then
  echo "  ⚠️  Task definition is INACTIVE!"
  echo ""
  echo "  Finding latest ACTIVE revision..."
  
  # Get latest active task definition
  LATEST_TASK_DEF=$(aws ecs list-task-definitions \
    --family-prefix "$TASK_FAMILY_PREFIX" \
    --region "$REGION" \
    --sort DESC \
    --status ACTIVE \
    --max-items 1 \
    --query 'taskDefinitionArns[0]' \
    --output text 2>/dev/null || echo "")
  
  if [ -z "$LATEST_TASK_DEF" ]; then
    echo "  ❌ No active task definition found!"
    echo ""
    echo "  Solution: Deploy the task stack first:"
    echo "    npx cdk deploy KestraEcsTaskStack"
    exit 1
  fi
  
  echo "  ✅ Found latest active: $LATEST_TASK_DEF"
  echo ""
  echo "  Updating service to use latest active task definition..."
  
  aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --task-definition "$LATEST_TASK_DEF" \
    --region "$REGION" \
    --force-new-deployment > /dev/null
  
  echo "  ✅ Service updated! New deployment started."
  echo ""
  echo "  Monitor deployment:"
  echo "    aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $REGION --query 'services[0].deployments'"
else
  echo "  ✅ Task definition is ACTIVE - no action needed"
  echo ""
  echo "  If deployment still fails, try:"
  echo "    1. Deploy task stack: npx cdk deploy KestraEcsTaskStack"
  echo "    2. Then deploy service stack: npx cdk deploy KestraEcsServiceStack"
fi

echo ""
echo "✅ Fix complete!"

