#!/bin/bash
# Test DNS resolution and EFS utilities on container instance

set -e

REGION="${AWS_REGION:-eu-central-1}"
AWS_PROFILE="${AWS_PROFILE:-data-sandbox}"
CLUSTER_NAME="${CLUSTER_NAME:-kestra-cluster}"

export AWS_PROFILE

echo "🔍 Testing Container Instance DNS and EFS Utilities"
echo "===================================================="
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

# Get EFS ID
EFS_ID=$(aws cloudformation describe-stacks --stack-name KestraEfsStack --region "$REGION" --query 'Stacks[0].Outputs[?OutputKey==`EfsId`].OutputValue' --output text 2>/dev/null)
EFS_DNS="${EFS_ID}.efs.${REGION}.amazonaws.com"

echo "2️⃣  EFS Information:"
echo "   EFS ID: $EFS_ID"
echo "   EFS DNS: $EFS_DNS"
echo ""

# Get mount target IPs
echo "3️⃣  Mount Target IPs:"
MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" --region "$REGION" --query 'MountTargets[*].[MountTargetId,IpAddress,SubnetId]' --output text 2>/dev/null)
echo "$MOUNT_TARGETS" | while read MT_ID MT_IP MT_SUBNET; do
    echo "   Mount Target: $MT_ID"
    echo "   IP Address: $MT_IP"
    echo "   Subnet: $MT_SUBNET"
    echo ""
done

echo "4️⃣  Testing DNS Resolution and EFS Utilities via SSM..."
echo "======================================================"
echo ""
echo "Connecting to instance via SSM Session Manager..."
echo ""

# Create a test script to run on the instance
TEST_SCRIPT="echo '=== Container Instance Diagnostics ==='; echo ''; echo '1. System Information:'; echo '   Hostname:' \$(hostname); echo '   OS:' \$(cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2); echo '   Kernel:' \$(uname -r); echo ''; echo '2. DNS Configuration:'; echo '   /etc/resolv.conf:'; cat /etc/resolv.conf | sed 's/^/     /'; echo ''; echo '3. DNS Resolution Test:'; EFS_DNS='${EFS_DNS}'; echo \"   Testing DNS resolution for: \$EFS_DNS\"; if nslookup \"\$EFS_DNS\" > /dev/null 2>&1; then echo '   ✅ DNS resolution successful'; nslookup \"\$EFS_DNS\" | grep -A 2 'Name:' | sed 's/^/     /'; else echo '   ❌ DNS resolution FAILED'; echo '   Trying with dig...'; if command -v dig > /dev/null 2>&1; then dig \"\$EFS_DNS\" +short | sed 's/^/     /' || echo '     dig also failed'; fi; fi; echo ''; echo '4. EFS Utilities Check:'; if command -v mount.efs > /dev/null 2>&1; then echo \"   ✅ mount.efs found: \$(which mount.efs)\"; mount.efs --version 2>&1 | head -1 | sed 's/^/     /' || echo '     (version check failed)'; else echo '   ❌ mount.efs NOT FOUND'; echo '   Checking for amazon-efs-utils package...'; if rpm -q amazon-efs-utils > /dev/null 2>&1 || dpkg -l | grep -q amazon-efs-utils; then echo '   ⚠️  Package installed but mount.efs not in PATH'; else echo '   ❌ amazon-efs-utils package NOT installed'; fi; fi; echo ''; echo '5. NFS Utilities Check:'; if command -v mount.nfs4 > /dev/null 2>&1; then echo \"   ✅ mount.nfs4 found: \$(which mount.nfs4)\"; else echo '   ❌ mount.nfs4 NOT FOUND'; fi; echo ''; echo '6. Network Connectivity Test:'; MT_IP='${MT_IP}'; if [ ! -z \"\$MT_IP\" ]; then echo \"   Testing connectivity to mount target: \$MT_IP\"; if timeout 3 bash -c \"echo > /dev/tcp/\$MT_IP/2049\" 2>/dev/null; then echo '   ✅ Port 2049 is reachable'; else echo '   ❌ Port 2049 is NOT reachable'; fi; fi; echo ''; echo '7. ECS Agent Status:'; if systemctl is-active --quiet ecs; then echo '   ✅ ECS agent is running'; systemctl status ecs --no-pager -l | grep -E '(Active|Main PID)' | sed 's/^/     /' || true; else echo '   ⚠️  ECS agent status unknown'; fi; echo ''; echo '=== End Diagnostics ==='"

# Get mount target IP for testing
MT_IP=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" --region "$REGION" --query 'MountTargets[0].IpAddress' --output text 2>/dev/null)

# Run the test script on the instance
echo "Running diagnostics on instance..."
echo ""

# Replace variables in the script
TEST_SCRIPT_FINAL=$(echo "$TEST_SCRIPT" | sed "s|\${EFS_DNS}|$EFS_DNS|g" | sed "s|\${MT_IP}|$MT_IP|g")

aws ssm send-command \
    --instance-id "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[$TEST_SCRIPT_FINAL]" \
    --region "$REGION" \
    --output text \
    --query 'Command.CommandId' > /tmp/ssm-command-id.txt 2>&1 || {
    echo "❌ Failed to send SSM command"
    echo "Make sure SSM Session Manager is enabled and instance has SSM agent running"
    exit 1
}

COMMAND_ID=$(cat /tmp/ssm-command-id.txt)
echo "Command ID: $COMMAND_ID"
echo ""
echo "Waiting for command to complete (this may take 30-60 seconds)..."
echo ""

# Wait for command to complete
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
echo "================"
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
echo "✅ Diagnostics complete!"

