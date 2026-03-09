;;;; translator.lisp — ACP translator: prompt CWD prefix, session rate limiting,
;;;;                   oversize prompt rejection
;;;;
;;;; The translator sits between ACP protocol events and the gateway, transforming
;;;; prompts (prefixing working directory, redacting home paths) and enforcing
;;;; rate limits on session creation.

(defpackage :cl-claw.acp.translator
  (:use :cl :cl-claw.acp.types)
  (:export
   :make-rate-limiter
   :rate-limiter
   :rate-limiter-allow-p
   :rate-limiter-reset
   :prefix-prompt-with-cwd
   :redact-home-in-path
   :validate-prompt-size))

(in-package :cl-claw.acp.translator)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Home Directory Redaction ───────────────────────────────────────────────

(declaim (ftype (function (string &optional (or string null)) string) redact-home-in-path))
(defun redact-home-in-path (path &optional home-dir)
  "Replace the home directory prefix in PATH with '~'.
   Preserves the original separator style (/ or \\)."
  (declare (type string path)
           (type (or string null) home-dir))
  (let ((home (or home-dir
                  (uiop:getenv "HOME")
                  (namestring (user-homedir-pathname)))))
    (declare (type string home))
    ;; Normalize: strip trailing slashes from home for comparison
    (let ((clean-home (string-right-trim '(#\/ #\\) home)))
      (declare (type string clean-home))
      (cond
        ;; Exact match
        ((string= path clean-home) "~")
        ;; path starts with home + separator
        ((and (> (length path) (length clean-home))
              (string= (subseq path 0 (length clean-home)) clean-home)
              (let ((sep (char path (length clean-home))))
                (or (char= sep #\/) (char= sep #\\))))
         (concatenate 'string "~" (subseq path (length clean-home))))
        (t path)))))

;;; ─── CWD Prefix ─────────────────────────────────────────────────────────────

(declaim (ftype (function (string string &key (:prefix-cwd boolean)) string)
                prefix-prompt-with-cwd))
(defun prefix-prompt-with-cwd (message cwd &key (prefix-cwd t))
  "Prepend [Working directory: <cwd>] to the message if PREFIX-CWD is true.
   Home directory is redacted to ~."
  (declare (type string message cwd)
           (type boolean prefix-cwd))
  (if (and prefix-cwd (not (string= cwd "")))
      (let ((redacted (redact-home-in-path cwd)))
        (declare (type string redacted))
        (format nil "[Working directory: ~A]~%~%~A" redacted message))
      message))

;;; ─── Rate Limiter ───────────────────────────────────────────────────────────

(defstruct (rate-limiter (:conc-name rate-limiter-))
  "Token bucket rate limiter for ACP session creation."
  (max-requests 10 :type fixnum)
  (window-ms 60000 :type fixnum)
  (timestamps nil :type list)
  (lock (bt:make-lock "rate-limiter") :type t))

(declaim (ftype (function (rate-limiter &key (:now fixnum)) boolean) rate-limiter-allow-p))
(defun rate-limiter-allow-p (limiter &key (now 0))
  "Returns T if the request is allowed under the rate limit."
  (declare (type rate-limiter limiter) (type fixnum now))
  (bt:with-lock-held ((rate-limiter-lock limiter))
    (let* ((window (rate-limiter-window-ms limiter))
           (cutoff (- now window))
           ;; Prune old timestamps
           (fresh (remove-if (lambda (ts) (< ts cutoff))
                             (rate-limiter-timestamps limiter))))
      (declare (type fixnum window cutoff) (type list fresh))
      (setf (rate-limiter-timestamps limiter) fresh)
      (if (< (length fresh) (rate-limiter-max-requests limiter))
          (progn
            (push now (rate-limiter-timestamps limiter))
            t)
          nil))))

(declaim (ftype (function (rate-limiter) null) rate-limiter-reset))
(defun rate-limiter-reset (limiter)
  "Clear all recorded timestamps."
  (declare (type rate-limiter limiter))
  (bt:with-lock-held ((rate-limiter-lock limiter))
    (setf (rate-limiter-timestamps limiter) nil))
  nil)

;;; ─── Prompt Size Validation ─────────────────────────────────────────────────

(declaim (ftype (function (string &key (:max-bytes fixnum)) boolean) validate-prompt-size))
(defun validate-prompt-size (prompt &key (max-bytes (* 1024 1024)))
  "Returns T if the prompt is within size limits.
   Signals ACP-ERROR if too large."
  (declare (type string prompt) (type fixnum max-bytes))
  (let ((size (length (the string prompt))))
    (declare (type fixnum size))
    (when (> size max-bytes)
      (error 'acp-error
             :code "ACP_PROMPT_TOO_LARGE"
             :text (format nil "Prompt exceeds maximum size (~:D bytes > ~:D limit)"
                           size max-bytes)))
    t))
