#!/bin/bash
# Check security group configurations for EFS mount issues

set -e

REGION="${AWS_REGION:-eu-central-1}"
AWS_PROFILE="${AWS_PROFILE:-data-sandbox}"

export AWS_PROFILE

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🔍 Checking Security Group Configuration for EFS Mount"
echo "======================================================="
echo "Region: $REGION"
echo "Profile: $AWS_PROFILE"
echo ""

# Find EFS
echo "1️⃣  Finding EFS File System..."
EFS_ID=$(aws efs describe-file-systems --region "$REGION" --query 'FileSystems[?contains(Name, `kestra`) || contains(Name, `Kestra`)].FileSystemId' --output text 2>/dev/null | head -1)

if [ -z "$EFS_ID" ]; then
    echo -e "${RED}❌ EFS not found${NC}"
    exit 1
fi

echo "   EFS ID: $EFS_ID"
echo ""

# Get EFS security group
echo "2️⃣  EFS Security Group Configuration..."
EFS_SG=$(aws efs describe-file-systems --file-system-id "$EFS_ID" --region "$REGION" --query 'FileSystems[0].SecurityGroups[0]' --output text 2>/dev/null)

if [ -z "$EFS_SG" ] || [ "$EFS_SG" == "None" ]; then
    echo -e "${RED}❌ EFS has no security group!${NC}"
    exit 1
fi

echo "   EFS Security Group: $EFS_SG"
echo ""

# Check EFS SG ingress rules
echo "   Ingress Rules (who can access EFS on port 2049):"
EFS_SG_RULES=$(aws ec2 describe-security-groups \
    --group-ids "$EFS_SG" \
    --region "$REGION" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`2049` || ToPort==`2049`]' \
    --output json 2>/dev/null)

if [ -z "$EFS_SG_RULES" ] || [ "$EFS_SG_RULES" == "[]" ] || [ "$EFS_SG_RULES" == "null" ]; then
    echo -e "   ${RED}❌ No NFS (2049) ingress rules found!${NC}"
    echo "   EFS security group must allow port 2049 from container instances"
else
    echo "$EFS_SG_RULES" | jq -r '.[] | "      ✅ Port \(.FromPort)-\(.ToPort): \(.IpProtocol) from \(.UserIdGroupPairs[0].GroupId // "unknown")"'
fi
echo ""

# Find cluster
echo "3️⃣  Finding ECS Cluster..."
CLUSTER_NAME=$(aws ecs list-clusters --region "$REGION" --query 'clusterArns[]' --output text 2>/dev/null | tr '\t' '\n' | grep -i kestra | awk -F'/' '{print $NF}' | head -1)

if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${YELLOW}⚠️  Cluster not found${NC}"
    exit 1
fi

echo "   Cluster: $CLUSTER_NAME"
echo ""

# Get container instances
echo "4️⃣  Container Instance Security Groups..."
CONTAINER_INSTANCES=$(aws ecs list-container-instances \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --query 'containerInstanceArns[]' \
    --output text 2>/dev/null | head -1)

if [ -z "$CONTAINER_INSTANCES" ] || [ "$CONTAINER_INSTANCES" == "None" ]; then
    echo -e "${YELLOW}⚠️  No container instances found${NC}"
else
    CONTAINER_INSTANCE_ID=$(echo "$CONTAINER_INSTANCES" | awk '{print $1}' | awk -F'/' '{print $NF}')
    echo "   Container Instance: $CONTAINER_INSTANCE_ID"
    
    # Get EC2 instance ID
    INSTANCE_DETAILS=$(aws ecs describe-container-instances \
        --cluster "$CLUSTER_NAME" \
        --container-instances "$CONTAINER_INSTANCES" \
        --region "$REGION" \
        --query 'containerInstances[0].ec2InstanceId' \
        --output text 2>/dev/null)
    
    if [ ! -z "$INSTANCE_DETAILS" ] && [ "$INSTANCE_DETAILS" != "None" ]; then
        echo "   EC2 Instance: $INSTANCE_DETAILS"
        
        # Get instance security groups
        INSTANCE_SGS=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_DETAILS" \
            --region "$REGION" \
            --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId' \
            --output text 2>/dev/null)
        
        echo "   Instance Security Groups:"
        for SG_ID in $INSTANCE_SGS; do
            SG_NAME=$(aws ec2 describe-security-groups \
                --group-ids "$SG_ID" \
                --region "$REGION" \
                --query 'SecurityGroups[0].GroupName' \
                --output text 2>/dev/null)
            echo "      - $SG_ID ($SG_NAME)"
            
            # Check if this SG can reach EFS
            CAN_REACH_EFS=$(aws ec2 describe-security-groups \
                --group-ids "$EFS_SG" \
                --region "$REGION" \
                --query "SecurityGroups[0].IpPermissions[?FromPort==\`2049\` && contains(UserIdGroupPairs[*].GroupId, \`$SG_ID\`)]" \
                --output text 2>/dev/null)
            
            if [ ! -z "$CAN_REACH_EFS" ] && [ "$CAN_REACH_EFS" != "None" ]; then
                echo -e "        ${GREEN}✅ Can access EFS (port 2049)${NC}"
            else
                echo -e "        ${RED}❌ Cannot access EFS (port 2049) - missing ingress rule${NC}"
            fi
        done
    fi
fi
echo ""

# Check task security groups
echo "5️⃣  Task Security Groups..."
SERVICES=$(aws ecs list-services --cluster "$CLUSTER_NAME" --region "$REGION" --query 'serviceArns[]' --output text 2>/dev/null | head -1)

if [ ! -z "$SERVICES" ] && [ "$SERVICES" != "None" ]; then
    SERVICE_NAME=$(echo "$SERVICES" | awk -F'/' '{print $NF}')
    SERVICE_DETAILS=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --region "$REGION" \
        --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups' \
        --output text 2>/dev/null)
    
    if [ ! -z "$SERVICE_DETAILS" ] && [ "$SERVICE_DETAILS" != "None" ]; then
        echo "   Service: $SERVICE_NAME"
        echo "   Task Security Groups:"
        for SG_ID in $SERVICE_DETAILS; do
            SG_NAME=$(aws ec2 describe-security-groups \
                --group-ids "$SG_ID" \
                --region "$REGION" \
                --query 'SecurityGroups[0].GroupName' \
                --output text 2>/dev/null)
            echo "      - $SG_ID ($SG_NAME)"
            
            # Check egress rules for NFS
            HAS_NFS_EGRESS=$(aws ec2 describe-security-groups \
                --group-ids "$SG_ID" \
                --region "$REGION" \
                --query "SecurityGroups[0].IpPermissionsEgress[?FromPort==\`2049\` && contains(UserIdGroupPairs[*].GroupId, \`$EFS_SG\`)]" \
                --output text 2>/dev/null)
            
            if [ ! -z "$HAS_NFS_EGRESS" ] && [ "$HAS_NFS_EGRESS" != "None" ]; then
                echo -e "        ${GREEN}✅ Has egress rule to EFS (port 2049)${NC}"
            else
                echo -e "        ${YELLOW}⚠️  No explicit egress rule to EFS${NC}"
                echo "        (May still work if allowAllOutbound is true)"
            fi
            
            # Check if EFS allows ingress from this SG
            CAN_REACH_EFS=$(aws ec2 describe-security-groups \
                --group-ids "$EFS_SG" \
                --region "$REGION" \
                --query "SecurityGroups[0].IpPermissions[?FromPort==\`2049\` && contains(UserIdGroupPairs[*].GroupId, \`$SG_ID\`)]" \
                --output text 2>/dev/null)
            
            if [ ! -z "$CAN_REACH_EFS" ] && [ "$CAN_REACH_EFS" != "None" ]; then
                echo -e "        ${GREEN}✅ EFS allows ingress from this SG${NC}"
            else
                echo -e "        ${RED}❌ EFS does NOT allow ingress from this SG${NC}"
            fi
        done
    fi
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Security Group Analysis Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "For EFS mounts to work, you need:"
echo "  1. ✅ EFS security group allows ingress on port 2049 from:"
echo "     - Container instance security group (for mounting)"
echo "     - Task security group (for task access)"
echo ""
echo "  2. ✅ Container instance security group can reach EFS"
echo "     (usually allowAllOutbound=true is sufficient)"
echo ""
echo "  3. ✅ Task security group can reach EFS"
echo "     (either explicit egress rule or allowAllOutbound=true)"
echo ""

