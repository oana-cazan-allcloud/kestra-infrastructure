#!/bin/bash
# Explain why tasks aren't running and what needs to be deployed

set -e

REGION="eu-central-1"
CLUSTER_NAME="kestra-cluster"

echo "🔍 Understanding: Why Don't I Have Tasks?"
echo "=========================================="
echo ""
echo "In ECS, there are three related concepts:"
echo ""
echo "1️⃣  Task Definition (blueprint)"
echo "    └─ Created by: KestraEcsTaskStack"
echo "    └─ Defines: containers, CPU, memory, volumes, etc."
echo "    └─ This is just a template, not a running task"
echo ""
echo "2️⃣  Task (running instance)"
echo "    └─ Created by: ECS Service"
echo "    └─ Uses: Task Definition"
echo "    └─ This is the actual running container"
echo ""
echo "3️⃣  Service (task manager)"
echo "    └─ Created by: KestraEcsServiceStack"
echo "    └─ Manages: Starting/stopping tasks, keeping desired count"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check task definitions
echo "📋 Checking Task Definitions..."
TASK_DEFS=$(aws ecs list-task-definitions \
  --family-prefix "KestraEcsTaskStack-KestraTaskDef" \
  --region "$REGION" \
  --query 'taskDefinitionArns' \
  --output text 2>/dev/null || echo "")

if [ -z "$TASK_DEFS" ] || [ "$TASK_DEFS" == "None" ]; then
  echo "  ❌ Task Definition: NOT DEPLOYED"
  echo ""
  echo "  💡 Solution: Deploy the task stack"
  echo "     npx cdk deploy KestraEcsTaskStack"
  echo ""
  TASK_DEF_EXISTS=false
else
  echo "  ✅ Task Definition: EXISTS"
  LATEST_TASK_DEF=$(echo "$TASK_DEFS" | tr ' ' '\n' | head -1)
  echo "     Latest: $LATEST_TASK_DEF"
  echo ""
  TASK_DEF_EXISTS=true
fi

# Check service
echo "📋 Checking ECS Service..."
SERVICES=$(aws ecs list-services \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'serviceArns' \
  --output text 2>/dev/null || echo "")

if [ -z "$SERVICES" ] || [ "$SERVICES" == "None" ]; then
  echo "  ❌ Service: NOT DEPLOYED"
  echo ""
  echo "  💡 This is why you don't have tasks!"
  echo "     The service is what creates and manages tasks."
  echo ""
  SERVICE_EXISTS=false
else
  SERVICE_NAME=$(echo "$SERVICES" | tr ' ' '\n' | head -1 | cut -d'/' -f3)
  echo "  ✅ Service: EXISTS"
  echo "     Name: $SERVICE_NAME"
  echo ""
  
  # Check if service has tasks
  TASKS=$(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --region "$REGION" \
    --query 'taskArns' \
    --output text 2>/dev/null || echo "")
  
  if [ -z "$TASKS" ] || [ "$TASKS" == "None" ]; then
    echo "  ⚠️  Service exists but NO TASKS running"
    echo ""
    echo "  Checking service status..."
    SERVICE_INFO=$(aws ecs describe-services \
      --cluster "$CLUSTER_NAME" \
      --services "$SERVICE_NAME" \
      --region "$REGION" \
      --query 'services[0].[desiredCount,runningCount,pendingCount,deployments[0].status]' \
      --output text 2>/dev/null || echo "")
    
    if [ ! -z "$SERVICE_INFO" ]; then
      DESIRED=$(echo "$SERVICE_INFO" | awk '{print $1}')
      RUNNING=$(echo "$SERVICE_INFO" | awk '{print $2}')
      PENDING=$(echo "$SERVICE_INFO" | awk '{print $3}')
      DEPLOY_STATUS=$(echo "$SERVICE_INFO" | awk '{print $4}')
      
      echo "     Desired: $DESIRED"
      echo "     Running: $RUNNING"
      echo "     Pending: $PENDING"
      echo "     Deployment: $DEPLOY_STATUS"
      echo ""
      
      if [ "$RUNNING" == "0" ] && [ "$DESIRED" -gt "0" ]; then
        echo "  💡 Tasks are trying to start but failing"
        echo "     Check service events for errors:"
        echo "     aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $REGION --query 'services[0].events[:5]'"
      fi
    fi
  else
    echo "  ✅ Tasks: $(echo $TASKS | wc -w | tr -d ' ') running"
  fi
  SERVICE_EXISTS=true
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Summary:"
echo ""

if [ "$TASK_DEF_EXISTS" == "false" ]; then
  echo "  ❌ Task Definition missing"
  echo "     → Deploy: npx cdk deploy KestraEcsTaskStack"
  echo ""
fi

if [ "$SERVICE_EXISTS" == "false" ]; then
  echo "  ❌ Service missing (THIS IS WHY NO TASKS)"
  echo "     → Deploy: npx cdk deploy KestraEcsServiceStack"
  echo ""
  echo "  ⚠️  But first ensure:"
  echo "     ✅ Task stack is deployed"
  echo "     ✅ ALB stack is deployed"
fi

echo ""
echo "💡 Key Point:"
echo "   Task Definition = Recipe"
echo "   Service = Chef (uses recipe to create tasks)"
echo "   Task = The actual dish (running container)"
echo ""
echo "   Without a Service, you can't have Tasks!"
echo "   Even if Task Definition exists, nothing runs until Service is deployed."

