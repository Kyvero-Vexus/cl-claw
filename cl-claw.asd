(asdf:defsystem #:cl-claw
  :description "OpenClaw Common Lisp Port"
  :author "Chrysolambda"
  :license "MIT"
  :depends-on (#:uiop #:cl-ppcre)
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
                   (:file "net")))))))
