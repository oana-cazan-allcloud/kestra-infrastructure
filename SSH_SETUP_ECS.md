# SSH Configuration for ECS Git-Sync

## ✅ Changes Made

The ECS task definition has been updated to use SSH for git-sync, matching the Docker Compose configuration.

### Key Changes:

1. **Repository URL**: Changed from HTTPS to SSH
   - Before: `https://github.com/oana-cazan-allcloud/cargo-partners.git`
   - After: `git@github.com:oana-cazan-allcloud/cargo-partners.git`

2. **Branch Reference**: Changed from `GITSYNC_BRANCH` to `GITSYNC_REF`
   - Matches Docker Compose configuration

3. **SSH Configuration**: Added SSH environment variables
   - `GITSYNC_SSH_KEY_FILE: /etc/git-secret/ssh`
   - `GITSYNC_SSH_KNOWN_HOSTS: true`
   - `GITSYNC_SSH_KNOWN_HOSTS_FILE: /etc/git-secret/known_hosts`
   - `GITSYNC_ADD_USER: true`

4. **SSH Init Container**: Added init container to set up SSH keys
   - Reads SSH keys from Secrets Manager
   - Writes them to `/etc/git-secret/` on EFS
   - Sets proper permissions (600 for private key, 644 for known_hosts)

## 📋 Required Secrets Manager Configuration

**Important**: You need to store SSH keys in **AWS Secrets Manager** (NOT SSM Parameter Store).

### Secret Name: `kestra/git`

The secret should contain these keys:

1. **`SSH_PRIVATE_KEY`**: Your SSH private key content
   ```bash
   # Get your SSH private key
   cat ~/.ssh/id_rsa
   ```

2. **`SSH_KNOWN_HOSTS`**: GitHub's SSH fingerprint (from `ssh-keyscan`)
   ```bash
   # Get GitHub's SSH fingerprint
   ssh-keyscan github.com
   ```

### Step-by-Step: Adding SSH Keys to Secrets Manager

#### Step 1: Get Your SSH Private Key

```bash
# Display your SSH private key (copy the entire output)
cat ~/.ssh/id_rsa

# It should look like:
# -----BEGIN OPENSSH PRIVATE KEY-----
# b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABlwAAAAdzc2gtcn
# ...
# -----END OPENSSH PRIVATE KEY-----
```

#### Step 2: Get GitHub's SSH Fingerprint

```bash
# Run this command to get GitHub's SSH host keys
ssh-keyscan github.com

# Output will look like:
# github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLjU+pUnZQ==
```

**Copy the entire line** (starts with `github.com ssh-rsa ...`)

#### Step 3: Update Secrets Manager Secret

**Option A: Using AWS CLI**

```bash
# Set your AWS profile
export AWS_PROFILE=data-sandbox
export AWS_DEFAULT_REGION=eu-central-1

# Update the secret with SSH keys
aws secretsmanager put-secret-value \
  --secret-id kestra/git \
  --secret-string '{
    "SSH_PRIVATE_KEY": "-----BEGIN OPENSSH PRIVATE KEY-----\nYOUR_PRIVATE_KEY_CONTENT_HERE\n-----END OPENSSH PRIVATE KEY-----",
    "SSH_KNOWN_HOSTS": "github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk="
  }' \
  --region eu-central-1
```

**Option B: Using AWS Console (Recommended for first-time setup)**

1. Go to **AWS Secrets Manager** in the AWS Console
2. Find the secret: `kestra/git`
3. Click **"Retrieve secret value"**
4. Click **"Edit"**
5. Make sure the secret format is **"Plaintext"** or **"Key/value"**
   
   If it's Key/value format, add/edit these keys:
   - **Key**: `SSH_PRIVATE_KEY`
     - **Value**: Paste your entire SSH private key (from `cat ~/.ssh/id_rsa`)
   
   - **Key**: `SSH_KNOWN_HOSTS`
     - **Value**: Paste the output from `ssh-keyscan github.com` (the entire line)

6. Click **"Save"**

**Option C: Create a JSON file and update**

```bash
# Create a JSON file with your SSH keys
cat > /tmp/ssh-keys.json << 'EOF'
{
  "SSH_PRIVATE_KEY": "-----BEGIN OPENSSH PRIVATE KEY-----\nPASTE_YOUR_PRIVATE_KEY_HERE\n-----END OPENSSH PRIVATE KEY-----",
  "SSH_KNOWN_HOSTS": "github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLjU+pUnZQ=="
}
EOF

# Update the secret
aws secretsmanager put-secret-value \
  --secret-id kestra/git \
  --secret-string file:///tmp/ssh-keys.json \
  --region eu-central-1 \
  --profile data-sandbox
```

### Important Notes:

- **Store in Secrets Manager**, NOT SSM Parameter Store
- The secret name must be exactly: `kestra/git`
- The keys must be named exactly: `SSH_PRIVATE_KEY` and `SSH_KNOWN_HOSTS`
- For `SSH_PRIVATE_KEY`: Include the entire key including `-----BEGIN` and `-----END` lines
- For `SSH_KNOWN_HOSTS`: Use the entire line from `ssh-keyscan github.com`

### Verify the Secret:

```bash
# Check if the secret has the correct keys
aws secretsmanager get-secret-value \
  --secret-id kestra/git \
  --region eu-central-1 \
  --profile data-sandbox \
  --query 'SecretString' \
  --output text | jq 'keys'

# Should show: ["SSH_PRIVATE_KEY", "SSH_KNOWN_HOSTS"]
```

## 🔧 How It Works

1. **SSH Init Container** (`SshInit`):
   - Runs first (non-essential)
   - Reads `SSH_PRIVATE_KEY` and `SSH_KNOWN_HOSTS` from Secrets Manager (`kestra/git`)
   - Writes them to `/etc/git-secret/ssh` and `/etc/git-secret/known_hosts` on EFS
   - Sets permissions: `600` for private key, `644` for known_hosts
   - Exits successfully

2. **Git-Sync Container**:
   - Waits for SSH init container to complete (`SUCCESS` condition)
   - Mounts `/etc/git-secret` from EFS (read-only)
   - Uses SSH key file for git operations
   - Clones repository using SSH URL

## ⚠️ Security Notes

- SSH keys are stored on EFS (encrypted at rest with transit encryption)
- SSH keys are read-only for git-sync container
- Secrets Manager encrypts secrets at rest
- Rotate SSH keys regularly

## 🚀 Next Steps

1. ✅ Get your SSH private key (`cat ~/.ssh/id_rsa`)
2. ✅ Get GitHub's SSH fingerprint (`ssh-keyscan github.com`)
3. ✅ Update the `kestra/git` secret in **Secrets Manager** (NOT SSM) with both keys
4. Deploy the updated task definition:
   ```bash
   cd kestra-cdk
   npx cdk deploy KestraEcsTaskStack
   ```
5. Verify git-sync is working:
   ```bash
   # Check git-sync logs
   aws logs tail /ecs/kestra --follow --filter-pattern "GitSync"
   ```

## 📝 Verification

After deployment, check that:
- SSH init container completes successfully
- Git-sync container starts after SSH init
- Git-sync successfully clones the repository
- No SSH authentication errors in logs

## ❓ FAQ

**Q: Should I use SSM Parameter Store or Secrets Manager?**  
A: **Secrets Manager** - The code is configured to read from Secrets Manager, not SSM.

**Q: What if my secret already exists with different keys?**  
A: You can add the new keys (`SSH_PRIVATE_KEY`, `SSH_KNOWN_HOSTS`) alongside existing keys. The init container will only read these two keys.

**Q: Can I use a different secret name?**  
A: No, the code references `kestra/git` specifically. You'd need to update the code to use a different name.

**Q: What format should the SSH_PRIVATE_KEY be in?**  
A: The entire private key file content, including `-----BEGIN OPENSSH PRIVATE KEY-----` and `-----END OPENSSH PRIVATE KEY-----` lines.
