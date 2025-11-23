#!/usr/bin/env python3
"""
Post GitHub release announcements to r/TodayRSS
"""

import os
import sys
import praw

def main():
    # Get environment variables
    client_id = os.environ.get('REDDIT_CLIENT_ID')
    client_secret = os.environ.get('REDDIT_CLIENT_SECRET')
    username = os.environ.get('REDDIT_USERNAME')
    password = os.environ.get('REDDIT_PASSWORD')

    release_tag = os.environ.get('RELEASE_TAG', 'Unknown Version')
    release_name = os.environ.get('RELEASE_NAME', 'New Release')
    release_body = os.environ.get('RELEASE_BODY', '')
    release_url = os.environ.get('RELEASE_URL', '')

    # Validate required credentials
    if not all([client_id, client_secret, username, password]):
        print("Error: Missing required Reddit API credentials")
        print("Please ensure REDDIT_CLIENT_ID, REDDIT_CLIENT_SECRET, REDDIT_USERNAME, and REDDIT_PASSWORD are set")
        sys.exit(1)

    try:
        # Initialize Reddit client
        reddit = praw.Reddit(
            client_id=client_id,
            client_secret=client_secret,
            username=username,
            password=password,
            user_agent=f"GitHub Actions Release Bot for Today RSS Reader by u/{username}"
        )

        # Create post title
        post_title = f"Today RSS Reader {release_tag} Released!"
        if release_name and release_name != release_tag:
            post_title = f"{release_name} ({release_tag})"

        # Create post body
        post_body = f"{release_body}\n\n"
        post_body += f"[View Release on GitHub]({release_url})\n\n"
        post_body += "---\n"
        post_body += "*This post was automatically generated from the GitHub release*"

        # Post to r/TodayRSS
        subreddit = reddit.subreddit('TodayRSS')
        submission = subreddit.submit(
            title=post_title,
            selftext=post_body
        )

        print(f"✅ Successfully posted to r/TodayRSS!")
        print(f"📝 Post title: {post_title}")
        print(f"🔗 Post URL: https://reddit.com{submission.permalink}")

    except praw.exceptions.PRAWException as e:
        print(f"❌ Reddit API error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
