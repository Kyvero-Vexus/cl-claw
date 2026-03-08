;;;; core.lisp — daemon/service installation helpers

(defpackage :cl-claw.daemon
  (:use :cl)
  (:export
   :detect-service-manager
   :generate-systemd-unit
   :generate-launchd-plist
   :generate-schtasks-command
   :build-daemon-install-plan))

(in-package :cl-claw.daemon)

(declaim (optimize (safety 3) (debug 3)))

(declaim (ftype (function (string) keyword) detect-service-manager))
(defun detect-service-manager (os-name)
  (declare (type string os-name))
  (let ((norm (string-downcase os-name)))
    (declare (type string norm))
    (cond
      ((or (search "linux" norm) (search "gnu" norm)) :systemd)
      ((or (search "darwin" norm) (search "mac" norm)) :launchd)
      ((search "win" norm) :schtasks)
      (t :unknown))))

(declaim (ftype (function (hash-table) string) generate-systemd-unit))
(defun generate-systemd-unit (options)
  (declare (type hash-table options))
  (let ((description (or (gethash "description" options) "OpenClaw Gateway"))
        (exec-start (or (gethash "execStart" options) "openclaw gateway start"))
        (working-directory (or (gethash "workingDirectory" options) "%h/.openclaw"))
        (restart-policy (or (gethash "restart" options) "on-failure"))
        (user (or (gethash "user" options) "%i")))
    (declare (type string description exec-start working-directory restart-policy user))
    (format nil "[Unit]~%Description=~a~%After=network-online.target~%~%[Service]~%Type=simple~%User=~a~%WorkingDirectory=~a~%ExecStart=~a~%Restart=~a~%~%[Install]~%WantedBy=default.target~%"
            description user working-directory exec-start restart-policy)))

(declaim (ftype (function (hash-table) string) generate-launchd-plist))
(defun generate-launchd-plist (options)
  (declare (type hash-table options))
  (let ((label (or (gethash "label" options) "group.openclaw.gateway"))
        (program (or (gethash "program" options) "/usr/local/bin/openclaw"))
        (working-directory (or (gethash "workingDirectory" options) "~/.openclaw")))
    (declare (type string label program working-directory))
    (format nil "<?xml version=\"1.0\" encoding=\"UTF-8\"?>~%<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">~%<plist version=\"1.0\">~%  <dict>~%    <key>Label</key><string>~a</string>~%    <key>ProgramArguments</key>~%    <array><string>~a</string><string>gateway</string><string>start</string></array>~%    <key>WorkingDirectory</key><string>~a</string>~%    <key>RunAtLoad</key><true/>~%    <key>KeepAlive</key><true/>~%  </dict>~%</plist>~%"
            label program working-directory)))

(declaim (ftype (function (hash-table) string) generate-schtasks-command))
(defun generate-schtasks-command (options)
  (declare (type hash-table options))
  (let ((task-name (or (gethash "taskName" options) "OpenClawGateway"))
        (exec (or (gethash "exec" options) "openclaw gateway start"))
        (user (or (gethash "user" options) "%USERNAME%")))
    (declare (type string task-name exec user))
    (format nil "schtasks /Create /SC ONLOGON /TN \"~a\" /TR \"~a\" /RU \"~a\" /F"
            task-name exec user)))

(declaim (ftype (function (keyword hash-table) list) build-daemon-install-plan))
(defun build-daemon-install-plan (manager options)
  (declare (type keyword manager)
           (type hash-table options))
  (ecase manager
    (:systemd
     (list "write ~/.config/systemd/user/openclaw-gateway.service"
           "systemctl --user daemon-reload"
           "systemctl --user enable --now openclaw-gateway.service"
           (generate-systemd-unit options)))
    (:launchd
     (list "write ~/Library/LaunchAgents/group.openclaw.gateway.plist"
           "launchctl unload ~/Library/LaunchAgents/group.openclaw.gateway.plist || true"
           "launchctl load ~/Library/LaunchAgents/group.openclaw.gateway.plist"
           (generate-launchd-plist options)))
    (:schtasks
     (list "create scheduled task for logon"
           (generate-schtasks-command options)))))
