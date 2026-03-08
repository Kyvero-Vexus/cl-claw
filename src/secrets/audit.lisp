;;;; audit.lisp — Secrets audit: scan config files for hardcoded secrets
;;;;
;;;; Implements RUN-SECRETS-AUDIT which scans openclaw state files for
;;;; plaintext secrets that should be externalized via secret refs.

(defpackage :cl-claw.secrets.audit
  (:use :cl)
  (:export
   :run-secrets-audit
   :audit-report
   :audit-report-findings
   :audit-report-clean-p
   :audit-finding
   :audit-finding-code
   :audit-finding-file
   :audit-finding-json-path
   :audit-finding-message))

(in-package :cl-claw.secrets.audit)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Audit finding ───────────────────────────────────────────────────────────

(defstruct audit-finding
  "A single secret audit finding."
  (code      ""  :type string)  ; e.g. "HARDCODED_API_KEY"
  (file      ""  :type string)  ; file path where found
  (json-path nil :type (or string null)) ; JSON path within file
  (message   ""  :type string))

;;; ─── Audit report ────────────────────────────────────────────────────────────

(defstruct audit-report
  "Result of running a secrets audit."
  (findings '() :type list)     ; list of AUDIT-FINDING
  (clean-p  t   :type boolean))

;;; ─── Secret detection patterns ───────────────────────────────────────────────

(defparameter *secret-key-patterns*
  '("(?i)api[_-]?key" "(?i)auth[_-]?token" "(?i)secret[_-]?key"
    "(?i)password" "(?i)private[_-]?key" "(?i)access[_-]?token"
    "(?i)bearer" "(?i)credential")
  "Regex patterns that suggest a key name is secret-bearing.")

(defparameter *secret-value-patterns*
  '(;; API keys (sk-, sk-proj-, etc.)
    "^sk-[a-zA-Z0-9]{20,}$"
    ;; GitHub tokens
    "^gh[pousr]_[A-Za-z0-9]{36,}$"
    ;; Telegram bot tokens
    "^[0-9]{6,}:[A-Za-z0-9_-]{30,}$"
    ;; Generic long random strings (likely tokens)
    "^[A-Za-z0-9+/=]{40,}$")
  "Regex patterns that match likely secret values.")

(declaim (ftype (function (string) boolean) looks-like-secret-key-p))
(defun looks-like-secret-key-p (key)
  "Return T if KEY name suggests it holds a secret."
  (declare (type string key))
  (not (null (some (lambda (pat)
                     (not (null (cl-ppcre:scan pat key))))
                   *secret-key-patterns*))))

(declaim (ftype (function (string) boolean) looks-like-secret-value-p))
(defun looks-like-secret-value-p (value)
  "Return T if VALUE looks like a hardcoded secret."
  (declare (type string value))
  ;; Already a secret ref → not a hardcoded secret
  (when (cl-ppcre:scan "^\\$\\{" value)
    (return-from looks-like-secret-value-p nil))
  (not (null (some (lambda (pat)
                     (not (null (cl-ppcre:scan pat value))))
                   *secret-value-patterns*))))

;;; ─── JSON scanning ───────────────────────────────────────────────────────────

(declaim (ftype (function (t string string) list) scan-json-for-secrets))
(defun scan-json-for-secrets (obj file-path json-path)
  "Recursively scan OBJ (parsed JSON) for hardcoded secrets.
Returns a list of AUDIT-FINDING."
  (declare (type t obj)
           (type string file-path json-path))
  (typecase obj
    (hash-table
     (let ((findings '()))
       (declare (type list findings))
       (maphash
        (lambda (key value)
          (declare (type string key)
                   (type t value))
          (let ((child-path (if (string= json-path "")
                                key
                                (format nil "~a.~a" json-path key))))
            (declare (type string child-path))
            ;; Check if this key-value pair looks like a secret
            (when (and (stringp value)
                       (looks-like-secret-key-p key)
                       (looks-like-secret-value-p value))
              (push (make-audit-finding
                     :code "HARDCODED_SECRET"
                     :file file-path
                     :json-path child-path
                     :message (format nil "Possible hardcoded secret at ~a in ~a"
                                      child-path file-path))
                    findings))
            ;; Recurse into nested objects/arrays
            (setf findings
                  (append findings
                          (scan-json-for-secrets value file-path child-path)))))
        obj)
       findings))
    (vector
     (let ((findings '()))
       (declare (type list findings))
       (loop for i from 0 below (length obj)
             do (let* ((item (aref obj i))
                       (child-path (format nil "~a[~a]" json-path i)))
                  (declare (type t item)
                           (type string child-path))
                  (setf findings
                        (append findings
                                (scan-json-for-secrets item file-path child-path)))))
       findings))
    (t '())))

;;; ─── File scanning ───────────────────────────────────────────────────────────

(declaim (ftype (function (string) list) scan-file-for-secrets))
(defun scan-file-for-secrets (file-path)
  "Scan a single file for hardcoded secrets. Returns list of AUDIT-FINDING."
  (declare (type string file-path))
  (unless (uiop:file-exists-p file-path)
    (return-from scan-file-for-secrets '()))
  (handler-case
      (let* ((content (uiop:read-file-string file-path))
             (parsed  (yason:parse content :object-as :hash-table)))
        (declare (type string content)
                 (type t parsed))
        (scan-json-for-secrets parsed file-path ""))
    (error ()
      ;; Non-JSON or unreadable file: skip
      '())))

;;; ─── Env file scanning ───────────────────────────────────────────────────────

(declaim (ftype (function (string) list) scan-env-file-for-secrets))
(defun scan-env-file-for-secrets (file-path)
  "Scan a .env file for hardcoded secrets. Returns list of AUDIT-FINDING."
  (declare (type string file-path))
  (unless (uiop:file-exists-p file-path)
    (return-from scan-env-file-for-secrets '()))
  (handler-case
      (let ((findings '()))
        (declare (type list findings))
        (with-open-file (f file-path :direction :input)
          (loop for line = (read-line f nil nil)
                while line
                do (let ((trimmed (string-trim '(#\Space #\Tab) line)))
                     (declare (type string trimmed))
                     (unless (or (string= trimmed "")
                                 (char= (char trimmed 0) #\#))
                       (let ((eq-pos (position #\= trimmed)))
                         (declare (type (or fixnum null) eq-pos))
                         (when eq-pos
                           (let ((key (subseq trimmed 0 eq-pos))
                                 (val (subseq trimmed (1+ eq-pos))))
                             (declare (type string key val))
                             (when (and (looks-like-secret-key-p key)
                                        (looks-like-secret-value-p val))
                               (push (make-audit-finding
                                      :code "HARDCODED_SECRET_ENV"
                                      :file file-path
                                      :json-path key
                                      :message (format nil "Hardcoded secret in .env: ~a" key))
                                     findings)))))))))
        findings)
    (error () '())))

;;; ─── Main audit entry point ──────────────────────────────────────────────────

(declaim (ftype (function (&key (:state-dir string)
                                (:config-path (or string null))
                                (:env-path (or string null))
                                (:extra-paths list))
                          audit-report)
                run-secrets-audit))
(defun run-secrets-audit (&key state-dir config-path env-path extra-paths)
  "Run a secrets audit over the openclaw state directory.

STATE-DIR: path to .openclaw directory
CONFIG-PATH: explicit config file path (or derived from state-dir)
ENV-PATH: explicit .env path (or derived from state-dir)
EXTRA-PATHS: additional JSON files to scan

Returns an AUDIT-REPORT."
  (declare (type string state-dir)
           (type (or string null) config-path env-path)
           (type list extra-paths))
  (let* ((cfg-path  (or config-path
                        (uiop:native-namestring
                         (merge-pathnames "openclaw.json"
                                          (uiop:parse-native-namestring state-dir :ensure-directory t)))))
         (env-p     (or env-path
                        (uiop:native-namestring
                         (merge-pathnames ".env"
                                          (uiop:parse-native-namestring state-dir :ensure-directory t)))))
         (all-paths (append (list cfg-path env-p) extra-paths))
         (findings  '()))
    (declare (type string cfg-path env-p)
             (type list all-paths findings))
    ;; Scan config JSON files
    (dolist (path all-paths)
      (declare (type string path))
      (cond
        ((cl-ppcre:scan "\\.env$" path)
         (setf findings (append findings (scan-env-file-for-secrets path))))
        (t
         (setf findings (append findings (scan-file-for-secrets path))))))
    (make-audit-report
     :findings findings
     :clean-p (null findings))))
