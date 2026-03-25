;;;; FiveAM test package for gateway domain
(defpackage :cl-claw.gateway.tests
  (:use :cl :fiveam)
  (:export #:gateway-suite))

(in-package :cl-claw.gateway.tests)

(def-suite gateway-suite
  :description "Tests for cl-claw gateway server, auth, sessions, and HTTP operations")
