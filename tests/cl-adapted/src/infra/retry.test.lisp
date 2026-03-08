(defpackage :cl-claw.infra.retry.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.retry.test)

(def-suite retry-suite)
(in-suite retry-suite)

(test returns-on-first-success
  "Returns on first success"
  (let ((call-count 0))
    (let ((result (cl-claw.infra.retry:retry-async
                   (lambda ()
                     (incf call-count)
                     "ok")
                   3 10)))
      (is (equal result "ok"))
      (is (= call-count 1)))))

(test retries-then-succeeds
  "Retries then succeeds"
  (let ((call-count 0))
    (let ((result (cl-claw.infra.retry:retry-async
                   (lambda ()
                     (incf call-count)
                     (if (= call-count 1)
                         (error "fail1")
                         "ok"))
                   (cl-claw.infra.retry:make-retry-options
                    :attempts 3
                    :min-delay-ms 0
                    :max-delay-ms 0))))
      (is (equal result "ok"))
      (is (= call-count 2)))))

(test propagates-after-exhausting-retries
  "Propagates after exhausting retries"
  (let ((call-count 0))
    (handler-case
        (cl-claw.infra.retry:retry-async
         (lambda ()
           (incf call-count)
           (error "boom"))
         (cl-claw.infra.retry:make-retry-options
          :attempts 2
          :min-delay-ms 0
          :max-delay-ms 0))
      (cl-claw.infra.retry:retry-error (e)
        (is (= call-count 2))
        (is (not (null (cl-claw.infra.retry:retry-error-cause e))))))))

(test stops-when-should-retry-returns-false
  "Stops when shouldRetry returns false"
  (let ((call-count 0))
    (handler-case
        (cl-claw.infra.retry:retry-async
         (lambda ()
           (incf call-count)
           (error "boom"))
         (cl-claw.infra.retry:make-retry-options
          :attempts 3
          :min-delay-ms 0
          :max-delay-ms 0
          :should-retry (lambda (e) (declare (ignore e)) nil)))
      (cl-claw.infra.retry:retry-error (e)
        (is (= call-count 1))
        (is (not (null (cl-claw.infra.retry:retry-error-cause e))))))))

(test calls-on-retry-before-retrying
  "Calls onRetry before retrying"
  (let ((call-count 0)
        (on-retry-called nil)
        (on-retry-info nil))
    (let ((result (cl-claw.infra.retry:retry-async
                   (lambda ()
                     (incf call-count)
                     (if (= call-count 1)
                         (error "boom")
                         "ok"))
                   (cl-claw.infra.retry:make-retry-options
                    :attempts 2
                    :min-delay-ms 0
                    :max-delay-ms 0
                    :on-retry (lambda (info)
                                (setf on-retry-called t)
                                (setf on-retry-info info))))))
      (is (equal result "ok"))
      (is-true on-retry-called)
      (is (= (getf on-retry-info :attempt) 1))
      (is (= (getf on-retry-info :max-attempts) 2)))))

(test clamps-attempts-to-at-least-1
  "Clamps attempts to at least 1"
  (let ((call-count 0))
    (handler-case
        (cl-claw.infra.retry:retry-async
         (lambda ()
           (incf call-count)
           (error "boom"))
         (cl-claw.infra.retry:make-retry-options
          :attempts 0
          :min-delay-ms 0
          :max-delay-ms 0))
      (cl-claw.infra.retry:retry-error (e)
        (declare (ignore e))
        (is (= call-count 1))))))

(test uses-retry-after-ms-when-provided
  "Uses retryAfterMs when provided"
  (let ((delays '()))
    (let ((result (cl-claw.infra.retry:retry-async
                   (lambda ()
                     (when (= (length delays) 0)
                       (error "boom"))
                     "ok")
                   (cl-claw.infra.retry:make-retry-options
                    :attempts 2
                    :min-delay-ms 0
                    :max-delay-ms 1000
                    :retry-after-ms (lambda () 500)
                    :on-retry (lambda (info)
                                (push (getf info :delay-ms) delays))))))
      (is (equal result "ok"))
      (is (= (first delays) 500)))))

(test clamps-retry-after-ms-to-max-delay-ms
  "Clamps retryAfterMs to maxDelayMs"
  (let ((delays '()))
    (let ((result (cl-claw.infra.retry:retry-async
                   (lambda ()
                     (when (= (length delays) 0)
                       (error "boom"))
                     "ok")
                   (cl-claw.infra.retry:make-retry-options
                    :attempts 2
                    :min-delay-ms 0
                    :max-delay-ms 100
                    :retry-after-ms (lambda () 500)
                    :on-retry (lambda (info)
                                (push (getf info :delay-ms) delays))))))
      (is (equal result "ok"))
      (is (= (first delays) 100)))))

(test clamps-retry-after-ms-to-min-delay-ms
  "Clamps retryAfterMs to minDelayMs"
  (let ((delays '()))
    (let ((result (cl-claw.infra.retry:retry-async
                   (lambda ()
                     (when (= (length delays) 0)
                       (error "boom"))
                     "ok")
                   (cl-claw.infra.retry:make-retry-options
                    :attempts 2
                    :min-delay-ms 250
                    :max-delay-ms 1000
                    :retry-after-ms (lambda () 50)
                    :on-retry (lambda (info)
                                (push (getf info :delay-ms) delays))))))
      (is (equal result "ok"))
      (is (= (first delays) 250)))))
