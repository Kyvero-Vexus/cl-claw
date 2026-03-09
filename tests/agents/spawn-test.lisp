;;;; spawn-test.lisp — Tests for agent spawn

(in-package :cl-claw.agents.tests)

(in-suite :agent-spawn)

(test spawn-config-creation
  "Creates spawn configuration"
  (let ((cfg (cl-claw.agents.spawn:make-spawn-config
              :agent-id "codex"
              :session-key "agent:codex:main"
              :cwd "/work"
              :backend "codex"
              :mode "persistent")))
    (is (string= "codex" (cl-claw.agents.spawn:spawn-config-agent-id cfg)))
    (is (string= "/work" (cl-claw.agents.spawn:spawn-config-cwd cfg)))
    (is (string= "persistent" (cl-claw.agents.spawn:spawn-config-mode cfg)))))

(test spawn-session-key-resolution
  "Resolves spawn session keys"
  ;; With parent
  (let ((key (cl-claw.agents.spawn:resolve-spawn-session-key
              "sub-agent" :parent-key "agent:main:main")))
    (is (stringp key))
    (is (search "sub-agent" key))
    (is (search "subagent" key)))
  ;; Without parent
  (let ((key (cl-claw.agents.spawn:resolve-spawn-session-key "my-agent")))
    (is (stringp key))
    (is (search "my-agent" key))))

(test spawn-thread-binding
  "Creates thread binding"
  (let ((binding (cl-claw.agents.spawn:make-thread-binding
                  :thread-id "t-123"
                  :channel "discord"
                  :session-key "agent:sub:thread:t-123")))
    (is (string= "t-123" (cl-claw.agents.spawn:thread-binding-thread-id binding)))
    (is (string= "discord" (cl-claw.agents.spawn:thread-binding-channel binding)))))

(test spawn-build-env
  "Builds spawn environment"
  (let* ((cfg (cl-claw.agents.spawn:make-spawn-config
               :agent-id "sub"
               :session-key "agent:sub:main"
               :cwd "/work"
               :backend "codex"
               :parent-session-key "agent:main:main"))
         (env (cl-claw.agents.spawn:build-spawn-env cfg)))
    (is (hash-table-p env))
    (is (string= "sub" (gethash "OPENCLAW_AGENT_ID" env)))
    (is (string= "acp-client" (gethash "OPENCLAW_SHELL" env)))
    (is (string= "agent:main:main" (gethash "OPENCLAW_PARENT_SESSION_KEY" env)))))

(test spawn-stream-relay
  "Creates stream relay"
  (let ((relay (cl-claw.agents.spawn:make-stream-relay
                :parent-key "agent:main:main")))
    (is (string= "agent:main:main"
                  (cl-claw.agents.spawn:stream-relay-parent-key relay)))))
