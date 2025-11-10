#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib/core';
import { KestraCdkStack } from '../lib/kestra-cdk-stack';
import { VPCCdkStack } from '../lib/vpc-cdk-stack';
import { EcsClusterStack } from '../lib/ecs-cluster-cdk-stack';
import { EfsStack } from '../lib/efs-cdk-stack';
import { S3Stack } from '../lib/s3-cdk-stack';
import { EcsTaskStack } from '../lib/ecs-task-cdk-stack';
import { EcsAlbStack } from '../lib/ecs-service-alb-stack';
import { EcsServiceStack } from '../lib/ecs-service-cdk-stack';
import { WafStack } from '../lib/waf-cdk-stack';
import { BackupStack } from '../lib/backup-cdk-stack';
const app = new cdk.App();


const env = { account: '822550017122', region: 'eu-central-1' };

new KestraCdkStack(app, 'KestraCdkStack', {
  env
  /* For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html */
});

// 🧱 1️⃣ Base network layer
const vpcStack = new VPCCdkStack(app, 'KestraVpcStack', { env });

// 🧱 2️⃣ ECS Cluster layer (depends on VPC)
const ecsClusterStack = new EcsClusterStack(app, 'KestraEcsClusterStack', {
  vpc: vpcStack.vpc,
  env,
});
ecsClusterStack.addDependency(vpcStack);

// 3️⃣ EFS stack
const efsStack = new EfsStack(app, 'KestraEfsStack', {  
  vpc: vpcStack.vpc,
  ecsSg: ecsClusterStack.ecsSg, // connect ECS tasks SG for NFS access
  containerInstanceSg: ecsClusterStack.containerInstanceSg, // connect container instance SG for EFS mounting
  env,
});
efsStack.addDependency(ecsClusterStack);


// 4️⃣ S3
const s3Stack = new S3Stack(app, 'KestraS3Stack', {
  env,
  // Optional: if you already have ECS task role, pass its ARN to restrict access
  // ecsTaskRoleArn: 'arn:aws:iam::822550017122:role/your-ecs-task-role',
});
s3Stack.addDependency(efsStack);


const ecsTaskStack = new EcsTaskStack(app, 'KestraEcsTaskStack', {
  vpc: vpcStack.vpc,
  cluster: ecsClusterStack.cluster,
  efsFileSystem: efsStack.fileSystem,
  s3Bucket: s3Stack.bucket,
  env,
});

ecsTaskStack.addDependency(efsStack);
ecsTaskStack.addDependency(ecsClusterStack);

const ecsAlbStack = new EcsAlbStack(app, 'KestraAlbStack', {
  vpc: vpcStack.vpc,
  env,
});

// ALB only needs VPC - it can be deployed independently
// Cluster and task definition are not needed for ALB construction
// Service stack will connect ALB to cluster and tasks
ecsAlbStack.addDependency(vpcStack);

const ecsServiceStack = new EcsServiceStack(app, 'KestraEcsServiceStack', {
  vpc: vpcStack.vpc,
  cluster: ecsClusterStack.cluster,
  taskDefinition: ecsTaskStack.taskDefinition,
  targetGroup: ecsAlbStack.targetGroup, // expose targetGroup from ALB stack
  ecsServiceSg: ecsAlbStack.ecsServiceSg, // use security group from ALB stack (for ALB access)
  ecsSg: ecsClusterStack.ecsSg, // use security group from cluster stack (for EFS access)
  env,
});

// Ensure service stack deploys AFTER task stack to get latest active task definition
ecsServiceStack.addDependency(ecsTaskStack);
ecsServiceStack.addDependency(ecsAlbStack);

const wafStack = new WafStack(app, 'KestraWafStack', {
  alb: ecsAlbStack.alb,                 // make sure EcsAlbStack exposes `alb: IApplicationLoadBalancer`
  webhookPath: '/webhook/jira',         // adjust as needed
  rateLimitPer5Min: 300,                // 300 req / 5min per IP
  allowCountries: ['RO','DE','FR'],     // optional
  ipAllowList: [],                      // optional CIDRs
  ipBlockList: [],                      // optional CIDRs
  env,
});   
wafStack.addDependency(ecsAlbStack);


// 🧾 Backup Stack
const backupStack = new BackupStack(app, 'KestraBackupStack', {
  efsFileSystem: efsStack.fileSystem,
  env,
});
backupStack.addDependency(efsStack);


cdk.Tags.of(app).add('Project', 'Kestra');
cdk.Tags.of(app).add('Environment', 'Production'); // or 'Development'
cdk.Tags.of(app).add('Owner', 'Oana Iacob');
cdk.Tags.of(app).add('ManagedBy', 'AWS CDK');
