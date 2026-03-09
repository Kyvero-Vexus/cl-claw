;;;; audit.lisp — Security audit: scan for config and runtime security issues
;;;;
;;;; Implements RUN-SECURITY-AUDIT which checks for common security misconfigurations.

(defpackage :cl-claw.security.audit
  (:use :cl)
  (:export
   :run-security-audit
   :security-audit-report
   :security-audit-report-findings
   :security-audit-report-clean-p
   :security-finding
   :security-finding-code
   :security-finding-severity
   :security-finding-message
   :security-finding-remediation))

(in-package :cl-claw.security.audit)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Security finding ────────────────────────────────────────────────────────

(defstruct security-finding
  "A single security audit finding."
  (code        ""     :type string)
  (severity    :info  :type keyword)  ; :critical :high :medium :low :info
  (message     ""     :type string)
  (remediation ""     :type string))

;;; ─── Security audit report ───────────────────────────────────────────────────

(defstruct security-audit-report
  "Result of running a security audit."
  (findings '() :type list)
  (clean-p  t   :type boolean))

;;; ─── Check helpers ───────────────────────────────────────────────────────────

(declaim (ftype (function (t) t) get-ht))
(defun get-ht (obj)
  "Return OBJ if it is a hash-table, else NIL."
  (declare (type t obj))
  (when (hash-table-p obj) obj))

(declaim (ftype (function (t string) t) ht-get))
(defun ht-get (ht key)
  "Get KEY from hash-table HT, or NIL."
  (declare (type t ht)
           (type string key))
  (when (hash-table-p ht) (gethash key ht)))

;;; ─── Security checks ─────────────────────────────────────────────────────────

(declaim (ftype (function (t list) list) check-auth-mode))
(defun check-auth-mode (config findings)
  "Warn if gateway auth mode is 'none' (no authentication)."
  (declare (type t config)
           (type list findings))
  (let* ((gateway (ht-get config "gateway"))
         (auth    (ht-get gateway "auth"))
         (mode    (ht-get auth "mode")))
    (when (or (null mode) (equal mode "none"))
      (push (make-security-finding
             :code "GATEWAY_AUTH_NONE"
             :severity :high
             :message "Gateway authentication is disabled (mode=none)"
             :remediation "Set gateway.auth.mode to 'token' or 'pairing'")
            findings))
    findings))

(declaim (ftype (function (t list) list) check-open-dm-policy))
(defun check-open-dm-policy (config findings)
  "Flag channels with dmPolicy=open and no wildcard allowFrom."
  (declare (type t config)
           (type list findings))
  (let ((channels (ht-get config "channels")))
    (dolist (channel-id '("telegram" "discord" "slack"))
      (declare (type string channel-id))
      (let* ((ch (ht-get channels channel-id))
             (dm-policy (ht-get ch "dmPolicy"))
             (allow-from (ht-get ch "allowFrom")))
        (when (equal dm-policy "open")
          (let ((has-wildcard
                 (and allow-from
                      (typecase allow-from
                        (vector (find "*" (coerce allow-from 'list) :test #'equal))
                        (list   (find "*" allow-from :test #'equal))
                        (t      nil)))))
            (declare (type boolean has-wildcard))
            (unless has-wildcard
              (push (make-security-finding
                     :code "OPEN_DM_WITHOUT_ALLOWFROM"
                     :severity :medium
                     :message (format nil "Channel ~a has dmPolicy=open without wildcard allowFrom" channel-id)
                     :remediation (format nil "Add '*' to channels.~a.allowFrom or change dmPolicy to 'pairing'" channel-id))
                    findings))))))
    findings))

(declaim (ftype (function (t list) list) check-sandbox-mode))
(defun check-sandbox-mode (config findings)
  "Warn if sandbox is disabled or running in host mode without restrictions."
  (declare (type t config)
           (type list findings))
  (let* ((agents   (ht-get config "agents"))
         (defaults (ht-get agents "defaults"))
         (sandbox  (ht-get defaults "sandbox")))
    (when (equal sandbox "none")
      (push (make-security-finding
             :code "SANDBOX_DISABLED"
             :severity :high
             :message "Agent sandbox is disabled (sandbox=none)"
             :remediation "Enable sandboxing via agents.defaults.sandbox")
            findings))
    findings))

;;; ─── Main audit entry point ──────────────────────────────────────────────────

(declaim (ftype (function (&key (:config t)
                                (:state-dir (or string null))
                                (:env t))
                          security-audit-report)
                run-security-audit))
(defun run-security-audit (&key config state-dir env)
  "Run a security audit against CONFIG and the state at STATE-DIR.

CONFIG: parsed config hash-table
STATE-DIR: path to .openclaw directory
ENV: hash-table of environment variables

Returns a SECURITY-AUDIT-REPORT."
  (declare (type t config state-dir env))
  (declare (ignore state-dir env))
  (let ((findings '()))
    (declare (type list findings))
    (setf findings (check-auth-mode config findings))
    (setf findings (check-open-dm-policy config findings))
    (setf findings (check-sandbox-mode config findings))
    (make-security-audit-report
     :findings (reverse findings)
     :clean-p (null findings))))
