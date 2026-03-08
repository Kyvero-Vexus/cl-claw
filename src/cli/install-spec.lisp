;;;; install-spec.lisp — local install-spec detection

(defpackage :cl-claw.cli.install-spec
  (:use :cl)
  (:export
   :looks-like-local-install-spec))

(in-package :cl-claw.cli.install-spec)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (string string) boolean) %ends-with-p))
(defun %ends-with-p (value suffix)
  (declare (type string value suffix))
  (let ((value-len (length value))
        (suffix-len (length suffix)))
    (declare (type fixnum value-len suffix-len))
    (and (>= value-len suffix-len)
         (string= value suffix :start1 (- value-len suffix-len)))))

(declaim (ftype (function (string list) boolean) looks-like-local-install-spec))
(defun looks-like-local-install-spec (spec known-suffixes)
  (declare (type string spec)
           (type list known-suffixes))
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) spec)))
    (declare (type string trimmed))
    (or (uiop:string-prefix-p "." trimmed)
        (uiop:string-prefix-p "~" trimmed)
        (not (null (uiop:absolute-pathname-p trimmed)))
        (loop for suffix in known-suffixes
              thereis (and (stringp suffix)
                           (%ends-with-p trimmed suffix))))))
