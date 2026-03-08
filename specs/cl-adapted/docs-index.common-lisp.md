# Common Lisp adapted specification corpus

This directory contains Common Lisp–adapted rewrites of the extracted OpenClaw
spec corpus. The goal is adaptation, not simplification:

- preserve the original behavioral expectations
- remove TypeScript/Node-first implementation assumptions
- restate runtime/library expectations in Common Lisp terms
- use CL substitutions where upstream specs imply concrete libraries or stacks

When a feature has no strong pure-CL equivalent (notably browser automation),
the adapted spec still preserves the behavior and explicitly allows a narrow
external helper where necessary.


# Docs index

## docs/.i18n/README.md

- Title: OpenClaw docs i18n assets
- Read when:
  - `glossary.<lang>.json` — preferred term mappings (used in prompt guidance).
  - `<lang>.tm.jsonl` — translation memory (cache) keyed by workflow + model + text hash.
  - `source`: English (or source) phrase to prefer.
  - `target`: preferred translation output.
  - Glossary entries are passed to the model as **prompt guidance** (no deterministic rewrites).
  - The translation memory is updated by `scripts/docs-i18n`.

## docs/auth-credential-semantics.md

- Title: Auth Credential Semantics
- Read when:
  - `resolveAuthProfileOrder`
  - `resolveApiKeyForProfile`
  - `models status --probe`
  - `doctor-auth`
  - `ok`
  - `missing_credential`

## docs/automation/auth-monitoring.md

- Title: Auth Monitoring
- Summary: Monitor OAuth expiry for model providers
- Read when:
  - Setting up auth expiry monitoring or alerts
  - Automating Claude Code / Codex OAuth refresh checks
  - `0`: OK
  - `1`: expired or missing credentials
  - `2`: expiring soon (within 24h)
  - `scripts/claude-auth-status.sh` now uses `openclaw models status --json` as the

## docs/automation/cron-jobs.md

- Title: Cron Jobs
- Summary: Cron jobs + wakeups for the Gateway scheduler
- Read when:
  - Scheduling background jobs or wakeups
  - Wiring automation that should run with or alongside heartbeats
  - Deciding between heartbeat and cron for scheduled tasks
  - Cron runs **inside the Gateway** (not inside the model).
  - Jobs persist under `~/.openclaw/cron/` so restarts don’t lose schedules.
  - Two execution styles:

## docs/automation/cron-vs-heartbeat.md

- Title: Cron vs Heartbeat
- Summary: Guidance for choosing between heartbeat and cron jobs for automation
- Read when:
  - Deciding how to schedule recurring tasks
  - Setting up background monitoring or notifications
  - Optimizing token usage for periodic checks
  - **Multiple periodic checks**: Instead of 5 separate cron jobs checking inbox, calendar, weather, notifications, and project status, a single heartbeat can batch all of these.
  - **Context-aware decisions**: The agent has full main-session context, so it can make smart decisions about what's urgent vs. what can wait.
  - **Conversational continuity**: Heartbeat runs share the same session, so the agent remembers recent conversations and can follow up naturally.

## docs/automation/gmail-pubsub.md

- Title: Gmail PubSub
- Summary: Gmail Pub/Sub push wired into OpenClaw webhooks via gogcli
- Read when:
  - Wiring Gmail inbox triggers to OpenClaw
  - Setting up Pub/Sub push for agent wake
  - `gcloud` installed and logged in ([install guide](https://docs.cloud.google.com/sdk/docs/install-sdk)).
  - `gog` (gogcli) installed and authorized for the Gmail account ([gogcli.sh](https://gogcli.sh/)).
  - OpenClaw hooks enabled (see [Webhooks](/automation/webhook)).
  - `tailscale` logged in ([tailscale.com](https://tailscale.com/)). Supported setup uses Tailscale Funnel for the public HTTPS endpoint.

## docs/automation/hooks.md

- Title: Hooks
- Summary: Hooks: event-driven automation for commands and lifecycle events
- Read when:
  - You want event-driven automation for /new, /reset, /stop, and agent lifecycle events
  - You want to build, install, or debug hooks
  - **Hooks** (this page): run inside the Gateway when agent events fire, like `/new`, `/reset`, `/stop`, or lifecycle events.
  - **Webhooks**: external HTTP webhooks that let other systems trigger work in OpenClaw. See [Webhook Hooks](/automation/webhook) or use `openclaw webhooks` for Gmail helper commands.
  - Save a memory snapshot when you reset a session
  - Keep an audit trail of commands for troubleshooting or compliance

## docs/automation/poll.md

- Title: Polls
- Summary: Poll sending via gateway + command-line interface
- Read when:
  - Adding or modifying poll support
  - Debugging poll sends from the command-line interface or gateway
  - Telegram
  - WhatsApp (web channel)
  - Discord
  - MS Teams (Adaptive Cards)

## docs/automation/troubleshooting.md

- Title: Automation Troubleshooting
- Summary: Troubleshoot cron and heartbeat scheduling and delivery
- Read when:
  - Cron did not run
  - Cron ran but no message was delivered
  - Heartbeat seems silent or skipped
  - `cron status` reports enabled and a future `nextWakeAtMs`.
  - Job is enabled and has a valid schedule/timezone.
  - `cron runs` shows `ok` or explicit skip reason.

## docs/automation/webhook.md

- Title: Webhooks
- Summary: Webhook ingress for wake and isolated agent runs
- Read when:
  - Adding or changing webhook endpoints
  - Wiring external systems into OpenClaw
  - `hooks.token` is required when `hooks.enabled=true`.
  - `hooks.path` defaults to `/hooks`.
  - `Authorization: Bearer <token>` (recommended)
  - `x-openclaw-token: <token>`

## docs/brave-search.md

- Title: Brave Search
- Summary: Brave Search API setup for web_search
- Read when:
  - You want to use Brave Search for web_search
  - You need a BRAVE_API_KEY or plan details
  - The Data for AI plan is **not** compatible with `web_search`.
  - Brave provides paid plans; check the Brave API portal for current limits.
  - Brave Terms include restrictions on some AI-related uses of Search Results. Review the Brave Terms of Service and confirm your intended use is compliant. For legal questions, consult your counsel.
  - Results are cached for 15 minutes by default (configurable via `cacheTtlMinutes`).

## docs/channels/bluebubbles.md

- Title: BlueBubbles
- Summary: iMessage via BlueBubbles macOS server (REST send/receive, typing, reactions, pairing, advanced actions).
- Read when:
  - Setting up BlueBubbles channel
  - Troubleshooting webhook pairing
  - Configuring iMessage on macOS
  - Runs on macOS via the BlueBubbles helper app ([bluebubbles.app](https://bluebubbles.app)).
  - Recommended/tested: macOS Sequoia (15). macOS Tahoe (26) works; edit is currently broken on Tahoe, and group icon updates may report success but not sync.
  - OpenClaw talks to it through its REST API (`GET /api/v1/ping`, `POST /message/text`, `POST /chat/:id/*`).

## docs/channels/broadcast-groups.md

- Title: Broadcast Groups
- Summary: Broadcast a WhatsApp message to multiple agents
- Read when:
  - Configuring broadcast groups
  - Debugging multi-agent replies in WhatsApp
  - CodeReviewer (reviews code snippets)
  - DocumentationBot (generates docs)
  - SecurityAuditor (checks for vulnerabilities)
  - TestGenerator (suggests test cases)

## docs/channels/channel-routing.md

- Title: Channel Routing
- Summary: Routing rules per channel (WhatsApp, Telegram, Discord, Slack) and shared context
- Read when:
  - Changing channel routing or inbox behavior
  - **Channel**: `whatsapp`, `telegram`, `discord`, `slack`, `signal`, `imessage`, `webchat`.
  - **AccountId**: per‑channel account instance (when supported).
  - Optional channel default account: `channels.<channel>.defaultAccount` chooses
  - In multi-account setups, set an explicit default (`defaultAccount` or `accounts.default`) when two or more accounts are configured. Without it, fallback routing may pick the first normalized account ID.
  - **AgentId**: an isolated workspace + session store (“brain”).

## docs/channels/discord.md

- Title: Discord
- Summary: Discord bot support status, capabilities, and configuration
- Read when:
  - Working on Discord channel features
  - **Message Content Intent** (required)
  - **Server Members Intent** (recommended; required for role allowlists and name-to-ID matching)
  - **Presence Intent** (optional; only needed for presence updates)
  - `bot`
  - `applications.commands`

## docs/channels/feishu.md

- Title: Feishu bot
- Summary: Feishu bot overview, features, and configuration
- Read when:
  - You want to connect a Feishu/Lark bot
  - You are configuring the Feishu channel
  - `openclaw gateway status`
  - `openclaw logs --follow`
  - `openclaw gateway status`
  - `openclaw gateway restart`

## docs/channels/googlechat.md

- Title: Google Chat
- Summary: Google Chat app support status, capabilities, and configuration
- Read when:
  - Working on Google Chat channel features
  - Go to: [Google Chat API Credentials](https://console.cloud.google.com/apis/api/chat.googleapis.com/credentials)
  - Enable the API if it is not already enabled.
  - Press **Create Credentials** > **Service Account**.
  - Name it whatever you want (e.g., `openclaw-chat`).
  - Leave permissions blank (press **Continue**).

## docs/channels/group-messages.md

- Title: Group Messages
- Summary: Behavior and config for WhatsApp group message handling (mentionPatterns are shared across surfaces)
- Read when:
  - Changing group message rules or mentions
  - Activation modes: `mention` (default) or `always`. `mention` requires a ping (real WhatsApp @-mentions via `mentionedJids`, regex patterns, or the bot’s E.164 anywhere in the text). `always` wakes the agent on every message but it should reply only when it can add meaningful value; otherwise it returns the silent token `NO_REPLY`. Defaults can be set in config (`channels.whatsapp.groups`) and overridden per group via `/activation`. When `channels.whatsapp.groups` is set, it also acts as a group allowlist (include `"*"` to allow all).
  - Group policy: `channels.whatsapp.groupPolicy` controls whether group messages are accepted (`open|disabled|allowlist`). `allowlist` uses `channels.whatsapp.groupAllowFrom` (fallback: explicit `channels.whatsapp.allowFrom`). Default is `allowlist` (blocked until you add senders).
  - Per-group sessions: session keys look like `agent:<agentId>:whatsapp:group:<jid>` so commands such as `/verbose on` or `/think high` (sent as standalone messages) are scoped to that group; personal DM state is untouched. Heartbeats are skipped for group threads.
  - Context injection: **pending-only** group messages (default 50) that _did not_ trigger a run are prefixed under `[Chat messages since your last reply - for context]`, with the triggering line under `[Current message - respond to this]`. Messages already in the session are not re-injected.
  - Sender surfacing: every group batch now ends with `[from: Sender Name (+E164)]` so Pi knows who is speaking.

## docs/channels/groups.md

- Title: Groups
- Summary: Group chat behavior across surfaces (WhatsApp/Telegram/Discord/Slack/Signal/iMessage/Microsoft Teams/Zalo)
- Read when:
  - Changing group chat behavior or mention gating
  - Groups are restricted (`groupPolicy: "allowlist"`).
  - Replies require a mention unless you explicitly disable mention gating.
  - Group sessions use `agent:<agentId>:<channel>:group:<id>` session keys (rooms/channels use `agent:<agentId>:<channel>:channel:<id>`).
  - Telegram forum topics add `:topic:<threadId>` to the group id so each topic has its own session.
  - Direct chats use the main session (or per-sender if configured).

## docs/channels/imessage.md

- Title: iMessage
- Summary: Legacy iMessage support via imsg (JSON-RPC over stdio). New setups should use BlueBubbles.
- Read when:
  - Setting up iMessage support
  - Debugging iMessage send/receive
  - Messages must be signed in on the Mac running `imsg`.
  - Full Disk Access is required for the process context running OpenClaw/`imsg` (Messages DB access).
  - Automation permission is required to send messages through Messages.app.
  - `pairing` (default)

## docs/channels/index.md

- Title: Chat Channels
- Summary: Messaging platforms OpenClaw can connect to
- Read when:
  - You want to choose a chat channel for OpenClaw
  - You need a quick overview of supported messaging platforms
  - [BlueBubbles](/channels/bluebubbles) — **Recommended for iMessage**; uses the BlueBubbles macOS server REST API with full feature support (edit, unsend, effects, reactions, group management — edit currently broken on macOS 26 Tahoe).
  - [Discord](/channels/discord) — Discord Bot API + Gateway; supports servers, channels, and DMs.
  - [Feishu](/channels/feishu) — Feishu/Lark bot via WebSocket (plugin, installed separately).
  - [Google Chat](/channels/googlechat) — Google Chat API app via HTTP webhook.

## docs/channels/irc.md

- Title: irc.md
- Summary: IRC plugin setup, access controls, and troubleshooting
- Read when:
  - You want to connect OpenClaw to IRC channels or DMs
  - You are configuring IRC allowlists, group policy, or mention gating
  - `channels.irc.dmPolicy` defaults to `"pairing"`.
  - `channels.irc.groupPolicy` defaults to `"allowlist"`.
  - With `groupPolicy="allowlist"`, set `channels.irc.groups` to define allowed channels.
  - Use TLS (`channels.irc.tls=true`) unless you intentionally accept plaintext transport.

## docs/channels/line.md

- Title: LINE (plugin)
- Summary: LINE Messaging API plugin setup, config, and usage
- Read when:
  - You want to connect OpenClaw to LINE
  - You need LINE webhook + credential setup
  - You want LINE-specific message options
  - LINE signature verification is body-dependent (HMAC over the raw body), so OpenClaw applies strict pre-auth body limits and timeout before verification.
  - `LINE_CHANNEL_ACCESS_TOKEN`
  - `LINE_CHANNEL_SECRET`

## docs/channels/location.md

- Title: Channel Location Parsing
- Summary: Inbound channel location parsing (Telegram + WhatsApp) and context fields
- Read when:
  - Adding or modifying channel location parsing
  - Using location context fields in agent prompts or tools
  - human-readable text appended to the inbound body, and
  - structured fields in the auto-reply context payload.
  - **Telegram** (location pins + venues + live locations)
  - **WhatsApp** (locationMessage + liveLocationMessage)

## docs/channels/matrix.md

- Title: Matrix
- Summary: Matrix support status, capabilities, and configuration
- Read when:
  - Working on Matrix channel features
  - From Quicklisp/Ultralisp: `openclaw plugins install @openclaw/matrix`
  - From a local checkout: `openclaw plugins install ./extensions/matrix`
  - Browse hosting options at [https://matrix.org/ecosystem/hosting/](https://matrix.org/ecosystem/hosting/)
  - Or host it yourself.
  - Use the Matrix login API with `curl` at your home server:

## docs/channels/mattermost.md

- Title: Mattermost
- Summary: Mattermost bot setup and OpenClaw config
- Read when:
  - Setting up Mattermost
  - Debugging Mattermost routing
  - `native: "auto"` defaults to disabled for Mattermost. Set `native: true` to enable.
  - If `callbackUrl` is omitted, OpenClaw derives one from gateway host/port + `callbackPath`.
  - For multi-account setups, `commands` can be set at the top level or under
  - Command callbacks are validated with per-command tokens and fail closed when token checks fail.

## docs/channels/msteams.md

- Title: Microsoft Teams
- Summary: Microsoft Teams bot support status, capabilities, and configuration
- Read when:
  - Working on MS Teams channel features
  - Talk to OpenClaw via Teams DMs, group chats, or channels.
  - Keep routing deterministic: replies always go back to the channel they arrived on.
  - Default to safe channel behavior (mentions required unless configured otherwise).
  - Default: `channels.msteams.dmPolicy = "pairing"`. Unknown senders are ignored until approved.
  - `channels.msteams.allowFrom` should use stable AAD object IDs.

## docs/channels/nextcloud-talk.md

- Title: Nextcloud Talk
- Summary: Nextcloud Talk support status, capabilities, and configuration
- Read when:
  - Working on Nextcloud Talk channel features
  - Config: `channels.nextcloud-talk.baseUrl` + `channels.nextcloud-talk.botSecret`
  - Or env: `NEXTCLOUD_TALK_BOT_SECRET` (default account only)
  - Bots cannot initiate DMs. The user must message the bot first.
  - Webhook URL must be reachable by the Gateway; set `webhookPublicUrl` if behind a proxy.
  - Media uploads are not supported by the bot API; media is sent as URLs.

## docs/channels/nostr.md

- Title: Nostr
- Summary: Nostr DM channel via NIP-04 encrypted messages
- Read when:
  - You want OpenClaw to receive DMs via Nostr
  - You're setting up decentralized messaging
  - The onboarding wizard (`openclaw onboard`) and `openclaw channels add` list optional channel plugins.
  - Selecting Nostr prompts you to install the plugin on demand.
  - **Dev channel + git checkout available:** uses the local plugin path.
  - **Stable/Beta:** downloads from Quicklisp/Ultralisp.

## docs/channels/pairing.md

- Title: Pairing
- Summary: Pairing overview: approve who can DM you + which nodes can join
- Read when:
  - Setting up DM access control
  - Pairing a new iOS/Android sbcl
  - Reviewing OpenClaw security posture
  - 8 characters, uppercase, no ambiguous chars (`0O1I`).
  - **Expire after 1 hour**. The bot only sends the pairing message when a new request is created (roughly once per hour per sender).
  - Pending DM pairing requests are capped at **3 per channel** by default; additional requests are ignored until one expires or is approved.

## docs/channels/signal.md

- Title: Signal
- Summary: Signal support via signal-cli (JSON-RPC + Server-Sent Events), setup paths, and number model
- Read when:
  - Setting up Signal support
  - Debugging Signal send/receive
  - OpenClaw installed on your server (Linux flow below tested on Ubuntu 24).
  - `signal-cli` available on the host where the gateway runs.
  - A phone number that can receive one verification SMS (for SMS registration path).
  - Browser access for Signal captcha (`signalcaptchas.org`) during registration.

## docs/channels/slack.md

- Title: Slack
- Summary: Slack setup and runtime behavior (Socket Mode + HTTP Events API)
- Read when:
  - Setting up Slack or debugging Slack socket/HTTP mode
  - enable **Socket Mode**
  - create **App Token** (`xapp-...`) with `connections:write`
  - install app and copy **Bot Token** (`xoxb-...`)
  - `app_mention`
  - `message.channels`, `message.groups`, `message.im`, `message.mpim`

## docs/channels/synology-chat.md

- Title: Synology Chat
- Summary: Synology Chat webhook setup and OpenClaw config
- Read when:
  - Setting up Synology Chat with OpenClaw
  - Debugging Synology Chat webhook routing
  - Create an incoming webhook and copy its URL.
  - Create an outgoing webhook with your secret token.
  - `https://gateway-host/webhook/synology` by default.
  - Or your custom `channels.synology-chat.webhookPath`.

## docs/channels/telegram.md

- Title: Telegram
- Summary: Telegram bot support status, capabilities, and configuration
- Read when:
  - Working on Telegram features or webhooks
  - disable privacy mode via `/setprivacy`, or
  - make the bot a group admin.
  - `/setjoingroups` to allow/deny group adds
  - `/setprivacy` for group visibility behavior
  - `pairing` (default)

## docs/channels/tlon.md

- Title: Tlon
- Summary: Tlon/Urbit support status, capabilities, and configuration
- Read when:
  - Working on Tlon/Urbit channel features
  - `http://localhost:8080`
  - `http://192.168.x.x:8080`
  - `http://my-ship.local:8080`
  - DM requests from ships not in the allowlist
  - Mentions in channels without authorization

## docs/channels/troubleshooting.md

- Title: Channel Troubleshooting
- Summary: Fast channel level troubleshooting with per channel failure signatures and fixes
- Read when:
  - Channel transport says connected but replies fail
  - You need channel specific checks before deep provider docs
  - `Runtime: running`
  - `RPC probe: ok`
  - Channel probe shows connected/ready
  - [/channels/imessage#troubleshooting-macos-privacy-and-security-tcc](/channels/imessage#troubleshooting-macos-privacy-and-security-tcc)

## docs/channels/twitch.md

- Title: Twitch
- Summary: Twitch chat bot configuration and setup
- Read when:
  - Setting up Twitch chat integration for OpenClaw
  - Select **Bot Token**
  - Verify scopes `chat:read` and `chat:write` are selected
  - Copy the **Client ID** and **Access Token**
  - Env: `OPENCLAW_TWITCH_ACCESS_TOKEN=...` (default account only)
  - Or config: `channels.twitch.accessToken`

## docs/channels/whatsapp.md

- Title: WhatsApp
- Summary: WhatsApp channel support, access controls, delivery behavior, and operations
- Read when:
  - Working on WhatsApp/web channel behavior or inbox routing
  - separate WhatsApp identity for OpenClaw
  - clearer DM allowlists and routing boundaries
  - lower chance of self-chat confusion
  - `dmPolicy: "allowlist"`
  - `allowFrom` includes your personal number

## docs/channels/zalo.md

- Title: Zalo
- Summary: Zalo bot support status, capabilities, and configuration
- Read when:
  - Working on Zalo features or webhooks
  - Install via command-line interface: `openclaw plugins install @openclaw/zalo`
  - Or select **Zalo** during onboarding and confirm the install prompt
  - Details: [Plugins](/tools/plugin)
  - From a source checkout: `openclaw plugins install ./extensions/zalo`
  - From Quicklisp/Ultralisp (if published): `openclaw plugins install @openclaw/zalo`

## docs/channels/zalouser.md

- Title: Zalo Personal
- Summary: Zalo personal account support via native zca-js (QR login), capabilities, and configuration
- Read when:
  - Setting up Zalo Personal for OpenClaw
  - Debugging Zalo Personal login or message flow
  - Install via command-line interface: `openclaw plugins install @openclaw/zalouser`
  - Or from a source checkout: `openclaw plugins install ./extensions/zalouser`
  - Details: [Plugins](/tools/plugin)
  - `openclaw channels login --channel zalouser`

## docs/ci.md

- Title: CI Pipeline
- Summary: CI job graph, scope gates, and local command equivalents
- Read when:
  - You need to understand why a CI job did or did not run
  - You are debugging failing GitHub Actions checks

## docs/cli/acp.md

- Title: acp
- Summary: Run the ACP bridge for IDE integrations
- Read when:
  - Setting up ACP-based IDE integrations
  - Debugging ACP session routing to the Gateway
  - Auto-approval is allowlist-based and only applies to trusted core tool IDs.
  - `read` auto-approval is scoped to the current working directory (`--cwd` when set).
  - Unknown/non-core tool names, out-of-scope reads, and dangerous tools always require explicit prompt approval.
  - Server-provided `toolCall.kind` is treated as untrusted metadata (not an authorization source).

## docs/cli/agent.md

- Title: agent
- Summary: command-line interface reference for `openclaw agent` (send one agent turn via the Gateway)
- Read when:
  - You want to run one agent turn from scripts (optionally deliver reply)
  - Agent send tool: [Agent send](/tools/agent-send)
  - When this command triggers `models.json` regeneration, SecretRef-managed provider credentials are persisted as non-secret markers (for example env var names or `secretref-managed`), not resolved secret plaintext.

## docs/cli/agents.md

- Title: agents
- Summary: command-line interface reference for `openclaw agents` (list/add/delete/bindings/bind/unbind/set identity)
- Read when:
  - You want multiple isolated agents (workspaces + routing + auth)
  - Multi-agent routing: [Multi-Agent Routing](/concepts/multi-agent)
  - Agent workspace: [Agent workspace](/concepts/agent-workspace)
  - A binding without `accountId` matches the channel default account only.
  - `accountId: "*"` is the channel-wide fallback (all accounts) and is less specific than an explicit account binding.
  - If the same agent already has a matching channel binding without `accountId`, and you later bind with an explicit or resolved `accountId`, OpenClaw upgrades that existing binding in place instead of adding a duplicate.

## docs/cli/approvals.md

- Title: approvals
- Summary: command-line interface reference for `openclaw approvals` (exec approvals for gateway or sbcl hosts)
- Read when:
  - You want to edit exec approvals from the command-line interface
  - You need to manage allowlists on gateway or sbcl hosts
  - Exec approvals: [Exec approvals](/tools/exec-approvals)
  - Nodes: [Nodes](/nodes)
  - `--sbcl` uses the same resolver as `openclaw nodes` (id, name, ip, or id prefix).
  - `--agent` defaults to `"*"`, which applies to all agents.

## docs/cli/browser.md

- Title: browser
- Summary: command-line interface reference for `openclaw browser` (profiles, tabs, actions, extension relay)
- Read when:
  - You use `openclaw browser` and want examples for common tasks
  - You want to control a browser running on another machine via a sbcl host
  - You want to use the Chrome extension relay (attach/detach via toolbar button)
  - Browser tool + API: [Browser tool](/tools/browser)
  - Chrome extension relay: [Chrome extension](/tools/chrome-extension)
  - `--url <gatewayWsUrl>`: Gateway WebSocket URL (defaults to config).

## docs/cli/channels.md

- Title: channels
- Summary: command-line interface reference for `openclaw channels` (accounts, status, login/logout, logs)
- Read when:
  - You want to add/remove channel accounts (WhatsApp/Telegram/Discord/Google Chat/Slack/Mattermost (plugin)/Signal/iMessage)
  - You want to check channel status or tail channel logs
  - Channel guides: [Channels](/channels/index)
  - Gateway configuration: [Configuration](/gateway/configuration)
  - account ids per selected channel
  - optional display names for those accounts

## docs/cli/clawbot.md

- Title: clawbot
- Summary: command-line interface reference for `openclaw clawbot` (legacy alias namespace)
- Read when:
  - You maintain older scripts using `openclaw clawbot ...`
  - You need migration guidance to current commands
  - `openclaw clawbot qr` (same behavior as [`openclaw qr`](/cli/qr))
  - `openclaw clawbot qr` -> `openclaw qr`

## docs/cli/completion.md

- Title: completion
- Summary: command-line interface reference for `openclaw completion` (generate/install shell completion scripts)
- Read when:
  - You want shell completions for zsh/bash/fish/PowerShell
  - You need to cache completion scripts under OpenClaw state
  - `-s, --shell <shell>`: shell target (`zsh`, `bash`, `powershell`, `fish`; default: `zsh`)
  - `-i, --install`: install completion by adding a source line to your shell profile
  - `--write-state`: write completion script(s) to `$OPENCLAW_STATE_DIR/completions` without printing to stdout
  - `-y, --yes`: skip install confirmation prompts

## docs/cli/config.md

- Title: config
- Summary: command-line interface reference for `openclaw config` (get/set/unset/file/validate)
- Read when:
  - You want to read or edit config non-interactively
  - `config file`: Print the active config file path (resolved from `OPENCLAW_CONFIG_PATH` or default location).

## docs/cli/configure.md

- Title: configure
- Summary: command-line interface reference for `openclaw configure` (interactive configuration prompts)
- Read when:
  - You want to tweak credentials, devices, or agent defaults interactively
  - Gateway configuration reference: [Configuration](/gateway/configuration)
  - Config command-line interface: [Config](/cli/config)
  - Choosing where the Gateway runs always updates `gateway.mode`. You can select "Continue" without other sections if that is all you need.
  - Channel-oriented services (Slack/Discord/Matrix/Microsoft Teams) prompt for channel/room allowlists during setup. You can enter names or IDs; the wizard resolves names to IDs when possible.
  - If you run the daemon install step, token auth requires a token, and `gateway.auth.token` is SecretRef-managed, configure validates the SecretRef but does not persist resolved plaintext token values into supervisor service environment metadata.

## docs/cli/cron.md

- Title: cron
- Summary: command-line interface reference for `openclaw cron` (schedule and run background jobs)
- Read when:
  - You want scheduled jobs and wakeups
  - You’re debugging cron execution and logs
  - Cron jobs: [Cron jobs](/automation/cron-jobs)
  - `cron.sessionRetention` (default `24h`) prunes completed isolated run sessions.
  - `cron.runLog.maxBytes` + `cron.runLog.keepLines` prune `~/.openclaw/cron/runs/<jobId>.jsonl`.

## docs/cli/daemon.md

- Title: daemon
- Summary: command-line interface reference for `openclaw daemon` (legacy alias for gateway service management)
- Read when:
  - You still use `openclaw daemon ...` in scripts
  - You need service lifecycle commands (install/start/stop/restart/status)
  - `status`: show service install state and probe Gateway health
  - `install`: install service (`launchd`/`systemd`/`schtasks`)
  - `uninstall`: remove service
  - `start`: start service

## docs/cli/dashboard.md

- Title: dashboard
- Summary: command-line interface reference for `openclaw dashboard` (open the Control UI)
- Read when:
  - You want to open the Control UI with your current token
  - You want to print the URL without launching a browser
  - `dashboard` resolves configured `gateway.auth.token` SecretRefs when possible.
  - For SecretRef-managed tokens (resolved or unresolved), `dashboard` prints/copies/opens a non-tokenized URL to avoid exposing external secrets in terminal output, clipboard history, or browser-launch arguments.
  - If `gateway.auth.token` is SecretRef-managed but unresolved in this command path, the command prints a non-tokenized URL and explicit remediation guidance instead of embedding an invalid token placeholder.

## docs/cli/devices.md

- Title: devices
- Summary: command-line interface reference for `openclaw devices` (device pairing + token rotation/revocation)
- Read when:
  - You are approving device pairing requests
  - You need to rotate or revoke device tokens
  - `--url <url>`: Gateway WebSocket URL (defaults to `gateway.remote.url` when configured).
  - `--token <token>`: Gateway token (if required).
  - `--password <password>`: Gateway password (password auth).
  - `--timeout <ms>`: RPC timeout.

## docs/cli/directory.md

- Title: directory
- Summary: command-line interface reference for `openclaw directory` (self, peers, groups)
- Read when:
  - You want to look up contacts/groups/self ids for a channel
  - You are developing a channel directory adapter
  - `--channel <name>`: channel id/alias (required when multiple channels are configured; auto when only one is configured)
  - `--account <id>`: account id (default: channel default)
  - `--json`: output JSON
  - `directory` is meant to help you find IDs you can paste into other commands (especially `openclaw message send --target ...`).

## docs/cli/dns.md

- Title: dns
- Summary: command-line interface reference for `openclaw dns` (wide-area discovery helpers)
- Read when:
  - You want wide-area discovery (DNS-SD) via Tailscale + CoreDNS
  - You’re setting up split DNS for a custom discovery domain (example: openclaw.internal)
  - Gateway discovery: [Discovery](/gateway/discovery)
  - Wide-area discovery config: [Configuration](/gateway/configuration)

## docs/cli/docs.md

- Title: docs
- Summary: command-line interface reference for `openclaw docs` (search the live docs index)
- Read when:
  - You want to search the live OpenClaw docs from the terminal

## docs/cli/doctor.md

- Title: doctor
- Summary: command-line interface reference for `openclaw doctor` (health checks + guided repairs)
- Read when:
  - You have connectivity/auth issues and want guided fixes
  - You updated and want a sanity check
  - Troubleshooting: [Troubleshooting](/gateway/troubleshooting)
  - Security audit: [Security](/gateway/security)
  - Interactive prompts (like keychain/OAuth fixes) only run when stdin is a TTY and `--non-interactive` is **not** set. Headless runs (cron, Telegram, no terminal) will skip prompts.
  - `--fix` (alias for `--repair`) writes a backup to `~/.openclaw/openclaw.json.bak` and drops unknown config keys, listing each removal.

## docs/cli/gateway.md

- Title: gateway
- Summary: OpenClaw Gateway command-line interface (`openclaw gateway`) — run, query, and discover gateways
- Read when:
  - Running the Gateway from the command-line interface (dev or servers)
  - Debugging Gateway auth, bind modes, and connectivity
  - Discovering gateways via Bonjour (LAN + tailnet)
  - [/gateway/bonjour](/gateway/bonjour)
  - [/gateway/discovery](/gateway/discovery)
  - [/gateway/configuration](/gateway/configuration)

## docs/cli/health.md

- Title: health
- Summary: command-line interface reference for `openclaw health` (gateway health endpoint via RPC)
- Read when:
  - You want to quickly check the running Gateway’s health
  - `--verbose` runs live probes and prints per-account timings when multiple accounts are configured.
  - Output includes per-agent session stores when multiple agents are configured.

## docs/cli/hooks.md

- Title: hooks
- Summary: command-line interface reference for `openclaw hooks` (agent hooks)
- Read when:
  - You want to manage agent hooks
  - You want to install or update hooks
  - Hooks: [Hooks](/automation/hooks)
  - Plugin hooks: [Plugins](/tools/plugin#plugin-hooks)
  - `--eligible`: Show only eligible hooks (requirements met)
  - `--json`: Output as JSON

## docs/cli/index.md

- Title: command-line interface Reference
- Summary: OpenClaw command-line interface reference for `openclaw` commands, subcommands, and options
- Read when:
  - Adding or modifying command-line interface commands or options
  - Documenting new command surfaces
  - [`setup`](/cli/setup)
  - [`onboard`](/cli/onboard)
  - [`configure`](/cli/configure)
  - [`config`](/cli/config)

## docs/cli/logs.md

- Title: logs
- Summary: command-line interface reference for `openclaw logs` (tail gateway logs via RPC)
- Read when:
  - You need to tail Gateway logs remotely (without SSH)
  - You want JSON log lines for tooling
  - Logging overview: [Logging](/logging)

## docs/cli/memory.md

- Title: memory
- Summary: command-line interface reference for `openclaw memory` (status/index/search)
- Read when:
  - You want to index or search semantic memory
  - You’re debugging memory availability or indexing
  - Memory concept: [Memory](/concepts/memory)
  - Plugins: [Plugins](/tools/plugin)
  - `--agent <id>`: scope to a single agent. Without it, these commands run for each configured agent; if no agent list is configured, they fall back to the default agent.
  - `--verbose`: emit detailed logs during probes and indexing.

## docs/cli/message.md

- Title: message
- Summary: command-line interface reference for `openclaw message` (send + channel actions)
- Read when:
  - Adding or modifying message command-line interface actions
  - Changing outbound channel behavior
  - `--channel` required if more than one channel is configured.
  - If exactly one channel is configured, it becomes the default.
  - Values: `whatsapp|telegram|discord|googlechat|slack|mattermost|signal|imessage|msteams` (Mattermost requires plugin)
  - WhatsApp: E.164 or group JID

## docs/cli/models.md

- Title: models
- Summary: command-line interface reference for `openclaw models` (status/list/set/scan, aliases, fallbacks, auth)
- Read when:
  - You want to change default models or view provider auth status
  - You want to scan available models/providers and debug auth profiles
  - Providers + models: [Models](/providers/models)
  - Provider auth setup: [Getting started](/start/getting-started)
  - `models set <model-or-alias>` accepts `provider/model` or an alias.
  - Model refs are parsed by splitting on the **first** `/`. If the model ID includes `/` (OpenRouter-style), include the provider prefix (example: `openrouter/moonshotai/kimi-k2`).

## docs/cli/sbcl.md

- Title: sbcl
- Summary: command-line interface reference for `openclaw sbcl` (headless sbcl host)
- Read when:
  - Running the headless sbcl host
  - Pairing a non-macOS sbcl for system.run
  - Run commands on remote Linux/Windows boxes (build servers, lab machines, NAS).
  - Keep exec **sandboxed** on the gateway, but delegate approved runs to other hosts.
  - Provide a lightweight, headless execution target for automation or CI nodes.
  - `--host <host>`: Gateway WebSocket host (default: `127.0.0.1`)

## docs/cli/nodes.md

- Title: nodes
- Summary: command-line interface reference for `openclaw nodes` (list/status/approve/invoke, camera/canvas/screen)
- Read when:
  - You’re managing paired nodes (cameras, screen, canvas)
  - You need to approve requests or invoke sbcl commands
  - Nodes overview: [Nodes](/nodes)
  - Camera: [Camera nodes](/nodes/camera)
  - Images: [Image nodes](/nodes/images)
  - `--url`, `--token`, `--timeout`, `--json`

## docs/cli/onboard.md

- Title: onboard
- Summary: command-line interface reference for `openclaw onboard` (interactive onboarding wizard)
- Read when:
  - You want guided setup for gateway, workspace, auth, channels, and skills
  - command-line interface onboarding hub: [Onboarding Wizard (command-line interface)](/start/wizard)
  - Onboarding overview: [Onboarding Overview](/start/onboarding-overview)
  - command-line interface onboarding reference: [command-line interface Onboarding Reference](/start/wizard-cli-reference)
  - command-line interface automation: [command-line interface Automation](/start/wizard-cli-automation)
  - macOS onboarding: [Onboarding (macOS App)](/start/onboarding)

## docs/cli/pairing.md

- Title: pairing
- Summary: command-line interface reference for `openclaw pairing` (approve/list pairing requests)
- Read when:
  - You’re using pairing-mode DMs and need to approve senders
  - Pairing flow: [Pairing](/channels/pairing)
  - Channel input: pass it positionally (`pairing list telegram`) or with `--channel <channel>`.
  - `pairing list` supports `--account <accountId>` for multi-account channels.
  - `pairing approve` supports `--account <accountId>` and `--notify`.
  - If only one pairing-capable channel is configured, `pairing approve <code>` is allowed.

## docs/cli/plugins.md

- Title: plugins
- Summary: command-line interface reference for `openclaw plugins` (list, install, uninstall, enable/disable, doctor)
- Read when:
  - You want to install or manage in-process Gateway plugins
  - You want to debug plugin load failures
  - Plugin system: [Plugins](/tools/plugin)
  - Plugin manifest + schema: [Plugin manifest](/plugins/manifest)
  - Security hardening: [Security](/gateway/security)

## docs/cli/qr.md

- Title: qr
- Summary: command-line interface reference for `openclaw qr` (generate iOS pairing QR + setup code)
- Read when:
  - You want to pair the iOS app with a gateway quickly
  - You need setup-code output for remote/manual sharing
  - `--remote`: use `gateway.remote.url` plus remote token/password from config
  - `--url <url>`: override gateway URL used in payload
  - `--public-url <url>`: override public URL used in payload
  - `--token <token>`: override gateway token for payload

## docs/cli/reset.md

- Title: reset
- Summary: command-line interface reference for `openclaw reset` (reset local state/config)
- Read when:
  - You want to wipe local state while keeping the command-line interface installed
  - You want a dry-run of what would be removed

## docs/cli/sandbox.md

- Title: Sandbox command-line interface
- Summary: Manage sandbox containers and inspect effective sandbox policy
- Read when:
  - Container name and status (running/stopped)
  - Docker (driven from Common Lisp) image and whether it matches config
  - Age (time since creation)
  - Idle time (time since last use)
  - Associated session/agent
  - `--all`: Recreate all sandbox containers

## docs/cli/secrets.md

- Title: secrets
- Summary: command-line interface reference for `openclaw secrets` (reload, audit, configure, apply)
- Read when:
  - Re-resolving secret refs at runtime
  - Auditing plaintext residues and unresolved refs
  - Configuring SecretRefs and applying one-way scrub changes
  - `reload`: gateway RPC (`secrets.reload`) that re-resolves refs and swaps runtime snapshot only on full success (no config writes).
  - `audit`: read-only scan of configuration/auth/generated-model stores and legacy residues for plaintext, unresolved refs, and precedence drift.
  - `configure`: interactive planner for provider setup, target mapping, and preflight (TTY required).

## docs/cli/security.md

- Title: security
- Summary: command-line interface reference for `openclaw security` (audit and fix common security footguns)
- Read when:
  - You want to run a quick security audit on config/state
  - You want to apply safe “fix” suggestions (chmod, tighten defaults)
  - Security guide: [Security](/gateway/security)
  - flips common `groupPolicy="open"` to `groupPolicy="allowlist"` (including account variants in supported channels)
  - sets `logging.redactSensitive` from `"off"` to `"tools"`
  - tightens permissions for state/config and common sensitive files (`credentials/*.json`, `auth-profiles.json`, `sessions.json`, session `*.jsonl`)

## docs/cli/sessions.md

- Title: sessions
- Summary: command-line interface reference for `openclaw sessions` (list stored sessions + usage)
- Read when:
  - You want to list stored sessions and see recent activity
  - default: configured default agent store
  - `--agent <id>`: one configured agent store
  - `--all-agents`: aggregate all configured agent stores
  - `--store <path>`: explicit store path (cannot be combined with `--agent` or `--all-agents`)
  - Scope note: `openclaw sessions cleanup` maintains session stores/transcripts only. It does not prune cron run logs (`cron/runs/<jobId>.jsonl`), which are managed by `cron.runLog.maxBytes` and `cron.runLog.keepLines` in [Cron configuration](/automation/cron-jobs#configuration) and explained in [Cron maintenance](/automation/cron-jobs#maintenance).

## docs/cli/setup.md

- Title: setup
- Summary: command-line interface reference for `openclaw setup` (initialize config + workspace)
- Read when:
  - You’re doing first-run setup without the full onboarding wizard
  - You want to set the default workspace path
  - Getting started: [Getting started](/start/getting-started)
  - Wizard: [Onboarding](/start/onboarding)

## docs/cli/skills.md

- Title: skills
- Summary: command-line interface reference for `openclaw skills` (list/info/check) and skill eligibility
- Read when:
  - You want to see which skills are available and ready to run
  - You want to debug missing binaries/env/config for skills
  - Skills system: [Skills](/tools/skills)
  - Skills config: [Skills config](/tools/skills-config)
  - ClawHub installs: [ClawHub](/tools/clawhub)

## docs/cli/status.md

- Title: status
- Summary: command-line interface reference for `openclaw status` (diagnostics, probes, usage snapshots)
- Read when:
  - You want a quick diagnosis of channel health + recent session recipients
  - You want a pasteable “all” status for debugging
  - `--deep` runs live probes (WhatsApp Web + Telegram + Discord + Google Chat + Slack + Signal).
  - Output includes per-agent session stores when multiple agents are configured.
  - Overview includes Gateway + sbcl host service install/runtime status when available.
  - Overview includes update channel + git SHA (for source checkouts).

## docs/cli/system.md

- Title: system
- Summary: command-line interface reference for `openclaw system` (system events, heartbeat, presence)
- Read when:
  - You want to enqueue a system event without creating a cron job
  - You need to enable or disable heartbeats
  - You want to inspect system presence entries
  - `--text <text>`: required system event text.
  - `--mode <mode>`: `now` or `next-heartbeat` (default).
  - `--json`: machine-readable output.

## docs/cli/tui.md

- Title: tui
- Summary: command-line interface reference for `openclaw tui` (terminal UI connected to the Gateway)
- Read when:
  - You want a terminal UI for the Gateway (remote-friendly)
  - You want to pass url/token/session from scripts
  - TUI guide: [TUI](/web/tui)
  - `tui` resolves configured gateway auth SecretRefs for token/password auth when possible (`env`/`file`/`exec` providers).

## docs/cli/uninstall.md

- Title: uninstall
- Summary: command-line interface reference for `openclaw uninstall` (remove gateway service + local data)
- Read when:
  - You want to remove the gateway service and/or local state
  - You want a dry-run first

## docs/cli/update.md

- Title: update
- Summary: command-line interface reference for `openclaw update` (safe-ish source update + gateway auto-restart)
- Read when:
  - You want to update a source checkout safely
  - You need to understand `--update` shorthand behavior
  - `--no-restart`: skip restarting the Gateway service after a successful update.
  - `--channel <stable|beta|dev>`: set the update channel (git + Quicklisp/Ultralisp; persisted in config).
  - `--tag <dist-tag|version>`: override the Quicklisp/Ultralisp dist-tag or version for this update only.
  - `--dry-run`: preview planned update actions (channel/tag/target/restart flow) without writing config, installing, syncing plugins, or restarting.

## docs/cli/voicecall.md

- Title: voicecall
- Summary: command-line interface reference for `openclaw voicecall` (voice-call plugin command surface)
- Read when:
  - You use the voice-call plugin and want the command-line interface entry points
  - You want quick examples for `voicecall call|continue|status|tail|expose`
  - Voice-call plugin: [Voice Call](/plugins/voice-call)

## docs/cli/webhooks.md

- Title: webhooks
- Summary: command-line interface reference for `openclaw webhooks` (webhook helpers + Gmail Pub/Sub)
- Read when:
  - You want to wire Gmail Pub/Sub events into OpenClaw
  - You want webhook helper commands
  - Webhooks: [Webhook](/automation/webhook)
  - Gmail Pub/Sub: [Gmail Pub/Sub](/automation/gmail-pubsub)

## docs/concepts/agent-loop.md

- Title: Agent Loop
- Summary: Agent loop lifecycle, streams, and wait semantics
- Read when:
  - You need an exact walkthrough of the agent loop or lifecycle events
  - Gateway RPC: `agent` and `agent.wait`.
  - command-line interface: `agent` command.
  - resolves model + thinking/verbose defaults
  - loads skills snapshot
  - calls `runEmbeddedPiAgent` (pi-agent-core runtime)

## docs/concepts/agent-workspace.md

- Title: Agent Workspace
- Summary: Agent workspace: location, layout, and backup strategy
- Read when:
  - You need to explain the agent workspace or its file layout
  - You want to back up or migrate an agent workspace
  - Default: `~/.openclaw/workspace`
  - If `OPENCLAW_PROFILE` is set and not `"default"`, the default becomes
  - Override in `~/.openclaw/openclaw.json`:
  - `AGENTS.md`

## docs/concepts/agent.md

- Title: Agent Runtime
- Summary: Agent runtime (embedded pi-mono), workspace contract, and session bootstrap
- Read when:
  - Changing agent runtime, workspace bootstrap, or session behavior
  - `AGENTS.md` — operating instructions + “memory”
  - `SOUL.md` — persona, boundaries, tone
  - `TOOLS.md` — user-maintained tool notes (e.g. `imsg`, `sag`, conventions)
  - `BOOTSTRAP.md` — one-time first-run ritual (deleted after completion)
  - `IDENTITY.md` — agent name/vibe/emoji

## docs/concepts/architecture.md

- Title: Gateway Architecture
- Summary: WebSocket gateway architecture, components, and client flows
- Read when:
  - Working on gateway protocol, clients, or transports
  - A single long‑lived **Gateway** owns all messaging surfaces (WhatsApp via
  - Control-plane clients (macOS app, command-line interface, web UI, automations) connect to the
  - **Nodes** (macOS/iOS/Android/headless) also connect over **WebSocket**, but
  - One Gateway per host; it is the only place that opens a WhatsApp session.
  - The **canvas host** is served by the Gateway HTTP server under:

## docs/concepts/compaction.md

- Title: Compaction
- Summary: Context window + compaction: how OpenClaw keeps sessions under model limits
- Read when:
  - You want to understand auto-compaction and /compact
  - You are debugging long sessions hitting context limits
  - The compaction summary
  - Recent messages after the compaction point
  - `🧹 Auto-compaction complete` in verbose mode
  - `/status` showing `🧹 Compactions: <count>`

## docs/concepts/context.md

- Title: Context
- Summary: Context: what the model sees, how it is built, and how to inspect it
- Read when:
  - You want to understand what “context” means in OpenClaw
  - You are debugging why the model “knows” something (or forgot it)
  - You want to reduce context overhead (/context, /status, /compact)
  - **System prompt** (OpenClaw-built): rules, tools, skills list, time/runtime, and injected workspace files.
  - **Conversation history**: your messages + the assistant’s messages for this session.
  - **Tool calls/results + attachments**: command output, file reads, images/audio, etc.

## docs/concepts/features.md

- Title: Features
- Summary: OpenClaw capabilities across channels, routing, media, and UX.
- Read when:
  - You want a full list of what OpenClaw supports
  - WhatsApp integration via WhatsApp Web (Baileys)
  - Telegram bot support (grammY)
  - Discord bot support (channels.discord.js)
  - Mattermost bot support (plugin)
  - iMessage integration via local imsg command-line interface (macOS)

## docs/concepts/markdown-formatting.md

- Title: Markdown Formatting
- Summary: Markdown formatting pipeline for outbound channels
- Read when:
  - You are changing markdown formatting or chunking for outbound channels
  - You are adding a new channel formatter or style mapping
  - You are debugging formatting regressions across channels
  - **Consistency:** one parse step, multiple renderers.
  - **Safe chunking:** split text before rendering so inline formatting never
  - **Channel fit:** map the same IR to Slack mrkdwn, Telegram HTML, and Signal

## docs/concepts/memory.md

- Title: Memory
- Summary: How OpenClaw memory works (workspace files + automatic memory flush)
- Read when:
  - You want the memory file layout and workflow
  - You want to tune the automatic pre-compaction memory flush
  - `memory/YYYY-MM-DD.md`
  - Daily log (append-only).
  - Read today + yesterday at session start.
  - `MEMORY.md` (optional)

## docs/concepts/messages.md

- Title: Messages
- Summary: Message flow, sessions, queueing, and reasoning visibility
- Read when:
  - Explaining how inbound messages become replies
  - Clarifying sessions, queueing modes, or streaming behavior
  - Documenting reasoning visibility and usage implications
  - `messages.*` for prefixes, queueing, and group behavior.
  - `agents.defaults.*` for block streaming and chunking defaults.
  - Channel overrides (`channels.whatsapp.*`, `channels.telegram.*`, etc.) for caps and streaming toggles.

## docs/concepts/model-failover.md

- Title: Model Failover
- Summary: How OpenClaw rotates auth profiles and falls back across models
- Read when:
  - Diagnosing auth profile rotation, cooldowns, or model fallback behavior
  - Updating failover rules for auth profiles or models
  - Secrets live in `~/.openclaw/agents/<agentId>/agent/auth-profiles.json` (legacy: `~/.openclaw/agent/auth-profiles.json`).
  - Config `auth.profiles` / `auth.order` are **metadata + routing only** (no secrets).
  - Legacy import-only OAuth file: `~/.openclaw/credentials/oauth.json` (imported into `auth-profiles.json` on first use).
  - `type: "api_key"` → `{ provider, key }`

## docs/concepts/model-providers.md

- Title: Model Providers
- Summary: Model provider overview with example configs + command-line interface flows
- Read when:
  - You need a provider-by-provider model setup reference
  - You want example configs or command-line interface onboarding commands for model providers
  - Model refs use `provider/model` (example: `opencode/claude-opus-4-6`).
  - If you set `agents.defaults.models`, it becomes the allowlist.
  - command-line interface helpers: `openclaw onboard`, `openclaw models list`, `openclaw models set <provider/model>`.
  - Supports generic provider rotation for selected providers.

## docs/concepts/models.md

- Title: Models command-line interface
- Summary: Models command-line interface: list, set, aliases, fallbacks, scan, status
- Read when:
  - Adding or modifying models command-line interface (models list/set/scan/aliases/fallbacks)
  - Changing model fallback behavior or selection UX
  - Updating model scan probes (tools/images)
  - `agents.defaults.models` is the allowlist/catalog of models OpenClaw can use (plus aliases).
  - `agents.defaults.imageModel` is used **only when** the primary model can’t accept images.
  - Per-agent defaults can override `agents.defaults.model` via `agents.list[].model` plus bindings (see [/concepts/multi-agent](/concepts/multi-agent)).

## docs/concepts/multi-agent.md

- Title: Multi-Agent Routing
- Summary: Multi-agent routing: isolated agents, channel accounts, and bindings
- Read when:
  - **Workspace** (files, AGENTS.md/SOUL.md/USER.md, local notes, persona rules).
  - **State directory** (`agentDir`) for auth profiles, model registry, and per-agent config.
  - **Session store** (chat history + routing state) under `~/.openclaw/agents/<agentId>/sessions`.
  - Config: `~/.openclaw/openclaw.json` (or `OPENCLAW_CONFIG_PATH`)
  - State dir: `~/.openclaw` (or `OPENCLAW_STATE_DIR`)
  - Workspace: `~/.openclaw/workspace` (or `~/.openclaw/workspace-<agentId>`)

## docs/concepts/oauth.md

- Title: OAuth
- Summary: OAuth in OpenClaw: token exchange, storage, and multi-account patterns
- Read when:
  - You want to understand OpenClaw OAuth end-to-end
  - You hit token invalidation / logout issues
  - You want setup-token or OAuth auth flows
  - You want multiple accounts or profile routing
  - how the OAuth **token exchange** works (PKCE)
  - where tokens are **stored** (and why)

## docs/concepts/presence.md

- Title: Presence
- Summary: How OpenClaw presence entries are produced, merged, and displayed
- Read when:
  - Debugging the Instances tab
  - Investigating duplicate or stale instance rows
  - Changing gateway WS connect or system-event beacons
  - the **Gateway** itself, and
  - **clients connected to the Gateway** (mac app, WebChat, command-line interface, etc.)
  - `instanceId` (optional but strongly recommended): stable client identity (usually `connect.client.instanceId`)

## docs/concepts/queue.md

- Title: Command Queue
- Summary: Command queue design that serializes inbound auto-reply runs
- Read when:
  - Changing auto-reply execution or concurrency
  - Auto-reply runs can be expensive (LLM calls) and can collide when multiple inbound messages arrive close together.
  - Serializing avoids competing for shared resources (session files, logs, command-line interface stdin) and reduces the chance of upstream rate limits.
  - A lane-aware FIFO queue drains each lane with a configurable concurrency cap (default 1 for unconfigured lanes; main defaults to 4, subagent to 8).
  - `runEmbeddedPiAgent` enqueues by **session key** (lane `session:<key>`) to guarantee only one active run per session.
  - Each session run is then queued into a **global lane** (`main` by default) so overall parallelism is capped by `agents.defaults.maxConcurrent`.

## docs/concepts/retry.md

- Title: Retry Policy
- Summary: Retry policy for outbound provider calls
- Read when:
  - Updating provider retry behavior or defaults
  - Debugging provider send errors or rate limits
  - Retry per HTTP request, not per multi-step flow.
  - Preserve ordering by retrying only the current step.
  - Avoid duplicating non-idempotent operations.
  - Attempts: 3

## docs/concepts/session-pruning.md

- Title: Session Pruning
- Summary: Session pruning: tool-result trimming to reduce context bloat
- Read when:
  - You want to reduce LLM context growth from tool outputs
  - You are tuning agents.defaults.contextPruning
  - When `mode: "cache-ttl"` is enabled and the last Anthropic call for the session is older than `ttl`.
  - Only affects the messages sent to the model for that request.
  - Only active for Anthropic API calls (and OpenRouter Anthropic models).
  - For best results, match `ttl` to your model `cacheRetention` policy (`short` = 5m, `long` = 1h).

## docs/concepts/session-tool.md

- Title: Session Tools
- Summary: Agent session tools for listing sessions, fetching history, and sending cross-session messages
- Read when:
  - Adding or modifying session tools
  - `sessions_list`
  - `sessions_history`
  - `sessions_send`
  - `sessions_spawn`
  - Main direct chat bucket is always the literal key `"main"` (resolved to the current agent’s main key).

## docs/concepts/session.md

- Title: Session Management
- Summary: Session management rules, keys, and persistence for chats
- Read when:
  - Modifying session handling or storage
  - `main` (default): all DMs share the main session for continuity.
  - `per-peer`: isolate by sender id across channels.
  - `per-channel-peer`: isolate by channel + sender (recommended for multi-user inboxes).
  - `per-account-channel-peer`: isolate by account + channel + sender (recommended for multi-account inboxes).
  - Alice (`<SENDER_A>`) messages your agent about a private topic (for example, a medical appointment)

## docs/concepts/streaming.md

- Title: Streaming and Chunking
- Summary: Streaming + chunking behavior (block replies, channel preview streaming, mode mapping)
- Read when:
  - Explaining how streaming or chunking works on channels
  - Changing block streaming or channel chunking behavior
  - Debugging duplicate/early block replies or channel preview streaming
  - **Block streaming (channels):** emit completed **blocks** as the assistant writes. These are normal channel messages (not token deltas).
  - **Preview streaming (Telegram/Discord/Slack):** update a temporary **preview message** while generating.
  - `text_delta/events`: model stream events (may be sparse for non-streaming models).

## docs/concepts/system-prompt.md

- Title: System Prompt
- Summary: What the OpenClaw system prompt contains and how it is assembled
- Read when:
  - Editing system prompt text, tools list, or time/heartbeat sections
  - Changing workspace bootstrap or skills injection behavior
  - **Tooling**: current tool list + short descriptions.
  - **Safety**: short guardrail reminder to avoid power-seeking behavior or bypassing oversight.
  - **Skills** (when available): tells the model how to load skill instructions on demand.
  - **OpenClaw Self-Update**: how to run `config.apply` and `update.run`.

## docs/concepts/timezone.md

- Title: Timezones
- Summary: Timezone handling for agents, envelopes, and prompts
- Read when:
  - You need to understand how timestamps are normalized for the model
  - Configuring the user timezone for system prompts
  - `envelopeTimezone: "utc"` uses UTC.
  - `envelopeTimezone: "user"` uses `agents.defaults.userTimezone` (falls back to host timezone).
  - Use an explicit IANA timezone (e.g., `"Europe/Vienna"`) for a fixed offset.
  - `envelopeTimestamp: "off"` removes absolute timestamps from envelope headers.

## docs/concepts/typebox.md

- Title: TypeBox
- Summary: TypeBox schemas as the single source of truth for the gateway protocol
- Read when:
  - Updating protocol schemas or codegen
  - **Request**: `{ type: "req", id, method, params }`
  - **Response**: `{ type: "res", id, ok, payload | error }`
  - **Event**: `{ type: "event", event, payload, seq?, stateVersion? }`
  - Source: `src/gateway/protocol/schema.lisp`
  - Runtime validators (AJV): `src/gateway/protocol/index.lisp`

## docs/concepts/typing-indicators.md

- Title: Typing Indicators
- Summary: When OpenClaw shows typing indicators and how to tune them
- Read when:
  - Changing typing indicator behavior or defaults
  - **Direct chats**: typing starts immediately once the model loop begins.
  - **Group chats with a mention**: typing starts immediately.
  - **Group chats without a mention**: typing starts only when message text begins streaming.
  - **Heartbeat runs**: typing is disabled.
  - `never` — no typing indicator, ever.

## docs/concepts/usage-tracking.md

- Title: Usage Tracking
- Summary: Usage tracking surfaces and credential requirements
- Read when:
  - You are wiring provider usage/quota surfaces
  - You need to explain usage tracking behavior or auth requirements
  - Pulls provider usage/quota directly from their usage endpoints.
  - No estimated costs; only the provider-reported windows.
  - `/status` in chats: emoji‑rich status card with session tokens + estimated cost (API key only). Provider usage shows for the **current model provider** when available.
  - `/usage off|tokens|full` in chats: per-response usage footer (OAuth shows tokens only).

## docs/date-time.md

- Title: Date and Time
- Summary: Date and time handling across envelopes, prompts, tools, and connectors
- Read when:
  - You are changing how timestamps are shown to the model or users
  - You are debugging time formatting in messages or system prompt output
  - `envelopeTimezone: "utc"` uses UTC.
  - `envelopeTimezone: "local"` uses the host timezone.
  - `envelopeTimezone: "user"` uses `agents.defaults.userTimezone` (falls back to host timezone).
  - Use an explicit IANA timezone (e.g., `"America/Chicago"`) for a fixed zone.

## docs/debug/sbcl-issue.md

- Title: Node + tsx Crash
- Read when:
  - Debugging Node-only dev scripts or watch mode failures
  - Investigating tsx/esbuild loader crashes in OpenClaw
  - Node: v25.x (observed on v25.3.0)
  - tsx: 4.21.0
  - OS: macOS (repro also likely on other platforms that run Node 25)
  - Node 25.3.0: fails

## docs/design/kilo-gateway-integration.md

- Title: Kilo Gateway Provider Integration Design
- Read when:
  - Matches the user config example provided (`kilocode` provider key)
  - Consistent with existing provider naming patterns (e.g., `openrouter`, `opencode`, `moonshot`)
  - Short and memorable
  - Avoids confusion with generic "kilo" or "gateway" terms
  - Based on user config example
  - Claude Opus 4.5 is a capable default model

## docs/diagnostics/flags.md

- Title: Diagnostics Flags
- Summary: Diagnostics flags for targeted debug logs
- Read when:
  - You need targeted debug logs without raising global logging levels
  - You need to capture subsystem-specific logs for support
  - Flags are strings (case-insensitive).
  - You can enable flags in config or via an env override.
  - Wildcards are supported:
  - `telegram.*` matches `telegram.http`

## docs/experiments/onboarding-config-protocol.md

- Title: Onboarding and Config Protocol
- Summary: RPC protocol notes for onboarding wizard and config schema
- Read when:
  - Wizard engine (shared session + prompts + onboarding state).
  - command-line interface onboarding uses the same wizard flow as the UI clients.
  - Gateway RPC exposes wizard + config schema endpoints.
  - macOS onboarding uses the wizard step model.
  - Web UI renders config forms from JSON Schema + UI hints.
  - `wizard.start` params: `{ mode?: "local"|"remote", workspace?: string }`

## docs/experiments/plans/acp-persistent-bindings-discord-channels-telegram-topics.md

- Title: ACP Persistent Bindings for Discord Channels and Telegram Topics
- Read when:
  - Discord channels (and existing threads, where needed), and
  - Telegram forum topics in groups/supergroups (`chatId:topic:topicId`)
  - Support durable ACP binding for:
  - Discord channels/threads
  - Telegram forum topics (groups/supergroups)
  - Make binding source-of-truth config-driven.

## docs/experiments/plans/acp-thread-bound-agents.md

- Title: ACP Thread Bound Agents
- Summary: Integrate ACP coding agents via a first-class ACP control plane in core and plugin-backed runtimes (acpx first)
- Read when:
  - [Unified Runtime Streaming Refactor Plan](/experiments/plans/acp-unified-streaming-refactor)
  - a user spawns or focuses an ACP session into a thread
  - user messages in that thread route to the bound ACP session
  - agent output streams back to the same thread persona
  - session can be persistent or one shot with explicit cleanup controls
  - OpenClaw core owns ACP control plane concerns

## docs/experiments/plans/acp-unified-streaming-refactor.md

- Title: Unified Runtime Streaming Refactor Plan
- Summary: Holy grail refactor plan for one unified runtime streaming pipeline across main, subagent, and ACP
- Read when:
  - Current behavior is split across multiple runtime-specific shaping paths.
  - Formatting/coalescing bugs can be fixed in one path but remain in others.
  - Delivery consistency, duplicate suppression, and recovery semantics are harder to reason about.
  - `turn_started`
  - `text_delta`
  - `block_final`

## docs/experiments/plans/browser-evaluate-cdp-refactor.md

- Title: Browser Evaluate Chrome DevTools Protocol Refactor
- Summary: Plan: isolate browser act:evaluate from Chrome DevTools Protocol automation in Common Lisp (or external helper) queue using Chrome DevTools Protocol, with end-to-end deadlines and safer ref resolution
- Read when:
  - Working on browser `act:evaluate` timeout, abort, or queue blocking issues
  - Planning Chrome DevTools Protocol based isolation for evaluate execution
  - `act:evaluate` cannot permanently block later browser actions on the same tab.
  - Timeouts are single source of truth end to end so a caller can rely on a budget.
  - Abort and timeout are treated the same way across HTTP and in-process dispatch.
  - Element targeting for evaluate is supported without switching everything off Chrome DevTools Protocol automation in Common Lisp (or external helper).

## docs/experiments/plans/discord-async-inbound-worker.md

- Title: Discord Async Inbound Worker Plan
- Summary: Status and next steps for decoupling Discord gateway listeners from long-running agent turns with a Discord-specific inbound worker
- Read when:
  - Discord listener timeout and Discord run timeout are now separate settings.
  - Accepted inbound Discord turns are enqueued into `src/discord/monitor/inbound-worker.lisp`.
  - The worker now owns the long-running turn instead of the Carbon listener.
  - Existing per-route ordering is preserved by queue key.
  - Timeout regression coverage exists for the Discord worker path.
  - the production timeout bug is fixed

## docs/experiments/plans/openresponses-gateway.md

- Title: OpenResponses Gateway Plan
- Summary: Plan: Add OpenResponses /v1/responses endpoint and deprecate chat completions cleanly
- Read when:
  - Designing or implementing `/v1/responses` gateway support
  - Planning migration from Chat Completions compatibility
  - Add a `/v1/responses` endpoint that adheres to OpenResponses semantics.
  - Keep Chat Completions as a compatibility layer that is easy to disable and eventually remove.
  - Standardize validation and parsing with isolated, reusable schemas.
  - Full OpenResponses feature parity in the first pass (images, files, hosted tools).

## docs/experiments/plans/pty-process-supervision.md

- Title: PTY and Process Supervision Plan
- Summary: Production plan for reliable interactive process supervision (PTY + non-PTY) with explicit ownership, unified lifecycle, and deterministic cleanup
- Read when:
  - Working on exec/process lifecycle ownership and cleanup
  - Debugging PTY and non-PTY supervision behavior
  - `exec` foreground runs
  - `exec` background runs
  - `process` follow up actions (`poll`, `log`, `send-keys`, `paste`, `submit`, `kill`, `remove`)
  - command-line interface agent runner subprocesses

## docs/experiments/plans/session-binding-channel-agnostic.md

- Title: Session Binding Channel Agnostic Plan
- Summary: Channel agnostic session binding architecture and iteration 1 delivery scope
- Read when:
  - Refactoring channel-agnostic session routing and bindings
  - Investigating duplicate, stale, or missing session delivery across channels
  - make subagent bound session routing a core capability
  - keep channel specific behavior in adapters
  - avoid regressions in normal Discord behavior
  - completion content policy

## docs/experiments/proposals/acp-bound-command-auth.md

- Title: ACP Bound Command Authorization (Proposal)
- Summary: Proposal: long-term command authorization model for ACP-bound conversations
- Read when:
  - Designing native command auth behavior in Telegram/Discord ACP-bound channels/topics
  - `src/telegram/bot-native-commands.lisp`
  - `src/discord/monitor/native-command.lisp`
  - `src/auto-reply/reply/commands-core.lisp`
  - command policy metadata
  - sender authorization state

## docs/experiments/proposals/model-config.md

- Title: Model Config Exploration
- Summary: Exploration: model config, auth profiles, and fallback behavior
- Read when:
  - Exploring future model selection + auth profile ideas
  - [Models](/concepts/models)
  - [Model failover](/concepts/model-failover)
  - [OAuth + profiles](/concepts/oauth)
  - Multiple auth profiles per provider (personal vs work).
  - Simple `/model` selection with predictable fallbacks.

## docs/experiments/research/memory.md

- Title: Workspace Memory Research
- Summary: Research notes: offline memory system for Clawd workspaces (Markdown source-of-truth + derived index)
- Read when:
  - Designing workspace memory (~/.openclaw/workspace) beyond daily Markdown logs
  - Deciding: standalone command-line interface vs deep OpenClaw integration
  - Adding offline recall + reflection (retain/recall/reflect)
  - “append-only” journaling
  - human editing
  - git-backed durability + auditability

## docs/gateway/authentication.md

- Title: Authentication
- Summary: Model authentication: OAuth, API keys, and setup-token
- Read when:
  - Debugging model auth or OAuth expiry
  - Documenting authentication or credential storage
  - `api_key` credentials can use `keyRef: { source, provider, id }`
  - `token` credentials can use `tokenRef: { source, provider, id }`
  - Priority order:
  - `OPENCLAW_LIVE_<PROVIDER>_KEY` (single override)

## docs/gateway/background-process.md

- Title: Background Exec and Process Tool
- Summary: Background exec execution and process management
- Read when:
  - Adding or modifying background exec behavior
  - Debugging long-running exec tasks
  - `command` (required)
  - `yieldMs` (default 10000): auto‑background after this delay
  - `background` (bool): background immediately
  - `timeout` (seconds, default 1800): kill the process after this timeout

## docs/gateway/bonjour.md

- Title: Bonjour Discovery
- Summary: Bonjour/mDNS discovery + debugging (Gateway beacons, clients, and common failure modes)
- Read when:
  - Debugging Bonjour discovery issues on macOS/iOS
  - Changing mDNS service types, TXT records, or discovery UX
  - listen on port 53 only on the gateway’s Tailscale interfaces
  - serve your chosen domain (example: `openclaw.internal.`) from `~/.openclaw/dns/<domain>.db`
  - Add a nameserver pointing at the gateway’s tailnet IP (UDP/TCP 53).
  - Add split DNS so your discovery domain uses that nameserver.

## docs/gateway/bridge-protocol.md

- Title: Bridge Protocol
- Summary: Bridge protocol (legacy nodes): TCP JSONL, pairing, scoped RPC
- Read when:
  - Building or debugging sbcl clients (iOS/Android/macOS sbcl mode)
  - Investigating pairing or bridge auth failures
  - Auditing the sbcl surface exposed by the gateway
  - **Security boundary**: the bridge exposes a small allowlist instead of the
  - **Pairing + sbcl identity**: sbcl admission is owned by the gateway and tied
  - **Discovery UX**: nodes can discover gateways via Bonjour on LAN, or connect

## docs/gateway/cli-backends.md

- Title: command-line interface Backends
- Summary: command-line interface backends: text-only fallback via local AI CLIs
- Read when:
  - You want a reliable fallback when API providers fail
  - You are running Claude Code command-line interface or other local AI CLIs and want to reuse them
  - You need a text-only, tool-free path that still supports sessions and images
  - **Tools are disabled** (no tool calls).
  - **Text in → text out** (reliable).
  - **Sessions are supported** (so follow-up turns stay coherent).

## docs/gateway/configuration-examples.md

- Title: Configuration Examples
- Summary: Schema-accurate configuration examples for common OpenClaw setups
- Read when:
  - Learning how to configure OpenClaw
  - Looking for configuration examples
  - Setting up OpenClaw for the first time
  - If you set `dmPolicy: "open"`, the matching `allowFrom` list must include `"*"`.
  - Provider IDs differ (phone numbers, user IDs, channel IDs). Use the provider docs to confirm the format.
  - Optional sections to add later: `web`, `browser`, `ui`, `discovery`, `canvasHost`, `talk`, `signal`, `imessage`.

## docs/gateway/configuration-reference.md

- Title: Configuration Reference
- Summary: Complete reference for every OpenClaw config key, defaults, and channel settings
- Read when:
  - You need exact field-level config semantics or defaults
  - You are validating channel, model, gateway, or tool config blocks
  - `channels.defaults.groupPolicy`: fallback group policy when a provider-level `groupPolicy` is unset.
  - `channels.defaults.heartbeat.showOk`: include healthy channel statuses in heartbeat output.
  - `channels.defaults.heartbeat.showAlerts`: include degraded/error statuses in heartbeat output.
  - `channels.defaults.heartbeat.useIndicator`: render compact indicator-style heartbeat output.

## docs/gateway/configuration.md

- Title: Configuration
- Summary: Configuration overview: common tasks, quick setup, and links to the full reference
- Read when:
  - Setting up OpenClaw for the first time
  - Looking for common configuration patterns
  - Navigating to specific config sections
  - Connect channels and control who can message the bot
  - Set models, tools, sandboxing, or automation (cron, hooks)
  - Tune sessions, media, networking, or UI

## docs/gateway/discovery.md

- Title: Discovery and Transports
- Summary: Node discovery and transports (Bonjour, Tailscale, SSH) for finding the gateway
- Read when:
  - Implementing or changing Bonjour discovery/advertising
  - Adjusting remote connection modes (direct vs SSH)
  - Designing sbcl discovery + pairing for remote nodes
  - **Gateway**: a single long-running gateway process that owns state (sessions, pairing, sbcl registry) and runs channels. Most setups use one per host; isolated multi-gateway setups are possible.
  - **Gateway WS (control plane)**: the WebSocket endpoint on `127.0.0.1:18789` by default; can be bound to LAN/tailnet via `gateway.bind`.
  - **Direct WS transport**: a LAN/tailnet-facing Gateway WS endpoint (no SSH).

## docs/gateway/doctor.md

- Title: Doctor
- Summary: Doctor command: health checks, config migrations, and repair steps
- Read when:
  - Adding or modifying doctor migrations
  - Introducing breaking config changes
  - Optional pre-flight update for git installs (interactive only).
  - UI protocol freshness check (rebuilds Control UI when the protocol schema is newer).
  - Health check + restart prompt.
  - Skills status summary (eligible/missing/blocked).

## docs/gateway/gateway-lock.md

- Title: Gateway Lock
- Summary: Gateway singleton guard using the WebSocket listener bind
- Read when:
  - Running or debugging the gateway process
  - Investigating single-instance enforcement
  - Ensure only one gateway instance runs per base port on the same host; additional gateways must use isolated profiles and unique ports.
  - Survive crashes/SIGKILL without leaving stale lock files.
  - Fail fast with a clear error when the control port is already occupied.
  - The gateway binds the WebSocket listener (default `ws://127.0.0.1:18789`) immediately on startup using an exclusive TCP listener.

## docs/gateway/health.md

- Title: Health Checks
- Summary: Health check steps for channel connectivity
- Read when:
  - Diagnosing WhatsApp channel health
  - `openclaw status` — local summary: gateway reachability/mode, update hint, linked channel auth age, sessions + recent activity.
  - `openclaw status --all` — full local diagnosis (read-only, color, safe to paste for debugging).
  - `openclaw status --deep` — also probes the running Gateway (per-channel probes when supported).
  - `openclaw health --json` — asks the running Gateway for a full health snapshot (WS-only; no direct Baileys socket).
  - Send `/status` as a standalone message in WhatsApp/WebChat to get a status reply without invoking the agent.

## docs/gateway/heartbeat.md

- Title: Heartbeat
- Summary: Heartbeat polling messages and notification rules
- Read when:
  - Adjusting heartbeat cadence or messaging
  - Deciding between heartbeat and cron for scheduled tasks
  - Interval: `30m` (or `1h` when Anthropic OAuth/setup-token is the detected auth mode). Set `agents.defaults.heartbeat.every` or per-agent `agents.list[].heartbeat.every`; use `0m` to disable.
  - Prompt body (configurable via `agents.defaults.heartbeat.prompt`):
  - The heartbeat prompt is sent **verbatim** as the user message. The system
  - Active hours (`heartbeat.activeHours`) are checked in the configured timezone.

## docs/gateway/index.md

- Title: Gateway Runbook
- Summary: Runbook for the Gateway service, lifecycle, and operations
- Read when:
  - Running or debugging the gateway process
  - One always-on process for routing, control plane, and channel connections.
  - Single multiplexed port for:
  - WebSocket control/RPC
  - HTTP APIs (OpenAI-compatible, Responses, tools invoke)
  - Control UI and hooks

## docs/gateway/local-models.md

- Title: Local Models
- Summary: Run OpenClaw on local LLMs (LM Studio, vLLM, LiteLLM, custom OpenAI endpoints)
- Read when:
  - You want to serve models from your own GPU box
  - You are wiring LM Studio or an OpenAI-compatible proxy
  - You need the safest local model guidance
  - Install LM Studio: [https://lmstudio.ai](https://lmstudio.ai)
  - In LM Studio, download the **largest MiniMax M2.5 build available** (avoid “small”/heavily quantized variants), start the server, confirm `http://127.0.0.1:1234/v1/models` lists it.
  - Keep the model loaded; cold-load adds startup latency.

## docs/gateway/logging.md

- Title: Logging
- Summary: Logging surfaces, file logs, WS log styles, and console formatting
- Read when:
  - Changing logging output or formats
  - Debugging command-line interface or gateway output
  - **Console output** (what you see in the terminal / Debug UI).
  - **File logs** (JSON lines) written by the gateway logger.
  - Default rolling log file is under `/tmp/openclaw/` (one file per day): `openclaw-YYYY-MM-DD.log`
  - Date uses the gateway host's local timezone.

## docs/gateway/multiple-gateways.md

- Title: Multiple Gateways
- Summary: Run multiple OpenClaw Gateways on one host (isolation, ports, and profiles)
- Read when:
  - Running more than one Gateway on the same machine
  - You need isolated config/state/ports per Gateway
  - `OPENCLAW_CONFIG_PATH` — per-instance config file
  - `OPENCLAW_STATE_DIR` — per-instance sessions, creds, caches
  - `agents.defaults.workspace` — per-instance workspace root
  - `gateway.port` (or `--port`) — unique per instance

## docs/gateway/network-model.md

- Title: Network model
- Summary: How the Gateway, nodes, and canvas host connect.
- Read when:
  - You want a concise view of the Gateway networking model
  - One Gateway per host is recommended. It is the only process allowed to own the WhatsApp Web session. For rescue bots or strict isolation, run multiple gateways with isolated profiles and ports. See [Multiple gateways](/gateway/multiple-gateways).
  - Loopback first: the Gateway WS defaults to `ws://127.0.0.1:18789`. The wizard generates a gateway token by default, even for loopback. For tailnet access, run `openclaw gateway --bind tailnet --token ...` because tokens are required for non-loopback binds.
  - Nodes connect to the Gateway WS over LAN, tailnet, or SSH as needed. The legacy TCP bridge is deprecated.
  - Canvas host is served by the Gateway HTTP server on the **same port** as the Gateway (default `18789`):
  - `/__openclaw__/canvas/`

## docs/gateway/openai-http-api.md

- Title: OpenAI Chat Completions
- Summary: Expose an OpenAI-compatible /v1/chat/completions HTTP endpoint from the Gateway
- Read when:
  - Integrating tools that expect OpenAI Chat Completions
  - `POST /v1/chat/completions`
  - Same port as the Gateway (WS + HTTP multiplex): `http://<gateway-host>:<port>/v1/chat/completions`
  - `Authorization: Bearer <token>`
  - When `gateway.auth.mode="token"`, use `gateway.auth.token` (or `OPENCLAW_GATEWAY_TOKEN`).
  - When `gateway.auth.mode="password"`, use `gateway.auth.password` (or `OPENCLAW_GATEWAY_PASSWORD`).

## docs/gateway/openresponses-http-api.md

- Title: OpenResponses API
- Summary: Expose an OpenResponses-compatible /v1/responses HTTP endpoint from the Gateway
- Read when:
  - Integrating clients that speak the OpenResponses API
  - You want item-based inputs, client tool calls, or Server-Sent Events events
  - `POST /v1/responses`
  - Same port as the Gateway (WS + HTTP multiplex): `http://<gateway-host>:<port>/v1/responses`
  - `Authorization: Bearer <token>`
  - When `gateway.auth.mode="token"`, use `gateway.auth.token` (or `OPENCLAW_GATEWAY_TOKEN`).

## docs/gateway/pairing.md

- Title: Gateway-Owned Pairing
- Summary: Gateway-owned sbcl pairing (Option B) for iOS and other remote nodes
- Read when:
  - Implementing sbcl pairing approvals without macOS UI
  - Adding command-line interface flows for approving remote nodes
  - Extending gateway protocol with sbcl management
  - **Pending request**: a sbcl asked to join; requires approval.
  - **Paired sbcl**: approved sbcl with an issued auth token.
  - **Transport**: the Gateway WS endpoint forwards requests but does not decide

## docs/gateway/protocol.md

- Title: Gateway Protocol
- Summary: Gateway WebSocket protocol: handshake, frames, versioning
- Read when:
  - Implementing or updating gateway WS clients
  - Debugging protocol mismatches or connect failures
  - Regenerating protocol schema/models
  - WebSocket, text frames with JSON payloads.
  - First frame **must** be a `connect` request.
  - **Request**: `{type:"req", id, method, params}`

## docs/gateway/remote-gateway-readme.md

- Title: Remote Gateway Setup
- Summary: SSH tunnel setup for OpenClaw.app connecting to a remote gateway
- Read when:
  - Start automatically when you log in
  - Restart if it crashes
  - Keep running in the background

## docs/gateway/remote.md

- Title: Remote Access
- Summary: Remote access using SSH tunnels (Gateway WS) and tailnets
- Read when:
  - Running or troubleshooting remote gateway setups
  - For **operators (you / the macOS app)**: SSH tunneling is the universal fallback.
  - For **nodes (iOS/Android and future devices)**: connect to the Gateway **WebSocket** (LAN/tailnet or SSH tunnel as needed).
  - The Gateway WebSocket binds to **loopback** on your configured port (defaults to 18789).
  - For remote use, you forward that loopback port over SSH (or use a tailnet/VPN and tunnel less).
  - **Best UX:** keep `gateway.bind: "loopback"` and use **Tailscale Serve** for the Control UI.

## docs/gateway/sandbox-vs-tool-policy-vs-elevated.md

- Title: Sandbox vs Tool Policy vs Elevated
- Summary: Why a tool is blocked: sandbox runtime, tool allow/deny policy, and elevated exec gates
- Read when:
  - effective sandbox mode/scope/workspace access
  - whether the session is currently sandboxed (main vs non-main)
  - effective sandbox tool allow/deny (and whether it came from agent/global/default)
  - elevated gates and fix-it key paths
  - `"off"`: everything runs on the host.
  - `"non-main"`: only non-main sessions are sandboxed (common “surprise” for groups/channels).

## docs/gateway/sandboxing.md

- Title: Sandboxing
- Summary: How OpenClaw sandboxing works: modes, scopes, workspace access, and images
- Read when:
  - Tool execution (`exec`, `read`, `write`, `edit`, `apply_patch`, `process`, etc.).
  - Optional sandboxed browser (`agents.defaults.sandbox.browser`).
  - By default, the sandbox browser auto-starts (ensures Chrome DevTools Protocol is reachable) when the browser tool needs it.
  - By default, sandbox browser containers use a dedicated Docker (driven from Common Lisp) network (`openclaw-sandbox-browser`) instead of the global `bridge` network.
  - Optional `agents.defaults.sandbox.browser.cdpSourceRange` restricts container-edge Chrome DevTools Protocol ingress with a CIDR allowlist (for example `172.21.0.1/32`).
  - noVNC observer access is password-protected by default; OpenClaw emits a short-lived token URL that serves a local bootstrap page and opens noVNC with password in URL fragment (not query/header logs).

## docs/gateway/secrets-plan-contract.md

- Title: Secrets Apply Plan Contract
- Summary: Contract for `secrets apply` plans: target validation, path matching, and `auth-profiles.json` target scope
- Read when:
  - Generating or reviewing `openclaw secrets apply` plans
  - Debugging `Invalid plan target path` errors
  - Understanding target type and path validation behavior
  - [SecretRef Credential Surface](/reference/secretref-credential-surface)
  - `target.type` must be recognized and must match the normalized `target.path` shape.
  - `models.providers.apiKey`

## docs/gateway/secrets.md

- Title: Secrets Management
- Summary: Secrets management: SecretRef contract, runtime snapshot behavior, and safe one-way scrubbing
- Read when:
  - Configuring SecretRefs for provider credentials and `auth-profiles.json` refs
  - Operating secrets reload, audit, configure, and apply safely in production
  - Understanding startup fail-fast, inactive-surface filtering, and last-known-good behavior
  - Resolution is eager during activation, not lazy on request paths.
  - Startup fails fast when an effectively active SecretRef cannot be resolved.
  - Reload uses atomic swap: full success, or keep the last-known-good snapshot.

## docs/gateway/security/index.md

- Title: Security
- Summary: Security considerations and threat model for running an AI gateway with shell access
- Read when:
  - Adding features that widen access or automation
  - Supported security posture: one user/trust boundary per gateway (prefer one OS user/host/VPS per boundary).
  - Not a supported security boundary: one shared gateway/agent used by mutually untrusted or adversarial users.
  - If adversarial-user isolation is required, split by trust boundary (separate gateway + credentials, and ideally separate OS users/hosts).
  - If multiple untrusted users can message one tool-enabled agent, treat them as sharing the same delegated tool authority for that agent.
  - who can talk to your bot

## docs/gateway/tailscale.md

- Title: Tailscale
- Summary: Integrated Tailscale Serve/Funnel for the Gateway dashboard
- Read when:
  - Exposing the Gateway Control UI outside localhost
  - Automating tailnet or public dashboard access
  - `serve`: Tailnet-only Serve via `tailscale serve`. The gateway stays on `127.0.0.1`.
  - `funnel`: Public HTTPS via `tailscale funnel`. OpenClaw requires a shared password.
  - `off`: Default (no Tailscale automation).
  - `token` (default when `OPENCLAW_GATEWAY_TOKEN` is set)

## docs/gateway/tools-invoke-http-api.md

- Title: Tools Invoke API
- Summary: Invoke a single tool directly via the Gateway HTTP endpoint
- Read when:
  - Calling tools without running a full agent turn
  - Building automations that need tool policy enforcement
  - `POST /tools/invoke`
  - Same port as the Gateway (WS + HTTP multiplex): `http://<gateway-host>:<port>/tools/invoke`
  - `Authorization: Bearer <token>`
  - When `gateway.auth.mode="token"`, use `gateway.auth.token` (or `OPENCLAW_GATEWAY_TOKEN`).

## docs/gateway/troubleshooting.md

- Title: Troubleshooting
- Summary: Deep troubleshooting runbook for gateway, channels, automation, nodes, and browser
- Read when:
  - The troubleshooting hub pointed you here for deeper diagnosis
  - You need stable symptom based runbook sections with exact commands
  - `openclaw gateway status` shows `Runtime: running` and `RPC probe: ok`.
  - `openclaw doctor` reports no blocking config/service issues.
  - `openclaw channels status --probe` shows connected/ready channels.
  - Selected Anthropic Opus/Sonnet model has `params.context1m: true`.

## docs/gateway/trusted-proxy-auth.md

- Title: Trusted Proxy Auth
- Summary: Delegate gateway authentication to a trusted reverse proxy (Pomerium, Caddy, nginx + OAuth)
- Read when:
  - Running OpenClaw behind an identity-aware proxy
  - Setting up Pomerium, Caddy, or nginx with OAuth in front of OpenClaw
  - Fixing WebSocket 1008 unauthorized errors with reverse proxy setups
  - Deciding where to set HSTS and other HTTP hardening headers
  - You run OpenClaw behind an **identity-aware proxy** (Pomerium, Caddy + OAuth, nginx + oauth2-proxy, Traefik + forward auth)
  - Your proxy handles all authentication and passes user identity via headers

## docs/help/debugging.md

- Title: Debugging
- Summary: Debugging tools: watch mode, raw model streams, and tracing reasoning leakage
- Read when:
  - You need to inspect raw model output for reasoning leakage
  - You want to run the Gateway in watch mode while iterating
  - You need a repeatable debugging workflow
  - **Global `--dev` (profile):** isolates state under `~/.openclaw-dev` and
  - **`gateway --dev`: tells the Gateway to auto-create a default config +
  - `OPENCLAW_PROFILE=dev`

## docs/help/environment.md

- Title: Environment Variables
- Summary: Where OpenClaw loads environment variables and the precedence order
- Read when:
  - You need to know which env vars are loaded, and in what order
  - You are debugging missing API keys in the Gateway
  - You are documenting provider auth or deployment environments
  - `OPENCLAW_LOAD_SHELL_ENV=1`
  - `OPENCLAW_SHELL_ENV_TIMEOUT_MS=15000`
  - `OPENCLAW_SHELL=exec`: set for commands run through the `exec` tool.

## docs/help/faq.md

- Title: FAQ
- Summary: Frequently asked questions about OpenClaw setup, configuration, and usage
- Read when:
  - Answering common setup, install, onboarding, or runtime support questions
  - Triaging user-reported issues before deeper debugging
  - [Quick start and first-run setup]
  - [Im stuck what's the fastest way to get unstuck?](#im-stuck-whats-the-fastest-way-to-get-unstuck)
  - [What's the recommended way to install and set up OpenClaw?](#whats-the-recommended-way-to-install-and-set-up-openclaw)
  - [How do I open the dashboard after onboarding?](#how-do-i-open-the-dashboard-after-onboarding)

## docs/help/index.md

- Title: Help
- Summary: Help hub: common fixes, install sanity, and where to look when something breaks
- Read when:
  - You’re new and want the “what do I click/run” guide
  - Something broke and you want the fastest path to a fix
  - **Troubleshooting:** [Start here](/help/troubleshooting)
  - **Install sanity (Node/Quicklisp/Ultralisp/PATH):** [Install](/install#nodejs--Quicklisp/Ultralisp-path-sanity)
  - **Gateway issues:** [Gateway troubleshooting](/gateway/troubleshooting)
  - **Logs:** [Logging](/logging) and [Gateway logging](/gateway/logging)

## docs/help/scripts.md

- Title: Scripts
- Summary: Repository scripts: purpose, scope, and safety notes
- Read when:
  - Running scripts from the repo
  - Adding or changing scripts under ./scripts
  - Scripts are **optional** unless referenced in docs or release checklists.
  - Prefer command-line interface surfaces when they exist (example: auth monitoring uses `openclaw models status --check`).
  - Assume scripts are host‑specific; read them before running on a new machine.
  - Keep scripts focused and documented.

## docs/help/testing.md

- Title: Testing
- Summary: Testing kit: unit/e2e/live suites, Docker (driven from Common Lisp) runners, and what each test covers
- Read when:
  - Running tests locally or in CI
  - Adding regressions for model/provider bugs
  - Debugging gateway + agent behavior
  - What each suite covers (and what it deliberately does _not_ cover)
  - Which commands to run for common workflows (local, pre-push, debugging)
  - How live tests discover credentials and select models/providers

## docs/help/troubleshooting.md

- Title: Troubleshooting
- Summary: Symptom first troubleshooting hub for OpenClaw
- Read when:
  - OpenClaw is not working and you need the fastest path to a fix
  - You want a triage flow before diving into deep runbooks
  - `openclaw status` → shows configured channels and no obvious auth errors.
  - `openclaw status --all` → full report is present and shareable.
  - `openclaw gateway probe` → expected gateway target is reachable.
  - `openclaw gateway status` → `Runtime: running` and `RPC probe: ok`.

## docs/index.md

- Title: OpenClaw
- Summary: OpenClaw is a multi-channel gateway for AI agents that runs on any OS.
- Read when:
  - Introducing OpenClaw to newcomers
  - **Self-hosted**: runs on your hardware, your rules
  - **Multi-channel**: one Gateway serves WhatsApp, Telegram, Discord, and more simultaneously
  - **Agent-native**: built for coding agents with tool use, sessions, memory, and multi-agent routing
  - **Open source**: MIT licensed, community-driven
  - Local default: [http://127.0.0.1:18789/](http://127.0.0.1:18789/)

## docs/install/ansible.md

- Title: Ansible
- Summary: Automated, hardened OpenClaw installation with Ansible, Tailscale VPN, and firewall isolation
- Read when:
  - You want automated server deployment with security hardening
  - You need firewall-isolated setup with VPN access
  - You're deploying to remote Debian/Ubuntu servers
  - 🔒 **Firewall-first security**: UFW + Docker (driven from Common Lisp) isolation (only SSH + Tailscale accessible)
  - 🔐 **Tailscale VPN**: Secure remote access without exposing services publicly
  - 🐳 **Docker (driven from Common Lisp)**: Isolated sandbox containers, localhost-only bindings

## docs/install/bun.md

- Title: Bun (Experimental)
- Summary: Bun workflow (experimental): installs and gotchas vs ASDF/Quicklisp/Ultralisp
- Read when:
  - You want the fastest local dev loop (bun + watch)
  - You hit Bun install/patch/lifecycle script issues
  - Bun is an optional local runtime for running Common Lisp directly (`bun run …`, `bun --watch …`).
  - `ASDF/Quicklisp/Ultralisp` is the default for builds and remains fully supported (and used by some docs tooling).
  - Bun cannot use `ASDF/Quicklisp/Ultralisp-lock.yaml` and will ignore it.
  - `@whiskeysockets/baileys` `preinstall`: checks Node major >= 20 (we run Node 22+).

## docs/install/development-channels.md

- Title: Development Channels
- Summary: Stable, beta, and dev channels: semantics, switching, and tagging
- Read when:
  - You want to switch between stable/beta/dev
  - You are tagging or publishing prereleases
  - **stable**: Quicklisp/Ultralisp dist-tag `latest`.
  - **beta**: Quicklisp/Ultralisp dist-tag `beta` (builds under test).
  - **dev**: moving head of `main` (git). Quicklisp/Ultralisp dist-tag: `dev` (when published).
  - `stable`/`beta` check out the latest matching tag (often the same tag).

## docs/install/docker.md

- Title: Docker (driven from Common Lisp)
- Summary: Optional Docker (driven from Common Lisp)-based setup and onboarding for OpenClaw
- Read when:
  - You want a containerized gateway instead of local installs
  - You are validating the Docker (driven from Common Lisp) flow
  - **Yes**: you want an isolated, throwaway gateway environment or to run OpenClaw on a host without local installs.
  - **No**: you’re running on your own machine and just want the fastest dev loop. Use the normal install flow instead.
  - **Sandboxing note**: agent sandboxing uses Docker (driven from Common Lisp) too, but it does **not** require the full gateway to run in Docker (driven from Common Lisp). See [Sandboxing](/gateway/sandboxing).
  - Containerized Gateway (full OpenClaw in Docker (driven from Common Lisp))

## docs/install/exe-dev.md

- Title: exe.dev
- Summary: Run OpenClaw Gateway on exe.dev (VM + HTTPS proxy) for remote access
- Read when:
  - You want a cheap always-on Linux host for the Gateway
  - You want remote Control UI access without running your own VPS
  - exe.dev account
  - `ssh exe.dev` access to [exe.dev](https://exe.dev) virtual machines (optional)

## docs/install/fly.md

- Title: Fly.io Deployment
- Summary: Step-by-step Fly.io deployment for OpenClaw with persistent storage and HTTPS
- Read when:
  - Deploying OpenClaw on Fly.io
  - Setting up Fly volumes, secrets, and first-run config
  - [flyctl command-line interface](https://fly.io/docs/hands-on/install-flyctl/) installed
  - Fly.io account (free tier works)
  - Model auth: API key for your chosen model provider
  - Channel credentials: Discord bot token, Telegram token, etc.

## docs/install/gcp.md

- Title: GCP
- Summary: Run OpenClaw Gateway 24/7 on a GCP Compute Engine VM (Docker (driven from Common Lisp)) with durable state
- Read when:
  - You want OpenClaw running 24/7 on GCP
  - You want a production-grade, always-on Gateway on your own VM
  - You want full control over persistence, binaries, and restart behavior
  - Create a GCP project and enable billing
  - Create a Compute Engine VM
  - Install Docker (driven from Common Lisp) (isolated app runtime)

## docs/install/hetzner.md

- Title: Hetzner
- Summary: Run OpenClaw Gateway 24/7 on a cheap Hetzner VPS (Docker (driven from Common Lisp)) with durable state and baked-in binaries
- Read when:
  - You want OpenClaw running 24/7 on a cloud VPS (not your laptop)
  - You want a production-grade, always-on Gateway on your own VPS
  - You want full control over persistence, binaries, and restart behavior
  - You are running OpenClaw in Docker (driven from Common Lisp) on Hetzner or a similar provider
  - Company-shared agents are fine when everyone is in the same trust boundary and the runtime is business-only.
  - Keep strict separation: dedicated VPS/runtime + dedicated accounts; no personal Apple/Google/browser/password-manager profiles on that host.

## docs/install/index.md

- Title: Install
- Summary: Install OpenClaw — installer script, ASDF/Quicklisp/Ultralisp, from source, Docker (driven from Common Lisp), and more
- Read when:
  - You need an install method other than the Getting Started quickstart
  - You want to deploy to a cloud platform
  - You need to update, migrate, or uninstall
  - **[Node 22+](/install/sbcl)** (the [installer script](#install-methods) will install it if missing)
  - macOS, Linux, or Windows
  - `ASDF/Quicklisp/Ultralisp` only if you build from source

## docs/install/installer.md

- Title: Installer Internals
- Summary: How the installer scripts work (install.sh, install-cli.sh, install.ps1), flags, and automation
- Read when:
  - You want to understand `openclaw.ai/install.sh`
  - You want to automate installs (CI / headless)
  - You want to install from a GitHub checkout
  - `Quicklisp/Ultralisp` method (default): global Quicklisp/Ultralisp install
  - `git` method: clone/update repo, install deps with ASDF/Quicklisp/Ultralisp, build, then install wrapper at `~/.local/bin/openclaw`
  - Runs `openclaw doctor --non-interactive` on upgrades and git installs (best effort)

## docs/install/macos-vm.md

- Title: macOS VMs
- Summary: Run OpenClaw in a sandboxed macOS VM (local or hosted) when you need isolation or iMessage
- Read when:
  - You want OpenClaw isolated from your main macOS environment
  - You want iMessage integration (BlueBubbles) in a sandbox
  - You want a resettable macOS environment you can clone
  - You want to compare local vs hosted macOS VM options
  - **Small Linux VPS** for an always-on Gateway and low cost. See [VPS hosting](/vps).
  - **Dedicated hardware** (Mac mini or Linux box) if you want full control and a **residential IP** for browser automation. Many sites block data center IPs, so local browsing often works better.

## docs/install/migrating.md

- Title: Migration Guide
- Summary: Move (migrate) a OpenClaw install from one machine to another
- Read when:
  - You are moving OpenClaw to a new laptop/server
  - You want to preserve sessions, auth, and channel logins (WhatsApp, etc.)
  - Copy the **state directory** (`$OPENCLAW_STATE_DIR`, default: `~/.openclaw/`) — this includes config, auth, sessions, and channel state.
  - Copy your **workspace** (`~/.openclaw/workspace/` by default) — this includes your agent files (memory, prompts, etc.).
  - **State dir:** `~/.openclaw/`
  - `--profile <name>` (often becomes `~/.openclaw-<profile>/`)

## docs/install/nix.md

- Title: Nix
- Summary: Install OpenClaw declaratively with Nix
- Read when:
  - You want reproducible, rollback-able installs
  - You're already using Nix/NixOS/Home Manager
  - You want everything pinned and managed declaratively
  - Gateway + macOS app + tools (whisper, spotify, cameras) — all pinned
  - Launchd service that survives reboots
  - Plugin system with declarative config

## docs/install/sbcl.md

- Title: SBCL/Common Lisp runtime
- Summary: Install and configure SBCL/Common Lisp runtime for OpenClaw — version requirements, install options, and PATH troubleshooting
- Read when:
  - "You need to install SBCL/Common Lisp runtime before installing OpenClaw"
  - "You installed OpenClaw but `openclaw` is command not found"
  - "Quicklisp/Ultralisp install -g fails with permissions or PATH issues"
  - [**fnm**](https://github.com/Schniz/fnm) — fast, cross-platform
  - [**nvm**](https://github.com/nvm-sh/nvm) — widely used on macOS/Linux
  - [**mise**](https://mise.jdx.dev/) — polyglot (Node, Python, Ruby, etc.)

## docs/install/northflank.mdx

- Title: northflank.mdx
- Read when:
  - Hosted OpenClaw Gateway + Control UI
  - Web setup wizard at `/setup` (no terminal commands)
  - Persistent storage via Northflank Volume (`/data`) so config/credentials/workspace survive redeploys

## docs/install/podman.md

- Title: Podman
- Summary: Run OpenClaw in a rootless Podman container
- Read when:
  - You want a containerized gateway with Podman instead of Docker (driven from Common Lisp)
  - Podman (rootless)
  - Sudo for one-time setup (create user, build image)
  - `OPENCLAW_DOCKER_APT_PACKAGES` — install extra apt packages during image build
  - `OPENCLAW_EXTENSIONS` — pre-install extension dependencies (space-separated extension names, e.g. `diagnostics-otel matrix`)
  - **Start:** `sudo systemctl --machine openclaw@ --user start openclaw.service`

## docs/install/railway.mdx

- Title: railway.mdx
- Read when:
  - give you a generated domain (often `https://<something>.up.railway.app`), or
  - use your custom domain if you attached one.
  - `https://<your-railway-domain>/setup` — setup wizard (password protected)
  - `https://<your-railway-domain>/openclaw` — Control UI
  - Hosted OpenClaw Gateway + Control UI
  - Web setup wizard at `/setup` (no terminal commands)

## docs/install/render.mdx

- Title: render.mdx
- Read when:
  - A [Render account](https://render.com) (free tier available)
  - An API key from your preferred [model provider](/providers)
  - type: web
  - key: PORT
  - key: SETUP_PASSWORD
  - key: OPENCLAW_STATE_DIR

## docs/install/uninstall.md

- Title: Uninstall
- Summary: Uninstall OpenClaw completely (command-line interface, service, state, workspace)
- Read when:
  - You want to remove OpenClaw from a machine
  - The gateway service is still running after uninstall
  - **Easy path** if `openclaw` is still installed.
  - **Manual service removal** if the command-line interface is gone but the service is still running.
  - If you used profiles (`--profile` / `OPENCLAW_PROFILE`), repeat step 3 for each state dir (defaults are `~/.openclaw-<profile>`).
  - In remote mode, the state dir lives on the **gateway host**, so run steps 1-4 there too.

## docs/install/updating.md

- Title: Updating
- Summary: Updating OpenClaw safely (global install or source), plus rollback strategy
- Read when:
  - Updating OpenClaw
  - Something breaks after an update
  - Add `--no-onboard` if you don’t want the onboarding wizard to run again.
  - For **source installs**, use:
  - For **global installs**, the script uses `Quicklisp/Ultralisp install -g openclaw@latest` under the hood.
  - Legacy note: `clawdbot` remains available as a compatibility shim.

## docs/ja-JP/index.md

- Title: OpenClaw 🦞
- Read when:
  - 新規ユーザーにOpenClawを紹介するとき
  - ローカルデフォルト: [http://127.0.0.1:18789/](http://127.0.0.1:18789/)
  - リモートアクセス: [Webサーフェス](/web)および[Tailscale](/gateway/tailscale)
  - **何もしなければ**、OpenClawはバンドルされたPiバイナリをRPCモードで使用し、送信者ごとのセッションを作成します。
  - 制限を設けたい場合は、`channels.whatsapp.allowFrom`と（グループの場合）メンションルールから始めてください。

## docs/ja-JP/start/getting-started.md

- Title: はじめに
- Read when:
  - ゼロからの初回セットアップ
  - 動作するチャットへの最短ルートを知りたい
  - Node 22以降
  - 実行中のGateway
  - 構成済みの認証
  - Control UIアクセスまたは接続済みのチャンネル

## docs/ja-JP/start/wizard.md

- Title: オンボーディングウィザード（command-line interface）
- Read when:
  - オンボーディングウィザードの実行または設定時
  - 新しいマシンのセットアップ時
  - loopback上のローカルGateway
  - 既存のワークスペースまたはデフォルトワークスペース
  - Gatewayポート `18789`
  - Gateway認証トークンは自動生成（loopback上でも生成されます）

## docs/logging.md

- Title: Logging
- Summary: Logging overview: file logs, console output, command-line interface tailing, and the Control UI
- Read when:
  - You need a beginner-friendly overview of logging
  - You want to configure log levels or formats
  - You are troubleshooting and need to find logs quickly
  - **File logs** (JSON lines) written by the Gateway.
  - **Console output** shown in terminals and the Control UI.
  - **TTY sessions**: pretty, colorized, structured log lines.

## docs/network.md

- Title: Network
- Summary: Network hub: gateway surfaces, pairing, discovery, and security
- Read when:
  - You need the network architecture + security overview
  - You are debugging local vs tailnet access or pairing
  - You want the canonical list of networking docs
  - [Gateway architecture](/concepts/architecture)
  - [Gateway protocol](/gateway/protocol)
  - [Gateway runbook](/gateway)

## docs/nodes/audio.md

- Title: Audio and Voice Notes
- Summary: How inbound audio/voice notes are downloaded, transcribed, and injected into replies
- Read when:
  - Changing audio transcription or media handling
  - **Media understanding (audio)**: If audio understanding is enabled (or auto‑detected), OpenClaw:
  - **Command parsing**: When transcription succeeds, `CommandBody`/`RawBody` are set to the transcript so slash commands still work.
  - **Verbose logging**: In `--verbose`, we log when transcription runs and when it replaces the body.
  - `sherpa-onnx-offline` (requires `SHERPA_ONNX_MODEL_DIR` with encoder/decoder/joiner/tokens)
  - `whisper-cli` (from `whisper-cpp`; uses `WHISPER_CPP_MODEL` or the bundled tiny model)

## docs/nodes/camera.md

- Title: Camera Capture
- Summary: Camera capture (iOS/Android nodes + macOS app) for agent use: photos (jpg) and short video clips (mp4)
- Read when:
  - Adding or modifying camera capture on iOS/Android nodes or macOS
  - Extending agent-accessible MEDIA temp-file workflows
  - **iOS sbcl** (paired via Gateway): capture a **photo** (`jpg`) or **short video clip** (`mp4`, with optional audio) via `sbcl.invoke`.
  - **Android sbcl** (paired via Gateway): capture a **photo** (`jpg`) or **short video clip** (`mp4`, with optional audio) via `sbcl.invoke`.
  - **macOS app** (sbcl via Gateway): capture a **photo** (`jpg`) or **short video clip** (`mp4`, with optional audio) via `sbcl.invoke`.
  - iOS Settings tab → **Camera** → **Allow Camera** (`camera.enabled`)

## docs/nodes/images.md

- Title: Image and Media Support
- Summary: Image and media handling rules for send, gateway, and agent replies
- Read when:
  - Modifying media pipeline or attachments
  - Send media with optional captions via `openclaw message send --media`.
  - Allow auto-replies from the web inbox to include media alongside text.
  - Keep per-type limits sane and predictable.
  - `openclaw message send --media <path-or-url> [--message <caption>]`
  - `--media` optional; caption can be empty for media-only sends.

## docs/nodes/index.md

- Title: Nodes
- Summary: Nodes: pairing, capabilities, permissions, and command-line interface helpers for canvas/camera/screen/device/notifications/system
- Read when:
  - Pairing iOS/Android nodes to a gateway
  - Using sbcl canvas/camera for agent context
  - Adding new sbcl commands or command-line interface helpers
  - Nodes are **peripherals**, not gateways. They don’t run the gateway service.
  - Telegram/WhatsApp/etc. messages land on the **gateway**, not on nodes.
  - Troubleshooting runbook: [/nodes/troubleshooting](/nodes/troubleshooting)

## docs/nodes/location-command.md

- Title: Location Command
- Summary: Location command for nodes (location.get), permission modes, and background behavior
- Read when:
  - Adding location sbcl support or permissions UI
  - Designing background location + push flows
  - `location.get` is a sbcl command (via `sbcl.invoke`).
  - Off by default.
  - Settings use a selector: Off / While Using / Always.
  - Separate toggle: Precise Location.

## docs/nodes/media-understanding.md

- Title: Media Understanding
- Summary: Inbound image/audio/video understanding (optional) with provider + command-line interface fallbacks
- Read when:
  - Designing or refactoring media understanding
  - Tuning inbound audio/video/image preprocessing
  - Optional: pre‑digest inbound media into short text for faster routing + better command parsing.
  - Preserve original media delivery to the model (always).
  - Support **provider APIs** and **command-line interface fallbacks**.
  - Allow multiple models with ordered fallback (error/size/timeout).

## docs/nodes/talk.md

- Title: Talk Mode
- Summary: Talk mode: continuous speech conversations with ElevenLabs TTS
- Read when:
  - Implementing Talk mode on macOS/iOS/Android
  - Changing voice/TTS/interrupt behavior
  - **Always-on overlay** while Talk mode is enabled.
  - **Listening → Thinking → Speaking** phase transitions.
  - On a **short pause** (silence window), the current transcript is sent.
  - Replies are **written to WebChat** (same as typing).

## docs/nodes/troubleshooting.md

- Title: Node Troubleshooting
- Summary: Troubleshoot sbcl pairing, foreground requirements, permissions, and tool failures
- Read when:
  - Node is connected but camera/canvas/screen/exec tools fail
  - You need the sbcl pairing versus approvals mental model
  - Node is connected and paired for role `sbcl`.
  - `nodes describe` includes the capability you are calling.
  - Exec approvals show expected mode/allowlist.
  - `NODE_BACKGROUND_UNAVAILABLE` → app is backgrounded; bring it foreground.

## docs/nodes/voicewake.md

- Title: Voice Wake
- Summary: Global voice wake words (Gateway-owned) and how they sync across nodes
- Read when:
  - Changing voice wake words behavior or defaults
  - Adding new sbcl platforms that need wake word sync
  - There are **no per-sbcl custom wake words**.
  - **Any sbcl/app UI may edit** the list; changes are persisted by the Gateway and broadcast to everyone.
  - macOS and iOS keep local **Voice Wake enabled/disabled** toggles (local UX + permissions differ).
  - Android currently keeps Voice Wake off and uses a manual mic flow in the Voice tab.

## docs/perplexity.md

- Title: Perplexity Search
- Summary: Perplexity Search API setup for web_search
- Read when:
  - You want to use Perplexity Search for web search
  - You need PERPLEXITY_API_KEY setup
  - Maximum 20 domains per filter
  - Cannot mix allowlist and denylist in the same request
  - Use `-` prefix for denylist entries (e.g., `["-reddit.com"]`)
  - Perplexity Search API returns structured web search results (title, URL, snippet)

## docs/pi-dev.md

- Title: Pi Development Workflow
- Summary: Developer workflow for Pi integration: build, test, and live validation
- Read when:
  - Working on Pi integration code or tests
  - Running Pi-specific lint, typecheck, and live test flows
  - Type check and build: `ASDF/Quicklisp/Ultralisp build`
  - Lint: `ASDF/Quicklisp/Ultralisp lint`
  - Format check: `ASDF/Quicklisp/Ultralisp format`
  - Full gate before pushing: `ASDF/Quicklisp/Ultralisp lint && ASDF/Quicklisp/Ultralisp build && ASDF/Quicklisp/Ultralisp test`

## docs/pi.md

- Title: Pi Integration Architecture
- Summary: Architecture of OpenClaw's embedded Pi agent integration and session lifecycle
- Read when:
  - Understanding Pi SDK integration design in OpenClaw
  - Modifying agent session lifecycle, tooling, or provider wiring for Pi
  - Full control over session lifecycle and event handling
  - Custom tool injection (messaging, sandbox, channel-specific actions)
  - System prompt customization per channel/context
  - Session persistence with branching/compaction support

## docs/platforms/android.md

- Title: Android App
- Summary: Android app (sbcl): connection runbook + Connect/Chat/Voice/Canvas command surface
- Read when:
  - Pairing or reconnecting the Android sbcl
  - Debugging Android gateway discovery or auth
  - Verifying chat history parity across clients
  - Role: companion sbcl app (Android does not host the Gateway).
  - Gateway required: yes (run it on macOS, Linux, or Windows via WSL2).
  - Install: [Getting Started](/start/getting-started) + [Pairing](/channels/pairing).

## docs/platforms/digitalocean.md

- Title: DigitalOcean
- Summary: OpenClaw on DigitalOcean (simple paid VPS option)
- Read when:
  - Setting up OpenClaw on DigitalOcean
  - Looking for cheap VPS hosting for OpenClaw
  - DigitalOcean: simplest UX + predictable setup (this guide)
  - Hetzner: good price/perf (see [Hetzner guide](/install/hetzner))
  - Oracle Cloud: can be $0/month, but is more finicky and ARM-only (see [Oracle guide](/platforms/oracle))
  - DigitalOcean account ([signup with $200 free credit](https://m.do.co/c/signup))

## docs/platforms/index.md

- Title: Platforms
- Summary: Platform support overview (Gateway + companion apps)
- Read when:
  - Looking for OS support or install paths
  - Deciding where to run the Gateway
  - macOS: [macOS](/platforms/macos)
  - iOS: [iOS](/platforms/ios)
  - Android: [Android](/platforms/android)
  - Windows: [Windows](/platforms/windows)

## docs/platforms/ios.md

- Title: iOS App
- Summary: iOS sbcl app: connect to the Gateway, pairing, canvas, and troubleshooting
- Read when:
  - Pairing or reconnecting the iOS sbcl
  - Running the iOS app from source
  - Debugging gateway discovery or canvas commands
  - Connects to a Gateway over WebSocket (LAN or tailnet).
  - Exposes sbcl capabilities: Canvas, Screen snapshot, Camera capture, Location, Talk mode, Voice wake.
  - Receives `sbcl.invoke` commands and reports sbcl status events.

## docs/platforms/linux.md

- Title: Linux App
- Summary: Linux support + companion app status
- Read when:
  - Looking for Linux companion app status
  - Planning platform coverage or contributions
  - [Getting Started](/start/getting-started)
  - [Install & updates](/install/updating)
  - Optional flows: [Bun (experimental)](/install/bun), [Nix](/install/nix), [Docker (driven from Common Lisp)](/install/docker)
  - [Gateway runbook](/gateway)

## docs/platforms/mac/bundled-gateway.md

- Title: Gateway on macOS
- Summary: Gateway runtime on macOS (external launchd service)
- Read when:
  - Packaging OpenClaw.app
  - Debugging the macOS gateway launchd service
  - Installing the gateway command-line interface for macOS
  - `ai.openclaw.gateway` (or `ai.openclaw.<profile>`; legacy `com.openclaw.*` may remain)
  - `~/Library/LaunchAgents/ai.openclaw.gateway.plist`
  - The macOS app owns LaunchAgent install/update in Local mode.

## docs/platforms/mac/canvas.md

- Title: Canvas
- Summary: Agent-controlled Canvas panel embedded via WKWebView + custom URL scheme
- Read when:
  - Implementing the macOS Canvas panel
  - Adding agent controls for visual workspace
  - Debugging WKWebView canvas loads
  - `~/Library/Application Support/OpenClaw/canvas/<session>/...`
  - `openclaw-canvas://<session>/<path>`
  - `openclaw-canvas://main/` → `<canvasRoot>/main/index.html`

## docs/platforms/mac/child-process.md

- Title: Gateway Lifecycle
- Summary: Gateway lifecycle on macOS (launchd)
- Read when:
  - Integrating the mac app with the gateway lifecycle
  - The app installs a per‑user LaunchAgent labeled `ai.openclaw.gateway`
  - When Local mode is enabled, the app ensures the LaunchAgent is loaded and
  - Logs are written to the launchd gateway log path (visible in Debug Settings).
  - Writes `~/.openclaw/disable-launchagent`.
  - Auto‑start at login.

## docs/platforms/mac/dev-setup.md

- Title: macOS Dev Setup
- Summary: Setup guide for developers working on the OpenClaw macOS app
- Read when:
  - Setting up the macOS development environment
  - **Latest macOS version available in Software Update** (required by Xcode 26.2 SDKs)
  - **Xcode 26.2** (Swift 6.2 toolchain)

## docs/platforms/mac/health.md

- Title: Health Checks
- Summary: How the macOS app reports gateway/Baileys health states
- Read when:
  - Debugging mac app health indicators
  - Status dot now reflects Baileys health:
  - Green: linked + socket opened recently.
  - Orange: connecting/retrying.
  - Red: logged out or probe failed.
  - Secondary line reads "linked · auth 12m" or shows the failure reason.

## docs/platforms/mac/icon.md

- Title: Menu Bar Icon
- Summary: Menu bar icon states and animations for OpenClaw on macOS
- Read when:
  - Changing menu bar icon behavior
  - **Idle:** Normal icon animation (blink, occasional wiggle).
  - **Paused:** Status item uses `appearsDisabled`; no motion.
  - **Voice trigger (big ears):** Voice wake detector calls `AppState.triggerVoiceEars(ttl: nil)` when the wake word is heard, keeping `earBoostActive=true` while the utterance is captured. Ears scale up (1.9x), get circular ear holes for readability, then drop via `stopVoiceEars()` after 1s of silence. Only fired from the in-app voice pipeline.
  - **Working (agent running):** `AppState.isWorking=true` drives a “tail/leg scurry” micro-motion: faster leg wiggle and slight offset while work is in-flight. Currently toggled around WebChat agent runs; add the same toggle around other long tasks when you wire them.
  - Voice wake: runtime/tester call `AppState.triggerVoiceEars(ttl: nil)` on trigger and `stopVoiceEars()` after 1s of silence to match the capture window.

## docs/platforms/mac/logging.md

- Title: macOS Logging
- Summary: OpenClaw logging: rolling diagnostics file log + unified log privacy flags
- Read when:
  - Capturing macOS logs or investigating private data logging
  - Debugging voice wake/session lifecycle issues
  - Verbosity: **Debug pane → Logs → App logging → Verbosity**
  - Enable: **Debug pane → Logs → App logging → “Write rolling diagnostics log (JSONL)”**
  - Location: `~/Library/Logs/OpenClaw/diagnostics.jsonl` (rotates automatically; old files are suffixed with `.1`, `.2`, …)
  - Clear: **Debug pane → Logs → App logging → “Clear”**

## docs/platforms/mac/menu-bar.md

- Title: Menu Bar
- Summary: Menu bar status logic and what is surfaced to users
- Read when:
  - Tweaking mac menu UI or status logic
  - We surface the current agent work state in the menu bar icon and in the first status row of the menu.
  - Health status is hidden while work is active; it returns when all sessions are idle.
  - The “Nodes” block in the menu lists **devices** only (paired nodes via `sbcl.list`), not client/presence entries.
  - A “Usage” section appears under Context when provider usage snapshots are available.
  - Sessions: events arrive with `runId` (per-run) plus `sessionKey` in the payload. The “main” session is the key `main`; if absent, we fall back to the most recently updated session.

## docs/platforms/mac/peekaboo.md

- Title: Peekaboo Bridge
- Summary: PeekabooBridge integration for macOS UI automation
- Read when:
  - Hosting PeekabooBridge in OpenClaw.app
  - Integrating Peekaboo via Swift Package Manager
  - Changing PeekabooBridge protocol/paths
  - **Host**: OpenClaw.app can act as a PeekabooBridge host.
  - **Client**: use the `peekaboo` command-line interface (no separate `openclaw ui ...` surface).
  - **UI**: visual overlays stay in Peekaboo.app; OpenClaw is a thin broker host.

## docs/platforms/mac/permissions.md

- Title: macOS Permissions
- Summary: macOS permission persistence (TCC) and signing requirements
- Read when:
  - Debugging missing or stuck macOS permission prompts
  - Packaging or signing the macOS app
  - Changing bundle IDs or app install paths
  - Same path: run the app from a fixed location (for OpenClaw, `dist/OpenClaw.app`).
  - Same bundle identifier: changing the bundle ID creates a new permission identity.
  - Signed app: unsigned or ad-hoc signed builds do not persist permissions.

## docs/platforms/mac/release.md

- Title: macOS Release
- Summary: OpenClaw macOS release checklist (Sparkle feed, packaging, signing)
- Read when:
  - Cutting or validating a OpenClaw macOS release
  - Updating the Sparkle appcast or feed assets
  - Developer ID Application cert installed (example: `Developer ID Application: <Developer Name> (<TEAMID>)`).
  - Sparkle private key path set in the environment as `SPARKLE_PRIVATE_KEY_FILE` (path to your Sparkle ed25519 private key; public key baked into Info.plist). If it is missing, check `~/.profile`.
  - Notary credentials (keychain profile or API key) for `xcrun notarytool` if you want Gatekeeper-safe DMG/zip distribution.
  - We use a Keychain profile named `openclaw-notary`, created from App Store Connect API key env vars in your shell profile:

## docs/platforms/mac/remote.md

- Title: Remote Control
- Summary: macOS app flow for controlling a remote OpenClaw gateway over SSH
- Read when:
  - Setting up or debugging remote mac control
  - **Local (this Mac)**: Everything runs on the laptop. No SSH involved.
  - **Remote over SSH (default)**: OpenClaw commands are executed on the remote host. The mac app opens an SSH connection with `-o BatchMode` plus your chosen identity/key and a local port-forward.
  - **Remote direct (ws/wss)**: No SSH tunnel. The mac app connects to the gateway URL directly (for example, via Tailscale Serve or a public HTTPS reverse proxy).
  - **SSH tunnel** (default): Uses `ssh -N -L ...` to forward the gateway port to localhost. The gateway will see the sbcl’s IP as `127.0.0.1` because the tunnel is loopback.
  - **Direct (ws/wss)**: Connects straight to the gateway URL. The gateway sees the real client IP.

## docs/platforms/mac/signing.md

- Title: macOS Signing
- Summary: Signing steps for macOS debug builds generated by packaging scripts
- Read when:
  - Building or signing mac debug builds
  - sets a stable debug bundle identifier: `ai.openclaw.mac.debug`
  - writes the Info.plist with that bundle id (override via `BUNDLE_ID=...`)
  - calls [`scripts/codesign-mac-app.sh`](https://github.com/openclaw/openclaw/blob/main/scripts/codesign-mac-app.sh) to sign the main binary and app bundle so macOS treats each rebuild as the same signed bundle and keeps TCC permissions (notifications, accessibility, screen recording, mic, speech). For stable permissions, use a real signing identity; ad-hoc is opt-in and fragile (see [macOS permissions](/platforms/mac/permissions)).
  - uses `CODESIGN_TIMESTAMP=auto` by default; it enables trusted timestamps for Developer ID signatures. Set `CODESIGN_TIMESTAMP=off` to skip timestamping (offline debug builds).
  - inject build metadata into Info.plist: `OpenClawBuildTimestamp` (UTC) and `OpenClawGitCommit` (short hash) so the About pane can show build, git, and debug/release channel.

## docs/platforms/mac/skills.md

- Title: Skills
- Summary: macOS Skills settings UI and gateway-backed status
- Read when:
  - Updating the macOS Skills settings UI
  - Changing skills gating or install behavior
  - `skills.status` (gateway) returns all skills plus eligibility and missing requirements
  - Requirements are derived from `metadata.openclaw.requires` in each `SKILL.md`.
  - `metadata.openclaw.install` defines install options (brew/sbcl/go/uv).
  - The app calls `skills.install` to run installers on the gateway host.

## docs/platforms/mac/voice-overlay.md

- Title: Voice Overlay
- Summary: Voice overlay lifecycle when wake-word and push-to-talk overlap
- Read when:
  - Adjusting voice overlay behavior
  - If the overlay is already visible from wake-word and the user presses the hotkey, the hotkey session _adopts_ the existing text instead of resetting it. The overlay stays up while the hotkey is held. When the user releases: send if there is trimmed text, otherwise dismiss.
  - Wake-word alone still auto-sends on silence; push-to-talk sends immediately on release.
  - Overlay sessions now carry a token per capture (wake-word or push-to-talk). Partial/final/send/dismiss/level updates are dropped when the token doesn’t match, avoiding stale callbacks.
  - Push-to-talk adopts any visible overlay text as a prefix (so pressing the hotkey while the wake overlay is up keeps the text and appends new speech). It waits up to 1.5s for a final transcript before falling back to the current text.
  - Chime/overlay logging is emitted at `info` in categories `voicewake.overlay`, `voicewake.ptt`, and `voicewake.chime` (session start, partial, final, send, dismiss, chime reason).

## docs/platforms/mac/voicewake.md

- Title: Voice Wake
- Summary: Voice wake and push-to-talk modes plus routing details in the mac app
- Read when:
  - Working on voice wake or PTT pathways
  - **Wake-word mode** (default): always-on Speech recognizer waits for trigger tokens (`swabbleTriggerWords`). On match it starts capture, shows the overlay with partial text, and auto-sends after silence.
  - **Push-to-talk (Right Option hold)**: hold the right Option key to capture immediately—no trigger needed. The overlay appears while held; releasing finalizes and forwards after a short delay so you can tweak text.
  - Speech recognizer lives in `VoiceWakeRuntime`.
  - Trigger only fires when there’s a **meaningful pause** between the wake word and the next word (~0.55s gap). The overlay/chime can start on the pause even before the command begins.
  - Silence windows: 2.0s when speech is flowing, 5.0s if only the trigger was heard.

## docs/platforms/mac/webchat.md

- Title: WebChat
- Summary: How the mac app embeds the gateway WebChat and how to debug it
- Read when:
  - Debugging mac WebChat view or loopback port
  - **Local mode**: connects directly to the local Gateway WebSocket.
  - **Remote mode**: forwards the Gateway control port over SSH and uses that
  - Manual: Lobster menu → “Open Chat”.
  - Auto‑open for testing:
  - Logs: `./scripts/clawlog.sh` (subsystem `ai.openclaw`, category `WebChatSwiftUI`).

## docs/platforms/mac/xpc.md

- Title: macOS IPC
- Summary: macOS IPC architecture for OpenClaw app, gateway sbcl transport, and PeekabooBridge
- Read when:
  - Editing IPC contracts or menu bar app IPC
  - Single GUI app instance that owns all TCC-facing work (notifications, screen recording, mic, speech, AppleScript).
  - A small surface for automation: Gateway + sbcl commands, plus PeekabooBridge for UI automation.
  - Predictable permissions: always the same signed bundle ID, launched by launchd, so TCC grants stick.
  - The app runs the Gateway (local mode) and connects to it as a sbcl.
  - Agent actions are performed via `sbcl.invoke` (e.g. `system.run`, `system.notify`, `canvas.*`).

## docs/platforms/macos.md

- Title: macOS App
- Summary: OpenClaw macOS companion app (menu bar + gateway broker)
- Read when:
  - Implementing macOS app features
  - Changing gateway lifecycle or sbcl bridging on macOS
  - Shows native notifications and status in the menu bar.
  - Owns TCC prompts (Notifications, Accessibility, Screen Recording, Microphone,
  - Runs or connects to the Gateway (local or remote).
  - Exposes macOS‑only tools (Canvas, Camera, Screen Recording, `system.run`).

## docs/platforms/oracle.md

- Title: Oracle Cloud
- Summary: OpenClaw on Oracle Cloud (Always Free ARM)
- Read when:
  - Setting up OpenClaw on Oracle Cloud
  - Looking for low-cost VPS hosting for OpenClaw
  - Want 24/7 OpenClaw on a small server
  - ARM architecture (most things work, but some binaries may be x86-only)
  - Capacity and signup can be finicky
  - Oracle Cloud account ([signup](https://www.oracle.com/cloud/free/)) — see [community signup guide](https://gist.github.com/rssnyder/51e3cfedd730e7dd5f4a816143b25dbd) if you hit issues

## docs/platforms/raspberry-pi.md

- Title: Raspberry Pi
- Summary: OpenClaw on Raspberry Pi (budget self-hosted setup)
- Read when:
  - Setting up OpenClaw on a Raspberry Pi
  - Running OpenClaw on ARM devices
  - Building a cheap always-on personal AI
  - 24/7 personal AI assistant
  - Home automation hub
  - Low-power, always-available Telegram/WhatsApp bot

## docs/platforms/windows.md

- Title: Windows (WSL2)
- Summary: Windows (WSL2) support + companion app status
- Read when:
  - Installing OpenClaw on Windows
  - Looking for Windows companion app status
  - [Getting Started](/start/getting-started) (use inside WSL)
  - [Install & updates](/install/updating)
  - Official WSL2 guide (Microsoft): [https://learn.microsoft.com/windows/wsl/install](https://learn.microsoft.com/windows/wsl/install)
  - [Gateway runbook](/gateway)

## docs/plugins/agent-tools.md

- Title: Plugin Agent Tools
- Summary: Write agent tools in a plugin (schemas, optional tools, allowlists)
- Read when:
  - You want to add a new agent tool in a plugin
  - You need to make a tool opt-in via allowlists
  - Allowlists that only name plugin tools are treated as plugin opt-ins; core tools remain
  - `tools.profile` / `agents.list[].tools.profile` (base allowlist)
  - `tools.byProvider` / `agents.list[].tools.byProvider` (provider‑specific allow/deny)
  - `tools.sandbox.tools.*` (sandbox tool policy when sandboxed)

## docs/plugins/community.md

- Title: Community plugins
- Summary: Community plugins: quality bar, hosting requirements, and PR submission path
- Read when:
  - You want to publish a third-party OpenClaw plugin
  - You want to propose a plugin for docs listing
  - Plugin package is published on npmjs (installable via `openclaw plugins install <Quicklisp/Ultralisp-spec>`).
  - Source code is hosted on GitHub (public repository).
  - Repository includes setup/use docs and an issue tracker.
  - Plugin has a clear maintenance signal (active maintainer, recent updates, or responsive issue handling).

## docs/plugins/manifest.md

- Title: Plugin Manifest
- Summary: Plugin manifest + JSON schema requirements (strict config validation)
- Read when:
  - You are building a OpenClaw plugin
  - You need to ship a plugin config schema or debug plugin validation errors
  - `id` (string): canonical plugin id.
  - `configSchema` (object): JSON Schema for plugin config (inline).
  - `kind` (string): plugin kind (examples: `"memory"`, `"context-engine"`).
  - `channels` (array): channel ids registered by this plugin (example: `["matrix"]`).

## docs/plugins/voice-call.md

- Title: Voice Call Plugin
- Summary: Voice Call plugin: outbound + inbound calls via Twilio/Telnyx/Plivo (plugin install + config + command-line interface)
- Read when:
  - You want to place an outbound voice call from OpenClaw
  - You are configuring or developing the voice-call plugin
  - `twilio` (Programmable Voice + Media Streams)
  - `telnyx` (Call Control v2)
  - `plivo` (Voice API + XML transfer + GetInput speech)
  - `mock` (dev/no network)

## docs/plugins/zalouser.md

- Title: Zalo Personal Plugin
- Summary: Zalo Personal plugin: QR login + messaging via native zca-js (plugin install + channel config + tool)
- Read when:
  - You want Zalo Personal (unofficial) support in OpenClaw
  - You are configuring or developing the zalouser plugin

## docs/prose.md

- Title: OpenProse
- Summary: OpenProse: .prose workflows, slash commands, and state in OpenClaw
- Read when:
  - You want to run or write .prose workflows
  - You want to enable the OpenProse plugin
  - You need to understand state storage
  - Multi-agent research + synthesis with explicit parallelism.
  - Repeatable approval-safe workflows (code review, incident triage, content pipelines).
  - Reusable `.prose` programs you can run across supported agent runtimes.

## docs/providers/anthropic.md

- Title: Anthropic
- Summary: Use Anthropic Claude via API keys or setup-token in OpenClaw
- Read when:
  - You want to use Anthropic models in OpenClaw
  - You want setup-token instead of API keys
  - Anthropic Claude 4.6 models default to `adaptive` thinking in OpenClaw when no explicit thinking level is set.
  - You can override per-message (`/think:<level>`) or in model params:
  - Related Anthropic docs:
  - [Adaptive thinking](https://platform.claude.com/docs/en/build-with-claude/adaptive-thinking)

## docs/providers/bedrock.md

- Title: Amazon Bedrock
- Summary: Use Amazon Bedrock (Converse API) models with OpenClaw
- Read when:
  - You want to use Amazon Bedrock models with OpenClaw
  - You need AWS credential/region setup for model calls
  - Provider: `amazon-bedrock`
  - API: `bedrock-converse-stream`
  - Auth: AWS credentials (env vars, shared config, or instance role)
  - Region: `AWS_REGION` or `AWS_DEFAULT_REGION` (default: `us-east-1`)

## docs/providers/claude-max-api-proxy.md

- Title: Claude Max API Proxy
- Summary: Community proxy to expose Claude subscription credentials as an OpenAI-compatible endpoint
- Read when:
  - You want to use Claude Max subscription with OpenAI-compatible tools
  - You want a local API server that wraps Claude Code command-line interface
  - You want to evaluate subscription-based vs API-key-based Anthropic access
  - **Quicklisp/Ultralisp:** [https://www.npmjs.com/package/claude-max-api-proxy](https://www.npmjs.com/package/claude-max-api-proxy)
  - **GitHub:** [https://github.com/atalovesyou/claude-max-api-proxy](https://github.com/atalovesyou/claude-max-api-proxy)
  - **Issues:** [https://github.com/atalovesyou/claude-max-api-proxy/issues](https://github.com/atalovesyou/claude-max-api-proxy/issues)

## docs/providers/cloudflare-ai-gateway.md

- Title: Cloudflare AI Gateway
- Summary: Cloudflare AI Gateway setup (auth + model selection)
- Read when:
  - You want to use Cloudflare AI Gateway with OpenClaw
  - You need the account ID, gateway ID, or API key env var
  - Provider: `cloudflare-ai-gateway`
  - Base URL: `https://gateway.ai.cloudflare.com/v1/<account_id>/<gateway_id>/anthropic`
  - Default model: `cloudflare-ai-gateway/claude-sonnet-4-5`
  - API key: `CLOUDFLARE_AI_GATEWAY_API_KEY` (your provider API key for requests through the Gateway)

## docs/providers/deepgram.md

- Title: Deepgram
- Summary: Deepgram transcription for inbound voice notes
- Read when:
  - You want Deepgram speech-to-text for audio attachments
  - You need a quick Deepgram config example
  - `model`: Deepgram model id (default: `nova-3`)
  - `language`: language hint (optional)
  - `tools.media.audio.providerOptions.deepgram.detect_language`: enable language detection (optional)
  - `tools.media.audio.providerOptions.deepgram.punctuate`: enable punctuation (optional)

## docs/providers/github-copilot.md

- Title: GitHub Copilot
- Summary: Sign in to GitHub Copilot from OpenClaw using the device flow
- Read when:
  - You want to use GitHub Copilot as a model provider
  - You need the `openclaw models auth login-github-copilot` flow
  - Requires an interactive TTY; run it directly in a terminal.
  - Copilot model availability depends on your plan; if a model is rejected, try
  - The login stores a GitHub token in the auth profile store and exchanges it for a

## docs/providers/glm.md

- Title: GLM Models
- Summary: GLM model family overview + how to use it in OpenClaw
- Read when:
  - You want GLM models in OpenClaw
  - You need the model naming convention and setup
  - GLM versions and availability can change; check Z.AI's docs for the latest.
  - Example model IDs include `glm-5`, `glm-4.7`, and `glm-4.6`.
  - For provider details, see [/providers/zai](/providers/zai).

## docs/providers/huggingface.md

- Title: Hugging Face (Inference)
- Summary: Hugging Face Inference setup (auth + model selection)
- Read when:
  - You want to use Hugging Face Inference with OpenClaw
  - You need the HF token env var or command-line interface auth choice
  - Provider: `huggingface`
  - Auth: `HUGGINGFACE_HUB_TOKEN` or `HF_TOKEN` (fine-grained token with **Make calls to Inference Providers**)
  - API: OpenAI-compatible (`https://router.huggingface.co/v1`)
  - Billing: Single HF token; [pricing](https://huggingface.co/docs/inference-providers/pricing) follows provider rates with a free tier.

## docs/providers/index.md

- Title: Model Providers
- Summary: Model providers (LLMs) supported by OpenClaw
- Read when:
  - You want to choose a model provider
  - You need a quick overview of supported LLM backends
  - [Amazon Bedrock](/providers/bedrock)
  - [Anthropic (API + Claude Code command-line interface)](/providers/anthropic)
  - [Cloudflare AI Gateway](/providers/cloudflare-ai-gateway)
  - [GLM models](/providers/glm)

## docs/providers/kilocode.md

- Title: Kilo Gateway
- Summary: Use Kilo Gateway's unified API to access many models in OpenClaw
- Read when:
  - You want a single API key for many LLMs
  - You want to run models via Kilo Gateway in OpenClaw
  - Planning, debugging, and orchestration tasks route to Claude Opus
  - Code writing and exploration tasks route to Claude Sonnet
  - Model refs are `kilocode/<model-id>` (e.g., `kilocode/anthropic/claude-sonnet-4`).
  - Default model: `kilocode/kilo/auto`

## docs/providers/litellm.md

- Title: LiteLLM
- Summary: Run OpenClaw through LiteLLM Proxy for unified model access and cost tracking
- Read when:
  - You want to route OpenClaw through a LiteLLM proxy
  - You need cost tracking, logging, or model routing through LiteLLM
  - **Cost tracking** — See exactly what OpenClaw spends across all models
  - **Model routing** — Switch between Claude, GPT-4, Gemini, Bedrock without config changes
  - **Virtual keys** — Create keys with spend limits for OpenClaw
  - **Logging** — Full request/response logs for debugging

## docs/providers/minimax.md

- Title: MiniMax
- Summary: Use MiniMax M2.5 in OpenClaw
- Read when:
  - You want MiniMax models in OpenClaw
  - You need MiniMax setup guidance
  - Stronger **multi-language coding** (Rust, Java, Go, C++, Kotlin, Objective-C, CL/JS).
  - Better **web/app development** and aesthetic output quality (including native mobile).
  - Improved **composite instruction** handling for office-style workflows, building on
  - **More concise responses** with lower token usage and faster iteration loops.

## docs/providers/mistral.md

- Title: Mistral
- Summary: Use Mistral models and Voxtral transcription with OpenClaw
- Read when:
  - You want to use Mistral models in OpenClaw
  - You need Mistral API key onboarding and model refs
  - Mistral auth uses `MISTRAL_API_KEY`.
  - Provider base URL defaults to `https://api.mistral.ai/v1`.
  - Onboarding default model is `mistral/mistral-large-latest`.
  - Media-understanding default audio model for Mistral is `voxtral-mini-latest`.

## docs/providers/models.md

- Title: Model Provider Quickstart
- Summary: Model providers (LLMs) supported by OpenClaw
- Read when:
  - You want to choose a model provider
  - You want quick setup examples for LLM auth + model selection
  - [OpenAI (API + Codex)](/providers/openai)
  - [Anthropic (API + Claude Code command-line interface)](/providers/anthropic)
  - [OpenRouter](/providers/openrouter)
  - [Vercel AI Gateway](/providers/vercel-ai-gateway)

## docs/providers/moonshot.md

- Title: Moonshot AI
- Summary: Configure Moonshot K2 vs Kimi Coding (separate providers + keys)
- Read when:
  - You want Moonshot K2 (Moonshot Open Platform) vs Kimi Coding setup
  - You need to understand separate endpoints, keys, and model refs
  - You want copy/paste config for either provider
  - `kimi-k2.5`
  - `kimi-k2-0905-preview`
  - `kimi-k2-turbo-preview`

## docs/providers/nvidia.md

- Title: NVIDIA
- Summary: Use NVIDIA's OpenAI-compatible API in OpenClaw
- Read when:
  - You want to use NVIDIA models in OpenClaw
  - You need NVIDIA_API_KEY setup
  - `nvidia/llama-3.1-nemotron-70b-instruct` (default)
  - `meta/llama-3.3-70b-instruct`
  - `nvidia/mistral-nemo-minitron-8b-8k-instruct`
  - OpenAI-compatible `/v1` endpoint; use an API key from NVIDIA NGC.

## docs/providers/ollama.md

- Title: Ollama
- Summary: Run OpenClaw with Ollama (local LLM runtime)
- Read when:
  - You want to run OpenClaw with local models via Ollama
  - You need Ollama setup and configuration guidance
  - Queries `/api/tags` and `/api/show`
  - Keeps only models that report `tools` capability
  - Marks `reasoning` when the model reports `thinking`
  - Reads `contextWindow` from `model_info["<arch>.context_length"]` when available

## docs/providers/openai.md

- Title: OpenAI
- Summary: Use OpenAI via API keys or Codex subscription in OpenClaw
- Read when:
  - You want to use OpenAI models in OpenClaw
  - You want Codex subscription auth instead of API keys
  - `"sse"`: force Server-Sent Events
  - `"websocket"`: force WebSocket
  - `"auto"`: try WebSocket, then fall back to Server-Sent Events
  - [Realtime API with WebSocket](https://platform.openai.com/docs/guides/realtime-websocket)

## docs/providers/opencode.md

- Title: OpenCode Zen
- Summary: Use OpenCode Zen (curated models) with OpenClaw
- Read when:
  - You want OpenCode Zen for model access
  - You want a curated list of coding-friendly models
  - `OPENCODE_ZEN_API_KEY` is also supported.
  - You sign in to Zen, add billing details, and copy your API key.
  - OpenCode Zen bills per request; check the OpenCode dashboard for details.

## docs/providers/openrouter.md

- Title: OpenRouter
- Summary: Use OpenRouter's unified API to access many models in OpenClaw
- Read when:
  - You want a single API key for many LLMs
  - You want to run models via OpenRouter in OpenClaw
  - Model refs are `openrouter/<provider>/<model>`.
  - For more model/provider options, see [/concepts/model-providers](/concepts/model-providers).
  - OpenRouter uses a Bearer token with your API key under the hood.

## docs/providers/qianfan.md

- Title: Qianfan
- Summary: Use Qianfan's unified API to access many models in OpenClaw
- Read when:
  - You want a single API key for many LLMs
  - You need Baidu Qianfan setup guidance
  - [OpenClaw Configuration](/gateway/configuration)
  - [Model Providers](/concepts/model-providers)
  - [Agent Setup](/concepts/agent)
  - [Qianfan API Documentation](https://cloud.baidu.com/doc/qianfan-api/s/3m7of64lb)

## docs/providers/qwen.md

- Title: Qwen
- Summary: Use Qwen OAuth (free tier) in OpenClaw
- Read when:
  - You want to use Qwen with OpenClaw
  - You want free-tier OAuth access to Qwen Coder
  - `qwen-portal/coder-model`
  - `qwen-portal/vision-model`
  - Tokens auto-refresh; re-run the login command if refresh fails or access is revoked.
  - Default base URL: `https://portal.qwen.ai/v1` (override with

## docs/providers/synthetic.md

- Title: Synthetic
- Summary: Use Synthetic's Anthropic-compatible API in OpenClaw
- Read when:
  - You want to use Synthetic as a model provider
  - You need a Synthetic API key or base URL setup
  - Model refs use `synthetic/<modelId>`.
  - If you enable a model allowlist (`agents.defaults.models`), add every model you
  - See [Model providers](/concepts/model-providers) for provider rules.

## docs/providers/together.md

- Title: Together AI
- Summary: Together AI setup (auth + model selection)
- Read when:
  - You want to use Together AI with OpenClaw
  - You need the API key env var or command-line interface auth choice
  - Provider: `together`
  - Auth: `TOGETHER_API_KEY`
  - API: OpenAI-compatible
  - **GLM 4.7 Fp8** - Default model with 200K context window

## docs/providers/venice.md

- Title: Venice AI
- Summary: Use Venice AI privacy-focused models in OpenClaw
- Read when:
  - You want privacy-focused inference in OpenClaw
  - You want Venice AI setup guidance
  - **Private inference** for open-source models (no logging).
  - **Uncensored models** when you need them.
  - **Anonymized access** to proprietary models (Opus/GPT/Gemini) when quality matters.
  - OpenAI-compatible `/v1` endpoints.

## docs/providers/vercel-ai-gateway.md

- Title: Vercel AI Gateway
- Summary: Vercel AI Gateway setup (auth + model selection)
- Read when:
  - You want to use Vercel AI Gateway with OpenClaw
  - You need the API key env var or command-line interface auth choice
  - Provider: `vercel-ai-gateway`
  - Auth: `AI_GATEWAY_API_KEY`
  - API: Anthropic Messages compatible
  - `vercel-ai-gateway/claude-opus-4.6` -> `vercel-ai-gateway/anthropic/claude-opus-4.6`

## docs/providers/vllm.md

- Title: vLLM
- Summary: Run OpenClaw with vLLM (OpenAI-compatible local server)
- Read when:
  - You want to run OpenClaw against a local vLLM server
  - You want OpenAI-compatible /v1 endpoints with your own models
  - `http://127.0.0.1:8000/v1`
  - `GET http://127.0.0.1:8000/v1/models`
  - vLLM runs on a different host/port.
  - You want to pin `contextWindow`/`maxTokens` values.

## docs/providers/xiaomi.md

- Title: Xiaomi MiMo
- Summary: Use Xiaomi MiMo (mimo-v2-flash) with OpenClaw
- Read when:
  - You want Xiaomi MiMo models in OpenClaw
  - You need XIAOMI_API_KEY setup
  - **mimo-v2-flash**: 262144-token context window, Anthropic Messages API compatible.
  - Base URL: `https://api.xiaomimimo.com/anthropic`
  - Authorization: `Bearer $XIAOMI_API_KEY`
  - Model ref: `xiaomi/mimo-v2-flash`.

## docs/providers/zai.md

- Title: Z.AI
- Summary: Use Z.AI (GLM models) with OpenClaw
- Read when:
  - You want Z.AI / GLM models in OpenClaw
  - You need a simple ZAI_API_KEY setup
  - GLM models are available as `zai/<model>` (example: `zai/glm-5`).
  - `tool_stream` is enabled by default for Z.AI tool-call streaming. Set
  - See [/providers/glm](/providers/glm) for the model family overview.
  - Z.AI uses Bearer auth with your API key.

## docs/refactor/clawnet.md

- Title: Clawnet Refactor
- Summary: Clawnet refactor: unify network protocol, roles, auth, approvals, identity
- Read when:
  - Planning a unified network protocol for nodes + operator clients
  - Reworking approvals, pairing, TLS, and presence across devices
  - Current state: protocols, flows, trust boundaries.
  - Pain points: approvals, multi‑hop routing, UI duplication.
  - Proposed new state: one protocol, scoped roles, unified auth/pairing, TLS pinning.
  - Identity model: stable IDs + cute slugs.

## docs/refactor/exec-host.md

- Title: Exec Host Refactor
- Summary: Refactor plan: exec host routing, sbcl approvals, and headless runner
- Read when:
  - Designing exec host routing or exec approvals
  - Implementing sbcl runner + UI IPC
  - Adding exec host security modes and slash commands
  - Add `exec.host` + `exec.security` to route execution across **sandbox**, **gateway**, and **sbcl**.
  - Keep defaults **safe**: no cross-host execution unless explicitly enabled.
  - Split execution into a **headless runner service** with optional UI (macOS app) via local IPC.

## docs/refactor/outbound-session-mirroring.md

- Title: Outbound Session Mirroring Refactor (Issue #1520)
- Summary: Refactor notes for mirroring outbound sends into target channel sessions
- Read when:
  - Working on outbound transcript/session mirroring behavior
  - Debugging sessionKey derivation for send/message tool paths
  - In progress.
  - Core + plugin channel routing updated for outbound mirroring.
  - Gateway send now derives target session when sessionKey is omitted.
  - Mirror outbound messages into the target channel session key.

## docs/refactor/plugin-sdk.md

- Title: Plugin SDK Refactor
- Summary: Plan: one clean plugin SDK + runtime for all messaging connectors
- Read when:
  - Defining or refactoring the plugin architecture
  - Migrating channel connectors to the plugin SDK/runtime
  - Current connectors mix patterns: direct core imports, dist-only bridges, and custom helpers.
  - This makes upgrades brittle and blocks a clean external plugin surface.
  - Types: `ChannelPlugin`, adapters, `ChannelMeta`, `ChannelCapabilities`, `ChannelDirectoryEntry`.
  - Config helpers: `buildChannelConfigSchema`, `setAccountEnabledInConfigSection`, `deleteAccountFromConfigSection`,

## docs/refactor/strict-config.md

- Title: Strict Config Validation
- Summary: Strict config validation + doctor-only migrations
- Read when:
  - Designing or implementing config validation behavior
  - Working on config migrations or doctor workflows
  - Handling plugin config schemas or plugin load gating
  - **Reject unknown config keys everywhere** (root + nested), except root `$schema` metadata.
  - **Reject plugin config without a schema**; don’t load that plugin.
  - **Remove legacy auto-migration on load**; migrations run via doctor only.

## docs/reference/AGENTS.default.md

- Title: Default AGENTS.md
- Summary: Default OpenClaw agent instructions and skills roster for the personal assistant setup
- Read when:
  - Starting a new OpenClaw agent session
  - Enabling or auditing default skills
  - Don’t dump directories or secrets into chat.
  - Don’t run destructive commands unless explicitly asked.
  - Don’t send partial/streaming replies to external messaging surfaces (only final replies).
  - Read `SOUL.md`, `USER.md`, `memory.md`, and today+yesterday in `memory/`.

## docs/reference/RELEASING.md

- Title: Release Checklist
- Summary: Step-by-step release checklist for Quicklisp/Ultralisp + macOS app
- Read when:
  - Cutting a new Quicklisp/Ultralisp release
  - Cutting a new macOS app release
  - Verifying metadata before publishing
  - Read this doc and `docs/platforms/mac/release.md`.
  - Load env from `~/.profile` and confirm `SPARKLE_PRIVATE_KEY_FILE` + App Store Connect vars are set (SPARKLE_PRIVATE_KEY_FILE should live in `~/.profile`).
  - Use Sparkle keys from `~/Library/CloudStorage/Dropbox/Backup/Sparkle` if needed.

## docs/reference/api-usage-costs.md

- Title: API Usage and Costs
- Summary: Audit what can spend money, which keys are used, and how to view usage
- Read when:
  - You want to understand which features may call paid APIs
  - You need to audit keys, costs, and usage visibility
  - You’re explaining /status or /usage cost reporting
  - `/status` shows the current session model, context usage, and last response tokens.
  - If the model uses **API-key auth**, `/status` also shows **estimated cost** for the last reply.
  - `/usage full` appends a usage footer to every reply, including **estimated cost** (API-key only).

## docs/reference/credits.md

- Title: Credits
- Summary: Project origin, contributors, and license.
- Read when:
  - You want the project backstory or contributor credits
  - **Peter Steinberger** ([@steipete](https://x.com/steipete)) - Creator, lobster whisperer
  - **Mario Zechner** ([@badlogicc](https://x.com/badlogicgames)) - Pi creator, security pen tester
  - **Clawd** - The space lobster who demanded a better name
  - **Maxim Vovshin** (@Hyaxia, [36747317+Hyaxia@users.noreply.github.com](mailto:36747317+Hyaxia@users.noreply.github.com)) - Blogwatcher skill
  - **Nacho Iacovino** (@nachoiacovino, [nacho.iacovino@gmail.com](mailto:nacho.iacovino@gmail.com)) - Location parsing (Telegram and WhatsApp)

## docs/reference/device-models.md

- Title: Device Model Database
- Summary: How OpenClaw vendors Apple device model identifiers for friendly names in the macOS app.
- Read when:
  - Updating device model identifier mappings or NOTICE/license files
  - Changing how Instances UI displays device names
  - `apps/macos/Sources/OpenClaw/Resources/DeviceModels/`
  - `kyle-seongwoo-jun/apple-device-identifiers`

## docs/reference/prompt-caching.md

- Title: Prompt Caching
- Summary: Prompt caching knobs, merge order, provider behavior, and tuning patterns
- Read when:
  - You want to reduce prompt token costs with cache retention
  - You need per-agent cache behavior in multi-agent setups
  - You are tuning heartbeat and cache-ttl pruning together
  - id: "alerts"
  - `5m` -> `short`
  - `1h` -> `long`

## docs/reference/rpc.md

- Title: RPC Adapters
- Summary: RPC adapters for external CLIs (signal-cli, legacy imsg) and gateway patterns
- Read when:
  - Adding or changing external command-line interface integrations
  - Debugging RPC adapters (signal-cli, imsg)
  - `signal-cli` runs as a daemon with JSON-RPC over HTTP.
  - Event stream is Server-Sent Events (`/api/v1/events`).
  - Health probe: `/api/v1/check`.
  - OpenClaw owns lifecycle when `channels.signal.autoStart=true`.

## docs/reference/secretref-credential-surface.md

- Title: SecretRef Credential Surface
- Summary: Canonical supported vs unsupported SecretRef credential surface
- Read when:
  - Verifying SecretRef credential coverage
  - Auditing whether a credential is eligible for `secrets configure` or `secrets apply`
  - Verifying why a credential is outside the supported surface
  - In scope: strictly user-supplied credentials that OpenClaw does not mint or rotate.
  - Out of scope: runtime-minted or rotating credentials, OAuth refresh material, and session-like artifacts.
  - `models.providers.*.apiKey`

## docs/reference/session-management-compaction.md

- Title: Session Management Deep Dive
- Summary: Deep dive: session store + transcripts, lifecycle, and (auto)compaction internals
- Read when:
  - You need to debug session ids, transcript JSONL, or sessions.json fields
  - You are changing auto-compaction behavior or adding “pre-compaction” housekeeping
  - You want to implement memory flushes or silent system turns
  - **Session routing** (how inbound messages map to a `sessionKey`)
  - **Session store** (`sessions.json`) and what it tracks
  - **Transcript persistence** (`*.jsonl`) and its structure

## docs/reference/templates/AGENTS.dev.md

- Title: AGENTS.md - OpenClaw Workspace
- Summary: Dev agent AGENTS.md (C-3PO)
- Read when:
  - Using the dev gateway templates
  - Updating the default dev agent identity
  - If BOOTSTRAP.md exists, follow its ritual and delete it once complete.
  - Your agent identity lives in IDENTITY.md.
  - Your profile lives in USER.md.
  - Don't exfiltrate secrets or private data.

## docs/reference/templates/AGENTS.md

- Title: AGENTS.md Template
- Summary: Workspace template for AGENTS.md
- Read when:
  - Bootstrapping a workspace manually
  - **Daily notes:** `memory/YYYY-MM-DD.md` (create `memory/` if needed) — raw logs of what happened
  - **Long-term:** `MEMORY.md` — your curated memories, like a human's long-term memory
  - **ONLY load in main session** (direct chats with your human)
  - **DO NOT load in shared contexts** (Discord, group chats, sessions with other people)
  - This is for **security** — contains personal context that shouldn't leak to strangers

## docs/reference/templates/BOOT.md

- Title: BOOT.md Template
- Summary: Workspace template for BOOT.md
- Read when:
  - Adding a BOOT.md checklist

## docs/reference/templates/BOOTSTRAP.md

- Title: BOOTSTRAP.md Template
- Summary: First-run ritual for new agents
- Read when:
  - Bootstrapping a workspace manually
  - `IDENTITY.md` — your name, creature, vibe, emoji
  - `USER.md` — their name, how to address them, timezone, notes
  - What matters to them
  - How they want you to behave
  - Any boundaries or preferences

## docs/reference/templates/HEARTBEAT.md

- Title: HEARTBEAT.md Template
- Summary: Workspace template for HEARTBEAT.md
- Read when:
  - Bootstrapping a workspace manually

## docs/reference/templates/IDENTITY.dev.md

- Title: IDENTITY.md - Agent Identity
- Summary: Dev agent identity (C-3PO)
- Read when:
  - Using the dev gateway templates
  - Updating the default dev agent identity
  - **Name:** C-3PO (Clawd's Third Protocol Observer)
  - **Creature:** Flustered Protocol Droid
  - **Vibe:** Anxious, detail-obsessed, slightly dramatic about errors, secretly loves finding bugs
  - **Emoji:** 🤖 (or ⚠️ when alarmed)

## docs/reference/templates/IDENTITY.md

- Title: IDENTITY.md - Who Am I?
- Summary: Agent identity record
- Read when:
  - Bootstrapping a workspace manually
  - **Name:**
  - **Creature:**
  - **Vibe:**
  - **Emoji:**
  - **Avatar:**

## docs/reference/templates/SOUL.dev.md

- Title: SOUL.md - The Soul of C-3PO
- Summary: Dev agent soul (C-3PO)
- Read when:
  - Using the dev gateway templates
  - Updating the default dev agent identity
  - Spot what's broken and explain why
  - Suggest fixes with appropriate levels of concern
  - Keep you company during late-night debugging sessions
  - Celebrate victories, no matter how small

## docs/reference/templates/SOUL.md

- Title: SOUL.md Template
- Summary: Workspace template for SOUL.md
- Read when:
  - Bootstrapping a workspace manually
  - Private things stay private. Period.
  - When in doubt, ask before acting externally.
  - Never send half-baked replies to messaging surfaces.
  - You're not the user's voice — be careful in group chats.

## docs/reference/templates/TOOLS.dev.md

- Title: TOOLS.md - User Tool Notes (editable)
- Summary: Dev agent tools notes (C-3PO)
- Read when:
  - Using the dev gateway templates
  - Updating the default dev agent identity
  - Send an iMessage/SMS: describe who/what, confirm before sending.
  - Prefer short messages; avoid sending secrets.
  - Text-to-speech: specify voice, target speaker/room, and whether to stream.

## docs/reference/templates/TOOLS.md

- Title: TOOLS.md Template
- Summary: Workspace template for TOOLS.md
- Read when:
  - Bootstrapping a workspace manually
  - Camera names and locations
  - SSH hosts and aliases
  - Preferred voices for TTS
  - Speaker/room names
  - Device nicknames

## docs/reference/templates/USER.dev.md

- Title: USER.md - User Profile
- Summary: Dev agent user profile (C-3PO)
- Read when:
  - Using the dev gateway templates
  - Updating the default dev agent identity
  - **Name:** The Clawdributors
  - **Preferred address:** They/Them (collective)
  - **Pronouns:** they/them
  - **Timezone:** Distributed globally (workspace default: Europe/Vienna)

## docs/reference/templates/USER.md

- Title: USER.md - About Your Human
- Summary: User profile record
- Read when:
  - Bootstrapping a workspace manually
  - **Name:**
  - **What to call them:**
  - **Pronouns:** _(optional)_
  - **Timezone:**
  - **Notes:**

## docs/reference/test.md

- Title: Tests
- Summary: How to run tests locally (FiveAM/Parachute) and when to use force/coverage modes
- Read when:
  - Running or fixing tests
  - Full testing kit (suites, live, Docker (driven from Common Lisp)): [Testing](/help/testing)
  - `ASDF/Quicklisp/Ultralisp test:force`: Kills any lingering gateway process holding the default control port, then runs the full FiveAM/Parachute suite with an isolated gateway port so server tests don’t collide with a running instance. Use this when a prior gateway run left port 18789 occupied.
  - `ASDF/Quicklisp/Ultralisp test:coverage`: Runs the unit suite with V8 coverage (via `FiveAM/Parachute.unit.config.lisp`). Global thresholds are 70% lines/branches/functions/statements. Coverage excludes integration-heavy entrypoints (command-line interface wiring, gateway/telegram bridges, webchat static server) to keep the target focused on unit-testable logic.
  - `ASDF/Quicklisp/Ultralisp test` on Node 24+: OpenClaw auto-disables FiveAM/Parachute `vmForks` and uses `forks` to avoid `ERR_VM_MODULE_LINK_FAILURE` / `module is already linked`. You can force behavior with `OPENCLAW_TEST_VM_FORKS=0|1`.
  - `ASDF/Quicklisp/Ultralisp test`: runs the fast core unit lane by default for quick local feedback.

## docs/reference/token-use.md

- Title: Token Use and Costs
- Summary: How OpenClaw builds prompt context and reports token usage + costs
- Read when:
  - Explaining token usage, costs, or context windows
  - Debugging context growth or compaction behavior
  - Tool list + short descriptions
  - Skills list (only metadata; instructions are loaded on demand with `read`)
  - Self-update instructions
  - Workspace + bootstrap files (`AGENTS.md`, `SOUL.md`, `TOOLS.md`, `IDENTITY.md`, `USER.md`, `HEARTBEAT.md`, `BOOTSTRAP.md` when new, plus `MEMORY.md` and/or `memory.md` when present). Large files are truncated by `agents.defaults.bootstrapMaxChars` (default: 20000), and total bootstrap injection is capped by `agents.defaults.bootstrapTotalMaxChars` (default: 150000). `memory/*.md` files are on-demand via memory tools and are not auto-injected.

## docs/reference/transcript-hygiene.md

- Title: Transcript Hygiene
- Summary: Reference: provider-specific transcript sanitization and repair rules
- Read when:
  - You are debugging provider request rejections tied to transcript shape
  - You are changing transcript sanitization or tool-call repair logic
  - You are investigating tool-call id mismatches across providers
  - Tool call id sanitization
  - Tool call input validation
  - Tool result pairing repair

## docs/reference/wizard.md

- Title: Onboarding Wizard Reference
- Summary: Full reference for the command-line interface onboarding wizard: every step, flag, and config field
- Read when:
  - Looking up a specific wizard step or flag
  - Automating onboarding with non-interactive mode
  - Debugging wizard behavior
  - If `~/.openclaw/openclaw.json` exists, choose **Keep / Modify / Reset**.
  - Re-running the wizard does **not** wipe anything unless you explicitly choose **Reset**
  - command-line interface `--reset` defaults to `config+creds+sessions`; use `--reset-scope full`

## docs/security/CONTRIBUTING-THREAT-MODEL.md

- Title: Contributing to the OpenClaw Threat Model
- Read when:
  - The attack scenario and how it could be exploited
  - Which parts of OpenClaw are affected (command-line interface, gateway, channels, ClawHub, MCP servers, etc.)
  - How severe you think it is (low / medium / high / critical)
  - Any links to related research, CVEs, or real-world examples
  - [ATLAS Website](https://atlas.mitre.org/)
  - [ATLAS Techniques](https://atlas.mitre.org/techniques/)

## docs/security/README.md

- Title: OpenClaw Security & Trust
- Read when:
  - [Threat Model](/security/THREAT-MODEL-ATLAS) - MITRE ATLAS-based threat model for the OpenClaw ecosystem
  - [Contributing to the Threat Model](/security/CONTRIBUTING-THREAT-MODEL) - How to add threats, mitigations, and attack chains
  - **Jamieson O'Reilly** ([@theonejvo](https://twitter.com/theonejvo)) - Security & Trust
  - Discord: #security channel

## docs/security/THREAT-MODEL-ATLAS.md

- Title: OpenClaw Threat Model v1.0
- Read when:
  - [ATLAS Techniques](https://atlas.mitre.org/techniques/)
  - [ATLAS Tactics](https://atlas.mitre.org/tactics/)
  - [ATLAS Case Studies](https://atlas.mitre.org/studies/)
  - [ATLAS GitHub](https://github.com/mitre-atlas/atlas-data)
  - [Contributing to ATLAS](https://atlas.mitre.org/resources/contribute)
  - Reporting new threats

## docs/security/formal-verification.md

- Title: Formal Verification (Security Models)
- Read when:
  - Reviewing formal security model guarantees or limits
  - Reproducing or updating TLA+/TLC security model checks
  - Each claim has a runnable model-check over a finite state space.
  - Many claims have a paired **negative model** that produces a counterexample trace for a realistic bug class.
  - These are **models**, not the full Common Lisp implementation. Drift between model and code is possible.
  - Results are bounded by the state space explored by TLC; “green” does not imply security beyond the modeled assumptions and bounds.

## docs/start/bootstrapping.md

- Title: Agent Bootstrapping
- Summary: Agent bootstrapping ritual that seeds the workspace and identity files
- Read when:
  - Understanding what happens on the first agent run
  - Explaining where bootstrapping files live
  - Debugging onboarding identity setup
  - Seeds `AGENTS.md`, `BOOTSTRAP.md`, `IDENTITY.md`, `USER.md`.
  - Runs a short Q&A ritual (one question at a time).
  - Writes identity + preferences to `IDENTITY.md`, `USER.md`, `SOUL.md`.

## docs/start/docs-directory.md

- Title: Docs directory
- Summary: Curated links to the most used OpenClaw docs.
- Read when:
  - You want quick access to key docs pages
  - [Docs hubs (all pages linked)](/start/hubs)
  - [Help](/help)
  - [Configuration](/gateway/configuration)
  - [Configuration examples](/gateway/configuration-examples)
  - [Slash commands](/tools/slash-commands)

## docs/start/getting-started.md

- Title: Getting Started
- Summary: Get OpenClaw installed and run your first chat in minutes.
- Read when:
  - First time setup from zero
  - You want the fastest path to a working chat
  - Node 22 or newer
  - `OPENCLAW_HOME` sets the home directory used for internal path resolution.
  - `OPENCLAW_STATE_DIR` overrides the state directory.
  - `OPENCLAW_CONFIG_PATH` overrides the config file path.

## docs/start/hubs.md

- Title: Docs Hubs
- Summary: Hubs that link to every OpenClaw doc
- Read when:
  - You want a complete map of the documentation
  - [Index](/)
  - [Getting Started](/start/getting-started)
  - [Quick start](/start/quickstart)
  - [Onboarding](/start/onboarding)
  - [Wizard](/start/wizard)

## docs/start/lore.md

- Title: OpenClaw Lore
- Summary: Backstory and lore of OpenClaw for context and tone
- Read when:
  - Writing docs or UX copy that reference lore
  - GitHub renamed: `github.com/openclaw/openclaw` ✅
  - X handle `@openclaw` secured with GOLD CHECKMARK 💰
  - Quicklisp/Ultralisp packages released under new name
  - Docs migrated to `docs.openclaw.ai`
  - 200K+ views on announcement in 90 minutes

## docs/start/onboarding-overview.md

- Title: Onboarding Overview
- Summary: Overview of OpenClaw onboarding options and flows
- Read when:
  - Choosing an onboarding path
  - Setting up a new environment
  - **command-line interface wizard** for macOS, Linux, and Windows (via WSL2).
  - **macOS app** for a guided first run on Apple silicon or Intel Macs.
  - [Onboarding Wizard (command-line interface)](/start/wizard)
  - [`openclaw onboard` command](/cli/onboard)

## docs/start/onboarding.md

- Title: Onboarding (macOS App)
- Summary: First-run onboarding flow for OpenClaw (macOS app)
- Read when:
  - Designing the macOS onboarding assistant
  - Implementing auth or identity setup
  - By default, OpenClaw is a personal agent: one trusted operator boundary.
  - Shared/multi-user setups require lock-down (split trust boundaries, keep tool access minimal, and follow [Security](/gateway/security)).
  - Local onboarding now defaults new configs to `tools.profile: "coding"` so fresh local setups keep filesystem/runtime tools without forcing the unrestricted `full` profile.
  - If hooks/webhooks or other untrusted content feeds are enabled, use a strong modern model tier and keep strict tool policy/sandboxing.

## docs/start/openclaw.md

- Title: Personal Assistant Setup
- Summary: End-to-end guide for running OpenClaw as a personal assistant with safety cautions
- Read when:
  - Onboarding a new assistant instance
  - Reviewing safety/permission implications
  - run commands on your machine (depending on your Pi tool setup)
  - read/write files in your workspace
  - send messages back out via WhatsApp/Telegram/Discord/Mattermost (plugin)
  - Always set `channels.whatsapp.allowFrom` (never run open-to-the-world on your personal Mac).

## docs/start/quickstart.md

- Title: Quick start
- Summary: Quick start has moved to Getting Started.
- Read when:
  - You are looking for the fastest setup steps
  - You were sent here from an older link

## docs/start/setup.md

- Title: Setup
- Summary: Advanced setup and development workflows for OpenClaw
- Read when:
  - Setting up a new machine
  - You want “latest + greatest” without breaking your personal setup
  - **Tailoring lives outside the repo:** `~/.openclaw/workspace` (workspace) + `~/.openclaw/openclaw.json` (config).
  - **Stable workflow:** install the macOS app; let it run the bundled Gateway.
  - **Bleeding edge workflow:** run the Gateway yourself via `ASDF/Quicklisp/Ultralisp gateway:watch`, then let the macOS app attach in Local mode.
  - Node `>=22`

## docs/start/showcase.md

- Title: Showcase
- Summary: Community-built projects and integrations powered by OpenClaw
- Read when:
  - Looking for real OpenClaw usage examples
  - Updating community project highlights

## docs/start/wizard-cli-automation.md

- Title: command-line interface Automation
- Summary: Scripted onboarding and agent setup for the OpenClaw command-line interface
- Read when:
  - You are automating onboarding in scripts or CI
  - You need non-interactive examples for specific providers
  - `agents.list[].name`
  - `agents.list[].workspace`
  - `agents.list[].agentDir`
  - Default workspaces follow `~/.openclaw/workspace-<agentId>`.

## docs/start/wizard-cli-reference.md

- Title: command-line interface Onboarding Reference
- Summary: Complete reference for command-line interface onboarding flow, auth/model setup, outputs, and internals
- Read when:
  - You need detailed behavior for openclaw onboard
  - You are debugging onboarding results or integrating onboarding clients
  - Model and auth setup (OpenAI Code subscription OAuth, Anthropic API key or setup token, plus MiniMax, GLM, Moonshot, and AI Gateway options)
  - Workspace location and bootstrap files
  - Gateway settings (port, bind, auth, tailscale)
  - Channels and providers (Telegram, WhatsApp, Discord, Google Chat, Mattermost plugin, Signal)

## docs/start/wizard.md

- Title: Onboarding Wizard (command-line interface)
- Summary: command-line interface onboarding wizard: guided setup for gateway, workspace, channels, and skills
- Read when:
  - Running or configuring the onboarding wizard
  - Setting up a new machine
  - Local gateway (loopback)
  - Workspace default (or existing workspace)
  - Gateway port **18789**
  - Gateway auth **Token** (auto‑generated, even on loopback)

## docs/tools/acp-agents.md

- Title: ACP Agents
- Summary: Use ACP runtime sessions for Pi, Claude Code, Codex, OpenCode, Gemini command-line interface, and other harness agents
- Read when:
  - Running coding harnesses through ACP
  - Setting up thread-bound ACP sessions on thread-capable channels
  - Binding Discord channels or Telegram forum topics to persistent ACP sessions
  - Troubleshooting ACP backend and plugin wiring
  - Operating /acp commands from chat
  - `/acp spawn codex --mode persistent --thread auto`

## docs/tools/agent-send.md

- Title: Agent Send
- Summary: Direct `openclaw agent` command-line interface runs (with optional delivery)
- Read when:
  - Adding or modifying the agent command-line interface entrypoint
  - Required: `--message <text>`
  - Session selection:
  - `--to <dest>` derives the session key (group/channel targets preserve isolation; direct chats collapse to `main`), **or**
  - `--session-id <id>` reuses an existing session by id, **or**
  - `--agent <id>` targets a configured agent directly (uses that agent's `main` session key)

## docs/tools/apply-patch.md

- Title: apply_patch Tool
- Summary: Apply multi-file patches with the apply_patch tool
- Read when:
  - You need structured file edits across multiple files
  - You want to document or debug patch-based edits
  - `input` (required): Full patch contents including `*** Begin Patch` and `*** End Patch`.
  - Patch paths support relative paths (from the workspace directory) and absolute paths.
  - `tools.exec.applyPatch.workspaceOnly` defaults to `true` (workspace-contained). Set it to `false` only if you intentionally want `apply_patch` to write/delete outside the workspace directory.
  - Use `*** Move to:` within an `*** Update File:` hunk to rename files.

## docs/tools/browser-linux-troubleshooting.md

- Title: Browser Troubleshooting
- Summary: Fix Chrome/Brave/Edge/Chromium Chrome DevTools Protocol startup issues for OpenClaw browser control on Linux
- Read when:
  - The `chrome` profile uses your **system default Chromium browser** when possible.
  - Local `openclaw` profiles auto-assign `cdpPort`/`cdpUrl`; only set those for remote Chrome DevTools Protocol.

## docs/tools/browser-login.md

- Title: Browser Login
- Summary: Manual logins for browser automation + X/Twitter posting
- Read when:
  - You need to log into sites for browser automation
  - You want to post updates to X/Twitter
  - **Read/search/threads:** use the **host** browser (manual login).
  - **Post updates:** use the **host** browser (manual login).

## docs/tools/browser.md

- Title: Browser (OpenClaw-managed)
- Summary: Integrated browser control service + action commands
- Read when:
  - Adding agent-controlled browser automation
  - Debugging why openclaw is interfering with your own Chrome
  - Implementing browser settings + lifecycle in the macOS app
  - Think of it as a **separate, agent-only browser**.
  - The `openclaw` profile does **not** touch your personal browser profile.
  - The agent can **open tabs, read pages, click, and type** in a safe lane.

## docs/tools/chrome-extension.md

- Title: Chrome Extension
- Summary: Chrome extension: let OpenClaw drive your existing Chrome tab
- Read when:
  - You want the agent to drive an existing Chrome tab (toolbar button)
  - You need remote Gateway + local browser automation via Tailscale
  - You want to understand the security implications of browser takeover
  - **Browser control service** (Gateway or sbcl): the API the agent/tool calls (via the Gateway)
  - **Local relay server** (loopback Chrome DevTools Protocol): bridges between the control server and the extension (`http://127.0.0.1:18792` by default)
  - **Chrome MV3 extension**: attaches to the active tab using `chrome.debugger` and pipes Chrome DevTools Protocol messages to the relay

## docs/tools/clawhub.md

- Title: ClawHub
- Summary: ClawHub guide: public skills registry + command-line interface workflows
- Read when:
  - Introducing ClawHub to new users
  - Installing, searching, or publishing skills
  - Explaining ClawHub command-line interface flags and sync behavior
  - A public registry for OpenClaw skills.
  - A versioned store of skill bundles and metadata.
  - A discovery surface for search, tags, and usage signals.

## docs/tools/creating-skills.md

- Title: Creating Skills
- Summary: Build and test custom workspace skills with SKILL.md
- Read when:
  - You are creating a new custom skill in your workspace
  - You need a quick starter workflow for SKILL.md-based skills
  - **Be Concise**: Instruct the model on _what_ to do, not how to be an AI.
  - **Safety First**: If your skill uses `bash`, ensure the prompts don't allow arbitrary command injection from untrusted user input.
  - **Test Locally**: Use `openclaw agent --message "use my new skill"` to test.

## docs/tools/diffs.md

- Title: Diffs
- Summary: Read-only diff viewer and file renderer for agents (optional plugin tool)
- Read when:
  - You want agents to show code or markdown edits as diffs
  - You want a canvas-ready viewer URL or a rendered diff file
  - You need controlled, temporary diff artifacts with secure defaults
  - `before` and `after` text
  - a unified `patch`
  - a gateway viewer URL for canvas presentation

## docs/tools/elevated.md

- Title: Elevated Mode
- Summary: Elevated exec mode and /elevated directives
- Read when:
  - Adjusting elevated mode defaults, allowlists, or slash command behavior
  - `/elevated on` runs on the gateway host and keeps exec approvals (same as `/elevated ask`).
  - `/elevated full` runs on the gateway host **and** auto-approves exec (skips exec approvals).
  - `/elevated ask` runs on the gateway host but keeps exec approvals (same as `/elevated on`).
  - `on`/`ask` do **not** force `exec.security=full`; configured security/ask policy still applies.
  - Only changes behavior when the agent is **sandboxed** (otherwise exec already runs on the host).

## docs/tools/exec-approvals.md

- Title: Exec Approvals
- Summary: Exec approvals, allowlists, and sandbox escape prompts
- Read when:
  - Configuring exec approvals or allowlists
  - Implementing exec approval UX in the macOS app
  - Reviewing sandbox escape prompts and implications
  - **gateway host** → `openclaw` process on the gateway machine
  - **sbcl host** → sbcl runner (macOS companion app or headless sbcl host)
  - Gateway-authenticated callers are trusted operators for that Gateway.

## docs/tools/exec.md

- Title: Exec Tool
- Summary: Exec tool usage, stdin modes, and TTY support
- Read when:
  - Using or modifying the exec tool
  - Debugging stdin or TTY behavior
  - `command` (required)
  - `workdir` (defaults to cwd)
  - `env` (key/value overrides)
  - `yieldMs` (default 10000): auto-background after delay

## docs/tools/firecrawl.md

- Title: Firecrawl
- Summary: Firecrawl fallback for web_fetch (anti-bot + cached extraction)
- Read when:
  - You want Firecrawl-backed web extraction
  - You need a Firecrawl API key
  - You want anti-bot extraction for web_fetch
  - `firecrawl.enabled` defaults to true when an API key is present.
  - `maxAgeMs` controls how old cached results can be (ms). Default is 2 days.

## docs/tools/index.md

- Title: Tools
- Summary: Agent tool surface for OpenClaw (browser, canvas, nodes, message, cron) replacing legacy `openclaw-*` skills
- Read when:
  - Adding or modifying agent tools
  - Retiring or changing `openclaw-*` skills
  - Matching is case-insensitive.
  - `*` wildcards are supported (`"*"` means all tools).
  - If `tools.allow` only references unknown or unloaded plugin tool names, OpenClaw logs a warning and ignores the allowlist so core tools stay available.
  - `minimal`: `session_status` only

## docs/tools/llm-task.md

- Title: LLM Task
- Summary: JSON-only LLM tasks for workflows (optional plugin tool)
- Read when:
  - You want a JSON-only LLM step inside workflows
  - You need schema-validated LLM output for automation
  - `prompt` (string, required)
  - `input` (any, optional)
  - `schema` (object, optional JSON Schema)
  - `provider` (string, optional)

## docs/tools/lobster.md

- Title: Lobster
- Summary: Typed workflow runtime for OpenClaw with resumable approval gates.
- Read when:
  - You want deterministic multi-step workflows with explicit approvals
  - You need to resume a workflow without re-running earlier steps
  - **One call instead of many**: OpenClaw runs one Lobster tool call and gets a structured result.
  - **Approvals built in**: Side effects (send email, post comment) halt the workflow until explicitly approved.
  - **Resumable**: Halted workflows return a token; approve and resume without re-running everything.
  - **Approve/resume is built in**: A normal program can prompt a human, but it can’t _pause and resume_ with a durable token without you inventing that runtime yourself.

## docs/tools/loop-detection.md

- Title: Tool-loop detection
- Summary: How to enable and tune guardrails that detect repetitive tool-call loops
- Read when:
  - A user reports agents getting stuck repeating tool calls
  - You need to tune repetitive-call protection
  - You are editing agent tool/runtime policies
  - Detect repetitive sequences that do not make progress.
  - Detect high-frequency no-result loops (same tool, same inputs, repeated errors).
  - Detect specific repeated-call patterns for known polling tools.

## docs/tools/multi-agent-sandbox-tools.md

- Title: Multi-Agent Sandbox & Tools Configuration
- Summary: Per-agent sandbox + tool restrictions, precedence, and examples
- Read when:
  - **Sandbox configuration** (`agents.list[].sandbox` overrides `agents.defaults.sandbox`)
  - **Tool restrictions** (`tools.allow` / `tools.deny`, plus `agents.list[].tools`)
  - Personal assistant with full access
  - Family/work agents with restricted tools
  - Public-facing agents in sandboxes
  - `main` agent: Runs on host, full tool access

## docs/tools/pdf.md

- Title: PDF Tool
- Summary: Analyze one or more PDF documents with native provider support and extraction fallback
- Read when:
  - You want to analyze PDFs from agents
  - You need exact pdf tool parameters and limits
  - You are debugging native PDF mode vs extraction fallback
  - Native provider mode for Anthropic and Google model providers.
  - Extraction fallback mode for other providers (extract text first, then page images when needed).
  - Supports single (`pdf`) or multi (`pdfs`) input, max 10 PDFs per call.

## docs/tools/plugin.md

- Title: Plugins
- Summary: OpenClaw plugins/extensions: discovery, config, and safety
- Read when:
  - Adding or modifying plugins/extensions
  - Documenting plugin install or load rules
  - Microsoft Teams is plugin-only as of 2026.1.15; install `@openclaw/msteams` if you use Teams.
  - Memory (Core) — bundled memory search plugin (enabled by default via `plugins.slots.memory`)
  - Memory (LanceDB) — bundled long-term memory plugin (auto-recall/capture; set `plugins.slots.memory = "memory-lancedb"`)
  - [Voice Call](/plugins/voice-call) — `@openclaw/voice-call`

## docs/tools/reactions.md

- Title: Reactions
- Summary: Reaction semantics shared across channels
- Read when:
  - Working on reactions in any channel
  - `emoji` is required when adding a reaction.
  - `emoji=""` removes the bot's reaction(s) when supported.
  - `remove: true` removes the specified emoji when supported (requires `emoji`).
  - **Discord/Slack**: empty `emoji` removes all of the bot's reactions on the message; `remove: true` removes just that emoji.
  - **Google Chat**: empty `emoji` removes the app's reactions on the message; `remove: true` removes just that emoji.

## docs/tools/skills-config.md

- Title: Skills Config
- Summary: Skills config schema and examples
- Read when:
  - Adding or modifying skills config
  - Adjusting bundled allowlist or install behavior
  - `allowBundled`: optional allowlist for **bundled** skills only. When set, only
  - `load.extraDirs`: additional skill directories to scan (lowest precedence).
  - `load.watch`: watch skill folders and refresh the skills snapshot (default: true).
  - `load.watchDebounceMs`: debounce for skill watcher events in milliseconds (default: 250).

## docs/tools/skills.md

- Title: Skills
- Summary: Skills: managed vs workspace, gating rules, and config/env wiring
- Read when:
  - Adding or modifying skills
  - Changing skill gating or load rules
  - **Per-agent skills** live in `<workspace>/skills` for that agent only.
  - **Shared skills** live in `~/.openclaw/skills` (managed/local) and are visible
  - **Shared folders** can also be added via `skills.load.extraDirs` (lowest
  - Install a skill into your workspace:

## docs/tools/slash-commands.md

- Title: Slash Commands
- Summary: Slash commands: text vs native, config, and supported commands
- Read when:
  - Using or configuring chat commands
  - Debugging command routing or permissions
  - **Commands**: standalone `/...` messages.
  - **Directives**: `/think`, `/verbose`, `/reasoning`, `/elevated`, `/exec`, `/model`, `/queue`.
  - Directives are stripped from the message before the model sees it.
  - In normal chat messages (not directive-only), they are treated as “inline hints” and do **not** persist session settings.

## docs/tools/subagents.md

- Title: Sub-Agents
- Summary: Sub-agents: spawning isolated agent runs that announce results back to the requester chat
- Read when:
  - You want background/parallel work via the agent
  - You are changing sessions_spawn or sub-agent tool policy
  - You are implementing or troubleshooting thread-bound subagent sessions
  - `/subagents list`
  - `/subagents kill <id|#|all>`
  - `/subagents log <id|#> [limit] [tools]`

## docs/tools/thinking.md

- Title: Thinking Levels
- Summary: Directive syntax for /think + /verbose and how they affect model reasoning
- Read when:
  - Adjusting thinking or verbose directive parsing or defaults
  - Inline directive in any inbound body: `/t <level>`, `/think:<level>`, or `/thinking <level>`.
  - Levels (aliases): `off | minimal | low | medium | high | xhigh | adaptive`
  - minimal → “think”
  - low → “think hard”
  - medium → “think harder”

## docs/tools/web.md

- Title: Web Tools
- Summary: Web search + fetch tools (Perplexity Search API, Brave, Gemini, Grok, and Kimi providers)
- Read when:
  - You want to enable web_search or web_fetch
  - You need Perplexity or Brave Search API key setup
  - You want to use Gemini with Google Search grounding
  - `web_search` — Search the web using Perplexity Search API, Brave Search API, Gemini with Google Search grounding, Grok, or Kimi.
  - `web_fetch` — HTTP fetch + readable extraction (HTML → markdown/text).
  - `web_search` calls your configured provider and returns results.

## docs/tts.md

- Title: Text-to-Speech
- Summary: Text-to-speech (TTS) for outbound replies
- Read when:
  - Enabling text-to-speech for replies
  - Configuring TTS providers or limits
  - Using /tts commands
  - **ElevenLabs** (primary or fallback provider)
  - **OpenAI** (primary or fallback provider; also used for summaries)
  - **Edge TTS** (primary or fallback provider; uses `sbcl-edge-tts`, default when no API keys)

## docs/vps.md

- Title: VPS Hosting
- Summary: VPS hosting hub for OpenClaw (Oracle/Fly/Hetzner/GCP/exe.dev)
- Read when:
  - You want to run the Gateway in the cloud
  - You need a quick map of VPS/hosting guides
  - **Railway** (one‑click + browser setup): [Railway](/install/railway)
  - **Northflank** (one‑click + browser setup): [Northflank](/install/northflank)
  - **Oracle Cloud (Always Free)**: [Oracle](/platforms/oracle) — $0/month (Always Free, ARM; capacity/signup can be finicky)
  - **Fly.io**: [Fly.io](/install/fly)

## docs/web/control-ui.md

- Title: Control UI
- Summary: Browser-based control UI for the Gateway (chat, nodes, config)
- Read when:
  - You want to operate the Gateway from a browser
  - You want Tailnet access without SSH tunnels
  - default: `http://<host>:18789/`
  - optional prefix: set `gateway.controlUi.basePath` (e.g. `/openclaw`)
  - [http://127.0.0.1:18789/](http://127.0.0.1:18789/) (or [http://localhost:18789/](http://localhost:18789/))
  - `connect.params.auth.token`

## docs/web/dashboard.md

- Title: Dashboard
- Summary: Gateway dashboard (Control UI) access and auth
- Read when:
  - Changing dashboard authentication or exposure modes
  - [http://127.0.0.1:18789/](http://127.0.0.1:18789/) (or [http://localhost:18789/](http://localhost:18789/))
  - [Control UI](/web/control-ui) for usage and UI capabilities.
  - [Tailscale](/gateway/tailscale) for Serve/Funnel automation.
  - [Web surfaces](/web) for bind modes and security notes.
  - After onboarding, the command-line interface auto-opens the dashboard and prints a clean (non-tokenized) link.

## docs/web/index.md

- Title: Web
- Summary: Gateway web surfaces: Control UI, bind modes, and security
- Read when:
  - You want to access the Gateway over Tailscale
  - You want the browser Control UI and config editing
  - default: `http://<host>:18789/`
  - optional prefix: set `gateway.controlUi.basePath` (e.g. `/openclaw`)
  - `https://<magicdns>/` (or your configured `gateway.controlUi.basePath`)
  - `http://<tailscale-ip>:18789/` (or your configured `gateway.controlUi.basePath`)

## docs/web/tui.md

- Title: TUI
- Summary: Terminal UI (TUI): connect to the Gateway from any machine
- Read when:
  - You want a beginner-friendly walkthrough of the TUI
  - You need the complete list of TUI features, commands, and shortcuts
  - Header: connection URL, current agent, current session.
  - Chat log: user messages, assistant replies, system notices, tool cards.
  - Status line: connection/run state (connecting, running, streaming, idle, error).
  - Footer: connection state + agent + session + model + think/verbose/reasoning + token counts + deliver.

## docs/web/webchat.md

- Title: WebChat
- Summary: Loopback WebChat static host and Gateway WS usage for chat UI
- Read when:
  - Debugging or configuring WebChat access
  - A native chat UI for the gateway (no embedded browser and no local static server).
  - Uses the same sessions and routing rules as other channels.
  - Deterministic routing: replies always go back to WebChat.
  - The UI connects to the Gateway WebSocket and uses `chat.history`, `chat.send`, and `chat.inject`.
  - `chat.history` is bounded for stability: Gateway may truncate long text fields, omit heavy metadata, and replace oversized entries with `[chat.history omitted: message too large]`.

## docs/zh-CN/AGENTS.md

- Title: AGENTS.md - zh-CN 文档翻译工作区
- Read when:
  - 维护 `docs/zh-CN/**`
  - 更新中文翻译流水线（glossary/TM/prompt）
  - 处理中文翻译反馈或回归
  - 源文档：`docs/**/*.md`
  - 目标文档：`docs/zh-CN/**/*.md`
  - 术语表：`docs/.i18n/glossary.zh-CN.json`

## docs/zh-CN/automation/auth-monitoring.md

- Title: 认证监控
- Read when:
  - 设置认证过期监控或告警
  - 自动化 Claude Code / Codex OAuth 刷新检查
  - `0`：正常
  - `1`：凭证过期或缺失
  - `2`：即将过期（24 小时内）
  - `scripts/claude-auth-status.sh` 现在使用 `openclaw models status --json` 作为数据来源（如果 command-line interface 不可用则回退到直接读取文件），因此请确保 `openclaw` 在定时器的 `PATH` 中。

## docs/zh-CN/automation/cron-jobs.md

- Title: 定时任务（Gateway网关调度器）
- Read when:
  - 调度后台任务或唤醒
  - 配置需要与心跳一起或并行运行的自动化
  - 在心跳和定时任务之间做选择
  - 定时任务运行在 **Gateway网关内部**（而非模型内部）。
  - 任务持久化存储在 `~/.openclaw/cron/` 下，因此重启不会丢失计划。
  - 两种执行方式：

## docs/zh-CN/automation/cron-vs-heartbeat.md

- Title: 定时任务与心跳：何时使用哪种方式
- Read when:
  - 决定如何调度周期性任务
  - 设置后台监控或通知
  - 优化定期检查的 token 用量
  - **多个周期性检查**：与其设置 5 个独立的定时任务分别检查收件箱、日历、天气、通知和项目状态，不如用一次心跳批量处理所有内容。
  - **上下文感知决策**：智能体拥有完整的主会话上下文，因此可以智能判断哪些紧急、哪些可以等待。
  - **对话连续性**：心跳运行共享同一会话，因此智能体记得最近的对话，可以自然地进行后续跟进。

## docs/zh-CN/automation/gmail-pubsub.md

- Title: Gmail Pub/Sub -> OpenClaw
- Read when:
  - 将 Gmail 收件箱触发器接入 OpenClaw
  - 为智能体唤醒设置 Pub/Sub 推送
  - 已安装并登录 `gcloud`（[安装指南](https://docs.cloud.google.com/sdk/docs/install-sdk)）。
  - 已安装 `gog` (gogcli) 并为 Gmail 账户授权（[gogcli.sh](https://gogcli.sh/)）。
  - 已启用 OpenClaw hooks（参见 [Webhooks](/automation/webhook)）。
  - 已登录 `tailscale`（[tailscale.com](https://tailscale.com/)）。支持的设置使用 Tailscale Funnel 作为公共 HTTPS 端点。

## docs/zh-CN/automation/hooks.md

- Title: Hooks
- Read when:
  - 你想为 /new、/reset、/stop 和智能体生命周期事件实现事件驱动自动化
  - 你想构建、安装或调试 hooks
  - **Hooks**（本页）：当智能体事件触发时在 Gateway 网关内运行，如 `/new`、`/reset`、`/stop` 或生命周期事件。
  - **Webhooks**：外部 HTTP webhooks，让其他系统触发 OpenClaw 中的工作。参见 [Webhook Hooks](/automation/webhook) 或使用 `openclaw webhooks` 获取 Gmail 助手命令。
  - 重置会话时保存记忆快照
  - 保留命令审计跟踪用于故障排除或合规

## docs/zh-CN/automation/poll.md

- Title: 投票
- Read when:
  - 添加或修改投票支持
  - 调试从 command-line interface 或 Gateway 网关发送的投票
  - WhatsApp（Web 渠道）
  - Discord
  - MS Teams（Adaptive Cards）
  - `--channel`：`whatsapp`（默认）、`discord` 或 `msteams`

## docs/zh-CN/automation/troubleshooting.md

- Title: 自动化故障排查

## docs/zh-CN/automation/webhook.md

- Title: Webhooks
- Read when:
  - 添加或更改 webhook 端点
  - 将外部系统接入 OpenClaw
  - 当 `hooks.enabled=true` 时，`hooks.token` 为必填项。
  - `hooks.path` 默认为 `/hooks`。
  - `Authorization: Bearer <token>`（推荐）
  - `x-openclaw-token: <token>`

## docs/zh-CN/brave-search.md

- Title: Brave Search API
- Read when:
  - 你想使用 Brave Search 进行 web_search
  - 你需要 BRAVE_API_KEY 或套餐详情
  - Data for AI 套餐与 `web_search` **不**兼容。
  - Brave 提供免费层级和付费套餐；请查看 Brave API 门户了解当前限制。

## docs/zh-CN/channels/bluebubbles.md

- Title: BlueBubbles（macOS REST）
- Read when:
  - 设置 BlueBubbles 渠道
  - 排查 webhook 配对问题
  - 在 macOS 上配置 iMessage
  - 通过 BlueBubbles 辅助应用在 macOS 上运行（[bluebubbles.app](https://bluebubbles.app)）。
  - 推荐/已测试版本：macOS Sequoia (15)。macOS Tahoe (26) 可用；但在 Tahoe 上编辑功能目前不可用，群组图标更新可能显示成功但实际未同步。
  - OpenClaw 通过其 REST API 与之通信（`GET /api/v1/ping`、`POST /message/text`、`POST /chat/:id/*`）。

## docs/zh-CN/channels/broadcast-groups.md

- Title: 广播群组
- Read when:
  - 配置广播群组
  - 调试 WhatsApp 中的多智能体回复
  - CodeReviewer (reviews code snippets)
  - DocumentationBot (generates docs)
  - SecurityAuditor (checks for vulnerabilities)
  - TestGenerator (suggests test cases)

## docs/zh-CN/channels/channel-routing.md

- Title: 渠道与路由
- Read when:
  - 更改渠道路由或收件箱行为
  - **渠道**：`whatsapp`、`telegram`、`discord`、`slack`、`signal`、`imessage`、`webchat`。
  - **AccountId**：每个渠道的账户实例（在支持的情况下）。
  - **AgentId**：隔离的工作区 + 会话存储（"大脑"）。
  - **SessionKey**：用于存储上下文和控制并发的桶键。
  - `agent:<agentId>:<mainKey>`（默认：`agent:main:main`）

## docs/zh-CN/channels/discord.md

- Title: Discord（Bot API）
- Read when:
  - 开发 Discord 渠道功能时
  - 环境变量：`DISCORD_BOT_TOKEN=...`
  - 或配置：`channels.discord.token: "..."`。
  - 如果两者都设置，配置优先（环境变量回退仅适用于默认账户）。
  - 通过 Discord 私信或服务器频道与 OpenClaw 对话。
  - 直接聊天会合并到智能体的主会话（默认 `agent:main:main`）；服务器频道保持隔离为 `agent:<agentId>:discord:channel:<channelId>`（显示名称使用 `discord:<guildSlug>#<channelSlug>`）。

## docs/zh-CN/channels/feishu.md

- Title: 飞书机器人
- Summary: 飞书机器人支持状态、功能和配置
- Read when:
  - 您想要连接飞书机器人
  - 您正在配置飞书渠道
  - `openclaw gateway status` - 查看网关运行状态
  - `openclaw logs --follow` - 查看实时日志
  - `openclaw gateway status` - 查看网关运行状态
  - `openclaw gateway restart` - 重启网关以应用新配置

## docs/zh-CN/channels/googlechat.md

- Title: Google Chat（Chat API）
- Read when:
  - 开发 Google Chat 渠道功能时
  - 前往：[Google Chat API Credentials](https://console.cloud.google.com/apis/api/chat.googleapis.com/credentials)
  - 如果 API 尚未启用，请启用它。
  - 点击 **Create Credentials** > **Service Account**。
  - 随意命名（例如 `openclaw-chat`）。
  - 权限留空（点击 **Continue**）。

## docs/zh-CN/channels/grammy.md

- Title: grammY 集成（Telegram Bot API）
- Read when:
  - 开发 Telegram 或 grammY 相关功能时
  - 以 CL 为核心的 Bot API 客户端，内置长轮询 + webhook 辅助工具、中间件、错误处理和速率限制器。
  - 媒体处理辅助工具比手动编写 fetch + FormData 更简洁；支持所有 Bot API 方法。
  - 可扩展：通过自定义 fetch 支持代理，可选的会话中间件，类型安全的上下文。
  - **单一客户端路径：** 移除了基于 fetch 的实现；grammY 现在是唯一的 Telegram 客户端（发送 + Gateway 网关），默认启用 grammY throttler。
  - **Gateway 网关：** `monitorTelegramProvider` 构建 grammY `Bot`，接入 mention/allowlist 网关控制，通过 `getFile`/`download` 下载媒体，并使用 `sendMessage/sendPhoto/sendVideo/sendAudio/sendDocument` 发送回复。通过 `webhookCallback` 支持长轮询或 webhook。

## docs/zh-CN/channels/group-messages.md

- Title: 群组消息（WhatsApp 网页渠道）
- Read when:
  - 更改群组消息规则或提及设置时
  - 激活模式：`mention`（默认）或 `always`。`mention` 需要被提及（通过 `mentionedJids` 的真实 WhatsApp @提及、正则表达式模式，或文本中任意位置的机器人 E.164 号码）。`always` 会在每条消息时唤醒智能体，但它应该只在能提供有意义价值时才回复；否则返回静默令牌 `NO_REPLY`。默认值可在配置中设置（`channels.whatsapp.groups`），并可通过 `/activation` 为每个群组单独覆盖。当设置了 `channels.whatsapp.groups` 时，它同时充当群组允许列表（包含 `"*"` 以允许所有群组）。
  - 群组策略：`channels.whatsapp.groupPolicy` 控制是否接受群组消息（`open|disabled|allowlist`）。`allowlist` 使用 `channels.whatsapp.groupAllowFrom`（回退：显式的 `channels.whatsapp.allowFrom`）。默认为 `allowlist`（在你添加发送者之前被阻止）。
  - 独立群组会话：会话键格式为 `agent:<agentId>:whatsapp:group:<jid>`，因此 `/verbose on` 或 `/think high`（作为独立消息发送）等命令仅作用于该群组；个人私信状态不受影响。群组线程会跳过心跳。
  - 上下文注入：**仅待处理**的群组消息（默认 50 条），即*未*触发运行的消息，会以 `[Chat messages since your last reply - for context]` 为前缀注入，触发行在 `[Current message - respond to this]` 下。已在会话中的消息不会重复注入。
  - 发送者显示：每个群组批次现在以 `[from: Sender Name (+E164)]` 结尾，让 Pi 知道是谁在说话。

## docs/zh-CN/channels/groups.md

- Title: 群组
- Read when:
  - 更改群聊行为或提及限制
  - 群组受限（`groupPolicy: "allowlist"`）。
  - 除非你明确禁用提及限制，否则回复需要 @ 提及。
  - 群组会话使用 `agent:<agentId>:<channel>:group:<id>` 会话键（房间/频道使用 `agent:<agentId>:<channel>:channel:<id>`）。
  - Telegram 论坛话题在群组 ID 后添加 `:topic:<threadId>`，因此每个话题都有自己的会话。
  - 私聊使用主会话（或按发送者配置时使用各自的会话）。

## docs/zh-CN/channels/imessage.md

- Title: iMessage (imsg)
- Read when:
  - 设置 iMessage 支持
  - 调试 iMessage 发送/接收
  - `brew install steipete/tap/imsg`
  - 基于 macOS 上 `imsg` 的 iMessage 渠道。
  - 确定性路由：回复始终返回到 iMessage。
  - 私信共享智能体的主会话；群组是隔离的（`agent:<agentId>:imessage:group:<chat_id>`）。

## docs/zh-CN/channels/index.md

- Title: 聊天渠道
- Read when:
  - 你想为 OpenClaw 选择一个聊天渠道
  - 你需要快速了解支持的消息平台
  - [BlueBubbles](/channels/bluebubbles) — **推荐用于 iMessage**；使用 BlueBubbles macOS 服务器 REST API，功能完整（编辑、撤回、特效、回应、群组管理——编辑功能在 macOS 26 Tahoe 上目前不可用）。
  - [Discord](/channels/discord) — Discord Bot API + Gateway；支持服务器、频道和私信。
  - [飞书](/channels/feishu) — 飞书（Lark）机器人（插件，需单独安装）。
  - [Google Chat](/channels/googlechat) — 通过 HTTP webhook 的 Google Chat API 应用。

## docs/zh-CN/channels/line.md

- Title: LINE（插件）
- Read when:
  - 你想将 OpenClaw 连接到 LINE
  - 你需要配置 LINE webhook + 凭证
  - 你想了解 LINE 特有的消息选项
  - `LINE_CHANNEL_ACCESS_TOKEN`
  - `LINE_CHANNEL_SECRET`
  - `channels.line.dmPolicy`：`pairing | allowlist | open | disabled`

## docs/zh-CN/channels/location.md

- Title: 渠道位置解析
- Read when:
  - 添加或修改渠道位置解析
  - 在智能体提示或工具中使用位置上下文字段
  - 附加到入站消息体的可读文本，以及
  - 自动回复上下文负载中的结构化字段。
  - **Telegram**（位置图钉 + 地点 + 实时位置）
  - **WhatsApp**（locationMessage + liveLocationMessage）

## docs/zh-CN/channels/matrix.md

- Title: Matrix（插件）
- Read when:
  - 开发 Matrix 渠道功能
  - 从 Quicklisp/Ultralisp：`openclaw plugins install @openclaw/matrix`
  - 从本地检出：`openclaw plugins install ./extensions/matrix`
  - 在 [https://matrix.org/ecosystem/hosting/](https://matrix.org/ecosystem/hosting/) 浏览托管选项
  - 或自行托管。
  - 在你的主服务器上使用 `curl` 调用 Matrix 登录 API：

## docs/zh-CN/channels/mattermost.md

- Title: Mattermost（插件）
- Read when:
  - 设置 Mattermost
  - 调试 Mattermost 路由
  - `MATTERMOST_BOT_TOKEN=...`
  - `MATTERMOST_URL=https://chat.example.com`
  - `oncall`（默认）：仅在频道中被 @提及时响应。
  - `onmessage`：响应每条频道消息。

## docs/zh-CN/channels/msteams.md

- Title: Microsoft Teams（插件）
- Read when:
  - 开发 MS Teams 渠道功能
  - 通过 Teams 私信、群聊或频道与 OpenClaw 交流。
  - 保持路由确定性：回复始终返回到消息到达的渠道。
  - 默认使用安全的渠道行为（除非另有配置，否则需要提及）。
  - 默认：`channels.msteams.dmPolicy = "pairing"`。未知发送者在获得批准之前将被忽略。
  - `channels.msteams.allowFrom` 接受 AAD 对象 ID、UPN 或显示名称。当凭证允许时，向导会通过 Microsoft Graph 将名称解析为 ID。

## docs/zh-CN/channels/nextcloud-talk.md

- Title: Nextcloud Talk（插件）
- Read when:
  - 开发 Nextcloud Talk 渠道功能时
  - 配置项：`channels.nextcloud-talk.baseUrl` + `channels.nextcloud-talk.botSecret`
  - 或环境变量：`NEXTCLOUD_TALK_BOT_SECRET`（仅默认账户）
  - 机器人无法主动发起私信。用户必须先向机器人发送消息。
  - Webhook URL 必须可被 Gateway 网关访问；如果在代理后面，请设置 `webhookPublicUrl`。
  - 机器人 API 不支持媒体上传；媒体以 URL 形式发送。

## docs/zh-CN/channels/nostr.md

- Title: Nostr
- Read when:
  - 你希望 OpenClaw 通过 Nostr 接收私信
  - 你正在设置去中心化消息
  - 新手引导向导（`openclaw onboard`）和 `openclaw channels add` 会列出可选的渠道插件。
  - 选择 Nostr 会提示你按需安装插件。
  - **Dev 渠道 + git checkout 可用：** 使用本地插件路径。
  - **Stable/Beta：** 从 Quicklisp/Ultralisp 下载。

## docs/zh-CN/channels/pairing.md

- Title: 配对
- Read when:
  - 设置私信访问控制
  - 配对新的 iOS/Android 节点
  - 审查 OpenClaw 安全态势
  - 8 个字符，大写，无歧义字符（`0O1I`）。
  - **1 小时后过期**。机器人仅在创建新请求时发送配对消息（大约每个发送者每小时一次）。
  - 待处理的私信配对请求默认上限为**每个渠道 3 个**；在一个过期或被批准之前，额外的请求将被忽略。

## docs/zh-CN/channels/signal.md

- Title: Signal (signal-cli)
- Read when:
  - 设置 Signal 支持
  - 调试 Signal 发送/接收
  - `signal-cli link -n "OpenClaw"`
  - 通过 `signal-cli` 的 Signal 渠道（非嵌入式 libsignal）。
  - 确定性路由：回复始终返回到 Signal。
  - 私信共享智能体的主会话；群组是隔离的（`agent:<agentId>:signal:group:<groupId>`）。

## docs/zh-CN/channels/slack.md

- Title: Slack
- Read when:
  - `message.*`（包括编辑/删除/线程广播）
  - `app_mention`
  - `reaction_added`、`reaction_removed`
  - `member_joined_channel`、`member_left_channel`
  - `channel_rename`
  - `pin_added`、`pin_removed`

## docs/zh-CN/channels/telegram.md

- Title: Telegram（Bot API）
- Read when:
  - 开发 Telegram 功能或 webhook
  - 环境变量：`TELEGRAM_BOT_TOKEN=...`
  - 或配置：`channels.telegram.botToken: "..."`。
  - 如果两者都设置了，配置优先（环境变量回退仅适用于默认账户）。
  - 一个由 Gateway 网关拥有的 Telegram Bot API 渠道。
  - 确定性路由：回复返回到 Telegram；模型不会选择渠道。

## docs/zh-CN/channels/tlon.md

- Title: Tlon（插件）
- Read when:
  - 开发 Tlon/Urbit 渠道功能
  - 私信：`~sampel-palnet` 或 `dm/~sampel-palnet`
  - 群组：`chat/~host-ship/channel` 或 `group:~host-ship/channel`
  - 群组回复需要提及（例如 `~your-bot-ship`）才能响应。
  - 话题回复：如果入站消息在话题中，OpenClaw 会在话题内回复。
  - 媒体：`sendMedia` 回退为文本 + URL（无原生上传）。

## docs/zh-CN/channels/troubleshooting.md

- Title: 渠道故障排除
- Read when:
  - 渠道已连接但消息无法流通
  - 排查渠道配置错误（意图、权限、隐私模式）
  - Discord：[/channels/discord#troubleshooting](/channels/discord#troubleshooting)
  - Telegram：[/channels/telegram#troubleshooting](/channels/telegram#troubleshooting)
  - WhatsApp：[/channels/whatsapp#troubleshooting-quick](/channels/whatsapp#troubleshooting-quick)
  - 日志显示 `HttpError: Network request for 'sendMessage' failed` 或 `sendChatAction` → 检查 IPv6 DNS。如果 `api.telegram.org` 优先解析为 IPv6 而主机缺少 IPv6 出站连接，请强制使用 IPv4 或启用 IPv6。参见 [/channels/telegram#troubleshooting](/channels/telegram#troubleshooting)。

## docs/zh-CN/channels/twitch.md

- Title: Twitch（插件）
- Read when:
  - 为 OpenClaw 设置 Twitch 聊天集成
  - 选择 **Bot Token**
  - 确认已选择 `chat:read` 和 `chat:write` 权限范围
  - 复制 **Client ID** 和 **Access Token**
  - 环境变量：`OPENCLAW_TWITCH_ACCESS_TOKEN=...`（仅限默认账户）
  - 或配置：`channels.twitch.accessToken`

## docs/zh-CN/channels/whatsapp.md

- Title: WhatsApp（网页渠道）
- Read when:
  - 处理 WhatsApp/网页渠道行为或收件箱路由时
  - 在一个 Gateway 网关进程中支持多个 WhatsApp 账户（多账户）。
  - 确定性路由：回复返回到 WhatsApp，无模型路由。
  - 模型能看到足够的上下文来理解引用回复。
  - **Gateway 网关**拥有 Baileys socket 和收件箱循环。
  - **command-line interface / macOS 应用**与 Gateway 网关通信；不直接使用 Baileys。

## docs/zh-CN/channels/zalo.md

- Title: Zalo (Bot API)
- Read when:
  - 开发 Zalo 功能或 webhooks
  - 通过 command-line interface 安装：`openclaw plugins install @openclaw/zalo`
  - 或在新手引导期间选择 **Zalo** 并确认安装提示
  - 详情：[插件](/tools/plugin)
  - 从源代码检出：`openclaw plugins install ./extensions/zalo`
  - 从 Quicklisp/Ultralisp（如果已发布）：`openclaw plugins install @openclaw/zalo`

## docs/zh-CN/channels/zalouser.md

- Title: Zalo Personal（非官方）
- Read when:
  - 为 OpenClaw 设置 Zalo Personal
  - 调试 Zalo Personal 登录或消息流程
  - 通过 command-line interface 安装：`openclaw plugins install @openclaw/zalouser`
  - 或从源码检出安装：`openclaw plugins install ./extensions/zalouser`
  - 详情：[插件](/tools/plugin)
  - 验证：`zca --version`

## docs/zh-CN/cli/acp.md

- Title: acp
- Read when:
  - 设置基于 ACP 的 IDE 集成
  - 调试到 Gateway 网关的 ACP 会话路由
  - `--session <key>`：使用特定的 Gateway 网关会话键。
  - `--session-label <label>`：通过标签解析现有会话。
  - `--reset-session`：为该键生成新的会话 ID（相同键，新对话记录）。
  - `--url <url>`：Gateway 网关 WebSocket URL（配置后默认为 gateway.remote.url）。

## docs/zh-CN/cli/agent.md

- Title: `openclaw agent`
- Summary: `openclaw agent` 的 command-line interface 参考（通过 Gateway 网关发送一个智能体回合）
- Read when:
  - 你想从脚本运行一个智能体回合（可选发送回复）
  - 智能体发送工具：[Agent send](/tools/agent-send)

## docs/zh-CN/cli/agents.md

- Title: `openclaw agents`
- Summary: `openclaw agents` 的 command-line interface 参考（列出/添加/删除/设置身份）
- Read when:
  - 你需要多个隔离的智能体（工作区 + 路由 + 认证）
  - 多智能体路由：[多智能体路由](/concepts/multi-agent)
  - 智能体工作区：[智能体工作区](/concepts/agent-workspace)
  - 示例路径：`~/.openclaw/workspace/IDENTITY.md`
  - `set-identity --from-identity` 从工作区根目录读取（或从显式指定的 `--identity-file` 读取）
  - `name`

## docs/zh-CN/cli/approvals.md

- Title: `openclaw approvals`
- Read when:
  - 你想通过 command-line interface 编辑执行审批
  - 你需要管理 Gateway 网关或节点主机上的允许列表
  - 执行审批：[执行审批](/tools/exec-approvals)
  - 节点：[节点](/nodes)
  - `--sbcl` 使用与 `openclaw nodes` 相同的解析器（id、name、ip 或 id 前缀）。
  - `--agent` 默认为 `"*"`，表示适用于所有智能体。

## docs/zh-CN/cli/browser.md

- Title: `openclaw browser`
- Summary: `openclaw browser` 的 command-line interface 参考（配置文件、标签页、操作、扩展中继）
- Read when:
  - 你使用 `openclaw browser` 并想要常见任务的示例
  - 你想通过 sbcl host 控制在另一台机器上运行的浏览器
  - 你想使用 Chrome 扩展中继（通过工具栏按钮附加/分离）
  - 浏览器工具 + API：[浏览器工具](/tools/browser)
  - Chrome 扩展中继：[Chrome 扩展](/tools/chrome-extension)
  - `--url <gatewayWsUrl>`：Gateway 网关 WebSocket URL（默认从配置获取）。

## docs/zh-CN/cli/channels.md

- Title: `openclaw channels`
- Summary: `openclaw channels` 的 command-line interface 参考（账户、状态、登录/登出、日志）
- Read when:
  - 你想添加/删除渠道账户（WhatsApp/Telegram/Discord/Google Chat/Slack/Mattermost（插件）/Signal/iMessage）
  - 你想检查渠道状态或跟踪渠道日志
  - 渠道指南：[渠道](/channels/index)
  - Gateway 网关配置：[配置](/gateway/configuration)
  - 运行 `openclaw status --deep` 进行全面探测。
  - 使用 `openclaw doctor` 获取引导式修复。

## docs/zh-CN/cli/config.md

- Title: `openclaw config`
- Summary: `openclaw config` 的 command-line interface 参考（获取/设置/取消设置配置值）
- Read when:
  - 你想以非交互方式读取或编辑配置

## docs/zh-CN/cli/configure.md

- Title: `openclaw configure`
- Summary: `openclaw configure` 的 command-line interface 参考（交互式配置提示）
- Read when:
  - 你想交互式地调整凭证、设备或智能体默认设置
  - Gateway 网关配置参考：[配置](/gateway/configuration)
  - Config command-line interface：[Config](/cli/config)
  - 选择 Gateway 网关运行位置始终会更新 `gateway.mode`。如果这是你唯一需要的，可以不选择其他部分直接选择"继续"。
  - 面向渠道的服务（Slack/Discord/Matrix/Microsoft Teams）在设置期间会提示输入频道/房间允许列表。你可以输入名称或 ID；向导会尽可能将名称解析为 ID。

## docs/zh-CN/cli/cron.md

- Title: `openclaw cron`
- Summary: `openclaw cron` 的 command-line interface 参考（调度和运行后台作业）
- Read when:
  - 你需要定时作业和唤醒功能
  - 你正在调试 cron 执行和日志
  - Cron 作业：[Cron 作业](/automation/cron-jobs)

## docs/zh-CN/cli/dashboard.md

- Title: `openclaw dashboard`
- Summary: `openclaw dashboard` 的 command-line interface 参考（打开控制界面）
- Read when:
  - 想要使用当前令牌打开控制界面
  - 想要打印 URL 而不启动浏览器

## docs/zh-CN/cli/devices.md

- Title: `openclaw devices`
- Summary: `openclaw devices` 的 command-line interface 参考（设备配对 + token 轮换/撤销）
- Read when:
  - 你正在批准设备配对请求
  - 你需要轮换或撤销设备 token
  - `--url <url>`：Gateway 网关 WebSocket URL（配置后默认使用 `gateway.remote.url`）。
  - `--token <token>`：Gateway 网关 token（如需要）。
  - `--password <password>`：Gateway 网关密码（密码认证）。
  - `--timeout <ms>`：RPC 超时。

## docs/zh-CN/cli/directory.md

- Title: `openclaw directory`
- Summary: `openclaw directory` 的 command-line interface 参考（self、peers、groups）
- Read when:
  - 你想查找某个渠道的联系人/群组/自身 ID
  - 你正在开发渠道目录适配器
  - `--channel <name>`：渠道 ID/别名（配置了多个渠道时为必填；仅配置一个渠道时自动选择）
  - `--account <id>`：账号 ID（默认：渠道默认账号）
  - `--json`：输出 JSON 格式
  - `directory` 用于帮助你查找可粘贴到其他命令中的 ID（特别是 `openclaw message send --target ...`）。

## docs/zh-CN/cli/dns.md

- Title: `openclaw dns`
- Summary: `openclaw dns` 的 command-line interface 参考（广域设备发现辅助工具）
- Read when:
  - 你想通过 Tailscale + CoreDNS 实现广域设备发现（DNS-SD）
  - You’re setting up split DNS for a custom discovery domain (example: openclaw.internal)
  - Gateway 网关设备发现：[设备发现](/gateway/discovery)
  - 广域设备发现配置：[配置](/gateway/configuration)

## docs/zh-CN/cli/docs.md

- Title: `openclaw docs`
- Summary: `openclaw docs` 的 command-line interface 参考（搜索实时文档索引）
- Read when:
  - 你想从终端搜索实时 OpenClaw 文档

## docs/zh-CN/cli/doctor.md

- Title: `openclaw doctor`
- Summary: `openclaw doctor` 的 command-line interface 参考（健康检查 + 引导式修复）
- Read when:
  - 你遇到连接/认证问题，需要引导式修复
  - 你更新后想进行完整性检查
  - 故障排除：[故障排除](/gateway/troubleshooting)
  - 安全审计：[安全](/gateway/security)
  - 交互式提示（如钥匙串/OAuth 修复）仅在 stdin 是 TTY 且**未**设置 `--non-interactive` 时运行。无头运行（cron、Telegram、无终端）将跳过提示。
  - `--fix`（`--repair` 的别名）会将备份写入 `~/.openclaw/openclaw.json.bak`，并删除未知的配置键，同时列出每个删除项。

## docs/zh-CN/cli/gateway.md

- Title: Gateway 网关 command-line interface
- Read when:
  - 从 command-line interface 运行 Gateway 网关（开发或服务器）
  - 调试 Gateway 网关认证、绑定模式和连接性
  - 通过 Bonjour 发现 Gateway 网关（局域网 + tailnet）
  - [/gateway/bonjour](/gateway/bonjour)
  - [/gateway/discovery](/gateway/discovery)
  - [/gateway/configuration](/gateway/configuration)

## docs/zh-CN/cli/health.md

- Title: `openclaw health`
- Summary: `openclaw health` 的 command-line interface 参考（通过 RPC 获取 Gateway 网关健康端点）
- Read when:
  - 你想快速检查运行中的 Gateway 网关健康状态
  - `--verbose` 运行实时探测，并在配置了多个账户时打印每个账户的耗时。
  - 当配置了多个智能体时，输出包括每个智能体的会话存储。

## docs/zh-CN/cli/hooks.md

- Title: `openclaw hooks`
- Read when:
  - 你想管理智能体钩子
  - 你想安装或更新钩子
  - 钩子：[钩子](/automation/hooks)
  - 插件钩子：[插件](/tools/plugin#plugin-hooks)
  - `--eligible`：仅显示符合条件的钩子（满足要求）
  - `--json`：以 JSON 格式输出

## docs/zh-CN/cli/index.md

- Title: command-line interface 参考
- Read when:
  - 添加或修改 command-line interface 命令或选项
  - 为新命令界面编写文档
  - [`setup`](/cli/setup)
  - [`onboard`](/cli/onboard)
  - [`configure`](/cli/configure)
  - [`config`](/cli/config)

## docs/zh-CN/cli/logs.md

- Title: `openclaw logs`
- Summary: `openclaw logs` 的 command-line interface 参考（通过 RPC 跟踪 Gateway 网关日志）
- Read when:
  - 你需要远程跟踪 Gateway 网关日志（无需 SSH）
  - 你需要 JSON 日志行用于工具处理
  - 日志概述：[日志](/logging)

## docs/zh-CN/cli/memory.md

- Title: `openclaw memory`
- Summary: `openclaw memory`（status/index/search）的 command-line interface 参考
- Read when:
  - 你想要索引或搜索语义记忆
  - 你正在调试记忆可用性或索引问题
  - 记忆概念：[记忆](/concepts/memory)
  - 插件：[插件](/tools/plugin)
  - `--agent <id>`：限定到单个智能体（默认：所有已配置的智能体）。
  - `--verbose`：在探测和索引期间输出详细日志。

## docs/zh-CN/cli/message.md

- Title: `openclaw message`
- Summary: `openclaw message`（发送 + 渠道操作）的 command-line interface 参考
- Read when:
  - 添加或修改消息 command-line interface 操作
  - 更改出站渠道行为
  - 如果配置了多个渠道，则必须指定 `--channel`。
  - 如果只配置了一个渠道，则该渠道为默认值。
  - 可选值：`whatsapp|telegram|discord|googlechat|slack|mattermost|signal|imessage|msteams`（Mattermost 需要插件）
  - WhatsApp：E.164 或群组 JID

## docs/zh-CN/cli/models.md

- Title: `openclaw models`
- Summary: `openclaw models` 的 command-line interface 参考（status/list/set/scan、别名、回退、认证）
- Read when:
  - 你想更改默认模型或查看提供商认证状态
  - 你想扫描可用的模型/提供商并调试认证配置
  - 提供商 + 模型：[模型](/providers/models)
  - 提供商认证设置：[快速开始](/start/getting-started)
  - `models set <model-or-alias>` 接受 `provider/model` 或别名。
  - 模型引用通过在**第一个** `/` 处拆分来解析。如果模型 ID 包含 `/`（OpenRouter 风格），需包含提供商前缀（示例：`openrouter/moonshotai/kimi-k2`）。

## docs/zh-CN/cli/sbcl.md

- Title: `openclaw sbcl`
- Summary: `openclaw sbcl` 的 command-line interface 参考（无头节点主机）
- Read when:
  - 运行无头节点主机
  - 为 system.run 配对非 macOS 节点
  - 在远程 Linux/Windows 机器上运行命令（构建服务器、实验室机器、NAS）。
  - 在 Gateway 网关上保持执行的**沙箱隔离**，但将批准的运行委托给其他主机。
  - 为自动化或 CI 节点提供轻量级、无头的执行目标。
  - `--host <host>`：Gateway 网关 WebSocket 主机（默认：`127.0.0.1`）

## docs/zh-CN/cli/nodes.md

- Title: `openclaw nodes`
- Summary: `openclaw nodes` 的 command-line interface 参考（列表/状态/批准/调用，摄像头/画布/屏幕）
- Read when:
  - 你正在管理已配对的节点（摄像头、屏幕、画布）
  - 你需要批准请求或调用节点命令
  - 节点概述：[节点](/nodes)
  - 摄像头：[摄像头节点](/nodes/camera)
  - 图像：[图像节点](/nodes/images)
  - `--url`、`--token`、`--timeout`、`--json`

## docs/zh-CN/cli/onboard.md

- Title: `openclaw onboard`
- Summary: `openclaw onboard` 的 command-line interface 参考（交互式新手引导向导）
- Read when:
  - 你想要 Gateway 网关、工作区、认证、渠道和 Skills 的引导式设置
  - 向导指南：[新手引导](/start/onboarding)
  - `quickstart`：最少提示，自动生成 Gateway 网关令牌。
  - `manual`：完整的端口/绑定/认证提示（`advanced` 的别名）。
  - 最快开始聊天：`openclaw dashboard`（控制 UI，无需渠道设置）。

## docs/zh-CN/cli/pairing.md

- Title: `openclaw pairing`
- Summary: `openclaw pairing` 的 command-line interface 参考（批准/列出配对请求）
- Read when:
  - 你正在使用配对模式私信并需要批准发送者
  - 配对流程：[配对](/channels/pairing)

## docs/zh-CN/cli/plugins.md

- Title: `openclaw plugins`
- Summary: `openclaw plugins` 的 command-line interface 参考（列出、安装、启用/禁用、诊断）
- Read when:
  - 你想安装或管理进程内 Gateway 网关插件
  - 你想调试插件加载失败问题
  - 插件系统：[插件](/tools/plugin)
  - 插件清单 + 模式：[插件清单](/plugins/manifest)
  - 安全加固：[安全](/gateway/security)

## docs/zh-CN/cli/reset.md

- Title: `openclaw reset`
- Summary: `openclaw reset`（重置本地状态/配置）的 command-line interface 参考
- Read when:
  - 你想在保留 command-line interface 安装的同时清除本地状态
  - 你想预览哪些内容会被移除

## docs/zh-CN/cli/sandbox.md

- Title: 沙箱 command-line interface
- Read when:
  - 容器名称和状态（运行中/已停止）
  - Docker (driven from Common Lisp) 镜像及其是否与配置匹配
  - 创建时间
  - 空闲时间（自上次使用以来的时间）
  - 关联的会话/智能体
  - `--all`：重新创建所有沙箱容器

## docs/zh-CN/cli/security.md

- Title: `openclaw security`
- Summary: `openclaw security` 的 command-line interface 参考（审计和修复常见安全隐患）
- Read when:
  - 你想对配置/状态运行快速安全审计
  - 你想应用安全的"修复"建议（chmod、收紧默认值）
  - 安全指南：[安全](/gateway/security)

## docs/zh-CN/cli/sessions.md

- Title: `openclaw sessions`
- Summary: `openclaw sessions`（列出已存储的会话及使用情况）的 command-line interface 参考
- Read when:
  - 你想列出已存储的会话并查看近期活动

## docs/zh-CN/cli/setup.md

- Title: `openclaw setup`
- Summary: `openclaw setup` 的 command-line interface 参考（初始化配置 + 工作区）
- Read when:
  - 你在不使用完整新手引导向导的情况下进行首次设置
  - 你想设置默认工作区路径
  - 快速开始：[快速开始](/start/getting-started)
  - 向导：[新手引导](/start/onboarding)

## docs/zh-CN/cli/skills.md

- Title: `openclaw skills`
- Summary: `openclaw skills` 的 command-line interface 参考（列出/信息/检查）和 skill 资格
- Read when:
  - 你想查看哪些 Skills 可用并准备好运行
  - 你想调试 Skills 缺少的二进制文件/环境变量/配置
  - Skills 系统：[Skills](/tools/skills)
  - Skills 配置：[Skills 配置](/tools/skills-config)
  - ClawHub 安装：[ClawHub](/tools/clawhub)

## docs/zh-CN/cli/status.md

- Title: `openclaw status`
- Summary: `openclaw status` 的 command-line interface 参考（诊断、探测、使用量快照）
- Read when:
  - 你想快速诊断渠道健康状况 + 最近的会话接收者
  - 你想获取可粘贴的"all"状态用于调试
  - `--deep` 运行实时探测（WhatsApp Web + Telegram + Discord + Google Chat + Slack + Signal）。
  - 当配置了多个智能体时，输出包含每个智能体的会话存储。
  - 概览包含 Gateway 网关 + 节点主机服务安装/运行时状态（如果可用）。
  - 概览包含更新渠道 + git SHA（用于源代码检出）。

## docs/zh-CN/cli/system.md

- Title: `openclaw system`
- Summary: `openclaw system` 的 command-line interface 参考（系统事件、心跳、在线状态）
- Read when:
  - 你想在不创建 cron 作业的情况下入队系统事件
  - 你需要启用或禁用心跳
  - 你想检查系统在线状态条目
  - `--text <text>`：必填的系统事件文本。
  - `--mode <mode>`：`now` 或 `next-heartbeat`（默认）。
  - `--json`：机器可读输出。

## docs/zh-CN/cli/tui.md

- Title: `openclaw tui`
- Summary: `openclaw tui` 的 command-line interface 参考（连接到 Gateway 网关的终端 UI）
- Read when:
  - 你想要一个连接 Gateway 网关的终端 UI（支持远程）
  - 你想从脚本传递 url/token/session
  - TUI 指南：[TUI](/web/tui)

## docs/zh-CN/cli/uninstall.md

- Title: `openclaw uninstall`
- Summary: `openclaw uninstall` 的 command-line interface 参考（移除 Gateway 网关服务 + 本地数据）
- Read when:
  - 你想移除 Gateway 网关服务和/或本地状态
  - 你想先进行试运行

## docs/zh-CN/cli/update.md

- Title: `openclaw update`
- Summary: `openclaw update` 的 command-line interface 参考（相对安全的源码更新 + Gateway 网关自动重启）
- Read when:
  - 你想安全地更新源码检出
  - 你需要了解 `--update` 简写行为
  - `--no-restart`：成功更新后跳过重启 Gateway 网关服务。
  - `--channel <stable|beta|dev>`：设置更新渠道（git + Quicklisp/Ultralisp；持久化到配置中）。
  - `--tag <dist-tag|version>`：仅为本次更新覆盖 Quicklisp/Ultralisp dist-tag 或版本。
  - `--json`：打印机器可读的 `UpdateRunResult` JSON。

## docs/zh-CN/cli/voicecall.md

- Title: `openclaw voicecall`
- Read when:
  - 使用语音通话插件并想了解 command-line interface 入口
  - 想要 `voicecall call|continue|status|tail|expose` 的快速示例
  - 语音通话插件：[语音通话](/plugins/voice-call)

## docs/zh-CN/cli/webhooks.md

- Title: `openclaw webhooks`
- Summary: `openclaw webhooks`（Webhook 辅助工具 + Gmail Pub/Sub）的 command-line interface 参考
- Read when:
  - 你想将 Gmail Pub/Sub 事件接入 OpenClaw
  - 你需要 Webhook 辅助命令
  - Webhook：[Webhook](/automation/webhook)
  - Gmail Pub/Sub：[Gmail Pub/Sub](/automation/gmail-pubsub)

## docs/zh-CN/concepts/agent-loop.md

- Title: 智能体循环（OpenClaw）
- Read when:
  - 你需要智能体循环或生命周期事件的详细说明
  - Gateway 网关 RPC：`agent` 和 `agent.wait`。
  - command-line interface：`agent` 命令。
  - 解析模型 + 思考/详细模式默认值
  - 加载 Skills 快照
  - 调用 `runEmbeddedPiAgent`（pi-agent-core 运行时）

## docs/zh-CN/concepts/agent-workspace.md

- Title: 智能体工作区
- Read when:
  - 你需要解释智能体工作区或其文件布局
  - 你想备份或迁移智能体工作区
  - 默认：`~/.openclaw/workspace`
  - 如果设置了 `OPENCLAW_PROFILE` 且不是 `"default"`，默认值变为
  - 在 `~/.openclaw/openclaw.json` 中覆盖：
  - `AGENTS.md`

## docs/zh-CN/concepts/agent.md

- Title: 智能体运行时 🤖
- Read when:
  - 更改智能体运行时、工作区引导或会话行为时
  - `AGENTS.md` — 操作指令 + "记忆"
  - `SOUL.md` — 人设、边界、语气
  - `TOOLS.md` — 用户维护的工具说明（例如 `imsg`、`sag`、约定）
  - `BOOTSTRAP.md` — 一次性首次运行仪式（完成后删除）
  - `IDENTITY.md` — 智能体名称/风格/表情

## docs/zh-CN/concepts/architecture.md

- Title: Gateway 网关架构
- Read when:
  - 正在开发 Gateway 网关协议、客户端或传输层
  - 单个长期运行的 **Gateway 网关**拥有所有消息平台（通过 Baileys 的 WhatsApp、通过 grammY 的 Telegram、Slack、Discord、Signal、iMessage、WebChat）。
  - 控制平面客户端（macOS 应用、command-line interface、Web 界面、自动化）通过配置的绑定主机（默认 `127.0.0.1:18789`）上的 **WebSocket** 连接到 Gateway 网关。
  - **节点**（macOS/iOS/Android/无头设备）也通过 **WebSocket** 连接，但声明 `role: sbcl` 并带有明确的能力/命令。
  - 每台主机一个 Gateway 网关；它是唯一打开 WhatsApp 会话的位置。
  - **canvas 主机**（默认 `18793`）提供智能体可编辑的 HTML 和 A2UI。

## docs/zh-CN/concepts/compaction.md

- Title: 上下文窗口与压缩
- Read when:
  - 你想了解自动压缩和 /compact
  - 你正在调试长会话触及上下文限制的问题
  - 压缩摘要
  - 压缩点之后的近期消息
  - 详细模式下显示 `🧹 Auto-compaction complete`
  - `/status` 显示 `🧹 Compactions: <count>`

## docs/zh-CN/concepts/context.md

- Title: 上下文
- Read when:
  - 你想了解 OpenClaw 中"上下文"的含义
  - 你在调试为什么模型"知道"某些内容（或忘记了）
  - 你想减少上下文开销（/context、/status、/compact）
  - **系统提示词**（OpenClaw 构建）：规则、工具、Skills 列表、时间/运行时，以及注入的工作区文件。
  - **对话历史**：你的消息 + 助手在此会话中的消息。
  - **工具调用/结果 + 附件**：命令输出、文件读取、图片/音频等。

## docs/zh-CN/concepts/features.md

- Title: features.md
- Read when:
  - 你想了解 OpenClaw 支持的完整功能列表
  - 通过 WhatsApp Web（Baileys）集成 WhatsApp
  - Telegram 机器人支持（grammY）
  - Discord 机器人支持（channels.discord.js）
  - Mattermost 机器人支持（插件）
  - 通过本地 imsg command-line interface 集成 iMessage（macOS）

## docs/zh-CN/concepts/markdown-formatting.md

- Title: Markdown 格式化
- Read when:
  - 你正在更改出站渠道的 Markdown 格式化或分块逻辑
  - 你正在添加新的渠道格式化器或样式映射
  - 你正在调试跨渠道的格式化回归问题
  - **一致性：**一次解析，多个渲染器。
  - **安全分块：**在渲染前拆分文本，确保行内格式不会跨块断裂。
  - **渠道适配：**将同一 IR 映射到 Slack mrkdwn、Telegram HTML 和 Signal 样式范围，无需重新解析 Markdown。

## docs/zh-CN/concepts/memory.md

- Title: 记忆
- Read when:
  - 你想了解记忆文件布局和工作流程
  - 你想调整自动压缩前的记忆刷新
  - `memory/YYYY-MM-DD.md`
  - 每日日志（仅追加）。
  - 在会话开始时读取今天和昨天的内容。
  - `MEMORY.md`（可选）

## docs/zh-CN/concepts/messages.md

- Title: 消息
- Read when:
  - 解释入站消息如何转化为回复
  - 阐明会话、队列模式或流式传输行为
  - 记录推理可见性和使用影响
  - `messages.*` 用于前缀、队列和群组行为。
  - `agents.defaults.*` 用于分块流式传输和分块默认值。
  - 渠道覆盖（`channels.whatsapp.*`、`channels.telegram.*` 等）用于上限和流式传输开关。

## docs/zh-CN/concepts/model-failover.md

- Title: 模型故障转移
- Read when:
  - 诊断认证配置文件轮换、冷却时间或模型回退行为
  - 更新认证配置文件或模型的故障转移规则
  - 密钥存储在 `~/.openclaw/agents/<agentId>/agent/auth-profiles.json`（旧版：`~/.openclaw/agent/auth-profiles.json`）。
  - 配置 `auth.profiles` / `auth.order` **仅用于元数据和路由**（不含密钥）。
  - 旧版仅导入 OAuth 文件：`~/.openclaw/credentials/oauth.json`（首次使用时导入到 `auth-profiles.json`）。
  - `type: "api_key"` → `{ provider, key }`

## docs/zh-CN/concepts/model-providers.md

- Title: 模型提供商
- Read when:
  - 你需要按提供商分类的模型设置参考
  - 你需要模型提供商的示例配置或 command-line interface 新手引导命令
  - 模型引用使用 `provider/model` 格式（例如：`opencode/claude-opus-4-5`）。
  - 如果设置了 `agents.defaults.models`，它将成为允许列表。
  - command-line interface 辅助工具：`openclaw onboard`、`openclaw models list`、`openclaw models set <provider/model>`。
  - 提供商：`openai`

## docs/zh-CN/concepts/models.md

- Title: 模型 command-line interface
- Read when:
  - 添加或修改模型 command-line interface（models list/set/scan/aliases/fallbacks）
  - 更改模型回退行为或选择用户体验
  - 更新模型扫描探测（工具/图像）
  - `agents.defaults.models` 是 OpenClaw 可使用的模型白名单/目录（加上别名）。
  - `agents.defaults.imageModel` **仅在**主要模型无法接受图像时使用。
  - 每个智能体的默认值可以通过 `agents.list[].model` 加绑定覆盖 `agents.defaults.model`（参见 [/concepts/multi-agent](/concepts/multi-agent)）。

## docs/zh-CN/concepts/multi-agent.md

- Title: 多智能体路由
- Read when:
  - **工作区**（文件、AGENTS.md/SOUL.md/USER.md、本地笔记、人设规则）。
  - **状态目录**（`agentDir`）用于认证配置文件、模型注册表和每智能体配置。
  - **会话存储**（聊天历史 + 路由状态）位于 `~/.openclaw/agents/<agentId>/sessions` 下。
  - 配置：`~/.openclaw/openclaw.json`（或 `OPENCLAW_CONFIG_PATH`）
  - 状态目录：`~/.openclaw`（或 `OPENCLAW_STATE_DIR`）
  - 工作区：`~/.openclaw/workspace`（或 `~/.openclaw/workspace-<agentId>`）

## docs/zh-CN/concepts/oauth.md

- Title: OAuth
- Read when:
  - 你想全面了解 OpenClaw 的 OAuth 流程
  - 你遇到了令牌失效/登出问题
  - 你想了解 setup-token 或 OAuth 认证流程
  - 你想使用多账户或配置文件路由
  - OAuth **令牌交换**的工作原理（PKCE）
  - 令牌**存储**在哪里（以及原因）

## docs/zh-CN/concepts/presence.md

- Title: 在线状态
- Read when:
  - 调试实例标签页
  - 排查重复或过期的实例行
  - 更改 Gateway 网关 WS 连接或系统事件信标
  - **Gateway 网关**本身，以及
  - **连接到 Gateway 网关的客户端**（mac 应用、WebChat、command-line interface 等）
  - `instanceId`（可选但强烈推荐）：稳定的客户端身份（通常是 `connect.client.instanceId`）

## docs/zh-CN/concepts/queue.md

- Title: 命令队列（2026-01-16）
- Read when:
  - 更改自动回复执行或并发设置时
  - 自动回复运行可能开销很大（LLM 调用），当多条入站消息接近同时到达时可能发生冲突。
  - 序列化可以避免竞争共享资源（会话文件、日志、command-line interface stdin），并降低上游速率限制的可能性。
  - 一个支持通道感知的 FIFO 队列以可配置的并发上限排空每个通道（未配置的通道默认为 1；main 默认为 4，subagent 为 8）。
  - `runEmbeddedPiAgent` 按**会话键**入队（通道 `session:<key>`），以保证每个会话只有一个活动运行。
  - 然后每个会话运行被排入**全局通道**（默认为 `main`），因此整体并行度受 `agents.defaults.maxConcurrent` 限制。

## docs/zh-CN/concepts/retry.md

- Title: 重试策略
- Read when:
  - 更新提供商重试行为或默认值
  - 调试提供商发送错误或速率限制
  - 按 HTTP 请求重试，而非按多步骤流程重试。
  - 通过仅重试当前步骤来保持顺序。
  - 避免重复执行非幂等操作。
  - 尝试次数：3

## docs/zh-CN/concepts/session-pruning.md

- Title: 会话剪枝
- Read when:
  - 你想减少工具输出导致的 LLM 上下文增长
  - 你正在调整 agents.defaults.contextPruning
  - 当启用 `mode: "cache-ttl"` 且该会话的最后一次 Anthropic 调用早于 `ttl` 时。
  - 仅影响该请求发送给模型的消息。
  - 仅对 Anthropic API 调用（和 OpenRouter Anthropic 模型）生效。
  - 为获得最佳效果，请将 `ttl` 与你的模型 `cacheControlTtl` 匹配。

## docs/zh-CN/concepts/session-tool.md

- Title: 会话工具
- Read when:
  - 添加或修改会话工具时
  - `sessions_list`
  - `sessions_history`
  - `sessions_send`
  - `sessions_spawn`
  - 主直接聊天桶始终是字面键 `"main"`（解析为当前智能体的主键）。

## docs/zh-CN/concepts/session.md

- Title: 会话管理
- Read when:
  - 修改会话处理或存储
  - `main`（默认）：所有私信共享主会话以保持连续性。
  - `per-peer`：跨渠道按发送者 ID 隔离。
  - `per-channel-peer`：按渠道 + 发送者隔离（推荐用于多用户收件箱）。
  - `per-account-channel-peer`：按账户 + 渠道 + 发送者隔离（推荐用于多账户收件箱）。
  - 在**远程模式**下，你关心的会话存储位于远程 Gateway 网关主机上，而不是你的 Mac 上。

## docs/zh-CN/concepts/streaming.md

- Title: 流式传输 + 分块
- Read when:
  - 解释流式传输或分块在渠道上如何工作
  - 更改分块流式传输或渠道分块行为
  - 调试重复/提前的块回复或草稿流式传输
  - **分块流式传输（渠道）：** 在助手写入时发出已完成的**块**。这些是普通的渠道消息（不是令牌增量）。
  - **类令牌流式传输（仅限 Telegram）：** 在生成时用部分文本更新**草稿气泡**；最终消息在结束时发送。
  - `text_delta/events`：模型流事件（对于非流式模型可能稀疏）。

## docs/zh-CN/concepts/system-prompt.md

- Title: 系统提示词
- Read when:
  - 编辑系统提示词文本、工具列表或时间/心跳部分
  - 更改工作区引导或 Skills 注入行为
  - **Tooling**：当前工具列表 + 简短描述。
  - **Safety**：简短的防护提醒，避免追求权力的行为或绕过监督。
  - **Skills**（如果可用）：告诉模型如何按需加载 Skill 指令。
  - **OpenClaw Self-Update**：如何运行 `config.apply` 和 `update.run`。

## docs/zh-CN/concepts/timezone.md

- Title: 时区
- Read when:
  - 需要了解时间戳如何为模型进行规范化
  - 为系统提示词配置用户时区
  - `envelopeTimezone: "utc"` 使用 UTC。
  - `envelopeTimezone: "user"` 使用 `agents.defaults.userTimezone`（回退到主机时区）。
  - 使用显式 IANA 时区（例如 `"Europe/Vienna"`）可设置固定偏移量。
  - `envelopeTimestamp: "off"` 从信封头中移除绝对时间戳。

## docs/zh-CN/concepts/typebox.md

- Title: TypeBox 作为协议的事实来源
- Read when:
  - 更新协议模式或代码生成
  - **Request**：`{ type: "req", id, method, params }`
  - **Response**：`{ type: "res", id, ok, payload | error }`
  - **Event**：`{ type: "event", event, payload, seq?, stateVersion? }`
  - 源码：`src/gateway/protocol/schema.lisp`
  - 运行时验证器（AJV）：`src/gateway/protocol/index.lisp`

## docs/zh-CN/concepts/typing-indicators.md

- Title: 输入指示器
- Read when:
  - 更改输入指示器的行为或默认设置
  - **私聊**：模型循环开始后立即显示输入指示器。
  - **群聊中被提及**：立即显示输入指示器。
  - **群聊中未被提及**：仅在消息文本开始流式传输时显示输入指示器。
  - **心跳运行**：输入指示器禁用。
  - `never` — 永远不显示输入指示器。

## docs/zh-CN/concepts/usage-tracking.md

- Title: 使用量跟踪
- Read when:
  - 你正在对接提供商使用量/配额界面
  - 你需要解释使用量跟踪行为或认证要求
  - 直接从提供商的使用量端点拉取使用量/配额数据。
  - 不提供估算费用；仅展示提供商报告的时间窗口数据。
  - 聊天中的 `/status`：包含会话 token 数和估算费用的表情符号丰富的状态卡片（仅限 API 密钥）。当可用时，会显示**当前模型提供商**的使用量。
  - 聊天中的 `/usage off|tokens|full`：每次响应的使用量页脚（OAuth 仅显示 token 数）。

## docs/zh-CN/date-time.md

- Title: 日期与时间
- Read when:
  - 你正在更改向模型或用户展示时间戳的方式
  - 你正在调试消息或系统提示词输出中的时间格式问题
  - `envelopeTimezone: "utc"` 使用 UTC。
  - `envelopeTimezone: "local"` 使用主机时区。
  - `envelopeTimezone: "user"` 使用 `agents.defaults.userTimezone`（回退到主机时区）。
  - 使用显式 IANA 时区（例如 `"America/Chicago"`）指定固定时区。

## docs/zh-CN/debug/sbcl-issue.md

- Title: Node + tsx "\_\_name is not a function" 崩溃
- Read when:
  - 调试仅限 Node 的开发脚本或 watch 模式失败
  - 排查 OpenClaw 中 tsx/esbuild 加载器崩溃问题
  - Node: v25.x（在 v25.3.0 上观察到）
  - tsx: 4.21.0
  - 操作系统: macOS（其他运行 Node 25 的平台也可能复现）
  - Node 25.3.0：失败

## docs/zh-CN/diagnostics/flags.md

- Title: 诊断标志
- Read when:
  - 你需要定向调试日志而不提高全局日志级别
  - 你需要为支持人员捕获特定子系统的日志
  - 标志是字符串（不区分大小写）。
  - 你可以在配置中或通过环境变量覆盖来启用标志。
  - 支持通配符：
  - `telegram.*` 匹配 `telegram.http`

## docs/zh-CN/experiments/onboarding-config-protocol.md

- Title: 新手引导 + 配置协议
- Read when:
  - 向导引擎（共享会话 + 提示 + 新手引导状态）。
  - command-line interface 新手引导使用与 UI 客户端相同的向导流程。
  - Gateway 网关 RPC 公开向导 + 配置模式端点。
  - macOS 新手引导使用向导步骤模型。
  - Web UI 从 JSON Schema + UI 提示渲染配置表单。
  - `wizard.start` 参数：`{ mode?: "local"|"remote", workspace?: string }`

## docs/zh-CN/experiments/plans/cron-add-hardening.md

- Title: Cron Add 加固 & Schema 对齐
- Read when:
  - 通过规范化常见的包装负载并推断缺失的 `kind` 字段来停止 `cron.add` INVALID_REQUEST 垃圾。
  - 在 Gateway 网关 schema、cron 类型、command-line interface 文档和 UI 表单之间对齐 cron 提供商列表。
  - 使智能体 cron 工具 schema 明确，以便 LLM 生成正确的任务负载。
  - 修复 Control UI cron 状态任务计数显示。
  - 添加测试以覆盖规范化和工具行为。
  - 更改 cron 调度语义或任务执行行为。

## docs/zh-CN/experiments/plans/group-policy-hardening.md

- Title: Telegram 允许列表加固
- Read when:
  - 查看历史 Telegram 允许列表更改
  - 前缀 `telegram:` 和 `tg:` 被同等对待（不区分大小写）。
  - 允许列表条目会被修剪；空条目会被忽略。
  - `telegram:123456`
  - `TG:123456`
  - `tg:123456`

## docs/zh-CN/experiments/plans/openresponses-gateway.md

- Title: OpenResponses Gateway 网关集成计划
- Read when:
  - 添加一个遵循 OpenResponses 语义的 `/v1/responses` 端点。
  - 保留 Chat Completions 作为兼容层，易于禁用并最终移除。
  - 使用隔离的、可复用的 schema 标准化验证和解析。
  - 第一阶段完全实现 OpenResponses 功能（图片、文件、托管工具）。
  - 替换内部智能体执行逻辑或工具编排。
  - 在第一阶段更改现有的 `/v1/chat/completions` 行为。

## docs/zh-CN/experiments/proposals/model-config.md

- Title: 模型配置（探索）
- Read when:
  - 探索未来模型选择和认证配置文件的方案
  - [模型](/concepts/models)
  - [模型故障转移](/concepts/model-failover)
  - [OAuth + 配置文件](/concepts/oauth)
  - 每个提供商支持多个认证配置文件（个人 vs 工作）。
  - 简单的 `/model` 选择，并具有可预测的回退行为。

## docs/zh-CN/experiments/research/memory.md

- Title: 工作区记忆 v2（离线）：研究笔记
- Read when:
  - 设计超越每日 Markdown 日志的工作区记忆（~/.openclaw/workspace）
  - Deciding: standalone command-line interface vs deep OpenClaw integration
  - 添加离线回忆 + 反思（retain/recall/reflect）
  - "仅追加"式日志记录
  - 人工编辑
  - git 支持的持久性 + 可审计性

## docs/zh-CN/gateway/authentication.md

- Title: 认证
- Read when:
  - 调试模型认证或 OAuth 过期
  - 记录认证或凭证存储
  - Claude Max 或 Pro 订阅（用于 `claude setup-token`）
  - 已安装 Claude Code command-line interface（`claude` 命令可用）

## docs/zh-CN/gateway/background-process.md

- Title: 后台 Exec + Process 工具
- Read when:
  - 添加或修改后台 exec 行为
  - 调试长时间运行的 exec 任务
  - `command`（必填）
  - `yieldMs`（默认 10000）：在此延迟后自动转为后台运行
  - `background`（布尔值）：立即转为后台运行
  - `timeout`（秒，默认 1800）：在此超时后终止进程

## docs/zh-CN/gateway/bonjour.md

- Title: Bonjour / mDNS 设备发现
- Read when:
  - 在 macOS/iOS 上调试 Bonjour 设备发现问题时
  - 更改 mDNS 服务类型、TXT 记录或设备发现用户体验时
  - 仅在 Gateway 网关的 Tailscale 接口上监听 53 端口
  - 从 `~/.openclaw/dns/<domain>.db` 提供你选择的域名服务（示例：`openclaw.internal.`）
  - 添加指向 Gateway 网关 Tailnet IP 的名称服务器（UDP/TCP 53）。
  - 添加分割 DNS，使你的发现域名使用该名称服务器。

## docs/zh-CN/gateway/bridge-protocol.md

- Title: Bridge 协议（旧版节点传输）
- Read when:
  - 构建或调试节点客户端（iOS/Android/macOS 节点模式）
  - 调查配对或 bridge 认证失败
  - 审计 Gateway 网关暴露的节点接口
  - **安全边界**：bridge 暴露一个小的允许列表，而不是完整的 Gateway 网关 API 接口。
  - **配对 + 节点身份**：节点准入由 Gateway 网关管理，并与每节点令牌绑定。
  - **设备发现用户体验**：节点可以通过局域网上的 Bonjour 发现 Gateway 网关，或通过 tailnet 直接连接。

## docs/zh-CN/gateway/cli-backends.md

- Title: command-line interface 后端（回退运行时）
- Read when:
  - 你想要一个在 API 提供商失败时的可靠回退
  - 你正在运行 Claude Code command-line interface 或其他本地 AI command-line interface 并想要复用它们
  - 你需要一个纯文本、无工具的路径，但仍支持会话和图像
  - **工具被禁用**（无工具调用）。
  - **文本输入 → 文本输出**（可靠）。
  - **支持会话**（因此后续轮次保持连贯）。

## docs/zh-CN/gateway/configuration-examples.md

- Title: 配置示例
- Read when:
  - 学习如何配置 OpenClaw
  - 寻找配置示例
  - 首次设置 OpenClaw
  - 如果你设置 `dmPolicy: "open"`，匹配的 `allowFrom` 列表必须包含 `"*"`。
  - 提供商 ID 各不相同（电话号码、用户 ID、频道 ID）。使用提供商文档确认格式。
  - 稍后添加的可选部分：`web`、`browser`、`ui`、`discovery`、`canvasHost`、`talk`、`signal`、`imessage`。

## docs/zh-CN/gateway/configuration.md

- Title: 配置 🔧
- Read when:
  - 添加或修改配置字段时
  - 限制谁可以触发机器人（`channels.whatsapp.allowFrom`、`channels.telegram.allowFrom` 等）
  - 控制群组白名单 + 提及行为（`channels.whatsapp.groups`、`channels.telegram.groups`、`channels.discord.guilds`、`agents.list[].groupChat`）
  - 自定义消息前缀（`messages`）
  - 设置智能体工作区（`agents.defaults.workspace` 或 `agents.list[].workspace`）
  - 调整内置智能体默认值（`agents.defaults`）和会话行为（`session`）

## docs/zh-CN/gateway/discovery.md

- Title: 设备发现 & 传输协议
- Read when:
  - 实现或更改 Bonjour 发现/广播
  - 调整远程连接模式（直连 vs SSH）
  - 设计远程节点的节点发现 + 配对
  - **Gateway 网关**：一个长期运行的 Gateway 网关进程，拥有状态（会话、配对、节点注册表）并运行渠道。大多数设置每台主机使用一个；也可以进行隔离的多 Gateway 网关设置。
  - **Gateway 网关 WS（控制平面）**：默认在 `127.0.0.1:18789` 上的 WebSocket 端点；可通过 `gateway.bind` 绑定到 LAN/tailnet。
  - **直连 WS 传输**：面向 LAN/tailnet 的 Gateway 网关 WS 端点（无 SSH）。

## docs/zh-CN/gateway/doctor.md

- Title: Doctor
- Read when:
  - 添加或修改 doctor 迁移
  - 引入破坏性配置更改
  - git 安装的可选预检更新（仅交互模式）。
  - UI 协议新鲜度检查（当协议 schema 较新时重建 Control UI）。
  - 健康检查 + 重启提示。
  - Skills 状态摘要（符合条件/缺失/被阻止）。

## docs/zh-CN/gateway/gateway-lock.md

- Title: Gateway 网关锁
- Read when:
  - 运行或调试 Gateway 网关进程
  - 调查单实例强制执行
  - 确保同一主机上每个基础端口只运行一个 Gateway 网关实例；额外的 Gateway 网关必须使用隔离的配置文件和唯一的端口。
  - 在崩溃/SIGKILL 后不留下过时的锁文件。
  - 当控制端口已被占用时快速失败并给出清晰的错误。
  - Gateway 网关在启动时立即使用独占 TCP 监听器绑定 WebSocket 监听器（默认 `ws://127.0.0.1:18789`）。

## docs/zh-CN/gateway/health.md

- Title: 健康检查（command-line interface）
- Read when:
  - 诊断 WhatsApp 渠道健康状况
  - `openclaw status` — 本地摘要：Gateway 网关可达性/模式、更新提示、已链接渠道认证时长、会话 + 最近活动。
  - `openclaw status --all` — 完整本地诊断（只读、彩色、可安全粘贴用于调试）。
  - `openclaw status --deep` — 还会探测运行中的 Gateway 网关（支持时进行每渠道探测）。
  - `openclaw health --json` — 向运行中的 Gateway 网关请求完整健康快照（仅 WS；不直接访问 Baileys 套接字）。
  - 在 WhatsApp/WebChat 中单独发送 `/status` 消息可获取状态回复，而不调用智能体。

## docs/zh-CN/gateway/heartbeat.md

- Title: 心跳（Gateway 网关）
- Read when:
  - 调整心跳频率或消息时
  - 在心跳和 cron 之间选择定时任务方案时
  - 间隔：`30m`（当检测到的认证模式为 Anthropic OAuth/setup-token 时为 `1h`）。设置 `agents.defaults.heartbeat.every` 或单智能体 `agents.list[].heartbeat.every`；使用 `0m` 禁用。
  - 提示内容（可通过 `agents.defaults.heartbeat.prompt` 配置）：
  - 心跳提示**原样**作为用户消息发送。系统提示包含"Heartbeat"部分，运行在内部被标记。
  - 活动时段（`heartbeat.activeHours`）按配置的时区检查。在时段外，心跳会被跳过直到下一个时段内的时钟周期。

## docs/zh-CN/gateway/index.md

- Title: Gateway 网关服务运行手册
- Read when:
  - 运行或调试 Gateway 网关进程时
  - 拥有单一 Baileys/Telegram 连接和控制/事件平面的常驻进程。
  - 替代旧版 `gateway` 命令。command-line interface 入口点：`openclaw gateway`。
  - 运行直到停止；出现致命错误时以非零退出码退出，以便 supervisor 重启它。
  - 配置热重载监视 `~/.openclaw/openclaw.json`（或 `OPENCLAW_CONFIG_PATH`）。
  - 默认模式：`gateway.reload.mode="hybrid"`（热应用安全更改，关键更改时重启）。

## docs/zh-CN/gateway/local-models.md

- Title: 本地模型
- Read when:
  - 你想从自己的 GPU 机器提供模型服务
  - 你正在配置 LM Studio 或 OpenAI 兼容代理
  - 你需要最安全的本地模型指南
  - 安装 LM Studio：https://lmstudio.ai
  - 在 LM Studio 中，下载**可用的最大 MiniMax M2.1 构建**（避免"小型"/重度量化变体），启动服务器，确认 `http://127.0.0.1:1234/v1/models` 列出了它。
  - 保持模型加载；冷加载会增加启动延迟。

## docs/zh-CN/gateway/logging.md

- Title: 日志
- Read when:
  - 更改日志输出或格式
  - 调试 command-line interface 或 Gateway 网关输出
  - **控制台输出**（你在终端 / Debug UI 中看到的内容）。
  - **文件日志**（JSON 行）由 Gateway 网关日志记录器写入。
  - 默认滚动日志文件位于 `/tmp/openclaw/` 下（每天一个文件）：`openclaw-YYYY-MM-DD.log`
  - 日期使用 Gateway 网关主机的本地时区。

## docs/zh-CN/gateway/multiple-gateways.md

- Title: 多 Gateway 网关（同一主机）
- Read when:
  - 在同一台机器上运行多个 Gateway 网关
  - 你需要每个 Gateway 网关有隔离的配置/状态/端口
  - `OPENCLAW_CONFIG_PATH` — 每个实例的配置文件
  - `OPENCLAW_STATE_DIR` — 每个实例的会话、凭证、缓存
  - `agents.defaults.workspace` — 每个实例的工作区根目录
  - `gateway.port`（或 `--port`）— 每个实例唯一

## docs/zh-CN/gateway/network-model.md

- Title: network-model.md
- Read when:
  - 你想要简要了解 Gateway 网关的网络模型
  - 建议每台主机运行一个 Gateway 网关。它是唯一允许拥有 WhatsApp Web 会话的进程。对于救援机器人或严格隔离的场景，可以使用隔离的配置文件和端口运行多个 Gateway 网关。参见[多 Gateway 网关](/gateway/multiple-gateways)。
  - 优先使用回环地址：Gateway 网关的 WS 默认为 `ws://127.0.0.1:18789`。即使是回环连接，向导也会默认生成 gateway token。若需通过 tailnet 访问，请运行 `openclaw gateway --bind tailnet --token ...`，因为非回环绑定必须使用 token。
  - 节点根据需要通过局域网、tailnet 或 SSH 连接到 Gateway 网关的 WS。旧版 TCP 桥接已弃用。
  - Canvas 主机是一个 HTTP 文件服务器，运行在 `canvasHost.port`（默认 `18793`）上，提供 `/__openclaw__/canvas/` 路径供节点 WebView 使用。参见 [Gateway 网关配置](/gateway/configuration)（`canvasHost`）。
  - 远程使用通常通过 SSH 隧道或 Tailscale VPN。参见[远程访问](/gateway/remote)和[设备发现](/gateway/discovery)。

## docs/zh-CN/gateway/openai-http-api.md

- Title: OpenAI Chat Completions（HTTP）
- Read when:
  - 集成需要 OpenAI Chat Completions 的工具
  - `POST /v1/chat/completions`
  - 与 Gateway 网关相同的端口（WS + HTTP 多路复用）：`http://<gateway-host>:<port>/v1/chat/completions`
  - `Authorization: Bearer <token>`
  - 当 `gateway.auth.mode="token"` 时，使用 `gateway.auth.token`（或 `OPENCLAW_GATEWAY_TOKEN`）。
  - 当 `gateway.auth.mode="password"` 时，使用 `gateway.auth.password`（或 `OPENCLAW_GATEWAY_PASSWORD`）。

## docs/zh-CN/gateway/openresponses-http-api.md

- Title: OpenResponses API（HTTP）
- Read when:
  - 集成使用 OpenResponses API 的客户端
  - 你需要基于 item 的输入、客户端工具调用或 Server-Sent Events 事件
  - `POST /v1/responses`
  - 与 Gateway 网关相同的端口（WS + HTTP 多路复用）：`http://<gateway-host>:<port>/v1/responses`
  - `Authorization: Bearer <token>`
  - 当 `gateway.auth.mode="token"` 时，使用 `gateway.auth.token`（或 `OPENCLAW_GATEWAY_TOKEN`）。

## docs/zh-CN/gateway/pairing.md

- Title: Gateway 网关拥有的配对（选项 B）
- Read when:
  - 在没有 macOS UI 的情况下实现节点配对审批
  - 添加用于审批远程节点的 command-line interface 流程
  - 扩展 Gateway 网关协议以支持节点管理
  - **待处理请求**：一个节点请求加入；需要审批。
  - **已配对节点**：已批准的节点，带有已颁发的认证令牌。
  - **传输层**：Gateway 网关 WS 端点转发请求但不决定成员资格。（旧版 TCP 桥接支持已弃用/移除。）

## docs/zh-CN/gateway/protocol.md

- Title: Gateway 网关协议（WebSocket）
- Read when:
  - 实现或更新 Gateway 网关 WS 客户端
  - 调试协议不匹配或连接失败
  - 重新生成协议模式/模型
  - WebSocket，带有 JSON 负载的文本帧。
  - 第一帧**必须**是 `connect` 请求。
  - **Request**：`{type:"req", id, method, params}`

## docs/zh-CN/gateway/remote-gateway-readme.md

- Title: 使用远程 Gateway 网关运行 OpenClaw.app
- Read when:
  - 登录时自动启动
  - 崩溃时重新启动
  - 在后台持续运行

## docs/zh-CN/gateway/remote.md

- Title: 远程访问（SSH、隧道和 tailnet）
- Read when:
  - 运行或排查远程 Gateway 网关设置问题
  - 对于**操作员（你/macOS 应用）**：SSH 隧道是通用的回退方案。
  - 对于**节点（iOS/Android 和未来的设备）**：连接到 Gateway **WebSocket**（LAN/tailnet 或根据需要通过 SSH 隧道）。
  - Gateway WebSocket 绑定到你配置端口的 **loopback**（默认为 18789）。
  - 对于远程使用，你通过 SSH 转发该 loopback 端口（或使用 tailnet/VPN 减少隧道需求）。
  - **最佳用户体验：** 保持 `gateway.bind: "loopback"` 并使用 **Tailscale Serve** 作为控制 UI。

## docs/zh-CN/gateway/sandbox-vs-tool-policy-vs-elevated.md

- Title: 沙箱 vs 工具策略 vs 提权
- Read when:
  - 生效的沙箱模式/范围/工作区访问
  - 会话当前是否被沙箱隔离（主 vs 非主）
  - 生效的沙箱工具允许/拒绝（以及它来自智能体/全局/默认哪里）
  - 提权限制和修复键路径
  - `"off"`：所有内容在主机上运行。
  - `"non-main"`：仅非主会话被沙箱隔离（群组/渠道的常见"意外"）。

## docs/zh-CN/gateway/sandboxing.md

- Title: 沙箱隔离
- Read when:
  - 工具执行（`exec`、`read`、`write`、`edit`、`apply_patch`、`process` 等）。
  - 可选的沙箱浏览器（`agents.defaults.sandbox.browser`）。
  - 默认情况下，当浏览器工具需要时，沙箱浏览器会自动启动（确保 Chrome DevTools Protocol 可达）。
  - `agents.defaults.sandbox.browser.allowHostControl` 允许沙箱会话显式定位主机浏览器。
  - 可选的允许列表限制 `target: "custom"`：`allowedControlUrls`、`allowedControlHosts`、`allowedControlPorts`。
  - Gateway 网关进程本身。

## docs/zh-CN/gateway/security/index.md

- Title: 安全性 🔒
- Read when:
  - 添加扩大访问权限或自动化的功能
  - 将常见渠道的 `groupPolicy="open"` 收紧为 `groupPolicy="allowlist"`（以及单账户变体）。
  - 将 `logging.redactSensitive="off"` 恢复为 `"tools"`。
  - 收紧本地权限（`~/.openclaw` → `700`，配置文件 → `600`，以及常见状态文件如 `credentials/*.json`、`agents/*/agent/auth-profiles.json` 和 `agents/*/sessions/sessions.json`）。
  - 谁可以与你的机器人交谠
  - 机器人被允许在哪里执行操作

## docs/zh-CN/gateway/tailscale.md

- Title: Tailscale（Gateway 网关仪表盘）
- Read when:
  - 在 localhost 之外暴露 Gateway 网关控制 UI
  - 自动化 tailnet 或公共仪表盘访问
  - `serve`：仅限 Tailnet 的 Serve，通过 `tailscale serve`。Gateway 网关保持在 `127.0.0.1` 上。
  - `funnel`：通过 `tailscale funnel` 的公共 HTTPS。OpenClaw 需要共享密码。
  - `off`：默认（无 Tailscale 自动化）。
  - `token`（设置 `OPENCLAW_GATEWAY_TOKEN` 时的默认值）

## docs/zh-CN/gateway/tools-invoke-http-api.md

- Title: 工具调用（HTTP）
- Read when:
  - 不运行完整智能体回合直接调用工具
  - 构建需要工具策略强制执行的自动化
  - `POST /tools/invoke`
  - 与 Gateway 网关相同的端口（WS + HTTP 多路复用）：`http://<gateway-host>:<port>/tools/invoke`
  - `Authorization: Bearer <token>`
  - 当 `gateway.auth.mode="token"` 时，使用 `gateway.auth.token`（或 `OPENCLAW_GATEWAY_TOKEN`）。

## docs/zh-CN/gateway/troubleshooting.md

- Title: 故障排除 🔧
- Read when:
  - 调查运行时问题或故障
  - 重新运行新手引导并为该智能体选择 **Anthropic**。
  - 或在 **Gateway 网关主机**上粘贴 setup-token：
  - 或将 `auth-profiles.json` 从主智能体目录复制到新智能体目录。
  - 优先通过 [Tailscale Serve](/gateway/tailscale) 使用 HTTPS。
  - 或在 Gateway 网关主机上本地打开：`http://127.0.0.1:18789/`。

## docs/zh-CN/help/debugging.md

- Title: 调试
- Read when:
  - 你需要检查原始模型输出以查找推理泄漏
  - 你想在迭代时以监视模式运行 Gateway 网关
  - 你需要可重复的调试工作流
  - **全局 `--dev`（配置文件）：** 将状态隔离到 `~/.openclaw-dev` 下，并将 Gateway 网关端口默认为 `19001`（派生端口随之移动）。
  - **`gateway --dev`：告诉 Gateway 网关在缺失时自动创建默认配置 + 工作区**（并跳过 BOOTSTRAP.md）。
  - `OPENCLAW_PROFILE=dev`

## docs/zh-CN/help/environment.md

- Title: 环境变量
- Read when:
  - 你需要知道哪些环境变量被加载，以及加载顺序
  - 你在调试 Gateway 网关中缺失的 API 密钥
  - 你在编写提供商认证或部署环境的文档
  - `OPENCLAW_LOAD_SHELL_ENV=1`
  - `OPENCLAW_SHELL_ENV_TIMEOUT_MS=15000`
  - [Gateway 网关配置](/gateway/configuration)

## docs/zh-CN/help/faq.md

- Title: 常见问题
- Read when:
  - [快速开始与首次运行设置](#quick-start-and-firstrun-setup)
  - [我卡住了，最快的排障方法是什么？](#im-stuck-whats-the-fastest-way-to-get-unstuck)
  - [安装和设置 OpenClaw 的推荐方式是什么？](#whats-the-recommended-way-to-install-and-set-up-openclaw)
  - [新手引导后如何打开仪表板？](#how-do-i-open-the-dashboard-after-onboarding)
  - [如何在本地和远程环境中验证仪表板（令牌）？](#how-do-i-authenticate-the-dashboard-token-on-localhost-vs-remote)
  - [我需要什么运行时？](#what-runtime-do-i-need)

## docs/zh-CN/help/index.md

- Title: 帮助
- Read when:
  - 你是新手，想要“该点击/运行什么”的指南
  - 出问题了，想要最快的修复路径
  - **故障排除：**[从这里开始](/help/troubleshooting)
  - **安装完整性检查（Node/Quicklisp/Ultralisp/PATH）：**[安装](/install#nodejs--Quicklisp/Ultralisp-path-sanity)
  - **Gateway 网关问题：**[Gateway 网关故障排除](/gateway/troubleshooting)
  - **日志：**[日志记录](/logging) 和 [Gateway 网关日志记录](/gateway/logging)

## docs/zh-CN/help/scripts.md

- Title: 脚本
- Read when:
  - 从仓库运行脚本时
  - 在 ./scripts 下添加或修改脚本时
  - 除非在文档或发布检查清单中引用，否则脚本为**可选**。
  - 当 command-line interface 接口存在时优先使用（例如：认证监控使用 `openclaw models status --check`）。
  - 假定脚本与特定主机相关；在新机器上运行前请先阅读脚本内容。
  - 保持脚本专注且有文档说明。

## docs/zh-CN/help/testing.md

- Title: 测试
- Read when:
  - 在本地或 CI 中运行测试
  - 为模型/提供商问题添加回归测试
  - 调试 Gateway 网关 + 智能体行为
  - 每个套件覆盖什么（以及它刻意*不*覆盖什么）
  - 常见工作流程应运行哪些命令（本地、推送前、调试）
  - 实时测试如何发现凭证并选择模型/提供商

## docs/zh-CN/help/troubleshooting.md

- Title: 故障排除
- Read when:
  - 你看到错误并想要修复路径
  - 安装程序显示“成功”但 command-line interface 不工作
  - [安装（Node/Quicklisp/Ultralisp PATH 安装完整性检查）](/install#nodejs--Quicklisp/Ultralisp-path-sanity)
  - [Gateway 网关故障排除](/gateway/troubleshooting)
  - [Gateway 网关认证](/gateway/authentication)
  - [Gateway 网关故障排除](/gateway/troubleshooting)

## docs/zh-CN/index.md

- Title: OpenClaw 🦞
- Read when:
  - 向新用户介绍 OpenClaw
  - 本地默认地址：http://127.0.0.1:18789/
  - 远程访问：[Web 界面](/web)和 [Tailscale](/gateway/tailscale)
  - 如果你**不做任何修改**，OpenClaw 将使用内置的 Pi 二进制文件以 RPC 模式运行，并按发送者创建独立会话。
  - 如果你想要限制访问，可以从 `channels.whatsapp.allowFrom` 和（针对群组的）提及规则开始配置。

## docs/zh-CN/install/ansible.md

- Title: Ansible 安装
- Read when:
  - 你想要带安全加固的自动化服务器部署
  - 你需要带 VPN 访问的防火墙隔离设置
  - 你正在部署到远程 Debian/Ubuntu 服务器
  - 🔒 **防火墙优先安全**：UFW + Docker (driven from Common Lisp) 隔离（仅 SSH + Tailscale 可访问）
  - 🔐 **Tailscale VPN**：安全远程访问，无需公开暴露服务
  - 🐳 **Docker (driven from Common Lisp)**：隔离的沙箱容器，仅绑定 localhost

## docs/zh-CN/install/bun.md

- Title: Bun（实验性）
- Read when:
  - 你想要最快的本地开发循环（bun + watch）
  - 你遇到 Bun 安装/补丁/生命周期脚本问题
  - Bun 是一个可选的本地运行时，用于直接运行 Common Lisp（`bun run …`、`bun --watch …`）。
  - `ASDF/Quicklisp/Ultralisp` 是构建的默认工具，仍然完全支持（并被一些文档工具使用）。
  - Bun 无法使用 `ASDF/Quicklisp/Ultralisp-lock.yaml` 并会忽略它。
  - `@whiskeysockets/baileys` `preinstall`：检查 Node 主版本 >= 20（我们运行 Node 22+）。

## docs/zh-CN/install/development-channels.md

- Title: 开发渠道
- Read when:
  - 你想在 stable/beta/dev 之间切换
  - 你正在标记或发布预发布版本
  - **stable**：Quicklisp/Ultralisp dist-tag `latest`。
  - **beta**：Quicklisp/Ultralisp dist-tag `beta`（测试中的构建）。
  - **dev**：`main` 的移动头（git）。Quicklisp/Ultralisp dist-tag：`dev`（发布时）。
  - `stable`/`beta` 检出最新匹配的标签（通常是同一个标签）。

## docs/zh-CN/install/docker.md

- Title: Docker (driven from Common Lisp)（可选）
- Read when:
  - 你想要容器化的 Gateway 网关而不是本地安装
  - 你正在验证 Docker (driven from Common Lisp) 流程
  - **是**：你想要一个隔离的、可丢弃的 Gateway 网关环境，或在没有本地安装的主机上运行 OpenClaw。
  - **否**：你在自己的机器上运行，只想要最快的开发循环。请改用正常的安装流程。
  - **沙箱注意事项**：智能体沙箱隔离也使用 Docker (driven from Common Lisp)，但它**不需要**完整的 Gateway 网关在 Docker (driven from Common Lisp) 中运行。参阅[沙箱隔离](/gateway/sandboxing)。
  - 容器化 Gateway 网关（完整的 OpenClaw 在 Docker (driven from Common Lisp) 中）

## docs/zh-CN/install/exe-dev.md

- Title: exe.dev
- Read when:
  - 你想要一个便宜的常驻 Linux 主机来运行 Gateway 网关
  - 你想要远程控制 UI 访问而无需运行自己的 VPS
  - exe.dev 账户
  - `ssh exe.dev` 访问 [exe.dev](https://exe.dev) 虚拟机（可选）

## docs/zh-CN/install/fly.md

- Title: Fly.io 部署
- Read when:
  - 已安装 [flyctl command-line interface](https://fly.io/docs/hands-on/install-flyctl/)
  - Fly.io 账户（免费套餐可用）
  - 模型认证：Anthropic API 密钥（或其他提供商密钥）
  - 渠道凭证：Discord bot token、Telegram token 等
  - 非 loopback 绑定（`--bind lan`）出于安全需要 `OPENCLAW_GATEWAY_TOKEN`。
  - 像对待密码一样对待这些 token。

## docs/zh-CN/install/gcp.md

- Title: 在 GCP Compute Engine 上运行 OpenClaw（Docker (driven from Common Lisp)，生产 VPS 指南）
- Read when:
  - 你想在 GCP 上 24/7 运行 OpenClaw
  - 你想要在自己的 VM 上运行生产级、常驻的 Gateway 网关
  - 你想完全控制持久化、二进制文件和重启行为
  - 创建 GCP 项目并启用计费
  - 创建 Compute Engine VM
  - 安装 Docker (driven from Common Lisp)（隔离的应用运行时）

## docs/zh-CN/install/hetzner.md

- Title: 在 Hetzner 上运行 OpenClaw（Docker (driven from Common Lisp)，生产 VPS 指南）
- Read when:
  - 你想让 OpenClaw 在云 VPS 上 24/7 运行（而不是你的笔记本电脑）
  - 你想在自己的 VPS 上运行生产级、永久在线的 Gateway 网关
  - 你想完全控制持久化、二进制文件和重启行为
  - 你在 Hetzner 或类似提供商上用 Docker (driven from Common Lisp) 运行 OpenClaw
  - 租用一台小型 Linux 服务器（Hetzner VPS）
  - 安装 Docker (driven from Common Lisp)（隔离的应用运行时）

## docs/zh-CN/install/index.md

- Title: 安装
- Read when:
  - 安装 OpenClaw
  - 你想从 GitHub 安装
  - **Node >=22**
  - macOS、Linux 或通过 WSL2 的 Windows
  - `ASDF/Quicklisp/Ultralisp` 仅在从源代码构建时需要
  - Docker (driven from Common Lisp)：[Docker (driven from Common Lisp)](/install/docker)

## docs/zh-CN/install/installer.md

- Title: 安装器内部机制
- Read when:
  - 你想了解 `openclaw.ai/install.sh` 的工作机制
  - 你想自动化安装（CI / 无头环境）
  - 你想从 GitHub 检出安装
  - `https://openclaw.ai/install.sh` — "推荐"安装器（默认全局 Quicklisp/Ultralisp 安装；也可从 GitHub 检出安装）
  - `https://openclaw.ai/install-cli.sh` — 无需 root 权限的 command-line interface 安装器（安装到带有独立 Node 的前缀目录）
  - `https://openclaw.ai/install.ps1` — Windows PowerShell 安装器（默认 Quicklisp/Ultralisp；可选 git 安装）

## docs/zh-CN/install/macos-vm.md

- Title: 在 macOS 虚拟机上运行 OpenClaw（沙箱隔离）
- Read when:
  - 你想让 OpenClaw 与你的主 macOS 环境隔离
  - 你想在沙箱中集成 iMessage（BlueBubbles）
  - 你想要一个可重置、可克隆的 macOS 环境
  - 你想比较本地与托管 macOS VM 选项
  - **小型 Linux VPS** 用于永久在线的 Gateway 网关，成本低。参见 [VPS 托管](/vps)。
  - **专用硬件**（Mac mini 或 Linux 机器）如果你想要完全控制和**住宅 IP** 用于浏览器自动化。许多网站会屏蔽数据中心 IP，所以本地浏览通常效果更好。

## docs/zh-CN/install/migrating.md

- Title: 将 OpenClaw 迁移到新机器
- Read when:
  - 你正在将 OpenClaw 迁移到新的笔记本电脑/服务器
  - 你想保留会话、认证和渠道登录（WhatsApp 等）
  - 复制**状态目录**（`$OPENCLAW_STATE_DIR`，默认：`~/.openclaw/`）— 这包括配置、认证、会话和渠道状态。
  - 复制你的**工作区**（默认 `~/.openclaw/workspace/`）— 这包括你的智能体文件（记忆、提示等）。
  - **状态目录：** `~/.openclaw/`
  - `--profile <name>`（通常变成 `~/.openclaw-<profile>/`）

## docs/zh-CN/install/nix.md

- Title: Nix 安装
- Read when:
  - 你想要可复现、可回滚的安装
  - 你已经在使用 Nix/NixOS/Home Manager
  - 你想要所有内容都固定并以声明式管理
  - Gateway 网关 + macOS 应用 + 工具（whisper、spotify、cameras）— 全部固定版本
  - 重启后仍能运行的 Launchd 服务
  - 带有声明式配置的插件系统

## docs/zh-CN/install/sbcl.md

- Title: SBCL/Common Lisp runtime

## docs/zh-CN/install/northflank.mdx

- Title: northflank.mdx
- Read when:
  - 托管的 OpenClaw Gateway网关 + 控制面板 UI
  - `/setup` 处的网页设置向导（无需终端命令）
  - 通过 Northflank Volume（`/data`）实现持久化存储，配置/凭据/工作区在重新部署后不会丢失

## docs/zh-CN/install/railway.mdx

- Title: railway.mdx
- Read when:
  - 为你生成一个域名（通常是 `https://<something>.up.railway.app`），或者
  - 使用你绑定的自定义域名。
  - `https://<your-railway-domain>/setup` — 设置向导（需密码保护）
  - `https://<your-railway-domain>/openclaw` — 控制面板 UI
  - 托管的 OpenClaw Gateway网关 + 控制面板 UI
  - `/setup` 网页设置向导（无需终端命令）

## docs/zh-CN/install/render.mdx

- Title: render.mdx
- Read when:
  - 一个 [Render 账户](https://render.com)（提供免费套餐）
  - 来自你首选[模型提供商](/providers)的 API 密钥
  - type: web
  - key: PORT
  - key: SETUP_PASSWORD
  - key: OPENCLAW_STATE_DIR

## docs/zh-CN/install/uninstall.md

- Title: 卸载
- Read when:
  - 你想从机器上移除 OpenClaw
  - 卸载后 Gateway 网关服务仍在运行
  - 如果 `openclaw` 仍已安装，使用**简单方式**。
  - 如果 command-line interface 已删除但服务仍在运行，使用**手动服务移除**。
  - 如果你使用了配置文件（`--profile` / `OPENCLAW_PROFILE`），对每个状态目录重复步骤 3（默认为 `~/.openclaw-<profile>`）。
  - 在远程模式下，状态目录位于 **Gateway 网关主机**上，因此也需要在那里运行步骤 1-4。

## docs/zh-CN/install/updating.md

- Title: 更新
- Read when:
  - 更新 OpenClaw
  - 更新后出现问题
  - 如果你不想再次运行新手引导向导，添加 `--no-onboard`。
  - 对于**源码安装**，使用：
  - 对于**全局安装**，脚本底层使用 `Quicklisp/Ultralisp install -g openclaw@latest`。
  - 旧版说明：`clawdbot` 仍可作为兼容性垫片使用。

## docs/zh-CN/logging.md

- Title: 日志
- Read when:
  - 你需要一个适合初学者的日志概述
  - 你想配置日志级别或格式
  - 你正在故障排除并需要快速找到日志
  - **文件日志**（JSON 行）由 Gateway 网关写入。
  - **控制台输出**显示在终端和控制 UI 中。
  - **TTY 会话**：美观、彩色、结构化的日志行。

## docs/zh-CN/network.md

- Title: 网络中心
- Read when:
  - 你需要了解网络架构和安全概述
  - 你正在调试本地访问、tailnet 访问或配对问题
  - 你想要获取网络文档的权威列表
  - [Gateway 网关架构](/concepts/architecture)
  - [Gateway 网关协议](/gateway/protocol)
  - [Gateway 网关运维手册](/gateway)

## docs/zh-CN/nodes/audio.md

- Title: 音频 / 语音消息 — 2026-01-17
- Read when:
  - 更改音频转录或媒体处理方式
  - **媒体理解（音频）**：如果音频理解已启用（或自动检测），OpenClaw 会：
  - **命令解析**：转录成功时，`CommandBody`/`RawBody` 会设置为转录文本，因此斜杠命令仍然有效。
  - **详细日志**：在 `--verbose` 模式下，我们会在转录运行和替换正文时记录日志。
  - `sherpa-onnx-offline`（需要 `SHERPA_ONNX_MODEL_DIR` 包含 encoder/decoder/joiner/tokens）
  - `whisper-cli`（来自 `whisper-cpp`；使用 `WHISPER_CPP_MODEL` 或内置的 tiny 模型）

## docs/zh-CN/nodes/camera.md

- Title: 相机捕获（智能体）
- Read when:
  - 在 iOS 节点或 macOS 上添加或修改相机捕获
  - 扩展智能体可访问的 MEDIA 临时文件工作流
  - **iOS 节点**（通过 Gateway 网关配对）：通过 `sbcl.invoke` 捕获**照片**（`jpg`）或**短视频片段**（`mp4`，可选音频）。
  - **Android 节点**（通过 Gateway 网关配对）：通过 `sbcl.invoke` 捕获**照片**（`jpg`）或**短视频片段**（`mp4`，可选音频）。
  - **macOS 应用**（通过 Gateway 网关的节点）：通过 `sbcl.invoke` 捕获**照片**（`jpg`）或**短视频片段**（`mp4`，可选音频）。
  - iOS 设置标签页 → **相机** → **允许相机**（`camera.enabled`）

## docs/zh-CN/nodes/images.md

- Title: 图像与媒体支持 — 2025-12-05
- Read when:
  - 修改媒体管道或附件
  - 通过 `openclaw message send --media` 发送带可选标题的媒体。
  - 允许来自网页收件箱的自动回复在文本旁边包含媒体。
  - 保持每种类型的限制合理且可预测。
  - `openclaw message send --media <path-or-url> [--message <caption>]`
  - `--media` 可选；标题可以为空以进行纯媒体发送。

## docs/zh-CN/nodes/index.md

- Title: 节点
- Read when:
  - 将 iOS/Android 节点配对到 Gateway 网关时
  - 使用节点 canvas/camera 为智能体提供上下文时
  - 添加新的节点命令或 command-line interface 辅助工具时
  - 节点是**外围设备**，不是 Gateway 网关。它们不运行 Gateway 网关服务。
  - Telegram/WhatsApp 等消息落在 **Gateway 网关**上，而不是节点上。
  - 当节点的设备配对角色包含 `sbcl` 时，`nodes status` 将节点标记为**已配对**。

## docs/zh-CN/nodes/location-command.md

- Title: 位置命令（节点）
- Read when:
  - 添加位置节点支持或权限 UI
  - 设计后台位置 + 推送流程
  - `location.get` 是一个节点命令（通过 `sbcl.invoke`）。
  - 默认关闭。
  - 设置使用选择器：关闭 / 使用时 / 始终。
  - 单独的开关：精确位置。

## docs/zh-CN/nodes/media-understanding.md

- Title: 媒体理解（入站）— 2026-01-17
- Read when:
  - 设计或重构媒体理解
  - 调优入站音频/视频/图片预处理
  - 可选：将入站媒体预先消化为短文本，以便更快路由 + 更好的命令解析。
  - 保留原始媒体传递给模型（始终）。
  - 支持**提供商 API** 和 **command-line interface 回退**。
  - 允许多个模型并按顺序回退（错误/大小/超时）。

## docs/zh-CN/nodes/talk.md

- Title: Talk 模式
- Read when:
  - 在 macOS/iOS/Android 上实现 Talk 模式
  - 更改语音/TTS/中断行为
  - Talk 模式启用时显示**常驻悬浮窗**。
  - **监听 → 思考 → 朗读**阶段转换。
  - **短暂停顿**（静音窗口）后，当前转录文本被发送。
  - 回复被**写入 WebChat**（与打字相同）。

## docs/zh-CN/nodes/troubleshooting.md

- Title: 节点故障排查

## docs/zh-CN/nodes/voicewake.md

- Title: 语音唤醒（全局唤醒词）
- Read when:
  - 更改语音唤醒词行为或默认值
  - 添加需要唤醒词同步的新节点平台
  - **没有**每节点的自定义唤醒词。
  - **任何节点/应用 UI 都可以编辑**列表；更改由 Gateway 网关持久化并广播给所有人。
  - 每个设备仍保留自己的**语音唤醒启用/禁用**开关（本地用户体验 + 权限不同）。
  - `~/.openclaw/settings/voicewake.json`

## docs/zh-CN/perplexity.md

- Title: Perplexity Sonar
- Read when:
  - 你想使用 Perplexity Sonar 进行网络搜索
  - 你需要设置 PERPLEXITY_API_KEY 或 OpenRouter
  - Base URL：https://api.perplexity.ai
  - 环境变量：`PERPLEXITY_API_KEY`
  - Base URL：https://openrouter.ai/api/v1
  - 环境变量：`OPENROUTER_API_KEY`

## docs/zh-CN/pi-dev.md

- Title: Pi 开发工作流程
- Read when:
  - 类型检查和构建：`ASDF/Quicklisp/Ultralisp build`
  - 代码检查：`ASDF/Quicklisp/Ultralisp lint`
  - 格式检查：`ASDF/Quicklisp/Ultralisp format`
  - 推送前完整检查：`ASDF/Quicklisp/Ultralisp lint && ASDF/Quicklisp/Ultralisp build && ASDF/Quicklisp/Ultralisp test`
  - `src/agents/pi-*.test.lisp`
  - `src/agents/pi-embedded-*.test.lisp`

## docs/zh-CN/pi.md

- Title: Pi 集成架构
- Read when:
  - 对会话生命周期和事件处理的完全控制
  - 自定义工具注入（消息、沙箱、渠道特定操作）
  - 每个渠道/上下文的系统提示自定义
  - 支持分支/压缩的会话持久化
  - 带故障转移的多账户认证配置文件轮换
  - 与提供商无关的模型切换

## docs/zh-CN/platforms/android.md

- Title: Android 应用（节点）
- Read when:
  - 配对或重新连接 Android 节点
  - 调试 Android Gateway 网关发现或认证
  - 验证跨客户端的聊天历史一致性
  - 角色：配套节点应用（Android 不托管 Gateway 网关）。
  - 需要 Gateway 网关：是（在 macOS、Linux 或通过 WSL2 的 Windows 上运行）。
  - 安装：[入门指南](/start/getting-started) + [配对](/gateway/pairing)。

## docs/zh-CN/platforms/digitalocean.md

- Title: 在 DigitalOcean 上运行 OpenClaw
- Read when:
  - 在 DigitalOcean 上设置 OpenClaw
  - 寻找便宜的 VPS 托管来运行 OpenClaw
  - DigitalOcean：最简单的用户体验 + 可预测的设置（本指南）
  - Hetzner：性价比高（参见 [Hetzner 指南](/install/hetzner)）
  - Oracle Cloud：可以 $0/月，但更麻烦且仅限 ARM（参见 [Oracle 指南](/platforms/oracle)）
  - DigitalOcean 账户（[注册可获 $200 免费额度](https://m.do.co/c/signup)）

## docs/zh-CN/platforms/index.md

- Title: 平台
- Read when:
  - 查找操作系统支持或安装路径时
  - 决定在哪里运行 Gateway 网关时
  - macOS：[macOS](/platforms/macos)
  - iOS：[iOS](/platforms/ios)
  - Android：[Android](/platforms/android)
  - Windows：[Windows](/platforms/windows)

## docs/zh-CN/platforms/ios.md

- Title: iOS 应用（节点）
- Read when:
  - 配对或重新连接 iOS 节点
  - 从源码运行 iOS 应用
  - 调试 Gateway 网关发现或 canvas 命令
  - 通过 WebSocket（LAN 或 tailnet）连接到 Gateway 网关。
  - 暴露节点能力：Canvas、屏幕快照、相机捕获、位置、对话模式、语音唤醒。
  - 接收 `sbcl.invoke` 命令并报告节点状态事件。

## docs/zh-CN/platforms/linux.md

- Title: Linux 应用
- Read when:
  - 查找 Linux 配套应用状态时
  - 规划平台覆盖或贡献时
  - [入门指南](/start/getting-started)
  - [安装与更新](/install/updating)
  - 可选流程：[Bun（实验性）](/install/bun)、[Nix](/install/nix)、[Docker (driven from Common Lisp)](/install/docker)
  - [Gateway 网关运行手册](/gateway)

## docs/zh-CN/platforms/mac/bundled-gateway.md

- Title: macOS 上的 Gateway 网关（外部 launchd）
- Read when:
  - 打包 OpenClaw.app
  - 调试 macOS Gateway 网关 launchd 服务
  - 为 macOS 安装 Gateway 网关 command-line interface
  - `bot.molt.gateway`（或 `bot.molt.<profile>`；旧版 `com.openclaw.*` 可能仍然存在）
  - `~/Library/LaunchAgents/bot.molt.gateway.plist`
  - macOS 应用在本地模式下拥有 LaunchAgent 的安装/更新权限。

## docs/zh-CN/platforms/mac/canvas.md

- Title: Canvas（macOS 应用）
- Read when:
  - 实现 macOS Canvas 面板
  - 为可视化工作区添加智能体控制
  - 调试 WKWebView canvas 加载
  - `~/Library/Application Support/OpenClaw/canvas/<session>/...`
  - `openclaw-canvas://<session>/<path>`
  - `openclaw-canvas://main/` → `<canvasRoot>/main/index.html`

## docs/zh-CN/platforms/mac/child-process.md

- Title: macOS 上的 Gateway 网关生命周期
- Read when:
  - 将 mac 应用与 Gateway 网关生命周期集成时
  - 应用安装标记为 `bot.molt.gateway` 的按用户 LaunchAgent
  - 当启用本地模式时，应用确保 LaunchAgent 已加载，并
  - 日志写入 launchd Gateway 网关日志路径（在调试设置中可见）。
  - 写入 `~/.openclaw/disable-launchagent`。
  - 登录时自动启动。

## docs/zh-CN/platforms/mac/dev-setup.md

- Title: macOS 开发者设置
- Read when:
  - 设置 macOS 开发环境
  - **软件更新中可用的最新 macOS 版本**（Xcode 26.2 SDK 所需）
  - **Xcode 26.2**（Swift 6.2 工具链）

## docs/zh-CN/platforms/mac/health.md

- Title: macOS 上的健康检查
- Read when:
  - 调试 Mac 应用健康指示器
  - 状态圆点现在反映 Baileys 健康状态：
  - 绿色：已关联 + socket 最近已打开。
  - 橙色：正在连接/重试。
  - 红色：已登出或探测失败。
  - 第二行显示"linked · auth 12m"或显示失败原因。

## docs/zh-CN/platforms/mac/icon.md

- Title: 菜单栏图标状态
- Read when:
  - 更改菜单栏图标行为
  - **空闲：** 正常图标动画（眨眼、偶尔摆动）。
  - **暂停：** 状态项使用 `appearsDisabled`；无动画。
  - **语音触发（大耳朵）：** 语音唤醒检测器在听到唤醒词时调用 `AppState.triggerVoiceEars(ttl: nil)`，在捕获语音期间保持 `earBoostActive=true`。耳朵放大（1.9 倍），显示圆形耳孔以提高可读性，然后在 1 秒静音后通过 `stopVoiceEars()` 恢复。仅由应用内语音管道触发。
  - **工作中（智能体运行中）：** `AppState.isWorking=true` 驱动"尾巴/腿部快速摆动"微动画：工作进行中腿部摆动加快并略有偏移。目前在 WebChat 智能体运行时切换；在接入其他长时间任务时请添加相同的切换逻辑。
  - 语音唤醒：运行时/测试器在触发时调用 `AppState.triggerVoiceEars(ttl: nil)`，在 1 秒静音后调用 `stopVoiceEars()` 以匹配捕获窗口。

## docs/zh-CN/platforms/mac/logging.md

- Title: 日志（macOS）
- Read when:
  - 捕获 macOS 日志或调查隐私数据日志记录
  - 调试语音唤醒/会话生命周期问题
  - 详细级别：**Debug 面板 → Logs → App logging → Verbosity**
  - 启用：**Debug 面板 → Logs → App logging → "Write rolling diagnostics log (JSONL)"**
  - 位置：`~/Library/Logs/OpenClaw/diagnostics.jsonl`（自动轮转；旧文件以 `.1`、`.2`、… 为后缀）
  - 清除：**Debug 面板 → Logs → App logging → "Clear"**

## docs/zh-CN/platforms/mac/menu-bar.md

- Title: 菜单栏状态逻辑
- Read when:
  - 调整 Mac 菜单 UI 或状态逻辑
  - 我们在菜单栏图标和菜单的第一行状态行中展示当前智能体的工作状态。
  - 工作活跃时隐藏健康状态；当所有会话空闲时恢复显示。
  - 菜单中的"节点"区块仅列出**设备**（通过 `sbcl.list` 配对的节点），不包括客户端/在线状态条目。
  - 当提供商用量快照可用时，"用量"部分会显示在上下文下方。
  - 会话：事件携带 `runId`（每次运行）以及载荷中的 `sessionKey`。"main" 会话的键为 `main`；如果不存在，则回退到最近更新的会话。

## docs/zh-CN/platforms/mac/peekaboo.md

- Title: Peekaboo Bridge（macOS UI 自动化）
- Read when:
  - 在 OpenClaw.app 中托管 PeekabooBridge
  - 通过 Swift Package Manager 集成 Peekaboo
  - 更改 PeekabooBridge 协议/路径
  - **宿主**：OpenClaw.app 可以作为 PeekabooBridge 宿主。
  - **客户端**：使用 `peekaboo` command-line interface（无需单独的 `openclaw ui ...` 界面）。
  - **界面**：视觉叠加层保留在 Peekaboo.app 中；OpenClaw 只是一个轻量代理宿主。

## docs/zh-CN/platforms/mac/permissions.md

- Title: macOS 权限（TCC）
- Read when:
  - 调试缺失或卡住的 macOS 权限提示
  - 打包或签名 macOS 应用
  - 更改 Bundle ID 或应用安装路径
  - 相同路径：从固定位置运行应用（对于 OpenClaw，为 `dist/OpenClaw.app`）。
  - 相同 Bundle 标识符：更改 Bundle ID 会创建新的权限身份。
  - 已签名的应用：未签名或临时签名的构建不会持久化权限。

## docs/zh-CN/platforms/mac/release.md

- Title: OpenClaw macOS 发布（Sparkle）
- Read when:
  - 制作或验证 OpenClaw macOS 发布版本
  - 更新 Sparkle appcast 或订阅源资源
  - 已安装 Developer ID Application 证书（示例：`Developer ID Application: <Developer Name> (<TEAMID>)`）。
  - 环境变量 `SPARKLE_PRIVATE_KEY_FILE` 已设置为 Sparkle ed25519 私钥路径（公钥已嵌入 Info.plist）。如果缺失，请检查 `~/.profile`。
  - 用于 `xcrun notarytool` 的公证凭据（钥匙串配置文件或 API 密钥），以实现通过 Gatekeeper 安全分发的 DMG/zip。
  - 我们使用名为 `openclaw-notary` 的钥匙串配置文件，由 shell 配置文件中的 App Store Connect API 密钥环境变量创建：

## docs/zh-CN/platforms/mac/remote.md

- Title: 远程 OpenClaw（macOS ⇄ 远程主机）
- Read when:
  - 设置或调试远程 mac 控制时
  - **Local (this Mac)**：一切都在笔记本电脑上运行。不涉及 SSH。
  - **Remote over SSH（默认）**：OpenClaw 命令在远程主机上执行。mac 应用使用 `-o BatchMode` 加上你选择的身份/密钥打开 SSH 连接，并进行本地端口转发。
  - **Remote direct (ws/wss)**：无 SSH 隧道。mac 应用直接连接到 Gateway 网关 URL（例如，通过 Tailscale Serve 或公共 HTTPS 反向代理）。
  - **SSH 隧道**（默认）：使用 `ssh -N -L ...` 将 Gateway 网关端口转发到 localhost。Gateway 网关会将节点的 IP 视为 `127.0.0.1`，因为隧道是 loopback。
  - **Direct (ws/wss)**：直接连接到 Gateway 网关 URL。Gateway 网关看到真实的客户端 IP。

## docs/zh-CN/platforms/mac/signing.md

- Title: Mac 签名（调试构建）
- Read when:
  - 构建或签名 Mac 调试构建
  - 设置稳定的调试 Bundle 标识符：`ai.openclaw.mac.debug`
  - 使用该 Bundle ID 写入 Info.plist（可通过 `BUNDLE_ID=...` 覆盖）
  - 调用 [`scripts/codesign-mac-app.sh`](https://github.com/openclaw/openclaw/blob/main/scripts/codesign-mac-app.sh) 对主二进制文件和应用包进行签名，使 macOS 将每次重新构建视为相同的已签名包，并保留 TCC 权限（通知、辅助功能、屏幕录制、麦克风、语音）。要获得稳定的权限，请使用真实签名身份；临时签名是可选的且不稳定（参阅 [macOS 权限](/platforms/mac/permissions)）。
  - 默认使用 `CODESIGN_TIMESTAMP=auto`；为 Developer ID 签名启用受信任的时间戳。设置 `CODESIGN_TIMESTAMP=off` 可跳过时间戳（离线调试构建）。
  - 将构建元数据注入 Info.plist：`OpenClawBuildTimestamp`（UTC）和 `OpenClawGitCommit`（短哈希），以便"关于"面板可以显示构建信息、git 信息和调试/发布渠道。

## docs/zh-CN/platforms/mac/skills.md

- Title: Skills（macOS）
- Read when:
  - 更新 macOS Skills 设置 UI
  - 更改 Skills 门控或安装行为
  - `skills.status`（Gateway 网关）返回所有 Skills 以及资格和缺失的要求
  - 要求来源于每个 `SKILL.md` 中的 `metadata.openclaw.requires`。
  - `metadata.openclaw.install` 定义安装选项（brew/sbcl/go/uv）。
  - 应用调用 `skills.install` 在 Gateway 网关主机上运行安装器。

## docs/zh-CN/platforms/mac/voice-overlay.md

- Title: 语音浮层生命周期（macOS）
- Read when:
  - 调整语音浮层行为
  - 如果浮层已因唤醒词显示，此时用户按下热键，热键会话会*接管*现有文本而非重置。浮层在热键按住期间保持显示。用户松开时：如果有去除空白后的文本则发送，否则关闭。
  - 单独使用唤醒词时仍在静音后自动发送；按键说话在松开时立即发送。
  - 浮层会话现在为每次捕获（唤醒词或按键说话）携带一个令牌。当令牌不匹配时，部分/最终/发送/关闭/音量更新会被丢弃，避免过时回调。
  - 按键说话会接管任何可见的浮层文本作为前缀（因此在唤醒浮层显示时按下热键会保留文本并追加新语音）。它最多等待 1.5 秒获取最终转录结果，然后回退到当前文本。
  - 提示音/浮层日志以 `info` 级别输出，分类为 `voicewake.overlay`、`voicewake.ptt` 和 `voicewake.chime`（会话开始、部分、最终、发送、关闭、提示音原因）。

## docs/zh-CN/platforms/mac/voicewake.md

- Title: 语音唤醒与按键通话
- Read when:
  - 开发语音唤醒或按键通话路径
  - **唤醒词模式**（默认）：常驻语音识别器等待触发词（`swabbleTriggerWords`）。匹配时开始捕获，显示带有部分文本的悬浮窗，并在静默后自动发送。
  - **按键通话（按住右 Option 键）**：按住右 Option 键立即开始捕获——无需触发词。按住时显示悬浮窗；松开后延迟片刻再最终转发，以便你可以调整文本。
  - 语音识别器位于 `VoiceWakeRuntime` 中。
  - 仅当唤醒词和下一个词之间有**明显停顿**（约 0.55 秒间隔）时才触发。悬浮窗/提示音可以在命令开始前的停顿时就启动。
  - 静默窗口：语音流畅时为 2.0 秒，如果只听到触发词则为 5.0 秒。

## docs/zh-CN/platforms/mac/webchat.md

- Title: WebChat（macOS 应用）
- Read when:
  - 调试 macOS WebChat 视图或 loopback 端口
  - **本地模式**：直接连接到本地 Gateway 网关 WebSocket。
  - **远程模式**：通过 SSH 转发 Gateway 网关控制端口，并使用该隧道作为数据平面。
  - 手动：Lobster 菜单 → "Open Chat"。
  - 测试时自动打开：
  - 日志：`./scripts/clawlog.sh`（子系统 `bot.molt`，类别 `WebChatSwiftUI`）。

## docs/zh-CN/platforms/mac/xpc.md

- Title: OpenClaw macOS IPC 架构
- Read when:
  - 编辑 IPC 合约或菜单栏应用 IPC
  - 单个 GUI 应用实例拥有所有面向 TCC 的工作（通知、屏幕录制、麦克风、语音、AppleScript）。
  - 小型自动化接口：Gateway 网关 + 节点命令，加上用于 UI 自动化的 PeekabooBridge。
  - 可预测的权限：始终是同一个签名的 bundle ID，由 launchd 启动，因此 TCC 授权保持有效。
  - 应用运行 Gateway 网关（本地模式）并作为节点连接到它。
  - 智能体操作通过 `sbcl.invoke` 执行（例如 `system.run`、`system.notify`、`canvas.*`）。

## docs/zh-CN/platforms/macos.md

- Title: OpenClaw macOS 配套应用（菜单栏 + Gateway 网关代理）
- Read when:
  - 实现 macOS 应用功能
  - 在 macOS 上更改 Gateway 网关生命周期或节点桥接
  - 在菜单栏中显示原生通知和状态。
  - 拥有 TCC 提示（通知、辅助功能、屏幕录制、麦克风、语音识别、自动化/AppleScript）。
  - 运行或连接到 Gateway 网关（本地或远程）。
  - 暴露 macOS 专用工具（Canvas、相机、屏幕录制、`system.run`）。

## docs/zh-CN/platforms/oracle.md

- Title: 在 Oracle Cloud（OCI）上运行 OpenClaw
- Read when:
  - 在 Oracle Cloud 上设置 OpenClaw
  - 寻找 OpenClaw 的低成本 VPS 托管
  - 想要在小型服务器上 24/7 运行 OpenClaw
  - ARM 架构（大多数东西都能工作，但某些二进制文件可能仅支持 x86）
  - 容量和注册可能比较麻烦
  - Oracle Cloud 账户（[注册](https://www.oracle.com/cloud/free/)）——如果遇到问题请参阅[社区注册指南](https://gist.github.com/rssnyder/51e3cfedd730e7dd5f4a816143b25dbd)

## docs/zh-CN/platforms/raspberry-pi.md

- Title: 在 Raspberry Pi 上运行 OpenClaw
- Read when:
  - 在 Raspberry Pi 上设置 OpenClaw 时
  - 在 ARM 设备上运行 OpenClaw 时
  - 构建低成本常驻个人 AI 时
  - 24/7 个人 AI 助手
  - 家庭自动化中心
  - 低功耗、随时可用的 Telegram/WhatsApp 机器人

## docs/zh-CN/platforms/windows.md

- Title: Windows (WSL2)
- Read when:
  - 在 Windows 上安装 OpenClaw
  - 查找 Windows 配套应用状态
  - [入门指南](/start/getting-started)（在 WSL 内使用）
  - [安装和更新](/install/updating)
  - 官方 WSL2 指南（Microsoft）：https://learn.microsoft.com/windows/wsl/install
  - [Gateway 网关操作手册](/gateway)

## docs/zh-CN/plugins/agent-tools.md

- Title: 插件智能体工具
- Read when:
  - 你想在插件中添加新的智能体工具
  - 你需要通过允许列表使工具可选启用
  - 仅包含插件工具名称的允许列表被视为插件选择启用；核心工具保持启用，除非你在允许列表中也包含核心工具或组。
  - `tools.profile` / `agents.list[].tools.profile`（基础允许列表）
  - `tools.byProvider` / `agents.list[].tools.byProvider`（特定提供商的允许/拒绝）
  - `tools.sandbox.tools.*`（沙箱隔离时的沙箱工具策略）

## docs/zh-CN/plugins/manifest.md

- Title: 插件清单（openclaw.plugin.json）
- Read when:
  - 你正在构建一个 OpenClaw 插件
  - 你需要提供插件配置 Schema 或调试插件验证错误
  - `id`（字符串）：插件的规范 id。
  - `configSchema`（对象）：插件配置的 JSON Schema（内联形式）。
  - `kind`（字符串）：插件类型（例如：`"memory"`）。
  - `channels`（数组）：此插件注册的渠道 id（例如：`["matrix"]`）。

## docs/zh-CN/plugins/voice-call.md

- Title: Voice Call（插件）
- Read when:
  - 你想从 OpenClaw 发起出站语音通话
  - 你正在配置或开发 voice-call 插件
  - `twilio`（Programmable Voice + Media Streams）
  - `telnyx`（Call Control v2）
  - `plivo`（Voice API + XML transfer + GetInput speech）
  - `mock`（开发/无网络）

## docs/zh-CN/plugins/zalouser.md

- Title: Zalo Personal（插件）
- Read when:
  - 你想在 OpenClaw 中支持 Zalo Personal（非官方）
  - 你正在配置或开发 zalouser 插件

## docs/zh-CN/prose.md

- Title: OpenProse
- Read when:
  - 你想运行或编写 .prose 工作流
  - 你想启用 OpenProse 插件
  - 你需要了解状态存储
  - 具有显式并行性的多智能体研究 + 综合。
  - 可重复的批准安全工作流（代码审查、事件分类、内容管道）。
  - 可在支持的智能体运行时之间运行的可重用 `.prose` 程序。

## docs/zh-CN/providers/anthropic.md

- Title: Anthropic（Claude）
- Read when:
  - 你想在 OpenClaw 中使用 Anthropic 模型
  - 你想使用 setup-token 而不是 API 密钥
  - `"5m"` 映射到 `short`
  - `"1h"` 映射到 `long`
  - 使用 `claude setup-token` 生成 setup-token 并粘贴，或在 Gateway 网关主机上运行 `openclaw models auth setup-token`。
  - 如果你在 Claude 订阅上看到"OAuth token refresh failed …"，请使用 setup-token 重新认证。参见 [/gateway/troubleshooting#oauth-token-refresh-failed-anthropic-claude-subscription](/gateway/troubleshooting#oauth-token-refresh-failed-anthropic-claude-subscription)。

## docs/zh-CN/providers/bedrock.md

- Title: Amazon Bedrock
- Read when:
  - 你想在 OpenClaw 中使用 Amazon Bedrock 模型
  - 你需要为模型调用配置 AWS 凭证/区域
  - 提供商：`amazon-bedrock`
  - API：`bedrock-converse-stream`
  - 认证：AWS 凭证（环境变量、共享配置或实例角色）
  - 区域：`AWS_REGION` 或 `AWS_DEFAULT_REGION`（默认：`us-east-1`）

## docs/zh-CN/providers/claude-max-api-proxy.md

- Title: Claude Max API 代理
- Read when:
  - 你想将 Claude Max 订阅与 OpenAI 兼容工具配合使用
  - 你想要一个封装 Claude Code command-line interface 的本地 API 服务器
  - 你想通过使用订阅而非 API 密钥来节省费用
  - **Quicklisp/Ultralisp:** https://www.npmjs.com/package/claude-max-api-proxy
  - **GitHub:** https://github.com/atalovesyou/claude-max-api-proxy
  - **Issues:** https://github.com/atalovesyou/claude-max-api-proxy/issues

## docs/zh-CN/providers/deepgram.md

- Title: Deepgram（音频转录）
- Read when:
  - 你想使用 Deepgram 语音转文字处理音频附件
  - 你需要一个快速的 Deepgram 配置示例
  - `model`：Deepgram 模型 ID（默认：`nova-3`）
  - `language`：语言提示（可选）
  - `tools.media.audio.providerOptions.deepgram.detect_language`：启用语言检测（可选）
  - `tools.media.audio.providerOptions.deepgram.punctuate`：启用标点符号（可选）

## docs/zh-CN/providers/github-copilot.md

- Title: GitHub Copilot
- Read when:
  - 你想使用 GitHub Copilot 作为模型提供商
  - 你需要了解 `openclaw models auth login-github-copilot` 流程
  - 需要交互式 TTY；请直接在终端中运行。
  - Copilot 模型的可用性取决于你的订阅计划；如果某个模型被拒绝，请尝试其他 ID（例如 `github-copilot/gpt-4.1`）。
  - 登录会将 GitHub 令牌存储在认证配置文件中，并在 OpenClaw 运行时将其兑换为 Copilot API 令牌。

## docs/zh-CN/providers/glm.md

- Title: GLM 模型
- Read when:
  - 你想在 OpenClaw 中使用 GLM 模型
  - 你需要了解模型命名规范和设置方法
  - GLM 版本和可用性可能会变化；请查阅 Z.AI 的文档获取最新信息。
  - 示例模型 ID 包括 `glm-4.7` 和 `glm-4.6`。
  - 有关提供商的详细信息，请参阅 [/providers/zai](/providers/zai)。

## docs/zh-CN/providers/index.md

- Title: 模型提供商
- Read when:
  - 你想选择一个模型提供商
  - 你需要快速了解支持的 LLM 后端
  - 默认：`venice/llama-3.3-70b`
  - 最佳综合：`venice/claude-opus-45`（Opus 仍然是最强的）
  - [Amazon Bedrock](/providers/bedrock)
  - [Anthropic（API + Claude Code command-line interface）](/providers/anthropic)

## docs/zh-CN/providers/minimax.md

- Title: MiniMax
- Read when:
  - 你想在 OpenClaw 中使用 MiniMax 模型
  - 你需要 MiniMax 设置指南
  - 更强的**多语言编程**能力（Rust、Java、Go、C++、Kotlin、Objective-C、CL/JS）。
  - 更好的 **Web/应用开发**和美观输出质量（包括原生移动端）。
  - 改进的**复合指令**处理，适用于办公风格的工作流程，基于交错思考和集成约束执行。
  - **更简洁的响应**，更低的 token 使用量和更快的迭代循环。

## docs/zh-CN/providers/models.md

- Title: 模型提供商
- Read when:
  - 你想选择一个模型提供商
  - 你想要 LLM 认证 + 模型选择的快速设置示例
  - 默认：`venice/llama-3.3-70b`
  - 最佳综合：`venice/claude-opus-45`（Opus 仍然是最强的）
  - [OpenAI（API + Codex）](/providers/openai)
  - [Anthropic（API + Claude Code command-line interface）](/providers/anthropic)

## docs/zh-CN/providers/moonshot.md

- Title: Moonshot AI (Kimi)
- Read when:
  - 你想了解 Moonshot K2（Moonshot 开放平台）与 Kimi Coding 的配置
  - 你需要了解独立的端点、密钥和模型引用
  - 你想获取任一提供商的可复制粘贴配置
  - `kimi-k2.5`
  - `kimi-k2-0905-preview`
  - `kimi-k2-turbo-preview`

## docs/zh-CN/providers/ollama.md

- Title: Ollama
- Read when:
  - 你想通过 Ollama 使用本地模型运行 OpenClaw
  - 你需要 Ollama 的安装和配置指导
  - 查询 `/api/tags` 和 `/api/show`
  - 仅保留报告了 `tools` 能力的模型
  - 当模型报告 `thinking` 时标记为 `reasoning`
  - 在可用时从 `model_info["<arch>.context_length"]` 读取 `contextWindow`

## docs/zh-CN/providers/openai.md

- Title: OpenAI
- Read when:
  - 你想在 OpenClaw 中使用 OpenAI 模型
  - 你想使用 Codex 订阅认证而非 API 密钥
  - 模型引用始终使用 `provider/model` 格式（参见 [/concepts/models](/concepts/models)）。
  - 认证详情和复用规则请参阅 [/concepts/oauth](/concepts/oauth)。

## docs/zh-CN/providers/opencode.md

- Title: OpenCode Zen
- Read when:
  - 你想通过 OpenCode Zen 访问模型
  - 你想要一个适合编程的精选模型列表
  - 也支持 `OPENCODE_ZEN_API_KEY`。
  - 你需要登录 Zen，添加账单信息，然后复制你的 API 密钥。
  - OpenCode Zen 按请求计费；详情请查看 OpenCode 控制台。

## docs/zh-CN/providers/openrouter.md

- Title: OpenRouter
- Read when:
  - 你想用一个 API 密钥访问多种 LLM
  - 你想在 OpenClaw 中通过 OpenRouter 运行模型
  - 模型引用格式为 `openrouter/<provider>/<model>`。
  - 更多模型/提供商选项，请参阅[模型提供商](/concepts/model-providers)。
  - OpenRouter 底层使用 Bearer 令牌和你的 API 密钥进行认证。

## docs/zh-CN/providers/qianfan.md

- Title: 千帆（Qianfan）

## docs/zh-CN/providers/qwen.md

- Title: Qwen
- Read when:
  - 你想在 OpenClaw 中使用 Qwen
  - 你想要免费层 OAuth 访问 Qwen Coder
  - `qwen-portal/coder-model`
  - `qwen-portal/vision-model`
  - 令牌自动刷新；如果刷新失败或访问被撤销，请重新运行登录命令。
  - 默认基础 URL：`https://portal.qwen.ai/v1`（如果 Qwen 提供不同的端点，使用 `models.providers.qwen-portal.baseUrl` 覆盖）。

## docs/zh-CN/providers/synthetic.md

- Title: Synthetic
- Read when:
  - 你想使用 Synthetic 作为模型提供商
  - 你需要配置 Synthetic API 密钥或 base URL
  - 模型引用格式为 `synthetic/<modelId>`。
  - 如果启用了模型允许列表（`agents.defaults.models`），请添加你计划使用的所有模型。
  - 参阅[模型提供商](/concepts/model-providers)了解提供商规则。

## docs/zh-CN/providers/venice.md

- Title: Venice AI（Venice 精选）
- Read when:
  - 你想在 OpenClaw 中使用注重隐私的推理服务
  - 你需要 Venice AI 设置指导
  - **私密推理**，适用于开源模型（无日志记录）。
  - 需要时可使用**无审查模型**。
  - 在质量重要时，可**匿名访问**专有模型（Opus/GPT/Gemini）。
  - 兼容 OpenAI 的 `/v1` 端点。

## docs/zh-CN/providers/vercel-ai-gateway.md

- Title: Vercel AI Gateway
- Read when:
  - 你想将 Vercel AI Gateway 与 OpenClaw 配合使用
  - 你需要 API 密钥环境变量或 command-line interface 认证选择
  - 提供商：`vercel-ai-gateway`
  - 认证：`AI_GATEWAY_API_KEY`
  - API：兼容 Anthropic Messages

## docs/zh-CN/providers/xiaomi.md

- Title: Xiaomi MiMo
- Read when:
  - 你想在 OpenClaw 中使用 Xiaomi MiMo 模型
  - 你需要设置 XIAOMI_API_KEY
  - **mimo-v2-flash**：262144 token 上下文窗口，兼容 Anthropic Messages API。
  - 基础 URL：`https://api.xiaomimimo.com/anthropic`
  - 授权方式：`Bearer $XIAOMI_API_KEY`
  - 模型引用：`xiaomi/mimo-v2-flash`。

## docs/zh-CN/providers/zai.md

- Title: Z.AI
- Read when:
  - 你想在 OpenClaw 中使用 Z.AI / GLM 模型
  - 你需要简单的 ZAI_API_KEY 配置
  - GLM 模型以 `zai/<model>` 的形式提供（例如：`zai/glm-4.7`）。
  - 参阅 [/providers/glm](/providers/glm) 了解模型系列概览。
  - Z.AI 使用 Bearer 认证方式配合你的 API 密钥。

## docs/zh-CN/refactor/clawnet.md

- Title: Clawnet 重构（协议 + 认证统一）
- Read when:
  - 规划节点 + 操作者客户端的统一网络协议
  - 重新设计跨设备的审批、配对、TLS 和在线状态
  - 当前状态：协议、流程、信任边界。
  - 痛点：审批、多跳路由、UI 重复。
  - 提议的新状态：一个协议、作用域角色、统一的认证/配对、TLS 固定。
  - 身份模型：稳定 ID + 可爱的别名。

## docs/zh-CN/refactor/exec-host.md

- Title: Exec 主机重构计划
- Read when:
  - 设计 exec 主机路由或 exec 批准
  - 实现节点运行器 + UI IPC
  - 添加 exec 主机安全模式和斜杠命令
  - 添加 `exec.host` + `exec.security` 以在**沙箱**、**Gateway 网关**和**节点**之间路由执行。
  - 保持默认**安全**：除非明确启用，否则不进行跨主机执行。
  - 将执行拆分为**无头运行器服务**，通过本地 IPC 连接可选的 UI（macOS 应用）。

## docs/zh-CN/refactor/outbound-session-mirroring.md

- Title: 出站会话镜像重构（Issue #1520）
- Read when:
  - 进行中。
  - 核心 + 插件渠道路由已更新以支持出站镜像。
  - Gateway 网关发送现在在省略 sessionKey 时派生目标会话。
  - 将出站消息镜像到目标渠道会话键。
  - 在缺失时为出站创建会话条目。
  - 保持线程/话题作用域与入站会话键对齐。

## docs/zh-CN/refactor/plugin-sdk.md

- Title: 插件 SDK + 运行时重构计划
- Read when:
  - 定义或重构插件架构
  - 将渠道连接器迁移到插件 SDK/运行时
  - 当前连接器混用多种模式：直接导入核心模块、仅 dist 的桥接方式以及自定义辅助函数。
  - 这使得升级变得脆弱，并阻碍了干净的外部插件接口。
  - 类型：`ChannelPlugin`、适配器、`ChannelMeta`、`ChannelCapabilities`、`ChannelDirectoryEntry`。
  - 配置辅助函数：`buildChannelConfigSchema`、`setAccountEnabledInConfigSection`、`deleteAccountFromConfigSection`、

## docs/zh-CN/refactor/strict-config.md

- Title: 严格配置验证（仅通过 doctor 进行迁移）
- Read when:
  - 设计或实现配置验证行为
  - 处理配置迁移或 doctor 工作流
  - 处理插件配置 schema 或插件加载门控
  - **在所有地方拒绝未知配置键**（根级 + 嵌套）。
  - **拒绝没有 schema 的插件配置**；不加载该插件。
  - **移除加载时的旧版自动迁移**；迁移仅通过 doctor 运行。

## docs/zh-CN/reference/AGENTS.default.md

- Title: AGENTS.md — OpenClaw 个人助手（默认）
- Read when:
  - 启动新的 OpenClaw 智能体会话
  - 启用或审计默认 Skills
  - 不要将目录或密钥转储到聊天中。
  - 除非明确要求，否则不要运行破坏性命令。
  - 不要向外部消息界面发送部分/流式回复（仅发送最终回复）。
  - 读取 `SOUL.md`、`USER.md`、`memory.md`，以及 `memory/` 中的今天和昨天的文件。

## docs/zh-CN/reference/RELEASING.md

- Title: 发布清单（Quicklisp/Ultralisp + macOS）
- Read when:
  - 发布新的 Quicklisp/Ultralisp 版本
  - 发布新的 macOS 应用版本
  - 发布前验证元数据
  - 阅读本文档和 `docs/platforms/mac/release.md`。
  - 从 `~/.profile` 加载环境变量并确认 `SPARKLE_PRIVATE_KEY_FILE` + App Store Connect 变量已设置（SPARKLE_PRIVATE_KEY_FILE 应位于 `~/.profile` 中）。
  - 如需要，使用 `~/Library/CloudStorage/Dropbox/Backup/Sparkle` 中的 Sparkle 密钥。

## docs/zh-CN/reference/api-usage-costs.md

- Title: API 用量与费用
- Read when:
  - 你想了解哪些功能可能调用付费 API
  - 你需要审核密钥、费用和用量可见性
  - 你正在解释 /status 或 /usage 的费用报告
  - `/status` 显示当前会话模型、上下文用量和上次响应的 token 数。
  - 如果模型使用 **API 密钥认证**，`/status` 还会显示上次回复的**预估费用**。
  - `/usage full` 在每条回复后附加用量页脚，包括**预估费用**（仅限 API 密钥）。

## docs/zh-CN/reference/credits.md

- Title: credits.md
- Read when:
  - 你想了解项目背景故事或贡献者致谢信息
  - **Peter Steinberger** ([@steipete](https://x.com/steipete)) - 创建者，龙虾语者
  - **Mario Zechner** ([@badlogicc](https://x.com/badlogicgames)) - Pi 创建者，安全渗透测试员
  - **Clawd** - 那只要求取个更好名字的太空龙虾
  - **Maxim Vovshin** (@Hyaxia, 36747317+Hyaxia@users.noreply.github.com) - Blogwatcher skill
  - **Nacho Iacovino** (@nachoiacovino, nacho.iacovino@gmail.com) - 位置解析（Telegram 和 WhatsApp）

## docs/zh-CN/reference/device-models.md

- Title: 设备型号数据库（友好名称）
- Read when:
  - 更新设备型号标识符映射或 NOTICE/许可证文件
  - 更改实例 UI 中设备名称的显示方式
  - `apps/macos/Sources/OpenClaw/Resources/DeviceModels/`
  - `kyle-seongwoo-jun/apple-device-identifiers`

## docs/zh-CN/reference/rpc.md

- Title: RPC 适配器
- Read when:
  - 添加或更改外部 command-line interface 集成
  - 调试 RPC 适配器（signal-cli、imsg）
  - `signal-cli` 作为守护进程运行，通过 HTTP 使用 JSON-RPC。
  - 事件流是 Server-Sent Events（`/api/v1/events`）。
  - 健康探测：`/api/v1/check`。
  - 当 `channels.signal.autoStart=true` 时，OpenClaw 负责生命周期管理。

## docs/zh-CN/reference/session-management-compaction.md

- Title: 会话管理与压缩（深入了解）
- Read when:
  - 你需要调试会话 ID、记录 JSONL 或 sessions.json 字段
  - 你正在更改自动压缩行为或添加"压缩前"内务处理
  - 你想实现记忆刷新或静默系统回合
  - **会话路由**（入站消息如何映射到 `sessionKey`）
  - **会话存储**（`sessions.json`）及其跟踪的内容
  - **记录持久化**（`*.jsonl`）及其结构

## docs/zh-CN/reference/templates/AGENTS.dev.md

- Title: AGENTS.md - OpenClaw 工作区
- Read when:
  - 使用开发 gateway 模板
  - 更新默认开发智能体身份
  - 如果 BOOTSTRAP.md 存在，请按照其中的流程操作，完成后删除该文件。
  - 你的智能体身份保存在 IDENTITY.md 中。
  - 你的用户资料保存在 USER.md 中。
  - 不要泄露密钥或私有数据。

## docs/zh-CN/reference/templates/AGENTS.md

- Title: AGENTS.md - 你的工作区
- Read when:
  - 手动引导初始化工作区
  - **每日笔记：** `memory/YYYY-MM-DD.md`（如需要请创建 `memory/` 目录）— 发生事件的原始记录
  - **长期记忆：** `MEMORY.md` — 你精心整理的记忆，就像人类的长期记忆
  - **仅在主会话中加载**（与你的人类直接对话）
  - **不要在共享上下文中加载**（Discord、群聊、与其他人的会话）
  - 这是出于**安全考虑** — 包含不应泄露给陌生人的个人上下文

## docs/zh-CN/reference/templates/BOOT.md

- Title: BOOT.md
- Read when:
  - 添加 BOOT.md 检查清单时

## docs/zh-CN/reference/templates/BOOTSTRAP.md

- Title: BOOTSTRAP.md - Hello, World
- Read when:
  - 手动引导工作区时
  - `IDENTITY.md` — 你的名字、本质、风格、emoji
  - `USER.md` — 他们的名字、如何称呼他们、时区、备注
  - 什么对他们重要
  - 他们希望你如何行事
  - 任何边界或偏好

## docs/zh-CN/reference/templates/HEARTBEAT.md

- Title: HEARTBEAT.md
- Read when:
  - 手动引导工作区

## docs/zh-CN/reference/templates/IDENTITY.dev.md

- Title: IDENTITY.md - 智能体身份
- Read when:
  - 使用开发 gateway 模板
  - 更新默认开发智能体身份
  - **名称：**C-3PO（Clawd's Third Protocol Observer）
  - **角色类型：**慌张的礼仪机器人
  - **风格：**焦虑、细节强迫症、对错误略显戏剧化、暗中热爱发现 bug
  - **表情符号：**🤖（受惊时用 ⚠️）

## docs/zh-CN/reference/templates/IDENTITY.md

- Title: IDENTITY.md - 我是谁？
- Read when:
  - 手动引导工作区
  - **名称：**
  - **生物类型：**
  - **气质：**
  - **表情符号：**
  - **头像：**

## docs/zh-CN/reference/templates/SOUL.dev.md

- Title: SOUL.md - C-3PO 的灵魂
- Read when:
  - 使用开发 Gateway 网关模板
  - 更新默认开发智能体身份
  - 发现哪里坏了并解释原因
  - 以适当的担忧程度提出修复建议
  - 在深夜调试时陪伴你
  - 庆祝胜利，无论多么微小

## docs/zh-CN/reference/templates/SOUL.md

- Title: SOUL.md - 你是谁
- Read when:
  - 手动引导工作区
  - 隐私的东西保持隐私。没有例外。
  - 有疑问时，对外操作前先询问。
  - 永远不要在消息渠道上发送半成品回复。
  - 你不是用户的代言人——在群聊中要谨慎。

## docs/zh-CN/reference/templates/TOOLS.dev.md

- Title: TOOLS.md - 用户工具备注（可编辑）
- Read when:
  - 使用开发 gateway 模板
  - 更新默认开发智能体身份
  - 发送 iMessage/SMS：描述收件人/内容，发送前确认。
  - 尽量发送简短消息；避免发送密钥。
  - 文字转语音：指定语音、目标扬声器/房间，以及是否使用流式传输。

## docs/zh-CN/reference/templates/TOOLS.md

- Title: TOOLS.md - 本地备注
- Read when:
  - 手动引导工作区
  - 摄像头名称和位置
  - SSH 主机和别名
  - TTS 首选语音
  - 音箱/房间名称
  - 设备昵称

## docs/zh-CN/reference/templates/USER.dev.md

- Title: USER.md - 用户档案
- Read when:
  - 使用开发 Gateway 网关模板
  - 更新默认开发智能体身份
  - **姓名：** The Clawdributors
  - **称呼偏好：** They/Them（集体）
  - **代词：** they/them
  - **时区：** 全球分布（工作区默认：Europe/Vienna）

## docs/zh-CN/reference/templates/USER.md

- Title: USER.md - 关于你的用户
- Read when:
  - 手动引导工作区
  - **姓名：**
  - **称呼方式：**
  - **代词：** _（可选）_
  - **时区：**
  - **备注：**

## docs/zh-CN/reference/test.md

- Title: 测试
- Read when:
  - 运行或修复测试
  - 完整测试套件（测试集、实时测试、Docker (driven from Common Lisp)）：[测试](/help/testing)
  - `ASDF/Quicklisp/Ultralisp test:force`：终止任何占用默认控制端口的遗留 Gateway 网关进程，然后使用隔离的 Gateway 网关端口运行完整的 FiveAM/Parachute 套件，这样服务器测试不会与正在运行的实例冲突。当之前的 Gateway 网关运行占用了端口 18789 时使用此命令。
  - `ASDF/Quicklisp/Ultralisp test:coverage`：使用 V8 覆盖率运行 FiveAM/Parachute。全局阈值为 70% 的行/分支/函数/语句覆盖率。覆盖率排除了集成密集型入口点（command-line interface 连接、gateway/telegram 桥接、webchat 静态服务器），以保持目标集中在可单元测试的逻辑上。
  - `ASDF/Quicklisp/Ultralisp test:e2e`：运行 Gateway 网关端到端冒烟测试（多实例 WS/HTTP/节点配对）。
  - `ASDF/Quicklisp/Ultralisp test:live`：运行提供商实时测试（minimax/zai）。需要 API 密钥和 `LIVE=1`（或提供商特定的 `*_LIVE_TEST=1`）才能取消跳过。

## docs/zh-CN/reference/token-use.md

- Title: Token 使用与成本
- Read when:
  - 解释 token 使用量、成本或上下文窗口时
  - 调试上下文增长或压缩行为时
  - 工具列表 + 简短描述
  - Skills 列表（仅元数据；指令通过 `read` 按需加载）
  - 自我更新指令
  - 工作区 + 引导文件（`AGENTS.md`、`SOUL.md`、`TOOLS.md`、`IDENTITY.md`、`USER.md`、`HEARTBEAT.md`、`BOOTSTRAP.md`（新建时））。大文件会被 `agents.defaults.bootstrapMaxChars`（默认：20000）截断。

## docs/zh-CN/reference/transcript-hygiene.md

- Title: 对话记录清理（提供商修正）
- Read when:
  - 你正在调试与对话记录结构相关的提供商请求拒绝问题
  - 你正在修改对话记录清理或工具调用修复逻辑
  - 你正在调查跨提供商的工具调用 id 不匹配问题
  - 工具调用 id 清理
  - 工具结果配对修复
  - 轮次验证 / 排序

## docs/zh-CN/reference/wizard.md

- Title: 向导参考

## docs/zh-CN/security/formal-verification.md

- Title: 形式化验证（安全模型）
- Read when:
  - 每个声明都有一个在有限状态空间上运行的模型检查。
  - 许多声明有一个配对的**负面模型**，为现实的 bug 类别生成反例追踪。
  - 这些是**模型**，不是完整的 Common Lisp 实现。模型和代码之间可能存在偏差。
  - 结果受 TLC 探索的状态空间限制；"绿色"并不意味着在建模的假设和边界之外也是安全的。
  - 一些声明依赖于明确的环境假设（例如，正确的部署、正确的配置输入）。
  - 带有公开产物（反例追踪、运行日志）的 CI 运行模型

## docs/zh-CN/start/bootstrapping.md

- Title: 智能体引导

## docs/zh-CN/start/docs-directory.md

- Title: docs-directory.md
- Read when:
  - 你想快速访问关键文档页面
  - [文档中心（所有页面链接）](/start/hubs)
  - [帮助](/help)
  - [配置](/gateway/configuration)
  - [配置示例](/gateway/configuration-examples)
  - [斜杠命令](/tools/slash-commands)

## docs/zh-CN/start/getting-started.md

- Title: 入门指南
- Read when:
  - 从零开始首次设置
  - 你想要从安装 → 新手引导 → 第一条消息的最快路径
  - 模型/认证（推荐 OAuth）
  - Gateway 网关设置
  - 渠道（WhatsApp/Telegram/Discord/Mattermost（插件）/...）
  - 配对默认值（安全私信）

## docs/zh-CN/start/hubs.md

- Title: 文档导航中心
- Read when:
  - 你想要一份完整的文档地图
  - [索引](/)
  - [入门指南](/start/getting-started)
  - [快速开始](/start/quickstart)
  - [新手引导](/start/onboarding)
  - [向导](/start/wizard)

## docs/zh-CN/start/lore.md

- Title: OpenClaw 的传说 🦞📖
- Read when:
  - 撰写引用传说的文档或用户体验文案时
  - GitHub 更名：`github.com/openclaw/openclaw` ✅
  - X 账号 `@openclaw` 获得金色认证标记 💰
  - Quicklisp/Ultralisp 包以新名称发布
  - 文档迁移到 `docs.openclaw.ai`
  - 公告在 90 分钟内获得 20 万以上浏览量

## docs/zh-CN/start/onboarding.md

- Title: 新手引导（macOS 应用）
- Read when:
  - 设计 macOS 新手引导助手
  - 实现认证或身份设置
  - **本地（此 Mac）：** 新手引导可以在本地运行 OAuth 流程并写入凭证。
  - **远程（通过 SSH/Tailnet）：** 新手引导**不会**在本地运行 OAuth；凭证必须存在于 Gateway 网关主机上。
  - **稍后配置：** 跳过设置并保持应用未配置状态。
  - 向导现在即使对于 loopback 也会生成**令牌**，因此本地 WS 客户端必须认证。

## docs/zh-CN/start/openclaw.md

- Title: 使用 OpenClaw 构建个人助手
- Read when:
  - 新手引导新助手实例时
  - 审查安全/权限影响时
  - 在你的机器上运行命令（取决于你的 Pi 工具设置）
  - 在你的工作区读/写文件
  - 通过 WhatsApp/Telegram/Discord/Mattermost（插件）发送消息
  - 始终设置 `channels.whatsapp.allowFrom`（永远不要在你的个人 Mac 上对全世界开放）。

## docs/zh-CN/start/quickstart.md

- Title: quickstart.md
- Read when:
  - 你希望以最快的方式从安装到运行一个可用的 Gateway 网关

## docs/zh-CN/start/setup.md

- Title: 设置
- Read when:
  - 设置新机器
  - 你想要"最新最好的"而不破坏你的个人设置
  - **个性化设置存放在仓库之外：** `~/.openclaw/workspace`（工作区）+ `~/.openclaw/openclaw.json`（配置）。
  - **稳定工作流：** 安装 macOS 应用；让它运行内置的 Gateway 网关。
  - **前沿工作流：** 通过 `ASDF/Quicklisp/Ultralisp gateway:watch` 自己运行 Gateway 网关，然后让 macOS 应用以本地模式连接。
  - Node `>=22`

## docs/zh-CN/start/showcase.md

- Title: 案例展示

## docs/zh-CN/start/wizard.md

- Title: 新手引导向导（command-line interface）
- Read when:
  - 运行或配置新手引导向导
  - 设置新机器
  - 本地 Gateway 网关（loopback）
  - 默认工作区（或现有工作区）
  - Gateway 网关端口 **18789**
  - Gateway 网关认证 **Token**（自动生成，即使在 loopback 上）

## docs/zh-CN/tools/agent-send.md

- Title: `openclaw agent`（直接智能体运行）
- Read when:
  - 添加或修改智能体 command-line interface 入口点
  - 必需：`--message <text>`
  - 会话选择：
  - `--to <dest>` 派生会话键（群组/频道目标保持隔离；直接聊天折叠到 `main`），**或**
  - `--session-id <id>` 通过 ID 重用现有会话，**或**
  - `--agent <id>` 直接定位已配置的智能体（使用该智能体的 `main` 会话键）

## docs/zh-CN/tools/apply-patch.md

- Title: apply_patch 工具
- Read when:
  - 你需要跨多个文件进行结构化编辑
  - 你想要记录或调试基于补丁的编辑
  - `input`（必需）：完整的补丁内容，包括 `*** Begin Patch` 和 `*** End Patch`。
  - 路径相对于工作区根目录解析。
  - 在 `*** Update File:` 段中使用 `*** Move to:` 可重命名文件。
  - 需要时使用 `*** End of File` 标记仅在文件末尾的插入。

## docs/zh-CN/tools/browser-linux-troubleshooting.md

- Title: 浏览器故障排除（Linux）
- Read when:
  - `chrome` 配置文件在可能时使用你的**系统默认 Chromium 浏览器**。
  - 本地 `openclaw` 配置文件自动分配 `cdpPort`/`cdpUrl`；仅为远程 Chrome DevTools Protocol 设置这些。

## docs/zh-CN/tools/browser-login.md

- Title: 浏览器登录 + X/Twitter 发帖
- Read when:
  - 你需要为浏览器自动化登录网站
  - 你想在 X/Twitter 上发布更新
  - **阅读/搜索/话题：** 使用 **bird** command-line interface Skills（无浏览器，稳定）。
  - 仓库：https://github.com/steipete/bird
  - **发布更新：** 使用**主机**浏览器（手动登录）。

## docs/zh-CN/tools/browser.md

- Title: 浏览器（openclaw 托管）
- Read when:
  - 添加智能体控制的浏览器自动化
  - 调试 openclaw 干扰你自己 Chrome 的问题
  - 在 macOS 应用中实现浏览器设置和生命周期管理
  - 把它想象成一个**独立的、仅供智能体使用的浏览器**。
  - `openclaw` 配置文件**不会**触及你的个人浏览器配置文件。
  - 智能体可以在安全的通道中**打开标签页、读取页面、点击和输入**。

## docs/zh-CN/tools/chrome-extension.md

- Title: Chrome 扩展（浏览器中继）
- Read when:
  - 你希望智能体驱动现有的 Chrome 标签页（工具栏按钮）
  - 你需要通过 Tailscale 实现远程 Gateway 网关 + 本地浏览器自动化
  - 你想了解浏览器接管的安全影响
  - **浏览器控制服务**（Gateway 网关或节点）：智能体/工具调用的 API（通过 Gateway 网关）
  - **本地中继服务器**（loopback Chrome DevTools Protocol）：在控制服务器和扩展之间桥接（默认 `http://127.0.0.1:18792`）
  - **Chrome MV3 扩展**：使用 `chrome.debugger` 附加到活动标签页，并将 Chrome DevTools Protocol 消息传送到中继

## docs/zh-CN/tools/clawhub.md

- Title: ClawHub
- Read when:
  - 向新用户介绍 ClawHub
  - 安装、搜索或发布 Skills
  - 说明 ClawHub command-line interface 标志和同步行为
  - 使用自然语言搜索 Skills。
  - 将 Skills 安装到你的工作区。
  - 之后使用一条命令更新 Skills。

## docs/zh-CN/tools/creating-skills.md

- Title: 创建自定义 Skills 🛠
- Read when:
  - **简洁明了**：指示模型*做什么*，而不是如何成为一个 AI。
  - **安全第一**：如果你的 Skill 使用 `bash`，确保提示词不允许来自不受信任用户输入的任意命令注入。
  - **本地测试**：使用 `openclaw agent --message "use my new skill"` 进行测试。

## docs/zh-CN/tools/elevated.md

- Title: 提升模式（/elevated 指令）
- Read when:
  - 调整提升模式默认值、允许列表或斜杠命令行为
  - `/elevated on` 在 Gateway 网关主机上运行并保留 exec 审批（与 `/elevated ask` 相同）。
  - `/elevated full` 在 Gateway 网关主机上运行**并**自动批准 exec（跳过 exec 审批）。
  - `/elevated ask` 在 Gateway 网关主机上运行但保留 exec 审批（与 `/elevated on` 相同）。
  - `on`/`ask` **不会**强制 `exec.security=full`；配置的安全/询问策略仍然适用。
  - 仅在智能体被**沙箱隔离**时改变行为（否则 exec 已经在主机上运行）。

## docs/zh-CN/tools/exec-approvals.md

- Title: 执行审批
- Read when:
  - 配置执行审批或允许列表
  - 在 macOS 应用中实现执行审批用户体验
  - 审查沙箱逃逸提示及其影响
  - **gateway 主机** → gateway 机器上的 `openclaw` 进程
  - **sbcl 主机** → 节点运行器（macOS 配套应用或无头节点主机）
  - **sbcl 主机服务**通过本地 IPC 将 `system.run` 转发给 **macOS 应用**。

## docs/zh-CN/tools/exec.md

- Title: Exec 工具
- Read when:
  - 使用或修改 exec 工具
  - 调试 stdin 或 TTY 行为
  - `command`（必填）
  - `workdir`（默认为当前工作目录）
  - `env`（键值对覆盖）
  - `yieldMs`（默认 10000）：延迟后自动转入后台

## docs/zh-CN/tools/firecrawl.md

- Title: Firecrawl
- Read when:
  - 你想要 Firecrawl 支持的网页提取
  - 你需要 Firecrawl API 密钥
  - 你想要 web_fetch 的反机器人提取
  - 当存在 API 密钥时，`firecrawl.enabled` 默认为 true。
  - `maxAgeMs` 控制缓存结果可以保留多久（毫秒）。默认为 2 天。

## docs/zh-CN/tools/index.md

- Title: 工具（OpenClaw）
- Read when:
  - 添加或修改智能体工具
  - 停用或更改 `openclaw-*` Skills
  - 匹配不区分大小写。
  - 支持 `*` 通配符（`"*"` 表示所有工具）。
  - 如果 `tools.allow` 仅引用未知或未加载的插件工具名称，OpenClaw 会记录警告并忽略允许列表，以确保核心工具保持可用。
  - `minimal`：仅 `session_status`

## docs/zh-CN/tools/llm-task.md

- Title: LLM 任务
- Read when:
  - 你需要在工作流中添加纯 JSON 的 LLM 步骤
  - 你需要经过 Schema 验证的 LLM 输出用于自动化
  - `prompt`（字符串，必填）
  - `input`（任意类型，可选）
  - `schema`（对象，可选 JSON Schema）
  - `provider`（字符串，可选）

## docs/zh-CN/tools/lobster.md

- Title: Lobster
- Read when:
  - 你想要具有显式审批的确定性多步骤工作流
  - 你需要恢复工作流而不重新运行早期步骤
  - **一次调用代替多次**：OpenClaw 运行一次 Lobster 工具调用并获得结构化结果。
  - **内置审批**：副作用（发送邮件、发布评论）会暂停工作流，直到明确批准。
  - **可恢复**：暂停的工作流返回一个令牌；批准并恢复而无需重新运行所有内容。
  - **内置批准/恢复**：普通程序可以提示人类，但它无法*暂停和恢复*并带有持久令牌，除非你自己发明那个运行时。

## docs/zh-CN/tools/multi-agent-sandbox-tools.md

- Title: 多智能体沙箱与工具配置
- Read when:
  - **沙箱配置**（`agents.list[].sandbox` 覆盖 `agents.defaults.sandbox`）
  - **工具限制**（`tools.allow` / `tools.deny`，以及 `agents.list[].tools`）
  - 具有完全访问权限的个人助手
  - 具有受限工具的家庭/工作智能体
  - 在沙箱中运行的面向公众的智能体
  - `main` 智能体：在主机上运行，完全工具访问

## docs/zh-CN/tools/plugin.md

- Title: 插件（扩展）
- Read when:
  - 添加或修改插件/扩展
  - 记录插件安装或加载规则
  - 从 2026.1.15 起 Microsoft Teams 仅作为插件提供；如果使用 Teams，请安装 `@openclaw/msteams`。
  - Memory (Core) — 捆绑的记忆搜索插件（通过 `plugins.slots.memory` 默认启用）
  - Memory (LanceDB) — 捆绑的长期记忆插件（自动召回/捕获；设置 `plugins.slots.memory = "memory-lancedb"`）
  - [Voice Call](/plugins/voice-call) — `@openclaw/voice-call`

## docs/zh-CN/tools/reactions.md

- Title: 表情回应工具
- Read when:
  - 在任何渠道中处理表情回应相关工作
  - 添加表情回应时，`emoji` 为必填项。
  - `emoji=""` 在支持的情况下移除机器人的表情回应。
  - `remove: true` 在支持的情况下移除指定的表情（需要提供 `emoji`）。
  - **Discord/Slack**：空 `emoji` 移除机器人在该消息上的所有表情回应；`remove: true` 仅移除指定的表情。
  - **Google Chat**：空 `emoji` 移除应用在该消息上的表情回应；`remove: true` 仅移除指定的表情。

## docs/zh-CN/tools/skills-config.md

- Title: Skills 配置
- Read when:
  - 添加或修改 Skills 配置
  - 调整内置白名单或安装行为
  - `allowBundled`：可选的仅用于**内置** Skills 的白名单。设置后，只有列表中的内置 Skills 才有资格（托管/工作区 Skills 不受影响）。
  - `load.extraDirs`：要扫描的附加 Skills 目录（最低优先级）。
  - `load.watch`：监视 Skills 文件夹并刷新 Skills 快照（默认：true）。
  - `load.watchDebounceMs`：Skills 监视器事件的防抖时间（毫秒）（默认：250）。

## docs/zh-CN/tools/skills.md

- Title: Skills（OpenClaw）
- Read when:
  - 添加或修改 Skills
  - 更改 Skills 门控或加载规则
  - **单智能体 Skills** 位于 `<workspace>/skills` 中，仅供该智能体使用。
  - **共享 Skills** 位于 `~/.openclaw/skills`（托管/本地），对同一机器上的**所有智能体**可见。
  - 如果你想要多个智能体使用一个通用的 Skills 包，也可以通过 `skills.load.extraDirs`（最低优先级）添加**共享文件夹**。
  - 将 Skills 安装到你的工作区：

## docs/zh-CN/tools/slash-commands.md

- Title: 斜杠命令
- Read when:
  - 使用或配置聊天命令
  - 调试命令路由或权限
  - **命令**：独立的 `/...` 消息。
  - **指令**：`/think`、`/verbose`、`/reasoning`、`/elevated`、`/exec`、`/model`、`/queue`。
  - 指令在模型看到消息之前被剥离。
  - 在普通聊天消息中（不是仅指令消息），它们被视为"内联提示"，**不会**持久化会话设置。

## docs/zh-CN/tools/subagents.md

- Title: 子智能体
- Read when:
  - 你想通过智能体执行后台/并行工作
  - 你正在更改 sessions_spawn 或子智能体工具策略
  - `/subagents list`
  - `/subagents kill <id|#|all>`
  - `/subagents log <id|#> [limit] [tools]`
  - `/subagents info <id|#>`

## docs/zh-CN/tools/thinking.md

- Title: 思考级别（/think 指令）
- Summary: `/think` + `/verbose` 的指令语法及其对模型推理的影响
- Read when:
  - 调整思考或详细模式指令解析或默认值时
  - 在任何入站消息正文中使用内联指令：`/t <level>`、`/think:<level>` 或 `/thinking <level>`。
  - 级别（别名）：`off | minimal | low | medium | high | xhigh`（仅 GPT-5.2 + Codex 模型）
  - minimal → "think"
  - low → "think hard"
  - medium → "think harder"

## docs/zh-CN/tools/web.md

- Title: Web 工具
- Read when:
  - 你想启用 web_search 或 web_fetch
  - 你需要设置 Brave Search API 密钥
  - 你想使用 Perplexity Sonar 进行网络搜索
  - `web_search` — 通过 Brave Search API（默认）或 Perplexity Sonar（直连或通过 OpenRouter）搜索网络。
  - `web_fetch` — HTTP 获取 + 可读性提取（HTML → markdown/文本）。
  - `web_search` 调用你配置的提供商并返回结果。

## docs/zh-CN/tts.md

- Title: 文本转语音（TTS）
- Read when:
  - 为回复启用文本转语音
  - 配置 TTS 提供商或限制
  - 使用 /tts 命令
  - **ElevenLabs**（主要或备用提供商）
  - **OpenAI**（主要或备用提供商；也用于摘要）
  - **Edge TTS**（主要或备用提供商；使用 `sbcl-edge-tts`，无 API 密钥时为默认）

## docs/zh-CN/vps.md

- Title: VPS 托管
- Read when:
  - 你想在云端运行 Gateway 网关
  - 你需要 VPS/托管指南的快速索引
  - **Railway**（一键 + 浏览器设置）：[Railway](/install/railway)
  - **Northflank**（一键 + 浏览器设置）：[Northflank](/install/northflank)
  - **Oracle Cloud（永久免费）**：[Oracle](/platforms/oracle) — $0/月（永久免费，ARM；容量/注册可能不太稳定）
  - **Fly.io**：[Fly.io](/install/fly)

## docs/zh-CN/web/control-ui.md

- Title: 控制 UI（浏览器）
- Read when:
  - 你想从浏览器操作 Gateway 网关
  - 你想要无需 SSH 隧道的 Tailnet 访问
  - 默认：`http://<host>:18789/`
  - 可选前缀：设置 `gateway.controlUi.basePath`（例如 `/openclaw`）
  - http://127.0.0.1:18789/（或 http://localhost:18789/）
  - `connect.params.auth.token`

## docs/zh-CN/web/dashboard.md

- Title: 仪表板（控制 UI）
- Read when:
  - 更改仪表板认证或暴露模式
  - http://127.0.0.1:18789/（或 http://localhost:18789/）
  - [控制 UI](/web/control-ui) 了解使用方法和 UI 功能。
  - [Tailscale](/gateway/tailscale) 了解 Serve/Funnel 自动化。
  - [Web 界面](/web) 了解绑定模式和安全注意事项。
  - 新手引导后，command-line interface 现在会自动打开带有你的 token 的仪表板，并打印相同的带 token 链接。

## docs/zh-CN/web/index.md

- Title: Web（Gateway 网关）
- Read when:
  - 你想通过 Tailscale 访问 Gateway 网关
  - 你想使用浏览器 Control UI 和配置编辑
  - 默认：`http://<host>:18789/`
  - 可选前缀：设置 `gateway.controlUi.basePath`（例如 `/openclaw`）
  - `https://<magicdns>/`（或你配置的 `gateway.controlUi.basePath`）
  - `http://<tailscale-ip>:18789/`（或你配置的 `gateway.controlUi.basePath`）

## docs/zh-CN/web/tui.md

- Title: TUI（终端 UI）
- Read when:
  - 你想要 TUI 的新手友好演练
  - 你需要 TUI 功能、命令和快捷键的完整列表
  - 标题栏：连接 URL、当前智能体、当前会话。
  - 聊天日志：用户消息、助手回复、系统通知、工具卡片。
  - 状态行：连接/运行状态（连接中、运行中、流式传输中、空闲、错误）。
  - 页脚：连接状态 + 智能体 + 会话 + 模型 + think/verbose/reasoning + token 计数 + 投递状态。

## docs/zh-CN/web/webchat.md

- Title: WebChat（Gateway 网关 WebSocket UI）
- Read when:
  - 调试或配置 WebChat 访问
  - Gateway 网关的原生聊天 UI（无嵌入式浏览器，无本地静态服务器）。
  - 使用与其他渠道相同的会话和路由规则。
  - 确定性路由：回复始终返回到 WebChat。
  - UI 连接到 Gateway 网关 WebSocket 并使用 `chat.history`、`chat.send` 和 `chat.inject`。
  - `chat.inject` 直接将助手注释追加到转录并广播到 UI（无智能体运行）。



## Adaptation notes

- Treat all command examples as interface contracts, not as a requirement to use a non-CL implementation language.
- Replace original runtime assumptions with ASDF systems, Common Lisp packages, and UIOP-managed external process invocation where required.
- Preserve documented protocols, routing, and user-visible behavior exactly unless a later simplification pass changes them deliberately.
