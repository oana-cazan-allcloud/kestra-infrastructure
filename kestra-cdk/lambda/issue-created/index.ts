// The AWS Lambda types are not resolving due to missing 'aws-lambda' module.
// Use a plain async function instead, and add a simple type for event if needed.

export const handler = async (event: any, p0: any, p1: () => null) => {
  console.log('🚀 Issue Created Event:', JSON.stringify(event, null, 2));

  // Example: Extract Jira issue key safely
  const issueKey = event?.issue?.key ?? 'unknown';

  // Simulated processing logic
  console.log(`Processing issue: ${issueKey}`);

  return {
    status: 'ok',
    action: 'issue_created',
    message: `Processed Jira issue ${issueKey}`,
    issueKey,
    timestamp: new Date().toISOString(),
  };
};
