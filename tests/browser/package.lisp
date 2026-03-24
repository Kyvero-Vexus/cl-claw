;;;; package.lisp - Browser domain test suite package and FiveAM suite definition
;;;;
;;;; Adapted from 56 upstream OpenClaw browser test specification files.
;;;; Covers: bridge server auth, browser utils, CDP, chrome, client,
;;;; config, control auth, extension relay, navigation guard, paths,
;;;; profiles, pw-session, pw-tools-core, screenshot, server, and session tab registry.

(defpackage :cl-claw.browser.tests
  (:use :cl :fiveam)
  (:export :run-browser-tests))

(in-package :cl-claw.browser.tests)

;;; - Top-level suite

(def-suite :cl-claw.browser.tests
  :description "Browser domain test suite (56 spec files)")

;;; - Sub-suites by spec category

(def-suite :browser-bridge-server-auth :in :cl-claw.browser.tests)
(def-suite :browser-utils :in :cl-claw.browser.tests)
(def-suite :browser-cdp :in :cl-claw.browser.tests)
(def-suite :browser-cdp-proxy-bypass :in :cl-claw.browser.tests)
(def-suite :browser-cdp-timeouts :in :cl-claw.browser.tests)
(def-suite :browser-chrome :in :cl-claw.browser.tests)
(def-suite :browser-chrome-default-browser :in :cl-claw.browser.tests)
(def-suite :browser-chrome-extension :in :cl-claw.browser.tests)
(def-suite :browser-client :in :cl-claw.browser.tests)
(def-suite :browser-client-fetch :in :cl-claw.browser.tests)
(def-suite :browser-config :in :cl-claw.browser.tests)
(def-suite :browser-control-auth :in :cl-claw.browser.tests)
(def-suite :browser-extension-relay :in :cl-claw.browser.tests)
(def-suite :browser-extension-relay-auth :in :cl-claw.browser.tests)
(def-suite :browser-fiveam :in :cl-claw.browser.tests)
(def-suite :browser-navigation-guard :in :cl-claw.browser.tests)
(def-suite :browser-paths :in :cl-claw.browser.tests)
(def-suite :browser-profiles :in :cl-claw.browser.tests)
(def-suite :browser-profiles-service :in :cl-claw.browser.tests)
(def-suite :browser-pw-ai :in :cl-claw.browser.tests)
(def-suite :browser-pw-role-snapshot :in :cl-claw.browser.tests)
(def-suite :browser-pw-session :in :cl-claw.browser.tests)
(def-suite :browser-pw-tools-core :in :cl-claw.browser.tests)
(def-suite :browser-screenshot :in :cl-claw.browser.tests)
(def-suite :browser-server :in :cl-claw.browser.tests)
(def-suite :browser-server-context :in :cl-claw.browser.tests)
(def-suite :browser-session-tab-registry :in :cl-claw.browser.tests)

(defun run-browser-tests ()
  "Run all browser tests and return results."
  (run! :cl-claw.browser.tests))

;;; - Test helpers

(defun hash (&rest pairs)
  "Build a hash-table from alternating key/value pairs."
  (let ((ht (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr
      do (setf (gethash k ht) v))
    ht))
