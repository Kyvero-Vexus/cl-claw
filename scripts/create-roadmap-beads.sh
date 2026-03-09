#!/bin/bash
set -e
cd ~/projects/cl-claw

# Helper function
create_task() {
  local title="$1"
  local desc="$2"
  local priority="$3"
  local type="${4:-task}"
  local parent="${5:-}"
  
  local args=(bd create "$title" --description="$desc" -t "$type" -p "$priority" --json)
  
  local output
  output=$("${args[@]}" 2>&1)
  local id=$(echo "$output" | grep '"id"' | head -1 | sed 's/.*"id": "\([^"]*\)".*/\1/')
  echo "$id"
  
  if [ -n "$parent" ]; then
    bd dep add "$id" "$parent" 2>/dev/null || true
  fi
}

echo "=== Creating Phase 0 Epics and Tasks ==="

# Epic 0.1: HTTP Server & WebSocket Core
E01=$(create_task "Epic 0.1: HTTP Server & WebSocket Core" "Build the HTTP/WS server that everything else plugs into. Hunchentoot/Woo with TLS, WebSocket for gateway control protocol." 0 epic)
echo "Epic 0.1: $E01"

create_task "HTTP server setup with Hunchentoot/Woo + TLS" "Set up the base HTTP server using Hunchentoot or Woo with TLS support. Define route dispatch, request/response handling, and server lifecycle." 0 task "$E01"
create_task "WebSocket server for gateway control protocol" "Implement WebSocket server (hunchensocket or custom) for the gateway WS control protocol. Handle connection upgrade, frame handling, ping/pong." 0 task "$E01"
create_task "Gateway auth layer — token/password modes, rate limiting" "Implement gateway authentication: token mode, password mode, auth mode policy, rate limiter (IP tracking, lockout, expiry), trusted-proxy support. ~40 test specs." 0 task "$E01"
create_task "Server startup/shutdown lifecycle, graceful drain" "Implement server boot sequence, graceful shutdown with connection drain, signal handling." 0 task "$E01"
create_task "Health check endpoints & server discovery" "Health check HTTP endpoints, server discovery protocol for multi-instance setups." 0 task "$E01"

# Epic 0.2: Gateway Core Runner
E02=$(create_task "Epic 0.2: Gateway Core Runner" "Main orchestration loop: boot sequence, session orchestration, channel health, heartbeat, config resolution, multi-account, tools catalog." 0 epic)
echo "Epic 0.2: $E02"
bd dep add "$E02" "$E01" 2>/dev/null || true

create_task "Gateway boot sequence (BOOT.md processing)" "Implement runBootOnce — check for BOOT.md, run agent command, per-agent session keys, session ID management. ~10 test specs." 0 task "$E02"
create_task "Session orchestration via WebSocket" "Create/resume/route sessions through the WS control protocol. Session mapping, turn serialization." 0 task "$E02"
create_task "Gateway call infrastructure" "callGateway, buildGatewayConnectionDetails, URL resolution, credential flow, password/token SecretRef resolution. ~30 test specs." 0 task "$E02"
create_task "Channel health monitor" "Startup grace period, periodic health checks, reconnection triggers. ~10 test specs." 0 task "$E02"
create_task "Heartbeat/keepalive system" "Gateway connection heartbeat, timeout detection, reconnection." 0 task "$E02"
create_task "Gateway configuration resolution" "Env vars, config files, SecretRefs, runtime overrides for gateway settings." 0 task "$E02"
create_task "Multi-account gateway support" "Multiple accounts per channel, account selection, credential isolation." 0 task "$E02"
create_task "Gateway server tools catalog & dispatch" "Tool registry, catalog endpoint, tool dispatch from gateway to tool executors." 0 task "$E02"

# Epic 0.3: Provider HTTP Layer
E03=$(create_task "Epic 0.3: Provider HTTP Layer" "Actual LLM API calls with streaming — Anthropic, OpenAI, OpenRouter, auth profiles, failover, token counting." 0 epic)
echo "Epic 0.3: $E03"

create_task "HTTP client abstraction with SSE streaming" "Build HTTP client wrapper around Dexador with Server-Sent Events streaming support for LLM providers." 0 task "$E03"
create_task "Anthropic API provider" "Messages API endpoint, streaming, tool use blocks, system prompts, model selection." 0 task "$E03"
create_task "OpenAI API provider" "Chat completions endpoint, streaming, function calling, response format." 0 task "$E03"
create_task "OpenRouter provider" "Routing layer, model selection, fallback, provider-specific headers." 0 task "$E03"
create_task "Provider auth profiles system" "OAuth, API key, cooldown/rotation, migration, per-provider store. ~40+ agent auth test files." 0 task "$E03"
create_task "Provider failover & round-robin logic" "Multi-profile ordering, lastGood tracking, cooldown expiry, explicit order vs round-robin." 0 task "$E03"
create_task "Token counting & budget enforcement" "Token counting per provider, budget limits, compaction triggers." 0 task "$E03"
create_task "Provider-specific quirks" "Gemini, Groq, DeepSeek, Chutes, Volcengine, Kilocode — provider-specific auth/API differences." 1 task "$E03"

# Epic 0.4: Context Engine
E04=$(create_task "Epic 0.4: Context Engine" "Prompt assembly, token budgets, workspace file injection, session history assembly." 0 epic)
echo "Epic 0.4: $E04"
bd dep add "$E04" "$E03" 2>/dev/null || true

create_task "Context engine core — prompt assembly" "Assemble prompts from system/user/tool messages. Content array handling, text extraction." 0 task "$E04"
create_task "Token budget system" "Token counting integration, budget allocation, trimming strategies, compaction triggers." 0 task "$E04"
create_task "Workspace file injection" "Inject SOUL.md, AGENTS.md, USER.md, TOOLS.md etc into prompt context." 0 task "$E04"
create_task "Session history assembly with truncation" "Build conversation history with token-aware truncation and sliding window." 0 task "$E04"
create_task "Agent prompt construction & identity" "Agent prompt building, assistant identity resolution, avatar normalization." 0 task "$E04"

# Epic 0.5: Tool Execution Framework
E05=$(create_task "Epic 0.5: Tool Execution Framework" "Tool dispatch for all gateway tools — exec, read/write, browser, image, web, TTS, message, canvas, approval system." 0 epic)
echo "Epic 0.5: $E05"
bd dep add "$E05" "$E01" 2>/dev/null || true

create_task "Tool dispatch core — registry, validation, permissions" "Tool registry with parameter validation, permission checking, approval flow integration." 0 task "$E05"
create_task "Exec tool — shell commands with PTY" "Shell command execution with PTY support, timeout, backgrounding, process registry. ~12 process test specs." 0 task "$E05"
create_task "Read/Write/Edit tools — file operations" "File read/write/edit with path security, symlink protection, workspace scoping." 0 task "$E05"
create_task "Browser tool — CDP integration" "Chrome DevTools Protocol client, snapshot, navigate, click, type, screenshot." 0 task "$E05"
create_task "Image/PDF analysis tools" "Vision model dispatch for image and PDF analysis." 1 task "$E05"
create_task "Web fetch/search tools" "HTTP fetch with content extraction, web search integration." 0 task "$E05"
create_task "TTS tool dispatch" "Text-to-speech tool — engine abstraction, voice selection, audio delivery." 1 task "$E05"
create_task "Message/canvas/node tools" "Channel message actions, canvas control, node device tools." 1 task "$E05"
create_task "Tool approval/permission system" "Ask modes (off/on-miss/always), allowlists, security levels, elevated permissions." 0 task "$E05"
create_task "Tool invoke HTTP — remote invocation" "Remote tool invocation via HTTP, approval bypass for node-invoked tools." 1 task "$E05"

echo ""
echo "=== Creating Phase 1 Epics (Channels) ==="

# Phase 1 Epic
P1=$(create_task "Phase 1: Channel Implementations" "Implement all channel protocols — Telegram, Discord, IRC, Signal, Slack, WhatsApp, iMessage, Line." 0 epic)
echo "Phase 1: $P1"
bd dep add "$P1" "$E02" 2>/dev/null || true

# Epic 1.1: Channel Core
E11=$(create_task "Epic 1.1: Channel Protocol Core" "Shared channel infrastructure: lifecycle, message normalization, formatting, account management, rate limiting." 0 epic)
echo "Epic 1.1: $E11"
bd dep add "$E11" "$E02" 2>/dev/null || true

create_task "Channel lifecycle — connect/disconnect/reconnect/health" "Base channel class with lifecycle management, reconnection logic, health reporting." 0 task "$E11"
create_task "Inbound message normalization" "Normalize inbound messages from all channels: text, media, attachments, metadata." 0 task "$E11"
create_task "Outbound message formatting per channel" "Markdown adaptation per channel (Discord mrkdwn, Telegram HTML, Slack blocks, etc)." 0 task "$E11"
create_task "Channel account management" "Multi-account support, per-channel config, credential management." 0 task "$E11"
create_task "Channel rate limiting & queue management" "Per-channel rate limits, message queuing, retry with backoff." 0 task "$E11"

# Epic 1.2: Telegram
E12=$(create_task "Epic 1.2: Telegram Channel" "Full Telegram Bot API implementation — polling/webhook, messages, media, groups/topics, polls, effects. ~62 test specs." 0 epic)
echo "Epic 1.2: $E12"
bd dep add "$E12" "$E11" 2>/dev/null || true

create_task "Telegram Bot API client — polling & webhook modes" "HTTP client for Telegram Bot API, long polling and webhook setup." 0 task "$E12"
create_task "Telegram message handling — text, media, stickers, reactions" "Send/receive text, photos, documents, stickers, reactions, reply markup." 0 task "$E12"
create_task "Telegram groups/topics — forum topic support" "Forum topic routing, group message handling, thread-based conversations." 0 task "$E12"
create_task "Telegram inline queries, callbacks, commands" "Inline query handling, callback queries, bot command registration." 1 task "$E12"
create_task "Telegram media upload/download" "File upload/download via Telegram API, size limits, format handling." 0 task "$E12"
create_task "Telegram polls, effects, voice messages" "Poll creation/voting, message effects, voice message handling." 1 task "$E12"

# Epic 1.3: Discord
E13=$(create_task "Epic 1.3: Discord Channel" "Full Discord integration — gateway WS, REST API, threads, slash commands, media, presence. ~73 test specs." 0 epic)
echo "Epic 1.3: $E13"
bd dep add "$E13" "$E11" 2>/dev/null || true

create_task "Discord gateway WebSocket client" "Connect to Discord gateway, handle IDENTIFY, RESUME, heartbeat, dispatch events." 0 task "$E13"
create_task "Discord REST API client" "Messages, threads, reactions, channels, guilds via Discord REST API." 0 task "$E13"
create_task "Discord thread management & ACP bindings" "Create/archive threads, ACP session binding to channels/threads." 0 task "$E13"
create_task "Discord slash commands & interactions" "Slash command registration, interaction handling, message components." 1 task "$E13"
create_task "Discord media/attachments & embeds" "File uploads, embed construction, attachment handling." 0 task "$E13"
create_task "Discord presence & activity status" "Bot presence, activity status (playing/watching/etc), status updates." 1 task "$E13"

# Epic 1.4: IRC
E14=$(create_task "Epic 1.4: IRC Channel" "IRC client — connect, auth, join/part, PRIVMSG, reconnection." 0 epic)
echo "Epic 1.4: $E14"
bd dep add "$E14" "$E11" 2>/dev/null || true

create_task "IRC client — connect, NickServ auth, join/part" "TLS connection, NickServ authentication, channel join/part, nick management." 0 task "$E14"
create_task "IRC message handling — PRIVMSG, NOTICE, CTCP" "Send/receive PRIVMSG, NOTICE, CTCP queries (VERSION, PING, etc)." 0 task "$E14"
create_task "IRC reconnection & resilience" "Auto-reconnect on disconnect, exponential backoff, nick recovery." 0 task "$E14"

# Epic 1.5: Signal
E15=$(create_task "Epic 1.5: Signal Channel" "Signal CLI/daemon integration — messages, media, groups, attachments. ~13 test specs." 1 epic)
echo "Epic 1.5: $E15"
bd dep add "$E15" "$E11" 2>/dev/null || true

create_task "Signal CLI/daemon integration" "Interface with signal-cli daemon via JSON-RPC or D-Bus." 1 task "$E15"
create_task "Signal message handling — text, media, reactions, groups" "Send/receive messages, attachments, reactions, group management." 1 task "$E15"

# Epic 1.6: Slack
E16=$(create_task "Epic 1.6: Slack Channel" "Slack Web API, Events API, Socket Mode, blocks, threads, files. ~49 test specs." 1 epic)
echo "Epic 1.6: $E16"
bd dep add "$E16" "$E11" 2>/dev/null || true

create_task "Slack Web API + Events API client" "HTTP client for Slack Web API, Events API webhook handling." 1 task "$E16"
create_task "Slack Socket Mode" "Real-time event handling via Slack Socket Mode WebSocket." 1 task "$E16"
create_task "Slack message formatting (blocks, mrkdwn)" "Slack-specific message formatting with Block Kit, mrkdwn syntax." 1 task "$E16"
create_task "Slack threads, reactions, file uploads" "Thread management, reaction handling, file upload via Slack API." 1 task "$E16"
create_task "Slack app configuration & OAuth" "Slack app setup, OAuth flow, token management." 1 task "$E16"

# Epic 1.7: WhatsApp
E17=$(create_task "Epic 1.7: WhatsApp Channel" "WhatsApp Web/Business API — messages, media, auth flow. ~2+ test specs." 1 epic)
echo "Epic 1.7: $E17"
bd dep add "$E17" "$E11" 2>/dev/null || true

create_task "WhatsApp Web/Business API integration" "WhatsApp API client, message send/receive, session management." 1 task "$E17"
create_task "WhatsApp auth flow (QR code, persistence)" "QR code authentication, session persistence across restarts." 1 task "$E17"

# Epic 1.8: iMessage
E18=$(create_task "Epic 1.8: iMessage Channel" "iMessage bridge — send/receive, attachments, reactions. ~12 test specs." 2 epic)
echo "Epic 1.8: $E18"
bd dep add "$E18" "$E11" 2>/dev/null || true

create_task "iMessage bridge integration" "AppleScript/BlueBubbles bridge for iMessage send/receive." 2 task "$E18"
create_task "iMessage attachments & reactions" "Handle media attachments, tapback reactions." 2 task "$E18"

# Epic 1.9: Line
E19=$(create_task "Epic 1.9: Line Channel" "Line Messaging API — message types, rich menus, flex messages. ~18 test specs." 2 epic)
echo "Epic 1.9: $E19"
bd dep add "$E19" "$E11" 2>/dev/null || true

create_task "Line Messaging API client" "Line API client, webhook handling, message send/receive." 2 task "$E19"
create_task "Line message types & rich menus" "Text, image, video, audio, sticker, location, flex messages, rich menus." 2 task "$E19"

echo ""
echo "=== Creating Phase 2 (ACP) ==="

# Phase 2
E21=$(create_task "Epic 2.1: ACP Core" "Sub-agent control plane: client, session manager, runtime cache, persistent bindings, policy, server, translator. ~15 test specs." 0 epic)
echo "Epic 2.1: $E21"
bd dep add "$E21" "$E02" 2>/dev/null || true
bd dep add "$E21" "$E05" 2>/dev/null || true

create_task "ACP client — spawn env, invocation resolution" "resolveAcpClientSpawnEnv, resolveAcpClientSpawnInvocation, resolvePermissionRequest, event mapper." 0 task "$E21"
create_task "ACP session manager — concurrent turns, eviction" "Session tracking, concurrent turn serialization, max session cap, idle eviction, stale marking." 0 task "$E21"
create_task "ACP runtime cache & handle management" "RuntimeCache with idle tracking, touch-aware lookups, handle reuse/rehydration." 0 task "$E21"
create_task "ACP persistent bindings" "Channel-specific session binding, Discord/Telegram bindings, session key resolution." 0 task "$E21"
create_task "ACP policy & server startup" "Enable/disable policy, allowlist filtering, gateway hello handshake, credential passing." 0 task "$E21"
create_task "ACP translator — prompt prefix, rate limits" "Prompt CWD prefix (home dir redaction), session creation rate limiting, oversize prompt rejection." 0 task "$E21"
create_task "ACP runtime registry & error handling" "Backend registration, health checks, error boundary, error text formatting." 0 task "$E21"

E22=$(create_task "Epic 2.2: Agent System" "Agent config, auth profiles, bash tools, patch, sandbox, spawn, identity. ~401 test specs — largest domain." 0 epic)
echo "Epic 2.2: $E22"
bd dep add "$E22" "$E21" 2>/dev/null || true

create_task "Agent config resolution — paths, scope, model" "resolveAgentConfig, agent paths, scope, model primary/fallback, sandbox/tools config." 0 task "$E22"
create_task "Agent auth profiles — full OAuth/key/cooldown system" "Auth profile store, migration, credential eligibility, OAuth refresh/fallback, cooldown, round-robin. The largest test surface." 0 task "$E22"
create_task "Agent bash tools — exec, approval, Docker" "Bash process registry, Docker exec args, exec approval flow, exec runtime events." 0 task "$E22"
create_task "Agent patch application" "applyPatch with path traversal protection, symlink escape detection, workspace-only mode." 0 task "$E22"
create_task "Agent sandbox — bind specs, workspace isolation" "Sandbox bind spec parsing, Docker workspace, environment isolation." 0 task "$E22"
create_task "Agent spawn — ACP direct, thread binding, stream relay" "spawnAcpDirect, thread binding, parent stream relay, inline delivery." 0 task "$E22"
create_task "Agent anthropic payload logging" "Redact image base64 before writing debug logs." 1 task "$E22"

echo ""
echo "=== Creating Phase 3 (Web/CLI/Commands) ==="

E31=$(create_task "Epic 3.1: Web Server" "Webchat and API endpoints — routes, accounts, monitor inbox, auto-reply, send API. ~30 test specs." 1 epic)
echo "Epic 3.1: $E31"
bd dep add "$E31" "$E01" 2>/dev/null || true
bd dep add "$E31" "$E02" 2>/dev/null || true

create_task "Web server setup — routes, static files, CORS" "HTTP server routes for webchat, static file serving, CORS configuration." 1 task "$E31"
create_task "Webchat interface — inbound/outbound flow" "WebSocket-based webchat, message rendering, typing indicators." 1 task "$E31"
create_task "Account management API" "Account create/list/auth, WhatsApp auth integration." 1 task "$E31"
create_task "Monitor inbox — streaming, media capture" "Stream inbound messages, capture media paths, sender filtering." 1 task "$E31"
create_task "Send API — external message injection" "REST API for injecting messages from external sources." 1 task "$E31"

E32=$(create_task "Epic 3.2: CLI System" "Command-line interface — arg parsing, auth, gateway control, channel management. ~100 test specs." 1 epic)
echo "Epic 3.2: $E32"

create_task "CLI argument parsing & command routing" "Argument parser, subcommand dispatch, help generation." 1 task "$E32"
create_task "CLI auth management commands" "Auth profile CRUD, credential setup, OAuth flow." 1 task "$E32"
create_task "CLI gateway control commands" "Start/stop/status, config display, health check." 1 task "$E32"
create_task "CLI channel management commands" "Channel list/add/remove/configure, status display." 1 task "$E32"
create_task "CLI JSON stdout mode" "Machine-readable JSON output for programmatic CLI use." 1 task "$E32"

E33=$(create_task "Epic 3.3: Commands" "Gateway command implementations — session, config, agent, tool, admin commands. ~127 test specs." 1 epic)
echo "Epic 3.3: $E33"
bd dep add "$E33" "$E32" 2>/dev/null || true

create_task "Session commands — send, list, history" "Session management commands via gateway." 1 task "$E33"
create_task "Config commands — get, set, validate" "Configuration CRUD through commands." 1 task "$E33"
create_task "Agent commands — list, configure, spawn" "Agent management commands." 1 task "$E33"
create_task "Tool commands — catalog, invoke" "Tool catalog listing and invocation commands." 1 task "$E33"

echo ""
echo "=== Creating Phase 4 (Supporting Systems) ==="

E41=$(create_task "Epic 4.1: Auto-Reply" "Auto-reply trigger matching, response generation, rate limiting, media handling. ~87 test specs." 1 epic)
echo "Epic 4.1: $E41"
bd dep add "$E41" "$E02" 2>/dev/null || true

create_task "Auto-reply trigger matching" "Pattern matching, schedule-based triggers, condition evaluation." 1 task "$E41"
create_task "Auto-reply response generation" "Template-based responses, LLM dispatch for intelligent replies." 1 task "$E41"
create_task "Auto-reply rate limiting & cooldown" "Per-sender/channel rate limits, cooldown periods." 1 task "$E41"
create_task "Auto-reply media handling" "Compression, format conversion for auto-reply media." 1 task "$E41"

E42=$(create_task "Epic 4.2: Cron & Scheduling" "Cron expression parsing, job lifecycle, execution, persistence. ~60 test specs." 1 epic)
echo "Epic 4.2: $E42"

create_task "Cron expression parser & scheduler" "Parse cron expressions, compute next run times, schedule management." 1 task "$E42"
create_task "Cron job lifecycle — CRUD" "Create, update, delete, list cron jobs." 1 task "$E42"
create_task "Cron job execution & error handling" "Agent dispatch on cron trigger, error capture, retry." 1 task "$E42"
create_task "Cron persistence & recovery" "Persist cron state, recover scheduled jobs after restart." 1 task "$E42"

E43=$(create_task "Epic 4.3: Memory System" "Memory CRUD, indexing, compaction, context integration. ~37 test specs." 1 epic)
echo "Epic 4.3: $E43"

create_task "Memory store — CRUD operations" "Create, read, update, delete memories with structured storage." 1 task "$E43"
create_task "Memory indexing & retrieval" "Search and retrieval across stored memories." 1 task "$E43"
create_task "Memory compaction & context integration" "Memory cleanup/compaction, injection into context engine." 1 task "$E43"

E44=$(create_task "Epic 4.4: Hooks & Plugins" "Hook system, plugin SDK, plugin loading, built-in plugins. ~77 test specs total." 1 epic)
echo "Epic 4.4: $E44"

create_task "Hook system — registration & dispatch" "Hook registration, event dispatch, lifecycle management." 1 task "$E44"
create_task "Plugin SDK — API surface & versioning" "Plugin API definition, version negotiation, isolation." 1 task "$E44"
create_task "Plugin loading & management" "Dynamic plugin loading, dependency resolution, enable/disable." 1 task "$E44"

E45=$(create_task "Epic 4.5: Browser Automation" "CDP client, snapshot, actions, profiles, tabs. ~56 test specs." 1 epic)
echo "Epic 4.5: $E45"

create_task "Chrome DevTools Protocol client in CL" "WebSocket-based CDP client, command/event handling." 1 task "$E45"
create_task "Browser snapshot — accessibility tree" "Capture page accessibility tree for AI consumption." 1 task "$E45"
create_task "Browser actions — click, type, navigate, screenshot" "User interaction simulation, navigation, screenshot capture." 1 task "$E45"
create_task "Browser profile & tab management" "Profile creation/management, tab lifecycle." 1 task "$E45"

E46=$(create_task "Epic 4.6: Media & Link Understanding" "Media detection, upload/download, link preview, media analysis. ~41 test specs." 1 epic)
echo "Epic 4.6: $E46"

create_task "Media type detection & pipeline" "MIME type detection, media download/upload pipeline." 1 task "$E46"
create_task "Link preview extraction" "URL metadata extraction, OpenGraph/Twitter cards." 1 task "$E46"
create_task "Media understanding — analysis dispatch" "Image/video analysis via vision models." 1 task "$E46"

echo ""
echo "=== Creating Phase 5 (Peripheral) ==="

E51=$(create_task "Epic 5.1: Canvas/TUI/Terminal" "Canvas host, TUI framework, terminal sessions. ~25 test specs." 2 epic)
echo "Epic 5.1: $E51"

create_task "Canvas host — present/hide/eval/snapshot" "Canvas rendering surface for UI output." 2 task "$E51"
create_task "TUI framework — terminal UI rendering" "Terminal-based UI components and rendering." 2 task "$E51"
create_task "Terminal session management" "Terminal session lifecycle, input/output handling." 2 task "$E51"

E52=$(create_task "Epic 5.2: i18n" "Internationalization — string tables, locale detection. ~1 test spec." 2 epic)
echo "Epic 5.2: $E52"

create_task "i18n framework — string tables & locale detection" "Internationalization support with locale-aware string resolution." 2 task "$E52"

E53=$(create_task "Epic 5.3: Node Pairing" "Node discovery, pairing, device control. ~4 test specs." 2 epic)
echo "Epic 5.3: $E53"

create_task "Node pairing — discovery & device control" "Node discovery protocol, pairing handshake, camera/screen/location control." 2 task "$E53"

E54=$(create_task "Epic 5.4: TTS Integration" "TTS engine abstraction, voice selection, audio delivery. ~2 test specs." 2 epic)
echo "Epic 5.4: $E54"

create_task "TTS engine abstraction & voice selection" "TTS provider abstraction, voice catalog, audio format selection." 2 task "$E54"

E55=$(create_task "Epic 5.5: Wizard" "Setup/migration wizard — interactive config flow. ~7 test specs." 2 epic)
echo "Epic 5.5: $E55"

create_task "Setup wizard — interactive configuration" "Guided setup flow for first-run configuration." 2 task "$E55"
create_task "Migration wizard — config format upgrades" "Automated config migration between versions." 2 task "$E55"

E56=$(create_task "Epic 5.6: Shared Utilities" "Shared utility functions used across domains. ~13 test specs." 2 epic)
echo "Epic 5.6: $E56"

create_task "Shared utility functions" "Common utilities: string manipulation, date handling, type coercion, etc." 2 task "$E56"

echo ""
echo "=== Creating Phase 6 (Testing) ==="

E61=$(create_task "Epic 6.1: Spec Test Adaptation" "Convert remaining ~1,300 spec test files into runnable FiveAM suites." 1 epic)
echo "Epic 6.1: $E61"

create_task "Adapt gateway domain tests (131 specs)" "Convert gateway test specifications to FiveAM test suites." 1 task "$E61"
create_task "Adapt agents domain tests (401 specs)" "Convert agents test specifications to FiveAM — largest domain." 1 task "$E61"
create_task "Adapt CLI domain tests (100 specs)" "Convert CLI test specifications to FiveAM." 1 task "$E61"
create_task "Adapt commands domain tests (127 specs)" "Convert commands test specifications to FiveAM." 1 task "$E61"
create_task "Adapt auto-reply domain tests (87 specs)" "Convert auto-reply test specifications to FiveAM." 1 task "$E61"
create_task "Adapt config domain tests (92 specs)" "Convert config test specifications to FiveAM." 1 task "$E61"
create_task "Adapt Discord domain tests (73 specs)" "Convert Discord test specifications to FiveAM." 1 task "$E61"
create_task "Adapt Telegram domain tests (62 specs)" "Convert Telegram test specifications to FiveAM." 1 task "$E61"
create_task "Adapt cron domain tests (60 specs)" "Convert cron test specifications to FiveAM." 1 task "$E61"
create_task "Adapt browser domain tests (56 specs)" "Convert browser test specifications to FiveAM." 1 task "$E61"
create_task "Adapt Slack domain tests (49 specs)" "Convert Slack test specifications to FiveAM." 1 task "$E61"
create_task "Adapt remaining domain tests" "Convert all other domain test specifications to FiveAM (channels, memory, media, hooks, plugins, etc)." 1 task "$E61"

E62=$(create_task "Epic 6.2: Integration & E2E Tests" "End-to-end tests proving the pieces work together." 1 epic)
echo "Epic 6.2: $E62"

create_task "E2E: Gateway boot → channel → message round-trip" "Full integration test: gateway starts, channel connects, message flows through." 1 task "$E62"
create_task "E2E: Provider call → streaming → tool → response" "Integration test: LLM call, streaming response, tool dispatch, final answer." 1 task "$E62"
create_task "E2E: ACP spawn → sub-agent → result relay" "Integration test: sub-agent spawning, turn execution, result relay to parent." 1 task "$E62"
create_task "E2E: Multi-channel concurrent operation" "Integration test: multiple channels receiving/sending simultaneously." 1 task "$E62"
create_task "E2E: Crash recovery & reconnection" "Integration test: process crash, state recovery, channel reconnection." 1 task "$E62"

# Add cross-phase dependencies
bd dep add "$P1" "$E02" 2>/dev/null || true
bd dep add "$E21" "$E02" 2>/dev/null || true
bd dep add "$E22" "$E21" 2>/dev/null || true
bd dep add "$E31" "$E02" 2>/dev/null || true
bd dep add "$E33" "$E32" 2>/dev/null || true
bd dep add "$E41" "$E02" 2>/dev/null || true

echo ""
echo "=== Done! ==="
echo "Created all roadmap beads."
