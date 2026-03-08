(defpackage :cl-claw.infra.env.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.env.test)

(def-suite env-suite)
(in-suite env-suite)

(test is-truthy-env-value-accepts-common-truthy-values
  "Accepts common truthy values"
  (is-true (cl-claw.infra.env:is-truthy-env-value "1"))
  (is-true (cl-claw.infra.env:is-truthy-env-value "true"))
  (is-true (cl-claw.infra.env:is-truthy-env-value " yes "))
  (is-true (cl-claw.infra.env:is-truthy-env-value "ON")))

(test is-truthy-env-value-rejects-other-values
  "Rejects other values"
  (is-false (cl-claw.infra.env:is-truthy-env-value "0"))
  (is-false (cl-claw.infra.env:is-truthy-env-value "false"))
  (is-false (cl-claw.infra.env:is-truthy-env-value ""))
  (is-false (cl-claw.infra.env:is-truthy-env-value nil)))

(test normalize-zai-env-copies-when-missing
  "Copies Z_AI_API_KEY to ZAI_API_KEY when missing"
  ;; Set up test environment
  (setf (uiop:getenv "ZAI_API_KEY") "")
  (setf (uiop:getenv "Z_AI_API_KEY") "zai-legacy")
  (cl-claw.infra.env:normalize-zai-env)
  (is (string= (uiop:getenv "ZAI_API_KEY") "zai-legacy")))

(test normalize-zai-env-does-not-override-existing
  "Does not override existing ZAI_API_KEY"
  (setf (uiop:getenv "ZAI_API_KEY") "zai-current")
  (setf (uiop:getenv "Z_AI_API_KEY") "zai-legacy")
  (cl-claw.infra.env:normalize-zai-env)
  (is (string= (uiop:getenv "ZAI_API_KEY") "zai-current")))

(test normalize-zai-env-ignores-blank-legacy
  "Ignores blank legacy Z_AI_API_KEY values"
  (setf (uiop:getenv "ZAI_API_KEY") "")
  (setf (uiop:getenv "Z_AI_API_KEY") "   ")
  (cl-claw.infra.env:normalize-zai-env)
  (is (string= (uiop:getenv "ZAI_API_KEY") "")))
