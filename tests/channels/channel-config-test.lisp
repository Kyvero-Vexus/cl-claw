;;;; channel-config-test.lisp — Tests for channels configuration

(in-package :cl-claw.channels.tests)

(in-suite :channels-config)

(test config-load-channel-config
  "Loads channel configuration from config"
  (let* ((config (make-nested-config "channels.enabled" t))
    (is (hash-table-p (cl-claw.channels:load-channel-config config)))))

(test config-default-channel-config
  "Returns default configuration when missing"
  (let ((config (make-hash-table)))
    (is (hash-table-p (cl-claw.channels:load-channel-config config)))
    (let ((default (cl-claw.channels:load-channel-config nil)))
      (is (hash-table-p default))))

(test config-validate-channel-config
  "Validates channel configuration"
  (let* ((valid-config (make-nested-config "channels.enabled" t))
         (invalid-config (make-nested-config "channels.invalid-key" "value")))
    (is (not (null (cl-claw.channels:validate-channel-config valid-config)))
    (is (null (cl-claw.channels:validate-channel-config invalid-config))))

(test config-get-channel-by-id
  "Retrieves channel by ID"
  (let* ((config (make-nested-config "channels.list" (list (hash "id" "ch1" "name" "test")))))
    (let ((channel (cl-claw.channels:get-channel-by-id config "ch1")))
      (is (not (null channel))
      (is (string= "ch1" (gethash "id" channel))))))

(test config-get-all-channels
  "Retrieves all configured channels"
  (let* ((config (make-nested-config
                 "channels.list"
                 (list (hash "id" "ch1" "name" "test1")
                        (hash "id" "ch2" "name" "test2")))))
    (let ((channels (cl-claw.channels:get-all-channels config)))
      (is (listp channels))
      (is (= 2 (length channels))))))
