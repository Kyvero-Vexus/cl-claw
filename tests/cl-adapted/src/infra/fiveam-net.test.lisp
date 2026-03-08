;;;; fiveam-net.test.lisp - FiveAM tests for net module

(defpackage :cl-claw.infra.net.test
  (:use :cl :fiveam))
(in-package :cl-claw.infra.net.test)

(def-suite net-suite
  :description "Tests for the net module (SSRF protection, fetch utilities)")
(in-suite net-suite)

;;; safe-private-ip-p tests

(test loopback-127-is-private
  "127.x.x.x addresses are private"
  (is-true (cl-claw.infra.net:safe-private-ip-p "127.0.0.1"))
  (is-true (cl-claw.infra.net:safe-private-ip-p "127.1.2.3")))

(test rfc1918-10-is-private
  "10.x.x.x range is private"
  (is-true (cl-claw.infra.net:safe-private-ip-p "10.0.0.1"))
  (is-true (cl-claw.infra.net:safe-private-ip-p "10.255.255.255")))

(test rfc1918-172-16-is-private
  "172.16-31.x.x range is private"
  (is-true (cl-claw.infra.net:safe-private-ip-p "172.16.0.1"))
  (is-true (cl-claw.infra.net:safe-private-ip-p "172.31.255.255")))

(test rfc1918-192-168-is-private
  "192.168.x.x range is private"
  (is-true (cl-claw.infra.net:safe-private-ip-p "192.168.1.1"))
  (is-true (cl-claw.infra.net:safe-private-ip-p "192.168.0.0")))

(test link-local-is-private
  "169.254.x.x link-local range is private"
  (is-true (cl-claw.infra.net:safe-private-ip-p "169.254.169.254"))
  (is-true (cl-claw.infra.net:safe-private-ip-p "169.254.0.1")))

(test public-ip-is-not-private
  "Public IP addresses are not private"
  (is-false (cl-claw.infra.net:safe-private-ip-p "8.8.8.8"))
  (is-false (cl-claw.infra.net:safe-private-ip-p "1.1.1.1"))
  (is-false (cl-claw.infra.net:safe-private-ip-p "203.0.113.1")))

;;; validate-url-not-ssrf tests

(test blocks-loopback-url
  "Blocks requests to loopback addresses"
  (handler-case
      (progn
        (cl-claw.infra.net:validate-url-not-ssrf "http://127.0.0.1/admin")
        (fail "Should have signaled SSRF error"))
    (cl-claw.infra.net:ssrf-error (e)
      (is (string= "http://127.0.0.1/admin" (cl-claw.infra.net:ssrf-error-url e))))))

(test blocks-localhost-hostname
  "Blocks requests to localhost"
  (handler-case
      (progn
        (cl-claw.infra.net:validate-url-not-ssrf "http://localhost/api")
        (fail "Should have signaled SSRF error"))
    (cl-claw.infra.net:ssrf-error () t)))

(test blocks-metadata-service
  "Blocks requests to cloud metadata service"
  (handler-case
      (progn
        (cl-claw.infra.net:validate-url-not-ssrf "http://169.254.169.254/latest/meta-data/")
        (fail "Should have signaled SSRF error"))
    (cl-claw.infra.net:ssrf-error () t)))

(test blocks-private-ip-range
  "Blocks requests to private IP ranges"
  (handler-case
      (progn
        (cl-claw.infra.net:validate-url-not-ssrf "http://192.168.1.1/")
        (fail "Should have signaled SSRF error"))
    (cl-claw.infra.net:ssrf-error () t)))

(test allows-public-https-url
  "Allows requests to public HTTPS URLs"
  (let ((result (cl-claw.infra.net:validate-url-not-ssrf "https://api.example.com/v1")))
    (is (string= "https://api.example.com/v1" result))))

(test allows-public-http-url
  "Allows requests to public HTTP URLs"
  (let ((result (cl-claw.infra.net:validate-url-not-ssrf "http://api.example.com/data")))
    (is (string= "http://api.example.com/data" result))))

(test blocks-non-http-protocol
  "Blocks non-HTTP(S) protocols"
  (handler-case
      (progn
        (cl-claw.infra.net:validate-url-not-ssrf "file:///etc/passwd")
        (fail "Should have signaled SSRF error"))
    (cl-claw.infra.net:ssrf-error () t))
  (handler-case
      (progn
        (cl-claw.infra.net:validate-url-not-ssrf "ftp://ftp.example.com/file")
        (fail "Should have signaled SSRF error"))
    (cl-claw.infra.net:ssrf-error () t)))

;;; fetch-options struct tests

(test creates-fetch-options
  "Creates fetch options with defaults"
  (let ((opts (cl-claw.infra.net:make-fetch-options :url "https://example.com")))
    (is (string= "https://example.com" (cl-claw.infra.net:fetch-options-url opts)))
    (is (string= "GET" (cl-claw.infra.net:fetch-options-method opts)))
    (is (= 30000 (cl-claw.infra.net:fetch-options-timeout-ms opts)))))

;;; fetch-response struct tests

(test creates-fetch-response
  "Creates fetch response struct"
  (let ((resp (cl-claw.infra.net:make-fetch-response :status 200 :body "ok")))
    (is (= 200 (cl-claw.infra.net:fetch-response-status resp)))
    (is (string= "ok" (cl-claw.infra.net:fetch-response-body resp)))))

;;; resolve-proxy-url tests

(test resolve-proxy-url-returns-nil-when-not-set
  "resolve-proxy-url returns NIL when no proxy is configured"
  ;; Pass empty env to avoid picking up real env vars
  (let ((proxy (cl-claw.infra.net:resolve-proxy-url :env '())))
    (is (null proxy))))

(test resolve-proxy-url-from-alist
  "resolve-proxy-url reads from env alist"
  (let ((proxy (cl-claw.infra.net:resolve-proxy-url
                :env '(("HTTPS_PROXY" . "http://proxy.example.com:8080")))))
    (is (string= "http://proxy.example.com:8080" proxy))))

;;; SSRF error condition tests

(test ssrf-error-has-url-and-reason
  "SSRF error condition exposes url and reason"
  (handler-case
      (cl-claw.infra.net:validate-url-not-ssrf "http://127.0.0.1/")
    (cl-claw.infra.net:ssrf-error (e)
      (is (not (null (cl-claw.infra.net:ssrf-error-url e))))
      (is (not (null (cl-claw.infra.net:ssrf-error-reason e)))))))
