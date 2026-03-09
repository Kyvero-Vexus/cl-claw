;;;; tailnet.lisp - Tailscale/Tailnet integration for cl-claw
;;;;
;;;; Provides utilities for detecting and using Tailscale/Tailnet
;;;; networking, including IP discovery and bind address resolution.

(defpackage :cl-claw.infra.tailnet
  (:use :cl)
  (:import-from :cl-ppcre :scan-to-strings)
  (:export :get-tailnet-ip
           :tailnet-available-p
           :resolve-bind-address
           :tailnet-info
           :make-tailnet-info
           :tailnet-info-ip
           :tailnet-info-hostname
           :tailnet-info-available))
(in-package :cl-claw.infra.tailnet)

(declaim (optimize (safety 3) (debug 3)))

(defstruct tailnet-info
  "Information about tailnet/Tailscale connectivity."
  (ip nil :type (or null string))
  (hostname nil :type (or null string))
  (available nil :type boolean))

(defparameter *tailscale-check-commands*
  '("tailscale" "/usr/local/bin/tailscale" "/usr/bin/tailscale")
  "Paths to try for the tailscale CLI.")

(declaim (ftype (function () (or null string)) find-tailscale-binary))
(defun find-tailscale-binary ()
  "Find the tailscale binary, returning its path or NIL."
  (dolist (cmd *tailscale-check-commands*)
    (handler-case
        (progn
          (uiop:run-program (list "which" cmd) :output :string :ignore-error-status t)
          (return-from find-tailscale-binary cmd))
      (error () nil)))
  nil)

(declaim (ftype (function (string) (or null string)) parse-tailscale-ip))
(defun parse-tailscale-ip (output)
  "Parse tailscale IP from 'tailscale ip' command output.
Returns the first non-IPv6 address, or NIL."
  (declare (type string output))
  (let ((lines (remove-if (lambda (s) (string= s ""))
                          (uiop:split-string output :separator '(#\Newline)))))
    (dolist (line lines)
      (let ((trimmed (string-trim '(#\Space #\Tab #\Return) line)))
        ;; Prefer 100.x.x.x Tailscale CGNAT addresses
        (when (and (> (length trimmed) 0)
                   (not (find #\: trimmed)))  ; skip IPv6
          (return-from parse-tailscale-ip trimmed))))
    nil))

(declaim (ftype (function (&key (:timeout-ms (integer 0))) (or null string)) get-tailnet-ip))
(defun get-tailnet-ip (&key (timeout-ms 2000))
  "Get the current Tailnet IP address.
Returns the IP string or NIL if Tailscale is not available."
  (declare (ignore timeout-ms))
  (let ((binary (find-tailscale-binary)))
    (when binary
      (handler-case
          (let ((output (uiop:run-program (list binary "ip")
                                          :output :string
                                          :ignore-error-status t)))
            (parse-tailscale-ip output))
        (error () nil)))))

(declaim (ftype (function () boolean) tailnet-available-p))
(defun tailnet-available-p ()
  "Return T if Tailscale/Tailnet is available on this system."
  (not (null (get-tailnet-ip))))

(declaim (ftype (function () (or null string)) get-tailnet-hostname))
(defun get-tailnet-hostname ()
  "Get the Tailscale hostname, or NIL if unavailable."
  (let ((binary (find-tailscale-binary)))
    (when binary
      (handler-case
          (let ((output (uiop:run-program (list binary "status" "--json")
                                          :output :string
                                          :ignore-error-status t)))
            ;; Very basic JSON hostname extraction - find "Self":{"HostName":"..."}
            (let ((match (cl-ppcre:scan-to-strings "\"HostName\":\"([^\"]+)\"" output)))
              (when match match)))
        (error () nil)))))

(declaim (ftype (function () tailnet-info) tailnet-info))
(defun tailnet-info ()
  "Get comprehensive tailnet info struct.
Returns a TAILNET-INFO with availability, IP, and hostname."
  (let ((ip (get-tailnet-ip)))
    (make-tailnet-info
     :ip ip
     :hostname (when ip (get-tailnet-hostname))
     :available (not (null ip)))))

(declaim (ftype (function (&key (:mode keyword) (:explicit-ip (or null string))) string) resolve-bind-address))
(defun resolve-bind-address (&key (mode :auto) (explicit-ip nil))
  "Resolve the gateway bind address based on MODE.

:auto    - use 127.0.0.1 normally, tailnet IP if tailnet is present and configured
:loopback - always use 127.0.0.1
:tailnet  - use the tailnet IP (error if unavailable)
:all      - use 0.0.0.0 (all interfaces)

EXPLICIT-IP overrides everything if provided."
  (cond
    (explicit-ip explicit-ip)
    ((eq mode :loopback) "127.0.0.1")
    ((eq mode :all) "0.0.0.0")
    ((eq mode :tailnet)
     (or (get-tailnet-ip)
         (error "Tailnet bind requested but Tailscale is not available")))
    (t  ; :auto
     "127.0.0.1")))
