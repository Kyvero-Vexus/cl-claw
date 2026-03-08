;;;; channel-activity.test.lisp - Tests for channel-activity module

(defpackage :cl-claw.infra.channel-activity.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.channel-activity.test)

(def-suite channel-activity-suite
  :description "Tests for the channel-activity module")
(in-suite channel-activity-suite)

(test creates-tracker
  "Creates a fresh activity tracker"
  (let ((tracker (cl-claw.infra.channel-activity:make-channel-activity-tracker)))
    (is (not (null tracker)))))

(test records-activity
  "Records activity and returns timestamp"
  (let ((tracker (cl-claw.infra.channel-activity:make-channel-activity-tracker))
        (fixed-ts 1000000))
    (let ((result (cl-claw.infra.channel-activity:record-activity tracker "ch1" fixed-ts)))
      (is (= result fixed-ts)))))

(test get-last-activity-returns-nil-for-unknown-channel
  "Returns NIL for a channel that has no recorded activity"
  (let ((tracker (cl-claw.infra.channel-activity:make-channel-activity-tracker)))
    (is (null (cl-claw.infra.channel-activity:get-last-activity tracker "unknown-ch")))))

(test get-last-activity-returns-recorded-timestamp
  "Returns the most recently recorded timestamp"
  (let ((tracker (cl-claw.infra.channel-activity:make-channel-activity-tracker)))
    (cl-claw.infra.channel-activity:record-activity tracker "ch1" 5000)
    (is (= 5000 (cl-claw.infra.channel-activity:get-last-activity tracker "ch1")))))

(test overwriting-activity-updates-timestamp
  "Subsequent activity records overwrite the previous one"
  (let ((tracker (cl-claw.infra.channel-activity:make-channel-activity-tracker)))
    (cl-claw.infra.channel-activity:record-activity tracker "ch1" 1000)
    (cl-claw.infra.channel-activity:record-activity tracker "ch1" 9999)
    (is (= 9999 (cl-claw.infra.channel-activity:get-last-activity tracker "ch1")))))

(test get-idle-duration-ms-returns-nil-when-no-activity
  "Returns NIL when no activity has been recorded"
  (let ((tracker (cl-claw.infra.channel-activity:make-channel-activity-tracker)))
    (is (null (cl-claw.infra.channel-activity:get-idle-duration-ms tracker "ch1" 10000)))))

(test get-idle-duration-ms-computes-difference
  "Returns the difference between now and last activity"
  (let ((tracker (cl-claw.infra.channel-activity:make-channel-activity-tracker)))
    (cl-claw.infra.channel-activity:record-activity tracker "ch1" 1000)
    (let ((idle (cl-claw.infra.channel-activity:get-idle-duration-ms tracker "ch1" 4000)))
      (is (= idle 3000)))))

(test channel-active-p-within-threshold
  "Channel is active when idle duration is within threshold"
  (let ((tracker (cl-claw.infra.channel-activity:make-channel-activity-tracker)))
    (cl-claw.infra.channel-activity:record-activity tracker "ch1" 9500)
    ;; Idle for 500ms, threshold is 1000ms → active
    (is-true (cl-claw.infra.channel-activity:channel-active-p tracker "ch1" 1000 10000))))

(test channel-active-p-exceeds-threshold
  "Channel is not active when idle exceeds threshold"
  (let ((tracker (cl-claw.infra.channel-activity:make-channel-activity-tracker)))
    (cl-claw.infra.channel-activity:record-activity tracker "ch1" 1000)
    ;; Idle for 5000ms, threshold is 1000ms → not active
    (is-false (cl-claw.infra.channel-activity:channel-active-p tracker "ch1" 1000 6000))))

(test channel-active-p-no-activity-returns-nil
  "Channel with no recorded activity is not active"
  (let ((tracker (cl-claw.infra.channel-activity:make-channel-activity-tracker)))
    (is-false (cl-claw.infra.channel-activity:channel-active-p tracker "ch1" 1000 10000))))

(test clear-activity-removes-record
  "Clearing activity removes the channel's record"
  (let ((tracker (cl-claw.infra.channel-activity:make-channel-activity-tracker)))
    (cl-claw.infra.channel-activity:record-activity tracker "ch1" 5000)
    (cl-claw.infra.channel-activity:clear-activity tracker "ch1")
    (is (null (cl-claw.infra.channel-activity:get-last-activity tracker "ch1")))))

(test tracks-multiple-channels-independently
  "Tracks multiple channels without interference"
  (let ((tracker (cl-claw.infra.channel-activity:make-channel-activity-tracker)))
    (cl-claw.infra.channel-activity:record-activity tracker "ch-a" 100)
    (cl-claw.infra.channel-activity:record-activity tracker "ch-b" 200)
    (is (= 100 (cl-claw.infra.channel-activity:get-last-activity tracker "ch-a")))
    (is (= 200 (cl-claw.infra.channel-activity:get-last-activity tracker "ch-b")))))
