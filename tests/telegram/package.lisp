;;;; package.lisp — Telegram domain test suite
;;;;
;;;; Adapted from 62 upstream OpenClaw Telegram test specification files.
;;;; Covers: accounts, audit, bot access, bot creation, bot delivery,
;;;; bot helpers, bot media, bot message context (ACP bindings, audio
;;;; transcription, DM threads, DM topic threading, implicit mention,
;;;; named account DM, sender prefix, thread binding, topic agent-id),
;;;; bot message dispatch, bot message, bot native commands (menu, group
;;;; auth, plugin auth, session meta, skills allowlist, general),
;;;; draft chunking, draft streaming, fetch, format, format.wrap-md,
;;;; group access (base, group policy, policy access), group migration,
;;;; inline buttons, lane delivery, model buttons, monitor, network
;;;; config, network errors, probe, proxy, reaction level, reasoning
;;;; lane coordinator, sendChatAction 401 backoff, send, send.proxy,
;;;; sequential key, status reaction variants, sticker cache, targets,
;;;; target writeback, thread bindings, token, update offset store,
;;;; voice, webhook, account inspect.

(defpackage :cl-claw.telegram.tests
  (:use :cl :fiveam)
  (:export :run-telegram-tests))

(in-package :cl-claw.telegram.tests)

(declaim (optimize (safety 3) (debug 3)))

;;; ── Top-level suite ──────────────────────────────────────────────────

(def-suite :cl-claw.telegram.tests
  :description "Telegram domain test suite (62 spec files, ~699 specs)")

;;; ── Sub-suites by spec file ──────────────────────────────────────────

(def-suite :tg-accounts             :in :cl-claw.telegram.tests)
(def-suite :tg-account-inspect      :in :cl-claw.telegram.tests)
(def-suite :tg-audit                :in :cl-claw.telegram.tests)
(def-suite :tg-bot-access           :in :cl-claw.telegram.tests)
(def-suite :tg-bot-create           :in :cl-claw.telegram.tests)
(def-suite :tg-bot-delivery         :in :cl-claw.telegram.tests)
(def-suite :tg-bot-delivery-media-retry :in :cl-claw.telegram.tests)
(def-suite :tg-bot-helpers          :in :cl-claw.telegram.tests)
(def-suite :tg-bot-helpers-sub      :in :cl-claw.telegram.tests)
(def-suite :tg-bot-media-download   :in :cl-claw.telegram.tests)
(def-suite :tg-bot-media-stickers   :in :cl-claw.telegram.tests)
(def-suite :tg-bot-msg-ctx-acp      :in :cl-claw.telegram.tests)
(def-suite :tg-bot-msg-ctx-audio    :in :cl-claw.telegram.tests)
(def-suite :tg-bot-msg-ctx-dm-threads :in :cl-claw.telegram.tests)
(def-suite :tg-bot-msg-ctx-dm-topic :in :cl-claw.telegram.tests)
(def-suite :tg-bot-msg-ctx-implicit :in :cl-claw.telegram.tests)
(def-suite :tg-bot-msg-ctx-named-dm :in :cl-claw.telegram.tests)
(def-suite :tg-bot-msg-ctx-sender   :in :cl-claw.telegram.tests)
(def-suite :tg-bot-msg-ctx-thread   :in :cl-claw.telegram.tests)
(def-suite :tg-bot-msg-ctx-topic    :in :cl-claw.telegram.tests)
(def-suite :tg-bot-msg-dispatch     :in :cl-claw.telegram.tests)
(def-suite :tg-bot-msg-dispatch-sticker :in :cl-claw.telegram.tests)
(def-suite :tg-bot-message          :in :cl-claw.telegram.tests)
(def-suite :tg-bot-native-cmd-menu  :in :cl-claw.telegram.tests)
(def-suite :tg-bot-native-cmds-group-auth :in :cl-claw.telegram.tests)
(def-suite :tg-bot-native-cmds-plugin-auth :in :cl-claw.telegram.tests)
(def-suite :tg-bot-native-cmds-session :in :cl-claw.telegram.tests)
(def-suite :tg-bot-native-cmds-skills :in :cl-claw.telegram.tests)
(def-suite :tg-bot-native-cmds      :in :cl-claw.telegram.tests)
(def-suite :tg-bot                   :in :cl-claw.telegram.tests)
(def-suite :tg-draft-chunking       :in :cl-claw.telegram.tests)
(def-suite :tg-draft-stream         :in :cl-claw.telegram.tests)
(def-suite :tg-fetch                :in :cl-claw.telegram.tests)
(def-suite :tg-format               :in :cl-claw.telegram.tests)
(def-suite :tg-format-wrap-md       :in :cl-claw.telegram.tests)
(def-suite :tg-group-access-base    :in :cl-claw.telegram.tests)
(def-suite :tg-group-access-policy  :in :cl-claw.telegram.tests)
(def-suite :tg-group-access-group   :in :cl-claw.telegram.tests)
(def-suite :tg-group-migration      :in :cl-claw.telegram.tests)
(def-suite :tg-inline-buttons       :in :cl-claw.telegram.tests)
(def-suite :tg-lane-delivery        :in :cl-claw.telegram.tests)
(def-suite :tg-model-buttons        :in :cl-claw.telegram.tests)
(def-suite :tg-monitor              :in :cl-claw.telegram.tests)
(def-suite :tg-network-config       :in :cl-claw.telegram.tests)
(def-suite :tg-network-errors       :in :cl-claw.telegram.tests)
(def-suite :tg-probe                :in :cl-claw.telegram.tests)
(def-suite :tg-proxy                :in :cl-claw.telegram.tests)
(def-suite :tg-reaction-level       :in :cl-claw.telegram.tests)
(def-suite :tg-reasoning-lane       :in :cl-claw.telegram.tests)
(def-suite :tg-sendchataction-backoff :in :cl-claw.telegram.tests)
(def-suite :tg-send                 :in :cl-claw.telegram.tests)
(def-suite :tg-send-proxy           :in :cl-claw.telegram.tests)
(def-suite :tg-sequential-key       :in :cl-claw.telegram.tests)
(def-suite :tg-status-reaction      :in :cl-claw.telegram.tests)
(def-suite :tg-sticker-cache        :in :cl-claw.telegram.tests)
(def-suite :tg-targets              :in :cl-claw.telegram.tests)
(def-suite :tg-target-writeback     :in :cl-claw.telegram.tests)
(def-suite :tg-thread-bindings      :in :cl-claw.telegram.tests)
(def-suite :tg-token                :in :cl-claw.telegram.tests)
(def-suite :tg-update-offset        :in :cl-claw.telegram.tests)
(def-suite :tg-voice                :in :cl-claw.telegram.tests)
(def-suite :tg-webhook              :in :cl-claw.telegram.tests)

;;; ── Helpers ──────────────────────────────────────────────────────────

(defun run-telegram-tests ()
  "Run the complete Telegram domain test suite."
  (run! :cl-claw.telegram.tests))

(defun hash (&rest kv)
  "Create hash table from key-value pairs."
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kv by #'cddr do
      (setf (gethash k h) v))
    h))

(defun make-test-config (&rest pairs)
  "Create a test config hash table."
  (apply #'hash pairs))

(defun make-tg-config (&rest overrides)
  "Base Telegram channel config with optional overrides."
  (let ((cfg (hash "channels" (hash "telegram" (apply #'hash overrides)))))
    cfg))

(defun make-tg-account-config (&key (bot-token "") allow-from group-allow-from groups)
  "Create a Telegram account config hash."
  (let ((acct (hash "botToken" bot-token)))
    (when allow-from (setf (gethash "allowFrom" acct) allow-from))
    (when group-allow-from (setf (gethash "groupAllowFrom" acct) group-allow-from))
    (when groups (setf (gethash "groups" acct) groups))
    acct))

(defun make-tg-message (&key chat-id thread-id text (message-id 1) (date 0)
                          user-id username is-forum chat-type sticker)
  "Create a mock Telegram message/update payload."
  (let* ((chat (hash "id" (or chat-id 0)))
         (msg (hash "message_id" message-id "date" date "chat" chat
                    "text" (or text ""))))
    (when chat-type (setf (gethash "type" chat) chat-type))
    (when is-forum (setf (gethash "is_forum" chat) is-forum))
    (when thread-id (setf (gethash "message_thread_id" msg) thread-id))
    (when user-id
      (let ((user (hash "id" user-id)))
        (when username (setf (gethash "username" user) username))
        (setf (gethash "from" msg) user)))
    (when sticker (setf (gethash "sticker" msg) sticker))
    msg))

(defun make-tg-update (&key (update-id 1) message callback-query)
  "Create a mock Telegram Update object."
  (let ((upd (hash "update_id" update-id)))
    (when message (setf (gethash "message" upd) message))
    (when callback-query (setf (gethash "callback_query" upd) callback-query))
    upd))

(defvar *mock-call-log* nil
  "Accumulator for mock function calls.")

(defun reset-mocks ()
  "Clear mock call log."
  (setf *mock-call-log* nil))

(defun record-call (name &rest args)
  "Record a mock call."
  (push (cons name args) *mock-call-log*))

(defun mock-calls (name)
  "Return recorded calls for NAME."
  (remove-if-not (lambda (entry) (equal (car entry) name))
                 (reverse *mock-call-log*)))

(defun mock-call-count (name)
  "Count of calls for NAME."
  (length (mock-calls name)))

(defun string-contains-p (needle haystack)
  "Return T if HAYSTACK contains NEEDLE."
  (not (null (search needle haystack :test #'char=))))

(defun starts-with-p (prefix string)
  "Return T if STRING starts with PREFIX."
  (and (>= (length string) (length prefix))
       (string= prefix string :end2 (length prefix))))

(defun normalize-id (id)
  "Normalize account ID: downcase, replace spaces with hyphens."
  (substitute #\- #\Space (string-downcase id)))
