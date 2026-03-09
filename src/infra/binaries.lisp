;;;; binaries.lisp - Binary availability checks for cl-claw
;;;;
;;;; Provides ENSURE-BINARY which checks that a required system binary is on
;;;; PATH.  The primary CL-idiomatic interface signals MISSING-BINARY-ERROR
;;;; with an EXIT-WITH-ERROR restart; a legacy :runtime callback plist is
;;;; supported for backward compatibility.

(defpackage :cl-claw.infra.binaries
  (:use :cl)
  (:export :ensure-binary
           :missing-binary-error
           :missing-binary-error-name
           :exit-with-error))

(in-package :cl-claw.infra.binaries)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Condition ───────────────────────────────────────────────────────────────

(define-condition missing-binary-error (error)
  ((binary-name :initarg :binary-name
                :reader  missing-binary-error-name
                :type    string))
  (:report (lambda (c s)
             (format s "Missing required binary: ~a. Please install it."
                     (missing-binary-error-name c))))
  (:documentation
   "Signalled when a required system binary cannot be found on PATH.
Establish the EXIT-WITH-ERROR restart (or handle the condition) to
control program flow when this is signalled."))

;;; ─── Implementation ──────────────────────────────────────────────────────────

(declaim (ftype (function (string &key (:exec-fn function) (:runtime list)) (or t null)) ensure-binary))
(defun ensure-binary (binary-name
                      &key (exec-fn #'uiop:run-program)
                           (runtime nil))
  "Verify BINARY-NAME is reachable via PATH.

Returns T when the binary is found.

When missing, the behaviour depends on whether a :runtime callback plist is
supplied:

  * Without :runtime (idiomatic CL): signals MISSING-BINARY-ERROR.  The
    restart EXIT-WITH-ERROR is established and exits with status 1 when
    invoked.

  * With :runtime (legacy/compat shim): calls (:error msg) then (:exit 1)
    from the plist and returns NIL, matching the original callback-object
    contract expected by older callers and tests."
  (declare (type string binary-name)
           (type function exec-fn)
           (type list runtime))
  (handler-case
      (progn
        (funcall exec-fn (format nil "which ~a" binary-name) :output :string)
        t)
    (error ()
      (let ((msg (format nil "Missing required binary: ~a. Please install it."
                         binary-name)))
        (cond
          ;; ── Legacy callback path (backward compat) ───────────────────────
          (runtime
           (let ((error-fn (getf runtime :error))
                 (exit-fn  (getf runtime :exit)))
             (when error-fn (funcall error-fn msg))
             (when exit-fn  (funcall exit-fn 1)))
           nil)
          ;; ── CL-idiomatic path ────────────────────────────────────────────
          (t
           (restart-case
               (error 'missing-binary-error :binary-name binary-name)
             (exit-with-error ()
               :report "Exit the process with status 1"
               (uiop:quit 1)))))))))
