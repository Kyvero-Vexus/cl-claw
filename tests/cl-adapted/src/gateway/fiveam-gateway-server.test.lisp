;;;; fiveam-gateway-server.test.lisp - Tests for gateway server core
;;;;
;;;; Tests IP normalization, rate limiting, authentication, and route dispatch.

(defpackage :cl-claw.gateway.server.test
  (:use :cl :fiveam)
  (:import-from :cl-claw.gateway.server
                :normalize-client-ip
                :loopback-ip-p
                :ipv4-mapped-ipv6-p
                :extract-ipv4-from-mapped
                :request-client-ip
                :make-rate-limiter
                :rate-limiter-check
                :rate-limiter-record-failure
                :rate-limiter-reset
                :rate-limiter-prune
                :rate-limiter-dispose
                :make-gateway-server-config
                :authenticate-request
                :auth-result-authenticated-p
                :auth-result-reason
                :auth-result-user
                :make-gateway-server
                :gateway-server
                :register-route
                :dispatch-request
                :make-route-handler
                :route-handler-handler
                :start-gateway-server
                :stop-gateway-server
                :gateway-server-running-p))

(in-package :cl-claw.gateway.server.test)

(def-suite gateway-server-suite
  :description "Gateway HTTP server tests")

(in-suite gateway-server-suite)

;;; ============================================================
;;; IP Address Utilities
;;; ============================================================

(test ip-normalization
  "Tests IP address normalization"
  ;; Empty/undefined -> unknown
  (is (string= "unknown" (normalize-client-ip "")))
  (is (string= "unknown" (normalize-client-ip "undefined")))
  ;; IPv4-mapped IPv6 -> IPv4
  (is (string= "192.168.1.1" (normalize-client-ip "::ffff:192.168.1.1")))
  (is (string= "10.0.0.1" (normalize-client-ip "::FFFF:10.0.0.1")))
  ;; Regular IPs unchanged
  (is (string= "192.168.1.1" (normalize-client-ip "192.168.1.1")))
  (is (string= "::1" (normalize-client-ip "::1"))))

(test loopback-detection
  "Tests loopback address detection"
  (is (loopback-ip-p "127.0.0.1"))
  (is (loopback-ip-p "127.0.0.2"))
  (is (loopback-ip-p "::1"))
  (is (not (loopback-ip-p "192.168.1.1")))
  (is (not (loopback-ip-p "10.0.0.1"))))

(test ipv4-mapped-detection
  "Tests IPv4-mapped IPv6 detection"
  (is (ipv4-mapped-ipv6-p "::ffff:192.168.1.1"))
  (is (ipv4-mapped-ipv6-p "::FFFF:10.0.0.1"))
  (is (not (ipv4-mapped-ipv6-p "192.168.1.1")))
  (is (not (ipv4-mapped-ipv6-p "::1"))))

(test ipv4-mapped-treats-same
  "Treats IPv4 and IPv4-mapped IPv6 as same client"
  (is (string= (normalize-client-ip "::ffff:10.0.0.1")
               (normalize-client-ip "10.0.0.1"))))

(test request-client-ip-extraction
  "Tests client IP extraction from headers"
  ;; From X-Forwarded-For
  (is (string= "1.2.3.4"
               (request-client-ip '(("x-forwarded-for" . "1.2.3.4, 5.6.7.8")
                                    ("remote-addr" . "10.0.0.1")))))
  ;; Fallback to remote-addr
  (is (string= "10.0.0.1"
               (request-client-ip '(("remote-addr" . "10.0.0.1")))))
  ;; X-Real-IP only when enabled
  (is (string= "unknown"
               (request-client-ip '(("x-real-ip" . "1.2.3.4")))))
  (is (string= "1.2.3.4"
               (request-client-ip '(("x-real-ip" . "1.2.3.4"))
                                  :use-x-real-ip t))))

;;; ============================================================
;;; Rate Limiter
;;; ============================================================

(test rate-limiter-allows-initial
  "Allows requests when no failures recorded"
  (let ((limiter (make-rate-limiter :max-attempts 3 :window-ms 60000 :lockout-ms 120000)))
    (is (rate-limiter-check limiter "1.2.3.4"))))

(test rate-limiter-tracks-failures
  "Decrements remaining count after each failure"
  (let ((limiter (make-rate-limiter :max-attempts 3 :window-ms 60000 :lockout-ms 120000)))
    (rate-limiter-record-failure limiter "1.2.3.4")
    (is (rate-limiter-check limiter "1.2.3.4"))
    (rate-limiter-record-failure limiter "1.2.3.4")
    (is (rate-limiter-check limiter "1.2.3.4"))
    (rate-limiter-record-failure limiter "1.2.3.4")
    ;; Should be locked after 3 failures
    (is (not (rate-limiter-check limiter "1.2.3.4")))))

(test rate-limiter-tracks-ips-independently
  "Tracks IPs independently"
  (let ((limiter (make-rate-limiter :max-attempts 2 :window-ms 60000 :lockout-ms 120000)))
    (rate-limiter-record-failure limiter "1.1.1.1")
    (rate-limiter-record-failure limiter "1.1.1.1")
    (is (not (rate-limiter-check limiter "1.1.1.1")))
    ;; Different IP still allowed
    (is (rate-limiter-check limiter "2.2.2.2"))))

(test rate-limiter-ipv4-mapped-same
  "Treats IPv4 and IPv4-mapped IPv6 as same client"
  (let ((limiter (make-rate-limiter :max-attempts 2 :window-ms 60000 :lockout-ms 120000)))
    (rate-limiter-record-failure limiter "::ffff:1.2.3.4")
    (rate-limiter-record-failure limiter "1.2.3.4")
    (is (not (rate-limiter-check limiter "1.2.3.4")))
    (is (not (rate-limiter-check limiter "::ffff:1.2.3.4")))))

(test rate-limiter-exempts-loopback
  "Exempts loopback addresses by default"
  (let ((limiter (make-rate-limiter :max-attempts 1 :window-ms 60000 :lockout-ms 120000
                                    :exempt-loopback t)))
    (rate-limiter-record-failure limiter "127.0.0.1")
    ;; Still allowed because loopback is exempt
    (is (rate-limiter-check limiter "127.0.0.1"))))

(test rate-limiter-no-exempt-loopback
  "Rate-limits loopback when exempt-loopback is false"
  (let ((limiter (make-rate-limiter :max-attempts 1 :window-ms 60000 :lockout-ms 120000
                                    :exempt-loopback nil)))
    (rate-limiter-record-failure limiter "127.0.0.1")
    (is (not (rate-limiter-check limiter "127.0.0.1")))))

(test rate-limiter-tracks-scopes-independently
  "Tracks scopes independently for the same IP"
  (let ((limiter (make-rate-limiter :max-attempts 1 :window-ms 60000 :lockout-ms 120000
                                    :exempt-loopback nil)))
    (rate-limiter-record-failure limiter "1.1.1.1" :scope "token")
    (is (not (rate-limiter-check limiter "1.1.1.1" :scope "token")))
    ;; Different scope still allowed
    (is (rate-limiter-check limiter "1.1.1.1" :scope "password"))))

(test rate-limiter-dispose-clears
  "Dispose clears all entries"
  (let ((limiter (make-rate-limiter :max-attempts 1 :window-ms 60000 :lockout-ms 120000
                                    :exempt-loopback nil)))
    (rate-limiter-record-failure limiter "1.1.1.1")
    (is (not (rate-limiter-check limiter "1.1.1.1")))
    (rate-limiter-dispose limiter)
    (is (rate-limiter-check limiter "1.1.1.1"))))

(test rate-limiter-reset-scope
  "Reset only clears the requested scope for an IP"
  (let ((limiter (make-rate-limiter :max-attempts 1 :window-ms 60000 :lockout-ms 120000
                                    :exempt-loopback nil)))
    (rate-limiter-record-failure limiter "1.1.1.1" :scope "token")
    (rate-limiter-record-failure limiter "1.1.1.1" :scope "password")
    (rate-limiter-reset limiter "1.1.1.1" :scope "token")
    ;; Token scope cleared
    (is (rate-limiter-check limiter "1.1.1.1" :scope "token"))
    ;; Password scope still blocked
    (is (not (rate-limiter-check limiter "1.1.1.1" :scope "password")))))

(test rate-limiter-unknown-ip
  "Normalizes undefined IP to 'unknown'"
  (let ((limiter (make-rate-limiter :max-attempts 1 :window-ms 60000 :lockout-ms 120000
                                    :exempt-loopback nil)))
    (rate-limiter-record-failure limiter "")
    (is (not (rate-limiter-check limiter "undefined")))))

;;; ============================================================
;;; Authentication
;;; ============================================================

(test auth-mode-none
  "Allows explicit auth mode none"
  (let ((config (make-gateway-server-config :auth-mode :none)))
    (let ((result (authenticate-request config '())))
      (is (auth-result-authenticated-p result)))))

(test auth-mode-none-with-token
  "Keeps none mode authoritative even when token is present"
  (let ((config (make-gateway-server-config :auth-mode :none :auth-token "secret")))
    (let ((result (authenticate-request config '())))
      (is (auth-result-authenticated-p result)))))

(test auth-token-valid
  "Accepts valid token"
  (let ((config (make-gateway-server-config :auth-mode :token :auth-token "my-secret")))
    (let ((result (authenticate-request config
                    '(("authorization" . "Bearer my-secret")))))
      (is (auth-result-authenticated-p result)))))

(test auth-token-mismatch
  "Reports mismatched token"
  (let ((config (make-gateway-server-config :auth-mode :token :auth-token "correct")))
    (let ((result (authenticate-request config
                    '(("authorization" . "Bearer wrong")))))
      (is (not (auth-result-authenticated-p result)))
      (is (string= "token-mismatch" (auth-result-reason result))))))

(test auth-token-missing
  "Reports missing token"
  (let ((config (make-gateway-server-config :auth-mode :token :auth-token "secret")))
    (let ((result (authenticate-request config '())))
      (is (not (auth-result-authenticated-p result)))
      (is (string= "missing-token" (auth-result-reason result))))))

(test auth-token-missing-config
  "Reports missing token config"
  (let ((config (make-gateway-server-config :auth-mode :token :auth-token nil)))
    (let ((result (authenticate-request config
                    '(("authorization" . "Bearer something")))))
      (is (not (auth-result-authenticated-p result)))
      (is (string= "missing-token-config" (auth-result-reason result))))))

(test auth-password-valid
  "Accepts valid password"
  (let ((config (make-gateway-server-config :auth-mode :password :auth-password "pass123")))
    (let ((result (authenticate-request config
                    '(("x-gateway-password" . "pass123")))))
      (is (auth-result-authenticated-p result)))))

(test auth-password-mismatch
  "Reports mismatched password"
  (let ((config (make-gateway-server-config :auth-mode :password :auth-password "correct")))
    (let ((result (authenticate-request config
                    '(("x-gateway-password" . "wrong")))))
      (is (not (auth-result-authenticated-p result)))
      (is (string= "password-mismatch" (auth-result-reason result))))))

(test auth-password-rate-limit-on-wrong
  "Records rate-limit failure for wrong token (brute-force attempt)"
  (let ((config (make-gateway-server-config :auth-mode :token :auth-token "correct"))
        (limiter (make-rate-limiter :max-attempts 2 :window-ms 60000 :lockout-ms 120000
                                    :exempt-loopback nil)))
    ;; Two wrong attempts
    (authenticate-request config '(("authorization" . "Bearer wrong"))
                          :rate-limiter limiter :client-ip "1.1.1.1")
    (authenticate-request config '(("authorization" . "Bearer wrong"))
                          :rate-limiter limiter :client-ip "1.1.1.1")
    ;; IP should be rate-limited now
    (is (not (rate-limiter-check limiter "1.1.1.1" :scope "token")))))

(test auth-no-rate-limit-for-missing-token
  "Does not record rate-limit failure for missing token"
  (let ((config (make-gateway-server-config :auth-mode :token :auth-token "correct"))
        (limiter (make-rate-limiter :max-attempts 1 :window-ms 60000 :lockout-ms 120000
                                    :exempt-loopback nil)))
    ;; Missing token
    (authenticate-request config '() :rate-limiter limiter :client-ip "1.1.1.1")
    ;; IP should still be allowed (missing token != brute force)
    (is (rate-limiter-check limiter "1.1.1.1" :scope "token"))))

(test auth-trusted-proxy-valid
  "Accepts valid request from trusted proxy"
  (let ((config (make-gateway-server-config
                 :auth-mode :trusted-proxy
                 :trusted-proxies '("10.0.0.1"))))
    (let ((result (authenticate-request config
                    '(("x-forwarded-user" . "admin"))
                    :client-ip "10.0.0.1")))
      (is (auth-result-authenticated-p result))
      (is (string= "admin" (auth-result-user result))))))

(test auth-trusted-proxy-untrusted-source
  "Rejects request from untrusted source"
  (let ((config (make-gateway-server-config
                 :auth-mode :trusted-proxy
                 :trusted-proxies '("10.0.0.1"))))
    (let ((result (authenticate-request config
                    '(("x-forwarded-user" . "admin"))
                    :client-ip "5.5.5.5")))
      (is (not (auth-result-authenticated-p result)))
      (is (string= "untrusted-source" (auth-result-reason result))))))

(test auth-trusted-proxy-missing-user
  "Rejects request with missing user header"
  (let ((config (make-gateway-server-config
                 :auth-mode :trusted-proxy
                 :trusted-proxies '("10.0.0.1"))))
    (let ((result (authenticate-request config '()
                    :client-ip "10.0.0.1")))
      (is (not (auth-result-authenticated-p result)))
      (is (string= "missing-user-header" (auth-result-reason result))))))

(test auth-trusted-proxy-no-config
  "Rejects when no trusted proxies configured"
  (let ((config (make-gateway-server-config
                 :auth-mode :trusted-proxy
                 :trusted-proxies nil)))
    (let ((result (authenticate-request config
                    '(("x-forwarded-user" . "admin"))
                    :client-ip "10.0.0.1")))
      (is (not (auth-result-authenticated-p result)))
      (is (string= "no-trusted-proxies-configured" (auth-result-reason result))))))

(test auth-trusted-proxy-trims-whitespace
  "Trims whitespace from user header value"
  (let ((config (make-gateway-server-config
                 :auth-mode :trusted-proxy
                 :trusted-proxies '("10.0.0.1"))))
    (let ((result (authenticate-request config
                    '(("x-forwarded-user" . "  admin  "))
                    :client-ip "10.0.0.1")))
      (is (auth-result-authenticated-p result))
      (is (string= "admin" (auth-result-user result))))))

;;; ============================================================
;;; Route Dispatch
;;; ============================================================

(test route-dispatch-match
  "Dispatches matching route"
  (let ((server (make-gateway-server)))
    (register-route server
      (make-route-handler :method "GET" :path "/health"
                          :handler (lambda () "ok")))
    (let ((route (dispatch-request server "GET" "/health")))
      (is (not (null route)))
      (is (string= "ok" (funcall (route-handler-handler route)))))))

(test route-dispatch-no-match
  "Returns nil for unmatched route"
  (let ((server (make-gateway-server)))
    (is (null (dispatch-request server "GET" "/nonexistent")))))

(test route-dispatch-method-mismatch
  "Returns nil for wrong method"
  (let ((server (make-gateway-server)))
    (register-route server
      (make-route-handler :method "GET" :path "/health"
                          :handler (lambda () "ok")))
    (is (null (dispatch-request server "POST" "/health")))))

;;; ============================================================
;;; Server Lifecycle
;;; ============================================================

(test server-lifecycle
  "Server start/stop lifecycle"
  (let ((server (make-gateway-server)))
    (is (not (gateway-server-running-p server)))
    (start-gateway-server server)
    (is (gateway-server-running-p server))
    (stop-gateway-server server)
    (is (not (gateway-server-running-p server)))))

(test server-double-start-error
  "Errors on double start"
  (let ((server (make-gateway-server)))
    (start-gateway-server server)
    (signals error (start-gateway-server server))
    (stop-gateway-server server)))
