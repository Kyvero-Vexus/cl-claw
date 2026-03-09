;;;; registry-test.lisp — Tests for ACP runtime registry

(in-package :cl-claw.acp.tests)

(in-suite :acp-registry)

(test registry-register-and-get
  "Register a backend and retrieve it"
  (let ((reg (cl-claw.acp.registry:make-runtime-registry)))
    (cl-claw.acp.registry:registry-register-backend reg "codex" :display-name "Codex")
    (let ((entry (cl-claw.acp.registry:registry-get-backend reg "codex")))
      (is (not (null entry))))))

(test registry-default-backend
  "Default backend is used when no ID specified"
  (let ((reg (cl-claw.acp.registry:make-runtime-registry)))
    (cl-claw.acp.registry:registry-register-backend reg "codex" :default t)
    (cl-claw.acp.registry:registry-register-backend reg "claude")
    (let ((entry (cl-claw.acp.registry:registry-get-backend reg)))
      (is (not (null entry))))))

(test registry-require-signals-error
  "require-backend signals error when backend not found"
  (let ((reg (cl-claw.acp.registry:make-runtime-registry)))
    (signals cl-claw.acp.types:acp-runtime-error
      (cl-claw.acp.registry:registry-require-backend reg "nonexistent"))))

(test registry-unregister
  "Unregister removes backend and clears default"
  (let ((reg (cl-claw.acp.registry:make-runtime-registry)))
    (cl-claw.acp.registry:registry-register-backend reg "codex" :default t)
    (is (cl-claw.acp.registry:registry-unregister-backend reg "codex"))
    (is (null (cl-claw.acp.registry:registry-get-backend reg "codex")))
    (is (null (cl-claw.acp.registry:registry-get-backend reg)))))

(test registry-list-backends
  "Lists all registered backends"
  (let ((reg (cl-claw.acp.registry:make-runtime-registry)))
    (cl-claw.acp.registry:registry-register-backend reg "a")
    (cl-claw.acp.registry:registry-register-backend reg "b")
    (is (= 2 (length (cl-claw.acp.registry:registry-list-backends reg))))))

(test registry-health-tracking
  "Tracks health status of backends"
  (let ((reg (cl-claw.acp.registry:make-runtime-registry)))
    (cl-claw.acp.registry:registry-register-backend reg "be1")
    (is (cl-claw.acp.registry:registry-backend-healthy-p reg "be1"))
    (cl-claw.acp.registry:registry-check-health reg "be1" nil :now 1000)
    (is (not (cl-claw.acp.registry:registry-backend-healthy-p reg "be1")))
    (cl-claw.acp.registry:registry-check-health reg "be1" t :now 2000)
    (is (cl-claw.acp.registry:registry-backend-healthy-p reg "be1"))))

(test registry-error-formatting
  "Formats ACP error text"
  (handler-case
      (error 'cl-claw.acp.types:acp-session-full-error :text "test error")
    (cl-claw.acp.types:acp-error (e)
      (let ((text (cl-claw.acp.registry:format-acp-error-text e)))
        (is (search "ACP_SESSION_FULL" text))
        (is (search "test error" text))))))

(test registry-error-boundary
  "Error boundary catches ACP errors"
  (multiple-value-bind (result errored)
      (cl-claw.acp.registry:make-acp-error-boundary
       (lambda () (error 'cl-claw.acp.types:acp-rate-limit-error :text "too fast")))
    (is (eq t errored))
    (is (hash-table-p result))
    (is (string= "ACP_RATE_LIMIT" (gethash "code" result))))
  ;; Success case
  (multiple-value-bind (result errored)
      (cl-claw.acp.registry:make-acp-error-boundary
       (lambda () 42))
    (is (not errored))
    (is (= 42 result))))
