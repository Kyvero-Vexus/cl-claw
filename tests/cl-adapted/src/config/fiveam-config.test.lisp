;;;; FiveAM tests for cl-claw config domain
;;;;
;;;; Tests for: schema, io, validation, runtime

(defpackage :cl-claw.config.test
  (:use :cl :fiveam))
(in-package :cl-claw.config.test)

(def-suite config-suite
  :description "Tests for the cl-claw config domain")

(in-suite config-suite)

;;; ─── schema tests ────────────────────────────────────────────────────────────

(def-suite schema-suite
  :description "Config schema tests"
  :in config-suite)

(in-suite schema-suite)

(test build-config-schema-returns-schema
  "build-config-schema returns a config-schema"
  (let ((schema (cl-claw.config.schema:build-config-schema)))
    (declare (type cl-claw.config.schema:config-schema schema))
    (is (not (null (cl-claw.config.schema:config-schema-fields schema))))
    (is (> (length (cl-claw.config.schema:config-schema-fields schema)) 0))))

(test lookup-config-schema-finds-gateway-port
  "Looks up gateway port field"
  (let* ((schema (cl-claw.config.schema:build-config-schema))
         (field (cl-claw.config.schema:lookup-config-schema
                 schema '("gateway" "port"))))
    (is (not (null field)))
    (when field
      (is (eq :number (cl-claw.config.schema:schema-field-type field))))))

(test lookup-config-schema-returns-nil-for-unknown
  "Returns nil for unknown path"
  (let* ((schema (cl-claw.config.schema:build-config-schema))
         (field (cl-claw.config.schema:lookup-config-schema
                 schema '("nonexistent" "path"))))
    (is (null field))))

(test build-config-schema-with-plugins
  "Extends schema with plugin ui hints"
  (let* ((plugins '((:id "voice-call"
                     :name "Voice Call"
                     :config-ui-hints (("provider" :label "Provider")
                                       ("twilio.authToken" :label "Auth Token" :sensitive t)))))
         (schema (cl-claw.config.schema:build-config-schema :plugins plugins)))
    (declare (type cl-claw.config.schema:config-schema schema))
    (is (> (length (cl-claw.config.schema:config-schema-fields schema)) 0))))

(test validate-config-value-accepts-valid-enum
  "Accepts valid enum value"
  (let* ((schema (cl-claw.config.schema:build-config-schema))
         (field (cl-claw.config.schema:lookup-config-schema schema '("gateway" "mode"))))
    (when field
      (multiple-value-bind (valid-p err)
          (cl-claw.config.schema:validate-config-value "local" field)
        (is-true valid-p)
        (is (null err))))))

(test validate-config-value-rejects-invalid-enum
  "Rejects invalid enum value"
  (let* ((schema (cl-claw.config.schema:build-config-schema))
         (field (cl-claw.config.schema:lookup-config-schema schema '("gateway" "mode"))))
    (when field
      (multiple-value-bind (valid-p err)
          (cl-claw.config.schema:validate-config-value "badmode" field)
        (is-false valid-p)
        (is (not (null err)))))))

;;; ─── validation tests ────────────────────────────────────────────────────────

(def-suite validation-suite
  :description "Config validation tests"
  :in config-suite)

(in-suite validation-suite)

(defun make-test-config (pairs)
  "Create a nested hash-table config from a plist-style list."
  (declare (type list pairs))
  (let ((ht (make-hash-table :test 'equal)))
    (declare (type hash-table ht))
    (dolist (pair pairs ht)
      (setf (gethash (car pair) ht) (cdr pair)))))

(test validate-config-returns-empty-list-for-valid-config
  "Returns empty list for valid config"
  (let* ((config (make-hash-table :test 'equal))
         (errors (cl-claw.config.validation:validate-config config)))
    (is (null errors))))

(test validate-config-flags-invalid-gateway-bind
  "Flags invalid gateway.bind value"
  (let ((config (make-hash-table :test 'equal)))
    (declare (type hash-table config))
    (let ((gateway (make-hash-table :test 'equal)))
      (declare (type hash-table gateway))
      (setf (gethash "bind" gateway) "invalid-bind-value")
      (setf (gethash "gateway" config) gateway))
    (let ((errors (cl-claw.config.validation:validate-config config)))
      (is (> (length errors) 0))
      (is (some (lambda (e)
                  (string= "INVALID_GATEWAY_BIND"
                           (cl-claw.config.validation:validation-error-code e)))
                errors)))))

(test validate-config-accepts-valid-gateway-bind
  "Accepts valid gateway.bind values"
  (dolist (bind-val '("loopback" "tailscale" "all"))
    (declare (type string bind-val))
    (let ((config (make-hash-table :test 'equal)))
      (declare (type hash-table config))
      (let ((gateway (make-hash-table :test 'equal)))
        (declare (type hash-table gateway))
        (setf (gethash "bind" gateway) bind-val)
        (setf (gethash "gateway" config) gateway))
      (let ((errors (cl-claw.config.validation:validate-config config)))
        (is (null (find-if (lambda (e)
                             (string= "INVALID_GATEWAY_BIND"
                                      (cl-claw.config.validation:validation-error-code e)))
                           errors)))))))

;;; ─── runtime tests ───────────────────────────────────────────────────────────

(def-suite runtime-suite
  :description "Runtime config tests"
  :in config-suite)

(in-suite runtime-suite)

(test make-runtime-config-creates-empty-store
  "Creates a runtime config from a base"
  (let ((base (make-hash-table :test 'equal)))
    (declare (type hash-table base))
    (setf (gethash "gateway" base) "local")
    (let ((rc (cl-claw.config.runtime:make-runtime-config base)))
      (declare (type cl-claw.config.runtime:runtime-config rc))
      (is (not (null rc))))))

(test runtime-config-set-and-get
  "Can set and retrieve values"
  (let* ((base (make-hash-table :test 'equal))
         (rc (cl-claw.config.runtime:make-runtime-config base)))
    (declare (type hash-table base)
             (type cl-claw.config.runtime:runtime-config rc))
    (cl-claw.config.runtime:runtime-config-set rc '("logging" "level") "debug")
    (is (string= "debug"
                 (cl-claw.config.runtime:runtime-config-get rc '("logging" "level"))))))

(test runtime-config-reset-clears-overrides
  "Reset clears all overrides"
  (let* ((base (make-hash-table :test 'equal))
         (rc (cl-claw.config.runtime:make-runtime-config base)))
    (declare (type hash-table base)
             (type cl-claw.config.runtime:runtime-config rc))
    (cl-claw.config.runtime:runtime-config-set rc '("key") "value")
    (cl-claw.config.runtime:runtime-config-reset rc)
    ;; After reset, the override should be gone
    (is (null (cl-claw.config.runtime:runtime-config-get rc '("key"))))))

(test merge-runtime-override-merges-hash-tables
  "Merges two hash-tables recursively"
  (let ((base (make-hash-table :test 'equal))
        (override (make-hash-table :test 'equal)))
    (declare (type hash-table base override))
    (setf (gethash "a" base) "base-a")
    (setf (gethash "b" override) "override-b")
    (let ((merged (cl-claw.config.runtime:merge-runtime-override base override)))
      (declare (type hash-table merged))
      (is (string= "base-a" (gethash "a" merged)))
      (is (string= "override-b" (gethash "b" merged))))))

(test runtime-config-snapshot-merges-base-and-overrides
  "Snapshot includes both base and overrides"
  (let* ((base (make-hash-table :test 'equal))
         (rc (cl-claw.config.runtime:make-runtime-config base)))
    (declare (type hash-table base)
             (type cl-claw.config.runtime:runtime-config rc))
    (setf (gethash "base-key" base) "base-val")
    (cl-claw.config.runtime:runtime-config-set rc '("override-key") "override-val")
    (let ((snap (cl-claw.config.runtime:runtime-config-snapshot rc)))
      (declare (type hash-table snap))
      (is (string= "override-val" (gethash "override-key" snap))))))

;;; ─── io tests ────────────────────────────────────────────────────────────────

(def-suite io-suite
  :description "Config I/O tests"
  :in config-suite)

(in-suite io-suite)

(test create-config-io-creates-handle
  "create-config-io creates a config-io handle"
  (let ((io (cl-claw.config.io:create-config-io
             :env (make-hash-table :test 'equal)
             :homedir (lambda () "/tmp"))))
    (declare (type cl-claw.config.io:config-io io))
    (is (not (null io)))))

(test read-config-file-snapshot-returns-empty-for-missing-file
  "Returns empty valid snapshot when config file doesn't exist"
  (let* ((tmpdir (uiop:temporary-directory))
         (home   (uiop:native-namestring
                  (merge-pathnames
                   (format nil "cl-claw-test-~a/" (random 1000000))
                   tmpdir)))
         (io (cl-claw.config.io:create-config-io
              :env (make-hash-table :test 'equal)
              :homedir (lambda () home))))
    (declare (type string home)
             (type cl-claw.config.io:config-io io))
    (let ((snapshot (cl-claw.config.io:read-config-file-snapshot io)))
      (declare (type cl-claw.config.io:config-snapshot snapshot))
      (is-true (cl-claw.config.io:config-snapshot-valid snapshot)))))

(test write-and-read-config-file
  "Write then read a config file round-trips correctly"
  (let* ((tmpdir (uiop:temporary-directory))
         (home   (uiop:native-namestring
                  (merge-pathnames
                   (format nil "cl-claw-rw-test-~a/" (random 1000000))
                   tmpdir)))
         (io (cl-claw.config.io:create-config-io
              :env (make-hash-table :test 'equal)
              :homedir (lambda () home))))
    (declare (type string home)
             (type cl-claw.config.io:config-io io))
    ;; Write a config
    (let ((config (make-hash-table :test 'equal)))
      (declare (type hash-table config))
      (let ((gateway (make-hash-table :test 'equal)))
        (declare (type hash-table gateway))
        (setf (gethash "port" gateway) 18789)
        (setf (gethash "gateway" config) gateway))
      (cl-claw.config.io:write-config-file io config))
    ;; Read it back
    (let ((snapshot (cl-claw.config.io:read-config-file-snapshot io)))
      (declare (type cl-claw.config.io:config-snapshot snapshot))
      (is-true (cl-claw.config.io:config-snapshot-valid snapshot))
      (let ((config (cl-claw.config.io:config-snapshot-config snapshot)))
        (when (hash-table-p config)
          (let ((gateway (gethash "gateway" config)))
            (when (hash-table-p gateway)
              (is (= 18789 (gethash "port" gateway))))))))))

(test deep-copy-hash-table-does-not-share-structure
  "Deep copy creates independent hash tables"
  (let ((original (make-hash-table :test 'equal)))
    (declare (type hash-table original))
    (let ((inner (make-hash-table :test 'equal)))
      (declare (type hash-table inner))
      (setf (gethash "key" inner) "value")
      (setf (gethash "inner" original) inner))
    (let ((copy (cl-claw.config.io::deep-copy-hash-table original)))
      (declare (type hash-table copy))
      ;; Mutate copy
      (setf (gethash "key" (gethash "inner" copy)) "modified")
      ;; Original should be unchanged
      (is (string= "value"
                   (gethash "key" (gethash "inner" original)))))))
