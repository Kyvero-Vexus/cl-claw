;;;; supervisor.lisp — Process supervisor: registry, run management, PTY/child adapters
;;;;
;;;; Provides a run registry, process supervision with timeouts, and
;;;; utilities for managing running/exited process records.

(defpackage :cl-claw.process.supervisor
  (:use :cl)
  (:export
   ;; Registry
   :create-run-registry
   :run-registry
   :registry-add
   :registry-get
   :registry-finalize
   :registry-list-by-scope

   ;; Record types
   :run-record
   :make-run-record
   :run-record-run-id
   :run-record-session-id
   :run-record-backend-id
   :run-record-scope-key
   :run-record-state
   :run-record-started-at-ms
   :run-record-last-output-at-ms
   :run-record-created-at-ms
   :run-record-updated-at-ms
   :run-record-termination-reason
   :run-record-exit-code
   :run-record-exit-signal

   ;; Finalize result
   :finalize-result
   :finalize-result-first-finalize
   :finalize-result-record))

(in-package :cl-claw.process.supervisor)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Run record ──────────────────────────────────────────────────────────────

(defstruct (run-record (:copier copy-run-record))
  "A record of a single supervised process run."
  (run-id              ""        :type string)
  (session-id          ""        :type string)
  (backend-id          ""        :type string)
  (scope-key           nil       :type (or string null))
  (state               :running  :type keyword)  ; :running or :exited
  (started-at-ms       0         :type fixnum)
  (last-output-at-ms   0         :type fixnum)
  (created-at-ms       0         :type fixnum)
  (updated-at-ms       0         :type fixnum)
  (termination-reason  nil       :type (or string null))
  (exit-code           nil       :type (or integer null))
  (exit-signal         nil       :type (or string null)))

;;; ─── Finalize result ─────────────────────────────────────────────────────────

(defstruct finalize-result
  "Result of finalizing a run record."
  (first-finalize t   :type boolean)
  (record         nil :type (or run-record null)))

;;; ─── Registry ────────────────────────────────────────────────────────────────

(defstruct (run-registry (:constructor %make-run-registry))
  "Registry of supervised process runs."
  (lock             (bt:make-lock "registry-lock") :type t)
  (records          (make-hash-table :test 'equal) :type hash-table)
  ;; Ordered list of exited run IDs (oldest first)
  (exited-order     '()  :type list)
  (max-exited-records 100 :type fixnum))

(declaim (ftype (function (&key (:max-exited-records (or fixnum null))) run-registry)
                create-run-registry))
(defun create-run-registry (&key max-exited-records)
  "Create a new run registry. MAX-EXITED-RECORDS caps how many exited records are kept."
  (declare (type (or fixnum null) max-exited-records))
  (%make-run-registry
   :max-exited-records (or max-exited-records 100)))

(declaim (ftype (function (run-registry run-record) t) registry-add))
(defun registry-add (registry record)
  "Add a RECORD to REGISTRY."
  (declare (type run-registry registry)
           (type run-record record))
  (bt:with-lock-held ((run-registry-lock registry))
    (setf (gethash (run-record-run-id record)
                   (run-registry-records registry))
          record)))

(declaim (ftype (function (run-registry string) (or run-record null)) registry-get))
(defun registry-get (registry run-id)
  "Return the run record for RUN-ID, or NIL if not found."
  (declare (type run-registry registry)
           (type string run-id))
  (bt:with-lock-held ((run-registry-lock registry))
    (gethash run-id (run-registry-records registry))))

(declaim (ftype (function (run-registry string &key (:reason string)
                                                    (:exit-code (or integer null))
                                                    (:exit-signal (or string null)))
                          (or finalize-result null))
                registry-finalize))
(defun registry-finalize (registry run-id &key reason exit-code exit-signal)
  "Finalize the run record for RUN-ID with the given termination metadata.
Idempotent: subsequent calls preserve the first terminal metadata.
Returns a FINALIZE-RESULT or NIL if RUN-ID is not found."
  (declare (type run-registry registry)
           (type string run-id)
           (type (or string null) reason exit-signal)
           (type (or integer null) exit-code))
  (bt:with-lock-held ((run-registry-lock registry))
    (let ((record (gethash run-id (run-registry-records registry))))
      (unless record (return-from registry-finalize nil))
      (let ((first-finalize (eq (run-record-state record) :running)))
        (declare (type boolean first-finalize))
        ;; Only update metadata on first finalize
        (when first-finalize
          (setf (run-record-state record) :exited)
          (setf (run-record-termination-reason record) reason)
          (setf (run-record-exit-code record) exit-code)
          (setf (run-record-exit-signal record) exit-signal)
          ;; Track exited order and prune if over cap
          (setf (run-registry-exited-order registry)
                (append (run-registry-exited-order registry) (list run-id)))
          (loop while (> (length (run-registry-exited-order registry))
                         (run-registry-max-exited-records registry))
                do (let ((oldest (pop (run-registry-exited-order registry))))
                     (declare (type string oldest))
                     (remhash oldest (run-registry-records registry)))))
        (make-finalize-result
         :first-finalize first-finalize
         :record record)))))

(declaim (ftype (function (run-registry string) list) registry-list-by-scope))
(defun registry-list-by-scope (registry scope-key)
  "Return a list of detached copies of run records matching SCOPE-KEY.
Returns empty list for blank SCOPE-KEY."
  (declare (type run-registry registry)
           (type string scope-key))
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline) scope-key)))
    (declare (type string trimmed))
    (when (string= trimmed "")
      (return-from registry-list-by-scope '()))
    (let ((result '()))
      (declare (type list result))
      (bt:with-lock-held ((run-registry-lock registry))
        (maphash
         (lambda (id record)
           (declare (ignore id))
           (when (and (run-record-scope-key record)
                      (string= (run-record-scope-key record) scope-key))
             ;; Return a detached copy
             (push (copy-run-record record) result)))
         (run-registry-records registry)))
      result)))
