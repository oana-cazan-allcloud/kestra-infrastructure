#!/bin/bash
# Create EFS subdirectories manually via SSM Session Manager

set -e

REGION="${AWS_REGION:-eu-central-1}"
AWS_PROFILE="${AWS_PROFILE:-data-sandbox}"
CLUSTER_NAME="${CLUSTER_NAME:-kestra-cluster}"

export AWS_PROFILE

echo "📁 Creating EFS Subdirectories"
echo "=============================="
echo ""

# Find container instance
echo "1️⃣  Finding container instance..."
INSTANCE_ARN=$(aws ecs list-container-instances --cluster "$CLUSTER_NAME" --region "$REGION" --query 'containerInstanceArns[0]' --output text 2>/dev/null)

if [ -z "$INSTANCE_ARN" ] || [ "$INSTANCE_ARN" == "None" ]; then
    echo "❌ No container instances found"
    exit 1
fi

INSTANCE_ID=$(aws ecs describe-container-instances \
    --cluster "$CLUSTER_NAME" \
    --container-instances "$INSTANCE_ARN" \
    --region "$REGION" \
    --query 'containerInstances[0].ec2InstanceId' \
    --output text 2>/dev/null)

echo "   Instance ID: $INSTANCE_ID"
echo ""

# Get EFS ID and mount target IP
EFS_ID=$(aws cloudformation describe-stacks --stack-name KestraEfsStack --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`EfsId`].OutputValue' --output text 2>/dev/null)
EFS_DNS="${EFS_ID}.efs.${REGION}.amazonaws.com"
MT_IP=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" --region "$REGION" --query 'MountTargets[0].IpAddress' --output text 2>/dev/null)

echo "2️⃣  EFS Information:"
echo "   EFS ID: $EFS_ID"
echo "   EFS DNS: $EFS_DNS"
echo "   Mount Target IP: $MT_IP"
echo ""

# Create script to mount EFS and create directories
CREATE_SCRIPT="
echo '=== Creating EFS Subdirectories ==='
echo ''

# Install EFS utilities if not present
if ! command -v mount.efs > /dev/null 2>&1; then
    echo 'Installing amazon-efs-utils...'
    yum install -y amazon-efs-utils 2>&1 || echo 'Package install failed, trying alternative...'
fi

# Create mount point
MOUNT_POINT=\"/tmp/efs-mount-\$\$\"
mkdir -p \"\$MOUNT_POINT\"
echo \"Mount point: \$MOUNT_POINT\"

# Try mounting EFS
echo 'Mounting EFS...'
if mount -t efs -o tls,iam \"$EFS_ID\":/ \"\$MOUNT_POINT\" 2>&1; then
    echo '✅ EFS mounted successfully'
    
    # Create directories
    echo ''
    echo 'Creating subdirectories...'
    mkdir -p \"\$MOUNT_POINT/postgres-data\"
    mkdir -p \"\$MOUNT_POINT/kestra-data\"
    
    # Set permissions
    chmod 755 \"\$MOUNT_POINT/postgres-data\"
    chmod 755 \"\$MOUNT_POINT/kestra-data\"
    
    echo ''
    echo '✅ Directories created:'
    ls -la \"\$MOUNT_POINT\" | grep -E '(postgres-data|kestra-data)' || ls -la \"\$MOUNT_POINT\"
    
    # Unmount
    echo ''
    echo 'Unmounting EFS...'
    umount \"\$MOUNT_POINT\" 2>&1 || true
    rmdir \"\$MOUNT_POINT\" 2>&1 || true
    
    echo ''
    echo '✅ Success! Directories created on EFS'
else
    echo '❌ Failed to mount EFS'
    echo 'Trying alternative mount method...'
    
    # Try with mount target IP
    if mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \"$MT_IP\":/ \"\$MOUNT_POINT\" 2>&1; then
        echo '✅ EFS mounted via IP'
        mkdir -p \"\$MOUNT_POINT/postgres-data\"
        mkdir -p \"\$MOUNT_POINT/kestra-data\"
        chmod 755 \"\$MOUNT_POINT/postgres-data\"
        chmod 755 \"\$MOUNT_POINT/kestra-data\"
        ls -la \"\$MOUNT_POINT\" | grep -E '(postgres-data|kestra-data)' || ls -la \"\$MOUNT_POINT\"
        umount \"\$MOUNT_POINT\" 2>&1 || true
        rmdir \"\$MOUNT_POINT\" 2>&1 || true
        echo '✅ Success!'
    else
        echo '❌ Both mount methods failed'
        exit 1
    fi
fi
"

echo "3️⃣  Running script on container instance via SSM..."
COMMAND_ID=$(aws ssm send-command \
    --instance-id "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[$CREATE_SCRIPT]" \
    --region "$REGION" \
    --output text \
    --query 'Command.CommandId' 2>&1)

echo "   Command ID: $COMMAND_ID"
echo ""
echo "Waiting for command to complete (30-60 seconds)..."
echo ""

# Wait for command
for i in {1..20}; do
    STATUS=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'Status' \
        --output text 2>/dev/null || echo "Unknown")
    
    if [ "$STATUS" == "Success" ] || [ "$STATUS" == "Failed" ] || [ "$STATUS" == "Cancelled" ] || [ "$STATUS" == "TimedOut" ]; then
        break
    fi
    echo "   [$i/20] Status: $STATUS... waiting"
    sleep 3
done

echo ""
echo "Command Output:"
echo "==============="
aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'StandardOutputContent' \
    --output text 2>&1

echo ""
echo "Error Output (if any):"
echo "======================"
ERROR_OUTPUT=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'StandardErrorContent' \
    --output text 2>&1)

if [ ! -z "$ERROR_OUTPUT" ] && [ "$ERROR_OUTPUT" != "None" ]; then
    echo "$ERROR_OUTPUT"
else
    echo "(none)"
fi

echo ""
FINAL_STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Status' \
    --output text 2>&1)

if [ "$FINAL_STATUS" == "Success" ]; then
    echo "✅ Directories created successfully!"
    echo ""
    echo "Now you can deploy the service stack:"
    echo "  npx cdk deploy KestraEcsServiceStack --require-approval never"
else
    echo "⚠️  Command status: $FINAL_STATUS"
    echo "Check the output above for details"
fi

