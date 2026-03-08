;;;; fiveam-state-migrations.test.lisp - FiveAM tests for state-migrations module

(defpackage :cl-claw.infra.state-migrations.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.state-migrations.test)

(def-suite state-migrations-suite
  :description "Tests for the state-migrations module")
(in-suite state-migrations-suite)

(defun make-temp-dir ()
  "Create a temporary directory for testing."
  (let ((path (uiop:native-namestring
               (merge-pathnames (format nil "cl-claw-test-~a/" (random 999999))
                                (uiop:temporary-directory)))))
    (uiop:ensure-all-directories-exist (list path))
    path))

(defun cleanup-dir (path)
  "Remove a temporary test directory."
  (uiop:delete-directory-tree (uiop:ensure-directory-pathname path) :validate t))

(test reset-for-test-works
  "reset-auto-migrate-for-test clears migration state"
  (cl-claw.infra.state-migrations:reset-auto-migrate-for-test)
  (is (eql t t)))  ; Just verifying it doesn't error

(test no-migration-when-target-already-exists
  "No migration when .openclaw already exists"
  (cl-claw.infra.state-migrations:reset-auto-migrate-for-test)
  (let ((temp (make-temp-dir)))
    (unwind-protect
         (let* ((target (uiop:native-namestring
                          (merge-pathnames ".openclaw/"
                                           (uiop:ensure-directory-pathname temp)))))
           ;; Create target directory
           (uiop:ensure-all-directories-exist (list target))
           (let ((result (cl-claw.infra.state-migrations:auto-migrate-legacy-state-dir
                          :homedir temp)))
             (is-false (cl-claw.infra.state-migrations:migration-result-migrated result))))
      (cleanup-dir temp))))

(test no-migration-when-no-legacy-dirs
  "No migration when no legacy directories exist"
  (cl-claw.infra.state-migrations:reset-auto-migrate-for-test)
  (let ((temp (make-temp-dir)))
    (unwind-protect
         (let ((result (cl-claw.infra.state-migrations:auto-migrate-legacy-state-dir
                        :homedir temp)))
           (is-false (cl-claw.infra.state-migrations:migration-result-migrated result)))
      (cleanup-dir temp))))

(test migration-result-structure
  "Migration result has expected fields"
  (cl-claw.infra.state-migrations:reset-auto-migrate-for-test)
  (let ((result (cl-claw.infra.state-migrations:auto-migrate-legacy-state-dir
                 :homedir "/tmp/nonexistent-test-dir")))
    (is (not (null result)))
    (is (listp (cl-claw.infra.state-migrations:migration-result-warnings result)))))

(test idempotent-migration
  "Migration only runs once per session"
  (cl-claw.infra.state-migrations:reset-auto-migrate-for-test)
  (let ((temp (make-temp-dir)))
    (unwind-protect
         (progn
           ;; First call
           (cl-claw.infra.state-migrations:auto-migrate-legacy-state-dir :homedir temp)
           ;; Second call should be idempotent (state already set)
           (let ((result (cl-claw.infra.state-migrations:auto-migrate-legacy-state-dir
                          :homedir temp)))
             (is-false (cl-claw.infra.state-migrations:migration-result-migrated result))))
      (cleanup-dir temp))))

(test migrates-legacy-moltbot-dir
  "Migrates .moltbot to .openclaw when it exists"
  (cl-claw.infra.state-migrations:reset-auto-migrate-for-test)
  (let* ((temp (make-temp-dir))
         (legacy-dir (uiop:native-namestring
                       (merge-pathnames ".moltbot/"
                                         (uiop:ensure-directory-pathname temp))))
         (marker-file (merge-pathnames "marker.txt"
                                        (uiop:ensure-directory-pathname legacy-dir))))
    (unwind-protect
         (progn
           ;; Create legacy dir with a marker file
           (uiop:ensure-all-directories-exist (list legacy-dir))
           (with-open-file (f marker-file :direction :output :if-exists :supersede)
             (write-string "ok" f))
           (let ((result (cl-claw.infra.state-migrations:auto-migrate-legacy-state-dir
                          :homedir temp)))
             ;; Migration should have occurred
             (is-true (cl-claw.infra.state-migrations:migration-result-migrated result))
             (is (null (cl-claw.infra.state-migrations:migration-result-warnings result)))))
      (cleanup-dir temp))))
