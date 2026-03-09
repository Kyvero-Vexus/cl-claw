;;;; lifecycle.lisp — Channel lifecycle management
;;;;
;;;; Manages channel connection lifecycle, reconnection logic,
;;;; and channel state transitions.

(defpackage :cl-claw.channel-protocol.lifecycle
  (:use :cl)
  (:import-from :cl-claw.channel-protocol.types
                :channel
                :channel-state-slot
                :channel-get-info
                :channel-connect
                :channel-disconnect
                :channel-get-state
                :channel-info
                :channel-info-id
                :channel-account
                :channel-account-id
                :+channel-state-disconnected+
                :+channel-state-connecting+
                :+channel-state-connected+
                :+channel-state-reconnecting+
                :+channel-state-error+)
  (:export
   ;; Lifecycle manager
   :channel-manager
   :make-channel-manager
   :manager-add-channel
   :manager-remove-channel
   :manager-get-channel
   :manager-list-channels
   :manager-connect-all
   :manager-disconnect-all
   :manager-get-status

   ;; Reconnection
   :reconnect-channel
   :*max-reconnect-attempts*
   :*reconnect-base-delay-ms*
   :*reconnect-max-delay-ms*
   :compute-backoff-delay))

(in-package :cl-claw.channel-protocol.lifecycle)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Configuration
;;; -----------------------------------------------------------------------

(defvar *max-reconnect-attempts* 10
  "Maximum number of reconnection attempts before giving up.")

(defvar *reconnect-base-delay-ms* 1000
  "Base delay in milliseconds for exponential backoff.")

(defvar *reconnect-max-delay-ms* 60000
  "Maximum delay in milliseconds for reconnection backoff.")

;;; -----------------------------------------------------------------------
;;; Backoff computation
;;; -----------------------------------------------------------------------

(declaim (ftype (function (fixnum) fixnum) compute-backoff-delay))
(defun compute-backoff-delay (attempt)
  "Compute exponential backoff delay for reconnection attempt.
Uses jittered exponential backoff."
  (declare (type fixnum attempt))
  (let* ((exponential (* *reconnect-base-delay-ms*
                         (expt 2 (min attempt 10))))
         (jitter (random (max 1 (floor exponential 4))))
         (delay (+ exponential jitter)))
    (min delay *reconnect-max-delay-ms*)))

;;; -----------------------------------------------------------------------
;;; Channel reconnection
;;; -----------------------------------------------------------------------

(declaim (ftype (function (channel channel-account &key (:max-attempts fixnum))
                          boolean)
                reconnect-channel))
(defun reconnect-channel (channel account &key (max-attempts *max-reconnect-attempts*))
  "Attempt to reconnect a channel with exponential backoff.
Returns T on success, NIL on failure."
  (declare (type channel channel)
           (type channel-account account)
           (type fixnum max-attempts))
  (setf (channel-state-slot channel) +channel-state-reconnecting+)
  (loop for attempt from 0 below max-attempts
        do (let ((delay (compute-backoff-delay attempt)))
             (declare (type fixnum delay))
             (sleep (/ delay 1000.0))
             (handler-case
                 (progn
                   (channel-connect channel account)
                   (when (eq (channel-get-state channel) +channel-state-connected+)
                     (return-from reconnect-channel t)))
               (error () nil))))
  (setf (channel-state-slot channel) +channel-state-error+)
  nil)

;;; -----------------------------------------------------------------------
;;; Channel manager — manages multiple channel instances
;;; -----------------------------------------------------------------------

(defstruct channel-manager
  "Manages a set of channel instances."
  (channels (make-hash-table :test 'equal) :type hash-table)
  (accounts (make-hash-table :test 'equal) :type hash-table)
  (lock (bt:make-lock "channel-manager") :type t))

(defun manager-add-channel (manager id channel account)
  "Add a channel to the manager."
  (declare (type channel-manager manager)
           (type string id)
           (type channel channel)
           (type channel-account account))
  (bt:with-lock-held ((channel-manager-lock manager))
    (setf (gethash id (channel-manager-channels manager)) channel)
    (setf (gethash id (channel-manager-accounts manager)) account))
  (values))

(defun manager-remove-channel (manager id)
  "Remove a channel from the manager."
  (declare (type channel-manager manager)
           (type string id))
  (bt:with-lock-held ((channel-manager-lock manager))
    (let ((channel (gethash id (channel-manager-channels manager))))
      (when channel
        (handler-case (channel-disconnect channel)
          (error () nil)))
      (remhash id (channel-manager-channels manager))
      (remhash id (channel-manager-accounts manager))))
  (values))

(defun manager-get-channel (manager id)
  "Get a channel by ID."
  (declare (type channel-manager manager)
           (type string id))
  (gethash id (channel-manager-channels manager)))

(defun manager-list-channels (manager)
  "List all channel IDs."
  (declare (type channel-manager manager))
  (let ((ids '()))
    (maphash (lambda (k v) (declare (ignore v)) (push k ids))
             (channel-manager-channels manager))
    (sort ids #'string<)))

(defun manager-connect-all (manager)
  "Connect all registered channels."
  (declare (type channel-manager manager))
  (maphash (lambda (id channel)
             (declare (type string id))
             (let ((account (gethash id (channel-manager-accounts manager))))
               (when account
                 (handler-case
                     (channel-connect channel account)
                   (error (e)
                     (format *error-output* "Failed to connect channel ~A: ~A~%" id e))))))
           (channel-manager-channels manager))
  (values))

(defun manager-disconnect-all (manager)
  "Disconnect all registered channels."
  (declare (type channel-manager manager))
  (maphash (lambda (id channel)
             (declare (ignore id))
             (handler-case
                 (channel-disconnect channel)
               (error () nil)))
           (channel-manager-channels manager))
  (values))

(defun manager-get-status (manager)
  "Get status of all channels as an alist of (id . state)."
  (declare (type channel-manager manager))
  (let ((status '()))
    (maphash (lambda (id channel)
               (push (cons id (channel-get-state channel)) status))
             (channel-manager-channels manager))
    (sort status #'string< :key #'car)))
