(asdf:defsystem #:cl-claw-tests
  :description "Test suite for cl-claw"
  :depends-on (#:cl-claw #:fiveam)
  :components ((:module "tests"
                :components
                ((:module "acp"
                  :components
                  ((:file "package")
                   (:file "policy-test" :depends-on ("package"))
                   (:file "session-test" :depends-on ("package"))
                   (:file "runtime-cache-test" :depends-on ("package"))
                   (:file "registry-test" :depends-on ("package"))
                   (:file "persistent-bindings-test" :depends-on ("package"))
                   (:file "client-test" :depends-on ("package"))
                   (:file "translator-test" :depends-on ("package"))
                   (:file "server-test" :depends-on ("package"))
                   (:file "core-test" :depends-on ("package"))))
                 (:module "config"
                  :depends-on ("acp")
                  :components
                  ((:file "package")
                   (:file "env-substitution.test" :depends-on ("package"))
                   (:file "merge-patch.test" :depends-on ("package"))
                   (:file "schema.test" :depends-on ("package"))
                   (:file "sessions.test" :depends-on ("package"))))
                 (:module "agents"
                  :depends-on ("acp" "config")
                  :components
                  ((:file "package")
                   (:file "core-test" :depends-on ("package"))
                   (:file "sandbox-test" :depends-on ("package"))
                   (:file "auth-test" :depends-on ("package"))
                   (:file "bash-test" :depends-on ("package"))
                   (:file "spawn-test" :depends-on ("package"))
                   (:file "patch-test" :depends-on ("package"))))
                 (:module "channels"
                  :depends-on ("acp")
                  :components
                  ((:file "package")
                   (:file "channel-config-test" :depends-on ("package"))
                   (:file "session-test" :depends-on ("package"))
                   (:file "allow-from-test" :depends-on ("package"))
                   (:file "allowlists-test" :depends-on ("package"))))
                 (:module "browser"
                  :depends-on ("acp")
                  :components
                  ((:file "package")))
                 (:module "cron"
                  :depends-on ("acp")
                  :components
                  ((:file "package")))
                 (:module "auto-reply"
                  :depends-on ("acp")
                  :components
                  ((:file "package")))
                 (:module "discord"
                  :depends-on ("acp")
                  :components
                  ((:file "package")))
                 (:module "e2e"
                  :depends-on ("acp" "agents" "channels" "browser" "cron" "auto-reply" "discord")
                  :components
                  ((:file "package")
                   (:file "crash-recovery-test" :depends-on ("package"))
                   (:file "multi-channel-concurrent-test" :depends-on ("package"))
                   (:file "acp-subagent-test" :depends-on ("package"))
                   (:file "provider-streaming-tool-test" :depends-on ("package"))
                   (:file "gateway-boot-roundtrip-test" :depends-on ("package")))))))
  :perform (test-op (o s)
             (uiop:symbol-call :fiveam :run! :cl-claw.acp.tests)
             (uiop:symbol-call :fiveam :run! :cl-claw.config.tests)
             (uiop:symbol-call :fiveam :run! :cl-claw.agents.tests)
             (uiop:symbol-call :fiveam :run! :cl-claw.channels.tests)
             (uiop:symbol-call :fiveam :run! :cl-claw.browser.tests)
             (uiop:symbol-call :fiveam :run! :cl-claw.cron.tests)
             (uiop:symbol-call :fiveam :run! :cl-claw.auto-reply.tests)
             (uiop:symbol-call :fiveam :run! :cl-claw.discord.tests)
             (uiop:symbol-call :fiveam :run! :cl-claw.e2e.tests)))
