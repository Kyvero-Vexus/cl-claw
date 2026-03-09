;;;; sandbox.lisp — Agent sandbox: bind specs, workspace isolation, Docker environment
;;;;
;;;; Extends the bind-spec parser with full sandbox configuration: workspace
;;;; directory resolution, environment isolation, Docker volume mount generation,
;;;; and sandbox policy enforcement.

(defpackage :cl-claw.agents.sandbox
  (:use :cl :cl-claw.agents.sandbox.bind-spec)
  (:export
   ;; Re-export from bind-spec
   :split-sandbox-bind-spec
   ;; Sandbox config
   :make-sandbox-config
   :sandbox-config
   :sandbox-config-enabled-p
   :sandbox-config-workspace
   :sandbox-config-docker-image
   :sandbox-config-bind-specs
   :sandbox-config-env-passthrough
   ;; Workspace isolation
   :resolve-sandbox-workspace
   :ensure-sandbox-workspace
   ;; Docker volume generation
   :generate-docker-volumes
   ;; Environment isolation
   :build-isolated-env))

(in-package :cl-claw.agents.sandbox)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Sandbox Config ─────────────────────────────────────────────────────────

(defstruct (sandbox-config (:conc-name sandbox-config-))
  "Configuration for an agent sandbox."
  (enabled-p nil :type boolean)
  (workspace "" :type string)
  (docker-image "" :type string)
  (bind-specs nil :type list)        ; list of bind spec strings
  (env-passthrough nil :type list))  ; list of env var names to pass through

;;; ─── Workspace Isolation ────────────────────────────────────────────────────

(declaim (ftype (function (string string &key (:sandbox-base string)) string)
                resolve-sandbox-workspace))
(defun resolve-sandbox-workspace (agent-id workspace-base &key (sandbox-base ""))
  "Resolve the workspace directory for a sandboxed agent."
  (declare (type string agent-id workspace-base sandbox-base))
  (let ((base (if (string= sandbox-base "")
                  workspace-base
                  sandbox-base)))
    (declare (type string base))
    (namestring
     (merge-pathnames (format nil "sandbox/~A/" agent-id)
                      (uiop:ensure-directory-pathname base)))))

(declaim (ftype (function (string) string) ensure-sandbox-workspace))
(defun ensure-sandbox-workspace (path)
  "Ensure the sandbox workspace directory exists. Returns the path."
  (declare (type string path))
  (ensure-directories-exist (uiop:ensure-directory-pathname path))
  path)

;;; ─── Docker Volume Generation ───────────────────────────────────────────────

(declaim (ftype (function (list string) list) generate-docker-volumes))
(defun generate-docker-volumes (bind-specs workspace)
  "Generate Docker -v volume mount arguments from bind specs.
   Always includes workspace as /workspace."
  (declare (type list bind-specs) (type string workspace))
  (let ((volumes (list (format nil "~A:/workspace" workspace))))
    (declare (type list volumes))
    (dolist (spec bind-specs)
      (when (stringp spec)
        (let ((parsed (split-sandbox-bind-spec spec)))
          (when parsed
            (let ((host (gethash "host" parsed))
                  (container (gethash "container" parsed))
                  (options (gethash "options" parsed)))
              (push (if (and (stringp options) (not (string= options "")))
                        (format nil "~A:~A:~A" host container options)
                        (format nil "~A:~A" host container))
                    volumes))))))
    (nreverse volumes)))

;;; ─── Environment Isolation ──────────────────────────────────────────────────

(declaim (ftype (function (hash-table list &key (:workspace string)) hash-table)
                build-isolated-env))
(defun build-isolated-env (full-env passthrough-keys &key (workspace ""))
  "Build an isolated environment from FULL-ENV, only passing through
   specified keys plus workspace-related variables."
  (declare (type hash-table full-env)
           (type list passthrough-keys)
           (type string workspace))
  (let ((env (make-hash-table :test 'equal)))
    ;; Always set workspace
    (when (not (string= workspace ""))
      (setf (gethash "WORKSPACE" env) workspace
            (gethash "HOME" env) workspace))
    ;; Pass through specified keys
    (dolist (key passthrough-keys)
      (when (stringp key)
        (let ((val (gethash key full-env)))
          (when val
            (setf (gethash key env) val)))))
    ;; Always pass PATH
    (let ((path (gethash "PATH" full-env)))
      (when (stringp path)
        (setf (gethash "PATH" env) path)))
    env))
