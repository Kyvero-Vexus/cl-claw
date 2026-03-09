;;;; fiveam-telegram.test.lisp — Tests for the Telegram channel

(defpackage :cl-claw.telegram.test
  (:use :cl :fiveam)
  (:import-from :cl-claw.telegram.api-client
                :telegram-client :make-telegram-client
                :telegram-client-token :telegram-client-api-base
                :tg-api-url :tg-download-file)
  (:import-from :cl-claw.telegram.handler
                :telegram-channel :make-telegram-channel-instance
                :telegram-channel-bot-username)
  (:import-from :cl-claw.telegram.media
                :file-id-to-path)
  (:import-from :cl-claw.telegram.groups
                :extract-topic-thread-id
                :is-forum-message-p
                :build-group-sender-prefix
                :register-thread-binding
                :resolve-thread-binding
                :remove-thread-binding
                :clear-thread-bindings
                :should-respond-in-group-p)
  (:import-from :cl-claw.channel-protocol
                :make-normalized-message
                :channel-get-info :channel-info-id
                :channel-get-state
                :+channel-state-disconnected+))

(in-package :cl-claw.telegram.test)

(def-suite telegram-suite
  :description "Telegram channel tests")

(in-suite telegram-suite)

;;; =======================================================================
;;; 1. API client tests
;;; =======================================================================

(test api-url-construction
  "tg-api-url builds correct URLs"
  (let ((client (make-telegram-client :token "123:ABC")))
    (is (string= "https://api.telegram.org/bot123:ABC/getMe"
                  (tg-api-url client "getMe")))
    (is (string= "https://api.telegram.org/bot123:ABC/sendMessage"
                  (tg-api-url client "sendMessage")))))

(test api-url-custom-base
  "tg-api-url respects custom base URL"
  (let ((client (make-telegram-client :token "tok" :api-base "http://localhost:8080")))
    (is (string= "http://localhost:8080/bottok/getMe"
                  (tg-api-url client "getMe")))))

(test download-url-construction
  "tg-download-file builds correct URLs"
  (let ((client (make-telegram-client :token "123:ABC")))
    (is (string= "https://api.telegram.org/file/bot123:ABC/photos/file_1.jpg"
                  (tg-download-file client "photos/file_1.jpg")))))

;;; =======================================================================
;;; 2. Channel instance tests
;;; =======================================================================

(test channel-info
  "telegram channel info is correct"
  (let* ((ch (make-telegram-channel-instance))
         (info (channel-get-info ch)))
    (is (string= "telegram" (channel-info-id info)))))

(test channel-initial-state
  "telegram channel starts disconnected"
  (let ((ch (make-telegram-channel-instance)))
    (is (eq +channel-state-disconnected+ (channel-get-state ch)))))

;;; =======================================================================
;;; 3. Media helper tests
;;; =======================================================================

(test file-id-to-path-test
  "file-id-to-path generates expected paths"
  (is (string= "/tmp/tg-abc123" (file-id-to-path "abc123")))
  (is (string= "/data/tg-xyz" (file-id-to-path "xyz" "/data"))))

;;; =======================================================================
;;; 4. Groups/topics tests
;;; =======================================================================

(test extract-topic-thread-id-test
  "extracts thread ID from raw message"
  (let ((msg (make-hash-table :test 'equal)))
    (setf (gethash "message_thread_id" msg) 42)
    (is (string= "42" (extract-topic-thread-id msg))))
  (let ((msg (make-hash-table :test 'equal)))
    (is (null (extract-topic-thread-id msg)))))

(test is-forum-message-test
  "detects forum messages"
  (let ((msg (make-hash-table :test 'equal)))
    (setf (gethash "is_topic_message" msg) t)
    (is (is-forum-message-p msg)))
  (let ((msg (make-hash-table :test 'equal)))
    (setf (gethash "message_thread_id" msg) 42)
    (is (is-forum-message-p msg)))
  (let ((msg (make-hash-table :test 'equal)))
    (is (not (is-forum-message-p msg)))))

(test group-sender-prefix
  "builds sender prefix for group messages"
  (let ((dm-msg (make-normalized-message :is-group-p nil :sender-name "Alice")))
    (is (string= "" (build-group-sender-prefix dm-msg))))
  (let ((group-msg (make-normalized-message :is-group-p t :sender-name "Alice")))
    (is (string= "[Alice] " (build-group-sender-prefix group-msg))))
  (let ((group-msg (make-normalized-message :is-group-p t :sender-name "")))
    (is (string= "" (build-group-sender-prefix group-msg)))))

;;; =======================================================================
;;; 5. Thread binding tests
;;; =======================================================================

(test thread-binding-crud
  "thread binding CRUD operations"
  (clear-thread-bindings)
  ;; Register
  (register-thread-binding "chat1" "thread1" "agent-a")
  (is (string= "agent-a" (resolve-thread-binding "chat1" "thread1")))
  ;; Not found
  (is (null (resolve-thread-binding "chat1" "thread2")))
  ;; Remove
  (remove-thread-binding "chat1" "thread1")
  (is (null (resolve-thread-binding "chat1" "thread1"))))

;;; =======================================================================
;;; 6. Group response decision tests
;;; =======================================================================

(test should-respond-dm
  "should respond to DMs"
  (let ((msg (make-normalized-message :is-group-p nil)))
    (is (should-respond-in-group-p msg))))

(test should-respond-mention
  "should respond to mentions"
  (let ((msg (make-normalized-message :is-group-p t :is-mention-p t)))
    (is (should-respond-in-group-p msg))))

(test should-not-respond-random-group
  "should not respond to random group messages"
  (let ((msg (make-normalized-message :is-group-p t :is-mention-p nil
                                       :target "chat1" :thread nil)))
    (is (not (should-respond-in-group-p msg)))))

(test should-respond-thread-binding
  "should respond when thread has binding"
  (clear-thread-bindings)
  (register-thread-binding "chat1" "t1" "agent-x")
  (let ((msg (make-normalized-message :is-group-p t :is-mention-p nil
                                       :target "chat1" :thread "t1")))
    (is (should-respond-in-group-p msg)))
  (clear-thread-bindings))
