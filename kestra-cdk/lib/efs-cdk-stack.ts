import {
    Stack,
    StackProps,
    aws_ec2 as ec2,
    aws_efs as efs,
    aws_backup as backup,
    Duration,
    CfnOutput,
    RemovalPolicy,
  } from 'aws-cdk-lib';
  import { Construct } from 'constructs';
  
  interface EfsStackProps extends StackProps {
    vpc: ec2.IVpc;
    ecsSg: ec2.ISecurityGroup; // security group from ECS tasks
    containerInstanceSg?: ec2.ISecurityGroup; // security group from container instances (EC2)
  }
  
export class EfsStack extends Stack {
  readonly fileSystem: efs.FileSystem;
  // Temporarily keep Access Points to avoid CloudFormation export conflicts
  // They're not used by the task stack anymore, but CloudFormation still tracks the exports
  readonly postgresAccessPoint: efs.AccessPoint;
  readonly kestraDataAccessPoint: efs.AccessPoint;

  constructor(scope: Construct, id: string, props: EfsStackProps) {
    super(scope, id, props);

    const { vpc, ecsSg, containerInstanceSg } = props;

      // 🧩 1️⃣ Create a Security Group for EFS
      const efsSg = new ec2.SecurityGroup(this, 'EfsSecurityGroup', {
        vpc,
        description: 'Allow NFS access from ECS tasks and container instances',
        allowAllOutbound: true,
      });

      // Allow NFS (2049) from ECS task security group
      efsSg.addIngressRule(ecsSg, ec2.Port.tcp(2049), 'Allow NFS from ECS tasks');

      // Allow NFS (2049) from container instance security group
      // Container instances need this to mount EFS volumes on behalf of tasks
      if (containerInstanceSg) {
        efsSg.addIngressRule(containerInstanceSg, ec2.Port.tcp(2049), 'Allow NFS from container instances');
      }
  
      // 🧩 2️⃣ Create EFS File System
      this.fileSystem = new efs.FileSystem(this, 'KestraEfs', {
        vpc,
        securityGroup: efsSg,
        removalPolicy: RemovalPolicy.DESTROY, // ✅ destroy automatically when you tear down the stack
        lifecyclePolicy: efs.LifecyclePolicy.AFTER_14_DAYS, // Move to IA after 14 days
        performanceMode: efs.PerformanceMode.GENERAL_PURPOSE,
        throughputMode: efs.ThroughputMode.BURSTING,
        encrypted: true,
        fileSystemName: 'kestra-gitsync-efs',
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
    });

    // 🧩 3️⃣ Create EFS Access Points (kept for CloudFormation compatibility)
    // Note: Task stack no longer uses these, but CloudFormation exports still exist
    // We'll remove them later once all references are cleaned up

    this.postgresAccessPoint = new efs.AccessPoint(this, 'PostgresAccessPoint', {
      fileSystem: this.fileSystem,
      path: '/postgres-data',
      createAcl: {
        ownerGid: '999',
        ownerUid: '999',
        permissions: '755',
      },
      posixUser: {
        gid: '999',
        uid: '999',
      },
    });

    this.kestraDataAccessPoint = new efs.AccessPoint(this, 'KestraDataAccessPoint', {
      fileSystem: this.fileSystem,
      path: '/kestra-data',
      createAcl: {
        ownerGid: '0',
        ownerUid: '0',
        permissions: '755',
      },
      posixUser: {
        gid: '0',
        uid: '0',
      },
    });

    // 🧩 4️⃣ Enable automatic backups
      // Use unique name (max 50 chars, alphanumeric + hyphens/underscores only)
      // Format: kestra-efs-{account-last-4}-{region}
      const accountSuffix = this.account.slice(-4); // Last 4 digits of account
      const regionShort = this.region.replace('-', ''); // Remove hyphens from region
      const vaultName = `kestra-efs-${accountSuffix}-${regionShort}`;
      
      // Import existing backup vault (it already exists from a previous deployment)
      const vault = backup.BackupVault.fromBackupVaultName(this, 'KestraEfsBackupVault', vaultName);
  
      const plan = new backup.BackupPlan(this, 'KestraEfsBackupPlan', {
        backupPlanName: `KestraEfsDailyBackupPlan-${this.account}-${this.region}`,
        backupVault: vault,
      });
  
      plan.addRule(
        new backup.BackupPlanRule({
          ruleName: 'DailyBackup',
          enableContinuousBackup: true,
          deleteAfter: Duration.days(30),
        }),
      );
  
      plan.addSelection('EfsSelection', {
        resources: [backup.BackupResource.fromEfsFileSystem(this.fileSystem)],
      });
  
    // 🧩 5️⃣ Outputs for reference
    new CfnOutput(this, 'EfsId', { value: this.fileSystem.fileSystemId });
    new CfnOutput(this, 'EfsSgId', { value: efsSg.securityGroupId });
    // Keep Access Point outputs for CloudFormation compatibility (even though task stack doesn't use them)
    new CfnOutput(this, 'PostgresAccessPointId', { value: this.postgresAccessPoint.accessPointId });
    new CfnOutput(this, 'KestraDataAccessPointId', { value: this.kestraDataAccessPoint.accessPointId });
  }
}
  