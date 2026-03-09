;;;; registry.lisp — ACP runtime backend registration, health checks, error handling
;;;;
;;;; Manages the registry of ACP runtime backends (e.g., codex, claude-code),
;;;; provides health check dispatch, and formats error text for ACP conditions.

(defpackage :cl-claw.acp.registry
  (:use :cl :cl-claw.acp.types)
  (:export
   :runtime-registry
   :make-runtime-registry
   :backend-entry
   :backend-entry-id
   :backend-entry-healthy
   :backend-entry-error-count
   :registry-register-backend
   :registry-unregister-backend
   :registry-get-backend
   :registry-require-backend
   :registry-list-backends
   :registry-backend-healthy-p
   :registry-check-health
   :format-acp-error-text
   :make-acp-error-boundary))

(in-package :cl-claw.acp.registry)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Backend Entry ──────────────────────────────────────────────────────────

(defstruct (backend-entry (:conc-name backend-entry-))
  "A registered ACP runtime backend."
  (id "" :type string)
  (display-name "" :type string)
  (healthy t :type boolean)
  (last-health-check 0 :type fixnum)
  (error-count 0 :type fixnum)
  (metadata nil :type (or hash-table null)))

;;; ─── Registry ───────────────────────────────────────────────────────────────

(defstruct (runtime-registry (:conc-name runtime-registry-))
  "Registry of available ACP runtime backends."
  (backends (make-hash-table :test 'equal) :type hash-table)
  (default-backend nil :type (or string null)))

;;; ─── Registration ───────────────────────────────────────────────────────────

(declaim (ftype (function (runtime-registry string &key (:display-name string)
                                                        (:default boolean)
                                                        (:metadata (or hash-table null)))
                          backend-entry)
                registry-register-backend))
(defun registry-register-backend (registry backend-id
                                  &key (display-name "")
                                       (default nil)
                                       (metadata nil))
  "Register a backend. Returns the entry."
  (declare (type runtime-registry registry)
           (type string backend-id display-name)
           (type boolean default)
           (type (or hash-table null) metadata))
  (let ((entry (make-backend-entry
                :id backend-id
                :display-name (if (string= display-name "") backend-id display-name)
                :metadata metadata)))
    (setf (gethash backend-id (runtime-registry-backends registry)) entry)
    (when default
      (setf (runtime-registry-default-backend registry) backend-id))
    entry))

(declaim (ftype (function (runtime-registry string) boolean) registry-unregister-backend))
(defun registry-unregister-backend (registry backend-id)
  "Remove a backend from the registry."
  (declare (type runtime-registry registry) (type string backend-id))
  (let ((removed (remhash backend-id (runtime-registry-backends registry))))
    (when (and removed
               (string= (or (runtime-registry-default-backend registry) "")
                         backend-id))
      (setf (runtime-registry-default-backend registry) nil))
    (not (null removed))))

(declaim (ftype (function (runtime-registry &optional (or string null))
                          (or backend-entry null))
                registry-get-backend))
(defun registry-get-backend (registry &optional backend-id)
  "Get a backend by ID, or the default if NIL."
  (declare (type runtime-registry registry)
           (type (or string null) backend-id))
  (let ((id (or backend-id (runtime-registry-default-backend registry))))
    (when id
      (gethash id (runtime-registry-backends registry)))))

(declaim (ftype (function (runtime-registry &optional (or string null)) backend-entry)
                registry-require-backend))
(defun registry-require-backend (registry &optional backend-id)
  "Get a backend or signal an error if not found."
  (declare (type runtime-registry registry)
           (type (or string null) backend-id))
  (let ((entry (registry-get-backend registry backend-id)))
    (unless entry
      (error 'acp-runtime-error
             :backend (or backend-id "<default>")
             :text (format nil "No ACP runtime backend registered for '~A'"
                           (or backend-id "<default>"))))
    entry))

(declaim (ftype (function (runtime-registry) list) registry-list-backends))
(defun registry-list-backends (registry)
  "List all registered backend entries."
  (declare (type runtime-registry registry))
  (let ((result nil))
    (maphash (lambda (k v) (declare (ignore k)) (push v result))
             (runtime-registry-backends registry))
    result))

;;; ─── Health ─────────────────────────────────────────────────────────────────

(declaim (ftype (function (runtime-registry string) boolean) registry-backend-healthy-p))
(defun registry-backend-healthy-p (registry backend-id)
  "Check if a backend is currently marked healthy."
  (declare (type runtime-registry registry) (type string backend-id))
  (let ((entry (gethash backend-id (runtime-registry-backends registry))))
    (and entry (backend-entry-healthy entry))))

(declaim (ftype (function (runtime-registry string boolean &key (:now fixnum)) null)
                registry-check-health))
(defun registry-check-health (registry backend-id healthy &key (now 0))
  "Update health status for a backend."
  (declare (type runtime-registry registry)
           (type string backend-id)
           (type boolean healthy)
           (type fixnum now))
  (let ((entry (gethash backend-id (runtime-registry-backends registry))))
    (when entry
      (setf (backend-entry-healthy entry) healthy
            (backend-entry-last-health-check entry) now)
      (unless healthy
        (incf (backend-entry-error-count entry)))))
  nil)

;;; ─── Error Formatting ──────────────────────────────────────────────────────

(declaim (ftype (function (acp-error) string) format-acp-error-text))
(defun format-acp-error-text (condition)
  "Format an ACP error condition into a user-facing text string."
  (declare (type acp-error condition))
  (format nil "[~A] ~A" (acp-error-code condition) (acp-error-text condition)))

(declaim (ftype (function (function) (values t boolean)) make-acp-error-boundary))
(defun make-acp-error-boundary (thunk)
  "Execute THUNK catching ACP errors. Returns (values result nil) on success,
   or (values error-ht t) on ACP error."
  (declare (type function thunk))
  (handler-case
      (values (funcall thunk) nil)
    (acp-error (e)
      (let ((ht (make-hash-table :test 'equal)))
        (setf (gethash "code" ht) (acp-error-code e)
              (gethash "message" ht) (format-acp-error-text e))
        (values ht t)))))
