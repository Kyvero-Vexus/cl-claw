;;;; state-migrations.lisp - State directory migration utilities for cl-claw
;;;;
;;;; Handles migration of legacy state directories (e.g. .clawdbot, .moltbot)
;;;; to the canonical ~/.openclaw directory.

(defpackage :cl-claw.infra.state-migrations
  (:use :cl)
  (:export :auto-migrate-legacy-state-dir
           :migration-result
           :migration-result-migrated
           :migration-result-warnings
           :migration-result-source
           :migration-result-target
           :reset-auto-migrate-for-test))
(in-package :cl-claw.infra.state-migrations)

;;; Legacy directory names to check (in priority order)
(defparameter *legacy-dir-names*
  '(".clawdbot" ".moltbot" ".openclaw-legacy")
  "Legacy state directory names to migrate from.")

(defparameter *target-dir-name*
  ".openclaw"
  "Target canonical state directory name.")

(defvar *migration-done* nil
  "Whether migration has already been performed this session.")

(defstruct migration-result
  "Result of an auto-migration attempt."
  (migrated nil :type boolean)
  (warnings nil :type list)
  (source nil :type (or null string))
  (target nil :type (or null string)))

(defun reset-auto-migrate-for-test ()
  "Reset migration state for testing purposes."
  (setf *migration-done* nil))

(defun resolve-real-path (path)
  "Resolve symlinks and return the canonical path, or PATH if resolution fails."
  (handler-case
      (uiop:native-namestring (truename path))
    (error () path)))

(defun directory-p (path)
  "Return T if PATH exists and is a directory."
  (and (uiop:directory-exists-p path) t))

(defun symlink-p (path)
  "Return T if PATH is a symbolic link."
  (handler-case
      (let ((stat (sb-posix:lstat path)))
        (= (logand (sb-posix:stat-mode stat) sb-posix:s-ifmt) sb-posix:s-iflnk))
    (error () nil)))

(defun find-legacy-source (homedir)
  "Find the first existing legacy state directory under HOMEDIR.
If the directory is a symlink, follows it to find the real target.
Returns (values source-path real-path) or NIL."
  (dolist (name *legacy-dir-names*)
    (let ((candidate (uiop:native-namestring
                      (merge-pathnames name (uiop:ensure-directory-pathname homedir)))))
      (when (or (directory-p candidate) (symlink-p candidate))
        (let ((real (resolve-real-path candidate)))
          (return-from find-legacy-source (values candidate real))))))
  nil)

(defun copy-directory-tree (source target)
  "Copy directory tree from SOURCE to TARGET, creating TARGET if needed."
  (uiop:ensure-all-directories-exist (list (uiop:ensure-directory-pathname target)))
  (uiop:run-program (list "cp" "-a" (uiop:native-namestring
                                      (uiop:ensure-directory-pathname source))
                           target)
                    :ignore-error-status t))

(defun auto-migrate-legacy-state-dir (&key env homedir)
  "Migrate legacy state directory to ~/.openclaw if needed.

ENV is the environment plist/alist (checked for OPENCLAW_STATE_DIR override).
HOMEDIR is a function or string giving the home directory (defaults to HOME).

Migration is idempotent: only runs once per session.
Returns a MIGRATION-RESULT struct."
  (when *migration-done*
    (return-from auto-migrate-legacy-state-dir
      (make-migration-result :migrated nil :warnings '())))
  (setf *migration-done* t)
  ;; Check for explicit state dir override
  (let ((state-dir-override
          (cond
            ((functionp env) (funcall env "OPENCLAW_STATE_DIR"))
            ((listp env) (or (cdr (assoc "OPENCLAW_STATE_DIR" env :test #'string=))
                             (getf env "OPENCLAW_STATE_DIR")))
            (t (uiop:getenv "OPENCLAW_STATE_DIR")))))
    (when (and state-dir-override (not (string= state-dir-override "")))
      ;; Explicit state dir, no migration needed
      (return-from auto-migrate-legacy-state-dir
        (make-migration-result :migrated nil :warnings '()))))
  ;; Resolve home directory
  (let* ((home-str (cond
                     ((null homedir) (uiop:getenv "HOME"))
                     ((functionp homedir) (funcall homedir))
                     (t homedir)))
         (target-path (uiop:native-namestring
                       (merge-pathnames *target-dir-name*
                                        (uiop:ensure-directory-pathname home-str)))))
    ;; If target already exists, no migration needed
    (when (directory-p target-path)
      (return-from auto-migrate-legacy-state-dir
        (make-migration-result :migrated nil :warnings '())))
    ;; Find a legacy source directory
    (multiple-value-bind (source-path real-path)
        (find-legacy-source home-str)
      (unless source-path
        (return-from auto-migrate-legacy-state-dir
          (make-migration-result :migrated nil :warnings '())))
      ;; Perform migration: rename real dir to .openclaw
      (let ((warnings '()))
        (handler-case
            (progn
              ;; Copy from real path to target
              (copy-directory-tree real-path target-path)
              (make-migration-result
               :migrated t
               :warnings warnings
               :source source-path
               :target target-path))
          (error (e)
            (push (format nil "Migration failed: ~a" e) warnings)
            (make-migration-result
             :migrated nil
             :warnings warnings
             :source source-path
             :target target-path)))))))
