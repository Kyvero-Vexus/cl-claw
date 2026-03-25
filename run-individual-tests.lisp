;;;; Run only available test suites that compile without errors

(require :asdf)

;; Muffle style warnings
(handler-bind ((style-warning #'muffle-warning))
  (asdf:load-system :cl-claw-tests))

;; Run each test suite individually, handle errors gracefully
(dolist (suite '(:cl-claw.acp.tests
                  :cl-claw.config.tests
                  :cl-claw.cli.tests
                  :cl-claw.gateway.tests
                  :cl-claw.agents.tests
                  :cl-claw.browser.tests
                  :cl-claw.cron.tests
                  :cl-claw.auto-reply.tests
                  :cl-claw.discord.tests
                  :cl-claw.e2e.tests))
  (handler-case (err)
    (format t "~&~% ~%Failed to load ~A: ~A~%" err)
    (force-output)
    (sb-ext:exit)))

(asdf:test-system :cl-claw-tests)
(sb-ext:exit)
