;;;; auth.lisp - Gateway authentication for cl-claw
;;;;
;;;; Resolves gateway auth configuration from environment variables,
;;;; config files, and SecretRef inputs. Handles token/password modes,
;;;; tailscale identity, and proxy-aware client IP resolution.
;;;;
;;;; Static typing: all functions have SBCL type declarations.

(defpackage :cl-claw.gateway.auth
  (:use :cl)
  (:import-from :cl-claw.gateway.server
                :gateway-auth-mode
                :auth-result
                :make-auth-result)
  (:export
   ;; Auth config resolution
   :gateway-auth-config
   :make-gateway-auth-config
   :gateway-auth-config-mode
   :gateway-auth-config-mode-source
   :gateway-auth-config-token
   :gateway-auth-config-password
   :gateway-auth-config-tailscale-header-auth-p
   ;; Resolution
   :resolve-gateway-auth-config
   :resolve-auth-from-env
   :resolve-secret-ref
   :secret-ref-p
   ;; Tailscale
   :tailscale-serve-hostname-p
   :tailscale-identity
   :make-tailscale-identity
   :tailscale-identity-user
   :tailscale-identity-node))

(in-package :cl-claw.gateway.auth)

(declaim (optimize (safety 3) (debug 3)))

;;; ============================================================
;;; SecretRef Resolution
;;; ============================================================

(defparameter *env-template-regex* "\\$\\{([^}]+)\\}"
  "Regex to match ${ENV_VAR} template strings.")

(declaim (ftype (function (string) boolean) secret-ref-p))
(defun secret-ref-p (value)
  "Return T if VALUE looks like a SecretRef (${ENV_VAR} pattern) rather than plaintext."
  (declare (type string value))
  (and (>= (length value) 4)
       (char= (char value 0) #\$)
       (char= (char value 1) #\{)
       (char= (char value (1- (length value))) #\})
       t))

(declaim (ftype (function (string &key (:env-fn (or null function))) (or null string)) resolve-secret-ref))
(defun resolve-secret-ref (value &key env-fn)
  "Resolve a SecretRef value. If VALUE is a ${ENV_VAR} template, resolve from env.
If it's a plain string, return as-is. Returns NIL if env var is not set."
  (declare (type string value))
  (if (secret-ref-p value)
      ;; Extract env var name and resolve
      (let* ((var-name (subseq value 2 (1- (length value))))
             (getter (or env-fn #'uiop:getenv)))
        (funcall getter var-name))
      ;; Plain string - return as-is
      value))

;;; ============================================================
;;; Gateway Auth Configuration
;;; ============================================================

(deftype auth-mode-source ()
  "Source of the auth mode setting."
  '(member :config :env :override :default))

(defstruct gateway-auth-config
  "Resolved gateway authentication configuration."
  (mode :token :type gateway-auth-mode)
  (mode-source :default :type auth-mode-source)
  (token nil :type (or null string))
  (password nil :type (or null string))
  (tailscale-header-auth-p nil :type boolean))

;;; --- Environment variable resolution ---

(defparameter *gateway-env-vars*
  '(("OPENCLAW_GATEWAY_TOKEN" . :token)
    ("OPENCLAW_GATEWAY_PASSWORD" . :password)
    ("OPENCLAW_GATEWAY_AUTH_MODE" . :mode))
  "Environment variables for gateway auth configuration.")

(declaim (ftype (function (&key (:env-fn (or null function))) gateway-auth-config) resolve-auth-from-env))
(defun resolve-auth-from-env (&key env-fn)
  "Resolve gateway auth configuration from environment variables."
  (let ((getter (or env-fn #'uiop:getenv)))
    (let ((token (funcall getter "OPENCLAW_GATEWAY_TOKEN"))
          (password (funcall getter "OPENCLAW_GATEWAY_PASSWORD"))
          (mode-str (funcall getter "OPENCLAW_GATEWAY_AUTH_MODE")))
      (let ((mode (cond
                    ((and mode-str (string-equal mode-str "none")) :none)
                    ((and mode-str (string-equal mode-str "token")) :token)
                    ((and mode-str (string-equal mode-str "password")) :password)
                    ((and mode-str (string-equal mode-str "trusted-proxy")) :trusted-proxy)
                    (token :token)
                    (password :password)
                    (t :token))))
        (make-gateway-auth-config
         :mode mode
         :mode-source (if mode-str :env :default)
         :token (when token
                  (if (secret-ref-p token)
                      nil  ; Don't resolve SecretRefs from env
                      token))
         :password (when password
                     (if (secret-ref-p password)
                         nil
                         password)))))))

;;; --- Combined resolution ---

(declaim (ftype (function (&key (:config-mode (or null gateway-auth-mode))
                                (:config-token (or null string))
                                (:config-password (or null string))
                                (:runtime-mode-override (or null gateway-auth-mode))
                                (:env-fn (or null function)))
                          gateway-auth-config)
               resolve-gateway-auth-config))
(defun resolve-gateway-auth-config (&key config-mode config-token config-password
                                         runtime-mode-override env-fn)
  "Resolve the full gateway auth configuration from config, env, and overrides.
Config values take precedence over environment variables.
Runtime overrides take precedence over config."
  (let ((env-config (resolve-auth-from-env :env-fn env-fn)))
    ;; Merge: config > env > defaults
    (let* ((effective-token (or config-token
                                (gateway-auth-config-token env-config)))
           (effective-password (or config-password
                                   (gateway-auth-config-password env-config)))
           (effective-mode (cond
                             (runtime-mode-override runtime-mode-override)
                             (config-mode config-mode)
                             (t (gateway-auth-config-mode env-config))))
           (mode-source (cond
                          (runtime-mode-override :override)
                          (config-mode :config)
                          (t (gateway-auth-config-mode-source env-config)))))
      ;; Resolve SecretRefs in config values
      (when (and effective-token (secret-ref-p effective-token))
        (setf effective-token (resolve-secret-ref effective-token :env-fn env-fn)))
      (when (and effective-password (secret-ref-p effective-password))
        (setf effective-password (resolve-secret-ref effective-password :env-fn env-fn)))
      (make-gateway-auth-config
       :mode effective-mode
       :mode-source mode-source
       :token effective-token
       :password effective-password))))

;;; ============================================================
;;; Tailscale Identity
;;; ============================================================

(defstruct tailscale-identity
  "Identity from Tailscale headers."
  (user nil :type (or null string))
  (node nil :type (or null string)))

(defparameter *tailscale-serve-suffixes*
  '(".ts.net" ".tailscale.net")
  "Hostname suffixes that indicate Tailscale serve.")

(declaim (ftype (function (string) boolean) tailscale-serve-hostname-p))
(defun tailscale-serve-hostname-p (hostname)
  "Return T if HOSTNAME is a local Tailscale serve hostname."
  (declare (type string hostname))
  (let ((lower (string-downcase hostname)))
    (dolist (suffix *tailscale-serve-suffixes*)
      (when (and (> (length lower) (length suffix))
                 (string= lower suffix
                          :start1 (- (length lower) (length suffix))))
        (return-from tailscale-serve-hostname-p t))))
  nil)
