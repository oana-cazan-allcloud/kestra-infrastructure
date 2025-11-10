#!/bin/bash
# Verify and fix SSH keys in Secrets Manager for Kestra Git-Sync

set -euo pipefail

SECRET_NAME="kestra/git"
REGION="${AWS_REGION:-eu-central-1}"
PROFILE="${AWS_PROFILE:-data-sandbox}"

echo "=============================================="
echo "🔍 Verifying SSH Keys in Secrets Manager"
echo "=============================================="
echo "Secret: $SECRET_NAME"
echo "Region: $REGION"
echo ""

# Check if secret exists
if ! aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" --profile "$PROFILE" &>/dev/null; then
  echo "❌ Secret '$SECRET_NAME' does not exist!"
  echo ""
  echo "Create it with:"
  echo "  aws secretsmanager create-secret \\"
  echo "    --name $SECRET_NAME \\"
  echo "    --secret-string '{\"SSH_PRIVATE_KEY\":\"\",\"SSH_KNOWN_HOSTS\":\"\"}' \\"
  echo "    --region $REGION \\"
  echo "    --profile $PROFILE"
  exit 1
fi

echo "✅ Secret exists"
echo ""

# Get the secret value
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'SecretString' \
  --output text)

# Check if it's valid JSON
if ! echo "$SECRET_JSON" | jq . &>/dev/null; then
  echo "❌ Secret is not valid JSON!"
  exit 1
fi

echo "✅ Secret is valid JSON"
echo ""

# Extract keys
SSH_KEY=$(echo "$SECRET_JSON" | jq -r '.SSH_PRIVATE_KEY // empty')
KNOWN_HOSTS=$(echo "$SECRET_JSON" | jq -r '.SSH_KNOWN_HOSTS // empty')

# Check SSH_PRIVATE_KEY
if [ -z "$SSH_KEY" ]; then
  echo "❌ SSH_PRIVATE_KEY is missing!"
else
  echo "✅ SSH_PRIVATE_KEY exists"
  
  # Check if it starts with BEGIN
  if echo "$SSH_KEY" | head -1 | grep -q "BEGIN"; then
    echo "   ✅ Starts with BEGIN marker"
  else
    echo "   ❌ Does NOT start with BEGIN marker"
    echo "   ⚠️  The SSH key format may be incorrect"
  fi
  
  # Check if it ends with END
  if echo "$SSH_KEY" | tail -1 | grep -q "END"; then
    echo "   ✅ Ends with END marker"
  else
    echo "   ❌ Does NOT end with END marker"
    echo "   ⚠️  The SSH key format may be incorrect"
  fi
  
  # Count lines (should be > 1 for a valid key)
  LINE_COUNT=$(echo "$SSH_KEY" | wc -l)
  echo "   📊 Line count: $LINE_COUNT"
  
  if [ "$LINE_COUNT" -lt 2 ]; then
    echo "   ⚠️  WARNING: SSH key appears to be on a single line"
    echo "   ⚠️  This might cause 'error in libcrypto'"
    echo ""
    echo "   💡 Fix: The SSH key should have actual newlines, not \\n escape sequences"
    echo "   💡 When storing in Secrets Manager JSON, use actual newlines or ensure \\n is properly converted"
  fi
fi

echo ""

# Check SSH_KNOWN_HOSTS
if [ -z "$KNOWN_HOSTS" ]; then
  echo "❌ SSH_KNOWN_HOSTS is missing!"
else
  echo "✅ SSH_KNOWN_HOSTS exists"
  echo "   Value: $KNOWN_HOSTS"
fi

echo ""
echo "=============================================="
echo "📝 How to Fix SSH Key Format"
echo "=============================================="
echo ""
echo "If the SSH key format is wrong, update it with:"
echo ""
echo "1. Get your SSH private key:"
echo "   cat ~/.ssh/id_rsa"
echo ""
echo "2. Create a JSON file with proper formatting:"
echo "   cat > /tmp/ssh-fix.json << 'EOF'"
echo "{"
echo "  \"SSH_PRIVATE_KEY\": \"$(cat ~/.ssh/id_rsa | jq -Rs . | tr -d '"')\","
echo "  \"SSH_KNOWN_HOSTS\": \"github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLjU+pUnZQ==\""
echo "}"
echo "EOF"
echo ""
echo "3. Update the secret:"
echo "   aws secretsmanager put-secret-value \\"
echo "     --secret-id $SECRET_NAME \\"
echo "     --secret-string file:///tmp/ssh-fix.json \\"
echo "     --region $REGION \\"
echo "     --profile $PROFILE"
echo ""
echo "=============================================="

