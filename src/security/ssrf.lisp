;;;; ssrf.lisp — SSRF (Server-Side Request Forgery) protection
;;;;
;;;; Implements URL validation to block requests to private/internal IP ranges,
;;;; localhost, and cloud metadata endpoints.

(defpackage :cl-claw.security.ssrf
  (:use :cl)
  (:export
   :check-url-for-ssrf
   :ssrf-check-result
   :ssrf-check-result-blocked-p
   :ssrf-check-result-reason
   :is-private-ip-p
   :is-safe-url-p))

(in-package :cl-claw.security.ssrf)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── SSRF check result ───────────────────────────────────────────────────────

(defstruct ssrf-check-result
  "Result of an SSRF URL check."
  (blocked-p nil    :type boolean)
  (reason    ""     :type string))

;;; ─── Blocked host patterns ───────────────────────────────────────────────────

(defparameter *blocked-hosts*
  '("localhost"
    "127.0.0.1"
    "0.0.0.0"
    "::1"
    "169.254.169.254"  ; AWS metadata
    "metadata.google.internal"
    "169.254.170.2")   ; ECS metadata
  "Exact hostnames/IPs that are always blocked.")

(defparameter *blocked-host-patterns*
  '("^10\\."                          ; 10.0.0.0/8
    "^172\\.(1[6-9]|2[0-9]|3[01])\\." ; 172.16-31.x.x
    "^192\\.168\\."                    ; 192.168.0.0/16
    "^fc[0-9a-f]{2}:"                  ; IPv6 fc00::/7
    "^fd[0-9a-f]{2}:"                  ; IPv6 fd00::/8
    "^fe80:"                           ; IPv6 link-local
    "\\.local$"                        ; mDNS .local domains
    "\\.internal$")                    ; internal domains
  "Regex patterns for private/internal host ranges.")

(defparameter *blocked-schemes*
  '("file" "ftp" "ftps" "gopher" "ldap" "ldaps" "dict" "sftp")
  "URL schemes that are not allowed.")

;;; ─── Host parsing ────────────────────────────────────────────────────────────

(declaim (ftype (function (string) (or string null)) extract-host))
(defun extract-host (url)
  "Extract the hostname from URL."
  (declare (type string url))
  (handler-case
      (multiple-value-bind (start end regs-start regs-end)
          (cl-ppcre:scan "^[a-z][a-z0-9+.-]*://([^/:?#]+)" url)
        (declare (ignore start end))
        (when (and regs-start (> (length regs-start) 0))
          (string-downcase (subseq url (aref regs-start 0) (aref regs-end 0)))))
    (error () nil)))

(declaim (ftype (function (string) (or string null)) extract-scheme))
(defun extract-scheme (url)
  "Extract the scheme from URL."
  (declare (type string url))
  (handler-case
      (multiple-value-bind (start end regs-start regs-end)
          (cl-ppcre:scan "^([a-z][a-z0-9+.-]*)://" url)
        (declare (ignore start end))
        (when (and regs-start (> (length regs-start) 0))
          (string-downcase (subseq url (aref regs-start 0) (aref regs-end 0)))))
    (error () nil)))

;;; ─── Private IP check ────────────────────────────────────────────────────────

(declaim (ftype (function (string) boolean) is-private-ip-p))
(defun is-private-ip-p (host)
  "Return T if HOST is a private/internal IP address or hostname."
  (declare (type string host))
  (let ((lower (string-downcase host)))
    (declare (type string lower))
    ;; Check exact blocked hosts
    (when (member lower *blocked-hosts* :test #'equal)
      (return-from is-private-ip-p t))
    ;; Check patterns
    (not (null (some (lambda (pat)
                       (not (null (cl-ppcre:scan pat lower))))
                     *blocked-host-patterns*)))))

;;; ─── SSRF check ──────────────────────────────────────────────────────────────

(declaim (ftype (function (string &key (:allow-private boolean)) ssrf-check-result)
                check-url-for-ssrf))
(defun check-url-for-ssrf (url &key allow-private)
  "Check URL for SSRF risk. Returns SSRF-CHECK-RESULT.

ALLOW-PRIVATE: if T, skip private IP blocking (for development/internal use)"
  (declare (type string url)
           (type boolean allow-private))
  ;; Check scheme
  (let ((scheme (extract-scheme url)))
    (declare (type (or string null) scheme))
    (when (and scheme (member scheme *blocked-schemes* :test #'equal))
      (return-from check-url-for-ssrf
        (make-ssrf-check-result
         :blocked-p t
         :reason (format nil "Blocked URL scheme: ~a" scheme)))))
  ;; Check host
  (unless allow-private
    (let ((host (extract-host url)))
      (declare (type (or string null) host))
      (when host
        (when (is-private-ip-p host)
          (return-from check-url-for-ssrf
            (make-ssrf-check-result
             :blocked-p t
             :reason (format nil "Blocked private/internal host: ~a" host)))))))
  (make-ssrf-check-result :blocked-p nil :reason ""))

(declaim (ftype (function (string &key (:allow-private boolean)) boolean) is-safe-url-p))
(defun is-safe-url-p (url &key allow-private)
  "Return T if URL is safe (not SSRF-risky)."
  (declare (type string url)
           (type boolean allow-private))
  (not (ssrf-check-result-blocked-p
        (check-url-for-ssrf url :allow-private allow-private))))
