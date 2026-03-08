;;;; sandbox-bind-spec.lisp — Docker bind spec parsing

(defpackage :cl-claw.agents.sandbox.bind-spec
  (:use :cl)
  (:export
   :split-sandbox-bind-spec))

(in-package :cl-claw.agents.sandbox.bind-spec)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (string) fixnum) get-host-container-separator-index))
(defun get-host-container-separator-index (spec)
  (declare (type string spec))
  (let* ((len (length spec))
         (has-drive-letter-prefix
           (and (>= len 3)
                (alpha-char-p (char spec 0))
                (char= (char spec 1) #\:)
                (or (char= (char spec 2) #\\)
                    (char= (char spec 2) #\/)))))
    (declare (type fixnum len)
             (type boolean has-drive-letter-prefix))
    (loop for i fixnum from (if has-drive-letter-prefix 2 0) below len do
      (when (char= (char spec i) #\:)
        (return i))
      finally (return -1))))

(declaim (ftype (function (string) (or hash-table null)) split-sandbox-bind-spec))
(defun split-sandbox-bind-spec (spec)
  (declare (type string spec))
  (let ((separator (get-host-container-separator-index spec)))
    (declare (type fixnum separator))
    (when (>= separator 0)
      (let* ((host (subseq spec 0 separator))
             (rest (subseq spec (1+ separator)))
             (options-start (position #\: rest))
             (result (make-hash-table :test 'equal)))
        (declare (type string host rest)
                 (type (or fixnum null) options-start)
                 (type hash-table result))
        (setf (gethash "host" result) host)
        (if options-start
            (progn
              (setf (gethash "container" result) (subseq rest 0 options-start)
                    (gethash "options" result) (subseq rest (1+ options-start))))
            (setf (gethash "container" result) rest
                  (gethash "options" result) ""))
        result))))
