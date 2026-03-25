;;;; allowlists-test.lisp — Tests for channels allowlists management

(in-package :cl-claw.channels.tests)

(in-suite :channels-allowlists)

(defun %make-allowlist-entry (user-id &key (roles '()))
  "Create an allowlist entry struct."
  (cl-claw.channels::make-allowlist-entry :id user-id :roles roles))

(test allowlists-add-to-allowlist
  "Adds user to allowlist"
  (let ((mgr (cl-claw.channels:make-allowlist-manager)))
    (cl-claw.channels:allowlist-add mgr (%make-allowlist-entry "user1"))
    (let ((found (cl-claw.channels:allowlist-get mgr "user1")))
      (is (not (null found))))))

(test allowlists-remove-from-allowlist
  "Removes user from allowlist"
  (let ((mgr (cl-claw.channels:make-allowlist-manager)))
    (cl-claw.channels:allowlist-add mgr (%make-allowlist-entry "user2"))
    (cl-claw.channels:allowlist-remove mgr "user2")
    (is (null (cl-claw.channels:allowlist-get mgr "user2")))))

(test allowlists-check-user-allowed
  "Checks if user is allowed"
  (let ((mgr (cl-claw.channels:make-allowlist-manager)))
    (cl-claw.channels:allowlist-add mgr (%make-allowlist-entry "user3" :roles '("admin")))
    (is (cl-claw.channels:allowlist-contains-p mgr "user3"))))

(test allowlists-get-roles
  "Gets user roles"
  (let ((mgr (cl-claw.channels:make-allowlist-manager)))
    (cl-claw.channels:allowlist-add mgr (%make-allowlist-entry "user4" :roles '("user" "admin")))
    (let ((roles (cl-claw.channels:allowlist-get-roles mgr "user4")))
      (is (not (null roles)))
      (is (= 2 (length roles))))))

(test allowlists-update-roles
  "Updates user roles"
  (let ((mgr (cl-claw.channels:make-allowlist-manager)))
    (cl-claw.channels:allowlist-add mgr (%make-allowlist-entry "user5"))
    (cl-claw.channels:allowlist-update-roles mgr "user5" '("moderator"))
    (let ((roles (cl-claw.channels:allowlist-get-roles mgr "user5")))
      (is (not (null roles)))
      (is (member "moderator" roles :test #'string=)))))
