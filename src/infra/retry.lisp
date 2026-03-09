;;;; retry.lisp - Retry utilities for cl-claw
;;;;
;;;; Idiomatic CL retry library: use WITH-RETRY for new code.
;;;; RETRY-ASYNC is retained as an alias for code ported from the TypeScript
;;;; original — the name was a misnomer there too (execution is synchronous).

(defpackage :cl-claw.infra.retry
  (:use :cl)
  (:export :retry-async          ; compat alias for WITH-RETRY
           :with-retry           ; idiomatic CL entry point
           :retry-options
           :make-retry-options
           :retry-error
           :retry-error-cause
           :retry-error-message))
(in-package :cl-claw.infra.retry)

(declaim (optimize (safety 3) (debug 3)))

(define-condition retry-error (error)
  ((message :initarg :message :reader retry-error-message)
   (cause :initarg :cause :reader retry-error-cause))
  (:documentation "Error raised when retry attempts are exhausted"))

(defstruct retry-options
  "Options for retry behavior."
  (attempts 1 :type (integer 0))
  (min-delay-ms 0 :type (integer 0))
  (max-delay-ms 1000 :type (integer 0))
  (jitter 0 :type (real 0 1))
  (retry-after-ms nil :type (or null function))
  (on-retry nil :type (or null function))
  (should-retry nil :type (or null function)))

(declaim (ftype (function (real real real) real) clamp))
(defun clamp (value min max)
  "Clamp VALUE between MIN and MAX."
  (declare (type real value min max))
  (max min (min max value)))

(declaim (ftype (function (retry-options (integer 1)) real) calculate-delay))
(defun calculate-delay (options attempt)
  "Calculate the delay in milliseconds for the given attempt."
  (declare (type retry-options options)
           (type (integer 1) attempt))
  (let* ((base-delay (if (retry-options-retry-after-ms options)
                         (funcall (retry-options-retry-after-ms options))
                         (retry-options-min-delay-ms options)))
         (jitter-factor (retry-options-jitter options))
         (jitter-amount (if (> jitter-factor 0)
                           (* base-delay jitter-factor (random 1.0))
                           0))
         (raw-delay (+ base-delay jitter-amount)))
    (clamp raw-delay
           (retry-options-min-delay-ms options)
           (retry-options-max-delay-ms options))))

(declaim (ftype (function (function &optional (or integer retry-options) real) t) with-retry))
(defun with-retry (fn &optional (options-spec 3) (delay-ms 10))
  "Retry FN up to OPTIONS-SPEC attempts, with DELAY-MS ms between retries.

FN is a zero-argument function that returns a value or signals an error.

OPTIONS-SPEC may be:
  - A positive integer: number of attempts (delay fixed at DELAY-MS)
  - A RETRY-OPTIONS struct: full control over attempts, delays, jitter,
    and the SHOULD-RETRY / ON-RETRY callbacks

Returns the result of FN on success.  Signals RETRY-ERROR when all attempts
are exhausted."
  (declare (type function fn)
           (type (or integer retry-options) options-spec)
           (type real delay-ms))
  (let* ((options (etypecase options-spec
                    (integer (make-retry-options :attempts    (max 1 options-spec)
                                                 :min-delay-ms delay-ms
                                                 :max-delay-ms delay-ms))
                    (retry-options options-spec)))
         (max-attempts (max 1 (retry-options-attempts options)))
         (last-error   nil))
    (loop :for attempt :from 1 :to max-attempts
          :do (handler-case
                  (return-from with-retry (funcall fn))
                (error (e)
                  (setf last-error e)
                  ;; Honour the should-retry predicate when provided.
                  (when (and (retry-options-should-retry options)
                             (not (funcall (retry-options-should-retry options) e)))
                    (error 'retry-error
                           :message "should-retry returned false"
                           :cause e))
                  ;; Sleep before the next attempt (not after the final failure).
                  (when (< attempt max-attempts)
                    (let ((delay (calculate-delay options attempt)))
                      (when (retry-options-on-retry options)
                        (funcall (retry-options-on-retry options)
                                 (list :attempt      attempt
                                       :max-attempts max-attempts
                                       :delay-ms     delay)))
                      (sleep (/ delay 1000.0)))))))
    (error 'retry-error
           :message (format nil "Retry exhausted after ~a attempts" max-attempts)
           :cause last-error)))

;;; RETRY-ASYNC is kept as an alias — the name came from the TypeScript source
;;; where async/await phrasing was natural; in CL it is simply WITH-RETRY.
(declaim (ftype (function (function &optional (or integer retry-options) real) t) retry-async))
(defun retry-async (fn &optional (options-spec 3) (delay-ms 10))
  "Backward-compatible alias for WITH-RETRY.  Prefer WITH-RETRY in new code."
  (declare (type function fn)
           (type (or integer retry-options) options-spec)
           (type real delay-ms))
  (with-retry fn options-spec delay-ms))
