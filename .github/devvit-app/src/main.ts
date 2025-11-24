import { Devvit } from '@devvit/public-api';

// Configure Devvit
Devvit.configure({
  http: true,
  redditAPI: true,
});

// Define the webhook endpoint
Devvit.addTrigger({
  event: 'http',
  handler: async (request, context) => {
    // Verify this is a POST request
    if (request.method !== 'POST') {
      return {
        status: 405,
        body: JSON.stringify({ error: 'Method not allowed' }),
      };
    }

    try {
      // Parse the incoming webhook data from GitHub
      const payload = await request.json();

      const { version, name, notes, url } = payload;

      // Validate required fields
      if (!version || !url) {
        return {
          status: 400,
          body: JSON.stringify({ error: 'Missing required fields: version, url' }),
        };
      }

      // Create post title
      let postTitle = `Today RSS Reader ${version} Released!`;
      if (name && name !== version) {
        postTitle = `${name} (${version})`;
      }

      // Create post body with Markdown formatting
      let postBody = notes || '';
      postBody += `\n\n[View Release on GitHub](${url})\n\n`;
      postBody += '---\n';
      postBody += '*This post was automatically generated from the GitHub release*';

      // Post to r/TodayRSS
      const reddit = context.reddit;
      const submission = await reddit.submitPost({
        subredditName: 'TodayRSS',
        title: postTitle,
        text: postBody,
      });

      console.log(`✅ Successfully posted to r/TodayRSS: ${submission.id}`);

      return {
        status: 200,
        body: JSON.stringify({
          success: true,
          postId: submission.id,
          message: 'Release announcement posted successfully',
        }),
      };
    } catch (error) {
      console.error('❌ Error posting to Reddit:', error);

      return {
        status: 500,
        body: JSON.stringify({
          error: 'Failed to post to Reddit',
          details: error instanceof Error ? error.message : 'Unknown error',
        }),
      };
    }
  },
});

export default Devvit;
