;;;; FiveAM test package for CLI domain
(defpackage :cl-claw.cli.tests
  (:use :cl :fiveam)
  (:export #:cli-suite))

(in-package :cl-claw.cli.tests)

(def-suite cli-suite
  :description "Tests for cl-claw CLI commands, argument parsing, and CLI operations")
