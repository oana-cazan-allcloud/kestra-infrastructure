#!/bin/bash
# Comprehensive check of all Kestra CDK deployment stacks

set -e

REGION="${AWS_REGION:-eu-central-1}"
AWS_PROFILE="${AWS_PROFILE:-data-sandbox}"

# Export profile for AWS CLI
export AWS_PROFILE

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🔍 Kestra CDK Stacks Deployment Check"
echo "======================================"
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

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
    else
        echo -e "${RED}❌ $2${NC}"
    fi
}

# Function to check stack status
check_stack() {
    local STACK_NAME=$1
    local STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$STATUS" == "NOT_FOUND" ]; then
        echo -e "${YELLOW}⚠️  Stack not found${NC}"
        return 1
    elif [[ "$STATUS" == *"COMPLETE"* ]] && [[ ! "$STATUS" == *"ROLLBACK"* ]]; then
        echo -e "${GREEN}✅ $STATUS${NC}"
        return 0
    else
        echo -e "${RED}❌ $STATUS${NC}"
        return 1
    fi
}

# 1️⃣ VPC Stack
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1️⃣  KestraVpcStack"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if check_stack "KestraVpcStack"; then
    VPC_ID=$(aws cloudformation describe-stacks --stack-name "KestraVpcStack" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' --output text 2>/dev/null)
    echo "   VPC ID: $VPC_ID"
    
    # Check DNS settings
    DNS_SUPPORT=$(aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsSupport --region "$REGION" --query 'EnableDnsSupport.Value' --output text 2>/dev/null || echo "null")
    DNS_HOSTNAMES=$(aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsHostnames --region "$REGION" --query 'EnableDnsHostnames.Value' --output text 2>/dev/null || echo "null")
    echo "   DNS Support: ${DNS_SUPPORT:-null}"
    echo "   DNS Hostnames: ${DNS_HOSTNAMES:-null}"
fi
echo ""

# 2️⃣ ECS Cluster Stack
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2️⃣  KestraEcsClusterStack"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if check_stack "KestraEcsClusterStack"; then
    CLUSTER_NAME=$(aws cloudformation describe-stacks --stack-name "KestraEcsClusterStack" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' --output text 2>/dev/null)
    echo "   Cluster: $CLUSTER_NAME"
    
    # Check cluster status
    CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$REGION" --query 'clusters[0].status' --output text 2>/dev/null || echo "UNKNOWN")
    CONTAINER_INSTANCES=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$REGION" --query 'clusters[0].registeredContainerInstancesCount' --output text 2>/dev/null || echo "0")
    echo "   Status: $CLUSTER_STATUS"
    echo "   Container Instances: $CONTAINER_INSTANCES"
fi
echo ""

# 3️⃣ EFS Stack
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3️⃣  KestraEfsStack"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if check_stack "KestraEfsStack"; then
    EFS_ID=$(aws cloudformation describe-stacks --stack-name "KestraEfsStack" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`EfsId`].OutputValue' --output text 2>/dev/null)
    echo "   EFS ID: $EFS_ID"
    
    # Check EFS status
    EFS_STATUS=$(aws efs describe-file-systems --file-system-id "$EFS_ID" --region "$REGION" --query 'FileSystems[0].LifeCycleState' --output text 2>/dev/null || echo "UNKNOWN")
    MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" --region "$REGION" --query 'length(MountTargets)' --output text 2>/dev/null || echo "0")
    echo "   Status: $EFS_STATUS"
    echo "   Mount Targets: $MOUNT_TARGETS"
    
    # Check Access Points
    ACCESS_POINTS=$(aws efs describe-access-points --file-system-id "$EFS_ID" --region "$REGION" --query 'length(AccessPoints)' --output text 2>/dev/null || echo "0")
    echo "   Access Points: $ACCESS_POINTS"
fi
echo ""

# 4️⃣ S3 Stack
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4️⃣  KestraS3Stack"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if check_stack "KestraS3Stack"; then
    BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name "KestraS3Stack" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text 2>/dev/null)
    echo "   Bucket: $BUCKET_NAME"
    
    # Check bucket exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$REGION" &>/dev/null; then
        echo -e "   ${GREEN}✅ Bucket exists${NC}"
    else
        echo -e "   ${RED}❌ Bucket not found${NC}"
    fi
fi
echo ""

# 5️⃣ ALB Stack
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5️⃣  KestraAlbStack"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if check_stack "KestraAlbStack"; then
    ALB_DNS=$(aws cloudformation describe-stacks --stack-name "KestraAlbStack" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`AlbDnsName`].OutputValue' --output text 2>/dev/null)
    echo "   ALB DNS: $ALB_DNS"
    
    # Check ALB status
    ALB_ARN=$(aws cloudformation describe-stacks --stack-name "KestraAlbStack" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`ExportsOutputRefKestraALB44AB63AD497CB7E2`].OutputValue' --output text 2>/dev/null || \
              aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?contains(LoadBalancerName, 'Kestra')].LoadBalancerArn" --output text 2>/dev/null | head -1)
    if [ ! -z "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
        ALB_STATE=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --region "$REGION" --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null || echo "UNKNOWN")
        echo "   State: $ALB_STATE"
    fi
fi
echo ""

# 6️⃣ Task Stack
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6️⃣  KestraEcsTaskStack"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if check_stack "KestraEcsTaskStack"; then
    TASK_DEF_ARN=$(aws cloudformation describe-stacks --stack-name "KestraEcsTaskStack" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinitionArn`].OutputValue' --output text 2>/dev/null)
    echo "   Task Definition: $TASK_DEF_ARN"
    
    # Get latest revision
    TASK_FAMILY=$(echo "$TASK_DEF_ARN" | awk -F'/' '{print $NF}' | awk -F':' '{print $1}')
    LATEST_REV=$(aws ecs list-task-definitions --family-prefix "$TASK_FAMILY" --region "$REGION" --sort DESC --max-items 1 --query 'taskDefinitionArns[0]' --output text 2>/dev/null | awk -F':' '{print $NF}')
    echo "   Latest Revision: $LATEST_REV"
    
    # Check volumes
    echo "   Volumes:"
    aws ecs describe-task-definition --task-definition "$TASK_FAMILY:$LATEST_REV" --region "$REGION" --query 'taskDefinition.volumes[*].{Name:name,Type:efsVolumeConfiguration!=null ? "EFS" : "Docker",TransitEncryption:efsVolumeConfiguration.transitEncryption}' --output json 2>/dev/null | jq -r '.[] | "      - \(.Name): \(.Type // "N/A") (TransitEncryption: \(.TransitEncryption // "N/A"))"' 2>/dev/null || echo "      Unable to retrieve volumes"
fi
echo ""

# 7️⃣ Service Stack
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "7️⃣  KestraEcsServiceStack"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if check_stack "KestraEcsServiceStack"; then
    SERVICE_NAME=$(aws cloudformation describe-stacks --stack-name "KestraEcsServiceStack" --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`EcsServiceName`].OutputValue' --output text 2>/dev/null)
    echo "   Service: $SERVICE_NAME"
    
    if [ ! -z "$SERVICE_NAME" ] && [ "$SERVICE_NAME" != "None" ]; then
        SERVICE_STATUS=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --region "$REGION" --query 'services[0].{DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount,Status:status}' --output json 2>/dev/null)
        echo "$SERVICE_STATUS" | jq -r '"   Desired: \(.DesiredCount), Running: \(.RunningCount), Pending: \(.PendingCount), Status: \(.Status)"' 2>/dev/null || echo "   Unable to retrieve service status"
        
        # Check task definition
        TASK_DEF=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --region "$REGION" --query 'services[0].taskDefinition' --output text 2>/dev/null)
        TASK_REV=$(echo "$TASK_DEF" | awk -F':' '{print $NF}')
        echo "   Task Definition Revision: $TASK_REV"
    fi
fi
echo ""

# 8️⃣ Optional Stacks
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "8️⃣  Optional Stacks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# WAF Stack
if aws cloudformation describe-stacks --stack-name "KestraWafStack" --region "$REGION" &>/dev/null; then
    echo -e "${BLUE}KestraWafStack:${NC}"
    check_stack "KestraWafStack"
else
    echo -e "${YELLOW}KestraWafStack: Not deployed${NC}"
fi

# Backup Stack
if aws cloudformation describe-stacks --stack-name "KestraBackupStack" --region "$REGION" &>/dev/null; then
    echo -e "${BLUE}KestraBackupStack:${NC}"
    check_stack "KestraBackupStack"
else
    echo -e "${YELLOW}KestraBackupStack: Not deployed${NC}"
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

STACKS=("KestraVpcStack" "KestraEcsClusterStack" "KestraEfsStack" "KestraS3Stack" "KestraAlbStack" "KestraEcsTaskStack" "KestraEcsServiceStack")
DEPLOYED=0
FAILED=0

for STACK in "${STACKS[@]}"; do
    STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
    if [ "$STATUS" != "NOT_FOUND" ]; then
        if [[ "$STATUS" == *"COMPLETE"* ]] && [[ ! "$STATUS" == *"ROLLBACK"* ]]; then
            ((DEPLOYED++))
        else
            ((FAILED++))
        fi
    fi
done

echo "Deployed Stacks: $DEPLOYED/${#STACKS[@]}"
echo "Failed Stacks: $FAILED"

if [ $DEPLOYED -eq ${#STACKS[@]} ]; then
    echo -e "${GREEN}✅ All core stacks deployed successfully!${NC}"
elif [ $FAILED -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Some stacks not deployed yet${NC}"
else
    echo -e "${RED}❌ Some stacks have failed${NC}"
fi

echo ""
echo "To check individual stack details:"
echo "  aws cloudformation describe-stacks --stack-name <StackName> --region $REGION"
echo ""
echo "To check service tasks:"
echo "  ./scripts/check-cluster-resources.sh"

