;;;; registry.lisp — Context engine registry
;;;;
;;;; Manages registration and resolution of context engine implementations.
;;;; Provides a pluggable context engine architecture matching OpenClaw's
;;;; plugin slot system.

(defpackage :cl-claw.context-engine.registry
  (:use :cl)
  (:import-from :cl-claw.context-engine.types
                :context-engine
                :context-engine-info
                :make-context-engine-info
                :engine-info
                :engine-ingest
                :engine-assemble
                :engine-compact
                :engine-dispose
                :ingest-result
                :make-ingest-result
                :assemble-result
                :make-assemble-result
                :compact-result
                :make-compact-result)
  (:export
   ;; Registry operations
   :register-context-engine
   :get-context-engine-factory
   :list-context-engine-ids
   :resolve-context-engine

   ;; Legacy engine
   :legacy-context-engine
   :register-legacy-context-engine

   ;; Initialization
   :ensure-context-engines-initialized))

(in-package :cl-claw.context-engine.registry)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Registry state
;;; -----------------------------------------------------------------------

(defvar *engine-registry* (make-hash-table :test 'equal)
  "Map from engine-id (string) to factory function (-> context-engine).")

(defvar *engines-initialized-p* nil
  "Whether the engine registry has been initialized.")

;;; -----------------------------------------------------------------------
;;; Registry operations
;;; -----------------------------------------------------------------------

(declaim (ftype (function (string function) (values)) register-context-engine))
(defun register-context-engine (id factory)
  "Register a context engine factory under the given ID.
FACTORY is a zero-argument function that returns a context-engine instance."
  (declare (type string id)
           (type function factory))
  (setf (gethash id *engine-registry*) factory)
  (values))

(declaim (ftype (function (string) (or function null)) get-context-engine-factory))
(defun get-context-engine-factory (id)
  "Get the factory function for the given engine ID, or nil."
  (declare (type string id))
  (gethash id *engine-registry*))

(declaim (ftype (function () list) list-context-engine-ids))
(defun list-context-engine-ids ()
  "Return a list of all registered context engine IDs."
  (let ((ids '()))
    (maphash (lambda (k v) (declare (ignore v)) (push k ids))
             *engine-registry*)
    (sort ids #'string<)))

(declaim (ftype (function (&optional (or hash-table null)) context-engine)
                resolve-context-engine))
(defun resolve-context-engine (&optional config)
  "Resolve the active context engine from config.
If CONFIG has a plugins.slots.contextEngine field, uses that engine ID.
Otherwise defaults to \"legacy\".
Signals an error if the requested engine is not registered."
  (declare (type (or hash-table null) config))
  (let* ((engine-id (or (and config
                              (let ((plugins (gethash "plugins" config)))
                                (when (hash-table-p plugins)
                                  (let ((slots (gethash "slots" plugins)))
                                    (when (hash-table-p slots)
                                      (gethash "contextEngine" slots))))))
                         "legacy"))
         (factory (get-context-engine-factory engine-id)))
    (declare (type string engine-id)
             (type (or function null) factory))
    (unless factory
      (error "Context engine ~S is not registered. Available engines: ~{~A~^, ~}"
             engine-id (list-context-engine-ids)))
    (funcall factory)))

;;; -----------------------------------------------------------------------
;;; Legacy context engine — pass-through implementation
;;; -----------------------------------------------------------------------

(defclass legacy-context-engine (context-engine)
  ()
  (:documentation "Legacy context engine: passes messages through unchanged.
This is the default engine that replicates the original OpenClaw behavior
where context assembly happens outside the engine."))

(defmethod engine-info ((engine legacy-context-engine))
  (make-context-engine-info :id "legacy"
                            :name "Legacy Context Engine"
                            :version "1.0.0"))

(defmethod engine-ingest ((engine legacy-context-engine)
                           session-id message
                           &key is-heartbeat)
  (declare (ignore engine session-id message is-heartbeat))
  (make-ingest-result :ingested-p nil))

(defmethod engine-assemble ((engine legacy-context-engine)
                              session-id messages
                              &key token-budget)
  (declare (ignore engine session-id token-budget))
  (make-assemble-result :messages messages
                        :estimated-tokens 0
                        :system-prompt-addition nil))

(defmethod engine-compact ((engine legacy-context-engine)
                             session-id session-file
                             &key token-budget compaction-target
                                  custom-instructions)
  (declare (ignore engine session-id session-file token-budget
                   compaction-target custom-instructions))
  (make-compact-result :ok-p t :compacted-p nil))

(defmethod engine-dispose ((engine legacy-context-engine))
  (declare (ignore engine))
  (values))

;;; -----------------------------------------------------------------------
;;; Registration helpers
;;; -----------------------------------------------------------------------

(defun register-legacy-context-engine ()
  "Register the legacy (pass-through) context engine."
  (register-context-engine "legacy"
                           (lambda () (make-instance 'legacy-context-engine))))

;;; -----------------------------------------------------------------------
;;; Initialization
;;; -----------------------------------------------------------------------

(defun ensure-context-engines-initialized ()
  "Ensure the context engine registry is initialized.
Idempotent — safe to call multiple times."
  (unless *engines-initialized-p*
    (register-legacy-context-engine)
    (setf *engines-initialized-p* t)))
