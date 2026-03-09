;;;; fiveam-gateway-auth.test.lisp - Tests for gateway auth resolution

(defpackage :cl-claw.gateway.auth.test
  (:use :cl :fiveam)
  (:import-from :cl-claw.gateway.auth
                :secret-ref-p
                :resolve-secret-ref
                :resolve-auth-from-env
                :resolve-gateway-auth-config
                :gateway-auth-config-mode
                :gateway-auth-config-mode-source
                :gateway-auth-config-token
                :gateway-auth-config-password
                :tailscale-serve-hostname-p))

(in-package :cl-claw.gateway.auth.test)

(def-suite gateway-auth-suite
  :description "Gateway auth resolution tests")

(in-suite gateway-auth-suite)

;;; ============================================================
;;; SecretRef Detection
;;; ============================================================

(test secret-ref-detection
  "Identifies SecretRef patterns"
  (is (secret-ref-p "${MY_TOKEN}"))
  (is (secret-ref-p "${A}"))
  (is (not (secret-ref-p "plain-text")))
  (is (not (secret-ref-p "$NOT_A_REF")))
  (is (not (secret-ref-p "")))
  (is (not (secret-ref-p "ab"))))

(test secret-ref-resolution
  "Resolves SecretRef from env"
  ;; Plain text returns as-is
  (is (string= "my-token" (resolve-secret-ref "my-token")))
  ;; SecretRef resolves from env function
  (is (string= "resolved-value"
               (resolve-secret-ref "${MY_VAR}"
                                   :env-fn (lambda (name)
                                             (when (string= name "MY_VAR")
                                               "resolved-value")))))
  ;; Missing env returns nil
  (is (null (resolve-secret-ref "${MISSING}"
                                :env-fn (lambda (name) (declare (ignore name)) nil)))))

;;; ============================================================
;;; Env Resolution
;;; ============================================================

(test resolve-auth-from-env-token
  "Resolves token from env vars"
  (let ((config (resolve-auth-from-env
                 :env-fn (lambda (name)
                           (cond
                             ((string= name "OPENCLAW_GATEWAY_TOKEN") "my-token")
                             (t nil))))))
    (is (eq :token (gateway-auth-config-mode config)))
    (is (string= "my-token" (gateway-auth-config-token config)))))

(test resolve-auth-from-env-password
  "Resolves password from env vars"
  (let ((config (resolve-auth-from-env
                 :env-fn (lambda (name)
                           (cond
                             ((string= name "OPENCLAW_GATEWAY_PASSWORD") "my-pass")
                             (t nil))))))
    (is (eq :password (gateway-auth-config-mode config)))
    (is (string= "my-pass" (gateway-auth-config-password config)))))

(test resolve-auth-from-env-explicit-mode
  "Respects explicit auth mode from env"
  (let ((config (resolve-auth-from-env
                 :env-fn (lambda (name)
                           (cond
                             ((string= name "OPENCLAW_GATEWAY_AUTH_MODE") "none")
                             ((string= name "OPENCLAW_GATEWAY_TOKEN") "ignored")
                             (t nil))))))
    (is (eq :none (gateway-auth-config-mode config)))
    (is (eq :env (gateway-auth-config-mode-source config)))))

(test resolve-auth-env-secret-ref-not-resolved
  "Does not resolve SecretRef templates in env values"
  (let ((config (resolve-auth-from-env
                 :env-fn (lambda (name)
                           (cond
                             ((string= name "OPENCLAW_GATEWAY_TOKEN") "${SECRET}")
                             (t nil))))))
    ;; SecretRef should not be resolved at env level
    (is (null (gateway-auth-config-token config)))))

;;; ============================================================
;;; Combined Resolution
;;; ============================================================

(test resolve-config-overrides-env
  "Config values override env"
  (let ((config (resolve-gateway-auth-config
                 :config-mode :password
                 :config-password "config-pass"
                 :env-fn (lambda (name)
                           (cond
                             ((string= name "OPENCLAW_GATEWAY_PASSWORD") "env-pass")
                             (t nil))))))
    (is (eq :password (gateway-auth-config-mode config)))
    (is (eq :config (gateway-auth-config-mode-source config)))
    (is (string= "config-pass" (gateway-auth-config-password config)))))

(test resolve-runtime-override
  "Runtime mode override takes precedence"
  (let ((config (resolve-gateway-auth-config
                 :config-mode :token
                 :runtime-mode-override :none
                 :env-fn (constantly nil))))
    (is (eq :none (gateway-auth-config-mode config)))
    (is (eq :override (gateway-auth-config-mode-source config)))))

(test resolve-config-secret-ref
  "Resolves SecretRef in config token"
  (let ((config (resolve-gateway-auth-config
                 :config-token "${MY_SECRET}"
                 :env-fn (lambda (name)
                           (when (string= name "MY_SECRET")
                             "resolved-secret")))))
    (is (string= "resolved-secret" (gateway-auth-config-token config)))))

;;; ============================================================
;;; Tailscale
;;; ============================================================

(test tailscale-serve-hostname
  "Detects Tailscale serve hostnames"
  (is (tailscale-serve-hostname-p "my-machine.ts.net"))
  (is (tailscale-serve-hostname-p "my-machine.tailscale.net"))
  (is (not (tailscale-serve-hostname-p "example.com")))
  (is (not (tailscale-serve-hostname-p "ts.net")))  ; Just the suffix, no hostname
  (is (not (tailscale-serve-hostname-p "notts.net"))))
