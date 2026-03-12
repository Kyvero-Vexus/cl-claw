;;;; crash-recovery-test.lisp — E2E: Crash recovery & reconnection
;;;;
;;;; Tests the full crash-recovery lifecycle:
;;;; 1. Session state persists across simulated crashes
;;;; 2. Channel reconnection with exponential backoff
;;;; 3. Stale process cleanup (lsof parsing)
;;;; 4. Boot sequence recovery (BOOT.md lifecycle)
;;;; 5. Retry exhaustion and error propagation
;;;; 6. Channel manager recovery after disconnect

(in-package :cl-claw.e2e.tests)

(in-suite :e2e-crash-recovery)

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Mock channel implementation for E2E testing
;;; ═══════════════════════════════════════════════════════════════════════════

(defclass mock-channel (cl-claw.channel-protocol.types:channel)
  ((connect-count :initform 0 :accessor mock-connect-count :type fixnum)
   (disconnect-count :initform 0 :accessor mock-disconnect-count :type fixnum)
   (fail-connects :initform 0 :accessor mock-fail-connects :type fixnum
                  :documentation "Number of connect calls that should fail before succeeding")
   (messages-sent :initform '() :accessor mock-messages-sent :type list)
   (channel-id :initarg :channel-id :initform "mock-1" :accessor mock-channel-id :type string))
  (:documentation "Mock channel for E2E crash recovery testing."))

(defmethod cl-claw.channel-protocol.types:channel-get-info ((ch mock-channel))
  (cl-claw.channel-protocol.types:make-channel-info
   :id (mock-channel-id ch)
   :name "mock"
   :version "1.0.0"
   :supports '(:text :attachments)))

(defmethod cl-claw.channel-protocol.types:channel-connect ((ch mock-channel) account)
  (declare (type cl-claw.channel-protocol.types:channel-account account))
  (incf (mock-connect-count ch))
  (cond
    ((> (mock-fail-connects ch) 0)
     (decf (mock-fail-connects ch))
     (setf (slot-value ch 'cl-claw.channel-protocol.types::state)
           cl-claw.channel-protocol.types:+channel-state-error+)
     (error "Mock connection failure (deliberate)"))
    (t
     (setf (slot-value ch 'cl-claw.channel-protocol.types::state)
           cl-claw.channel-protocol.types:+channel-state-connected+))))

(defmethod cl-claw.channel-protocol.types:channel-disconnect ((ch mock-channel))
  (incf (mock-disconnect-count ch))
  (setf (slot-value ch 'cl-claw.channel-protocol.types::state)
        cl-claw.channel-protocol.types:+channel-state-disconnected+))

(defmethod cl-claw.channel-protocol.types:channel-send-message ((ch mock-channel) outbound)
  (declare (type cl-claw.channel-protocol.types:outbound-message outbound))
  (push (cl-claw.channel-protocol.types:outbound-message-text outbound)
        (mock-messages-sent ch))
  (format nil "mock-msg-~a" (length (mock-messages-sent ch))))

(defmethod cl-claw.channel-protocol.types:channel-format-outbound ((ch mock-channel) message)
  (declare (ignore message))
  (make-hash-table :test 'equal))

(defun make-mock-account (&optional (id "mock-acct"))
  "Create a mock channel account for testing."
  (cl-claw.channel-protocol.types:make-channel-account
   :id id
   :channel "mock"
   :display-name "Mock Bot"
   :bot-token "mock-token-12345"))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 1: Session state persists across simulated crash
;;; ═══════════════════════════════════════════════════════════════════════════

(test crash-recovery-session-persistence
  "Session state survives crash: create session, save to disk, reload from disk."
  (let* ((tmp-dir (format nil "/tmp/cl-claw-e2e-~a/" (get-universal-time)))
         (store (cl-claw.sessions.store:create-session-store :root-dir tmp-dir)))
    (unwind-protect
         (progn
           ;; Create a session and record some state
           (cl-claw.sessions.store:session-store-upsert
            store "agent:main:telegram"
            :message-count 42)

           ;; Verify it's in memory
           (let ((entry (cl-claw.sessions.store:session-store-get store "agent:main:telegram")))
             (is (not (null entry))
                 "Session entry exists in memory after upsert")
             (is (= 42 (cl-claw.sessions.store:session-entry-message-count entry))
                 "Message count is correct before crash"))

           ;; Simulate crash: create a fresh store from the same directory (disk reload)
           (let* ((store-2 (cl-claw.sessions.store:create-session-store :root-dir tmp-dir))
                  (recovered (cl-claw.sessions.store:session-store-get
                              store-2 "agent:main:telegram")))
             (is (not (null recovered))
                 "Session entry recovered from disk after simulated crash")
             (is (= 42 (cl-claw.sessions.store:session-entry-message-count recovered))
                 "Message count preserved across crash boundary")
             (is (string= (cl-claw.sessions.store:session-entry-key recovered)
                           (cl-claw.sessions.store:normalize-session-key "agent:main:telegram"))
                 "Session key normalized consistently across crash")))
      ;; Cleanup
      (ignore-errors
       (uiop:delete-directory-tree
        (uiop:ensure-directory-pathname tmp-dir)
        :validate t :if-does-not-exist :ignore)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 2: Multiple sessions survive crash
;;; ═══════════════════════════════════════════════════════════════════════════

(test crash-recovery-multiple-sessions
  "Multiple sessions persist independently across simulated crash."
  (let* ((tmp-dir (format nil "/tmp/cl-claw-e2e-multi-~a/" (get-universal-time)))
         (store (cl-claw.sessions.store:create-session-store :root-dir tmp-dir)))
    (unwind-protect
         (progn
           ;; Create multiple sessions simulating different channels
           (cl-claw.sessions.store:session-store-upsert
            store "agent:main:telegram" :message-count 100)
           (cl-claw.sessions.store:session-store-upsert
            store "agent:main:discord" :message-count 200)
           (cl-claw.sessions.store:session-store-upsert
            store "agent:bot:irc" :message-count 50)

           ;; Simulate crash and reload
           (let ((store-2 (cl-claw.sessions.store:create-session-store :root-dir tmp-dir)))
             (is (= 3 (length (cl-claw.sessions.store:session-store-list store-2)))
                 "All three sessions recovered after crash")

             ;; Verify each session independently
             (let ((tg (cl-claw.sessions.store:session-store-get store-2 "agent:main:telegram"))
                   (dc (cl-claw.sessions.store:session-store-get store-2 "agent:main:discord"))
                   (irc (cl-claw.sessions.store:session-store-get store-2 "agent:bot:irc")))
               (is (= 100 (cl-claw.sessions.store:session-entry-message-count tg))
                   "Telegram session count preserved")
               (is (= 200 (cl-claw.sessions.store:session-entry-message-count dc))
                   "Discord session count preserved")
               (is (= 50 (cl-claw.sessions.store:session-entry-message-count irc))
                   "IRC session count preserved"))))
      (ignore-errors
       (uiop:delete-directory-tree
        (uiop:ensure-directory-pathname tmp-dir)
        :validate t :if-does-not-exist :ignore)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 3: Channel reconnection with backoff
;;; ═══════════════════════════════════════════════════════════════════════════

(test crash-recovery-channel-reconnect-success
  "Channel reconnects after transient failures using exponential backoff."
  (let ((ch (make-instance 'mock-channel :channel-id "tg-reconnect"))
        (acct (make-mock-account)))
    ;; Fail 2 times, succeed on 3rd attempt
    (setf (mock-fail-connects ch) 2)

    ;; Override backoff delays so test runs fast
    (let ((cl-claw.channel-protocol.lifecycle:*reconnect-base-delay-ms* 1)
          (cl-claw.channel-protocol.lifecycle:*reconnect-max-delay-ms* 5)
          (cl-claw.channel-protocol.lifecycle:*max-reconnect-attempts* 5))
      (let ((result (cl-claw.channel-protocol.lifecycle:reconnect-channel ch acct)))
        (is (eq t result)
            "Reconnection succeeds after transient failures")
        (is (eq :connected (cl-claw.channel-protocol.types:channel-get-state ch))
            "Channel state is connected after successful reconnect")
        ;; 2 failed + 1 success = 3 total connect attempts
        (is (= 3 (mock-connect-count ch))
            "Expected 3 connect attempts (2 failures + 1 success)")))))

(test crash-recovery-channel-reconnect-exhausted
  "Channel reconnection fails after max attempts exhausted."
  (let ((ch (make-instance 'mock-channel :channel-id "tg-exhaust"))
        (acct (make-mock-account)))
    ;; Fail more times than max attempts
    (setf (mock-fail-connects ch) 100)

    (let ((cl-claw.channel-protocol.lifecycle:*reconnect-base-delay-ms* 1)
          (cl-claw.channel-protocol.lifecycle:*reconnect-max-delay-ms* 2)
          (cl-claw.channel-protocol.lifecycle:*max-reconnect-attempts* 3))
      (let ((result (cl-claw.channel-protocol.lifecycle:reconnect-channel ch acct)))
        (is (null result)
            "Reconnection returns NIL after exhausting attempts")
        (is (eq :error (cl-claw.channel-protocol.types:channel-get-state ch))
            "Channel state is :error after exhausted reconnection")
        (is (= 3 (mock-connect-count ch))
            "Exactly max-attempts connect calls were made")))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 4: Exponential backoff computation
;;; ═══════════════════════════════════════════════════════════════════════════

(test crash-recovery-backoff-increases
  "Backoff delay increases exponentially with attempt number."
  (let ((cl-claw.channel-protocol.lifecycle:*reconnect-base-delay-ms* 100)
        (cl-claw.channel-protocol.lifecycle:*reconnect-max-delay-ms* 100000))
    (let ((delay-0 (cl-claw.channel-protocol.lifecycle:compute-backoff-delay 0))
          (delay-1 (cl-claw.channel-protocol.lifecycle:compute-backoff-delay 1))
          (delay-3 (cl-claw.channel-protocol.lifecycle:compute-backoff-delay 3)))
      ;; Delay should generally increase (with jitter it's not perfectly monotone,
      ;; but the base doubles so even with jitter it trends up)
      (is (> delay-1 0) "Delay at attempt 1 is positive")
      (is (> delay-3 delay-0)
          "Delay at attempt 3 is greater than at attempt 0 (exponential growth)"))))

(test crash-recovery-backoff-capped
  "Backoff delay is capped at max-delay."
  (let ((cl-claw.channel-protocol.lifecycle:*reconnect-base-delay-ms* 1000)
        (cl-claw.channel-protocol.lifecycle:*reconnect-max-delay-ms* 5000))
    (let ((delay (cl-claw.channel-protocol.lifecycle:compute-backoff-delay 20)))
      (is (<= delay 5000)
          "Backoff delay does not exceed maximum"))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 5: Stale process detection (lsof output parsing)
;;; ═══════════════════════════════════════════════════════════════════════════

(test crash-recovery-parse-lsof-finds-openclaw
  "Parses lsof -Fpc output to find stale openclaw gateway PIDs."
  (let ((output (format nil "p12345~%copenclaw~%p67890~%copenclaw-gateway~%")))
    (let ((pids (cl-claw.infra.restart:parse-pids-from-lsof-output
                 output :current-pid 99999)))
      (is (= 2 (length pids))
          "Finds both openclaw PIDs")
      (is (member 12345 pids)
          "Finds PID 12345")
      (is (member 67890 pids)
          "Finds PID 67890"))))

(test crash-recovery-parse-lsof-filters-current-pid
  "Lsof parser filters out the current process PID."
  (let ((output (format nil "p12345~%copenclaw~%p99999~%copenclaw~%")))
    (let ((pids (cl-claw.infra.restart:parse-pids-from-lsof-output
                 output :current-pid 99999)))
      (is (= 1 (length pids))
          "Only one PID returned (current filtered)")
      (is (= 12345 (first pids))
          "Returns the non-current PID"))))

(test crash-recovery-parse-lsof-ignores-non-openclaw
  "Lsof parser ignores non-openclaw processes."
  (let ((output (format nil "p111~%cnginx~%p222~%cnode~%p333~%copenclaw~%")))
    (let ((pids (cl-claw.infra.restart:parse-pids-from-lsof-output
                 output :current-pid 99999)))
      (is (= 1 (length pids))
          "Only openclaw PID returned")
      (is (= 333 (first pids))
          "Correct openclaw PID identified"))))

(test crash-recovery-parse-lsof-empty
  "Lsof parser returns empty list for empty output."
  (let ((pids (cl-claw.infra.restart:parse-pids-from-lsof-output
               "" :current-pid 99999)))
    (is (null pids)
        "No PIDs from empty lsof output")))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 6: Boot sequence crash recovery
;;; ═══════════════════════════════════════════════════════════════════════════

(test crash-recovery-boot-sequence-no-bootmd
  "Boot sequence skips gracefully when no BOOT.md exists."
  (let ((result (cl-claw.gateway.boot:run-boot-once
                 :base-dir "/tmp/cl-claw-no-boot-md-ever/")))
    (is (eq :skipped (cl-claw.gateway.boot:boot-result-status result))
        "Boot skipped when no BOOT.md")))

(test crash-recovery-boot-sequence-with-bootmd
  "Boot sequence runs agent when BOOT.md exists and cleans up."
  (let* ((tmp-dir (format nil "/tmp/cl-claw-boot-e2e-~a/" (get-universal-time)))
         (boot-path (merge-pathnames "BOOT.md" (uiop:ensure-directory-pathname tmp-dir)))
         (agent-ran nil)
         (agent-content nil))
    (unwind-protect
         (progn
           (ensure-directories-exist boot-path)
           (with-open-file (out boot-path :direction :output :if-exists :supersede)
             (write-string "Bootstrap the system" out))

           (let ((result (cl-claw.gateway.boot:run-boot-once
                          :base-dir tmp-dir
                          :run-agent-fn (lambda (session-id content)
                                          (declare (ignore session-id))
                                          (setf agent-ran t
                                                agent-content content))
                          :session-id-fn (lambda () "test-session-42"))))
             (is (eq :completed (cl-claw.gateway.boot:boot-result-status result))
                 "Boot completed successfully")
             (is (string= "test-session-42" (cl-claw.gateway.boot:boot-result-session-id result))
                 "Session ID matches expected value")
             (is (eq t agent-ran)
                 "Agent function was actually called")
             (is (string= "Bootstrap the system" agent-content)
                 "Agent received correct BOOT.md content")))
      (ignore-errors
       (uiop:delete-directory-tree
        (uiop:ensure-directory-pathname tmp-dir)
        :validate t :if-does-not-exist :ignore)))))

(test crash-recovery-boot-sequence-agent-error
  "Boot sequence reports failure when agent function errors."
  (let* ((tmp-dir (format nil "/tmp/cl-claw-boot-err-~a/" (get-universal-time)))
         (boot-path (merge-pathnames "BOOT.md" (uiop:ensure-directory-pathname tmp-dir))))
    (unwind-protect
         (progn
           (ensure-directories-exist boot-path)
           (with-open-file (out boot-path :direction :output :if-exists :supersede)
             (write-string "Crash me" out))

           (let ((result (cl-claw.gateway.boot:run-boot-once
                          :base-dir tmp-dir
                          :run-agent-fn (lambda (session-id content)
                                          (declare (ignore session-id content))
                                          (error "Simulated agent crash")))))
             (is (eq :failed (cl-claw.gateway.boot:boot-result-status result))
                 "Boot reports failure on agent error")
             (is (not (null (cl-claw.gateway.boot:boot-result-error result)))
                 "Error message is populated")))
      (ignore-errors
       (uiop:delete-directory-tree
        (uiop:ensure-directory-pathname tmp-dir)
        :validate t :if-does-not-exist :ignore)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 7: Retry mechanism under crash conditions
;;; ═══════════════════════════════════════════════════════════════════════════

(test crash-recovery-retry-succeeds-after-failures
  "Retry mechanism recovers after transient failures."
  (let ((call-count 0))
    (let ((result (cl-claw.infra.retry:with-retry
                    (lambda ()
                      (incf call-count)
                      (when (< call-count 3)
                        (error "Transient failure ~a" call-count))
                      :recovered)
                    (cl-claw.infra.retry:make-retry-options
                     :attempts 5
                     :min-delay-ms 1
                     :max-delay-ms 2)
                    1)))
      (is (eq :recovered result)
          "Retry returns success value")
      (is (= 3 call-count)
          "Function called 3 times (2 failures + 1 success)"))))

(test crash-recovery-retry-exhaustion
  "Retry signals retry-error when all attempts fail."
  (signals cl-claw.infra.retry:retry-error
    (cl-claw.infra.retry:with-retry
      (lambda () (error "Permanent failure"))
      (cl-claw.infra.retry:make-retry-options
       :attempts 3
       :min-delay-ms 1
       :max-delay-ms 2)
      1)))

(test crash-recovery-retry-should-retry-predicate
  "Retry respects should-retry predicate to stop early on non-transient errors."
  (let ((call-count 0))
    (signals cl-claw.infra.retry:retry-error
      (cl-claw.infra.retry:with-retry
        (lambda ()
          (incf call-count)
          (error "Fatal error"))
        (cl-claw.infra.retry:make-retry-options
         :attempts 10
         :min-delay-ms 1
         :max-delay-ms 2
         :should-retry (lambda (e) (declare (ignore e)) nil))
        1))
    ;; should-retry returns nil immediately, so only 1 call
    (is (= 1 call-count)
        "Only called once when should-retry returns NIL")))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 8: Channel manager full recovery cycle
;;; ═══════════════════════════════════════════════════════════════════════════

(test crash-recovery-manager-full-cycle
  "Channel manager: add channels, connect, simulate crash (disconnect-all),
   reconnect, verify state restored."
  (let ((manager (cl-claw.channel-protocol.lifecycle:make-channel-manager))
        (ch1 (make-instance 'mock-channel :channel-id "telegram"))
        (ch2 (make-instance 'mock-channel :channel-id "discord"))
        (acct1 (make-mock-account "tg-acct"))
        (acct2 (make-mock-account "dc-acct")))

    ;; Phase 1: Register and connect
    (cl-claw.channel-protocol.lifecycle:manager-add-channel manager "telegram" ch1 acct1)
    (cl-claw.channel-protocol.lifecycle:manager-add-channel manager "discord" ch2 acct2)
    (cl-claw.channel-protocol.lifecycle:manager-connect-all manager)

    (is (= 2 (length (cl-claw.channel-protocol.lifecycle:manager-list-channels manager)))
        "Two channels registered")
    (is (eq :connected (cl-claw.channel-protocol.types:channel-get-state ch1))
        "Telegram connected")
    (is (eq :connected (cl-claw.channel-protocol.types:channel-get-state ch2))
        "Discord connected")

    ;; Phase 2: Simulate crash (disconnect all)
    (cl-claw.channel-protocol.lifecycle:manager-disconnect-all manager)
    (is (eq :disconnected (cl-claw.channel-protocol.types:channel-get-state ch1))
        "Telegram disconnected after crash")
    (is (eq :disconnected (cl-claw.channel-protocol.types:channel-get-state ch2))
        "Discord disconnected after crash")

    ;; Phase 3: Recovery — reconnect all
    (cl-claw.channel-protocol.lifecycle:manager-connect-all manager)
    (is (eq :connected (cl-claw.channel-protocol.types:channel-get-state ch1))
        "Telegram reconnected after recovery")
    (is (eq :connected (cl-claw.channel-protocol.types:channel-get-state ch2))
        "Discord reconnected after recovery")

    ;; Verify connect counts: 1 initial + 1 recovery = 2 each
    (is (= 2 (mock-connect-count ch1))
        "Telegram connected twice (initial + recovery)")
    (is (= 2 (mock-connect-count ch2))
        "Discord connected twice (initial + recovery)")))

(test crash-recovery-manager-status-reflects-state
  "Channel manager status accurately reflects channel states during recovery."
  (let ((manager (cl-claw.channel-protocol.lifecycle:make-channel-manager))
        (ch (make-instance 'mock-channel :channel-id "test-ch"))
        (acct (make-mock-account)))
    (cl-claw.channel-protocol.lifecycle:manager-add-channel manager "test" ch acct)

    ;; Before connect
    (let ((status (cl-claw.channel-protocol.lifecycle:manager-get-status manager)))
      (is (eq :disconnected (cdr (assoc "test" status :test #'string=)))
          "Status shows disconnected before connect"))

    ;; After connect
    (cl-claw.channel-protocol.lifecycle:manager-connect-all manager)
    (let ((status (cl-claw.channel-protocol.lifecycle:manager-get-status manager)))
      (is (eq :connected (cdr (assoc "test" status :test #'string=)))
          "Status shows connected after connect"))

    ;; After simulated crash
    (cl-claw.channel-protocol.lifecycle:manager-disconnect-all manager)
    (let ((status (cl-claw.channel-protocol.lifecycle:manager-get-status manager)))
      (is (eq :disconnected (cdr (assoc "test" status :test #'string=)))
          "Status shows disconnected after crash"))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 9: Session deletion during crash recovery
;;; ═══════════════════════════════════════════════════════════════════════════

(test crash-recovery-session-delete-and-recover
  "Deleted sessions stay deleted after crash recovery."
  (let* ((tmp-dir (format nil "/tmp/cl-claw-e2e-del-~a/" (get-universal-time)))
         (store (cl-claw.sessions.store:create-session-store :root-dir tmp-dir)))
    (unwind-protect
         (progn
           (cl-claw.sessions.store:session-store-upsert store "keep-me" :message-count 10)
           (cl-claw.sessions.store:session-store-upsert store "delete-me" :message-count 20)
           (cl-claw.sessions.store:session-store-delete store "delete-me")

           ;; Reload from disk
           (let ((store-2 (cl-claw.sessions.store:create-session-store :root-dir tmp-dir)))
             (is (not (null (cl-claw.sessions.store:session-store-get store-2 "keep-me")))
                 "Kept session survives crash")
             (is (null (cl-claw.sessions.store:session-store-get store-2 "delete-me"))
                 "Deleted session stays deleted after crash")
             (is (= 1 (length (cl-claw.sessions.store:session-store-list store-2)))
                 "Only one session exists after recovery")))
      (ignore-errors
       (uiop:delete-directory-tree
        (uiop:ensure-directory-pathname tmp-dir)
        :validate t :if-does-not-exist :ignore)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 10: Retry policy with transient error detection
;;; ═══════════════════════════════════════════════════════════════════════════

(test crash-recovery-retry-policy-transient-detection
  "Retry policy detects transient network errors via regex pattern."
  (let ((runner (cl-claw.infra.retry-policy:make-retry-runner
                 :options (cl-claw.infra.retry-policy:make-retry-runner-options
                           :attempts 3
                           :min-delay-ms 1
                           :max-delay-ms 2))))
    ;; Transient error should be retried
    (let ((call-count 0))
      (let ((result (funcall runner
                             (lambda ()
                               (incf call-count)
                               (when (< call-count 2)
                                 (error "Connection refused ECONNREFUSED"))
                               :ok))))
        (is (eq :ok result) "Transient error recovered")
        (is (= 2 call-count) "Retried once on transient error")))))

(test crash-recovery-retry-policy-strict-mode
  "Strict retry mode only retries when predicate says so."
  (let ((runner (cl-claw.infra.retry-policy:make-retry-runner
                 :options (cl-claw.infra.retry-policy:make-retry-runner-options
                           :attempts 5
                           :min-delay-ms 1
                           :max-delay-ms 2
                           :should-retry (lambda (e)
                                           (declare (ignore e))
                                           nil)
                           :strict-should-retry t))))
    ;; With strict mode + predicate returning nil → no retry
    (signals error
      (funcall runner (lambda () (error "Will not retry"))))))
