;;;; persistent-bindings-test.lisp — Tests for ACP persistent bindings

(in-package :cl-claw.acp.tests)

(in-suite :acp-persistent-bindings)

(defun %make-binding-config (&key (agent-id "test-agent")
                                  (channel "telegram")
                                  (peer-id "12345")
                                  (account-id nil)
                                  (cwd "/home/test"))
  "Build a config hash-table with a single ACP binding."
  (let ((peer (make-test-config "id" peer-id))
        (match (make-test-config "channel" channel "peer" nil))
        (acp-section (make-test-config "cwd" cwd)))
    (setf (gethash "peer" match) peer)
    (when account-id
      (setf (gethash "accountId" match) account-id))
    (let ((binding (make-test-config "type" "acp"
                                     "agentId" agent-id
                                     "match" match
                                     "acp" acp-section)))
      (make-test-config "bindings" (list binding)))))

(test bindings-session-key-construction
  "Builds deterministic session keys"
  (let ((key (cl-claw.acp.persistent-bindings:build-configured-acp-session-key
              "MyAgent" "telegram" "acct1" "conv-42")))
    (is (stringp key))
    (is (search "myagent" key))
    (is (search "telegram" key))
    (is (search "acct1" key))
    (is (search "conv-42" key))))

(test bindings-session-key-case-insensitive
  "Session keys are case-insensitive"
  (let ((key1 (cl-claw.acp.persistent-bindings:build-configured-acp-session-key
               "Agent" "Telegram" "Acct" "Conv"))
        (key2 (cl-claw.acp.persistent-bindings:build-configured-acp-session-key
               "agent" "telegram" "acct" "conv")))
    (is (string= key1 key2))))

(test bindings-resolve-matching
  "Resolves a binding that matches channel/conversation"
  (let ((cfg (%make-binding-config :agent-id "codex"
                                   :channel "telegram"
                                   :peer-id "99")))
    (let ((result (cl-claw.acp.persistent-bindings:resolve-configured-acp-binding-record
                   cfg :channel "telegram" :account-id "default" :conversation-id "99")))
      (is (not (null result)))
      (is (consp result))
      ;; spec
      (let ((spec (car result)))
        (is (string= "telegram" (cl-claw.acp.types:acp-binding-spec-channel spec)))
        (is (string= "99" (cl-claw.acp.types:acp-binding-spec-conversation-id spec)))
        (is (string= "codex" (cl-claw.acp.types:acp-binding-spec-agent-id spec))))
      ;; record
      (let ((record (cdr result)))
        (is (stringp (cl-claw.acp.types:acp-binding-record-target-session-key record)))
        (is (hash-table-p (cl-claw.acp.types:acp-binding-record-metadata record)))))))

(test bindings-resolve-no-match
  "Returns NIL when no binding matches"
  (let ((cfg (%make-binding-config :channel "telegram" :peer-id "99")))
    (is (null (cl-claw.acp.persistent-bindings:resolve-configured-acp-binding-record
               cfg :channel "discord" :account-id "x" :conversation-id "99")))
    (is (null (cl-claw.acp.persistent-bindings:resolve-configured-acp-binding-record
               cfg :channel "telegram" :account-id "x" :conversation-id "wrong")))))

(test bindings-resolve-by-session-key
  "Finds binding spec by session key"
  (let ((cfg (%make-binding-config :agent-id "codex"
                                   :channel "telegram"
                                   :peer-id "99"
                                   :account-id "acct1")))
    (let ((key (cl-claw.acp.persistent-bindings:build-configured-acp-session-key
                "codex" "telegram" "acct1" "99")))
      (let ((spec (cl-claw.acp.persistent-bindings:resolve-configured-acp-binding-spec-by-session-key
                   cfg key)))
        (is (not (null spec)))
        (is (string= "codex" (cl-claw.acp.types:acp-binding-spec-agent-id spec)))))))

(test bindings-ensure-session
  "ensure-configured-acp-binding-session calls initializer on match"
  (let ((cfg (%make-binding-config :agent-id "codex"
                                   :channel "telegram"
                                   :peer-id "42"))
        (called nil))
    (cl-claw.acp.persistent-bindings:ensure-configured-acp-binding-session
     cfg "telegram" "default" "42"
     (lambda (spec record)
       (declare (ignore record))
       (setf called (cl-claw.acp.types:acp-binding-spec-agent-id spec))))
    (is (string= "codex" called))))

(test bindings-reset-session
  "reset-acp-session-in-place calls closer on match"
  (let ((cfg (%make-binding-config :agent-id "codex"
                                   :channel "telegram"
                                   :peer-id "42"
                                   :account-id "acct1"))
        (closed-key nil))
    (let ((key (cl-claw.acp.persistent-bindings:build-configured-acp-session-key
                "codex" "telegram" "acct1" "42")))
      (cl-claw.acp.persistent-bindings:reset-acp-session-in-place
       cfg key
       (lambda (sk spec)
         (declare (ignore spec))
         (setf closed-key sk)))
      (is (string= key closed-key)))))

(test bindings-empty-config
  "Returns NIL for empty config"
  (let ((cfg (make-hash-table :test 'equal)))
    (is (null (cl-claw.acp.persistent-bindings:resolve-configured-acp-binding-record
               cfg :channel "x" :account-id "y" :conversation-id "z")))))
