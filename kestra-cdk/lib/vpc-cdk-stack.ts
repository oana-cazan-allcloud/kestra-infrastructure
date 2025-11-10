import * as cdk from 'aws-cdk-lib/core';
import {
  Stack,
  StackProps,
  aws_ec2 as ec2,
  aws_route53resolver as route53resolver,
  CfnOutput,
} from 'aws-cdk-lib';
import { Construct } from 'constructs';

export class VPCCdkStack extends cdk.Stack {
  // 🧩 Expose key resources as public attributes
  readonly vpc: ec2.Vpc;
  readonly albSg: ec2.SecurityGroup;
  readonly ecsSg: ec2.SecurityGroup;
  readonly efsSg: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // --- 1️⃣ Create a new VPC ---
    this.vpc = new ec2.Vpc(this, 'KestraVpc', {
      vpcName: 'KestraVpc',
      maxAzs: 2,
      natGateways: 1,
      subnetConfiguration: [
        { name: 'Public', subnetType: ec2.SubnetType.PUBLIC, cidrMask: 24 },
        { name: 'Private', subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS, cidrMask: 24 },
      ],
      // ✅ Enable DNS resolution for EFS DNS names (e.g., fs-xxxxx.efs.region.amazonaws.com)
      // This is REQUIRED for ECS to resolve EFS mount target DNS names
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // --- 2️⃣ Security Groups ---
    this.albSg = new ec2.SecurityGroup(this, 'AlbSg', {
      vpc: this.vpc,
      description: 'Allow HTTP/HTTPS inbound for ALB',
      allowAllOutbound: true,
    });
    this.albSg.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(80), 'Allow HTTP');
    this.albSg.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(443), 'Allow HTTPS');

    this.ecsSg = new ec2.SecurityGroup(this, 'EcsTasksSg', {
      vpc: this.vpc,
      description: 'Allow inbound traffic from ALB',
      allowAllOutbound: true,
    });
    this.ecsSg.addIngressRule(this.albSg, ec2.Port.tcp(8080), 'Allow ALB to ECS');

    this.efsSg = new ec2.SecurityGroup(this, 'EfsSg', {
      vpc: this.vpc,
      description: 'Allow ECS tasks to access EFS',
      allowAllOutbound: true,
    });
    this.efsSg.addIngressRule(this.ecsSg, ec2.Port.tcp(2049), 'Allow NFS from ECS');

    // --- 3️⃣ Outputs for reference (optional) ---
    new CfnOutput(this, 'VpcId', { value: this.vpc.vpcId });
    new CfnOutput(this, 'PublicSubnets', {
      value: this.vpc.publicSubnets.map(s => s.subnetId).join(', '),
    });
    new CfnOutput(this, 'PrivateSubnets', {
      value: this.vpc.privateSubnets.map(s => s.subnetId).join(', '),
    });
    new CfnOutput(this, 'AlbSecurityGroup', { value: this.albSg.securityGroupId });
    new CfnOutput(this, 'EcsTasksSecurityGroup', { value: this.ecsSg.securityGroupId });
    new CfnOutput(this, 'EfsSecurityGroup', { value: this.efsSg.securityGroupId });
  }
}
