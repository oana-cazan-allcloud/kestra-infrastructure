import {
  Stack,
  StackProps,
  Duration,
  aws_lambda as lambda,
  aws_stepfunctions as sfn,
  aws_stepfunctions_tasks as tasks,
  aws_iam as iam,
  CfnOutput,
} from 'aws-cdk-lib';
import { Construct } from 'constructs';

export class StepFunctionsStack extends Stack {
  readonly issueCreatedStateMachine: sfn.StateMachine;
  readonly commentCreatedStateMachine: sfn.StateMachine;

  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    //
    // 🔹 1️⃣ Shared IAM Role for Lambdas
    //
    const lambdaRole = new iam.Role(this, 'WorkflowLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName(
          'service-role/AWSLambdaBasicExecutionRole'
        ),
      ],
    });

    //
    // 🔹 2️⃣ Lambda: Issue Created Handler
    //
    const issueLambda = new lambda.Function(this, 'IssueCreatedHandler', {
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset('lambda/issue-created'),
      role: lambdaRole,
      timeout: Duration.seconds(60),
      environment: {
        LOG_LEVEL: 'info',
      },
    });

    //
    // 🔹 3️⃣ Lambda: Comment Created Handler
    //
    const commentLambda = new lambda.Function(this, 'CommentCreatedHandler', {
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset('lambda/comment-created'),
      role: lambdaRole,
      timeout: Duration.seconds(60),
      environment: {
        LOG_LEVEL: 'info',
      },
    });

    //
    // 🔹 4️⃣ Step Function: Issue Created Workflow
    //
    const issueWorkflow = new sfn.StateMachine(this, 'IssueCreatedWorkflow', {
      definition: new tasks.LambdaInvoke(this, 'ProcessIssueCreated', {
        lambdaFunction: issueLambda,
        outputPath: '$.Payload', // Return only Lambda result to Step Function
      }),
      timeout: Duration.minutes(5),
      stateMachineType: sfn.StateMachineType.STANDARD,
    });

    //
    // 🔹 5️⃣ Step Function: Comment Created Workflow
    //
    const commentWorkflow = new sfn.StateMachine(this, 'CommentCreatedWorkflow', {
      definition: new tasks.LambdaInvoke(this, 'ProcessCommentCreated', {
        lambdaFunction: commentLambda,
        outputPath: '$.Payload',
      }),
      timeout: Duration.minutes(5),
      stateMachineType: sfn.StateMachineType.STANDARD,
    });

    //
    // 🔹 6️⃣ Outputs (for Kestra configuration or ECS stack)
    //
    new CfnOutput(this, 'IssueCreatedStepFnArn', {
      value: issueWorkflow.stateMachineArn,
      exportName: 'IssueCreatedStepFnArn',
    });

    new CfnOutput(this, 'CommentCreatedStepFnArn', {
      value: commentWorkflow.stateMachineArn,
      exportName: 'CommentCreatedStepFnArn',
    });

    //
    // Expose references if other stacks need them
    //
    this.issueCreatedStateMachine = issueWorkflow;
    this.commentCreatedStateMachine = commentWorkflow;
  }
}
