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
                 (:module "agents"
                  :depends-on ("acp")
                  :components
                  ((:file "package")
                   (:file "core-test" :depends-on ("package"))
                   (:file "sandbox-test" :depends-on ("package"))
                   (:file "auth-test" :depends-on ("package"))
                   (:file "bash-test" :depends-on ("package"))
                   (:file "spawn-test" :depends-on ("package"))
                   (:file "patch-test" :depends-on ("package"))))
                 (:module "e2e"
                  :depends-on ("acp" "agents")
                  :components
                  ((:file "package")
                   (:file "crash-recovery-test" :depends-on ("package"))
                   (:file "multi-channel-concurrent-test" :depends-on ("package"))
                   (:file "acp-subagent-test" :depends-on ("package"))
                   (:file "provider-streaming-tool-test" :depends-on ("package"))
                   (:file "gateway-boot-roundtrip-test" :depends-on ("package")))))))
  :perform (test-op (o s)
             (uiop:symbol-call :fiveam :run! :cl-claw.acp.tests)
             (uiop:symbol-call :fiveam :run! :cl-claw.agents.tests)
             (uiop:symbol-call :fiveam :run! :cl-claw.e2e.tests)))
