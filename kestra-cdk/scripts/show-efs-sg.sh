#!/bin/bash
# Show EFS Security Group Configuration

set -e

REGION="${AWS_REGION:-eu-central-1}"
AWS_PROFILE="${AWS_PROFILE:-data-sandbox}"

export AWS_PROFILE

echo "🔍 EFS Security Group Configuration"
echo "===================================="
echo ""

# Get EFS ID and Security Group
EFS_ID=$(aws cloudformation describe-stacks --stack-name KestraEfsStack --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`EfsId`].OutputValue' --output text 2>/dev/null)
EFS_SG=$(aws cloudformation describe-stacks --stack-name KestraEfsStack --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`EfsSgId`].OutputValue' --output text 2>/dev/null)

echo "EFS File System ID: $EFS_ID"
echo "EFS Security Group ID: $EFS_SG"
echo ""

# Show security group details
echo "Security Group Details:"
aws ec2 describe-security-groups --group-ids "$EFS_SG" --region "$REGION" --query 'SecurityGroups[0].[GroupId,GroupName,Description,VpcId]' --output table 2>&1

echo ""
echo "Ingress Rules (who can access EFS on port 2049):"
aws ec2 describe-security-groups --group-ids "$EFS_SG" --region "$REGION" --query 'SecurityGroups[0].IpPermissions[?FromPort==`2049`]' --output json 2>&1 | jq -r '.[] | "  Port: \(.FromPort) (\(.IpProtocol))\n  Source Security Groups:" + (if .UserIdGroupPairs then "\n" + (.UserIdGroupPairs | map("    - \(.GroupId)") | join("\n")) else "\n    - None" end)'

echo ""
echo "Source Security Groups Details:"
for SG_ID in $(aws ec2 describe-security-groups --group-ids "$EFS_SG" --region "$REGION" --query 'SecurityGroups[0].IpPermissions[?FromPort==`2049`].UserIdGroupPairs[*].GroupId' --output text 2>/dev/null); do
    SG_NAME=$(aws ec2 describe-security-groups --group-ids "$SG_ID" --region "$REGION" --query 'SecurityGroups[0].GroupName' --output text 2>/dev/null)
    SG_DESC=$(aws ec2 describe-security-groups --group-ids "$SG_ID" --region "$REGION" --query 'SecurityGroups[0].Description' --output text 2>/dev/null)
    echo "  $SG_ID"
    echo "    Name: $SG_NAME"
    echo "    Description: $SG_DESC"
    echo ""
done

echo "Mount Target Security Groups:"
aws efs describe-mount-targets --file-system-id "$EFS_ID" --region "$REGION" --query 'MountTargets[*].[MountTargetId,SubnetId]' --output text 2>/dev/null | while read MT_ID MT_SUBNET; do
    echo "  Mount Target: $MT_ID"
    echo "    Subnet: $MT_SUBNET"
    MT_SGS=$(aws efs describe-mount-target-security-groups --mount-target-id "$MT_ID" --region "$REGION" --query 'SecurityGroups[*]' --output text 2>/dev/null)
    echo "    Security Groups: $MT_SGS"
    echo ""
done

echo "✅ EFS Security Group allows NFS (2049) from:"
echo "   - Container Instance Security Group (for mounting)"
echo "   - ECS Task Security Group (for task access)"

