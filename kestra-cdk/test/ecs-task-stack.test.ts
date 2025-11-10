import { App } from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { EcsTaskStack } from '../lib/ecs-task-stack';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as efs from 'aws-cdk-lib/aws-efs';
import * as ecs from 'aws-cdk-lib/aws-ecs';

test('EcsTaskStack defines an ECS Task Definition', () => {
  const app = new App();

  // Minimal mocks for constructor props
  const vpc = new ec2.Vpc(app, 'Vpc');
  const cluster = new ecs.Cluster(app, 'Cluster', { vpc });
  const fileSystem = new efs.FileSystem(app, 'FileSystem', { vpc });
  const bucket = new s3.Bucket(app, 'Bucket');

  const stack = new EcsTaskStack(app, 'TestEcsTaskStack', {
    vpc,
    cluster,
    efsFileSystem: fileSystem,
    s3Bucket: bucket,
  });

  const template = Template.fromStack(stack);

  template.hasResourceProperties('AWS::ECS::TaskDefinition', {
    NetworkMode: 'awsvpc',
  });
});
