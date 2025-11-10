#!/bin/bash
# Comprehensive check of what's actually deployed in AWS

set -e

REGION="eu-central-1"
CLUSTER_NAME="kestra-cluster"

echo "🔍 Comprehensive AWS Deployment Check"
echo "======================================"
echo ""

# 1. Check cluster
echo "1️⃣ ECS Cluster..."
CLUSTER=$(aws ecs describe-clusters \
  --clusters "$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'clusters[0].clusterName' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER" != "NOT_FOUND" ] && [ "$CLUSTER" != "None" ]; then
  echo "  ✅ Cluster exists: $CLUSTER"
else
  echo "  ❌ Cluster NOT found"
fi

echo ""

# 2. Check task definitions
echo "2️⃣ Task Definitions..."
TASK_DEFS=$(aws ecs list-task-definitions \
  --family-prefix "KestraEcsTaskStack-KestraTaskDef" \
  --region "$REGION" \
  --query 'taskDefinitionArns' \
  --output text 2>/dev/null || echo "")

if [ ! -z "$TASK_DEFS" ] && [ "$TASK_DEFS" != "None" ]; then
  COUNT=$(echo "$TASK_DEFS" | wc -w | tr -d ' ')
  echo "  ✅ Found $COUNT task definition(s)"
  LATEST=$(echo "$TASK_DEFS" | tr ' ' '\n' | head -1)
  echo "     Latest: $(echo $LATEST | cut -d'/' -f2)"
  
  # Check status
  STATUS=$(aws ecs describe-task-definition \
    --task-definition "$LATEST" \
    --region "$REGION" \
    --query 'taskDefinition.status' \
    --output text 2>/dev/null || echo "UNKNOWN")
  echo "     Status: $STATUS"
else
  echo "  ❌ No task definitions found"
fi

echo ""

# 3. Check services
echo "3️⃣ ECS Services..."
SERVICES=$(aws ecs list-services \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'serviceArns' \
  --output text 2>/dev/null || echo "")

if [ ! -z "$SERVICES" ] && [ "$SERVICES" != "None" ]; then
  for service_arn in $SERVICES; do
    SERVICE_NAME=$(echo $service_arn | cut -d'/' -f3)
    echo "  ✅ Service found: $SERVICE_NAME"
    
    # Get service details
    SERVICE_INFO=$(aws ecs describe-services \
      --cluster "$CLUSTER_NAME" \
      --services "$SERVICE_NAME" \
      --region "$REGION" \
      --query 'services[0].[status,desiredCount,runningCount,pendingCount,deployments[0].status,deployments[0].taskDefinition]' \
      --output text 2>/dev/null || echo "")
    
    if [ ! -z "$SERVICE_INFO" ]; then
      STATUS=$(echo "$SERVICE_INFO" | awk '{print $1}')
      DESIRED=$(echo "$SERVICE_INFO" | awk '{print $2}')
      RUNNING=$(echo "$SERVICE_INFO" | awk '{print $3}')
      PENDING=$(echo "$SERVICE_INFO" | awk '{print $4}')
      DEPLOY_STATUS=$(echo "$SERVICE_INFO" | awk '{print $5}')
      TASK_DEF=$(echo "$SERVICE_INFO" | awk '{print $6}')
      
      echo "     Status: $STATUS"
      echo "     Desired: $DESIRED | Running: $RUNNING | Pending: $PENDING"
      echo "     Deployment: $DEPLOY_STATUS"
      echo "     Task Definition: $(echo $TASK_DEF | cut -d'/' -f2)"
      echo ""
      
      # Check for stopped tasks
      echo "     Checking for stopped tasks..."
      STOPPED_TASKS=$(aws ecs list-tasks \
        --cluster "$CLUSTER_NAME" \
        --service-name "$SERVICE_NAME" \
        --desired-status STOPPED \
        --region "$REGION" \
        --max-items 5 \
        --query 'taskArns' \
        --output text 2>/dev/null || echo "")
      
      if [ ! -z "$STOPPED_TASKS" ] && [ "$STOPPED_TASKS" != "None" ]; then
        STOPPED_COUNT=$(echo "$STOPPED_TASKS" | wc -w | tr -d ' ')
        echo "     ⚠️  Found $STOPPED_COUNT stopped task(s)"
        
        # Get details of first stopped task
        FIRST_STOPPED=$(echo "$STOPPED_TASKS" | tr ' ' '\n' | head -1)
        STOPPED_INFO=$(aws ecs describe-tasks \
          --cluster "$CLUSTER_NAME" \
          --tasks "$FIRST_STOPPED" \
          --region "$REGION" \
          --query 'tasks[0].[stopCode,stoppedReason,containers[*].[name,exitCode,reason]]' \
          --output json 2>/dev/null || echo "{}")
        
        echo "     Latest stopped task:"
        echo "$STOPPED_INFO" | jq -r '.stopCode // "N/A"' | sed 's/^/        Stop Code: /'
        echo "$STOPPED_INFO" | jq -r '.stoppedReason // "N/A"' | sed 's/^/        Reason: /'
      fi
      
      # Check recent events
      echo ""
      echo "     Recent service events:"
      aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --region "$REGION" \
        --query 'services[0].events[:3].[createdAt,message]' \
        --output table 2>/dev/null | head -10 || echo "        Could not fetch events"
    fi
  done
else
  echo "  ❌ No services found"
fi

echo ""

# 4. Check running tasks
echo "4️⃣ Running Tasks..."
if [ "$CLUSTER" != "NOT_FOUND" ] && [ "$CLUSTER" != "None" ]; then
  RUNNING_TASKS=$(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --desired-status RUNNING \
    --region "$REGION" \
    --query 'taskArns' \
    --output text 2>/dev/null || echo "")
  
  if [ ! -z "$RUNNING_TASKS" ] && [ "$RUNNING_TASKS" != "None" ]; then
    COUNT=$(echo "$RUNNING_TASKS" | wc -w | tr -d ' ')
    echo "  ✅ Found $COUNT running task(s)"
  else
    echo "  ❌ No running tasks"
  fi
else
  echo "  ⚠️  Cannot check (cluster not found)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Analysis:"
echo ""

if [ ! -z "$SERVICES" ] && [ "$SERVICES" != "None" ]; then
  if [ "$RUNNING" == "0" ] && [ "$DESIRED" -gt "0" ]; then
    echo "  ⚠️  Service exists but tasks aren't running"
    echo "     → Check service events above for errors"
    echo "     → Tasks may be failing to start"
  elif [ "$RUNNING" -gt "0" ]; then
    echo "  ✅ Tasks are running!"
    echo "     → Log streams should exist"
    echo "     → Check CloudWatch logs: /ecs/kestra"
  fi
else
  echo "  ❌ Service not deployed"
  echo "     → Deploy: npx cdk deploy KestraEcsServiceStack"
fi

echo ""
echo "✅ Check complete!"

