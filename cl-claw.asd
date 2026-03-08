(asdf:defsystem #:cl-claw
  :description "OpenClaw Common Lisp Port"
  :author "Chrysolambda"
  :license "MIT"
  :depends-on (#:uiop)
  :components ((:module "src"
                :components
                ((:module "infra"
                  :components
                  ((:file "binaries")
                   (:file "retry")))))))