#!/bin/bash
# Check what's using a security group that's blocking deletion

set -e

REGION="${AWS_REGION:-eu-central-1}"
AWS_PROFILE="${AWS_PROFILE:-data-sandbox}"
SECURITY_GROUP_ID="${1}"

export AWS_PROFILE

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$SECURITY_GROUP_ID" ]; then
    echo "Usage: $0 <security-group-id>"
    echo ""
    echo "Finding security groups from Kestra stacks..."
    
    # Find ECS cluster security groups
    CLUSTER_NAME=$(aws ecs list-clusters --region "$REGION" --query 'clusterArns[]' --output text 2>/dev/null | tr '\t' '\n' | grep -i kestra | awk -F'/' '{print $NF}' | head -1)
    
    if [ ! -z "$CLUSTER_NAME" ]; then
        echo "Cluster: $CLUSTER_NAME"
        echo ""
        
        # Get container instances
        INSTANCES=$(aws ecs list-container-instances --cluster "$CLUSTER_NAME" --region "$REGION" --query 'containerInstanceArns[]' --output text 2>/dev/null | head -1)
        
        if [ ! -z "$INSTANCES" ] && [ "$INSTANCES" != "None" ]; then
            INSTANCE_ID=$(aws ecs describe-container-instances \
                --cluster "$CLUSTER_NAME" \
                --container-instances "$INSTANCES" \
                --region "$REGION" \
                --query 'containerInstances[0].ec2InstanceId' \
                --output text 2>/dev/null)
            
            if [ ! -z "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
                echo "Container Instance Security Groups:"
                aws ec2 describe-instances \
                    --instance-ids "$INSTANCE_ID" \
                    --region "$REGION" \
                    --query 'Reservations[0].Instances[0].SecurityGroups[*].[GroupId,GroupName]' \
                    --output table
            fi
        fi
        
        # Get service security groups
        SERVICES=$(aws ecs list-services --cluster "$CLUSTER_NAME" --region "$REGION" --query 'serviceArns[]' --output text 2>/dev/null | head -1)
        if [ ! -z "$SERVICES" ] && [ "$SERVICES" != "None" ]; then
            SERVICE_NAME=$(echo "$SERVICES" | awk -F'/' '{print $NF}')
            echo ""
            echo "Service Security Groups:"
            aws ecs describe-services \
                --cluster "$CLUSTER_NAME" \
                --services "$SERVICE_NAME" \
                --region "$REGION" \
                --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups[*]' \
                --output table
        fi
    fi
    
    exit 0
fi

echo "🔍 Checking what's using Security Group: $SECURITY_GROUP_ID"
echo "========================================================"
echo ""

# Check EC2 instances
echo "1️⃣  EC2 Instances using this security group..."
INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=instance.group-id,Values=$SECURITY_GROUP_ID" \
    --region "$REGION" \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$INSTANCES" ] && [ "$INSTANCES" != "None" ]; then
    echo "$INSTANCES" | while read INSTANCE_ID STATE; do
        echo "   Instance: $INSTANCE_ID (State: $STATE)"
        if [ "$STATE" == "running" ]; then
            echo -e "      ${RED}❌ Instance is running - must stop/terminate first${NC}"
        fi
    done
else
    echo "   ✅ No EC2 instances using this security group"
fi
echo ""

# Check ENIs (Elastic Network Interfaces)
echo "2️⃣  Network Interfaces using this security group..."
ENIS=$(aws ec2 describe-network-interfaces \
    --filters "Name=group-id,Values=$SECURITY_GROUP_ID" \
    --region "$REGION" \
    --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$ENIS" ] && [ "$ENIS" != "None" ]; then
    echo -e "${YELLOW}⚠️  Found network interfaces using this security group:${NC}"
    echo "$ENIS" | while read ENI_ID STATUS DESC; do
        echo "   ENI: $ENI_ID (Status: $STATUS)"
        echo "   Description: $DESC"
        
        # Check if it's attached to an instance
        ATTACHMENT=$(aws ec2 describe-network-interfaces \
            --network-interface-ids "$ENI_ID" \
            --region "$REGION" \
            --query 'NetworkInterfaces[0].Attachment.InstanceId' \
            --output text 2>/dev/null || echo "None")
        
        if [ "$ATTACHMENT" != "None" ] && [ ! -z "$ATTACHMENT" ]; then
            echo "   Attached to: $ATTACHMENT"
        fi
    done
else
    echo "   ✅ No network interfaces using this security group"
fi
echo ""

# Check ECS services
echo "3️⃣  ECS Services using this security group..."
CLUSTERS=$(aws ecs list-clusters --region "$REGION" --query 'clusterArns[]' --output text 2>/dev/null || echo "")

if [ ! -z "$CLUSTERS" ]; then
    for CLUSTER_ARN in $CLUSTERS; do
        CLUSTER_NAME=$(echo "$CLUSTER_ARN" | awk -F'/' '{print $NF}')
        SERVICES=$(aws ecs list-services --cluster "$CLUSTER_NAME" --region "$REGION" --query 'serviceArns[]' --output text 2>/dev/null || echo "")
        
        if [ ! -z "$SERVICES" ]; then
            for SERVICE_ARN in $SERVICES; do
                SERVICE_NAME=$(echo "$SERVICE_ARN" | awk -F'/' '{print $NF}')
                SERVICE_SGS=$(aws ecs describe-services \
                    --cluster "$CLUSTER_NAME" \
                    --services "$SERVICE_NAME" \
                    --region "$REGION" \
                    --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups[*]' \
                    --output text 2>/dev/null || echo "")
                
                if echo "$SERVICE_SGS" | grep -q "$SECURITY_GROUP_ID"; then
                    echo -e "${YELLOW}⚠️  Service $SERVICE_NAME in cluster $CLUSTER_NAME uses this SG${NC}"
                    echo "   You may need to update the service to use a new security group first"
                fi
            done
        fi
    done
else
    echo "   ✅ No ECS services found"
fi
echo ""

# Check RDS instances
echo "4️⃣  RDS Instances using this security group..."
RDS_INSTANCES=$(aws rds describe-db-instances \
    --region "$REGION" \
    --query "DBInstances[?contains(VpcSecurityGroups[*].VpcSecurityGroupId, \`$SECURITY_GROUP_ID\`)].[DBInstanceIdentifier,DBInstanceStatus]" \
    --output text 2>/dev/null || echo "")

if [ ! -z "$RDS_INSTANCES" ] && [ "$RDS_INSTANCES" != "None" ]; then
    echo -e "${YELLOW}⚠️  RDS instances using this security group:${NC}"
    echo "$RDS_INSTANCES"
else
    echo "   ✅ No RDS instances using this security group"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 To fix stuck deletion:"
echo ""
echo "1. If EC2 instances are using it:"
echo "   - Stop/terminate the instances"
echo "   - Or update instances to use a different security group"
echo ""
echo "2. If ECS service is using it:"
echo "   - Update service to use new security group"
echo "   - Or scale down service to 0 tasks first"
echo ""
echo "3. If network interfaces are using it:"
echo "   - Detach ENIs or delete them"
echo "   - Or wait for ECS to clean them up"

