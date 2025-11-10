import { App } from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { StepFunctionsStack } from '../lib/step-function-stack';

test('StepFunctionsStack defines two Lambdas and two State Machines', () => {
  const app = new App();
  const stack = new StepFunctionsStack(app, 'TestStack');
  const template = Template.fromStack(stack);

  template.resourceCountIs('AWS::Lambda::Function', 2);
  template.resourceCountIs('AWS::StepFunctions::StateMachine', 2);
});
