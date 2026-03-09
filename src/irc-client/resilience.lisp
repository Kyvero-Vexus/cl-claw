;;;; resilience.lisp — IRC reconnection & resilience
;;;;
;;;; Provides automatic reconnection with backoff for IRC connections.

(defpackage :cl-claw.irc-client.resilience
  (:use :cl)
  (:import-from :cl-claw.irc-client.connection
                :irc-connection
                :irc-connection-connected-p
                :irc-connect
                :irc-disconnect)
  (:import-from :cl-claw.channel-protocol.lifecycle
                :compute-backoff-delay)
  (:export
   :irc-reconnect
   :irc-with-reconnect
   :*irc-max-reconnect-attempts*))

(in-package :cl-claw.irc-client.resilience)

(declaim (optimize (safety 3) (debug 3)))

(defvar *irc-max-reconnect-attempts* 15
  "Maximum IRC reconnection attempts.")

(defun irc-reconnect (conn &key (max-attempts *irc-max-reconnect-attempts*))
  "Attempt to reconnect an IRC connection with exponential backoff.
Returns T on success, NIL on failure."
  (declare (type irc-connection conn)
           (type fixnum max-attempts))
  ;; Disconnect first
  (handler-case (irc-disconnect conn) (error () nil))
  (loop for attempt from 0 below max-attempts
        do (let ((delay (compute-backoff-delay attempt)))
             (sleep (/ delay 1000.0))
             (handler-case
                 (progn
                   (irc-connect conn)
                   (when (irc-connection-connected-p conn)
                     (return-from irc-reconnect t)))
               (error () nil))))
  nil)

(defmacro irc-with-reconnect ((conn &key (max-attempts '*irc-max-reconnect-attempts*))
                               &body body)
  "Execute BODY, reconnecting on connection errors."
  (let ((result (gensym "RESULT"))
        (success (gensym "SUCCESS")))
    `(let ((,result nil)
           (,success nil))
       (handler-case
           (progn
             (setf ,result (progn ,@body))
             (setf ,success t))
         (error ()
           (when (irc-reconnect ,conn :max-attempts ,max-attempts)
             (handler-case
                 (progn
                   (setf ,result (progn ,@body))
                   (setf ,success t))
               (error () nil)))))
       (values ,result ,success))))
