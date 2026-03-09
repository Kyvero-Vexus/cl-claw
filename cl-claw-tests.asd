(asdf:defsystem #:cl-claw-tests
  :description "Tests for cl-claw"
  :author "Chrysolambda"
  :license "MIT"
  :depends-on (#:cl-claw #:fiveam)
  :components ((:module "tests/cl-adapted/src/infra"
                :components
                ((:file "binaries.test")
                 (:file "retry.test")
                 (:file "abort-signal.test")
                 (:file "env.test")
                 (:file "channel-activity.test")
                 (:file "dedupe.test")
                 (:file "diagnostic-events.test")
                 (:file "fiveam-restart.test")
                 (:file "fiveam-retry-policy.test")
                 (:file "fiveam-state-migrations.test")
                 (:file "fiveam-tailnet.test")
                 (:file "fiveam-voicewake.test")
                 (:file "fiveam-fs-safe.test")
                 (:file "fiveam-net.test")))
               (:module "tests/cl-adapted/src/process"
                :components
                ((:file "fiveam-process.test")))
               (:module "tests/cl-adapted/src/logging"
                :components
                ((:file "fiveam-logging.test")))
               (:module "tests/cl-adapted/src/config"
                :components
                ((:file "fiveam-config.test")))
               (:module "tests/cl-adapted/src/secrets"
                :components
                ((:file "fiveam-secrets.test")))
               (:module "tests/cl-adapted/src/sessions"
                :components
                ((:file "fiveam-sessions.test")))
               (:module "tests/cl-adapted/src/routing"
                :components
                ((:file "fiveam-routing.test")))
               (:module "tests/cl-adapted/src/providers"
                :components
                ((:file "fiveam-providers.test")))
               (:module "tests/cl-adapted/src/memory"
                :components
                ((:file "fiveam-memory.test")))
               (:module "tests/cl-adapted/src/cron"
                :components
                ((:file "fiveam-cron.test")))
               (:module "tests/cl-adapted/src/channels"
                :components
                ((:file "fiveam-channels.test")
                 (:file "fiveam-imessage.test")))
               (:module "tests/cl-adapted/src/security"
                :components
                ((:file "fiveam-security.test")))
               (:module "tests/cl-adapted/src/agents"
                :components
                ((:file "fiveam-agents.test")))
               (:module "tests/cl-adapted/src/cli"
                :components
                ((:file "fiveam-cli.test")))
               (:module "tests/cl-adapted/src/commands"
                :components
                ((:file "fiveam-commands.test")))
               (:module "tests/cl-adapted/src/daemon"
                :components
                ((:file "fiveam-daemon.test")))
               (:module "tests/cl-adapted/src/markdown"
                :components
                ((:file "fiveam-markdown.test")))
               (:module "tests/cl-adapted/src/hooks"
                :components
                ((:file "fiveam-hooks.test")))
               (:module "tests/cl-adapted/src/media"
                :components
                ((:file "fiveam-media.test")))
               (:module "tests/cl-adapted/src/plugins"
                :components
                ((:file "fiveam-plugins.test")))
               (:module "tests/cl-adapted/src/browser"
                :components
                ((:file "fiveam-browser.test")))
               (:module "tests/cl-adapted/src/gateway"
                :components
                ((:file "fiveam-gateway-server.test")
                 (:file "fiveam-gateway-auth.test")
                 (:file "fiveam-gateway-boot.test")))
               (:module "tests/cl-adapted/src/context-engine"
                :components
                ((:file "fiveam-context-engine.test")))
               (:module "tests/cl-adapted/src/tools"
                :components
                ((:file "fiveam-tools.test")))
               (:module "tests/cl-adapted/src/channel-protocol"
                :components
                ((:file "fiveam-channel-protocol.test"))))
  :perform (asdf:test-op (op c)
             (flet ((run-suite (suite-sym pkg-name)
                      (let ((suite (find-symbol (string-upcase suite-sym)
                                                (find-package pkg-name))))
                        (when suite
                          (symbol-call :fiveam :run! suite)))))
               ;; Infra domain (existing)
               (run-suite "binaries-suite" :cl-claw.infra.binaries.test)
               (run-suite "retry-suite" :cl-claw.infra.retry.test)
               (run-suite "abort-signal-suite" :cl-claw.infra.abort-signal.test)
               (run-suite "env-suite" :cl-claw.infra.env.test)
               (run-suite "channel-activity-suite" :cl-claw.infra.channel-activity.test)
               (run-suite "dedupe-suite" :cl-claw.infra.dedupe.test)
               (run-suite "diagnostic-events-suite" :cl-claw.infra.diagnostic-events.test)
               (run-suite "restart-suite" :cl-claw.infra.restart.test)
               (run-suite "retry-policy-suite" :cl-claw.infra.retry-policy.test)
               (run-suite "state-migrations-suite" :cl-claw.infra.state-migrations.test)
               (run-suite "tailnet-suite" :cl-claw.infra.tailnet.test)
               (run-suite "voicewake-suite" :cl-claw.infra.voicewake.test)
               (run-suite "fs-safe-suite" :cl-claw.infra.fs-safe.test)
               (run-suite "net-suite" :cl-claw.infra.net.test)
               ;; P0 domains (new)
               (run-suite "process-suite" :cl-claw.process.test)
               (run-suite "logging-suite" :cl-claw.logging.test)
               (run-suite "config-suite" :cl-claw.config.test)
               (run-suite "secrets-suite" :cl-claw.secrets.test)
               (run-suite "sessions-suite" :cl-claw.sessions.test)
               (run-suite "routing-suite" :cl-claw.routing.test)
               (run-suite "providers-suite" :cl-claw.providers.test)
               (run-suite "memory-suite" :cl-claw.memory.test)
               (run-suite "cron-suite" :cl-claw.cron.test)
               (run-suite "channels-suite" :cl-claw.channels.test)
               (run-suite "channels-imessage-suite" :cl-claw.channels.imessage.test)
               (run-suite "security-suite" :cl-claw.security.test)
               (run-suite "agents-suite" :cl-claw.agents.test)
               (run-suite "cli-suite" :cl-claw.cli.test)
               (run-suite "commands-suite" :cl-claw.commands.test)
               (run-suite "daemon-suite" :cl-claw.daemon.test)
               (run-suite "markdown-suite" :cl-claw.markdown.test)
               (run-suite "hooks-suite" :cl-claw.hooks.test)
               (run-suite "media-suite" :cl-claw.media.test)
               (run-suite "plugins-suite" :cl-claw.plugins.test)
               (run-suite "browser-suite" :cl-claw.browser.test)
               ;; Gateway domain
               (run-suite "gateway-server-suite" :cl-claw.gateway.server.test)
               (run-suite "gateway-auth-suite" :cl-claw.gateway.auth.test)
               (run-suite "gateway-boot-suite" :cl-claw.gateway.boot.test)
               ;; Context engine domain
               (run-suite "context-engine-suite" :cl-claw.context-engine.test)
               ;; Tools domain
               (run-suite "tools-suite" :cl-claw.tools.test)
               ;; Channel protocol domain
               (run-suite "channel-protocol-suite" :cl-claw.channel-protocol.test))))
