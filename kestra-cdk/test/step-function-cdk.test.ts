import { App } from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { StepFunctionsStack } from '../lib/step-function-stack';

test('StepFunctionsStack creates two Lambdas and two Step Functions', () => {
  const app = new App();
  const stack = new StepFunctionsStack(app, 'TestStack');
  const template = Template.fromStack(stack);

  // ✅ Check that two Lambda Functions exist
  template.resourceCountIs('AWS::Lambda::Function', 2);

  // ✅ Check that two Step Functions exist
  template.resourceCountIs('AWS::StepFunctions::StateMachine', 2);

  // ✅ Optionally verify the Lambda handler names
  template.hasResourceProperties('AWS::Lambda::Function', {
    Handler: 'index.handler',
    Runtime: 'nodejs20.x',
  });
});
