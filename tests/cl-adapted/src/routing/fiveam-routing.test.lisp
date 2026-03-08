;;;; FiveAM tests for routing domain

(defpackage :cl-claw.routing.test
  (:use :cl :fiveam))

(in-package :cl-claw.routing.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite routing-suite
  :description "Tests for session-key routing")

(in-suite routing-suite)

(test make-session-key-normalizes-provider-account-and-target
  (is (string= "discord:ops:user_123@main"
               (cl-claw.routing:make-session-key "DisCord" "OPS" "User#123"))))

(test parse-session-key-roundtrip
  (let* ((key (cl-claw.routing:make-session-key "telegram" "default" "chat-10" :thread "77" :agent-id "ops"))
         (parsed (cl-claw.routing:parse-session-key key)))
    (is (string= "telegram" (gethash "provider" parsed)))
    (is (string= "default" (gethash "account" parsed)))
    (is (string= "chat-10" (gethash "target" parsed)))
    (is (string= "77" (gethash "thread" parsed)))
    (is (string= "ops" (gethash "agentId" parsed)))))

(test resolve-route-for-inbound-is-stable
  (let* ((table (cl-claw.routing:create-route-table))
         (first (cl-claw.routing:resolve-route-for-inbound table "discord" "a1" "channel-9"))
         (second (cl-claw.routing:resolve-route-for-inbound table "DISCORD" "A1" "channel-9")))
    (declare (type cl-claw.routing:route-table table)
             (type cl-claw.routing:route-entry first second))
    (is (string= (cl-claw.routing:route-entry-provider first)
                 (cl-claw.routing:route-entry-provider second)))
    (is (string= (cl-claw.routing:route-entry-target first)
                 (cl-claw.routing:route-entry-target second)))))

(test remember-and-resolve-route-by-session-key
  (let* ((table (cl-claw.routing:create-route-table))
         (route (cl-claw.routing::make-route-entry :provider "slack"
                                                   :account "default"
                                                   :target "C-1"
                                                   :topic "thread-x"
                                                   :agent-id "main"))
         (key (cl-claw.routing:remember-route table route))
         (resolved (cl-claw.routing:resolve-route table key)))
    (declare (type cl-claw.routing:route-entry route resolved)
             (type string key))
    (is (not (null resolved)))
    (is (string= "slack" (cl-claw.routing:route-entry-provider resolved)))
    (is (string= "c-1" (cl-claw.routing:route-entry-target resolved)))
    (is (string= "thread-x" (cl-claw.routing:route-entry-topic resolved)))))