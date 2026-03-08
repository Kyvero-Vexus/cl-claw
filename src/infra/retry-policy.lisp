;;;; retry-policy.lisp - Telegram and provider retry policy for cl-claw
;;;;
;;;; Provides retry runners with configurable retry predicates,
;;;; including strictShouldRetry mode for Telegram and other providers.

(defpackage :cl-claw.infra.retry-policy
  (:use :cl)
  (:export :make-retry-runner
           :create-telegram-retry-runner
           :run-with-retry
           :make-retry-runner-options
           :retry-runner-options-attempts
           :retry-runner-options-min-delay-ms
           :retry-runner-options-max-delay-ms
           :retry-runner-options-jitter
           :retry-runner-options-should-retry
           :retry-runner-options-strict-should-retry
           :*transient-error-pattern*))
(in-package :cl-claw.infra.retry-policy)

(defparameter *transient-error-pattern*
  nil
  "Regex pattern for detecting transient network errors that should be retried.
Initialized lazily to avoid compile-time dependency on cl-ppcre.")

(defun ensure-transient-pattern ()
  "Lazily initialize the transient error pattern."
  (unless *transient-error-pattern*
    (setf *transient-error-pattern*
          (cl-ppcre:create-scanner
           "(reset|refused|timeout|unavailable|econnreset|econnrefused|etimedout)"
           :case-insensitive-mode t)))
  *transient-error-pattern*)

(defstruct retry-runner-options
  "Options for a retry runner."
  (attempts 3 :type (integer 1))
  (min-delay-ms 0 :type (integer 0))
  (max-delay-ms 1000 :type (integer 0))
  (jitter 0 :type real)
  (should-retry nil :type (or null function))
  (strict-should-retry nil :type boolean))

(defun transient-error-p (condition)
  "Return T if CONDITION looks like a transient network error by regex."
  (let ((msg (format nil "~a" condition)))
    (not (null (cl-ppcre:scan (ensure-transient-pattern) msg)))))

(defun make-retry-runner (&key (options nil))
  "Create a retry runner function from OPTIONS (a retry-runner-options struct).

The returned function takes a thunk FN and runs it with retry logic:
- If FN succeeds, returns its value
- If FN fails, checks should-retry (if set) and transient-error-p
- With strict-should-retry=T, only retries when should-retry returns T
- Without strict-should-retry, also retries on transient errors (regex fallback)"
  (declare (type (or null retry-runner-options) options))
  (let* ((opts (or options (make-retry-runner-options)))
         (max-attempts (retry-runner-options-attempts opts))
         (min-delay (retry-runner-options-min-delay-ms opts))
         (max-delay (retry-runner-options-max-delay-ms opts))
         (should-retry-fn (retry-runner-options-should-retry opts))
         (strict (retry-runner-options-strict-should-retry opts)))
    (lambda (fn &optional label)
      (declare (ignore label))
      (block runner-block
        (let ((last-error nil))
          (loop for attempt from 1 to max-attempts
                do (handler-case
                       (return-from runner-block (funcall fn))
                     (error (e)
                       (setf last-error e)
                       (let* ((predicate-allows
                                (and should-retry-fn (funcall should-retry-fn e)))
                              (regex-allows (transient-error-p e))
                              (should-retry-p
                                (cond
                                  (strict predicate-allows)
                                  (should-retry-fn (or predicate-allows regex-allows))
                                  (t t))))
                         (when (or (not should-retry-p) (= attempt max-attempts))
                           (error e))
                         (let ((delay (min max-delay (max min-delay 0))))
                           (when (> delay 0)
                             (sleep (/ delay 1000.0))))))))
          (when last-error (error last-error)))))))

(defun create-telegram-retry-runner (&key retry should-retry (strict-should-retry nil))
  "Create a Telegram-specific retry runner.

RETRY should be a plist with :attempts, :min-delay-ms, :max-delay-ms, :jitter.
SHOULD-RETRY is an optional predicate function.
STRICT-SHOULD-RETRY, when T, makes the predicate authoritative (suppresses regex fallback)."
  (let ((opts (make-retry-runner-options
               :attempts (or (getf retry :attempts) 3)
               :min-delay-ms (or (getf retry :min-delay-ms) 0)
               :max-delay-ms (or (getf retry :max-delay-ms) 1000)
               :jitter (or (getf retry :jitter) 0)
               :should-retry should-retry
               :strict-should-retry strict-should-retry)))
    (make-retry-runner :options opts)))

(defun run-with-retry (runner fn &optional label)
  "Run FN using RUNNER (created by make-retry-runner or create-telegram-retry-runner)."
  (funcall runner fn label))
