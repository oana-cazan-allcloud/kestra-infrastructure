#!/bin/bash
# Create SSH key JSON file for Secrets Manager

set -euo pipefail

SSH_KEY_FILE="${1:-$HOME/.ssh/id_rsa}"
OUTPUT_FILE="/tmp/ssh-fix.json"

if [ ! -f "$SSH_KEY_FILE" ]; then
  echo "❌ SSH key file not found: $SSH_KEY_FILE"
  echo ""
  echo "Usage: $0 [path-to-ssh-private-key]"
  echo "Example: $0 ~/.ssh/id_rsa"
  exit 1
fi

echo "📝 Creating SSH key JSON file..."
echo "   SSH Key: $SSH_KEY_FILE"
echo "   Output: $OUTPUT_FILE"
echo ""

# Read SSH key and escape it properly for JSON
SSH_KEY=$(cat "$SSH_KEY_FILE" | jq -Rs .)

# GitHub SSH fingerprint (from github_ssh_fingerprint.txt)
KNOWN_HOSTS="github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLjU+pUnZQ=="

# Create JSON file
cat > "$OUTPUT_FILE" << EOF
{
  "SSH_PRIVATE_KEY": $SSH_KEY,
  "SSH_KNOWN_HOSTS": "$KNOWN_HOSTS"
}
EOF

echo "✅ Created $OUTPUT_FILE"
echo ""
echo "📋 File contents preview:"
echo "   SSH_PRIVATE_KEY: $(echo "$SSH_KEY" | head -c 50)..."
echo "   SSH_KNOWN_HOSTS: $KNOWN_HOSTS"
echo ""
echo "🔍 Verifying JSON format..."
if jq . "$OUTPUT_FILE" > /dev/null 2>&1; then
  echo "✅ JSON is valid"
else
  echo "❌ JSON is invalid!"
  exit 1
fi

echo ""
echo "🚀 Next step: Update the secret with:"
echo ""
echo "   aws secretsmanager put-secret-value \\"
echo "     --secret-id kestra/git \\"
echo "     --secret-string file://$OUTPUT_FILE \\"
echo "     --region eu-central-1 \\"
echo "     --profile data-sandbox"
echo ""

