;;;; package.lisp — Test suite package and FiveAM suite definition for ACP

(defpackage :cl-claw.acp.tests
  (:use :cl :fiveam)
  (:export :run-acp-tests))

(in-package :cl-claw.acp.tests)

(def-suite :cl-claw.acp.tests
  :description "ACP module test suite")

(def-suite :acp-policy :in :cl-claw.acp.tests)
(def-suite :acp-session :in :cl-claw.acp.tests)
(def-suite :acp-runtime-cache :in :cl-claw.acp.tests)
(def-suite :acp-registry :in :cl-claw.acp.tests)
(def-suite :acp-persistent-bindings :in :cl-claw.acp.tests)
(def-suite :acp-client :in :cl-claw.acp.tests)
(def-suite :acp-translator :in :cl-claw.acp.tests)
(def-suite :acp-server :in :cl-claw.acp.tests)
(def-suite :acp-core :in :cl-claw.acp.tests)

(defun run-acp-tests ()
  "Run all ACP tests and return results."
  (run! :cl-claw.acp.tests))

;;; ─── Test Helpers ───────────────────────────────────────────────────────────

(defun make-test-config (&rest pairs)
  "Build a hash-table config from alternating key/value pairs."
  (let ((ht (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr
          do (setf (gethash k ht) v))
    ht))

(defun make-nested-config (path value)
  "Build nested hash-tables from a dotted path string.
   E.g., (make-nested-config \"acp.enabled\" nil) builds {\"acp\": {\"enabled\": nil}}"
  (let ((keys (uiop:split-string path :separator ".")))
    (if (= (length keys) 1)
        (make-test-config (first keys) value)
        (make-test-config (first keys)
                          (make-nested-config
                           (format nil "~{~A~^.~}" (rest keys))
                           value)))))
