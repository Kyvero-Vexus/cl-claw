;;;; FiveAM tests for cron domain helpers

(defpackage :cl-claw.cron.test
  (:use :cl :fiveam))

(in-package :cl-claw.cron.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite cron-suite
  :description "Tests for cron scheduler, jobs, and delivery helpers")

(in-suite cron-suite)

(defun %hash (&rest kv)
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kv by #'cddr do
      (setf (gethash k h) v))
    h))

(test normalize-cron-payload-defaults
  (let ((payload (cl-claw.cron:normalize-cron-payload nil)))
    (is (hash-table-p payload))
    (is (= 0 (hash-table-count payload)))))

(test compute-next-run-at-for-every-schedule
  (let* ((schedule (%hash "kind" "every" "seconds" 30))
         (next (cl-claw.cron:compute-next-run-at schedule :from-time 1000)))
    (is (= 1030 next))))

(test compute-next-run-at-for-cron-hourly
  (let* ((schedule (%hash "kind" "cron" "expr" "0 * * * *"))
         (from (encode-universal-time 0 15 10 8 3 2026 0))
         (next (cl-claw.cron:compute-next-run-at schedule :from-time from))
         (decoded (multiple-value-list (decode-universal-time next 0))))
    (is (= 0 (first decoded)))
    (is (= 0 (second decoded)))
    (is (= 11 (third decoded)))))

(test store-add-list-get-and-enable-toggle
  (let* ((store (cl-claw.cron:make-cron-store))
         (job (cl-claw.cron:make-cron-job :id "job-1"
                                          :schedule (%hash "kind" "every" "seconds" 60)
                                          :next-run-at 50)))
    (cl-claw.cron:add-cron-job store job)
    (is (= 1 (length (cl-claw.cron:list-cron-jobs store))))
    (is (string= "job-1" (cl-claw.cron:cron-job-id (cl-claw.cron:get-cron-job store "job-1"))))
    (is (cl-claw.cron:cron-job-enabled-p (cl-claw.cron:get-cron-job store "job-1")))
    (cl-claw.cron:set-job-enabled store "job-1" nil)
    (is-false (cl-claw.cron:cron-job-enabled-p (cl-claw.cron:get-cron-job store "job-1")))))

(test build-delivery-payload-includes-routing-fields
  (let* ((delivery (cl-claw.cron:make-cron-delivery :mode "announce"
                                                     :to "telegram:123"
                                                     :account-id "ops"
                                                     :thread-id "55"))
         (job (cl-claw.cron:make-cron-job :id "job-delivery"
                                          :schedule (%hash "kind" "every" "seconds" 60)
                                          :delivery delivery))
         (payload (cl-claw.cron:build-delivery-payload job "ok" "done")))
    (is (string= "job-delivery" (gethash "jobId" payload)))
    (is (string= "announce" (gethash "mode" payload)))
    (is (string= "telegram:123" (gethash "to" payload)))
    (is (string= "ops" (gethash "accountId" payload)))
    (is (string= "55" (gethash "threadId" payload)))))

(test run-due-jobs-runs-only-due-jobs-and-advances
  (let* ((store (cl-claw.cron:make-cron-store))
         (due (cl-claw.cron:make-cron-job :id "due"
                                          :schedule (%hash "kind" "every" "seconds" 20)
                                          :next-run-at 100))
         (future (cl-claw.cron:make-cron-job :id "future"
                                             :schedule (%hash "kind" "every" "seconds" 20)
                                             :next-run-at 9999)))
    (cl-claw.cron:add-cron-job store due)
    (cl-claw.cron:add-cron-job store future)
    (let ((results (cl-claw.cron:run-due-jobs store (lambda (job)
                                                       (declare (ignore job))
                                                       "ok")
                                              :now 120)))
      (is (= 1 (length results)))
      (is (= 1 (cl-claw.cron:cron-job-run-count due)))
      (is (= 0 (cl-claw.cron:cron-job-run-count future)))
      (is (> (cl-claw.cron:cron-job-next-run-at due) 120)))))
