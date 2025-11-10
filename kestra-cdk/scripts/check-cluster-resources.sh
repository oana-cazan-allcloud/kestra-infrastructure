#!/bin/bash
# Comprehensive check of all Kestra ECS cluster resources

set -e

REGION="${AWS_REGION:-eu-central-1}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
AWS_PROFILE="${AWS_PROFILE:-data-sandbox}"

# Export profile for AWS CLI
export AWS_PROFILE

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Checking Kestra ECS Cluster Resources"
echo "=========================================="
echo "Region: $REGION"
echo "Profile: $AWS_PROFILE"
echo ""

# Check AWS credentials
if ! aws sts get-caller-identity --region "$REGION" &>/dev/null; then
    echo -e "${RED}❌ AWS credentials are invalid or expired!${NC}"
    echo "   Please run: aws sso login"
    echo "   Or configure credentials: aws configure"
    exit 1
fi

# Auto-detect cluster if not provided
if [ -z "$CLUSTER_NAME" ]; then
    echo "🔍 Auto-detecting cluster..."
    CLUSTER_NAME=$(aws ecs list-clusters --region "$REGION" --query 'clusterArns[]' --output text 2>/dev/null | tr '\t' '\n' | grep -i kestra | awk -F'/' '{print $NF}' | head -1)
    
    if [ -z "$CLUSTER_NAME" ]; then
        # Try to find any cluster
        CLUSTER_NAME=$(aws ecs list-clusters --region "$REGION" --query 'clusterArns[0]' --output text 2>/dev/null | awk -F'/' '{print $NF}')
    fi
    
    if [ -z "$CLUSTER_NAME" ]; then
        echo -e "${RED}❌ No clusters found in region $REGION${NC}"
        echo "   Please specify cluster name: CLUSTER_NAME=your-cluster-name ./check-cluster-resources.sh"
        exit 1
    fi
fi

echo "Cluster: $CLUSTER_NAME"
echo ""

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
    else
        echo -e "${RED}❌ $2${NC}"
    fi
}

# 1. Check Cluster Status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1️⃣  ECS Cluster Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
CLUSTER_INFO=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$REGION" 2>/dev/null || echo "")
if [ -z "$CLUSTER_INFO" ] || [ "$(echo "$CLUSTER_INFO" | jq -r '.clusters[0].status // "MISSING"')" == "MISSING" ]; then
    echo -e "${RED}❌ Cluster '$CLUSTER_NAME' not found!${NC}"
    exit 1
fi

CLUSTER_STATUS=$(echo "$CLUSTER_INFO" | jq -r '.clusters[0].status')
ACTIVE_SERVICES=$(echo "$CLUSTER_INFO" | jq -r '.clusters[0].activeServicesCount // 0')
RUNNING_TASKS=$(echo "$CLUSTER_INFO" | jq -r '.clusters[0].runningTasksCount // 0')
PENDING_TASKS=$(echo "$CLUSTER_INFO" | jq -r '.clusters[0].pendingTasksCount // 0')
REGISTERED_CONTAINERS=$(echo "$CLUSTER_INFO" | jq -r '.clusters[0].registeredContainerInstancesCount // 0')

echo "   Status: $CLUSTER_STATUS"
echo "   Active Services: $ACTIVE_SERVICES"
echo "   Running Tasks: $RUNNING_TASKS"
echo "   Pending Tasks: $PENDING_TASKS"
echo "   Registered Container Instances: $REGISTERED_CONTAINERS"
echo ""

# 2. Check Services
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2️⃣  ECS Services"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SERVICES=$(aws ecs list-services --cluster "$CLUSTER_NAME" --region "$REGION" --query 'serviceArns[]' --output text 2>/dev/null || echo "")

if [ -z "$SERVICES" ]; then
    echo -e "${YELLOW}⚠️  No services found in cluster${NC}"
else
    for SERVICE_ARN in $SERVICES; do
        SERVICE_NAME=$(echo "$SERVICE_ARN" | awk -F'/' '{print $NF}')
        echo ""
        echo "   Service: $SERVICE_NAME"
        
        SERVICE_DETAILS=$(aws ecs describe-services \
            --cluster "$CLUSTER_NAME" \
            --services "$SERVICE_NAME" \
            --region "$REGION" 2>/dev/null | jq -r '.services[0]')
        
        if [ "$SERVICE_DETAILS" != "null" ] && [ ! -z "$SERVICE_DETAILS" ]; then
            STATUS=$(echo "$SERVICE_DETAILS" | jq -r '.status')
            DESIRED=$(echo "$SERVICE_DETAILS" | jq -r '.desiredCount')
            RUNNING=$(echo "$SERVICE_DETAILS" | jq -r '.runningCount')
            PENDING=$(echo "$SERVICE_DETAILS" | jq -r '.pendingCount')
            DEPLOYMENT_STATUS=$(echo "$SERVICE_DETAILS" | jq -r '.deployments[0].status // "UNKNOWN"')
            TASK_DEF=$(echo "$SERVICE_DETAILS" | jq -r '.taskDefinition' | awk -F'/' '{print $NF}')
            
            echo "      Status: $STATUS"
            echo "      Desired: $DESIRED | Running: $RUNNING | Pending: $PENDING"
            echo "      Deployment Status: $DEPLOYMENT_STATUS"
            echo "      Task Definition: $TASK_DEF"
            
            if [ "$RUNNING" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ] && [ "$DEPLOYMENT_STATUS" == "PRIMARY" ]; then
                echo -e "      ${GREEN}✅ Service is healthy${NC}"
            else
                echo -e "      ${YELLOW}⚠️  Service may have issues${NC}"
            fi
        fi
    done
fi
echo ""

# 3. Check Running Tasks
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3️⃣  Running Tasks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TASK_ARNS=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --region "$REGION" --query 'taskArns[]' --output text 2>/dev/null || echo "")

if [ -z "$TASK_ARNS" ]; then
    echo -e "${YELLOW}⚠️  No running tasks found${NC}"
else
    TASK_COUNT=$(echo "$TASK_ARNS" | wc -w | tr -d ' ')
    echo "   Found $TASK_COUNT task(s)"
    echo ""
    
    for TASK_ARN in $TASK_ARNS; do
        TASK_ID=$(echo "$TASK_ARN" | awk -F'/' '{print $NF}')
        echo "   Task: $TASK_ID"
        
        TASK_DETAILS=$(aws ecs describe-tasks \
            --cluster "$CLUSTER_NAME" \
            --tasks "$TASK_ARN" \
            --region "$REGION" 2>/dev/null | jq -r '.tasks[0]')
        
        if [ "$TASK_DETAILS" != "null" ] && [ ! -z "$TASK_DETAILS" ]; then
            LAST_STATUS=$(echo "$TASK_DETAILS" | jq -r '.lastStatus')
            HEALTH_STATUS=$(echo "$TASK_DETAILS" | jq -r '.healthStatus // "UNKNOWN"')
            DESIRED_STATUS=$(echo "$TASK_DETAILS" | jq -r '.desiredStatus')
            TASK_DEF_ARN=$(echo "$TASK_DETAILS" | jq -r '.taskDefinitionArn' | awk -F'/' '{print $NF}')
            
            echo "      Status: $LAST_STATUS"
            echo "      Health: $HEALTH_STATUS"
            echo "      Desired: $DESIRED_STATUS"
            echo "      Task Definition: $TASK_DEF_ARN"
            
            # Check containers
            CONTAINERS=$(echo "$TASK_DETAILS" | jq -r '.containers[]')
            if [ ! -z "$CONTAINERS" ]; then
                echo "      Containers:"
                echo "$CONTAINERS" | jq -r '.[] | "         - \(.name): \(.lastStatus) (Health: \(.healthStatus // "N/A"))"'
            fi
            
            if [ "$LAST_STATUS" == "RUNNING" ] && [ "$HEALTH_STATUS" == "HEALTHY" ]; then
                echo -e "      ${GREEN}✅ Task is healthy${NC}"
            elif [ "$LAST_STATUS" == "RUNNING" ]; then
                echo -e "      ${YELLOW}⚠️  Task is running but health status unknown${NC}"
            else
                echo -e "      ${RED}❌ Task is not running properly${NC}"
            fi
            echo ""
        fi
    done
fi
echo ""

# 4. Check Task Definitions
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4️⃣  Task Definitions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# Search for task definitions with 'kestra' or 'Kestra' in the name (case-insensitive)
ALL_TASK_DEFS=$(aws ecs list-task-definitions --region "$REGION" --query 'taskDefinitionArns[]' --output text 2>/dev/null || echo "")
TASK_DEFS=$(echo "$ALL_TASK_DEFS" | tr '\t' '\n' | grep -i kestra || echo "")

if [ -z "$TASK_DEFS" ]; then
    echo -e "${YELLOW}⚠️  No task definitions found with 'kestra' in name${NC}"
    echo "   Checking for any recent task definitions..."
    RECENT_TASK_DEFS=$(echo "$ALL_TASK_DEFS" | tr '\t' '\n' | head -5)
    if [ ! -z "$RECENT_TASK_DEFS" ]; then
        echo "   Recent task definitions:"
        echo "$RECENT_TASK_DEFS" | awk -F'/' '{print "      - " $NF}' | head -5
    fi
else
    for TASK_DEF_ARN in $TASK_DEFS; do
        TASK_DEF_NAME=$(echo "$TASK_DEF_ARN" | awk -F'/' '{print $NF}' | awk -F':' '{print $1}')
        REVISION=$(echo "$TASK_DEF_ARN" | awk -F'/' '{print $NF}' | awk -F':' '{print $2}')
        
        TASK_DEF_DETAILS=$(aws ecs describe-task-definition \
            --task-definition "$TASK_DEF_ARN" \
            --region "$REGION" 2>/dev/null | jq -r '.taskDefinition')
        
        if [ "$TASK_DEF_DETAILS" != "null" ] && [ ! -z "$TASK_DEF_DETAILS" ]; then
            STATUS=$(echo "$TASK_DEF_DETAILS" | jq -r '.status // "ACTIVE"')
            CONTAINER_COUNT=$(echo "$TASK_DEF_DETAILS" | jq -r '.containerDefinitions | length')
            
            echo "   $TASK_DEF_NAME (Revision: $REVISION)"
            echo "      Status: $STATUS"
            echo "      Containers: $CONTAINER_COUNT"
            
            if [ "$STATUS" == "ACTIVE" ]; then
                echo -e "      ${GREEN}✅ Task definition is active${NC}"
            else
                echo -e "      ${YELLOW}⚠️  Task definition status: $STATUS${NC}"
            fi
            echo ""
        fi
    done
fi
echo ""

# 5. Check ALB and Target Groups
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5️⃣  Application Load Balancer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ALB_ARN=$(aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[?contains(LoadBalancerName, `kestra`) || contains(LoadBalancerName, `Kestra`)].LoadBalancerArn' --output text 2>/dev/null || echo "")

if [ -z "$ALB_ARN" ]; then
    echo -e "${YELLOW}⚠️  No ALB found with 'kestra' in name${NC}"
else
    ALB_NAME=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --region "$REGION" --query 'LoadBalancers[0].LoadBalancerName' --output text 2>/dev/null)
    ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --region "$REGION" --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null)
    ALB_STATE=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --region "$REGION" --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null)
    
    echo "   ALB Name: $ALB_NAME"
    echo "   DNS: $ALB_DNS"
    echo "   State: $ALB_STATE"
    
    if [ "$ALB_STATE" == "active" ]; then
        echo -e "   ${GREEN}✅ ALB is active${NC}"
    else
        echo -e "   ${YELLOW}⚠️  ALB state: $ALB_STATE${NC}"
    fi
    
    # Check Target Groups
    echo ""
    echo "   Target Groups:"
    TG_ARNS=$(aws elbv2 describe-target-groups --load-balancer-arn "$ALB_ARN" --region "$REGION" --query 'TargetGroups[].TargetGroupArn' --output text 2>/dev/null || echo "")
    
    if [ ! -z "$TG_ARNS" ]; then
        for TG_ARN in $TG_ARNS; do
            TG_NAME=$(aws elbv2 describe-target-groups --target-group-arns "$TG_ARN" --region "$REGION" --query 'TargetGroups[0].TargetGroupName' --output text 2>/dev/null)
            TG_HEALTH=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --region "$REGION" 2>/dev/null || echo "")
            
            HEALTHY_COUNT=$(echo "$TG_HEALTH" | jq -r '[.TargetHealthDescriptions[] | select(.TargetHealth.State == "healthy")] | length' 2>/dev/null || echo "0")
            UNHEALTHY_COUNT=$(echo "$TG_HEALTH" | jq -r '[.TargetHealthDescriptions[] | select(.TargetHealth.State != "healthy")] | length' 2>/dev/null || echo "0")
            TOTAL_TARGETS=$(echo "$TG_HEALTH" | jq -r '.TargetHealthDescriptions | length' 2>/dev/null || echo "0")
            
            echo "      $TG_NAME"
            echo "         Healthy: $HEALTHY_COUNT | Unhealthy: $UNHEALTHY_COUNT | Total: $TOTAL_TARGETS"
            
            if [ "$HEALTHY_COUNT" -gt 0 ] && [ "$UNHEALTHY_COUNT" -eq 0 ]; then
                echo -e "         ${GREEN}✅ All targets healthy${NC}"
            elif [ "$HEALTHY_COUNT" -gt 0 ]; then
                echo -e "         ${YELLOW}⚠️  Some targets unhealthy${NC}"
            else
                echo -e "         ${RED}❌ No healthy targets${NC}"
            fi
        done
    fi
fi
echo ""

# 6. Check EFS Mount Targets
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6️⃣  EFS File System"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# Get all EFS and filter for kestra (case-insensitive)
ALL_EFS=$(aws efs describe-file-systems --region "$REGION" --query 'FileSystems[*].[FileSystemId,Name]' --output text 2>/dev/null || echo "")
EFS_IDS=$(echo "$ALL_EFS" | grep -i kestra | awk '{print $1}' | tr '\n' ' ' || echo "")

if [ -z "$EFS_IDS" ]; then
    echo -e "${YELLOW}⚠️  No EFS file systems found with 'kestra' in name${NC}"
    echo "   Available EFS file systems:"
    echo "$ALL_EFS" | head -5 | awk '{print "      - " $1 " (Name: " ($2 ? $2 : "None") ")"}'
else
    for EFS_ID in $EFS_IDS; do
        EFS_NAME=$(aws efs describe-file-systems --file-system-id "$EFS_ID" --region "$REGION" --query 'FileSystems[0].Name' --output text 2>/dev/null)
        EFS_STATE=$(aws efs describe-file-systems --file-system-id "$EFS_ID" --region "$REGION" --query 'FileSystems[0].LifeCycleState' --output text 2>/dev/null)
        
        echo "   EFS ID: $EFS_ID"
        echo "   Name: $EFS_NAME"
        echo "   State: $EFS_STATE"
        
        if [ "$EFS_STATE" == "available" ]; then
            echo -e "   ${GREEN}✅ EFS is available${NC}"
        else
            echo -e "   ${YELLOW}⚠️  EFS state: $EFS_STATE${NC}"
        fi
        
        # Check mount targets
        MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" --region "$REGION" --query 'MountTargets[]' 2>/dev/null || echo "[]")
        MT_COUNT=$(echo "$MOUNT_TARGETS" | jq -r 'length' 2>/dev/null || echo "0")
        MT_AVAILABLE=$(echo "$MOUNT_TARGETS" | jq -r '[.[] | select(.LifeCycleState == "available")] | length' 2>/dev/null || echo "0")
        
        echo "   Mount Targets: $MT_AVAILABLE/$MT_COUNT available"
        echo ""
    done
fi

# 7. Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Cluster: $CLUSTER_STATUS"
echo "Services: $ACTIVE_SERVICES active"
echo "Tasks: $RUNNING_TASKS running, $PENDING_TASKS pending"
echo "Container Instances: $REGISTERED_CONTAINERS registered"
echo ""

# More nuanced health check
if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
    echo -e "${RED}❌ Cluster is not ACTIVE - this is a problem!${NC}"
elif [ "$REGISTERED_CONTAINERS" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Cluster has no container instances - cannot run tasks${NC}"
elif [ "$ACTIVE_SERVICES" -eq 0 ]; then
    echo -e "${YELLOW}ℹ️  No ECS services deployed yet${NC}"
    echo "   → Deploy KestraEcsServiceStack to start running tasks"
    echo "   → Command: npx cdk deploy KestraEcsServiceStack"
elif [ "$RUNNING_TASKS" -eq 0 ] && [ "$ACTIVE_SERVICES" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Services exist but no tasks running - check service status above${NC}"
elif [ "$RUNNING_TASKS" -gt 0 ] && [ "$ACTIVE_SERVICES" -gt 0 ]; then
    echo -e "${GREEN}✅ Cluster is operational - services and tasks are running${NC}"
else
    echo -e "${YELLOW}ℹ️  Cluster is ready but waiting for services to be deployed${NC}"
fi

