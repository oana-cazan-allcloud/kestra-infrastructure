#!/bin/bash
# Clear Postgres data directory on EFS using ECS Exec

set -euo pipefail

CLUSTER="kestra-cluster"
REGION="${AWS_REGION:-eu-central-1}"
PROFILE="${AWS_PROFILE:-data-sandbox}"

export AWS_PROFILE="$PROFILE"
export AWS_REGION="$REGION"

echo "=============================================="
echo "🧹 Clearing Postgres Data Directory on EFS"
echo "=============================================="
echo ""

# Get a running task
TASK_ARN=$(aws ecs list-tasks --cluster "$CLUSTER" --region "$REGION" --query 'taskArns[0]' --output text)

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
  echo "❌ No running tasks found. Please start a task first."
  echo ""
  echo "Start a task with:"
  echo "  aws ecs update-service --cluster $CLUSTER --service <service-name> --desired-count 1 --region $REGION --profile $PROFILE"
  exit 1
fi

echo "✅ Found task: $TASK_ARN"
echo ""
echo "To clear Postgres data directory, run:"
echo ""
echo "aws ecs execute-command \\"
echo "  --cluster $CLUSTER \\"
echo "  --task $TASK_ARN \\"
echo "  --container PostgresInit \\"
echo "  --command '/bin/sh -c \"rm -rf /var/lib/postgresql/data/* /var/lib/postgresql/data/.[!.]* && echo Data cleared\"' \\"
echo "  --interactive \\"
echo "  --region $REGION \\"
echo "  --profile $PROFILE"
echo ""
echo "Or use ECS Exec to connect interactively:"
echo ""
echo "aws ecs execute-command \\"
echo "  --cluster $CLUSTER \\"
echo "  --task $TASK_ARN \\"
echo "  --container PostgresInit \\"
echo "  --interactive \\"
echo "  --region $REGION \\"
echo "  --profile $PROFILE"
echo ""

