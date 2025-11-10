import {
    Stack,
    StackProps,
    Duration,
    aws_backup as backup,
    aws_events as events,
    aws_iam as iam,
    aws_efs as efs,
  } from 'aws-cdk-lib';
  import { Construct } from 'constructs';
  
  interface BackupStackProps extends StackProps {
    efsFileSystem: efs.IFileSystem;
  }
  
  export class BackupStack extends Stack {
    constructor(scope: Construct, id: string, props: BackupStackProps) {
      super(scope, id, props);
  
      const { efsFileSystem } = props;
  
      // 🏦 1️⃣ Backup Vault (stores snapshots)
      const vault = new backup.BackupVault(this, 'KestraBackupVault', {
        backupVaultName: 'KestraBackupVault',
      });
  
      // 🧩 2️⃣ Backup Plan
      const plan = new backup.BackupPlan(this, 'KestraBackupPlan', {
        backupPlanName: 'KestraDailyBackupPlan',
        backupVault: vault,
      });
  
      // 🕒 3️⃣ Add a daily backup rule (2 AM UTC, 30-day retention)
      plan.addRule(
        new backup.BackupPlanRule({
          ruleName: 'DailyBackup',
          scheduleExpression: events.Schedule.cron({ minute: '0', hour: '2' }),
          deleteAfter: Duration.days(30),
        }),
      );
  
      // 🔐 4️⃣ Dedicated IAM role for AWS Backup
      const backupRole = new iam.Role(this, 'KestraBackupRole', {
        assumedBy: new iam.ServicePrincipal('backup.amazonaws.com'),
      });
  
      backupRole.addManagedPolicy(
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBackupServiceRolePolicyForBackup'),
      );
  
      backupRole.addManagedPolicy(
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBackupServiceRolePolicyForRestores'),
      );
  
      // 🎯 5️⃣ Add the EFS filesystem as a backup resource with IAM role
      plan.addSelection('EfsBackupSelection', {
        resources: [
          backup.BackupResource.fromArn(efsFileSystem.fileSystemArn),
        ],
        role: backupRole,
      });
    }
  }
  