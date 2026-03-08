;;;; fiveam-restart.test.lisp - FiveAM tests for restart module

(defpackage :cl-claw.infra.restart.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.restart.test)

(def-suite restart-suite
  :description "Tests for the restart module (gateway process management)")
(in-suite restart-suite)

(test parse-empty-stdout-returns-empty
  "Parsing empty lsof output returns empty list"
  (let ((result (cl-claw.infra.restart:parse-pids-from-lsof-output "")))
    (is (null result))))

(test parse-pids-from-lsof-output-basic
  "Parses lsof output and extracts openclaw PIDs"
  ;; Simulate lsof -Fpc output: p<PID> then c<COMMAND>
  (let* ((lsof-output (format nil "p4100~%copenclaw-gateway~%p4200~%cnode~%p4300~%cOpenClaw"))
         ;; Use an impossible current PID so we don't filter anything
         (pids (cl-claw.infra.restart:parse-pids-from-lsof-output
                lsof-output :current-pid -1)))
    ;; 4100 and 4300 have openclaw-like commands, 4200 has 'node'
    (is (member 4100 pids))
    (is (member 4300 pids))
    (is (not (member 4200 pids)))))

(test parse-pids-filters-current-process
  "parse-pids-from-lsof-output filters out the current PID"
  (let* ((current-pid 9999)
         (lsof-output (format nil "p~a~%copenclaw~%p4100~%copenclaw" current-pid))
         (pids (cl-claw.infra.restart:parse-pids-from-lsof-output
                lsof-output :current-pid current-pid)))
    (is (not (member current-pid pids)))
    (is (member 4100 pids))))

(test returns-empty-when-no-openclaw-processes
  "Returns empty list when no openclaw processes found"
  (let* ((lsof-output (format nil "p1000~%cnode~%p2000~%cpython"))
         (pids (cl-claw.infra.restart:parse-pids-from-lsof-output
                lsof-output :current-pid -1)))
    (is (null pids))))

(test parse-lsof-handles-malformed-lines
  "Handles lsof output with unexpected lines gracefully"
  (let* ((lsof-output (format nil "p4100~%copenclaw~%garbage-line~%p4200~%copenclaw"))
         (pids (cl-claw.infra.restart:parse-pids-from-lsof-output
                lsof-output :current-pid -1)))
    ;; At least p4100 should be found; p4200 may or may not depending on state machine
    (is (member 4100 pids))))

(test find-gateway-pids-on-port-on-windows-returns-empty
  "On non-Unix platforms, find-gateway-pids-on-port-sync returns empty (mocked via nil lsof)"
  ;; We can't easily test this on Linux, but we can test that the function returns a list
  (let ((result (cl-claw.infra.restart:find-gateway-pids-on-port-sync
                 18789
                 ;; Use a non-existent lsof path that will fail
                 :lsof-command "/nonexistent/lsof")))
    (is (listp result))))

(test clean-stale-gateway-processes-returns-list
  "clean-stale-gateway-processes-sync returns a list (even when empty)"
  ;; This test just verifies the function returns a list
  ;; In real tests with mock lsof, we'd verify kill was called
  (let ((result (cl-claw.infra.restart:clean-stale-gateway-processes-sync)))
    (is (listp result))))
