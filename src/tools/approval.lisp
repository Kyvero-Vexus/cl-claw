;;;; approval.lisp — Tool approval/permission system
;;;;
;;;; Manages tool execution approval policies, including per-tool
;;;; permission overrides, security mode (deny/allowlist/full),
;;;; and approval callback infrastructure.

(defpackage :cl-claw.tools.approval
  (:use :cl)
  (:import-from :cl-claw.tools.types
                :tool-call
                :tool-call-name
                :tool-definition
                :tool-definition-name
                :tool-definition-requires-approval-p
                :approval-decision
                :make-approval-decision
                :approval-decision-approved-p
                :+permission-allow+
                :+permission-deny+
                :+permission-ask+)
  (:import-from :cl-claw.tools.dispatch
                :*tool-permission-policy*
                :set-tool-permission
                :get-tool-permission)
  (:export
   ;; Security modes
   :+security-deny+
   :+security-allowlist+
   :+security-full+

   ;; Approval system
   :*security-mode*
   :*approval-callback*
   :set-security-mode
   :set-approval-callback
   :request-approval
   :auto-approve

   ;; Policy management
   :apply-security-policy
   :reset-security-policy

   ;; Batch operations
   :allow-tools
   :deny-tools
   :require-approval-for-tools))

(in-package :cl-claw.tools.approval)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Security modes
;;; -----------------------------------------------------------------------

(defconstant +security-deny+ :deny
  "Deny all tools by default.")
(defconstant +security-allowlist+ :allowlist
  "Only allow explicitly listed tools.")
(defconstant +security-full+ :full
  "Allow all tools by default.")

;;; -----------------------------------------------------------------------
;;; Global state
;;; -----------------------------------------------------------------------

(defvar *security-mode* +security-full+
  "Current security mode for tool execution.")

(defvar *approval-callback* nil
  "Callback function for tool approval requests.
Signature: (tool-call tool-definition) -> approval-decision
When nil, tools requiring approval are denied.")

;;; -----------------------------------------------------------------------
;;; Configuration
;;; -----------------------------------------------------------------------

(defun set-security-mode (mode)
  "Set the global security mode."
  (declare (type keyword mode))
  (unless (member mode (list +security-deny+ +security-allowlist+ +security-full+))
    (error "Invalid security mode: ~A. Must be :deny, :allowlist, or :full" mode))
  (setf *security-mode* mode)
  (values))

(defun set-approval-callback (callback)
  "Set the approval callback function.
CALLBACK: (tool-call tool-definition) -> approval-decision, or nil to disable."
  (declare (type (or function null) callback))
  (setf *approval-callback* callback)
  (values))

;;; -----------------------------------------------------------------------
;;; Approval request handling
;;; -----------------------------------------------------------------------

(declaim (ftype (function (tool-call tool-definition) approval-decision)
                request-approval))
(defun request-approval (call tool)
  "Request approval for a tool call.
Uses *approval-callback* if set, otherwise denies."
  (declare (type tool-call call)
           (type tool-definition tool))
  (if *approval-callback*
      (funcall *approval-callback* call tool)
      (make-approval-decision :approved-p nil
                              :reason "No approval handler configured")))

(declaim (ftype (function (tool-call tool-definition) approval-decision)
                auto-approve))
(defun auto-approve (call tool)
  "An approval function that auto-approves everything."
  (declare (ignore call tool))
  (make-approval-decision :approved-p t :reason "auto-approved"))

;;; -----------------------------------------------------------------------
;;; Policy management
;;; -----------------------------------------------------------------------

(defun apply-security-policy (tool-names)
  "Apply the current security mode to a list of tool names.
In :deny mode: deny all tools
In :allowlist mode: only allow listed tools (requires explicit allow)
In :full mode: allow all tools"
  (declare (type list tool-names))
  (ecase *security-mode*
    (:deny
     (dolist (name tool-names)
       (set-tool-permission name +permission-deny+)))
    (:allowlist
     ;; Don't modify — rely on the allowlist mechanism in dispatch
     (values))
    (:full
     (dolist (name tool-names)
       (set-tool-permission name +permission-allow+))))
  (values))

(defun reset-security-policy ()
  "Reset all tool permissions to defaults."
  (clrhash *tool-permission-policy*)
  (setf *security-mode* +security-full+)
  (setf *approval-callback* nil)
  (values))

;;; -----------------------------------------------------------------------
;;; Batch operations
;;; -----------------------------------------------------------------------

(defun allow-tools (&rest names)
  "Explicitly allow the named tools."
  (dolist (name names)
    (set-tool-permission name +permission-allow+))
  (values))

(defun deny-tools (&rest names)
  "Explicitly deny the named tools."
  (dolist (name names)
    (set-tool-permission name +permission-deny+))
  (values))

(defun require-approval-for-tools (&rest names)
  "Set the named tools to require approval."
  (dolist (name names)
    (set-tool-permission name +permission-ask+))
  (values))
