#!/bin/bash
# Script to check task definition status and service configuration

set -e

REGION="eu-central-1"
CLUSTER_NAME="kestra-cluster"
SERVICE_NAME_PREFIX="KestraEcsServiceStack-KestraService"

echo "🔍 Checking ECS Task Definition and Service Status..."
echo ""

# Find the service name
echo "Finding ECS service..."
SERVICE_NAME=$(aws ecs list-services --cluster "$CLUSTER_NAME" --region "$REGION" --query "serviceArns[?contains(@, '$SERVICE_NAME_PREFIX')]" --output text 2>/dev/null | head -1 | cut -d'/' -f3 || echo "")

if [ -z "$SERVICE_NAME" ]; then
  echo "  ⚠️  Service not found. It may not be deployed yet."
  echo ""
  echo "Checking task definitions..."
  aws ecs list-task-definitions \
    --family-prefix "KestraEcsTaskStack-KestraTaskDef" \
    --region "$REGION" \
    --sort DESC \
    --max-items 5 \
    --output table 2>&1 | head -20
  exit 0
fi

echo "  ✅ Found service: $SERVICE_NAME"
echo ""

# Get service details
echo "📋 Service Details:"
SERVICE_INFO=$(aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --region "$REGION" \
  --query 'services[0].[taskDefinition,status,runningCount,desiredCount,deployments[0].status]' \
  --output text 2>/dev/null || echo "")

if [ ! -z "$SERVICE_INFO" ]; then
  TASK_DEF=$(echo "$SERVICE_INFO" | awk '{print $1}')
  STATUS=$(echo "$SERVICE_INFO" | awk '{print $2}')
  RUNNING=$(echo "$SERVICE_INFO" | awk '{print $3}')
  DESIRED=$(echo "$SERVICE_INFO" | awk '{print $4}')
  DEPLOY_STATUS=$(echo "$SERVICE_INFO" | awk '{print $5}')
  
  echo "  Task Definition: $TASK_DEF"
  echo "  Service Status: $STATUS"
  echo "  Running Count: $RUNNING / $DESIRED"
  echo "  Deployment Status: $DEPLOY_STATUS"
  echo ""
  
  # Extract task definition family and revision
  TASK_FAMILY=$(echo "$TASK_DEF" | cut -d'/' -f2 | cut -d':' -f1)
  TASK_REVISION=$(echo "$TASK_DEF" | cut -d':' -f2)
  
  echo "📋 Task Definition Details:"
  echo "  Family: $TASK_FAMILY"
  echo "  Revision: $TASK_REVISION"
  echo ""
  
  # Check task definition status
  echo "Checking task definition status..."
  TASK_DEF_STATUS=$(aws ecs describe-task-definition \
    --task-definition "$TASK_DEF" \
    --region "$REGION" \
    --query 'taskDefinition.status' \
    --output text 2>/dev/null || echo "UNKNOWN")
  
  echo "  Status: $TASK_DEF_STATUS"
  echo ""
  
  if [ "$TASK_DEF_STATUS" == "INACTIVE" ]; then
    echo "⚠️  WARNING: Task definition is INACTIVE!"
    echo ""
    echo "This usually means:"
    echo "  1. A newer revision was created"
    echo "  2. The service should be using the latest active revision"
    echo ""
    echo "Checking for active revisions..."
    aws ecs list-task-definitions \
      --family-prefix "$TASK_FAMILY" \
      --region "$REGION" \
      --sort DESC \
      --max-items 5 \
      --output table 2>&1 | head -15
    echo ""
    echo "💡 Solution:"
    echo "  - If the service is using an inactive revision, update the service"
    echo "  - Or redeploy the stack: npx cdk deploy KestraEcsServiceStack"
  else
    echo "✅ Task definition is ACTIVE"
  fi
  
  # Check running tasks
  echo ""
  echo "📋 Running Tasks:"
  TASKS=$(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --region "$REGION" \
    --query 'taskArns' \
    --output text 2>/dev/null || echo "")
  
  if [ -z "$TASKS" ]; then
    echo "  ⚠️  No tasks running"
    echo ""
    echo "Possible reasons:"
    echo "  - Service deployment failed"
    echo "  - Tasks failed to start (check CloudWatch logs)"
    echo "  - No capacity available in cluster"
  else
    echo "  Found $(echo $TASKS | wc -w | tr -d ' ') task(s)"
    for task in $TASKS; do
      TASK_STATUS=$(aws ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$task" \
        --region "$REGION" \
        --query 'tasks[0].[lastStatus,healthStatus,stoppedReason]' \
        --output text 2>/dev/null || echo "UNKNOWN")
      echo "    Task: $(echo $task | cut -d'/' -f3)"
      echo "      Status: $TASK_STATUS"
    done
  fi
else
  echo "  ❌ Could not retrieve service information"
fi

echo ""
echo "✅ Check complete!"

