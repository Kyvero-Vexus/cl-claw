;;;; FiveAM tests for channel adapters

(defpackage :cl-claw.channels.test
  (:use :cl :fiveam))

(in-package :cl-claw.channels.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite channels-suite
  :description "Tests for telegram/irc/discord/signal/slack routing helpers")

(in-suite channels-suite)

(defun hash (&rest kv)
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kv by #'cddr do
      (setf (gethash k h) v))
    h))

(test telegram-maps-threaded-update
  (let* ((update (hash "chatId" 123 "threadId" 77))
         (route (cl-claw.channels.telegram:telegram-update->route-entry update))
         (payload (cl-claw.channels.telegram:telegram-route->send-payload route "hi")))
    (is (string= "telegram" (cl-claw.routing:route-entry-provider route)))
    (is (string= "123" (cl-claw.routing:route-entry-target route)))
    (is (string= "77" (gethash "message_thread_id" payload)))))

(test irc-maps-channel-and-privmsg
  (let* ((message (hash "channel" "#bots"))
         (route (cl-claw.channels.irc:irc-message->route-entry message))
         (cmd (cl-claw.channels.irc:irc-route->send-command route "pong")))
    (is (string= "irc" (cl-claw.routing:route-entry-provider route)))
    (is (search "PRIVMSG #bots :pong" cmd))))

(test discord-maps-thread
  (let* ((event (hash "channelId" "C1" "threadId" "T1"))
         (route (cl-claw.channels.discord:discord-event->route-entry event))
         (payload (cl-claw.channels.discord:discord-route->send-payload route "yo")))
    (is (string= "discord" (cl-claw.routing:route-entry-provider route)))
    (is (string= "T1" (gethash "thread_id" payload)))))

(test signal-maps-group
  (let* ((event (hash "groupId" "grp-9"))
         (route (cl-claw.channels.signal:signal-envelope->route-entry event))
         (payload (cl-claw.channels.signal:signal-route->send-payload route "ok")))
    (is (string= "signal" (cl-claw.routing:route-entry-provider route)))
    (is (string= "grp-9" (gethash "recipient" payload)))))

(test slack-maps-thread
  (let* ((event (hash "channel" "C77" "thread_ts" "1700.3"))
         (route (cl-claw.channels.slack:slack-event->route-entry event))
         (payload (cl-claw.channels.slack:slack-route->send-payload route "hey")))
    (is (string= "slack" (cl-claw.routing:route-entry-provider route)))
    (is (string= "1700.3" (gethash "thread_ts" payload)))))