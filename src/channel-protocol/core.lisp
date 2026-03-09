;;;; core.lisp — Channel Protocol Core — unified API
;;;;
;;;; Re-exports the channel protocol subsystem.

(defpackage :cl-claw.channel-protocol
  (:use :cl)
  (:import-from :cl-claw.channel-protocol.types
                ;; Normalized message
                :normalized-message :make-normalized-message
                :normalized-message-id :normalized-message-channel
                :normalized-message-account :normalized-message-target
                :normalized-message-thread :normalized-message-sender-id
                :normalized-message-sender-name :normalized-message-text
                :normalized-message-timestamp-ms :normalized-message-reply-to-id
                :normalized-message-attachments :normalized-message-raw
                :normalized-message-agent-id
                :normalized-message-is-group-p :normalized-message-is-mention-p
                ;; Outbound message
                :outbound-message :make-outbound-message
                :outbound-message-target :outbound-message-thread
                :outbound-message-text :outbound-message-reply-to-id
                :outbound-message-attachments :outbound-message-silent-p
                :outbound-message-format :outbound-message-effect
                ;; Attachment
                :attachment :make-attachment
                :attachment-type :attachment-url :attachment-path
                :attachment-mime-type :attachment-filename
                :attachment-size-bytes :attachment-caption
                ;; Channel state
                :+channel-state-disconnected+ :+channel-state-connecting+
                :+channel-state-connected+ :+channel-state-reconnecting+
                :+channel-state-error+
                ;; Channel account
                :channel-account :make-channel-account
                :channel-account-id :channel-account-channel
                :channel-account-display-name :channel-account-bot-token
                ;; Channel info
                :channel-info :make-channel-info
                :channel-info-id :channel-info-name :channel-info-version
                ;; Channel protocol
                :channel :channel-get-info :channel-connect
                :channel-disconnect :channel-get-state
                :channel-send-message :channel-set-message-handler
                :channel-format-outbound
                ;; Rate limiter
                :rate-limiter :make-rate-limiter
                :rate-limit-check :rate-limit-record)
  (:import-from :cl-claw.channel-protocol.lifecycle
                :channel-manager :make-channel-manager
                :manager-add-channel :manager-remove-channel
                :manager-get-channel :manager-list-channels
                :manager-connect-all :manager-disconnect-all
                :manager-get-status
                :reconnect-channel :compute-backoff-delay)
  (:import-from :cl-claw.channel-protocol.normalize
                :normalize-telegram-message
                :normalize-discord-message
                :normalize-irc-message
                :extract-mentions :sanitize-message-text)
  (:import-from :cl-claw.channel-protocol.format
                :format-telegram-outbound
                :format-discord-outbound
                :format-irc-outbound
                :split-long-message
                :+telegram-max-message-length+
                :+discord-max-message-length+
                :+irc-max-message-length+)
  (:import-from :cl-claw.channel-protocol.queue
                :message-queue :make-message-queue
                :queue-enqueue :queue-dequeue :queue-length
                :queue-empty-p :queue-clear :queue-peek
                :rate-limited-sender :make-rate-limited-sender
                :sender-enqueue :sender-process-next
                :sender-process-all :sender-queue-length)
  (:import-from :cl-claw.channel-protocol.accounts
                :register-account :get-account :list-accounts
                :list-accounts-for-channel :remove-account :clear-accounts
                :resolve-account-from-config
                :resolve-telegram-account :resolve-discord-account
                :resolve-irc-account)
  (:export
   ;; Re-export everything
   ;; Types
   :normalized-message :make-normalized-message
   :normalized-message-id :normalized-message-channel
   :normalized-message-account :normalized-message-target
   :normalized-message-thread :normalized-message-sender-id
   :normalized-message-sender-name :normalized-message-text
   :normalized-message-timestamp-ms :normalized-message-reply-to-id
   :normalized-message-attachments :normalized-message-raw
   :normalized-message-agent-id
   :normalized-message-is-group-p :normalized-message-is-mention-p
   :outbound-message :make-outbound-message
   :outbound-message-target :outbound-message-thread
   :outbound-message-text :outbound-message-reply-to-id
   :outbound-message-attachments :outbound-message-silent-p
   :outbound-message-format :outbound-message-effect
   :attachment :make-attachment
   :attachment-type :attachment-url :attachment-path
   :attachment-mime-type :attachment-filename
   :attachment-size-bytes :attachment-caption
   :+channel-state-disconnected+ :+channel-state-connecting+
   :+channel-state-connected+ :+channel-state-reconnecting+
   :+channel-state-error+
   :channel-account :make-channel-account
   :channel-account-id :channel-account-channel
   :channel-account-display-name :channel-account-bot-token
   :channel-info :make-channel-info
   :channel-info-id :channel-info-name :channel-info-version
   :channel :channel-get-info :channel-connect
   :channel-disconnect :channel-get-state
   :channel-send-message :channel-set-message-handler
   :channel-format-outbound
   :rate-limiter :make-rate-limiter
   :rate-limit-check :rate-limit-record
   ;; Lifecycle
   :channel-manager :make-channel-manager
   :manager-add-channel :manager-remove-channel
   :manager-get-channel :manager-list-channels
   :manager-connect-all :manager-disconnect-all
   :manager-get-status
   :reconnect-channel :compute-backoff-delay
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
   :+discord-max-message-length+
   :+irc-max-message-length+
   ;; Queue
   :message-queue :make-message-queue
   :queue-enqueue :queue-dequeue :queue-length
   :queue-empty-p :queue-clear :queue-peek
   :rate-limited-sender :make-rate-limited-sender
   :sender-enqueue :sender-process-next
   :sender-process-all :sender-queue-length
   ;; Accounts
   :register-account :get-account :list-accounts
   :list-accounts-for-channel :remove-account :clear-accounts
   :resolve-account-from-config
   :resolve-telegram-account :resolve-discord-account
   :resolve-irc-account))

(in-package :cl-claw.channel-protocol)
