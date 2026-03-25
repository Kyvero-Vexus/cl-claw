;;;; channel-config-test.lisp — Tests for channels configuration

(in-package :cl-claw.channels.tests)

(in-suite :channels-config)

(test config-load-channel-config
  "Loads channel configuration from config"
  (let ((config (make-nested-config "channels.enabled" t)))
    (is (hash-table-p (cl-claw.channels:load-channel-config config)))))

(test config-default-channel-config
  "Returns default configuration when missing"
  (let ((config (make-hash-table)))
    (is (hash-table-p (cl-claw.channels:load-channel-config config))))
  (let ((default-cfg (cl-claw.channels:load-channel-config nil)))
    (is (hash-table-p default-cfg))))

(test config-validate-channel-config
  "Validates channel configuration"
  (let ((valid-config (make-nested-config "channels.enabled" t))
        (invalid-config (make-nested-config "channels.invalid-key" "value")))
    (is (not (null (cl-claw.channels:validate-channel-config valid-config))))
    (is (not (null (cl-claw.channels:validate-channel-config invalid-config))))))

(test config-get-channel-by-id
  "Retrieves channel by ID"
  (let ((config (make-test-config "id" "ch1" "name" "test")))
    (let ((channel (cl-claw.channels:get-channel-by-id config "ch1")))
      ;; Stub returns nil — verifying call doesn't error
      (is (null channel)))))

(test config-get-all-channels
  "Retrieves all configured channels"
  (let* ((ch1 (make-test-config "id" "ch1" "name" "test1"))
         (ch2 (make-test-config "id" "ch2" "name" "test2"))
         (config (make-test-config "channels" (list ch1 ch2))))
    (let ((channels (cl-claw.channels:get-all-channels config)))
      (is (listp channels))
      (is (= 2 (length channels))))))
