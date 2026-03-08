;;;; FiveAM tests for providers domain

(defpackage :cl-claw.providers.test
  (:use :cl :fiveam))

(in-package :cl-claw.providers.test)

(declaim (optimize (safety 3) (debug 3)))

(def-suite providers-suite
  :description "Tests for provider fallback orchestration")

(in-suite providers-suite)

(test invoke-prefers-openai-by-default
  (let* ((registry (cl-claw.providers:make-default-provider-registry))
         (request (cl-claw.providers:make-provider-request :prompt "hello" :model "gpt-test"))
         (response (cl-claw.providers:invoke-with-fallback registry request)))
    (is-true (cl-claw.providers:provider-response-ok-p response))
    (is (string= "openai" (cl-claw.providers:provider-response-provider response)))
    (is (search "openai:" (cl-claw.providers:provider-response-text response)))))

(test invoke-falls-back-when-openai-fails
  (let* ((registry (cl-claw.providers:make-default-provider-registry))
         (request (cl-claw.providers:make-provider-request
                   :prompt "[fail:openai] continue"
                   :model "model-x"))
         (response (cl-claw.providers:invoke-with-fallback registry request)))
    (is-true (cl-claw.providers:provider-response-ok-p response))
    (is (string= "anthropic" (cl-claw.providers:provider-response-provider response)))))

(test preferred-provider-is-tried-first
  (let* ((registry (cl-claw.providers:make-default-provider-registry))
         (request (cl-claw.providers:make-provider-request :prompt "hello" :model "model-y"))
         (response (cl-claw.providers:invoke-with-fallback
                    registry request :preferred-provider "google")))
    (is-true (cl-claw.providers:provider-response-ok-p response))
    (is (string= "google" (cl-claw.providers:provider-response-provider response)))))

(test returns-error-when-all-providers-fail
  (let* ((registry (cl-claw.providers:make-default-provider-registry))
         (request (cl-claw.providers:make-provider-request
                   :prompt "[fail:openai] [fail:anthropic] [fail:google]"
                   :model "model-z"))
         (response (cl-claw.providers:invoke-with-fallback registry request)))
    (is-false (cl-claw.providers:provider-response-ok-p response))
    (is (string= "none" (cl-claw.providers:provider-response-provider response)))
    (is (not (null (cl-claw.providers:provider-response-error response))))))