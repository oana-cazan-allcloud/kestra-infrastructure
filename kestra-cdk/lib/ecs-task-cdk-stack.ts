import {
  Stack,
  StackProps,
  aws_ecs as ecs,
  aws_ec2 as ec2,
  aws_efs as efs,
  aws_logs as logs,
  aws_iam as iam,
  aws_s3 as s3,
  CfnOutput,
  RemovalPolicy,
  Duration,
  aws_secretsmanager as secretsmanager,
} from 'aws-cdk-lib';
import { Construct } from 'constructs';

interface EcsTaskStackProps extends StackProps {
  vpc: ec2.IVpc;
  cluster: ecs.Cluster;
  efsFileSystem: efs.IFileSystem;
  s3Bucket: s3.Bucket;
}

export class EcsTaskStack extends Stack {
  readonly taskRole: iam.Role;
  readonly taskDefinition: ecs.Ec2TaskDefinition;
  readonly s3Bucket: s3.Bucket;

  constructor(scope: Construct, id: string, props: EcsTaskStackProps) {
    super(scope, id, props);

    const { efsFileSystem, s3Bucket, cluster } = props;
    this.s3Bucket = s3Bucket;

    // 🔹 1️⃣ IAM Roles
    const executionRole = new iam.Role(this, 'KestraTaskExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });

    // Grant permissions for ECR, logs, EFS
    executionRole.addToPolicy(
      new iam.PolicyStatement({
        actions: [
          'ecr:GetAuthorizationToken',
          'ecr:BatchCheckLayerAvailability',
          'ecr:GetDownloadUrlForLayer',
          'ecr:BatchGetImage',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
          'elasticfilesystem:ClientMount',
          'elasticfilesystem:ClientWrite',
          'elasticfilesystem:ClientRootAccess', // Required for EFS IAM authorization
        ],
        resources: ['*'],
      })
    );

    // Grant specific permissions for secrets
    executionRole.addToPolicy(
      new iam.PolicyStatement({
        actions: ['secretsmanager:GetSecretValue'],
        resources: [
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:kestra/git*`,
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:kestra/postgres*`,
        ],
      })
    );

    this.taskRole = new iam.Role(this, 'KestraTaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
    });

    this.taskRole.addToPolicy(
      new iam.PolicyStatement({
        actions: ['s3:GetObject', 's3:PutObject', 's3:DeleteObject', 's3:ListBucket'],
        resources: ['*'],
      })
    );

    // Grant ECS permissions for Kestra ECS Executor (alternative to Docker socket)
    this.taskRole.addToPolicy(
      new iam.PolicyStatement({
        actions: [
          'ecs:RunTask',
          'ecs:StopTask',
          'ecs:DescribeTasks',
          'ecs:DescribeTaskDefinition',
          'ecs:ListTasks',
        ],
        resources: [
          cluster.clusterArn,
          `${cluster.clusterArn}/*`,
          `arn:aws:ecs:${this.region}:${this.account}:task-definition/*`,
        ],
      })
    );

    this.taskRole.addToPolicy(
      new iam.PolicyStatement({
        actions: ['elasticfilesystem:ClientMount', 'elasticfilesystem:ClientWrite'],
        resources: [efsFileSystem.fileSystemArn],
      })
    );

    this.taskRole.addToPolicy(
      new iam.PolicyStatement({
        actions: ['logs:CreateLogStream', 'logs:PutLogEvents', 'cloudwatch:PutMetricData'],
        resources: ['*'],
      })
    );

    // 🔹 2️⃣ CloudWatch Logs
    const logGroup = new logs.LogGroup(this, 'KestraLogs', {
      logGroupName: '/ecs/kestra',
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const logDriver = ecs.LogDriver.awsLogs({
      logGroup,
      streamPrefix: 'kestra',
    });

    // 🔹 3️⃣ Task Definition with Volumes
    this.taskDefinition = new ecs.Ec2TaskDefinition(this, 'KestraTaskDef', {
      networkMode: ecs.NetworkMode.AWS_VPC,
      taskRole: this.taskRole,
      executionRole,
      volumes: [
        {
          name: 'efs-shared',
          efsVolumeConfiguration: {
            fileSystemId: efsFileSystem.fileSystemId,
            rootDirectory: '/git-flows', // ✅ Isolate git-sync data
            transitEncryption: 'ENABLED',
            authorizationConfig: {
              iam: 'ENABLED',
            },
          },
        },
        {
          name: 'postgres-data',
          efsVolumeConfiguration: {
            fileSystemId: efsFileSystem.fileSystemId,
            rootDirectory: '/postgres-data', // ✅ Isolate Postgres data
            transitEncryption: 'ENABLED',
            authorizationConfig: {
              iam: 'ENABLED',
            },
          },
        },
        {
          name: 'repo-watch',
          efsVolumeConfiguration: {
            fileSystemId: efsFileSystem.fileSystemId,
            rootDirectory: '/repo-watch', // ✅ Isolate synced repo
            transitEncryption: 'ENABLED',
            authorizationConfig: {
              iam: 'ENABLED',
            },
          },
        },
        {
          name: 'kestra-data',
          efsVolumeConfiguration: {
            fileSystemId: efsFileSystem.fileSystemId,
            rootDirectory: '/kestra-data', // ✅ Isolate Kestra storage
            transitEncryption: 'ENABLED',
            authorizationConfig: {
              iam: 'ENABLED',
            },
          },
        },
      ],
    });

    // -------------------------------------------------------------------------
    // 🧩 Container 1: PostgreSQL
    // -------------------------------------------------------------------------
    const postgresSecret = secretsmanager.Secret.fromSecretNameV2(this, 'PostgresSecret', 'kestra/postgres');

    // Init container to prepare Postgres data directory
    // This ensures the directory exists and handles existing data
    const postgresInitContainer = this.taskDefinition.addContainer('PostgresInit', {
      image: ecs.ContainerImage.fromRegistry('alpine:3.18'),
      essential: false,
      cpu: 64,
      memoryReservationMiB: 64,
      logging: logDriver,
      entryPoint: ['/bin/sh', '-c'],
      command: [
        `
        # Check if Postgres data directory exists and has valid data
        if [ -f /var/lib/postgresql/data/PG_VERSION ]; then
          echo "Postgres data directory already initialized, skipping..."
        else
          echo "Cleaning Postgres data directory for fresh initialization..."
          rm -rf /var/lib/postgresql/data/*
          rm -rf /var/lib/postgresql/data/.[!.]*
        fi
        echo "Postgres data directory ready"
        `,
      ],
    });

    postgresInitContainer.addMountPoints({
      containerPath: '/var/lib/postgresql/data',
      sourceVolume: 'postgres-data',
      readOnly: false,
    });

    const postgresContainer = this.taskDefinition.addContainer('Postgres', {
      image: ecs.ContainerImage.fromRegistry('postgres:17'),
      essential: true,
      cpu: 256,
      memoryReservationMiB: 512,
      memoryLimitMiB: 1024,
      logging: logDriver,
      environment: {
        POSTGRES_USER: 'kestra',
        POSTGRES_DB: 'kestra',
      },
      secrets: {
        POSTGRES_PASSWORD: ecs.Secret.fromSecretsManager(postgresSecret),
      },
      portMappings: [
        {
          containerPort: 5432,
          hostPort: 5432,
          protocol: ecs.Protocol.TCP,
        },
      ],
      healthCheck: {
        command: ['CMD-SHELL', 'pg_isready -U kestra'],
        interval: Duration.seconds(10),
        retries: 3,
        startPeriod: Duration.seconds(30),
        timeout: Duration.seconds(5),
      },
    });

    // Postgres depends on init container
    postgresContainer.addContainerDependencies({
      container: postgresInitContainer,
      condition: ecs.ContainerDependencyCondition.SUCCESS,
    });

    postgresContainer.addMountPoints({
      containerPath: '/var/lib/postgresql/data',
      sourceVolume: 'postgres-data',
      readOnly: false,
    });

    // -------------------------------------------------------------------------
    // 🧩 Container 2: SSH Init Container
    // -------------------------------------------------------------------------
    const gitSecret = secretsmanager.Secret.fromSecretNameV2(this, 'GitSyncSecret', 'kestra/git');

    const sshInitContainer = this.taskDefinition.addContainer('SshInit', {
      image: ecs.ContainerImage.fromRegistry('alpine:3.18'),
      essential: false,
      cpu: 64,
      memoryReservationMiB: 64,
      logging: logDriver,
      entryPoint: ['/bin/sh', '-c'],
      command: [
        `
        # Create SSH directory structure
        mkdir -p /git/.ssh
        
        # Write SSH keys
        printf '%s' "$SSH_PRIVATE_KEY" > /git/.ssh/ssh
        printf '%s' "$SSH_KNOWN_HOSTS" > /git/.ssh/known_hosts
        
        # Set permissions
        chmod 700 /git/.ssh
        chmod 600 /git/.ssh/ssh
        chmod 644 /git/.ssh/known_hosts
        
        # Validate key format
        if ! head -1 /git/.ssh/ssh | grep -q "BEGIN"; then
          echo "ERROR: SSH key format invalid"
          exit 1
        fi
        
        echo "SSH keys initialized successfully"
        ls -la /git/.ssh/
        `,
      ],
      secrets: {
        SSH_PRIVATE_KEY: ecs.Secret.fromSecretsManager(gitSecret, 'SSH_PRIVATE_KEY'),
        SSH_KNOWN_HOSTS: ecs.Secret.fromSecretsManager(gitSecret, 'SSH_KNOWN_HOSTS'),
      },
    });

    sshInitContainer.addMountPoints({
      containerPath: '/git',
      sourceVolume: 'efs-shared',
      readOnly: false,
    });

    // -------------------------------------------------------------------------
    // 🧩 Container 3: Git-Sync (atomic updates) - Using SSH
    // -------------------------------------------------------------------------
    const gitSyncContainer = this.taskDefinition.addContainer('GitSync', {
      image: ecs.ContainerImage.fromRegistry('registry.k8s.io/git-sync/git-sync:v4.4.2'),
      essential: true,
      cpu: 128,
      memoryReservationMiB: 256,
      logging: logDriver,
      user: 'root',
      environment: {
        GITSYNC_REPO: 'git@github.com:oana-cazan-allcloud/cargo-partners.git',
        GITSYNC_REF: 'main',
        GITSYNC_ROOT: '/git',
        GITSYNC_LINK: 'repo',
        GITSYNC_WAIT: '60',
        GITSYNC_PERIOD: '10s',
        GITSYNC_ONE_TIME: 'false',
        GITSYNC_MAX_FAILURES: '-1',
        // ✅ Updated SSH paths
        GITSYNC_SSH_KEY_FILE: '/git/.ssh/ssh',
        GITSYNC_SSH_KNOWN_HOSTS: 'true',
        GITSYNC_SSH_KNOWN_HOSTS_FILE: '/git/.ssh/known_hosts',
        GITSYNC_ADD_USER: 'true',
      },
      healthCheck: {
        command: ['CMD-SHELL', '[ -d /git/repo ] && [ -f /git/repo/.git/config ] || exit 1'],
        interval: Duration.seconds(30),
        retries: 3,
        startPeriod: Duration.seconds(60), // ✅ Increased - git clone takes time
        timeout: Duration.seconds(5),
      },
    });

    // Git-Sync depends on SSH init container
    gitSyncContainer.addContainerDependencies({
      container: sshInitContainer,
      condition: ecs.ContainerDependencyCondition.SUCCESS,
    });

    gitSyncContainer.addMountPoints({
      containerPath: '/git',
      sourceVolume: 'efs-shared',
      readOnly: false,
    });

    // -------------------------------------------------------------------------
    // 🧩 Container 4: Repo-Syncer (inotify + rsync)
    // -------------------------------------------------------------------------
    const repoSyncerContainer = this.taskDefinition.addContainer('RepoSyncer', {
      image: ecs.ContainerImage.fromRegistry('alpine:3.18'),
      essential: true,
      cpu: 128,
      memoryReservationMiB: 256,
      logging: logDriver,
      entryPoint: ['/bin/sh', '-c'],
      command: [
        `
        apk add --no-cache rsync inotify-tools
        echo "Repo syncer started..."
        
        # Wait for git-sync to create the repo directory
        echo "Waiting for /git/repo to exist..."
        TIMEOUT=300  # 5 minutes timeout
        ELAPSED=0
        while [ ! -d /git/repo ] && [ $ELAPSED -lt $TIMEOUT ]; do
          echo "Waiting... ($ELAPSED seconds elapsed)"
          sleep 5
          ELAPSED=$((ELAPSED + 5))
        done
        
        if [ ! -d /git/repo ]; then
          echo "ERROR: /git/repo not found after $TIMEOUT seconds"
          exit 1
        fi
        
        echo "Found /git/repo, performing initial sync..."
        
        # Initial sync with error handling
        if ! rsync -av --delete --exclude='.git' --exclude='.gitignore' /git/repo/ /repo/; then
          echo "ERROR: Initial sync failed"
          exit 1
        fi
        
        echo "Initial sync complete. Starting watch loop..."
        
        # Watch for changes
        while true; do
          if inotifywait -r -e modify,create,delete,move /git/repo 2>/dev/null; then
            sleep 2
            echo "Syncing changes..."
            rsync -av --delete --exclude='.git' --exclude='.gitignore' /git/repo/ /repo/ || echo "Sync failed, will retry on next change"
          fi
        done
        `,
      ],
    });

    repoSyncerContainer.addMountPoints(
      {
        containerPath: '/git',
        sourceVolume: 'efs-shared',
        readOnly: true,
      },
      {
        containerPath: '/repo',
        sourceVolume: 'repo-watch',
        readOnly: false,
      }
    );

    // ✅ Wait for git-sync to be healthy before starting
    repoSyncerContainer.addContainerDependencies({
      container: gitSyncContainer,
      condition: ecs.ContainerDependencyCondition.HEALTHY,
    });

    // -------------------------------------------------------------------------
    // 🧩 Container 5: Kestra Server
    // -------------------------------------------------------------------------
    const kestraContainer = this.taskDefinition.addContainer('KestraServer', {
      image: ecs.ContainerImage.fromRegistry('kestra/kestra:latest'),
      essential: true,
      cpu: 512,
      memoryReservationMiB: 1024,
      logging: logDriver,
      user: 'root',
      command: ['server', 'standalone', '--no-tutorials'],
      portMappings: [{ containerPort: 8080 }],
      environment: {
        KESTRA_SERVER_PORT: '8080',
        KESTRA_REPOSITORY_PATH: '/repo',
        KESTRA_DATABASE_JDBC_URL: 'jdbc:postgresql://localhost:5432/kestra',
        KESTRA_DATABASE_USERNAME: 'kestra',
        KESTRA_DATABASE_PASSWORD: 'kestra',
        KESTRA_STORAGE_TYPE: 's3',
        KESTRA_STORAGE_S3_BUCKET: this.s3Bucket.bucketName,
      },
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:8080/api/v1/health || exit 1'],
        interval: Duration.seconds(30),
        retries: 3,
        startPeriod: Duration.seconds(60),
        timeout: Duration.seconds(5),
      },
    });

    kestraContainer.addMountPoints(
      {
        containerPath: '/repo',
        sourceVolume: 'repo-watch',
        readOnly: true,
      },
      {
        containerPath: '/app/storage',
        sourceVolume: 'kestra-data',
        readOnly: false,
      }
    );

    // -------------------------------------------------------------------------
    // 🔄 Container Dependencies
    // -------------------------------------------------------------------------
    kestraContainer.addContainerDependencies(
      {
        container: postgresContainer,
        condition: ecs.ContainerDependencyCondition.HEALTHY,
      },
      {
        container: gitSyncContainer,
        condition: ecs.ContainerDependencyCondition.START,
      },
      {
        container: repoSyncerContainer,
        condition: ecs.ContainerDependencyCondition.START,
      }
    );

    // -------------------------------------------------------------------------
    // 📤 Outputs
    // -------------------------------------------------------------------------
    new CfnOutput(this, 'TaskDefinitionArn', {
      value: this.taskDefinition.taskDefinitionArn,
    });
    new CfnOutput(this, 'TaskRoleArn', { value: this.taskRole.roleArn });
  }
}