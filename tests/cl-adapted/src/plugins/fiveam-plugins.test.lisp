;;;; FiveAM tests for plugin manifest and hook integration

(defpackage :cl-claw.plugins.test
  (:use :cl :fiveam))

(in-package :cl-claw.plugins.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite plugins-suite
  :description "Tests for plugin manifest discovery/validation and hook registration")

(in-suite plugins-suite)

(defun %write-file (path content)
  (uiop:ensure-all-directories-exist (list path))
  (with-open-file (out path :direction :output :if-exists :supersede :if-does-not-exist :create)
    (write-string content out))
  path)

(test load-and-validate-plugin-manifest
  (let* ((tmp-root (merge-pathnames (format nil "cl-claw-plugins-~a/" (gensym "P"))
                                    (uiop:ensure-directory-pathname "/tmp")))
         (manifest-path (merge-pathnames "demo/plugin.json" tmp-root)))
    (unwind-protect
         (progn
           (%write-file manifest-path
                        "{\"name\":\"demo\",\"version\":\"1.0.0\",\"main\":\"index.js\",\"hooks\":[{\"event\":\"message:received\",\"handler\":\"onMessage\"}]}")
           (let* ((manifest (cl-claw.plugins:load-plugin-manifest-file (namestring manifest-path)))
                  (validation (cl-claw.plugins:validate-plugin-manifest manifest)))
             (is (string= "demo" (gethash "name" manifest)))
             (is-true (gethash "valid" validation))))
      (uiop:delete-directory-tree tmp-root :validate t :if-does-not-exist :ignore))))

(test discover-plugin-manifests-finds-plugin-json
  (let* ((tmp-root (merge-pathnames (format nil "cl-claw-plugins-~a/" (gensym "P"))
                                    (uiop:ensure-directory-pathname "/tmp")))
         (a (merge-pathnames "a/plugin.json" tmp-root))
         (b (merge-pathnames "b/plugin.json" tmp-root)))
    (unwind-protect
         (progn
           (%write-file a "{}")
           (%write-file b "{}")
           (is (= 2 (length (cl-claw.plugins:discover-plugin-manifests (namestring tmp-root))))))
      (uiop:delete-directory-tree tmp-root :validate t :if-does-not-exist :ignore))))

(test build-registry-and-register-hooks
  (let* ((manifest (make-hash-table :test 'equal))
         (hook (make-hash-table :test 'equal))
         (hook-registry (cl-claw.hooks:create-hook-registry)))
    (setf (gethash "name" manifest) "demo"
          (gethash "version" manifest) "1.0.0"
          (gethash "main" manifest) "index.js"
          (gethash "event" hook) "message:received"
          (gethash "handler" hook) "onMessage"
          (gethash "hooks" manifest) (list hook))
    (let ((registry (cl-claw.plugins:build-plugin-registry (list manifest))))
      (is (hash-table-p registry))
      (is (hash-table-p (gethash "demo" registry))))
    (let ((registrations (cl-claw.plugins:register-plugin-hooks manifest hook-registry)))
      (is (= 1 (length registrations)))
      (let ((results (cl-claw.hooks:run-hook hook-registry "message:received" :payload)))
        (is (= 1 (length results)))
        (is (string= "demo" (getf (first results) :plugin)))))))
