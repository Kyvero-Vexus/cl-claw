(asdf:defsystem #:cl-claw-tests
  :description "Test suite for cl-claw ACP modules"
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
                   (:file "core-test" :depends-on ("package")))))))
  :perform (test-op (o s) (uiop:symbol-call :fiveam :run! :cl-claw.acp.tests)))
