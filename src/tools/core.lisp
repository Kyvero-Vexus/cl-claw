;;;; core.lisp — Tool execution framework — unified API
;;;;
;;;; Top-level package that re-exports the tool subsystem and provides
;;;; initialization/registration of all built-in tools.

(defpackage :cl-claw.tools
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
                :tool-result-metadata
                :approval-decision
                :make-approval-decision
                :approval-decision-approved-p
                :approval-decision-reason
                :+permission-allow+
                :+permission-deny+
                :+permission-ask+)
  (:import-from :cl-claw.tools.dispatch
                :*tool-registry*
                :register-tool
                :unregister-tool
                :get-tool
                :list-tool-names
                :list-tools
                :clear-tool-registry
                :dispatch-tool-call
                :validate-tool-call
                :*tool-permission-policy*
                :set-tool-permission
                :get-tool-permission
                :check-tool-permission
                :*tool-allowlist*
                :set-tool-allowlist
                :tool-allowed-p)
  (:import-from :cl-claw.tools.file-ops
                :handle-read-tool
                :handle-write-tool
                :handle-edit-tool
                :register-file-tools)
  (:import-from :cl-claw.tools.exec-tool
                :handle-exec-tool
                :handle-process-tool
                :register-exec-tools)
  (:import-from :cl-claw.tools.web
                :handle-web-fetch
                :handle-web-search
                :register-web-tools)
  (:import-from :cl-claw.tools.browser
                :handle-browser-tool
                :register-browser-tool)
  (:import-from :cl-claw.tools.approval
                :*security-mode*
                :*approval-callback*
                :set-security-mode
                :set-approval-callback
                :request-approval
                :auto-approve
                :apply-security-policy
                :reset-security-policy
                :allow-tools
                :deny-tools
                :require-approval-for-tools
                :+security-deny+
                :+security-allowlist+
                :+security-full+)
  (:export
   ;; Types
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
   :tool-result-metadata
   :approval-decision
   :make-approval-decision
   :approval-decision-approved-p
   :approval-decision-reason
   :+permission-allow+
   :+permission-deny+
   :+permission-ask+

   ;; Registry
   :register-tool
   :unregister-tool
   :get-tool
   :list-tool-names
   :list-tools
   :clear-tool-registry
   :dispatch-tool-call
   :validate-tool-call

   ;; Permissions
   :set-tool-permission
   :get-tool-permission
   :check-tool-permission
   :*tool-allowlist*
   :set-tool-allowlist
   :tool-allowed-p

   ;; Approval
   :*security-mode*
   :*approval-callback*
   :set-security-mode
   :set-approval-callback
   :request-approval
   :auto-approve
   :apply-security-policy
   :reset-security-policy
   :allow-tools
   :deny-tools
   :require-approval-for-tools
   :+security-deny+
   :+security-allowlist+
   :+security-full+

   ;; Built-in tool handlers
   :handle-read-tool
   :handle-write-tool
   :handle-edit-tool
   :handle-exec-tool
   :handle-process-tool
   :handle-web-fetch
   :handle-web-search
   :handle-browser-tool

   ;; Initialization
   :register-all-tools
   :initialize-tool-system))

(in-package :cl-claw.tools)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Initialization
;;; -----------------------------------------------------------------------

(defun register-all-tools ()
  "Register all built-in tools in the global registry."
  (register-file-tools)
  (register-exec-tools)
  (register-web-tools)
  (register-browser-tool)
  (values))

(defun initialize-tool-system (&key (security-mode +security-full+)
                                     (register-builtins t))
  "Initialize the complete tool execution framework.
Sets up the registry, registers built-in tools, and configures security."
  (declare (type keyword security-mode)
           (type boolean register-builtins))
  (clear-tool-registry)
  (reset-security-policy)
  (set-tool-allowlist nil)
  (set-security-mode security-mode)
  (when register-builtins
    (register-all-tools))
  (values))
