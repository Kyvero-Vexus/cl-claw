;;;; package.lisp — E2E test suite package for crash recovery & multi-channel

(defpackage :cl-claw.e2e.tests
  (:use :cl :fiveam)
  (:export :run-e2e-tests))

(in-package :cl-claw.e2e.tests)

(def-suite :cl-claw.e2e.tests
  :description "End-to-end integration test suite")

(def-suite :e2e-crash-recovery :in :cl-claw.e2e.tests
  :description "Crash recovery & reconnection E2E tests")

(def-suite :e2e-provider-streaming-tool :in :cl-claw.e2e.tests
  :description "Provider call → streaming → tool dispatch → final response E2E tests")

(defun run-e2e-tests ()
  "Run all E2E tests and return results."
  (run! :cl-claw.e2e.tests))

;;; ─── Test Helpers ───────────────────────────────────────────────────────────

(defun make-test-config (&rest pairs)
  "Build a hash-table config from alternating key/value pairs."
  (let ((ht (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr
          do (setf (gethash k ht) v))
    ht))
