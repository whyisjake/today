import { Devvit } from '@devvit/public-api';

// Configure Devvit
Devvit.configure({
  redditAPI: true,
});

// Define the feed recommendation form
const feedRecommendationForm = Devvit.createForm(
  {
    fields: [
      {
        name: 'feedName',
        label: 'Feed Name',
        type: 'string',
        required: true,
        helpText: 'The name of the RSS feed (e.g., "The Verge")',
      },
      {
        name: 'feedUrl',
        label: 'Feed URL',
        type: 'string',
        required: true,
        helpText: 'The RSS/Atom feed URL (must start with http:// or https://)',
      },
      {
        name: 'category',
        label: 'Category',
        type: 'select',
        required: true,
        options: [
          { label: '📰 News', value: 'news' },
          { label: '💻 Technology', value: 'tech' },
          { label: '🎮 Gaming', value: 'gaming' },
          { label: '⚽ Sports', value: 'sports' },
          { label: '🎬 Entertainment', value: 'entertainment' },
          { label: '💼 Business', value: 'business' },
          { label: '🔬 Science', value: 'science' },
          { label: '🎨 Design', value: 'design' },
          { label: '📱 Mobile', value: 'mobile' },
          { label: '🌍 World News', value: 'world' },
          { label: '🎧 Podcasts', value: 'podcasts' },
          { label: '📚 Blogs', value: 'blogs' },
          { label: '🔮 Other', value: 'other' },
        ],
      },
      {
        name: 'description',
        label: 'Why do you recommend this feed?',
        type: 'paragraph',
        required: true,
        helpText: 'Tell the community what makes this feed great!',
      },
    ],
    title: 'Recommend an RSS Feed',
    description: 'Share a great RSS feed with the Today community',
    acceptLabel: 'Submit Recommendation',
  },
  async (event, context) => {
    const { feedName, feedUrl, category, description } = event.values;

    // Validate URL format
    if (!feedUrl.startsWith('http://') && !feedUrl.startsWith('https://')) {
      context.ui.showToast('❌ Feed URL must start with http:// or https://');
      return;
    }

    // Get category emoji
    const categoryEmojis: Record<string, string> = {
      news: '📰',
      tech: '💻',
      gaming: '🎮',
      sports: '⚽',
      entertainment: '🎬',
      business: '💼',
      science: '🔬',
      design: '🎨',
      mobile: '📱',
      world: '🌍',
      podcasts: '🎧',
      blogs: '📚',
      other: '🔮',
    };

    const categoryLabels: Record<string, string> = {
      news: 'News',
      tech: 'Technology',
      gaming: 'Gaming',
      sports: 'Sports',
      entertainment: 'Entertainment',
      business: 'Business',
      science: 'Science',
      design: 'Design',
      mobile: 'Mobile',
      world: 'World News',
      podcasts: 'Podcasts',
      blogs: 'Blogs',
      other: 'Other',
    };

    const categoryEmoji = categoryEmojis[category] || '📡';
    const categoryLabel = categoryLabels[category] || 'Other';

    // Create post title
    const postTitle = `${categoryEmoji} Feed Recommendation: ${feedName}`;

    // Create formatted post body
    const postBody = `## ${feedName}

**Category:** ${categoryLabel}

**Feed URL:** ${feedUrl}

**Why I recommend it:**
${description}

---

*Want to add this feed to Today? Copy the feed URL above and add it in the app!*

*Have a feed to recommend? Click "Recommend RSS Feed" to share your favorite!*`;

    try {
      // Submit the post
      const subreddit = await context.reddit.getCurrentSubreddit();
      const post = await context.reddit.submitPost({
        title: postTitle,
        subredditName: subreddit.name,
        text: postBody,
      });

      // Add flair if configured
      try {
        await post.setFlair({
          text: '📰 Feed Recommendation',
        });
      } catch (flairError) {
        console.log('Could not set flair (may not be configured):', flairError);
      }

      context.ui.showToast({
        text: `✅ Feed recommendation posted!`,
        appearance: 'success',
      });

      // Navigate to the new post
      context.ui.navigateTo(post);
    } catch (error) {
      console.error('Error submitting feed recommendation:', error);
      context.ui.showToast({
        text: '❌ Failed to post recommendation. Please try again.',
        appearance: 'neutral',
      });
    }
  }
);

// Add menu action for users to submit feed recommendations
Devvit.addMenuItem({
  label: '📡 Recommend RSS Feed',
  location: 'subreddit',
  onPress: async (_event, context) => {
    context.ui.showForm(feedRecommendationForm);
  },
});

export default Devvit;
