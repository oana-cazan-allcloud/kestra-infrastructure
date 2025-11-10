import {
  Stack,
  StackProps,
  aws_ec2 as ec2,
  aws_ecs as ecs,
  aws_elasticloadbalancingv2 as elbv2,
  aws_applicationautoscaling as appscaling,
  Duration,
  CfnOutput,
  RemovalPolicy,
} from 'aws-cdk-lib';
import { Construct } from 'constructs';

interface EcsServiceStackProps extends StackProps {
  vpc: ec2.IVpc;
  cluster: ecs.Cluster;
  taskDefinition: ecs.Ec2TaskDefinition;
  targetGroup: elbv2.ApplicationTargetGroup;
  ecsServiceSg: ec2.ISecurityGroup; // Security group from ALB stack (for ALB access)
  ecsSg: ec2.ISecurityGroup; // Security group from cluster stack (for EFS access)
}

export class EcsServiceStack extends Stack {
  constructor(scope: Construct, id: string, props: EcsServiceStackProps) {
    super(scope, id, props);

    const { vpc, cluster, taskDefinition, targetGroup, ecsServiceSg, ecsSg } = props;

    // Use both security groups:
    // - ecsServiceSg: Allows ALB to reach tasks on port 8080
    // - ecsSg: Allows tasks to access EFS on port 2049

    // 🔹 ECS Service
    const service = new ecs.Ec2Service(this, 'KestraService', {
      cluster,
      taskDefinition,
      desiredCount: 0, // ✅ Start with 0 tasks - scale up manually after deployment succeeds
      securityGroups: [ecsServiceSg, ecsSg], // Both security groups for ALB and EFS access
      minHealthyPercent: 0, // ✅ Allow 0% healthy during initial deployment (gives more time for containers to start)
      maxHealthyPercent: 100, // ✅ Don't exceed desired count during deployment
      deploymentController: {
        type: ecs.DeploymentControllerType.ECS,
      },
      circuitBreaker: {
        enable: true,
        rollback: true, // ✅ Deployment circuit breaker
      },
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      placementStrategies: [
        ecs.PlacementStrategy.spreadAcross(ecs.BuiltInAttributes.AVAILABILITY_ZONE),
        ecs.PlacementStrategy.packedByCpu(),
      ],
      // Removed conflicting placement constraint - let it spread across AZs for HA
    });

    // 🔒 Prevent accidental deletion during stack deletion
    // Note: ECS services don't support EnableDeletionProtection in CloudFormation
    // This DeletionPolicy will retain the service if the stack is deleted
    // To prevent deletion during updates, ensure service name/logical ID doesn't change
    const cfnService = service.node.defaultChild as ecs.CfnService;
    cfnService.applyRemovalPolicy(RemovalPolicy.RETAIN);

    // 🔹 Attach the service to the ALB Target Group
    service.attachToApplicationTargetGroup(targetGroup);

    // 🔹 Auto Scaling based on CPU & Memory
    const scalableTarget = service.autoScaleTaskCount({
      minCapacity: 1,
      maxCapacity: 5,
    });

    scalableTarget.scaleOnCpuUtilization('CpuScaling', {
      targetUtilizationPercent: 60,
      scaleInCooldown: Duration.seconds(60),
      scaleOutCooldown: Duration.seconds(60),
    });

    scalableTarget.scaleOnMemoryUtilization('MemoryScaling', {
      targetUtilizationPercent: 70,
      scaleInCooldown: Duration.seconds(60),
      scaleOutCooldown: Duration.seconds(60),
    });

    // 🔹 Output for easy reference
    new CfnOutput(this, 'EcsServiceName', { value: service.serviceName });
    new CfnOutput(this, 'ServiceSecurityGroupId', { value: ecsServiceSg.securityGroupId });
    new CfnOutput(this, 'PlacementStrategy', {
      value: 'Spread across AZs, packed by CPU for high availability',
    });
  }
}
