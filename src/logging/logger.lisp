;;;; logger.lisp — Core logging infrastructure
;;;;
;;;; Provides a structured logger with level filtering, subsystem support,
;;;; timestamp formatting, and optional redaction.

(defpackage :cl-claw.logging.logger
  (:use :cl)
  (:export
   ;; Logger struct
   :logger
   :make-logger
   :logger-level
   :logger-subsystem
   :logger-redact-mode
   :logger-timestamp-tz

   ;; Log levels
   :+level-debug+
   :+level-info+
   :+level-warn+
   :+level-error+
   :+level-silent+

   ;; Logging functions
   :log-debug
   :log-info
   :log-warn
   :log-error
   :logger-enabled-p

   ;; Level parsing
   :parse-log-level
   :log-level-name))

(in-package :cl-claw.logging.logger)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Log levels ──────────────────────────────────────────────────────────────

(defconstant +level-debug+  0 "Debug log level.")
(defconstant +level-info+   1 "Info log level.")
(defconstant +level-warn+   2 "Warn log level.")
(defconstant +level-error+  3 "Error log level.")
(defconstant +level-silent+ 9 "Silent — no output.")

(declaim (ftype (function (string) fixnum) parse-log-level))
(defun parse-log-level (name)
  "Parse a level name string to its numeric value. Defaults to INFO."
  (declare (type string name))
  (cond
    ((string-equal name "debug")  +level-debug+)
    ((string-equal name "info")   +level-info+)
    ((string-equal name "warn")   +level-warn+)
    ((string-equal name "error")  +level-error+)
    ((string-equal name "silent") +level-silent+)
    (t +level-info+)))

(declaim (ftype (function (fixnum) string) log-level-name))
(defun log-level-name (level)
  "Return the string name for a numeric LEVEL."
  (declare (type fixnum level))
  (cond
    ((= level +level-debug+)  "debug")
    ((= level +level-info+)   "info")
    ((= level +level-warn+)   "warn")
    ((= level +level-error+)  "error")
    ((= level +level-silent+) "silent")
    (t "info")))

;;; ─── Logger struct ───────────────────────────────────────────────────────────

(defstruct (logger (:constructor make-logger
                    (&key (level +level-info+)
                          (subsystem "")
                          (redact-mode "tools")
                          (timestamp-tz "UTC")
                          (output-stream *standard-output*))))
  "A structured logger."
  (level           +level-info+ :type fixnum)
  (subsystem       ""           :type string)
  (redact-mode     "tools"      :type string)
  (timestamp-tz    "UTC"        :type string)
  (output-stream   *standard-output* :type t))

;;; ─── Level check ─────────────────────────────────────────────────────────────

(declaim (ftype (function (logger fixnum) boolean) logger-enabled-p))
(defun logger-enabled-p (lgr level)
  "Return T if LEVEL is enabled for LGR."
  (declare (type logger lgr)
           (type fixnum level))
  (>= level (logger-level lgr)))

;;; ─── Formatting ──────────────────────────────────────────────────────────────

(declaim (ftype (function (logger fixnum string &rest t) t) log-message))
(defun log-message (lgr level format-string &rest args)
  "Internal: log a message at LEVEL if enabled."
  (declare (type logger lgr)
           (type fixnum level)
           (type string format-string))
  (when (logger-enabled-p lgr level)
    (let* ((msg (apply #'format nil format-string args))
           (ts  (handler-case
                    (cl-claw.logging.timestamps:format-local-iso-with-offset
                     (local-time:now)
                     (logger-timestamp-tz lgr))
                  (error () (format nil "~a" (get-universal-time)))))
           (subsys (logger-subsystem lgr))
           (lvl-name (log-level-name level))
           (line (if (string= subsys "")
                     (format nil "[~a] [~a] ~a~%" ts lvl-name msg)
                     (format nil "[~a] [~a] [~a] ~a~%" ts lvl-name subsys msg))))
      (declare (type string msg ts subsys lvl-name line))
      (write-string line (logger-output-stream lgr))
      (force-output (logger-output-stream lgr)))))

(declaim (ftype (function (logger string &rest t) t) log-debug))
(defun log-debug (lgr format-string &rest args)
  "Log a debug message."
  (declare (type logger lgr) (type string format-string))
  (apply #'log-message lgr +level-debug+ format-string args))

(declaim (ftype (function (logger string &rest t) t) log-info))
(defun log-info (lgr format-string &rest args)
  "Log an info message."
  (declare (type logger lgr) (type string format-string))
  (apply #'log-message lgr +level-info+ format-string args))

(declaim (ftype (function (logger string &rest t) t) log-warn))
(defun log-warn (lgr format-string &rest args)
  "Log a warn message."
  (declare (type logger lgr) (type string format-string))
  (apply #'log-message lgr +level-warn+ format-string args))

(declaim (ftype (function (logger string &rest t) t) log-error))
(defun log-error (lgr format-string &rest args)
  "Log an error message."
  (declare (type logger lgr) (type string format-string))
  (apply #'log-message lgr +level-error+ format-string args))
