;;;; FiveAM tests for config sessions

(in-package :cl-claw.config.tests)

(declaim (optimize (safety 3) (debug 3)))

(in-suite config-suite)

;; Helper to create hash tables
(defun %hash (&rest kv)
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kv by #'cddr do
      (setf (gethash k h) v))
    h))

;; Tests for session configuration

(test session-key-normalization
  "Session keys are normalized correctly"
  ;; TODO: Implement when session key functions are available
  (skip "session key normalization functions not yet available"))

(test session-cache-fields
  "Session cache fields are handled correctly"
  ;; TODO: Implement when session cache functions are available
  (skip "session cache functions not yet available"))

(test session-artifacts-persistence
  "Session artifacts persist correctly"
  ;; TODO: Implement when session artifact functions are available
  (skip "session artifact functions not yet available"))

(test session-disk-budget-enforcement
  "Session disk budget is enforced"
  ;; TODO: Implement when disk budget functions are available
  (skip "disk budget functions not yet available"))

(test session-delivery-info
  "Session delivery info is tracked"
  ;; TODO: Implement when delivery info functions are available
  (skip "delivery info functions not yet available"))
