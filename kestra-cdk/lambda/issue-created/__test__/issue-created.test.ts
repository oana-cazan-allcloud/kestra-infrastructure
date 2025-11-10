import { handler } from '../index';
import { describe, it, expect } from '@jest/globals';

describe('IssueCreated Lambda', () => {
  it('returns success payload and logs input', async () => {
    const event = { issue: { key: 'JIRA-123' } };

    const result = await handler(event, {} as any, () => null);

    expect(result.status).toBe('ok');
    expect(result.action).toBe('issue_created');
    expect(result.issueKey).toBe('JIRA-123');
  });
});
