;;;; package.lisp - test suite package and FiveAM suite definition for channels

(defpackage :cl-claw.channels.tests
  (:use :cl :fiveam)
  (:export :run-channels-tests))

(in-package :cl-claw.channels.tests)

;; Main suite definition
(def-suite :cl-claw.channels.tests
  :description "Channels module test suite")

;; Sub-suites for organizing tests
(def-suite :channels-config :description "Channel configuration tests")
(def-suite :channels-session :description "Channel session tests")
(def-suite :channels-allow-from :description "Allow-from validation tests")
(def-suite :channels-allowlists :description "Allowlist tests")

(defun run-channels-tests ()
  "Run all channels tests and return results."
  (run! :cl-claw.channels.tests))

;;; -- test helpers ------------------------------------------------------------

(defun make-test-config (&rest pairs)
  "Build a hash-table config from alternating key/value pairs."
  (let ((ht (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr
      do (setf (gethash k ht) v))
    ht))

(defun make-nested-config (path value)
  "Build nested hash-tables from a dotted path string.
   E.g., (make-nested-config \"channels.enabled\" nil) builds {\"channels\": {\"enabled\": nil}}"
  (let ((keys (uiop:split-string path :separator ".")))
    (if (= (length keys) 1)
        (let ((ht (make-hash-table :test 'equal)))
          (setf (gethash (first keys) ht) value)
          ht)
        (let* ((rest-path (reduce (lambda (acc key) (concatenate acc "." key))
                                  (rest keys)))
               (inner-ht (make-nested-config rest-path value))
               (ht (make-hash-table :test 'equal)))
          (setf (gethash (first keys) ht) inner-ht)
          ht))))
