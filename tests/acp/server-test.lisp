;;;; server-test.lisp — Tests for ACP server startup, credentials, hello payload

(in-package :cl-claw.acp.tests)

(in-suite :acp-server)

(test server-credentials-from-config
  "Resolves credentials from config acp.credentials section"
  (let* ((creds-section (make-test-config "apiKey" "sk-test-123"))
         (acp-section (make-test-config "credentials" creds-section))
         (cfg (make-test-config "acp" acp-section)))
    (let ((creds (cl-claw.acp.server:resolve-acp-server-credentials cfg)))
      (is (string= "sk-test-123" (gethash "apiKey" creds))))))

(test server-credentials-empty
  "Returns empty creds when no config or env"
  (let ((cfg (make-hash-table :test 'equal)))
    (let ((creds (cl-claw.acp.server:resolve-acp-server-credentials cfg)))
      (is (hash-table-p creds)))))

(test server-hello-payload
  "Builds gateway hello payload"
  (let ((payload (cl-claw.acp.server:build-gateway-hello-payload
                  "codex" :version "2.0" :agent "my-agent"
                  :capabilities '("exec" "file"))))
    (is (string= "acp" (gethash "protocol" payload)))
    (is (string= "2.0" (gethash "version" payload)))
    (is (string= "codex" (gethash "backend" payload)))
    (is (string= "my-agent" (gethash "agent" payload)))
    (is (equal '("exec" "file") (gethash "capabilities" payload)))))

(test server-hello-payload-minimal
  "Hello payload omits agent when empty"
  (let ((payload (cl-claw.acp.server:build-gateway-hello-payload "be")))
    (is (null (gethash "agent" payload)))
    (is (null (gethash "capabilities" payload)))))

(test server-validate-startup-enabled
  "Validates startup for enabled config"
  (let* ((acp-section (make-test-config "enabled" t "backend" "codex"))
         (cfg (make-test-config "acp" acp-section)))
    (let ((result (cl-claw.acp.server:validate-acp-server-startup cfg)))
      (is (cl-claw.acp.server::startup-check-ready-p result)))))

(test server-validate-startup-disabled
  "Reports not ready when ACP is disabled"
  (let* ((acp-section (make-test-config "enabled" nil))
         (cfg (make-test-config "acp" acp-section)))
    (let ((result (cl-claw.acp.server:validate-acp-server-startup cfg)))
      (is (not (cl-claw.acp.server::startup-check-ready-p result)))
      (is (not (null (cl-claw.acp.server::startup-check-errors result)))))))

(test server-validate-no-backend-warning
  "Warns when no backend is specified"
  (let* ((acp-section (make-test-config "enabled" t))
         (cfg (make-test-config "acp" acp-section)))
    (let ((result (cl-claw.acp.server:validate-acp-server-startup cfg)))
      (is (cl-claw.acp.server::startup-check-ready-p result))
      (is (not (null (cl-claw.acp.server::startup-check-warnings result)))))))

(test server-full-startup-check
  "Full startup check including registry"
  (let* ((acp-section (make-test-config "enabled" t "backend" "codex"))
         (cfg (make-test-config "acp" acp-section))
         (reg (cl-claw.acp.registry:make-runtime-registry)))
    ;; Empty registry should warn
    (let ((result (cl-claw.acp.server:acp-server-startup-check cfg reg)))
      (is (find "No ACP runtime backends registered"
                (cl-claw.acp.server::startup-check-warnings result)
                :test #'string=)))
    ;; With unhealthy backend
    (cl-claw.acp.registry:registry-register-backend reg "codex")
    (cl-claw.acp.registry:registry-check-health reg "codex" nil :now 100)
    (let ((result (cl-claw.acp.server:acp-server-startup-check cfg reg)))
      (is (find-if (lambda (w) (search "unhealthy" w))
                   (cl-claw.acp.server::startup-check-warnings result))))))
