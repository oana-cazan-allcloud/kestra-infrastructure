#!/bin/bash
# Watch cluster resources in real-time

set -e

REGION="${AWS_REGION:-eu-central-1}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
AWS_PROFILE="${AWS_PROFILE:-data-sandbox}"
INTERVAL="${INTERVAL:-10}"

export AWS_PROFILE

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "🔍 Watching Kestra Cluster Resources"
echo "======================================"
echo "Region: $REGION"
echo "Profile: $AWS_PROFILE"
echo "Update interval: ${INTERVAL}s"
echo "Press Ctrl+C to stop"
echo ""

# Auto-detect cluster if not provided
if [ -z "$CLUSTER_NAME" ]; then
    CLUSTER_NAME=$(aws ecs list-clusters --region "$REGION" --query 'clusterArns[]' --output text 2>/dev/null | tr '\t' '\n' | grep -i kestra | awk -F'/' '{print $NF}' | head -1)
    if [ -z "$CLUSTER_NAME" ]; then
        CLUSTER_NAME=$(aws ecs list-clusters --region "$REGION" --query 'clusterArns[0]' --output text 2>/dev/null | awk -F'/' '{print $NF}')
    fi
fi

if [ -z "$CLUSTER_NAME" ]; then
    echo "❌ Could not detect cluster name"
    exit 1
fi

echo "Cluster: $CLUSTER_NAME"
echo ""

# Clear screen function
clear_screen() {
    printf "\033[2J\033[H"
}

# Main loop
while true; do
    clear_screen
    echo "🔍 Watching Kestra Cluster Resources - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "======================================"
    echo ""
    
    # Run the check script and capture output
    "$SCRIPT_DIR/check-cluster-resources.sh" 2>&1 | tail -50
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Next update in ${INTERVAL}s... (Ctrl+C to stop)"
    
    sleep "$INTERVAL"
done

