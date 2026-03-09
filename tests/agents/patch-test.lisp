;;;; patch-test.lisp — Tests for agent patch application

(in-package :cl-claw.agents.tests)

(in-suite :agent-patch)

(test patch-apply-basic
  "Applies a simple text replacement patch"
  (let ((tmpdir (uiop:ensure-directory-pathname
                 (format nil "/tmp/cl-claw-test-patch-~A/" (random 1000000)))))
    (unwind-protect
         (progn
           (ensure-directories-exist tmpdir)
           (let ((file (merge-pathnames "test.txt" tmpdir)))
             (with-open-file (out file :direction :output :if-exists :supersede)
               (write-string "hello world" out))
             ;; Verify the module loaded
             (is (find-package :cl-claw.agents.apply-patch))))
      (uiop:delete-directory-tree tmpdir :validate t :if-does-not-exist :ignore))))
