;;;; package.lisp — Test suite for agent modules

(defpackage :cl-claw.agents.tests
  (:use :cl :fiveam)
  (:export :run-agent-tests))

(in-package :cl-claw.agents.tests)

(def-suite :cl-claw.agents.tests
  :description "Agent module test suite")

(def-suite :agent-core :in :cl-claw.agents.tests)
(def-suite :agent-sandbox :in :cl-claw.agents.tests)
(def-suite :agent-auth :in :cl-claw.agents.tests)
(def-suite :agent-bash :in :cl-claw.agents.tests)
(def-suite :agent-spawn :in :cl-claw.agents.tests)
(def-suite :agent-patch :in :cl-claw.agents.tests)

(defun run-agent-tests ()
  (run! :cl-claw.agents.tests))

(defun make-test-config (&rest pairs)
  (let ((ht (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr
          do (setf (gethash k ht) v))
    ht))
