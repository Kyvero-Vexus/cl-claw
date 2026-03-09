;;;; types.lisp — Tool system type definitions
;;;;
;;;; Core types for the tool execution framework: tool definitions,
;;;; call/result structures, permissions, and the tool protocol.

(defpackage :cl-claw.tools.types
  (:use :cl)
  (:export
   ;; Tool definition
   :tool-definition
   :make-tool-definition
   :tool-definition-name
   :tool-definition-description
   :tool-definition-handler
   :tool-definition-parameters-schema
   :tool-definition-requires-approval-p
   :tool-definition-category

   ;; Tool call
   :tool-call
   :make-tool-call
   :tool-call-id
   :tool-call-name
   :tool-call-arguments

   ;; Tool result
   :tool-result
   :make-tool-result
   :tool-result-call-id
   :tool-result-content
   :tool-result-error-p
   :tool-result-metadata

   ;; Permission levels
   :+permission-allow+
   :+permission-deny+
   :+permission-ask+

   ;; Tool approval
   :approval-decision
   :approval-decision-p
   :make-approval-decision
   :approval-decision-approved-p
   :approval-decision-reason

   ;; Tool handler signature
   :tool-handler))

(in-package :cl-claw.tools.types)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Permission levels
;;; -----------------------------------------------------------------------

(defconstant +permission-allow+ :allow)
(defconstant +permission-deny+ :deny)
(defconstant +permission-ask+ :ask)

;;; -----------------------------------------------------------------------
;;; Tool definition
;;; -----------------------------------------------------------------------

(defstruct tool-definition
  "Definition of a tool available to agents."
  (name "" :type string)
  (description "" :type string)
  (handler nil :type (or function null))
  (parameters-schema nil :type (or hash-table null))
  (requires-approval-p nil :type boolean)
  (category "core" :type string))

;;; -----------------------------------------------------------------------
;;; Tool call — represents an LLM's request to use a tool
;;; -----------------------------------------------------------------------

(defstruct tool-call
  "A tool invocation request from the LLM."
  (id "" :type string)
  (name "" :type string)
  (arguments nil :type (or hash-table null)))

;;; -----------------------------------------------------------------------
;;; Tool result — the outcome of executing a tool
;;; -----------------------------------------------------------------------

(defstruct tool-result
  "The result of executing a tool call."
  (call-id "" :type string)
  (content "" :type string)
  (error-p nil :type boolean)
  (metadata nil :type (or hash-table null)))

;;; -----------------------------------------------------------------------
;;; Approval decision
;;; -----------------------------------------------------------------------

(defstruct approval-decision
  "An approval decision for a tool call requiring permission."
  (approved-p nil :type boolean)
  (reason nil :type (or string null)))

;;; -----------------------------------------------------------------------
;;; Tool handler type
;;; -----------------------------------------------------------------------

(deftype tool-handler ()
  "A tool handler function: (hash-table) -> string"
  '(function (hash-table) string))
