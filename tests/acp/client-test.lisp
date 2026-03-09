;;;; client-test.lisp — Tests for ACP client spawn env and invocation

(in-package :cl-claw.acp.tests)

(in-suite :acp-client)

(test client-spawn-env-sets-marker
  "Spawn env always sets OPENCLAW_SHELL=acp-client"
  (let ((base (make-test-config "PATH" "/usr/bin" "HOME" "/home/test")))
    (let ((env (cl-claw.acp.client:resolve-acp-client-spawn-env base)))
      (is (string= "acp-client" (gethash "OPENCLAW_SHELL" env)))
      (is (string= "/usr/bin" (gethash "PATH" env)))
      (is (string= "/home/test" (gethash "HOME" env))))))

(test client-spawn-env-strips-keys
  "Spawn env strips specified keys but never OPENCLAW_SHELL"
  (let ((base (make-test-config "SECRET" "x" "OPENCLAW_SHELL" "old" "PATH" "/bin")))
    (let ((env (cl-claw.acp.client:resolve-acp-client-spawn-env
                base :strip-keys '("SECRET" "OPENCLAW_SHELL"))))
      (is (null (gethash "SECRET" env)))
      ;; OPENCLAW_SHELL is never stripped, always overridden
      (is (string= "acp-client" (gethash "OPENCLAW_SHELL" env)))
      (is (string= "/bin" (gethash "PATH" env))))))

(test client-spawn-env-does-not-mutate-base
  "Spawn env does not modify the base environment"
  (let ((base (make-test-config "KEY" "val")))
    (cl-claw.acp.client:resolve-acp-client-spawn-env base :strip-keys '("KEY"))
    (is (string= "val" (gethash "KEY" base)))))

(test client-invocation-codex
  "Resolves codex backend invocation"
  (let ((inv (cl-claw.acp.client:resolve-acp-client-spawn-invocation
              "codex" :cwd "/work" :agent "my-agent" :session-key "sk-1")))
    (is (listp (cl-claw.acp.client::acp-invocation-command inv)))
    (is (string= "codex" (first (cl-claw.acp.client::acp-invocation-command inv))))
    (is (string= "/work" (cl-claw.acp.client::acp-invocation-cwd inv)))))

(test client-invocation-claude-code
  "Resolves claude-code backend invocation"
  (let ((inv (cl-claw.acp.client:resolve-acp-client-spawn-invocation
              "claude-code" :session-key "s" :agent "a")))
    (is (string= "claude" (first (cl-claw.acp.client::acp-invocation-command inv))))))

(test client-invocation-generic
  "Falls back to backend name as command for unknown backends"
  (let ((inv (cl-claw.acp.client:resolve-acp-client-spawn-invocation
              "custom-be" :session-key "s" :agent "a")))
    (is (string= "custom-be" (first (cl-claw.acp.client::acp-invocation-command inv))))))

(test client-extract-text-from-prompt
  "Extracts concatenated text from prompt parts"
  (let ((parts (list (make-test-config "type" "text" "text" "hello")
                     (make-test-config "type" "image" "url" "http://img")
                     (make-test-config "type" "text" "text" "world"))))
    (let ((text (cl-claw.acp.client:extract-text-from-prompt parts)))
      (is (search "hello" text))
      (is (search "world" text)))))

(test client-extract-attachments
  "Extracts non-text attachments from prompt parts"
  (let ((parts (list (make-test-config "type" "text" "text" "hi")
                     (make-test-config "type" "image" "url" "http://img")
                     (make-test-config "type" "file" "path" "/tmp/f"))))
    (let ((attachments (cl-claw.acp.client:extract-attachments-from-prompt parts)))
      (is (= 2 (length attachments))))))

(test client-permission-resolution
  "Resolves permission request structure"
  (let* ((tool-call (make-test-config "toolCallId" "tc-1"
                                      "title" "Run command"
                                      "status" "pending"))
         (request (make-test-config "sessionId" "s-1"
                                    "toolCall" tool-call
                                    "options" (list "allow" "deny"))))
    (let ((res (cl-claw.acp.client:resolve-permission-request request)))
      (is (string= "s-1" (cl-claw.acp.client::permission-resolution-session-id res)))
      (is (string= "tc-1" (cl-claw.acp.client::permission-resolution-tool-call-id res)))
      (is (string= "Run command" (cl-claw.acp.client::permission-resolution-title res)))
      (is (equal '("allow" "deny") (cl-claw.acp.client::permission-resolution-options res))))))
