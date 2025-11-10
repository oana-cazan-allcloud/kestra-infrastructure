# Push Kestra Infrastructure to GitHub

## Step-by-Step Instructions

### 1. Navigate to the project directory
```bash
cd /Users/oana.iacob/kestra-infrastructure
```

### 2. Initialize git (if not already done)
```bash
git init
```

### 3. Configure git user (if not already set)
```bash
git config user.name "Your Name"
git config user.email "your.email@example.com"
```

### 4. Add remote repository
```bash
git remote add origin https://github.com/oana-cazan-allcloud/kestra-infrastructure.git
```

If remote already exists, update it:
```bash
git remote set-url origin https://github.com/oana-cazan-allcloud/kestra-infrastructure.git
```

### 5. Stage all files
```bash
git add .
```

### 6. Commit changes
```bash
git commit -m "Initial commit: Kestra infrastructure with CDK stacks"
```

### 7. Set main branch and push
```bash
git branch -M main
git push -u origin main
```

## Troubleshooting "Permission Denied"

If you get "permission denied" when pushing, try one of these:

### Option A: Use Personal Access Token (PAT)
1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate a new token with `repo` scope
3. When prompted for password, use the token instead:
```bash
git push -u origin main
# Username: your-github-username
# Password: <paste-your-token-here>
```

### Option B: Use SSH instead of HTTPS
1. Set up SSH keys: https://docs.github.com/en/authentication/connecting-to-github-with-ssh
2. Change remote to SSH:
```bash
git remote set-url origin git@github.com:oana-cazan-allcloud/kestra-infrastructure.git
git push -u origin main
```

### Option C: Use GitHub CLI
```bash
# Install GitHub CLI if not installed
brew install gh

# Authenticate
gh auth login

# Then push
git push -u origin main
```

## Quick One-Liner (if you have credentials configured)
```bash
cd /Users/oana.iacob/kestra-infrastructure && \
git init && \
git remote add origin https://github.com/oana-cazan-allcloud/kestra-infrastructure.git 2>/dev/null || \
git remote set-url origin https://github.com/oana-cazan-allcloud/kestra-infrastructure.git && \
git add . && \
git commit -m "Initial commit: Kestra infrastructure with CDK stacks" && \
git branch -M main && \
git push -u origin main
```

