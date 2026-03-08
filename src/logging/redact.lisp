;;;; redact.lisp — Sensitive text redaction for logs and tool output
;;;;
;;;; Implements GET-DEFAULT-REDACT-PATTERNS and REDACT-SENSITIVE-TEXT.

(defpackage :cl-claw.logging.redact
  (:use :cl)
  (:export :get-default-redact-patterns
           :redact-sensitive-text))

(in-package :cl-claw.logging.redact)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Default redact patterns ─────────────────────────────────────────────────

(defparameter *default-redact-patterns*
  '((:regex "([A-Z_]{3,}(?:KEY|TOKEN|SECRET|PASSWORD|PASS|PWD|API|AUTH)[A-Z_]*)=([A-Za-z0-9+/=_~-]{8,})"
     :type :env-assign)
    (:regex "\"(?:token|api[-_]?key|secret|password|auth|bearer)\"\\s*:\\s*\"([A-Za-z0-9+/=_~.-]{8,})\""
     :type :json-field)
    (:regex "(?:Authorization:\\s*Bearer\\s+)([A-Za-z0-9+/=_~-]{8,})"
     :type :bearer-token)
    (:regex "(?:bot)?([0-9]{5,}:[A-Za-z0-9_-]{20,})"
     :type :telegram)
    (:regex "(-----BEGIN [A-Z ]+ KEY-----)[^-]*(-----END [A-Z ]+ KEY-----)"
     :type :pem-block))
  "Default list of redaction patterns.")

;;; ─── Token masking ───────────────────────────────────────────────────────────

(declaim (ftype (function (string) string) mask-token))
(defun mask-token (token)
  "Mask TOKEN: prefix…suffix for long, *** for short."
  (declare (type string token))
  (let ((len (length token)))
    (declare (type fixnum len))
    (cond
      ((< len 8)  "***")
      ((< len 12) (format nil "~a~c~a"
                          (subseq token 0 4)
                          #\HORIZONTAL_ELLIPSIS
                          (subseq token (- len 4))))
      (t          (format nil "~a~c~a"
                          (subseq token 0 6)
                          #\HORIZONTAL_ELLIPSIS
                          (subseq token (- len 4)))))))

;;; ─── Safe regex check ────────────────────────────────────────────────────────

(declaim (ftype (function (string) boolean) safe-regex-p))
(defun safe-regex-p (pattern)
  "Return T if PATTERN is safe to apply (no nested repetition)."
  (declare (type string pattern))
  (not (cl-ppcre:scan "\\([^)]*[+*][^)]*\\)[+*]" pattern)))

;;; ─── Single-pattern application ──────────────────────────────────────────────
;;; We use :simple-calls t so the lambda receives (match reg1 reg2 ...)
;;; where each reg is the corresponding capture group string (or nil).

(declaim (ftype (function (string list) string) apply-single-pattern))
(defun apply-single-pattern (text pattern)
  "Apply one redaction PATTERN to TEXT. Returns modified string."
  (declare (type string text)
           (type list pattern))
  (let ((regex (getf pattern :regex))
        (ptype (getf pattern :type)))
    (declare (type string regex)
             (type keyword ptype))
    (handler-case
        (ecase ptype
          (:env-assign
           ;; Captures: (1)key (2)value
           ;; Replace with: key=masked-value
           (cl-ppcre:regex-replace-all
            regex text
            (lambda (match key val)
              (declare (ignore match)
                       (type (or string null) key val))
              (format nil "~a=~a"
                      (or key "")
                      (mask-token (or val ""))))
            :simple-calls t))
          (:json-field
           ;; Captures: (1)value
           ;; Full match contains key:value, replace value part
           (cl-ppcre:regex-replace-all
            regex text
            (lambda (match value)
              (declare (type string match)
                       (type (or string null) value))
              (if (and value (search value match))
                  (let ((val-start (search value match)))
                    (declare (type fixnum val-start))
                    (format nil "~a~a~a"
                            (subseq match 0 val-start)
                            (mask-token value)
                            (subseq match (+ val-start (length value)))))
                  match))
            :simple-calls t))
          (:bearer-token
           ;; Captures: (1)token
           (cl-ppcre:regex-replace-all
            regex text
            (lambda (match token)
              (declare (type string match)
                       (type (or string null) token))
              (if (and token (search token match))
                  (let ((tok-start (search token match)))
                    (declare (type fixnum tok-start))
                    (format nil "~a~a~a"
                            (subseq match 0 tok-start)
                            (mask-token token)
                            (subseq match (+ tok-start (length token)))))
                  match))
            :simple-calls t))
          (:telegram
           ;; Match entire telegram token, mask whole thing
           (cl-ppcre:regex-replace-all
            regex text
            (lambda (match &rest regs)
              (declare (ignore regs))
              (mask-token match))
            :simple-calls t))
          (:pem-block
           ;; Captures: (1)begin (2)end
           (cl-ppcre:regex-replace-all
            regex text
            (lambda (match begin end)
              (declare (ignore match)
                       (type (or string null) begin end))
              (format nil "~a~%...redacted...~%~a"
                      (or begin "-----BEGIN KEY-----")
                      (or end   "-----END KEY-----")))
            :simple-calls t)))
      (error () text))))

;;; ─── Default patterns application ───────────────────────────────────────────

(declaim (ftype (function (string list) string) apply-default-patterns))
(defun apply-default-patterns (text patterns)
  "Apply all PATTERNS to TEXT in sequence."
  (declare (type string text)
           (type list patterns))
  (let ((result text))
    (declare (type string result))
    (dolist (pattern patterns result)
      (setf result (apply-single-pattern result pattern)))))

;;; ─── Custom pattern application ──────────────────────────────────────────────

(declaim (ftype (function (string list) string) apply-custom-patterns))
(defun apply-custom-patterns (text pattern-strings)
  "Apply PATTERN-STRINGS (regex strings) to TEXT."
  (declare (type string text)
           (type list pattern-strings))
  (let ((result text))
    (declare (type string result))
    (dolist (pat pattern-strings result)
      (declare (type string pat))
      (when (safe-regex-p pat)
        (handler-case
            (setf result
                  (cl-ppcre:regex-replace-all
                   pat result
                   (lambda (match &rest regs)
                     (declare (ignore regs))
                     (if (>= (length match) 8)
                         (mask-token match)
                         "***"))
                   :simple-calls t))
          (error () nil))))))

;;; ─── Public API ──────────────────────────────────────────────────────────────

(declaim (ftype (function () list) get-default-redact-patterns))
(defun get-default-redact-patterns ()
  "Return the default list of redaction patterns."
  *default-redact-patterns*)

(declaim (ftype (function (string &key (:mode string) (:patterns list)) string)
                redact-sensitive-text))
(defun redact-sensitive-text (text &key (mode "tools") patterns)
  "Redact sensitive text. MODE: 'tools' (active) or 'off' (no-op)."
  (declare (type string text mode)
           (type list patterns))
  (when (string= mode "off")
    (return-from redact-sensitive-text text))
  (if (and patterns (stringp (car patterns)))
      (apply-custom-patterns text patterns)
      (apply-default-patterns text (or patterns *default-redact-patterns*))))
