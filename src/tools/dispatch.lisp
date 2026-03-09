;;;; dispatch.lisp — Tool dispatch core — registry, validation, permissions
;;;;
;;;; Central tool registry and dispatch engine. Handles tool registration,
;;;; name resolution, argument validation, permission checks, and execution.

(defpackage :cl-claw.tools.dispatch
  (:use :cl)
  (:import-from :cl-claw.tools.types
                :tool-definition
                :make-tool-definition
                :tool-definition-name
                :tool-definition-description
                :tool-definition-handler
                :tool-definition-parameters-schema
                :tool-definition-requires-approval-p
                :tool-definition-category
                :tool-call
                :make-tool-call
                :tool-call-id
                :tool-call-name
                :tool-call-arguments
                :tool-result
                :make-tool-result
                :tool-result-call-id
                :tool-result-content
                :tool-result-error-p
                :approval-decision
                :make-approval-decision
                :approval-decision-approved-p
                :approval-decision-p
                :+permission-allow+
                :+permission-deny+
                :+permission-ask+)
  (:export
   ;; Registry
   :*tool-registry*
   :register-tool
   :unregister-tool
   :get-tool
   :list-tool-names
   :list-tools
   :clear-tool-registry

   ;; Dispatch
   :dispatch-tool-call
   :validate-tool-call

   ;; Permission policy
   :*tool-permission-policy*
   :set-tool-permission
   :get-tool-permission
   :check-tool-permission

   ;; Allowlist
   :*tool-allowlist*
   :set-tool-allowlist
   :tool-allowed-p))

(in-package :cl-claw.tools.dispatch)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Tool registry — global map of name -> tool-definition
;;; -----------------------------------------------------------------------

(defvar *tool-registry* (make-hash-table :test 'equal)
  "Global tool registry: tool-name (string) -> tool-definition.")

(declaim (ftype (function (tool-definition) (values)) register-tool))
(defun register-tool (tool)
  "Register a tool definition in the global registry."
  (declare (type tool-definition tool))
  (let ((name (tool-definition-name tool)))
    (declare (type string name))
    (when (string= "" name)
      (error "Tool name cannot be empty"))
    (setf (gethash name *tool-registry*) tool))
  (values))

(declaim (ftype (function (string) (values)) unregister-tool))
(defun unregister-tool (name)
  "Remove a tool from the registry."
  (declare (type string name))
  (remhash name *tool-registry*)
  (values))

(declaim (ftype (function (string) (or tool-definition null)) get-tool))
(defun get-tool (name)
  "Look up a tool by name. Returns nil if not found."
  (declare (type string name))
  (gethash name *tool-registry*))

(declaim (ftype (function () list) list-tool-names))
(defun list-tool-names ()
  "Return a sorted list of all registered tool names."
  (let ((names '()))
    (maphash (lambda (k v) (declare (ignore v)) (push k names))
             *tool-registry*)
    (sort names #'string<)))

(declaim (ftype (function () list) list-tools))
(defun list-tools ()
  "Return a list of all registered tool definitions."
  (let ((tools '()))
    (maphash (lambda (k v) (declare (ignore k)) (push v tools))
             *tool-registry*)
    (sort tools #'string< :key #'tool-definition-name)))

(defun clear-tool-registry ()
  "Clear all registered tools. Primarily for testing."
  (clrhash *tool-registry*)
  (values))

;;; -----------------------------------------------------------------------
;;; Permission policy
;;; -----------------------------------------------------------------------

(defvar *tool-permission-policy* (make-hash-table :test 'equal)
  "Per-tool permission overrides: tool-name -> :allow | :deny | :ask.")

(declaim (ftype (function (string keyword) (values)) set-tool-permission))
(defun set-tool-permission (tool-name permission)
  "Set the permission level for a specific tool."
  (declare (type string tool-name)
           (type keyword permission))
  (setf (gethash tool-name *tool-permission-policy*) permission)
  (values))

(declaim (ftype (function (string) keyword) get-tool-permission))
(defun get-tool-permission (tool-name)
  "Get the permission level for a tool.
Returns the configured permission or :allow for tools without explicit policy."
  (declare (type string tool-name))
  (let ((tool (get-tool tool-name)))
    (or (gethash tool-name *tool-permission-policy*)
        (if (and tool (tool-definition-requires-approval-p tool))
            +permission-ask+
            +permission-allow+))))

(declaim (ftype (function (string) keyword) check-tool-permission))
(defun check-tool-permission (tool-name)
  "Check whether a tool call is permitted.
Returns :allow, :deny, or :ask."
  (declare (type string tool-name))
  (get-tool-permission tool-name))

;;; -----------------------------------------------------------------------
;;; Allowlist — restrict which tools are available
;;; -----------------------------------------------------------------------

(defvar *tool-allowlist* nil
  "When non-nil, only tools in this list (by name) are available.
When nil, all registered tools are available.")

(defun set-tool-allowlist (names)
  "Set the tool allowlist. Pass nil to allow all tools."
  (setf *tool-allowlist* (when names (mapcar #'string names)))
  (values))

(declaim (ftype (function (string) boolean) tool-allowed-p))
(defun tool-allowed-p (name)
  "Check if a tool is allowed by the current allowlist."
  (declare (type string name))
  (if *tool-allowlist*
      (if (member name *tool-allowlist* :test #'string=) t nil)
      t))

;;; -----------------------------------------------------------------------
;;; Validation
;;; -----------------------------------------------------------------------

(defstruct validation-result
  "Result of validating a tool call."
  (valid-p t :type boolean)
  (error-message nil :type (or string null)))

(declaim (ftype (function (tool-call) validation-result) validate-tool-call))
(defun validate-tool-call (call)
  "Validate a tool call before execution.
Checks: tool exists, tool is allowed, arguments are non-nil."
  (declare (type tool-call call))
  (let ((name (tool-call-name call)))
    (declare (type string name))
    ;; Check tool exists
    (unless (get-tool name)
      (return-from validate-tool-call
        (make-validation-result :valid-p nil
                                :error-message
                                (format nil "Unknown tool: ~A. Available: ~{~A~^, ~}"
                                        name (list-tool-names)))))
    ;; Check allowlist
    (unless (tool-allowed-p name)
      (return-from validate-tool-call
        (make-validation-result :valid-p nil
                                :error-message
                                (format nil "Tool ~A is not in the allowlist" name))))
    ;; Check permission
    (let ((permission (check-tool-permission name)))
      (when (eq permission +permission-deny+)
        (return-from validate-tool-call
          (make-validation-result :valid-p nil
                                  :error-message
                                  (format nil "Tool ~A is denied by policy" name)))))
    (make-validation-result :valid-p t)))

;;; -----------------------------------------------------------------------
;;; Dispatch — execute a tool call
;;; -----------------------------------------------------------------------

(declaim (ftype (function (tool-call &key (:approval-fn (or function null)))
                          tool-result)
                dispatch-tool-call))
(defun dispatch-tool-call (call &key approval-fn)
  "Dispatch and execute a tool call.
1. Validates the call (tool exists, allowed, permitted)
2. Checks approval if tool requires it
3. Executes the tool handler
4. Returns a tool-result

APPROVAL-FN, if provided, is called for tools requiring approval:
  (funcall approval-fn tool-call tool-definition) -> approval-decision"
  (declare (type tool-call call)
           (type (or function null) approval-fn))
  (let ((name (tool-call-name call))
        (call-id (tool-call-id call))
        (args (or (tool-call-arguments call)
                  (make-hash-table :test 'equal))))
    (declare (type string name call-id)
             (type hash-table args))

    ;; 1. Validate
    (let ((validation (validate-tool-call call)))
      (unless (validation-result-valid-p validation)
        (return-from dispatch-tool-call
          (make-tool-result :call-id call-id
                            :content (or (validation-result-error-message validation)
                                         "Tool call validation failed")
                            :error-p t))))

    ;; 2. Get tool
    (let ((tool (get-tool name)))
      (declare (type (or tool-definition null) tool))
      (unless tool
        (return-from dispatch-tool-call
          (make-tool-result :call-id call-id
                            :content (format nil "Tool ~A not found" name)
                            :error-p t)))

      ;; 3. Check approval
      (let ((permission (check-tool-permission name)))
        (when (eq permission +permission-ask+)
          (if approval-fn
              (let ((decision (funcall approval-fn call tool)))
                (unless (and (approval-decision-p decision)
                             (approval-decision-approved-p decision))
                  (return-from dispatch-tool-call
                    (make-tool-result :call-id call-id
                                      :content "Tool call was not approved"
                                      :error-p t))))
              ;; No approval function — deny by default
              (return-from dispatch-tool-call
                (make-tool-result :call-id call-id
                                  :content "Tool requires approval but no approval handler is configured"
                                  :error-p t)))))

      ;; 4. Execute handler
      (let ((handler (tool-definition-handler tool)))
        (unless handler
          (return-from dispatch-tool-call
            (make-tool-result :call-id call-id
                              :content (format nil "Tool ~A has no handler" name)
                              :error-p t)))
        (handler-case
            (let ((result (funcall handler args)))
              (make-tool-result :call-id call-id
                                :content (if (stringp result) result
                                             (format nil "~A" result))
                                :error-p nil))
          (error (e)
            (make-tool-result :call-id call-id
                              :content (format nil "Tool ~A error: ~A" name e)
                              :error-p t)))))))
