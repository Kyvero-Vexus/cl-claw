;;;; FiveAM test package for config domain
(defpackage :cl-claw.config.tests
  (:use :cl :fiveam)
  (:export #:config-suite))

(in-package :cl-claw.config.tests)

(def-suite config-suite
  :description "Tests for cl-claw config domain (env substitution, merge-patch, schema, sessions, etc.)")
