;;;; FiveAM tests for iMessage/BlueBubbles adapter

(defpackage :cl-claw.channels.imessage.test
  (:use :cl :fiveam))

(in-package :cl-claw.channels.imessage.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite channels-imessage-suite
  :description "Tests for iMessage (BlueBubbles) routing and payload helpers")

(in-suite channels-imessage-suite)

(defun %hash (&rest kv)
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kv by #'cddr do
      (setf (gethash k h) v))
    h))

(test direct-chat-uses-sender-handle
  (let* ((event (%hash "sender" "+1 (212) 555-0199" "isGroup" nil))
         (route (cl-claw.channels.imessage:imessage-event->route-entry event)))
    (is (string= "imessage" (cl-claw.routing:route-entry-provider route)))
    (is (string= "+12125550199" (cl-claw.routing:route-entry-target route)))))

(test group-chat-uses-chat-id
  (let* ((event (%hash "sender" "+12125550199"
                       "chat_id" "chat123456;+-;1"
                       "isGroup" t))
         (route (cl-claw.channels.imessage:imessage-event->route-entry event)))
    (is (string= "chat123456;+-;1" (cl-claw.routing:route-entry-target route)))))

(test classify-common-imessage-target-forms
  (is (eq :phone (cl-claw.channels.imessage:classify-imessage-target "+1 650 555 0001")))
  (is (eq :email (cl-claw.channels.imessage:classify-imessage-target "User@Example.COM")))
  (is (eq :chat-guid (cl-claw.channels.imessage:classify-imessage-target "chat987;+-;2"))))

(test payload-uses-address-for-direct-target
  (let* ((route (cl-claw.routing:make-route-entry :provider "imessage"
                                                  :account "default"
                                                  :target "+14155550100"
                                                  :thread nil
                                                  :agent-id "main"))
         (payload (cl-claw.channels.imessage:imessage-route->send-payload route "hello")))
    (is (string= "+14155550100" (gethash "address" payload)))
    (is (null (gethash "chatGuid" payload)))
    (is (string= "hello" (gethash "message" payload)))))

(test payload-uses-chat-guid-for-groups
  (let* ((route (cl-claw.routing:make-route-entry :provider "imessage"
                                                  :account "default"
                                                  :target "chat123;+-;3"
                                                  :thread "thread-7"
                                                  :agent-id "main"))
         (payload (cl-claw.channels.imessage:imessage-route->send-payload route "yo")))
    (is (string= "chat123;+-;3" (gethash "chatGuid" payload)))
    (is (null (gethash "address" payload)))
    (is (string= "thread-7" (gethash "thread_id" payload)))))
