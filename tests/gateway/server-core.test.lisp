;;;; FiveAM tests for gateway server core operations

(in-package :cl-claw.gateway.tests)

(declaim (optimize (safety 3) (debug 3)))

(in-suite gateway-suite)

;; Tests for gateway server startup and lifecycle

(test gateway-server-startup
  "Gateway server starts correctly"
  ;; TODO: Implement when gateway server functions are available
  (skip "gateway server functions not yet available"))

(test gateway-server-shutdown
  "Gateway server shuts down cleanly"
  ;; TODO: Implement when gateway server functions are available
  (skip "gateway server functions not yet available"))

(test gateway-server-config-reload
  "Gateway server reloads config"
  ;; TODO: Implement when gateway server functions are available
  (skip "gateway server functions not yet available"))

(test gateway-server-restart-sentinel
  "Gateway server restart sentinel works"
  ;; TODO: Implement when gateway server functions are available
  (skip "gateway server functions not yet available"))

;; Tests for gateway session management

(test gateway-sessions-send
  "Gateway sends messages to sessions"
  ;; TODO: Implement when gateway session functions are available
  (skip "gateway session functions not yet available"))

(test gateway-sessions-canvas-auth
  "Gateway handles canvas auth"
  ;; TODO: Implement when gateway canvas auth functions are available
  (skip "gateway canvas auth functions not yet available"))

(test gateway-sessions-ios-client-id
  "Gateway handles iOS client ID"
  ;; TODO: Implement when gateway iOS client functions are available
  (skip "gateway iOS client functions not yet available"))

;; Tests for gateway tools

(test gateway-tools-catalog
  "Gateway provides tools catalog"
  ;; TODO: Implement when gateway tools catalog functions are available
  (skip "gateway tools catalog functions not yet available"))

(test gateway-tools-invoke-http
  "Gateway invokes HTTP tools"
  ;; TODO: Implement when gateway HTTP invoke functions are available
  (skip "gateway HTTP invoke functions not yet available"))
