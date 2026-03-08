;;;; fiveam-retry-policy.test.lisp - FiveAM tests for retry-policy module

(defpackage :cl-claw.infra.retry-policy.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.retry-policy.test)

(def-suite retry-policy-suite
  :description "Tests for the retry-policy module")
(in-suite retry-policy-suite)

(test create-telegram-retry-runner-basic
  "Creates a telegram retry runner without error"
  (let ((runner (cl-claw.infra.retry-policy:create-telegram-retry-runner
                 :retry (list :attempts 2 :min-delay-ms 0 :max-delay-ms 0 :jitter 0))))
    (is (not (null runner)))
    (is (functionp runner))))

(test without-strict-should-retry-econnreset-is-retried
  "Without strictShouldRetry: ECONNRESET is retried via regex fallback even when predicate returns false"
  (let* ((call-count 0)
         (runner (cl-claw.infra.retry-policy:create-telegram-retry-runner
                  :retry (list :attempts 2 :min-delay-ms 0 :max-delay-ms 0 :jitter 0)
                  :should-retry (lambda (e) (declare (ignore e)) nil)
                  ;; strictShouldRetry not set — regex fallback still applies
                  :strict-should-retry nil)))
    ;; ECONNRESET should match regex even though predicate says false
    (handler-case
        (funcall runner
                 (lambda ()
                   (incf call-count)
                   (error "read ECONNRESET"))
                 "test")
      (error () nil))
    ;; Should have been called 2 times (retried once)
    (is (= 2 call-count))))

(test with-strict-should-retry-econnreset-not-retried-when-predicate-false
  "With strictShouldRetry=true: ECONNRESET is NOT retried when predicate returns false"
  (let* ((call-count 0)
         (runner (cl-claw.infra.retry-policy:create-telegram-retry-runner
                  :retry (list :attempts 2 :min-delay-ms 0 :max-delay-ms 0 :jitter 0)
                  :should-retry (lambda (e) (declare (ignore e)) nil)
                  :strict-should-retry t)))
    ;; With strict mode, predicate returning false means no retry
    (handler-case
        (funcall runner
                 (lambda ()
                   (incf call-count)
                   (error "read ECONNRESET"))
                 "test")
      (error () nil))
    ;; Should only be called once (no retry)
    (is (= 1 call-count))))

(test with-strict-should-retry-econnrefused-retried-when-predicate-true
  "With strictShouldRetry=true: ECONNREFUSED is still retried when predicate returns true"
  (let* ((call-count 0)
         (runner (cl-claw.infra.retry-policy:create-telegram-retry-runner
                  :retry (list :attempts 2 :min-delay-ms 0 :max-delay-ms 0 :jitter 0)
                  :should-retry (lambda (e)
                                  (search "ECONNREFUSED" (format nil "~a" e)))
                  :strict-should-retry t)))
    (let ((result
            (handler-case
                (funcall runner
                         (lambda ()
                           (incf call-count)
                           (if (= call-count 1)
                               (error "ECONNREFUSED connection refused")
                               "ok"))
                         "test")
              (error () :error))))
      (is (equal "ok" result))
      (is (= 2 call-count)))))

(test retry-runner-succeeds-on-first-try
  "Runner returns immediately on success"
  (let* ((runner (cl-claw.infra.retry-policy:create-telegram-retry-runner
                  :retry (list :attempts 3 :min-delay-ms 0 :max-delay-ms 0 :jitter 0)))
         (result (funcall runner (lambda () "success") "test")))
    (is (equal "success" result))))

(test retry-runner-exhausts-attempts
  "Runner exhausts attempts and signals error"
  (let* ((call-count 0)
         (runner (cl-claw.infra.retry-policy:create-telegram-retry-runner
                  :retry (list :attempts 2 :min-delay-ms 0 :max-delay-ms 0 :jitter 0))))
    (handler-case
        (funcall runner
                 (lambda ()
                   (incf call-count)
                   (error "permanent error"))
                 "test")
      (error () nil))
    (is (= 2 call-count))))
