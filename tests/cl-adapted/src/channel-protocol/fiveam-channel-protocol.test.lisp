;;;; fiveam-channel-protocol.test.lisp — Tests for the channel protocol

(defpackage :cl-claw.channel-protocol.test
  (:use :cl :fiveam)
  (:import-from :cl-claw.channel-protocol
                ;; Types
                :normalized-message :make-normalized-message
                :normalized-message-id :normalized-message-channel
                :normalized-message-text :normalized-message-target
                :normalized-message-thread :normalized-message-sender-name
                :normalized-message-is-group-p :normalized-message-is-mention-p
                :normalized-message-attachments :normalized-message-reply-to-id
                :outbound-message :make-outbound-message
                :outbound-message-text :outbound-message-target
                :outbound-message-thread :outbound-message-reply-to-id
                :outbound-message-silent-p
                :attachment :make-attachment :attachment-type
                :channel-account :make-channel-account
                :channel-account-id :channel-account-channel
                :channel-account-display-name
                :channel-account-bot-token
                :channel-info :make-channel-info
                :channel :channel-get-state
                :+channel-state-disconnected+
                ;; Normalize
                :normalize-telegram-message
                :normalize-discord-message
                :normalize-irc-message
                :extract-mentions :sanitize-message-text
                ;; Format
                :format-telegram-outbound
                :format-discord-outbound
                :format-irc-outbound
                :split-long-message
                :+telegram-max-message-length+
                ;; Queue
                :message-queue :make-message-queue
                :queue-enqueue :queue-dequeue :queue-length
                :queue-empty-p :queue-clear
                :rate-limited-sender :make-rate-limited-sender
                :sender-enqueue :sender-queue-length
                ;; Lifecycle
                :channel-manager :make-channel-manager
                :manager-add-channel :manager-list-channels
                :manager-get-channel :manager-get-status
                :compute-backoff-delay
                ;; Accounts
                :register-account :get-account :list-accounts
                :list-accounts-for-channel :clear-accounts
                :resolve-account-from-config))

(in-package :cl-claw.channel-protocol.test)

(def-suite channel-protocol-suite
  :description "Channel protocol tests")

(in-suite channel-protocol-suite)

;;; -----------------------------------------------------------------------
;;; Helpers
;;; -----------------------------------------------------------------------

(defun make-tg-message (&key (text "hello") (chat-id 12345) (from-id 67890)
                              (first-name "Test") (chat-type "private")
                              thread-id reply-to)
  "Create a mock Telegram message hash-table."
  (let ((msg (make-hash-table :test 'equal))
        (chat (make-hash-table :test 'equal))
        (from (make-hash-table :test 'equal)))
    (setf (gethash "message_id" msg) 999)
    (setf (gethash "text" msg) text)
    (setf (gethash "date" msg) 1700000000)
    (setf (gethash "id" chat) chat-id)
    (setf (gethash "type" chat) chat-type)
    (setf (gethash "chat" msg) chat)
    (setf (gethash "id" from) from-id)
    (setf (gethash "first_name" from) first-name)
    (setf (gethash "from" msg) from)
    (when thread-id
      (setf (gethash "message_thread_id" msg) thread-id))
    (when reply-to
      (let ((reply-msg (make-hash-table :test 'equal)))
        (setf (gethash "message_id" reply-msg) reply-to)
        (setf (gethash "reply_to_message" msg) reply-msg)))
    msg))

(defun make-discord-message (&key (content "hello") (channel-id "123")
                                   (guild-id "456") (author-id "789")
                                   (username "testuser"))
  "Create a mock Discord message hash-table."
  (let ((msg (make-hash-table :test 'equal))
        (author (make-hash-table :test 'equal)))
    (setf (gethash "id" msg) "msg-1")
    (setf (gethash "content" msg) content)
    (setf (gethash "channel_id" msg) channel-id)
    (when guild-id
      (setf (gethash "guild_id" msg) guild-id))
    (setf (gethash "id" author) author-id)
    (setf (gethash "username" author) username)
    (setf (gethash "author" msg) author)
    msg))

;;; =======================================================================
;;; 1. Normalized message tests
;;; =======================================================================

(test normalized-message-struct
  "normalized-message struct works"
  (let ((nm (make-normalized-message :id "1" :channel "telegram"
                                      :text "hello" :target "123")))
    (is (string= "1" (normalized-message-id nm)))
    (is (string= "telegram" (normalized-message-channel nm)))
    (is (string= "hello" (normalized-message-text nm)))
    (is (string= "123" (normalized-message-target nm)))))

(test outbound-message-struct
  "outbound-message struct works"
  (let ((om (make-outbound-message :text "hi" :target "123"
                                    :silent-p t)))
    (is (string= "hi" (outbound-message-text om)))
    (is (string= "123" (outbound-message-target om)))
    (is (outbound-message-silent-p om))))

;;; =======================================================================
;;; 2. Telegram normalization tests
;;; =======================================================================

(test normalize-telegram-private
  "normalizes a private Telegram message"
  (let* ((raw (make-tg-message :text "hello world" :chat-id 12345 :from-id 67890))
         (nm (normalize-telegram-message raw)))
    (is (string= "telegram" (normalized-message-channel nm)))
    (is (string= "hello world" (normalized-message-text nm)))
    (is (string= "12345" (normalized-message-target nm)))
    (is (not (normalized-message-is-group-p nm)))))

(test normalize-telegram-group
  "normalizes a group Telegram message"
  (let* ((raw (make-tg-message :text "hello" :chat-type "supergroup"))
         (nm (normalize-telegram-message raw)))
    (is (normalized-message-is-group-p nm))))

(test normalize-telegram-mention
  "detects bot mention in Telegram message"
  (let* ((raw (make-tg-message :text "hey @mybot check this"))
         (nm (normalize-telegram-message raw :bot-username "mybot")))
    (is (normalized-message-is-mention-p nm))))

(test normalize-telegram-thread
  "preserves thread ID"
  (let* ((raw (make-tg-message :thread-id 42))
         (nm (normalize-telegram-message raw)))
    (is (string= "42" (normalized-message-thread nm)))))

(test normalize-telegram-reply
  "extracts reply-to message ID"
  (let* ((raw (make-tg-message :reply-to 555))
         (nm (normalize-telegram-message raw)))
    (is (string= "555" (normalized-message-reply-to-id nm)))))

(test normalize-telegram-attachments
  "extracts photo attachments"
  (let* ((raw (make-tg-message))
         (photo-small (make-hash-table :test 'equal))
         (photo-large (make-hash-table :test 'equal)))
    (setf (gethash "file_id" photo-small) "small")
    (setf (gethash "file_size" photo-small) 1000)
    (setf (gethash "file_id" photo-large) "large")
    (setf (gethash "file_size" photo-large) 5000)
    (setf (gethash "photo" raw) (list photo-small photo-large))
    (let ((nm (normalize-telegram-message raw)))
      (is (= 1 (length (normalized-message-attachments nm))))
      (is (string= "image" (attachment-type (first (normalized-message-attachments nm))))))))

;;; =======================================================================
;;; 3. Discord normalization tests
;;; =======================================================================

(test normalize-discord-basic
  "normalizes a Discord message"
  (let* ((raw (make-discord-message :content "test msg"))
         (nm (normalize-discord-message raw)))
    (is (string= "discord" (normalized-message-channel nm)))
    (is (string= "test msg" (normalized-message-text nm)))
    (is (normalized-message-is-group-p nm))))

(test normalize-discord-dm
  "normalizes a Discord DM (no guild)"
  (let* ((raw (make-discord-message :guild-id nil))
         (nm (normalize-discord-message raw)))
    (is (not (normalized-message-is-group-p nm)))))

(test normalize-discord-mention
  "detects bot mention in Discord message"
  (let* ((raw (make-discord-message :content "hey <@BOT123> help"))
         (nm (normalize-discord-message raw :bot-user-id "BOT123")))
    (is (normalized-message-is-mention-p nm))))

;;; =======================================================================
;;; 4. IRC normalization tests
;;; =======================================================================

(test normalize-irc-channel
  "normalizes an IRC channel message"
  (let* ((raw (make-hash-table :test 'equal)))
    (setf (gethash "nick" raw) "testuser")
    (setf (gethash "target" raw) "#bots")
    (setf (gethash "text" raw) "hello bots")
    (let ((nm (normalize-irc-message raw)))
      (is (string= "irc" (normalized-message-channel nm)))
      (is (string= "hello bots" (normalized-message-text nm)))
      (is (string= "#bots" (normalized-message-target nm)))
      (is (normalized-message-is-group-p nm)))))

(test normalize-irc-private
  "normalizes an IRC private message"
  (let* ((raw (make-hash-table :test 'equal)))
    (setf (gethash "nick" raw) "sender")
    (setf (gethash "target" raw) "mybotname")
    (setf (gethash "text" raw) "hey")
    (let ((nm (normalize-irc-message raw)))
      (is (not (normalized-message-is-group-p nm))))))

;;; =======================================================================
;;; 5. Message formatting tests
;;; =======================================================================

(test format-telegram-basic
  "formats a basic Telegram outbound message"
  (let* ((msg (make-outbound-message :text "hello" :target "123"))
         (payload (format-telegram-outbound msg)))
    (is (string= "123" (gethash "chat_id" payload)))
    (is (string= "hello" (gethash "text" payload)))))

(test format-telegram-reply
  "formats a Telegram reply message"
  (let* ((msg (make-outbound-message :text "reply" :target "123"
                                      :reply-to-id "456"))
         (payload (format-telegram-outbound msg)))
    (is (gethash "reply_parameters" payload))
    (is (string= "456" (gethash "message_id"
                                 (gethash "reply_parameters" payload))))))

(test format-telegram-silent
  "formats a silent Telegram message"
  (let* ((msg (make-outbound-message :text "shh" :target "123" :silent-p t))
         (payload (format-telegram-outbound msg)))
    (is (eq t (gethash "disable_notification" payload)))))

(test format-telegram-thread
  "formats a Telegram message with thread"
  (let* ((msg (make-outbound-message :text "threaded" :target "123" :thread "42"))
         (payload (format-telegram-outbound msg)))
    (is (string= "42" (gethash "message_thread_id" payload)))))

(test format-discord-basic
  "formats a Discord outbound message"
  (let* ((msg (make-outbound-message :text "hello" :target "123"))
         (payload (format-discord-outbound msg)))
    (is (string= "hello" (gethash "content" payload)))))

(test format-irc-basic
  "formats an IRC outbound message"
  (let* ((msg (make-outbound-message :text "hello" :target "#bots"))
         (commands (format-irc-outbound msg)))
    (is (= 1 (length commands)))
    (is (search "PRIVMSG #bots :hello" (first commands)))))

;;; =======================================================================
;;; 6. Message splitting tests
;;; =======================================================================

(test split-short-message
  "short messages are not split"
  (let ((result (split-long-message "hello" 100)))
    (is (= 1 (length result)))
    (is (string= "hello" (first result)))))

(test split-long-message-test
  "long messages are split at boundaries"
  (let ((long-text (format nil "~{~A~^ ~}" (loop for i from 1 to 100 collect "word"))))
    (let ((result (split-long-message long-text 50)))
      (is (> (length result) 1))
      (is (every (lambda (chunk) (<= (length chunk) 50)) result)))))

;;; =======================================================================
;;; 7. Queue tests
;;; =======================================================================

(test queue-basic
  "message queue works"
  (let ((q (make-message-queue)))
    (is (queue-empty-p q))
    (is (= 0 (queue-length q)))
    (queue-enqueue q "a")
    (queue-enqueue q "b")
    (queue-enqueue q "c")
    (is (= 3 (queue-length q)))
    (is (not (queue-empty-p q)))
    (multiple-value-bind (item found) (queue-dequeue q)
      (is (string= "a" item))
      (is-true found))
    (is (= 2 (queue-length q)))))

(test queue-empty-dequeue
  "dequeuing from empty queue returns nil"
  (let ((q (make-message-queue)))
    (multiple-value-bind (item found) (queue-dequeue q)
      (is (null item))
      (is (null found)))))

(test queue-clear-test
  "queue clear removes all items"
  (let ((q (make-message-queue)))
    (queue-enqueue q "a")
    (queue-enqueue q "b")
    (queue-clear q)
    (is (queue-empty-p q))))

;;; =======================================================================
;;; 8. Rate-limited sender tests
;;; =======================================================================

(test rate-limited-sender-basic
  "rate-limited sender queues messages"
  (let ((sender (make-rate-limited-sender :max-per-second 10.0
                                           :max-per-minute 100.0)))
    (sender-enqueue sender "msg1")
    (sender-enqueue sender "msg2")
    (is (= 2 (sender-queue-length sender)))))

;;; =======================================================================
;;; 9. Lifecycle tests
;;; =======================================================================

(test backoff-computation
  "compute-backoff-delay increases with attempts"
  (let ((delay0 (compute-backoff-delay 0))
        (delay3 (compute-backoff-delay 3))
        (delay10 (compute-backoff-delay 10)))
    (is (> delay3 delay0))
    (is (>= delay10 delay3))))

(test channel-manager-basic
  "channel manager tracks channels"
  (let ((mgr (make-channel-manager)))
    (is (null (manager-list-channels mgr)))
    (is (null (manager-get-status mgr)))))

;;; =======================================================================
;;; 10. Account management tests
;;; =======================================================================

(test account-register-get
  "registering and getting accounts works"
  (clear-accounts)
  (let ((acct (make-channel-account :id "bot1"
                                     :channel "telegram"
                                     :bot-token "tok123")))
    (register-account acct)
    (let ((found (get-account "telegram" "bot1")))
      (is (not (null found)))
      (is (string= "tok123" (channel-account-bot-token found))))))

(test account-list-by-channel
  "listing accounts by channel works"
  (clear-accounts)
  (register-account (make-channel-account :id "tg1" :channel "telegram"))
  (register-account (make-channel-account :id "tg2" :channel "telegram"))
  (register-account (make-channel-account :id "dc1" :channel "discord"))
  (is (= 2 (length (list-accounts-for-channel "telegram"))))
  (is (= 1 (length (list-accounts-for-channel "discord")))))

(test account-resolve-from-config
  "resolving accounts from config works"
  (let ((config (make-hash-table :test 'equal))
        (channels (make-hash-table :test 'equal))
        (telegram (make-hash-table :test 'equal))
        (accounts (make-hash-table :test 'equal))
        (default-acct (make-hash-table :test 'equal)))
    (setf (gethash "token" default-acct) "bot-token-123")
    (setf (gethash "name" default-acct) "MyBot")
    (setf (gethash "default" accounts) default-acct)
    (setf (gethash "accounts" telegram) accounts)
    (setf (gethash "telegram" channels) telegram)
    (setf (gethash "channels" config) channels)
    (let ((acct (resolve-account-from-config config "telegram" "default")))
      (is (not (null acct)))
      (is (string= "bot-token-123" (channel-account-bot-token acct)))
      (is (string= "MyBot" (channel-account-display-name acct))))))

;;; =======================================================================
;;; 11. Text sanitization & mention tests
;;; =======================================================================

(test sanitize-text
  "sanitize-message-text trims whitespace"
  (is (string= "hello" (sanitize-message-text "  hello  ")))
  (is (string= "hello" (sanitize-message-text (format nil "~%hello~%")))))

(test extract-mentions-test
  "extract-mentions detects bot mentions"
  (is (extract-mentions "hey @mybot help" "mybot"))
  (is (extract-mentions "hey @MYBOT help" "mybot"))
  (is (not (extract-mentions "hey there" "mybot")))
  (is (not (extract-mentions "" "mybot"))))
