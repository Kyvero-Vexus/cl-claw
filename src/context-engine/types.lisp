;;;; types.lisp — Context engine type definitions
;;;;
;;;; Defines the core data structures for the context engine:
;;;; engine info, ingest/assemble/compact results, and the
;;;; context-engine protocol (CLOS generic functions).

(defpackage :cl-claw.context-engine.types
  (:use :cl)
  (:export
   ;; Engine info
   :context-engine-info
   :make-context-engine-info
   :context-engine-info-id
   :context-engine-info-name
   :context-engine-info-version

   ;; Ingest result
   :ingest-result
   :make-ingest-result
   :ingest-result-ingested-p

   ;; Assemble result
   :assemble-result
   :make-assemble-result
   :assemble-result-messages
   :assemble-result-estimated-tokens
   :assemble-result-system-prompt-addition

   ;; Compact result detail
   :compact-result-detail
   :make-compact-result-detail
   :compact-result-detail-summary
   :compact-result-detail-tokens-before
   :compact-result-detail-tokens-after

   ;; Compact result
   :compact-result
   :make-compact-result
   :compact-result-ok-p
   :compact-result-compacted-p
   :compact-result-reason
   :compact-result-detail

   ;; Agent message (hash-table wrapper for transcript messages)
   :agent-message
   :agent-message-role
   :agent-message-content
   :agent-message-timestamp-ms

   ;; Context file
   :context-file
   :make-context-file
   :context-file-path
   :context-file-content

   ;; Context engine protocol
   :context-engine
   :engine-info
   :engine-ingest
   :engine-assemble
   :engine-compact
   :engine-dispose))

(in-package :cl-claw.context-engine.types)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Context engine info
;;; -----------------------------------------------------------------------

(defstruct context-engine-info
  "Metadata about a context engine implementation."
  (id   "" :type string)
  (name "" :type string)
  (version "0.0.0" :type string))

;;; -----------------------------------------------------------------------
;;; Result types
;;; -----------------------------------------------------------------------

(defstruct ingest-result
  "Result from ingesting a message into the context engine."
  (ingested-p nil :type boolean))

(defstruct assemble-result
  "Result from assembling context for an LLM call."
  (messages '() :type list)
  (estimated-tokens 0 :type fixnum)
  (system-prompt-addition nil :type (or string null)))

(defstruct compact-result-detail
  "Detail about a compaction operation."
  (summary "" :type string)
  (tokens-before 0 :type fixnum)
  (tokens-after 0 :type fixnum))

(defstruct compact-result
  "Result from compacting session history."
  (ok-p nil :type boolean)
  (compacted-p nil :type boolean)
  (reason nil :type (or string null))
  (detail nil :type (or compact-result-detail null)))

;;; -----------------------------------------------------------------------
;;; Agent message accessors (hash-table based, matching transcript format)
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table) string) agent-message-role))
(defun agent-message-role (msg)
  "Get the role from an agent message hash-table."
  (declare (type hash-table msg))
  (the string (or (gethash "role" msg) "")))

(declaim (ftype (function (hash-table) string) agent-message-content))
(defun agent-message-content (msg)
  "Get the content from an agent message hash-table."
  (declare (type hash-table msg))
  (the string (or (gethash "content" msg) "")))

(declaim (ftype (function (hash-table) fixnum) agent-message-timestamp-ms))
(defun agent-message-timestamp-ms (msg)
  "Get the timestamp (ms) from an agent message hash-table."
  (declare (type hash-table msg))
  (the fixnum (or (gethash "timestampMs" msg) 0)))

;; Type alias for clarity in signatures
(deftype agent-message () 'hash-table)

;;; -----------------------------------------------------------------------
;;; Context file — a workspace file loaded for prompt injection
;;; -----------------------------------------------------------------------

(defstruct context-file
  "A workspace file to inject into the system prompt."
  (path "" :type string)
  (content "" :type string))

;;; -----------------------------------------------------------------------
;;; Context engine protocol (CLOS generic functions)
;;; -----------------------------------------------------------------------

(defclass context-engine ()
  ()
  (:documentation "Abstract base class for context engine implementations."))

(defgeneric engine-info (engine)
  (:documentation "Return the context-engine-info for this engine."))

(defgeneric engine-ingest (engine session-id message &key is-heartbeat)
  (:documentation "Ingest a message into the engine's context store.
Returns an ingest-result."))

(defgeneric engine-assemble (engine session-id messages &key token-budget)
  (:documentation "Assemble messages for an LLM call, respecting token budget.
Returns an assemble-result."))

(defgeneric engine-compact (engine session-id session-file
                            &key token-budget compaction-target
                                 custom-instructions)
  (:documentation "Compact session history to fit within budget.
Returns a compact-result."))

(defgeneric engine-dispose (engine)
  (:documentation "Release any resources held by this engine.")
  (:method ((engine context-engine))
    ;; Default: no-op
    (declare (ignore engine))
    (values)))
