import { handler } from '../index';

describe('CommentCreated Lambda', () => {
  it('detects AI mentions correctly', async () => {
    const event = {
      comment: {
        body: 'Hey @ai-bot, check this out',
        author: { displayName: 'John Doe' },
      },
    };

    const result = await handler(event, {} as any, () => null);

    expect(result.status).toBe('ok');
    expect(result.mentioned).toBe(true);
    expect(result.author).toBe('John Doe');
  });
});
