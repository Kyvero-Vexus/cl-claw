# cl-claw Roadmap: Full OpenClaw Compatibility

**Generated:** 2026-03-09
**Status:** Active
**Spec Source:** `specs/cl-adapted/test-specs-by-domain.common-lisp.md` (1,862 test spec files across ~55 domains)

## Current State

- **58 source files**, ~7,600 LOC across 22 modules
- **592 unit test checks** pass (FiveAM)
- Covers: infra, process, config, logging, secrets, sessions, routing, providers, memory, security, agents, cli, commands, daemon, markdown, hooks, media, plugins, browser, cron
- What exists: well-typed utility library of building blocks
- What's missing: everything needed to actually RUN as an OpenClaw-compatible gateway

## Architecture Principles

1. **Static typing everywhere** — SBCL strict type declarations; Coalton for new core modules
2. **Behavioral parity** — no simplification, no scope reduction per `runtime-adaptation-spec.md`
3. **CL library substitutions** — Dexador, JZON/YASON, Ironclad, Bordeaux-Threads, UIOP
4. **External helpers only where needed** — browser automation may use CDP helper

---

## Phase 0: Foundation & HTTP Stack (P0 — Critical Path)

### Epic 0.1: HTTP Server & WebSocket Core
Build the HTTP/WS server that everything else plugs into.
- **0.1.1** Hunchentoot/Woo HTTP server setup with TLS support (~131 gateway test specs)
- **0.1.2** WebSocket server (hunchensocket or custom) for gateway control protocol
- **0.1.3** Gateway auth layer — token/password modes, rate limiting, trusted-proxy support
- **0.1.4** Server startup/shutdown lifecycle, graceful drain
- **0.1.5** Health check endpoints, server discovery

### Epic 0.2: Gateway Core Runner
The main orchestration loop that ties everything together.
- **0.2.1** Gateway boot sequence (`runBootOnce`, BOOT.md processing)
- **0.2.2** Session orchestration — create/resume/route sessions via WS
- **0.2.3** Gateway call infrastructure (`callGateway`, URL resolution, credential flow)
- **0.2.4** Channel health monitor — startup grace, reconnection logic
- **0.2.5** Heartbeat/keepalive system for gateway connections
- **0.2.6** Gateway configuration resolution (env vars, config files, SecretRefs)
- **0.2.7** Multi-account gateway support
- **0.2.8** Gateway server tools catalog & dispatch

### Epic 0.3: Provider HTTP Layer
Actual LLM API calls with streaming.
- **0.3.1** HTTP client abstraction (Dexador) with SSE streaming support
- **0.3.2** Anthropic API provider — messages endpoint, streaming, tool use
- **0.3.3** OpenAI API provider — chat completions, streaming, function calling
- **0.3.4** OpenRouter provider — routing, model selection, fallback
- **0.3.5** Provider auth profiles — OAuth, API key, cooldown, rotation (~40+ agent auth test files)
- **0.3.6** Provider failover & round-robin logic
- **0.3.7** Token counting & budget enforcement
- **0.3.8** Provider-specific quirks (Gemini, Groq, DeepSeek, Chutes, etc.)

### Epic 0.4: Context Engine
Prompt assembly and token management.
- **0.4.1** Context engine core — prompt assembly from system/user/tool messages
- **0.4.2** Token budget system — counting, trimming, compaction triggers
- **0.4.3** Workspace file injection (SOUL.md, AGENTS.md, etc.)
- **0.4.4** Session history assembly with token-aware truncation
- **0.4.5** Agent prompt construction & identity resolution

### Epic 0.5: Tool Execution Framework
Tool dispatch for all gateway tools.
- **0.5.1** Tool dispatch core — registry, parameter validation, permission checking
- **0.5.2** Exec tool — shell command execution with PTY, timeout, backgrounding
- **0.5.3** Read/Write/Edit tools — file operations with path security
- **0.5.4** Browser tool — CDP integration, snapshot, navigate, act
- **0.5.5** Image/PDF analysis tools — vision model dispatch
- **0.5.6** Web fetch/search tools — HTTP fetch, search integration
- **0.5.7** TTS tool — text-to-speech dispatch
- **0.5.8** Message/canvas/node tools — channel actions, canvas control
- **0.5.9** Tool approval/permission system (ask modes, allowlists)
- **0.5.10** Tool invoke HTTP — remote tool invocation

---

## Phase 1: Channel Implementations (P0 — Critical Path)

### Epic 1.1: Channel Protocol Core
Shared channel infrastructure.
- **1.1.1** Channel lifecycle — connect, disconnect, reconnect, health reporting
- **1.1.2** Inbound message normalization — text, media, attachments
- **1.1.3** Outbound message formatting — markdown adaptation per channel
- **1.1.4** Channel account management — multi-account, per-channel config
- **1.1.5** Channel-specific rate limiting and queue management

### Epic 1.2: Telegram Channel (~62 test specs)
- **1.2.1** Telegram Bot API client — polling/webhook modes
- **1.2.2** Telegram message handling — text, media, stickers, reactions
- **1.2.3** Telegram groups/topics — forum topic support, thread routing
- **1.2.4** Telegram inline queries, callbacks, commands
- **1.2.5** Telegram media upload/download
- **1.2.6** Telegram polls, effects, voice messages

### Epic 1.3: Discord Channel (~73 test specs)
- **1.3.1** Discord gateway (WebSocket) client — connect, resume, heartbeat
- **1.3.2** Discord REST API client — messages, threads, reactions
- **1.3.3** Discord thread management — create, archive, ACP bindings
- **1.3.4** Discord slash commands, interactions, components
- **1.3.5** Discord media/attachments, embeds
- **1.3.6** Discord presence, activity status
- **1.3.7** Discord voice channel support (if applicable)

### Epic 1.4: IRC Channel
- **1.4.1** IRC client — connect, auth (NickServ), join/part
- **1.4.2** IRC message handling — PRIVMSG, NOTICE, CTCP
- **1.4.3** IRC reconnection & resilience

### Epic 1.5: Signal Channel (~13 test specs)
- **1.5.1** Signal CLI/daemon integration
- **1.5.2** Signal message handling — text, media, reactions, groups
- **1.5.3** Signal attachment handling

### Epic 1.6: Slack Channel (~49 test specs)
- **1.6.1** Slack Web API + Events API client
- **1.6.2** Slack Socket Mode for real-time events
- **1.6.3** Slack message formatting (blocks, mrkdwn)
- **1.6.4** Slack threads, reactions, file uploads
- **1.6.5** Slack app configuration & OAuth

### Epic 1.7: WhatsApp Channel (~2 test specs + web tests)
- **1.7.1** WhatsApp Web/Business API integration
- **1.7.2** WhatsApp message handling — text, media, status
- **1.7.3** WhatsApp auth flow (QR code, session persistence)

### Epic 1.8: iMessage Channel (~12 test specs)
- **1.8.1** iMessage bridge (AppleScript/BlueBubbles/alternative)
- **1.8.2** iMessage send/receive, attachments, reactions

### Epic 1.9: Line Channel (~18 test specs)
- **1.9.1** Line Messaging API client
- **1.9.2** Line message types, rich menus, flex messages

---

## Phase 2: ACP & Agent Orchestration (P0 — Critical Path)

### Epic 2.1: ACP Core (~15 test specs)
Sub-agent control plane.
- **2.1.1** ACP client — spawn env resolution, invocation handling
- **2.1.2** ACP session manager — concurrent turns, max sessions, eviction
- **2.1.3** ACP runtime cache — idle tracking, handle reuse
- **2.1.4** ACP persistent bindings — channel-specific session binding
- **2.1.5** ACP policy — enable/disable, allowlist filtering
- **2.1.6** ACP server startup — gateway hello, credential passing
- **2.1.7** ACP session mapper — label/key resolution
- **2.1.8** ACP translator — prompt prefix, session rate limits
- **2.1.9** ACP runtime registry — backend management, health checks
- **2.1.10** ACP secret file reader — size limits, symlink rejection

### Epic 2.2: Agent System (~401 test specs)
Agent configuration, auth, tools, and lifecycle.
- **2.2.1** Agent config resolution — paths, scope, model selection
- **2.2.2** Agent auth profiles — OAuth, API key, cooldown, rotation, migration
- **2.2.3** Agent bash tools — exec, approval, Docker integration
- **2.2.4** Agent patch application — file add/update/move with path security
- **2.2.5** Agent sandbox — bind specs, Docker exec, workspace isolation
- **2.2.6** Agent spawn — ACP direct spawn, thread binding, stream relay
- **2.2.7** Agent anthropic payload logging
- **2.2.8** Agent identity & model resolution

---

## Phase 3: Web Layer & API (P1 — Important)

### Epic 3.1: Web Server (~30 test specs)
Webchat and API endpoints.
- **3.1.1** Web server setup — routes, static files, CORS
- **3.1.2** Webchat interface — inbound/outbound message flow
- **3.1.3** Account management API — create, list, auth
- **3.1.4** Monitor inbox — streaming inbound messages, media capture
- **3.1.5** Web auto-reply — compression, rate limiting
- **3.1.6** Web reconnection & session persistence
- **3.1.7** Send API — external message injection
- **3.1.8** Logout & session cleanup

### Epic 3.2: CLI System (~100 test specs)
Command-line interface for gateway management.
- **3.2.1** CLI argument parsing & command routing
- **3.2.2** CLI install spec resolution
- **3.2.3** CLI auth management commands
- **3.2.4** CLI gateway control (start/stop/status)
- **3.2.5** CLI channel management
- **3.2.6** CLI JSON stdout mode for programmatic use

### Epic 3.3: Commands (~127 test specs)
Gateway command implementations.
- **3.3.1** Session commands — send, list, history
- **3.3.2** Config commands — get, set, validate
- **3.3.3** Agent commands — list, configure, spawn
- **3.3.4** Tool commands — catalog, invoke
- **3.3.5** Admin commands — health, debug, migrate

---

## Phase 4: Supporting Systems (P1 — Important)

### Epic 4.1: Auto-Reply (~87 test specs)
- **4.1.1** Auto-reply trigger matching — patterns, schedules, conditions
- **4.1.2** Auto-reply response generation — templates, LLM dispatch
- **4.1.3** Auto-reply rate limiting & cooldown
- **4.1.4** Auto-reply per-channel configuration
- **4.1.5** Auto-reply media handling (compression, format conversion)

### Epic 4.2: Cron & Scheduling (~60 test specs)
- **4.2.1** Cron expression parser & scheduler
- **4.2.2** Cron job lifecycle — create, update, delete, list
- **4.2.3** Cron job execution — agent dispatch, error handling
- **4.2.4** Cron persistence & recovery after restart

### Epic 4.3: Memory System (~37 test specs)
- **4.3.1** Memory store — CRUD operations, search
- **4.3.2** Memory indexing & retrieval
- **4.3.3** Memory compaction & cleanup
- **4.3.4** Memory integration with context engine

### Epic 4.4: Hooks & Plugins (~19 + 34 + 24 test specs)
- **4.4.1** Hook system — registration, dispatch, lifecycle
- **4.4.2** Plugin SDK — API surface, versioning, isolation
- **4.4.3** Plugin loading & management
- **4.4.4** Built-in plugins — media, browser extensions

### Epic 4.5: Browser Automation (~56 test specs)
- **4.5.1** Chrome DevTools Protocol client in CL
- **4.5.2** Browser snapshot — accessibility tree extraction
- **4.5.3** Browser actions — click, type, navigate, screenshot
- **4.5.4** Browser profile management
- **4.5.5** Browser tab lifecycle

### Epic 4.6: Media & Link Understanding (~17 + 23 + 1 test specs)
- **4.6.1** Media type detection & validation
- **4.6.2** Media download/upload pipeline
- **4.6.3** Link preview extraction
- **4.6.4** Media understanding — image/video analysis dispatch

---

## Phase 5: Peripheral Systems (P2 — Nice to Have)

### Epic 5.1: Canvas/TUI/Terminal (~2 + 17 + 6 test specs)
- **5.1.1** Canvas host — present/hide/eval/snapshot
- **5.1.2** TUI framework — terminal UI rendering
- **5.1.3** Terminal session management

### Epic 5.2: i18n (~1 test spec)
- **5.2.1** Internationalization framework — string tables, locale detection

### Epic 5.3: Node Pairing (~4 test specs)
- **5.3.1** Node discovery & pairing protocol
- **5.3.2** Node device control — camera, screen, location

### Epic 5.4: TTS Integration (~2 test specs)
- **5.4.1** TTS engine abstraction
- **5.4.2** Voice selection & audio delivery

### Epic 5.5: Wizard (~7 test specs)
- **5.5.1** Setup wizard — interactive configuration flow
- **5.5.2** Migration wizard — config format upgrades

### Epic 5.6: Shared Utilities (~13 test specs)
- **5.6.1** Shared utility functions (used across domains)

---

## Phase 6: Test Coverage (P1 — Ongoing)

### Epic 6.1: Spec Test Adaptation
Convert remaining ~1,300 spec test files into runnable FiveAM suites.
- **6.1.1** Gateway domain tests (131 specs)
- **6.1.2** Agents domain tests (401 specs — largest)
- **6.1.3** CLI domain tests (100 specs)
- **6.1.4** Commands domain tests (127 specs)
- **6.1.5** Auto-reply domain tests (87 specs)
- **6.1.6** Config domain tests (92 specs)
- **6.1.7** Discord domain tests (73 specs)
- **6.1.8** Telegram domain tests (62 specs)
- **6.1.9** Cron domain tests (60 specs)
- **6.1.10** Browser domain tests (56 specs)
- **6.1.11** Slack domain tests (49 specs)
- **6.1.12** Channels domain tests (66 specs)
- **6.1.13** Remaining domain tests (all others)

### Epic 6.2: Integration & E2E Tests
- **6.2.1** Gateway startup → channel connect → message round-trip
- **6.2.2** Provider call → streaming → tool dispatch → response
- **6.2.3** ACP spawn → sub-agent turn → result relay
- **6.2.4** Multi-channel concurrent operation test
- **6.2.5** Crash recovery & reconnection tests

---

## Dependency Graph

```
Phase 0 (Foundation)
  ├── 0.1 HTTP/WS Server ──────┐
  ├── 0.3 Provider HTTP ────────┤
  │                             ▼
  ├── 0.2 Gateway Runner ◄─── (needs 0.1, 0.3, 0.4, 0.5)
  ├── 0.4 Context Engine ◄─── (needs 0.3 for token counting)
  └── 0.5 Tool Framework ◄─── (needs 0.1 for exec/browser)

Phase 1 (Channels) ◄── Phase 0 (all channels need gateway runner)
  ├── 1.1 Channel Core ────────┐
  ├── 1.2 Telegram ◄───────────┤
  ├── 1.3 Discord ◄────────────┤
  ├── 1.4 IRC ◄────────────────┤
  ├── 1.5 Signal ◄─────────────┤
  ├── 1.6 Slack ◄──────────────┤
  ├── 1.7 WhatsApp ◄───────────┤
  ├── 1.8 iMessage ◄───────────┤
  └── 1.9 Line ◄───────────────┘

Phase 2 (ACP) ◄── Phase 0 (needs gateway, providers, tools)

Phase 3 (Web/CLI/Commands) ◄── Phase 0 + Phase 1

Phase 4 (Supporting) ◄── Phase 0 (partial), can start after 0.1-0.3

Phase 5 (Peripheral) ◄── Phase 0 + Phase 4

Phase 6 (Tests) — runs in parallel with all phases
```

## Milestones

| Milestone | Target | Description |
|-----------|--------|-------------|
| M0 | Phase 0 complete | Gateway boots, accepts WS, calls LLM, dispatches tools |
| M1 | First channel works | One channel (Telegram or IRC) end-to-end |
| M2 | ACP works | Sub-agent spawn and turn completion |
| M3 | Multi-channel | 3+ channels operational |
| M4 | Feature parity | All channels, auto-reply, cron, memory, plugins |
| M5 | Test parity | 1,800+ spec tests passing |
| M6 | Production ready | E2E tests, crash recovery, performance validated |

## Estimated Scope

- **Total spec test files:** 1,862
- **Currently passing:** 592 checks (in existing domains)
- **Domains with code:** 22
- **Domains needing implementation:** ~33 additional
- **Estimated sessions to completion:** 80-120 (at 1-2 sessions per subtask)
