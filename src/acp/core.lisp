;;;; core.lisp — ACP top-level API: session manager integration, turn execution
;;;;
;;;; Provides the high-level ACP session manager that integrates the session store,
;;;; runtime cache, backend registry, and policy checks into a unified interface
;;;; for managing ACP sessions and dispatching turns.

(defpackage :cl-claw.acp
  (:use :cl
        :cl-claw.acp.types
        :cl-claw.acp.policy
        :cl-claw.acp.session
        :cl-claw.acp.runtime-cache
        :cl-claw.acp.registry
        :cl-claw.acp.persistent-bindings
        :cl-claw.acp.client
        :cl-claw.acp.translator
        :cl-claw.acp.server)
  (:export
   ;; Re-export key symbols from submodules
   ;; Types
   :acp-error :acp-error-code :acp-error-text
   :acp-session-full-error :acp-dispatch-disabled-error
   :acp-agent-not-allowed-error :acp-rate-limit-error
   :acp-runtime-error
   :acp-runtime-handle :acp-session-meta :acp-session-entry
   :acp-binding-spec :acp-binding-record
   ;; Policy
   :acp-enabled-by-policy-p :acp-dispatch-enabled-by-policy-p
   :acp-agent-allowed-by-policy-p
   ;; Session store
   :create-session-store
   :session-store-create-session :session-store-get-session
   :session-store-has-session-p :session-store-set-active-run
   :session-store-cancel-active-run
   ;; Runtime cache
   :make-runtime-cache :runtime-cache-set :runtime-cache-get
   :runtime-cache-collect-idle-candidates :runtime-cache-snapshot
   ;; Registry
   :make-runtime-registry :registry-register-backend
   :registry-require-backend :format-acp-error-text
   ;; Bindings
   :build-configured-acp-session-key
   :resolve-configured-acp-binding-record
   ;; Client
   :resolve-acp-client-spawn-env :resolve-acp-client-spawn-invocation
   ;; Translator
   :prefix-prompt-with-cwd :redact-home-in-path
   :make-rate-limiter :rate-limiter-allow-p :validate-prompt-size
   ;; Server
   :resolve-acp-server-credentials :build-gateway-hello-payload
   :validate-acp-server-startup :acp-server-startup-check
   ;; Manager
   :make-acp-session-manager
   :acp-session-manager
   :manager-resolve-session
   :manager-initialize-session
   :manager-close-session))

(in-package :cl-claw.acp)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── ACP Session Manager ────────────────────────────────────────────────────
;;; Combines session store + runtime cache + registry + policy into one manager.

(defstruct (acp-session-manager (:conc-name acp-manager-)
                                  (:constructor %make-acp-session-manager))
  "Unified ACP session manager."
  (config (make-hash-table :test 'equal) :type hash-table)
  (session-store nil :type (or cl-claw.acp.session::session-store null))
  (runtime-cache nil :type (or runtime-cache null))
  (registry nil :type (or runtime-registry null))
  (rate-limiter nil :type (or rate-limiter null)))

(declaim (ftype (function (hash-table &key (:max-sessions fixnum)
                                           (:idle-ttl-ms fixnum)
                                           (:rate-max fixnum)
                                           (:rate-window-ms fixnum))
                          acp-session-manager)
                make-acp-session-manager))
(defun make-acp-session-manager (cfg &key (max-sessions 100) (idle-ttl-ms 3600000)
                                          (rate-max 30) (rate-window-ms 60000))
  "Create a fully initialized ACP session manager."
  (declare (type hash-table cfg)
           (type fixnum max-sessions idle-ttl-ms rate-max rate-window-ms))
  (let ((manager (%make-acp-session-manager)))
    (setf (acp-manager-config manager) cfg
          (acp-manager-session-store manager) (cl-claw.acp.session::create-session-store
                                               :max-sessions max-sessions
                                               :idle-ttl-ms idle-ttl-ms)
          (acp-manager-runtime-cache manager) (make-runtime-cache)
          (acp-manager-registry manager) (make-runtime-registry)
          (acp-manager-rate-limiter manager) (make-rate-limiter
                                              :max-requests rate-max
                                              :window-ms rate-window-ms))
    manager))

;;; ─── Manager Operations ─────────────────────────────────────────────────────

(declaim (ftype (function (acp-session-manager string) (or acp-session-entry null))
                manager-resolve-session))
(defun manager-resolve-session (manager session-id)
  "Resolve an existing session by ID."
  (declare (type acp-session-manager manager) (type string session-id))
  (session-store-get-session (acp-manager-session-store manager) session-id))

(declaim (ftype (function (acp-session-manager &key (:session-id string)
                                                    (:session-key string)
                                                    (:cwd string)
                                                    (:agent string))
                          acp-session-entry)
                manager-initialize-session))
(defun manager-initialize-session (manager &key session-id session-key cwd (agent ""))
  "Initialize a new ACP session with policy checks."
  (declare (type acp-session-manager manager)
           (type string session-key cwd agent)
           (type (or string null) session-id))
  ;; Policy checks
  (unless (acp-enabled-by-policy-p (acp-manager-config manager))
    (error 'acp-dispatch-disabled-error
           :text "ACP is disabled by policy"))
  (unless (acp-dispatch-enabled-by-policy-p (acp-manager-config manager))
    (error 'acp-dispatch-disabled-error
           :text "ACP dispatch is disabled by policy"))
  (when (and (not (string= agent ""))
             (not (acp-agent-allowed-by-policy-p (acp-manager-config manager) agent)))
    (error 'acp-agent-not-allowed-error
           :code "ACP_SESSION_INIT_FAILED"
           :text (format nil "Agent '~A' is not in the ACP allowed agents list" agent)))
  ;; Rate limit check
  (let ((limiter (acp-manager-rate-limiter manager)))
    (when limiter
      (let ((now (get-universal-time)))
        (unless (rate-limiter-allow-p limiter :now now)
          (error 'acp-rate-limit-error
                 :text "Session creation rate limit exceeded")))))
  ;; Create session
  (session-store-create-session
   (acp-manager-session-store manager)
   :session-id session-id
   :session-key session-key
   :cwd cwd))

(declaim (ftype (function (acp-session-manager string) hash-table)
                manager-close-session))
(defun manager-close-session (manager session-id)
  "Close and remove an ACP session. Returns a result hash-table."
  (declare (type acp-session-manager manager) (type string session-id))
  (let ((store (acp-manager-session-store manager))
        (cache (acp-manager-runtime-cache manager))
        (result (make-hash-table :test 'equal)))
    ;; Cancel any active run
    (session-store-cancel-active-run store session-id)
    ;; Remove from session store
    (let ((removed (session-store-remove-session store session-id)))
      (setf (gethash "metaCleared" result) removed))
    ;; Remove from runtime cache if present
    (let ((cache-removed (runtime-cache-remove cache session-id)))
      (setf (gethash "runtimeClosed" result) cache-removed))
    result))
