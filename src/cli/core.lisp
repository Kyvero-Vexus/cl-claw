;;;; core.lisp — lightweight command-line parsing helpers

(defpackage :cl-claw.cli
  (:use :cl)
  (:export
   :parse-global-options
   :parse-command-line
   :normalize-command-name
   :command-invocation-string))

(in-package :cl-claw.cli)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (string) string) normalize-command-name))
(defun normalize-command-name (name)
  (declare (type string name))
  (string-downcase (string-trim '(#\Space #\Tab #\Newline #\Return) name)))

(declaim (ftype (function (list) hash-table) parse-global-options))
(defun parse-global-options (args)
  (declare (type list args))
  (let ((state (make-hash-table :test 'equal))
        (rest nil)
        (done nil))
    (declare (type hash-table state)
             (type list rest)
             (type boolean done))
    (setf (gethash "help" state) nil
          (gethash "version" state) nil
          (gethash "json" state) nil
          (gethash "verbose" state) nil)
    (dolist (arg args)
      (declare (type t arg))
      (let ((token (if (stringp arg) arg (format nil "~a" arg))))
        (declare (type string token))
        (cond
          (done (push token rest))
          ((string= token "--") (setf done t))
          ((or (string= token "-h") (string= token "--help"))
           (setf (gethash "help" state) t))
          ((or (string= token "-V") (string= token "--version"))
           (setf (gethash "version" state) t))
          ((or (string= token "-j") (string= token "--json"))
           (setf (gethash "json" state) t))
          ((or (string= token "-v") (string= token "--verbose"))
           (setf (gethash "verbose" state) t))
          ((uiop:string-prefix-p "-" token)
           (push token rest))
          (t
           (setf done t)
           (push token rest)))))
    (setf (gethash "rest" state) (nreverse rest))
    state))

(declaim (ftype (function (list) hash-table) parse-command-line))
(defun parse-command-line (args)
  (declare (type list args))
  (let* ((parsed (parse-global-options args))
         (rest (gethash "rest" parsed))
         (command (and (listp rest) (first rest)))
         (tail (if (listp rest) (rest rest) nil))
         (subcommand (and (listp tail) (first tail))))
    (declare (type hash-table parsed)
             (type t rest command tail subcommand))
    (setf (gethash "command" parsed) (and (stringp command) (normalize-command-name command))
          (gethash "subcommand" parsed) (and (stringp subcommand) (normalize-command-name subcommand))
          (gethash "args" parsed) (if (listp tail) (rest tail) nil))
    parsed))

(declaim (ftype (function (hash-table) string) command-invocation-string))
(defun command-invocation-string (parsed)
  (declare (type hash-table parsed))
  (let ((command (gethash "command" parsed))
        (subcommand (gethash "subcommand" parsed))
        (args (gethash "args" parsed)))
    (declare (type t command subcommand args))
    (format nil "~@[~a~]~@[ ~a~]~{ ~a~}" command subcommand (if (listp args) args nil))))
