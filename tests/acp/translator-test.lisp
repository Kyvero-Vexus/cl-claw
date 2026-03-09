;;;; translator-test.lisp — Tests for ACP translator (prompt prefix, rate limiter, size)

(in-package :cl-claw.acp.tests)

(in-suite :acp-translator)

;;; ─── Home Redaction ─────────────────────────────────────────────────────────

(test translator-redact-home-exact
  "Redacts exact home directory to ~"
  (is (string= "~" (cl-claw.acp.translator:redact-home-in-path "/home/user" "/home/user"))))

(test translator-redact-home-subdir
  "Redacts home prefix in subdirectory"
  (is (string= "~/projects/foo"
                (cl-claw.acp.translator:redact-home-in-path
                 "/home/user/projects/foo" "/home/user"))))

(test translator-redact-home-no-match
  "Preserves path when it doesn't start with home"
  (is (string= "/opt/stuff"
                (cl-claw.acp.translator:redact-home-in-path "/opt/stuff" "/home/user"))))

(test translator-redact-home-trailing-slash
  "Handles trailing slash on home directory"
  (is (string= "~/work"
                (cl-claw.acp.translator:redact-home-in-path
                 "/home/user/work" "/home/user/"))))

;;; ─── CWD Prefix ─────────────────────────────────────────────────────────────

(test translator-prefix-cwd
  "Prepends working directory to message"
  (let ((result (cl-claw.acp.translator:prefix-prompt-with-cwd
                 "hello" "/home/user/project" :prefix-cwd t)))
    (is (search "[Working directory:" result))
    (is (search "hello" result))))

(test translator-prefix-cwd-redacted
  "Redacts home in CWD prefix"
  (let ((result (cl-claw.acp.translator:prefix-prompt-with-cwd
                 "hi" (concatenate 'string (namestring (user-homedir-pathname)) "test")
                 :prefix-cwd t)))
    (is (search "~" result))))

(test translator-prefix-cwd-disabled
  "Does not prefix when disabled"
  (let ((result (cl-claw.acp.translator:prefix-prompt-with-cwd
                 "hello" "/work" :prefix-cwd nil)))
    (is (string= "hello" result))))

(test translator-prefix-cwd-empty
  "Does not prefix with empty CWD"
  (let ((result (cl-claw.acp.translator:prefix-prompt-with-cwd
                 "hello" "" :prefix-cwd t)))
    (is (string= "hello" result))))

;;; ─── Rate Limiter ───────────────────────────────────────────────────────────

(test translator-rate-limiter-allows
  "Rate limiter allows requests within limit"
  (let ((rl (cl-claw.acp.translator:make-rate-limiter :max-requests 3 :window-ms 60000)))
    (is (cl-claw.acp.translator:rate-limiter-allow-p rl :now 1000))
    (is (cl-claw.acp.translator:rate-limiter-allow-p rl :now 1001))
    (is (cl-claw.acp.translator:rate-limiter-allow-p rl :now 1002))))

(test translator-rate-limiter-rejects
  "Rate limiter rejects requests beyond limit"
  (let ((rl (cl-claw.acp.translator:make-rate-limiter :max-requests 2 :window-ms 60000)))
    (is (cl-claw.acp.translator:rate-limiter-allow-p rl :now 1000))
    (is (cl-claw.acp.translator:rate-limiter-allow-p rl :now 1001))
    (is (not (cl-claw.acp.translator:rate-limiter-allow-p rl :now 1002)))))

(test translator-rate-limiter-window-expiry
  "Rate limiter allows after window expires"
  (let ((rl (cl-claw.acp.translator:make-rate-limiter :max-requests 1 :window-ms 1000)))
    (is (cl-claw.acp.translator:rate-limiter-allow-p rl :now 1000))
    (is (not (cl-claw.acp.translator:rate-limiter-allow-p rl :now 1500)))
    ;; After window
    (is (cl-claw.acp.translator:rate-limiter-allow-p rl :now 2001))))

(test translator-rate-limiter-reset
  "Rate limiter reset clears all timestamps"
  (let ((rl (cl-claw.acp.translator:make-rate-limiter :max-requests 1 :window-ms 60000)))
    (is (cl-claw.acp.translator:rate-limiter-allow-p rl :now 1000))
    (is (not (cl-claw.acp.translator:rate-limiter-allow-p rl :now 1001)))
    (cl-claw.acp.translator:rate-limiter-reset rl)
    (is (cl-claw.acp.translator:rate-limiter-allow-p rl :now 1002))))

;;; ─── Prompt Size Validation ─────────────────────────────────────────────────

(test translator-prompt-size-ok
  "Accepts prompts within size limit"
  (is (cl-claw.acp.translator:validate-prompt-size "hello" :max-bytes 1000)))

(test translator-prompt-size-reject
  "Rejects oversized prompts"
  (let ((big (make-string 2000 :initial-element #\a)))
    (signals cl-claw.acp.types:acp-error
      (cl-claw.acp.translator:validate-prompt-size big :max-bytes 1000))))
