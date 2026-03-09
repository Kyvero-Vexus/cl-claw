;;;; accounts.lisp — Channel account management
;;;;
;;;; Manages channel accounts (bot tokens, credentials) and provides
;;;; account resolution from configuration.

(defpackage :cl-claw.channel-protocol.accounts
  (:use :cl)
  (:import-from :cl-claw.channel-protocol.types
                :channel-account
                :make-channel-account
                :channel-account-id
                :channel-account-channel
                :channel-account-display-name
                :channel-account-bot-token)
  (:export
   ;; Account store
   :*account-store*
   :register-account
   :get-account
   :list-accounts
   :list-accounts-for-channel
   :remove-account
   :clear-accounts

   ;; Account resolution
   :resolve-account-from-config
   :resolve-telegram-account
   :resolve-discord-account
   :resolve-irc-account))

(in-package :cl-claw.channel-protocol.accounts)

(declaim (optimize (safety 3) (debug 3)))

;;; -----------------------------------------------------------------------
;;; Account store
;;; -----------------------------------------------------------------------

(defvar *account-store* (make-hash-table :test 'equal)
  "Global account store: account-key -> channel-account.
Key format: 'channel:account-id'")

(defun account-key (channel account-id)
  "Generate a store key from channel and account ID."
  (format nil "~A:~A" channel account-id))

(defun register-account (account)
  "Register a channel account."
  (declare (type channel-account account))
  (let ((key (account-key (channel-account-channel account)
                           (channel-account-id account))))
    (setf (gethash key *account-store*) account))
  (values))

(defun get-account (channel account-id)
  "Get a channel account by channel name and account ID."
  (declare (type string channel account-id))
  (gethash (account-key channel account-id) *account-store*))

(defun list-accounts ()
  "List all registered accounts."
  (let ((accounts '()))
    (maphash (lambda (k v) (declare (ignore k)) (push v accounts))
             *account-store*)
    accounts))

(defun list-accounts-for-channel (channel)
  "List accounts for a specific channel."
  (declare (type string channel))
  (let ((accounts '()))
    (maphash (lambda (k v)
               (declare (ignore k))
               (when (string= channel (channel-account-channel v))
                 (push v accounts)))
             *account-store*)
    accounts))

(defun remove-account (channel account-id)
  "Remove a channel account."
  (declare (type string channel account-id))
  (remhash (account-key channel account-id) *account-store*)
  (values))

(defun clear-accounts ()
  "Clear all registered accounts."
  (clrhash *account-store*)
  (values))

;;; -----------------------------------------------------------------------
;;; Account resolution from config
;;; -----------------------------------------------------------------------

(defun resolve-account-from-config (config channel-name account-id)
  "Resolve a channel account from OpenClaw config hash-table."
  (declare (type hash-table config)
           (type string channel-name account-id))
  (let* ((channels (gethash "channels" config))
         (channel-cfg (when (hash-table-p channels)
                        (gethash channel-name channels)))
         (accounts (when (hash-table-p channel-cfg)
                     (gethash "accounts" channel-cfg)))
         (account-cfg (when (hash-table-p accounts)
                        (gethash account-id accounts))))
    (when (hash-table-p account-cfg)
      (make-channel-account
       :id account-id
       :channel channel-name
       :display-name (or (gethash "displayName" account-cfg)
                         (gethash "name" account-cfg)
                         account-id)
       :bot-token (or (gethash "token" account-cfg)
                      (gethash "botToken" account-cfg))
       :extra account-cfg))))

(defun resolve-telegram-account (config &optional (account-id "default"))
  "Resolve a Telegram account from config."
  (declare (type hash-table config)
           (type string account-id))
  (resolve-account-from-config config "telegram" account-id))

(defun resolve-discord-account (config &optional (account-id "default"))
  "Resolve a Discord account from config."
  (declare (type hash-table config)
           (type string account-id))
  (resolve-account-from-config config "discord" account-id))

(defun resolve-irc-account (config &optional (account-id "default"))
  "Resolve an IRC account from config."
  (declare (type hash-table config)
           (type string account-id))
  (resolve-account-from-config config "irc" account-id))
