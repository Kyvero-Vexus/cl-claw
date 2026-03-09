;;;; normalize.lisp — Inbound message normalization
;;;;
;;;; Converts channel-specific inbound message formats into the
;;;; normalized-message representation used by the agent system.

(defpackage :cl-claw.channel-protocol.normalize
  (:use :cl)
  (:import-from :cl-claw.channel-protocol.types
                :normalized-message
                :make-normalized-message
                :attachment
                :make-attachment)
  (:export
   ;; Normalization
   :normalize-telegram-message
   :normalize-discord-message
   :normalize-irc-message

   ;; Helpers
   :extract-mentions
   :extract-reply-to
   :sanitize-message-text))

(in-package :cl-claw.channel-protocol.normalize)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Text sanitization
;;; -----------------------------------------------------------------------

(declaim (ftype (function (string) string) sanitize-message-text))
(defun sanitize-message-text (text)
  "Sanitize inbound message text.
Trims whitespace and normalizes line endings."
  (declare (type string text))
  (string-trim '(#\Space #\Tab #\Newline #\Return) text))

;;; -----------------------------------------------------------------------
;;; Mention extraction
;;; -----------------------------------------------------------------------

(declaim (ftype (function (string string) boolean) extract-mentions))
(defun extract-mentions (text bot-username)
  "Check if the text mentions the bot.
Returns T if the bot is mentioned."
  (declare (type string text bot-username))
  (when (and (plusp (length bot-username))
             (plusp (length text)))
    (let ((lower-text (string-downcase text))
          (lower-bot (string-downcase bot-username)))
      (declare (type string lower-text lower-bot))
      (not (null (search (concatenate 'string "@" lower-bot) lower-text))))))

;;; -----------------------------------------------------------------------
;;; Reply-to extraction
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table string) (or string null)) extract-reply-to))
(defun extract-reply-to (raw-message reply-key)
  "Extract reply-to message ID from raw message data."
  (declare (type hash-table raw-message)
           (type string reply-key))
  (let ((reply (gethash reply-key raw-message)))
    (when reply
      (if (hash-table-p reply)
          (let ((id (gethash "message_id" reply)))
            (when id (format nil "~A" id)))
          (format nil "~A" reply)))))

;;; -----------------------------------------------------------------------
;;; Telegram normalization
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table &key (:account string)
                                          (:agent-id string)
                                          (:bot-username string))
                          normalized-message)
                normalize-telegram-message))
(defun normalize-telegram-message (raw &key (account "default")
                                            (agent-id "main")
                                            (bot-username ""))
  "Normalize a Telegram message into the standard format."
  (declare (type hash-table raw)
           (type string account agent-id bot-username))
  (let* ((message-id (format nil "~A" (or (gethash "message_id" raw) "")))
         (chat (gethash "chat" raw))
         (chat-id (when (hash-table-p chat)
                    (format nil "~A" (or (gethash "id" chat) ""))))
         (chat-type (when (hash-table-p chat)
                      (or (gethash "type" chat) "private")))
         (from (gethash "from" raw))
         (sender-id (when (hash-table-p from)
                      (format nil "~A" (or (gethash "id" from) ""))))
         (sender-first (when (hash-table-p from)
                         (or (gethash "first_name" from) "")))
         (sender-last (when (hash-table-p from)
                        (or (gethash "last_name" from) "")))
         (sender-name (string-trim " " (format nil "~A ~A" 
                                                (or sender-first "")
                                                (or sender-last ""))))
         (text (or (gethash "text" raw) ""))
         (thread-id (let ((tid (gethash "message_thread_id" raw)))
                      (when tid (format nil "~A" tid))))
         (is-group (member chat-type '("group" "supergroup") :test #'string=))
         (is-mention (extract-mentions text bot-username))
         (reply-to (let ((reply-msg (gethash "reply_to_message" raw)))
                     (when (hash-table-p reply-msg)
                       (format nil "~A" (or (gethash "message_id" reply-msg) "")))))
         ;; Extract attachments
         (attachments (telegram-extract-attachments raw)))
    (make-normalized-message
     :id message-id
     :channel "telegram"
     :account account
     :target (or chat-id "")
     :thread thread-id
     :sender-id (or sender-id "")
     :sender-name sender-name
     :text (sanitize-message-text text)
     :timestamp-ms (let ((date (gethash "date" raw)))
                     (if date (* date 1000) 0))
     :reply-to-id reply-to
     :attachments attachments
     :raw raw
     :agent-id agent-id
     :is-group-p (if is-group t nil)
     :is-mention-p (if is-mention t nil))))

(defun telegram-extract-attachments (raw)
  "Extract attachments from a Telegram message."
  (declare (type hash-table raw))
  (let ((attachments '()))
    ;; Photo
    (let ((photo (gethash "photo" raw)))
      (when (and photo (listp photo) (plusp (length photo)))
        (let ((largest (car (last photo))))
          (when (hash-table-p largest)
            (push (make-attachment :type "image"
                                   :filename (or (gethash "file_id" largest) "")
                                   :size-bytes (or (gethash "file_size" largest) 0))
                  attachments)))))
    ;; Document
    (let ((doc (gethash "document" raw)))
      (when (hash-table-p doc)
        (push (make-attachment :type "file"
                               :filename (or (gethash "file_name" doc) "")
                               :mime-type (or (gethash "mime_type" doc) "")
                               :size-bytes (or (gethash "file_size" doc) 0))
              attachments)))
    ;; Voice
    (let ((voice (gethash "voice" raw)))
      (when (hash-table-p voice)
        (push (make-attachment :type "voice"
                               :mime-type (or (gethash "mime_type" voice) "audio/ogg")
                               :size-bytes (or (gethash "file_size" voice) 0))
              attachments)))
    ;; Audio
    (let ((audio (gethash "audio" raw)))
      (when (hash-table-p audio)
        (push (make-attachment :type "audio"
                               :filename (or (gethash "file_name" audio) "")
                               :mime-type (or (gethash "mime_type" audio) "")
                               :size-bytes (or (gethash "file_size" audio) 0))
              attachments)))
    ;; Video
    (let ((video (gethash "video" raw)))
      (when (hash-table-p video)
        (push (make-attachment :type "video"
                               :filename (or (gethash "file_name" video) "")
                               :mime-type (or (gethash "mime_type" video) "")
                               :size-bytes (or (gethash "file_size" video) 0))
              attachments)))
    ;; Sticker
    (let ((sticker (gethash "sticker" raw)))
      (when (hash-table-p sticker)
        (push (make-attachment :type "sticker"
                               :filename (or (gethash "file_id" sticker) ""))
              attachments)))
    (nreverse attachments)))

;;; -----------------------------------------------------------------------
;;; Discord normalization
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table &key (:account string)
                                          (:agent-id string)
                                          (:bot-user-id string))
                          normalized-message)
                normalize-discord-message))
(defun normalize-discord-message (raw &key (account "default")
                                           (agent-id "main")
                                           (bot-user-id ""))
  "Normalize a Discord message into the standard format."
  (declare (type hash-table raw)
           (type string account agent-id bot-user-id))
  (let* ((message-id (or (gethash "id" raw) ""))
         (channel-id (or (gethash "channel_id" raw) ""))
         (guild-id (gethash "guild_id" raw))
         (author (gethash "author" raw))
         (sender-id (when (hash-table-p author)
                      (or (gethash "id" author) "")))
         (sender-name (when (hash-table-p author)
                        (or (gethash "username" author) "")))
         (content (or (gethash "content" raw) ""))
         (thread-id (gethash "thread_id" raw))
         (is-group (not (null guild-id)))
         (is-mention (and (plusp (length bot-user-id))
                          (search (format nil "<@~A>" bot-user-id) content)))
         (referenced (gethash "referenced_message" raw))
         (reply-to (when (hash-table-p referenced)
                     (gethash "id" referenced))))
    (make-normalized-message
     :id message-id
     :channel "discord"
     :account account
     :target channel-id
     :thread (when thread-id (format nil "~A" thread-id))
     :sender-id (or sender-id "")
     :sender-name (or sender-name "")
     :text (sanitize-message-text content)
     :timestamp-ms 0  ; Discord uses ISO timestamps, would need parsing
     :reply-to-id reply-to
     :raw raw
     :agent-id agent-id
     :is-group-p is-group
     :is-mention-p (if is-mention t nil))))

;;; -----------------------------------------------------------------------
;;; IRC normalization
;;; -----------------------------------------------------------------------

(declaim (ftype (function (hash-table &key (:account string)
                                          (:agent-id string)
                                          (:bot-nick string))
                          normalized-message)
                normalize-irc-message))
(defun normalize-irc-message (raw &key (account "default")
                                       (agent-id "main")
                                       (bot-nick ""))
  "Normalize an IRC message into the standard format."
  (declare (type hash-table raw)
           (type string account agent-id bot-nick))
  (let* ((nick (or (gethash "nick" raw) ""))
         (target (or (gethash "target" raw) ""))
         (text (or (gethash "text" raw) ""))
         (is-channel (and (plusp (length target))
                          (char= (char target 0) #\#)))
         (is-mention (extract-mentions text bot-nick)))
    (make-normalized-message
     :id (format nil "irc-~A" (get-universal-time))
     :channel "irc"
     :account account
     :target target
     :sender-id nick
     :sender-name nick
     :text (sanitize-message-text text)
     :timestamp-ms (* (get-universal-time) 1000)
     :raw raw
     :agent-id agent-id
     :is-group-p is-channel
     :is-mention-p (if is-mention t nil))))
