;;;; FiveAM tests for config schema validation

(in-package :cl-claw.config.tests)

(declaim (optimize (safety 3) (debug 3)))

(in-suite config-suite)

;; Tests for sensitive config path detection

(test is-sensitive-config-path-token-whitelist
  "Token-related paths are whitelisted (not sensitive)"
  (let ((whitelisted-paths '("maxTokens"
                             "maxOutputTokens"
                             "maxInputTokens"
                             "maxCompletionTokens"
                             "contextTokens"
                             "totalTokens"
                             "tokenCount"
                             "tokenLimit"
                             "tokenBudget"
                             "channels.irc.nickserv.passwordFile")))
    (dolist (path whitelisted-paths)
      ;; TODO: Implement when is-sensitive-config-path function is available
      (skip "is-sensitive-config-path function not yet available"))))

(test is-sensitive-config-path-sensitive-keys
  "Sensitive keys are marked as sensitive"
  (let ((sensitive-paths '("channels.slack.token"
                           "models.providers.openai.apiKey"
                           "channels.irc.nickserv.password")))
    (dolist (path sensitive-paths)
      ;; TODO: Implement when is-sensitive-config-path function is available
      (skip "is-sensitive-config-path function not yet available"))))

(test dm-policy-validation-rejects-invalid
  "DM policy validation rejects invalid policies"
  (let ((invalid-config (%hash "dmPolicy" "invalid-value")))
    ;; The validate-dm-policy function exists in config/validation.lisp
    (signals error (cl-claw.config.validation:validate-dm-policy invalid-config))))

(test dm-policy-validation-accepts-valid
  "DM policy validation accepts valid policies"
  (let ((valid-config (%hash "dmPolicy" "allow-all")))
    ;; Should not signal error
    (is-true (cl-claw.config.validation:validate-dm-policy valid-config))))
