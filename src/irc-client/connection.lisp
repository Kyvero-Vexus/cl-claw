;;;; connection.lisp — IRC client connection
;;;;
;;;; IRC client with TLS support, authentication, and message I/O.
;;;; Uses SBCL sockets directly.

(defpackage :cl-claw.irc-client.connection
  (:use :cl)
  (:export
   :irc-connection
   :make-irc-connection
   :irc-connection-host
   :irc-connection-port
   :irc-connection-nick
   :irc-connection-user
   :irc-connection-realname
   :irc-connection-password
   :irc-connection-tls-p
   :irc-connection-connected-p

   ;; Connection management
   :irc-connect
   :irc-disconnect
   :irc-send-raw
   :irc-read-line

   ;; IRC commands
   :irc-nick
   :irc-user-cmd
   :irc-join
   :irc-part
   :irc-privmsg
   :irc-notice
   :irc-quit
   :irc-pong
   :irc-nickserv-identify))

(in-package :cl-claw.irc-client.connection)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; IRC connection
;;; -----------------------------------------------------------------------

(defstruct irc-connection
  "IRC connection state."
  (host "" :type string)
  (port 6667 :type fixnum)
  (nick "" :type string)
  (user "" :type string)
  (realname "cl-claw" :type string)
  (password nil :type (or string null))
  (tls-p nil :type boolean)
  (connected-p nil :type boolean)
  (socket nil)
  (stream nil :type (or stream null))
  (lock (bt:make-lock "irc-connection") :type t))

;;; -----------------------------------------------------------------------
;;; Connection management
;;; -----------------------------------------------------------------------

(defun irc-connect (conn)
  "Connect to the IRC server."
  (declare (type irc-connection conn))
  (let* ((host (irc-connection-host conn))
         (port (irc-connection-port conn)))
    ;; Use openssl s_client for TLS or netcat for plain
    ;; This is a simplified approach; production would use usocket+cl+ssl
    (handler-case
        (let ((process (uiop:launch-program
                        (if (irc-connection-tls-p conn)
                            (list "openssl" "s_client" "-quiet" "-connect"
                                  (format nil "~A:~D" host port))
                            (list "ncat" host (format nil "~D" port)))
                        :input :stream
                        :output :stream
                        :error-output nil)))
          (setf (irc-connection-socket conn) process)
          (setf (irc-connection-stream conn) (uiop:process-info-input process))
          (setf (irc-connection-connected-p conn) t)
          ;; Send registration
          (when (irc-connection-password conn)
            (irc-send-raw conn (format nil "PASS ~A" (irc-connection-password conn))))
          (irc-nick conn (irc-connection-nick conn))
          (irc-user-cmd conn (irc-connection-user conn) (irc-connection-realname conn))
          t)
      (error (e)
        (setf (irc-connection-connected-p conn) nil)
        (error "IRC connect failed: ~A" e)))))

(defun irc-disconnect (conn)
  "Disconnect from the IRC server."
  (declare (type irc-connection conn))
  (when (irc-connection-connected-p conn)
    (handler-case
        (progn
          (irc-quit conn "cl-claw shutting down")
          (when (irc-connection-socket conn)
            (uiop:terminate-process (irc-connection-socket conn))))
      (error () nil))
    (setf (irc-connection-connected-p conn) nil)
    (setf (irc-connection-stream conn) nil)
    (setf (irc-connection-socket conn) nil)))

(defun irc-send-raw (conn raw-line)
  "Send a raw IRC line."
  (declare (type irc-connection conn)
           (type string raw-line))
  (bt:with-lock-held ((irc-connection-lock conn))
    (let ((stream (irc-connection-stream conn)))
      (when stream
        (write-string raw-line stream)
        (write-char #\Return stream)
        (write-char #\Newline stream)
        (force-output stream)))))

(defun irc-read-line (conn)
  "Read a line from the IRC connection. Returns nil on EOF."
  (declare (type irc-connection conn))
  (let ((socket (irc-connection-socket conn)))
    (when socket
      (let ((stream (uiop:process-info-output socket)))
        (when stream
          (handler-case
              (read-line stream nil nil)
            (error () nil)))))))

;;; -----------------------------------------------------------------------
;;; IRC commands
;;; -----------------------------------------------------------------------

(defun irc-nick (conn nickname)
  "Send NICK command."
  (declare (type irc-connection conn)
           (type string nickname))
  (irc-send-raw conn (format nil "NICK ~A" nickname)))

(defun irc-user-cmd (conn username realname)
  "Send USER command."
  (declare (type irc-connection conn)
           (type string username realname))
  (irc-send-raw conn (format nil "USER ~A 0 * :~A" username realname)))

(defun irc-join (conn channel &optional key)
  "Send JOIN command."
  (declare (type irc-connection conn)
           (type string channel))
  (if key
      (irc-send-raw conn (format nil "JOIN ~A ~A" channel key))
      (irc-send-raw conn (format nil "JOIN ~A" channel))))

(defun irc-part (conn channel &optional message)
  "Send PART command."
  (declare (type irc-connection conn)
           (type string channel))
  (if message
      (irc-send-raw conn (format nil "PART ~A :~A" channel message))
      (irc-send-raw conn (format nil "PART ~A" channel))))

(defun irc-privmsg (conn target message)
  "Send PRIVMSG command."
  (declare (type irc-connection conn)
           (type string target message))
  (irc-send-raw conn (format nil "PRIVMSG ~A :~A" target message)))

(defun irc-notice (conn target message)
  "Send NOTICE command."
  (declare (type irc-connection conn)
           (type string target message))
  (irc-send-raw conn (format nil "NOTICE ~A :~A" target message)))

(defun irc-quit (conn &optional message)
  "Send QUIT command."
  (declare (type irc-connection conn))
  (if message
      (irc-send-raw conn (format nil "QUIT :~A" message))
      (irc-send-raw conn "QUIT")))

(defun irc-pong (conn server)
  "Send PONG command (response to PING)."
  (declare (type irc-connection conn)
           (type string server))
  (irc-send-raw conn (format nil "PONG :~A" server)))

(defun irc-nickserv-identify (conn password)
  "Identify with NickServ."
  (declare (type irc-connection conn)
           (type string password))
  (irc-privmsg conn "NickServ" (format nil "IDENTIFY ~A" password)))
