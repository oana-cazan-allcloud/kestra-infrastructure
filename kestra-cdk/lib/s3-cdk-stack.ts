import {
    Stack,
    StackProps,
    aws_s3 as s3,
    aws_iam as iam,
    CfnOutput,
    Duration,
    RemovalPolicy,
  } from 'aws-cdk-lib';
  import { Construct } from 'constructs';
  
  interface S3StackProps extends StackProps {
    ecsTaskRoleArn?: string; // optional: restrict access to ECS task role
  }
  
  export class S3Stack extends Stack {
    readonly bucket: s3.Bucket;
  
    constructor(scope: Construct, id: string, props: S3StackProps) {
      super(scope, id, props);
  
      // 🧩 1️⃣ Create S3 bucket for Kestra storage
      this.bucket = new s3.Bucket(this, 'KestraInternalStorage', {
        bucketName: `kestra-internal-storage-${this.account}-${this.region}`,
        versioned: true, // ✅ enable versioning for data protection
        encryption: s3.BucketEncryption.S3_MANAGED, // ✅ SSE-S3 encryption
        blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL, // ✅ no public access
        enforceSSL: true,
        removalPolicy: RemovalPolicy.DESTROY, // auto-delete for dev; switch to RETAIN in prod
        autoDeleteObjects: true,
        lifecycleRules: [
          {
            id: 'ExpireOldObjects',
            expiration: Duration.days(31), // ✅ 30-day retention (adjust as needed)
            enabled: true,
          },
          {
            id: 'TransitionToIA',
            transitions: [
              {
                storageClass: s3.StorageClass.INFREQUENT_ACCESS,
                transitionAfter: Duration.days(60),
              },
            ],
            enabled: true,
          },
        ],
      });
  
      // 🧩 2️⃣ Optionally restrict access to ECS task role only
      if (props.ecsTaskRoleArn) {
        this.bucket.addToResourcePolicy(
          new iam.PolicyStatement({
            sid: 'AllowEcsTaskRoleAccess',
            actions: ['s3:*'],
            principals: [new iam.ArnPrincipal(props.ecsTaskRoleArn)],
            resources: [this.bucket.bucketArn, `${this.bucket.bucketArn}/*`],
          }),
        );
      }
  
      // 🧩 3️⃣ (Optional) Enable server access logging
      // For logging, you would need a separate target bucket
      // Uncomment below if you want to enable it:
      /*
      const logBucket = new s3.Bucket(this, 'KestraLogBucket', {
        encryption: s3.BucketEncryption.S3_MANAGED,
        blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
        enforceSSL: true,
        removalPolicy: RemovalPolicy.DESTROY,
        autoDeleteObjects: true,
      });
  
      this.bucket.addLifecycleRule({
        id: 'ExpireLogs',
        expiration: Duration.days(90),
        enabled: true,
      });
  
      this.bucket.addServerAccessLogsBucket(logBucket);
      */
  
      // 🧩 4️⃣ Outputs for reference
      new CfnOutput(this, 'BucketName', { value: this.bucket.bucketName });
      new CfnOutput(this, 'BucketArn', { value: this.bucket.bucketArn });
    }
  }
  