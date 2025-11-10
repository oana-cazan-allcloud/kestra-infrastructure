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
  // This allows Kestra to run tasks as separate ECS tasks instead of Docker containers
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
          // ✅ Enable transit encryption for consistency with Access Points
          transitEncryption: 'ENABLED',
          authorizationConfig: {
            iam: 'ENABLED', // Required for transit encryption
          },
        },
      },
      {
        name: 'postgres-data',
        // Simplified: Mount root EFS, container will create /postgres-data subdirectory
        efsVolumeConfiguration: {
          fileSystemId: efsFileSystem.fileSystemId,
          transitEncryption: 'ENABLED',
          authorizationConfig: {
            iam: 'ENABLED',
          },
        },
      },
      {
        name: 'repo-watch',
        // ✅ Using EFS-native volume configuration (not dockerVolumeConfiguration)
        efsVolumeConfiguration: {
          fileSystemId: efsFileSystem.fileSystemId,
          transitEncryption: 'ENABLED',
          authorizationConfig: {
            iam: 'ENABLED',
          },
        },
      },
      {
        name: 'kestra-data',
        // Simplified: Mount root EFS, container will create /kestra-data subdirectory
        efsVolumeConfiguration: {
          fileSystemId: efsFileSystem.fileSystemId,
          transitEncryption: 'ENABLED',
          authorizationConfig: {
            iam: 'ENABLED',
          },
        },
      },
    ],
  });

  // -------------------------------------------------------------------------
  // 🧩 REMOVED: Init Container (no longer needed with Access Points)
  // Access Points automatically create directories, so init container is not required
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // 🧩 Container 1: PostgreSQL
  // -------------------------------------------------------------------------
  const postgresSecret = secretsmanager.Secret.fromSecretNameV2(this, 'PostgresSecret', 'kestra/postgres');
  
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

  // Wait for init container to create directories before starting Postgres
  // REMOVED: No longer needed with Access Points - they handle directory creation automatically
  // postgresContainer.addContainerDependencies({
  //   container: initContainer,
  //   condition: ecs.ContainerDependencyCondition.SUCCESS,
  // });

  postgresContainer.addMountPoints({
    containerPath: '/var/lib/postgresql/data',
    sourceVolume: 'postgres-data',
    readOnly: false,
  });

  // Note: Postgres will write to /var/lib/postgresql/data
  // Since we mount root EFS, Postgres will create its data directory there
  // We can organize it later if needed

  // -------------------------------------------------------------------------
  // 🧩 Container 2: Git-Sync (atomic updates) - Using SSH
  // -------------------------------------------------------------------------
  const gitSecret = secretsmanager.Secret.fromSecretNameV2(this, 'GitSyncSecret', 'kestra/git');

  // Init container to set up SSH keys from Secrets Manager
  // SSH keys are written to EFS subdirectory for git-sync to use
  const sshInitContainer = this.taskDefinition.addContainer('SshInit', {
    image: ecs.ContainerImage.fromRegistry('alpine:3.18'),
    essential: false,
    cpu: 64,
    memoryReservationMiB: 64,
    logging: logDriver,
    entryPoint: ['/bin/sh', '-c'],
    command: [
      `
      mkdir -p /etc/git-secret
      echo "$${SSH_PRIVATE_KEY}" > /etc/git-secret/ssh
      echo "$${SSH_KNOWN_HOSTS}" > /etc/git-secret/known_hosts
      chmod 600 /etc/git-secret/ssh
      chmod 644 /etc/git-secret/known_hosts
      echo "SSH keys initialized"
      `,
    ],
    secrets: {
      SSH_PRIVATE_KEY: ecs.Secret.fromSecretsManager(gitSecret, 'SSH_PRIVATE_KEY'),
      SSH_KNOWN_HOSTS: ecs.Secret.fromSecretsManager(gitSecret, 'SSH_KNOWN_HOSTS'),
    },
  });

  // Mount SSH keys directory as shared volume
  sshInitContainer.addMountPoints({
    containerPath: '/etc/git-secret',
    sourceVolume: 'efs-shared',
    readOnly: false,
  });

  const gitSyncContainer = this.taskDefinition.addContainer('GitSync', {
    image: ecs.ContainerImage.fromRegistry('registry.k8s.io/git-sync/git-sync:v4.4.2'),
    essential: true,
    cpu: 128,
    memoryReservationMiB: 256,
    logging: logDriver,
    user: 'root', // ✅ Match Docker Compose: user: "root"
    environment: {
      // ✅ Changed to SSH URL to match Docker Compose
      GITSYNC_REPO: 'git@github.com:oana-cazan-allcloud/cargo-partners.git',
      // ✅ Changed GITSYNC_BRANCH to GITSYNC_REF to match Docker Compose
      GITSYNC_REF: 'main',
      GITSYNC_ROOT: '/git',
      GITSYNC_LINK: 'repo', // ✅ Match Docker Compose: GITSYNC_LINK: repo
      GITSYNC_WAIT: '60',
      GITSYNC_PERIOD: '10s', // ✅ Match Docker Compose: GITSYNC_PERIOD: 10s
      GITSYNC_ONE_TIME: 'false',
      GITSYNC_MAX_FAILURES: '-1', // ✅ Match Docker Compose: GITSYNC_MAX_FAILURES: -1
      // ✅ SSH Configuration to match Docker Compose
      GITSYNC_SSH_KEY_FILE: '/etc/git-secret/ssh',
      GITSYNC_SSH_KNOWN_HOSTS: 'true',
      GITSYNC_SSH_KNOWN_HOSTS_FILE: '/etc/git-secret/known_hosts',
      GITSYNC_ADD_USER: 'true',
    },
    healthCheck: {
      command: ['CMD-SHELL', '[ -d /git/.git ] || exit 1'],
      interval: Duration.seconds(30),
      retries: 3,
      startPeriod: Duration.seconds(30),
      timeout: Duration.seconds(5),
    },
  });

  // Git-Sync depends on SSH init container
  gitSyncContainer.addContainerDependencies({
    container: sshInitContainer,
    condition: ecs.ContainerDependencyCondition.SUCCESS,
  });

  // Mount SSH keys directory (shared from init container via EFS)
  gitSyncContainer.addMountPoints(
    {
      containerPath: '/git',
      sourceVolume: 'efs-shared',
      readOnly: false,
    },
    {
      containerPath: '/etc/git-secret',
      sourceVolume: 'efs-shared',
      readOnly: true, // Read-only for git-sync
    }
  );

  // Wait for init container to create directories before starting GitSync
  // REMOVED: No longer needed with Access Points
  // gitSyncContainer.addContainerDependencies({
  //   container: initContainer,
  //   condition: ecs.ContainerDependencyCondition.SUCCESS,
  // });

  gitSyncContainer.addMountPoints({
    containerPath: '/git',
    sourceVolume: 'efs-shared',
    readOnly: false,
  });

  // -------------------------------------------------------------------------
  // 🧩 Container 3: Repo-Syncer (inotify + rsync)
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
      if [ -d /git/repo ]; then
        echo "Initial sync..."
        rsync -a --delete --exclude='.git' --exclude='.gitignore' /git/repo/ /repo/
      fi
      while true; do
        inotifywait -r -e modify,create,delete,move /git/repo 2>/dev/null
        sleep 2
        echo "Syncing changes..."
        rsync -a --delete --exclude='.git' --exclude='.gitignore' /git/repo/ /repo/
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

  // Wait for init container to create directories before starting RepoSyncer
  // REMOVED: No longer needed with Access Points
  // repoSyncerContainer.addContainerDependencies({
  //   container: initContainer,
  //   condition: ecs.ContainerDependencyCondition.SUCCESS,
  // });

  // -------------------------------------------------------------------------
  // 🧩 Container 4: Kestra Server
  // -------------------------------------------------------------------------
  const kestraContainer = this.taskDefinition.addContainer('KestraServer', {
    image: ecs.ContainerImage.fromRegistry('kestra/kestra:latest'),
    essential: true,
    cpu: 512,
    memoryReservationMiB: 1024,
    logging: logDriver,
    user: 'root', // ✅ Match Docker Compose: user: "root"
    command: ['server', 'standalone', '--no-tutorials'], // ✅ Match Docker Compose: command: server standalone --no-tutorials
    portMappings: [{ containerPort: 8080 }],
    environment: {
      KESTRA_SERVER_PORT: '8080',
      KESTRA_REPOSITORY_PATH: '/repo',
      KESTRA_DATABASE_JDBC_URL: 'jdbc:postgresql://localhost:5432/kestra',
      KESTRA_DATABASE_USERNAME: 'kestra',
      KESTRA_DATABASE_PASSWORD: 'kestra',
      KESTRA_STORAGE_TYPE: 's3', // ⚠️ Using S3 instead of local (Docker Compose uses local)
      KESTRA_STORAGE_S3_BUCKET: this.s3Bucket.bucketName,
      // Note: Docker Compose uses local storage, but ECS uses S3 for better scalability
      // Docker socket mount (/var/run/docker.sock) is not available in ECS
      // /tmp/kestra-wd mount is handled by container's tmpfs
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

  // Note: Kestra will write to /app/storage
  // Since we mount root EFS, Kestra will create its storage directory there

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
    },
    // REMOVED: Init container dependency - Access Points handle directory creation automatically
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
