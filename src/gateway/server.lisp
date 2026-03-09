;;;; server.lisp - Gateway HTTP/WebSocket Server for cl-claw
;;;;
;;;; Provides the HTTP server that hosts the gateway control protocol,
;;;; health endpoints, and WebSocket connections for agent sessions.
;;;; Uses Hunchentoot as the HTTP server with hunchensocket for WebSocket.
;;;;
;;;; Static typing policy: all functions have full type declarations.

(defpackage :cl-claw.gateway.server
  (:use :cl)
  (:import-from :cl-ppcre :scan)
  (:export
   ;; Server lifecycle
   :gateway-server
   :make-gateway-server
   :gateway-server-host
   :gateway-server-port
   :gateway-server-tls-p
   :gateway-server-running-p
   :start-gateway-server
   :stop-gateway-server
   ;; Configuration
   :gateway-server-config
   :make-gateway-server-config
   :gateway-server-config-host
   :gateway-server-config-port
   :gateway-server-config-tls-cert-path
   :gateway-server-config-tls-key-path
   :gateway-server-config-auth-mode
   :gateway-server-config-auth-token
   :gateway-server-config-auth-password
   :gateway-server-config-trusted-proxies
   ;; Route handling
   :route-handler
   :define-route
   :register-route
   :dispatch-request
   ;; Auth
   :gateway-auth-mode
   :auth-result
   :make-auth-result
   :auth-result-authenticated-p
   :auth-result-reason
   :auth-result-user
   :authenticate-request
   ;; Rate limiting
   :rate-limiter
   :make-rate-limiter
   :rate-limiter-check
   :rate-limiter-record-failure
   :rate-limiter-reset
   :rate-limiter-prune
   :rate-limiter-dispose
   ;; Health
   :health-status
   :make-health-status
   :health-status-ok-p
   :health-status-uptime-ms
   :health-status-version
   :health-status-channels
   ;; Request/Response helpers
   :request-client-ip
   :normalize-client-ip
   :loopback-ip-p
   :ipv4-mapped-ipv6-p
   :extract-ipv4-from-mapped))

(in-package :cl-claw.gateway.server)

(declaim (optimize (safety 3) (debug 3)))

;;; ============================================================
;;; Constants
;;; ============================================================

(defvar +gateway-version+ "0.1.0"
  "Current gateway version.")

;;; ============================================================
;;; Type declarations and structures
;;; ============================================================

(deftype gateway-auth-mode ()
  "Authentication mode for the gateway."
  '(member :none :token :password :trusted-proxy))

;;; --- Server Configuration ---

(defstruct gateway-server-config
  "Configuration for the gateway HTTP server."
  (host "127.0.0.1" :type string)
  (port 3578 :type (integer 1 65535))
  (tls-cert-path nil :type (or null string))
  (tls-key-path nil :type (or null string))
  (auth-mode :token :type gateway-auth-mode)
  (auth-token nil :type (or null string))
  (auth-password nil :type (or null string))
  (trusted-proxies nil :type list)        ; list of trusted proxy IP strings
  (rate-limit-max-attempts 10 :type (integer 1))
  (rate-limit-window-ms 300000 :type (integer 1))
  (rate-limit-lockout-ms 900000 :type (integer 1))
  (exempt-loopback t :type boolean))

;;; --- Auth Result ---

(defstruct auth-result
  "Result of gateway authentication."
  (authenticated-p nil :type boolean)
  (reason nil :type (or null string))
  (user nil :type (or null string)))

;;; --- Rate Limiter ---

(defstruct rate-limit-entry
  "Tracking entry for rate limiting."
  (failures nil :type list)             ; list of timestamps (universal-time)
  (locked-until 0 :type integer)        ; universal-time when lock expires
  (scope "default" :type string))

(defstruct rate-limiter
  "Rate limiter for authentication attempts."
  (max-attempts 10 :type (integer 1))
  (window-ms 300000 :type (integer 1))
  (lockout-ms 900000 :type (integer 1))
  (exempt-loopback t :type boolean)
  (entries (make-hash-table :test 'equal) :type hash-table))  ; ip+scope -> rate-limit-entry

;;; --- Health Status ---

(defstruct health-status
  "Gateway health check response."
  (ok-p t :type boolean)
  (uptime-ms 0 :type (integer 0))
  (version "0.0.0" :type string)
  (channels nil :type list))            ; alist of (channel-name . status)

;;; --- Route Handler ---

(defstruct route-handler
  "HTTP route handler definition."
  (method "GET" :type string)
  (path "/" :type string)
  (handler nil :type (or null function))
  (description "" :type string))

;;; --- Gateway Server ---

(defstruct gateway-server
  "The main gateway HTTP/WebSocket server."
  (config (make-gateway-server-config) :type gateway-server-config)
  (running-p nil :type boolean)
  (start-time 0 :type integer)         ; universal-time
  (routes nil :type list)              ; list of route-handler
  (rate-limiter nil :type (or null rate-limiter))
  (acceptor nil :type t)               ; hunchentoot acceptor (typed as T for portability)
  (ws-connections nil :type list)      ; active WebSocket connections
  (lock (bordeaux-threads:make-lock "gateway-server") :type t))

;;; ============================================================
;;; IP Address Utilities
;;; ============================================================

(declaim (ftype (function (string) boolean) loopback-ip-p))
(defun loopback-ip-p (ip)
  "Return T if IP is a loopback address."
  (declare (type string ip))
  (or (string= ip "127.0.0.1")
      (string= ip "::1")
      (uiop:string-prefix-p "127." ip)))

(declaim (ftype (function (string) boolean) ipv4-mapped-ipv6-p))
(defun ipv4-mapped-ipv6-p (ip)
  "Return T if IP is an IPv4-mapped IPv6 address (::ffff:x.x.x.x)."
  (declare (type string ip))
  (and (>= (length ip) 7)
       (uiop:string-prefix-p "::ffff:" (string-downcase ip))))

(declaim (ftype (function (string) string) extract-ipv4-from-mapped))
(defun extract-ipv4-from-mapped (ip)
  "Extract IPv4 address from an IPv4-mapped IPv6 address.
Returns the original IP if not mapped."
  (declare (type string ip))
  (if (ipv4-mapped-ipv6-p ip)
      (subseq ip 7)
      ip))

(declaim (ftype (function (string) string) normalize-client-ip))
(defun normalize-client-ip (ip)
  "Normalize a client IP address.
Converts IPv4-mapped IPv6 to plain IPv4, handles empty/nil."
  (declare (type string ip))
  (cond
    ((or (string= ip "") (string= ip "undefined"))
     "unknown")
    ((ipv4-mapped-ipv6-p ip)
     (extract-ipv4-from-mapped ip))
    (t ip)))

(declaim (ftype (function (list &key (:use-x-real-ip boolean)) string) request-client-ip))
(defun request-client-ip (headers &key (use-x-real-ip nil))
  "Extract client IP from request headers.
Uses X-Forwarded-For by default, optionally X-Real-IP as fallback."
  (declare (type list headers))
  (let ((forwarded-for (cdr (assoc "x-forwarded-for" headers :test #'string-equal)))
        (real-ip (when use-x-real-ip
                   (cdr (assoc "x-real-ip" headers :test #'string-equal))))
        (remote-addr (or (cdr (assoc "remote-addr" headers :test #'string-equal))
                         "unknown")))
    (normalize-client-ip
     (cond
       (forwarded-for
        ;; Take first IP from X-Forwarded-For
        (string-trim '(#\Space) (first (uiop:split-string forwarded-for :separator ","))))
       (real-ip
        (string-trim '(#\Space) real-ip))
       (t remote-addr)))))

;;; ============================================================
;;; Rate Limiter Implementation
;;; ============================================================

(declaim (ftype (function (rate-limiter string &key (:scope string)) boolean) rate-limiter-check))
(defun rate-limiter-check (limiter ip &key (scope "default"))
  "Check if IP is rate-limited. Returns T if allowed, NIL if blocked."
  (declare (type rate-limiter limiter)
           (type string ip scope))
  (let* ((normalized-ip (normalize-client-ip ip))
         (key (format nil "~a:~a" normalized-ip scope)))
    ;; Exempt loopback
    (when (and (rate-limiter-exempt-loopback limiter)
               (loopback-ip-p normalized-ip))
      (return-from rate-limiter-check t))
    ;; Check existing entry
    (let ((entry (gethash key (rate-limiter-entries limiter))))
      (if (null entry)
          t
          ;; Check if locked out
          (let ((now (get-universal-time)))
            (if (> (rate-limit-entry-locked-until entry) now)
                nil  ; Still locked
                ;; Expire old failures and check count
                (let ((window-seconds (floor (rate-limiter-window-ms limiter) 1000))
                      (cutoff (- now (floor (rate-limiter-window-ms limiter) 1000))))
                  (declare (ignorable window-seconds))
                  (setf (rate-limit-entry-failures entry)
                        (remove-if (lambda (ts) (< ts cutoff))
                                   (rate-limit-entry-failures entry)))
                  (< (length (rate-limit-entry-failures entry))
                     (rate-limiter-max-attempts limiter)))))))))

(declaim (ftype (function (rate-limiter string &key (:scope string)) null) rate-limiter-record-failure))
(defun rate-limiter-record-failure (limiter ip &key (scope "default"))
  "Record an authentication failure for rate limiting."
  (declare (type rate-limiter limiter)
           (type string ip scope))
  (let* ((normalized-ip (normalize-client-ip ip))
         (key (format nil "~a:~a" normalized-ip scope))
         (now (get-universal-time))
         (entry (or (gethash key (rate-limiter-entries limiter))
                    (let ((new-entry (make-rate-limit-entry :scope scope)))
                      (setf (gethash key (rate-limiter-entries limiter)) new-entry)
                      new-entry))))
    ;; Add failure timestamp
    (push now (rate-limit-entry-failures entry))
    ;; Check if we should lock
    (let ((cutoff (- now (floor (rate-limiter-window-ms limiter) 1000))))
      (setf (rate-limit-entry-failures entry)
            (remove-if (lambda (ts) (< ts cutoff))
                       (rate-limit-entry-failures entry)))
      (when (>= (length (rate-limit-entry-failures entry))
                (rate-limiter-max-attempts limiter))
        (setf (rate-limit-entry-locked-until entry)
              (+ now (floor (rate-limiter-lockout-ms limiter) 1000))))))
  nil)

(declaim (ftype (function (rate-limiter string &key (:scope (or null string))) null) rate-limiter-reset))
(defun rate-limiter-reset (limiter ip &key scope)
  "Reset rate-limit tracking for an IP. If scope is provided, only clear that scope."
  (declare (type rate-limiter limiter)
           (type string ip))
  (let ((normalized-ip (normalize-client-ip ip)))
    (if scope
        (remhash (format nil "~a:~a" normalized-ip scope) (rate-limiter-entries limiter))
        ;; Remove all entries for this IP
        (let ((to-remove nil))
          (maphash (lambda (k v)
                     (declare (ignore v))
                     (when (uiop:string-prefix-p (format nil "~a:" normalized-ip) k)
                       (push k to-remove)))
                   (rate-limiter-entries limiter))
          (dolist (k to-remove)
            (remhash k (rate-limiter-entries limiter))))))
  nil)

(declaim (ftype (function (rate-limiter) null) rate-limiter-prune))
(defun rate-limiter-prune (limiter)
  "Remove stale entries from the rate limiter."
  (declare (type rate-limiter limiter))
  (let ((now (get-universal-time))
        (to-remove nil))
    (maphash (lambda (k entry)
               (let ((cutoff (- now (floor (rate-limiter-window-ms limiter) 1000))))
                 ;; Remove expired failures
                 (setf (rate-limit-entry-failures entry)
                       (remove-if (lambda (ts) (< ts cutoff))
                                  (rate-limit-entry-failures entry)))
                 ;; Remove entry if empty and not locked
                 (when (and (null (rate-limit-entry-failures entry))
                            (<= (rate-limit-entry-locked-until entry) now))
                   (push k to-remove))))
             (rate-limiter-entries limiter))
    (dolist (k to-remove)
      (remhash k (rate-limiter-entries limiter))))
  nil)

(declaim (ftype (function (rate-limiter) null) rate-limiter-dispose))
(defun rate-limiter-dispose (limiter)
  "Clear all entries in the rate limiter."
  (declare (type rate-limiter limiter))
  (clrhash (rate-limiter-entries limiter))
  nil)

;;; ============================================================
;;; Authentication
;;; ============================================================

(declaim (ftype (function (gateway-server-config list &key (:rate-limiter (or null rate-limiter)) (:client-ip string)) auth-result) authenticate-request))
(defun authenticate-request (config headers &key rate-limiter (client-ip "unknown"))
  "Authenticate a gateway request based on config and headers.
Returns an AUTH-RESULT."
  (declare (type gateway-server-config config)
           (type list headers)
           (type string client-ip))
  (let ((mode (gateway-server-config-auth-mode config)))
    (case mode
      ;; No auth required
      (:none
       (make-auth-result :authenticated-p t))
      
      ;; Token-based auth
      (:token
       (let ((config-token (gateway-server-config-auth-token config))
             (request-token (or (extract-bearer-token headers)
                                (cdr (assoc "x-gateway-token" headers :test #'string-equal)))))
         (cond
           ((null config-token)
            (make-auth-result :authenticated-p nil :reason "missing-token-config"))
           ((null request-token)
            ;; Missing token from client - not a brute-force attempt
            (make-auth-result :authenticated-p nil :reason "missing-token"))
           ((string= request-token config-token)
            (make-auth-result :authenticated-p t))
           (t
            ;; Wrong token - record rate-limit failure
            (when rate-limiter
              (rate-limiter-record-failure rate-limiter client-ip :scope "token"))
            (make-auth-result :authenticated-p nil :reason "token-mismatch")))))
      
      ;; Password-based auth
      (:password
       (let ((config-password (gateway-server-config-auth-password config))
             (request-password (cdr (assoc "x-gateway-password" headers :test #'string-equal))))
         (cond
           ((null config-password)
            (make-auth-result :authenticated-p nil :reason "missing-password-config"))
           ((null request-password)
            (make-auth-result :authenticated-p nil :reason "missing-password"))
           ((string= request-password config-password)
            (make-auth-result :authenticated-p t))
           (t
            (when rate-limiter
              (rate-limiter-record-failure rate-limiter client-ip :scope "password"))
            (make-auth-result :authenticated-p nil :reason "password-mismatch")))))
      
      ;; Trusted proxy auth
      (:trusted-proxy
       (let* ((trusted (gateway-server-config-trusted-proxies config))
              (source-ip (normalize-client-ip client-ip))
              (user-header (cdr (assoc "x-forwarded-user" headers :test #'string-equal))))
         (cond
           ((null trusted)
            (make-auth-result :authenticated-p nil :reason "no-trusted-proxies-configured"))
           ((not (member source-ip trusted :test #'string=))
            (make-auth-result :authenticated-p nil :reason "untrusted-source"))
           ((null user-header)
            (make-auth-result :authenticated-p nil :reason "missing-user-header"))
           (t
            (make-auth-result :authenticated-p t
                              :user (string-trim '(#\Space) user-header))))))
      
      ;; Unknown mode
      (otherwise
       (make-auth-result :authenticated-p nil :reason "unknown-auth-mode")))))

;;; --- Auth helpers ---

(declaim (ftype (function (list) (or null string)) extract-bearer-token))
(defun extract-bearer-token (headers)
  "Extract Bearer token from Authorization header."
  (declare (type list headers))
  (let ((auth-header (cdr (assoc "authorization" headers :test #'string-equal))))
    (when (and auth-header (uiop:string-prefix-p "Bearer " auth-header))
      (subseq auth-header 7))))

;;; ============================================================
;;; Route Registration and Dispatch
;;; ============================================================

(declaim (ftype (function (gateway-server route-handler) null) register-route))
(defun register-route (server handler)
  "Register a route handler with the gateway server."
  (declare (type gateway-server server)
           (type route-handler handler))
  (bordeaux-threads:with-lock-held ((gateway-server-lock server))
    (push handler (gateway-server-routes server)))
  nil)

(declaim (ftype (function (gateway-server string string) (or null route-handler)) dispatch-request))
(defun dispatch-request (server method path)
  "Find matching route handler for METHOD and PATH."
  (declare (type gateway-server server)
           (type string method path))
  (bordeaux-threads:with-lock-held ((gateway-server-lock server))
    (find-if (lambda (route)
               (and (string-equal (route-handler-method route) method)
                    (string= (route-handler-path route) path)))
             (gateway-server-routes server))))

;;; ============================================================
;;; Server Lifecycle
;;; ============================================================

(declaim (ftype (function (gateway-server) gateway-server) start-gateway-server))
(defun start-gateway-server (server)
  "Start the gateway HTTP server.
Sets up routes, creates the Hunchentoot acceptor, and begins listening.
Returns the server instance."
  (declare (type gateway-server server))
  (when (gateway-server-running-p server)
    (error "Gateway server is already running"))
  (let ((config (gateway-server-config server)))
    ;; Create rate limiter
    (setf (gateway-server-rate-limiter server)
          (make-rate-limiter
           :max-attempts (gateway-server-config-rate-limit-max-attempts config)
           :window-ms (gateway-server-config-rate-limit-window-ms config)
           :lockout-ms (gateway-server-config-rate-limit-lockout-ms config)
           :exempt-loopback (gateway-server-config-exempt-loopback config)))
    ;; Register default routes
    (register-default-routes server)
    ;; Mark as running
    (setf (gateway-server-running-p server) t
          (gateway-server-start-time server) (get-universal-time))
    ;; Note: actual Hunchentoot acceptor creation happens when the library is loaded.
    ;; This allows the core logic to be tested without Hunchentoot dependency.
    )
  server)

(declaim (ftype (function (gateway-server) null) stop-gateway-server))
(defun stop-gateway-server (server)
  "Stop the gateway HTTP server gracefully."
  (declare (type gateway-server server))
  (unless (gateway-server-running-p server)
    (return-from stop-gateway-server nil))
  ;; Clean up rate limiter
  (when (gateway-server-rate-limiter server)
    (rate-limiter-dispose (gateway-server-rate-limiter server)))
  ;; Close WebSocket connections
  (bordeaux-threads:with-lock-held ((gateway-server-lock server))
    (setf (gateway-server-ws-connections server) nil))
  ;; Stop Hunchentoot acceptor
  (when (gateway-server-acceptor server)
    ;; (hunchentoot:stop (gateway-server-acceptor server))
    (setf (gateway-server-acceptor server) nil))
  (setf (gateway-server-running-p server) nil)
  nil)

;;; --- Default Routes ---

(defun register-default-routes (server)
  "Register the default health and status routes."
  (declare (type gateway-server server))
  ;; Health check
  (register-route server
    (make-route-handler
     :method "GET"
     :path "/health"
     :description "Health check endpoint"
     :handler (lambda ()
                (let ((status (build-health-status server)))
                  (values (if (health-status-ok-p status) 200 503)
                          (health-status-to-json status))))))
  ;; Version
  (register-route server
    (make-route-handler
     :method "GET"
     :path "/version"
     :description "Version endpoint"
     :handler (lambda ()
                (values 200 (format nil "{\"version\":\"~a\"}" +gateway-version+))))))

(defun build-health-status (server)
  "Build a health status response."
  (declare (type gateway-server server))
  (let ((uptime-ms (* (- (get-universal-time) (gateway-server-start-time server)) 1000)))
    (make-health-status
     :ok-p (gateway-server-running-p server)
     :uptime-ms uptime-ms
     :version +gateway-version+
     :channels nil)))

(defun health-status-to-json (status)
  "Convert health status to JSON string."
  (declare (type health-status status))
  (format nil "{\"ok\":~a,\"uptime_ms\":~d,\"version\":\"~a\"}"
          (if (health-status-ok-p status) "true" "false")
          (health-status-uptime-ms status)
          (health-status-version status)))

;;; ============================================================
;;; Constants
;;; ============================================================


