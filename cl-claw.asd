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
                 (:module "channels"
                  :depends-on ("routing" "sessions" "providers" "memory")
                  :components
                  ((:file "telegram")
                   (:file "irc")
                   (:file "discord")
                   (:file "signal")
                   (:file "slack")))
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
                 (:module "security"
                  :depends-on ("infra" "config")
                  :components
                  ((:file "ssrf")
                   (:file "safe-bin")
                   (:file "external-content")
                   (:file "audit" :depends-on ("ssrf"))))))))
