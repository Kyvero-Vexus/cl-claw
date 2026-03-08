;;;; kill-tree.lisp — Cross-platform process tree termination
;;;;
;;;; Implements KILL-PROCESS-TREE which sends SIGTERM (Unix) or taskkill (Windows)
;;;; and optionally force-kills after a grace period.

(defpackage :cl-claw.process.kill-tree
  (:use :cl)
  (:export :kill-process-tree))

(in-package :cl-claw.process.kill-tree)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (integer) boolean) pid-exists-p))
(defun pid-exists-p (pid)
  "Return T if PID is alive (signal 0 does not raise)."
  (declare (type integer pid))
  (handler-case
      (progn
        #+sbcl (sb-posix:kill pid 0)
        #-sbcl (uiop:run-program (list "kill" "-0" (format nil "~d" pid)))
        t)
    (error () nil)))

(declaim (ftype (function (integer &key (:grace-ms fixnum)
                                        (:platform (or string null)))
                          t)
                kill-process-tree))
(defun kill-process-tree (pid &key (grace-ms 5000) platform)
  "Kill the process tree rooted at PID.

On Windows: uses taskkill /T /PID, then after GRACE-MS ms force-kills with /F if needed.
On Unix: sends SIGTERM to process group (-PID), then SIGKILL after GRACE-MS if still alive.
PLATFORM defaults to the current platform string."
  (declare (type integer pid)
           (type fixnum grace-ms)
           (type (or string null) platform))
  (let ((p (or platform
               #+win32 "win32"
               #-win32 "unix")))
    (declare (type string p))
    (cond
      ((string= p "win32")
       ;; Windows: taskkill /T /PID <pid>
       (uiop:launch-program
        (list "taskkill" "/T" "/PID" (format nil "~d" pid))
        :ignore-error-status t)
       ;; After grace period, force-kill if still alive
       (bt:make-thread
        (lambda ()
          (sleep (/ grace-ms 1000.0))
          (when (pid-exists-p pid)
            (uiop:launch-program
             (list "taskkill" "/F" "/T" "/PID" (format nil "~d" pid))
             :ignore-error-status t)))
        :name "kill-tree-grace-windows"))

      (t
       ;; Unix: kill process group with SIGTERM
       (let ((pgid (- pid)))
         (declare (type integer pgid))
         (handler-case
             #+sbcl (sb-posix:kill pgid sb-posix:sigterm)
             #-sbcl (uiop:run-program (list "kill" "-TERM" (format nil "~d" pgid))
                                      :ignore-error-status t)
           (error ()))
         ;; After grace period, check if still alive and SIGKILL
         (bt:make-thread
          (lambda ()
            (sleep (/ grace-ms 1000.0))
            (when (pid-exists-p pgid)
              (handler-case
                  #+sbcl (sb-posix:kill pgid sb-posix:sigkill)
                  #-sbcl (uiop:run-program (list "kill" "-KILL" (format nil "~d" pgid))
                                           :ignore-error-status t)
                (error ()))))
          :name "kill-tree-grace-unix"))))))
