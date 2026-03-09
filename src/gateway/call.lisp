;;;; call.lisp - Gateway call infrastructure for cl-claw
;;;;
;;;; Handles URL resolution, credential flow, and connection details
;;;; for communicating with the gateway from agents and CLI.

(defpackage :cl-claw.gateway.call
  (:use :cl)
  (:import-from :cl-claw.gateway.auth
                :resolve-secret-ref
                :secret-ref-p)
  (:export
   :gateway-connection-details
   :make-gateway-connection-details
   :gateway-connection-details-url
   :gateway-connection-details-token
   :gateway-connection-details-password
   :gateway-connection-details-tls-fingerprint
   :gateway-connection-details-source
   :build-gateway-connection-details
   :call-gateway-error
   :call-gateway-error-reason
   :call-gateway-error-details
   :validate-gateway-url))

(in-package :cl-claw.gateway.call)

(declaim (optimize (safety 3) (debug 3)))

;;; ============================================================
;;; Types
;;; ============================================================

(deftype connection-source ()
  "Source of the gateway connection URL."
  '(member :local :remote :env-override :cli-override))

(defstruct gateway-connection-details
  "Resolved gateway connection details."
  (url nil :type (or null string))
  (token nil :type (or null string))
  (password nil :type (or null string))
  (tls-fingerprint nil :type (or null string))
  (source :local :type connection-source)
  (note nil :type (or null string)))

(define-condition call-gateway-error (error)
  ((reason :initarg :reason :reader call-gateway-error-reason
           :type string)
   (details :initarg :details :reader call-gateway-error-details
            :type (or null gateway-connection-details)))
  (:report (lambda (c s)
             (format s "Gateway call error: ~a" (call-gateway-error-reason c)))))

;;; ============================================================
;;; URL Validation
;;; ============================================================

(declaim (ftype (function (string &key (:allow-insecure-private boolean)) string) validate-gateway-url))
(defun validate-gateway-url (url &key (allow-insecure-private nil))
  "Validate a gateway URL for security.
Rejects insecure ws:// URLs unless they are loopback or explicitly allowed.
Returns the URL if valid, signals error otherwise."
  (declare (type string url))
  (let ((lower (string-downcase url)))
    (cond
      ;; Secure WebSocket - always OK
      ((uiop:string-prefix-p "wss://" lower) url)
      ;; Secure HTTP - always OK
      ((uiop:string-prefix-p "https://" lower) url)
      ;; Insecure WebSocket
      ((uiop:string-prefix-p "ws://" lower)
       (let ((host (extract-ws-host url)))
         (cond
           ;; Loopback is OK for local mode
           ((loopback-host-p host) url)
           ;; Private allowed with explicit opt-in
           (allow-insecure-private url)
           ;; Otherwise reject (CWE-319)
           (t (error 'call-gateway-error
                     :reason (format nil "Insecure ws:// URL not allowed: ~a" url)
                     :details nil)))))
      ;; HTTP - OK for local
      ((uiop:string-prefix-p "http://" lower) url)
      ;; Unknown protocol
      (t (error 'call-gateway-error
                :reason (format nil "Unsupported protocol in URL: ~a" url)
                :details nil)))))

;;; ============================================================
;;; Connection Details Resolution
;;; ============================================================

(declaim (ftype (function (&key (:cli-url (or null string))
                                (:remote-url (or null string))
                                (:remote-token (or null string))
                                (:remote-password (or null string))
                                (:remote-tls-fingerprint (or null string))
                                (:local-token (or null string))
                                (:local-password (or null string))
                                (:env-fn (or null function))
                                (:allow-insecure-private boolean))
                          gateway-connection-details)
               build-gateway-connection-details))
(defun build-gateway-connection-details (&key cli-url remote-url
                                              remote-token remote-password
                                              remote-tls-fingerprint
                                              local-token local-password
                                              env-fn
                                              (allow-insecure-private nil))
  "Build resolved gateway connection details from available sources.
Priority: CLI override > env override > remote > local."
  (let* ((getter (or env-fn #'uiop:getenv))
         (env-url (funcall getter "OPENCLAW_GATEWAY_URL"))
         (env-token (funcall getter "OPENCLAW_GATEWAY_TOKEN"))
         (env-password (funcall getter "OPENCLAW_GATEWAY_PASSWORD")))
    (cond
      ;; CLI URL override
      (cli-url
       (validate-gateway-url cli-url :allow-insecure-private allow-insecure-private)
       (make-gateway-connection-details
        :url cli-url
        :token (or remote-token env-token)
        :password (or remote-password env-password)
        :source :cli-override))
      
      ;; Env URL override
      (env-url
       (validate-gateway-url env-url :allow-insecure-private allow-insecure-private)
       ;; Use env credentials, don't resolve local SecretRefs
       (make-gateway-connection-details
        :url env-url
        :token env-token
        :password env-password
        :tls-fingerprint remote-tls-fingerprint
        :source :env-override))
      
      ;; Remote URL
      (remote-url
       (validate-gateway-url remote-url :allow-insecure-private allow-insecure-private)
       ;; Resolve SecretRefs for remote credentials
       (let ((resolved-token (when remote-token
                               (if (secret-ref-p remote-token)
                                   (resolve-secret-ref remote-token :env-fn env-fn)
                                   remote-token)))
             (resolved-password (when remote-password
                                  (if (secret-ref-p remote-password)
                                      (resolve-secret-ref remote-password :env-fn env-fn)
                                      remote-password))))
         (make-gateway-connection-details
          :url remote-url
          :token resolved-token
          :password resolved-password
          :tls-fingerprint remote-tls-fingerprint
          :source :remote)))
      
      ;; Local mode - build from local config
      (t
       ;; Resolve local SecretRefs
       (let ((resolved-local-token (when local-token
                                     (if (secret-ref-p local-token)
                                         (resolve-secret-ref local-token :env-fn env-fn)
                                         local-token)))
             (resolved-local-password (when local-password
                                        (if (secret-ref-p local-password)
                                            (resolve-secret-ref local-password :env-fn env-fn)
                                            local-password))))
         (make-gateway-connection-details
          :url "ws://127.0.0.1:3578"
          :token (or resolved-local-token env-token)
          :password (or resolved-local-password env-password)
          :source :local
          :note (when (and (not remote-url) (not env-url))
                  "No remote URL configured, using local gateway")))))))

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun extract-ws-host (url)
  "Extract host from a WebSocket URL."
  (declare (type string url))
  (let* ((proto-end (or (search "://" url) 0))
         (host-start (+ proto-end 3))
         (rest (subseq url host-start))
         (host-end (or (position #\/ rest)
                       (position #\: rest)
                       (length rest))))
    (subseq rest 0 host-end)))

(defun loopback-host-p (host)
  "Return T if HOST is a loopback address or hostname."
  (declare (type string host))
  (or (string= host "127.0.0.1")
      (string= host "localhost")
      (string= host "::1")
      (uiop:string-prefix-p "127." host)))
