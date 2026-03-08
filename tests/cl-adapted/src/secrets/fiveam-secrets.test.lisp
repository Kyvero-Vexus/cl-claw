;;;; FiveAM tests for cl-claw secrets domain
;;;;
;;;; Tests for: resolve, storage, audit

(defpackage :cl-claw.secrets.test
  (:use :cl :fiveam))
(in-package :cl-claw.secrets.test)

(def-suite secrets-suite
  :description "Tests for the cl-claw secrets domain")

(in-suite secrets-suite)

;;; ─── storage tests ───────────────────────────────────────────────────────────

(def-suite storage-suite
  :description "Secret storage tests"
  :in secrets-suite)

(in-suite storage-suite)

(test create-secret-store-empty
  "Creates an empty secret store"
  (let ((store (cl-claw.secrets.storage:create-secret-store)))
    (declare (type cl-claw.secrets.storage:secret-store store))
    (is (null (cl-claw.secrets.storage:retrieve-secret store "missing")))))

(test store-and-retrieve-secret
  "Store and retrieve a secret"
  (let ((store (cl-claw.secrets.storage:create-secret-store)))
    (declare (type cl-claw.secrets.storage:secret-store store))
    (cl-claw.secrets.storage:store-secret store "mykey" "mysecret")
    (is (string= "mysecret"
                 (cl-claw.secrets.storage:retrieve-secret store "mykey")))))

(test retrieve-missing-secret-returns-nil
  "Retrieving a missing secret returns nil"
  (let ((store (cl-claw.secrets.storage:create-secret-store)))
    (declare (type cl-claw.secrets.storage:secret-store store))
    (is (null (cl-claw.secrets.storage:retrieve-secret store "nonexistent")))))

(test delete-secret-returns-true-if-existed
  "Delete returns T if the secret existed"
  (let ((store (cl-claw.secrets.storage:create-secret-store)))
    (declare (type cl-claw.secrets.storage:secret-store store))
    (cl-claw.secrets.storage:store-secret store "temp" "value")
    (is-true (cl-claw.secrets.storage:delete-secret store "temp"))
    (is (null (cl-claw.secrets.storage:retrieve-secret store "temp")))))

(test delete-nonexistent-secret-returns-false
  "Delete returns NIL if secret didn't exist"
  (let ((store (cl-claw.secrets.storage:create-secret-store)))
    (declare (type cl-claw.secrets.storage:secret-store store))
    (is-false (cl-claw.secrets.storage:delete-secret store "doesnotexist"))))

(test list-secret-names-returns-sorted-names
  "List returns sorted secret names"
  (let ((store (cl-claw.secrets.storage:create-secret-store)))
    (declare (type cl-claw.secrets.storage:secret-store store))
    (cl-claw.secrets.storage:store-secret store "c-key" "c")
    (cl-claw.secrets.storage:store-secret store "a-key" "a")
    (cl-claw.secrets.storage:store-secret store "b-key" "b")
    (let ((names (cl-claw.secrets.storage:list-secret-names store)))
      (declare (type list names))
      (is (equal '("a-key" "b-key" "c-key") names)))))

(test store-snapshot-returns-copy
  "Snapshot returns an independent copy"
  (let ((store (cl-claw.secrets.storage:create-secret-store)))
    (declare (type cl-claw.secrets.storage:secret-store store))
    (cl-claw.secrets.storage:store-secret store "key1" "val1")
    (let ((snap (cl-claw.secrets.storage:store-snapshot store)))
      (declare (type hash-table snap))
      (is (string= "val1" (gethash "key1" snap))))))

(test create-secret-store-with-file-path-and-persist
  "Secret store can persist to and load from a file"
  (let* ((tmpdir (uiop:temporary-directory))
         (path   (uiop:native-namestring
                  (merge-pathnames
                   (format nil "cl-claw-secret-~a.json" (random 1000000))
                   tmpdir))))
    (declare (type string path))
    ;; Write a secret
    (let ((store (cl-claw.secrets.storage:create-secret-store :path path)))
      (declare (type cl-claw.secrets.storage:secret-store store))
      (cl-claw.secrets.storage:store-secret store "persistent-key" "persistent-val"))
    ;; Re-read from file
    (let ((store2 (cl-claw.secrets.storage:create-secret-store :path path)))
      (declare (type cl-claw.secrets.storage:secret-store store2))
      (is (string= "persistent-val"
                   (cl-claw.secrets.storage:retrieve-secret store2 "persistent-key"))))
    ;; Cleanup
    (ignore-errors (delete-file path))))

;;; ─── resolve tests ───────────────────────────────────────────────────────────

(def-suite resolve-suite
  :description "Secret resolution tests"
  :in secrets-suite)

(in-suite resolve-suite)

(test resolve-secret-ref-string-invalid-ref
  "Returns error for invalid secret ref"
  (let ((result (cl-claw.secrets.resolve:resolve-secret-ref-string
                 "${not-a-secret}" (make-hash-table :test 'equal))))
    (declare (type cl-claw.secrets.resolve:secret-result result))
    (is (not (null (cl-claw.secrets.resolve:secret-result-error result))))))

(test resolve-secret-ref-string-undefined-secret
  "Returns error when secret name not found in config"
  (let ((config (make-hash-table :test 'equal)))
    (declare (type hash-table config))
    (let ((result (cl-claw.secrets.resolve:resolve-secret-ref-string
                   "${secret:mykey}" config)))
      (declare (type cl-claw.secrets.resolve:secret-result result))
      (is (not (null (cl-claw.secrets.resolve:secret-result-error result)))))))

(test resolve-file-secret-from-existing-file
  "Resolves a file secret from a real file"
  (let* ((tmpdir (uiop:temporary-directory))
         (path   (uiop:native-namestring
                  (merge-pathnames
                   (format nil "cl-claw-secret-file-~a.txt" (random 1000000))
                   tmpdir))))
    (declare (type string path))
    (uiop:with-output-file (out path :if-exists :supersede)
      (write-string "my-secret-value" out))
    (let ((result (cl-claw.secrets.resolve:resolve-secret-ref-string
                   "${secret:myfile}"
                   (let ((config (make-hash-table :test 'equal)))
                     (let ((secrets (make-hash-table :test 'equal)))
                       (let ((file-config (make-hash-table :test 'equal)))
                         (setf (gethash "source" file-config) "file")
                         (setf (gethash "path" file-config) path)
                         (setf (gethash "mode" file-config) "singleValue")
                         (setf (gethash "myfile" secrets) file-config))
                       (setf (gethash "secrets" config) secrets))
                     config))))
      (declare (type cl-claw.secrets.resolve:secret-result result))
      (is (string= "my-secret-value"
                   (cl-claw.secrets.resolve:secret-result-value result)))
      (is (null (cl-claw.secrets.resolve:secret-result-error result))))
    (ignore-errors (delete-file path))))

(test resolve-secret-ref-value-expands-strings
  "Resolves secret refs in nested structures"
  (let ((config (make-hash-table :test 'equal)))
    (declare (type hash-table config))
    ;; Test with non-secret string → unchanged
    (let ((result (cl-claw.secrets.resolve:resolve-secret-ref-value "hello" config)))
      (is (string= "hello" result)))
    ;; Test with nested hash-table
    (let ((ht (make-hash-table :test 'equal)))
      (declare (type hash-table ht))
      (setf (gethash "key" ht) "value")
      (let ((result (cl-claw.secrets.resolve:resolve-secret-ref-value ht config)))
        (is (hash-table-p result))
        (is (string= "value" (gethash "key" result)))))))

;;; ─── audit tests ─────────────────────────────────────────────────────────────

(def-suite secrets-audit-suite
  :description "Secrets audit tests"
  :in secrets-suite)

(in-suite secrets-audit-suite)

(test run-secrets-audit-returns-clean-for-empty-dir
  "Returns clean report for empty state directory"
  (let* ((tmpdir (uiop:temporary-directory))
         (state-dir (uiop:native-namestring
                     (merge-pathnames
                      (format nil "cl-claw-audit-~a/" (random 1000000))
                      tmpdir))))
    (declare (type string state-dir))
    (ensure-directories-exist state-dir)
    (let ((report (cl-claw.secrets.audit:run-secrets-audit
                   :state-dir state-dir)))
      (declare (type cl-claw.secrets.audit:audit-report report))
      (is-true (cl-claw.secrets.audit:audit-report-clean-p report))
      (is (null (cl-claw.secrets.audit:audit-report-findings report))))))

(test run-secrets-audit-detects-hardcoded-api-key
  "Detects hardcoded API key in config file"
  (let* ((tmpdir (uiop:temporary-directory))
         (state-dir (uiop:native-namestring
                     (merge-pathnames
                      (format nil "cl-claw-audit2-~a/" (random 1000000))
                      tmpdir)))
         (config-path (format nil "~aopenclaw.json" state-dir)))
    (declare (type string state-dir config-path))
    (ensure-directories-exist state-dir)
    ;; Write a config with a hardcoded API key (fake)
    (with-open-file (f config-path :direction :output :if-does-not-exist :create)
      (write-string
       "{\"api_key\": \"sk-1234567890abcdefghijklmnopqrstuvwxyz1234\"}"
       f))
    (let ((report (cl-claw.secrets.audit:run-secrets-audit
                   :state-dir state-dir
                   :config-path config-path)))
      (declare (type cl-claw.secrets.audit:audit-report report))
      ;; Should find the hardcoded key
      (is-false (cl-claw.secrets.audit:audit-report-clean-p report)))
    ;; Cleanup
    (ignore-errors (delete-file config-path))))
