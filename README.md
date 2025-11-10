# Kestra Infrastructure

AWS CDK infrastructure for deploying Kestra workflow orchestration platform on ECS.

## Architecture

This repository contains CDK stacks for deploying Kestra with the following components:

- **VPC Stack**: Network infrastructure with DNS support
- **ECS Cluster Stack**: ECS cluster with AutoScaling Group for container instances
- **EFS Stack**: Elastic File System for shared storage
- **S3 Stack**: S3 bucket for Kestra storage
- **ECS Task Stack**: Task definition with PostgreSQL, Git-Sync, Repo-Syncer, and Kestra Server
- **ALB Stack**: Application Load Balancer with target group
- **ECS Service Stack**: ECS service configuration
- **WAF Stack** (Optional): Web Application Firewall
- **Backup Stack** (Optional): Automated backups for EFS

## Prerequisites

- Node.js 18+ and npm
- AWS CLI configured with appropriate credentials
- AWS CDK CLI: `npm install -g aws-cdk`
- TypeScript

## Deployment Order

1. `KestraVpcStack` - Network infrastructure
2. `KestraEcsClusterStack` - ECS cluster and container instances
3. `KestraEfsStack` - EFS file system
4. `KestraS3Stack` - S3 bucket
5. `KestraEcsTaskStack` - Task definition (blueprint)
6. `KestraAlbStack` - Load balancer and target group
7. `KestraEcsServiceStack` - ECS service (connects tasks to ALB)

Optional stacks:
- `KestraWafStack` - Web Application Firewall
- `KestraBackupStack` - EFS backups

## Quick Start

```bash
# Install dependencies
cd kestra-cdk
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy all stacks
cdk deploy --all

# Or deploy individually
cdk deploy KestraVpcStack
cdk deploy KestraEcsClusterStack
cdk deploy KestraEfsStack
cdk deploy KestraS3Stack
cdk deploy KestraEcsTaskStack
cdk deploy KestraAlbStack
cdk deploy KestraEcsServiceStack
```

## Configuration

### AWS Profile

Set your AWS profile:
```bash
export AWS_PROFILE=data-sandbox
export AWS_DEFAULT_REGION=eu-central-1
```

### Secrets

Required AWS Secrets Manager secrets:
- `kestra/git` - Git credentials (GIT_SYNC_USERNAME, GIT_SYNC_PASSWORD)
- `kestra/postgres` - PostgreSQL password (POSTGRES_PASSWORD)

### Service Configuration

The service is configured with `desiredCount: 0` by default. To start tasks:

```bash
aws ecs update-service \
  --cluster kestra-cluster \
  --service <service-name> \
  --desired-count 1
```

## Scripts

Helper scripts are available in `kestra-cdk/scripts/`:

- `check-all-stacks.sh` - Check deployment status of all stacks
- `check-cluster-resources.sh` - Check ECS cluster resources
- `watch-cluster.sh` - Monitor cluster in real-time

## Docker Compose

For local development, see `docker/docker-compose.yml`.

## License

MIT

