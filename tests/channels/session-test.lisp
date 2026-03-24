;;;; session-test.lisp — Tests for channels session management

(in-package :cl-claw.channels.tests)

(in-suite :channels-session)

(defun %make-session-config (session-id channel-id)
  "Create test session configuration."
  (make-test-config
   "session-id" session-id
   "channel-id" channel-id
   "created-at" (get-universal-time)))

(defun %make-test-session (session-id channel-id)
  "Create a test session object."
  (let ((config (%make-session-config session-id channel-id)))
    (cl-claw.channels:make-session config)))

(test session-create-session
  "Creates a new session"
  (let ((session (%make-test-session "test-sess-1" "test-channel")))
    (is (not (null session))
    (is (string= "test-sess-1" (cl-claw.channels.types:session-id session)))
    (is (string= "test-channel" (cl-claw.channels.types:session-channel session)))))

(test session-get-session-by-id
  "Retrieves session by ID"
  (let ((session (%make-test-session "test-sess-2" "test-channel")))
    (let ((found (cl-claw.channels:get-session-by-id "test-sess-2")))
      (is (not (null found))
      (is (eq session found)))))

(test session-delete-session
  "Deletes a session"
  (let ((session (%make-test-session "test-sess-3" "test-channel")))
    (cl-claw.channels:delete-session "test-sess-3")
    (is (null (cl-claw.channels:get-session-by-id "test-sess-3")))))

(test session-update-session
  "Updates session properties"
  (let ((session (%make-test-session "test-sess-4" "test-channel")))
    (let ((updated (cl-claw.channels:update-session
                     "test-sess-4"
                     (list :active nil :metadata (hash "key" "value")))))
      (is (not (null updated))
      (is (gethash "metadata" updated)))))
