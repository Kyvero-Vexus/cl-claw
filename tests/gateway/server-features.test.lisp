;;;; FiveAM tests for gateway discovery and plugins

(in-package :cl-claw.gateway.tests)

(declaim (optimize (safety 3) (debug 3)))

(in-suite gateway-suite)

;; Tests for gateway server discovery

(test gateway-discovery-broadcast
  "Gateway broadcasts discovery messages"
  ;; TODO: Implement when gateway discovery functions are available
  (skip "gateway discovery functions not yet available"))

(test gateway-discovery-response
  "Gateway responds to discovery requests"
  ;; TODO: Implement when gateway discovery functions are available
  (skip "gateway discovery functions not yet available"))

;; Tests for gateway plugins

(test gateway-plugins-load
  "Gateway loads plugins"
  ;; TODO: Implement when gateway plugin functions are available
  (skip "gateway plugin functions not yet available"))

(test gateway-plugins-hooks
  "Gateway executes plugin hooks"
  ;; TODO: Implement when gateway plugin hook functions are available
  (skip "gateway plugin hook functions not yet available"))

(test gateway-plugins-skills-status
  "Gateway reports skills status"
  ;; TODO: Implement when gateway skills status functions are available
  (skip "gateway skills status functions not yet available"))

;; Tests for gateway HTTP handling

(test gateway-http-request-timeout
  "Gateway enforces request timeouts"
  ;; TODO: Implement when gateway HTTP functions are available
  (skip "gateway HTTP functions not yet available"))

(test gateway-http-openai-compat
  "Gateway handles OpenAI-compatible requests"
  ;; TODO: Implement when gateway OpenAI functions are available
  (skip "gateway OpenAI functions not yet available"))

;; Tests for gateway security

(test gateway-security-path-validation
  "Gateway validates security paths"
  ;; TODO: Implement when gateway security functions are available
  (skip "gateway security functions not yet available"))

(test gateway-credential-precedence
  "Gateway enforces credential precedence"
  ;; TODO: Implement when gateway credential functions are available
  (skip "gateway credential functions not yet available"))
