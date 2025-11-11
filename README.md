# Kestra Infrastructure

AWS CDK infrastructure for deploying Kestra workflow orchestration platform on ECS with Git-based workflow synchronization.

## Architecture

This repository contains CDK stacks for deploying Kestra with the following components:

### Core Infrastructure

- **VPC Stack** (`KestraVpcStack`): Network infrastructure with DNS support for EFS
- **ECS Cluster Stack** (`KestraEcsClusterStack`): ECS cluster with AutoScaling Group for EC2 container instances
- **EFS Stack** (`KestraEfsStack`): Elastic File System for shared storage (Postgres data, Git repos, Kestra data)
- **S3 Stack** (`KestraS3Stack`): S3 bucket for Kestra internal storage
- **ECS Task Stack** (`KestraEcsTaskStack`): Task definition with all containers:
  - **PostgresInit**: Initializes Postgres data directory
  - **Postgres**: PostgreSQL 17 database
  - **SshInit**: Sets up SSH keys for Git access
  - **GitSync**: Synchronizes Git repository (using SSH)
  - **RepoSyncer**: Watches and syncs files to Kestra
  - **KestraServer**: Kestra workflow orchestration server
- **ALB Stack** (`KestraAlbStack`): Application Load Balancer with target group
- **ECS Service Stack** (`KestraEcsServiceStack`): ECS service configuration (defaults to `desiredCount: 0`)

### Optional Stacks

- **WAF Stack** (`KestraWafStack`): Web Application Firewall for ALB
- **Backup Stack** (`KestraBackupStack`): Automated backups for EFS

## Prerequisites

- **Node.js**: 18+ (tested with Node 20+)
- **npm**: Comes with Node.js
- **AWS CLI**: Configured with appropriate credentials
- **AWS CDK CLI**: `npm install -g aws-cdk`
- **TypeScript**: Installed via npm
- **jq**: For JSON processing in scripts (optional but recommended)

## Quick Start

### 1. Install Dependencies

```bash
cd kestra-cdk
npm install
```

### 2. Configure AWS Credentials

```bash
export AWS_PROFILE=data-sandbox
export AWS_REGION=eu-central-1
```

### 3. Bootstrap CDK (First Time Only)

```bash
cdk bootstrap
```

### 4. Set Up Secrets

Before deploying, create the required secrets in AWS Secrets Manager:

**Required Secrets:**

1. **`kestra/postgres`**:
   ```json
   {
     "POSTGRES_PASSWORD": "your-secure-password"
   }
   ```

2. **`kestra/git`**:
   ```json
   {
     "SSH_PRIVATE_KEY": "-----BEGIN OPENSSH PRIVATE KEY-----\n...\n-----END OPENSSH PRIVATE KEY-----",
     "SSH_KNOWN_HOSTS": "github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLjU+pUnZQ=="
   }
   ```

See [SSH_SETUP_ECS.md](./SSH_SETUP_ECS.md) for detailed SSH setup instructions.

### 5. Deploy Stacks

**Option A: Deploy All Stacks (Recommended)**

```bash
cd kestra-cdk
./scripts/deploy-all-stacks.sh
```

**Option B: Deploy Individually**

```bash
cd kestra-cdk
export JSII_SILENCE_WARNING_UNTESTED_NODE_VERSION=1

cdk deploy KestraVpcStack --app "npx ts-node --prefer-ts-exts bin/kestra-cdk.ts" --require-approval never
cdk deploy KestraEcsClusterStack --app "npx ts-node --prefer-ts-exts bin/kestra-cdk.ts" --require-approval never
cdk deploy KestraEfsStack --app "npx ts-node --prefer-ts-exts bin/kestra-cdk.ts" --require-approval never
cdk deploy KestraS3Stack --app "npx ts-node --prefer-ts-exts bin/kestra-cdk.ts" --require-approval never
cdk deploy KestraEcsTaskStack --app "npx ts-node --prefer-ts-exts bin/kestra-cdk.ts" --require-approval never
cdk deploy KestraAlbStack --app "npx ts-node --prefer-ts-exts bin/kestra-cdk.ts" --require-approval never
cdk deploy KestraEcsServiceStack --app "npx ts-node --prefer-ts-exts bin/kestra-cdk.ts" --require-approval never
```

### 6. Start the Service

The service starts with `desiredCount: 0` by default. To start tasks:

```bash
aws ecs update-service \
  --cluster kestra-cluster \
  --service <service-name> \
  --desired-count 1 \
  --region eu-central-1 \
  --profile data-sandbox
```

Or use the helper script:

```bash
cd kestra-cdk/scripts
./check-task-commands.sh  # Shows all available commands
```

## Deployment Order

Stacks must be deployed in dependency order:

1. `KestraVpcStack` - Network infrastructure
2. `KestraEcsClusterStack` - ECS cluster (depends on VPC)
3. `KestraEfsStack` - EFS file system (depends on Cluster)
4. `KestraS3Stack` - S3 bucket (depends on EFS)
5. `KestraEcsTaskStack` - Task definition (depends on EFS, Cluster)
6. `KestraAlbStack` - Load balancer (depends on VPC)
7. `KestraEcsServiceStack` - ECS service (depends on Task, ALB)

**Optional:**
- `KestraWafStack` - WAF (depends on ALB)
- `KestraBackupStack` - Backups (depends on EFS)

See [DEPLOYMENT_ORDER.md](./kestra-cdk/DEPLOYMENT_ORDER.md) for detailed information.

## Configuration

### AWS Profile and Region

Default configuration:
- **Profile**: `data-sandbox`
- **Region**: `eu-central-1`
- **Account**: `822550017122`

To change, edit `kestra-cdk/bin/kestra-cdk.ts`.

### Git Repository

The Git repository is configured in `kestra-cdk/lib/ecs-task-cdk-stack.ts`:
- **Repository**: `git@github.com:oana-cazan-allcloud/cargo-partners.git`
- **Branch**: `main`
- **Sync Period**: `10s`

### Service Configuration

- **Desired Count**: `0` (scale up manually after deployment)
- **Min Healthy Percent**: `0`
- **Max Healthy Percent**: `100`
- **Placement Strategy**: Spread across AZs, packed by CPU

## Scripts

Helper scripts are available in `kestra-cdk/scripts/`:

### Deployment Scripts
- `deploy-all-stacks.sh` - Deploy all stacks in correct order
- `destroy-kestra-stacks.sh` - Destroy all stacks (in reverse order)

### Monitoring Scripts
- `check-all-stacks.sh` - Check deployment status of all stacks
- `check-cluster-resources.sh` - Check ECS cluster resources
- `check-task-status.sh` - Check ECS task status and logs
- `check-task-commands.sh` - Show useful commands for task management
- `watch-cluster.sh` - Monitor cluster in real-time

### Setup Scripts
- `verify-secrets.sh` - Verify Secrets Manager secrets
- `verify-ssh-secret.sh` - Verify SSH secret format
- `create-ssh-json.sh` - Create SSH key JSON for Secrets Manager

### Troubleshooting Scripts
- `clear-postgres-data.sh` - Clear Postgres data directory on EFS

## Docker Compose (Local Development)

For local development and testing, see [docker/README.md](./docker/README.md).

Quick start:
```bash
cd docker
docker-compose up -d
```

Access Kestra UI at: http://localhost:8080

## Documentation

- [SSH_SETUP_ECS.md](./SSH_SETUP_ECS.md) - Detailed SSH setup for Git-Sync
- [COMPARISON_DOCKER_ECS.md](./COMPARISON_DOCKER_ECS.md) - Docker Compose vs ECS comparison
- [DEPLOYMENT_ORDER.md](./kestra-cdk/DEPLOYMENT_ORDER.md) - Stack deployment order and dependencies

## Troubleshooting

### Tasks Not Starting

1. Check service status:
   ```bash
   ./scripts/check-task-status.sh
   ```

2. Check service events:
   ```bash
   aws ecs describe-services --cluster kestra-cluster --services <service-name> --query 'services[0].events[:5]'
   ```

3. Verify secrets:
   ```bash
   ./scripts/verify-secrets.sh
   ```

### Postgres Failing

If Postgres fails with "directory exists but is not empty":
```bash
./scripts/clear-postgres-data.sh
```

### SSH Key Issues

1. Verify SSH secret format:
   ```bash
   ./scripts/verify-ssh-secret.sh
   ```

2. Recreate SSH JSON:
   ```bash
   ./scripts/create-ssh-json.sh ~/.ssh/id_rsa
   ```

3. Update secret:
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id kestra/git \
     --secret-string file:///tmp/ssh-fix.json \
     --region eu-central-1 \
     --profile data-sandbox
   ```

### View Logs

```bash
# Follow all logs
aws logs tail /ecs/kestra --follow --region eu-central-1 --profile data-sandbox

# Filter by container
aws logs tail /ecs/kestra --filter-pattern "GitSync" --region eu-central-1 --profile data-sandbox
```

## Architecture Details

### Containers

1. **PostgresInit**: Alpine-based init container that prepares the Postgres data directory
2. **Postgres**: PostgreSQL 17 database with persistent storage on EFS
3. **SshInit**: Alpine-based init container that writes SSH keys to EFS for Git-Sync
4. **GitSync**: Kubernetes Git-Sync container that clones/pulls Git repository via SSH
5. **RepoSyncer**: Alpine-based container using `inotify-tools` and `rsync` to sync files
6. **KestraServer**: Kestra workflow orchestration server

### Storage

- **EFS**: Shared file system for:
  - Postgres data (`/var/lib/postgresql/data`)
  - Git repository (`/git/repo`)
  - Synced repository (`/repo`)
  - SSH keys (`/etc/git-secret`)
  - Kestra data (`/kestra-data`)

- **S3**: Kestra internal storage (workflow execution data, logs, etc.)

### Networking

- **VPC**: Custom VPC with public and private subnets across 2 AZs
- **ALB**: Application Load Balancer in public subnets
- **ECS Tasks**: Run in private subnets with NAT Gateway for outbound internet access
- **EFS**: Mount targets in private subnets

## License

MIT


