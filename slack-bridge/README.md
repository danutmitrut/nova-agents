# Nova Cortex Slack Bridge

Optional Slack control channel for Nova Cortex.

The bridge uses Slack Socket Mode and the existing cortextOS file bus:

- Slack messages are forwarded to the target agent with `cortextos bus send-message`.
- Agent replies addressed to the bridge agent (`slack` by default) are read from the bus inbox and posted back to the originating Slack channel or thread.

This keeps Nova Cortex compatible with upstream cortextOS while adding Slack as an install-time option.

## Slack App Setup

Create a Slack app at <https://api.slack.com/apps>:

1. Enable **Socket Mode** and create an app-level token with `connections:write`. It starts with `xapp-`.
2. Add bot token scopes:
   - `app_mentions:read`
   - `channels:history`
   - `chat:write`
   - `files:read`
   - `im:history`
   - `im:read`
3. Subscribe to bot events:
   - `app_mention`
   - `message.channels`
   - `message.im`
4. Click **Reinstall to Workspace** after changing scopes or events.
5. Copy the bot token. It starts with `xoxb-`.

Optional later:

- Add `groups:history` only if you want the bridge in private channels.
- Add `mpim:history` only if you want the bridge in multi-person DMs.

For a dedicated control channel, set `SLACK_LISTEN_CHANNELS` to that channel ID and write normally:

```text
/onboarding
```

For other channels, mention the app explicitly. For direct messages, just message the app.

## Environment

```bash
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
NOVA_TARGET_AGENT=boss
NOVA_BRIDGE_AGENT=slack
CTX_ORG=nova-yourname
CTX_FRAMEWORK_ROOT=$HOME/cortextos
CTX_PROJECT_ROOT=$HOME/cortextos
CTX_INSTANCE_ID=default
```

Optional:

```bash
SLACK_ALLOWED_USER=U123456789
SLACK_DEFAULT_CHANNEL=C123456789
SLACK_LISTEN_CHANNELS=C123456789
SLACK_BRIDGE_STATE=$HOME/cortextos/slack-bridge-state.json
SLACK_MEDIA_DIR=$HOME/cortextos/orgs/nova-yourname/agents/boss/slack-media
SLACK_MAX_FILE_BYTES=104857600
```

## Media Files

When a Slack message includes images, documents, audio, or video, the bridge downloads each file with the bot token and stores it in `SLACK_MEDIA_DIR`.

By default, that folder is inside the target agent directory:

```text
$HOME/cortextos/orgs/<org>/agents/<target-agent>/slack-media
```

The agent receives a structured block like:

```text
[IMAGE]
file_name: screenshot.png
mime_type: image/png
size: 12345
local_file: slack-media/1710000000000-F123-screenshot.png
```

Agents should read the `local_file:` path directly from their working directory. File-only Slack messages are forwarded too, even when there is no text.

## Run

```bash
cd slack-bridge
npm install
npm start
```

With PM2:

```bash
pm2 start npm --name nova-slack-bridge -- start
pm2 save
```
