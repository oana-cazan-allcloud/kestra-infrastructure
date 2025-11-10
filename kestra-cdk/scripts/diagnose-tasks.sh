#!/bin/bash
# Script to diagnose ECS task and container startup issues

set -e

REGION="eu-central-1"
CLUSTER_NAME="kestra-cluster"
SERVICE_NAME_PREFIX="KestraEcsServiceStack-KestraService"
LOG_GROUP="/ecs/kestra"

echo "🔍 Diagnosing ECS Task and Container Issues..."
echo ""

# Find the service
echo "Finding ECS service..."
SERVICE_NAME=$(aws ecs list-services --cluster "$CLUSTER_NAME" --region "$REGION" --query "serviceArns[?contains(@, '$SERVICE_NAME_PREFIX')]" --output text 2>/dev/null | head -1 | cut -d'/' -f3 || echo "")

if [ -z "$SERVICE_NAME" ]; then
  echo "  ❌ Service not found!"
  echo "  Deploy the service stack first: npx cdk deploy KestraEcsServiceStack"
  exit 1
fi

echo "  ✅ Found service: $SERVICE_NAME"
echo ""

# Get running tasks
echo "📋 Checking running tasks..."
TASKS=$(aws ecs list-tasks \
  --cluster "$CLUSTER_NAME" \
  --service-name "$SERVICE_NAME" \
  --region "$REGION" \
  --query 'taskArns' \
  --output text 2>/dev/null || echo "")

if [ -z "$TASKS" ]; then
  echo "  ⚠️  No tasks running!"
  echo ""
  echo "  Checking service events for errors..."
  aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$REGION" \
    --query 'services[0].events[:5]' \
    --output table 2>/dev/null || echo "Could not fetch events"
  exit 1
fi

echo "  Found $(echo $TASKS | wc -w | tr -d ' ') task(s)"
echo ""

# Check each task
for task_arn in $TASKS; do
  TASK_ID=$(echo $task_arn | cut -d'/' -f3)
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Task: $TASK_ID"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Get task details
  TASK_INFO=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$task_arn" \
    --region "$REGION" \
    --query 'tasks[0].[lastStatus,desiredStatus,healthStatus,stoppedReason,stopCode]' \
    --output text 2>/dev/null || echo "")
  
  if [ ! -z "$TASK_INFO" ]; then
    LAST_STATUS=$(echo "$TASK_INFO" | awk '{print $1}')
    DESIRED_STATUS=$(echo "$TASK_INFO" | awk '{print $2}')
    HEALTH_STATUS=$(echo "$TASK_INFO" | awk '{print $3}')
    STOPPED_REASON=$(echo "$TASK_INFO" | awk '{print $4}')
    STOP_CODE=$(echo "$TASK_INFO" | awk '{print $5}')
    
    echo "  Status: $LAST_STATUS"
    echo "  Desired: $DESIRED_STATUS"
    echo "  Health: ${HEALTH_STATUS:-N/A}"
    
    if [ "$LAST_STATUS" == "STOPPED" ]; then
      echo "  ⚠️  Task is STOPPED!"
      echo "  Stop Code: ${STOP_CODE:-N/A}"
      echo "  Reason: ${STOPPED_REASON:-N/A}"
    fi
  fi
  
  echo ""
  echo "  📦 Container Status:"
  
  # Get container details
  aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$task_arn" \
    --region "$REGION" \
    --query 'tasks[0].containers[*].[name,lastStatus,healthStatus,exitCode,reason]' \
    --output table 2>/dev/null || echo "Could not fetch container info"
  
  echo ""
  echo "  📋 Container Logs Check:"
  
  # Check if log streams exist
  for container in Postgres GitSync RepoSyncer KestraServer; do
    LOG_STREAM="${container}/${TASK_ID}"
    EXISTS=$(aws logs describe-log-streams \
      --log-group-name "$LOG_GROUP" \
      --log-stream-name-prefix "$LOG_STREAM" \
      --region "$REGION" \
      --query 'logStreams[0].logStreamName' \
      --output text 2>/dev/null || echo "")
    
    if [ ! -z "$EXISTS" ] && [ "$EXISTS" != "None" ]; then
      echo "    ✅ $container: Log stream exists"
      # Get last few log lines
      echo "       Last logs:"
      aws logs get-log-events \
        --log-group-name "$LOG_GROUP" \
        --log-stream-name "$EXISTS" \
        --region "$REGION" \
        --limit 3 \
        --query 'events[*].message' \
        --output text 2>/dev/null | sed 's/^/         /' || echo "         (no logs yet)"
    else
      echo "    ⚠️  $container: Log stream not created yet"
      echo "       This usually means the container hasn't started or hasn't written logs"
    fi
  done
  
  echo ""
  
  # Check task stop code and exit code for stopped tasks
  if [ "$LAST_STATUS" == "STOPPED" ]; then
    echo "  🔍 Detailed Stop Information:"
    aws ecs describe-tasks \
      --cluster "$CLUSTER_NAME" \
      --tasks "$task_arn" \
      --region "$REGION" \
      --query 'tasks[0].[stoppedReason,stopCode,containers[*].[name,exitCode,reason]]' \
      --output json 2>/dev/null | jq '.' || echo "Could not fetch details"
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Common Issues and Solutions:"
echo ""
echo "1. Containers not starting:"
echo "   - Check CloudWatch logs: aws logs tail /ecs/kestra --follow"
echo "   - Verify secrets exist: ./scripts/verify-secrets.sh"
echo "   - Check task definition: aws ecs describe-task-definition --task-definition <family>"
echo ""
echo "2. Log streams not created:"
echo "   - Containers may be failing to start"
echo "   - Check ECS service events for errors"
echo "   - Verify IAM permissions for CloudWatch Logs"
echo ""
echo "3. Task keeps stopping:"
echo "   - Check container exit codes above"
echo "   - Review CloudWatch logs for errors"
echo "   - Verify all dependencies (secrets, EFS, etc.)"
echo ""
echo "✅ Diagnosis complete!"

