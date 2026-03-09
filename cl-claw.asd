(asdf:defsystem #:cl-claw
  :description "OpenClaw Common Lisp Port"
  :author "Chrysolambda"
  :license "MIT"
  :depends-on (#:uiop #:cl-ppcre #:bordeaux-threads #:local-time #:yason #:ironclad)
  :components ((:module "src"
                :components
                ((:module "infra"
                  :components
                  ((:file "binaries")
                   (:file "retry")
                   (:file "abort-signal")
                   (:file "env")
                   (:file "channel-activity")
                   (:file "dedupe")
                   (:file "diagnostic-events")
                   (:file "restart")
                   (:file "retry-policy")
                   (:file "state-migrations")
                   (:file "tailnet")
                   (:file "voicewake")
                   (:file "fs-safe")
                   (:file "net")))
                 (:module "process"
                  :depends-on ("infra")
                  :components
                  ((:file "command-queue")
                   (:file "exec")
                   (:file "kill-tree")
                   (:file "spawn-utils")
                   (:file "supervisor")))
                 (:module "logging"
                  :depends-on ("infra")
                  :components
                  ((:file "timestamps")
                   (:file "redact")
                   (:file "logger" :depends-on ("timestamps"))))
                 (:module "config"
                  :depends-on ("infra" "logging")
                  :components
                  ((:file "schema")
                   (:file "validation")
                   (:file "io" :depends-on ("schema" "validation"))
                   (:file "runtime")))
                 (:module "secrets"
                  :depends-on ("infra" "process" "config")
                  :components
                  ((:file "storage")
                   (:file "resolve" :depends-on ("storage"))
                   (:file "audit")))
                 (:module "sessions"
                  :depends-on ("infra" "config")
                  :components
                  ((:file "store")
                   (:file "transcript" :depends-on ("store"))
                   (:file "compaction" :depends-on ("transcript"))))
                 (:module "routing"
                  :depends-on ("sessions")
                  :components
                  ((:file "core")))
                 (:module "providers"
                  :depends-on ("routing")
                  :components
                  ((:file "core")))
                 (:module "memory"
                  :depends-on ("providers")
                  :components
                  ((:file "core")))
                 (:module "cron"
                  :depends-on ("infra")
                  :components
                  ((:file "core")))
                 (:module "channels"
                  :depends-on ("routing" "sessions" "providers" "memory")
                  :components
                  ((:file "telegram")
                   (:file "irc")
                   (:file "discord")
                   (:file "signal")
                   (:file "slack")
                   (:file "imessage")))
                 (:module "agents"
                  :depends-on ("infra" "config" "sessions" "routing" "providers" "memory" "channels" "security")
                  :components
                  ((:file "core")
                   (:file "sandbox-bind-spec")
                   (:file "apply-patch")))
                 (:module "cli"
                  :depends-on ("infra" "config" "agents")
                  :components
                  ((:file "install-spec")
                   (:file "core")))
                 (:module "commands"
                  :depends-on ("cli" "agents")
                  :components
                  ((:file "core")))
                 (:module "daemon"
                  :depends-on ("commands" "cli")
                  :components
                  ((:file "core")))
                 (:module "markdown"
                  :depends-on ("channels")
                  :components
                  ((:file "core")))
                 (:module "hooks"
                  :depends-on ("routing" "channels")
                  :components
                  ((:file "core")))
                 (:module "media"
                  :depends-on ("security" "infra")
                  :components
                  ((:file "core")))
                 (:module "plugins"
                  :depends-on ("hooks" "media" "security")
                  :components
                  ((:file "core")))
                 (:module "browser"
                  :depends-on ("plugins" "daemon" "channels")
                  :components
                  ((:file "core")))
                 (:module "security"
                  :depends-on ("infra" "config")
                  :components
                  ((:file "ssrf")
                   (:file "safe-bin")
                   (:file "external-content")
                   (:file "audit" :depends-on ("ssrf"))))
                 (:module "tools"
                  :depends-on ("infra" "config" "security")
                  :components
                  ((:file "types")
                   (:file "dispatch" :depends-on ("types"))
                   (:file "approval" :depends-on ("types" "dispatch"))
                   (:file "file-ops" :depends-on ("types" "dispatch"))
                   (:file "exec-tool" :depends-on ("types" "dispatch"))
                   (:file "web-tools" :depends-on ("types" "dispatch"))
                   (:file "browser-tool" :depends-on ("types" "dispatch"))
                   (:file "core" :depends-on ("types" "dispatch" "approval" "file-ops" "exec-tool" "web-tools" "browser-tool"))))
                 (:module "channel-protocol"
                  :depends-on ("infra" "config" "routing")
                  :components
                  ((:file "types")
                   (:file "lifecycle" :depends-on ("types"))
                   (:file "normalize" :depends-on ("types"))
                   (:file "format" :depends-on ("types"))
                   (:file "queue" :depends-on ("types"))
                   (:file "accounts" :depends-on ("types"))
                   (:file "core" :depends-on ("types" "lifecycle" "normalize" "format" "queue" "accounts"))))
                 (:module "telegram"
                  :depends-on ("infra" "channel-protocol")
                  :components
                  ((:file "api-client")
                   (:file "media" :depends-on ("api-client"))
                   (:file "groups" :depends-on ("api-client"))
                   (:file "handler" :depends-on ("api-client" "media" "groups"))))
                 (:module "discord"
                  :depends-on ("infra" "channel-protocol")
                  :components
                  ((:file "rest-client")
                   (:file "gateway" :depends-on ("rest-client"))
                   (:file "media")
                   (:file "threads" :depends-on ("rest-client"))
                   (:file "handler" :depends-on ("rest-client" "media" "threads"))))
                 (:module "irc-client"
                  :depends-on ("infra" "channel-protocol")
                  :components
                  ((:file "connection")
                   (:file "parser")
                   (:file "resilience" :depends-on ("connection"))
                   (:file "handler" :depends-on ("connection" "parser" "resilience"))))
                 (:module "context-engine"
                  :depends-on ("infra" "config" "sessions")
                  :components
                  ((:file "types")
                   (:file "tokens" :depends-on ("types"))
                   (:file "workspace" :depends-on ("types"))
                   (:file "prompt" :depends-on ("types" "tokens" "workspace"))
                   (:file "history" :depends-on ("types" "tokens"))
                   (:file "registry" :depends-on ("types"))
                   (:file "core" :depends-on ("types" "tokens" "workspace" "prompt" "history" "registry"))))
                 (:module "gateway"
                  :depends-on ("infra" "config" "sessions" "routing" "providers"
                               "security" "agents" "channels" "context-engine")
                  :components
                  ((:file "server")
                   (:file "auth" :depends-on ("server"))
                   (:file "boot")
                   (:file "call" :depends-on ("auth"))))))))
