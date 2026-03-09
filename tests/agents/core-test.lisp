;;;; core-test.lisp — Tests for agent config resolution

(in-package :cl-claw.agents.tests)

(in-suite :agent-core)

(test agent-normalize-id
  "Normalizes agent IDs to lowercase, sanitized form"
  (is (string= "main" (cl-claw.agents:normalize-agent-id "")))
  (is (string= "main" (cl-claw.agents:normalize-agent-id "  ")))
  (is (string= "my-agent" (cl-claw.agents:normalize-agent-id "My Agent")))
  (is (string= "codex" (cl-claw.agents:normalize-agent-id "Codex")))
  (is (string= "test_agent" (cl-claw.agents:normalize-agent-id "test_agent"))))

(test agent-resolve-workspace-dir
  "Resolves agent workspace directory"
  (let ((dir (cl-claw.agents:resolve-agent-workspace-dir "/opt/agents" "MyAgent")))
    (is (search "myagent" dir))
    (is (search "/opt/agents" dir))))

(test agent-resolve-config
  "Resolves agent-specific config from main config"
  (let* ((agent-entry (make-test-config "model" "gpt-4"))
         (agents-list (make-test-config "myagent" agent-entry))
         (agents (make-test-config "list" agents-list))
         (config (make-test-config "agents" agents)))
    (let ((result (cl-claw.agents:resolve-agent-config config "MyAgent")))
      (is (hash-table-p result))
      (is (string= "gpt-4" (gethash "model" result))))
    (is (null (cl-claw.agents:resolve-agent-config config "nonexistent")))))

(test agent-model-primary
  "Resolves primary model for agent"
  ;; String model
  (let* ((agent-entry (make-test-config "model" "gpt-4"))
         (agents-list (make-test-config "myagent" agent-entry))
         (agents (make-test-config "list" agents-list))
         (config (make-test-config "agents" agents)))
    (is (string= "gpt-4" (cl-claw.agents:resolve-agent-model-primary config "myagent"))))
  ;; Hash-table model with primary key
  (let* ((model (make-test-config "primary" "claude-3" "fallbacks" '("gpt-4")))
         (agent-entry (make-test-config "model" model))
         (agents-list (make-test-config "myagent" agent-entry))
         (agents (make-test-config "list" agents-list))
         (config (make-test-config "agents" agents)))
    (is (string= "claude-3" (cl-claw.agents:resolve-agent-model-primary config "myagent")))))

(test agent-model-fallbacks
  "Resolves model fallbacks"
  (let* ((model (make-test-config "primary" "claude-3" "fallbacks" '("gpt-4" "gemini")))
         (agent-entry (make-test-config "model" model))
         (agents-list (make-test-config "myagent" agent-entry))
         (agents (make-test-config "list" agents-list))
         (config (make-test-config "agents" agents)))
    (is (cl-claw.agents:agent-has-model-fallbacks-p config "myagent"))
    (is (equal '("gpt-4" "gemini")
               (cl-claw.agents:resolve-agent-model-fallbacks config "myagent")))))

(test agent-openclaw-dir-resolution
  "Resolves openclaw agent directory from various sources"
  ;; Direct override
  (is (string= "/custom/agents"
               (cl-claw.agents:resolve-openclaw-agent-dir :openclaw-agent-dir "/custom/agents")))
  ;; From OPENCLAW_HOME
  (let ((dir (cl-claw.agents:resolve-openclaw-agent-dir :openclaw-home "/opt/openclaw")))
    (is (search "agents" dir))
    (is (search "/opt/openclaw" dir))))
