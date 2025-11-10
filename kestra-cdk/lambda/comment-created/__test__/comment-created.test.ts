import { describe, it, expect } from '@jest/globals';
import { handler } from '../index';

describe('CommentCreated Lambda', () => {
  it('returns success payload and logs input', async () => {
    const event = { comment: { body: 'Hey @ai-bot, check this out', author: { displayName: 'John Doe' } } };

    const result = await handler(event);

    expect(result.status).toBe('ok');
    expect(result.action).toBe('comment_created');
    expect(result.mentioned).toBe(true);
    expect(result.author).toBe('John Doe');
  });
});
