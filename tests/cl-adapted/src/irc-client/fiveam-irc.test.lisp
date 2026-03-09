;;;; fiveam-irc.test.lisp — Tests for the IRC channel

(defpackage :cl-claw.irc-client.test
  (:use :cl :fiveam)
  (:import-from :cl-claw.irc-client.connection
                :irc-connection :make-irc-connection
                :irc-connection-host :irc-connection-port
                :irc-connection-nick :irc-connection-tls-p)
  (:import-from :cl-claw.irc-client.parser
                :irc-message :parse-irc-line
                :irc-message-prefix :irc-message-nick
                :irc-message-user :irc-message-host
                :irc-message-command :irc-message-params
                :irc-message-trailing
                :extract-nick-from-prefix)
  (:import-from :cl-claw.irc-client.handler
                :irc-channel :make-irc-channel-instance)
  (:import-from :cl-claw.channel-protocol
                :channel-get-info :channel-info-id
                :channel-get-state :+channel-state-disconnected+))

(in-package :cl-claw.irc-client.test)

(def-suite irc-suite :description "IRC channel tests")
(in-suite irc-suite)

;;; Connection struct
(test irc-connection-struct
  "irc-connection struct works"
  (let ((conn (make-irc-connection :host "irc.example.com"
                                    :port 6697
                                    :nick "testbot"
                                    :tls-p t)))
    (is (string= "irc.example.com" (irc-connection-host conn)))
    (is (= 6697 (irc-connection-port conn)))
    (is (string= "testbot" (irc-connection-nick conn)))
    (is (irc-connection-tls-p conn))))

;;; IRC message parsing
(test parse-privmsg
  "parses a PRIVMSG correctly"
  (let ((msg (parse-irc-line ":nick!user@host PRIVMSG #channel :Hello world")))
    (is (string= "nick" (irc-message-nick msg)))
    (is (string= "user" (irc-message-user msg)))
    (is (string= "host" (irc-message-host msg)))
    (is (string= "PRIVMSG" (irc-message-command msg)))
    (is (equal '("#channel") (irc-message-params msg)))
    (is (string= "Hello world" (irc-message-trailing msg)))))

(test parse-ping
  "parses a PING correctly"
  (let ((msg (parse-irc-line "PING :server.example.com")))
    (is (string= "PING" (irc-message-command msg)))
    (is (string= "server.example.com" (irc-message-trailing msg)))))

(test parse-numeric-reply
  "parses a numeric reply"
  (let ((msg (parse-irc-line ":server 001 botname :Welcome to IRC")))
    (is (string= "server" (irc-message-nick msg)))
    (is (string= "001" (irc-message-command msg)))
    (is (equal '("botname") (irc-message-params msg)))
    (is (string= "Welcome to IRC" (irc-message-trailing msg)))))

(test parse-join
  "parses a JOIN correctly"
  (let ((msg (parse-irc-line ":nick!user@host JOIN #channel")))
    (is (string= "JOIN" (irc-message-command msg)))
    (is (string= "nick" (irc-message-nick msg)))))

(test parse-no-prefix
  "parses line without prefix"
  (let ((msg (parse-irc-line "NOTICE AUTH :*** Looking up your hostname")))
    (is (null (irc-message-prefix msg)))
    (is (string= "NOTICE" (irc-message-command msg)))))

(test parse-cr-lf
  "strips trailing CR/LF"
  (let ((msg (parse-irc-line (format nil ":n!u@h PRIVMSG #c :test~C~C" #\Return #\Newline))))
    (is (string= "test" (irc-message-trailing msg)))))

;;; Nick extraction
(test extract-nick
  "extracts nick from prefix"
  (is (string= "nick" (extract-nick-from-prefix "nick!user@host")))
  (is (string= "nick" (extract-nick-from-prefix "nick")))
  (is (string= "server.example.com" (extract-nick-from-prefix "server.example.com"))))

;;; Channel
(test irc-channel-info
  "IRC channel info is correct"
  (let* ((ch (make-irc-channel-instance))
         (info (channel-get-info ch)))
    (is (string= "irc" (channel-info-id info)))))

(test irc-initial-state
  "IRC channel starts disconnected"
  (is (eq +channel-state-disconnected+
          (channel-get-state (make-irc-channel-instance)))))
