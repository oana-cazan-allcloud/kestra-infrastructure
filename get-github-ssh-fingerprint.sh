#!/bin/bash
# Save GitHub SSH fingerprint to file

OUTPUT_FILE="${1:-github_ssh_fingerprint.txt}"

echo "🔍 Getting GitHub SSH fingerprint..."
ssh-keyscan github.com > "$OUTPUT_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Saved to: $OUTPUT_FILE"
    echo ""
    echo "📄 Contents:"
    cat "$OUTPUT_FILE"
    echo ""
    echo "💡 Use this value for SSH_KNOWN_HOSTS in Secrets Manager"
else
    echo "❌ Error getting SSH fingerprint"
    exit 1
fi

