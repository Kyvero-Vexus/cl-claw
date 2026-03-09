;;;; fiveam-gateway-boot.test.lisp - Tests for gateway boot sequence

(defpackage :cl-claw.gateway.boot.test
  (:use :cl :fiveam)
  (:import-from :cl-claw.gateway.boot
                :run-boot-once
                :boot-result-status
                :boot-result-session-id
                :boot-result-error
                :boot-md-exists-p
                :read-boot-md))

(in-package :cl-claw.gateway.boot.test)

(def-suite gateway-boot-suite
  :description "Gateway boot sequence tests")

(in-suite gateway-boot-suite)

(defun make-temp-dir ()
  "Create a temporary directory for testing."
  (let ((dir (format nil "/tmp/cl-claw-boot-test-~a/" (random 1000000))))
    (ensure-directories-exist dir)
    dir))

(defun cleanup-temp-dir (dir)
  "Remove a temporary test directory."
  (uiop:delete-directory-tree (pathname dir) :validate t :if-does-not-exist :ignore))

(test boot-skips-when-no-boot-md
  "Skips when BOOT.md is missing"
  (let ((dir (make-temp-dir)))
    (unwind-protect
        (let ((result (run-boot-once :base-dir dir)))
          (is (eq :skipped (boot-result-status result)))
          (is (null (boot-result-session-id result))))
      (cleanup-temp-dir dir))))

(test boot-runs-when-boot-md-exists
  "Runs agent command when BOOT.md exists"
  (let ((dir (make-temp-dir))
        (agent-called nil)
        (agent-content nil))
    (unwind-protect
        (progn
          ;; Create BOOT.md
          (with-open-file (f (merge-pathnames "BOOT.md" dir)
                             :direction :output :if-exists :supersede)
            (write-string "Run initial setup" f))
          (let ((result (run-boot-once
                         :base-dir dir
                         :run-agent-fn (lambda (session-id content)
                                         (declare (ignore session-id))
                                         (setf agent-called t
                                               agent-content content))
                         :session-id-fn (lambda () "test-session-1"))))
            (is (eq :completed (boot-result-status result)))
            (is (string= "test-session-1" (boot-result-session-id result)))
            (is (eq t agent-called))
            (is (string= "Run initial setup" agent-content))))
      (cleanup-temp-dir dir))))

(test boot-returns-failed-when-read-fails
  "Returns failed when BOOT.md cannot be read"
  (let ((dir (make-temp-dir)))
    (unwind-protect
        (progn
          ;; Create BOOT.md as a regular file then make it unreadable
          (let ((path (merge-pathnames "BOOT.md" dir)))
            (with-open-file (f path :direction :output :if-exists :supersede)
              (write-string "test" f))
            ;; Make it unreadable
            (uiop:run-program (list "chmod" "000" (namestring path))))
          (let ((result (run-boot-once :base-dir dir)))
            ;; Should fail because BOOT.md can't be read
            (is (eq :failed (boot-result-status result)))
            (is (stringp (boot-result-error result)))))
      ;; Restore permissions for cleanup
      (let ((path (merge-pathnames "BOOT.md" dir)))
        (ignore-errors (uiop:run-program (list "chmod" "644" (namestring path)))))
      (cleanup-temp-dir dir))))

(test boot-failed-when-agent-throws
  "Returns failed when agent command throws"
  (let ((dir (make-temp-dir)))
    (unwind-protect
        (progn
          (with-open-file (f (merge-pathnames "BOOT.md" dir)
                             :direction :output :if-exists :supersede)
            (write-string "test" f))
          (let ((result (run-boot-once
                         :base-dir dir
                         :run-agent-fn (lambda (sid content)
                                         (declare (ignore sid content))
                                         (error "Agent command failed!"))
                         :session-id-fn (lambda () "test-session-2"))))
            (is (eq :failed (boot-result-status result)))
            (is (string= "test-session-2" (boot-result-session-id result)))
            (is (search "Agent command failed" (boot-result-error result)))))
      (cleanup-temp-dir dir))))

(test boot-uses-custom-session-id
  "Uses per-agent session key when provided"
  (let ((dir (make-temp-dir)))
    (unwind-protect
        (progn
          (with-open-file (f (merge-pathnames "BOOT.md" dir)
                             :direction :output :if-exists :supersede)
            (write-string "test" f))
          (let ((result (run-boot-once
                         :base-dir dir
                         :agent-id "my-agent"
                         :session-id-fn (lambda () "custom-id-123"))))
            (is (eq :completed (boot-result-status result)))
            (is (string= "custom-id-123" (boot-result-session-id result)))))
      (cleanup-temp-dir dir))))
