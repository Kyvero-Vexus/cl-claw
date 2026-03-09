;;;; types.lisp — ACP core types, conditions, and protocol structures
;;;;
;;;; Provides the foundational type definitions for the Agent Client Protocol
;;;; (ACP) subsystem: runtime handles, session state, capability descriptors,
;;;; error conditions, and event types.

(defpackage :cl-claw.acp.types
  (:use :cl)
  (:export
   ;; --- Conditions ---
   :acp-error
   :acp-error-code
   :acp-error-text
   :acp-session-full-error
   :acp-dispatch-disabled-error
   :acp-agent-not-allowed-error
   :acp-rate-limit-error
   :acp-runtime-error
   :acp-runtime-error-backend
   ;; --- Enums / constants ---
   :+acp-session-state-idle+
   :+acp-session-state-running+
   :+acp-session-state-closing+
   :+acp-session-state-error+
   :+acp-mode-persistent+
   :+acp-mode-oneshot+
   :+acp-dispatch-state-enabled+
   :+acp-dispatch-state-acp-disabled+
   :+acp-dispatch-state-dispatch-disabled+
   ;; --- Structs ---
   :make-acp-runtime-handle
   :acp-runtime-handle
   :acp-runtime-handle-session-key
   :acp-runtime-handle-backend
   :acp-runtime-handle-runtime-session-name
   :make-acp-session-meta
   :acp-session-meta
   :acp-session-meta-backend
   :acp-session-meta-agent
   :acp-session-meta-runtime-session-name
   :acp-session-meta-mode
   :acp-session-meta-state
   :acp-session-meta-last-activity-at
   :acp-session-meta-runtime-options
   :make-acp-session-entry
   :acp-session-entry
   :acp-session-entry-session-id
   :acp-session-entry-session-key
   :acp-session-entry-cwd
   :acp-session-entry-created-at
   :acp-session-entry-last-touched-at
   :acp-session-entry-active-run-id
   :acp-session-entry-abort-controller
   :make-acp-runtime-capabilities
   :acp-runtime-capabilities
   :acp-runtime-capabilities-controls
   :make-acp-binding-spec
   :acp-binding-spec
   :acp-binding-spec-channel
   :acp-binding-spec-account-id
   :acp-binding-spec-conversation-id
   :acp-binding-spec-agent-id
   :acp-binding-spec-cwd
   :make-acp-binding-record
   :acp-binding-record
   :acp-binding-record-target-session-key
   :acp-binding-record-metadata
   :make-acp-idle-candidate
   :acp-idle-candidate
   :acp-idle-candidate-actor-key
   :acp-idle-candidate-idle-ms
   :make-cached-runtime-state
   :cached-runtime-state
   :cached-runtime-state-handle
   :cached-runtime-state-backend
   :cached-runtime-state-agent
   :cached-runtime-state-mode
   :cached-runtime-state-last-touched-at
   :make-acp-snapshot-entry
   :acp-snapshot-entry
   :acp-snapshot-entry-actor-key
   :acp-snapshot-entry-backend
   :acp-snapshot-entry-agent
   :acp-snapshot-entry-mode
   :acp-snapshot-entry-idle-ms))

(in-package :cl-claw.acp.types)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Conditions ─────────────────────────────────────────────────────────────

(define-condition acp-error (error)
  ((code :initarg :code :reader acp-error-code :type string)
   (text :initarg :text :reader acp-error-text :type string))
  (:report (lambda (c s)
             (format s "ACP error [~A]: ~A" (acp-error-code c) (acp-error-text c)))))

(define-condition acp-session-full-error (acp-error) ()
  (:default-initargs :code "ACP_SESSION_FULL"))

(define-condition acp-dispatch-disabled-error (acp-error) ()
  (:default-initargs :code "ACP_DISPATCH_DISABLED"))

(define-condition acp-agent-not-allowed-error (acp-error) ()
  (:default-initargs :code "ACP_AGENT_NOT_ALLOWED"))

(define-condition acp-rate-limit-error (acp-error) ()
  (:default-initargs :code "ACP_RATE_LIMIT"))

(define-condition acp-runtime-error (acp-error)
  ((backend :initarg :backend :reader acp-runtime-error-backend
            :type (or string null) :initform nil))
  (:default-initargs :code "ACP_RUNTIME_ERROR"))

;;; ─── Constants ──────────────────────────────────────────────────────────────

(defvar +acp-session-state-idle+ "idle")
(defvar +acp-session-state-running+ "running")
(defvar +acp-session-state-closing+ "closing")
(defvar +acp-session-state-error+ "error")

(defvar +acp-mode-persistent+ "persistent")
(defvar +acp-mode-oneshot+ "oneshot")

(defvar +acp-dispatch-state-enabled+ "enabled")
(defvar +acp-dispatch-state-acp-disabled+ "acp_disabled")
(defvar +acp-dispatch-state-dispatch-disabled+ "dispatch_disabled")

;;; ─── Structs ────────────────────────────────────────────────────────────────

(defstruct (acp-runtime-handle (:conc-name acp-runtime-handle-))
  "Handle returned after ensuring a session on a runtime backend."
  (session-key "" :type string)
  (backend "" :type string)
  (runtime-session-name "" :type string))

(defstruct (acp-session-meta (:conc-name acp-session-meta-))
  "Metadata describing current state of an ACP session."
  (backend "" :type string)
  (agent "" :type string)
  (runtime-session-name "" :type string)
  (mode "persistent" :type string)
  (state "idle" :type string)
  (last-activity-at 0 :type fixnum)
  (runtime-options nil :type (or hash-table null)))

(defstruct (acp-session-entry (:conc-name acp-session-entry-))
  "In-memory session entry tracked by the session store."
  (session-id "" :type string)
  (session-key "" :type string)
  (cwd "" :type string)
  (created-at 0 :type fixnum)
  (last-touched-at 0 :type fixnum)
  (active-run-id nil :type (or string null))
  (abort-controller nil :type t))

(defstruct (acp-runtime-capabilities (:conc-name acp-runtime-capabilities-))
  "Capabilities reported by a runtime backend."
  (controls nil :type list))

(defstruct (acp-binding-spec (:conc-name acp-binding-spec-))
  "Specification for an ACP persistent binding."
  (channel "" :type string)
  (account-id "" :type string)
  (conversation-id "" :type string)
  (agent-id "" :type string)
  (cwd "" :type string))

(defstruct (acp-binding-record (:conc-name acp-binding-record-))
  "Record mapping a binding spec to a target session key."
  (target-session-key "" :type string)
  (metadata nil :type (or hash-table null)))

(defstruct (acp-idle-candidate (:conc-name acp-idle-candidate-))
  "An entry identified as idle in the runtime cache."
  (actor-key "" :type string)
  (idle-ms 0 :type fixnum))

(defstruct (cached-runtime-state (:conc-name cached-runtime-state-))
  "State stored in the runtime cache for an active actor."
  (handle nil :type (or acp-runtime-handle null))
  (backend "" :type string)
  (agent "" :type string)
  (mode "persistent" :type string)
  (last-touched-at 0 :type fixnum))

(defstruct (acp-snapshot-entry (:conc-name acp-snapshot-entry-))
  "A point-in-time snapshot entry for a cached runtime."
  (actor-key "" :type string)
  (backend "" :type string)
  (agent "" :type string)
  (mode "" :type string)
  (idle-ms 0 :type fixnum))
