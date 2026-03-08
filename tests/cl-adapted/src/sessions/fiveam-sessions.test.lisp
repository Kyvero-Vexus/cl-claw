;;;; FiveAM tests for cl-claw sessions domain

(defpackage :cl-claw.sessions.test
  (:use :cl :fiveam))

(in-package :cl-claw.sessions.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite sessions-suite
  :description "Tests for cl-claw sessions domain")

(in-suite sessions-suite)

(defun make-temp-store ()
  (let* ((root (format nil "~a/cl-claw-sessions-~d"
                       (uiop:native-namestring (uiop:temporary-directory))
                       (random 1000000000)))
         (store (cl-claw.sessions.store:create-session-store :root-dir root)))
    (declare (type string root)
             (type cl-claw.sessions.store:session-store store))
    store))

(test normalize-session-key-lowercases-and-sanitizes
  (is (string= "discord_direct_user_123"
               (cl-claw.sessions.store:normalize-session-key "Discord:Direct:User#123"))))

(test append-and-read-transcript-message
  (let ((store (make-temp-store)))
    (declare (type cl-claw.sessions.store:session-store store))
    (cl-claw.sessions.store:session-store-upsert store "Discord:Direct:Alice")
    (cl-claw.sessions.transcript:append-transcript-message store "Discord:Direct:Alice" "user" "hello")
    (cl-claw.sessions.transcript:append-transcript-message store "Discord:Direct:Alice" "assistant" "hi")
    (let ((messages (cl-claw.sessions.transcript:read-session-transcript store "discord:direct:alice")))
      (declare (type list messages))
      (is (= 2 (length messages)))
      (is (string= "user" (gethash "role" (first messages))))
      (is (string= "assistant" (gethash "role" (second messages)))))))

(test session-store-persists-across-reload
  (let* ((store (make-temp-store))
         (root (cl-claw.sessions.store:session-store-root-dir store)))
    (declare (type cl-claw.sessions.store:session-store store)
             (type string root))
    (cl-claw.sessions.transcript:append-transcript-message store "session-A" "user" "msg-1")
    (let ((store2 (cl-claw.sessions.store:create-session-store :root-dir root)))
      (declare (type cl-claw.sessions.store:session-store store2))
      (let ((messages (cl-claw.sessions.transcript:read-session-transcript store2 "session-A")))
        (is (= 1 (length messages)))
        (is (string= "msg-1" (gethash "content" (first messages))))))))

(test transcript-compaction-keeps-tail-and-marker
  (let ((store (make-temp-store)))
    (declare (type cl-claw.sessions.store:session-store store))
    (loop for i from 1 to 6 do
      (cl-claw.sessions.transcript:append-transcript-message
       store "my-session" "user" (format nil "m~d" i)))
    (let ((result (cl-claw.sessions.compaction:compact-session-transcript
                   store "my-session" :max-messages 3)))
      (declare (type cl-claw.sessions.compaction:compaction-result result))
      (is-true (cl-claw.sessions.compaction:compaction-result-changed-p result))
      (is (= 6 (cl-claw.sessions.compaction:compaction-result-before-count result)))
      (is (= 4 (cl-claw.sessions.compaction:compaction-result-after-count result)))
      (let ((messages (cl-claw.sessions.transcript:read-session-transcript store "my-session")))
        (is (= 4 (length messages)))
        (is (string= "system" (gethash "role" (first messages))))
        (is (string= "m4" (gethash "content" (second messages))))
        (is (string= "m6" (gethash "content" (fourth messages))))))))

(test compaction-noop-when-under-threshold
  (let ((store (make-temp-store)))
    (declare (type cl-claw.sessions.store:session-store store))
    (cl-claw.sessions.transcript:append-transcript-message store "small" "user" "a")
    (let ((result (cl-claw.sessions.compaction:compact-session-transcript
                   store "small" :max-messages 5)))
      (declare (type cl-claw.sessions.compaction:compaction-result result))
      (is-false (cl-claw.sessions.compaction:compaction-result-changed-p result))
      (is (= 1 (cl-claw.sessions.compaction:compaction-result-after-count result))))))