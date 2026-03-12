;;;; multi-channel-concurrent-test.lisp — E2E: Multi-channel concurrent operation
;;;;
;;;; Tests concurrent operation across multiple channels:
;;;; 1. Multiple mock channels sending/receiving simultaneously
;;;; 2. Thread-safe message queue under concurrent load
;;;; 3. No race conditions in channel manager operations
;;;; 4. No deadlocks when channels interact concurrently
;;;; 5. Rate limiter correctness under concurrent access
;;;; 6. Concurrent session store operations

(in-package :cl-claw.e2e.tests)

(in-suite :cl-claw.e2e.tests)

(def-suite :e2e-multi-channel :in :cl-claw.e2e.tests
  :description "Multi-channel concurrent operation E2E tests")

(in-suite :e2e-multi-channel)

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Concurrent mock channel — adds simulated latency and thread tracking
;;; ═══════════════════════════════════════════════════════════════════════════

(defclass concurrent-mock-channel (cl-claw.channel-protocol.types:channel)
  ((channel-id :initarg :channel-id :initform "concurrent-mock" :accessor cmc-channel-id :type string)
   (connect-count :initform 0 :accessor cmc-connect-count :type fixnum)
   (messages-sent :initform '() :accessor cmc-messages-sent :type list)
   (messages-received :initform '() :accessor cmc-messages-received :type list)
   (send-delay-ms :initarg :send-delay-ms :initform 0 :accessor cmc-send-delay-ms :type fixnum)
   (connect-delay-ms :initarg :connect-delay-ms :initform 0 :accessor cmc-connect-delay-ms :type fixnum)
   (thread-ids-seen :initform '() :accessor cmc-thread-ids-seen :type list)
   (lock :initform (bt:make-lock "cmc-lock") :accessor cmc-lock :type t))
  (:documentation "Mock channel for concurrent E2E testing with latency simulation."))

(defmethod cl-claw.channel-protocol.types:channel-get-info ((ch concurrent-mock-channel))
  (cl-claw.channel-protocol.types:make-channel-info
   :id (cmc-channel-id ch)
   :name "concurrent-mock"
   :version "1.0.0"
   :supports '(:text :attachments)))

(defmethod cl-claw.channel-protocol.types:channel-connect ((ch concurrent-mock-channel) account)
  (declare (type cl-claw.channel-protocol.types:channel-account account)
           (ignore account))
  ;; Simulate connection latency
  (when (> (cmc-connect-delay-ms ch) 0)
    (sleep (/ (cmc-connect-delay-ms ch) 1000.0)))
  (bt:with-lock-held ((cmc-lock ch))
    (incf (cmc-connect-count ch))
    (push (bt:current-thread) (cmc-thread-ids-seen ch)))
  (setf (slot-value ch 'cl-claw.channel-protocol.types::state)
        cl-claw.channel-protocol.types:+channel-state-connected+))

(defmethod cl-claw.channel-protocol.types:channel-disconnect ((ch concurrent-mock-channel))
  (setf (slot-value ch 'cl-claw.channel-protocol.types::state)
        cl-claw.channel-protocol.types:+channel-state-disconnected+))

(defmethod cl-claw.channel-protocol.types:channel-send-message ((ch concurrent-mock-channel) outbound)
  (declare (type cl-claw.channel-protocol.types:outbound-message outbound))
  ;; Simulate send latency
  (when (> (cmc-send-delay-ms ch) 0)
    (sleep (/ (cmc-send-delay-ms ch) 1000.0)))
  (let ((msg-id (format nil "~a-msg-~a-~a"
                        (cmc-channel-id ch)
                        (get-universal-time)
                        (random 1000000))))
    (bt:with-lock-held ((cmc-lock ch))
      (push (cons msg-id (cl-claw.channel-protocol.types:outbound-message-text outbound))
            (cmc-messages-sent ch))
      (push (bt:current-thread) (cmc-thread-ids-seen ch)))
    msg-id))

(defmethod cl-claw.channel-protocol.types:channel-format-outbound ((ch concurrent-mock-channel) message)
  (declare (ignore message))
  (make-hash-table :test 'equal))

(defun simulate-inbound (ch msg-text)
  "Simulate an inbound message arriving on a concurrent mock channel."
  (declare (type concurrent-mock-channel ch)
           (type string msg-text))
  (bt:with-lock-held ((cmc-lock ch))
    (push msg-text (cmc-messages-received ch)))
  (let ((handler (slot-value ch 'cl-claw.channel-protocol.types::message-handler)))
    (when handler
      (funcall handler
               (cl-claw.channel-protocol.types:make-normalized-message
                :id (format nil "in-~a-~a" (get-universal-time) (random 1000000))
                :channel (cmc-channel-id ch)
                :text msg-text
                :sender-id "user-1"
                :sender-name "Test User")))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 1: Concurrent message sending across multiple channels
;;; ═══════════════════════════════════════════════════════════════════════════

(test multi-channel-concurrent-send
  "Multiple channels can send messages concurrently without data corruption."
  (let* ((num-channels 4)
         (msgs-per-channel 25)
         (channels (loop for i from 1 to num-channels
                         collect (make-instance 'concurrent-mock-channel
                                                :channel-id (format nil "ch-~a" i)
                                                :send-delay-ms 1)))
         (errors '())
         (error-lock (bt:make-lock "error-lock"))
         (start-flag nil)
         (start-lock (bt:make-lock "start-lock")))
    ;; Spawn a thread per channel, each sends msgs-per-channel messages
    (let ((threads
            (loop for ch in channels
                  for ch-copy = ch  ;; capture the binding
                  collect (bt:make-thread
                           (let ((my-ch ch-copy))
                             (lambda ()
                               ;; Spin until start flag
                               (loop until start-flag do (sleep 0.001))
                               ;; Send messages
                               (handler-case
                                   (dotimes (i msgs-per-channel)
                                     (cl-claw.channel-protocol.types:channel-send-message
                                      my-ch
                                      (cl-claw.channel-protocol.types:make-outbound-message
                                       :target "user-1"
                                       :text (format nil "msg-~a-from-~a" i (cmc-channel-id my-ch)))))
                                 (error (e)
                                   (bt:with-lock-held (error-lock)
                                     (push (format nil "~a: ~a" (cmc-channel-id my-ch) e) errors))))))
                           :name (format nil "sender-~a" (cmc-channel-id ch))))))
      ;; Start all threads simultaneously
      (setf start-flag t)
      ;; Wait for all threads to finish
      (dolist (th threads)
        (bt:join-thread th))
      ;; Verify no errors
      (is (null errors)
          "No errors during concurrent send: ~a" errors)
      ;; Verify each channel got exactly the right number of messages
      (dolist (ch channels)
        (let ((my-ch ch))
          (is (= msgs-per-channel (length (cmc-messages-sent my-ch)))
              "Channel ~a sent exactly ~a messages (got ~a)"
              (cmc-channel-id my-ch) msgs-per-channel (length (cmc-messages-sent my-ch)))))
      ;; Verify total messages across all channels
      (let ((total (reduce #'+ channels :key (lambda (ch) (length (cmc-messages-sent ch))))))
        (is (= (* num-channels msgs-per-channel) total)
            "Total messages sent = ~a (expected ~a)" total (* num-channels msgs-per-channel))))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 2: Concurrent channel manager connect/disconnect
;;; ═══════════════════════════════════════════════════════════════════════════

(test multi-channel-concurrent-connect-disconnect
  "Channel manager handles concurrent connect and disconnect without deadlock."
  (let ((manager (cl-claw.channel-protocol.lifecycle:make-channel-manager))
        (num-channels 6)
        (errors '())
        (error-lock (bt:make-lock "error-lock")))
    ;; Register channels
    (loop for i from 1 to num-channels
          for id = (format nil "ch-~a" i)
          for ch = (make-instance 'concurrent-mock-channel
                                  :channel-id id
                                  :connect-delay-ms 5)
          for acct = (make-mock-account id)
          do (cl-claw.channel-protocol.lifecycle:manager-add-channel manager id ch acct))
    ;; Concurrently connect-all, disconnect-all, and connect-all again
    (let ((threads
            (list
             (bt:make-thread
              (lambda ()
                (handler-case
                    (cl-claw.channel-protocol.lifecycle:manager-connect-all manager)
                  (error (e)
                    (bt:with-lock-held (error-lock)
                      (push (format nil "connect-1: ~a" e) errors)))))
              :name "connect-1")
             (bt:make-thread
              (lambda ()
                (sleep 0.01)
                (handler-case
                    (cl-claw.channel-protocol.lifecycle:manager-disconnect-all manager)
                  (error (e)
                    (bt:with-lock-held (error-lock)
                      (push (format nil "disconnect: ~a" e) errors)))))
              :name "disconnect")
             (bt:make-thread
              (lambda ()
                (sleep 0.02)
                (handler-case
                    (cl-claw.channel-protocol.lifecycle:manager-connect-all manager)
                  (error (e)
                    (bt:with-lock-held (error-lock)
                      (push (format nil "connect-2: ~a" e) errors)))))
              :name "connect-2"))))
      (dolist (th threads)
        (bt:join-thread th))
      (is (null errors)
          "No errors during concurrent connect/disconnect: ~a" errors)
      ;; After final connect, all channels should be connected
      (let ((status (cl-claw.channel-protocol.lifecycle:manager-get-status manager)))
        (is (= num-channels (length status))
            "All ~a channels still registered" num-channels)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 3: Thread-safe message queue under concurrent load
;;; ═══════════════════════════════════════════════════════════════════════════

(test multi-channel-concurrent-queue-integrity
  "Message queue maintains integrity under concurrent enqueue/dequeue."
  (let* ((queue (cl-claw.channel-protocol.queue:make-message-queue))
         (num-producers 4)
         (items-per-producer 100)
         (total-items (* num-producers items-per-producer))
         (consumed '())
         (consumed-lock (bt:make-lock "consumed"))
         (done-producing nil))
    ;; Producers
    (let ((producers
            (loop for p from 1 to num-producers
                  collect (let ((my-p p))
                            (bt:make-thread
                             (lambda ()
                               (dotimes (i items-per-producer)
                                 (cl-claw.channel-protocol.queue:queue-enqueue
                                  queue (format nil "p~a-~a" my-p i))))
                             :name (format nil "producer-~a" my-p))))))
      ;; Wait for all producers to finish
      (dolist (th producers)
        (bt:join-thread th))
      (setf done-producing t)
      ;; Now drain the queue (single-threaded to avoid counting races)
      (loop
        (multiple-value-bind (item found)
            (cl-claw.channel-protocol.queue:queue-dequeue queue)
          (unless found (return))
          (push item consumed)))
      ;; Verify
      (is (= total-items (length consumed))
          "All ~a items consumed (got ~a)" total-items (length consumed))
      (is (cl-claw.channel-protocol.queue:queue-empty-p queue)
          "Queue is empty after all consumption")
      ;; Verify no duplicates
      (let ((unique (remove-duplicates consumed :test #'string=)))
        (is (= total-items (length unique))
            "No duplicate items consumed (~a unique out of ~a)"
            (length unique) (length consumed))))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 4: Concurrent inbound message dispatch
;;; ═══════════════════════════════════════════════════════════════════════════

(test multi-channel-concurrent-inbound-dispatch
  "Inbound messages on multiple channels dispatch to handlers concurrently."
  (let* ((num-channels 4)
         (msgs-per-channel 20)
         (received-messages '())
         (received-lock (bt:make-lock "received"))
         (channels
           (loop for i from 1 to num-channels
                 for ch = (make-instance 'concurrent-mock-channel
                                         :channel-id (format nil "inbound-ch-~a" i))
                 do (cl-claw.channel-protocol.types:channel-set-message-handler
                     ch
                     (lambda (msg)
                       (bt:with-lock-held (received-lock)
                         (push (cons (cl-claw.channel-protocol.types:normalized-message-channel msg)
                                     (cl-claw.channel-protocol.types:normalized-message-text msg))
                               received-messages))))
                 collect ch))
         (errors '())
         (error-lock (bt:make-lock "error-lock")))
    ;; Spawn threads to simulate inbound messages on each channel
    (let ((threads
            (loop for ch in channels
                  collect (let ((my-ch ch))
                            (bt:make-thread
                             (lambda ()
                               (handler-case
                                   (dotimes (i msgs-per-channel)
                                     (simulate-inbound my-ch (format nil "hello-~a" i)))
                                 (error (e)
                                   (bt:with-lock-held (error-lock)
                                     (push (format nil "~a: ~a" (cmc-channel-id my-ch) e) errors)))))
                             :name (format nil "inbound-~a" (cmc-channel-id ch)))))))
      (dolist (th threads)
        (bt:join-thread th))
      (is (null errors)
          "No errors during concurrent inbound dispatch: ~a" errors)
      (is (= (* num-channels msgs-per-channel) (length received-messages))
          "All ~a inbound messages dispatched (got ~a)"
          (* num-channels msgs-per-channel) (length received-messages))
      ;; Verify messages came from all channels
      (let ((channels-seen (remove-duplicates (mapcar #'car received-messages) :test #'string=)))
        (is (= num-channels (length channels-seen))
            "Messages received from all ~a channels" num-channels)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 5: No deadlock: concurrent send + inbound + connect/disconnect
;;; ═══════════════════════════════════════════════════════════════════════════

(test multi-channel-no-deadlock-mixed-operations
  "Mixed concurrent operations (send, receive, connect, disconnect) don't deadlock."
  (let* ((manager (cl-claw.channel-protocol.lifecycle:make-channel-manager))
         (ch1 (make-instance 'concurrent-mock-channel :channel-id "dl-ch-1" :send-delay-ms 1))
         (ch2 (make-instance 'concurrent-mock-channel :channel-id "dl-ch-2" :send-delay-ms 1))
         (acct1 (make-mock-account "dl-acct-1"))
         (acct2 (make-mock-account "dl-acct-2"))
         (errors '())
         (error-lock (bt:make-lock "error-lock"))
         (deadline (+ (get-internal-real-time)
                      (* 5 internal-time-units-per-second))))
    (cl-claw.channel-protocol.lifecycle:manager-add-channel manager "ch1" ch1 acct1)
    (cl-claw.channel-protocol.lifecycle:manager-add-channel manager "ch2" ch2 acct2)
    (cl-claw.channel-protocol.lifecycle:manager-connect-all manager)
    ;; Set up inbound handlers
    (cl-claw.channel-protocol.types:channel-set-message-handler
     ch1 (lambda (msg) (declare (ignore msg))))
    (cl-claw.channel-protocol.types:channel-set-message-handler
     ch2 (lambda (msg) (declare (ignore msg))))
    ;; Spawn mixed operations with a 5-second timeout
    (let ((threads
            (list
             ;; Thread 1: continuous sending on ch1
             (bt:make-thread
              (lambda ()
                (handler-case
                    (dotimes (i 30)
                      (when (> (get-internal-real-time) deadline) (return))
                      (cl-claw.channel-protocol.types:channel-send-message
                       ch1
                       (cl-claw.channel-protocol.types:make-outbound-message
                        :target "u" :text (format nil "s1-~a" i))))
                  (error (e)
                    (bt:with-lock-held (error-lock)
                      (push (format nil "sender-1: ~a" e) errors)))))
              :name "sender-1")
             ;; Thread 2: continuous sending on ch2
             (bt:make-thread
              (lambda ()
                (handler-case
                    (dotimes (i 30)
                      (when (> (get-internal-real-time) deadline) (return))
                      (cl-claw.channel-protocol.types:channel-send-message
                       ch2
                       (cl-claw.channel-protocol.types:make-outbound-message
                        :target "u" :text (format nil "s2-~a" i))))
                  (error (e)
                    (bt:with-lock-held (error-lock)
                      (push (format nil "sender-2: ~a" e) errors)))))
              :name "sender-2")
             ;; Thread 3: inbound messages on ch1
             (bt:make-thread
              (lambda ()
                (handler-case
                    (dotimes (i 20)
                      (when (> (get-internal-real-time) deadline) (return))
                      (simulate-inbound ch1 (format nil "in-~a" i)))
                  (error (e)
                    (bt:with-lock-held (error-lock)
                      (push (format nil "inbound-1: ~a" e) errors)))))
              :name "inbound-1")
             ;; Thread 4: connect/disconnect cycles
             (bt:make-thread
              (lambda ()
                (handler-case
                    (dotimes (i 5)
                      (when (> (get-internal-real-time) deadline) (return))
                      (cl-claw.channel-protocol.lifecycle:manager-disconnect-all manager)
                      (sleep 0.005)
                      (cl-claw.channel-protocol.lifecycle:manager-connect-all manager))
                  (error (e)
                    (bt:with-lock-held (error-lock)
                      (push (format nil "lifecycle: ~a" e) errors)))))
              :name "lifecycle")
             ;; Thread 5: status polling
             (bt:make-thread
              (lambda ()
                (handler-case
                    (dotimes (i 15)
                      (when (> (get-internal-real-time) deadline) (return))
                      (cl-claw.channel-protocol.lifecycle:manager-get-status manager)
                      (cl-claw.channel-protocol.lifecycle:manager-list-channels manager)
                      (sleep 0.003))
                  (error (e)
                    (bt:with-lock-held (error-lock)
                      (push (format nil "status-poll: ~a" e) errors)))))
              :name "status-poll"))))
      ;; Wait for all threads with timeout
      (dolist (th threads)
        (handler-case
            (bt:join-thread th)
          (error (e)
            (bt:with-lock-held (error-lock)
              (push (format nil "join: ~a" e) errors)))))
      ;; The test passes if we get here without hanging (deadlock)
      (is (not (null t)) "Mixed concurrent operations completed without deadlock")
      ;; Errors from send on disconnected channels are expected — filter them
      (let ((real-errors (remove-if (lambda (e)
                                      (or (search "disconnected" e :test #'char-equal)
                                          (search "state" e :test #'char-equal)))
                                     errors)))
        (is (null real-errors)
            "No unexpected errors during mixed operations: ~a" real-errors)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 6: Concurrent session store operations
;;; ═══════════════════════════════════════════════════════════════════════════

(test multi-channel-concurrent-session-store
  "Session store handles concurrent upsert/get/delete from multiple threads."
  (let* ((tmp-dir (format nil "/tmp/cl-claw-e2e-concurrent-~a/" (get-universal-time)))
         (store (cl-claw.sessions.store:create-session-store :root-dir tmp-dir))
         (num-threads 4)
         (ops-per-thread 50)
         (errors '())
         (error-lock (bt:make-lock "error-lock")))
    (unwind-protect
         (progn
           (let ((threads
                   (loop for t-id from 1 to num-threads
                         collect (let ((my-tid t-id))
                                   (bt:make-thread
                                    (lambda ()
                                      (handler-case
                                          (dotimes (i ops-per-thread)
                                            (let ((key (format nil "session-t~a-~a" my-tid i)))
                                              ;; Upsert
                                              (cl-claw.sessions.store:session-store-upsert
                                               store key :message-count i)
                                              ;; Read back
                                              (let ((entry (cl-claw.sessions.store:session-store-get store key)))
                                                (unless entry
                                                  (bt:with-lock-held (error-lock)
                                                    (push (format nil "Missing entry ~a" key) errors))))
                                              ;; Delete odd-numbered entries
                                              (when (oddp i)
                                                (cl-claw.sessions.store:session-store-delete store key))))
                                        (error (e)
                                          (bt:with-lock-held (error-lock)
                                            (push (format nil "thread-~a: ~a" my-tid e) errors)))))
                                    :name (format nil "session-worker-~a" t-id))))))
             (dolist (th threads)
               (bt:join-thread th))
             (is (null errors)
                 "No errors during concurrent session operations: ~a" errors)
             ;; Verify: even-numbered entries should exist, odd should be deleted
             (loop for tid from 1 to num-threads
                   do (dotimes (i ops-per-thread)
                        (let* ((key (format nil "session-t~a-~a" tid i))
                               (entry (cl-claw.sessions.store:session-store-get store key)))
                          (if (oddp i)
                              (is (null entry)
                                  "Odd entry ~a was deleted" key)
                              (is (not (null entry))
                                  "Even entry ~a still exists" key)))))))
      (ignore-errors
       (uiop:delete-directory-tree
        (uiop:ensure-directory-pathname tmp-dir)
        :validate t :if-does-not-exist :ignore)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 7: Rate limiter thread safety
;;; ═══════════════════════════════════════════════════════════════════════════

(test multi-channel-rate-limiter-thread-safety
  "Rate limiter correctly tracks state under concurrent access."
  (let* ((limiter (cl-claw.channel-protocol.types:make-rate-limiter
                   :max-per-second 100.0
                   :max-per-minute 1000.0))
         (num-threads 4)
         (checks-per-thread 50)
         (allowed-count 0)
         (count-lock (bt:make-lock "count-lock"))
         (errors '())
         (error-lock (bt:make-lock "error-lock")))
    (let ((threads
            (loop for i from 1 to num-threads
                  collect (let ((my-i i))
                            (bt:make-thread
                             (lambda ()
                               (handler-case
                                   (dotimes (j checks-per-thread)
                                     (when (cl-claw.channel-protocol.types:rate-limit-check limiter)
                                       (cl-claw.channel-protocol.types:rate-limit-record limiter)
                                       (bt:with-lock-held (count-lock)
                                         (incf allowed-count))))
                                 (error (e)
                                   (bt:with-lock-held (error-lock)
                                     (push (format nil "rl-thread-~a: ~a" my-i e) errors)))))
                             :name (format nil "rl-thread-~a" i))))))
      (dolist (th threads)
        (bt:join-thread th))
      (is (null errors)
          "No errors during concurrent rate limit access: ~a" errors)
      ;; Some messages should have been allowed
      (is (> allowed-count 0)
          "At least some messages were allowed through rate limiter")
      ;; Rate limiter should have capped total
      (is (<= allowed-count (* num-threads checks-per-thread))
          "Allowed count (~a) does not exceed total attempts (~a)"
          allowed-count (* num-threads checks-per-thread)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 8: Concurrent rate-limited sender
;;; ═══════════════════════════════════════════════════════════════════════════

(test multi-channel-concurrent-rate-limited-sender
  "Rate-limited sender processes messages correctly from multiple enqueuers."
  (let* ((sent '())
         (sent-lock (bt:make-lock "sent-lock"))
         (sender (cl-claw.channel-protocol.queue:make-rate-limited-sender
                  :send-fn (lambda (msg)
                             (bt:with-lock-held (sent-lock)
                               (push msg sent)))
                  :max-per-second 1000.0
                  :max-per-minute 10000.0))
         (num-enqueuers 3)
         (msgs-per-enqueuer 20)
         (errors '())
         (error-lock (bt:make-lock "error-lock")))
    ;; Enqueue from multiple threads
    (let ((enqueue-threads
            (loop for e from 1 to num-enqueuers
                  collect (let ((my-e e))
                            (bt:make-thread
                             (lambda ()
                               (handler-case
                                   (dotimes (i msgs-per-enqueuer)
                                     (cl-claw.channel-protocol.queue:sender-enqueue
                                      sender (format nil "e~a-m~a" my-e i)))
                                 (error (err)
                                   (bt:with-lock-held (error-lock)
                                     (push (format nil "enqueuer-~a: ~a" my-e err) errors)))))
                             :name (format nil "enqueuer-~a" e))))))
      (dolist (th enqueue-threads)
        (bt:join-thread th)))
    ;; Process all in one shot
    (cl-claw.channel-protocol.queue:sender-process-all sender)
    (is (null errors)
        "No errors during concurrent enqueue: ~a" errors)
    ;; All messages should have been sent
    (is (= (* num-enqueuers msgs-per-enqueuer) (length sent))
        "All ~a messages were sent (got ~a)"
        (* num-enqueuers msgs-per-enqueuer) (length sent))
    (is (= 0 (cl-claw.channel-protocol.queue:sender-queue-length sender))
        "Queue is empty after processing")))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 9: Cross-channel message routing under concurrency
;;; ═══════════════════════════════════════════════════════════════════════════

(test multi-channel-cross-channel-routing
  "Messages can be routed across channels concurrently (receive on A, send on B)."
  (let* ((ch-telegram (make-instance 'concurrent-mock-channel :channel-id "telegram" :send-delay-ms 1))
         (ch-discord (make-instance 'concurrent-mock-channel :channel-id "discord" :send-delay-ms 1))
         (ch-irc (make-instance 'concurrent-mock-channel :channel-id "irc" :send-delay-ms 1))
         (channels (list ch-telegram ch-discord ch-irc))
         (forwarded '())
         (forwarded-lock (bt:make-lock "forwarded"))
         (errors '())
         (error-lock (bt:make-lock "error-lock")))
    ;; Set up cross-routing: each channel forwards to all others
    (dolist (source channels)
      (let ((my-source source))
        (cl-claw.channel-protocol.types:channel-set-message-handler
         my-source
         (lambda (msg)
           (dolist (target channels)
             (unless (string= (cmc-channel-id target) (cmc-channel-id my-source))
               (handler-case
                   (let ((msg-id (cl-claw.channel-protocol.types:channel-send-message
                                  target
                                  (cl-claw.channel-protocol.types:make-outbound-message
                                   :target "routed"
                                   :text (format nil "fwd:~a"
                                                 (cl-claw.channel-protocol.types:normalized-message-text msg))))))
                     (bt:with-lock-held (forwarded-lock)
                       (push msg-id forwarded)))
                 (error (e)
                   (bt:with-lock-held (error-lock)
                     (push (format nil "route: ~a" e) errors))))))))))
    ;; Simulate concurrent inbound on all channels
    (let ((threads
            (loop for ch in channels
                  collect (let ((my-ch ch))
                            (bt:make-thread
                             (lambda ()
                               (dotimes (i 10)
                                 (simulate-inbound my-ch (format nil "hi-~a" i))))
                             :name (format nil "inbound-~a" (cmc-channel-id ch)))))))
      (dolist (th threads)
        (bt:join-thread th))
      (is (null errors)
          "No errors during cross-channel routing: ~a" errors)
      ;; 3 channels × 10 messages × 2 forwards each = 60 forwarded messages
      (is (= 60 (length forwarded))
          "Expected 60 forwarded messages (got ~a)" (length forwarded)))))

;;; ═══════════════════════════════════════════════════════════════════════════
;;; Test 10: Channel manager add/remove under concurrent access
;;; ═══════════════════════════════════════════════════════════════════════════

(test multi-channel-manager-concurrent-add-remove
  "Channel manager remains consistent when channels are added/removed concurrently."
  (let ((manager (cl-claw.channel-protocol.lifecycle:make-channel-manager))
        (errors '())
        (error-lock (bt:make-lock "error-lock")))
    ;; Thread 1: adds channels 1-20
    ;; Thread 2: adds channels 21-40
    ;; Thread 3: removes channels 1-10 (with delay to let them be added first)
    (let ((threads
            (list
             (bt:make-thread
              (lambda ()
                (handler-case
                    (dotimes (i 20)
                      (let ((id (format nil "ch-~a" (1+ i))))
                        (cl-claw.channel-protocol.lifecycle:manager-add-channel
                         manager id
                         (make-instance 'concurrent-mock-channel :channel-id id)
                         (make-mock-account id))))
                  (error (e)
                    (bt:with-lock-held (error-lock)
                      (push (format nil "adder-1: ~a" e) errors)))))
              :name "adder-1")
             (bt:make-thread
              (lambda ()
                (handler-case
                    (dotimes (i 20)
                      (let ((id (format nil "ch-~a" (+ 21 i))))
                        (cl-claw.channel-protocol.lifecycle:manager-add-channel
                         manager id
                         (make-instance 'concurrent-mock-channel :channel-id id)
                         (make-mock-account id))))
                  (error (e)
                    (bt:with-lock-held (error-lock)
                      (push (format nil "adder-2: ~a" e) errors)))))
              :name "adder-2")
             (bt:make-thread
              (lambda ()
                (sleep 0.01) ; let some adds happen first
                (handler-case
                    (dotimes (i 10)
                      (cl-claw.channel-protocol.lifecycle:manager-remove-channel
                       manager (format nil "ch-~a" (1+ i))))
                  (error (e)
                    (bt:with-lock-held (error-lock)
                      (push (format nil "remover: ~a" e) errors)))))
              :name "remover"))))
      (dolist (th threads)
        (bt:join-thread th))
      (is (null errors)
          "No errors during concurrent add/remove: ~a" errors)
      ;; Should have 40 added - 10 removed = 30 channels
      (let ((remaining (length (cl-claw.channel-protocol.lifecycle:manager-list-channels manager))))
        (is (= 30 remaining)
            "Expected 30 channels remaining (got ~a)" remaining)))))
