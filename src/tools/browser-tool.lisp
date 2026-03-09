;;;; browser-tool.lisp — Browser tool — CDP integration stub
;;;;
;;;; Provides the browser tool definition and handler stub.
;;;; Full CDP (Chrome DevTools Protocol) integration is a separate
;;;; subsystem; this module provides the tool registry entry and
;;;; basic action dispatch.

(defpackage :cl-claw.tools.browser
  (:use :cl)
  (:import-from :cl-claw.tools.types
                :tool-definition
                :make-tool-definition)
  (:import-from :cl-claw.tools.dispatch
                :register-tool)
  (:export
   :handle-browser-tool
   :register-browser-tool

   ;; Browser actions
   :+browser-actions+))

(in-package :cl-claw.tools.browser)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Supported actions
;;; -----------------------------------------------------------------------

(defparameter +browser-actions+
  '("status" "start" "stop" "profiles" "tabs" "open" "focus"
    "close" "snapshot" "screenshot" "navigate" "console" "pdf"
    "upload" "dialog" "act")
  "List of supported browser actions.")

;;; -----------------------------------------------------------------------
;;; Browser tool handler
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table) string) handle-browser-tool))
(defun handle-browser-tool (args)
  "Handle a browser tool call.
Arguments:
  action: browser action (status, start, stop, snapshot, etc.)
  url: URL for open/navigate actions
  ref: element reference for act actions
  ... (action-specific arguments)"
  (declare (type hash-table args))
  (let ((action (or (gethash "action" args)
                    (error "browser tool requires action"))))
    (declare (type string action))
    (unless (member action +browser-actions+ :test #'string=)
      (error "Unknown browser action: ~A. Supported: ~{~A~^, ~}"
             action +browser-actions+))
    ;; Stub implementation — returns structured placeholder
    ;; Full CDP integration will replace these
    (cond
      ((string= action "status")
       "{\"status\": \"not-connected\", \"note\": \"CDP integration pending\"}")
      ((string= action "start")
       "{\"status\": \"started\", \"note\": \"CDP integration pending\"}")
      ((string= action "stop")
       "{\"status\": \"stopped\"}")
      ((string= action "snapshot")
       "{\"snapshot\": [], \"note\": \"CDP integration pending\"}")
      ((string= action "screenshot")
       "{\"error\": \"CDP integration pending\"}")
      ((string= action "navigate")
       (let ((url (gethash "url" args)))
         (if url
             (format nil "{\"navigated\": \"~A\"}" url)
             "{\"error\": \"navigate requires url\"}")))
      ((string= action "open")
       (let ((url (gethash "url" args)))
         (if url
             (format nil "{\"opened\": \"~A\"}" url)
             "{\"error\": \"open requires url\"}")))
      (t
       (format nil "{\"action\": \"~A\", \"note\": \"CDP integration pending\"}"
               action)))))

;;; -----------------------------------------------------------------------
;;; Registration
;;; -----------------------------------------------------------------------

(defun register-browser-tool ()
  "Register the browser tool in the global registry."
  (register-tool (make-tool-definition
                  :name "browser"
                  :description "Control the browser via CDP (Chrome DevTools Protocol). Actions: status, start, stop, snapshot, screenshot, navigate, act."
                  :handler #'handle-browser-tool
                  :category "browser"))
  (values))
