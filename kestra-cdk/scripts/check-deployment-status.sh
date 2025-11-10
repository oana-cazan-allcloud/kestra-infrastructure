#!/bin/bash
# Script to check deployment status and guide next steps

set -e

REGION="eu-central-1"
CLUSTER_NAME="kestra-cluster"

echo "🔍 Checking Kestra Infrastructure Deployment Status..."
echo ""

# Check if cluster exists
echo "1️⃣ Checking ECS Cluster..."
CLUSTER_EXISTS=$(aws ecs describe-clusters \
  --clusters "$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'clusters[0].clusterName' \
  --output text 2>/dev/null || echo "")

if [ ! -z "$CLUSTER_EXISTS" ] && [ "$CLUSTER_EXISTS" != "None" ]; then
  echo "  ✅ Cluster exists: $CLUSTER_NAME"
else
  echo "  ❌ Cluster not found!"
  echo "     Deploy: npx cdk deploy KestraEcsClusterStack"
  exit 1
fi

echo ""

# Check for services
echo "2️⃣ Checking ECS Services..."
SERVICES=$(aws ecs list-services \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'serviceArns' \
  --output text 2>/dev/null || echo "")

if [ -z "$SERVICES" ] || [ "$SERVICES" == "None" ]; then
  echo "  ❌ No services found!"
  echo ""
  echo "  📋 What needs to be deployed:"
  echo "     ✅ Cluster: Exists"
  echo "     ❌ Service: NOT DEPLOYED"
  echo ""
  echo "  🚀 Next Steps:"
  echo "     1. Ensure task stack is deployed:"
  echo "        npx cdk deploy KestraEcsTaskStack"
  echo ""
  echo "     2. Ensure ALB stack is deployed:"
  echo "        npx cdk deploy KestraAlbStack"
  echo ""
  echo "     3. Deploy the service stack:"
  echo "        npx cdk deploy KestraEcsServiceStack"
  echo ""
  exit 1
else
  echo "  ✅ Found $(echo $SERVICES | wc -w | tr -d ' ') service(s)"
  for service in $SERVICES; do
    SERVICE_NAME=$(echo $service | cut -d'/' -f3)
    echo "     - $SERVICE_NAME"
  done
fi

echo ""

# Check for task definitions
echo "3️⃣ Checking Task Definitions..."
TASK_DEFS=$(aws ecs list-task-definitions \
  --family-prefix "KestraEcsTaskStack-KestraTaskDef" \
  --region "$REGION" \
  --query 'taskDefinitionArns' \
  --output text 2>/dev/null || echo "")

if [ -z "$TASK_DEFS" ] || [ "$TASK_DEFS" == "None" ]; then
  echo "  ❌ No task definitions found!"
  echo "     Deploy: npx cdk deploy KestraEcsTaskStack"
else
  echo "  ✅ Found $(echo $TASK_DEFS | wc -w | tr -d ' ') task definition(s)"
fi

echo ""

# Check for ALB
echo "4️⃣ Checking Application Load Balancer..."
ALBS=$(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --query 'LoadBalancers[?contains(LoadBalancerName, `Kestra`) || contains(LoadBalancerName, `kestra`)].LoadBalancerName' \
  --output text 2>/dev/null || echo "")

if [ -z "$ALBS" ] || [ "$ALBS" == "None" ]; then
  echo "  ❌ No ALB found!"
  echo "     Deploy: npx cdk deploy KestraAlbStack"
else
  echo "  ✅ Found ALB(s):"
  for alb in $ALBS; do
    echo "     - $alb"
  done
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Deployment Checklist:"
echo ""
echo "  [$( [ ! -z "$CLUSTER_EXISTS" ] && [ "$CLUSTER_EXISTS" != "None" ] && echo "✅" || echo "❌" )] Cluster: KestraEcsClusterStack"
echo "  [$( [ ! -z "$TASK_DEFS" ] && [ "$TASK_DEFS" != "None" ] && echo "✅" || echo "❌" )] Task Definition: KestraEcsTaskStack"
echo "  [$( [ ! -z "$ALBS" ] && [ "$ALBS" != "None" ] && echo "✅" || echo "❌" )] ALB: KestraAlbStack"
echo "  [$( [ ! -z "$SERVICES" ] && [ "$SERVICES" != "None" ] && echo "✅" || echo "❌" )] Service: KestraEcsServiceStack"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -z "$SERVICES" ] || [ "$SERVICES" == "None" ]; then
  echo "🚀 To deploy the service, run:"
  echo ""
  echo "   npx cdk deploy KestraEcsServiceStack --require-approval never"
  echo ""
  echo "⚠️  Make sure these are deployed first:"
  echo "   - KestraEcsTaskStack (creates task definition)"
  echo "   - KestraAlbStack (creates ALB and target group)"
fi

echo "✅ Status check complete!"

