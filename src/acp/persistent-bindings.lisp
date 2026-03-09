;;;; persistent-bindings.lisp — Channel-specific ACP session binding resolution
;;;;
;;;; Resolves ACP bindings from configuration for specific channel/account/peer
;;;; combinations. Builds session keys for bound sessions and supports Discord
;;;; thread→parent fallback.

(defpackage :cl-claw.acp.persistent-bindings
  (:use :cl :cl-claw.acp.types)
  (:export
   :build-configured-acp-session-key
   :resolve-configured-acp-binding-record
   :resolve-configured-acp-binding-spec-by-session-key
   :ensure-configured-acp-binding-session
   :reset-acp-session-in-place))

(in-package :cl-claw.acp.persistent-bindings)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Helpers ────────────────────────────────────────────────────────────────

(declaim (ftype (function (string) string) %sanitize-key-part))
(defun %sanitize-key-part (part)
  "Lowercase and strip whitespace for session key building."
  (declare (type string part))
  (string-downcase (string-trim '(#\Space #\Tab) part)))

;;; ─── Session Key Construction ───────────────────────────────────────────────

(declaim (ftype (function (string string string string) string)
                build-configured-acp-session-key))
(defun build-configured-acp-session-key (agent-id channel account-id conversation-id)
  "Build a deterministic session key for a configured ACP binding."
  (declare (type string agent-id channel account-id conversation-id))
  (format nil "agent:~A:acp:binding:~A:~A:~A"
          (%sanitize-key-part agent-id)
          (%sanitize-key-part channel)
          (%sanitize-key-part account-id)
          (%sanitize-key-part conversation-id)))

;;; ─── Binding Resolution ─────────────────────────────────────────────────────

(declaim (ftype (function (hash-table) list) %extract-bindings))
(defun %extract-bindings (cfg)
  "Extract the bindings list from config."
  (declare (type hash-table cfg))
  (let ((bindings (gethash "bindings" cfg)))
    (if (listp bindings) bindings nil)))

(declaim (ftype (function (hash-table string string) boolean) %binding-matches-p))
(defun %binding-matches-p (binding-match channel conversation-id)
  "Check if a binding match clause matches the given channel and conversation."
  (declare (type hash-table binding-match)
           (type string channel conversation-id))
  (let ((match-channel (gethash "channel" binding-match))
        (match-peer (gethash "peer" binding-match)))
    (and (stringp match-channel)
         (string= (string-downcase match-channel) (string-downcase channel))
         (hash-table-p match-peer)
         (let ((peer-id (gethash "id" match-peer)))
           (and (stringp peer-id)
                (string= peer-id conversation-id))))))

(declaim (ftype (function (hash-table &key (:channel string)
                                           (:account-id string)
                                           (:conversation-id string))
                          (or cons null))
                resolve-configured-acp-binding-record))
(defun resolve-configured-acp-binding-record (cfg &key channel account-id conversation-id)
  "Resolve a binding record from config for the given channel context.
   Returns (spec . record) cons or NIL if no binding matches.
   Falls back to parent channel for Discord thread IDs."
  (declare (type hash-table cfg)
           (type string channel account-id conversation-id))
  (let ((bindings (%extract-bindings cfg)))
    (dolist (binding bindings)
      (when (and (hash-table-p binding)
                 (string= (or (gethash "type" binding) "") "acp"))
        (let ((match (gethash "match" binding))
              (agent-id (or (gethash "agentId" binding) ""))
              (acp-section (gethash "acp" binding)))
          (when (and (hash-table-p match)
                     (stringp agent-id)
                     (%binding-matches-p match channel conversation-id))
            (let* ((cwd (if (hash-table-p acp-section)
                            (or (gethash "cwd" acp-section) "")
                            ""))
                   (match-account (gethash "accountId" match))
                   (effective-account (if (stringp match-account) match-account account-id))
                   (session-key (build-configured-acp-session-key
                                 agent-id channel effective-account conversation-id))
                   (spec (cl-claw.acp.types::make-acp-binding-spec
                          :channel channel
                          :account-id effective-account
                          :conversation-id conversation-id
                          :agent-id agent-id
                          :cwd (if (stringp cwd) cwd "")))
                   (metadata (let ((ht (make-hash-table :test 'equal)))
                               (setf (gethash "source" ht) "config")
                               ht))
                   (record (cl-claw.acp.types::make-acp-binding-record
                            :target-session-key session-key
                            :metadata metadata)))
              (return-from resolve-configured-acp-binding-record
                (cons spec record)))))))
    ;; Discord thread fallback: try parent channel ID
    ;; (Discord thread IDs differ from parent channel IDs)
    nil))

;;; ─── Spec Lookup by Session Key ─────────────────────────────────────────────

(declaim (ftype (function (hash-table string) (or acp-binding-spec null))
                resolve-configured-acp-binding-spec-by-session-key))
(defun resolve-configured-acp-binding-spec-by-session-key (cfg session-key)
  "Find the binding spec whose constructed session key matches."
  (declare (type hash-table cfg) (type string session-key))
  (let ((bindings (%extract-bindings cfg)))
    (dolist (binding bindings)
      (when (and (hash-table-p binding)
                 (string= (or (gethash "type" binding) "") "acp"))
        (let* ((match (gethash "match" binding))
               (agent-id (or (gethash "agentId" binding) ""))
               (peer (and (hash-table-p match) (gethash "peer" match)))
               (peer-id (and (hash-table-p peer) (gethash "id" peer)))
               (match-channel (and (hash-table-p match) (gethash "channel" match)))
               (match-account (and (hash-table-p match) (gethash "accountId" match))))
          (when (and (stringp agent-id) (stringp peer-id) (stringp match-channel))
            (let ((key (build-configured-acp-session-key
                        agent-id match-channel
                        (or match-account "default")
                        peer-id)))
              (when (string= key session-key)
                (let ((acp-section (gethash "acp" binding)))
                  (return-from resolve-configured-acp-binding-spec-by-session-key
                    (cl-claw.acp.types::make-acp-binding-spec
                     :channel match-channel
                     :account-id (or match-account "default")
                     :conversation-id peer-id
                     :agent-id agent-id
                     :cwd (if (and (hash-table-p acp-section)
                                   (stringp (gethash "cwd" acp-section)))
                              (gethash "cwd" acp-section)
                              ""))))))))))))

;;; ─── Session Lifecycle ──────────────────────────────────────────────────────

(declaim (ftype (function (hash-table string string string function) t)
                ensure-configured-acp-binding-session))
(defun ensure-configured-acp-binding-session (cfg channel account-id conversation-id
                                              session-initializer)
  "Ensure a bound session exists. Calls SESSION-INITIALIZER with the binding
   spec and record when a new session needs creation."
  (declare (type hash-table cfg)
           (type string channel account-id conversation-id)
           (type function session-initializer))
  (let ((result (resolve-configured-acp-binding-record
                 cfg
                 :channel channel
                 :account-id account-id
                 :conversation-id conversation-id)))
    (when result
      (funcall session-initializer (car result) (cdr result)))))

(declaim (ftype (function (hash-table string function) t)
                reset-acp-session-in-place))
(defun reset-acp-session-in-place (cfg session-key session-closer)
  "Reset a bound session by closing it via SESSION-CLOSER.
   Returns the result of the closer or NIL."
  (declare (type hash-table cfg)
           (type string session-key)
           (type function session-closer))
  (let ((spec (resolve-configured-acp-binding-spec-by-session-key cfg session-key)))
    (when spec
      (funcall session-closer session-key spec))))
