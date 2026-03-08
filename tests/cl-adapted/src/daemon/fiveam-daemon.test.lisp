;;;; FiveAM tests for daemon helpers

(defpackage :cl-claw.daemon.test
  (:use :cl :fiveam))

(in-package :cl-claw.daemon.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite daemon-suite
  :description "Tests for service-manager detection and daemon install artifacts")

(in-suite daemon-suite)

(defun %opts (&rest kv)
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kv by #'cddr do
      (setf (gethash k h) v))
    h))

(test detect-service-manager-by-os
  (is (eq :systemd (cl-claw.daemon:detect-service-manager "linux")))
  (is (eq :launchd (cl-claw.daemon:detect-service-manager "darwin")))
  (is (eq :schtasks (cl-claw.daemon:detect-service-manager "windows")))
  (is (eq :unknown (cl-claw.daemon:detect-service-manager "freebsd"))))

(test generate-systemd-unit-includes-required-fields
  (let ((unit (cl-claw.daemon:generate-systemd-unit
               (%opts "description" "OpenClaw Test"
                      "execStart" "/usr/bin/openclaw gateway start"
                      "workingDirectory" "/tmp/openclaw"
                      "restart" "always"
                      "user" "slime"))))
    (is (search "[Unit]" unit))
    (is (search "ExecStart=/usr/bin/openclaw gateway start" unit))
    (is (search "Restart=always" unit))))

(test generate-launchd-plist-includes-label-and-program
  (let ((plist (cl-claw.daemon:generate-launchd-plist
                (%opts "label" "group.openclaw.test"
                       "program" "/opt/bin/openclaw"))))
    (is (search "group.openclaw.test" plist))
    (is (search "/opt/bin/openclaw" plist))
    (is (search "<plist version=\"1.0\">" plist))))

(test generate-schtasks-command-has-task-and-command
  (let ((command (cl-claw.daemon:generate-schtasks-command
                  (%opts "taskName" "OpenClawTest"
                         "exec" "openclaw gateway start"
                         "user" "slime"))))
    (is (search "schtasks /Create" command))
    (is (search "OpenClawTest" command))
    (is (search "openclaw gateway start" command))))

(test build-daemon-install-plan-emits-platform-steps
  (let ((opts (%opts)))
    (is (= 4 (length (cl-claw.daemon:build-daemon-install-plan :systemd opts))))
    (is (= 4 (length (cl-claw.daemon:build-daemon-install-plan :launchd opts))))
    (is (= 2 (length (cl-claw.daemon:build-daemon-install-plan :schtasks opts))))))
