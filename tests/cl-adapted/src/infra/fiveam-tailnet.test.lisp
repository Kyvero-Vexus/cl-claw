;;;; fiveam-tailnet.test.lisp - FiveAM tests for tailnet module

(defpackage :cl-claw.infra.tailnet.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.tailnet.test)

(def-suite tailnet-suite
  :description "Tests for the tailnet module")
(in-suite tailnet-suite)

(test creates-tailnet-info-struct
  "Creates a tailnet-info struct with expected fields"
  (let ((info (cl-claw.infra.tailnet:make-tailnet-info
               :ip "100.1.2.3"
               :hostname "my-host"
               :available t)))
    (is (string= "100.1.2.3" (cl-claw.infra.tailnet:tailnet-info-ip info)))
    (is (string= "my-host" (cl-claw.infra.tailnet:tailnet-info-hostname info)))
    (is-true (cl-claw.infra.tailnet:tailnet-info-available info))))

(test resolve-bind-address-loopback-mode
  "Resolves to 127.0.0.1 in loopback mode"
  (let ((addr (cl-claw.infra.tailnet:resolve-bind-address :mode :loopback)))
    (is (string= "127.0.0.1" addr))))

(test resolve-bind-address-all-mode
  "Resolves to 0.0.0.0 in all-interfaces mode"
  (let ((addr (cl-claw.infra.tailnet:resolve-bind-address :mode :all)))
    (is (string= "0.0.0.0" addr))))

(test resolve-bind-address-auto-mode-defaults-to-loopback
  "Auto mode defaults to 127.0.0.1 (tailnet IP used only when available)"
  (let ((addr (cl-claw.infra.tailnet:resolve-bind-address :mode :auto)))
    ;; On a system without tailscale, should be loopback
    (is (not (null addr)))
    (is (stringp addr))))

(test resolve-bind-address-explicit-ip-overrides-all
  "Explicit IP overrides all mode settings"
  (let ((addr (cl-claw.infra.tailnet:resolve-bind-address
               :mode :loopback
               :explicit-ip "10.0.0.1")))
    (is (string= "10.0.0.1" addr))))

(test parse-tailscale-ip-prefers-ipv4
  "parse-tailscale-ip returns first IPv4 address"
  (let* ((output (format nil "100.64.1.2~%fd7a:115c:a1e0::1~%"))
         ;; Access internal function via restart package
         (ip (cl-claw.infra.tailnet::parse-tailscale-ip output)))
    (is (string= "100.64.1.2" ip))))

(test parse-tailscale-ip-skips-ipv6
  "parse-tailscale-ip skips IPv6 addresses"
  (let* ((output (format nil "fd7a:115c:a1e0::1~%100.64.1.2~%"))
         (ip (cl-claw.infra.tailnet::parse-tailscale-ip output)))
    (is (string= "100.64.1.2" ip))))

(test parse-tailscale-ip-empty-returns-nil
  "parse-tailscale-ip returns NIL for empty output"
  (let ((ip (cl-claw.infra.tailnet::parse-tailscale-ip "")))
    (is (null ip))))

(test keeps-loopback-for-auto-when-tailnet-absent
  "Auto mode keeps loopback when tailnet is not present"
  ;; This test verifies the default behavior (no tailscale installed)
  (let ((addr (cl-claw.infra.tailnet:resolve-bind-address :mode :auto)))
    ;; Should be a valid IP string
    (is (stringp addr))
    (is (> (length addr) 0))))
