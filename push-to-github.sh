#!/bin/bash
# Script to push Kestra infrastructure code to GitHub

set -e

REPO_URL="https://github.com/oana-cazan-allcloud/kestra-infrastructure.git"
REPO_DIR="/Users/oana.iacob/kestra-infrastructure"

cd "$REPO_DIR"

echo "🚀 Pushing Kestra infrastructure to GitHub"
echo "=========================================="
echo ""

# Check if git is initialized
if [ ! -d .git ]; then
    echo "📦 Initializing git repository..."
    git init
fi

# Set remote
if git remote get-url origin &>/dev/null; then
    echo "✅ Remote 'origin' already configured"
    git remote set-url origin "$REPO_URL"
else
    echo "➕ Adding remote 'origin'..."
    git remote add origin "$REPO_URL"
fi

# Configure git user if not set
if [ -z "$(git config user.name)" ]; then
    echo "⚠️  Git user.name not set. Please configure:"
    echo "   git config user.name 'Your Name'"
    echo "   git config user.email 'your.email@example.com'"
    exit 1
fi

# Add all files
echo "📝 Staging files..."
git add .

# Show what will be committed
echo ""
echo "Files to be committed:"
git status --short | head -20
echo ""

# Commit
echo "💾 Committing changes..."
git commit -m "Initial commit: Kestra infrastructure with CDK stacks

- VPC stack with DNS support
- ECS cluster with AutoScaling Group
- EFS file system for shared storage
- S3 bucket for Kestra storage
- ECS task definition with PostgreSQL, Git-Sync, Repo-Syncer, and Kestra Server
- Application Load Balancer (ALB) with target group
- ECS service with deployment configuration
- Optional WAF and Backup stacks
- Deployment scripts and documentation"

# Set main branch
echo "🌿 Setting main branch..."
git branch -M main

# Push to GitHub
echo ""
echo "🚀 Pushing to GitHub..."
echo "   Repository: $REPO_URL"
echo ""

git push -u origin main

echo ""
echo "✅ Successfully pushed to GitHub!"
echo "   View at: $REPO_URL"

