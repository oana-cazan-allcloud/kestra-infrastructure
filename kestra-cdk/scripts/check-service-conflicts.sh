#!/bin/bash
# Check if there's an existing service that might conflict

set -e

REGION="eu-central-1"
CLUSTER_NAME="kestra-cluster"

echo "🔍 Checking for Existing Services That Might Conflict..."
echo ""

# List all services in the cluster
echo "Services in cluster '$CLUSTER_NAME':"
SERVICES=$(aws ecs list-services \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'serviceArns' \
  --output text 2>/dev/null || echo "")

if [ -z "$SERVICES" ] || [ "$SERVICES" == "None" ]; then
  echo "  ✅ No existing services found"
  echo "     Safe to deploy KestraEcsServiceStack"
  exit 0
fi

echo "  Found $(echo $SERVICES | wc -w | tr -d ' ') service(s):"
echo ""

for service_arn in $SERVICES; do
  SERVICE_NAME=$(echo $service_arn | cut -d'/' -f3)
  echo "  📋 Service: $SERVICE_NAME"
  
  # Get service details
  SERVICE_INFO=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$REGION" \
    --query 'services[0].[status,desiredCount,runningCount,deployments[0].taskDefinition]' \
    --output text 2>/dev/null || echo "")
  
  if [ ! -z "$SERVICE_INFO" ]; then
    STATUS=$(echo "$SERVICE_INFO" | awk '{print $1}')
    DESIRED=$(echo "$SERVICE_INFO" | awk '{print $2}')
    RUNNING=$(echo "$SERVICE_INFO" | awk '{print $3}')
    TASK_DEF=$(echo "$SERVICE_INFO" | awk '{print $4}')
    
    echo "     Status: $STATUS"
    echo "     Desired: $DESIRED | Running: $RUNNING"
    echo "     Task Definition: $(echo $TASK_DEF | cut -d'/' -f2)"
    echo ""
    
    # Check if this might be from the old ALB stack
    if [[ "$SERVICE_NAME" == *"KestraService"* ]] || [[ "$SERVICE_NAME" == *"Kestra"* ]]; then
      echo "     ⚠️  This might be a conflicting service!"
      echo ""
      echo "     💡 Options:"
      echo "        1. Delete this service first:"
      echo "           aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --desired-count 0 --region $REGION"
      echo "           aws ecs delete-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --region $REGION"
      echo ""
      echo "        2. Or update the service name in CDK to avoid conflict"
      echo ""
    fi
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 If deploying causes deletion:"
echo "   1. There might be a service name conflict"
echo "   2. CloudFormation might be replacing the service"
echo "   3. Check CloudFormation events for details"
echo ""
echo "   To prevent deletion, deletion protection has been added to the service."

