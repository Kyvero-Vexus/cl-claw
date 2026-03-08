;;;; retry.lisp - Retry utilities for cl-claw
;;;;
;;;; Implements retry logic with configurable attempts, delays, and callbacks.
;;;; Based on test specs from tests/cl-adapted/src/infra/retry.test.lisp

(defpackage :cl-claw.infra.retry
  (:use :cl)
  (:export :retry-async
           :retry-options
           :make-retry-options
           :retry-error
           :retry-error-cause
           :retry-error-message))
(in-package :cl-claw.infra.retry)

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

(defun clamp (value min max)
  "Clamp VALUE between MIN and MAX."
  (declare (type real value min max))
  (max min (min max value)))

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

(defun retry-async (fn &optional (options-spec 3) (delay-ms 10))
  "Retry FN up to ATTEMPTS times with DELAY-MS between retries.

FN should be a function of no arguments that returns a value or signals an error.

OPTIONS-SPEC can be:
- An integer (number of attempts)
- A retry-options struct

Returns the result of FN on success, or signals RETRY-ERROR on failure."
  (declare (type (or integer retry-options) options-spec))
  (let* ((options (etypecase options-spec
                    (integer (make-retry-options :attempts (max 1 options-spec)
                                                 :min-delay-ms delay-ms
                                                 :max-delay-ms delay-ms))
                    (retry-options options-spec)))
         (max-attempts (max 1 (retry-options-attempts options)))
         (last-error nil))
    (loop :for attempt :from 1 :to max-attempts
          :do (handler-case
                  (return-from retry-async (funcall fn))
                (error (e)
                  (setf last-error e)
                  ;; Check should-retry
                  (when (and (retry-options-should-retry options)
                             (not (funcall (retry-options-should-retry options) e)))
                    (error 'retry-error :message "shouldRetry returned false" :cause e))
                  ;; If this wasn't the last attempt, retry
                  (when (< attempt max-attempts)
                    (let ((delay (calculate-delay options attempt)))
                      ;; Call on-retry callback if provided
                      (when (retry-options-on-retry options)
                        (funcall (retry-options-on-retry options)
                                 (list :attempt attempt
                                       :max-attempts max-attempts
                                       :delay-ms delay)))
                      ;; Sleep for the delay
                      (sleep (/ delay 1000.0)))))))
    ;; All attempts exhausted
    (error 'retry-error
           :message (format nil "Retry exhausted after ~a attempts" max-attempts)
           :cause last-error)))
