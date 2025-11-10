import {
  Stack,
  StackProps,
  aws_ec2 as ec2,
  aws_ecs as ecs,
  aws_autoscaling as autoscaling,
  aws_iam as iam,
  CfnOutput,
} from 'aws-cdk-lib';
import { Construct } from 'constructs';

export interface EcsClusterStackProps extends StackProps {
  vpc: ec2.IVpc;
}

export class EcsClusterStack extends Stack {
  readonly cluster: ecs.Cluster;
  readonly ecsSg: ec2.SecurityGroup;
  readonly containerInstanceSg: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: EcsClusterStackProps) {
    super(scope, id, props);

    const { vpc } = props;

    // ⚙️ Create ECS Cluster
    this.cluster = new ecs.Cluster(this, 'KestraEcsCluster', {
      vpc,
      clusterName: 'kestra-cluster',
      // Container Insights can be enabled via CloudWatch settings or AWS Console
      // The containerInsights property is deprecated in favor of containerInsightsV2
    });

    // 💡 ECS Task Security Group
    // Note: ALB access is handled via ecsServiceSg from ALB stack
    // This security group is used for EFS access and other task-to-task communication
    this.ecsSg = new ec2.SecurityGroup(this, 'EcsTasksSg', {
      vpc,
      description: 'Security group for ECS tasks running Kestra',
      allowAllOutbound: false, // strict outbound control
    });

    // ✅ Egress: allow DNS (UDP 53) to VPC DNS resolver - REQUIRED for VPC networking
    this.ecsSg.addEgressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.udp(53),
      'Allow DNS resolution via VPC DNS resolver',
    );

    // ✅ Egress: allow outbound HTTPS (443) to AWS APIs, GitHub, etc.
    this.ecsSg.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow outbound HTTPS for AWS APIs, S3, and git clone',
    );

    // ✅ Egress: allow NFS (2049) traffic to EFS within VPC
    // Note: EFS is in the VPC, so we allow NFS to VPC CIDR
    // EFS security group will control ingress (who can access)
    this.ecsSg.addEgressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(2049),
      'Allow NFS traffic to EFS for shared storage',
    );

    // 💡 Security Group for Container Instances (EC2)
    // Container instances need to mount EFS volumes on behalf of tasks
    this.containerInstanceSg = new ec2.SecurityGroup(this, 'ContainerInstanceSg', {
      vpc,
      description: 'Security group for ECS container instances',
      allowAllOutbound: true,
    });

    // 💡 EC2 AutoScaling Group for ECS capacity
    const asg = new autoscaling.AutoScalingGroup(this, 'KestraAsg', {
      vpc,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.LARGE),
      machineImage: ecs.EcsOptimizedImage.amazonLinux2(),
      minCapacity: 1,
      maxCapacity: 3,
      // Note: desiredCapacity is intentionally omitted to avoid resetting ASG size on every deployment
      // The ASG will start with minCapacity (1) and can scale based on demand
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      securityGroup: this.containerInstanceSg, // Assign security group to container instances
    });

    // Add IAM policies for ECS + SSM
    asg.role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName(
        'service-role/AmazonEC2ContainerServiceforEC2Role',
      ),
    );
    asg.role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
    );

    // Grant EFS permissions to container instance role
    // Container instances need this to mount EFS volumes on behalf of tasks
    // Note: asg.role is an IRole, so we need to attach an inline policy
    const efsPolicy = new iam.Policy(this, 'ContainerInstanceEfsPolicy', {
      statements: [
        new iam.PolicyStatement({
          actions: [
            'elasticfilesystem:ClientMount',
            'elasticfilesystem:ClientWrite',
            'elasticfilesystem:ClientRootAccess',
          ],
          resources: ['*'], // Allow access to any EFS in the account
        }),
      ],
    });
    efsPolicy.attachToRole(asg.role);

    // 🧩 Attach AutoScalingGroup as Capacity Provider
    const capacityProvider = new ecs.AsgCapacityProvider(this, 'KestraCapacityProvider', {
      autoScalingGroup: asg,
    });
    this.cluster.addAsgCapacityProvider(capacityProvider);

    // 📤 Outputs
    new CfnOutput(this, 'ClusterName', { value: this.cluster.clusterName });
    new CfnOutput(this, 'AutoScalingGroupName', { value: asg.autoScalingGroupName });
    new CfnOutput(this, 'EcsTasksSecurityGroupId', { value: this.ecsSg.securityGroupId });
  }
}
