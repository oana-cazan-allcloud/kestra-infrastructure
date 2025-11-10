import {
  Stack,
  StackProps,
  aws_ec2 as ec2,
  aws_ecs as ecs,
  aws_elasticloadbalancingv2 as elbv2,
  Duration,
  CfnOutput,
} from 'aws-cdk-lib';
import { Construct } from 'constructs';

interface EcsAlbStackProps extends StackProps {
  vpc: ec2.IVpc;
}

export class EcsAlbStack extends Stack {
  readonly targetGroup: elbv2.ApplicationTargetGroup;
  readonly alb: elbv2.ApplicationLoadBalancer;
  readonly ecsServiceSg: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: EcsAlbStackProps) {
    super(scope, id, props);

    const { vpc } = props;
    
    // 🔹 1️⃣ Security Groups
    const albSg = new ec2.SecurityGroup(this, 'AlbSecurityGroup', {
      vpc,
      description: 'Allow HTTP traffic to ALB',
      allowAllOutbound: true,
    });
    albSg.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(80), 'Allow inbound HTTP traffic from the internet');

    // Security group for ECS service (will be used by EcsServiceStack)
    const ecsServiceSg = new ec2.SecurityGroup(this, 'EcsServiceSecurityGroup', {
      vpc,
      description: 'Allow ALB to access ECS service on Kestra port 8080',
      allowAllOutbound: true,
    });
    ecsServiceSg.addIngressRule(albSg, ec2.Port.tcp(8080), 'Allow ALB to ECS task on Kestra port 8080');
    
    // Export security group so EcsServiceStack can reference it
    this.ecsServiceSg = ecsServiceSg;

    // 🔹 2️⃣ Application Load Balancer
    // Note: Removed hardcoded name to avoid conflicts - CDK will generate unique name
    this.alb = new elbv2.ApplicationLoadBalancer(this, 'KestraALB', {
      vpc,
      internetFacing: true,
      securityGroup: albSg,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      // loadBalancerName removed - let CDK generate unique name to avoid conflicts
    });

    // 🔹 3️⃣ Target Group for ECS service
    this.targetGroup = new elbv2.ApplicationTargetGroup(this, 'KestraTargetGroup', {
      vpc,
      port: 8080,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        path: '/api/v1/health',
        interval: Duration.seconds(30),
        timeout: Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 5,
      },
      deregistrationDelay: Duration.seconds(15),
      stickinessCookieDuration: Duration.minutes(5), // optional sticky sessions
    });

    // 🔹 4️⃣ HTTP Listener
    this.alb.addListener('HttpListener', {
      port: 80,
      open: true,
      defaultTargetGroups: [this.targetGroup],
    });

    // ⚠️ COMMENTED OUT: ECS Service moved to EcsServiceStack to avoid duplicate services
    // The ECS service is now created in EcsServiceStack, not here.
    // This stack only manages ALB infrastructure (ALB, Target Group, Security Groups).
    //
    // 🔹 5️⃣ ECS Service (COMMENTED - moved to EcsServiceStack)
    // const service = new ecs.Ec2Service(this, 'KestraService', {
    //   cluster,
    //   taskDefinition,
    //   desiredCount: 1,
    //   minHealthyPercent: 100,
    //   maxHealthyPercent: 200,
    //   securityGroups: [ecsServiceSg],
    //   vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
    // });
    //
    // // Attach the service to the target group
    // service.attachToApplicationTargetGroup(this.targetGroup);

    // 🔹 6️⃣ Outputs
    new CfnOutput(this, 'AlbDnsName', { value: this.alb.loadBalancerDnsName });
    new CfnOutput(this, 'AlbSecurityGroupId', { value: albSg.securityGroupId });
    new CfnOutput(this, 'EcsServiceSecurityGroupId', { value: ecsServiceSg.securityGroupId });
    // new CfnOutput(this, 'EcsServiceName', { value: service.serviceName }); // COMMENTED - service moved to EcsServiceStack
  }
}
