# Kestra CDK Infrastructure

AWS CDK (Cloud Development Kit) project for deploying Kestra workflow orchestration platform on AWS ECS.

## Project Structure

```
kestra-cdk/
├── bin/
│   └── kestra-cdk.ts          # CDK app entry point
├── lib/
│   ├── vpc-cdk-stack.ts       # VPC and networking
│   ├── ecs-cluster-cdk-stack.ts # ECS cluster and capacity
│   ├── efs-cdk-stack.ts       # EFS file system
│   ├── s3-cdk-stack.ts        # S3 bucket
│   ├── ecs-task-cdk-stack.ts  # Task definition with containers
│   ├── ecs-service-alb-stack.ts # Application Load Balancer
│   ├── ecs-service-cdk-stack.ts # ECS service
│   ├── waf-cdk-stack.ts       # Web Application Firewall
│   └── backup-cdk-stack.ts    # EFS backups
├── lambda/                    # Lambda functions (optional)
├── scripts/                   # Helper scripts
├── test/                      # Unit tests
└── cdk.json                   # CDK configuration
```

## Prerequisites

- Node.js 18+ (tested with Node 20+)
- npm
- AWS CLI configured
- AWS CDK CLI: `npm install -g aws-cdk`

## Setup

```bash
# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap
```

## Useful Commands

### CDK Commands

```bash
# Compile TypeScript
npm run build

# Watch for changes and compile
npm run watch

# Run unit tests
npm run test

# Synthesize CloudFormation template
npx cdk synth

# Compare deployed stack with current state
npx cdk diff

# Deploy a specific stack
npx cdk deploy <StackName> --app "npx ts-node --prefer-ts-exts bin/kestra-cdk.ts"

# Deploy all stacks
./scripts/deploy-all-stacks.sh

# Destroy all stacks
./scripts/destroy-kestra-stacks.sh
```

### Deployment

**Deploy with profile and region:**
```bash
export AWS_PROFILE=data-sandbox
export AWS_REGION=eu-central-1
export JSII_SILENCE_WARNING_UNTESTED_NODE_VERSION=1

cdk deploy KestraVpcStack --app "npx ts-node --prefer-ts-exts bin/kestra-cdk.ts" --require-approval never
```

**Or use the deployment script:**
```bash
./scripts/deploy-all-stacks.sh
```

### Monitoring

```bash
# Check all stacks
./scripts/check-all-stacks.sh

# Check cluster resources
./scripts/check-cluster-resources.sh

# Check task status
./scripts/check-task-status.sh

# Watch cluster
./scripts/watch-cluster.sh
```

## Configuration

### Environment

Default AWS environment is configured in `bin/kestra-cdk.ts`:
- **Account**: `822550017122`
- **Region**: `eu-central-1`

### Secrets

Required AWS Secrets Manager secrets:
- `kestra/postgres` - PostgreSQL password
- `kestra/git` - SSH keys for Git access

See [../SSH_SETUP_ECS.md](../SSH_SETUP_ECS.md) for SSH setup details.

## Testing

```bash
# Run tests
npm test

# Run tests in watch mode
npm run test:watch
```

## Scripts

See [../README.md](../README.md#scripts) for a complete list of available scripts.

## Documentation

- [Main README](../README.md) - Overview and quick start
- [SSH_SETUP_ECS.md](../SSH_SETUP_ECS.md) - SSH configuration guide
- [DEPLOYMENT_ORDER.md](./DEPLOYMENT_ORDER.md) - Stack dependencies
- [COMPARISON_DOCKER_ECS.md](../COMPARISON_DOCKER_ECS.md) - Docker vs ECS comparison

