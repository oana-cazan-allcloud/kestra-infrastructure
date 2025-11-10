#!/bin/bash
# Diagnose why ECS tasks aren't running

set -e

REGION="${AWS_REGION:-eu-central-1}"
CLUSTER_NAME="${CLUSTER_NAME:-kestra-cluster}"
AWS_PROFILE="${AWS_PROFILE:-data-sandbox}"

# Export profile for AWS CLI
export AWS_PROFILE

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🔍 Diagnosing ECS Task Startup Issues"
echo "======================================"
echo "Region: $REGION"
echo "Profile: $AWS_PROFILE"
echo ""

# Check AWS credentials
if ! aws sts get-caller-identity --region "$REGION" &>/dev/null; then
    echo -e "${RED}❌ AWS credentials are invalid or expired!${NC}"
    echo "   Please refresh credentials first"
    exit 1
fi

# Find the service
echo "1️⃣  Finding ECS Service..."
SERVICE_ARNS=$(aws ecs list-services --cluster "$CLUSTER_NAME" --region "$REGION" --query 'serviceArns[]' --output text 2>/dev/null || echo "")

if [ -z "$SERVICE_ARNS" ]; then
    echo -e "${YELLOW}⚠️  No services found in cluster${NC}"
    echo "   Service may not be deployed yet"
    exit 1
fi

SERVICE_ARN=$(echo "$SERVICE_ARNS" | awk '{print $1}')
SERVICE_NAME=$(echo "$SERVICE_ARN" | awk -F'/' '{print $NF}')
echo "   Found: $SERVICE_NAME"
echo ""

# Get service details
echo "2️⃣  Service Status..."
SERVICE_INFO=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$REGION" \
    --query 'services[0]' 2>/dev/null)

if [ -z "$SERVICE_INFO" ] || [ "$SERVICE_INFO" == "null" ]; then
    echo -e "${RED}❌ Could not get service details${NC}"
    exit 1
fi

STATUS=$(echo "$SERVICE_INFO" | jq -r '.status')
DESIRED=$(echo "$SERVICE_INFO" | jq -r '.desiredCount')
RUNNING=$(echo "$SERVICE_INFO" | jq -r '.runningCount')
PENDING=$(echo "$SERVICE_INFO" | jq -r '.pendingCount')
DEPLOYMENT_STATUS=$(echo "$SERVICE_INFO" | jq -r '.deployments[0].status // "UNKNOWN"')
FAILED_TASKS=$(echo "$SERVICE_INFO" | jq -r '.deployments[0].failedTasks // 0')

echo "   Status: $STATUS"
echo "   Desired: $DESIRED"
echo "   Running: $RUNNING"
echo "   Pending: $PENDING"
echo "   Deployment Status: $DEPLOYMENT_STATUS"
echo "   Failed Tasks: $FAILED_TASKS"
echo ""

# Check service events
echo "3️⃣  Recent Service Events (last 5)..."
echo "$SERVICE_INFO" | jq -r '.events[:5][] | "   [\(.createdAt)] \(.message)"' 2>/dev/null || echo "   Could not fetch events"
echo ""

# Check stopped tasks
echo "4️⃣  Checking Stopped Tasks..."
STOPPED_TASKS=$(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --desired-status STOPPED \
    --region "$REGION" \
    --query 'taskArns[:3]' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$STOPPED_TASKS" ] && [ "$STOPPED_TASKS" != "None" ]; then
    echo "   Found stopped tasks - checking reasons..."
    for TASK_ARN in $STOPPED_TASKS; do
        TASK_ID=$(echo "$TASK_ARN" | awk -F'/' '{print $NF}')
        echo ""
        echo "   Task: $TASK_ID"
        
        TASK_DETAILS=$(aws ecs describe-tasks \
            --cluster "$CLUSTER_NAME" \
            --tasks "$TASK_ARN" \
            --region "$REGION" \
            --query 'tasks[0]' 2>/dev/null)
        
        if [ ! -z "$TASK_DETAILS" ] && [ "$TASK_DETAILS" != "null" ]; then
            STOP_CODE=$(echo "$TASK_DETAILS" | jq -r '.stopCode // "N/A"')
            STOP_REASON=$(echo "$TASK_DETAILS" | jq -r '.stoppedReason // "N/A"')
            EXIT_CODE=$(echo "$TASK_DETAILS" | jq -r '.containers[0].exitCode // "N/A"')
            
            echo "      Stop Code: $STOP_CODE"
            echo "      Stop Reason: $STOP_REASON"
            echo "      Exit Code: $EXIT_CODE"
            
            # Check container reasons
            echo "      Container Issues:"
            echo "$TASK_DETAILS" | jq -r '.containers[] | "         - \(.name): exitCode=\(.exitCode // "N/A"), reason=\(.reason // "N/A")"' 2>/dev/null || echo "         (could not parse)"
        fi
    done
else
    echo "   No stopped tasks found"
fi
echo ""

# Check container instance capacity
echo "5️⃣  Container Instance Capacity..."
CONTAINER_INSTANCES=$(aws ecs list-container-instances \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --query 'containerInstanceArns[]' \
    --output text 2>/dev/null || echo "")

if [ -z "$CONTAINER_INSTANCES" ]; then
    echo -e "${RED}❌ No container instances registered!${NC}"
    echo "   Cannot run tasks without container instances"
else
    INSTANCE_COUNT=$(echo "$CONTAINER_INSTANCES" | wc -w | tr -d ' ')
    echo "   Registered Instances: $INSTANCE_COUNT"
    
    # Check resources on first instance
    FIRST_INSTANCE=$(echo "$CONTAINER_INSTANCES" | awk '{print $1}')
    INSTANCE_DETAILS=$(aws ecs describe-container-instances \
        --cluster "$CLUSTER_NAME" \
        --container-instances "$FIRST_INSTANCE" \
        --region "$REGION" \
        --query 'containerInstances[0]' 2>/dev/null)
    
    if [ ! -z "$INSTANCE_DETAILS" ] && [ "$INSTANCE_DETAILS" != "null" ]; then
        AVAILABLE_CPU=$(echo "$INSTANCE_DETAILS" | jq -r '.remainingResources[] | select(.name=="CPU") | .integerValue' 2>/dev/null || echo "N/A")
        AVAILABLE_MEMORY=$(echo "$INSTANCE_DETAILS" | jq -r '.remainingResources[] | select(.name=="MEMORY") | .integerValue' 2>/dev/null || echo "N/A")
        STATUS=$(echo "$INSTANCE_DETAILS" | jq -r '.status' 2>/dev/null || echo "N/A")
        
        echo "   Instance Status: $STATUS"
        echo "   Available CPU: $AVAILABLE_CPU"
        echo "   Available Memory: ${AVAILABLE_MEMORY}MB"
    fi
fi
echo ""

# Check task definition
echo "6️⃣  Task Definition Check..."
TASK_DEF_ARN=$(echo "$SERVICE_INFO" | jq -r '.taskDefinition' 2>/dev/null)
if [ ! -z "$TASK_DEF_ARN" ] && [ "$TASK_DEF_ARN" != "null" ]; then
    TASK_DEF_NAME=$(echo "$TASK_DEF_ARN" | awk -F'/' '{print $NF}' | awk -F':' '{print $1}')
    REVISION=$(echo "$TASK_DEF_ARN" | awk -F'/' '{print $NF}' | awk -F':' '{print $2}')
    
    echo "   Task Definition: $TASK_DEF_NAME (Revision: $REVISION)"
    
    TASK_DEF=$(aws ecs describe-task-definition \
        --task-definition "$TASK_DEF_ARN" \
        --region "$REGION" \
        --query 'taskDefinition' 2>/dev/null)
    
    if [ ! -z "$TASK_DEF" ] && [ "$TASK_DEF" != "null" ]; then
        CPU=$(echo "$TASK_DEF" | jq -r '.cpu // "N/A"')
        MEMORY=$(echo "$TASK_DEF" | jq -r '.memory // "N/A"')
        CONTAINER_COUNT=$(echo "$TASK_DEF" | jq -r '.containerDefinitions | length')
        
        echo "   CPU: $CPU"
        echo "   Memory: $MEMORY"
        echo "   Containers: $CONTAINER_COUNT"
    fi
fi
echo ""

# Summary and recommendations
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Diagnosis Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$RUNNING" -gt 0 ]; then
    echo -e "${GREEN}✅ Tasks are running!${NC}"
elif [ "$PENDING" -gt 0 ]; then
    echo -e "${YELLOW}⏳ Tasks are pending - may be starting up${NC}"
elif [ "$FAILED_TASKS" -gt 0 ]; then
    echo -e "${RED}❌ Tasks are failing - check stopped tasks above${NC}"
    echo ""
    echo "Common causes:"
    echo "  - Container exit code != 0 (check logs)"
    echo "  - Insufficient CPU/memory"
    echo "  - Network/security group issues"
    echo "  - Missing secrets or environment variables"
elif [ "$DESIRED" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Service desired count is 0${NC}"
    echo "   Service may have been scaled down"
else
    echo -e "${YELLOW}⚠️  Tasks not starting - check events and stopped tasks above${NC}"
fi

echo ""
echo "💡 Next Steps:"
echo "  1. Check CloudWatch logs: aws logs tail /ecs/kestra --follow"
echo "  2. Check service events above for errors"
echo "  3. Review stopped task reasons above"
echo "  4. Verify container instance has enough resources"

