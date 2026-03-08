;;;; core.lisp — hook registration and lifecycle execution

(defpackage :cl-claw.hooks
  (:use :cl)
  (:export
   :create-hook-registry
   :register-hook-handler
   :list-hook-handlers
   :run-hook
   :run-hook-safe
   :default-bundled-hook-names))

(in-package :cl-claw.hooks)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function () hash-table) create-hook-registry))
(defun create-hook-registry ()
  (make-hash-table :test 'equal))

(declaim (ftype (function () list) default-bundled-hook-names))
(defun default-bundled-hook-names ()
  (list "message:received"
        "message:before-send"
        "message:after-send"
        "lifecycle:start"
        "lifecycle:stop"
        "lifecycle:error"))

(declaim (ftype (function (hash-table string function) list) register-hook-handler))
(defun register-hook-handler (registry hook-name handler)
  (declare (type hash-table registry)
           (type string hook-name)
           (type function handler))
  (let* ((name (string-downcase hook-name))
         (handlers (gethash name registry)))
    (declare (type string name)
             (type t handlers))
    (setf (gethash name registry)
          (append (if (listp handlers) handlers nil)
                  (list handler)))
    (the list (gethash name registry))))

(declaim (ftype (function (hash-table string) list) list-hook-handlers))
(defun list-hook-handlers (registry hook-name)
  (declare (type hash-table registry)
           (type string hook-name))
  (let ((handlers (gethash (string-downcase hook-name) registry)))
    (declare (type t handlers))
    (if (listp handlers) handlers nil)))

(declaim (ftype (function (hash-table string &optional t) list) run-hook))
(defun run-hook (registry hook-name &optional payload)
  (declare (type hash-table registry)
           (type string hook-name))
  (let ((results nil))
    (declare (type list results))
    (dolist (handler (list-hook-handlers registry hook-name))
      (push (funcall handler payload) results))
    (nreverse results)))

(declaim (ftype (function (hash-table string &optional t) hash-table) run-hook-safe))
(defun run-hook-safe (registry hook-name &optional payload)
  (declare (type hash-table registry)
           (type string hook-name))
  (let ((result (make-hash-table :test 'equal))
        (ok nil)
        (errors nil))
    (declare (type hash-table result)
             (type list ok errors))
    (dolist (handler (list-hook-handlers registry hook-name))
      (handler-case
          (push (funcall handler payload) ok)
        (error (e)
          (push (princ-to-string e) errors))))
    (setf (gethash "ok" result) (nreverse ok)
          (gethash "errors" result) (nreverse errors)
          (gethash "had-errors" result) (not (null errors)))
    result))
