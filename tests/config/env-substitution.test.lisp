;;;; FiveAM tests for config env-substitution

(in-package :cl-claw.config.tests)

(declaim (optimize (safety 3) (debug 3)))

(in-suite config-suite)

;; Helper to create hash tables
(defun %hash (&rest kv)
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kv by #'cddr do
      (setf (gethash k h) v))
    h))

;; Tests for env variable substitution

(test env-substitution-basic-direct
  "Substitutes direct env var reference"
  (let ((config (%hash "key" "${FOO}"))
        (env (%hash "FOO" "bar")))
    (let ((result (cl-claw.config.io:resolve-env-refs-in-value config env)))
      (is (string= "bar" (gethash "key" result))))))

(test env-substitution-multiple-vars-same-string
  "Substitutes multiple env vars in same string"
  (let ((config (%hash "key" "${A}/${B}"))
        (env (%hash "A" "x" "B" "y")))
    (let ((result (cl-claw.config.io:resolve-env-refs-in-value config env)))
      (is (string= "x/y" (gethash "key" result))))))

(test env-substitution-inline-prefix-suffix
  "Substitutes with inline prefix/suffix"
  (let ((config (%hash "key" "prefix-${FOO}-suffix"))
        (env (%hash "FOO" "bar")))
    (let ((result (cl-claw.config.io:resolve-env-refs-in-value config env)))
      (is (string= "prefix-bar-suffix" (gethash "key" result))))))

(test env-substitution-same-var-repeated
  "Substitutes same var repeated in string"
  (let ((config (%hash "key" "${FOO}:${FOO}"))
        (env (%hash "FOO" "bar")))
    (let ((result (cl-claw.config.io:resolve-env-refs-in-value config env)))
      (is (string= "bar:bar" (gethash "key" result))))))

(test env-substitution-nested-object
  "Substitutes variables in nested objects"
  (let ((config (%hash "outer" (%hash "inner" (%hash "key" "${API_KEY}"))))
        (env (%hash "API_KEY" "secret123")))
    (let ((result (cl-claw.config.io:resolve-env-refs-in-value config env)))
      (is (string= "secret123"
                   (gethash "key"
                            (gethash "inner"
                                     (gethash "outer" result))))))))

(test env-substitution-flat-array
  "Substitutes variables in flat arrays"
  (let ((config (%hash "items" (list "${A}" "${B}" "${C}")))
        (env (%hash "A" "1" "B" "2" "C" "3")))
    (let ((result (cl-claw.config.io:resolve-env-refs-in-value config env)))
      (is (equal '("1" "2" "3") (gethash "items" result))))))

(test env-substitution-escaped-placeholder
  "Handles escaped placeholders"
  (let ((config (%hash "key" "$${VAR}"))
        (env (%hash "VAR" "value")))
    (let ((result (cl-claw.config.io:resolve-env-refs-in-value config env)))
      (is (string= "${VAR}" (gethash "key" result))))))

(test env-substitution-mix-escaped-and-unescaped
  "Mix of escaped and unescaped vars"
  (let ((config (%hash "key" "${REAL}/$${LITERAL}"))
        (env (%hash "REAL" "resolved")))
    (let ((result (cl-claw.config.io:resolve-env-refs-in-value config env)))
      (is (string= "resolved/${LITERAL}" (gethash "key" result))))))

(test env-substitution-no-braces-unchanged
  "Leaves $VAR (no braces) unchanged"
  (let ((config (%hash "key" "$VAR"))
        (env (%hash "VAR" "value")))
    (let ((result (cl-claw.config.io:resolve-env-refs-in-value config env)))
      (is (string= "$VAR" (gethash "key" result))))))

(test env-substitution-lowercase-unchanged
  "Leaves lowercase placeholder unchanged"
  (let ((config (%hash "key" "${lowercase}"))
        (env (%hash "lowercase" "value")))
    (let ((result (cl-claw.config.io:resolve-env-refs-in-value config env)))
      (is (string= "${lowercase}" (gethash "key" result))))))
