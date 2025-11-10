#!/bin/bash
# Comprehensive script to check if tasks are correct and running properly

set -e

REGION="eu-central-1"
CLUSTER_NAME="kestra-cluster"
SERVICE_NAME_PREFIX="KestraEcsServiceStack-KestraService"
LOG_GROUP="/ecs/kestra"

echo "🔍 Comprehensive Task Health Check"
echo "=================================="
echo ""

# Find the service
echo "1️⃣ Finding ECS Service..."
SERVICE_NAME=$(aws ecs list-services \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "serviceArns[?contains(@, '$SERVICE_NAME_PREFIX')]" \
  --output text 2>/dev/null | head -1 | cut -d'/' -f3 || echo "")

if [ -z "$SERVICE_NAME" ]; then
  echo "  ❌ Service not found!"
  echo "     Deploy: npx cdk deploy KestraEcsServiceStack"
  exit 1
fi

echo "  ✅ Found service: $SERVICE_NAME"
echo ""

# Get service details
echo "2️⃣ Service Configuration..."
SERVICE_INFO=$(aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --region "$REGION" \
  --query 'services[0].[desiredCount,runningCount,pendingCount,deployments[0].status,deployments[0].taskDefinition]' \
  --output text 2>/dev/null || echo "")

if [ -z "$SERVICE_INFO" ]; then
  echo "  ❌ Could not get service info"
  exit 1
fi

DESIRED=$(echo "$SERVICE_INFO" | awk '{print $1}')
RUNNING=$(echo "$SERVICE_INFO" | awk '{print $2}')
PENDING=$(echo "$SERVICE_INFO" | awk '{print $3}')
DEPLOY_STATUS=$(echo "$SERVICE_INFO" | awk '{print $4}')
TASK_DEF_ARN=$(echo "$SERVICE_INFO" | awk '{print $5}')

echo "  Desired Count: $DESIRED"
echo "  Running Count: $RUNNING"
echo "  Pending Count: $PENDING"
echo "  Deployment Status: $DEPLOY_STATUS"
echo "  Task Definition: $(echo $TASK_DEF_ARN | cut -d'/' -f2)"
echo ""

# Check task definition status
echo "3️⃣ Task Definition Status..."
TASK_DEF_STATUS=$(aws ecs describe-task-definition \
  --task-definition "$TASK_DEF_ARN" \
  --region "$REGION" \
  --query 'taskDefinition.status' \
  --output text 2>/dev/null || echo "UNKNOWN")

if [ "$TASK_DEF_STATUS" == "INACTIVE" ]; then
  echo "  ⚠️  Task definition is INACTIVE!"
  echo "     This will cause tasks to fail"
  echo "     Fix: npx cdk deploy KestraEcsTaskStack"
else
  echo "  ✅ Task definition is ACTIVE"
fi
echo ""

# Get running tasks
echo "4️⃣ Running Tasks..."
RUNNING_TASKS=$(aws ecs list-tasks \
  --cluster "$CLUSTER_NAME" \
  --service-name "$SERVICE_NAME" \
  --desired-status RUNNING \
  --region "$REGION" \
  --query 'taskArns' \
  --output text 2>/dev/null || echo "")

if [ -z "$RUNNING_TASKS" ] || [ "$RUNNING_TASKS" == "None" ]; then
  echo "  ❌ No running tasks!"
  echo ""
  echo "  Checking for stopped tasks..."
  STOPPED_TASKS=$(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --desired-status STOPPED \
    --region "$REGION" \
    --max-items 3 \
    --query 'taskArns' \
    --output text 2>/dev/null || echo "")
  
  if [ ! -z "$STOPPED_TASKS" ] && [ "$STOPPED_TASKS" != "None" ]; then
    echo "  ⚠️  Found stopped tasks - checking why..."
    FIRST_STOPPED=$(echo "$STOPPED_TASKS" | tr ' ' '\n' | head -1)
    
    STOPPED_DETAILS=$(aws ecs describe-tasks \
      --cluster "$CLUSTER_NAME" \
      --tasks "$FIRST_STOPPED" \
      --region "$REGION" \
      --query 'tasks[0].[stopCode,stoppedReason,containers[*].[name,exitCode,reason,lastStatus]]' \
      --output json 2>/dev/null || echo "{}")
    
    echo "$STOPPED_DETAILS" | jq -r '.stopCode // "N/A"' | sed 's/^/     Stop Code: /'
    echo "$STOPPED_DETAILS" | jq -r '.stoppedReason // "N/A"' | sed 's/^/     Reason: /'
    echo ""
    echo "     Container Status:"
    echo "$STOPPED_DETAILS" | jq -r '.containers[]? | "       \(.name): Exit Code \(.exitCode // "N/A") - \(.reason // "N/A")"' || echo "       Could not get container details"
  else
    echo "  ℹ️  No stopped tasks found either"
    echo "     Tasks may not have started yet"
  fi
  
  echo ""
  echo "  📋 Recent Service Events:"
  aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$REGION" \
    --query 'services[0].events[:5].[createdAt,message]' \
    --output table 2>/dev/null | head -15 || echo "     Could not fetch events"
  
  exit 1
fi

TASK_COUNT=$(echo "$RUNNING_TASKS" | wc -w | tr -d ' ')
echo "  ✅ Found $TASK_COUNT running task(s)"
echo ""

# Check each running task in detail
for task_arn in $RUNNING_TASKS; do
  TASK_ID=$(echo $task_arn | cut -d'/' -f3)
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Task: $TASK_ID"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Get task details
  TASK_DETAILS=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$task_arn" \
    --region "$REGION" \
    --query 'tasks[0].[lastStatus,desiredStatus,healthStatus,startedAt,connectivity,connectivityAt]' \
    --output text 2>/dev/null || echo "")
  
  if [ ! -z "$TASK_DETAILS" ]; then
    LAST_STATUS=$(echo "$TASK_DETAILS" | awk '{print $1}')
    DESIRED_STATUS=$(echo "$TASK_DETAILS" | awk '{print $2}')
    HEALTH_STATUS=$(echo "$TASK_DETAILS" | awk '{print $3}')
    STARTED_AT=$(echo "$TASK_DETAILS" | awk '{print $4}')
    CONNECTIVITY=$(echo "$TASK_DETAILS" | awk '{print $5}')
    CONNECTIVITY_AT=$(echo "$TASK_DETAILS" | awk '{print $6}')
    
    echo "  Status: $LAST_STATUS"
    echo "  Desired: $DESIRED_STATUS"
    echo "  Health: ${HEALTH_STATUS:-N/A}"
    echo "  Started: ${STARTED_AT:-N/A}"
    echo "  Connectivity: ${CONNECTIVITY:-N/A}"
    echo ""
  fi
  
  # Check containers
  echo "  📦 Container Status:"
  CONTAINERS=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$task_arn" \
    --region "$REGION" \
    --query 'tasks[0].containers[*].[name,lastStatus,healthStatus,exitCode,reason]' \
    --output json 2>/dev/null || echo "[]")
  
  echo "$CONTAINERS" | jq -r '.[] | "    \(.name): \(.lastStatus) | Health: \(.healthStatus // "N/A") | Exit: \(.exitCode // "N/A")"' || echo "    Could not get container info"
  
  # Check for issues
  echo ""
  echo "  🔍 Health Check:"
  UNHEALTHY=$(echo "$CONTAINERS" | jq -r '.[] | select(.healthStatus == "UNHEALTHY") | .name' || echo "")
  if [ ! -z "$UNHEALTHY" ]; then
    echo "    ⚠️  Unhealthy containers: $UNHEALTHY"
  else
    echo "    ✅ All containers healthy or health checks not configured"
  fi
  
  EXIT_CODE=$(echo "$CONTAINERS" | jq -r '.[] | select(.exitCode != null and .exitCode != 0) | "\(.name): \(.exitCode)"' || echo "")
  if [ ! -z "$EXIT_CODE" ]; then
    echo "    ⚠️  Containers with exit codes:"
    echo "$EXIT_CODE" | sed 's/^/      /'
  fi
  
  # Check logs
  echo ""
  echo "  📋 Log Streams:"
  for container in Postgres GitSync RepoSyncer KestraServer; do
    LOG_STREAM="${container}/${TASK_ID}"
    LOG_EXISTS=$(aws logs describe-log-streams \
      --log-group-name "$LOG_GROUP" \
      --log-stream-name-prefix "$LOG_STREAM" \
      --region "$REGION" \
      --max-items 1 \
      --query 'logStreams[0].logStreamName' \
      --output text 2>/dev/null || echo "")
    
    if [ ! -z "$LOG_EXISTS" ] && [ "$LOG_EXISTS" != "None" ]; then
      # Get last log line
      LAST_LOG=$(aws logs get-log-events \
        --log-group-name "$LOG_GROUP" \
        --log-stream-name "$LOG_EXISTS" \
        --region "$REGION" \
        --limit 1 \
        --query 'events[0].message' \
        --output text 2>/dev/null || echo "")
      
      echo "    ✅ $container: Log stream exists"
      if [ ! -z "$LAST_LOG" ] && [ "$LAST_LOG" != "None" ]; then
        echo "       Last log: $(echo "$LAST_LOG" | cut -c1-80)..."
      fi
    else
      echo "    ⚠️  $container: No log stream yet"
    fi
  done
  
  # Check task networking
  echo ""
  echo "  🌐 Network Configuration:"
  NETWORK=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$task_arn" \
    --region "$REGION" \
    --query 'tasks[0].attachments[0].details[*].[name,value]' \
    --output json 2>/dev/null || echo "[]")
  
  ENI_ID=$(echo "$NETWORK" | jq -r '.[] | select(.[0] == "networkInterfaceId") | .[1]' || echo "")
  if [ ! -z "$ENI_ID" ]; then
    echo "    Network Interface: $ENI_ID"
    
    # Get IP addresses
    PRIVATE_IP=$(aws ec2 describe-network-interfaces \
      --network-interface-ids "$ENI_ID" \
      --region "$REGION" \
      --query 'NetworkInterfaces[0].PrivateIpAddress' \
      --output text 2>/dev/null || echo "N/A")
    
    echo "    Private IP: $PRIVATE_IP"
  fi
  
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Task Health Check Complete!"
echo ""
echo "Summary:"
echo "  - Service: $SERVICE_NAME"
echo "  - Desired: $DESIRED | Running: $RUNNING | Pending: $PENDING"
echo "  - Task Definition: $TASK_DEF_STATUS"
echo "  - Running Tasks: $TASK_COUNT"
echo ""
echo "💡 If tasks are not running correctly:"
echo "   1. Check service events for errors"
echo "   2. Review CloudWatch logs: /ecs/kestra"
echo "   3. Verify secrets are accessible"
echo "   4. Check EFS mount points"
echo "   5. Review container health checks"

