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

(test dm-policy-validation-open-requires-wildcard
  "DM policy 'open' requires allowFrom to include '*'"
  (let ((invalid-config (%hash "channels"
                               (%hash "telegram"
                                      (%hash "dmPolicy" "open"
                                             "allowFrom" (list "123456789"))))))
    ;; validate-config returns a list of validation errors
    (let ((errors (cl-claw.config.validation:validate-config invalid-config)))
      (is-true (find-if (lambda (e)
                          (and (equal (cl-claw.config.validation:validation-error-code e)
                                     "ALLOWFROM_REQUIRES_WILDCARD")))
                        errors)))))

(test dm-policy-validation-open-with-wildcard-succeeds
  "DM policy 'open' with wildcard allowFrom passes validation"
  (let ((valid-config (%hash "channels"
                               (%hash "telegram"
                                      (%hash "dmPolicy" "open"
                                             "allowFrom" (list "*"))))))
    ;; validate-config should return empty list for valid config
    (is-true (null (cl-claw.config.validation:validate-config valid-config)))))
