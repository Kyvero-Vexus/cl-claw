;;;; client.lisp — ACP client spawn environment and invocation resolution
;;;;
;;;; Constructs the environment variables and command invocations for spawning
;;;; ACP client processes. Handles key stripping, OPENCLAW_SHELL marker,
;;;; permission request resolution, and prompt text/attachment extraction.

(defpackage :cl-claw.acp.client
  (:use :cl :cl-claw.acp.types)
  (:export
   :resolve-acp-client-spawn-env
   :resolve-acp-client-spawn-invocation
   :resolve-permission-request
   :extract-text-from-prompt
   :extract-attachments-from-prompt))

(in-package :cl-claw.acp.client)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Spawn Environment ──────────────────────────────────────────────────────

(declaim (ftype (function (hash-table &key (:strip-keys list)) hash-table)
                resolve-acp-client-spawn-env))
(defun resolve-acp-client-spawn-env (base-env &key (strip-keys nil))
  "Build the spawn environment for an ACP client process.
   Sets OPENCLAW_SHELL=acp-client and strips specified keys.
   Does NOT modify BASE-ENV."
  (declare (type hash-table base-env)
           (type list strip-keys))
  (let ((env (make-hash-table :test 'equal)))
    ;; Copy base env
    (maphash (lambda (k v)
               (declare (type string k))
               (setf (gethash k env) v))
             base-env)
    ;; Strip keys (but never OPENCLAW_SHELL itself)
    (dolist (key strip-keys)
      (unless (string= key "OPENCLAW_SHELL")
        (remhash key env)))
    ;; Always set marker
    (setf (gethash "OPENCLAW_SHELL" env) "acp-client")
    env))

;;; ─── Invocation Resolution ──────────────────────────────────────────────────

(defstruct (acp-invocation (:conc-name acp-invocation-))
  "Resolved command invocation for spawning an ACP client."
  (command nil :type list)    ; ("npx" "openclaw" "acp" ...)
  (cwd "" :type string)
  (env nil :type (or hash-table null)))

(declaim (ftype (function (string &key (:cwd string)
                                       (:agent string)
                                       (:session-key string))
                          acp-invocation)
                resolve-acp-client-spawn-invocation))
(defun resolve-acp-client-spawn-invocation (backend &key (cwd "") (agent "") (session-key ""))
  "Resolve the spawn command for a given ACP backend."
  (declare (type string backend cwd agent session-key))
  (let ((cmd (cond
               ((or (string= backend "codex") (string= backend "acpx"))
                (list "codex" "--session" session-key
                      "--agent" agent
                      "--cwd" cwd))
               ((string= backend "claude-code")
                (list "claude" "--session" session-key
                      "--agent" agent
                      "--cwd" cwd))
               (t
                (list backend "--session" session-key
                      "--agent" agent
                      "--cwd" cwd)))))
    (make-acp-invocation :command cmd :cwd cwd)))

;;; ─── Permission Request Resolution ─────────────────────────────────────────

(defstruct (permission-resolution (:conc-name permission-resolution-))
  "Resolved permission request info."
  (tool-call-id "" :type string)
  (title "" :type string)
  (status "pending" :type string)
  (options nil :type list)
  (session-id "" :type string))

(declaim (ftype (function (hash-table) permission-resolution) resolve-permission-request))
(defun resolve-permission-request (request)
  "Extract structured permission request from a raw hash-table."
  (declare (type hash-table request))
  (let* ((session-id (or (gethash "sessionId" request) ""))
         (tool-call (gethash "toolCall" request))
         (options (gethash "options" request)))
    (make-permission-resolution
     :session-id (if (stringp session-id) session-id "")
     :tool-call-id (if (and (hash-table-p tool-call)
                            (stringp (gethash "toolCallId" tool-call)))
                       (gethash "toolCallId" tool-call)
                       "")
     :title (if (and (hash-table-p tool-call)
                     (stringp (gethash "title" tool-call)))
                (gethash "title" tool-call)
                "")
     :status (if (and (hash-table-p tool-call)
                      (stringp (gethash "status" tool-call)))
                 (gethash "status" tool-call)
                 "pending")
     :options (if (listp options) options nil))))

;;; ─── Prompt Text/Attachment Extraction ──────────────────────────────────────

(declaim (ftype (function (list) string) extract-text-from-prompt))
(defun extract-text-from-prompt (prompt-parts)
  "Extract concatenated text from prompt parts list.
   Each part is a hash-table with 'type' and 'text' keys."
  (declare (type list prompt-parts))
  (with-output-to-string (out)
    (let ((first t))
      (dolist (part prompt-parts)
        (when (and (hash-table-p part)
                   (string= (or (gethash "type" part) "") "text"))
          (let ((text (gethash "text" part)))
            (when (stringp text)
              (unless first (write-char #\Newline out))
              (write-string text out)
              (setf first nil))))))))

(declaim (ftype (function (list) list) extract-attachments-from-prompt))
(defun extract-attachments-from-prompt (prompt-parts)
  "Extract attachment entries from prompt parts (non-text parts)."
  (declare (type list prompt-parts))
  (loop for part in prompt-parts
        when (and (hash-table-p part)
                  (not (string= (or (gethash "type" part) "text") "text")))
          collect part))
