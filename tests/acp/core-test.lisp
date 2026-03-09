;;;; core-test.lisp — Tests for ACP session manager (top-level integration)

(in-package :cl-claw.acp.tests)

(in-suite :acp-core)

(defun %enabled-config ()
  "Config with ACP enabled and dispatch enabled."
  (let* ((dispatch (make-test-config "enabled" t))
         (acp-section (make-test-config "enabled" t "dispatch" dispatch)))
    (make-test-config "acp" acp-section)))

(defun %disabled-config ()
  "Config with ACP disabled."
  (let ((acp-section (make-test-config "enabled" nil)))
    (make-test-config "acp" acp-section)))

(defun %allowlist-config (agents)
  "Config with ACP agent allowlist."
  (let ((acp-section (make-test-config "enabled" t "allowedAgents" agents)))
    (make-test-config "acp" acp-section)))

(test core-create-manager
  "Creates ACP session manager"
  (let ((mgr (cl-claw.acp:make-acp-session-manager (%enabled-config))))
    (is (cl-claw.acp::acp-session-manager-p mgr))))

(test core-initialize-session
  "Initializes a session through the manager"
  (let ((mgr (cl-claw.acp:make-acp-session-manager (%enabled-config))))
    (let ((entry (cl-claw.acp:manager-initialize-session
                  mgr :session-id "s1" :session-key "k:s1" :cwd "/tmp")))
      (is (not (null entry)))
      (is (string= "s1" (cl-claw.acp.types:acp-session-entry-session-id entry))))))

(test core-resolve-session
  "Resolves an initialized session"
  (let ((mgr (cl-claw.acp:make-acp-session-manager (%enabled-config))))
    (cl-claw.acp:manager-initialize-session
     mgr :session-id "s1" :session-key "k" :cwd "/")
    (let ((found (cl-claw.acp:manager-resolve-session mgr "s1")))
      (is (not (null found)))
      (is (string= "s1" (cl-claw.acp.types:acp-session-entry-session-id found))))
    (is (null (cl-claw.acp:manager-resolve-session mgr "nonexistent")))))

(test core-close-session
  "Closes a session and returns result"
  (let ((mgr (cl-claw.acp:make-acp-session-manager (%enabled-config))))
    (cl-claw.acp:manager-initialize-session
     mgr :session-id "s1" :session-key "k" :cwd "/")
    (let ((result (cl-claw.acp:manager-close-session mgr "s1")))
      (is (hash-table-p result))
      (is (gethash "metaCleared" result)))
    ;; Session should be gone
    (is (null (cl-claw.acp:manager-resolve-session mgr "s1")))))

(test core-policy-rejects-disabled
  "Manager rejects session init when ACP is disabled"
  (let ((mgr (cl-claw.acp:make-acp-session-manager (%disabled-config))))
    (signals cl-claw.acp.types:acp-dispatch-disabled-error
      (cl-claw.acp:manager-initialize-session
       mgr :session-id "x" :session-key "k" :cwd "/"))))

(test core-policy-rejects-disallowed-agent
  "Manager rejects disallowed agent"
  (let ((mgr (cl-claw.acp:make-acp-session-manager
              (%allowlist-config '("codex")))))
    ;; Allowed
    (is (not (null (cl-claw.acp:manager-initialize-session
                    mgr :session-id "ok" :session-key "k" :cwd "/"
                    :agent "codex"))))
    ;; Disallowed
    (signals cl-claw.acp.types:acp-agent-not-allowed-error
      (cl-claw.acp:manager-initialize-session
       mgr :session-id "bad" :session-key "k" :cwd "/"
       :agent "gemini"))))

(test core-rate-limiting
  "Manager enforces rate limits on session creation"
  (let ((mgr (cl-claw.acp:make-acp-session-manager
              (%enabled-config) :rate-max 2 :rate-window-ms 60000)))
    (cl-claw.acp:manager-initialize-session
     mgr :session-id "s1" :session-key "k1" :cwd "/")
    (cl-claw.acp:manager-initialize-session
     mgr :session-id "s2" :session-key "k2" :cwd "/")
    (signals cl-claw.acp.types:acp-rate-limit-error
      (cl-claw.acp:manager-initialize-session
       mgr :session-id "s3" :session-key "k3" :cwd "/"))))

(test core-close-with-active-run
  "Closing a session cancels active runs"
  (let ((mgr (cl-claw.acp:make-acp-session-manager (%enabled-config))))
    (cl-claw.acp:manager-initialize-session
     mgr :session-id "s1" :session-key "k" :cwd "/")
    ;; Set active run directly on the store
    (cl-claw.acp.session:session-store-set-active-run
     (cl-claw.acp::acp-manager-session-store mgr)
     "s1" "run-1" :controller)
    ;; Close should succeed
    (let ((result (cl-claw.acp:manager-close-session mgr "s1")))
      (is (hash-table-p result)))))
