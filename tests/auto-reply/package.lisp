;;;; package.lisp — Test suite for auto-reply modules

(defpackage :cl-claw.auto-reply.tests
  (:use :cl :fiveam)
  (:export :run-auto-reply-tests))

(in-package :cl-claw.auto-reply.tests)

(def-suite :cl-claw.auto-reply.tests
  :description "Auto-reply module test suite")

(def-suite :auto-reply-chunk :in :cl-claw.auto-reply.tests)
(def-suite :auto-reply-commands :in :cl-claw.auto-reply.tests)
(def-suite :auto-reply-dispatch :in :cl-claw.auto-reply.tests)
(def-suite :auto-reply-heartbeat :in :cl-claw.auto-reply.tests)
(def-suite :auto-reply-inbound :in :cl-claw.auto-reply.tests)
(def-suite :auto-reply-model :in :cl-claw.auto-reply.tests)
(def-suite :auto-reply-reply :in :cl-claw.auto-reply.tests)
(def-suite :auto-reply-status :in :cl-claw.auto-reply.tests)
(def-suite :auto-reply-tokens :in :cl-claw.auto-reply.tests)

(defun run-auto-reply-tests ()
  (run! :cl-claw.auto-reply.tests))
