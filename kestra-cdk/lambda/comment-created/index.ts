export const handler = async (event: any) => {
  console.log('💬 Comment Created Event:', JSON.stringify(event, null, 2));

  const comment = event.comment?.body ?? '';
  const author = event.comment?.author?.displayName ?? '';
  const mentionedAi = comment.includes('@ai-bot');

  if (mentionedAi) {
    console.log(`🤖 AI mention detected by ${author}`);
  } else {
    console.log(`No AI mention in comment by ${author}`);
  }

  return {
    status: 'ok',
    action: 'comment_created',
    mentioned: mentionedAi,
    author,
    timestamp: new Date().toISOString(),
  };
};
