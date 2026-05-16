#!/usr/bin/env node
const { App } = require('@slack/bolt');
const { execFile } = require('child_process');
const { existsSync, readFileSync, writeFileSync, mkdirSync } = require('fs');
const { dirname, join, relative } = require('path');
const os = require('os');

function loadDotEnv(filePath) {
  if (!existsSync(filePath)) return;
  const lines = readFileSync(filePath, 'utf-8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (!process.env[key]) process.env[key] = value;
  }
}

loadDotEnv(join(process.cwd(), '.env'));

const required = ['SLACK_BOT_TOKEN', 'SLACK_APP_TOKEN', 'CTX_ORG'];
for (const key of required) {
  if (!process.env[key]) {
    console.error(`[nova-slack-bridge] Missing required env var: ${key}`);
    process.exit(1);
  }
}

const targetAgent = process.env.NOVA_TARGET_AGENT || 'boss';
const bridgeAgent = process.env.NOVA_BRIDGE_AGENT || 'slack';
const allowedUser = process.env.SLACK_ALLOWED_USER || '';
const defaultChannel = process.env.SLACK_DEFAULT_CHANNEL || '';
const listenChannels = new Set(
  String(process.env.SLACK_LISTEN_CHANNELS || defaultChannel || '')
    .split(',')
    .map((channel) => channel.trim())
    .filter(Boolean)
);
const frameworkRoot = process.env.CTX_FRAMEWORK_ROOT || join(os.homedir(), 'cortextos');
const statePath = process.env.SLACK_BRIDGE_STATE ||
  join(frameworkRoot, 'slack-bridge-state.json');
const targetAgentDir = join(frameworkRoot, 'orgs', process.env.CTX_ORG, 'agents', targetAgent);
const mediaDir = process.env.SLACK_MEDIA_DIR || join(targetAgentDir, 'slack-media');
const maxFileBytes = Number(process.env.SLACK_MAX_FILE_BYTES || 100 * 1024 * 1024);

const busEnv = {
  ...process.env,
  CTX_AGENT_NAME: bridgeAgent,
  CTX_FRAMEWORK_ROOT: frameworkRoot,
  CTX_PROJECT_ROOT: process.env.CTX_PROJECT_ROOT || frameworkRoot,
  CTX_INSTANCE_ID: process.env.CTX_INSTANCE_ID || 'default',
};

function loadState() {
  if (!existsSync(statePath)) return { threads: {}, seen: {} };
  try {
    return JSON.parse(readFileSync(statePath, 'utf-8'));
  } catch {
    return { threads: {}, seen: {} };
  }
}

function saveState(next) {
  mkdirSync(dirname(statePath), { recursive: true });
  writeFileSync(statePath, JSON.stringify(next, null, 2));
}

let state = loadState();

function execCortextos(args) {
  return new Promise((resolve, reject) => {
    execFile('cortextos', args, { env: busEnv }, (error, stdout, stderr) => {
      if (error) {
        error.message += `\n${stderr || ''}`;
        reject(error);
        return;
      }
      resolve(stdout.trim());
    });
  });
}

function cleanSlackText(text) {
  return String(text || '')
    .replace(/<@[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .trim();
}

function sanitizeFilename(value) {
  return String(value || 'slack-file')
    .replace(/[/\\?%*:|"<>]/g, '-')
    .replace(/\s+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 140) || 'slack-file';
}

function classifySlackFile(file) {
  const mimetype = String(file.mimetype || '');
  if (mimetype.startsWith('image/')) return 'IMAGE';
  if (mimetype.startsWith('audio/')) return 'AUDIO';
  if (mimetype.startsWith('video/')) return 'VIDEO';
  return 'DOCUMENT';
}

async function downloadSlackFiles(files = []) {
  if (!files.length) return [];
  mkdirSync(mediaDir, { recursive: true });

  const downloaded = [];
  for (const file of files) {
    const size = Number(file.size || 0);
    const originalName = file.name || file.title || `${file.id || 'slack-file'}.${file.filetype || 'bin'}`;
    const safeName = `${Date.now()}-${sanitizeFilename(file.id)}-${sanitizeFilename(originalName)}`;
    const absolutePath = join(mediaDir, safeName);
    const localFile = relative(targetAgentDir, absolutePath);
    const item = {
      type: classifySlackFile(file),
      id: file.id,
      name: originalName,
      mimetype: file.mimetype || file.filetype || 'unknown',
      size,
      localFile,
    };

    if (size > maxFileBytes) {
      downloaded.push({ ...item, skipped: `file is larger than SLACK_MAX_FILE_BYTES (${maxFileBytes})` });
      continue;
    }

    const url = file.url_private_download || file.url_private;
    if (!url) {
      downloaded.push({ ...item, skipped: 'missing Slack private download URL' });
      continue;
    }

    try {
      const response = await fetch(url, {
        headers: { Authorization: `Bearer ${process.env.SLACK_BOT_TOKEN}` },
      });
      if (!response.ok) throw new Error(`Slack download failed: ${response.status} ${response.statusText}`);
      const buffer = Buffer.from(await response.arrayBuffer());
      writeFileSync(absolutePath, buffer);
      downloaded.push(item);
    } catch (err) {
      downloaded.push({ ...item, error: err.message });
    }
  }
  return downloaded;
}

function formatFiles(downloadedFiles) {
  if (!downloadedFiles.length) return '';
  return downloadedFiles.map((file) => {
    const lines = [
      `[${file.type}]`,
      `file_name: ${file.name}`,
      `mime_type: ${file.mimetype}`,
      `size: ${file.size}`,
    ];
    if (file.localFile && !file.skipped && !file.error) lines.push(`local_file: ${file.localFile}`);
    if (file.skipped) lines.push(`download_skipped: ${file.skipped}`);
    if (file.error) lines.push(`download_error: ${file.error}`);
    return lines.join('\n');
  }).join('\n\n');
}

async function forwardToAgent({ text, files, channel, threadTs, user, source }) {
  const cleaned = cleanSlackText(text);
  const downloadedFiles = await downloadSlackFiles(files || []);
  if (!cleaned && downloadedFiles.length === 0) return;

  const message = [
    `=== SLACK MESSAGE from ${user || 'unknown'} in ${channel}${threadTs ? ` thread ${threadTs}` : ''} ===`,
    cleaned || '(no text)',
    formatFiles(downloadedFiles),
    `Reply using: cortextos bus send-message ${bridgeAgent} normal '<your reply>'`,
  ].filter(Boolean).join('\n');

  const msgId = await execCortextos(['bus', 'send-message', targetAgent, 'normal', message]);
  state.threads[msgId] = {
    channel,
    threadTs: threadTs || undefined,
    user,
    source,
    createdAt: new Date().toISOString(),
  };
  saveState(state);
  return msgId;
}

function resolveReplyTarget(msg) {
  if (msg.reply_to && state.threads[msg.reply_to]) {
    return state.threads[msg.reply_to];
  }
  const keys = Object.keys(state.threads);
  if (keys.length > 0) {
    return state.threads[keys[keys.length - 1]];
  }
  if (defaultChannel) return { channel: defaultChannel };
  return null;
}

async function pollBridgeInbox(app) {
  try {
    const raw = await execCortextos(['bus', 'check-inbox']);
    const messages = raw ? JSON.parse(raw) : [];
    for (const msg of messages) {
      if (state.seen[msg.id]) {
        await execCortextos(['bus', 'ack-inbox', msg.id]);
        continue;
      }

      const target = resolveReplyTarget(msg);
      if (!target) {
        console.warn(`[nova-slack-bridge] No Slack target for reply ${msg.id}`);
        await execCortextos(['bus', 'ack-inbox', msg.id]);
        continue;
      }

      await app.client.chat.postMessage({
        token: process.env.SLACK_BOT_TOKEN,
        channel: target.channel,
        thread_ts: target.threadTs,
        text: msg.text,
      });

      state.seen[msg.id] = new Date().toISOString();
      saveState(state);
      await execCortextos(['bus', 'ack-inbox', msg.id]);
    }
  } catch (err) {
    console.error(`[nova-slack-bridge] inbox poll failed: ${err.message}`);
  }
}

const app = new App({
  token: process.env.SLACK_BOT_TOKEN,
  appToken: process.env.SLACK_APP_TOKEN,
  socketMode: true,
});

app.event('app_mention', async ({ event, say }) => {
  console.log(`[nova-slack-bridge] app_mention user=${event.user} channel=${event.channel} ts=${event.ts} files=${event.files?.length || 0}`);
  if (allowedUser && event.user !== allowedUser) {
    console.log(`[nova-slack-bridge] ignored app_mention from user=${event.user}; expected ${allowedUser}`);
    return;
  }
  try {
    await forwardToAgent({
      text: event.text,
      files: event.files || [],
      channel: event.channel,
      threadTs: undefined,
      user: event.user,
      source: 'app_mention',
    });
  } catch (err) {
    console.error(`[nova-slack-bridge] app_mention failed: ${err.message}`);
  }
});

app.message(async ({ message, say }) => {
  console.log(`[nova-slack-bridge] message subtype=${message.subtype || 'none'} user=${message.user} channel=${message.channel} channel_type=${message.channel_type} files=${message.files?.length || 0}`);
  if (message.bot_id) {
    console.log('[nova-slack-bridge] ignored bot message');
    return;
  }
  if (message.subtype && message.subtype !== 'file_share') {
    console.log(`[nova-slack-bridge] ignored subtype=${message.subtype}`);
    return;
  }
  if (allowedUser && message.user !== allowedUser) {
    console.log(`[nova-slack-bridge] ignored message from user=${message.user}; expected ${allowedUser}`);
    return;
  }
  if (message.channel_type !== 'im' && !listenChannels.has(message.channel)) {
    console.log(`[nova-slack-bridge] ignored non-DM message outside listen channels; channel=${message.channel} channel_type=${message.channel_type}`);
    return;
  }

  try {
    await forwardToAgent({
      text: message.text,
      files: message.files || [],
      channel: message.channel,
      threadTs: message.channel_type === 'im' ? (message.thread_ts || message.ts) : undefined,
      user: message.user,
      source: message.channel_type === 'im' ? 'dm' : 'channel_message',
    });
  } catch (err) {
    console.error(`[nova-slack-bridge] dm failed: ${err.message}`);
  }
});

(async () => {
  await app.start();
  console.log(`[nova-slack-bridge] running. Slack -> ${targetAgent}, replies via ${bridgeAgent}`);
  setInterval(() => pollBridgeInbox(app), 1500);
})();
