;;;; gateway-boot-roundtrip-test.lisp — E2E: Gateway boot → channel → message round-trip
;;;;
;;;; Tests the full gateway lifecycle:
;;;; 1. Gateway server boots up (config, auth, routes)
;;;; 2. Channel connects via channel manager
;;;; 3. Message round-trip: inbound → route → handler → outbound response
;;;; 4. Session state persists across the message cycle
;;;; 5. Multi-channel routing with correct message delivery
;;;; 6. Gateway health endpoint reflects channel state

(in-package :cl-claw.e2e.tests)

(in-suite :e2e-gateway-boot-roundtrip)

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Mock roundtrip channel — tracks full send/receive cycle
;;; ═══════════════════════════════════════════════════════════════════════════

(defclass roundtrip-mock-channel (cl-claw.channel-protocol.types:channel)
  ((channel-id :initarg :channel-id :initform "rt-mock" :accessor rt-channel-id :type string)
   (connected-p :initform nil :accessor rt-connected-p :type boolean)
   (connect-count :initform 0 :accessor rt-connect-count :type fixnum)
   (messages-sent :initform '() :accessor rt-messages-sent :type list)
   (inbound-queue :initform '() :accessor rt-inbound-queue :type list)
   (lock :initform (bt:make-lock "rt-mock-lock") :accessor rt-lock :type t))
  (:documentation "Mock channel for gateway boot → message round-trip E2E testing."))

(defmethod cl-claw.channel-protocol.types:channel-get-info ((ch roundtrip-mock-channel))
  (cl-claw.channel-protocol.types:make-channel-info
   :id (rt-channel-id ch)
   :name "roundtrip-mock"
   :version "1.0.0"
   :supports '(:text :attachments)))

(defmethod cl-claw.channel-protocol.types:channel-connect ((ch roundtrip-mock-channel) account)
  (declare (type cl-claw.channel-protocol.types:channel-account account)
           (ignore account))
  (bt:with-lock-held ((rt-lock ch))
    (incf (rt-connect-count ch))
    (setf (rt-connected-p ch) t))
  (setf (slot-value ch 'cl-claw.channel-protocol.types::state)
        cl-claw.channel-protocol.types:+channel-state-connected+))

(defmethod cl-claw.channel-protocol.types:channel-disconnect ((ch roundtrip-mock-channel))
  (bt:with-lock-held ((rt-lock ch))
    (setf (rt-connected-p ch) nil))
  (setf (slot-value ch 'cl-claw.channel-protocol.types::state)
        cl-claw.channel-protocol.types:+channel-state-disconnected+))

(defmethod cl-claw.channel-protocol.types:channel-send-message ((ch roundtrip-mock-channel) outbound)
  (declare (type cl-claw.channel-protocol.types:outbound-message outbound))
  (let ((msg-id (format nil "rt-msg-~a-~a" (get-universal-time) (random 1000000))))
    (bt:with-lock-held ((rt-lock ch))
      (push (cons msg-id (cl-claw.channel-protocol.types:outbound-message-text outbound))
            (rt-messages-sent ch)))
    msg-id))

(defmethod cl-claw.channel-protocol.types:channel-format-outbound ((ch roundtrip-mock-channel) message)
  (declare (ignore message))
  (make-hash-table :test 'equal))

(defun rt-inject-inbound (ch text &key (sender-id "user-42") (sender-name "TestUser"))
  "Inject a simulated inbound message into a roundtrip mock channel.
Calls the registered message handler if present."
  (declare (type roundtrip-mock-channel ch)
           (type string text sender-id sender-name))
  (let ((msg (cl-claw.channel-protocol.types:make-normalized-message
              :id (format nil "in-~a-~a" (get-universal-time) (random 1000000))
              :channel (rt-channel-id ch)
              :text text
              :sender-id sender-id
              :sender-name sender-name)))
    (bt:with-lock-held ((rt-lock ch))
      (push msg (rt-inbound-queue ch)))
    ;; Dispatch to handler
    (let ((handler (slot-value ch 'cl-claw.channel-protocol.types::message-handler)))
      (when handler
        (funcall handler msg)))
    msg))

(defun rt-get-sent-messages (ch)
  "Get list of (msg-id . text) pairs sent through this channel."
  (declare (type roundtrip-mock-channel ch))
  (bt:with-lock-held ((rt-lock ch))
    (copy-list (rt-messages-sent ch))))

(defun rt-clear-sent (ch)
  "Clear sent message history."
  (declare (type roundtrip-mock-channel ch))
  (bt:with-lock-held ((rt-lock ch))
    (setf (rt-messages-sent ch) nil)))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 1: Gateway boots, channel connects, message round-trips
;;; ═══════════════════════════════════════════════════════════════════════════

(test gateway-boot-channel-connect-roundtrip
  "Full lifecycle: gateway boots → channel connects → message sent → response received."
  (let* ((tmp-dir (format nil "/tmp/cl-claw-e2e-rt-~a/" (get-universal-time)))
         ;; 1. Boot gateway server
         (server-config (cl-claw.gateway.server:make-gateway-server-config
                         :host "127.0.0.1"
                         :port 13578  ; test port
                         :auth-mode :none))
         (server (cl-claw.gateway.server:make-gateway-server :config server-config))
         ;; 2. Set up channel manager + mock channel
         (manager (cl-claw.channel-protocol.lifecycle:make-channel-manager))
         (ch (make-instance 'roundtrip-mock-channel :channel-id "telegram"))
         (acct (make-mock-account "tg-bot"))
         ;; 3. Set up session store
         (store (cl-claw.sessions.store:create-session-store :root-dir tmp-dir))
         ;; 4. Set up route table
         (route-table (cl-claw.routing:create-route-table))
         ;; Track received messages for round-trip verification
         (received-messages '())
         (received-lock (bt:make-lock "received")))
    (unwind-protect
         (progn
           ;; === Phase 1: Gateway Boot ===
           (cl-claw.gateway.server:start-gateway-server server)
           (is (cl-claw.gateway.server:gateway-server-running-p server)
               "Gateway server is running after boot")

           ;; Verify health endpoint route exists
           (let ((health-route (cl-claw.gateway.server:dispatch-request server "GET" "/health")))
             (is (not (null health-route))
                 "Health route registered after boot"))

           ;; === Phase 2: Channel Connection ===
           (cl-claw.channel-protocol.lifecycle:manager-add-channel manager "telegram" ch acct)
           (cl-claw.channel-protocol.lifecycle:manager-connect-all manager)

           (is (eq :connected (cl-claw.channel-protocol.types:channel-get-state ch))
               "Channel is connected after manager-connect-all")
           (is (= 1 (rt-connect-count ch))
               "Channel connected exactly once")

           ;; === Phase 3: Set up message handler (echo bot) ===
           ;; Simulates the gateway routing: receive inbound → process → respond
           (cl-claw.channel-protocol.types:channel-set-message-handler
            ch
            (lambda (msg)
              (let* ((text (cl-claw.channel-protocol.types:normalized-message-text msg))
                     (sender (cl-claw.channel-protocol.types:normalized-message-sender-id msg))
                     (channel-id (cl-claw.channel-protocol.types:normalized-message-channel msg))
                     ;; Route the inbound message
                     (route-entry (cl-claw.routing:resolve-route-for-inbound
                                   route-table channel-id "default" sender))
                     (session-key (cl-claw.routing:make-session-key
                                   channel-id "default" sender))
                     ;; Record in session store
                     (_ (cl-claw.sessions.store:session-store-upsert
                         store session-key
                         :message-count (1+ (let ((existing (cl-claw.sessions.store:session-store-get
                                                             store session-key)))
                                              (if existing
                                                  (cl-claw.sessions.store:session-entry-message-count existing)
                                                  0)))))
                     ;; Generate response
                     (response-text (format nil "Echo: ~a" text)))
                (declare (ignore _ route-entry))
                ;; Track received
                (bt:with-lock-held (received-lock)
                  (push (cons session-key text) received-messages))
                ;; Send response back through channel
                (cl-claw.channel-protocol.types:channel-send-message
                 ch
                 (cl-claw.channel-protocol.types:make-outbound-message
                  :target sender
                  :text response-text)))))

           ;; === Phase 4: Message Round-Trip ===
           (rt-inject-inbound ch "Hello gateway!" :sender-id "user-42" :sender-name "Alice")

           ;; Verify inbound was received
           (is (= 1 (length received-messages))
               "One inbound message received by handler")
           (is (string= "Hello gateway!" (cdar received-messages))
               "Inbound message text matches")

           ;; Verify outbound response was sent
           (let ((sent (rt-get-sent-messages ch)))
             (is (= 1 (length sent))
                 "One outbound message sent")
             (is (string= "Echo: Hello gateway!" (cdar sent))
                 "Response text is correct echo"))

           ;; Verify session state was recorded
           (let* ((session-key (cl-claw.routing:make-session-key "telegram" "default" "user-42"))
                  (entry (cl-claw.sessions.store:session-store-get store session-key)))
             (is (not (null entry))
                 "Session entry created for the message exchange")
             (is (= 1 (cl-claw.sessions.store:session-entry-message-count entry))
                 "Session message count is 1 after first exchange"))

           ;; === Phase 5: Second message — verify session accumulation ===
           (rt-inject-inbound ch "Second message" :sender-id "user-42" :sender-name "Alice")

           (is (= 2 (length received-messages))
               "Two inbound messages received total")

           (let* ((session-key (cl-claw.routing:make-session-key "telegram" "default" "user-42"))
                  (entry (cl-claw.sessions.store:session-store-get store session-key)))
             (is (= 2 (cl-claw.sessions.store:session-entry-message-count entry))
                 "Session message count incremented to 2"))

           (let ((sent (rt-get-sent-messages ch)))
             (is (= 2 (length sent))
                 "Two outbound messages sent total")))

      ;; Cleanup
      (cl-claw.gateway.server:stop-gateway-server server)
      (cl-claw.channel-protocol.lifecycle:manager-disconnect-all manager)
      (ignore-errors
       (uiop:delete-directory-tree
        (uiop:ensure-directory-pathname tmp-dir)
        :validate t :if-does-not-exist :ignore)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 2: Gateway boot with BOOT.md triggers agent and channel connects
;;; ═══════════════════════════════════════════════════════════════════════════

(test gateway-boot-with-bootmd-then-channel-roundtrip
  "Gateway reads BOOT.md during boot, then channels connect and messages flow."
  (let* ((tmp-dir (format nil "/tmp/cl-claw-e2e-bootmd-rt-~a/" (get-universal-time)))
         (boot-path (merge-pathnames "BOOT.md" (uiop:ensure-directory-pathname tmp-dir)))
         (boot-agent-ran nil)
         (boot-content nil))
    (unwind-protect
         (progn
           ;; Create BOOT.md
           (ensure-directories-exist boot-path)
           (with-open-file (out boot-path :direction :output :if-exists :supersede)
             (write-string "Initialize all channels" out))

           ;; Run boot sequence
           (let ((boot-result (cl-claw.gateway.boot:run-boot-once
                               :base-dir tmp-dir
                               :run-agent-fn (lambda (session-id content)
                                               (declare (ignore session-id))
                                               (setf boot-agent-ran t
                                                     boot-content content))
                               :session-id-fn (lambda () "boot-e2e-session"))))
             (is (eq :completed (cl-claw.gateway.boot:boot-result-status boot-result))
                 "Boot sequence completed")
             (is (eq t boot-agent-ran)
                 "Boot agent function was called")
             (is (string= "Initialize all channels" boot-content)
                 "Boot agent received correct BOOT.md content"))

           ;; Now boot the gateway server
           (let* ((server (cl-claw.gateway.server:make-gateway-server
                           :config (cl-claw.gateway.server:make-gateway-server-config
                                    :auth-mode :none)))
                  (manager (cl-claw.channel-protocol.lifecycle:make-channel-manager))
                  (ch (make-instance 'roundtrip-mock-channel :channel-id "discord"))
                  (acct (make-mock-account "dc-bot"))
                  (response-received nil))

             (cl-claw.gateway.server:start-gateway-server server)
             (cl-claw.channel-protocol.lifecycle:manager-add-channel manager "discord" ch acct)
             (cl-claw.channel-protocol.lifecycle:manager-connect-all manager)

             ;; Set up handler and send message
             (cl-claw.channel-protocol.types:channel-set-message-handler
              ch
              (lambda (msg)
                (cl-claw.channel-protocol.types:channel-send-message
                 ch
                 (cl-claw.channel-protocol.types:make-outbound-message
                  :target (cl-claw.channel-protocol.types:normalized-message-sender-id msg)
                  :text (format nil "Booted! ~a"
                                (cl-claw.channel-protocol.types:normalized-message-text msg))))
                (setf response-received t)))

             (rt-inject-inbound ch "ping" :sender-id "user-1")

             (is (eq t response-received)
                 "Handler processed message after boot")
             (let ((sent (rt-get-sent-messages ch)))
               (is (= 1 (length sent))
                   "One response sent")
               (is (string= "Booted! ping" (cdar sent))
                   "Response includes boot confirmation"))

             ;; Cleanup server
             (cl-claw.gateway.server:stop-gateway-server server)
             (cl-claw.channel-protocol.lifecycle:manager-disconnect-all manager)))

      (ignore-errors
       (uiop:delete-directory-tree
        (uiop:ensure-directory-pathname tmp-dir)
        :validate t :if-does-not-exist :ignore)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 3: Multi-channel message routing — different users, different channels
;;; ═══════════════════════════════════════════════════════════════════════════

(test gateway-multi-channel-routing-roundtrip
  "Messages route correctly across multiple channels with independent sessions."
  (let* ((tmp-dir (format nil "/tmp/cl-claw-e2e-multi-rt-~a/" (get-universal-time)))
         (store (cl-claw.sessions.store:create-session-store :root-dir tmp-dir))
         (route-table (cl-claw.routing:create-route-table))
         (manager (cl-claw.channel-protocol.lifecycle:make-channel-manager))
         (ch-tg (make-instance 'roundtrip-mock-channel :channel-id "telegram"))
         (ch-dc (make-instance 'roundtrip-mock-channel :channel-id "discord"))
         (ch-irc (make-instance 'roundtrip-mock-channel :channel-id "irc")))
    (unwind-protect
         (progn
           ;; Register all channels
           (cl-claw.channel-protocol.lifecycle:manager-add-channel
            manager "telegram" ch-tg (make-mock-account "tg-bot"))
           (cl-claw.channel-protocol.lifecycle:manager-add-channel
            manager "discord" ch-dc (make-mock-account "dc-bot"))
           (cl-claw.channel-protocol.lifecycle:manager-add-channel
            manager "irc" ch-irc (make-mock-account "irc-bot"))
           (cl-claw.channel-protocol.lifecycle:manager-connect-all manager)

           ;; Verify all connected
           (is (eq :connected (cl-claw.channel-protocol.types:channel-get-state ch-tg))
               "Telegram connected")
           (is (eq :connected (cl-claw.channel-protocol.types:channel-get-state ch-dc))
               "Discord connected")
           (is (eq :connected (cl-claw.channel-protocol.types:channel-get-state ch-irc))
               "IRC connected")

           ;; Set up echo handlers on each channel (with channel tag)
           (dolist (ch (list ch-tg ch-dc ch-irc))
             (let ((my-ch ch))
               (cl-claw.channel-protocol.types:channel-set-message-handler
                my-ch
                (lambda (msg)
                  (let* ((channel-id (cl-claw.channel-protocol.types:normalized-message-channel msg))
                         (sender (cl-claw.channel-protocol.types:normalized-message-sender-id msg))
                         (text (cl-claw.channel-protocol.types:normalized-message-text msg))
                         (session-key (cl-claw.routing:make-session-key channel-id "default" sender)))
                    ;; Remember route
                    (cl-claw.routing:remember-route
                     route-table
                     (cl-claw.routing:make-route-entry
                      :provider channel-id :account "default" :target sender))
                    ;; Update session
                    (cl-claw.sessions.store:session-store-upsert
                     store session-key :message-count 1)
                    ;; Respond
                    (cl-claw.channel-protocol.types:channel-send-message
                     my-ch
                     (cl-claw.channel-protocol.types:make-outbound-message
                      :target sender
                      :text (format nil "[~a] ~a" channel-id text))))))))

           ;; Send messages on each channel from different users
           (rt-inject-inbound ch-tg "hello from telegram" :sender-id "tg-user-1")
           (rt-inject-inbound ch-dc "hello from discord" :sender-id "dc-user-1")
           (rt-inject-inbound ch-irc "hello from irc" :sender-id "irc-user-1")

           ;; Verify responses on correct channels
           (let ((tg-sent (rt-get-sent-messages ch-tg))
                 (dc-sent (rt-get-sent-messages ch-dc))
                 (irc-sent (rt-get-sent-messages ch-irc)))
             (is (= 1 (length tg-sent)) "Telegram got 1 response")
             (is (= 1 (length dc-sent)) "Discord got 1 response")
             (is (= 1 (length irc-sent)) "IRC got 1 response")
             (is (string= "[telegram] hello from telegram" (cdar tg-sent))
                 "Telegram response correct")
             (is (string= "[discord] hello from discord" (cdar dc-sent))
                 "Discord response correct")
             (is (string= "[irc] hello from irc" (cdar irc-sent))
                 "IRC response correct"))

           ;; Verify independent sessions were created
           (let ((tg-key (cl-claw.routing:make-session-key "telegram" "default" "tg-user-1"))
                 (dc-key (cl-claw.routing:make-session-key "discord" "default" "dc-user-1"))
                 (irc-key (cl-claw.routing:make-session-key "irc" "default" "irc-user-1")))
             (is (not (null (cl-claw.sessions.store:session-store-get store tg-key)))
                 "Telegram session exists")
             (is (not (null (cl-claw.sessions.store:session-store-get store dc-key)))
                 "Discord session exists")
             (is (not (null (cl-claw.sessions.store:session-store-get store irc-key)))
                 "IRC session exists"))

           ;; Verify routes were remembered
           (let ((tg-route (cl-claw.routing:resolve-route
                            route-table
                            (cl-claw.routing:make-session-key "telegram" "default" "tg-user-1"))))
             (is (not (null tg-route))
                 "Telegram route remembered")
             (is (string= "telegram" (cl-claw.routing:route-entry-provider tg-route))
                 "Route provider is telegram")))

      ;; Cleanup
      (cl-claw.channel-protocol.lifecycle:manager-disconnect-all manager)
      (ignore-errors
       (uiop:delete-directory-tree
        (uiop:ensure-directory-pathname tmp-dir)
        :validate t :if-does-not-exist :ignore)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 4: Gateway server auth + channel message flow
;;; ═══════════════════════════════════════════════════════════════════════════

(test gateway-auth-then-channel-roundtrip
  "Gateway enforces auth on control plane while channels process messages freely."
  (let* ((server-config (cl-claw.gateway.server:make-gateway-server-config
                         :auth-mode :token
                         :auth-token "test-secret-token-xyz"))
         (server (cl-claw.gateway.server:make-gateway-server :config server-config))
         (manager (cl-claw.channel-protocol.lifecycle:make-channel-manager))
         (ch (make-instance 'roundtrip-mock-channel :channel-id "telegram"))
         (acct (make-mock-account "tg-bot"))
         (handler-called nil))
    (unwind-protect
         (progn
           ;; Boot gateway with token auth
           (cl-claw.gateway.server:start-gateway-server server)
           (is (cl-claw.gateway.server:gateway-server-running-p server)
               "Server running with token auth")

           ;; Verify auth works — valid token
           (let ((auth-result (cl-claw.gateway.server:authenticate-request
                               server-config
                               '(("authorization" . "Bearer test-secret-token-xyz")))))
             (is (cl-claw.gateway.server:auth-result-authenticated-p auth-result)
                 "Valid token authenticates"))

           ;; Verify auth works — invalid token
           (let ((auth-result (cl-claw.gateway.server:authenticate-request
                               server-config
                               '(("authorization" . "Bearer wrong-token")))))
             (is (not (cl-claw.gateway.server:auth-result-authenticated-p auth-result))
                 "Invalid token rejected")
             (is (string= "token-mismatch"
                           (cl-claw.gateway.server:auth-result-reason auth-result))
                 "Rejection reason is token-mismatch"))

           ;; Now connect channel and verify messages flow independently of auth
           (cl-claw.channel-protocol.lifecycle:manager-add-channel manager "telegram" ch acct)
           (cl-claw.channel-protocol.lifecycle:manager-connect-all manager)

           (cl-claw.channel-protocol.types:channel-set-message-handler
            ch
            (lambda (msg)
              (declare (ignore msg))
              (setf handler-called t)
              (cl-claw.channel-protocol.types:channel-send-message
               ch
               (cl-claw.channel-protocol.types:make-outbound-message
                :target "user-1"
                :text "Authenticated gateway response"))))

           (rt-inject-inbound ch "test" :sender-id "user-1")

           (is (eq t handler-called)
               "Message handler called despite auth being on control plane")
           (is (= 1 (length (rt-get-sent-messages ch)))
               "Response sent through channel"))

      (cl-claw.gateway.server:stop-gateway-server server)
      (cl-claw.channel-protocol.lifecycle:manager-disconnect-all manager))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 5: Gateway shutdown cleans up channels
;;; ═══════════════════════════════════════════════════════════════════════════

(test gateway-shutdown-disconnects-channels
  "Gateway shutdown disconnects all channels cleanly."
  (let* ((server (cl-claw.gateway.server:make-gateway-server
                  :config (cl-claw.gateway.server:make-gateway-server-config :auth-mode :none)))
         (manager (cl-claw.channel-protocol.lifecycle:make-channel-manager))
         (ch1 (make-instance 'roundtrip-mock-channel :channel-id "telegram"))
         (ch2 (make-instance 'roundtrip-mock-channel :channel-id "discord")))
    ;; Boot and connect
    (cl-claw.gateway.server:start-gateway-server server)
    (cl-claw.channel-protocol.lifecycle:manager-add-channel manager "telegram" ch1 (make-mock-account "tg"))
    (cl-claw.channel-protocol.lifecycle:manager-add-channel manager "discord" ch2 (make-mock-account "dc"))
    (cl-claw.channel-protocol.lifecycle:manager-connect-all manager)

    (is (eq :connected (cl-claw.channel-protocol.types:channel-get-state ch1))
        "Channel 1 connected")
    (is (eq :connected (cl-claw.channel-protocol.types:channel-get-state ch2))
        "Channel 2 connected")

    ;; Shutdown
    (cl-claw.gateway.server:stop-gateway-server server)
    (cl-claw.channel-protocol.lifecycle:manager-disconnect-all manager)

    (is (not (cl-claw.gateway.server:gateway-server-running-p server))
        "Gateway not running after shutdown")
    (is (eq :disconnected (cl-claw.channel-protocol.types:channel-get-state ch1))
        "Channel 1 disconnected after shutdown")
    (is (eq :disconnected (cl-claw.channel-protocol.types:channel-get-state ch2))
        "Channel 2 disconnected after shutdown")))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 6: Concurrent message round-trips across channels
;;; ═══════════════════════════════════════════════════════════════════════════

(test gateway-concurrent-roundtrip
  "Multiple messages round-trip concurrently without data corruption."
  (let* ((tmp-dir (format nil "/tmp/cl-claw-e2e-conc-rt-~a/" (get-universal-time)))
         (store (cl-claw.sessions.store:create-session-store :root-dir tmp-dir))
         (manager (cl-claw.channel-protocol.lifecycle:make-channel-manager))
         (ch (make-instance 'roundtrip-mock-channel :channel-id "telegram"))
         (num-messages 50)
         (responses-lock (bt:make-lock "responses"))
         (responses '())
         (errors '())
         (errors-lock (bt:make-lock "errors")))
    (unwind-protect
         (progn
           (cl-claw.channel-protocol.lifecycle:manager-add-channel
            manager "telegram" ch (make-mock-account "tg"))
           (cl-claw.channel-protocol.lifecycle:manager-connect-all manager)

           ;; Handler: echo with sequence number
           (cl-claw.channel-protocol.types:channel-set-message-handler
            ch
            (lambda (msg)
              (let ((text (cl-claw.channel-protocol.types:normalized-message-text msg))
                    (sender (cl-claw.channel-protocol.types:normalized-message-sender-id msg)))
                ;; Update session
                (let ((session-key (cl-claw.routing:make-session-key "telegram" "default" sender)))
                  (cl-claw.sessions.store:session-store-upsert store session-key :message-count 1))
                ;; Send response
                (let ((msg-id (cl-claw.channel-protocol.types:channel-send-message
                               ch
                               (cl-claw.channel-protocol.types:make-outbound-message
                                :target sender
                                :text (format nil "re:~a" text)))))
                  (bt:with-lock-held (responses-lock)
                    (push msg-id responses))))))

           ;; Fire messages concurrently from multiple threads
           (let ((threads
                   (loop for i from 0 below num-messages
                         collect (let ((my-i i))
                                   (bt:make-thread
                                    (lambda ()
                                      (handler-case
                                          (rt-inject-inbound
                                           ch
                                           (format nil "msg-~a" my-i)
                                           :sender-id (format nil "user-~a" (mod my-i 10)))
                                        (error (e)
                                          (bt:with-lock-held (errors-lock)
                                            (push (format nil "~a" e) errors)))))
                                    :name (format nil "sender-~a" i))))))
             (dolist (th threads)
               (bt:join-thread th)))

           (is (null errors)
               "No errors during concurrent round-trip: ~a" errors)
           (is (= num-messages (length responses))
               "All ~a messages got responses (got ~a)" num-messages (length responses))
           (is (= num-messages (length (rt-get-sent-messages ch)))
               "All ~a outbound messages recorded" num-messages))

      (cl-claw.channel-protocol.lifecycle:manager-disconnect-all manager)
      (ignore-errors
       (uiop:delete-directory-tree
        (uiop:ensure-directory-pathname tmp-dir)
        :validate t :if-does-not-exist :ignore)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 7: Session key round-trip — parse ↔ make are inverse
;;; ═══════════════════════════════════════════════════════════════════════════

(test gateway-session-key-roundtrip
  "Session keys survive make → parse → make round-trip consistently."
  (let* ((key1 (cl-claw.routing:make-session-key "telegram" "default" "user-42"))
         (parsed (cl-claw.routing:parse-session-key key1))
         (key2 (cl-claw.routing:make-session-key
                (cl-claw.routing:parsed-session-key-provider parsed)
                (cl-claw.routing:parsed-session-key-account parsed)
                (cl-claw.routing:parsed-session-key-target parsed)
                :agent-id (cl-claw.routing:parsed-session-key-agent-id parsed))))
    (is (string= key1 key2)
        "Session key round-trips: ~a = ~a" key1 key2)
    (is (string= "telegram" (cl-claw.routing:parsed-session-key-provider parsed))
        "Provider parsed correctly")
    (is (string= "default" (cl-claw.routing:parsed-session-key-account parsed))
        "Account parsed correctly")
    (is (string= "user-42" (cl-claw.routing:parsed-session-key-target parsed))
        "Target parsed correctly")))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 8: Channel manager status reflects gateway state through lifecycle
;;; ═══════════════════════════════════════════════════════════════════════════

(test gateway-manager-status-lifecycle
  "Channel manager status accurately tracks state through full gateway lifecycle."
  (let ((manager (cl-claw.channel-protocol.lifecycle:make-channel-manager))
        (ch (make-instance 'roundtrip-mock-channel :channel-id "telegram")))
    ;; Pre-connect
    (cl-claw.channel-protocol.lifecycle:manager-add-channel
     manager "telegram" ch (make-mock-account "tg"))
    (let ((status (cl-claw.channel-protocol.lifecycle:manager-get-status manager)))
      (is (eq :disconnected (cdr (assoc "telegram" status :test #'string=)))
          "Status is disconnected before connect"))

    ;; Post-connect
    (cl-claw.channel-protocol.lifecycle:manager-connect-all manager)
    (let ((status (cl-claw.channel-protocol.lifecycle:manager-get-status manager)))
      (is (eq :connected (cdr (assoc "telegram" status :test #'string=)))
          "Status is connected after connect"))

    ;; Send a message while connected
    (cl-claw.channel-protocol.types:channel-send-message
     ch
     (cl-claw.channel-protocol.types:make-outbound-message :target "u" :text "test"))
    (let ((status (cl-claw.channel-protocol.lifecycle:manager-get-status manager)))
      (is (eq :connected (cdr (assoc "telegram" status :test #'string=)))
          "Status remains connected after sending"))

    ;; Post-disconnect
    (cl-claw.channel-protocol.lifecycle:manager-disconnect-all manager)
    (let ((status (cl-claw.channel-protocol.lifecycle:manager-get-status manager)))
      (is (eq :disconnected (cdr (assoc "telegram" status :test #'string=)))
          "Status is disconnected after disconnect"))))
