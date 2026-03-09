;;;; policy-test.lisp — Tests for ACP policy predicates

(in-package :cl-claw.acp.tests)

(in-suite :acp-policy)

(test policy-defaults-enabled
  "ACP and dispatch are enabled by default with empty config"
  (let ((cfg (make-hash-table :test 'equal)))
    (is (cl-claw.acp.policy:acp-enabled-by-policy-p cfg))
    (is (cl-claw.acp.policy:acp-dispatch-enabled-by-policy-p cfg))
    (is (string= "enabled"
                  (cl-claw.acp.policy:resolve-acp-dispatch-policy-state cfg)))))

(test policy-acp-disabled
  "Reports ACP disabled state when acp.enabled is false"
  (let* ((acp-section (make-test-config "enabled" nil))
         (cfg (make-test-config "acp" acp-section)))
    (is (not (cl-claw.acp.policy:acp-enabled-by-policy-p cfg)))
    (is (string= "acp_disabled"
                  (cl-claw.acp.policy:resolve-acp-dispatch-policy-state cfg)))
    (let ((msg (cl-claw.acp.policy:resolve-acp-dispatch-policy-message cfg)))
      (is (stringp msg))
      (is (search "acp.enabled=false" msg)))
    (let ((err (cl-claw.acp.policy:resolve-acp-dispatch-policy-error cfg)))
      (is (hash-table-p err))
      (is (string= "ACP_DISPATCH_DISABLED" (gethash "code" err))))))

(test policy-dispatch-disabled
  "Reports dispatch-disabled state when dispatch gate is false"
  (let* ((dispatch (make-test-config "enabled" nil))
         (acp-section (make-test-config "enabled" t "dispatch" dispatch))
         (cfg (make-test-config "acp" acp-section)))
    (is (not (cl-claw.acp.policy:acp-dispatch-enabled-by-policy-p cfg)))
    (is (string= "dispatch_disabled"
                  (cl-claw.acp.policy:resolve-acp-dispatch-policy-state cfg)))
    (let ((msg (cl-claw.acp.policy:resolve-acp-dispatch-policy-message cfg)))
      (is (search "acp.dispatch.enabled=false" msg)))))

(test policy-agent-allowlist
  "Applies allowlist filtering for ACP agents"
  (let* ((acp-section (make-test-config "allowedAgents"
                                        (list "Codex" "claude-code" "kimi")))
         (cfg (make-test-config "acp" acp-section)))
    (is (cl-claw.acp.policy:acp-agent-allowed-by-policy-p cfg "codex"))
    (is (cl-claw.acp.policy:acp-agent-allowed-by-policy-p cfg "claude-code"))
    (is (cl-claw.acp.policy:acp-agent-allowed-by-policy-p cfg "KIMI"))
    (is (not (cl-claw.acp.policy:acp-agent-allowed-by-policy-p cfg "gemini")))
    (let ((err (cl-claw.acp.policy:resolve-acp-agent-policy-error cfg "gemini")))
      (is (hash-table-p err))
      (is (string= "ACP_SESSION_INIT_FAILED" (gethash "code" err))))
    (is (null (cl-claw.acp.policy:resolve-acp-agent-policy-error cfg "codex")))))

(test policy-no-allowlist-allows-all
  "When no allowlist is configured, all agents are allowed"
  (let ((cfg (make-hash-table :test 'equal)))
    (is (cl-claw.acp.policy:acp-agent-allowed-by-policy-p cfg "anything"))
    (is (cl-claw.acp.policy:acp-agent-allowed-by-policy-p cfg "codex"))))
