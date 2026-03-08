;;;; safe-bin.lisp — Safe binary execution policy
;;;;
;;;; Implements checks for whether a command/binary is on the approved safe-list
;;;; before execution, preventing execution of unauthorized programs.

(defpackage :cl-claw.security.safe-bin
  (:use :cl)
  (:export
   :safe-bin-check
   :safe-bin-result
   :safe-bin-result-allowed-p
   :safe-bin-result-reason
   :make-safe-bin-policy
   :safe-bin-policy
   :is-safe-binary-p
   :add-allowed-binary
   :remove-allowed-binary))

(in-package :cl-claw.security.safe-bin)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Safe binary policy ──────────────────────────────────────────────────────

(defstruct (safe-bin-policy (:constructor %make-safe-bin-policy))
  "A policy governing which binaries may be executed."
  (lock          (bt:make-lock "safe-bin-lock") :type t)
  (allowed-names (make-hash-table :test 'equal) :type hash-table)
  (mode          :allowlist :type keyword))  ; :allowlist or :denylist or :open

(declaim (ftype (function (&key (:allowed-names list)
                                (:mode keyword))
                          safe-bin-policy)
                make-safe-bin-policy))
(defun make-safe-bin-policy (&key allowed-names (mode :allowlist))
  "Create a safe binary policy.

ALLOWED-NAMES: list of allowed binary names (for :allowlist mode)
MODE:
  :allowlist — only listed binaries are allowed (default)
  :denylist  — listed binaries are blocked, others allowed
  :open      — all binaries allowed (development mode)"
  (declare (type list allowed-names)
           (type keyword mode))
  (let ((ht (make-hash-table :test 'equal)))
    (declare (type hash-table ht))
    (dolist (name allowed-names)
      (declare (type string name))
      (setf (gethash name ht) t))
    (%make-safe-bin-policy :allowed-names ht :mode mode)))

;;; ─── Safe bin check result ───────────────────────────────────────────────────

(defstruct safe-bin-result
  "Result of checking a binary against the safe-bin policy."
  (allowed-p nil :type boolean)
  (reason    ""  :type string))

;;; ─── Helpers ─────────────────────────────────────────────────────────────────

(declaim (ftype (function (string) string) basename))
(defun basename (path)
  "Return the basename of a PATH (last component after last slash)."
  (declare (type string path))
  (let ((slash-pos (or (position #\/ path :from-end t)
                       (position #\\ path :from-end t))))
    (declare (type (or fixnum null) slash-pos))
    (if slash-pos
        (subseq path (1+ slash-pos))
        path)))

;;; ─── Policy checks ───────────────────────────────────────────────────────────

(declaim (ftype (function (safe-bin-policy string) boolean) is-safe-binary-p))
(defun is-safe-binary-p (policy binary-name)
  "Return T if BINARY-NAME is allowed by POLICY."
  (declare (type safe-bin-policy policy)
           (type string binary-name))
  (let ((base (basename binary-name))
        (mode (safe-bin-policy-mode policy)))
    (declare (type string base)
             (type keyword mode))
    (bt:with-lock-held ((safe-bin-policy-lock policy))
      (case mode
        (:open      t)
        (:allowlist (gethash base (safe-bin-policy-allowed-names policy)))
        (:denylist  (not (gethash base (safe-bin-policy-allowed-names policy))))
        (t          nil)))))

(declaim (ftype (function (safe-bin-policy string) safe-bin-result) safe-bin-check))
(defun safe-bin-check (policy binary-path)
  "Check BINARY-PATH against POLICY. Returns SAFE-BIN-RESULT."
  (declare (type safe-bin-policy policy)
           (type string binary-path))
  (if (is-safe-binary-p policy binary-path)
      (make-safe-bin-result :allowed-p t :reason "")
      (make-safe-bin-result
       :allowed-p nil
       :reason (format nil "Binary '~a' is not on the allowed list"
                        (basename binary-path)))))

(declaim (ftype (function (safe-bin-policy string) t) add-allowed-binary))
(defun add-allowed-binary (policy name)
  "Add NAME to the policy's allowlist."
  (declare (type safe-bin-policy policy)
           (type string name))
  (bt:with-lock-held ((safe-bin-policy-lock policy))
    (setf (gethash name (safe-bin-policy-allowed-names policy)) t)))

(declaim (ftype (function (safe-bin-policy string) t) remove-allowed-binary))
(defun remove-allowed-binary (policy name)
  "Remove NAME from the policy's allowlist."
  (declare (type safe-bin-policy policy)
           (type string name))
  (bt:with-lock-held ((safe-bin-policy-lock policy))
    (remhash name (safe-bin-policy-allowed-names policy))))
