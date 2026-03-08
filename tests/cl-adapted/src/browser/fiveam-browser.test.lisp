;;;; FiveAM tests for browser domain helpers

(defpackage :cl-claw.browser.test
  (:use :cl :fiveam))

(in-package :cl-claw.browser.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite browser-suite
  :description "Tests for browser profile normalization, relay checks, and request assembly")

(in-suite browser-suite)

(test normalize-browser-profile-defaults-and-known-values
  (is (string= "openclaw" (cl-claw.browser:normalize-browser-profile nil)))
  (is (string= "openclaw" (cl-claw.browser:normalize-browser-profile "")))
  (is (string= "chrome" (cl-claw.browser:normalize-browser-profile "CHROME")))
  (is (string= "openclaw" (cl-claw.browser:normalize-browser-profile "unknown"))))

(test chrome-profile-requires-extension-attach
  (is-true (cl-claw.browser:profile-requires-extension-attach-p "chrome"))
  (is-false (cl-claw.browser:profile-requires-extension-attach-p "openclaw")))

(test ensure-relay-tab-attached-errors-when-missing
  (signals error
    (cl-claw.browser:ensure-relay-tab-attached "chrome" 0))
  (is-false (cl-claw.browser:ensure-relay-tab-attached "chrome" 1))
  (is-false (cl-claw.browser:ensure-relay-tab-attached "openclaw" 0)))

(test sanitize-cdp-endpoint-validates-scheme
  (is (string= "ws://127.0.0.1:9222/devtools/browser/abc"
               (cl-claw.browser:sanitize-cdp-endpoint "ws://127.0.0.1:9222/devtools/browser/abc")))
  (is (string= "wss://browser.example/ws"
               (cl-claw.browser:sanitize-cdp-endpoint "wss://browser.example/ws")))
  (signals error
    (cl-claw.browser:sanitize-cdp-endpoint "http://browser.example")))

(test choose-browser-target-fallbacks
  (is (eq :node (cl-claw.browser:choose-browser-target "node" t)))
  (is (eq :host (cl-claw.browser:choose-browser-target "node" nil)))
  (is (eq :sandbox (cl-claw.browser:choose-browser-target "sandbox" nil)))
  (is (eq :host (cl-claw.browser:choose-browser-target "host" nil))))

(test build-browser-open-request-emits-stable-shape
  (let ((request (cl-claw.browser:build-browser-open-request "https://example.com" "chrome" :host)))
    (is (string= "open" (gethash "action" request)))
    (is (string= "https://example.com" (gethash "url" request)))
    (is (string= "chrome" (gethash "profile" request)))
    (is (string= "host" (gethash "target" request)))))
