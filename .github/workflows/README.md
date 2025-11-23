# GitHub Actions Workflows

## Reddit Release Announcements

Automatically posts to [r/TodayRSS](https://www.reddit.com/r/TodayRSS/) when a new release is published on GitHub.

### Setup Instructions

#### 1. Create a Reddit App

1. Go to https://www.reddit.com/prefs/apps
2. Click "create another app..." at the bottom
3. Fill in the form:
   - **Name**: `Today RSS Release Bot` (or any name you prefer)
   - **App type**: Select "script"
   - **Description**: `Automated release announcements for Today RSS Reader`
   - **About URL**: `https://github.com/whyisjake/today`
   - **Redirect URI**: `http://localhost:8080` (required but not used for script apps)
4. Click "create app"
5. Note down:
   - **Client ID**: The string under the app name (looks like: `abc123def456`)
   - **Client Secret**: The "secret" value (click to reveal)

#### 2. Configure GitHub Secrets

Add the following secrets to your GitHub repository:

1. Go to your repository on GitHub
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** and add each of these:

| Secret Name | Description |
|------------|-------------|
| `REDDIT_CLIENT_ID` | The client ID from your Reddit app (e.g., `abc123def456`) |
| `REDDIT_CLIENT_SECRET` | The client secret from your Reddit app |
| `REDDIT_USERNAME` | Your Reddit username (without the u/ prefix) |
| `REDDIT_PASSWORD` | Your Reddit account password |

**Security Note**: These secrets are encrypted and only exposed to GitHub Actions. They are never visible in logs or accessible to anyone else.

#### 3. Test the Workflow

The workflow will automatically run when you publish a release. To test it:

1. Create and publish a new release on GitHub
2. Go to the **Actions** tab in your repository
3. Look for the "Post Release to Reddit" workflow
4. Verify it completed successfully
5. Check r/TodayRSS to see your post!

### Workflow Details

- **Trigger**: Runs automatically when a release is published
- **Posts to**: r/TodayRSS
- **Post Format**:
  - Title: Release name and version tag
  - Body: Release notes + link to GitHub release
  - Footer: Automated post attribution

### Troubleshooting

**Workflow fails with authentication error:**
- Double-check your Reddit credentials in GitHub Secrets
- Ensure your Reddit account has posting permissions on r/TodayRSS
- Verify the client ID and secret match your Reddit app

**Post doesn't appear:**
- Check if your account is approved to post on r/TodayRSS
- Verify you're a moderator/approved submitter for the subreddit
- Check Reddit's spam filters

**Want to customize the post format?**
- Edit `.github/scripts/post_to_reddit.py`
- Modify the `post_title` and `post_body` variables

### Manual Testing

To test the script locally (optional):

```bash
# Install dependencies
pip install praw

# Set environment variables
export REDDIT_CLIENT_ID="your_client_id"
export REDDIT_CLIENT_SECRET="your_client_secret"
export REDDIT_USERNAME="your_username"
export REDDIT_PASSWORD="your_password"
export RELEASE_TAG="v1.0.0"
export RELEASE_NAME="Test Release"
export RELEASE_BODY="This is a test release"
export RELEASE_URL="https://github.com/whyisjake/today/releases/tag/v1.0.0"

# Run the script
python .github/scripts/post_to_reddit.py
```
