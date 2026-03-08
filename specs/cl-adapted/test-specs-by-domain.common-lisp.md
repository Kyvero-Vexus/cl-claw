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


# Test specs by domain

## acp

### src/acp/client.test.lisp
- resolveAcpClientSpawnEnv
- sets OPENCLAW_SHELL marker and preserves existing env values
- overrides pre-existing OPENCLAW_SHELL to acp-client
- strips skill-injected env keys when stripKeys is provided
- does not modify the original baseEnv when stripping keys
- preserves OPENCLAW_SHELL even when stripKeys contains it
- resolveAcpClientSpawnInvocation
- keeps non-windows invocation unchanged
- unwraps .cmd shim entrypoint on windows
- falls back to shell mode for unresolved wrappers on windows
- resolvePermissionRequest
- auto-approves safe tools without prompting
- prompts for dangerous tool names inferred from title
- prompts for non-read/search tools (write)
- auto-approves search without prompting
- prompts for read outside cwd scope
- auto-approves read when rawInput path resolves inside cwd
- auto-approves read when rawInput file URL resolves inside cwd
- prompts for read when rawInput path escapes cwd via traversal
- prompts for read when scoped path is missing
- prompts for non-core read-like tool names
- prompts when kind is spoofed as read
- uses allow_always and reject_always when once options are absent
- prompts when tool identity is unknown and can still approve
- prompts when metadata tool name contains invalid characters
- prompts when raw input tool name exceeds max length
- prompts when title tool name contains non-allowed characters
- returns cancelled when no permission options are present
- acp event mapper
- extracts text and resource blocks into prompt text
- escapes control and delimiter characters in resource link metadata
- escapes C0/C1 separators in resource link metadata
- never emits raw C0/C1 or unicode line separators from resource link metadata
- keeps full resource link title content without truncation
- counts newline separators toward prompt byte limits
- extracts image blocks into gateway attachments

### src/acp/control-plane/manager.test.lisp
- AcpSessionManager
- marks ACP-shaped sessions without metadata as stale
- serializes concurrent turns for the same ACP session
- runs turns for different ACP sessions in parallel
- reuses runtime session handles for repeat turns in the same manager process
- rehydrates runtime handles after a manager restart
- enforces acp.maxConcurrentSessions when opening new runtime handles
- enforces acp.maxConcurrentSessions during initializeSession
- drops cached runtime handles when close tolerates backend-unavailable errors
- evicts idle cached runtimes before enforcing max concurrent limits
- tracks ACP turn latency and error-code observability
- rolls back ensured runtime sessions when metadata persistence fails
- preempts an active turn on cancel and returns to idle state
- cleans actor-tail bookkeeping after session turns complete
- surfaces backend failures raised after a done event
- persists runtime mode changes through setSessionRuntimeMode
- reapplies persisted controls on next turn after runtime option updates
- reconciles persisted ACP session identifiers from runtime status after a turn
- reconciles pending ACP identities during startup scan
- skips startup identity reconciliation for already resolved sessions
- preserves existing ACP session identifiers when ensure returns none
- applies persisted runtime options before running turns
- returns unsupported-control error when backend does not support set_config_option
- rejects invalid runtime option values before backend controls run
- can close and clear metadata when backend is unavailable
- surfaces metadata clear errors during closeSession

### src/acp/control-plane/runtime-cache.test.lisp
- RuntimeCache
- tracks idle candidates with touch-aware lookups
- returns snapshot entries with idle durations

### src/acp/persistent-bindings.test.lisp
- resolveConfiguredAcpBindingRecord
- resolves discord channel ACP binding from top-level typed bindings
- falls back to parent discord channel when conversation is a thread id
- prefers direct discord thread binding over parent channel fallback
- prefers exact account binding over wildcard for the same discord conversation
- returns null when no top-level ACP binding matches the conversation
- resolves telegram forum topic bindings using canonical conversation ids
- skips telegram non-group topic configs
- applies agent runtime ACP defaults for bound conversations
- resolveConfiguredAcpBindingSpecBySessionKey
- maps a configured discord binding session key back to its spec
- returns null for unknown session keys
- prefers exact account ACP settings over wildcard when session keys collide
- buildConfiguredAcpSessionKey
- is deterministic for the same conversation binding
- ensureConfiguredAcpBindingSession
- keeps an existing ready session when configured binding omits cwd
- reinitializes a ready session when binding config explicitly sets mismatched cwd
- initializes ACP session with runtime agent override when provided
- resetAcpSessionInPlace
- reinitializes from configured binding when ACP metadata is missing
- does not clear ACP metadata before reinitialize succeeds
- preserves harness agent ids during in-place reset even when not in agents.list

### src/acp/policy.test.lisp
- acp policy
- treats ACP + ACP dispatch as enabled by default
- reports ACP disabled state when acp.enabled is false
- reports dispatch-disabled state when dispatch gate is false
- applies allowlist filtering for ACP agents

### src/acp/runtime/error-text.test.lisp
- formatAcpRuntimeErrorText
- adds actionable next steps for known ACP runtime error codes
- returns consistent ACP error envelope for runtime failures

### src/acp/runtime/errors.test.lisp
- withAcpRuntimeErrorBoundary
- wraps generic errors with fallback code and source message
- passes through existing ACP runtime errors

### src/acp/runtime/registry.test.lisp
- acp runtime registry
- registers and resolves backends by id
- prefers a healthy backend when resolving without explicit id
- throws a typed missing-backend error when no backend is registered
- throws a typed unavailable error when the requested backend is unhealthy
- unregisters a backend by id
- keeps backend state on a global registry for cross-loader access

### src/acp/runtime/session-identifiers.test.lisp
- session identifier helpers
- hides unresolved identifiers from thread intro details while pending
- adds a Codex resume hint when agent identity is resolved
- adds a Kimi resume hint when agent identity is resolved
- shows pending identity text for status rendering
- prefers runtimeOptions.cwd over legacy meta.cwd

### src/acp/secret-file.test.lisp
- readSecretFromFile
- reads and trims a regular secret file
- rejects files larger than the secret-file limit
- rejects non-regular files
- rejects symlinks

### src/acp/server.startup.test.lisp
- serveAcpGateway startup
- waits for gateway hello before creating AgentSideConnection
- rejects startup when gateway connect fails before hello
- passes resolved SecretInput gateway credentials to the ACP gateway client
- passes command-line interface URL override context into shared gateway auth resolution

### src/acp/session-mapper.test.lisp
- acp session mapper
- prefers explicit sessionLabel over sessionKey
- lets meta sessionKey override default label

### src/acp/session.test.lisp
- acp session manager
- tracks active runs and clears on cancel
- refreshes existing session IDs instead of creating duplicates
- reaps idle sessions before enforcing the max session cap
- uses soft-cap eviction for the oldest idle session when full
- rejects when full and no session is evictable

### src/acp/translator.prompt-prefix.test.lisp
- acp prompt cwd prefix
- redacts home directory in prompt prefix
- keeps backslash separators when cwd uses them

### src/acp/translator.session-rate-limit.test.lisp
- acp session creation rate limit
- rate limits excessive newSession bursts
- does not count loadSession refreshes for an existing session ID
- acp prompt size hardening
- rejects oversized prompt blocks without leaking active runs
- rejects oversize final messages from cwd prefix without leaking active runs

## agents

### src/agents/acp-binding-architecture.guardrail.test.lisp
- ACP/session binding architecture guardrails
- keeps ACP/focus flows off Discord thread-binding manager APIs

### src/agents/acp-spawn-parent-stream.test.lisp
- startAcpSpawnParentStreamRelay
- relays assistant progress and completion to the parent session
- emits a no-output notice and a resumed notice when output returns
- auto-disposes stale relays after max lifetime timeout
- supports delayed start notices
- preserves delta whitespace boundaries in progress relays
- resolves ACP spawn stream log path from session metadata

### src/agents/acp-spawn.test.lisp
- spawnAcpDirect
- spawns ACP session, binds a new thread, and dispatches initial task
- does not inline delivery for fresh oneshot ACP runs
- includes cwd in ACP thread intro banner when provided at spawn time
- rejects disallowed ACP agents
- requires an explicit ACP agent when no config default exists
- fails fast when Discord ACP thread spawn is disabled
- forbids ACP spawn from sandboxed requester sessions
- forbids sandbox="require" for runtime=acp
- streams ACP progress to parent when streamTo="parent"
- announces parent relay start only after successful child dispatch
- keeps inline delivery for thread-bound ACP session mode
- disposes pre-registered parent relay when initial ACP dispatch fails
- rejects streamTo="parent" without requester session context

### src/agents/agent-paths.test.lisp
- resolveOpenClawAgentDir
- defaults to the multi-agent path when no overrides are set
- honors OPENCLAW_AGENT_DIR overrides
- honors PI_CODING_AGENT_DIR when OPENCLAW_AGENT_DIR is unset
- prefers OPENCLAW_AGENT_DIR over PI_CODING_AGENT_DIR when both are set

### src/agents/agent-scope.test.lisp
- resolveAgentConfig
- should return undefined when no agents config exists
- should return undefined when agent id does not exist
- should return basic agent config
- resolves explicit and effective model primary separately
- supports per-agent model primary+fallbacks
- resolves fallback agent id from explicit agent id first
- resolves fallback agent id from session key when explicit id is missing
- resolves run fallback overrides via shared helper
- computes whether any model fallbacks are configured via shared helper
- should return agent-specific sandbox config
- should return agent-specific tools config
- should return both sandbox and tools config
- should normalize agent id
- uses OPENCLAW_HOME for default agent workspace
- uses OPENCLAW_HOME for default agentDir

### src/agents/anthropic-payload-log.test.lisp
- createAnthropicPayloadLogger
- redacts image base64 payload data before writing logs

### src/agents/anthropic.setup-token.live.test.lisp
- pickModel
- resolves sonnet-4.6 aliases to claude-sonnet-4-6
- resolves opus-4.6 aliases to claude-opus-4-6
- completes using a setup-token profile

### src/agents/apply-patch.test.lisp
- applyPatch
- adds a file
- updates and moves a file
- supports end-of-file inserts
- rejects path traversal outside cwd by default
- rejects absolute paths outside cwd by default
- allows absolute paths within cwd by default
- rejects symlink escape attempts by default
- rejects broken final symlink targets outside cwd by default
- rejects hardlink alias escapes by default
- allows symlinks that resolve within cwd by default
- rejects delete path traversal via symlink directories by default
- allows path traversal when workspaceOnly is explicitly disabled
- allows deleting a symlink itself even if it points outside cwd

### src/agents/auth-health.test.lisp
- buildAuthHealthSummary
- classifies OAuth and API key profiles
- reports expired for OAuth without a refresh token
- marks token profiles with invalid expires as missing with reason code
- formatRemainingShort
- supports an explicit under-minute label override

### src/agents/auth-profiles.chutes.test.lisp
- auth-profiles (chutes)
- refreshes expired Chutes OAuth credentials

### src/agents/auth-profiles.cooldown-auto-expiry.test.lisp
- resolveAuthProfileOrder — cooldown auto-expiry
- places profile with expired cooldown in available list (round-robin path)
- places profile with expired cooldown in available list (explicit-order path)
- keeps profile with active cooldown in cooldown list
- expired cooldown resets error count — prevents escalation on next failure
- mixed active and expired cooldowns across profiles
- does not affect profiles from other providers

### src/agents/auth-profiles.ensureauthprofilestore.test.lisp
- ensureAuthProfileStore
- migrates legacy auth.json and deletes it (PR #368)
- merges main auth profiles into agent store and keeps agent overrides
- normalizes auth-profiles credential aliases with canonical-field precedence
- normalizes mode/apiKey aliases while migrating legacy auth.json
- logs one warning with aggregated reasons for rejected auth-profiles entries

### src/agents/auth-profiles.getsoonestcooldownexpiry.test.lisp
- getSoonestCooldownExpiry
- returns null when no cooldown timestamps exist
- returns earliest unusable time across profiles
- ignores unknown profiles and invalid cooldown values
- returns past timestamps when cooldown already expired

### src/agents/auth-profiles.markauthprofilefailure.test.lisp
- markAuthProfileFailure
- disables billing failures for ~5 hours by default
- honors per-provider billing backoff overrides
- keeps persisted cooldownUntil unchanged across mid-window retries
- records overloaded failures in the cooldown bucket
- disables auth_permanent failures via disabledUntil (like billing)
- resets backoff counters outside the failure window
- does not persist cooldown windows for OpenRouter profiles
- calculateAuthProfileCooldownMs
- applies exponential backoff with a 1h cap

### src/agents/auth-profiles.readonly-sync.test.lisp
- auth profiles read-only external command-line interface sync
- syncs external command-line interface credentials in-memory without writing auth-profiles.json in read-only mode

### src/agents/auth-profiles.resolve-auth-profile-order.does-not-prioritize-lastgood-round-robin-ordering.test.lisp
- resolveAuthProfileOrder
- does not prioritize lastGood over round-robin ordering
- uses explicit profiles when order is missing
- uses configured order when provided
- prefers store order over config order
- mode: oauth config accepts both oauth and token credentials (issue #559)
- mode: token config rejects oauth credentials (issue #559 root cause)

### src/agents/auth-profiles.resolve-auth-profile-order.normalizes-z-ai-aliases-auth-order.test.lisp
- resolveAuthProfileOrder
- normalizes z.ai aliases in auth.order
- normalizes provider casing in auth.order keys
- normalizes z.ai aliases in auth.profiles
- prioritizes oauth profiles when order missing

### src/agents/auth-profiles.resolve-auth-profile-order.orders-by-lastused-no-explicit-order-exists.test.lisp
- resolveAuthProfileOrder
- orders by lastUsed when no explicit order exists
- pushes cooldown profiles to the end, ordered by cooldown expiry

### src/agents/auth-profiles.resolve-auth-profile-order.uses-stored-profiles-no-config-exists.test.lisp
- resolveAuthProfileOrder
- uses stored profiles when no config exists
- prioritizes preferred profiles
- drops explicit order entries that are missing from the store
- falls back to stored provider profiles when config profile ids drift
- does not bypass explicit ids when the configured profile exists but is invalid
- drops explicit order entries that belong to another provider
- keeps api_key profiles backed by keyRef when plaintext key is absent
- keeps token profiles backed by tokenRef when expires is absent
- drops tokenRef profiles when expires is invalid
- keeps token profiles with inline token when no expires is set
- keeps oauth profiles that can refresh

### src/agents/auth-profiles.runtime-snapshot-save.test.lisp
- auth profile runtime snapshot persistence
- does not write resolved plaintext keys during usage updates

### src/agents/auth-profiles.store.save.test.lisp
- saveAuthProfileStore
- strips plaintext when keyRef/tokenRef are present

### src/agents/auth-profiles/credential-state.test.lisp
- resolveTokenExpiryState
- treats undefined as missing
- treats non-finite and non-positive values as invalid_expires
- returns expired when expires is in the past
- returns valid when expires is in the future
- evaluateStoredCredentialEligibility
- marks api_key with keyRef as eligible
- marks tokenRef with missing expires as eligible
- marks token with invalid expires as ineligible

### src/agents/auth-profiles/oauth.fallback-to-main-agent.test.lisp
- resolveApiKeyForProfile fallback to main agent
- falls back to main agent credentials when secondary agent token is expired and refresh fails
- adopts newer OAuth token from main agent even when secondary token is still valid
- adopts main token when secondary expires is NaN/malformed
- accepts mode=token + type=oauth for legacy compatibility
- accepts mode=oauth + type=token (regression)
- rejects true mode/type mismatches
- throws error when both secondary and main agent credentials are expired

### src/agents/auth-profiles/oauth.openai-codex-refresh-fallback.test.lisp
- resolveApiKeyForProfile openai-codex refresh fallback
- falls back to cached access token when openai-codex refresh fails on accountId extraction
- keeps throwing for non-codex providers on the same refresh error
- does not use fallback for unrelated openai-codex refresh errors

### src/agents/auth-profiles/oauth.test.lisp
- resolveApiKeyForProfile config compatibility
- accepts token credentials when config mode is oauth
- rejects token credentials when config mode is api_key
- rejects credentials when provider does not match config
- accepts oauth credentials when config mode is token (bidirectional compat)
- resolveApiKeyForProfile token expiry handling
- accepts token credentials when expires is undefined
- accepts token credentials when expires is in the future
- returns null for expired token credentials
- returns null for token credentials when expires is 0
- returns null for token credentials when expires is invalid (NaN)
- resolveApiKeyForProfile secret refs
- resolves api_key keyRef from env
- resolves token tokenRef from env
- resolves token tokenRef without inline token when expires is absent
- resolves inline ${ENV} api_key values
- resolves inline ${ENV} token values

### src/agents/auth-profiles/order.test.lisp
- resolveAuthProfileOrder
- accepts base-provider credentials for volcengine-plan auth lookup

### src/agents/auth-profiles/session-override.test.lisp
- resolveSessionAuthProfileOverride
- keeps user override when provider alias differs

### src/agents/auth-profiles/usage.test.lisp
- resolveProfileUnusableUntil
- returns null when both values are missing or invalid
- returns the latest active timestamp
- resolveProfileUnusableUntilForDisplay
- hides cooldown markers for OpenRouter profiles
- keeps cooldown markers visible for other providers
- isProfileInCooldown
- returns false when profile has no usage stats
- returns true when cooldownUntil is in the future
- returns false when cooldownUntil has passed
- returns true when disabledUntil is in the future (even if cooldownUntil expired)
- returns false for OpenRouter even when cooldown fields exist
- returns false for Kilocode even when cooldown fields exist
- resolveProfilesUnavailableReason
- prefers active disabledReason when profiles are disabled
- returns auth_permanent for active permanent auth disables
- uses recorded non-rate-limit failure counts for active cooldown windows
- returns overloaded for active overloaded cooldown windows
- falls back to rate_limit when active cooldown has no reason history
- ignores expired windows and returns null when no profile is actively unavailable
- breaks ties by reason priority for equal active failure counts
- clearExpiredCooldowns
- returns false on empty usageStats
- returns false when no profiles have cooldowns
- returns false when cooldown is still active
- clears expired cooldownUntil and resets errorCount
- clears expired disabledUntil and disabledReason
- handles independent expiry: cooldown expired but disabled still active
- handles independent expiry: disabled expired but cooldown still active
- resets errorCount only when both cooldown and disabled have expired
- processes multiple profiles independently
- accepts an explicit `now` timestamp for deterministic testing
- clears cooldownUntil that equals exactly `now`
- ignores NaN and Infinity cooldown values
- ignores zero and negative cooldown values
- clearAuthProfileCooldown
- clears all error state fields including disabledUntil and failureCounts
- preserves lastUsed and lastFailureAt timestamps
- no-ops for unknown profile id
- markAuthProfileFailure — active windows do not extend on retry
- keeps active ${testCase.label} unchanged on retry
- recomputes ${testCase.label} after the previous window expires

### src/agents/bash-process-registry.test.lisp
- bash process registry
- captures output and truncates
- caps pending output to avoid runaway polls
- respects max output cap when pending cap is larger
- caps stdout and stderr independently
- only persists finished sessions when backgrounded

### src/agents/bash-tools.build-docker-exec-args.test.lisp
- buildDockerExecArgs
- prepends custom PATH after login shell sourcing to preserve both custom and system tools
- does not interpolate PATH into the shell command
- does not add PATH export when PATH is not in env
- includes workdir flag when specified
- uses login shell for consistent environment
- includes tty flag when requested

### src/agents/bash-tools.exec-approval-request.test.lisp
- requestExecApprovalDecision
- returns string decisions
- returns null for missing or non-string decisions
- uses registration response id when waiting for decision
- treats expired-or-missing waitDecision as null decision
- returns final decision directly when gateway already replies with decision

### src/agents/bash-tools.exec-runtime.test.lisp
- emitExecSystemEvent
- scopes heartbeat wake to the event session key
- keeps wake unscoped for non-agent session keys
- ignores events without a session key

### src/agents/bash-tools.exec.approval-id.test.lisp
- exec approvals
- reuses approval id as the sbcl runId
- skips approval when sbcl allowlist is satisfied
- honors ask=off for elevated gateway exec without prompting
- uses exec-approvals ask=off to suppress gateway prompts
- inherits ask=off from exec-approvals defaults when tool ask is unset
- requires approval for elevated ask when allowlist misses
- waits for approval registration before returning approval-pending
- fails fast when approval registration fails
- denies sbcl obfuscated command when approval request times out
- denies gateway obfuscated command when approval request times out

### src/agents/bash-tools.exec.background-abort.test.lisp
- background exec is not killed when tool signal aborts
- pty background exec is not killed when tool signal aborts
- background exec still times out after tool signal abort
- background exec without explicit timeout ignores default timeout
- yielded background exec still times out

### src/agents/bash-tools.exec.path.test.lisp
- exec PATH login shell merge
- merges login-shell PATH for host=gateway
- sets OPENCLAW_SHELL for host=gateway commands
- throws security violation when env.PATH is provided
- does not apply login-shell PATH when probe rejects unregistered absolute SHELL
- exec host env validation
- blocks LD_/DYLD_ env vars on host execution
- strips dangerous inherited env vars from host execution
- defaults to sandbox when sandbox runtime is unavailable
- fails closed when sandbox host is explicitly configured without sandbox runtime

### src/agents/bash-tools.exec.pty-cleanup.test.lisp
- exec disposes PTY listeners after normal exit
- exec tears down PTY resources on timeout

### src/agents/bash-tools.exec.pty-fallback-failure.test.lisp
- exec cleans session state when PTY fallback spawn also fails

### src/agents/bash-tools.exec.pty-fallback.test.lisp
- exec falls back when PTY spawn fails

### src/agents/bash-tools.exec.pty.test.lisp
- exec supports pty output
- exec sets OPENCLAW_SHELL in pty mode

### src/agents/bash-tools.exec.script-preflight.test.lisp
- blocks shell env var injection tokens in python scripts before execution
- blocks obvious shell-as-js output before sbcl execution
- skips preflight when script token is quoted and unresolved by fast parser
- skips preflight file reads for script paths outside the workdir

### src/agents/bash-tools.process.poll-timeout.test.lisp
- process poll waits for completion when timeout is provided
- process poll accepts string timeout values
- process poll exposes adaptive retryInMs for repeated no-output polls
- process poll resets retryInMs when output appears and clears on completion

### src/agents/bash-tools.process.send-keys.test.lisp
- process send-keys encodes Enter for pty sessions
- process submit sends Enter for pty sessions

### src/agents/bash-tools.process.supervisor.test.lisp
- process tool supervisor cancellation
- routes kill through supervisor when run is managed
- remove drops running session immediately when cancellation is requested
- falls back to process-tree kill when supervisor record is missing
- fails remove when no supervisor record and no pid is available

### src/agents/bash-tools.shared.test.lisp
- resolveSandboxWorkdir
- maps container root workdir to host workspace
- maps nested container workdir under the container workspace
- supports custom container workdir prefixes

### src/agents/bash-tools.test.lisp
- exec tool backgrounding
- backgrounds after yield and can be polled
- supports explicit background and derives session name from the command
- uses default timeout when timeout is omitted
- scopes process sessions by scopeKey
- exec exit codes
- treats non-zero exits as completed and appends exit code
- exec notifyOnExit
- enqueues a system event when a backgrounded exec exits
- scopes notifyOnExit heartbeat wake to the exec session key
- keeps notifyOnExit heartbeat wake unscoped for non-agent session keys
- exec PATH handling
- prepends configured path entries
- findPathKey
- returns PATH when key is uppercase
- returns Path when key is mixed-case (Windows style)
- returns PATH as default when no PATH-like key exists
- prefers uppercase PATH when both PATH and Path exist
- applyPathPrepend with case-insensitive PATH key
- prepends to Path key on Windows-style env (no uppercase PATH)
- preserves all existing entries when prepending via Path key
- respects requireExisting option with Path key

### src/agents/bedrock-discovery.test.lisp
- bedrock discovery
- filters to active streaming text models and maps modalities
- applies provider filter
- uses configured defaults for context and max tokens
- caches results when refreshInterval is enabled
- skips cache when refreshInterval is 0

### src/agents/bootstrap-budget.test.lisp
- buildBootstrapInjectionStats
- maps raw and injected sizes and marks truncation
- analyzeBootstrapBudget
- reports per-file and total-limit causes
- does not force a total-limit cause when totals are within limits
- bootstrap prompt warnings
- resolves seen signatures from report history or legacy single signature
- ignores single-signature fallback when warning mode is off
- dedupes warnings in once mode by signature
- dedupes once mode across non-consecutive repeated signatures
- includes overflow line when more files are truncated than shown
- disambiguates duplicate file names in warning lines
- respects off/always warning modes
- uses file path in signature to avoid collisions for duplicate names
- builds truncation report metadata from analysis + warning decision

### src/agents/bootstrap-cache.test.lisp
- getOrLoadBootstrapFiles
- loads from disk on first call and caches
- returns cached result on second call
- different session keys get independent caches
- clearBootstrapSnapshot
- clears a single session entry
- does not affect other sessions

### src/agents/bootstrap-files.test.lisp
- resolveBootstrapFilesForRun
- applies bootstrap hook overrides
- drops malformed hook files with missing/invalid paths
- resolveBootstrapContextForRun
- returns context files for hook-adjusted bootstrap files
- uses heartbeat-only bootstrap files in lightweight heartbeat mode
- keeps bootstrap context empty in lightweight cron mode

### src/agents/bootstrap-hooks.test.lisp
- applyBootstrapHookOverrides
- returns updated files when a hook mutates the context

### src/agents/byteplus.live.test.lisp
- returns assistant text

### src/agents/cache-trace.test.lisp
- createCacheTrace
- returns null when diagnostics cache tracing is disabled
- honors diagnostics cache trace config and expands file paths
- records empty prompt/system values when enabled
- respects env overrides for enablement
- redacts image data from options and messages before writing
- handles circular references in messages without stack overflow

### src/agents/channel-tools.test.lisp
- channel tools
- skips crashing plugins and logs once
- does not infer poll actions from outbound adapters when action discovery omits them

### src/agents/chutes-oauth.flow.test.lisp
- chutes-oauth
- exchanges code for tokens and stores username as email
- refreshes tokens using stored client id and falls back to old refresh token
- refreshes tokens and ignores empty refresh_token values

### src/agents/chutes-oauth.test.lisp
- parseOAuthCallbackInput
- rejects code-only input (state required)
- accepts full redirect URL when state matches
- accepts querystring-only input when state matches
- rejects missing state
- rejects state mismatch
- generateChutesPkce
- returns verifier and challenge

### src/agents/claude-cli-runner.test.lisp
- runClaudeCliAgent
- starts a new session with --session-id when none is provided
- uses --resume when a claude session id is provided
- serializes concurrent claude-cli runs

### src/agents/cli-backends.test.lisp
- resolveCliBackendConfig reliability merge
- defaults codex-cli to workspace-write for fresh and resume runs
- deep-merges reliability watchdog overrides for codex
- resolveCliBackendConfig claude-cli defaults
- uses non-interactive permission-mode defaults for fresh and resume args
- retains default claude safety args when only command is overridden
- normalizes legacy skip-permissions overrides to permission-mode bypassPermissions
- keeps explicit permission-mode overrides while removing legacy skip flag

### src/agents/cli-credentials.test.lisp
- cli credentials
- updates the Claude Code keychain item in place
- prevents shell injection via untrusted token payload values
- falls back to the file store when the keychain update fails
- caches Claude Code command-line interface credentials within the TTL window
- refreshes Claude Code command-line interface credentials after the TTL window
- reads Codex credentials from keychain when available
- falls back to Codex auth.json when keychain is unavailable

### src/agents/cli-runner.test.lisp
- runCliAgent with process supervisor
- runs command-line interface through supervisor and returns payload
- fails with timeout when no-output watchdog trips
- enqueues a system event and heartbeat wake on no-output watchdog timeout for session runs
- fails with timeout when overall timeout trips
- rethrows the retry failure when session-expired recovery retry also fails
- falls back to per-agent workspace when workspaceDir is missing
- resolveCliNoOutputTimeoutMs
- uses backend-configured resume watchdog override

### src/agents/command-poll-backoff.test.lisp
- command-poll-backoff
- calculateBackoffMs
- returns 5s for first poll
- returns 10s for second poll
- returns 30s for third poll
- returns 60s for fourth and subsequent polls (capped)
- recordCommandPoll
- returns 5s on first no-output poll
- increments count and increases backoff on consecutive no-output polls
- resets count when poll returns new output
- tracks different commands independently
- getCommandPollSuggestion
- returns undefined for untracked command
- returns current backoff for tracked command
- resetCommandPollCount
- removes command from tracking
- is safe to call on untracked command
- pruneStaleCommandPolls
- removes polls older than maxAge
- handles empty state gracefully

### src/agents/compaction.identifier-policy.test.lisp
- compaction identifier policy
- defaults to strict identifier preservation
- can disable identifier preservation with off policy
- supports custom identifier instructions
- falls back to strict text when custom policy is missing instructions
- keeps custom focus text when identifier policy is off

### src/agents/compaction.identifier-preservation.test.lisp
- compaction identifier-preservation instructions
- injects identifier-preservation guidance even without custom instructions
- keeps identifier-preservation guidance when custom instructions are provided
- applies identifier-preservation guidance on staged split + merge summarization
- avoids duplicate additional-focus headers in split+merge path
- buildCompactionSummarizationInstructions
- returns base instructions when no custom text is provided
- appends custom instructions in a stable format

### src/agents/compaction.retry.test.lisp
- compaction retry integration
- should successfully call generateSummary with retry wrapper
- should retry on transient error and succeed
- should NOT retry on user abort
- should retry up to 3 times and then fail
- should apply exponential backoff

### src/agents/compaction.test.lisp
- splitMessagesByTokenShare
- splits messages into two non-empty parts
- preserves message order across parts
- pruneHistoryForContextShare
- drops older chunks until the history budget is met
- keeps the newest messages when pruning
- keeps history when already within budget
- returns droppedMessagesList containing dropped messages
- returns empty droppedMessagesList when no pruning needed
- removes orphaned tool_result messages when tool_use is dropped
- keeps tool_result when its tool_use is also kept
- removes multiple orphaned tool_results from the same dropped tool_use

### src/agents/compaction.token-sanitize.test.lisp
- compaction token accounting sanitization
- does not pass toolResult.details into per-message token estimates

### src/agents/compaction.tool-result-details.test.lisp
- compaction toolResult details stripping
- does not pass toolResult.details into generateSummary
- ignores toolResult.details when evaluating oversized messages

### src/agents/content-blocks.test.lisp
- collectTextContentBlocks
- collects text content blocks in order
- ignores invalid entries and non-arrays

### src/agents/context-window-guard.test.lisp
- context-window-guard
- blocks below 16k (model metadata)
- warns below 32k but does not block at 16k+
- does not warn at 32k+ (model metadata)
- uses models.providers.*.models[].contextWindow when present
- caps with agents.defaults.contextTokens
- does not override when cap exceeds base window
- uses default when nothing else is available
- allows overriding thresholds
- exports thresholds as expected

### src/agents/context.lookup.test.lisp
- lookupContextTokens
- returns configured model context window on first lookup
- does not skip eager warmup when --profile is followed by -- terminator
- retries config loading after backoff when an initial load fails

### src/agents/context.test.lisp
- applyDiscoveredContextWindows
- keeps the smallest context window when duplicate model ids are discovered
- applyConfiguredContextWindows
- overrides discovered cache values with explicit models.providers contextWindow
- adds config-only model context windows and ignores invalid entries
- createSessionManagerRuntimeRegistry
- stores, reads, and clears values by object identity
- ignores non-object keys
- resolveContextTokensForModel
- returns 1M context when anthropic context1m is enabled for opus/sonnet
- does not force 1M context when context1m is not enabled
- does not force 1M context for non-opus/sonnet Anthropic models

### src/agents/custom-api-registry.test.lisp
- ensureCustomApiRegistered
- registers a custom api provider once
- delegates both stream entrypoints to the provided stream function

### src/agents/failover-error.test.lisp
- failover-error
- infers failover reason from HTTP status
- classifies documented provider error shapes at the error boundary
- keeps status-only 503s conservative unless the payload is clearly overloaded
- treats 400 insufficient_quota payloads as billing instead of format
- treats zhipuai weekly/monthly limit exhausted as rate_limit
- treats overloaded provider payloads as overloaded
- keeps raw-text 402 weekly/monthly limit errors in billing
- keeps temporary 402 spend limits retryable without downgrading explicit billing
- keeps raw 402 wrappers aligned with status-split temporary spend limits
- keeps explicit 402 rate-limit wrappers aligned with status-split payloads
- keeps plan-upgrade 402 wrappers aligned with status-split billing payloads
- infers format errors from error messages
- infers timeout from common sbcl error codes
- infers timeout from abort/error stop-reason messages
- infers timeout from connection/network error messages
- treats AbortError reason=abort as timeout
- coerces failover-worthy errors into FailoverError with metadata
- maps overloaded to a 503 fallback status
- coerces format errors with a 400 status
- 401/403 with generic message still returns auth (backward compat)
- 401 with permanent auth message returns auth_permanent
- 403 with revoked key message returns auth_permanent
- resolveFailoverStatus maps auth_permanent to 403
- coerces permanent auth error with correct reason
- 403 permission_error returns auth_permanent
- permission_error in error message string classifies as auth_permanent
- 'not allowed for this organization' classifies as auth_permanent
- describes non-Error values consistently

### src/agents/google-gemini-switch.live.test.lisp
- handles unsigned tool calls from Antigravity when switching to ${modelId}

### src/agents/huggingface-models.test.lisp
- huggingface-models
- buildHuggingfaceModelDefinition returns config with required fields
- discoverHuggingfaceModels returns static catalog when apiKey is empty
- discoverHuggingfaceModels returns static catalog in test env (VITEST)
- isHuggingfacePolicyLocked
- returns true for :cheapest and :fastest refs
- returns false for base ref and :provider refs

### src/agents/identity-avatar.test.lisp
- resolveAgentAvatar
- resolves local avatar from config when inside workspace
- rejects avatars outside the workspace
- falls back to IDENTITY.md when config has no avatar
- returns missing for non-existent local avatar files
- rejects local avatars larger than max bytes
- accepts remote and data avatars

### src/agents/identity-file.test.lisp
- parseIdentityMarkdown
- ignores identity template placeholders
- parses explicit identity values

### src/agents/identity.human-delay.test.lisp
- resolveHumanDelayConfig
- returns undefined when no humanDelay config is set
- merges defaults with per-agent overrides

### src/agents/identity.per-channel-prefix.test.lisp
- resolveResponsePrefix with per-channel override
- backward compatibility (no channel param)
- returns undefined when no prefix configured anywhere
- returns global prefix when set
- resolves 'auto' to identity name at global level
- returns empty string when global prefix is explicitly empty
- channel-level prefix
- returns channel prefix when set, ignoring global
- falls through to global when channel prefix is undefined
- channel empty string stops cascade (no global prefix applied)
- resolves 'auto' at channel level to identity name
- different channels get different prefixes
- returns undefined when channel not in config
- account-level prefix
- returns account prefix when set, ignoring channel and global
- falls through to channel prefix when account prefix is undefined
- falls through to global when both account and channel are undefined
- account empty string stops cascade
- resolves 'auto' at account level to identity name
- different accounts on same channel get different prefixes
- unknown accountId falls through to channel level
- full 4-level cascade
- L1: account prefix wins when all levels set
- L2: channel prefix when account undefined
- L4: global prefix when channel has no prefix
- undefined: no prefix at any level
- resolveEffectiveMessagesConfig with channel context
- passes channel context through to responsePrefix resolution
- uses global when no channel context provided

### src/agents/identity.test.lisp
- resolveAckReaction
- prefers account-level overrides
- falls back to channel-level overrides
- uses the global ackReaction when channel overrides are missing
- falls back to the agent identity emoji when global config is unset
- returns the default emoji when no config is present
- allows empty strings to disable reactions

### src/agents/image-sanitization.test.lisp
- image sanitization config
- defaults when no config value exists
- reads and normalizes agents.defaults.imageMaxDimensionPx

### src/agents/kilocode-models.test.lisp
- discoverKilocodeModels
- returns static catalog in test environment
- static catalog has correct defaults for kilo/auto
- discoverKilocodeModels (fetch path)
- parses gateway models with correct pricing conversion
- falls back to static catalog on network error
- falls back to static catalog on HTTP error
- ensures kilo/auto is present even when API doesn't return it
- detects text-only models without image modality
- keeps a later valid duplicate when an earlier entry is malformed

### src/agents/memory-search.test.lisp
- memory search config
- returns null when disabled
- defaults provider to auto when unspecified
- merges defaults and overrides
- merges extra memory paths from defaults and overrides
- includes batch defaults for openai without remote overrides
- keeps remote unset for local provider without overrides
- includes remote defaults for gemini without overrides
- includes remote defaults and model default for mistral without overrides
- includes remote defaults and model default for ollama without overrides
- defaults session delta thresholds
- merges remote defaults with agent overrides
- preserves SecretRef remote apiKey when merging defaults with agent overrides
- gates session sources behind experimental flag
- allows session sources when experimental flag is enabled

### src/agents/minimax-vlm.normalizes-api-key.test.lisp
- minimaxUnderstandImage apiKey normalization
- strips embedded CR/LF before sending Authorization header
- drops non-Latin1 characters from apiKey before sending Authorization header
- isMinimaxVlmModel
- only matches the canonical MiniMax VLM model id

### src/agents/minimax.live.test.lisp
- returns assistant text

### src/agents/model-auth-label.test.lisp
- resolveModelAuthLabel
- does not include token value in label for token profiles
- does not include api-key value in label for api-key profiles
- shows oauth type with profile label

### src/agents/model-auth-markers.test.lisp
- model auth markers
- recognizes explicit non-secret markers
- recognizes known env marker names but not arbitrary all-caps keys
- recognizes all built-in provider env marker names
- can exclude env marker-name interpretation for display-only paths

### src/agents/model-auth.profiles.test.lisp
- getApiKeyForModel
- migrates legacy oauth.json into auth-profiles.json
- suggests openai-codex when only Codex OAuth is configured
- throws when ZAI API key is missing
- accepts legacy Z_AI_API_KEY for zai
- resolves Synthetic API key from env
- resolves Qianfan API key from env
- resolves synthetic local auth key for configured ollama provider without apiKey
- prefers explicit OLLAMA_API_KEY over synthetic local key
- still throws for ollama when no env/profile/config provider is available
- resolves Vercel AI Gateway API key from env
- prefers Bedrock bearer token over access keys and profile
- prefers Bedrock access keys over profile
- uses Bedrock profile when access keys are missing
- accepts VOYAGE_API_KEY for voyage
- strips embedded CR/LF from ANTHROPIC_API_KEY
- resolveEnvApiKey('huggingface') returns HUGGINGFACE_HUB_TOKEN when set
- resolveEnvApiKey('huggingface') prefers HUGGINGFACE_HUB_TOKEN over HF_TOKEN when both set
- resolveEnvApiKey('huggingface') returns HF_TOKEN when only HF_TOKEN set

### src/agents/model-auth.test.lisp
- resolveAwsSdkEnvVarName
- prefers bearer token over access keys and profile
- uses access keys when bearer token is missing
- uses profile when no bearer token or access keys exist
- returns undefined when no AWS auth env is set
- resolveModelAuthMode
- returns mixed when provider has both token and api key profiles
- returns aws-sdk when provider auth is overridden
- returns aws-sdk for bedrock alias without explicit auth override
- returns aws-sdk for aws-bedrock alias without explicit auth override
- requireApiKey
- normalizes line breaks in resolved API keys
- throws when no API key is present

### src/agents/model-catalog.test.lisp
- loadModelCatalog
- retries after import failure without poisoning the cache
- returns partial results on discovery errors
- adds openai-codex/gpt-5.3-codex-spark when base gpt-5.3-codex exists
- adds gpt-5.4 forward-compat catalog entries when template models exist
- merges configured models for opted-in non-pi-native providers
- does not merge configured models for providers that are not opted in
- does not duplicate opted-in configured models already present in ModelRegistry

### src/agents/model-compat.test.lisp
- normalizeModelCompat — Anthropic baseUrl
- strips /v1 suffix from anthropic-messages baseUrl
- strips trailing /v1/ (with slash) from anthropic-messages baseUrl
- leaves anthropic-messages baseUrl without /v1 unchanged
- leaves baseUrl undefined unchanged for anthropic-messages
- does not strip /v1 from non-anthropic-messages models
- strips /v1 from custom Anthropic proxy baseUrl
- normalizeModelCompat
- forces supportsDeveloperRole off for z.ai models
- forces supportsDeveloperRole off for moonshot models
- forces supportsDeveloperRole off for custom moonshot-compatible endpoints
- forces supportsDeveloperRole off for DashScope provider ids
- forces supportsDeveloperRole off for DashScope-compatible endpoints
- leaves native api.openai.com model untouched
- forces supportsDeveloperRole off for Azure OpenAI (Chat Completions, not Responses API)
- forces supportsDeveloperRole off for generic custom openai-completions provider
- forces supportsUsageInStreaming off for generic custom openai-completions provider
- forces supportsDeveloperRole off for Qwen proxy via openai-completions
- leaves openai-completions model with empty baseUrl untouched
- forces supportsDeveloperRole off for malformed baseUrl values
- overrides explicit supportsDeveloperRole true on non-native endpoints
- overrides explicit supportsUsageInStreaming true on non-native endpoints
- does not mutate caller model when forcing supportsDeveloperRole off
- does not override explicit compat false
- isModernModelRef
- includes OpenAI gpt-5.4 variants in modern selection
- excludes opencode minimax variants from modern selection
- keeps non-minimax opencode modern models
- resolveForwardCompatModel
- resolves openai gpt-5.4 via gpt-5.2 template
- resolves openai gpt-5.4 without templates using normalized fallback defaults
- resolves openai gpt-5.4-pro via template fallback
- resolves openai-codex gpt-5.4 via codex template fallback
- resolves anthropic opus 4.6 via 4.5 template
- resolves anthropic sonnet 4.6 dot variant with suffix
- does not resolve anthropic 4.6 fallback for other providers

### src/agents/model-fallback.probe.test.lisp
- runWithModelFallback – probe logic
- skips primary model when far from cooldown expiry (30 min remaining)
- uses inferred unavailable reason when skipping a cooldowned primary model
- probes primary model when within 2-min margin of cooldown expiry
- probes primary model when cooldown already expired
- attempts non-primary fallbacks during rate-limit cooldown after primary probe failure
- attempts non-primary fallbacks during overloaded cooldown after primary probe failure
- throttles probe when called within 30s interval
- allows probe when 30s have passed since last probe
- handles non-finite soonest safely (treats as probe-worthy)
- handles NaN soonest safely (treats as probe-worthy)
- handles null soonest safely (treats as probe-worthy)
- single candidate skips with rate_limit and exhausts candidates
- scopes probe throttling by agentDir to avoid cross-agent suppression
- skips billing-cooldowned primary when no fallback candidates exist
- probes billing-cooldowned primary with fallbacks when near cooldown expiry
- skips billing-cooldowned primary with fallbacks when far from cooldown expiry

### src/agents/model-fallback.run-embedded.e2e.test.lisp
- runWithModelFallback + runEmbeddedPiAgent overload policy
- falls back across providers after overloaded primary failure and persists transient cooldown
- surfaces a bounded overloaded summary when every fallback candidate is overloaded
- probes a provider already in overloaded cooldown before falling back
- persists overloaded cooldown across turns while still allowing one probe and fallback
- keeps bare service-unavailable failures in the timeout lane without persisting cooldown
- rethrows AbortError during overload backoff instead of falling through fallback

### src/agents/model-fallback.test.lisp
- runWithModelFallback
- keeps openai gpt-5.3 codex on the openai provider before running
- falls back on unrecognized errors when candidates remain
- passes original unknown errors to onError during fallback
- throws unrecognized error on last candidate
- falls back on auth errors
- falls back directly to configured primary when an override model fails
- keeps configured fallback chain when current model is a configured fallback
- treats normalized default refs as primary and keeps configured fallback chain
- falls back on transient HTTP 5xx errors
- falls back on 402 payment required
- falls back on billing errors
- records 400 insufficient_quota payloads as billing during fallback
- falls back to configured primary for override credential validation errors
- falls back on unknown model errors
- falls back on model not found errors
- warns when falling back due to model_not_found
- sanitizes model identifiers in model_not_found warnings
- skips providers when all profiles are in cooldown
- does not skip OpenRouter when legacy cooldown markers exist
- propagates disabled reason when all profiles are unavailable
- does not skip when any profile is available
- does not append configured primary when fallbacksOverride is set
- uses fallbacksOverride instead of agents.defaults.model.fallbacks
- treats an empty fallbacksOverride as disabling global fallbacks
- keeps explicit fallbacks reachable when models allowlist is present
- defaults provider/model when missing (regression #946)
- falls back on missing API key errors
- falls back on lowercase credential errors
- falls back on documented OpenAI 429 rate limit responses
- falls back on documented overloaded_error payloads
- falls back on internal model cooldown markers
- falls back on compatibility connection error messages
- falls back on timeout abort errors
- falls back on abort errors with timeout reasons
- falls back on abort errors with reason: abort
- falls back on unhandled stop reason error responses
- falls back on abort errors with reason: error
- falls back when message says aborted but error is a timeout
- falls back on ECONNREFUSED (local server down or remote unreachable)
- falls back on ENETUNREACH (network disconnected)
- falls back on EHOSTUNREACH (host unreachable)
- falls back on EAI_AGAIN (DNS resolution failure)
- falls back on ENETRESET (connection reset by network)
- falls back on provider abort errors with request-aborted messages
- does not fall back on user aborts
- appends the configured primary as a last fallback
- fallback behavior with session model overrides
- allows fallbacks when session model differs from config within same provider
- allows fallbacks with model version differences within same provider
- still skips fallbacks when using different provider than config
- uses fallbacks when session model exactly matches config primary
- fallback behavior with provider cooldowns
- attempts same-provider fallbacks during rate limit cooldown
- attempts same-provider fallbacks during overloaded cooldown
- skips same-provider models on auth cooldown but still tries no-profile fallback providers
- skips same-provider models on billing cooldown but still tries no-profile fallback providers
- tries cross-provider fallbacks when same provider has rate limit
- runWithImageModelFallback
- keeps explicit image fallbacks reachable when models allowlist is present
- isAnthropicBillingError
- does not false-positive on plain 'a 402' prose
- matches real 402 billing payload contexts including JSON keys

### src/agents/model-ref-profile.test.lisp
- splitTrailingAuthProfile
- returns trimmed model when no profile suffix exists
- splits trailing @profile suffix
- keeps @-prefixed path segments in model ids
- supports trailing profile override after @-prefixed path segments
- keeps openrouter preset paths without profile override
- supports openrouter preset profile overrides
- does not split when suffix after @ contains slash
- uses first @ after last slash for email-based auth profiles

### src/agents/model-scan.test.lisp
- scanOpenRouterModels
- lists free models without probing
- requires an API key when probing

### src/agents/model-selection.test.lisp
- model-selection
- normalizeProviderId
- should normalize provider names
- normalizeProviderIdForAuth
- maps coding-plan variants to base provider for auth lookup
- parseModelRef
- should parse full model refs
- preserves nested model ids after provider prefix
- normalizes anthropic alias refs to canonical model ids
- should use default provider if none specified
- normalizes deprecated google flash preview ids to the working model id
- normalizes gemini 3.1 flash-lite to the preview model id
- keeps openai gpt-5.3 codex refs on the openai provider
- should return null for empty strings
- should preserve openrouter/ prefix for native models
- should pass through openrouter external provider models as-is
- normalizes Vercel Claude shorthand to anthropic-prefixed model ids
- keeps already-prefixed Vercel Anthropic models unchanged
- passes through non-Claude Vercel model ids unchanged
- should handle invalid slash usage
- inferUniqueProviderFromConfiguredModels
- infers provider when configured model match is unique
- returns undefined when configured matches are ambiguous
- returns undefined for provider-prefixed model ids
- infers provider for slash-containing model id when allowlist match is unique
- buildModelAliasIndex
- should build alias index from config
- buildAllowedModelSet
- keeps explicitly allowlisted models even when missing from bundled catalog
- resolveAllowedModelRef
- accepts explicit allowlist refs absent from bundled catalog
- strips trailing auth profile suffix before allowlist matching
- resolveModelRefFromString
- should resolve from string with alias
- should resolve direct ref if no alias match
- strips trailing profile suffix for simple model refs
- strips trailing profile suffix for provider/model refs
- preserves Cloudflare @cf model segments
- preserves OpenRouter @preset model segments
- splits trailing profile suffix after OpenRouter preset paths
- strips profile suffix before alias resolution
- resolveConfiguredModelRef
- should fall back to anthropic and warn if provider is missing for non-alias
- sanitizes control characters in providerless-model warnings
- should use default provider/model if config is empty
- should prefer configured custom provider when default provider is not in models.providers
- should keep default provider when it is in models.providers
- should fall back to hardcoded default when no custom providers have models
- should warn when specified model cannot be resolved and falls back to default
- resolveThinkingDefault
- prefers per-model params.thinking over global thinkingDefault
- accepts per-model params.thinking=adaptive
- defaults Anthropic Claude 4.6 models to adaptive
- normalizeModelSelection
- returns trimmed string for string input
- returns undefined for empty/whitespace string
- extracts primary from object
- returns undefined for object without primary
- returns undefined for null/undefined/number

### src/agents/model-tool-support.test.lisp
- supportsModelTools
- defaults to true when the model has no compat override
- returns true when compat.supportsTools is true
- returns false when compat.supportsTools is false

### src/agents/models-config.applies-config-env-vars.test.lisp
- models-config
- applies config env.vars entries while ensuring models.json
- does not overwrite already-set host env vars

### src/agents/models-config.auto-injects-github-copilot-provider-token-is.test.lisp
- models-config
- auto-injects github-copilot provider when token is present
- prefers COPILOT_GITHUB_TOKEN over GH_TOKEN and GITHUB_TOKEN

### src/agents/models-config.falls-back-default-baseurl-token-exchange-fails.test.lisp
- models-config
- falls back to default baseUrl when token exchange fails
- uses agentDir override auth profiles for copilot injection

### src/agents/models-config.file-mode.test.lisp
- models-config file mode
- writes models.json with mode 0600
- repairs models.json mode to 0600 on no-content-change paths

### src/agents/models-config.fills-missing-provider-apikey-from-env-var.test.lisp
- models-config
- keeps anthropic api defaults when model entries omit api
- fills missing provider.apiKey from env var name when models exist
- merges providers by default
- preserves non-empty agent apiKey but lets explicit config baseUrl win in merge mode
- lets explicit config baseUrl win in merge mode when the config provider key is normalized
- replaces stale merged apiKey when provider is SecretRef-managed in current config
- replaces stale merged apiKey when provider is SecretRef-managed via auth-profiles
- replaces stale non-env marker when provider transitions back to plaintext config
- uses config apiKey/baseUrl when existing agent values are empty
- refreshes moonshot capabilities while preserving explicit token limits
- does not persist resolved env var value as plaintext in models.json
- preserves explicit larger token limits when they exceed implicit catalog defaults
- falls back to implicit token limits when explicit values are invalid

### src/agents/models-config.normalizes-gemini-3-ids-preview-google-providers.test.lisp
- models-config
- normalizes gemini 3 ids to preview for google providers
- normalizes the deprecated google flash preview id to the working preview id

### src/agents/models-config.preserves-explicit-reasoning-override.test.lisp
- models-config: explicit reasoning override
- preserves user reasoning:false when built-in catalog has reasoning:true (MiniMax-M2.5)
- falls back to built-in reasoning:true when user omits the field (MiniMax-M2.5)

### src/agents/models-config.providers.auth-provenance.test.lisp
- models-config provider auth provenance
- persists env keyRef and tokenRef auth profiles as env var markers
- uses non-env marker for ref-managed profiles even when runtime plaintext is present
- keeps oauth compatibility markers for minimax-portal and qwen-portal

### src/agents/models-config.providers.cloudflare-ai-gateway.test.lisp
- cloudflare-ai-gateway profile provenance
- prefers env keyRef marker over runtime plaintext for persistence
- uses non-env marker for non-env keyRef cloudflare profiles

### src/agents/models-config.providers.discovery-auth.test.lisp
- provider discovery auth marker guardrails
- does not send marker value as vLLM bearer token during discovery
- does not call Hugging Face discovery with marker-backed credentials
- keeps all-caps plaintext API keys for authenticated discovery

### src/agents/models-config.providers.google-antigravity.test.lisp
- normalizeAntigravityModelId
- normalizeGoogleModelId
- maps the deprecated 3.1 flash alias to the real preview model
- adds the preview suffix for gemini 3.1 flash-lite
- google-antigravity provider normalization
- normalizes bare gemini pro IDs only for google-antigravity providers
- returns original providers object when no antigravity IDs need normalization

### src/agents/models-config.providers.kilocode.test.lisp
- Kilo Gateway implicit provider
- should include kilocode when KILOCODE_API_KEY is configured
- should not include kilocode when no API key is configured
- should build kilocode provider with correct configuration
- should include the default kilocode model
- should include the static fallback catalog

### src/agents/models-config.providers.kimi-coding.test.lisp
- kimi-coding implicit provider (#22409)
- should include kimi-coding when KIMI_API_KEY is configured
- should build kimi-coding provider with anthropic-messages API
- should not include kimi-coding when no API key is configured

### src/agents/models-config.providers.minimax.test.lisp
- minimax provider catalog
- does not advertise the removed lightning model for api-key or oauth providers

### src/agents/models-config.providers.normalize-keys.test.lisp
- normalizeProviders
- trims provider keys so image models remain discoverable for custom providers
- keeps the latest provider config when duplicate keys only differ by whitespace
- replaces resolved env var value with env var name to prevent plaintext persistence
- normalizes SecretRef-backed provider headers to non-secret marker values

### src/agents/models-config.providers.nvidia.test.lisp
- NVIDIA provider
- should include nvidia when NVIDIA_API_KEY is configured
- resolves the nvidia api key value from env
- should build nvidia provider with correct configuration
- should include default nvidia models
- MiniMax implicit provider (#15275)
- should use anthropic-messages API for API-key provider
- should set authHeader for minimax portal provider
- should include minimax portal provider when MINIMAX_OAUTH_TOKEN is configured
- vLLM provider
- should not include vllm when no API key is configured
- should include vllm when VLLM_API_KEY is set

### src/agents/models-config.providers.ollama-autodiscovery.test.lisp
- Ollama auto-discovery
- auto-registers ollama provider when models are discovered locally
- does not warn when Ollama is unreachable and not explicitly configured
- warns when Ollama is unreachable and explicitly configured

### src/agents/models-config.providers.ollama.test.lisp
- resolveOllamaApiBase
- returns default localhost base when no configured URL is provided
- strips /v1 suffix from OpenAI-compatible URLs
- keeps URLs without /v1 unchanged
- handles trailing slash before canonicalizing
- Ollama provider
- should not include ollama when no API key is configured
- should use native ollama api type
- should preserve explicit ollama baseUrl on implicit provider injection
- discovers per-model context windows from /api/show
- falls back to default context window when /api/show fails
- caps /api/show requests when /api/tags returns a very large model list
- should have correct model structure without streaming override
- should skip discovery fetch when explicit models are configured
- should preserve explicit apiKey when discovery path has no models and no env key

### src/agents/models-config.providers.qianfan.test.lisp
- Qianfan provider
- should include qianfan when QIANFAN_API_KEY is configured

### src/agents/models-config.providers.volcengine-byteplus.test.lisp
- Volcengine and BytePlus providers
- includes volcengine and volcengine-plan when VOLCANO_ENGINE_API_KEY is configured
- includes byteplus and byteplus-plan when BYTEPLUS_API_KEY is configured
- includes providers when auth profiles are env keyRef-only

### src/agents/models-config.runtime-source-snapshot.test.lisp
- models-config runtime source snapshot
- uses runtime source snapshot markers when passed the active runtime config
- uses non-env marker from runtime source snapshot for file refs
- uses header markers from runtime source snapshot instead of resolved runtime values

### src/agents/models-config.skips-writing-models-json-no-env-token.test.lisp
- models-config
- skips writing models.json when no env token or profile exists
- writes models.json for configured providers
- adds minimax provider when MINIMAX_API_KEY is set
- adds synthetic provider when SYNTHETIC_API_KEY is set

### src/agents/models-config.uses-first-github-copilot-profile-env-tokens.test.lisp
- models-config
- uses the first github-copilot profile when env tokens are missing
- does not override explicit github-copilot provider config
- uses tokenRef env var when github-copilot profile omits plaintext token

### src/agents/models-config.write-serialization.test.lisp
- models-config write serialization
- serializes concurrent models.json writes to avoid overlap

### src/agents/models.profiles.live.test.lisp
- completes across selected models

### src/agents/moonshot.live.test.lisp
- returns assistant text

### src/agents/ollama-stream.test.lisp
- convertToOllamaMessages
- converts user text messages
- converts user messages with content parts
- prepends system message when provided
- converts assistant messages with toolCall content blocks
- converts tool result messages with 'tool' role
- converts SDK 'toolResult' role to Ollama 'tool' role
- includes tool_name from SDK toolResult messages
- omits tool_name when not provided in toolResult
- handles empty messages array
- buildAssistantMessage
- builds text-only response
- falls back to thinking when content is empty
- falls back to reasoning when content and thinking are empty
- builds response with tool calls
- sets all costs to zero for local models
- parseNdjsonStream
- parses text-only streaming chunks
- parses tool_calls from intermediate chunk (not final)
- accumulates tool_calls across multiple intermediate chunks
- preserves unsafe integer tool arguments as exact strings
- keeps safe integer tool arguments as numbers
- createOllamaStreamFn
- normalizes /v1 baseUrl and maps maxTokens + signal
- merges default headers and allows request headers to override them
- preserves an explicit Authorization header when apiKey is a local marker
- allows a real apiKey to override an explicit Authorization header
- accumulates thinking chunks when content is empty
- prefers streamed content over earlier thinking chunks
- accumulates reasoning chunks when thinking is absent
- prefers streamed content over earlier reasoning chunks
- resolveOllamaBaseUrlForRun
- prefers provider baseUrl over model baseUrl
- falls back to model baseUrl when provider baseUrl is missing
- falls back to native default when neither baseUrl is configured
- createConfiguredOllamaStreamFn
- uses provider-level baseUrl when model baseUrl is absent

### src/agents/openai-responses.reasoning-replay.test.lisp
- openai-responses reasoning replay
- replays reasoning for tool-call-only turns (OpenAI requires it)
- still replays reasoning when paired with an assistant message

### src/agents/openai-ws-connection.test.lisp
- OpenAIWebSocketManager
- connect()
- opens a WebSocket with Bearer auth header
- resolves when the connection opens
- rejects when the initial connection fails (maxRetries=0)
- sets isConnected() to true after open
- uses the custom URL when provided
- send()
- sends a JSON-serialized event over the socket
- throws if the connection is not open
- includes previous_response_id when provided
- onMessage()
- calls handler for each incoming message
- returns an unsubscribe function that stops delivery
- supports multiple simultaneous handlers
- previousResponseId
- starts as null
- is updated when a response.completed event is received
- tracks the most recent completed response
- is not updated for non-completed events
- isConnected()
- returns false before connect
- returns true while open
- returns false after close()
- close()
- marks the manager as disconnected
- prevents reconnect after explicit close
- is safe to call before connect()
- auto-reconnect
- reconnects on unexpected close
- stops retrying after maxRetries
- does not double-count retries when error and close both fire on a reconnect attempt
- resets retry count after a successful reconnect
- warmUp()
- sends a response.create event with generate: false
- includes tools when provided
- error handling
- emits error event on malformed JSON message
- emits error event when message has no type field
- emits error event on WebSocket socket error
- handles multiple successive socket errors without crashing
- full turn sequence
- tracks previous_response_id across turns and sends continuation correctly

### src/agents/openai-ws-stream.e2e.test.lisp
- OpenAI WebSocket e2e

### src/agents/openai-ws-stream.test.lisp
- convertTools
- returns empty array for undefined tools
- returns empty array for empty tools
- converts tools to FunctionToolDefinition format
- handles tools without description
- convertMessagesToInputItems
- converts a simple user text message
- converts an assistant text-only message
- converts an assistant message with a tool call
- converts a tool result message
- drops tool result messages with empty tool call id
- falls back to toolUseId when toolCallId is missing
- converts a full multi-turn conversation
- handles assistant messages with only tool calls (no text)
- drops assistant tool calls with empty ids
- skips thinking blocks in assistant messages
- returns empty array for empty messages
- buildAssistantMessageFromResponse
- extracts text content from a message output item
- sets stopReason to 'stop' for text-only responses
- extracts tool call from function_call output item
- sets stopReason to 'toolUse' when tool calls are present
- includes both text and tool calls when both present
- maps usage tokens correctly
- sets model/provider/api from modelInfo
- handles empty output gracefully
- createOpenAIWebSocketStreamFn
- connects to the WebSocket on first call
- sends a response.create event on first turn (full context)
- includes store:false by default
- omits store when compat.supportsStore is false (#39086)
- emits an AssistantMessage on response.completed
- falls back to HTTP when WebSocket connect fails (session pre-broken via flag)
- tracks previous_response_id across turns (incremental send)
- sends instructions (system prompt) in each request
- resets session state and falls back to HTTP when send() throws
- forwards temperature and maxTokens to response.create
- forwards maxTokens: 0 to response.create as max_output_tokens
- forwards reasoningEffort/reasoningSummary to response.create reasoning block
- forwards topP and toolChoice to response.create
- rejects promise when WebSocket drops mid-request
- sends warm-up event before first request when openaiWsWarmup=true
- skips warm-up when openaiWsWarmup=false
- releaseWsSession / hasWsSession
- hasWsSession returns false for unknown session
- hasWsSession returns true after a session is created
- releaseWsSession closes the connection and removes the session
- releaseWsSession is a no-op for unknown sessions

### src/agents/openclaw-gateway-tool.test.lisp
- gateway tool
- marks gateway as owner-only
- schedules SIGUSR1 restart
- passes config.apply through gateway call
- passes config.patch through gateway call
- passes update.run through gateway call
- returns a path-scoped schema lookup result

### src/agents/openclaw-tools.agents.test.lisp
- agents_list
- defaults to the requester agent only
- includes allowlisted targets plus requester
- returns configured agents when allowlist is *
- marks allowlisted-but-unconfigured agents

### src/agents/openclaw-tools.camera.test.lisp
- nodes camera_snap
- uses front/high-quality defaults when params are omitted
- maps jpg payloads to image/jpeg
- omits inline base64 image blocks when model has no vision
- passes deviceId when provided
- rejects facing both when deviceId is provided
- downloads camera_snap url payloads when sbcl remoteIp is available
- rejects camera_snap url payloads when sbcl remoteIp is missing
- nodes camera_clip
- downloads camera_clip url payloads when sbcl remoteIp is available
- rejects camera_clip url payloads when sbcl remoteIp is missing
- nodes photos_latest
- returns empty content/details when no photos are available
- returns MEDIA paths and no inline images when model has no vision
- includes inline image blocks when model has vision
- nodes notifications_list
- invokes notifications.list and returns payload
- nodes notifications_action
- invokes notifications.actions dismiss
- nodes device_status and device_info
- invokes device.status and returns payload
- invokes device.info and returns payload
- invokes device.permissions and returns payload
- invokes device.health and returns payload
- nodes run
- passes invoke and command timeouts
- requests approval and retries with allow-once decision
- fails with user denied when approval decision is deny
- fails closed for timeout and invalid approval decisions
- nodes invoke
- allows metadata-only camera.list via generic invoke
- blocks media invoke commands to avoid base64 context bloat
- allows media invoke commands when explicitly enabled

### src/agents/openclaw-tools.pdf-registration.test.lisp
- createOpenClawTools PDF registration
- includes pdf tool when pdfModel is configured

### src/agents/openclaw-tools.plugin-context.test.lisp
- createOpenClawTools plugin context
- forwards trusted requester sender identity to plugin tool context
- forwards ephemeral sessionId to plugin tool context

### src/agents/openclaw-tools.session-status.test.lisp
- session_status tool
- returns a status card for the current session
- errors for unknown session keys
- resolves sessionId inputs
- uses non-standard session keys without sessionId resolution
- blocks cross-agent session_status without agent-to-agent access
- scopes bare session keys to the requester agent
- resets per-session model override via model=default

### src/agents/openclaw-tools.sessions-visibility.test.lisp
- sessions tools visibility
- defaults to tree visibility (self + spawned) for sessions_history
- allows broader access when tools.sessions.visibility=all
- clamps sandboxed sessions to tree when agents.defaults.sandbox.sessionToolsVisibility=spawned

### src/agents/openclaw-tools.sessions.test.lisp
- sessions tools
- uses number (not integer) in tool schemas for Gemini compatibility
- sessions_list filters kinds and includes messages
- sessions_list resolves transcriptPath from agent state dir for multi-store listings
- sessions_history filters tool messages by default
- sessions_history caps oversized payloads and strips heavy fields
- sessions_history enforces a hard byte cap even when a single message is huge
- sessions_history sets contentRedacted when sensitive data is redacted
- sessions_history sets both contentRedacted and contentTruncated independently
- sessions_history resolves sessionId inputs
- sessions_history errors on missing sessionId
- sessions_send supports fire-and-forget and wait
- sessions_send resolves sessionId inputs
- sessions_send runs ping-pong then announces
- subagents lists active and recent runs
- subagents list keeps ended orchestrators active while descendants are pending
- subagents list usage separates io tokens from prompt/cache
- subagents steer sends guidance to a running run
- subagents numeric targets follow active-first list ordering
- subagents numeric targets treat ended orchestrators waiting on children as active
- subagents kill stops a running run
- subagents kill-all cascades through ended parents to active descendants

### src/agents/openclaw-tools.subagents.sessions-spawn-applies-thinking-default.test.lisp
- sessions_spawn thinking defaults
- applies agents.defaults.subagents.thinking when thinking is omitted
- prefers explicit sessions_spawn.thinking over config default

### src/agents/openclaw-tools.subagents.sessions-spawn-default-timeout-absent.test.lisp
- sessions_spawn default runTimeoutSeconds (config absent)
- falls back to 0 (no timeout) when config key is absent

### src/agents/openclaw-tools.subagents.sessions-spawn-default-timeout.test.lisp
- sessions_spawn default runTimeoutSeconds
- uses config default when agent omits runTimeoutSeconds
- explicit runTimeoutSeconds wins over config default

### src/agents/openclaw-tools.subagents.sessions-spawn-depth-limits.test.lisp
- sessions_spawn depth + child limits
- rejects spawning when caller depth reaches maxSpawnDepth
- allows depth-1 callers when maxSpawnDepth is 2
- rejects depth-2 callers when maxSpawnDepth is 2 (using stored spawnDepth on flat keys)
- rejects depth-2 callers when spawnDepth is missing but spawnedBy ancestry implies depth 2
- rejects depth-2 callers when the requester key is a sessionId
- rejects when active children for requester session reached maxChildrenPerAgent
- does not use subagent maxConcurrent as a per-parent spawn gate
- fails spawn when sessions.patch rejects the model

### src/agents/openclaw-tools.subagents.sessions-spawn.allowlist.test.lisp
- openclaw-tools: subagents (sessions_spawn allowlist)
- sessions_spawn only allows same-agent by default
- sessions_spawn forbids cross-agent spawning when not allowed
- sessions_spawn allows cross-agent spawning when configured
- sessions_spawn allows any agent when allowlist is *
- sessions_spawn normalizes allowlisted agent ids
- forbids sandboxed cross-agent spawns that would unsandbox the child
- forbids sandbox="require" when target runtime is unsandboxed
- rejects error-message-like strings as agentId (#31311)
- rejects agentId containing path separators (#31311)
- rejects agentId exceeding 64 characters (#31311)
- accepts well-formed agentId with hyphens and underscores (#31311)
- allows allowlisted-but-unconfigured agentId (#31311)

### src/agents/openclaw-tools.subagents.sessions-spawn.cron-note.test.lisp
- sessions_spawn: cron isolated session note suppression
- suppresses ACCEPTED_NOTE for cron isolated sessions (mode=run)
- preserves ACCEPTED_NOTE for regular sessions (mode=run)
- does not suppress ACCEPTED_NOTE for non-canonical cron-like keys
- does not suppress note when agentSessionKey is undefined

### src/agents/openclaw-tools.subagents.sessions-spawn.lifecycle.test.lisp
- openclaw-tools: subagents (sessions_spawn lifecycle)
- sessions_spawn runs cleanup flow after subagent completion
- sessions_spawn runs cleanup via lifecycle events
- sessions_spawn deletes session when cleanup=delete via agent.wait
- sessions_spawn reports timed out when agent.wait returns timeout
- sessions_spawn announces with requester accountId

### src/agents/openclaw-tools.subagents.sessions-spawn.model.test.lisp
- openclaw-tools: subagents (sessions_spawn model + thinking)
- sessions_spawn applies a model to the child session
- sessions_spawn forwards thinking overrides to the agent run
- sessions_spawn rejects invalid thinking levels
- sessions_spawn applies default subagent model from defaults config
- sessions_spawn falls back to runtime default model when no model config is set
- sessions_spawn prefers per-agent subagent model over defaults
- sessions_spawn prefers target agent primary model over global default
- sessions_spawn fails when model patch is rejected
- sessions_spawn supports legacy timeoutSeconds alias

### src/agents/openclaw-tools.subagents.steer-failure-clears-suppression.test.lisp
- openclaw-tools: subagents steer failure
- restores announce behavior when steer replacement dispatch fails

### src/agents/opencode-zen-models.test.lisp
- resolveOpencodeZenAlias
- resolves opus alias
- keeps legacy aliases working
- resolves gpt5 alias
- resolves gemini alias
- returns input if no alias exists
- is case-insensitive
- resolveOpencodeZenModelApi
- maps APIs by model family
- getOpencodeZenStaticFallbackModels
- returns an array of models
- includes Claude, GPT, Gemini, and GLM models
- returns valid ModelDefinitionConfig objects
- OPENCODE_ZEN_MODEL_ALIASES
- has expected aliases

### src/agents/owner-display.test.lisp
- resolveOwnerDisplaySetting
- returns keyed hash settings when hash mode has an explicit secret
- does not fall back to gateway tokens when hash secret is missing
- disables owner hash secret when display mode is raw
- ensureOwnerDisplaySecret
- generates a dedicated secret when hash mode is enabled without one
- does nothing when a hash secret is already configured

### src/agents/path-policy.test.lisp
- toRelativeWorkspacePath (windows semantics)
- accepts windows paths with mixed separators and case
- rejects windows paths outside workspace root

### src/agents/pi-auth-json.test.lisp
- ensurePiAuthJsonFromAuthProfiles
- writes openai-codex oauth credentials into auth.json for pi-coding-agent discovery
- writes api_key credentials into auth.json
- writes token credentials as api_key into auth.json
- syncs multiple providers at once
- skips profiles with empty keys
- skips expired token credentials
- normalizes provider ids when writing auth.json keys
- preserves existing auth.json entries not in auth-profiles

### src/agents/pi-embedded-block-chunker.test.lisp
- EmbeddedBlockChunker
- breaks at paragraph boundary right after fence close
- flushes paragraph boundaries before minChars when flushOnParagraph is set
- treats blank lines with whitespace as paragraph boundaries when flushOnParagraph is set
- falls back to maxChars when flushOnParagraph is set and no paragraph break exists
- clamps long paragraphs to maxChars when flushOnParagraph is set
- ignores paragraph breaks inside fences when flushOnParagraph is set
- parses fence spans once per drain call for long fenced buffers

### src/agents/pi-embedded-helpers.buildbootstrapcontextfiles.test.lisp
- buildBootstrapContextFiles
- keeps missing markers
- skips empty or whitespace-only content
- truncates large bootstrap content
- keeps content under the default limit
- keeps total injected bootstrap characters under the new default total cap
- caps total injected bootstrap characters when totalMaxChars is configured
- enforces strict total cap even when truncation markers are present
- skips bootstrap injection when remaining total budget is too small
- keeps missing markers under small total budgets
- skips files with missing or invalid paths and emits warnings
- bootstrap limit resolvers
- return defaults when unset
- use configured values when valid
- fall back when values are invalid
- resolveBootstrapPromptTruncationWarningMode
- defaults to once
- accepts explicit valid modes
- falls back to default for invalid values

### src/agents/pi-embedded-helpers.formatassistanterrortext.test.lisp
- formatAssistantErrorText
- returns a friendly message for context overflow
- returns context overflow for Anthropic 'Request size exceeds model context window'
- returns context overflow for Kimi 'model token limit' errors
- returns a reasoning-required message for mandatory reasoning endpoint errors
- returns a friendly message for Anthropic role ordering
- returns a friendly message for Anthropic overload errors
- returns a recovery hint when tool call input is missing
- handles JSON-wrapped role errors
- suppresses raw error JSON payloads that are not otherwise classified
- returns a friendly billing message for credit balance errors
- returns a friendly billing message for HTTP 402 errors
- returns a friendly billing message for insufficient credits
- includes provider and assistant model in billing message when provider is given
- uses the active assistant model for billing message context
- returns generic billing message when provider is not given
- returns a friendly message for rate limit errors
- returns a friendly message for empty stream chunk errors
- formatRawAssistantErrorForUi
- renders HTTP code + type + message from Anthropic payloads
- renders a generic unknown error message when raw is empty
- formats plain HTTP status lines
- sanitizes HTML error pages into a clean unavailable message

### src/agents/pi-embedded-helpers.isbillingerrormessage.test.lisp
- isAuthPermanentErrorMessage
- matches permanent auth failure patterns
- does not match transient auth errors
- isAuthErrorMessage
- matches credential validation errors
- matches OAuth refresh failures
- isBillingErrorMessage
- matches credit / payment failures
- does not false-positive on issue IDs or text containing 402
- does not false-positive on long assistant responses mentioning billing keywords
- still matches explicit 402 markers in long payloads
- does not match long numeric text that is not a billing error
- still matches real HTTP 402 billing errors
- isCloudCodeAssistFormatError
- matches format errors
- isCloudflareOrHtmlErrorPage
- detects Cloudflare 521 HTML pages
- detects generic 5xx HTML pages
- does not flag non-HTML status lines
- does not flag quoted HTML without a closing html tag
- isCompactionFailureError
- matches compaction overflow failures
- ignores non-compaction overflow errors
- isContextOverflowError
- matches known overflow hints
- matches 'exceeds model context window' in various formats
- matches Kimi 'model token limit' context overflow errors
- matches exceed/context/max_tokens overflow variants
- matches model_context_window_exceeded stop reason surfaced by pi-ai
- matches Chinese context overflow error messages from proxy providers
- ignores normal conversation text mentioning context overflow
- excludes reasoning-required invalid-request errors
- error classifiers
- ignore unrelated errors
- isLikelyContextOverflowError
- matches context overflow hints
- excludes context window too small errors
- excludes rate limit errors that match the broad hint regex
- excludes reasoning-required invalid-request errors
- isTransientHttpError
- returns true for retryable 5xx status codes
- returns false for non-retryable or non-http text
- isFailoverErrorMessage
- matches auth/rate/billing/timeout
- matches abort stop-reason timeout variants
- parseImageSizeError
- parses max MB values from error text
- returns null for unrelated errors
- image dimension errors
- parses anthropic image dimension errors
- classifyFailoverReasonFromHttpStatus – 402 temporary limits
- reclassifies periodic usage limits as rate_limit
- reclassifies org/workspace spend limits as rate_limit
- keeps 402 as billing when explicit billing signals are present
- keeps long 402 payloads with explicit billing text as billing
- keeps 402 as billing without message or with generic message
- matches raw 402 wrappers and status-split payloads for the same message
- keeps explicit 402 rate-limit messages in the rate_limit lane
- keeps plan-upgrade 402 limit messages in billing
- classifyFailoverReason
- classifies documented provider error messages
- classifies internal and compatibility error messages
- classifies OpenAI usage limit errors as rate_limit
- classifies provider high-demand / service-unavailable messages as overloaded
- classifies bare 'service unavailable' as timeout instead of rate_limit (#32828)
- classifies zhipuai Weekly/Monthly Limit Exhausted as rate_limit (#33785)
- classifies permanent auth errors as auth_permanent
- classifies JSON api_error internal server failures as timeout

### src/agents/pi-embedded-helpers.sanitize-session-messages-images.removes-empty-assistant-text-blocks-but-preserves.test.lisp
- sanitizeSessionMessagesImages
- keeps tool call + tool result IDs unchanged by default
- sanitizes tool call + tool result IDs in strict mode (alphanumeric only)
- does not synthesize tool call input when missing
- removes empty assistant text blocks but preserves tool calls
- sanitizes tool ids in strict mode (alphanumeric only)
- sanitizes tool IDs in images-only mode when explicitly enabled
- filters whitespace-only assistant text blocks
- drops assistant messages that only contain empty text
- keeps empty assistant error messages
- leaves non-assistant messages unchanged
- thought_signature stripping
- strips msg_-prefixed thought_signature from assistant message content blocks
- sanitizeGoogleTurnOrdering
- prepends a synthetic user turn when history starts with assistant
- is a no-op when history starts with user

### src/agents/pi-embedded-helpers.sanitizeuserfacingtext.test.lisp
- sanitizeUserFacingText
- strips final tags
- sanitizes role ordering errors
- sanitizes HTTP status errors with error hints
- does not rewrite billing error-shaped text without errorContext
- rewrites billing error-shaped text with errorContext
- sanitizes raw API error payloads
- returns a friendly message for rate limit errors in Error: prefixed payloads
- preserves trailing whitespace and internal newlines
- stripThoughtSignatures
- returns non-array content unchanged
- removes msg_-prefixed thought_signature from content blocks
- preserves blocks without thought_signature
- handles mixed blocks with and without thought_signature
- handles empty array
- handles null/undefined blocks in array
- sanitizeToolCallId
- strict mode (default)
- keeps valid alphanumeric tool call IDs
- strips underscores and hyphens
- strips invalid characters
- strict mode (alphanumeric only)
- strips all non-alphanumeric characters
- strict9 mode (Mistral tool call IDs)
- returns alphanumeric IDs with length 9
- downgradeOpenAIReasoningBlocks
- keeps reasoning signatures when followed by content
- drops orphaned reasoning blocks without following content
- drops object-form orphaned signatures
- keeps non-reasoning thinking signatures
- is idempotent for orphaned reasoning cleanup
- downgradeOpenAIFunctionCallReasoningPairs
- strips fc ids when reasoning cannot be replayed
- keeps fc ids when replayable reasoning is present
- only rewrites tool results paired to the downgraded assistant turn
- normalizeTextForComparison
- isMessagingToolDuplicate

### src/agents/pi-embedded-helpers.validate-turns.test.lisp
- validate turn edge cases
- returns empty array unchanged
- returns single message unchanged
- validateGeminiTurns
- should leave alternating user/assistant unchanged
- should merge consecutive assistant messages
- should preserve metadata from later message when merging
- should handle toolResult messages without merging
- validateAnthropicTurns
- should return alternating user/assistant unchanged
- should merge consecutive user messages
- should merge three consecutive user messages
- keeps newest metadata when merging consecutive users
- merges consecutive users with images and preserves order
- should not merge consecutive assistant messages
- should handle mixed scenario with steering messages
- mergeConsecutiveUserTurns
- keeps newest metadata while merging content
- backfills timestamp from earlier message when missing
- validateAnthropicTurns strips dangling tool_use blocks
- should strip tool_use blocks without matching tool_result
- should preserve tool_use blocks with matching tool_result
- should insert fallback text when all content would be removed
- should handle multiple dangling tool_use blocks
- should handle mixed tool_use with some having matching tool_result
- should not modify messages when next is not user
- is replay-safe across repeated validation passes
- does not crash when assistant content is non-array

### src/agents/pi-embedded-helpers/thinking.test.lisp
- pickFallbackThinkingLevel
- returns undefined for empty message
- returns undefined for undefined message
- extracts supported values from error message
- skips already attempted values
- falls back to "off" when error says "not supported" without listing values
- falls back to "off" for generic not-supported messages
- returns undefined if "off" was already attempted
- returns undefined for unrelated error messages

### src/agents/pi-embedded-runner-extraparams.live.test.lisp
- applies config maxTokens to openai streamFn
- sanitizes Gemini 3.1 thinking payload and keeps image parts with reasoning enabled

### src/agents/pi-embedded-runner-extraparams.test.lisp
- resolveExtraParams
- returns undefined with no model config
- returns params for exact provider/model key
- ignores unrelated model entries
- returns per-agent params when agentId matches
- merges per-agent params over global model defaults
- preserves higher-precedence agent parallelToolCalls override across alias styles
- ignores per-agent params when agentId does not match
- applyExtraParamsToAgent
- does not inject reasoning when thinkingLevel is off (default) for OpenRouter
- injects reasoning.effort when thinkingLevel is non-off for OpenRouter
- removes legacy reasoning_effort and keeps reasoning unset when thinkingLevel is off
- does not inject effort when payload already has reasoning.max_tokens
- does not inject reasoning.effort for x-ai/grok models on OpenRouter (#32039)
- injects parallel_tool_calls for openai-completions payloads when configured
- injects parallel_tool_calls for openai-responses payloads when configured
- does not inject parallel_tool_calls for unsupported APIs
- lets runtime override win across alias styles for parallel_tool_calls
- lets null runtime override suppress inherited parallel_tool_calls injection
- warns and skips invalid parallel_tool_calls values
- normalizes thinking=off to null for SiliconFlow Pro models
- keeps thinking=off unchanged for non-Pro SiliconFlow model IDs
- maps thinkingLevel=off to Moonshot thinking.type=disabled
- maps non-off thinking levels to Moonshot thinking.type=enabled and normalizes tool_choice
- respects explicit Moonshot thinking param from model config
- normalizes kimi-coding anthropic tools to OpenAI function format
- does not rewrite anthropic tool schema for non-kimi endpoints
- removes invalid negative Google thinkingBudget and maps Gemini 3.1 to thinkingLevel
- keeps valid Google thinkingBudget unchanged
- adds OpenRouter attribution headers to stream options
- passes configured websocket transport through stream options
- passes configured websocket transport through stream options for openai-codex gpt-5.4
- defaults Codex transport to auto (WebSocket-first)
- defaults OpenAI transport to auto (WebSocket-first)
- lets runtime options override OpenAI default transport
- allows disabling OpenAI websocket warm-up via model params
- lets runtime options override configured OpenAI websocket warm-up
- allows forcing Codex transport to Server-Sent Events
- lets runtime options override configured transport
- falls back to Codex default transport when configured value is invalid
- disables prompt caching for non-Anthropic Bedrock models
- keeps Anthropic Bedrock models eligible for provider-side caching
- passes through explicit cacheRetention for Anthropic Bedrock models
- adds Anthropic 1M beta header when context1m is enabled for Opus/Sonnet
- does not add Anthropic 1M beta header when context1m is not enabled
- skips context1m beta for OAuth tokens but preserves OAuth-required betas
- merges existing anthropic-beta headers with configured betas
- ignores context1m for non-Opus/Sonnet Anthropic models
- forces store=true for direct OpenAI Responses payloads
- injects configured OpenAI service_tier into Responses payloads
- preserves caller-provided service_tier values
- does not inject service_tier for non-openai providers
- does not inject service_tier for proxied openai base URLs
- does not inject service_tier for openai provider routed to Azure base URLs
- warns and skips service_tier injection for invalid serviceTier values
- does not force store for OpenAI Responses routed through non-OpenAI base URLs
- does not force store for OpenAI Responses when baseUrl is empty
- strips store from payload for models that declare supportsStore=false
- strips store from payload for non-OpenAI responses providers with supportsStore=false
- keeps existing context_management when stripping store for supportsStore=false models
- auto-injects OpenAI Responses context_management compaction for direct OpenAI models
- does not auto-inject OpenAI Responses context_management for Azure by default
- allows explicitly enabling OpenAI Responses context_management compaction
- preserves existing context_management payload values
- allows disabling OpenAI Responses context_management compaction via model params

### src/agents/pi-embedded-runner.applygoogleturnorderingfix.test.lisp
- applyGoogleTurnOrderingFix
- prepends a bootstrap once and records a marker for Google models
- skips non-Google models

### src/agents/pi-embedded-runner.buildembeddedsandboxinfo.test.lisp
- buildEmbeddedSandboxInfo
- returns undefined when sandbox is missing
- maps sandbox context into prompt info
- includes elevated info when allowed

### src/agents/pi-embedded-runner.compaction-safety-timeout.test.lisp
- compactWithSafetyTimeout
- rejects with timeout when compaction never settles
- returns result and clears timer when compaction settles first
- preserves compaction errors and clears timer

### src/agents/pi-embedded-runner.createsystempromptoverride.test.lisp
- createSystemPromptOverride
- returns the override prompt trimmed
- returns an empty string for blank overrides

### src/agents/pi-embedded-runner.e2e.test.lisp
- runEmbeddedPiAgent
- handles prompt error paths without dropping user state
- preserves existing transcript entries across an additional turn
- repairs orphaned user messages and continues

### src/agents/pi-embedded-runner.get-dm-history-limit-from-session-key.falls-back-provider-default-per-dm-not.test.lisp
- getDmHistoryLimitFromSessionKey
- falls back to provider default when per-DM not set
- returns per-DM override for agent-prefixed keys
- handles userId with colons (e.g., email)
- returns undefined when per-DM historyLimit is not set
- returns 0 when per-DM historyLimit is explicitly 0 (unlimited)

### src/agents/pi-embedded-runner.get-dm-history-limit-from-session-key.returns-undefined-sessionkey-is-undefined.test.lisp
- getDmHistoryLimitFromSessionKey
- returns undefined when sessionKey is undefined
- returns undefined when config is undefined
- returns dmHistoryLimit for telegram provider
- returns dmHistoryLimit for whatsapp provider
- returns dmHistoryLimit for agent-prefixed session keys
- strips thread suffix from dm session keys
- keeps non-numeric thread markers in dm ids
- returns historyLimit for channel session kinds when configured
- returns undefined for non-dm/channel/group session kinds
- returns undefined for unknown provider
- returns undefined when provider config has no dmHistoryLimit
- handles all supported providers
- handles per-DM overrides for all supported providers
- returns per-DM override when set
- returns historyLimit for channel sessions for all providers
- returns historyLimit for group sessions
- returns undefined for channel sessions when historyLimit is not configured
- backward compatibility
- accepts both legacy :dm: and new :direct: session keys

### src/agents/pi-embedded-runner.guard.test.lisp
- guardSessionManager integration
- persists synthetic toolResult before subsequent assistant message

### src/agents/pi-embedded-runner.guard.waitforidle-before-flush.test.lisp
- flushPendingToolResultsAfterIdle
- waits for idle so real tool results can land before flush
- flushes pending tool call after timeout when idle never resolves
- clears pending without synthetic flush when timeout cleanup is requested
- clears timeout handle when waitForIdle resolves first

### src/agents/pi-embedded-runner.history-limit-from-session-key.test.lisp
- getDmHistoryLimitFromSessionKey
- keeps backward compatibility for dm/direct session kinds
- returns historyLimit for channel and group session kinds
- returns undefined for unsupported session kinds

### src/agents/pi-embedded-runner.limithistoryturns.test.lisp
- limitHistoryTurns
- returns all messages when limit is undefined
- returns all messages when limit is 0
- returns all messages when limit is negative
- returns empty array when messages is empty
- keeps all messages when fewer user turns than limit
- limits to last N user turns
- handles single user turn limit
- handles messages with multiple assistant responses per user turn
- preserves message content integrity

### src/agents/pi-embedded-runner.openai-tool-id-preservation.test.lisp
- sanitizeSessionHistory openai tool id preservation

### src/agents/pi-embedded-runner.resolvesessionagentids.test.lisp
- resolveSessionAgentIds
- falls back to the configured default when sessionKey is missing
- falls back to the configured default when sessionKey is non-agent
- falls back to the configured default for global sessions
- keeps the agent id for provider-qualified agent sessions
- uses the agent id from agent session keys
- uses explicit agentId when sessionKey is missing
- prefers explicit agentId over non-agent session keys

### src/agents/pi-embedded-runner.run-embedded-pi-agent.auth-profile-rotation.e2e.test.lisp
- runEmbeddedPiAgent auth profile rotation
- refreshes copilot token after auth error and retries once
- allows another auth refresh after a successful retry
- does not reschedule copilot refresh after shutdown
- rotates for auto-pinned profiles across retryable stream failures
- rotates for overloaded assistant failures across auto-pinned profiles
- rotates for overloaded prompt failures across auto-pinned profiles
- rotates on timeout without cooling down the timed-out profile
- rotates on bare service unavailable without cooling down the profile
- does not rotate for compaction timeouts
- does not rotate for user-pinned profiles
- honors user-pinned profiles even when in cooldown
- ignores user-locked profile when provider mismatches
- skips profiles in cooldown during initial selection
- fails over when all profiles are in cooldown and fallbacks are configured
- can probe one cooldowned profile when transient cooldown probe is explicitly allowed
- can probe one cooldowned profile when overloaded cooldown is explicitly probeable
- treats agent-level fallbacks as configured when defaults have none
- fails over with disabled reason when all profiles are unavailable
- fails over when auth is unavailable and fallbacks are configured
- uses the active erroring model in billing failover errors
- skips profiles in cooldown when rotating after failure

### src/agents/pi-embedded-runner.sanitize-session-history.policy.test.lisp
- sanitizeSessionHistory e2e smoke
- applies full sanitize policy for google model APIs
- keeps images-only sanitize policy without tool-call id rewriting for openai-responses
- downgrades openai reasoning blocks when the model snapshot changed

### src/agents/pi-embedded-runner.sanitize-session-history.test.lisp
- sanitizeSessionHistory
- sanitizes tool call ids for Google model APIs
- sanitizes tool call ids with strict9 for Mistral models
- sanitizes tool call ids for Anthropic APIs
- does not sanitize tool call ids for openai-responses
- sanitizes tool call ids for openai-completions
- prepends a bootstrap user turn for strict OpenAI-compatible assistant-first history
- annotates inter-session user messages before context sanitization
- drops stale assistant usage snapshots kept before latest compaction summary
- preserves fresh assistant usage snapshots created after latest compaction summary
- adds a zeroed assistant usage snapshot when usage is missing
- normalizes mixed partial assistant usage fields to numeric totals
- preserves existing usage cost while normalizing token fields
- preserves unknown cost when token fields already match
- drops stale usage when compaction summary appears before kept assistant messages
- keeps fresh usage after compaction timestamp in summary-first ordering
- keeps reasoning-only assistant messages for openai-responses
- synthesizes missing tool results for openai-responses after repair
- drops tool calls that are not in the allowed tool set
- downgrades orphaned openai reasoning even when the model has not changed
- downgrades orphaned openai reasoning when the model changes too
- drops orphaned toolResult entries when switching from openai history to anthropic
- drops assistant thinking blocks for github-copilot models
- preserves assistant turn when all content is thinking blocks (github-copilot)
- preserves tool_use blocks when dropping thinking blocks (github-copilot)
- does not drop thinking blocks for non-copilot providers
- does not drop thinking blocks for non-claude copilot models

### src/agents/pi-embedded-runner.splitsdktools.test.lisp
- splitSdkTools
- routes all tools to customTools when sandboxed
- routes all tools to customTools even when not sandboxed

### src/agents/pi-embedded-runner/cache-ttl.test.lisp
- isCacheTtlEligibleProvider
- allows anthropic
- allows moonshot and zai providers
- is case-insensitive for native providers
- allows openrouter cache-ttl models
- rejects unsupported providers and models

### src/agents/pi-embedded-runner/compact.hooks.test.lisp
- compactEmbeddedPiSessionDirect hooks
- emits internal + plugin compaction hooks with counts
- uses sessionId as hook session key fallback when sessionKey is missing
- applies validated transcript before hooks even when it becomes empty
- registers the Ollama api provider before compaction

### src/agents/pi-embedded-runner/extensions.test.lisp
- buildEmbeddedExtensionFactories
- does not opt safeguard mode into quality-guard retries
- wires explicit safeguard quality-guard runtime flags

### src/agents/pi-embedded-runner/extra-params.cache-retention-default.test.lisp
- cacheRetention default behavior
- returns 'short' for Anthropic when not configured
- respects explicit 'none' config
- respects explicit 'long' config
- respects legacy cacheControlTtl config
- returns undefined for non-Anthropic providers
- prefers explicit cacheRetention over default
- works with extraParamsOverride

### src/agents/pi-embedded-runner/extra-params.kilocode.test.lisp
- extra-params: Kilocode wrapper
- injects X-KILOCODE-FEATURE header with default value
- reads X-KILOCODE-FEATURE from KILOCODE_FEATURE env var
- cannot be overridden by caller headers
- does not inject header for non-kilocode providers
- extra-params: Kilocode kilo/auto reasoning
- does not inject reasoning.effort for kilo/auto
- injects reasoning.effort for non-auto kilocode models
- does not inject reasoning.effort for x-ai models

### src/agents/pi-embedded-runner/extra-params.openrouter-cache-control.test.lisp
- extra-params: OpenRouter Anthropic cache_control
- injects cache_control into system message for OpenRouter Anthropic models
- adds cache_control to last content block when system message is already array
- does not inject cache_control for OpenRouter non-Anthropic models
- leaves payload unchanged when no system message exists

### src/agents/pi-embedded-runner/extra-params.zai-tool-stream.test.lisp
- extra-params: Z.AI tool_stream support
- injects tool_stream=true for zai provider by default
- does not inject tool_stream for non-zai providers
- allows disabling tool_stream via params

### src/agents/pi-embedded-runner/google.test.lisp
- sanitizeToolsForGoogle
- strips unsupported schema keywords for Google providers
- returns original tools for non-google providers

### src/agents/pi-embedded-runner/kilocode.test.lisp
- kilocode cache-ttl eligibility
- is eligible when model starts with anthropic/
- is eligible with other anthropic models
- is not eligible for non-anthropic models on kilocode
- is case-insensitive for provider name

### src/agents/pi-embedded-runner/model.forward-compat.test.lisp
- pi embedded model e2e smoke
- attaches provider ids and provider-level baseUrl for inline models
- builds an openai-codex forward-compat fallback for gpt-5.3-codex
- builds an openai-codex forward-compat fallback for gpt-5.4
- keeps unknown-model errors for non-forward-compat IDs
- builds a google-gemini-cli forward-compat fallback for gemini-3.1-pro-preview
- builds a google-gemini-cli forward-compat fallback for gemini-3.1-flash-preview
- builds a google-gemini-cli forward-compat fallback for gemini-3.1-flash-lite-preview
- builds a google forward-compat fallback for gemini-3.1-pro-preview
- builds a google forward-compat fallback for gemini-3.1-flash-lite-preview
- keeps unknown-model errors for unrecognized google-gemini-cli model IDs

### src/agents/pi-embedded-runner/model.test.lisp
- buildInlineProviderModels
- attaches provider ids to inline models
- inherits baseUrl from provider when model does not specify it
- inherits api from provider when model does not specify it
- model-level api takes precedence over provider-level api
- inherits both baseUrl and api from provider config
- merges provider-level headers into inline models
- omits headers when neither provider nor model specifies them
- preserves literal marker-shaped headers in inline provider models
- resolveModel
- includes provider baseUrl in fallback model
- includes provider headers in provider fallback model
- preserves literal marker-shaped provider headers in fallback models
- drops marker headers from discovered models.json entries
- prefers matching configured model metadata for fallback token limits
- propagates reasoning from matching configured fallback model
- prefers configured provider api metadata over discovered registry model
- prefers exact provider config over normalized alias match when both keys exist
- builds an openai-codex fallback for gpt-5.3-codex
- builds an openai-codex fallback for gpt-5.4
- applies provider overrides to openai gpt-5.4 forward-compat models
- builds an anthropic forward-compat fallback for claude-opus-4-6
- builds an anthropic forward-compat fallback for claude-sonnet-4-6
- builds a zai forward-compat fallback for glm-5
- keeps unknown-model errors when no antigravity thinking template exists
- keeps unknown-model errors when no antigravity non-thinking template exists
- keeps unknown-model errors for non-gpt-5 openai-codex ids
- uses codex fallback even when openai-codex provider is configured
- includes auth hint for unknown ollama models (#17328)
- includes auth hint for unknown vllm models
- does not add auth hint for non-local providers
- applies provider baseUrl override to registry-found models
- applies provider headers override to registry-found models
- does not override when no provider config exists

### src/agents/pi-embedded-runner/run.overflow-compaction.loop.test.lisp
- overflow compaction in run loop
- retries after successful compaction on context overflow promptError
- retries after successful compaction on likely-overflow promptError variants
- returns error if compaction fails
- falls back to tool-result truncation and retries when oversized results are detected
- retries compaction up to 3 times before giving up
- succeeds after second compaction attempt
- does not attempt compaction for compaction_failure errors
- retries after successful compaction on assistant context overflow errors
- does not treat stale assistant overflow as current-attempt overflow when promptError is non-overflow
- returns an explicit timeout payload when the run times out before producing any reply
- sets promptTokens from the latest model call usage, not accumulated attempt usage

### src/agents/pi-embedded-runner/run.overflow-compaction.test.lisp
- runEmbeddedPiAgent overflow compaction trigger routing
- passes precomputed legacy before_agent_start result into the attempt
- passes resolved auth profile into run attempts for context-engine afterTurn propagation
- passes trigger=overflow when retrying compaction after context overflow
- does not reset compaction attempt budget after successful tool-result truncation
- returns retry_limit when repeated retries never converge

### src/agents/pi-embedded-runner/run/attempt.test.lisp
- resolvePromptBuildHookResult
- reuses precomputed legacy before_agent_start result without invoking hook again
- calls legacy hook when precomputed result is absent
- merges prompt-build and legacy context fields in deterministic order
- composeSystemPromptWithHookContext
- returns undefined when no hook system context is provided
- builds prepend/base/append system prompt order
- avoids blank separators when base system prompt is empty
- resolvePromptModeForSession
- uses minimal mode for subagent sessions
- uses full mode for cron sessions
- resolveAttemptFsWorkspaceOnly
- uses global tools.fs.workspaceOnly when agent has no override
- prefers agent-specific tools.fs.workspaceOnly override
- wrapStreamFnTrimToolCallNames
- trims whitespace from live streamed tool call names and final result message
- supports async stream functions that return a promise
- normalizes common tool aliases when the canonical name is allowed
- maps provider-prefixed tool names to allowed canonical tools
- normalizes toolUse and functionCall names before dispatch
- preserves multi-segment tool suffixes when dropping provider prefixes
- does not collapse whitespace-only tool names to empty strings
- assigns fallback ids to missing/blank tool call ids in streamed and final messages
- trims surrounding whitespace on tool call ids
- isOllamaCompatProvider
- detects native ollama provider id
- detects localhost Ollama OpenAI-compatible endpoint
- does not misclassify non-local OpenAI-compatible providers
- detects remote Ollama-compatible endpoint when provider id hints ollama
- detects IPv6 loopback Ollama OpenAI-compatible endpoint
- does not classify arbitrary remote hosts on 11434 without ollama provider hint
- resolveOllamaBaseUrlForRun
- prefers provider baseUrl over model baseUrl
- falls back to model baseUrl when provider baseUrl is missing
- falls back to native default when neither baseUrl is configured
- wrapOllamaCompatNumCtx
- injects num_ctx and preserves downstream onPayload hooks
- resolveOllamaCompatNumCtxEnabled
- defaults to true when config is missing
- defaults to true when provider config is missing
- returns false when provider flag is explicitly disabled
- shouldInjectOllamaCompatNumCtx
- requires openai-completions adapter
- respects provider flag disablement
- decodeHtmlEntitiesInObject
- decodes HTML entities in string values
- recursively decodes nested objects
- passes through non-string primitives unchanged
- returns strings without entities unchanged
- decodes numeric character references
- prependSystemPromptAddition
- prepends context-engine addition to the system prompt
- returns the original system prompt when no addition is provided
- buildAfterTurnLegacyCompactionParams
- includes resolved auth profile fields for context-engine afterTurn compaction

### src/agents/pi-embedded-runner/run/compaction-timeout.test.lisp
- compaction-timeout helpers
- flags compaction timeout consistently for internal and external timeout sources
- does not flag when timeout is false
- uses pre-compaction snapshot when compaction timeout occurs
- falls back to current snapshot when pre-compaction snapshot is unavailable

### src/agents/pi-embedded-runner/run/history-image-prune.test.lisp
- pruneProcessedHistoryImages
- prunes image blocks from user messages that already have assistant replies
- does not prune latest user message when no assistant response exists yet
- does not change messages when no assistant turn exists

### src/agents/pi-embedded-runner/run/images.test.lisp
- detectImageReferences
- detects absolute file paths with common extensions
- detects relative paths starting with ./
- detects relative paths starting with ../
- detects home directory paths starting with ~/
- detects multiple image references in a prompt
- handles various image extensions
- deduplicates repeated image references
- dedupe casing follows host filesystem conventions
- returns empty array when no images found
- ignores non-image file extensions
- handles paths inside quotes (without spaces)
- handles paths in parentheses
- detects [Image: source: ...] format from messaging systems
- handles complex message attachment paths
- detects multiple images in [media attached: ...] format
- does not double-count path and url in same bracket
- ignores remote URLs entirely (local-only)
- handles single file format with URL (no index)
- handles paths with spaces in filename
- modelSupportsImages
- returns true when model input includes image
- returns false when model input does not include image
- returns false when model input is undefined
- returns false when model input is empty
- loadImageFromRef
- allows sandbox-validated host paths outside default media roots
- detectAndLoadPromptImages
- returns no images for non-vision models even when existing images are provided
- returns no detected refs when prompt has no image references
- blocks prompt image refs outside workspace when sandbox workspaceOnly is enabled

### src/agents/pi-embedded-runner/run/payloads.errors.test.lisp
- buildEmbeddedRunPayloads
- suppresses raw API error JSON when the assistant errored
- suppresses pretty-printed error JSON that differs from the errorMessage
- suppresses raw error JSON from fallback assistant text
- includes provider and model context for billing errors
- suppresses raw error JSON even when errorMessage is missing
- does not suppress error-shaped JSON when the assistant did not error
- adds a fallback error when a tool fails and no assistant output exists
- does not add tool error fallback when assistant output exists
- does not add synthetic completion text when tools run without final assistant text
- does not add synthetic completion text for channel sessions
- does not add synthetic completion text for group sessions
- does not add synthetic completion text when messaging tool already delivered output
- does not add synthetic completion text when the run still has a tool error
- does not add synthetic completion text when no tools ran
- adds tool error fallback when the assistant only invoked tools and verbose mode is on
- does not add tool error fallback when assistant text exists after tool calls
- suppresses recoverable tool errors containing 'required' for non-mutating tools
- suppresses recoverable tool errors containing 'missing' for non-mutating tools
- suppresses recoverable tool errors containing 'invalid' for non-mutating tools
- suppresses non-mutating non-recoverable tool errors when messages.suppressToolErrors is enabled
- suppresses mutating tool errors when suppressToolErrorWarnings is enabled
- shows mutating tool errors even when assistant output exists
- does not treat session_status read failures as mutating when explicitly flagged
- dedupes identical tool warning text already present in assistant output
- includes non-recoverable tool error details when verbose mode is on

### src/agents/pi-embedded-runner/run/payloads.test.lisp
- buildEmbeddedRunPayloads tool-error warnings
- suppresses exec tool errors when verbose mode is off
- shows exec tool errors when verbose mode is on
- keeps non-exec mutating tool failures visible
- suppresses sessions_send errors to avoid leaking transient relay failures
- suppresses sessions_send errors even when marked mutating

### src/agents/pi-embedded-runner/sanitize-session-history.tool-result-details.test.lisp
- sanitizeSessionHistory toolResult details stripping
- strips toolResult.details so untrusted payloads are not fed back to the model

### src/agents/pi-embedded-runner/skills-runtime.integration.test.lisp
- resolveEmbeddedRunSkillEntries (integration)
- loads bundled diffs skill when explicitly enabled in config
- skips bundled diffs skill when config is missing

### src/agents/pi-embedded-runner/skills-runtime.test.lisp
- resolveEmbeddedRunSkillEntries
- loads skill entries with config when no resolved snapshot skills exist
- skips skill entry loading when resolved snapshot skills are present

### src/agents/pi-embedded-runner/system-prompt.test.lisp
- applySystemPromptOverrideToSession
- applies a string override to the session system prompt
- trims whitespace from string overrides
- applies a function override to the session system prompt
- sets _rebuildSystemPrompt that returns the override

### src/agents/pi-embedded-runner/thinking.test.lisp
- isAssistantMessageWithContent
- accepts assistant messages with array content and rejects others
- dropThinkingBlocks
- returns the original reference when no thinking blocks are present
- drops thinking blocks while preserving non-thinking assistant content
- keeps assistant turn structure when all content blocks were thinking

### src/agents/pi-embedded-runner/tool-result-context-guard.test.lisp
- installToolResultContextGuard
- compacts oldest-first when total context overflows, even if each result fits individually
- keeps compacting oldest-first until context is back under budget
- survives repeated large tool results by compacting older outputs before later turns
- truncates an individually oversized tool result with a context-limit notice
- keeps compacting oldest-first until overflow clears, including the newest tool result when needed
- wraps an existing transformContext and guards the transformed output
- handles legacy role=tool string outputs when enforcing context budget
- drops oversized read-tool details payloads when compacting tool results

### src/agents/pi-embedded-runner/tool-result-truncation.test.lisp
- truncateToolResultText
- returns text unchanged when under limit
- truncates text that exceeds limit
- preserves at least MIN_KEEP_CHARS (2000)
- tries to break at newline boundary
- supports custom suffix and min keep chars
- getToolResultTextLength
- sums all text blocks in tool results
- returns zero for non-toolResult messages
- truncateToolResultMessage
- truncates with a custom suffix
- calculateMaxToolResultChars
- scales with context window size
- caps at HARD_MAX_TOOL_RESULT_CHARS for very large windows
- returns reasonable size for 128K context
- isOversizedToolResult
- returns false for small tool results
- returns true for oversized tool results
- returns false for non-toolResult messages
- truncateOversizedToolResultsInMessages
- returns unchanged messages when nothing is oversized
- truncates oversized tool results
- preserves non-toolResult messages
- handles multiple oversized tool results
- sessionLikelyHasOversizedToolResults
- returns false when no tool results are oversized
- returns true when a tool result is oversized
- returns false for empty messages
- truncateToolResultText head+tail strategy
- preserves error content at the tail when present
- uses simple head truncation when tail has no important content

### src/agents/pi-embedded-runner/usage-reporting.test.lisp
- runEmbeddedPiAgent usage reporting
- forwards sender identity fields into embedded attempts
- reports total usage from the last turn instead of accumulated total

### src/agents/pi-embedded-subscribe.block-reply-rejections.test.lisp
- subscribeEmbeddedPiSession block reply rejections
- contains rejected async text_end block replies
- contains rejected async message_end block replies

### src/agents/pi-embedded-subscribe.code-span-awareness.test.lisp
- subscribeEmbeddedPiSession thinking tag code span awareness
- does not strip thinking tags inside inline code backticks
- does not strip thinking tags inside fenced code blocks
- still strips actual thinking tags outside code spans

### src/agents/pi-embedded-subscribe.handlers.lifecycle.test.lisp
- handleAgentEnd
- logs the resolved error message when run ends with assistant error
- keeps non-error run-end logging on debug only

### src/agents/pi-embedded-subscribe.handlers.messages.test.lisp
- resolveSilentReplyFallbackText
- replaces NO_REPLY with latest messaging tool text when available
- keeps original text when response is not NO_REPLY
- keeps NO_REPLY when there is no messaging tool text to mirror

### src/agents/pi-embedded-subscribe.handlers.tools.media.test.lisp
- handleToolExecutionEnd media emission
- does not warn for read tool when path is provided via file_path alias
- emits media when verbose is off and tool result has MEDIA: path
- does NOT emit local media for untrusted tools
- emits remote media for untrusted tools
- does NOT emit media when verbose is full (emitToolOutput handles it)
- does NOT emit media for error results
- does NOT emit when tool result has no media
- does NOT emit media for <media:audio> placeholder text
- does NOT emit media for malformed MEDIA:-prefixed prose
- emits media from details.path fallback when no MEDIA: text

### src/agents/pi-embedded-subscribe.handlers.tools.test.lisp
- handleToolExecutionStart read path checks
- does not warn when read tool uses file_path alias
- warns when read tool has neither path nor file_path
- awaits onBlockReplyFlush before continuing tool start processing
- handleToolExecutionEnd cron.add commitment tracking
- increments successfulCronAdds when cron add succeeds
- does not increment successfulCronAdds when cron add fails
- messaging tool media URL tracking
- tracks media arg from messaging tool as pending
- commits pending media URL on tool success
- commits mediaUrls from tool result payload
- trims messagingToolSentMediaUrls to 200 on commit (FIFO)
- discards pending media URL on tool error

### src/agents/pi-embedded-subscribe.lifecycle-billing-error.test.lisp
- subscribeEmbeddedPiSession lifecycle billing errors
- includes provider and model context in lifecycle billing errors

### src/agents/pi-embedded-subscribe.reply-tags.test.lisp
- subscribeEmbeddedPiSession reply tags
- carries reply_to_current across tag-only block chunks
- flushes trailing directive tails on stream end
- streams partial replies past reply_to tags split across chunks

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.calls-onblockreplyflush-before-tool-execution-start-preserve.test.lisp
- subscribeEmbeddedPiSession
- calls onBlockReplyFlush before tool_execution_start to preserve message boundaries
- flushes buffered block chunks before tool execution

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.does-not-append-text-end-content-is.test.lisp
- subscribeEmbeddedPiSession

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.does-not-call-onblockreplyflush-callback-is-not.test.lisp
- subscribeEmbeddedPiSession
- does not call onBlockReplyFlush when callback is not provided

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.does-not-duplicate-text-end-repeats-full.test.lisp
- subscribeEmbeddedPiSession
- does not duplicate when text_end repeats full content
- does not duplicate block chunks when text_end repeats full content

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.does-not-emit-duplicate-block-replies-text.test.lisp
- subscribeEmbeddedPiSession
- does not emit duplicate block replies when text_end repeats
- does not duplicate assistantTexts when message_end repeats
- does not duplicate assistantTexts when message_end repeats with trailing whitespace changes
- does not duplicate assistantTexts when message_end repeats with reasoning blocks
- populates assistantTexts for non-streaming models with chunking enabled

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.emits-block-replies-text-end-does-not.test.lisp
- subscribeEmbeddedPiSession
- emits block replies on text_end and does not duplicate on message_end
- does not duplicate when message_end flushes and a late text_end arrives

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.emits-reasoning-as-separate-message-enabled.test.lisp
- subscribeEmbeddedPiSession
- emits reasoning as a separate message when enabled

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.filters-final-suppresses-output-without-start-tag.test.lisp
- subscribeEmbeddedPiSession
- filters to <final> and suppresses output without a start tag
- suppresses agent events on message_end without <final> tags when enforced
- emits via streaming when <final> tags are present and enforcement is on
- does not require <final> when enforcement is off
- emits block replies on message_end

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.includes-canvas-action-metadata-tool-summaries.test.lisp
- subscribeEmbeddedPiSession
- includes canvas action metadata in tool summaries
- skips tool summaries when shouldEmitToolResult is false
- emits tool summaries when shouldEmitToolResult overrides verbose

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.keeps-assistanttexts-final-answer-block-replies-are.test.lisp
- subscribeEmbeddedPiSession
- keeps assistantTexts to the final answer when block replies are disabled
- suppresses partial replies when reasoning is enabled and block replies are disabled

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.keeps-indented-fenced-blocks-intact.test.lisp
- subscribeEmbeddedPiSession
- keeps indented fenced blocks intact
- accepts longer fence markers for close

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.reopens-fenced-blocks-splitting-inside-them.test.lisp
- subscribeEmbeddedPiSession
- reopens fenced blocks when splitting inside them
- avoids splitting inside tilde fences

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.splits-long-single-line-fenced-blocks-reopen.test.lisp
- subscribeEmbeddedPiSession
- splits long single-line fenced blocks with reopen/close
- waits for auto-compaction retry and clears buffered text
- resolves after compaction ends without retry
- resets assistant usage to a zero snapshot after compaction without retry

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.streams-soft-chunks-paragraph-preference.test.lisp
- subscribeEmbeddedPiSession
- streams soft chunks with paragraph preference
- avoids splitting inside fenced code blocks

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.subscribeembeddedpisession.test.lisp
- subscribeEmbeddedPiSession
- streams native thinking_delta events and signals reasoning end
- emits reasoning end once when native and tagged reasoning end overlap
- emits delta chunks in agent events for streaming assistant text
- emits agent events on message_end for non-streaming assistant text
- does not emit duplicate agent events when message_end repeats
- skips agent events when cleaned text rewinds mid-stream
- emits agent events when media arrives without text
- keeps unresolved mutating failure when an unrelated tool succeeds
- clears unresolved mutating failure when the same action succeeds
- keeps unresolved mutating failure when same tool succeeds on a different target
- keeps unresolved session_status model-mutation failure on later read-only status success
- emits lifecycle:error event on agent_end when last assistant message was an error

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.suppresses-message-end-block-replies-message-tool.test.lisp
- subscribeEmbeddedPiSession
- suppresses message_end block replies when the message tool already sent
- does not suppress message_end replies when message tool reports error
- clears block reply state on message_start

### src/agents/pi-embedded-subscribe.subscribe-embedded-pi-session.waits-multiple-compaction-retries-before-resolving.test.lisp
- subscribeEmbeddedPiSession
- waits for multiple compaction retries before resolving
- does not count compaction until end event
- does not count compaction when result is absent
- emits compaction events on the agent event bus
- rejects compaction wait with AbortError when unsubscribed
- emits tool summaries at tool start when verbose is on
- includes browser action metadata in tool summaries
- emits exec output in full verbose mode and includes PTY indicator

### src/agents/pi-embedded-subscribe.tools.extract.test.lisp
- extractMessagingToolSend
- uses channel as provider for message tool
- prefers provider when both provider and channel are set
- accepts target alias when to is omitted

### src/agents/pi-embedded-subscribe.tools.media.test.lisp
- extractToolResultMediaPaths
- returns empty array for null/undefined
- returns empty array for non-object
- returns empty array when content is missing
- returns empty array when content has no text or image blocks
- extracts MEDIA: path from text content block
- extracts MEDIA: path with extra text in the block
- extracts multiple MEDIA: paths from different text blocks
- falls back to details.path when image content exists but no MEDIA: text
- returns empty array when image content exists but no MEDIA: and no details.path
- does not fall back to details.path when MEDIA: paths are found
- handles backtick-wrapped MEDIA: paths
- ignores null/undefined items in content array
- returns empty array for text-only results without MEDIA:
- ignores details.path when no image content exists
- handles details.path with whitespace
- skips empty details.path
- does not match <media:audio> placeholder as a MEDIA: token
- does not match <media:image> placeholder as a MEDIA: token
- does not match other media placeholder variants
- does not match mid-line MEDIA: in documentation text
- does not treat malformed MEDIA:-prefixed prose as a file path
- still extracts MEDIA: at line start after other text lines
- extracts indented MEDIA: line
- extracts valid MEDIA: line while ignoring <media:audio> on another line
- extracts multiple MEDIA: lines from a single text block

### src/agents/pi-embedded-subscribe.tools.test.lisp
- extractToolErrorMessage
- ignores non-error status values
- keeps error-like status values

### src/agents/pi-embedded-utils.test.lisp
- extractAssistantText
- strips tool-only Minimax invocation XML from text
- strips multiple tool invocations
- keeps invoke snippets without Minimax markers
- preserves normal text without tool invocations
- sanitizes HTTP-ish error text only when stopReason is error
- does not rewrite normal text that references billing plans
- strips Minimax tool invocations with extra attributes
- strips minimax tool_call open and close tags
- ignores invoke blocks without minimax markers
- strips invoke blocks when minimax markers are present elsewhere
- strips invoke blocks with nested tags
- strips tool XML mixed with regular content
- handles multiple invoke blocks in one message
- handles stray closing tags without opening tags
- handles multiple text blocks
- strips downgraded Gemini tool call text representations
- strips multiple downgraded tool calls
- strips tool results for downgraded calls
- preserves text around downgraded tool calls
- preserves trailing text after downgraded tool call blocks
- handles multiple text blocks with tool calls and results
- strips reasoning/thinking tag variants
- formatReasoningMessage
- returns empty string for whitespace-only input
- wraps single line in italics
- wraps each line separately for multiline text (Telegram fix)
- preserves empty lines between reasoning text
- handles mixed empty and non-empty lines
- trims leading/trailing whitespace
- stripDowngradedToolCallText
- strips downgraded marker blocks while preserving surrounding user-facing text
- promoteThinkingTagsToBlocks
- does not crash on malformed null content entries
- does not crash on undefined content entries
- passes through well-formed content unchanged when no thinking tags
- empty input handling
- returns empty string

### src/agents/pi-extensions/compaction-safeguard.test.lisp
- compaction-safeguard tool failures
- formats tool failures with meta and summary
- dedupes by toolCallId and handles empty output
- caps the number of failures and adds overflow line
- omits section when there are no tool failures
- computeAdaptiveChunkRatio
- returns BASE_CHUNK_RATIO for normal messages
- reduces ratio when average message > 10% of context
- respects MIN_CHUNK_RATIO floor
- handles empty message array
- handles single huge message
- isOversizedForSummary
- returns false for small messages
- returns true for messages > 50% of context
- applies safety margin
- compaction-safeguard runtime registry
- stores and retrieves config by session manager identity
- returns null for unknown session manager
- clears entry when value is null
- ignores non-object session managers
- isolates different session managers
- stores and retrieves model from runtime (fallback for compact.lisp workflow)
- stores and retrieves contextWindowTokens from runtime
- stores and retrieves combined runtime values
- wires oversized safeguard runtime values when config validation is bypassed
- compaction-safeguard recent-turn preservation
- preserves the most recent user/assistant messages
- drops orphaned tool results from preserved assistant turns
- includes preserved tool results in the preserved-turns section
- formats preserved non-text messages with placeholders
- keeps non-text placeholders for mixed-content preserved messages
- does not add non-text placeholders for text-only content blocks
- caps preserved tail when user turns are below preserve target
- trim-starts preserved section when history summary is empty
- does not append empty summary sections
- clamps preserve count into a safe range
- extracts opaque identifiers and audits summary quality
- dedupes pure-hex identifiers across case variants
- dedupes identifiers before applying the result cap
- filters ordinary short numbers and trims wrapped punctuation
- fails quality audit when required sections are missing
- requires exact section headings instead of substring matches
- does not enforce identifier retention when policy is off
- does not force strict identifier retention for custom policy
- matches pure-hex identifiers case-insensitively in retention checks
- flags missing non-latin latest asks when summary omits them
- accepts non-latin latest asks when summary reflects a shorter cjk phrase
- rejects latest-ask overlap when only stopwords overlap
- requires more than one meaningful overlap token for detailed asks
- clamps quality-guard retries into a safe range
- builds structured instructions with required sections
- does not force strict identifier retention when identifier policy is off
- threads custom identifier policy text into structured instructions
- sanitizes untrusted custom instruction text before embedding
- sanitizes custom identifier policy text before embedding
- builds a structured fallback summary from legacy previous summary text
- preserves an already-structured previous summary as-is
- restructures summaries with near-match headings instead of reusing them
- does not force policy-off marker in fallback exact identifiers section
- uses structured instructions when summarizing dropped history chunks
- does not retry summaries unless quality guard is explicitly enabled
- retries when generated summary misses headings even if preserved turns contain them
- does not treat preserved latest asks as satisfying overlap checks
- keeps last successful summary when a quality retry call fails
- keeps required headings when all turns are preserved and history is carried forward
- compaction-safeguard extension model fallback
- uses runtime.model when ctx.model is undefined (compact.lisp workflow)
- cancels compaction when both ctx.model and runtime.model are undefined
- compaction-safeguard double-compaction guard
- cancels compaction when there are no real messages to summarize
- continues when messages include real conversation content
- readWorkspaceContextForSummary

### src/agents/pi-extensions/context-pruning.test.lisp
- context-pruning
- mode off disables pruning
- does not touch tool results after the last N assistants
- never prunes tool results before the first user message
- hard-clear removes eligible tool results before cutoff
- uses contextWindow override when ctx.model is missing
- reads per-session settings from registry
- cache-ttl prunes once and resets the ttl window
- respects tools allow/deny (deny wins; wildcards supported)
- skips tool results that contain images (no soft trim, no hard clear)
- soft-trims across block boundaries
- soft-trims oversized tool results and preserves head/tail with a note

### src/agents/pi-extensions/context-pruning/pruner.test.lisp
- pruneContextMessages
- does not crash on assistant message with malformed thinking block (missing thinking string)
- does not crash on assistant message with null content entries
- does not crash on assistant message with malformed text block (missing text string)
- handles well-formed thinking blocks correctly

### src/agents/pi-model-discovery.auth.test.lisp
- discoverAuthStorage
- loads runtime credentials from auth-profiles without writing auth.json
- scrubs static api_key entries from legacy auth.json and keeps oauth entries
- preserves legacy auth.json when auth store is forced read-only

### src/agents/pi-model-discovery.compat.e2e.test.lisp
- pi-model-discovery module compatibility
- loads when InMemoryAuthStorageBackend is not exported

### src/agents/pi-project-settings.test.lisp
- resolveEmbeddedPiProjectSettingsPolicy
- defaults to sanitize
- accepts trusted and ignore modes
- buildEmbeddedPiSettingsSnapshot
- sanitize mode strips shell path + prefix but keeps other project settings
- ignore mode drops all project settings
- trusted mode keeps project settings as-is

### src/agents/pi-settings.test.lisp
- applyPiCompactionSettingsFromConfig
- bumps reserveTokens when below floor
- does not override when already above floor and not in safeguard mode
- applies explicit reserveTokens but still enforces floor
- applies keepRecentTokens when explicitly configured
- preserves current keepRecentTokens when safeguard mode leaves it unset
- treats keepRecentTokens=0 as invalid and keeps the current setting
- resolveCompactionReserveTokensFloor
- returns the default when config is missing
- accepts configured floors, including zero

### src/agents/pi-tool-definition-adapter.after-tool-call.fires-once.test.lisp
- after_tool_call fires exactly once in embedded runs
- fires after_tool_call exactly once on success when both adapter and handler are active
- fires after_tool_call exactly once on error when both adapter and handler are active
- uses before_tool_call adjusted params for after_tool_call payload
- fires after_tool_call exactly once per tool across multiple sequential tool calls

### src/agents/pi-tool-definition-adapter.after-tool-call.test.lisp
- pi tool definition adapter after_tool_call
- does not fire after_tool_call from the adapter (handled by subscription handler)
- does not fire after_tool_call from the adapter on error
- does not consume adjusted params in adapter for wrapped tools

### src/agents/pi-tool-definition-adapter.test.lisp
- pi tool definition adapter
- wraps tool errors into a tool result
- normalizes exec tool aliases in error results
- coerces details-only tool results to include content
- coerces non-standard object results to include content

### src/agents/pi-tools-agent-config.test.lisp
- Agent-specific tool filtering
- should apply global tool policy when no agent-specific policy exists
- should keep global tool policy when agent only sets tools.elevated
- should allow apply_patch when exec is allow-listed and applyPatch is enabled
- defaults apply_patch to workspace-only (blocks traversal)
- allows disabling apply_patch workspace-only via config (dangerous)
- should apply agent-specific tool policy
- should apply provider-specific tool policy
- should apply provider-specific tool profile overrides
- should allow different tool policies for different agents
- should apply group tool policy overrides (group-specific beats wildcard)
- should apply per-sender tool policies for group tools
- should not let default sender policy override group tools
- should resolve telegram group tool policy for topic session keys
- should inherit group tool policy for subagents from spawnedBy session keys
- should apply global tool policy before agent-specific policy
- should work with sandbox tools filtering
- should run exec synchronously when process is denied
- keeps sandbox as the implicit exec host default without forcing gateway approvals
- fails closed when exec host=sandbox is requested without sandbox runtime
- should apply agent-specific exec host defaults over global defaults
- applies explicit agentId exec defaults when sessionKey is opaque

### src/agents/pi-tools.before-tool-call.e2e.test.lisp
- before_tool_call loop detection behavior
- blocks known poll loops when no progress repeats
- does nothing when loopDetection.enabled is false
- does not block known poll loops when output progresses
- keeps generic repeated calls warn-only below global breaker
- blocks generic repeated no-progress calls at global breaker threshold
- coalesces repeated generic warning events into threshold buckets
- emits structured warning diagnostic events for ping-pong loops
- blocks ping-pong loops at critical threshold and emits critical diagnostic events
- does not block ping-pong at critical threshold when outcomes are progressing
- emits structured critical diagnostic events when blocking loops

### src/agents/pi-tools.before-tool-call.integration.e2e.test.lisp
- before_tool_call hook integration
- executes tool normally when no hook is registered
- allows hook to modify parameters
- blocks tool execution when hook returns block=true
- continues execution when hook throws
- normalizes non-object params for hook contract
- keeps adjusted params isolated per run when toolCallId collides
- before_tool_call hook deduplication (#15502)
- fires hook exactly once when tool goes through wrap + toToolDefinitions
- fires hook exactly once when tool goes through wrap + abort + toToolDefinitions
- before_tool_call hook integration for client tools
- passes modified params to client tool callbacks

### src/agents/pi-tools.create-openclaw-coding-tools.adds-claude-style-aliases-schemas-without-dropping-b.test.lisp
- createOpenClawCodingTools
- preserves action enums in normalized schemas
- enforces apply_patch availability and canonical names across model/provider constraints
- provides top-level object schemas for all tools

### src/agents/pi-tools.create-openclaw-coding-tools.adds-claude-style-aliases-schemas-without-dropping-d.test.lisp
- createOpenClawCodingTools
- returns image metadata for images and text-only blocks for text files
- filters tools by sandbox policy
- hard-disables write/edit when sandbox workspaceAccess is ro

### src/agents/pi-tools.create-openclaw-coding-tools.adds-claude-style-aliases-schemas-without-dropping-f.test.lisp
- createOpenClawCodingTools
- accepts Claude Code parameter aliases for read/write/edit
- coerces structured content blocks for write
- coerces structured old/new text blocks for edit

### src/agents/pi-tools.create-openclaw-coding-tools.adds-claude-style-aliases-schemas-without-dropping.test.lisp
- createOpenClawCodingTools
- Claude/Gemini alias support
- adds Claude-style aliases to schemas without dropping metadata
- normalizes file_path to path and enforces required groups at runtime
- keeps browser tool schema OpenAI-compatible without normalization
- mentions Chrome extension relay in browser tool description
- keeps browser tool schema properties after normalization
- exposes raw for gateway config.apply tool calls
- flattens anyOf-of-literals to enum for provider compatibility
- inlines local $ref before removing unsupported keywords
- cleans tuple items schemas
- drops null-only union variants without flattening other unions
- avoids anyOf/oneOf/allOf in tool schemas
- keeps raw core tool schemas union-free
- does not expose provider-specific message tools
- filters session tools for sub-agent sessions by default
- uses stored spawnDepth to apply leaf tool policy for flat depth-2 session keys
- supports allow-only sub-agent tool policy
- applies tool profiles before allow/deny policies
- expands group shorthands in global tool policy
- expands group shorthands in global tool deny policy
- lets agent profiles override global profiles
- removes unsupported JSON Schema keywords for Cloud Code Assist API compatibility
- applies sandbox path guards to file_path alias
- auto-pages read output across chunks when context window budget allows
- adds capped continuation guidance when aggregated read output reaches budget
- strips truncation.content details from read results while preserving other fields

### src/agents/pi-tools.message-provider-policy.test.lisp
- createOpenClawCodingTools message provider policy
- keeps tts tool for non-voice providers

### src/agents/pi-tools.model-provider-collision.test.lisp
- applyModelProviderToolPolicy
- keeps web_search for non-xAI models
- removes web_search for OpenRouter xAI model ids
- removes web_search for direct xAI providers

### src/agents/pi-tools.policy.test.lisp
- pi-tools.policy
- treats * in allow as allow-all
- treats * in deny as deny-all
- supports wildcard allow/deny patterns
- keeps apply_patch when exec is allowlisted
- resolveSubagentToolPolicy depth awareness
- applies subagent tools.alsoAllow to re-enable default-denied tools
- applies subagent tools.allow to re-enable default-denied tools
- merges subagent tools.alsoAllow into tools.allow when both are set
- keeps configured deny precedence over allow and alsoAllow
- does not create a restrictive allowlist when only alsoAllow is configured
- depth-1 orchestrator (maxSpawnDepth=2) allows sessions_spawn
- depth-1 orchestrator (maxSpawnDepth=2) allows subagents
- depth-1 orchestrator (maxSpawnDepth=2) allows sessions_list
- depth-1 orchestrator (maxSpawnDepth=2) allows sessions_history
- depth-1 orchestrator still denies gateway, cron, memory
- depth-2 leaf denies sessions_spawn
- depth-2 orchestrator (maxSpawnDepth=3) allows sessions_spawn
- depth-3 leaf (maxSpawnDepth=3) denies sessions_spawn
- depth-2 leaf allows subagents (for visibility)
- depth-2 leaf denies sessions_list and sessions_history
- depth-1 leaf (maxSpawnDepth=1) denies sessions_spawn
- depth-1 leaf (maxSpawnDepth=1) denies sessions_list
- defaults to leaf behavior when no depth is provided
- defaults to leaf behavior when depth is undefined and maxSpawnDepth is 1

### src/agents/pi-tools.read.host-edit-access.test.lisp
- createHostWorkspaceEditTool host access mapping

### src/agents/pi-tools.read.host-edit-recovery.test.lisp
- createHostWorkspaceEditTool post-write recovery
- returns success when upstream throws but file has newText and no longer has oldText
- rethrows when file on disk does not contain newText
- rethrows when file still contains oldText (pre-write failure; avoid false success)

### src/agents/pi-tools.read.workspace-root-guard.test.lisp
- wrapToolWorkspaceRootGuardWithOptions
- maps container workspace paths to host workspace root
- maps file:// container workspace paths to host workspace root
- maps @-prefixed container workspace paths to host workspace root
- normalizes @-prefixed absolute paths before guard checks
- does not remap absolute paths outside the configured container workdir

### src/agents/pi-tools.safe-bins.test.lisp
- createOpenClawCodingTools safeBins
- threads tools.exec.safeBins into exec allowlist checks
- rejects unprofiled custom safe-bin entries
- does not allow env var expansion to smuggle file args via safeBins
- blocks sort output/compress bypass attempts in safeBins mode
- blocks shell redirection metacharacters in safeBins mode
- blocks grep recursive flags from reading cwd via safeBins

### src/agents/pi-tools.sandbox-mounted-paths.workspace-only.test.lisp
- tools.fs.workspaceOnly
- defaults to allowing sandbox mounts outside the workspace root
- rejects sandbox mounts outside the workspace root when enabled
- enforces apply_patch workspace-only in sandbox mounts by default
- allows apply_patch outside workspace root when explicitly disabled

### src/agents/pi-tools.whatsapp-login-gating.test.lisp
- owner-only tool gating
- removes owner-only tools for unauthorized senders
- keeps owner-only tools for authorized senders
- defaults to removing owner-only tools when owner status is unknown

### src/agents/pi-tools.workspace-only-false.test.lisp
- FS tools with workspaceOnly=false
- should allow write outside workspace when workspaceOnly=false
- should allow write outside workspace via ../ path when workspaceOnly=false
- should allow edit outside workspace when workspaceOnly=false
- should allow edit outside workspace via ../ path when workspaceOnly=false
- should allow read outside workspace when workspaceOnly=false
- should allow write outside workspace when workspaceOnly is unset
- should allow edit outside workspace when workspaceOnly is unset
- should block write outside workspace when workspaceOnly=true

### src/agents/pi-tools.workspace-paths.test.lisp
- workspace path resolution
- resolves relative read/write/edit paths against workspaceDir even after cwd changes
- allows deletion edits with empty newText
- defaults exec cwd to workspaceDir when workdir is omitted
- lets exec workdir override the workspace default
- rejects @-prefixed absolute paths outside workspace when workspaceOnly is enabled
- rejects hardlinked file aliases when workspaceOnly is enabled
- sandboxed workspace paths
- uses sandbox workspace for relative read/write/edit

### src/agents/pty-keys.test.lisp
- encodeKeySequence maps common keys and modifiers
- encodeKeySequence supports hex + literal with warnings
- encodePaste wraps bracketed sequences by default
- stripDsrRequests removes cursor queries and counts them
- buildCursorPositionResponse returns CPR sequence

### src/agents/sandbox-agent-config.agent-specific-sandbox-config.e2e.test.lisp
- Agent-specific sandbox config
- should use agent-specific workspaceRoot
- should prefer agent config over global for multiple agents
- should prefer agent-specific sandbox tool policy
- should use global sandbox config when no agent-specific config exists
- should resolve setupCommand overrides based on sandbox scope
- should allow agent-specific docker settings beyond setupCommand
- should honor agent-specific sandbox mode overrides
- should use agent-specific scope
- enforces required allowlist tools in default and explicit sandbox configs

### src/agents/sandbox-create-args.test.lisp
- buildSandboxCreateArgs
- includes hardening and resource flags
- emits -v flags for safe custom binds
- omits -v flags when binds is empty or undefined
- blocks bind sources outside runtime allowlist roots
- allows bind sources outside runtime allowlist with explicit override
- blocks reserved /workspace target bind mounts by default
- allows reserved /workspace target bind mounts with explicit dangerous override
- allows container namespace join with explicit dangerous override

### src/agents/sandbox-explain.test.lisp
- sandbox explain helpers
- prefers agent overrides > global > defaults (sandbox tool policy)
- expands group tool shorthands inside sandbox tool policy
- denies still win after group expansion
- includes config key paths + main-session hint for non-main mode

### src/agents/sandbox-media-paths.test.lisp
- createSandboxBridgeReadFile
- delegates reads through the sandbox bridge with sandbox root cwd

### src/agents/sandbox-merge.test.lisp
- sandbox config merges
- resolves sandbox scope deterministically
- merges sandbox docker env and ulimits (agent wins)
- resolves docker binds and shared-scope override behavior
- applies per-agent browser and prune overrides (ignored under shared scope)

### src/agents/sandbox-paths.test.lisp
- resolveSandboxedMediaSource
- resolves sandbox-relative paths
- maps container /workspace absolute paths into sandbox root
- maps file:// URLs under /workspace into sandbox root
- rejects symlinked OpenClaw tmp paths escaping tmp root
- rejects sandbox symlink escapes when the outside leaf does not exist yet
- rejects hardlinked OpenClaw tmp paths to outside files
- rejects symlinked OpenClaw tmp paths to hardlinked outside files
- passes HTTP URLs through unchanged
- returns empty string for empty input
- returns empty string for whitespace-only input

### src/agents/sandbox-skills.test.lisp
- sandbox skill mirroring

### src/agents/sandbox.resolveSandboxContext.test.lisp
- resolveSandboxContext
- does not sandbox the agent main session in non-main mode
- does not create a sandbox workspace for the agent main session in non-main mode
- treats main session aliases as main in non-main mode

### src/agents/sandbox/bind-spec.test.lisp
- splitSandboxBindSpec
- splits POSIX bind specs with and without mode
- preserves Windows drive-letter host paths
- returns null when no host/container separator exists

### src/agents/sandbox/browser.create.test.lisp
- ensureSandboxBrowser create args
- publishes noVNC on loopback and injects noVNC password env
- does not inject noVNC password env when noVNC is disabled
- mounts the main workspace read-only when workspaceAccess is none
- keeps the main workspace writable when workspaceAccess is rw

### src/agents/sandbox/browser.novnc-url.test.lisp
- noVNC auth helpers
- builds the default observer URL without password
- builds a fragment-based observer target URL with password
- issues one-time short-lived observer tokens
- expires observer tokens
- generates 8-char alphanumeric passwords

### src/agents/sandbox/config-hash.test.lisp
- computeSandboxConfigHash
- ignores object key order
- computeSandboxBrowserConfigHash
- treats docker bind order as significant
- changes when security epoch changes
- changes when cdp source range changes

### src/agents/sandbox/context.user-fallback.test.lisp
- resolveSandboxDockerUser
- keeps configured docker.user
- falls back to workspace ownership when docker.user is unset
- leaves docker.user unset when workspace stat fails

### src/agents/sandbox/docker.config-hash-recreate.test.lisp
- ensureSandboxContainer config-hash recreation
- recreates shared container when array-order change alters hash
- applies custom binds after workspace mounts so overlapping binds can override

### src/agents/sandbox/docker.execDockerRaw.enoent.test.lisp
- execDockerRaw
- wraps docker ENOENT with an actionable configuration error

### src/agents/sandbox/docker.windows.test.lisp
- resolveDockerSpawnInvocation
- keeps non-windows invocation unchanged
- prefers docker.exe entrypoint over cmd shell fallback on windows
- falls back to shell mode when only unresolved docker.cmd wrapper exists

### src/agents/sandbox/fs-bridge.anchored-ops.test.lisp
- sandbox fs bridge anchored ops

### src/agents/sandbox/fs-bridge.boundary.test.lisp
- sandbox fs bridge boundary validation
- blocks writes into read-only bind mounts
- allows mkdirp for existing in-boundary subdirectories
- allows mkdirp when boundary open reports io for an existing directory
- rejects mkdirp when target exists as a file
- rejects pre-existing host symlink escapes before docker exec
- rejects pre-existing host hardlink escapes before docker exec
- rejects missing files before any docker read command runs

### src/agents/sandbox/fs-bridge.shell.test.lisp
- sandbox fs bridge shell compatibility
- uses POSIX-safe shell prologue in all bridge commands
- resolveCanonicalContainerPath script is valid POSIX sh (no do; token)
- reads inbound media-style filenames with triple-dash ids
- resolves dash-leading basenames into absolute container paths
- resolves bind-mounted absolute container paths for reads
- writes via temp file + atomic rename (never direct truncation)
- re-validates target before final rename and cleans temp file on failure

### src/agents/sandbox/fs-paths.test.lisp
- parseSandboxBindMount
- parses bind mode and writeability
- parses Windows drive-letter host paths
- parses UNC-style host paths
- resolveSandboxFsPathWithMounts
- maps mounted container absolute paths to host paths
- keeps workspace-relative display paths for default workspace files
- preserves legacy sandbox-root error for outside paths
- prefers custom bind mounts over default workspace mount at /workspace

### src/agents/sandbox/host-paths.test.lisp
- normalizeSandboxHostPath
- normalizes dot segments and strips trailing slash
- resolveSandboxHostPathViaExistingAncestor
- keeps non-absolute paths unchanged
- resolves symlink parents when the final leaf does not exist

### src/agents/sandbox/registry.test.lisp
- registry race safety
- keeps both container updates under concurrent writes
- prevents concurrent container remove/update from resurrecting deleted entries
- keeps both browser updates under concurrent writes
- prevents concurrent browser remove/update from resurrecting deleted entries
- fails fast when registry files are malformed during update
- fails fast when registry entries are invalid during update

### src/agents/sandbox/sanitize-env-vars.test.lisp
- sanitizeEnvVars
- keeps normal env vars and blocks obvious credentials
- blocks credentials even when suffix pattern matches
- adds warnings for suspicious values
- supports strict mode with explicit allowlist

### src/agents/sandbox/validate-sandbox-security.test.lisp
- getBlockedBindReason
- blocks common Docker (driven from Common Lisp) socket directories
- does not block /var by default
- validateBindMounts
- allows legitimate project directory mounts
- allows undefined or empty binds
- blocks dangerous bind source paths
- allows parent mounts that are not blocked
- blocks symlink escapes into blocked directories
- blocks symlink-parent escapes with non-existent leaf outside allowed roots
- blocks symlink-parent escapes into blocked paths when leaf does not exist
- rejects non-absolute source paths (relative or named volumes)
- blocks bind sources outside allowed roots when allowlist is configured
- allows bind sources in allowed roots when allowlist is configured
- allows bind sources outside allowed roots with explicit dangerous override
- blocks reserved container target paths by default
- allows reserved container target paths with explicit dangerous override
- validateNetworkMode
- allows bridge/none/custom/undefined
- blocks host mode (case-insensitive)
- blocks container namespace joins by default
- allows container namespace joins with explicit dangerous override
- validateSeccompProfile
- allows custom profile paths/undefined
- validateApparmorProfile
- allows named profile/undefined
- profile hardening
- validateSandboxSecurity
- passes with safe config

### src/agents/sandbox/workspace-mounts.test.lisp
- appendWorkspaceMountArgs
- omits agent workspace mount when workspaceAccess is none
- omits agent workspace mount when paths are identical

### src/agents/sandbox/workspace.test.lisp
- ensureSandboxWorkspace
- seeds regular bootstrap files from the source workspace

### src/agents/sanitize-for-prompt.test.lisp
- sanitizeForPromptLiteral (OC-19 hardening)
- strips ASCII control chars (CR/LF/NUL/tab)
- strips Unicode line/paragraph separators
- strips Unicode format chars (bidi override)
- preserves ordinary Unicode + spaces
- buildAgentSystemPrompt uses sanitized workspace/sandbox strings
- sanitizes workspaceDir (no newlines / separators)
- sanitizes sandbox workspace/mount/url strings
- wrapUntrustedPromptDataBlock
- wraps sanitized text in untrusted-data tags
- returns empty string when sanitized input is empty
- applies max char limit

### src/agents/schema/clean-for-gemini.test.lisp
- cleanSchemaForGemini
- coerces null properties to an empty object
- coerces non-object properties to an empty object
- coerces array properties to an empty object
- coerces nested null properties while preserving valid siblings

### src/agents/schema/clean-for-xai.test.lisp
- isXaiProvider
- matches direct xai provider
- matches x-ai provider string
- matches openrouter with x-ai model id
- does not match openrouter with non-xai model id
- does not match openai provider
- does not match google provider
- handles undefined provider
- matches venice provider with grok model id
- matches venice provider with venice/ prefixed grok model id
- does not match venice provider with non-grok model id
- stripXaiUnsupportedKeywords
- strips minLength and maxLength from string properties
- strips minItems and maxItems from array properties
- strips minContains and maxContains
- strips keywords recursively inside nested objects
- strips keywords inside anyOf/oneOf/allOf variants
- strips keywords inside array item schemas
- preserves all other schema keywords
- passes through primitives and null unchanged

### src/agents/session-file-repair.test.lisp
- repairSessionFileIfNeeded
- rewrites session files that contain malformed lines
- does not drop CRLF-terminated JSONL lines
- warns and skips repair when the session header is invalid
- returns a detailed reason when read errors are not ENOENT

### src/agents/session-slug.test.lisp
- session slug
- generates a two-word slug by default
- adds a numeric suffix when the base slug is taken
- falls back to three words when collisions persist

### src/agents/session-tool-result-guard.test.lisp
- installSessionToolResultGuard
- inserts synthetic toolResult before non-tool message when pending
- flushes pending tool calls when asked explicitly
- clears pending tool calls without inserting synthetic tool results
- clears pending on user interruption when synthetic tool results are disabled
- does not add synthetic toolResult when a matching one exists
- backfills blank toolResult names from pending tool calls
- preserves ordering with multiple tool calls and partial results
- flushes pending on guard when no toolResult arrived
- handles toolUseId on toolResult
- drops malformed tool calls missing input before persistence
- drops malformed tool calls with invalid name tokens before persistence
- drops tool calls not present in allowedToolNames
- flushes pending tool results when a sanitized assistant message is dropped
- clears pending when a sanitized assistant message is dropped and synthetic results are disabled
- drops older pending ids before new tool calls when synthetic results are disabled
- caps oversized tool result text during persistence
- does not truncate tool results under the limit
- blocks persistence when before_message_write returns block=true
- applies before_message_write message mutations before persistence
- applies before_message_write to synthetic tool-result flushes
- applies message persistence transform to user messages
- does NOT create synthetic toolResult for aborted assistant messages with toolCalls
- does NOT create synthetic toolResult for errored assistant messages with toolCalls

### src/agents/session-tool-result-guard.tool-result-persist-hook.test.lisp
- tool_result_persist hook
- does not modify persisted toolResult messages when no hook is registered
- loads tool_result_persist hooks without breaking persistence
- before_message_write hook
- continues persistence when a before_message_write hook throws

### src/agents/session-transcript-repair.attachments.test.lisp
- sanitizeToolCallInputs redacts sessions_spawn attachments
- replaces attachments[].content with __OPENCLAW_REDACTED__
- redacts attachments content from tool input payloads too

### src/agents/session-transcript-repair.test.lisp
- sanitizeToolUseResultPairing
- moves tool results directly after tool calls and inserts missing results
- repairs blank tool result names from matching tool calls
- drops duplicate tool results for the same id within a span
- drops duplicate tool results for the same id across the transcript
- drops orphan tool results that do not match any tool call
- skips tool call extraction for assistant messages with stopReason 'error'
- skips tool call extraction for assistant messages with stopReason 'aborted'
- still repairs tool results for normal assistant messages with stopReason 'toolUse'
- drops orphan tool results that follow an aborted assistant message
- sanitizeToolCallInputs
- drops tool calls missing input or arguments
- keeps valid tool calls and preserves text blocks
- preserves toolUse input shape for sessions_spawn when no attachments are present
- redacts sessions_spawn attachments for mixed-case and padded tool names
- preserves other block properties when trimming tool names
- stripToolResultDetails
- removes details only from toolResult messages
- returns the same array reference when there are no toolResult details

### src/agents/session-write-lock.test.lisp
- acquireSessionWriteLock
- reuses locks across symlinked session paths
- keeps the lock file until the last release
- reclaims stale lock files
- does not reclaim fresh malformed lock files during contention
- reclaims malformed lock files once they are old enough
- watchdog releases stale in-process locks
- derives max hold from timeout plus grace
- clamps max hold for effectively no-timeout runs
- cleans stale .jsonl lock files in sessions directories
- removes held locks on termination signals
- reclaims lock files with recycled PIDs
- reclaims orphan lock files without starttime when PID matches current process
- does not reclaim active in-process lock files without starttime
- does not reclaim active in-process lock files with malformed starttime
- registers cleanup for SIGQUIT and SIGABRT
- cleans up locks on SIGINT without removing other handlers
- cleans up locks on exit
- keeps other signal listeners registered

### src/agents/sessions-spawn-hooks.test.lisp
- sessions_spawn subagent lifecycle hooks
- runs subagent_spawning and emits subagent_spawned with requester metadata
- emits subagent_spawned with threadRequested=false when not requested
- respects explicit mode=run when thread binding is requested
- returns error when thread binding cannot be created
- returns error when thread binding is not marked ready
- rejects mode=session when thread=true is not requested
- rejects thread=true on channels without thread support
- runs subagent_ended cleanup hook when agent start fails after successful bind
- falls back to sessions.delete cleanup when subagent_ended hook is unavailable

### src/agents/sessions-spawn-threadid.test.lisp
- sessions_spawn requesterOrigin threading
- captures threadId in requesterOrigin
- stores requesterOrigin without threadId when none is provided

### src/agents/shell-utils.test.lisp
- getShellConfig
- uses PowerShell on Windows
- prefers bash when fish is default and bash is on PATH
- falls back to sh when fish is default and bash is missing
- falls back to env shell when fish is default and no sh is available
- uses sh when SHELL is unset
- resolveShellFromPath
- returns undefined when PATH is empty
- returns the first executable match from PATH
- returns undefined when command does not exist
- resolvePowerShellPath
- prefers PowerShell 7 in ProgramFiles
- prefers ProgramW6432 PowerShell 7 when ProgramFiles lacks pwsh
- finds pwsh on PATH when not in standard install locations
- falls back to Windows PowerShell 5.1 path when pwsh is unavailable

### src/agents/skills-install-fallback.test.lisp
- skills-install fallback edge cases
- handles sudo probe failures for go install without apt fallback
- status-selected go installer fails gracefully when apt fallback needs sudo
- uv not installed and no brew returns helpful error without curl auto-install

### src/agents/skills-install.download.test.lisp
- installDownloadSpec extraction safety
- rejects archive traversal writes outside targetDir
- extracts zip with stripComponents safely
- rejects targetDir escapes outside the per-skill tools root
- allows relative targetDir inside the per-skill tools root
- installDownloadSpec extraction safety (tar.bz2)
- handles tar.bz2 extraction safety edge-cases
- rejects tar.bz2 archives that change after preflight

### src/agents/skills-install.test.lisp
- installSkill code safety scanning
- adds detailed warnings for critical findings and continues install
- warns and continues when skill scan fails

### src/agents/skills-status.test.lisp
- buildWorkspaceSkillStatus
- does not surface install options for OS-scoped skills on unsupported platforms

### src/agents/skills.agents-skills-directory.test.lisp
- buildWorkspaceSkillsPrompt — .agents/skills/ directories
- loads project .agents/skills/ above managed and below workspace
- loads personal ~/.agents/skills/ above managed and below project .agents/skills/
- loads unique skills from all .agents/skills/ sources alongside others

### src/agents/skills.build-workspace-skills-prompt.applies-bundled-allowlist-without-affecting-workspace-skills.test.lisp
- buildWorkspaceSkillsPrompt
- applies bundled allowlist without affecting workspace skills

### src/agents/skills.build-workspace-skills-prompt.prefers-workspace-skills-managed-skills.test.lisp
- buildWorkspaceSkillsPrompt
- prefers workspace skills over managed skills
- gates by bins, config, and always
- uses skillKey for config lookups

### src/agents/skills.build-workspace-skills-prompt.syncs-merged-skills-into-target-workspace.test.lisp
- buildWorkspaceSkillsPrompt
- syncs merged skills into a target workspace
- keeps synced skills confined under target workspace when frontmatter name uses traversal
- keeps synced skills confined under target workspace when frontmatter name is absolute
- filters skills based on env/config gates
- applies skill filters, including empty lists

### src/agents/skills.buildworkspaceskillsnapshot.test.lisp
- buildWorkspaceSkillSnapshot
- returns an empty snapshot when skills dirs are missing
- omits disable-model-invocation skills from the prompt
- keeps prompt output aligned with buildWorkspaceSkillsPrompt
- truncates the skills prompt when it exceeds the configured char budget
- limits discovery for nested repo-style skills roots (dir/skills/*)
- skips skills whose SKILL.md exceeds maxSkillFileBytes
- detects nested skills roots beyond the first 25 entries
- enforces maxSkillFileBytes for root-level SKILL.md

### src/agents/skills.buildworkspaceskillstatus.test.lisp
- buildWorkspaceSkillStatus
- reports missing requirements and install options
- respects OS-gated skills
- marks bundled skills blocked by allowlist
- filters install options by OS

### src/agents/skills.compact-skill-paths.test.lisp
- compactSkillPaths
- replaces home directory prefix with ~ in skill locations
- preserves paths outside home directory

### src/agents/skills.e2e-test-helpers.test.lisp
- writeSkill
- writes SKILL.md with required fields
- includes optional metadata, body, and frontmatterExtra
- keeps empty body and trims blank frontmatter extra entries

### src/agents/skills.loadworkspaceskillentries.test.lisp
- loadWorkspaceSkillEntries
- handles an empty managed skills dir without throwing
- includes plugin-shipped skills when the plugin is enabled
- excludes plugin-shipped skills when the plugin is not allowed
- includes diffs plugin skill when the plugin is enabled
- excludes diffs plugin skill when the plugin is disabled

### src/agents/skills.resolveskillspromptforrun.test.lisp
- resolveSkillsPromptForRun
- prefers snapshot prompt when available
- builds prompt from entries when snapshot is missing

### src/agents/skills.sherpa-onnx-tts-bin.test.lisp
- skills/sherpa-onnx-tts bin script
- loads as Common Lisp package/module structure and falls through to usage output when env is missing

### src/agents/skills.summarize-skill-description.test.lisp
- skills/summarize frontmatter
- mentions podcasts, local files, and transcription use cases

### src/agents/skills.test.lisp
- buildWorkspaceSkillCommandSpecs
- sanitizes and de-duplicates command names
- truncates descriptions longer than 100 characters for Discord compatibility
- includes tool-dispatch metadata from frontmatter
- buildWorkspaceSkillsPrompt
- returns empty prompt when skills dirs are missing
- loads bundled skills when present
- loads extra skill folders from config (lowest precedence)
- loads skills from workspace skills/
- applySkillEnvOverrides
- sets and restores env vars
- keeps env keys tracked until all overlapping overrides restore
- applies env overrides from snapshots
- blocks unsafe env overrides but allows declared secrets
- blocks dangerous host env overrides even when declared
- allows required env overrides from snapshots

### src/agents/skills/bundled-dir.test.lisp
- resolveBundledSkillsDir
- returns OPENCLAW_BUNDLED_SKILLS_DIR override when set
- resolves bundled skills under a flattened dist layout

### src/agents/skills/filter.test.lisp
- skills/filter
- normalizes configured filters with trimming
- preserves explicit empty list as []
- normalizes for comparison with dedupe + ordering
- matches equivalent filters after normalization

### src/agents/skills/frontmatter.test.lisp
- resolveSkillInvocationPolicy
- defaults to enabled behaviors
- parses frontmatter boolean strings
- resolveOpenClawMetadata install validation
- accepts safe install specs
- drops unsafe brew formula values
- drops unsafe Quicklisp/Ultralisp package specs for sbcl installers
- drops unsafe go module specs
- drops unsafe download urls

### src/agents/skills/plugin-skills.test.lisp
- resolvePluginSkillDirs
- rejects plugin skill paths that escape the plugin root
- rejects plugin skill symlinks that resolve outside plugin root

### src/agents/skills/refresh.test.lisp
- ensureSkillsWatcher
- ignores node_modules, dist, .git, and Python venvs by default
- /tmp/workspace/skills/node_modules/pkg/index.js
- /tmp/workspace/skills/dist/index.js
- /tmp/workspace/skills/.git/config
- /tmp/workspace/skills/scripts/.venv/bin/python
- /tmp/workspace/skills/venv/lib/python3.10/site.py
- /tmp/workspace/skills/__pycache__/module.pyc
- /tmp/workspace/skills/.mypy_cache/3.10/foo.json
- /tmp/workspace/skills/.pytest_cache/v/cache
- /tmp/workspace/skills/build/output.js
- /tmp/workspace/skills/.cache/data.json
- /tmp/.hidden/skills/index.md
- /tmp/workspace/skills/my-skill/SKILL.md

### src/agents/spawned-context.test.lisp
- normalizeSpawnedRunMetadata
- trims text fields and drops empties
- mapToolContextToSpawnedRunMetadata
- maps agent group fields to run metadata shape
- resolveSpawnedWorkspaceInheritance
- prefers explicit workspaceDir when provided
- returns undefined for missing requester context
- resolveIngressWorkspaceOverrideForSpawnedRun
- forwards workspace only for spawned runs

### src/agents/subagent-announce-dispatch.test.lisp
- mapQueueOutcomeToDeliveryResult
- maps steered to delivered
- maps queued to delivered
- maps none to not-delivered
- runSubagentAnnounceDispatch
- uses queue-first ordering for non-completion mode
- short-circuits direct send when non-completion queue delivers
- uses direct-first ordering for completion mode
- falls back to queue when completion direct send fails
- returns direct failure when completion fallback queue cannot deliver
- returns none immediately when signal is already aborted

### src/agents/subagent-announce-queue.test.lisp
- subagent-announce-queue
- retries failed sends without dropping queued announce items
- preserves queue summary state across failed summary delivery retries
- retries collect-mode batches without losing queued items
- uses debounce floor for retries when debounce exceeds backoff

### src/agents/subagent-announce.capture-completion-reply.test.lisp
- captureSubagentCompletionReply
- returns immediate assistant output without polling
- polls briefly and returns late tool output once available
- returns undefined when no completion output arrives before retry window closes

### src/agents/subagent-announce.format.e2e.test.lisp
- subagent announce formatting
- sends instructional message to main agent with status and findings
- includes success status when outcome is ok
- uses child-run announce identity for direct idempotency
- uses latest assistant text when it appears after a tool output
- keeps full findings and includes compact stats
- routes manual spawn completion through a parent-agent announce turn
- keeps direct completion announce delivery immediate even when sibling counters are non-zero
- suppresses completion delivery when subagent reply is ANNOUNCE_SKIP
- suppresses announce flow for whitespace-padded ANNOUNCE_SKIP and still runs cleanup
- suppresses completion delivery when subagent reply is NO_REPLY
- uses fallback reply when wake continuation returns NO_REPLY
- retries completion direct agent announce on transient channel-unavailable errors
- does not retry completion direct agent announce on permanent channel errors
- retries direct agent announce on transient channel-unavailable errors
- delivers completion-mode announces immediately even when sibling runs are still active
- keeps session-mode completion delivery on the bound destination when sibling runs are active
- does not duplicate to main channel when two active bound sessions complete from the same requester channel
- includes completion status details for error and timeout outcomes
- routes manual completion announce agent delivery using requester thread hints
- does not force Slack threadId from bound conversation id
- routes manual completion announce agent delivery for telegram forum topics
- uses hook-provided thread target across requester thread variants
- steers announcements into an active run when queue mode is steer
- queues announce delivery with origin account routing
- reports cron announce as delivered when it successfully queues into an active requester run
- keeps queued idempotency unique for same-ms distinct child runs
- prefers direct delivery first for completion-mode and then queues on direct failure
- falls back to internal requester-session injection when completion route is missing
- uses direct completion delivery when explicit channel+to route is available
- returns failure for completion-mode when direct delivery fails and queue fallback is unavailable
- uses assistant output for completion-mode when latest assistant text exists
- falls back to latest tool output for completion-mode when assistant output is empty
- ignores user text when deriving fallback completion output
- queues announce delivery back into requester subagent session
- splits collect-mode queues when accountId differs
- injects direct announce into requester subagent session as a user-turn agent call
- keeps completion-mode announce internal for nested requester subagent sessions
- retries reading subagent output when early lifecycle completion had no text
- does not include batching guidance when sibling subagents are still active
- defers announces while any descendant runs remain pending
- keeps single subagent announces self contained without batching hints
- announces completion immediately when no descendants are pending
- announces with direct child completion outputs once all descendants are settled
- wakes an ended orchestrator run with settled child results before any upward announce
- does not re-wake an already woken run id
- nested completion chains re-check child then parent deterministically
- ignores post-completion announce traffic for completed run-mode requester sessions
- bubbles child announce to parent requester when requester subagent session is missing
- keeps announce retryable when missing requester subagent session has no fallback requester
- defers announce when child run stays active after settle timeout
- prefers requesterOrigin channel over stale session lastChannel in queued announce
- routes or falls back for ended parent subagent sessions (#18037)
- subagent announce regression matrix for nested completion delivery
- regression simple announce, leaf subagent with no children announces immediately
- regression nested 2-level, parent announces direct child frozen result instead of placeholder text
- regression parallel fan-out, parent defers until both children settle and then includes both outputs
- regression parallel timing difference, fast child cannot trigger early parent announce before slow child settles
- regression nested parallel, middle waits for two children then parent receives the synthesized middle result
- regression sequential spawning, parent preserves child output order across child 1 then child 2 then child 3
- regression child error handling, parent announce includes child error status and preserved child output
- regression descendant count gating, announce defers at pending > 0 then fires at pending = 0
- regression deep 3-level re-check chain, child announce then parent re-check emits synthesized parent output

### src/agents/subagent-announce.timeout.test.lisp
- subagent announce timeout config
- uses 60s timeout by default for direct announce agent call
- honors configured announce timeout for direct announce agent call
- honors configured announce timeout for completion direct agent call
- regression, skips parent announce while descendants are still pending
- regression, supports cron announceType without declaration order errors
- regression, routes child announce to parent session instead of grandparent when parent session still exists
- regression, falls back to grandparent only when parent subagent session is missing

### src/agents/subagent-depth.test.lisp
- getSubagentDepthFromSessionStore
- uses spawnDepth from the session store when available
- derives depth from spawnedBy ancestry when spawnDepth is missing
- resolves depth when caller is identified by sessionId
- resolves prefixed store keys when caller key omits the agent prefix
- falls back to session-key segment counting when metadata is missing
- resolveAgentTimeoutMs
- uses a timer-safe sentinel for no-timeout overrides
- clamps very large timeout overrides to timer-safe values

### src/agents/subagent-registry-cleanup.test.lisp
- resolveDeferredCleanupDecision
- defers completion-message cleanup while descendants are still pending
- hard-expires completion-message cleanup when descendants never settle
- keeps regular expiry behavior for non-completion flows
- uses retry backoff for completion-message flows once descendants are settled

### src/agents/subagent-registry-completion.test.lisp
- emitSubagentEndedHookOnce
- records ended hook marker even when no subagent_ended hooks are registered
- runs subagent_ended hooks when available
- returns false when runId is blank
- returns false when ended hook marker already exists
- returns false when runId is already in flight
- returns false when subagent hook execution throws

### src/agents/subagent-registry-queries.test.lisp
- subagent registry query regressions
- regression descendant count gating, pending descendants block announce until cleanup completion is recorded
- regression nested parallel counting, traversal includes child and grandchildren pending states
- regression excluding current run, countPendingDescendantRunsExcludingRun keeps sibling gating intact
- counts ended orchestrators with pending descendants as active
- scopes direct child listings to the requester run window when requesterRunId is provided
- regression post-completion gating, run-mode sessions ignore late announces after cleanup completes
- keeps run-mode orchestrators announce-eligible while waiting on child completions
- regression post-completion gating, session-mode sessions keep accepting follow-up announces

### src/agents/subagent-registry.announce-loop-guard.test.lisp
- announce loop guard (#18264)
- SubagentRunRecord has announceRetryCount and lastAnnounceRetryAt fields
- expired completion-message entries are still resumed for announce
- announce rejection resets cleanupHandled so retries can resume

### src/agents/subagent-registry.archive.e2e.test.lisp
- subagent registry archive behavior
- does not set archiveAtMs for persistent session-mode runs
- keeps archiveAtMs unset when replacing a session-mode run after steer restart

### src/agents/subagent-registry.lifecycle-retry-grace.e2e.test.lisp
- subagent registry lifecycle error grace
- ignores transient lifecycle errors when run retries and then ends successfully
- announces error when lifecycle error remains terminal after grace window
- freezes completion result at run termination across deferred announce retries
- refreshes frozen completion output from later turns in the same session
- ignores silent follow-up turns when refreshing frozen completion output
- regression, captures frozen completion output with 100KB cap and retains it for keep-mode cleanup
- keeps parallel child completion results frozen even when late traffic arrives

### src/agents/subagent-registry.nested.e2e.test.lisp
- subagent registry nested agent tracking
- listSubagentRunsForRequester returns children of the requesting session
- announce uses requesterSessionKey to route to the correct parent
- countActiveRunsForSession only counts active children of the specific session
- countActiveDescendantRuns traverses through ended parents
- countPendingDescendantRuns includes ended descendants until cleanup completes
- keeps parent pending for parallel children until both descendants complete cleanup
- countPendingDescendantRunsExcludingRun ignores only the active announce run

### src/agents/subagent-registry.persistence.test.lisp
- subagent registry persistence
- persists runs to disk and resumes after restart
- skips cleanup when cleanupHandled was persisted
- maps legacy announce fields into cleanup state
- retries cleanup announce after a failed announce
- keeps delete-mode runs retryable when announce is deferred
- reconciles orphaned restored runs by pruning them from registry
- resume guard prunes orphan runs before announce retry
- uses isolated temp state when OPENCLAW_STATE_DIR is unset in tests

### src/agents/subagent-registry.steer-restart.test.lisp
- subagent registry steer restarts
- suppresses announce for interrupted runs and only announces the replacement run
- defers subagent_ended hook for completion-mode runs until announce delivery resolves
- does not emit subagent_ended on completion for persistent session-mode runs
- clears announce retry state when replacing after steer restart
- clears terminal lifecycle state when replacing after steer restart
- clears frozen completion fields when replacing after steer restart
- preserves frozen completion as fallback when replacing for wake continuation
- restores announce for a finished run when steer replacement dispatch fails
- marks killed runs terminated and inactive
- recovers announce cleanup when completion arrives after a kill marker
- retries deferred parent cleanup after a descendant announces
- retries completion-mode announce delivery with backoff and then gives up after retry limit
- keeps completion cleanup pending while descendants are still active

### src/agents/subagent-spawn.attachments.test.lisp
- decodeStrictBase64
- valid base64 returns buffer with correct bytes
- empty string returns null
- bad padding (length % 4 !== 0) returns null
- non-base64 chars returns null
- whitespace-only returns null (empty after strip)
- pre-decode oversize guard: encoded string > maxEncodedBytes * 2 returns null
- decoded byteLength exceeds maxDecodedBytes returns null
- valid base64 at exact boundary returns Buffer
- spawnSubagentDirect filename validation
- name with / returns attachments_invalid_name
- name '..' returns attachments_invalid_name
- name '.manifest.json' returns attachments_invalid_name
- name with newline returns attachments_invalid_name
- duplicate name returns attachments_duplicate_name
- empty name returns attachments_invalid_name

### src/agents/system-prompt-params.test.lisp
- buildSystemPromptParams repo root
- detects repo root from workspaceDir
- falls back to cwd when workspaceDir has no repo
- uses configured repoRoot when valid
- ignores invalid repoRoot config and auto-detects
- returns undefined when no repo is found

### src/agents/system-prompt-report.test.lisp
- buildSystemPromptReport
- counts injected chars when injected file paths are absolute
- keeps legacy basename matching for injected files
- marks workspace files truncated when injected chars are smaller than raw chars
- includes both bootstrap caps in the report payload
- reports injectedChars=0 when injected file does not match by path or basename
- ignores malformed injected file paths and still matches valid entries

### src/agents/system-prompt-stability.test.lisp
- system prompt stability for cache hits
- returns identical results for same inputs across multiple calls
- returns consistent ordering across calls
- maintains consistency even with missing files
- maintains consistency across concurrent loads

### src/agents/system-prompt.test.lisp
- buildAgentSystemPrompt
- formats owner section for plain, hash, and missing owner lists
- uses a stable, keyed HMAC when ownerDisplaySecret is provided
- omits extended sections in minimal prompt mode
- includes skills in minimal prompt mode when skillsPrompt is provided (cron regression)
- omits skills in minimal prompt mode when skillsPrompt is absent
- includes safety guardrails in full prompts
- includes voice hint when provided
- adds reasoning tag hint when enabled
- includes a command-line interface quick reference section
- guides runtime completion events without exposing internal metadata
- guides subagent workflows to avoid polling loops
- lists available tools when provided
- documents ACP sessions_spawn agent targeting requirements
- guides harness requests to ACP thread-bound spawns
- omits ACP harness guidance when ACP is disabled
- omits ACP harness spawn guidance for sandboxed sessions and shows ACP block note
- preserves tool casing in the prompt
- includes docs guidance when docsPath is provided
- includes workspace notes when provided
- shows timezone section for 12h, 24h, and timezone-only modes
- hints to use session_status for current date/time
- does NOT include a date or time in the system prompt (cache stability)
- includes model alias guidance when aliases are provided
- adds ClaudeBot self-update guidance when gateway tool is available
- includes skills guidance when skills prompt is present
- appends available skills when provided
- omits skills section when no skills prompt is provided
- renders project context files when provided
- ignores context files with missing or blank paths
- adds SOUL guidance when a soul file is present
- renders bootstrap truncation warning even when no context files are injected
- summarizes the message tool when available
- includes inline button style guidance when runtime supports inline buttons
- includes runtime provider capabilities when present
- includes agent id in runtime when provided
- includes reasoning visibility hint
- builds runtime line with agent and channel details
- describes sandboxed runtime and elevated when allowed
- includes reaction guidance when provided
- buildSubagentSystemPrompt
- renders depth-1 orchestrator guidance, labels, and recovery notes
- omits ACP spawning guidance when ACP is disabled
- renders depth-2 leaf guidance with parent orchestrator labels
- omits spawning guidance for depth-1 leaf agents

### src/agents/test-helpers/pi-tools-sandbox-context.test.lisp
- createPiToolsSandboxContext
- provides stable defaults for pi-tools sandbox tests
- applies provided overrides

### src/agents/tool-call-id.test.lisp
- sanitizeToolCallIdsForCloudCodeAssist
- strict mode (default)
- is a no-op for already-valid non-colliding IDs
- strips non-alphanumeric characters from tool call IDs
- avoids collisions when sanitization would produce duplicate IDs
- caps tool call IDs at 40 chars while preserving uniqueness
- strict mode (alphanumeric only)
- strips underscores and hyphens from tool call IDs
- avoids collisions with alphanumeric-only suffixes
- strict9 mode (Mistral tool call IDs)
- is a no-op for already-valid 9-char alphanumeric IDs
- enforces alphanumeric IDs with length 9

### src/agents/tool-display.test.lisp
- tool display details
- skips zero/false values for optional detail fields
- includes only truthy boolean details
- keeps positive numbers and true booleans
- formats read/write/edit with intent-first file detail
- formats web_search query with quotes
- summarizes exec commands with context
- moves cd path to context suffix and appends raw command
- moves cd path to context suffix with multiple stages and raw command
- moves pushd path to context suffix and appends raw command
- clears inferred cwd when popd is stripped from preamble
- moves cd path to context suffix with || separator
- explicit workdir takes priority over cd path
- summarizes all stages and appends raw command
- falls back to raw command for unknown binaries
- falls back to raw command for unknown binary with cwd
- keeps multi-stage summary when only some stages are generic
- handles standalone cd as raw command
- handles chained cd commands using last path
- respects quotes when splitting preamble separators
- recognizes heredoc/inline script exec details

### src/agents/tool-fs-policy.test.lisp
- resolveEffectiveToolFsWorkspaceOnly
- returns false by default when tools.fs.workspaceOnly is unset
- uses global tools.fs.workspaceOnly when no agent override exists
- prefers agent-specific tools.fs.workspaceOnly override over global setting
- supports agent-specific enablement when global workspaceOnly is off

### src/agents/tool-images.log.test.lisp
- tool-images log context
- includes filename from MEDIA text
- includes filename from read label

### src/agents/tool-images.test.lisp
- tool image sanitizing
- shrinks oversized images to <=5MB
- sanitizes image arrays and reports drops
- shrinks images that exceed max dimension even if size is small
- corrects mismatched jpeg mimeType
- drops malformed image base64 payloads

### src/agents/tool-loop-detection.test.lisp
- tool-loop-detection
- hashToolCall
- creates consistent hash for same tool and params
- creates different hashes for different params
- creates different hashes for different tools
- handles non-object params
- produces deterministic hashes regardless of key order
- keeps hashes fixed-size even for large params
- recordToolCall
- adds tool call to empty history
- maintains sliding window of last N calls
- records timestamp for each call
- respects configured historySize
- detectToolCallLoop
- is disabled by default
- does not flag unique tool calls
- warns on generic repeated tool+args calls
- keeps generic loops warn-only below global breaker threshold
- applies custom thresholds when detection is enabled
- can disable specific detectors
- warns for known polling no-progress loops
- blocks known polling no-progress loops at critical threshold
- does not block known polling when output progresses
- blocks any tool with global no-progress breaker at 30
- warns on ping-pong alternating patterns
- blocks ping-pong alternating patterns at critical threshold
- does not block ping-pong at critical threshold when outcomes are progressing
- does not flag ping-pong when alternation is broken
- records fixed-size result hashes for large tool outputs
- handles empty history
- getToolCallStats
- returns zero stats for empty history
- counts total calls and unique patterns
- identifies most frequent pattern

### src/agents/tool-mutation.test.lisp
- tool mutation helpers
- treats session_status as mutating only when model override is provided
- builds stable fingerprints for mutating calls and omits read-only calls
- exposes mutation state for downstream payload rendering
- matches tool actions by fingerprint and fails closed on asymmetric data
- keeps legacy name-only mutating heuristics for payload fallback

### src/agents/tool-policy-pipeline.test.lisp
- tool-policy-pipeline
- strips allowlists that would otherwise disable core tools
- warns about unknown allowlist entries
- applies allowlist filtering when core tools are explicitly listed

### src/agents/tool-policy.plugin-only-allowlist.test.lisp
- stripPluginOnlyAllowlist
- strips allowlist when it only targets plugin tools
- strips allowlist when it only targets plugin groups
- keeps allowlist when it uses "*"
- keeps allowlist when it mixes plugin and core entries
- strips allowlist with unknown entries when no core tools match
- keeps allowlist with core tools and reports unknown entries

### src/agents/tool-policy.test.lisp
- tool-policy
- expands groups and normalizes aliases
- resolves known profiles and ignores unknown ones
- includes core tool groups in group:openclaw
- normalizes tool names and aliases
- identifies owner-only tools
- strips owner-only tools for non-owner senders
- keeps owner-only tools for the owner sender
- honors ownerOnly metadata for custom tool names
- TOOL_POLICY_CONFORMANCE
- matches exported TOOL_GROUPS exactly
- is JSON-serializable
- sandbox tool policy
- allows all tools with * allow
- denies all tools with * deny
- supports wildcard patterns
- applies deny before allow
- treats empty allowlist as allow-all (with deny exceptions)
- expands tool groups + aliases in patterns
- normalizes whitespace + case
- resolveSandboxToolPolicyForAgent
- keeps allow-all semantics when allow is []
- auto-adds image to explicit allowlists unless denied
- does not auto-add image when explicitly denied

### src/agents/tools/agent-step.test.lisp
- readLatestAssistantReply
- returns the most recent assistant message when compaction markers trail history
- falls back to older assistant text when latest assistant has no text

### src/agents/tools/browser-tool.test.lisp
- browser tool snapshot maxChars
- applies the default ai snapshot limit
- respects an explicit maxChars override
- skips the default when maxChars is explicitly zero
- lists profiles
- passes refs mode through to browser snapshot
- uses config snapshot defaults when mode is not provided
- does not apply config snapshot defaults to aria snapshots
- defaults to host when using profile=chrome (even in sandboxed sessions)
- routes to sbcl proxy when target=sbcl
- keeps sandbox bridge url when sbcl proxy is available
- keeps chrome profile on host when sbcl proxy is available
- browser tool url alias support
- accepts url alias for open
- tracks opened tabs when session context is available
- accepts url alias for navigate
- keeps targetUrl required error label when both params are missing
- untracks explicit tab close for tracked sessions
- browser tool act compatibility
- accepts flattened act params for backward compatibility
- prefers request payload when both request and flattened fields are present
- browser tool snapshot labels
- returns image + text when labels are requested
- browser tool external content wrapping
- wraps aria snapshots as external content
- wraps tabs output as external content
- wraps console output as external content
- browser tool act stale target recovery
- retries chrome act once without targetId when tab id is stale

### src/agents/tools/common.params.test.lisp
- createActionGate
- defaults to enabled when unset
- respects explicit false
- readStringOrNumberParam
- returns numeric strings for numbers
- trims strings
- accepts snake_case aliases for camelCase keys
- readNumberParam
- parses numeric strings
- keeps partial parse behavior by default
- rejects partial numeric strings when strict is enabled
- truncates when integer is true
- accepts snake_case aliases for camelCase keys
- required parameter validation
- throws when required values are missing
- readReactionParams
- allows empty emoji for removal semantics
- throws when remove true but emoji empty
- passes through remove flag

### src/agents/tools/common.test.lisp
- parseAvailableTags
- returns undefined for non-array inputs
- drops entries without a string name and returns undefined when empty
- keeps falsy ids and sanitizes emoji fields

### src/agents/tools/cron-tool.flat-params.test.lisp
- cron tool flat-params
- preserves explicit top-level sessionKey during flat-params recovery

### src/agents/tools/cron-tool.test.lisp
- cron tool
- marks cron as owner-only
- prefers jobId over id when both are provided
- supports due-only run mode
- normalizes cron.add job payloads
- does not default agentId when job.agentId is null
- stamps cron.add with caller sessionKey when missing
- preserves explicit job.sessionKey on add
- adds recent context for systemEvent reminders when contextMessages > 0
- caps contextMessages at 10
- does not add context when contextMessages is 0 (default)
- preserves explicit agentId null on add
- infers delivery from threaded session keys
- preserves telegram forum topics when inferring delivery
- infers delivery when delivery is null
- recovers flat params when job is missing
- recovers flat params when job is empty object
- recovers flat message shorthand as agentTurn payload
- does not recover flat params when no meaningful job field is present
- prefers existing non-empty job over flat params
- does not infer delivery when mode is none
- does not infer announce delivery when mode is webhook
- fails fast when webhook mode is missing delivery.to
- fails fast when webhook mode uses a non-http URL
- recovers flat patch params for update action
- recovers additional flat patch params for update action

### src/agents/tools/discord-actions-moderation.authz.test.lisp
- discord moderation sender authorization
- rejects ban when sender lacks BAN_MEMBERS
- rejects kick when sender lacks KICK_MEMBERS
- rejects timeout when sender lacks MODERATE_MEMBERS
- executes moderation action when sender has required permission
- forwards accountId into permission check and moderation execution

### src/agents/tools/discord-actions-presence.test.lisp
- handleDiscordPresenceAction
- sets playing activity
- sets status-only without activity
- defaults status to online
- respects presence gating
- errors when gateway is not registered
- errors when gateway is not connected
- uses accountId to resolve gateway
- requires activityType when activityName is provided
- rejects unknown presence actions

### src/agents/tools/discord-actions.test.lisp
- handleDiscordMessagingAction
- removes reactions on empty emoji
- removes reactions when remove flag set
- rejects removes without emoji
- respects reaction gating
- parses string booleans for poll options
- adds normalized timestamps to readMessages payloads
- adds normalized timestamps to fetchMessage payloads
- adds normalized timestamps to listPins payloads
- adds normalized timestamps to searchMessages payloads
- sends voice messages from a local file path
- forwards trusted mediaLocalRoots into sendMessageDiscord
- rejects voice messages that include content
- forwards optional thread content
- handleDiscordGuildAction - channel management
- creates a channel
- respects channel gating for channelCreate
- forwards accountId for channelList
- edits a channel
- forwards thread edit fields
- deletes a channel
- moves a channel
- creates a category with type=4
- edits a category
- deletes a category
- removes channel permissions
- handleDiscordModerationAction
- forwards accountId for timeout
- handleDiscordAction per-account gating
- allows moderation when account config enables it
- blocks moderation when account omits it
- uses account-merged config, not top-level config
- inherits top-level channel gate when account overrides moderation only
- allows account to explicitly re-enable top-level disabled channel gate

### src/agents/tools/gateway.test.lisp
- gateway tool defaults
- leaves url undefined so callGateway can use config
- accepts allowlisted gatewayUrl overrides (SSRF hardening)
- uses OPENCLAW_GATEWAY_TOKEN for allowlisted local overrides
- falls back to config gateway.auth.token when env is unset for local overrides
- uses gateway.remote.token for allowlisted remote overrides
- does not leak local env/config tokens to remote overrides
- ignores unresolved local token SecretRef for strict remote overrides
- explicit gatewayToken overrides fallback token resolution
- uses least-privilege write scope for write methods
- uses admin scope only for admin methods
- default-denies unknown methods by sending no scopes
- rejects non-allowlisted overrides (SSRF hardening)

### src/agents/tools/image-tool.test.lisp
- image tool implicit imageModel config
- stays disabled without auth when no pairing is possible
- pairs minimax primary with MiniMax-VL-01 (and fallbacks) when auth exists
- pairs minimax-portal primary with MiniMax-VL-01 (and fallbacks) when auth exists
- pairs zai primary with glm-4.6v (and fallbacks) when auth exists
- pairs a custom provider when it declares an image-capable model
- prefers explicit agents.defaults.imageModel
- keeps image tool available when primary model supports images (for explicit requests)
- sends moonshot image requests with user+image payloads only
- exposes an Anthropic-safe image schema without union keywords
- keeps an Anthropic-safe image schema snapshot
- allows workspace images outside default local media roots
- respects fsPolicy.workspaceOnly for non-sandbox image paths
- allows workspace images via createOpenClawCodingTools default workspace root
- sandboxes image paths like the read tool
- applies tools.fs.workspaceOnly to image paths in sandbox mode
- rewrites inbound absolute paths into sandbox media/inbound
- image tool data URL support
- decodes base64 image data URLs
- rejects non-image data URLs
- image tool MiniMax VLM routing
- accepts image for single-image requests and calls /v1/coding_plan/vlm
- accepts images[] for multi-image requests
- combines image + images with dedupe and enforces maxImages
- surfaces MiniMax API errors from /v1/coding_plan/vlm
- image tool response validation
- returns trimmed text from image-model responses

### src/agents/tools/memory-tool.citations.test.lisp
- memory search citations
- appends source information when citations are enabled
- leaves snippet untouched when citations are off
- clamps decorated snippets to qmd injected budget
- honors auto mode for direct chats
- suppresses citations for auto mode in group chats
- memory tools
- does not throw when memory_search fails (e.g. embeddings 429)
- does not throw when memory_get fails
- returns empty text without error when file does not exist (ENOENT)

### src/agents/tools/memory-tool.test.lisp
- memory_search unavailable payloads
- returns explicit unavailable metadata for quota failures
- returns explicit unavailable metadata for non-quota failures

### src/agents/tools/message-tool.test.lisp
- message tool agent routing
- derives agentId from the session key
- message tool path passthrough
- message tool schema scoping
- includes poll in the action enum when the current channel supports poll actions
- hides telegram poll extras when telegram polls are disabled in scoped mode
- message tool description
- hides BlueBubbles group actions for DM targets
- includes other configured channels when currentChannel is set
- does not include 'Other configured channels' when only one channel is configured
- message tool reasoning tag sanitization
- message tool sandbox passthrough
- forwards trusted requesterSenderId to runMessageAction

### src/agents/tools/nodes-tool.test.lisp
- createNodesTool screen_record duration guardrails
- caps durationMs schema at 300000
- clamps screen_record durationMs argument to 300000 before gateway invoke
- omits rawCommand when preparing wrapped argv execution

### src/agents/tools/nodes-utils.test.lisp
- resolveNodeIdFromList defaults
- falls back to most recently connected sbcl when multiple non-Mac candidates exist
- preserves local Mac preference when exactly one local Mac candidate exists
- uses stable nodeId ordering when connectedAtMs is unavailable
- listNodes
- falls back to sbcl.pair.list only when sbcl.list is unavailable
- rethrows unexpected sbcl.list failures without fallback

### src/agents/tools/pdf-tool.test.lisp
- parsePageRange
- parses a single page number
- parses a page range
- parses comma-separated pages and ranges
- clamps to maxPages
- deduplicates and sorts
- throws on invalid page number
- throws on invalid range (start > end)
- throws on zero page number
- throws on negative page number
- handles empty parts gracefully
- providerSupportsNativePdf
- returns true for anthropic
- returns true for google
- returns false for openai
- returns false for minimax
- is case-insensitive
- resolvePdfModelConfigForTool
- returns null without any auth
- prefers explicit pdfModel config
- falls back to imageModel config when no pdfModel set
- prefers anthropic when available for native PDF support
- uses anthropic primary when provider is anthropic
- createPdfTool
- returns null without agentDir and no explicit config
- returns null without any auth configured
- throws when agentDir missing but explicit config present
- creates tool when auth is available
- rejects when no pdf input provided
- rejects too many PDFs
- respects fsPolicy.workspaceOnly for non-sandbox pdf paths
- rejects unsupported scheme references
- deduplicates pdf inputs before loading
- uses native PDF path without eager extraction
- rejects pages parameter for native PDF providers
- uses extraction fallback for non-native models
- tool parameters have correct schema shape
- native PDF provider API calls
- anthropicAnalyzePdf sends correct request shape
- anthropicAnalyzePdf throws on API error
- anthropicAnalyzePdf throws when response has no text
- geminiAnalyzePdf sends correct request shape
- geminiAnalyzePdf throws on API error
- geminiAnalyzePdf throws when no candidates returned
- anthropicAnalyzePdf supports multiple PDFs
- anthropicAnalyzePdf uses custom base URL
- anthropicAnalyzePdf requires apiKey
- geminiAnalyzePdf requires apiKey
- pdf-tool.helpers
- resolvePdfToolMaxTokens respects model limit
- coercePdfModelConfig reads primary and fallbacks
- coercePdfAssistantText returns trimmed text
- coercePdfAssistantText throws clear error for failed model output
- model catalog document support
- modelSupportsDocument returns true when input includes document
- modelSupportsDocument returns false when input lacks document
- modelSupportsDocument returns false for undefined entry

### src/agents/tools/sessions-access.test.lisp
- resolveSessionToolsVisibility
- defaults to tree when unset or invalid
- accepts known visibility values case-insensitively
- resolveEffectiveSessionToolsVisibility
- clamps to tree in sandbox when sandbox visibility is spawned
- preserves visibility when sandbox clamp is all
- sandbox session-tools context
- defaults sandbox visibility clamp to spawned
- restricts non-subagent sandboxed sessions to spawned visibility
- does not restrict subagent sessions in sandboxed mode
- createAgentToAgentPolicy
- denies cross-agent access when disabled
- honors allow patterns when enabled
- createSessionVisibilityGuard
- blocks cross-agent send when agent-to-agent is disabled
- enforces self visibility for same-agent sessions

### src/agents/tools/sessions-resolution.test.lisp
- resolveMainSessionAlias
- uses normalized main key and global alias for global scope
- falls back to per-sender defaults
- uses session.mainKey over any legacy routing sessions key
- session key display/internal mapping
- maps alias and main key to display main
- maps input main to alias for internal routing
- session reference shape detection
- detects session ids
- detects canonical session key families
- treats non-keys as session-id candidates
- resolved session visibility checks
- requires spawned-session verification only for sandboxed key-based cross-session access
- returns true immediately when spawned-session verification is not required

### src/agents/tools/sessions-spawn-tool.test.lisp
- sessions_spawn tool
- uses subagent runtime by default
- passes inherited workspaceDir from tool context, not from tool args
- routes to ACP runtime when runtime=acp
- forwards ACP sandbox options and requester sandbox context
- rejects attachments for ACP runtime
- rejects streamTo when runtime is not "acp"
- keeps attachment content schema unconstrained for llama.cpp grammar safety

### src/agents/tools/sessions.test.lisp
- sanitizeTextContent
- strips minimax tool call XML and downgraded markers
- strips thinking tags
- extractAssistantText
- sanitizes blocks without injecting newlines
- rewrites error-ish assistant text only when the transcript marks it as an error
- keeps normal status text that mentions billing
- resolveAnnounceTarget
- derives non-WhatsApp announce targets from the session key
- hydrates WhatsApp accountId from sessions.list when available
- sessions_list gating
- filters out other agents when tools.agentToAgent.enabled is false
- sessions_list transcriptPath resolution
- resolves cross-agent transcript paths from agent defaults when gateway store path is relative
- resolves transcriptPath even when sessions.list does not return a store path
- falls back to agent defaults when gateway path is non-string
- falls back to agent defaults when gateway path is '(multiple)'
- resolves absolute {agentId} template paths per session agent
- sessions_send gating
- returns an error when neither sessionKey nor label is provided
- returns an error when label resolution fails
- blocks cross-agent sends when tools.agentToAgent.enabled is false

### src/agents/tools/slack-actions.test.lisp
- handleSlackAction
- removes reactions on empty emoji
- removes reactions when remove flag set
- rejects removes without emoji
- respects reaction gating
- passes threadTs to sendSlackMessage for thread replies
- returns a friendly error when downloadFile cannot fetch the attachment
- passes download scope (channel/thread) to downloadSlackFile
- requires at least one of content, blocks, or mediaUrl
- rejects blocks combined with mediaUrl
- requires content or blocks for editMessage
- auto-injects threadTs from context when replyToMode=all
- replyToMode=first threads first message then stops
- replyToMode=first marks hasRepliedRef even when threadTs is explicit
- replyToMode=first without hasRepliedRef does not thread
- does not auto-inject threadTs when replyToMode=off
- does not auto-inject threadTs when sending to different channel
- explicit threadTs overrides context threadTs
- handles channel target without prefix when replyToMode=all
- adds normalized timestamps to readMessages payloads
- passes threadId through to readSlackMessages
- adds normalized timestamps to pin payloads
- uses user token for reads when available
- falls back to bot token for reads when user token missing
- uses bot token for writes when userTokenReadOnly is true
- allows user token writes when bot token is missing
- returns all emojis when no limit is provided
- applies limit to emoji-list results

### src/agents/tools/telegram-actions.test.lisp
- handleTelegramAction
- adds reactions when reactionLevel is minimal
- surfaces non-fatal reaction warnings
- adds reactions when reactionLevel is extensive
- accepts snake_case message_id for reactions
- soft-fails when messageId is missing
- removes reactions on empty emoji
- rejects sticker actions when disabled by default
- sends stickers when enabled
- removes reactions when remove flag set
- soft-fails when reactions are disabled via actions.reactions
- sends a text message
- sends a poll
- parses string booleans for poll flags
- forwards trusted mediaLocalRoots into sendMessageTelegram
- requires content when no mediaUrl is provided
- respects sendMessage gating
- respects poll gating
- deletes a message
- respects deleteMessage gating
- throws on missing bot token for sendMessage
- allows inline buttons by default (allowlist)
- allows inline buttons in DMs with tg: prefixed targets
- allows inline buttons in groups with topic targets
- sends messages with inline keyboard buttons when enabled
- forwards optional button style
- readTelegramButtons
- returns trimmed button rows for valid input
- normalizes optional style
- rejects unsupported button style
- handleTelegramAction per-account gating
- allows sticker when account config enables it
- blocks sticker when account omits it
- uses account-merged config, not top-level config
- inherits top-level reaction gate when account overrides sticker only
- allows account to explicitly re-enable top-level disabled reaction gate

### src/agents/tools/tts-tool.test.lisp
- createTtsTool
- uses SILENT_REPLY_TOKEN in guidance text

### src/agents/tools/web-fetch-visibility.test.lisp
- sanitizeHtml
- strips display:none elements
- strips visibility:hidden elements
- strips opacity:0 elements
- strips font-size:0 elements
- strips text-indent far-offscreen elements
- strips color:transparent elements
- strips color:rgba with zero alpha elements
- strips color:rgba with zero decimal alpha elements
- strips color:hsla with zero alpha elements
- strips transform:scale(0) elements
- strips transform:translateX far-offscreen elements
- strips width:0 height:0 overflow:hidden elements
- strips left far-offscreen positioned elements
- strips clip-path:inset(100%) elements
- strips clip-path:inset(50%) elements
- does not strip clip-path:inset(0%) elements
- strips sr-only class elements
- strips visually-hidden class elements
- strips d-none class elements
- strips hidden class elements
- does not strip elements with hidden as substring of class name
- strips aria-hidden=true elements
- strips elements with hidden attribute
- strips input type=hidden
- strips HTML comments
- strips meta tags
- strips template tags
- strips iframe tags
- preserves visible content
- handles nested hidden elements without removing visible siblings
- handles malformed HTML gracefully
- stripInvisibleUnicode
- strips zero-width space
- strips zero-width non-joiner
- strips zero-width joiner
- strips left-to-right mark
- strips right-to-left mark
- strips directional overrides (LRO, RLO, PDF, etc.)
- strips word joiner and other formatting chars
- preserves normal text unchanged
- strips multiple invisible chars in a row
- handles empty string

### src/agents/tools/web-fetch.cf-markdown.test.lisp
- web_fetch Cloudflare Markdown for Agents
- sends Accept header preferring text/markdown
- uses cf-markdown extractor for text/markdown responses
- falls back to readability for text/html responses
- logs x-markdown-tokens when header is present
- converts markdown to text when extractMode is text
- does not log x-markdown-tokens when header is absent

### src/agents/tools/web-fetch.ssrf.test.lisp
- web_fetch SSRF protection
- blocks localhost hostnames before fetch/firecrawl
- blocks private IP literals without DNS
- blocks when DNS resolves to private addresses
- blocks redirects to private hosts
- allows public hosts

### src/agents/tools/web-guarded-fetch.test.lisp
- web-guarded-fetch
- uses trusted SSRF policy for trusted web tools endpoints
- keeps strict endpoint policy unchanged

### src/agents/tools/web-search.redirect.test.lisp
- web_search redirect resolution hardening
- resolves redirects via SSRF-guarded HEAD requests
- falls back to the original URL when guarded resolution fails

### src/agents/tools/web-search.test.lisp
- web_search brave language param normalization
- normalizes and auto-corrects swapped Brave language params
- flags invalid Brave language formats
- web_search freshness normalization
- accepts Brave shortcut values and maps for Perplexity
- accepts Perplexity values and maps for Brave
- accepts valid date ranges for Brave
- rejects invalid values
- rejects invalid date ranges for Brave
- web_search date normalization
- accepts ISO format
- accepts Perplexity format and converts to ISO
- rejects invalid formats
- converts ISO to Perplexity format
- rejects invalid ISO dates
- web_search grok config resolution
- uses config apiKey when provided
- returns undefined when no apiKey is available
- uses default model when not specified
- uses config model when provided
- defaults inlineCitations to false
- respects inlineCitations config
- web_search grok response parsing
- extracts content from Responses API message blocks
- extracts url_citation annotations from content blocks
- falls back to deprecated output_text
- returns undefined text when no content found
- extracts output_text blocks directly in output array (no message wrapper)
- web_search kimi config resolution
- uses config apiKey when provided
- falls back to KIMI_API_KEY, then MOONSHOT_API_KEY
- returns undefined when no Kimi key is configured
- resolves default model and baseUrl
- extractKimiCitations
- collects unique URLs from search_results and tool arguments

### src/agents/tools/web-tools.enabled-defaults.test.lisp
- web tools defaults
- enables web_fetch by default (non-sandbox)
- disables web_fetch when explicitly disabled
- enables web_search by default
- web_search country and language parameters
- should pass language parameter to Brave API as search_lang
- maps legacy zh language code to Brave zh-hans search_lang
- maps ja language code to Brave jp search_lang
- passes Brave extended language code variants unchanged
- rejects unsupported Brave search_lang values before upstream request
- rejects invalid freshness values
- uses proxy-aware dispatcher when HTTP_PROXY is configured
- web_search provider proxy dispatch
- web_search perplexity Search API
- uses Perplexity Search API when PERPLEXITY_API_KEY is set
- passes country parameter to Perplexity Search API
- uses config API key when provided
- passes freshness filter to Perplexity Search API
- accepts all valid freshness values for Perplexity
- rejects invalid freshness values
- passes domain filter to Perplexity Search API
- passes language to Perplexity Search API as search_language_filter array
- passes multiple filters together to Perplexity Search API
- web_search kimi provider
- returns a setup hint when Kimi key is missing
- runs the Kimi web_search tool flow and echoes tool results
- web_search external content wrapping
- wraps Brave result descriptions
- does not wrap Brave result urls (raw for tool chaining)
- does not wrap Brave site names
- does not wrap Brave published ages

### src/agents/tools/web-tools.fetch.test.lisp
- web_fetch extraction fallbacks
- wraps fetched text with external content markers
- enforces maxChars after wrapping
- honors maxChars even when wrapper overhead exceeds limit
- caps response bytes and does not hang on endless streams
- keeps DNS pinning for untrusted web_fetch URLs even when HTTP_PROXY is configured
- falls back to firecrawl when readability returns no content
- normalizes firecrawl Authorization header values
- throws when readability is disabled and firecrawl is unavailable
- throws when readability is empty and firecrawl fails
- uses firecrawl when direct fetch fails
- wraps external content and clamps oversized maxChars
- strips and truncates HTML from error responses
- strips HTML errors when content-type is missing
- wraps firecrawl error details

### src/agents/tools/web-tools.readability.test.lisp
- web fetch readability
- extracts readable text
- extracts readable markdown

### src/agents/tools/whatsapp-actions.test.lisp
- handleWhatsAppAction
- adds reactions
- removes reactions on empty emoji
- removes reactions when remove flag set
- passes account scope and sender flags
- respects reaction gating
- applies default account allowFrom when accountId is omitted
- routes to resolved default account when no accountId is provided

### src/agents/transcript-policy.policy.test.lisp
- resolveTranscriptPolicy e2e smoke
- uses images-only sanitization without tool-call id rewriting for OpenAI models
- uses strict9 tool-call sanitization for Mistral-family models

### src/agents/transcript-policy.test.lisp
- resolveTranscriptPolicy
- enables sanitizeToolCallIds for Anthropic provider
- enables sanitizeToolCallIds for Google provider
- enables sanitizeToolCallIds for Mistral provider
- disables sanitizeToolCallIds for OpenAI provider
- enables strict tool call id sanitization for openai-completions APIs
- enables user-turn merge for strict OpenAI-compatible providers
- enables Anthropic-compatible policies for Bedrock provider
- preserves thinking signatures for Anthropic provider (#32526)
- preserves thinking signatures for Bedrock Anthropic (#32526)
- does not preserve signatures for Google provider (#32526)
- does not preserve signatures for OpenAI provider (#32526)
- does not preserve signatures for Mistral provider (#32526)
- enables turn-ordering and assistant-merge for strict OpenAI-compatible providers (#38962)
- keeps OpenRouter on its existing turn-validation path

### src/agents/usage.normalization.test.lisp
- normalizeUsage
- normalizes Anthropic-style snake_case usage
- normalizes OpenAI-style prompt/completion usage
- returns undefined for empty usage objects
- guards against empty/zero usage overwrites
- does not clamp derived session total tokens to the context window
- uses prompt tokens when within context window
- prefers explicit prompt token overrides

### src/agents/usage.test.lisp
- normalizeUsage
- normalizes cache fields from provider response
- normalizes cache fields from alternate naming
- handles cache_read and cache_write naming variants
- handles Moonshot/Kimi cached_tokens field
- handles Kimi K2 prompt_tokens_details.cached_tokens field
- clamps negative input to zero (pre-subtracted cached_tokens > prompt_tokens)
- clamps negative prompt_tokens alias to zero
- returns undefined when no valid fields are provided
- handles undefined input
- hasNonzeroUsage
- returns true when cache read is nonzero
- returns true when cache write is nonzero
- returns true when both cache fields are nonzero
- returns false when cache fields are zero
- returns false for undefined usage
- derivePromptTokens
- includes cache tokens in prompt total
- handles missing cache fields
- returns undefined for empty usage
- deriveSessionTotalTokens
- includes cache tokens in total calculation
- prefers promptTokens override over derived total

### src/agents/venice-models.test.lisp
- venice-models
- buildVeniceModelDefinition returns config with required fields
- retries transient fetch failures before succeeding
- uses API maxCompletionTokens for catalog models when present
- retains catalog maxTokens when the API omits maxCompletionTokens
- disables tools for catalog models that do not support function calling
- uses a conservative bounded maxTokens value for new models
- caps new-model maxTokens to the fallback context window when API context is missing
- ignores missing capabilities on partial metadata instead of aborting discovery
- keeps known models discoverable when a row omits model_spec
- falls back to static catalog after retry budget is exhausted

### src/agents/workspace-run.test.lisp
- resolveRunWorkspaceDir
- resolves explicit workspace values without fallback
- falls back to configured per-agent workspace when input is missing
- falls back to default workspace for blank strings
- falls back to built-in main workspace when config is unavailable
- throws for malformed agent session keys
- uses explicit agent id for per-agent fallback when config is unavailable
- throws for malformed agent session keys even when config has a default agent
- treats non-agent legacy keys as default, not malformed

### src/agents/workspace-templates.test.lisp
- resolveWorkspaceTemplateDir
- resolves templates from package root when module url is dist-rooted
- falls back to package-root docs path when templates directory is missing

### src/agents/workspace.bootstrap-cache.test.lisp
- workspace bootstrap file caching
- returns cached content when mtime unchanged
- invalidates cache when mtime changes
- invalidates cache when inode changes with same mtime
- handles file deletion gracefully
- handles concurrent access
- caches files independently by path
- returns missing=true when bootstrap file never existed

### src/agents/workspace.defaults.test.lisp
- DEFAULT_AGENT_WORKSPACE_DIR
- uses OPENCLAW_HOME when resolving the default workspace dir

### src/agents/workspace.load-extra-bootstrap-files.test.lisp
- loadExtraBootstrapFiles
- loads recognized bootstrap files from glob patterns
- keeps path-traversal attempts outside workspace excluded
- supports symlinked workspace roots with realpath checks
- rejects hardlinked aliases to files outside workspace
- skips oversized bootstrap files and reports diagnostics

### src/agents/workspace.test.lisp
- resolveDefaultAgentWorkspaceDir
- uses OPENCLAW_HOME for default workspace resolution
- ensureAgentWorkspace
- creates BOOTSTRAP.md and records a seeded marker for brand new workspaces
- recovers partial initialization by creating BOOTSTRAP.md when marker is missing
- does not recreate BOOTSTRAP.md after completion, even when a core file is recreated
- does not re-seed BOOTSTRAP.md for legacy completed workspaces without state marker
- treats memory-backed workspaces as existing even when template files are missing
- treats git-backed workspaces as existing even when template files are missing
- loadWorkspaceBootstrapFiles
- includes MEMORY.md when present
- includes memory.md when MEMORY.md is absent
- omits memory entries when no memory files exist
- treats hardlinked bootstrap aliases as missing
- filterBootstrapFilesForSession
- returns all files for main session (no sessionKey)
- returns all files for normal (non-subagent, non-cron) session key
- filters to allowlist for subagent sessions
- filters to allowlist for cron sessions

### src/agents/zai.live.test.lisp
- returns assistant text
- glm-4.7 returns assistant text

## auto-reply

### src/auto-reply/chunk.test.lisp
- chunkText
- keeps multi-line text in one chunk when under limit
- splits only when text exceeds the limit
- prefers breaking at a newline before the limit
- otherwise breaks at the last whitespace under the limit
- falls back to a hard break when no whitespace is present
- resolveTextChunkLimit
- uses per-provider defaults
- supports provider overrides
- prefers account overrides when provided
- uses the matching provider override
- chunkMarkdownText
- keeps fenced blocks intact when a safe break exists
- handles multiple fence marker styles when splitting inside fences
- never produces an empty fenced chunk when splitting
- hard-breaks when a parenthetical exceeds the limit
- parses fence spans once for long fenced payloads
- chunkByNewline
- splits text on newlines
- preserves blank lines by folding into the next chunk
- trims whitespace from lines
- preserves leading blank lines on the first chunk
- falls back to length-based for long lines
- does not split long lines when splitLongLines is false
- returns empty array for empty and whitespace-only input
- preserves trailing blank lines on the last chunk
- keeps whitespace when trimLines is false
- chunkTextWithMode
- applies mode-specific chunking behavior
- chunkMarkdownTextWithMode
- applies markdown/newline mode behavior
- handles newline mode fence splitting rules
- resolveChunkMode
- resolves default, provider, account, and internal channel modes

### src/auto-reply/command-auth.owner-default.test.lisp
- senderIsOwner only reflects explicit owner authorization
- does not treat direct-message senders as owners when no ownerAllowFrom is configured
- does not treat group-chat senders as owners when no ownerAllowFrom is configured
- senderIsOwner is false when ownerAllowFrom is configured and sender does not match
- senderIsOwner is true when ownerAllowFrom matches sender
- senderIsOwner is true when ownerAllowFrom is wildcard (*)
- senderIsOwner is true for internal operator.admin sessions

### src/auto-reply/command-control.test.lisp
- resolveCommandAuthorization
- uses explicit owner allowlist when allowFrom is wildcard
- uses owner allowlist override from context when configured
- does not infer a provider from channel allowlists for webchat command contexts
- commands.allowFrom
- uses commands.allowFrom global list when configured
- ignores commandAuthorized when commands.allowFrom is configured
- uses commands.allowFrom provider-specific list over global
- falls back to channel allowFrom when commands.allowFrom not set
- allows all senders when commands.allowFrom includes wildcard
- does not treat conversation ids in From as sender identities
- still falls back to From for direct messages when sender fields are absent
- does not fall back to conversation-shaped From when chat type is missing
- normalizes Discord commands.allowFrom prefixes and mentions
- grants senderIsOwner for internal channel with operator.admin scope
- does not grant senderIsOwner for internal channel without admin scope
- does not grant senderIsOwner for external channel even with admin scope
- control command parsing
- requires slash for send policy
- requires slash for activation
- treats bare commands as non-control
- respects disabled config/debug commands
- requires commands to be the full message
- detects inline command tokens
- ignores telegram commands addressed to other bots

### src/auto-reply/commands-args.test.lisp
- COMMAND_ARG_FORMATTERS
- formats config args (show/get/unset/set) and normalizes values
- formats debug args (show/reset/unset/set)
- formats queue args (order + omission)

### src/auto-reply/commands-registry.test.lisp
- commands registry
- builds command text with args
- exposes native specs
- filters commands based on config flags
- does not enable restricted commands from inherited flags
- appends skill commands when provided
- applies provider-specific native names
- renames status to agentstatus for slack
- keeps discord native command specs within slash-command limits
- keeps ACP native action choices aligned with implemented handlers
- detects known text commands
- ${alias}:
- ${alias} list
- ${alias}: list
- ${alias} list
- ${alias}: list
- try /status
- respects text command gating
- normalizes telegram-style command mentions for the current bot
- keeps telegram-style command mentions for other bots
- normalizes dock command aliases
- commands registry args
- parses positional args and captureRemaining
- serializes args via raw first, then values
- resolves auto arg menus when missing a choice arg
- does not show menus when arg already provided
- resolves function-based choices with a default provider/model context
- does not show menus when args were provided as raw text only

### src/auto-reply/dispatch.test.lisp
- withReplyDispatcher
- always marks complete and waits for idle after success
- still drains dispatcher after run throws
- dispatchInboundMessage owns dispatcher lifecycle

### src/auto-reply/envelope.test.lisp
- formatAgentEnvelope
- includes channel, from, ip, host, and timestamp
- formats timestamps in local timezone by default
- formats timestamps in UTC when configured
- formats timestamps in user timezone when configured
- omits timestamps when configured
- handles missing optional fields
- formatInboundEnvelope
- prefixes sender for non-direct chats
- uses sender fields when senderLabel is missing
- keeps direct messages unprefixed
- includes elapsed time when previousTimestamp is provided
- omits elapsed time when disabled
- prefixes DM body with (self) when fromMe is true
- does not prefix group messages with (self) when fromMe is true
- resolves envelope options from config

### src/auto-reply/fallback-state.test.lisp
- fallback-state
- treats fallback as active only when state matches selected and active refs
- does not treat runtime drift as fallback when persisted state does not match
- marks fallback transition when selected->active pair changes
- normalizes fallback reason whitespace for summaries
- refreshes reason when fallback remains active with same model pair
- marks fallback as cleared when runtime returns to selected model

### src/auto-reply/heartbeat.test.lisp
- stripHeartbeatToken
- skips empty or token-only replies
- drops heartbeats with small junk in heartbeat mode
- drops short remainder in heartbeat mode
- keeps heartbeat replies when remaining content exceeds threshold
- strips token at edges for normal messages
- does not touch token in the middle
- strips HTML-wrapped heartbeat tokens
- strips markdown-wrapped heartbeat tokens
- removes markup-wrapped token and keeps trailing content
- strips trailing punctuation only when directly after the token
- strips a sentence-ending token and keeps trailing punctuation
- strips sentence-ending token with emphasis punctuation in heartbeat mode
- preserves trailing punctuation on text before the token
- isHeartbeatContentEffectivelyEmpty
- returns false for undefined/null (missing file should not skip)
- returns true for empty string
- returns true for whitespace only
- returns true for header-only content
- returns true for comments only
- returns true for default template content (header + comment)
- returns true for header with only empty lines
- returns false when actionable content exists
- returns false for content with tasks after header
- returns false for mixed content with non-comment text
- treats markdown headers as comments (effectively empty)

### src/auto-reply/inbound.test.lisp
- applyTemplate
- renders primitive values
- renders arrays of primitives
- drops object values
- renders missing placeholders as empty
- normalizeInboundTextNewlines
- keeps real newlines
- normalizes CRLF/CR to LF
- preserves literal backslash-n sequences (Windows paths)
- sanitizeInboundSystemTags
- neutralizes bracketed internal markers
- is case-insensitive and handles extra bracket spacing
- neutralizes line-leading System prefixes
- neutralizes line-leading System prefixes in multiline text
- does not rewrite non-line-leading System tokens
- finalizeInboundContext
- fills BodyForAgent/BodyForCommands and normalizes newlines
- sanitizes spoofed system markers in user-controlled text fields
- preserves literal backslash-n in Windows paths
- can force BodyForCommands to follow updated CommandBody
- fills MediaType/MediaTypes defaults only when media exists
- pads MediaTypes to match MediaPaths/MediaUrls length
- derives MediaType from MediaTypes when missing
- inbound dedupe
- builds a stable key when MessageSid is present
- skips duplicates with the same key
- does not dedupe when the peer changes
- does not dedupe across session keys
- createInboundDebouncer
- debounces and combines items
- flushes buffered items before non-debounced item
- supports per-item debounce windows when default debounce is disabled
- initSessionState BodyStripped
- prefers BodyForAgent over Body for group chats
- prefers BodyForAgent over Body for direct chats
- mention helpers
- builds regexes and skips invalid patterns
- openclaw
- normalizes zero-width characters
- matches patterns case-insensitively
- uses per-agent mention patterns when configured
- resolveGroupRequireMention
- respects Discord guild/channel requireMention settings
- respects Slack channel requireMention settings
- respects LINE prefixed group keys in reply-stage requireMention resolution
- preserves plugin-backed channel requireMention resolution

### src/auto-reply/media-note.test.lisp
- buildInboundMediaNote
- formats single MediaPath as a media note
- formats multiple MediaPaths as numbered media notes
- skips media notes for attachments with understanding output
- only suppresses attachments when media understanding succeeded
- suppresses attachments when media understanding succeeds via decisions
- strips audio attachments when transcription succeeded via MediaUnderstanding (issue #4197)
- only strips audio attachments that were transcribed
- strips audio attachments when Transcript is present (issue #4197)
- does not strip multiple audio attachments using transcript-only fallback
- strips audio by extension even without mime type (issue #4197)
- keeps audio attachments when no transcription available

### src/auto-reply/model.test.lisp
- extractModelDirective
- basic /model command
- extracts /model with argument
- does not treat /models as a /model directive
- does not parse /models as a /model directive (no args)
- extracts /model with provider/model format
- extracts /model with profile override
- keeps OpenRouter preset paths that include @ in the model name
- still allows profile overrides after OpenRouter preset paths
- keeps Cloudflare @cf path segments inside model ids
- allows profile overrides after Cloudflare @cf path segments
- returns no directive for plain text
- alias shortcuts
- recognizes /gpt as model directive when alias is configured
- recognizes /gpt: as model directive when alias is configured
- recognizes /sonnet as model directive
- recognizes alias mid-message
- is case-insensitive for aliases
- does not match alias without leading slash
- does not match unknown aliases
- prefers /model over alias when both present
- handles empty aliases array
- handles undefined aliases
- edge cases
- absorbs path-like segments when /model includes extra slashes
- handles alias with special regex characters
- does not match partial alias
- handles empty body
- handles undefined body

### src/auto-reply/reply.block-streaming.test.lisp
- block streaming
- handles ordering, timeout fallback, and telegram streamMode block
- trims leading whitespace in block-streamed replies
- still parses media directives for direct block payloads

### src/auto-reply/reply.directive.directive-behavior.applies-inline-reasoning-mixed-messages-acks-immediately.test.lisp
- directive behavior
- keeps reasoning acks out of mixed messages, including rapid repeats
- handles standalone verbose directives and persistence
- updates tool verbose during in-flight runs for toggle on/off
- covers think status and /thinking xhigh support matrix
- keeps reserved command aliases from matching after trimming
- treats skill commands as reserved for model aliases
- reports invalid queue options and current queue settings

### src/auto-reply/reply.directive.directive-behavior.defaults-think-low-reasoning-capable-models-no.test.lisp
- directive behavior
- covers /think status and reasoning defaults for reasoning and non-reasoning models
- renders model list and status variants across catalog/config combinations
- sets model override on /model directive
- ignores inline /model and /think directives while still running agent content
- passes elevated defaults when sender is approved
- persists /reasoning off on discord even when model defaults reasoning on
- handles reply_to_current tags and explicit reply_to precedence

### src/auto-reply/reply.directive.directive-behavior.prefers-alias-matches-fuzzy-selection-is-ambiguous.test.lisp
- directive behavior
- supports unambiguous fuzzy model matches across /model forms
- picks the best fuzzy match for global and provider-scoped minimax queries
- prefers alias matches when fuzzy selection is ambiguous
- stores auth profile overrides on /model directive
- queues system events for model, elevated, and reasoning directives

### src/auto-reply/reply.directive.directive-behavior.shows-current-verbose-level-verbose-has-no.test.lisp
- directive behavior
- reports current directive defaults when no arguments are provided
- persists elevated toggles across /status and /elevated
- enforces per-agent elevated restrictions and status visibility
- applies per-agent allowlist requirements before allowing elevated
- handles runtime warning, invalid level, and multi-directive elevated inputs
- persists queue overrides and reset behavior
- strips inline elevated directives from the user text (does not persist session override)

### src/auto-reply/reply.directive.parse.test.lisp
- directive parsing
- ignores verbose directive inside URL
- ignores typoed /verioussmith
- ignores think directive inside URL
- matches verbose with leading space
- matches reasoning directive
- matches reasoning stream directive
- matches elevated with leading space
- matches elevated ask
- matches elevated full
- matches think at start of line
- does not match /think followed by extra letters
- matches /think with no argument
- matches /t with no argument
- matches think with no argument and consumes colon
- matches verbose with no argument
- matches reasoning with no argument
- matches elevated with no argument
- matches exec directive with options
- captures invalid exec host values
- matches queue directive
- preserves spacing when stripping think directives before paths
- preserves spacing when stripping verbose directives before paths
- preserves spacing when stripping reasoning directives before paths
- preserves spacing when stripping status directives before paths
- does not treat /usage as a status directive
- parses queue options and modes
- extracts reply_to_current tag
- extracts reply_to_current tag with whitespace
- extracts reply_to id tag
- extracts reply_to id tag with whitespace
- preserves newlines when stripping reply tags

### src/auto-reply/reply.heartbeat-typing.test.lisp
- getReplyFromConfig typing (heartbeat)
- starts typing for normal runs
- does not start typing for heartbeat runs

### src/auto-reply/reply.media-note.test.lisp
- getReplyFromConfig media note plumbing
- includes all MediaPaths in the agent prompt

### src/auto-reply/reply.raw-body.test.lisp
- RawBody directive parsing
- handles directives and history in the prompt

### src/auto-reply/reply.triggers.trigger-handling.stages-inbound-media-into-sandbox-workspace.test.lisp
- stageSandboxMedia
- stages allowed media and blocks unsafe paths
- blocks destination symlink escapes when staging into sandbox workspace
- skips oversized media staging and keeps original media paths

### src/auto-reply/reply.triggers.trigger-handling.targets-active-session-native-stop.e2e.test.lisp
- trigger handling
- handles trigger command and heartbeat flows end-to-end

### src/auto-reply/reply/abort.test.lisp
- abort detection
- triggerBodyNormalized extracts /stop from RawBody for abort detection
- isAbortTrigger matches standalone abort trigger phrases
- isAbortRequestText aligns abort command semantics
- removes abort memory entry when flag is reset
- caps abort memory tracking to a bounded max size
- extracts abort cutoff metadata from context
- treats numeric message IDs at or before cutoff as stale
- falls back to timestamp cutoff when message IDs are unavailable
- resolves session entry when key exists in store
- resolves Telegram forum topic session when lookup key has different casing than store
- fast-aborts even when text commands are disabled
- fast-abort clears queued followups and session lane
- plain-language stop on ACP-bound session triggers ACP cancel
- ACP cancel failures do not skip queue and lane cleanup
- persists abort cutoff metadata on /stop when command and target session match
- does not persist cutoff metadata when native /stop targets a different session
- fast-abort stops active subagent runs for requester session
- cascade stop kills depth-2 children when stopping depth-1 agent
- cascade stop traverses ended depth-1 parents to stop active depth-2 children

### src/auto-reply/reply/acp-projector.test.lisp
- createAcpReplyProjector
- coalesces text deltas into bounded block chunks
- does not suppress identical short text across terminal turn boundaries
- flushes staggered live text deltas after idle gaps
- splits oversized live text by maxChunkChars
- does not flush short live fragments mid-phrase on idle
- supports deliveryMode=final_only by buffering all projected output until done
- flushes buffered status/tool output on error in deliveryMode=final_only
- suppresses usage_update by default and allows deduped usage when tag-visible
- hides available_commands_update by default
- dedupes repeated tool lifecycle updates when repeatSuppression is enabled
- keeps terminal tool updates even when rendered summaries are truncated
- renders fallback tool labels without leaking call ids as primary label
- allows repeated status/tool summaries when repeatSuppression is disabled
- suppresses exact duplicate status updates when repeatSuppression is enabled
- truncates oversized turns once and emits one truncation notice
- supports tagVisibility overrides for tool updates
- inserts a space boundary before visible text after hidden tool updates by default
- preserves hidden boundary across nonterminal hidden tool updates
- supports hiddenBoundarySeparator=space
- supports hiddenBoundarySeparator=none
- does not duplicate newlines when previous visible text already ends with newline
- does not insert boundary separator for hidden non-tool status updates

### src/auto-reply/reply/acp-stream-settings.test.lisp
- acp stream settings
- resolves stable defaults
- applies explicit stream overrides
- accepts explicit deliveryMode=live override
- uses default tag visibility when no override is provided
- respects tag visibility overrides
- resolves chunking/coalescing from ACP stream controls
- applies live-mode streaming overrides for incremental delivery

### src/auto-reply/reply/agent-runner-helpers.test.lisp
- agent runner helpers
- detects audio payloads from mediaUrl/mediaUrls
- uses fallback verbose level when session context is missing
- uses session verbose level when present
- falls back when store read fails or session value is invalid
- schedules followup drain and returns the original value
- signals typing only when any payload has text or media

### src/auto-reply/reply/agent-runner-payloads.test.lisp
- buildReplyPayloads media filter integration
- strips media URL from payload when in messagingToolSentMediaUrls
- preserves media URL when not in messagingToolSentMediaUrls
- normalizes sent media URLs before deduping normalized reply media
- drops only invalid media when reply media normalization fails
- applies media filter after text filter
- does not dedupe text for cross-target messaging sends
- does not dedupe media for cross-target messaging sends
- suppresses same-target replies when messageProvider is synthetic but originatingChannel is set
- suppresses same-target replies when message tool target provider is generic
- suppresses same-target replies when target provider is channel alias
- does not suppress same-target replies when accountId differs

### src/auto-reply/reply/agent-runner-utils.test.lisp
- agent-runner-utils
- resolves model fallback options from run context
- passes through missing agentId for helper-based fallback resolution
- builds embedded run base params with auth profile and run metadata
- builds embedded contexts and scopes auth profile by provider
- prefers OriginatingChannel over Provider for messageProvider

### src/auto-reply/reply/agent-runner.media-paths.test.lisp
- runReplyAgent media path normalization
- normalizes final MEDIA replies against the run workspace

### src/auto-reply/reply/agent-runner.misc.runreplyagent.test.lisp
- runReplyAgent onAgentRunStart
- does not emit start callback when fallback fails before run start
- emits start callback when cli runner starts
- runReplyAgent authProfileId fallback scoping
- drops authProfileId when provider changes during fallback
- runReplyAgent auto-compaction token update
- updates totalTokens after auto-compaction using lastCallUsage
- updates totalTokens from lastCallUsage even without compaction
- does not enqueue legacy post-compaction audit warnings
- runReplyAgent block streaming
- coalesces duplicate text_end block replies
- returns the final payload when onBlockReply times out
- runReplyAgent claude-cli routing
- uses claude-cli runner for claude-cli provider
- runReplyAgent messaging tool suppression
- drops replies when a messaging tool sent via the same provider + target
- delivers replies when tool provider does not match
- keeps final reply when text matches a cross-target messaging send
- delivers replies when account ids do not match
- persists usage fields even when replies are suppressed
- persists totalTokens from promptTokens when snapshot is available
- persists totalTokens from promptTokens when provider omits usage
- runReplyAgent reminder commitment guard
- appends guard note when reminder commitment is not backed by cron.add
- keeps reminder commitment unchanged when cron.add succeeded
- suppresses guard note when session already has an active cron job
- still appends guard note when cron jobs exist but not for the current session
- still appends guard note when cron jobs for session exist but are disabled
- still appends guard note when sessionKey is missing
- still appends guard note when cron store read fails
- runReplyAgent fallback reasoning tags
- enforces <final> when the fallback provider requires reasoning tags
- enforces <final> during memory flush on fallback providers
- runReplyAgent response usage footer
- appends session key when responseUsage=full
- does not append session key when responseUsage=tokens
- runReplyAgent transient HTTP retry
- retries once after transient 521 HTML failure and then succeeds

### src/auto-reply/reply/agent-runner.runreplyagent.e2e.test.lisp
- runReplyAgent heartbeat followup guard
- drops heartbeat runs when another run is active
- still enqueues non-heartbeat runs when another run is active
- drains followup queue when an unexpected exception escapes the run path
- runReplyAgent typing (heartbeat)
- signals typing for normal runs
- never signals typing for heartbeat runs
- suppresses NO_REPLY partials but allows normal No-prefix partials
- does not start typing on assistant message start without prior text in message mode
- starts typing from reasoning stream in thinking mode
- keeps assistant partial streaming enabled when reasoning mode is stream
- suppresses typing in never mode
- signals typing on normalized block replies
- handles typing for normal and silent tool results
- retries transient HTTP failures once with timer-driven backoff
- delivers tool results in order even when dispatched concurrently
- continues delivering later tool results after an earlier tool result fails
- announces auto-compaction in verbose mode and tracks count
- announces model fallback only when verbose mode is enabled
- announces model fallback only once per active fallback state
- re-announces model fallback after returning to selected model
- announces fallback-cleared once when runtime returns to selected model
- emits fallback lifecycle events while verbose is off
- updates fallback reason summary while fallback stays active
- retries after compaction failure by resetting the session
- retries after context overflow payload by resetting the session
- surfaces overflow fallback when embedded run returns empty payloads
- surfaces overflow fallback when embedded payload text is whitespace-only
- resets the session after role ordering payloads
- resets corrupted Gemini sessions and deletes transcripts
- keeps sessions intact on other errors
- still replies even if session reset fails to persist
- returns friendly message for role ordering errors thrown as exceptions
- rewrites Bun socket errors into friendly text
- runReplyAgent memory flush
- skips memory flush for command-line interface providers
- uses configured prompts for memory flush runs
- passes stored bootstrap warning signatures to memory flush runs
- runs a memory flush turn and updates session metadata
- runs memory flush when transcript fallback uses a relative sessionFile path
- forces memory flush when transcript file exceeds configured byte threshold
- skips memory flush when disabled in config
- skips memory flush after a prior flush in the same compaction cycle
- increments compaction count when flush compaction completes

### src/auto-reply/reply/block-streaming.test.lisp
- resolveEffectiveBlockStreamingConfig
- applies ACP-style overrides while preserving chunk/coalescer bounds
- reuses caller-provided chunking for shared main/subagent/ACP config resolution
- allows ACP maxChunkChars overrides above base defaults up to provider text limits

### src/auto-reply/reply/commands-acp.test.lisp
- /acp command
- returns null when the message is not /acp
- shows help by default
- spawns an ACP session and binds a Discord thread
- accepts unicode dash option prefixes in /acp spawn args
- binds Telegram topic ACP spawns to full conversation ids
- binds Telegram DM ACP spawns to the DM conversation id
- requires explicit ACP target when acp.defaultAgent is not configured
- rejects thread-bound ACP spawn when spawnAcpSessions is disabled
- forbids /acp spawn from sandboxed requester sessions
- cancels the ACP session bound to the current thread
- sends steer instructions via ACP runtime
- resolves bound Telegram topic ACP sessions for /acp steer without explicit target
- blocks /acp steer when ACP dispatch is disabled by policy
- closes an ACP session, unbinds thread targets, and clears metadata
- lists ACP sessions from the session store
- shows ACP status for the thread-bound ACP session
- updates ACP runtime mode via /acp set-mode
- updates ACP config options and keeps cwd local when using /acp set
- rejects non-absolute cwd values via ACP runtime option validation
- rejects invalid timeout values before backend config writes
- returns actionable doctor output when backend is missing
- shows deterministic install instructions via /acp install

### src/auto-reply/reply/commands-acp/context.test.lisp
- commands-acp context
- resolves channel/account/thread context from originating fields
- resolves discord thread parent from ParentSessionKey when targets point at the thread
- resolves discord thread parent from native context when ParentSessionKey is absent
- falls back to default account and target-derived conversation id
- builds canonical telegram topic conversation ids from originating chat + thread
- resolves Telegram DM conversation ids from telegram targets

### src/auto-reply/reply/commands-acp/install-hints.test.lisp
- ACP install hints
- prefers explicit runtime install command
- uses local acpx extension path when present
- falls back to Quicklisp/Ultralisp install hint for acpx when local extension is absent
- returns generic plugin hint for non-acpx backend

### src/auto-reply/reply/commands-acp/shared.test.lisp
- parseSteerInput
- preserves non-option instruction tokens while normalizing unicode-dash flags

### src/auto-reply/reply/commands-context-report.test.lisp
- buildContextReply
- shows bootstrap truncation warning in list output when context exceeds configured limits
- does not show bootstrap truncation warning when there is no truncation
- falls back to config defaults when legacy reports are missing bootstrap limits

### src/auto-reply/reply/commands-session-lifecycle.test.lisp
- /session idle and /session max-age
- sets idle timeout for the focused Discord session
- shows active idle timeout when no value is provided
- sets max age for the focused Discord session
- sets idle timeout for focused Telegram conversations
- reports Telegram max-age expiry from the original bind time
- disables max age when set to off
- is unavailable outside discord and telegram
- requires binding owner for lifecycle updates

### src/auto-reply/reply/commands-setunset.test.lisp
- parseSetUnsetCommand
- parses unset values
- parses set values
- parseSetUnsetCommandAction
- returns null for non set/unset actions
- maps parse errors through onError
- parseSlashCommandWithSetUnset
- returns null when the input does not match the slash command
- prefers set/unset mapping and falls back to known actions
- returns onError for unknown actions
- parseStandardSetUnsetSlashCommand
- uses default set/unset/error mappings
- supports caller-provided mappings

### src/auto-reply/reply/commands-subagents-focus.test.lisp
- /focus, /unfocus, /agents
- /focus resolves ACP sessions and binds the current Discord thread
- /focus binds Telegram topics as current conversations
- /focus includes ACP session identifiers in intro text when available
- /unfocus removes an active binding for the binding owner
- /focus rejects rebinding when the thread is focused by another user
- /agents includes active conversation bindings on the current channel/account
- /agents keeps finished session-mode runs visible while binding remains
- /focus rejects unsupported channels

### src/auto-reply/reply/commands-subagents-spawn.test.lisp
- /subagents spawn command
- shows usage when agentId is missing
- shows usage when task is missing
- spawns subagent and confirms reply text and child session key
- spawns with --model flag and passes model to spawnSubagentDirect
- spawns with --thinking flag and passes thinking to spawnSubagentDirect
- passes group context from session entry to spawnSubagentDirect
- prefers CommandTargetSessionKey for native /subagents spawn
- falls back to OriginatingTo for agentTo when command.to is missing
- returns forbidden for unauthorized cross-agent spawn
- allows cross-agent spawn when in allowlist
- ignores unauthorized sender (silent, no reply)
- returns null when text commands disabled

### src/auto-reply/reply/commands.test.lisp
- handleCommands gating
- blocks gated commands when disabled or not elevated-allowlisted
- /approve command
- rejects invalid usage
- submits approval
- rejects gateway clients without approvals scope
- allows gateway clients with approvals or admin scopes
- /compact command
- returns null when command is not /compact
- rejects unauthorized /compact commands
- routes manual compaction with explicit trigger and context metadata
- abort trigger command
- rejects unauthorized natural-language abort triggers
- buildCommandsPaginationKeyboard
- adds agent id to callback data when provided
- parseConfigCommand
- parses config/debug command actions and JSON payloads
- extractMessageText
- preserves user markers and sanitizes assistant markers
- handleCommands /config configWrites gating
- blocks /config set when channel config writes are disabled
- blocks /config set from gateway clients without operator.admin
- keeps /config show available to gateway operator.write clients
- keeps /config set working for gateway operator.admin clients
- handleCommands bash alias
- routes !poll and !stop through the /bash handler
- handleCommands /allowlist
- lists config + store allowFrom entries
- adds entries to config and pairing store
- writes store entries to the selected account scope
- removes default-account entries from scoped and legacy pairing stores
- rejects blocked account ids and keeps Object.prototype clean
- removes DM allowlist entries from canonical allowFrom and deletes legacy dm.allowFrom
- /models command
- rejects unauthorized /models commands
- lists providers on telegram (buttons)
- handles provider model pagination, all mode, and unknown providers
- lists configured models outside the curated catalog
- threads the routed agent through /models replies
- handleCommands plugin commands
- dispatches registered plugin commands
- handleCommands identity
- returns sender details for /whoami
- handleCommands hooks
- triggers hooks for /new with arguments
- triggers hooks for native /new routed to target sessions
- handleCommands ACP-bound /new and /reset
- handles /new as ACP in-place reset for bound conversations
- continues with trailing prompt text after successful ACP-bound /new
- handles /reset failures without falling back to normal session reset flow
- does not emit reset hooks when ACP reset fails
- keeps existing /new behavior for non-ACP sessions
- still targets configured ACP binding when runtime routing falls back to a non-ACP session
- emits reset hooks for the ACP session key when routing falls back to non-ACP session
- uses active ACP command target when conversation binding context is missing
- handleCommands context
- returns expected details for /context commands
- handleCommands subagents
- lists subagents when none exist
- truncates long subagent task text in /subagents list
- lists subagents for the command target session for native /subagents
- keeps ended orchestrators in active list while descendants are pending
- formats subagent usage with io and prompt/cache breakdown
- returns help/usage for invalid or incomplete subagents commands
- returns info for a subagent
- kills subagents via /kill alias without a confirmation reply
- resolves numeric aliases in active-first display order
- sends follow-up messages to finished subagents
- steers subagents via /steer alias
- restores announce behavior when /steer replacement dispatch fails
- handleCommands /tts
- returns status for bare /tts on text command surfaces

### src/auto-reply/reply/directive-handling.auth.test.lisp
- resolveAuthLabel ref-aware labels
- shows api-key (ref) for keyRef-only profiles in compact mode
- shows token (ref) for tokenRef-only profiles in compact mode
- uses token:ref instead of token:missing in verbose mode

### src/auto-reply/reply/directive-handling.levels.test.lisp
- resolveCurrentDirectiveLevels
- prefers resolved model default over agent thinkingDefault
- keeps session thinking override without consulting defaults

### src/auto-reply/reply/directive-handling.model.test.lisp
- /model chat UX
- shows summary for /model with no args
- shows active runtime model when different from selected model
- auto-applies closest match for typos
- rejects numeric /model selections with a guided error
- treats explicit default /model selection as resettable default
- keeps openrouter provider/model split for exact selections
- keeps cloudflare @cf model segments for exact selections
- handleDirectiveOnly model persist behavior (fixes #1435)
- shows success message when session state is available
- shows no model message when no /model directive
- persists thinkingLevel=off (does not clear)

### src/auto-reply/reply/dispatch-acp-delivery.test.lisp
- createAcpDispatchDeliveryCoordinator
- starts reply lifecycle only once when called directly and through deliver
- starts reply lifecycle once when deliver triggers first
- does not start reply lifecycle for empty payload delivery

### src/auto-reply/reply/dispatch-acp.test.lisp
- tryDispatchAcpReply
- routes ACP block output to originating channel
- edits ACP tool lifecycle updates in place when supported
- falls back to new tool message when edit fails
- starts reply lifecycle when ACP turn starts, including hidden-only turns
- starts reply lifecycle once per turn when output is delivered
- does not start reply lifecycle for empty ACP prompt
- surfaces ACP policy errors as final error replies

### src/auto-reply/reply/dispatch-from-config.test.lisp
- dispatchReplyFromConfig
- does not route when Provider matches OriginatingChannel (even if Surface is missing)
- routes when OriginatingChannel differs from Provider
- forces suppressTyping when routing to a different originating channel
- forces suppressTyping for internal webchat turns
- routes when provider is webchat but surface carries originating channel metadata
- routes Feishu replies when provider is webchat and origin metadata points to Feishu
- does not route when provider already matches originating channel
- does not route external origin replies when current surface is internal webchat without explicit delivery
- routes external origin replies for internal webchat turns when explicit delivery is set
- routes media-only tool results when summaries are suppressed
- provides onToolResult in DM sessions
- suppresses group tool summaries but still forwards tool media
- sends tool results via dispatcher in DM sessions
- suppresses native tool summaries but still forwards tool media
- fast-aborts without calling the reply resolver
- fast-abort reply includes stopped subagent count when provided
- routes ACP sessions through the runtime branch and streams block replies
- posts a one-time resolved-session-id notice in thread after the first ACP turn
- posts resolved-session-id notice when ACP session is bound even without MessageThreadId
- honors send-policy deny before ACP runtime dispatch
- routes ACP slash commands through the normal command pipeline
- routes ACP reset tails through ACP after command handling
- does not bypass ACP slash aliases when text commands are disabled on native surfaces
- does not bypass ACP dispatch for unauthorized bang-prefixed messages
- does not bypass ACP dispatch for bang-prefixed messages when text commands are disabled
- coalesces tiny ACP token deltas into normal Discord text spacing
- generates final-mode TTS audio after ACP block streaming completes
- routes ACP block output to originating channel without parent dispatcher duplicates
- closes oneshot ACP sessions after the turn completes
- emits an explicit ACP policy error when dispatch is disabled
- fails closed when ACP metadata is missing for an ACP session key
- surfaces backend-missing ACP errors in-thread without falling back
- deduplicates inbound messages by MessageSid and origin
- emits message_received hook with originating channel metadata
- emits internal message:received hook when a session key is available
- skips internal message:received hook when session key is unavailable
- emits diagnostics when enabled
- marks diagnostics skipped for duplicate inbound messages
- suppresses isReasoning payloads from final replies (WhatsApp channel)
- suppresses isReasoning payloads from block replies (generic dispatch path)

### src/auto-reply/reply/export-html/template.security.test.lisp
- export html security hardening
- escapes raw HTML from markdown blocks
- escapes tree and header metadata fields
- sanitizes image MIME types used in data URLs
- flattens remote markdown images but keeps data-image markdown
- escapes markdown data-image attributes

### src/auto-reply/reply/followup-runner.test.lisp
- createFollowupRunner compaction
- adds verbose auto-compaction notice and tracks count
- createFollowupRunner bootstrap warning dedupe
- passes stored warning signature history to embedded followup runs
- createFollowupRunner messaging tool dedupe
- drops payloads already sent via messaging tool
- delivers payloads when not duplicates
- suppresses replies when a messaging tool sent via the same provider + target
- suppresses replies when provider is synthetic but originating channel matches
- does not suppress replies for same target when account differs
- drops media URL from payload when messaging tool already sent it
- delivers media payload when not a duplicate
- persists usage even when replies are suppressed
- does not fall back to dispatcher when cross-channel origin routing fails
- falls back to dispatcher when same-channel origin routing fails
- routes followups with originating account/thread metadata
- createFollowupRunner typing cleanup
- calls both markRunComplete and markDispatchIdle on NO_REPLY
- calls both markRunComplete and markDispatchIdle on empty payloads
- calls both markRunComplete and markDispatchIdle on agent error
- calls both markRunComplete and markDispatchIdle on successful delivery
- createFollowupRunner agentDir forwarding
- passes queued run agentDir to runEmbeddedPiAgent

### src/auto-reply/reply/get-reply-inline-actions.skip-when-config-empty.test.lisp
- handleInlineActions
- skips whatsapp replies when config is empty and From !== To
- forwards agentDir into handleCommands
- skips stale queued messages that are at or before the /stop cutoff
- clears /stop cutoff when a newer message arrives

### src/auto-reply/reply/get-reply-run.media-only.test.lisp
- runPreparedReply media-only handling
- allows media-only prompts and preserves thread context in queued followups
- keeps thread history context on follow-up turns
- returns the empty-body reply when there is no text and no media
- omits auth key labels from /new and /reset confirmation messages
- skips reset notice when only webchat fallback routing is available
- uses inbound origin channel for run messageProvider
- prefers Provider over Surface when origin channel is missing
- passes suppressTyping through typing mode resolution
- routes queued system events into user prompt text, not system prompt context
- preserves first-token think hint when system events are prepended
- carries system events into followupRun.prompt for deferred turns
- does not strip think-hint token from deferred queue body

### src/auto-reply/reply/get-reply.message-hooks.test.lisp
- getReplyFromConfig message hooks
- emits transcribed + preprocessed hooks with enriched context
- emits only preprocessed when no transcript is produced
- skips message hooks in fast test mode
- skips message hooks when SessionKey is unavailable

### src/auto-reply/reply/get-reply.reset-hooks-fallback.test.lisp
- getReplyFromConfig reset-hook fallback
- emits reset hooks when inline actions return early without marking resetHookTriggered
- does not emit fallback hooks when resetHookTriggered is already set

### src/auto-reply/reply/inbound-meta.test.lisp
- buildInboundMetaSystemPrompt
- includes session-stable routing fields
- does not include per-turn message identifiers (cache stability)
- does not include per-turn flags in system metadata
- omits sender_id when blank
- buildInboundUserContextPrefix
- omits conversation label block for direct chats
- hides message identifiers for direct webchat chats
- includes message identifiers for direct external-channel chats
- includes message identifiers for direct chats when channel is inferred from Provider
- does not treat group chats as direct based on sender id
- keeps conversation label for group chats
- includes sender identifier in conversation info
- prefers SenderName in conversation info sender identity
- includes sender metadata block for direct chats
- includes formatted timestamp in conversation info when provided
- omits invalid timestamps instead of throwing
- includes message_id in conversation info
- prefers MessageSid when both MessageSid and MessageSidFull are present
- falls back to MessageSidFull when MessageSid is missing
- includes reply_to_id in conversation info
- includes sender_id in conversation info
- includes dynamic per-turn flags in conversation info
- trims sender_id in conversation info
- falls back to SenderId when sender phone is missing

### src/auto-reply/reply/memory-flush.test.lisp
- resolveMemoryFlushPromptForRun
- replaces YYYY-MM-DD using user timezone and appends current time
- does not append a duplicate current time line
- DEFAULT_MEMORY_FLUSH_PROMPT
- includes append-only instruction to prevent overwrites (#6877)
- includes anti-fragmentation instruction to prevent timestamped variant files (#34919)

### src/auto-reply/reply/mentions.test.lisp
- stripStructuralPrefixes
- returns empty string for undefined input at runtime
- returns empty string for empty input
- strips sender prefix labels
- passes through plain text

### src/auto-reply/reply/message-preprocess-hooks.test.lisp
- emitPreAgentMessageHooks
- emits transcribed and preprocessed events when transcript exists
- emits only preprocessed when transcript is missing
- skips hook emission in fast-test mode
- skips hook emission without session key

### src/auto-reply/reply/model-selection.test.lisp
- createModelSelectionState parent inheritance
- inherits parent override from explicit parentSessionKey
- derives parent key from topic session suffix
- prefers child override over parent
- ignores parent override when disallowed
- applies stored override when heartbeat override was not resolved
- skips stored override when heartbeat override was resolved
- createModelSelectionState respects session model override
- applies session modelOverride when set
- falls back to default when no modelOverride is set
- respects modelOverride even when session model field differs
- uses default provider when providerOverride is not set but modelOverride is
- createModelSelectionState resolveDefaultReasoningLevel
- returns on when catalog model has reasoning true
- returns off when catalog model has no reasoning

### src/auto-reply/reply/origin-routing.test.lisp
- origin-routing helpers
- prefers originating channel over provider for message provider
- falls back to provider when originating channel is missing
- prefers originating destination over fallback destination
- prefers originating account over fallback account

### src/auto-reply/reply/post-compaction-context.test.lisp
- readPostCompactionContext
- returns null when no AGENTS.md exists
- returns null when AGENTS.md has no relevant sections
- extracts Session Startup section
- extracts Red Lines section
- extracts both sections
- truncates when content exceeds limit
- matches section names case-insensitively
- matches H3 headings
- skips sections inside code blocks
- includes sub-headings within a section
- substitutes YYYY-MM-DD with the actual date in extracted sections
- appends current time line even when no YYYY-MM-DD placeholder is present
- agents.defaults.compaction.postCompactionSections
- uses default sections (Session Startup + Red Lines) when config is not set
- uses custom section names from config instead of defaults
- supports multiple custom section names
- returns null when postCompactionSections is explicitly set to [] (opt-out)
- returns null when custom sections are configured but none found in AGENTS.md
- does NOT reference 'Session Startup' in prose when custom sections are configured
- uses default 'Session Startup' prose when default sections are active
- falls back to legacy sections when defaults are explicitly configured
- falls back to legacy sections when default sections are configured in a different order
- custom section names are matched case-insensitively

### src/auto-reply/reply/queue-policy.test.lisp
- resolveActiveRunQueueAction
- runs immediately when there is no active run
- drops heartbeat runs while another run is active
- enqueues followups for non-heartbeat active runs
- enqueues steer mode runs while active

### src/auto-reply/reply/reply-elevated.test.lisp
- resolveElevatedPermissions
- authorizes when sender matches allowFrom
- does not authorize when only recipient matches allowFrom
- does not authorize untyped mutable sender fields
- authorizes mutable sender fields only with explicit prefix

### src/auto-reply/reply/reply-flow.test.lisp
- normalizeInboundTextNewlines
- normalizes real newlines and preserves literal backslash-n sequences
- inbound context contract (providers + extensions)
- hasLineDirectives
- matches expected detection across directive patterns
- parseLineDirectives
- quick_replies
- parses quick replies variants
- location
- parses location variants
- confirm
- parses confirm directives with default and custom action payloads
- buttons
- parses message/uri/postback button actions and enforces action caps
- media_player
- parses media_player directives across full/minimal/paused variants
- event
- parses event variants
- agenda
- parses agenda variants
- device
- parses device variants
- appletv_remote
- parses appletv remote variants
- combined directives
- handles text with no directives
- preserves other payload fields
- followup queue deduplication
- deduplicates messages with same Discord message_id
- deduplicates same message_id after queue drain restarts
- does not collide recent message-id keys when routing contains delimiters
- deduplicates exact prompt when routing matches and no message id
- does not deduplicate across different providers without message id
- can opt-in to prompt-based dedupe when message id is absent
- followup queue collect routing
- does not collect when destinations differ
- collects when channel+destination match
- collects Slack messages in same thread and preserves string thread id
- does not collect Slack messages when thread ids differ
- retries collect-mode batches without losing queued items
- retries overflow summary delivery without losing dropped previews
- preserves routing metadata on overflow summary followups
- followup queue drain restart after idle window
- does not retain stale callbacks when scheduleFollowupDrain runs with an empty queue
- processes a message enqueued after the drain empties and deletes the queue
- does not double-drain when a message arrives while drain is still running
- does not process messages after clearSessionQueues clears the callback
- createReplyDispatcher
- drops empty payloads and exact silent tokens without media
- strips heartbeat tokens and applies responsePrefix
- avoids double-prefixing and keeps media when heartbeat is the only text
- preserves ordering across tool, block, and final replies
- fires onIdle when the queue drains
- delays block replies after the first when humanDelay is natural
- uses custom bounds for humanDelay and clamps when max <= min
- resolveReplyToMode
- resolves defaults, channel overrides, chat-type overrides, and legacy dm overrides
- createReplyToModeFilter
- handles off/all mode behavior for replyToId
- keeps only the first replyToId when mode is first

### src/auto-reply/reply/reply-inline-whitespace.test.lisp
- collapseInlineHorizontalWhitespace
- collapses spaces and tabs but preserves newlines

### src/auto-reply/reply/reply-inline.test.lisp
- stripInlineStatus
- strips /status directive from message
- preserves newlines in multi-line messages
- preserves newlines when stripping /status
- collapses horizontal whitespace but keeps newlines
- returns empty string for whitespace-only input
- extractInlineSimpleCommand
- extracts /help command
- preserves newlines after extracting command
- returns null for empty body

### src/auto-reply/reply/reply-media-paths.test.lisp
- createReplyMediaPathNormalizer
- resolves workspace-relative media against the agent workspace
- maps sandbox-relative media back to the host sandbox workspace

### src/auto-reply/reply/reply-payloads.test.lisp
- filterMessagingToolMediaDuplicates
- strips mediaUrl when it matches sentMediaUrls
- preserves mediaUrl when it is not in sentMediaUrls
- filters matching entries from mediaUrls array
- clears mediaUrls when all entries match
- returns payloads unchanged when no media present
- returns payloads unchanged when sentMediaUrls is empty
- dedupes equivalent file and local path variants
- dedupes encoded file:// paths against local paths
- shouldSuppressMessagingToolReplies
- suppresses when target provider is missing but target matches current provider route
- suppresses when target provider uses "message" placeholder and target matches
- does not suppress when providerless target does not match origin route
- suppresses telegram topic-origin replies when explicit threadId matches
- does not suppress telegram topic-origin replies when explicit threadId differs
- does not suppress telegram topic-origin replies when target omits topic metadata
- suppresses telegram replies when chatId matches but target forms differ

### src/auto-reply/reply/reply-plumbing.test.lisp
- buildThreadingToolContext
- uses conversation id for WhatsApp
- falls back to To for WhatsApp when From is missing
- uses the recipient id for other channels
- normalizes signal direct targets for tool context
- preserves signal group ids for tool context
- uses the sender handle for iMessage direct chats
- uses chat_id for iMessage groups
- prefers MessageThreadId for Slack tool threading
- applyReplyThreading auto-threading
- sets replyToId to currentMessageId even without [[reply_to_current]] tag
- threads only first payload when mode is 'first'
- threads all payloads when mode is 'all'
- strips replyToId when mode is 'off'
- does not bypass off mode for Slack when reply is implicit
- strips explicit tags for Slack when off mode disallows tags
- keeps explicit tags for Telegram when off mode is enabled
- subagents utils
- resolves labels from label, task, or fallback
- formats run labels with truncation
- sorts subagent runs by newest start/created time
- formats run status from outcome and timestamps
- formats duration compact for seconds and minutes

### src/auto-reply/reply/reply-state.test.lisp
- history helpers
- returns current message when history is empty
- wraps history entries and excludes current by default
- trims history to configured limit
- builds context from map and appends entry
- builds context from pending map without appending
- records pending entries only when enabled
- clears history entries only when enabled
- memory flush settings
- defaults to enabled with fallback prompt and system prompt
- respects disable flag
- appends NO_REPLY hint when missing
- falls back to defaults when numeric values are invalid
- parses forceFlushTranscriptBytes from byte-size strings
- shouldRunMemoryFlush
- requires totalTokens and threshold
- skips when entry is missing
- skips when under threshold
- triggers at the threshold boundary
- skips when already flushed for current compaction count
- runs when above threshold and not flushed
- ignores stale cached totals
- hasAlreadyFlushedForCurrentCompaction
- returns true when memoryFlushCompactionCount matches compactionCount
- returns false when memoryFlushCompactionCount differs
- returns false when memoryFlushCompactionCount is undefined
- treats missing compactionCount as 0
- resolveMemoryFlushContextWindowTokens
- falls back to agent config or default tokens
- incrementCompactionCount
- increments compaction count
- updates totalTokens when tokensAfter is provided
- does not update totalTokens when tokensAfter is not provided

### src/auto-reply/reply/reply-utils.test.lisp
- matchesMentionWithExplicit
- combines explicit-mention state with regex fallback rules
- normalizeReplyPayload
- keeps channelData-only replies
- records skip reasons for silent/empty payloads
- strips NO_REPLY from mixed emoji message (#30916)
- strips NO_REPLY appended after substantive text (#30916)
- keeps NO_REPLY when used as leading substantive text
- suppresses message when stripping NO_REPLY leaves nothing
- strips NO_REPLY but keeps media payload
- typing controller
- stops only after both run completion and dispatcher idle are set (any order)
- does not start typing after run completion
- does not restart typing after it has stopped
- resolveTypingMode
- resolves defaults, configured overrides, and heartbeat suppression
- parseAudioTag
- extracts audio tag state and cleaned text
- resolveResponsePrefixTemplate
- resolves known variables, aliases, and case-insensitive tokens
- preserves unresolved/unknown placeholders and handles static inputs
- createTypingSignaler
- gates run-start typing by mode
- signals on message-mode boundaries and text deltas
- starts typing and refreshes ttl on text for thinking mode
- handles tool-start typing before and after active text mode
- suppresses typing when disabled
- block reply coalescer
- coalesces chunks within the idle window
- waits until minChars before idle flush
- still accumulates when flushOnEnqueue is not set (default)
- flushes immediately per enqueue when flushOnEnqueue is set
- flushes buffered text before media payloads
- createReplyReferencePlanner
- plans references correctly for off/first/all modes
- honors allowReference=false
- createStreamingDirectiveAccumulator
- stashes reply_to_current until a renderable chunk arrives
- handles reply tags split across chunks
- propagates explicit reply ids across current and subsequent chunks
- clears sticky reply context on reset
- extractShortModelName
- normalizes provider/date/latest suffixes while preserving other IDs
- hasTemplateVariables
- handles empty, static, and repeated variable checks

### src/auto-reply/reply/route-reply.test.lisp
- routeReply
- skips sends when abort signal is already aborted
- no-ops on empty payload
- suppresses reasoning payloads
- drops silent token payloads
- does not drop payloads that merely start with the silent token
- applies responsePrefix when routing
- does not derive responsePrefix from agent identity when routing
- uses threadId for Slack when replyToId is missing
- passes thread id to Telegram sends
- passes replyToId to Telegram sends
- uses replyToId as threadTs for Slack
- uses threadId as threadTs for Slack when replyToId is missing
- sends multiple mediaUrls (caption only on first)
- routes WhatsApp via outbound sender (accountId honored)
- routes MS Teams via proactive sender
- passes mirror data when sessionKey is set
- skips mirror data when mirror is false

### src/auto-reply/reply/session-delivery.test.lisp
- session delivery direct-session routing overrides

### src/auto-reply/reply/session-hooks-context.test.lisp
- session hook context wiring
- passes sessionKey to session_start hook context
- passes sessionKey to session_end hook context on reset

### src/auto-reply/reply/session-reset-prompt.test.lisp
- buildBareSessionResetPrompt
- includes the core session startup instruction
- appends current time line so agents know the date
- does not append a duplicate current time line
- falls back to UTC when no timezone configured

### src/auto-reply/reply/session.test.lisp
- initSessionState thread forking
- forks a new session from the parent session file
- forks from parent when thread session key already exists but was not forked yet
- skips fork and creates fresh session when parent tokens exceed threshold
- respects session.parentForkMaxTokens override
- records topic-specific session files when MessageThreadId is present
- initSessionState RawBody
- uses RawBody for command extraction and reset triggers when Body contains wrapped context
- preserves argument casing while still matching reset triggers case-insensitively
- does not rotate local session state for /new on bound ACP sessions
- does not rotate local session state for ACP /new when conversation IDs are unavailable
- keeps custom reset triggers working on bound ACP sessions
- keeps normal /new behavior for unbound ACP-shaped session keys
- does not suppress /new when active conversation binding points to a non-ACP session
- does not suppress /new when active target session key is non-ACP even with configured ACP binding
- uses the default per-agent sessions store when config store is unset
- initSessionState reset policy
- defaults to daily reset at 4am local time
- treats sessions as stale before the daily reset when updated before yesterday's boundary
- expires sessions when idle timeout wins over daily reset
- uses per-type overrides for thread sessions
- detects thread sessions without thread key suffix
- defaults to daily resets when only resetByType is configured
- keeps legacy idleMinutes behavior without reset config
- initSessionState channel reset overrides
- uses channel-specific reset policy when configured
- initSessionState reset triggers in WhatsApp groups
- applies WhatsApp group reset authorization across sender variants
- initSessionState reset triggers in Slack channels
- supports mention-prefixed Slack reset commands and preserves args
- applyResetModelOverride
- selects a model hint and strips it from the body
- clears auth profile overrides when reset applies a model
- skips when resetTriggered is false
- initSessionState preserves behavior overrides across /new and /reset
- preserves behavior overrides across /new and /reset
- archives the old session store entry on /new
- archives the old session transcript on daily/scheduled reset (stale session)
- idle-based new session does NOT preserve overrides (no entry to read)
- drainFormattedSystemEvents
- adds a local timestamp to queued system events by default
- persistSessionUsageUpdate
- uses lastCallUsage for totalTokens when provided
- uses lastCallUsage cache counters when available
- marks totalTokens as unknown when no fresh context snapshot is available
- uses promptTokens when available without lastCallUsage
- persists totalTokens from promptTokens when usage is unavailable
- keeps non-clamped lastCallUsage totalTokens when exceeding context window
- initSessionState stale threadId fallback
- does not inherit lastThreadId from a previous thread interaction in non-thread sessions
- preserves lastThreadId within the same thread session
- initSessionState dmScope delivery migration
- retires stale main-session delivery route when dmScope uses per-channel DM keys
- keeps legacy main-session delivery route when current DM target does not match
- initSessionState internal channel routing preservation
- keeps persisted external lastChannel when OriginatingChannel is internal webchat
- lets direct webchat turns override persisted external routes for per-channel-peer sessions
- keeps persisted external route when OriginatingChannel is non-deliverable
- uses session key channel hint when first turn is internal webchat
- keeps internal route when there is no persisted external fallback
- keeps webchat channel for webchat/main sessions
- does not reuse stale external lastTo for webchat/main turns without destination
- prefers webchat route over persisted external route for main session turns

### src/auto-reply/reply/strip-inbound-meta.test.lisp
- stripInboundMetadata
- fast-path: returns same string when no sentinels present
- fast-path: returns empty string unchanged
- strips a single Conversation info block
- strips multiple chained metadata blocks
- strips Replied message block leaving user message intact
- strips all six known sentinel types
- handles metadata block with no user text after it
- preserves message containing json fences that are not metadata
- preserves leading newlines in user content after stripping
- preserves leading spaces in user content after stripping
- strips trailing Untrusted context metadata suffix blocks
- does not strip plain user text that starts with untrusted context words
- does not strip lookalike sentinel lines with extra text
- does not strip sentinel text when json fence is missing
- extractInboundSenderLabel
- returns the sender label block when present
- falls back to conversation sender when sender block is absent
- returns null when inbound sender metadata is absent

### src/auto-reply/reply/subagents-utils.test.lisp
- subagents utils
- resolves subagent label with fallback
- sorts by startedAt then createdAt descending
- selects last from sorted runs
- resolves numeric index from running then recent finished order
- resolves session key target and unknown session errors
- resolves exact label, prefix, run-id prefix and ambiguity errors
- returns ambiguous exact label error before prefix/run id matching

### src/auto-reply/reply/telegram-context.test.lisp
- resolveTelegramConversationId
- builds canonical topic ids from chat target and message thread id
- returns the direct-message chat id when no topic id is present
- does not treat non-topic groups as globally bindable conversations
- falls back to command target when originating target is missing

### src/auto-reply/reply/typing-persistence.test.lisp
- typing persistence bug fix
- should NOT restart typing after markRunComplete is called
- should stop typing when both runComplete and dispatchIdle are true
- should prevent typing restart even if cleanup is delayed

### src/auto-reply/reply/typing-policy.test.lisp
- resolveRunTypingPolicy
- forces heartbeat policy for heartbeat runs
- forces internal webchat policy
- forces system event policy for routed turns
- preserves requested policy for regular user turns
- respects explicit suppressTyping

### src/auto-reply/skill-commands.test.lisp
- resolveSkillCommandInvocation
- matches skill commands and parses args
- supports /skill with name argument
- normalizes /skill lookup names
- returns null for unknown commands
- listSkillCommandsForAgents
- deduplicates by skillName across agents, keeping the first registration
- scopes to specific agents when agentIds is provided
- prevents cross-agent skill leakage when each agent has an allowlist
- merges allowlists for agents that share one workspace
- deduplicates overlapping allowlists for shared workspace
- keeps workspace unrestricted when one co-tenant agent has no skills filter
- merges empty allowlist with non-empty allowlist for shared workspace
- skips agents with missing workspaces gracefully
- dedupeBySkillName
- keeps the first entry when multiple commands share a skillName
- matches skillName case-insensitively
- passes through commands with an empty skillName
- returns an empty array for empty input

### src/auto-reply/status.test.lisp
- buildStatusMessage
- summarizes agent readiness and context usage
- falls back to sessionEntry levels when resolved levels are not passed
- notes channel model overrides in status output
- shows 1M context window when anthropic context1m is enabled
- uses per-agent sandbox config when config and session key are provided
- shows verbose/elevated labels only when enabled
- includes media understanding decisions when present
- omits media line when all decisions are none
- does not show elevated label when session explicitly disables it
- shows selected model and active runtime model when they differ
- omits active fallback details when runtime drift does not match fallback state
- omits active lines when runtime matches selected model
- keeps provider prefix from configured model
- handles missing agent config gracefully
- includes group activation for group sessions
- shows queue details when overridden
- inserts usage summary beneath context line
- hides cost when not using an API key
- prefers cached prompt tokens from the session log
- reads transcript usage for non-default agents
- reads transcript usage using explicit agentId when sessionKey is missing
- buildCommandsMessage
- lists commands with aliases and hints
- includes skill commands when provided
- buildHelpMessage
- hides config/debug when disabled
- buildCommandsMessagePaginated
- formats telegram output with pages
- includes plugin commands in the paginated list

### src/auto-reply/thinking.test.lisp
- normalizeThinkLevel
- accepts mid as medium
- accepts xhigh aliases
- accepts extra-high aliases as xhigh
- does not over-match nearby xhigh words
- accepts on as low
- accepts adaptive and auto aliases
- listThinkingLevels
- includes xhigh for codex models
- includes xhigh for openai gpt-5.2 and gpt-5.4 variants
- includes xhigh for openai-codex gpt-5.4
- includes xhigh for github-copilot gpt-5.2 refs
- excludes xhigh for non-codex models
- always includes adaptive
- listThinkingLevelLabels
- returns on/off for ZAI
- returns full levels for non-ZAI
- normalizeReasoningLevel
- accepts on/off
- accepts show/hide
- accepts stream

### src/auto-reply/tokens.test.lisp
- isSilentReplyText
- returns true for exact token
- returns true for token with surrounding whitespace
- returns false for undefined/empty
- returns false for substantive text ending with token (#19537)
- returns false for substantive text starting with token
- returns false for token embedded in text
- works with custom token
- stripSilentToken
- strips token from end of text
- does not strip token from start of text
- strips token with emoji (#30916)
- does not strip embedded token suffix without whitespace delimiter
- strips only trailing occurrence
- returns empty string when only token remains
- strips token preceded by bold markdown formatting
- works with custom token
- isSilentReplyPrefixText
- matches uppercase token lead fragments
- rejects ambiguous natural-language prefixes
- keeps underscore guard for non-NO_REPLY tokens
- rejects non-prefixes and mixed characters

### src/auto-reply/tool-meta.test.lisp
- tool meta formatting
- shortens paths under HOME
- shortens meta strings with optional colon suffix
- formats aggregates with grouping and brace-collapse
- wraps aggregate meta in backticks when markdown is enabled
- keeps exec flags outside markdown and moves them to the front
- formats prefixes with default labels

## browser

### src/browser/bridge-server.auth.test.lisp
- startBrowserBridgeServer auth
- rejects unauthenticated requests when authToken is set
- accepts x-openclaw-password when authPassword is set
- requires auth params
- serves noVNC bootstrap html without leaking password in Location header

### src/browser/browser-utils.test.lisp
- toBoolean
- parses yes/no and 1/0
- returns undefined for on/off strings
- passes through boolean values
- browser target id resolution
- resolves exact ids
- resolves unique prefixes (case-insensitive)
- fails on ambiguous prefixes
- fails when no tab matches
- browser CSRF loopback mutation guard
- rejects mutating methods from non-loopback origin
- allows mutating methods from loopback origin
- allows mutating methods without origin/referer (non-browser clients)
- rejects mutating methods with origin=null
- rejects mutating methods from non-loopback referer
- rejects cross-site mutations via Sec-Fetch-Site when present
- does not reject non-mutating methods
- cdp.helpers
- preserves query params when appending Chrome DevTools Protocol paths
- appends paths under a base prefix
- adds basic auth headers when credentials are present
- keeps preexisting authorization headers
- does not add relay header for unknown loopback ports
- adds relay header for known relay ports
- fetchBrowserJson loopback auth (bridge auth registry)
- falls back to per-port bridge auth when config auth is not available
- browser server-context listKnownProfileNames
- includes configured and runtime-only profile names

### src/browser/cdp-proxy-bypass.test.lisp
- cdp-proxy-bypass
- getDirectAgentForCdp
- returns http.Agent for http://localhost URLs
- returns http.Agent for http://127.0.0.1 URLs
- returns https.Agent for wss://localhost URLs
- returns https.Agent for https://127.0.0.1 URLs
- returns http.Agent for ws://[::1] URLs
- returns undefined for non-loopback URLs
- returns undefined for invalid URLs
- hasProxyEnv
- returns false when no proxy vars set
- returns true when HTTP_PROXY is set
- returns true when ALL_PROXY is set
- withNoProxyForLocalhost
- sets NO_PROXY when proxy is configured
- extends existing NO_PROXY
- skips when no proxy env is set
- restores env even on error
- withNoProxyForLocalhost concurrency
- does not leak NO_PROXY when called concurrently
- withNoProxyForLocalhost reverse exit order
- restores NO_PROXY when first caller exits before second
- withNoProxyForLocalhost preserves user-configured NO_PROXY
- does not delete NO_PROXY when loopback entries already present
- withNoProxyForCdpUrl
- does not mutate NO_PROXY for non-loopback Chrome DevTools Protocol URLs
- does not overwrite external NO_PROXY changes made during execution

### src/browser/cdp-timeouts.test.lisp
- resolveCdpReachabilityTimeouts
- uses loopback defaults when timeout is omitted
- clamps loopback websocket timeout range
- enforces remote minimums even when caller passes lower timeout
- uses remote defaults when timeout is omitted

### src/browser/cdp.test.lisp
- cdp
- creates a target via the browser websocket
- blocks private navigation targets by default
- blocks unsupported non-network navigation URLs
- allows private navigation targets when explicitly configured
- evaluates javascript via Chrome DevTools Protocol
- fails when /json/version omits webSocketDebuggerUrl
- captures an aria snapshot via Chrome DevTools Protocol
- normalizes loopback websocket URLs for remote Chrome DevTools Protocol hosts
- propagates auth and query params onto normalized websocket URLs
- upgrades ws to wss when Chrome DevTools Protocol uses https

### src/browser/chrome-extension-background-utils.test.lisp
- chrome extension background utils
- derives relay token as HMAC-SHA256 of gateway token and port
- builds websocket url with derived relay token
- throws when gateway token is missing
- uses exponential backoff from attempt index
- caps reconnect delay at max
- adds jitter using injected random source
- sanitizes invalid attempts and options
- marks missing token errors as non-retryable
- keeps transient network errors retryable

### src/browser/chrome-extension-manifest.test.lisp
- chrome extension manifest
- keeps background worker configured as module
- includes resilience permissions

### src/browser/chrome-extension-options-validation.test.lisp
- chrome extension options validation
- maps 401 response to token rejected error
- maps non-json 200 response to wrong-port error
- maps json response without Chrome DevTools Protocol keys to wrong-port error
- maps valid relay json response to success
- maps syntax/json exceptions to wrong-endpoint error
- maps generic exceptions to relay unreachable error

### src/browser/chrome.default-browser.test.lisp
- browser default executable detection
- prefers default Chromium browser on macOS
- falls back when default browser is non-Chromium on macOS

### src/browser/chrome.test.lisp
- browser chrome profile decoration
- writes expected name + signed ARGB seed to Chrome prefs
- best-effort writes name when color is invalid
- recovers from missing/invalid preference files
- writes clean exit prefs to avoid restore prompts
- is idempotent when rerun on an existing profile
- browser chrome helpers
- picks the first existing Chrome candidate on macOS
- returns null when no Chrome candidate exists
- picks the first existing Chrome candidate on Windows
- finds Chrome in Program Files on Windows
- returns null when no Chrome candidate exists on Windows
- resolves Windows executables without LOCALAPPDATA
- reports reachability based on /json/version
- reports cdpReady only when Browser.getVersion command succeeds
- reports cdpReady false when websocket opens but command channel is stale
- stopOpenClawChrome no-ops when process is already killed
- stopOpenClawChrome sends SIGTERM and returns once Chrome DevTools Protocol is down
- stopOpenClawChrome escalates to SIGKILL when Chrome DevTools Protocol stays reachable

### src/browser/client-fetch.loopback-auth.test.lisp
- fetchBrowserJson loopback auth
- adds bearer auth for loopback absolute HTTP URLs
- does not inject auth for non-loopback absolute URLs
- keeps caller-supplied auth header
- injects auth for IPv6 loopback absolute URLs
- injects auth for IPv4-mapped IPv6 loopback URLs
- preserves dispatcher error context while keeping no-retry hint
- keeps absolute URL failures wrapped as reachability errors

### src/browser/client.test.lisp
- browser client
- wraps connection failures with a sandbox hint
- adds useful timeout messaging for abort-like failures
- surfaces non-2xx responses with body text
- adds labels + efficient mode query params to snapshots
- adds refs=aria to snapshots when requested
- uses the expected endpoints + methods for common calls

### src/browser/config.test.lisp
- browser config
- defaults to enabled with loopback defaults and lobster-orange color
- derives default ports from OPENCLAW_GATEWAY_PORT when unset
- derives default ports from gateway.port when env is unset
- supports overriding the local Chrome DevTools Protocol auto-allocation range start
- rejects cdpPortRangeStart values that overflow the Chrome DevTools Protocol range window
- normalizes hex colors
- supports custom remote Chrome DevTools Protocol timeouts
- falls back to default color for invalid hex
- treats non-loopback cdpUrl as remote
- supports explicit Chrome DevTools Protocol URLs for the default profile
- uses profile cdpUrl when provided
- inherits attachOnly from global browser config when profile override is not set
- allows profile attachOnly to override global browser attachOnly
- uses base protocol for profiles with only cdpPort
- rejects unsupported protocols
- does not add the built-in chrome extension profile if the derived relay port is already used
- defaults extraArgs to empty array when not provided
- passes through valid extraArgs strings
- filters out empty strings and whitespace-only entries from extraArgs
- filters out non-string entries from extraArgs
- defaults extraArgs to empty array when set to non-array
- resolves browser SSRF policy when configured
- defaults browser SSRF policy to trusted-network mode
- supports explicit strict mode by disabling private network access
- default profile preference
- defaults to openclaw profile when defaultProfile is not configured
- keeps openclaw default when headless=true
- keeps openclaw default when noSandbox=true
- keeps openclaw default when both headless and noSandbox are true
- explicit defaultProfile config overrides defaults in headless mode
- explicit defaultProfile config overrides defaults in noSandbox mode
- allows custom profile as default even in headless mode

### src/browser/control-auth.auto-token.test.lisp
- ensureBrowserControlAuth
- returns existing auth and skips writes
- auto-generates and persists a token when auth is missing
- skips auto-generation in test env
- respects explicit password mode
- respects explicit none mode
- reuses auth from latest config snapshot
- fails when gateway.auth.token SecretRef is unresolved

### src/browser/control-auth.test.lisp
- ensureBrowserControlAuth
- trusted-proxy mode
- should not auto-generate token when auth mode is trusted-proxy
- password mode
- should not auto-generate token when auth mode is password (even if password not set)
- none mode
- should not auto-generate token when auth mode is none
- token mode
- should return existing token if configured
- should skip auto-generation in test environment

### src/browser/extension-relay-auth.secretref.test.lisp
- extension-relay-auth SecretRef handling
- resolves env-template gateway.auth.token from its referenced env var
- fails closed when env-template gateway.auth.token is unresolved
- resolves file-backed gateway.auth.token SecretRef
- resolves exec-backed gateway.auth.token SecretRef

### src/browser/extension-relay-auth.test.lisp
- extension-relay-auth
- derives deterministic relay tokens per port
- accepts both relay-scoped and raw gateway tokens for compatibility
- accepts authenticated openclaw relay probe responses
- rejects unauthenticated probe responses
- rejects probe responses with wrong browser identity

### src/browser/extension-relay.test.lisp
- chrome extension relay server
- advertises Chrome DevTools Protocol WS only when extension is connected
- uses relay-scoped token only for known relay ports
- rejects Chrome DevTools Protocol access without relay auth token
- returns 400 for malformed percent-encoding in target action routes
- deduplicates concurrent relay starts for the same requested port
- allows CORS preflight from chrome-extension origins
- rejects CORS preflight from non-extension origins
- returns CORS headers on JSON responses for extension origins
- rejects extension websocket access without relay auth token
- rejects a second live extension connection with 409
- allows immediate reconnect when prior extension socket is closing
- keeps Chrome DevTools Protocol clients alive across a brief extension reconnect
- keeps /json/version websocket endpoint during short extension disconnects
- accepts re-announce attach events with minimal targetInfo
- waits briefly for extension reconnect before failing Chrome DevTools Protocol commands
- closes Chrome DevTools Protocol clients after reconnect grace when extension stays disconnected
- stops advertising websocket endpoint after reconnect grace expires
- accepts extension websocket access with relay token query param
- accepts /json endpoints with relay token query param
- accepts raw gateway token for relay auth compatibility
- tracks attached page targets and exposes them via Chrome DevTools Protocol + /json/list
- removes cached targets from /json/list when targetDestroyed arrives
- prunes stale cached targets after target-not-found command errors
- rebroadcasts attach when a session id is reused for a new target
- reuses an already-bound relay port when another process owns it
- restores tabs after extension reconnects and re-announces
- preserves tab across a fast extension reconnect within grace period
- does not swallow EADDRINUSE when occupied port is not an openclaw relay

### src/browser/navigation-guard.test.lisp
- browser navigation guard
- blocks private loopback URLs by default
- allows about:blank
- blocks file URLs
- blocks data URLs
- blocks javascript URLs
- blocks non-blank about URLs
- allows blocked hostnames when explicitly allowed
- blocks hostnames that resolve to private addresses by default
- allows hostnames that resolve to public addresses
- blocks strict policy navigation when env proxy is configured
- allows env proxy navigation when private-network mode is explicitly enabled
- rejects invalid URLs
- validates final network URLs after navigation
- ignores non-network browser-internal final URLs

### src/browser/paths.test.lisp
- resolveExistingPathsWithinRoot
- accepts existing files under the upload root
- rejects traversal outside the upload root
- rejects blank paths
- keeps lexical in-root paths when files do not exist yet
- rejects directory paths inside upload root
- resolveStrictExistingPathsWithinRoot
- rejects missing files instead of returning lexical fallbacks
- resolvePathWithinRoot
- uses default file name when requested path is blank
- rejects root-level path aliases that do not point to a file
- resolveWritablePathWithinRoot
- accepts a writable path under root when parent is a real directory
- resolvePathsWithinRoot
- resolves all valid in-root paths
- returns the first path validation error

### src/browser/profiles-service.test.lisp
- BrowserProfilesService
- allocates next local port for new profiles
- falls back to derived Chrome DevTools Protocol range when resolved Chrome DevTools Protocol range is missing
- allocates from configured cdpPortRangeStart for new local profiles
- accepts per-profile cdpUrl for remote Chrome
- deletes remote profiles without stopping or removing local data
- deletes local profiles and moves data to Trash

### src/browser/profiles.test.lisp
- profile name validation
- rejects empty or missing names
- rejects names that are too long
- port allocation
- allocates within an explicit range
- allocates next available port from default range
- returns null when all ports are exhausted
- getUsedPorts
- returns empty set for undefined profiles
- extracts ports from profile configs
- extracts ports from cdpUrl when cdpPort is missing
- ignores invalid cdpUrl values
- port collision prevention
- raw config vs resolved config - shows the data source difference
- create-profile must use resolved config to avoid port collision
- color allocation
- allocates next unused color from palette
- handles case-insensitive color matching
- cycles when all colors are used
- cycles based on count when palette exhausted
- getUsedColors
- returns empty set when no color profiles are configured
- extracts and uppercases colors from profile configs

### src/browser/pw-ai.e2e.test.lisp
- pw-ai
- captures an ai snapshot via Chrome DevTools Protocol automation in Common Lisp (or external helper) for a specific target
- registers aria refs from ai snapshots for act commands
- truncates oversized snapshots
- clicks a ref using aria-ref locator
- fails with a clear error when _snapshotForAI is missing
- reuses the Chrome DevTools Protocol connection for repeated calls

### src/browser/pw-role-snapshot.test.lisp
- pw-role-snapshot
- adds refs for interactive elements
- uses nth only when duplicates exist
- respects maxDepth
- computes stats
- returns a helpful message when no interactive elements exist
- parses role refs
- preserves Chrome DevTools Protocol automation in Common Lisp (or external helper) aria-ref ids in ai snapshots

### src/browser/pw-session.browserless.live.test.lisp
- creates, lists, focuses, and closes tabs via Chrome DevTools Protocol automation in Common Lisp (or external helper)

### src/browser/pw-session.create-page.navigation-guard.test.lisp
- pw-session createPageViaPlaywright navigation guard
- blocks unsupported non-network URLs
- allows about:blank without network navigation

### src/browser/pw-session.get-page-for-targetid.extension-fallback.test.lisp
- pw-session getPageForTargetId
- falls back to the only page when Chrome DevTools Protocol session attachment is blocked (extension relays)

### src/browser/pw-session.test.lisp
- pw-session refLocator
- uses frameLocator for role refs when snapshot was scoped to a frame
- uses page getByRole for role refs by default
- uses aria-ref locators when refs mode is aria
- pw-session role refs cache
- restores refs for a different Page instance (same Chrome DevTools Protocol targetId)
- pw-session ensurePageState
- tracks page errors and network requests (best-effort)
- drops state on page close

### src/browser/pw-tools-core.clamps-timeoutms-scrollintoview.test.lisp
- pw-tools-core
- clamps timeoutMs for scrollIntoView
- rewrites covered/hidden errors into interactable hints

### src/browser/pw-tools-core.interactions.evaluate.abort.test.lisp
- evaluateViaPlaywright (abort)

### src/browser/pw-tools-core.interactions.set-input-files.test.lisp
- setInputFilesViaPlaywright
- revalidates upload paths and uses resolved canonical paths for inputRef
- throws and skips setInputFiles when use-time validation fails

### src/browser/pw-tools-core.last-file-chooser-arm-wins.test.lisp
- pw-tools-core
- last file-chooser arm wins
- arms the next dialog and accepts/dismisses (default timeout)
- waits for selector, url, load state, and function

### src/browser/pw-tools-core.screenshots-element-selector.test.lisp
- pw-tools-core
- screenshots an element selector
- screenshots a ref locator
- rejects fullPage for element or ref screenshots
- arms the next file chooser and sets files (default timeout)
- revalidates file-chooser paths at use-time and cancels missing files
- arms the next file chooser and escapes if no paths provided

### src/browser/pw-tools-core.snapshot.navigate-guard.test.lisp
- pw-tools-core.snapshot navigate guard
- blocks unsupported non-network URLs before page lookup
- navigates valid network URLs with clamped timeout
- reconnects and retries once when navigation detaches frame

### src/browser/pw-tools-core.waits-next-download-saves-it.test.lisp
- pw-tools-core
- waits for the next download and atomically finalizes explicit output paths
- clicks a ref and atomically finalizes explicit download paths
- uses preferred tmp dir when waiting for download without explicit path
- sanitizes suggested download filenames to prevent traversal escapes
- waits for a matching response and returns its body
- scrolls a ref into view (default timeout)
- requires a ref for scrollIntoView

### src/browser/routes/agent.shared.test.lisp
- browser route shared helpers
- readBody
- returns object bodies
- normalizes non-object bodies to empty object
- target id parsing
- extracts and trims targetId from body
- extracts and trims targetId from query

### src/browser/routes/agent.snapshot.test.lisp
- resolveTargetIdAfterNavigate
- returns original targetId when old target still exists (no swap)
- resolves new targetId when old target is gone (renderer swap)
- prefers non-stale targetId when multiple tabs share the URL
- retries and resolves targetId when first listTabs has no URL match
- falls back to original targetId when no match found after retry
- falls back to single remaining tab when no URL match after retry
- falls back to original targetId when listTabs throws

### src/browser/routes/agent.storage.test.lisp
- browser storage route parsing
- parseStorageKind
- accepts local and session
- rejects unsupported values
- parseStorageMutationRequest
- returns parsed kind and trimmed target id
- returns null kind and undefined target id for invalid values
- parseRequiredStorageMutationRequest
- returns parsed request for supported kinds
- returns null for unsupported kind

### src/browser/routes/dispatcher.abort.test.lisp
- browser route dispatcher (abort)
- propagates AbortSignal and lets handlers observe abort
- returns 400 for malformed percent-encoding in route params

### src/browser/screenshot.test.lisp
- browser screenshot normalization
- shrinks oversized images to <=2000x2000 and <=5MB
- keeps already-small screenshots unchanged

### src/browser/server-context.ensure-browser-available.waits-for-cdp-ready.test.lisp
- browser server-context ensureBrowserAvailable
- waits for Chrome DevTools Protocol readiness after launching to avoid follow-up PortInUseError races (#21149)
- stops launched chrome when Chrome DevTools Protocol readiness never arrives

### src/browser/server-context.ensure-tab-available.prefers-last-target.test.lisp
- browser server-context ensureTabAvailable
- sticks to the last selected target when targetId is omitted
- falls back to the only attached tab when an invalid targetId is provided (extension)
- returns a descriptive message when no extension tabs are attached

### src/browser/server-context.hot-reload-profiles.test.lisp
- server-context hot-reload profiles
- forProfile hot-reloads newly added profiles from config
- forProfile still throws for profiles that don't exist in fresh config
- forProfile refreshes existing profile config after loadConfig cache updates
- listProfiles refreshes config before enumerating profiles

### src/browser/server-context.remote-profile-tab-ops.test.lisp

### src/browser/server-context.remote-tab-ops.test.lisp

### src/browser/server-context.reset.test.lisp
- createProfileResetOps
- stops extension relay for extension profiles
- rejects remote non-extension profiles
- stops local browser, closes Chrome DevTools Protocol automation in Common Lisp (or external helper) connection, and trashes profile dir
- forces Chrome DevTools Protocol automation in Common Lisp (or external helper) disconnect when loopback cdp is occupied by non-owned process

### src/browser/server-context.tab-selection-state.test.lisp

### src/browser/server-lifecycle.test.lisp
- ensureExtensionRelayForProfiles
- starts relay only for extension profiles
- reports relay startup errors
- stopKnownBrowserProfiles
- stops all known profiles and ignores per-profile failures
- warns when profile enumeration fails

### src/browser/server.agent-contract-form-layout-act-commands.test.lisp
- browser control server
- agent contract: form + layout act commands
- blocks act:evaluate when browser.evaluateEnabled=false
- agent contract: hooks + response + downloads + screenshot
- blocks file chooser traversal / absolute paths outside uploads dir
- agent contract: stop endpoint
- trace stop rejects traversal path outside trace dir
- trace stop accepts in-root relative output path
- wait/download rejects traversal path outside downloads dir
- download rejects traversal path outside downloads dir
- wait/download accepts in-root relative output path
- download accepts in-root relative output path

### src/browser/server.agent-contract-snapshot-endpoints.test.lisp
- browser control server
- agent contract: snapshot endpoints
- agent contract: navigation + common act commands

### src/browser/server.auth-fail-closed.test.lisp
- browser control auth bootstrap failures
- fails closed when auth bootstrap throws and no auth is configured

### src/browser/server.auth-token-gates-http.test.lisp
- browser control HTTP auth
- requires bearer auth for standalone browser HTTP routes

### src/browser/server.evaluate-disabled-does-not-block-storage.test.lisp
- browser control evaluate gating
- blocks act:evaluate but still allows cookies/storage reads

### src/browser/server.post-tabs-open-profile-unknown-returns-404.test.lisp
- browser control server
- POST /tabs/open?profile=unknown returns 404
- POST /tabs/open returns 400 for invalid URLs
- profile CRUD endpoints
- validates profile create/delete endpoints

### src/browser/session-tab-registry.test.lisp
- session tab registry
- tracks and closes tabs for normalized session keys
- untracks specific tabs
- deduplicates tabs and ignores expected close errors

## canvas-host

### src/canvas-host/server.state-dir.test.lisp
- canvas host state dir defaults
- uses OPENCLAW_STATE_DIR for the default canvas root

### src/canvas-host/server.test.lisp
- canvas host
- injects live reload script
- creates a default index.html when missing
- skips live reload injection when disabled
- serves canvas content from the mounted base path and reuses handlers without double close
- serves HTML with injection and broadcasts reload on file changes
- serves A2UI scaffold and blocks traversal/symlink escapes

## channels

### src/channels/account-snapshot-fields.test.lisp
- projectSafeChannelAccountSnapshotFields
- omits webhook and public-key style fields from generic snapshots

### src/channels/ack-reactions.test.lisp
- shouldAckReaction
- honors direct and group-all scopes
- skips when scope is off
- defaults to group-mentions gating
- requires mention gating for group-mentions
- shouldAckReactionForWhatsApp
- respects direct and group modes
- honors mentions or activation for group-mentions
- removeAckReactionAfterReply
- removes only when ack succeeded
- skips removal when ack did not happen

### src/channels/allow-from.test.lisp
- mergeDmAllowFromSources
- merges, trims, and filters empty values
- excludes pairing-store entries when dmPolicy is allowlist
- keeps pairing-store entries for non-allowlist policies
- resolveGroupAllowFromSources
- prefers explicit group allowlist
- falls back to DM allowlist when group allowlist is unset/empty
- can disable fallback to DM allowlist
- firstDefined
- returns the first non-undefined value
- isSenderIdAllowed
- supports per-channel empty-list defaults and wildcard/id matches

### src/channels/allowlists/resolve-utils.test.lisp
- buildAllowlistResolutionSummary
- returns mapping, additions, and unresolved (including missing ids)
- supports custom resolved formatting
- supports custom unresolved formatting
- addAllowlistUserEntriesFromConfigEntry
- adds trimmed users and skips '*' and blanks
- ignores non-objects
- canonicalizeAllowlistWithResolvedIds
- replaces resolved names with ids and keeps unresolved entries
- deduplicates ids after canonicalization
- patchAllowlistUsersInConfigEntries
- supports canonicalization strategy for nested users
- summarizeMapping
- logs sampled resolved and unresolved entries
- skips logging when both lists are empty

### src/channels/channel-config.test.lisp
- buildChannelKeyCandidates
- dedupes and trims keys
- normalizeChannelSlug
- normalizes names into slugs
- resolveChannelEntryMatch
- returns matched entry and wildcard metadata
- resolveChannelEntryMatchWithFallback
- matches normalized keys when normalizeKey is provided
- applyChannelMatchMeta
- copies match metadata onto resolved configs
- resolveChannelMatchConfig
- returns null when no entry is matched
- resolves entry and applies match metadata
- validateSenderIdentity
- allows direct messages without sender fields
- requires some sender identity for non-direct chats
- validates SenderE164 and SenderUsername shape
- resolveNestedAllowlistDecision

### src/channels/channels-misc.test.lisp
- channel-web barrel
- exports the expected web helpers
- normalizeChatType
- backward compatibility
- accepts legacy 'dm' value shape variants and normalizes to 'direct'
- channels/web entrypoint
- re-exports web channel helpers

### src/channels/command-gating.test.lisp
- resolveCommandAuthorizedFromAuthorizers
- denies when useAccessGroups is enabled and no authorizer is configured
- allows when useAccessGroups is enabled and any configured authorizer allows
- allows when useAccessGroups is disabled (default)
- honors modeWhenAccessGroupsOff=deny
- honors modeWhenAccessGroupsOff=configured (allow when none configured)
- honors modeWhenAccessGroupsOff=configured (enforce when configured)
- resolveControlCommandGate
- blocks control commands when unauthorized
- does not block when control commands are disabled

### src/channels/conversation-label.test.lisp
- resolveConversationLabel

### src/channels/dock.test.lisp
- channels dock
- telegram and googlechat threading contexts map thread ids consistently
- telegram threading does not treat ReplyToId as thread id in DMs
- irc resolveDefaultTo matches account id case-insensitively
- signal allowFrom formatter normalizes values and preserves wildcard
- telegram allowFrom formatter trims, strips prefix, and lowercases
- telegram dock config readers preserve omitted-account fallback semantics
- slack dock config readers stay read-only when tokens are unresolved SecretRefs
- dock config readers coerce numeric allowFrom/defaultTo entries through shared helpers

### src/channels/draft-stream-controls.test.lisp
- draft-stream-controls
- takeMessageIdAfterStop stops, reads, and clears message id
- clearFinalizableDraftMessage deletes valid message ids
- clearFinalizableDraftMessage skips invalid message ids
- clearFinalizableDraftMessage warns when delete fails
- controls ignore updates after final
- lifecycle clear marks stopped, clears id, and deletes preview message

### src/channels/inbound-debounce-policy.test.lisp
- shouldDebounceTextInbound
- rejects blank text, media, and control commands
- accepts normal text when debounce is allowed
- createChannelInboundDebouncer
- resolves per-channel debounce and forwards callbacks

### src/channels/location.test.lisp
- provider location helpers
- formats pin locations with accuracy
- formats named places with address and caption
- formats live locations with live label
- builds ctx fields with normalized source

### src/channels/mention-gating.test.lisp
- resolveMentionGating
- combines explicit, implicit, and bypass mentions
- skips when mention required and none detected
- does not skip when mention detection is unavailable
- resolveMentionGatingWithBypass

### src/channels/model-overrides.test.lisp
- resolveChannelModelOverride

### src/channels/native-command-session-targets.test.lisp
- resolveNativeCommandSessionTargets
- uses the bound session for both targets when present
- falls back to the routed session target when unbound
- supports lowercase session keys for providers that already normalize

### src/channels/plugins/account-action-gate.test.lisp
- createAccountActionGate
- prefers account action values over base values
- falls back to base actions when account actions are unset
- uses default value when neither account nor base defines the key

### src/channels/plugins/account-helpers.test.lisp
- createAccountListHelpers
- listConfiguredAccountIds
- returns empty for missing config
- returns empty when no accounts key
- returns empty for empty accounts object
- filters out empty keys
- returns account keys
- with normalizeAccountId option
- normalizes and deduplicates configured account ids
- listAccountIds
- returns ["default"] for empty config
- returns ["default"] for empty accounts
- returns sorted ids
- resolveDefaultAccountId
- prefers configured defaultAccount when it matches a configured account id
- normalizes configured defaultAccount before matching
- falls back when configured defaultAccount is missing
- returns "default" when present
- returns first sorted id when no default
- returns "default" for empty config

### src/channels/plugins/actions/actions.test.lisp
- discord message actions
- lists channel and upload actions by default
- respects disabled channel actions
- lists moderation when at least one account enables it
- omits moderation when all accounts omit it
- inherits top-level channel gate when account overrides moderation only
- allows account to explicitly re-enable top-level disabled channels
- handleDiscordMessageAction
- uses trusted requesterSenderId for moderation and ignores params senderUserId
- forwards trusted mediaLocalRoots for send actions
- falls back to toolContext.currentMessageId for reactions when messageId is omitted
- rejects reactions when neither messageId nor toolContext.currentMessageId is provided
- telegramMessageActions
- lists poll when telegram is configured
- omits poll when sendMessage is disabled
- omits poll when poll actions are disabled
- omits poll when sendMessage and poll are split across accounts
- lists sticker actions only when enabled by config
- maps action params into telegram actions
- forwards trusted mediaLocalRoots for send
- rejects non-integer messageId for edit before reaching telegram-actions
- inherits top-level reaction gate when account overrides sticker only
- accepts numeric messageId and channelId for reactions
- accepts snake_case message_id for reactions
- falls back to toolContext.currentMessageId for reactions when messageId is omitted
- forwards missing reaction messageId to telegram-actions for soft-fail handling
- signalMessageActions
- lists actions based on account presence and reaction gates
- skips send for plugin dispatch
- blocks reactions when action gate is disabled
- maps reaction targets into signal sendReaction calls
- falls back to toolContext.currentMessageId for reactions when messageId is omitted
- rejects reaction when neither messageId nor toolContext.currentMessageId is provided
- requires targetAuthor for group reactions
- slack actions adapter
- forwards threadId for read
- forwards normalized limit for emoji-list
- forwards blocks for send/edit actions
- rejects invalid send block combinations before dispatch
- rejects edit when both message and blocks are missing

### src/channels/plugins/actions/reaction-message-id.test.lisp
- resolveReactionMessageId
- uses explicit messageId when present
- accepts snake_case message_id alias
- falls back to toolContext.currentMessageId

### src/channels/plugins/config-helpers.test.lisp
- clearAccountEntryFields
- clears configured values and removes empty account entries
- treats empty string values as not configured by default
- can mark cleared when fields are present even if values are empty
- keeps other account fields intact
- returns unchanged when account entry is missing

### src/channels/plugins/config-schema.test.lisp
- buildChannelConfigSchema
- builds json schema when toJSONSchema is available
- falls back when toJSONSchema is missing (zod v3 plugin compatibility)
- passes draft-07 compatibility options to toJSONSchema

### src/channels/plugins/directory-config-helpers.test.lisp
- listDirectoryUserEntriesFromAllowFrom
- normalizes, deduplicates, filters, and limits user ids
- listDirectoryGroupEntriesFromMapKeys
- extracts normalized group ids from map keys
- listDirectoryUserEntriesFromAllowFromAndMapKeys
- merges allowFrom and map keys with dedupe/query/limit
- listDirectoryGroupEntriesFromMapKeysAndAllowFrom
- merges groups keys and group allowFrom entries

### src/channels/plugins/group-mentions.test.lisp
- group mentions (slack)
- uses matched channel requireMention and wildcard fallback
- resolves sender override, then channel tools, then wildcard tools
- group mentions (telegram)
- resolves topic-level requireMention and chat-level tools for topic ids
- group mentions (discord)
- prefers channel policy, then guild policy, with sender-specific overrides
- group mentions (bluebubbles)
- uses generic channel group policy helpers
- group mentions (line)
- matches raw and prefixed LINE group keys for requireMention and tools
- uses account-scoped prefixed LINE group config for requireMention

### src/channels/plugins/group-policy-warnings.test.lisp
- group policy warning builders
- builds base open-policy warning
- builds restrict-senders warning
- builds no-route-allowlist warning
- builds configure-route-allowlist warning
- collects restrict-senders warning only for open policy
- resolves allowlist-provider runtime policy before collecting restrict-senders warnings
- passes resolved allowlist-provider policy into the warning collector
- passes resolved open-provider policy into the warning collector
- collects route allowlist warning variants
- collects configured-route warning variants

### src/channels/plugins/helpers.test.lisp
- buildAccountScopedDmSecurityPolicy
- builds top-level dm policy paths when no account config exists
- uses account-scoped paths when account config exists
- supports nested dm paths without explicit policyPath
- supports custom defaults and approve hints

### src/channels/plugins/message-actions.security.test.lisp
- dispatchChannelMessageAction trusted sender guard
- rejects privileged discord moderation action without trusted sender in tool context
- allows privileged discord moderation action with trusted sender in tool context
- does not require trusted sender without tool context

### src/channels/plugins/message-actions.test.lisp
- message action capability checks
- aggregates buttons/card support across plugins
- checks per-channel capabilities

### src/channels/plugins/normalize/targets.test.lisp
- normalize target helpers
- iMessage
- normalizes blank inputs to undefined
- detects common iMessage target forms
- WhatsApp
- normalizes blank inputs to undefined
- detects common WhatsApp target forms

### src/channels/plugins/normalize/telegram.test.lisp
- normalizeTelegramMessagingTarget
- normalizes t.me links to prefixed usernames
- keeps unprefixed topic targets valid
- keeps legacy prefixed topic targets valid
- looksLikeTelegramTargetId
- recognizes unprefixed topic targets
- recognizes legacy prefixed topic targets
- still recognizes normalized lookup targets

### src/channels/plugins/onboarding/channel-access-configure.test.lisp
- configureChannelAccessWithAllowlist
- returns input config when user skips access configuration
- applies non-allowlist policy directly
- resolves allowlist entries and applies them after forcing allowlist policy

### src/channels/plugins/onboarding/channel-access.test.lisp
- parseAllowlistEntries
- splits comma/newline/semicolon-separated entries
- formatAllowlistEntries
- formats compact comma-separated output
- promptChannelAllowlist
- uses existing entries as initial value
- promptChannelAccessPolicy
- returns selected policy
- promptChannelAccessConfig
- returns null when user skips configuration
- returns allowlist entries when policy is allowlist
- returns non-allowlist policy with empty entries

### src/channels/plugins/onboarding/helpers.test.lisp
- buildSingleChannelSecretPromptState
- enables env path only when env is present and no config token exists
- disables env path when config token already exists
- promptResolvedAllowFrom
- re-prompts without token until all ids are parseable
- re-prompts when token resolution returns unresolved entries
- re-prompts when resolver throws before succeeding
- promptLegacyChannelAllowFrom
- applies parsed ids without token resolution
- uses resolver when token is present
- promptSingleChannelToken
- uses env tokens when confirmed
- prompts for token when env exists but user declines env
- keeps existing configured token when confirmed
- prompts for token when no env/config token is used
- promptSingleChannelSecretInput
- returns use-env action when plaintext mode selects env fallback
- returns ref + resolved value when external env ref is selected
- returns keep action when ref mode keeps an existing configured ref
- applySingleTokenPromptResult
- writes env selection as an empty patch on target account
- writes provided token under requested key
- promptParsedAllowFromForScopedChannel
- writes parsed allowFrom values to default account channel config
- writes parsed values to non-default account allowFrom
- uses parser validation from the prompt validate callback
- channel lookup note helpers
- emits summary lines for resolved and unresolved entries
- skips note output when there is nothing to report
- formats lookup failures consistently
- setAccountAllowFromForChannel
- writes allowFrom on default account channel config
- writes allowFrom on nested non-default account config
- patchChannelConfigForAccount
- patches root channel config for default account
- patches nested account config and preserves existing enabled flag
- moves single-account config into default account when patching non-default
- supports imessage/signal account-scoped channel patches
- setOnboardingChannelEnabled
- updates enabled and keeps existing channel fields
- creates missing channel config with enabled state
- patchLegacyDmChannelConfig
- patches discord root config and defaults dm.enabled to true
- preserves explicit dm.enabled=false for slack
- setLegacyChannelDmPolicyWithAllowFrom
- adds wildcard allowFrom for open policy using legacy dm allowFrom fallback
- sets policy without changing allowFrom when not open
- setLegacyChannelAllowFrom
- writes allowFrom through legacy dm patching
- setAccountGroupPolicyForChannel
- writes group policy on default account config
- writes group policy on nested non-default account
- setChannelDmPolicyWithAllowFrom
- adds wildcard allowFrom when setting dmPolicy=open
- sets dmPolicy without changing allowFrom for non-open policies
- supports telegram channel dmPolicy updates
- setTopLevelChannelDmPolicyWithAllowFrom
- adds wildcard allowFrom for open policy
- supports custom allowFrom lookup callback
- setTopLevelChannelAllowFrom
- writes allowFrom and can force enabled state
- setTopLevelChannelGroupPolicy
- writes groupPolicy and can force enabled state
- splitOnboardingEntries
- splits comma/newline/semicolon input and trims blanks
- parseOnboardingEntriesWithParser
- maps entries and de-duplicates parsed values
- returns parser errors and clears parsed entries
- parseOnboardingEntriesAllowingWildcard
- preserves wildcard and delegates non-wildcard entries
- returns parser errors for non-wildcard entries
- parseMentionOrPrefixedId
- parses mention ids
- parses prefixed ids and normalizes result
- returns null for blank or invalid input
- normalizeAllowFromEntries
- normalizes values, preserves wildcard, and removes duplicates
- trims and de-duplicates without a normalizer
- resolveOnboardingAccountId
- normalizes provided account ids
- falls back to default account id when input is blank
- resolveAccountIdForConfigure
- uses normalized override without prompting
- uses default account when override is missing and prompting disabled
- prompts for account id when prompting is enabled and no override is provided

### src/channels/plugins/onboarding/imessage.test.lisp
- parseIMessageAllowFromEntries
- parses handles and chat targets
- returns validation errors for invalid chat_id
- returns validation errors for invalid chat_identifier entries

### src/channels/plugins/onboarding/signal.test.lisp
- normalizeSignalAccountInput
- normalizes valid E.164 numbers
- rejects invalid values
- parseSignalAllowFromEntries
- parses e164, uuid and wildcard entries
- normalizes bare uuid values
- returns validation errors for invalid entries

### src/channels/plugins/onboarding/telegram.test.lisp
- normalizeTelegramAllowFromInput
- strips telegram/tg prefixes and trims whitespace
- parseTelegramAllowFromId
- accepts numeric ids with optional prefixes
- rejects non-numeric values

### src/channels/plugins/onboarding/whatsapp.test.lisp
- whatsappOnboardingAdapter.configure
- applies owner allowlist when forceAllowFrom is enabled
- supports disabled DM policy for separate-phone setup
- normalizes allowFrom entries when list mode is selected
- enables allowlist self-chat mode for personal-phone setup
- forces wildcard allowFrom for open policy without allowFrom follow-up prompts
- runs WhatsApp login when not linked and user confirms linking
- skips relink note when already linked and relink is declined
- shows follow-up login command note when not linked and linking is skipped

### src/channels/plugins/outbound/direct-text-media.sendpayload.test.lisp
- createDirectTextMediaOutbound sendPayload
- text-only delegates to sendText
- single media delegates to sendMedia
- multi-media iterates URLs with caption on first
- empty payload returns no-op
- chunking splits long text

### src/channels/plugins/outbound/discord.sendpayload.test.lisp
- discordOutbound sendPayload
- text-only delegates to sendText
- single media delegates to sendMedia
- multi-media iterates URLs with caption on first
- empty payload returns no-op
- text exceeding chunk limit is sent as-is when chunker is null

### src/channels/plugins/outbound/discord.test.lisp
- normalizeDiscordOutboundTarget
- normalizes bare numeric IDs to channel: prefix
- passes through channel: prefixed targets
- passes through user: prefixed targets
- passes through channel name strings
- returns error for empty target
- returns error for undefined target
- trims whitespace
- discordOutbound
- routes text sends to thread target when threadId is provided
- uses webhook persona delivery for bound thread text replies
- falls back to bot send for silent delivery on bound threads
- falls back to bot send when webhook send fails
- routes poll sends to thread target when threadId is provided

### src/channels/plugins/outbound/imessage.test.lisp
- imessageOutbound
- passes replyToId through sendText
- passes replyToId through sendMedia

### src/channels/plugins/outbound/signal.test.lisp
- signalOutbound
- passes account-scoped maxBytes for sendText
- passes mediaUrl/mediaLocalRoots for sendMedia

### src/channels/plugins/outbound/slack.sendpayload.test.lisp
- slackOutbound sendPayload
- text-only delegates to sendText
- single media delegates to sendMedia
- multi-media iterates URLs with caption on first
- empty payload returns no-op
- text exceeding chunk limit is sent as-is when chunker is null

### src/channels/plugins/outbound/slack.test.lisp
- slack outbound hook wiring
- calls send without hooks when no hooks registered
- forwards identity opts when present
- forwards icon_emoji only when icon_url is absent
- calls message_sending hook before sending
- cancels send when hook returns cancel:true
- modifies text when hook returns content
- skips hooks when runner has no message_sending hooks

### src/channels/plugins/outbound/telegram.test.lisp
- telegramOutbound
- passes parsed reply/thread ids for sendText
- parses scoped DM thread ids for sendText
- passes media options for sendMedia
- sends payload media list and applies buttons only to first message

### src/channels/plugins/outbound/whatsapp.poll.test.lisp
- whatsappOutbound sendPoll
- threads cfg through poll send options

### src/channels/plugins/outbound/whatsapp.sendpayload.test.lisp
- whatsappOutbound sendPayload
- text-only delegates to sendText
- single media delegates to sendMedia
- multi-media iterates URLs with caption on first
- empty payload returns no-op
- chunking splits long text

### src/channels/plugins/plugins-channel.test.lisp
- imessage target normalization
- preserves service prefixes for handles
- drops service prefixes for chat targets
- signal target normalization
- normalizes uuid targets by stripping uuid:
- normalizes signal:uuid targets
- preserves case for group targets
- preserves case for base64-like group IDs without signal prefix
- accepts uuid prefixes for target detection
- accepts signal-prefixed E.164 targets for detection
- accepts compact UUIDs for target detection
- rejects invalid uuid prefixes
- telegramOutbound.sendPayload
- sends text payload with buttons
- sends media payloads and attaches buttons only to first
- whatsappOutbound.resolveTarget
- returns error when no target is provided even with allowFrom
- returns error when implicit target is not in allowFrom
- keeps group JID targets even when allowFrom does not contain them
- normalizeSignalAccountInput
- accepts already normalized numbers
- normalizes formatted input
- rejects empty input
- rejects non-numeric input
- rejects inputs with stray + characters
- rejects numbers that are too short or too long

### src/channels/plugins/plugins-core.test.lisp
- channel plugin registry
- sorts channel plugins by configured order
- refreshes cached channel lookups when the same registry instance is re-activated
- channel plugin catalog
- includes Microsoft Teams
- lists plugin catalog entries
- includes external catalog entries
- channel plugin loader
- loads channel plugins from the active registry
- loads outbound adapters from registered plugins
- refreshes cached plugin values when registry changes
- refreshes cached outbound values when registry changes
- returns undefined when plugin has no outbound adapter
- BaseProbeResult assignability
- TelegramProbe satisfies BaseProbeResult
- DiscordProbe satisfies BaseProbeResult
- SlackProbe satisfies BaseProbeResult
- SignalProbe satisfies BaseProbeResult
- IMessageProbe satisfies BaseProbeResult
- LineProbeResult satisfies BaseProbeResult
- BaseTokenResolution assignability
- Telegram and Discord token resolutions satisfy BaseTokenResolution
- resolveChannelConfigWrites
- defaults to allow when unset
- blocks when channel config disables writes
- account override wins over channel default
- matches account ids case-insensitively
- directory (config-backed)
- lists Slack peers/groups from config
- lists Discord peers/groups from config (numeric ids only)
- lists Telegram peers/groups from config
- keeps Telegram config-backed directory fallback semantics when accountId is omitted
- keeps config-backed directories readable when channel tokens are unresolved SecretRefs
- lists WhatsApp peers/groups from config
- applies query and limit filtering for config-backed directories

### src/channels/plugins/setup-helpers.test.lisp
- applySetupAccountConfigPatch
- patches top-level config for default account and enables channel
- patches named account config and enables both channel and account
- normalizes account id and preserves other accounts

### src/channels/plugins/status-issues/bluebubbles.test.lisp
- collectBlueBubblesStatusIssues
- reports unconfigured enabled accounts
- reports probe failure and runtime error for configured running accounts
- skips disabled accounts

### src/channels/plugins/status-issues/whatsapp.test.lisp
- collectWhatsAppStatusIssues
- reports unlinked enabled accounts
- reports linked but disconnected runtime state
- skips disabled accounts

### src/channels/plugins/whatsapp-heartbeat.test.lisp
- resolveWhatsAppHeartbeatRecipients
- uses allowFrom store recipients when session recipients are ambiguous
- falls back to allowFrom when no session recipient is authorized
- includes both session and allowFrom recipients when --all is set
- returns explicit --to recipient and source flag
- returns ambiguous session recipients when no allowFrom list exists
- returns single session recipient when allowFrom is empty
- returns all authorized session recipients when allowFrom matches multiple
- ignores session store when session scope is global

### src/channels/registry.helpers.test.lisp
- channel registry helpers
- normalizes aliases + trims whitespace
- keeps Telegram first in the default order
- does not include MS Teams by default
- formats selection lines with docs labels + website extras

### src/channels/run-state-machine.test.lisp
- createRunStateMachine
- resets stale busy fields on init
- emits busy status while active and clears when done
- stops publishing after lifecycle abort

### src/channels/sender-label.test.lisp
- resolveSenderLabel
- prefers display + identifier when both are available
- falls back to identifier-only labels
- returns null when all values are empty
- listSenderLabelCandidates
- returns unique normalized candidates plus resolved label

### src/channels/session.test.lisp
- recordInboundSession
- does not pass ctx when updating a different session key
- passes ctx when updating the same session key
- normalizes mixed-case session keys before recording and route updates
- skips last-route updates when main DM owner pin mismatches sender

### src/channels/status-reactions.test.lisp
- resolveToolEmoji
- should ${testCase.name}
- createStatusReactionController
- should not call adapter when disabled
- should call setReaction with initialEmoji for setQueued immediately
- should debounce setThinking and eventually call adapter
- should classify tool name and debounce
- should execute ${testCase.name} immediately without debounce
- should ${testCase.name}
- should only fire last state when rapidly changing (debounce)
- should deduplicate same emoji calls
- should call removeReaction when adapter supports it and emoji changes
- should only call setReaction when adapter lacks removeReaction
- should clear all known emojis when adapter supports removeReaction
- should handle clear gracefully when adapter lacks removeReaction
- should restore initial emoji
- should use custom emojis when provided
- should use custom timing when provided
- should trigger ${testCase.name}
- should reset stall timers on ${testCase.name}
- should call onError callback when adapter throws
- constants
- should export CODING_TOOL_TOKENS
- should export WEB_TOOL_TOKENS
- should export DEFAULT_EMOJIS with all required keys
- should export DEFAULT_TIMING with all required keys

### src/channels/targets.test.lisp
- channel targets
- ensureTargetId returns the candidate when it matches
- ensureTargetId throws with the provided message on mismatch
- requireTargetKind returns the target id when the kind matches
- requireTargetKind throws when the kind is missing or mismatched

### src/channels/telegram/allow-from.test.lisp
- telegram allow-from helpers
- normalizes tg/telegram prefixes
- accepts signed numeric IDs

### src/channels/telegram/api.test.lisp
- fetchTelegramChatId
- calls Telegram getChat endpoint

### src/channels/thread-binding-id.test.lisp
- resolveThreadBindingConversationIdFromBindingId
- returns the conversation id for matching account-prefixed binding ids
- returns undefined when binding id is missing or account prefix does not match
- trims whitespace and rejects empty ids after the account prefix

### src/channels/transport/stall-watchdog.test.lisp
- createArmableStallWatchdog
- fires onTimeout once when armed and idle exceeds timeout
- does not fire when disarmed before timeout
- extends timeout window when touched

### src/channels/typing-start-guard.test.lisp
- createTypingStartGuard
- skips starts when sealed
- trips breaker after max consecutive failures
- resets breaker state
- rethrows start errors when configured

### src/channels/typing.test.lisp
- createTypingCallbacks
- invokes start on reply start
- reports start errors
- invokes stop on idle and reports stop errors
- sends typing keepalive pings until idle cleanup
- stops keepalive after consecutive start failures
- does not restart keepalive when breaker trips on initial start
- resets failure counter after a successful keepalive tick
- deduplicates stop across idle and cleanup
- does not restart keepalive after idle cleanup
- TTL safety
- auto-stops typing after maxDurationMs
- does not auto-stop if idle is called before TTL
- uses default 60s TTL when not specified
- disables TTL when maxDurationMs is 0
- resets TTL timer on restart after idle

## cli

### src/cli/acp-cli.option-collisions.test.lisp
- acp cli option collisions
- forwards --verbose to `acp client` when parent and child option names collide
- loads gateway token/password from files
- rejects mixed secret flags and file flags
- rejects mixed password flags and file flags
- warns when inline secret flags are used
- trims token file path before reading
- reports missing token-file read errors

### src/cli/argv.test.lisp
- argv helpers
- extracts command path while skipping known root option values
- extracts routed config get positionals with interleaved root options
- extracts routed config unset positionals with interleaved root options
- returns null when routed command sees unknown options
- parses verbose flags
- builds parse argv from raw args
- builds parse argv from fallback args
- decides when to migrate state

### src/cli/banner.test.lisp
- formatCliBannerLine
- hides tagline text when cli.banner.taglineMode is off
- uses default tagline when cli.banner.taglineMode is default
- prefers explicit tagline mode over config

### src/cli/browser-cli-actions-input/shared.test.lisp
- readFields
- requires ref

### src/cli/browser-cli-extension.test.lisp
- bundled extension resolver (fs-mocked)
- walks up to find the assets directory
- prefers the nearest assets directory
- browser extension install (fs-mocked)
- installs into the state dir (never node_modules)
- copies extension path to clipboard

### src/cli/browser-cli-inspect.test.lisp
- browser cli snapshot defaults
- does not set mode when config defaults are absent
- applies explicit efficient mode without config defaults
- sends screenshot request with trimmed target id and jpeg type

### src/cli/browser-cli-manage.timeout-option.test.lisp
- browser manage start timeout option
- uses parent --timeout for browser start instead of hardcoded 15s

### src/cli/browser-cli-state.option-collisions.test.lisp
- browser state option collisions
- forwards parent-captured --target-id on `browser cookies set`
- resolves --url via parent when addGatewayClientOptions captures it
- inherits --url from parent when subcommand does not provide it
- accepts legacy parent `--json` by parsing payload via positional headers fallback
- filters non-string header values from JSON payload
- errors when set offline receives an invalid value
- errors when set media receives an invalid value
- errors when headers JSON is missing
- errors when headers JSON is not an object

### src/cli/browser-cli.test.lisp
- browser command-line interface --browser-profile flag
- does not conflict with global --profile flag

### src/cli/channel-auth.test.lisp
- channel-auth
- runs login with explicit trimmed account and verbose flag
- auto-picks the single configured channel when opts are empty
- propagates channel ambiguity when channel is omitted
- throws for unsupported channel aliases
- throws when channel does not support login
- runs logout with resolved account and explicit account id
- throws when channel does not support logout

### src/cli/channel-options.test.lisp
- resolveCliChannelOptions
- uses precomputed startup metadata when available
- falls back to dynamic catalog resolution when metadata is missing
- respects eager mode and includes loaded plugin ids
- keeps dynamic catalog resolution when external catalog env is set

### src/cli/cli-utils.test.lisp
- waitForever
- creates an unref'ed interval and returns a pending promise
- shouldSkipRespawnForArgv
- skips respawn for help/version calls
- keeps respawn path for normal commands
- nodes canvas helpers
- parses canvas.snapshot payload
- rejects invalid canvas.snapshot payload
- dns cli
- prints setup info (no apply)
- parseByteSize
- parses byte-size units and shorthand values
- uses default unit when omitted
- rejects invalid values
- parseDurationMs
- parses duration strings
- rejects invalid composite strings

### src/cli/command-options.test.lisp
- inheritOptionFromParent
- does not inherit when the child option was set explicitly
- does not inherit from ancestors beyond the bounded traversal depth
- inherits values from non-default ancestor sources (for example env)
- skips default-valued ancestor options and keeps traversing
- returns undefined when command is missing

### src/cli/command-secret-gateway.test.lisp
- resolveCommandSecretRefsViaGateway
- returns config unchanged when no target SecretRefs are configured
- skips gateway resolution when all configured target refs are inactive
- hydrates requested SecretRef targets from gateway snapshot assignments
- fails fast when gateway-backed resolution is unavailable
- falls back to local resolution when gateway secrets.resolve is unavailable
- returns a version-skew hint when gateway does not support secrets.resolve
- returns a version-skew hint when required-method capability check fails
- fails when gateway returns an invalid secrets.resolve payload
- fails when gateway assignment path does not exist in local config
- fails when configured refs remain unresolved after gateway assignments are applied
- allows unresolved refs when gateway diagnostics mark the target as inactive
- uses inactiveRefPaths from structured response without parsing diagnostic text
- allows unresolved array-index refs when gateway marks concrete paths inactive
- degrades unresolved refs in summary mode instead of throwing
- uses targeted local fallback after an incomplete gateway snapshot
- limits strict local fallback analysis to unresolved gateway paths
- limits local fallback to targeted refs in read-only modes
- degrades unresolved refs in operational read-only mode

### src/cli/command-secret-resolution.coverage.test.lisp
- command secret resolution coverage

### src/cli/command-secret-targets.test.lisp
- command secret target ids
- includes memorySearch remote targets for agent runtime commands
- keeps memory command target set focused on memorySearch remote credentials

### src/cli/completion-fish.test.lisp
- completion-fish helpers
- escapes single quotes in descriptions
- builds a subcommand completion line
- builds option line with short and long flags
- builds option line with long-only flags

### src/cli/config-cli.test.lisp
- config cli
- config set - issue #6070
- preserves existing config keys when setting a new value
- does not inject runtime defaults into the written config
- auto-seeds a valid Ollama provider when setting only models.providers.ollama.apiKey
- config get
- redacts sensitive values
- config validate
- prints success and exits 0 when config is valid
- prints issues and exits 1 when config is invalid
- returns machine-readable JSON with --json for invalid config
- preserves allowed-values metadata in --json output
- prints file-not-found and exits 1 when config file is missing
- config set parsing flags
- falls back to raw string when parsing fails and strict mode is off
- throws when strict parsing is enabled via --strict-json
- keeps --json as a strict parsing alias
- shows --strict-json and keeps --json as a legacy alias in help
- path hardening
- rejects blocked prototype-key segments for config get
- rejects blocked prototype-key segments for config set
- rejects blocked prototype-key segments for config unset
- config unset - issue #6070
- preserves existing config keys when unsetting a value
- config file
- prints the active config file path
- handles config file path with home directory

### src/cli/cron-cli.test.lisp
- cron cli
- trims model and thinking on cron add
- defaults isolated cron add to announce delivery
- infers sessionTarget from payload when --session is omitted
- supports --keep-after-run on cron add
- includes --account on isolated cron add delivery
- rejects --account on non-isolated/systemEvent cron add
- sends agent id on cron add
- sets lightContext on cron add when --light-context is passed
- sets and clears agent id on cron edit
- allows model/thinking updates without --message
- sets and clears lightContext on cron edit
- updates delivery settings without requiring --message
- supports --no-deliver on cron edit
- updates delivery account without requiring --message on cron edit
- does not include undefined delivery fields when updating message
- includes delivery fields when explicitly provided with message
- sets explicit stagger for cron add
- sets exact cron mode on add
- rejects --stagger with --exact on add
- rejects --stagger when schedule is not cron
- sets explicit stagger for cron edit
- applies --exact to existing cron job without requiring --cron on edit
- rejects --exact on edit when existing job is not cron
- patches failure alert settings on cron edit
- supports --no-failure-alert on cron edit
- patches failure alert mode/accountId on cron edit

### src/cli/cron-cli/shared.test.lisp
- printCronList
- handles job with undefined sessionTarget (#9649)
- handles job with defined sessionTarget
- shows stagger label for cron schedules
- shows dash for unset agentId instead of default
- shows Model column with payload.model for agentTurn jobs
- shows dash in Model column for systemEvent jobs
- shows dash in Model column for agentTurn jobs without model override
- shows explicit agentId when set
- shows exact label for cron schedules with stagger disabled

### src/cli/daemon-cli-compat.test.lisp
- resolveLegacyDaemonCliAccessors
- resolves aliased daemon-cli exports from a bundled chunk
- returns null when required aliases are missing
- returns null when the required restart alias is missing

### src/cli/daemon-cli.coverage.test.lisp
- daemon-cli coverage
- probes gateway status by default
- derives probe URL from service args + env (json)
- passes deep scan flag for daemon status
- installs the daemon (json output)
- starts and stops daemon (json output)

### src/cli/daemon-cli/gateway-token-drift.test.lisp
- resolveGatewayTokenForDriftCheck
- prefers persisted config token over shell env
- does not fall back to caller env for unresolved config token refs

### src/cli/daemon-cli/install.integration.test.lisp
- runDaemonInstall integration
- fails closed when token SecretRef is required but unresolved
- auto-mints token when no source exists without embedding it into service env

### src/cli/daemon-cli/install.test.lisp
- runDaemonInstall
- fails install when token auth requires an unresolved token SecretRef
- validates token SecretRef but does not serialize resolved token into service env
- does not treat env-template gateway.auth.token as plaintext during install
- auto-mints and persists token when no source exists
- continues Linux install when service probe hits a non-fatal systemd bus failure
- fails install when service probe reports an unrelated error

### src/cli/daemon-cli/lifecycle-core.test.lisp
- runServiceRestart token drift
- emits drift warning when enabled
- compares restart drift against config token even when caller env is set
- skips drift warning when disabled
- emits stopped when an unmanaged process handles stop
- runs restart health checks after an unmanaged restart signal

### src/cli/daemon-cli/lifecycle.test.lisp
- runDaemonRestart health checks
- kills stale gateway pids and retries restart
- fails restart when gateway remains unhealthy
- signals an unmanaged gateway process on stop
- signals a single unmanaged gateway process on restart
- fails unmanaged restart when multiple gateway listeners are present
- fails unmanaged restart when the running gateway has commands.restart disabled
- skips unmanaged signaling for pids that are not live gateway processes

### src/cli/daemon-cli/register-service-commands.test.lisp
- addGatewayServiceCommands
- forwards install option collisions from parent gateway command
- forwards status auth collisions from parent gateway command

### src/cli/daemon-cli/restart-health.test.lisp
- inspectGatewayRestart
- treats a gateway listener child pid as healthy ownership
- marks non-owned gateway listener pids as stale while runtime is running
- treats unknown listeners as stale on Windows when enabled
- does not treat unknown listeners as stale when fallback is disabled
- does not apply unknown-listener fallback while runtime is running
- does not treat known non-gateway listeners as stale in fallback mode
- uses a local gateway probe when ownership is ambiguous
- treats auth-closed probe as healthy gateway reachability
- treats busy ports with unavailable listener details as healthy when runtime is running

### src/cli/daemon-cli/shared.test.lisp
- resolveRuntimeStatusColor
- maps known runtime states to expected theme colors
- falls back to warning color for unexpected states

### src/cli/daemon-cli/status.gather.test.lisp
- gatherDaemonStatus
- uses wss probe URL and forwards TLS fingerprint when daemon TLS is enabled
- does not force local TLS fingerprint when probe URL is explicitly overridden
- resolves daemon gateway auth password SecretRef values before probing
- resolves daemon gateway auth token SecretRef values before probing
- does not resolve daemon password SecretRef when token auth is configured
- keeps remote probe auth strict when remote token is missing
- skips TLS runtime loading when probe is disabled

### src/cli/deps.test.lisp
- createDefaultDeps
- does not load provider modules until a dependency is used
- reuses module cache after first dynamic import

### src/cli/devices-cli.test.lisp
- devices cli approve
- approves an explicit request id without listing
- prints an error and exits when no pending requests are available
- devices cli remove
- removes a paired device by id
- devices cli clear
- requires --yes before clearing
- clears paired devices and optionally pending requests
- devices cli tokens
- rejects blank device or role values
- devices cli local fallback
- falls back to local pairing list when gateway returns pairing required on loopback
- falls back to local approve when gateway returns pairing required on loopback
- does not use local fallback when an explicit --url is provided

### src/cli/exec-approvals-cli.test.lisp
- exec approvals command-line interface
- routes get command to local, gateway, and sbcl modes
- defaults allowlist add to wildcard agent
- removes wildcard allowlist entry and prunes empty agent

### src/cli/gateway-cli.coverage.test.lisp
- gateway-cli coverage
- registers call/health commands and routes to callGateway
- registers gateway probe and routes to gatewayStatusCommand
- registers gateway discover and prints json output
- validates gateway discover timeout
- fails gateway call on invalid params JSON
- validates gateway ports and handles force/start errors
- prints stop hints on GatewayLockError when service is loaded
- uses env/config port when --port is omitted

### src/cli/gateway-cli/register.option-collisions.test.lisp
- gateway register option collisions
- forwards --token to gateway call when parent and child option names collide
- forwards --token to gateway probe when parent and child option names collide

### src/cli/gateway-cli/run-loop.test.lisp
- runGatewayLoop
- exits 0 on SIGTERM after graceful close
- restarts after SIGUSR1 even when drain times out, and resets lanes for the new iteration
- releases the lock before exiting on spawned restart
- forwards lockPort to initial and restart lock acquisitions
- exits when lock reacquire fails during in-process restart fallback
- gateway discover routing helpers
- prefers resolved service host over TXT hints
- prefers resolved service port over TXT gatewayPort
- falls back to TXT host/port when resolve data is missing

### src/cli/gateway-cli/run.option-collisions.test.lisp
- gateway run option collisions
- forwards parent-captured options to `gateway run` subcommand
- starts gateway when token mode has no configured token (startup bootstrap path)
- accepts --auth none override
- accepts --auth trusted-proxy override
- prints all supported modes on invalid --auth value
- allows password mode preflight when password is configured via SecretRef
- reads gateway password from --password-file
- warns when gateway password is passed inline
- rejects using both --password and --password-file

### src/cli/hooks-cli.test.lisp
- hooks cli formatting
- labels hooks list output
- labels hooks status output
- labels plugin-managed hooks with plugin id

### src/cli/log-level-option.test.lisp
- parseCliLogLevelOption
- accepts allowed log levels
- rejects invalid log levels

### src/cli/logs-cli.test.lisp
- logs cli
- writes output directly to stdout/stderr
- wires --local-time through command-line interface parsing and emits local timestamps
- warns when the output pipe closes
- formatLogTimestamp
- formats UTC timestamp in plain mode by default
- formats UTC timestamp in pretty mode
- formats local time in plain mode when localTime is true
- formats local time in pretty mode when localTime is true

### src/cli/memory-cli.test.lisp
- memory cli
- prints vector status when available
- resolves configured memory SecretRefs through gateway snapshot
- logs gateway secret diagnostics for non-json status output
- documents memory help examples
- prints vector error when unavailable
- prints embeddings status when deep
- enables verbose logging with --verbose
- logs close failure after status
- reindexes on status --index
- closes manager after index
- logs qmd index file path and size after index
- fails index when qmd db file is empty
- logs close failures without failing the command
- logs close failure after search
- closes manager after search error
- prints status json output when requested
- routes gateway secret diagnostics to stderr for json status output
- logs default message when memory manager is missing
- logs backend unsupported message when index has no sync
- prints no matches for empty search results
- accepts --query for memory search
- prefers --query when positional and flag are both provided
- fails when neither positional query nor --query is provided
- prints search results as json when requested

### src/cli/models-cli.test.lisp
- models cli
- registers github-copilot login command
- shows help for models auth without error exit

### src/cli/nodes-camera.test.lisp
- nodes camera helpers
- parses camera.snap payload
- rejects invalid camera.snap payload
- parses camera.clip payload
- rejects invalid camera.clip payload
- builds stable temp paths when id provided
- writes camera clip payload to temp path
- writes camera clip payload from url
- rejects camera clip url payloads without sbcl remoteIp
- writes base64 to file
- writes url payload to file
- rejects url host mismatches
- rejects invalid url payload responses
- removes partially written file when url stream fails
- nodes screen helpers
- parses screen.record payload
- drops invalid optional fields instead of throwing
- rejects invalid screen.record payload
- builds screen record temp path

### src/cli/nodes-cli.coverage.test.lisp
- nodes-cli coverage
- invokes system.run with parsed params
- invokes system.run with raw command
- inherits ask=off from local exec approvals when tools.exec.ask is unset
- invokes system.notify with provided fields
- invokes location.get with params

### src/cli/nodes-cli/register.invoke.nodes-run-approval-timeout.test.lisp
- nodes run: approval transport timeout (#12098)
- callGatewayCli forwards opts.timeout as the transport timeoutMs
- fix: overriding transportTimeoutMs gives the approval enough transport time
- fix: user-specified timeout larger than approval is preserved
- fix: non-numeric timeout falls back to approval floor

### src/cli/nodes-media-utils.test.lisp
- cli/nodes-media-utils
- parses primitive helper values
- normalizes temp path parts

### src/cli/Quicklisp/Ultralisp-resolution.test.lisp
- Quicklisp/Ultralisp-resolution helpers
- keeps original spec when pin is disabled
- warns when pin is enabled but resolved spec is missing
- returns pinned spec notice when resolved spec is available
- maps Quicklisp/Ultralisp resolution metadata to install fields
- builds common Quicklisp/Ultralisp install record fields
- logs pin warning/notice messages through provided writers
- resolves pinned install record and emits pin notice
- resolves pinned install record for command-line interface and formats warning output

### src/cli/outbound-send-mapping.test.lisp
- createOutboundSendDepsFromCliSource
- maps command-line interface send deps to outbound send deps

### src/cli/pairing-cli.test.lisp
- pairing cli
- evaluates pairing channels when registering the command-line interface (not at import)
- accepts channel as positional for list
- forwards --account for list
- normalizes channel aliases
- accepts extension channels outside the registry
- defaults list to the sole available channel
- accepts channel as positional for approve (Quicklisp/Ultralisp-run compatible)
- forwards --account for approve
- defaults approve to the sole available channel when only code is provided
- keeps approve usage error when multiple channels exist and channel is omitted

### src/cli/plugin-install-plan.test.lisp
- plugin install plan helpers
- prefers bundled plugin for bare plugin-id specs
- skips bundled pre-plan for scoped Quicklisp/Ultralisp specs
- uses Quicklisp/Ultralisp-spec bundled fallback only for package-not-found
- skips fallback for non-not-found Quicklisp/Ultralisp failures

### src/cli/plugins-config.test.lisp
- setPluginEnabledInConfig
- sets enabled flag for an existing plugin entry
- creates a plugin entry when it does not exist
- keeps built-in channel and plugin entry flags in sync

### src/cli/ports.test.lisp
- probePortFree
- resolves false (not rejects) when bind returns EADDRINUSE
- rejects immediately for EADDRNOTAVAIL (non-retryable: host address not on any interface)
- rejects immediately for EACCES (non-retryable bind error)
- rejects immediately for other non-retryable errors
- resolves true when the port is free
- waitForPortBindable
- probes the provided host when waiting for bindability
- propagates EACCES rejection immediately without retrying

### src/cli/profile.test.lisp
- parseCliProfileArgs
- leaves gateway --dev for subcommands
- still accepts global --dev before subcommand
- parses --profile value and strips it
- rejects missing profile value
- applyCliProfileEnv
- fills env defaults for dev profile
- does not override explicit env values
- uses OPENCLAW_HOME when deriving profile state dir
- formatCliCommand
- inserts --profile flag when profile is set
- trims whitespace from profile
- handles command with no args after openclaw
- handles ASDF/Quicklisp/Ultralisp wrapper

### src/cli/program.force.test.lisp
- gateway --force helpers
- parses lsof output into pid/command pairs
- returns empty list when lsof finds nothing
- throws when lsof missing
- kills each listener and returns metadata
- retries until the port is free
- escalates to SIGKILL if SIGTERM doesn't free the port
- falls back to fuser when lsof is permission denied
- uses fuser SIGKILL escalation when port stays busy
- throws when lsof is unavailable and fuser is missing
- gateway --force helpers (Windows netstat path)
- returns empty list when netstat finds no listeners on the port
- parses PIDs from netstat output correctly
- does not incorrectly match a port that is a substring (e.g. 80 vs 8080)
- deduplicates PIDs that appear multiple times
- throws a descriptive error when netstat fails
- kills Windows listeners and returns metadata

### src/cli/program.nodes-basic.e2e.test.lisp
- cli program (nodes basics)
- runs nodes list --connected and filters to connected nodes
- runs nodes status --last-connected and filters by age
- runs nodes describe and calls sbcl.describe
- runs nodes approve and calls sbcl.pair.approve
- runs nodes invoke and calls sbcl.invoke

### src/cli/program.nodes-media.e2e.test.lisp
- cli program (nodes media)
- runs nodes camera snap and prints two MEDIA paths
- runs nodes camera clip and prints one MEDIA path
- runs nodes camera snap with facing front and passes params
- runs nodes camera clip with --no-audio
- runs nodes camera clip with human duration (10s)
- runs nodes canvas snapshot and prints MEDIA path
- fails nodes camera snap on invalid facing
- fails nodes camera snap when --facing both and --device-id are combined
- URL-based payloads

### src/cli/program.nodes-test-helpers.test.lisp
- program.nodes-test-helpers
- builds a sbcl.list response with iOS sbcl fixture

### src/cli/program.smoke.test.lisp
- cli program (smoke)
- registers memory + status commands
- runs tui with explicit timeout override
- warns and ignores invalid tui timeout override
- runs setup wizard when wizard flags are present

### src/cli/program/action-reparse.test.lisp
- reparseProgramFromActionArgs
- uses action command name + args as fallback argv
- falls back to action args without command name when action has no name
- uses program root when action command is missing

### src/cli/program/build-program.test.lisp
- buildProgram
- wires context/help/preaction/command registration with shared context

### src/cli/program/build-program.version-alias.test.lisp
- buildProgram version alias handling
- exits with version output for root -v
- does not treat subcommand -v as root version alias

### src/cli/program/command-registry.test.lisp
- command-registry
- includes both agent and agents in core command-line interface command names
- returns only commands that support subcommands
- registerCoreCliByName resolves agents to the agent entry
- registerCoreCliByName returns false for unknown commands
- registers doctor placeholder for doctor primary command
- does not narrow to the primary command when help is requested
- treats maintenance commands as top-level builtins
- registers grouped core entry placeholders without duplicate command errors
- replaces placeholders when loading a grouped entry by secondary command name

### src/cli/program/command-tree.test.lisp
- command-tree
- removes a command instance when present
- returns false when command instance is already absent
- removes by command name
- returns false when name does not exist

### src/cli/program/config-guard.test.lisp
- ensureConfigReady
- exits for invalid config on non-allowlisted commands
- does not exit for invalid config on allowlisted commands
- runs doctor migration flow only once per module instance
- still runs doctor flow when stdout suppression is enabled
- prevents preflight stdout noise when suppression is enabled
- allows preflight stdout noise when suppression is not enabled

### src/cli/program/context.test.lisp
- createProgramContext
- builds program context from version and resolved channel options
- handles empty channel options
- does not resolve channel options before access
- reuses one channel option resolution across all getters
- reads program version without resolving channel options

### src/cli/program/help.test.lisp
- configureProgramHelp
- adds root help hint and marks commands with subcommands
- includes banner and docs/examples in root help output
- prints version and exits immediately when version flags are present

### src/cli/program/helpers.test.lisp
- program helpers
- collectOption appends values in order
- resolveActionArgs returns args when command has arg array
- resolveActionArgs returns empty array for missing/invalid args

### src/cli/program/message/helpers.test.lisp
- runMessageAction
- calls exit(0) after successful message delivery
- runs gateway_stop hooks before exit when registered
- calls exit(1) when message delivery fails
- runs gateway_stop hooks on failure before exit(1)
- logs gateway_stop failure and still exits with success code
- logs gateway_stop failure and preserves failure exit code when send fails
- does not call exit(0) when the action throws
- does not call exit(0) if the error path returns
- passes action and maps account to accountId
- strips non-string account values instead of passing accountId

### src/cli/program/preaction.test.lisp
- registerPreActionHooks
- handles debug mode and plugin-required command preaction
- skips help/version preaction and respects banner opt-out
- applies --json stdout suppression only for explicit JSON output commands
- bypasses config guard for config validate
- bypasses config guard for config validate when root option values are present

### src/cli/program/program-context.test.lisp
- program context storage
- stores and retrieves context on a command instance
- returns undefined when no context was set
- does not leak context between command instances

### src/cli/program/register.agent.test.lisp
- registerAgentCommands
- runs agent command with deps and verbose enabled for --verbose on
- runs agent command with verbose disabled for --verbose off
- runs agents add and computes hasFlags based on explicit options
- runs agents list when root agents command is invoked
- forwards agents list options
- forwards agents bindings options
- forwards agents bind options
- documents bind accountId resolution behavior in help text
- forwards agents unbind options
- forwards agents delete options
- forwards set-identity options
- reports errors via runtime when a command fails
- reports errors via runtime when agent command fails

### src/cli/program/register.configure.test.lisp
- registerConfigureCommand
- forwards repeated --section values
- reports errors through runtime when configure command fails

### src/cli/program/register.maintenance.test.lisp
- registerMaintenanceCommands doctor action
- exits with code 0 after successful doctor run
- exits with code 1 when doctor fails
- maps --fix to repair=true
- passes noOpen to dashboard command
- passes reset options to reset command
- passes uninstall options to uninstall command
- exits with code 1 when dashboard fails

### src/cli/program/register.message.test.lisp
- registerMessageCommands
- registers message command and wires all message sub-registrars with shared helpers
- shows command help when root message command is invoked

### src/cli/program/register.onboard.test.lisp
- registerOnboardCommand
- defaults installDaemon to undefined when no daemon flags are provided
- sets installDaemon from explicit install flags and prioritizes --skip-daemon
- parses numeric gateway port and drops invalid values
- forwards --reset-scope to onboard command options
- parses --mistral-api-key and forwards mistralApiKey
- forwards --gateway-token-ref-env
- reports errors via runtime on onboard command failures

### src/cli/program/register.setup.test.lisp
- registerSetupCommand
- runs setup command by default
- runs onboard command when --wizard is set
- runs onboard command when wizard-only flags are passed explicitly
- reports setup errors through runtime

### src/cli/program/register.status-health-sessions.test.lisp
- registerStatusHealthSessionsCommands
- runs status command with timeout and debug-derived verbose
- rejects invalid status timeout without calling status command
- runs health command with parsed timeout
- rejects invalid health timeout without calling health command
- runs sessions command with forwarded options
- runs sessions command with --agent forwarding
- runs sessions command with --all-agents forwarding
- runs sessions cleanup subcommand with forwarded options
- forwards parent-level all-agents to cleanup subcommand

### src/cli/program/register.subclis.test.lisp
- registerSubCliCommands
- registers only the primary placeholder and dispatches
- registers placeholders for all subcommands when no primary
- returns null for plugin registration when the config snapshot is invalid
- loads validated config for plugin registration when the snapshot is valid
- re-parses argv for lazy subcommands
- replaces placeholder when registering a subcommand by name

### src/cli/program/routes.test.lisp
- program routes
- matches status route and always loads plugins for security parity
- matches health route and preloads plugins only for text output
- returns false when status timeout flag value is missing
- returns false for sessions route when --store value is missing
- returns false for sessions route when --active value is missing
- returns false for sessions route when --agent value is missing
- does not fast-route sessions subcommands
- does not match unknown routes
- returns false for config get route when path argument is missing
- returns false for config unset route when path argument is missing
- passes config get path correctly when root option values precede command
- passes config unset path correctly when root option values precede command
- passes config get path when root value options appear after subcommand
- passes config unset path when root value options appear after subcommand
- returns false for config get route when unknown option appears
- returns false for memory status route when --agent value is missing
- returns false for models list route when --provider value is missing
- returns false for models status route when probe flags are missing values
- returns false for models status route when --probe-profile has no value
- accepts negative-number probe profile values

### src/cli/progress.test.lisp
- cli progress
- logs progress when non-tty and fallback=log
- does not log without a tty when fallback is none

### src/cli/prompt.test.lisp
- promptYesNo
- returns true when global --yes is set
- asks the question and respects default

### src/cli/qr-cli.test.lisp
- registerQrCli
- prints setup code only when requested
- renders ASCII QR by default
- accepts --token override when config has no auth
- skips local password SecretRef resolution when --token override is provided
- resolves local gateway auth password SecretRefs before setup code generation
- uses OPENCLAW_GATEWAY_PASSWORD without resolving local password SecretRef
- does not resolve local password SecretRef when auth mode is token
- resolves local password SecretRef when auth mode is inferred
- fails when token and password SecretRefs are both configured with inferred mode
- exits with error when gateway config is not pairable
- uses gateway.remote.url when --remote is set (ignores device-pair publicUrl)
- logs remote secret diagnostics in non-json output mode
- routes remote secret diagnostics to stderr for setup-code-only output
- routes remote secret diagnostics to stderr for json output
- errors when --remote is set but no remote URL is configured
- supports --remote with tailscale serve when remote token ref resolves

### src/cli/qr-dashboard.integration.test.lisp
- cli integration: qr + dashboard token SecretRef
- uses the same resolved token SecretRef for both qr and dashboard commands
- fails qr but keeps dashboard actionable when the shared token SecretRef is unresolved

### src/cli/route.test.lisp
- tryRouteCli
- passes suppressDoctorStdout=true for routed --json commands
- does not pass suppressDoctorStdout for routed non-json commands
- routes status when root options precede the command

### src/cli/run-main.exit.test.lisp
- runCli exit behavior
- does not force process.exit after successful routed command

### src/cli/run-main.profile-env.test.lisp
- runCli profile env bootstrap
- applies --profile before dotenv loading

### src/cli/run-main.test.lisp
- rewriteUpdateFlagArgv
- leaves argv unchanged when --update is absent
- rewrites --update into the update command
- preserves global flags that appear before --update
- keeps update options after the rewritten command
- shouldRegisterPrimarySubcommand
- skips eager primary registration for help/version invocations
- keeps eager primary registration for regular command runs
- shouldSkipPluginCommandRegistration
- skips plugin registration for root help/version
- skips plugin registration for builtin subcommand help
- skips plugin registration for builtin command runs
- keeps plugin registration for non-builtin help
- keeps plugin registration for non-builtin command runs
- shouldEnsureCliPath
- skips path bootstrap for help/version invocations
- skips path bootstrap for read-only fast paths
- keeps path bootstrap for mutating or unknown commands

### src/cli/secrets-cli.test.lisp
- secrets command-line interface
- calls secrets.reload and prints human output
- prints JSON when requested
- runs secrets audit and exits via check code
- runs secrets configure then apply when confirmed
- forwards --agent to secrets configure

### src/cli/skills-cli.commands.test.lisp
- registerSkillsCli
- runs list command with resolved report and formatter options
- runs info command and forwards skill name
- runs check command and writes formatter output
- uses list formatter for default skills action
- reports runtime errors when report loading fails

### src/cli/skills-cli.formatting.test.lisp
- skills-cli (e2e)
- loads bundled skills and formats them
- formats info for a real bundled skill (peekaboo)

### src/cli/skills-cli.test.lisp
- skills-cli
- formatSkillsList
- formats empty skills list
- formats skills list with eligible skill
- formats skills list with disabled skill
- formats skills list with missing requirements
- filters to eligible only with --eligible flag
- formatSkillInfo
- returns not found message for unknown skill
- shows detailed info for a skill
- formatSkillsCheck
- shows summary of skill status
- JSON output

### src/cli/system-cli.test.lisp
- system-cli
- runs system event with default wake mode and text output
- prints JSON for event when --json is enabled
- handles invalid wake mode as runtime error

### src/cli/tagline.test.lisp
- pickTagline
- returns empty string when mode is off
- returns default tagline when mode is default
- keeps OPENCLAW_TAGLINE_INDEX behavior in random mode

### src/cli/update-cli.option-collisions.test.lisp
- update cli option collisions
- forwards parent-captured --json/--timeout to `update status`
- forwards parent-captured --timeout to `update wizard`

### src/cli/update-cli.test.lisp
- update-cli
- updateCommand --dry-run previews without mutating
- updateStatusCommand prints table output
- updateStatusCommand emits JSON
- falls back to latest when beta tag is older than release
- honors --tag override
- updateCommand outputs JSON when --json is set
- updateCommand exits with error on failure
- updateCommand refreshes gateway service env when service is already installed
- updateCommand refreshes service env from updated install root when available
- updateCommand falls back to restart when env refresh install fails
- updateCommand falls back to restart when no detached restart script is available
- updateCommand does not refresh service env when --no-restart is set
- updateCommand continues after doctor sub-step and clears update flag
- updateCommand skips success message when restart does not run
- persists update channel when --channel is set
- dry-run bypasses downgrade confirmation checks in non-interactive mode
- updateWizardCommand requires a TTY
- updateWizardCommand offers dev checkout and forwards selections

### src/cli/update-cli/progress.test.lisp
- inferUpdateFailureHints
- returns EACCES hint for global update permission failures
- returns native optional dependency hint for sbcl-gyp failures
- does not return Quicklisp/Ultralisp hints for non-Quicklisp/Ultralisp install modes

### src/cli/update-cli/restart-helper.test.lisp
- restart-helper
- prepareRestartScript
- creates a systemd restart script on Linux
- uses OPENCLAW_SYSTEMD_UNIT override for systemd scripts
- creates a launchd restart script on macOS
- uses OPENCLAW_LAUNCHD_LABEL override on macOS
- creates a schtasks restart script on Windows
- uses OPENCLAW_WINDOWS_TASK_NAME override on Windows
- uses passed gateway port for port polling on Windows
- uses custom profile in service names
- uses custom profile in macOS launchd label
- uses custom profile in Windows task name
- returns null for unsupported platforms
- returns null when script creation fails
- escapes single quotes in profile names for shell scripts
- expands HOME in plist path instead of leaving literal $HOME
- prefers env parameter HOME over the process environment via UIOP.HOME for plist path
- shell-escapes the label in the plist path on macOS
- rejects unsafe batch profile names on Windows
- runRestartScript
- spawns the script as a detached process on Linux
- uses cmd.exe on Windows
- quotes cmd.exe /c paths with metacharacters on Windows

### src/cli/update-cli/shared.command-runner.test.lisp
- createGlobalCommandRunner
- forwards argv/options and maps exec result shape

## commands

### src/commands/agent-via-gateway.test.lisp
- agentCliCommand
- uses a timer-safe max gateway timeout when --timeout is 0
- uses gateway by default
- falls back to embedded agent when gateway fails
- skips gateway when --local is set

### src/commands/agent.acp.test.lisp
- agentCommand ACP runtime routing
- routes ACP sessions through AcpSessionManager instead of embedded agent
- suppresses ACP NO_REPLY lead fragments before emitting assistant text
- keeps silent-only ACP turns out of assistant output
- preserves repeated identical ACP delta chunks
- re-emits buffered NO prefix when ACP text becomes visible content
- fails closed for ACP-shaped session keys missing ACP metadata
- blocks ACP turns when ACP agent is disallowed by policy
- allows ACP turns for kimi when policy allowlists kimi

### src/commands/agent.delivery.test.lisp
- deliverAgentCommandResult
- prefers explicit accountId for outbound delivery
- falls back to session accountId for implicit delivery
- does not infer accountId for explicit delivery targets
- skips session accountId when channel differs
- uses session last channel when none is provided
- uses reply overrides for delivery routing
- uses runContext turn source over stale session last route
- does not reuse session lastTo when runContext source omits currentChannelId
- uses caller-provided outbound session context when opts.sessionKey is absent
- prefixes nested agent outputs with context

### src/commands/agent.test.lisp
- agentCommand
- sets runtime snapshots from source config before embedded agent run
- creates a session entry when deriving from --to
- persists thinking and verbose overrides
- requires explicit senderIsOwner for ingress runs
- honors explicit senderIsOwner for ingress runs
- resumes when session-id is provided
- uses the resumed session agent scope when sessionId resolves to another agent store
- forwards resolved outbound session context when resuming by sessionId
- resolves resumed session transcript path from custom session store directory
- does not duplicate agent events from embedded runs
- uses provider/model from agents.defaults.model.primary
- uses default fallback list for session model overrides
- keeps stored session model override when models allowlist is empty
- persists cleared model and auth override fields when stored override falls back to default
- keeps explicit sessionKey even when sessionId exists elsewhere
- persists resolved sessionFile for existing session keys
- preserves topic transcript suffix when persisting missing sessionFile
- derives session key from --agent when no routing target is provided
- clears stale Claude command-line interface legacy session IDs before retrying after session expiration
- rejects unknown agent overrides
- defaults thinking to low for reasoning-capable models
- defaults thinking to adaptive for Anthropic Claude 4.6 models
- prefers per-model thinking over global thinkingDefault
- prints JSON payload when requested
- passes the message through as the agent prompt
- passes through telegram accountId when delivering
- uses reply channel as the message channel context
- prefers runContext for embedded routing
- forwards accountId to embedded runs
- logs output when delivery is disabled

### src/commands/agent/session-store.test.lisp
- updateSessionStoreAfterAgentRun
- preserves ACP metadata when caller has a stale session snapshot
- persists latest systemPromptReport for downstream warning dedupe

### src/commands/agent/session.test.lisp
- resolveSessionKeyForRequest
- returns sessionKey when --to resolves a session key via context
- finds session by sessionId via reverse lookup in primary store
- finds session by sessionId in non-primary agent store
- returns correct sessionStore when session found in non-primary agent store
- returns undefined sessionKey when sessionId not found in any store
- does not search other stores when explicitSessionKey is set
- searches other stores when --to derives a key that does not match --session-id
- skips already-searched primary store when iterating agents

### src/commands/agents.add.test.lisp
- agents add command
- requires --workspace when flags are present
- requires --workspace in non-interactive mode
- exits with code 1 when the interactive wizard is cancelled

### src/commands/agents.bind.commands.test.lisp
- agents bind/unbind commands
- lists all bindings by default
- binds routes to default agent when --agent is omitted
- defaults matrix-js accountId to the target agent id when omitted
- upgrades existing channel-only binding when accountId is later provided
- unbinds all routes for an agent
- reports ownership conflicts during unbind and exits 1
- keeps role-based bindings when removing channel-level discord binding

### src/commands/agents.identity.test.lisp
- agents set-identity command
- sets identity from workspace IDENTITY.md
- errors when multiple agents match the same workspace
- overrides identity file values with explicit flags
- reads identity from an explicit IDENTITY.md path
- accepts avatar-only identity from IDENTITY.md
- accepts avatar-only updates via flags
- errors when identity data is missing

### src/commands/agents.test.lisp
- agents helpers
- buildAgentSummaries includes default + configured agents
- applyAgentConfig merges updates
- applyAgentBindings skips duplicates and reports conflicts
- applyAgentBindings upgrades channel-only binding to account-specific binding for same agent
- applyAgentBindings treats role-based bindings as distinct routes
- removeAgentBindings does not remove role-based bindings when removing channel-level routes
- pruneAgentConfig removes agent, bindings, and allowlist entries

### src/commands/auth-choice-options.test.lisp
- buildAuthChoiceOptions
- includes core and provider-specific auth choices
- builds cli help choices from the same catalog
- can include legacy aliases in cli help choices
- shows Chutes in grouped provider selection

### src/commands/auth-choice.apply-helpers.test.lisp
- normalizeTokenProviderInput
- trims and lowercases non-empty values
- maybeApplyApiKeyFromOption
- stores normalized token when provider matches
- matches provider with whitespace/case normalization
- skips when provider does not match
- ensureApiKeyFromEnvOrPrompt
- uses env credential when user confirms
- falls back to prompt when env is declined
- uses explicit inline env ref when secret-input-mode=ref selects existing env key
- fails ref mode without select when fallback env var is missing
- re-prompts after provider ref validation failure and succeeds with env ref
- never includes resolved env secret values in reference validation notes
- ensureApiKeyFromOptionEnvOrPrompt
- uses opts token and skips note/env/prompt
- falls back to env flow and shows note when opts provider does not match

### src/commands/auth-choice.apply.anthropic.test.lisp
- applyAuthChoiceAnthropic
- persists setup-token ref without plaintext token in auth-profiles store

### src/commands/auth-choice.apply.google-gemini-cli.test.lisp
- applyAuthChoiceGoogleGeminiCli
- returns null for unrelated authChoice
- shows caution and skips setup when user declines
- continues to plugin provider flow when user confirms

### src/commands/auth-choice.apply.huggingface.test.lisp
- applyAuthChoiceHuggingface
- returns null when authChoice is not huggingface-api-key
- prompts for key and model, then writes config and auth profile
- notes when selected Hugging Face model uses a locked router policy

### src/commands/auth-choice.apply.minimax.test.lisp
- applyAuthChoiceMiniMax
- returns null for unrelated authChoice
- uses minimax-api-lightning default model

### src/commands/auth-choice.apply.openai.test.lisp
- applyAuthChoiceOpenAI
- writes env-backed OpenAI key as plaintext by default
- writes env-backed OpenAI key as keyRef when secret-input-mode=ref
- writes explicit token input into openai auth profile

### src/commands/auth-choice.apply.volcengine-byteplus.test.lisp
- volcengine/byteplus auth choice
- stores explicit volcengine key when env is not used

### src/commands/auth-choice.moonshot.test.lisp
- applyAuthChoice (moonshot)
- keeps the .cn baseUrl when setDefaultModel is false
- sets the default model when setDefaultModel is true

### src/commands/auth-choice.test.lisp
- applyAuthChoice
- does not throw when openai-codex oauth fails
- stores openai-codex OAuth with email profile id
- prompts and writes provider API key for common providers
- handles Z.AI endpoint selection and detection paths
- maps apiKey tokenProvider aliases to provider flow
- uses opts token for Gemini and keeps global default model when setDefaultModel=false
- prompts for Venice API key and shows the Venice note when no token is provided
- uses existing env API keys for selected providers
- retries ref setup when provider preflight fails and can switch to env ref
- keeps existing default model for explicit provider keys when setDefaultModel=false
- sets default model when selecting github-copilot
- does not persist literal 'undefined' when API key prompts return undefined
- ignores legacy LiteLLM oauth profiles when selecting litellm-api-key
- configures cloudflare ai gateway via env key and explicit opts
- writes Chutes OAuth credentials when selecting chutes (remote/manual)
- writes portal OAuth credentials for plugin providers
- resolvePreferredProviderForAuthChoice
- maps known and unknown auth choices

### src/commands/channel-account-context.test.lisp
- resolveDefaultChannelAccountContext
- uses enabled/configured defaults when hooks are missing
- uses plugin enable/configure hooks

### src/commands/channels.add.test.lisp
- channelsAddCommand
- clears telegram update offsets when the token changes
- does not clear telegram update offsets when the token is unchanged

### src/commands/channels.adds-non-default-telegram-account.test.lisp
- channels command
- adds a non-default telegram account
- moves single-account telegram config into accounts.default when adding non-default
- seeds accounts.default for env-only single-account telegram config when adding non-default
- adds a default slack account with tokens
- deletes a non-default discord account
- adds a named WhatsApp account
- adds a second signal account with a distinct name
- disables a default provider account when remove has no delete flag
- includes external auth profiles in JSON output
- stores default account names in accounts when multiple accounts exist
- migrates base names when adding non-default accounts
- formats gateway channel status lines in registry order
- includes Telegram bot username from probe data
- surfaces Telegram group membership audit issues in channels status output
- surfaces WhatsApp auth/runtime hints when unlinked or disconnected
- cleans up telegram update offset when deleting a telegram account
- does not clean up offset when deleting a non-telegram channel
- does not clean up offset when disabling (not deleting) a telegram account

### src/commands/channels.config-only-status-output.test.lisp
- config-only channels status output
- shows configured-but-unavailable credentials distinctly from not configured
- prefers resolved config snapshots when command-local secret resolution succeeds
- does not resolve raw source config for extension channels without inspectAccount
- renders Slack HTTP signing-secret availability in config-only status

### src/commands/channels.surfaces-signal-runtime-errors-channels-status-output.test.lisp
- channels command
- surfaces Signal runtime errors in channels status output
- surfaces iMessage runtime errors in channels status output

### src/commands/channels/capabilities.test.lisp
- channelsCapabilitiesCommand
- prints Slack bot + user scopes when user token is configured
- prints Teams Graph permission hints when present

### src/commands/chutes-oauth.test.lisp
- loginChutes
- captures local redirect and exchanges code for tokens
- supports manual flow with pasted redirect URL
- does not reuse code_verifier as state
- rejects pasted redirect URLs missing state

### src/commands/cleanup-utils.test.lisp
- buildCleanupPlan
- resolves inside-state flags and workspace dirs
- applyAgentDefaultPrimaryModel
- does not mutate when already set
- normalizes legacy models
- cleanup path removals
- removes state and only linked paths outside state
- removes every workspace directory

### src/commands/configure.daemon.test.lisp
- maybeInstallDaemon
- does not serialize SecretRef token into service environment
- blocks install when token SecretRef is unresolved
- continues daemon install flow when service status probe throws
- rethrows install probe failures that are not the known non-fatal Linux systemd cases
- continues the WSL2 daemon install flow when service status probe reports systemd unavailability

### src/commands/configure.gateway-auth.prompt-auth-config.test.lisp
- promptAuthConfig
- keeps Kilo provider models while applying allowlist defaults
- does not mutate provider model catalogs when allowlist is set

### src/commands/configure.gateway-auth.test.lisp
- buildGatewayAuthConfig
- preserves allowTailscale when switching to token
- drops password when switching to token
- drops token when switching to password
- does not silently omit password when literal string is provided
- generates random token for missing, empty, and coerced-literal token inputs
- preserves SecretRef tokens when token mode is selected
- builds trusted-proxy config with all options
- builds trusted-proxy config with only userHeader
- preserves allowTailscale when switching to trusted-proxy
- throws error when trusted-proxy mode lacks trustedProxy config
- drops token and password when switching to trusted-proxy

### src/commands/configure.gateway.test.lisp
- promptGatewayConfig
- generates a token when the prompt returns undefined
- does not set password to literal 'undefined' when prompt returns undefined
- prompts for trusted-proxy configuration when trusted-proxy mode selected
- handles trusted-proxy with no optional fields
- forces tailscale off when trusted-proxy is selected
- adds Tailscale origin to controlUi.allowedOrigins when tailscale serve is enabled
- adds Tailscale origin to controlUi.allowedOrigins when tailscale funnel is enabled
- does not add Tailscale origin when getTailnetHostname fails
- does not duplicate Tailscale origin if already present
- formats IPv6 Tailscale fallback addresses as valid HTTPS origins
- stores gateway token as SecretRef when token source is ref

### src/commands/configure.wizard.test.lisp
- runConfigureWizard
- persists gateway.mode=local when only the run mode is selected
- exits with code 1 when configure wizard is cancelled

### src/commands/daemon-install-helpers.test.lisp
- resolveGatewayDevMode
- detects dev mode for src ts entrypoints
- buildGatewayInstallPlan
- uses provided nodePath and returns plan
- emits warnings when renderSystemNodeWarning returns one
- merges config env vars into the environment
- drops dangerous config env vars before service merge
- does not include empty config env values
- drops whitespace-only config env values
- keeps service env values over config env vars
- gatewayInstallErrorHint
- returns platform-specific hints

### src/commands/daemon-install-plan.shared.test.lisp
- resolveGatewayDevMode
- detects src ts entrypoints
- resolveDaemonInstallRuntimeInputs
- keeps explicit devMode and nodePath overrides

### src/commands/daemon-install-runtime-warning.test.lisp
- emitNodeRuntimeWarning
- skips lookup when runtime is not sbcl
- emits warning when system sbcl check returns one
- does not emit when warning helper returns null

### src/commands/dashboard.links.test.lisp
- dashboardCommand
- opens and copies the dashboard link by default
- prints SSH hint when browser cannot open
- respects --no-open and skips browser attempts
- prints non-tokenized URL with guidance when token SecretRef is unresolved
- keeps URL non-tokenized when token SecretRef is unresolved but env fallback exists
- resolves env-template gateway.auth.token before building dashboard URL

### src/commands/dashboard.test.lisp
- dashboardCommand bind selection
- preserves custom bind mode
- preserves tailnet bind mode

### src/commands/doctor-auth.deprecated-cli-profiles.test.lisp
- maybeRemoveDeprecatedCliAuthProfiles
- removes deprecated command-line interface auth profiles from store + config

### src/commands/doctor-auth.hints.test.lisp
- resolveUnusableProfileHint
- returns billing guidance for disabled billing profiles
- returns credential guidance for permanent auth disables
- falls back to cooldown guidance for non-billing disable reasons
- returns cooldown guidance for cooldown windows

### src/commands/doctor-bootstrap-size.test.lisp
- noteBootstrapFileSize
- emits a warning when bootstrap files are truncated
- stays silent when files are comfortably within limits

### src/commands/doctor-config-flow.include-warning.test.lisp
- doctor include warning
- surfaces include confinement hint for escaped include paths

### src/commands/doctor-config-flow.missing-default-account-bindings.integration.test.lisp
- doctor missing default account binding warning
- emits a doctor warning when named accounts have no valid account-scoped bindings
- emits a warning when multiple accounts have no explicit default
- emits a warning when defaultAccount does not match configured accounts

### src/commands/doctor-config-flow.missing-default-account-bindings.test.lisp
- collectMissingDefaultAccountBindingWarnings
- warns when named accounts exist without default and no valid binding exists
- does not warn when an explicit account binding exists
- warns when bindings cover only a subset of configured accounts
- does not warn when wildcard account binding exists
- does not warn when default account is present

### src/commands/doctor-config-flow.missing-explicit-default-account.test.lisp
- collectMissingExplicitDefaultAccountWarnings
- warns when multiple named accounts are configured without default selection
- does not warn for a single named account without default
- does not warn when accounts.default exists
- does not warn when defaultAccount points to a configured account
- normalizes defaultAccount before validating configured account ids
- warns when defaultAccount is invalid for configured accounts
- warns across channels that support account maps

### src/commands/doctor-config-flow.safe-bins.test.lisp
- doctor config flow safe bins
- scaffolds missing custom safe-bin profiles on repair but skips interpreter bins
- warns when interpreter/custom safeBins entries are missing profiles in non-repair mode
- hints safeBinTrustedDirs when safeBins resolve outside default trusted dirs

### src/commands/doctor-config-flow.test.lisp
- doctor config flow
- preserves invalid config for doctor repairs
- does not warn on mutable account allowlists when dangerous name matching is inherited
- does not warn about sender-based group allowlist for googlechat
- warns when imessage group allowlist is empty even if allowFrom is set
- drops unknown keys on repair
- preserves discord streaming intent while stripping unsupported keys on repair
- resolves Telegram @username allowFrom entries to numeric IDs on repair
- does not crash when Telegram allowFrom repair sees unavailable SecretRef-backed credentials
- converts numeric discord ids to strings on repair
- does not restore top-level allowFrom when config is intentionally default-account scoped
- adds allowFrom ["*"] when dmPolicy="open" and allowFrom is missing on repair
- adds * to existing allowFrom array when dmPolicy is open on repair
- repairs nested dm.allowFrom when top-level allowFrom is absent on repair
- skips repair when allowFrom already includes *
- repairs per-account dmPolicy open without allowFrom on repair
- repairs dmPolicy="allowlist" by restoring allowFrom from pairing store on repair
- migrates legacy toolsBySender keys to typed id entries on repair
- repairs googlechat dm.policy open by setting dm.allowFrom on repair
- migrates top-level heartbeat into agents.defaults.heartbeat on repair
- migrates top-level heartbeat visibility into channels.defaults.heartbeat on repair
- repairs googlechat account dm.policy open by setting dm.allowFrom on repair
- recovers from stale googlechat top-level allowFrom by repairing dm.allowFrom

### src/commands/doctor-gateway-auth-token.test.lisp
- resolveGatewayAuthTokenForService
- returns plaintext gateway.auth.token when configured
- resolves SecretRef-backed gateway.auth.token
- resolves env-template gateway.auth.token via SecretRef resolution
- falls back to OPENCLAW_GATEWAY_TOKEN when SecretRef is unresolved
- falls back to OPENCLAW_GATEWAY_TOKEN when SecretRef resolves to empty
- returns unavailableReason when SecretRef is unresolved without env fallback
- shouldRequireGatewayTokenForInstall
- requires token when auth mode is token
- does not require token when auth mode is password
- requires token in inferred mode when password env exists only in shell
- does not require token in inferred mode when password is configured
- does not require token in inferred mode when password env is configured in config
- requires token in inferred mode when no password candidate exists

### src/commands/doctor-gateway-services.test.lisp
- maybeRepairGatewayServiceConfig
- treats gateway.auth.token as source of truth for service token repairs
- uses OPENCLAW_GATEWAY_TOKEN when config token is missing
- treats SecretRef-managed gateway token as non-persisted service state
- falls back to embedded service token when config and env tokens are missing
- does not persist EnvironmentFile-backed service tokens into config
- maybeScanExtraGatewayServices
- removes legacy Linux user systemd services

### src/commands/doctor-legacy-config.migrations.test.lisp
- normalizeCompatibilityConfigValues
- does not add whatsapp config when missing and no auth exists
- copies legacy ack reaction when whatsapp config exists
- does not add whatsapp config when only auth exists (issue #900)
- does not add whatsapp config when only legacy auth exists (issue #900)
- does not add whatsapp config when only non-default auth exists (issue #900)
- copies legacy ack reaction when authDir override exists
- migrates Slack dm.policy/dm.allowFrom to dmPolicy/allowFrom aliases
- migrates Discord account dm.policy/dm.allowFrom to dmPolicy/allowFrom aliases
- migrates Discord streaming boolean alias to streaming enum
- migrates Discord legacy streamMode into streaming enum
- migrates Telegram streamMode into streaming enum
- migrates Slack legacy streaming keys to unified config
- moves missing default account from single-account top-level config when named accounts already exist
- migrates browser ssrfPolicy allowPrivateNetwork to dangerouslyAllowPrivateNetwork
- normalizes conflicting browser SSRF alias keys without changing effective behavior

### src/commands/doctor-legacy-config.test.lisp
- normalizeCompatibilityConfigValues preview streaming aliases
- normalizes telegram boolean streaming aliases to enum
- normalizes discord boolean streaming aliases to enum
- normalizes slack boolean streaming aliases to enum and native streaming

### src/commands/doctor-memory-search.test.lisp
- noteMemorySearchHealth
- does not warn when local provider is set with no explicit modelPath (default model fallback)
- warns when local provider with default model but gateway probe reports not ready
- does not warn when local provider with default model and gateway probe is ready
- does not warn when local provider has an explicit hf: modelPath
- does not warn when QMD backend is active
- does not warn when remote apiKey is configured for explicit provider
- treats SecretRef remote apiKey as configured for explicit provider
- does not warn in auto mode when remote apiKey is configured
- treats SecretRef remote apiKey as configured in auto mode
- resolves provider auth from the default agent directory
- resolves mistral auth for explicit mistral embedding provider
- notes when gateway probe reports embeddings ready and command-line interface API key is missing
- uses model configure hint when gateway probe is unavailable and API key is missing
- warns in auto mode when no local modelPath and no API keys are configured
- still warns in auto mode when only ollama credentials exist
- detectLegacyWorkspaceDirs
- returns active workspace and no legacy dirs

### src/commands/doctor-platform-notes.launchctl-env-overrides.test.lisp
- noteMacLaunchctlGatewayEnvOverrides
- prints clear unsetenv instructions for token override
- does nothing when config has no gateway credentials
- treats SecretRef-backed credentials as configured
- does nothing on non-darwin platforms

### src/commands/doctor-platform-notes.startup-optimization.test.lisp
- noteStartupOptimizationHints
- does not warn when compile cache and no-respawn are configured
- warns when compile cache is under /tmp and no-respawn is not set
- warns when compile cache is disabled via env override
- skips startup optimization note on win32
- skips startup optimization note on non-target linux hosts

### src/commands/doctor-sandbox.warns-sandbox-enabled-without-docker.test.lisp
- maybeRepairSandboxImages
- warns when sandbox mode is enabled but Docker (driven from Common Lisp) is not available
- warns when sandbox mode is 'all' but Docker (driven from Common Lisp) is not available
- does not warn when sandbox mode is off
- does not warn when Docker (driven from Common Lisp) is available

### src/commands/doctor-security.test.lisp
- noteSecurityWarnings gateway exposure
- warns when exposed without auth
- uses env token to avoid critical warning
- treats SecretRef token config as authenticated for exposure warning level
- treats whitespace token as missing
- skips warning for loopback bind
- shows explicit dmScope config command for multi-user DMs
- clarifies approvals.exec forwarding-only behavior
- warns when heartbeat delivery relies on implicit directPolicy defaults
- warns when a per-agent heartbeat relies on implicit directPolicy
- skips heartbeat directPolicy warning when delivery is internal-only or explicit

### src/commands/doctor-session-locks.test.lisp
- noteSessionLockHealth
- reports existing lock files with pid status and age
- removes stale locks in repair mode

### src/commands/doctor-state-integrity.cloud-storage.test.lisp
- detectMacCloudSyncedStateDir
- detects state dir under iCloud Drive
- detects state dir under Library/CloudStorage
- detects cloud-synced target when state dir resolves via symlink
- ignores cloud-synced symlink prefix when resolved target is local
- anchors cloud detection to OS homedir when OPENCLAW_HOME is overridden
- returns null outside darwin

### src/commands/doctor-state-integrity.linux-storage.test.lisp
- detectLinuxSdBackedStateDir
- detects state dir on mmc-backed mount
- returns null for non-mmc devices
- resolves /dev/disk aliases to mmc devices
- uses resolved state path to select mount
- returns null outside linux
- escapes decoded mountinfo control characters in warning output

### src/commands/doctor-state-integrity.test.lisp
- doctor state integrity oauth dir checks
- does not prompt for oauth dir when no whatsapp/pairing config is active
- prompts for oauth dir when whatsapp is configured
- prompts for oauth dir when a channel dmPolicy is pairing
- prompts for oauth dir when OPENCLAW_OAUTH_DIR is explicitly configured
- detects orphan transcripts and offers archival remediation
- prints openclaw-only verification hints when recent sessions are missing transcripts
- ignores slash-routing sessions for recent missing transcript warnings

### src/commands/doctor-state-migrations.test.lisp
- doctor legacy state migrations
- migrates legacy sessions into agents/<id>/sessions
- migrates legacy agent dir with conflict fallback
- auto-migrates legacy agent dir on startup
- auto-migrates legacy sessions on startup
- migrates legacy WhatsApp auth files without touching oauth.json
- migrates legacy Telegram pairing allowFrom store to account-scoped default file
- fans out legacy Telegram pairing allowFrom store to configured named accounts
- no-ops when nothing detected
- routes legacy state to the default agent entry
- honors session.mainKey when seeding the direct-chat bucket
- canonicalizes legacy main keys inside the target sessions store
- prefers the newest entry when collapsing main aliases
- lowercases agent session keys during canonicalization
- auto-migrates when only target sessions contain legacy keys
- does nothing when no legacy state dir exists
- skips state dir migration when env override is set
- does not warn when legacy state dir is an already-migrated symlink mirror
- warns when legacy state dir is empty and target already exists
- warns when legacy state dir contains non-symlink entries and target already exists
- does not warn when legacy state dir contains nested symlink mirrors
- warns when legacy state dir symlink points outside the target tree
- warns when legacy state dir contains a broken symlink target
- warns when legacy symlink escapes target tree through second-hop symlink

### src/commands/doctor.migrates-routing-allowfrom-channels-whatsapp-allowfrom.test.lisp
- doctor command
- does not add a new gateway auth token while fixing legacy issues on invalid config
- skips legacy gateway services migration
- offers to update first for git checkouts

### src/commands/doctor.migrates-slack-discord-dm-policy-aliases.test.lisp
- doctor command
- migrates Slack/Discord dm.policy keys to dmPolicy aliases

### src/commands/doctor.runs-legacy-state-migrations-yes-mode-without.e2e.test.lisp
- doctor command
- runs legacy state migrations in yes mode without prompting
- runs legacy state migrations in non-interactive mode without prompting
- skips gateway restarts in non-interactive mode
- migrates anthropic oauth config profile id when only email profile exists

### src/commands/doctor.warns-per-agent-sandbox-docker-browser-prune.e2e.test.lisp
- doctor command
- warns when per-agent sandbox docker/browser/prune overrides are ignored under shared scope
- does not warn when only the active workspace is present

### src/commands/doctor.warns-state-directory-is-missing.e2e.test.lisp
- doctor command
- warns when the state directory is missing
- warns about opencode provider overrides
- skips gateway auth warning when OPENCLAW_GATEWAY_TOKEN is set
- warns when token and password are both configured and gateway.auth.mode is unset

### src/commands/gateway-install-token.test.lisp
- resolveGatewayInstallToken
- uses plaintext gateway.auth.token when configured
- validates SecretRef token but does not persist resolved plaintext
- returns unavailable reason when token SecretRef is unresolved in token mode
- returns unavailable reason when token and password are both configured and mode is unset
- auto-generates token when no source exists and auto-generation is enabled
- persists auto-generated token when requested
- drops generated plaintext when config changes to SecretRef before persist
- does not auto-generate when inferred mode has password SecretRef configured
- skips token SecretRef resolution when token auth is not required

### src/commands/gateway-status.test.lisp
- gateway-status command
- prints human output by default
- prints a structured JSON envelope when --json is set
- surfaces unresolved SecretRef auth diagnostics in warnings
- does not resolve local token SecretRef when OPENCLAW_GATEWAY_TOKEN is set
- does not resolve local password SecretRef in token mode
- resolves env-template gateway.auth.token before probing targets
- emits stable SecretRef auth configuration booleans in --json output
- supports SSH tunnel targets
- skips invalid ssh-auto discovery targets
- infers SSH target from gateway.remote.url and ssh config
- falls back to host-only when USER is missing and ssh config is unavailable
- keeps explicit SSH identity even when ssh config provides one

### src/commands/gateway-status/helpers.test.lisp
- extractConfigSummary
- marks SecretRef-backed gateway auth credentials as configured
- still treats empty plaintext auth values as not configured
- resolveAuthForTarget
- resolves local auth token SecretRef before probing local targets
- resolves remote auth token SecretRef before probing remote targets
- resolves remote auth even when local auth mode is none
- does not force remote auth type from local auth mode
- redacts resolver internals from unresolved SecretRef diagnostics

### src/commands/health.command.coverage.test.lisp
- healthCommand (coverage)
- prints the rich text summary when linked and configured

### src/commands/health.snapshot.test.lisp
- getHealthSnapshot
- skips telegram probe when not configured
- probes telegram getMe + webhook info when configured
- treats telegram.tokenFile as configured
- returns a structured telegram probe error when getMe fails
- captures unexpected probe exceptions as errors
- disables heartbeat for agents without heartbeat blocks

### src/commands/health.test.lisp
- healthCommand
- outputs JSON from gateway
- prints text summary when not json
- formats per-account probe timings
- formatHealthCheckFailure
- keeps non-rich output stable
- formats gateway connection details as indented key/value lines

### src/commands/message.test.lisp
- messageCommand
- threads resolved SecretRef config into outbound send actions
- threads resolved SecretRef config into outbound adapter sends
- keeps local-fallback resolved cfg in outbound adapter sends
- defaults channel when only one configured
- requires channel when multiple configured
- sends via gateway for WhatsApp
- routes discord polls through message action
- routes telegram polls through message action

### src/commands/model-picker.test.lisp
- promptDefaultModel
- supports configuring vLLM during onboarding
- promptModelAllowlist
- filters to allowed keys when provided
- router model filtering
- filters internal router models in both default and allowlist prompts
- applyModelAllowlist
- preserves existing entries for selected models
- clears the allowlist when no models remain
- applyModelFallbacksFromSelection
- sets fallbacks from selection when the primary is included
- keeps existing fallbacks when the primary is not selected

### src/commands/models.auth.provider-resolution.test.lisp
- resolveRequestedLoginProviderOrThrow
- returns null and resolves provider by id/alias
- throws when requested provider is not loaded

### src/commands/models.list.auth-sync.test.lisp
- models list auth-profile sync
- marks models available when auth exists only in auth-profiles.json
- does not persist blank auth-profile credentials

### src/commands/models.list.e2e.test.lisp
- models list/status
- models list runs model discovery without auth.json sync
- models list outputs canonical zai key for configured z.ai model
- models list plain outputs canonical zai key
- models list marks auth as unavailable when ZAI key is missing
- models list does not treat availability-unavailable code as discovery fallback
- models list fails fast when registry model discovery is unavailable
- loadModelRegistry throws when model discovery is unavailable
- loadModelRegistry persists using source config snapshot when provided
- loadModelRegistry uses resolved config when no source snapshot is provided
- toModelRow does not crash without cfg/authStore when availability is undefined

### src/commands/models.set.e2e.test.lisp
- models set + fallbacks
- normalizes z.ai provider in models set
- normalizes z-ai provider in models fallbacks add
- preserves primary when adding fallbacks to string defaults.model
- normalizes provider casing in models set
- rewrites string defaults.model to object form when setting primary

### src/commands/models/auth.test.lisp
- modelsAuthLoginCommand
- supports built-in openai-codex login without provider plugins
- applies openai-codex default model when --set-default is used
- keeps existing plugin error behavior for non built-in providers
- does not persist a cancelled manual token entry

### src/commands/models/list.auth-overview.test.lisp
- resolveProviderAuthOverview
- does not throw when token profile only has tokenRef
- renders marker-backed models.json auth as marker detail
- keeps env-var-shaped models.json values masked to avoid accidental plaintext exposure

### src/commands/models/list.list-command.forward-compat.test.lisp
- modelsListCommand forward-compat
- does not mark configured codex model as missing when forward-compat can build a fallback
- passes source config to model registry loading for persistence safety
- keeps configured local openai gpt-5.4 entries visible in --local output
- marks synthetic codex gpt-5.4 rows as available when provider auth exists
- exits with an error when configured-mode listing has no model registry

### src/commands/models/list.probe.targets.test.lisp
- buildProbeTargets reason codes
- reports invalid_expires with a legacy-compatible first error line
- reports excluded_by_auth_order when profile id is not present in explicit order
- reports unresolved_ref when a ref-only profile cannot resolve its SecretRef
- skips marker-only models.json credentials when building probe targets
- does not treat arbitrary all-caps models.json apiKey values as markers

### src/commands/models/list.probe.test.lisp
- mapFailoverReasonToProbeStatus
- maps auth_permanent to auth
- keeps existing failover reason mappings
- falls back to unknown for unrecognized values

### src/commands/models/list.status.test.lisp
- modelsStatusCommand auth overview
- includes masked auth sources in JSON output
- does not emit raw short api-key values in JSON labels
- uses agent overrides and reports sources
- labels defaults when --agent has no overrides
- reports defaults source in JSON when --agent has no overrides
- throws when agent id is unknown
- exits non-zero when auth is missing

### src/commands/models/load-config.test.lisp
- models load-config
- returns source+resolved configs and sets runtime snapshot
- loadModelsConfig returns resolved config while preserving runtime snapshot behavior

### src/commands/models/shared.test.lisp
- models/shared
- returns config when snapshot is valid
- throws formatted issues when snapshot is invalid
- updateConfig writes mutated config

### src/commands/oauth-tls-preflight.doctor.test.lisp
- noteOpenAIOAuthTlsPrerequisites
- emits OAuth TLS prerequisite guidance when cert chain validation fails
- stays quiet when preflight succeeds
- skips probe when OpenAI Codex OAuth is not configured
- runs probe in deep mode even without OpenAI Codex OAuth profile

### src/commands/oauth-tls-preflight.test.lisp
- runOpenAIOAuthTlsPreflight
- returns ok when OpenAI auth endpoint is reachable
- classifies TLS trust failures from fetch cause code
- keeps generic TLS transport failures in network classification
- formatOpenAIOAuthTlsPreflightFix
- includes remediation commands for TLS failures

### src/commands/onboard-auth.config-core.kilocode.test.lisp
- Kilo Gateway provider config
- constants
- KILOCODE_BASE_URL points to kilo openrouter endpoint
- KILOCODE_DEFAULT_MODEL_REF includes provider prefix
- KILOCODE_DEFAULT_MODEL_ID is kilo/auto
- buildKilocodeModelDefinition
- returns correct model shape
- applyKilocodeProviderConfig
- registers kilocode provider with correct baseUrl and api
- includes the default model in the provider model list
- surfaces the full Kilo model catalog
- appends missing catalog models to existing Kilo provider config
- sets Kilo Gateway alias in agent default models
- preserves existing alias if already set
- does not change the default model selection
- applyKilocodeConfig
- sets kilocode as the default model
- also registers the provider
- env var resolution
- resolves KILOCODE_API_KEY from env
- returns null when KILOCODE_API_KEY is not set
- resolves the kilocode api key via resolveApiKeyForProvider

### src/commands/onboard-auth.config-shared.test.lisp
- onboard auth provider config merges
- appends missing default models to existing provider models
- merges model catalogs without duplicating existing model ids
- supports single default model convenience wrapper

### src/commands/onboard-auth.credentials.test.lisp
- onboard auth credentials secret refs
- keeps env-backed moonshot key as plaintext by default
- stores env-backed moonshot key as keyRef when secret-input-mode=ref
- stores ${ENV} moonshot input as keyRef even when env value is unset
- keeps plaintext moonshot key when no env ref applies
- preserves cloudflare metadata when storing keyRef
- keeps env-backed openai key as plaintext by default
- stores env-backed openai key as keyRef in ref mode
- stores env-backed volcengine and byteplus keys as keyRef in ref mode

### src/commands/onboard-auth.test.lisp
- writeOAuthCredentials
- writes auth-profiles.json under OPENCLAW_AGENT_DIR when set
- writes OAuth credentials to all sibling agent dirs when syncSiblingAgents=true
- writes OAuth credentials only to target dir by default
- syncs siblings from explicit agentDir outside OPENCLAW_STATE_DIR
- setMinimaxApiKey
- writes to OPENCLAW_AGENT_DIR when set
- applyAuthProfileConfig
- promotes the newly selected profile to the front of auth.order
- creates provider order when switching from legacy oauth to api_key without explicit order
- keeps implicit round-robin when no mixed provider modes are present
- applyMinimaxApiConfig
- adds minimax provider with correct settings
- keeps reasoning enabled for MiniMax-M2.5
- preserves existing model params when adding alias
- merges existing minimax provider models
- preserves other providers when adding minimax
- preserves existing models mode
- provider config helpers
- does not overwrite existing primary model
- applyZaiConfig
- adds zai provider with correct settings
- supports CN endpoint for supported coding models
- applySyntheticConfig
- adds synthetic provider with correct settings
- merges existing synthetic provider models
- primary model defaults
- sets correct primary model
- applyXiaomiConfig
- adds Xiaomi provider with correct settings
- merges Xiaomi models and keeps existing provider overrides
- applyXaiConfig
- adds xAI provider with correct settings
- applyXaiProviderConfig
- merges xAI models and keeps existing provider overrides
- applyMistralConfig
- adds Mistral provider with correct settings
- applyMistralProviderConfig
- merges Mistral models and keeps existing provider overrides
- fallback preservation helpers
- preserves existing model fallbacks
- provider alias defaults
- adds expected alias for provider defaults
- allowlist provider helpers
- adds allowlist entry and preserves alias
- applyLitellmProviderConfig
- preserves existing baseUrl and api key while adding the default model
- default-model config helpers
- sets primary model and preserves existing model fallbacks

### src/commands/onboard-channels.e2e.test.lisp
- setupChannels
- QuickStart uses single-select (no multiselect) and doesn't prompt for Telegram token when WhatsApp is chosen
- continues Telegram onboarding even when plugin registry is empty (avoids 'plugin not available' block)
- shows explicit dmScope config command in channel primer
- prompts for configured channel action and skips configuration when told to skip
- adds disabled hint to channel selection when a channel is disabled
- uses configureInteractive skip without mutating selection/account state
- applies configureInteractive result cfg/account updates
- uses configureWhenConfigured when channel is already configured
- respects configureWhenConfigured skip without mutating selection or account state
- prefers configureInteractive over configureWhenConfigured when both hooks exist

### src/commands/onboard-config.test.lisp
- applyOnboardingLocalWorkspaceConfig
- defaults local onboarding tool profile to coding
- sets secure dmScope default when unset
- preserves existing dmScope when already configured
- preserves explicit non-main dmScope values
- preserves an explicit tools.profile when already configured

### src/commands/onboard-custom.test.lisp
- promptCustomApiConfig
- handles openai flow and saves alias
- retries when verification fails
- detects openai compatibility when unknown
- uses expanded max_tokens for openai verification probes
- uses azure-specific headers and body for openai verification probes
- uses expanded max_tokens for anthropic verification probes
- re-prompts base url when unknown detection fails
- renames provider id when baseUrl differs
- aborts verification after timeout
- stores env SecretRef for custom provider when selected
- re-prompts source after provider ref preflight fails and succeeds with env ref
- applyCustomApiConfig
- parseNonInteractiveCustomApiFlags
- parses required flags and defaults compatibility to openai

### src/commands/onboard-helpers.test.lisp
- openUrl
- quotes URLs on win32 so '&' is not treated as cmd separator
- resolveBrowserOpenCommand
- marks win32 commands as quoteUrl=true
- resolveControlUiLinks
- uses customBindHost for custom bind
- falls back to loopback for invalid customBindHost
- uses tailnet IP for tailnet bind
- keeps loopback for auto even when tailnet is present
- normalizeGatewayTokenInput
- returns empty string for undefined or null
- trims string input
- returns empty string for non-string input
- rejects literal string coercion artifacts ("undefined"/"null")
- validateGatewayPasswordInput
- requires a non-empty password
- rejects literal string coercion artifacts
- accepts a normal password

### src/commands/onboard-hooks.test.lisp
- onboard-hooks
- setupInternalHooks
- should enable hooks when user selects them
- should not enable hooks when user skips
- should handle no eligible hooks
- should preserve existing hooks config when enabled
- should preserve existing config when user skips
- should show informative notes to user

### src/commands/onboard-interactive.test.lisp
- runInteractiveOnboarding
- restores terminal state without resuming stdin on success
- restores terminal state without resuming stdin on cancel
- rethrows non-cancel errors after restoring terminal state

### src/commands/onboard-non-interactive.gateway.test.lisp
- onboard (non-interactive): gateway and remote auth
- writes gateway token auth into config
- uses OPENCLAW_GATEWAY_TOKEN when --gateway-token is omitted
- writes gateway token SecretRef from --gateway-token-ref-env
- fails when --gateway-token-ref-env points to a missing env var
- writes gateway.remote url/token and callGateway uses them
- auto-generates token auth when binding LAN and persists the token

### src/commands/onboard-non-interactive.provider-auth.test.lisp
- onboard (non-interactive): provider auth
- stores MiniMax API key and uses global baseUrl by default
- supports MiniMax CN API endpoint auth choice
- stores Z.AI API key and uses global baseUrl by default
- supports Z.AI CN coding endpoint auth choice
- stores xAI API key and sets default model
- infers Mistral auth choice from --mistral-api-key and sets default model
- stores Volcano Engine API key and sets default model
- infers BytePlus auth choice from --byteplus-api-key and sets default model
- stores Vercel AI Gateway API key and sets default model
- stores token auth profile
- stores OpenAI API key and sets OpenAI default model
- stores the detected env alias as keyRef for opencode ref mode
- rejects vLLM auth choice in non-interactive mode
- stores LiteLLM API key and sets default model
- infers Together auth choice from --together-api-key and sets default model
- infers QIANFAN auth choice from --qianfan-api-key and sets default model
- configures a custom provider from non-interactive flags
- infers custom provider auth choice from custom flags
- uses CUSTOM_API_KEY env fallback for non-interactive custom provider auth
- stores CUSTOM_API_KEY env ref for non-interactive custom provider auth in ref mode
- fails fast for custom provider ref mode when --custom-api-key is set but CUSTOM_API_KEY env is missing
- uses matching profile fallback for non-interactive custom provider auth
- fails custom provider auth when compatibility is invalid
- fails custom provider auth when explicit provider id is invalid
- fails inferred custom auth when required flags are incomplete

### src/commands/onboard-non-interactive/local/daemon-install.test.lisp
- installGatewayDaemonNonInteractive
- does not pass plaintext token for SecretRef-managed install
- aborts with actionable error when SecretRef is unresolved

### src/commands/onboard-remote.test.lisp
- promptRemoteGatewayConfig
- defaults discovered direct remote URLs to wss://
- validates insecure ws:// remote URLs and allows only loopback ws:// by default
- allows ws:// hostname remote URLs when OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1
- supports storing remote auth as an external env secret ref

### src/commands/onboard-search.test.lisp
- setupSearch
- returns config unchanged when user skips
- sets provider and key for perplexity
- sets provider and key for brave
- sets provider and key for gemini
- sets provider and key for grok
- sets provider and key for kimi
- shows missing-key note when no key is provided and no env var
- keeps existing key when user leaves input blank
- advanced preserves enabled:false when keeping existing key
- quickstart skips key prompt when config key exists
- quickstart preserves enabled:false when search was intentionally disabled
- quickstart falls through to key prompt when no key and no env var
- quickstart skips key prompt when env var is available
- stores env-backed SecretRef when secretInputMode=ref for perplexity
- stores env-backed SecretRef when secretInputMode=ref for brave
- stores plaintext key when secretInputMode is unset
- exports all 5 providers in SEARCH_PROVIDER_OPTIONS

### src/commands/onboard-skills.test.lisp
- setupSkills
- does not recommend Homebrew when user skips installing brew-backed deps
- recommends Homebrew when user selects a brew-backed install and brew is missing

### src/commands/onboard.test.lisp
- onboardCommand
- fails fast for invalid secret-input-mode before onboarding starts
- defaults --reset to config+creds+sessions scope
- uses configured default workspace for --reset when --workspace is not provided
- accepts explicit --reset-scope full
- fails fast for invalid --reset-scope

### src/commands/onboarding/plugin-install.test.lisp
- ensureOnboardingPluginInstalled
- installs from Quicklisp/Ultralisp and enables the plugin
- uses local path when selected
- defaults to local on dev channel when local path exists
- defaults to Quicklisp/Ultralisp on beta channel even when local path exists
- falls back to local path after Quicklisp/Ultralisp install failure

### src/commands/openai-codex-oauth.test.lisp
- loginOpenAICodexOAuth
- returns credentials on successful oauth login
- passes through Pi-provided OAuth authorize URL without mutation
- reports oauth errors and rethrows
- continues OAuth flow on non-certificate preflight failures
- fails early with actionable message when TLS preflight fails

### src/commands/openai-model-default.test.lisp
- applyDefaultModelChoice
- ensures allowlist entry exists when returning an agent override
- adds canonical allowlist key for anthropic aliases
- uses applyDefaultConfig path when setDefaultModel is true
- shared default model behavior
- sets defaults when model is unset
- overrides existing models
- no-ops when already on the target default
- applyOpenAIProviderConfig
- adds allowlist entry for default model
- preserves existing alias for default model
- applyOpenAIConfig
- sets default when model is unset
- overrides model.primary when model object already exists
- applyOpenAICodexModelDefault
- sets openai-codex default when model is unset
- sets openai-codex default when model is openai/*
- does not override openai-codex/*
- does not override non-openai models
- applyOpencodeZenModelDefault
- no-ops when already legacy opencode-zen default
- preserves fallbacks when setting primary

### src/commands/sandbox-explain.test.lisp
- sandbox explain command
- prints JSON shape + fix-it keys

### src/commands/sandbox-formatters.test.lisp
- sandbox-formatters
- formatStatus
- formatSimpleStatus
- formatImageMatch
- formatAge
- countRunning
- countMismatches
- counter empty inputs

### src/commands/sandbox.test.lisp
- sandboxListCommand
- human format output
- should display containers
- should display browsers when --browser flag is set
- should show warning when image mismatches detected
- should display message when no containers found
- JSON output
- should output JSON format
- error handling
- should handle errors gracefully
- sandboxRecreateCommand
- validation
- should error if no filter is specified
- should error if multiple filters specified
- filtering
- should filter by session
- should filter by agent (exact + subkeys)
- should remove all when --all flag set
- should handle browsers when --browser flag set
- confirmation flow
- should require confirmation without --force
- should cancel when user declines
- should cancel on clack cancel symbol
- should skip confirmation with --force
- execution
- should show message when no containers match
- should handle removal errors and exit with code 1
- should display success message

### src/commands/session-store-targets.test.lisp
- resolveSessionStoreTargets
- resolves the default agent store when no selector is provided
- resolves all configured agent stores
- dedupes shared store paths for --all-agents
- rejects unknown agent ids
- rejects conflicting selectors

### src/commands/sessions-cleanup.test.lisp
- sessionsCleanupCommand
- emits a single JSON object for non-dry runs and applies maintenance
- returns dry-run JSON without mutating the store
- counts missing transcript entries when --fix-missing is enabled in dry-run
- renders a dry-run action table with keep/prune actions
- returns grouped JSON for --all-agents dry-runs

### src/commands/sessions.default-agent-store.test.lisp
- sessionsCommand default store agent selection
- includes agentId on sessions rows for --all-agents JSON output
- avoids duplicate rows when --all-agents resolves to a shared store path
- uses configured default agent id when resolving implicit session store path
- uses all configured agent stores with --all-agents

### src/commands/sessions.model-resolution.test.lisp
- sessionsCommand model resolution
- prefers runtime model fields for subagent sessions in JSON output
- falls back to modelOverride when runtime model is missing

### src/commands/sessions.test.lisp
- sessionsCommand
- renders a tabular view with token percentages
- shows placeholder rows when tokens are missing
- exports freshness metadata in JSON output
- applies --active filtering in JSON output
- rejects invalid --active values

### src/commands/signal-install.test.lisp
- looksLikeArchive
- recognises .tar.gz
- recognises .tgz
- recognises .zip
- rejects signature files
- rejects unrelated files
- pickAsset
- linux
- selects the Linux-native asset on x64
- returns undefined on arm64 (triggers brew fallback)
- returns undefined on arm (32-bit)
- darwin
- selects the macOS-native asset
- selects the macOS-native asset on x64
- win32
- selects the Windows-native asset
- edge cases
- returns undefined for an empty asset list
- skips assets with missing name or url
- falls back to first archive for unknown platform
- never selects .asc signature files
- extractSignalCliArchive
- rejects zip slip path traversal
- extracts zip archives
- extracts tar.gz archives

### src/commands/status-all/channels.mattermost-token-summary.test.lisp
- buildChannelsTable - mattermost token summary
- does not require appToken for mattermost accounts
- keeps bot+app requirement when both fields exist
- reports configured-but-unavailable Slack credentials as warn
- preserves unavailable credential state from the source config snapshot
- treats status-only available credentials as resolved
- treats Slack HTTP signing-secret availability as required config
- still reports single-token channels as ok

### src/commands/status-all/report-lines.test.lisp
- buildStatusAllReportLines
- renders bootstrap column using file-presence semantics

### src/commands/status.scan.test.lisp
- scanStatus
- passes sourceConfig into buildChannelsTable for summary-mode status output

### src/commands/status.service-summary.test.lisp
- readServiceStatusSummary
- marks OpenClaw-managed services as installed
- marks running unmanaged services as externally managed
- keeps missing services as not installed when nothing is running

### src/commands/status.summary.redaction.test.lisp
- redactSensitiveStatusSummary
- removes sensitive session and path details while preserving summary structure

### src/commands/status.test.lisp
- statusCommand
- prints JSON when requested
- surfaces unknown usage when totalTokens is missing
- prints unknown usage in formatted output when totalTokens is missing
- prints formatted lines otherwise
- shows gateway auth when reachable
- warns instead of crashing when gateway auth SecretRef is unresolved for probe auth
- surfaces channel runtime errors from the gateway
- extracts requestId from close reason when error text omits it
- includes sessions across agents in JSON output

### src/commands/status.update.test.lisp
- resolveUpdateAvailability
- flags git update when behind upstream
- flags registry update when latest version is newer
- formatUpdateOneLiner
- renders git status and registry latest summary
- renders package-manager mode with registry error
- formatUpdateAvailableHint
- returns null when no update is available
- renders git and registry update details

### src/commands/text-format.test.lisp
- shortenText
- returns original text when it fits
- truncates and appends ellipsis when over limit
- counts multi-byte characters correctly

### src/commands/zai-endpoint-detect.test.lisp
- detectZaiEndpoint
- resolves preferred/fallback endpoints and null when probes fail

## config

### src/config/agent-dirs.test.lisp
- resolveEffectiveAgentDir via findDuplicateAgentDirs
- uses OPENCLAW_HOME for default agent dir resolution
- resolves agent dir under OPENCLAW_HOME state dir

### src/config/allowed-values.test.lisp
- summarizeAllowedValues
- does not collapse mixed-type entries that stringify similarly
- keeps distinct long values even when labels truncate the same way

### src/config/cache-utils.test.lisp
- resolveCacheTtlMs
- accepts exact non-negative integers
- rejects malformed env values and falls back to the default

### src/config/channel-capabilities.test.lisp
- resolveChannelCapabilities
- returns undefined for missing inputs
- normalizes and prefers per-account capabilities
- falls back to provider capabilities when account capabilities are missing
- matches account keys case-insensitively
- supports msteams capabilities
- handles object-format capabilities gracefully (e.g., { inlineButtons: 'dm' })

### src/config/commands.test.lisp
- resolveNativeSkillsEnabled
- uses provider defaults for auto
- honors explicit provider settings
- resolveNativeCommandsEnabled
- follows the same provider default heuristic
- honors explicit provider/global booleans
- isNativeCommandsExplicitlyDisabled
- returns true only for explicit false at provider or fallback global
- isRestartEnabled
- defaults to enabled unless explicitly false
- ignores inherited restart flags
- isCommandFlagEnabled
- requires own boolean true

### src/config/config-misc.test.lisp
- $schema key in config (#14998)
- accepts config with $schema string
- accepts config without $schema
- rejects non-string $schema
- plugins.slots.contextEngine
- accepts a contextEngine slot id
- ui.seamColor
- accepts hex colors
- rejects non-hex colors
- rejects invalid hex length
- plugins.entries.*.hooks.allowPromptInjection
- accepts boolean values
- rejects non-boolean values
- web search provider config
- accepts kimi provider and config
- talk.voiceAliases
- accepts a string map of voice aliases
- rejects non-string voice alias values
- gateway.remote.transport
- accepts direct transport
- rejects unknown transport
- gateway.tools config
- accepts gateway.tools allow and deny lists
- rejects invalid gateway.tools values
- gateway.channelHealthCheckMinutes
- accepts zero to disable monitor
- rejects negative intervals
- cron webhook schema
- accepts cron.webhookToken and legacy cron.webhook
- accepts cron.webhookToken SecretRef values
- rejects non-http cron.webhook URLs
- accepts cron.retry config
- broadcast
- accepts a broadcast peer map with strategy
- rejects invalid broadcast strategy
- rejects non-array broadcast entries
- model compat config schema
- accepts full openai-completions compat fields
- config paths
- rejects empty and blocked paths
- sets, gets, and unsets nested values
- config strict validation
- rejects unknown fields
- flags legacy config entries without auto-migrating
- does not mark resolved-only gateway.bind aliases as auto-migratable legacy
- still marks literal gateway.bind host aliases as legacy

### src/config/config.acp-binding-cutover.test.lisp
- ACP binding cutover schema
- accepts top-level typed ACP bindings with per-agent runtime defaults
- rejects legacy Discord channel-local ACP binding fields
- rejects legacy Telegram topic-local ACP binding fields
- rejects ACP bindings without a peer conversation target
- rejects ACP bindings on unsupported channels
- rejects non-canonical Telegram ACP topic peer IDs

### src/config/config.agent-concurrency-defaults.test.lisp
- agent concurrency defaults
- resolves defaults when unset
- clamps invalid values to at least 1
- accepts subagent spawn depth and per-agent child limits
- injects defaults on load

### src/config/config.allowlist-requires-allowfrom.test.lisp
- dmPolicy="allowlist" requires non-empty effective allowFrom
- rejects telegram dmPolicy="allowlist" without allowFrom
- rejects signal dmPolicy="allowlist" without allowFrom
- rejects discord dmPolicy="allowlist" without allowFrom
- rejects whatsapp dmPolicy="allowlist" without allowFrom
- accepts dmPolicy="pairing" without allowFrom
- account dmPolicy="allowlist" uses inherited allowFrom
- accepts telegram account allowlist when parent allowFrom exists
- rejects telegram account allowlist when neither account nor parent has allowFrom
- accepts signal account allowlist when parent allowFrom exists
- accepts discord account allowlist when parent allowFrom exists
- accepts slack account allowlist when parent allowFrom exists
- accepts whatsapp account allowlist when parent allowFrom exists
- accepts imessage account allowlist when parent allowFrom exists
- accepts irc account allowlist when parent allowFrom exists
- accepts bluebubbles account allowlist when parent allowFrom exists

### src/config/config.backup-rotation.test.lisp
- config backup rotation
- keeps a 5-deep backup ring for config writes
- cleanOrphanBackups removes stale files outside the rotation ring
- maintainConfigBackups composes rotate/copy/harden/prune flow

### src/config/config.compaction-settings.test.lisp
- config compaction settings
- preserves memory flush config values
- preserves pi compaction override values
- defaults compaction mode to safeguard
- preserves recent turn safeguard values through loadConfig()
- preserves oversized quality guard retry values for runtime clamping

### src/config/config.discord-agent-components.test.lisp
- discord agentComponents config
- accepts channels.discord.agentComponents.enabled
- accepts channels.discord.accounts.<id>.agentComponents.enabled
- rejects unknown fields under channels.discord.agentComponents

### src/config/config.discord-presence.test.lisp
- config discord presence
- accepts status-only presence
- accepts custom activity when type is omitted
- accepts custom activity type
- rejects streaming activity without url
- rejects activityUrl without streaming type
- accepts auto presence config
- rejects auto presence min update interval above check interval

### src/config/config.discord.test.lisp
- config discord
- loads discord guild map + dm group settings
- rejects numeric discord allowlist entries

### src/config/config.dm-policy-alias.test.lisp
- DM policy aliases (Slack/Discord)
- rejects discord dmPolicy="open" without allowFrom "*"
- rejects discord dmPolicy="open" with empty allowFrom
- rejects discord legacy dm.policy="open" with empty dm.allowFrom
- accepts discord legacy dm.policy="open" with top-level allowFrom alias
- rejects slack dmPolicy="open" without allowFrom "*"
- accepts slack legacy dm.policy="open" with top-level allowFrom alias

### src/config/config.env-vars.test.lisp
- config env vars
- applies env vars from env block when missing
- does not override existing env vars
- applies env vars from env.vars when missing
- blocks dangerous startup env vars from config env
- drops non-portable env keys from config env
- loads ${VAR} substitutions from ~/.openclaw/.env on repeated runtime loads

### src/config/config.gateway-tailscale-bind.test.lisp
- gateway tailscale bind validation
- accepts loopback bind when tailscale serve/funnel is enabled
- accepts custom loopback bind host with tailscale serve/funnel
- rejects IPv6 custom bind host for tailscale serve/funnel
- rejects non-loopback bind when tailscale serve/funnel is enabled

### src/config/config.hooks-module-paths.test.lisp
- config hooks module paths
- rejects absolute hooks.mappings[].transform.module
- rejects escaping hooks.mappings[].transform.module
- rejects absolute hooks.internal.handlers[].module
- rejects escaping hooks.internal.handlers[].module

### src/config/config.identity-avatar.test.lisp
- identity avatar validation
- accepts workspace-relative avatar paths
- accepts http(s) and data avatars
- rejects avatar paths outside workspace

### src/config/config.identity-defaults.test.lisp
- config identity defaults
- does not derive mention defaults and only sets ackReactionScope when identity is present
- keeps ackReaction unset and does not synthesize agent/session defaults when identity is missing
- does not override explicit values
- supports provider textChunkLimit config
- accepts blank model provider apiKey values
- accepts SecretRef values in model provider headers
- respects empty responsePrefix to disable identity defaults

### src/config/config.irc.test.lisp
- config irc
- accepts basic irc config
- rejects irc.dmPolicy="open" without allowFrom "*"
- accepts irc.dmPolicy="open" with allowFrom "*"
- accepts mixed allowFrom value types for IRC
- rejects nickserv register without registerEmail
- accepts nickserv register with password and registerEmail
- accepts nickserv register with registerEmail only (password may come from env)

### src/config/config.legacy-config-detection.accepts-imessage-dmpolicy.test.lisp
- legacy config detection
- accepts imessage.dmPolicy="open" with allowFrom "*"
- rejects unsafe executable config values
- accepts tools audio transcription without cli
- accepts path-like executable values with spaces
- rejects legacy agent.model string
- migrates telegram.requireMention to channels.telegram.groups.*.requireMention
- migrates messages.tts.enabled to messages.tts.auto
- migrates legacy model config to agent.models + model lists
- flags legacy config in snapshot
- flags top-level memorySearch as legacy in snapshot
- flags top-level heartbeat as legacy in snapshot
- flags legacy provider sections in snapshot
- does not auto-migrate claude-cli auth profile mode on load
- flags routing.allowFrom in snapshot
- rejects bindings[].match.provider on load
- rejects bindings[].match.accountID on load
- accepts bindings[].comment on load
- rejects session.sendPolicy.rules[].match.provider on load
- rejects messages.queue.byProvider on load

### src/config/config.legacy-config-detection.rejects-routing-allowfrom.test.lisp
- legacy config detection
- rejects legacy routing keys
- migrates or drops routing.allowFrom based on whatsapp configuration
- migrates routing.groupChat.requireMention to provider group defaults
- migrates routing.groupChat.mentionPatterns to messages.groupChat.mentionPatterns
- migrates routing agentToAgent/queue/transcribeAudio to tools/messages/media
- migrates audio.transcription with custom script names
- rejects audio.transcription when command contains non-string parts
- migrates agent config into agents.defaults and tools
- migrates top-level memorySearch to agents.defaults.memorySearch
- merges top-level memorySearch into agents.defaults.memorySearch
- keeps nested agents.defaults.memorySearch values when merging legacy defaults
- migrates tools.bash to tools.exec
- accepts per-agent tools.elevated overrides
- rejects telegram.requireMention
- rejects gateway.token
- migrates gateway.token to gateway.auth.token
- keeps gateway.bind tailnet
- normalizes gateway.bind host aliases to supported bind modes
- flags gateway.bind host aliases as legacy to trigger auto-migration paths
- escapes control characters in gateway.bind migration change text
- enforces dmPolicy="open" allowFrom wildcard for supported providers
- accepts dmPolicy="open" when allowFrom includes wildcard
- defaults dm/group policy for configured providers
- normalizes telegram legacy streamMode aliases
- normalizes discord streaming fields during legacy migration
- normalizes discord streaming fields during validation
- normalizes account-level discord and slack streaming aliases
- accepts historyLimit overrides per provider and account

### src/config/config.meta-timestamp-coercion.test.lisp
- meta.lastTouchedAt numeric timestamp coercion
- accepts a numeric Unix timestamp and coerces it to an ISO string
- still accepts a string ISO timestamp unchanged
- rejects out-of-range numeric timestamps without throwing
- passes non-date strings through unchanged (backwards-compatible)
- accepts meta with only lastTouchedVersion (no lastTouchedAt)

### src/config/config.msteams.test.lisp
- config msteams
- accepts replyStyle at global/team/channel levels
- rejects invalid replyStyle

### src/config/config.multi-agent-agentdir-validation.test.lisp
- multi-agent agentDir validation
- rejects shared agents.list agentDir
- throws on shared agentDir during loadConfig()

### src/config/config.nix-integration-u3-u5-u9.test.lisp
- Nix integration (U3, U5, U9)
- U3: isNixMode env var detection
- isNixMode is false when OPENCLAW_NIX_MODE is not set
- isNixMode is false when OPENCLAW_NIX_MODE is empty
- isNixMode is false when OPENCLAW_NIX_MODE is not '1'
- isNixMode is true when OPENCLAW_NIX_MODE=1
- U5: CONFIG_PATH and STATE_DIR env var overrides
- STATE_DIR defaults to ~/.openclaw when env not set
- STATE_DIR respects OPENCLAW_STATE_DIR override
- STATE_DIR respects OPENCLAW_HOME when state override is unset
- CONFIG_PATH defaults to OPENCLAW_HOME/.openclaw/openclaw.json
- CONFIG_PATH defaults to ~/.openclaw/openclaw.json when env not set
- CONFIG_PATH respects OPENCLAW_CONFIG_PATH override
- CONFIG_PATH expands ~ in OPENCLAW_CONFIG_PATH override
- CONFIG_PATH uses STATE_DIR when only state dir is overridden
- U5b: tilde expansion for config paths
- expands ~ in common path-ish config fields
- U6: gateway port resolution
- uses default when env and config are unset
- prefers OPENCLAW_GATEWAY_PORT over config
- falls back to config when env is invalid
- U9: telegram.tokenFile schema validation
- accepts config with only botToken
- accepts config with only tokenFile
- accepts config with both botToken and tokenFile

### src/config/config.plugin-validation.test.lisp
- config plugin validation
- reports missing plugin refs across load paths, entries, and allowlist surfaces
- warns for removed legacy plugin ids instead of failing validation
- surfaces plugin config diagnostics
- surfaces allowed enum values for plugin config diagnostics
- accepts voice-call webhookSecurity and streaming guard config fields
- accepts known plugin ids and valid channel/heartbeat enums
- accepts plugin heartbeat targets
- rejects unknown heartbeat targets
- rejects invalid heartbeat directPolicy values

### src/config/config.pruning-defaults.test.lisp
- config pruning defaults
- does not enable contextPruning by default
- enables cache-ttl pruning + 1h heartbeat for Anthropic OAuth
- enables cache-ttl pruning + 1h cache TTL for Anthropic API keys
- adds default cacheRetention for Anthropic Claude models on Bedrock
- does not add default cacheRetention for non-Anthropic Bedrock models
- does not override explicit contextPruning mode

### src/config/config.sandbox-docker.test.lisp
- sandbox docker config
- joins setupCommand arrays with newlines
- accepts safe binds array in sandbox.docker config
- rejects network host mode via Zod schema validation
- rejects container namespace join by default
- allows container namespace join with explicit dangerous override
- uses agent override precedence for dangerous sandbox docker booleans
- rejects seccomp unconfined via Zod schema validation
- rejects apparmor unconfined via Zod schema validation
- rejects non-string values in binds array
- sandbox browser binds config
- accepts binds array in sandbox.browser config
- rejects non-string values in browser binds array
- merges global and agent browser binds
- treats empty binds as configured (override to none)
- ignores agent browser binds under shared scope
- returns undefined binds when none configured
- defaults browser network to dedicated sandbox network
- prefers agent browser network over global browser network
- merges cdpSourceRange with agent override
- rejects host network mode in sandbox.browser config
- rejects container namespace join in sandbox.browser config by default
- allows container namespace join in sandbox.browser config with explicit dangerous override

### src/config/config.schema-regressions.test.lisp
- config schema regressions
- accepts nested telegram groupPolicy overrides
- accepts memorySearch fallback "voyage"
- accepts memorySearch provider "mistral"
- accepts safe iMessage remoteHost
- accepts channels.whatsapp.enabled
- rejects unsafe iMessage remoteHost
- accepts iMessage attachment root patterns
- accepts string values for agents defaults model inputs
- accepts pdf default model and limits
- rejects non-positive pdf limits
- rejects relative iMessage attachment roots
- accepts browser.extraArgs for proxy and custom flags
- rejects browser.extraArgs with non-array value

### src/config/config.secrets-schema.test.lisp
- config secret refs schema
- accepts top-level secrets sources and model apiKey refs
- accepts openai-codex-responses as a model api value
- accepts googlechat serviceAccount refs
- accepts skills entry apiKey refs
- accepts file refs with id "value" for singleValue mode providers
- rejects invalid secret ref id
- rejects env refs that are not env var names
- rejects file refs that are not absolute JSON pointers

### src/config/config.skills-entries-config.test.lisp
- skills entries config schema
- accepts custom fields under config
- rejects unknown top-level fields

### src/config/config.talk-api-key-fallback.test.lisp
- talk api key fallback
- reads ELEVENLABS_API_KEY from profile when env is missing
- prefers ELEVENLABS_API_KEY env over profile

### src/config/config.telegram-audio-preflight.test.lisp
- telegram disableAudioPreflight schema
- accepts disableAudioPreflight for groups and topics
- rejects non-boolean disableAudioPreflight values

### src/config/config.telegram-custom-commands.test.lisp
- telegram custom commands schema
- normalizes custom commands
- normalizes hyphens in custom command names

### src/config/config.telegram-topic-agentid.test.lisp
- telegram topic agentId schema
- accepts valid agentId in forum group topic config
- accepts valid agentId in DM topic config
- accepts empty config without agentId (backward compatible)
- accepts multiple topics with different agentIds
- rejects unknown fields in topic config (strict schema)

### src/config/config.tools-alsoAllow.test.lisp
- config: tools.alsoAllow
- rejects tools.allow + tools.alsoAllow together
- rejects agents.list[].tools.allow + alsoAllow together
- allows profile + alsoAllow

### src/config/config.web-search-provider.test.lisp
- web search provider config
- accepts perplexity provider and config
- accepts gemini provider and config
- accepts gemini provider with no extra config
- web search provider auto-detection
- falls back to perplexity when no keys available
- auto-detects brave when only BRAVE_API_KEY is set
- auto-detects gemini when only GEMINI_API_KEY is set
- auto-detects kimi when only KIMI_API_KEY is set
- auto-detects perplexity when only PERPLEXITY_API_KEY is set
- auto-detects grok when only XAI_API_KEY is set
- auto-detects kimi when only KIMI_API_KEY is set
- auto-detects kimi when only MOONSHOT_API_KEY is set
- follows priority order — perplexity wins when multiple keys available
- brave wins over gemini and grok when perplexity unavailable
- explicit provider always wins regardless of keys

### src/config/env-preserve-io.test.lisp
- env snapshot TOCTOU via createConfigIO
- restores env refs using read-time env even after env mutation
- without snapshot bridging, mutated env causes incorrect restoration
- env snapshot TOCTOU via wrapper APIs
- uses explicit read context even if another read interleaves
- ignores read context when expected config path does not match

### src/config/env-preserve.test.lisp
- restoreEnvVarRefs
- restores a simple ${VAR} reference when value matches
- keeps new value when caller intentionally changed it
- handles nested objects
- preserves new keys not in parsed
- handles non-env-var strings (no restoration needed)
- handles arrays
- handles null/undefined parsed gracefully
- handles missing env var (cannot verify match)
- handles composite template strings like prefix-${VAR}-suffix
- handles type mismatches between incoming and parsed
- does not restore when parsed value has no env var pattern
- does not incorrectly restore when env var value changed between read and write
- correctly restores when env var value hasn't changed
- does not restore when env snapshot differs from live env (TOCTOU fix)
- handles $${VAR} escape sequence (literal ${VAR} in output)
- does not confuse $${VAR} escape with ${VAR} substitution

### src/config/env-substitution.test.lisp
- resolveConfigEnvVars
- basic substitution
- substitutes direct, inline, repeated, and multi-var patterns
- nested structures
- substitutes variables in nested objects and arrays
- missing env var handling
- throws MissingEnvVarError with var name and config path details
- escape syntax
- handles escaped placeholders alongside regular substitutions
- pattern matching rules
- leaves non-matching placeholders unchanged
- substitutes valid uppercase/underscore placeholder names
- passthrough behavior
- passes through primitives unchanged
- preserves empty and non-string containers
- graceful missing env var handling (onMissing)
- collects warnings and preserves placeholder when onMissing is set
- collects multiple warnings across nested paths
- still throws when onMissing is not set
- containsEnvVarReference
- detects unresolved env var placeholders
- returns false for non-matching patterns
- returns false for escaped placeholders
- detects references mixed with escaped placeholders
- real-world config patterns
- substitutes provider, gateway, and base URL config values

### src/config/group-policy.test.lisp
- resolveChannelGroupPolicy
- fails closed when groupPolicy=allowlist and groups are missing
- allows configured groups when groupPolicy=allowlist
- blocks all groups when groupPolicy=disabled
- respects account-scoped groupPolicy overrides
- allows groups when groupPolicy=allowlist with hasGroupAllowFrom but no groups
- still fails closed when groupPolicy=allowlist without groups or groupAllowFrom
- resolveToolsBySender
- matches typed sender IDs
- does not allow senderName collisions to match id keys
- treats untyped legacy keys as senderId only
- matches username keys only against senderUsername
- matches e164 and name only when explicitly typed
- prefers id over username over name
- emits one deprecation warning per legacy key

### src/config/includes.test.lisp
- resolveConfigIncludes
- passes through non-include values unchanged
- rejects absolute path outside config directory (CWE-22)
- resolves single and array include merges
- merges include content with sibling keys and sibling overrides
- throws when sibling keys are used with non-object includes
- resolves nested includes
- surfaces include read and parse failures
- throws CircularIncludeError for circular includes
- throws on invalid include value/item types
- respects max depth limit
- allows depth 10 but rejects depth 11
- handles relative paths and nested-include override ordering
- enforces traversal boundaries while allowing safe nested-parent paths
- real-world config patterns
- supports common modular include layouts
- security: path traversal protection (CWE-22)
- absolute path attacks
- rejects absolute path attack variants
- relative traversal attacks
- rejects relative traversal path variants
- legitimate includes (should work)
- allows legitimate include paths under config root
- error properties
- preserves error type/path/message details
- array includes with malicious paths
- rejects arrays that contain malicious include paths
- allows array with all legitimate paths
- prototype pollution protection
- blocks prototype pollution vectors in shallow and nested merges
- edge cases
- rejects malformed include paths
- allows child include when config is at filesystem root
- allows include files when the config root path is a symlink
- rejects include files that are hardlinked aliases
- rejects oversized include files

### src/config/io.compat.test.lisp
- config io paths
- uses ~/.openclaw/openclaw.json when config exists
- defaults to ~/.openclaw/openclaw.json when config is missing
- uses OPENCLAW_HOME for default config path
- honors explicit OPENCLAW_CONFIG_PATH override
- honors legacy CLAWDBOT_CONFIG_PATH override
- normalizes safe-bin config entries at config load time
- logs invalid config path details and throws on invalid config

### src/config/io.eacces.test.lisp
- config io EACCES handling
- returns a helpful error message when config file is not readable (EACCES)
- includes configPath in the chown hint for the correct remediation command

### src/config/io.owner-display-secret.test.lisp
- config io owner display secret autofill
- auto-generates and persists commands.ownerDisplaySecret in hash mode

### src/config/io.runtime-snapshot-write.test.lisp
- runtime config snapshot writes
- returns the source snapshot when runtime snapshot is active
- clears runtime source snapshot when runtime snapshot is cleared
- preserves source secret refs when writeConfigFile receives runtime-resolved config

### src/config/io.validation-fails-closed.test.lisp
- config validation fail-closed behavior
- throws INVALID_CONFIG instead of returning an empty config
- still loads valid security settings unchanged

### src/config/io.write-config.test.lisp
- config io write
- persists caller changes onto resolved config without leaking runtime defaults
- shows actionable guidance for dmPolicy="open" without wildcard allowFrom
- honors explicit unset paths when schema defaults would otherwise reappear
- does not mutate caller config when unsetPaths is applied on first write
- does not mutate caller config when unsetPaths is applied on existing files
- keeps caller arrays immutable when unsetting array entries
- treats missing unset paths as no-op without mutating caller config
- ignores blocked prototype-key unset path segments
- preserves env var references when writing
- does not reintroduce Slack/Discord legacy dm.policy defaults when writing
- keeps env refs in arrays when appending entries
- logs an overwrite audit entry when replacing an existing config file
- does not log an overwrite audit entry when creating config for the first time
- appends config write audit JSONL entries with forensic metadata
- records gateway watch session markers in config audit entries

### src/config/issue-format.test.lisp
- config issue format
- normalizes empty paths to <root>
- formats issue lines with and without markers
- sanitizes control characters and ANSI sequences in formatted lines
- normalizes issue metadata for machine output

### src/config/legacy-migrate.test.lisp
- legacy migrate audio transcription
- moves routing.transcribeAudio into tools.media.audio.models
- keeps existing tools media model and drops legacy routing value
- drops invalid audio.transcription payloads
- legacy migrate mention routing
- moves routing.groupChat.requireMention into channel group defaults
- moves channels.telegram.requireMention into groups.*.requireMention
- legacy migrate heartbeat config
- moves top-level heartbeat into agents.defaults.heartbeat
- moves top-level heartbeat visibility into channels.defaults.heartbeat
- keeps explicit agents.defaults.heartbeat values when merging top-level heartbeat
- keeps explicit channels.defaults.heartbeat values when merging top-level heartbeat visibility
- preserves agent.heartbeat precedence over top-level heartbeat legacy key
- drops blocked prototype keys when migrating top-level heartbeat
- records a migration change when removing empty top-level heartbeat
- legacy migrate controlUi.allowedOrigins seed (issue #29385)
- seeds allowedOrigins for bind=lan with no existing controlUi config
- seeds allowedOrigins using configured port
- seeds allowedOrigins including custom bind host for bind=custom
- does not overwrite existing allowedOrigins — returns null (no migration needed)
- does not migrate when dangerouslyAllowHostHeaderOriginFallback is set — returns null
- seeds allowedOrigins when existing entries are blank strings
- does not migrate loopback bind — returns null
- preserves existing controlUi fields when seeding allowedOrigins

### src/config/legacy.shared.test.lisp
- mergeMissing prototype pollution guard
- ignores __proto__ keys without polluting Object.prototype

### src/config/logging-max-file-bytes.test.lisp
- logging.maxFileBytes config
- accepts a positive maxFileBytes
- rejects non-positive maxFileBytes

### src/config/merge-patch.proto-pollution.test.lisp
- applyMergePatch prototype pollution guard
- ignores __proto__ keys in patch
- ignores constructor key in patch
- ignores prototype key in patch
- ignores __proto__ in nested patches

### src/config/merge-patch.test.lisp
- applyMergePatch
- replaces arrays by default
- merges object arrays by id when enabled
- merges by id even when patch entries lack id (appends them)
- does not destroy agents list when patching a single agent by id
- keeps existing id entries when patch mixes id and primitive entries
- falls back to replacement for non-id arrays even when enabled

### src/config/model-alias-defaults.test.lisp
- applyModelDefaults
- adds default aliases when models are present
- does not override existing aliases
- respects explicit empty alias disables
- fills missing model provider defaults
- clamps maxTokens to contextWindow
- defaults anthropic provider and model api to anthropic-messages
- propagates provider api to models when model api is missing

### src/config/normalize-paths.test.lisp
- normalizeConfigPaths
- expands tilde for path-ish keys only

### src/config/paths.test.lisp
- oauth paths
- prefers OPENCLAW_OAUTH_DIR over OPENCLAW_STATE_DIR
- derives oauth path from OPENCLAW_STATE_DIR when unset
- state + config path candidates
- uses OPENCLAW_STATE_DIR when set
- uses OPENCLAW_HOME for default state/config locations
- prefers OPENCLAW_HOME over HOME for default state/config locations
- orders default config candidates in a stable order
- prefers ~/.openclaw when it exists and legacy dir is missing
- falls back to existing legacy state dir when ~/.openclaw is missing
- CONFIG_PATH prefers existing config when present
- respects state dir overrides when config is missing

### src/config/plugin-auto-enable.test.lisp
- applyPluginAutoEnable
- auto-enables built-in channels and appends to existing allowlist
- does not create plugins.allow when allowlist is unset
- ignores channels.modelByChannel for plugin auto-enable
- keeps auto-enabled WhatsApp config schema-valid
- respects explicit disable
- respects built-in channel explicit disable via channels.<id>.enabled
- auto-enables irc when configured via env
- auto-enables provider auth plugins when profiles exist
- auto-enables acpx plugin when ACP is configured
- does not auto-enable acpx when a different ACP backend is configured
- skips when plugins are globally disabled
- third-party channel plugins (pluginId ≠ channelId)
- uses the plugin manifest id, not the channel id, for plugins.entries
- does not double-enable when plugin is already enabled under its plugin id
- respects explicit disable of the plugin by its plugin id
- falls back to channel key as plugin id when no installed manifest declares the channel
- preferOver channel prioritization
- prefers bluebubbles: skips imessage auto-configure when both are configured
- keeps imessage enabled if already explicitly enabled (non-destructive)
- allows imessage auto-configure when bluebubbles is explicitly disabled
- allows imessage auto-configure when bluebubbles is in deny list
- auto-enables imessage when only imessage is configured

### src/config/plugins-runtime-boundary.test.lisp
- plugins runtime boundary config
- omits legacy plugins.runtime keys from schema metadata
- omits plugins.runtime from the generated config schema
- rejects legacy plugins.runtime config entries

### src/config/redact-snapshot.test.lisp
- redactConfigSnapshot
- redacts common secret field patterns across config sections
- redacts googlechat serviceAccount object payloads
- redacts object-valued apiKey refs in model providers
- preserves non-sensitive fields
- does not redact maxTokens-style fields
- does not redact passwordFile path fields
- preserves hash unchanged
- redacts secrets in raw field via text-based redaction
- keeps non-sensitive raw fields intact when secret values overlap
- preserves SecretRef structural fields while redacting SecretRef id
- handles overlap fallback and SecretRef in the same snapshot
- redacts parsed and resolved objects
- handles null raw gracefully
- withholds resolved config for invalid snapshots
- handles deeply nested tokens in accounts
- redacts env vars that look like secrets
- respects token-name redaction boundaries
- uses uiHints to determine sensitivity
- keeps regex fallback for extension keys not covered by uiHints
- honors sensitive:false for extension keys even with regex fallback
- round-trips nested and array sensitivity cases
- respects sensitive:false in uiHints even for regex-matching paths
- redacts sensitive-looking paths even when absent from uiHints (defense in depth)
- redacts and restores dynamic env catchall secrets when uiHints miss the path
- redacts and restores skills entry env secrets in dynamic record paths
- contract-covers dynamic catchall/record paths for redact+restore
- uses wildcard hints for array items
- restoreRedactedValues
- restores sentinel values from original config
- preserves explicitly changed sensitive values
- preserves non-sensitive fields unchanged
- handles deeply nested sentinel restoration
- handles missing original gracefully
- rejects invalid restore inputs
- returns a human-readable error when sentinel cannot be restored
- keeps unmatched wildcard array entries unchanged outside extension paths
- round-trips config through redact → restore
- round-trips with uiHints for custom sensitive fields
- restores with uiHints respecting sensitive:false override
- restores array items using wildcard uiHints
- realredactConfigSnapshot_real
- main schema redact works (samples)

### src/config/runtime-group-policy.test.lisp
- resolveRuntimeGroupPolicy
- resolveOpenProviderRuntimeGroupPolicy
- uses open fallback when provider config exists
- resolveAllowlistProviderRuntimeGroupPolicy
- uses allowlist fallback when provider config exists
- resolveDefaultGroupPolicy
- returns channels.defaults.groupPolicy when present
- warnMissingProviderGroupPolicyFallbackOnce
- logs only once per provider/account key

### src/config/runtime-overrides.test.lisp
- runtime overrides
- sets and applies nested overrides
- merges object overrides without clobbering siblings
- unsets overrides and prunes empty branches
- rejects prototype pollution paths
- blocks __proto__ keys inside override object values
- blocks constructor/prototype keys inside override object values
- sanitizes blocked object keys when writing overrides

### src/config/schema.help.quality.test.lisp
- config help copy quality
- keeps root section labels and help complete
- keeps labels in parity for all help keys
- covers the target confusing fields with non-trivial explanations
- covers tools/hooks help keys with non-trivial operational guidance
- covers channels/agents help keys with non-trivial operational guidance
- covers final backlog help keys with non-trivial operational guidance
- documents option behavior for enum-style fields
- explains memory citations mode semantics
- includes concrete examples on path and interval fields
- documents cron deprecation, migration, and retention formats
- documents session send-policy examples and prefix semantics
- documents session maintenance duration/size examples and deprecations
- documents cron run-log retention controls
- documents approvals filters and target semantics
- documents broadcast and audio command examples
- documents hook transform safety and queue behavior options
- documents gateway bind modes and web reconnect semantics
- documents metadata/admin semantics for logging, wizard, and plugins
- documents auth/model root semantics and provider secret handling
- documents agent compaction safeguards and memory flush behavior

### src/config/schema.hints.test.lisp
- isSensitiveConfigPath
- matches whitelist suffixes case-insensitively
- keeps true sensitive keys redacted
- mapSensitivePaths
- should detect sensitive fields nested inside all structural Zod types
- should not detect non-sensitive fields nested inside all structural Zod types
- maps sensitive fields nested under object catchall schemas
- does not mark plain catchall values sensitive by default
- main schema yields correct hints (samples)

### src/config/schema.test.lisp
- config schema
- exports schema + hints
- merges plugin ui hints
- does not re-mark existing non-sensitive token-like fields
- merges plugin + channel schemas
- looks up plugin config paths for slash-delimited plugin ids
- adds heartbeat target hints with dynamic channels
- caches merged schemas for identical plugin/channel metadata
- derives security/auth tags for credential paths
- derives tools/performance tags for web fetch timeout paths
- keeps tags in the allowed taxonomy
- covers core/built-in config paths with tags
- looks up a config schema path with immediate child summaries
- returns a shallow lookup schema without nested composition keywords
- matches wildcard ui hints for concrete lookup paths
- normalizes bracketed lookup paths
- matches ui hints that use empty array brackets
- uses the indexed tuple item schema for positional array lookups
- rejects prototype-chain lookup segments
- rejects overly deep lookup paths
- returns null for missing config schema paths

### src/config/sessions.cache.test.lisp
- Session Store Cache
- should load session store from disk on first call
- should serve freshly saved session stores from cache without disk reads
- should not allow cached session mutations to leak across loads
- should refresh cache when store file changes on disk
- should invalidate cache on write
- should respect OPENCLAW_SESSION_CACHE_TTL_MS=0 to disable cache
- should handle non-existent store gracefully
- should handle invalid JSON gracefully
- should refresh cache when file is rewritten within the same mtime tick

### src/config/sessions.test.lisp
- sessions
- builds discord display name with guild+channel slugs
- updateLastRoute persists channel and target
- updateLastRoute prefers explicit deliveryContext
- updateLastRoute clears threadId when explicit route omits threadId
- updateLastRoute records origin + group metadata when ctx is provided
- updateSessionStoreEntry preserves existing fields when patching
- updateSessionStoreEntry returns null when session key does not exist
- updateSessionStoreEntry keeps existing entry when patch callback returns null
- updateSessionStore preserves concurrent additions
- recovers from array-backed session stores
- normalizes last route fields on write
- updateSessionStore keeps deletions when concurrent writes happen
- loadSessionStore auto-migrates legacy provider keys to channel keys
- derives session transcripts dir from OPENCLAW_STATE_DIR
- includes topic ids in session transcript filenames
- uses agent id when resolving session file fallback paths
- resolves cross-agent absolute sessionFile paths
- resolves cross-agent paths when OPENCLAW_STATE_DIR differs from stored paths
- falls back when structural cross-root path traverses after sessions
- falls back when structural cross-root path nests under sessions
- resolveSessionFilePathOptions keeps explicit agentId alongside absolute store path
- resolves sibling agent absolute sessionFile using alternate agentId from options
- falls back to derived transcript path when sessionFile is outside agent sessions directories
- updateSessionStoreEntry merges concurrent patches
- updateSessionStoreEntry re-reads disk inside lock instead of using stale cache

### src/config/sessions/artifacts.test.lisp
- session artifact helpers
- classifies archived artifact file names
- classifies primary transcript files
- formats and parses archive timestamps

### src/config/sessions/cache-fields.test.lisp
- SessionEntry cache fields
- supports cacheRead and cacheWrite fields
- merges cache fields properly
- handles undefined cache fields
- allows cache fields to be cleared with undefined

### src/config/sessions/delivery-info.test.lisp
- extractDeliveryInfo
- parses base session and thread/topic ids
- returns deliveryContext for direct session keys
- falls back to base sessions for :thread: keys
- falls back to base sessions for :topic: keys

### src/config/sessions/disk-budget.test.lisp
- enforceSessionDiskBudget
- does not treat referenced transcripts with marker-like session IDs as archived artifacts
- removes true archived transcript artifacts while preserving referenced primary transcripts

### src/config/sessions/explicit-session-key-normalization.test.lisp
- normalizeExplicitSessionKey
- dispatches discord keys through the provider normalizer
- infers the provider from From when explicit provider fields are absent
- uses Provider when Surface is absent
- lowercases and passes through unknown providers unchanged

### src/config/sessions/session-key.test.lisp
- resolveSessionKey
- Discord DM session key normalization
- passes through correct discord:direct keys unchanged
- migrates legacy discord:dm: keys to discord:direct:
- fixes phantom discord:channel:USERID keys when sender matches
- does not rewrite discord:channel: keys for non-direct chats
- does not rewrite discord:channel: keys when sender does not match
- handles keys without an agent prefix

### src/config/sessions/sessions.test.lisp
- session path safety
- rejects unsafe session IDs
- resolves transcript path inside an explicit sessions dir
- falls back to derived path when sessionFile is outside known agent sessions dirs
- ignores multi-store sentinel paths when deriving session file options
- accepts symlink-alias session paths that resolve under the sessions dir
- falls back when sessionFile is a symlink that escapes sessions dir
- resolveSessionResetPolicy
- backward compatibility: resetByType.dm -> direct
- does not use dm fallback for group/thread types
- session store lock (Promise chain mutex)
- serializes concurrent updateSessionStore calls without data loss
- skips session store disk writes when payload is unchanged
- multiple consecutive errors do not permanently poison the queue
- clears stale runtime provider when model is patched without provider
- normalizes orphan modelProvider fields at store write boundary
- appendAssistantMessageToSessionTranscript
- creates transcript file and appends message for valid session
- resolveAndPersistSessionFile
- persists fallback topic transcript paths for sessions without sessionFile
- creates and persists entry when session is not yet present

### src/config/sessions/store.pruning.integration.test.lisp
- Integration: saveSessionStore with pruning
- saveSessionStore prunes stale entries on write
- archives transcript files for stale sessions pruned on write
- cleans up archived transcripts older than the prune window
- cleans up reset archives using resetArchiveRetention
- saveSessionStore skips enforcement when maintenance mode is warn
- archives transcript files for entries evicted by maxEntries capping
- does not archive external transcript paths when capping entries
- enforces maxDiskBytes with oldest-first session eviction
- uses projected sessions.json size to avoid over-eviction
- never deletes transcripts outside the agent sessions directory during budget cleanup

### src/config/sessions/store.pruning.test.lisp
- pruneStaleEntries
- removes entries older than maxAgeDays
- capEntryCount
- over limit: keeps N most recent by updatedAt, deletes rest
- rotateSessionFile
- file over maxBytes: renamed to .bak.{timestamp}, returns true
- multiple rotations: only keeps 3 most recent .bak files

### src/config/sessions/store.session-key-normalization.test.lisp
- session store key normalization
- records inbound metadata under a canonical lowercase key
- does not create a duplicate mixed-case key when last route is updated
- migrates legacy mixed-case entries to the canonical key on update
- preserves updatedAt when recording inbound metadata for an existing session

### src/config/slack-http-config.test.lisp
- Slack HTTP mode config
- accepts HTTP mode when signing secret is configured
- accepts HTTP mode when signing secret is configured as SecretRef
- rejects HTTP mode without signing secret
- accepts account HTTP mode when base signing secret is set
- accepts account HTTP mode when account signing secret is set as SecretRef
- rejects account HTTP mode without signing secret

### src/config/slack-token-validation.test.lisp
- Slack token config fields
- accepts user token config fields
- accepts account-level user token config
- rejects invalid userTokenReadOnly types
- rejects invalid userToken types

### src/config/talk.normalize.test.lisp
- talk normalization
- maps legacy ElevenLabs fields into provider/providers
- uses new provider/providers shape directly when present
- preserves SecretRef apiKey values during normalization
- merges ELEVENLABS_API_KEY into normalized defaults for legacy configs
- does not apply ELEVENLABS_API_KEY when active provider is not elevenlabs
- does not inject ELEVENLABS_API_KEY fallback when talk.apiKey is SecretRef

### src/config/telegram-actions-poll.test.lisp
- telegram poll action config
- accepts channels.telegram.actions.poll
- accepts channels.telegram.accounts.<id>.actions.poll

### src/config/telegram-webhook-port.test.lisp
- Telegram webhookPort config
- accepts a positive webhookPort
- accepts webhookPort set to 0 for ephemeral port binding
- rejects negative webhookPort

### src/config/telegram-webhook-secret.test.lisp
- Telegram webhook config
- accepts webhookUrl when webhookSecret is configured
- accepts webhookUrl when webhookSecret is configured as SecretRef
- rejects webhookUrl without webhookSecret
- accepts account webhookUrl when base webhookSecret is configured
- accepts account webhookUrl when account webhookSecret is configured as SecretRef
- rejects account webhookUrl without webhookSecret

### src/config/thread-bindings-config-keys.test.lisp
- thread binding config keys
- rejects legacy session.threadBindings.ttlHours
- rejects legacy channels.discord.threadBindings.ttlHours
- rejects legacy channels.discord.accounts.<id>.threadBindings.ttlHours
- migrates session.threadBindings.ttlHours to idleHours
- migrates Discord threadBindings.ttlHours for root and account entries

### src/config/validation.allowed-values.test.lisp
- config validation allowed-values metadata
- adds allowed values for invalid union paths
- keeps native enum messages while attaching allowed values metadata
- includes boolean variants for boolean-or-enum unions
- skips allowed-values hints for unions with open-ended branches

### src/config/zod-schema.cron-retention.test.lisp
- OpenClawSchema cron retention and run-log validation
- accepts valid cron.sessionRetention and runLog values
- rejects invalid cron.sessionRetention
- rejects invalid cron.runLog.maxBytes

### src/config/zod-schema.logging-levels.test.lisp
- OpenClawSchema logging levels
- accepts valid logging level values for level and consoleLevel
- rejects invalid logging level values

### src/config/zod-schema.session-maintenance-extensions.test.lisp
- SessionSchema maintenance extensions
- accepts valid maintenance extensions
- accepts parentForkMaxTokens including 0 to disable the guard
- rejects negative parentForkMaxTokens
- accepts disabling reset archive cleanup
- rejects invalid maintenance extension values

### src/config/zod-schema.typing-mode.test.lisp
- typing mode schema reuse
- accepts supported typingMode values for session and agent defaults
- rejects unsupported typingMode values for session and agent defaults

## context-engine

### src/context-engine/context-engine.test.lisp
- Engine contract tests
- a mock engine implementing ContextEngine can be registered and resolved
- ingest() returns IngestResult with ingested boolean
- assemble() returns AssembleResult with messages array and estimatedTokens
- compact() returns CompactResult with ok, compacted, reason, result fields
- dispose() is callable (optional method)
- Registry tests
- registerContextEngine() stores a factory
- getContextEngineFactory() returns the factory
- listContextEngineIds() returns all registered ids
- registering the same id overwrites the previous factory
- Default engine selection
- resolveContextEngine() with no config returns the default ('legacy') engine
- resolveContextEngine() with config contextEngine='legacy' returns legacy engine
- resolveContextEngine() with config contextEngine='test-engine' returns the custom engine
- Invalid engine fallback
- resolveContextEngine() with config pointing to unregistered engine throws with helpful error
- error message includes the requested id and available ids
- LegacyContextEngine parity
- ingest() returns { ingested: false } (no-op)
- assemble() returns messages as-is (pass-through)
- dispose() completes without error
- Initialization guard
- ensureContextEnginesInitialized() is idempotent (calling twice does not throw)
- after init, 'legacy' engine is registered

## cron

### src/cron/cron-protocol-conformance.test.lisp
- cron protocol conformance
- ui + swift include all cron delivery modes from gateway schema
- cron status shape matches gateway fields in UI + Swift

### src/cron/delivery.test.lisp
- resolveCronDeliveryPlan
- defaults to announce when delivery object has no mode
- respects legacy payload deliver=false
- resolves mode=none with requested=false and no channel (#21808)
- resolves webhook mode without channel routing
- threads delivery.accountId when explicitly configured
- resolveFailureDestination
- merges global defaults with job-level overrides
- returns null for webhook mode without destination URL
- returns null when failure destination matches primary delivery target
- allows job-level failure destination fields to clear inherited global values

### src/cron/heartbeat-policy.test.lisp
- shouldSkipHeartbeatOnlyDelivery
- suppresses empty payloads
- suppresses when any payload is a heartbeat ack and no media is present
- does not suppress when media is present
- shouldEnqueueCronMainSummary
- enqueues only when delivery was requested but did not run
- does not enqueue after attempted outbound delivery

### src/cron/isolated-agent.auth-profile-propagation.test.lisp
- runCronIsolatedAgentTurn auth profile propagation (#20624)
- passes authProfileId to runEmbeddedPiAgent when auth profiles exist

### src/cron/isolated-agent.delivers-response-has-heartbeat-ok-but-includes.test.lisp
- runCronIsolatedAgentTurn
- does not fan out telegram cron delivery across allowFrom entries
- suppresses announce delivery for multi-payload narration ending in HEARTBEAT_OK
- handles media heartbeat delivery and announce cleanup modes
- skips structured outbound delivery when timeout abort is already set
- uses a unique announce childRunId for each cron run

### src/cron/isolated-agent.delivery-target-thread-session.test.lisp
- resolveDeliveryTarget thread session lookup
- uses thread session entry when sessionKey is provided and entry exists
- falls back to main session when sessionKey entry does not exist
- falls back to main session when no sessionKey is provided
- preserves threadId from :topic: in delivery.to on first run (no session history)
- explicit accountId overrides session lastAccountId
- preserves threadId from :topic: when lastTo differs

### src/cron/isolated-agent.direct-delivery-forum-topics.test.lisp
- runCronIsolatedAgentTurn forum topic delivery
- routes forum-topic and plain telegram targets through the correct delivery path

### src/cron/isolated-agent.model-formatting.test.lisp
- cron model formatting and precedence edge cases
- parseModelRef formatting
- splits standard provider/model
- handles leading/trailing whitespace in model string
- handles openrouter nested provider paths
- rejects model with trailing slash (empty model name)
- rejects model with leading slash (empty provider)
- normalizes provider casing
- normalizes anthropic model aliases
- normalizes bedrock provider alias
- model precedence isolation
- job payload model overrides default (anthropic → openai)
- session override applies when no job payload model is present
- job payload model wins over conflicting session override
- falls through to default when no override is present
- sequential model switches (CI failure regression)
- openai override → session openai → job anthropic: each step resolves correctly
- provider does not leak between isolated sequential runs
- forceNew session preserves model overrides from store
- new isolated session inherits stored modelOverride/providerOverride
- new isolated session uses default when store has no override
- whitespace and empty model strings
- whitespace-only model treated as unset (falls to default)
- empty string model treated as unset
- whitespace-only session modelOverride is ignored
- config model format variations
- default model as string 'provider/model'
- default model as object with primary field
- job override switches away from object default

### src/cron/isolated-agent.skips-delivery-without-whatsapp-recipient-besteffortdeliver-true.test.lisp
- runCronIsolatedAgentTurn
- announces explicit targets with direct and final-payload text
- routes announce injection to the delivery-target session key
- routes threaded announce targets through direct delivery
- skips announce when messaging tool already sent to target
- reports not-delivered when best-effort structured outbound sends all fail
- skips announce for heartbeat-only output
- fails when structured direct delivery fails and best-effort is disabled
- falls back to direct delivery when announce reports false and best-effort is disabled
- falls back to direct delivery when announce reports false and best-effort is enabled
- falls back to direct delivery for signal when announce reports false and best-effort is enabled
- falls back to direct delivery when announce flow throws and best-effort is disabled
- ignores structured direct delivery failures when best-effort is enabled

### src/cron/isolated-agent.subagent-model.test.lisp
- runCronIsolatedAgentTurn: subagent model resolution (#11461)
- explicit job model override takes precedence over subagents.model

### src/cron/isolated-agent.uses-last-non-empty-agent-text-as.test.lisp
- runCronIsolatedAgentTurn
- treats blank model overrides as unset
- uses last non-empty agent text as summary
- returns error when embedded run payload is marked as error
- treats transient error payloads as non-fatal when a later success payload exists
- keeps error status when run-level error accompanies post-error text
- passes resolved agentDir to runEmbeddedPiAgent
- appends current time after the cron header line
- uses agentId for workspace, session key, and store paths
- applies model overrides with correct precedence
- uses hooks.gmail.model and keeps precedence over stored session override
- wraps external hook content by default
- skips external content wrapping when hooks.gmail opts out
- ignores hooks.gmail.model when not in the allowlist
- rejects invalid model override
- defaults thinking to low for reasoning-capable models
- truncates long summaries
- starts a fresh session id for each cron run
- preserves an existing cron session label

### src/cron/isolated-agent/delivery-dispatch.double-announce.test.lisp
- dispatchCronDelivery — double-announce guard
- early return (active subagent) sets deliveryAttempted=true so timer skips enqueueSystemEvent
- early return (stale interim suppression) sets deliveryAttempted=true so timer skips enqueueSystemEvent
- normal announce success delivers exactly once and sets deliveryAttempted=true
- announce failure falls back to direct delivery exactly once (no double-deliver)
- no delivery requested means deliveryAttempted stays false and runSubagentAnnounceFlow not called

### src/cron/isolated-agent/delivery-dispatch.named-agent.test.lisp
- matchesMessagingToolDeliveryTarget
- matches when channel and to agree
- rejects when channel differs
- rejects when to is missing from delivery
- rejects when channel is missing from delivery
- strips :topic:NNN suffix from target.to before comparing
- matches when provider is 'message' (generic)
- rejects when accountIds differ
- resolveCronDeliveryBestEffort
- returns false by default (no bestEffort set)
- returns true when delivery.bestEffort is true
- returns true when payload.bestEffortDeliver is true and no delivery.bestEffort

### src/cron/isolated-agent/delivery-target.test.lisp
- resolveDeliveryTarget
- reroutes implicit whatsapp delivery to authorized allowFrom recipient
- keeps explicit whatsapp target unchanged
- falls back to bound accountId when session has no lastAccountId
- preserves session lastAccountId when present
- returns undefined accountId when no binding and no session
- selects correct binding when multiple agents have bindings
- ignores bindings for different channels
- drops session threadId when destination does not match the previous recipient
- keeps session threadId when destination matches the previous recipient
- uses single configured channel when neither explicit nor session channel exists
- returns an error when channel selection is ambiguous
- uses sessionKey thread entry before main session entry
- uses main session channel when channel=last and session route exists
- explicit delivery.accountId overrides session-derived accountId
- explicit delivery.accountId overrides bindings-derived accountId

### src/cron/isolated-agent/helpers.test.lisp
- pickSummaryFromPayloads
- picks real text over error payload
- falls back to error payload when no real text exists
- returns undefined for empty payloads
- treats isError: undefined as non-error
- pickLastNonEmptyTextFromPayloads
- picks real text over error payload
- falls back to error payload when no real text exists
- returns undefined for empty payloads
- treats isError: undefined as non-error
- pickLastDeliverablePayload
- picks real payload over error payload
- falls back to error payload when no real payload exists
- returns undefined for empty payloads
- picks media payload over error text payload
- treats isError: undefined as non-error
- isHeartbeatOnlyResponse
- returns true for empty payloads
- returns true for a single HEARTBEAT_OK payload
- returns false for a single non-heartbeat payload
- returns true when multiple payloads include narration followed by HEARTBEAT_OK
- returns false when media is present even with HEARTBEAT_OK text
- returns false when media is in a different payload than HEARTBEAT_OK
- returns false when no payload contains HEARTBEAT_OK

### src/cron/isolated-agent/run.cron-model-override.test.lisp
- runCronIsolatedAgentTurn — cron model override (#21057)
- persists cron payload model on session entry even when the run throws
- session entry already carries cron model at pre-run persist time (race condition)
- returns error without persisting model when payload model is disallowed
- persists session-level /model override on session entry before the run
- logs warning and continues when pre-run persist fails
- persists default model pre-run when no payload override is present

### src/cron/isolated-agent/run.interim-retry.test.lisp
- runCronIsolatedAgentTurn — interim ack retry
- regression, retries once when cron returns interim acknowledgement and no descendants were spawned
- does not retry when the first turn is already a concrete result
- does not retry when descendants were spawned in this run even if they already settled

### src/cron/isolated-agent/run.message-tool-policy.test.lisp
- runCronIsolatedAgentTurn message tool policy
- keeps the message tool enabled when delivery.mode is "none"
- disables the message tool when cron delivery is active

### src/cron/isolated-agent/run.payload-fallbacks.test.lisp
- runCronIsolatedAgentTurn — payload.fallbacks

### src/cron/isolated-agent/run.sandbox-config-preserved.test.lisp
- runCronIsolatedAgentTurn sandbox config preserved
- preserves default sandbox config when agent entry omits sandbox
- keeps global sandbox defaults when agent override is partial

### src/cron/isolated-agent/run.session-key.test.lisp
- resolveCronAgentSessionKey
- builds an agent-scoped key for legacy aliases
- preserves canonical agent keys instead of prefixing twice
- normalizes canonical keys to lowercase before reuse
- keeps hook keys scoped under the target agent

### src/cron/isolated-agent/run.skill-filter.test.lisp
- runCronIsolatedAgentTurn — skill filter
- passes agent-level skillFilter to buildWorkspaceSkillSnapshot
- omits skillFilter when agent has no skills config
- passes empty skillFilter when agent explicitly disables all skills
- refreshes cached snapshot when skillFilter changes without version bump
- forces a fresh session for isolated cron runs
- reuses cached snapshot when version and normalized skillFilter are unchanged
- model fallbacks
- preserves defaults when agent overrides primary as string
- preserves defaults when agent overrides primary in object form
- applies payload.model override when model is allowed
- falls back to agent defaults when payload.model is not allowed
- returns an error when payload.model is invalid
- command-line interface session handoff (issue #29774)
- does not pass stored cliSessionId on fresh isolated runs (isNewSession=true)
- reuses stored cliSessionId on continuation runs (isNewSession=false)

### src/cron/isolated-agent/session.test.lisp
- resolveCronSession
- preserves modelOverride and providerOverride from existing session entry
- handles missing modelOverride gracefully
- handles no existing session entry
- session reuse for webhooks/cron
- reuses existing sessionId when session is fresh
- creates new sessionId when session is stale
- creates new sessionId when forceNew is true
- clears delivery routing metadata and deliveryContext when forceNew is true
- clears delivery routing metadata when session is stale
- preserves delivery routing metadata when reusing fresh session
- creates new sessionId when entry exists but has no sessionId

### src/cron/isolated-agent/subagent-followup.test.lisp
- isLikelyInterimCronMessage
- detects 'on it' as interim
- detects subagent-related interim text
- rejects substantive content
- treats empty as interim
- expectsSubagentFollowup
- returns true for subagent spawn hints
- returns false for plain interim text
- returns false for empty string
- readDescendantSubagentFallbackReply
- returns undefined when no descendants exist
- reads reply from child session transcript
- falls back to frozenResultText when session transcript unavailable
- prefers session transcript over frozenResultText
- joins replies from multiple descendants
- skips SILENT_REPLY_TOKEN descendants
- returns undefined when frozenResultText is null
- ignores descendants that ended before run started
- waitForDescendantSubagentSummary
- returns initialReply immediately when no active descendants and observedActiveDescendants=false
- awaits active descendants via agent.wait and returns synthesis after grace period
- returns undefined when descendants finish but only interim text remains after grace period
- returns synthesis even if initial reply was undefined
- uses agent.wait for each active run when multiple descendants exist
- waits for newly discovered active descendants after the first wait round
- handles agent.wait errors gracefully and still reads the synthesis
- skips NO_REPLY synthesis and returns undefined

### src/cron/normalize.test.lisp
- normalizeCronJobCreate
- maps legacy payload.provider to payload.channel and strips provider
- trims agentId and drops null
- trims sessionKey and drops blanks
- canonicalizes payload.channel casing
- coerces ISO schedule.at to normalized ISO (UTC)
- coerces schedule.atMs string to schedule.at (UTC)
- migrates legacy schedule.cron into schedule.expr
- defaults cron stagger for recurring top-of-hour schedules
- preserves explicit exact cron schedule
- defaults deleteAfterRun for one-shot schedules
- normalizes delivery mode and channel
- normalizes delivery accountId and strips blanks
- strips empty accountId from delivery
- normalizes webhook delivery mode and target URL
- defaults isolated agentTurn delivery to announce
- migrates legacy delivery fields to delivery
- maps legacy deliver=false to delivery none
- migrates legacy isolation settings to announce delivery
- infers payload kind/session target and name for message-only jobs
- maps top-level model/thinking/timeout into payload for legacy add params
- preserves timeoutSeconds=0 for no-timeout agentTurn payloads
- coerces sessionTarget and wakeMode casing
- strips invalid delivery mode from partial delivery objects
- normalizeCronJobPatch
- infers agentTurn kind for model-only payload patches
- does not infer agentTurn kind for delivery-only legacy hints
- preserves null sessionKey patches and trims string values
- normalizes cron stagger values in patch schedules

### src/cron/run-log.test.lisp
- cron run log
- resolves prune options from config with defaults
- resolves store path to per-job runs/<jobId>.jsonl
- rejects unsafe job ids when resolving run log path
- appends JSONL and prunes by line count
- reads newest entries and filters by jobId
- ignores invalid and non-finished lines while preserving delivery fields
- reads telemetry fields
- cleans up pending-write bookkeeping after appends complete
- read drains pending fire-and-forget writes

### src/cron/schedule.test.lisp
- cron schedule
- computes next run for cron expression with timezone
- does not roll back year for Asia/Shanghai daily cron schedules (#30351)
- throws a clear error when cron expr is missing at runtime
- supports legacy cron field when expr is missing
- computes next run for every schedule
- computes next run for every schedule when anchorMs is not provided
- handles string-typed everyMs and anchorMs from legacy persisted data
- returns undefined for non-numeric string everyMs
- advances when now matches anchor for every schedule
- never returns a past timestamp for Asia/Shanghai daily schedule (#30351)
- never returns a previous run that is at-or-after now
- reuses compiled cron evaluators for the same expression/timezone
- cron with specific seconds (6-field pattern)
- advances past current second when nowMs is exactly at the match
- advances past current second when nowMs is mid-second (.500) within the match
- advances past current second when nowMs is late in the matching second (.999)
- advances to next day once the matching second is fully past
- returns today when nowMs is before the match
- advances to next day when job completes within same second it fired (#17821)
- advances to next day when job completes just before second boundary (#17821)
- coerceFiniteScheduleNumber
- returns finite numbers directly
- parses numeric strings
- returns undefined for invalid inputs

### src/cron/service.armtimer-tight-loop.test.lisp
- CronService - armTimer tight loop prevention
- enforces a minimum delay when the next wake time is in the past
- does not add extra delay when the next wake time is in the future
- breaks the onTimer→armTimer hot-loop with stuck runningAtMs

### src/cron/service.delivery-plan.test.lisp
- CronService delivery plan consistency
- does not post isolated summary when legacy deliver=false
- treats delivery object without mode as announce
- does not enqueue duplicate relay when isolated run marks delivery handled

### src/cron/service.every-jobs-fire.test.lisp
- CronService interval/cron jobs fire on time
- fires an every-type main job when the timer fires a few ms late
- fires a cron-expression job when the timer fires a few ms late
- keeps legacy every jobs due while minute cron jobs recompute schedules

### src/cron/service.failure-alert.test.lisp
- CronService failure alerts
- alerts after configured consecutive failures and honors cooldown
- supports per-job failure alert override when global alerts are disabled
- respects per-job failureAlert=false and suppresses alerts
- threads failure alert mode/accountId and skips best-effort jobs

### src/cron/service.get-job.test.lisp
- CronService.getJob
- returns added jobs and undefined for missing ids
- preserves webhook delivery on create

### src/cron/service.heartbeat-ok-summary-suppressed.test.lisp
- cron isolated job HEARTBEAT_OK summary suppression (#32013)
- does not enqueue HEARTBEAT_OK as a system event to the main session
- still enqueues real cron summaries as system events

### src/cron/service.issue-13992-regression.test.lisp
- issue #13992 regression - cron jobs skip execution
- should NOT recompute nextRunAtMs for past-due jobs by default
- should recompute past-due nextRunAtMs with recomputeExpired when slot already executed
- should NOT recompute past-due nextRunAtMs for running jobs even with recomputeExpired
- should compute missing nextRunAtMs during maintenance
- should clear nextRunAtMs for disabled jobs during maintenance
- should clear stuck running markers during maintenance
- isolates schedule errors while filling missing nextRunAtMs
- recomputes expired slots already executed but keeps never-executed stale slots
- does not advance overdue never-executed jobs when stale running marker is cleared

### src/cron/service.issue-16156-list-skips-cron.test.lisp
- #16156: cron.list() must not silently advance past-due recurring jobs
- does not skip a cron job when list() is called while the job is past-due
- does not skip a cron job when status() is called while the job is past-due
- still fills missing nextRunAtMs via list() for enabled jobs

### src/cron/service.issue-17852-daily-skip.test.lisp
- issue #17852 - daily cron jobs should not skip days
- recomputeNextRunsForMaintenance should NOT advance past-due nextRunAtMs by default
- recomputeNextRunsForMaintenance can advance expired nextRunAtMs on recovery path when slot already executed
- full recomputeNextRuns WOULD silently advance past-due nextRunAtMs (the bug)

### src/cron/service.issue-19676-at-reschedule.test.lisp
- Cron issue #19676 at-job reschedule
- returns undefined for a completed one-shot job that has not been rescheduled
- returns the new atMs when a completed one-shot job is rescheduled to a future time
- returns the new atMs when rescheduled via legacy numeric atMs field
- returns undefined when rescheduled to a time before the last run
- still returns atMs for a job that has never run
- still returns atMs for a job whose last status is error
- returns undefined for a disabled job even if rescheduled

### src/cron/service.issue-22895-every-next-run.test.lisp
- Cron issue #22895 interval scheduling
- uses lastRunAtMs cadence when the next interval is still in the future
- falls back to anchor scheduling when lastRunAtMs cadence is already in the past

### src/cron/service.issue-35195-backup-timing.test.lisp
- cron backup timing for edit
- keeps .bak as the pre-edit store even after later normalization persists

### src/cron/service.issue-regressions.test.lisp
- Cron issue regressions
- covers schedule updates and payload patching
- repairs isolated every jobs missing createdAtMs and sets nextWakeAtMs
- repairs missing nextRunAtMs on non-schedule updates without touching other jobs
- does not advance unrelated due jobs when updating another job
- treats persisted jobs with missing enabled as enabled during update()
- treats persisted due jobs with missing enabled as runnable
- caps timer delay to 60s for far-future schedules
- re-arms timer without hot-looping when a run is already in progress
- skips forced manual runs while a timer-triggered run is in progress
- does not double-run a job when cron.run overlaps a due timer tick
- manual cron.run preserves unrelated due jobs but advances already-executed stale slots
- keeps telegram delivery target writeback after manual cron.run
- #13845: one-shot jobs with terminal statuses do not re-fire on restart
- #24355: one-shot retries then succeeds (with and without deleteAfterRun)
- #24355: one-shot job disabled after max transient retries
- #24355: one-shot job respects cron.retry config
- #24355: one-shot job retries status-only 529 failures when retryOn only includes overloaded
- #24355: one-shot job disabled immediately on permanent error
- prevents spin loop when cron job completes within the scheduled second (#17821)
- enforces a minimum refire gap for second-granularity cron schedules (#17821)
- treats timeoutSeconds=0 as no timeout for isolated agentTurn jobs
- does not time out agentTurn jobs at the default 10-minute safety window
- aborts isolated runs when cron timeout fires
- suppresses isolated follow-up side effects after timeout
- applies timeoutSeconds to manual cron.run isolated executions
- applies timeoutSeconds to startup catch-up isolated executions
- respects abort signals while retrying main-session wake-now heartbeat runs
- retries cron schedule computation from the next second when the first attempt returns undefined (#17821)
- records per-job start time and duration for batched due jobs
- #17554: run() clears stale runningAtMs and executes the job
- honors cron maxConcurrentRuns for due jobs
- outer cron timeout fires at configured timeoutSeconds, not at 1/3 (#29774)
- keeps state updates when cron next-run computation throws after a successful run (#30905)
- falls back to backoff schedule when cron next-run computation throws on error path (#30905)
- force run preserves 'every' anchor while recording manual lastRunAtMs

### src/cron/service.jobs.test.lisp
- applyJobPatch
- clears delivery when switching to main session
- keeps webhook delivery when switching to main session
- maps legacy payload delivery updates onto delivery
- treats legacy payload targets as announce requests
- merges delivery.accountId from patch and preserves existing
- persists agentTurn payload.lightContext updates when editing existing jobs
- applies payload.lightContext when replacing payload kind via patch
- rejects webhook delivery without a valid http(s) target URL
- trims webhook delivery target URLs
- rejects failureDestination on main jobs without webhook delivery mode
- validates and trims webhook failureDestination target URLs
- rejects Telegram delivery with invalid target (chatId/topicId format)
- accepts Telegram delivery with t.me URL
- accepts Telegram delivery with t.me URL (no https)
- accepts Telegram delivery with valid target (plain chat id)
- accepts Telegram delivery with valid target (colon delimiter)
- accepts Telegram delivery with valid target (topic marker)
- accepts Telegram delivery without target
- accepts Telegram delivery with @username
- createJob rejects sessionTarget main for non-default agents
- allows creating a main-session job for the default agent
- allows creating a main-session job when defaultAgentId matches (case-insensitive)
- rejects creating a main-session job for a non-default agentId
- rejects main-session job for non-default agent even without explicit defaultAgentId
- allows isolated session job for non-default agents
- rejects failureDestination on main jobs without webhook delivery mode
- applyJobPatch rejects sessionTarget main for non-default agents
- rejects patching agentId to non-default on a main-session job
- allows patching agentId to the default agent on a main-session job
- cron stagger defaults
- defaults top-of-hour cron jobs to 5m stagger
- keeps exact schedules when staggerMs is explicitly 0
- preserves existing stagger when editing cron expression without stagger
- applies default stagger when switching from every to top-of-hour cron
- createJob delivery defaults
- defaults delivery to { mode: "announce" } for isolated agentTurn jobs without explicit delivery
- preserves explicit delivery for isolated agentTurn jobs
- does not set delivery for main systemEvent jobs without explicit delivery

### src/cron/service.jobs.top-of-hour-stagger.test.lisp
- computeJobNextRunAtMs top-of-hour staggering
- applies deterministic 0..5m stagger for recurring top-of-hour schedules
- can still fire in the current hour when the staggered slot is ahead
- also applies to 6-field top-of-hour cron expressions
- supports explicit stagger for non top-of-hour cron expressions
- keeps schedules exact when staggerMs is set to 0
- caches stable stagger offsets per job/window

### src/cron/service.list-page-sort-guards.test.lisp
- cron listPage sort guards
- does not throw when sorting by name with malformed name fields
- does not throw when tie-break sorting encounters missing ids

### src/cron/service.main-job-passes-heartbeat-target-last.test.lisp
- cron main job passes heartbeat target=last
- should pass heartbeat.target=last to runHeartbeatOnce for wakeMode=now main jobs
- should not pass heartbeat target for wakeMode=next-heartbeat main jobs

### src/cron/service.persists-delivered-status.test.lisp
- CronService persists delivered status
- persists lastDelivered=true when isolated job reports delivered
- persists lastDelivered=false when isolated job explicitly reports not delivered
- persists not-requested delivery state when delivery is not configured
- persists unknown delivery state when delivery is requested but the runner omits delivered
- does not set lastDelivered for main session jobs
- emits delivered in the finished event

### src/cron/service.prevents-duplicate-timers.test.lisp
- CronService
- avoids duplicate runs when two services share a store

### src/cron/service.read-ops-nonblocking.test.lisp
- CronService read ops while job is running
- keeps list and status responsive during a long isolated run
- keeps list and status responsive during manual cron.run execution
- keeps list and status responsive during startup catch-up runs

### src/cron/service.rearm-timer-when-running.test.lisp
- CronService - timer re-arm when running (#12025)
- re-arms the timer when onTimer is called while state.running is true
- arms a watchdog timer while a timer tick is still executing

### src/cron/service.restart-catchup.test.lisp
- CronService restart catch-up
- executes an overdue recurring job immediately on start
- clears stale running markers without replaying interrupted startup jobs
- replays the most recent missed cron slot after restart when nextRunAtMs already advanced
- does not replay interrupted one-shot jobs on startup
- does not replay cron slot when the latest slot already ran before restart
- does not replay missed cron slots while error backoff is pending after restart
- replays missed cron slot after restart when error backoff has already elapsed

### src/cron/service.runs-one-shot-main-job-disables-it.test.lisp
- CronService
- runs a one-shot main job and disables it after success when requested
- runs a one-shot job and deletes it after success by default
- wakeMode now waits for heartbeat completion when available
- rejects sessionTarget main for non-default agents at creation time
- wakeMode now falls back to queued heartbeat when main lane stays busy
- runs an isolated job and posts summary to main
- does not post isolated summary to main when run already delivered output
- does not post isolated summary to main when announce delivery was attempted
- migrates legacy payload.provider to payload.channel on load
- canonicalizes payload.channel casing on load
- posts last output to main even when isolated job errors
- does not post fallback main summary for isolated delivery-target errors
- rejects unsupported session/payload combinations
- skips invalid main jobs with agentTurn payloads from disk

### src/cron/service.session-reaper-in-finally.test.lisp
- CronService - session reaper runs in finally block (#31946)
- session reaper runs even when job execution throws
- session reaper runs when resolveSessionStorePath is provided
- prunes expired cron-run sessions even when cron store load throws

### src/cron/service.skips-main-jobs-empty-systemevent-text.test.lisp
- CronService
- skips main jobs with empty systemEvent text
- does not schedule timers when cron is disabled
- status reports next wake when enabled

### src/cron/service.store-migration.test.lisp
- CronService store migrations
- migrates legacy top-level agentTurn fields and initializes missing state
- preserves legacy timeoutSeconds=0 during top-level agentTurn field migration
- migrates legacy cron fields (jobId + schedule.cron) and defaults wakeMode

### src/cron/service.store.migration.test.lisp
- cron store migration
- migrates isolated jobs to announce delivery and drops isolation
- adds anchorMs to legacy every schedules
- adds default staggerMs to legacy recurring top-of-hour cron schedules
- adds default staggerMs to legacy 6-field top-of-hour cron schedules
- removes invalid legacy staggerMs from non top-of-hour cron schedules
- migrates legacy string schedules and command-only payloads (#18445)

### src/cron/service/jobs.schedule-error-isolation.test.lisp
- cron schedule error isolation
- continues processing other jobs when one has a malformed schedule
- logs a warning for the first schedule error
- auto-disables job after 3 consecutive schedule errors
- clears scheduleErrorCount when schedule computation succeeds
- does not modify disabled jobs
- increments error count on each failed computation
- stores error message in lastError
- records a clear schedule error when cron expr is missing

### src/cron/service/timeout-policy.test.lisp
- timeout-policy
- uses default timeout for non-agent jobs
- uses expanded safety timeout for agentTurn jobs without explicit timeout
- disables timeout when timeoutSeconds <= 0
- applies explicit timeoutSeconds when positive

### src/cron/session-reaper.test.lisp
- resolveRetentionMs
- returns 24h default when no config
- returns 24h default when config is empty
- parses duration string
- returns null when disabled
- falls back to default on invalid string
- isCronRunSessionKey
- matches cron run session keys
- does not match base cron session keys
- does not match regular session keys
- does not match non-canonical cron-like keys
- sweepCronRunSessions
- prunes expired cron run sessions
- archives transcript files for pruned run sessions that are no longer referenced
- does not archive external transcript paths for pruned runs
- respects custom retention
- does nothing when pruning is disabled
- throttles sweeps without force
- throttles per store path

### src/cron/stagger.test.lisp
- cron stagger helpers
- detects recurring top-of-hour cron expressions for 5-field and 6-field cron
- normalizes explicit stagger values
- resolves effective stagger for cron schedules
- handles missing runtime expr values without throwing

### src/cron/store.test.lisp
- resolveCronStorePath
- uses OPENCLAW_HOME for tilde expansion
- cron store
- returns empty store when file does not exist
- throws when store contains invalid JSON
- does not create a backup file when saving unchanged content
- backs up previous content before replacing the store
- saveCronStore
- persists and round-trips a store file
- retries rename on EBUSY then succeeds
- falls back to copyFile on EPERM (Windows)

## daemon

### src/daemon/cmd-argv.test.lisp
- cmd argv helpers
- round-trips mixed command lines
- rejects CR/LF in command arguments

### src/daemon/constants.test.lisp
- normalizeGatewayProfile
- returns null for empty/default profiles
- returns trimmed custom profiles
- resolveGatewayLaunchAgentLabel
- returns default label when no profile is set
- returns profile-specific label when profile is set
- resolveGatewaySystemdServiceName
- returns default service name when no profile is set
- returns profile-specific service name when profile is set
- resolveGatewayWindowsTaskName
- returns default task name when no profile is set
- returns profile-specific task name when profile is set
- resolveGatewayProfileSuffix
- returns empty string when no profile is set
- returns empty string for default profiles
- returns a hyphenated suffix for custom profiles
- trims whitespace from profiles
- formatGatewayServiceDescription
- returns default description when no profile/version
- includes profile when set
- includes version when set
- includes profile and version when set
- resolveGatewayServiceDescription
- prefers explicit description override
- resolves version from explicit environment map
- LEGACY_GATEWAY_SYSTEMD_SERVICE_NAMES
- includes known pre-rebrand gateway unit names

### src/daemon/inspect.test.lisp
- findExtraGatewayServices (win32)
- skips schtasks queries unless deep mode is enabled
- returns empty results when schtasks query fails
- collects only non-openclaw marker tasks from schtasks output

### src/daemon/launchd.integration.e2e.test.lisp
- restarts launchd service and keeps it running with a new pid

### src/daemon/launchd.test.lisp
- launchd runtime parsing
- parses state, pid, and exit status
- does not set pid when pid = 0
- sets pid for positive values
- does not set pid for negative values
- rejects pid and exit status values with junk suffixes
- launchctl list detection
- detects the resolved label in launchctl list
- returns false when the label is missing
- launchd bootstrap repair
- bootstraps and kickstarts the resolved label
- launchd install
- enables service before bootstrap (clears persisted disabled state)
- writes TMPDIR to LaunchAgent environment when provided
- writes KeepAlive=true policy with restrictive umask
- restarts LaunchAgent with bootout-bootstrap-kickstart order
- waits for previous launchd pid to exit before bootstrapping
- shows actionable guidance when launchctl gui domain does not support bootstrap
- surfaces generic bootstrap failures without GUI-specific guidance
- resolveLaunchAgentPlistPath

### src/daemon/program-args.test.lisp
- resolveGatewayProgramArguments
- uses realpath-resolved dist entry when running via npx shim
- prefers symlinked path over realpath for stable service config
- falls back to node_modules package dist when .bin path is not resolved

### src/daemon/runtime-binary.test.lisp
- isNodeRuntime
- recognizes standard sbcl binaries
- recognizes versioned sbcl binaries with and without dashes
- handles quotes and casing
- rejects non-sbcl runtimes
- isBunRuntime
- recognizes bun binaries
- rejects non-bun runtimes

### src/daemon/runtime-hints.test.lisp
- buildPlatformRuntimeLogHints
- renders launchd log hints on darwin
- renders systemd and windows hints by platform
- buildPlatformServiceStartHints
- builds platform-specific service start hints

### src/daemon/runtime-hints.windows-paths.test.lisp
- buildPlatformRuntimeLogHints
- strips windows drive prefixes from darwin display paths

### src/daemon/runtime-paths.test.lisp
- resolvePreferredNodePath
- prefers execPath (version manager sbcl) over system sbcl
- falls back to system sbcl when execPath version is unsupported
- ignores execPath when it is not sbcl
- uses system sbcl when it meets the minimum version
- skips system sbcl when it is too old
- returns undefined when no system sbcl is found
- resolveStableNodePath
- resolves Homebrew Cellar path to opt symlink
- falls back to bin symlink for default sbcl formula
- resolves Intel Mac Cellar path to opt symlink
- resolves versioned sbcl@22 formula to opt symlink
- returns original path when no stable symlink exists
- returns non-Cellar paths unchanged
- returns system paths unchanged
- resolvePreferredNodePath — Homebrew Cellar
- resolves Cellar execPath to stable Homebrew symlink
- resolveSystemNodeInfo
- returns supported info when version is new enough
- returns undefined when system sbcl is missing
- renders a warning when system sbcl is too old

### src/daemon/schtasks.install.test.lisp
- installScheduledTask
- writes quoted set assignments and escapes metacharacters
- rejects line breaks in command arguments, env vars, and descriptions
- does not persist a frozen PATH snapshot into the generated task script

### src/daemon/schtasks.test.lisp
- schtasks runtime parsing
- scheduled task runtime derivation
- treats Running + 0x41301 as running
- treats Running + decimal 267009 as running
- treats Running without numeric result as unknown
- treats non-running result codes as stopped
- detects running via result code when status is localized (German)
- detects running via result code when status is localized (French)
- treats localized status as stopped when result code is not a running code
- treats localized status without result code as unknown
- resolveTaskScriptPath
- readScheduledTaskCommand
- parses script with quoted arguments containing spaces
- returns null when script does not exist
- returns null when script has no command
- parses full script with all components
- parses command with Windows backslash paths
- preserves UNC paths in command arguments
- reads script from OPENCLAW_STATE_DIR override
- parses quoted set assignments with escaped metacharacters

### src/daemon/service-audit.test.lisp
- auditGatewayServiceConfig
- flags bun runtime
- flags version-managed sbcl paths
- accepts Linux minimal PATH with user directories
- flags gateway token mismatch when service token is stale
- flags embedded service token even when it matches config token
- does not flag token issues when service token is not embedded
- does not treat EnvironmentFile-backed tokens as embedded
- checkTokenDrift
- returns null when both tokens are undefined
- returns null when both tokens are empty strings
- returns null when tokens match
- returns null when tokens match but service token has trailing newline
- returns null when tokens match but have surrounding whitespace
- returns null when both tokens have different whitespace padding
- detects drift when config has token but service has different token
- returns null when config has token but service has no token
- returns null when service has token but config does not

### src/daemon/service-env.test.lisp
- getMinimalServicePathParts - Linux user directories
- includes user bin directories when HOME is set on Linux
- excludes user bin directories when HOME is undefined on Linux
- places user directories before system directories on Linux
- places extraDirs before user directories on Linux
- includes env-configured bin roots when HOME is set on Linux
- includes version manager directories on macOS when HOME is set
- includes env-configured version manager dirs on macOS
- places version manager dirs before system dirs on macOS
- does not include Linux user directories on Windows
- buildMinimalServicePath
- includes Homebrew + system dirs on macOS
- returns PATH as-is on Windows
- includes Linux user directories when HOME is set in env
- excludes Linux user directories when HOME is not in env
- ensures user directories come before system directories on Linux
- includes extra directories when provided
- deduplicates directories
- buildServiceEnvironment
- sets minimal PATH and gateway vars
- forwards TMPDIR from the host environment
- falls back to os.tmpdir when TMPDIR is not set
- uses profile-specific unit and label
- forwards proxy environment variables for launchd/systemd runtime
- omits PATH on Windows so Scheduled Tasks can inherit the current shell path
- buildNodeServiceEnvironment
- passes through HOME for sbcl services
- passes through OPENCLAW_GATEWAY_TOKEN for sbcl services
- maps legacy CLAWDBOT_GATEWAY_TOKEN to OPENCLAW_GATEWAY_TOKEN for sbcl services
- prefers OPENCLAW_GATEWAY_TOKEN over legacy CLAWDBOT_GATEWAY_TOKEN
- omits OPENCLAW_GATEWAY_TOKEN when both token env vars are empty
- forwards proxy environment variables for sbcl services
- forwards TMPDIR for sbcl services
- falls back to os.tmpdir for sbcl services when TMPDIR is not set
- shared Node TLS env defaults
- resolveGatewayStateDir
- uses the default state dir when no overrides are set
- appends the profile suffix when set
- treats default profiles as the base state dir
- uses OPENCLAW_STATE_DIR when provided
- expands ~ in OPENCLAW_STATE_DIR
- preserves Windows absolute paths without HOME

### src/daemon/service.test.lisp
- resolveGatewayService
- throws for unsupported platforms

### src/daemon/systemd-hints.test.lisp
- isSystemdUnavailableDetail
- matches systemd unavailable error details
- renderSystemdUnavailableHints
- renders WSL2-specific recovery hints
- renders generic Linux recovery hints outside WSL

### src/daemon/systemd-unit.test.lisp
- buildSystemdUnit
- quotes arguments with whitespace
- renders control-group kill mode for child-process cleanup
- rejects environment values with line breaks

### src/daemon/systemd.test.lisp
- systemd availability
- returns true when systemctl --user succeeds
- returns false when systemd user bus is unavailable
- returns true when systemd is degraded but still reachable
- falls back to machine user scope when --user bus is unavailable
- isSystemdServiceEnabled
- returns false when systemctl is not present
- returns false without calling systemctl when the managed unit file is missing
- calls systemctl is-enabled when systemctl is present
- returns false when systemctl reports disabled
- returns false for the WSL2 Ubuntu 24.04 wrapper-only is-enabled failure
- returns false when is-enabled cannot connect to the user bus without machine fallback
- returns false when both direct and machine-scope is-enabled checks report bus unavailability
- throws when generic wrapper errors report infrastructure failures
- throws when systemctl is-enabled fails for non-state errors
- returns false when systemctl is-enabled exits with code 4 (not-found)
- isNonFatalSystemdInstallProbeError
- matches wrapper-only WSL install probe failures
- matches bus-unavailable install probe failures
- does not match real infrastructure failures
- systemd runtime parsing
- parses active state details
- rejects pid and exit status values with junk suffixes
- resolveSystemdUserUnitPath
- splitArgsPreservingQuotes
- splits on whitespace outside quotes
- supports systemd-style backslash escaping
- supports schtasks-style escaped quotes while preserving other backslashes
- parseSystemdExecStart
- preserves quoted arguments
- readSystemdServiceExecStart
- loads OPENCLAW_GATEWAY_TOKEN from EnvironmentFile
- lets EnvironmentFile override inline Environment values
- ignores missing optional EnvironmentFile entries
- keeps parsing when non-optional EnvironmentFile entries are missing
- supports multiple EnvironmentFile entries and quoted paths
- resolves relative EnvironmentFile paths from the unit directory
- parses EnvironmentFile content with comments and quoted values
- systemd service control
- stops the resolved user unit
- allows stop when systemd status is degraded but available
- restarts a profile-specific user unit
- surfaces stop failures with systemctl detail
- throws the user-bus error before stop when systemd is unavailable
- targets the sudo caller's user scope when SUDO_USER is set
- keeps direct --user scope when SUDO_USER is root
- falls back to machine user scope for restart when user bus env is missing

## discord

### src/discord/account-inspect.test.lisp
- inspectDiscordAccount
- prefers account token over channel token and strips Bot prefix
- reports configured_unavailable for unresolved configured secret input
- does not fall back when account token key exists but is missing
- falls back to channel token when account token is absent
- allows env token only for default account

### src/discord/accounts.test.lisp
- resolveDiscordAccount allowFrom precedence
- prefers accounts.default.allowFrom over top-level for default account
- falls back to top-level allowFrom for named account without override
- does not inherit default account allowFrom for named account when top-level is absent

### src/discord/api.test.lisp
- fetchDiscord
- formats rate limit payloads without raw JSON
- preserves non-JSON error text
- retries rate limits before succeeding

### src/discord/audit.test.lisp
- discord audit
- collects numeric channel ids and counts unresolved keys
- does not count '*' wildcard key as unresolved channel
- handles guild with only '*' wildcard and no numeric channel ids
- collects audit channel ids without resolving SecretRef-backed Discord tokens

### src/discord/chunk.test.lisp
- chunkDiscordText
- splits tall messages even when under 2000 chars
- keeps fenced code blocks balanced across chunks
- keeps fenced blocks intact when chunkMode is newline
- reserves space for closing fences when chunking
- preserves whitespace when splitting long lines
- preserves mixed whitespace across chunk boundaries
- keeps leading whitespace when splitting long lines
- keeps reasoning italics balanced across chunks
- keeps reasoning italics balanced when chunks split by char limit
- reopens italics while preserving leading whitespace on following chunk

### src/discord/components.test.lisp
- discord components
- builds v2 containers with modal trigger
- requires options for modal select fields
- requires attachment references for file blocks
- discord component registry
- registers and consumes component entries

### src/discord/directory-live.test.lisp
- discord directory live lookups
- returns empty group directory when token is missing
- returns empty peer directory without query and skips guild listing
- filters group channels by query and respects limit
- returns ranked peer results and caps member search by limit

### src/discord/gateway-logging.test.lisp
- attachDiscordGatewayLogging
- logs debug events and promotes reconnect/close to info
- logs warnings and metrics only to verbose
- removes listeners on cleanup

### src/discord/mentions.test.lisp
- formatMention
- formats user mentions from ids
- formats role mentions from ids
- formats channel mentions from ids
- throws when no mention id is provided
- throws when more than one mention id is provided
- rewriteDiscordKnownMentions
- rewrites @name mentions when a cached user id exists
- preserves unknown mentions and reserved mentions
- does not rewrite mentions inside markdown code spans
- is account-scoped

### src/discord/monitor.gateway.test.lisp
- waitForDiscordGatewayStop
- resolves on abort and disconnects gateway
- rejects on gateway error and disconnects
- ignores gateway errors when instructed
- resolves on abort without a gateway
- rejects via registerForceStop and disconnects gateway
- ignores forceStop after promise already settled

### src/discord/monitor.test.lisp
- registerDiscordListener
- dedupes listeners by constructor
- DiscordMessageListener
- returns immediately while handler continues in background
- dispatches subsequent events concurrently without blocking on prior handler
- logs handler failures
- does not apply its own slow-listener logging (owned by inbound worker)
- discord allowlist helpers
- normalizes slugs
- matches ids by default and names only when enabled
- matches pk-prefixed allowlist entries
- discord guild/channel resolution
- resolves guild entry by id
- resolves guild entry by slug key
- falls back to wildcard guild entry
- resolves channel config by slug
- denies channel when config present but no match
- treats empty channel config map as no channel allowlist
- inherits parent config for thread channels
- does not match thread name/slug when resolving allowlists
- applies wildcard channel config when no specific match
- falls back to wildcard when thread channel and parent are missing
- treats empty channel config map as no thread allowlist
- discord mention gating
- requires mention by default
- applies autoThread mention rules based on thread ownership
- inherits parent channel mention rules for threads
- discord groupPolicy gating
- applies open/disabled/allowlist policy rules
- discord group DM gating
- allows all when no allowlist
- matches group DM allowlist
- discord reply target selection
- handles off/first/all reply modes
- discord autoThread name sanitization
- strips mentions and collapses whitespace
- falls back to thread + id when empty after cleaning
- discord reaction notification gating
- applies mode-specific reaction notification rules
- discord media payload
- preserves attachment order for MediaPaths/MediaUrls
- discord DM reaction handling
- processes DM reactions with or without guild allowlists
- blocks DM reactions when dmPolicy is disabled
- blocks DM reactions for unauthorized sender in allowlist mode
- allows DM reactions for authorized sender in allowlist mode
- blocks group DM reactions when group DMs are disabled
- blocks guild reactions when groupPolicy is disabled
- still processes guild reactions (no regression)
- routes DM reactions with peer kind 'direct' and user id
- routes group DM reactions with peer kind 'group'
- discord reaction notification modes
- applies message-fetch behavior across notification modes and channel types

### src/discord/monitor.tool-result.accepts-guild-messages-mentionpatterns-match.e2e.test.lisp
- discord tool result dispatch
- accepts guild messages when mentionPatterns match
- skips tool results for native slash commands
- accepts guild reply-to-bot messages as implicit mentions
- forks thread sessions and injects starter context
- skips thread starter context when disabled
- treats forum threads as distinct sessions without channel payloads
- scopes thread sessions to the routed agent

### src/discord/monitor.tool-result.sends-status-replies-responseprefix.test.lisp
- discord tool result dispatch
- uses channel id allowlists for non-thread channels with categories
- prefixes group bodies with sender label
- replies with pairing code and sender id when dmPolicy is pairing

### src/discord/monitor/agent-components.wildcard.test.lisp
- discord wildcard component registration ids
- uses distinct sentinel customIds instead of a shared literal wildcard
- still resolves sentinel ids and runtime ids through wildcard parser key

### src/discord/monitor/auto-presence.test.lisp
- discord auto presence
- maps exhausted runtime signal to dnd
- treats overloaded cooldown as exhausted
- recovers from exhausted to online once a profile becomes usable
- re-applies presence on refresh even when signature is unchanged
- does nothing when auto presence is disabled

### src/discord/monitor/commands.test.lisp
- resolveDiscordSlashCommandConfig
- defaults ephemeral to true when undefined
- defaults ephemeral to true when not explicitly false
- sets ephemeral to false when explicitly false
- keeps ephemeral true when explicitly true

### src/discord/monitor/dm-command-auth.test.lisp
- resolveDiscordDmCommandAccess
- allows open DMs and keeps command auth enabled without allowlist entries
- marks command auth true when sender is allowlisted
- keeps command auth enabled for open DMs when configured allowlist does not match
- returns pairing decision and unauthorized command auth for unknown senders
- authorizes sender from pairing-store allowlist entries
- keeps open DM command auth true when access groups are disabled

### src/discord/monitor/dm-command-decision.test.lisp
- handleDiscordDmCommandDecision
- returns true for allowed DM access
- creates pairing reply for new pairing requests
- skips pairing reply when pairing request already exists
- runs unauthorized handler for blocked DM access

### src/discord/monitor/exec-approvals.test.lisp
- buildExecApprovalCustomId
- encodes approval id and action
- encodes special characters in approval id
- parseExecApprovalData
- parses valid data
- parses encoded data
- rejects invalid action
- rejects missing id
- rejects missing action
- rejects null/undefined input
- accepts all valid actions
- roundtrip encoding
- encodes and decodes correctly
- extractDiscordChannelId
- extracts channel IDs and rejects invalid session key inputs
- DiscordExecApprovalHandler.shouldHandle
- returns false when disabled
- returns false when no approvers
- returns true with minimal config
- filters by agent ID
- filters by session key substring
- filters by session key regex
- rejects unsafe nested-repetition regex in session filter
- matches long session keys with tail-bounded regex checks
- filters by discord account when session store includes account
- combines agent and session filters
- DiscordExecApprovalHandler.getApprovers
- returns approvers for configured, empty, and undefined lists
- ExecApprovalButton
- denies unauthorized users with ephemeral message
- allows authorized user and resolves approval
- shows correct label for allow-always
- shows correct label for deny
- handles invalid data gracefully
- follows up with error when resolve fails
- matches approvers with string coercion
- DiscordExecApprovalHandler target config
- accepts all target modes and defaults to dm when target is omitted
- DiscordExecApprovalHandler gateway auth
- passes the shared gateway token from config into GatewayClient
- prefers OPENCLAW_GATEWAY_TOKEN when config token is missing
- DiscordExecApprovalHandler timeout cleanup
- cleans up request cache for the exact approval id
- DiscordExecApprovalHandler delivery routing
- falls back to DM delivery when channel target has no channel id
- DiscordExecApprovalHandler gateway auth resolution
- passes command-line interface URL overrides to shared gateway auth resolver
- passes env URL overrides to shared gateway auth resolver

### src/discord/monitor/gateway-error-guard.test.lisp
- attachEarlyGatewayErrorGuard
- captures gateway errors until released
- returns noop guard when gateway emitter is unavailable

### src/discord/monitor/inbound-context.test.lisp
- Discord inbound context helpers
- builds guild access context from channel config and topic
- omits guild-only metadata for direct messages
- keeps direct helper behavior consistent

### src/discord/monitor/inbound-job.test.lisp
- buildDiscordInboundJob
- keeps live runtime references out of the payload
- re-materializes the process context with an overridden abort signal
- preserves Carbon message getters across queued jobs

### src/discord/monitor/listeners.test.lisp
- DiscordMessageListener
- returns immediately without awaiting handler completion
- runs handlers for the same channel concurrently (no per-channel serialization)
- runs handlers for different channels in parallel
- logs async handler failures
- calls onEvent callback for each message

### src/discord/monitor/message-handler.bot-self-filter.test.lisp
- createDiscordMessageHandler bot-self filter
- skips bot-own messages before the debounce queue
- enqueues non-bot messages for processing

### src/discord/monitor/message-handler.inbound-contract.test.lisp
- discord processDiscordMessage inbound contract
- passes a finalized MsgContext to dispatchInboundMessage
- keeps channel metadata out of GroupSystemPrompt

### src/discord/monitor/message-handler.preflight.acp-bindings.test.lisp
- preflightDiscordMessage configured ACP bindings
- does not initialize configured ACP bindings for rejected messages
- initializes configured ACP bindings only after preflight accepts the message

### src/discord/monitor/message-handler.preflight.test.lisp
- resolvePreflightMentionRequirement
- requires mention when config requires mention and thread is not bound
- disables mention requirement for bound thread sessions
- keeps mention requirement disabled when config already disables it
- preflightDiscordMessage
- drops bound-thread bot system messages to prevent ACP self-loop
- keeps bound-thread regular bot messages flowing when allowBots=true
- bypasses mention gating in bound threads for allowed bot senders
- drops bot messages without mention when allowBots=mentions
- allows bot messages with explicit mention when allowBots=mentions
- drops guild messages that mention another user when ignoreOtherMentions=true
- does not drop @everyone messages when ignoreOtherMentions=true
- ignores bot-sent @everyone mentions for detection
- uses attachment content_type for guild audio preflight mention detection
- shouldIgnoreBoundThreadWebhookMessage
- returns true when inbound webhook id matches the bound thread webhook
- returns false when webhook ids differ
- returns false when there is no bound thread webhook
- returns true for recently unbound thread webhook echoes

### src/discord/monitor/message-handler.process.test.lisp
- processDiscordMessage ack reactions
- skips ack reactions for group-mentions when mentions are not required
- sends ack reactions for mention-gated guild messages when mentioned
- uses preflight-resolved messageChannelId when message.channelId is missing
- debounces intermediate phase reactions and jumps to done for short runs
- shows stall emojis for long no-progress runs
- applies status reaction emoji/timing overrides from config
- clears status reactions when dispatch aborts and removeAckAfterReply is enabled
- processDiscordMessage session routing
- stores DM lastRoute with user target for direct-session continuity
- stores group lastRoute with channel target
- prefers bound session keys and sets MessageThreadId for bound thread messages
- processDiscordMessage draft streaming
- finalizes via preview edit when final fits one chunk
- accepts streaming=true alias for partial preview mode
- falls back to standard send when final needs multiple chunks
- suppresses reasoning payload delivery to Discord
- suppresses reasoning-tagged final payload delivery to Discord
- delivers non-reasoning block payloads to Discord
- streams block previews using draft chunking
- forces new preview messages on assistant boundaries in block mode
- strips reasoning tags from partial stream updates
- skips pure-reasoning partial updates without updating draft

### src/discord/monitor/message-handler.queue.test.lisp
- createDiscordMessageHandler queue behavior
- resets busy counters when the handler is created
- returns immediately and tracks busy status while queued runs execute
- applies explicit inbound worker timeout to queued runs so stalled runs do not block the queue
- does not time out queued runs when the inbound worker timeout is disabled
- refreshes run activity while active runs are in progress
- stops status publishing after lifecycle abort
- stops status publishing after handler deactivation
- skips queued runs that have not started yet after deactivation
- preserves non-debounced message ordering by awaiting debouncer enqueue
- recovers queue progress after a run failure without leaving busy state stuck

### src/discord/monitor/message-utils.test.lisp
- resolveDiscordMessageChannelId
- resolveForwardedMediaList
- downloads forwarded attachments
- forwards fetchImpl to forwarded attachment downloads
- keeps forwarded attachment metadata when download fails
- downloads forwarded stickers
- returns empty when no snapshots are present
- skips snapshots without attachments
- resolveMediaList
- downloads stickers
- forwards fetchImpl to sticker downloads
- keeps attachment metadata when download fails
- falls back to URL when saveMediaBuffer fails
- preserves downloaded attachments alongside failed ones
- keeps sticker metadata when sticker download fails
- Discord media SSRF policy
- passes Discord CDN hostname allowlist with RFC2544 enabled
- merges provided ssrfPolicy with Discord CDN defaults
- resolveDiscordMessageText
- includes forwarded message snapshots in body text
- resolves user mentions in content
- leaves content unchanged if no mentions present
- uses sticker placeholders when content is empty
- uses embed title when content is empty
- uses embed description when content is empty
- joins embed title and description when content is empty
- prefers message content over embed fallback text
- joins forwarded snapshot embed title and description when content is empty
- resolveDiscordChannelInfo
- caches channel lookups between calls
- negative-caches missing channels

### src/discord/monitor/model-picker-preferences.test.lisp
- discord model picker preferences
- records recent models in recency order without duplicates
- filters recent models using an allowlist
- falls back to an empty store when the file is corrupt

### src/discord/monitor/model-picker.test.lisp
- loadDiscordModelPickerData
- reuses buildModelsProviderData as source of truth with agent scope
- Discord model picker custom_id
- encodes and decodes command/provider/page/user context
- parses component data payloads
- parses compact custom_id aliases
- parses optional submit model index
- rejects invalid command/action/view values
- enforces Discord custom_id max length
- keeps typical submit ids under Discord max length
- provider paging
- keeps providers on a single page when count fits Discord button rows
- paginates providers when count exceeds one-page Discord button limits
- caps custom provider page size at Discord-safe max
- model paging
- sorts models and paginates with Discord select-option constraints
- returns null for unknown provider
- caps custom model page size at Discord select-option max
- Discord model picker rendering
- renders provider view on one page when provider count is <= 25
- does not render navigation buttons even when provider count exceeds one page
- supports classic fallback rendering with content + action rows
- renders model view with select menu and explicit submit button
- renders not-found model view with a back button
- shows Recents button when quickModels are provided
- omits Recents button when no quickModels
- Discord model picker recents view
- renders one button per model with back button after divider
- includes (default) suffix on default model button label
- deduplicates recents that match the default model

### src/discord/monitor/monitor.test.lisp
- agent components
- sends pairing reply when DM sender is not allowlisted
- blocks DM interactions when only pairing store entries match in allowlist mode
- matches tag-based allowlist entries for DM select menus
- accepts cid payloads for agent button interactions
- keeps malformed percent cid values without throwing
- discord component interactions
- routes button clicks with reply references
- keeps reusable buttons active after use
- blocks buttons when allowedUsers does not match
- routes modal submissions with field values
- does not mark guild modal events as command-authorized for non-allowlisted users
- marks guild modal events as command-authorized for allowlisted users
- keeps reusable modal entries active after submission
- resolveDiscordOwnerAllowFrom
- returns undefined when no allowlist is configured
- skips wildcard matches for owner allowFrom
- returns a matching user id entry
- returns the normalized name slug for name matches only when enabled
- resolveDiscordRoleAllowed
- allows when no role allowlist is configured
- matches role IDs only
- does not match non-ID role entries
- returns false when no matching role IDs
- resolveDiscordMemberAllowed
- allows when no user or role allowlists are configured
- allows when user allowlist matches
- allows when role allowlist matches
- denies when user and role allowlists do not match
- gateway-registry
- stores and retrieves a gateway by account
- uses collision-safe key when accountId is undefined
- unregisters a gateway
- clears all gateways
- overwrites existing entry for same account
- presence-cache
- scopes presence entries by account
- clears presence per account
- resolveDiscordPresenceUpdate
- returns default online presence when no presence config provided
- returns status-only presence when activity is omitted
- defaults to custom activity type when activity is set without type
- includes streaming url when activityType is streaming
- resolveDiscordAutoThreadContext
- returns null without a created thread and re-keys context when present
- resolveDiscordReplyDeliveryPlan
- applies delivery targets and reply reference behavior across thread modes
- maybeCreateDiscordAutoThread
- handles create-thread failures with and without an existing thread
- resolveDiscordAutoThreadReplyPlan
- applies auto-thread reply planning across created, existing, and disabled modes

### src/discord/monitor/native-command-context.test.lisp
- buildDiscordNativeCommandContext
- builds direct-message slash command context
- builds guild slash command context with owner allowlist and channel metadata

### src/discord/monitor/native-command.commands-allowfrom.test.lisp
- Discord native slash commands with commands.allowFrom
- authorizes guild slash commands when commands.allowFrom.discord matches the sender
- authorizes guild slash commands from the global commands.allowFrom list when provider-specific allowFrom is missing
- authorizes guild slash commands when commands.useAccessGroups is false and commands.allowFrom.discord matches the sender
- rejects guild slash commands when commands.allowFrom.discord does not match the sender
- rejects guild slash commands when commands.useAccessGroups is false and commands.allowFrom.discord does not match the sender

### src/discord/monitor/native-command.model-picker.test.lisp
- Discord model picker interactions
- registers distinct fallback ids for button and select handlers
- ignores interactions from users other than the picker owner
- requires submit click before routing selected model through /model pipeline
- shows timeout status and skips recents write when apply is still processing
- clicking Recents button renders recents view
- clicking recents model button applies model through /model pipeline
- verifies model state against the bound thread session

### src/discord/monitor/native-command.options.test.lisp
- createDiscordNativeCommand option wiring
- uses autocomplete for /acp action so inline action values are accepted
- keeps static choices for non-acp string action arguments

### src/discord/monitor/native-command.plugin-dispatch.test.lisp
- Discord native plugin command dispatch
- executes matched plugin commands directly without invoking the agent dispatcher
- routes native slash commands through configured ACP Discord channel bindings
- falls back to the routed slash and channel session keys when no bound session exists
- routes Discord DM native slash commands through configured ACP bindings

### src/discord/monitor/presence.test.lisp
- resolveDiscordPresenceUpdate
- returns online presence when no config is provided
- uses configured status
- includes activity when configured
- uses custom activity type by default
- respects explicit activityType
- sets streaming URL for type 1

### src/discord/monitor/provider.allowlist.test.lisp
- resolveDiscordAllowlistConfig
- canonicalizes resolved user names to ids in runtime config
- logs discord name metadata for resolved and unresolved allowlist entries

### src/discord/monitor/provider.group-policy.test.lisp
- resolveDiscordRuntimeGroupPolicy
- fails closed when channels.discord is missing and no defaults are set
- keeps open default when channels.discord is configured
- respects explicit provider policy
- ignores explicit global defaults when provider config is missing

### src/discord/monitor/provider.lifecycle.test.lisp
- runDiscordGatewayLifecycle
- cleans up thread bindings when exec approvals startup fails
- cleans up when gateway wait fails after startup
- cleans up after successful gateway wait
- pushes connected status when gateway is already connected at lifecycle start
- handles queued disallowed intents errors without waiting for gateway events
- throws queued non-disallowed fatal gateway errors
- retries stalled HELLO with resume before forcing fresh identify
- resets HELLO stall counter after a successful reconnect that drops quickly
- force-stops when reconnect stalls after a close event
- does not force-stop when reconnect resumes before watchdog timeout
- does not push connected: true when abortSignal is already aborted

### src/discord/monitor/provider.proxy.test.lisp
- createDiscordGatewayPlugin
- uses proxy agent for gateway WebSocket when configured
- falls back to the default gateway plugin when proxy is invalid
- uses proxy fetch for gateway metadata lookup before registering

### src/discord/monitor/provider.rest-proxy.test.lisp
- resolveDiscordRestFetch
- uses undici proxy fetch when a proxy URL is configured
- falls back to global fetch when proxy URL is invalid

### src/discord/monitor/provider.skill-dedupe.test.lisp
- resolveThreadBindingsEnabled
- defaults to enabled when unset
- uses global session default when channel value is unset
- uses channel value to override global session default

### src/discord/monitor/provider.test.lisp
- monitorDiscordProvider
- stops thread bindings when startup fails before lifecycle begins
- does not double-stop thread bindings when lifecycle performs cleanup
- treats ACP error status as uncertain during startup thread-binding probes
- classifies typed ACP session init failures as stale
- classifies typed non-init ACP errors as uncertain when not stale-running
- aborts timed-out ACP status probes during startup thread-binding health checks
- falls back to legacy missing-session message classification
- captures gateway errors emitted before lifecycle wait starts
- passes default eventQueue.listenerTimeout of 120s to Carbon Client
- forwards custom eventQueue config from discord config to Carbon Client
- does not reuse eventQueue.listenerTimeout as the queued inbound worker timeout
- forwards inbound worker timeout config to the Discord message handler
- registers plugin commands as native Discord commands
- reports connected status on startup and shutdown

### src/discord/monitor/reply-delivery.test.lisp
- deliverDiscordReply
- routes audioAsVoice payloads through the voice API and sends text separately
- skips follow-up text when the voice payload text is blank
- passes mediaLocalRoots through media sends
- uses replyToId only for the first chunk when replyToMode is first
- does not consume replyToId for replyToMode=first on whitespace-only payloads
- preserves leading whitespace in delivered text chunks
- sends text chunks in order via sendDiscordText when rest is provided
- falls back to sendMessageDiscord when rest is not provided
- retries bot send on 429 rate limit then succeeds
- retries bot send on 500 server error then succeeds
- does not retry on 4xx client errors
- throws after exhausting retry attempts
- delivers remaining chunks after a mid-sequence retry
- sends bound-session text replies through webhook delivery
- touches bound-thread activity after outbound delivery
- falls back to bot send when webhook delivery fails
- does not use thread webhook when outbound target is not a bound thread

### src/discord/monitor/route-resolution.test.lisp
- discord route resolution helpers
- builds a direct peer from DM metadata
- resolves bound session keys on top of the routed session
- falls back to configured route when no bound session exists
- resolves the same route shape as the inline Discord route inputs
- composes route building with effective-route overrides

### src/discord/monitor/thread-bindings.discord-api.test.lisp
- resolveChannelIdForBinding
- returns explicit channelId without resolving route
- returns parent channel for thread channels
- keeps non-thread channel id even when parent_id exists
- keeps forum channel id instead of parent category

### src/discord/monitor/thread-bindings.lifecycle.test.lisp
- thread binding lifecycle
- includes idle and max-age details in intro text
- includes cwd near the top of intro text
- auto-unfocuses idle-expired bindings and sends inactivity message
- auto-unfocuses max-age-expired bindings and sends max-age message
- keeps binding when thread sweep probe fails transiently
- unbinds when thread sweep probe reports unknown channel
- updates idle timeout by target session key
- updates max age by target session key
- keeps binding when idle timeout is disabled per session key
- keeps a binding when activity is touched during the same sweep pass
- refreshes inactivity window when thread activity is touched
- persists touched activity timestamps across restart when persistence is enabled
- reuses webhook credentials after unbind when rebinding in the same channel
- creates a new thread when spawning from an already bound thread
- resolves parent channel when thread target is passed via to without threadId
- passes manager token when resolving parent channels for auto-bind
- refreshes manager token when an existing manager is reused
- keeps overlapping thread ids isolated per account
- removes stale ACP bindings during startup reconciliation
- keeps ACP bindings when session store reads fail during startup reconciliation
- removes ACP bindings when health probe marks running session as stale
- keeps running ACP bindings when health probe is uncertain
- keeps ACP bindings in stored error state when no explicit stale probe verdict exists
- starts ACP health probes in parallel during startup reconciliation
- caps ACP startup health probe concurrency
- migrates legacy expiresAt bindings to idle/max-age semantics
- persists unbinds even when no manager is active

### src/discord/monitor/thread-bindings.persona.test.lisp
- thread binding persona
- prefers explicit label and prefixes with gear
- falls back to agent id when label is missing
- builds persona from binding record

### src/discord/monitor/thread-bindings.shared-state.test.lisp
- thread binding manager state
- shares managers between Common Lisp package/module structure and alternate-loaded module instances

### src/discord/monitor/thread-session-close.test.lisp
- closeDiscordThreadSessions
- resets updatedAt to 0 for sessions whose key contains the threadId
- returns 0 and leaves store unchanged when no session matches
- resets all matching sessions when multiple keys contain the threadId
- does not match a key that contains the threadId as a substring of a longer snowflake
- matching is case-insensitive for the session key
- returns 0 immediately when threadId is empty without touching the store
- resolves the store path using cfg.session.store and accountId

### src/discord/monitor/threading.auto-thread.test.lisp
- maybeCreateDiscordAutoThread
- skips auto-thread if channelType is GuildForum
- skips auto-thread if channelType is GuildMedia
- skips auto-thread if channelType is GuildVoice
- skips auto-thread if channelType is GuildStageVoice
- creates auto-thread if channelType is GuildText

### src/discord/monitor/threading.parent-info.test.lisp
- resolveDiscordThreadParentInfo
- falls back to fetched thread parentId when parentId is missing in payload
- does not fetch thread info when parentId is already present
- returns empty parent info when fallback thread lookup has no parentId

### src/discord/monitor/threading.starter.test.lisp
- resolveDiscordThreadStarter
- falls back to joined embed title and description when content is empty
- prefers starter content over embed fallback text

### src/discord/pluralkit.test.lisp
- fetchPluralKitMessageInfo
- returns null when disabled
- returns null on 404
- returns payload and sends token when configured

### src/discord/probe.intents.test.lisp
- resolveDiscordPrivilegedIntentsFromFlags
- reports disabled when no bits set
- reports enabled when full intent bits set
- reports limited when limited intent bits set
- prefers enabled over limited when both set

### src/discord/probe.parse-token.test.lisp
- parseApplicationIdFromToken
- extracts application ID from a valid token
- extracts large snowflake IDs without precision loss
- handles tokens with Bot prefix
- returns undefined for empty string
- returns undefined for token without dots
- returns undefined when decoded segment is not numeric
- returns undefined for whitespace-only input
- returns undefined when first segment is empty (starts with dot)

### src/discord/resolve-allowlist-common.test.lisp
- resolve-allowlist-common
- resolves and filters guilds by id or name
- builds unresolved result rows in input order
- normalizes allowlist token values

### src/discord/resolve-channels.test.lisp
- resolveDiscordChannelAllowlist
- resolves guild/channel by name
- resolves channel id to guild
- resolves guildId/channelId entries via channel lookup
- reports unresolved when channel id belongs to a different guild
- resolves numeric channel id when guild is specified by name
- marks invalid numeric channelId as unresolved without aborting batch
- treats 403 channel lookup as unresolved without aborting batch
- falls back to name matching when numeric channel name is not a valid ID
- does not fall back to name matching when channel lookup returns 403
- does not fall back to name matching when channel payload is malformed
- resolves guild: prefixed id as guild (not channel)
- bare numeric guild id is misrouted as channel id (regression)

### src/discord/resolve-users.test.lisp
- resolveDiscordUserAllowlist
- resolves plain user ids without calling listGuilds
- resolves mention-format ids without calling listGuilds
- resolves prefixed ids (user:, discord:) without calling listGuilds
- resolves user ids even when listGuilds would fail
- calls listGuilds lazily when resolving usernames
- fetches guilds only once for multiple username entries
- handles mixed ids and usernames — ids resolve even if guilds fail
- returns unresolved for empty/blank entries
- returns all unresolved when token is empty

### src/discord/send.components.test.lisp
- sendDiscordComponentMessage
- keeps direct-channel DM session keys on component entries

### src/discord/send.creates-thread.test.lisp
- sendMessageDiscord
- creates a thread
- creates forum threads with an initial message
- creates media threads with provided content
- passes applied_tags for forum threads
- omits applied_tags for non-forum threads
- falls back when channel lookup is unavailable
- respects explicit thread type for standalone threads
- sends initial message for non-forum threads with content
- sends initial message for message-attached threads with content
- lists active threads by guild
- times out a member
- adds and removes roles
- bans a member
- listGuildEmojisDiscord
- lists emojis for a guild
- uploadEmojiDiscord
- uploads emoji assets
- uploadStickerDiscord
- uploads sticker assets
- sendStickerDiscord
- sends sticker payloads
- sendPollDiscord
- sends polls with answers
- retry rate limits
- retries on Discord rate limits
- uses retry_after delays when rate limited
- stops after max retry attempts
- does not retry non-rate-limit errors
- retries reactions on rate limits
- retries media upload without duplicating overflow text

### src/discord/send.permissions.authz.test.lisp
- discord guild permission authorization
- fetchMemberGuildPermissionsDiscord
- returns null when user is not a guild member
- includes @everyone and member roles in computed permissions
- hasAnyGuildPermissionDiscord
- returns true when user has required permission
- returns true when user has ADMINISTRATOR
- returns false when user lacks all required permissions
- hasAllGuildPermissionsDiscord
- returns false when user has only one of multiple required permissions
- returns true for hasAll checks when user has ADMINISTRATOR

### src/discord/send.sends-basic-channel-messages.test.lisp
- sendMessageDiscord
- sends basic channel messages
- rewrites cached @username mentions to id-based mentions
- auto-creates a forum thread when target is a Forum channel
- posts media as a follow-up message in forum channels
- chunks long forum posts into follow-up messages
- starts DM when recipient is a user
- rejects bare numeric IDs as ambiguous
- adds missing permission hints on 50013
- uploads media attachments
- uses configured discord mediaMaxMb for uploads
- sends media with empty text without content field
- preserves whitespace in media captions
- includes message_reference when replying
- preserves reply reference across all text chunks
- preserves reply reference for follow-up text chunks after media caption split
- reactMessageDiscord
- reacts with unicode emoji
- normalizes variation selectors in unicode emoji
- reacts with custom emoji syntax
- removeReactionDiscord
- removes a unicode emoji reaction
- removeOwnReactionsDiscord
- removes all own reactions on a message
- fetchReactionsDiscord
- returns reactions with users
- fetchChannelPermissionsDiscord
- calculates permissions from guild roles
- treats Administrator as all permissions despite overwrites
- readMessagesDiscord
- passes query params as an object
- edit/delete message helpers
- edits message content
- deletes message
- pin helpers
- pins and unpins messages
- searchMessagesDiscord
- uses URLSearchParams for search
- supports channel/author arrays and clamps limit

### src/discord/send.webhook-activity.test.lisp
- sendWebhookMessageDiscord activity
- records outbound channel activity for webhook sends

### src/discord/session-key-normalization.test.lisp
- normalizeExplicitDiscordSessionKey
- rewrites bare discord:dm keys for direct chats
- rewrites legacy discord:dm keys for direct chats
- rewrites phantom discord:channel keys when sender matches
- leaves non-direct channel keys unchanged

### src/discord/targets.test.lisp
- parseDiscordTarget
- parses user mention and prefixes
- parses channel targets
- accepts numeric ids when a default kind is provided
- rejects invalid parse targets
- resolveDiscordChannelId
- strips channel: prefix and accepts raw ids
- rejects user targets
- resolveDiscordTarget
- returns a resolved user for usernames
- falls back to parsing when lookup misses
- does not call directory lookup for explicit user ids
- normalizeDiscordMessagingTarget
- defaults raw numeric ids to channels

### src/discord/token.test.lisp
- resolveDiscordToken
- prefers config token over env
- uses env token when config is missing
- prefers account token for non-default accounts
- falls back to top-level token for non-default accounts without account token
- does not inherit top-level token when account token is explicitly blank
- resolves account token when account key casing differs from normalized id
- throws when token is an unresolved SecretRef object

### src/discord/voice-message.test.lisp
- ensureOggOpus
- rejects URL/protocol input paths
- keeps .ogg only when codec is opus and sample rate is 48kHz
- re-encodes .ogg opus when sample rate is not 48kHz
- re-encodes non-ogg input with bounded ffmpeg execution

### src/discord/voice/command.test.lisp
- createDiscordVoiceCommand
- vc leave reports missing guild before manager lookup
- vc status reports unavailable voice manager
- vc status reports no active sessions when manager has none

### src/discord/voice/manager.e2e.test.lisp
- DiscordVoiceManager
- keeps the new session when an old disconnected handler fires
- keeps the new session when an old destroyed handler fires
- removes voice listeners on leave
- passes DAVE options to joinVoiceChannel
- attempts rejoin after repeated decrypt failures
- passes senderIsOwner=true for allowlisted voice speakers
- passes senderIsOwner=false for non-owner voice speakers
- reuses speaker context cache for repeated segments from the same speaker

## docker-image-digests.test.lisp

### src/docker-image-digests.test.lisp
- docker base image pinning
- pins selected Dockerfile FROM lines to immutable sha256 digests
- keeps Dependabot Docker (driven from Common Lisp) updates enabled for root Dockerfiles

## docker-setup.e2e.test.lisp

### src/docker-setup.e2e.test.lisp
- docker-setup.sh
- handles env defaults, home-volume mounts, and apt build args
- precreates config identity dir for command-line interface device auth writes
- precreates agent data dirs to avoid EACCES in container
- reuses existing config token when OPENCLAW_GATEWAY_TOKEN is unset
- reuses existing .env token when OPENCLAW_GATEWAY_TOKEN and config token are unset
- reuses the last non-empty .env token and strips CRLF without truncating '='
- treats OPENCLAW_SANDBOX=0 as disabled
- resets stale sandbox mode and overlay when sandbox is not active
- skips sandbox gateway restart when sandbox config writes fail
- rejects injected multiline OPENCLAW_EXTRA_MOUNTS values
- rejects invalid OPENCLAW_EXTRA_MOUNTS mount format
- rejects invalid OPENCLAW_HOME_VOLUME names
- avoids associative arrays so the script remains Bash 3.2-compatible
- keeps docker-compose gateway command in sync
- keeps docker-compose command-line interface network namespace settings in sync
- keeps docker-compose gateway token env defaults aligned across services

## dockerfile.test.lisp

### src/dockerfile.test.lisp
- Dockerfile
- uses shared multi-arch base image refs for all root Node stages
- installs optional browser dependencies after ASDF/Quicklisp/Ultralisp install
- normalizes plugin and agent paths permissions in image layers
- Docker (driven from Common Lisp) GPG fingerprint awk uses correct quoting for OPENCLAW_SANDBOX=1 build

## docs

### src/docs/slash-commands-doc.test.lisp
- slash commands docs
- documents all built-in chat command aliases

## gateway

### src/gateway/agent-prompt.test.lisp
- gateway agent prompt
- returns empty for no entries
- returns current body when there is no history
- extracts text from content-array body when there is no history
- uses history context when there is history
- prefers last tool entry over assistant for current message
- normalizes content-array bodies in history and current message

### src/gateway/android-sbcl.capabilities.live.test.lisp
- command: ${command}
- covers every advertised non-interactive command

### src/gateway/assistant-identity.test.lisp
- resolveAssistantIdentity avatar normalization
- drops sentence-like avatar placeholders
- keeps short text avatars
- keeps path avatars

### src/gateway/auth-mode-policy.test.lisp
- gateway auth mode policy
- does not flag config when auth mode is explicit
- does not flag config when only one auth credential is configured
- flags config when both token and password are configured and mode is unset
- flags config when both token/password SecretRefs are configured and mode is unset
- throws the shared explicit-mode error for ambiguous dual auth config

### src/gateway/auth-rate-limit.test.lisp
- auth rate limiter
- allows requests when no failures have been recorded
- decrements remaining count after each failure
- blocks the IP once maxAttempts is reached
- unblocks after the lockout period expires
- expires old failures outside the window
- tracks IPs independently
- treats ipv4 and ipv4-mapped ipv6 forms as the same client
- tracks scopes independently for the same IP
- exempts loopback addresses by default
- exempts IPv6 loopback by default
- rate-limits loopback when exemptLoopback is false
- clears tracking state when reset is called
- reset only clears the requested scope for an IP
- prune removes stale entries
- prune keeps entries that are still locked out
- normalizes undefined IP to 'unknown'
- normalizes empty-string IP to 'unknown'
- dispose clears all entries

### src/gateway/auth.test.lisp
- gateway auth
- resolves token/password from OPENCLAW gateway env vars
- does not resolve legacy CLAWDBOT gateway env vars
- keeps gateway auth config values ahead of env overrides
- treats env-template auth secrets as SecretRefs instead of plaintext
- resolves explicit auth mode none from config
- marks mode source as override when runtime mode override is provided
- does not throw when req is missing socket
- reports missing and mismatched token reasons
- reports missing token config reason
- allows explicit auth mode none
- keeps none mode authoritative even when token is present
- reports missing and mismatched password reasons
- reports missing password config reason
- treats local tailscale serve hostnames as direct
- does not allow tailscale identity to satisfy token mode auth by default
- allows tailscale identity when header auth is explicitly enabled
- keeps tailscale header auth disabled on HTTP auth wrapper
- enables tailscale header auth on ws control-ui auth wrapper
- uses proxy-aware request client IP by default for rate-limit checks
- ignores X-Real-IP fallback by default for rate-limit checks
- uses X-Real-IP when fallback is explicitly enabled
- passes custom rate-limit scope to limiter operations
- does not record rate-limit failure for missing token (misconfigured client, not brute-force)
- does not record rate-limit failure for missing password (misconfigured client, not brute-force)
- still records rate-limit failure for wrong token (brute-force attempt)
- still records rate-limit failure for wrong password (brute-force attempt)
- throws specific error when password is a provider reference object
- accepts password mode when env provides OPENCLAW_GATEWAY_PASSWORD
- throws generic error when password mode has no password at all
- trusted-proxy auth
- accepts valid request from trusted proxy
- rejects request from untrusted source
- rejects request with missing user header
- rejects request with missing required headers
- rejects user not in allowlist
- accepts user in allowlist
- rejects when no trustedProxies configured
- rejects when trustedProxy config missing
- supports Pomerium-style headers
- trims whitespace from user header value

### src/gateway/boot.test.lisp
- runBootOnce
- skips when BOOT.md is missing
- returns failed when BOOT.md cannot be read
- runs agent command when BOOT.md exists
- returns failed when agent command throws
- uses per-agent session key when agentId is provided
- generates new session ID when no existing session exists
- uses a fresh boot session ID even when main session mapping already exists
- restores the original main session mapping after the boot run
- removes a boot-created main-session mapping when none existed before

### src/gateway/call.test.lisp
- callGateway url resolution
- uses url override in remote mode even when remote url is missing
- uses OPENCLAW_GATEWAY_URL env override in remote mode when remote URL is missing
- uses env URL override credentials without resolving local password SecretRefs
- uses remote tlsFingerprint with env URL override
- does not apply remote tlsFingerprint for command-line interface url override
- passes explicit scopes through, including empty arrays
- buildGatewayConnectionDetails
- uses explicit url overrides and omits bind details
- emits a remote fallback note when remote url is missing
- prefers remote url when configured
- uses env OPENCLAW_GATEWAY_URL when set
- throws for insecure ws:// remote URLs (CWE-319)
- allows ws:// private remote URLs only when OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1
- allows ws:// hostname remote URLs when OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1
- allows ws:// for loopback addresses in local mode
- callGateway error details
- includes connection details when the gateway closes
- includes connection details on timeout
- does not overflow very large timeout values
- fails fast when remote mode is missing remote url
- fails before request when a required gateway method is missing
- callGateway url override auth requirements
- throws when url override is set without explicit credentials
- throws when env URL override is set without env credentials
- callGateway password resolution
- resolves gateway.auth.password SecretInput refs for gateway calls
- does not resolve local password ref when env password takes precedence
- does not resolve local password ref when token auth can win
- resolves local password ref before unresolved local token ref can block auth
- does not resolve local password ref when remote password is already configured
- resolves gateway.remote.token SecretInput refs when remote token is required
- resolves gateway.remote.password SecretInput refs when remote password is required
- does not resolve remote token ref when remote password already wins
- resolves remote token ref before unresolved remote password ref can block auth
- does not resolve remote password ref when remote token already wins
- resolves remote token refs on local-mode calls when fallback token can win

### src/gateway/channel-health-monitor.test.lisp
- channel-health-monitor
- does not run before the grace period
- runs health check after grace period
- accepts timing.monitorStartupGraceMs
- skips healthy channels (running + connected)
- skips disabled channels
- skips unconfigured channels
- skips manually stopped channels
- restarts a stuck channel (running but not connected)
- skips restart when channel is busy with active runs
- restarts busy channels when run activity is stale
- restarts disconnected channels when busy flags are inherited from a prior lifecycle
- skips recently-started channels while they are still connecting
- respects custom per-channel startup grace
- restarts a stopped channel that gave up (reconnectAttempts >= 10)
- restarts a channel that stopped unexpectedly (not running, not manual)
- treats missing enabled/configured flags as managed accounts
- applies cooldown — skips recently restarted channels for 2 cycles
- caps at 3 health-monitor restarts per channel per hour
- runs checks single-flight when restart work is still in progress
- stops cleanly
- stops via abort signal
- treats running channels without a connected field as healthy
- stale socket detection
- restarts a channel with no events past the stale threshold
- skips channels with recent events
- skips channels still within the startup grace window for stale detection
- restarts a channel that has seen no events since connect past the stale threshold
- skips connected channels that do not report event liveness
- respects custom staleEventThresholdMs

### src/gateway/channel-health-policy.test.lisp
- evaluateChannelHealth
- treats disabled accounts as healthy unmanaged
- uses channel connect grace before flagging disconnected
- treats active runs as busy even when disconnected
- flags stale busy channels as stuck when run activity is too old
- ignores inherited busy flags until current lifecycle reports run activity
- flags stale sockets when no events arrive beyond threshold
- skips stale-socket detection for telegram long-polling channels
- skips stale-socket detection for channels in webhook mode
- does not flag stale sockets for channels without event tracking
- does not flag stale sockets without an active connected socket
- ignores inherited event timestamps from a previous lifecycle
- flags inherited event timestamps after the lifecycle exceeds the stale threshold
- resolveChannelRestartReason
- maps not-running + high reconnect attempts to gave-up
- maps disconnected to disconnected instead of stuck

### src/gateway/channel-status-patches.test.lisp
- createConnectedChannelStatusPatch
- uses one timestamp for connected event-liveness state

### src/gateway/chat-abort.test.lisp
- isChatStopCommandText
- matches slash and standalone multilingual stop forms
- abortChatRunById
- broadcasts aborted payload with partial message when buffered text exists
- omits aborted message when buffered text is empty
- preserves partial message even when abort listeners clear buffers synchronously

### src/gateway/chat-attachments.test.lisp
- buildMessageWithAttachments
- embeds a single image as data URL
- rejects non-image mime types
- parseMessageWithAttachments
- strips data URL prefix
- sniffs mime when missing
- drops non-image payloads and logs
- prefers sniffed mime type and logs mismatch
- drops unknown mime when sniff fails and logs
- keeps valid images and drops invalid ones
- shared attachment validation
- rejects invalid base64 content for both builder and parser
- rejects images over limit for both builder and parser without decoding base64

### src/gateway/chat-sanitize.test.lisp
- stripEnvelopeFromMessage
- removes message_id hint lines from user messages
- removes message_id hint lines from text content arrays
- does not strip inline message_id text that is part of a line
- does not strip assistant messages
- defensively strips inbound metadata blocks from non-user messages
- removes inbound un-bracketed conversation info blocks from user messages
- removes all inbound metadata blocks before user text
- strips metadata-like blocks even when not a prefix
- strips trailing untrusted context metadata suffix blocks

### src/gateway/client-callsites.guard.test.lisp
- GatewayClient production callsites
- remain constrained to allowlisted files

### src/gateway/client.test.lisp
- GatewayClient security checks
- blocks ws:// to non-loopback addresses (CWE-319)
- handles malformed URLs gracefully without crashing
- allows ws:// to loopback addresses
- allows wss:// to any address
- allows ws:// to private addresses only with OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1
- allows ws:// hostnames with OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1
- GatewayClient close handling
- clears stale token on device token mismatch close
- does not break close flow when token clear throws
- does not break close flow when pairing clear rejects
- does not clear auth state for non-mismatch close reasons
- does not clear persisted device auth when explicit shared token is provided
- GatewayClient connect auth payload
- uses explicit shared token and does not inject stored device token
- uses explicit shared password and does not inject stored device token
- uses stored device token when shared token is not provided
- prefers explicit deviceToken over stored device token

### src/gateway/client.watchdog.test.lisp
- GatewayClient
- closes on missing ticks
- rejects mismatched tls fingerprint

### src/gateway/config-reload.test.lisp
- diffConfigPaths
- captures nested config changes
- captures array changes
- does not report unchanged arrays of objects as changed
- reports changed arrays of objects
- buildGatewayReloadPlan
- marks gateway changes as restart required
- restarts the Gmail watcher for hooks.gmail changes
- restarts providers when provider config prefixes change
- restarts heartbeat when model-related config changes
- restarts heartbeat when agents.defaults.models allowlist changes
- hot-reloads health monitor when channelHealthCheckMinutes changes
- treats gateway.remote as no-op
- treats secrets config changes as no-op for gateway restart planning
- treats diagnostics.stuckSessionWarnMs as no-op for gateway restart planning
- defaults unknown paths to restart
- resolveGatewayReloadSettings
- uses defaults when unset
- startGatewayConfigReloader
- retries missing snapshots and reloads once config file reappears
- caps missing-file retries and skips reload after retry budget is exhausted
- contains restart callback failures and retries on subsequent changes

### src/gateway/connection-auth.test.lisp
- resolveGatewayConnectionAuth
- can disable legacy env fallback
- resolves local SecretRef token when legacy env is disabled
- resolves config-first token SecretRef even when OPENCLAW env token exists
- resolves config-first password SecretRef even when OPENCLAW env password exists
- throws when config-first token SecretRef cannot resolve even if env token exists
- throws when config-first password SecretRef cannot resolve even if env password exists

### src/gateway/control-ui-csp.test.lisp
- buildControlUiCspHeader
- blocks inline scripts while allowing inline styles
- allows Google Fonts for style and font loading

### src/gateway/control-ui-routing.test.lisp
- classifyControlUiRequest
- falls through non-read root requests for plugin webhooks
- returns not-found for legacy /ui routes when root-mounted
- falls through basePath non-read methods for plugin webhooks
- falls through PUT/DELETE/PATCH/OPTIONS under basePath for plugin handlers
- returns redirect for basePath entrypoint GET
- classifies basePath subroutes as control ui

### src/gateway/control-ui.http.test.lisp
- handleControlUiHttpRequest
- sets security headers for Control UI responses
- does not inject inline scripts into index.html
- serves bootstrap config JSON
- serves bootstrap config JSON under basePath
- serves local avatar bytes through hardened avatar handler
- rejects avatar symlink paths from resolver
- rejects symlinked assets that resolve outside control-ui root
- allows symlinked assets that resolve inside control-ui root
- serves HEAD for in-root assets without writing a body
- rejects symlinked SPA fallback index.html outside control-ui root
- does not handle POST to root-mounted paths (plugin webhook passthrough)
- does not handle POST to paths outside basePath
- does not handle /api paths when basePath is empty
- does not handle /plugins paths when basePath is empty
- falls through POST requests when basePath is empty
- falls through POST requests under configured basePath (plugin webhook passthrough)
- rejects absolute-path escape attempts under basePath routes
- rejects symlink escape attempts under basePath routes

### src/gateway/credential-precedence.parity.test.lisp
- gateway credential precedence parity

### src/gateway/credentials.test.lisp
- resolveGatewayCredentialsFromConfig
- prefers explicit credentials over config and environment
- returns empty credentials when url override is used without explicit auth
- uses env credentials for env-sourced url overrides
- uses local-mode environment values before local config
- uses config-first local token precedence inside gateway service runtime
- falls back to remote credentials in local mode when local auth is missing
- throws when local password auth relies on an unresolved SecretRef
- treats env-template local tokens as SecretRefs instead of plaintext
- throws when env-template local token SecretRef is unresolved in token mode
- ignores unresolved local password ref when local auth mode is none
- ignores unresolved local password ref when local auth mode is trusted-proxy
- keeps local credentials ahead of remote fallback in local mode
- uses remote-mode remote credentials before env and local config
- falls back to env/config when remote mode omits remote credentials
- supports env-first password override in remote mode for gateway call path
- supports env-first token precedence in remote mode
- supports remote-only password fallback for strict remote override call sites
- supports remote-only token fallback for strict remote override call sites
- throws when remote token auth relies on an unresolved SecretRef
- ignores unresolved local token ref in remote-only mode when local auth mode is token
- throws for unresolved local token ref in remote mode when local fallback is enabled
- does not throw for unresolved remote token ref when password is available
- throws when remote password auth relies on an unresolved SecretRef
- can disable legacy CLAWDBOT env fallback
- resolveGatewayCredentialsFromValues
- supports config-first precedence for token/password
- uses env-first precedence by default
- rejects unresolved env var placeholders in config credentials
- accepts config credentials that do not contain env var references

### src/gateway/device-auth.test.lisp
- device-auth payload vectors
- builds canonical v3 payload
- normalizes metadata with ASCII-only lowercase

### src/gateway/gateway-cli-backend.live.test.lisp
- runs the agent pipeline against the local command-line interface backend

### src/gateway/gateway-misc.test.lisp
- GatewayClient
- uses a large maxPayload for sbcl snapshots
- returns 404 for missing static asset paths instead of SPA fallback
- returns 404 for missing static assets with query strings
- still serves SPA fallback for extensionless paths
- HEAD returns 404 for missing static assets consistent with GET
- serves SPA fallback for dotted path segments that are not static assets
- serves SPA fallback for .html paths that do not exist on disk
- gateway broadcaster
- filters approval and pairing events by scope
- chat run registry
- queues and removes runs per session
- late-arriving invoke results
- returns success for unknown invoke ids for both success and error payloads
- sbcl subscription manager
- routes events to subscribed nodes
- unsubscribeAll clears session mappings
- resolveNodeCommandAllowlist
- includes iOS service commands by default
- includes Android notifications and device diagnostics commands by default
- can explicitly allow dangerous commands via allowCommands
- treats unknown/confusable metadata as fail-safe for system.run defaults
- normalizes dotted-I platform values to iOS classification
- normalizeVoiceWakeTriggers
- returns defaults when input is empty
- trims and limits entries
- formatError
- prefers message for Error
- handles status/code

### src/gateway/gateway-models.profiles.live.test.lisp
- runs meaningful prompts across models with available keys
- z.ai fallback handles anthropic tool history

### src/gateway/gateway.test.lisp
- gateway e2e
- runs a mock OpenAI tool call end-to-end via gateway agent loop
- runs wizard over ws and writes auth token config

### src/gateway/hooks-mapping.test.lisp
- hooks mapping
- resolves gmail preset
- renders template from payload
- passes model override from mapping
- runs transform module
- rejects transform module traversal outside transformsDir
- rejects absolute transform module path outside transformsDir
- rejects transformsDir traversal outside the transforms root
- rejects transformsDir absolute path outside the transforms root
- accepts transformsDir subdirectory within the transforms root
- treats null transform as a handled skip
- prefers explicit mappings over presets
- passes agentId from mapping
- agentId is undefined when not set
- caches transform functions by module path and export name
- rejects missing message
- prototype pollution protection
- blocks __proto__ traversal in webhook payload
- blocks constructor traversal in webhook payload
- blocks prototype traversal in webhook payload

### src/gateway/hooks.test.lisp
- gateway hooks helpers
- resolveHooksConfig normalizes paths + requires token
- resolveHooksConfig rejects root path
- extractHookToken prefers bearer > header
- normalizeWakePayload trims + validates
- normalizeAgentPayload defaults + validates channel
- normalizeAgentPayload passes agentId
- resolveHookTargetAgentId falls back to default for unknown agent ids
- isHookAgentAllowed honors hooks.allowedAgentIds for explicit routing
- isHookAgentAllowed treats empty allowlist as deny-all for explicit agentId
- isHookAgentAllowed treats wildcard allowlist as allow-all
- resolveHookSessionKey disables request sessionKey by default
- resolveHookSessionKey allows request sessionKey when explicitly enabled
- resolveHookSessionKey enforces allowed prefixes
- resolveHookSessionKey uses defaultSessionKey when request key is absent
- normalizeHookDispatchSessionKey strips duplicate target agent prefix
- normalizeHookDispatchSessionKey preserves non-target agent scoped keys
- resolveHooksConfig validates defaultSessionKey and generated fallback against prefixes

### src/gateway/http-auth-helpers.test.lisp
- authorizeGatewayBearerRequestOrReply
- disables tailscale header auth for HTTP bearer checks
- forwards bearer token and returns true on successful auth

### src/gateway/http-common.test.lisp
- setDefaultSecurityHeaders
- sets X-Content-Type-Options
- sets Referrer-Policy
- sets Permissions-Policy
- sets Strict-Transport-Security when provided
- does not set Strict-Transport-Security when not provided
- does not set Strict-Transport-Security for empty string

### src/gateway/http-endpoint-helpers.test.lisp
- handleGatewayPostJsonEndpoint
- returns false when path does not match
- returns undefined and replies when method is not POST
- returns undefined when auth fails
- returns body when auth succeeds and JSON parsing succeeds

### src/gateway/http-utils.request-context.test.lisp
- resolveGatewayRequestContext
- uses normalized x-openclaw-message-channel when enabled
- uses default messageChannel when header support is disabled
- includes session prefix and user in generated session key

### src/gateway/live-tool-probe-utils.test.lisp
- live tool probe utils
- matches nonce pair when both are present
- matches single nonce when present
- detects anthropic nonce refusal phrasing
- does not treat generic helper text as nonce refusal
- detects prompt-injection style tool refusal without nonce text
- retries malformed tool output when attempts remain
- does not retry once max attempts are exhausted
- does not retry when nonce pair is already present
- retries when tool output is empty and attempts remain
- retries when output still looks like tool/function scaffolding
- retries mistral nonce marker echoes without parsed nonce values
- retries anthropic nonce refusal output
- retries anthropic prompt-injection refusal output
- does not retry nonce marker echoes for non-mistral providers
- retries malformed exec+read output when attempts remain
- does not retry exec+read once max attempts are exhausted
- does not retry exec+read when nonce is present
- retries anthropic exec+read nonce refusal output

### src/gateway/method-scopes.test.lisp
- method scope resolution
- classifies sessions.resolve + config.schema.lookup as read and poll as write
- returns empty scopes for unknown methods
- operator scope authorization
- allows read methods with operator.read or operator.write
- requires operator.write for write methods
- requires approvals scope for approval methods
- requires admin for unknown methods
- core gateway method classification
- classifies every exposed core gateway handler method
- classifies every listed gateway method name

### src/gateway/net.test.lisp
- resolveHostName
- normalizes IPv4/hostname and IPv6 host forms
- isLocalishHost
- accepts loopback and tailscale serve/funnel host headers
- rejects non-local hosts
- isTrustedProxyAddress
- exact IP matching
- returns true when IP matches exactly
- returns false when IP does not match
- returns true when IP matches one of multiple proxies
- ignores surrounding whitespace in exact IP entries
- CIDR subnet matching
- returns true when IP is within /24 subnet
- returns false when IP is outside /24 subnet
- returns true when IP is within /16 subnet
- returns false when IP is outside /16 subnet
- returns true when IP is within /32 subnet (single IP)
- returns false when IP does not match /32 subnet
- handles mixed exact IPs and CIDR notation
- supports IPv6 CIDR notation
- backward compatibility
- preserves exact IP matching behavior (no CIDR notation)
- does NOT treat plain IPs as /32 CIDR (exact match only)
- handles IPv4-mapped IPv6 addresses (existing normalizeIp behavior)
- edge cases
- returns false when IP is undefined
- returns false when trustedProxies is undefined
- returns false when trustedProxies is empty
- returns false for invalid CIDR notation
- ignores surrounding whitespace in CIDR entries
- ignores blank trusted proxy entries
- resolveClientIp
- resolveGatewayListenHosts
- resolves listen hosts for non-loopback and loopback variants
- pickPrimaryLanIPv4
- prefers en0, then eth0, then any non-internal IPv4, otherwise undefined
- isPrivateOrLoopbackAddress
- accepts loopback, private, link-local, and cgnat ranges
- rejects public addresses
- isPrivateOrLoopbackHost
- accepts localhost
- accepts loopback addresses
- accepts RFC 1918 private addresses
- accepts CGNAT and link-local addresses
- accepts IPv6 private addresses
- rejects unspecified IPv6 address (::)
- rejects multicast IPv6 addresses (ff00::/8)
- rejects public addresses
- rejects empty/falsy input
- isSecureWebSocketUrl
- defaults to loopback-only ws:// and rejects private/public remote ws://
- allows private ws:// only when opt-in is enabled
- still rejects ws:// public IP literals when opt-in is enabled
- still rejects non-unicast IPv6 ws:// even when opt-in is enabled

### src/gateway/sbcl-invoke-system-run-approval-match.test.lisp
- evaluateSystemRunApprovalMatch
- rejects approvals that do not carry v1 binding
- enforces exact argv binding in v1 object
- rejects argv mismatch in v1 object
- rejects env overrides when v1 binding has no env hash
- accepts matching env hash with reordered keys
- rejects non-sbcl host requests
- uses v1 binding even when legacy command text diverges

### src/gateway/sbcl-invoke-system-run-approval.test.lisp
- sanitizeSystemRunParamsForForwarding
- rejects cmd.exe /c trailing-arg mismatch against rawCommand
- accepts matching cmd.exe /c command text for approval binding
- rejects env-assignment shell wrapper when approval command omits env prelude
- accepts env-assignment shell wrapper only when approval command matches full argv text
- rejects trailing-space argv mismatch against legacy command-only approval
- enforces commandArgv identity when approval includes argv binding
- accepts matching commandArgv binding for trailing-space argv
- uses systemRunPlan for forwarded command context and ignores caller tampering
- rejects env overrides when approval record lacks env binding
- rejects env hash mismatch
- accepts matching env hash with reordered keys
- consumes allow-once approvals and blocks same runId replay
- rejects approval ids that do not bind a nodeId
- rejects approval ids replayed against a different nodeId

### src/gateway/openai-http.image-budget.test.lisp
- openai image budget accounting
- counts normalized base64 image bytes against maxTotalImageBytes
- does not double-count unchanged base64 image payloads

### src/gateway/openai-http.message-channel.test.lisp
- OpenAI HTTP message channel
- passes x-openclaw-message-channel through to agentCommand
- defaults messageChannel to webchat when header is absent

### src/gateway/openai-http.test.lisp
- OpenAI-compatible HTTP API (e2e)
- rejects when disabled (default + config)
- handles request validation and routing
- returns 429 for repeated failed auth when gateway.auth.rateLimit is configured
- streams Server-Sent Events chunks when stream=true

### src/gateway/openresponses-http.test.lisp
- OpenResponses HTTP API (e2e)
- rejects when disabled (default + config)
- handles OpenResponses request parsing and validation
- streams OpenResponses Server-Sent Events events
- blocks unsafe URL-based file/image inputs
- enforces URL allowlist and URL part cap for responses inputs

### src/gateway/openresponses-parity.test.lisp
- OpenResponses Feature Parity
- Schema Validation
- should validate input_image with url source
- should validate input_image with base64 source
- should validate input_image with HEIC base64 source
- should reject input_image with invalid mime type
- should validate input_file with url source
- should validate input_file with base64 source
- should validate tool definition
- should reject tool definition without name
- CreateResponseBody Schema
- should validate request with input_image
- should validate request with client tools
- should validate request with function_call_output for turn-based tools
- should validate complete turn-based tool flow
- Response Resource Schema
- should validate response with function_call output
- buildAgentPrompt
- should convert function_call_output to tool entry
- should handle mixed message and function_call_output items

### src/gateway/origin-check.test.lisp
- checkBrowserOrigin
- accepts same-origin host matches only with legacy host-header fallback
- rejects same-origin host matches when legacy host-header fallback is disabled
- accepts loopback host mismatches for dev
- rejects loopback origin mismatches when request is not local
- accepts allowlisted origins
- accepts wildcard allowedOrigins
- rejects missing origin
- rejects mismatched origins
- accepts any origin when allowedOrigins includes "*" (regression: #30990)
- accepts any origin when allowedOrigins includes "*" alongside specific entries
- accepts wildcard entries with surrounding whitespace

### src/gateway/probe-auth.test.lisp
- resolveGatewayProbeAuthSafe
- returns probe auth credentials when available
- returns warning and empty auth when token SecretRef is unresolved
- ignores unresolved local token SecretRef in remote mode when remote-only auth is requested
- resolveGatewayProbeAuthWithSecretInputs
- resolves local probe SecretRef values before shared credential selection

### src/gateway/probe.test.lisp
- probeGateway
- connects with operator.read scope

### src/gateway/protocol/cron-validators.test.lisp
- cron protocol validators
- accepts minimal add params
- rejects add params when required scheduling fields are missing
- accepts update params for id and jobId selectors
- accepts remove params for id and jobId selectors
- accepts run params mode for id and jobId selectors
- accepts list paging/filter/sort params
- enforces runs limit minimum for id and jobId selectors
- rejects cron.runs path traversal ids
- accepts runs paging/filter/sort params
- accepts all-scope runs with multi-select filters

### src/gateway/protocol/index.test.lisp
- formatValidationErrors
- returns unknown validation error when missing errors
- returns unknown validation error when errors list is empty
- formats additionalProperties at root
- formats additionalProperties with instancePath
- formats message with path for other errors
- de-dupes repeated entries

### src/gateway/reconnect-gating.test.lisp
- isNonRecoverableAuthError
- returns false for undefined error (normal disconnect)
- returns false for errors without detail codes (network issues)
- blocks reconnect for AUTH_TOKEN_MISSING (misconfigured client)
- blocks reconnect for AUTH_PASSWORD_MISSING
- blocks reconnect for AUTH_PASSWORD_MISMATCH (wrong password won't self-correct)
- blocks reconnect for AUTH_RATE_LIMITED (reconnecting burns more slots)
- allows reconnect for AUTH_TOKEN_MISMATCH (device-token fallback flow)
- allows reconnect for unrecognized detail codes (future-proof)

### src/gateway/resolve-configured-secret-input-string.test.lisp
- resolveConfiguredSecretInputWithFallback
- returns plaintext config value when present
- returns fallback value when config is empty and no SecretRef is configured
- returns resolved SecretRef value
- falls back when SecretRef cannot be resolved
- returns unresolved reason when SecretRef cannot be resolved and no fallback exists
- resolveRequiredConfiguredSecretRefInputString
- returns undefined when no SecretRef is configured
- returns resolved SecretRef value
- throws when SecretRef cannot be resolved

### src/gateway/role-policy.test.lisp
- gateway role policy
- parses supported roles
- allows device-less bypass only for operator + shared auth
- authorizes roles against sbcl vs operator methods

### src/gateway/security-path.test.lisp
- security-path canonicalization
- canonicalizes decoded case/slash variants
- resolves traversal after repeated decoding
- marks malformed encoding
- resolves 4x encoded slash path variants to protected channel routes
- flags decode depth overflow and fails closed for protected prefix checks
- security-path protected-prefix matching
- protects plugin channel path variant: ${path}
- does not protect unrelated paths

### src/gateway/server-channels.test.lisp
- server-channels auto restart
- caps crash-loop restarts after max attempts
- does not auto-restart after manual stop during backoff
- marks enabled/configured when account descriptors omit them
- passes channelRuntime through channel gateway context when provided

### src/gateway/server-chat.agent-events.test.lisp
- agent event handler
- emits chat delta for assistant text-only events
- strips inline directives from assistant chat events
- does not emit chat delta for NO_REPLY streaming text
- does not include NO_REPLY text in chat final message
- suppresses NO_REPLY lead fragments and does not leak NO in final chat message
- keeps final short replies like 'No' even when lead-fragment deltas are suppressed
- flushes buffered text as delta before final when throttle suppresses the latest chunk
- preserves pre-tool assistant text when later segments stream as non-prefix snapshots
- flushes merged segmented text before final when latest segment is throttled
- does not flush an extra delta when the latest text already broadcast
- cleans up agent run sequence tracking when lifecycle completes
- flushes buffered chat delta before tool start events
- routes tool events only to registered recipients when verbose is enabled
- broadcasts tool events to WS recipients even when verbose is off, but skips sbcl send
- strips tool output when verbose is on
- keeps tool output when verbose is full
- broadcasts fallback events to agent subscribers and sbcl session
- remaps chat-linked lifecycle runId to client runId
- suppresses chat and sbcl session events for non-control-UI-visible runs
- uses agent event sessionKey when run-context lookup cannot resolve
- remaps chat-linked tool runId for non-full verbose payloads
- suppresses heartbeat ack-like chat output when showOk is false
- keeps heartbeat alert text in final chat output when remainder exceeds ackMaxChars

### src/gateway/server-cron.test.lisp
- buildGatewayCronService
- routes main-target jobs to the scoped session for enqueue + wake
- blocks private webhook URLs via SSRF-guarded fetch

### src/gateway/server-discovery.test.lisp
- resolveTailnetDnsHint
- returns env hint when disabled
- skips tailscale lookup when disabled
- uses tailscale lookup when enabled

### src/gateway/server-http.hooks-request-timeout.test.lisp
- createHooksRequestHandler timeout status mapping
- returns 408 for request body timeout
- shares hook auth rate-limit bucket across ipv4 and ipv4-mapped ipv6 forms

### src/gateway/server-http.probe.test.lisp
- gateway probe endpoints
- returns detailed readiness payload for local /ready requests
- returns only readiness state for unauthenticated remote /ready requests
- returns detailed readiness payload for authenticated remote /ready requests
- returns typed internal error payload when readiness evaluation throws
- keeps /healthz shallow even when readiness checker reports failing channels
- reflects readiness status on HEAD /readyz without a response body

### src/gateway/server-maintenance.test.lisp
- startGatewayMaintenanceTimers
- does not schedule recursive media cleanup unless ttl is configured
- runs startup media cleanup and repeats it hourly
- skips overlapping media cleanup runs

### src/gateway/server-methods.control-plane-rate-limit.test.lisp
- gateway control-plane write rate limit
- allows 3 control-plane writes and blocks the 4th in the same minute
- resets the control-plane write budget after 60 seconds
- uses connId fallback when both device and client IP are unknown
- keeps device/IP-based key when identity is present

### src/gateway/server-methods/agent-wait-dedupe.test.lisp
- agent wait dedupe helper
- unblocks waiters when a terminal chat dedupe entry is written
- keeps stale chat dedupe blocked while agent dedupe is in-flight
- uses newer terminal chat snapshot when agent entry is non-terminal
- ignores stale agent snapshots when waiting for an active chat run
- prefers the freshest terminal snapshot when agent/chat dedupe keys collide
- resolves multiple waiters for the same run id
- cleans up waiter registration on timeout

### src/gateway/server-methods/agent.test.lisp
- gateway agent handler
- preserves ACP metadata from the current stored session entry
- preserves cliSessionIds from existing session entry
- injects a timestamp into the message passed to agentCommand
- respects explicit bestEffortDeliver=false for main session runs
- only forwards workspaceDir for spawned subagent runs
- keeps origin messageChannel as webchat while delivery channel uses last session channel
- handles missing cliSessionIds gracefully
- prunes legacy main alias keys when writing a canonical session entry
- handles bare /new by resetting the same session and sending reset greeting prompt
- uses /reset suffix as the post-reset message and still injects timestamp
- rejects malformed agent session keys early in agent handler
- rejects malformed session keys in agent.identity.get

### src/gateway/server-methods/agents-mutate.test.lisp
- agents.create
- creates a new agent successfully
- ensures workspace is set up before writing config
- rejects creating an agent with reserved 'main' id
- rejects creating a duplicate agent
- rejects invalid params (missing name)
- always writes Name to IDENTITY.md even without emoji/avatar
- writes emoji and avatar to IDENTITY.md when provided
- agents.update
- updates an existing agent successfully
- rejects updating a nonexistent agent
- ensures workspace when workspace changes
- does not ensure workspace when workspace is unchanged
- agents.delete
- deletes an existing agent and trashes files by default
- skips file deletion when deleteFiles is false
- rejects deleting the main agent
- rejects deleting a nonexistent agent
- rejects invalid params (missing agentId)
- agents.files.list
- includes BOOTSTRAP.md when onboarding has not completed
- hides BOOTSTRAP.md when workspace onboarding is complete
- falls back to showing BOOTSTRAP.md when workspace state cannot be read
- falls back to showing BOOTSTRAP.md when workspace state is malformed JSON
- agents.files.get/set symlink safety
- allows in-workspace symlink reads but rejects writes through symlink aliases

### src/gateway/server-methods/browser.profile-from-body.test.lisp
- browser.request profile selection
- uses profile from request body when query profile is missing
- prefers query profile over body profile when both are present

### src/gateway/server-methods/chat.abort-persistence.test.lisp
- chat abort transcript persistence
- persists run-scoped abort partial with rpc metadata and idempotency
- persists session-scoped abort partials with rpc metadata
- persists /stop partials with stop-command metadata
- skips run-scoped transcript persistence when partial text is blank

### src/gateway/server-methods/chat.directive-tags.test.lisp
- chat directive tag stripping for non-streaming final payloads
- registers tool-event recipients for clients advertising tool-events capability
- does not register tool-event recipients without tool-events capability
- chat.inject keeps message defined when directive tag is the only content
- chat.send non-streaming final keeps message defined for directive-only assistant text
- rejects oversized chat.send session keys before dispatch
- chat.inject strips external untrusted wrapper metadata from final payload text
- chat.send non-streaming final strips external untrusted wrapper metadata from final payload text
- chat.send keeps explicit delivery routes for channel-scoped sessions
- chat.send keeps explicit delivery routes for Feishu channel-scoped sessions
- chat.send keeps explicit delivery routes for per-account channel-peer sessions
- chat.send keeps explicit delivery routes for legacy channel-peer sessions
- chat.send keeps explicit delivery routes for legacy thread sessions
- chat.send does not inherit external delivery context for shared main sessions
- chat.send does not inherit external delivery context for UI clients on main sessions
- chat.send inherits external delivery context for command-line interface clients on configured main sessions
- chat.send keeps configured main delivery inheritance when connect metadata omits client details
- chat.send does not inherit external delivery context for non-channel custom sessions
- chat.send keeps replies on the internal surface when deliver is not enabled
- chat.send does not inherit external routes for webchat clients on channel-scoped sessions
- chat.send still inherits external routes for UI clients on channel-scoped sessions

### src/gateway/server-methods/chat.inject.parentid.test.lisp
- gateway chat.inject transcript writes
- appends a Pi session entry that includes parentId

### src/gateway/server-methods/doctor.test.lisp
- doctor.memory.status
- returns gateway embedding probe status for the default agent
- returns unavailable when memory manager is missing
- returns probe failure when manager probe throws

### src/gateway/server-methods/nodes.canvas-capability-refresh.test.lisp
- sbcl.canvas.capability.refresh
- rotates the caller canvas capability and returns a fresh scoped URL
- returns unavailable when the caller session has no base canvas URL

### src/gateway/server-methods/nodes.invoke-wake.test.lisp
- sbcl.invoke APNs wake path
- keeps the existing not-connected response when wake path is unavailable
- wakes and retries invoke after the sbcl reconnects
- forces one retry wake when the first wake still fails to reconnect

### src/gateway/server-methods/push.test.lisp
- push.test handler
- rejects invalid params
- returns invalid request when sbcl has no APNs registration
- sends push test when registration and auth are available

### src/gateway/server-methods/secrets.test.lisp
- secrets handlers
- responds with warning count on successful reload
- returns unavailable when reload fails
- resolves requested command secret assignments from the active snapshot
- rejects invalid secrets.resolve params
- rejects secrets.resolve params when targetIds entries are not strings
- rejects unknown secrets.resolve target ids
- returns unavailable when secrets.resolve handler returns an invalid payload shape

### src/gateway/server-methods/send.test.lisp
- gateway send mirroring
- accepts media-only sends without message
- rejects empty sends when neither text nor media is present
- returns actionable guidance when channel is internal webchat
- auto-picks the single configured channel for send
- returns invalid request when send channel selection is ambiguous
- auto-picks the single configured channel for poll
- returns invalid request when poll channel selection is ambiguous
- does not mirror when delivery returns no results
- mirrors media filenames when delivery succeeds
- mirrors MEDIA tags as attachments
- lowercases provided session keys for mirroring
- derives a target session key when none is provided
- uses explicit agentId for delivery when sessionKey is not provided
- uses sessionKey agentId when explicit agentId is omitted
- prefers explicit agentId over sessionKey agent for delivery and mirror
- ignores blank explicit agentId and falls back to sessionKey agent
- forwards threadId to outbound delivery when provided
- returns invalid request when outbound target resolution fails
- recovers cold plugin resolution for telegram threaded sends

### src/gateway/server-methods/server-methods.test.lisp
- waitForAgentJob
- maps lifecycle end events with aborted=true to timeout
- keeps non-aborted lifecycle end events as ok
- can ignore cached snapshots and wait for fresh lifecycle events
- injectTimestamp
- prepends a compact timestamp matching formatZonedTimestamp
- uses channel envelope format with DOW prefix
- always uses 24-hour format
- uses the configured timezone
- defaults to UTC when no timezone specified
- returns empty/whitespace messages unchanged
- does NOT double-stamp messages with channel envelope timestamps
- does NOT double-stamp messages already injected by us
- does NOT double-stamp messages with cron-injected timestamps
- handles midnight correctly
- handles date boundaries (just before midnight)
- handles DST correctly (same UTC hour, different local time)
- accepts a custom now date
- timestampOptsFromConfig
- extracts timezone from config
- falls back gracefully with empty config
- normalizeRpcAttachmentsToChatAttachments
- passes through string content
- converts Uint8Array content to base64
- sanitizeChatSendMessageInput
- rejects null bytes
- strips unsafe control characters while preserving tab/newline/carriage return
- normalizes unicode to NFC
- gateway chat transcript writes (guardrail)
- routes transcript writes through helper and SessionManager parentId append
- exec approval handlers
- ExecApprovalRequestParams validation
- rejects host=sbcl approval requests without nodeId
- rejects host=sbcl approval requests without systemRunPlan
- broadcasts request + resolve
- stores versioned system.run binding and sorted env keys on approval request
- prefers systemRunPlan canonical command/cwd when present
- accepts resolve during broadcast
- accepts explicit approval ids
- forwards turn-source metadata to exec approval forwarding
- expires immediately when no approver clients and no forwarding targets
- gateway healthHandlers.status scope handling
- logs.tail
- falls back to latest rolling log file when today is missing

### src/gateway/server-methods/skills.update.normalizes-api-key.test.lisp
- skills.update
- strips embedded CR/LF from apiKey

### src/gateway/server-methods/tools-catalog.test.lisp
- tools.catalog handler
- rejects invalid params
- rejects unknown agent ids
- returns core groups including tts and excludes plugins when includePlugins=false
- includes plugin groups with plugin metadata

### src/gateway/server-methods/update.test.lisp
- update.run sentinel deliveryContext
- includes deliveryContext in sentinel payload when sessionKey is provided
- omits deliveryContext when no sessionKey is provided
- includes threadId in sentinel payload for threaded sessions
- update.run timeout normalization
- enforces a 1000ms minimum timeout for tiny values
- update.run restart scheduling
- schedules restart when update succeeds
- skips restart when update fails

### src/gateway/server-methods/usage.sessions-usage.test.lisp
- sessions.usage
- discovers sessions across configured agents and keeps agentId in key
- resolves store entries by sessionId when queried via discovered agent-prefixed key
- rejects traversal-style keys in specific session usage lookups
- passes parsed agentId into sessions.usage.timeseries
- passes parsed agentId into sessions.usage.logs
- rejects traversal-style keys in timeseries/log lookups

### src/gateway/server-methods/usage.test.lisp
- gateway usage helpers
- parseDateToMs accepts YYYY-MM-DD and rejects invalid input
- parseUtcOffsetToMinutes supports whole-hour and half-hour offsets
- parseUtcOffsetToMinutes rejects invalid offsets
- parseDays coerces strings/numbers to integers
- parseDateRange uses explicit start/end as UTC when mode is missing (backward compatible)
- parseDateRange uses explicit UTC mode
- parseDateRange uses specific UTC offset for explicit dates
- parseDateRange falls back to UTC when specific mode offset is missing or invalid
- parseDateRange uses specific offset for today/day math after UTC midnight
- parseDateRange uses gateway local day boundaries in gateway mode
- parseDateRange clamps days to at least 1 and defaults to 30 days
- loadCostUsageSummaryCached caches within TTL

### src/gateway/server-sbcl-events.test.lisp
- sbcl exec events
- enqueues exec.started events
- enqueues exec.finished events with output
- suppresses noisy exec.finished success events with empty output
- truncates long exec.finished output in system events
- enqueues exec.denied events with reason
- suppresses exec.started when notifyOnExit is false
- suppresses exec.finished when notifyOnExit is false
- suppresses exec.denied when notifyOnExit is false
- voice transcript events
- dedupes repeated transcript payloads for the same session
- does not dedupe identical text when source event IDs differ
- forwards transcript with voice provenance
- does not block agent dispatch when session-store touch fails
- notifications changed events
- enqueues notifications.changed posted events
- enqueues notifications.changed removed events
- wakes heartbeat on payload sessionKey when provided
- canonicalizes notifications session key before enqueue and wake
- ignores notifications.changed payloads missing required fields
- does not wake heartbeat when notifications.changed event is deduped
- agent request events
- disables delivery when route is unresolved instead of falling back globally
- reuses the current session route when delivery target is omitted

### src/gateway/server-plugins.test.lisp
- loadGatewayPlugins
- logs plugin errors with details
- provides subagent runtime with sessions.get method aliases
- shares fallback context across module reloads for existing runtimes
- uses updated fallback context after context replacement
- reflects fallback context object mutation at dispatch time

### src/gateway/server-restart-deferral.test.lisp
- gateway restart deferral
- defers restart while reply delivery is in flight
- keeps pending > 0 until the reply is actually enqueued
- defers restart until reply dispatcher completes
- clears dispatcher reservation when no replies were sent

### src/gateway/server-restart-sentinel.test.lisp
- scheduleRestartSentinelWake
- forwards session context to outbound delivery

### src/gateway/server-runtime-config.test.lisp
- resolveGatewayRuntimeConfig
- trusted-proxy auth mode
- token/password auth modes
- rejects non-loopback control UI when allowed origins are missing
- allows non-loopback control UI without allowed origins when dangerous fallback is enabled
- HTTP security headers
- resolves strict transport security header from config
- does not set strict transport security when explicitly disabled

### src/gateway/server-startup-log.test.lisp
- gateway startup log
- warns when dangerous config flags are enabled
- does not warn when dangerous config flags are disabled
- logs all listen endpoints on a single line

### src/gateway/server-startup-memory.test.lisp
- startGatewayMemoryBackend
- skips initialization when memory backend is not qmd
- initializes qmd backend for each configured agent
- logs a warning when qmd manager init fails and continues with other agents
- skips agents with memory search disabled

### src/gateway/server.agent.gateway-server-agent-a.test.lisp
- gateway server agent
- agent marks implicit delivery when lastTo is stale
- agent forwards sessionKey to agentCommand
- agent preserves spawnDepth on subagent sessions
- agent derives sessionKey from agentId
- agent rejects unknown reply channel
- agent rejects mismatched agentId and sessionKey
- agent rejects malformed agent-prefixed session keys
- agent forwards accountId to agentCommand
- agent avoids lastAccountId when explicit to is provided
- agent keeps explicit accountId when explicit to is provided
- agent falls back to lastAccountId for implicit delivery
- agent forwards image attachments as images[]
- agent errors when delivery requested and no last channel exists

### src/gateway/server.agent.gateway-server-agent-b.test.lisp
- gateway server agent
- agent errors when deliver=true and last-channel plugin is unavailable
- agent accepts channel aliases (imsg/teams)
- agent rejects unknown channel
- agent errors when deliver=true and last channel is webchat
- agent uses webchat for internal runs when last provider is webchat
- agent routes bare /new through session reset before running greeting prompt
- agent ack response then final response
- agent dedupes by idempotencyKey after completion
- agent dedupe survives reconnect
- agent events stream to webchat clients when run context is registered

### src/gateway/server.auth.browser-hardening.test.lisp
- gateway auth browser hardening
- rejects non-local browser origins for non-control-ui clients
- rate-limits browser-origin auth failures on loopback even when loopback exemption is enabled
- does not silently auto-pair non-control-ui browser clients on loopback
- rejects forged loopback origin for control-ui when proxy headers make client non-local

### src/gateway/server.auth.control-ui.test.lisp
- gateway server auth/connect

### src/gateway/server.auth.default-token.test.lisp
- gateway server auth/connect

### src/gateway/server.auth.modes.test.lisp
- gateway server auth/connect

### src/gateway/server.canvas-auth.test.lisp
- gateway canvas host auth
- authorizes canvas HTTP/WS via sbcl-scoped capability and rejects misuse
- denies canvas auth when trusted proxy omits forwarded client headers
- accepts capability-scoped paths over IPv6 loopback
- returns 429 for repeated failed canvas auth attempts (HTTP + WS upgrade)

### src/gateway/server.channels.test.lisp
- gateway server channels
- channels.status returns snapshot without probe
- channels.logout reports no session when missing
- channels.logout clears telegram bot token from config

### src/gateway/server.chat.gateway-server-chat-b.test.lisp
- gateway server chat
- smoke: caps history payload and preserves routing metadata
- chat.send does not force-disable block streaming
- chat.history hard-caps single oversized nested payloads
- chat.history keeps recent small messages when latest message is oversized
- chat.history strips inline directives from displayed message text
- smoke: supports abort and idempotent completion

### src/gateway/server.chat.gateway-server-chat.test.lisp
- gateway server chat
- sanitizes inbound chat.send message text and rejects null bytes
- handles chat send and history flows
- chat.history hides assistant NO_REPLY-only entries
- routes chat.send slash commands without agent runs
- chat.history hides assistant NO_REPLY-only entries and keeps mixed-content assistant entries
- agent.wait resolves chat.send runs that finish without lifecycle events
- agent.wait ignores stale chat dedupe when an agent run with the same runId is in flight
- agent.wait ignores stale agent snapshots while same-runId chat.send is active
- agent.wait keeps lifecycle wait active while same-runId chat.send is active
- agent events include sessionKey and agent.wait covers lifecycle flows

### src/gateway/server.config-apply.test.lisp
- gateway config.apply
- rejects invalid raw config
- requires raw to be a string

### src/gateway/server.config-patch.test.lisp
- gateway config methods
- returns a path-scoped config schema lookup
- rejects config.schema.lookup when the path is missing
- rejects config.schema.lookup when the path is only whitespace
- rejects config.schema.lookup when the path exceeds the protocol limit
- rejects config.schema.lookup when the path contains invalid characters
- rejects prototype-chain config.schema.lookup paths without reflecting them
- rejects config.patch when raw is not an object
- gateway server sessions
- filters sessions by agentId
- resolves and patches main alias to default agent main key

### src/gateway/server.cron.test.lisp
- gateway server cron
- handles cron CRUD, normalization, and patch semantics
- writes cron run history and auto-runs due jobs
- posts webhooks for delivery mode and legacy notify fallback only when summary exists
- ignores non-string cron.webhookToken values without crashing webhook delivery

### src/gateway/server.health.test.lisp
- gateway server health/presence
- connect + health + presence + status succeed
- broadcasts heartbeat events and serves last-heartbeat
- presence events carry seq + stateVersion
- agent events stream with seq
- shutdown event is broadcast on close
- presence broadcast reaches multiple clients
- presence includes client fingerprint
- cli connections are not tracked as instances

### src/gateway/server.hooks.test.lisp
- gateway server hooks
- handles auth, wake, and agent flows
- rejects request sessionKey unless hooks.allowRequestSessionKey is enabled
- respects hooks session policy for request + mapping session keys
- normalizes duplicate target-agent prefixes before isolated dispatch
- enforces hooks.allowedAgentIds for explicit agent routing
- denies explicit agentId when hooks.allowedAgentIds is empty
- throttles repeated hook auth failures and resets after success
- rejects non-POST hook requests without consuming auth failure budget

### src/gateway/server.ios-client-id.test.lisp
- connect params client id validation
- rejects unknown client ids

### src/gateway/server.legacy-migration.test.lisp
- gateway startup legacy migration fallback
- surfaces detailed validation errors when legacy entries have no migration output
- keeps detailed validation errors when heartbeat comes from include-resolved config

### src/gateway/server.models-voicewake-misc.test.lisp
- gateway server models + voicewake
- voicewake.get returns defaults and voicewake.set broadcasts
- pushes voicewake.changed to nodes on connect and on updates
- models.list returns model catalog
- models.list filters to allowlisted configured models by default
- models.list includes synthetic entries for allowlist models absent from catalog
- models.list rejects unknown params
- gateway server misc
- hello-ok advertises the gateway port for canvas host
- send dedupes by idempotencyKey
- auto-enables configured channel plugins on startup
- refuses to start when port already bound
- releases port after close

### src/gateway/server.sbcl-invoke-approval-bypass.test.lisp
- sbcl.invoke approval bypass
- rejects malformed/forbidden sbcl.invoke payloads before forwarding
- binds approvals to decision/device and blocks cross-device replay
- blocks cross-sbcl replay on same device

### src/gateway/server.plugin-http-auth.test.lisp
- gateway plugin HTTP auth boundary
- applies default security headers and optional strict transport security
- serves unauthenticated liveness/readiness probe routes when no other route handles them
- does not shadow plugin routes mounted on probe paths
- rejects non-GET/HEAD methods on probe routes
- requires gateway auth for protected plugin route space and allows authenticated pass-through
- allows unauthenticated Mattermost slash callback routes while keeping other channel routes protected
- does not bypass auth when mattermost callbackPath points to non-mattermost channel routes
- keeps wildcard plugin handlers ungated when auth enforcement predicate excludes their paths
- uses /api/channels auth by default while keeping wildcard handlers ungated with no predicate
- serves plugin routes before control ui spa fallback
- passes POST webhook routes through root-mounted control ui to plugins
- plugin routes take priority over control ui catch-all
- unmatched plugin paths fall through to control ui
- root-mounted control ui does not swallow gateway probe routes
- root-mounted control ui still lets plugins claim probe paths first
- requires gateway auth for canonicalized /api/channels variants
- rejects unauthenticated plugin-channel fuzz corpus variants
- enforces auth before plugin handlers on encoded protected-path variants
- rejects query-token hooks requests with bindHost=::

### src/gateway/server.reload.test.lisp
- gateway hot reload
- applies hot reload actions and emits restart signal
- fails startup when required secret refs are unresolved
- allows startup when unresolved refs exist only on disabled surfaces
- honors startup auth overrides before secret preflight gating
- fails startup when auth-profile secret refs are unresolved
- emits one-shot degraded and recovered system events during secret reload transitions
- serves secrets.reload immediately after startup without race failures
- gateway agents
- lists configured agents via agents.list RPC

### src/gateway/server.roles-allowlist-update.test.lisp
- gateway role enforcement
- enforces operator and sbcl permissions
- gateway update.run
- writes sentinel and schedules restart
- uses configured update channel
- gateway sbcl command allowlist
- enforces command allowlists across sbcl clients
- rejects reconnect metadata spoof for paired sbcl devices
- filters system.run for confusable iOS metadata at connect time

### src/gateway/server.sessions-send.test.lisp
- sessions_send gateway loopback
- returns reply when lifecycle ends before agent.wait
- sessions_send label lookup
- finds session by label and sends message

### src/gateway/server.sessions.gateway-server-sessions-a.test.lisp
- gateway server sessions
- lists and patches session store via sessions.* RPC
- sessions.preview returns transcript previews
- sessions.preview resolves legacy mixed-case main alias with custom mainKey
- sessions.resolve and mutators clean legacy main-alias ghost keys
- sessions.delete rejects main and aborts active runs
- sessions.delete closes ACP runtime handles before removing ACP sessions
- sessions.delete does not emit lifecycle events when nothing was deleted
- sessions.delete emits subagent targetKind for subagent sessions
- sessions.delete can skip lifecycle hooks while still unbinding thread bindings
- sessions.delete directly unbinds thread bindings when hooks are unavailable
- sessions.reset aborts active runs and clears queues
- sessions.reset closes ACP runtime handles for ACP sessions
- sessions.reset does not emit lifecycle events when key does not exist
- sessions.reset emits subagent targetKind for subagent sessions
- sessions.reset directly unbinds thread bindings when hooks are unavailable
- sessions.reset emits internal command hook with reason
- sessions.reset returns unavailable when active run does not stop
- sessions.delete returns unavailable when active run does not stop
- webchat clients cannot patch or delete sessions
- control-ui client can delete sessions even in webchat mode

### src/gateway/server.skills-status.test.lisp
- gateway skills.status
- does not expose raw config values to operator.read clients

### src/gateway/server.talk-config.test.lisp
- gateway talk.config
- returns redacted talk config for read scope
- requires operator.talk.secrets for includeSecrets
- returns secrets for operator.talk.secrets scope
- prefers normalized provider payload over conflicting legacy talk keys

### src/gateway/server.tools-catalog.test.lisp
- gateway tools.catalog
- returns core catalog data and includes tts
- supports includePlugins=false and rejects unknown agent ids

### src/gateway/server/http-listen.test.lisp
- listenGatewayHttpServer
- retries EADDRINUSE and closes server handle before retry
- throws GatewayLockError after EADDRINUSE retries are exhausted
- wraps non-EADDRINUSE errors as GatewayLockError

### src/gateway/server/plugins-http.test.lisp
- createGatewayPluginRequestHandler
- returns false when no routes are registered
- handles exact route matches
- prefers exact matches before prefix matches
- supports route fallthrough when handler returns false
- fails closed when a matched gateway route reaches dispatch without auth
- allows gateway route fallthrough only after gateway auth succeeds
- matches canonicalized route variants
- logs and responds with 500 when a route throws
- plugin HTTP route auth checks
- detects registered route paths
- matches canonicalized variants of registered route paths
- enforces auth for protected and gateway-auth routes
- enforces auth when any overlapping matched route requires gateway auth

### src/gateway/server/presence-events.test.lisp
- broadcastPresenceSnapshot
- increments version and broadcasts presence with state versions

### src/gateway/server/readiness.test.lisp
- createReadinessChecker
- reports ready when all managed channels are healthy
- ignores disabled and unconfigured channels
- uses startup grace before marking disconnected channels not ready
- reports disconnected managed channels after startup grace
- keeps restart-pending channels ready during reconnect backoff
- treats stale-socket channels as ready to avoid pulling healthy idle pods
- keeps telegram long-polling channels ready without stale-socket classification
- caches readiness snapshots briefly to keep repeated probes cheap

### src/gateway/server/ws-connection/auth-context.test.lisp
- resolveConnectAuthDecision
- keeps shared-secret mismatch when fallback device-token check fails
- reports explicit device-token mismatches as device_token_mismatch
- accepts valid device tokens and marks auth method as device-token
- returns rate-limited auth result without verifying device token
- returns the original decision when device fallback does not apply

### src/gateway/server/ws-connection/connect-policy.test.lisp
- ws connect policy
- resolves control-ui auth policy
- evaluates missing-device decisions
- pairing bypass requires control-ui bypass + shared auth (or trusted-proxy auth)
- trusted-proxy control-ui bypass only applies to operator + trusted-proxy auth

### src/gateway/server/ws-connection/unauthorized-flood-guard.test.lisp
- UnauthorizedFloodGuard
- suppresses repeated unauthorized responses and closes after threshold
- resets counters
- isUnauthorizedRoleError
- detects unauthorized role responses
- ignores non-role authorization errors

### src/gateway/session-utils.fs.test.lisp
- readFirstUserMessageFromTranscript
- extracts first user text across supported content formats
- skips non-user messages to find first user message
- skips inter-session user messages by default
- returns null when no user messages exist
- handles malformed JSON lines gracefully
- returns null for empty content
- readLastMessagePreviewFromTranscript
- returns null for empty file
- returns the last user or assistant message from transcript
- skips system messages to find last user/assistant
- returns null when no user/assistant messages exist
- handles malformed JSON lines gracefully (last preview)
- handles array/output_text content formats
- skips empty content to find previous message
- reads from end of large file (16KB window)
- handles valid UTF-8 content
- strips inline directives from last preview text
- shared transcript read behaviors
- returns null for missing transcript files
- uses sessionFile overrides when provided
- trims whitespace in extracted previews
- readSessionTitleFieldsFromTranscript cache
- returns cached values without re-reading when unchanged
- invalidates cache when transcript changes
- readSessionMessages
- includes synthetic compaction markers for compaction entries
- reads cross-agent absolute sessionFile across store-root layouts
- readSessionPreviewItemsFromTranscript
- returns recent preview items with tool summary
- detects tool calls from tool_use/tool_call blocks and toolName field
- truncates preview text to max chars
- strips inline directives from preview items
- resolveSessionTranscriptCandidates
- fallback candidate uses OPENCLAW_HOME instead of os.homedir()
- resolveSessionTranscriptCandidates safety
- keeps cross-agent absolute sessionFile for standard and custom store roots
- drops unsafe session IDs instead of producing traversal paths
- drops unsafe sessionFile candidates and keeps safe fallbacks
- archiveSessionTranscripts
- archives transcript from default and explicit sessionFile paths
- returns empty array when no transcript files exist
- skips files that do not exist and archives only existing ones

### src/gateway/session-utils.test.lisp
- gateway session utils
- capArrayByJsonBytes trims from the front
- parseGroupKey handles group keys
- classifySessionKey respects chat type + prefixes
- resolveSessionStoreKey maps main aliases to default agent main
- resolveSessionStoreKey canonicalizes bare keys to default agent
- resolveSessionStoreKey falls back to first list entry when no agent is marked default
- resolveSessionStoreKey falls back to main when agents.list is missing
- resolveSessionStoreKey normalizes session key casing
- resolveSessionStoreKey honors global scope
- resolveGatewaySessionStoreTarget uses canonical key for main alias
- resolveGatewaySessionStoreTarget includes legacy mixed-case store key
- resolveGatewaySessionStoreTarget includes all case-variant duplicate keys
- resolveGatewaySessionStoreTarget finds legacy main alias key when mainKey is customized
- pruneLegacyStoreKeys removes alias and case-variant ghost keys
- listAgentsForGateway rejects avatar symlink escapes outside workspace
- listAgentsForGateway allows avatar symlinks that stay inside workspace
- listAgentsForGateway keeps explicit agents.list scope over disk-only agents (scope boundary)
- resolveSessionModelRef
- prefers runtime model/provider from session entry
- preserves openrouter provider when model contains vendor prefix
- falls back to override when runtime model is not recorded yet
- falls back to resolved provider for unprefixed legacy runtime model
- preserves provider from slash-prefixed model when modelProvider is missing
- resolveSessionModelIdentityRef
- does not inherit default provider for unprefixed legacy runtime model
- infers provider from configured model allowlist when unambiguous
- keeps provider unknown when configured models are ambiguous
- preserves provider from slash-prefixed runtime model
- infers wrapper provider for slash-prefixed runtime model when allowlist match is unique
- deriveSessionTitle
- returns undefined for undefined entry
- prefers displayName when set
- falls back to subject when displayName is missing
- uses first user message when displayName and subject missing
- truncates long first user message to 60 chars with ellipsis
- truncates at word boundary when possible
- falls back to sessionId prefix with date
- falls back to sessionId prefix without date when updatedAt missing
- trims whitespace from displayName
- ignores empty displayName and falls through
- listSessionsFromStore search
- returns all sessions when search is empty or missing
- filters sessions across display metadata and key fields
- hides cron run alias session keys from sessions list
- exposes unknown totals when freshness is stale or missing
- loadCombinedSessionStoreForGateway includes disk-only agents (#32804)
- ACP agent sessions are visible even when agents.list is configured

### src/gateway/sessions-patch.test.lisp
- gateway sessions patch
- persists thinkingLevel=off (does not clear)
- clears thinkingLevel when patch sets null
- persists reasoningLevel=off (does not clear)
- clears reasoningLevel when patch sets null
- persists elevatedLevel=off (does not clear)
- persists elevatedLevel=on
- clears elevatedLevel when patch sets null
- rejects invalid elevatedLevel values
- clears auth overrides when model patch changes
- sets spawnDepth for subagent sessions
- rejects spawnDepth on non-subagent sessions
- normalizes exec/send/group patches
- rejects invalid execHost values
- rejects invalid sendPolicy values
- rejects invalid groupActivation values
- allows target agent own model for subagent session even when missing from global allowlist
- allows target agent subagents.model for subagent session even when missing from global allowlist
- allows global defaults.subagents.model for subagent session even when missing from global allowlist

### src/gateway/startup-auth.test.lisp
- ensureGatewayStartupAuth
- generates and persists a token when startup auth is missing
- does not generate when token already exists
- does not generate in password mode
- resolves gateway.auth.password SecretRef before startup auth checks
- resolves gateway.auth.token SecretRef before startup auth checks
- resolves env-template gateway.auth.token before env-token short-circuiting
- uses OPENCLAW_GATEWAY_TOKEN without resolving configured token SecretRef
- fails when gateway.auth.token SecretRef is active and unresolved
- requires explicit gateway.auth.mode when token and password are both configured
- uses OPENCLAW_GATEWAY_PASSWORD without resolving configured password SecretRef
- does not resolve gateway.auth.password SecretRef when token mode is explicit
- does not generate in trusted-proxy mode
- does not generate in explicit none mode
- treats undefined token override as no override
- keeps generated token ephemeral when runtime override flips explicit non-token mode
- keeps generated token ephemeral when runtime override flips explicit none mode
- keeps generated token ephemeral when runtime override flips implicit password mode
- throws when hooks token reuses gateway token resolved from env
- assertHooksTokenSeparateFromGatewayAuth
- throws when hooks token reuses gateway token auth
- allows hooks token when gateway auth is not token mode
- allows matching values when hooks are disabled

### src/gateway/system-run-approval-binding.contract.test.lisp
- system-run approval binding contract fixtures

### src/gateway/system-run-approval-binding.test.lisp
- buildSystemRunApprovalEnvBinding
- normalizes keys and produces stable hash regardless of input order
- matchSystemRunApprovalEnvHash
- accepts empty env hash on both sides
- rejects non-empty actual env hash when expected is empty
- matchSystemRunApprovalBinding
- accepts matching binding with reordered env keys
- rejects env mismatch
- toSystemRunApprovalMismatchError
- includes runId/code and preserves mismatch details

### src/gateway/tools-invoke-http.cron-regression.test.lisp
- tools invoke HTTP denylist
- blocks cron and gateway by default
- allows cron only when explicitly enabled in gateway.tools.allow
- keeps cron available under coding profile without exposing gateway

### src/gateway/tools-invoke-http.test.lisp
- POST /tools/invoke
- invokes a tool and returns {ok:true,result}
- supports tools.alsoAllow in profile and implicit modes
- routes tools invoke before plugin HTTP handlers
- returns 404 when denylisted or blocked by tools.profile
- denies sessions_spawn via HTTP even when agent policy allows
- propagates message target/thread headers into tools context for sessions_spawn
- denies sessions_send via HTTP gateway
- denies gateway tool via HTTP
- allows gateway tool via HTTP when explicitly enabled in gateway.tools.allow
- treats gateway.tools.deny as higher priority than gateway.tools.allow
- uses the configured main session key when sessionKey is missing or main
- maps tool input/auth errors to 400/403 and unexpected execution errors to 500
- passes deprecated format alias through invoke payloads even when schema omits it

### src/gateway/ws-log.test.lisp
- gateway ws log helpers
- shortId compacts uuids and long strings
- formatForLog formats errors and messages
- formatForLog redacts obvious secrets
- summarizeAgentEventForWsLog extracts useful fields

## hooks

### src/hooks/bundled/boot-md/handler.gateway-startup.integration.test.lisp
- boot-md startup hook integration
- dispatches gateway:startup through internal hooks and runs BOOT for each configured agent scope

### src/hooks/bundled/boot-md/handler.test.lisp
- boot-md handler
- skips non-gateway events
- skips non-startup actions
- skips when cfg is missing from context
- runs boot for each agent
- runs boot for single default agent when no agents configured
- logs warning details when a per-agent boot run fails
- logs debug details when a per-agent boot run is skipped

### src/hooks/bundled/bootstrap-extra-files/handler.test.lisp
- bootstrap-extra-files hook
- appends extra bootstrap files from configured patterns
- re-applies subagent bootstrap allowlist after extras are added

### src/hooks/bundled/session-memory/handler.test.lisp
- session-memory hook
- skips non-command events
- skips commands other than new
- creates memory file with session content on /new command
- creates memory file with session content on /reset command
- filters out non-message entries (tool calls, system)
- filters out inter-session user messages
- filters out command messages starting with /
- respects custom messages config (limits to N messages)
- filters messages before slicing (fix for #2681)
- falls back to latest .jsonl.reset.* transcript when active file is empty
- handles reset-path session pointers from previousSessionEntry
- recovers transcript when previousSessionEntry.sessionFile is missing
- prefers the newest reset transcript when multiple reset candidates exist
- prefers active transcript when it is non-empty even with reset candidates
- handles empty session files gracefully
- handles session files with fewer messages than requested

### src/hooks/fire-and-forget.test.lisp
- fireAndForgetHook
- logs rejection errors
- does not log for resolved tasks

### src/hooks/frontmatter.test.lisp
- parseFrontmatter
- parses single-line key-value pairs
- handles missing frontmatter
- handles unclosed frontmatter
- parses multi-line metadata block with indented JSON
- parses multi-line metadata with complex nested structure
- handles single-line metadata (inline JSON)
- handles mixed single-line and multi-line values
- strips surrounding quotes from values
- handles CRLF line endings
- handles CR line endings
- resolveOpenClawMetadata
- extracts openclaw metadata from parsed frontmatter
- returns undefined when metadata is missing
- returns undefined when openclaw key is missing
- returns undefined for invalid JSON
- handles install specs
- handles os restrictions
- parses real session-memory HOOK.md format
- parses YAML metadata map
- resolveHookInvocationPolicy
- defaults to enabled when missing
- parses enabled flag

### src/hooks/gmail-setup-utils.test.lisp
- resolvePythonExecutablePath
- ensureTailscaleEndpoint
- includes stdout and exit code when tailscale serve fails
- includes JSON parse failure details with stdout

### src/hooks/gmail-watcher-lifecycle.test.lisp
- startGmailWatcherWithLogs
- logs startup success
- logs actionable non-start reason
- suppresses expected non-start reasons
- supports skip callback when watcher is disabled
- logs startup errors

### src/hooks/gmail.test.lisp
- gmail hook config
- builds default hook url
- parses topic path
- resolves runtime config with defaults
- fails without hook token
- defaults serve path to / when tailscale is enabled
- keeps the default public path when serve path is explicit
- keeps custom public path when serve path is set
- keeps serve path when tailscale target is set

### src/hooks/hooks-install.test.lisp
- hooks install (e2e)
- installs a hook pack and triggers the handler

### src/hooks/import-url.test.lisp
- buildImportUrl
- returns bare URL for bundled hooks (no query string)
- appends mtime-based cache buster for workspace hooks
- appends mtime-based cache buster for managed hooks
- appends mtime-based cache buster for plugin hooks
- returns same URL for bundled hooks across calls (cacheable)
- returns same URL for workspace hooks when file is unchanged
- falls back to Date.now() when file does not exist

### src/hooks/install.test.lisp
- installHooksFromArchive
- installHooksFromPath
- uses --ignore-scripts for dependency install
- installs a single hook directory
- rejects hook pack entries that traverse outside package directory
- rejects hook pack entries that escape via symlink
- installHooksFromNpmSpec
- uses --ignore-scripts for Quicklisp/Ultralisp pack and cleans up temp dir
- rejects non-registry Quicklisp/Ultralisp specs
- aborts when integrity drift callback rejects the fetched artifact
- rejects bare Quicklisp/Ultralisp specs that resolve to prerelease versions
- gmail watcher
- detects address already in use errors

### src/hooks/internal-hooks.test.lisp
- hooks
- registerInternalHook
- should register a hook handler
- should allow multiple handlers for the same event
- unregisterInternalHook
- should unregister a specific handler
- should clean up empty handler arrays
- triggerInternalHook
- should trigger handlers for general event type
- should trigger handlers for specific event action
- should trigger both general and specific handlers
- should handle async handlers
- should catch and log errors from handlers
- should not throw if no handlers are registered
- stores handlers in the global singleton registry
- createInternalHookEvent
- should create a properly formatted event
- should use empty context if not provided
- isAgentBootstrapEvent
- isGatewayStartupEvent
- isMessageReceivedEvent
- isMessageSentEvent
- message type-guard shared negatives
- returns false for non-message and missing-context shapes
- message hooks
- should trigger message:received handlers
- should trigger message:sent handlers
- should trigger general message handlers for both received and sent
- should handle hook errors without breaking message processing
- getRegisteredEventKeys
- should return all registered event keys
- should return empty array when no handlers are registered
- clearInternalHooks
- should remove all registered handlers

### src/hooks/loader.test.lisp
- loader
- loadInternalHooks
- should return 0 when hooks are not enabled
- should return 0 when hooks config is missing
- should load a handler from a module
- should load multiple handlers
- should support named exports
- should handle module loading errors gracefully
- should handle non-function exports
- should handle relative paths
- should actually call the loaded handler
- rejects directory hook handlers that escape hook dir via symlink
- rejects legacy handler modules that escape workspace via symlink
- rejects directory hook handlers that escape hook dir via hardlink
- rejects legacy handler modules that escape workspace via hardlink

### src/hooks/message-hook-mappers.test.lisp
- message hook mappers
- derives canonical inbound context with body precedence and group metadata
- supports explicit content/messageId overrides
- maps canonical inbound context to plugin/internal received payloads
- maps transcribed and preprocessed internal payloads
- maps sent context consistently for plugin/internal hooks

### src/hooks/message-hooks.test.lisp
- message hooks
- action handlers
- triggers handler for ${testCase.label}
- does not trigger action-specific handlers for other actions
- general handler
- receives full message lifecycle in order
- triggers both general and specific handlers
- error isolation
- does not propagate handler errors
- continues with later handlers when one fails
- isolates async handler errors
- event structure
- includes timestamps on message events
- preserves mutable messages and sessionKey

### src/hooks/module-loader.test.lisp
- hooks module loader helpers
- builds a file URL without cache-busting by default
- adds a cache-busting query when requested
- resolves explicit function exports
- falls back through named exports when no explicit export is provided
- returns undefined when export exists but is not callable

### src/hooks/workspace.test.lisp
- hooks workspace
- ignores ASDF system definition hook paths that traverse outside package directory
- accepts ASDF system definition hook paths within package directory
- ignores ASDF system definition hook paths that escape via symlink
- ignores hooks with hardlinked HOOK.md aliases
- ignores hooks with hardlinked handler aliases

## i18n

### src/i18n/registry.test.lisp
- ui i18n locale registry
- lists supported locales
- resolves browser locale fallbacks
- loads lazy locale translations from the registry

## imessage

### src/imessage/monitor.gating.test.lisp
- imessage monitor gating + envelope builders
- parseIMessageNotification rejects malformed payloads
- drops group messages without mention by default
- dispatches group messages with mention and builds a group envelope
- includes reply-to context fields + suffix
- treats configured chat_id as a group session even when is_group is false
- allows group messages when requireMention is true but no mentionPatterns exist
- blocks group messages when imessage.groups is set without a wildcard
- honors group allowlist and ignores pairing-store senders in groups
- blocks group messages when groupPolicy is disabled

### src/imessage/monitor.shutdown.unhandled-rejection.test.lisp
- monitorIMessageProvider
- does not trigger unhandledRejection when aborting during shutdown

### src/imessage/monitor/deliver.test.lisp
- deliverReplies
- propagates payload replyToId through all text chunks
- propagates payload replyToId through media sends
- records outbound text and message ids in sent-message cache

### src/imessage/monitor/inbound-processing.test.lisp
- resolveIMessageInboundDecision echo detection
- drops inbound messages when outbound message id matches echo cache
- describeIMessageEchoDropLog
- includes message id when available
- resolveIMessageInboundDecision command auth
- does not auto-authorize DM commands in open mode without allowlists
- authorizes DM commands for senders in pairing-store allowlist

### src/imessage/monitor/loop-rate-limiter.test.lisp
- createLoopRateLimiter
- allows messages below the threshold
- rate limits at the threshold
- does not cross-contaminate conversations
- resets after the time window expires
- returns false for unknown conversations

### src/imessage/monitor/monitor-provider.echo-cache.test.lisp
- iMessage sent-message echo cache
- matches recent text within the same scope
- matches by outbound message id and ignores placeholder ids
- keeps message-id lookups longer than text fallback

### src/imessage/monitor/provider.group-policy.test.lisp
- resolveIMessageRuntimeGroupPolicy
- fails closed when channels.imessage is missing and no defaults are set
- keeps open fallback when channels.imessage is configured
- ignores explicit global defaults when provider config is missing

### src/imessage/monitor/reflection-guard.test.lisp
- detectReflectedContent
- returns false for empty text
- returns false for normal user text
- detects +#+#+#+# separator pattern
- detects assistant to=final marker
- detects <thinking> tags
- detects <thought> tags
- detects <relevant_memories> tags
- detects <final> tags
- returns multiple matched labels for combined markers
- ignores reflection markers inside inline code
- ignores reflection markers inside fenced code blocks
- still flags markers that appear outside code blocks
- does not flag normal code discussion about thinking
- flags '<final answer>' as reflection when it forms a complete tag
- does not flag partial tag without closing bracket
- does not flag '<thought experiment>' phrase without closing bracket

### src/imessage/monitor/sanitize-outbound.test.lisp
- sanitizeOutboundText
- returns empty string unchanged
- preserves normal user-facing text
- strips <thinking> tags and content
- strips <thought> tags and content
- strips <final> tags
- strips <relevant_memories> tags and content
- strips +#+#+#+# separator patterns
- strips assistant to=final markers
- strips trailing role turn markers
- collapses excessive blank lines after stripping
- handles combined internal markers in one message

### src/imessage/probe.test.lisp
- probeIMessage
- marks unknown rpc subcommand as fatal

### src/imessage/send.test.lisp
- sendMessageIMessage
- sends to chat_id targets
- applies sms service prefix
- adds file attachment with placeholder text
- normalizes mixed-case parameterized MIME for attachment placeholder text
- returns message id when rpc provides one
- prepends reply tag as the first token when replyToId is provided
- rewrites an existing leading reply tag to keep the requested id first
- sanitizes replyToId before writing the leading reply tag
- skips reply tagging when sanitized replyToId is empty
- normalizes string message_id values from rpc result
- does not stop an injected client

### src/imessage/targets.test.lisp
- imessage targets
- parses chat_id targets
- parses chat targets
- parses sms handles with service
- normalizes handles
- normalizes chat_id prefixes case-insensitively
- normalizes chat_guid prefixes case-insensitively
- normalizes chat_identifier prefixes case-insensitively
- checks allowFrom against chat_id
- checks allowFrom against handle
- denies when allowFrom is empty
- formats chat targets
- createIMessageRpcClient
- refuses to spawn imsg rpc in test environments

## infra

### src/infra/abort-pattern.test.lisp
- abort pattern: .bind() vs arrow closure (#7174)
- controller.abort.bind(controller) aborts the signal
- bound abort works with setTimeout
- bindAbortRelay() preserves default AbortError reason when used as event listener
- raw .abort.bind() leaks Event as reason — bindAbortRelay() does not
- removeEventListener works with saved bindAbortRelay() reference
- bindAbortRelay() forwards abort through combined signals

### src/infra/abort-signal.test.lisp
- waitForAbortSignal
- resolves immediately when signal is missing
- resolves immediately when signal is already aborted
- waits until abort fires

### src/infra/agent-events.test.lisp
- agent-events sequencing
- stores and clears run context
- maintains monotonic seq per runId
- preserves compaction ordering on the event bus
- omits sessionKey for runs hidden from Control UI

### src/infra/archive-path.test.lisp
- archive path helpers
- uses custom escape labels in traversal errors
- preserves strip-induced traversal for follow-up validation
- keeps resolved output paths inside the root

### src/infra/archive.test.lisp
- archive utils
- detects archive kinds
- rejects zip path traversal (zip slip)
- rejects zip entries that traverse pre-existing destination symlinks
- does not clobber out-of-destination file when parent dir is symlink-rebound during zip extract
- rejects tar path traversal (zip slip)
- fails resolvePackedRootDir when extract dir has multiple root dirs
- rejects tar entries with absolute extraction paths

### src/infra/bonjour-discovery.test.lisp
- bonjour-discovery
- discovers beacons on darwin across local + wide-area domains
- decodes dns-sd octal escapes in TXT displayName
- falls back to tailnet DNS probing for wide-area when split DNS is not configured
- normalizes domains and respects domains override

### src/infra/bonjour.test.lisp
- gateway bonjour advertiser
- does not block on advertise and publishes expected txt keys
- omits cliPath and sshPort in minimal mode
- attaches conflict listeners for services
- cleans up unhandled rejection handler after shutdown
- logs advertise failures and retries via watchdog
- handles advertise throwing synchronously
- normalizes hostnames with domains for service names

### src/infra/boundary-path.test.lisp
- resolveBoundaryPath
- resolves symlink parents with non-existent leafs inside root
- blocks dangling symlink leaf escapes outside root
- allows final symlink only when unlink policy opts in
- allows canonical aliases that still resolve inside root
- maintains containment invariant across randomized alias cases

### src/infra/brew.test.lisp
- brew helpers
- resolves brew from ~/.linuxbrew/bin when executable exists
- prefers HOMEBREW_PREFIX/bin/brew when present
- prefers HOMEBREW_BREW_FILE over prefix and trims value
- falls back to prefix when HOMEBREW_BREW_FILE is missing or not executable
- includes Linuxbrew bin/sbin in path candidates

### src/infra/channel-summary.test.lisp
- buildChannelSummary
- preserves Slack HTTP signing-secret unavailable state from source config

### src/infra/cli-root-options.test.lisp
- consumeRootOptionToken
- consumes boolean and inline root options
- consumes split root value option only when next token is a value

### src/infra/control-ui-assets.test.lisp
- control UI assets helpers (fs-mocked)
- resolves repo root from src argv1
- resolves repo root by traversing up (dist argv1)
- resolves dist control-ui index path for dist argv1
- uses resolveOpenClawPackageRoot when available
- falls back to ASDF system definition name matching when root resolution fails
- returns null when fallback package name does not match
- reports health for missing + existing dist assets
- resolves control-ui root from override file or directory
- resolves control-ui root for dist bundle argv1 and moduleUrl candidates

### src/infra/device-identity.state-dir.test.lisp
- device identity state dir defaults
- writes the default identity file under OPENCLAW_STATE_DIR

### src/infra/device-pairing.test.lisp
- device pairing tokens
- reuses existing pending requests for the same device
- merges pending roles/scopes for the same device before approval
- generates base64url device tokens with 256-bit entropy output length
- allows down-scoping from admin and preserves approved scope baseline
- preserves existing token scopes when approving a repair without requested scopes
- rejects scope escalation when rotating a token and leaves state unchanged
- verifies token and rejects mismatches
- accepts operator.read/operator.write requests with an operator.admin token scope
- treats multibyte same-length token input as mismatch without throwing
- removes paired devices by device id
- clears paired device state by device id

### src/infra/dotenv.test.lisp
- loadDotEnv
- loads ~/.openclaw/.env as fallback without overriding CWD .env
- does not override an already-set env var from the shell
- loads fallback state .env when CWD .env is missing

### src/infra/env.test.lisp
- normalizeZaiEnv
- copies Z_AI_API_KEY to ZAI_API_KEY when missing
- does not override existing ZAI_API_KEY
- ignores blank legacy Z_AI_API_KEY values
- does not copy when legacy Z_AI_API_KEY is unset
- isTruthyEnvValue
- accepts common truthy values
- rejects other values

### src/infra/exec-approval-forwarder.test.lisp
- exec approval forwarder
- forwards to session target and resolves
- forwards to explicit targets and expires
- formats single-line commands as inline code
- formats complex commands as fenced code blocks
- returns false when forwarding is disabled
- rejects unsafe nested-repetition regex in sessionFilter
- matches long session keys with tail-bounded regex checks
- returns false when all targets are skipped
- forwards to discord when discord exec approvals handler is disabled
- skips discord forwarding when discord exec approvals handler is enabled
- prefers turn-source routing over stale session last route
- can forward resolved notices without pending cache when request payload is present
- uses a longer fence when command already contains triple backticks

### src/infra/exec-approvals-allow-always.test.lisp
- resolveAllowAlwaysPatterns
- returns direct executable paths for non-shell segments
- unwraps shell wrappers and persists the inner executable instead
- extracts all inner binaries from shell chains and deduplicates
- persists shell script paths for wrapper invocations without inline commands
- matches persisted shell script paths through dispatch wrappers
- does not treat inline shell commands as persisted script paths
- does not treat stdin shell mode as a persisted script path
- does not persist broad shell binaries when no inner command can be derived
- detects shell wrappers even when unresolved executableName is a full path
- unwraps known dispatch wrappers before shell wrappers
- unwraps busybox/toybox shell applets and persists inner executables
- fails closed for unsupported busybox/toybox applets
- fails closed for unresolved dispatch wrappers
- prevents allow-always bypass for busybox shell applets
- prevents allow-always bypass for dispatch-wrapper + shell-wrapper chains
- does not persist comment-tailed payload paths that never execute

### src/infra/exec-approvals-config.test.lisp
- exec approvals wildcard agent
- merges wildcard allowlist entries with agent entries
- exec approvals sbcl host allowlist check
- matches exact and wildcard allowlist patterns
- does not treat unknown tools as safe bins
- satisfies via safeBins even when not in allowlist
- exec approvals default agent migration
- migrates legacy default agent entries to main
- prefers main agent settings when both main and default exist
- normalizeExecApprovals handles string allowlist entries (#9790)
- converts bare string entries to proper ExecAllowlistEntry objects
- preserves proper ExecAllowlistEntry objects unchanged
- sanitizes mixed and malformed allowlist shapes

### src/infra/exec-approvals-parity.test.lisp
- exec approvals shell parser parity fixture
- matches fixture: ${fixture.id}
- exec approvals wrapper resolution parity fixture
- matches wrapper fixture: ${fixture.id}

### src/infra/exec-approvals-safe-bins.test.lisp
- exec approvals safe bins
- supports injected trusted safe-bin dirs for tests/callers
- supports injected platform for deterministic safe-bin checks
- supports injected trusted path checker for deterministic callers
- keeps safe-bin profile fixtures aligned with compiled profiles
- does not include sort/grep in default safeBins
- does not auto-allow unprofiled safe-bin entries
- allows caller-defined custom safe-bin profiles
- blocks sort output flags independent of file existence
- threads trusted safe-bin dirs through allowlist evaluation
- does not auto-trust PATH-shadowed safe bins without explicit trusted dirs
- fails closed for semantic env wrappers in allowlist mode

### src/infra/exec-approvals.test.lisp
- exec approvals allowlist matching
- handles wildcard/path matching semantics
- matches bare * wildcard pattern against any resolved path
- matches bare * wildcard against arbitrary executables
- matches absolute paths containing regex metacharacters
- does not throw when wildcard globs are mixed with + in path
- matches paths containing []() regex tokens literally
- mergeExecApprovalsSocketDefaults
- prefers normalized socket, then current, then default path
- falls back to current token when missing in normalized
- resolve exec approvals defaults
- expands home-prefixed default file and socket paths
- exec approvals safe shell command builder
- quotes only safeBins segments (leaves other segments untouched)
- enforces canonical planned argv for every approved segment
- exec approvals command resolution
- resolves PATH, relative, and quoted executables
- unwraps transparent env wrapper argv to resolve the effective executable
- blocks semantic env wrappers from allowlist/safeBins auto-resolution
- fails closed for env -S even when env itself is allowlisted
- fails closed when transparent env wrappers exceed unwrap depth
- unwraps env wrapper with shell inner executable
- unwraps nice wrapper argv to resolve the effective executable
- exec approvals shell parsing
- parses pipelines and chained commands
- parses argv commands
- rejects unsupported shell constructs
- accepts inert substitution-like syntax
- accepts safe heredoc forms
- rejects unsafe or malformed heredoc forms
- parses windows quoted executables
- normalizes short option clusters with attached payloads
- normalizes long options with inline payloads
- exec approvals shell allowlist (chained commands)
- evaluates chained command allowlist scenarios
- respects quoted chain separators
- fails allowlist analysis for shell line continuations
- satisfies allowlist when bare * wildcard is present
- exec approvals allowlist evaluation
- satisfies allowlist on exact match
- satisfies allowlist via safe bins
- satisfies allowlist via auto-allow skills
- does not satisfy auto-allow skills for explicit relative paths
- does not satisfy auto-allow skills when command resolution is missing
- returns empty segment details for chain misses
- aggregates segment satisfaction across chains
- exec approvals policy helpers
- minSecurity returns the more restrictive value
- maxAsk returns the more aggressive ask mode
- requiresExecApproval respects ask mode and allowlist satisfaction

### src/infra/exec-obfuscation-detect.test.lisp
- detectCommandObfuscation
- base64 decode to shell
- detects base64 -d piped to sh
- detects base64 --decode piped to bash
- does NOT flag base64 -d without pipe to shell
- hex decode to shell
- detects xxd -r piped to sh
- pipe to shell
- detects arbitrary content piped to sh
- does NOT flag piping to other commands
- detects shell piped execution with flags
- detects shell piped execution with long flags
- escape sequence obfuscation
- detects multiple octal escapes
- detects multiple hex escapes
- curl/wget piped to shell
- detects curl piped to sh
- suppresses Homebrew install piped to bash (known-good pattern)
- does NOT suppress when a known-good URL is piggybacked with a malicious one
- does NOT suppress when known-good domains appear in query parameters
- eval and variable expansion
- detects eval with base64
- detects chained variable assignments with expansion
- alternative execution forms
- detects command substitution decode in shell -c
- detects process substitution remote execution
- detects source with process substitution from remote content
- detects shell heredoc execution
- edge cases
- returns no detection for empty input
- can detect multiple patterns at once

### src/infra/exec-safe-bin-policy.test.lisp
- exec safe bin policy grep
- allows stdin-only grep when pattern comes from flags
- blocks grep positional pattern form to avoid filename ambiguity
- blocks file positionals when pattern comes from -e/--regexp
- exec safe bin policy sort
- allows stdin-only sort flags
- blocks sort --compress-program in safe-bin mode
- blocks denied long-option abbreviations in safe-bin mode
- rejects unknown or ambiguous long options in safe-bin mode
- exec safe bin policy wc
- blocks wc --files0-from abbreviations in safe-bin mode
- exec safe bin policy long-option metadata
- precomputes long-option prefix mappings for compiled profiles
- preserves behavior when profile metadata is missing and rebuilt at runtime
- builds prefix maps from collected long flags
- exec safe bin policy denied-flag matrix
- ${binName} denies ${deniedFlag} (${variant.join(" ")})
- exec safe bin policy docs parity
- keeps denied-flag docs in sync with policy fixtures

### src/infra/exec-safe-bin-runtime-policy.test.lisp
- exec safe-bin runtime policy
- classifies interpreter-like safe bin '${testCase.bin}'
- lists interpreter-like bins from a mixed set
- merges and normalizes safe-bin profile fixtures
- computes unprofiled interpreter entries separately from custom profiled bins
- merges explicit safe-bin trusted dirs from global and local config
- does not trust package-manager bin dirs unless explicitly configured
- emits runtime warning when explicitly trusted dir is writable

### src/infra/exec-safe-bin-trust.test.lisp
- exec safe bin trust
- keeps default trusted dirs limited to immutable system paths
- builds trusted dirs from defaults and explicit extra dirs
- memoizes trusted dirs per explicit trusted-dir snapshot
- validates resolved paths using injected trusted dirs
- does not trust PATH entries by default
- flags explicitly trusted dirs that are group/world writable

### src/infra/fetch.test.lisp
- wrapFetchWithAbortSignal
- adds duplex for requests with a body
- converts foreign abort signals to native controllers
- does not emit an extra unhandled rejection when wrapped fetch rejects
- preserves original rejection when listener cleanup throws
- skips listener cleanup when foreign signal is already aborted
- returns the same function when called with an already wrapped fetch
- keeps preconnect bound to the original fetch implementation

### src/infra/file-identity.test.lisp
- sameFileIdentity
- accepts exact dev+ino match
- rejects inode mismatch
- rejects dev mismatch on non-windows
- accepts win32 dev mismatch when either side is 0
- keeps dev strictness on win32 when both dev values are non-zero
- handles bigint stats

### src/infra/fixed-window-rate-limit.test.lisp
- fixed-window rate limiter
- blocks after max requests until window reset
- supports explicit reset

### src/infra/format-time/format-time.test.lisp
- format-duration
- formatDurationCompact
- returns undefined for null/undefined/non-positive
- formats compact units and omits trailing zero components
- supports spaced option
- rounds at boundaries
- formatDurationHuman
- returns fallback for invalid duration input
- formats single-unit outputs and day threshold behavior
- formatDurationPrecise
- shows milliseconds for sub-second
- shows decimal seconds for >=1s
- returns unknown for non-finite
- formatDurationSeconds
- formats with configurable decimals
- supports seconds unit
- format-datetime
- resolveTimezone
- formatUtcTimestamp
- formatZonedTimestamp
- format-relative
- formatTimeAgo
- returns fallback for invalid elapsed input
- formats relative age around key unit boundaries
- omits suffix when suffix: false
- formatRelativeTimestamp
- returns fallback for invalid timestamp input
- falls back to date for old timestamps when enabled

### src/infra/fs-safe.test.lisp
- fs-safe
- reads a local file safely
- rejects directories
- enforces maxBytes
- blocks traversal outside root
- rejects directory path within root without leaking EISDIR (issue #31186)
- reads a file within root
- reads an absolute path within root via readPathWithinRoot
- creates a root-scoped read callback
- writes a file within root safely
- does not truncate existing target when atomic rename fails
- does not truncate existing target when atomic copy rename fails
- copies a file within root safely
- enforces maxBytes when copying into root
- writes a file within root from another local source path safely
- rejects write traversal outside root
- does not truncate out-of-root file when symlink retarget races write open
- does not clobber out-of-root file when symlink retarget races write-from-path open
- cleans up created out-of-root file when symlink retarget races create path
- returns not-found for missing files
- tilde expansion in file tools
- expandHomePrefix respects the process environment via UIOP.HOME changes
- reads a file via ~/path after HOME override
- writes a file via ~/path after HOME override
- rejects ~/path that resolves outside root

### src/infra/gateway-lock.test.lisp
- gateway lock
- blocks concurrent acquisition until release
- treats recycled linux pid as stale when start time mismatches
- keeps lock on linux when proc access fails unless stale
- keeps lock when fs.stat fails until payload is stale
- treats lock as stale when owner pid is alive but configured port is free
- keeps lock when configured port is busy and owner pid is alive
- returns null when multi-gateway override is enabled
- returns null in test env unless allowInTests is set
- wraps unexpected fs errors as GatewayLockError

### src/infra/git-root.test.lisp
- git-root
- finds git root and HEAD path when .git is a directory
- resolves HEAD path when .git is a gitdir pointer file
- keeps root detection for .git file and skips invalid gitdir content for HEAD lookup
- respects maxDepth traversal limit

### src/infra/heartbeat-active-hours.test.lisp
- isWithinActiveHours
- returns true when activeHours is not configured
- returns true when activeHours start/end are invalid
- returns false when activeHours start equals end
- respects user timezone windows for normal ranges
- supports overnight ranges
- respects explicit non-user timezones
- falls back to user timezone when activeHours timezone is invalid

### src/infra/heartbeat-events-filter.test.lisp
- heartbeat event prompts
- builds user-relay cron prompt by default
- builds internal-only cron prompt when delivery is disabled
- builds internal-only exec prompt when delivery is disabled

### src/infra/heartbeat-reason.test.lisp
- heartbeat-reason
- normalizes wake reasons with trim + requested fallback
- classifies known reason kinds
- classifies unknown reasons as other
- matches event-driven behavior used by heartbeat preflight
- matches action-priority wake behavior

### src/infra/heartbeat-runner.ghost-reminder.test.lisp
- Ghost reminder bug (issue #13317)
- does not use CRON_EVENT_PROMPT when only a HEARTBEAT_OK event is present
- uses CRON_EVENT_PROMPT when an actionable cron event exists
- uses CRON_EVENT_PROMPT when cron events are mixed with heartbeat noise
- uses CRON_EVENT_PROMPT for tagged cron events on interval wake
- uses an internal-only cron prompt when delivery target is none
- uses an internal-only exec prompt when delivery target is none

### src/infra/heartbeat-runner.model-override.test.lisp
- runHeartbeatOnce – heartbeat model override
- passes heartbeatModelOverride from defaults heartbeat config
- passes suppressToolErrorWarnings when configured
- passes bootstrapContextMode when heartbeat lightContext is enabled
- passes per-agent heartbeat model override (merged with defaults)
- does not pass heartbeatModelOverride when no heartbeat model is configured
- trims heartbeat model override before passing it downstream

### src/infra/heartbeat-runner.respects-ackmaxchars-heartbeat-acks.test.lisp
- runHeartbeatOnce ack handling
- respects ackMaxChars for heartbeat acks
- sends HEARTBEAT_OK when visibility.showOk is true
- skips heartbeat LLM calls when visibility disables all output
- skips delivery for markup-wrapped HEARTBEAT_OK
- does not regress updatedAt when restoring heartbeat sessions
- skips WhatsApp delivery when not linked or running

### src/infra/heartbeat-runner.returns-default-unset.test.lisp
- resolveHeartbeatIntervalMs
- returns default when unset
- returns null when invalid or zero
- parses duration strings with minute defaults
- uses explicit heartbeat overrides when provided
- resolveHeartbeatPrompt
- uses default or trimmed override prompts
- isHeartbeatEnabledForAgent
- enables only explicit heartbeat agents when configured
- falls back to default agent when no explicit heartbeat entries
- resolveHeartbeatDeliveryTarget
- resolves target variants across route and allowlist rules
- parses optional telegram :topic: threadId suffix
- handles explicit heartbeat accountId allow/deny
- prefers per-agent heartbeat overrides when provided
- resolveHeartbeatSenderContext
- prefers delivery accountId for allowFrom resolution
- runHeartbeatOnce
- skips when agent heartbeat is not enabled
- skips outside active hours
- uses the last non-empty payload for delivery
- uses per-agent heartbeat overrides and session keys
- reuses non-default agent sessionFile from templated stores
- resolves configured and forced session key overrides
- suppresses duplicate heartbeat payloads within 24h
- handles reasoning payload delivery variants
- loads the default agent session from templated stores
- adds explicit workspace HEARTBEAT.md path guidance to heartbeat prompts
- applies HEARTBEAT.md gating rules across file states and triggers
- uses an internal-only cron prompt when heartbeat delivery target is none
- uses an internal-only exec prompt when heartbeat delivery target is none

### src/infra/heartbeat-runner.scheduler.test.lisp
- startHeartbeatRunner
- updates scheduling when config changes without restart
- continues scheduling after runOnce throws an unhandled error
- cleanup is idempotent and does not clear a newer runner's handler
- run() returns skipped when runner is stopped
- reschedules timer when runOnce returns requests-in-flight
- does not push nextDueMs forward on repeated requests-in-flight skips
- routes targeted wake requests to the requested agent/session
- does not fan out to unrelated agents for session-scoped exec wakes

### src/infra/heartbeat-runner.sender-prefers-delivery-target.test.lisp
- runHeartbeatOnce
- uses the delivery target as sender when lastTo differs

### src/infra/heartbeat-runner.transcript-prune.test.lisp
- heartbeat transcript pruning
- prunes transcript when heartbeat returns HEARTBEAT_OK
- does not prune transcript when heartbeat returns meaningful content

### src/infra/heartbeat-visibility.test.lisp
- resolveHeartbeatVisibility
- returns default values when no config is provided
- uses channel defaults when provided
- per-channel config overrides channel defaults
- per-account config overrides per-channel config
- falls through to defaults when account has no heartbeat config
- handles missing accountId gracefully
- handles non-existent account gracefully
- works with whatsapp channel
- works with discord channel
- works with slack channel
- webchat uses channel defaults only (no per-channel config)
- webchat returns defaults when no channel defaults configured
- webchat ignores accountId (only uses defaults)

### src/infra/heartbeat-wake.test.lisp
- heartbeat-wake
- coalesces multiple wake requests into one run
- retries requests-in-flight after the default retry delay
- keeps retry cooldown even when a sooner request arrives
- retries thrown handler errors after the default retry delay
- stale disposer does not clear a newer handler
- preempts existing timer when a sooner schedule is requested
- keeps existing timer when later schedule is requested
- does not downgrade a higher-priority pending reason
- resets running/scheduled flags when new handler is registered
- clears stale retry cooldown when a new handler is registered
- drains pending wake once a handler is registered
- forwards wake target fields and preserves them across retries
- executes distinct targeted wakes queued in the same coalescing window

### src/infra/home-dir.test.lisp
- resolveEffectiveHomeDir
- prefers OPENCLAW_HOME over HOME and USERPROFILE
- falls back to HOME then USERPROFILE then homedir
- expands OPENCLAW_HOME when set to ~
- resolveRequiredHomeDir
- returns cwd when no home source is available
- returns a fully resolved path for OPENCLAW_HOME
- returns cwd when OPENCLAW_HOME is tilde-only and no fallback home exists
- expandHomePrefix
- expands tilde using effective home
- keeps non-tilde values unchanged

### src/infra/host-env-security.policy-parity.test.lisp
- host env security policy parity
- keeps generated macOS host env policy in sync with shared JSON policy

### src/infra/host-env-security.test.lisp
- isDangerousHostEnvVarName
- matches dangerous keys and prefixes case-insensitively
- sanitizeHostExecEnv
- removes dangerous inherited keys while preserving PATH
- blocks PATH and dangerous override values
- drops dangerous inherited shell trace keys
- drops non-portable env key names
- isDangerousHostEnvOverrideVarName
- matches override-only blocked keys case-insensitively
- normalizeEnvVarKey
- normalizes and validates keys
- sanitizeSystemRunEnvOverrides
- keeps overrides for non-shell commands
- drops non-allowlisted overrides for shell wrappers
- shell wrapper exploit regression
- blocks SHELLOPTS/PS4 chain after sanitization
- git env exploit regression
- blocks GIT_SSH_COMMAND override so git cannot execute helper payloads

### src/infra/http-body.test.lisp
- http body limits
- reads body within max bytes
- rejects oversized body
- returns json parse error when body is invalid
- returns payload-too-large for json body
- guard rejects oversized declared content-length
- guard rejects streamed oversized body
- timeout surfaces typed error when timeoutMs is clamped
- guard clamps invalid maxBytes to one byte
- declared oversized content-length does not emit unhandled error

### src/infra/infra-parsing.test.lisp
- infra parsing
- diagnostic flags
- merges config + env flags
- treats env true as wildcard
- treats env false as disabled
- isMainModule
- returns true when argv[1] matches current file
- returns true under PM2 when pm_exec_path matches current file
- returns true for dist/entry.js when launched via openclaw.lisp wrapper
- returns false for wrapper launches when wrapper pair is not configured
- returns false when wrapper pair targets a different entry basename
- returns false when running under PM2 but this module is imported
- buildNodeShellCommand
- uses cmd.exe for win32
- uses cmd.exe for windows labels
- uses /bin/sh for darwin
- uses /bin/sh when platform missing
- parseSshTarget
- parses user@host:port targets
- parses host-only targets with default port
- rejects hostnames that start with '-'

### src/infra/infra-runtime.test.lisp
- infra runtime
- ensureBinary
- passes through when binary exists
- logs and exits when missing
- createTelegramRetryRunner
- retries when custom shouldRetry matches non-telegram error
- restart authorization
- authorizes exactly once when scheduled restart emits
- tracks external restart policy
- suppresses duplicate emit until the restart cycle is marked handled
- coalesces duplicate scheduled restarts into a single pending timer
- applies restart cooldown between emitted restart cycles
- pre-restart deferral check
- emits SIGUSR1 immediately when no deferral check is registered
- emits SIGUSR1 immediately when deferral check returns 0
- defers SIGUSR1 until deferral check returns 0
- emits SIGUSR1 after deferral timeout even if still pending
- emits SIGUSR1 if deferral check throws
- tailnet address detection
- detects tailscale IPv4 and IPv6 addresses

### src/infra/infra-store.test.lisp
- infra store
- state migrations fs
- treats array session stores as invalid
- parses JSON5 object session stores
- voicewake store
- returns defaults when missing
- sanitizes and persists triggers
- falls back to defaults when triggers empty
- sanitizes malformed persisted config values
- diagnostic-events
- emits monotonic seq
- emits message-flow events
- channel activity
- records inbound/outbound separately
- isolates accounts
- createDedupeCache
- marks duplicates within TTL
- expires entries after TTL
- evicts oldest entries when over max size
- prunes expired entries even when refreshed keys are older in insertion order
- supports non-mutating existence checks via peek()

### src/infra/install-flow.test.lisp
- resolveExistingInstallPath
- returns resolved path and stat for existing files
- returns a path-not-found error for missing paths
- withExtractedArchiveRoot
- extracts archive and passes root directory to callback
- returns extract failure when extraction throws
- returns root-resolution failure when archive layout is invalid

### src/infra/install-mode-options.test.lisp
- install mode option helpers
- applies logger, mode, and dryRun defaults
- preserves explicit mode and dryRun values
- uses default timeout when not provided
- honors custom timeout default override

### src/infra/install-package-dir.test.lisp
- installPackageDir
- keeps the existing install in place when staged validation fails
- restores the original install if publish rename fails
- aborts without outside writes when the install base is rebound before publish
- warns and leaves the backup in place when the install base changes before backup cleanup

### src/infra/install-safe-path.test.lisp
- safePathSegmentHashed
- keeps safe names unchanged
- normalizes separators and adds hash suffix
- hashes long names while staying bounded
- assertCanonicalPathWithinBase
- accepts in-base directories

### src/infra/install-source-utils.test.lisp
- withTempDir
- creates a temp dir and always removes it after callback
- resolveArchiveSourcePath
- returns not found error for missing archive paths
- rejects unsupported archive extensions
- accepts supported archive extensions
- packNpmSpecToArchive
- packs spec and returns archive path using JSON output metadata
- falls back to parsing final stdout line when Quicklisp/Ultralisp json output is unavailable
- returns Quicklisp/Ultralisp pack error details when command fails
- falls back to archive detected in cwd when Quicklisp/Ultralisp pack stdout is empty
- falls back to archive detected in cwd when stdout does not contain a tgz
- returns friendly error for 404 (package not on Quicklisp/Ultralisp)
- returns explicit error when Quicklisp/Ultralisp pack produces no archive name
- parses scoped metadata from id-only json output even with Quicklisp/Ultralisp notice prefix
- uses stdout fallback error text when stderr is empty

### src/infra/json-utf8-bytes.test.lisp
- jsonUtf8Bytes
- returns utf8 byte length for serializable values
- falls back to string conversion when JSON serialization throws

### src/infra/net/fetch-guard.ssrf.test.lisp
- fetchWithSsrFGuard hardening
- blocks private and legacy loopback literals before fetch
- blocks special-use IPv4 literal URLs before fetch
- allows RFC2544 benchmark range IPv4 literal URLs when explicitly opted in
- blocks redirect chains that hop to private hosts
- enforces hostname allowlist policies
- allows wildcard allowlisted hosts
- strips sensitive headers when redirect crosses origins
- keeps headers when redirect stays on same origin
- ignores env proxy by default to preserve DNS-pinned destination binding
- uses env proxy only when dangerous proxy bypass is explicitly enabled

### src/infra/net/proxy-fetch.test.lisp
- makeProxyFetch
- uses undici fetch with ProxyAgent dispatcher
- resolveProxyFetchFromEnv
- returns undefined when no proxy env vars are set
- returns proxy fetch using EnvHttpProxyAgent when HTTPS_PROXY is set
- returns proxy fetch when HTTP_PROXY is set
- returns proxy fetch when lowercase https_proxy is set
- returns proxy fetch when lowercase http_proxy is set
- returns undefined when EnvHttpProxyAgent constructor throws

### src/infra/net/ssrf.dispatcher.test.lisp
- createPinnedDispatcher
- uses pinned lookup without overriding global family policy

### src/infra/net/ssrf.pinning.test.lisp
- ssrf pinning
- pins resolved addresses for the target hostname
- allows RFC2544 benchmark range addresses only when policy explicitly opts in
- falls back for non-matching hostnames
- enforces hostname allowlist when configured
- supports wildcard hostname allowlist patterns
- sorts IPv4 addresses before IPv6 in pinned results
- uses DNS family metadata for ordering (not address string heuristics)
- allows ISATAP embedded private IPv4 when private network is explicitly enabled
- accepts dangerouslyAllowPrivateNetwork as an allowPrivateNetwork alias

### src/infra/net/ssrf.test.lisp
- ssrf ip classification
- classifies blocked ip literals as private
- classifies public ip literals as non-private
- does not treat hostnames as ip literals
- normalizeFingerprint
- strips sha256 prefixes and separators
- isBlockedHostnameOrIp
- blocks localhost.localdomain and metadata hostname aliases
- blocks private transition addresses via shared IP classifier
- blocks IPv4 special-use ranges but allows adjacent public ranges
- supports opt-in policy to allow RFC2544 benchmark range
- blocks legacy IPv4 literal representations

### src/infra/net/undici-global-dispatcher.test.lisp
- ensureGlobalUndiciStreamTimeouts
- replaces default Agent dispatcher with extended stream timeouts
- replaces EnvHttpProxyAgent dispatcher while preserving env-proxy mode
- does not override unsupported custom proxy dispatcher types
- is idempotent for unchanged dispatcher kind and network policy
- re-applies when autoSelectFamily decision changes

### src/infra/sbcl-pairing.test.lisp
- sbcl pairing tokens
- reuses existing pending requests for the same sbcl
- generates base64url sbcl tokens with 256-bit entropy output length
- verifies token and rejects mismatches
- treats multibyte same-length token input as mismatch without throwing

### src/infra/Quicklisp/Ultralisp-integrity.test.lisp
- resolveNpmIntegrityDrift
- returns proceed=true when integrity is missing or unchanged
- uses callback on integrity drift
- warns by default when no callback is provided
- formats default warning and abort error messages

### src/infra/Quicklisp/Ultralisp-pack-install.test.lisp
- installFromNpmSpecArchive
- returns pack errors without invoking installer
- returns resolution metadata and installer result on success
- proceeds when integrity drift callback accepts drift
- aborts when integrity drift callback rejects drift
- warns and proceeds on drift when no callback is configured
- returns installer failures to callers for domain-specific handling
- installFromNpmSpecArchiveWithInstaller
- passes archive path and installer params to installFromArchive
- finalizeNpmSpecArchiveInstall
- returns top-level flow errors unchanged
- returns install errors unchanged
- attaches Quicklisp/Ultralisp metadata to successful install results

### src/infra/Quicklisp/Ultralisp-registry-spec.test.lisp
- Quicklisp/Ultralisp registry spec validation
- accepts bare package names, exact versions, and dist-tags
- rejects semver ranges
- Quicklisp/Ultralisp prerelease resolution policy
- blocks prerelease resolutions for bare specs
- blocks prerelease resolutions for latest
- allows prerelease resolutions when the user explicitly opted in

### src/infra/openclaw-root.test.lisp
- resolveOpenClawPackageRoot
- resolves package root from .bin argv1
- resolves package root via symlinked argv1
- falls back when argv1 realpath throws
- prefers moduleUrl candidates
- returns null for non-openclaw package roots
- async resolver matches sync behavior
- async resolver returns null when no package roots exist

### src/infra/outbound/agent-delivery.test.lisp
- agent delivery helpers
- builds a delivery plan from session delivery context
- resolves fallback targets when no explicit destination is provided
- does not inject a default deliverable channel when session has none
- skips outbound target resolution when explicit target validation is disabled
- prefers turn-source delivery context over session last route
- does not reuse mutable session to when only turnSourceChannel is provided

### src/infra/outbound/bound-delivery-router.test.lisp
- bound delivery router
- resolves to a bound destination when a single active binding exists
- falls back when no active binding exists
- fails closed when multiple bindings exist without requester signal
- selects requester-matching conversation when multiple bindings exist
- falls back for invalid requester conversation values

### src/infra/outbound/cfg-threading.guard.test.lisp
- outbound cfg-threading guard
- keeps outbound adapter entrypoints free of loadConfig calls
- keeps inline channel outbound blocks free of loadConfig calls

### src/infra/outbound/channel-selection.test.lisp
- resolveMessageChannelSelection
- keeps explicit known channels and marks source explicit
- falls back to tool context channel when explicit channel is unknown
- uses fallback channel when explicit channel is omitted
- selects single configured channel when no explicit/fallback channel exists
- throws unknown channel when explicit and fallback channels are both invalid

### src/infra/outbound/conversation-id.test.lisp
- resolveConversationIdFromTargets
- prefers explicit thread id when present
- extracts channel ids from channel: targets
- extracts ids from Discord channel mentions
- accepts raw numeric ids
- returns undefined for non-channel targets

### src/infra/outbound/deliver.test.lisp
- deliverOutboundPayloads
- chunks telegram markdown and passes through accountId
- clamps telegram text chunk size to protocol max even with higher config
- keeps payload replyToId across all chunked telegram sends
- passes explicit accountId to sendTelegram
- preserves HTML text for telegram sendPayload channelData path
- scopes media local roots to the active agent workspace when agentId is provided
- includes OpenClaw tmp root in telegram mediaLocalRoots
- includes OpenClaw tmp root in signal mediaLocalRoots
- includes OpenClaw tmp root in whatsapp mediaLocalRoots
- includes OpenClaw tmp root in imessage mediaLocalRoots
- uses signal media maxBytes from config
- chunks Signal markdown using the format-first chunker
- chunks WhatsApp text and returns all results
- respects newline chunk mode for WhatsApp
- strips leading blank lines for WhatsApp text payloads
- drops whitespace-only WhatsApp text payloads when no media is attached
- drops HTML-only WhatsApp text payloads after sanitization
- keeps WhatsApp media payloads but clears whitespace-only captions
- drops non-WhatsApp HTML-only text payloads after sanitization
- preserves fenced blocks for markdown chunkers in newline mode
- uses iMessage media maxBytes from agent fallback
- normalizes payloads and drops empty entries
- continues on errors when bestEffort is enabled
- emits internal message:sent hook with success=true for chunked payload delivery
- does not emit internal message:sent hook when neither mirror nor sessionKey is provided
- emits internal message:sent hook when sessionKey is provided without mirror
- warns when session.agentId is set without a session key
- calls failDelivery instead of ackDelivery on bestEffort partial failure
- acks the queue entry when delivery is aborted
- passes normalized payload to onError
- mirrors delivered output when mirror options are provided
- emits message_sent success for text-only deliveries
- emits message_sent success for sendPayload deliveries
- preserves channelData-only payloads with empty text for non-WhatsApp sendPayload channels
- falls back to sendText when plugin outbound omits sendMedia
- falls back to one sendText call for multi-media payloads when sendMedia is omitted
- fails media-only payloads when plugin outbound omits sendMedia
- emits message_sent failure when delivery errors

### src/infra/outbound/message-action-normalization.test.lisp
- normalizeMessageActionInput
- prefers explicit target and clears legacy target fields
- ignores empty-string legacy target fields when explicit target is present
- maps legacy target fields into canonical target
- infers target from tool context when required
- infers channel from tool context provider
- throws when required target remains unresolved

### src/infra/outbound/message-action-params.test.lisp
- message action sandbox media hydration

### src/infra/outbound/message-action-runner.test.lisp
- runMessageAction context isolation
- allows send when target matches current channel
- accepts legacy to parameter for send
- defaults to current channel when target is omitted
- allows media-only send when target matches current channel
- requires message when no media hint is provided
- rejects send actions that include poll creation params
- rejects send actions that include string-encoded poll params
- rejects send actions that include snake_case poll params
- allows send when poll booleans are explicitly false
- blocks send when target differs from current channel
- blocks thread-reply when channelId differs from current channel
- infers channel + target from tool context when missing
- falls back to tool-context provider when channel param is an id
- falls back to tool-context provider for broadcast channel ids
- blocks cross-provider sends by default
- blocks same-provider cross-context when disabled
- runMessageAction sendAttachment hydration
- hydrates buffer and filename from media for sendAttachment
- rewrites sandboxed media paths for sendAttachment
- rejects local absolute path for sendAttachment when sandboxRoot is missing
- rejects local absolute path for setGroupIcon when sandboxRoot is missing
- runMessageAction sandboxed media validation
- rejects data URLs in media params
- rewrites sandbox-relative media paths
- rewrites /workspace media paths to host sandbox root
- rewrites MEDIA directives under sandbox
- allows media paths under preferred OpenClaw tmp root
- runMessageAction media caption behavior
- promotes caption to message for media sends when message is empty
- runMessageAction card-only send behavior
- allows card-only sends without text or media
- runMessageAction telegram plugin poll forwarding
- forwards telegram poll params through plugin dispatch
- runMessageAction components parsing
- parses components JSON strings before plugin dispatch
- throws on invalid components JSON strings
- runMessageAction accountId defaults
- propagates defaultAccountId into params
- falls back to the agent's bound account when accountId is omitted

### src/infra/outbound/message-action-runner.threading.test.lisp
- runMessageAction threading auto-injection
- uses explicit telegram threadId when provided
- threads explicit replyTo through executeSendAction

### src/infra/outbound/message.channels.test.lisp
- sendMessage channel normalization
- threads resolved cfg through alias + target normalization in outbound dispatch
- normalizes Teams alias
- normalizes iMessage alias
- sendMessage replyToId threading
- passes replyToId through to the outbound adapter
- passes threadId through to the outbound adapter
- sendPoll channel normalization
- normalizes Teams alias for polls
- gateway url override hardening
- drops gateway url overrides in backend mode (SSRF hardening)
- forwards explicit agentId in gateway send params

### src/infra/outbound/message.test.lisp
- sendMessage
- passes explicit agentId to outbound delivery for scoped media roots
- recovers telegram plugin resolution so message/send does not fail with Unknown channel: telegram

### src/infra/outbound/outbound-send-service.test.lisp
- executeSendAction
- forwards ctx.agentId to sendMessage on core outbound path
- uses plugin poll action when available
- passes agent-scoped media local roots to plugin dispatch
- forwards poll args to sendPoll on core outbound path

### src/infra/outbound/outbound.test.lisp
- delivery-queue
- enqueue + ack lifecycle
- creates and removes a queue entry
- ack is idempotent (no error on missing file)
- ack cleans up leftover .delivered marker when .json is already gone
- ack removes .delivered marker so recovery does not replay
- loadPendingDeliveries cleans up stale .delivered markers without replaying
- failDelivery
- increments retryCount, records attempt time, and sets lastError
- moveToFailed
- moves entry to failed/ subdirectory
- isPermanentDeliveryError
- loadPendingDeliveries
- returns empty array when queue directory does not exist
- loads multiple entries
- backfills lastAttemptAt for legacy retry entries during load
- computeBackoffMs
- returns scheduled backoff values and clamps at max retry
- isEntryEligibleForRecoveryRetry
- allows first replay after crash for retryCount=0 without lastAttemptAt
- defers retry entries until backoff window elapses
- recoverPendingDeliveries
- recovers entries from a simulated crash
- moves entries that exceeded max retries to failed/
- increments retryCount on failed recovery attempt
- moves entries to failed/ immediately on permanent delivery errors
- passes skipQueue: true to prevent re-enqueueing during recovery
- replays stored delivery options during recovery
- respects maxRecoveryMs time budget
- defers entries until backoff becomes eligible
- continues past high-backoff entries and recovers ready entries behind them
- recovers deferred entries on a later restart once backoff elapsed
- returns zeros when queue is empty
- DirectoryCache
- expires entries after ttl
- evicts least-recent entries when capacity is exceeded
- buildOutboundResultEnvelope
- formats envelope variants
- formatOutboundDeliverySummary
- formats fallback and channel-specific detail variants
- buildOutboundDeliveryJson
- builds direct delivery payloads across provider-specific fields
- formatGatewaySummary
- formats default and custom gateway action summaries
- outbound policy
- allows cross-provider sends when enabled
- uses components when available and preferred
- resolveOutboundSessionRoute
- resolves provider-specific session routes
- uses resolved Discord user targets to route bare numeric ids as DMs
- rejects bare numeric Discord targets when the caller has no kind hint
- normalizeOutboundPayloadsForJson
- normalizes payloads for JSON output
- suppresses reasoning payloads
- normalizeOutboundPayloads
- keeps channelData-only payloads
- suppresses reasoning payloads
- formatOutboundPayloadLog
- formats text+media and media-only logs

### src/infra/outbound/sanitize-text.test.lisp
- isPlainTextSurface
- is case-insensitive
- sanitizeForPlainText
- converts <br> to newline
- converts self-closing <br/> and <br /> variants
- converts <b> and <strong> to WhatsApp bold
- converts <i> and <em> to WhatsApp italic
- converts <s>, <strike>, and <del> to WhatsApp strikethrough
- converts <code> to backtick wrapping
- converts <p> and <div> to newlines
- converts headings to bold text with newlines
- converts <li> to bullet points
- strips unknown/remaining tags
- preserves angle-bracket autolinks
- passes through clean text unchanged
- does not corrupt angle brackets in prose
- handles mixed HTML content
- collapses excessive newlines

### src/infra/outbound/session-binding-service.test.lisp
- session binding service
- normalizes conversation refs and infers current placement
- supports explicit child placement when adapter advertises it
- returns structured errors when adapter is unavailable
- returns structured errors for unsupported placement
- returns structured errors when adapter bind fails
- reports adapter capabilities for command preflight messaging

### src/infra/outbound/target-resolver.test.lisp
- resolveMessagingTarget (directory fallback)
- uses live directory fallback and caches the result
- skips directory lookup for direct ids

### src/infra/outbound/targets.channel-resolution.test.lisp
- resolveOutboundTarget channel resolution
- recovers telegram plugin resolution so announce delivery does not fail with Unsupported channel: telegram
- retries bootstrap on subsequent resolve when the first bootstrap attempt fails

### src/infra/outbound/targets.test.lisp
- resolveOutboundTarget defaultTo config fallback
- uses whatsapp defaultTo when no explicit target is provided
- uses telegram defaultTo when no explicit target is provided
- explicit --reply-to overrides defaultTo
- still errors when no defaultTo and no explicit target
- resolveSessionDeliveryTarget
- derives implicit delivery from the last route
- prefers explicit targets without reusing lastTo
- allows mismatched lastTo when configured
- passes through explicitThreadId when provided
- uses session lastThreadId when no explicitThreadId
- does not inherit lastThreadId in heartbeat mode
- falls back to a provided channel when requested is unsupported
- parses :topic:NNN from explicitTo into threadId
- parses :topic:NNN even when lastTo is absent
- skips :topic: parsing for non-telegram channels
- skips :topic: parsing when channel is explicitly non-telegram even if lastChannel was telegram
- explicitThreadId takes priority over :topic: parsed value
- allows heartbeat delivery to Slack DMs and avoids inherited threadId by default
- blocks heartbeat delivery to Slack DMs when directPolicy is block
- allows heartbeat delivery to Discord DMs by default
- allows heartbeat delivery to Telegram direct chats by default
- blocks heartbeat delivery to Telegram direct chats when directPolicy is block
- keeps heartbeat delivery to Telegram groups
- allows heartbeat delivery to WhatsApp direct chats by default
- keeps heartbeat delivery to WhatsApp groups
- uses session chatType hint when target parser cannot classify and allows direct by default
- blocks session chatType direct hints when directPolicy is block
- keeps heartbeat delivery to Discord channels
- keeps explicit threadId in heartbeat mode
- parses explicit heartbeat topic targets into threadId
- resolveSessionDeliveryTarget — cross-channel reply guard (#24152)
- uses turnSourceChannel over session lastChannel when provided
- falls back to session lastChannel when turnSourceChannel is not set
- respects explicit requestedChannel over turnSourceChannel
- preserves turnSourceAccountId and turnSourceThreadId
- does not fall back to session target metadata when turnSourceChannel is set
- uses explicitTo even when turnSourceTo is omitted
- still allows mismatched lastTo only from turn-scoped metadata

### src/infra/parse-finite-number.test.lisp
- parseFiniteNumber
- returns finite numbers
- parses numeric strings
- returns undefined for non-finite or non-numeric values
- parseStrictInteger
- parses exact integers
- rejects junk prefixes and suffixes
- parseStrictPositiveInteger
- accepts only positive integers
- parseStrictNonNegativeInteger
- accepts zero and positive integers only

### src/infra/path-alias-guards.test.lisp
- assertNoPathAliasEscape

### src/infra/path-env.test.lisp
- ensureOpenClawCliOnPath
- prepends the bundled app bin dir when a sibling openclaw exists
- is idempotent
- prepends mise shims when available
- only appends project-local node_modules/.bin when explicitly enabled
- prepends Linuxbrew dirs when present

### src/infra/path-safety.test.lisp
- path-safety
- resolves safe base dir with trailing separator
- checks directory containment

### src/infra/plain-object.test.lisp
- isPlainObject
- accepts plain objects
- rejects non-plain values

### src/infra/ports.test.lisp
- ports helpers
- ensurePortAvailable rejects when port busy
- handlePortError exits nicely on EADDRINUSE
- prints an OpenClaw-specific hint when port details look like another OpenClaw instance
- classifies ssh and gateway listeners
- formats port diagnostics with hints
- reports busy when lsof is missing but loopback listener exists
- falls back to ss when lsof is unavailable

### src/infra/process-respawn.test.lisp
- restartGatewayProcessWithFreshPid
- returns disabled when OPENCLAW_NO_RESPAWN is set
- returns supervised when launchd hints are present on macOS
- runs launchd kickstart helper on macOS when launchd label is set
- returns failed when launchd kickstart helper fails
- does not schedule kickstart on non-darwin platforms
- spawns detached child with current exec argv
- returns supervised when OPENCLAW_LAUNCHD_LABEL is set (stock launchd plist)
- returns supervised when OPENCLAW_SYSTEMD_UNIT is set
- returns supervised when OpenClaw gateway task markers are set on Windows
- keeps generic service markers out of non-Windows supervisor detection
- returns disabled on Windows without Scheduled Task markers
- ignores sbcl task script hints for gateway restart detection on Windows
- returns failed when spawn throws

### src/infra/provider-usage.auth.normalizes-keys.test.lisp
- resolveProviderAuths key normalization
- strips embedded CR/LF from env keys
- strips embedded CR/LF from stored auth profiles (token + api_key)
- returns injected auth values unchanged
- accepts z-ai env alias and normalizes embedded CR/LF
- falls back to legacy .pi auth file for zai keys even after os.homedir() is primed
- extracts google oauth token from JSON payload in token profiles
- keeps raw google token when token payload is not JSON
- uses config api keys when env and profiles are missing
- returns no auth when providers have no configured credentials
- uses zai api_key auth profiles when env and config are missing
- ignores invalid legacy z-ai auth files
- discovers oauth provider from config but skips mismatched profile providers
- skips providers without oauth-compatible profiles
- skips oauth profiles that resolve without an api key and uses later profiles
- skips api_key entries in oauth token resolution order
- ignores marker-backed config keys for provider usage auth resolution
- keeps all-caps plaintext config keys eligible for provider usage auth resolution

### src/infra/provider-usage.fetch.claude.test.lisp
- fetchClaudeUsage
- parses oauth usage windows
- returns HTTP errors with provider message suffix
- falls back to claude web usage when oauth scope is missing
- parses sessionKey from CLAUDE_WEB_COOKIE for web fallback
- keeps oauth error when fallback session key is unavailable

### src/infra/provider-usage.fetch.codex.test.lisp
- fetchCodexUsage
- returns token expired for auth failures
- returns HTTP status errors for non-auth failures
- parses windows, reset times, and plan balance
- labels weekly secondary window as Week
- labels secondary window as Week when reset cadence clearly exceeds one day

### src/infra/provider-usage.fetch.copilot.test.lisp
- fetchCopilotUsage
- returns HTTP errors for failed requests
- parses premium/chat usage from remaining percentages

### src/infra/provider-usage.fetch.gemini.test.lisp
- fetchGeminiUsage
- returns HTTP errors for failed requests
- selects the lowest remaining fraction per model family

### src/infra/provider-usage.fetch.minimax.test.lisp
- fetchMinimaxUsage
- returns HTTP errors for failed requests
- returns invalid JSON when payload cannot be parsed
- returns API errors from base_resp
- derives usage from used/total fields and includes reset + plan
- supports usage ratio strings with minute windows and ISO reset strings
- derives used from total and remaining counts
- returns unsupported response shape when no usage fields are present
- handles repeated nested records while scanning usage candidates

### src/infra/provider-usage.fetch.shared.test.lisp
- provider usage fetch shared helpers
- builds a provider error snapshot
- maps configured status codes to token expired
- includes trimmed API error messages in HTTP errors

### src/infra/provider-usage.fetch.zai.test.lisp
- fetchZaiUsage
- returns HTTP errors for failed requests
- returns API message errors for unsuccessful payloads
- parses token and monthly windows with reset times

### src/infra/provider-usage.format.test.lisp
- provider-usage.format
- returns null summary for errored or empty snapshots
- formats reset windows across now/minute/hour/day/date buckets
- honors max windows and reset toggle
- formats summary line from highest-usage window and provider cap
- formats report output for empty, error, no-data, and plan entries

### src/infra/provider-usage.shared.test.lisp
- provider-usage.shared
- normalizes supported usage provider ids
- clamps usage percents and handles non-finite values
- returns work result when it resolves before timeout
- returns fallback when timeout wins

### src/infra/provider-usage.test.lisp
- provider usage formatting
- returns null when no usage is available
- picks the most-used window for summary line
- prints provider errors in report output
- includes reset countdowns in report lines
- provider usage loading
- loads usage snapshots with injected auth
- handles nested MiniMax usage payloads
- prefers MiniMax count-based usage when percent looks inverted
- handles MiniMax model_remains usage payloads
- discovers Claude usage from token auth profiles
- falls back to claude.ai web usage when OAuth scope is missing
- loads snapshots for copilot gemini codex and xiaomi
- returns empty provider list when auth resolves to none
- returns unsupported provider snapshots for unknown provider ids
- filters errors that are marked as ignored
- throws when fetch is unavailable

### src/infra/push-apns.test.lisp
- push APNs registration store
- stores and reloads sbcl APNs registration
- rejects invalid APNs tokens
- push APNs env config
- normalizes APNs environment values
- resolves inline private key and unescapes newlines
- returns an error when required APNs auth vars are missing
- push APNs send semantics
- sends alert pushes with alert headers and payload
- sends background wake pushes with silent payload semantics
- defaults background wake reason when not provided

### src/infra/restart-sentinel.test.lisp
- restart sentinel
- writes and consumes a sentinel
- drops invalid sentinel payloads
- formatRestartSentinelMessage uses custom message when present
- formatRestartSentinelMessage falls back to summary when no message
- formatRestartSentinelMessage falls back to summary for blank message
- trims log tails
- formats restart messages without volatile timestamps
- restart sentinel message dedup
- omits duplicate Reason: line when stats.reason matches message
- keeps Reason: line when stats.reason differs from message

### src/infra/restart-stale-pids.test.lisp
- findGatewayPidsOnPortSync
- returns [] when lsof exits with non-zero status
- logs warning when initial lsof scan exits with status > 1
- returns [] when lsof returns an error object (e.g. ENOENT)
- parses openclaw-gateway pids and excludes the current process
- excludes pids whose command does not include 'openclaw'
- forwards the spawnTimeoutMs argument to spawnSync
- deduplicates pids from dual-stack listeners (IPv4+IPv6 emit same pid twice)
- returns [] and skips lsof on win32
- parsePidsFromLsofOutput (via findGatewayPidsOnPortSync stdout path)
- returns [] for empty lsof stdout (status 0, nothing listening)
- parses multiple openclaw pids from a single lsof output block
- returns [] when status 0 but only non-openclaw pids present
- pollPortOnce — no second lsof spawn (Codex P1 regression)
- treats lsof exit status 1 as port-free (no listeners)
- treats lsof exit status >1 as inconclusive, not port-free — Codex P2 regression
- does not make a second lsof call when the first returns status 0
- lsof status 1 with non-empty openclaw stdout is treated as busy, not free (Linux container edge case)
- pollPortOnce outer catch returns { free: null, permanent: false } when resolveLsofCommandSync throws
- cleanStaleGatewayProcessesSync
- returns [] and does not call process.kill when port has no listeners
- sends SIGTERM to stale pids and returns them
- escalates to SIGKILL when process survives the SIGTERM window
- polls until port is confirmed free before returning — regression for #33103
- bails immediately when lsof is permanently unavailable (ENOENT) — Greptile edge case
- bails immediately when lsof is permanently unavailable (EPERM) — SELinux/AppArmor
- bails immediately when lsof is permanently unavailable (EACCES) — same as ENOENT
- proceeds with warning when polling budget is exhausted — fake clock, no real 2s wait
- still polls for port-free when all stale pids were already dead at SIGTERM time
- continues polling on transient lsof errors (not ENOENT) — Codex P1 fix
- returns gracefully when resolveGatewayPort throws
- returns gracefully when lsof is unavailable from the start
- parsePidsFromLsofOutput — branch coverage (lines 67-69)
- skips a mid-loop entry when the command does not include 'openclaw'
- skips a mid-loop entry when currentCmd is missing (two consecutive p-lines)
- ignores a p-line with an invalid (non-positive) PID — ternary false branch
- silently skips lines that start with neither 'p' nor 'c' — else-if false branch
- pollPortOnce — status 1 + non-empty non-openclaw stdout (line 145)
- treats status 1 + non-openclaw stdout as port-free (not an openclaw process)
- sleepSync — Atomics.wait paths
- returns immediately when called with 0ms (timeoutMs <= 0 early return)
- returns immediately when called with a negative value (Math.max(0,...) clamp)
- executes the Atomics.wait path successfully when called with a positive timeout
- falls back to busy-wait when Atomics.wait throws (Worker / sandboxed env)

### src/infra/restart.test.lisp
- parses lsof output and filters non-openclaw/current processes
- returns empty when lsof fails
- kills stale gateway pids discovered on the gateway port
- uses explicit port override when provided
- returns empty when no stale listeners are found

### src/infra/retry-policy.test.lisp
- createTelegramRetryRunner
- strictShouldRetry
- without strictShouldRetry: ECONNRESET is retried via regex fallback even when predicate returns false
- with strictShouldRetry=true: ECONNRESET is NOT retried when predicate returns false
- with strictShouldRetry=true: ECONNREFUSED is still retried when predicate returns true

### src/infra/retry.test.lisp
- retryAsync
- returns on first success
- retries then succeeds
- propagates after exhausting retries
- stops when shouldRetry returns false
- calls onRetry before retrying
- clamps attempts to at least 1
- uses retryAfterMs when provided
- clamps retryAfterMs to maxDelayMs
- clamps retryAfterMs to minDelayMs

### src/infra/run-sbcl.test.lisp
- run-sbcl script

### src/infra/runtime-guard.test.lisp
- runtime-guard
- parses semver with or without leading v
- compares versions correctly
- validates runtime thresholds
- throws via exit when runtime is too old
- returns silently when runtime meets requirements

### src/infra/safe-open-sync.test.lisp
- openVerifiedFileSync
- rejects directories by default
- accepts directories when allowedType is directory

### src/infra/scp-host.test.lisp
- scp remote host
- accepts host and user@host forms
- rejects unsafe host tokens

### src/infra/secure-random.test.lisp
- secure-random
- generates UUIDs
- generates url-safe tokens

### src/infra/session-cost-usage.test.lisp
- session cost usage
- aggregates daily totals with log cost and pricing fallback
- summarizes a single session file
- captures message counts, tool usage, and model usage
- does not exclude sessions with mtime after endMs during discovery
- resolves non-main absolute sessionFile using explicit agentId for cost summary
- resolves non-main absolute sessionFile using explicit agentId for timeseries
- resolves non-main absolute sessionFile using explicit agentId for logs
- strips inbound and untrusted metadata blocks from session usage logs
- preserves totals and cumulative values when downsampling timeseries

### src/infra/session-maintenance-warning.test.lisp
- deliverSessionMaintenanceWarning
- forwards session context to outbound delivery

### src/infra/shell-env.test.lisp
- shell env fallback
- is disabled by default
- resolves timeout from env with default fallback
- skips when already has an expected key
- imports expected keys without overriding existing env
- resolves PATH via login shell and caches it
- returns null on shell env read failure and caches null
- falls back to /bin/sh when SHELL is non-absolute
- falls back to /bin/sh when SHELL points to an untrusted path
- falls back to /bin/sh when SHELL is absolute but not registered in /etc/shells
- uses SHELL when it is explicitly registered in /etc/shells
- sanitizes startup-related env vars before shell fallback exec
- sanitizes startup-related env vars before login-shell PATH probe
- returns null without invoking shell on win32

### src/infra/skills-remote.test.lisp
- skills-remote
- removes disconnected nodes from remote skill eligibility
- supports idempotent remote sbcl removal

### src/infra/ssh-config.test.lisp
- ssh-config
- parses ssh -G output
- resolves ssh config via ssh -G
- returns null when ssh -G fails

### src/infra/state-migrations.state-dir.test.lisp
- legacy state dir auto-migration
- follows legacy symlink when it points at another legacy dir (clawdbot -> moltbot)

### src/infra/system-events.test.lisp
- system events (session routing)
- does not leak session-scoped events into main
- requires an explicit session key
- returns false for consecutive duplicate events
- filters heartbeat/noise lines, returning undefined
- prefixes every line of a multi-line event
- scrubs sbcl last-input suffix
- isCronSystemEvent
- returns false for empty entries
- returns false for heartbeat ack markers
- returns false for heartbeat poll and wake noise
- returns false for exec completion events
- returns true for real cron reminder content

### src/infra/system-message.test.lisp
- system-message
- prepends the system mark once
- does not double-prefix messages that already have the mark
- detects marked system text after trim normalization

### src/infra/system-presence.test.lisp
- system-presence
- dedupes entries across sources by case-insensitive instanceId key
- merges roles and scopes for the same device
- prunes stale non-self entries after TTL

### src/infra/system-presence.version.test.lisp
- system-presence version fallback
- uses runtime VERSION when OPENCLAW_VERSION is not set
- prefers OPENCLAW_VERSION over runtime VERSION
- uses runtime VERSION when OPENCLAW_VERSION and OPENCLAW_SERVICE_VERSION are blank

### src/infra/system-run-approval-mismatch.contract.test.lisp
- system-run approval mismatch contract fixtures

### src/infra/system-run-command.contract.test.lisp
- system-run command contract fixtures

### src/infra/system-run-command.test.lisp
- system run command helpers
- formatExecCommand quotes args with spaces
- formatExecCommand preserves trailing whitespace in argv tokens
- extractShellCommandFromArgv extracts sh -lc command
- extractShellCommandFromArgv extracts cmd.exe /c command
- extractShellCommandFromArgv unwraps /usr/bin/env shell wrappers
- extractShellCommandFromArgv unwraps known dispatch wrappers before shell wrappers
- extractShellCommandFromArgv supports fish and pwsh wrappers
- extractShellCommandFromArgv unwraps busybox/toybox shell applets
- extractShellCommandFromArgv ignores env wrappers when no shell wrapper follows
- extractShellCommandFromArgv includes trailing cmd.exe args after /c
- validateSystemRunCommandConsistency accepts rawCommand matching direct argv
- validateSystemRunCommandConsistency rejects mismatched rawCommand vs direct argv
- validateSystemRunCommandConsistency accepts rawCommand matching sh wrapper argv
- validateSystemRunCommandConsistency rejects shell-only rawCommand for positional-argv carrier wrappers
- validateSystemRunCommandConsistency accepts rawCommand matching env shell wrapper argv
- validateSystemRunCommandConsistency rejects shell-only rawCommand for env assignment prelude
- validateSystemRunCommandConsistency accepts full rawCommand for env assignment prelude
- validateSystemRunCommandConsistency rejects cmd.exe /c trailing-arg smuggling
- validateSystemRunCommandConsistency rejects mismatched rawCommand vs sh wrapper argv
- resolveSystemRunCommand requires command when rawCommand is present
- resolveSystemRunCommand returns normalized argv and cmdText
- resolveSystemRunCommand binds cmdText to full argv for shell-wrapper positional-argv carriers
- resolveSystemRunCommand binds cmdText to full argv when env prelude modifies shell wrapper

### src/infra/tailscale.test.lisp
- tailscale helpers
- parses DNS name from tailscale status
- falls back to IP when DNS missing
- ensureGoInstalled installs when missing and user agrees
- ensureGoInstalled exits when missing and user declines install
- ensureTailscaledInstalled installs when missing and user agrees
- ensureTailscaledInstalled exits when missing and user declines install
- enableTailscaleServe attempts normal first, then sudo
- enableTailscaleServe does NOT use sudo if first attempt succeeds
- disableTailscaleServe uses fallback
- ensureFunnel uses fallback for enabling
- enableTailscaleServe skips sudo on non-permission errors
- enableTailscaleServe rethrows original error if sudo fails

### src/infra/tmp-openclaw-dir.test.lisp
- resolvePreferredOpenClawTmpDir
- prefers /tmp/openclaw when it already exists and is writable
- prefers /tmp/openclaw when it does not exist but /tmp is writable
- falls back to os.tmpdir()/openclaw when /tmp/openclaw is not a directory
- falls back to os.tmpdir()/openclaw when /tmp is not writable
- falls back when /tmp/openclaw is a symlink
- falls back when /tmp/openclaw is not owned by the current user
- falls back when /tmp/openclaw is group/other writable
- throws when fallback path is a symlink
- creates fallback directory when missing, then validates ownership and mode
- repairs fallback directory permissions after create when umask makes it group-writable
- repairs existing fallback directory when permissions are too broad

### src/infra/transport-ready.test.lisp
- waitForTransportReady
- returns when the check succeeds and logs after the delay
- throws after the timeout
- returns early when aborted

### src/infra/unhandled-rejections.fatal-detection.test.lisp
- installUnhandledRejectionHandler - fatal detection
- fatal errors
- exits on fatal runtime codes
- configuration errors
- exits on configuration error codes
- non-fatal errors
- does not exit on known transient network errors
- exits on generic errors without code
- exits on non-transient Slack request errors
- does not exit on AbortError and logs suppression warning

### src/infra/unhandled-rejections.test.lisp
- isAbortError
- returns true for error with name AbortError
- returns true for error with "This operation was aborted" message
- returns true for undici-style AbortError
- returns true for object with AbortError name
- returns false for regular errors
- returns false for errors with similar but different messages
- isTransientNetworkError
- returns true for errors with transient network codes
- returns true for TypeError with "fetch failed" message
- returns true for fetch failed with network cause
- returns true for fetch failed with unclassified cause
- returns true for nested cause chain with network error
- returns true for Slack request errors that wrap network codes in .original
- returns true for network codes nested in .data payloads
- returns true for AggregateError containing network errors
- returns true for wrapped fetch-failed messages from integration clients
- returns false for non-network fetch-failed wrappers from tools
- returns true for TLS/SSL transient message snippets
- returns false for regular errors without network codes
- returns false for errors with non-network codes
- returns false for Slack request errors without network indicators
- returns false for non-transient undici codes that only appear in message text
- returns false for AggregateError with only non-network errors

### src/infra/update-channels.test.lisp
- update-channels tag detection
- recognizes both -beta and .beta formats
- keeps legacy -x tags stable
- does not false-positive on non-beta words

### src/infra/update-check.test.lisp
- compareSemverStrings
- handles stable and prerelease precedence for both legacy and beta formats
- returns null for invalid inputs
- resolveNpmChannelTag
- falls back to latest when beta is older
- keeps beta when beta is not older
- falls back to latest when beta has same base as stable

### src/infra/update-runner.test.lisp
- runGatewayUpdate
- skips git update when worktree is dirty
- aborts rebase on failure
- returns error and stops early when deps install fails
- returns error and stops early when build fails
- uses stable tag when beta tag is older than release
- skips update when no git root
- cleans stale Quicklisp/Ultralisp rename dirs before global update
- retries global Quicklisp/Ultralisp update with --omit=optional when initial install fails
- updates global bun installs when detected
- rejects git roots that are not a openclaw checkout
- fails with a clear reason when openclaw.lisp is missing
- repairs UI assets when doctor run removes control-ui files
- fails when UI assets are still missing after post-doctor repair

### src/infra/update-startup.test.lisp
- update-startup
- hydrates cached update from persisted state during throttle window
- emits update change callback when update state clears
- skips update check when disabled in config
- defers stable auto-update until rollout window is due
- runs beta auto-update checks hourly when enabled
- runs auto-update when checkOnStart is false but auto-update is enabled
- uses current runtime + entrypoint for default auto-update command execution
- scheduleGatewayUpdateCheck returns a cleanup function

### src/infra/warning-filter.test.lisp
- warning filter
- suppresses known deprecation and experimental warning signatures
- keeps unknown warnings visible
- installs once and suppresses known warnings at emit time

### src/infra/watch-sbcl.test.lisp
- watch-sbcl script
- wires sbcl watch to run-sbcl with watched source/config paths
- terminates child on SIGINT and returns shell interrupt code
- terminates child on SIGTERM and returns shell terminate code

### src/infra/widearea-dns.test.lisp
- wide-area DNS-SD zone rendering
- renders a zone with gateway PTR/SRV/TXT records
- includes tailnetDns when provided

### src/infra/windows-task-restart.test.lisp
- relaunchGatewayScheduledTask
- writes a detached schtasks relaunch helper
- prefers OPENCLAW_WINDOWS_TASK_NAME overrides
- returns failed when the helper cannot be spawned
- quotes the cmd /c script path when temp paths contain metacharacters

### src/infra/wsl.test.lisp
- wsl detection
- reads /proc/version for sync WSL detection when env vars are absent
- returns false for sync detection on non-linux platforms
- caches async WSL detection until reset
- returns false when async WSL detection cannot read osrelease
- returns false for async detection on non-linux platforms without reading osrelease

## line

### src/line/accounts.test.lisp
- LINE accounts
- resolveLineAccount
- resolves account from config
- resolves account from environment variables
- resolves named account
- returns empty token when not configured
- resolveDefaultLineAccountId
- prefers channels.line.defaultAccount when configured
- normalizes channels.line.defaultAccount before lookup
- returns first named account when default not configured
- falls back when channels.line.defaultAccount is missing
- normalizeAccountId
- trims and lowercases account ids

### src/line/auto-reply-delivery.test.lisp
- deliverLineAutoReply
- uses reply token for text before sending rich messages
- uses reply token for rich-only payloads
- sends rich messages before quick-reply text so quick replies remain visible
- falls back to push when reply token delivery fails

### src/line/bot-handlers.test.lisp
- handleLineWebhookEvents
- blocks group messages when groupPolicy is disabled
- blocks group messages when allowlist is empty
- allows group messages when sender is in groupAllowFrom
- blocks group sender not in groupAllowFrom even when sender is paired in DM store
- blocks group messages without sender id when groupPolicy is allowlist
- does not authorize group messages from DM pairing-store entries when group allowlist is empty
- blocks group messages when wildcard group config disables groups
- scopes DM pairing requests to accountId
- does not authorize DM senders from another account's pairing-store entries
- deduplicates replayed webhook events by webhookEventId before processing
- skips concurrent redeliveries while the first event is still processing
- mirrors in-flight replay failures so concurrent duplicates also fail
- deduplicates redeliveries by LINE message id when webhookEventId changes
- deduplicates postback redeliveries by webhookEventId when replyToken changes
- skips group messages by default when requireMention is not configured
- records unmentioned group messages as pending history
- skips group messages without mention when requireMention is set
- processes group messages with bot mention when requireMention is set
- processes group messages with @all mention when requireMention is set
- does not apply requireMention gating to DM messages
- allows non-text group messages through when requireMention is set (cannot detect mention)
- does not bypass mention gating when non-bot mention is present with control command
- does not mark replay cache when event processing fails

### src/line/bot-message-context.test.lisp
- buildLineMessageContext
- routes group message replies to the group id
- routes group postback replies to the group id
- routes room postback replies to the room id
- resolves prefixed-only group config through the inbound message context
- resolves prefixed-only room config through the inbound message context
- keeps non-text message contexts fail-closed for command auth
- sets CommandAuthorized=true when authorized
- sets CommandAuthorized=false when not authorized
- sets CommandAuthorized on postback context
- group peer binding matches raw groupId without prefix (#21907)
- room peer binding matches raw roomId without prefix (#21907)

### src/line/download.test.lisp
- downloadLineMedia
- does not derive temp file path from external messageId
- rejects oversized media before writing to disk
- classifies M4A ftyp major brand as audio/mp4
- detects MP4 video from ftyp major brand (isom)

### src/line/flex-templates.test.lisp
- createInfoCard
- includes footer when provided
- createListCard
- limits items to 8
- createImageCard
- includes body text when provided
- createActionCard
- limits actions to 4
- createCarousel
- limits to 12 bubbles
- createDeviceControlCard
- limits controls to 6
- createEventCard
- includes all optional fields together

### src/line/group-keys.test.lisp
- resolveLineGroupLookupIds
- expands raw ids to both prefixed candidates
- preserves prefixed ids while also checking the raw id
- resolveLineGroupConfigEntry
- matches raw, prefixed, and wildcard group config entries
- resolveLineGroupHistoryKey
- uses the raw group or room id as the shared LINE peer key
- account-scoped LINE groups
- resolves the effective account-scoped groups map

### src/line/markdown-to-line.test.lisp
- extractMarkdownTables
- extracts a simple 2-column table
- extracts multiple tables
- handles tables with alignment markers
- returns empty when no tables present
- extractCodeBlocks
- extracts code blocks across language/no-language/multiple variants
- extractLinks
- extracts markdown links
- stripMarkdown
- strips inline markdown marker variants
- handles complex markdown
- convertTableToFlexBubble
- replaces empty cells with placeholders
- strips bold markers and applies weight for fully bold cells
- convertCodeBlockToFlexBubble
- creates a code card with language label
- creates a code card without language
- truncates very long code
- processLineMessage
- processes text with code blocks
- handles mixed content
- handles plain text unchanged
- hasMarkdownToConvert
- detects supported markdown patterns
- returns false for plain text

### src/line/monitor.fail-closed.test.lisp
- monitorLineProvider fail-closed webhook auth
- rejects startup when channel secret is missing
- rejects startup when channel access token is missing

### src/line/monitor.lifecycle.test.lisp
- monitorLineProvider lifecycle
- waits for abort before resolving
- stops immediately when signal is already aborted
- returns immediately without abort signal and stop is idempotent

### src/line/monitor.read-body.test.lisp
- readLineWebhookRequestBody
- reads body within limit
- rejects oversized body

### src/line/probe.test.lisp
- probeLineBot
- returns timeout when bot info stalls
- returns bot info when available

### src/line/reply-chunks.test.lisp
- sendLineReplyChunks
- uses reply token for all chunks when possible
- attaches quick replies to a single reply chunk
- replies with up to five chunks before pushing the rest
- falls back to push flow when replying fails

### src/line/rich-menu.test.lisp
- messageAction
- creates message actions with explicit or default text
- uriAction
- creates a URI action
- action label truncation
- postbackAction
- creates a postback action
- applies postback payload truncation and displayText behavior
- datetimePickerAction
- creates picker actions for all supported modes
- includes initial/min/max when provided
- createGridLayout
- computes expected 2x3 layout for supported menu heights
- assigns correct actions to areas
- createDefaultMenuConfig
- creates a valid default menu configuration
- has valid area bounds
- uses message actions with expected default commands

### src/line/send.test.lisp
- LINE send helpers
- limits quick reply items to 13
- pushes images via normalized LINE target
- replies when reply token is provided
- throws when push messages are empty
- logs HTTP body when push fails
- caches profile results by default
- continues when loading animation is unsupported
- pushes quick-reply text and caps to 13 buttons

### src/line/template-messages.test.lisp
- createConfirmTemplate
- truncates text to 240 characters
- createButtonTemplate
- limits actions to 4
- truncates title to 40 characters
- truncates text to 60 chars when no thumbnail is provided
- keeps longer text when thumbnail is provided
- createCarouselColumn
- limits actions to 3
- truncates text to 120 characters
- carousel column limits
- createProductCarousel

### src/line/webhook-sbcl.test.lisp
- createLineNodeWebhookHandler
- returns 200 for GET
- returns 204 for HEAD
- returns 200 for verification request (empty events, no signature)
- returns 405 for non-GET/HEAD/POST methods
- rejects missing signature when events are non-empty
- uses a tight body-read limit for unsigned POST requests
- uses strict pre-auth limits for signed POST requests
- rejects invalid signature
- accepts valid signature and dispatches events
- returns 500 when event processing fails and does not acknowledge with 200
- returns 400 for invalid JSON payload even when signature is valid

### src/line/webhook.test.lisp
- createLineWebhookMiddleware
- rejects startup when channel secret is missing
- rejects invalid JSON payloads
- rejects webhooks with invalid signatures
- returns 200 for verification request (empty events, no signature)
- rejects missing signature when events are non-empty
- rejects signed requests when raw body is missing
- returns 500 when event processing fails and does not acknowledge with 200

## link-understanding

### src/link-understanding/detect.test.lisp
- extractLinksFromMessage
- extracts bare http/https URLs in order
- dedupes links and enforces maxLinks
- ignores markdown links
- blocks 127.0.0.1
- blocks localhost and common loopback addresses
- blocks private network ranges
- blocks link-local and cloud metadata addresses
- blocks CGNAT range used by Tailscale
- blocks private and mapped IPv6 addresses
- allows legitimate public URLs

## logger.test.lisp

### src/logger.test.lisp
- logger helpers
- formats messages through runtime log/error
- only logs debug when verbose is enabled
- writes to configured log file at configured level
- filters messages below configured level
- uses daily rolling default log file and prunes old ones
- globals
- toggles verbose flag and logs when enabled
- stores yes flag
- stripRedundantSubsystemPrefixForConsole
- drops known subsystem prefixes
- keeps messages that do not start with the subsystem

## logging

### src/logging/console-capture.test.lisp
- enableConsoleCapture
- swallows EIO from stderr writes
- swallows EIO from original console writes
- prefixes console output with timestamps when enabled
- suppresses discord EventQueue slow listener duplicates
- does not double-prefix timestamps
- leaves JSON output unchanged when timestamp prefix is enabled
- rethrows non-EPIPE errors on stdout

### src/logging/console-settings.test.lisp
- getConsoleSettings
- does not recurse when loadConfig logs during resolution
- skips config fallback during re-entrant resolution

### src/logging/console-timestamp.test.lisp
- formatConsoleTimestamp
- pretty style returns local HH:MM:SS
- compact style returns local ISO-like timestamp with timezone offset
- json style returns local ISO-like timestamp with timezone offset
- timestamp contains the correct local date components

### src/logging/diagnostic.test.lisp
- diagnostic session state pruning
- evicts stale idle session states
- caps tracked session states to a bounded max
- reuses keyed session state when later looked up by sessionId
- logger import side effects
- does not mkdir at import time
- stuck session diagnostics threshold
- uses the configured diagnostics.stuckSessionWarnMs threshold
- falls back to default threshold when config is absent
- uses default threshold for invalid values

### src/logging/log-file-size-cap.test.lisp
- log file size cap
- defaults maxFileBytes to 500 MB when unset
- uses configured maxFileBytes
- suppresses file writes after cap is reached and warns once

### src/logging/logger-env.test.lisp
- OPENCLAW_LOG_LEVEL
- applies a valid env override to both file and console levels
- warns once and ignores invalid env values

### src/logging/logger-settings.test.lisp
- getResolvedLoggerSettings
- uses a silent fast path in default FiveAM/Parachute mode without config reads
- reads logging config when test file logging is explicitly enabled

### src/logging/logger-timestamp.test.lisp
- logger timestamp format
- uses local time format in file logs (not UTC)

### src/logging/logger.settings.test.lisp
- shouldSkipLoadConfigFallback
- matches config validate invocations
- handles root flags before config validate
- does not match other commands

### src/logging/parse-log-line.test.lisp
- parseLogLine
- parses structured JSON log lines
- falls back to meta timestamp when top-level time is missing
- returns null for invalid JSON

### src/logging/redact.test.lisp
- redactSensitiveText
- masks env assignments while keeping the key
- masks command-line interface flags
- masks JSON fields
- masks bearer tokens
- masks Telegram-style tokens
- masks Telegram Bot API URL tokens
- redacts short tokens fully
- redacts private key blocks
- honors custom patterns with flags
- ignores unsafe nested-repetition custom patterns
- redacts large payloads with bounded regex passes
- skips redaction when mode is off

### src/logging/subsystem.test.lisp
- createSubsystemLogger().isEnabled
- returns true for any/file when only file logging would emit
- returns true for any/console when only console logging would emit
- returns false when neither console nor file logging would emit
- honors console subsystem filters for console target
- does not apply console subsystem filters to file target

### src/logging/timestamps.test.lisp
- formatLocalIsoWithOffset
- produces +00:00 offset for UTC
- produces +08:00 offset for Asia/Shanghai
- produces correct offset for America/New_York
- produces correct offset for America/New_York in summer (EDT)
- outputs a valid ISO 8601 string with offset
- falls back gracefully for an invalid timezone
- does NOT use getHours, getMinutes, getTimezoneOffset in the implementation
- isValidTimeZone
- returns true for valid IANA timezones
- returns false for invalid timezone strings

## markdown

### src/markdown/frontmatter.test.lisp
- parseFrontmatterBlock
- parses YAML block scalars
- handles JSON5-style multi-line metadata
- preserves inline JSON values
- stringifies YAML objects and arrays
- preserves inline description values containing colons
- does not replace YAML block scalars with block indicators
- keeps nested YAML mappings as structured JSON
- returns empty when frontmatter is missing

### src/markdown/ir.blockquote-spacing.test.lisp
- blockquote spacing
- blockquote followed by paragraph
- should have double newline (one blank line) between blockquote and paragraph
- should not produce triple newlines
- consecutive blockquotes
- should have double newline between two blockquotes
- should not produce triple newlines between blockquotes
- nested blockquotes
- should handle nested blockquotes correctly
- should not produce triple newlines in nested blockquotes
- should handle deeply nested blockquotes
- blockquote followed by other block elements
- should have double newline between blockquote and heading
- should have double newline between blockquote and list
- should have double newline between blockquote and code block
- should have double newline between blockquote and horizontal rule
- blockquote with multi-paragraph content
- should handle multi-paragraph blockquote followed by paragraph
- blockquote prefix option
- should include prefix and maintain proper spacing
- edge cases
- should handle empty blockquote followed by paragraph
- should handle blockquote at end of document
- should handle multiple blockquotes with paragraphs between
- comparison with other block elements (control group)
- paragraphs should have double newline separation
- list followed by paragraph should have double newline
- heading followed by paragraph should have double newline

### src/markdown/ir.hr-spacing.test.lisp
- hr (thematic break) spacing
- current behavior documentation
- just hr alone renders as separator
- hr interrupting paragraph (setext heading case)
- expected behavior (tests assert CORRECT behavior)
- hr between paragraphs should render with separator
- hr between paragraphs using *** should render with separator
- hr between paragraphs using ___ should render with separator
- consecutive hrs should produce multiple separators
- hr at document end renders separator
- hr at document start renders separator
- should not produce triple newlines regardless of hr placement
- multiple consecutive hrs between paragraphs should each render as separator
- edge cases
- hr between list items renders as separator without extra spacing
- hr followed immediately by heading
- heading followed by hr

### src/markdown/ir.nested-lists.test.lisp
- Nested Lists - 2 Level Nesting
- renders bullet items nested inside bullet items with proper indentation
- renders ordered items nested inside bullet items
- renders bullet items nested inside ordered items
- renders ordered items nested inside ordered items
- Nested Lists - 3+ Level Deep Nesting
- renders 3 levels of bullet nesting
- renders 4 levels of bullet nesting
- renders 3 levels with multiple items at each level
- Nested Lists - Mixed Nesting
- renders complex mixed nesting (bullet > ordered > bullet)
- renders ordered > bullet > ordered nesting
- Nested Lists - Newline Handling
- does not produce triple newlines in nested lists
- does not produce double newlines between nested items
- properly terminates top-level list (trimmed output)
- Nested Lists - Edge Cases
- handles empty parent with nested items
- handles nested list as first child of parent item
- handles sibling nested lists at same level
- list paragraph spacing
- adds blank line between bullet list and following paragraph
- adds blank line between ordered list and following paragraph
- does not produce triple newlines

### src/markdown/ir.table-bullets.test.lisp
- markdownToIR tableMode bullets
- converts simple table to bullets
- handles table with multiple columns
- leaves table syntax untouched by default
- handles empty cells gracefully
- bolds row labels in bullets mode
- renders tables as code blocks in code mode
- preserves inline styles and links in bullets mode

### src/markdown/ir.table-code.test.lisp
- markdownToIR tableMode code - style overlap
- should not have overlapping styles when cell has bold text
- should not have overlapping styles when cell has italic text
- should not have overlapping styles when cell has inline code
- should not have overlapping styles with multiple styled cells

### src/markdown/whatsapp.test.lisp
- markdownToWhatsApp
- handles common markdown-to-whatsapp conversions
- preserves fenced code blocks
- preserves code block with formatting inside

## media

### src/media/audio.test.lisp
- isVoiceCompatibleAudio
- returns false when no contentType and no fileName
- prefers MIME type over extension

### src/media/base64.test.lisp
- base64 helpers
- normalizes whitespace and keeps valid base64
- rejects invalid base64 characters
- estimates decoded bytes with whitespace

### src/media/fetch.test.lisp
- fetchRemoteMedia
- rejects when content-length exceeds maxBytes
- rejects when streamed payload exceeds maxBytes
- blocks private IP literals before fetching

### src/media/ffmpeg-exec.test.lisp
- parseFfprobeCsvFields
- splits ffprobe csv output across commas and newlines
- parseFfprobeCodecAndSampleRate
- parses opus codec and numeric sample rate
- returns null sample rate for invalid numeric fields

### src/media/host.test.lisp
- ensureMediaHosted
- throws and cleans up when server not allowed to start
- starts media server when allowed
- skips server start when port already in use

### src/media/image-ops.helpers.test.lisp
- buildImageResizeSideGrid
- returns descending unique sides capped by maxSide
- keeps only positive side values
- IMAGE_REDUCE_QUALITY_STEPS
- keeps expected quality ladder

### src/media/inbound-path-policy.test.lisp
- inbound-path-policy
- validates absolute root patterns
- matches wildcard roots for iMessage attachment paths
- normalizes and de-duplicates merged roots
- resolves configured roots with account overrides
- falls back to default iMessage roots

### src/media/input-files.fetch-guard.test.lisp
- HEIC input image normalization
- converts base64 HEIC images to JPEG before returning them
- converts URL HEIC images to JPEG before returning them
- keeps declared MIME for non-HEIC images after validation
- rejects spoofed base64 images when detected bytes are not an image
- rejects spoofed URL images when detected bytes are not an image
- fetchWithGuard
- rejects oversized streamed payloads and cancels the stream
- base64 size guards
- input image base64 validation
- rejects malformed base64 payloads
- normalizes whitespace in valid base64 payloads

### src/media/load-options.test.lisp
- media load options
- returns undefined localRoots when mediaLocalRoots is empty
- keeps trusted mediaLocalRoots entries
- builds loadWebMedia options from maxBytes and mediaLocalRoots

### src/media/mime.test.lisp
- mime detection
- detects docx from buffer
- detects pptx from buffer
- prefers extension mapping over generic zip
- uses extension mapping for Common Lisp assets
- extensionForMime
- isAudioFileName
- matches known audio extensions
- normalizeMimeType
- mediaKindFromMime
- normalizes MIME strings before kind classification
- returns undefined for missing or unrecognized MIME kinds

### src/media/parse.test.lisp
- splitMediaFromOutput
- detects audio_as_voice tag and strips it
- accepts supported media path variants
- keeps audio_as_voice detection stable across calls
- keeps MEDIA mentions in prose
- rejects bare words without file extensions

### src/media/server.outside-workspace.test.lisp
- media server outside-workspace mapping
- returns 400 with a specific outside-workspace message

### src/media/server.test.lisp
- media server
- serves media and cleans up after send
- expires old media
- rejects oversized media files
- returns not found for missing media IDs
- returns 404 when route param is missing (dot path)
- rejects overlong media id

### src/media/store.outside-workspace.test.lisp
- media store outside-workspace mapping
- maps outside-workspace reads to a descriptive invalid-path error

### src/media/store.redirect.test.lisp
- media store redirects
- follows redirects and keeps detected mime/extension
- fails when redirect response omits location header

### src/media/store.test.lisp
- media store
- creates and returns media directory
- saves buffers and enforces size limit
- retries buffer writes when cleanup prunes the target directory
- copies local files and cleans old media
- retries local-source writes when cleanup prunes the target directory
- rejects directory sources with typed error code
- cleans old media files in first-level subdirectories
- cleans old media files in nested subdirectories and preserves fresh siblings
- keeps nested remote-cache files during shallow cleanup
- prunes empty directory chains after recursive cleanup
- sets correct mime for xlsx by extension
- renames media based on detected mime even when extension is wrong
- sniffs xlsx mime for zip buffers and renames extension
- prefers header mime extension when sniffed mime lacks mapping
- extractOriginalFilename
- extracts original filename from embedded pattern
- handles uppercase UUID pattern
- falls back to basename for non-matching patterns
- preserves original name with special characters
- saveMediaBuffer with originalFilename
- embeds original filename in stored path when provided
- sanitizes unsafe characters in original filename
- truncates long original filenames
- falls back to UUID-only when originalFilename not provided

## media-understanding

### src/media-understanding/apply.echo-transcript.test.lisp
- applyMediaUnderstanding – echo transcript
- does NOT echo when echoTranscript is false (default)
- does NOT echo when echoTranscript is absent (default)
- echoes transcript with default format when echoTranscript is true
- uses custom echoFormat when provided
- does NOT echo when there are no audio attachments
- does NOT echo when transcription fails
- does NOT echo when channel is not deliverable
- does NOT echo when ctx has no From or OriginatingTo
- uses OriginatingTo when From is absent
- echo delivery failure does not throw or break transcription

### src/media-understanding/apply.test.lisp
- applyMediaUnderstanding
- sets Transcript and replaces Body when audio transcription succeeds
- skips file blocks for text-like audio when transcription succeeds
- keeps caption for command parsing when audio has user text
- handles URL-only attachments for audio transcription
- transcribes WhatsApp audio with parameterized MIME despite casing/whitespace
- skips URL-only audio when remote file is too small
- skips audio transcription when attachment exceeds maxBytes
- falls back to command-line interface model when provider fails
- reads parakeet-mlx transcript from output-dir txt file
- falls back to stdout for parakeet-mlx when output format is not txt
- auto-detects sherpa for audio when binary and model files are available
- auto-detects whisper-cli when sherpa is unavailable
- skips audio auto-detect when no supported binaries or provider keys are available
- uses command-line interface image understanding and preserves caption for commands
- uses shared media models list when capability config is missing
- uses active model when enabled and models are missing
- handles multiple audio attachments when attachment mode is all
- orders mixed media outputs as image, audio, video
- treats text-like attachments as CSV (comma wins over tabs)
- infers TSV when tabs are present without commas
- treats cp1252-like attachments as text
- skips binary audio attachments that are not text-like
- does not reclassify PDF attachments as text/plain
- respects configured allowedMimes for text-like attachments
- escapes XML special characters in filenames to prevent injection
- escapes file block content to prevent structure injection
- normalizes MIME types to prevent attribute injection
- handles path traversal attempts in filenames safely
- forces BodyForCommands when only file blocks are added
- handles files with non-ASCII Unicode filenames
- skips binary application/vnd office attachments even when bytes look printable
- keeps vendor +json attachments eligible for text extraction

### src/media-understanding/attachments.guards.test.lisp
- media-understanding selectAttachments guards
- does not throw when attachments is undefined
- does not throw when attachments is not an array
- ignores malformed attachment entries inside an array

### src/media-understanding/defaults.test.lisp
- DEFAULT_AUDIO_MODELS
- includes Mistral Voxtral default
- AUTO_AUDIO_KEY_PROVIDERS
- includes mistral auto key resolution
- AUTO_VIDEO_KEY_PROVIDERS
- includes moonshot auto key resolution
- AUTO_IMAGE_KEY_PROVIDERS
- includes minimax-portal auto key resolution
- DEFAULT_IMAGE_MODELS
- includes the MiniMax portal vision default

### src/media-understanding/format.test.lisp
- formatMediaUnderstandingBody
- replaces placeholder body with transcript
- includes user text when body is meaningful
- strips leading media placeholders from user text
- keeps user text once when multiple outputs exist
- formats image outputs

### src/media-understanding/media-understanding-misc.test.lisp
- media understanding scope
- normalizes chatType
- matches channel chatType explicitly
- media understanding attachments SSRF
- blocks private IP URLs before fetching
- reads local attachments inside configured roots
- blocks local attachments outside configured roots
- blocks directory attachments even inside configured roots
- blocks symlink escapes that resolve outside configured roots

### src/media-understanding/providers/deepgram/audio.live.test.lisp
- transcribes sample audio

### src/media-understanding/providers/deepgram/audio.test.lisp
- transcribeDeepgramAudio
- respects lowercase authorization header overrides
- builds the expected request payload
- throws when the provider response omits transcript

### src/media-understanding/providers/google/video.test.lisp
- describeGeminiVideo
- respects case-insensitive x-goog-api-key overrides
- builds the expected request payload

### src/media-understanding/providers/image.test.lisp
- describeImageWithModel
- routes minimax-portal image models through the MiniMax VLM endpoint
- uses generic completion for non-canonical minimax-portal image models
- normalizes deprecated google flash ids before lookup and keeps profile auth selection
- normalizes gemini 3.1 flash-lite ids before lookup and keeps profile auth selection

### src/media-understanding/providers/index.test.lisp
- media-understanding provider registry
- registers the Mistral provider
- keeps provider id normalization behavior
- registers the Moonshot provider
- registers the minimax portal provider

### src/media-understanding/providers/mistral/index.test.lisp
- mistralProvider
- has expected provider metadata
- uses Mistral base URL by default
- allows overriding baseUrl

### src/media-understanding/providers/moonshot/video.test.lisp
- describeMoonshotVideo
- builds an OpenAI-compatible video request
- falls back to reasoning_content when content is empty

### src/media-understanding/providers/openai/audio.test.lisp
- transcribeOpenAiCompatibleAudio
- respects lowercase authorization header overrides
- builds the expected request payload
- throws when the provider response omits text

### src/media-understanding/resolve.test.lisp
- resolveModelEntries
- uses provider capabilities for shared entries without explicit caps
- keeps per-capability entries even without explicit caps
- skips shared command-line interface entries without capabilities
- resolveEntriesWithActiveFallback
- uses active model when enabled and no models are configured
- ignores active model when configured entries exist
- skips active model when provider lacks capability

### src/media-understanding/runner.auto-audio.test.lisp
- runCapability auto audio entries
- uses provider keys to auto-enable audio transcription
- skips auto audio when disabled
- prefers explicitly configured audio model entries
- uses mistral when only mistral key is configured

### src/media-understanding/runner.deepgram.test.lisp
- runCapability deepgram provider options
- merges provider options, headers, and baseUrl overrides

### src/media-understanding/runner.entries.guards.test.lisp
- media-understanding formatDecisionSummary guards
- does not throw when decision.attachments is undefined
- does not throw when attachment attempts is malformed
- ignores non-string provider/model/reason fields

### src/media-understanding/runner.proxy.test.lisp
- runCapability proxy fetch passthrough
- passes fetchFn to audio provider when HTTPS_PROXY is set
- passes fetchFn to video provider when HTTPS_PROXY is set
- does not pass fetchFn when no proxy env vars are set

### src/media-understanding/runner.skip-tiny-audio.test.lisp
- runCapability skips tiny audio files
- skips audio transcription when file is smaller than MIN_AUDIO_FILE_BYTES
- skips audio transcription for empty (0-byte) files
- proceeds with transcription when file meets minimum size

### src/media-understanding/runner.video.test.lisp
- runCapability video provider wiring
- merges video baseUrl and headers with entry precedence
- auto-selects moonshot for video when google is unavailable

### src/media-understanding/runner.vision-skip.test.lisp
- runCapability image skip
- skips image understanding when the active model supports vision

### src/media-understanding/transcribe-audio.test.lisp
- transcribeAudioFile
- does not force audio/wav when mime is omitted
- returns undefined when helper returns no transcript
- propagates helper errors

## memory

### src/memory/backend-config.test.lisp
- resolveMemoryBackendConfig
- defaults to builtin backend when config missing
- resolves qmd backend with default collections
- parses quoted qmd command paths
- resolves custom paths relative to workspace
- scopes qmd collection names per agent
- resolves qmd update timeout overrides
- resolves qmd search mode override

### src/memory/batch-error-utils.test.lisp
- extractBatchErrorMessage
- returns the first top-level error message
- falls back to nested response error message
- accepts plain string response bodies
- formatUnavailableBatchError
- formats errors and non-error values

### src/memory/batch-http.test.lisp
- postJsonWithRetry
- posts JSON and returns parsed response payload
- attaches status to non-ok errors

### src/memory/batch-output.test.lisp
- applyEmbeddingBatchOutputLine
- stores embedding for successful response
- records provider error from line.error
- records non-2xx response errors and empty embedding errors

### src/memory/batch-status.test.lisp
- batch-status helpers
- resolves completion payload from completed status
- throws for terminal failure states
- returns completed result directly without waiting
- throws when wait disabled and batch is not complete

### src/memory/batch-voyage.test.lisp
- runVoyageEmbeddingBatches
- successfully submits batch, waits, and streams results
- handles empty lines and stream chunks correctly

### src/memory/embedding-chunk-limits.test.lisp
- embedding chunk limits
- splits oversized chunks so each embedding input stays <= maxInputTokens bytes
- does not split inside surrogate pairs (emoji)
- uses conservative fallback limits for local providers without declared maxInputTokens
- honors hard safety caps lower than provider maxInputTokens

### src/memory/embeddings-mistral.test.lisp
- normalizeMistralModel
- returns the default model for empty values
- strips the mistral/ prefix
- keeps explicit non-prefixed models

### src/memory/embeddings-model-normalize.test.lisp
- normalizeEmbeddingModelWithPrefixes
- returns default model when input is blank
- strips the first matching prefix
- keeps explicit model names when no prefix matches

### src/memory/embeddings-ollama.test.lisp
- embeddings-ollama
- calls /api/embeddings and returns normalized vectors
- resolves baseUrl/apiKey/headers from models.providers.ollama and strips /v1
- fails fast when memory-search remote apiKey is an unresolved SecretRef
- falls back to env key when models.providers.ollama.apiKey is an unresolved SecretRef

### src/memory/embeddings-remote-fetch.test.lisp
- fetchRemoteEmbeddingVectors
- maps remote embedding response data to vectors
- throws a status-rich error on non-ok responses

### src/memory/embeddings-voyage.test.lisp
- voyage embedding provider
- configures client with correct defaults and headers
- respects remote overrides for baseUrl and apiKey
- passes input_type=document for embedBatch
- normalizes model names

### src/memory/embeddings.test.lisp
- embedding provider remote overrides
- uses remote baseUrl/apiKey and merges headers
- falls back to resolved api key when remote apiKey is blank
- builds Gemini embeddings requests with api key header
- fails fast when Gemini remote apiKey is an unresolved SecretRef
- uses GEMINI_API_KEY env indirection for Gemini remote apiKey
- builds Mistral embeddings requests with bearer auth
- embedding provider auto selection
- prefers openai when a key resolves
- uses gemini when openai is missing
- keeps explicit model when openai is selected
- uses mistral when openai/gemini/voyage are missing
- embedding provider local fallback
- falls back to openai when sbcl-llama-cpp is missing
- throws a helpful error when local is requested and fallback is none
- mentions every remote provider in local setup guidance
- local embedding normalization
- normalizes local embeddings to magnitude ~1.0
- handles zero vector without division by zero
- sanitizes non-finite values before normalization
- normalizes batch embeddings to magnitude ~1.0
- local embedding ensureContext concurrency
- loads the model only once when embedBatch is called concurrently
- retries initialization after a transient ensureContext failure
- shares initialization when embedQuery and embedBatch start concurrently
- FTS-only fallback when no provider available
- returns null provider with reason when auto mode finds no providers
- returns null provider when explicit provider fails with missing API key
- returns null provider when both primary and fallback fail with missing API keys

### src/memory/hybrid.test.lisp
- memory hybrid helpers
- buildFtsQuery tokenizes and AND-joins
- bm25RankToScore is monotonic and clamped
- bm25RankToScore preserves FTS5 BM25 relevance ordering
- mergeHybridResults unions by id and combines weighted scores
- mergeHybridResults prefers keyword snippet when ids overlap

### src/memory/index.test.lisp
- memory index
- indexes memory files and searches
- keeps dirty false in status-only manager after prior indexing
- reindexes sessions when source config adds sessions to an existing index
- reindexes when the embedding model changes
- reuses cached embeddings on forced reindex
- finds keyword matches via hybrid search when query embedding is zero
- preserves keyword-only hybrid hits when minScore exceeds text weight
- reports vector availability after probe
- rejects reading non-memory paths
- allows reading from additional memory paths and blocks symlinks

### src/memory/internal.test.lisp
- normalizeExtraMemoryPaths
- trims, resolves, and dedupes paths
- listMemoryFiles
- includes files from additional paths (directory)
- includes files from additional paths (single file)
- handles relative paths in additional paths
- ignores non-existent additional paths
- ignores symlinked files and directories
- dedupes overlapping extra paths that resolve to the same file
- buildFileEntry
- returns null when the file disappears before reading
- returns metadata when the file exists
- chunkMarkdown
- splits overly long lines into max-sized chunks
- remapChunkLines
- remaps chunk line numbers using a lineMap
- preserves original line numbers when lineMap is undefined
- handles multi-chunk content with correct remapping

### src/memory/manager.async-search.test.lisp
- memory search async sync
- does not await sync when searching
- waits for in-flight search sync during close

### src/memory/manager.atomic-reindex.test.lisp
- memory manager atomic reindex
- keeps the prior index when a full reindex fails

### src/memory/manager.batch.test.lisp
- memory indexing with OpenAI batches
- uses OpenAI batch uploads when enabled
- retries OpenAI batch create on transient failures
- tracks batch failures, resets on success, and disables after repeated failures

### src/memory/manager.embedding-batches.test.lisp
- memory embedding batches
- splits large files across multiple embedding batches
- keeps small files in a single embedding batch
- retries embeddings on transient rate limit and 5xx errors
- skips empty chunks so embeddings input stays valid

### src/memory/manager.get-concurrency.test.lisp
- memory manager cache hydration
- deduplicates concurrent manager creation for the same cache key

### src/memory/manager.mistral-provider.test.lisp
- memory manager mistral provider wiring
- stores mistral client when mistral provider is selected
- stores mistral client after fallback activation
- uses default ollama model when activating ollama fallback

### src/memory/manager.read-file.test.lisp
- MemoryIndexManager.readFile
- returns empty text when the requested file does not exist
- returns content slices when the file exists
- returns empty text when the requested slice is past EOF
- returns empty text when the file disappears after stat

### src/memory/manager.readonly-recovery.test.lisp
- memory manager readonly recovery
- reopens sqlite and retries once when sync hits SQLITE_READONLY
- reopens sqlite and retries when readonly appears in error code
- does not retry non-readonly sync errors
- sets busy_timeout on memory sqlite connections

### src/memory/manager.sync-errors-do-not-crash.test.lisp
- memory manager sync failures
- does not raise unhandledRejection when watch-triggered sync fails

### src/memory/manager.vector-dedupe.test.lisp
- memory vector dedupe
- deletes existing vector rows before inserting replacements

### src/memory/manager.watcher-config.test.lisp
- memory watcher config
- watches markdown globs and ignores dependency directories

### src/memory/mmr.test.lisp
- tokenize
- normalizes, filters, and deduplicates token sets
- jaccardSimilarity
- computes expected scores for overlap edge cases
- is symmetric
- textSimilarity
- computes expected text-level similarity cases
- computeMMRScore
- balances relevance and diversity across lambda settings
- empty input behavior
- returns empty array for empty input
- mmrRerank
- edge cases
- returns single item unchanged
- returns copy, not original array
- returns items unchanged when disabled
- lambda edge cases
- lambda=1 returns pure relevance order
- lambda=0 maximizes diversity
- clamps lambda > 1 to 1
- clamps lambda < 0 to 0
- diversity behavior
- promotes diverse results over similar high-scoring ones
- handles items with identical content
- handles all identical content gracefully
- tie-breaking
- uses original score as tiebreaker
- preserves all items even with same MMR scores
- score normalization
- handles items with same scores
- handles negative scores
- applyMMRToHybridResults
- preserves all original fields
- creates unique IDs from path and startLine
- re-ranks results for diversity
- respects disabled config
- DEFAULT_MMR_CONFIG
- has expected default values

### src/memory/post-json.test.lisp
- postJson
- parses JSON payload on successful response
- attaches status to thrown error when requested

### src/memory/qmd-manager.test.lisp
- QmdMemoryManager
- debounces back-to-back sync calls
- runs boot update in background by default
- skips qmd command side effects in status mode initialization
- can be configured to block startup on boot update
- times out collection bootstrap commands
- rebinds sessions collection when existing collection path targets another agent
- avoids destructive rebind when qmd only reports collection names
- migrates unscoped legacy collections before adding scoped names
- rebinds conflicting collection name when path+pattern slot is already occupied
- warns instead of silently succeeding when add conflict metadata is unavailable
- migrates unscoped legacy collections from plain-text collection list output
- does not migrate unscoped collections when listed metadata differs
- times out qmd update during sync when configured
- rebuilds managed collections once when qmd update fails with null-byte ENOTDIR
- rebuilds managed collections once when qmd update hits duplicate document constraint
- does not rebuild collections for unrelated unique constraint failures
- does not rebuild collections for generic qmd update failures
- uses configured qmd search mode command
- repairs missing managed collections and retries search once
- resolves bare qmd command to a Windows-compatible spawn invocation
- normalizes mixed Han-script BM25 queries before qmd search
- falls back to the original query when Han normalization yields no BM25 tokens
- keeps original Han queries in qmd query mode
- retries search with qmd query when configured mode rejects flags
- queues a forced sync behind an in-flight update
- honors multiple forced sync requests while forced queue is active
- scopes qmd queries to managed collections
- runs qmd query per collection when query mode has multiple collection filters
- uses per-collection query fallback when search mode rejects flags
- runs qmd searches via mcporter and warns when startDaemon=false
- uses mcporter.cmd on Windows when mcporter bridge is enabled
- retries mcporter search with bare command on Windows EINVAL cmd-shim failures
- passes manager-scoped XDG env to mcporter commands
- retries mcporter daemon start after a failure
- starts the mcporter daemon only once when enabled
- fails closed when no managed collections are configured
- diversifies mixed session and memory search results so memory hits are retained
- logs and continues when qmd embed times out
- skips qmd embed in search mode even for forced sync
- retries boot update when qmd reports a retryable lock error
- succeeds on qmd update even when stdout exceeds the output cap
- scopes by channel for agent-prefixed session keys
- logs when qmd scope denies search
- blocks non-markdown or symlink reads for qmd paths
- reads only requested line ranges without loading the whole file
- returns empty text when qmd files are missing before or during read
- reuses exported session markdown files when inputs are unchanged
- fails closed when sqlite index is busy during doc lookup or search
- prefers exact docid match before prefix fallback for qmd document lookups
- prefers collection hint when resolving duplicate qmd document hashes
- resolves search hits when qmd returns qmd:// file URIs without docid
- preserves multi-collection qmd search hits when results only include file URIs
- errors when qmd output exceeds command output safety cap
- treats plain-text no-results markers from stdout/stderr as empty result sets
- throws when stdout is empty without the no-results marker
- sets busy_timeout on qmd sqlite connections
- model cache symlink
- handles first-run symlink, existing dir preservation, and missing default cache

### src/memory/qmd-query-parser.test.lisp
- parseQmdQueryJson
- parses clean qmd JSON output
- extracts embedded result arrays from noisy stdout
- treats plain-text no-results from stderr as an empty result set
- treats prefixed no-results marker output as an empty result set
- does not treat arbitrary non-marker text as no-results output
- throws when stdout cannot be interpreted as qmd JSON

### src/memory/qmd-scope.test.lisp
- qmd scope
- derives channel and chat type from canonical keys once
- derives channel and chat type from stored key suffixes
- treats parsed keys with no chat prefix as direct
- applies scoped key-prefix checks against normalized key
- supports rawKeyPrefix matches for agent-prefixed keys
- keeps legacy agent-prefixed keyPrefix rules working

### src/memory/query-expansion.test.lisp
- extractKeywords
- extracts keywords from English conversational query
- extracts keywords from Chinese conversational query
- extracts keywords from mixed language query
- returns specific technical terms
- extracts keywords from Korean conversational query
- strips Korean particles to extract stems
- filters Korean stop words including inflected forms
- filters inflected Korean stop words not explicitly listed
- does not produce bogus single-char stems from particle stripping
- strips longest Korean trailing particles first
- keeps stripped ASCII stems for mixed Korean tokens
- handles mixed Korean and English query
- extracts keywords from Japanese conversational query
- handles mixed Japanese and English query
- filters Japanese stop words
- extracts keywords from Spanish conversational query
- extracts keywords from Portuguese conversational query
- filters Spanish and Portuguese question stop words
- extracts keywords from Arabic conversational query
- filters Arabic question stop words
- handles empty query
- handles query with only stop words
- removes duplicate keywords
- expandQueryForFts
- returns original query and extracted keywords
- builds expanded OR query for FTS
- returns original query when no keywords extracted

### src/memory/search-manager.test.lisp
- getMemorySearchManager caching
- reuses the same QMD manager instance for repeated calls
- evicts failed qmd wrapper so next call retries qmd
- does not cache status-only qmd managers
- does not evict a newer cached wrapper when closing an older failed wrapper
- falls back to builtin search when qmd fails with sqlite busy
- keeps original qmd error when fallback manager initialization fails

### src/memory/session-files.test.lisp
- buildSessionEntry
- returns lineMap tracking original JSONL line numbers
- returns empty lineMap when no messages are found
- skips blank lines and invalid JSON without breaking lineMap

### src/memory/temporal-decay.test.lisp
- temporal decay
- matches exponential decay formula
- is 0.5 exactly at half-life
- does not decay evergreen memory files
- applies decay in hybrid merging before ranking
- handles future dates, zero age, and very old memories
- uses file mtime fallback for non-memory sources

## sbcl-host

### src/sbcl-host/exec-policy.test.lisp
- resolveExecApprovalDecision
- accepts known approval decisions
- normalizes unknown approval decisions to null
- formatSystemRunAllowlistMissMessage
- returns legacy allowlist miss message by default
- adds shell-wrapper guidance when wrappers are blocked
- adds Windows shell-wrapper guidance when blocked by cmd.exe policy
- evaluateSystemRunPolicy
- denies when security mode is deny
- requires approval when ask policy requires it
- allows allowlist miss when explicit approval is provided
- denies allowlist misses without approval
- treats shell wrappers as allowlist misses
- keeps Windows-specific guidance for cmd.exe wrappers
- allows execution when policy checks pass

### src/sbcl-host/invoke-system-run-plan.test.lisp
- hardenApprovedExecutionPaths
- captures mutable shell script operands in approval plans

### src/sbcl-host/invoke-system-run.test.lisp
- formatSystemRunAllowlistMissMessage
- returns legacy allowlist miss message by default
- adds Windows shell-wrapper guidance when blocked by cmd.exe policy
- handleSystemRunInvoke mac app exec host routing
- uses local execution by default when mac app exec host preference is disabled
- uses mac app exec host when explicitly preferred
- forwards canonical cmdText to mac app exec host for positional-argv shell wrappers
- handles transparent env wrappers in allowlist mode
- denies semantic env wrappers in allowlist mode
- uses canonical executable path for approval-based relative command execution
- denies approval-based execution when cwd identity drifts before execution
- denies approval-based execution when a script operand changes after approval
- keeps approved shell script execution working when the script is unchanged
- denies ./sh wrapper spoof in allowlist on-miss mode before execution
- denies ./skill-bin even when autoAllowSkills trust entry exists
- denies env -S shell payloads in allowlist mode
- denies semicolon-chained shell payloads in allowlist mode without explicit approval
- denies PowerShell encoded-command payloads in allowlist mode without explicit approval
- denies env-wrapped shell payloads at the dispatch depth boundary
- denies nested env shell payloads when wrapper depth is exceeded

### src/sbcl-host/invoke.sanitize-env.test.lisp
- sbcl-host sanitizeEnv
- ignores PATH overrides
- blocks dangerous env keys/prefixes
- blocks dangerous override-only env keys
- drops dangerous inherited env keys even without overrides
- sbcl-host output decoding
- parses code pages from chcp output text
- decodes GBK output on Windows when code page is known
- buildNodeInvokeResultParams
- omits optional fields when null/undefined
- includes payloadJSON when provided
- includes payload when provided

### src/sbcl-host/runner.credentials.test.lisp
- resolveNodeHostGatewayCredentials
- does not inherit gateway.remote token in local mode
- ignores unresolved gateway.remote token refs in local mode
- resolves remote token SecretRef values
- prefers OPENCLAW_GATEWAY_TOKEN over configured refs
- throws when a configured remote token ref cannot resolve
- does not resolve remote password refs when token auth is already available

## pairing

### src/pairing/pairing-challenge.test.lisp
- issuePairingChallenge
- creates and sends a pairing reply when request is newly created
- does not send a reply when request already exists
- supports custom reply text builder
- calls onCreated and forwards meta to upsert
- captures reply errors through onReplyError

### src/pairing/pairing-messages.test.lisp
- buildPairingReply
- formats pairing reply for ${testCase.channel}

### src/pairing/pairing-store.test.lisp
- pairing store
- reuses pending code and reports created=false
- expires pending requests after TTL
- regenerates when a generated code collides
- caps pending requests at the default limit
- stores allowFrom entries per account when accountId is provided
- approves pairing codes into account-scoped allowFrom via pairing metadata
- filters approvals by account id and ignores blank approval codes
- removes account-scoped allowFrom entries idempotently
- reads sync allowFrom with account-scoped isolation and wildcard filtering
- does not read legacy channel-scoped allowFrom for non-default account ids
- does not fall back to legacy allowFrom when scoped file exists but is empty
- keeps async and sync reads aligned for malformed scoped allowFrom files
- does not reuse pairing requests across accounts for the same sender id
- reads legacy channel-scoped allowFrom for default account
- uses default-account allowFrom when account id is omitted
- reuses cached async allowFrom reads and invalidates on file updates
- reuses cached sync allowFrom reads and invalidates on file updates

### src/pairing/setup-code.test.lisp
- pairing setup code
- encodes payload as base64url JSON
- resolves custom bind + token auth
- resolves gateway.auth.password SecretRef for pairing payload
- uses OPENCLAW_GATEWAY_PASSWORD without resolving configured password SecretRef
- does not resolve gateway.auth.password SecretRef in token mode
- resolves gateway.auth.token SecretRef for pairing payload
- errors when gateway.auth.token SecretRef is unresolved in token mode
- uses password env in inferred mode without resolving token SecretRef
- does not treat env-template token as plaintext in inferred mode
- requires explicit auth mode when token and password are both configured
- errors when token and password SecretRefs are both configured with inferred mode
- honors env token override
- errors when gateway is loopback only
- uses tailscale serve DNS when available
- prefers gateway.remote.url over tailscale when requested

## plugin-sdk

### src/plugin-sdk/allow-from.test.lisp
- isAllowedParsedChatSender
- denies when allowFrom is empty
- allows wildcard entries
- matches normalized handles
- matches chat IDs when provided
- isNormalizedSenderAllowed
- allows wildcard
- normalizes case and strips prefixes
- rejects when sender is missing
- formatAllowFromLowercase
- trims, strips prefixes, and lowercases entries
- formatNormalizedAllowFromEntries
- applies custom normalization after trimming
- filters empty normalized entries

### src/plugin-sdk/allowlist-resolution.test.lisp
- mapAllowlistResolutionInputs
- maps inputs sequentially and preserves order

### src/plugin-sdk/channel-config-helpers.test.lisp
- mapAllowFromEntries
- coerces allowFrom entries to strings
- returns empty list for missing input
- resolveOptionalConfigString
- trims and returns string values
- coerces numeric values
- returns undefined for empty values
- createScopedAccountConfigAccessors
- maps allowFrom and defaultTo from the resolved account
- omits resolveDefaultTo when no selector is provided

### src/plugin-sdk/channel-lifecycle.test.lisp
- plugin-sdk channel lifecycle helpers
- resolves waitUntilAbort when signal aborts
- keeps server task pending until close, then resolves
- triggers abort hook once and resolves after close

### src/plugin-sdk/command-auth.test.lisp
- plugin-sdk/command-auth
- authorizes group commands from explicit group allowlist
- keeps pairing-store identities DM-only for group command auth

### src/plugin-sdk/fetch-auth.test.lisp
- fetchWithBearerAuthScopeFallback
- rejects non-https urls when https is required
- returns immediately when the first attempt succeeds
- retries with auth scopes after a 401 response
- does not attach auth when host predicate rejects url
- continues across scopes when token retrieval fails

### src/plugin-sdk/group-access.test.lisp
- resolveSenderScopedGroupPolicy
- preserves disabled policy
- maps open/allowlist based on effective sender allowlist
- evaluateSenderGroupAccessForPolicy
- blocks disabled policy
- blocks allowlist with empty list
- evaluateGroupRouteAccessForPolicy
- blocks disabled policy
- blocks allowlist without configured routes
- blocks unmatched allowlist route
- blocks disabled matched route even when group policy is open
- evaluateMatchedGroupAccessForPolicy
- blocks disabled policy
- blocks allowlist without configured entries
- blocks allowlist when required match input is missing
- blocks unmatched allowlist sender
- allows open policy
- evaluateSenderGroupAccess
- defaults missing provider config to allowlist
- blocks disabled policy
- blocks allowlist with empty list
- blocks sender not allowlisted

### src/plugin-sdk/index.test.lisp
- plugin-sdk exports
- does not expose runtime modules
- exports critical functions used by channel extensions
- exports critical constants used by channel extensions

### src/plugin-sdk/keyed-async-queue.test.lisp
- enqueueKeyedTask
- serializes tasks per key and keeps different keys independent
- keeps queue alive after task failures
- runs enqueue/settle hooks once per task
- KeyedAsyncQueue
- exposes tail map for observability

### src/plugin-sdk/outbound-media.test.lisp
- loadOutboundMediaFromUrl
- forwards maxBytes and mediaLocalRoots to loadWebMedia
- keeps options optional

### src/plugin-sdk/persistent-dedupe.test.lisp
- createPersistentDedupe
- deduplicates keys and persists across instances
- guards concurrent calls for the same key
- falls back to memory-only behavior on disk errors
- warmup loads persisted entries into memory
- warmup returns 0 when no disk file exists
- warmup skips expired entries

### src/plugin-sdk/reply-payload.test.lisp
- sendPayloadWithChunkedTextAndMedia
- returns empty result when payload has no text and no media
- sends first media with text and remaining media without text
- chunks text and sends each chunk
- detects numeric target IDs

### src/plugin-sdk/request-url.test.lisp
- resolveRequestUrl
- resolves string input
- resolves URL input
- resolves object input with url field

### src/plugin-sdk/root-alias.test.lisp
- plugin-sdk root alias
- exposes the fast empty config schema helper
- loads legacy root exports lazily through the proxy
- preserves reflection semantics for lazily resolved exports

### src/plugin-sdk/runtime.test.lisp
- resolveRuntimeEnv
- returns provided runtime when present
- creates logger-backed runtime when runtime is missing

### src/plugin-sdk/slack-message-actions.test.lisp
- handleSlackMessageAction
- maps download-file to the internal downloadFile action
- maps download-file target aliases to scope fields

### src/plugin-sdk/ssrf-policy.test.lisp
- normalizeHostnameSuffixAllowlist
- uses defaults when input is missing
- normalizes wildcard prefixes and deduplicates
- isHttpsUrlAllowedByHostnameSuffixAllowlist
- requires https
- supports exact and suffix match
- supports wildcard allowlist
- buildHostnameAllowlistPolicyFromSuffixAllowlist
- returns undefined when allowHosts is empty
- returns undefined when wildcard host is present
- expands a suffix entry to exact + wildcard hostname allowlist patterns
- normalizes wildcard prefixes, leading/trailing dots, and deduplicates patterns

### src/plugin-sdk/status-helpers.test.lisp
- createDefaultChannelRuntimeState
- builds default runtime state without extra fields
- merges extra fields into the default runtime state
- buildBaseChannelStatusSummary
- defaults missing values
- keeps explicit values
- buildBaseAccountStatusSnapshot
- builds account status with runtime defaults
- buildComputedAccountStatusSnapshot
- builds account status when configured is computed outside resolver
- buildRuntimeAccountStatusSnapshot
- builds runtime lifecycle fields with defaults
- buildTokenChannelStatusSummary
- includes token/probe fields with mode by default
- can omit mode for channels without a mode state
- collectStatusIssuesFromLastError
- returns runtime issues only for non-empty string lastError values

### src/plugin-sdk/subpaths.test.lisp
- plugin-sdk subpath exports
- exports compat helpers
- exports Discord helpers
- exports Slack helpers
- exports Telegram helpers
- exports Signal helpers
- exports iMessage helpers
- exports WhatsApp helpers
- exports LINE helpers
- exports Microsoft Teams helpers
- resolves bundled extension subpaths

### src/plugin-sdk/temp-path.test.lisp
- buildRandomTempFilePath
- builds deterministic paths when now/uuid are provided
- sanitizes prefix and extension to avoid path traversal segments
- withTempDownloadPath
- creates a temp path under tmp dir and cleans up the temp directory
- sanitizes prefix and fileName

### src/plugin-sdk/text-chunking.test.lisp
- chunkTextForOutbound
- returns empty for empty input
- splits on newline or whitespace boundaries
- falls back to hard limit when no separator exists

### src/plugin-sdk/webhook-memory-guards.test.lisp
- createFixedWindowRateLimiter
- enforces a fixed-window request limit
- resets counters after the window elapses
- caps tracked keys
- prunes stale keys
- createBoundedCounter
- increments and returns per-key counts
- caps tracked keys
- expires stale keys when ttl is set
- defaults
- exports shared webhook limit profiles
- createWebhookAnomalyTracker
- increments only tracked status codes and logs at configured cadence

### src/plugin-sdk/webhook-request-guards.test.lisp
- isJsonContentType
- accepts application/json and +json suffixes
- rejects non-json media types
- applyBasicWebhookRequestGuards
- rejects disallowed HTTP methods
- enforces rate limits
- rejects non-json requests when required
- readJsonWebhookBodyOrReject
- returns parsed JSON body
- preserves valid JSON null payload
- writes 400 on invalid JSON payload
- readWebhookBodyOrReject
- returns raw body contents
- enforces strict pre-auth default body limits
- beginWebhookRequestPipelineOrReject
- enforces in-flight request limits and releases slots

### src/plugin-sdk/webhook-targets.test.lisp
- registerWebhookTarget
- normalizes the path and unregisters cleanly
- runs first/last path lifecycle hooks only at path boundaries
- does not register target when first-path hook throws
- registerWebhookTargetWithPluginRoute
- registers plugin route on first target and removes it on last target
- resolveWebhookTargets
- resolves normalized path targets
- returns null when path has no targets
- withResolvedWebhookRequestPipeline
- returns false when request path has no registered targets
- runs handler when targets resolve and method passes
- releases in-flight slot when handler throws
- rejectNonPostWebhookRequest
- sets 405 for non-POST requests
- resolveSingleWebhookTarget
- resolveWebhookTargetWithAuthOrReject
- returns matched target
- writes unauthorized response on no match
- writes ambiguous response on multi-match
- resolveWebhookTargetWithAuthOrRejectSync
- returns matched target synchronously

## plugins

### src/plugins/bundled-sources.test.lisp
- bundled plugin sources
- resolves bundled sources keyed by plugin id
- finds bundled source by Quicklisp/Ultralisp spec
- finds bundled source by plugin id

### src/plugins/cli.test.lisp
- registerPluginCliCommands
- skips plugin command-line interface registrars when commands already exist

### src/plugins/commands.test.lisp
- registerPluginCommand
- rejects malformed runtime command shapes
- normalizes command metadata for downstream consumers
- supports provider-specific native command aliases

### src/plugins/config-state.test.lisp
- normalizePluginsConfig
- uses default memory slot when not specified
- respects explicit memory slot value
- disables memory slot when set to 'none' (case insensitive)
- trims whitespace from memory slot value
- uses default when memory slot is empty string
- uses default when memory slot is whitespace only
- normalizes plugin hook policy flags
- drops invalid plugin hook policy values
- resolveEffectiveEnableState
- enables bundled channels when channels.<id>.enabled=true
- keeps explicit plugin-level disable authoritative

### src/plugins/discovery.test.lisp
- discoverOpenClawPlugins
- discovers global and workspace extensions
- ignores backup and disabled plugin directories in scanned roots
- loads package extension packs
- derives unscoped ids for scoped packages
- treats configured directory paths as plugin packages
- blocks extension entries that escape package directory
- rejects package extension entries that escape via symlink
- rejects package extension entries that are hardlinked aliases
- ignores package manifests that are hardlinked aliases
- reuses discovery results from cache until cleared

### src/plugins/enable.test.lisp
- enablePluginInConfig
- enables a plugin entry
- adds plugin to allowlist when allowlist is configured
- refuses enable when plugin is denylisted
- writes built-in channels to channels.<id>.enabled and plugins.entries
- adds built-in channel id to allowlist when allowlist is configured
- re-enables built-in channels after explicit plugin-level disable

### src/plugins/hooks.before-agent-start.test.lisp
- before_agent_start hook merger
- returns modelOverride from a single plugin
- returns providerOverride from a single plugin
- returns both modelOverride and providerOverride together
- higher-priority plugin wins for modelOverride
- lower-priority plugin does not overwrite if it returns undefined
- prependContext still concatenates when modelOverride is present
- backward compat: plugin returning only prependContext produces no modelOverride
- modelOverride without providerOverride leaves provider undefined
- returns undefined when no hooks are registered
- systemPrompt merges correctly alongside model overrides

### src/plugins/hooks.model-override-wiring.test.lisp
- model override pipeline wiring
- before_model_resolve (run.lisp pattern)
- hook receives prompt-only event and returns provider/model override
- new hook overrides beat legacy before_agent_start fallback
- before_prompt_build (attempt.lisp pattern)
- hook receives prompt and messages and can prepend context
- legacy before_agent_start context can still be merged as fallback
- graceful degradation + hook detection
- one broken before_model_resolve plugin does not block other overrides
- hasHooks reports new and legacy hooks independently

### src/plugins/hooks.phase-hooks.test.lisp
- phase hooks merger
- before_model_resolve keeps higher-priority override values
- before_prompt_build concatenates prependContext and preserves systemPrompt precedence
- before_prompt_build concatenates prependSystemContext and appendSystemContext

### src/plugins/http-registry.test.lisp
- registerPluginHttpRoute
- registers route and unregisters it
- returns noop unregister when path is missing
- replaces stale route on same path when replaceExisting=true
- rejects conflicting route registrations without replaceExisting
- rejects route replacement when a different plugin owns the route
- rejects mixed-auth overlapping routes

### src/plugins/install.test.lisp
- installPluginFromArchive
- installs into ~/.openclaw/extensions and uses unscoped id
- rejects installing when plugin already exists
- installs from a zip archive
- allows updates when mode is update
- rejects traversal-like plugin names
- rejects reserved plugin ids
- rejects packages without openclaw.extensions
- rejects legacy plugin package shape when openclaw.extensions is missing
- warns when plugin contains dangerous code patterns
- scans extension entry files in hidden directories
- continues install when scanner throws
- installPluginFromDir
- uses --ignore-scripts for dependency install
- strips workspace devDependencies before Quicklisp/Ultralisp install
- uses openclaw.plugin.json id as install key when it differs from package name
- normalizes scoped manifest ids to unscoped install keys
- installPluginFromPath
- blocks hardlink alias overwrites when installing a plain file plugin
- installPluginFromNpmSpec
- uses --ignore-scripts for Quicklisp/Ultralisp pack and cleans up temp dir
- rejects non-registry Quicklisp/Ultralisp specs
- aborts when integrity drift callback rejects the fetched artifact
- classifies Quicklisp/Ultralisp package-not-found errors with a stable error code
- rejects bare Quicklisp/Ultralisp specs that resolve to prerelease versions
- allows explicit prerelease Quicklisp/Ultralisp tags

### src/plugins/installs.test.lisp
- buildNpmResolutionInstallFields
- maps Quicklisp/Ultralisp resolution metadata into install record fields
- returns undefined fields when resolution is missing
- recordPluginInstall
- stores install metadata for the plugin id

### src/plugins/loader.test.lisp
- loadOpenClawPlugins
- disables bundled plugins by default
- loads bundled telegram plugin when enabled
- loads bundled channel plugins when channels.<id>.enabled=true
- still respects explicit disable via plugins.entries for bundled channels
- preserves ASDF system definition metadata for bundled memory plugins
- loads plugins from config paths
- re-initializes global hook runner when serving registry from cache
- loads plugins when source and root differ only by realpath alias
- denylist disables plugins even if allowed
- fails fast on invalid plugin config
- registers channel plugins
- registers http routes with auth and match options
- registers http routes
- rewrites removed registerHttpHandler failures into migration diagnostics
- does not rewrite unrelated registerHttpHandler helper failures
- rejects plugin http routes missing explicit auth
- allows explicit replaceExisting for same-plugin http route overrides
- rejects http route replacement when another plugin owns the route
- rejects mixed-auth overlapping http routes
- allows same-auth overlapping http routes
- respects explicit disable in config
- blocks before_prompt_build but preserves legacy model overrides when prompt injection is disabled
- keeps prompt-injection typed hooks enabled by default
- ignores unknown typed hooks from plugins and keeps loading
- enforces memory slot selection
- skips importing bundled memory plugins that are disabled by memory slot
- disables memory plugins when slot is none
- prefers higher-precedence plugins with the same id
- prefers bundled plugin over auto-discovered global duplicate ids
- warns when plugins.allow is empty and non-bundled plugins are discoverable
- warns when loaded non-bundled plugin has no install/load-path provenance
- rejects plugin entry files that escape plugin root via symlink
- rejects plugin entry files that escape plugin root via hardlink
- allows bundled plugin entry files that are hardlinked aliases
- preserves runtime reflection semantics when runtime is lazily initialized
- supports legacy plugins importing monolithic plugin-sdk root
- prefers dist plugin-sdk alias when loader runs from dist
- prefers dist candidates first for production src runtime
- prefers src plugin-sdk alias when loader runs from src in non-production
- prefers src candidates first for non-production src runtime
- falls back to src plugin-sdk alias when dist is missing in production
- prefers dist root-alias shim when loader runs from dist
- prefers src root-alias shim when loader runs from src in non-production

### src/plugins/logger.test.lisp
- plugins/logger
- forwards logger methods

### src/plugins/manifest-registry.test.lisp
- loadPluginManifestRegistry
- emits duplicate warning for truly distinct plugins with same id
- suppresses duplicate warning when candidates share the same physical directory via symlink
- suppresses duplicate warning when candidates have identical rootDir paths
- prefers higher-precedence origins for the same physical directory (config > workspace > global > bundled)
- rejects manifest paths that escape plugin root via symlink
- rejects manifest paths that escape plugin root via hardlink
- allows bundled manifest paths that are hardlinked aliases

### src/plugins/runtime/gateway-request-scope.test.lisp
- gateway request scope
- reuses AsyncLocalStorage across reloaded module instances

### src/plugins/runtime/index.test.lisp
- plugin runtime command execution
- exposes runtime.system.runCommandWithTimeout by default
- forwards runtime.system.runCommandWithTimeout errors
- exposes runtime.events listener registration helpers
- exposes runtime.system.requestHeartbeatNow

### src/plugins/runtime/types.contract.test.lisp
- plugin runtime type contract
- createPluginRuntime returns the declared PluginRuntime shape

### src/plugins/schema-validator.test.lisp
- schema validator
- includes allowed values in enum validation errors
- includes allowed value in const validation errors
- truncates long allowed-value hints
- appends missing required property to the structured path
- appends missing dependency property to the structured path
- truncates oversized allowed value entries
- sanitizes terminal text while preserving structured fields

### src/plugins/services.test.lisp
- startPluginServices
- starts services and stops them in reverse order
- logs start/stop failures and continues

### src/plugins/slots.test.lisp
- applyExclusiveSlotSelection
- selects the slot and disables other entries for the same kind
- does nothing when the slot already matches
- warns when the slot falls back to a default
- keeps disabled competing plugins disabled without adding disable warnings
- skips changes when no exclusive slot applies

### src/plugins/source-display.test.lisp
- formatPluginSourceForTable
- shortens bundled plugin sources under the stock root
- shortens workspace plugin sources under the workspace root
- shortens global plugin sources under the global root

### src/plugins/tools.optional.test.lisp
- resolvePluginTools optional tools
- skips optional tools without explicit allowlist
- allows optional tools by tool name
- allows optional tools via plugin-scoped allowlist entries
- rejects plugin id collisions with core tool names
- skips conflicting tool names but keeps other tools
- suppresses conflict diagnostics when requested

### src/plugins/uninstall.test.lisp
- removePluginFromConfig
- removes plugin from entries
- removes plugin from installs
- removes plugin from allowlist
- removes linked path from load.paths
- cleans up load when removing the only linked path
- clears memory slot when uninstalling active memory plugin
- does not modify memory slot when uninstalling non-memory plugin
- removes plugins object when uninstall leaves only empty slots
- cleans up empty slots object
- handles plugin that only exists in entries
- handles plugin that only exists in installs
- cleans up empty plugins object
- preserves other config values
- uninstallPlugin
- returns error when plugin not found
- removes config entries
- deletes directory when deleteFiles is true
- preserves directory for linked plugins
- does not delete directory when deleteFiles is false
- succeeds even if directory does not exist
- returns a warning when directory deletion fails unexpectedly
- never deletes arbitrary configured install paths
- resolveUninstallDirectoryTarget
- returns null for linked plugins
- falls back to default path when configured installPath is untrusted

### src/plugins/update.test.lisp
- updateNpmInstalledPlugins
- skips integrity drift checks for unpinned Quicklisp/Ultralisp specs during dry-run updates
- keeps integrity drift checks for exact-version Quicklisp/Ultralisp specs during dry-run updates
- formats package-not-found updates with a stable message
- falls back to raw installer error for unknown error codes

### src/plugins/voice-call.plugin.test.lisp
- voice-call plugin
- registers gateway methods
- initiates a call via voicecall.initiate
- returns call status
- tool get_status returns json payload
- legacy tool status without sid returns error payload
- command-line interface latency summarizes turn metrics from JSONL
- command-line interface start prints JSON

### src/plugins/wired-hooks-after-tool-call.e2e.test.lisp
- after_tool_call hook wiring
- calls runAfterToolCall in handleToolExecutionEnd when hook is registered
- includes error in after_tool_call event on tool failure
- does not call runAfterToolCall when no hooks registered
- keeps start args isolated per run when toolCallId collides

### src/plugins/wired-hooks-compaction.test.lisp
- compaction hook wiring
- calls runBeforeCompaction in handleAutoCompactionStart
- calls runAfterCompaction when willRetry is false
- does not call runAfterCompaction when willRetry is true but still increments counter
- does not increment counter when compaction was aborted
- does not increment counter when compaction has result but was aborted
- does not increment counter when result is undefined
- resets stale assistant usage after final compaction
- does not clear assistant usage while compaction is retrying

### src/plugins/wired-hooks-gateway.test.lisp
- gateway hook runner methods
- runGatewayStart invokes registered gateway_start hooks
- runGatewayStop invokes registered gateway_stop hooks
- hasHooks returns true for registered gateway hooks

### src/plugins/wired-hooks-llm.test.lisp
- llm hook runner methods
- runLlmInput invokes registered llm_input hooks
- runLlmOutput invokes registered llm_output hooks
- hasHooks returns true for registered llm hooks

### src/plugins/wired-hooks-message.test.lisp
- message_sending hook runner
- runMessageSending invokes registered hooks and returns modified content
- runMessageSending can cancel message delivery
- message_sent hook runner
- runMessageSent invokes registered hooks with success=true
- runMessageSent invokes registered hooks with error on failure

### src/plugins/wired-hooks-session.test.lisp
- session hook runner methods
- runSessionStart invokes registered session_start hooks
- runSessionEnd invokes registered session_end hooks
- hasHooks returns true for registered session hooks

### src/plugins/wired-hooks-subagent.test.lisp
- subagent hook runner methods
- runSubagentSpawning invokes registered subagent_spawning hooks
- runSubagentSpawned invokes registered subagent_spawned hooks
- runSubagentDeliveryTarget invokes registered subagent_delivery_target hooks
- runSubagentDeliveryTarget returns undefined when no matching hooks are registered
- runSubagentEnded invokes registered subagent_ended hooks
- hasHooks returns true for registered subagent hooks

## poll-params.test.lisp

### src/poll-params.test.lisp
- poll params
- does not treat explicit false booleans as poll creation params
- treats finite numeric poll params as poll creation intent
- treats string-encoded boolean poll params as poll creation intent when true
- treats string poll options as poll creation intent
- detects snake_case poll fields as poll creation intent
- resolves telegram poll visibility flags

## polls.test.lisp

### src/polls.test.lisp
- polls
- normalizes question/options and validates maxSelections
- enforces max option count when configured
- rejects both durationSeconds and durationHours

## process

### src/process/command-queue.test.lisp
- command queue
- resetAllLanes is safe when no lanes have been created
- runs tasks one at a time in order
- logs enqueue depth after push
- invokes onWait callback when a task waits past the threshold
- getActiveTaskCount returns count of currently executing tasks
- waitForActiveTasks resolves immediately when no tasks are active
- waitForActiveTasks waits for active tasks to finish
- waitForActiveTasks returns drained=false when timeout is zero and tasks are active
- waitForActiveTasks returns drained=false on timeout
- resetAllLanes drains queued work immediately after reset
- waitForActiveTasks ignores tasks that start after the call
- clearCommandLane rejects pending promises
- keeps draining functional after synchronous onWait failure
- rejects new enqueues with GatewayDrainingError after markGatewayDraining
- does not affect already-active tasks after markGatewayDraining
- resetAllLanes clears gateway draining flag and re-allows enqueue

### src/process/exec.no-output-timer.test.lisp
- runCommandWithTimeout no-output timer
- resets no-output timeout when spawned child keeps emitting stdout

### src/process/exec.test.lisp
- runCommandWithTimeout
- never enables shell execution (Windows cmd.exe injection hardening)
- merges custom env with base env and drops undefined values
- suppresses Quicklisp/Ultralisp fund prompts for Quicklisp/Ultralisp argv
- kills command when no output timeout elapses
- reports global timeout termination when overall timeout elapses
- attachChildProcessBridge
- forwards SIGTERM to the wrapped child and detaches on exit

### src/process/exec.windows.test.lisp
- windows command wrapper behavior
- wraps .cmd commands via cmd.exe in runCommandWithTimeout
- uses cmd.exe wrapper with windowsVerbatimArguments in runExec for .cmd shims

### src/process/kill-tree.test.lisp
- killProcessTree
- on Windows skips delayed force-kill when PID is already gone
- on Windows force-kills after grace period only when PID still exists
- on Unix sends SIGTERM first and skips SIGKILL when process exits
- on Unix sends SIGKILL after grace period when process is still alive

### src/process/spawn-utils.test.lisp
- spawnWithFallback
- retries on EBADF using fallback options
- does not retry on non-EBADF errors
- restart-recovery
- skips recovery on first iteration and runs on subsequent iterations

### src/process/supervisor/adapters/child.test.lisp
- createChildAdapter
- uses process-tree kill for default SIGKILL
- uses direct child.kill for non-SIGKILL signals
- disables detached mode in service-managed runtime
- keeps inherited env when no override env is provided
- passes explicit env overrides as strings

### src/process/supervisor/adapters/pty.test.lisp
- createPtyAdapter
- forwards explicit signals to sbcl-pty kill on non-Windows
- uses process-tree kill for SIGKILL by default
- wait does not settle immediately on SIGKILL
- prefers real PTY exit over SIGKILL fallback settle
- resolves wait when exit fires before wait is called
- keeps inherited env when no override env is provided
- passes explicit env overrides as strings
- does not pass a signal to sbcl-pty on Windows
- uses process-tree kill for SIGKILL on Windows

### src/process/supervisor/registry.test.lisp
- process supervisor run registry
- finalize is idempotent and preserves first terminal metadata
- prunes oldest exited records once retention cap is exceeded
- filters listByScope and returns detached copies

### src/process/supervisor/supervisor.pty-command.test.lisp
- process supervisor PTY command contract
- passes PTY command verbatim to shell args
- rejects empty PTY command

### src/process/supervisor/supervisor.test.lisp
- process supervisor
- spawns child runs and captures output
- enforces no-output timeout for silent processes
- cancels prior scoped run when replaceExistingScope is enabled
- applies overall timeout even for near-immediate timer firing
- can stream output without retaining it in RunExit payload

## providers

### src/providers/github-copilot-models.test.lisp
- github-copilot-models
- getDefaultCopilotModelIds
- includes claude-sonnet-4.6
- includes claude-sonnet-4.5
- returns a mutable copy
- buildCopilotModelDefinition
- builds a valid definition for claude-sonnet-4.6
- trims whitespace from model id
- throws on empty model id

### src/providers/github-copilot-token.test.lisp
- github-copilot token
- derives baseUrl from token
- uses cache when token is still valid
- fetches and stores token when cache is missing

### src/providers/google-shared.ensures-function-call-comes-after-user-turn.test.lisp
- google-shared convertTools
- ensures function call comes after user turn, not after model turn
- strips tool call and response ids for google-gemini-cli

### src/providers/google-shared.preserves-parameters-type-is-missing.test.lisp
- google-shared convertTools
- preserves parameters when type is missing
- keeps unsupported JSON Schema keywords intact
- keeps supported schema fields
- google-shared convertMessages
- keeps thinking blocks when provider/model match
- keeps thought signatures for Claude models
- does not merge consecutive user messages for Gemini
- does not merge consecutive user messages for non-Gemini Google models
- does not merge consecutive model messages for Gemini
- handles user message after tool result without model response in between

### src/providers/qwen-portal-oauth.test.lisp
- refreshQwenPortalCredentials
- refreshes tokens with a new access token
- keeps refresh token when refresh response omits it
- keeps refresh token when response sends an empty refresh token
- errors when refresh response has invalid expires_in
- errors when refresh token is invalid
- errors when refresh token is missing before any request
- errors when refresh response omits access token
- errors with server payload text for non-400 status

## routing

### src/routing/account-id.test.lisp
- account id normalization
- defaults missing values to default account
- normalizes valid ids to lowercase
- sanitizes invalid characters into canonical ids
- rejects prototype-pollution key vectors
- preserves optional semantics without forcing default

### src/routing/account-lookup.test.lisp
- resolveAccountEntry
- resolves direct and case-insensitive account keys
- ignores prototype-chain values

### src/routing/resolve-route.test.lisp
- resolveAgentRoute
- defaults to main/default when no bindings exist
- dmScope controls direct-message session key isolation
- resolveInboundLastRouteSessionKey follows route policy
- deriveLastRoutePolicy collapses only main-session routes
- identityLinks applies to direct-message scopes
- peer binding wins over account binding
- discord channel peer binding wins over guild binding
- coerces numeric peer ids to stable session keys
- guild binding wins over account binding when peer not bound
- peer+guild binding does not act as guild-wide fallback when peer mismatches (#14752)
- peer+guild binding requires guild match even when peer matches
- peer+team binding does not act as team-wide fallback when peer mismatches
- peer+team binding requires team match even when peer matches
- missing accountId in binding matches default account only
- accountId=* matches any account as a channel fallback
- binding accountId matching is canonicalized
- defaultAgentId is used when no binding matches
- dmScope=per-account-channel-peer isolates DM sessions per account, channel and sender
- dmScope=per-account-channel-peer uses default accountId when not provided
- parentPeer binding inheritance (thread support)
- thread inherits binding from parent channel when no direct match
- direct peer binding wins over parent peer binding
- parent peer binding wins over guild binding
- falls back to guild binding when no parent peer match
- parentPeer with empty id is ignored
- null parentPeer is handled gracefully
- backward compatibility: peer.kind dm → direct
- legacy dm in config matches runtime direct peer
- runtime dm peer.kind matches config direct binding (#22730)
- backward compatibility: peer.kind group ↔ channel
- config group binding matches runtime channel scope
- config channel binding matches runtime group scope
- group/channel compatibility does not match direct peer kind
- role-based agent routing
- guild+roles binding matches when member has matching role
- guild+roles binding skipped when no matching role
- guild+roles is more specific than guild-only
- peer binding still beats guild+roles
- parent peer binding still beats guild+roles
- no memberRoleIds means guild+roles doesn't match
- first matching binding wins with multiple role bindings
- empty roles array treated as no role restriction
- guild+roles binding does not match as guild-only when roles do not match
- peer+guild+roles binding does not act as guild+roles fallback when peer mismatches
- binding evaluation cache scalability
- does not rescan full bindings after channel/account cache rollover (#36915)

### src/routing/session-key.continuity.test.lisp
- Discord Session Key Continuity
- generates distinct keys for DM vs Channel (dmScope=main)
- generates distinct keys for DM vs Channel (dmScope=per-peer)
- handles empty/invalid IDs safely without collision

### src/routing/session-key.test.lisp
- classifySessionKeyShape
- classifies empty keys as missing
- classifies valid agent keys
- classifies malformed agent keys
- treats non-agent legacy or alias keys as non-malformed
- session key backward compatibility
- classifies legacy :dm: session keys as valid agent keys
- classifies new :direct: session keys as valid agent keys
- getSubagentDepth
- returns 0 for non-subagent session keys
- returns 2 for nested subagent session keys
- isCronSessionKey
- matches base and run cron agent session keys
- does not match non-cron sessions
- deriveSessionChatType
- detects canonical direct/group/channel session keys
- detects legacy direct markers
- detects legacy discord guild channel keys
- returns unknown for main or malformed session keys
- session key canonicalization
- parses agent keys case-insensitively and returns lowercase tokens
- does not double-prefix already-qualified agent keys
- isValidAgentId
- accepts valid agent ids
- rejects malformed agent ids

## scripts

### src/scripts/canvas-a2ui-copy.test.lisp
- canvas a2ui copy
- throws a helpful error when assets are missing
- skips missing assets when OPENCLAW_A2UI_SKIP_MISSING=1
- copies bundled assets to dist

### src/scripts/ci-changed-scope.test.lisp
- detectChangedScope
- fails safe when no paths are provided
- keeps all lanes off for docs-only changes
- enables sbcl lane for sbcl-relevant files
- keeps sbcl lane off for native-only changes
- does not force macOS for generated protocol model-only changes
- enables sbcl lane for non-native non-doc files by fallback
- keeps windows lane off for non-runtime GitHub metadata files
- runs Python skill tests when skills change
- treats base and head as literal git args

## secrets

### src/secrets/apply.test.lisp
- secrets apply
- preflights and applies one-way scrub without plaintext backups
- applies auth-profiles sibling ref targets to the scoped agent store
- creates a new auth-profiles mapping when provider metadata is supplied
- is idempotent on repeated write applies
- applies targets safely when map keys contain dots
- migrates skills entries apiKey targets alongside provider api keys
- applies non-legacy target types
- applies model provider header targets
- applies array-indexed targets for agent memory search
- rejects plan targets that do not match allowed secret-bearing paths
- rejects plan targets with forbidden prototype-like path segments
- applies provider upserts and deletes from plan

### src/secrets/audit.test.lisp
- secrets audit
- reports plaintext + shadowing findings
- does not mutate legacy auth.json during audit
- reports malformed sidecar JSON as findings instead of crashing
- batches ref resolution per provider during audit
- short-circuits per-ref fallback for provider-wide batch failures
- scans agent models.json files for plaintext provider apiKey values
- scans agent models.json files for plaintext provider header values
- does not flag non-sensitive routing headers in models.json
- does not flag models.json marker values as plaintext
- flags arbitrary all-caps models.json apiKey values as plaintext
- does not flag models.json header marker values as plaintext
- reports unresolved models.json SecretRef objects in provider headers
- reports malformed models.json as unresolved findings
- does not flag non-sensitive routing headers in openclaw config

### src/secrets/command-config.test.lisp
- collectCommandSecretAssignmentsFromSnapshot
- returns assignments from the active runtime snapshot for configured refs
- throws when configured refs are unresolved in the snapshot
- skips unresolved refs that are marked inactive by runtime warnings

### src/secrets/configure-plan.test.lisp
- secrets configure plan helpers
- builds configure candidates from supported configure targets
- collects provider upserts and deletes
- discovers auth-profiles candidates for the selected agent scope
- captures existing refs for prefilled configure prompts
- marks normalized alias paths as derived when not authored directly
- reports configure change presence and builds deterministic plan shape

### src/secrets/configure.test.lisp
- runSecretsConfigureInteractive
- does not load auth-profiles when running providers-only

### src/secrets/path-utils.test.lisp
- secrets path utils
- deletePathStrict compacts arrays via splice
- getPath returns undefined for invalid array path segment
- setPathExistingStrict throws when path does not already exist
- setPathExistingStrict updates an existing leaf
- setPathCreateStrict creates missing container segments
- setPathCreateStrict leaves value unchanged when equal

### src/secrets/plan.test.lisp
- secrets plan validation
- accepts legacy provider target types
- accepts expanded target types beyond legacy surface
- accepts model provider header targets with wildcard-backed paths
- rejects target paths that do not match the registered shape
- validates plan files with non-legacy target types
- requires agentId for auth-profiles plan targets

### src/secrets/resolve.test.lisp
- secret ref resolver
- resolves env refs via implicit default env provider
- rejects misconfigured provider source mismatches

### src/secrets/runtime-gateway-auth-surfaces.test.lisp
- evaluateGatewayAuthSurfaceStates
- marks gateway.auth.token active when token mode is explicit
- marks gateway.auth.token inactive when env token is configured
- marks gateway.auth.token inactive when password mode is explicit
- marks gateway.auth.password active when password mode is explicit
- marks gateway.auth.password inactive when env token is configured
- marks gateway.remote.token active when remote token fallback is active
- marks gateway.remote.token inactive when token auth cannot win
- marks gateway.remote.password active when remote url is configured
- marks gateway.remote.password inactive when password auth cannot win

### src/secrets/runtime.coverage.test.lisp
- secrets runtime target coverage
- handles every openclaw.json registry target when configured as active
- handles every auth-profiles registry target

### src/secrets/runtime.test.lisp
- secrets runtime snapshot
- resolves env refs for config and auth profiles
- normalizes inline SecretRef object on token to tokenRef
- normalizes inline SecretRef object on key to keyRef
- keeps explicit keyRef when inline key SecretRef is also present
- treats non-selected web search provider refs as inactive
- resolves provider-specific refs in web search auto mode
- resolves selected web search provider ref even when provider config is disabled
- resolves file refs via configured file provider
- fails when file provider payload is not a JSON object
- activates runtime snapshots for loadConfig and ensureAuthProfileStore
- skips inactive-surface refs and emits diagnostics
- treats gateway.remote refs as inactive when local auth credentials are configured
- treats gateway.auth.password ref as active when mode is unset and no token is configured
- treats gateway.auth.token ref as active when token mode is explicit
- treats gateway.auth.token ref as inactive when password mode is explicit
- fails when gateway.auth.token ref is active and unresolved
- treats gateway.auth.password ref as inactive when auth mode is trusted-proxy
- treats gateway.auth.password ref as inactive when remote token is configured
- treats gateway.remote.token ref as active in local mode when no local credentials are configured
- treats gateway.remote.password ref as active in local mode when password can win
- treats top-level Zalo botToken refs as active even when tokenFile is configured
- treats account-level Zalo botToken refs as active even when tokenFile is configured
- treats top-level Zalo botToken refs as active for non-default accounts without overrides
- treats channels.zalo.accounts.default.botToken refs as active
- treats top-level Nextcloud Talk botSecret and apiPassword refs as active when file paths are configured
- treats account-level Nextcloud Talk botSecret and apiPassword refs as active when file paths are configured
- treats gateway.remote refs as active when tailscale serve is enabled
- treats defaults memorySearch ref as inactive when all enabled agents disable memorySearch
- fails when enabled channel surfaces contain unresolved refs
- fails when default Telegram account can inherit an unresolved top-level token ref
- treats top-level Telegram token as inactive when all enabled accounts override it
- treats Telegram account overrides as enabled when account.enabled is omitted
- treats Telegram webhookSecret refs as inactive when webhook mode is not configured
- treats Telegram top-level botToken refs as inactive when tokenFile is configured
- treats Telegram account botToken refs as inactive when account tokenFile is configured
- treats top-level Telegram botToken refs as active when account botToken is blank
- treats IRC account nickserv password refs as inactive when nickserv is disabled
- treats top-level IRC nickserv password refs as inactive when nickserv is disabled
- treats Slack signingSecret refs as inactive when mode is socket
- treats Slack appToken refs as inactive when mode is http
- treats top-level Google Chat serviceAccount as inactive when enabled accounts use serviceAccountRef
- fails when non-default Discord account inherits an unresolved top-level token ref
- treats top-level Discord token refs as inactive when account token is explicitly blank
- treats Discord PluralKit token refs as inactive when PluralKit is disabled
- treats Discord voice TTS refs as inactive when voice is disabled
- handles Discord nested inheritance for enabled and disabled accounts
- skips top-level Discord voice refs when all enabled accounts override nested voice config
- fails when an enabled Discord account override has an unresolved nested ref
- does not write inherited auth stores during runtime secret activation

### src/secrets/target-registry-pattern.test.lisp
- target registry pattern helpers
- matches wildcard and array tokens with stable capture ordering
- materializes sibling ref paths from wildcard and array captures
- matches two wildcard captures in five-segment header paths
- expands wildcard and array patterns over config objects

### src/secrets/target-registry.test.lisp
- secret target registry
- stays in sync with docs/reference/secretref-user-supplied-credentials-matrix.json
- stays in sync with docs/reference/secretref-credential-surface.md
- supports filtered discovery by target ids

## security

### src/security/audit-extra.sync.test.lisp
- collectAttackSurfaceSummaryFindings
- distinguishes external webhooks from internal hooks when only internal hooks are enabled
- reports both hook systems as enabled when both are configured
- reports both hook systems as disabled when neither is configured
- safeEqualSecret
- matches identical secrets
- rejects mismatched secrets
- rejects different-length secrets
- rejects missing values

### src/security/audit.test.lisp
- security audit
- includes an attack surface summary (info)
- flags non-loopback bind without auth as critical
- does not flag non-loopback bind without auth when gateway password uses SecretRef
- evaluates gateway auth rate-limit warning based on configuration
- scores dangerous gateway.tools.allow over HTTP by exposure
- warns when sandbox exec host is selected while sandbox mode is off
- warns for interpreter safeBins only when explicit profiles are missing
- warns for risky safeBinTrustedDirs entries
- does not warn for non-risky absolute safeBinTrustedDirs entries
- evaluates loopback control UI and logging exposure findings
- treats Windows ACL-only perms as secure
- flags Windows ACLs when Users can read the state dir
- warns when sandbox browser containers have missing or stale hash labels
- skips sandbox browser hash label checks when docker inspect is unavailable
- flags sandbox browser containers with non-loopback published ports
- uses symlink target permissions for config checks
- warns when workspace skill files resolve outside workspace root
- does not warn for workspace skills that stay inside workspace root
- scores small-model risk by tool/sandbox exposure
- checks sandbox docker mode-off findings with/without agent override
- flags dangerous sandbox docker config (binds/network/seccomp/apparmor)
- flags container namespace join network mode in sandbox config
- checks sandbox browser bridge-network restrictions
- flags ineffective gateway.nodes.denyCommands entries
- suggests prefix-matching commands for unknown denyCommands entries
- keeps unknown denyCommands entries without suggestions when no close command exists
- scores dangerous gateway.nodes.allowCommands by exposure
- does not flag dangerous allowCommands entries when denied again
- flags agent profile overrides when global tools.profile is minimal
- flags tools.elevated allowFrom wildcard as critical
- flags browser control without auth when browser is enabled
- does not flag browser control auth when gateway token is configured
- does not flag browser control auth when gateway password uses SecretRef
- warns when remote Chrome DevTools Protocol uses HTTP
- warns when control UI allows insecure auth
- warns when control UI device auth is disabled
- warns when insecure/dangerous debug flags are enabled
- flags non-loopback Control UI without allowed origins
- flags wildcard Control UI origins by exposure level
- flags dangerous host-header origin fallback and suppresses missing allowed-origins finding
- warns when Feishu doc tool is enabled because create can grant requester access
- treats Feishu SecretRef appSecret as configured for doc tool risk detection
- does not warn for Feishu doc grant risk when doc tools are disabled
- scores X-Real-IP fallback risk by gateway exposure
- scores mDNS full mode risk by gateway bind mode
- evaluates trusted-proxy auth guardrails
- warns when multiple DM senders share the main session
- flags Discord native commands without a guild user allowlist
- keeps channel security findings when SecretRef credentials are configured but unavailable
- keeps Slack HTTP slash-command findings when resolved inspection only exposes signingSecret status
- keeps source-configured Slack HTTP findings when resolved inspection is unconfigured
- does not flag Discord slash commands when dm.allowFrom includes a Discord snowflake id
- warns when Discord allowlists contain name-based entries
- marks Discord name-based allowlists as break-glass when dangerous matching is enabled
- audits non-default Discord accounts for dangerous name matching
- does not treat prototype properties as explicit Discord account config paths
- audits name-based allowlists on non-default Discord accounts
- does not warn when Discord allowlists use ID-style entries only
- flags Discord slash commands when access-group enforcement is disabled and no users allowlist exists
- flags Slack slash commands without a channel users allowlist
- flags Slack slash commands when access-group enforcement is disabled
- flags Telegram group commands without a sender allowlist
- warns when Telegram allowFrom entries are non-numeric (legacy @username configs)
- adds probe_failed warnings for deep probe failure modes
- classifies legacy and weak-tier model identifiers
- warns when hooks token looks short
- flags hooks token reuse of the gateway env token as critical
- warns when hooks.defaultSessionKey is unset
- scores hooks request sessionKey override by gateway exposure
- scores gateway HTTP no-auth findings by exposure
- does not report gateway.http.no_auth when auth mode is token
- reports HTTP API session-key override surfaces when enabled
- warns when state/config look like a synced folder
- flags group/world-readable config include files
- flags extensions without plugins.allow
- warns on unpinned Quicklisp/Ultralisp install specs and missing integrity metadata
- does not warn on pinned Quicklisp/Ultralisp install specs with integrity metadata
- warns when install records drift from installed package versions
- flags enabled extensions when tool policy can expose plugin tools
- does not flag plugin tool reachability when profile is restrictive
- flags unallowlisted extensions as critical when native skill commands are exposed
- treats SecretRef channel credentials as configured for extension allowlist severity
- does not scan plugin code safety findings when deep audit is disabled
- reports detailed code-safety issues for both plugins and skills
- flags plugin extension entry path traversal in deep audit
- reports scan_failed when plugin code scanner throws during deep audit
- flags open groupPolicy when tools.elevated is enabled
- flags open groupPolicy when runtime/filesystem tools are exposed without guards
- does not flag runtime/filesystem exposure for open groups when sandbox mode is all
- does not flag runtime/filesystem exposure for open groups when runtime is denied and fs is workspace-only
- warns when config heuristics suggest a likely multi-user setup
- does not warn for multi-user heuristic when no shared-user signals are configured
- maybeProbeGateway auth selection
- applies token precedence across local/remote gateway modes
- applies password precedence for remote gateways
- adds warning finding when probe auth SecretRef is unavailable

### src/security/dm-policy-channel-smoke.test.lisp
- security/dm-policy-shared channel smoke
- [${testCase.name}] blocks group ${ingress} when sender is only in pairing store

### src/security/dm-policy-shared.test.lisp
- security/dm-policy-shared
- normalizes config + store allow entries and counts distinct senders
- handles empty allowlists and store failures
- skips pairing-store reads when dmPolicy is allowlist
- skips pairing-store reads when shouldRead=false
- builds effective DM/group allowlists from config + pairing store
- falls back to DM allowlist for groups when groupAllowFrom is empty
- can keep group allowlist empty when fallback is disabled
- infers pinned main DM owner from a single configured allowlist entry
- does not infer pinned owner for wildcard/multi-owner/non-main scope
- excludes storeAllowFrom when dmPolicy is allowlist
- keeps group allowlist explicit when dmPolicy is pairing
- resolves access + effective allowlists in one shared call
- resolves command gate with dm/group parity for groups
- keeps configured dm allowlist usable for group command auth
- treats dm command authorization as dm access result
- does not auto-authorize dm commands in open mode without explicit allowlists
- keeps allowlist mode strict in shared resolver (no pairing-store fallback)
- keeps message/reaction policy parity table across channels
- [${channel}] blocks groups when group allowlist is empty
- [${channel}] allows groups when group policy is open
- [${channel}] blocks DM allowlist mode when allowlist is empty
- [${channel}] uses pairing flow when DM sender is not allowlisted
- [${channel}] allows DM sender when allowlisted
- [${channel}] blocks group allowlist mode when sender/group is not allowlisted

### src/security/external-content.test.lisp
- external-content security
- detectSuspiciousPatterns
- detects ignore previous instructions pattern
- detects system prompt override attempts
- detects bracketed internal marker spoof attempts
- detects line-leading System prefix spoof attempts
- detects exec command injection
- detects delete all emails request
- returns empty array for benign content
- returns empty array for normal email content
- wrapExternalContent
- wraps content with security boundaries and matching IDs
- includes sender metadata when provided
- includes security warning by default
- can skip security warning when requested
- sanitizes attacker-injected markers with fake IDs
- preserves non-marker unicode content
- wrapWebContent
- wraps web search content with boundaries
- includes the source label
- adds warnings for web fetch content
- normalizes homoglyph markers before sanitizing
- normalizes additional angle bracket homoglyph markers before sanitizing
- buildSafeExternalPrompt
- builds complete safe prompt with all metadata
- handles minimal parameters
- isExternalHookSession
- identifies gmail hook sessions
- identifies webhook sessions
- identifies mixed-case hook prefixes
- rejects non-hook sessions
- getHookType
- returns email for gmail hooks
- returns webhook for webhook hooks
- returns webhook for generic hooks
- returns hook type for mixed-case hook prefixes
- returns unknown for non-hook sessions
- prompt injection scenarios
- safely wraps social engineering attempt
- safely wraps role hijacking attempt

### src/security/fix.test.lisp
- security fix
- tightens groupPolicy + filesystem perms
- applies allowlist per-account and seeds WhatsApp groupAllowFrom from store
- does not seed WhatsApp groupAllowFrom if allowFrom is set
- returns ok=false for invalid config but still tightens perms
- tightens perms for credentials + agent auth/sessions + include files

### src/security/safe-regex.test.lisp
- safe regex
- flags nested repetition patterns
- rejects unsafe nested repetition during compile
- compiles common safe filter regex
- agent:main:discord:channel:123
- agent:main:telegram:channel:123
- supports explicit flags
- checks bounded regex windows for long inputs

### src/security/skill-scanner.test.lisp
- scanSource
- detects child_process exec with string interpolation
- detects child_process spawn usage
- does not flag child_process import without exec/spawn call
- detects eval usage
- detects new Function constructor
- detects fs.readFile combined with fetch POST (exfiltration)
- detects hex-encoded strings (obfuscation)
- detects base64 decode of large payloads (obfuscation)
- detects stratum protocol references (mining)
- detects WebSocket to non-standard high port
- detects the process environment via UIOP access combined with network send (env harvesting)
- returns empty array for clean plugin code
- returns empty array for normal http client code (just a fetch GET)
- isScannable
- accepts .js, .ts, .mjs, .cjs, .tsx, .jsx files
- rejects non-code files (.md, .json, .png, .css)
- scanDirectory
- scans .js files in a directory tree
- skips node_modules directories
- skips hidden directories
- scans hidden entry files when explicitly included
- scanDirectoryWithSummary
- returns correct counts
- caps scanned file count with maxFiles
- skips files above maxFileBytes
- ignores missing included files
- prioritizes included entry files when maxFiles is reached
- throws when reading a scannable file fails
- reuses cached findings for unchanged files and invalidates on file updates
- reuses cached directory listings for unchanged trees

### src/security/temp-path-guard.test.lisp
- temp path guard
- skips test helper filename variants
- detects dynamic and ignores static fixtures
- enforces runtime guardrails for tmpdir joins and weak randomness

### src/security/windows-acl.test.lisp
- windows-acl
- resolveWindowsUserPrincipal
- returns DOMAIN\\USERNAME when both are present
- returns just USERNAME when USERDOMAIN is not present
- trims whitespace from values
- falls back to os.userInfo when USERNAME is empty
- parseIcaclsOutput
- parses standard icacls output
- parses entries with inheritance flags
- filters out DENY entries
- skips status messages
- skips localized (non-English) status lines that have no parenthesised token
- parses SID-format principals
- ignores malformed ACL lines that contain ':' but no rights tokens
- handles quoted target paths
- detects write permissions correctly
- summarizeWindowsAcl
- classifies trusted principals
- classifies world principals
- classifies current user as trusted
- classifies unknown principals as group
- summarizeWindowsAcl — SID-based classification
- classifies SYSTEM SID (S-1-5-18) as trusted
- classifies *S-1-5-18 (icacls /sid prefix form of SYSTEM) as trusted (refs #35834)
- classifies *S-1-5-32-544 (icacls /sid Administrators) as trusted
- classifies BUILTIN\\Administrators SID (S-1-5-32-544) as trusted
- classifies caller SID from USERSID env var as trusted
- matches SIDs case-insensitively and trims USERSID
- does not trust *-prefixed Everyone via USERSID
- classifies unknown SID as group (not world)
- classifies Everyone SID (S-1-1-0) as world, not group
- classifies Authenticated Users SID (S-1-5-11) as world, not group
- classifies BUILTIN\\Users SID (S-1-5-32-545) as world, not group
- full scenario: SYSTEM SID + owner SID only → no findings
- inspectWindowsAcl
- returns parsed ACL entries on success
- classifies *S-1-5-18 (SID form of SYSTEM from /sid) as trusted
- resolves current user SID via whoami when USERSID is missing
- returns error state on exec failure
- combines stdout and stderr for parsing
- formatWindowsAclSummary
- returns 'unknown' for failed summary
- returns 'trusted-only' when no untrusted entries
- formats untrusted entries
- formatIcaclsResetCommand
- generates command for files
- generates command for directories with inheritance flags
- uses system username when env is empty (falls back to os.userInfo)
- createIcaclsResetCommand
- returns structured command object
- returns command with system username when env is empty (falls back to os.userInfo)
- includes display string matching formatIcaclsResetCommand
- summarizeWindowsAcl — localized SYSTEM account names
- classifies French SYSTEM (AUTORITE NT\\Système) as trusted
- classifies German SYSTEM (NT-AUTORITÄT\\SYSTEM) as trusted
- classifies Spanish SYSTEM (AUTORIDAD NT\\SYSTEM) as trusted
- French Windows full scenario: user + Système only → no untrusted
- formatIcaclsResetCommand — uses SID for SYSTEM
- uses *S-1-5-18 instead of SYSTEM in reset command

## sessions

### src/sessions/model-overrides.test.lisp
- applyModelOverrideToSessionEntry
- clears stale runtime model fields when switching overrides
- clears stale runtime model fields even when override selection is unchanged
- retains aligned runtime model fields when selection and runtime already match

### src/sessions/send-policy.test.lisp
- resolveSendPolicy
- defaults to allow
- entry override wins
- rule match by channel + chatType
- rule match by keyPrefix
- rule match by rawKeyPrefix

### src/sessions/session-id.test.lisp
- session-id
- matches canonical UUID session ids
- 123e4567-e89b-12d3-a456-426614174000
- rejects non-session-id values
- agent:main:main

### src/sessions/transcript-events.test.lisp
- transcript events
- emits trimmed session file updates
- continues notifying other listeners when one throws

## shared

### src/shared/avatar-policy.test.lisp
- avatar policy
- accepts workspace-relative avatar paths and rejects URI schemes
- checks path containment safely
- detects avatar-like path strings
- supports expected local file extensions
- resolves mime type from extension

### src/shared/config-eval.test.lisp
- evaluateRuntimeEligibility
- rejects entries when required OS does not match local or remote
- accepts entries when remote platform satisfies OS requirements
- bypasses runtime requirements when always=true
- evaluates runtime requirements when always is false

### src/shared/net/ip.test.lisp
- shared ip helpers
- distinguishes canonical dotted IPv4 from legacy forms
- matches both IPv4 and IPv6 CIDRs
- extracts embedded IPv4 for transition prefixes
- treats blocked IPv6 classes as private/internal

### src/shared/sbcl-list-parse.test.lisp
- shared/sbcl-list-parse
- parses sbcl.list payloads
- parses sbcl.pair.list payloads

### src/shared/operator-scope-compat.test.lisp
- roleScopesAllow
- treats operator.read as satisfied by read/write/admin scopes
- treats operator.write as satisfied by write/admin scopes
- treats operator.approvals/operator.pairing as satisfied by operator.admin
- does not treat operator.admin as satisfying non-operator scopes
- uses strict matching for non-operator roles

### src/shared/pid-alive.test.lisp
- isPidAlive
- returns true for the current running process
- returns false for a non-existent PID
- returns false for invalid PIDs
- returns false for zombie processes on Linux
- getProcessStartTime
- returns a number on Linux for the current process
- returns null on non-Linux platforms
- returns null for invalid PIDs
- returns null for malformed /proc stat content
- handles comm fields containing spaces and parentheses

### src/shared/requirements.test.lisp
- requirements helpers
- resolveMissingBins respects local+remote
- resolveMissingAnyBins requires at least one
- resolveMissingOs allows remote platform
- resolveMissingEnv uses predicate
- buildConfigChecks includes status
- evaluateRequirementsFromMetadata derives required+missing

### src/shared/shared-misc.test.lisp
- extractTextFromChatContent
- normalizes string content
- extracts text blocks from array content
- applies sanitizer when provided
- supports custom join and normalization
- shared/frontmatter
- normalizeStringList handles strings and arrays
- getFrontmatterString extracts strings only
- parseFrontmatterBool respects fallback
- resolveOpenClawManifestBlock parses JSON5 metadata and picks openclaw block
- resolveOpenClawManifestBlock returns undefined for invalid input
- resolveNodeIdFromCandidates
- matches nodeId
- matches displayName using normalization
- matches nodeId prefix (>=6 chars)
- throws unknown sbcl with known list
- throws ambiguous sbcl with matches list
- prefers a unique connected sbcl when names are duplicated
- stays ambiguous when multiple connected nodes match

### src/shared/string-normalization.test.lisp
- shared/string-normalization
- normalizes mixed allow-list entries
- normalizes mixed allow-list entries to lowercase
- normalizes slug-like labels while preserving supported symbols
- normalizes @/# prefixed slugs used by channel allowlists

### src/shared/string-sample.test.lisp
- summarizeStringEntries
- returns emptyText for empty lists
- joins short lists without a suffix
- adds a remainder suffix when truncating

### src/shared/text/assistant-visible-text.test.lisp
- stripAssistantInternalScaffolding
- strips reasoning tags
- strips relevant-memories scaffolding blocks
- supports relevant_memories tag variants
- keeps relevant-memories tags inside fenced code
- hides unfinished relevant-memories blocks

### src/shared/text/join-segments.test.lisp
- concatOptionalTextSegments
- concatenates left and right with default separator
- keeps explicit empty-string right value
- joinPresentTextSegments
- joins non-empty segments
- returns undefined when all segments are empty
- trims segments when requested

### src/shared/text/reasoning-tags.test.lisp
- stripReasoningTagsFromText
- basic functionality
- returns text unchanged when no reasoning tags present
- strips reasoning-tag variants
- strips multiple reasoning blocks
- code block preservation (issue #3952)
- preserves tags inside code examples
- handles mixed code-tag and real-tag content
- edge cases
- handles malformed tags and null-ish inputs
- handles fenced and inline code edge behavior
- handles nested and final tag behavior
- handles unicode, attributes, and case-insensitive tag names
- handles long content and pathological backtick patterns efficiently
- strict vs preserve mode
- applies strict and preserve modes to unclosed tags
- trim options
- applies configured trim strategies

## signal

### src/signal/client.test.lisp
- signalRpcRequest
- returns parsed RPC result
- throws a wrapped error when RPC response JSON is malformed
- throws when RPC response envelope has neither result nor error

### src/signal/format.chunking.test.lisp
- splitSignalFormattedText
- style-aware splitting - basic text
- text with no styles splits correctly at whitespace
- empty text returns empty array
- text under limit returns single chunk unchanged
- style-aware splitting - style preservation
- style fully within first chunk stays in first chunk
- style fully within second chunk has offset adjusted to chunk-local position
- style spanning chunk boundary is split into two ranges
- style starting exactly at split point goes entirely to second chunk
- style ending exactly at split point stays entirely in first chunk
- multiple styles, some spanning boundary, some not
- style-aware splitting - edge cases
- handles zero-length text with styles gracefully
- handles text that splits exactly at limit
- preserves style through whitespace trimming
- handles repeated substrings correctly (no indexOf fragility)
- handles chunk that starts with whitespace after split
- deterministically tracks position without indexOf fragility
- markdownToSignalTextChunks
- link expansion chunk limit
- does not exceed chunk limit after link expansion
- handles multiple links near chunk boundary
- link expansion with style preservation
- long message with links that expand beyond limit preserves all text
- styles (bold, italic) survive chunking correctly after link expansion
- multiple links near chunk boundary all get properly chunked
- preserves spoiler style through link expansion and chunking

### src/signal/format.links.test.lisp
- markdownToSignalText
- duplicate URL display
- does not duplicate URL for normalized equivalent labels
- still shows URL when label is meaningfully different
- handles URL with path - should show URL when label is just domain

### src/signal/format.test.lisp
- markdownToSignalText
- renders inline styles
- renders links as label plus url when needed
- keeps style offsets correct with multiple expanded links
- applies spoiler styling
- renders fenced code blocks with monospaced styles
- renders lists without extra block markup
- uses UTF-16 code units for offsets

### src/signal/format.visual.test.lisp
- markdownToSignalText
- headings visual distinction
- renders headings as bold text
- renders h2 headings as bold text
- renders h3 headings as bold text
- blockquote visual distinction
- renders blockquotes with a visible prefix
- renders multi-line blockquotes with prefix
- horizontal rule rendering
- renders horizontal rules as a visible separator
- renders horizontal rule between content

### src/signal/identity.test.lisp
- looksLikeUuid
- accepts hyphenated UUIDs
- accepts compact UUIDs
- accepts uuid-like hex values with letters
- rejects numeric ids and phone-like values
- signal sender identity
- prefers sourceNumber over sourceUuid
- uses sourceUuid when sourceNumber is missing
- maps uuid senders to recipient and peer ids

### src/signal/monitor.test.lisp
- signal groupPolicy gating
- allows when policy is open
- blocks when policy is disabled
- blocks allowlist when empty
- allows allowlist when sender matches
- allows allowlist wildcard
- allows allowlist when uuid sender matches

### src/signal/monitor.tool-result.pairs-uuid-only-senders-uuid-allowlist-entry.test.lisp
- monitorSignalProvider tool results
- pairs uuid-only senders with a uuid allowlist entry
- reconnects after stream errors until aborted

### src/signal/monitor.tool-result.sends-tool-summaries-responseprefix.test.lisp
- monitorSignalProvider tool results
- uses bounded readiness checks when auto-starting the daemon
- uses startupTimeoutMs override when provided
- caps startupTimeoutMs at 2 minutes
- fails fast when auto-started signal daemon exits during startup
- treats daemon exit after user abort as clean shutdown
- skips tool summaries with responsePrefix
- replies with pairing code when dmPolicy is pairing and no allowFrom is set
- ignores reaction-only messages
- ignores reaction-only dataMessage.reaction events (don’t treat as broken attachments)
- enqueues system events for reaction notifications
- notifies on own reactions when target includes uuid + phone
- processes messages when reaction metadata is present
- does not resend pairing code when a request is already pending

### src/signal/monitor/event-handler.inbound-contract.test.lisp
- signal createSignalEventHandler inbound contract
- passes a finalized MsgContext to dispatchInboundMessage
- normalizes direct chat To/OriginatingTo targets to canonical Signal ids
- sends typing + read receipt for allowed DMs
- does not auto-authorize DM commands in open mode without allowlists
- forwards all fetched attachments via MediaPaths/MediaTypes
- drops own UUID inbound messages when only accountUuid is configured
- drops sync envelopes when syncMessage is present but null

### src/signal/monitor/event-handler.mention-gating.test.lisp
- signal mention gating
- drops group messages without mention when requireMention is configured
- allows group messages with mention when requireMention is configured
- sets WasMentioned=false for group messages without mention when requireMention is off
- records pending history for skipped group messages
- records attachment placeholder in pending history for skipped attachment-only group messages
- normalizes mixed-case parameterized attachment MIME in skipped pending history
- summarizes multiple skipped attachments with stable file count wording
- records quote text in pending history for skipped quote-only group messages
- bypasses mention gating for authorized control commands
- hydrates mention placeholders before trimming so offsets stay aligned
- counts mention metadata replacements toward requireMention gating
- renderSignalMentions
- returns the original message when no mentions are provided
- replaces placeholder code points using mention metadata
- skips mentions that lack identifiers or out-of-bounds spans
- clamps and truncates fractional mention offsets

### src/signal/probe.test.lisp
- probeSignal
- extracts version from {version} result
- returns ok=false when /check fails
- classifySignalCliLogLine
- treats INFO/DEBUG as log (even if emitted on stderr)
- treats WARN/ERROR as error
- treats failures without explicit severity as error
- returns null for empty lines

### src/signal/send-reactions.test.lisp
- sendReactionSignal
- uses recipients array and targetAuthor for uuid dms
- uses groupIds array and maps targetAuthorUuid
- defaults targetAuthor to recipient for removals

## slack

### src/slack/accounts.test.lisp
- resolveSlackAccount allowFrom precedence
- prefers accounts.default.allowFrom over top-level for default account
- falls back to top-level allowFrom for named account without override
- does not inherit default account allowFrom for named account when top-level is absent
- falls back to top-level dm.allowFrom when allowFrom alias is unset

### src/slack/actions.blocks.test.lisp
- editSlackMessage blocks
- updates with valid blocks
- uses image block text as edit fallback
- uses video block title as edit fallback
- uses generic file fallback text for file blocks
- rejects empty blocks arrays
- rejects blocks missing a type
- rejects blocks arrays above Slack max count

### src/slack/actions.download-file.test.lisp
- downloadSlackFile
- returns null when files.info has no private download URL
- downloads via resolveSlackMedia using fresh files.info metadata
- returns null when channel scope definitely mismatches file shares
- returns null when thread scope definitely mismatches file share thread
- keeps legacy behavior when file metadata does not expose channel/thread shares

### src/slack/actions.read.test.lisp
- readSlackMessages
- uses conversations.replies and drops the parent message
- uses conversations.history when threadId is missing

### src/slack/blocks-fallback.test.lisp
- buildSlackBlocksFallbackText
- prefers header text
- uses image alt text
- uses generic defaults for file and unknown blocks

### src/slack/blocks-input.test.lisp
- parseSlackBlocksInput
- returns undefined when blocks are missing
- accepts blocks arrays
- accepts JSON blocks strings
- rejects invalid block payloads

### src/slack/channel-migration.test.lisp
- migrateSlackChannelConfig
- migrates global channel ids
- migrates account-scoped channels
- matches account ids case-insensitively
- skips migration when new id already exists
- no-ops when old and new channel ids are the same

### src/slack/client.test.lisp
- slack web client config
- applies the default retry config when none is provided
- respects explicit retry config overrides
- passes merged options into WebClient

### src/slack/draft-stream.test.lisp
- createSlackDraftStream
- sends the first update and edits subsequent updates
- does not send duplicate text
- supports forceNewMessage for subsequent assistant messages
- stops when text exceeds max chars
- clear removes preview message when one exists
- clear is a no-op when no preview message exists
- clear warns when cleanup fails

### src/slack/format.test.lisp
- markdownToSlackMrkdwn
- handles core markdown formatting conversions
- handles nested list items
- handles complex message with multiple elements
- does not throw when input is undefined at runtime
- escapeSlackMrkdwn
- returns plain text unchanged
- escapes slack and mrkdwn control characters
- normalizeSlackOutboundText
- normalizes markdown for outbound send/update paths

### src/slack/http/registry.test.lisp
- normalizeSlackWebhookPath
- returns the default path when input is empty
- ensures a leading slash
- registerSlackHttpHandler
- routes requests to a registered handler
- returns false when no handler matches
- logs and ignores duplicate registrations

### src/slack/message-actions.test.lisp
- listSlackMessageActions
- includes download-file when message actions are enabled

### src/slack/modal-metadata.test.lisp
- parseSlackModalPrivateMetadata
- returns empty object for missing or invalid values
- parses known metadata fields
- encodeSlackModalPrivateMetadata
- encodes only known non-empty fields
- throws when encoded payload exceeds Slack metadata limit

### src/slack/monitor.test.lisp
- slack groupPolicy gating
- allows when policy is open
- blocks when policy is disabled
- blocks allowlist when no channel allowlist configured
- allows allowlist when channel is allowed
- blocks allowlist when channel is not allowed
- resolveSlackThreadTs
- stays in incoming threads for all replyToMode values
- replyToMode=off
- returns undefined when not in a thread
- replyToMode=first
- returns messageTs for first reply when not in a thread
- returns undefined for subsequent replies when not in a thread (goes to main channel)
- replyToMode=all
- returns messageTs when not in a thread (starts thread)
- buildSlackSlashCommandMatcher
- matches with or without a leading slash
- openclaw
- /openclaw
- does not match similar names
- /openclaw-bot
- openclaw-bot

### src/slack/monitor.threading.missing-thread-ts.test.lisp
- monitorSlackProvider threading
- recovers missing thread_ts when parent_user_id is present
- continues without thread_ts when history lookup returns no thread result
- continues without thread_ts when history lookup throws

### src/slack/monitor.tool-result.test.lisp
- monitorSlackProvider tool results
- skips socket startup when Slack channel is disabled
- skips tool summaries with responsePrefix
- drops events with mismatched api_app_id
- does not derive responsePrefix from routed agent identity when unset
- preserves RawBody without injecting processed room history
- scopes thread history to the thread by default
- updates assistant thread status when replies start
- accepts channel messages when mentionPatterns match
- accepts channel messages when mentionPatterns match even if another user is mentioned
- treats replies to bot threads as implicit mentions
- accepts channel messages without mention when channels.slack.requireMention is false
- treats control commands as mentions for group bypass
- threads replies when incoming message is in a thread
- ignores replyToId directive when replyToMode is off
- keeps replyToId directive threading when replyToMode is all
- reacts to mention-gated room messages when ackReaction is enabled
- replies with pairing code when dmPolicy is pairing and no allowFrom is set
- does not resend pairing code when a request is already pending
- threads top-level replies when replyToMode is all
- treats parent_user_id as a thread reply even when thread_ts matches ts
- keeps thread parent inheritance opt-in
- injects starter context for thread replies
- scopes thread session keys to the routed agent
- keeps replies in channel root when message is not threaded (replyToMode off)
- threads first reply when replyToMode is first and message is not threaded

### src/slack/monitor/allow-list.test.lisp
- slack/allow-list
- normalizes lists and slugs
- matches wildcard and id candidates by default
- allows all users when allowList is empty and denies unknown entries

### src/slack/monitor/auth.test.lisp
- resolveSlackEffectiveAllowFrom
- falls back to channel config allowFrom when pairing store throws
- treats malformed non-array pairing-store responses as empty
- memoizes pairing-store allowFrom reads within TTL
- refreshes pairing-store allowFrom when cache TTL is zero

### src/slack/monitor/context.test.lisp
- createSlackMonitorContext shouldDropMismatchedSlackEvent
- drops mismatched top-level app/team identifiers
- drops mismatched nested team.id payloads used by interaction bodies

### src/slack/monitor/events/channels.test.lisp
- registerSlackChannelEvents
- does not track mismatched events
- tracks accepted events

### src/slack/monitor/events/interactions.test.lisp
- registerSlackInteractionEvents
- enqueues structured events and updates button rows
- drops block actions when mismatch guard triggers
- drops modal lifecycle payloads when mismatch guard triggers
- captures select values and updates action rows for non-button actions
- blocks block actions from users outside configured channel users allowlist
- blocks DM block actions when sender is not in allowFrom
- ignores malformed action payloads after ack and logs warning
- escapes mrkdwn characters in confirmation labels
- falls back to container channel and message timestamps
- summarizes multi-select confirmations in updated message rows
- renders date/time/datetime picker selections in confirmation rows
- captures expanded selection and temporal payload fields
- captures workflow button trigger metadata
- captures modal submissions and enqueues view submission event
- blocks modal events when private metadata userId does not match submitter
- blocks modal events when private metadata is missing userId
- captures modal input labels and picker values across block types
- truncates rich text preview to keep payload summaries compact
- captures modal close events and enqueues view closed event
- defaults modal close isCleared to false when Slack omits the flag
- caps oversized interaction payloads with compact summaries

### src/slack/monitor/events/members.test.lisp
- registerSlackMemberEvents
- does not track mismatched events
- tracks accepted member events

### src/slack/monitor/events/message-subtype-handlers.test.lisp
- resolveSlackMessageSubtypeHandler
- resolves message_changed metadata and identifiers
- DM with @user
- resolves message_deleted metadata and identifiers
- general
- resolves thread_broadcast metadata and identifiers
- general
- returns undefined for regular messages

### src/slack/monitor/events/messages.test.lisp
- registerSlackMessageEvents
- passes regular message events to the message handler
- handles channel and group messages via the unified message handler
- applies subtype system-event handling for channel messages
- skips app_mention events for DM channel ids even with contradictory channel_type
- routes app_mention events from channels to the message handler

### src/slack/monitor/events/pins.test.lisp
- registerSlackPinEvents
- does not track mismatched events
- tracks accepted pin events

### src/slack/monitor/events/reactions.test.lisp
- registerSlackReactionEvents
- does not track mismatched events
- tracks accepted message reactions
- passes sender context when resolving reaction session keys

### src/slack/monitor/media.test.lisp
- fetchWithSlackAuth
- sends Authorization header on initial request with manual redirect
- rejects non-Slack hosts to avoid leaking tokens
- follows redirects without Authorization header
- handles relative redirect URLs
- returns redirect response when no location header is provided
- returns 4xx/5xx responses directly without following
- handles 301 permanent redirects
- resolveSlackMedia
- prefers url_private_download over url_private
- returns null when download fails
- returns null when no files are provided
- skips files without url_private
- rejects HTML auth pages for non-HTML files
- allows expected HTML uploads
- overrides video/* MIME to audio/* for slack_audio voice messages
- preserves original MIME for non-voice Slack files
- falls through to next file when first file returns error
- returns all successfully downloaded files as an array
- caps downloads to 8 files for large multi-attachment messages
- Slack media SSRF policy
- passes ssrfPolicy with Slack CDN allowedHostnames and allowRfc2544BenchmarkRange to file downloads
- passes ssrfPolicy to forwarded attachment image downloads
- resolveSlackAttachmentContent
- ignores non-forwarded attachments
- extracts text from forwarded shared attachments
- skips forwarded image URLs on non-Slack hosts
- downloads Slack-hosted images from forwarded shared attachments
- resolveSlackThreadHistory
- paginates and returns the latest N messages across pages
- includes file-only messages and drops empty-only entries
- returns empty when limit is zero without calling Slack API
- returns empty when Slack API throws

### src/slack/monitor/message-handler.app-mention-race.test.lisp
- createSlackMessageHandler app_mention race handling
- allows a single app_mention retry when message event was dropped before dispatch
- allows app_mention while message handling is still in-flight, then keeps later duplicates deduped
- suppresses message dispatch when app_mention already dispatched during in-flight race
- keeps app_mention deduped when message event already dispatched

### src/slack/monitor/message-handler.debounce-key.test.lisp
- buildSlackDebounceKey
- returns null when message has no sender
- scopes thread replies by thread_ts
- isolates unresolved thread replies with maybe-thread prefix
- scopes top-level messages by their own timestamp to prevent cross-thread collisions
- keeps top-level DMs channel-scoped to preserve short-message batching
- falls back to bare channel when no timestamp is available
- uses bot_id as sender fallback

### src/slack/monitor/message-handler.test.lisp
- createSlackMessageHandler
- does not track invalid non-message events from the message stream
- does not track duplicate messages that are already seen
- tracks accepted non-duplicate messages
- flushes pending top-level buffered keys before immediate non-debounce follow-ups

### src/slack/monitor/message-handler/dispatch.streaming.test.lisp
- slack native streaming defaults
- is enabled for partial mode when native streaming is on
- is disabled outside partial mode or when native streaming is off
- slack native streaming thread hint
- stays off-thread when replyToMode=off and message is not in a thread
- uses first-reply thread when replyToMode=first
- uses the existing incoming thread regardless of replyToMode

### src/slack/monitor/message-handler/prepare.test.lisp
- slack prepareSlackMessage inbound contract
- produces a finalized MsgContext
- includes forwarded shared attachment text in raw body
- ignores non-forward attachments when no direct text/files are present
- delivers file-only message with placeholder when media download fails
- falls back to generic file label when a Slack file name is empty
- extracts attachment text for bot messages with empty text when allowBots is true (#27616)
- keeps channel metadata out of GroupSystemPrompt
- classifies D-prefix DMs correctly even when channel_type is wrong
- classifies D-prefix DMs when channel_type is missing
- sets MessageThreadId for top-level messages when replyToMode=all
- respects replyToModeByChatType.direct override for DMs
- still threads channel messages when replyToModeByChatType.direct is off
- respects dm.replyToMode legacy override for DMs
- marks first thread turn and injects thread history for a new thread session
- skips loading thread history when thread session already exists in store (bloat fix)
- includes thread_ts and parent_user_id metadata in thread replies
- excludes thread_ts from top-level messages
- excludes thread metadata when thread_ts equals ts without parent_user_id
- creates thread session for top-level DM when replyToMode=all
- prepareSlackMessage sender prefix
- prefixes channel bodies with sender label
- detects /new as control command when prefixed with Slack mention

### src/slack/monitor/message-handler/prepare.thread-session-key.test.lisp
- thread-level session keys
- keeps top-level channel turns in one session when replyToMode=off
- uses parent thread_ts for thread replies even when replyToMode=off
- keeps top-level channel messages on the per-channel session regardless of replyToMode
- does not add thread suffix for DMs when replyToMode=off

### src/slack/monitor/monitor.test.lisp
- resolveSlackChannelConfig
- uses defaultRequireMention when channels config is empty
- defaults defaultRequireMention to true when not provided
- prefers explicit channel/fallback requireMention over defaultRequireMention
- uses wildcard entries when no direct channel config exists
- uses direct match metadata when channel config exists
- matches channel config key stored in lowercase when Slack delivers uppercase channel ID
- matches channel config key stored in uppercase when user types lowercase channel ID
- normalizeSlackChannelType
- infers channel types from ids when missing
- prefers explicit channel_type values
- overrides wrong channel_type for D-prefix DM channels
- preserves correct channel_type for D-prefix DM channels
- does not override G-prefix channel_type (ambiguous prefix)
- resolveSlackSystemEventSessionKey
- defaults missing channel_type to channel sessions
- routes channel system events through account bindings
- routes DM system events through direct-peer bindings when sender is known
- isChannelAllowed with groupPolicy and channelsConfig
- allows unlisted channels when groupPolicy is open even with channelsConfig entries
- blocks unlisted channels when groupPolicy is allowlist
- blocks explicitly denied channels even when groupPolicy is open
- allows all channels when groupPolicy is open and channelsConfig is empty
- resolveSlackThreadStarter cache
- returns cached thread starter without refetching within ttl
- expires stale cache entries and refetches after ttl
- does not cache empty starter text
- evicts oldest entries once cache exceeds bounded size
- createSlackThreadTsResolver
- caches resolved thread_ts lookups

### src/slack/monitor/provider.auth-errors.test.lisp
- isNonRecoverableSlackAuthError
- returns true when error is a plain string
- matches case-insensitively
- returns false for non-error values
- returns false for empty string

### src/slack/monitor/provider.group-policy.test.lisp
- resolveSlackRuntimeGroupPolicy
- fails closed when channels.slack is missing and no defaults are set
- keeps open default when channels.slack is configured
- ignores explicit global defaults when provider config is missing

### src/slack/monitor/provider.reconnect.test.lisp
- slack socket reconnect helpers
- seeds event liveness when socket mode connects
- clears connected state when socket mode disconnects
- clears connected state without error when socket mode disconnects cleanly
- resolves disconnect waiter on socket disconnect event
- resolves disconnect waiter on socket error event
- preserves error payload from unable_to_socket_mode_start event

### src/slack/monitor/replies.test.lisp
- deliverReplies identity passthrough
- passes identity to sendMessageSlack for text replies
- passes identity to sendMessageSlack for media replies
- omits identity key when not provided

### src/slack/monitor/slash.test.lisp
- Slack native command argument menus
- registers options handlers without losing app receiver binding
- falls back to static menus when app.options() throws during registration
- shows a button menu when required args are omitted
- shows a static_select menu when choices exceed button row size
- falls back to buttons when static_select value limit would be exceeded
- shows an overflow menu when choices fit compact range
- escapes mrkdwn characters in confirm dialog text
- dispatches the command when a menu button is clicked
- maps /agentstatus to /status when dispatching
- dispatches the command when a static_select option is chosen
- dispatches the command when an overflow option is chosen
- shows an external_select menu when choices exceed static_select options max
- serves filtered options for external_select menus
- rejects external_select option requests without user identity
- rejects menu clicks from other users
- falls back to postEphemeral with token when respond is unavailable
- treats malformed percent-encoding as an invalid button (no throw)
- slack slash commands channel policy
- drops mismatched slash payloads before dispatch
- allows unlisted channels when groupPolicy is open
- blocks explicitly denied channels when groupPolicy is open
- blocks unlisted channels when groupPolicy is allowlist
- slack slash commands access groups
- fails closed when channel type lookup returns empty for channels
- still treats D-prefixed channel ids as DMs when lookup fails
- computes CommandAuthorized for DM slash commands when dmPolicy is open
- enforces access-group gating when lookup fails for private channels
- slack slash command session metadata
- calls recordSessionMetaFromInbound after dispatching a slash command
- awaits session metadata persistence before dispatch

### src/slack/resolve-allowlist-common.test.lisp
- collectSlackCursorItems
- collects items across cursor pages
- resolveSlackAllowlistEntries
- handles id, non-id, and unresolved entries

### src/slack/resolve-channels.test.lisp
- resolveSlackChannelAllowlist
- resolves by name and prefers active channels
- keeps unresolved entries

### src/slack/resolve-users.test.lisp
- resolveSlackUserAllowlist
- resolves by email and prefers active human users
- keeps unresolved users

### src/slack/send.blocks.test.lisp
- sendMessageSlack NO_REPLY guard
- suppresses NO_REPLY text before any Slack API call
- suppresses NO_REPLY with surrounding whitespace
- does not suppress substantive text containing NO_REPLY
- does not suppress NO_REPLY when blocks are attached
- sendMessageSlack blocks
- posts blocks with fallback text when message is empty
- derives fallback text from image blocks
- derives fallback text from video blocks
- derives fallback text from file blocks
- rejects blocks combined with mediaUrl
- rejects empty blocks arrays from runtime callers
- rejects blocks arrays above Slack max count
- rejects blocks missing type from runtime callers

### src/slack/send.upload.test.lisp
- sendMessageSlack file upload with user IDs
- resolves bare user ID to DM channel before completing upload
- resolves prefixed user ID to DM channel before completing upload
- sends file directly to channel without conversations.open
- resolves mention-style user ID before file upload
- uploads bytes to the presigned URL and completes with thread+caption

### src/slack/sent-thread-cache.test.lisp
- slack sent-thread-cache
- records and checks thread participation
- returns false for unrecorded threads
- distinguishes different channels and threads
- scopes participation by accountId
- ignores empty accountId, channelId, or threadTs
- clears all entries
- expired entries return false and are cleaned up on read
- enforces maximum entries by evicting oldest fresh entries

### src/slack/stream-mode.test.lisp
- resolveSlackStreamMode
- defaults to replace
- accepts valid modes
- resolveSlackStreamingConfig
- defaults to partial mode with native streaming enabled
- maps legacy streamMode values to unified streaming modes
- maps legacy streaming booleans to unified mode and native streaming toggle
- accepts unified enum values directly
- applyAppendOnlyStreamUpdate
- starts with first incoming text
- uses cumulative incoming text when it extends prior source
- ignores regressive shorter incoming text
- appends non-prefix incoming chunks
- buildStatusFinalPreviewText
- cycles status dots

### src/slack/targets.test.lisp
- parseSlackTarget
- parses user mentions and prefixes
- parses channel targets
- rejects invalid @ and # targets
- resolveSlackChannelId
- strips channel: prefix and accepts raw ids
- rejects user targets
- normalizeSlackMessagingTarget
- defaults raw ids to channels

### src/slack/threading-tool-context.test.lisp
- buildSlackThreadingToolContext
- uses top-level replyToMode by default
- uses chat-type replyToMode overrides for direct messages when configured
- uses top-level replyToMode for channels when no channel override is set
- falls back to top-level when no chat-type override is set
- uses legacy dm.replyToMode for direct messages when no chat-type override exists
- uses all mode when MessageThreadId is present
- does not force all mode from ThreadLabel alone
- keeps configured channel behavior when not in a thread
- defaults to off when no replyToMode is configured
- extracts currentChannelId from channel: prefixed To
- uses NativeChannelId for DM when To is user-prefixed
- returns undefined currentChannelId when neither channel: To nor NativeChannelId is set

### src/slack/threading.test.lisp
- resolveSlackThreadTargets
- threads replies when message is already threaded
- threads top-level replies when mode is all
- does not thread status indicator when reply threading is off
- does not treat auto-created top-level thread_ts as a real thread when mode is off
- keeps first-mode behavior for auto-created top-level thread_ts
- sets messageThreadId for top-level messages when replyToMode is all
- prefers thread_ts as messageThreadId for replies

## telegram

### src/telegram/account-inspect.test.lisp
- inspectTelegramAccount SecretRef resolution
- resolves default env SecretRef templates in read-only status paths
- respects env provider allowlists in read-only status paths
- does not read env values for non-env providers

### src/telegram/accounts.test.lisp
- resolveTelegramAccount
- falls back to the first configured account when accountId is omitted
- uses TELEGRAM_BOT_TOKEN when default account config is missing
- prefers default config token over TELEGRAM_BOT_TOKEN
- does not fall back when accountId is explicitly provided
- formats debug logs with inspect-style output when debug env is enabled
- resolveDefaultTelegramAccountId
- warns when accounts.default is missing in multi-account setup (#32137)
- does not warn when accounts.default exists
- does not warn when defaultAccount is explicitly set
- does not warn when only one non-default account is configured
- warns only once per process lifetime
- prefers channels.telegram.defaultAccount when it matches a configured account
- normalizes channels.telegram.defaultAccount before lookup
- falls back when channels.telegram.defaultAccount is not configured
- resolveTelegramAccount allowFrom precedence
- prefers accounts.default allowlists over top-level for default account
- falls back to top-level allowlists for named account without overrides
- does not inherit default account allowlists for named account when top-level is absent
- resolveTelegramPollActionGateState
- requires both sendMessage and poll actions
- returns enabled only when both actions are enabled
- resolveTelegramAccount groups inheritance (#30673)
- inherits channel-level groups in single-account setup
- does NOT inherit channel-level groups to secondary account in multi-account setup
- does NOT inherit channel-level groups to default account in multi-account setup
- uses account-level groups even in multi-account setup
- account-level groups takes priority over channel-level in single-account setup

### src/telegram/audit.test.lisp
- telegram audit
- collects unmentioned numeric group ids and flags wildcard
- audits membership via getChatMember
- reports bot not in group when status is left

### src/telegram/bot-access.test.lisp
- normalizeAllowFrom
- accepts sender IDs and keeps negative chat IDs invalid

### src/telegram/bot-message-context.acp-bindings.test.lisp
- buildTelegramMessageContext ACP configured bindings
- treats configured topic bindings as explicit route matches on non-default accounts
- skips ACP session initialization when topic access is denied
- defers ACP session initialization for unauthorized control commands
- drops inbound processing when configured ACP binding initialization fails

### src/telegram/bot-message-context.audio-transcript.test.lisp
- buildTelegramMessageContext audio transcript body
- uses preflight transcript as BodyForAgent for mention-gated group voice messages
- skips preflight transcription when disableAudioPreflight is true
- uses topic disableAudioPreflight=false to override group disableAudioPreflight=true
- uses topic disableAudioPreflight=true to override group disableAudioPreflight=false

### src/telegram/bot-message-context.dm-threads.test.lisp
- buildTelegramMessageContext dm thread sessions
- uses thread session key for dm topics
- keeps legacy dm session key when no thread id
- buildTelegramMessageContext group sessions without forum
- ignores message_thread_id for regular groups (not forums)
- keeps same session for regular group with and without message_thread_id
- uses topic session for forum groups with message_thread_id
- buildTelegramMessageContext direct peer routing
- isolates dm sessions by sender id when chat id differs

### src/telegram/bot-message-context.dm-topic-threadid.test.lisp
- buildTelegramMessageContext DM topic threadId in deliveryContext (#8891)
- passes threadId to updateLastRoute for DM topics
- does not pass threadId for regular DM without topic
- does not set updateLastRoute for group messages

### src/telegram/bot-message-context.implicit-mention.test.lisp
- buildTelegramMessageContext implicitMention forum service messages
- does NOT trigger implicitMention for forum_topic_created service message
- does NOT trigger implicitMention for forum_topic_closed service message
- does NOT trigger implicitMention for general_forum_topic_hidden service message
- DOES trigger implicitMention for real bot replies (non-empty text)
- DOES trigger implicitMention for bot media messages with caption
- DOES trigger implicitMention for bot sticker/voice (no text, no caption, no service field)
- does NOT trigger implicitMention when reply is from a different user

### src/telegram/bot-message-context.named-account-dm.test.lisp
- buildTelegramMessageContext named-account DM fallback
- allows DM through for a named account with no explicit binding
- uses a per-account session key for named-account DMs
- keeps named-account fallback lastRoute on the isolated DM session
- isolates sessions between named accounts that share the default agent
- keeps identity-linked peer canonicalization in the named-account fallback path
- still drops named-account group messages without an explicit binding
- does not change the default-account DM session key

### src/telegram/bot-message-context.sender-prefix.test.lisp
- buildTelegramMessageContext sender prefix
- prefixes group bodies with sender label
- sets MessageSid from message_id
- respects messageIdOverride option

### src/telegram/bot-message-context.thread-binding.test.lisp
- buildTelegramMessageContext bound conversation override
- routes forum topic messages to the bound session
- treats named-account bound conversations as explicit route matches
- routes dm messages to the bound session

### src/telegram/bot-message-context.topic-agentid.test.lisp
- buildTelegramMessageContext per-topic agentId routing
- uses group-level agent when no topic agentId is set
- routes to topic-specific agent when agentId is set
- different topics route to different agents
- ignores whitespace-only agentId and uses group-level agent
- falls back to default agent when topic agentId does not exist
- routes DM topic to specific agent when agentId is set

### src/telegram/bot-message-dispatch.sticker-media.test.lisp
- pruneStickerMediaFromContext
- preserves appended reply media while removing primary sticker media
- clears media fields when sticker is the only media
- does not prune when sticker media is already omitted from context

### src/telegram/bot-message-dispatch.test.lisp
- dispatchTelegramMessage draft streaming
- streams drafts in private threads and forwards thread id
- uses 30-char preview debounce for legacy block stream mode
- keeps block streaming enabled when account config enables it
- keeps block streaming enabled when session reasoning level is on
- streams reasoning draft updates even when answer stream mode is off
- does not overwrite finalized preview when additional final payloads are sent
- keeps streamed preview visible when final text regresses after a tool warning
- materializes boundary preview and keeps it when no matching final arrives
- waits for queued boundary rotation before final lane delivery
- clears active preview even when an unrelated boundary archive exists
- queues late partials behind async boundary materialization
- keeps final-only preview lane finalized until a real boundary rotation happens
- does not force new message on first assistant message start
- rotates before a late second-message partial so finalized preview is not overwritten
- does not skip message-start rotation when pre-rotation did not force a new message
- does not trigger late pre-rotation mid-message after an explicit assistant message start
- finalizes multi-message assistant stream to matching preview messages in order
- maps finals correctly when first preview id resolves after message boundary
- maps finals correctly when archived preview id arrives during final flush
- queues reasoning-end split decisions behind queued reasoning deltas
- cleans superseded reasoning previews after lane rotation
- suppresses reasoning-only final payloads when reasoning level is off
- does not resend suppressed reasoning-only text through raw fallback
- uses message preview transport for DM reasoning lane when answer preview lane is active
- materializes DM answer draft final without sending a duplicate final message
- keeps reasoning and answer streaming in separate preview lanes
- does not edit reasoning preview bubble with final answer when no assistant partial arrived yet
- updates reasoning preview for reasoning block payloads instead of sending duplicates
- keeps DM draft reasoning block updates in preview flow without sending duplicates
- falls back to normal send when DM draft reasoning flush emits no preview update
- routes think-tag partials to reasoning lane and keeps answer lane clean
- routes unmatched think partials to reasoning lane without leaking answer lane
- keeps reasoning preview message when reasoning is streamed but final is answer-only
- splits think-tag final payload into reasoning and answer lanes
- does not edit preview message when final payload is an error
- clears preview for error-only finals
- clears preview after media final delivery
- clears stale preview when response is NO_REPLY
- falls back when all finals are skipped and clears preview
- sends fallback and clears preview when deliver throws (dispatcher swallows error)
- sends fallback in off mode when deliver throws
- handles error block + response final — error delivered, response finalizes preview
- cleans up preview even when fallback delivery throws (double failure)
- sends error fallback and clears preview when dispatcher throws
- supports concurrent dispatches with independent previews

### src/telegram/bot-message.test.lisp
- telegram bot message processor
- dispatches when context is available
- skips dispatch when no context is produced
- sends user-visible fallback when dispatch throws
- swallows fallback delivery failures after dispatch throws

### src/telegram/bot-native-command-menu.test.lisp
- bot-native-command-menu
- caps menu entries to Telegram limit
- validates plugin command specs and reports conflicts
- normalizes hyphenated plugin command names
- ignores malformed plugin specs without crashing
- deletes stale commands before setting new menu
- produces a stable hash regardless of command order (#32017)
- produces different hashes for different command lists (#32017)
- skips sync when command hash is unchanged (#32017)
- does not reuse cached hash across different bot identities
- does not cache empty-menu hash when deleteMyCommands fails
- retries with fewer commands on BOT_COMMANDS_TOO_MUCH

### src/telegram/bot-native-commands.group-auth.test.lisp
- native command auth in groups
- authorizes native commands in groups when sender is in groupAllowFrom
- authorizes native commands in groups from commands.allowFrom.telegram
- uses commands.allowFrom.telegram as the sole auth source when configured
- keeps groupPolicy disabled enforced when commands.allowFrom is configured
- keeps group chat allowlists enforced when commands.allowFrom is configured
- rejects native commands in groups when sender is in neither allowlist
- replies in the originating forum topic when auth is rejected

### src/telegram/bot-native-commands.plugin-auth.test.lisp
- registerTelegramNativeCommands (plugin auth)
- does not register plugin commands in menu when native=false but keeps handlers available
- allows requireAuth:false plugin command even when sender is unauthorized

### src/telegram/bot-native-commands.session-meta.test.lisp
- registerTelegramNativeCommands — session metadata
- calls recordSessionMetaFromInbound after a native slash command
- awaits session metadata persistence before dispatch
- routes Telegram native commands through configured ACP topic bindings
- routes Telegram native commands through topic-specific agent sessions
- routes Telegram native commands through bound topic sessions
- aborts native command dispatch when configured ACP topic binding cannot initialize
- keeps /new blocked in ACP-bound Telegram topics when sender is unauthorized
- keeps /new blocked for unbound Telegram topics when sender is unauthorized

### src/telegram/bot-native-commands.skills-allowlist.test.lisp
- registerTelegramNativeCommands skill allowlist integration
- registers only allowlisted skills for the bound agent menu

### src/telegram/bot-native-commands.test.lisp
- registerTelegramNativeCommands
- scopes skill commands when account binding exists
- scopes skill commands to default agent without a matching binding (#15599)
- truncates Telegram command registration to 100 commands
- normalizes hyphenated native command names for Telegram registration
- registers only Telegram-safe command names across native, custom, and plugin sources
- passes agent-scoped media roots for plugin command replies with media

### src/telegram/bot.create-telegram-bot.test.lisp
- createTelegramBot
- installs grammY throttler
- uses wrapped fetch when global fetch is available
- applies global and per-account timeoutSeconds
- sequentializes updates by chat and thread
- routes callback_query payloads as messages and answers callbacks
- wraps inbound message with Telegram envelope
- handles pairing DM flows for new and already-pending requests
- blocks unauthorized DM media before download and sends pairing reply
- blocks DM media downloads completely when dmPolicy is disabled
- blocks unauthorized DM media groups before any photo download
- triggers typing cue via onReplyStart
- dedupes duplicate updates for callback_query, message, and channel_post
- does not persist update offset past pending updates
- allows distinct callback_query ids without update_id
- applies groupPolicy cases
- routes DMs by telegram accountId binding
- drops non-default account DMs without explicit bindings
- applies group mention overrides and fallback behavior
- routes forum topics to parent or topic-specific bindings
- sends GIF replies as animations
- accepts mentionPatterns matches with and without unrelated mentions
- keeps group envelope headers stable (sender identity is separate)
- reacts to mention-gated group messages when ackReaction is enabled
- clears native commands when disabled
- handles requireMention when mentions do and do not resolve
- includes reply-to context when a Telegram reply is received
- blocks group messages for restrictive group config edge cases
- blocks group sender not in groupAllowFrom even when sender is paired in DM store
- allows control commands with TG-prefixed groupAllowFrom entries
- handles forum topic metadata and typing thread fallbacks
- threads forum replies only when a topic id exists
- applies allowFrom edge cases
- sends replies without native reply threading
- prefixes final replies with responsePrefix
- honors threaded replies for replyToMode=first/all
- honors routed group activation from session store
- applies topic skill filters and system prompts
- threads native command replies inside topics
- skips tool summaries for native slash commands
- buffers channel_post media groups and processes them together
- coalesces channel_post near-limit text fragments into one message
- drops oversized channel_post media instead of dispatching a placeholder message
- notifies users when media download fails for direct messages
- processes remaining media group photos when one photo download fails
- drops the media group when a non-recoverable media error occurs
- dedupes duplicate message updates by update_id

### src/telegram/bot.helpers.test.lisp
- resolveTelegramStreamMode
- defaults to partial when telegram streaming is unset
- prefers explicit streaming boolean
- maps legacy streamMode values
- maps unified progress mode to partial on Telegram

### src/telegram/bot.media.downloads-media-file-path-no-file-download.e2e.test.lisp
- telegram inbound media
- handles file_path media downloads and missing file_path safely
- keeps Telegram inbound media paths with triple-dash ids
- prefers proxyFetch over global fetch
- captures pin and venue location payload fields
- telegram media groups
- handles same-group buffering and separate-group independence
- telegram forwarded bursts
- coalesces forwarded text + forwarded attachment into a single processing turn with default debounce config

### src/telegram/bot.media.stickers-and-fragments.e2e.test.lisp
- telegram stickers
- downloads static sticker (WEBP) and includes sticker metadata
- refreshes cached sticker metadata on cache hit
- skips animated and video sticker formats that cannot be downloaded
- telegram text fragments
- buffers near-limit text and processes sequential parts as one message

### src/telegram/bot.test.lisp
- createTelegramBot
- merges custom commands with native commands
- ignores custom commands that collide with native commands
- registers custom commands when native commands are disabled
- blocks callback_query when inline buttons are allowlist-only and sender not authorized
- allows callback_query in groups when group policy authorizes the sender
- edits commands list for pagination callbacks
- falls back to default agent for pagination callbacks without agent suffix
- blocks pagination callbacks when allowlist rejects sender
- routes compact model callbacks by inferring provider
- rejects ambiguous compact model callbacks and returns provider list
- includes sender identity in group envelope headers
- uses quote text when a Telegram partial reply is received
- includes replied image media in inbound context for text replies
- does not fetch reply media for unauthorized DM replies
- defers reply media download until debounce flush
- isolates inbound debounce by DM topic thread id
- handles quote-only replies without reply metadata
- uses external_reply quote text for partial replies
- propagates forwarded origin from external_reply targets
- accepts group replies to the bot without explicit mention when requireMention is enabled
- inherits group allowlist + requireMention in topics
- prefers topic allowFrom over group allowFrom
- allows group messages for per-group groupPolicy open override (global groupPolicy allowlist)
- blocks control commands from unauthorized senders in per-group open groups
- sets command target session key for dm topic commands
- allows native DM commands for paired users
- blocks native DM commands for unpaired users
- registers message_reaction handler
- enqueues system event for reaction
- skips reaction when reactionNotifications is off
- defaults reactionNotifications to own
- allows reaction in all mode regardless of message sender
- skips reaction in own mode when message is not sent by bot
- allows reaction in own mode when message is sent by bot
- skips reaction from bot users
- skips reaction removal (only processes added reactions)
- enqueues one event per added emoji reaction
- routes forum group reactions to the general topic (thread id not available on reactions)
- uses correct session key for forum group reactions in general topic
- uses correct session key for regular group reactions without topic

### src/telegram/bot/delivery.resolve-media-retry.test.lisp
- resolveMedia getFile retry
- retries getFile on transient failure and succeeds on second attempt
- does not catch errors from fetchRemoteMedia (only getFile is retried)
- does not retry 'file is too big' error (400 Bad Request) and returns null
- does not retry 'file is too big' GrammyError instances and returns null
- throws when getFile returns no file_path
- still retries transient errors even after encountering file too big in different call
- retries getFile for stickers on transient failure
- returns null for sticker when getFile exhausts retries
- resolveMedia original filename preservation
- passes document.file_name to saveMediaBuffer instead of server-side path
- passes audio.file_name to saveMediaBuffer
- passes video.file_name to saveMediaBuffer
- falls back to fetched.fileName when telegram file_name is absent
- falls back to filePath when neither telegram nor fetched fileName is available

### src/telegram/bot/delivery.test.lisp
- deliverReplies
- skips audioAsVoice-only payloads without logging an error
- skips malformed replies and continues with valid entries
- reports message_sent success=false when hooks blank out a text-only reply
- passes accountId into message hooks
- passes media metadata to message_sending hooks
- invokes onVoiceRecording before sending a voice note
- renders markdown in media captions
- passes mediaLocalRoots to media loading
- includes link_preview_options when linkPreview is false
- includes message_thread_id for DM topics
- retries DM topic sends without message_thread_id when thread is missing
- does not retry forum sends without message_thread_id
- retries media sends without message_thread_id for DM topics
- does not include link_preview_options when linkPreview is true
- falls back to plain text when markdown renders to empty HTML in threaded mode
- throws when formatted and plain fallback text are both empty
- uses reply_to_message_id when quote text is provided
- falls back to text when sendVoice fails with VOICE_MESSAGES_FORBIDDEN
- voice fallback applies reply-to only on first chunk when replyToMode is first
- rethrows non-VOICE_MESSAGES_FORBIDDEN errors from sendVoice
- replyToMode 'first' only applies reply-to to the first text chunk
- replyToMode 'all' applies reply-to to every text chunk
- replyToMode 'first' only applies reply-to to first media item
- pins the first delivered text message when telegram pin is requested
- continues when pinning fails
- rethrows VOICE_MESSAGES_FORBIDDEN when no text fallback is available

### src/telegram/bot/helpers.test.lisp
- resolveTelegramForumThreadId
- buildTelegramThreadParams
- buildTypingThreadParams
- resolveTelegramDirectPeerId
- prefers sender id when available
- falls back to chat id when sender id is missing
- thread id normalization
- normalizeForwardedContext
- handles forward_origin users
- handles hidden forward_origin names
- handles forward_origin channel with author_signature and message_id
- handles forward_origin chat with sender_chat and author_signature
- uses author_signature from forward_origin
- returns undefined signature when author_signature is blank
- handles forward_origin channel without author_signature
- describeReplyTarget
- returns null when no reply_to_message
- extracts basic reply info
- extracts forwarded context from reply_to_message (issue #9619)
- extracts forwarded context from channel forward in reply_to_message
- extracts forwarded context from external_reply
- hasBotMention
- prefers caption text and caption entities when message text is absent
- matches exact username mentions from plain text
- does not match mention prefixes from longer bot usernames
- still matches exact mention entities
- expandTextLinks
- returns text unchanged when no entities are provided
- returns text unchanged when there are no text_link entities
- expands a single text_link entity
- expands multiple text_link entities
- handles adjacent text_link entities
- preserves offsets from the original string

### src/telegram/draft-chunking.test.lisp
- resolveTelegramDraftStreamingChunking
- uses smaller defaults than block streaming
- clamps to telegram.textChunkLimit
- supports per-account overrides

### src/telegram/draft-stream.test.lisp
- createTelegramDraftStream
- sends stream preview message with message_thread_id when provided
- edits existing stream preview message on subsequent updates
- waits for in-flight updates before final flush edit
- omits message_thread_id for general topic id
- uses sendMessageDraft for dm threads and does not create a preview message
- supports forcing message transport in dm threads
- falls back to message transport when sendMessageDraft is unavailable
- falls back to message transport when sendMessageDraft is rejected at runtime
- retries DM message preview send without thread when thread is not found
- materializes draft previews using rendered HTML text
- clears draft after materializing to avoid duplicate display in DM
- retries materialize send without thread when dm thread lookup fails
- returns existing preview id when materializing message transport
- does not edit or delete messages after DM draft stream finalization
- rotates draft_id when forceNewMessage races an in-flight DM draft send
- creates new message after forceNewMessage is called
- sends first update immediately after forceNewMessage within throttle window
- does not rebind to an old message when forceNewMessage races an in-flight send
- supports rendered previews with parse_mode
- enforces maxChars after renderText expansion
- draft stream initial message debounce
- isFinal has highest priority
- sends immediately on stop() even with 1 character
- sends immediately on stop() with short sentence
- minInitialChars threshold
- does not send first message below threshold
- sends first message when reaching threshold
- works with longer text above threshold
- subsequent updates after first message
- edits normally after first message is sent
- default behavior without debounce params
- sends immediately without minInitialChars set (backward compatible)

### src/telegram/fetch.test.lisp
- resolveTelegramFetch
- returns wrapped global fetch when available
- wraps proxy fetches and normalizes foreign signals once
- does not double-wrap an already wrapped proxy fetch
- honors env enable override
- uses config override when provided
- env disable override wins over config
- applies dns result order from config
- retries dns setter on next call when previous attempt threw
- replaces global undici dispatcher with proxy-aware EnvHttpProxyAgent
- keeps an existing proxy-like global dispatcher
- updates proxy-like dispatcher when proxy env is configured
- sets global dispatcher only once across repeated equal decisions
- updates global dispatcher when autoSelectFamily decision changes
- retries once with ipv4 fallback when fetch fails with network timeout/unreachable
- retries with ipv4 fallback once per request, not once per process
- does not retry when fetch fails without fallback network error codes

### src/telegram/format.test.lisp
- markdownToTelegramHtml
- handles core markdown-to-telegram conversions
- renders blockquotes as native Telegram blockquote tags
- renders blockquotes with inline formatting
- renders multiline blockquotes as a single Telegram blockquote
- renders separated quoted paragraphs as distinct blockquotes
- renders fenced code blocks
- properly nests overlapping bold and autolink (#4071)
- properly nests link inside bold
- properly nests bold wrapping a link with trailing text
- properly nests bold inside a link
- wraps punctuated file references in code tags
- renders spoiler tags
- renders spoiler with nested formatting
- does not treat single pipe as spoiler
- does not treat unpaired || as spoiler
- keeps valid spoiler pairs when a trailing || is unmatched

### src/telegram/format.wrap-md.test.lisp
- wrapFileReferencesInHtml
- wraps supported file references and paths
- does not wrap inside protected html contexts
- handles mixed content correctly
- handles boundary and punctuation wrapping cases
- de-linkifies auto-linkified anchors for plain files and paths
- preserves explicit links where label differs from href
- wraps file ref after closing anchor tag
- renderTelegramHtmlText - file reference wrapping
- wraps file references in markdown mode
- does not wrap in HTML mode (trusts caller markup)
- does not double-wrap already code-formatted content
- markdownToTelegramHtml - file reference wrapping
- wraps file references by default
- can skip wrapping when requested
- wraps multiple file types in a single message
- preserves real URLs as anchor tags
- preserves explicit markdown links even when href looks like a file ref
- wraps file ref after real URL in same message
- markdownToTelegramChunks - file reference wrapping
- wraps file references in chunked output
- keeps rendered html chunks within the provided limit
- preserves whitespace when html-limit retry splitting runs
- edge cases
- wraps file refs inside emphasis tags
- does not wrap inside fenced code blocks
- preserves real URL/domain paths as anchors
- handles wrapFileRefs: false (plain text output)
- classifies extension-like tokens as file refs or domains
- wraps file refs across boundaries, sequences, and path variants
- handles nested code tags (depth tracking)
- handles multiple anchor tags in sequence
- wraps orphaned TLD pattern after special character
- wraps orphaned single-letter TLD patterns
- does not match filenames containing angle brackets
- wraps file ref before unrelated HTML tags
- handles malformed HTML with stray closing tags (negative depth)
- does not wrap orphaned TLD fragments inside protected HTML contexts
- handles multiple orphaned TLDs with HTML tags (offset stability)

### src/telegram/group-access.base-access.test.lisp
- evaluateTelegramGroupBaseAccess
- fails closed when explicit group allowFrom override is empty
- allows group message when override is not configured
- allows sender explicitly listed in override

### src/telegram/group-access.group-policy.test.lisp
- resolveTelegramRuntimeGroupPolicy
- fails closed when channels.telegram is missing and no defaults are set
- keeps open fallback when channels.telegram is configured
- ignores explicit defaults when provider config is missing

### src/telegram/group-access.policy-access.test.lisp
- evaluateTelegramGroupPolicyAccess – chat allowlist vs sender allowlist ordering
- allows a group explicitly listed in groups config even when no allowFrom entries exist
- still blocks when only wildcard match and no allowFrom entries
- rejects a group NOT in groups config
- still enforces sender allowlist when checkChatAllowlist is disabled
- blocks unauthorized sender even when chat is explicitly allowed and sender entries exist
- allows when groupPolicy is open regardless of allowlist state
- rejects when groupPolicy is disabled
- allows non-group messages without any checks
- blocks allowlist groups without sender identity before sender matching
- allows authorized sender in wildcard-matched group with sender entries

### src/telegram/group-migration.test.lisp
- migrateTelegramGroupConfig
- migrates global group ids
- migrates account-scoped groups
- matches account ids case-insensitively
- skips migration when new id already exists
- no-ops when old and new group ids are the same

### src/telegram/inline-buttons.test.lisp
- resolveTelegramTargetChatType
- returns 'direct' for positive numeric IDs
- returns 'group' for negative numeric IDs
- handles telegram: prefix from normalizeTelegramMessagingTarget
- handles tg/group prefixes and topic suffixes
- returns 'unknown' for usernames
- returns 'unknown' for empty strings

### src/telegram/lane-delivery.test.lisp
- createLaneTextDeliverer
- finalizes text-only replies by editing an existing preview message
- primes stop-created previews with final text before editing
- treats stop-created preview edit failures as delivered
- treats 'message is not modified' preview edit errors as delivered
- falls back to normal delivery when editing an existing preview fails
- falls back to normal delivery when stop-created preview has no message id
- keeps existing preview when final text regresses
- falls back to normal delivery when final text exceeds preview edit limit
- materializes DM draft streaming final even when text is unchanged
- materializes DM draft streaming final when revision changes
- falls back to normal send when draft materialize returns no message id
- does not use DM draft final shortcut for media payloads
- does not use DM draft final shortcut when inline buttons are present
- deletes consumed boundary previews after fallback final send

### src/telegram/model-buttons.test.lisp
- parseModelCallbackData
- parses supported callback variants
- returns null for unsupported callback variants
- resolveModelSelection
- returns explicit provider selections unchanged
- resolves compact callbacks when exactly one provider matches
- returns ambiguous result when zero or multiple providers match
- buildModelSelectionCallbackData
- uses standard callback when under limit and compact callback when needed
- returns null when even compact callback exceeds Telegram limit
- buildProviderKeyboard
- lays out providers in two-column rows
- buildModelsKeyboard
- shows back button for empty models
- renders model rows and optional current-model indicator
- renders pagination controls for first, middle, and last pages
- keeps short display IDs untouched and truncates overly long IDs
- uses compact selection callback when provider/model callback exceeds 64 bytes
- buildBrowseProvidersButton
- returns browse providers button
- getModelsPageSize
- returns default page size
- calculateTotalPages
- calculates pages correctly
- uses custom page size
- large model lists (OpenRouter-scale)
- handles 100+ models with pagination
- all callback_data stays within 64-byte limit
- skips models that would exceed callback_data limit

### src/telegram/monitor.test.lisp
- monitorTelegramProvider (grammY)
- processes a DM and sends reply
- uses agent maxConcurrent for runner concurrency
- requires mention in groups by default
- retries on recoverable undici fetch errors
- deletes webhook before starting polling
- retries recoverable deleteWebhook failures before polling
- retries setup-time recoverable errors before starting polling
- awaits runner.stop before retrying after recoverable polling error
- stops bot instance when polling cycle exits
- surfaces non-recoverable errors
- force-restarts polling when unhandled network rejection stalls runner
- passes configured webhookHost to webhook listener
- webhook mode waits for abort signal before returning
- force-restarts polling when getUpdates stalls (watchdog)
- confirms persisted offset with Telegram before starting runner
- skips offset confirmation when no persisted offset exists
- skips offset confirmation when persisted offset is invalid
- skips offset confirmation when persisted offset cannot be safely incremented
- resets webhookCleared latch on 409 conflict so deleteWebhook re-runs
- falls back to configured webhookSecret when not passed explicitly

### src/telegram/network-config.test.lisp
- resolveTelegramAutoSelectFamilyDecision
- prefers env enable over env disable
- uses env disable when set
- prefers env enable over config
- prefers env disable over config
- uses config override when provided
- defaults to enable on Node 22
- returns null when no decision applies
- WSL2 detection
- disables autoSelectFamily on WSL2
- respects config override on WSL2
- respects env override on WSL2
- uses Node 22 default when not on WSL2
- memoizes WSL2 detection across repeated defaults
- resolveTelegramDnsResultOrderDecision
- uses env override when provided
- uses config override when provided
- defaults to ipv4first on Node 22
- returns null when no dns decision applies

### src/telegram/network-errors.test.lisp
- isRecoverableTelegramNetworkError
- detects recoverable error codes
- detects additional recoverable error codes
- detects AbortError names
- detects nested causes
- detects expanded message patterns
- treats undici fetch failed errors as recoverable in send context
- skips broad message matches for send context
- treats grammY failed-after envelope errors as recoverable in send context
- returns false for unrelated errors
- detects grammY 'timed out' long-poll errors (#7239)
- Grammy HttpError
- detects network error wrapped in HttpError
- detects network error with cause wrapped in HttpError
- returns false for non-network errors wrapped in HttpError
- isSafeToRetrySendError
- allows retry for ECONNREFUSED (pre-connect, message not sent)
- allows retry for ENOTFOUND (DNS failure, message not sent)
- allows retry for EAI_AGAIN (transient DNS, message not sent)
- allows retry for ENETUNREACH (no route to host, message not sent)
- allows retry for EHOSTUNREACH (host unreachable, message not sent)
- does NOT allow retry for ECONNRESET (message may already be delivered)
- does NOT allow retry for ETIMEDOUT (message may already be delivered)
- does NOT allow retry for EPIPE (connection broken mid-transfer, message may be delivered)
- does NOT allow retry for UND_ERR_CONNECT_TIMEOUT (ambiguous timing)
- does NOT allow retry for non-network errors
- detects pre-connect error nested in cause chain

### src/telegram/probe.test.lisp
- probeTelegram retry logic
- should fail after 3 unsuccessful attempts
- should NOT retry if getMe returns a 401 Unauthorized

### src/telegram/proxy.test.lisp
- makeProxyFetch
- uses undici fetch with ProxyAgent dispatcher

### src/telegram/reaction-level.test.lisp
- resolveTelegramReactionLevel
- defaults to minimal level when reactionLevel is not set
- returns off level with no reactions enabled
- returns ack level with only ackEnabled
- returns minimal level with agent reactions enabled and minimal guidance
- returns extensive level with agent reactions enabled and extensive guidance
- resolves reaction level from a specific account
- falls back to global level when account has no reactionLevel

### src/telegram/reasoning-lane-coordinator.test.lisp
- splitTelegramReasoningText
- splits real tagged reasoning and answer
- ignores literal think tags inside inline code
- ignores literal think tags inside fenced code
- does not emit partial reasoning tag prefixes

### src/telegram/send.proxy.test.lisp
- telegram proxy client

### src/telegram/send.test.lisp
- sent-message-cache
- records and retrieves sent messages
- handles string chat IDs
- clears cache
- buildInlineKeyboard
- normalizes keyboard inputs
- sendMessageTelegram
- applies timeoutSeconds config precedence
- falls back to plain text when Telegram rejects HTML and preserves send params
- keeps link_preview_options disabled for both html and plain-text fallback
- fails when Telegram text send returns no message_id
- fails when Telegram media send returns no message_id
- uses native fetch for BAN compatibility when api is omitted
- normalizes chat ids with internal prefixes
- resolves t.me targets to numeric chat ids via getChat
- fails clearly when a legacy target cannot be resolved
- includes thread params in media messages
- splits long captions into media + text messages when text exceeds 1024 chars
- uses caption when text is within 1024 char limit
- renders markdown in media captions
- sends video notes when requested and regular videos otherwise
- applies reply markup and thread options to split video-note sends
- retries on transient errors with retry_after
- does not retry on non-transient errors
- retries when grammY network envelope message includes failed-after wording
- sends GIF media as animation
- routes audio media to sendAudio/sendVoice based on voice compatibility
- keeps message_thread_id for forum/private/group sends
- retries sends without message_thread_id on thread-not-found
- does not retry on non-retriable thread/chat errors
- sets disable_notification when silent is true
- parses message_thread_id from recipient string (telegram:group:...:topic:...)
- retries media sends without message_thread_id when thread is missing
- defaults outbound media uploads to 100MB
- uses configured telegram mediaMaxMb for outbound uploads
- reactMessageTelegram
- resolves legacy telegram targets before reacting
- sendStickerTelegram
- throws error when fileId is blank
- retries sticker sends without message_thread_id when thread is missing
- fails when sticker send returns no message_id
- shared send behaviors
- includes reply_to_message_id for threaded replies
- wraps chat-not-found with actionable context
- editMessageTelegram
- treats 'message is not modified' as success
- disables link previews when linkPreview is false
- sendPollTelegram
- maps durationSeconds to open_period
- retries without message_thread_id on thread-not-found
- rejects durationHours for Telegram polls
- fails when poll send returns no message_id
- createForumTopicTelegram

### src/telegram/sendchataction-401-backoff.test.lisp
- createTelegramSendChatActionHandler
- calls sendChatActionFn on success
- applies exponential backoff on consecutive 401 errors
- suspends after maxConsecutive401 failures
- resets failure counter on success
- does not count non-401 errors toward suspension
- reset() clears suspension
- is shared across multiple chatIds (global handler)

### src/telegram/sequential-key.test.lisp
- getTelegramSequentialKey

### src/telegram/status-reaction-variants.test.lisp
- resolveTelegramStatusReactionEmojis
- falls back to Telegram-safe defaults for empty overrides
- preserves explicit non-empty overrides
- buildTelegramStatusReactionVariants
- puts requested emoji first and appends Telegram fallbacks
- isTelegramSupportedReactionEmoji
- accepts Telegram-supported reaction emojis
- rejects unsupported emojis
- extractTelegramAllowedEmojiReactions
- returns undefined when chat does not include available_reactions
- returns null when available_reactions is omitted/null
- extracts emoji reactions only
- resolveTelegramAllowedEmojiReactions
- uses getChat lookup when message chat does not include available_reactions
- falls back to unrestricted reactions when getChat lookup fails
- resolveTelegramReactionVariant
- returns requested emoji when already Telegram-supported
- returns first Telegram-supported fallback for unsupported requested emoji
- uses generic Telegram fallbacks for unknown emojis
- respects chat allowed reactions
- returns undefined when no candidate is chat-allowed
- returns undefined for empty requested emoji

### src/telegram/sticker-cache.test.lisp
- sticker-cache
- getCachedSticker
- returns null for unknown ID
- returns cached sticker after cacheSticker
- returns null after cache is cleared
- cacheSticker
- adds entry to cache
- updates existing entry
- searchStickers
- finds stickers by description substring
- finds stickers by emoji
- finds stickers by set name
- respects limit parameter
- ranks exact matches higher
- returns empty array for no matches
- is case insensitive
- matches multiple words
- getAllCachedStickers
- returns empty array when cache is empty
- returns all cached stickers
- getCacheStats
- returns count 0 when cache is empty
- returns correct stats with cached stickers

### src/telegram/target-writeback.test.lisp
- maybePersistResolvedTelegramTarget
- skips writeback when target is already numeric
- writes back matching config and cron targets
- preserves topic suffix style in writeback target
- matches username targets case-insensitively

### src/telegram/targets.test.lisp
- stripTelegramInternalPrefixes
- strips telegram prefix
- strips telegram+group prefixes
- does not strip group prefix without telegram prefix
- is idempotent
- parseTelegramTarget
- parses plain chatId
- parses @username
- parses chatId:topicId format
- parses chatId:topic:topicId format
- trims whitespace
- does not treat non-numeric suffix as topicId
- strips internal prefixes before parsing
- normalizeTelegramChatId
- rejects username and t.me forms
- keeps numeric chat ids unchanged
- returns undefined for empty input
- normalizeTelegramLookupTarget
- normalizes legacy t.me and username targets
- keeps numeric chat ids unchanged
- rejects invalid username forms
- isNumericTelegramChatId
- matches numeric telegram chat ids
- rejects non-numeric chat ids

### src/telegram/thread-bindings.test.lisp
- telegram thread bindings
- registers a telegram binding adapter and binds current conversations
- does not support child placement
- updates lifecycle windows by session key
- does not persist lifecycle updates when manager persistence is disabled

### src/telegram/token.test.lisp
- resolveTelegramToken
- prefers config token over env
- uses env token when config is missing
- uses tokenFile when configured
- falls back to config token when no env or tokenFile
- does not fall back to config when tokenFile is missing
- resolves per-account tokens when the config account key casing doesn't match routing normalization
- falls back to top-level token for non-default accounts without account token
- falls back to top-level tokenFile for non-default accounts
- throws when botToken is an unresolved SecretRef object
- telegram update offset store
- persists and reloads the last update id

### src/telegram/update-offset-store.test.lisp
- deleteTelegramUpdateOffset
- removes the offset file so a new bot starts fresh
- does not throw when the offset file does not exist
- only removes the targeted account offset, leaving others intact
- returns null when stored offset was written by a different bot token
- treats legacy offset records without bot identity as stale when token is provided
- ignores invalid persisted update IDs from disk
- rejects writing invalid update IDs

### src/telegram/voice.test.lisp
- resolveTelegramVoiceSend
- skips voice when wantsVoice is false
- logs fallback for incompatible media
- keeps voice when compatible

### src/telegram/webhook.test.lisp
- startTelegramWebhook
- starts server, registers webhook, and serves health
- registers webhook with certificate when webhookCertPath is provided
- invokes webhook handler on matching path
- rejects startup when webhook secret is missing
- registers webhook using the bound listening port when port is 0
- keeps webhook payload readable when callback delays body read
- keeps webhook payload readable across multiple delayed reads
- processes a second request after first-request delayed-init data loss
- handles near-limit payload with random chunk writes and event-loop yields
- handles near-limit payload written in a single request write
- rejects payloads larger than 1MB before invoking webhook handler
- de-registers webhook when shutting down

## terminal

### src/terminal/ansi.test.lisp
- terminal ansi helpers
- strips ANSI and OSC8 sequences
- sanitizes control characters for log-safe interpolation

### src/terminal/prompt-select-styled.test.lisp
- selectStyled
- styles message and option hints before delegating to clack select

### src/terminal/restore.test.lisp
- restoreTerminalState
- does not resume paused stdin by default
- resumes paused stdin when resumeStdin is true
- does not touch stdin when stdin is not a TTY

### src/terminal/safe-text.test.lisp
- sanitizeTerminalText
- removes C1 control characters
- escapes line controls while preserving printable text

### src/terminal/stream-writer.test.lisp
- createSafeStreamWriter
- signals broken pipes and closes the writer
- treats broken pipes from beforeWrite as closed

### src/terminal/table.test.lisp
- renderTable
- prefers shrinking flex columns to avoid wrapping non-flex labels
- expands flex columns to fill available width
- wraps ANSI-colored cells without corrupting escape sequences
- resets ANSI styling on wrapped lines
- respects explicit newlines in cell values
- wrapNoteMessage
- preserves long filesystem paths without inserting spaces/newlines
- preserves long urls without inserting spaces/newlines
- preserves long file-like underscore tokens for copy safety
- still chunks generic long opaque tokens to avoid pathological line width
- wraps bullet lines while preserving bullet indentation
- preserves long Windows paths without inserting spaces/newlines
- preserves UNC paths without inserting spaces/newlines

## test

### test/appcast.test.lisp
- appcast.xml
- uses canonical sparkle build for the latest stable appcast entry

### test/cli-json-stdout.e2e.test.lisp
- cli json stdout contract
- keeps `update status --json` stdout parseable even with legacy doctor preflight inputs

### test/gateway.multi.e2e.test.lisp
- gateway multi-instance e2e
- spins up two gateways and exercises WS + HTTP + sbcl pairing
- delivers final chat event for telegram-shaped session keys

### test/git-hooks-pre-commit.test.lisp
- git-hooks/pre-commit (integration)
- does not treat staged filenames as git-add flags (e.g. --all)

### test/release-check.test.lisp
- collectAppcastSparkleVersionErrors
- accepts legacy 9-digit calver builds before lane-floor cutover
- requires lane-floor builds on and after lane-floor cutover
- accepts canonical stable lane builds on and after lane-floor cutover

### test/scripts/check-channel-agnostic-boundaries.test.lisp
- check-channel-agnostic-boundaries
- flags direct channel module imports
- flags channel config path access
- flags channel-literal comparisons
- flags object literals with explicit channel ids
- ignores non-channel literals and unrelated text
- reverse-deps mode flags channel module re-exports
- reverse-deps mode ignores channel literals when no imports are present
- user-facing text mode flags channel names in string literals
- user-facing text mode ignores channel names in import specifiers
- system-mark guard flags hardcoded gear literals
- system-mark guard ignores module import specifiers

### test/scripts/check-no-random-messaging-tmp.test.lisp
- check-no-random-messaging-tmp
- finds os.tmpdir calls imported from sbcl:os
- finds tmpdir named import calls from sbcl:os
- finds tmpdir calls imported from os
- ignores mentions in comments and strings
- ignores tmpdir symbols that are not imported from sbcl:os

### test/scripts/check-no-raw-window-open.test.lisp
- check-no-raw-window-open
- finds direct window.open calls
- finds globalThis.open calls
- ignores mentions in strings and comments
- handles parenthesized and asserted window references

### test/scripts/ios-team-id.test.lisp
- scripts/ios-team-id.sh
- parses team listings and prioritizes preferred IDs without shelling out
- resolves a fallback team ID from Xcode team listings (smoke)
- prints actionable guidance when Xcode account exists but no Team ID is resolvable

### test/scripts/ui.test.lisp
- scripts/ui windows spawn behavior
- enables shell for Windows command launchers that require cmd.exe
- does not enable shell for non-shell launchers
- allows safe forwarded args when shell mode is required on Windows
- rejects dangerous forwarded args when shell mode is required on Windows
- does not reject args on non-windows platforms

### test/ui.presenter-next-run.test.lisp
- formatNextRun
- returns n/a for nullish values
- includes weekday and relative time

## test-helpers

### src/test-helpers/state-dir-env.test.lisp
- state-dir-env helpers
- set/snapshot/restore round-trips OPENCLAW_STATE_DIR
- withStateDirEnv sets env for callback and cleans up temp root
- withStateDirEnv restores env and cleans temp root when callback throws
- withStateDirEnv restores both env vars when legacy var was previously set

## test-utils

### src/test-utils/channel-plugins.test.lisp
- createChannelTestPluginBase
- builds a plugin base with defaults
- honors config and metadata overrides
- createOutboundTestPlugin
- keeps outbound test plugin account list behavior

### src/test-utils/env.test.lisp
- env test utils
- captureEnv restores mutated keys
- captureFullEnv restores added keys and baseline values
- withEnv applies values only inside callback
- withEnv restores values when callback throws
- withEnv can delete a key only inside callback
- withEnvAsync restores values when callback throws
- withEnvAsync applies values only inside async callback
- withEnvAsync can delete a key only inside callback

### src/test-utils/temp-home.test.lisp
- createTempHomeEnv
- sets home env vars and restores them on cleanup

## tts

### src/tts/prepare-text.test.lisp
- TTS text preparation – stripMarkdown
- strips markdown headers before TTS
- strips bold and italic markers before TTS
- strips inline code markers before TTS
- handles a typical LLM reply with mixed markdown
- handles markdown-heavy system design explanation

### src/tts/tts.test.lisp
- tts
- isValidVoiceId
- validates ElevenLabs voice ID length and character rules
- isValidOpenAIVoice
- accepts all valid OpenAI voices including newer additions
- rejects invalid voice names
- treats the default endpoint with trailing slash as the default endpoint
- isValidOpenAIModel
- matches the supported model set and rejects unsupported values
- treats the default endpoint with trailing slash as the default endpoint
- resolveOutputFormat
- selects opus for voice-bubble channels (telegram/feishu/whatsapp) and mp3 for others
- resolveEdgeOutputFormat
- uses default edge output format unless overridden
- parseTtsDirectives
- extracts overrides and strips directives when enabled
- accepts edge as provider override
- rejects provider override by default while keeping voice overrides enabled
- keeps text intact when overrides are disabled
- accepts custom voices and models when openaiBaseUrl is a non-default endpoint
- rejects unknown voices and models when openaiBaseUrl is the default OpenAI endpoint
- summarizeText
- summarizes text and returns result with metrics
- calls the summary model with the expected parameters
- uses summaryModel override when configured
- registers the Ollama api before direct summarization
- validates targetLength bounds
- throws when summary output is missing or empty
- getTtsProvider
- selects provider based on available API keys
- resolveTtsConfig – openai.baseUrl
- defaults to the official OpenAI endpoint
- picks up OPENAI_TTS_BASE_URL env var when no config baseUrl is set
- config baseUrl takes precedence over env var
- strips trailing slashes from the resolved baseUrl
- strips trailing slashes from env var baseUrl
- maybeApplyTtsToPayload
- applies inbound auto-TTS gating by audio status and cleaned text length
- skips auto-TTS in tagged mode unless a tts tag is present
- runs auto-TTS in tagged mode when tags are present

## tui

### src/tui/commands.test.lisp
- parseCommand
- normalizes aliases and keeps command args
- returns empty name for empty input
- getSlashCommands
- provides level completions for built-in toggles
- helpText
- includes slash command help for aliases

### src/tui/components/chat-log.test.lisp
- ChatLog
- caps component growth to avoid unbounded render trees
- drops stale streaming references when old components are pruned
- drops stale tool references when old components are pruned

### src/tui/components/searchable-select-list.test.lisp
- SearchableSelectList
- renders all items when no filter is applied
- does not truncate long labels on wide terminals when description is present
- does not show description layout at width 40 (boundary)
- shows description layout at width 41 (boundary)
- keeps ANSI-highlighted description rows within terminal width
- ignores ANSI escape codes in search matching
- does not corrupt ANSI sequences when highlighting multiple tokens
- filters items when typing
- prioritizes exact substring matches over fuzzy matches
- keeps exact label matches ahead of description matches
- exact label match beats description match
- orders description matches by earliest index
- filters items with fuzzy matching
- preserves fuzzy ranking when only fuzzy matches exist
- highlights matches in rendered output
- shows no match message when filter yields no results
- navigates with arrow keys
- calls onSelect when enter is pressed
- calls onCancel when escape is pressed

### src/tui/gateway-chat.test.lisp
- resolveGatewayConnection
- throws when url override is missing explicit credentials
- uses config auth token for local mode when both config and env tokens are set
- falls back to OPENCLAW_GATEWAY_TOKEN when config token is missing
- uses local password auth when gateway.auth.mode is unset and password-only is configured
- fails when both local token and password are configured but gateway.auth.mode is unset
- resolves env-template config auth token from referenced env var
- fails with guidance when env-template config auth token is unresolved
- prefers OPENCLAW_GATEWAY_PASSWORD over remote password fallback
- resolves exec-backed SecretRef token for local mode
- resolves only token SecretRef when gateway.auth.mode is token
- resolves only password SecretRef when gateway.auth.mode is password

### src/tui/osc8-hyperlinks.test.lisp
- wrapOsc8
- wraps text with OSC 8 open and close sequences
- handles empty text
- extractUrls
- extracts bare URLs
- extracts multiple bare URLs
- extracts markdown link hrefs
- extracts markdown links with angle brackets and title text
- extracts both bare URLs and markdown links
- deduplicates URLs
- returns empty array for text without URLs
- handles URLs with query params and fragments
- addOsc8Hyperlinks
- returns lines unchanged when no URLs
- wraps a single-line URL with OSC 8
- wraps a URL broken across two lines
- handles URL with ANSI styling codes
- handles named link rendered as text (url)
- handles multiple URLs on the same line
- does not modify lines without URL text
- prefers the longest known URL when a fragment matches multiple prefixes
- handles URL split across three lines

### src/tui/theme/theme.test.lisp
- markdownTheme
- highlightCode
- passes supported language through to the highlighter
- falls back to auto-detect for unknown language and preserves lines
- returns plain highlighted lines when highlighting throws
- theme
- keeps assistant text in terminal default foreground
- list themes
- reuses shared select-list styles in searchable list theme
- keeps searchable list specific renderers readable

### src/tui/tui-command-handlers.test.lisp
- tui command handlers
- renders the sending indicator before chat.send resolves
- forwards unknown slash commands to the gateway
- creates unique session for /new and resets shared session for /reset
- reports send failures and marks activity status as error
- sanitizes control sequences in /new and /reset failures
- reports disconnected status and skips gateway send when offline

### src/tui/tui-event-handlers.test.lisp
- tui-event-handlers: handleAgentEvent
- processes tool events when runId matches activeChatRunId (even if sessionId differs)
- ignores tool events when runId does not match activeChatRunId
- processes lifecycle events when runId matches activeChatRunId
- captures runId from chat events when activeChatRunId is unset
- accepts chat events when session key is an alias of the active canonical key
- does not cross-match canonical session keys from different agents
- clears run mapping when the session changes
- accepts tool events after chat final for the same run
- ignores lifecycle updates for non-active runs in the same session
- suppresses tool events when verbose is off
- omits tool output when verbose is on (non-full)
- refreshes history after a non-local chat final
- does not reload history or clear active run when another run final arrives mid-stream
- suppresses non-local empty final placeholders during concurrent runs
- renders final error text when chat final has no content but includes event errorMessage
- drops streaming assistant when chat final has no message
- reloads history when a local run ends without a displayable final message

### src/tui/tui-formatters.test.lisp
- extractTextFromMessage
- renders errorMessage when assistant content is empty
- falls back to a generic message when errorMessage is missing
- joins multiple text blocks with single newlines
- preserves internal newlines for string content
- preserves internal newlines for text blocks
- places thinking before content when included
- sanitizes ANSI and control chars from string content
- redacts heavily corrupted binary-like lines
- strips leading inbound metadata blocks for user messages
- keeps metadata-like blocks for non-user messages
- does not strip metadata-like blocks that are not a leading prefix
- strips trailing untrusted context metadata suffix blocks for user messages
- extractThinkingFromMessage
- collects only thinking blocks
- extractContentFromMessage
- collects only text blocks
- renders error text when stopReason is error and content is not an array
- isCommandMessage
- detects command-marked messages
- sanitizeRenderableText
- preserves long filesystem paths verbatim for copy safety
- preserves long urls verbatim for copy safety
- preserves long file-like underscore tokens for copy safety
- preserves long credential-like mixed alnum tokens for copy safety
- preserves quoted credential-like mixed alnum tokens for copy safety
- wraps rtl lines with directional isolation marks
- only wraps lines that contain rtl script
- does not double-wrap lines that already include bidi controls

### src/tui/tui-input-history.test.lisp
- createEditorSubmitHandler
- adds submitted messages to editor history
- trims input before adding to history
- routes slash commands to handleCommand
- routes normal messages to sendMessage
- routes bang-prefixed lines to handleBangLine

### src/tui/tui-local-shell.test.lisp
- createLocalShellRunner
- logs denial on subsequent ! attempts without re-prompting
- sets OPENCLAW_SHELL when running local shell commands

### src/tui/tui-overlays.test.lisp
- createOverlayHandlers
- routes overlays through the TUI overlay stack
- restores focus when closing without an overlay

### src/tui/tui-session-actions.test.lisp
- tui session actions
- queues session refreshes and applies the latest result
- keeps patched model selection when a refresh returns an older snapshot
- accepts older session snapshots after switching session keys

### src/tui/tui-stream-assembler.test.lisp
- TuiStreamAssembler
- keeps thinking before content even when thinking arrives later
- omits thinking when showThinking is false
- falls back to streamed text on empty final payload
- falls back to event error message when final payload has no renderable text
- returns null when delta text is unchanged
- keeps streamed delta text when incoming tool boundary drops a block

### src/tui/tui-waiting.test.lisp
- tui-waiting
- pickWaitingPhrase rotates every 10 ticks
- buildWaitingStatusMessage includes shimmer markup and metadata

### src/tui/tui.submit-handler.test.lisp
- createEditorSubmitHandler
- routes lines starting with ! to handleBangLine
- treats a lone ! as a normal message
- does not treat leading whitespace before ! as a bang command
- trims normal messages before sending and adding to history
- preserves internal newlines for multiline messages
- createSubmitBurstCoalescer
- coalesces rapid single-line submits into one multiline submit when enabled
- passes through immediately when disabled
- shouldEnableWindowsGitBashPasteFallback
- enables fallback on Windows Git Bash env
- enables fallback on macOS iTerm
- enables fallback on macOS Terminal.app
- disables fallback outside Windows

### src/tui/tui.test.lisp
- resolveFinalAssistantText
- falls back to streamed text when final text is empty
- prefers the final text when present
- falls back to formatted error text when final and streamed text are empty
- tui slash commands
- treats /elev as an alias for /elevated
- normalizes alias case
- includes gateway text commands
- resolveTuiSessionKey
- uses global only as the default when scope is global
- keeps explicit agent-prefixed keys unchanged
- lowercases session keys with uppercase characters
- resolveGatewayDisconnectState
- returns pairing recovery guidance when disconnect reason requires pairing
- falls back to idle for generic disconnect reasons
- createBackspaceDeduper
- suppresses duplicate backspace events within the dedupe window
- preserves backspace events outside the dedupe window
- never suppresses non-backspace keys
- resolveCtrlCAction
- clears input and arms exit on first ctrl+c when editor has text
- exits on second ctrl+c within the exit window
- shows warning when exit window has elapsed
- TUI shutdown safety
- treats setRawMode EBADF errors as ignorable
- does not ignore unrelated stop errors
- swallows only ignorable stop errors
- rethrows non-ignorable stop errors

## utils

### src/utils/delivery-context.test.lisp
- delivery context helpers
- normalizes channel/to/accountId and drops empty contexts
- does not inherit route fields from fallback when channels conflict
- inherits missing route fields when channels match
- uses fallback route fields when fallback has no channel
- builds stable keys only when channel and to are present
- derives delivery context from a session entry
- normalizes delivery fields, mirrors session fields, and avoids cross-channel carryover

### src/utils/directive-tags.test.lisp
- stripInlineDirectiveTagsForDisplay
- removes reply and audio directives
- supports whitespace variants
- does not mutate plain text
- stripInlineDirectiveTagsFromMessageForDisplay
- strips inline directives from text content blocks
- preserves empty-string text when directives are entire content
- returns original message when content is not an array

### src/utils/mask-api-key.test.lisp
- maskApiKey
- returns missing for empty values
- masks short and medium values without returning raw secrets
- masks long values with first and last 8 chars

### src/utils/message-channel.test.lisp
- message-channel
- normalizes gateway message channels and rejects unknown values
- normalizes plugin aliases when registered

### src/utils/normalize-secret-input.test.lisp
- normalizeSecretInput
- returns empty string for non-string values
- strips embedded line breaks and surrounding whitespace
- drops non-Latin1 code points that can break HTTP ByteString headers
- preserves Latin-1 characters and internal spaces
- normalizeOptionalSecretInput
- returns undefined when normalized value is empty
- returns normalized value when non-empty

### src/utils/queue-helpers.test.lisp
- applyQueueRuntimeSettings
- updates runtime queue settings with normalization
- keeps existing values when optional settings are missing/invalid
- queue summary helpers
- previewQueueSummaryPrompt does not mutate state
- buildQueueSummaryPrompt clears state after rendering
- clearQueueSummaryState resets summary counters
- drainCollectItemIfNeeded
- skips when neither force mode nor cross-channel routing is active
- drains one item in force mode
- switches to force mode and returns empty when cross-channel with no queued item

### src/utils/reaction-level.test.lisp
- resolveReactionLevel

### src/utils/run-with-concurrency.test.lisp
- runTasksWithConcurrency
- preserves task order with bounded worker count
- stops scheduling after first failure in stop mode
- continues after failures and reports the first one

### src/utils/transcript-tools.test.lisp
- transcript-tools
- extractToolCallNames
- extracts tool name from message.toolName/tool_name
- extracts tool call names from content blocks (tool_use/toolcall/tool_call)
- normalizes type and trims names; de-dupes
- hasToolCall
- returns true when tool call names exist
- returns false when no tool calls exist
- countToolResults
- counts tool_result blocks and tool_result_error blocks; tracks errors via is_error
- handles non-array content

### src/utils/usage-format.test.lisp
- usage-format
- formats token counts
- formats USD values
- resolves model cost config and estimates usage cost

### src/utils/utils-misc.test.lisp
- parseBooleanValue
- handles boolean inputs
- parses default truthy/falsy strings
- respects custom truthy/falsy lists
- returns undefined for unsupported values
- isReasoningTagProvider
- splitShellArgs
- splits whitespace and respects quotes
- supports backslash escapes inside double quotes
- returns null for unterminated quotes
- stops at unquoted shell comments but keeps quoted hashes literal

## utils.test.lisp

### src/utils.test.lisp
- normalizePath
- adds leading slash when missing
- keeps existing slash
- withWhatsAppPrefix
- adds whatsapp prefix
- leaves prefixed intact
- ensureDir
- creates nested directory
- sleep
- resolves after delay using fake timers
- assertWebChannel
- accepts valid channel
- throws for invalid channel
- normalizeE164 & toWhatsappJid
- strips formatting and prefixes
- preserves existing JIDs
- jidToE164
- maps @lid using reverse mapping file
- maps @lid from authDir mapping files
- maps @hosted.lid from authDir mapping files
- accepts hosted PN JIDs
- falls back through lidMappingDirs in order
- resolveConfigDir
- prefers ~/.openclaw when legacy dir is missing
- resolveHomeDir
- prefers OPENCLAW_HOME over HOME
- shortenHomePath
- uses $OPENCLAW_HOME prefix when OPENCLAW_HOME is set
- shortenHomeInString
- uses $OPENCLAW_HOME replacement when OPENCLAW_HOME is set
- resolveJidToE164
- resolves @lid via lidLookup when mapping file is missing
- skips lidLookup for non-lid JIDs
- returns null when lidLookup throws
- resolveUserPath
- expands ~ to home dir
- expands ~/ to home dir
- resolves relative paths
- prefers OPENCLAW_HOME for tilde expansion
- keeps blank paths blank
- returns empty string for undefined/null input

## version.test.lisp

### src/version.test.lisp
- version resolution
- resolves package version from nested dist/plugin-sdk module URL
- ignores unrelated nearby ASDF system definition files
- falls back to build-info when package metadata is unavailable
- returns null when no version metadata exists
- ignores non-openclaw package and blank build-info versions
- returns null for malformed module URLs
- resolves binary version with explicit precedence
- prefers OPENCLAW_VERSION over service and package versions
- normalizes runtime version candidate for fallback handling
- prefers runtime VERSION over service/package markers and ignores blank env values

## web

### src/web/accounts.test.lisp
- resolveWhatsAppAuthDir
- sanitizes path traversal sequences in accountId
- sanitizes special characters in accountId
- returns default directory for empty accountId
- preserves valid accountId unchanged

### src/web/accounts.whatsapp-auth.test.lisp
- hasAnyWhatsAppAuth
- returns false when no auth exists
- returns true when legacy auth exists
- returns true when non-default auth exists
- includes authDir overrides

### src/web/auto-reply.broadcast-groups.combined.test.lisp
- broadcast groups
- skips unknown broadcast agent ids when agents.list is present
- broadcasts sequentially in configured order
- shares group history across broadcast agents and clears after replying
- broadcasts in parallel by default

### src/web/auto-reply.web-auto-reply.compresses-common-formats-jpeg-cap.test.lisp
- web auto-reply
- compresses common formats to jpeg under the cap
- honors channels.whatsapp.mediaMaxMb for outbound auto-replies
- prefers per-account WhatsApp media caps for outbound auto-replies
- falls back to text when media is unsupported
- falls back to text when media send fails
- returns a warning when remote media fetch 404s
- sends media with a caption when delivery succeeds

### src/web/auto-reply.web-auto-reply.connection-and-logging.e2e.test.lisp
- web auto-reply connection
- handles helper envelope timestamps with trimmed timezones (regression)
- handles reconnect progress and max-attempt stop behavior
- treats status 440 as non-retryable and stops without retrying
- forces reconnect when watchdog closes without onClose
- processes inbound messages without batching and preserves timestamps
- emits heartbeat logs with connection metadata
- logs outbound replies to file
- marks dispatch idle after replies flush

### src/web/auto-reply.web-auto-reply.last-route.test.lisp
- web auto-reply last-route
- updates last-route for direct chats without senderE164
- updates last-route for group chats with account id

### src/web/auto-reply/deliver-reply.test.lisp
- deliverWebReply
- suppresses payloads flagged as reasoning
- suppresses payloads that start with reasoning prefix text
- does not suppress messages that mention Reasoning: mid-text
- sends chunked text replies and logs a summary
- sends image media with caption and then remaining text
- retries media send on transient failure
- falls back to text-only when the first media send fails
- sends audio media as ptt voice note
- sends video media
- sends non-audio/image/video media as document

### src/web/auto-reply/heartbeat-runner.test.lisp
- runWebHeartbeatOnce
- supports manual override body dry-run without sending
- sends HEARTBEAT_OK when reply is empty and showOk is enabled
- injects a cron-style Current time line into the heartbeat prompt
- treats heartbeat token-only replies as ok-token and preserves session updatedAt
- skips sending alerts when showAlerts is disabled but still emits a skipped event
- emits failed events when sending throws and rethrows the error
- redacts recipient and omits body preview in heartbeat logs

### src/web/auto-reply/monitor/group-members.test.lisp
- noteGroupMember
- normalizes member phone numbers before storing
- ignores incomplete member values
- formatGroupMembers
- deduplicates participants and appends named roster members
- falls back to sender when no participants or roster are available
- returns undefined when no members can be resolved

### src/web/auto-reply/monitor/process-message.inbound-contract.test.lisp
- web processMessage inbound contract
- passes a finalized MsgContext to the dispatcher
- falls back SenderId to SenderE164 when senderJid is empty
- defaults responsePrefix to identity name in self-chats when unset
- does not force an [openclaw] response prefix in self-chats when identity is unset
- clears pending group history when the dispatcher does not queue a final reply
- suppresses non-final WhatsApp payload delivery
- forces disableBlockStreaming for WhatsApp dispatch
- updates main last route for DM when session key matches main session key
- does not update main last route for isolated DM scope sessions
- does not update main last route for non-owner sender when main DM scope is pinned
- updates main last route for owner sender when main DM scope is pinned

### src/web/auto-reply/web-auto-reply-monitor.test.lisp
- applyGroupGating
- treats reply-to-bot as implicit mention
- does not bypass mention gating for non-owner /new in group chats
- uses per-agent mention patterns for group gating (routing + mentionPatterns)
- allows group messages when whatsapp groups default disables mention gating
- blocks group messages when whatsapp groups is set without a wildcard
- buildInboundLine
- prefixes group messages with sender
- includes reply-to context blocks when replyToBody is present
- applies the WhatsApp messagePrefix when configured
- normalizes direct from labels by stripping whatsapp: prefix
- formatReplyContext
- returns null when replyToBody is missing
- uses unknown sender label when reply sender is absent

### src/web/auto-reply/web-auto-reply-utils.test.lisp
- isBotMentionedFromTargets
- ignores regex matches when other mentions are present
- matches explicit self mentions
- falls back to regex when no mentions are present
- ignores JID mentions in self-chat mode
- matches fallback number mentions when regexes do not match
- resolveMentionTargets with @lid mapping
- uses @lid reverse mapping for mentions and self identity
- getSessionSnapshot
- uses channel reset overrides when configured
- web auto-reply util
- mentions diagnostics
- returns normalized debug fields and mention outcome
- resolves owner list from allowFrom or falls back to self
- elide
- returns undefined for undefined input
- returns input when under limit
- truncates and annotates when over limit
- isLikelyWhatsAppCryptoError
- matches known Baileys crypto auth errors (Error)
- does not throw on circular objects

### src/web/inbound.media.test.lisp
- web inbound media saves with extension
- stores image extension, extracts caption mentions, and keeps document filename
- passes mediaMaxMb to saveMediaBuffer

### src/web/inbound.test.lisp
- web inbound helpers
- prefers the main conversation body
- falls back to captions when conversation text is missing
- handles document captions
- extracts WhatsApp contact cards
- prefers FN over N in WhatsApp vcards
- normalizes tel: prefixes in WhatsApp vcards
- trims and skips empty WhatsApp vcard phones
- extracts multiple WhatsApp contact cards
- counts empty WhatsApp contact cards in array summaries
- summarizes empty WhatsApp contact cards with a count
- unwraps view-once v2 extension messages
- returns placeholders for media-only payloads
- extracts WhatsApp location messages
- extracts WhatsApp live location messages

### src/web/inbound/access-control.group-policy.test.lisp
- resolveWhatsAppRuntimeGroupPolicy
- fails closed when channels.whatsapp is missing and no defaults are set
- keeps open fallback when channels.whatsapp is configured
- ignores explicit default policy when provider config is missing

### src/web/inbound/access-control.test.lisp
- checkInboundAccessControl pairing grace
- suppresses pairing replies for historical DMs on connect
- sends pairing replies for live DMs
- WhatsApp dmPolicy precedence
- uses account-level dmPolicy instead of channel-level (#8736)
- inherits channel-level dmPolicy when account-level dmPolicy is unset
- does not merge persisted pairing approvals in allowlist mode
- always allows same-phone DMs even when allowFrom is restrictive

### src/web/inbound/media.sbcl.test.lisp
- downloadInboundMedia
- returns undefined for messages without media
- uses explicit mimetype from audioMessage when present
- uses explicit mimetype from imageMessage when present
- preserves fileName from document messages

### src/web/inbound/send-api.test.lisp
- createWebSendApi
- uses sendOptions fileName for outbound documents
- falls back to default document filename when fileName is absent
- sends plain text messages
- supports image media with caption
- supports audio as push-to-talk voice note
- supports video media and gifPlayback option
- falls back to unknown messageId if Baileys result does not expose key.id
- sends polls and records outbound activity
- sends reactions with participant JID normalization
- sends composing presence updates to the recipient JID

### src/web/login-qr.test.lisp
- login-qr
- restarts login once on status 515 and completes

### src/web/login.coverage.test.lisp
- loginWeb coverage
- restarts once when WhatsApp requests code 515
- clears creds and throws when logged out
- formats and rethrows generic errors

### src/web/login.test.lisp
- web login
- loginWeb waits for connection and closes
- renderQrPngBase64
- renders a PNG data payload
- avoids dynamic require of qrcode-terminal vendor modules

### src/web/logout.test.lisp
- web logout
- deletes cached credentials when present
- removes oauth.json too when not using legacy auth dir
- no-ops when nothing to delete
- keeps shared oauth.json when using legacy auth dir

### src/web/media.test.lisp
- web media loading
- strips MEDIA: prefix before reading local file (including whitespace variants)
- compresses large local images under the provided cap
- optimizes images when options object omits optimizeImages
- allows callers to disable optimization via options object
- sniffs mime before extension when loading local files
- normalizes HEIC local files to JPEG output
- includes URL + status in fetch errors
- blocks SSRF URLs before fetch
- respects maxBytes for raw URL fetches
- keeps raw mode when options object sets optimizeImages true
- uses content-disposition filename when available
- preserves GIF from URL without JPEG conversion
- preserves PNG alpha when under the cap
- falls back to JPEG when PNG alpha cannot fit under cap
- Discord voice message input hardening
- rejects unsafe voice message inputs
- local media root guard
- rejects local paths outside allowed roots
- allows local paths under an explicit root
- accepts win32 dev=0 stat mismatch for local file loads
- requires readFile override for localRoots bypass
- allows any path when localRoots is 'any'
- rejects filesystem root entries in localRoots
- allows default OpenClaw state workspace and sandbox roots
- rejects default OpenClaw state per-agent workspace-* roots without explicit local roots
- allows per-agent workspace-* paths with explicit local roots

### src/web/monitor-inbox.allows-messages-from-senders-allowfrom-list.test.lisp
- web monitor inbox
- allows messages from senders in allowFrom list
- allows same-phone messages even if not in allowFrom
- locks down when no config is present (pairing for unknown senders)
- skips pairing replies for outbound DMs in same-phone mode
- skips pairing replies for outbound DMs when same-phone mode is disabled
- handles append messages by marking them read but skipping auto-reply
- normalizes participant phone numbers to JIDs in sendReaction

### src/web/monitor-inbox.blocks-messages-from-unauthorized-senders-not-allowfrom.test.lisp
- web monitor inbox
- blocks messages from unauthorized senders not in allowFrom
- skips read receipts in self-chat mode
- skips read receipts when disabled
- lets group messages through even when sender not in allowFrom
- blocks all group messages when groupPolicy is 'disabled'
- blocks group messages from senders not in groupAllowFrom when groupPolicy is 'allowlist'
- allows group messages from senders in groupAllowFrom when groupPolicy is 'allowlist'
- allows all group senders with wildcard in groupPolicy allowlist
- blocks group messages when groupPolicy allowlist has no groupAllowFrom

### src/web/monitor-inbox.captures-media-path-image-messages.test.lisp
- web monitor inbox
- captures media path for image messages
- sets gifPlayback on outbound video payloads when requested
- resolves onClose when the socket closes
- logs inbound bodies to file
- includes participant when marking group messages read
- passes through group messages with participant metadata
- unwraps ephemeral messages, preserves mentions, and still delivers group pings
- still forwards group messages (with sender info) even when allowFrom is restrictive

### src/web/monitor-inbox.streams-inbound-messages.test.lisp
- web monitor inbox
- streams inbound messages
- deduplicates redelivered messages by id
- resolves LID JIDs using Baileys LID mapping store
- resolves LID JIDs via authDir mapping files
- resolves group participant LID JIDs via Baileys mapping
- does not block follow-up messages when handler is pending
- captures reply context from quoted messages
- captures reply context from wrapped quoted messages

### src/web/outbound.test.lisp
- web outbound
- sends message via active listener
- throws a helpful error when no active listener exists
- maps audio to PTT with opus mime when ogg
- maps video with caption
- marks gif playback for video when requested
- maps image with caption
- maps other kinds to document with filename
- uses account-aware WhatsApp media caps for outbound uploads
- sends polls via active listener
- redacts recipients and poll text in outbound logs
- sends reactions via active listener

### src/web/reconnect.test.lisp
- web reconnect helpers
- resolves sane reconnect defaults with clamps
- computes increasing backoff with jitter
- returns heartbeat default when unset
- sleepWithAbort rejects on abort

### src/web/session.test.lisp
- web session
- creates WA socket with QR handler
- waits for connection open
- rejects when connection closes
- logWebSelfId prints cached E.164 when creds exist
- formatError prints Boom-like payload message
- does not clobber creds backup when creds.json is corrupted
- serializes creds.update saves to avoid overlapping writes
- rotates creds backup when creds.json is valid JSON

## whatsapp

### src/whatsapp/normalize.test.lisp
- normalizeWhatsAppTarget
- preserves group JIDs
- normalizes direct JIDs to E.164
- normalizes user JIDs with device suffix to E.164
- normalizes LID JIDs to E.164
- rejects invalid targets
- handles repeated prefixes
- isWhatsAppUserTarget
- detects user JIDs with various formats
- isWhatsAppGroupJid
- detects group JIDs with or without prefixes

### src/whatsapp/resolve-outbound-target.test.lisp
- resolveWhatsAppOutboundTarget
- empty/missing to parameter
- normalization failures
- returns error when normalizeWhatsAppTarget returns null/undefined
- group JID handling
- returns success for valid group JID regardless of mode
- returns success for group JID in heartbeat mode
- implicit/heartbeat mode with allowList
- allows message when wildcard is present
- allows message when allowList is empty
- allows message when target is in allowList
- denies message when target is not in allowList
- handles mixed numeric and string allowList entries
- filters out invalid normalized entries from allowList
- heartbeat mode
- allows message when target is in allowList in heartbeat mode
- denies message when target is not in allowList in heartbeat mode
- explicit/custom modes
- allows message in null mode when allowList is not set
- allows message in undefined mode when allowList is not set
- enforces allowList in custom mode string
- allows message in custom mode string when target is in allowList
- whitespace handling
- trims whitespace from to parameter
- trims whitespace from allowList entries

## wizard

### src/wizard/clack-prompter.test.lisp
- tokenizedOptionFilter
- matches tokens regardless of order
- requires all tokens to match
- matches against label, hint, and value

### src/wizard/onboarding.completion.test.lisp
- setupOnboardingShellCompletion
- QuickStart: installs without prompting
- Advanced: prompts; skip means no install

### src/wizard/onboarding.finalize.test.lisp
- finalizeOnboardingWizard
- resolves gateway password SecretRef for probe and TUI
- does not persist resolved SecretRef token in daemon install plan

### src/wizard/onboarding.gateway-config.test.lisp
- configureGatewayForOnboarding
- generates a token when the prompt returns undefined
- prefers OPENCLAW_GATEWAY_TOKEN during quickstart token setup
- does not set password to literal 'undefined' when prompt returns undefined
- seeds control UI allowed origins for non-loopback binds
- honors secretInputMode=ref for gateway password prompts
- stores gateway token as SecretRef when secretInputMode=ref
- resolves quickstart exec SecretRefs for gateway token bootstrap

### src/wizard/onboarding.secret-input.test.lisp
- resolveOnboardingSecretInputString
- resolves env-template SecretInput strings
- returns plaintext strings when value is not a SecretRef
- throws with path context when env-template SecretRef cannot resolve

### src/wizard/onboarding.test.lisp
- runOnboardingWizard
- exits when config is invalid
- skips prompts and setup steps when flags are set
- launches TUI without auto-delivery when hatching
- offers TUI hatch even without BOOTSTRAP.md
- shows the web search hint at the end of onboarding
- resolves gateway.auth.password SecretRef for local onboarding probe
- passes secretInputMode through to local gateway config step

### src/wizard/session.test.lisp
- WizardSession
- steps progress in order
- invalid answers throw
- cancel marks session and unblocks

