;;;; session-test.lisp — Tests for channels session management

(in-package :cl-claw.channels.tests)

(in-suite :channels-session)

(defun %make-test-session (session-id channel-id)
  "Create a test session object."
  (cl-claw.channels:make-session :id session-id :channel-id channel-id :active t))

(test session-create-session
  "Creates a new session"
  (let ((session (%make-test-session "test-sess-1" "test-channel")))
    (is (not (null session)))
    (is (string= "test-sess-1" (cl-claw.channels::channel-session-id session)))))

(test session-get-session-by-id
  "Retrieves session by ID"
  (%make-test-session "test-sess-2" "test-channel")
  (let ((found (cl-claw.channels:get-session-by-id "test-sess-2")))
    (is (not (null found)))
    (is (string= "test-sess-2" (cl-claw.channels::channel-session-id found)))))

(test session-delete-session
  "Deletes a session"
  (%make-test-session "test-sess-3" "test-channel")
  (cl-claw.channels:delete-session "test-sess-3")
  (is (null (cl-claw.channels:get-session-by-id "test-sess-3"))))

(test session-update-session
  "Updates session properties"
  (%make-test-session "test-sess-4" "test-channel")
  (let ((updated (cl-claw.channels:update-session "test-sess-4" :active nil)))
    (is (not (null updated)))))
