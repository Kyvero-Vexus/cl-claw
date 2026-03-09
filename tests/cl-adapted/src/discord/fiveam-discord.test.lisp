;;;; fiveam-discord.test.lisp — Tests for the Discord channel

(defpackage :cl-claw.discord.test
  (:use :cl :fiveam)
  (:import-from :cl-claw.discord.rest-client
                :discord-client :make-discord-client
                :dc-api-url)
  (:import-from :cl-claw.discord.gateway
                :+op-dispatch+ :+op-heartbeat+ :+op-identify+
                :+intent-guilds+ :+intent-message-content+
                :default-intents
                :gateway-client :make-gateway-client
                :gateway-client-state :+gateway-disconnected+
                :register-gateway-event :dispatch-gateway-event
                :*gateway-event-handlers*)
  (:import-from :cl-claw.discord.handler
                :discord-channel :make-discord-channel-instance)
  (:import-from :cl-claw.discord.threads
                :register-discord-thread-binding
                :resolve-discord-thread-binding
                :clear-discord-thread-bindings)
  (:import-from :cl-claw.discord.media
                :make-discord-embed :make-embed-field
                :extract-discord-attachments)
  (:import-from :cl-claw.channel-protocol
                :channel-get-info :channel-info-id
                :channel-get-state :+channel-state-disconnected+))

(in-package :cl-claw.discord.test)

(def-suite discord-suite :description "Discord channel tests")
(in-suite discord-suite)

;;; REST client
(test dc-api-url-test
  "dc-api-url builds correct URLs"
  (let ((client (make-discord-client :token "tok123")))
    (is (string= "https://discord.com/api/v10/users/@me"
                  (dc-api-url client "/users/@me")))))

(test dc-api-url-custom-base
  "dc-api-url with custom base"
  (let ((client (make-discord-client :token "t" :api-base "http://localhost")))
    (is (string= "http://localhost/test" (dc-api-url client "/test")))))

;;; Gateway
(test gateway-opcodes
  "gateway opcodes are correct"
  (is (= 0 +op-dispatch+))
  (is (= 1 +op-heartbeat+))
  (is (= 2 +op-identify+)))

(test gateway-intents
  "gateway intents compute correctly"
  (is (= 1 +intent-guilds+))
  (is (= 32768 +intent-message-content+))
  (let ((intents (default-intents)))
    (is (plusp intents))
    (is (logtest +intent-guilds+ intents))
    (is (logtest +intent-message-content+ intents))))

(test gateway-client-state
  "gateway client starts disconnected"
  (let ((gc (make-gateway-client)))
    (is (eq +gateway-disconnected+ (gateway-client-state gc)))))

(test gateway-event-dispatch
  "gateway event dispatch works"
  (let ((received nil))
    (clrhash *gateway-event-handlers*)
    (register-gateway-event "MESSAGE_CREATE"
                            (lambda (data) (setf received data)))
    (dispatch-gateway-event "MESSAGE_CREATE" "test-data")
    (is (string= "test-data" received))
    (clrhash *gateway-event-handlers*)))

;;; Channel
(test discord-channel-info
  "discord channel info is correct"
  (let* ((ch (make-discord-channel-instance))
         (info (channel-get-info ch)))
    (is (string= "discord" (channel-info-id info)))))

(test discord-initial-state
  "discord channel starts disconnected"
  (is (eq +channel-state-disconnected+
          (channel-get-state (make-discord-channel-instance)))))

;;; Threads
(test discord-thread-binding-crud
  "Discord thread bindings work"
  (clear-discord-thread-bindings)
  (register-discord-thread-binding "t1" "agent-a")
  (is (string= "agent-a" (resolve-discord-thread-binding "t1")))
  (is (null (resolve-discord-thread-binding "t2")))
  (clear-discord-thread-bindings)
  (is (null (resolve-discord-thread-binding "t1"))))

;;; Media & embeds
(test discord-embed-construction
  "make-discord-embed creates valid embeds"
  (let ((embed (make-discord-embed :title "Test"
                                    :description "A test embed"
                                    :color 16711680)))
    (is (string= "Test" (gethash "title" embed)))
    (is (string= "A test embed" (gethash "description" embed)))
    (is (= 16711680 (gethash "color" embed)))))

(test discord-embed-with-fields
  "embed fields work"
  (let* ((fields (list (make-embed-field "Name" "Value" :inline t)))
         (embed (make-discord-embed :fields fields)))
    (is (= 1 (length (gethash "fields" embed))))
    (let ((field (first (gethash "fields" embed))))
      (is (string= "Name" (gethash "name" field)))
      (is (string= "Value" (gethash "value" field)))
      (is (eq t (gethash "inline" field))))))

(test extract-attachments-empty
  "extract-discord-attachments handles no attachments"
  (let ((msg (make-hash-table :test 'equal)))
    (is (null (extract-discord-attachments msg)))))

(test extract-attachments-with-files
  "extract-discord-attachments extracts file info"
  (let ((msg (make-hash-table :test 'equal))
        (att (make-hash-table :test 'equal)))
    (setf (gethash "url" att) "https://cdn.discord.com/file.png")
    (setf (gethash "filename" att) "file.png")
    (setf (gethash "size" att) 1234)
    (setf (gethash "attachments" msg) (list att))
    (let ((result (extract-discord-attachments msg)))
      (is (= 1 (length result)))
      (is (string= "https://cdn.discord.com/file.png" (first (first result)))))))
