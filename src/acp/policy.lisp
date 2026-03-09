;;;; policy.lisp — ACP enable/disable policy, allowlist filtering
;;;;
;;;; Evaluates configuration to determine whether ACP and dispatch are enabled,
;;;; which agents are allowed, and produces structured policy error/state info.

(defpackage :cl-claw.acp.policy
  (:use :cl :cl-claw.acp.types)
  (:export
   :acp-enabled-by-policy-p
   :acp-dispatch-enabled-by-policy-p
   :acp-agent-allowed-by-policy-p
   :resolve-acp-dispatch-policy-state
   :resolve-acp-dispatch-policy-message
   :resolve-acp-dispatch-policy-error
   :resolve-acp-agent-policy-error))

(in-package :cl-claw.acp.policy)

(declaim (optimize (safety 3) (debug 3)))

;;; ─── Helpers ────────────────────────────────────────────────────────────────

(declaim (ftype (function (hash-table string) t) %cfg-get))
(defun %cfg-get (cfg key)
  "Get a value from config hash-table. Returns NIL if missing."
  (declare (type hash-table cfg) (type string key))
  (gethash key cfg))

(declaim (ftype (function (hash-table) (or hash-table null)) %acp-section))
(defun %acp-section (cfg)
  "Extract the 'acp' section from config."
  (declare (type hash-table cfg))
  (let ((acp (%cfg-get cfg "acp")))
    (if (hash-table-p acp) acp nil)))

(declaim (ftype (function (hash-table) (or hash-table null)) %dispatch-section))
(defun %dispatch-section (cfg)
  "Extract the 'dispatch' subsection from the acp config."
  (declare (type hash-table cfg))
  (let ((acp (%acp-section cfg)))
    (when acp
      (let ((dispatch (%cfg-get acp "dispatch")))
        (if (hash-table-p dispatch) dispatch nil)))))

;;; ─── Policy predicates ─────────────────────────────────────────────────────

(declaim (ftype (function (hash-table) boolean) acp-enabled-by-policy-p))
(defun acp-enabled-by-policy-p (cfg)
  "Returns T if ACP is enabled (default: T when unset)."
  (declare (type hash-table cfg))
  (let ((acp (%acp-section cfg)))
    (if acp
        (multiple-value-bind (val present-p) (gethash "enabled" acp)
          (if present-p
              (not (not val))
              t))  ; default enabled when key absent
        t)))

(declaim (ftype (function (hash-table) boolean) acp-dispatch-enabled-by-policy-p))
(defun acp-dispatch-enabled-by-policy-p (cfg)
  "Returns T if ACP dispatch is enabled (default: T when unset)."
  (declare (type hash-table cfg))
  (if (not (acp-enabled-by-policy-p cfg))
      nil
      (let ((dispatch (%dispatch-section cfg)))
        (if dispatch
            (multiple-value-bind (val present-p) (gethash "enabled" dispatch)
              (if present-p
                  (not (not val))
                  t))
            t))))

(declaim (ftype (function (hash-table string) boolean) acp-agent-allowed-by-policy-p))
(defun acp-agent-allowed-by-policy-p (cfg agent-id)
  "Returns T if the given agent ID is allowed by the ACP allowlist.
   When no allowlist is configured, all agents are allowed."
  (declare (type hash-table cfg) (type string agent-id))
  (let ((acp (%acp-section cfg)))
    (if (null acp)
        t
        (let ((allowed (%cfg-get acp "allowedAgents")))
          (if (or (null allowed) (not (listp allowed)))
              t  ; no allowlist = all allowed
              (let ((downcased (string-downcase agent-id)))
                (declare (type string downcased))
                (loop for entry in allowed
                      thereis (and (stringp entry)
                                   (string= (string-downcase entry) downcased)))))))))

;;; ─── Policy state resolution ───────────────────────────────────────────────

(declaim (ftype (function (hash-table) string) resolve-acp-dispatch-policy-state))
(defun resolve-acp-dispatch-policy-state (cfg)
  "Returns the dispatch policy state string."
  (declare (type hash-table cfg))
  (cond
    ((not (acp-enabled-by-policy-p cfg))
     +acp-dispatch-state-acp-disabled+)
    ((not (acp-dispatch-enabled-by-policy-p cfg))
     +acp-dispatch-state-dispatch-disabled+)
    (t
     +acp-dispatch-state-enabled+)))

(declaim (ftype (function (hash-table) (or string null)) resolve-acp-dispatch-policy-message))
(defun resolve-acp-dispatch-policy-message (cfg)
  "Returns a human-readable policy message or NIL when enabled."
  (declare (type hash-table cfg))
  (let ((state (resolve-acp-dispatch-policy-state cfg)))
    (cond
      ((string= state +acp-dispatch-state-acp-disabled+)
       "ACP dispatch disabled: acp.enabled=false in config")
      ((string= state +acp-dispatch-state-dispatch-disabled+)
       "ACP dispatch disabled: acp.dispatch.enabled=false in config")
      (t nil))))

(declaim (ftype (function (hash-table) (or hash-table null)) resolve-acp-dispatch-policy-error))
(defun resolve-acp-dispatch-policy-error (cfg)
  "Returns an error descriptor hash-table or NIL when dispatch is enabled."
  (declare (type hash-table cfg))
  (let ((msg (resolve-acp-dispatch-policy-message cfg)))
    (when msg
      (let ((ht (make-hash-table :test 'equal)))
        (setf (gethash "code" ht) "ACP_DISPATCH_DISABLED"
              (gethash "message" ht) msg)
        ht))))

(declaim (ftype (function (hash-table string) (or hash-table null)) resolve-acp-agent-policy-error))
(defun resolve-acp-agent-policy-error (cfg agent-id)
  "Returns an error descriptor for a disallowed agent, or NIL if allowed."
  (declare (type hash-table cfg) (type string agent-id))
  (if (acp-agent-allowed-by-policy-p cfg agent-id)
      nil
      (let ((ht (make-hash-table :test 'equal)))
        (setf (gethash "code" ht) "ACP_SESSION_INIT_FAILED"
              (gethash "message" ht)
              (format nil "Agent '~A' is not in the ACP allowed agents list" agent-id))
        ht)))
