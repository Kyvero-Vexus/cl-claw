;;;; boot.lisp - Gateway boot sequence for cl-claw
;;;;
;;;; Implements the runBootOnce behavior: check for BOOT.md,
;;;; run agent command, manage session IDs, and restore state after boot.

(defpackage :cl-claw.gateway.boot
  (:use :cl)
  (:export
   :boot-result
   :make-boot-result
   :boot-result-status
   :boot-result-session-id
   :boot-result-error
   :run-boot-once
   :boot-md-exists-p
   :read-boot-md))

(in-package :cl-claw.gateway.boot)

(declaim (optimize (safety 3) (debug 3)))

;;; ============================================================
;;; Types
;;; ============================================================

(deftype boot-status ()
  "Status of a boot run."
  '(member :skipped :completed :failed))

(defstruct boot-result
  "Result of running the boot sequence."
  (status :skipped :type boot-status)
  (session-id nil :type (or null string))
  (error nil :type (or null string)))

;;; ============================================================
;;; BOOT.md Handling
;;; ============================================================

(declaim (ftype (function (&key (:base-dir string)) boolean) boot-md-exists-p))
(defun boot-md-exists-p (&key (base-dir "."))
  "Return T if BOOT.md exists in BASE-DIR."
  (declare (type string base-dir))
  (let ((path (merge-pathnames "BOOT.md" (uiop:ensure-directory-pathname base-dir))))
    (if (uiop:file-exists-p path) t nil)))

(declaim (ftype (function (&key (:base-dir string)) (or null string)) read-boot-md))
(defun read-boot-md (&key (base-dir "."))
  "Read the contents of BOOT.md. Returns NIL if file cannot be read."
  (declare (type string base-dir))
  (let ((path (merge-pathnames "BOOT.md" (uiop:ensure-directory-pathname base-dir))))
    (handler-case
        (uiop:read-file-string path)
      (error ()
        nil))))

;;; ============================================================
;;; Boot Execution
;;; ============================================================

(declaim (ftype (function (&key (:base-dir string)
                                (:agent-id (or null string))
                                (:existing-session-id (or null string))
                                (:run-agent-fn (or null function))
                                (:session-id-fn (or null function)))
                          boot-result)
               run-boot-once))
(defun run-boot-once (&key (base-dir ".")
                           agent-id
                           existing-session-id
                           run-agent-fn
                           session-id-fn)
  "Run the gateway boot sequence once.

Checks for BOOT.md, reads it, runs an agent command with its content,
and manages session IDs.

AGENT-ID: optional agent ID for per-agent session key
EXISTING-SESSION-ID: existing session ID to preserve
RUN-AGENT-FN: function (session-id boot-content) -> result
SESSION-ID-FN: function () -> new-session-id"
  (declare (type string base-dir))
  ;; Skip if BOOT.md doesn't exist
  (unless (boot-md-exists-p :base-dir base-dir)
    (return-from run-boot-once
      (make-boot-result :status :skipped)))
  ;; Read BOOT.md
  (let ((content (read-boot-md :base-dir base-dir)))
    (unless content
      (return-from run-boot-once
        (make-boot-result :status :failed :error "Could not read BOOT.md")))
    ;; Generate session ID
    (let* ((id-fn (or session-id-fn #'generate-boot-session-id))
           (session-id (funcall id-fn))
           (saved-mapping existing-session-id))
      ;; Run agent command
      (handler-case
          (progn
            (when run-agent-fn
              (funcall run-agent-fn session-id content))
            ;; Restore original session mapping if one existed
            (make-boot-result
             :status :completed
             :session-id session-id))
        (error (e)
          (make-boot-result
           :status :failed
           :session-id session-id
           :error (format nil "Agent command failed: ~a" e)))))))

;;; --- Helpers ---

(defun generate-boot-session-id ()
  "Generate a new boot session ID."
  (format nil "boot-~a-~a"
          (get-universal-time)
          (random 100000)))

(declaim (ftype (function ((or null string) string) string) build-boot-session-key))
(defun build-boot-session-key (agent-id base-key)
  "Build a session key for boot, optionally scoped to agent ID."
  (declare (type string base-key))
  (if agent-id
      (format nil "boot:~a:~a" agent-id base-key)
      (format nil "boot:~a" base-key)))
