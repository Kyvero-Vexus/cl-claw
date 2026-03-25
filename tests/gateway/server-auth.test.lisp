;;;; FiveAM tests for gateway server auth

(in-package :cl-claw.gateway.tests)

(declaim (optimize (safety 3) (debug 3)))

(in-suite gateway-suite)

;; Tests for gateway server authentication

(test gateway-auth-secret-ref-detection
  "Identifies SecretRef patterns"
  ;; TODO: Implement when secret-ref-p function is available
  (skip "gateway auth functions not yet available"))

(test gateway-auth-secret-ref-resolution
  "Resolves SecretRef from env"
  ;; TODO: Implement when resolve-secret-ref function is available
  (skip "gateway auth functions not yet available"))

(test gateway-auth-token-from-env
  "Resolves token from env vars"
  ;; TODO: Implement when resolve-auth-from-env function is available
  (skip "gateway auth functions not yet available"))

(test gateway-auth-password-from-env
  "Resolves password from env vars"
  ;; TODO: Implement when resolve-auth-from-env function is available
  (skip "gateway auth functions not yet available"))

(test gateway-auth-config-overrides-env
  "Config values override env"
  ;; TODO: Implement when resolve-gateway-auth-config function is available
  (skip "gateway auth functions not yet available"))

(test gateway-auth-runtime-override
  "Runtime mode override takes precedence"
  ;; TODO: Implement when resolve-gateway-auth-config function is available
  (skip "gateway auth functions not yet available"))

(test gateway-auth-tailscale-hostname
  "Detects Tailscale serve hostnames"
  ;; TODO: Implement when tailscale-serve-hostname-p function is available
  (skip "gateway auth functions not yet available"))
