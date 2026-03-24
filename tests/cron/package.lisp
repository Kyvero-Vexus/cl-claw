;;;; package.lisp — Test suite for cron modules

(defpackage :cl-claw.cron.tests
  (:use :cl :fiveam)
  (:export :run-cron-tests))

(in-package :cl-claw.cron.tests)

(def-suite :cl-claw.cron.tests
  :description "Cron module test suite")

(def-suite :cron-protocol :in :cl-claw.cron.tests)
(def-suite :cron-delivery :in :cl-claw.cron.tests)
(def-suite :cron-heartbeat :in :cl-claw.cron.tests)
(def-suite :cron-service :in :cl-claw.cron.tests)
(def-suite :cron-session-reaper :in :cl-claw.cron.tests)
(def-suite :cron-store :in :cl-claw.cron.tests)
(def-suite :cron-isolated-agent :in :cl-claw.cron.tests)

(defun run-cron-tests ()
  (run! :cl-claw.cron.tests))
