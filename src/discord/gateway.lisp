;;;; gateway.lisp — Discord gateway WebSocket client (stub)
;;;;
;;;; Provides the gateway connection infrastructure for Discord's
;;;; WebSocket-based real-time event system. Full WebSocket implementation
;;;; requires a CL WebSocket library (e.g., websocket-driver);
;;;; this provides the protocol skeleton and event dispatch.

(defpackage :cl-claw.discord.gateway
  (:use :cl)
  (:import-from :cl-claw.discord.rest-client
                :discord-client
                :dc-get-gateway)
  (:export
   ;; Gateway state
   :+gateway-disconnected+
   :+gateway-connecting+
   :+gateway-connected+
   :+gateway-resuming+

   ;; Gateway opcodes
   :+op-dispatch+
   :+op-heartbeat+
   :+op-identify+
   :+op-resume+
   :+op-hello+
   :+op-heartbeat-ack+

   ;; Gateway intents
   :+intent-guilds+
   :+intent-guild-messages+
   :+intent-guild-message-reactions+
   :+intent-direct-messages+
   :+intent-message-content+
   :default-intents

   ;; Gateway client
   :gateway-client
   :make-gateway-client
   :gateway-client-state
   :gateway-client-session-id
   :gateway-client-sequence
   :gateway-url-from-rest

   ;; Event dispatch
   :gateway-event-handler
   :*gateway-event-handlers*
   :register-gateway-event
   :dispatch-gateway-event))

(in-package :cl-claw.discord.gateway)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Gateway state
;;; -----------------------------------------------------------------------

(defconstant +gateway-disconnected+ :disconnected)
(defconstant +gateway-connecting+ :connecting)
(defconstant +gateway-connected+ :connected)
(defconstant +gateway-resuming+ :resuming)

;;; -----------------------------------------------------------------------
;;; Opcodes (Discord Gateway)
;;; -----------------------------------------------------------------------

(defconstant +op-dispatch+ 0)
(defconstant +op-heartbeat+ 1)
(defconstant +op-identify+ 2)
(defconstant +op-resume+ 6)
(defconstant +op-hello+ 10)
(defconstant +op-heartbeat-ack+ 11)

;;; -----------------------------------------------------------------------
;;; Gateway intents
;;; -----------------------------------------------------------------------

(defconstant +intent-guilds+ (ash 1 0))
(defconstant +intent-guild-messages+ (ash 1 9))
(defconstant +intent-guild-message-reactions+ (ash 1 10))
(defconstant +intent-direct-messages+ (ash 1 12))
(defconstant +intent-message-content+ (ash 1 15))

(defun default-intents ()
  "Default gateway intents for an OpenClaw agent."
  (logior +intent-guilds+
          +intent-guild-messages+
          +intent-guild-message-reactions+
          +intent-direct-messages+
          +intent-message-content+))

;;; -----------------------------------------------------------------------
;;; Gateway client
;;; -----------------------------------------------------------------------

(defstruct gateway-client
  "Discord gateway WebSocket client state."
  (state +gateway-disconnected+ :type keyword)
  (session-id nil :type (or string null))
  (sequence nil :type (or fixnum null))
  (gateway-url nil :type (or string null))
  (heartbeat-interval 0 :type fixnum)
  (intents (default-intents) :type fixnum))

;;; -----------------------------------------------------------------------
;;; Gateway URL resolution
;;; -----------------------------------------------------------------------

(defun gateway-url-from-rest (rest-client)
  "Get the gateway WebSocket URL via REST API."
  (declare (type discord-client rest-client))
  (multiple-value-bind (result ok) (dc-get-gateway rest-client)
    (when (and ok (hash-table-p result))
      (gethash "url" result))))

;;; -----------------------------------------------------------------------
;;; Event dispatch
;;; -----------------------------------------------------------------------

(defvar *gateway-event-handlers* (make-hash-table :test 'equal)
  "Map from event-name (string) -> handler function.")

(defun register-gateway-event (event-name handler)
  "Register a handler for a gateway event."
  (declare (type string event-name)
           (type function handler))
  (setf (gethash event-name *gateway-event-handlers*) handler)
  (values))

(defun dispatch-gateway-event (event-name data)
  "Dispatch a gateway event to registered handlers."
  (declare (type string event-name))
  (let ((handler (gethash event-name *gateway-event-handlers*)))
    (when handler
      (funcall handler data))))
