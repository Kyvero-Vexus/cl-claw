;;;; server.lisp — ACP server startup, gateway hello handshake, credential passing
;;;;
;;;; Manages the ACP server lifecycle: startup sequence with gateway handshake,
;;;; credential resolution and passing to ACP clients, and shutdown coordination.

(defpackage :cl-claw.acp.server
  (:use :cl :cl-claw.acp.types :cl-claw.acp.policy :cl-claw.acp.registry)
  (:export
   :make-acp-server-config
   :acp-server-config
   :acp-server-config-backend
   :acp-server-config-host
   :acp-server-config-port
   :acp-server-config-credentials
   :resolve-acp-server-credentials
   :build-gateway-hello-payload
   :validate-acp-server-startup
   :acp-server-startup-check))

(in-package :cl-claw.acp.server)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Server Config ──────────────────────────────────────────────────────────

(defstruct (acp-server-config (:conc-name acp-server-config-))
  "Configuration for an ACP server instance."
  (backend "acpx" :type string)
  (host "127.0.0.1" :type string)
  (port 0 :type fixnum)
  (credentials nil :type (or hash-table null)))

;;; ─── Credential Resolution ──────────────────────────────────────────────────

(declaim (ftype (function (hash-table &key (:env-prefix string)) hash-table)
                resolve-acp-server-credentials))
(defun resolve-acp-server-credentials (cfg &key (env-prefix "OPENCLAW"))
  "Resolve credentials for the ACP server from config and environment.
   Returns a hash-table of credential key→value pairs."
  (declare (type hash-table cfg) (type string env-prefix))
  (let ((creds (make-hash-table :test 'equal))
        (acp (gethash "acp" cfg)))
    ;; Check for explicit credentials in config
    (when (hash-table-p acp)
      (let ((explicit-creds (gethash "credentials" acp)))
        (when (hash-table-p explicit-creds)
          (maphash (lambda (k v)
                     (when (stringp v)
                       (setf (gethash k creds) v)))
                   explicit-creds))))
    ;; Check environment variables
    (let ((api-key-env (format nil "~A_API_KEY" env-prefix)))
      (let ((env-val (uiop:getenv api-key-env)))
        (when (and (stringp env-val) (not (string= env-val "")))
          (unless (gethash "apiKey" creds)
            (setf (gethash "apiKey" creds) env-val)))))
    creds))

;;; ─── Gateway Hello Handshake ────────────────────────────────────────────────

(declaim (ftype (function (string &key (:version string)
                                       (:capabilities list)
                                       (:agent string))
                          hash-table)
                build-gateway-hello-payload))
(defun build-gateway-hello-payload (backend &key (version "1.0")
                                                  (capabilities nil)
                                                  (agent ""))
  "Build the hello payload for the gateway handshake."
  (declare (type string backend version agent)
           (type list capabilities))
  (let ((payload (make-hash-table :test 'equal)))
    (setf (gethash "protocol" payload) "acp"
          (gethash "version" payload) version
          (gethash "backend" payload) backend)
    (when (not (string= agent ""))
      (setf (gethash "agent" payload) agent))
    (when capabilities
      (setf (gethash "capabilities" payload) capabilities))
    payload))

;;; ─── Startup Validation ─────────────────────────────────────────────────────

(defstruct (startup-check-result (:conc-name startup-check-))
  "Result of a startup readiness check."
  (ready-p t :type boolean)
  (errors nil :type list)
  (warnings nil :type list))

(declaim (ftype (function (hash-table) startup-check-result)
                validate-acp-server-startup))
(defun validate-acp-server-startup (cfg)
  "Validate that the configuration is suitable for ACP server startup.
   Returns a startup-check-result."
  (declare (type hash-table cfg))
  (let ((result (make-startup-check-result))
        (acp (gethash "acp" cfg)))
    ;; Check if ACP is enabled
    (unless (acp-enabled-by-policy-p cfg)
      (push "ACP is disabled in configuration" (startup-check-errors result))
      (setf (startup-check-ready-p result) nil))
    ;; Check for backend specification
    (when (hash-table-p acp)
      (let ((backend (gethash "backend" acp)))
        (when (or (null backend) (and (stringp backend) (string= backend "")))
          (push "No ACP backend specified" (startup-check-warnings result)))))
    ;; Check dispatch
    (unless (acp-dispatch-enabled-by-policy-p cfg)
      (push "ACP dispatch is disabled" (startup-check-warnings result)))
    result))

(declaim (ftype (function (hash-table runtime-registry) startup-check-result)
                acp-server-startup-check))
(defun acp-server-startup-check (cfg registry)
  "Full startup check including registry health verification."
  (declare (type hash-table cfg) (type runtime-registry registry))
  (let ((result (validate-acp-server-startup cfg)))
    ;; Check if any backends are registered
    (when (null (registry-list-backends registry))
      (push "No ACP runtime backends registered" (startup-check-warnings result)))
    ;; Check backend health
    (dolist (entry (registry-list-backends registry))
      (unless (backend-entry-healthy entry)
        (push (format nil "Backend '~A' is unhealthy" (backend-entry-id entry))
              (startup-check-warnings result))))
    result))
