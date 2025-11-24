# Today RSS Release Announcer - Devvit App

This Devvit app automatically posts release announcements to r/TodayRSS when new versions are published on GitHub.

## What is Devvit?

Devvit is Reddit's platform for building apps that run directly on Reddit. Unlike the traditional Reddit API, Devvit apps:
- Don't require API credentials
- Run on Reddit's infrastructure
- Are easier to approve for subreddit moderators
- Can receive HTTP webhooks

## Setup Instructions

### 1. Install Devvit CLI

```bash
npm install -g devvit
```

### 2. Login to Reddit

```bash
devvit login
```

This will open a browser window to authenticate with Reddit.

### 3. Navigate to the Devvit App Directory

```bash
cd .github/devvit-app
```

### 4. Install Dependencies

```bash
npm install
```

### 5. Test the App Locally (Optional)

```bash
npm run dev
```

This starts a local development server where you can test the webhook.

### 6. Upload the App to Reddit

```bash
npm run upload
```

This uploads the app to Reddit's platform.

### 7. Install the App on r/TodayRSS

1. Go to https://developers.reddit.com/apps
2. Find "Today RSS Release Announcer"
3. Click "Install"
4. Select r/TodayRSS as the installation subreddit
5. Approve the permissions (submit posts)

### 8. Get the Webhook URL

After installing, Devvit will provide a webhook URL that looks like:
```
https://developers.reddit.com/v1/webhooks/YOUR_APP_ID/YOUR_INSTALLATION_ID
```

### 9. Add the Webhook URL to GitHub Secrets

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `DEVVIT_WEBHOOK_URL`
5. Value: The webhook URL from step 8
6. Click **Add secret**

## How It Works

1. You publish a release on GitHub
2. GitHub Actions sends a webhook to the Devvit app
3. The Devvit app receives the webhook
4. The app formats the release information
5. The app posts to r/TodayRSS using Reddit's API

## Webhook Payload Format

The GitHub Action sends this JSON payload:

```json
{
  "version": "v1.8.0",
  "name": "Reddit Improvements",
  "notes": "Release notes in markdown...",
  "url": "https://github.com/whyisjake/today/releases/tag/v1.8.0"
}
```

## Testing

To test the webhook locally:

```bash
curl -X POST http://localhost:3000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "version": "v1.0.0-test",
    "name": "Test Release",
    "notes": "This is a test release",
    "url": "https://github.com/whyisjake/today/releases/tag/v1.0.0-test"
  }'
```

## Troubleshooting

**App not showing up in developers.reddit.com:**
- Make sure you're logged in with the correct Reddit account
- Verify the upload completed successfully
- Check `devvit logs` for any errors

**Webhook returns 500 error:**
- Check the app logs: `devvit logs`
- Verify the JSON payload is properly formatted
- Ensure you have posting permissions on r/TodayRSS

**Post doesn't appear on r/TodayRSS:**
- Check Reddit's spam filters
- Verify the app is installed on the correct subreddit
- Check that the installation has "submit" permissions

## Updating the App

When you make changes to the code:

```bash
npm run upload
```

The app will be updated on Reddit's platform.

## Development Commands

- `npm run dev` - Start local development server
- `npm run build` - Build the TypeScript code
- `npm run upload` - Upload to Reddit

## File Structure

```
.github/devvit-app/
├── devvit.yaml       # App configuration
├── package.json      # Dependencies
├── src/
│   └── main.ts      # Main app code
└── README.md        # This file
```

## Advantages Over Traditional Reddit API

1. **No API Credentials Required** - No need to create a Reddit app or manage OAuth tokens
2. **Faster Approval** - Moderators can install apps without Reddit API approval
3. **Native Integration** - Runs directly on Reddit's platform
4. **Automatic Updates** - Push updates without redeploying
5. **Better Reliability** - Reddit hosts and maintains the infrastructure

## Support

For Devvit-specific questions:
- Devvit Docs: https://developers.reddit.com/docs
- Devvit Discord: https://discord.gg/devvit

For app-specific issues, file an issue on the GitHub repository.
