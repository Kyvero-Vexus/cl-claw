(asdf:defsystem #:cl-claw-tests
  :description "Tests for cl-claw"
  :author "Chrysolambda"
  :license "MIT"
  :depends-on (#:cl-claw #:fiveam)
  :components ((:module "tests/cl-adapted/src/infra"
                :components
                ((:file "binaries.test")
                 (:file "retry.test"))))
  :perform (asdf:test-op (op c)
             (let ((binaries-suite (find-symbol (string-upcase "binaries-suite") :cl-claw.infra.binaries.test))
                   (retry-suite (find-symbol (string-upcase "retry-suite") :cl-claw.infra.retry.test)))
               (when binaries-suite
                 (symbol-call :fiveam :run! binaries-suite))
               (when retry-suite
                 (symbol-call :fiveam :run! retry-suite)))))
