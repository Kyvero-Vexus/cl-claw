;;;; core.lisp — Command dispatch metadata

(defpackage :cl-claw.commands
  (:use :cl)
  (:export
   :command-spec
   :make-command-spec
   :command-spec-name
   :command-spec-subcommands
   :command-spec-description
   :command-spec-requires-subcommand-p
   :create-default-command-table
   :lookup-command-spec
   :command-known-p
   :subcommand-known-p
   :resolve-command-action))

(in-package :cl-claw.commands)

(declaim (optimize (safety 3) (debug 3)))

(defstruct command-spec
  (name "" :type string)
  (subcommands nil :type list)
  (description "" :type string)
  (requires-subcommand-p t :type boolean))

(declaim (ftype (function (string) string) normalize-token))
(defun normalize-token (token)
  (declare (type string token))
  (string-downcase (string-trim '(#\Space #\Tab #\Newline #\Return) token)))

(declaim (ftype (function () hash-table) create-default-command-table))
(defun create-default-command-table ()
  (let ((table (make-hash-table :test 'equal)))
    (declare (type hash-table table))
    (setf (gethash "agent" table)
          (make-command-spec :name "agent"
                             :subcommands (list "run" "spawn" "list" "status" "stop")
                             :description "Agent lifecycle and orchestration commands"
                             :requires-subcommand-p t)
          (gethash "daemon" table)
          (make-command-spec :name "daemon"
                             :subcommands (list "status" "start" "stop" "restart")
                             :description "Gateway daemon management commands"
                             :requires-subcommand-p t)
          (gethash "configure" table)
          (make-command-spec :name "configure"
                             :subcommands (list "get" "set" "list" "validate" "reset")
                             :description "Runtime configuration commands"
                             :requires-subcommand-p t)
          (gethash "doctor" table)
          (make-command-spec :name "doctor"
                             :subcommands (list "auth" "network" "env")
                             :description "Health check and diagnostics"
                             :requires-subcommand-p nil))
    table))

(declaim (ftype (function (hash-table string) (or command-spec null)) lookup-command-spec))
(defun lookup-command-spec (table command)
  (declare (type hash-table table)
           (type string command))
  (let ((spec (gethash (normalize-token command) table)))
    (declare (type t spec))
    (and (typep spec 'command-spec) spec)))

(declaim (ftype (function (hash-table string) boolean) command-known-p))
(defun command-known-p (table command)
  (declare (type hash-table table)
           (type string command))
  (not (null (lookup-command-spec table command))))

(declaim (ftype (function (hash-table string string) boolean) subcommand-known-p))
(defun subcommand-known-p (table command subcommand)
  (declare (type hash-table table)
           (type string command subcommand))
  (let ((spec (lookup-command-spec table command)))
    (declare (type (or command-spec null) spec))
    (and spec
         (member (normalize-token subcommand)
                 (command-spec-subcommands spec)
                 :test #'string=)
         t)))

(declaim (ftype (function (hash-table string (or string null) list) hash-table)
                resolve-command-action))
(defun resolve-command-action (table command subcommand args)
  (declare (type hash-table table)
           (type string command)
           (type (or string null) subcommand)
           (type list args))
  (let* ((result (make-hash-table :test 'equal))
         (spec (lookup-command-spec table command))
         (normalized-sub (and subcommand (normalize-token subcommand))))
    (declare (type hash-table result)
             (type (or command-spec null) spec)
             (type (or string null) normalized-sub))
    (cond
      ((null spec)
       (setf (gethash "ok" result) nil
             (gethash "error" result) (format nil "Unknown command: ~a" command)))
      ((and (command-spec-requires-subcommand-p spec)
            (or (null normalized-sub) (string= normalized-sub "")))
       (setf (gethash "ok" result) nil
             (gethash "error" result)
             (format nil "Command ~a requires a subcommand" (command-spec-name spec))))
      ((and normalized-sub
            (not (subcommand-known-p table (command-spec-name spec) normalized-sub)))
       (setf (gethash "ok" result) nil
             (gethash "error" result)
             (format nil "Unknown subcommand for ~a: ~a" (command-spec-name spec) normalized-sub)))
      (t
       (setf (gethash "ok" result) t
             (gethash "command" result) (command-spec-name spec)
             (gethash "subcommand" result) normalized-sub
             (gethash "args" result) args)))
    result))
