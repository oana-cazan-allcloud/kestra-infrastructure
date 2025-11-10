#!/bin/bash
# Check ECS task status and logs for Kestra

set -euo pipefail

CLUSTER="kestra-cluster"
REGION="${AWS_REGION:-eu-central-1}"
PROFILE="${AWS_PROFILE:-data-sandbox}"

export AWS_PROFILE="$PROFILE"
export AWS_REGION="$REGION"

echo "=============================================="
echo "🔍 Checking ECS Tasks for Kestra"
echo "=============================================="
echo "Cluster: $CLUSTER"
echo "Region: $REGION"
echo ""

# Get service name
SERVICE_NAME=$(aws ecs list-services --cluster "$CLUSTER" --region "$REGION" --query 'serviceArns[0]' --output text | awk -F'/' '{print $NF}')
echo "Service: $SERVICE_NAME"
echo ""

# List tasks
echo "📋 Running Tasks:"
TASK_ARNS=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE_NAME" --region "$REGION" --query 'taskArns' --output text)

if [ -z "$TASK_ARNS" ]; then
  echo "   ⚠️  No running tasks found"
  echo ""
  echo "   Check service status:"
  aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE_NAME" --region "$REGION" --query 'services[0].{Status:status,DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount}' --output table
  exit 0
fi

TASK_COUNT=$(echo "$TASK_ARNS" | wc -w)
echo "   Found $TASK_COUNT task(s)"
echo ""

# Get task details
for TASK_ARN in $TASK_ARNS; do
  TASK_ID=$(echo "$TASK_ARN" | awk -F'/' '{print $NF}')
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Task: $TASK_ID"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Get task status
  TASK_STATUS=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$REGION" --query 'tasks[0].{LastStatus:lastStatus,HealthStatus:healthStatus,DesiredStatus:desiredStatus,TaskDefinition:taskDefinitionArn,StartedAt:startedAt}' --output table)
  echo "$TASK_STATUS"
  echo ""
  
  # Get container statuses
  echo "📦 Container Statuses:"
  aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$REGION" --query 'tasks[0].containers[*].{Name:name,Status:lastStatus,ExitCode:exitCode,Reason:reason}' --output table
  echo ""
done

echo "=============================================="
echo "📝 Recent Logs (GitSync container)"
echo "=============================================="
echo ""

# Get logs from CloudWatch
LOG_GROUP="/aws/ecs/kestra-logs"

if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region "$REGION" --query "logGroups[?logGroupName=='$LOG_GROUP'].logGroupName" --output text | grep -q "$LOG_GROUP"; then
  echo "Fetching recent GitSync logs..."
  echo ""
  
  # Get last 50 log events for GitSync
  aws logs filter-log-events \
    --log-group-name "$LOG_GROUP" \
    --region "$REGION" \
    --filter-pattern "GitSync" \
    --max-items 20 \
    --query 'events[*].{Time:timestamp,Message:message}' \
    --output table 2>/dev/null || echo "   No GitSync logs found or log group empty"
  
  echo ""
  echo "Fetching recent SshInit logs..."
  echo ""
  
  aws logs filter-log-events \
    --log-group-name "$LOG_GROUP" \
    --region "$REGION" \
    --filter-pattern "SshInit" \
    --max-items 10 \
    --query 'events[*].{Time:timestamp,Message:message}' \
    --output table 2>/dev/null || echo "   No SshInit logs found"
else
  echo "⚠️  Log group not found: $LOG_GROUP"
fi

echo ""
echo "=============================================="
echo "💡 Commands to check logs manually:"
echo "=============================================="
echo ""
echo "# Follow GitSync logs:"
echo "aws logs tail $LOG_GROUP --follow --filter-pattern 'GitSync' --region $REGION --profile $PROFILE"
echo ""
echo "# Follow SshInit logs:"
echo "aws logs tail $LOG_GROUP --follow --filter-pattern 'SshInit' --region $REGION --profile $PROFILE"
echo ""
echo "# Get all recent logs:"
echo "aws logs tail $LOG_GROUP --since 10m --region $REGION --profile $PROFILE"
echo ""

